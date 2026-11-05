local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Sharing your own awards with everyone online: the guild, and the group if you're in one. For filling
-- the gaps when the awards' own broadcast didn't reach everyone, such as people who were offline, or
-- before 0.8.0, Award All messages that never left. Only awards the sender handed out themselves are
-- taken (each entry records who did, `owner`), so nobody can put entries into anyone else's history.
-- Entries a player already has are skipped, so sharing twice does no harm.
local History = PLC.History

local DEFAULT_DAYS = 7 -- what /plc share sends without a date
local DAY = 86400

-- History dates are the server's UTC date, "yyyy/mm/dd" (Data/History.lua:RecordAward).
local function dateOf(t)
	return date("!%Y/%m/%d", t)
end

local function isDate(text)
	return type(text) == "string" and text:match("^%d%d%d%d/%d%d/%d%d$") ~= nil
end

local function ownerIs(entry, fullName)
	return type(entry.owner) == "string" and History.NormalizeName(entry.owner) == fullName
end

-- This player's own awards in `db` (the whole history by default, or a filtered view of it, such as
-- History:GetFilteredDB), from fromDate to toDate (inclusive, either open): { { name, entry }, ... }.
function History:CollectOwnEntries(fromDate, toDate, db)
	local me = History.NormalizeName(UnitName("player"))
	local list = {}
	for name, entries in pairs(db or self:GetDB()) do
		if type(entries) == "table" then
			for _, entry in ipairs(entries) do
				local day = type(entry) == "table" and entry.date or ""
				if type(entry) == "table" and entry.id and ownerIs(entry, me)
					and (not fromDate or day >= fromDate) and (not toDate or day <= toDate) then
					table.insert(list, { name = name, entry = entry })
				end
			end
		end
	end
	return list
end

-- Sends them, at the lowest priority so a running session's messages go first. Says when it's done:
-- the server lets an addon send 1 message a second after the first 10, so a raid night takes a while.
-- Returns how many entries are on their way. db: see CollectOwnEntries.
function History:Share(fromDate, toDate, db)
	local entries = self:CollectOwnEntries(fromDate, toDate, db)
	if #entries == 0 then
		print(L["CHAT_PREFIX"] .. L["HISTORY_SHARE_NONE"])
		return 0
	end
	local channels = {}
	if IsInGuild() then
		table.insert(channels, "GUILD")
	end
	local group = PLC.Loot.Announce:GetChannel()
	if group then
		table.insert(channels, group)
	end
	if #channels == 0 then
		print(L["CHAT_PREFIX"] .. L["HISTORY_SHARE_NO_ONE"])
		return 0
	end
	print(L["CHAT_PREFIX"] .. string.format(L["HISTORY_SHARE_SENDING"], #entries))
	local left = #channels
	for _, channel in ipairs(channels) do
		PLC.Comms.Protocol:Send("history_share", { entries = entries }, channel, nil, "BULK", function()
			left = left - 1
			if left == 0 then
				print(L["CHAT_PREFIX"] .. string.format(L["HISTORY_SHARE_DONE"], #entries))
			end
		end)
	end
	return #entries
end

function History:OnHistoryShared(data, sender)
	if type(data) ~= "table" or type(data.entries) ~= "table" or type(sender) ~= "string" then
		return
	end
	local from = History.NormalizeName(sender)
	local idsByName, count = {}, 0
	for _, shared in ipairs(data.entries) do
		local entry = type(shared) == "table" and shared.entry
		if type(shared) == "table" and type(shared.name) == "string" and type(entry) == "table" and entry.id
			and entry.lootWon and ownerIs(entry, from) then
			local name = History.NormalizeName(shared.name)
			idsByName[name] = idsByName[name] or self:StoredIds(name)
			if self:InsertEntry(name, entry, idsByName[name]) then
				count = count + 1
			end
		end
	end
	if count > 0 then
		self:notifyFrame()
		print(L["CHAT_PREFIX"] .. string.format(L["HISTORY_SHARE_RECEIVED"], count, (strsplit("-", sender))))
	end
end

-- /plc share: the last DEFAULT_DAYS days. /plc share 2026/11/05: from that day on.
PLC:RegisterSlashCommand("share", L["SLASH_SHARE"], function(args)
	local text = strtrim(args or "")
	if text == "" then
		History:Share(dateOf(time() - DEFAULT_DAYS * DAY))
	elseif isDate(text) then
		History:Share(text)
	else
		print(L["CHAT_PREFIX"] .. L["HISTORY_SHARE_BAD_DATE"])
	end
end)

