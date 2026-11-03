-- Run from the addon folder: luajit tests/autoloot_test.lua
--
-- The real Loot/Detection.lua, Loot/AutoLoot.lua, Loot/Award.lua and Data/ExcludedItems.lua against
-- a stubbed loot window: Shift taking a window by hand, and loot everyone takes their own copy of.
local out = print
_G.print = function() end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strsplit = function(sep, s) local a, b = s:match("^(.-)" .. sep .. "(.*)$"); if a then return a, b end return s end
_G.strlower = string.lower
_G.MAX_RAID_MEMBERS = 40
_G.LOOT_SLOT_MONEY = 2
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end

-- The loot window ----------------------------------------------------------------------------------
local BADGE, HELM, BLUE = 29434, 30001, 30002
local loot, shift, actions = {}, false, {}
local function link(id) return "|cff|Hitem:" .. id .. ":0:0|h[" .. id .. "]|h|r" end
local function open(...)
	loot = {}
	for i, item in ipairs({ ... }) do loot[i] = { id = item[1], quality = item[2] } end
	actions = {}
end
_G.GetNumLootItems = function() return #loot end
_G.LootSlotHasItem = function(slot) return loot[slot] ~= nil and not loot[slot].gone end
_G.GetLootSlotInfo = function(slot)
	local item = loot[slot]
	return "icon", tostring(item.id), 1, nil, item.quality, false, false, nil, false
end
_G.GetLootSlotLink = function(slot) return loot[slot] and not loot[slot].gone and link(loot[slot].id) or nil end
_G.GetLootSourceInfo = function() return "Creature-0-1" end
_G.GetLootSlotType = function() return 1 end
_G.GetLootThreshold = function() return 2 end
_G.GetMasterLootCandidate = function(_, index) return ({ "Pixl", "Mule" })[index] end
_G.GiveMasterLoot = function(slot, index) actions[#actions + 1] = "give " .. loot[slot].id .. " " .. index end
_G.LootSlot = function(slot) actions[#actions + 1] = "take " .. loot[slot].id end
_G.IsShiftKeyDown = function() return shift end
_G.IsInInstance = function() return true end
_G.GetInstanceInfo = function() return "Karazhan", "raid", 3, "10 Player", 10, 0, false, 532, 10 end
_G.UnitGUID = function() return "Player-1" end
_G.UnitName = function() return "Pixl" end
_G.C_Item = { GetItemInfoInstant = function(l)
	local id = tonumber(tostring(l):match("item:(%d+)"))
	return id, nil, nil, nil, nil, id == BADGE and 10 or 4
end }

local handlers, ticks = {}, {}
local PLC = { Loot = {}, Events = { RegisterHandler = function(_, event, fn) handlers[event] = fn end } }
function PLC:ScheduleTimer() return {} end
function PLC:ScheduleRepeatingTimer(fn) local t = { fn = fn }; ticks[#ticks + 1] = t; return t end
function PLC:CancelTimer(t) if t then t.cancelled = true end end
function PLC:RegisterSlashCommand() end
PLC.db = { profile = { lootThreshold = 4, autoLoot = {
	enabled = true, lootGold = false, outsideInstances = false, reviewTarget = "self", otherTarget = "leave", exceptions = {},
} } }
PLC.CouncilRules = { AmIMasterLooter = function() return true end }
local noted = {}
PLC.Session = { CollectDetectedItems = function(_, slots, delivered)
	for _, info in pairs(slots) do
		if PLC.Loot.Detection:IsReviewItem(info.link, info.quality) then
			noted[#noted + 1] = (delivered and "bagged " or "noted ") .. info.link:match("item:(%d+)")
		end
	end
end }
for _, file in ipairs({ "Data/ExcludedItems.lua", "Loot/Award.lua", "Loot/AutoLoot.lua", "Loot/Detection.lua" }) do
	assert(loadfile(file))("PixlLootCouncil", PLC)
end

local function tick()
	for _, t in ipairs(ticks) do
		if not t.cancelled then t.fn() end
	end
end
-- The server confirms whatever's in flight: the slot empties.
local function confirm()
	local pending = PLC.Loot.Award.pending
	if pending then
		loot[pending.slot].gone = true
		handlers.LOOT_SLOT_CLEARED("LOOT_SLOT_CLEARED", pending.slot)
	end
end
local function close()
	handlers.LOOT_CLOSED()
	ticks, noted = {}, {}
end

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

-- Shift ----------------------------------------------------------------------------------------------
open({ HELM, 4 })
shift = true
handlers.LOOT_READY()
shift = false
handlers.LOOT_READY() -- the game can fire it again for the same window
tick(); tick()
check("S1", #actions == 0, "Shift held when the window opens: nothing is handed out")
check("S2", noted[1] == "noted " .. HELM, "even after letting go of Shift before the window's second LOOT_READY")
close()

open({ HELM, 4 })
handlers.LOOT_READY()
tick(); confirm(); tick()
check("S3", actions[1] == "give " .. HELM .. " 1" and noted[1] == "bagged " .. HELM, "without Shift, auto loot hands it out")
close()

open({ HELM, 4 }, { HELM + 10, 4 }, { HELM + 20, 4 })
handlers.LOOT_READY()
tick(); confirm()
shift = true
tick()
shift = false
tick(); tick()
check("S4", #actions == 1, "pressing Shift with the window open stops it there")
check("S5", table.concat(noted, ",") == "bagged " .. HELM .. ",noted " .. (HELM + 10) .. ",noted " .. (HELM + 20)
	or table.concat(noted, ",") == "bagged " .. HELM .. ",noted " .. (HELM + 20) .. ",noted " .. (HELM + 10),
	"and what's left is noted for the master looter to take, once each")
handlers.LOOT_READY()
tick()
check("S6", #actions == 1, "and it stays theirs for the rest of the window")
close()

open({ HELM, 4 })
handlers.LOOT_READY()
tick()
check("S7", #actions == 1, "the next window is automatic again")
close()

-- Badge of Justice -----------------------------------------------------------------------------------
open({ BADGE, 4 }, { HELM, 4 })
handlers.LOOT_READY()
tick(); confirm(); tick(); confirm()
check("B1", actions[1] == "take " .. BADGE, "auto loot takes the master looter's own badge, without the master loot list")
check("B2", #noted == 1 and noted[1] == "bagged " .. HELM, "and it never joins a session, while the helm does")
close()

PLC.db.profile.autoLoot.exceptions[BADGE] = "Mule"
check("B3", PLC.Loot.AutoLoot:GetTarget(link(BADGE), 4) == "self", "no exception can send someone else's badge away")
PLC.db.profile.autoLoot.exceptions[BADGE] = nil

open({ BADGE, 4 })
shift = true
handlers.LOOT_READY()
shift = false
check("B4", #noted == 0 and not PLC.Loot.Detection:IsReviewItem(link(BADGE), 4), "looted by hand, it isn't review loot either")
close()

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
