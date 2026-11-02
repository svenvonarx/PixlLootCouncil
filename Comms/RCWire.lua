local ADDON_NAME, PLC = ...

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

PLC.Comms = PLC.Comms or {}
local RCWire = {}
PLC.Comms.RCWire = RCWire

-- RCLootCouncil's wire format (RCLootCouncil/Classes/Services/Comms.lua), so this addon can talk to
-- clients running RC without RC being installed here: Serialize(command, { args... }), deflated at
-- level 3, encoded for the addon channel. Data/RCBridge.lua and Data/HistoryImport.lua register for
-- the commands they care about.
--
-- RC reads every payload with unpack(data), which stops at the first nil: an argument list must
-- never have a hole, or the receiver gets nothing at all. Send false or 0 instead.
RCWire.MAIN = "RCLC"
RCWire.SYNC = "RCLCs"

local handlers = {} -- [prefix] = { [command] = fn(data, sender, distribution) }

function RCWire:IsRCRunning()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return isLoaded ~= nil and (isLoaded("RCLootCouncil_Classic") or isLoaded("RCLootCouncil")) and true or false
end

-- This player as RC names them: "Name-Realm", with the realm normalized.
function RCWire:GetFullName()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName():gsub("%s", "")
	return UnitName("player") .. "-" .. realm
end

function RCWire:Encode(command, ...)
	local serialized = AceSerializer:Serialize(command, { ... })
	return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(serialized, { level = 3 }))
end

-- Returns command, data, or nil for anything unreadable or meant for someone else.
function RCWire:Decode(message)
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
		if target ~= self:GetFullName() then
			return nil
		end
		command = table.remove(data, 1)
		if type(command) ~= "string" then
			return nil
		end
	end
	return command, data
end

-- target: "group", or a player to whisper.
function RCWire:Send(prefix, target, command, ...)
	local encoded = self:Encode(command, ...)
	if target == "group" then
		local channel = PLC.Loot.Announce:GetChannel()
		if channel then
			PLC:SendCommMessage(prefix, encoded, channel)
		end
	else
		PLC:SendCommMessage(prefix, encoded, "WHISPER", target)
	end
end

local function onComm(prefix, message, distribution, sender)
	if not sender then
		return
	end
	local command, data = RCWire:Decode(message)
	local handler = command and handlers[prefix] and handlers[prefix][command]
	if handler then
		handler(data, sender, distribution)
	end
end

-- Call from an OnEnable callback: AceComm registers the prefix.
function RCWire:Register(prefix, command, fn)
	if not handlers[prefix] then
		handlers[prefix] = {}
		PLC:RegisterComm(prefix, onComm)
	end
	handlers[prefix][command] = fn
end
