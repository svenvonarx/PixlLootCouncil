local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- A loot session's identity is sticky and location-independent (see docs/SPECIFICATION.md §5.1):
-- it is never reset by zoning, travel, or group reform -- there is simply no handler anywhere in
-- this file for any of those events. Only the holder's explicit Start/End, or another council
-- member's force-end after the holder's heartbeat goes stale, changes state. States:
-- "inactive" -> "active" -> "ended" | "force_ended".
--
-- Bagged-item workflow: the ML stays on Master Loot and self-loots every qualifying item the
-- moment it drops (CollectDetectedItems below) -- silently, with no review/voting yet, possibly
-- hours before a Start() ever happens. "inactive" therefore does NOT mean "nothing is going on":
-- self.items can already be full of bagged loot while state is still "inactive". Start() is the
-- explicit, deliberate moment the ML opens review on everything collected so far; AwardBaggedItem
-- records who an item should go to (the ML still has to trade it to them manually -- there is no
-- live loot slot left to transfer it through by the time anyone's reviewing it).
local Session = {}
PLC.Session = Session

Session.state = "inactive"
Session.sessionId = nil
Session.owner = nil -- { guid, name }
-- [idx] = { idx, lootSlot, itemString, boss, quality, deadlineAt, link, icon, bagged, awarded,
--           preAwardGuid }
Session.items = {}
Session.responses = {} -- [idx][guid] = { response, note }
Session.lastHolderSeenAt = nil
Session.nextIdx = 1
Session.sentFirstBatch = false
Session.responseTimeoutSeconds = 60 -- the holder's db.profile.responseTimeoutSeconds wins for everyone -- see Start()
Session.isCollector = false -- true once this client has silently bagged at least one item -- see persist()

local heartbeatTimerHandle

function Session:IsHolder()
	return self.state == "active" and self.owner ~= nil and self.owner.guid == UnitGUID("player")
end

-- Writes (or clears) db.char.activeSession based on current truth every time it's called, rather
-- than a one-way "only the holder ever writes" gate -- two separate things now need their local
-- state to survive a reload: the formal review-pass holder (IsHolder(), as before) AND a
-- collector who's been silently bagging loot for hours with no formal session running yet
-- (isCollector). Whichever of those is true, this saves the full current picture (items already
-- carry their own bagged/awarded/preAwardGuid state, so nothing extra is needed); when neither
-- is true, it explicitly clears the saved slot instead of leaving a stale value behind.
local function persist()
	if Session:IsHolder() or Session.isCollector then
		PLC.db.char.activeSession = {
			sessionId = Session.sessionId,
			owner = Session.owner,
			items = Session.items,
			responses = Session.responses,
			lastHolderSeenAt = Session.lastHolderSeenAt,
			nextIdx = Session.nextIdx,
			responseTimeoutSeconds = Session.responseTimeoutSeconds,
			isCollector = Session.isCollector,
		}
	else
		PLC.db.char.activeSession = nil
	end
end

-- Strips everything that's only meaningful on the holder's own client (lootSlot -- a live
-- Blizzard loot-window index, not a stable identifier, and gone entirely once an item is bagged
-- -- and the already-resolved display link/icon) before a batch crosses the wire. Mirrors the
-- minimal-wire-shape approach that keeps RCLootCouncil_Classic's per-item send to {typeCode,
-- string, session, boss, owner}. deadlineAt DOES cross the wire, unlike those -- it's stamped
-- once by the holder right when a batch is actually broadcast (Start()/CollectDetectedItems,
-- never at the moment an item was silently bagged, which could have been hours earlier) and must
-- stay the SAME absolute value for every client, including one that resyncs well after the fact.
local function stripForTransmit(entries)
	local out = {}
	for idx, entry in pairs(entries) do
		out[idx] = {
			idx = entry.idx,
			itemString = entry.itemString,
			boss = entry.boss,
			quality = entry.quality,
			deadlineAt = entry.deadlineAt,
		}
	end
	return out
end

local function itemStringFromLink(link)
	return link and link:match("|H(.-)|h")
end

-- GetItemInfo's 10th return value is the item's icon texture -- already being fetched for the
-- link reconstruction, just wasn't being read before.
local function reconstructItemVisuals(itemString)
	if not itemString then
		return nil, nil
	end
	local _, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemString)
	return link, icon
end

-- If the receiving client has never seen this item before, GetItemInfo returns nothing on the
-- first call -- it has to ask the server and comes back later (the exact same "not cached yet"
-- case Loot/Detection.lua's scanLootSlots already retries for the holder's own loot window; this
-- is the equivalent for a RECEIVED item, which was missing entirely before). pendingVisuals
-- tracks which items are still waiting; a single watcher frame resolves all of them whenever
-- Blizzard's GET_ITEM_INFO_RECEIVED fires, rather than polling.
local pendingVisuals = {} -- [idx] = true
local itemInfoWatcher

local function resolvePendingVisuals()
	local resolvedAny = false
	for idx in pairs(pendingVisuals) do
		local entry = Session.items[idx]
		if not entry then
			pendingVisuals[idx] = nil
		else
			local link, icon = reconstructItemVisuals(entry.itemString)
			if link then
				entry.link = link
				entry.icon = icon
				pendingVisuals[idx] = nil
				resolvedAny = true
			end
		end
	end
	if resolvedAny then
		Session:notifyLootFrame()
		Session:notifySessionFrame()
	end
end

local function ensureItemInfoWatcher()
	if itemInfoWatcher then
		return
	end
	itemInfoWatcher = CreateFrame("Frame")
	itemInfoWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	itemInfoWatcher:SetScript("OnEvent", resolvePendingVisuals)
end

local function applyReceivedItems(items)
	for idx, entry in pairs(items) do
		entry.link, entry.icon = reconstructItemVisuals(entry.itemString)
		Session.items[idx] = entry
		if not entry.link then
			pendingVisuals[idx] = true
		end
	end
	if next(pendingVisuals) then
		ensureItemInfoWatcher()
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

-- Finds the most recently collected, not-yet-bagged item for a live Blizzard loot slot. Searched
-- from the end, matching the established search order in Loot/Award.lua:136 -- the item at this
-- lootSlot right now is always the most recent one collected for it, since an older item for the
-- same numeric slot (from an earlier, now-closed loot window) would already be bagged.
local function findItemBySlot(lootSlot)
	for idx = Session.nextIdx - 1, 1, -1 do
		local item = Session.items[idx]
		if item and item.lootSlot == lootSlot and not item.bagged then
			return item
		end
	end
end

-- Called (defensively) from Loot/Detection.lua whenever the local player is the live Blizzard
-- master looter -- NOT gated on an active review session: collection is silent background
-- self-looting across the whole raid, independent of whether Start()/End() has ever run yet.
-- Filters to db.profile.lootThreshold so trash doesn't get hoovered into the ML's bags.
function Session:CollectDetectedItems(lootSlotInfo)
	local threshold = PLC.db.profile.lootThreshold
	local newlyCollected = {}

	for lootSlot, info in pairs(lootSlotInfo) do
		if info.quality and info.quality >= threshold then
			local alreadyCollected = false
			for idx = 1, self.nextIdx - 1 do
				local existing = self.items[idx]
				if existing and existing.lootSlot == lootSlot and existing.link == info.link then
					alreadyCollected = true
					break
				end
			end
			if not alreadyCollected then
				local idx = self.nextIdx
				self.nextIdx = self.nextIdx + 1
				local entry = {
					idx = idx,
					lootSlot = lootSlot,
					itemString = itemStringFromLink(info.link),
					boss = info.boss,
					quality = info.quality,
					link = info.link,
					icon = info.icon,
				}
				self.items[idx] = entry
				newlyCollected[idx] = entry
				-- Self-loot into the ML's own bag through the existing pre-validated funnel.
				-- reason "collect" is how OnAwardConfirmed below tells this apart from anything
				-- else that might ever call TryAward.
				PLC.Loot.Award:TryAward(lootSlot, UnitGUID("player"), "collect")
			end
		end
	end

	if not next(newlyCollected) then
		return
	end

	self.isCollector = true
	persist()

	-- A review pass may already be active (the ML kept raiding while reviewing) -- broadcast
	-- these immediately so candidates see them live. Otherwise this stays silent; Start() below
	-- broadcasts the whole backlog once the ML actually opens review.
	if self:IsHolder() then
		for _, entry in pairs(newlyCollected) do
			entry.deadlineAt = time() + self.responseTimeoutSeconds
		end
		self:broadcastNewItems(newlyCollected)
	end
end

-- Forward-hook target already called (defensively) from Loot/Award.lua, fired once
-- LOOT_SLOT_CLEARED confirms a self-loot actually completed. Award.lua's live-loot-slot funnel is
-- only ever called with the ML's own GUID now (see CollectDetectedItems above) -- a real council
-- award decision goes through AwardBaggedItem instead, which never touches a live slot at all --
-- so this is the only path that reaches here.
function Session:OnAwardConfirmed(entry)
	local item = findItemBySlot(entry.slot)
	if not item then
		return
	end
	item.bagged = true
	item.lootSlot = nil -- the live slot is gone now; nothing should reference it again
	self.isCollector = true
	persist()
	self:notifySessionFrame()
end

-- Forward-hook target already called (defensively) from Loot/Award.lua. Local-only: a failed/
-- timed-out self-loot just means the item is still sitting in the loot window -- it'll be picked
-- up again next time this slot's corpse (or another) triggers LOOT_READY.
function Session:OnAwardAttempted(entry)
end

function Session:OnAwardFailed(entry, reason)
end

-- Explicit holder action only -- there is no reactive "handle loot?" prompt (see
-- docs/SPECIFICATION.md §3 principle 9).
function Session:Start()
	if self.state == "active" then
		print(L["CHAT_PREFIX"] .. L["SESSION_ALREADY_ACTIVE"])
		return
	end
	self.sessionId = UnitGUID("player") .. "-" .. time()
	self.owner = { guid = UnitGUID("player"), name = UnitName("player") }
	self.state = "active"
	self.responses = {}
	self.sentFirstBatch = false
	self.lastHolderSeenAt = time()
	self.responseTimeoutSeconds = PLC.db.profile.responseTimeoutSeconds
	startHeartbeat()

	-- Whatever's already been silently collected becomes this review pass's starting batch.
	-- Each item's response deadline is stamped NOW, not back when it was bagged -- otherwise an
	-- item collected hours ago would show an already-expired countdown the instant anyone
	-- actually sees it.
	local toSend = {}
	for idx, item in pairs(self.items) do
		if not item.awarded then
			item.deadlineAt = time() + self.responseTimeoutSeconds
			toSend[idx] = item
		end
	end

	persist()
	print(L["CHAT_PREFIX"] .. L["SESSION_STARTED"])

	if next(toSend) then
		self:broadcastNewItems(toSend)
	end
end

-- Shared by Start() and AddManualItem below -- sends session_start (first batch of this review
-- pass) or item_add (everything after), announces once, and notifies the UI. Caller is
-- responsible for having already added/updated self.items and called persist() first.
function Session:broadcastNewItems(newItems)
	if not self.sentFirstBatch then
		self.sentFirstBatch = true
		PLC.Comms.Sync:SendSessionStart(self.sessionId, self.owner, stripForTransmit(newItems), self.responseTimeoutSeconds)
		PLC.Loot.Announce:AnnounceSessionStart(newItems)
	else
		PLC.Comms.Sync:SendItemAdd(self.sessionId, stripForTransmit(newItems))
	end
	self:notifyLootFrame()
	self:notifySessionFrame()
end

-- Manually adds one item to the session by itemID or item link -- e.g. a world-drop someone
-- already has in their bag, or anything else that didn't come through this client's own loot
-- window. Holder-only once a review pass is active; works pre-Start() too (silent collection,
-- same as CollectDetectedItems) as long as this client is the designated collector.
function Session:AddManualItem(itemIdOrLink)
	if self.state == "active" and not self:IsHolder() then
		print(L["CHAT_PREFIX"] .. L["SESSION_NOT_HOLDER"])
		return
	end

	local _, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemIdOrLink)
	if not link then
		print(L["CHAT_PREFIX"] .. L["SESSION_ADDITEM_UNKNOWN"])
		return
	end

	local idx = self.nextIdx
	self.nextIdx = self.nextIdx + 1
	local entry = {
		idx = idx,
		lootSlot = nil,
		itemString = itemStringFromLink(link),
		boss = nil,
		quality = quality,
		link = link,
		icon = icon,
		bagged = true, -- manually added items are, by definition, already somewhere in a bag
	}
	self.items[idx] = entry
	self.isCollector = true
	persist()

	if self.state == "active" then
		entry.deadlineAt = time() + self.responseTimeoutSeconds
		self:broadcastNewItems({ [idx] = entry })
	end

	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_ADDITEM_SUCCESS"], link))
end

-- Records a final award decision for an already-bagged item -- by review time everything is
-- bagged under this workflow, so there's no live loot slot left to call GiveMasterLoot against.
-- "Award" here means "decide + tell the holder who to trade it to," not "transfer it directly"
-- (no trade-window automation yet -- see docs/SPECIFICATION.md's Phase 2 notes). Holder-only:
-- only the person physically holding the item's bags should be able to commit this.
function Session:AwardBaggedItem(idx, winnerGuid)
	if not self:IsHolder() then
		print(L["CHAT_PREFIX"] .. L["SESSION_NOT_HOLDER"])
		return false
	end
	local item = self.items[idx]
	if not item then
		return false
	end
	if item.awarded then
		print(L["CHAT_PREFIX"] .. L["SESSION_ALREADY_AWARDED"])
		return false
	end
	local winnerEntry = PLC.Roster:Get(winnerGuid)
	if not winnerEntry then
		print(L["CHAT_PREFIX"] .. L["SESSION_AWARD_UNKNOWN_WINNER"])
		return false
	end

	item.awarded = winnerGuid
	item.preAwardGuid = nil
	persist()
	PLC.Comms.Sync:SendAward(self.sessionId, item.idx, winnerGuid)
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_AWARD_TRADE_INSTRUCTION"], item.link or "?", winnerEntry.name))
	-- The "announce awards in chat" option (profile.announce.award) -- this is now the only
	-- place that can ever fire it; Loot/Award.lua's OnLootSlotCleared skips it entirely for
	-- "collect" reason self-loots (see the comment there).
	if PLC.Loot.Announce and PLC.Loot.Announce.AnnounceAward then
		PLC.Loot.Announce:AnnounceAward({ link = item.link, winnerName = winnerEntry.name })
	end
	self:notifyVotingFrame(item.idx)
	self:notifySessionFrame()
	return true
end

-- Holder-local staging only -- never broadcast, never visible to anyone but the holder's own
-- client. The ML's own private "who I'm planning to pick" scratch space before committing, one
-- at a time (AwardBaggedItem) or in bulk (AwardAllPreAwarded below).
function Session:SetPreAward(idx, winnerGuid)
	if not self:IsHolder() then
		return
	end
	local item = self.items[idx]
	if not item or item.awarded then
		return
	end
	item.preAwardGuid = winnerGuid
	persist()
	self:notifyVotingFrame(idx)
	self:notifySessionFrame()
end

-- Local removal only, never synced -- only safe while nothing's been broadcast about this item
-- yet (state ~= "active"; there's no wire command to retract an already-broadcast item from a
-- candidate's copy). UI/SessionFrame.lua only ever offers this while that holds true.
function Session:RemoveItem(idx)
	if self.state == "active" then
		return
	end
	local item = self.items[idx]
	if not item or item.awarded then
		return
	end
	self.items[idx] = nil
	self.isCollector = next(self.items) ~= nil
	persist()
	self:notifySessionFrame()
end

-- Commits every item that currently has a staged pre-award, through the exact same path a
-- one-by-one Award click uses.
function Session:AwardAllPreAwarded()
	if not self:IsHolder() then
		print(L["CHAT_PREFIX"] .. L["SESSION_NOT_HOLDER"])
		return
	end
	local count = 0
	for idx, item in pairs(self.items) do
		if item.preAwardGuid and not item.awarded then
			if self:AwardBaggedItem(idx, item.preAwardGuid) then
				count = count + 1
			end
		end
	end
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_AWARD_ALL_RESULT"], count))
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
	-- The holder's configured timeout wins for everyone, never the receiving client's own
	-- profile.responseTimeoutSeconds.
	self.responseTimeoutSeconds = data.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	applyReceivedItems(data.items)
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_STARTED_BY"], data.owner and data.owner.name or "?"))
	self:notifyLootFrame()
	self:notifySessionFrame()
end

function Session:OnItemAddReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.lastHolderSeenAt = time()
	applyReceivedItems(data.items)
	self:notifyLootFrame()
	self:notifySessionFrame()
end

-- UI/LootFrame.lua doesn't exist until Stage 5 -- guarded exactly like every other
-- not-yet-built-module forward-call in this codebase.
function Session:notifyLootFrame()
	if PLC.UI and PLC.UI.LootFrame and PLC.UI.LootFrame.Refresh then
		PLC.UI.LootFrame:Refresh()
	end
end

-- UI/SessionFrame.lua's item list only cares about the item SET changing or a status flipping
-- (not per-vote detail, that's UI/VotingFrame.lua's embedded panel via notifyVotingFrame below)
-- -- a full rebuild is cheap enough that there's no targeted-row variant of this one.
function Session:notifySessionFrame()
	if PLC.UI and PLC.UI.SessionFrame and PLC.UI.SessionFrame.OnSessionUpdated then
		PLC.UI.SessionFrame:OnSessionUpdated()
	end
end

-- Broadcast to the whole group, not whispered to the holder -- every council member's client
-- computes the same council set locally from Data/Roster.lua, so every council member's own
-- embedded response grid can stay in sync independently of the holder relaying anything.
function Session:SendMyResponse(idx, response, note)
	if self.state ~= "active" then
		return
	end
	local guid = UnitGUID("player")
	self.responses[idx] = self.responses[idx] or {}
	self.responses[idx][guid] = { response = response, note = note }
	PLC.Comms.Sync:SendResponse(self.sessionId, idx, guid, response, note)
	self:notifyVotingFrame(idx, guid)
	self:notifyLootFrame()
end

function Session:OnResponseReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.responses[data.idx] = self.responses[data.idx] or {}
	self.responses[data.idx][data.guid] = { response = data.response, note = data.note }
	self:notifyVotingFrame(data.idx, data.guid)
end

-- guid is the one row that changed, so VotingFrame can target-refresh just that row instead of
-- rebuilding; omitted (e.g. a fresh sync) means "rebuild everything."
function Session:notifyVotingFrame(idx, guid)
	if PLC.UI and PLC.UI.VotingFrame and PLC.UI.VotingFrame.OnItemUpdated then
		PLC.UI.VotingFrame:OnItemUpdated(idx, guid)
	end
end

function Session:OnAwardReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	local item = self.items[data.idx]
	if item then
		item.awarded = data.winnerGuid
	end
	self:notifyVotingFrame(data.idx)
	self:notifySessionFrame()
end

function Session:OnHeartbeatReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.lastHolderSeenAt = data.ts or time()
end

-- Holder-only explicit action.
function Session:End()
	if not self:IsHolder() then
		print(L["CHAT_PREFIX"] .. L["SESSION_NOT_HOLDER"])
		return
	end
	PLC.Comms.Sync:SendSessionEnd(self.sessionId)
	stopHeartbeat()
	self.state = "ended"

	-- Prune already-awarded items -- not-yet-awarded ones carry forward to the next Start()
	-- instead of this review pass's leftovers vanishing.
	for idx, item in pairs(self.items) do
		if item.awarded then
			self.items[idx] = nil
		end
	end
	self.isCollector = next(self.items) ~= nil
	persist()

	print(L["CHAT_PREFIX"] .. L["SESSION_ENDED"])
end

function Session:OnSessionEndReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.state = "ended"
end

-- The stuck-session escape hatch (spec §5.1/§9): any council member CAN force-end once the
-- holder's heartbeat has gone stale -- this is deliberately a user-visible action, never
-- something a client triggers on its own just because the threshold passed.
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
		responseTimeoutSeconds = self.responseTimeoutSeconds,
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
	self.responseTimeoutSeconds = data.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
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
	Session.responseTimeoutSeconds = saved.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	Session.isCollector = saved.isCollector or false

	if saved.owner and saved.sessionId and saved.owner.guid == UnitGUID("player") then
		-- A formal review pass was active -- resume it fully, heartbeat included.
		Session.state = "active"
		Session.sentFirstBatch = true
		startHeartbeat()
		print(L["CHAT_PREFIX"] .. L["SESSION_RESTORED"])
	else
		-- Collector-only: items were silently bagged but no review pass had started yet.
		-- Restore the backlog locally without claiming formal session ownership -- Start()
		-- claims it for real once the ML actually begins reviewing.
		Session.state = "inactive"
	end
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

-- Debug entry point for the two lifecycle actions that still have no real UI anywhere in the
-- Phase 1 plan: force-end (spec §5.1's stuck-session escape hatch is a user action, but no stage
-- builds it a button) and a manual sync request.
PLC:RegisterSlashCommand("session", "Debug: forceend|sync the loot session", function(args)
	local sub = args:match("^(%S*)") or ""
	if sub == "forceend" then
		Session:ForceEnd()
	elseif sub == "sync" then
		Session:RequestSync()
	else
		print(L["CHAT_PREFIX"] .. L["SESSION_USAGE"])
	end
end)

-- Real utility command, not a debug stub -- lets the ML add an item that didn't come through
-- their own loot window (a world drop someone already picked up, etc).
PLC:RegisterSlashCommand("additem", "Manually add an item to the session by itemID or link", function(args)
	local itemArg = args:match("^%s*(.-)%s*$")
	if itemArg == "" then
		print(L["CHAT_PREFIX"] .. L["SESSION_ADDITEM_USAGE"])
		return
	end
	Session:AddManualItem(tonumber(itemArg) or itemArg)
end)
