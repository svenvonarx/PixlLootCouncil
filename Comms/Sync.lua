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

function Sync:SendSessionStart(sessionId, owner, items)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_start", { sessionId = sessionId, owner = owner, items = items }, ch)
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

function Sync:SendAward(sessionId, idx, winnerGuid)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("award", { sessionId = sessionId, idx = idx, winnerGuid = winnerGuid }, ch)
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

Protocol:RegisterHandler("session_start", function(data) PLC.Session:OnSessionStartReceived(data) end)
Protocol:RegisterHandler("item_add", function(data) PLC.Session:OnItemAddReceived(data) end)
Protocol:RegisterHandler("response", function(data) PLC.Session:OnResponseReceived(data) end)
Protocol:RegisterHandler("award", function(data) PLC.Session:OnAwardReceived(data) end)
Protocol:RegisterHandler("session_heartbeat", function(data) PLC.Session:OnHeartbeatReceived(data) end)
Protocol:RegisterHandler("session_end", function(data) PLC.Session:OnSessionEndReceived(data) end)
Protocol:RegisterHandler("session_force_end", function(data) PLC.Session:OnForceEndReceived(data) end)
Protocol:RegisterHandler("session_sync_request", function(data, sender) PLC.Session:OnSyncRequestReceived(data, sender) end)
Protocol:RegisterHandler("session_sync_data", function(data) PLC.Session:OnSyncDataReceived(data) end)
