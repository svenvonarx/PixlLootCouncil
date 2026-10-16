local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

-- Ported from FojjiCore's OptionsMenu.lua in full (see docs/analysis/fojjicore-ui-style.md) --
-- PopupMenu.Open(owner, entries, opts)/Close()/IsOpen(owner)/Refresh(). Entry fields: text,
-- checked, disabled, tag, onClick, onRemove, onFavorite, favorite, keepOpen, header, color.
-- Options: width, maxRows, openUp.
local PopupMenu = {}
PLC.UI.Widgets.PopupMenu = PopupMenu

local ROW_H, PAD = 22, 3

local popup, catcher, track, thumb
local edges = {}
local rows = {}
local current

local Render

function PopupMenu.IsOpen(owner)
	return current ~= nil and (owner == nil or current.owner == owner)
end

function PopupMenu.Close()
	if popup and popup:IsShown() then
		popup:Hide()
	end
	if catcher then
		catcher:Hide()
	end
	current = nil
end

local function scroll(delta)
	if not current then
		return
	end
	current.offset = current.offset - delta
	Render()
end

local function getRow(index)
	local row = rows[index]
	if row then
		return row
	end

	row = CreateFrame("Button", nil, popup)
	row:SetHeight(ROW_H)

	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:Hide()

	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetWidth(2)
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")

	row.label = Primitives.createText(row, "", 11)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.label:SetPoint("LEFT", 9, 0)

	row.tag = Primitives.createText(row, "", 9, "dim")

	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(ROW_H, ROW_H)
	row.remove:SetPoint("RIGHT")
	row.remove:SetFrameLevel(row:GetFrameLevel() + 3)
	row.remove.x = Primitives.createText(row.remove, "x", 12)
	row.remove.x:SetPoint("CENTER", 0, 1)

	row:EnableMouseWheel(true)
	row:SetScript("OnMouseWheel", function(_, delta)
		scroll(delta)
	end)
	row:SetScript("OnEnter", function(self)
		if self.entry and not self.entry.disabled and not self.entry.header then
			local r, g, b = Primitives.color("accent")
			self.hover:SetColorTexture(r, g, b, 0.16)
			self.hover:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
	end)
	row:SetScript("OnClick", function(self)
		local entry = self.entry
		if not entry or entry.disabled or entry.header then
			return
		end
		if entry.keepOpen then
			if entry.onClick then
				entry.onClick(entry)
			end
			PopupMenu.Refresh()
		else
			PopupMenu.Close()
			if entry.onClick then
				entry.onClick(entry)
			end
		end
	end)
	row.remove:SetScript("OnEnter", function(self)
		local r, g, b = Primitives.color("warning")
		self.x:SetTextColor(r, g, b)
	end)
	row.remove:SetScript("OnLeave", function(self)
		local r, g, b = Primitives.color(row.entry and row.entry.favorite and "accent" or "dim")
		self.x:SetTextColor(r, g, b)
	end)
	row.remove:SetScript("OnClick", function()
		local entry = row.entry
		if not entry or entry.disabled or entry.header then
			return
		end
		if entry.onFavorite then
			entry.favorite = not entry.favorite
			entry.onFavorite(entry.favorite)
			Render()
		elseif entry.onRemove then
			entry.onRemove(entry)
			PopupMenu.Refresh()
		end
	end)

	rows[index] = row
	return row
end

Render = function()
	if not current or not popup then
		return
	end
	local entries = current.entries
	local count = #entries
	local visible = math.min(count, current.maxRows)
	current.offset = math.max(0, math.min(current.offset, math.max(0, count - visible)))
	local scrolling = count > visible
	local width = current.width
	local inner = width - 2 - (scrolling and 7 or 0)

	popup:SetSize(width, visible * ROW_H + PAD * 2)
	local bgR, bgG, bgB = Primitives.color("header")
	popup.bg:SetColorTexture(bgR, bgG, bgB, 0.98)
	local bR, bG, bB = Primitives.color("accent", 0.7)
	for _, edge in ipairs(edges) do
		edge:SetColorTexture(bR, bG, bB, 0.7)
	end

	for index = 1, visible do
		local entry = entries[current.offset + index]
		local row = getRow(index)
		row.entry = entry
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(PAD + (index - 1) * ROW_H))
		row:SetWidth(inner)
		row:SetHeight(ROW_H)
		row.hover:Hide()

		local colorName = (entry.disabled and "dim") or (entry.header and "accent") or "text"
		row.label:SetText(entry.text or "")
		if entry.color then
			row.label:SetTextColor(entry.color.r or entry.color[1], entry.color.g or entry.color[2], entry.color.b or entry.color[3])
		else
			local r, g, b = Primitives.color(colorName)
			row.label:SetTextColor(r, g, b)
		end

		if entry.tag then
			row.tag:SetText(entry.tag)
			row.tag:ClearAllPoints()
			row.tag:SetPoint("RIGHT", row, "RIGHT", (entry.onFavorite and -46) or (entry.onRemove and -(ROW_H + 2)) or -8, 0)
			row.tag:Show()
		else
			row.tag:SetText("")
			row.tag:Hide()
		end

		local reserve = 10 + (entry.onFavorite and 44 or (entry.onRemove and ROW_H or 0))
			+ (entry.tag and ((row.tag:GetStringWidth() or 30) + 8) or 0)
		row.label:ClearAllPoints()
		row.label:SetPoint("LEFT", row, "LEFT", 9, 0)
		row.label:SetPoint("RIGHT", row, "RIGHT", -reserve, 0)

		if entry.checked then
			local r, g, b = Primitives.color("accent")
			row.mark:SetColorTexture(r, g, b, 1)
			row.mark:Show()
		else
			row.mark:Hide()
		end

		row.remove:SetWidth(entry.onFavorite and 40 or ROW_H)
		row.remove.x:SetText(entry.onFavorite and "FAV" or "x")
		row.remove:SetShown(entry.onRemove ~= nil or entry.onFavorite ~= nil)
		local r, g, b = Primitives.color(entry.favorite and "accent" or "dim")
		row.remove.x:SetTextColor(r, g, b)
		row:Show()
	end
	for index = visible + 1, #rows do
		rows[index]:Hide()
		rows[index].entry = nil
	end

	track:SetShown(scrolling)
	thumb:SetShown(scrolling)
	if scrolling then
		local trackHeight = visible * ROW_H
		local size = math.max(14, trackHeight * visible / count)
		local room = trackHeight - size
		local fraction = current.offset / math.max(1, count - visible)
		thumb:SetHeight(size)
		thumb:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -(PAD + room * fraction))
	end
end

function PopupMenu.Refresh()
	Render()
end

local function ensurePopup()
	if popup then
		return
	end

	popup = CreateFrame("Frame", nil, UIParent)
	popup:SetFrameStrata("TOOLTIP")
	popup:EnableMouseWheel(true)
	popup:SetScript("OnMouseWheel", function(_, delta)
		scroll(delta)
	end)

	popup.bg = popup:CreateTexture(nil, "BACKGROUND")
	popup.bg:SetAllPoints()

	popup.border = Primitives.createBorder(popup, "accent", 0.7)
	edges = { popup.border.top, popup.border.bottom, popup.border.left, popup.border.right }

	track = popup:CreateTexture(nil, "ARTWORK")
	track:SetWidth(3)
	track:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -2, -3)
	track:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -2, 3)
	local r, g, b = Primitives.color("scroll")
	track:SetColorTexture(r, g, b, 1)

	thumb = popup:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(3)
	local ar, ag, ab = Primitives.color("accent")
	thumb:SetColorTexture(ar, ag, ab, 0.75)

	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetFrameStrata("TOOLTIP")
	catcher:SetFrameLevel(1)
	catcher:SetAllPoints(UIParent)
	catcher:SetScript("OnClick", PopupMenu.Close)
	catcher:Hide()
end

-- owner: any frame with GetWidth/GetBottom/GetTop (anchors above/below it). opts: width,
-- maxRows, openUp.
function PopupMenu.Open(owner, entries, opts)
	ensurePopup()
	opts = opts or {}

	current = {
		owner = owner,
		entries = entries,
		offset = 0,
		width = opts.width or math.max(220, owner:GetWidth()),
		maxRows = opts.maxRows or 7,
	}

	popup:ClearAllPoints()
	if opts.openUp then
		popup:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
	else
		popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	end
	popup:SetFrameLevel((owner:GetFrameLevel() or 0) + 10)

	Render()
	popup:Show()
	catcher:Show()
	catcher:SetFrameLevel(popup:GetFrameLevel() - 1)
end
