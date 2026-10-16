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

		council = {
			mode = "raidAssist", -- "raidAssist" | "manual" | "mlOnly"
			manualList = {}, -- [charName] = true, used only when mode == "manual"
		},

		responses = {
			{ key = "NEED",  text = "Need",  color = { r = 0.10, g = 0.90, b = 0.20 }, order = 1 },
			{ key = "GREED", text = "Greed", color = { r = 0.90, g = 0.90, b = 0.10 }, order = 2 },
			{ key = "PASS",  text = "Pass",  color = { r = 0.60, g = 0.60, b = 0.60 }, order = 3 },
		},

		lootThreshold = 3, -- Blizzard item quality enum: 3 = Rare

		sessionForceEndMinutes = 10, -- see docs/SPECIFICATION.md §5.1 "stuck-session escape hatch"
		sessionHeartbeatSeconds = 60,
		responseTimeoutSeconds = 60, -- the holder's value wins for everyone -- see Data/Session.lua:Start()

		announce = {
			sessionStart = true,
			award = true,
		},
	},
	char = {
		activeSession = nil, -- Data/Session.lua persists the held session here; nil = not currently a holder
	},
}
