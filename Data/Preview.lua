local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- A practice run of the whole workflow in a group, with fictional loot: the holder gets a backlog
-- of made-up items on made-up trade timers, and everyone goes through responses, staging, Award All
-- and trades as usual. What's different:
--   * every client sets its real session state aside and gets it back afterwards, and nothing is
--     saved while a preview runs (Session's persist), so a reload can't mix the two
--   * nothing is recorded in the history (Session:AwardBaggedItem)
--   * trades use BoE items from the holder's bags as stand-ins (Loot/Trade.lua)
--   * real loot ends the preview at once, so it can't end up among the fictional items
local Preview = {}
PLC.Preview = Preview

local POOL = {
	{ id = 28789, quality = 4 }, -- Eye of Magtheridon
	{ id = 28830, quality = 4 }, -- Dragonspine Trophy
	{ id = 32331, quality = 4 }, -- Cloak of the Illidari Council
	{ id = 30242, quality = 4 }, -- Helm of the Vanquished Champion
	{ id = 32527, quality = 4 }, -- Ring of Ancient Knowledge
	{ id = 32519, quality = 4 }, -- Belt of Divine Guidance
	{ id = 30302, quality = 4 }, -- Pattern: Belt of Deep Shadow
	{ id = 32837, quality = 5 }, -- Warglaive of Azzinoth
}
local BOE_ITEM = { id = 30324, quality = 4, boe = true } -- Plans: Red Havoc Boots
-- Trade time left on each item, covering every state the timers can show. 0 = already expired.
local TRADE_SECONDS = { 7140, 5400, 3300, 1100, 280, 0 }

local STASHED_FIELDS = {
	"sessionId", "owner", "state", "items", "responses", "nextIdx", "lastHolderSeenAt",
	"responseTimeoutSeconds", "responseSet", "council", "enchanterGuid", "isCollector", "sentFirstBatch",
}

local stash
local stopping = false

local function notifyOptions()
	if PLC.UI and PLC.UI.OptionsFrame and PLC.UI.OptionsFrame.OnPreviewChanged then
		PLC.UI.OptionsFrame:OnPreviewChanged()
	end
end

local function notifyAll()
	local Session = PLC.Session
	Session:notifyLootFrame()
	Session:notifySessionFrame()
	Session:notifyTradeFrame()
	notifyOptions()
end

-- Sets this client's real session state aside. Called on the holder and on everyone who receives
-- a preview session.
function Preview:Enter()
	if stash then
		return
	end
	local Session = PLC.Session
	stash = {}
	for _, field in ipairs(STASHED_FIELDS) do
		stash[field] = Session[field]
	end
	Session.items, Session.responses = {}, {}
	Session.nextIdx = 1
	Session.state = "inactive"
	Session.owner, Session.sessionId, Session.council, Session.responseSet = nil, nil, nil, nil
	Session.isCollector = false
	Session.preview = true
	notifyOptions()
end

-- Puts the real session state back.
function Preview:Leave()
	if not stash then
		return
	end
	local Session = PLC.Session
	for _, field in ipairs(STASHED_FIELDS) do
		Session[field] = stash[field]
	end
	stash = nil
	Session.preview = false
	notifyAll()
end

local function shuffled(list)
	local copy = {}
	for i, value in ipairs(list) do
		copy[i] = value
	end
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function previewEntry(idx, source)
	return {
		idx = idx,
		itemString = "item:" .. source.id,
		quality = source.quality,
		bagged = true,
		itemGUID = "preview-" .. idx, -- never matches a real bag item, so BagTracker leaves it alone
		bossName = L["PREVIEW_LABEL"],
		instance = L["PREVIEW_LABEL"],
	}
end

local function buildItems()
	local items = {}
	local pool = shuffled(POOL)
	for idx, seconds in ipairs(TRADE_SECONDS) do
		local entry = previewEntry(idx, pool[idx])
		entry.tradeRemaining = seconds
		entry.untradable = seconds == 0 or nil
		items[idx] = entry
	end
	local boeIdx = #items + 1
	items[boeIdx] = previewEntry(boeIdx, BOE_ITEM)
	items[boeIdx].boe = true
	return items
end

function Preview:Start()
	local Session = PLC.Session
	if Session.preview then
		print(L["CHAT_PREFIX"] .. L["PREVIEW_ALREADY_RUNNING"])
		return
	end
	if Session.state == "active" then
		print(L["CHAT_PREFIX"] .. L["PREVIEW_SESSION_RUNNING"])
		return
	end
	if not Session:CanStart() then
		print(L["CHAT_PREFIX"] .. L["SESSION_ONLY_ML_STARTS"])
		return
	end
	self:Enter()
	local items = buildItems()
	Session:ApplyItems(items)
	Session.nextIdx = #items + 1
	Session:Start()
	print(L["CHAT_PREFIX"] .. L["PREVIEW_STARTED"])
	PLC.UI.SessionFrame:Open()
end

-- Ends the preview. `message` overrides the usual chat line (real loot arrived).
function Preview:Stop(message)
	local Session = PLC.Session
	if not Session.preview then
		return
	end
	stopping = true
	if Session:IsHolder() then
		Session:End()
	end
	if Session:IsOwner() then
		PLC.Comms.Sync:SendPreviewEnd(Session.sessionId)
	end
	stopping = false
	self:Leave()
	print(L["CHAT_PREFIX"] .. (message or L["PREVIEW_ENDED"]))
end

-- A preview finishes by itself once its review is over and nothing awarded is left to trade.
function Preview:CheckFinished()
	local Session = PLC.Session
	if not Session.preview or stopping or Session.state == "active" or not Session:IsOwner() then
		return
	end
	for _, item in pairs(Session.items) do
		if item.awarded and not item.traded then
			return
		end
	end
	self:Stop()
end

function Preview:OnPreviewEndReceived(data)
	local Session = PLC.Session
	if Session.preview and data.sessionId and data.sessionId == Session.sessionId then
		self:Leave()
		print(L["CHAT_PREFIX"] .. L["PREVIEW_ENDED"])
	end
end

function Preview:Toggle()
	if PLC.Session.preview then
		self:Stop()
	else
		self:Start()
	end
end

PLC:RegisterSlashCommand("preview", L["SLASH_PREVIEW"], function()
	Preview:Toggle()
end)
