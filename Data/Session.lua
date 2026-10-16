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
-- Who disenchanted items are staged to -- nil means "use Session:GetEnchanterGuid()'s computed
-- default (alphabetically-first roster member)" rather than no one. Treated like `owner`, not
-- like per-item scratch state: never reset by Start()/End(), since a raid's designated enchanter
-- is realistically the same person across the whole night's many review passes.
Session.enchanterGuid = nil
-- [idx] = { idx, lootSlot, itemString, boss, quality, deadlineAt, link, icon, bagged, awarded,
--           awardReason, awardedAt, traded, preAwardGuid, preAwardReason,
--           itemGUID, tradeExpiresAt, boe, untradable -- Loot/BagTracker.lua's trade tracking }
Session.items = {}
Session.responses = {} -- [idx][guid] = { response, note }
Session.lastHolderSeenAt = nil
Session.nextIdx = 1
Session.sentFirstBatch = false
Session.responseTimeoutSeconds = 60 -- the holder's db.profile.responseTimeoutSeconds wins for everyone -- see Start()
Session.isCollector = false -- true once this client has silently bagged at least one item -- see persist()

local heartbeatTimerHandle
local persist -- forward-declared: SetEnchanter (above its definition) calls it

function Session:IsHolder()
	return self.state == "active" and self.owner ~= nil and self.owner.guid == UnitGUID("player")
end

-- Same identity check as IsHolder, WITHOUT the state == "active" requirement -- for post-commit
-- bookkeeping (Loot/Trade.lua's trade-placement/bag-watching, UI/TradeFrame.lua's "items to hand
-- out") that has to keep working for as long as items are still physically outstanding, which is
-- routinely AFTER the review pass itself has ended (Award All now ends the session the moment it
-- commits -- see AwardAllPreAwarded below -- so anything gated on IsHolder() instead of this would
-- have silently stopped working at exactly the moment it's needed most: right as the holder goes
-- to actually hand everything out). Session.owner itself is never cleared by End() -- only
-- Start()'s brand-new session claims a different owner -- so this stays correct for exactly as
-- long as it needs to: until the NEXT review pass starts under a (possibly different) holder.
function Session:IsOwner()
	return self.owner ~= nil and self.owner.guid == UnitGUID("player")
end

-- Strictly a known Enchanter or nothing -- NEVER a random roster member picked by alphabetical
-- luck, even as a last-resort fallback. Two parts:
--  1. An explicit pick (Session:SetEnchanter, via the now-filtered dropdown -- see
--     UI/SessionFrame.lua) only counts while that person is STILL known to have Enchanting right
--     now. This is what actually closes the bug for good: a stale pick persisted from before
--     today's rework (back when the default/dropdown weren't profession-filtered yet) would
--     otherwise keep silently overriding the computed default forever, since Session.enchanterGuid
--     is sticky by design (never reset by Start()/End(), like owner) -- re-validating it here means
--     a bad historical pick simply stops counting the moment it's checked, no manual cleanup
--     needed.
--  2. Otherwise, the alphabetically-first roster member who IS currently known to have Enchanting
--     (Data/Professions.lua) -- or nil if nobody's synced Enchanting data yet. Returning nil here
--     is deliberate: silently defaulting to someone who doesn't have Enchanting is the exact bug
--     this replaces, so "we don't know anyone yet" has to be a real, visible state rather than a
--     wrong-but-plausible-looking guess (see UI/SessionFrame.lua/UI/VotingFrame.lua's nil handling).
-- Computed fresh on every call (not cached) so it naturally tracks roster/profession-sync changes.
function Session:GetEnchanterGuid()
	if self.enchanterGuid and PLC.Professions:HasProfession(self.enchanterGuid, PLC.Professions.ENCHANTING_KEY) then
		return self.enchanterGuid
	end
	local bestGuid, bestName
	for guid, entry in PLC.Roster:IterateGroup() do
		if PLC.Professions:HasProfession(guid, PLC.Professions.ENCHANTING_KEY) then
			local name = PLC.Roster:ShortName(entry.name)
			if not bestName or name < bestName then
				bestGuid, bestName = guid, name
			end
		end
	end
	return bestGuid
end

-- Holder-only, like every other session-identity write (Start/End/AwardBaggedItem). Unlike
-- preAwardGuid, this is never cleared by Start()/End() -- see the field comment on
-- Session.enchanterGuid above.
function Session:SetEnchanter(guid)
	if not self:IsHolder() then
		return
	end
	self.enchanterGuid = guid
	persist()
	PLC.Comms.Sync:SendSetEnchanter(self.sessionId, guid)
	-- No notifyVotingFrame call -- unlike an item update, this isn't tied to any specific item
	-- idx (notifyVotingFrame(idx, guid)'s idx must match the panel's currently-shown item exactly
	-- or it's a no-op, see UI/VotingFrame.lua:Panel:OnItemUpdated). UI/VotingFrame.lua's
	-- Disenchant button instead reads Session:GetEnchanterGuid() fresh at hover time for its
	-- tooltip, so there's nothing here that needs pushing.
	self:notifySessionFrame()
end

function Session:OnEnchanterReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.enchanterGuid = data.guid
	self:notifySessionFrame()
end

-- Writes (or clears) db.char.activeSession based on current truth every time it's called, rather
-- than a one-way "only the holder ever writes" gate -- two separate things now need their local
-- state to survive a reload: the formal review-pass holder (IsHolder(), as before) AND a
-- collector who's been silently bagging loot for hours with no formal session running yet
-- (isCollector). Whichever of those is true, this saves the full current picture (items already
-- carry their own bagged/awarded/preAwardGuid state, so nothing extra is needed); when neither
-- is true, it explicitly clears the saved slot instead of leaving a stale value behind.
function persist()
	if Session:IsHolder() or Session.isCollector then
		PLC.db.char.activeSession = {
			sessionId = Session.sessionId,
			state = Session.state,
			owner = Session.owner,
			enchanterGuid = Session.enchanterGuid,
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
-- Trade time travels as seconds REMAINING, not the holder's absolute tradeExpiresAt -- each client's
-- time() is its own machine clock, so an absolute value would be off by however far the clocks
-- differ; applyReceivedItems turns it back into a local tradeExpiresAt.
local function stripForTransmit(entries)
	local out = {}
	for idx, entry in pairs(entries) do
		out[idx] = {
			idx = entry.idx,
			itemString = entry.itemString,
			boss = entry.boss,
			quality = entry.quality,
			deadlineAt = entry.deadlineAt,
			tradeRemaining = entry.tradeExpiresAt and math.max(0, entry.tradeExpiresAt - time()) or nil,
			boe = entry.boe,
			untradable = entry.untradable,
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
		if entry.tradeRemaining then
			entry.tradeExpiresAt = time() + entry.tradeRemaining
			entry.tradeRemaining = nil
		end
		-- An item_add can re-send an item this client already has (the holder learned its trade
		-- time later) -- keep the award/trade state we already know about.
		local existing = Session.items[idx]
		if existing then
			entry.awarded, entry.awardReason, entry.awardedAt = existing.awarded, existing.awardReason, existing.awardedAt
			entry.traded = existing.traded
		end
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
					-- Collection-time only, local to this client, never sent over the wire (not in
					-- stripForTransmit below) -- purely for Data/History.lua's own recording on
					-- whichever client actually ends up holding/awarding the item.
					bossName = info.bossName,
					instance = info.instance,
					difficultyName = info.difficultyName,
					mapID = info.mapID,
					difficultyID = info.difficultyID,
					groupSize = info.groupSize,
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
	-- Always notify, even while silently collecting (state ~= "active" -- the normal state for
	-- most of a raid under this workflow) -- an already-open UI/SessionFrame.lua needs to show
	-- newly bagged items live, not just once a review pass starts. broadcastNewItems below
	-- notifies again when active, which is a harmless redundant call, not a correctness issue.
	self:notifySessionFrame()

	-- A review pass may already be active (the ML kept raiding while reviewing) -- broadcast
	-- these immediately so candidates see them live. Otherwise this stays silent; Start() below
	-- broadcasts the whole backlog once the ML actually opens review.
	if self:IsHolder() then
		for _, entry in pairs(newlyCollected) do
			entry.deadlineAt = time() + self.responseTimeoutSeconds
		end
		self:broadcastNewItems(newlyCollected)
	else
		self:ScheduleAutoStart()
	end
end

-- Adds an item Loot/BagTracker.lua found in the bags (raid loot that didn't come through this
-- client's own loot-window collection: a trade-window BoP or a BoE recipe). Same shape as a
-- collected item, already bagged and tied to its physical copy via itemGUID. Returns the entry.
function Session:AddTrackedItem(link, itemGUID)
	if self.state == "active" and not self:IsHolder() then
		return nil
	end
	local _, fullLink, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
	local instanceName, _, difficultyID, difficultyName, _, _, _, mapID, groupSize = GetInstanceInfo()
	local idx = self.nextIdx
	self.nextIdx = self.nextIdx + 1
	local entry = {
		idx = idx,
		itemString = itemStringFromLink(fullLink or link),
		quality = quality,
		link = fullLink or link,
		icon = icon,
		bagged = true,
		itemGUID = itemGUID,
		instance = instanceName,
		difficultyName = difficultyName,
		mapID = mapID,
		difficultyID = difficultyID,
		groupSize = groupSize,
	}
	self.items[idx] = entry
	self.isCollector = true
	persist()
	self:notifySessionFrame()
	if self:IsHolder() then
		entry.deadlineAt = time() + self.responseTimeoutSeconds
		self:broadcastNewItems({ [idx] = entry })
	else
		self:ScheduleAutoStart()
	end
	return entry
end

-- Called by Loot/BagTracker.lua after it updated items' trade status. During an active review,
-- items that were broadcast before their trade time was known are re-sent once (item_add on an
-- existing idx just refreshes it on the other clients -- see applyReceivedItems).
function Session:OnTradeStatusChanged()
	if self:IsHolder() then
		local resend = {}
		for idx, item in pairs(self.items) do
			if item.deadlineAt and not item.awarded and not item.tradeSynced
				and (item.tradeExpiresAt or item.boe or item.untradable) then
				item.tradeSynced = true
				resend[idx] = item
			end
		end
		if next(resend) then
			PLC.Comms.Sync:SendItemAdd(self.sessionId, stripForTransmit(resend))
		end
	end
	if self:IsHolder() or self.isCollector then
		persist()
	end
	self:notifySessionFrame()
	self:notifyTradeFrame()
end

-- RC's autoStart: the master looter collecting loot starts a review pass on its own. Debounced, so
-- one boss's whole loot window (plus the bag scan that follows it) becomes a single session.
local AUTO_START_DELAY = 3
local autoStartTimer

function Session:ScheduleAutoStart()
	if not PLC.db.profile.autoStartSession or self.state == "active" or not IsInGroup() then
		return
	end
	if autoStartTimer then
		PLC:CancelTimer(autoStartTimer)
	end
	autoStartTimer = PLC:ScheduleTimer(function()
		autoStartTimer = nil
		if self.state == "active" or not PLC.CouncilRules:AmIMasterLooter() then
			return
		end
		for _, item in pairs(self.items) do
			if not item.awarded and not item.untradable then
				self:Start()
				if PLC.UI and PLC.UI.SessionFrame and PLC.UI.SessionFrame.Open then
					PLC.UI.SessionFrame:Open()
				end
				return
			end
		end
	end, AUTO_START_DELAY)
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
	-- The holder is almost always also a candidate -- announce their own equipped gear and
	-- professions the same as every other candidate does (see Data/Gear.lua, Data/Professions.lua),
	-- not a special case.
	PLC.Gear:BroadcastOwn()
	PLC.Professions:BroadcastOwn()

	-- Whatever's already been silently collected becomes this review pass's starting batch.
	-- Each item's response deadline is stamped NOW, not back when it was bagged -- otherwise an
	-- item collected hours ago would show an already-expired countdown the instant anyone
	-- actually sees it. preAwardGuid/preAwardReason are cleared too -- they're this review pass's
	-- own scratch state (Session:SetPreAward), and a pick staged but never committed before the
	-- previous End() must not silently show as "Staged" again the moment a new review starts.
	local toSend = {}
	for idx, item in pairs(self.items) do
		-- Items whose trade window already ran out can't go to anyone -- they stay in the list
		-- (marked expired) until removed, but aren't put up for review.
		if not item.awarded and not item.untradable then
			item.deadlineAt = time() + self.responseTimeoutSeconds
			item.tradeSynced = item.tradeExpiresAt ~= nil or item.boe or nil
			item.preAwardGuid = nil
			item.preAwardReason = nil
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
		PLC.Comms.Sync:SendSessionStart(self.sessionId, self.owner, stripForTransmit(newItems), self.responseTimeoutSeconds, self.enchanterGuid)
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
	-- Same reasoning as CollectDetectedItems above: notify regardless of state, so an
	-- already-open UI/SessionFrame.lua picks up a manually-added item immediately even before
	-- any review pass has started.
	self:notifySessionFrame()

	if self.state == "active" then
		entry.deadlineAt = time() + self.responseTimeoutSeconds
		self:broadcastNewItems({ [idx] = entry })
	end

	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_ADDITEM_SUCCESS"], link))
end

-- Records a FINAL award decision for an already-bagged item -- by review time everything is
-- bagged under this workflow, so there's no live loot slot left to call GiveMasterLoot against.
-- "Award" here means "decide who gets it" -- the actual handoff is Loot/Trade.lua's job from here
-- (UI/TradeFrame.lua's "items to hand out"/"items to collect" windows), not this function's.
-- Holder-only: only the person physically holding the item's bags should be able to commit this.
--
-- The only caller is AwardAllPreAwarded below -- there's no more direct, one-click-and-it's-final
-- path from the UI (see UI/VotingFrame.lua): every row's Award/Disenchant button only ever calls
-- SetPreAward (stage), never this. `reason` is "award" (trade to winnerGuid) or "disenchant"
-- (winnerGuid is the designated Enchanter, Session:GetEnchanterGuid() -- still a real roster GUID,
-- still goes through the exact same trade-tracking/Announce path, just with different wording).
function Session:AwardBaggedItem(idx, winnerGuid, reason)
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

	reason = reason or "award"
	item.awarded = winnerGuid
	item.awardReason = reason
	item.awardedAt = time() -- feeds UI/TradeFrame.lua's "awarded Xm ago" timer
	item.preAwardGuid = nil
	item.preAwardReason = nil
	persist()
	PLC.Comms.Sync:SendAward(self.sessionId, item.idx, winnerGuid, reason)
	-- No local "trade it to them!" print here anymore -- the raid-chat announcement below already
	-- communicates who got what, and UI/TradeFrame.lua's own "items to hand out" row is the
	-- holder's actual actionable reminder now; a third, redundant local system-message line on top
	-- of both was exactly what the user asked to drop.
	if PLC.Loot.Announce and PLC.Loot.Announce.AnnounceAward then
		PLC.Loot.Announce:AnnounceAward({ link = item.link, winnerName = winnerEntry.name, reason = reason })
	end
	if PLC.History and PLC.History.RecordAward then
		PLC.History:RecordAward(item, winnerGuid, reason)
	end
	-- A genuine self-AWARD (not disenchant) -- the item's already sitting right where it needs to
	-- be, so there's nothing left to do at all; auto-complete it so UI/TradeFrame.lua never shows
	-- it in both "items to hand out" and "items to collect" forever, and clicking Trade on it never
	-- tries to InitiateTrade with yourself. A self-DISENCHANT is deliberately NOT included here --
	-- the item is in the holder's bags, yes, but disenchanting it is a real action this addon
	-- doesn't perform for them (no "auto-cast Disenchant" feature), so it still needs to show up as
	-- a reminder. Loot/Trade.lua's own bag-watch picks it up automatically once they actually
	-- disenchant it, the same way a real trade's completion is detected.
	if reason == "award" and winnerGuid == UnitGUID("player") then
		self:MarkItemTraded(idx)
	end
	self:notifyVotingFrame(item.idx)
	self:notifySessionFrame()
	self:notifyTradeFrame()
	return true
end

-- Holder-local staging only -- never broadcast, never visible to anyone but the holder's own
-- client. This is now THE way every decision gets made (see UI/VotingFrame.lua's Award/Disenchant
-- buttons) -- the ML's "who I'm planning to pick" scratch space, committed only in bulk via
-- AwardAllPreAwarded below. Calling this again (a different candidate, or the other reason) just
-- overwrites the previous pick -- that's the whole "you can still go back and award it to someone
-- else" behavior, already free from this always having been overwrite-not-append.
function Session:SetPreAward(idx, winnerGuid, reason)
	if not self:IsHolder() then
		return
	end
	local item = self.items[idx]
	if not item or item.awarded then
		return
	end
	item.preAwardGuid = winnerGuid
	item.preAwardReason = reason or "award"
	persist()
	self:notifyVotingFrame(idx)
	self:notifySessionFrame()
end

-- Removes not-yet-awarded items. Outside a review pass this is local only (nothing was broadcast
-- yet); during one, only the holder can do it and the removal is broadcast (item_remove) so every
-- candidate's Loot Response window and every council grid drop the item too.
local function removeItems(idxs)
	local removed = {}
	for _, idx in ipairs(idxs) do
		local item = Session.items[idx]
		if item and not item.awarded then
			Session.items[idx] = nil
			Session.responses[idx] = nil
			table.insert(removed, idx)
		end
	end
	return removed
end

function Session:CanRemoveItems()
	return self.state ~= "active" or self:IsHolder()
end

function Session:RemoveItem(idx)
	self:RemoveItems({ idx })
end

function Session:RemoveItems(idxs)
	if not self:CanRemoveItems() then
		print(L["CHAT_PREFIX"] .. L["SESSION_NOT_HOLDER"])
		return 0
	end
	local removed = removeItems(idxs)
	if #removed == 0 then
		return 0
	end
	self.isCollector = next(self.items) ~= nil
	if self.state == "active" then
		PLC.Comms.Sync:SendItemRemove(self.sessionId, removed)
	end
	persist()
	self:notifySessionFrame()
	self:notifyLootFrame()
	return #removed
end

-- Every item that hasn't been awarded yet (awarded items stay until they're traded). Ends an active
-- review pass if that leaves it with nothing to review.
function Session:RemoveAllItems()
	local idxs = {}
	for idx, item in pairs(self.items) do
		if not item.awarded then
			table.insert(idxs, idx)
		end
	end
	local count = self:RemoveItems(idxs)
	if count > 0 then
		print(L["CHAT_PREFIX"] .. string.format(L["SESSION_REMOVED_ALL"], count))
		if self:IsHolder() then
			self:End()
		end
	end
	return count
end

function Session:OnItemRemoveReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId or type(data.idxs) ~= "table" then
		return
	end
	removeItems(data.idxs)
	self:notifySessionFrame()
	self:notifyLootFrame()
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
			if self:AwardBaggedItem(idx, item.preAwardGuid, item.preAwardReason) then
				count = count + 1
			end
		end
	end
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_AWARD_ALL_RESULT"], count))
	-- Award All is now also the deliberate "I'm done reviewing" signal, not just a bulk-commit --
	-- confirmed explicitly (the alternative, leaving End Session as a separate step so voting
	-- could keep going on other items, was declined). End() already handles broadcasting
	-- session_end, stopping the heartbeat, and pruning -- nothing else here needs to change.
	self:End()
	if PLC.UI and PLC.UI.TradeFrame and PLC.UI.TradeFrame.Open then
		PLC.UI.TradeFrame:Open()
	end
end

function Session:OnSessionStartReceived(data)
	if self:IsHolder() then
		return
	end
	self.sessionId = data.sessionId
	self.owner = data.owner
	self.enchanterGuid = data.enchanterGuid
	self.state = "active"
	self.items = {}
	self.responses = {}
	self.lastHolderSeenAt = time()
	-- The holder's configured timeout wins for everyone, never the receiving client's own
	-- profile.responseTimeoutSeconds.
	self.responseTimeoutSeconds = data.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	applyReceivedItems(data.items)
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_STARTED_BY"], data.owner and data.owner.name or "?"))
	-- Announces OUR gear and professions now that we know a review pass actually started -- see
	-- Data/Gear.lua, Data/Professions.lua.
	PLC.Gear:BroadcastOwn()
	PLC.Professions:BroadcastOwn()
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

-- UI/TradeFrame.lua doesn't exist until this round's own UI step -- guarded exactly like every
-- other not-yet-built-module forward-call in this codebase (see notifyLootFrame above).
function Session:notifyTradeFrame()
	if PLC.UI and PLC.UI.TradeFrame and PLC.UI.TradeFrame.OnSessionUpdated then
		PLC.UI.TradeFrame:OnSessionUpdated()
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
		item.awardReason = data.reason or "award"
		item.awardedAt = time()
		item.preAwardGuid = nil
		item.preAwardReason = nil
	end
	self:notifyVotingFrame(data.idx)
	self:notifySessionFrame()
	if data.winnerGuid == UnitGUID("player") and PLC.UI and PLC.UI.TradeFrame and PLC.UI.TradeFrame.Open then
		-- Awarded to me: reopen the trade window even if I closed it earlier.
		PLC.UI.TradeFrame:Open()
	else
		self:notifyTradeFrame()
	end
end

-- Session owner only (IsOwner, not IsHolder -- this keeps working after the session has ended,
-- which it now always has by the time most items actually get traded, since Award All ends it
-- immediately), called from Loot/Trade.lua once it's confirmed (by actually re-checking its own
-- bags after a trade closes, never just assumed) that an item genuinely left the holder's hands --
-- see Loot/Trade.lua:OnTradeClosed. Every other client only ever learns this via the broadcast
-- below (OnTradeCompleteReceived), never by guessing from their own BAG_UPDATE -- a recipient who
-- already owned a stack of the same item would be a false positive for that, so the holder's own
-- bags are kept the one source of truth.
function Session:MarkItemTraded(idx)
	if not self:IsOwner() then
		return
	end
	local item = self.items[idx]
	if not item or not item.awarded or item.traded then
		return
	end
	item.traded = true
	persist()
	PLC.Comms.Sync:SendTradeComplete(self.sessionId, idx)
	self:notifySessionFrame()
	self:notifyTradeFrame()
end

-- Manual escape hatch from UI/TradeFrame.lua's remove button, for a row that's stuck (traded
-- outside the addon, item lost, bugged state). The owner's removal counts as a completed handoff
-- and is broadcast, so the recipient's matching "collect" row clears too; a recipient's removal
-- only dismisses the row in their own window.
function Session:DismissTradeItem(idx)
	local item = self.items[idx]
	if not item or not item.awarded or item.traded then
		return
	end
	if self:IsOwner() then
		self:MarkItemTraded(idx)
		return
	end
	item.traded = true
	self:notifySessionFrame()
	self:notifyTradeFrame()
end

function Session:OnTradeCompleteReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	local item = self.items[data.idx]
	if item then
		item.traded = true
	end
	self:notifySessionFrame()
	self:notifyTradeFrame()
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

	-- Prune fully TRADED items -- not item.awarded. This used to prune on item.awarded, back when
	-- End() was always pressed well after Award All, by which point everything awarded had
	-- already been physically traded too. Now that Award All ends the session itself, immediately
	-- after committing (see AwardAllPreAwarded), item.awarded is true for everything the instant
	-- End() runs here -- pruning on that condition would have deleted every just-awarded item from
	-- Session.items before UI/TradeFrame.lua ever got a chance to show it, and before
	-- Loot/Trade.lua had any record left to mark traded once it actually happened. item.traded is
	-- the real "nothing left to do" signal; an awarded-but-not-yet-traded item now correctly
	-- survives End() (and persists across a reload -- see persist()'s own isCollector check below)
	-- for as long as it takes to actually hand it off, exactly like UI/TradeFrame.lua's "items to
	-- hand out"/"items to collect" sections need. Not-yet-awarded items still carry forward to the
	-- next Start() same as before; preAwardGuid/preAwardReason (this review pass's own scratch
	-- state, Session:SetPreAward) are still cleared here too, not just in Start(), so a pick
	-- staged but never committed doesn't keep showing as "Staged" during the inactive gap.
	for idx, item in pairs(self.items) do
		if item.traded then
			self.items[idx] = nil
		else
			item.preAwardGuid = nil
			item.preAwardReason = nil
		end
	end
	self.isCollector = next(self.items) ~= nil
	persist()
	self:notifySessionFrame()
	self:notifyLootFrame()
	self:notifyTradeFrame()

	print(L["CHAT_PREFIX"] .. L["SESSION_ENDED"])
end

function Session:OnSessionEndReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.state = "ended"
	self:notifySessionFrame()
	self:notifyLootFrame()
	self:notifyTradeFrame()
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
	self:notifySessionFrame()
	self:notifyLootFrame()
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
		enchanterGuid = self.enchanterGuid,
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
	self.enchanterGuid = data.enchanterGuid
	self.state = "active"
	self.items = {}
	self.responseTimeoutSeconds = data.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	applyReceivedItems(data.items)
	self.responses = data.responses or {}
	self.lastHolderSeenAt = data.lastHolderSeenAt or time()
	print(L["CHAT_PREFIX"] .. L["SESSION_SYNCED"])
	-- A late joiner catching up never got the session-start broadcast that would otherwise have
	-- triggered this -- announce our gear and professions now so we're not a permanent gap in the
	-- group's data for this session (see Data/Gear.lua, Data/Professions.lua).
	PLC.Gear:BroadcastOwn()
	PLC.Professions:BroadcastOwn()
end

local function restoreFromSaved()
	local saved = PLC.db.char.activeSession
	if not saved then
		return
	end
	Session.sessionId = saved.sessionId
	Session.owner = saved.owner
	Session.enchanterGuid = saved.enchanterGuid
	Session.items = saved.items or {}
	Session.responses = saved.responses or {}
	Session.lastHolderSeenAt = saved.lastHolderSeenAt or time()
	Session.nextIdx = saved.nextIdx or 1
	Session.responseTimeoutSeconds = saved.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	Session.isCollector = saved.isCollector or false

	local isOwner = saved.owner and saved.owner.guid == UnitGUID("player")
	-- Only a save explicitly marked active resumes. Saves from before state was persisted
	-- (state == nil) used to be treated as active, which resurrected long-dead sessions on every
	-- reload and made that client ignore everyone else's session_start as the "holder."
	if isOwner and saved.sessionId and saved.state == "active" then
		-- A formal review pass was active -- resume it fully, heartbeat included.
		Session.state = "active"
		Session.sentFirstBatch = true
		startHeartbeat()
		print(L["CHAT_PREFIX"] .. L["SESSION_RESTORED"])
	elseif isOwner and saved.state then
		-- Ended, but items may still be awaiting trade/disenchant -- keep owner (IsOwner) without
		-- resuming the review pass or its heartbeat.
		Session.state = saved.state
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

-- The two session lifecycle actions without a button: resync from the holder, and the
-- stuck-session escape hatch (spec §5.1).
PLC:RegisterSlashCommand("sync", "Resync the current loot session from its holder", function()
	Session:RequestSync()
end)

PLC:RegisterSlashCommand("forceend", "Force-end a session whose holder stopped responding", function()
	Session:ForceEnd()
end)

-- Real utility command, not a debug stub -- lets the ML add an item that didn't come through
-- their own loot window (a world drop someone already picked up, etc).
PLC:RegisterSlashCommand("additem", "Add an item to the session by item link or ID", function(args)
	local itemArg = args:match("^%s*(.-)%s*$")
	if itemArg == "" then
		print(L["CHAT_PREFIX"] .. L["SESSION_ADDITEM_USAGE"])
		return
	end
	Session:AddManualItem(tonumber(itemArg) or itemArg)
end)
