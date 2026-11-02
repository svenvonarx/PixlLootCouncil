-- Run from the addon folder: luajit tests/banking_test.lua
--
-- The real Data/Session.lua, Data/History.lua, Loot/Announce.lua, UI/VotingFrame.lua,
-- UI/SessionFrame.lua and UI/HistoryFrame.lua against a stubbed game and stubbed widgets: Banking,
-- and who already has the item being reviewed.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.time = os.time
_G.date = os.date
_G.GetServerTime = os.time
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strmatch = string.match
_G.tinsert = table.insert
_G.strsplit = function(sep, s)
	local a, b = s:match("^(.-)" .. sep .. "(.*)$")
	if a then return a, b end
	return s
end
_G.UNKNOWN = "Unknown"
_G.RAID_CLASS_COLORS = {}
-- Keys come back as themselves, so tests can see which text was used. LOCALE has the real English.
local LOCALE = {}
_G.LibStub = function()
	return {
		GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end,
		NewLocale = function() return setmetatable({}, { __newindex = function(_, k, v) LOCALE[k] = v end }) end,
	}
end
assert(loadfile("Locale/enUS.lua"))("PixlLootCouncil", {})

-- Anything capitalized is a method that does nothing, unless a test needs it to do something.
local noop = function() end
local frameMethods = {
	SetScript = function(f, name, fn) f.scripts[name] = fn end,
	GetScript = function(f, name) return f.scripts[name] end,
	HookScript = function(f, name, fn) f.scripts[name] = fn end,
	SetPoint = function(f, ...) f.points[#f.points + 1] = { ... } end,
	ClearAllPoints = function(f) f.points = {} end,
	SetShown = function(f, shown) f.shown = shown and true or false end,
	Show = function(f) f.shown = true end,
	Hide = function(f) f.shown = false end,
	IsShown = function(f) return f.shown end,
	SetText = function(f, text) f.text = text end,
	GetText = function(f) return f.text end,
	SetTextColor = function(f, r, g, b) f.color = { r, g, b } end,
	SetWordWrap = function(f, wrap) f.wordWrap = wrap end,
	SetSize = function(f, w, h) f.width, f.height = w, h end,
	SetWidth = function(f, w) f.width = w end,
	GetWidth = function(f) return f.width or 100 end,
	GetHeight = function() return 100 end,
	GetVerticalScroll = function() return 0 end,
	GetFrameLevel = function() return 1 end,
}
local function frame(props)
	local f = props or {}
	f.scripts, f.points, f.shown = {}, {}, false
	f.label = f.label or (props and props.noLabel and nil)
	return setmetatable(f, { __index = function(_, k)
		if frameMethods[k] then return frameMethods[k] end
		if type(k) == "string" and k:match("^%u") then return noop end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return frame() end end
	end })
end
frameMethods.CreateTexture = function() return frame() end
frameMethods.CreateFontString = function() return frame() end
_G.CreateFrame = function() return frame() end
_G.UIParent = frame()
_G.GameTooltip = frame()
_G.UISpecialFrames = {}
_G.StaticPopupDialogs = {}

local ME, MULE, OTHER = "guid-me", "guid-mule", "guid-other"
local myGuid = ME
_G.UnitGUID = function() return myGuid end
_G.UnitName = function() return "Pixl" end
_G.GetRealmName = function() return "Realm" end
_G.IsInRaid = function() return true end
_G.IsInGroup = function() return true end
_G.InCombatLockdown = function() return false end
_G.C_Item = { GetItemInfo = function(link)
	return nil, "[Equipped " .. tostring(link) .. "]", nil, nil, nil, nil, nil, nil, "INVTYPE_HEAD"
end }
local chat = {}
_G.C_ChatInfo = { SendChatMessage = function(text, channel) chat[#chat + 1] = { text, channel } end }

-- The addon around the files under test ------------------------------------------------------------
local PLC = { Loot = {}, UI = { Widgets = {} } }
function PLC:RegisterOnEnable() end
function PLC:RegisterSlashCommand() end
function PLC:SetDefaultSlashHandler() end
function PLC:RegisterEvent() end
function PLC:ScheduleTimer() end
function PLC:ScheduleRepeatingTimer() return {} end
function PLC:CancelTimer() end
PLC.Events = { RegisterHandler = noop }

local tables, buttons, texts = {}, {}, {}
PLC.UI.Theme = { LAYOUT = setmetatable({}, { __index = function() return 20 end }), Track = function(_, x) return x end }
PLC.UI.Widgets.Primitives = setmetatable({
	color = function(name) if name == "accent" then return 1, 0, 0, 1 end return 1, 1, 1, 1 end,
	attachTooltip = function(f, title, text) f.tipTitle, f.tipText = title, text end,
	createText = function(_, text)
		local label = frame({ text = text })
		texts[#texts + 1] = label
		return label
	end,
}, { __index = function() return function(...) return frame() end end })
PLC.UI.Widgets.Button = setmetatable({
	createButton = function(_, text, width)
		local b = frame({ label = frame({ text = text }), width = width, caption = text })
		buttons[text] = b
		return b
	end,
}, { __index = function() return function() return frame({ label = frame() }) end end })
PLC.UI.Widgets.Dropdown = setmetatable({}, { __index = function() return function() return frame({ text = frame(), arrow = frame() }) end end })
PLC.UI.Widgets.ScrollFrame = { RESERVED_WIDTH = 14 }
PLC.UI.Widgets.DataTable = { Create = function(_, rowHeight)
	local t = frame({ rowHeight = rowHeight })
	t.SetColumns = function(s, columns) s.columns = columns end
	t.SetRows = function(s, rows) s.rows = rows end
	tables[#tables + 1] = t
	return t
end }
local windows = {}
PLC.UI.TradeFrame = { Open = function() windows.trades = (windows.trades or 0) + 1 end, OnSessionUpdated = noop }
PLC.UI.LootFrame = { Refresh = noop }
PLC.UI.LootTimersFrame = { OnSessionUpdated = noop, Hide = noop, IsShown = function() return false end }

local sent = {}
PLC.Comms = { Sync = setmetatable({}, { __index = function(_, command)
	return function(_, ...) sent[#sent + 1] = { command = command, ... } end
end }) }
local function sentOf(command)
	local found = {}
	for _, message in ipairs(sent) do if message.command == command then found[#found + 1] = message end end
	return found
end

local ROSTER = {
	[ME] = { name = "Pixl-Realm", class = "PALADIN" },
	[MULE] = { name = "Mule-Realm", class = "ROGUE" },
	[OTHER] = { name = "Other-Realm", class = "MAGE" },
}
PLC.Roster = {
	Get = function(_, guid) return ROSTER[guid] end,
	IterateGroup = function() return pairs(ROSTER) end,
	ShortName = function(_, name) return name and name:match("^[^-]+") end,
}
PLC.Presence = { IsPresent = function() return true end }
PLC.Gear = setmetatable({
	SlotsForEquipLoc = function() return { 1 } end,
	GetEquipped = function() return 1234 end,
}, { __index = function() return noop end })
local ACTIVE = { { key = "BIS", text = "BiS", color = { r = 0, g = 1, b = 0 } } }
PLC.Responses = { GetActive = function() return ACTIVE end, Sanitize = function(set) return set end, GetDefaults = function() return ACTIVE end }
PLC.CouncilRules = setmetatable({ IsMasterLootMethod = function() return true end }, { __index = function() return noop end })
PLC.Professions = setmetatable({ ENCHANTING_KEY = "enchanting", HasProfession = function(_, guid) return guid == OTHER end }, { __index = function() return noop end })
PLC.Preview = setmetatable({ CheckFinished = noop }, { __index = function() return noop end })
PLC.Loot.Detection = setmetatable({}, { __index = function() return noop end })
PLC.Loot.BagTracker = setmetatable({}, { __index = function() return noop end })
PLC.db = { char = {}, profile = {
	announce = { award = true, sessionStart = true }, responseTimeoutSeconds = 60,
	sessionHeartbeatSeconds = 15, sessionForceEndMinutes = 5, historyFilters = {},
} }
PLC.lootDB = { factionrealm = {} }

for _, file in ipairs({ "Data/Session.lua", "Data/History.lua", "Loot/Announce.lua", "UI/VotingFrame.lua", "UI/HistoryFrame.lua", "UI/SessionFrame.lua" }) do
	assert(loadfile(file))("PixlLootCouncil", PLC)
end
local Session, History, SessionFrame = PLC.Session, PLC.History, PLC.UI.SessionFrame
function Session:IsCouncilMember() return true end

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

-- A running session with two items, held by `holder`.
local function session(holder)
	myGuid = ME
	for k in pairs(sent) do sent[k] = nil end
	for k in pairs(chat) do chat[k] = nil end
	windows.trades = nil
	PLC.lootDB.factionrealm = {}
	Session.state, Session.sessionId, Session.preview = "active", "s1", false
	Session.owner = { guid = holder or ME, name = "Pixl-Realm" }
	Session.enchanterGuid = OTHER
	Session.items = {
		[1] = { idx = 1, link = "|cff|Hitem:100:0:0|h[Helm]|h|r", itemString = "item:100", bossName = "Boss", instance = "Karazhan" },
		[2] = { idx = 2, link = "|cff|Hitem:200:0:0|h[Boots]|h|r", itemString = "item:200", bossName = "Boss", instance = "Karazhan" },
	}
	Session.responses = { [1] = { [ME] = { response = "BIS", note = "for my offset" } }, [2] = {} }
	SessionFrame:Open()
end

session()
local panel = PLC.UI.VotingFrame.activePanel
local bank, disenchant = panel.bankButton, panel.disenchantButton
check("B1", bank ~= nil and bank.caption == "VOTINGFRAME_BANKING", "there's a Banking button")
check("B2", bank.shown and disenchant.shown, "the holder sees both buttons")
check("B3", bank.tipText == "VOTINGFRAME_BANKING_TIP", "and Banking explains itself")

local firstIdx = panel.currentIdx
bank.scripts.OnClick()
check("B36", panel.currentIdx ~= firstIdx and panel.currentIdx ~= nil, "and moves on to the next item, like Award and Disenchant")
panel:ShowItem(1)
local item = Session.items[1]
if firstIdx ~= 1 then -- whichever came first is the one that got staged
	item = Session.items[firstIdx]
end
check("B4", item.preAwardGuid == ME and item.preAwardReason == "bank" and not item.awarded, "Banking stages to the holder, and commits nothing")
check("B5", #sentOf("SendStage") == 1 and sentOf("SendStage")[1][4] == "bank", "the council hears about it")
panel:ShowItem(item.idx)
check("B6", bank.label.text == "VOTINGFRAME_STAGED" and bank.label.color[2] == 0, "the button reads Staged, in the accent color")
check("B7", disenchant.label.text == "VOTINGFRAME_DISENCHANT", "Disenchant doesn't")
local myRow
for _, row in ipairs(panel.rowsData) do if row.guid == ME then myRow = row end end
check("B8", myRow and not myRow.staged, "my own candidate row doesn't read Staged: I didn't win it")
panel:Award(MULE)
panel:ShowItem(item.idx)
check("B9", item.preAwardGuid == MULE and bank.label.text == "VOTINGFRAME_BANKING", "awarding it instead replaces the pick")
for _, row in ipairs(panel.rowsData) do if row.guid == MULE then myRow = row end end
check("B10", myRow.staged, "and a normal pick still shows on its row")
panel:ShowItem(item.idx)
disenchant.scripts.OnClick()
panel:ShowItem(item.idx)
check("B11", item.preAwardReason == "disenchant" and disenchant.label.text == "VOTINGFRAME_STAGED" and bank.label.text == "VOTINGFRAME_BANKING", "so does disenchanting it")

-- Committing ----------------------------------------------------------------------------------------
session()
panel:ShowItem(1); bank.scripts.OnClick()
local banked = Session.items[1]
Session:AwardAllPreAwarded()
check("B12", banked.awarded == ME and banked.awardReason == "bank" and banked.traded, "Award All finishes it: awarded to the holder, nothing to trade")
check("B13", Session.items[1] == nil, "so it's out of the session")
check("B14", #sentOf("SendAward") == 1 and sentOf("SendAward")[1][4] == "bank" and #sentOf("SendTradeComplete") == 1, "everyone hears the reason, and that it's done")
check("B15", windows.trades == nil, "Loot Trades stays closed with nothing to trade")
check("B16", #chat == 1 and chat[1][1] == "ANNOUNCE_BANK" and LOCALE["ANNOUNCE_BANK"]:find("%s", 1, true) ~= nil, "raid chat gets the bank line, with no name")

local entries = PLC.lootDB.factionrealm["Pixl-Realm"] or select(2, next(PLC.lootDB.factionrealm))
local entry = entries and entries[1]
check("B17", entry and entry.response == "VOTINGFRAME_BANKING" and entry.responseID == 2 and entry.isAwardReason == true, "history: RC's Banking award reason, under the holder")
check("B18", entry and entry.color[1] == 1 and entry.color[2] == 1 and entry.color[3] == 1, "in RC's white")
check("B19", entry and entry.note == nil and entry.itemReplaced1 == nil, "without the holder's response note or gear")
check("B20", LOCALE["VOTINGFRAME_BANKING"] == "Banking", "and the text is RC's, so its filter and spreadsheets line up")
check("B21", #sentOf("SendHistory") == 1, "the entry goes to the group like any award")

session()
panel:ShowItem(1); bank.scripts.OnClick()
panel:Award(MULE) -- moved on to item 2 by now, staging the other item for Mule
Session.items[2].preAwardGuid, Session.items[2].preAwardReason = MULE, "award"
Session.items[1].preAwardGuid, Session.items[1].preAwardReason = ME, "bank"
Session:AwardAllPreAwarded()
check("B22", windows.trades == 1 and Session.items[2] and not Session.items[2].traded, "with a real award left, Loot Trades does open")

-- What must not change ------------------------------------------------------------------------------
session()
Session:SetPreAward(1, ME, "award"); Session:SetPreAward(2, ME, "disenchant")
Session:AwardAllPreAwarded()
check("B23", Session.items[1] == nil, "a self-award still finishes by itself")
check("B24", Session.items[2] and not Session.items[2].traded and windows.trades == 1, "a self-disenchant still waits in Loot Trades")

session()
Session.preview = true
Session:SetPreAward(1, ME, "bank"); Session:AwardAllPreAwarded()
check("B25", next(PLC.lootDB.factionrealm) == nil, "a preview keeps nothing in the history")
Session.preview = false

-- Everyone else --------------------------------------------------------------------------------------
session(MULE)
SessionFrame:OnSessionUpdated()
check("B26", not bank.shown and not disenchant.shown, "a council member doesn't get the buttons")
local shownIdx = panel.currentIdx
Session:OnStageReceived({ sessionId = "s1", idx = shownIdx, guid = MULE, reason = "bank" })
check("B27", panel.header.text:find("VOTINGFRAME_STAGED_BANKING", 1, true) ~= nil, "but sees Staged: Banking")
Session:OnAwardReceived({ sessionId = "s1", idx = shownIdx, winnerGuid = MULE, reason = "bank" })
check("B28", Session.items[shownIdx].awardReason == "bank" and windows.trades == nil, "and the award, with no window for them")

session()
panel:ShowItem(1); bank.scripts.OnClick(); panel:ShowItem(1)
check("B29", not panel.header.text:find("STAGED", 1, true), "the holder has the button for that")

-- The header row ------------------------------------------------------------------------------------
session()
panel:ShowItem(1)
SessionFrame:OnSessionUpdated()
local count = panel.header
check("B30", bank.points[1][1] == "RIGHT" and bank.points[1][2] == disenchant and bank.points[1][3] == "LEFT", "Banking sits left of Disenchant")
check("B31", count.points[1][2] == bank and count.points[1][3] == "TOPLEFT", "the holder's vote count is left of both")
session(MULE); panel:ShowItem(1); SessionFrame:OnSessionUpdated()
check("B32", count.points[1][2] == disenchant and count.points[1][3] == "TOPRIGHT", "a council member's takes their place")
check("B33", bank.width + 4 + disenchant.width == 144 and LOCALE["VOTINGFRAME_VOTE_COUNT"] == "%d/%d voted", "the row leaves the room the item name and trade time need")

local cutShort = false
for _, label in ipairs(texts) do
	local right = false
	for _, point in ipairs(label.points) do right = right or point[1] == "RIGHT" end
	cutShort = cutShort or (label.wordWrap == false and right)
end
check("B37", cutShort, "a long item name is cut short at the vote count")

-- Sidebar tooltips ----------------------------------------------------------------------------------
local cell
for _, t in ipairs(tables) do
	for _, column in ipairs(t.columns or {}) do
		if column.isWidget and column.update and t ~= panel.dataTable and not cell then cell = column end
	end
end
local function status(row)
	local holder = cell.create(frame())
	cell.update(holder, row)
	return holder.tooltipStatus
end
session()
check("B34", status({ idx1 = 1, link1 = "x", awarded1 = ME, awardReason1 = "bank" }) == "SESSIONFRAME_BANKED", "the sidebar says Banked")
check("B35", status({ idx1 = 1, link1 = "x", preAwardGuid1 = ME, preAwardReason1 = "bank" }) == "VOTINGFRAME_STAGED_BANKING", "and Staged: Banking")

-- Who already has it ---------------------------------------------------------------------------------
local LINK = "|cff|Hitem:100:0:0|h[Helm]|h|r"
local function history(entries)
	PLC.lootDB.factionrealm = entries
end
local function won(fields)
	fields.lootWon = fields.lootWon or LINK
	fields.date, fields.id = "2026/10/01", "1-" .. tostring(fields)
	return fields
end

local db = { ["Mule-Realm"] = { won({ response = "BiS", responseID = 1 }) } }
session(); history(db); panel:ShowItem(1)
local seen = {}
for _, row in ipairs(panel.rowsData) do seen[row.shortName] = row.received end
check("R1", seen.Mule == true and seen.Other == false and seen.Pixl == false, "someone who got it is marked, the others aren't")

local function markedFor(entry)
	session()
	history({ ["Mule-Realm"] = { entry } })
	panel:ShowItem(1)
	for _, row in ipairs(panel.rowsData) do
		if row.shortName == "Mule" then return row.received end
	end
end
check("R2", markedFor(won({ response = "BiS", responseID = 1 })) == true, "a normal response counts, even with response number 1")
check("R3", markedFor(won({ lootWon = "|cff|Hitem:999:0:0|h[Other]|h|r", response = "BiS", responseID = 1 })) == false, "another item doesn't")
check("R4", markedFor(won({ lootWon = "|cff|Hitem:100:2564:0|h[Helm]|h|r", response = "BiS", responseID = 1 })) == true, "the same item with an enchant does")
check("R5", markedFor(won({ response = "VOTINGFRAME_BANKING", responseID = 2, isAwardReason = true })) == false, "banked isn't received")
check("R6", markedFor(won({ response = "VOTINGFRAME_DISENCHANT", responseID = 1, isAwardReason = true })) == false, "disenchanted isn't either")
check("R7", markedFor(won({ response = "Bank it", responseID = "2", isAwardReason = true })) == false, "RC's reason keeps counting when renamed, or stored as text")
check("R21", markedFor(won({ response = "Shard it", responseID = 1, isAwardReason = true })) == false, "and a renamed Disenchant")
check("R8", markedFor(won({ response = "VOTINGFRAME_DISENCHANT" })) == false, "an old RC entry with only the text is caught too")
check("R9", markedFor(won({ response = "Free", responseID = 3, isAwardReason = true })) == true, "RC's Free award is received")
check("R10", markedFor(won({ response = "VOTINGFRAME_AWARD", responseID = 0, isAwardReason = true })) == true, "so is an award to someone who didn't respond")

session()
history({ ["Mule-Realm"] = { won({ response = "BiS" }) }, ["Mule-OtherRealm"] = {} })
panel:ShowItem(1)
history({ ["Mule-OtherRealm"] = { won({ response = "BiS" }) } })
panel:ShowItem(1)
seen = {}
for _, row in ipairs(panel.rowsData) do seen[row.shortName] = row.received end
check("R11", seen.Mule == false, "a namesake on another realm doesn't count")

ROSTER[MULE].name = "Mule-Some Realm"
check("R12", markedFor(won({ response = "BiS" })) == false, "(no entry under the name with a space)")
session(); history({ ["Mule-SomeRealm"] = { won({ response = "BiS" }) } }); panel:ShowItem(1)
for _, row in ipairs(panel.rowsData) do seen[row.shortName] = row.received end
check("R13", seen.Mule == true, "a realm with a space matches how the history stores it")
ROSTER[MULE].name = "Mule-Realm"

session(); history({})
Session.items[1].link = nil
check("R14", pcall(function() panel:ShowItem(1) end), "an item with no link yet doesn't break the grid")

local nameCell = panel.dataTable.columns[1]
local cellHolder = nameCell.create(frame())
local function row(isReceived) return { shortName = "Mule", class = "ROGUE", received = isReceived } end
nameCell.update(cellHolder, row(true))
local shownWhenHas = cellHolder.received.shown
nameCell.update(cellHolder, row(false))
check("R15", shownWhenHas and not cellHolder.received.shown, "the tag follows the row, as cells get reused")
check("R16", cellHolder.received.text == "VOTINGFRAME_RECEIVED" and cellHolder.received.points[1][1] == "RIGHT", "it sits at the cell's right edge")
check("R17", cellHolder.text.wordWrap == false and cellHolder.text.points[2][1] == "RIGHT" and cellHolder.text.points[2][2] == -20, "and the name stops short of it")

local function linesFor(fn, ...)
	local lines = {}
	fn({ AddLine = function(_, text) lines[#lines + 1] = tostring(text) end, AddDoubleLine = function(_, text) lines[#lines + 1] = tostring(text) end }, ...)
	return table.concat(lines, "|")
end
history({ ["Mule-Realm"] = { won({ response = "VOTINGFRAME_BANKING", responseID = 2, isAwardReason = true }) } })
check("R18", not linesFor(PLC.UI.HistoryFrame.AddPlayerLines, "Mule-Realm", LINK):find("HISTORY_TIP_ALREADY_HAS", 1, true), "the hover doesn't say a banked item was received")
check("R19", linesFor(PLC.UI.HistoryFrame.AddItemLines, LINK):find("HISTORY_TIP_ITEM_NONE", 1, true) ~= nil, "nor does the item's own tooltip")
history({ ["Mule-Realm"] = { won({ response = "BiS" }) } })
check("R20", linesFor(PLC.UI.HistoryFrame.AddPlayerLines, "Mule-Realm", LINK):find("HISTORY_TIP_ALREADY_HAS", 1, true) ~= nil, "a real award still says so, with the date")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
