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
L["AWARD_USAGE"] = "Usage: /plc award <slot> <playerName>"

L["CANGIVE_NO_SLOT"] = "no such loot slot"
L["CANGIVE_LOOT_CLOSED"] = "loot window is not open"
L["CANGIVE_ITEM_CHANGED"] = "the item in that slot has changed"
L["CANGIVE_NO_BAG_SPACE"] = "not enough bag space"
L["CANGIVE_NOT_IN_GROUP"] = "player is not in your group"
L["CANGIVE_OFFLINE"] = "player is offline"
L["CANGIVE_NOT_ELIGIBLE"] = "player is not an eligible master loot candidate for this item"

L["ANNOUNCE_ITEM"] = "[PixlLootCouncil] Item up for council: %s"
L["ANNOUNCE_AWARD"] = "[PixlLootCouncil] %s awarded to %s"

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
L["SESSION_USAGE"] = "Usage: /plc session start|end|forceend|sync|respond <idx> <response>"
