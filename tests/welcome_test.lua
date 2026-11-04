-- Run from the addon folder: luajit tests/welcome_test.lua
--
-- The real UI/WelcomeFrame.lua and Data/RCImport.lua against stub widgets and a fake
-- RCLootCouncil saved file: the first-time welcome, its steps, the import and the reset.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.NEED, _G.GREED, _G.CANCEL = "Need", "Greed", "Cancel"
_G.CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local world = { combat = false, rcInstalled = false }
_G.InCombatLockdown = function() return world.combat end
_G.UnitName = function() return "Pixl" end
_G.GetRealmName = function() return "Realm" end
_G.C_AddOns = { GetAddOnInfo = function(name)
	if name == "RCLootCouncil_Classic" and world.rcInstalled then return name, "RC", "", true, nil end
	return name, nil, nil, false, "MISSING"
end }
local known = { ["Player-1-AAAA"] = { "Mage", "MAGE", "Human", "Human", 2, "Ana", "" } }
_G.GetPlayerInfoByGUID = function(guid) local i = known[guid]; if i then return unpack(i) end end
local popups, reloaded = {}, 0
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which) popups[#popups + 1] = which end
_G.ReloadUI = function() reloaded = reloaded + 1 end

-- Frames that remember what's done to them ---------------------------------------------------------------
local function stub(extra)
	local f = extra or {}
	f.points, f.scripts, f.hooks, f.shown = {}, {}, {}, true
	return setmetatable(f, { __index = function(_, k)
		if k == "SetPoint" then return function(s, ...) s.points[#s.points + 1] = { ... } end end
		if k == "Show" then return function(s)
			local was = s.shown
			s.shown = true
			if not was and s.hooks.OnShow then s.hooks.OnShow(s) end
		end end
		if k == "Hide" then return function(s)
			local was = s.shown
			s.shown = false
			if was and s.scripts.OnHide then s.scripts.OnHide(s) end
		end end
		if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
		if k == "IsShown" then return function(s) return s.shown end end
		if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
		if k == "HookScript" then return function(s, n, fn)
			local before = s.hooks[n]
			s.hooks[n] = before and function(...) before(...); fn(...) end or fn
		end end
		if k == "SetText" then return function(s, v) s.text = v end end
		if k == "SetChecked" then return function(s, v) s.checked = v end end
		if k == "SetValue" then return function(s, v) s.value = v end end
		if k == "ShowValue" then return function(s, v) s.shownValue = v end end
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
_G.CreateFrame = function() return stub() end
_G.UIParent = stub()

local PLC = { UI = { Widgets = {} } }
local onEnable, timers = {}, {}
function PLC:RegisterOnEnable(fn) onEnable[#onEnable + 1] = fn end
function PLC:RegisterEvent() end
function PLC:ScheduleTimer(fn, delay) timers[#timers + 1] = { fn = fn, delay = delay } end
local slash = {}
function PLC:RegisterSlashCommand(name, _, fn) slash[name] = fn end
local texts = {}
PLC.UI.Theme = { LAYOUT = setmetatable({}, { __index = function() return 24 end }) }
PLC.UI.Widgets.Primitives = setmetatable({
	createText = function(_, text) local t = stub({ text = text }); texts[#texts + 1] = t; return t end,
	createCloseButton = function() return stub({ isClose = true }) end,
	createBorder = function() return {} end,
	color = function() return 1, 1, 1, 1 end,
}, { __index = function() return function() return stub() end end })
PLC.UI.Widgets.Button = { createButton = function(_, text) return stub({ caption = text }) end }
PLC.UI.Widgets.Checkbox = { createCheckbox = function(_, text, onChanged) return stub({ caption = text, onChanged = onChanged }) end }
PLC.UI.Widgets.Slider = { createSlider = function() return stub({ container = stub() }) end }
local optionsOpened = false
PLC.UI.OptionsFrame = { Open = function() optionsOpened = true end }
local historyImports = 0
PLC.History = {
	HasLocalRCData = function() return world.rcHistory == true end,
	ImportFromLocalRC = function() historyImports = historyImports + 1; return 12 end,
}
local rebuilt = 0
PLC.Roster = { Rebuild = function() rebuilt = rebuilt + 1 end }
PLC.CouncilRules = { SetRaiderMode = function(_, on) PLC.db.profile.raiderMode = on end }

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[k] = deepcopy(x) end
	return c
end
assert(loadfile("Core/Events.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Core/Defaults.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/Responses.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/RCImport.lua"))("PixlLootCouncil", PLC)
assert(loadfile("UI/WelcomeFrame.lua"))("PixlLootCouncil", PLC)
local Welcome, RCImport = PLC.UI.WelcomeFrame, PLC.RCImport
local resets = { db = 0, loot = 0 }

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function freshAccount()
	PLC.db = { global = {}, profile = deepcopy(PLC.Defaults.profile), char = {},
		ResetDB = function() resets.db = resets.db + 1 end }
	PLC.lootDB = { ResetDB = function() resets.loot = resets.loot + 1 end }
	_G.RCLootCouncilDB = nil
	world.rcInstalled, world.rcHistory, world.combat = false, false, false
	timers = {}
	for k in pairs(printed) do printed[k] = nil end
end
local function login()
	for _, fn in ipairs(onEnable) do fn() end
end
local function runTimers()
	local due = timers
	timers = {}
	for _, timer in ipairs(due) do timer.fn() end
end
local function find(caption)
	for _, t in ipairs(texts) do if t.text == caption then return t end end
end
-- First time ------------------------------------------------------------------------------------------
freshAccount()
login()
check("W1", #timers == 1 and timers[1].delay >= 3 and not Welcome:IsShown(), "on a first login it waits for the loading screen to pass")
runTimers()
check("W2", Welcome:IsShown() and Welcome:CurrentStep() == "role" and not PLC.db.global.onboarded, "then opens on the first question, without counting as seen yet")
check("W3", find("WELCOME_RAIDER") and find("WELCOME_LOOTMASTER") and find("WELCOME_RAIDER_TEXT"), "two big choices with an explanation each")

-- The window keeps its steps and frame to itself; a test reaches them through the functions using them.
local function upvalue(fn, wanted)
	local i = 1
	while true do
		local name, value = debug.getupvalue(fn, i)
		if not name then return nil end
		if name == wanted then return value end
		i = i + 1
	end
end
local steps = upvalue(Welcome.ShowStep, "steps")
local frame = upvalue(Welcome.IsShown, "frame")

-- Raider: done in one click
check("W4", steps.role and steps.rc and steps.setup and steps.done, "it has the four steps")
steps.role.raider.scripts.OnClick()
check("W5", PLC.db.global.onboarded and not Welcome:IsShown() and printed[#printed]:find("WELCOME_RAIDER_DONE", 1, true), "Raider: done, with a line saying the window will come by itself")
login()
check("W6", #timers == 0, "and it doesn't come back next login")
check("W6a", PLC.db.profile.raiderMode == true, "and as master looter, the addon leaves the loot alone (raider mode)")

freshAccount()
Welcome:Open()
frame = upvalue(Welcome.IsShown, "frame")
frame:Hide() -- what Escape and the close button do
check("W7", PLC.db.global.onboarded == true, "closing it any other way counts as seen too, so it never nags")

freshAccount()
world.combat = true
login()
runTimers()
check("W8", not Welcome:IsShown(), "not in combat")
world.combat = false
PLC.Events.Dispatch("PLAYER_REGEN_ENABLED")
check("W9", Welcome:IsShown(), "but right after it")
frame:Hide()

-- Loot master, no RCLootCouncil ---------------------------------------------------------------------------
freshAccount()
Welcome:Open()
PLC.db.profile.raiderMode = true -- picked Raider before, now /plc setup
steps.role.master.scripts.OnClick()
check("W10a", PLC.db.profile.raiderMode == false, "Loot Master turns raider mode off")
check("W10", Welcome:CurrentStep() == "setup" and not steps.setup.rcNote.shown, "a loot master without RCLootCouncil goes straight to the essentials")
local profile = PLC.db.profile
steps.setup.autoLoot.onChanged(false)
steps.setup.council.onChanged(false)
steps.setup.announce.onChanged(false)
steps.setup.slider.scripts.OnValueChanged(steps.setup.slider, 90)
check("W11", profile.autoLoot.enabled == false and profile.council.raidAssist == false and profile.announce.sessionStart == false
	and profile.announce.award == false and profile.responseTimeoutSeconds == 90, "each choice is saved as it's made")
steps.setup.finish.scripts.OnClick()
check("W12", Welcome:CurrentStep() == "done" and steps.done.summary.text:find("WELCOME_SETUP_SAVED", 1, true), "Finish: the last page says it's saved")
steps.done.options.scripts.OnClick()
check("W13", optionsOpened and not Welcome:IsShown() and PLC.db.global.onboarded, "and can open Options, closing itself")

freshAccount()
world.rcInstalled = true -- there, but not enabled on this character: nothing to read
Welcome:Open()
steps.role.master.scripts.OnClick()
check("W14", Welcome:CurrentStep() == "setup" and steps.setup.rcNote.shown, "RCLootCouncil installed but disabled: the essentials, with a note on how to import")
steps.setup.back.scripts.OnClick()
check("W15", Welcome:CurrentStep() == "role", "Back goes back")
frame:Hide()

-- Loot master with RCLootCouncil ----------------------------------------------------------------------------
local function rcAccount(rcProfile, extra)
	freshAccount()
	world.rcInstalled, world.rcHistory = true, true
	_G.RCLootCouncilDB = { profileKeys = { ["Pixl - Realm"] = "Raid" }, profiles = { Raid = rcProfile, Default = { timeout = 11 } },
		global = { playerCache = { ["Player-1-BBBB"] = { name = "Bo-Realm" } } } }
	for k, v in pairs(extra or {}) do _G.RCLootCouncilDB[k] = v end
end
rcAccount({
	timeout = 90, announceItems = false, autoStart = true, minRank = 3,
	council = { "Player-1-AAAA", "Player-1-BBBB", "Player-1-CCCC" },
	buttons = { default = { [1] = { text = "Main" }, numButtons = 4, [4] = { text = "Transmog" } } },
	responses = { default = { [2] = { color = { 0.1, 0.2, 0.3, 1 } } } },
})
Welcome:Open()
steps.role.master.scripts.OnClick()
check("W16", Welcome:CurrentStep() == "rc", "a loot master with RCLootCouncil is offered the import")
steps.rc.import.scripts.OnClick()
profile = PLC.db.profile
local summary = steps.done.summary.text
check("W17", Welcome:CurrentStep() == "done" and historyImports == 1 and summary:find("WELCOME_IMPORTED_HISTORY", 1, true), "Import: one click brings the history over")
check("W18", profile.responseTimeoutSeconds == 90 and profile.announce.sessionStart == false and profile.autoStartSession == true and profile.announce.award == true,
	"and the settings that were changed there, leaving the others as they were here")
check("W19", profile.council.guildRanks[0] and profile.council.guildRanks[1] and profile.council.guildRanks[2] and not profile.council.guildRanks[3],
	"its minimum rank becomes these guild ranks (rank 1 is the guild master)")
check("W20", profile.council.manualList["Ana"] and profile.council.manualList["Bo-Realm"] and summary:find("WELCOME_IMPORTED_UNKNOWN", 1, true),
	"council names come from RCLootCouncil's own cache or the game, and anyone unknown is mentioned")
local buttons = PLC.Responses:GetConfigured()
local texts4 = {}
for i, b in ipairs(buttons) do texts4[i] = b.text end
check("W21", table.concat(texts4, ",") == "Main,Greed,RC_MINOR_UPGRADE,Transmog,RESPONSE_PASS", "its buttons come over, the ones it saved only partly filled in from its defaults: " .. table.concat(texts4, ","))
check("W22", buttons[2].color.r == 0.1 and buttons[2].color.b == 0.3 and buttons[1].color.g == 1, "with their colors, saved or default")
check("W23", rebuilt == 1, "and the council is worked out again")
steps.done.done.scripts.OnClick()
check("W24", not Welcome:IsShown() and PLC.db.global.onboarded, "Done closes it")

rcAccount({})
local before = deepcopy(PLC.db.profile)
local result = RCImport:Import()
local same = PLC.db.profile.responseTimeoutSeconds == before.responseTimeoutSeconds and PLC.db.profile.autoStartSession == before.autoStartSession
	and PLC.db.profile.customResponses == nil and next(PLC.db.profile.council.guildRanks) == nil
check("W25", same and result.timeout == nil and result.buttons == nil, "nothing changed in RCLootCouncil: nothing of ours changes, not even to its defaults")

rcAccount({ timeout = 900, buttons = { default = { numButtons = 9,
	{ text = "A" }, { text = "B" }, { text = "C" }, { text = "D" }, { text = "E" }, { text = "F" }, { text = "G" }, { text = "H" }, { text = "I" } } } })
RCImport:Import()
local capped = PLC.Responses:GetConfigured()
check("W26", PLC.db.profile.responseTimeoutSeconds == 300 and #capped == 7 and capped[7].key == "PASS",
	"out-of-range values are kept in range, and buttons to our maximum, still ending with Pass")
rcAccount({ buttons = { default = { numButtons = 5 } } })
RCImport:Import()
check("W33", #PLC.Responses:GetConfigured() == 4, "buttons it never named are left out, rather than imported as \"Button\"")
rcAccount({ timeout = false })
RCImport:Import()
check("W27", PLC.db.profile.responseTimeoutSeconds == PLC.Defaults.profile.responseTimeoutSeconds, "RCLootCouncil's timeout turned off leaves ours alone")
rcAccount({ timeout = 45 })
_G.RCLootCouncilDB.profileKeys = {}
_G.RCLootCouncilDB.profiles.Default = { timeout = 75 }
RCImport:Import()
check("W28", PLC.db.profile.responseTimeoutSeconds == 75, "the character's own RCLootCouncil profile, or Default")

-- Again, and resetting ---------------------------------------------------------------------------------------
freshAccount()
PLC.db.global.onboarded = true
slash.setup()
check("W29", Welcome:IsShown() and Welcome:CurrentStep() == "role", "/plc setup shows it again, from the start")
frame:Hide()
slash.reset()
check("W30", popups[#popups] == "PIXLLOOTCOUNCIL_RESET" and resets.db == 0 and reloaded == 0, "/plc reset asks first, and does nothing yet")
local dialog = StaticPopupDialogs.PIXLLOOTCOUNCIL_RESET
check("W31", dialog.showAlert and dialog.text == "RESET_CONFIRM_TEXT" and dialog.button2 == "Cancel", "with a warning, and a way out")
dialog.OnAccept()
check("W32", resets.db == 1 and resets.loot == 1 and reloaded == 1, "deleting wipes the settings and the loot history, then reloads")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
