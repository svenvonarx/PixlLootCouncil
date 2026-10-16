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

-- Standard "hover to see this item's real tooltip" handler -- the full native tooltip (name,
-- stats, everything), via SetHyperlink, not a hand-built text-only one. `frame` must be a real
-- Frame (a FontString/Texture region has no SetScript -- wrap it in a Frame first if the visual
-- element itself can't host this directly, see UI/SessionFrame.lua's detail item label).
--
-- Anchored TOPLEFT-to-TOPLEFT by default (pass an explicit `anchor` -- one of the "ANCHOR_*"
-- strings SetOwner takes -- to override) rather than Blizzard's own default "ANCHOR_RIGHT":
-- that positions relative to the hovered frame's own right edge, which sits somewhere different
-- for a 24px icon than for a 170px-wide name label, so the tooltip jumped to a different offset
-- depending on which one of the two you were hovering. Anchoring to the shared TOPLEFT corner
-- instead lands the tooltip in the same relative spot regardless of the hovered frame's width.
--
-- Reads `frame.itemLink` fresh on every hover rather than taking the link as a parameter here,
-- since the main use case is a pooled/recycled row-cell widget (UI/Widgets/DataTable.lua) that
-- gets rebound to a different item on every render -- the caller just updates
-- `frame.itemLink` in its own update() and this always shows whatever that currently is. A nil
-- itemLink suppresses the tooltip entirely (e.g. a cell not yet bound to any row).
function Primitives.attachItemTooltip(frame, anchor)
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", function(self)
		if self.itemLink then
			GameTooltip:SetOwner(self, anchor or "ANCHOR_NONE")
			if not anchor then
				GameTooltip:SetPoint("TOPLEFT", self, "TOPLEFT")
			end
			GameTooltip:SetHyperlink(self.itemLink)
			GameTooltip:Show()
		end
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
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

-- The brand mark, rasterized from the vector source at 98x128 (its natural 43.5:57 aspect
-- ratio) for crisp scaling down to header-icon size. Accent-tinted via createArtwork above, so
-- it live-retints along with everything else when the user changes their accent color.
local LOGO_ASPECT = 98 / 128

function Primitives.createLogo(parent, height)
	height = height or 20
	local logo = Primitives.createArtwork(parent, "logo.png", "ARTWORK", true)
	logo:SetSize(height * LOGO_ASPECT, height)
	return logo
end

-- The standard Blizzard circular class-icon atlas (matching modern Blizzard UI, e.g. the group
-- finder tool) -- CLASS_ICON_TCOORDS is a long-standing Blizzard global, keyed by class FILE
-- token (e.g. "WARRIOR", "MAGE"), mapping to {left, right, top, bottom} texture coordinates into
-- this one shared atlas. No new art asset needed. Split into a setter + a creator (rather than
-- just the creator) so a pooled/recycled widget (UI/Widgets/DataTable.lua row cells) can update
-- an existing icon's class in its own update() instead of needing a new texture every render.
function Primitives.setClassIcon(icon, classToken)
	local coords = classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
	if coords then
		icon:SetTexCoord(unpack(coords))
		icon:Show()
	else
		icon:Hide()
	end
end

function Primitives.createClassIcon(parent, classToken)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circle")
	Primitives.setClassIcon(icon, classToken)
	return icon
end

-- The standard Blizzard role-icon atlas (Tank/Healer/Damager, matching the group finder tool and
-- raid frame role icons), "Interface\LFGFrame\UI-LFG-ICON-ROLES". The global function that used
-- to hand back these texture coordinates (GetTexCoordsForRole / GetTexCoordsForRoleSmallCircle)
-- was removed by Blizzard in patch 10.1.5 -- calling it here silently broke every role icon
-- (nil-function-call error on every row, not something a /reload vs full restart would ever have
-- fixed). Confirmed against two other already-installed addons that hit the same removal and
-- worked around it their own way (WeakAuras/BuffTrigger2.lua keeps a local reimplementation
-- explicitly marked "-- Deprecated in 10.1.5"; NovaInstanceTracker.lua hardcodes the identical
-- coordinates directly) -- both independently agree with the values below, which is why these
-- are hardcoded here too rather than relying on a Blizzard helper that may or may not exist on a
-- given client. The atlas is a 256x256 sheet of 67x67 cells: Tank top-left, Healer top-right,
-- Damager bottom-right (Guide, bottom-left, has no PixlLootCouncil use).
local ROLE_TCOORDS = {
	TANK = { 0, 67 / 256, 67 / 256, 134 / 256 },
	HEALER = { 67 / 256, 134 / 256, 0, 67 / 256 },
	DAMAGER = { 67 / 256, 134 / 256, 67 / 256, 134 / 256 },
}

-- Same setter/creator split as createClassIcon, for the same pooled-widget reason.
function Primitives.setRoleIcon(icon, role)
	local coords = role and ROLE_TCOORDS[role]
	if coords then
		icon:SetTexCoord(unpack(coords))
		icon:Show()
	else
		icon:Hide()
	end
end

function Primitives.createRoleIcon(parent, role)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
	Primitives.setRoleIcon(icon, role)
	return icon
end

-- A small "page with lines" glyph marking "this row has a note attached" -- built from the same
-- flat vector-primitive technique as the header close button's rotated-hairline "X"
-- (UI/Widgets/Primitives.lua's createCloseButton) and the resize grip's dot-triangle
-- (makeResizable), not a new texture asset. Caller toggles visibility with :SetShown(...)
-- depending on whether that row actually has a note -- this just builds the glyph.
function Primitives.createNoteIcon(parent, size)
	size = size or 10
	local icon = CreateFrame("Frame", nil, parent)
	icon:SetSize(size, size)
	icon.border = Primitives.createBorder(icon, "dim")
	for i = 1, 2 do
		local line = Primitives.createTexture(icon, "ARTWORK", "dim")
		line:SetHeight(1)
		line:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * 3))
		line:SetPoint("TOPRIGHT", -2, -(2 + (i - 1) * 3))
	end
	return icon
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

	-- A brand-new FontString using the bundled custom font sometimes doesn't actually render its
	-- very first SetText until the font is truly ready -- observed as: every label that gets
	-- SetText called again shortly after creation (DataTable cells, re-rendered on every refresh/
	-- update) always shows correctly, while a label set exactly once at creation time (e.g. a
	-- static button's text, set here and never touched again) sometimes stays blank forever. A
	-- single next-tick retry was enough on a plain /reload but not reliably on a real first login
	-- (far more addons/textures/fonts all loading at once, so the font can still not be ready a
	-- tick later) -- several retries spread out over the following ~1.5s instead of just one,
	-- cheap and self-terminating, covers both. Each one reads font:GetText() at fire time (not the
	-- `text` parameter) so it can never clobber a legitimate SetText call that lands in between.
	for _, delay in ipairs({ 0, 0.2, 0.5, 1.5 }) do
		PLC:ScheduleTimer(function()
			font:SetText(font:GetText() or "")
		end, delay)
	end

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

-- Every window's header close control -- previously a flat colored square behind a bundled-font
-- "x" glyph, which read as a stray button rather than a close control (the font's "x" is stubby/
-- rounded at header-icon size and needed the square backing just to be visible at all). This is
-- two thin rotated hairlines crossing at the button's center instead -- no background, no font
-- glyph, just a longer/thinner "X" that matches the rest of the flat, no-backdrop design
-- language. Accent by default, flips to warning-red on hover (the one spot in the app where
-- hovering something red-flagged is the *safe* affordance, not a warning).
function Primitives.createCloseButton(parent, size)
	size = size or 20
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)

	local length = size * 0.6
	local thickness = 1.4

	local strokeA = Primitives.createTexture(button, "ARTWORK", "accent")
	strokeA:SetSize(length, thickness)
	strokeA:SetPoint("CENTER")
	strokeA:SetRotation(math.rad(45))

	local strokeB = Primitives.createTexture(button, "ARTWORK", "accent")
	strokeB:SetSize(length, thickness)
	strokeB:SetPoint("CENTER")
	strokeB:SetRotation(math.rad(-45))

	button:SetScript("OnEnter", function()
		strokeA:SetColorTexture(Primitives.color("warning"))
		strokeB:SetColorTexture(Primitives.color("warning"))
	end)
	button:SetScript("OnLeave", function()
		strokeA:SetColorTexture(Primitives.color("accent"))
		strokeB:SetColorTexture(Primitives.color("accent"))
	end)

	return button
end

function Primitives.anchorBelow(object, previous, gap)
	object:ClearAllPoints()
	object:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(gap or 8))
end

-- A small downward chevron ("⌄") built from two rotated stroke textures, same technique as
-- createCloseButton's X above (just the bottom two strokes, not all four) -- not a font glyph,
-- so it always renders crisp and consistent regardless of whether the bundled custom font
-- actually has a good-looking "v"/arrow character in it. Used by UI/Widgets/Dropdown.lua's own
-- button in place of the plain text "v" it used to draw.
function Primitives.createChevron(parent, size, colorName)
	size = size or 10
	local icon = CreateFrame("Frame", nil, parent)
	icon:SetSize(size, size)

	local length = size * 0.62
	local thickness = 1.4
	-- Empirical offsets -- centers each stroke so the two meet at a point slightly below the
	-- icon's own center, reading as a single "v" shape rather than two separate floating strokes.
	local spread = length * 0.3

	local legLeft = Primitives.createTexture(icon, "ARTWORK", colorName or "dim")
	legLeft:SetSize(length, thickness)
	legLeft:SetPoint("CENTER", icon, "CENTER", -spread, size * 0.1)
	legLeft:SetRotation(math.rad(-45))

	local legRight = Primitives.createTexture(icon, "ARTWORK", colorName or "dim")
	legRight:SetSize(length, thickness)
	legRight:SetPoint("CENTER", icon, "CENTER", spread, size * 0.1)
	legRight:SetRotation(math.rad(45))

	return icon
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

-- Flat field-colored fill + 1px border like every other widget here -- no BackdropTemplate.
-- EditBox has no native placeholder attribute, so one is faked with the standard WoW idiom (dim
-- placeholder text shown/cleared on focus); call :GetValue() rather than :GetText() to get ""
-- while the placeholder is showing instead of the placeholder string itself.
--
-- An EditBox does NOT clip its own text to its frame bounds on its own -- typed text just keeps
-- extending past the box's declared width/height with nothing to stop it, both for a single-line
-- box (text running past the right border) and a multi-line one (wrapped lines running past the
-- bottom border, growing downward without limit). SetClipsChildren(true) clips the EditBox's own
-- internal FontString to its frame rect like every other child region, fixing both at the root --
-- applied unconditionally, not just for `multiline`, since the single-line case had the exact
-- same bug.
--
-- `multiline`, when true, lets text wrap onto a second line instead of running past the box's
-- right edge on the first one. The box's own height is still whatever `height` says -- callers
-- that want 2 lines actually visible should size it for 2 lines; this only stops a 3rd+ line (or
-- a too-long single line) from being typed at all, via `maxLetters`, rather than relying on the
-- clip to hide runaway overflow.
function Primitives.createEditBox(parent, width, height, placeholder, multiline, maxLetters)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(width, height or 20)
	box:SetAutoFocus(false)
	if box.SetClipsChildren then
		box:SetClipsChildren(true)
	end
	if multiline then
		box:SetMultiLine(true)
		box:SetMaxLetters(maxLetters or 80)
		box:SetTextInsets(6, 6, 2, 2)
		-- MIDDLE, not TOP -- most of the time this box holds just the placeholder or one short
		-- line, and top-justifying that pinned it near the box's top edge while a button sitting
		-- right next to it (UI/LootFrame.lua's response row) centers its label dead in the
		-- middle -- same frame height, same border, but the text inside read as misaligned. Two
		-- lines of wrapped text still read fine centered (the box is sized for ~2 lines, so it
		-- fills most of the height either way).
		box:SetJustifyV("MIDDLE")
	else
		box:SetTextInsets(6, 6, 0, 0)
	end

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

-- Makes `frame` drag-resizable from a small corner grip, bottom-right -- a flat diagonal-dot
-- mark (no dedicated resize-handle art asset), brightening to accent on hover like every other
-- interactive element in this design system. `frame` must already support StartSizing (true for
-- any plain CreateFrame("Frame", ...) once SetResizable(true) is called). Bounds keep the window
-- from shrinking below its content's minimum usable layout.
function Primitives.makeResizable(frame, minWidth, minHeight, maxWidth, maxHeight)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(minWidth, minHeight, maxWidth or 2000, maxHeight or 2000)
	else
		frame:SetMinResize(minWidth, minHeight)
		frame:SetMaxResize(maxWidth or 2000, maxHeight or 2000)
	end

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)

	-- A triangular grid of 6 small dots -- 3 right along the very corner, 2 one step in, 1
	-- furthest -- instead of one undifferentiated square. This is the same glyph classic
	-- Windows/GTK/textarea resize handles use; a single flat dot didn't read as "drag to
	-- resize" to someone who hadn't already stumbled onto it, where this shape is something
	-- most people already recognize on sight.
	local DOT_SIZE = 2
	local PITCH = 4
	grip.dots = {}
	for row = 0, 2 do
		for col = 0, 2 - row do
			local dot = Primitives.createTexture(grip, "OVERLAY", "dim")
			dot:SetSize(DOT_SIZE, DOT_SIZE)
			dot:SetPoint("BOTTOMRIGHT", -(2 + col * PITCH), 2 + row * PITCH)
			table.insert(grip.dots, dot)
		end
	end

	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
	end)
	grip:SetScript("OnHide", function()
		frame:StopMovingOrSizing()
	end)
	grip:SetScript("OnEnter", function()
		for _, dot in ipairs(grip.dots) do
			dot:SetColorTexture(Primitives.color("accent"))
		end
	end)
	grip:SetScript("OnLeave", function()
		for _, dot in ipairs(grip.dots) do
			dot:SetColorTexture(Primitives.color("dim"))
		end
	end)

	return grip
end
