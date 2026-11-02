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

		-- The built-in set. Edits are stored in profile.customResponses -- see Data/Responses.lua.
		responses = {
			{ key = "BIS",     text = "BiS",     color = { r = 0.15, g = 0.85, b = 0.35 }, order = 1 },
			{ key = "UPGRADE", text = "Upgrade", color = { r = 0.35, g = 0.65, b = 0.95 }, order = 2 },
			{ key = "PVP",     text = "PvP",     color = { r = 0.75, g = 0.40, b = 0.90 }, order = 3 },
			{ key = "OS",      text = "OS",      color = { r = 0.90, g = 0.55, b = 0.20 }, order = 4 },
			{ key = "PASS",    text = "Pass",    color = { r = 0.60, g = 0.60, b = 0.60 }, order = 5 },
		},

		-- Blizzard item quality enum: 4 = Epic. Patterns count regardless (Detection:IsReviewItem).
		-- Raid materials nobody assigns stay out this way: Mark of the Illidari is green, Heart of
		-- Darkness and Sunmote are blue.
		lootThreshold = 4,

		-- Loot/AutoLoot.lua. A target is "self", "leave" or comma-separated player names, tried in order.
		autoLoot = {
			enabled = true,
			lootGold = true,
			outsideInstances = false, -- world bosses
			reviewTarget = "self", -- epics, legendaries and patterns
			otherTarget = "leave", -- anything else the group's loot threshold makes master loot
			exceptions = {}, -- [itemID] = target
		},

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
		-- Answer a master looter running RCLootCouncil with this addon's Loot Response window
		-- (Data/RCBridge.lua). Does nothing while RC itself is running on this client.
		rcBridge = true,
		-- RCLootCouncil's autoStart: collecting loot as master looter starts a review pass by itself
		-- (Data/Session.lua:ScheduleAutoStart).
		autoStartSession = true,
		-- The Loot Session window was minimized into UI/LootTimersFrame.lua: `/plc` and auto-start
		-- reopen that view instead of the full window.
		sessionMinimized = false,
		lootTimersWindow = { point = "RIGHT", x = -60, y = 120 }, -- LibWindow-1.1 position
		-- Loot/MasterLooterList.lua: who becomes master looter when the group switches to Master Loot.
		autoMasterLooter = true,
		masterLooterList = {}, -- names, the first found in the group gets it
		masterLootThreshold = 0, -- item quality to set when switching to Master Loot, 0 leaves it
	},
	char = {
		activeSession = nil, -- Data/Session.lua persists the held session here; nil = not currently a holder
		knownBagGuids = nil, -- Loot/BagTracker.lua: item GUIDs in the bags at the last scan (nil = no baseline yet)
	},
}
