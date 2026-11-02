local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Slider = {}
PLC.UI.Widgets.Slider = Slider

-- A titled horizontal slider: the title on the left with the current value lined up on the right, and
-- a thin track with an accent handle under both, as wide as whatever the caller anchors it to. Returns
-- the Slider itself; position its outer frame, slider.container, by both sides. formatValue(value)
-- turns a value into what's shown: a person wants "1 minute", not 60.
local TRACK_HEIGHT = 18
local RAIL_HEIGHT = 4
local HANDLE_WIDTH, HANDLE_HEIGHT = 10, 12

function Slider.createSlider(parent, labelText, minValue, maxValue, step, formatValue)
	local container = CreateFrame("Frame", nil, parent)
	container:SetHeight(Theme.LAYOUT.sliderHeight)

	local title = Primitives.createText(container, labelText, 12)
	title:SetPoint("TOPLEFT")

	local slider = CreateFrame("Slider", nil, container)
	slider:SetHeight(TRACK_HEIGHT)
	slider:SetPoint("BOTTOMLEFT")
	slider:SetPoint("BOTTOMRIGHT")
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)

	local rail = Primitives.createTexture(slider, "BACKGROUND", "scroll")
	rail:SetHeight(RAIL_HEIGHT)
	rail:SetPoint("LEFT")
	rail:SetPoint("RIGHT")

	local handle = Primitives.createTexture(slider, "ARTWORK", "accent")
	handle:SetSize(HANDLE_WIDTH, HANDLE_HEIGHT)
	slider:SetThumbTexture(handle)

	local valueText = Primitives.createText(container, "", 12, "white")
	valueText:SetPoint("TOPRIGHT")

	function slider:ShowValue(value)
		valueText:SetText(formatValue and formatValue(value) or tostring(value))
	end

	slider.container = container
	return slider
end
