-- Run from the addon folder: luajit tests/history_import_test.lua
--
-- The real Data/History.lua and Data/HistoryImport.lua importing RCLootCouncil's loot history: what
-- comes over, what's skipped as already there, and that a big history doesn't freeze the game.
local out = print
_G.print = function() end
_G.strsplit = function(sep, s, n)
	local parts = {}
	for part in (s .. sep):gmatch("(.-)%" .. sep) do parts[#parts + 1] = part end
	if n and #parts > n then
		parts[n] = table.concat(parts, sep, n)
		for i = #parts, n + 1, -1 do parts[i] = nil end
	end
	return unpack(parts)
end
_G.strmatch = string.match
_G.GetRealmName = function() return "Realm" end
_G.UnitFactionGroup = function() return "Horde" end
_G.CopyTable = function(t)
	local function copy(x)
		if type(x) ~= "table" then return x end
		local r = {}
		for k, v in pairs(x) do r[k] = copy(v) end
		return r
	end
	return copy(t)
end
_G.StaticPopupDialogs = {}
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end

_G.strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.UnitName = function() return "Brukt" end
_G.IsInGuild = function() return true end
local now = os.time({ year = 2026, month = 11, day = 6, hour = 12 })
_G.time = function() return now end
_G.date = os.date
local printed = {}
_G.print = function(text) printed[#printed + 1] = tostring(text) end

local PLC = { lootDB = { factionrealm = {} }, db = { profile = { historyFilters = { class = {}, hiddenResponses = {} } } }, Loot = {}, Comms = {} }
function PLC:RegisterOnEnable() end
local slash = {}
function PLC:RegisterSlashCommand(name, _, fn) slash[name] = fn end
local sends = {}
PLC.Comms.Protocol = { Send = function(_, cmd, data, channel, target, prio, onSent)
	sends[#sends + 1] = { cmd = cmd, data = data, channel = channel, prio = prio, onSent = onSent }
end }
PLC.Loot.Announce = { GetChannel = function() return "RAID" end }
assert(loadfile("Data/History.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/HistoryImport.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/HistoryShare.lua"))("PixlLootCouncil", PLC)
local History = PLC.History

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function entry(id, extra)
	local e = { id = id, lootWon = "|Hitem:30001|h", date = "2024/01/01", time = "20:00:00" }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end
local function rc(data) _G.RCLootCouncilLootDB = { factionrealm = { ["Horde - Realm"] = data } } end

-- What comes over ------------------------------------------------------------------------------------
History:InsertEntry("Pixl-Realm", entry("1-1"))
rc({
	["Pixl-Realm"] = { entry("1-1"), entry("1-2", { SR = {}, sessionData = {} }), entry("1-2") },
	["Mule"] = { entry("2-1"), { id = "2-2" } },
	["Old-Realm"] = { entry(nil, { date = "05/03/21" }) },
})
local count = History:ImportFromLocalRC()
local db = History:GetDB()
check("I1", count == 3 and #db["Pixl-Realm"] == 2, "entries already stored, or twice in the import, come over once")
check("I2", db["Pixl-Realm"][2].SR == nil and db["Pixl-Realm"][2].sessionData == nil, "without RC's raw session data")
check("I3", #db["Mule-Realm"] == 1, "names get their realm, and entries that aren't awards are skipped")
check("I4", db["Old-Realm"][1].date == "2021/03/05" and db["Old-Realm"][1].id, "old dates are converted, and entries without an id get one")
check("I5", History:ImportFromLocalRC() == 0, "importing again adds nothing")
check("I6", RCLootCouncilLootDB.factionrealm["Horde - Realm"]["Pixl-Realm"][2].SR ~= nil, "and RC's own data isn't touched")
check("I7", History:InsertEntry("Pixl-Realm", entry("1-3")) and not History:InsertEntry("Pixl-Realm", entry("1-3")),
	"a single award (live mirroring) is still checked against what's stored")

-- A big history ---------------------------------------------------------------------------------------
-- Years of disenchants under one name: checking each entry against the whole list took minutes in game.
PLC.lootDB.factionrealm = {}
local big = {}
for i = 1, 40000 do big[i] = entry("1600000000-" .. i) end
rc({ ["Enchanter-Realm"] = big })
local started = os.clock()
count = History:ImportFromLocalRC()
local first = os.clock() - started
started = os.clock()
local again = History:ImportFromLocalRC()
local second = os.clock() - started
check("B1", count == 40000 and again == 0, "40,000 entries under one name all come over, once")
check("B2", first < 0.5 and second < 0.5, string.format("in a moment: %.2fs, and %.2fs to import again", first, second))

-- Sharing your own awards ----------------------------------------------------------------------------------
-- The master looter's awards that never reached everyone: they share them, and only they can.
PLC.lootDB.factionrealm = {}
local function award(id, day, owner, class) return entry(id, { date = day, owner = owner, class = class }) end
History:InsertEntry("Mash-Realm", award("9-1", "2026/11/05", "Brukt-Realm", "WARRIOR"))
History:InsertEntry("Yolo-Realm", award("9-2", "2026/11/05", "Brukt", "MAGE"))
History:InsertEntry("Yolo-Realm", award("9-3", "2026/10/01", "Brukt-Realm", "MAGE"))
History:InsertEntry("Yolo-Realm", award("9-4", "2026/11/05", "Someone-Realm", "MAGE"))
sends, printed = {}, {}
local shared = History:Share("2026/11/01")
check("S1", shared == 2, "only their own awards from that day on: not older ones, not someone else's")
check("S2", #sends == 2 and sends[1].channel == "GUILD" and sends[2].channel == "RAID" and sends[1].prio == "BULK",
	"to the guild and the group, behind any session messages")
check("S3", printed[1]:find("HISTORY_SHARE_SENDING", 1, true) and #printed == 1, "chat says it's sending")
sends[1].onSent(); check("S4", #printed == 1, "and only says it's done once both have gone")
sends[2].onSent(); check("S5", #printed == 2 and printed[2]:find("HISTORY_SHARE_DONE", 1, true), "then says so")

PLC.db.profile.historyFilters.class = { WARRIOR = true }
sends = {}
History:Share(nil, nil, History:GetFilteredDB(nil, nil))
check("S6", #sends == 2 and #sends[1].data.entries == 1 and sends[1].data.entries[1].entry.id == "9-1",
	"from what the window shows (the button): its filters count")
PLC.db.profile.historyFilters.class = {}

sends, printed = {}, {}
check("S7", History:Share("2027/01/01") == 0 and #sends == 0 and printed[1]:find("HISTORY_SHARE_NONE", 1, true), "nothing to share: nothing sent, and chat says so")

sends, printed = {}, {}
slash.share("")
check("C1", #sends == 2 and #sends[1].data.entries == 2, "/plc share: the last 7 days")
sends, printed = {}, {}
slash.share("2026/10/01")
check("C2", #sends[1].data.entries == 3, "/plc share 2026/10/01: from that day on")
sends, printed = {}, {}
slash.share("yesterday")
check("C3", #sends == 0 and printed[1]:find("HISTORY_SHARE_BAD_DATE", 1, true), "anything else explains the date")

-- Receiving them ------------------------------------------------------------------------------------------
PLC.lootDB.factionrealm = { ["Mash-Realm"] = { award("9-1", "2026/11/05", "Brukt-Realm") } }
printed = {}
History:OnHistoryShared({ entries = {
	{ name = "Mash-Realm", entry = award("9-1", "2026/11/05", "Brukt-Realm") },
	{ name = "Yolo-Realm", entry = award("9-2", "2026/11/05", "Brukt") },
	{ name = "Yolo-Realm", entry = award("9-5", "2026/11/05", "Mallory-Realm") },
	{ name = "Yolo", entry = award("9-6", "2026/11/05", "Brukt-Realm") },
} }, "Brukt")
local stored = History:GetDB()
check("R1", #stored["Mash-Realm"] == 1 and #stored["Yolo-Realm"] == 2, "what's new comes in, what's there already doesn't twice")
local ids = {}
for _, e in ipairs(stored["Yolo-Realm"]) do ids[e.id] = true end
check("R2", not ids["9-5"], "an award the sender didn't hand out is refused")
check("R3", ids["9-6"], "a name without its realm gets this realm, like the rest of the history")
check("R4", #printed == 1 and printed[1]:find("HISTORY_SHARE_RECEIVED", 1, true), "with one chat line")
printed = {}
History:OnHistoryShared({ entries = { { name = "Yolo-Realm", entry = award("9-2", "2026/11/05", "Brukt") } } }, "Brukt")
History:OnHistoryShared("nonsense", "Brukt")
History:OnHistoryShared({ entries = { "nonsense" } }, "Brukt")
check("R5", #printed == 0, "nothing new, or nonsense: nothing happens")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
