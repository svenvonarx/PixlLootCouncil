local ADDON_NAME, PLC = ...

-- Pure derivation of "is this roster entry on the council" -- never keeps a membership table of
-- its own. Roster:Rebuild() is the only writer of entry.council; this module only computes the
-- value. Keeping it this way is what makes Roster the single source of truth for council
-- membership (see docs/SPECIFICATION.md §3 principle 2 / §5.2).
local CouncilRules = {}
PLC.CouncilRules = CouncilRules

-- The legacy global GetLootMethod() (method, partyMasterLooterID, raidMasterLooterID as a
-- string method) is nil on this client -- confirmed live via /plc errors
-- ("attempt to call a nil value" from this function). The modern C_PartyInfo.GetLootMethod()
-- namespace version returns the same shape but method as an Enum.LootMethod number (2 == Master
-- Looter) instead of the string "master". Tried first, with the legacy global kept as a
-- fallback in case some other client build has it the other way around. The single place this
-- distinction is handled -- Loot/Detection.lua's own group-loot-method check goes through
-- CouncilRules:IsMasterLootMethod() below instead of calling either API directly.
local function getLootMethod()
	if C_PartyInfo and C_PartyInfo.GetLootMethod then
		local method, partyID, raidID = C_PartyInfo.GetLootMethod()
		return method == 2, partyID, raidID -- Enum.LootMethod.Masterlooter
	elseif GetLootMethod then
		local method, partyID, raidID = GetLootMethod()
		return method == "master", partyID, raidID
	end
	return false
end

function CouncilRules:IsMasterLootMethod()
	return (getLootMethod())
end

-- Indices (partyID/raidID) are unit numbers, not GUIDs, and both are 0 when the master looter is
-- the player themself.
function CouncilRules:GetMasterLooterUnit()
	local isMaster, partyID, raidID = getLootMethod()
	if not isMaster then
		return nil
	end

	if raidID and raidID > 0 then
		return "raid" .. raidID
	elseif partyID and partyID > 0 then
		return "party" .. partyID
	end
	return "player"
end

function CouncilRules:IsMasterLooterUnit(unit)
	local mlUnit = self:GetMasterLooterUnit()
	return mlUnit ~= nil and UnitIsUnit(unit, mlUnit)
end

-- Shared by Loot/Detection.lua and Loot/Award.lua so "am I the live Blizzard master looter"
-- is computed in exactly one place.
function CouncilRules:AmIMasterLooter()
	return self:IsMasterLooterUnit("player")
end

-- entry: the roster entry being built (identity data only); unit: the live unit token it came
-- from (used for authority checks that need a fresh Blizzard query); profile: PLC.db.profile.
function CouncilRules:Evaluate(entry, unit, profile)
	local mode = profile.council.mode

	if mode == "manual" then
		return profile.council.manualList[entry.name] == true
	end

	local isML = self:IsMasterLooterUnit(unit)

	if mode == "mlOnly" then
		return isML
	end

	-- "raidAssist" (default): master looter, raid leader, and raid assistants are all council.
	if isML then
		return true
	end
	if UnitIsGroupLeader and UnitIsGroupLeader(unit) then
		return true
	end
	if UnitIsGroupAssistant and UnitIsGroupAssistant(unit) then
		return true
	end
	return false
end
