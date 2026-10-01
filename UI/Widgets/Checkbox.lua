local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Checkbox = {}
PLC.UI.Widgets.Checkbox = Checkbox

-- Ported from FojjiCore (Options.lua:285-336, see docs/analysis/fojjicore-ui-style.md): a custom
-- 16x16 box (not the Blizzard CheckButton template) with a flat accent-colored fill as the check
-- mark, shown/hidden rather than drawn as a glyph.
function Checkbox.createCheckbox(parent, text, onChanged)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(Theme.LAYOUT.checkboxWidth, Theme.LAYOUT.checkboxHeight)

	local box = CreateFrame("Frame", nil, button)
	box:SetSize(16, 16)
	box:SetPoint("LEFT")

	local bg = Primitives.createTexture(box, "BACKGROUND", "field")
	bg:SetAllPoints()

	button.border = Primitives.createBorder(box, "border")

	button.check = Primitives.createTexture(box, "ARTWORK", "accent")
	button.check:SetPoint("TOPLEFT", 3, -3)
	button.check:SetPoint("BOTTOMRIGHT", -3, 3)
	button.check:Hide()

	button.label = Primitives.createText(button, text, 12)
	button.label:SetPoint("LEFT", box, "RIGHT", 9, 0)

	button.checked = false

	function button:SetChecked(value)
		self.checked = value and true or false
		self.check:SetShown(self.checked)
	end

	function button:GetChecked()
		return self.checked
	end

	button:SetScript("OnClick", function(self)
		self:SetChecked(not self:GetChecked())
		if onChanged then
			onChanged(self:GetChecked())
		end
	end)

	button:SetScript("OnEnter", function(self)
		Primitives.setBorderColor(self.border, "accent", 0.85)
		self.label:SetTextColor(Primitives.color("white"))
	end)

	button:SetScript("OnLeave", function(self)
		Primitives.setBorderColor(self.border, "border")
		local r, g, b = Primitives.color("text")
		self.label:SetTextColor(r, g, b)
	end)

	return button
end
