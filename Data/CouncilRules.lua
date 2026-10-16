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

-- Guild rank of a group member: GetGuildInfo(unit) when the client has it (same guild, nearby),
-- else the guild roster by name. Returns guildName, rankIndex (0 = guild master) or nil.
local guildRankByName = {}

function CouncilRules:RefreshGuildRoster()
	wipe(guildRankByName)
	if not IsInGuild() then
		return
	end
	local getInfo = GetGuildRosterInfo
	for i = 1, (GetNumGuildMembers and GetNumGuildMembers()) or 0 do
		local name, _, rankIndex = getInfo(i)
		if name then
			guildRankByName[name] = rankIndex
			guildRankByName[(strsplit("-", name))] = guildRankByName[(strsplit("-", name))] or rankIndex
		end
	end
end

local function guildRank(unit, fullName)
	local myGuild = GetGuildInfo("player")
	if not myGuild then
		return nil
	end
	local guildName, _, rankIndex = GetGuildInfo(unit)
	if guildName then
		return guildName == myGuild and rankIndex or nil
	end
	local short = fullName and (strsplit("-", fullName))
	return guildRankByName[fullName] or (short and guildRankByName[short])
end

-- The current guild's ranks as { index = rankIndex, name = rankName }, highest first -- for the
-- Council options page. rankIndex is 0-based (0 = guild master), like GetGuildInfo's.
function CouncilRules:GetGuildRanks()
	local ranks = {}
	if not IsInGuild() or not GuildControlGetNumRanks then
		return ranks
	end
	for i = 1, GuildControlGetNumRanks() do
		table.insert(ranks, { index = i - 1, name = GuildControlGetRankName(i) or ("Rank " .. i) })
	end
	return ranks
end

-- Who's on the loot council, from the profile's council settings. The master looter is always on
-- it; on top of that: raid leader and assistants (council.raidAssist), members of the selected
-- guild ranks (council.guildRanks[rankIndex]) and manually listed names (council.manualList, by
-- "Name-Realm" or plain "Name"). Only the session HOLDER's settings matter once a session runs --
-- the holder broadcasts the resulting member list (Data/Session.lua:OnRosterRebuilt).
-- entry: the roster entry being built; unit: its live unit token; profile: PLC.db.profile.
function CouncilRules:Evaluate(entry, unit, profile)
	local council = profile.council
	if self:IsMasterLooterUnit(unit) then
		return true
	end
	if council.raidAssist then
		if (UnitIsGroupLeader and UnitIsGroupLeader(unit)) or (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) then
			return true
		end
	end
	if next(council.guildRanks) then
		local rank = guildRank(unit, entry.name)
		if rank and council.guildRanks[rank] then
			return true
		end
	end
	local short = entry.name and (strsplit("-", entry.name))
	return council.manualList[entry.name] == true or (short ~= nil and council.manualList[short] == true)
end

-- One-time move from the old single "mode" setting (raidAssist / manual / mlOnly) to the
-- combinable settings above. The master looter was council in every old mode and still is.
PLC:RegisterOnEnable(function()
	local council = PLC.db.profile.council
	if council.mode then
		council.raidAssist = council.mode == "raidAssist"
		council.mode = nil
	end
	if GuildRoster then
		GuildRoster()
	elseif C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	end
end)
