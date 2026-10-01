local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- The single ML-facing window (header+content, no sidebar -- spec §4.3). Reworked from two
-- separate windows (this + a standalone VotingFrame popup opened via a per-item Vote button)
-- into one, per the first live playtest's feedback: items shown as icons, with the response
-- grid visible in the SAME window (master-detail: click an item in the top list, its full
-- candidate/response/Award grid -- UI/VotingFrame.lua, now an embedded panel, not its own
-- window -- renders below it), not a second popup.
--
-- Curation only applies to the FIRST batch of a new session: once Session.state == "active",
-- later corpses' items auto-flow straight into the session via the existing Loot/Detection.lua
-- hook (real raid practice resolves each session's items before the next corpse anyway, and
-- re-litigating an already-broadcast item would need a wire command this addon doesn't have --
-- see Data/Session.lua's QueueDetectedItems). "Remove" here only ever acts on items that haven't
-- been queued/broadcast yet.
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
local removedSlots = {} -- [lootSlot] = true, curation-only, cleared on Start()
local selectedIdx -- which session item's response grid is currently shown below the list

local function iconColumn()
	return {
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
	}
end

local PENDING_COLUMNS = {
	iconColumn(),
	{
		width = 190,
		render = function(row)
			return row.link or "?"
		end,
	},
	{
		width = 50,
		isWidget = true,
		create = function(row)
			return ButtonWidget.createButton(row, L["SESSIONFRAME_REMOVE"], 44)
		end,
		update = function(button, rowData)
			button:SetScript("OnClick", function()
				removedSlots[rowData.slot] = true
				dataTable:SetRows(dataTable.pendingBuilder())
			end)
		end,
	},
}

local ACTIVE_COLUMNS = {
	iconColumn(),
	{
		width = 180,
		render = function(row)
			return row.link or "?"
		end,
	},
	{
		width = 70,
		render = function(row)
			if row.awarded then
				return L["SESSIONFRAME_AWARDED"]
			end
			if row.deadlineAt and time() > row.deadlineAt then
				return L["SESSIONFRAME_EXPIRED"], Primitives.color("warning")
			end
			return L["SESSIONFRAME_PENDING"]
		end,
	},
}

local function pendingRows()
	local rows = {}
	for slot, info in pairs(PLC.Loot.Detection.lootSlotInfo) do
		if not removedSlots[slot] and info.link then
			table.insert(rows, { slot = slot, link = info.link, icon = info.icon })
		end
	end
	table.sort(rows, function(a, b) return a.slot < b.slot end)
	return rows
end

local function activeRows()
	local rows = {}
	for idx, item in pairs(PLC.Session.items) do
		table.insert(rows, {
			idx = idx,
			link = item.link,
			icon = item.icon,
			awarded = item.awarded,
			deadlineAt = item.deadlineAt,
		})
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
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

local function firstPendingIdx(rows)
	for _, row in ipairs(rows) do
		if not row.awarded then
			return row.idx
		end
	end
	return nil
end

local function showActiveView()
	itemListContainer:ClearAllPoints()
	itemListContainer:SetPoint("TOPLEFT", content, "TOPLEFT")
	itemListContainer:SetPoint("TOPRIGHT", content, "TOPRIGHT")
	itemListContainer:SetHeight(140)

	dataTable:SetColumns(ACTIVE_COLUMNS)
	local rows = activeRows()
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
	dataTable:SetRowClickHandler(function(rowData)
		showDetailFor(rowData.idx)
	end)

	showDetailFor(selectedIdx)

	startButton:Hide()
	endButton:Show()
end

local function showPendingView()
	itemListContainer:ClearAllPoints()
	itemListContainer:SetPoint("TOPLEFT", content, "TOPLEFT")
	itemListContainer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")

	dataTable.pendingBuilder = pendingRows
	dataTable:SetRowClickHandler(nil)
	dataTable:SetColumns(PENDING_COLUMNS)
	dataTable:SetRows(pendingRows())

	detailLabel:Hide()
	detailContainer:Hide()

	startButton:Show()
	endButton:Hide()
end

-- Rebuilds whichever view matches the session's current state -- called whenever the frame is
-- (re)shown, after Start()/End() flip that state, and from Session's forward-hook whenever the
-- item set or an award changes while this window is open.
local function refresh()
	if not dataTable then
		return
	end
	if PLC.Session.state == "active" then
		showActiveView()
	else
		showPendingView()
	end
end

local function onStartClick()
	local filtered = {}
	for slot, info in pairs(PLC.Loot.Detection.lootSlotInfo) do
		if not removedSlots[slot] then
			filtered[slot] = info
		end
	end
	selectedIdx = nil
	PLC.Session:Start()
	PLC.Session:QueueDetectedItems(filtered)
	wipe(removedSlots)
	refresh()
end

local function onEndClick()
	PLC.Session:End()
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

	endButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_END"], 160)
	endButton:SetPoint("BOTTOM", 0, 12)
	endButton:SetScript("OnClick", onEndClick)

	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", startButton, "TOPRIGHT", -10, 10)

	itemListContainer = CreateFrame("Frame", nil, content)
	-- anchored per-view in showActiveView/showPendingView (fixed-height-at-top when a response
	-- grid is showing below it, full-height when it's the only thing in the window)

	dataTable = DataTable.Create(itemListContainer)
	dataTable.scroll:SetAllPoints()
	dataTable.pendingBuilder = pendingRows

	detailLabel = Primitives.createText(content, L["VOTINGFRAME_TITLE"], 12, "dim")
	detailLabel:SetPoint("TOPLEFT", itemListContainer, "BOTTOMLEFT", 0, -8)

	detailContainer = CreateFrame("Frame", nil, content)
	detailContainer:SetPoint("TOPLEFT", detailLabel, "BOTTOMLEFT", 0, -4)
	detailContainer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")

	votingPanel = PLC.UI.VotingFrame.CreatePanel(detailContainer)

	frame:Hide()
	return frame
end

-- Called (defensively) from Loot/Detection.lua:onLootReady whenever the local player is the live
-- Blizzard master looter. No-ops once a PixlLootCouncil session is already active -- see the
-- file banner comment above (curation only matters before Start()).
function SessionFrame:OnLootReady()
	if PLC.Session.state == "active" then
		return
	end
	local f = ensureFrame()
	refresh()
	f:Show()
end

-- Forward-hook target from Data/Session.lua whenever the item set or an award changes (new
-- items queued/received, an award confirmed/received) -- only does anything while this window
-- is actually open, same guard style as every other UI forward-hook in this codebase.
function SessionFrame:OnSessionUpdated()
	if not frame or not frame:IsShown() then
		return
	end
	refresh()
end

-- Manual open, mainly so any council member (not just the live ML) can monitor/reach the
-- End button for a session already running -- there's no automatic re-show for that, it's not
-- tied to a loot event.
PLC:RegisterSlashCommand("sessionframe", "Open the session curation/control window", function()
	local f = ensureFrame()
	refresh()
	f:Show()
end)

-- Temporary debug seed: fabricates one fake session item (no live loot slot, so the embedded
-- VotingFrame panel's Award button will correctly fail -- see VOTINGFRAME_NO_LOOT_SLOT) and
-- forces the active view, so the merged layout's scrolling/selection/row-recycling can be
-- exercised solo without a real session running. See docs/TESTING.md.
PLC:RegisterSlashCommand("testdata", "Debug: seed a fake session item and open the session window", function()
	if PLC.Session.state ~= "active" then
		PLC.Session.state = "active"
		PLC.Session.sessionId = PLC.Session.sessionId or "testdata"
		PLC.Session.owner = PLC.Session.owner or { guid = UnitGUID("player"), name = UnitName("player") }
	end
	PLC.Session.items[1] = PLC.Session.items[1] or {
		idx = 1,
		lootSlot = nil,
		link = "item:6948::::::::1:::::::",
		icon = "Interface\\Icons\\INV_Misc_Book_09",
		quality = 4,
		deadlineAt = time() + 300,
	}
	PLC.Session.responses[1] = PLC.Session.responses[1] or {}
	PLC.Session.nextIdx = math.max(PLC.Session.nextIdx, 2)

	local f = ensureFrame()
	refresh()
	f:Show()
end)
