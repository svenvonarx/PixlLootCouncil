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

-- The server lets each addon prefix send 10 messages at once, then 1 a second, and AceComm splits
-- anything over 255 bytes into several. Big, unhurried data (a catch-up's whole session, shared
-- history, everyone's gear) goes on its own prefix, so it can never hold up what the raid is waiting
-- for: new items, answers, awards and the session's end. Before, a raid zoning out together queued
-- minutes of catch-up answers in front of all of that. Version and presence stay on PREFIX, which
-- older versions listen to, so they still hear about updates.
local BULK_PREFIX = "PLCB"
local BULK_COMMANDS = {
	session_sync_data = true,
	history_share = true,
	history = true,
	gear = true,
	profession = true,
}
Protocol.PREFIX, Protocol.BULK_PREFIX = PREFIX, BULK_PREFIX

-- Messages handed to AceComm that haven't fully gone out yet, per prefix: the master looter sees
-- them as "sending" (Protocol:Pending).
local pending = { [PREFIX] = 0, [BULK_PREFIX] = 0 }

local handlers = {} -- [cmd] = fn(data, senderName)
local warnedVersions = {} -- [tostring(v)] = true, dedupes the "unknown protocol version" print

function Protocol:RegisterHandler(cmd, fn)
	handlers[cmd] = fn
end

-- distribution: standard AceComm distribution strings ("RAID", "PARTY", "INSTANCE_CHAT",
-- "WHISPER", "GUILD"); target is only required for "WHISPER". prio: ChatThrottleLib's "BULK",
-- "NORMAL" or "ALERT"; by default ALERT for the session's own messages and BULK for big data.
-- onSent(): called once the whole message has gone out.
function Protocol:Send(cmd, data, distribution, target, prio, onSent)
	local envelope = { v = PROTOCOL_VERSION, cmd = cmd, data = data }
	local serialized = AceSerializer:Serialize(envelope)
	local compressed = LibDeflate:CompressDeflate(serialized)
	local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
	local bulk = BULK_COMMANDS[cmd]
	local prefix = bulk and BULK_PREFIX or PREFIX
	pending[prefix] = pending[prefix] + 1
	local done = false
	local function callback(_, sent, total)
		if not done and sent and total and sent >= total then
			done = true
			pending[prefix] = math.max(0, pending[prefix] - 1)
			if onSent then
				onSent()
			end
		end
	end
	PLC:SendCommMessage(prefix, encoded, distribution or "RAID", target, prio or (bulk and "BULK" or "ALERT"), callback)
end

-- How many messages are still on their way out: the session's own, and big data.
function Protocol:Pending()
	return pending[PREFIX], pending[BULK_PREFIX]
end

-- WoW echoes our own PARTY/RAID addon messages back to us. Every sender updates its local state
-- before sending, so the echo is never needed -- and processing it was actively harmful (e.g. the
-- holder's own item_add overwrote its local items with the stripped wire copy, and a late
-- session_start echo could reactivate a session the holder had already ended).
local function isSelf(sender)
	if not sender then
		return false
	end
	local name, realm = strsplit("-", sender, 2)
	if name ~= UnitName("player") then
		return false
	end
	if not realm or realm == "" then
		return true
	end
	local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName():gsub("[%s%-]", ""))
	return realm == myRealm
end

local function onCommReceived(prefix, message, distribution, sender)
	if (prefix ~= PREFIX and prefix ~= BULK_PREFIX) or isSelf(sender) then
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
	PLC:RegisterComm(BULK_PREFIX, onCommReceived)
end)
