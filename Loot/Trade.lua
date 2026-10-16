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

-- Scans every bag for the first stack of a given item ID -- used both to place an item into a
-- trade slot and, after the trade closes, to confirm it actually left (see OnTradeClosed below).
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

-- Called directly from a button's OnClick (UI/TradeFrame.lua) -- stays synchronous, no scheduled
-- delay in between, so InitiateTrade still carries the click's own hardware-event status. Works
-- from either side: the holder opening a trade to hand an item off, or a recipient opening one to
-- go collect it -- whichever client is actually the holder for whatever's owed auto-places it once
-- TRADE_SHOW fires (see onTradeShow below), regardless of who clicked Trade first.
function Trade:StartTrade(idx)
	local item = PLC.Session.items[idx]
	if not item or not item.awarded then
		return
	end
	local myGuid = UnitGUID("player")
	-- If I'm the one who won it, my trade partner is the holder; otherwise I must be the holder,
	-- and my trade partner is whoever it was awarded to.
	local partnerGuid = (item.awarded == myGuid) and (PLC.Session.owner and PLC.Session.owner.guid) or item.awarded
	local unit = self:ResolveUnitToken(partnerGuid)
	if not unit then
		local entry = partnerGuid and PLC.Roster:Get(partnerGuid)
		local name = (entry and PLC.Roster:ShortName(entry.name)) or "?"
		print(L["CHAT_PREFIX"] .. string.format(L["TRADE_NOT_FOUND"], name))
		return
	end
	InitiateTrade(unit)
end

-- Items this client just placed into the currently-open trade window, re-checked once it closes
-- (see onTradeClosed) -- the only way to actually confirm a trade went through versus being
-- cancelled is to look at whether the item is still sitting where it was.
local placedItems = {} -- array of { idx, itemID }

-- One slot held back on purpose, same reasoning a lot of trade addons use -- leaves room for
-- either side to manually add something extra (gold, an unrelated item) without first having to
-- pull one of the auto-placed items back out.
local MAX_AUTO_PLACE = (MAX_TRADE_ITEMS and MAX_TRADE_ITEMS - 1) or 5

-- Fires for both participants -- only the holder's own client ever auto-places anything (a
-- recipient has nothing of the holder's to place). Not gated on "did I click Trade" -- the other
-- party may have initiated it instead -- just: is my current trade partner (the "npc" unit token,
-- confirmed against Warcraft Wiki as the trade-partner token) someone I owe an un-traded award to?
-- Places as many of the owed items as fit, not just one, since the same person can easily be owed
-- more than one item from the same review pass.
local function onTradeShow()
	wipe(placedItems)
	if not PLC.Session:IsHolder() then
		return
	end
	local partnerGuid = UnitGUID("npc")
	if not partnerGuid then
		return
	end
	local _, _, pickup = getContainerFns()
	local tradeSlot = 1
	for idx, item in pairs(PLC.Session.items) do
		if item.awarded == partnerGuid and not item.traded and tradeSlot <= MAX_AUTO_PLACE then
			local itemID = itemIDFromItemString(item.itemString)
			local bag, slot = Trade:FindBagSlot(itemID)
			if bag then
				pickup(bag, slot)
				ClickTradeButton(tradeSlot)
				table.insert(placedItems, { idx = idx, itemID = itemID })
				tradeSlot = tradeSlot + 1
			end
			-- No bag match: already moved/traded outside the addon, mailed, banked, etc. -- leaves
			-- the opened trade as-is for a manual drag rather than failing the whole flow.
		end
	end
end

-- Re-checks each item this client just placed -- gone means the trade actually went through
-- (cancelling a trade leaves everything exactly where it was); still present means it was
-- cancelled. Session:MarkItemTraded does its own holder/awarded/not-already-traded checks, so
-- nothing here needs to re-verify those.
local function onTradeClosed()
	for _, placed in ipairs(placedItems) do
		local bag = Trade:FindBagSlot(placed.itemID)
		if not bag then
			PLC.Session:MarkItemTraded(placed.idx)
		end
	end
	wipe(placedItems)
end

PLC.Events:RegisterHandler("TRADE_SHOW", onTradeShow)
PLC.Events:RegisterHandler("TRADE_CLOSED", onTradeClosed)
