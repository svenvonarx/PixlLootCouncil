local ADDON_NAME, PLC = ...

-- What auto loot does with particular items, and whether sessions review them. Each rule is a target
-- like Options -> Auto Loot's (Loot/AutoLoot.lua):
--   "keep"   the master looter takes it, and it's never reviewed: loot the raid keeps
--   "leave"  it stays in the loot window, where clicking it opens Blizzard's assign list; never reviewed
--   "self"   the master looter takes it, and it's reviewed like any loot
--   names    a comma-separated list of players, tried in order; never reviewed
-- DEFAULTS is curated here and changes with updates. Anyone can change an item for themselves under
-- Options -> Auto Loot (profile.autoLoot.exceptions), which only stores what they changed: every
-- other item keeps following DEFAULTS, so a new default reaches them, and resetting an item brings its
-- default back.
local ItemRules = {}
PLC.ItemRules = ItemRules

ItemRules.KEEP = "keep"
ItemRules.LEAVE = "leave"
ItemRules.SELF = "self"

ItemRules.DEFAULTS = {
	-- Raid materials
	[32897] = "keep", -- Mark of the Illidari (Black Temple)
	[32428] = "keep", -- Heart of Darkness (Black Temple)
	[23572] = "keep", -- Primal Nether
	[30183] = "keep", -- Nether Vortex
	[34664] = "leave", -- Sunmote (Sunwell Plateau)
	-- Raw epic gems (Hyjal, Black Temple and Sunwell trash)
	[32227] = "keep", -- Crimson Spinel
	[32228] = "keep", -- Empyrean Sapphire
	[32229] = "keep", -- Lionseye
	[32230] = "keep", -- Shadowsong Amethyst
	[32231] = "keep", -- Pyrestone
	[32249] = "keep", -- Seaspray Emerald
}

local function ownRules()
	local autoLoot = PLC.db and PLC.db.profile and PLC.db.profile.autoLoot
	return autoLoot and autoLoot.exceptions or {}
end

-- The player's own rule for an item, else the default, else nil (nothing particular).
function ItemRules.For(itemID)
	if not itemID then
		return nil
	end
	return ownRules()[itemID] or ItemRules.DEFAULTS[itemID]
end

-- Kept or left in the window: loot nobody hands out through a session. Not loot sent to named players,
-- which is the master looter's own business once it's in their bags.
function ItemRules.IsKeptOrLeft(itemID)
	local rule = ItemRules.For(itemID)
	return rule == ItemRules.KEEP or rule == ItemRules.LEAVE
end

-- Loot every player takes their own copy of, like a currency: nothing for the council to hand out.
-- Sessions never review them, and auto loot takes the master looter's own copy, like anyone loots
-- theirs. These aren't master looted, so no rule can send them to someone else.
PLC.PersonalLootItems = {
	[29434] = true, -- Badge of Justice
}
