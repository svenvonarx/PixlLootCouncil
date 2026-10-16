local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local PopupMenu = PLC.UI.Widgets.PopupMenu
local Theme = PLC.UI.Theme

local Dropdown = {}
PLC.UI.Widgets.Dropdown = Dropdown

-- A field-styled button showing the current choice with a chevron; clicking opens a
-- UI/Widgets/PopupMenu.lua list. The list comes from Dropdown.setEntries -- selecting is up to
-- each entry's own onClick.
function Dropdown.createDropdownButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(Theme.LAYOUT.fieldWidth, Theme.LAYOUT.fieldHeight)

	button.bg = Primitives.createTexture(button, "BACKGROUND", "field")
	button.bg:SetAllPoints()
	button.border = Primitives.createBorder(button)

	button.arrow = Primitives.createChevron(button, 9, "dim")
	button.arrow:SetPoint("RIGHT", -14, 0)

	button.text = Primitives.createText(button, "", 11)
	button.text:SetJustifyH("LEFT")
	button.text:SetPoint("LEFT", 12, 0)
	button.text:SetPoint("RIGHT", button.arrow, "LEFT", -8, 0)

	button:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(Primitives.color("fieldHover"))
		Primitives.setBorderColor(self.border, "accent", 0.70)
	end)
	button:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(Primitives.color("field"))
		Primitives.setBorderColor(self.border, "border")
	end)
	button:SetScript("OnClick", function(self)
		if not self.menuEntries then
			return
		end
		if PopupMenu.IsOpen(self) then
			PopupMenu.Close()
		else
			PopupMenu.Open(self, self.menuEntries, {
				width = math.max(220, self:GetWidth()),
				maxRows = Theme.LAYOUT.menuMaxRows,
			})
		end
	end)
	return button
end

-- displayText: what the closed dropdown shows. entries: PopupMenu entries (text, checked,
-- onClick, ...), or nil for a dropdown that doesn't open.
function Dropdown.setEntries(button, displayText, entries)
	button.text:SetText(displayText or "")
	button.menuEntries = entries
end
