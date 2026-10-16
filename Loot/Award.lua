local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local Award = {}
PLC.Loot.Award = Award

local LOOT_TIMEOUT = 5 -- seconds; matches the verified upstream constant (ml_core.lua:35)

Award.pendingQueue = {} -- array of { slot, link, winnerGuid, winnerName, reason, timerHandle }

-- Mirrors the verified CanGiveLoot rule set (ml_core.lua:667-721) client-side, narrowed to the
-- one path this addon still uses it for: the ML self-looting a bagged item into their own bags
-- (see TryAward below). Under the bagged-item workflow, awarding to anyone else is
-- PLC.Session:AwardBaggedItem recording a decision -- never a live GiveMasterLoot transfer, the
-- deliberate no-trade-automation choice -- so this never runs for any winnerGuid but the ML's own
-- anymore. Returns true, or false + a localized cause string.
function Award:CanGiveLoot(slot, winnerGuid)
	local Detection = PLC.Loot.Detection
	local info = Detection.lootSlotInfo[slot]
	if not info then
		return false, L["CANGIVE_NO_SLOT"]
	end
	if not Detection.lootOpen then
		return false, L["CANGIVE_LOOT_CLOSED"]
	end

	-- The slot must still hold the same item -- loot windows can change between an award being
	-- queued (e.g. by a council vote) and the moment it's actually attempted.
	if GetLootSlotLink(slot) ~= info.link then
		return false, L["CANGIVE_ITEM_CHANGED"]
	end

	if not PLC.Roster:Get(winnerGuid) then
		return false, L["CANGIVE_NOT_IN_GROUP"]
	end

	local getFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	local freeSlots = 0
	for bag = 0, NUM_BAG_SLOTS do
		freeSlots = freeSlots + (getFreeSlots(bag) or 0)
	end
	if freeSlots <= 0 then
		return false, L["CANGIVE_NO_BAG_SPACE"]
	end
	return true
end

-- The funnel for the ML's own silent self-collection (see docs/SPECIFICATION.md §3 principle 4;
-- Data/Session.lua:CollectDetectedItems is the only caller, always with the ML's own GUID).
-- Validates first, then loots the slot, then queues a timeout-bounded pending entry that
-- OnLootSlotCleared/OnTimeout resolve.
function Award:TryAward(slot, winnerGuid, reason)
	local info = PLC.Loot.Detection.lootSlotInfo[slot]
	local winnerEntry = PLC.Roster:Get(winnerGuid)

	local ok, cause = self:CanGiveLoot(slot, winnerGuid)
	if not ok then
		print(L["CHAT_PREFIX"] .. string.format(L["AWARD_FAILED"], (info and info.link) or "?",
			(winnerEntry and winnerEntry.name) or winnerGuid, cause))
		return false
	end

	LootSlot(slot)

	local entry = {
		slot = slot,
		link = info.link,
		winnerGuid = winnerGuid,
		winnerName = winnerEntry.name,
		reason = reason,
	}
	entry.timerHandle = PLC:ScheduleTimer(function()
		Award:OnTimeout(entry)
	end, LOOT_TIMEOUT)
	table.insert(self.pendingQueue, entry)

	if PLC.Session and PLC.Session.OnAwardAttempted then
		PLC.Session:OnAwardAttempted(entry)
	end

	return true
end

local function removeFromQueue(entry)
	for i = #Award.pendingQueue, 1, -1 do
		if Award.pendingQueue[i] == entry then
			table.remove(Award.pendingQueue, i)
			return
		end
	end
end

-- Searches from the end (most recent award first) -- matches the verified upstream search order
-- (ml_core.lua:594-603).
function Award:OnLootSlotCleared(slot)
	for i = #self.pendingQueue, 1, -1 do
		local entry = self.pendingQueue[i]
		if entry.slot == slot then
			PLC:CancelTimer(entry.timerHandle)
			table.remove(self.pendingQueue, i)
			-- reason == "collect" means this was silent background self-looting (see
			-- Data/Session.lua:CollectDetectedItems), not a real award decision -- no success
			-- print, no raid-chat announcement for every single item bagged across the raid.
			-- Session:AwardBaggedItem handles the real "awarded to X" messaging separately, once
			-- the council actually decides.
			if entry.reason ~= "collect" then
				print(L["CHAT_PREFIX"] .. string.format(L["AWARD_SUCCESS"], entry.link, entry.winnerName))
			end
			if PLC.Session and PLC.Session.OnAwardConfirmed then
				PLC.Session:OnAwardConfirmed(entry)
			end
			if entry.reason ~= "collect" and PLC.Loot.Announce and PLC.Loot.Announce.AnnounceAward then
				PLC.Loot.Announce:AnnounceAward(entry)
			end
			return
		end
	end
end

function Award:OnTimeout(entry)
	removeFromQueue(entry)
	print(L["CHAT_PREFIX"] .. string.format(L["AWARD_TIMEOUT"], entry.link, entry.winnerName))
	if PLC.Session and PLC.Session.OnAwardFailed then
		PLC.Session:OnAwardFailed(entry, "timeout")
	end
end
