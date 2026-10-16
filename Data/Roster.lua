local ADDON_NAME, PLC = ...

-- SINGLE source of truth for who's in the group and who's council (see
-- docs/SPECIFICATION.md §3 principle 2). Rebuild() wholesale-replaces `members` -- nothing else
-- in the addon ever writes to this table, and no other module keeps its own parallel roster copy;
-- Data/Session.lua and every UI frame look players up here by GUID instead.
local Roster = {}
PLC.Roster = Roster

Roster.members = {} -- [guid] = entry

local function addUnit(members, unit, profile)
	if not UnitExists(unit) then
		return
	end
	local guid = UnitGUID(unit)
	if not guid then
		return
	end

	local name, realm = UnitName(unit)
	if not realm or realm == "" then
		realm = GetRealmName() or ""
	end

	local _, class = UnitClass(unit)
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
	if role == "NONE" then
		role = nil
	end

	local entry = {
		guid = guid,
		name = name .. "-" .. realm,
		class = class,
		role = role,
		online = UnitIsConnected(unit) and true or false,
		inGroup = true,
		updatedAt = time(),
	}
	entry.council = PLC.CouncilRules:Evaluate(entry, unit, profile)
	members[guid] = entry
end

function Roster:Rebuild()
	local profile = PLC.db.profile
	local members = {}

	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			addUnit(members, "raid" .. i, profile)
		end
	else
		addUnit(members, "player", profile)
		for i = 1, GetNumSubgroupMembers() do
			addUnit(members, "party" .. i, profile)
		end
	end

	self.members = members
end

function Roster:Get(guid)
	return self.members[guid]
end

-- Display-only helper -- entry.name itself always stays "Name-Realm" (addUnit above appends the
-- realm unconditionally, same-realm group or not, since it's used for wire/identity purposes
-- elsewhere), but showing the realm in the Loot Session window's candidate grid was pure clutter
-- for the overwhelmingly common same-realm-raid case. Matches up to the FIRST hyphen only --
-- player names can never contain one, but some realm names do (e.g. "Area-52").
function Roster:ShortName(fullName)
	return fullName and fullName:match("^[^-]+") or fullName
end

function Roster:GetCouncil()
	local council = {}
	for guid, entry in pairs(self.members) do
		if entry.council then
			council[guid] = entry
		end
	end
	return council
end

function Roster:IterateGroup()
	return pairs(self.members)
end

-- A raid-wide roster churn (wipe, boss kill, mass reconnect) fires GROUP_ROSTER_UPDATE many times
-- in the same frame; AceBucket coalesces that into a single rebuild instead of rebuilding N times.
function Roster:Enable()
	PLC:RegisterBucketEvent({ "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ENTERING_WORLD" }, 1, function()
		Roster:Rebuild()
	end)
	Roster:Rebuild()
end

PLC:RegisterOnEnable(function()
	Roster:Enable()
end)
