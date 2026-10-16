local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local CheckboxWidget = PLC.UI.Widgets.Checkbox
local SliderWidget = PLC.UI.Widgets.Slider
local DropdownWidget = PLC.UI.Widgets.Dropdown
local PanelLayout = PLC.UI.Widgets.PanelLayout
local Theme = PLC.UI.Theme

-- General / Responses / Council / Appearance sidebar categories (spec §4.3), reading/writing
-- db.profile.* live -- no /reload needed to see a change take effect (AceDB itself handles
-- writing the change through to disk on logout).
local OptionsFrame = {}
PLC.UI.OptionsFrame = OptionsFrame

local panel

local function buildGeneralPage(page)
	local profile = PLC.db.profile
	local y = 0

	local announceStart = CheckboxWidget.createCheckbox(page, L["OPTIONS_ANNOUNCE_START"], function(checked)
		profile.announce.sessionStart = checked
	end)
	announceStart:SetPoint("TOPLEFT", 0, y)
	announceStart:SetChecked(profile.announce.sessionStart)
	y = y - 30

	local announceAward = CheckboxWidget.createCheckbox(page, L["OPTIONS_ANNOUNCE_AWARD"], function(checked)
		profile.announce.award = checked
	end)
	announceAward:SetPoint("TOPLEFT", 0, y)
	announceAward:SetChecked(profile.announce.award)
	y = y - 50

	local threshold = SliderWidget.createSlider(page, L["OPTIONS_LOOT_THRESHOLD"], 0, 5, 1)
	threshold.container:SetPoint("TOPLEFT", 0, y)
	threshold:SetValue(profile.lootThreshold)
	threshold.valueText:SetText(tostring(profile.lootThreshold))
	threshold:SetScript("OnValueChanged", function(_, value)
		profile.lootThreshold = value
		threshold.valueText:SetText(tostring(value))
	end)
	y = y - 70

	local heartbeat = SliderWidget.createSlider(page, L["OPTIONS_HEARTBEAT_SECONDS"], 15, 180, 5)
	heartbeat.container:SetPoint("TOPLEFT", 0, y)
	heartbeat:SetValue(profile.sessionHeartbeatSeconds)
	heartbeat.valueText:SetText(tostring(profile.sessionHeartbeatSeconds))
	heartbeat:SetScript("OnValueChanged", function(_, value)
		profile.sessionHeartbeatSeconds = value
		heartbeat.valueText:SetText(tostring(value))
	end)
	y = y - 70

	local forceEnd = SliderWidget.createSlider(page, L["OPTIONS_FORCE_END_MINUTES"], 1, 30, 1)
	forceEnd.container:SetPoint("TOPLEFT", 0, y)
	forceEnd:SetValue(profile.sessionForceEndMinutes)
	forceEnd.valueText:SetText(tostring(profile.sessionForceEndMinutes))
	forceEnd:SetScript("OnValueChanged", function(_, value)
		profile.sessionForceEndMinutes = value
		forceEnd.valueText:SetText(tostring(value))
	end)
	y = y - 70

	-- The holder's value at session start wins for every candidate -- see
	-- Data/Session.lua:Start()/OnSessionStartReceived -- so changing this only affects sessions
	-- this character goes on to hold, never a session already in progress.
	local responseTimeout = SliderWidget.createSlider(page, L["OPTIONS_RESPONSE_TIMEOUT"], 15, 300, 5)
	responseTimeout.container:SetPoint("TOPLEFT", 0, y)
	responseTimeout:SetValue(profile.responseTimeoutSeconds)
	responseTimeout.valueText:SetText(tostring(profile.responseTimeoutSeconds))
	responseTimeout:SetScript("OnValueChanged", function(_, value)
		profile.responseTimeoutSeconds = value
		responseTimeout.valueText:SetText(tostring(value))
	end)
end

-- Read-only: full response customization (add/remove/reorder custom response sets) is Phase 3
-- scope (spec §7) -- this just surfaces what's currently configured.
local function buildResponsesPage(page)
	local y = 0
	for _, resp in ipairs(PLC.db.profile.responses) do
		-- Not Primitives.createTexture -- these colors come from per-response data, not a named
		-- theme token, and createTexture's registration would reset them to "text" gray on the
		-- next Theme:Refresh().
		local swatch = page:CreateTexture(nil, "ARTWORK")
		swatch:SetColorTexture(resp.color.r, resp.color.g, resp.color.b)
		swatch:SetSize(14, 14)
		swatch:SetPoint("TOPLEFT", 0, y)

		local label = Primitives.createText(page, resp.text, 12)
		label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
		y = y - 24
	end
end

local COUNCIL_MODES = { "raidAssist", "manual", "mlOnly" }

local function buildCouncilPage(page)
	local profile = PLC.db.profile

	local label = Primitives.createText(page, L["OPTIONS_COUNCIL_MODE"], 13, "white")
	label:SetPoint("TOPLEFT")

	local dropdown = DropdownWidget.createDropdownButton(page)
	dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)

	local function refreshDropdown()
		local entries = {}
		for _, mode in ipairs(COUNCIL_MODES) do
			table.insert(entries, {
				text = L["OPTIONS_COUNCIL_MODE_" .. mode:upper()] or mode,
				selected = profile.council.mode == mode,
				onClick = function()
					profile.council.mode = mode
					refreshDropdown()
				end,
			})
		end
		DropdownWidget.setEntries(dropdown, L["OPTIONS_COUNCIL_MODE_" .. profile.council.mode:upper()] or profile.council.mode, entries)
	end
	refreshDropdown()

	local hint = Primitives.createText(page, L["OPTIONS_COUNCIL_MODE_HINT"], 10, "dim")
	hint:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -10)
	hint:SetWidth(300)
	hint:SetJustifyH("LEFT")
end

local function buildAppearancePage(page)
	local profile = PLC.db.profile

	local label = Primitives.createText(page, L["OPTIONS_ACCENT_COLOR"], 13, "white")
	label:SetPoint("TOPLEFT")

	local swatch = CreateFrame("Button", nil, page)
	swatch:SetSize(28, 28)
	swatch:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)
	-- Not Primitives.createTexture -- same reason as the response swatches above: this color is
	-- the live-edited accent value itself, not a named theme token to re-skin from COLORS.
	swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
	swatch.tex:SetAllPoints()
	swatch.tex:SetColorTexture(profile.accent.r, profile.accent.g, profile.accent.b)
	swatch.border = Primitives.createBorder(swatch)

	swatch:SetScript("OnClick", function()
		local accent = profile.accent
		local function apply()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			accent.r, accent.g, accent.b = r, g, b
			Theme:ApplyFromAccent(r, g, b)
			swatch.tex:SetColorTexture(r, g, b)
		end
		ColorPickerFrame.func = apply
		ColorPickerFrame.cancelFunc = function()
			Theme:ApplyFromAccent(accent.r, accent.g, accent.b)
			swatch.tex:SetColorTexture(accent.r, accent.g, accent.b)
		end
		ColorPickerFrame.hasOpacity = false
		if ColorPickerFrame.SetColorRGB then
			ColorPickerFrame:SetColorRGB(accent.r, accent.g, accent.b)
		end
		ShowUIPanel(ColorPickerFrame)
	end)
end

local function ensurePanel()
	if panel then
		return panel
	end

	panel = PanelLayout.Create({
		name = "PixlLootCouncilOptionsFrame",
		width = 560,
		height = 460, -- General now stacks 2 checkboxes + 4 sliders; give it room
		title = L["OPTIONS_TITLE"],
	})

	panel:AddSidebarHeader(L["OPTIONS_SECTION_RAID"])
	buildGeneralPage(panel:AddTab("general", L["OPTIONS_TAB_GENERAL"]))
	buildResponsesPage(panel:AddTab("responses", L["OPTIONS_TAB_RESPONSES"]))
	buildCouncilPage(panel:AddTab("council", L["OPTIONS_TAB_COUNCIL"]))

	panel:AddSidebarHeader(L["OPTIONS_SECTION_SETTINGS"])
	buildAppearancePage(panel:AddTab("appearance", L["OPTIONS_TAB_APPEARANCE"]))

	return panel
end

PLC:RegisterSlashCommand("options", "Open the PixlLootCouncil options window", function()
	ensurePanel():Show()
end)
