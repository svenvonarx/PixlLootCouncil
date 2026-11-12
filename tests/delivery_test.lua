-- Run from the addon folder: luajit tests/delivery_test.lua
--
-- A raid on a fake network: every client runs the real Data/Session.lua, Comms/Sync.lua,
-- Loot/Announce.lua and Core/Events.lua. Messages to someone on a loading screen are lost, as in
-- the game, and a test can lose any other message on purpose. The point: a loot session reaches
-- everyone and stays the same everywhere, wherever they are and whatever got lost on the way.
local out = print
_G.print = function() end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strsplit = function(sep, s) local a, b = s:match("^(.-)" .. sep .. "(.*)$"); if a then return a, b end return s end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.strlower = string.lower
_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
_G.UnitIsGroupLeader = function() return current.leader end
_G.IsInGroup = function(category) return current.inGroup and (category == nil or category == 1) end
_G.IsInRaid = function(category)
	if category == nil and current.inBattleground then return true end -- the active group is the battleground's
	return current.inGroup and (category == nil or category == 1)
end
_G.UnitGUID = function() return current.guid end
_G.IsPartyLFG = function() return current.inBattleground end
masterLooter = nil -- the client that's master looter, with Master Loot on; nil = another loot method
_G.UnitName = function(unit)
	if unit == "ml" then return masterLooter and masterLooter.name end
	return current.name
end
_G.GetRealmName = function() return "Realm" end
_G.C_ChatInfo = { SendChatMessage = function() end }
_G.C_Item = { GetItemInfo = function(link) return "Item", "|cff|H" .. tostring(link) .. "|h[Item]|h|r", 4, 100, nil, nil, nil, nil, "INVTYPE_HEAD", 1 end }
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end

-- Time and timers --------------------------------------------------------------------------------------
local now = 100000
_G.time = function() return math.floor(now) end
_G.GetTime = function() return now end
current = nil -- the client whose code is running
local clients = {}
local function as(client, fn, ...)
	local before = current
	current = client
	local result = fn(...)
	current = before
	return result
end

-- The network --------------------------------------------------------------------------------------------
local LATENCY = 0.3
local queue = {}
local sent = {} -- every message, for counting
local dropRule -- function(message, recipient) -> true to lose it
local sendSeconds = {} -- [cmd] = seconds a message takes to leave, as with the server's limit of 1 a second
local lateRule -- function(message, recipient) -> extra seconds before it arrives
local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in pairs(v) do c[deepcopy(k)] = deepcopy(x) end
	return c
end
local function send(from, cmd, data, distribution, target, onSent)
	local message = { from = from, cmd = cmd, data = deepcopy(data), distribution = distribution, target = target,
		at = now + LATENCY + (sendSeconds[cmd] or 0), onSent = onSent }
	sent[#sent + 1] = message
	queue[#queue + 1] = message
end
local function deliver(message)
	-- It has left the sender: what AceComm's callback reports.
	if message.onSent and not message.only then
		local onSent = message.onSent
		message.onSent = nil
		as(message.from, onSent)
	end
	for _, client in ipairs(clients) do
		local addressed = client ~= message.from and client.inGroup
			and ((message.distribution == "WHISPER" and client.name == message.target)
				or (message.distribution == "RAID" or message.distribution == "PARTY"))
			and (not message.only or message.only == client)
		local late = addressed and not message.only and lateRule and lateRule(message, client)
		if late then
			local copy = {}
			for k, v in pairs(message) do copy[k] = v end
			copy.only, copy.at = client, now + late
			queue[#queue + 1] = copy
		elseif addressed and not client.zoning and not (dropRule and dropRule(message, client)) then
			local handler = client.handlers[message.cmd]
			if handler then
				as(client, handler, deepcopy(message.data), message.from.name)
			end
		end
	end
end
local function count(cmd, from)
	local n = 0
	for _, m in ipairs(sent) do
		if m.cmd == cmd and (not from or m.from == from) then n = n + 1 end
	end
	return n
end

-- Runs the world for `seconds`, a tenth of a second at a time.
local function advance(seconds)
	local stop = now + seconds
	while now < stop do
		now = now + 0.1
		local due = {}
		for i = #queue, 1, -1 do
			if queue[i].at <= now then
				table.insert(due, 1, table.remove(queue, i))
			end
		end
		for _, message in ipairs(due) do deliver(message) end
		for _, client in ipairs(clients) do
			for _, timer in ipairs(client.timers) do
				if not timer.cancelled and timer.at <= now then
					if timer.every then timer.at = timer.at + timer.every else timer.cancelled = true end
					as(client, timer.fn)
				end
			end
		end
	end
end

-- A client --------------------------------------------------------------------------------------------
-- saved: what the character's saved data holds of an earlier session (db.char.activeSession).
local function newClient(name, guid, saved)
	local client = { name = name, guid = guid, inGroup = true, leader = false, handlers = {}, timers = {}, lootFrameShows = 0, synced = 0 }
	local PLC = { Loot = {}, UI = {}, Comms = {} }
	client.PLC = PLC
	local onEnable = {}
	function PLC:RegisterOnEnable(fn) onEnable[#onEnable + 1] = fn end
	function PLC:RegisterSlashCommand() end
	function PLC:RegisterEvent() end
	function PLC:ScheduleTimer(fn, delay)
		local timer = { fn = fn, at = now + delay }
		client.timers[#client.timers + 1] = timer
		return timer
	end
	function PLC:ScheduleRepeatingTimer(fn, every)
		local timer = { fn = fn, at = now + every, every = every }
		client.timers[#client.timers + 1] = timer
		return timer
	end
	function PLC:CancelTimer(timer) if timer then timer.cancelled = true end end
	local noop = function() end
	local quiet = setmetatable({}, { __index = function() return noop end })
	PLC.Comms.Protocol = {
		RegisterHandler = function(_, cmd, fn) client.handlers[cmd] = fn end,
		Send = function(_, cmd, data, distribution, target, _, onSent) send(client, cmd, data, distribution, target, onSent) end,
	}
	PLC.Roster = {
		Get = function(_, g) for _, c in ipairs(clients) do if c.guid == g then return { name = c.name .. "-Realm", class = "MAGE" } end end end,
		GetCouncil = function() return {} end,
		IterateGroup = function() return pairs({}) end,
		ShortName = function(_, n) return n end,
	}
	PLC.CouncilRules = setmetatable({
		IsMasterLootMethod = function() return masterLooter ~= nil end,
		GetMasterLooterUnit = function() return masterLooter and "ml" or nil end,
		AmIMasterLooter = function() return masterLooter == client end,
	}, { __index = function() return noop end })
	PLC.Preview = setmetatable({}, { __index = function() return noop end })
	PLC.Gear, PLC.Professions, PLC.History = quiet, quiet, quiet
	PLC.Loot.Detection, PLC.Loot.BagTracker = quiet, quiet
	PLC.UI.LootFrame = { Refresh = function() client.lootFrameShows = client.lootFrameShows + 1 end }
	PLC.UI.SessionFrame, PLC.UI.TradeFrame, PLC.UI.LootTimersFrame, PLC.UI.VotingFrame = quiet, quiet, quiet, quiet
	as(client, function()
		assert(loadfile("Core/Events.lua"))("PixlLootCouncil", PLC)
		assert(loadfile("Core/Defaults.lua"))("PixlLootCouncil", PLC)
		PLC.db = { profile = deepcopy(PLC.Defaults.profile), char = { activeSession = saved }, global = {} }
		assert(loadfile("Data/Responses.lua"))("PixlLootCouncil", PLC)
		assert(loadfile("Loot/Announce.lua"))("PixlLootCouncil", PLC)
		assert(loadfile("Data/Session.lua"))("PixlLootCouncil", PLC)
		assert(loadfile("Comms/Sync.lua"))("PixlLootCouncil", PLC)
		for _, fn in ipairs(onEnable) do fn() end
	end)
	local realPrint = _G.print
	client.Session = PLC.Session
	clients[#clients + 1] = client
	return client
end

local holder = newClient("Holder", "guid-holder")
holder.leader = true
local raiders = { newClient("Ana", "guid-ana"), newClient("Bo", "guid-bo"), newClient("Cy", "guid-cy"), newClient("Di", "guid-di") }
local ana, bo, cy, di = raiders[1], raiders[2], raiders[3], raiders[4]

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function itemCount(client)
	local n = 0
	for _ in pairs(client.Session.items) do n = n + 1 end
	return n
end
local function sentCount()
	local n = 0
	for _, item in pairs(holder.Session.items) do
		if item.sentIn == holder.Session.sessionId then n = n + 1 end
	end
	return n
end
local function hasSession(client)
	return client.Session.state == "active" and client.Session.sessionId == holder.Session.sessionId and itemCount(client) == sentCount()
end
local function everyone(test)
	for _, r in ipairs(raiders) do if not test(r) then return false end end
	return true
end
local function zone(client, seconds)
	client.zoning = true
	advance(seconds)
	client.zoning = false
	as(client, client.PLC.Events.Dispatch, "PLAYER_ENTERING_WORLD", false, false)
end
local function respond(client, idx, key)
	as(client, function() client.Session:SendMyResponse(idx, key, nil) end)
end
local function holderHas(client, idx)
	local byGuid = holder.Session.responses[idx]
	return byGuid ~= nil and byGuid[client.guid] ~= nil
end
local function startSession(items)
	as(holder, function()
		local wire = {}
		for idx = 1, items do wire[idx] = { idx = idx, itemString = "item:" .. (1000 + idx), quality = 4 } end
		holder.Session:ApplyItems(wire)
		holder.Session.nextIdx = items + 1
		holder.Session:Start()
	end)
end
local function endSession()
	as(holder, function() holder.Session:End() end)
end
local function reset()
	if holder.Session.state == "active" then endSession() end
	advance(1)
	dropRule, lateRule = nil, nil
	for _, c in ipairs(clients) do c.zoning = false; c.Session.items = {} end
	holder.Session.items = {}
	advance(20)
	for k in pairs(sent) do sent[k] = nil end
end

-- Normal start -------------------------------------------------------------------------------------------
-- The holder still has an item awarded in an earlier pass, waiting to be traded. It isn't part of
-- this one, and must not make everyone look out of step.
holder.Session.items[99] = { idx = 99, itemString = "item:999", awarded = ana.guid, awardReason = "award" }
startSession(3)
holder.Session.items[99] = holder.Session.items[99] -- (kept)
advance(1)
check("D1", everyone(hasSession) and everyone(function(r) return r.lootFrameShows > 0 end), "everyone gets the session and its popup")

advance(120)
check("D2", count("session_sync_request") == 0 and count("responses") == 0 and count("session_heartbeat", holder) >= 11, "a quiet session stays quiet: two minutes of heartbeats, no catch-up chatter")

-- On a loading screen when the session starts: the reason RCLootCouncil sessions went missing --------------
reset()
ana.zoning = true
startSession(3)
advance(10.5) -- the start, and the first heartbeat, happen during the loading screen
check("D3", not hasSession(ana), "(on a loading screen, the start never arrives)")
local showsBefore = ana.lootFrameShows
ana.zoning = false
as(ana, ana.PLC.Events.Dispatch, "PLAYER_ENTERING_WORLD", false, false)
advance(6) -- the next heartbeat is still almost 4 seconds away
check("D4", hasSession(ana) and ana.lootFrameShows > showsBefore, "back from the loading screen, the session and its popup arrive within seconds")
check("D5", count("session_sync_request", ana) == 1, "with one ask")

reset()
bo.zoning = true
startSession(2)
advance(2)
bo.zoning = false -- and somehow no loading-screen event: a message lost for any reason
advance(11)
check("D6", hasSession(bo), "even without one, the next heartbeat brings it, as the session is unknown")

-- Something lost mid-session -------------------------------------------------------------------------------
reset()
startSession(2)
advance(1)
dropRule = function(m, to) return to == cy and m.cmd == "item_add" end
as(holder, function()
	holder.Session:ApplyItems({ [3] = { idx = 3, itemString = "item:1003", quality = 4 } })
	holder.Session.nextIdx = 4
	holder.Session:broadcastNewItems({ [3] = holder.Session.items[3] })
end)
advance(1)
dropRule = nil
check("D7", itemCount(cy) == 2 and itemCount(ana) == 3, "(an added item didn't reach Cy)")
advance(25)
check("D8", hasSession(cy) and cy.Session.items[3] ~= nil, "two heartbeats later, Cy has it")

dropRule = function(m, to) return to == di and m.cmd == "stage" end
as(holder, function() holder.Session:SetPreAward(1, ana.guid, "award") end)
advance(1)
dropRule = nil
advance(25)
check("D9", di.Session.items[1].preAwardGuid == ana.guid, "a staged pick that got lost arrives too")

-- The holder on a loading screen while people answer --------------------------------------------------------
reset()
startSession(2)
advance(1)
holder.zoning = true
respond(ana, 1, "BIS")
respond(ana, 2, "OS")
advance(3)
holder.zoning = false
as(holder, holder.PLC.Events.Dispatch, "PLAYER_ENTERING_WORLD", false, false)
check("D10", not holderHas(ana, 1), "(the holder was zoning and missed Ana's answers)")
advance(25)
check("D11", holderHas(ana, 1) and holderHas(ana, 2) and holder.Session.responses[2][ana.guid].response == "OS", "Ana sends them again by herself, once the holder's heartbeats show they're missing")
check("D12", count("responses", ana) == 1, "once")
check("D13", bo.Session.responses[1] and bo.Session.responses[1][ana.guid] ~= nil, "and everyone else who missed nothing still has them")

-- Races don't cause chatter ---------------------------------------------------------------------------------
reset()
startSession(3)
-- Each heartbeat crosses two answers: one that reaches the holder just after it, so the heartbeat
-- shows the holder missing it, and one the holder has but Di gets late, so it shows Di behind.
lateRule = function(m, to) return m.cmd == "response" and to == di and 0.8 or nil end
advance(9.5)
for i = 1, 6 do
	respond(raiders[(i - 1) % 3 + 1], (i - 1) % 3 + 1, "UPGRADE")
	advance(0.35)
	respond(raiders[i % 3 + 1], (i - 1) % 3 + 1, "OS")
	advance(9.65)
end
advance(30)
check("D14", count("session_sync_request") == 0 and count("responses") == 0, "answers crossing a heartbeat don't make anyone catch up or resend")

-- Someone else's answer that never reached a council member
reset()
startSession(2)
advance(1)
dropRule = function(m, to) return to == bo and m.cmd == "response" and m.from == ana end
respond(ana, 2, "BIS")
advance(1)
dropRule = nil
check("D26", not (bo.Session.responses[2] and bo.Session.responses[2][ana.guid]), "(Ana's answer never reached Bo)")
advance(25)
check("D27", bo.Session.responses[2] and bo.Session.responses[2][ana.guid] ~= nil, "the holder's heartbeats show Bo is behind, so Bo catches up and sees it")

-- An item list still arriving in pieces when a heartbeat overtakes it
reset()
startSession(1)
lateRule = function(m, to) return m.cmd == "item_add" and to == cy and 1.0 or nil end
advance(9.7)
for k in pairs(sent) do sent[k] = nil end
as(holder, function()
	holder.Session:ApplyItems({ [2] = { idx = 2, itemString = "item:1002", quality = 4 } })
	holder.Session.nextIdx = 3
	holder.Session:broadcastNewItems({ [2] = holder.Session.items[2] })
end)
advance(25)
check("D29", hasSession(cy) and count("session_sync_request") == 0, "a heartbeat overtaking a slow item list doesn't make Cy catch up for nothing")

-- Asking is limited
reset()
startSession(1)
advance(1)
for k in pairs(sent) do sent[k] = nil end
zone(ana, 1)
advance(4)
zone(ana, 1)
advance(4)
check("D28", count("session_sync_request", ana) == 1, "two loading screens close together ask once")

-- Everyone zones out together ------------------------------------------------------------------------------
reset()
for _, r in ipairs({ ana, bo, cy }) do r.zoning = true end
startSession(4)
advance(6)
for _, r in ipairs({ ana, bo, cy }) do
	r.zoning = false
	as(r, r.PLC.Events.Dispatch, "PLAYER_ENTERING_WORLD", false, false)
end
local diAppliedBefore = di.lootFrameShows
advance(8)
check("D15", hasSession(ana) and hasSession(bo) and hasSession(cy), "three people back from loading screens at once all catch up")
local groupAnswers, whispers = 0, 0
for _, m in ipairs(sent) do
	if m.cmd == "session_sync_data" then
		if m.distribution == "WHISPER" then whispers = whispers + 1 else groupAnswers = groupAnswers + 1 end
	end
end
check("D16", groupAnswers == 1 and whispers == 0, "from one answer to the group, not one each (" .. groupAnswers .. " group, " .. whispers .. " whispers)")
check("D17", di.lootFrameShows == diAppliedBefore, "Di, who missed nothing, ignores it")

-- An answer and a catch-up crossing ---------------------------------------------------------------------------
reset()
startSession(2)
advance(1)
dropRule = function(m, to) return to == holder and m.cmd == "response" and m.from == bo end
respond(bo, 1, "BIS")
advance(1)
dropRule = nil
zone(bo, 4)
advance(6)
check("D18", bo.Session.responses[1] and bo.Session.responses[1][bo.guid] and bo.Session.responses[1][bo.guid].response == "BIS", "a catch-up from a holder that lacks Bo's answer doesn't erase it on Bo's side")
check("D19", holderHas(bo, 1), "and Bo sends it again with it")

-- The end that never arrived ---------------------------------------------------------------------------------
reset()
startSession(2)
advance(1)
dropRule = function(m, to) return to == cy and m.cmd == "session_end" end
endSession()
advance(1)
dropRule = nil
check("D20", cy.Session.state == "active", "(Cy missed the end)")
advance(45)
check("D21", cy.Session.state == "ended", "the heartbeats stopping makes Cy ask, and the holder says it ended")

-- Older holders and the right channel --------------------------------------------------------------------------
reset()
startSession(1)
advance(1)
for k in pairs(sent) do sent[k] = nil end
as(ana, function() ana.Session.items[9] = { idx = 9 } end) -- out of step, but the holder can't say
as(ana, ana.handlers.session_heartbeat, { sessionId = holder.Session.sessionId, ts = time() })
as(ana, ana.handlers.session_heartbeat, { sessionId = holder.Session.sessionId, ts = time() })
check("D22", count("session_sync_request") == 0, "a heartbeat from an older holder, with nothing to compare, changes nothing")
ana.Session.items[9] = nil

ana.inBattleground = true
check("D23", as(ana, ana.PLC.Loot.Announce.GetChannel, ana.PLC.Loot.Announce) == "RAID", "from inside a battleground, messages still go to the raid")
ana.inBattleground = false

-- Awards survive catching up ---------------------------------------------------------------------------------
reset()
startSession(2)
advance(1)
as(holder, function()
	holder.Session:SetPreAward(1, di.guid, "award")
	holder.Session.items[1].awarded, holder.Session.items[1].awardReason = di.guid, "award"
	holder.Session.items[1].preAwardGuid = nil
end)
zone(di, 3)
advance(6)
check("D24", di.Session.items[1] and di.Session.items[1].awarded == di.guid, "an award made earlier comes with the catch-up, so Di's item to collect stays")

-- Leaving BT for Gruul ---------------------------------------------------------------------------------------
-- Everyone's loading screen ends at a different moment, and a whole session takes a while to send at
-- the server's 1 message a second. One answer each queued minutes of them, in front of everything.
reset()
for _, r in ipairs(raiders) do r.zoning = true end
startSession(4)
advance(3)
sendSeconds.session_sync_data = 15
for i, r in ipairs(raiders) do
	r.zoning = false
	as(r, r.PLC.Events.Dispatch, "PLAYER_ENTERING_WORLD", false, false)
	advance(3) -- the next one's loading screen ends a little later
end
advance(60)
check("D30", everyone(hasSession), "everyone back from the loading screen one by one catches up")
check("D31", count("session_sync_data") <= 2, "with at most two answers, not one each: " .. count("session_sync_data"))
sendSeconds.session_sync_data = nil

-- Item numbers used again ------------------------------------------------------------------------------------
-- Raiders keep a pass's awarded items, to look back at. The next pass can use the same numbers, from
-- another master looter or one whose list was cleared: its items are new ones, not awarded.
local function award(idx, winner)
	as(holder, function() holder.Session:SetPreAward(idx, winner.guid, "award") end)
end
local function awardAll()
	as(holder, function() holder.Session:AwardAllPreAwarded() end)
end
reset()
startSession(2)
advance(2)
award(1, ana); award(2, bo); awardAll()
advance(3)
check("N1", ana.Session.items[1] and ana.Session.items[1].awarded == ana.guid and ana.Session.state == "ended",
	"(a pass is awarded and over; raiders keep its items, with who got them)")
as(holder, function()
	holder.Session.items, holder.Session.nextIdx = {}, 1
	holder.Session:ApplyItems({ [1] = { idx = 1, itemString = "item:2001", quality = 4 }, [2] = { idx = 2, itemString = "item:2002", quality = 4 } })
	holder.Session.nextIdx = 3
	holder.Session:Start()
end)
advance(2)
check("N2", everyone(function(r) return r.Session.items[1].itemString == "item:2001" and not r.Session.items[1].awarded end),
	"the next pass's items with the same numbers are new ones, not awarded already")
for k in pairs(sent) do sent[k] = nil end
advance(60)
check("N3", count("session_sync_request") == 0, "and nobody keeps asking to catch up")

-- Dropped twice ------------------------------------------------------------------------------------------------
-- Raiders answer once for both copies; the master looter gives them to two different people.
reset()
as(holder, function()
	holder.Session:ApplyItems({ [1] = { idx = 1, itemString = "item:31099", quality = 4 }, [2] = { idx = 2, itemString = "item:31099", quality = 4 } })
	holder.Session.nextIdx = 3
	holder.Session:Start()
end)
advance(2)
for k in pairs(sent) do sent[k] = nil end
as(ana, function() ana.Session:SendMyResponses({ [1] = { response = "BIS" }, [2] = { response = "BIS" } }) end)
as(bo, function() bo.Session:SendMyResponses({ [1] = { response = "OS", note = "pvp" }, [2] = { response = "OS", note = "pvp" } }) end)
advance(2)
check("T1", holderHas(ana, 1) and holderHas(ana, 2) and holderHas(bo, 2) and count("responses", ana) == 1 and count("response", ana) == 0,
	"one answer for an item that dropped twice counts for both copies, in one message")
check("T2", cy.Session.responses[2][bo.guid].note == "pvp", "and everyone on the council sees it on each copy, note included")
award(1, ana); award(2, bo); awardAll()
advance(3)
check("T3", everyone(function(r) return r.Session.items[1].awarded == ana.guid and r.Session.items[2].awarded == bo.guid end),
	"the two copies go to two different people, and everyone sees who got which")
check("T4", di.Session.items[2].votes and di.Session.items[2].votes[bo.guid].response == "OS",
	"with the votes kept on each, to look back at who else wanted it")

-- Someone else's old session ------------------------------------------------------------------------------------
-- A character whose own pass was left running resumes it at login. With a master looter in the
-- raid, nobody follows it, and it ends once that character sees who the master looter is.
reset()
masterLooter = holder
startSession(3)
advance(3)
masterLooter = bo -- (so Bo's client lets it start: the pass it "resumed")
as(bo, function()
	bo.Session.state = "inactive"
	bo.Session:ApplyItems({ [1] = { idx = 1, itemString = "item:9001", quality = 4 } })
	bo.Session.nextIdx = 2
	bo.Session:Start()
end)
masterLooter = holder
for k in pairs(sent) do sent[k] = nil end
advance(60)
local others = { ana, cy, di }
local stayed = true
for _, r in ipairs(others) do stayed = stayed and hasSession(r) end
check("O1", stayed, "nobody leaves the master looter's session for someone else's")
check("O2", count("session_sync_data") == 0, "and no whole sessions get sent back and forth: " .. count("session_sync_data"))
as(bo, function() bo.Session:End() end)

local old = newClient("Old", "guid-old", {
	sessionId = "guid-old-1", state = "active", owner = { guid = "guid-old", name = "Old" }, nextIdx = 2,
	items = { [1] = { idx = 1, itemString = "item:7001", sentIn = "guid-old-1" } }, lastHolderSeenAt = now - 600,
})
check("O3", as(old, function() return old.Session:IsHolder() end), "(a pass from ten minutes ago is resumed at login: a reload mid-raid)")
as(old, function() old.Session:OnRosterRebuilt() end)
check("O4", old.Session.state == "ended", "in a raid whose master looter is someone else, it ends")
old.inGroup = false
local ancient = newClient("Ancient", "guid-ancient", {
	sessionId = "guid-ancient-1", state = "active", owner = { guid = "guid-ancient", name = "Ancient" }, nextIdx = 2,
	items = { [1] = { idx = 1, itemString = "item:7002", sentIn = "guid-ancient-1" } }, lastHolderSeenAt = now - 8 * 3600,
})
check("O5", ancient.Session.state == "ended" and ancient.Session.items[1] ~= nil, "a pass left running hours ago isn't resumed at all; its items stay")
ancient.inGroup = false
masterLooter = nil

-- What it costs ------------------------------------------------------------------------------------------------
check("D25", holder.PLC.db.profile.sessionHeartbeatSeconds == 10, "heartbeats every 10 seconds by default, so a repair takes about 20")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
