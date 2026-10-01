local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- Header + content only, no sidebar -- single-purpose window (see docs/SPECIFICATION.md §4.3).
-- The Award button on each row calls PLC.Loot.Award:TryAward directly, finally retiring
-- Loot/Award.lua's temporary /plc award debug command.
local VotingFrame = {}
PLC.UI.VotingFrame = VotingFrame

local frame
local dataTable
local currentIdx
local rowsData = {}

local function classColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return c.r, c.g, c.b
	end
	return Primitives.color("text")
end

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

local function buildRows()
	local rows = {}
	if not currentIdx then
		return rows
	end
	local responses = PLC.Session.responses[currentIdx]
	for guid, entry in PLC.Roster:IterateGroup() do
		table.insert(rows, {
			guid = guid,
			name = entry.name,
			class = entry.class,
			role = entry.role,
			response = responses and responses[guid] and responses[guid].response,
		})
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

local function findRowIndexByGuid(guid)
	for i, row in ipairs(rowsData) do
		if row.guid == guid then
			return i
		end
	end
end

function VotingFrame:Award(guid)
	if not currentIdx then
		return
	end
	local item = PLC.Session.items[currentIdx]
	if not item or not item.lootSlot then
		print(L["CHAT_PREFIX"] .. L["VOTINGFRAME_NO_LOOT_SLOT"])
		return
	end
	PLC.Loot.Award:TryAward(item.lootSlot, guid, "council")
end

local function ensureFrame()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "PixlLootCouncilVotingFrame", UIParent)
	frame:SetSize(480, 360)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilVotingFrame")

	frame.bg = Primitives.createTexture(frame, "BACKGROUND", "frame")
	frame.bg:SetAllPoints()
	frame.border = Primitives.createBorder(frame)

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()

	header.title = Primitives.createText(header, L["VOTINGFRAME_TITLE"], 14, "title")
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
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

	dataTable = DataTable.Create(content)
	dataTable.scroll:SetAllPoints()

	dataTable:SetColumns({
		{
			width = 180,
			render = function(row)
				local r, g, b = classColor(row.class)
				return row.name, r, g, b
			end,
		},
		{
			width = 90,
			render = function(row)
				return row.role or "-"
			end,
		},
		{
			width = 110,
			render = function(row)
				local resp = responseConfig(row.response)
				if resp then
					return resp.text, resp.color.r, resp.color.g, resp.color.b
				end
				return "-"
			end,
		},
		{
			width = 80,
			isWidget = true,
			create = function(row)
				return ButtonWidget.createButton(row, L["VOTINGFRAME_AWARD"], 70)
			end,
			update = function(button, rowData)
				button:SetScript("OnClick", function()
					VotingFrame:Award(rowData.guid)
				end)
			end,
		},
	})

	frame:Hide()
	return frame
end

function VotingFrame:ShowItem(idx)
	currentIdx = idx
	local f = ensureFrame()
	rowsData = buildRows()
	dataTable:SetRows(rowsData)
	f:Show()
end

-- Session:notifyVotingFrame's target -- guid present means "just this one row changed"
-- (targeted RefreshRow, no full rebuild, per docs/SPECIFICATION.md §4.4); omitted means
-- "rebuild everything" (used for award changes, which can affect multiple rows at once).
function VotingFrame:OnItemUpdated(idx, guid)
	if not frame or not frame:IsShown() or idx ~= currentIdx then
		return
	end
	if not guid then
		rowsData = buildRows()
		dataTable:SetRows(rowsData)
		return
	end
	local rowIndex = findRowIndexByGuid(guid)
	if not rowIndex then
		rowsData = buildRows()
		dataTable:SetRows(rowsData)
		return
	end
	local responses = PLC.Session.responses[idx]
	rowsData[rowIndex].response = responses and responses[guid] and responses[guid].response
	dataTable:RefreshRow(rowIndex)
end

-- Temporary debug seed: fabricates one fake session item (no live loot slot, so the Award
-- button's CanGiveLoot call will correctly fail -- see VOTINGFRAME_NO_LOOT_SLOT) so the table's
-- layout/scroll/row-recycling can be exercised solo, without a real loot window open. See
-- docs/TESTING.md.
PLC:RegisterSlashCommand("testdata", "Debug: seed a fake session item and open VotingFrame", function()
	PLC.Session.items[1] = PLC.Session.items[1] or { idx = 1, lootSlot = nil, link = nil, quality = 4 }
	PLC.Session.responses[1] = PLC.Session.responses[1] or {}
	VotingFrame:ShowItem(1)
end)
