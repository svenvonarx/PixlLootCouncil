local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local LibWindow = LibStub("LibWindow-1.1")
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- The Loot Session window minimized: every item waiting to be reviewed, with its remaining 2-hour
-- trade time, so the master looter can keep raiding without losing track of what's in their bags.
-- Most urgent first; each row's background drains as its trade window runs out. Shows itself when
-- new loot comes in (for whoever holds the backlog, Session:CanManage) unless the full window is
-- open. Closing it only dismisses it until the next new item. Deliberately not in UISpecialFrames:
-- Escape shouldn't be able to clear this window by accident in the middle of a pull.
local LootTimersFrame = {}
PLC.UI.LootTimersFrame = LootTimersFrame

local frame
local dataTable
local countText
local emptyText
local statusText
local startButton
local tickerHandle
local hadRows = false -- the last render had rows; see render()
local seen = setmetatable({}, { __mode = "k" }) -- [session item] = true, already announced by showing

local ROW_HEIGHT = 26
local MAX_VISIBLE_ROWS = 8
local FOOTER_HEIGHT = 44
local CONTENT_GAP = 8

-- Sort order, most urgent first: on a timer, no time limit, too late.
local GROUP_TIMER, GROUP_NO_LIMIT, GROUP_EXPIRED = 1, 2, 3

-- Returns the sort group, status text and theme color name for a session item.
local function statusOf(item)
	local BagTracker = PLC.Loot.BagTracker
	local left = BagTracker:SecondsLeft(item)
	if left == 0 then
		return GROUP_EXPIRED, L["LOOTTIMERS_EXPIRED"], "warning"
	elseif left then
		return GROUP_TIMER, BagTracker.FormatShort(left), BagTracker.ColorFor(left)
	elseif item.boe then
		return GROUP_NO_LIMIT, L["TRADETIME_SHORT_BOE"], "dim"
	end
	return GROUP_NO_LIMIT, L["LOOTTIMERS_NO_TIMER"], "dim"
end

-- What's been picked up and not awarded yet: awarded items move to Loot Trades, and an item only
-- counts from the moment it's in the bags, since that's when its trade window starts.
local function buildRows()
	local BagTracker = PLC.Loot.BagTracker
	local rows = {}
	for idx, item in pairs(PLC.Session.items) do
		if not item.awarded and not item.lootSlot then
			table.insert(rows, {
				idx = idx,
				item = item,
				group = (statusOf(item)),
				left = BagTracker:SecondsLeft(item) or 0,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.group ~= b.group then
			return a.group < b.group
		end
		if a.left ~= b.left then
			return a.left < b.left
		end
		return a.idx < b.idx
	end)
	return rows
end

local COLUMNS = {
	{
		width = 28,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(22, 22)
			holder.texture = holder:CreateTexture(nil, "ARTWORK")
			holder.texture:SetAllPoints()
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			holder.texture:SetTexture(rowData.item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			holder.itemLink = rowData.item.link
		end,
	},
	{
		width = 166,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(162, 22)
			holder.text = Primitives.createText(holder, "", 11)
			holder.text:SetPoint("LEFT")
			holder.text:SetPoint("RIGHT")
			holder.text:SetJustifyH("LEFT")
			holder.text:SetWordWrap(false)
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			holder.text:SetText(rowData.item.link or "?")
			holder.itemLink = rowData.item.link
		end,
	},
	{
		width = 64,
		justify = "RIGHT",
		render = function(rowData)
			local _, text, colorName = statusOf(rowData.item)
			local r, g, b = Primitives.color(colorName)
			return text, r, g, b
		end,
	},
}

local function addTooltip(button, text)
	button:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(text)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function stopTicker()
	if tickerHandle then
		PLC:CancelTimer(tickerHandle)
		tickerHandle = nil
	end
end

local function ensureFrame()
	if frame then
		return frame
	end

	local rowContentWidth = 0
	for _, col in ipairs(COLUMNS) do
		rowContentWidth = rowContentWidth + col.width
	end

	frame = CreateFrame("Frame", "PixlLootCouncilLootTimersFrame", UIParent)
	Primitives.refreshFontsOnShow(frame)
	frame:SetSize(rowContentWidth + PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH + 20, 140)
	-- Below every other window here (History MEDIUM, Options HIGH, Session DIALOG, Loot
	-- FULLSCREEN_DIALOG, Trades TOOLTIP): it's meant to stay up during a raid, out of everything's way.
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(true)
	LibWindow.RegisterConfig(frame, PLC.db.profile.lootTimersWindow)
	LibWindow.RestorePosition(frame)
	LibWindow.MakeDraggable(frame)
	frame:SetScript("OnHide", stopTicker)

	frame.bg = Primitives.createTexture(frame, "BACKGROUND", "frame")
	frame.bg:SetAllPoints()
	frame.border = Primitives.createBorder(frame)

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()

	header.logo = Primitives.createLogo(header, 20)
	header.logo:SetPoint("LEFT", 10, 0)
	header.title = Primitives.createText(header, L["LOOTTIMERS_TITLE"], 18, "title")
	header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, -2)
	countText = Primitives.createText(header, "", 11, "dim")
	countText:SetPoint("BOTTOMLEFT", header.title, "BOTTOMRIGHT", 8, 1)

	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		frame:Hide()
	end)
	addTooltip(header.close, L["LOOTTIMERS_CLOSE_TIP"])

	header.expand = Primitives.createExpandButton(header, 20)
	header.expand:SetPoint("RIGHT", header.close, "LEFT", -2, 0)
	header.expand:SetScript("OnClick", function()
		PLC.UI.SessionFrame:Expand()
	end)
	addTooltip(header.expand, L["LOOTTIMERS_EXPAND_TIP"])

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -CONTENT_GAP)
	content:SetPoint("BOTTOMRIGHT", -10, FOOTER_HEIGHT)

	dataTable = DataTable.Create(content, ROW_HEIGHT)
	dataTable:SetColumns(COLUMNS)
	dataTable:SetRowTimerProvider(function(rowData)
		local BagTracker = PLC.Loot.BagTracker
		local left = BagTracker:SecondsLeft(rowData.item)
		if not left or left <= 0 then
			return nil
		end
		local r, g, b = Primitives.color(BagTracker.ColorFor(left))
		return left / BagTracker.TRADE_WINDOW_SECONDS, r, g, b, 0.16
	end)

	emptyText = Primitives.createText(content, L["LOOTTIMERS_EMPTY"], 11, "dim")
	emptyText:SetPoint("CENTER")

	startButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_START"], 130)
	startButton:SetPoint("BOTTOM", 0, 8)
	startButton:SetScript("OnClick", function()
		PLC.Session:Start()
		PLC.UI.SessionFrame:Expand()
	end)

	statusText = Primitives.createText(frame, L["LOOTTIMERS_SESSION_RUNNING"], 11, "dim")
	statusText:SetPoint("BOTTOM", 0, 16)

	frame:Hide()
	return frame
end

-- The window grows with the list, up to MAX_VISIBLE_ROWS; past that the list scrolls.
local function fitHeight(count)
	local visible = math.max(1, math.min(count, MAX_VISIBLE_ROWS))
	frame:SetHeight(Theme.LAYOUT.headerHeight + CONTENT_GAP + visible * ROW_HEIGHT + FOOTER_HEIGHT)
end

-- Hides the window once its last item is dealt with. An explicitly opened empty window stays up
-- (hadRows is false), so minimizing with nothing collected yet shows the empty message.
local function render(rows)
	local count = #rows
	if count == 0 and hadRows then
		hadRows = false
		frame:Hide()
		return
	end
	hadRows = count > 0

	fitHeight(count)
	dataTable:SetRows(rows)
	local countLabel = count > 0 and tostring(count) or ""
	countText:SetText(PLC.Session.preview and (countLabel .. "  " .. L["PREVIEW_LABEL"]) or countLabel)
	emptyText:SetShown(count == 0)

	local active = PLC.Session.state == "active"
	startButton:SetShown(not active and count > 0 and PLC.Session:CanStart())
	statusText:SetShown(active)
end

local function startTicker()
	if tickerHandle then
		return
	end
	tickerHandle = PLC:ScheduleRepeatingTimer(function()
		render(buildRows())
	end, 1)
end

function LootTimersFrame:HasItems()
	return #buildRows() > 0
end

function LootTimersFrame:IsShown()
	return frame ~= nil and frame:IsShown()
end

function LootTimersFrame:Show()
	ensureFrame()
	render(buildRows())
	frame:Show()
	startTicker()
end

function LootTimersFrame:Hide()
	if frame then
		frame:Hide()
	end
end

-- Called from Data/Session.lua's notifySessionFrame on every item or status change. Items seen for
-- the first time bring the window up, even after it was dismissed; expired leftovers never do.
function LootTimersFrame:OnSessionUpdated()
	local rows = buildRows()
	local hasNewLoot = false
	for _, row in ipairs(rows) do
		if not seen[row.item] then
			seen[row.item] = true
			hasNewLoot = hasNewLoot or row.group ~= GROUP_EXPIRED
		end
	end
	if hasNewLoot and PLC.Session:CanManage() and not PLC.UI.SessionFrame:IsShown() then
		self:Show()
	elseif self:IsShown() then
		render(rows)
	end
end

-- A reload shouldn't hide what's still in the bags. Waits for BagTracker's first scan (3s).
PLC:RegisterOnEnable(function()
	PLC:ScheduleTimer(function()
		LootTimersFrame:OnSessionUpdated()
	end, 4)
end)

PLC:RegisterSlashCommand("timers", L["SLASH_TIMERS"], function()
	if LootTimersFrame:IsShown() then
		LootTimersFrame:Hide()
	else
		LootTimersFrame:Show()
	end
end)
