local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives

-- One shared popup list, used by dropdowns and the history filter menu. Only one is open at a
-- time; clicking anywhere outside closes it.
--
--   PopupMenu.Open(owner, entries, opts)  opens below `owner` (opts.openUp: above it).
--                                         opts.width (default: owner's width, min 220),
--                                         opts.maxRows (default 7, the list scrolls past that)
--   PopupMenu.Close() / PopupMenu.IsOpen(owner) / PopupMenu.Refresh()
--
-- Entry fields: text; color ({r,g,b} or {r=,g=,b=}); checked (accent marker on the left);
-- header (an accent-colored, unclickable section title); disabled (dimmed, unclickable);
-- onClick(entry); keepOpen (stay open after the click and redraw -- for toggle lists, where
-- onClick updates entry.checked itself).
local PopupMenu = {}
PLC.UI.Widgets.PopupMenu = PopupMenu

local ROW_HEIGHT = 22
local PADDING = 3
local SCROLLBAR_WIDTH = 3

local menu -- the popup frame, built on first use
local blocker -- full-screen click catcher behind it
local state -- { owner, entries, first, width, maxRows } while open

local draw -- forward-declared: rows call it on scroll

local function isClickable(entry)
	return entry ~= nil and not entry.header and not entry.disabled
end

local function entryColor(entry)
	if entry.color then
		local c = entry.color
		return c.r or c[1], c.g or c[2], c.b or c[3]
	end
	return Primitives.color((entry.disabled and "dim") or (entry.header and "accent") or "text")
end

local function scrollBy(rows)
	if state then
		state.first = state.first + rows
		draw()
	end
end

local function onRowClick(row)
	local entry = row.entry
	if not isClickable(entry) then
		return
	end
	if entry.keepOpen then
		if entry.onClick then
			entry.onClick(entry)
		end
		draw()
		return
	end
	PopupMenu.Close()
	if entry.onClick then
		entry.onClick(entry)
	end
end

local function makeRow()
	local row = CreateFrame("Button", nil, menu)
	row:SetHeight(ROW_HEIGHT)

	row.highlight = row:CreateTexture(nil, "BACKGROUND")
	row.highlight:SetAllPoints()
	row.highlight:Hide()

	row.marker = row:CreateTexture(nil, "ARTWORK")
	row.marker:SetWidth(2)
	row.marker:SetPoint("TOPLEFT")
	row.marker:SetPoint("BOTTOMLEFT")

	row.label = Primitives.createText(row, "", 11)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.label:SetPoint("LEFT", 9, 0)
	row.label:SetPoint("RIGHT", -8, 0)

	row:EnableMouseWheel(true)
	row:SetScript("OnMouseWheel", function(_, delta) scrollBy(-delta) end)
	row:SetScript("OnClick", onRowClick)
	row:SetScript("OnEnter", function(self)
		if isClickable(self.entry) then
			local r, g, b = Primitives.color("accent")
			self.highlight:SetColorTexture(r, g, b, 0.16)
			self.highlight:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.highlight:Hide()
	end)
	return row
end

local function build()
	menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("TOOLTIP")
	menu:EnableMouse(true)
	menu:EnableMouseWheel(true)
	menu:SetScript("OnMouseWheel", function(_, delta) scrollBy(-delta) end)
	menu.bg = menu:CreateTexture(nil, "BACKGROUND")
	menu.bg:SetAllPoints()
	menu.border = Primitives.createBorder(menu, "accent", 0.7)
	menu.rows = {}

	menu.track = menu:CreateTexture(nil, "ARTWORK")
	menu.track:SetWidth(SCROLLBAR_WIDTH)
	menu.track:SetPoint("TOPRIGHT", -2, -PADDING)
	menu.track:SetPoint("BOTTOMRIGHT", -2, PADDING)
	menu.thumb = menu:CreateTexture(nil, "OVERLAY")
	menu.thumb:SetWidth(SCROLLBAR_WIDTH)

	blocker = CreateFrame("Button", nil, UIParent)
	blocker:SetFrameStrata("TOOLTIP")
	blocker:SetAllPoints(UIParent)
	blocker:SetScript("OnClick", PopupMenu.Close)
	blocker:Hide()
end

function draw()
	if not state then
		return
	end
	local entries = state.entries
	local visible = math.min(#entries, state.maxRows)
	local lastFirst = math.max(1, #entries - visible + 1)
	state.first = math.max(1, math.min(state.first, lastFirst))
	local scrolls = #entries > visible

	local hr, hg, hb = Primitives.color("header")
	menu.bg:SetColorTexture(hr, hg, hb, 0.98)
	menu:SetSize(state.width, visible * ROW_HEIGHT + PADDING * 2)

	local rowWidth = state.width - 2 - (scrolls and (SCROLLBAR_WIDTH + 4) or 0)
	for i = 1, visible do
		local row = menu.rows[i] or makeRow()
		menu.rows[i] = row
		local entry = entries[state.first + i - 1]
		row.entry = entry
		row:SetWidth(rowWidth)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 1, -PADDING - (i - 1) * ROW_HEIGHT)
		row.highlight:Hide()
		row.label:SetText(entry.text or "")
		row.label:SetTextColor(entryColor(entry))
		if entry.checked then
			local r, g, b = Primitives.color("accent")
			row.marker:SetColorTexture(r, g, b, 1)
		end
		row.marker:SetShown(entry.checked and true or false)
		row:Show()
	end
	for i = visible + 1, #menu.rows do
		menu.rows[i]:Hide()
		menu.rows[i].entry = nil
	end

	menu.track:SetShown(scrolls)
	menu.thumb:SetShown(scrolls)
	if scrolls then
		local tr, tg, tb = Primitives.color("scroll")
		menu.track:SetColorTexture(tr, tg, tb, 1)
		local ar, ag, ab = Primitives.color("accent")
		menu.thumb:SetColorTexture(ar, ag, ab, 0.75)
		local trackHeight = visible * ROW_HEIGHT
		local thumbHeight = math.max(14, trackHeight * visible / #entries)
		local progress = (state.first - 1) / (lastFirst - 1)
		menu.thumb:SetHeight(thumbHeight)
		menu.thumb:ClearAllPoints()
		menu.thumb:SetPoint("TOPRIGHT", -2, -PADDING - (trackHeight - thumbHeight) * progress)
	end
end

function PopupMenu.Open(owner, entries, opts)
	if not menu then
		build()
	end
	opts = opts or {}
	state = {
		owner = owner,
		entries = entries,
		first = 1,
		width = opts.width or math.max(220, owner:GetWidth()),
		maxRows = opts.maxRows or 7,
	}
	menu:ClearAllPoints()
	if opts.openUp then
		menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
	else
		menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	end
	local level = (owner:GetFrameLevel() or 0) + 10
	menu:SetFrameLevel(level)
	blocker:SetFrameLevel(level - 1)
	draw()
	blocker:Show()
	menu:Show()
end

function PopupMenu.Close()
	state = nil
	if menu then
		menu:Hide()
		blocker:Hide()
	end
end

function PopupMenu.IsOpen(owner)
	return state ~= nil and (owner == nil or state.owner == owner)
end

function PopupMenu.Refresh()
	draw()
end
