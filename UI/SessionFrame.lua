local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- ML curation + Start/End control (header+content, no sidebar -- spec §4.3). Curation only
-- applies to the FIRST batch of a new session: once Session.state == "active", later corpses'
-- items auto-flow straight into the session via the existing Loot/Detection.lua hook (real raid
-- practice resolves each session's items before the next corpse anyway, and re-litigating an
-- already-broadcast item would need a wire command this addon doesn't have -- see
-- Data/Session.lua's QueueDetectedItems). "Remove" here only ever acts on items that haven't
-- been queued/broadcast yet.
local SessionFrame = {}
PLC.UI.SessionFrame = SessionFrame

local frame
local dataTable
local startButton
local endButton
local removedSlots = {} -- [lootSlot] = true, curation-only, cleared on Start()

local PENDING_COLUMNS = {
	{
		width = 240,
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
	{
		width = 180,
		render = function(row)
			return row.link or "?"
		end,
	},
	{
		width = 50,
		render = function(row)
			return row.awarded and L["SESSIONFRAME_AWARDED"] or L["SESSIONFRAME_PENDING"]
		end,
	},
	{
		width = 50,
		isWidget = true,
		create = function(row)
			return ButtonWidget.createButton(row, L["SESSIONFRAME_VOTE"], 44)
		end,
		update = function(button, rowData)
			button:SetScript("OnClick", function()
				PLC.UI.VotingFrame:ShowItem(rowData.idx)
			end)
		end,
	},
}

local function pendingRows()
	local rows = {}
	for slot, info in pairs(PLC.Loot.Detection.lootSlotInfo) do
		if not removedSlots[slot] and info.link then
			table.insert(rows, { slot = slot, link = info.link })
		end
	end
	table.sort(rows, function(a, b) return a.slot < b.slot end)
	return rows
end

local function activeRows()
	local rows = {}
	for idx, item in pairs(PLC.Session.items) do
		table.insert(rows, { idx = idx, link = item.link, awarded = item.awarded })
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

-- Rebuilds whichever view matches the session's current state -- called whenever the frame is
-- (re)shown, and after Start()/End() flip that state.
local function refresh()
	if not dataTable then
		return
	end
	if PLC.Session.state == "active" then
		dataTable.pendingBuilder = activeRows
		dataTable:SetColumns(ACTIVE_COLUMNS)
		dataTable:SetRows(activeRows())
		startButton:Hide()
		endButton:Show()
	else
		dataTable.pendingBuilder = pendingRows
		dataTable:SetColumns(PENDING_COLUMNS)
		dataTable:SetRows(pendingRows())
		startButton:Show()
		endButton:Hide()
	end
end

local function onStartClick()
	local filtered = {}
	for slot, info in pairs(PLC.Loot.Detection.lootSlotInfo) do
		if not removedSlots[slot] then
			filtered[slot] = info
		end
	end
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
	frame:SetSize(360, 320)
	frame:SetPoint("CENTER", 0, 120)
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

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", startButton, "TOPRIGHT", -10, 10)

	dataTable = DataTable.Create(content)
	dataTable.scroll:SetAllPoints()
	dataTable.pendingBuilder = pendingRows

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

-- Manual open, mainly so the holder can reach the End button once a session is already running
-- (there's no automatic re-show for that -- it's not tied to a loot event).
PLC:RegisterSlashCommand("sessionframe", "Open the session curation/control window", function()
	local f = ensureFrame()
	refresh()
	f:Show()
end)
