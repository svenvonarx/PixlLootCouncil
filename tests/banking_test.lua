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
	HookScript = function(f, name, fn)
		local previous = f.scripts[name]
		f.scripts[name] = previous and function(...) previous(...); fn(...) end or fn
	end,
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
	IsTruncated = function(f) return f.truncated end,
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
local tooltipLines = {}
function GameTooltip:AddLine(text, r, g, b) tooltipLines[#tooltipLines + 1] = { text = tostring(text), r = r, g = g, b = b } end
function GameTooltip:AddDoubleLine(text) self:AddLine(text) end
function GameTooltip:SetText(text, _, _, _, _, wrap) self:AddLine(text); self.wrapped = wrap end
function GameTooltip:SetHyperlink(link) self:AddLine("item:" .. link) end
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
	attachItemTooltip = function(f)
		f.scripts.OnEnter = function(self)
			if self.itemLink then GameTooltip:SetHyperlink(self.itemLink) end
		end
	end,
	createText = function(parent, text, size)
		local label = frame({ text = text, parent = parent, size = size })
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
PLC.UI.Widgets.ScrollFrame = { RESERVED_WIDTH = 14, createScrollFrame = function() return frame() end }
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
check("B13", Session.items[1] == banked and banked.votes and banked.votes[ME].response == "BIS",
	"and stays listed, finished, with the votes it was awarded on, until the master looter removes it")
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
local order = {}
for _, message in ipairs(sent) do
	if message.command == "BeginBatch" or message.command == "SendAward" or message.command == "FlushBatch" or message.command == "SendSessionEnd" then
		order[#order + 1] = message.command
	end
end
check("B22a", table.concat(order, ",") == "BeginBatch,SendAward,SendAward,FlushBatch,SendSessionEnd",
	"Award All's awards go out together, and the session's end after them: " .. table.concat(order, ","))

-- What must not change ------------------------------------------------------------------------------
session()
Session:SetPreAward(1, ME, "award"); Session:SetPreAward(2, ME, "disenchant")
Session:AwardAllPreAwarded()
check("B23", Session.items[1] and Session.items[1].traded, "a self-award still finishes by itself")
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
check("B31", count.points[1][1] == "RIGHT" and count.points[1][2] == bank and count.points[1][3] == "LEFT", "the holder's vote count is left of both, level with them")
session(MULE); panel:ShowItem(1); SessionFrame:OnSessionUpdated()
check("B32", count.points[1][1] == "RIGHT" and count.points[1][2] == disenchant and count.points[1][3] == "RIGHT", "a council member's takes their place")

-- The window's edges: the details' buttons end where the toolbar does, and the icons have as much
-- room on their left (inside the 1px border) as the scrollbar strip leaves them on their right.
local function upvalue(fn, name)
	for i = 1, 200 do
		local n, v = debug.getupvalue(fn, i)
		if n == name then return v end
		if not n then return nil end
	end
end
local ensureSessionFrame = upvalue(upvalue(SessionFrame.Open, "showFullWindow"), "ensureFrame")
local sessionWindow, toolbar = upvalue(ensureSessionFrame, "frame"), upvalue(ensureSessionFrame, "enchanterRow")
local sidebar, details = upvalue(ensureSessionFrame, "itemListContainer"), upvalue(ensureSessionFrame, "detailArea")
local content = upvalue(ensureSessionFrame, "content")
local iconsLeft = toolbar.points[1][4] + content.points[1][4]
local detailsLeft = iconsLeft + sidebar.width + details.points[1][4]
local buttonsRight
for _, point in ipairs(disenchant.points) do
	if point[1] == "TOPRIGHT" and point[2] == details then buttonsRight = detailsLeft + point[4] end
end
check("G1", buttonsRight == sessionWindow.width + toolbar.points[2][4], "Disenchant and Award end level with the toolbar's last button")
check("G2", iconsLeft - 1 == PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH, "the icons have the same room on both sides")
check("B33", bank.width + 4 + disenchant.width == 144 and LOCALE["VOTINGFRAME_VOTE_COUNT"] == "%d/%d voted", "the row leaves the room the item name and trade time need")

local itemLabel
for _, label in ipairs(texts) do
	if label.size == 13 and label.wordWrap == false then itemLabel = label end
end
local itemRow = itemLabel and itemLabel.parent
local labelRight = false
for _, point in ipairs(itemLabel and itemLabel.points or {}) do labelRight = labelRight or point[1] == "RIGHT" end
check("B37", labelRight, "the item name stops at the edge of its row, so it's cut short")

-- What's at the end of the item name's row: which frame, and which side of it.
local function rowEnd()
	for _, point in ipairs(itemRow.points) do
		if point[1] == "RIGHT" then return point[2], point[3] end
	end
end
local removeButton = buttons["SESSIONFRAME_REMOVE"]
session(); panel:ShowItem(1); SessionFrame:OnSessionUpdated()
local target, side = rowEnd()
check("H1", target == count and side == "LEFT", "the holder's name stops at the vote count, itself left of the buttons")
session(MULE); SessionFrame:OnSessionUpdated()
target, side = rowEnd()
check("H2", target == count and side == "LEFT", "so does a council member's, with more room")

session()
Session.state = "inactive"
function Session:CanManage() return true end
SessionFrame:OnSessionUpdated()
target, side = rowEnd()
check("H3", removeButton.shown and target == removeButton and side == "LEFT", "outside a session the name stops at Remove, not underneath it")

Session.items = {}
SessionFrame:OnSessionUpdated()
target, side = rowEnd()
check("H4", itemLabel.text == "SESSIONFRAME_NO_ITEMS" and target == disenchant and side == "RIGHT", "with no items, the message gets the whole row")
check("H5", not count.shown and not bank.shown and not disenchant.shown and not removeButton.shown, "as nothing else is on it")

local function hover()
	for k in pairs(tooltipLines) do tooltipLines[k] = nil end
	itemRow.scripts.OnEnter(itemRow)
	local joined = {}
	for i, line in ipairs(tooltipLines) do joined[i] = line.text end
	return table.concat(joined, "|")
end
itemLabel.truncated = false
check("H6", hover() == "", "text that fits doesn't need a tooltip")
itemLabel.truncated = true
check("H7", hover() == "SESSIONFRAME_NO_ITEMS" and GameTooltip.wrapped == true, "text that's cut shows in full, wrapped")
itemLabel.truncated = false

session()
PLC.Loot.BagTracker.StatusText = function() return "Tradable for 1h 52m", "success" end
SessionFrame:OnSessionUpdated()
local shown = hover()
check("H8", shown:find("item:", 1, true) == 1 and shown:find("Tradable for 1h 52m", 1, true) ~= nil, "an item's tooltip always has its trade time, the part a cut would lose")
check("H9", tooltipLines[2].text == "Tradable for 1h 52m" and tooltipLines[2].r ~= nil, "right below the item, in its color")
PLC.Loot.BagTracker.StatusText = function() return nil end
SessionFrame:OnSessionUpdated()
check("H10", not hover():find("Tradable", 1, true), "and nothing when the item has none")
Session.items = {}
SessionFrame:OnSessionUpdated()
PLC.Loot.BagTracker.StatusText = noop
Session.CanManage = nil
function Session:CanManage() return false end

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
check("R17", cellHolder.text.wordWrap == false and cellHolder.text.points[2][1] == "RIGHT" and cellHolder.text.points[2][2] == cellHolder.received, "and the name stops short of it, however long the word is")

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

-- A preview ending from outside the Options page ----------------------------------------------------
assert(loadfile("Data/Preview.lua"))("PixlLootCouncil", PLC)
local optionsTold = 0
PLC.UI.OptionsFrame = { OnPreviewChanged = function() optionsTold = optionsTold + 1 end }
Session.state, Session.preview = "ended", false
local function runningPreview()
	optionsTold = 0
	PLC.Preview:Enter()
	Session.state, Session.sessionId = "active", "s1"
	Session.owner = { guid = ME, name = "Pixl-Realm" }
	Session.items = {}
end
runningPreview()
check("U1", optionsTold == 1, "the Options page hears when a preview starts, wherever from")
Session:End()
check("U2", Session.preview == false and optionsTold == 2, "pressing End Session ends it, and the Options page hears")

runningPreview()
Session.items = { [1] = { idx = 1, awarded = MULE } }
Session:End()
check("U3", Session.preview == true and optionsTold == 1, "with a trade left it keeps running, so the button stays on Stop")
Session:MarkItemTraded(1)
check("U4", Session.preview == false and optionsTold == 2, "and the last trade ends it")

runningPreview()
PLC.Preview:OnPreviewEndReceived({ sessionId = "s1" })
check("U5", Session.preview == false and optionsTold == 2, "so does the holder ending it, for everyone else")

runningPreview()
PLC.Preview:Toggle()
check("U6", Session.preview == false and optionsTold == 2, "and /plc preview")

-- Who needs it most ---------------------------------------------------------------------------------------
session()
local savedActive = { unpack(ACTIVE) }
for i = #ACTIVE, 1, -1 do ACTIVE[i] = nil end
for i, key in ipairs({ "BIS", "UPGRADE", "OS", "PASS" }) do ACTIVE[i] = { key = key, text = key, color = { r = 1, g = 1, b = 1 } } end
local THIRD = "Player-Third"
ROSTER[THIRD] = { name = "Aaron-Realm", class = "WARRIOR" }
Session.responses[1] = { [ME] = { response = "PASS" }, [MULE] = { response = "OS" }, [OTHER] = { response = "BIS" } }
panel:ShowItem(1)
local order = {}
for _, row in ipairs(panel:buildRows()) do order[#order + 1] = row.shortName end
check("V1", table.concat(order, ",") == "Other,Mule,Aaron,Pixl", "votes are ordered by answer: BiS first, no answer yet, Pass last: " .. table.concat(order, ","))
ROSTER[THIRD] = nil
for i = #ACTIVE, 1, -1 do ACTIVE[i] = nil end
for i, resp in ipairs(savedActive) do ACTIVE[i] = resp end

-- Collecting the same item twice ------------------------------------------------------------------------
-- A slow server (a 25-player boss) can confirm a hand-out after the bag scan already saw the item
-- land: it was listed twice. And reopening a corpse numbers its slots again.
local isReview = PLC.Loot.Detection.IsReviewItem
PLC.Loot.Detection.IsReviewItem = function() return true end
_G.GetInstanceInfo = function() return "Black Temple", "raid", 4, "25 Player", 25, 0, false, 564, 25 end
local GLAIVE = "|cffa335ee|Hitem:32837:0:0|h[Warglaive]|h|r"
local function count(link)
	local id, n = link:match("item:(%d+)"), 0
	for _, item in pairs(Session.items) do if (item.itemString or ""):match("item:(%d+)") == id then n = n + 1 end end
	return n
end
session("Player-Other") -- someone else's pass: nothing is broadcast from here
Session.state = "inactive"
Session.nextIdx = 3
Session:AddTrackedItem(GLAIVE, "GUID-1")
Session:CollectDetectedItems({ [2] = { link = GLAIVE, quality = 4, boss = "Creature-Illidan", bossName = "Illidan Stormrage" } }, true)
check("D1", count(GLAIVE) == 1, "a hand-out confirmed after the bag scan listed the item is the same item")
local glaive
for _, item in pairs(Session.items) do if (item.itemString or ""):match("item:(%d+)") == "32837" then glaive = item end end
check("D2", glaive and glaive.bossName == "Illidan Stormrage" and glaive.itemGUID == "GUID-1", "and it keeps both: the boss, and its copy in the bags")
Session:CollectDetectedItems({ [3] = { link = GLAIVE, quality = 4, boss = "Creature-Illidan" } }, true)
check("D3", count(GLAIVE) == 2, "a second copy handed out is a second item")

local WARGLAIVE_OFF = "|cffa335ee|Hitem:32838:0:0|h[Warglaive Off]|h|r"
local HELMET = "|cffa335ee|Hitem:32235:0:0|h[Cursed Vision]|h|r"
Session:CollectDetectedItems({
	[3] = { link = WARGLAIVE_OFF, quality = 4, boss = "Creature-Illidan" },
	[4] = { link = HELMET, quality = 4, boss = "Creature-Illidan" },
	[5] = { link = HELMET, quality = 4, boss = "Creature-Illidan" },
})
check("D4", count(WARGLAIVE_OFF) == 1 and count(HELMET) == 2, "noted by hand: two copies are two items")
Session:CollectDetectedItems({
	[1] = { link = WARGLAIVE_OFF, quality = 4, boss = "Creature-Illidan" },
	[2] = { link = HELMET, quality = 4, boss = "Creature-Illidan" },
	[3] = { link = HELMET, quality = 4, boss = "Creature-Illidan" },
})
check("D5", count(WARGLAIVE_OFF) == 1 and count(HELMET) == 2, "reopening the corpse, its slots numbered again, adds nothing")
-- The Illidari Council's four corpses share one loot: opening a second one showed the same items.
local LEGS = "|cffa335ee|Hitem:31099:0:0|h[Leggings of the Forgotten Vanquisher]|h|r"
Session:CollectDetectedItems({ [1] = { link = LEGS, quality = 4, boss = "Creature-Gathios" } })
Session:CollectDetectedItems({ [1] = { link = LEGS, quality = 4, boss = "Creature-Veras" } })
check("D6", count(LEGS) == 1, "the same item seen on another council corpse is the same item")
Session:CollectDetectedItems({ [1] = { link = LEGS, quality = 4, boss = "Creature-Veras" } }, true)
local legs
for _, item in pairs(Session.items) do if (item.itemString or ""):match("item:(%d+)") == "31099" then legs = item end end
check("D7", count(LEGS) == 1 and legs.bagged and not legs.lootSlot, "handed out to the master looter after it was noted: still the same item, now in the bags")
Session:CollectDetectedItems({ [1] = { link = LEGS, quality = 4, boss = "Creature-Illidan" } })
check("D8", count(LEGS) == 2, "once the first is in the bags, another one lying in a corpse is another item")
PLC.Loot.Detection.IsReviewItem = isReview

-- Sharing from Loot History ------------------------------------------------------------------------------
PLC.db.profile.historyFilters = PLC.db.profile.historyFilters or { class = {}, hiddenResponses = {} }
PLC.db.profile.historyFilters.class = PLC.db.profile.historyFilters.class or {}
PLC.db.profile.historyFilters.hiddenResponses = PLC.db.profile.historyFilters.hiddenResponses or {}
PLC.UI.HistoryFrame:Open()
local sharedWith
local realShare = PLC.History.Share
PLC.History.Share = function(_, from, to, db) sharedWith = { from = from, to = to, db = db } end
PLC.UI.HistoryFrame.shareButton.scripts.OnClick()
check("H20", sharedWith and sharedWith.from == nil and type(sharedWith.db) == "table", "Share sends what the window shows, its filters included")
PLC.History.Share = realShare

-- Pasting into the import box ---------------------------------------------------------------------------
-- The game lays out all of a multi-line box's text: a pasted CSV export of a long history froze it.
local function findUpvalue(fn, wanted, seen)
	seen = seen or {}
	if seen[fn] then return nil end
	seen[fn] = true
	for i = 1, 200 do
		local name, value = debug.getupvalue(fn, i)
		if not name then break end
		if name == wanted then return value end
		if type(value) == "function" then
			local found = findUpvalue(value, wanted, seen)
			if found then return found end
		end
	end
end
-- Four item icons a row in the Loot Session window, so a raid's loot doesn't make it very tall.
local pack = findUpvalue(PLC.UI.SessionFrame.Open, "packItemRows")
local packed = pack({ { idx = 1 }, { idx = 2 }, { idx = 3 }, { idx = 4 }, { idx = 5 } })
check("G3", #packed == 2 and packed[1].idx4 == 4 and packed[2].idx1 == 5 and packed[2].idx2 == nil, "five items fill one row of four, and start another")

local clock = 100
_G.GetTime = function() return clock end
frameMethods.SetMaxBytes = function(f, bytes) f.maxBytes = bytes end
local importFrame = findUpvalue(PLC.UI.HistoryFrame.Open, "ensureImportFrame")()
local box = importFrame.box
local huge = string.rep("player,date,time,item,response\n", 20000)
for i = 1, #huge do box.scripts.OnChar(box, huge:sub(i, i)) end
box.scripts.OnUpdate(box)
check("P1", box.maxBytes and box.maxBytes <= 5000, "the box itself only holds a few thousand bytes, so a long paste can't freeze the game")
check("P2", importFrame.pasted == huge and box.text:find("HISTORY_IMPORT_PASTED", 1, true) ~= nil,
	"the whole paste is kept, and the box says how much came in")
local imported
local realImport = PLC.History.ImportPlayerExport
PLC.History.ImportPlayerExport = function(_, text) imported = text end
importFrame.importButton.scripts.OnClick()
check("P3", imported == huge, "Import gets the whole paste")
clock = 101
box.scripts.OnChar(box, "x")
box.scripts.OnUpdate(box)
check("P4", importFrame.pasted == huge, "a key pressed afterwards doesn't count as a paste")
box.text = ""
box.scripts.OnTextChanged(box, true)
importFrame.importButton.scripts.OnClick()
check("P5", imported == "", "clearing the box forgets the paste")
PLC.History.ImportPlayerExport = realImport

-- Looking back -------------------------------------------------------------------------------------------
-- Awarded items stay, with the votes they were awarded on: a spare token, and who else wanted it?
session()
Session:SetPreAward(1, MULE, "award"); Session:SetPreAward(2, ME, "bank")
Session:AwardAllPreAwarded()
local flat = findUpvalue(PLC.UI.SessionFrame.Open, "flatItemRows")()
check("K1", #flat == 2 and flat[1].awarded and flat[2].awarded, "after Award All both items are still listed")
Session.responses = {} -- what the next review pass starts with
local myVote
panel:ShowItem(1)
for _, row in ipairs(panel:buildRows()) do if row.guid == ME then myVote = row.response end end
check("K2", myVote == "BIS", "and a new pass doesn't erase the votes it was awarded on")
local winner
for _, row in ipairs(panel:buildRows()) do if row.awardedTo then winner = row.guid end end
check("K3", winner == MULE, "the winner's row says who got it")
local canManage = Session.CanManage
Session.CanManage = function() return true end -- the master looter, who holds what they collected
Session:RemoveAllItems()
Session.CanManage = canManage
check("K4", Session.items[1] and not Session.items[2], "Remove All clears what's finished, and keeps what's still to hand over")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
