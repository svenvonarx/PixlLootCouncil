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
}
