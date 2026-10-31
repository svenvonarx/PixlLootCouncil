local ADDON_NAME, PLC = ...

-- The response buttons raiders choose from. Two sets matter:
--   configured: this character's own set (Options -> Responses), used for sessions they start
--   active: Session.responseSet, the copy the holder took at Start() and sent to every client
--     (session_start, session_sync_data), so everyone sees the holder's buttons whatever their own
--     options say. Like the response timeout, it's fixed for the whole session: a recorded answer
--     must always find its response, and buttons shouldn't change under someone mid-vote.
-- Answers are stored by `key`, which never changes, so renaming a response is always safe.
--
-- Edits live in profile.customResponses, a key with no AceDB default, never in the default
-- profile.responses list: AceDB refills an array from its defaults on load, so a response deleted
-- from that list would come back after a reload.
local Responses = {}
PLC.Responses = Responses

Responses.MAX_COUNT = 7
Responses.MAX_TEXT_LETTERS = 12
local MAX_TEXT_BYTES = Responses.MAX_TEXT_LETTERS * 4 -- UTF-8

local function colorValue(value)
	return type(value) == "number" and math.max(0, math.min(1, value)) or 1
end

-- A clean copy of `list`, safe to display and to send, or nil if nothing in it is usable. Also what
-- a received set goes through, so a bad message can't break the Loot Response window.
function Responses.Sanitize(list)
	if type(list) ~= "table" then
		return nil
	end
	local clean, seen = {}, {}
	for _, resp in ipairs(list) do
		if #clean < Responses.MAX_COUNT and type(resp) == "table" and type(resp.key) == "string" and resp.key ~= ""
			and type(resp.text) == "string" and resp.text ~= "" and #resp.text <= MAX_TEXT_BYTES and not seen[resp.key] then
			seen[resp.key] = true
			local color = type(resp.color) == "table" and resp.color or {}
			table.insert(clean, {
				key = resp.key,
				text = resp.text,
				color = { r = colorValue(color.r), g = colorValue(color.g), b = colorValue(color.b) },
			})
		end
	end
	return clean[1] and clean or nil
end

function Responses:GetDefaults()
	return Responses.Sanitize(PLC.Defaults.profile.responses)
end

-- Always a fresh copy, so callers can edit it and hand it to Save.
function Responses:GetConfigured()
	return Responses.Sanitize(PLC.db.profile.customResponses) or self:GetDefaults()
end

-- What the current (or last) session uses; this character's own set when there hasn't been one.
function Responses:GetActive()
	return PLC.Session.responseSet or self:GetConfigured()
end

function Responses:Find(key)
	if not key then
		return nil
	end
	for _, resp in ipairs(self:GetActive()) do
		if resp.key == key then
			return resp
		end
	end
	return nil
end

function Responses:Save(list)
	PLC.db.profile.customResponses = Responses.Sanitize(list)
end

function Responses:Reset()
	PLC.db.profile.customResponses = nil
end

-- A key no response in `list` uses.
function Responses.NewKey(list)
	local used = {}
	for _, resp in ipairs(list) do
		used[resp.key] = true
	end
	local n = 1
	while used["CUSTOM" .. n] do
		n = n + 1
	end
	return "CUSTOM" .. n
end

-- Changes when the Loot Response window's buttons need rebuilding.
function Responses:Signature()
	local parts = {}
	for _, resp in ipairs(self:GetActive()) do
		table.insert(parts, resp.key .. "=" .. resp.text)
	end
	return table.concat(parts, "\n")
end
