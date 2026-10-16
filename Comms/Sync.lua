local ADDON_NAME, PLC = ...

-- Thin per-command senders over Comms/Protocol.lua, plus the receive-side dispatch table that
-- forwards straight into Data/Session.lua. Keeping every command's wire shape here (instead of
-- scattered across Session.lua) makes the full Phase 1 command set grep-able in one file.
local Protocol = PLC.Comms.Protocol
local Sync = {}
PLC.Comms.Sync = Sync

local function channel()
	return PLC.Loot.Announce:GetChannel()
end

function Sync:SendSessionStart(sessionId, owner, items, responseTimeoutSeconds, enchanterGuid)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_start", {
		sessionId = sessionId,
		owner = owner,
		items = items,
		responseTimeoutSeconds = responseTimeoutSeconds,
		enchanterGuid = enchanterGuid,
	}, ch)
end

function Sync:SendItemAdd(sessionId, items)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("item_add", { sessionId = sessionId, items = items }, ch)
end

function Sync:SendResponse(sessionId, idx, guid, response, note)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("response", { sessionId = sessionId, idx = idx, guid = guid, response = response, note = note }, ch)
end

function Sync:SendAward(sessionId, idx, winnerGuid, reason)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("award", { sessionId = sessionId, idx = idx, winnerGuid = winnerGuid, reason = reason }, ch)
end

function Sync:SendHeartbeat(sessionId)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_heartbeat", { sessionId = sessionId, ts = time() }, ch)
end

function Sync:SendSessionEnd(sessionId)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_end", { sessionId = sessionId }, ch)
end

function Sync:SendForceEnd(sessionId, byGuid)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_force_end", { sessionId = sessionId, byGuid = byGuid }, ch)
end

function Sync:SendSyncRequest(requesterGuid)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_sync_request", { requesterGuid = requesterGuid }, ch)
end

-- Unlike every other command, the sync reply goes to exactly one player (the requester), never
-- the whole group -- a full-state snapshot has no reason to be seen by anyone else.
function Sync:SendSyncData(snapshot, targetName)
	Protocol:Send("session_sync_data", snapshot, "WHISPER", targetName)
end

-- Not session-scoped (no sessionId) -- every client broadcasts this periodically regardless of
-- whether any loot session is running, see Data/Presence.lua.
function Sync:SendPresence(guid)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("presence", { guid = guid }, ch)
end

-- Not session-scoped either, but unlike presence it's only ever sent at specific moments (a
-- session starting, a late joiner catching up), never periodically -- see Data/Gear.lua.
function Sync:SendGear(guid, slots)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("gear", { guid = guid, slots = slots }, ch)
end

-- Same trigger points/reasoning as SendGear above -- see Data/Professions.lua.
function Sync:SendProfessions(guid, known)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("profession", { guid = guid, known = known }, ch)
end

-- Session-scoped (carries sessionId, unlike presence/gear/profession) since the Enchanter is a
-- per-session-lifecycle pick, not standing account data -- see Data/Session.lua:SetEnchanter.
function Sync:SendSetEnchanter(sessionId, guid)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("set_enchanter", { sessionId = sessionId, guid = guid }, ch)
end

-- Holder-only, sent once Loot/Trade.lua has actually confirmed (by re-checking its own bags, not
-- assumed) that an item left the holder's hands -- see Data/Session.lua:MarkItemTraded. Everyone
-- else trusts this broadcast rather than guessing from their own bags, since a recipient who
-- already owned a stack of the same item would be a false positive for that.
-- Not session-scoped: a history entry is permanent once written, and every client keeps its own
-- copy (RCLootCouncil's default sendHistory behavior) -- see Data/History.lua.
function Sync:SendHistory(name, entry)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("history", { name = name, entry = entry }, ch)
end

-- Holder-only: items taken back out of an active review pass (Remove / Remove All).
function Sync:SendItemRemove(sessionId, idxs)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("item_remove", { sessionId = sessionId, idxs = idxs }, ch)
end

function Sync:SendTradeComplete(sessionId, idx)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("trade_complete", { sessionId = sessionId, idx = idx }, ch)
end

Protocol:RegisterHandler("session_start", function(data) PLC.Session:OnSessionStartReceived(data) end)
Protocol:RegisterHandler("item_add", function(data) PLC.Session:OnItemAddReceived(data) end)
Protocol:RegisterHandler("item_remove", function(data) PLC.Session:OnItemRemoveReceived(data) end)
Protocol:RegisterHandler("response", function(data) PLC.Session:OnResponseReceived(data) end)
Protocol:RegisterHandler("award", function(data) PLC.Session:OnAwardReceived(data) end)
Protocol:RegisterHandler("session_heartbeat", function(data) PLC.Session:OnHeartbeatReceived(data) end)
Protocol:RegisterHandler("session_end", function(data) PLC.Session:OnSessionEndReceived(data) end)
Protocol:RegisterHandler("session_force_end", function(data) PLC.Session:OnForceEndReceived(data) end)
Protocol:RegisterHandler("session_sync_request", function(data, sender) PLC.Session:OnSyncRequestReceived(data, sender) end)
Protocol:RegisterHandler("session_sync_data", function(data) PLC.Session:OnSyncDataReceived(data) end)
Protocol:RegisterHandler("presence", function(data) PLC.Presence:OnPresenceReceived(data) end)
Protocol:RegisterHandler("gear", function(data) PLC.Gear:OnGearReceived(data) end)
Protocol:RegisterHandler("profession", function(data) PLC.Professions:OnProfessionReceived(data) end)
Protocol:RegisterHandler("set_enchanter", function(data) PLC.Session:OnEnchanterReceived(data) end)
Protocol:RegisterHandler("trade_complete", function(data) PLC.Session:OnTradeCompleteReceived(data) end)
Protocol:RegisterHandler("history", function(data) PLC.History:OnHistoryReceived(data) end)
