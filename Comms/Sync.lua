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

-- Award All's awards and history entries, collected into one "awards" message. The server lets each
-- addon prefix send 10 messages at once, then 1 a second, and AceComm splits anything over 255 bytes
-- into several: one award and its history entry took 3 messages, so a 20-item Award All queued 60
-- and took over a minute to leave, with the session's end behind them, and logging off in that time
-- lost all of it. Together they compress to a few messages and go out at once.
local batch -- { awards = {}, history = {} } between BeginBatch and FlushBatch

function Sync:BeginBatch()
	batch = { awards = {}, history = {} }
end

function Sync:FlushBatch(sessionId)
	local pending = batch
	batch = nil
	if not pending or (not next(pending.awards) and not next(pending.history)) then
		return
	end
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("awards", { sessionId = sessionId, awards = pending.awards, history = pending.history }, ch)
end

function Sync:SendSessionStart(sessionId, owner, items, responseTimeoutSeconds, enchanterGuid, council, responseSet, preview)
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
		council = council,
		responseSet = responseSet,
		preview = preview or nil,
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
	if batch then
		table.insert(batch.awards, { idx = idx, winnerGuid = winnerGuid, reason = reason })
		return
	end
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("award", { sessionId = sessionId, idx = idx, winnerGuid = winnerGuid, reason = reason }, ch)
end

-- Also a summary of the session (see Data/Session.lua:Fingerprint), so anyone who missed something
-- notices. `every` is how often it comes, so silence can be noticed too.
function Sync:SendHeartbeat(sessionId, items, responded, every)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_heartbeat", { sessionId = sessionId, ts = time(), items = items, responded = responded, every = every }, ch)
end

-- Every answer this player has given in the session, sent again: the holder was missing some.
function Sync:SendResponses(sessionId, guid, responses)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("responses", { sessionId = sessionId, guid = guid, responses = responses }, ch)
end

function Sync:SendSessionEnd(sessionId)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("session_end", { sessionId = sessionId }, ch)
end

-- Holder-only: a practice session is over, so everyone goes back to their real state (Data/Preview.lua).
function Sync:SendPreviewEnd(sessionId)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("preview_end", { sessionId = sessionId }, ch)
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
-- To one player, or the whole group when several asked at once (no targetName).
function Sync:SendSyncData(snapshot, targetName)
	if not targetName then
		local ch = channel()
		if ch then
			Protocol:Send("session_sync_data", snapshot, ch)
		end
		return
	end
	Protocol:Send("session_sync_data", snapshot, "WHISPER", targetName)
end

-- Not session-scoped (no sessionId) -- every client broadcasts this periodically regardless of
-- whether any loot session is running, see Data/Presence.lua.
function Sync:SendPresence(guid, version)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("presence", { guid = guid, version = version }, ch)
end

-- Everyone answers with a presence ping -- see Data/Presence.lua:CheckGroup.
-- A development copy has no version to send.
function Sync:SendVersionToGuild(version)
	if version and IsInGuild() then
		Protocol:Send("version", { version = version }, "GUILD")
	end
end

function Sync:SendVersionCheck()
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("version_check", {}, ch)
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
	if batch then
		table.insert(batch.history, { name = name, entry = entry })
		return
	end
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("history", { name = name, entry = entry }, ch)
end

-- Holder-only: the loot council for this session (list of GUIDs), whenever it changes.
function Sync:SendCouncil(sessionId, council)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("council", { sessionId = sessionId, council = council }, ch)
end

-- Holder-only: a staged (not yet committed) pick, so the council sees review progress.
function Sync:SendStage(sessionId, idx, guid, reason)
	local ch = channel()
	if not ch then
		return
	end
	Protocol:Send("stage", { sessionId = sessionId, idx = idx, guid = guid, reason = reason }, ch)
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
Protocol:RegisterHandler("council", function(data) PLC.Session:OnCouncilReceived(data) end)
Protocol:RegisterHandler("stage", function(data) PLC.Session:OnStageReceived(data) end)
Protocol:RegisterHandler("response", function(data) PLC.Session:OnResponseReceived(data) end)
Protocol:RegisterHandler("award", function(data) PLC.Session:OnAwardReceived(data) end)
Protocol:RegisterHandler("session_heartbeat", function(data) PLC.Session:OnHeartbeatReceived(data) end)
Protocol:RegisterHandler("session_end", function(data) PLC.Session:OnSessionEndReceived(data) end)
Protocol:RegisterHandler("responses", function(data) PLC.Session:OnResponsesReceived(data) end)
Protocol:RegisterHandler("version", function(data) PLC.Presence:NoteVersion(data.version) end)
Protocol:RegisterHandler("preview_end", function(data) PLC.Preview:OnPreviewEndReceived(data) end)
Protocol:RegisterHandler("session_force_end", function(data) PLC.Session:OnForceEndReceived(data) end)
Protocol:RegisterHandler("session_sync_request", function(data, sender) PLC.Session:OnSyncRequestReceived(data, sender) end)
Protocol:RegisterHandler("session_sync_data", function(data) PLC.Session:OnSyncDataReceived(data) end)
Protocol:RegisterHandler("presence", function(data) PLC.Presence:OnPresenceReceived(data) end)
Protocol:RegisterHandler("version_check", function() PLC.Presence:OnVersionCheckReceived() end)
Protocol:RegisterHandler("gear", function(data) PLC.Gear:OnGearReceived(data) end)
Protocol:RegisterHandler("profession", function(data) PLC.Professions:OnProfessionReceived(data) end)
Protocol:RegisterHandler("set_enchanter", function(data) PLC.Session:OnEnchanterReceived(data) end)
Protocol:RegisterHandler("trade_complete", function(data) PLC.Session:OnTradeCompleteReceived(data) end)
Protocol:RegisterHandler("history", function(data) PLC.History:OnHistoryReceived(data) end)
Protocol:RegisterHandler("history_share", function(data, sender) PLC.History:OnHistoryShared(data, sender) end)
Protocol:RegisterHandler("awards", function(data)
	if type(data) ~= "table" then
		return
	end
	for _, award in ipairs(type(data.awards) == "table" and data.awards or {}) do
		if type(award) == "table" then
			PLC.Session:OnAwardReceived({ sessionId = data.sessionId, idx = award.idx, winnerGuid = award.winnerGuid, reason = award.reason })
		end
	end
	for _, history in ipairs(type(data.history) == "table" and data.history or {}) do
		PLC.History:OnHistoryReceived(history)
	end
end)
