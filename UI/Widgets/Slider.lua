local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Slider = {}
PLC.UI.Widgets.Slider = Slider

-- A titled horizontal slider: label on top, a thin track with an accent handle, min/max captions
-- underneath and the current value to the right. Returns the Slider itself; its outer frame is
-- slider.container (position that) and slider.valueText is the value caption (the caller updates
-- it from OnValueChanged).
local TRACK_HEIGHT = 18
local RAIL_HEIGHT = 4

function Slider.createSlider(parent, labelText, minValue, maxValue, step)
	local width = Theme.LAYOUT.sliderWidth
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(width + 75, Theme.LAYOUT.sliderHeight)

	local title = Primitives.createText(container, labelText, 13, "white")
	title:SetPoint("TOPLEFT")

	local slider = CreateFrame("Slider", nil, container)
	slider:SetSize(width, TRACK_HEIGHT)
	slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -13)
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)

	local rail = Primitives.createTexture(slider, "BACKGROUND", "scroll")
	rail:SetHeight(RAIL_HEIGHT)
	rail:SetPoint("LEFT")
	rail:SetPoint("RIGHT")

	local handle = Primitives.createTexture(slider, "ARTWORK", "accent")
	handle:SetSize(12, 20)
	slider:SetThumbTexture(handle)

	local low = Primitives.createText(container, tostring(minValue), 10, "dim")
	low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -4)
	local high = Primitives.createText(container, tostring(maxValue), 10, "dim")
	high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -4)

	slider.valueText = Primitives.createText(container, "", 12, "white")
	slider.valueText:SetPoint("LEFT", slider, "RIGHT", 20, 0)
	slider.container = container
	return slider
end
