local ADDON_NAME, PLC = ...

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Getting RCLootCouncil's loot history into Data/History.lua. Since PLC stores entries in RC's
-- exact shape, every path is just "find RC's { [Name-Realm] = { entries } } table and insert":
--   1. RC's in-game sync (/rc sync -> "Loot History" -> pick this player). PLC answers RC's own
--      handshake on the RCLCs prefix (RCLootCouncil/Modules/Sync.lua), so the sender needs nothing
--      but stock RC -- the receiver doesn't need RC installed at all.
--   2. Live mirroring: an RC master looter broadcasts every award ("history" on the RCLC prefix,
--      RCLootCouncil/ml_core.lua:1335) to the group; PLC stores those as they happen.
--   3. Pasting RC's "Player Export" string (lootHistory.lua PlayerExport/ImportPlayerExport).
--   4. Reading RCLootCouncilLootDB directly when RC is installed on this character.
local History = PLC.History

local RC_PREFIX_MAIN = "RCLC"
local RC_PREFIX_SYNC = "RCLCs"

local pendingSync = {} -- [sender] = true once we've accepted their sync request

-- RC's date format changed in v3.15.4 from dd/mm/yy to yyyy/mm/dd; old entries are converted on
-- import exactly like RC's own checkDateFormatting (lootHistory.lua).
local function fixDate(entry)
	if type(entry.date) ~= "string" then
		return
	end
	local d, m, y = strsplit("/", entry.date, 3)
	if d and #d < 4 and m and y then
		entry.date = string.format("%04d/%02d/%02d", tonumber("20" .. y) or 0, tonumber(m) or 0, tonumber(d) or 0)
	end
end

-- data: RC's lootDB.factionrealm shape. Returns the number of entries actually added (entries
-- already present, matched by id, are skipped -- re-importing is always safe).
function History:ImportRCData(data)
	if type(data) ~= "table" then
		return 0
	end
	local count = 0
	for name, entries in pairs(data) do
		if type(name) == "string" and type(entries) == "table" then
			local fullName = History.NormalizeName(name)
			for _, entry in ipairs(entries) do
				if type(entry) == "table" and entry.lootWon then
					entry.SR = nil -- RC strips raw session responses before storing, too
					entry.sessionData = nil
					fixDate(entry)
					if not entry.id then
						-- Very old RC entries can lack an id; derive a stable one so re-imports dedupe.
						entry.id = "0-" .. tostring(entry.date) .. tostring(entry.time) .. tostring(entry.lootWon)
					end
					if self:InsertEntry(fullName, entry) then
						count = count + 1
					end
				end
			end
		end
	end
	if count > 0 then
		self:notifyFrame()
	end
	return count
end

local function reportImport(count)
	print(L["CHAT_PREFIX"] .. string.format(L["HISTORY_IMPORT_SUCCESS"], count))
end

-- RC's "Player Export" (and "Player Export (new)") string: AceSerializer output with every "|"
-- doubled so item links survive copy/paste.
function History:ImportPlayerExport(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text:sub(1, 2) ~= "^1" then
		print(L["CHAT_PREFIX"] .. L["HISTORY_IMPORT_BAD_FORMAT"])
		return nil
	end
	local ok, data = AceSerializer:Deserialize((text:gsub("||", "|")))
	if not ok or type(data) ~= "table" then
		print(L["CHAT_PREFIX"] .. L["HISTORY_IMPORT_BAD_FORMAT"])
		return nil
	end
	local count = self:ImportRCData(data)
	reportImport(count)
	return count
end

-- RC's own SavedVariables, available only when RC is installed and enabled on this character.
-- AceDB keys factionrealm by "<Faction> - <Realm>".
local function localRCData()
	local sv = _G.RCLootCouncilLootDB
	local key = (UnitFactionGroup("player") or "") .. " - " .. GetRealmName()
	return sv and type(sv.factionrealm) == "table" and sv.factionrealm[key] or nil
end

function History:HasLocalRCData()
	local data = localRCData()
	return data ~= nil and next(data) ~= nil
end

function History:ImportFromLocalRC()
	local data = localRCData()
	if not data then
		print(L["CHAT_PREFIX"] .. L["HISTORY_IMPORT_NO_RC"])
		return nil
	end
	-- Copy so stripping fields on import never touches RC's own saved data.
	local count = self:ImportRCData(CopyTable(data))
	reportImport(count)
	return count
end

----------------------------------------------------------------------------------------------------
-- RC wire format (RCLootCouncil/Classes/Services/Comms.lua): Serialize(command, { args... }),
-- deflated, encoded for the addon channel.
----------------------------------------------------------------------------------------------------

local function encodeRC(command, ...)
	local serialized = AceSerializer:Serialize(command, { ... })
	return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(serialized, { level = 3 }))
end

local function myFullName()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName():gsub("%s", "")
	return UnitName("player") .. "-" .. realm
end

local function decodeRC(message)
	local decoded = LibDeflate:DecodeForWoWAddonChannel(message)
	if not decoded then
		return nil
	end
	local decompressed = LibDeflate:DecompressDeflate(decoded)
	if not decompressed then
		return nil
	end
	local ok, command, data = AceSerializer:Deserialize(decompressed)
	if not ok or type(command) ~= "string" or type(data) ~= "table" then
		return nil
	end
	-- Cross-realm targets that can't be whispered get "xrealm" over the group channel, with the
	-- real target and command prepended to the args.
	if command == "xrealm" then
		local target = table.remove(data, 1)
		if target ~= myFullName() then
			return nil
		end
		command = table.remove(data, 1)
		if type(command) ~= "string" then
			return nil
		end
	end
	return command, data
end

local function sendRC(prefix, target, command, ...)
	PLC:SendCommMessage(prefix, encodeRC(command, ...), "WHISPER", target)
end

local function shortName(sender)
	return Ambiguate and Ambiguate(sender, "none") or (strsplit("-", sender))
end

----------------------------------------------------------------------------------------------------
-- 1. RC sync receiver (RCLootCouncil/Modules/Sync.lua): syncR -> (accept) syncAck -> sync data,
--    or syncNack with RC's own decline reason keys.
----------------------------------------------------------------------------------------------------

StaticPopupDialogs["PIXLLOOTCOUNCIL_RC_SYNC"] = {
	text = L["HISTORY_RC_SYNC_REQUEST"],
	button1 = ACCEPT,
	button2 = DECLINE,
	OnAccept = function(_, sender)
		pendingSync[sender] = true
		sendRC(RC_PREFIX_SYNC, sender, "syncAck", "history")
		print(L["CHAT_PREFIX"] .. string.format(L["HISTORY_RC_SYNC_RECEIVING"], shortName(sender)))
	end,
	OnCancel = function(_, sender)
		sendRC(RC_PREFIX_SYNC, sender, "syncNack", "history", "user_declined")
	end,
	timeout = 60,
	whileDead = true,
	hideOnEscape = true,
}

local function onRCSync(prefix, message, distribution, sender)
	if prefix ~= RC_PREFIX_SYNC or not sender then
		return
	end
	local command, data = decodeRC(message)
	if command == "syncR" then
		if data[1] == "history" then
			local dialog = StaticPopup_Show("PIXLLOOTCOUNCIL_RC_SYNC", shortName(sender))
			if dialog then
				dialog.data = sender
			end
		else
			-- RC's own "'player' can't receive 'type'" reason -- PLC only takes the loot history.
			sendRC(RC_PREFIX_SYNC, sender, "syncNack", data[1], "unsupported")
		end
	elseif command == "sync" then
		-- Only from someone whose request we explicitly accepted.
		if not pendingSync[sender] or data[1] ~= "history" then
			return
		end
		pendingSync[sender] = nil
		local count = History:ImportRCData(data[2])
		print(L["CHAT_PREFIX"] .. string.format(L["HISTORY_RC_SYNC_DONE"], count, shortName(sender)))
	end
end

----------------------------------------------------------------------------------------------------
-- 2. Live mirroring of an RC master looter's award broadcasts.
----------------------------------------------------------------------------------------------------

-- RC itself only accepts "history" from the master looter (or over GUILD, when the ML opted into
-- sending it there). The leader is accepted too, since RC Classic's ML is usually the leader and
-- the loot-method lookup can lag right after a change.
local function isLootAuthority(sender)
	local name = shortName(sender)
	if UnitIsGroupLeader and UnitIsGroupLeader(name) then
		return true
	end
	local getLootMethod = GetLootMethod or (C_PartyInfo and C_PartyInfo.GetLootMethod)
	if not getLootMethod then
		return false
	end
	local method, partyID, raidID = getLootMethod()
	if method ~= "master" then
		return false
	end
	local unit
	if raidID then
		unit = "raid" .. raidID
	elseif partyID == 0 then
		unit = "player"
	elseif partyID then
		unit = "party" .. partyID
	end
	return unit ~= nil and UnitIsUnit(unit, name)
end

local function onRCMain(prefix, message, distribution, sender)
	if prefix ~= RC_PREFIX_MAIN or not sender or not PLC.db.profile.historyMirrorRC then
		return
	end
	local command, data = decodeRC(message)
	if command == "history" then
		if distribution ~= "GUILD" and not isLootAuthority(sender) then
			return
		end
		local name, entry = data[1], data[2]
		if type(name) == "string" and type(entry) == "table" then
			History:ImportRCData({ [name] = { entry } })
		end
	elseif command == "delete_history" then
		if distribution ~= "GUILD" and not isLootAuthority(sender) then
			return
		end
		local id = data[1]
		if not id then
			return
		end
		for name, list in pairs(History:GetDB()) do
			if type(list) == "table" then
				for _, entry in ipairs(list) do
					if entry.id == id then
						History:DeleteEntry(name, entry)
						return
					end
				end
			end
		end
	end
end

local function isRCLoaded()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return isLoaded and isLoaded("RCLootCouncil_Classic") and true or false
end

PLC:RegisterOnEnable(function()
	-- With RC running here too, RC answers its own sync requests (two answers would confuse the
	-- sender); the user can then pull it in with "Import from RCLootCouncil" instead.
	if not isRCLoaded() then
		PLC:RegisterComm(RC_PREFIX_SYNC, onRCSync)
	end
	PLC:RegisterComm(RC_PREFIX_MAIN, onRCMain)
end)
