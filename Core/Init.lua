local ADDON_NAME, PLC = ...

local AceAddon = LibStub("AceAddon-3.0")
local AceDB = LibStub("AceDB-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

AceAddon:NewAddon(PLC, ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0", "AceComm-3.0", "AceBucket-3.0")

function PLC:OnInitialize()
	self.db = AceDB:New(ADDON_NAME .. "DB", self.Defaults, true)
	-- Loot history in its own SavedVariables, mirroring RCLootCouncil's RCLootCouncilLootDB:
	-- lootDB.factionrealm[fullName] = { entry, ... } (see Data/History.lua).
	self.lootDB = AceDB:New(ADDON_NAME .. "LootDB")
	self.ErrorHandler:AttachDB(self.db)
end

-- Modules hook into the enable sequence via PLC:RegisterOnEnable instead of Init.lua needing to
-- know every module by name -- keeps this file stable as later stages add Roster/Session/etc.
local onEnableCallbacks = {}

function PLC:RegisterOnEnable(fn)
	table.insert(onEnableCallbacks, fn)
end

-- Each callback runs through pcall so one module's enable-time error can't silently abort every
-- module registered after it -- without this, a single bad callback (or Events:RegisterAll()
-- itself) would leave every later module's setup (Roster's bucket registration, Session's
-- restore, Theme's palette, Comms' RegisterComm, ...) never having run, with no visible error.
local function guardedCall(fn)
	local ok, err = pcall(fn)
	if not ok then
		PLC.ErrorHandler:LogError(err)
	end
end

function PLC:OnEnable()
	guardedCall(function()
		self.Events:RegisterAll()
	end)
	for _, fn in ipairs(onEnableCallbacks) do
		guardedCall(fn)
	end
end

-- Slash command router ---------------------------------------------------
-- Modules register their own subcommands via PLC:RegisterSlashCommand instead of each adding
-- its own /plc-prefixed chat command, so `/plc` alone always lists everything available.

local subcommands = {}
local defaultHandler

function PLC:RegisterSlashCommand(name, description, handler)
	subcommands[name:lower()] = { description = description, handler = handler }
end

-- What plain `/plc` does (UI/SessionFrame.lua opens the Loot Session window). `/plc help` lists
-- every subcommand.
function PLC:SetDefaultSlashHandler(handler)
	defaultHandler = handler
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
	if input == "" and defaultHandler then
		defaultHandler()
		return
	end
	local cmd, rest = input:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" or cmd == "help" then
		printHelp()
		return
	end
	local entry = subcommands[cmd]
	if not entry then
		print(L["CHAT_PREFIX"] .. string.format(L["CMD_UNKNOWN"], cmd))
		return
	end
	entry.handler(rest)
end

PLC:RegisterChatCommand("plc", "SlashHandler")

PLC:RegisterSlashCommand("errors", "Show captured errors (useful for bug reports)", function()
	local entries = PLC.ErrorHandler:GetEntries()
	if #entries == 0 then
		print(L["CHAT_PREFIX"] .. L["ERROR_LOG_EMPTY"])
		return
	end
	for _, entry in ipairs(entries) do
		print(L["CHAT_PREFIX"] .. string.format(L["ERROR_LOG_ENTRY"], date("%H:%M:%S", entry.time), entry.message))
	end
end)
