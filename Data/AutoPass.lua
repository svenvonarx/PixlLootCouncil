local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Passing by itself on loot this character can't use, so the Loot Response window only shows what's
-- worth answering, and the council still sees an answer from everyone. Like RCLootCouncil Classic's
-- auto pass, but read from the item's own tooltip, which the game already colors red for whatever
-- this character can't meet: another class's token ("Classes: ..."), an armor or weapon type it
-- can't use, a profession it doesn't have or a pattern it already knows, a level it hasn't reached.
-- That works the same in every client language. On top, RCLootCouncil's weapon rule, kept to what
-- holds in TBC: a caster weapon (Intellect, no Strength or Agility) for a physical class, and a
-- physical one (Strength or Agility, no Intellect) for a pure caster. Hybrids never pass on stats.
-- Cloaks never pass: anyone can wear one.
local AutoPass = {}
PLC.AutoPass = AutoPass

local PHYSICAL = { WARRIOR = true, ROGUE = true, HUNTER = true }
local CASTER = { PRIEST = true, MAGE = true, WARLOCK = true }
local WEAPON_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2

local scanTooltip
local cache = {} -- [itemString] = true/false, once the item's tooltip could be read

local function isRed(fontString)
	if not fontString or not fontString:IsShown() or (fontString:GetText() or "") == "" then
		return false
	end
	local r, g, b = fontString:GetTextColor()
	return r and r > 0.95 and g < 0.2 and b < 0.2
end

-- true: something on the tooltip is red. nil: the tooltip couldn't be read yet (not cached).
local function tooltipSaysUnusable(link)
	if not scanTooltip then
		scanTooltip = CreateFrame("GameTooltip", "PixlLootCouncilAutoPassTooltip", nil, "GameTooltipTemplate")
	end
	scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
	scanTooltip:ClearLines()
	scanTooltip:SetHyperlink(link)
	local lines = scanTooltip:NumLines() or 0
	if lines < 2 then
		scanTooltip:Hide()
		return nil
	end
	local red = false
	for i = 2, lines do
		if isRed(_G["PixlLootCouncilAutoPassTooltipTextLeft" .. i]) or isRed(_G["PixlLootCouncilAutoPassTooltipTextRight" .. i]) then
			red = true
			break
		end
	end
	scanTooltip:Hide()
	return red
end

local function wrongWeaponStats(link)
	local _, class = UnitClass("player")
	if not (PHYSICAL[class] or CASTER[class]) then
		return false
	end
	local stats = C_Item.GetItemStats and C_Item.GetItemStats(link) or (GetItemStats and GetItemStats(link))
	if not stats then
		return false
	end
	local physical = stats.ITEM_MOD_STRENGTH_SHORT or stats.ITEM_MOD_AGILITY_SHORT
	local caster = stats.ITEM_MOD_INTELLECT_SHORT
	if PHYSICAL[class] then
		return caster ~= nil and not physical
	end
	return physical ~= nil and not caster
end

-- true: pass on it. false: worth answering. nil: can't tell yet (the item isn't cached).
function AutoPass:ShouldPass(link, itemString)
	if not link then
		return nil
	end
	local key = itemString or link
	if cache[key] ~= nil then
		return cache[key]
	end
	local _, _, _, _, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(link)
	if not equipLoc then
		return nil
	end
	local pass
	if equipLoc == "INVTYPE_CLOAK" then
		pass = false
	else
		local red = tooltipSaysUnusable(link)
		if red == nil then
			return nil
		end
		pass = red or (classID == WEAPON_CLASS and wrongWeaponStats(link))
	end
	cache[key] = pass
	return pass
end

-- Learning a profession or reaching a level changes the answer.
PLC.Events:RegisterHandler("PLAYER_LEVEL_UP", function() wipe(cache) end)
PLC:RegisterOnEnable(function()
	PLC:RegisterBucketEvent({ "SKILL_LINES_CHANGED" }, 1, function() wipe(cache) end)
end)

-- The note the council sees with an automatic pass.
AutoPass.NOTE_KEY = "AUTOPASS_NOTE"
function AutoPass:Note()
	return L[self.NOTE_KEY]
end
