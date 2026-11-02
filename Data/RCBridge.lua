local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Lets a raider answer a master looter who runs RCLootCouncil, with this addon instead of RC. Only
-- the candidate's side of RC's protocol (RCLootCouncil/core.lua, Modules/lootFrame.lua):
--   lootTable, lt_add    items to respond to, shown in UI/LootFrame.lua like any other session
--   mldb                 the master's buttons and timeout
--   reroll, re_roll      items sent out again, or a request to /roll on them
--   session_end          the session is over
--   playerInfoRequest    answered so the master's grid shows this player's role and item level
-- and it sends lootAck (without one the master shows "Offline or RCLootCouncil not installed"),
-- response and roll. Council voting and auto pass aren't covered. With RC itself running on this
-- client this stays off, since the master would get two answers. Nothing here touches PLC.Session:
-- the two kinds of session can't get in each other's way, and nothing is saved, because the master
-- resends everything when asked with "reconnect".
local RCBridge = {}
PLC.RCBridge = RCBridge

local ROLL_KEY = "ROLL"
local SKIP_ROLL_KEY = "SKIP_ROLL"
local PASS_KEY = "PASS"
local ROLL_TIMEOUT = 3
local CACHE_RETRY_SECONDS = 0.2
local CACHE_RETRIES = 50
local MLDB_RETRY_SECONDS = 1
local MLDB_RETRIES = 3

-- RC's short keys for the master's settings (RCLootCouncil/Classes/Data/MLDB.lua).
local MLDB_KEYS = {
	["|5"] = "numButtons", ["|8"] = "buttons", ["|10"] = "requireNotes", ["|11"] = "responses",
	["|12"] = "timeout", ["|13"] = "outOfRaid", ["|14"] = "default", ["|15"] = "text", ["|16"] = "color",
	["|18"] = "requireNotes",
}

-- RC's translation from an item's slot to the "WEAPON" button group (RCLootCouncil/Core/Constants.lua).
local WEAPON_TYPE_CODES = {
	INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_WEAPON = true,
	INVTYPE_THROWN = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_HOLDABLE = true,
}

local FIRST_GEAR_SLOT, LAST_GEAR_SLOT = 1, 18
local SHIRT_SLOT = 4

RCBridge.enabled = false -- set on login unless RC itself is running here
RCBridge.authority = nil -- who we last asked for the session state
RCBridge.master = nil -- who sent the current items
RCBridge.mldb = nil
RCBridge.items = {} -- [session] = { session, link, icon, ilvl, equipLoc, typeCode, isRoll, deadlineAt, answered }

local responseSets = {} -- [button group] = the buttons for UI/LootFrame.lua, rebuilt with each mldb
local tickHandle
local pendingRoll -- { sessions, timer } while waiting for our /roll in chat
local rollPattern

function RCBridge:IsActive()
	return self.enabled and PLC.db.profile.rcBridge
end

local function notify()
	if PLC.UI and PLC.UI.LootFrame then
		PLC.UI.LootFrame:Refresh()
	end
end

local function restoreKeys(value)
	if type(value) ~= "table" then
		return value
	end
	local restored = {}
	for k, v in pairs(value) do
		restored[MLDB_KEYS[k] or k] = restoreKeys(v)
	end
	return restored
end

local function buttonGroupFor(typeCode)
	local buttons = RCBridge.mldb and RCBridge.mldb.buttons
	if not buttons then
		return nil
	end
	if buttons[typeCode] and typeCode ~= "default" then
		return buttons[typeCode]
	end
	return WEAPON_TYPE_CODES[typeCode] and buttons.WEAPON or nil
end

-- The buttons for an item, as UI/LootFrame.lua wants them: RC's are numbered, and that number is
-- the answer it expects back. The master only sends what differs from RC's defaults.
local function responseSetFor(typeCode)
	local group = buttonGroupFor(typeCode)
	local key = group and typeCode or "default"
	if responseSets[key] then
		return responseSets[key]
	end

	local set = {}
	if group then
		for i, button in ipairs(group) do
			set[i] = { key = i, text = button.text or tostring(i), requireNotes = button.requireNotes }
		end
	else
		local mldb = RCBridge.mldb or {}
		local default = mldb.buttons and mldb.buttons.default or {}
		local builtIn = { _G.NEED, _G.GREED, L["RC_MINOR_UPGRADE"] }
		for i = 1, default.numButtons or mldb.numButtons or #builtIn do
			local button = default[i] or {}
			set[i] = { key = i, text = button.text or builtIn[i] or tostring(i), requireNotes = button.requireNotes }
		end
	end
	table.insert(set, { key = PASS_KEY, text = _G.PASS })
	responseSets[key] = set
	return set
end

local function rollSet()
	responseSets[ROLL_KEY] = responseSets[ROLL_KEY]
		or { { key = ROLL_KEY, text = _G.ROLL }, { key = SKIP_ROLL_KEY, text = _G.PASS } }
	return responseSets[ROLL_KEY]
end

local function setFor(item)
	return item.isRoll and rollSet() or responseSetFor(item.typeCode)
end

local function cleanItemString(link)
	local itemString = link and link:match("item:[%d:-]+")
	return itemString and (itemString:gsub(":+$", ""):gsub("^item:", "")) or nil
end

local function itemLevelOf(link)
	return (select(4, C_Item.GetItemInfo(link)))
end

-- What this client has in the slots the item competes for, and the item level difference, the way
-- RC reports them. Items without a slot, such as tier tokens, have neither.
local function compareWithGear(item)
	local slots = item.equipLoc and PLC.Gear:SlotsForEquipLoc(UnitGUID("player"), item.equipLoc)
	if not slots then
		return nil, nil, 0
	end
	local gear1 = slots[1] and GetInventoryItemLink("player", slots[1])
	local gear2 = slots[2] and GetInventoryItemLink("player", slots[2])
	local level1, level2 = gear1 and itemLevelOf(gear1), gear2 and itemLevelOf(gear2)
	local lowest = level1 and level2 and math.min(level1, level2) or level1 or level2
	return gear1, gear2, lowest and item.ilvl and (item.ilvl - lowest) or 0
end

-- The client has no GetAverageItemLevel here, so this is RC Classic's own calculation.
local function averageItemLevel()
	local sum, count = 0, 0
	for slot = FIRST_GEAR_SLOT, LAST_GEAR_SLOT do
		local link = slot ~= SHIRT_SLOT and GetInventoryItemLink("player", slot)
		if link then
			sum = sum + (itemLevelOf(link) or 0)
			count = count + 1
		end
	end
	return count > 0 and math.floor(sum / count * 100 + 0.5) / 100 or 0
end

-- Tells the group we have these items. specID is always 0 here, like RC on this client: nil would
-- leave a hole in the arguments (see Comms/RCWire.lua).
local function sendLootAck(items)
	local ack = { gear1 = {}, gear2 = {}, diff = {}, response = {} }
	local rolls = {}
	for session, item in pairs(items) do
		local gear1, gear2, diff = compareWithGear(item)
		ack.gear1[session] = cleanItemString(gear1)
		ack.gear2[session] = cleanItemString(gear2)
		ack.diff[session] = diff
		if item.isRoll then
			rolls[session] = "?"
		end
	end
	if next(rolls) then
		ack.roll = rolls
	end
	local Wire = PLC.Comms.RCWire
	Wire:Send(Wire.MAIN, "group", "lootAck", 0, averageItemLevel(), ack)
end

local function sendResponse(session, response, note)
	local Wire = PLC.Comms.RCWire
	Wire:Send(Wire.MAIN, "group", "response", session, { response = response, note = note })
end

local function sendRoll(roll, sessions)
	local Wire = PLC.Comms.RCWire
	Wire:Send(Wire.MAIN, "group", "roll", Wire:GetFullName(), roll, sessions)
end

local function sendPlayerInfo()
	local Wire = PLC.Comms.RCWire
	local myGuid = UnitGUID("player")
	local key = PLC.Professions.ENCHANTING_KEY
	local enchanting = PLC.Professions.known[myGuid] and PLC.Professions.known[myGuid][key]
	local _, rank = GetGuildInfo("player")
	Wire:Send(Wire.MAIN, "group", "pI", UnitGroupRolesAssigned("player") or "NONE", rank or "",
		enchanting ~= nil, enchanting and enchanting.skillLevel or 0, averageItemLevel(), 0)
end

local function stopTicking()
	if tickHandle then
		PLC:CancelTimer(tickHandle)
		tickHandle = nil
	end
end

-- Out of time: RC's own answer, so the master sees it rather than a stuck "selecting response".
local function tick()
	local now = time()
	local waiting = false
	for session, item in pairs(RCBridge.items) do
		if not item.answered then
			if item.deadlineAt and now >= item.deadlineAt then
				item.answered = true
				if item.isRoll then
					sendRoll("-", { session })
				else
					sendResponse(session, "TIMEOUT")
				end
			else
				waiting = true
			end
		end
	end
	if not waiting then
		stopTicking()
	end
	notify()
end

local function startTicking()
	if not tickHandle then
		tickHandle = PLC:ScheduleRepeatingTimer(tick, 1)
	end
end

function RCBridge:Clear()
	stopTicking()
	wipe(self.items)
	self.master = nil
	if pendingRoll then
		PLC:CancelTimer(pendingRoll.timer)
		pendingRoll = nil
	end
	notify()
end

local function buildItem(session, entry)
	local itemString = "item:" .. tostring(entry.string)
	local _, link, _, ilvl, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(itemString)
	local timeout = RCBridge.mldb and RCBridge.mldb.timeout
	return {
		session = session,
		link = link,
		icon = icon,
		ilvl = ilvl,
		equipLoc = equipLoc,
		typeCode = entry.typeCode or "default",
		isRoll = entry.isRoll,
		deadlineAt = type(timeout) == "number" and (time() + timeout) or nil,
	}
end

local function allCached(lootTable)
	for _, entry in pairs(lootTable) do
		if not C_Item.GetItemInfo("item:" .. tostring(entry.string)) then
			return false
		end
	end
	return true
end

local function outOfRaid()
	return RCBridge.mldb and RCBridge.mldb.outOfRaid and GetNumGroupMembers() >= 8 and not IsInInstance()
end

-- `replace`: a new session, rather than items added to the running one. RC's items may be new to
-- this client, so this waits for them, and for the master's settings if they haven't arrived.
local function receiveItems(lootTable, sender, replace, attempt)
	attempt = attempt or 0
	if not RCBridge.mldb and attempt < MLDB_RETRIES then
		local Wire = PLC.Comms.RCWire
		if attempt == 0 then
			Wire:Send(Wire.MAIN, sender, "MLdb_request")
		end
		PLC:ScheduleTimer(function()
			receiveItems(lootTable, sender, replace, attempt + 1)
		end, MLDB_RETRY_SECONDS)
		return
	end
	if not allCached(lootTable) and attempt < CACHE_RETRIES then
		PLC:ScheduleTimer(function()
			receiveItems(lootTable, sender, replace, attempt + 1)
		end, CACHE_RETRY_SECONDS)
		return
	end

	if replace then
		wipe(RCBridge.items)
	end
	if not RCBridge.master then
		print(L["CHAT_PREFIX"] .. string.format(L["RC_SESSION_STARTED"], PLC.Roster:ShortName(sender)))
	end
	RCBridge.master = sender

	local items = {}
	for key, entry in pairs(lootTable) do
		local session = entry.session or key
		items[session] = buildItem(session, entry)
		RCBridge.items[session] = items[session]
	end

	if outOfRaid() then
		for session, item in pairs(items) do
			item.answered = true
			sendResponse(session, "NOTINRAID")
		end
		return
	end
	sendLootAck(items)
	startTicking()
	notify()
end

-- UI/LootFrame.lua's rows for what's still unanswered.
function RCBridge:GetRows()
	local rows = {}
	if not self:IsActive() then
		return rows
	end
	local timeout = self.mldb and self.mldb.timeout
	for session, item in pairs(self.items) do
		if not item.answered then
			table.insert(rows, {
				id = "rc" .. session,
				idx = session,
				link = item.link,
				icon = item.icon,
				deadlineAt = item.deadlineAt,
				timeoutSeconds = type(timeout) == "number" and timeout or 60,
				responses = setFor(item),
				ownerName = self.master and PLC.Roster:ShortName(self.master) or "?",
				respond = function(key, note)
					self:Respond(session, key, note)
				end,
			})
		end
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

-- Every button set in this session, answered items included, so the window's buttons don't get
-- rebuilt under someone typing a note just because one kind of item has been answered.
function RCBridge:GetResponseSets()
	local sets = {}
	if not self:IsActive() then
		return sets
	end
	for _, item in pairs(self.items) do
		sets[setFor(item)] = true
	end
	return sets
end

function RCBridge:Respond(session, key, note)
	local item = self.items[session]
	if not item or item.answered then
		return
	end
	if key == ROLL_KEY then
		if pendingRoll then
			return
		end
		item.answered = true
		pendingRoll = { sessions = { session } }
		pendingRoll.timer = PLC:ScheduleTimer(function()
			pendingRoll = nil
		end, ROLL_TIMEOUT)
		RandomRoll(1, 100)
	elseif key == SKIP_ROLL_KEY then
		item.answered = true
		sendRoll("-", { session })
	else
		for _, button in ipairs(setFor(item)) do
			if button.key == key and button.requireNotes and not note then
				print(L["CHAT_PREFIX"] .. string.format(L["RC_NOTE_REQUIRED"], button.text))
				return
			end
		end
		item.answered = true
		sendResponse(session, key, note)
	end
	notify()
end

local function onSystemMessage(_, message)
	if not pendingRoll then
		return
	end
	if not rollPattern then
		-- RANDOM_ROLL_RESULT is "%s rolls %d (%d-%d)"; deDE and others use numbered placeholders.
		rollPattern = RANDOM_ROLL_RESULT:gsub("[%(%)%-]", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
			:gsub("%%%d%$s", "(.+)"):gsub("%%%d%$d", "(%%d+)")
	end
	local name, roll, low, high = message:match(rollPattern)
	if name == UnitName("player") and tonumber(low) == 1 and tonumber(high) == 100 then
		PLC:CancelTimer(pendingRoll.timer)
		sendRoll(tonumber(roll), pendingRoll.sessions)
		pendingRoll = nil
	end
end

-- Called by Data/Roster.lua after every rebuild. Someone logging in, reloading or joining the group
-- asks the master for the session once, and again if the master changes: RC ignores this unless the
-- master is running it, and otherwise answers with its settings and any running session.
function RCBridge:OnRosterRebuilt()
	if not self:IsActive() then
		return
	end
	if not IsInGroup() then
		self.authority = nil
		self.mldb = nil
		wipe(responseSets)
		if next(self.items) then
			self:Clear()
		end
		return
	end
	local authority = PLC.CouncilRules:GetLootAuthorityName()
	if not authority or authority == self.authority then
		return
	end
	self.authority = authority
	self.mldb = nil
	wipe(responseSets)
	if authority ~= UnitName("player") then
		local Wire = PLC.Comms.RCWire
		sendPlayerInfo()
		Wire:Send(Wire.MAIN, authority, "reconnect")
	end
end

local function fromMaster(handler)
	return function(data, sender)
		if RCBridge:IsActive() and PLC.CouncilRules:IsLootAuthority(sender) then
			handler(data, sender)
		end
	end
end

PLC.Events:RegisterHandler("CHAT_MSG_SYSTEM", onSystemMessage)

PLC:RegisterOnEnable(function()
	local Wire = PLC.Comms.RCWire
	if Wire:IsRCRunning() then
		return
	end
	RCBridge.enabled = true

	Wire:Register(Wire.MAIN, "mldb", fromMaster(function(data)
		RCBridge.mldb = restoreKeys(data[1])
		wipe(responseSets)
		notify()
	end))
	Wire:Register(Wire.MAIN, "lootTable", fromMaster(function(data, sender)
		receiveItems(data[1], sender, true)
	end))
	Wire:Register(Wire.MAIN, "lt_add", fromMaster(function(data, sender)
		receiveItems(data[1], sender, false)
	end))
	Wire:Register(Wire.MAIN, "reroll", fromMaster(function(data, sender)
		receiveItems(data[1], sender, false)
	end))
	Wire:Register(Wire.MAIN, "re_roll", fromMaster(function(data, sender)
		local me = UnitGUID("player"):gsub("Player%-", "")
		for _, candidate in ipairs(data[1]) do
			if candidate == me then
				receiveItems(data[2], sender, false)
				return
			end
		end
	end))
	Wire:Register(Wire.MAIN, "session_end", fromMaster(function(_, sender)
		if next(RCBridge.items) then
			print(L["CHAT_PREFIX"] .. string.format(L["RC_SESSION_ENDED"], PLC.Roster:ShortName(sender)))
		end
		RCBridge:Clear()
	end))
	Wire:Register(Wire.MAIN, "playerInfoRequest", fromMaster(function()
		sendPlayerInfo()
	end))
end)
