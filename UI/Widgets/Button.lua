local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Button = {}
PLC.UI.Widgets.Button = Button

-- Ported from FojjiCore (Options.lua:260-283, see docs/analysis/fojjicore-ui-style.md): flat
-- fill + 1px border, centered label, hover swaps bg to buttonHover and borders to accent.
--
-- `width` is optional -- omit it (or pass nil/false) for a button that sizes itself to its own
-- label instead of a caller-chosen fixed width. UI/LootFrame.lua's 5 response buttons used to
-- share one fixed width, which left short labels like "OS" swimming in padding while longer ones
-- like "Upgrade" looked cramped against their own border.
local BUTTON_PADDING_X = 20
local MIN_BUTTON_WIDTH = 36

function Button.createButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent)

	button.bg = Primitives.createTexture(button, "BACKGROUND", "button")
	button.bg:SetAllPoints()

	button.border = Primitives.createBorder(button)

	button.label = Primitives.createText(button, text, 12)
	button.label:SetPoint("CENTER")

	if width then
		button:SetSize(width, Theme.LAYOUT.buttonHeight)
	else
		button:SetSize(math.max(MIN_BUTTON_WIDTH, button.label:GetStringWidth() + BUTTON_PADDING_X), Theme.LAYOUT.buttonHeight)
	end

	button:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(Primitives.color("buttonHover"))
		Primitives.setBorderColor(self.border, "accent", 0.75)
	end)

	button:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(Primitives.color("button"))
		Primitives.setBorderColor(self.border, "border")
	end)

	return button
end
