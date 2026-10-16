local ADDON_NAME, PLC = ...

-- Self-reported equipped gear, synced over the addon's own comms channel at session start --
-- deliberately NOT Blizzard's Inspect API (NotifyInspect/INSPECT_READY), which only works in
-- range and is rate-limited. Modeled directly on Data/Presence.lua: every candidate announces
-- their OWN gear, which they always have perfect, instant, local access to
-- (GetInventoryItemID("player", ...)), rather than this client trying to inspect everyone else's.
-- Same tradeoff presence/response data already has: only works for candidates who also have the
-- addon, not a new category of "doesn't work for some people."
local Gear = {}
PLC.Gear = Gear

-- The 17 standard equippable gear slots -- skips shirt (4) and tabard (19), cosmetic and never
-- loot-council-relevant.
local SLOT_IDS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

Gear.equipped = {} -- [guid] = { [slotID] = itemID }, in-memory only -- repopulated by the next
-- sync (a new session start, or a late joiner catching up via Session:RequestSync), same as
-- Data/Presence.lua's lastSeen never persisting across a reload either.

function Gear:GetEquipped(guid, slotID)
	local g = self.equipped[guid]
	return g and g[slotID]
end

-- Mirrors Presence:notifyVotingFrame (Data/Presence.lua) exactly -- only the currently-shown
-- item's rows need a nudge; a full rebuild re-evaluates every row's gear lookup, which is cheap
-- at normal roster sizes.
function Gear:notifyVotingFrame()
	local VotingFrame = PLC.UI and PLC.UI.VotingFrame
	local panel = VotingFrame and VotingFrame.activePanel
	if panel and panel.currentIdx then
		panel:OnItemUpdated(panel.currentIdx)
	end
end

function Gear:OnGearReceived(data)
	if not data.guid or not data.slots then
		return
	end
	self.equipped[data.guid] = data.slots
	self:notifyVotingFrame()
end

-- Called whenever a session starts or a late joiner catches up (see Data/Session.lua) -- never
-- periodically, by design: gear doesn't change mid-raid often enough to be worth the comms
-- traffic, and the user explicitly asked for "sync whenever the session is getting started."
function Gear:BroadcastOwn()
	local slots = {}
	for _, slotID in ipairs(SLOT_IDS) do
		local itemID = GetInventoryItemID("player", slotID)
		if itemID then
			slots[slotID] = itemID
		end
	end
	local myGuid = UnitGUID("player")
	-- Cached locally too, not just sent -- so the broadcaster's own candidate row works
	-- immediately, without waiting on a round-trip through the group channel back to itself.
	self.equipped[myGuid] = slots
	PLC.Comms.Sync:SendGear(myGuid, slots)
end

-- Resolving an equipped item's visuals/ilvl from a bare itemID mirrors Data/Session.lua's own
-- reconstructItemVisuals/resolvePendingVisuals/ensureItemInfoWatcher pattern (Data/Session.lua:
-- 90-138) for the exact same reason: GetItemInfo returns nothing on the first call for an item
-- this client has never seen, and the answer only arrives later via GET_ITEM_INFO_RECEIVED. A
-- self-contained copy here, not a shared helper -- this never risks touching Session.lua's
-- already-working code.
local pendingItemIDs = {} -- [itemID] = true
local itemInfoWatcher

local function resolvePendingItemIDs()
	local resolvedAny = false
	for itemID in pairs(pendingItemIDs) do
		local name = C_Item.GetItemInfo(itemID)
		if name then
			pendingItemIDs[itemID] = nil
			resolvedAny = true
		end
	end
	if resolvedAny then
		Gear:notifyVotingFrame()
	end
end

local function ensureItemInfoWatcher()
	if itemInfoWatcher then
		return
	end
	itemInfoWatcher = CreateFrame("Frame")
	itemInfoWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	itemInfoWatcher:SetScript("OnEvent", resolvePendingItemIDs)
end

-- UI/VotingFrame.lua's one entry point for turning a raw equipped itemID into something
-- displayable -- returns nil for all three if not resolved yet (and queues a retry), so call
-- sites never need to know the watcher exists.
function Gear:ResolveItem(itemID)
	if not itemID then
		return nil, nil, nil
	end
	local name, link, _, itemLevel, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
	if not name then
		pendingItemIDs[itemID] = true
		ensureItemInfoWatcher()
		return nil, nil, nil
	end
	return link, icon, itemLevel
end
