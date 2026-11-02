local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.Loot = PLC.Loot or {}
local Announce = {}
PLC.Loot.Announce = Announce

-- Shared by Comms/Sync.lua (send) and this file (chat post): resolves to whatever group channel
-- currently exists. This is a transport detail only -- it never gates session validity (see
-- docs/SPECIFICATION.md §5.1/§5.3).
function Announce:GetChannel()
	if IsPartyLFG and IsPartyLFG() then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
	return nil
end

-- ML-only: gate every chat post on being the session holder so only one client ever announces,
-- never both the holder and e.g. a council member who also has the addon.
local function iAmHolder()
	return PLC.Session and PLC.Session.IsHolder and PLC.Session:IsHolder()
end

-- The global SendChatMessage only exists as a deprecation shim here, so prefer the real one.
local function post(text, channel)
	if PLC.Session.preview then
		text = L["PREVIEW_CHAT_TAG"] .. text
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	send(text, channel)
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
