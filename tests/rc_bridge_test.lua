-- Run from the addon folder: luajit tests/rc_bridge_test.lua
--
-- Plays an RCLootCouncil master looter against the real Comms/RCWire.lua, Data/RCBridge.lua,
-- Data/HistoryImport.lua and UI/LootFrame.lua. Messages are encoded the way RC's Comms.lua does it,
-- with the real AceSerializer and LibDeflate, and what comes back is read the way RC reads it, so
-- this checks the wire format and not just our own round trip. WoW itself is stubbed.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end

local now = 1000
_G.time = function() return now end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strsplit = function(sep, s, limit)
	local a, b = s:match("^(.-)" .. sep .. "(.*)$")
	if a then return a, b end
	return s
end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.strmatch = string.match
_G.tinsert = table.insert
_G.NEED, _G.GREED, _G.PASS, _G.ROLL = "Need", "Greed", "Pass", "Roll"
_G.ACCEPT, _G.DECLINE = "Accept", "Decline"
_G.UNKNOWNOBJECT = "Unknown"
_G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
_G.StaticPopupDialogs = {}
_G.UISpecialFrames = {}
_G.UIParent = {}

local function loadLua(path, ...)
	return assert(loadfile(path))(...)
end
loadLua("Libs/LibStub/LibStub.lua")
loadLua("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
loadLua("Libs/LibDeflate/LibDeflate.lua")
LibStub:NewLibrary("AceLocale-3.0", 1).GetLocale = function()
	return setmetatable({}, { __index = function(_, k) return k end })
end
local AceSerializer, LibDeflate = LibStub("AceSerializer-3.0"), LibStub("LibDeflate")

-- The world ---------------------------------------------------------------------------------------
local world
local ME, MASTER, LEADER = "Pixl", "Lootboss", "Raidlead"
local function resetWorld()
	world = {
		lootMethod = 2, -- Enum.LootMethod.Masterlooter
		masterRaidIndex = 2,
		inGroup = true,
		inInstance = true,
		groupSize = 25,
		rcRunning = false,
		rolls = 0,
		cached = {},
		uncached = {},
		gear = { [1] = "|cff|Hitem:29011:0:0|h[Helm]|h|r", [16] = "|cff|Hitem:29000:0:0|h[Sword]|h|r" },
	}
end
resetWorld()

local UNITS = { raid1 = ME, raid2 = MASTER, raid3 = LEADER, player = ME }
local function nameOf(unit) return UNITS[unit] or unit end
_G.UnitName = function(unit) return nameOf(unit) end
_G.UnitGUID = function(unit) return unit == "player" and "Player-6412-ABCDEF01" or nil end
_G.UnitIsUnit = function(a, b) return nameOf(a) == nameOf(b) end
_G.UnitIsGroupLeader = function(unit) return nameOf(unit) == LEADER end
_G.IsInGroup = function() return world.inGroup end
_G.IsInRaid = function() return world.inGroup end
_G.GetNumGroupMembers = function() return world.inGroup and world.groupSize or 0 end
_G.GetNumSubgroupMembers = function() return 0 end
_G.IsInInstance = function() return world.inInstance end
_G.GetRealmName = function() return "Spine Shatter" end
_G.GetNormalizedRealmName = function() return "SpineShatter" end
_G.Ambiguate = function(name) return (name:gsub("%-.*$", "")) end
_G.GetGuildInfo = function() return "Guild", "Raider", 3 end
_G.UnitGroupRolesAssigned = function() return "HEALER" end
_G.GetInventoryItemLink = function(_, slot) return world.gear[slot] end
_G.RandomRoll = function() world.rolls = world.rolls + 1 end
_G.C_PartyInfo = { GetLootMethod = function() return world.lootMethod, nil, world.masterRaidIndex end }
_G.C_AddOns = { IsAddOnLoaded = function(name) return world.rcRunning and name == "RCLootCouncil_Classic" end }
_G.C_Item = {
	GetItemInfo = function(x)
		local id = tostring(x):match("item:(%d+)") or tostring(x)
		if world.uncached[id] then return nil end
		local equipLoc = ({ ["30001"] = "INVTYPE_HEAD", ["30002"] = "INVTYPE_WEAPON", ["30003"] = "" })[id] or "INVTYPE_HEAD"
		local ilvl = ({ ["29011"] = 120, ["29000"] = 115, ["30001"] = 141 })[id] or 128
		return "I" .. id, "|cff|Hitem:" .. id .. ":0:0|h[I" .. id .. "]|h|r", 4, ilvl, 70, "", "", 1, equipLoc, id
	end,
	GetItemInfoInstant = function(x) return tonumber(tostring(x):match("item:(%d+)")), "", "", "", 0, 4, 0 end,
}

-- Timers and comms ----------------------------------------------------------------------------------
local PLC = { UI = { Widgets = {} }, Loot = {}, Comms = {} }
local timers, seq = {}, 0
function PLC:ScheduleTimer(fn, delay)
	seq = seq + 1
	local handle = { at = now + (delay or 0), fn = fn, id = seq }
	timers[handle] = true
	return handle
end
function PLC:ScheduleRepeatingTimer(fn, delay)
	local handle = self:ScheduleTimer(fn, delay)
	handle.every = delay
	return handle
end
function PLC:CancelTimer(handle) if handle then timers[handle] = nil end end
function PLC:RegisterEvent() end
function PLC:RegisterSlashCommand() end
local enableCallbacks = {}
function PLC:RegisterOnEnable(fn) enableCallbacks[#enableCallbacks + 1] = fn end

local function advance(seconds)
	local stop = now + seconds
	while true do
		local nextTimer
		for handle in pairs(timers) do
			if handle.at <= stop and (not nextTimer or handle.at < nextTimer.at
				or (handle.at == nextTimer.at and handle.id < nextTimer.id)) then
				nextTimer = handle
			end
		end
		if not nextTimer then break end
		now = nextTimer.at
		if nextTimer.every then nextTimer.at = now + nextTimer.every else timers[nextTimer] = nil end
		nextTimer.fn()
	end
	now = stop
end

local commHandlers = {}
function PLC:RegisterComm(prefix, fn) commHandlers[prefix] = fn end
local sent = {} -- everything this addon sent, decoded the way RC decodes it
function PLC:SendCommMessage(prefix, encoded, distribution, target)
	local decoded = LibDeflate:DecodeForWoWAddonChannel(encoded)
	local ok, command, data = AceSerializer:Deserialize(LibDeflate:DecompressDeflate(decoded))
	assert(ok, "we sent something RC can't deserialize")
	sent[#sent + 1] = { prefix = prefix, command = command, data = data, distribution = distribution, target = target }
end

-- What RC's Comms.lua does to send: Serialize(command, { args... }), deflate level 3, encode.
local function rc(sender, command, ...)
	local serialized = AceSerializer:Serialize(command, { ... })
	local message = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(serialized, { level = 3 }))
	commHandlers.RCLC("RCLC", message, "RAID", sender .. "-SpineShatter")
end
local function rcGuild(sender, command, ...)
	local serialized = AceSerializer:Serialize(command, { ... })
	local message = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(serialized, { level = 3 }))
	commHandlers.RCLC("RCLC", message, "GUILD", sender .. "-SpineShatter")
end

-- UI stubs ------------------------------------------------------------------------------------------
local function newStub(extra)
	local f = extra or {}
	f.scripts, f.shown = {}, true
	return setmetatable(f, { __index = function(_, k)
		if k == "Show" then return function(s) s.shown = true end end
		if k == "Hide" then return function(s) s.shown = false end end
		if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
		if k == "IsShown" then return function(s) return s.shown end end
		if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return newStub() end end
		if k == "SetWidth" then return function(s, v) s.width = v end end
		if k == "GetWidth" then return function(s) return s.width or 0 end end
		if k == "SetText" then return function(s, v) s.text = v end end
		if k == "GetText" then return function(s) return s.text end end
		return function() end
	end })
end
_G.CreateFrame = function() return newStub() end
PLC.UI.Theme = { LAYOUT = { buttonHeight = 28, headerHeight = 32 } }
PLC.UI.Widgets.ScrollFrame = { RESERVED_WIDTH = 11 }
PLC.UI.Widgets.Button = { createButton = function(_, text) return newStub({ width = #text * 6 + 20, label = newStub(), caption = text }) end }
PLC.UI.Widgets.Primitives = setmetatable({
	color = function() return 1, 1, 1, 1 end,
	createText = function(_, text) return newStub({ text = text }) end,
	createEditBox = function(_, width)
		local box = newStub({ width = width, text = "", value = "", placeholder = "note" })
		box.GetValue = function(s) return s.value end
		return box
	end,
}, { __index = function() return function() return newStub() end end })
local rows, columns, columnBuilds = {}, nil, 0
PLC.UI.Widgets.DataTable = { Create = function()
	return {
		SetColumns = function(_, c) columns = c; columnBuilds = columnBuilds + 1 end,
		SetRows = function(_, r) rows = r end,
		SetRowTimerProvider = function() end,
	}
end }

-- The real files ------------------------------------------------------------------------------------
loadLua("Core/Defaults.lua", "PixlLootCouncil", PLC)
loadLua("Core/Events.lua", "PixlLootCouncil", PLC)
PLC.Session = { state = "inactive", items = {}, responses = {}, preview = false, responseTimeoutSeconds = 60 }
PLC.Roster = { ShortName = function(_, name) return name and name:match("^[^-]+") or name end }
PLC.Professions = { ENCHANTING_KEY = "ENCHANTING", known = {} }
for _, file in ipairs({ "Data/CouncilRules.lua", "Data/Gear.lua", "Data/Responses.lua", "Data/History.lua",
	"Data/HistoryImport.lua", "Comms/RCWire.lua", "Loot/Announce.lua", "Data/RCBridge.lua", "UI/LootFrame.lua" }) do
	loadLua(file, "PixlLootCouncil", PLC)
end
local Bridge, History = PLC.RCBridge, PLC.History

-- An empty window hides without rendering, so the stub's row list has to be cleared before each pass.
local realRefresh = PLC.UI.LootFrame.Refresh
PLC.UI.LootFrame.Refresh = function(self)
	rows = {}
	realRefresh(self)
end

-- Test helpers --------------------------------------------------------------------------------------
local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for k, v in pairs(value) do result[k] = copy(v) end
	return result
end
local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function reset()
	resetWorld()
	for handle in pairs(timers) do timers[handle] = nil end
	for k in pairs(sent) do sent[k] = nil end
	for k in pairs(printed) do printed[k] = nil end
	rows, columns = {}, nil
	PLC.db = { profile = copy(PLC.Defaults.profile), char = {}, factionrealm = {} }
	PLC.lootDB = { factionrealm = {} }
	PLC.Session.state, PLC.Session.items = "inactive", {}
	Bridge.enabled = false
	Bridge:Clear()
	Bridge.authority, Bridge.mldb = nil, nil
	for _, fn in ipairs(enableCallbacks) do fn() end
end
local function find(command)
	for _, message in ipairs(sent) do
		if message.command == command then return message end
	end
end
local function findAll(command)
	local all = {}
	for _, message in ipairs(sent) do
		if message.command == command then all[#all + 1] = message end
	end
	return all
end
local function sawPrint(text)
	for _, line in ipairs(printed) do
		if line:find(text, 1, true) then return true end
	end
	return false
end
local function texts(set)
	local t = {}
	for _, resp in ipairs(set) do t[#t + 1] = resp.text end
	return table.concat(t, ",")
end
-- RC's mldb travels with short keys (RCLootCouncil/Classes/Data/MLDB.lua).
local function mldb(timeout)
	return { ["|5"] = 3, ["|8"] = { ["|14"] = { numButtons = 3 } }, ["|11"] = {}, ["|12"] = timeout or 60 }
end
local function lootTable(...)
	local lt = {}
	for session, id in ipairs({ ... }) do
		lt[session] = { string = id .. ":0:0", session = session, owner = MASTER .. "-SpineShatter" }
	end
	return lt
end
local function start(...)
	rc(MASTER, "mldb", mldb())
	rc(MASTER, "lootTable", lootTable(...))
	advance(0.1)
end

-- Receiving items -----------------------------------------------------------------------------------
reset(); start(30001, 30002)
check("R1", #rows == 2 and texts(rows[1].responses) == "Need,Greed,RC_MINOR_UPGRADE,Pass", "items shown with RC's default buttons")
check("R2", rows[1].ownerName == MASTER and math.abs(rows[1].deadlineAt - (now + 60 - 0.1)) < 0.01 and rows[1].link:find("I30001", 1, true) ~= nil, "owner, deadline and link")
check("R3", sawPrint("RC_SESSION_STARTED"), "chat says who started it")

reset(); rc(ME, "mldb", mldb()); rc("Stranger", "lootTable", lootTable(30001)); advance(1)
check("R4", #rows == 0 and not find("lootAck"), "a loot table from someone else is ignored")

reset()
rc(MASTER, "mldb", { ["|5"] = 4, ["|8"] = { ["|14"] = { numButtons = 4, [1] = { text = "BiS" }, [2] = { text = "Upgrade", ["|18"] = true }, [4] = { text = "Offspec" } } }, ["|11"] = {}, ["|12"] = 90 })
rc(MASTER, "lootTable", lootTable(30001)); advance(0.1)
local set = rows[1].responses
check("R5", texts(set) == "BiS,Upgrade,RC_MINOR_UPGRADE,Offspec,Pass" and set[2].requireNotes == true and math.abs(rows[1].deadlineAt - (now + 90 - 0.1)) < 0.01, "master's custom buttons, inherited defaults: " .. texts(set))

reset()
rc(MASTER, "mldb", { ["|8"] = { ["|14"] = { numButtons = 3 }, TOKEN = { { text = "Tier" }, { text = "Off" } }, WEAPON = { { text = "Main" } } }, ["|11"] = {}, ["|12"] = 60 })
local lt = lootTable(30001, 30003, 30002)
lt[2].typeCode = "TOKEN"; lt[3].typeCode = "INVTYPE_WEAPON"
rc(MASTER, "lootTable", lt); advance(0.1)
check("R6", texts(rows[1].responses) == "Need,Greed,RC_MINOR_UPGRADE,Pass" and texts(rows[2].responses) == "Tier,Off,Pass" and texts(rows[3].responses) == "Main,Pass", "button groups per item type")

reset(); rc(MASTER, "lootTable", lootTable(30001)); advance(0.1)
check("R7", #rows == 0 and find("MLdb_request") and find("MLdb_request").target == MASTER .. "-SpineShatter", "items before settings: asks the master, by whisper")
rc(MASTER, "mldb", mldb(45)); advance(1)
check("R8", #rows == 1 and rows[1].deadlineAt ~= nil, "then shows them")

reset(); world.uncached["30001"] = true; rc(MASTER, "mldb", mldb()); rc(MASTER, "lootTable", lootTable(30001)); advance(1)
local waited = #rows == 0 and not find("lootAck")
world.uncached["30001"] = nil; advance(0.5)
check("R9", waited and #rows == 1 and find("lootAck"), "an item the client hasn't seen waits for its data")

reset(); start(30001); rc(MASTER, "lt_add", { [2] = { string = "30002:0:0", session = 2 } }); advance(0.1)
check("R10", #rows == 2, "lt_add adds to the session")
rc(MASTER, "lootTable", lootTable(30003)); advance(0.1)
check("R11", #rows == 1 and rows[1].idx == 1, "a new lootTable replaces it")

reset(); world.inInstance = false; rc(MASTER, "mldb", { ["|8"] = { ["|14"] = { numButtons = 3 } }, ["|13"] = true, ["|12"] = 60 }); rc(MASTER, "lootTable", lootTable(30001)); advance(0.1)
local notInRaid = find("response")
check("R12", #rows == 0 and notInRaid and notInRaid.data[2].response == "NOTINRAID", "master's out-of-raid rule answers for us")

-- What the master gets back -------------------------------------------------------------------------
reset(); start(30001, 30002)
local ack = find("lootAck")
local specID, ilvl, ackData = unpack(ack.data) -- exactly how RC reads it
check("A1", ack.distribution == "RAID" and specID == 0 and type(ilvl) == "number" and type(ackData) == "table", "lootAck survives RC's unpack: specID=" .. tostring(specID) .. " ilvl=" .. tostring(ilvl))
check("A2", ackData.gear1[1] == "29011:0:0" and ackData.gear2[1] == nil and ackData.diff[1] == 21, "gear is RC's clean item string, diff is against it: " .. tostring(ackData.gear1[1]) .. " +" .. tostring(ackData.diff[1]))
check("A3", type(ackData.response) == "table" and ackData.gear1[2] == "29000:0:0" and ackData.roll == nil, "every table RC indexes is there")

reset(); start(30003)
ackData = select(3, unpack(find("lootAck").data))
check("A4", type(ackData.gear1) == "table" and next(ackData.gear1) == nil and ackData.diff[1] == 0, "item without a slot: no gear, diff 0, like RC")

reset(); start(30001)
rows[1].respond(1, "need it")
local response = find("response")
local session, payload = unpack(response.data)
check("A5", response.distribution == "RAID" and session == 1 and payload.response == 1 and payload.note == "need it", "a vote is the button's number, to the group")
check("A6", #rows == 0, "the row goes away")
rc(MASTER, "lootAck", 0, 1, {}); check("A7", #findAll("response") == 1, "only one answer per item")

reset(); start(30001); rows[1].respond("PASS")
check("A8", find("response").data[2].response == "PASS", "Pass is RC's PASS")

reset()
rc(MASTER, "mldb", { ["|8"] = { ["|14"] = { numButtons = 1, [1] = { text = "BiS", ["|18"] = true } } }, ["|12"] = 60 })
rc(MASTER, "lootTable", lootTable(30001)); advance(0.1)
rows[1].respond(1)
local blocked = not find("response") and #rows == 1 and sawPrint("RC_NOTE_REQUIRED")
rows[1].respond("PASS")
check("A9", blocked and find("response").data[2].response == "PASS", "a required note blocks that button, but not Pass")

reset(); rc(MASTER, "mldb", mldb(30)); rc(MASTER, "lootTable", lootTable(30001, 30002)); advance(0.1)
rows[1].respond(2); advance(31)
local all = findAll("response")
check("A10", #all == 2 and all[2].data[1] == 2 and all[2].data[2].response == "TIMEOUT" and #rows == 0, "out of time sends RC's TIMEOUT, only for what's unanswered")
advance(5)
check("A11", #findAll("response") == 2, "and only once")

reset(); start(30001)
rc(MASTER, "playerInfoRequest"); advance(0.1)
local info = { unpack(find("pI").data) }
check("A12", #info == 6 and info[1] == "HEALER" and info[2] == "Raider" and info[3] == false and info[4] == 0 and info[6] == 0, "player info has no holes: " .. #info .. " fields")

-- Rolls ---------------------------------------------------------------------------------------------
local function rollTable(id) return { [1] = { string = id .. ":0:0", session = 1, isRoll = true } } end
reset(); start(30001); rows[1].respond(1)
rc(MASTER, "re_roll", { "6412-ABCDEF01" }, rollTable(30001)); advance(0.1)
check("X1", #rows == 1 and texts(rows[1].responses) == "Roll,Pass", "a roll request for us shows Roll and Pass")
check("X2", select(3, unpack(findAll("lootAck")[2].data)).roll[1] == "?", "acknowledged as a roll")
rows[1].respond("ROLL")
check("X3", world.rolls == 1 and #rows == 0, "Roll does a real /roll")
PLC.Events.Dispatch("CHAT_MSG_SYSTEM", "Someone rolls 99 (1-100)")
PLC.Events.Dispatch("CHAT_MSG_SYSTEM", ME .. " rolls 42 (1-50)")
local notYet = not find("roll")
PLC.Events.Dispatch("CHAT_MSG_SYSTEM", ME .. " rolls 42 (1-100)")
local name, roll, sessions = unpack(find("roll").data)
check("X4", notYet and name == ME .. "-SpineShatter" and roll == 42 and sessions[1] == 1, "only our own 1-100 roll is sent, under the name RC keys on")

reset(); start(30001); rc(MASTER, "re_roll", { "6412-99999999" }, rollTable(30002)); advance(0.1)
check("X5", #rows == 1 and rows[1].link:find("I30001", 1, true) ~= nil, "a roll request for others changes nothing")

reset(); start(30001); rows[1].respond(1); rc(MASTER, "re_roll", { "6412-ABCDEF01" }, rollTable(30001)); advance(0.1)
rows[1].respond("SKIP_ROLL")
local skip = { unpack(find("roll").data) }
check("X6", skip[2] == "-" and skip[3][1] == 1, "Pass on a roll sends RC's dash")

-- End of a session, and asking for one --------------------------------------------------------------
reset(); start(30001); rc("Stranger", "session_end"); advance(0.1)
local survived = #rows == 1
rc(MASTER, "session_end"); advance(0.1)
check("E1", survived and #rows == 0 and next(Bridge.items) == nil and sawPrint("RC_SESSION_ENDED"), "session_end only from the master")

reset(); Bridge:OnRosterRebuilt(); Bridge:OnRosterRebuilt()
local reconnects = findAll("reconnect")
check("E2", #reconnects == 1 and reconnects[1].target == MASTER and find("pI") ~= nil, "joining asks the master once")
world.masterRaidIndex = 3; Bridge:OnRosterRebuilt()
check("E3", #findAll("reconnect") == 2 and findAll("reconnect")[2].target == LEADER and Bridge.mldb == nil, "a new master gets asked, and old settings go")

reset(); start(30001); world.inGroup = false; Bridge:OnRosterRebuilt()
check("E4", #rows == 0 and next(Bridge.items) == nil and Bridge.mldb == nil, "leaving the group ends it")

reset(); world.lootMethod = 3; Bridge:OnRosterRebuilt()
check("E5", findAll("reconnect")[1].target == LEADER, "without Master Loot, RC's master is the leader")

-- Turned off ----------------------------------------------------------------------------------------
reset(); PLC.db.profile.rcBridge = false; start(30001); Bridge:OnRosterRebuilt()
check("O1", #rows == 0 and #sent == 0, "the option turns it all off")

reset(); world.rcRunning = true; Bridge.enabled = false
for _, fn in ipairs(enableCallbacks) do fn() end
check("O2", Bridge.enabled == false, "stays off with RC running here")

-- The Loot Response window --------------------------------------------------------------------------
local function buttons(row)
	local cell = columns[#columns].create(newStub())
	columns[#columns].update(cell, row)
	local shown = {}
	for _, group in pairs(cell.groups) do
		for key, button in pairs(group) do
			if button.shown then shown[#shown + 1] = button.caption end
		end
	end
	table.sort(shown)
	return table.concat(shown, ","), cell
end
reset()
rc(MASTER, "mldb", { ["|8"] = { ["|14"] = { numButtons = 3 }, TOKEN = { { text = "Tier" } } }, ["|12"] = 60 })
lt = lootTable(30001, 30003); lt[2].typeCode = "TOKEN"
rc(MASTER, "lootTable", lt); advance(0.1)
check("W1", buttons(rows[1]) == "Greed,Need,Pass,RC_MINOR_UPGRADE" and buttons(rows[2]) == "Pass,Tier", "each row shows its own buttons")
local builds = columnBuilds
rows[2].respond(1); advance(0.1)
check("W2", columnBuilds == builds, "answering one type doesn't rebuild the buttons")
rc(MASTER, "mldb", { ["|8"] = { ["|14"] = { numButtons = 3 }, TOKEN = { { text = "Tier" } } }, ["|12"] = 60 }); advance(0.1)
check("W3", columnBuilds == builds and buttons(rows[1]) == "Greed,Need,Pass,RC_MINOR_UPGRADE", "the same settings again keep the buttons working")
rc(MASTER, "mldb", { ["|8"] = { ["|14"] = { numButtons = 3, [1] = { text = "BiS" } }, TOKEN = { { text = "Tier" } } }, ["|12"] = 60 }); advance(0.1)
check("W4", columnBuilds == builds + 1 and buttons(rows[1]) == "BiS,Greed,Pass,RC_MINOR_UPGRADE", "changed settings rebuild them")
local _, cell = buttons(rows[1])
cell.noteBox.value = "typed"
for _, group in pairs(cell.groups) do
	for key, button in pairs(group) do
		if key == 1 and button.shown then button.scripts.OnClick() end
	end
end
check("W5", findAll("response")[2].data[2].note == "typed", "a button click sends the typed note")

reset()
PLC.Session.state, PLC.Session.owner = "active", { name = "Holder-SpineShatter" }
PLC.Session.items = { [1] = { link = "x", deadlineAt = now + 60 } }
PLC.Session.responses, PLC.Session.responseSet = {}, PLC.Responses:GetDefaults()
PLC.UI.LootFrame:Refresh()
local plcOnly = #rows == 1 and buttons(rows[1]) == "RESPONSE_BIS,RESPONSE_OS,RESPONSE_PASS,RESPONSE_PVP,RESPONSE_UPGRADE"
local mine
PLC.Session.SendMyResponse = function(_, idx, key) mine = { idx, key } end
start(30001)
check("W6", plcOnly and #rows == 2 and rows[1].id == "session1" and rows[2].id == "rc1", "this addon's session and an RC one share the window")
rows[1].respond("BIS")
check("W7", mine and mine[2] == "BIS" and #findAll("response") == 0, "a normal row still goes to Session")

-- History -------------------------------------------------------------------------------------------
local function entry(id) return { id = id, lootWon = "|cff|Hitem:30001:0:0|h[I30001]|h|r", date = "2026/11/02", time = "20:00:00", response = "Need", SR = { 1 } } end
local winner = "Winner-SpineShatter"
reset(); rc(MASTER, "history", winner, entry("1-0")); advance(0.1)
local stored = History:GetDB()[winner]
check("H1", stored and #stored == 1 and stored[1].SR == nil, "history from a master looter who isn't the leader is stored")
rc(MASTER, "history", winner, entry("1-0")); advance(0.1)
check("H2", #History:GetDB()[winner] == 1, "the same award isn't stored twice")
rc("Stranger", "history", winner, entry("2-0")); advance(0.1)
check("H3", #History:GetDB()[winner] == 1, "history from anyone else is ignored")
rcGuild("Stranger", "history", winner, entry("3-0")); advance(0.1)
check("H4", #History:GetDB()[winner] == 2, "unless it comes over guild chat, as RC allows")
rc(MASTER, "delete_history", "1-0"); advance(0.1)
check("H5", #History:GetDB()[winner] == 1 and History:GetDB()[winner][1].id == "3-0", "a deletion by the master follows")
reset(); PLC.db.profile.historyMirrorRC = false; rc(MASTER, "history", winner, entry("4-0")); advance(0.1)
check("H6", History:GetDB()[winner] == nil, "the mirror option still works")
reset(); world.lootMethod = 3; rc(LEADER, "history", winner, entry("5-0")); advance(0.1)
check("H7", #History:GetDB()[winner] == 1, "without Master Loot, the leader counts")
reset(); PLC.db.profile.rcBridge = false; rc(MASTER, "history", winner, entry("6-0")); advance(0.1)
check("H8", #History:GetDB()[winner] == 1, "history doesn't depend on the voting option")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
