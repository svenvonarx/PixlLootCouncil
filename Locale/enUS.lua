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
