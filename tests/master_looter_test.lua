-- Run from the addon folder: luajit tests/master_looter_test.lua
--
-- The real Loot/MasterLooterList.lua, Data/CouncilRules.lua and Core/Events.lua against a stubbed group.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.strlower = string.lower
_G.strsplit = function(sep, s) return s:match("^(.-)" .. sep) or s end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.UNKNOWNOBJECT = "Unknown"
_G.Enum = { LootMethod = { Masterlooter = 2, Group = 3 } }
_G.ITEM_QUALITY3_DESC, _G.ITEM_QUALITY4_DESC = "Rare", "Epic"
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end

local world, calls, thresholds, timers
local function reset(roster)
	world = { method = 3, master = nil, roster = roster, inGroup = true, leader = true, shift = false, combat = false,
		threshold = 2, acceptsThreshold = true }
	calls, thresholds, timers = {}, {}, {}
	for k in pairs(printed) do printed[k] = nil end
end
reset({})
local function unitIndex(unit) return tonumber(unit:match("^raid(%d+)$")) end
_G.UnitName = function(unit)
	if unit == "player" then return "Pixl" end
	local member = world.roster[unitIndex(unit) or 0]
	return member and member.name
end
_G.UnitIsConnected = function(unit)
	local member = world.roster[unitIndex(unit) or 0]
	return member and member.online ~= false
end
_G.IsInRaid = function() return world.inGroup end
_G.IsInGroup = function() return world.inGroup end
_G.GetNumGroupMembers = function() return #world.roster end
_G.GetNumSubgroupMembers = function() return 0 end
_G.UnitIsGroupLeader = function() return world.leader end
_G.UnitIsUnit = function(a, b) return UnitName(a) == UnitName(b) end
_G.IsShiftKeyDown = function() return world.shift end
_G.InCombatLockdown = function() return world.combat end
_G.GetLootThreshold = function() return world.threshold end
_G.SetLootThreshold = function(quality)
	thresholds[#thresholds + 1] = quality
	if world.acceptsThreshold then world.threshold = quality end
end
_G.C_PartyInfo = {
	GetLootMethod = function()
		if world.method ~= 2 then return world.method end
		return 2, nil, world.master
	end,
	SetLootMethod = function(method, name)
		calls[#calls + 1] = { method = method, name = name }
		for i, member in ipairs(world.roster) do
			if member.name == name then world.master = i end
		end
		PLC_dispatch("PARTY_LOOT_METHOD_CHANGED") -- the game reports the change back
	end,
}

local PLC = { Loot = {} }
function PLC:RegisterEvent() end
function PLC:RegisterOnEnable() end
function PLC:ScheduleTimer(callback, delay) timers[#timers + 1] = { callback = callback, delay = delay } end
assert(loadfile("Core/Events.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/CouncilRules.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Core/Defaults.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Loot/MasterLooterList.lua"))("PixlLootCouncil", PLC)
function PLC_dispatch(event) PLC.Events.Dispatch(event) end
local List = PLC.Loot.MasterLooterList
PLC.db = { profile = { autoMasterLooter = true, masterLooterList = {}, masterLootThreshold = 0 } }

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function saw(text)
	for _, line in ipairs(printed) do if line:find(text, 1, true) then return true end end
	return false
end
local function group(list, ...)
	local roster = { { name = "Pixl" } }
	for _, member in ipairs({ ... }) do roster[#roster + 1] = type(member) == "table" and member or { name = member } end
	reset(roster)
	PLC.db.profile.masterLooterList, PLC.db.profile.autoMasterLooter, PLC.db.profile.masterLootThreshold = list, true, 0
	world.inGroup = false; List:OnRosterRebuilt() -- forget the last test's group
	world.inGroup = true; List:OnRosterRebuilt()
end
-- The leader switches to Master Loot: the game makes them master looter and reports it.
local function switchToMaster()
	world.method, world.master = 2, 1
	PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
end

group({ "Mule", "Backup" }, "Other", "Backup", "Mule"); switchToMaster()
check("M1", #calls == 1 and calls[1].name == "Mule" and calls[1].method == 2 and world.master == 4, "the first on the list gets it, whatever the raid order")
check("M2", saw("ML_ASSIGNED"), "and chat says who")

group({ "Absent", "Backup", "Mule" }, "Mule", "Backup"); switchToMaster()
check("M3", calls[1] and calls[1].name == "Backup", "someone not in the group is skipped")

group({ "Mule", "Backup" }, { name = "Mule", online = false }, "Backup"); switchToMaster()
check("M4", calls[1] and calls[1].name == "Backup", "someone offline is skipped")

group({ "mULE" }, "Mule"); switchToMaster()
check("M5", calls[1] and calls[1].name == "Mule", "capitalization doesn't matter, and the game's spelling is sent")

group({ "Mule-Spineshatter" }, "Mule"); switchToMaster()
check("M6", calls[1] and calls[1].name == "Mule", "a name with a realm matches too")

group({ "Pixl", "Mule" }, "Mule"); switchToMaster()
check("M7", #calls == 0 and world.master == 1, "first on the list is me: nothing to change")

group({ "Absent" }, "Mule"); switchToMaster()
check("M8", #calls == 0 and saw("ML_NOBODY"), "nobody found: chat says so, and it stays with me")

group({}, "Mule"); switchToMaster()
check("M9", #calls == 0 and #printed == 0, "an empty list does nothing, quietly")

group({ "Mule" }, "Mule"); PLC.db.profile.autoMasterLooter = false; switchToMaster()
check("M10", #calls == 0, "the option turns it off")

group({ "Mule" }, "Mule"); world.leader = false; switchToMaster()
check("M11", #calls == 0, "only the leader can, so nobody else tries")

group({ "Mule" }, "Mule"); world.shift = true; switchToMaster()
check("M12", #calls == 0, "Shift skips it once")

group({ "Mule" }, "Mule", "Other"); switchToMaster()
world.master = 3; PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
check("M13", #calls == 1 and world.master == 3, "handing it to someone else afterwards sticks")

group({ "Mule" }, "Mule", "Other"); switchToMaster()
world.roster[#world.roster + 1] = { name = "Backup" }; List:OnRosterRebuilt()
check("M14", #calls == 1, "someone joining changes nothing")

group({ "Mule" }, "Mule"); world.combat = true; switchToMaster()
local deferred = #calls == 0
PLC_dispatch("PLAYER_REGEN_DISABLED")
world.combat = false; PLC_dispatch("PLAYER_REGEN_ENABLED")
check("M15", deferred and calls[1] and calls[1].name == "Mule", "in combat it waits until combat ends")
world.roster[#world.roster + 1] = { name = "Other" }
world.master = #world.roster; PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
PLC_dispatch("PLAYER_REGEN_ENABLED")
check("M16", #calls == 1 and world.master == #world.roster, "and only once: handing it on later still sticks after the next fight")

group({ "Mule" }, "Mule"); world.combat = true; switchToMaster()
world.method = 3; world.combat = false; PLC_dispatch("PLAYER_REGEN_ENABLED")
check("M17", #calls == 0, "not if the group left Master Loot in the meantime")

-- Logging in or reloading mid-raid, with Master Loot already on, must never reassign anything.
group({ "Mule" }, "Mule", "Other")
world.inGroup = false; List:OnRosterRebuilt() -- a fresh login: group not known yet
world.inGroup, world.method, world.master = true, 2, 3
PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
check("M18", #calls == 0, "login: the first report of Master Loot isn't a switch")
world.inGroup = false; List:OnRosterRebuilt()
world.inGroup = true; List:OnRosterRebuilt()
PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
check("M19", #calls == 0, "reload: the same, whichever comes first")

group({ "Mule" }, "Mule"); switchToMaster()
world.method = 3; PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
switchToMaster()
check("M20", #calls == 2, "switching away and back counts again")

-- The loot threshold ------------------------------------------------------------------------------
local function runTimers()
	local due = timers
	timers = {}
	for _, timer in ipairs(due) do timer.callback() end
end
local function thresholdGroup(list, quality, ...)
	group(list, ...)
	PLC.db.profile.masterLootThreshold = quality
end

check("M21", PLC.db.profile.masterLootThreshold == 0, "the default leaves the threshold alone")

thresholdGroup({ "Mule" }, 3, "Mule"); switchToMaster()
check("M22", #thresholds == 0 and timers[1] and timers[1].delay >= 2, "it waits for the loot method change to land")
runTimers()
check("M23", thresholds[1] == 3 and #thresholds == 1 and #calls == 1, "then sets it, after the master looter has moved")
runTimers()
check("M24", #thresholds == 1 and #printed == 1, "and the check after it stays quiet when it worked")

thresholdGroup({}, 4, "Mule"); switchToMaster(); runTimers()
check("M25", thresholds[1] == 4, "it works without a list")

thresholdGroup({ "Mule" }, 3, "Mule"); PLC.db.profile.autoMasterLooter = false; switchToMaster(); runTimers()
check("M26", #calls == 0 and thresholds[1] == 3, "and with the list turned off")

thresholdGroup({ "Mule" }, 0, "Mule"); switchToMaster(); runTimers()
check("M27", #thresholds == 0, "Don't change doesn't")

thresholdGroup({}, 2, "Mule"); switchToMaster(); runTimers()
check("M28", #thresholds == 0, "already right: nothing to send, so no chat line from the game")

thresholdGroup({}, 3, "Mule"); world.shift = true; switchToMaster(); runTimers()
check("M29", #thresholds == 0, "Shift skips it too")

thresholdGroup({}, 3, "Mule"); world.leader = false; switchToMaster(); runTimers()
check("M30", #thresholds == 0, "only the leader can, so nobody else tries")

thresholdGroup({ "Mule" }, 3, "Mule"); world.combat = true; switchToMaster(); runTimers()
local waited = #thresholds == 0
world.combat = false; PLC_dispatch("PLAYER_REGEN_ENABLED"); runTimers()
check("M31", waited and thresholds[1] == 3, "in combat it waits until combat ends")

thresholdGroup({}, 3, "Mule"); switchToMaster()
world.method = 3; PLC_dispatch("PARTY_LOOT_METHOD_CHANGED"); runTimers()
check("M32", #thresholds == 0, "not if the group left Master Loot during the wait")

thresholdGroup({}, 3, "Mule"); world.acceptsThreshold = false; switchToMaster(); runTimers()
local quiet = #printed == 0
runTimers()
check("M33", quiet and saw("ML_THRESHOLD_FAILED"), "if the game ignores it, chat says so afterwards")

-- The point of the whole thing: only the switch itself does anything.
thresholdGroup({ "Mule" }, 3, "Mule", "Other"); switchToMaster(); runTimers(); runTimers()
world.threshold = 4; PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
world.master = 3; PLC_dispatch("PARTY_LOOT_METHOD_CHANGED")
world.roster[#world.roster + 1] = { name = "Backup" }; List:OnRosterRebuilt(); runTimers()
check("M34", #thresholds == 1 and #calls == 1 and world.threshold == 4 and world.master == 3, "changing the threshold or the master looter by hand afterwards sticks")

thresholdGroup({ "Mule" }, 3, "Mule")
world.inGroup = false; List:OnRosterRebuilt()
world.inGroup, world.method, world.master = true, 2, 2
PLC_dispatch("PARTY_LOOT_METHOD_CHANGED"); List:OnRosterRebuilt(); runTimers()
check("M35", #thresholds == 0, "logging in with Master Loot on doesn't touch it")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
