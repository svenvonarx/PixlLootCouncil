-- Run from the addon folder: luajit tests/roster_test.lua
--
-- The real Data/Roster.lua: who's in the group, and who was. Votes and awards of someone who left
-- the group still need their name and class.
local out = print
_G.print = function() end
_G.time = function() return 1000 end
_G.GetRealmName = function() return "Realm" end
local units = {}
_G.IsInRaid = function() return true end
_G.GetNumGroupMembers = function() return #units end
_G.GetNumSubgroupMembers = function() return 0 end
local function unit(token) return units[tonumber(token:match("raid(%d+)") or 0)] end
_G.UnitExists = function(token) return unit(token) ~= nil end
_G.UnitGUID = function(token) return unit(token) and unit(token).guid end
_G.UnitName = function(token) return unit(token) and unit(token).name end
_G.UnitClass = function(token) return "Class", unit(token) and unit(token).class end
_G.UnitIsConnected = function() return true end
local gameKnows = {}
_G.GetPlayerInfoByGUID = function(guid)
	local info = gameKnows[guid]
	if info then return "Class", info.class, "Race", "RACE", 2, info.name, "" end
end

local PLC = { db = { profile = {} }, Session = { voters = {} } }
function PLC:RegisterOnEnable() end
function PLC:RegisterBucketEvent() end
PLC.CouncilRules = { Evaluate = function() return false end, RefreshGuildRoster = function() end }
assert(loadfile("Data/Roster.lua"))("PixlLootCouncil", PLC)
local Roster = PLC.Roster

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

units = { { guid = "G-ana", name = "Ana", class = "MAGE" }, { guid = "G-audio", name = "Audio", class = "PRIEST" } }
Roster:Rebuild()
check("R1", Roster:Get("G-audio").name == "Audio-Realm" and not Roster:GetKnown("G-audio").left, "someone in the group is known as they are")
units = { units[1] }
Roster:Rebuild()
local gone = Roster:GetKnown("G-audio")
check("R2", Roster:Get("G-audio") == nil, "(after leaving they're no longer in the group)")
check("R3", gone and gone.name == "Audio-Realm" and gone.class == "PRIEST" and gone.left == true, "but still known, as someone who left")

-- After a reload the group as it was is forgotten; the session remembers who answered.
Roster.known = {}
PLC.Session.voters["G-audio"] = { name = "Audio-Realm", class = "PRIEST" }
gone = Roster:GetKnown("G-audio")
check("R4", gone and gone.name == "Audio-Realm" and gone.left == true, "after a reload, from the session's own record of who answered")
PLC.Session.voters = {}
gameKnows["G-audio"] = { name = "Audio", class = "PRIEST" }
gone = Roster:GetKnown("G-audio")
check("R5", gone and gone.name == "Audio-Realm" and gone.class == "PRIEST", "or from what the game still knows of that player")
check("R6", Roster:GetKnown("G-nobody") == nil and Roster:GetKnown(nil) == nil, "someone never seen is unknown")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
