local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local Announce = {}
PLC.Loot.Announce = Announce

-- Shared by Comms/Sync.lua (send) and this file (chat post): the raid or party itself. This is a
-- transport detail only -- it never gates session validity (see docs/SPECIFICATION.md §5.1/§5.3).
-- Always the home group, never a battleground's: asked without a category, the game answers for
-- whichever group is active, which for someone who queued into a battleground from the raid is the
-- battleground, and the session would go to the wrong people.
local HOME = LE_PARTY_CATEGORY_HOME or 1

function Announce:GetChannel()
	if IsInRaid(HOME) then
		return "RAID"
	elseif IsInGroup(HOME) then
		return "PARTY"
	end
	return nil
end

-- ML-only: gate every chat post on being the session holder so only one client ever announces,
-- never both the holder and e.g. a council member who also has the addon.
local function iAmHolder()
	return PLC.Session and PLC.Session.IsHolder and PLC.Session:IsHolder()
end

-- Chat lines go out one a second: sent all at once, as after Award All, the server dropped some.
-- ChatThrottleLib also holds a line back while the server says it's too much, and keeps the
-- addon's chat within its share of what the client may send.
local SPACING = 1
local queue = {}
local sending = false

local function sendNext()
	local line = table.remove(queue, 1)
	if not line then
		sending = false
		return
	end
	if ChatThrottleLib and ChatThrottleLib.SendChatMessage then
		ChatThrottleLib:SendChatMessage("NORMAL", "PLC", line.text, line.channel)
	else
		-- The global SendChatMessage only exists as a deprecation shim here, so prefer the real one.
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		send(line.text, line.channel)
	end
	PLC:ScheduleTimer(sendNext, SPACING)
end

local function post(text, channel)
	if PLC.Session.preview then
		text = L["PREVIEW_CHAT_TAG"] .. text
	end
	table.insert(queue, { text = text, channel = channel })
	if not sending then
		sending = true
		sendNext()
	end
end

-- One summary line, not one per item -- the per-item breakdown belongs in each candidate's
-- UI/LootFrame.lua window, not raid chat.
function Announce:AnnounceSessionStart(items)
	if not (iAmHolder() and PLC.db.profile.announce.sessionStart) then
		return
	end
	local channel = self:GetChannel()
	if not channel then
		return
	end
	local count = 0
	for _ in pairs(items) do
		count = count + 1
	end
	post(string.format(L["ANNOUNCE_SESSION_START"], count), channel)
end

function Announce:AnnounceAward(entry)
	if not (iAmHolder() and PLC.db.profile.announce.award) then
		return
	end
	local channel = self:GetChannel()
	if not channel then
		return
	end
	-- Disenchant deliberately omits the winner name -- the Enchanter isn't "the winner" the way a
	-- regular award's recipient is, just the designated hand it passes through.
	if entry.reason == "disenchant" then
		post(string.format(L["ANNOUNCE_DISENCHANT"], entry.link), channel)
	elseif entry.reason == "bank" then
		post(string.format(L["ANNOUNCE_BANK"], entry.link), channel)
	else
		post(string.format(L["ANNOUNCE_AWARD"], entry.link, entry.winnerName), channel)
	end
end
