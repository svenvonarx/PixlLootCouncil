local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

-- Ported from FojjiCore's root options frame construction (Options.lua, see
-- docs/analysis/fojjicore-ui-style.md) -- the full header-bar + sidebar-nav + content-panel +
-- page-switch machinery. Per docs/SPECIFICATION.md §4.3, this is only for multi-section windows
-- (Options, History); single-purpose windows (SessionFrame, VotingFrame, LootFrame) use just the
-- header-bar portion they already built directly, not this file.
local PanelLayout = {}
PLC.UI.Widgets.PanelLayout = PanelLayout

local Panel = {}
local PanelMeta = { __index = Panel }

-- opts: width, height, title, name (global frame name, for UISpecialFrames/Escape-to-close).
function PanelLayout.Create(opts)
	local frame = CreateFrame("Frame", opts.name, UIParent)
	frame:SetSize(opts.width or 760, opts.height or 540)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if opts.name then
		tinsert(UISpecialFrames, opts.name)
	end

	frame.bg = Primitives.createTexture(frame, "BACKGROUND", "frame")
	frame.bg:SetAllPoints()
	frame.border = Primitives.createBorder(frame)

	-- Header ---------------------------------------------------------------
	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()

	header.title = Primitives.createText(header, opts.title or "", 14, "title")
	header.title:SetPoint("LEFT", 10, 0)

	header.close = CreateFrame("Button", nil, header)
	header.close:SetSize(20, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close.bg = Primitives.createTexture(header.close, "BACKGROUND", "button")
	header.close.bg:SetAllPoints()
	header.close.label = Primitives.createText(header.close, "x", 14, "warning")
	header.close.label:SetPoint("CENTER")
	header.close:SetScript("OnClick", function()
		frame:Hide()
	end)

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	-- Sidebar + content, divided by a 1px vertical line ---------------------
	local sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetWidth(Theme.LAYOUT.sidebarWidth)
	sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	sidebar:SetPoint("BOTTOMLEFT")
	sidebar.bg = Primitives.createTexture(sidebar, "BACKGROUND", "sidebar")
	sidebar.bg:SetAllPoints()

	local divider = Primitives.createTexture(frame, "ARTWORK", "borderDim")
	divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
	divider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT")
	divider:SetWidth(1)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
	content:SetPoint("BOTTOMRIGHT")
	content.bg = Primitives.createTexture(content, "BACKGROUND", "content")
	content.bg:SetAllPoints()

	local self = setmetatable({
		frame = frame,
		header = header,
		sidebar = sidebar,
		content = content,
		pages = {},
		navButtons = {},
		sidebarCursorY = -10,
	}, PanelMeta)

	frame:Hide()
	return self
end

function Panel:AddSidebarHeader(text)
	local label = Primitives.createText(self.sidebar, text, 10, "dim")
	label:SetPoint("TOPLEFT", 12, self.sidebarCursorY)
	self.sidebarCursorY = self.sidebarCursorY - 20
end

-- Returns the content-area page frame this tab shows; caller fills it in.
function Panel:AddTab(key, text)
	local page = CreateFrame("Frame", nil, self.content)
	page:SetPoint("TOPLEFT", Theme.LAYOUT.contentPadding, -Theme.LAYOUT.contentPadding)
	page:SetPoint("BOTTOMRIGHT", -Theme.LAYOUT.contentPadding, Theme.LAYOUT.contentPadding)
	page:Hide()
	self.pages[key] = page

	local button = CreateFrame("Button", nil, self.sidebar)
	button:SetSize(self.sidebar:GetWidth() - 16, 26)
	button:SetPoint("TOPLEFT", 8, self.sidebarCursorY)
	self.sidebarCursorY = self.sidebarCursorY - 28

	button.indicator = Primitives.createTexture(button, "ARTWORK", "accent")
	button.indicator:SetWidth(3)
	button.indicator:SetPoint("TOPLEFT")
	button.indicator:SetPoint("BOTTOMLEFT")
	button.indicator:Hide()

	button.glow = Primitives.createTexture(button, "BACKGROUND", "accent", 0.10)
	button.glow:SetAllPoints()
	button.glow:Hide()

	button.label = Primitives.createText(button, text, 12, "dim")
	button.label:SetPoint("LEFT", 10, 0)

	button:SetScript("OnEnter", function(self)
		if not self.active then
			self.glow:SetColorTexture(1, 1, 1, 0.025)
			self.glow:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		if not self.active then
			self.glow:Hide()
		end
	end)
	button:SetScript("OnClick", function()
		self:SelectTab(key)
	end)

	self.navButtons[key] = button
	if not self.activeKey then
		self.activeKey = key
	end
	return page
end

-- 0.12s alpha fade-in, matching FojjiCore's fadePage (Options.lua:715-719).
local function fadeIn(frame)
	frame:SetAlpha(0)
	frame:Show()
	UIFrameFadeIn(frame, 0.12, 0, 1)
end

function Panel:SelectTab(key)
	if not self.pages[key] then
		return
	end
	self.activeKey = key
	for navKey, button in pairs(self.navButtons) do
		local active = navKey == key
		button.active = active
		button.indicator:SetShown(active)
		button.glow:SetShown(active)
		if active then
			local r, g, b = Primitives.color("accent", 0.10)
			button.glow:SetColorTexture(r, g, b)
			local wr, wg, wb = Primitives.color("white")
			button.label:SetTextColor(wr, wg, wb)
		else
			local r, g, b = Primitives.color("dim")
			button.label:SetTextColor(r, g, b)
		end
	end
	for pageKey, page in pairs(self.pages) do
		if pageKey == key then
			fadeIn(page)
		else
			page:Hide()
		end
	end
end

function Panel:Show()
	self.frame:Show()
	if self.activeKey then
		self:SelectTab(self.activeKey)
	end
end
