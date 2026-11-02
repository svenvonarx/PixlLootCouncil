local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Addon-wide presence tracking, independent of any loot session -- lets UI/VotingFrame.lua tell
-- "has the addon, hasn't responded yet" apart from "no addon detected at all" for every roster
-- member, not just whoever's actually voted. Every client (not just the holder) broadcasts a
-- lightweight "presence" ping periodically; nothing here ever gates on being the master looter
-- or a session holder. The ping also carries the addon's version, which is what the Options ->
-- About page lists and what tells someone that a newer version is around (Data/UpdateNotice.lua).
-- The guild hears that version once, at login, so people find out before they're in a raid. Nobody
-- answers that one: a whole guild replying to every login isn't worth it.
local Presence = {}
PLC.Presence = Presence

local PRESENCE_TIMEOUT = 300 -- seconds; long enough to tolerate a missed broadcast or two
local CHECK_COOLDOWN = 10 -- a version check makes the whole group answer, so not more often than this
local ANSWER_COOLDOWN = 5
local MAX_VERSION_LENGTH = 32
local GUILD_DELAY = 10 -- like the login broadcast below, plus time for the guild channel to be up

Presence.lastSeen = {} -- [guid] = time()
Presence.versions = {} -- [guid] = version string, from anyone on a version that sends one
Presence.newest = nil -- the newest version seen in a group, if it's newer than ours

local lastCheck, lastAnswer

-- major, minor, patch and whether it's a final release, or nil for anything else ("v0.3.0-beta").
local function parseVersion(version)
	local major, minor, patch, rest = tostring(version):match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
	if not major then
		return nil
	end
	return tonumber(major), tonumber(minor), tonumber(patch), rest == ""
end

-- Is `a` newer than `b`? Something unparseable, like a development copy, is never either.
function Presence.IsNewer(a, b)
	local aMajor, aMinor, aPatch, aFinal = parseVersion(a)
	local bMajor, bMinor, bPatch, bFinal = parseVersion(b)
	if not aMajor or not bMajor then
		return false
	end
	if aMajor ~= bMajor then
		return aMajor > bMajor
	elseif aMinor ~= bMinor then
		return aMinor > bMinor
	elseif aPatch ~= bPatch then
		return aPatch > bPatch
	end
	return aFinal and not bFinal
end

-- A whole version ahead, not just a patch: 0.4.0 over 0.3.2.
function Presence.IsBigUpdate(a, b)
	local aMajor, aMinor = parseVersion(a)
	local bMajor, bMinor = parseVersion(b)
	if not aMajor or not bMajor then
		return false
	end
	return aMajor > bMajor or (aMajor == bMajor and aMinor > bMinor)
end

-- These come from other players and end up in chat, so only what a version really looks like.
local function isVersion(version)
	return type(version) == "string" and #version <= MAX_VERSION_LENGTH
		and version:match("^v?%d+%.%d+%.%d+[%w%.%-]*$") ~= nil
end

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
	self:RecordVersion(data.guid, data.version)
	self:notifyVotingFrame()
	self:notifyOptions()
end

function Presence:RecordVersion(guid, version)
	if not guid or not isVersion(version) then
		return
	end
	self.versions[guid] = version
	self:NoteVersion(version)
end

-- Anyone's version, in the group or not.
function Presence:NoteVersion(version)
	if not isVersion(version) then
		return
	end
	if version == self.newest then
		PLC.UpdateNotice:Remember(version)
	elseif self.IsNewer(version, self.newest or PLC.version) then
		self.newest = version
		PLC.UpdateNotice:Remember(version)
		PLC.UpdateNotice:Notify()
	end
end

function Presence:notifyOptions()
	if PLC.UI and PLC.UI.OptionsFrame and PLC.UI.OptionsFrame.OnVersionsUpdated then
		PLC.UI.OptionsFrame:OnVersionsUpdated()
	end
end

-- Without this, a response grid rendered before someone's presence ping actually arrived (e.g.
-- opened right as the addon loaded, before the 2s-delayed first broadcast) would show
-- "No addon detected" for them FOREVER -- nothing else ever re-reads Presence:IsPresent for an
-- already-rendered row. Only the currently-selected item needs a nudge; forces a full-rows
-- rebuild (cheap at normal roster sizes) so every row's presence check gets re-evaluated.
function Presence:notifyVotingFrame()
	local VotingFrame = PLC.UI and PLC.UI.VotingFrame
	local panel = VotingFrame and VotingFrame.activePanel
	if panel and panel.currentIdx then
		panel:OnItemUpdated(panel.currentIdx)
	end
end

local function broadcastPresence()
	local myGuid = UnitGUID("player")
	Presence:MarkSeen(myGuid)
	PLC.Comms.Sync:SendPresence(myGuid, PLC.version)
end

-- Asks everyone in the group for their version right now, instead of waiting for the next ping.
function Presence:CheckGroup()
	local now = GetTime()
	if lastCheck and now - lastCheck < CHECK_COOLDOWN then
		return
	end
	lastCheck = now
	PLC.Comms.Sync:SendVersionCheck()
end

function Presence:OnVersionCheckReceived()
	local now = GetTime()
	if lastAnswer and now - lastAnswer < ANSWER_COOLDOWN then
		return
	end
	lastAnswer = now
	broadcastPresence()
end

PLC:RegisterOnEnable(function()
	-- Mark self present immediately -- no reason to wait on the group channel just to know we're
	-- here ourselves. The actual broadcast (so OTHER clients learn about us) is delayed, matching
	-- Data/Session.lua's own RequestSync delay, so Data/Roster.lua and comms have a moment to be
	-- ready.
	Presence:MarkSeen(UnitGUID("player"))
	PLC:ScheduleTimer(broadcastPresence, 2)
	PLC:ScheduleRepeatingTimer(broadcastPresence, 120)
	PLC:ScheduleTimer(function()
		PLC.Comms.Sync:SendVersionToGuild(PLC.version)
	end, GUILD_DELAY)
end)
