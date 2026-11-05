-- Run from the addon folder: luajit tests/bags_test.lua
--
-- The real Loot/BagTracker.lua scan against stubbed bags: loot that leaves the bags without being
-- awarded (traded by another addon, mailed, sold) leaves the loot session's list, and nothing else does.
local out = print
local printed = {}
_G.print = function(s) printed[#printed + 1] = tostring(s) end
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end
_G.NUM_BAG_SLOTS = 4
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local now = 1000
_G.time = function() return now end
_G.IsInInstance = function() return false end

-- The bags: [slot] = { id, guid }; guid nil = the game didn't report one this time.
local bag = {}
local function link(id) return "|cffa335ee|Hitem:" .. id .. ":0:0|h[" .. id .. "]|h|r" end
_G.C_Container = {
	GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
	GetContainerItemLink = function(b, slot) return b == 0 and bag[slot] and link(bag[slot].id) or nil end,
}
_G.ItemLocation = { CreateFromBagAndSlot = function(_, b, slot) return { bag = b, slot = slot } end }
_G.C_Item = {
	GetItemGUID = function(loc) return loc.bag == 0 and bag[loc.slot] and bag[loc.slot].guid or nil end,
	GetItemInfo = function() return nil end,
}

local PLC = { Loot = {}, db = { char = {}, profile = {} } }
function PLC:RegisterOnEnable() end
function PLC:RegisterSlashCommand() end
local Session = { items = {}, responses = {}, state = "active", manage = true, holder = true, ended = false }
PLC.Session = Session
function Session:CanManage() return self.manage end
function Session:IsHolder() return self.holder end
function Session:End() self.ended = true end
function Session:OnTradeStatusChanged() end
function Session:IsOwner() return false end
PLC.CouncilRules = { IsRaiderMode = function() return false end, AmIMasterLooter = function() return false end }
function Session:RemoveItems(idxs)
	for _, idx in ipairs(idxs) do self.items[idx] = nil end
	return #idxs
end
assert(loadfile("Data/ExcludedItems.lua"))("PixlLootCouncil", PLC)
assert(loadfile("Loot/BagTracker.lua"))("PixlLootCouncil", PLC)
local BagTracker = PLC.Loot.BagTracker
BagTracker.GetTradeStatus = function() return "free" end

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end
local GEM, HELM, VORTEX = 30002, 30001, 30183 -- VORTEX stacks
local function setup(...)
	Session.items, Session.preview, Session.manage, Session.holder, Session.ended = {}, nil, true, true, false
	bag = {}
	for i, item in ipairs({ ... }) do
		Session.items[i] = { itemString = "item:" .. item.id, link = link(item.id), itemGUID = item.guid, awarded = item.awarded,
			bagged = true, instance = not item.manual and "Black Temple" or nil }
		if item.guid then bag[i] = { id = item.id, guid = item.guid } end
	end
	PLC.db.char.knownBagGuids = {}
	for k in pairs(printed) do printed[k] = nil end
	BagTracker:Scan()
end
local function later(seconds) now = now + seconds; BagTracker:Scan() end

-- Gone for good ---------------------------------------------------------------------------------------
setup({ id = GEM, guid = "G1" }, { id = HELM, guid = "G2" })
bag[1] = nil -- traded away by another loot addon
later(1)
check("G1", Session.items[1] ~= nil, "an item that just left the bags isn't dropped on the first scan")
later(10)
check("G2", Session.items[1] == nil and Session.items[2] ~= nil, "still gone a scan and 10 seconds later, it leaves the list; the rest stays")
check("G3", #printed == 1 and printed[1]:find("BAGS_ITEM_GONE", 1, true), "with a chat line naming it")
check("G4", not Session.ended, "the session goes on while something's left to review")
bag[2] = nil
later(1); later(10)
check("G5", next(Session.items) == nil and Session.ended, "and ends once nothing's left")

-- Not gone ----------------------------------------------------------------------------------------------
setup({ id = GEM, guid = "G1" })
bag[1].guid = nil -- the game reports the item but not its GUID this time
later(1); later(10); later(30)
check("K1", Session.items[1] ~= nil, "a copy of the item still in the bags keeps it, GUID or not")

setup({ id = GEM, guid = "G1" })
local saved = bag
bag = {} -- the bags not loaded yet, right after logging in
later(1)
bag = saved
later(10)
check("K2", Session.items[1] ~= nil, "bags reported empty for a moment don't drop anything")

setup({ id = GEM, guid = "G1", awarded = true })
bag[1] = nil
later(1); later(10)
check("K3", Session.items[1] ~= nil, "awarded items are left to Loot Trades")

setup({ id = GEM, guid = "G1" })
Session.manage = false -- a raider's copy of someone else's session
bag[1] = nil
later(1); later(10)
check("K4", Session.items[1] ~= nil, "only whoever holds the loot drops anything")

setup({ id = GEM, guid = "G1" })
Session.preview = true
bag[1] = nil
later(1); later(10)
check("K5", Session.items[1] ~= nil, "nor in a preview")

setup({ id = GEM, guid = "G1" })
bag[1] = nil
later(1)
bag[1] = { id = GEM, guid = "G1" } -- back, from the bank or a cancelled trade
later(10)
bag[1] = nil
later(1)
check("K6", Session.items[1] ~= nil, "coming back starts the wait over")

-- Stacks -----------------------------------------------------------------------------------------------
-- A second Nether Vortex joins the first one's stack, so it never gets a GUID of its own.
setup({ id = VORTEX, guid = "V1" }, { id = VORTEX })
check("T1", Session.items[2].boe == true, "a copy in a stack shows the stack's trade status")
bag[1] = nil
later(1); later(10)
check("T2", next(Session.items) == nil, "and leaves with the stack")

setup({ id = VORTEX, manual = true })
later(1); later(10)
check("T3", Session.items[1] ~= nil and Session.items[1].boe == nil, "an item added by hand isn't touched: it may be in someone else's bags")

-- Excluded since it was collected ---------------------------------------------------------------------
local LIONSEYE, PYRESTONE = 32229, 32231
setup({ id = LIONSEYE, guid = "L1" }, { id = PYRESTONE, guid = "P1" }, { id = HELM, guid = "H1" }, { id = LIONSEYE, manual = true })
check("X1", Session.items[1] == nil and Session.items[2] == nil and Session.items[3] ~= nil,
	"raw epic gems collected before they were excluded leave the list; the helm stays")
check("X2", #printed == 1 and printed[1]:find("SESSION_DROPPED_EXCLUDED", 1, true), "with one chat line for all of them")
check("X3", Session.items[4] ~= nil, "a gem added by hand stays")

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
