local ADDON_NAME, PLC = ...

PLC.UI = PLC.UI or {}
local Theme = {}
PLC.UI.Theme = Theme

-- PixlLootCouncil's look: near-black surfaces with a faint tint of one user-chosen accent color
-- (db.profile.accent, default #E8A33D warm gold), flat fills and 1px borders. Every themed texture
-- and font string is tracked here, so changing the accent (Options -> Appearance) recolors the
-- whole UI live.

-- Fixed colors, independent of the accent.
local FIXED = {
	title = { 0.92, 0.95, 1.00 },
	text = { 0.87, 0.88, 0.90 },
	dim = { 0.52, 0.54, 0.58 },
	white = { 1, 1, 1 },
	field = { 0.022, 0.026, 0.032 },
	fieldHover = { 0.042, 0.050, 0.062 },
	scroll = { 0.075, 0.085, 0.100 },
	warning = { 1.00, 0.27, 0.27 },
	success = { 0.27, 0.84, 0.38 },
}

-- Accent-tinted surfaces: a neutral base color moved `tint` of the way towards the accent.
local TINTED = {
	frame = { base = { 0.018, 0.020, 0.026 }, tint = 0.012 },
	header = { base = { 0.024, 0.027, 0.034 }, tint = 0.070 },
	sidebar = { base = { 0.026, 0.030, 0.037 }, tint = 0.022 },
	content = { base = { 0.050, 0.056, 0.068 }, tint = 0.020 },
	button = { base = { 0.040, 0.045, 0.055 }, tint = 0.065 },
	buttonHover = { base = { 0.055, 0.062, 0.075 }, tint = 0.150 },
	border = { base = { 0.110, 0.120, 0.140 }, tint = 0.220 },
	borderDim = { base = { 0.080, 0.090, 0.110 }, tint = 0.110 },
}

Theme.COLORS = {}

-- Shared widget sizes.
Theme.LAYOUT = {
	buttonHeight = 28,
	headerHeight = 32,
	checkboxWidth = 240,
	checkboxHeight = 22,
	sliderWidth = 220,
	sliderHeight = 60,
	fieldWidth = 260,
	fieldHeight = 28,
	menuMaxRows = 7,
	sidebarWidth = 140,
	contentPadding = 16,
}

-- [region] = { kind = "fill" | "tint" | "text", color = name, alpha = number|nil }. Weak keys,
-- so widgets that go away are simply dropped.
local tracked = setmetatable({}, { __mode = "k" })

function Theme:Color(name, alpha)
	local c = self.COLORS[name] or self.COLORS.text
	return c[1], c[2], c[3], alpha or 1
end

local function paint(region, entry)
	local r, g, b, a = Theme:Color(entry.color, entry.alpha)
	if entry.kind == "fill" then
		region:SetColorTexture(r, g, b, a)
	elseif entry.kind == "tint" then
		region:SetVertexColor(r, g, b)
	else
		region:SetTextColor(r, g, b)
	end
end

-- Registers a region to be repainted on accent changes, and paints it now.
--   "fill": a texture filled with a theme color   "tint": a texture vertex-colored with one
--   "text": a font string's text color
function Theme:Track(region, kind, colorName, alpha)
	local entry = { kind = kind, color = colorName, alpha = alpha }
	tracked[region] = entry
	paint(region, entry)
	return region
end

-- Calls fn(fontString) for every tracked font string (UI/Widgets/Primitives.lua's font refresh).
function Theme:ForEachText(fn)
	for region, entry in pairs(tracked) do
		if entry.kind == "text" then
			fn(region)
		end
	end
end

function Theme:ApplyFromAccent(r, g, b)
	local colors = self.COLORS
	for name, c in pairs(FIXED) do
		colors[name] = c
	end
	colors.accent = { r, g, b }
	local accent = colors.accent
	for name, spec in pairs(TINTED) do
		local t = spec.tint
		colors[name] = {
			spec.base[1] + (accent[1] - spec.base[1]) * t,
			spec.base[2] + (accent[2] - spec.base[2]) * t,
			spec.base[3] + (accent[3] - spec.base[3]) * t,
		}
	end
	self:Refresh()
end

function Theme:Refresh()
	for region, entry in pairs(tracked) do
		paint(region, entry)
	end
end

-- Defaults right away, so widgets built before OnEnable still get real colors.
Theme:ApplyFromAccent(0.91, 0.64, 0.24)

PLC:RegisterOnEnable(function()
	local accent = PLC.db.profile.accent
	Theme:ApplyFromAccent(accent.r, accent.g, accent.b)
end)
