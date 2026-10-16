local L = LibStub("AceLocale-3.0"):NewLocale("PixlLootCouncil", "enUS", true)
if not L then return end

L["ADDON_NAME"] = "PixlLootCouncil"
L["CHAT_PREFIX"] = "|cffE8A33D[PixlLootCouncil]|r "

L["CMD_HELP_HEADER"] = "PixlLootCouncil slash commands:"
L["CMD_UNKNOWN"] = "Unknown command: %s. Type /plc for help."

L["ERROR_LOG_EMPTY"] = "No errors recorded."
L["ERROR_LOG_ENTRY"] = "[%s] %s"
L["ERROR_LOG_CAPTURED"] = "An error was captured and logged (%s). Use /plc errors to review."
L["TEST_ERROR_TRIGGERED"] = "Test error triggered and logged."

L["TAINT_BLOCKED"] = "Blocked action captured: %s"
L["TAINT_FORBIDDEN"] = "Forbidden action captured: %s"

L["ROSTER_EMPTY"] = "Roster is empty (not in a group?)."
L["ROSTER_ENTRY"] = "%s (%s) role=%s online=%s council=%s"

L["LOOT_METHOD_NOT_MASTER"] = "This group's loot method isn't Master Loot -- PixlLootCouncil can't run a session until it is."
L["DEBUG_ON"] = "Debug logging enabled."
L["DEBUG_OFF"] = "Debug logging disabled."
L["DETECTED_SLOT"] = "Detected loot slot %d: %s (quality %s)"

L["AWARD_SUCCESS"] = "Awarded %s to %s."
L["AWARD_FAILED"] = "Could not award %s to %s: %s"
L["AWARD_TIMEOUT"] = "Award of %s to %s timed out -- no confirmation received."

L["CANGIVE_NO_SLOT"] = "no such loot slot"
L["CANGIVE_LOOT_CLOSED"] = "loot window is not open"
L["CANGIVE_ITEM_CHANGED"] = "the item in that slot has changed"
L["CANGIVE_NO_BAG_SPACE"] = "not enough bag space"
L["CANGIVE_NOT_IN_GROUP"] = "player is not in your group"

L["ANNOUNCE_SESSION_START"] = "[PixlLootCouncil] Loot session started with %d item(s) -- check your Loot Response window!"
L["ANNOUNCE_AWARD"] = "[PixlLootCouncil] %s awarded to %s"
L["ANNOUNCE_DISENCHANT"] = "[PixlLootCouncil] %s sent to disenchant"

L["COMMS_UNKNOWN_VERSION"] = "Ignored a message using protocol version %s (newer than this client understands)."

L["SESSION_ALREADY_ACTIVE"] = "A loot session is already active."
L["SESSION_STARTED"] = "Loot session started."
L["SESSION_STARTED_BY"] = "%s started a loot session."
L["SESSION_NOT_HOLDER"] = "You are not holding the current loot session."
L["SESSION_ENDED"] = "Loot session ended."
L["SESSION_CANNOT_FORCE_END"] = "Cannot force-end: the holder's heartbeat hasn't gone stale yet."
L["SESSION_FORCE_ENDED"] = "Loot session force-ended."
L["SESSION_FORCE_ENDED_BY"] = "%s force-ended the loot session (holder unresponsive)."
L["SESSION_SYNCED"] = "Loot session synced from the holder."
L["SESSION_RESTORED"] = "Restored your active loot session."
L["SESSION_USAGE"] = "Usage: /plc session forceend|sync"
L["SESSION_ADDITEM_USAGE"] = "Usage: /plc additem <itemID or itemLink>"
L["SESSION_ADDITEM_UNKNOWN"] = "Could not resolve that item -- check the itemID/link, or try again once it's cached."
L["SESSION_ADDITEM_SUCCESS"] = "Added %s to the session."
L["SESSION_ALREADY_AWARDED"] = "That item has already been awarded."
L["SESSION_AWARD_UNKNOWN_WINNER"] = "Could not find that player in the roster."
L["SESSION_AWARD_TRADE_INSTRUCTION"] = "%s awarded to %s -- trade it to them!"
L["SESSION_DISENCHANT_INSTRUCTION"] = "%s sent to %s for disenchant!"
L["SESSION_AWARD_ALL_RESULT"] = "Awarded %d pre-awarded item(s)."

L["VOTINGFRAME_AWARD"] = "Award"
L["VOTINGFRAME_DISENCHANT"] = "Disenchant"
L["VOTINGFRAME_DISENCHANT_TARGET"] = "Will go to: %s"
L["VOTINGFRAME_STAGED"] = "Staged"
L["VOTINGFRAME_WAITING"] = "Waiting for response..."
L["VOTINGFRAME_NO_ADDON"] = "No addon detected"
L["VOTINGFRAME_VOTE_COUNT"] = "%d out of %d have voted"

L["SESSIONFRAME_TITLE"] = "Loot Session"
L["SESSIONFRAME_START"] = "Start Session"
L["SESSIONFRAME_END"] = "End Session"
L["SESSIONFRAME_AWARDALL"] = "Award All"
L["SESSIONFRAME_REMOVE"] = "Remove"
L["SESSIONFRAME_AWARDED_TO"] = "Awarded: %s"
L["SESSIONFRAME_PREAWARDED_TO"] = "Staged: %s"
L["SESSIONFRAME_DISENCHANTED"] = "Disenchanted"
L["SESSIONFRAME_STAGED_DISENCHANT"] = "Staged: Disenchant (%s)"
L["SESSIONFRAME_PENDING"] = "Pending"
L["SESSIONFRAME_EXPIRED"] = "Expired"
L["SESSIONFRAME_TIME_LEFT"] = "Time left: %ds"
L["SESSIONFRAME_ENCHANTER_LABEL"] = "Enchanter:"
-- Not window-prefixed -- shared by both UI/SessionFrame.lua's and UI/LootFrame.lua's header,
-- since whoever's holding the session matters just as much to a candidate deciding how to
-- respond as it does to the holder's own window.
L["STARTED_BY_LABEL"] = "Session started by %s"
L["SESSIONFRAME_NO_ITEMS"] = "No items yet -- loot something above the quality threshold."

L["LOOTFRAME_TITLE"] = "Loot Response"
L["LOOTFRAME_NOTE_PLACEHOLDER"] = "Optional Note..."

L["OPTIONS_TITLE"] = "PixlLootCouncil Options"
L["OPTIONS_SECTION_RAID"] = "RAID TOOLS"
L["OPTIONS_SECTION_SETTINGS"] = "SETTINGS"
L["OPTIONS_TAB_GENERAL"] = "General"
L["OPTIONS_TAB_RESPONSES"] = "Responses"
L["OPTIONS_TAB_COUNCIL"] = "Council"
L["OPTIONS_TAB_APPEARANCE"] = "Appearance"

L["OPTIONS_ANNOUNCE_START"] = "Announce session start in chat"
L["OPTIONS_ANNOUNCE_AWARD"] = "Announce awards in chat"
L["OPTIONS_LOOT_THRESHOLD"] = "Minimum item quality"
L["OPTIONS_HEARTBEAT_SECONDS"] = "Holder heartbeat interval (seconds)"
L["OPTIONS_FORCE_END_MINUTES"] = "Force-end after holder is unresponsive for (minutes)"
L["OPTIONS_RESPONSE_TIMEOUT"] = "Response deadline per item (seconds)"

L["OPTIONS_COUNCIL_MODE"] = "Council membership"
L["OPTIONS_COUNCIL_MODE_RAIDASSIST"] = "Master looter, leader, and assistants"
L["OPTIONS_COUNCIL_MODE_MANUAL"] = "Manual list"
L["OPTIONS_COUNCIL_MODE_MLONLY"] = "Master looter only"
L["OPTIONS_COUNCIL_MODE_HINT"] = "Controls who can vote and award loot."

L["OPTIONS_ACCENT_COLOR"] = "Accent color"
