-- Run from the addon folder: luajit tests/update_notice_test.lua
--
-- The real Data/Presence.lua, Data/UpdateNotice.lua, Comms/Sync.lua and Core/Defaults.lua against a
-- stubbed game.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.StaticPopupDialogs = {}
_G.CLOSE = "Close"
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end

local now = 1000000
_G.time = function() return now end
_G.GetTime = function() return now end
_G.UnitGUID = function() return "me" end
local world = {}
_G.InCombatLockdown = function() return world.combat end
_G.IsInInstance = function() return world.instance end
local popups = {}
_G.StaticPopup_Show = function(which, a, b) popups[#popups + 1] = { which, a, b } end

local onEnable, timers, handlers = {}, {}, {}
local PLC = { version = "v0.4.0", website = "https://example.invalid" }
function PLC:RegisterOnEnable(fn) onEnable[#onEnable + 1] = fn end
function PLC:ScheduleTimer(fn, delay) timers[#timers + 1] = { fn = fn, delay = delay } end
function PLC:ScheduleRepeatingTimer() end
PLC.Events = { RegisterHandler = function(_, event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end }
local guild, protocolHandlers = {}, {}
PLC.Comms = { Protocol = {
	RegisterHandler = function(_, command, fn) protocolHandlers[command] = fn end,
	Send = function(_, command, data, channel)
		if channel == "GUILD" then guild[#guild + 1] = { command = command, version = data.version } end
	end,
} }
_G.IsInGuild = function() return world.guild end
_G.IsInRaid = function() return false end
_G.IsInGroup = function() return false end
PLC.Session = { state = "inactive" }
local openedTab
PLC.UI = { OptionsFrame = { Open = function(_, tab) openedTab = tab end, OnVersionsUpdated = function() end } }

PLC.Loot = { Announce = { GetChannel = function() return nil end } }
assert(loadfile("Comms/Sync.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Core/Defaults.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/Presence.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/UpdateNotice.lua"))("PixlLootCouncil", PLC)
local Presence = PLC.Presence

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function chatLines()
	local count = 0
	for _, line in ipairs(printed) do if line:find("UPDATE_CHAT", 1, true) then count = count + 1 end end
	return count
end
local function runTimers()
	local due = timers
	timers = {}
	for _, timer in ipairs(due) do timer.fn() end
end
local function fire(event) for _, fn in ipairs(handlers[event] or {}) do fn() end end
local function login()
	Presence.newest, Presence.versions = nil, {}
	for k in pairs(printed) do printed[k] = nil end
	for k in pairs(popups) do popups[k] = nil end
	for k in pairs(guild) do guild[k] = nil end
	timers = {}
	for _, fn in ipairs(onEnable) do fn() end
end
local function fresh(version)
	PLC.version = version or "v0.4.0"
	PLC.db = { global = { update = {} }, profile = { updateNotices = true } }
	world.combat, world.instance, world.guild = false, false, world.guild ~= false
	PLC.Session.state = "inactive"
	login()
	runTimers()
end

check("N1", PLC.Defaults.profile.updateNotices == true and type(PLC.Defaults.global.update) == "table", "on by default, with somewhere to remember")

fresh()
check("N2", #guild == 1 and guild[1].command == "version" and guild[1].version == "v0.4.0", "the guild hears our version once at login")
protocolHandlers.version({ version = "v0.4.1" })
check("N33", Presence.newest == "v0.4.1" and Presence.versions["guild"] == nil, "hearing it from the guild counts, without joining the group's list")
Presence.newest = nil; PLC.db.global.update = {}; for k in pairs(printed) do printed[k] = nil end

Presence:NoteVersion("v0.4.1")
check("N3", chatLines() == 1 and #popups == 0, "a patch behind: one chat line, no pop-up")
Presence:NoteVersion("v0.4.1"); Presence:RecordVersion("g1", "v0.4.1")
check("N4", chatLines() == 1, "hearing it again says nothing")
Presence:NoteVersion("v0.4.2")
check("N5", chatLines() == 2, "a newer one is worth one more line")

fresh()
Presence:RecordVersion("g1", "v0.5.0")
check("N6", #popups == 1 and popups[1][1] == "PIXLLOOTCOUNCIL_UPDATE" and popups[1][2] == "v0.5.0" and popups[1][3] == "v0.4.0", "a whole version behind: the pop-up, naming both versions")
check("N7", Presence.versions.g1 == "v0.5.0", "and the About list still gets it")
StaticPopupDialogs.PIXLLOOTCOUNCIL_UPDATE.OnAccept()
check("N8", openedTab == "about", "its button opens the page with the link")
check("N9", StaticPopupDialogs.PIXLLOOTCOUNCIL_UPDATE.hasEditBox == nil, "no text box to grab the keyboard")

login()
runTimers()
check("N10", chatLines() == 0 and #popups == 0, "logging in again the same day stays quiet: the pop-up never comes back")
now = now + 86400
login()
check("N11", chatLines() == 0, "and nothing during the login spam")
runTimers()
check("N12", chatLines() == 1 and Presence.newest == "v0.5.0" and #popups == 0, "a day later, one chat line, from what was remembered")
now = now + 1
Presence:NoteVersion("v0.5.0"); fire("PLAYER_ENTERING_WORLD"); fire("PLAYER_REGEN_ENABLED")
check("N13", chatLines() == 1 and #popups == 0, "zoning and fights don't repeat anything")

Presence:NoteVersion("v0.6.0")
check("N14", #popups == 1 and popups[1][2] == "v0.6.0", "a later version gets its own pop-up")

-- Never at a bad moment --------------------------------------------------------------------------------
fresh(); world.combat = true
Presence:NoteVersion("v0.5.0")
check("N15", chatLines() == 1 and #popups == 0, "in combat: the chat line, no pop-up")
world.combat = false; fire("PLAYER_REGEN_ENABLED")
check("N16", #popups == 1, "the pop-up comes after combat")
fire("PLAYER_REGEN_ENABLED")
check("N17", #popups == 1, "once")

fresh(); world.instance = true
Presence:NoteVersion("v0.5.0"); fire("PLAYER_REGEN_ENABLED")
check("N18", #popups == 0, "not inside a raid, even between pulls")
world.instance = false; fire("PLAYER_ENTERING_WORLD")
check("N19", #popups == 1, "but after leaving it")

fresh(); PLC.Session.state = "active"
Presence:NoteVersion("v0.5.0"); fire("PLAYER_REGEN_ENABLED")
local during = #popups
PLC.Session.state = "ended"; fire("PLAYER_REGEN_ENABLED")
check("N20", during == 0 and #popups == 1, "not during a loot session either")

fresh(); world.instance = true
Presence:NoteVersion("v0.5.0")
now = now + 86400
login(); world.instance = false; runTimers()
check("N21", #popups == 1, "if it never got to show tonight, it shows at the next login")

-- Off, and false alarms ----------------------------------------------------------------------------------
fresh(); PLC.db.profile.updateNotices = false
Presence:NoteVersion("v0.5.0"); fire("PLAYER_ENTERING_WORLD")
check("N22", chatLines() == 0 and #popups == 0 and Presence.newest == "v0.5.0", "the option silences both, and About still knows")

fresh()
Presence:NoteVersion("v0.5.0")
PLC.version = "v0.5.0"
login(); runTimers()
check("N23", Presence.newest == nil and next(PLC.db.global.update) == nil, "updating clears it")

fresh()
Presence:NoteVersion("v0.5.0")
now = now + 15 * 86400
login(); runTimers()
check("N24", Presence.newest == nil and chatLines() == 0, "not heard of for two weeks: forgotten, in case it was never real")
fresh()
Presence:NoteVersion("v0.5.0")
now = now + 10 * 86400
Presence:NoteVersion("v0.5.0")
now = now + 10 * 86400
login(); runTimers()
check("N25", Presence.newest == "v0.5.0", "hearing it again keeps it alive")

fresh("@dev@"); PLC.version = nil
Presence:NoteVersion("v9.0.0")
check("N26", Presence.newest == nil and chatLines() == 0 and #popups == 0, "a development copy is never told to update")
fresh(); PLC.version = nil; login(); runTimers()
check("N27", #guild == 0, "and has no version to tell the guild")
world.guild = false; fresh(); world.guild = nil
check("N34", #guild == 0, "someone without a guild sends nothing")

fresh()
for _, bad in ipairs({ "v9.0.0|cffff0000red|r", "v9.0.0 hello", "nonsense", "", 5, {}, "v9.0.0" .. string.rep("x", 40) }) do
	Presence:NoteVersion(bad)
	Presence:RecordVersion("g2", bad)
end
check("N28", Presence.newest == nil and Presence.versions.g2 == nil, "anything that isn't really a version is ignored, and never reaches chat")
Presence:NoteVersion("v0.4.0-beta")
check("N29", Presence.newest == nil, "our own beta is older")
Presence:NoteVersion("v0.3.0")
check("N30", Presence.newest == nil, "and so is an old version")
fresh("v0.4.0-beta")
Presence:NoteVersion("v0.4.0")
check("N31", chatLines() == 1 and #popups == 0, "the final release of our beta is a chat line, not a pop-up")

check("N32", Presence.IsBigUpdate("v1.0.0", "v0.9.9") and Presence.IsBigUpdate("v0.5.0", "v0.4.9") and not Presence.IsBigUpdate("v0.4.9", "v0.4.0") and not Presence.IsBigUpdate("v0.5.0", nil), "a whole version means major or minor")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
