-- Run from the addon folder: luajit tests/timers_test.lua
--
-- The real Core/Init.lua over a stand-in for AceTimer that behaves like the real one where it
-- matters: an error in a repeating timer's callback ends that timer, as the next run is only
-- scheduled once the callback returns.
local out = print
_G.print = function() end
local reported = {}
_G.geterrorhandler = function() return function(message) reported[#reported + 1] = tostring(message) end end
_G.C_AddOns = { GetAddOnMetadata = function() return nil end }

local timers = {}
local aceTimer = {}
function aceTimer:ScheduleRepeatingTimer(func, delay, ...)
	local timer = { func = func, delay = delay, args = { ... }, count = select("#", ...), runs = 0 }
	timers[#timers + 1] = timer
	return timer
end
local function fire(timer)
	if timer.stopped then return end
	local ok = pcall(timer.func, unpack(timer.args, 1, timer.count))
	timer.runs = timer.runs + 1
	if not ok then timer.stopped = true end -- what AceTimer does: no next run
end

_G.LibStub = function(name)
	if name == "AceAddon-3.0" then
		return { NewAddon = function(_, addon)
			for k, v in pairs(aceTimer) do addon[k] = v end
			addon.RegisterChatCommand = function() end
			return addon
		end }
	end
	if name == "AceLocale-3.0" then
		return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end }
	end
	return {}
end

local PLC = {}
assert(loadfile("Core/Init.lua"))("PixlLootCouncil", PLC)

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

local calls = 0
local timer = PLC:ScheduleRepeatingTimer(function()
	calls = calls + 1
	if calls == 1 then error("PixlLootCouncil/UI/LootFrame.lua:1: boom") end
end, 1)
fire(timer); fire(timer); fire(timer)
check("T1", calls == 3 and not timer.stopped, "a repeating timer keeps going after its callback fails")
check("T2", #reported == 1 and reported[1]:find("boom", 1, true), "and the error still reaches the error handler, for /plc errors")

local got
function PLC:Tick(a, b) got = { self, a, b } end
local byName = PLC:ScheduleRepeatingTimer("Tick", 5, "x", nil)
fire(byName)
check("T3", got and got[1] == PLC and got[2] == "x" and got[3] == nil and byName.delay == 5, "a method name and arguments work as before")

-- Game events: several parts of the addon listen to the same one (Core/Events.lua).
local Events = {}
do
	local host = { RegisterEvent = function() end }
	assert(loadfile("Core/Events.lua"))("PixlLootCouncil", host)
	Events = host.Events
end
local heard = {}
Events:RegisterHandler("LOOT_READY", function() error("first one breaks") end)
Events:RegisterHandler("LOOT_READY", function(_, arg) heard[#heard + 1] = arg end)
local reportedBefore = #reported
Events.Dispatch("LOOT_READY", "corpse")
check("E1", heard[1] == "corpse", "one listener failing doesn't keep the others from hearing the event")
check("E2", #reported == reportedBefore + 1 and reported[#reported]:find("first one breaks", 1, true) ~= nil, "and the error is still reported")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
