-- Run from the addon folder: luajit tests/award_all_test.lua
--
-- The real Comms/Sync.lua and Loot/Announce.lua: Award All's awards leave as one small message
-- instead of a queue that the server's addon message limit (10 at once, then 1 a second per prefix)
-- took over a minute to send, their history follows on the bulk prefix, and raid chat gets one line.
local out = print
_G.print = function() end
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k)
	return k:find("^ANNOUNCE") and (k .. " %s") or k
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
check("A2", #wire == 3 and wire[1].cmd == "awards" and #wire[1].data.awards == 20 and wire[1].data.history == nil,
	"then all 20 awards go out in one small message, without the history's bulk")
check("A2a", wire[2].cmd == "history_share" and #wire[2].data.entries == 20 and wire[2].data.quiet == true,
	"the history entries follow, as the master looter's own awards, with no chat line for raiders")
check("A3", wire[3].cmd == "session_end", "and the session's end doesn't wait for the history")
wire[1].onSent()
check("A3a", not reached, "the awards being out isn't everything yet")
wire[2].onSent()
check("A3b", reached, "the master looter hears once the history has reached the raid too")
Sync:SendAward("S1", 21, "Player-21", "award")
check("A4", wire[4] and wire[4].cmd == "award", "outside Award All, an award goes on its own as before")
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
check("R2", #stored == 1 and stored[1].name == "A-Realm", "history in the same message, from a 0.8 or 0.9 master looter, is still stored")
local opened = 0
PLC.UI = { TradeFrame = { Open = function() opened = opened + 1 end } }
PLC.Session.sessionId = "S1"
handlers.awards({ sessionId = "S1", awards = { { idx = 5, winnerGuid = "G5" } } })
check("R2a", opened == 1, "Loot Trades opens for everyone, to show who got what")
handlers.awards({ sessionId = "S0", awards = { { idx = 5, winnerGuid = "G5" } } })
check("R2b", opened == 1, "not for another session's awards")
local before = #awarded
handlers.awards({ sessionId = "S1", awards = "nonsense" })
handlers.awards("nonsense")
check("R3", #awarded == before and opened == 1, "a malformed message is ignored")

-- Raid chat ----------------------------------------------------------------------------------------------
Announce:AnnounceAwards(40)
check("C0", #chat == 1 and chat[1].text:find("40", 1, true) ~= nil, "a whole Award All is one line in raid chat, not one per item")
while #timers > 0 do table.remove(timers, 1).fn() end -- the queue runs empty
for i = #chat, 1, -1 do chat[i] = nil end
PLC.db.profile.announce.sessionStart = true
for i = 1, 3 do Announce:AnnounceSessionStart({ i }) end
check("C1", #chat == 1 and chat[1].channel == "RAID", "the first line goes out right away")
check("C2", #timers == 1 and timers[1].delay >= 1, "the next one a second later")
local due = table.remove(timers, 1); due.fn()
check("C3", #chat == 2, "one at a time")
due = table.remove(timers, 1); due.fn()
due = table.remove(timers, 1); due.fn()
check("C4", #chat == 3 and #timers == 0, "until all are out, in order")
check("C5", chat[1].channel == "RAID" and chat[3].channel == "RAID", "each to the raid")
Announce:AnnounceAwards(2)
check("C6", #chat == 4, "a later line goes out right away again")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
