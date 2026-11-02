-- Run from the addon folder: luajit tests/options_test.lua
--
-- Builds the real Options window against stub frames that remember their anchors, and runs the real
-- version logic. It can't show how the window looks, only that everything is where it should be.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.time = function() return 1000 end
local clock = 100
_G.GetTime = function() return clock end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.tinsert = table.insert
_G.UISpecialFrames = {}
_G.UIParent = {}
_G.RAID_CLASS_COLORS = { HUNTER = { r = 0.6, g = 0.8, b = 0.4 } }
_G.UIFrameFadeIn = function() end
_G.hooksecurefunc = function() end
_G.C_Item = { GetItemInfo = function() return nil end, GetItemInfoInstant = function() return nil end }
_G.CreateColor = function() return {} end

local frames = {}
local function stub(extra)
	local f = extra or {}
	f.points, f.scripts, f.hooks, f.shown = {}, {}, {}, true
	frames[#frames + 1] = f
	return setmetatable(f, { __index = function(_, k)
		if k == "SetPoint" then return function(s, ...) s.points[#s.points + 1] = { ... } end end
		if k == "Show" then return function(s) s.shown = true; if s.hooks.OnShow then s.hooks.OnShow(s) end end end
		if k == "Hide" then return function(s) s.shown = false end end
		if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
		if k == "IsShown" then return function(s) return s.shown end end
		if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
		if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
		if k == "SetText" then return function(s, v) s.text = v end end
		if k == "GetText" then return function(s) return s.text end end
		if k == "SetWidth" then return function(s, v) s.width = v end end
		if k == "SetHeight" then return function(s, v) s.height = v end end
		if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
		if k == "HasFocus" then return function() return false end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return stub() end end
		return function() end
	end })
end
_G.CreateFrame = function() return stub() end
_G.ColorPickerFrame = stub()

local loc = setmetatable({}, { __index = function(_, k) return k end })
_G.LibStub = function() return { GetLocale = function() return loc end } end

local PLC = { UI = { Widgets = {} }, Loot = {}, Comms = { Sync = {} } }
function PLC:RegisterOnEnable() end
function PLC:RegisterSlashCommand(name, _, fn) PLC["slash_" .. name] = fn end
function PLC:ScheduleTimer() return {} end
function PLC:ScheduleRepeatingTimer() return {} end
assert(loadfile("UI/Theme.lua"))("PixlLootCouncil", PLC)
local texts = {} -- every label, with the text it was created with
PLC.UI.Widgets.Primitives = setmetatable({
	color = function() return 1, 1, 1, 1 end,
	createText = function(_, text) local t = stub({ text = text }); texts[#texts + 1] = t; return t end,
	createTexture = function() return stub() end,
	createLogo = function() return stub({ isLogo = true }) end,
	createBorder = function() return {} end,
	createSeparator = function() return stub() end,
	createCloseButton = function() return stub() end,
	createEditBox = function() local b = stub(); b.GetValue = function(s) return s.text or "" end; return b end,
}, { __index = function() return function() return stub() end end })
PLC.UI.Widgets.Button = { createButton = function(_, text, width) return stub({ width = width, label = stub({ text = text }), caption = text }) end }
PLC.UI.Widgets.Checkbox = { createCheckbox = function() return stub({ label = stub() }) end }
PLC.UI.Widgets.Slider = { createSlider = function() return stub({ container = stub(), valueText = stub() }) end }
PLC.UI.Widgets.Dropdown = { createDropdownButton = function() return stub() end, setEntries = function(d, text) d.displayText = text end }
PLC.UI.Widgets.ScrollFrame = { RESERVED_WIDTH = 11 }
local tables = {}
PLC.UI.Widgets.DataTable = { Create = function(_, rowHeight)
	local t = { rowHeight = rowHeight, SetColumns = function(s, c) s.columns = c end, SetRows = function(s, r) s.rows = r end }
	tables[#tables + 1] = t
	return t
end }
assert(loadfile("UI/Widgets/PanelLayout.lua"))("PixlLootCouncil", PLC)

assert(loadfile("Core/Defaults.lua"))("PixlLootCouncil", PLC)
local function copy(v) if type(v) ~= "table" then return v end local o = {} for k, x in pairs(v) do o[k] = copy(x) end return o end
PLC.db = { profile = copy(PLC.Defaults.profile), char = {} }
PLC.CouncilRules = { GetGuildRanks = function() return {} end }
PLC.Responses = { MAX_COUNT = 7, MAX_TEXT_LETTERS = 12, GetConfigured = function() return {} end, Save = function() end, Reset = function() end, NewKey = function() return "K" end }
PLC.Loot.AutoLoot = { SELF = "self", LEAVE = "leave" }
PLC.ExcludedItems = { [32897] = true }
PLC.Session = { preview = false }
PLC.Preview = { Toggle = function() end }
PLC.author, PLC.website, PLC.version = "Pixl", "https://example.invalid", "v0.4.0"
local myGuid = "Player-1-AAAA"
_G.UnitGUID = function() return myGuid end
local members = {
	[myGuid] = { name = "Pixl-Realm", class = "HUNTER" },
	["Player-1-BBBB"] = { name = "Current-Realm", class = "HUNTER" },
	["Player-1-CCCC"] = { name = "Older-Realm", class = "HUNTER" },
	["Player-1-DDDD"] = { name = "Noaddon-Realm", class = "HUNTER" },
}
PLC.Roster = { IterateGroup = function() return pairs(members) end, ShortName = function(_, n) return n:match("^[^-]+") end }
local checks, answers = 0, 0
PLC.Comms.Sync.SendVersionCheck = function() checks = checks + 1 end
local lastPing
PLC.Comms.Sync.SendPresence = function(_, guid, version) answers = answers + 1; lastPing = { guid, version } end
assert(loadfile("Data/Presence.lua"))("PixlLootCouncil", PLC)
assert(loadfile("UI/OptionsFrame.lua"))("PixlLootCouncil", PLC)
local Presence = PLC.Presence

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

-- Layout --------------------------------------------------------------------------------------------
frames = {}
PLC.UI.OptionsFrame:Open()
local navIcons, navRows, sectionTitles = {}, {}, {}
for _, f in ipairs(frames) do
	if rawget(f, "wash") then navRows[#navRows + 1] = f end
end
for _, t in ipairs(texts) do
	if tostring(t.text):find("OPTIONS_SECTION_", 1, true) then sectionTitles[#sectionTitles + 1] = t end
end
local function leftOf(region) return region.points[1][2] end
local titleX = leftOf(sectionTitles[1])
local allFull, allAligned = #navRows == 7, true
for _, row in ipairs(navRows) do
	local left, right = row.points[1], row.points[2]
	allFull = allFull and left[1] == "TOPLEFT" and left[2] == 0 and right[1] == "TOPRIGHT" and right[2] == 0
	allAligned = allAligned and row.icon.points[1][1] == "LEFT" and row.icon.points[1][2] == titleX
end
check("L1", allFull, "all 7 menu rows run from edge to edge")
check("L2", allAligned, "every icon starts where the section titles start, x=" .. tostring(titleX))
local sameTitles = #sectionTitles == 3
for _, t in ipairs(sectionTitles) do sameTitles = sameTitles and leftOf(t) == titleX end
check("L3", sameTitles, "all 3 section titles share that edge")
local bar = navRows[1].bar.points
check("L4", bar[1][1] == "TOPLEFT" and bar[1][2] == nil and bar[2][1] == "BOTTOMLEFT", "the selection bar sits on the row's far left")
local logoX
for _, f in ipairs(frames) do
	if rawget(f, "isLogo") and f.points[1] and f.points[1][1] == "LEFT" then logoX = f.points[1][2] end
end
check("L5", logoX == titleX, "the title bar's logo is on the same edge: " .. tostring(logoX))
local stacked = true
for i = 2, #navRows do
	stacked = stacked and navRows[i].points[1][3] <= navRows[i - 1].points[1][3] - 30
end
check("L6", stacked, "rows don't overlap")
local nameTables = 0
for _, t in ipairs(tables) do if t.rowHeight == 20 then nameTables = nameTables + 1 end end
check("L7", nameTables == 3, "the Auto Loot, Council and About lists all get their row height: " .. nameTables)

-- Pages fit the window: a stub can't measure text, but it can add up what's stacked.
local Theme = PLC.UI.Theme.LAYOUT
local available = 640 - Theme.headerHeight - 2 - Theme.contentPadding * 2 - 48 - 20
local width = 580 - 2 - Theme.sidebarWidth - 1 - Theme.contentPadding * 2
check("L8", available >= 482, "General's 482 of stacked settings fit in " .. available)
check("L9", width >= 384 and 130 + 100 + 140 + 11 <= width and 92 + 290 <= width, "the widest rows fit in " .. width)

-- Versions ------------------------------------------------------------------------------------------
local N = Presence.IsNewer
check("V1", N("v0.4.0", "v0.3.0") and N("v0.3.1", "v0.3.0") and N("v1.0.0", "v0.9.9") and not N("v0.3.0", "v0.4.0") and not N("v0.3.0", "v0.3.0"), "numbers compare as numbers")
check("V2", N("v0.10.0", "v0.9.0"), "0.10 is newer than 0.9")
check("V3", N("v0.3.0", "v0.3.0-beta") and not N("v0.3.0-beta", "v0.3.0") and not N("v0.3.0-beta", "v0.3.0-beta"), "a release beats its own beta")
check("V4", not N("@project-version@", "v0.3.0") and not N("v0.3.0", "@project-version@") and not N("v0.3.0", nil), "a development copy is never newer or older")

Presence:RecordVersion("Player-1-BBBB", "v0.4.0")
check("V5", Presence.newest == nil and #printed == 0, "the same version says nothing")
Presence:RecordVersion("Player-1-EEEE", "v0.5.0")
Presence:RecordVersion("Player-1-FFFF", "v0.6.0")
local notices = 0
for _, line in ipairs(printed) do if line:find("ABOUT_UPDATE_NOTICE", 1, true) then notices = notices + 1 end end
check("V6", Presence.newest == "v0.6.0" and notices == 1, "one notice, and the newest version is kept")
Presence:RecordVersion("Player-1-GGGG", "v0.5.5")
check("V7", Presence.newest == "v0.6.0", "an older one doesn't replace it")

local realVersion = PLC.version
PLC.version = nil; Presence.newest = nil
Presence:RecordVersion("Player-1-EEEE", "v9.0.0")
check("V8", Presence.newest == nil, "a development copy doesn't get told to update")
PLC.version = realVersion; Presence.newest = nil

-- The list ------------------------------------------------------------------------------------------
local versionTable
for _, t in ipairs(tables) do
	if t.columns and t.columns[2] and t.columns[2].width == 100 then versionTable = t end
end
Presence.versions = { ["Player-1-BBBB"] = "v0.4.0" }
Presence.lastSeen = { ["Player-1-CCCC"] = 950 }
Presence.newest = "v0.5.0"
PLC.UI.OptionsFrame:Open("about")
PLC.UI.OptionsFrame:OnVersionsUpdated()
local byName = {}
for _, row in ipairs(versionTable.rows) do byName[row.name] = row end
check("A1", byName.Pixl.version == "v0.4.0" and byName.Pixl.status == "ABOUT_STATUS_OUTDATED" and byName.Current.status == "ABOUT_STATUS_OUTDATED", "behind the newest version seen: outdated")
Presence.newest = nil; PLC.UI.OptionsFrame:OnVersionsUpdated()
byName = {}
for _, row in ipairs(versionTable.rows) do byName[row.name] = row end
check("A2", byName.Pixl.status == "ABOUT_STATUS_CURRENT" and byName.Current.status == "ABOUT_STATUS_CURRENT", "nothing newer: up to date")
check("A3", byName.Older.version == "ABOUT_VERSION_UNKNOWN" and byName.Older.status == "ABOUT_STATUS_OUTDATED", "has the addon but sends no version: older")
check("A4", byName.Noaddon.status == "VOTINGFRAME_NO_ADDON" and byName.Noaddon.version == "-", "no addon")
check("A5", versionTable.rows[1].name == "Current", "sorted by name")

clock = 500; checks = 0
Presence:CheckGroup(); Presence:CheckGroup(); clock = clock + 5; Presence:CheckGroup()
local throttled = checks
clock = clock + 6; Presence:CheckGroup()
check("A6", throttled == 1 and checks == 2, "a check can't be spammed")
answers = 0
Presence:OnVersionCheckReceived(); Presence:OnVersionCheckReceived()
check("A7", answers == 1 and lastPing[1] == myGuid and lastPing[2] == "v0.4.0", "answers once, with the version")

Presence:OnPresenceReceived({ guid = "Player-1-CCCC" })
check("A8", Presence.versions["Player-1-CCCC"] == nil, "a client without a version field doesn't break anything")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
