local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

-- A settings-style window: title bar, a navigation column on the left (section titles and
-- icon tabs), and a content area showing one page at a time under its own title and description.
-- Used by the Options window.
--   local panel = PanelLayout.Create({ name = "GlobalName", title = "...", width = , height = })
--   panel:AddSidebarHeader("SECTION")
--   local page = panel:AddTab("key", "Tab name", { icon = "nav_general.png", description = "..." })
--   panel:Show()
local PanelLayout = {}
PLC.UI.Widgets.PanelLayout = PanelLayout

local Panel = {}
Panel.__index = Panel

local NAV_INSET = 8 -- left/right margin of nav entries inside the column
local NAV_ROW_HEIGHT = 30
local NAV_ICON_SIZE = 16
local SECTION_GAP = 14 -- space above a section title (after the first)
local PAGE_HEADER_HEIGHT = 58
local PAGE_FADE_SECONDS = 0.12

local function buildTitleBar(frame, title)
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetHeight(Theme.LAYOUT.headerHeight)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	Primitives.createTexture(bar, "BACKGROUND", "header"):SetAllPoints()

	bar.logo = Primitives.createLogo(bar, 20)
	bar.logo:SetPoint("LEFT", 10, 0)
	bar.title = Primitives.createText(bar, title or "", 18, "title")
	-- -2: a font string's LEFT anchor centers its whole line box (descender room included), so
	-- large text sits visibly high without a small downward nudge.
	bar.title:SetPoint("LEFT", bar.logo, "RIGHT", 8, -2)

	bar.close = Primitives.createCloseButton(bar, 20)
	bar.close:SetPoint("RIGHT", -6, 0)
	bar.close:SetScript("OnClick", function()
		frame:Hide()
	end)

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)
	return bar
end

function PanelLayout.Create(opts)
	local frame = CreateFrame("Frame", opts.name, UIParent)
	Primitives.refreshFontsOnShow(frame)
	frame:SetSize(opts.width or 760, opts.height or 540)
	frame:SetPoint("CENTER")
	-- Below the Loot Session window (DIALOG) and Loot Response (FULLSCREEN_DIALOG): settings are
	-- the least urgent thing on screen.
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if opts.name then
		tinsert(UISpecialFrames, opts.name) -- Escape closes it
	end
	Primitives.createTexture(frame, "BACKGROUND", "frame"):SetAllPoints()
	Primitives.createBorder(frame)

	local header = buildTitleBar(frame, opts.title)

	local nav = CreateFrame("Frame", nil, frame)
	nav:SetWidth(Theme.LAYOUT.sidebarWidth)
	nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
	nav:SetPoint("BOTTOMLEFT")
	Primitives.createTexture(nav, "BACKGROUND", "sidebar"):SetAllPoints()

	local rule = Primitives.createTexture(frame, "ARTWORK", "borderDim")
	rule:SetWidth(1)
	rule:SetPoint("TOPLEFT", nav, "TOPRIGHT")
	rule:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT")

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 1, 0)
	content:SetPoint("BOTTOMRIGHT")
	Primitives.createTexture(content, "BACKGROUND", "content"):SetAllPoints()

	frame:Hide()
	local panel = setmetatable({
		frame = frame,
		header = header,
		sidebar = nav,
		content = content,
		tabs = {}, -- [key] = { page, button, title }
		cursorY = -12, -- next free y in the nav column
		sections = 0,
	}, Panel)
	-- The selected tab's accent colors follow accent changes.
	Theme:OnRefresh(function()
		if panel.selected then
			panel:SelectTab(panel.selected, true)
		end
	end)
	return panel
end

-- A section title in the nav column: small accent capitals, with a divider above every section
-- but the first.
function Panel:AddSidebarHeader(text)
	if self.sections > 0 then
		self.cursorY = self.cursorY - SECTION_GAP / 2
		local divider = Primitives.createTexture(self.sidebar, "ARTWORK", "borderDim")
		divider:SetHeight(1)
		divider:SetPoint("TOPLEFT", NAV_INSET + 4, self.cursorY)
		divider:SetPoint("TOPRIGHT", -(NAV_INSET + 4), self.cursorY)
		self.cursorY = self.cursorY - SECTION_GAP / 2 - 4
	end
	self.sections = self.sections + 1
	local label = Primitives.createText(self.sidebar, text, 10, "accent")
	label:SetPoint("TOPLEFT", NAV_INSET + 4, self.cursorY)
	self.cursorY = self.cursorY - 20
end

-- Selected: accent side bar, an accent wash fading to the right, accent icon, white label.
-- Hovered: a faint light wash. Otherwise: dim icon, regular label.
local function paintTab(button, selected, hovered)
	local ar, ag, ab = Primitives.color("accent")
	button.bar:SetShown(selected)
	if selected then
		button.bar:SetColorTexture(ar, ag, ab, 1)
		button.wash:SetColorTexture(1, 1, 1, 1)
		if button.wash.SetGradient and CreateColor then
			button.wash:SetGradient("HORIZONTAL", CreateColor(ar, ag, ab, 0.20), CreateColor(ar, ag, ab, 0.03))
		else
			button.wash:SetColorTexture(ar, ag, ab, 0.12)
		end
		button.wash:Show()
		button.icon:SetVertexColor(ar, ag, ab)
		button.label:SetTextColor(Primitives.color("white"))
	else
		if button.wash.SetGradient and CreateColor then
			-- Reset any gradient left from being selected before the flat hover color.
			button.wash:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
		end
		button.wash:SetColorTexture(1, 1, 1, 0.04)
		button.wash:SetShown(hovered)
		local r, g, b = Primitives.color(hovered and "text" or "dim")
		button.icon:SetVertexColor(r, g, b)
		button.label:SetTextColor(Primitives.color(hovered and "white" or "text"))
	end
end

local function buildPageHeader(content, opts)
	local padding = Theme.LAYOUT.contentPadding
	local holder = CreateFrame("Frame", nil, content)
	holder:SetPoint("TOPLEFT", padding, -padding + 2)
	holder:SetPoint("TOPRIGHT", -padding, -padding + 2)
	holder:SetHeight(PAGE_HEADER_HEIGHT - padding)
	holder:Hide()

	holder.title = Primitives.createText(holder, opts.title, 17, "white")
	holder.title:SetPoint("TOPLEFT")
	if opts.description then
		holder.description = Primitives.createText(holder, opts.description, 11, "dim")
		holder.description:SetPoint("TOPLEFT", holder.title, "BOTTOMLEFT", 0, -5)
		holder.description:SetPoint("RIGHT", holder, "RIGHT")
		holder.description:SetJustifyH("LEFT")
		holder.description:SetWordWrap(true)
	end

	local line = Primitives.createTexture(holder, "ARTWORK", "borderDim")
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	local underline = Primitives.createTexture(holder, "OVERLAY", "accent")
	underline:SetSize(36, 2)
	underline:SetPoint("BOTTOMLEFT", 0, -0.5)
	return holder
end

-- Adds a nav entry (with an optional icon from textures/UI/) and returns its (empty) content
-- page, which sits below the page's title and description.
function Panel:AddTab(key, text, opts)
	opts = opts or {}
	local padding = Theme.LAYOUT.contentPadding
	local pageHeader = buildPageHeader(self.content, { title = text, description = opts.description })

	local page = CreateFrame("Frame", nil, self.content)
	page:SetPoint("TOPLEFT", padding, -(PAGE_HEADER_HEIGHT + padding))
	page:SetPoint("BOTTOMRIGHT", -padding, padding)
	page:Hide()

	local button = CreateFrame("Button", nil, self.sidebar)
	button:SetHeight(NAV_ROW_HEIGHT)
	button:SetPoint("TOPLEFT", NAV_INSET, self.cursorY)
	button:SetPoint("TOPRIGHT", -NAV_INSET, self.cursorY)
	self.cursorY = self.cursorY - NAV_ROW_HEIGHT - 2

	button.wash = button:CreateTexture(nil, "BACKGROUND")
	button.wash:SetAllPoints()
	button.bar = button:CreateTexture(nil, "ARTWORK")
	button.bar:SetWidth(2)
	button.bar:SetPoint("TOPLEFT")
	button.bar:SetPoint("BOTTOMLEFT")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(NAV_ICON_SIZE, NAV_ICON_SIZE)
	button.icon:SetPoint("LEFT", 10, 0)
	if opts.icon then
		button.icon:SetTexture("Interface\\AddOns\\PixlLootCouncil\\textures\\UI\\" .. opts.icon)
	end
	button.label = Primitives.createText(button, text, 12)
	button.label:SetPoint("LEFT", opts.icon and button.icon or button, opts.icon and "RIGHT" or "LEFT", opts.icon and 9 or 12, 0)

	paintTab(button, false, false)
	button:SetScript("OnEnter", function(b) paintTab(b, self.selected == key, true) end)
	button:SetScript("OnLeave", function(b) paintTab(b, self.selected == key, false) end)
	button:SetScript("OnClick", function() self:SelectTab(key) end)

	self.tabs[key] = { page = page, button = button, header = pageHeader }
	self.selected = self.selected or key
	return page
end

-- noFade: repaint only (accent change), without replaying the page fade.
function Panel:SelectTab(key, noFade)
	if not self.tabs[key] then
		return
	end
	local changed = self.selected ~= key
	self.selected = key
	for tabKey, tab in pairs(self.tabs) do
		local selected = tabKey == key
		paintTab(tab.button, selected, false)
		tab.header:SetShown(selected)
		if selected then
			if not noFade or changed then
				tab.page:SetAlpha(0)
				tab.page:Show()
				UIFrameFadeIn(tab.page, PAGE_FADE_SECONDS, 0, 1)
			end
		else
			tab.page:Hide()
		end
	end
end

function Panel:Show()
	self.frame:Show()
	if self.selected then
		self:SelectTab(self.selected)
	end
end
