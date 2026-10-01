local ADDON_NAME, PLC = ...

-- Pure derivation of "is this roster entry on the council" -- never keeps a membership table of
-- its own. Roster:Rebuild() is the only writer of entry.council; this module only computes the
-- value. Keeping it this way is what makes Roster the single source of truth for council
-- membership (see docs/SPECIFICATION.md §3 principle 2 / §5.2).
local CouncilRules = {}
PLC.CouncilRules = CouncilRules

-- GetLootMethod() returns (method, partyMasterLooterID, raidMasterLooterID); indices are unit
-- numbers, not GUIDs, and both are 0 when the master looter is the player themself.
function CouncilRules:GetMasterLooterUnit()
	local method, partyID, raidID = GetLootMethod()
	if method ~= "master" then
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
