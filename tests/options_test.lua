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
_G.ITEM_QUALITY2_DESC, _G.ITEM_QUALITY3_DESC, _G.ITEM_QUALITY4_DESC, _G.ITEM_QUALITY5_DESC = "Uncommon", "Rare", "Epic", "Legendary"
_G.ITEM_QUALITY_COLORS = { [2] = { r = 0.1, g = 1, b = 0 }, [3] = { r = 0, g = 0.4, b = 0.9 }, [4] = { r = 0.6, g = 0.2, b = 0.9 }, [5] = { r = 1, g = 0.5, b = 0 } }

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
		if k == "GetStringHeight" then return function() return 14 end end
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

local loc = setmetatable({ OPTIONS_SECONDS = "%d seconds", OPTIONS_MINUTE = "%d minute", OPTIONS_MINUTES = "%d minutes" },
	{ __index = function(_, k) return k end })
_G.LibStub = function() return { GetLocale = function() return loc end } end

local PLC = { UI = { Widgets = {} }, Loot = {}, Comms = { Sync = {} } }
function PLC:RegisterOnEnable() end
function PLC:RegisterSlashCommand(name, _, fn) PLC["slash_" .. name] = fn end
function PLC:ScheduleTimer() return {} end
function PLC:ScheduleRepeatingTimer() return {} end
assert(loadfile("UI/Theme.lua"))("PixlLootCouncil", PLC)
local texts = {} -- every label, with the text it was created with
local tooltips = {} -- [frame] = { title, text }
PLC.UI.Widgets.Primitives = setmetatable({
	color = function() return 1, 1, 1, 1 end,
	createText = function(_, text)
		local t = stub({ text = text })
		texts[#texts + 1] = t
		return PLC.UI.Theme:Track(t, "text", "text")
	end,
	hasInter = true,
	fontNames = function() return { "Inter", "Arial Narrow", "Morpheus" } end,
	fontPath = function(name) return "path/" .. name end,
	setFont = function(name) PLC.chosenFont = name end,
	setBorderColor = function(border, color) border.color = color end,
	createTexture = function() return stub() end,
	createLogo = function() return stub({ isLogo = true }) end,
	createBorder = function() return {} end,
	createSeparator = function() return stub() end,
	createCloseButton = function() return stub() end,
	createEditBox = function() local b = stub(); b.GetValue = function(s) return s.text or "" end; return b end,
	attachTooltip = function(frame, title, text) tooltips[frame] = { title, text } end,
}, { __index = function() return function() return stub() end end })
PLC.UI.Widgets.Button = { createArrowButton = function(_, pointsUp) return stub({ pointsUp = pointsUp }) end, createButton = function(_, text, width) return stub({ width = width, label = stub({ text = text }), caption = text }) end }
local checkboxes, dropdowns = {}, {}
PLC.UI.Widgets.Checkbox = { createCheckbox = function(_, text)
	local box = stub({ label = stub(), caption = text })
	box.SetChecked = function() end
	checkboxes[#checkboxes + 1] = box
	return box
end }
PLC.UI.Widgets.Dropdown = {
	createDropdownButton = function()
		local d = stub({ text = stub() })
		d.text.SetTextColor = function(s, r, g, b) s.color = { r, g, b } end
		dropdowns[#dropdowns + 1] = d
		return d
	end,
	setEntries = function(d, text, entries) d.displayText, d.entries = text, entries end,
}
assert(loadfile("UI/Widgets/Slider.lua"))("PixlLootCouncil", PLC)
local sliders = {}
do
	local create = PLC.UI.Widgets.Slider.createSlider
	PLC.UI.Widgets.Slider.createSlider = function(...)
		local slider = create(...)
		sliders[#sliders + 1] = slider
		return slider
	end
end
PLC.UI.Widgets.ScrollFrame = { RESERVED_WIDTH = 11, createScrollFrame = function(parent)
	local scroll = stub({ width = 360, parent = parent })
	scroll.SetScrollChild = function(s, child) s.child = child end
	scroll.GetWidth = function(s) return s.width end
	return scroll
end }
PLC.Changelog = { Get = function()
	return {
		{ title = "1.1.0", items = { { level = 0, text = "Intro" }, { level = 1, text = "First" }, { level = 2, text = "Nested" } } },
		{ title = "1.0.0", items = { { level = 1, text = "Older" } } },
	}
end }
PLC.UI.WelcomeFrame = { Open = function() PLC.welcomeOpened = true end, ConfirmReset = function() PLC.resetAsked = true end }
local tables = {}
PLC.UI.Widgets.DataTable = { Create = function(_, rowHeight)
	local t = { rowHeight = rowHeight, SetColumns = function(s, c) s.columns = c end, SetRows = function(s, r) s.rows = r end }
	tables[#tables + 1] = t
	return t
end }
assert(loadfile("UI/Widgets/PanelLayout.lua"))("PixlLootCouncil", PLC)

assert(loadfile("Core/Defaults.lua"))("PixlLootCouncil", PLC)
local function copy(v) if type(v) ~= "table" then return v end local o = {} for k, x in pairs(v) do o[k] = copy(x) end return o end
PLC.db = { profile = copy(PLC.Defaults.profile), char = {}, global = {} }
PLC.CouncilRules = { GetGuildRanks = function() return {} end }
PLC.Responses = { MAX_COUNT = 7, MAX_TEXT_LETTERS = 12, GetConfigured = function() return {} end, Save = function() end, Reset = function() end, NewKey = function() return "K" end }
PLC.Loot.AutoLoot = { SELF = "self", LEAVE = "leave" }
PLC.ExcludedItems = { [32897] = true }
PLC.UnreviewedItems = { [32229] = true }
PLC.Session = { preview = false }
PLC.Preview = { Toggle = function() end }
local updateNotices = 0
PLC.UpdateNotice = { Remember = function() end, Notify = function() updateNotices = updateNotices + 1 end }
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
local allFull, allAligned = #navRows == 9, true
for _, row in ipairs(navRows) do
	local left, right = row.points[1], row.points[2]
	allFull = allFull and left[1] == "TOPLEFT" and left[2] == 0 and right[1] == "TOPRIGHT" and right[2] == 0
	allAligned = allAligned and row.icon.points[1][1] == "LEFT" and row.icon.points[1][2] == titleX
end
check("L1", allFull, "all 9 menu rows run from edge to edge")
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

-- The right-hand side -------------------------------------------------------------------------------
local stretched = #sliders == 3
for _, slider in ipairs(sliders) do
	local first, second = slider.container.points[1], slider.container.points[2]
	stretched = stretched and first[1] == "TOPLEFT" and second and second[1] == "TOPRIGHT" and second[2] == 0
	local track = slider.points
	stretched = stretched and track[1][1] == "BOTTOMLEFT" and track[2][1] == "BOTTOMRIGHT"
end
check("S1", stretched, "sliders run the full width of the page")
local shown = {}
for _, t in ipairs(texts) do if t.points and t.points[1] and t.points[1][1] == "TOPRIGHT" and t.text then shown[#shown + 1] = t.text end end
check("S2", table.concat(shown, ","):find("60 seconds", 1, true) ~= nil and table.concat(shown, ","):find("10 minutes", 1, true) ~= nil, "values are lined up on the right, with units: " .. table.concat(shown, ", "))
local quality
for _, d in ipairs(dropdowns) do if d.displayText == "Epic" then quality = d end end
check("S3", quality ~= nil and quality.text.color[1] == 0.6, "minimum quality reads Epic, in its color")
quality.entries[2].onClick()
check("S4", PLC.db.profile.lootThreshold == 3 and quality.displayText == "Rare" and quality.entries[2].checked, "choosing Rare saves it")
PLC.db.profile.lootThreshold = 4
local names = {}
for i, entry in ipairs(quality.entries) do names[i] = entry.text end
check("S5", table.concat(names, ",") == "Uncommon,Rare,Epic,Legendary" and quality.entries[3].color == ITEM_QUALITY_COLORS[4], "the choices are names, in the game's colors")

-- Tooltips ------------------------------------------------------------------------------------------
local bare = {}
for _, box in ipairs(checkboxes) do
	if not tooltips[box] or tostring(tooltips[box][2]):sub(1, 4) ~= "TIP_" then bare[#bare + 1] = tostring(box.caption) end
end
for _, slider in ipairs(sliders) do
	if not tooltips[slider.container] then bare[#bare + 1] = "slider" end
end
if not tooltips[quality] then bare[#bare + 1] = "quality" end
check("T1", #bare == 0, "every checkbox, slider and the quality choice explains itself (" .. #checkboxes .. " checkboxes, " .. #sliders .. " sliders)" .. (#bare > 0 and ": missing " .. table.concat(bare, ", ") or ""))

-- The master looter list ----------------------------------------------------------------------------
local mlTable
for _, t in ipairs(tables) do if t.rowHeight == 26 then mlTable = t end end
check("P1", mlTable ~= nil and #mlTable.columns == 4, "the list has names, up, down and remove")
local profile = PLC.db.profile
local nameBox, addButton
for _, f in ipairs(frames) do
	if rawget(f, "caption") == "OPTIONS_COUNCIL_ADD" then addButton = f end
end
local mlThreshold
for frame, tip in pairs(tooltips) do
	if tip[2] == "TIP_ML_LIST" then nameBox = frame end
	if tip[2] == "TIP_ML_THRESHOLD" then mlThreshold = frame end
end
nameBox.points = nameBox.points
local function add(name) nameBox.text = name; nameBox.scripts.OnEnterPressed() end
add("mule"); add("Backup"); add("MULE"); add("   ")
check("P2", table.concat(profile.masterLooterList, ",") == "Mule,Backup", "names are capitalized, duplicates and blanks skipped: " .. table.concat(profile.masterLooterList, ","))
check("P3", mlTable.rows[2].name == "Backup" and mlTable.columns[1].render(mlTable.rows[2]) == "  2.  Backup", "the order shows as numbers")
local up = stub({ points = {} })
mlTable.columns[2].update(up, mlTable.rows[2])
up.scripts.OnClick()
check("P4", profile.masterLooterList[1] == "Backup", "moving someone up changes who's first")
local firstUp = stub()
mlTable.columns[2].update(firstUp, mlTable.rows[1])
check("P5", firstUp.shown == false, "the first row has no up button")
local upArrow, downArrow = mlTable.columns[2].create(stub()), mlTable.columns[3].create(stub())
check("P11", upArrow.pointsUp == true and downArrow.pointsUp == false, "the list's buttons are real arrows, the right way up")
local remove = stub()
mlTable.columns[4].update(remove, mlTable.rows[1])
remove.scripts.OnClick()
check("P6", #profile.masterLooterList == 1 and profile.masterLooterList[1] == "Mule", "removing someone")
profile.masterLooterList = {}
names = {}
for i, entry in ipairs(mlThreshold.entries) do names[i] = entry.text end
check("P7", table.concat(names, ",") == "OPTIONS_ML_THRESHOLD_NONE,Uncommon,Rare,Epic" and mlThreshold.displayText == "OPTIONS_ML_THRESHOLD_NONE", "the threshold defaults to leaving it, and offers what the game's menu does")
mlThreshold.entries[2].onClick()
check("P8", profile.masterLootThreshold == 2 and mlThreshold.displayText == "Uncommon" and mlThreshold.text.color[2] == 1, "choosing Uncommon saves it, in its color")
mlThreshold.entries[1].onClick()
check("P9", profile.masterLootThreshold == 0 and mlThreshold.entries[1].checked and mlThreshold.text.color[1] == 1 and mlThreshold.text.color[3] == 1, "going back to Don't change drops the color")

local previewButton
for _, f in ipairs(frames) do
	if rawget(f, "caption") == "OPTIONS_PREVIEW_START" then previewButton = f end
end
PLC.UI.OptionsFrame:OnPreviewChanged()
local previewIdle = previewButton.label.text
PLC.Session.preview = true
PLC.UI.OptionsFrame:OnPreviewChanged()
local previewRunning = previewButton.label.text
PLC.Session.preview = false
PLC.UI.OptionsFrame:OnPreviewChanged()
check("P10", previewIdle == "OPTIONS_PREVIEW_START" and previewRunning == "OPTIONS_PREVIEW_STOP" and previewButton.label.text == "OPTIONS_PREVIEW_START", "the Preview button follows the preview, however it starts or ends")

-- Appearance ----------------------------------------------------------------------------------------
local cards = {}
for frame, tip in pairs(tooltips) do
	if tip[2] == "TIP_THEME" then cards[#cards + 1] = frame end
end
local function cardOrder(card)
	local point = card.points[1]
	return -point[#point] * 10 + (point[2] == 0 and 0 or 1)
end
table.sort(cards, function(a, b) return cardOrder(a) < cardOrder(b) end)
check("A1", #cards == #PLC.UI.Theme.THEMES and #cards == 8, "a card for every theme, each explaining itself")
check("A2", cards[1].key == "gold" and cards[1].border.color == "accent" and cards[2].border.color == "border", "the default theme is first and marked")
local left, right = cards[1], cards[2]
check("A3", left.points[1][1] == "TOPLEFT" and left.points[2][2] ~= nil and right.points[2][1] == "TOPRIGHT" and right.points[2][2] == 0, "two columns, reaching the page's right edge")
local goldAccent = PLC.UI.Theme.COLORS.accent
cards[3].scripts.OnClick()
check("A4", profile.theme == cards[3].key and PLC.UI.Theme.COLORS.accent ~= goldAccent, "clicking a card saves it and recolors everything")
check("A5", cards[3].border.color == "accent" and cards[1].border.color == "border", "and moves the mark")
cards[2].scripts.OnEnter(cards[2]); cards[2].scripts.OnLeave(cards[2])
check("A6", cards[2].border.color == "border" and cards[3].border.color == "accent", "hovering leaves it where it was")
cards[1].scripts.OnClick()

local fontField
for frame, tip in pairs(tooltips) do if tip[2] == "TIP_FONT" then fontField = frame end end
names = {}
for i, entry in ipairs(fontField.entries) do names[i] = entry.text end
check("A7", table.concat(names, ",") == "Inter,Arial Narrow,Morpheus" and fontField.displayText == "Inter" and fontField.entries[1].checked, "the registered fonts, with the current one marked")
check("A8", fontField.entries[2].font == "path/Arial Narrow", "each shown in its own font")
fontField.entries[2].onClick()
check("A9", profile.font == "Arial Narrow" and PLC.chosenFont == "Arial Narrow" and fontField.displayText == "Arial Narrow" and fontField.entries[2].checked, "picking one saves it and applies it")
profile.font = "Inter"

-- Pages fit the window: a stub can't measure text, but it can add up what's stacked.
local Theme = PLC.UI.Theme.LAYOUT
local available = 640 - Theme.headerHeight - 2 - Theme.contentPadding * 2 - 48 - 20
local width = 580 - 2 - Theme.sidebarWidth - 1 - Theme.contentPadding * 2
check("L8", available >= 456, "General's 456 of stacked settings fit in " .. available)
check("L10", available >= 400, "the About page's 400 fit too")
check("L11", available >= 24 + 4 * (46 + 8) + 14 + 28, "the Appearance page's theme cards and font fit too")
check("L9", width >= 384 and 130 + 100 + 140 + 11 <= width and 92 + 290 <= width, "the widest rows fit in " .. width)

-- Versions ------------------------------------------------------------------------------------------
local N = Presence.IsNewer
check("V1", N("v0.4.0", "v0.3.0") and N("v0.3.1", "v0.3.0") and N("v1.0.0", "v0.9.9") and not N("v0.3.0", "v0.4.0") and not N("v0.3.0", "v0.3.0"), "numbers compare as numbers")
check("V2", N("v0.10.0", "v0.9.0"), "0.10 is newer than 0.9")
check("V3", N("v0.3.0", "v0.3.0-beta") and not N("v0.3.0-beta", "v0.3.0") and not N("v0.3.0-beta", "v0.3.0-beta"), "a release beats its own beta")
check("V4", not N("@project-version@", "v0.3.0") and not N("v0.3.0", "@project-version@") and not N("v0.3.0", nil), "a development copy is never newer or older")

Presence:RecordVersion("Player-1-BBBB", "v0.4.0")
check("V5", Presence.newest == nil and updateNotices == 0, "the same version says nothing")
Presence:RecordVersion("Player-1-EEEE", "v0.5.0")
Presence:RecordVersion("Player-1-FFFF", "v0.6.0")
check("V6", Presence.newest == "v0.6.0", "the newest version is kept")
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

-- About: setup and reset ---------------------------------------------------------------------------
local setupButton, resetButton
for frame, tip in pairs(tooltips) do
	if tip[2] == "TIP_SETUP_AGAIN" then setupButton = frame end
	if tip[2] == "TIP_RESET" then resetButton = frame end
end
setupButton.scripts.OnClick()
resetButton.scripts.OnClick()
check("A10", PLC.welcomeOpened and PLC.resetAsked, "About can run the setup again, and reset, which asks first")
check("L12", available >= 24 + 6 * 20 + 46 + 172 + 28, "the About page with its two new buttons still fits")

-- Changelog -----------------------------------------------------------------------------------------
local changelogTexts = {}
for _, t in ipairs(texts) do changelogTexts[tostring(t.text)] = t end
local before = changelogTexts["1.1.0"]
check("C1", before == nil, "the changelog isn't built until its page is shown")
local changelogPage
for _, f in ipairs(frames) do
	if rawget(f, "child") then changelogPage = f end
end
check("C2", changelogPage ~= nil, "the changelog page scrolls")
-- Showing it builds and lays it out: headings, then paragraphs and bullets, indented by level.
changelogPage.parent.hooks.OnShow(changelogPage.parent)
local byText = {}
for _, label in ipairs(texts) do byText[tostring(label.text)] = label end
local function x(label) return label and label.points[#label.points][2] end
check("C3", byText["1.1.0"] and byText["1.0.0"] and x(byText["1.1.0"]) == 0, "each version is a heading")
check("C4", x(byText["Intro"]) == 0 and x(byText["First"]) > 0 and x(byText["Nested"]) > x(byText["First"]), "paragraphs sit at the edge, bullets indent by level")
check("C5", byText["•"] ~= nil and byText["–"] ~= nil, "with a dot, or a dash one level deeper")
local content = changelogPage.child
check("C6", content and content.height and content.height > 14 * 5, "and the page scrolls as far as the text goes")
changelogPage.parent.hooks.OnShow(changelogPage.parent)
local headings = 0
for _, label in ipairs(texts) do if label.text == "1.1.0" then headings = headings + 1 end end
check("C7", headings == 1, "showing it again lays it out again, without building it twice")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
