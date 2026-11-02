local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local CheckboxWidget = PLC.UI.Widgets.Checkbox
local SliderWidget = PLC.UI.Widgets.Slider
local Theme = PLC.UI.Theme

-- The welcome window: shown once, the first time the addon loads on an account, and again from
-- Options -> About or /plc setup. Raider or loot master; a loot master then imports from
-- RCLootCouncil or picks the essentials. Closing it any way counts as done, so it never nags.
local WelcomeFrame = {}
PLC.UI.WelcomeFrame = WelcomeFrame

local WIDTH, HEIGHT = 600, 440
local CARD_WIDTH, CARD_HEIGHT = 250, 190
local CARD_GAP = 20
local ICON_SIZE = 64
local FIRST_SHOW_DELAY = 4 -- seconds after login, past the loading screen's wall of chat

local frame
local steps = {} -- [name] = page frame
local current
local waitingForCombat = false

local function finish()
	PLC.db.global.onboarded = true
	if frame then
		frame:Hide()
	end
end

-- A big clickable choice: an icon, a title and a line of explanation.
local function createCard(parent, icon, title, text, onClick)
	local card = CreateFrame("Button", nil, parent)
	card:SetSize(CARD_WIDTH, CARD_HEIGHT)
	card.bg = Primitives.createTexture(card, "BACKGROUND", "button")
	card.bg:SetAllPoints()
	card.border = Primitives.createBorder(card)

	card.icon = Primitives.createArtwork(card, icon, "ARTWORK", true)
	card.icon:SetSize(ICON_SIZE, ICON_SIZE)
	card.icon:SetPoint("TOP", 0, -28)
	card.title = Primitives.createText(card, title, 18, "white")
	card.title:SetPoint("TOP", card.icon, "BOTTOM", 0, -16)
	card.text = Primitives.createText(card, text, 12, "dim")
	card.text:SetPoint("TOP", card.title, "BOTTOM", 0, -8)
	card.text:SetWidth(CARD_WIDTH - 36)
	card.text:SetWordWrap(true)
	card.text:SetJustifyH("CENTER")

	card:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(Primitives.color("buttonHover"))
		Primitives.setBorderColor(self.border, "accent", 0.85)
	end)
	card:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(Primitives.color("button"))
		Primitives.setBorderColor(self.border, "border")
	end)
	card:SetScript("OnClick", onClick)
	return card
end

-- A page with its heading and a line under it.
local function createStep(name, title, hint)
	local page = CreateFrame("Frame", nil, frame.body)
	page:SetAllPoints()
	page:Hide()
	page.title = Primitives.createText(page, title, 22, "title")
	page.title:SetPoint("TOP", 0, -26)
	page.hint = Primitives.createText(page, hint or "", 12, "dim")
	page.hint:SetPoint("TOP", page.title, "BOTTOM", 0, -8)
	page.hint:SetWidth(WIDTH - 80)
	page.hint:SetWordWrap(true)
	page.hint:SetJustifyH("CENTER")
	steps[name] = page
	return page
end

local function placePair(left, right, page)
	left:SetPoint("TOPRIGHT", page, "TOP", -CARD_GAP / 2, -96)
	right:SetPoint("TOPLEFT", page, "TOP", CARD_GAP / 2, -96)
end

local function backButton(page, target)
	local button = ButtonWidget.createButton(page, L["WELCOME_BACK"], 100)
	button:SetPoint("BOTTOMLEFT", 24, 22)
	button:SetScript("OnClick", function()
		WelcomeFrame:ShowStep(target)
	end)
	return button
end

local function showDone(lines)
	local page = steps.done
	page.summary:SetText(table.concat(lines, "\n"))
	WelcomeFrame:ShowStep("done")
end

-- What came over from RCLootCouncil, one line each.
local function importLines(summary)
	local lines = {}
	if summary.history then
		lines[#lines + 1] = string.format(L["WELCOME_IMPORTED_HISTORY"], summary.history)
	end
	if summary.council then
		lines[#lines + 1] = string.format(L["WELCOME_IMPORTED_COUNCIL"], summary.council)
	end
	if summary.ranks then
		lines[#lines + 1] = string.format(L["WELCOME_IMPORTED_RANKS"], summary.ranks)
	end
	if summary.buttons then
		lines[#lines + 1] = string.format(L["WELCOME_IMPORTED_BUTTONS"], summary.buttons)
	end
	if summary.timeout then
		lines[#lines + 1] = string.format(L["WELCOME_IMPORTED_TIMEOUT"], summary.timeout)
	end
	if summary.announce or summary.autoStart then
		lines[#lines + 1] = L["WELCOME_IMPORTED_CHAT"]
	end
	if #lines == 0 or (#lines == 1 and summary.history) then
		lines[#lines + 1] = L["WELCOME_IMPORTED_NOTHING"]
	end
	if summary.unknown then
		lines[#lines + 1] = string.format(L["WELCOME_IMPORTED_UNKNOWN"], summary.unknown)
	end
	for i, line in ipairs(lines) do
		lines[i] = "•  " .. line
	end
	return lines
end

local function buildRoleStep()
	local page = createStep("role", L["WELCOME_ROLE_TITLE"], L["WELCOME_ROLE_HINT"])
	local raider = createCard(page, "welcome_raider.png", L["WELCOME_RAIDER"], L["WELCOME_RAIDER_TEXT"], function()
		print(L["CHAT_PREFIX"] .. L["WELCOME_RAIDER_DONE"])
		finish()
	end)
	local master = createCard(page, "welcome_lootmaster.png", L["WELCOME_LOOTMASTER"], L["WELCOME_LOOTMASTER_TEXT"], function()
		WelcomeFrame:ShowStep(PLC.RCImport:IsAvailable() and "rc" or "setup")
	end)
	placePair(raider, master, page)
	page.raider, page.master = raider, master
end

local function buildRCStep()
	local page = createStep("rc", L["WELCOME_RC_TITLE"], L["WELCOME_RC_HINT"])
	local import = createCard(page, "welcome_import.png", L["WELCOME_IMPORT"], L["WELCOME_IMPORT_TEXT"], function()
		showDone(importLines(PLC.RCImport:Import()))
	end)
	local setup = createCard(page, "welcome_setup.png", L["WELCOME_SETUP"], L["WELCOME_SETUP_TEXT"], function()
		WelcomeFrame:ShowStep("setup")
	end)
	placePair(import, setup, page)
	page.import, page.setup = import, setup
	backButton(page, "role")
end

-- The few settings a loot master should decide on day one. Each writes straight to the profile,
-- like Options does: whichever profile is current when it's used, as the page outlives a switch.
local function buildSetupStep()
	local page = createStep("setup", L["WELCOME_SETUP_TITLE"], L["WELCOME_SETUP_HINT"])
	local function profile()
		return PLC.db.profile
	end
	local y = -100
	local left = 80

	local function checkbox(text, get, set)
		local box = CheckboxWidget.createCheckbox(page, text, set)
		box:SetPoint("TOPLEFT", left, y)
		box:HookScript("OnShow", function(self) self:SetChecked(get()) end)
		box:SetChecked(get())
		y = y - 34
		return box
	end
	page.autoLoot = checkbox(L["WELCOME_OPT_AUTOLOOT"], function() return profile().autoLoot.enabled end,
		function(checked) profile().autoLoot.enabled = checked end)
	page.council = checkbox(L["WELCOME_OPT_COUNCIL"], function() return profile().council.raidAssist end,
		function(checked) profile().council.raidAssist = checked end)
	page.announce = checkbox(L["WELCOME_OPT_ANNOUNCE"],
		function() return profile().announce.sessionStart and profile().announce.award end,
		function(checked) profile().announce.sessionStart, profile().announce.award = checked, checked end)

	local slider = SliderWidget.createSlider(page, L["OPTIONS_RESPONSE_TIMEOUT"], 15, 300, 5, function(value)
		return string.format(L["OPTIONS_SECONDS"], value)
	end)
	slider.container:SetPoint("TOPLEFT", left, y - 10)
	slider.container:SetPoint("TOPRIGHT", -left, y - 10)
	slider:SetScript("OnValueChanged", function(self, value)
		profile().responseTimeoutSeconds = value
		self:ShowValue(value)
	end)
	page:HookScript("OnShow", function()
		slider:SetValue(profile().responseTimeoutSeconds)
		slider:ShowValue(profile().responseTimeoutSeconds)
	end)
	page.slider = slider

	-- RCLootCouncil is there but not enabled on this character, so there's nothing to read.
	page.rcNote = Primitives.createText(page, L["WELCOME_RC_DISABLED"], 11, "dim")
	page.rcNote:SetPoint("BOTTOMLEFT", 24, 64)
	page.rcNote:SetPoint("BOTTOMRIGHT", -24, 64)
	page.rcNote:SetJustifyH("LEFT")
	page.rcNote:SetWordWrap(true)
	page:HookScript("OnShow", function()
		page.rcNote:SetShown(PLC.RCImport:IsInstalled() and not PLC.RCImport:IsAvailable())
	end)

	page.back = backButton(page, "role")
	page:HookScript("OnShow", function()
		-- Back to where this page was reached from.
		page.back:SetScript("OnClick", function()
			WelcomeFrame:ShowStep(PLC.RCImport:IsAvailable() and "rc" or "role")
		end)
	end)
	local done = ButtonWidget.createButton(page, L["WELCOME_FINISH"], 140)
	done:SetPoint("BOTTOMRIGHT", -24, 22)
	done:SetScript("OnClick", function()
		showDone({ "•  " .. L["WELCOME_SETUP_SAVED"] })
	end)
	page.finish = done
end

local function buildDoneStep()
	local page = createStep("done", L["WELCOME_DONE_TITLE"], L["WELCOME_DONE_TIP"])
	page.summary = Primitives.createText(page, "", 13, "text")
	page.summary:SetPoint("TOPLEFT", 80, -110)
	page.summary:SetPoint("TOPRIGHT", -80, -110)
	page.summary:SetJustifyH("LEFT")
	page.summary:SetWordWrap(true)
	page.summary:SetSpacing(6)

	local options = ButtonWidget.createButton(page, L["WELCOME_OPEN_OPTIONS"], 160)
	options:SetPoint("BOTTOMLEFT", 24, 22)
	options:SetScript("OnClick", function()
		finish()
		PLC.UI.OptionsFrame:Open()
	end)
	local done = ButtonWidget.createButton(page, L["WELCOME_DONE"], 140)
	done:SetPoint("BOTTOMRIGHT", -24, 22)
	done:SetScript("OnClick", finish)
	page.options, page.done = options, done
end

local function ensureFrame()
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", "PixlLootCouncilWelcome", UIParent)
	Primitives.refreshFontsOnShow(frame)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", 0, 40)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilWelcome")
	Primitives.createTexture(frame, "BACKGROUND", "frame"):SetAllPoints()
	Primitives.createBorder(frame)

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	Primitives.createTexture(header, "BACKGROUND", "header"):SetAllPoints()
	header.logo = Primitives.createLogo(header, 20)
	header.logo:SetPoint("LEFT", 14, 0)
	header.title = Primitives.createText(header, L["WELCOME_TITLE"], 18, "title")
	header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, -2)
	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", finish)
	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)
	frame.header = header

	frame.body = CreateFrame("Frame", nil, frame)
	frame.body:SetPoint("TOPLEFT", 1, -Theme.LAYOUT.headerHeight - 1)
	frame.body:SetPoint("BOTTOMRIGHT", -1, 1)
	Primitives.createTexture(frame.body, "BACKGROUND", "content"):SetAllPoints()

	buildRoleStep()
	buildRCStep()
	buildSetupStep()
	buildDoneStep()
	-- Hidden first: a new frame starts shown, and hiding it now must not count as having seen it.
	frame:Hide()
	-- Escape, the close button, or finishing: any of them means it's been seen.
	frame:SetScript("OnHide", function()
		PLC.db.global.onboarded = true
	end)
	return frame
end

function WelcomeFrame:ShowStep(name)
	ensureFrame()
	for stepName, page in pairs(steps) do
		page:SetShown(stepName == name)
	end
	current = name
end

function WelcomeFrame:CurrentStep()
	return current
end

function WelcomeFrame:Open()
	ensureFrame()
	self:ShowStep("role")
	frame:Show()
end

function WelcomeFrame:IsShown()
	return frame ~= nil and frame:IsShown()
end

local function showFirstTime()
	if PLC.db.global.onboarded or WelcomeFrame:IsShown() then
		return
	end
	if InCombatLockdown() then
		waitingForCombat = true
		return
	end
	WelcomeFrame:Open()
end

PLC.Events:RegisterHandler("PLAYER_REGEN_ENABLED", function()
	if waitingForCombat then
		waitingForCombat = false
		showFirstTime()
	end
end)

PLC:RegisterOnEnable(function()
	if not PLC.db.global.onboarded then
		PLC:ScheduleTimer(showFirstTime, FIRST_SHOW_DELAY)
	end
end)

PLC:RegisterSlashCommand("setup", L["SLASH_SETUP"], function()
	WelcomeFrame:Open()
end)

-- Everything this addon has saved, on every character, with a warning first. Then a reload, so
-- nothing still running holds on to the old data, and the welcome window comes back.
StaticPopupDialogs["PIXLLOOTCOUNCIL_RESET"] = {
	text = L["RESET_CONFIRM_TEXT"],
	button1 = L["RESET_CONFIRM_BUTTON"],
	button2 = CANCEL,
	OnAccept = function()
		PLC.db:ResetDB()
		PLC.lootDB:ResetDB()
		ReloadUI()
	end,
	showAlert = true,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function WelcomeFrame:ConfirmReset()
	StaticPopup_Show("PIXLLOOTCOUNCIL_RESET")
end

PLC:RegisterSlashCommand("reset", L["SLASH_RESET"], function()
	WelcomeFrame:ConfirmReset()
end)
