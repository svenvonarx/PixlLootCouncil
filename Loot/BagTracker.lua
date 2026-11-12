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
--     raid are added to the session backlog if they're review loot (Detection:IsReviewItem) that's
--     still in its trade window, or a BoE recipe
--   * RC's low-trade-time reminder in chat, and flagging items whose trade window ran out
-- Items are told apart by their item GUID (ItemLocation-based, the same API RC uses), so three
-- copies of the same oil are three separate entries with their own timers.

local REMINDER_THRESHOLDS = { 1200, 300 } -- RC warns at 20 min; a final nudge at 5
local REFRESH_SECONDS = 30
BagTracker.TRADE_WINDOW_SECONDS = 7200 -- soulbound raid loot stays tradable for 2 hours

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

local durationUnits -- [unit as the client writes it] = seconds

-- Adds a unit from the client's own format, where |4 lists its plural forms: "%d |4hour:hrs;".
local function addDurationUnit(format, seconds)
	local text = format:gsub("%%d", "")
	local before, forms, after = text:match("^(.-)|4(.-);(.*)$")
	if forms then
		for form in forms:gmatch("[^:]+") do
			durationUnits[strtrim(before .. form .. after)] = seconds
		end
	else
		durationUnits[strtrim(text)] = seconds
	end
end

-- "1 hour 52 min" / "52 min" / "45 sec" -> seconds, in any client language: "1 Stunde 52 Min.",
-- "1小时52分钟". nil if nothing could be read.
local function parseDuration(text)
	if not durationUnits then
		durationUnits = {}
		addDurationUnit(INT_SPELL_DURATION_HOURS, 3600)
		addDurationUnit(INT_SPELL_DURATION_MIN, 60)
		addDurationUnit(INT_SPELL_DURATION_SEC, 1)
	end
	local total
	for number, unit in text:gmatch("(%d+)%s*([^%d]*)") do
		local seconds = durationUnits[strtrim(unit)]
		if not seconds then
			return nil
		end
		total = (total or 0) + tonumber(number) * seconds
	end
	return total
end

-- Returns one of:
--   "timer", secondsLeft  -- soulbound, still inside the loot-trade window (secondsLeft may be nil
--                            if the time text couldn't be read -- treat as "some time left")
--   "free"                -- not bound at all (BoE, recipes, consumables): tradable, no limit
--   "bound"               -- soulbound, trade window over: not tradable
function BagTracker:GetTradeStatus(bag, slot)
	if not scanTooltip then
		scanTooltip = CreateFrame("GameTooltip", "PixlLootCouncilScanTooltip", nil, "GameTooltipTemplate")
		-- Escape pattern magic, then turn the placeholder into a capture for the time text. Some
		-- languages have numbered it: %1$s.
		tradeTimePattern = BIND_TRADE_TIME_REMAINING
			and BIND_TRADE_TIME_REMAINING:gsub("%%1%$s", "%%s")
				:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
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
		item.tradeExpiresAt = time() + (secondsLeft or BagTracker.TRADE_WINDOW_SECONDS)
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

-- How many items a bag slot holds: a stack can hold several.
local function stackCount(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		return info and info.stackCount or 1
	elseif GetContainerItemInfo then
		return select(2, GetContainerItemInfo(bag, slot)) or 1
	end
	return 1
end

-- Everything in the bags right now: [guid] = { bag, slot, link, itemID }, every itemID seen, with or
-- without a GUID, and how many of each there are.
local function snapshotBags()
	local snapshot, itemIDs, counts = {}, {}, {} -- itemIDs: [itemID] = an entry with a GUID, or true
	local getNumSlots, getLink = getContainerFns()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, getNumSlots(bag) or 0 do
			local link = getLink(bag, slot)
			if link then
				local itemID = itemIDFromString(link)
				if itemID then
					counts[itemID] = (counts[itemID] or 0) + stackCount(bag, slot)
				end
				local guid = BagTracker:GetItemGUID(bag, slot)
				if guid then
					snapshot[guid] = { bag = bag, slot = slot, link = link, itemID = itemID }
				end
				-- Prefer a copy with a GUID, whose trade status can be read.
				if itemID and type(itemIDs[itemID]) ~= "table" then
					itemIDs[itemID] = guid and snapshot[guid] or true
				end
			end
		end
	end
	return snapshot, itemIDs, counts
end

-- Does a newly bagged raid item belong in the loot session backlog?
local function qualifies(entry, status)
	local Detection = PLC.Loot.Detection
	local _, _, quality = C_Item.GetItemInfo(entry.link)
	if not Detection:IsReviewItem(entry.link, quality) then
		return false
	end
	if status == "free" then
		return select(6, C_Item.GetItemInfoInstant(entry.link)) == Detection.RECIPE_CLASS_ID
	end
	return status == "timer"
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

-- Items that left the bags without being awarded: traded or handed out some other way (such as
-- another loot addon), mailed, sold, banked or destroyed. They can't be handed out from here anymore,
-- so they leave the list. To be sure it's really gone and not a moment the game doesn't report the
-- bags fully, no copy of that item may be left in the bags, and it has to stay missing for GONE_AFTER
-- seconds, across more than one scan.
local GONE_AFTER = 10

-- Collected raid loot that's in the bags but never got its own GUID: it joined a stack, such as a
-- second Nether Vortex. Items added by hand (/plc additem) may be in someone else's bags, so they
-- don't count.
local function isStackedCopy(item)
	return not item.itemGUID and item.bagged and not item.lootSlot and item.instance ~= nil
end
local missingSince = setmetatable({}, { __mode = "k" }) -- [session item] = time first missed

local function findGoneItems(snapshot, itemIDs)
	local Session = PLC.Session
	local gone = {}
	if Session.preview or not Session:CanManage() then
		return gone
	end
	local now = time()
	for idx, item in pairs(Session.items) do
		local missing = (item.itemGUID or isStackedCopy(item)) and not item.awarded and not item.traded
			and not (item.itemGUID and snapshot[item.itemGUID]) and not itemIDs[itemIDFromString(item.itemString) or 0]
		if not missing then
			missingSince[item] = nil
		elseif not missingSince[item] then
			missingSince[item] = now
		elseif now - missingSince[item] >= GONE_AFTER then
			gone[#gone + 1] = idx
		end
	end
	return gone
end

-- More copies of an item listed than the bags hold: one was listed twice, however that happened (a
-- slow server, corpses sharing loot). The extras leave the list, unawarded ones without a bag copy
-- of their own first, after the same wait as for gone items. What's awarded and not yet traded is
-- still in the bags, so it counts too, but is never removed here.
local excessSince = {} -- [itemID] = time the extra copies were first seen

local function inBags(item)
	return not item.traded and (item.itemGUID or (item.bagged and not item.lootSlot)) and item.instance ~= nil
end

local function findExtraCopies(counts, snapshot)
	local Session = PLC.Session
	local extra = {}
	if Session.preview or not Session:CanManage() then
		wipe(excessSince)
		return extra
	end
	local copies = {} -- [itemID] = { idx, ... }
	for idx, item in pairs(Session.items) do
		local itemID = itemIDFromString(item.itemString)
		if itemID and inBags(item) then
			copies[itemID] = copies[itemID] or {}
			table.insert(copies[itemID], idx)
		end
	end
	local now = time()
	for itemID in pairs(excessSince) do
		if not copies[itemID] then
			excessSince[itemID] = nil
		end
	end
	for itemID, idxs in pairs(copies) do
		local held = counts[itemID] or 0
		-- None held at all is for findGoneItems, which knows each copy's own GUID.
		local excess = held > 0 and #idxs - held or 0
		if excess <= 0 then
			excessSince[itemID] = nil
		elseif not excessSince[itemID] then
			excessSince[itemID] = now
		elseif now - excessSince[itemID] >= GONE_AFTER then
			table.sort(idxs, function(a, b)
				local ia, ib = Session.items[a], Session.items[b]
				if (ia.itemGUID ~= nil) ~= (ib.itemGUID ~= nil) then
					return ib.itemGUID ~= nil -- without a GUID of its own first
				end
				return a > b -- then the newest
			end)
			for _, idx in ipairs(idxs) do
				if excess == 0 then
					break
				end
				-- Never one whose own copy is in the bags: that one is real. The one that isn't may
				-- be an awarded item handed over outside the addon, which stays for Loot Trades.
				local item = Session.items[idx]
				if not item.awarded and not (item.itemGUID and snapshot[item.itemGUID]) then
					table.insert(extra, idx)
					excess = excess - 1
				end
			end
			excessSince[itemID] = nil
		end
	end
	return extra
end

local function dropExtraCopies(extra)
	local Session = PLC.Session
	local links = {}
	for i, idx in ipairs(extra) do
		links[i] = Session.items[idx].link or "?"
	end
	if Session:RemoveItems(extra) == 0 then
		return
	end
	for _, link in ipairs(links) do
		print(L["CHAT_PREFIX"] .. string.format(L["BAGS_ITEM_LISTED_TWICE"], link))
	end
end

local function dropGoneItems(gone)
	local Session = PLC.Session
	local links = {}
	for i, idx in ipairs(gone) do
		links[i] = Session.items[idx].link or "?"
	end
	if Session:RemoveItems(gone) == 0 then
		return
	end
	for _, link in ipairs(links) do
		print(L["CHAT_PREFIX"] .. string.format(L["BAGS_ITEM_GONE"], link))
	end
	-- A review pass with nothing left to review ends, like after Remove All.
	if Session:IsHolder() then
		for _, item in pairs(Session.items) do
			if not item.awarded then
				return
			end
		end
		Session:End()
	end
end

-- Collected loot that's kept or left in the window now (Data/ExcludedItems.lua), but wasn't when it
-- was collected, such as raw epic gems: it leaves the list. Items added by hand (/plc additem) stay.
local function dropExcludedItems()
	local Session = PLC.Session
	if Session.preview or not Session:CanManage() then
		return
	end
	local excluded, example = {}, nil
	for idx, item in pairs(Session.items) do
		local itemID = itemIDFromString(item.itemString)
		if itemID and (PLC.PersonalLootItems[itemID] or PLC.ItemRules.IsKeptOrLeft(itemID)) and not item.awarded
			and (item.instance or item.boss) then
			excluded[#excluded + 1] = idx
			example = example or item.link
		end
	end
	if #excluded > 0 and Session:RemoveItems(excluded) > 0 then
		print(L["CHAT_PREFIX"] .. string.format(L["SESSION_DROPPED_EXCLUDED"], #excluded, example or "?"))
	end
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

-- Only the session owner/collector tracks bags: that's whoever physically holds the raid's loot. In
-- raider mode nothing new is picked up, whatever reaches the bags.
local function isTracking()
	if PLC.CouncilRules:IsRaiderMode() then
		return false
	end
	return PLC.Session:IsOwner() or PLC.Session.isCollector or PLC.CouncilRules:AmIMasterLooter()
end

function BagTracker:Scan()
	if not hasGuidApi() then
		return
	end
	local snapshot, itemIDs, counts = snapshotBags()
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
					-- It's in the bags now, however it got there (this addon's self-loot, autoloot,
					-- or Blizzard's own master-loot list) -- the loot slot no longer means anything.
					item.bagged = true
					item.lootSlot = nil
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

	-- 2. Refresh trade time for every session item we can locate. A copy that joined a stack reads
	-- the stack's.
	for _, item in pairs(PLC.Session.items) do
		if not item.traded then
			local entry = item.itemGUID and snapshot[item.itemGUID]
			if not entry and isStackedCopy(item) then
				local copy = itemIDs[itemIDFromString(item.itemString) or 0]
				entry = type(copy) == "table" and copy or nil
			end
			if entry then
				local before, wasBoe, wasUntradable = item.tradeExpiresAt, item.boe, item.untradable
				applyStatus(item, self:GetTradeStatus(entry.bag, entry.slot))
				-- The tooltip only has minute precision; don't churn on sub-minute differences.
				if before and item.tradeExpiresAt and math.abs(before - item.tradeExpiresAt) < 60 then
					item.tradeExpiresAt = before
				end
				-- Only a real change counts: every scan saying "changed" redrew the windows each time
				-- the bags moved.
				if item.tradeExpiresAt ~= before or item.boe ~= wasBoe or item.untradable ~= wasUntradable then
					changed = true
				end
			end
		end
	end

	-- 3. What left the bags without being awarded leaves the list. Not on the very first scan,
	-- which has no baseline yet. Nor does what isn't reviewed anymore.
	dropExcludedItems()
	if not firstRun then
		local gone = findGoneItems(snapshot, itemIDs)
		if #gone > 0 then
			dropGoneItems(gone)
		end
		local extra = findExtraCopies(counts, snapshot)
		if #extra > 0 then
			dropExtraCopies(extra)
		end
	end

	-- 4. RC's low-trade-time reminder, for anything still waiting to be awarded or handed over.
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
