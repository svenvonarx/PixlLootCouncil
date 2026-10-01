local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local Detection = {}
PLC.Loot.Detection = Detection

-- Everything here is purely event-driven off LOOT_READY/LOOT_SLOT_CLEARED/LOOT_CLOSED/
-- START_LOOT_ROLL. This file never touches GroupLootFrame/LootFrame or any other addon's loot
-- buttons (see docs/SPECIFICATION.md §2/§3 principle 3).

Detection.lootSlotInfo = {} -- [slotIndex] = { link, icon, quantity, quality, boss, looted }
Detection.lootOpen = false
Detection.debug = false

local warnedThisSession = false

local function scanLootSlots()
	wipe(Detection.lootSlotInfo)

	if not IsInInstance() then
		return
	end
	local numItems = GetNumLootItems()
	if not numItems or numItems <= 0 then
		return
	end

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
				Detection.lootSlotInfo[i] = {
					link = link,
					icon = icon,
					quantity = quantity,
					quality = quality,
					boss = sourceGUID,
					looted = false,
				}
				if Detection.debug then
					print(L["CHAT_PREFIX"] .. string.format(L["DETECTED_SLOT"], i, link or name or "?", tostring(quality)))
				end
			end
		end
	end

	if pendingRetry then
		PLC:ScheduleTimer(scanLootSlots, 0)
	end
end

local function onLootReady()
	Detection.lootOpen = true
	scanLootSlots()

	if PLC.CouncilRules:AmIMasterLooter() and PLC.Session and PLC.Session.QueueDetectedItems then
		PLC.Session:QueueDetectedItems(Detection.lootSlotInfo)
	end

	-- UI/SessionFrame.lua doesn't exist until Stage 5 -- same guard pattern as the Session hook
	-- above. SessionFrame itself decides whether curation is actually relevant right now (no-op
	-- once a session is already active; see UI/SessionFrame.lua).
	if PLC.CouncilRules:AmIMasterLooter() and PLC.UI and PLC.UI.SessionFrame and PLC.UI.SessionFrame.OnLootReady then
		PLC.UI.SessionFrame:OnLootReady()
	end
end

local function onLootSlotCleared(eventName, slot)
	local info = Detection.lootSlotInfo[slot]
	if info then
		info.looted = true
	end
	if PLC.Loot.Award then
		PLC.Loot.Award:OnLootSlotCleared(slot)
	end
end

local function onLootClosed()
	Detection.lootOpen = false
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

PLC:RegisterSlashCommand("debug", "Toggle verbose loot-detection logging", function()
	Detection.debug = not Detection.debug
	print(L["CHAT_PREFIX"] .. (Detection.debug and L["DEBUG_ON"] or L["DEBUG_OFF"]))
end)
