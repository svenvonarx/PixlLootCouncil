-- Run from the addon folder: luajit tests/autopass_test.lua
--
-- The real Data/AutoPass.lua against a stubbed tooltip: which loot a character passes on by itself.
local out = print
_G.print = function() end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end
_G.UIParent = {}

-- The items: their tooltip lines (red = true where the game colors them red), slot, class and stats.
local ITEMS = {
	["[Token]"] = { lines = { { "Classes: Warrior, Hunter, Shaman", red = true } }, equipLoc = "", classID = 15 },
	["[Own token]"] = { lines = { { "Classes: Paladin, Rogue, Shaman" } }, equipLoc = "", classID = 15 },
	["[Plate]"] = { lines = { { "Chest", right = "Plate", rightRed = true } }, equipLoc = "INVTYPE_CHEST", classID = 4 },
	["[Cloth]"] = { lines = { { "Chest", right = "Cloth" } }, equipLoc = "INVTYPE_CHEST", classID = 4 },
	["[Cloak]"] = { lines = { { "Back", right = "Cloth", rightRed = true } }, equipLoc = "INVTYPE_CLOAK", classID = 4 },
	["[Pattern]"] = { lines = { { "Requires Leatherworking (375)", red = true } }, equipLoc = "", classID = 9 },
	["[Known]"] = { lines = { { "Already known", red = true } }, equipLoc = "", classID = 9 },
	["[Caster staff]"] = { lines = { { "Two-Hand", right = "Staff" } }, equipLoc = "INVTYPE_2HWEAPON", classID = 2,
		stats = { ITEM_MOD_INTELLECT_SHORT = 30 } },
	["[Agility sword]"] = { lines = { { "One-Hand", right = "Sword" } }, equipLoc = "INVTYPE_WEAPON", classID = 2,
		stats = { ITEM_MOD_AGILITY_SHORT = 20 } },
	["[Spell dagger]"] = { lines = { { "One-Hand", right = "Dagger" } }, equipLoc = "INVTYPE_WEAPON", classID = 2, stats = {} },
}
local lookups = 0
_G.C_Item = {
	GetItemInfo = function(link)
		local item = ITEMS[link]
		if not item then return nil end
		lookups = lookups + 1
		return link, link, 4, 70, 70, "", "", 1, item.equipLoc, 0, 0, item.classID
	end,
	GetItemStats = function(link) return ITEMS[link] and ITEMS[link].stats end,
}
local function fontString()
	local f = { text = "", r = 1, g = 1, b = 1, shown = false }
	function f:IsShown() return self.shown end
	function f:GetText() return self.text end
	function f:GetTextColor() return self.r, self.g, self.b end
	return f
end
_G.CreateFrame = function(_, name)
	local tip = { count = 0 }
	for i = 1, 10 do
		_G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i] = fontString(), fontString()
	end
	function tip:SetOwner() end
	function tip:Hide() end
	function tip:ClearLines()
		self.count = 0
		for i = 1, 10 do _G[name .. "TextLeft" .. i].shown, _G[name .. "TextRight" .. i].shown = false, false end
	end
	function tip:SetHyperlink(link)
		local item = ITEMS[link]
		if not item then return end
		local all = { { link } }
		for _, line in ipairs(item.lines) do all[#all + 1] = line end
		for i, line in ipairs(all) do
			local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
			left.text, left.shown, left.r, left.g, left.b = line[1], true, 1, line.red and 0.1 or 1, line.red and 0.1 or 1
			if line.right then
				right.text, right.shown, right.r, right.g, right.b = line.right, true, 1, line.rightRed and 0.1 or 1, line.rightRed and 0.1 or 1
			end
		end
		self.count = #all
	end
	function tip:NumLines() return self.count end
	return tip
end
local class = "MAGE"
_G.UnitClass = function() return "Mage", class end

local PLC = { Events = { RegisterHandler = function() end } }
function PLC:RegisterOnEnable() end
assert(loadfile("Data/AutoPass.lua"))("PixlLootCouncil", PLC)
local AutoPass = PLC.AutoPass

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local function passes(link) return AutoPass:ShouldPass(link, link .. class) end

check("A1", passes("[Token]") == true and passes("[Own token]") == false, "another class's token passes; your own doesn't")
check("A2", passes("[Plate]") == true and passes("[Cloth]") == false, "armor you can't wear passes")
check("A3", passes("[Cloak]") == false, "a cloak never does: anyone can wear one")
check("A4", passes("[Pattern]") == true and passes("[Known]") == true, "a pattern for another profession, or one you know, passes")
check("A5", passes("[Agility sword]") == true and passes("[Caster staff]") == false, "a mage passes on a physical weapon, not a caster one")
class = "WARRIOR"
check("A6", passes("[Caster staff]") == true and passes("[Agility sword]") == false, "a warrior the other way round")
class = "PALADIN"
check("A7", passes("[Caster staff]") == false and passes("[Agility sword]") == false, "hybrids never pass on stats")
check("A8", passes("[Spell dagger]") == false, "nor does anyone on a weapon without main stats")
check("A9", AutoPass:ShouldPass("[Not cached]") == nil, "an item the game doesn't know yet: can't tell, so it shows")
passes("[Token]")
local before = lookups
passes("[Token]")
check("A10", lookups == before, "an answer is kept, so a busy window doesn't read tooltips every second")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
