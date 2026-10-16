local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local Trade = {}
PLC.Loot.Trade = Trade

-- Event-driven trade automation (docs/SPECIFICATION.md's long-reserved Phase 2 slot) -- no
-- TradeFrame hooking, only the documented API surface (InitiateTrade, PickupContainerItem,
-- ClickTradeButton). "Automatically trades the person the item" means zero-click PLACEMENT, not a
-- zero-click handshake: AcceptTrade is hardware-event-protected (confirmed against Warcraft Wiki),
-- so the actual accept click still has to be a real click from a real person on each side -- that's
-- a WoW constraint, not something this file can route around.

local function getContainerFns()
	return (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots,
		(C_Container and C_Container.GetContainerItemID) or GetContainerItemID,
		(C_Container and C_Container.PickupContainerItem) or PickupContainerItem
end

local function itemIDFromItemString(itemString)
	return itemString and tonumber(itemString:match("item:(%d+)"))
end

-- Wires UI/TradeFrame.lua's one-click "Disenchant" button for a specific item, the same
-- /cast + /use macro sequence any manually-written disenchant macro already uses -- the standard,
-- documented, taint-safe way to do this (see UI/Widgets/Button.lua:createActionButton's own
-- comment for why this goes through a macro at all instead of calling CastSpellByName/
-- UseContainerItem directly). `/use item:<id>` lets Blizzard's own macro engine find the item
-- wherever it currently is (equipped or any bag slot) instead of this file tracking bag/slot
-- itself. Re-applied on every UI refresh since DataTable recycles row widgets across different
-- items, not created fresh per row. Skipped entirely during combat lockdown -- a secure frame's
-- attributes can't be changed then; leaving the button's previous macrotext in place is safer
-- than erroring, and disenchanting is essentially never time-critical mid-fight anyway.
function Trade:ConfigureDisenchantButton(button, idx)
	if InCombatLockdown() then
		return
	end
	local item = PLC.Session.items[idx]
	local itemID = item and itemIDFromItemString(item.itemString)
	if not itemID then
		button:SetAttribute("macrotext", "")
		return
	end
	button:SetAttribute("macrotext", "/cast Disenchant\n/use item:" .. itemID)
end

-- Scans every bag for the first stack of a given item ID -- used by the self-disenchant watcher
-- (onBagUpdate below) to confirm the item actually left. Trades use findTradableStack instead.
-- Same (C_Container and C_Container.X) or X fallback pattern Loot/Award.lua:39 already established
-- for container APIs.
function Trade:FindBagSlot(itemID)
	if not itemID then
		return nil
	end
	local getNumSlots, getItemID = getContainerFns()
	for bag = 0, NUM_BAG_SLOTS do
		local numSlots = getNumSlots(bag) or 0
		for slot = 1, numSlots do
			if getItemID(bag, slot) == itemID then
				return bag, slot
			end
		end
	end
	return nil
end

-- A live unit token is needed for InitiateTrade/FollowUnit -- GUIDs alone don't work, and roster
-- entries don't cache one (unstable across regroups), so this is resolved fresh every call, same
-- "compute live, don't cache" approach Data/Session.lua:GetEnchanterGuid already uses for the
-- Enchanter default.
function Trade:ResolveUnitToken(guid)
	if not guid then
		return nil
	end
	if UnitGUID("player") == guid then
		return "player"
	end
	for i = 1, 4 do
		if UnitGUID("party" .. i) == guid then
			return "party" .. i
		end
	end
	for i = 1, 40 do
		if UnitGUID("raid" .. i) == guid then
			return "raid" .. i
		end
	end
	return nil
end

-- Who the local player's counterpart is for a given item -- shared by StartTrade and
-- FollowPartner below so both buttons (UI/TradeFrame.lua's Trade and Follow columns, now on both
-- sections -- see that file) always agree on the same person. If I'm the one who won it, my
-- partner is the holder; otherwise I must be the holder, and my partner is whoever it was awarded
-- to. Written as an explicit if/else, not the `cond and A or B` idiom -- that idiom silently
-- falls through to B whenever A itself is falsy, which Session.owner being nil (a real possible
-- state) would have hit here.
function Trade:GetPartnerGuid(idx)
	local item = PLC.Session.items[idx]
	if not item or not item.awarded then
		return nil
	end
	if item.awarded == UnitGUID("player") then
		return PLC.Session.owner and PLC.Session.owner.guid
	end
	return item.awarded
end

local function resolveOrWarn(partnerGuid)
	if not partnerGuid or partnerGuid == UnitGUID("player") then
		-- Self-awarded items are auto-completed the moment they're awarded (see
		-- Data/Session.lua:AwardBaggedItem) and never get a Trade/Follow button to begin with, so
		-- this is just a defensive guard against ever trying to trade/follow yourself, not an
		-- expected path.
		return nil
	end
	local unit = Trade:ResolveUnitToken(partnerGuid)
	if not unit then
		local entry = PLC.Roster:Get(partnerGuid)
		local name = (entry and PLC.Roster:ShortName(entry.name)) or "?"
		print(L["CHAT_PREFIX"] .. string.format(L["TRADE_NOT_FOUND"], name))
	end
	return unit
end

-- Called directly from a button's OnClick (UI/TradeFrame.lua) -- stays synchronous, no scheduled
-- delay in between, so InitiateTrade still carries the click's own hardware-event status. Works
-- from either side: the holder opening a trade to hand an item off, or a recipient opening one to
-- go collect it -- whichever client is actually the holder for whatever's owed auto-places it once
-- TRADE_SHOW fires (see onTradeShow below), regardless of who clicked Trade first.
function Trade:StartTrade(idx)
	local unit = resolveOrWarn(self:GetPartnerGuid(idx))
	if unit then
		InitiateTrade(unit)
	end
end

-- Same hardware-event requirement as StartTrade -- called directly from OnClick, no delay.
function Trade:FollowPartner(idx)
	local unit = resolveOrWarn(self:GetPartnerGuid(idx))
	if unit then
		FollowUnit(unit)
	end
end

-- One slot held back on purpose, same reasoning a lot of trade addons use (RC included) -- the
-- last trade slot is "Will not be traded", and this leaves room for either side to add something
-- extra without first having to pull one of the auto-placed items back out.
local MAX_AUTO_PLACE = (MAX_TRADE_ITEMS and MAX_TRADE_ITEMS - 1) or 6
-- RC's TRADE_ADD_DELAY: placing items the instant TRADE_SHOW fires silently does nothing (the trade
-- window isn't ready to accept them yet), and several at once also fail -- so each placement is
-- scheduled, one per step.
local TRADE_ADD_DELAY = 0.1

local tradeOpen = false
local tradePartnerGuid -- captured at TRADE_SHOW; the "npc" token is gone by the time a trade completes
local placeQueue = {} -- array of { itemID, idxs = { idx, ... } } still to place this trade
local usedSlots = {} -- ["bag:slot"] = true, bag slots already put into this trade
local nextTradeSlot = 1
local tradedSnapshot = {} -- [itemID] = count, what we had in the trade window at the last accept

local function containerInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then
			return info.itemID, info.stackCount or 1, info.isLocked
		end
		return nil
	end
	local _, count, locked, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
	return itemID, count or 1, locked
end

-- RC's GetContainerItemTradeTimeRemaining, reduced to a yes/no: tradable unless soulbound, and a
-- soulbound item still is while its "You may trade this item with players that were also eligible
-- to loot this item for the next ..." line (BIND_TRADE_TIME_REMAINING) is on the tooltip.
local scanTooltip
local tradeTimePattern

local function isTradable(bag, slot)
	if not scanTooltip then
		scanTooltip = CreateFrame("GameTooltip", "PixlLootCouncilScanTooltip", nil, "GameTooltipTemplate")
		tradeTimePattern = BIND_TRADE_TIME_REMAINING
			and BIND_TRADE_TIME_REMAINING:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", ".+")
	end
	scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTooltip:SetBagItem(bag, slot)
	local bound = false
	for i = 1, scanTooltip:NumLines() or 0 do
		local line = _G["PixlLootCouncilScanTooltipTextLeft" .. i]
		local text = line and line:GetText()
		if text then
			if text == ITEM_SOULBOUND or text == ITEM_ACCOUNTBOUND or text == ITEM_BIND_QUEST then
				bound = true
			elseif tradeTimePattern and text:match(tradeTimePattern) then
				scanTooltip:Hide()
				return true
			end
		end
	end
	scanTooltip:Hide()
	return not bound
end

-- The first unlocked, tradable stack of itemID not already in this trade -- preferring one big
-- enough to cover `needed` on its own. Returns bag, slot, stackCount.
local function findTradableStack(itemID, needed)
	local getNumSlots = getContainerFns()
	local fallbackBag, fallbackSlot, fallbackCount
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, getNumSlots(bag) or 0 do
			local id, count, locked = containerInfo(bag, slot)
			if id == itemID and not locked and not usedSlots[bag .. ":" .. slot] and isTradable(bag, slot) then
				if count >= needed then
					return bag, slot, count
				end
				if not fallbackBag then
					fallbackBag, fallbackSlot, fallbackCount = bag, slot, count
				end
			end
		end
	end
	return fallbackBag, fallbackSlot, fallbackCount
end

local function itemLabel(itemID)
	return (select(2, C_Item.GetItemInfo(itemID))) or ("item:" .. itemID)
end

-- Places the head of placeQueue into the next trade slot, then schedules itself for the rest.
-- Stacks are split so only the awarded count goes over (3 oils in one stack, 1 awarded -> 1 traded).
local function placeNext()
	if not tradeOpen or #placeQueue == 0 or nextTradeSlot > MAX_AUTO_PLACE then
		return
	end
	local entry = table.remove(placeQueue, 1)
	local needed = #entry.idxs
	local bag, slot, count = findTradableStack(entry.itemID, needed)
	if not bag then
		print(L["CHAT_PREFIX"] .. string.format(L["TRADE_NO_TRADABLE"], itemLabel(entry.itemID)))
	else
		local amount = math.min(needed, count)
		ClearCursor()
		if count > amount then
			local split = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem
			split(bag, slot, amount)
		else
			local _, _, pickup = getContainerFns()
			pickup(bag, slot)
		end
		ClickTradeButton(nextTradeSlot)
		usedSlots[bag .. ":" .. slot] = true
		nextTradeSlot = nextTradeSlot + 1
		if amount < needed then
			-- No single stack covered every unit owed; the rest goes in the next trade slot.
			local rest = {}
			for i = amount + 1, needed do
				table.insert(rest, entry.idxs[i])
			end
			table.insert(placeQueue, 1, { itemID = entry.itemID, idxs = rest })
		end
	end
	if #placeQueue > 0 then
		PLC:ScheduleTimer(placeNext, TRADE_ADD_DELAY)
	end
end

-- Fires for both participants -- only the session owner's own client ever auto-places anything (a
-- recipient has nothing of the holder's to place). IsOwner, not IsHolder -- trading routinely
-- happens after the review pass has already ended (Award All ends it immediately), so this has to
-- keep working regardless of live session state. Not gated on "did I click Trade" -- the other
-- party may have initiated it instead -- just: is my current trade partner (the "npc" unit token)
-- someone I owe an un-traded award to? Awards of the same item are grouped, so two oils owed to
-- the same player go over as one stack of 2.
local function onTradeShow()
	tradeOpen = true
	wipe(placeQueue)
	wipe(usedSlots)
	wipe(tradedSnapshot)
	nextTradeSlot = 1
	tradePartnerGuid = UnitGUID("npc")
	if not PLC.Session:IsOwner() or not tradePartnerGuid then
		return
	end
	local byItem, order = {}, {}
	for idx, item in pairs(PLC.Session.items) do
		local itemID = itemIDFromItemString(item.itemString)
		if itemID and item.awarded == tradePartnerGuid and not item.traded then
			if not byItem[itemID] then
				byItem[itemID] = { itemID = itemID, idxs = {} }
				table.insert(order, byItem[itemID])
			end
			table.insert(byItem[itemID].idxs, idx)
		end
	end
	for _, entry in ipairs(order) do
		table.sort(entry.idxs)
		table.insert(placeQueue, entry)
	end
	if #placeQueue > 0 then
		PLC:ScheduleTimer(placeNext, TRADE_ADD_DELAY)
	end
end

-- RC's TRADE_ACCEPT_UPDATE: whenever either side accepts, record exactly what we're giving. Items
-- can't change after an accept without resetting it (which fires this again), so the last snapshot
-- is what a completed trade actually transferred -- including anything dragged in by hand.
local function onTradeAcceptUpdate(_, playerAccepted, targetAccepted)
	if playerAccepted ~= 1 and targetAccepted ~= 1 then
		return
	end
	wipe(tradedSnapshot)
	for i = 1, MAX_AUTO_PLACE do
		local link = GetTradePlayerItemLink(i)
		local itemID = link and tonumber(link:match("item:(%d+)"))
		if itemID then
			local _, _, count = GetTradePlayerItemInfo(i)
			tradedSnapshot[itemID] = (tradedSnapshot[itemID] or 0) + (count or 1)
		end
	end
end

-- "Trade complete." -- mark one pending award to this partner as traded per unit of that item we
-- just gave them. Session:MarkItemTraded does its own owner/awarded/not-already-traded checks.
local function onUIInfoMessage(_, messageType, message)
	local complete = (LE_GAME_ERR_TRADE_COMPLETE and messageType == LE_GAME_ERR_TRADE_COMPLETE)
		or (ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE)
	if not complete or not tradePartnerGuid or not PLC.Session:IsOwner() then
		return
	end
	local pending = {}
	for idx, item in pairs(PLC.Session.items) do
		if item.awarded == tradePartnerGuid and not item.traded then
			table.insert(pending, idx)
		end
	end
	table.sort(pending)
	for _, idx in ipairs(pending) do
		local itemID = itemIDFromItemString(PLC.Session.items[idx].itemString)
		if itemID and (tradedSnapshot[itemID] or 0) > 0 then
			tradedSnapshot[itemID] = tradedSnapshot[itemID] - 1
			PLC.Session:MarkItemTraded(idx)
		end
	end
	wipe(tradedSnapshot)
end

local function onTradeClosed()
	tradeOpen = false
	wipe(placeQueue)
	wipe(usedSlots)
end

PLC.Events:RegisterHandler("TRADE_SHOW", onTradeShow)
PLC.Events:RegisterHandler("TRADE_ACCEPT_UPDATE", onTradeAcceptUpdate)
PLC.Events:RegisterHandler("UI_INFO_MESSAGE", onUIInfoMessage)
PLC.Events:RegisterHandler("TRADE_CLOSED", onTradeClosed)

-- Equipment slots 1-19 (head..tabard, the stable Vanilla-era numbering this whole client line
-- still uses) -- checked in addition to bags by onBagUpdate below. "Not in any bag" alone isn't
-- reliable evidence an item was actually disenchanted: gear (unlike a pure crafting reagent) can
-- just as easily leave every bag slot by being equipped instead -- even briefly, to compare
-- stats -- which would otherwise false-positive as "done" and silently drop the item from the
-- window despite it never having been disenchanted at all.
local function isItemEquipped(itemID)
	if not itemID then
		return false
	end
	for slot = 1, 19 do
		if GetInventoryItemID("player", slot) == itemID then
			return true
		end
	end
	return false
end

-- A self-disenchant (the holder awarding an item to themselves as the Enchanter -- see
-- Data/Session.lua:AwardBaggedItem, which deliberately does NOT auto-complete this case the way
-- it does a genuine self-award) has no trade to detect at all: the item's already in the holder's
-- bags, and the only remaining action is casting Disenchant on it themselves, which this addon
-- doesn't do for them. The only way to know it actually happened is the same "did it leave my
-- bags" check a real trade's completion uses (disenchanting consumes the item), just triggered by
-- BAG_UPDATE instead of TRADE_CLOSED -- plus the isItemEquipped check above, which onTradeClosed
-- doesn't need (WoW's trade UI only ever accepts bag items, never equipped gear, so that false
-- positive is specific to this watcher). Bucketed (same pattern as Data/Roster.lua's
-- GROUP_ROSTER_UPDATE) since a single bag action can fire this event several times in a row.
-- IsOwner, not IsHolder -- disenchanting routinely happens after the review pass has already
-- ended (Award All ends it immediately), so this has to keep working regardless of live session
-- state, same reasoning as onTradeShow above.
local function onBagUpdate()
	if not PLC.Session:IsOwner() then
		return
	end
	local myGuid = UnitGUID("player")
	for idx, item in pairs(PLC.Session.items) do
		if item.awarded == myGuid and not item.traded then
			local itemID = itemIDFromItemString(item.itemString)
			local bag = Trade:FindBagSlot(itemID)
			if not bag and not isItemEquipped(itemID) then
				PLC.Session:MarkItemTraded(idx)
			end
		end
	end
end

PLC:RegisterOnEnable(function()
	PLC:RegisterBucketEvent({ "BAG_UPDATE" }, 1, onBagUpdate)
end)
