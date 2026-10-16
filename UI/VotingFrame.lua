local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable

-- Embeddable response-grid panel, NOT its own top-level window -- UI/SessionFrame.lua mounts
-- this directly into its own content area as the "same window, all the answers" merged layout
-- (see docs/SPECIFICATION.md §4.3's single-purpose-window guidance -- this is no longer
-- single-purpose on its own, it's a component of SessionFrame).
--
-- Bagged-item workflow: by the time anyone's reviewing an item it's always already in the ML's
-- bags (Data/Session.lua:CollectDetectedItems self-loots everything at collection time), so
-- there's never a live loot slot left for Award to transfer through directly -- Award here means
-- "record who should get it, the holder trades it to them manually" (Session:AwardBaggedItem).
-- Pre-Award stages a choice (Session:SetPreAward) without committing, for Session:
-- AwardAllPreAwarded to commit in bulk later.
local VotingFrame = {}
PLC.UI.VotingFrame = VotingFrame

local Panel = {}
local PanelMeta = { __index = Panel }

local ROLE_ABBR = { TANK = "Tank", HEALER = "Heal", DAMAGER = "DPS" }

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

local function findRowIndexByGuid(rowsData, guid)
	for i, row in ipairs(rowsData) do
		if row.guid == guid then
			return i
		end
	end
end

function Panel:buildRows()
	local rows = {}
	if not self.currentIdx then
		return rows
	end
	local item = PLC.Session.items[self.currentIdx]
	local responses = PLC.Session.responses[self.currentIdx]
	for guid, entry in PLC.Roster:IterateGroup() do
		local r = responses and responses[guid]
		table.insert(rows, {
			guid = guid,
			name = entry.name,
			class = entry.class,
			role = entry.role,
			response = r and r.response,
			note = r and r.note,
			present = PLC.Presence:IsPresent(guid),
			staged = item ~= nil and item.preAwardGuid == guid,
		})
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

-- "N out of M have voted" (RCLootCouncil-style header, from the screenshot comparison) -- M is
-- everyone shown in the table (addon or not), N is actual recorded responses, regardless of
-- presence.
function Panel:updateHeader()
	local responded, total = 0, 0
	for _, row in ipairs(self.rowsData) do
		total = total + 1
		if row.response then
			responded = responded + 1
		end
	end
	self.header:SetText(string.format(L["VOTINGFRAME_VOTE_COUNT"], responded, total))
end

function Panel:Award(guid)
	if not self.currentIdx then
		return
	end
	PLC.Session:AwardBaggedItem(self.currentIdx, guid)
end

function Panel:PreAward(guid)
	if not self.currentIdx then
		return
	end
	PLC.Session:SetPreAward(self.currentIdx, guid)
end

function Panel:ShowItem(idx)
	self.currentIdx = idx
	self.rowsData = self:buildRows()
	self.dataTable:SetRows(self.rowsData)
	self:updateHeader()
end

-- Session:notifyVotingFrame's target (forwarded via VotingFrame:OnItemUpdated below). guid
-- present means "just this one row changed" (targeted RefreshRow, no full rebuild, per
-- docs/SPECIFICATION.md §4.4); omitted means "rebuild everything" (award/pre-award changes,
-- which can affect multiple rows at once -- e.g. staging a new pre-award un-stages the old one).
function Panel:OnItemUpdated(idx, guid)
	if idx ~= self.currentIdx then
		return
	end
	if not guid then
		self.rowsData = self:buildRows()
		self.dataTable:SetRows(self.rowsData)
		self:updateHeader()
		return
	end
	local rowIndex = findRowIndexByGuid(self.rowsData, guid)
	if not rowIndex then
		self.rowsData = self:buildRows()
		self.dataTable:SetRows(self.rowsData)
		self:updateHeader()
		return
	end
	local responses = PLC.Session.responses[idx]
	local r = responses and responses[guid]
	self.rowsData[rowIndex].response = r and r.response
	self.rowsData[rowIndex].note = r and r.note
	self.dataTable:RefreshRow(rowIndex)
	self:updateHeader()
end

-- Builds the "N of M voted" header + candidate/role/response/Award/Pre-Award grid into `parent`
-- and returns the panel object. Only one is ever actually live at a time in practice (the one
-- UI/SessionFrame.lua mounts), but nothing here assumes that -- VotingFrame.activePanel (set
-- below) is just "whichever panel Session's forward-hooks should talk to."
function VotingFrame.CreatePanel(parent)
	local header = Primitives.createText(parent, "", 11, "dim")
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")

	local tableContainer = CreateFrame("Frame", nil, parent)
	tableContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	tableContainer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")

	local dataTable = DataTable.Create(tableContainer, 32) -- taller than the 24px default: the
	-- Award buttons are 28px tall and would otherwise vertically overflow/clip against the next row
	dataTable.scroll:SetAllPoints()

	local self = setmetatable({
		header = header,
		dataTable = dataTable,
		currentIdx = nil,
		rowsData = {},
	}, PanelMeta)

	dataTable:SetColumns({
		{
			width = 150,
			render = function(row)
				local r, g, b = classColor(row.class)
				return row.name, r, g, b
			end,
		},
		{
			width = 50,
			render = function(row)
				return ROLE_ABBR[row.role] or "-"
			end,
		},
		{
			-- Three real states: already voted > present (addon confirmed, no vote yet) > not
			-- detected at all (see Data/Presence.lua) -- not just a bare "-" for every
			-- not-yet-voted case.
			width = 150,
			isWidget = true,
			create = function(row)
				local holder = CreateFrame("Frame", nil, row)
				holder:SetSize(150, 20)
				holder:EnableMouse(true)
				holder.text = Primitives.createText(holder, "", 11)
				holder.text:SetAllPoints()
				holder:SetScript("OnEnter", function(frame)
					if frame.note and frame.note ~= "" then
						GameTooltip:SetOwner(frame, "ANCHOR_TOP")
						GameTooltip:SetText(frame.note, nil, nil, nil, nil, true)
						GameTooltip:Show()
					end
				end)
				holder:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
				return holder
			end,
			update = function(holder, rowData)
				local resp = responseConfig(rowData.response)
				if resp then
					holder.text:SetText(resp.text)
					holder.text:SetTextColor(resp.color.r, resp.color.g, resp.color.b)
				elseif rowData.present then
					holder.text:SetText(L["VOTINGFRAME_WAITING"])
					local r, g, b = Primitives.color("dim")
					holder.text:SetTextColor(r, g, b)
				else
					holder.text:SetText(L["VOTINGFRAME_NO_ADDON"])
					local r, g, b = Primitives.color("warning")
					holder.text:SetTextColor(r, g, b)
				end
				holder.note = rowData.note
			end,
		},
		{
			width = 60,
			isWidget = true,
			create = function(row)
				return ButtonWidget.createButton(row, L["VOTINGFRAME_AWARD"], 54)
			end,
			update = function(button, rowData)
				button:SetScript("OnClick", function()
					self:Award(rowData.guid)
				end)
			end,
		},
		{
			width = 70,
			isWidget = true,
			create = function(row)
				return ButtonWidget.createButton(row, L["VOTINGFRAME_PREAWARD"], 64)
			end,
			update = function(button, rowData)
				if rowData.staged then
					button.label:SetText(L["VOTINGFRAME_STAGED"])
					local r, g, b = Primitives.color("accent")
					button.label:SetTextColor(r, g, b)
				else
					button.label:SetText(L["VOTINGFRAME_PREAWARD"])
					local r, g, b = Primitives.color("text")
					button.label:SetTextColor(r, g, b)
				end
				button:SetScript("OnClick", function()
					self:PreAward(rowData.guid)
				end)
			end,
		},
	})

	VotingFrame.activePanel = self
	return self
end

function VotingFrame:OnItemUpdated(idx, guid)
	if self.activePanel then
		self.activePanel:OnItemUpdated(idx, guid)
	end
end
