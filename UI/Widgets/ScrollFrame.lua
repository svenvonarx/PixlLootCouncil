local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives

local ScrollFrame = {}
PLC.UI.Widgets.ScrollFrame = ScrollFrame

-- Ported from FojjiCore (Options.lua:391-419, see docs/analysis/fojjicore-ui-style.md): a plain
-- ScrollFrame plus a custom 7px vertical scrollbar that auto-hides when there's nothing to
-- scroll -- reworked from the original port to reserve the scrollbar's own space, see below.
local BAR_WIDTH = 7
local BAR_GAP = 4
local RESERVED_WIDTH = BAR_WIDTH + BAR_GAP
-- Exposed so a caller that needs to size a container to fit an exact content width *and* the
-- scrollbar (e.g. UI/SessionFrame.lua's icon sidebar, sized to exactly fit 2 icon columns) can
-- add this instead of hardcoding/duplicating the same number.
ScrollFrame.RESERVED_WIDTH = RESERVED_WIDTH

-- Takes the full container every caller actually wants filled (previously callers had to
-- `scroll:SetAllPoints()` themselves AND separately leave room to the right for the scrollbar,
-- which FojjiCore's original anchored 10px past the scroll frame's own right edge -- every
-- caller in this codebase just filled their full container instead, so the scrollbar always
-- rendered 10-17px past the window's own edge. Now self-contained: pass the container to fill,
-- get back the actual scrollable viewport (already narrower, by RESERVED_WIDTH, than `parent`),
-- and the bar lives entirely inside that reserved strip -- nothing to remember at the call site.
function ScrollFrame.createScrollFrame(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -RESERVED_WIDTH, 0)
	scroll:EnableMouseWheel(true)

	local bar = CreateFrame("Slider", nil, parent)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", BAR_GAP, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", BAR_GAP, 0)
	bar:SetWidth(BAR_WIDTH)
	bar:SetOrientation("VERTICAL")
	bar:SetMinMaxValues(0, 0)
	bar:SetValueStep(1)
	-- Hidden until the first OnScrollRangeChanged confirms there's actually something to scroll
	-- (below) -- shown-by-default-until-proven-otherwise was the "visible with no overflow" bug.
	bar:Hide()

	local track = Primitives.createTexture(bar, "BACKGROUND", "borderDim")
	track:SetAllPoints()

	local thumb = Primitives.createTexture(bar, "ARTWORK", "accent", 0.65)
	thumb:SetSize(BAR_WIDTH, 36)
	bar:SetThumbTexture(thumb)

	bar:SetScript("OnValueChanged", function(_, value)
		scroll:SetVerticalScroll(value)
	end)
	scroll:SetScript("OnScrollRangeChanged", function(_, _, range)
		bar:SetMinMaxValues(0, range)
		bar:SetShown(range > 0)
		local current = scroll:GetVerticalScroll() or 0
		if current > range then
			current = range
			scroll:SetVerticalScroll(current)
		end
		-- Explicitly resyncs the thumb's drawn position to the real current offset every time
		-- the scrollable range changes (i.e. on every content resize, which for a DataTable is
		-- most row updates) -- previously the thumb only ever moved reactively from
		-- OnVerticalScroll below, which a range change alone doesn't fire, so the thumb could
		-- sit at a stale position until the user dragged it (the "doesn't show the current
		-- position until you click it" bug).
		bar:SetValue(current)
	end)
	-- A post-hook on the method itself, not `scroll:SetScript("OnVerticalScroll", ...)` -- every
	-- caller of this widget (UI/Widgets/DataTable.lua included) sets its own OnVerticalScroll
	-- script to re-render visible rows on scroll, and SetScript REPLACES whatever script was
	-- there before rather than stacking with it. That silently ate this thumb-sync entirely
	-- (confirmed: DataTable.lua's own OnVerticalScroll handler was overwriting this one), so the
	-- thumb stopped tracking the mouse wheel. hooksecurefunc runs alongside any OnVerticalScroll
	-- script a caller sets, regardless of order, since it hooks the method call itself rather
	-- than competing for the same script slot.
	hooksecurefunc(scroll, "SetVerticalScroll", function(_, value)
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
