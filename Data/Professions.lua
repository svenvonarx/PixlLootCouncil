local ADDON_NAME, PLC = ...

-- Self-reported professions, synced over the addon's own comms channel at session start --
-- same pattern as Data/Gear.lua (and the same reasoning: a client always has instant, perfect
-- access to its OWN professions, so there's no range/inspect problem to work around). This exists
-- for the Enchanter picker in UI/SessionFrame.lua to know who's actually trained in Enchanting --
-- filtering which ITEMS are even disenchant-eligible by known recipes is a later round, not this
-- one; this file only needs to answer "does this candidate have Enchanting at all."
local Professions = {}
PLC.Professions = Professions

-- The long-standing, locale-independent Blizzard skill line ID for Enchanting. Keyed by this
-- (not by GetProfessionInfo's localized `name` string) specifically so a German or French client
-- in the same raid is still recognized correctly -- a name-string key would silently never match
-- across locales.
Professions.ENCHANTING_SKILL_LINE = 333

Professions.known = {} -- [guid] = { [skillLine] = { name, skillLevel } }, in-memory only -- same
-- non-persistence as Data/Gear.lua's equipped table, repopulated by the next sync.

function Professions:HasProfession(guid, skillLine)
	local p = self.known[guid]
	return p ~= nil and p[skillLine] ~= nil
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

local function addProfession(known, index)
	if not index then
		return
	end
	-- GetProfessionInfo(index): name, icon, skillLevel, maxSkillLevel, numSpells, offset,
	-- skillLine, ... -- skillLine (7th return) is what gets keyed on; name is kept only for
	-- display (e.g. a future tooltip), never for matching.
	local name, _, skillLevel, _, _, _, skillLine = GetProfessionInfo(index)
	if skillLine then
		known[skillLine] = { name = name, skillLevel = skillLevel }
	end
end

-- Called whenever a session starts or a late joiner catches up (see Data/Session.lua), same three
-- trigger points Data/Gear.lua's BroadcastOwn already fires from -- never periodically, matching
-- the user's explicit "sync whenever the session is getting started" for gear, applied the same
-- way here.
function Professions:BroadcastOwn()
	-- GetProfessions() returns the two PRIMARY profession slot indices (plus archaeology/fishing/
	-- cooking/first aid, irrelevant here) -- not looped via ipairs({prof1, prof2}), since a table
	-- literal with a nil first element and a real second one creates a hole ipairs stops at,
	-- silently skipping prof2.
	local prof1, prof2 = GetProfessions()
	local known = {}
	addProfession(known, prof1)
	addProfession(known, prof2)

	local myGuid = UnitGUID("player")
	-- Cached locally too, not just sent -- so the broadcaster's own Enchanter-dropdown entry
	-- (green-highlighted when they have Enchanting) works immediately, without a round-trip.
	self.known[myGuid] = known
	PLC.Comms.Sync:SendProfessions(myGuid, known)
end
