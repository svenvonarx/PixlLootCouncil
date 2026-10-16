local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

-- A settings-style window: title bar, a navigation column on the left (section titles and
-- tabs), and a content area showing one page at a time. Used by the Options window.
--   local panel = PanelLayout.Create({ name = "GlobalName", title = "...", width = , height = })
--   panel:AddSidebarHeader("SECTION")
--   local page = panel:AddTab("key", "Tab name")   -- fill `page` with widgets
--   panel:Show()
local PanelLayout = {}
PLC.UI.Widgets.PanelLayout = PanelLayout

local Panel = {}
Panel.__index = Panel

local NAV_ROW_HEIGHT = 26
local NAV_ROW_STEP = 28
local NAV_HEADER_STEP = 20
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
	nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
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
	return setmetatable({
		frame = frame,
		header = header,
		sidebar = nav,
		content = content,
		tabs = {}, -- [key] = { page, button }
		cursorY = -10, -- next free y in the nav column
	}, Panel)
end

function Panel:AddSidebarHeader(text)
	local label = Primitives.createText(self.sidebar, text, 10, "dim")
	label:SetPoint("TOPLEFT", 12, self.cursorY)
	self.cursorY = self.cursorY - NAV_HEADER_STEP
end

local function paintTab(button, selected, hovered)
	button.indicator:SetShown(selected)
	if selected then
		local r, g, b = Primitives.color("accent")
		button.glow:SetColorTexture(r, g, b, 0.10)
		button.glow:Show()
		button.label:SetTextColor(Primitives.color("white"))
	else
		button.glow:SetColorTexture(1, 1, 1, 0.025)
		button.glow:SetShown(hovered)
		button.label:SetTextColor(Primitives.color("dim"))
	end
end

-- Adds a nav entry and returns its (empty) content page.
function Panel:AddTab(key, text)
	local padding = Theme.LAYOUT.contentPadding
	local page = CreateFrame("Frame", nil, self.content)
	page:SetPoint("TOPLEFT", padding, -padding)
	page:SetPoint("BOTTOMRIGHT", -padding, padding)
	page:Hide()

	local button = CreateFrame("Button", nil, self.sidebar)
	button:SetSize(self.sidebar:GetWidth() - 16, NAV_ROW_HEIGHT)
	button:SetPoint("TOPLEFT", 8, self.cursorY)
	self.cursorY = self.cursorY - NAV_ROW_STEP

	button.glow = button:CreateTexture(nil, "BACKGROUND")
	button.glow:SetAllPoints()
	button.indicator = Primitives.createTexture(button, "ARTWORK", "accent")
	button.indicator:SetWidth(3)
	button.indicator:SetPoint("TOPLEFT")
	button.indicator:SetPoint("BOTTOMLEFT")
	button.label = Primitives.createText(button, text, 12, "dim")
	button.label:SetPoint("LEFT", 10, 0)
	paintTab(button, false, false)

	button:SetScript("OnEnter", function(b) paintTab(b, self.selected == key, true) end)
	button:SetScript("OnLeave", function(b) paintTab(b, self.selected == key, false) end)
	button:SetScript("OnClick", function() self:SelectTab(key) end)

	self.tabs[key] = { page = page, button = button }
	self.selected = self.selected or key
	return page
end

function Panel:SelectTab(key)
	if not self.tabs[key] then
		return
	end
	self.selected = key
	for tabKey, tab in pairs(self.tabs) do
		local selected = tabKey == key
		paintTab(tab.button, selected, false)
		if selected then
			tab.page:SetAlpha(0)
			tab.page:Show()
			UIFrameFadeIn(tab.page, PAGE_FADE_SECONDS, 0, 1)
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
