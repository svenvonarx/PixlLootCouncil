local ADDON_NAME, PLC = ...

local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

AceAddon:NewAddon(PLC, ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0", "AceComm-3.0", "AceBucket-3.0")

function PLC:OnInitialize()
	self.db = AceDB:New(ADDON_NAME .. "DB", self.Defaults, true)
	self.ErrorHandler:AttachDB(self.db)
end

-- Modules hook into the enable sequence via PLC:RegisterOnEnable instead of Init.lua needing to
-- know every module by name -- keeps this file stable as later stages add Roster/Session/etc.
local onEnableCallbacks = {}

function PLC:RegisterOnEnable(fn)
	table.insert(onEnableCallbacks, fn)
end

function PLC:OnEnable()
	self.Events:RegisterAll()
	for _, fn in ipairs(onEnableCallbacks) do
		fn()
	end
end

-- Slash command router ---------------------------------------------------
-- Modules register their own subcommands via PLC:RegisterSlashCommand instead of each adding
-- its own /plc-prefixed chat command, so `/plc` alone always lists everything available.

local subcommands = {}

function PLC:RegisterSlashCommand(name, description, handler)
	subcommands[name:lower()] = { description = description, handler = handler }
end

local function printHelp()
	print(L["CHAT_PREFIX"] .. L["CMD_HELP_HEADER"])
	local names = {}
	for name in pairs(subcommands) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		print(string.format("  /plc %s - %s", name, subcommands[name].description))
	end
end

function PLC:SlashHandler(input)
	input = input and strtrim(input) or ""
	if input == "" then
		printHelp()
		return
	end
	local cmd, rest = input:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local entry = subcommands[cmd]
	if not entry then
		print(L["CHAT_PREFIX"] .. string.format(L["CMD_UNKNOWN"], cmd))
		return
	end
	entry.handler(rest)
end

PLC:RegisterChatCommand("plc", "SlashHandler")

PLC:RegisterSlashCommand("errors", "Show the captured error/taint log", function()
	local entries = PLC.ErrorHandler:GetEntries()
	if #entries == 0 then
		print(L["CHAT_PREFIX"] .. L["ERROR_LOG_EMPTY"])
		return
	end
	for _, entry in ipairs(entries) do
		print(L["CHAT_PREFIX"] .. string.format(L["ERROR_LOG_ENTRY"], date("%H:%M:%S", entry.time), entry.message))
	end
end)

PLC:RegisterSlashCommand("errortest", "Trigger and log a test error", function()
	PLC.ErrorHandler:LogError("manual /plc errortest trigger")
	print(L["CHAT_PREFIX"] .. L["TEST_ERROR_TRIGGERED"])
end)
