local ADDON_NAME, PLC = ...

-- AceDB-3.0 defaults table. `global` is account-wide, `profile` is per-AceDB-profile,
-- `char` is per-character-realm (used for the active session, since a loot session
-- belongs to whichever character started it -- see docs/SPECIFICATION.md §5.1).
PLC.Defaults = {
	global = {
		errors = {}, -- ring buffer, see Core/ErrorHandler.lua
	},
	profile = {
		accent = { r = 0.91, g = 0.64, b = 0.24 }, -- #E8A33D, see docs/SPECIFICATION.md §4.1

		-- Data/CouncilRules.lua:Evaluate. The master looter is always council; these add to it.
		council = {
			raidAssist = true, -- raid leader and assistants
			guildRanks = {}, -- [rankIndex] = true (0 = guild master)
			manualList = {}, -- ["Name-Realm" or "Name"] = true
		},

		responses = {
			{ key = "BIS",     text = "BiS",     color = { r = 0.15, g = 0.85, b = 0.35 }, order = 1 },
			{ key = "UPGRADE", text = "Upgrade", color = { r = 0.35, g = 0.65, b = 0.95 }, order = 2 },
			{ key = "PVP",     text = "PvP",     color = { r = 0.75, g = 0.40, b = 0.90 }, order = 3 },
			{ key = "OS",      text = "OS",      color = { r = 0.90, g = 0.55, b = 0.20 }, order = 4 },
			{ key = "PASS",    text = "Pass",    color = { r = 0.60, g = 0.60, b = 0.60 }, order = 5 },
		},

		lootThreshold = 3, -- Blizzard item quality enum: 3 = Rare

		sessionForceEndMinutes = 10, -- see docs/SPECIFICATION.md §5.1 "stuck-session escape hatch"
		sessionHeartbeatSeconds = 60,
		responseTimeoutSeconds = 60, -- the holder's value wins for everyone -- see Data/Session.lua:Start()

		announce = {
			sessionStart = true,
			award = true,
		},

		historyExport = "sheets", -- UI/HistoryFrame.lua export format: "sheets" | "tsv"
		-- UI/HistoryFrame.lua filter menu (see Data/History.lua:PassesFilters). class: [classFile] =
		-- true for each selected class (none = all); hiddenResponses: [response text] = true.
		historyFilters = {
			class = {},
			hiddenResponses = {},
		},
		-- Store the loot history an RCLootCouncil master looter broadcasts to the group (see
		-- Data/HistoryImport.lua) -- lets a raider who isn't the loot master keep the full history.
		historyMirrorRC = true,
		-- RCLootCouncil's autoStart: collecting loot as master looter starts a review pass by itself
		-- (Data/Session.lua:ScheduleAutoStart).
		autoStartSession = true,
	},
	char = {
		activeSession = nil, -- Data/Session.lua persists the held session here; nil = not currently a holder
		knownBagGuids = nil, -- Loot/BagTracker.lua: item GUIDs in the bags at the last scan (nil = no baseline yet)
	},
}
