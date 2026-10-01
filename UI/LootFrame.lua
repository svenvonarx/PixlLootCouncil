local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- Candidate-side response UI (header+content, no sidebar -- spec §4.3). One row per active
-- session item THIS PLAYER HASN'T RESPONDED TO YET -- once you vote, or the item's response
-- deadline passes, it simply stops being in buildRows() and vanishes from the table (matching
-- RCLootCouncil's behavior, per user feedback from the first live playtest -- no "you voted"
-- label to leave behind).
local LootFrame = {}
PLC.UI.LootFrame = LootFrame

local frame
local dataTable
local tickerHandle

local function myResponse(idx)
	local responses = PLC.Session.responses[idx]
	local guid = UnitGUID("player")
	return responses and responses[guid]
end

local function buildRows()
	local rows = {}
	local now = time()
	for idx, item in pairs(PLC.Session.items) do
		local expired = item.deadlineAt and now > item.deadlineAt
		if not myResponse(idx) and not expired then
			table.insert(rows, { idx = idx, link = item.link, icon = item.icon, deadlineAt = item.deadlineAt })
		end
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

-- Ticks once a second while the frame is visible so remaining-time text counts down and expired
-- rows disappear promptly, instead of only updating on the next vote/item-add event.
local function startTicker()
	if tickerHandle then
		return
	end
	tickerHandle = PLC:ScheduleRepeatingTimer(function()
		LootFrame:Refresh()
	end, 1)
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

	frame = CreateFrame("Frame", "PixlLootCouncilLootFrame", UIParent)
	frame:SetSize(560, 260)
	frame:SetPoint("CENTER", 0, -80)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilLootFrame")

	frame.bg = Primitives.createTexture(frame, "BACKGROUND", "frame")
	frame.bg:SetAllPoints()
	frame.border = Primitives.createBorder(frame)

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()

	header.title = Primitives.createText(header, L["LOOTFRAME_TITLE"], 14, "title")
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

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	dataTable = DataTable.Create(content, 32)
	dataTable.scroll:SetAllPoints()

	dataTable:SetColumns({
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
			width = 44,
			render = function(row)
				if not row.deadlineAt then
					return "-"
				end
				local remaining = math.max(0, math.ceil(row.deadlineAt - time()))
				if remaining <= 10 then
					return remaining .. "s", Primitives.color("warning")
				end
				return remaining .. "s"
			end,
		},
		{
			width = 300,
			isWidget = true,
			create = function(row)
				local container = CreateFrame("Frame", nil, row)
				container:SetSize(300, 28)
				container.buttons = {}
				local x = 0
				for i, resp in ipairs(PLC.db.profile.responses) do
					local button = ButtonWidget.createButton(container, resp.text, 50)
					button:SetPoint("LEFT", x, 0)
					x = x + 54
					container.buttons[resp.key] = button
				end
				container.noteBox = Primitives.createEditBox(container, 110, 22, L["LOOTFRAME_NOTE_PLACEHOLDER"])
				container.noteBox:SetPoint("LEFT", x + 10, 0)
				return container
			end,
			-- Only resets the note box when this row-pool slot gets rebound to a DIFFERENT item
			-- (container.idx changes) -- not on every refresh/tick for the same still-pending
			-- item, which would otherwise wipe out whatever the player is actively typing.
			update = function(container, rowData)
				if container.idx ~= rowData.idx then
					container.idx = rowData.idx
					container.noteBox:SetText(container.noteBox.placeholder)
					container.noteBox.showingPlaceholder = true
					local r, g, b = Primitives.color("dim")
					container.noteBox:SetTextColor(r, g, b)
				end
				for key, button in pairs(container.buttons) do
					button:SetScript("OnClick", function()
						local note = container.noteBox:GetValue()
						PLC.Session:SendMyResponse(rowData.idx, key, note ~= "" and note or nil)
					end)
				end
			end,
		},
	})

	frame:Hide()
	return frame
end

-- Called (defensively) from Data/Session.lua whenever the item set or this player's own
-- responses change (session_start/item_add received, SendMyResponse's own optimistic update),
-- and once a second while shown (see startTicker). Hides itself once there's nothing left to
-- respond to, rather than showing an empty window.
function LootFrame:Refresh()
	if PLC.Session.state ~= "active" then
		stopTicker()
		if frame then
			frame:Hide()
		end
		return
	end

	local rows = buildRows()
	if #rows == 0 then
		stopTicker()
		if frame then
			frame:Hide()
		end
		return
	end

	local f = ensureFrame()
	dataTable:SetRows(rows)
	f:Show()
	startTicker()
end

-- Manual reopen, in case the candidate closed it mid-session -- Refresh() only re-shows it
-- reactively, on an actual item/response/tick event.
PLC:RegisterSlashCommand("lootframe", "Reopen the loot response window", function()
	LootFrame:Refresh()
end)
