local ADDON_NAME, PLC = ...

PLC.UI = PLC.UI or {}
PLC.UI.Widgets = PLC.UI.Widgets or {}
local Primitives = {}
PLC.UI.Widgets.Primitives = Primitives

local Theme = PLC.UI.Theme

-- Building blocks every window uses: themed fills and text, 1px borders, icons drawn from plain
-- textures, the bundled font. No BackdropTemplate, no art assets beyond the logo. Everything themed
-- is registered with UI/Theme.lua so an accent change recolors it live.

local MEDIA = "Interface\\AddOns\\PixlLootCouncil\\"
-- Inter (SIL Open Font License 1.1, see font/Inter-LICENSE.txt).
local FONT = MEDIA .. "font\\Inter-Medium.ttf"

function Primitives.color(name, alpha)
	return Theme:Color(name, alpha)
end

----------------------------------------------------------------------------------------------------
-- Fills, artwork, borders
----------------------------------------------------------------------------------------------------

-- A texture filled with a theme color.
function Primitives.createTexture(parent, layer, colorName, alpha)
	return Theme:Track(parent:CreateTexture(nil, layer), "fill", colorName, alpha)
end

-- An image from textures/UI/; `tinted` colors it with the accent (and follows accent changes).
function Primitives.createArtwork(parent, asset, layer, tinted)
	local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
	texture:SetTexture(MEDIA .. "textures\\UI\\" .. asset)
	if tinted then
		Theme:Track(texture, "tint", "accent")
	end
	return texture
end

-- The PixlLootCouncil mark (textures/UI/logo.png, 98x128), accent-tinted.
function Primitives.createLogo(parent, height)
	height = height or 20
	local logo = Primitives.createArtwork(parent, "logo.png", "ARTWORK", true)
	logo:SetSize(height * 98 / 128, height)
	return logo
end

-- Four 1px edge textures around `parent`, `inset` pixels in. Returns { top, bottom, left, right }.
local EDGES = {
	top = { "TOPLEFT", "TOPRIGHT", "height" },
	bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
	left = { "TOPLEFT", "BOTTOMLEFT", "width" },
	right = { "TOPRIGHT", "BOTTOMRIGHT", "width" },
}

function Primitives.createBorder(parent, colorName, alpha, inset)
	inset = inset or 0
	local border = {}
	for side, spec in pairs(EDGES) do
		local edge = Primitives.createTexture(parent, "BORDER", colorName or "border", alpha)
		for i = 1, 2 do
			local point = spec[i]
			local x = point:find("LEFT") and inset or -inset
			local y = point:find("TOP") and -inset or inset
			edge:SetPoint(point, x, y)
		end
		if spec[3] == "height" then
			edge:SetHeight(1)
		else
			edge:SetWidth(1)
		end
		border[side] = edge
	end
	return border
end

function Primitives.setBorderColor(border, colorName, alpha)
	local r, g, b, a = Primitives.color(colorName, alpha)
	for _, edge in pairs(border) do
		edge:SetColorTexture(r, g, b, a)
	end
end

-- Horizontal 1px divider across `parent` at vertical offset y.
function Primitives.createSeparator(parent, y)
	local line = Primitives.createTexture(parent, "ARTWORK", "borderDim")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, y)
	line:SetPoint("TOPRIGHT", 0, y)
	return line
end

function Primitives.anchorBelow(object, previous, gap)
	object:ClearAllPoints()
	object:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(gap or 8))
end

----------------------------------------------------------------------------------------------------
-- Text and the bundled font
----------------------------------------------------------------------------------------------------

-- Callers pass a "design size"; the font is rendered at four fifths of it (every layout in the
-- addon is tuned to that), never below 9px.
local function pixelSizeFor(size)
	return math.max(9, math.floor((size or 12) * 0.8 + 0.5))
end

-- One Font object per pixel size, shared by every label of that size.
local fonts = {}

local function setFontWithFallback(target, pixelSize)
	if target:SetFont(FONT, pixelSize, "") == false then
		target:SetFont(STANDARD_TEXT_FONT, pixelSize, "")
	end
end

local function sharedFont(pixelSize)
	if not fonts[pixelSize] then
		local font = CreateFont("PixlLootCouncilFont" .. pixelSize)
		setFontWithFallback(font, pixelSize)
		fonts[pixelSize] = font
	end
	return fonts[pixelSize]
end

-- Cold-start blank labels: on a fresh game start, labels laid out before WoW finished loading
-- the .ttf can stay empty (button captions, window titles) -- WoW skips SetFont/SetText calls that
-- change nothing, so re-applying the same values never redraws them. Three measures:
--   1. the font is referenced at file load (during the loading screen), well before any window;
--   2. every label uses a shared Font object, so the font can be re-applied to all at once;
--   3. RefreshFonts() makes a *real* change -- nudges each Font object's size and restores it,
--      clears and re-sets every label's text -- after login and whenever one of our windows opens.
do
	local warmup = UIParent:CreateFontString(nil, "BACKGROUND")
	warmup:SetFontObject(sharedFont(12))
	warmup:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", 0, 100) -- off-screen
	warmup:SetText("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
end

function Primitives.RefreshFonts()
	for pixelSize, font in pairs(fonts) do
		font:SetFont(FONT, pixelSize + 1, "")
		setFontWithFallback(font, pixelSize)
	end
	Theme:ForEachText(function(fontString)
		local text = fontString:GetText()
		if text and text ~= "" then
			fontString:SetText("")
			fontString:SetText(text)
		end
	end)
end

-- Call once per top-level window right after creating it.
function Primitives.refreshFontsOnShow(frame)
	frame:HookScript("OnShow", Primitives.RefreshFonts)
end

PLC.Events:RegisterHandler("PLAYER_ENTERING_WORLD", function()
	Primitives.RefreshFonts()
	for _, delay in ipairs({ 1, 3, 8 }) do
		PLC:ScheduleTimer(Primitives.RefreshFonts, delay)
	end
end)

-- A label in the bundled font. `size` is the design size (see pixelSizeFor), `colorName` a theme
-- color (default "text").
function Primitives.createText(parent, text, size, colorName)
	local label = parent:CreateFontString(nil, "OVERLAY")
	label:SetFontObject(sharedFont(pixelSizeFor(size)))
	label:SetText(text or "")
	return Theme:Track(label, "text", colorName or "text")
end

-- A single- or multi-line input in the same flat style. EditBox has no placeholder support, so a
-- dim placeholder is shown while empty and unfocused; read the value with :GetValue() (returns ""
-- while the placeholder shows). Text is clipped to the box (an EditBox doesn't clip on its own).
-- Multi-line boxes cap input at `maxLetters` (default 80) instead of growing past their height.
function Primitives.createEditBox(parent, width, height, placeholder, multiline, maxLetters)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, height or 20)
	box:SetAutoFocus(false)
	box:SetFontObject(sharedFont(pixelSizeFor(11)))
	if box.SetClipsChildren then
		box:SetClipsChildren(true)
	end
	if multiline then
		box:SetMultiLine(true)
		box:SetMaxLetters(maxLetters or 80)
		box:SetTextInsets(6, 6, 2, 2)
		box:SetJustifyV("MIDDLE") -- lines up with buttons beside it while holding one line
	else
		box:SetTextInsets(6, 6, 0, 0)
	end

	box.bg = Primitives.createTexture(box, "BACKGROUND", "field")
	box.bg:SetAllPoints()
	box.border = Primitives.createBorder(box)

	local function showPlaceholder(show)
		box.showingPlaceholder = show
		box:SetText(show and box.placeholder or "")
		box:SetTextColor(Primitives.color(show and "dim" or "text"))
	end

	box:SetTextColor(Primitives.color("text"))
	if placeholder then
		box.placeholder = placeholder
		showPlaceholder(true)
	end

	box:SetScript("OnEditFocusGained", function(self)
		if self.showingPlaceholder then
			showPlaceholder(false)
		end
	end)
	box:SetScript("OnEditFocusLost", function(self)
		if self.placeholder and self:GetText() == "" then
			showPlaceholder(true)
		end
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)

	function box:GetValue()
		return self.showingPlaceholder and "" or self:GetText()
	end

	return box
end

----------------------------------------------------------------------------------------------------
-- Item tooltips
----------------------------------------------------------------------------------------------------

-- Hovering `frame` shows the full game tooltip for `frame.itemLink` (read on every hover, so
-- pooled table cells can just update the field). Anchored to the frame's top-left corner by
-- default, so it lands in the same spot whether the frame is a 24px icon or a long name label.
function Primitives.attachItemTooltip(frame, anchor)
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", function(self)
		if not self.itemLink then
			return
		end
		GameTooltip:SetOwner(self, anchor or "ANCHOR_NONE")
		if not anchor then
			GameTooltip:SetPoint("TOPLEFT", self, "TOPLEFT")
		end
		GameTooltip:SetHyperlink(self.itemLink)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

----------------------------------------------------------------------------------------------------
-- Class and role icons (Blizzard atlases)
----------------------------------------------------------------------------------------------------

-- Circular class icons: CLASS_ICON_TCOORDS maps a class file token ("WARRIOR") to coordinates in
-- Blizzard's shared atlas. Setter + creator, so pooled table cells can re-point an existing icon.
function Primitives.setClassIcon(icon, classToken)
	local coords = classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
	icon:SetShown(coords ~= nil)
	if coords then
		icon:SetTexCoord(unpack(coords))
	end
end

function Primitives.createClassIcon(parent, classToken)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circle")
	Primitives.setClassIcon(icon, classToken)
	return icon
end

-- Role icons from the LFG role atlas (a 256x256 sheet of 67x67 cells). The coordinates are
-- hardcoded: Blizzard's own lookup helper for them no longer exists on this client.
local ROLE_COORDS = {
	TANK = { 0, 67 / 256, 67 / 256, 134 / 256 },
	HEALER = { 67 / 256, 134 / 256, 0, 67 / 256 },
	DAMAGER = { 67 / 256, 134 / 256, 67 / 256, 134 / 256 },
}

function Primitives.setRoleIcon(icon, role)
	local coords = role and ROLE_COORDS[role]
	icon:SetShown(coords ~= nil)
	if coords then
		icon:SetTexCoord(unpack(coords))
	end
end

function Primitives.createRoleIcon(parent, role)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
	Primitives.setRoleIcon(icon, role)
	return icon
end

----------------------------------------------------------------------------------------------------
-- Small glyphs drawn from flat strokes (crisp at any size, no font or art dependency)
----------------------------------------------------------------------------------------------------

local function stroke(parent, colorName, length, angle, x, y)
	local line = Primitives.createTexture(parent, "ARTWORK", colorName)
	line:SetSize(length, 1.4)
	line:SetPoint("CENTER", parent, "CENTER", x or 0, y or 0)
	line:SetRotation(math.rad(angle))
	return line
end

-- "Has a note" marker: a tiny outlined page with two text lines.
function Primitives.createNoteIcon(parent, size)
	size = size or 10
	local icon = CreateFrame("Frame", nil, parent)
	icon:SetSize(size, size)
	icon.border = Primitives.createBorder(icon, "dim")
	for i = 0, 1 do
		local line = Primitives.createTexture(icon, "ARTWORK", "dim")
		line:SetHeight(1)
		line:SetPoint("TOPLEFT", 2, -2 - i * 3)
		line:SetPoint("TOPRIGHT", -2, -2 - i * 3)
	end
	return icon
end

-- Window/row close control: a thin accent "X" that turns red on hover.
function Primitives.createCloseButton(parent, size)
	size = size or 20
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	local strokes = {
		stroke(button, "accent", size * 0.6, 45),
		stroke(button, "accent", size * 0.6, -45),
	}
	local function recolor(colorName)
		local r, g, b = Primitives.color(colorName)
		for _, line in ipairs(strokes) do
			line:SetColorTexture(r, g, b, 1)
		end
	end
	button:SetScript("OnEnter", function() recolor("warning") end)
	button:SetScript("OnLeave", function() recolor("accent") end)
	return button
end

-- Downward chevron for dropdowns: two strokes meeting just below the center.
function Primitives.createChevron(parent, size, colorName)
	size = size or 10
	local icon = CreateFrame("Frame", nil, parent)
	icon:SetSize(size, size)
	local length = size * 0.62
	local offset = length * 0.3
	stroke(icon, colorName or "dim", length, -45, -offset, size * 0.1)
	stroke(icon, colorName or "dim", length, 45, offset, size * 0.1)
	return icon
end

-- Title text with a divider under it, for content pages.
function Primitives.createPageHeader(parent, title)
	local titleText = Primitives.createText(parent, title, 20, "title")
	titleText:SetPoint("TOPLEFT")
	Primitives.createSeparator(parent, -40)
	return titleText
end

----------------------------------------------------------------------------------------------------
-- Resizing
----------------------------------------------------------------------------------------------------

-- Drag-resizable from a bottom-right grip (a triangle of dots, brightening on hover), within the
-- given bounds.
function Primitives.makeResizable(frame, minWidth, minHeight, maxWidth, maxHeight)
	frame:SetResizable(true)
	maxWidth, maxHeight = maxWidth or 2000, maxHeight or 2000
	if frame.SetResizeBounds then
		frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
	else
		frame:SetMinResize(minWidth, minHeight)
		frame:SetMaxResize(maxWidth, maxHeight)
	end

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip.dots = {}
	for row = 0, 2 do
		for col = 0, 2 - row do
			local dot = Primitives.createTexture(grip, "OVERLAY", "dim")
			dot:SetSize(2, 2)
			dot:SetPoint("BOTTOMRIGHT", -(2 + col * 4), 2 + row * 4)
			grip.dots[#grip.dots + 1] = dot
		end
	end

	local function recolor(colorName)
		local r, g, b = Primitives.color(colorName)
		for _, dot in ipairs(grip.dots) do
			dot:SetColorTexture(r, g, b, 1)
		end
	end
	grip:SetScript("OnEnter", function() recolor("accent") end)
	grip:SetScript("OnLeave", function() recolor("dim") end)
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
	grip:SetScript("OnHide", function() frame:StopMovingOrSizing() end)
	return grip
end
