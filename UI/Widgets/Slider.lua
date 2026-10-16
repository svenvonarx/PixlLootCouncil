local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Slider = {}
PLC.UI.Widgets.Slider = Slider

-- Ported from FojjiCore (Options.lua:338-377, see docs/analysis/fojjicore-ui-style.md): a real
-- Slider frame over a flat 4px track, with a solid accent-colored thumb texture -- no separate
-- fill/progress bar.
function Slider.createSlider(parent, labelText, minValue, maxValue, step)
	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(Theme.LAYOUT.sliderWidth + 75, Theme.LAYOUT.sliderHeight)

	local label = Primitives.createText(container, labelText, 13, "white")
	label:SetPoint("TOPLEFT")

	local track = CreateFrame("Frame", nil, container)
	track:SetSize(Theme.LAYOUT.sliderWidth, 18)
	track:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -13)

	local bg = Primitives.createTexture(track, "BACKGROUND", "scroll")
	bg:SetPoint("LEFT")
	bg:SetPoint("RIGHT")
	bg:SetHeight(4)

	local slider = CreateFrame("Slider", nil, track)
	slider:SetAllPoints()
	slider:SetOrientation("HORIZONTAL")
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)

	local thumb = slider:CreateTexture(nil, "ARTWORK")
	thumb:SetSize(12, 20)
	thumb:SetColorTexture(Primitives.color("accent"))
	slider:SetThumbTexture(thumb)

	local minText = Primitives.createText(container, tostring(minValue), 10, "dim")
	minText:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -4)

	local maxText = Primitives.createText(container, tostring(maxValue), 10, "dim")
	maxText:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -4)

	slider.valueText = Primitives.createText(container, "", 12, "white")
	slider.valueText:SetPoint("LEFT", track, "RIGHT", 20, 0)
	slider.container = container

	return slider
end
