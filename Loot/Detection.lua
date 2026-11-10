local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local Detection = {}
PLC.Loot.Detection = Detection

-- Everything here is purely event-driven off LOOT_READY/LOOT_SLOT_CLEARED/LOOT_CLOSED/
-- START_LOOT_ROLL. This file never touches GroupLootFrame/LootFrame or any other addon's loot
-- buttons (see docs/SPECIFICATION.md §2/§3 principle 3).

Detection.lootSlotInfo = {} -- [slotIndex] = { link, icon, quantity, quality, boss, looted }

Detection.RECIPE_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local MIN_RECIPE_QUALITY = 2 -- uncommon

local warnedThisSession = false

-- Good enough to review? Anything at db.profile.lootThreshold or better, plus patterns of any
-- quality from uncommon up.
function Detection:IsReviewQuality(link, quality)
	quality = quality or 0
	local classID = link and select(6, C_Item.GetItemInfoInstant(link))
	if classID == self.RECIPE_CLASS_ID then
		return quality >= MIN_RECIPE_QUALITY
	end
	return quality >= PLC.db.profile.lootThreshold
end

-- Is this item loot the raid reviews? The one rule for both ways an item enters the backlog:
-- Session:CollectDetectedItems and Loot/BagTracker.lua's bag scan.
function Detection:IsReviewItem(link, quality)
	return self:IsReviewQuality(link, quality) and not PLC.Loot.AutoLoot:IsExcludedFromReview(link)
end

local function scanLootSlots()
	wipe(Detection.lootSlotInfo)

	if not IsInInstance() and not PLC.db.profile.autoLoot.outsideInstances then
		return
	end
	local numItems = GetNumLootItems()
	if not numItems or numItems <= 0 then
		return
	end

	-- Captured once per scan (the same for every item looted together), not re-derived per item --
	-- purely for Data/History.lua's loot-history recording later (matching RCLootCouncil_Classic's
	-- own instance/mapID/difficultyID/groupSize columns), nothing else in this addon reads these.
	-- instanceID (8th return) is RCLootCouncil's "mapID"; instanceGroupSize (9th) is its
	-- "groupSize" -- NOT maxPlayers (5th), which is the instance's fixed capacity for its
	-- difficulty, not how many are actually in the group right now.
	local instanceName, _, difficultyID, difficultyName, _, _, _, mapID, groupSize = GetInstanceInfo()

	local pendingRetry = false
	for i = 1, numItems do
		if LootSlotHasItem(i) then
			local icon, name, quantity, currencyID, quality = GetLootSlotInfo(i)
			if currencyID and currencyID > 0 then
				-- currency, not a lootable item for council purposes
			elseif not icon then
				-- item info not cached client-side yet; retry next frame
				pendingRetry = true
			else
				local link = GetLootSlotLink(i)
				local sourceGUID = GetLootSourceInfo(i)
				-- Resolved only when the loot source is also the player's current target (the
				-- overwhelmingly common case -- you loot what you just killed/targeted); falls
				-- back to the raw GUID otherwise rather than leaving it blank. Only used for
				-- Data/History.lua's "boss" column -- nothing else in this addon reads a boss name.
				local bossName = sourceGUID
				if sourceGUID and UnitGUID("target") == sourceGUID then
					bossName = UnitName("target") or sourceGUID
				end
				Detection.lootSlotInfo[i] = {
					link = link,
					icon = icon,
					quantity = quantity,
					quality = quality,
					boss = sourceGUID,
					bossName = bossName,
					instance = instanceName,
					difficultyName = difficultyName,
					mapID = mapID,
					difficultyID = difficultyID,
					groupSize = groupSize,
					looted = false,
				}
			end
		end
	end

	if pendingRetry then
		PLC:ScheduleTimer(scanLootSlots, 0)
	end
end

local raiderModeHinted = false

-- What the loot windows of the last RECENT_SECONDS held, by item: where an item came from, for loot
-- that reaches the bags some other way (Blizzard's own assign list, a hand-out the server confirmed
-- late), which listed "Unknown" as its boss in the history.
local RECENT_SECONDS = 600
local recent = {} -- [itemID] = { info, at }

local function rememberSources()
	local now = time()
	for _, info in pairs(Detection.lootSlotInfo) do
		local itemID = info.link and tonumber(info.link:match("item:(%d+)"))
		if itemID then
			recent[itemID] = { info = info, at = now }
		end
	end
end

-- The loot window info of a recent corpse that held this item, or nil.
function Detection:RecentSource(link)
	local itemID = link and tonumber(tostring(link):match("item:(%d+)"))
	local seen = itemID and recent[itemID]
	if seen and time() - seen.at <= RECENT_SECONDS then
		return seen.info
	end
	return nil
end

local function onLootReady()
	scanLootSlots()
	rememberSources()

	-- Silent background collection (Loot/AutoLoot.lua) -- not gated on an active review session,
	-- only on actually being the live master looter. The full Loot Session window stays closed on
	-- purpose: across a multi-hour raid this fires constantly, and the whole point of this workflow
	-- is that review happens once, deliberately, later -- not on every drop. The small
	-- UI/LootTimersFrame.lua list is what shows the ML what was collected and how long it can wait.
	-- With auto loot off (or Shift held) the ML loots by hand, so what's here is only noted, to be
	-- matched with its bag copy by Loot/BagTracker.lua when it arrives.
	-- In raider mode the loot is left alone, for the player or another addon, with one reminder
	-- per login of why.
	if not PLC.CouncilRules:AmIMasterLooter() then
		return
	end
	if PLC.CouncilRules:IsRaiderMode() then
		if not raiderModeHinted then
			raiderModeHinted = true
			print(L["CHAT_PREFIX"] .. L["RAIDER_MODE_HINT"])
		end
	elseif not PLC.Loot.AutoLoot:Begin() then
		PLC.Session:CollectDetectedItems(Detection.lootSlotInfo)
	end
end

local function onLootSlotCleared(eventName, slot)
	local info = Detection.lootSlotInfo[slot]
	if info then
		info.looted = true
	end
	PLC.Loot.Award:OnLootSlotCleared(slot)
end

local function onLootClosed()
		PLC.Loot.AutoLoot:End()
end

-- Phase 1 intentionally does not port the full auto-pass/auto-roll bitfield logic upstream
-- builds around START_LOOT_ROLL -- that's deferred past Phase 1 (see plan §4a). We only warn
-- council members once per session if the group's loot method isn't Master Loot.
local function onStartLootRoll()
	if warnedThisSession then
		return
	end
	if PLC.CouncilRules:IsMasterLootMethod() then
		return
	end
	local myGuid = UnitGUID("player")
	local myEntry = PLC.Roster and myGuid and PLC.Roster:Get(myGuid)
	if myEntry and myEntry.council then
		warnedThisSession = true
		print(L["CHAT_PREFIX"] .. L["LOOT_METHOD_NOT_MASTER"])
	end
end

PLC.Events:RegisterHandler("LOOT_READY", onLootReady)
PLC.Events:RegisterHandler("LOOT_SLOT_CLEARED", onLootSlotCleared)
PLC.Events:RegisterHandler("LOOT_CLOSED", onLootClosed)
PLC.Events:RegisterHandler("START_LOOT_ROLL", onStartLootRoll)
