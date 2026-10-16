local ADDON_NAME, PLC = ...

-- Addon-wide presence tracking, independent of any loot session -- lets UI/VotingFrame.lua tell
-- "has the addon, hasn't responded yet" apart from "no addon detected at all" for every roster
-- member, not just whoever's actually voted. Every client (not just the holder) broadcasts a
-- lightweight "presence" ping periodically; nothing here ever gates on being the master looter
-- or a session holder.
local Presence = {}
PLC.Presence = Presence

local PRESENCE_TIMEOUT = 300 -- seconds; long enough to tolerate a missed broadcast or two

Presence.lastSeen = {} -- [guid] = time()

function Presence:MarkSeen(guid, ts)
	if not guid then
		return
	end
	self.lastSeen[guid] = ts or time()
end

function Presence:IsPresent(guid)
	local seen = self.lastSeen[guid]
	return seen ~= nil and (time() - seen) < PRESENCE_TIMEOUT
end

function Presence:OnPresenceReceived(data)
	self:MarkSeen(data.guid)
end

local function broadcastPresence()
	local myGuid = UnitGUID("player")
	Presence:MarkSeen(myGuid)
	PLC.Comms.Sync:SendPresence(myGuid)
end

PLC:RegisterOnEnable(function()
	-- Mark self present immediately -- no reason to wait on the group channel just to know we're
	-- here ourselves. The actual broadcast (so OTHER clients learn about us) is delayed, matching
	-- Data/Session.lua's own RequestSync delay, so Data/Roster.lua and comms have a moment to be
	-- ready.
	Presence:MarkSeen(UnitGUID("player"))
	PLC:ScheduleTimer(broadcastPresence, 2)
	PLC:ScheduleRepeatingTimer(broadcastPresence, 120)
end)
