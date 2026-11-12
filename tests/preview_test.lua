-- Run from the addon folder: luajit tests/preview_test.lua
--
-- The real Data/Preview.lua: when a preview ends by itself. It has to wait for the Loot Trades window
-- with who got what, or a preview alone would never show it.
local out = print
local printed = {}
_G.print = function(text) printed[#printed + 1] = tostring(text) end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.LibStub = function() return { GetLocale = function() return setmetatable({}, { __index = function(_, k) return k end }) end } end

local PLC = { UI = {}, Comms = {} }
function PLC:RegisterSlashCommand() end
local ended, previewEnds = 0, 0
local Session = { items = {}, responses = {}, state = "inactive", preview = false, nextIdx = 5 }
PLC.Session = Session
function Session:IsOwner() return true end
function Session:IsHolder() return self.state == "active" end
function Session:End() ended = ended + 1; self.state = "ended" end
function Session:notifyLootFrame() end
function Session:notifySessionFrame() end
function Session:notifyTradeFrame() end
PLC.Comms.Sync = { SendPreviewEnd = function() previewEnds = previewEnds + 1 end }
local tradesShown = false
PLC.UI.TradeFrame = { IsShown = function() return tradesShown end }
assert(loadfile("Data/Preview.lua"))("PixlLootCouncil", PLC)
local Preview = PLC.Preview

local passed, failed = 0, 0
local function check(id, ok, detail)
	if ok then passed = passed + 1 else failed = failed + 1 end
	out(string.format("%-4s %-5s %s", id, ok and "pass" or "FAIL", detail or ""))
end

-- Alone: every award is one's own, so nothing is left to trade the moment Award All is pressed.
Session.items = { [1] = { idx = 1, link = "[Real]" } }
Preview:Enter()
Session.state = "ended"
Session.items = { [1] = { idx = 1, awarded = "me", traded = true }, [2] = { idx = 2, awarded = "me", traded = true } }
tradesShown = true
Preview:CheckFinished()
check("P1", Session.preview == true and Session.items[2] ~= nil, "after Award All the preview stays while Loot Trades shows who got what")
tradesShown = false
Preview:CheckFinished()
check("P2", Session.preview == false and previewEnds == 1, "closing Loot Trades ends it, for everyone")
check("P3", Session.items[1].link == "[Real]" and Session.items[2] == nil and Session.nextIdx == 5, "and the real loot list is back")

Preview:Enter()
Session.state = "ended"
Session.items = { [1] = { idx = 1, awarded = "ana" } }
Preview:CheckFinished()
check("P4", Session.preview == true, "with something still to hand over it stays, window or not")
Session.items[1].traded = true
Preview:CheckFinished()
check("P5", Session.preview == false, "and ends once that's done and the window is closed")

Preview:Enter()
Session.state = "active"
Preview:CheckFinished()
check("P6", Session.preview == true, "never while the review is still running")
Preview:Stop()

out(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
