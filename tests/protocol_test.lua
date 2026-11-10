-- Run from the addon folder: luajit tests/protocol_test.lua
--
-- The real Comms/Protocol.lua with the real AceSerializer and LibDeflate: which prefix and priority
-- each message goes out on, and that the master looter can see what's still on its way.
local out = print
_G.print = function() end
_G.UnitName = function() return "Pixl" end
_G.GetRealmName = function() return "Realm" end
_G.strsplit = function(sep, s, n) local a, b = s:match("^(.-)" .. sep .. "(.*)$"); if a then return a, b end return s end
local function loadLua(path, ...) return assert(loadfile(path))(...) end
loadLua("Libs/LibStub/LibStub.lua")
loadLua("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
loadLua("Libs/LibDeflate/LibDeflate.lua")
LibStub:NewLibrary("AceLocale-3.0", 1).GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end

local PLC = { Comms = {} }
local onEnable, registered, sent = {}, {}, {}
function PLC:RegisterOnEnable(fn) onEnable[#onEnable + 1] = fn end
function PLC:RegisterComm(prefix, fn) registered[prefix] = fn end
function PLC:SendCommMessage(prefix, text, distribution, target, prio, callback)
	sent[#sent + 1] = { prefix = prefix, text = text, distribution = distribution, prio = prio, callback = callback }
end
loadLua("Comms/Protocol.lua", "PixlLootCouncil", PLC)
for _, fn in ipairs(onEnable) do fn() end
local Protocol = PLC.Comms.Protocol

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

-- Two queues ------------------------------------------------------------------------------------------------
-- The server allows each prefix 10 messages at once, then 1 a second. What the raid is waiting for
-- mustn't queue behind big data, as it did leaving BT for Gruul.
for _, cmd in ipairs({ "session_start", "item_add", "awards", "response", "session_heartbeat", "session_end", "version" }) do
	Protocol:Send(cmd, {}, "RAID")
end
local live = true
for _, message in ipairs(sent) do live = live and message.prefix == "PLC" and message.prio == "ALERT" end
check("Q1", live, "the session's own messages, and version checks, go on PLC, first in line")
sent = {}
for _, cmd in ipairs({ "session_sync_data", "history_share", "history", "gear", "profession" }) do
	Protocol:Send(cmd, {}, "RAID")
end
local bulk = true
for _, message in ipairs(sent) do bulk = bulk and message.prefix == "PLCB" and message.prio == "BULK" end
check("Q2", bulk, "catch-ups, shared history and gear go on PLCB, last in line")
check("Q3", registered.PLC and registered.PLCB, "and both are listened to")

-- Still on its way --------------------------------------------------------------------------------------------
local session, big = Protocol:Pending()
check("P1", session == 7 and big == 5, "everything handed over counts as on its way: " .. session .. ", " .. big)
local done = false
sent = {}
Protocol:Send("awards", {}, "RAID", nil, nil, function() done = true end)
sent[1].callback(nil, 100, 300)
check("P2", not done and select(1, Protocol:Pending()) == 8, "part of it out isn't all of it")
sent[1].callback(nil, 300, 300)
sent[1].callback(nil, 300, 300)
check("P3", done and select(1, Protocol:Pending()) == 7, "once it's all out it says so, once")

-- Receiving ------------------------------------------------------------------------------------------------------
local got = {}
Protocol:RegisterHandler("history_share", function(data, sender) got[#got + 1] = { data = data, sender = sender } end)
sent = {}
Protocol:Send("history_share", { n = 3 }, "GUILD")
registered.PLCB("PLCB", sent[1].text, "GUILD", "Brukt-Realm")
check("R1", got[1] and got[1].data.n == 3 and got[1].sender == "Brukt-Realm", "what comes in on either prefix is read the same way")
registered.PLCB("PLCB", sent[1].text, "GUILD", "Pixl")
check("R2", #got == 1, "and our own echo is ignored")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
