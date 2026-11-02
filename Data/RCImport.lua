local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- One-click move from RCLootCouncil, for the welcome window (UI/WelcomeFrame.lua): its loot
-- history, and the settings that mean the same thing here.
--
-- Only what the loot master actually changed in RCLootCouncil comes over. Its saved data holds
-- nothing else (AceDB leaves defaults out), and its defaults aren't always ours: it doesn't start
-- sessions by itself, for example, and that's not something they chose.
local RCImport = {}
PLC.RCImport = RCImport

local RC_FOLDER = "RCLootCouncil_Classic"
-- RCLootCouncil's own default buttons, for any it saved only partly (Core/Defaults.lua there).
local RC_BUTTONS = {
	{ text = _G.NEED, color = { 0, 1, 0 } },
	{ text = _G.GREED, color = { 1, 0.5, 0 } },
	{ text = L["RC_MINOR_UPGRADE"], color = { 0, 0.7, 0.7 } },
}
local RC_DEFAULT_BUTTON_COUNT = 3
local MIN_TIMEOUT, MAX_TIMEOUT = 15, 300 -- Options -> General's range

-- Installed, whether or not it's enabled on this character.
function RCImport:IsInstalled()
	local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	if not getInfo then
		return false
	end
	local name, _, _, _, reason = getInfo(RC_FOLDER)
	return name ~= nil and reason ~= "MISSING"
end

-- Its saved data only loads with it, on characters it's enabled for.
local function profile()
	local db = _G.RCLootCouncilDB
	if type(db) ~= "table" or type(db.profiles) ~= "table" then
		return nil
	end
	local key = (UnitName("player") or "") .. " - " .. (GetRealmName() or "")
	local name = type(db.profileKeys) == "table" and db.profileKeys[key] or "Default"
	return db.profiles[name]
end

function RCImport:IsAvailable()
	return profile() ~= nil or PLC.History:HasLocalRCData()
end

-- RCLootCouncil keeps its council as character IDs. Its own cache has their names, and the game
-- knows anyone it has seen recently.
local function nameFor(guid)
	local cache = type(_G.RCLootCouncilDB) == "table" and type(_G.RCLootCouncilDB.global) == "table"
		and _G.RCLootCouncilDB.global.playerCache
	local cached = type(cache) == "table" and cache[guid]
	if type(cached) == "table" and type(cached.name) == "string" and cached.name ~= "" then
		return cached.name
	end
	local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
	if name and name ~= "" then
		return (realm and realm ~= "") and (name .. "-" .. realm) or name
	end
	return nil
end

local function color(value, fallback)
	if type(value) == "table" and type(value[1]) == "number" then
		return { r = value[1], g = value[2] or 0, b = value[3] or 0 }
	end
	return { r = fallback[1], g = fallback[2], b = fallback[3] }
end

-- Its buttons, if the loot master changed them, ending with our Pass. Partly saved buttons are
-- filled in from its defaults.
local function buttons(rc)
	local saved = type(rc.buttons) == "table" and type(rc.buttons.default) == "table" and rc.buttons.default
	local savedColors = type(rc.responses) == "table" and type(rc.responses.default) == "table" and rc.responses.default
	if not saved and not savedColors then
		return nil
	end
	saved, savedColors = saved or {}, savedColors or {}
	local count = tonumber(saved.numButtons) or RC_DEFAULT_BUTTON_COUNT
	local list = {}
	for i = 1, math.min(count, PLC.Responses.MAX_COUNT - 1) do
		local button = type(saved[i]) == "table" and saved[i] or {}
		local fallback = RC_BUTTONS[i] or { text = nil, color = { 1, 1, 1 } }
		local text = type(button.text) == "string" and button.text ~= "" and button.text or fallback.text
		if text then
			local response = type(savedColors[i]) == "table" and savedColors[i] or {}
			table.insert(list, { key = "RC" .. i, text = text, color = color(response.color, fallback.color) })
		end
	end
	table.insert(list, { key = "PASS", text = L["RESPONSE_PASS"], color = { r = 0.6, g = 0.6, b = 0.6 } })
	return PLC.Responses.Sanitize(list)
end

-- Imports everything that fits, and says what: { history, council, unknown, ranks, buttons,
-- timeout, announce, autoStart }, each nil when nothing came over.
function RCImport:Import()
	local summary = {}
	if PLC.History:HasLocalRCData() then
		summary.history = PLC.History:ImportFromLocalRC()
	end

	local rc = profile()
	if not rc then
		return summary
	end
	local settings = PLC.db.profile

	if type(rc.timeout) == "number" then
		settings.responseTimeoutSeconds = math.max(MIN_TIMEOUT, math.min(MAX_TIMEOUT, math.floor(rc.timeout)))
		summary.timeout = settings.responseTimeoutSeconds
	end
	if type(rc.announceAward) == "boolean" then
		settings.announce.award = rc.announceAward
		summary.announce = true
	end
	if type(rc.announceItems) == "boolean" then
		settings.announce.sessionStart = rc.announceItems
		summary.announce = true
	end
	if type(rc.autoStart) == "boolean" then
		settings.autoStartSession = rc.autoStart
		summary.autoStart = true
	end

	-- "This rank and above": rank 1 is the guild master, our rank index 0.
	if type(rc.minRank) == "number" and rc.minRank >= 1 then
		for rank = 0, rc.minRank - 1 do
			settings.council.guildRanks[rank] = true
		end
		summary.ranks = rc.minRank
	end
	if type(rc.council) == "table" and #rc.council > 0 then
		local added, unknown = 0, 0
		for _, guid in ipairs(rc.council) do
			local name = type(guid) == "string" and nameFor(guid)
			if name then
				settings.council.manualList[name] = true
				added = added + 1
			else
				unknown = unknown + 1
			end
		end
		summary.council = added > 0 and added or nil
		summary.unknown = unknown > 0 and unknown or nil
	end

	local list = buttons(rc)
	if list then
		PLC.Responses:Save(list)
		summary.buttons = #list
	end
	if PLC.Roster and PLC.Roster.Rebuild then
		PLC.Roster:Rebuild() -- the council may have changed
	end
	return summary
end
