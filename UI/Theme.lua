local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

PLC.UI = PLC.UI or {}
local Theme = {}
PLC.UI.Theme = Theme

-- PixlLootCouncil's look: near-black surfaces with a faint tint of the theme's accent color, flat
-- fills and 1px borders. Every themed texture and font string is tracked here, so changing the
-- theme (db.profile.theme, Options -> Appearance) recolors the whole UI live.

-- The default theme's colors. Themes change these through Theme.THEMES below.
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

-- Fixed colors that are surfaces too, and so take a theme's shade.
local SHADED = { "field", "fieldHover", "scroll" }

-- In menu order, the default first.
--   accent  the highlight color. It's also a signal: trade timers run green -> accent -> red, and
--           Staged is accent where Awarded is green. So it has to stay clearly apart from success,
--           warning and text, which tests/appearance_test.lua checks for every theme.
--   shade   multiplies every neutral surface, which is what gives a theme its own background
--   colors  replaces fixed colors: a green accent takes a different success color
Theme.DEFAULT = "gold"
Theme.THEMES = {
	{ key = "gold", name = L["THEME_GOLD"], accent = { 0.91, 0.64, 0.24 } },
	{ key = "sunwell", name = L["THEME_SUNWELL"], accent = { 0.97, 0.86, 0.58 }, shade = { 1.40, 1.10, 0.70 } },
	{
		key = "fel",
		name = L["THEME_FEL"],
		accent = { 0.62, 0.93, 0.20 },
		shade = { 0.80, 1.35, 0.75 },
		colors = { success = { 0.25, 0.85, 0.80 } },
	},
	{
		key = "zangarmarsh",
		name = L["THEME_ZANGARMARSH"],
		accent = { 0.25, 0.85, 0.72 },
		shade = { 0.70, 1.20, 1.15 },
		colors = { success = { 0.62, 0.88, 0.30 } },
	},
	{ key = "frost", name = L["THEME_FROST"], accent = { 0.45, 0.78, 0.98 }, shade = { 0.80, 1.05, 1.40 } },
	{ key = "twilight", name = L["THEME_TWILIGHT"], accent = { 0.45, 0.58, 1.00 }, shade = { 0.75, 0.85, 1.60 } },
	{ key = "arcane", name = L["THEME_ARCANE"], accent = { 0.72, 0.50, 1.00 }, shade = { 1.10, 0.80, 1.70 } },
	{ key = "nether", name = L["THEME_NETHER"], accent = { 0.93, 0.40, 0.85 }, shade = { 1.40, 0.75, 1.40 } },
}

Theme.COLORS = {}

-- Shared widget sizes.
Theme.LAYOUT = {
	buttonHeight = 28,
	headerHeight = 32,
	checkboxWidth = 300,
	checkboxHeight = 22,
	sliderHeight = 40,
	fieldWidth = 260,
	fieldHeight = 28,
	menuMaxRows = 7,
	sidebarWidth = 150,
	contentPadding = 20,
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
	if entry.own then
		r, g, b = entry.own[1], entry.own[2], entry.own[3]
	end
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

-- For a region that shows a color of its own, whatever the theme: a preview of another theme.
function Theme:KeepColor(region, color)
	tracked[region].own = color
	paint(region, tracked[region])
end

-- Calls fn(fontString) for every tracked font string (UI/Widgets/Primitives.lua's font refresh).
function Theme:ForEachText(fn)
	for region, entry in pairs(tracked) do
		if entry.kind == "text" then
			fn(region)
		end
	end
end

local function findTheme(key)
	for _, theme in ipairs(Theme.THEMES) do
		if theme.key == key then
			return theme
		end
	end
	return Theme.THEMES[1]
end

-- Every color of a theme, by name. An unknown key is the default theme.
function Theme:Palette(key)
	local theme = findTheme(key)
	local shade = theme.shade or { 1, 1, 1 }
	local accent = theme.accent
	local function shaded(c)
		return { c[1] * shade[1], c[2] * shade[2], c[3] * shade[3] }
	end

	local palette = { accent = accent }
	for name, c in pairs(FIXED) do
		palette[name] = c
	end
	for _, name in ipairs(SHADED) do
		palette[name] = shaded(FIXED[name])
	end
	for name, spec in pairs(TINTED) do
		local base, t = shaded(spec.base), spec.tint
		palette[name] = {
			base[1] + (accent[1] - base[1]) * t,
			base[2] + (accent[2] - base[2]) * t,
			base[3] + (accent[3] - base[3]) * t,
		}
	end
	for name, c in pairs(theme.colors or {}) do
		palette[name] = c
	end
	return palette
end

function Theme:Apply(key)
	for name, c in pairs(self:Palette(key)) do
		self.COLORS[name] = c
	end
	self:Refresh()
end

-- For widgets whose colors depend on state (e.g. a selected tab): fn() runs after every recolor.
local refreshCallbacks = {}

function Theme:OnRefresh(fn)
	table.insert(refreshCallbacks, fn)
end

function Theme:Refresh()
	for region, entry in pairs(tracked) do
		paint(region, entry)
	end
	for _, fn in ipairs(refreshCallbacks) do
		fn()
	end
end

-- Defaults right away, so widgets built before OnEnable still get real colors.
Theme:Apply(Theme.DEFAULT)

PLC:RegisterOnEnable(function()
	PLC.db.profile.accent = nil -- what the accent color setting left behind
	Theme:Apply(PLC.db.profile.theme)
end)
