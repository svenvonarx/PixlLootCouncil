local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- A loot session's identity is sticky and location-independent (see docs/SPECIFICATION.md §5.1):
-- it is never reset by zoning, travel, or group reform -- there is simply no handler anywhere in
-- this file for any of those events. Only the holder's explicit Start/End, or another council
-- member's force-end after the holder's heartbeat goes stale, changes state. States:
-- "inactive" -> "active" -> "ended" | "force_ended".
--
-- Bagged-item workflow: the ML stays on Master Loot and every qualifying item goes into their bags
-- the moment it drops (Loot/AutoLoot.lua, then CollectDetectedItems below) -- silently, with no
-- review/voting yet, possibly hours before a Start() ever happens. "inactive" therefore does NOT mean "nothing is going on":
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
Session.responseSet = nil -- the holder's response buttons, fixed at Start() -- see Data/Responses.lua
Session.preview = false -- a practice session with fictional loot is running -- see Data/Preview.lua
Session.isCollector = false -- true once this client has silently bagged at least one item -- see persist()
-- [guid] = true: the loot council for the current session, decided by the HOLDER's council
-- settings and broadcast by the holder (session_start, sync, "council" on roster changes), so every
-- client agrees on who sees the voting grid. nil = no session info yet; fall back to the local roster.
Session.council = nil

local heartbeatTimerHandle
local persist -- forward-declared: SetEnchanter (above its definition) calls it
local restored = false -- restoreFromSaved has run, so IsHolder() can be trusted
local syncAsked = false -- already asked for a resync since joining this group
local resumedAtLogin = false -- a running pass was resumed at login; checked once the group is known

-- Catching up (Session:CatchUp). Group messages only reach whoever is there to hear them: someone on
-- a loading screen, or whose message got lost, simply never gets it, and the holder can miss
-- answers the same way. So nothing relies on one message arriving. The holder's heartbeat says what
-- the session looks like, and whoever doesn't match asks for all of it, or sends their answers
-- again.
local CATCH_UP_COOLDOWN = 15 -- seconds between asks, so nobody floods the holder
local SYNC_GATHER = 2 -- the holder waits this long for more asks, then answers them all at once
local ZONE_SETTLE = 3 -- seconds after a loading screen before asking
local SILENT_BEATS = 3 -- this many missed heartbeats and the holder may have ended without us
local lastCatchUp = 0
local awaitingSync = false -- asked, and the answer hasn't come yet
local itemsBehindLast = false -- the previous heartbeat's item summary didn't match either
local previousResponded -- the holder's answer counts in the previous heartbeat
local mineAtLastBeat -- how many items this client had answered when that heartbeat came
local lastHeartbeatAt -- local time the holder's last heartbeat came in
local holderEvery -- seconds between the holder's heartbeats, as it says
local syncRequesters, syncAnswerTimer = {}, nil

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

-- Who may START a review pass: the live master looter whenever the group is on Master Loot (the
-- ML holds the loot, so the ML is always the session master); without Master Loot, the group
-- leader -- or anyone solo, for testing.
function Session:CanStart()
	if self.state == "active" then
		return false
	end
	if PLC.CouncilRules:IsMasterLootMethod() then
		return PLC.CouncilRules:AmIMasterLooter()
	end
	return not IsInGroup() or UnitIsGroupLeader("player")
end

-- Who may manage the item list (Remove / Remove All / Enchanter): the holder during a review pass;
-- outside one, whoever actually holds the backlog (the collector / session owner / master looter).
function Session:CanManage()
	if self.state == "active" then
		return self:IsHolder()
	end
	return self.isCollector or self:IsOwner() or PLC.CouncilRules:AmIMasterLooter()
end

-- The council set from the local roster (this client's own council settings) plus the holder.
function Session:ComputeCouncil()
	local council = {}
	for guid in pairs(PLC.Roster:GetCouncil()) do
		council[guid] = true
	end
	if self.owner then
		council[self.owner.guid] = true
	end
	return council
end

function Session:IsCouncilMember(guid)
	guid = guid or UnitGUID("player")
	if self.owner and self.owner.guid == guid and self.state == "active" then
		return true
	end
	if self.council and self.state ~= "inactive" then
		return self.council[guid] == true
	end
	local entry = PLC.Roster:Get(guid)
	return entry ~= nil and entry.council == true
end

local function councilList(set)
	local list = {}
	for guid in pairs(set or {}) do
		table.insert(list, guid)
	end
	table.sort(list)
	return list
end

local function councilSet(list)
	local set = {}
	for _, guid in ipairs(list or {}) do
		set[guid] = true
	end
	return set
end

-- Called by Data/Roster.lua after every rebuild (group changes, loot method, guild ranks, council
-- options). The holder re-broadcasts the council when it changed. Everyone else uses it to catch
-- up on a session they weren't there for: logging in, reloading, or joining the group mid-session
-- all end up here, once the group is actually known -- one request per group membership.
function Session:OnRosterRebuilt()
	-- A pass resumed at login belongs to whoever runs the loot now. In a group whose master looter
	-- is someone else, this client's old pass would pull the raid off theirs: it ends instead.
	if resumedAtLogin and IsInGroup() then
		resumedAtLogin = false
		if self:IsHolder() and not self.preview and PLC.CouncilRules:IsMasterLootMethod()
			and PLC.CouncilRules:GetMasterLooterUnit() and not PLC.CouncilRules:AmIMasterLooter() then
			print(L["CHAT_PREFIX"] .. L["SESSION_NOT_MASTER_LOOTER"])
			self:End()
		end
	end
	if not IsInGroup() then
		syncAsked = false
	elseif restored and not syncAsked and not self:IsHolder() then
		syncAsked = true
		self:RequestSync()
	end
	if not self:IsHolder() then
		return
	end
	local council = self:ComputeCouncil()
	local before, after = table.concat(councilList(self.council), ","), table.concat(councilList(council), ",")
	if before ~= after then
		self.council = council
		PLC.Comms.Sync:SendCouncil(self.sessionId, councilList(council))
		self:notifySessionFrame()
	end
end

function Session:OnCouncilReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	self.council = councilSet(data.council)
	self:notifySessionFrame()
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
	if Session.preview then
		return -- the real session stays exactly as it was saved
	end
	-- Item numbers never start over, even once the list is empty and nothing else is saved: raiders
	-- keep awarded items by number.
	PLC.db.char.nextIdx = Session.nextIdx
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
			responseSet = Session.responseSet,
			isCollector = Session.isCollector,
			council = Session.council,
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
			preAwardGuid = entry.preAwardGuid,
			preAwardReason = entry.preAwardReason,
		}
	end
	return out
end

-- What every client should agree on while a review pass runs: the items sent in it, each marked
-- awarded or staged. The holder counts only what it sent in this pass (item.sentIn), since it keeps
-- older items the others never got. Everyone else counts all they have.
-- Everyone's answers for an item: the running pass's, or, once it's awarded, the ones it was awarded
-- on (item.votes), which a later pass doesn't clear, so they can still be looked at.
function Session:VotesFor(idx)
	local item = self.items[idx]
	return self.responses[idx] or (item and item.votes)
end

-- What a new pass keeps of the last one: its awarded items, with their votes, to look back at.
local function keepAwarded(items)
	local kept = {}
	for idx, item in pairs(items) do
		if item.awarded then
			kept[idx] = item
		end
	end
	return kept
end

local function itemSummary(items, sessionId)
	local parts = {}
	for idx, item in pairs(items) do
		if not sessionId or item.sentIn == sessionId then
			parts[#parts + 1] = idx .. (item.awarded and "a" or "") .. (item.preAwardGuid and "s" or "")
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- [guid] = how many items that player has answered.
local function responseCounts(responses)
	local counts = {}
	for _, byGuid in pairs(responses) do
		for guid, r in pairs(byGuid) do
			if r.response then
				counts[guid] = (counts[guid] or 0) + 1
			end
		end
	end
	return counts
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
		-- time later) -- keep the award/trade state we already know about. Only for the same item
		-- of the same pass: an awarded item kept from an earlier pass (keepAwarded) can have the
		-- same number, when the holder's numbering started over or the holder is someone else, and
		-- the new item must not inherit its award.
		local existing = Session.items[idx]
		if existing and (existing.sentIn ~= Session.sessionId or existing.itemString ~= entry.itemString) then
			existing = nil
		end
		if existing then
			entry.awarded = entry.awarded or existing.awarded
			entry.awardReason = entry.awardReason or existing.awardReason
			entry.awardedAt = entry.awardedAt or existing.awardedAt
			entry.traded = entry.traded or existing.traded
		end
		-- A catch-up carries awards made before it, so "items to collect" survives it.
		if entry.awarded and not entry.awardedAt then
			entry.awardedAt = time()
		end
		entry.link, entry.icon = reconstructItemVisuals(entry.itemString)
		entry.sentIn = Session.sessionId -- this pass's, for the heartbeat's comparison (itemSummary)
		entry.votes = entry.votes or (existing and existing.votes)
		Session.items[idx] = entry
		if not entry.link then
			pendingVisuals[idx] = true
		end
	end
	if next(pendingVisuals) then
		ensureItemInfoWatcher()
	end
end

-- Adds items built elsewhere in the wire shape, resolving their links and icons (Data/Preview.lua).
function Session:ApplyItems(items)
	applyReceivedItems(items)
end

local function startHeartbeat()
	if heartbeatTimerHandle then
		return
	end
	heartbeatTimerHandle = PLC:ScheduleRepeatingTimer(function()
		Session.lastHolderSeenAt = time()
		persist()
		PLC.Comms.Sync:SendHeartbeat(Session.sessionId, itemSummary(Session.items, Session.sessionId),
			responseCounts(Session.responses), PLC.db.profile.sessionHeartbeatSeconds)
	end, PLC.db.profile.sessionHeartbeatSeconds)
end

local function stopHeartbeat()
	if heartbeatTimerHandle then
		PLC:CancelTimer(heartbeatTimerHandle)
		heartbeatTimerHandle = nil
	end
end

-- Adds review loot to the backlog -- NOT gated on an active review session: collection is silent
-- background work across the whole raid, independent of whether Start()/End() has ever run yet.
-- `delivered`: Loot/AutoLoot.lua confirmed these reached this client's bags. Otherwise the ML is
-- looting by hand, and each entry waits (with its lootSlot) for Loot/BagTracker.lua to find its bag
-- copy. Filtered by Detection:IsReviewItem so trash doesn't get hoovered into the backlog.
-- Items Session:AddTrackedItem took from the bags stay claimable this long by the loot window's own
-- hand-out confirmation, which may arrive after the bag scan.
local CLAIM_SECONDS = 60

local function itemIDOf(itemString)
	return tonumber((itemString or ""):match("item:(%d+)"))
end

-- A recent item from the bags, not yet claimed by a hand-out, for this link's item.
local function findFromBags(link)
	local itemString = itemStringFromLink(link)
	for idx = 1, Session.nextIdx - 1 do
		local item = Session.items[idx]
		if item and item.fromBagsAt and not item.awarded and time() - item.fromBagsAt <= CLAIM_SECONDS
			and itemIDOf(item.itemString) == itemIDOf(itemString) then
			return item
		end
	end
	return nil
end

-- The loot window knows where it came from; the bags didn't.
local function claimFromBags(item, info)
	item.fromBagsAt = nil
	item.boss = item.boss or info.boss
	item.bossName = info.bossName or item.bossName
	item.instance = info.instance or item.instance
	item.difficultyName = info.difficultyName or item.difficultyName
	item.mapID = info.mapID or item.mapID
	item.difficultyID = info.difficultyID or item.difficultyID
	item.groupSize = info.groupSize or item.groupSize
	persist()
end

function Session:CollectDetectedItems(lootSlotInfo, delivered)
	local newlyCollected = {}
	local realLoot = false
	for _, info in pairs(lootSlotInfo) do
		realLoot = realLoot or PLC.Loot.Detection:IsReviewItem(info.link, info.quality)
	end
	if realLoot and self.preview then
		PLC.Preview:Stop(L["PREVIEW_ENDED_REAL_LOOT"])
	end

	-- In slot order, so two copies of one item are matched the same way every time.
	local slots = {}
	for lootSlot in pairs(lootSlotInfo) do
		table.insert(slots, lootSlot)
	end
	table.sort(slots)
	local matched = {}
	for _, lootSlot in ipairs(slots) do
		local info = lootSlotInfo[lootSlot]
		if PLC.Loot.Detection:IsReviewItem(info.link, info.quality) then
			local alreadyCollected = false
			-- Noted before and still lying in a corpse: the same item again, not a new one. Matched by
			-- item, not corpse or slot: reopening a corpse numbers its slots anew, and the Illidari
			-- Council's four corpses share one loot, so the same items showed on each. Each copy
			-- counts once.
			local noted
			for idx = 1, self.nextIdx - 1 do
				local existing = self.items[idx]
				if existing and not matched[existing] and existing.lootSlot and not existing.awarded
					and existing.link == info.link then
					noted = existing
					break
				end
			end
			if noted then
				matched[noted] = true
				alreadyCollected = true
				if delivered then
					-- Now it's in the master looter's bags: where Loot/BagTracker.lua finds it.
					noted.lootSlot = nil
					noted.bagged = true
				else
					noted.lootSlot = lootSlot
				end
			elseif delivered then
				-- The bag scan can see it land before the hand-out is confirmed, when the server is
				-- slow (a 25-player boss): it's already listed, from the bags.
				local found = findFromBags(info.link)
				if found then
					claimFromBags(found, info)
					alreadyCollected = true
				end
			end
			if not alreadyCollected then
				local idx = self.nextIdx
				self.nextIdx = self.nextIdx + 1
				local entry = {
					idx = idx,
					lootSlot = not delivered and lootSlot or nil,
					bagged = delivered or nil,
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
				matched[entry] = true -- a second copy in this window is a second item
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
	PLC.Preview:Stop(L["PREVIEW_ENDED_REAL_LOOT"])
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
		fromBagsAt = time(), -- see findFromBags: the loot window's confirmation may still come
		instance = instanceName,
		difficultyName = difficultyName,
		mapID = mapID,
		difficultyID = difficultyID,
		groupSize = groupSize,
	}
	-- Where it came from, if a recent loot window held it.
	local source = PLC.Loot.Detection.RecentSource and PLC.Loot.Detection:RecentSource(entry.link)
	if source then
		entry.boss, entry.bossName = source.boss, source.bossName
	end
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
	if not PLC.db.profile.autoStartSession or PLC.CouncilRules:IsRaiderMode() or self.state == "active" or not IsInGroup() then
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

-- Explicit holder action only -- there is no reactive "handle loot?" prompt (see
-- docs/SPECIFICATION.md §3 principle 9).
function Session:Start()
	if self.state == "active" then
		print(L["CHAT_PREFIX"] .. L["SESSION_ALREADY_ACTIVE"])
		return
	end
	if not self:CanStart() then
		print(L["CHAT_PREFIX"] .. L["SESSION_ONLY_ML_STARTS"])
		return
	end
	self.sessionId = UnitGUID("player") .. "-" .. time()
	self.owner = { guid = UnitGUID("player"), name = UnitName("player") }
	self.state = "active"
	self.responses = {}
	self.sentFirstBatch = false
	self.lastHolderSeenAt = time()
	self.responseTimeoutSeconds = PLC.db.profile.responseTimeoutSeconds
	self.responseSet = PLC.Responses:GetConfigured()
	self.council = self:ComputeCouncil()
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
	for idx in pairs(newItems) do
		if self.items[idx] then
			self.items[idx].sentIn = self.sessionId
		end
	end
	persist()
	if not self.sentFirstBatch then
		self.sentFirstBatch = true
		PLC.Comms.Sync:SendSessionStart(self.sessionId, self.owner, stripForTransmit(newItems), self.responseTimeoutSeconds, self.enchanterGuid, councilList(self.council), self.responseSet, self.preview)
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
	PLC.Preview:Stop(L["PREVIEW_ENDED_REAL_LOOT"])
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
-- SetPreAward (stage), never this. `reason` is "award" (trade to winnerGuid), "disenchant"
-- (winnerGuid is the designated Enchanter, Session:GetEnchanterGuid() -- still a real roster GUID,
-- still goes through the exact same trade-tracking/Announce path, just with different wording) or
-- "bank" (winnerGuid is the holder, who keeps it: this only records it, with nothing to trade).
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
	item.winnerName, item.winnerClass = winnerEntry.name, winnerEntry.class -- for Loot Trades' results
	item.votes = self.responses[idx] or item.votes
	item.awardedAt = time() -- feeds UI/TradeFrame.lua's "awarded Xm ago" timer
	item.preAwardGuid = nil
	item.preAwardReason = nil
	persist()
	PLC.Comms.Sync:SendAward(self.sessionId, item.idx, winnerGuid, reason)
	-- Who got what shows in everyone's Loot Trades window (UI/TradeFrame.lua); raid chat gets one
	-- line for the whole Award All (AwardAllPreAwarded), not one per item.
	if PLC.History and PLC.History.RecordAward and not self.preview then
		PLC.History:RecordAward(item, winnerGuid, reason)
	end
	-- A genuine self-AWARD (not disenchant) -- the item's already sitting right where it needs to
	-- be, so there's nothing left to do at all; auto-complete it so UI/TradeFrame.lua never shows
	-- it in both "items to hand out" and "items to collect" forever, and clicking Trade on it never
	-- tries to InitiateTrade with yourself. A self-DISENCHANT is deliberately NOT included here --
	-- the item is in the holder's bags, yes, but disenchanting it is a real action this addon
	-- doesn't perform for them (no "auto-cast Disenchant" feature), so it still needs to show up as
	-- a reminder. Loot/Trade.lua's own bag-watch picks it up automatically once they actually
	-- disenchant it, the same way a real trade's completion is detected. Banking has nothing left
	-- to do either: that's the point of it.
	if reason == "bank" or (reason == "award" and winnerGuid == UnitGUID("player")) then
		self:MarkItemTraded(idx)
	end
	self:notifyVotingFrame(item.idx)
	self:notifySessionFrame()
	self:notifyTradeFrame()
	return true
end

-- Holder-only staging -- THE way every decision gets made (see UI/VotingFrame.lua's Award/
-- Disenchant buttons), committed only in bulk via AwardAllPreAwarded below. Calling this again (a
-- different candidate, or the other reason) just overwrites the previous pick. Broadcast ("stage")
-- so the rest of the council sees the review progress live; nothing is final until Award All.
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
	PLC.Comms.Sync:SendStage(self.sessionId, idx, winnerGuid, item.preAwardReason)
	self:notifyVotingFrame(idx)
	self:notifySessionFrame()
end

function Session:OnStageReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId then
		return
	end
	local item = self.items[data.idx]
	if not item or item.awarded then
		return
	end
	item.preAwardGuid = data.guid
	item.preAwardReason = data.reason
	self:notifyVotingFrame(data.idx)
	self:notifySessionFrame()
end

-- Removes not-yet-awarded items. Outside a review pass this is local only (nothing was broadcast
-- yet); during one, only the holder can do it and the removal is broadcast (item_remove) so every
-- candidate's Loot Response window and every council grid drop the item too.
local function removeItems(idxs)
	local removed = {}
	for _, idx in ipairs(idxs) do
		local item = Session.items[idx]
		-- Awarded and handed over, it's finished: it can go too. Awarded and not yet handed over,
		-- Loot Trades still needs it.
		if item and (not item.awarded or item.traded) then
			Session.items[idx] = nil
			Session.responses[idx] = nil
			table.insert(removed, idx)
		end
	end
	return removed
end

function Session:CanRemoveItems()
	return self:CanManage()
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

-- Every item that isn't waiting to be handed over: not awarded, or awarded and traded. Ends an active
-- review pass if that leaves it with nothing to review.
function Session:RemoveAllItems()
	local idxs = {}
	for idx, item in pairs(self.items) do
		if not item.awarded or item.traded then
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
	-- In item order, so raid chat lists them the way the Loot Session window does. Everything goes
	-- out in one message (Comms/Sync.lua:BeginBatch), and the session's end right after it.
	local idxs = {}
	for idx, item in pairs(self.items) do
		if item.preAwardGuid and not item.awarded then
			table.insert(idxs, idx)
		end
	end
	table.sort(idxs)
	local count = 0
	PLC.Comms.Sync:BeginBatch()
	local ok, err = pcall(function()
		for _, idx in ipairs(idxs) do
			local item = self.items[idx]
			if self:AwardBaggedItem(idx, item.preAwardGuid, item.preAwardReason) then
				count = count + 1
			end
		end
	end)
	-- Whatever was awarded goes out, even if something went wrong on the way. The holder hears when
	-- it has reached the raid, so nobody logs off with the awards still waiting to leave.
	local preview = self.preview
	PLC.Comms.Sync:FlushBatch(self.sessionId, count > 0 and not preview and function()
		print(L["CHAT_PREFIX"] .. string.format(L["SESSION_AWARDS_SENT"], count))
	end or nil)
	if count > 0 then
		PLC.Loot.Announce:AnnounceAwards(count)
	end
	if not ok then
		error(err, 0)
	end
	print(L["CHAT_PREFIX"] .. string.format(L["SESSION_AWARD_ALL_RESULT"], count))
	-- Award All is now also the deliberate "I'm done reviewing" signal, not just a bulk-commit --
	-- confirmed explicitly (the alternative, leaving End Session as a separate step so voting
	-- could keep going on other items, was declined). End() already handles broadcasting
	-- session_end, stopping the heartbeat, and pruning -- nothing else here needs to change.
	self:End()
	-- Loot Trades: what's to hand out, and who got what.
	if count > 0 and PLC.UI and PLC.UI.TradeFrame and PLC.UI.TradeFrame.Open then
		PLC.UI.TradeFrame:Open()
	end
end

-- A practice session sets the real state aside; a real one ends any practice run in progress.
local function matchPreviewState(preview)
	if preview then
		PLC.Preview:Enter()
	else
		PLC.Preview:Leave()
	end
end

-- Whether `sender` may be running a loot session. With Master Loot on and a master looter known,
-- only the master looter: anyone else still holding an old pass (left running, resumed at login)
-- would otherwise pull the whole raid onto it. Without Master Loot, or before the group is known,
-- anyone, as before.
local function mayHold(sender)
	if not sender or not PLC.CouncilRules:IsMasterLootMethod() then
		return true
	end
	local unit = PLC.CouncilRules:GetMasterLooterUnit()
	local name = unit and UnitName(unit)
	if not name or name == UNKNOWNOBJECT then
		return true
	end
	return strlower((strsplit("-", name))) == strlower((strsplit("-", sender)))
end

function Session:OnSessionStartReceived(data, sender)
	if self:IsHolder() or not mayHold(sender) then
		return
	end
	matchPreviewState(data.preview)
	self.sessionId = data.sessionId
	self.owner = data.owner
	self.enchanterGuid = data.enchanterGuid
	self.state = "active"
	self.items = keepAwarded(self.items)
	self.responses = {}
	self.lastHolderSeenAt = time()
	lastHeartbeatAt = time()
	itemsBehindLast, previousResponded, mineAtLastBeat = false, nil, nil
	-- The holder's configured timeout wins for everyone, never the receiving client's own
	-- profile.responseTimeoutSeconds.
	self.responseTimeoutSeconds = data.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	-- The holder's buttons win too. A holder on an older version sends none, and uses the defaults.
	self.responseSet = PLC.Responses.Sanitize(data.responseSet) or PLC.Responses:GetDefaults()
	self.council = data.council and councilSet(data.council) or nil
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
	if PLC.UI and PLC.UI.LootTimersFrame and PLC.UI.LootTimersFrame.OnSessionUpdated then
		PLC.UI.LootTimersFrame:OnSessionUpdated()
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

-- Several answers in one message: an item that dropped twice, or everything this character can't
-- use (Data/AutoPass.lua). One by one they'd queue behind the server's limit of 1 message a second,
-- with the player's own answers behind them. answers: { [idx] = { response, note } }.
function Session:SendMyResponses(answers)
	if self.state ~= "active" then
		return
	end
	local guid = UnitGUID("player")
	local sent = {}
	for idx, answer in pairs(answers) do
		if self.items[idx] and answer.response then
			self.responses[idx] = self.responses[idx] or {}
			self.responses[idx][guid] = { response = answer.response, note = answer.note }
			sent[idx] = { response = answer.response, note = answer.note }
		end
	end
	if not next(sent) then
		return
	end
	PLC.Comms.Sync:SendResponses(self.sessionId, guid, sent)
	for idx in pairs(sent) do
		self:notifyVotingFrame(idx, guid)
	end
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
		local winner = PLC.Roster:Get(data.winnerGuid)
		item.winnerName, item.winnerClass = winner and winner.name, winner and winner.class
		item.votes = self.responses[data.idx] or item.votes
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
	PLC.Preview:CheckFinished()
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

function Session:OnHeartbeatReceived(data, sender)
	if not data.sessionId or self:IsHolder() or not mayHold(sender) then
		return
	end
	lastHeartbeatAt = time()
	holderEvery = tonumber(data.every) or holderEvery
	if data.sessionId ~= self.sessionId or self.state == "inactive" then
		-- A review pass this client never heard start, from a loading screen for example.
		self:CatchUp()
		return
	end
	if self.state ~= "active" then
		return
	end
	self.lastHolderSeenAt = data.ts or time()
	if type(data.items) ~= "string" then
		return -- a holder on an older version, with nothing to compare
	end

	local mine = UnitGUID("player")
	local counts = responseCounts(self.responses)
	local responded = {}
	if type(data.responded) == "table" then
		for guid, count in pairs(data.responded) do
			responded[guid] = tonumber(count) or 0
		end
	end
	-- Items only change through the holder's own messages, so a different summary means one got
	-- lost, or that one is still arriving: a long one comes in pieces, and the throttle library can
	-- let a short heartbeat past it. Two in a row, then.
	local itemsBehind = data.items ~= itemSummary(self.items, self.sessionId)
	-- Answers come from everyone, so one can always be on its way when a heartbeat arrives. What's
	-- missing is what the holder already had a heartbeat ago and still hasn't come, and, the other
	-- way round, answers this client gave before the last heartbeat that the holder still lacks.
	local answersBehind = false
	for guid, count in pairs(previousResponded or {}) do
		if guid ~= mine and (counts[guid] or 0) < count then
			answersBehind = true
		end
	end
	local holderMissesMine = (responded[mine] or 0) < (mineAtLastBeat or 0)
	if (itemsBehind and itemsBehindLast) or answersBehind then
		self:CatchUp()
	end
	if holderMissesMine then
		self:ResendMyResponses()
	end
	itemsBehindLast, previousResponded, mineAtLastBeat = itemsBehind, responded, counts[mine] or 0
end

-- Asks the holder for the whole session, at most every CATCH_UP_COOLDOWN seconds.
function Session:CatchUp()
	if self:IsHolder() or not IsInGroup() or time() - lastCatchUp < CATCH_UP_COOLDOWN then
		return
	end
	lastCatchUp = time()
	self:RequestSync()
end

-- Every answer this player has given in the session, again: the holder didn't have them all.
function Session:ResendMyResponses()
	local mine = UnitGUID("player")
	local own = {}
	for idx, byGuid in pairs(self.responses) do
		local r = byGuid[mine]
		if r and r.response and self.items[idx] then
			own[idx] = { response = r.response, note = r.note }
		end
	end
	if next(own) then
		PLC.Comms.Sync:SendResponses(self.sessionId, mine, own)
	end
end

function Session:OnResponsesReceived(data)
	if not data.sessionId or data.sessionId ~= self.sessionId or type(data.responses) ~= "table" or not data.guid then
		return
	end
	for idx, r in pairs(data.responses) do
		if self.items[idx] and type(r) == "table" and r.response then
			self.responses[idx] = self.responses[idx] or {}
			self.responses[idx][data.guid] = { response = r.response, note = r.note }
			self:notifyVotingFrame(idx, data.guid)
		end
	end
	if self:IsHolder() then
		persist()
	end
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

	-- Nothing leaves by itself: awarded items stay, with the votes they were awarded on, so the
	-- council can look back at who wanted what (a spare token, a mistake), until the master looter
	-- removes them (Remove, Remove All). Not-yet-awarded items carry forward to the next Start();
	-- picks staged but never committed stop showing as "Staged".
	for _, item in pairs(self.items) do
		item.preAwardGuid = nil
		item.preAwardReason = nil
	end
	self.isCollector = next(self.items) ~= nil
	persist()
	self:notifySessionFrame()
	self:notifyLootFrame()
	self:notifyTradeFrame()

	print(L["CHAT_PREFIX"] .. L["SESSION_ENDED"])
	PLC.Preview:CheckFinished()
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
	awaitingSync = true
	PLC.Comms.Sync:SendSyncRequest(UnitGUID("player"))
end

-- Everything a client needs to be where everyone else is: the items sent in this pass, with
-- their awards, and every answer so far.
local function sessionSnapshot()
	local sent = {}
	for idx, item in pairs(Session.items) do
		if item.sentIn == Session.sessionId then
			sent[idx] = item
		end
	end
	local items = stripForTransmit(sent)
	for idx, entry in pairs(items) do
		entry.awarded, entry.awardReason, entry.traded = sent[idx].awarded, sent[idx].awardReason, sent[idx].traded
	end
	return {
		sessionId = Session.sessionId,
		owner = Session.owner,
		enchanterGuid = Session.enchanterGuid,
		items = items,
		responses = Session.responses,
		lastHolderSeenAt = Session.lastHolderSeenAt,
		responseTimeoutSeconds = Session.responseTimeoutSeconds,
		responseSet = Session.responseSet,
		preview = Session.preview or nil,
		council = councilList(Session.council),
	}
end

-- One answer, to the whole group, for everyone who asked in the last SYNC_GATHER seconds: a raid
-- zoning out together costs one answer instead of one each. And never a second while one is still
-- going out (a whole session is a dozen messages or more, at the server's 1 a second): whoever asks
-- meanwhile gets the next one, once this one is out. Before, a raid's loading screens ending one by
-- one queued an answer each, minutes of them, in front of the session's own messages.
local syncInFlight = false
local answerSyncRequests

local function scheduleSyncAnswer()
	if not syncInFlight then
		syncAnswerTimer = syncAnswerTimer or PLC:ScheduleTimer(answerSyncRequests, SYNC_GATHER)
	end
end

function answerSyncRequests()
	syncAnswerTimer = nil
	if not next(syncRequesters) or not Session:IsHolder() then
		wipe(syncRequesters)
		return
	end
	wipe(syncRequesters)
	syncInFlight = true
	PLC.Comms.Sync:SendSyncData(sessionSnapshot(), nil, function()
		syncInFlight = false
		if next(syncRequesters) then
			scheduleSyncAnswer()
		end
	end)
end

function Session:OnSyncRequestReceived(data, sender)
	if self:IsHolder() then
		syncRequesters[sender or "?"] = true
		scheduleSyncAnswer()
	elseif self:IsOwner() and self.sessionId and (self.state == "ended" or self.state == "force_ended") then
		-- Someone still thinks the review pass this client ran is on: it missed the end.
		PLC.Comms.Sync:SendSyncData({ sessionId = self.sessionId, ended = true }, sender)
	end
end

function Session:OnSyncDataReceived(data, sender)
	if self:IsHolder() or not data.sessionId then
		return
	end
	if data.ended then
		if data.sessionId == self.sessionId and self.state == "active" then
			awaitingSync = false
			self.state = "ended"
			self:notifySessionFrame()
			self:notifyLootFrame()
			self:notifyTradeFrame()
		end
		return
	end
	if not mayHold(sender) then
		return
	end
	-- Sent to the whole group when several asked at once: it's only for those who did, or who
	-- don't have this session.
	if not awaitingSync and data.sessionId == self.sessionId and self.state == "active" then
		return
	end
	awaitingSync = false
	-- This client's own answers, in case the holder doesn't have them yet.
	local mine = UnitGUID("player")
	local own = {}
	if data.sessionId == self.sessionId then
		for idx, byGuid in pairs(self.responses) do
			if byGuid[mine] then
				own[idx] = byGuid[mine]
			end
		end
	end
	matchPreviewState(data.preview)
	self.sessionId = data.sessionId
	self.owner = data.owner
	self.enchanterGuid = data.enchanterGuid
	self.state = "active"
	self.items = keepAwarded(self.items)
	self.responseTimeoutSeconds = data.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	self.responseSet = PLC.Responses.Sanitize(data.responseSet) or PLC.Responses:GetDefaults()
	applyReceivedItems(data.items)
	self.responses = data.responses or {}
	local missing = {}
	for idx, r in pairs(own) do
		if self.items[idx] and not (self.responses[idx] and self.responses[idx][mine]) then
			self.responses[idx] = self.responses[idx] or {}
			self.responses[idx][mine] = r
			missing[idx] = { response = r.response, note = r.note }
		end
	end
	if next(missing) then
		PLC.Comms.Sync:SendResponses(self.sessionId, mine, missing)
	end
	itemsBehindLast, previousResponded, mineAtLastBeat = false, nil, nil
	lastHeartbeatAt = time()
	self.lastHolderSeenAt = data.lastHolderSeenAt or time()
	self.council = data.council and councilSet(data.council) or nil
	print(L["CHAT_PREFIX"] .. L["SESSION_SYNCED"])
	-- A late joiner catching up never got the session-start broadcast that would otherwise have
	-- triggered this -- announce our gear and professions now so we're not a permanent gap in the
	-- group's data for this session (see Data/Gear.lua, Data/Professions.lua).
	PLC.Gear:BroadcastOwn()
	PLC.Professions:BroadcastOwn()
	self:notifyLootFrame()
	self:notifySessionFrame()
end

-- A running pass older than this isn't resumed at login: it was left running by mistake.
local STALE_SECONDS = 6 * 3600

local function restoreFromSaved()
	Session.nextIdx = PLC.db.char.nextIdx or 1
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
	Session.nextIdx = math.max(Session.nextIdx, saved.nextIdx or 1)
	Session.responseTimeoutSeconds = saved.responseTimeoutSeconds or PLC.db.profile.responseTimeoutSeconds
	Session.responseSet = PLC.Responses.Sanitize(saved.responseSet)
	Session.isCollector = saved.isCollector or false
	Session.council = saved.council

	local isOwner = saved.owner and saved.owner.guid == UnitGUID("player")
	-- Only a save explicitly marked active resumes. Saves from before state was persisted
	-- (state == nil) used to be treated as active, which resurrected long-dead sessions on every
	-- reload and made that client ignore everyone else's session_start as the "holder."
	local fresh = time() - (saved.lastHolderSeenAt or 0) <= STALE_SECONDS
	if isOwner and saved.sessionId and saved.state == "active" and fresh then
		-- A formal review pass was active -- resume it fully, heartbeat included.
		Session.state = "active"
		Session.sentFirstBatch = true
		Session.responseSet = Session.responseSet or PLC.Responses:GetConfigured()
		resumedAtLogin = true
		startHeartbeat()
		print(L["CHAT_PREFIX"] .. L["SESSION_RESTORED"])
	elseif isOwner and saved.sessionId and saved.state == "active" then
		-- Left running hours ago: it's over. The items stay, for the next pass.
		Session.state = "ended"
		Session.isCollector = next(Session.items) ~= nil
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

-- After a loading screen: whatever was sent meanwhile never arrived. Logging in and reloading are
-- caught up from OnRosterRebuilt instead.
PLC.Events:RegisterHandler("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
	if not isInitialLogin and not isReloadingUi then
		PLC:ScheduleTimer(function()
			Session:CatchUp()
		end, ZONE_SETTLE)
	end
end)

-- The holder's heartbeat stopped: it ended the pass and that never arrived, or it's offline.
local function checkHolderSilence()
	if Session:IsHolder() or Session.state ~= "active" or not lastHeartbeatAt then
		return
	end
	local every = holderEvery or PLC.db.profile.sessionHeartbeatSeconds
	if time() - lastHeartbeatAt > every * SILENT_BEATS then
		Session:CatchUp()
	end
end

-- The resync a client needs after logging in or reloading is requested from OnRosterRebuilt.
PLC:RegisterOnEnable(function()
	restoreFromSaved()
	restored = true
	PLC:ScheduleRepeatingTimer(checkHolderSilence, 5)
end)

-- The two session lifecycle actions without a button: resync from the holder, and the
-- stuck-session escape hatch (spec §5.1).
PLC:RegisterSlashCommand("sync", L["SLASH_SYNC"], function()
	Session:RequestSync()
end)

PLC:RegisterSlashCommand("forceend", L["SLASH_FORCEEND"], function()
	Session:ForceEnd()
end)

-- Real utility command, not a debug stub -- lets the ML add an item that didn't come through
-- their own loot window (a world drop someone already picked up, etc).
PLC:RegisterSlashCommand("additem", L["SLASH_ADDITEM"], function(args)
	local itemArg = args:match("^%s*(.-)%s*$")
	if itemArg == "" then
		print(L["CHAT_PREFIX"] .. L["SESSION_ADDITEM_USAGE"])
		return
	end
	Session:AddManualItem(tonumber(itemArg) or itemArg)
end)
