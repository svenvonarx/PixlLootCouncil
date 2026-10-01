local ADDON_NAME, PLC = ...

PLC.UI = PLC.UI or {}
PLC.UI.Widgets = PLC.UI.Widgets or {}
local Primitives = {}
PLC.UI.Widgets.Primitives = Primitives

local Theme = PLC.UI.Theme

-- Ported FojjiCore construction primitives (see docs/analysis/fojjicore-ui-style.md) -- fully
-- custom CreateFrame-based widgets, no BackdropTemplate, one bundled font (see
-- docs/SPECIFICATION.md §4.2). Every texture/text these create registers itself into Theme's
-- weak tables so Theme:Refresh() can re-skin it later without tracking frame references.
local FONT = "Interface\\AddOns\\PixlLootCouncil\\font\\PixlLootCouncil.ttf"

function Primitives.color(name, alpha)
	return Theme:Color(name, alpha)
end

function Primitives.createTexture(parent, layer, colorName, alpha)
	local texture = parent:CreateTexture(nil, layer)
	texture:SetColorTexture(Primitives.color(colorName, alpha))
	Theme.themeTextures[texture] = { name = colorName, alpha = alpha }
	return texture
end

function Primitives.createArtwork(parent, asset, layer, tinted)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
	texture:SetTexture("Interface\\AddOns\\PixlLootCouncil\\textures\\UI\\" .. asset)
	if tinted then
		texture:SetVertexColor(Primitives.color("accent"))
		Theme.themeGlows[texture] = true
	end
	return texture
end

-- Requested size is scaled ~20% down before SetFont (ported formula, min 9px) -- falls back to
-- the default Blizzard font if the bundled one fails to load (e.g. font file missing on disk),
-- same safety net FojjiCore's own OptionsMenu.lua uses.
function Primitives.createText(parent, text, size, colorName)
	local font = parent:CreateFontString(nil, "OVERLAY")
	local pixelSize = math.max(9, math.floor((size or 12) * 0.8 + 0.5))
	if font:SetFont(FONT, pixelSize, "") == false then
		font:SetFont(STANDARD_TEXT_FONT, pixelSize, "")
	end
	font:SetText(text or "")
	local r, g, b = Primitives.color(colorName or "text")
	font:SetTextColor(r, g, b)
	Theme.themeFonts[font] = colorName or "text"
	return font
end

-- 4×1px hairline strips, no backdrop template.
function Primitives.createBorder(parent, colorName, alpha, inset)
	inset = inset or 0
	colorName = colorName or "border"

	local border = {}

	border.top = Primitives.createTexture(parent, "BORDER", colorName, alpha)
	border.top:SetPoint("TOPLEFT", inset, -inset)
	border.top:SetPoint("TOPRIGHT", -inset, -inset)
	border.top:SetHeight(1)

	border.bottom = Primitives.createTexture(parent, "BORDER", colorName, alpha)
	border.bottom:SetPoint("BOTTOMLEFT", inset, inset)
	border.bottom:SetPoint("BOTTOMRIGHT", -inset, inset)
	border.bottom:SetHeight(1)

	border.left = Primitives.createTexture(parent, "BORDER", colorName, alpha)
	border.left:SetPoint("TOPLEFT", inset, -inset)
	border.left:SetPoint("BOTTOMLEFT", inset, inset)
	border.left:SetWidth(1)

	border.right = Primitives.createTexture(parent, "BORDER", colorName, alpha)
	border.right:SetPoint("TOPRIGHT", -inset, -inset)
	border.right:SetPoint("BOTTOMRIGHT", -inset, inset)
	border.right:SetWidth(1)

	return border
end

function Primitives.setBorderColor(border, colorName, alpha)
	for _, texture in pairs(border) do
		texture:SetColorTexture(Primitives.color(colorName, alpha))
	end
end

function Primitives.anchorBelow(object, previous, gap)
	object:ClearAllPoints()
	object:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(gap or 8))
end

function Primitives.createSeparator(parent, y)
	local line = Primitives.createTexture(parent, "ARTWORK", "borderDim")
	line:SetPoint("TOPLEFT", 0, y)
	line:SetPoint("TOPRIGHT", 0, y)
	line:SetHeight(1)
	return line
end

function Primitives.createPageHeader(parent, title)
	local titleText = Primitives.createText(parent, title, 20, "title")
	titleText:SetPoint("TOPLEFT")
	Primitives.createSeparator(parent, -40)
	return titleText
end

-- Single-line text input, flat field-colored fill + 1px border like every other widget here --
-- no BackdropTemplate. EditBox has no native placeholder attribute, so one is faked with the
-- standard WoW idiom (dim placeholder text shown/cleared on focus); call :GetValue() rather than
-- :GetText() to get "" while the placeholder is showing instead of the placeholder string itself.
function Primitives.createEditBox(parent, width, height, placeholder)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, height or 20)
	box:SetAutoFocus(false)
	box:SetTextInsets(6, 6, 0, 0)

	local pixelSize = math.max(9, math.floor(11 * 0.8 + 0.5))
	if box:SetFont(FONT, pixelSize, "") == false then
		box:SetFont(STANDARD_TEXT_FONT, pixelSize, "")
	end

	box.bg = Primitives.createTexture(box, "BACKGROUND", "field")
	box.bg:SetAllPoints()
	box.border = Primitives.createBorder(box)

	local function setTextColor(colorName)
		local r, g, b = Primitives.color(colorName)
		box:SetTextColor(r, g, b)
	end

	setTextColor("text")
	if placeholder then
		box.placeholder = placeholder
		box.showingPlaceholder = true
		box:SetText(placeholder)
		setTextColor("dim")
	end

	box:SetScript("OnEditFocusGained", function(self)
		if self.showingPlaceholder then
			self:SetText("")
			setTextColor("text")
			self.showingPlaceholder = false
		end
	end)
	box:SetScript("OnEditFocusLost", function(self)
		if self:GetText() == "" and self.placeholder then
			self:SetText(self.placeholder)
			setTextColor("dim")
			self.showingPlaceholder = true
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)

	function box:GetValue()
		if self.showingPlaceholder then
			return ""
		end
		return self:GetText()
	end

	return box
end
