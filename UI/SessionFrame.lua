local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- The single ML-facing window (header+content, no sidebar -- spec §4.3): master-detail, one
-- unified list. Items accumulate in Data/Session.lua's PLC.Session.items from the moment they're
-- silently self-looted (Session:CollectDetectedItems), long before any review pass -- this list
-- always reflects that directly, not a separate pre-Start() "curation of the live loot window"
-- step (that step doesn't exist anymore under the bagged-item workflow: by the time anyone could
-- react to an item it's already bagged). Click a row to select it; its full candidate/response/
-- Award/Pre-Award grid (UI/VotingFrame.lua, embedded, not its own window) renders below.
local SessionFrame = {}
PLC.UI.SessionFrame = SessionFrame

local frame
local content
local itemListContainer
local dataTable
local detailLabel
local detailContainer
local votingPanel
local startButton
local endButton
local awardAllButton
local selectedIdx -- which session item's response grid is currently shown below the list

local ITEM_COLUMNS = {
	{
		width = 28,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(24, 24)
			holder.texture = holder:CreateTexture(nil, "ARTWORK")
			holder.texture:SetAllPoints()
			return holder
		end,
		update = function(holder, rowData)
			holder.texture:SetTexture(rowData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		end,
	},
	{
		width = 170,
		render = function(row)
			return row.link or "?"
		end,
	},
	{
		-- Priority Awarded > Pre-awarded > Expired > Pending -- the "visibly flagged" overview
		-- status (see docs/SPECIFICATION.md's bagged-item workflow notes).
		width = 140,
		render = function(row)
			if row.awarded then
				local entry = PLC.Roster:Get(row.awarded)
				return string.format(L["SESSIONFRAME_AWARDED_TO"], (entry and entry.name) or "?")
			end
			if row.preAwardGuid then
				local entry = PLC.Roster:Get(row.preAwardGuid)
				return string.format(L["SESSIONFRAME_PREAWARDED_TO"], (entry and entry.name) or "?"), Primitives.color("accent")
			end
			if row.deadlineAt and time() > row.deadlineAt then
				return L["SESSIONFRAME_EXPIRED"], Primitives.color("warning")
			end
			return L["SESSIONFRAME_PENDING"]
		end,
	},
	{
		-- Only shown pre-Start()/post-End() for a not-yet-awarded item -- there's no wire command
		-- to retract an item once it's been broadcast, so removal has to stop being offered the
		-- moment that becomes possible (Session:RemoveItem enforces the same rule independently).
		width = 50,
		isWidget = true,
		create = function(row)
			return ButtonWidget.createButton(row, L["SESSIONFRAME_REMOVE"], 44)
		end,
		update = function(button, rowData)
			if PLC.Session.state ~= "active" and not rowData.awarded then
				button:Show()
				button:SetScript("OnClick", function()
					if selectedIdx == rowData.idx then
						selectedIdx = nil
					end
					PLC.Session:RemoveItem(rowData.idx)
				end)
			else
				button:Hide()
			end
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

local function showDetailFor(idx)
	selectedIdx = idx
	if selectedIdx then
		detailLabel:Show()
		detailContainer:Show()
		votingPanel:ShowItem(selectedIdx)
	else
		detailLabel:Hide()
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

-- Rebuilds the list, keeps/advances the selection, and updates the bottom button row -- called
-- whenever the frame is (re)shown, after Start()/End()/Award All, and from Session's
-- notifySessionFrame forward-hook whenever the item set or an award/pre-award changes while this
-- window is open.
local function refresh()
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
	frame:SetSize(520, 480)
	frame:SetPoint("CENTER", 0, 60)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilSessionFrame")

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
	itemListContainer:SetPoint("TOPRIGHT", content, "TOPRIGHT")
	itemListContainer:SetHeight(160)

	dataTable = DataTable.Create(itemListContainer)
	dataTable.scroll:SetAllPoints()
	dataTable:SetColumns(ITEM_COLUMNS)
	dataTable:SetRowClickHandler(function(rowData)
		showDetailFor(rowData.idx)
	end)

	detailLabel = Primitives.createText(content, L["VOTINGFRAME_TITLE"], 12, "dim")
	detailLabel:SetPoint("TOPLEFT", itemListContainer, "BOTTOMLEFT", 0, -8)

	detailContainer = CreateFrame("Frame", nil, content)
	detailContainer:SetPoint("TOPLEFT", detailLabel, "BOTTOMLEFT", 0, -4)
	detailContainer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")

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
