-- Run from the addon folder: luajit tests/trades_test.lua
--
-- The real UI/TradeFrame.lua against stubbed widgets: what's still to hand over, and who got what in
-- the last review pass, which is where awards are announced instead of a line each in raid chat.
local out = print
_G.print = function() end
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end
_G.tinsert = table.insert
_G.UISpecialFrames = {}
_G.time = function() return 1000 end
_G.GetTime = function() return 1000 end
local ME, ANA, BO, ML = "guid-me", "guid-ana", "guid-bo", "guid-ml"
_G.UnitGUID = function() return ME end
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.8, b = 1 }, ROGUE = { r = 1, g = 1, b = 0.4 } }

local function stub(extra)
	local f = extra or {}
	f.scripts, f.shown = {}, false
	return setmetatable(f, { __index = function(_, k)
		if k == "Show" then return function(s) s.shown = true end end
		if k == "Hide" then return function(s) s.shown = false end end
		if k == "IsShown" then return function(s) return s.shown end end
		if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
		if k == "SetScript" or k == "HookScript" then return function(s, n, fn) s.scripts[n] = fn end end
		if k == "SetText" then return function(s, v) s.text = v end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return stub() end end
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
_G.CreateFrame = function() return stub() end
_G.UIParent = stub()

local PLC = { UI = { Widgets = {} }, Loot = {} }
PLC.UI.Theme = { LAYOUT = { headerHeight = 32, buttonHeight = 28 } }
PLC.UI.Widgets.Primitives = setmetatable({ color = function() return 1, 1, 1 end }, { __index = function() return function() return stub() end end })
PLC.UI.Widgets.Button = setmetatable({}, { __index = function() return function() return stub() end end })
PLC.UI.Widgets.ScrollFrame = { RESERVED_WIDTH = 14 }
local shownRows
PLC.UI.Widgets.DataTable = { Create = function()
	return { SetColumns = function(t, columns) t.columns = columns end, SetRows = function(_, rows) shownRows = rows end }
end }
function PLC:ScheduleRepeatingTimer() return {} end
function PLC:CancelTimer() end
function PLC:RegisterSlashCommand() end
local owner = false
PLC.Session = { items = {}, sessionId = "S2", owner = { guid = ML, name = "Brukt-Realm" }, preview = false,
	IsOwner = function() return owner end }
local ROSTER = { [ANA] = { name = "Ana-Realm", class = "MAGE" }, [BO] = { name = "Bo-Realm", class = "ROGUE" }, [ME] = { name = "Me-Realm", class = "MAGE" } }
PLC.Roster = { Get = function(_, guid) return ROSTER[guid] end, ShortName = function(_, name) return name and name:match("^[^-]+") end }
PLC.Loot.BagTracker = { StatusText = function() return nil end }
assert(loadfile("UI/TradeFrame.lua"))("PixlLootCouncil", PLC)
local TradeFrame = PLC.UI.TradeFrame

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function upvalue(fn, wanted)
	for i = 1, 60 do
		local name, value = debug.getupvalue(fn, i)
		if not name then return nil end
		if name == wanted then return value end
	end
end
local function item(idx, winner, extra)
	local entry = { idx = idx, link = "[Item " .. idx .. "]", awarded = winner, awardReason = "award", sentIn = "S2", awardedAt = 990,
		winnerName = ROSTER[winner] and ROSTER[winner].name, winnerClass = ROSTER[winner] and ROSTER[winner].class }
	for k, v in pairs(extra or {}) do entry[k] = v end
	return entry
end
local function kinds()
	local list = {}
	for _, row in ipairs(shownRows) do list[#list + 1] = row.kind .. row.idx end
	return table.concat(list, ",")
end
local function window() return upvalue(TradeFrame.Refresh, "frame") end

-- A raider, after an Award All -----------------------------------------------------------------------------
PLC.Session.items = {
	[1] = item(1, ANA), [2] = item(2, ME), [3] = item(3, BO, { awardReason = "disenchant" }),
	[4] = { idx = 4, link = "[Item 4]", sentIn = "S2" }, -- not awarded
	[5] = item(5, ANA, { sentIn = "S1" }), -- an earlier pass's
}
TradeFrame:Open()
check("W1", window().shown, "Loot Trades opens when an Award All arrives")
check("W2", kinds() == "collect2,result1,result3", "what's mine to collect first, then who got the rest: " .. kinds())
local columns = upvalue(TradeFrame.Refresh, "dataTable").columns
local name, r, g = columns[3].render(shownRows[2])
check("W3", name == "Ana" and r == 0.2 and g == 0.8, "each with the winner's name, in their class color")
check("W4", columns[4].render(shownRows[3]) == "SESSIONFRAME_DISENCHANTED" and columns[4].render(shownRows[2]) == "SESSIONFRAME_AWARDED",
	"and whether it was awarded, disenchanted or banked")
local trade = stub({ tradeButton = stub(), disenchantButton = stub() })
columns[5].update(trade, shownRows[2])
check("W5", not trade.tradeButton.shown, "with nothing to click on someone else's item")
columns[5].update(trade, shownRows[1])
check("W6", trade.tradeButton.shown, "and Trade on my own")

-- When it shows -------------------------------------------------------------------------------------------
window().scripts.OnHide(window()); window():Hide()
PLC.Session.items[2].traded = true -- collected
TradeFrame:Refresh()
check("S1", not window().shown and kinds() == "result1,result2,result3", "results alone don't bring it up by themselves: not at every login")
TradeFrame:Open()
check("S2", window().shown, "/plc trades and the next Award All do")
window():Hide()
PLC.Session.items[6] = item(6, ME)
TradeFrame:Refresh()
check("S3", window().shown and shownRows[1].kind == "collect", "something new to collect brings it up again")
PLC.Session.sessionId = "S3" -- the next pass starts
TradeFrame:Refresh()
check("S4", kinds() == "collect6", "the next pass clears the old results, not what's still to collect")

-- The master looter ----------------------------------------------------------------------------------------
owner = true
PLC.Session.sessionId = "S2"
PLC.Session.items = { [1] = item(1, ANA), [2] = item(2, BO, { traded = true }), [3] = item(3, ME, { awardReason = "bank", traded = true }) }
TradeFrame:Open()
check("M1", kinds() == "handout1,result2,result3", "what's still to hand out first; handed over, it stays as a result: " .. kinds())
check("M2", columns[4].render(shownRows[3]) == "SESSIONFRAME_BANKED", "banked items say so")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
