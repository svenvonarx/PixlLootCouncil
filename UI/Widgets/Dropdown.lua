local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local PopupMenu = PLC.UI.Widgets.PopupMenu
local Theme = PLC.UI.Theme

local Dropdown = {}
PLC.UI.Widgets.Dropdown = Dropdown

-- Ported from FojjiCore (Options.lua:421-450, see docs/analysis/fojjicore-ui-style.md): a flat
-- field-colored button with a right-aligned "v" text glyph (not a texture).
function Dropdown.createDropdownButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(Theme.LAYOUT.fieldWidth, Theme.LAYOUT.fieldHeight)

	button.bg = Primitives.createTexture(button, "BACKGROUND", "field")
	button.bg:SetAllPoints()

	button.border = Primitives.createBorder(button)

	button.text = Primitives.createText(button, "", 11)
	button.text:SetPoint("LEFT", 12, 0)
	button.text:SetPoint("RIGHT", -38, 0)
	button.text:SetJustifyH("LEFT")

	button.arrow = Primitives.createText(button, "v", 11)
	button.arrow:SetTextColor(0.65, 0.68, 0.72)
	button.arrow:SetPoint("RIGHT", -14, 2)

	button:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(Primitives.color("fieldHover"))
		Primitives.setBorderColor(self.border, "accent", 0.70)
	end)

	button:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(Primitives.color("field"))
		Primitives.setBorderColor(self.border, "border")
	end)

	button:SetScript("OnClick", function(self)
		if button.menuEntries then
			PopupMenu.Open(self, button.menuEntries, { width = math.max(220, self:GetWidth()), maxRows = Theme.LAYOUT.menuMaxRows })
		end
	end)

	return button
end

-- Sets both the button's displayed text and the entry list its click handler opens. entries:
-- array of { text, selected, onClick(entry) }. Selecting an entry is the caller's job (via
-- onClick) -- this just wires the button to the popup list (ported createDropdownMenu,
-- Options.lua:452-463).
function Dropdown.setEntries(button, displayText, entries)
	button.text:SetText(displayText or "")
	button.menuEntries = entries
end
