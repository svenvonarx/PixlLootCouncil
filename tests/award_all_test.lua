-- Run from the addon folder: luajit tests/award_all_test.lua
--
-- The real Comms/Sync.lua and Loot/Announce.lua: Award All's awards leave as one message instead of
-- a queue that the server's addon message limit (10 at once, then 1 a second per prefix) took over a
-- minute to send, and raid chat lines go out one a second instead of all at once.
local out = print
_G.print = function() end
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k)
	return k:find("^ANNOUNCE") and (k .. " %s %s") or k
end }) end } end
_G.IsInRaid = function() return true end
_G.IsInGroup = function() return true end

local timers = {}
local PLC = { Loot = {}, Comms = {}, db = { profile = { announce = { award = true } } } }
function PLC:ScheduleTimer(fn, delay) timers[#timers + 1] = { fn = fn, delay = delay } end
local wire = {}
local handlers = {}
PLC.Comms.Protocol = {
	Send = function(_, cmd, data, channel, _, _, onSent) wire[#wire + 1] = { cmd = cmd, data = data, channel = channel, onSent = onSent } end,
	RegisterHandler = function(_, cmd, fn) handlers[cmd] = fn end,
}
local holder = true
PLC.Session = { preview = false, IsHolder = function() return holder end }
local chat = {}
_G.ChatThrottleLib = { SendChatMessage = function(_, prio, prefix, text, channel) chat[#chat + 1] = { prio = prio, text = text, channel = channel } end }

assert(loadfile("Loot/Announce.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Comms/Sync.lua"))("PixlLootCouncil", PLC)
local Sync, Announce = PLC.Comms.Sync, PLC.Loot.Announce

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

-- One message ------------------------------------------------------------------------------------------
Sync:BeginBatch()
for idx = 1, 20 do
	Sync:SendAward("S1", idx, "Player-" .. idx, "award")
	Sync:SendHistory("Name" .. idx .. "-Realm", { id = "1-" .. idx })
end
check("A1", #wire == 0, "nothing leaves while Award All is still awarding")
local reached = false
Sync:FlushBatch("S1", function() reached = true end)
Sync:SendSessionEnd("S1")
check("A2", #wire == 2 and wire[1].cmd == "awards" and #wire[1].data.awards == 20 and #wire[1].data.history == 20,
	"then all 20 awards and their history go out in one message")
check("A3", wire[2].cmd == "session_end", "with the session's end right after it")
wire[1].onSent()
check("A3a", reached, "and the master looter hears once it has reached the raid")
Sync:SendAward("S1", 21, "Player-21", "award")
check("A4", wire[3] and wire[3].cmd == "award", "outside Award All, an award goes on its own as before")
wire = {}
Sync:BeginBatch()
Sync:FlushBatch("S1")
check("A5", #wire == 0, "an empty Award All sends nothing")

-- Receiving it -----------------------------------------------------------------------------------------
local awarded, stored = {}, {}
PLC.Session.OnAwardReceived = function(_, data) awarded[#awarded + 1] = data end
PLC.History = { OnHistoryReceived = function(_, data) stored[#stored + 1] = data end }
handlers.awards({ sessionId = "S1", awards = { { idx = 3, winnerGuid = "G3", reason = "bank" }, { idx = 4, winnerGuid = "G4" } },
	history = { { name = "A-Realm", entry = { id = "1-1" } } } })
check("R1", #awarded == 2 and awarded[1].sessionId == "S1" and awarded[1].idx == 3 and awarded[1].reason == "bank",
	"each award is applied like a single one, for its session")
check("R2", #stored == 1 and stored[1].name == "A-Realm", "and each history entry is stored")
handlers.awards({ sessionId = "S1", awards = "nonsense" })
handlers.awards("nonsense")
check("R3", #awarded == 2, "a malformed message is ignored")

-- Raid chat ----------------------------------------------------------------------------------------------
for i = 1, 3 do Announce:AnnounceAward({ link = "[Item " .. i .. "]", winnerName = "P" .. i, reason = "award" }) end
check("C1", #chat == 1 and chat[1].channel == "RAID", "the first line goes out right away")
check("C2", #timers == 1 and timers[1].delay >= 1, "the next one a second later")
local due = table.remove(timers, 1); due.fn()
check("C3", #chat == 2, "one at a time")
due = table.remove(timers, 1); due.fn()
due = table.remove(timers, 1); due.fn()
check("C4", #chat == 3 and #timers == 0, "until all are out, in order")
check("C5", chat[1].text:find("Item 1", 1, true) and chat[3].text:find("Item 3", 1, true), "each line is its own award, in order")
Announce:AnnounceAward({ link = "[Item 4]", winnerName = "P4", reason = "award" })
check("C6", #chat == 4, "a later line goes out right away again")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
