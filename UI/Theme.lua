local ADDON_NAME, PLC = ...

PLC.UI = PLC.UI or {}
local Theme = {}
PLC.UI.Theme = Theme

-- Ports FojjiCore's dark-chrome palette + applyTheme() mixing formula (see
-- docs/SPECIFICATION.md §4, docs/analysis/fojjicore-ui-style.md) with our own configurable accent
-- (db.profile.accent, default #E8A33D warm gold) instead of FojjiCore's 4-preset theme picker --
-- we only ever have the one accent. fieldHover/text/dim/scroll/white/warning are never
-- recomputed below, matching FojjiCore's own applyTheme(): only the near-black background
-- channels and the accent itself derive from the user's color choice.
Theme.COLORS = {
	accent = { 0.91, 0.64, 0.24 },
	title = { 0.90, 0.94, 1.00 },
	frame = { 0.018, 0.021, 0.026 },
	header = { 0.022, 0.026, 0.032 },
	sidebar = { 0.025, 0.032, 0.040 },
	content = { 0.035, 0.040, 0.048 },
	field = { 0.024, 0.028, 0.034 },
	fieldHover = { 0.044, 0.052, 0.064 },
	button = { 0.052, 0.058, 0.068 },
	buttonHover = { 0.075, 0.088, 0.105 },
	border = { 0.16, 0.18, 0.22 },
	borderDim = { 0.13, 0.15, 0.18 },
	text = { 0.88, 0.89, 0.91 },
	dim = { 0.50, 0.53, 0.57 },
	scroll = { 0.08, 0.09, 0.11 },
	white = { 1, 1, 1 },
	warning = { 1.00, 0.25, 0.25 },
}

-- Shared widget sizing constants -- extended as later stages add widgets that need them.
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

-- Weak-keyed so a destroyed widget's entry is collected instead of leaking. Every
-- createTexture/createText/createArtwork(tinted) call in UI/Widgets/Primitives.lua registers
-- itself here, so Theme:Refresh() can re-skin every live widget in one pass with no need to
-- track frame references anywhere else (ported pattern, see fojjicore-ui-style.md).
Theme.themeTextures = setmetatable({}, { __mode = "k" })
Theme.themeFonts = setmetatable({}, { __mode = "k" })
Theme.themeGlows = setmetatable({}, { __mode = "k" })

function Theme:Color(name, alpha)
	local c = self.COLORS[name] or self.COLORS.text
	return c[1], c[2], c[3], alpha or 1
end

-- The exact near-black-base + accent-mix formula FojjiCore's applyTheme() uses (Options.lua:117-
-- 143), generalized to whatever accent the user picks (Stage 7's Appearance panel) instead of a
-- fixed preset list.
function Theme:ApplyFromAccent(r, g, b)
	local C = self.COLORS
	C.accent = { r, g, b }
	C.frame = { 0.015 + r * 0.014, 0.018 + g * 0.014, 0.026 + b * 0.014 }
	C.header = { 0.025 + r * 0.08, 0.028 + g * 0.08, 0.036 + b * 0.08 }
	C.sidebar = { 0.025 + r * 0.025, 0.028 + g * 0.025, 0.035 + b * 0.025 }
	C.content = { 0.055 + r * 0.018, 0.060 + g * 0.018, 0.073 + b * 0.018 }
	C.border = { 0.10 + r * 0.24, 0.10 + g * 0.24, 0.12 + b * 0.24 }
	C.borderDim = { 0.07 + r * 0.12, 0.08 + g * 0.12, 0.10 + b * 0.12 }
	C.button = { 0.035 + r * 0.07, 0.04 + g * 0.07, 0.05 + b * 0.07 }
	C.buttonHover = { 0.045 + r * 0.17, 0.05 + g * 0.17, 0.06 + b * 0.17 }

	self:Refresh()
end

function Theme:Refresh()
	for texture, data in pairs(self.themeTextures) do
		local r, g, b, a = self:Color(data.name, data.alpha)
		texture:SetColorTexture(r, g, b, a)
	end
	for texture in pairs(self.themeGlows) do
		local r, g, b = self:Color("accent")
		texture:SetVertexColor(r, g, b)
	end
	for font, colorName in pairs(self.themeFonts) do
		local r, g, b = self:Color(colorName)
		font:SetTextColor(r, g, b)
	end
end

PLC:RegisterOnEnable(function()
	local accent = PLC.db.profile.accent
	Theme:ApplyFromAccent(accent.r, accent.g, accent.b)
end)
