local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- A loot session's identity is sticky and location-independent (see docs/SPECIFICATION.md §5.1):
-- it is never reset by zoning, travel, or group reform -- there is simply no handler anywhere in
-- this file for any of those events. Only the holder's explicit Start/End, or another council
-- member's force-end after the holder's heartbeat goes stale, changes state. States:
-- "inactive" -> "active" -> "ended" | "force_ended".
local Session = {}
PLC.Session = Session

Session.state = "inactive"
Session.sessionId = nil
Session.owner = nil -- { guid, name }
Session.items = {} -- [idx] = { idx, lootSlot, itemString, boss, quality, link, awarded }
Session.responses = {} -- [idx][guid] = { response, note }
Session.lastHolderSeenAt = nil
Session.nextIdx = 1
Session.sentFirstBatch = false

local heartbeatTimerHandle

function Session:IsHolder()
	return self.state == "active" and self.owner ~= nil and self.owner.guid == UnitGUID("player")
end

-- Only the holder's own client writes char.activeSession (per spec §5.1, session state lives on
-- the holder's client, independent of comms); every other client just keeps the in-memory mirror
-- built from session_start/item_add/session_sync_data below.
local function persist()
	if not Session:IsHolder() then
		return
	end
	PLC.db.char.activeSession = {
		sessionId = Session.sessionId,
		owner = Session.owner,
		items = Session.items,
		responses = Session.responses,
		lastHolderSeenAt = Session.lastHolderSeenAt,
		nextIdx = Session.nextIdx,
	}
end

-- Strips everything that's only meaningful on the holder's own client (lootSlot -- a live
-- Blizzard loot-window index, not a stable identifier -- and the already-resolved display link)
-- before a batch crosses the wire. Mirrors the minimal-wire-shape approach that keeps
-- RCLootCouncil_Classic's per-item send to {typeCode, string, session, boss, owner}.
local function stripForTransmit(entries)
	local out = {}
	for idx, entry in pairs(entries) do
		out[idx] = { idx = entry.idx, itemString = entry.itemString, boss = entry.boss, quality = entry.quality }
	end
	return out
end

local function itemStringFromLink(link)
	return link and link:match("|H(.-)|h")
end

local function reconstructLink(itemString)
	if not itemString then
		return nil
	end
	local _, link = C_Item.GetItemInfo(itemString)
	return link
end

local function applyReceivedItems(items)
	for idx, entry in pairs(items) do
		entry.link = reconstructLink(entry.itemString)
		Session.items[idx] = entry
	end
end

local function startHeartbeat()
	if heartbeatTimerHandle then
		return
	end
	heartbeatTimerHandle = PLC:ScheduleRepeatingTimer(function()
		Session.lastHolderSeenAt = time()
		persist()
		PLC.Comms.Sync:SendHeartbeat(Session.sessionId)
	end, PLC.db.profile.sessionHeartbeatSeconds)
end

local function stopHeartbeat()
	if heartbeatTimerHandle then
		PLC:CancelTimer(heartbeatTimerHandle)
		heartbeatTimerHandle = nil
	end
end

-- Finds the most recently queued, not-yet-awarded item for a live Blizzard loot slot. Searched
-- from the end, matching the established search order in Loot/Award.lua:136 -- the item at this
-- lootSlot right now is always the most recent one queued for it, since an older item for the
-- same numeric slot (from an earlier, now-closed loot window) would already be resolved.
local function findItemBySlot(lootSlot)
	for idx = Session.nextIdx - 1, 1, -1 do
		local item = Session.items[idx]
		if item and item.lootSlot == lootSlot and not item.awarded then
			return item
		end
	end
end

-- Explicit holder action only -- there is no reactive "handle loot?" prompt (see
-- docs/SPECIFICATION.md §3 principle 9). Stage 3: temporary /plc session start debug command,
-- same pattern as Loot/Award.lua's /plc award. Removed once UI/SessionFrame.lua's real Start
-- button lands in Stage 5.
function Session:Start()
	if self.state == "active" then
		print(L["CHAT_PREFIX"] .. L["SESSION_ALREADY_ACTIVE"])
		return
	end
	self.sessionId = UnitGUID("player") .. "-" .. time()
	self.owner = { guid = UnitGUID("player"), name = UnitName("player") }
	self.state = "active"
	self.items = {}
	self.responses = {}
	self.nextIdx = 1
	self.sentFirstBatch = false
	self.lastHolderSeenAt = time()
	startHeartbeat()
	persist()
	print(L["CHAT_PREFIX"] .. L["SESSION_STARTED"])
end

-- Forward-hook target already called (defensively) from Loot/Detection.lua:66-68. No-ops unless
-- we're both the live Blizzard master looter (checked there) and the session holder (checked
-- here) -- those are deliberately separate concerns (spec §5.1).
function Session:QueueDetectedItems(lootSlotInfo)
	if not self:IsHolder() then
		return
	end

	local newItems = {}
	for lootSlot, info in pairs(lootSlotInfo) do
		local alreadyQueued = false
		for idx = 1, self.nextIdx - 1 do
			local existing = self.items[idx]
			if existing and existing.lootSlot == lootSlot and existing.link == info.link then
				alreadyQueued = true
				break
			end
		end
		if not alreadyQueued then
			local idx = self.nextIdx
			self.nextIdx = self.nextIdx + 1
			local entry = {
				idx = idx,
				lootSlot = lootSlot,
				itemString = itemStringFromLink(info.link),
				boss = info.boss,
				quality = info.quality,
				link = info.link,
			}
			self.items[idx] = entry
			newItems[idx] = entry
		end
	end

	if not next(newItems) then
		return
	end

	persist()

	if not self.sentFirstBatch then
		self.sentFirstBatch = true
		PLC.Comms.Sync:SendSessionStart(self.sessionId, self.owner, stripForTransmit(self.items))
	else
		PLC.Comms.Sync:SendItemAdd(self.sessionId, stripForTransmit(newItems))
	end
end

function Session:OnSessionStartReceived(data)
	if self:IsHolder() then
		return
	end
	self.sessionId = data.sessionId
	self.owner = data.owner
	self.state = "active"
	self.items = {}
	self.responses = {}
	self.lastHolderSeenAt = time()
	applyReceivedItems(data.items)
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_STARTED_BY"], data.owner and data.owner.name or "?"))
end

function Session:OnItemAddReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.lastHolderSeenAt = time()
	applyReceivedItems(data.items)
end

-- Broadcast to the whole group, not whispered to the holder -- every council member's client
-- computes the same council set locally from Data/Roster.lua, so every council member's own
-- (future) VotingFrame can stay in sync independently of the holder relaying anything.
function Session:SendMyResponse(idx, response, note)
	if self.state ~= "active" then
		return
	end
	local guid = UnitGUID("player")
	self.responses[idx] = self.responses[idx] or {}
	self.responses[idx][guid] = { response = response, note = note }
	PLC.Comms.Sync:SendResponse(self.sessionId, idx, guid, response, note)
end

function Session:OnResponseReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.responses[data.idx] = self.responses[data.idx] or {}
	self.responses[data.idx][data.guid] = { response = data.response, note = data.note }
end

-- Forward-hook target already called (defensively) from Loot/Award.lua:117-119. Kept as an
-- explicit no-op entry point -- a later stage's VotingFrame can show "award in progress" here --
-- rather than broadcasting anything: nothing is confirmed yet.
function Session:OnAwardAttempted(entry)
end

-- Forward-hook target already called (defensively) from Loot/Award.lua:142-144, fired only after
-- LOOT_SLOT_CLEARED actually confirms the award. This is the single "award" broadcast -- there is
-- no separate ack command, matching RCLootCouncil_Classic's own single "awarded" comm.
function Session:OnAwardConfirmed(entry)
	if not self:IsHolder() then
		return
	end
	local item = findItemBySlot(entry.slot)
	if not item then
		return
	end
	item.awarded = entry.winnerGuid
	persist()
	PLC.Comms.Sync:SendAward(self.sessionId, item.idx, entry.winnerGuid)
end

-- Forward-hook target already called (defensively) from Loot/Award.lua:156-158. Local-only: a
-- failed/timed-out award is retried by the holder, never announced to the group.
function Session:OnAwardFailed(entry, reason)
end

function Session:OnAwardReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	local item = self.items[data.idx]
	if item then
		item.awarded = data.winnerGuid
	end
end

function Session:OnHeartbeatReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.lastHolderSeenAt = data.ts or time()
end

-- Holder-only explicit action. Stage 3: temporary /plc session end debug command, same lifecycle
-- as Start(); removed once UI/SessionFrame.lua lands in Stage 5.
function Session:End()
	if not self:IsHolder() then
		print(L["CHAT_PREFIX"] .. L["SESSION_NOT_HOLDER"])
		return
	end
	PLC.Comms.Sync:SendSessionEnd(self.sessionId)
	stopHeartbeat()
	self.state = "ended"
	PLC.db.char.activeSession = nil
	print(L["CHAT_PREFIX"] .. L["SESSION_ENDED"])
end

function Session:OnSessionEndReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.state = "ended"
end

-- The stuck-session escape hatch (spec §5.1/§9): any council member CAN force-end once the
-- holder's heartbeat has gone stale -- this is deliberately a user-visible action (temp
-- /plc session forceend now, a real button later), never something a client triggers on its own
-- just because the threshold passed.
function Session:CanForceEnd()
	if self:IsHolder() or self.state ~= "active" or not self.lastHolderSeenAt then
		return false
	end
	return (time() - self.lastHolderSeenAt) > (PLC.db.profile.sessionForceEndMinutes * 60)
end

function Session:ForceEnd()
	if not self:CanForceEnd() then
		print(L["CHAT_PREFIX"] .. L["SESSION_CANNOT_FORCE_END"])
		return
	end
	PLC.Comms.Sync:SendForceEnd(self.sessionId, UnitGUID("player"))
	self.state = "force_ended"
	print(L["CHAT_PREFIX"] .. L["SESSION_FORCE_ENDED"])
end

function Session:OnForceEndReceived(data, sender)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	local wasHolder = self:IsHolder()
	self.state = "force_ended"
	if wasHolder then
		stopHeartbeat()
		PLC.db.char.activeSession = nil
	end
	local byEntry = data.byGuid and PLC.Roster:Get(data.byGuid)
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_FORCE_ENDED_BY"], (byEntry and byEntry.name) or sender or "?"))
end

-- Resync, not replay (spec §5.1): a client that missed messages (reconnected, zoned back in
-- separately from the holder) asks for a full state snapshot instead of relying on having
-- received every incremental session_start/item_add/response.
function Session:RequestSync()
	PLC.Comms.Sync:SendSyncRequest(UnitGUID("player"))
end

function Session:OnSyncRequestReceived(data, sender)
	if not self:IsHolder() then
		return
	end
	PLC.Comms.Sync:SendSyncData({
		sessionId = self.sessionId,
		owner = self.owner,
		items = stripForTransmit(self.items),
		responses = self.responses,
		lastHolderSeenAt = self.lastHolderSeenAt,
	}, sender)
end

function Session:OnSyncDataReceived(data)
	if self:IsHolder() or not data.sessionId then
		return
	end
	self.sessionId = data.sessionId
	self.owner = data.owner
	self.state = "active"
	self.items = {}
	applyReceivedItems(data.items)
	self.responses = data.responses or {}
	self.lastHolderSeenAt = data.lastHolderSeenAt or time()
	print(L["CHAT_PREFIX"] .. L["SESSION_SYNCED"])
end

local function restoreFromSaved()
	local saved = PLC.db.char.activeSession
	if not saved then
		return
	end
	Session.sessionId = saved.sessionId
	Session.owner = saved.owner
	Session.items = saved.items or {}
	Session.responses = saved.responses or {}
	Session.lastHolderSeenAt = saved.lastHolderSeenAt or time()
	Session.nextIdx = saved.nextIdx or 1
	Session.state = "active"
	Session.sentFirstBatch = true
	startHeartbeat()
	print(L["CHAT_PREFIX"] .. L["SESSION_RESTORED"])
end

PLC:RegisterOnEnable(function()
	restoreFromSaved()
	if not Session:IsHolder() then
		-- One-shot, slightly delayed so Data/Roster.lua has a moment to populate first.
		PLC:ScheduleTimer(function()
			Session:RequestSync()
		end, 2)
	end
end)

-- Temporary debug entry point for Stage 3 -- exercises the full session lifecycle (start, item
-- queueing via real loot detection, response/award broadcast, end, force-end, sync) before any
-- UI exists. Removed once UI/SessionFrame.lua's Start/End controls land in Stage 5.
PLC:RegisterSlashCommand("session", "Debug: start|end|forceend|sync|respond the loot session", function(args)
	local sub = args:match("^(%S*)") or ""
	if sub == "start" then
		Session:Start()
	elseif sub == "end" then
		Session:End()
	elseif sub == "forceend" then
		Session:ForceEnd()
	elseif sub == "sync" then
		Session:RequestSync()
	elseif sub == "respond" then
		local idxStr, response = args:match("^respond%s+(%S+)%s+(%S+)$")
		local idx = idxStr and tonumber(idxStr)
		if not idx or not response then
			print(L["CHAT_PREFIX"] .. L["SESSION_USAGE"])
			return
		end
		Session:SendMyResponse(idx, response:upper(), nil)
	else
		print(L["CHAT_PREFIX"] .. L["SESSION_USAGE"])
	end
end)
