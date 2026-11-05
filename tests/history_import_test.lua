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

local PLC = { lootDB = { factionrealm = {} }, db = { profile = {} } }
function PLC:RegisterOnEnable() end
function PLC:RegisterSlashCommand() end
assert(loadfile("Data/History.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Data/HistoryImport.lua"))("PixlLootCouncil", PLC)
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

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
