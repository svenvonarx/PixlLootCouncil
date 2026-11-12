local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Passing by itself on loot this character can't use, so the Loot Response window only shows what's
-- worth answering, and the council still sees an answer from everyone. Like RCLootCouncil Classic's
-- auto pass, but read from the item's own tooltip, which the game already colors red for whatever
-- this character can't meet: another class's token ("Classes: ..."), an armor or weapon type it
-- can't use, a profession it doesn't have or a pattern it already knows, a level it hasn't reached.
-- A pattern for the character's own profession that only needs more skill doesn't pass.
-- That works the same in every client language. On top, RCLootCouncil's weapon rule, kept to what
-- holds in TBC: a caster weapon (Intellect, no Strength or Agility) for a physical class, and a
-- physical one (Strength or Agility, no Intellect) for a pure caster. Hybrids never pass on stats.
-- Cloaks never pass: anyone can wear one.
local AutoPass = {}
PLC.AutoPass = AutoPass

local PHYSICAL = { WARRIOR = true, ROGUE = true, HUNTER = true }
local CASTER = { PRIEST = true, MAGE = true, WARLOCK = true }
local WEAPON_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9

local scanTooltip
local cache = {} -- [itemString] = true/false, once the item's tooltip could be read

local function isRed(fontString)
	if not fontString or not fontString:IsShown() or (fontString:GetText() or "") == "" then
		return false
	end
	local r, g, b = fontString:GetTextColor()
	return r and r > 0.95 and g < 0.2 and b < 0.2
end

-- true: something on the tooltip is red; second value: one of the red lines says it's already known
-- (ITEM_SPELL_KNOWN). nil: the tooltip couldn't be read yet (not cached).
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
	local red, known = false, false
	for i = 2, lines do
		local left = _G["PixlLootCouncilAutoPassTooltipTextLeft" .. i]
		if isRed(left) or isRed(_G["PixlLootCouncilAutoPassTooltipTextRight" .. i]) then
			red = true
			if ITEM_SPELL_KNOWN and left and left:GetText() == ITEM_SPELL_KNOWN then
				known = true
			end
		end
	end
	scanTooltip:Hide()
	return red, known
end

-- Whether this character has the profession a recipe is for, at any skill: the recipe's item
-- subtype is the profession's name, in the client's language like the skill list.
local function hasProfession(name)
	if not name or not GetNumSkillLines then
		return false
	end
	for i = 1, GetNumSkillLines() do
		local skillName, isHeader = GetSkillLineInfo(i)
		if not isHeader and skillName == name then
			return true
		end
	end
	return false
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
	local _, _, _, _, _, _, subType, _, equipLoc, _, _, classID = C_Item.GetItemInfo(link)
	if not equipLoc then
		return nil
	end
	local pass
	if equipLoc == "INVTYPE_CLOAK" then
		pass = false
	else
		local red, known = tooltipSaysUnusable(link)
		if red == nil then
			return nil
		end
		if red and classID == RECIPE_CLASS and not known and hasProfession(subType) then
			-- Their own profession, only not skilled enough yet: theirs to answer.
			red = false
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
