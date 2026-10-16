local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Loot history, kept in the exact shape RCLootCouncil_Classic uses so its TSV export (and any
-- spreadsheet built on it) works unchanged. Mirrors, field for field:
--   entry builder  RCLootCouncil/ml_core.lua:1285-1343 (TrackAndLogLoot)
--   storage        RCLootCouncil/Modules/History/lootHistory.lua:159-193 (OnHistoryReceived)
--   TSV export     lootHistory.lua:1617-1662 (ExportTSV / ExportGoogleSheets)
-- Storage is PLC.lootDB.factionrealm[fullName] = { entry, ... } -- its own SavedVariables
-- (PixlLootCouncilLootDB), like RC's RCLootCouncilLootDB. The holder records each award and
-- broadcasts it; every client with the addon stores its own copy (RC's default sendHistory).
local History = {}
PLC.History = History

-- RC Classic's TBC override of LootHistory.wowheadBaseUrl (RCLootCouncil_Classic/Core/Hooks.lua).
local WOWHEAD_BASE_URL = "https://tbc.wowhead.com/item="
-- RC exports above this length in a single-line box to avoid freezing the client.
History.HUGE_EXPORT_LENGTH = 40000

local historyCounter = 0 -- RC's file-local counter for the "<serverTime>-<counter>" id

function History:GetDB()
	return PLC.lootDB.factionrealm
end

-- RC's Utils.Item patterns, verbatim (RCLootCouncil/Classes/Utils/Item.lua:36,47).
function History.GetItemStringFromLink(link)
	return strmatch(strmatch(link or "", "item:[%d:-]+") or "", "(item:.-):*$")
end

function History.GetItemIDFromLink(link)
	return tonumber(strmatch(link or "", "item:(%d+):?"))
end

-- RC keys history by full "Name-Realm" with the realm normalized (no spaces).
local function normalizeName(fullName)
	if not fullName then
		return nil
	end
	local name, realm = strsplit("-", fullName, 2)
	if not realm or realm == "" then
		realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
	end
	return name .. "-" .. realm:gsub("%s", "")
end
History.NormalizeName = normalizeName

local function serverTimeLocal()
	return (C_DateAndTime and C_DateAndTime.GetServerTimeLocal and C_DateAndTime.GetServerTimeLocal()) or time()
end

local function serverTime()
	return (GetServerTime and GetServerTime()) or time()
end

-- The winner's response, as RC stores it: display text, NUMERIC id (RC's response ids are button
-- indices) and color {r, g, b, a}. Returns nil when the winner never responded.
local function winnerResponse(idx, winnerGuid)
	local responses = PLC.Session.responses[idx]
	local r = responses and responses[winnerGuid]
	if not r or not r.response then
		return nil
	end
	for i, resp in ipairs(PLC.db.profile.responses) do
		if resp.key == r.response then
			return resp.text, i, { resp.color.r, resp.color.g, resp.color.b, 1 }, r.note
		end
	end
	return nil
end

-- Item links of what the winner currently has equipped in the slot(s) this item competes for --
-- RC's itemReplaced1/itemReplaced2.
local function itemsReplaced(winnerGuid, link)
	if not link then
		return nil, nil
	end
	local _, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(link)
	local slotIDs = equipLoc and PLC.Gear:SlotsForEquipLoc(winnerGuid, equipLoc)
	if not slotIDs then
		return nil, nil
	end
	local id1 = slotIDs[1] and PLC.Gear:GetEquipped(winnerGuid, slotIDs[1])
	local id2 = slotIDs[2] and PLC.Gear:GetEquipped(winnerGuid, slotIDs[2])
	return id1 and (select(2, C_Item.GetItemInfo(id1))), id2 and (select(2, C_Item.GetItemInfo(id2)))
end

local function insertEntry(name, entry)
	local db = History:GetDB()
	db[name] = db[name] or {}
	for _, existing in ipairs(db[name]) do
		if existing.id == entry.id then
			return false
		end
	end
	table.insert(db[name], entry)
	return true
end

-- Inserts unless an entry with the same id is already stored for that name. Returns true if added.
function History:InsertEntry(name, entry)
	return insertEntry(name, entry)
end

-- RC's DateTimeSort key: the epoch and counter encoded in the entry id ("<serverTime>-<counter>").
function History.EntryEpoch(entry)
	local t, c = strsplit("-", entry.id or "")
	return tonumber(t) or 0, tonumber(c) or 0
end

local function newestFirst(a, b)
	local ta, ca = History.EntryEpoch(a.entry)
	local tb, cb = History.EntryEpoch(b.entry)
	if ta ~= tb then
		return ta > tb
	end
	return ca > cb
end

function History:notifyFrame()
	if PLC.UI and PLC.UI.HistoryFrame and PLC.UI.HistoryFrame.OnHistoryUpdated then
		PLC.UI.HistoryFrame:OnHistoryUpdated()
	end
end

-- Called from Data/Session.lua:AwardBaggedItem (holder only).
function History:RecordAward(item, winnerGuid, reason)
	local winnerEntry = PLC.Roster:Get(winnerGuid)
	if not winnerEntry then
		return
	end

	local response, responseID, color, note = winnerResponse(item.idx, winnerGuid)
	local isAwardReason = false
	if reason == "disenchant" then
		-- RC's default award reason #1 is Disenchant (sort 401 -> responseID 401 - 400 = 1).
		response, responseID, color, isAwardReason = L["VOTINGFRAME_DISENCHANT"], 1, { 1, 1, 1, 1 }, true
	elseif not response then
		-- Holder awarded without the winner having responded.
		response, responseID, color, isAwardReason = L["VOTINGFRAME_AWARD"], 0, { 1, 1, 1, 1 }, true
	end

	local instance = item.instance and (item.difficultyName and item.difficultyName ~= ""
		and (item.instance .. "-" .. item.difficultyName) or item.instance) or _G.UNKNOWN

	local ownerEntry = PLC.Session.owner and PLC.Roster:Get(PLC.Session.owner.guid)
	local itemReplaced1, itemReplaced2 = itemsReplaced(winnerGuid, item.link)
	local t = serverTimeLocal()

	local entry = {
		lootWon = item.link,
		date = date("!%Y/%m/%d", t),
		time = date("!%H:%M:%S", t),
		instance = instance,
		boss = item.bossName or _G.UNKNOWN,
		-- RC's votes is the council vote count; this addon has no council voting step.
		votes = 0,
		itemReplaced1 = itemReplaced1,
		itemReplaced2 = itemReplaced2,
		response = response,
		responseID = responseID,
		color = color,
		class = winnerEntry.class,
		isAwardReason = isAwardReason,
		difficultyID = item.difficultyID,
		mapID = item.mapID,
		groupSize = item.groupSize,
		note = note,
		id = serverTime() .. "-" .. historyCounter,
		owner = normalizeName(ownerEntry and ownerEntry.name),
	}
	historyCounter = historyCounter + 1

	local name = normalizeName(winnerEntry.name)
	insertEntry(name, entry)
	PLC.Comms.Sync:SendHistory(name, entry)
	self:notifyFrame()
end

function History:OnHistoryReceived(data)
	if type(data) ~= "table" or not data.name or type(data.entry) ~= "table" or not data.entry.id then
		return
	end
	if insertEntry(data.name, data.entry) then
		self:notifyFrame()
	end
end

-- Local only, like RC's delete button.
function History:DeleteEntry(name, entry)
	local list = self:GetDB()[name]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == entry then
			table.remove(list, i)
			break
		end
	end
	if #list == 0 then
		self:GetDB()[name] = nil
	end
	self:notifyFrame()
end

-- RC's filter menu (lootHistory.lua FilterMenu/FilterFunc): a class multi-select where nothing
-- selected means every class, plus per-response toggles. Responses are keyed by their display text,
-- not RC's numeric responseID -- imported RC entries and this addon's own entries number their
-- responses differently, but the text is what both show. Persisted like RC's, in the profile.
local function filters()
	return PLC.db.profile.historyFilters
end

function History:ResponseKey(entry)
	return tostring(entry.response or "")
end

function History:IsFiltering()
	local f = filters()
	return next(f.class) ~= nil or next(f.hiddenResponses) ~= nil
end

function History:PassesFilters(entry)
	local f = filters()
	if next(f.class) and not f.class[entry.class or ""] then
		return false
	end
	return not f.hiddenResponses[self:ResponseKey(entry)]
end

-- RC's GetFilteredDB: { [name] = { entries } } limited to the selected date and/or name and the
-- active class/response filters. Both the window and the export go through this, like RC.
function History:GetFilteredDB(selectedDate, selectedName)
	local filtered = {}
	for name, entries in pairs(self:GetDB()) do
		if type(entries) == "table" and (not selectedName or name == selectedName) then
			for _, entry in ipairs(entries) do
				if (not selectedDate or entry.date == selectedDate) and self:PassesFilters(entry) then
					filtered[name] = filtered[name] or {}
					table.insert(filtered[name], entry)
				end
			end
		end
	end
	return filtered
end

-- One player's entries, newest first, as { entry = e } rows. Unfiltered -- the hover tooltips
-- answer "what has this player received", not "what does the history window currently show".
function History:GetPlayerEntries(fullName)
	local rows = {}
	local list = fullName and self:GetDB()[normalizeName(fullName)]
	if type(list) == "table" then
		for _, entry in ipairs(list) do
			table.insert(rows, { entry = entry })
		end
	end
	table.sort(rows, newestFirst)
	return rows
end

-- Everyone who has received this itemID, newest first, as { name = fullName, entry = e } rows.
function History:GetItemRecipients(itemID)
	local rows = {}
	if not itemID then
		return rows
	end
	for name, list in pairs(self:GetDB()) do
		if type(list) == "table" then
			for _, entry in ipairs(list) do
				if History.GetItemIDFromLink(entry.lootWon) == itemID then
					table.insert(rows, { name = name, entry = entry })
				end
			end
		end
	end
	table.sort(rows, newestFirst)
	return rows
end

local function hyperlink(link, delimiter)
	return table.concat({ "=HYPERLINK(\"", WOWHEAD_BASE_URL, tostring(History.GetItemIDFromLink(link) or 0),
		"\"", delimiter, "\"", tostring(link), "\")" })
end

-- RC's ExportTSV(formulaDelimiter), field for field. delimiter ";" = "TSV (Google Sheets &
-- English Excel)", "," = "TSV (International Excel)". Only deliberate difference: tabs/newlines in
-- the note are replaced with spaces (RC writes them raw, which breaks the row).
function History:ExportTSV(delimiter, filteredDB)
	local ret = { "player\tdate\ttime\titem\titemID\titemString\tresponse\tvotes\tclass\tinstance\tboss\tgear1\tgear2\tresponseID\tisAwardReason\trollType\tsubType\tequipLoc\tnote\towner\r\n" }
	local export = {}
	for player, entries in pairs(filteredDB) do
		for _, d in ipairs(entries) do
			local _, _, subType, equipLoc = C_Item.GetItemInfoInstant(d.lootWon)
			wipe(export)
			tinsert(export, tostring(player))
			tinsert(export, tostring(d.date))
			tinsert(export, tostring(d.time))
			tinsert(export, hyperlink(d.lootWon, delimiter))
			tinsert(export, tostring(History.GetItemIDFromLink(d.lootWon) or ""))
			tinsert(export, tostring(History.GetItemStringFromLink(d.lootWon) or ""))
			tinsert(export, tostring(d.response))
			tinsert(export, tostring(d.votes))
			tinsert(export, tostring(d.class))
			tinsert(export, tostring(d.instance))
			tinsert(export, tostring(d.boss))
			tinsert(export, d.itemReplaced1 and hyperlink(d.itemReplaced1, delimiter) or "")
			tinsert(export, d.itemReplaced2 and hyperlink(d.itemReplaced2, delimiter) or "")
			tinsert(export, tostring(d.responseID))
			tinsert(export, tostring(d.isAwardReason or false))
			tinsert(export, "normal")
			tinsert(export, tostring(subType))
			tinsert(export, tostring(equipLoc and _G[equipLoc] or ""))
			tinsert(export, (tostring(d.note or ""):gsub("[\t\r\n]", " ")))
			tinsert(export, tostring(d.owner or "Unknown"))
			tinsert(ret, table.concat(export, "\t"))
			tinsert(ret, "\r\n")
		end
	end
	return table.concat(ret)
end

-- One-time move of entries recorded last round into PLC.db.factionrealm, before the dedicated
-- lootDB existed. Only array-of-entries values (each with an id) are moved.
PLC:RegisterOnEnable(function()
	local old = PLC.db.factionrealm
	for name, entries in pairs(old) do
		if type(entries) == "table" and type(entries[1]) == "table" and entries[1].id and entries[1].lootWon then
			for _, entry in ipairs(entries) do
				insertEntry(normalizeName(name), entry)
			end
			old[name] = nil
		end
	end
end)
