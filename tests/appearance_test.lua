-- Run from the addon folder: luajit tests/appearance_test.lua
--
-- The real UI/Theme.lua, UI/Widgets/Primitives.lua, UI/Widgets/PopupMenu.lua and LibSharedMedia
-- against a stubbed game. Colors are measured: every theme has to stay readable, and a theme's
-- accent has to stay apart from the colors that mean something.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.bit = require("bit")
_G.GetLocale = function() return "enUS" end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.C_UIFileAsset = { IsKnownFile = function() return true end }
_G.geterrorhandler = function() return function(message) error(message) end end
_G.securecallfunction = function(fn, ...) return fn(...) end

local noop = function() end
local frameMethods = {
	SetFont = function(f, path, size)
		if f.refuses and f.refuses[path] then return false end
		f.fontPath, f.fontSize = path, size
		return true
	end,
	SetScript = function(f, name, fn) f.scripts[name] = fn end,
	SetPoint = noop,
	SetText = function(f, text) f.text = text end,
	GetText = function(f) return f.text end,
	SetTextColor = function(f, r, g, b) f.textColor = { r, g, b } end,
	SetColorTexture = function(f, r, g, b) f.fillColor = { r, g, b } end,
	SetVertexColor = function(f, r, g, b) f.vertexColor = { r, g, b } end,
	SetShown = function(f, shown) f.shown = shown and true or false end,
	Show = function(f) f.shown = true end,
	Hide = function(f) f.shown = false end,
	GetWidth = function() return 200 end,
	GetFrameLevel = function() return 1 end,
}
local fontObjects = {}
local function frame(props)
	local f = props or {}
	f.scripts = {}
	return setmetatable(f, { __index = function(_, k)
		if frameMethods[k] then return frameMethods[k] end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return frame() end end
		if type(k) == "string" and k:match("^%u") then return noop end
	end })
end
_G.CreateFrame = function() return frame() end
_G.CreateFont = function(name) local f = frame({ name = name }); fontObjects[#fontObjects + 1] = f; return f end
_G.UIParent = frame()

local function loadLua(path, ...) return assert(loadfile(path))(...) end
loadLua("Libs/LibStub/LibStub.lua")
loadLua("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
loadLua("Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua")
LibStub:NewLibrary("AceLocale-3.0", 1).GetLocale = function()
	return setmetatable({}, { __index = function(_, k) return k end })
end
local LSM = LibStub("LibSharedMedia-3.0")

local onEnable = {}
local PLC = { UI = { Widgets = {} } }
function PLC:RegisterOnEnable(fn) onEnable[#onEnable + 1] = fn end
function PLC:ScheduleTimer() end
PLC.Events = { RegisterHandler = noop }
loadLua("Core/Defaults.lua", "PixlLootCouncil", PLC)
loadLua("UI/Theme.lua", "PixlLootCouncil", PLC)
loadLua("UI/Widgets/Primitives.lua", "PixlLootCouncil", PLC)
loadLua("UI/Widgets/PopupMenu.lua", "PixlLootCouncil", PLC)
local Theme, Primitives, PopupMenu = PLC.UI.Theme, PLC.UI.Widgets.Primitives, PLC.UI.Widgets.PopupMenu

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function same(a, b)
	for i = 1, 3 do if math.abs(a[i] - b[i]) > 0.00001 then return false end end
	return true
end

-- The default is exactly the look from before there were themes -------------------------------------
local BEFORE = {
	frame = { { 0.018, 0.020, 0.026 }, 0.012 }, header = { { 0.024, 0.027, 0.034 }, 0.070 },
	sidebar = { { 0.026, 0.030, 0.037 }, 0.022 }, content = { { 0.050, 0.056, 0.068 }, 0.020 },
	button = { { 0.040, 0.045, 0.055 }, 0.065 }, buttonHover = { { 0.055, 0.062, 0.075 }, 0.150 },
	border = { { 0.110, 0.120, 0.140 }, 0.220 }, borderDim = { { 0.080, 0.090, 0.110 }, 0.110 },
}
local ACCENT = { 0.91, 0.64, 0.24 }
local gold = Theme:Palette("gold")
local unchanged = same(gold.accent, ACCENT)
for name, spec in pairs(BEFORE) do
	local base, t = spec[1], spec[2]
	local expected = { base[1] + (ACCENT[1] - base[1]) * t, base[2] + (ACCENT[2] - base[2]) * t, base[3] + (ACCENT[3] - base[3]) * t }
	unchanged = unchanged and same(gold[name], expected)
end
unchanged = unchanged and same(gold.field, { 0.022, 0.026, 0.032 }) and same(gold.scroll, { 0.075, 0.085, 0.100 })
	and same(gold.text, { 0.87, 0.88, 0.90 }) and same(gold.success, { 0.27, 0.84, 0.38 }) and same(gold.warning, { 1.00, 0.27, 0.27 })
check("T1", unchanged, "Pixl Gold is exactly the old default look")
check("T2", Theme.THEMES[1].key == "gold" and Theme.DEFAULT == "gold" and PLC.Defaults.profile.theme == "gold", "and it's first, and the default")
check("T3", PLC.Defaults.profile.accent == nil and PLC.Defaults.profile.font == "Inter", "the accent setting is gone, and Inter is the default font")

-- Every theme, measured ------------------------------------------------------------------------------
local function luminance(c)
	local function channel(v)
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end
local function hue(c)
	local maxv, minv = math.max(c[1], c[2], c[3]), math.min(c[1], c[2], c[3])
	local d = maxv - minv
	if d == 0 then return 0 end
	local h
	if maxv == c[1] then h = ((c[2] - c[3]) / d) % 6
	elseif maxv == c[2] then h = (c[3] - c[1]) / d + 2
	else h = (c[1] - c[2]) / d + 4 end
	return h * 60
end
local function hueGap(a, b)
	local gap = math.abs(hue(a) - hue(b)) % 360
	return math.min(gap, 360 - gap)
end
local function distance(a, b)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

local keys, problems = {}, {}
local function problem(theme, text) problems[#problems + 1] = theme.key .. ": " .. text end
for _, theme in ipairs(Theme.THEMES) do
	if keys[theme.key] then problem(theme, "same key twice") end
	keys[theme.key] = true
	local p = Theme:Palette(theme.key)
	for _, surface in ipairs({ "frame", "header", "sidebar", "content", "button", "field" }) do
		if contrast(p.text, p[surface]) < 7 then problem(theme, "text on " .. surface) end
		if contrast(p.accent, p[surface]) < 4.5 then problem(theme, "accent on " .. surface) end
		if contrast(p.success, p[surface]) < 4.5 then problem(theme, "success on " .. surface) end
		if contrast(p.warning, p[surface]) < 4.5 then problem(theme, "warning on " .. surface) end
		if contrast(p.dim, p[surface]) < 3 then problem(theme, "dim on " .. surface) end
	end
	if contrast(p.text, p.buttonHover) < 7 then problem(theme, "text on a hovered button") end
	if contrast(p.border, p.frame) < 1.3 then problem(theme, "border against the frame") end
	if luminance(p.frame) > 0.02 then problem(theme, "frame isn't dark") end
end
check("T4", #problems == 0, "every theme is readable and stays dark " .. table.concat(problems, "; "))

problems = {}
for _, theme in ipairs(Theme.THEMES) do
	local p = Theme:Palette(theme.key)
	if hueGap(p.accent, p.success) < 40 then problem(theme, "accent looks like success") end
	if hueGap(p.accent, p.warning) < 30 then problem(theme, "accent looks like warning") end
	if hueGap(p.success, p.warning) < 60 then problem(theme, "success looks like warning") end
	if distance(p.accent, p.text) < 0.25 then problem(theme, "accent looks like plain text") end
end
check("T5", #problems == 0, "timers and Staged/Awarded still read: accent stays apart from green, red and text " .. table.concat(problems, "; "))

problems = {}
for i, a in ipairs(Theme.THEMES) do
	for j = i + 1, #Theme.THEMES do
		local b = Theme.THEMES[j]
		if distance(a.accent, b.accent) < 0.2 then problem(a, "too close to " .. b.key) end
	end
end
check("T6", #problems == 0, "and no two themes look alike " .. table.concat(problems, "; "))

local shades = 0
for _, theme in ipairs(Theme.THEMES) do
	if theme.shade then shades = shades + 1 end
	if not theme.name or theme.name == "" then shades = -100 end
end
check("T7", shades == #Theme.THEMES - 1, "every other theme has backgrounds of its own, not just a different highlight")

-- Applying -----------------------------------------------------------------------------------------
local fill, label, kept = Theme:Track(frame(), "fill", "header"), Theme:Track(frame(), "text", "accent"), Theme:Track(frame(), "text", "text")
Theme:KeepColor(kept, { 0.1, 0.2, 0.3 })
local refreshed = 0
Theme:OnRefresh(function() refreshed = refreshed + 1 end)
Theme:Apply("arcane")
local arcane = Theme:Palette("arcane")
check("T8", same(fill.fillColor, arcane.header) and same(label.textColor, arcane.accent), "applying repaints everything tracked")
check("T9", same(kept.textColor, { 0.1, 0.2, 0.3 }), "except what shows a color of its own")
check("T10", refreshed == 1, "and tells whatever depends on colors")
Theme:Apply("fel")
check("T11", same(Theme.COLORS.success, Theme:Palette("fel").success) and not same(Theme.COLORS.success, gold.success), "a theme can move the fixed colors")
Theme:Apply("gold")
check("T12", same(Theme.COLORS.success, gold.success) and same(Theme.COLORS.field, gold.field), "and they come back with the next one")
check("T16", not same(Theme:Palette("frost").field, gold.field) and not same(Theme:Palette("frost").scroll, gold.scroll), "input fields and scrollbars take a theme's backgrounds too")
Theme:Apply("gone")
check("T13", same(Theme.COLORS.accent, gold.accent), "a theme that doesn't exist is the default")

-- Fonts --------------------------------------------------------------------------------------------
local INTER = "Interface\\AddOns\\PixlLootCouncil\\font\\Inter-Medium.ttf"
local names = Primitives.fontNames()
check("F1", names[1] == "Inter" and LSM:Fetch("font", "Inter") == INTER, "Inter is registered, so other addons can use it too, and comes first")
LSM:Register("font", "Zeta Sans", "Interface\\AddOns\\Other\\zeta.ttf")
LSM:Register("font", "Alpha Serif", "Interface\\AddOns\\Other\\alpha.ttf")
names = Primitives.fontNames()
local seenZeta, inter = false, 0
for _, name in ipairs(names) do
	seenZeta = seenZeta or name == "Zeta Sans"
	if name == "Inter" then inter = inter + 1 end
end
check("F2", seenZeta and inter == 1 and names[2] < names[3], "other addons' fonts are listed, in order, with Inter once")
local realList = LSM.List
LSM.List = function() return { "Alpha Serif" } end
names = Primitives.fontNames()
check("F3", names[1] == "Inter" and names[2] == "Alpha Serif", "Inter stays listed even if registering it was refused")
LSM.List = function() return nil end
check("F4", #Primitives.fontNames() == 1, "and a missing list doesn't break it")
LSM.List = realList
check("F5", Primitives.fontPath("Zeta Sans") == "Interface\\AddOns\\Other\\zeta.ttf" and Primitives.fontPath("Removed") == INTER and Primitives.fontPath("Inter") == INTER, "a font that's gone falls back to Inter")

local label12 = Primitives.createText(frame(), "x", 12)
local label16 = Primitives.createText(frame(), "x", 16)
Primitives.setFont("Zeta Sans")
local all = #fontObjects >= 2
for _, font in ipairs(fontObjects) do all = all and font.fontPath == "Interface\\AddOns\\Other\\zeta.ttf" end
check("F6", all, "setting a font changes every size at once")
local sizes = {}
for _, font in ipairs(fontObjects) do sizes[font.name] = font.fontSize end
check("F7", sizes.PixlLootCouncilFont10 == 10, "without losing a size to the redraw nudge")
Primitives.createText(frame(), "x", 30)
check("F8", fontObjects[#fontObjects].fontPath == "Interface\\AddOns\\Other\\zeta.ttf", "and labels made later use it too")
fontObjects[1].refuses = { ["Interface\\AddOns\\Other\\bad.ttf"] = true }
LSM:Register("font", "Bad", "Interface\\AddOns\\Other\\bad.ttf")
Primitives.setFont("Bad")
check("F9", fontObjects[1].fontPath == STANDARD_TEXT_FONT, "a font the game can't load falls back to the game's own")
fontObjects[1].refuses = nil
Primitives.setFont("Inter")

PLC.db = { profile = { theme = "nether", font = "Later Font", accent = { r = 1, g = 0, b = 0 } } }
for _, fn in ipairs(onEnable) do fn() end
check("T14", same(Theme.COLORS.accent, Theme:Palette("nether").accent), "login applies the saved theme")
check("T15", PLC.db.profile.accent == nil, "and clears the old accent setting from the saved data")
check("F10", fontObjects[1].fontPath == INTER, "a saved font that isn't registered yet waits, on Inter")
LSM:Register("font", "Unrelated", "Interface\\AddOns\\Other\\un.ttf")
check("F11", fontObjects[1].fontPath == INTER, "another addon's font doesn't change that")
LSM:Register("font", "Later Font", "Interface\\AddOns\\Other\\later.ttf")
check("F12", fontObjects[1].fontPath == "Interface\\AddOns\\Other\\later.ttf", "the saved font takes over once its addon registers it")

PLC.db.profile.font = "Zeta Sans"
for _, fn in ipairs(onEnable) do fn() end
check("F13", fontObjects[1].fontPath == "Interface\\AddOns\\Other\\zeta.ttf", "a saved font that's already registered applies at login")

-- The font menu -------------------------------------------------------------------------------------
local created = {}
do
	local realCreateText = Primitives.createText
	Primitives.createText = function(...)
		local t = realCreateText(...)
		created[#created + 1] = t
		return t
	end
end
local owner = frame({ width = 200 })
PopupMenu.Open(owner, { { text = "Alpha", font = "alpha.ttf" }, { text = "Plain" } }, {})
local label1, sample1, label2, sample2 = created[1], created[2], created[3], created[4]
check("M1", sample1.shown and sample1.text == "Alpha" and sample1.fontPath == "alpha.ttf" and not label1.shown, "a font's menu row is written in that font")
check("M2", label2.shown and label2.text == "Plain" and not sample2.shown, "a row without one uses the normal label")
PopupMenu.Close()
PopupMenu.Open(owner, { { text = "Rare" }, { text = "Epic" } }, {})
check("M3", label1.shown and label1.text == "Rare" and not sample1.shown and label1.fontPath == nil, "the next menu reuses the row with no sample font left on it")
PopupMenu.Close()

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
