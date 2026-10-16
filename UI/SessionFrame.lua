local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- The single ML-facing window (header+content, no PanelLayout sidebar-nav -- spec §4.3, this is
-- a different kind of sidebar, see below): master-detail, RCLootCouncil-style -- a narrow
-- left-hand strip of item icons (status shown via border color + a tooltip, no room for inline
-- text at this width), click one to load its full candidate/response/Award/Pre-Award grid
-- (UI/VotingFrame.lua, embedded, not its own window) into the content area on the right.
--
-- Items accumulate in Data/Session.lua's PLC.Session.items from the moment they're silently
-- self-looted (Session:CollectDetectedItems), long before any review pass -- the icon list
-- always reflects that directly, not a separate pre-Start() "curation of the live loot window"
-- step (that step doesn't exist anymore under the bagged-item workflow: by the time anyone could
-- react to an item it's already bagged).
local SessionFrame = {}
PLC.UI.SessionFrame = SessionFrame

local frame
local content
local itemListContainer
local dataTable
local detailArea
local detailItemLabel
local detailRemoveButton
local detailContainer
local votingPanel
local startButton
local endButton
local awardAllButton
local selectedIdx -- which session item's response grid is currently shown in the detail area
local refresh -- forward-declared: onRemoveClick (defined before it) calls it

-- Single icon-only column -- status is shown via the icon's border color (no room for inline
-- text at sidebar width) plus a tooltip naming the item and its status on hover. Priority
-- Awarded > Pre-awarded > Expired > Pending -- the "visibly flagged" overview status (see
-- docs/SPECIFICATION.md's bagged-item workflow notes).
local ICON_SIZE = 30
local ICON_ROW_HEIGHT = 34
local ICON_SIDEBAR_WIDTH = 46

local ICON_COLUMNS = {
	{
		width = ICON_SIZE,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(ICON_SIZE, ICON_SIZE)
			holder.texture = holder:CreateTexture(nil, "ARTWORK")
			holder.texture:SetPoint("TOPLEFT", 1, -1)
			holder.texture:SetPoint("BOTTOMRIGHT", -1, 1)
			holder.border = Primitives.createBorder(holder)

			-- Tooltip handlers go on `row` itself (already mouse-enabled with its own OnMouseUp
			-- click handler, see UI/Widgets/DataTable.lua:getRow), not on `holder` -- a separate
			-- mouse-enabled child frame sitting almost exactly on top of the row (the icon fills
			-- nearly the entire narrow sidebar width) would otherwise swallow every click before
			-- it ever reached the row's own handler, which is exactly why the icons weren't
			-- properly clickable.
			row:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(holder.tooltipName or "?")
				if holder.tooltipStatus then
					GameTooltip:AddLine(holder.tooltipStatus, 1, 1, 1)
				end
				GameTooltip:Show()
			end)
			row:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)

			return holder
		end,
		update = function(holder, rowData)
			holder.texture:SetTexture(rowData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			holder.tooltipName = rowData.link or "?"

			local borderColor
			if rowData.awarded then
				local entry = PLC.Roster:Get(rowData.awarded)
				holder.tooltipStatus = string.format(L["SESSIONFRAME_AWARDED_TO"], (entry and entry.name) or "?")
				borderColor = "borderDim"
			elseif rowData.preAwardGuid then
				local entry = PLC.Roster:Get(rowData.preAwardGuid)
				holder.tooltipStatus = string.format(L["SESSIONFRAME_PREAWARDED_TO"], (entry and entry.name) or "?")
				borderColor = "accent"
			elseif rowData.deadlineAt and time() > rowData.deadlineAt then
				holder.tooltipStatus = L["SESSIONFRAME_EXPIRED"]
				borderColor = "warning"
			else
				holder.tooltipStatus = L["SESSIONFRAME_PENDING"]
				borderColor = "border"
			end
			Primitives.setBorderColor(holder.border, borderColor)
		end,
	},
}

local function itemRows()
	local rows = {}
	for idx, item in pairs(PLC.Session.items) do
		table.insert(rows, {
			idx = idx,
			link = item.link,
			icon = item.icon,
			awarded = item.awarded,
			preAwardGuid = item.preAwardGuid,
			deadlineAt = item.deadlineAt,
		})
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

local function firstPendingIdx(rows)
	for _, row in ipairs(rows) do
		if not row.awarded then
			return row.idx
		end
	end
	return nil
end

-- Session:RemoveItem already triggers notifySessionFrame -> OnSessionUpdated -> refresh() on
-- success, but stays silent on its (defensive, shouldn't-happen-given-the-button's-own-visibility-
-- rule) no-op paths -- the explicit refresh() call after this keeps selectedIdx consistent with
-- reality either way, not just in the success case.
local function onRemoveClick()
	if not selectedIdx then
		return
	end
	PLC.Session:RemoveItem(selectedIdx)
	selectedIdx = nil
	refresh()
end

local function showDetailFor(idx)
	selectedIdx = idx
	local item = idx and PLC.Session.items[idx]
	if item then
		detailItemLabel:SetText(item.link or "?")
		detailRemoveButton:SetShown(PLC.Session.state ~= "active" and not item.awarded)
		detailContainer:Show()
		votingPanel:ShowItem(idx)
	else
		detailItemLabel:SetText(L["SESSIONFRAME_NO_ITEMS"])
		detailRemoveButton:Hide()
		detailContainer:Hide()
	end
end

local function updateButtons()
	if PLC.Session.state == "active" then
		startButton:Hide()
		endButton:Show()
		awardAllButton:Show()
	else
		startButton:Show()
		endButton:Hide()
		awardAllButton:Hide()
	end
end

-- Rebuilds the icon list, keeps/advances the selection, and updates the bottom button row --
-- called whenever the frame is (re)shown, after Start()/End()/Award All/Remove, and from
-- Session's notifySessionFrame forward-hook whenever the item set or an award/pre-award changes
-- while this window is open. Assigns to the forward-declared local above (not `local function`
-- again here) since onRemoveClick, defined earlier in the file, already calls it.
function refresh()
	if not dataTable then
		return
	end

	local rows = itemRows()
	dataTable:SetRows(rows)

	-- Auto-selects the first not-yet-awarded item, and auto-advances off whatever was selected
	-- once it gets awarded -- never auto-advances AWAY from an item the user deliberately picked
	-- while it's still pending.
	if not selectedIdx or (PLC.Session.items[selectedIdx] and PLC.Session.items[selectedIdx].awarded) then
		selectedIdx = firstPendingIdx(rows)
	end

	local dataIndex
	for i, row in ipairs(rows) do
		if row.idx == selectedIdx then
			dataIndex = i
			break
		end
	end
	dataTable:SetSelectedIndex(dataIndex)
	showDetailFor(selectedIdx)

	updateButtons()
end

local function onStartClick()
	PLC.Session:Start()
	refresh()
end

local function onEndClick()
	PLC.Session:End()
	refresh()
end

local function onAwardAllClick()
	PLC.Session:AwardAllPreAwarded()
	refresh()
end

local function ensureFrame()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "PixlLootCouncilSessionFrame", UIParent)
	frame:SetSize(640, 500)
	frame:SetPoint("CENTER", 0, 50)
	-- Deliberately stays at "DIALOG" -- UI/LootFrame.lua sits one strata tier above this on
	-- purpose, so responding to loot is always reachable regardless of which window was
	-- clicked/opened more recently.
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilSessionFrame")
	Primitives.makeResizable(frame, 520, 360, 900, 800)

	frame.bg = Primitives.createTexture(frame, "BACKGROUND", "frame")
	frame.bg:SetAllPoints()
	frame.border = Primitives.createBorder(frame)

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()

	header.title = Primitives.createText(header, L["SESSIONFRAME_TITLE"], 14, "title")
	header.title:SetPoint("LEFT", 10, 0)

	header.close = CreateFrame("Button", nil, header)
	header.close:SetSize(20, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close.bg = Primitives.createTexture(header.close, "BACKGROUND", "button")
	header.close.bg:SetAllPoints()
	header.close.label = Primitives.createText(header.close, "x", 14, "warning")
	header.close.label:SetPoint("CENTER")
	header.close:SetScript("OnClick", function()
		frame:Hide()
	end)

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	startButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_START"], 160)
	startButton:SetPoint("BOTTOM", 0, 12)
	startButton:SetScript("OnClick", onStartClick)

	endButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_END"], 140)
	endButton:SetPoint("BOTTOM", 90, 12)
	endButton:SetScript("OnClick", onEndClick)

	awardAllButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_AWARDALL"], 140)
	awardAllButton:SetPoint("BOTTOM", -90, 12)
	awardAllButton:SetScript("OnClick", onAwardAllClick)

	-- Anchored to frame's actual corners, not a button's position -- see git history for why
	-- this matters (a prior version anchored to a centered button's TOPRIGHT and silently
	-- clipped everything past ~half the window's real width).
	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 50)

	itemListContainer = CreateFrame("Frame", nil, content)
	itemListContainer:SetPoint("TOPLEFT", content, "TOPLEFT")
	itemListContainer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT")
	itemListContainer:SetWidth(ICON_SIDEBAR_WIDTH)

	dataTable = DataTable.Create(itemListContainer, ICON_ROW_HEIGHT)
	-- Leaves room on the right for the scrollbar (createScrollFrame anchors it just past the
	-- scroll frame's own right edge) instead of letting it crowd right up against the divider.
	dataTable.scroll:SetPoint("TOPLEFT")
	dataTable.scroll:SetPoint("BOTTOMRIGHT", -14, 0)
	dataTable:SetColumns(ICON_COLUMNS)
	dataTable:SetRowClickHandler(function(rowData)
		showDetailFor(rowData.idx)
	end)

	local divider = Primitives.createTexture(content, "ARTWORK", "borderDim")
	divider:SetPoint("TOPLEFT", itemListContainer, "TOPRIGHT")
	divider:SetPoint("BOTTOMLEFT", itemListContainer, "BOTTOMRIGHT")
	divider:SetWidth(1)

	detailArea = CreateFrame("Frame", nil, content)
	detailArea:SetPoint("TOPLEFT", itemListContainer, "TOPRIGHT", 8, 0)
	detailArea:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")

	detailItemLabel = Primitives.createText(detailArea, "", 13, "white")
	detailItemLabel:SetPoint("TOPLEFT")
	detailItemLabel:SetPoint("RIGHT", detailArea, "RIGHT", -80, 0)
	detailItemLabel:SetJustifyH("LEFT")

	-- Only ever meaningful pre-Start()/post-End() for a not-yet-awarded item -- there's no wire
	-- command to retract an item once it's been broadcast (Session:RemoveItem enforces the same
	-- rule independently); showDetailFor keeps this hidden the rest of the time.
	detailRemoveButton = ButtonWidget.createButton(detailArea, L["SESSIONFRAME_REMOVE"], 70)
	detailRemoveButton:SetPoint("TOPRIGHT")
	detailRemoveButton:SetScript("OnClick", onRemoveClick)

	Primitives.createSeparator(detailArea, -28)

	detailContainer = CreateFrame("Frame", nil, detailArea)
	detailContainer:SetPoint("TOPLEFT", 0, -36)
	detailContainer:SetPoint("BOTTOMRIGHT")

	votingPanel = PLC.UI.VotingFrame.CreatePanel(detailContainer)

	frame:Hide()
	return frame
end

-- Forward-hook target from Data/Session.lua whenever the item set or an award/pre-award status
-- changes -- only does anything while this window is actually open, same guard style as every
-- other UI forward-hook in this codebase.
function SessionFrame:OnSessionUpdated()
	if not frame or not frame:IsShown() then
		return
	end
	refresh()
end

-- Manual open -- there's no automatic popup on loot anymore (collection is deliberately silent
-- across the whole raid, see Loot/Detection.lua); any council member, not just the live ML, can
-- use this to check progress or reach the controls for a session already running.
PLC:RegisterSlashCommand("sessionframe", "Open the loot session window", function()
	local f = ensureFrame()
	refresh()
	f:Show()
end)

-- Debug seed: adds a real item -- Hearthstone (itemID 6948), always cached client-side since
-- every character starts with one, so C_Item.GetItemInfo resolves it instantly -- via the same
-- Session:AddManualItem path /plc additem uses, so the layout's scrolling/selection/row-
-- recycling can be exercised solo with real resolved item data (name/icon/link), not a
-- hand-typed placeholder string. See docs/TESTING.md.
PLC:RegisterSlashCommand("testdata", "Debug: seed a real test item and open the session window", function()
	PLC.Session:AddManualItem(6948)

	local f = ensureFrame()
	refresh()
	f:Show()
end)
