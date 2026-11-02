-- Run from the addon folder: luajit tests/locale_test.lua
--
-- What has to work on every client language, with each language's real strings
-- (tests/locale_data.lua, from the game's own data), and the translations themselves.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.time = function() return 1000 end
_G.UIParent = {}
_G.ITEM_SOULBOUND, _G.ITEM_ACCOUNTBOUND, _G.ITEM_BIND_QUEST = "Soulbound", "Account", "Quest"

local DATA = dofile("tests/locale_data.lua")
local LANGUAGES = { "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-5s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

local function stubLocale()
	_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end
end
stubLocale()

-- Writes a count the way the game does: "|4hour:hrs;" is singular:plural.
local function spell(format, count)
	local text = format:gsub("%%d", tostring(count))
	return (text:gsub("|4([^:;]*):([^;]*);", function(one, many) return count == 1 and one or many end))
end

-- A tooltip line saying this much time is left, in this language.
local function tooltipLine(strings, hours, minutes, seconds)
	local parts = {}
	if hours > 0 then parts[#parts + 1] = spell(strings.INT_SPELL_DURATION_HOURS, hours) end
	if minutes > 0 then parts[#parts + 1] = spell(strings.INT_SPELL_DURATION_MIN, minutes) end
	if seconds > 0 then parts[#parts + 1] = spell(strings.INT_SPELL_DURATION_SEC, seconds) end
	local timeText = table.concat(parts, strings.TIME_UNIT_DELIMITER)
	return (strings.BIND_TRADE_TIME_REMAINING:gsub("%%1%$s", "%%s"):gsub("%%s", function() return timeText end))
end

local function loadBagTracker(strings)
	_G.BIND_TRADE_TIME_REMAINING = strings.BIND_TRADE_TIME_REMAINING
	_G.INT_SPELL_DURATION_HOURS = strings.INT_SPELL_DURATION_HOURS
	_G.INT_SPELL_DURATION_MIN = strings.INT_SPELL_DURATION_MIN
	_G.INT_SPELL_DURATION_SEC = strings.INT_SPELL_DURATION_SEC
	local tooltip = {}
	_G.CreateFrame = function() return setmetatable({ NumLines = function() return #tooltip end }, { __index = function() return function() end end }) end
	local PLC = { Loot = {}, Events = { RegisterHandler = function() end } }
	function PLC:RegisterOnEnable() end
	function PLC:ScheduleTimer() end
	function PLC:ScheduleRepeatingTimer() end
	assert(loadfile("Loot/BagTracker.lua"))("PixlLootCouncil", PLC)
	return PLC.Loot.BagTracker, tooltip
end

local function read(tracker, tooltip, text)
	tooltip[1] = text
	_G.PixlLootCouncilScanTooltipTextLeft1 = { GetText = function() return text end }
	return tracker:GetTradeStatus(0, 1)
end

-- Trade time, on every client ------------------------------------------------------------------------
local CASES = {
	{ 1, 52, 0, 6720 }, { 2, 0, 0, 7200 }, { 1, 0, 0, 3600 }, { 1, 1, 0, 3660 },
	{ 0, 59, 0, 3540 }, { 0, 1, 0, 60 }, { 0, 2, 0, 120 }, { 0, 0, 45, 45 }, { 0, 0, 1, 1 },
}
local wrong = {}
for _, language in ipairs(LANGUAGES) do
	local strings = DATA[language]
	local tracker, tooltip = loadBagTracker(strings)
	for _, case in ipairs(CASES) do
		local text = tooltipLine(strings, case[1], case[2], case[3])
		local status, seconds = read(tracker, tooltip, text)
		if status ~= "timer" or seconds ~= case[4] then
			wrong[#wrong + 1] = string.format("%s %q gave %s %s", language, text, tostring(status), tostring(seconds))
		end
	end
end
check("T1", #wrong == 0, "trade time reads right on all 11 clients " .. table.concat(wrong, "; "):sub(1, 300))

local tracker, tooltip = loadBagTracker(DATA.deDE)
check("T2", read(tracker, tooltip, "Seelengebunden Beispiel") == "free", "an unrelated line isn't a timer")
check("T3", read(tracker, tooltip, "Soulbound") == "bound", "a bound item past its window still reads as bound")
local numbered = {}
for k, v in pairs(DATA.ruRU) do numbered[k] = v end
numbered.BIND_TRADE_TIME_REMAINING = DATA.ruRU.BIND_TRADE_TIME_REMAINING:gsub("%%s", "%%1$s")
tracker, tooltip = loadBagTracker(numbered)
local status, seconds = read(tracker, tooltip, tooltipLine(numbered, 1, 52, 0))
check("T4", status == "timer" and seconds == 6720, "a numbered %1$s placeholder works too, as Russian has used")
tracker, tooltip = loadBagTracker(DATA.deDE)
status, seconds = read(tracker, tooltip, tooltipLine(DATA.deDE, 1, 0, 0):gsub("1 Stunde", "1 Fortnight"))
check("T5", status == "timer" and seconds == nil, "a unit it can't read leaves the time unknown instead of guessing")

-- The default font ------------------------------------------------------------------------------------
_G.bit = require("bit")
_G.STANDARD_TEXT_FONT = "Fonts\\GAME.TTF"
_G.C_UIFileAsset = { IsKnownFile = function() return true end }
_G.geterrorhandler = function() return function(message) error(message) end end
_G.securecallfunction = function(fn, ...) return fn(...) end
local function fakeObject()
	return setmetatable({}, { __index = function(t, k)
		if k == "SetFont" then return function(self, path, size) self.path, self.size = path, size end end
		if k == "CreateFontString" then return function() return fakeObject() end end
		return function() end
	end })
end
_G.CreateFont = function() return fakeObject() end
_G.UIParent = fakeObject()
_G.CreateFrame = function() return fakeObject() end
local realLibStub = LibStub
local function loadPrimitives(language)
	_G.GetLocale = function() return language end
	_G.LibStub = nil
	_G.LibStub = nil
	assert(loadfile("Libs/LibStub/LibStub.lua"))()
	assert(loadfile("Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"))()
	assert(loadfile("Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua"))()
	local PLC = { UI = { Widgets = {} }, Events = { RegisterHandler = function() end } }
	function PLC:RegisterOnEnable() end
	function PLC:ScheduleTimer() end
	PLC.UI.Theme = { Track = function(_, region) return region end, ForEachText = function() end }
	assert(loadfile("UI/Widgets/Primitives.lua"))("PixlLootCouncil", PLC)
	return PLC.UI.Widgets.Primitives
end
local INTER = "Interface\\AddOns\\PixlLootCouncil\\font\\Inter-Medium.ttf"
local bad = {}
for _, language in ipairs(LANGUAGES) do
	local Primitives = loadPrimitives(language)
	local cjk = language == "koKR" or language == "zhCN" or language == "zhTW"
	if Primitives.hasInter == cjk or Primitives.fontPath("Inter") ~= (cjk and STANDARD_TEXT_FONT or INTER) then
		bad[#bad + 1] = language
	end
	if Primitives.fontNames()[1] ~= "Inter" then bad[#bad + 1] = language .. " list" end
end
check("F1", #bad == 0, "Korean and Chinese default to the game's font, everyone else to Inter " .. table.concat(bad, ","))
local label = fakeObject()
local Primitives = loadPrimitives("zhCN")
_G.LibStub = realLibStub

-- The translations -------------------------------------------------------------------------------------
local function strings(language)
	local L = {}
	_G.GetLocale = function() return language end
	_G.LibStub = function()
		return { NewLocale = function() return L end }
	end
	assert(loadfile("Locale/" .. language .. ".lua"))()
	_G.LibStub = realLibStub
	return L
end
local english = strings("enUS")
local function placeholders(text)
	local found = {}
	for spec in tostring(text):gmatch("%%[%d%$]*[sd]") do found[#found + 1] = spec end
	table.sort(found)
	return table.concat(found, " ")
end
local function escapes(text)
	local found = {}
	for code in tostring(text):gmatch("|[cr][%x]*") do found[#found + 1] = code end
	return table.concat(found, " ")
end
-- Fine in English everywhere: the chat prefix, names, and what's a term in every language.
local UNIVERSAL = {
	CHAT_PREFIX = true, ERROR_LOG_ENTRY = true, ABOUT_LIBRARIES_LIST = true, OPTIONS_GROUP_RC = true,
	RESPONSE_BIS = true, RESPONSE_PVP = true,
}
local unknown, broken, missing, enchanting = {}, {}, {}, {}
for _, language in ipairs(LANGUAGES) do
	if language ~= "enUS" then
		local L = strings(language)
		for key, text in pairs(L) do
			if english[key] == nil then unknown[#unknown + 1] = language .. ":" .. key
			elseif placeholders(text) ~= placeholders(english[key]) then broken[#broken + 1] = language .. ":" .. key
			elseif escapes(text) ~= escapes(english[key]) then broken[#broken + 1] = language .. ":" .. key .. " (color)"
			end
		end
		for key in pairs(english) do
			if L[key] == nil and not UNIVERSAL[key] then missing[#missing + 1] = language .. ":" .. key end
		end
		if L.PROFESSION_ENCHANTING ~= DATA[language].enchanting then
			enchanting[#enchanting + 1] = language .. " " .. tostring(L.PROFESSION_ENCHANTING)
		end
	end
end
check("L1", #unknown == 0, "no translation of something that doesn't exist " .. table.concat(unknown, ", "):sub(1, 200))
check("L2", #broken == 0, "every %s, %d and color code survives translation " .. table.concat(broken, ", "):sub(1, 200))
check("L3", #missing == 0, "every string is translated in every language (" .. #missing .. " left) " .. table.concat(missing, ", "):sub(1, 160))
check("L4", #enchanting == 0, "Enchanting is the game's own skill name in every language, or Enchanters aren't found " .. table.concat(enchanting, ", "))
check("L5", english.PROFESSION_ENCHANTING == DATA.enUS.enchanting, "English included")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
