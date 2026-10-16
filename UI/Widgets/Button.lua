local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Button = {}
PLC.UI.Widgets.Button = Button

-- Flat buttons: a filled rectangle with a 1px border and a centered label. Hovering lightens the
-- fill and lights the border in the accent color.
--
-- `width` is optional: without it the button fits its label (with padding, never narrower than
-- MIN_WIDTH), which suits rows of short, different-length captions like the Loot Response window's
-- response buttons.
local PADDING = 20
local MIN_WIDTH = 36

local function setHovered(button, hovered)
	button.bg:SetColorTexture(Primitives.color(hovered and "buttonHover" or "button"))
	if hovered then
		Primitives.setBorderColor(button.border, "accent", 0.75)
	else
		Primitives.setBorderColor(button.border, "border")
	end
end

local function decorate(button, text, width)
	button.bg = Primitives.createTexture(button, "BACKGROUND", "button")
	button.bg:SetAllPoints()
	button.border = Primitives.createBorder(button)
	button.label = Primitives.createText(button, text, 12)
	button.label:SetPoint("CENTER")

	local w = width or math.max(MIN_WIDTH, button.label:GetStringWidth() + PADDING)
	button:SetSize(w, Theme.LAYOUT.buttonHeight)

	button:SetScript("OnEnter", function(self) setHovered(self, true) end)
	button:SetScript("OnLeave", function(self) setHovered(self, false) end)
	return button
end

function Button.createButton(parent, text, width)
	return decorate(CreateFrame("Button", nil, parent), text, width)
end

-- Same look, but a secure macro button: for actions that must cast a protected spell (the
-- one-click Disenchant in Loot/Trade.lua). Casting from plain Lua would be blocked; the macro is
-- run by Blizzard's own secure code. The caller sets :SetAttribute("macrotext", ...) -- never
-- during combat lockdown, when secure attributes can't change.
function Button.createActionButton(parent, text, width)
	local button = decorate(CreateFrame("Button", nil, parent, "SecureActionButtonTemplate"), text, width)
	button:SetAttribute("type", "macro")
	button:RegisterForClicks("AnyUp", "AnyDown")
	return button
end
