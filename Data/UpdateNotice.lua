local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

-- Tells someone on an old version to update, like ElvUI does, and stays out of the way doing it:
--   * one chat line a day at most, however often they log in or reload
--   * a pop-up only when they're a whole version behind (0.3 -> 0.4), not for a patch. Once per
--     version, and it waits until they're out of combat, out of instances and out of a loot session
--   * Options -> About turns both off
-- Data/Presence.lua finds out about newer versions. Knowing about one survives logging out, so a
-- raider who heard about it last night is reminded before the next raid, not during it.
local UpdateNotice = {}
PLC.UpdateNotice = UpdateNotice

local CHAT_COOLDOWN = 86400
local LOGIN_DELAY = 10 -- past the wall of chat every addon prints while loading
-- Nobody's mentioned it for this long, so it may never have been real: anyone can claim any version.
local FORGET_AFTER = 14 * 86400

local function saved()
	return PLC.db.global.update
end

local function tellInChat(newest)
	local update = saved()
	if update.chatVersion == newest and time() - (update.chatAt or 0) < CHAT_COOLDOWN then
		return
	end
	update.chatVersion, update.chatAt = newest, time()
	print(L["CHAT_PREFIX"] .. string.format(L["UPDATE_CHAT"], newest, PLC.version))
end

local function showPopup(newest)
	local update = saved()
	if update.popupVersion == newest or not PLC.Presence.IsBigUpdate(newest, PLC.version) then
		return
	end
	if InCombatLockdown() or IsInInstance() or PLC.Session.state == "active" then
		return -- PLAYER_REGEN_ENABLED and PLAYER_ENTERING_WORLD below try again
	end
	update.popupVersion = newest
	StaticPopup_Show("PIXLLOOTCOUNCIL_UPDATE", newest, PLC.version)
end

function UpdateNotice:Notify()
	local newest = PLC.Presence.newest
	if newest and PLC.db.profile.updateNotices then
		tellInChat(newest)
		showPopup(newest)
	end
end

function UpdateNotice:Remember(version)
	local update = saved()
	update.version, update.seenAt = version, time()
end

local function retryPopup()
	local newest = PLC.Presence.newest
	if newest and PLC.db.profile.updateNotices then
		showPopup(newest)
	end
end

-- No text box for the link: it would grab the keyboard from someone who's walking around. The About
-- page has it to copy.
StaticPopupDialogs["PIXLLOOTCOUNCIL_UPDATE"] = {
	text = L["UPDATE_POPUP"],
	button1 = L["UPDATE_POPUP_WHERE"],
	button2 = CLOSE,
	OnAccept = function()
		PLC.UI.OptionsFrame:Open("about")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

PLC.Events:RegisterHandler("PLAYER_REGEN_ENABLED", retryPopup)
PLC.Events:RegisterHandler("PLAYER_ENTERING_WORLD", retryPopup)

PLC:RegisterOnEnable(function()
	local update = saved()
	if update.version and PLC.Presence.IsNewer(update.version, PLC.version)
		and time() - (update.seenAt or 0) < FORGET_AFTER then
		PLC.Presence.newest = update.version
		PLC:ScheduleTimer(function()
			UpdateNotice:Notify()
		end, LOGIN_DELAY)
	else
		wipe(update) -- updated since, or it was never real
	end
end)
