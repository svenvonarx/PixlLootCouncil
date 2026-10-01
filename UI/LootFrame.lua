local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- Candidate-side response UI (header+content, no sidebar -- spec §4.3). One row per active
-- session item; each row's response buttons are built from db.profile.responses (NEED/GREED/PASS
-- + any custom entries), and swap to a "you voted: X" label once this player has responded to
-- that item -- disabling is per item (keyed by idx), never a single global lock.
local LootFrame = {}
PLC.UI.LootFrame = LootFrame

local frame
local dataTable

local function responseConfig(key)
	if not key then
		return nil
	end
	for _, resp in ipairs(PLC.db.profile.responses) do
		if resp.key == key then
			return resp
		end
	end
	return nil
end

local function myResponse(idx)
	local responses = PLC.Session.responses[idx]
	local guid = UnitGUID("player")
	return responses and responses[guid]
end

local function buildRows()
	local rows = {}
	for idx, item in pairs(PLC.Session.items) do
		table.insert(rows, { idx = idx, link = item.link })
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

local function ensureFrame()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "PixlLootCouncilLootFrame", UIParent)
	frame:SetSize(420, 260)
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
			width = 160,
			render = function(row)
				return row.link or "?"
			end,
		},
		{
			width = 240,
			isWidget = true,
			create = function(row)
				local container = CreateFrame("Frame", nil, row)
				container:SetSize(240, 28)
				container.buttons = {}
				for i, resp in ipairs(PLC.db.profile.responses) do
					local button = ButtonWidget.createButton(container, resp.text, 60)
					button:SetPoint("LEFT", (i - 1) * 64, 0)
					container.buttons[resp.key] = button
				end
				container.votedLabel = Primitives.createText(container, "", 11, "dim")
				container.votedLabel:SetPoint("LEFT")
				container.votedLabel:Hide()
				return container
			end,
			update = function(container, rowData)
				local mine = myResponse(rowData.idx)
				if mine then
					for _, button in pairs(container.buttons) do
						button:Hide()
					end
					local resp = responseConfig(mine.response)
					container.votedLabel:SetText(string.format(L["LOOTFRAME_VOTED"], (resp and resp.text) or mine.response))
					container.votedLabel:Show()
				else
					container.votedLabel:Hide()
					for key, button in pairs(container.buttons) do
						button:Show()
						button:SetScript("OnClick", function()
							PLC.Session:SendMyResponse(rowData.idx, key, nil)
						end)
					end
				end
			end,
		},
	})

	frame:Hide()
	return frame
end

-- Called (defensively) from Data/Session.lua whenever the item set or this player's own
-- responses change (session_start/item_add received, or SendMyResponse's own optimistic update).
function LootFrame:Refresh()
	if PLC.Session.state ~= "active" then
		if frame then
			frame:Hide()
		end
		return
	end
	local f = ensureFrame()
	dataTable:SetRows(buildRows())
	f:Show()
end

-- Manual reopen, in case the candidate closed it mid-session -- Refresh() only re-shows it
-- reactively, on an actual item/response change.
PLC:RegisterSlashCommand("lootframe", "Reopen the loot response window", function()
	LootFrame:Refresh()
end)
