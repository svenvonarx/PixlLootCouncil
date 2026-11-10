local ADDON_NAME, PLC = ...

PLC.Loot = PLC.Loot or {}
local Award = {}
PLC.Loot.Award = Award

-- The one place an item leaves a loot window on this addon's say-so. Loot/AutoLoot.lua decides who
-- gets what; this does the transfer and reports how it went. One item at a time, so a server error
-- can only belong to the transfer in flight: done(true) on LOOT_SLOT_CLEARED, done(false, reason)
-- on a known error, and if nothing arrives the timeout re-checks the slot. Under master loot only
-- GiveMasterLoot moves an item: LootSlot would open Blizzard's candidate list instead.
local HANDOUT_TIMEOUT = 4 -- a 25-player boss can take the server a while: too short, and a hand-out that went through counted as failed

Award.pending = nil -- { slot, link, done, timer }

local function reasonFor(message)
	if message == ERR_LOOT_MASTER_INV_FULL then
		return "BAGS"
	elseif message == ERR_LOOT_MASTER_UNIQUE_ITEM or message == ERR_ITEM_MAX_COUNT then
		return "UNIQUE"
	elseif message == ERR_LOOT_TOO_FAR or message == ERR_TOO_FAR_TO_INTERACT then
		return "FAR"
	elseif message == ERR_LOOT_PLAYER_NOT_FOUND then
		return "ELIGIBLE"
	elseif message == ERR_LOOT_MASTER_OTHER then
		return "OTHER"
	end
	return nil
end

local function resolve(pending, success, reason)
	if Award.pending ~= pending then
		return
	end
	Award.pending = nil
	PLC:CancelTimer(pending.timer)
	pending.done(success, reason)
end

local function begin(slot, link, done)
	local pending = { slot = slot, link = link, done = done }
	pending.timer = PLC:ScheduleTimer(function()
		local stillThere = LootSlotHasItem(slot) and GetLootSlotLink(slot) == link
		resolve(pending, not stillThere, "OTHER")
	end, HANDOUT_TIMEOUT)
	Award.pending = pending
end

-- The candidate-list index of a player for this slot, or nil if they can't receive it right now.
function Award:FindCandidate(slot, name)
	local wanted = strlower((strsplit("-", name)))
	for index = 1, MAX_RAID_MEMBERS do
		local candidate = GetMasterLootCandidate(slot, index)
		if candidate and strlower((strsplit("-", candidate))) == wanted then
			return index
		end
	end
	return nil
end

function Award:GiveTo(slot, link, candidateIndex, done)
	begin(slot, link, done)
	GiveMasterLoot(slot, candidateIndex)
end

-- For an item below the group's loot threshold, which isn't master looted at all.
function Award:Take(slot, link, done)
	begin(slot, link, done)
	LootSlot(slot)
end

function Award:OnLootSlotCleared(slot)
	if self.pending and self.pending.slot == slot then
		resolve(self.pending, true)
	end
end

function Award:OnErrorMessage(message)
	local reason = reasonFor(message)
	if reason and self.pending then
		resolve(self.pending, false, reason)
	end
end

-- The loot window closed: what's in flight can no longer be confirmed either way.
function Award:Cancel()
	if self.pending then
		PLC:CancelTimer(self.pending.timer)
		self.pending = nil
	end
end

PLC.Events:RegisterHandler("UI_ERROR_MESSAGE", function(_, _, message)
	Award:OnErrorMessage(message)
end)
