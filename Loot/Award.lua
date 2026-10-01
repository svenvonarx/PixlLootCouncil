local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local Award = {}
PLC.Loot.Award = Award

local LOOT_TIMEOUT = 5 -- seconds; matches the verified upstream constant (ml_core.lua:35)

Award.pendingQueue = {} -- array of { slot, link, winnerGuid, winnerName, reason, timerHandle }

-- Mirrors the verified CanGiveLoot rule set (ml_core.lua:667-721) client-side, before ever
-- calling the protected GiveMasterLoot API. Returns true, or false + a localized cause string.
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

	local winnerEntry = PLC.Roster:Get(winnerGuid)
	if not winnerEntry then
		return false, L["CANGIVE_NOT_IN_GROUP"]
	end

	if winnerGuid == UnitGUID("player") then
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

	if not winnerEntry.online then
		return false, L["CANGIVE_OFFLINE"]
	end

	-- GetMasterLootCandidate already reflects Blizzard's own master-loot eligibility (in group,
	-- in range/instance) for this specific slot -- this loop is the verified exact shape
	-- (ml_core.lua:694-700), adapted to compare GUIDs since our identity model is GUID-keyed.
	for i = 1, MAX_RAID_MEMBERS do
		local candidateUnit = GetMasterLootCandidate(slot, i)
		if not candidateUnit then
			break
		end
		if UnitGUID(candidateUnit) == winnerGuid then
			return true
		end
	end
	return false, L["CANGIVE_NOT_ELIGIBLE"]
end

-- The single funnel for every award path (see docs/SPECIFICATION.md §3 principle 4). Validates
-- first, then calls the real protected API, then queues a timeout-bounded pending entry that
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

	if winnerGuid == UnitGUID("player") then
		-- Awarding to the master looter themself is just looting the slot directly.
		LootSlot(slot)
	else
		local candidateIndex
		for i = 1, MAX_RAID_MEMBERS do
			local candidateUnit = GetMasterLootCandidate(slot, i)
			if not candidateUnit then
				break
			end
			if UnitGUID(candidateUnit) == winnerGuid then
				candidateIndex = i
				break
			end
		end
		if not candidateIndex then
			-- CanGiveLoot already confirmed eligibility moments ago; this should not happen, but
			-- GiveMasterLoot must never be called with a nil index.
			print(L["CHAT_PREFIX"] .. string.format(L["AWARD_FAILED"], info.link, winnerEntry.name, L["CANGIVE_NOT_ELIGIBLE"]))
			return false
		end
		GiveMasterLoot(slot, candidateIndex)
	end

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
			print(L["CHAT_PREFIX"] .. string.format(L["AWARD_SUCCESS"], entry.link, entry.winnerName))
			if PLC.Session and PLC.Session.OnAwardConfirmed then
				PLC.Session:OnAwardConfirmed(entry)
			end
			if PLC.Loot.Announce and PLC.Loot.Announce.AnnounceAward then
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
