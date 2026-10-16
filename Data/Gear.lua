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

-- Which inventory slot(s) a loot item's own equipLoc competes against -- shared by
-- UI/VotingFrame.lua's gear-comparison columns and Data/History.lua's itemReplaced1/2 history
-- recording, moved here (not duplicated in both) since it's really a property of gear/slots, not
-- of either caller. Covers every equipLoc EXCEPT the weapon/offhand types directly -- those need a
-- per-candidate check (see DUAL_WEAPON_SLOT_TYPES/SlotsForEquipLoc below), since whether a given
-- candidate has an offhand slot in use at all depends on what they personally have equipped, not
-- on the loot item alone. An equipLoc with no entry here and not in DUAL_WEAPON_SLOT_TYPES
-- (non-equippable loot) simply has nothing to compare against -- not an error case.
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	-- A two-handed loot item always competes against both weapon slots regardless of what the
	-- candidate currently has -- equipping it gives up whatever's in both, 1h+offhand or another
	-- 2h alike, so both are always worth seeing.
	INVTYPE_2HWEAPON = { 16, 17 },
	INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
}

-- An offhand item or a one-handed weapon always competes against BOTH weapon slots by default --
-- either could be the one that actually gets replaced -- EXCEPT when this specific candidate
-- currently has a two-handed weapon equipped, where there's no real offhand slot in use (it's
-- empty), so only the mainhand (16, where the 2H weapon sits) is shown. This has to be resolved
-- per CANDIDATE, not once per item (unlike everything in EQUIP_SLOTS above) -- two different
-- candidates being compared against the same loot item can have different weapon setups.
local DUAL_WEAPON_SLOT_TYPES = {
	INVTYPE_WEAPON = true,
	INVTYPE_WEAPONMAINHAND = true,
	INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_SHIELD = true,
	INVTYPE_HOLDABLE = true,
}

function Gear:SlotsForEquipLoc(guid, equipLoc)
	if not DUAL_WEAPON_SLOT_TYPES[equipLoc] then
		return EQUIP_SLOTS[equipLoc]
	end
	local mainhandItemID = self:GetEquipped(guid, 16)
	if mainhandItemID then
		-- Only checking what TYPE of weapon this is, not resolving it for display (that's
		-- ResolveItem below, which handles "not cached yet" with its own retry) -- if this
		-- particular GetItemInfo call happens to return nothing yet, the fallback below (showing
		-- both slots) is harmless and self-corrects once the mainhand's own resolution lands.
		local _, _, _, _, _, _, _, _, mainhandEquipLoc = C_Item.GetItemInfo(mainhandItemID)
		if mainhandEquipLoc == "INVTYPE_2HWEAPON" then
			return { 16 }
		end
	end
	return { 16, 17 }
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
