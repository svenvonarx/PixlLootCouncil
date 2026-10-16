local ADDON_NAME, PLC = ...

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Comms = PLC.Comms or {}
local Protocol = {}
PLC.Comms.Protocol = Protocol

-- Versioned envelope over AceComm. RCLootCouncil_Classic's own comms format has no version field
-- at all -- its "version check" only warns the user a client is outdated, it never gates parsing,
-- which is exactly why its MLDB minification table carries a documented, permanently-unfixable
-- duplicate-key bug (a shape change can never ship without silently corrupting older clients).
-- Every envelope here carries a "v" field; a receiver that doesn't understand it ignores the
-- message outright instead of attempting to parse an unknown shape (see
-- docs/SPECIFICATION.md §3 principle 6, §5.3).
local PREFIX = "PLC"
local PROTOCOL_VERSION = 1

local handlers = {} -- [cmd] = fn(data, senderName)
local warnedVersions = {} -- [tostring(v)] = true, dedupes the "unknown protocol version" print

function Protocol:RegisterHandler(cmd, fn)
	handlers[cmd] = fn
end

-- distribution: standard AceComm distribution strings ("RAID", "PARTY", "INSTANCE_CHAT",
-- "WHISPER", "GUILD"); target is only required for "WHISPER".
function Protocol:Send(cmd, data, distribution, target)
	local envelope = { v = PROTOCOL_VERSION, cmd = cmd, data = data }
	local serialized = AceSerializer:Serialize(envelope)
	local compressed = LibDeflate:CompressDeflate(serialized)
	local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
	PLC:SendCommMessage(PREFIX, encoded, distribution or "RAID", target)
end

local function onCommReceived(prefix, message, distribution, sender)
	if prefix ~= PREFIX then
		return
	end

	local decoded = LibDeflate:DecodeForWoWAddonChannel(message)
	if not decoded then
		return
	end
	local decompressed = LibDeflate:DecompressDeflate(decoded)
	if not decompressed then
		return
	end
	local ok, envelope = AceSerializer:Deserialize(decompressed)
	if not ok or type(envelope) ~= "table" or type(envelope.cmd) ~= "string" then
		return
	end

	if type(envelope.v) ~= "number" or envelope.v > PROTOCOL_VERSION then
		local key = tostring(envelope.v)
		if not warnedVersions[key] then
			warnedVersions[key] = true
			print(L["CHAT_PREFIX"] .. string.format(L["COMMS_UNKNOWN_VERSION"], key))
		end
		return
	end

	local handler = handlers[envelope.cmd]
	if handler then
		handler(envelope.data, sender)
	end
end

PLC:RegisterOnEnable(function()
	PLC:RegisterComm(PREFIX, onCommReceived)
end)
