local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local BagTracker = {}
PLC.Loot.BagTracker = BagTracker

-- Tracks raid loot sitting in the master looter's bags, RCLootCouncil-style (its ItemStorage
-- "award_later" list + TradeUI time checks):
--   * which items are still tradable, and for how long -- a BoP item can be traded to anyone who
--     was eligible to loot it for 2 hours, shown on its tooltip as BIND_TRADE_TIME_REMAINING
--   * raid loot that never went through this addon's own loot-window collection (looted by hand,
--     handed to the ML, below the master-loot threshold...): new items in the ML's bags while in a
--     raid are added to the session backlog if they're still trade-window items (quality >=
--     lootThreshold) or BoE recipes
--   * RC's low-trade-time reminder in chat, and flagging items whose trade window ran out
-- Items are told apart by their item GUID (ItemLocation-based, the same API RC uses), so three
-- copies of the same oil are three separate entries with their own timers.

local RECIPE_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local MIN_RECIPE_QUALITY = 2 -- uncommon
local REMINDER_THRESHOLDS = { 1200, 300 } -- RC warns at 20 min; a final nudge at 5
local REFRESH_SECONDS = 30

local function getContainerFns()
	return (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots,
		(C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
end

local function itemIDFromString(text)
	return text and tonumber(text:match("item:(%d+)"))
end

local function hasGuidApi()
	return C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot and true or false
end

function BagTracker:GetItemGUID(bag, slot)
	if not hasGuidApi() then
		return nil
	end
	local ok, guid = pcall(function()
		local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
		if C_Item.DoesItemExist and not C_Item.DoesItemExist(location) then
			return nil
		end
		return C_Item.GetItemGUID(location)
	end)
	return ok and guid or nil
end

----------------------------------------------------------------------------------------------------
-- Trade status from the bag item's tooltip (RC's GetContainerItemTradeTimeRemaining).
----------------------------------------------------------------------------------------------------

local scanTooltip
local tradeTimePattern

-- "1 hour 52 min" / "52 min" / "45 sec" -> seconds. The client's own duration wording; matched on
-- the unit's first letter, which covers the English client. nil if nothing could be read.
local function parseDuration(text)
	local lower = text:lower()
	local hours = tonumber(lower:match("(%d+)%s*h"))
	local minutes = tonumber(lower:match("(%d+)%s*m"))
	local seconds = tonumber(lower:match("(%d+)%s*s"))
	if not hours and not minutes and not seconds then
		return nil
	end
	return (hours or 0) * 3600 + (minutes or 0) * 60 + (seconds or 0)
end

-- Returns one of:
--   "timer", secondsLeft  -- soulbound, still inside the loot-trade window (secondsLeft may be nil
--                            if the time text couldn't be read -- treat as "some time left")
--   "free"                -- not bound at all (BoE, recipes, consumables): tradable, no limit
--   "bound"               -- soulbound, trade window over: not tradable
function BagTracker:GetTradeStatus(bag, slot)
	if not scanTooltip then
		scanTooltip = CreateFrame("GameTooltip", "PixlLootCouncilScanTooltip", nil, "GameTooltipTemplate")
		-- Escape pattern magic, then turn the %s placeholder into a capture for the time text.
		tradeTimePattern = BIND_TRADE_TIME_REMAINING
			and BIND_TRADE_TIME_REMAINING:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
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
			elseif tradeTimePattern then
				local timeText = text:match(tradeTimePattern)
				if timeText then
					scanTooltip:Hide()
					return "timer", parseDuration(timeText)
				end
			end
		end
	end
	scanTooltip:Hide()
	return bound and "bound" or "free"
end

function BagTracker:IsTradable(bag, slot)
	return self:GetTradeStatus(bag, slot) ~= "bound"
end

-- Bag and slot currently holding the item with this GUID, or nil.
function BagTracker:FindByGUID(guid)
	if not guid or not hasGuidApi() then
		return nil
	end
	local getNumSlots = getContainerFns()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, getNumSlots(bag) or 0 do
			if self:GetItemGUID(bag, slot) == guid then
				return bag, slot
			end
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Applying trade status to session items.
----------------------------------------------------------------------------------------------------

-- Writes the trade status onto a session item: tradeExpiresAt (absolute local time), boe, untradable.
local function applyStatus(item, status, secondsLeft)
	if status == "timer" then
		item.boe = nil
		item.untradable = nil
		item.tradeExpiresAt = time() + (secondsLeft or 7200)
	elseif status == "free" then
		item.boe = true
		item.untradable = nil
		item.tradeExpiresAt = nil
	else
		item.untradable = true
		item.tradeExpiresAt = item.tradeExpiresAt and math.min(item.tradeExpiresAt, time()) or time()
	end
end

-- Seconds of trade time left for a session item: nil = no limit (BoE) or unknown, 0 = expired.
function BagTracker:SecondsLeft(item)
	if not item then
		return nil
	end
	if item.untradable then
		return 0
	end
	if not item.tradeExpiresAt then
		return nil
	end
	return math.max(0, item.tradeExpiresAt - time())
end

-- "1h 52m" / "45m" / "<1m" -- compact, for the sidebar and Loot Trades.
function BagTracker.FormatShort(seconds)
	if seconds >= 3600 then
		return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	elseif seconds >= 60 then
		return string.format("%dm", math.floor(seconds / 60))
	end
	return "<1m"
end

-- Theme color name for a remaining trade time: plenty / getting short / urgent.
function BagTracker.ColorFor(seconds)
	if seconds <= 0 then
		return "warning"
	elseif seconds < 1200 then
		return "warning"
	elseif seconds < 3600 then
		return "accent"
	end
	return "success"
end

-- One line describing an item's trade status, for tooltips/labels. nil when nothing is known.
function BagTracker:StatusText(item)
	if not item then
		return nil
	end
	if item.untradable then
		return L["TRADETIME_EXPIRED"], "warning"
	end
	if item.tradeExpiresAt then
		local left = self:SecondsLeft(item)
		if left <= 0 then
			return L["TRADETIME_EXPIRED"], "warning"
		end
		return string.format(L["TRADETIME_LEFT"], self.FormatShort(left)), self.ColorFor(left)
	end
	if item.boe then
		return L["TRADETIME_BOE"], "dim"
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- The bag scan.
----------------------------------------------------------------------------------------------------

local function inRaidInstance()
	local inInstance, instanceType = IsInInstance()
	return inInstance and instanceType == "raid"
end

-- Everything in the bags right now: [guid] = { bag, slot, link, itemID }.
local function snapshotBags()
	local snapshot = {}
	local getNumSlots, getLink = getContainerFns()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, getNumSlots(bag) or 0 do
			local link = getLink(bag, slot)
			if link then
				local guid = BagTracker:GetItemGUID(bag, slot)
				if guid then
					snapshot[guid] = { bag = bag, slot = slot, link = link, itemID = itemIDFromString(link) }
				end
			end
		end
	end
	return snapshot
end

-- Does a newly bagged raid item belong in the loot session backlog?
local function qualifies(entry, status)
	local _, _, quality = C_Item.GetItemInfo(entry.link)
	local classID = select(6, C_Item.GetItemInfoInstant(entry.link))
	if status == "timer" then
		return (quality or 0) >= PLC.db.profile.lootThreshold
	end
	if status == "free" and classID == RECIPE_CLASS_ID then
		return (quality or 0) >= MIN_RECIPE_QUALITY
	end
	return false
end

-- An unlinked session item for this itemID (collected from the loot window, not yet matched to
-- the physical copy that just landed in the bags).
local function findUnlinkedItem(itemID)
	for _, item in pairs(PLC.Session.items) do
		if not item.itemGUID and not item.awarded and itemIDFromString(item.itemString) == itemID then
			return item
		end
	end
	return nil
end

local function remind(item, threshold)
	item.tradeWarned = item.tradeWarned or {}
	if item.tradeWarned[threshold] then
		return
	end
	item.tradeWarned[threshold] = true
	local left = BagTracker:SecondsLeft(item) or 0
	print(L["CHAT_PREFIX"] .. string.format(L["TRADETIME_REMINDER"], item.link or "?", BagTracker.FormatShort(left)))
end

-- Only the session owner/collector tracks bags: that's whoever physically holds the raid's loot.
local function isTracking()
	return PLC.Session:IsOwner() or PLC.Session.isCollector or PLC.CouncilRules:AmIMasterLooter()
end

function BagTracker:Scan()
	if not hasGuidApi() then
		return
	end
	local snapshot = snapshotBags()
	local known = PLC.db.char.knownBagGuids
	local firstRun = known == nil
	local changed = false

	-- 1. New items in the bags since the last scan.
	if not firstRun and isTracking() then
		for guid, entry in pairs(snapshot) do
			if not known[guid] and entry.itemID then
				local item = findUnlinkedItem(entry.itemID)
				local status, secondsLeft = self:GetTradeStatus(entry.bag, entry.slot)
				if item then
					item.itemGUID = guid
					applyStatus(item, status, secondsLeft)
					changed = true
				elseif inRaidInstance() and qualifies(entry, status) then
					local tracked = PLC.Session:AddTrackedItem(entry.link, guid)
					if tracked then
						applyStatus(tracked, status, secondsLeft)
						changed = true
					end
				end
			end
		end
	end

	-- 2. Refresh trade time for every session item we can locate.
	for _, item in pairs(PLC.Session.items) do
		if item.itemGUID and not item.traded then
			local entry = snapshot[item.itemGUID]
			if entry then
				local before = item.tradeExpiresAt
				applyStatus(item, self:GetTradeStatus(entry.bag, entry.slot))
				-- The tooltip only has minute precision; don't churn on sub-minute differences.
				if before and item.tradeExpiresAt and math.abs(before - item.tradeExpiresAt) < 60 then
					item.tradeExpiresAt = before
				end
				changed = true
			end
		end
	end

	-- 3. RC's low-trade-time reminder, for anything still waiting to be awarded or handed over.
	if PLC.Session:IsOwner() or PLC.Session.isCollector then
		for _, item in pairs(PLC.Session.items) do
			local left = self:SecondsLeft(item)
			if left and left > 0 and not item.traded then
				for _, threshold in ipairs(REMINDER_THRESHOLDS) do
					if left <= threshold then
						remind(item, threshold)
					end
				end
			end
		end
	end

	-- Remember exactly what's in the bags now (also the baseline on the very first run, so items
	-- already owned before this feature existed are never pulled into a session).
	local nowKnown = {}
	for guid in pairs(snapshot) do
		nowKnown[guid] = true
	end
	PLC.db.char.knownBagGuids = nowKnown

	if changed then
		PLC.Session:OnTradeStatusChanged()
	end
end

PLC:RegisterOnEnable(function()
	PLC:RegisterBucketEvent({ "BAG_UPDATE" }, 1, function()
		BagTracker:Scan()
	end)
	PLC:ScheduleRepeatingTimer(function()
		BagTracker:Scan()
	end, REFRESH_SECONDS)
	PLC:ScheduleTimer(function()
		BagTracker:Scan()
	end, 3)
end)
