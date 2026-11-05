local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local AutoLoot = {}
PLC.Loot.AutoLoot = AutoLoot

-- Hands out master loot by itself while the master looter's loot window is open. Every item gets a
-- target, in this order:
--   0. loot everyone takes their own copy of (PLC.PersonalLootItems, e.g. Badge of Justice): the
--      master looter's copy goes to them, and it's never reviewed
--   1. the item's rule (Data/ExcludedItems.lua): the player's own from Options -> Auto Loot, else the
--      default. "keep" goes to the master looter and is never reviewed (raw epic gems, Nether
--      Vortex); "leave" stays in the window for Blizzard's own assign list
--   2. quest items stay in the window too
--   3. review loot (Detection:IsReviewQuality): profile.autoLoot.reviewTarget. A legendary never goes
--      to a named player this way: a general rule shouldn't bind one to somebody else
--   4. anything else the group's loot threshold makes master loot: profile.autoLoot.otherTarget
-- A target is "self", "leave" or a comma-separated list of names, tried in order: the first who
-- can receive it gets it, so a second name is a fallback for a full mule. Only review loot that
-- actually reached the master looter joins a session (Session:CollectDetectedItems).
AutoLoot.SELF = PLC.ItemRules.SELF
AutoLoot.LEAVE = PLC.ItemRules.LEAVE
AutoLoot.KEEP = PLC.ItemRules.KEEP

local TICK_SECONDS = 0.2 -- the window's contents can change at any moment, so keep checking it
local MAX_WAITING_TICKS = 10 -- how long a candidate may take to show up in the list
local REPORT_DELAY = 0.5 -- groups a burst of failures into one chat line
local LEGENDARY_QUALITY = 5
local QUEST_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

-- { slots = { [slot] = { tried, waiting, done } }, goldDone, manual } from the first LOOT_READY of a
-- loot window to LOOT_CLOSED. `manual`: the master looter took this window by hand (Shift).
local window
local tickHandle
local failures = {} -- [reason .. name] = { reason, name, links }
local reportHandle

local function settings()
	return PLC.db.profile.autoLoot
end

local function shortName(name)
	return (strsplit("-", name))
end

local function isMe(name)
	return strlower(shortName(name)) == strlower(UnitName("player"))
end

local function itemIdentity(link)
	if not link then
		return nil, nil
	end
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
	return itemID, classID
end

-- The target for an item: "self", "leave" or a list of names.
function AutoLoot:GetTarget(link, quality)
	local itemID, classID = itemIdentity(link)
	if PLC.PersonalLootItems[itemID] then
		return self.SELF
	end
	local rule = PLC.ItemRules.For(itemID)
	if rule == self.KEEP then
		return self.SELF
	elseif rule then
		return rule
	end
	if classID == QUEST_CLASS_ID then
		return self.LEAVE
	end
	if PLC.Loot.Detection:IsReviewQuality(link, quality) then
		local target = settings().reviewTarget
		if (quality or 0) >= LEGENDARY_QUALITY and target ~= self.LEAVE then
			return self.SELF
		end
		return target
	end
	if (quality or 0) >= (GetLootThreshold() or 2) then
		return settings().otherTarget
	end
	return self.LEAVE
end

-- Loot that's never put up for review, however good it is: its rule keeps it, leaves it in the
-- window or sends it to someone, or it's a quest item or everyone's own.
function AutoLoot:IsExcludedFromReview(link)
	local itemID, classID = itemIdentity(link)
	if classID == QUEST_CLASS_ID or PLC.PersonalLootItems[itemID] then
		return true
	end
	local rule = PLC.ItemRules.For(itemID)
	return rule ~= nil and rule ~= self.SELF
end

local function recipients(target)
	if target == AutoLoot.LEAVE then
		return {}
	elseif target == AutoLoot.SELF then
		return { UnitName("player") }
	end
	local names = {}
	for name in target:gmatch("[^,%s]+") do
		table.insert(names, name)
	end
	return names
end

local function flushFailures()
	if reportHandle then
		PLC:CancelTimer(reportHandle)
		reportHandle = nil
	end
	for key, failure in pairs(failures) do
		print(L["CHAT_PREFIX"] .. string.format(L["AUTOLOOT_FAILED_" .. failure.reason], failure.name, table.concat(failure.links, ", ")))
		failures[key] = nil
	end
end

local function reportFailure(reason, name, link)
	local key = reason .. name
	failures[key] = failures[key] or { reason = reason, name = shortName(name), links = {} }
	table.insert(failures[key].links, link)
	if not reportHandle then
		reportHandle = PLC:ScheduleTimer(flushFailures, REPORT_DELAY)
	end
end

local function delivered(slot, info, name)
	if isMe(name) then
		PLC.Session:CollectDetectedItems({ [slot] = info }, true)
	else
		print(L["CHAT_PREFIX"] .. string.format(L["AUTOLOOT_SENT"], info.link, shortName(name)))
	end
end

-- Starts the transfer to `name`. False if they can't receive this item right now.
local function startHandout(slot, info, state, name)
	local function done(success, reason)
		if success then
			state.done = true
			delivered(slot, info, name)
		else
			reportFailure(reason, name, info.link)
		end
	end

	local Award = PLC.Loot.Award
	-- Neither is master looted: the master looter just loots it, like anyone would.
	local belowThreshold = (info.quality or 0) < (GetLootThreshold() or 2)
	local personal = PLC.PersonalLootItems[(itemIdentity(info.link))]
	if (belowThreshold or personal) and isMe(name) then
		Award:Take(slot, info.link, done)
		return true
	end
	local candidateIndex = Award:FindCandidate(slot, name)
	if not candidateIndex then
		return false
	end
	Award:GiveTo(slot, info.link, candidateIndex, done)
	return true
end

-- Returns true once a transfer is in flight.
local function handOut(slot, info, state)
	local target = AutoLoot:GetTarget(info.link, info.quality)
	local names = recipients(target)
	if #names == 0 then
		state.done = true
		return false
	end

	local untried = false
	for _, name in ipairs(names) do
		if not state.tried[name] then
			if startHandout(slot, info, state, name) then
				state.tried[name] = true
				return true
			end
			untried = true
		end
	end
	if not untried then
		state.done = true -- everyone listed was tried, and each failure was reported
		return false
	end

	state.waiting = state.waiting + 1
	if state.waiting >= MAX_WAITING_TICKS then
		state.done = true
		reportFailure("NONE", target == AutoLoot.SELF and UnitName("player") or target, info.link)
	end
	return false
end

-- Money from a corpse. Not from lockboxes and the like, which aren't the raid's.
local function lootGold()
	window.goldDone = true
	if not settings().lootGold then
		return
	end
	for slot = 1, GetNumLootItems() do
		if GetLootSlotType(slot) == LOOT_SLOT_MONEY then
			local source = GetLootSourceInfo(slot)
			if not (source and source:find("^Item%-")) then
				LootSlot(slot)
			end
		end
	end
end

local function stopTicking()
	if tickHandle then
		PLC:CancelTimer(tickHandle)
		tickHandle = nil
	end
end

-- Shift pressed with the window open: the rest of it is the master looter's. What's still in it is
-- noted, as when they open a window with Shift held (Loot/Detection.lua), except a hand-out already
-- under way, which reports for itself.
local function takeOver()
	window.manual = true
	stopTicking()
	local left = {}
	local pending = PLC.Loot.Award.pending
	for slot, info in pairs(PLC.Loot.Detection.lootSlotInfo) do
		if not info.looted and not (pending and pending.slot == slot) then
			left[slot] = info
		end
	end
	PLC.Session:CollectDetectedItems(left)
end

local function tick()
	if not window or window.manual then
		return
	end
	if IsShiftKeyDown() then
		takeOver()
		return
	end
	if not window.goldDone then
		lootGold()
	end
	if PLC.Loot.Award.pending then
		return
	end
	for slot = 1, GetNumLootItems() do
		local info = PLC.Loot.Detection.lootSlotInfo[slot]
		if info and info.link then
			window.slots[slot] = window.slots[slot] or { tried = {}, waiting = 0 }
			local state = window.slots[slot]
			local locked = select(6, GetLootSlotInfo(slot))
			if not state.done and not locked and handOut(slot, info, state) then
				return
			end
		end
	end
end

-- Called when the master looter's loot window opens. False leaves the window to them: auto loot is
-- off, or they're holding Shift to take this one by hand. LOOT_READY can fire more than once for one
-- window, so the first decides for all of them: letting go of Shift before a second one mustn't
-- start auto loot after all.
function AutoLoot:Begin()
	if window then
		return not window.manual
	end
	if not settings().enabled then
		return false
	end
	window = { slots = {} }
	if IsShiftKeyDown() then
		window.manual = true
		return false
	end
	tickHandle = PLC:ScheduleRepeatingTimer(tick, TICK_SECONDS)
	return true
end

function AutoLoot:End()
	stopTicking()
	window = nil
	PLC.Loot.Award:Cancel()
	flushFailures()
end

PLC:RegisterSlashCommand("autoloot", L["SLASH_AUTOLOOT"], function()
	local autoLoot = settings()
	autoLoot.enabled = not autoLoot.enabled
	print(L["CHAT_PREFIX"] .. L[autoLoot.enabled and "AUTOLOOT_TURNED_ON" or "AUTOLOOT_TURNED_OFF"])
end)
