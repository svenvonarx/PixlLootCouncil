local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- AceDB-3.0 defaults table. `global` is account-wide, `profile` is per-AceDB-profile,
-- `char` is per-character-realm (used for the active session, since a loot session
-- belongs to whichever character started it -- see docs/SPECIFICATION.md §5.1).
PLC.Defaults = {
	global = {
		errors = {}, -- ring buffer, see Core/ErrorHandler.lua
		update = {}, -- the newest version heard of and what's been said about it, Data/UpdateNotice.lua
	},
	profile = {
		theme = "gold", -- a key of Theme.THEMES, see UI/Theme.lua
		uiScale = 100, -- percent, Options -> Appearance -> Scale (UI/Widgets/Primitives.lua:addonScale)
		sessionScale = 1, -- the Loot Session window's own, set by dragging its corner sideways
		font = "Inter", -- a LibSharedMedia font name, see UI/Widgets/Primitives.lua

		-- Data/CouncilRules.lua:Evaluate. The master looter is always council; these add to it.
		council = {
			raidAssist = true, -- raid leader and assistants
			guildRanks = {}, -- [rankIndex] = true (0 = guild master)
			manualList = {}, -- ["Name-Realm" or "Name"] = true
		},

		-- The built-in set. Edits are stored in profile.customResponses -- see Data/Responses.lua.
		responses = {
			{ key = "BIS",     text = L["RESPONSE_BIS"], color = { r = 0.15, g = 0.85, b = 0.35 }, order = 1 },
			{ key = "UPGRADE", text = L["RESPONSE_UPGRADE"], color = { r = 0.35, g = 0.65, b = 0.95 }, order = 2 },
			{ key = "PVP",     text = L["RESPONSE_PVP"], color = { r = 0.75, g = 0.40, b = 0.90 }, order = 3 },
			{ key = "OS",      text = L["RESPONSE_OS"], color = { r = 0.90, g = 0.55, b = 0.20 }, order = 4 },
			{ key = "PASS",    text = L["RESPONSE_PASS"], color = { r = 0.60, g = 0.60, b = 0.60 }, order = 5 },
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
		sessionHeartbeatSeconds = 10, -- also how quickly anyone who missed something catches up
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
		-- Raider mode (Data/CouncilRules.lua:IsRaiderMode): as master looter, loot, collect and start
		-- nothing by itself. Set by the welcome window's Raider card or /plc raider.
		raiderMode = false,
		-- RCLootCouncil's autoStart: collecting loot as master looter starts a review pass by itself
		-- (Data/Session.lua:ScheduleAutoStart).
		autoStartSession = true,
		-- The Loot Session window was minimized into UI/LootTimersFrame.lua: `/plc` and auto-start
		-- reopen that view instead of the full window.
		sessionMinimized = false,
		-- How many items the Loot Response window shows before it scrolls, set by resizing it. Fewer
		-- items shrink it below this (UI/LootFrame.lua:fitHeight).
		lootResponseRows = 8,
		lootTimersWindow = { point = "RIGHT", x = -60, y = 120 }, -- LibWindow-1.1 position
		-- Loot/MasterLooterList.lua: who becomes master looter when the group switches to Master Loot.
		autoMasterLooter = true,
		masterLooterList = {}, -- names, the first found in the group gets it
		masterLootThreshold = 0, -- item quality to set when switching to Master Loot, 0 leaves it

		updateNotices = true, -- Data/UpdateNotice.lua
	},
	char = {
		activeSession = nil, -- Data/Session.lua persists the held session here; nil = not currently a holder
		knownBagGuids = nil, -- Loot/BagTracker.lua: item GUIDs in the bags at the last scan (nil = no baseline yet)
	},
}
