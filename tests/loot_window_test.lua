-- Run from the addon folder: luajit tests/loot_window_test.lua
--
-- The real UI/LootFrame.lua, UI/Widgets/DataTable.lua and UI/Widgets/ScrollFrame.lua against stub
-- frames that remember their sizes: the Loot Response window's rows, and how the name and the note
-- share the room as the window is resized.
local out = print
_G.print = function() end
local now = 1000
_G.time = function() return now end
_G.UnitGUID = function() return "Player-1-AAAA" end
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end

local function stub(extra)
	local f = extra or {}
	f.points, f.scripts, f.shown = {}, {}, true
	return setmetatable(f, { __index = function(_, k)
		if k == "SetPoint" then return function(s, ...) s.points[#s.points + 1] = { ... } end end
		if k == "ClearAllPoints" then return function(s) s.points = {} end end
		if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
		if k == "SetWidth" then return function(s, w) s.width = w end end
		if k == "SetHeight" then return function(s, h) s.height = h end end
		if k == "GetWidth" then return function(s) return s.width or 0 end end
		if k == "GetHeight" then return function(s) return s.height or 0 end end
		if k == "Show" then return function(s) s.shown = true end end
		if k == "Hide" then return function(s) s.shown = false end end
		if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
		if k == "IsShown" then return function(s) return s.shown end end
		if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
		if k == "HookScript" then return function(s, n, fn) s.scripts[n] = fn end end
		if k == "SetValue" then return function(s, v) s.value = v end end
		if k == "GetValue" then return function(s) return s.value or 0 end end
		if k == "GetFrameLevel" then return function(s) return s.level or 1 end end
		if k == "SetFrameLevel" then return function(s, v) s.level = v end end
		if k == "SetDrawLayer" then return function(s, layer, sub) s.layer, s.sublevel = layer, sub end end
		if k == "SetWordWrap" then return function(s, v) s.wraps = v end end
		if k == "SetText" then return function(s, v) s.text = v end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return stub() end end
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
_G.CreateFrame = function() return stub() end
_G.UIParent = stub()

local bounds, grip, closeButtons
local PLC = { UI = { Widgets = {} }, db = { profile = { lootResponseRows = 8 } } }
PLC.UI.Theme = { LAYOUT = { headerHeight = 32, buttonHeight = 28 } }
PLC.UI.Widgets.Primitives = setmetatable({
	color = function() return 1, 1, 1 end,
	createText = function() return stub() end,
	createTexture = function(_, layer, colorName) return stub({ layer = layer, colorName = colorName }) end,
	createEditBox = function(_, width, height, placeholder, multiline, maxLetters)
		return stub({ width = width, height = height, placeholder = placeholder, multiline = multiline,
			maxLetters = maxLetters, GetValue = function() return "" end,
			SetFocus = function(box) box.focused = true end, ClearFocus = function(box) box.focused = false end })
	end,
	setResizeBounds = function(_, minW, minH, maxW, maxH) bounds = { minW, minH, maxW, maxH } end,
	makeResizable = function() grip = stub(); return grip end,
	createCloseButton = function() closeButtons = (closeButtons or 0) + 1; return stub() end,
}, { __index = function() return function() return stub() end end })
PLC.UI.Widgets.Button = { createButton = function(_, text)
	return stub({ width = #text * 6 + 20, height = 28 })
end }
local soon = {}
function PLC:ScheduleTimer(fn) soon[#soon + 1] = fn end
function PLC:ScheduleRepeatingTimer() return {} end
function PLC:CancelTimer() end
function PLC:RegisterSlashCommand() end

local SET = { { key = "BIS", text = "BIS" }, { key = "UP", text = "Upgrade" }, { key = "PASS", text = "Pass" } }
local function signature(set)
	local keys = {}
	for i, r in ipairs(set) do keys[i] = r.key .. "=" .. r.text end
	return table.concat(keys, ",")
end
PLC.Responses = { GetActive = function() return SET end, Signature = signature,
	Find = function(_, key) for _, r in ipairs(SET) do if r.key == key then return r end end end }
PLC.RCBridge = { GetRows = function() return {} end, GetResponseSets = function() return {} end }
PLC.Roster = { ShortName = function(_, name) return name end }
PLC.Session = { state = "active", items = {}, responses = {}, responseTimeoutSeconds = 60, owner = { name = "Pixl" } }
local function items(count)
	PLC.Session.items = {}
	for i = 1, count do
		PLC.Session.items[i] = { link = "[Item " .. i .. "]", deadlineAt = now + 60 }
	end
end

local function loadLua(path) return assert(loadfile(path))("PixlLootCouncil", PLC) end
loadLua("UI/Widgets/ScrollFrame.lua")
loadLua("UI/Widgets/DataTable.lua")
loadLua("UI/LootFrame.lua")
local LootFrame = PLC.UI.LootFrame

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function upvalue(fn, name)
	for i = 1, 60 do
		local n, v = debug.getupvalue(fn, i)
		if n == name then return v end
		if not n then return nil end
	end
end

-- The game sizes the table from the window; here the test does: the 1px border each side, and the
-- header with its separator and one row gap above the rows, and the border and one row gap below.
local frame, dataTable
local function resize(width, height)
	frame.width, frame.height = width or frame.width, height or frame.height
	dataTable.scroll.width = frame.width - 2
	dataTable.scroll.height = frame.height - 32 - 2 - 2
	dataTable:Layout()
end
local function refresh()
	LootFrame:Refresh()
	resize() -- the game relays the window's new size to the table
end
items(3)
LootFrame:Refresh()
frame, dataTable = upvalue(LootFrame.Refresh, "frame"), upvalue(LootFrame.Refresh, "dataTable")
resize()

local function shownRows()
	local list = {}
	for _, row in ipairs(dataTable.rows) do
		if row.shown and row.dataIndex then list[#list + 1] = row end
	end
	return list
end
local function cells(row) return row.cells[1], row.cells[2], row.cells[4] end
local function note(row) return select(3, cells(row)).noteBox end
local function nameWidth(row) local _, name = cells(row); return name.shown and name.width or 0 end

-- Rows -----------------------------------------------------------------------------------------------
local rows = shownRows()
local icon, _, responses = cells(rows[1])
check("R1", #rows == 3 and rows[1].height == 32 and rows[2].points[1][5] == -33, "rows are the icon plus 3px above and below, 1px apart")
check("R2", rows[1].bg and rows[1].bg.colorName == "content" and rows[1].bg.sublevel == -1, "each row has its own background, under the countdown fill")
check("R3", rows[1].width == dataTable.scroll.width, "and runs the full width of the window")
check("R4", icon.width == 26 and icon.height == 26 and icon.points[1][4] == 3, "the icon is 26px, 3px in from the edge")
local sameHeight = true
for _, group in pairs(responses.groups) do
	for _, button in pairs(group) do sameHeight = sameHeight and button.height == 26 end
end
check("R5", sameHeight and note(rows[1]).height == 26 and responses.height == 26, "buttons and the note are as tall as the icon")
check("R6", note(rows[1]).multiline == false and note(rows[1]).maxLetters == 50, "the note is one line, with a letter cap")

-- Width ----------------------------------------------------------------------------------------------
local opening = frame.width
check("W1", note(rows[1]).width == 300 and nameWidth(rows[1]) == 170, "it opens with the note at 300px and the full name")
check("W2", bounds[1] < opening and bounds[3] > opening, "and the window can be resized both ways")
resize(opening + 100)
check("W3", note(rows[1]).width == 400 and nameWidth(rows[1]) == 170, "wider: the note gets the room")
resize(opening - 50)
check("W4", note(rows[1]).width == 300 and nameWidth(rows[1]) == 120, "narrower: the name gives way first")
resize(opening - 80 - 100)
check("W5", note(rows[1]).width == 200 and nameWidth(rows[1]) == 90, "then the note")
resize(opening - 80 - 181)
local _, name = cells(rows[1])
check("W6", not name.shown and note(rows[1]).width == 119 + 96, "then the name goes, and the note takes its place")
resize(bounds[1])
check("W7", not name.shown and note(rows[1]).width == 120, "the narrowest window still fits the note at 120px")
check("W8", name.text.wraps == false, "a long name is cut short on one line")

-- The scrollbar --------------------------------------------------------------------------------------
resize(opening)
items(9)
refresh()
rows = shownRows()
check("S1", rows[1].width == dataTable.scroll.width - 13 and note(rows[1]).width == 300 and nameWidth(rows[1]) == 157,
	"rows make room for the scrollbar while it shows, the name giving way")
items(2)
refresh()
rows = shownRows()
check("S2", rows[1].width == dataTable.scroll.width and note(rows[1]).width == 300, "and take it back when it goes")

-- A new set of buttons -------------------------------------------------------------------------------
resize(opening)
SET = { { key = "BIS", text = "BIS" }, { key = "PASS", text = "Pass" } }
LootFrame:Refresh()
local upgrade = #"Upgrade" * 6 + 20 + 6
resize(frame.width) -- the game relays the new width to the table
check("N1", frame.width == opening - upgrade and note(shownRows()[1]).width == 300, "an untouched window follows the buttons")
resize(frame.width + 60)
SET = { { key = "BIS", text = "BIS" }, { key = "UP", text = "Upgrade" }, { key = "PASS", text = "Pass" } }
LootFrame:Refresh()
check("N2", frame.width == opening - upgrade + 60, "a width the player chose is kept")
resize(bounds[3])
SET = { { key = "BIS", text = "BIS" } }
LootFrame:Refresh()
check("N3", frame.width == bounds[3] and bounds[3] < opening + 400, "within the new bounds")

-- Height ---------------------------------------------------------------------------------------------
local function tall(count) return 35 + 33 * count end
local function drag(height)
	grip.scripts.OnMouseDown(grip)
	frame.height = height
	grip.scripts.OnMouseUp(grip)
	resize()
end
items(3)
refresh()
check("H1", frame.height == tall(3) and bounds[2] == tall(1) and bounds[4] == tall(3), "three items: exactly three rows tall, and it can't be dragged taller")
check("H2", #shownRows() == 3 and not dataTable:needsBarRoom(), "with all of them in full, and no scrollbar")
items(12)
refresh()
check("H3", frame.height == tall(8) and bounds[4] == tall(12) and dataTable:needsBarRoom(), "twelve: the usual eight rows, scrolling, and room to show all twelve")
drag(tall(12))
check("H4", PLC.db.profile.lootResponseRows == 12 and frame.height == tall(12) and not dataTable:needsBarRoom(), "dragged to show all twelve, that's remembered")
items(4)
refresh()
check("H5", frame.height == tall(4) and PLC.db.profile.lootResponseRows == 12, "four items shrink it, without forgetting")
drag(tall(4))
check("H6", PLC.db.profile.lootResponseRows == 12, "a click on the grip changes nothing")
items(12)
refresh()
check("H7", frame.height == tall(12), "and twelve grow it back")
drag(tall(10) + 20)
check("H8", PLC.db.profile.lootResponseRows == 11 and frame.height == tall(11), "a height between rows snaps to whole rows")
UIParent.height = 500
items(20)
refresh()
check("H9", bounds[4] == tall(math.floor((500 - 80 - 35) / 33)) and frame.height <= 500 - 80, "never taller than the screen has room for")
UIParent.height = nil

-- Typing in a note -----------------------------------------------------------------------------------
PLC.Session.items = { [1] = { link = "[A]", deadlineAt = now + 5 }, [2] = { link = "[B]", deadlineAt = now + 60 } }
refresh()
local box = note(shownRows()[1])
box:SetFocus()
now = now + 6
refresh()
rows = shownRows()
check("F1", #rows == 1 and select(2, cells(rows[1])).itemLink == "[B]", "the item being typed for still goes when its time is up")
check("F2", not box.focused and box.showingPlaceholder, "and the typing ends with it, not carried over to the next item")
check("F3", box.scripts.OnHide == box.ClearFocus, "a note box that hides lets go of the keyboard")

-- Only what a raider can still get ----------------------------------------------------------------------
PLC.Session.items = {
	[1] = { link = "[Open]", deadlineAt = now + 60, tradeExpiresAt = now + 600 },
	[2] = { link = "[Expired]", untradable = true },
	[3] = { link = "[Never put up]" },
	[4] = { link = "[Trade ending]", deadlineAt = now + 60, tradeExpiresAt = now + 5 },
}
refresh()
local function links()
	local list = {}
	for _, row in ipairs(shownRows()) do list[#list + 1] = select(2, cells(row)).itemLink end
	return table.concat(list, ",")
end
check("E1", links() == "[Open],[Trade ending]", "an item whose trade time ran out, or that was never put up, isn't shown")
now = now + 6
refresh()
check("E2", links() == "[Open]", "and one whose trade time runs out during the session goes then")

-- Closing ---------------------------------------------------------------------------------------
-- It comes back within a second while anything waits for an answer, so there's nothing to close it with.
check("C1", not closeButtons and #UISpecialFrames == 0, "no close button, and Escape leaves it open")

-- Two of the same --------------------------------------------------------------------------------------
-- A boss dropped the same item twice: raiders answer once, for both, and the master looter still
-- awards each on its own.
local answered = {}
PLC.Session.SendMyResponse = function(_, idx, key) answered[#answered + 1] = idx .. "=" .. key end
PLC.Session.items = {
	[1] = { link = "[Glaive]", itemString = "item:32837", deadlineAt = now + 40 },
	[2] = { link = "[Helm]", itemString = "item:32235", deadlineAt = now + 60 },
	[3] = { link = "[Glaive]", itemString = "item:32837", deadlineAt = now + 60 },
}
refresh()
rows = shownRows()
local icon = cells(rows[1])
check("T1", #rows == 2 and links() == "[Glaive],[Helm]", "two copies share one row")
check("T2", icon.count.text == 2 and cells(rows[2]).count.text == "", "the icon says how many dropped, like a stack in the bags")
local data = upvalue(LootFrame.Refresh, "buildRows")()
check("T3", data[1].deadlineAt == now + 40, "the first copy to run out sets the time")
data[1].respond("BIS")
check("T4", table.concat(answered, ",") == "1=BIS,3=BIS", "one answer is sent for each copy")

-- Can't use it --------------------------------------------------------------------------------------------
-- Another class's token, plate for a mage: a Pass goes by itself, with a note, and it isn't shown.
PLC.db.profile.autoPass = true
if not PLC.Responses:Find("PASS") then SET[#SET + 1] = { key = "PASS", text = "Pass" } end
PLC.AutoPass = { ShouldPass = function(_, link) return link == "[Plate]" end, Note = function() return "AUTOPASS_NOTE" end }
local sentPasses = {}
PLC.Session.SendMyResponse = function(_, idx, key, note)
	sentPasses[#sentPasses + 1] = idx .. "=" .. key .. ":" .. tostring(note)
	PLC.Session.responses[idx] = { [UnitGUID("player")] = { response = key, note = note } } -- as the real one records it
end
PLC.Session.items = {
	[1] = { link = "[Plate]", itemString = "item:1", deadlineAt = now + 60 },
	[2] = { link = "[Cloth]", itemString = "item:2", deadlineAt = now + 60 },
}
PLC.Session.responses = {}
refresh()
check("P1", links() == "[Cloth]", "an item this character can't use isn't shown")
check("P2", #sentPasses == 0 and #soon == 1, "its Pass waits until the window is drawn")
soon[1](); soon = {}
check("P3", sentPasses[1] == "1=PASS:AUTOPASS_NOTE", "then goes out, with a note saying why")
refresh()
check("P4", #soon == 0, "and only once")
PLC.db.profile.autoPass = false
PLC.Session.items[3] = { link = "[Plate]", itemString = "item:3", deadlineAt = now + 60 }
refresh()
check("P5", links():find("[Plate]", 1, true) ~= nil and #soon == 0, "turned off, everything shows")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
