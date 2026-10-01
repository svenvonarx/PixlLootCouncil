local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Button = {}
PLC.UI.Widgets.Button = Button

-- Ported from FojjiCore (Options.lua:260-283, see docs/analysis/fojjicore-ui-style.md): flat
-- fill + 1px border, centered label, hover swaps bg to buttonHover and borders to accent.
function Button.createButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, Theme.LAYOUT.buttonHeight)

	button.bg = Primitives.createTexture(button, "BACKGROUND", "button")
	button.bg:SetAllPoints()

	button.border = Primitives.createBorder(button)

	button.label = Primitives.createText(button, text, 12)
	button.label:SetPoint("CENTER")

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
