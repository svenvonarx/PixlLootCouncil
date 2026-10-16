local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Checkbox = {}
PLC.UI.Widgets.Checkbox = Checkbox

-- A label with a small square in front of it; checked shows an accent-filled inner square. The
-- whole row is clickable. onChanged(checked) fires on every click.
local BOX_SIZE = 16
local MARK_INSET = 3

function Checkbox.createCheckbox(parent, text, onChanged)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(Theme.LAYOUT.checkboxWidth, Theme.LAYOUT.checkboxHeight)

	local square = CreateFrame("Frame", nil, row)
	square:SetSize(BOX_SIZE, BOX_SIZE)
	square:SetPoint("LEFT")
	Primitives.createTexture(square, "BACKGROUND", "field"):SetAllPoints()
	row.border = Primitives.createBorder(square)

	row.check = Primitives.createTexture(square, "ARTWORK", "accent")
	row.check:SetPoint("TOPLEFT", MARK_INSET, -MARK_INSET)
	row.check:SetPoint("BOTTOMRIGHT", -MARK_INSET, MARK_INSET)

	row.label = Primitives.createText(row, text, 12)
	row.label:SetPoint("LEFT", square, "RIGHT", 9, 0)

	function row:SetChecked(value)
		self.checked = value and true or false
		self.check:SetShown(self.checked)
	end

	function row:GetChecked()
		return self.checked
	end

	row:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if onChanged then
			onChanged(self.checked)
		end
	end)
	row:SetScript("OnEnter", function(self)
		Primitives.setBorderColor(self.border, "accent", 0.85)
		self.label:SetTextColor(Primitives.color("white"))
	end)
	row:SetScript("OnLeave", function(self)
		Primitives.setBorderColor(self.border, "border")
		self.label:SetTextColor(Primitives.color("text"))
	end)

	row:SetChecked(false)
	return row
end
