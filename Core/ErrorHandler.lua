local ADDON_NAME, PLC = ...

local ErrorHandler = {}
PLC.ErrorHandler = ErrorHandler

local MAX_ENTRIES = 50
local buffer = {} -- holds entries until a SavedVariables db is attached by Core/Init.lua
local db -- set via :AttachDB once AceDB exists

local function trim(list)
	while #list > MAX_ENTRIES do
		table.remove(list, 1)
	end
end

local function addEntry(kind, message)
	local entry = { time = time(), kind = kind, message = tostring(message) }
	local list = db and db.global.errors or buffer
	table.insert(list, entry)
	trim(list)
end

function ErrorHandler:AttachDB(newDb)
	db = newDb
	db.global.errors = db.global.errors or {}
	for _, entry in ipairs(buffer) do
		table.insert(db.global.errors, entry)
	end
	wipe(buffer)
	trim(db.global.errors)
end

function ErrorHandler:LogError(message)
	addEntry("lua", message)
end

function ErrorHandler:LogTaint(kind, message)
	addEntry(kind, message)
end

function ErrorHandler:GetEntries()
	return db and db.global.errors or buffer
end

function ErrorHandler:Clear()
	wipe(db and db.global.errors or buffer)
end

-- Wrap (not replace) whatever error handler is already installed, so other addons/Blizzard UI
-- keep their normal behavior; we only intercept to log errors that originate from our own files.
local previousHandler = geterrorhandler()
seterrorhandler(function(msg)
	if type(msg) == "string" and msg:find(ADDON_NAME, 1, true) then
		ErrorHandler:LogError(msg)
	end
	if previousHandler then
		previousHandler(msg)
	end
end)

-- ADDON_ACTION_BLOCKED/FORBIDDEN fire independently of Lua errors and are the main signal for
-- taint regressions (protected/secure API misuse) — captured from a dedicated frame so this
-- works from file-load time, before the Ace addon object exists.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:SetScript("OnEvent", function(_, event, blockedAddon, functionName)
	if blockedAddon ~= ADDON_NAME then
		return
	end
	local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME, true)
	local kind = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden"
	local message = string.format("%s: %s", event, tostring(functionName))
	ErrorHandler:LogTaint(kind, message)
	if L then
		local template = kind == "blocked" and L["TAINT_BLOCKED"] or L["TAINT_FORBIDDEN"]
		print((L["CHAT_PREFIX"] or "") .. string.format(template, tostring(functionName)))
	end
end)
