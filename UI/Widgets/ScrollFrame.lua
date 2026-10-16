local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives

local ScrollFrame = {}
PLC.UI.Widgets.ScrollFrame = ScrollFrame

-- Scrolling areas with a slim custom scrollbar. Both helpers fill the container they're given and
-- keep a strip of RESERVED_WIDTH on its right for the bar, so the bar never sticks out of a window;
-- the bar only shows when there's something to scroll.
--   createScrollFrame(parent)          pixel-based ScrollFrame, for content with its own height
--                                      (the export/import text boxes): set a scroll child.
--   createRowScroll(parent, onScroll)  row-indexed, for UI/Widgets/DataTable.lua.
local BAR_WIDTH = 7
local BAR_GAP = 4
ScrollFrame.RESERVED_WIDTH = BAR_WIDTH + BAR_GAP

local WHEEL_PIXELS = 36
local WHEEL_ROWS = 2

local function makeViewport(frameType, parent)
	local viewport = CreateFrame(frameType, nil, parent)
	viewport:SetPoint("TOPLEFT")
	viewport:SetPoint("BOTTOMRIGHT", -ScrollFrame.RESERVED_WIDTH, 0)
	viewport:EnableMouseWheel(true)
	return viewport
end

-- The vertical bar to the right of `viewport`: a Slider with a dim track and accent thumb.
local function makeBar(parent, viewport)
	local bar = CreateFrame("Slider", nil, parent)
	bar:SetWidth(BAR_WIDTH)
	bar:SetPoint("TOPLEFT", viewport, "TOPRIGHT", BAR_GAP, 0)
	bar:SetPoint("BOTTOMLEFT", viewport, "BOTTOMRIGHT", BAR_GAP, 0)
	bar:SetOrientation("VERTICAL")
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	Primitives.createTexture(bar, "BACKGROUND", "borderDim"):SetAllPoints()
	local thumb = Primitives.createTexture(bar, "ARTWORK", "accent", 0.65)
	thumb:SetSize(BAR_WIDTH, 36)
	bar:SetThumbTexture(thumb)
	bar:Hide()
	return bar
end

function ScrollFrame.createScrollFrame(parent)
	local scroll = makeViewport("ScrollFrame", parent)
	local bar = makeBar(parent, scroll)

	bar:SetScript("OnValueChanged", function(_, value)
		scroll:SetVerticalScroll(value)
	end)
	-- Content grew or shrank: resize the bar's range, clamp, and keep the thumb in sync.
	scroll:SetScript("OnScrollRangeChanged", function(self, _, range)
		bar:SetMinMaxValues(0, range)
		bar:SetShown(range > 0)
		local position = math.min(self:GetVerticalScroll() or 0, range)
		self:SetVerticalScroll(position)
		bar:SetValue(position)
	end)
	-- Hooked rather than set as a script, so a caller's own OnVerticalScroll script can't replace it.
	hooksecurefunc(scroll, "SetVerticalScroll", function(_, value)
		if bar:GetValue() ~= value then
			bar:SetValue(value)
		end
	end)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local target = (self:GetVerticalScroll() or 0) - delta * WHEEL_PIXELS
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), target)))
	end)
	return scroll
end

-- Position is a first-row offset, not pixels: a pixel-based child as tall as all rows stops
-- scrolling somewhere past ~23000px, which cut long tables (the loot history) off partway.
-- Returns a clipped viewport with :SetMaxOffset(n), :GetOffset() and :SetOffset(n) (clamped;
-- calls onScroll(offset) when it changes).
function ScrollFrame.createRowScroll(parent, onScroll)
	local viewport = makeViewport("Frame", parent)
	viewport:SetClipsChildren(true)
	local bar = makeBar(parent, viewport)
	if bar.SetObeyStepOnDrag then
		bar:SetObeyStepOnDrag(true)
	end

	local offset, maxOffset = 0, 0

	function viewport:GetOffset()
		return offset
	end

	function viewport:SetOffset(value)
		value = math.max(0, math.min(maxOffset, math.floor((value or 0) + 0.5)))
		if bar:GetValue() ~= value then
			bar:SetValue(value)
		end
		if value ~= offset then
			offset = value
			if onScroll then
				onScroll(offset)
			end
		end
	end

	function viewport:SetMaxOffset(value)
		maxOffset = math.max(0, value or 0)
		bar:SetMinMaxValues(0, maxOffset)
		bar:SetShown(maxOffset > 0)
		if offset > maxOffset then
			self:SetOffset(maxOffset)
		else
			bar:SetValue(offset)
		end
	end

	bar:SetScript("OnValueChanged", function(_, value)
		viewport:SetOffset(value)
	end)
	viewport:SetScript("OnMouseWheel", function(self, delta)
		self:SetOffset(offset - delta * WHEEL_ROWS)
	end)
	return viewport
end
