local ADDON_NAME, PLC = ...

-- Central AceEvent registration layer. Other modules never call PLC:RegisterEvent themselves --
-- they call Events:RegisterHandler(eventName, fn) at file-load time, and this file is the only
-- place raw Blizzard events get wired up. Keeping one registration point makes the full set of
-- events this addon listens for grep-able in one file instead of scattered across every module.
local Events = {}
PLC.Events = Events

local handlers = {} -- [eventName] = { fn1, fn2, ... }
local registered = false

function Events:RegisterHandler(eventName, fn)
	handlers[eventName] = handlers[eventName] or {}
	table.insert(handlers[eventName], fn)
	if registered then
		PLC:RegisterEvent(eventName, Events.Dispatch)
	end
end

function Events.Dispatch(eventName, ...)
	local list = handlers[eventName]
	if not list then
		return
	end
	for _, fn in ipairs(list) do
		fn(eventName, ...)
	end
end

-- Called once from Core/Init.lua:OnEnable, after every module has had a chance to
-- RegisterHandler at file-load time.
function Events:RegisterAll()
	if registered then
		return
	end
	registered = true
	for eventName in pairs(handlers) do
		PLC:RegisterEvent(eventName, Events.Dispatch)
	end
end
