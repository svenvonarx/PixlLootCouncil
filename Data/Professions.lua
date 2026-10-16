local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Self-reported professions, synced over the addon's own comms channel at session start --
-- same pattern as Data/Gear.lua (and the same reasoning: a client always has instant, perfect
-- access to its OWN professions, so there's no range/inspect problem to work around). This exists
-- for the Enchanter picker in UI/SessionFrame.lua to know who's actually trained in Enchanting --
-- filtering which ITEMS are even disenchant-eligible by known recipes is a later round, not this
-- one; this file only needs to answer "does this candidate have Enchanting at all."
local Professions = {}
PLC.Professions = Professions

-- GetProfessions()/GetProfessionInfo() -- this file's first implementation -- turned out to be
-- Cataclysm+/retail-only: confirmed empirically via /plc profdebug on a live TBC Anniversary
-- client, where GetProfessions() returned nil for every single slot (not just the primaries, ALL
-- SIX, for two different characters known to have real trained professions) -- not a sync/timing
-- bug at all, the API itself doesn't function here. The actually-available Classic/TBC Classic
-- API is the older GetNumSkillLines()/GetSkillLineInfo() pair (confirmed via Warcraft Wiki's own
-- version history: "Burning Crusade Classic: Available"), which only ever returns the LOCALIZED
-- skill name -- no numeric skill line ID the way the retail API has one. Locale independence is
-- preserved a different way instead of giving up on it: match against THIS addon's own
-- L["PROFESSION_ENCHANTING"] (translatable per-locale like every other user-facing string here),
-- not a hardcoded English literal -- and key/broadcast by a fixed internal string (ENCHANTING_KEY
-- below), never by the localized name itself, so a receiving client in a different locale still
-- matches correctly without needing to translate anything on its own end. The one real limitation
-- versus the original numeric-ID plan: this only works correctly for a locale that actually has
-- PROFESSION_ENCHANTING translated -- AceLocale silently falls back to the enUS "Enchanting" for
-- any locale that doesn't, which would then never match that locale's own localized skill name.
Professions.ENCHANTING_KEY = "ENCHANTING"

Professions.known = {} -- [guid] = { [ENCHANTING_KEY] = { name, skillLevel } }, in-memory only --
-- same non-persistence as Data/Gear.lua's equipped table, repopulated by the next sync.

function Professions:HasProfession(guid, key)
	local p = self.known[guid]
	return p ~= nil and p[key] ~= nil
end

-- Mirrors Data/Gear.lua's notifyVotingFrame, but this data feeds UI/SessionFrame.lua's Enchanter
-- dropdown, not the candidate grid -- OnSessionUpdated is the existing "re-run refresh() if the
-- window is open" entry point (also used by Data/Session.lua), so no new forward-hook is needed.
function Professions:notifySessionFrame()
	local SessionFrame = PLC.UI and PLC.UI.SessionFrame
	if SessionFrame and SessionFrame.OnSessionUpdated then
		SessionFrame:OnSessionUpdated()
	end
end

function Professions:OnProfessionReceived(data)
	if not data.guid or not data.known then
		return
	end
	self.known[data.guid] = data.known
	self:notifySessionFrame()
end

-- Called whenever a session starts or a late joiner catches up (see Data/Session.lua), same three
-- trigger points Data/Gear.lua's BroadcastOwn already fires from -- never periodically, matching
-- the user's explicit "sync whenever the session is getting started" for gear, applied the same
-- way here.
function Professions:BroadcastOwn()
	local known = {}
	-- GetNumSkillLines()/GetSkillLineInfo(index) walk EVERY skill line shown in the classic skill
	-- window (professions, weapon skills, languages, headers, the lot) -- isHeader (2nd return)
	-- excludes section headers, skillRank (4th return) > 0 excludes a header's own contained
	-- skills that haven't actually been learned (shouldn't normally appear at all, but a 0-or-nil
	-- rank is excluded defensively rather than trusted to never happen).
	for i = 1, GetNumSkillLines() do
		local skillName, isHeader, _, skillRank = GetSkillLineInfo(i)
		if not isHeader and skillRank and skillRank > 0 and skillName == L["PROFESSION_ENCHANTING"] then
			known[Professions.ENCHANTING_KEY] = { name = skillName, skillLevel = skillRank }
		end
	end

	local myGuid = UnitGUID("player")
	-- Cached locally too, not just sent -- so the broadcaster's own Enchanter-dropdown entry
	-- (green-highlighted when they have Enchanting) works immediately, without a round-trip.
	self.known[myGuid] = known
	PLC.Comms.Sync:SendProfessions(myGuid, known)
end

-- GetSkillLineInfo can plausibly hit the same "not cached yet right after login/reload" race the
-- old GetProfessionInfo-based implementation did (unconfirmed for this specific API, but the
-- underlying client-side skill data is the same system either way) -- SKILLLINES_CHANGED is the
-- actual completion signal for that regardless of which API reads it afterward, so re-broadcasting
-- whenever it fires stays worth keeping as a self-correcting safety net. Bucketed (same pattern as
-- Data/Roster.lua's GROUP_ROSTER_UPDATE) since multiple skill lines can change in the same burst.
PLC:RegisterOnEnable(function()
	PLC:RegisterBucketEvent({ "SKILLLINES_CHANGED" }, 1, function()
		Professions:BroadcastOwn()
	end)
end)

-- Raw API dump (debug) -- walks every skill line this client sees and prints it unfiltered, so a
-- future "X isn't being detected" report can be read directly (is the skill even in this list?
-- what's its exact name/rank/header-ness?) instead of guessed at again.
PLC:RegisterSlashCommand("profdebug", "Raw GetNumSkillLines()/GetSkillLineInfo() dump (debug)", function()
	local count = GetNumSkillLines()
	print(L["CHAT_PREFIX"] .. string.format("GetNumSkillLines() -> %d", count))
	for i = 1, count do
		local skillName, isHeader, isExpanded, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
		print(L["CHAT_PREFIX"] .. string.format("[%d] %s | header=%s | rank=%s/%s",
			i, tostring(skillName), tostring(isHeader), tostring(skillRank), tostring(skillMaxRank)))
	end
	print(L["CHAT_PREFIX"] .. string.format("Matching against L[\"PROFESSION_ENCHANTING\"] = %s", tostring(L["PROFESSION_ENCHANTING"])))
end)

-- Debug visibility into what's actually been synced -- profession sync has no periodic
-- re-broadcast (same limitation Data/Gear.lua already has), so a client that joined/reloaded
-- after someone else's one-shot broadcast simply never gets their data until the next
-- Start()/session-start/sync. This dumps exactly what THIS client currently believes, so a "wrong
-- Enchanter default" report can be told apart from "the sync packet just never arrived here."
PLC:RegisterSlashCommand("professions", "Dump synced profession data (debug)", function()
	local count = 0
	for guid, known in pairs(Professions.known) do
		count = count + 1
		local entry = PLC.Roster:Get(guid)
		local name = entry and PLC.Roster:ShortName(entry.name) or guid
		local parts = {}
		for key, info in pairs(known) do
			table.insert(parts, string.format("%s (%d, key %s)", info.name or "?", info.skillLevel or 0, key))
		end
		local summary = #parts > 0 and table.concat(parts, ", ") or L["PROFESSIONS_NONE"]
		print(L["CHAT_PREFIX"] .. string.format(L["PROFESSIONS_ENTRY"], name, summary))
	end
	if count == 0 then
		print(L["CHAT_PREFIX"] .. L["PROFESSIONS_EMPTY"])
	end
end)
