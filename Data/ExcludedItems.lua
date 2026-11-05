local ADDON_NAME, PLC = ...

-- Items auto loot never hands out and sessions never review: nobody assigns them through the council.
-- They stay in the loot window, where clicking one opens Blizzard's normal assign list. This list
-- is curated over time: add an item here by its ID. An exception under Options -> Auto Loot still
-- wins, so a raid can send these to a mule without changing the list.
PLC.ExcludedItems = {
	[32897] = true, -- Mark of the Illidari (Black Temple)
	[32428] = true, -- Heart of Darkness (Black Temple)
	[34664] = true, -- Sunmote (Sunwell Plateau)
	[23572] = true, -- Primal Nether
	-- Raw epic gems (Hyjal, Black Temple and Sunwell trash)
	[32227] = true, -- Crimson Spinel
	[32228] = true, -- Empyrean Sapphire
	[32229] = true, -- Lionseye
	[32230] = true, -- Shadowsong Amethyst
	[32231] = true, -- Pyrestone
	[32249] = true, -- Seaspray Emerald
}

-- Loot every player takes their own copy of, like a currency: nothing for the council to hand out.
-- Sessions never review them, and auto loot takes the master looter's own copy, like anyone loots
-- theirs. These aren't master looted, so no exception can send them to someone else.
PLC.PersonalLootItems = {
	[29434] = true, -- Badge of Justice
}
