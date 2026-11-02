local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local MasterLooterList = {}
PLC.Loot.MasterLooterList = MasterLooterList

-- When the group leader switches the group to Master Loot, the game makes them master looter. This
-- passes it on to the first person on profile.masterLooterList who's online in the group, and sets
-- the loot threshold to profile.masterLootThreshold. Only at that moment: changing either later is
-- deliberate and has to stick, so a change of who's master looter on its own, or someone joining,
-- does nothing.
--
-- wasMaster is what tells a real switch apart from the game just reporting the current method, which
-- it does while logging in: it stays nil until the group is known, and the first report only sets it.
local wasMaster
local pending = false -- switched during combat, when the game won't take the change

-- A threshold sent right after a loot method change gets lost, so MRT and Gargul both wait too.
local THRESHOLD_DELAY = 2
local THRESHOLD_CHECK_DELAY = 1

local function groupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			units[i] = "raid" .. i
		end
	else
		units[1] = "player"
		for i = 1, GetNumSubgroupMembers() do
			units[i + 1] = "party" .. i
		end
	end
	return units
end

-- The first name on the list that's online in the group, as the game spells it.
function MasterLooterList:FindFirst()
	local online = {}
	for _, unit in ipairs(groupUnits()) do
		local name = UnitName(unit)
		if name and UnitIsConnected(unit) then
			online[strlower(name)] = name
		end
	end
	for _, entry in ipairs(PLC.db.profile.masterLooterList) do
		local found = online[strlower((strsplit("-", entry)))]
		if found then
			return found
		end
	end
	return nil
end

local function canChangeLoot()
	return PLC.CouncilRules:IsMasterLootMethod() and UnitIsGroupLeader("player")
end

local function assign()
	if not PLC.db.profile.autoMasterLooter or not next(PLC.db.profile.masterLooterList) then
		return
	end
	local name = MasterLooterList:FindFirst()
	if not name then
		print(L["CHAT_PREFIX"] .. L["ML_NOBODY"])
		return
	end
	local current = PLC.CouncilRules:GetMasterLooterUnit()
	if current and UnitName(current) == name then
		return
	end
	C_PartyInfo.SetLootMethod(Enum.LootMethod.Masterlooter, name)
	print(L["CHAT_PREFIX"] .. string.format(L["ML_ASSIGNED"], name))
end

local function setThreshold()
	local wanted = PLC.db.profile.masterLootThreshold
	if wanted == 0 or not canChangeLoot() or GetLootThreshold() == wanted then
		return
	end
	SetLootThreshold(wanted) -- the game announces this in chat itself
	PLC:ScheduleTimer(function()
		if canChangeLoot() and GetLootThreshold() ~= wanted then
			print(L["CHAT_PREFIX"] .. string.format(L["ML_THRESHOLD_FAILED"], _G["ITEM_QUALITY" .. wanted .. "_DESC"]))
		end
	end, THRESHOLD_CHECK_DELAY)
end

local function applySwitch()
	if not canChangeLoot() then
		return
	end
	if InCombatLockdown() then
		pending = true
		return
	end
	assign()
	PLC:ScheduleTimer(setThreshold, THRESHOLD_DELAY)
end

local function onLootMethodChanged()
	local isMaster = PLC.CouncilRules:IsMasterLootMethod()
	local switched = wasMaster == false and isMaster
	wasMaster = isMaster
	if switched and not IsShiftKeyDown() then
		applySwitch()
	end
end

-- Called by Data/Roster.lua: the group is known from here on, and leaving it starts over.
function MasterLooterList:OnRosterRebuilt()
	if not IsInGroup() then
		wasMaster = nil
		pending = false
	elseif wasMaster == nil then
		wasMaster = PLC.CouncilRules:IsMasterLootMethod()
	end
end

PLC.Events:RegisterHandler("PARTY_LOOT_METHOD_CHANGED", onLootMethodChanged)
PLC.Events:RegisterHandler("PLAYER_REGEN_ENABLED", function()
	if pending then
		pending = false
		applySwitch()
	end
end)
