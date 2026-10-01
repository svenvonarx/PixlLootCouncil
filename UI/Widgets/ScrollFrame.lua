local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives

local ScrollFrame = {}
PLC.UI.Widgets.ScrollFrame = ScrollFrame

-- Ported directly from FojjiCore (Options.lua:391-419, see docs/analysis/fojjicore-ui-style.md):
-- a plain ScrollFrame plus a custom 7px vertical scrollbar that auto-hides when there's nothing
-- to scroll.
function ScrollFrame.createScrollFrame(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:EnableMouseWheel(true)

	local bar = CreateFrame("Slider", nil, scroll)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 10, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 10, 0)
	bar:SetWidth(7)
	bar:SetOrientation("VERTICAL")
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)

	local track = Primitives.createTexture(bar, "BACKGROUND", "borderDim")
	track:SetAllPoints()

	local thumb = Primitives.createTexture(bar, "ARTWORK", "accent", 0.65)
	thumb:SetSize(7, 36)
	bar:SetThumbTexture(thumb)

	bar:SetScript("OnValueChanged", function(_, value)
		scroll:SetVerticalScroll(value)
	end)
	scroll:SetScript("OnScrollRangeChanged", function(_, _, range)
		bar:SetMinMaxValues(0, range)
		bar:SetShown(range > 0)
		if scroll:GetVerticalScroll() > range then
			scroll:SetVerticalScroll(range)
		end
	end)
	scroll:SetScript("OnVerticalScroll", function(_, value)
		if bar:GetValue() ~= value then
			bar:SetValue(value)
		end
	end)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		local range = scroll:GetVerticalScrollRange()
		local current = scroll:GetVerticalScroll()
		scroll:SetVerticalScroll(math.max(0, math.min(range, current - delta * 36)))
	end)

	return scroll
end
