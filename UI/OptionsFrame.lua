local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local CheckboxWidget = PLC.UI.Widgets.Checkbox
local ButtonWidget = PLC.UI.Widgets.Button
local SliderWidget = PLC.UI.Widgets.Slider
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
	y = y - 30

	local mirrorRC = CheckboxWidget.createCheckbox(page, L["OPTIONS_MIRROR_RC"], function(checked)
		profile.historyMirrorRC = checked
	end)
	mirrorRC:SetPoint("TOPLEFT", 0, y)
	mirrorRC:SetChecked(profile.historyMirrorRC)
	y = y - 30

	local autoStart = CheckboxWidget.createCheckbox(page, L["OPTIONS_AUTO_START"], function(checked)
		profile.autoStartSession = checked
	end)
	autoStart:SetPoint("TOPLEFT", 0, y)
	autoStart:SetChecked(profile.autoStartSession)
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

-- Who's on the loot council (Data/CouncilRules.lua:Evaluate). The master looter is always on it
-- and runs the session; these settings add members. While a session runs, the HOLDER's settings
-- decide the council for everyone. Any change rebuilds the roster, which re-broadcasts the council
-- if this client is holding a session (Session:OnRosterRebuilt).
local MAX_RANKS = 10
local NAME_ROW_HEIGHT = 20

local function councilChanged()
	PLC.Roster:Rebuild()
end

local function buildCouncilPage(page)
	local council = PLC.db.profile.council

	local raidAssist = CheckboxWidget.createCheckbox(page, L["OPTIONS_COUNCIL_RAIDASSIST"], function(checked)
		council.raidAssist = checked
		councilChanged()
	end)
	raidAssist:SetPoint("TOPLEFT", 0, 0)
	raidAssist:SetChecked(council.raidAssist)

	-- Guild ranks: one checkbox per rank, two columns, rebuilt whenever the page is shown (rank
	-- names load lazily, and can change).
	local ranksLabel = Primitives.createText(page, L["OPTIONS_COUNCIL_GUILD_RANKS"], 13, "white")
	ranksLabel:SetPoint("TOPLEFT", 0, -38)
	local noGuild = Primitives.createText(page, L["OPTIONS_COUNCIL_NO_GUILD"], 11, "dim")
	noGuild:SetPoint("TOPLEFT", ranksLabel, "BOTTOMLEFT", 0, -8)

	local rankBoxes = {}
	for i = 1, MAX_RANKS do
		local box = CheckboxWidget.createCheckbox(page, "", function(checked)
			council.guildRanks[rankBoxes[i].rankIndex] = checked or nil
			councilChanged()
		end)
		box:SetWidth(180)
		local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
		box:SetPoint("TOPLEFT", ranksLabel, "BOTTOMLEFT", column * 190, -8 - row * 24)
		box:Hide()
		rankBoxes[i] = box
	end

	-- Manual names.
	local namesTop = -38 - 18 - 8 - math.ceil(MAX_RANKS / 2) * 24 - 12
	local namesLabel = Primitives.createText(page, L["OPTIONS_COUNCIL_NAMES"], 13, "white")
	namesLabel:SetPoint("TOPLEFT", 0, namesTop)

	local nameBox = Primitives.createEditBox(page, 200, 24, L["OPTIONS_COUNCIL_NAME_PLACEHOLDER"])
	nameBox:SetPoint("TOPLEFT", namesLabel, "BOTTOMLEFT", 0, -8)
	local addButton = ButtonWidget.createButton(page, L["OPTIONS_COUNCIL_ADD"], 70)
	addButton:SetHeight(24)
	addButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)

	local listHolder = CreateFrame("Frame", nil, page)
	listHolder:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -8)
	listHolder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
	listHolder.border = Primitives.createBorder(listHolder, "borderDim")
	local nameTable = PLC.UI.Widgets.DataTable.Create(listHolder, NAME_ROW_HEIGHT)

	local refreshNames
	nameTable:SetColumns({
		{
			width = 220,
			render = function(rowData)
				return "  " .. rowData.name
			end,
		},
		{
			width = 24,
			isWidget = true,
			create = function(row)
				return Primitives.createCloseButton(row, 14)
			end,
			update = function(button, rowData)
				button:SetScript("OnClick", function()
					council.manualList[rowData.name] = nil
					refreshNames()
					councilChanged()
				end)
			end,
		},
	})

	function refreshNames()
		local rows = {}
		for name in pairs(council.manualList) do
			table.insert(rows, { name = name })
		end
		table.sort(rows, function(a, b) return a.name < b.name end)
		nameTable:SetRows(rows)
	end

	local function addName()
		local name = strtrim(nameBox:GetValue() or "")
		if name == "" then
			return
		end
		-- Character names are stored capitalized, like the game shows them.
		name = name:sub(1, 1):upper() .. name:sub(2)
		council.manualList[name] = true
		nameBox:SetText("")
		nameBox:ClearFocus()
		refreshNames()
		councilChanged()
	end
	addButton:SetScript("OnClick", addName)
	nameBox:SetScript("OnEnterPressed", addName)

	local function refreshRanks()
		local ranks = PLC.CouncilRules:GetGuildRanks()
		noGuild:SetShown(#ranks == 0)
		for i, box in ipairs(rankBoxes) do
			local rank = ranks[i]
			if rank then
				box.rankIndex = rank.index
				box.label:SetText(rank.name)
				box:SetChecked(council.guildRanks[rank.index])
				box:Show()
			else
				box:Hide()
			end
		end
	end

	page:HookScript("OnShow", function()
		raidAssist:SetChecked(council.raidAssist)
		refreshRanks()
		refreshNames()
	end)
	refreshRanks()
	refreshNames()
end

local DEFAULT_ACCENT = { r = 0.91, g = 0.64, b = 0.24 }

local function buildAppearancePage(page)
	local profile = PLC.db.profile

	local label = Primitives.createText(page, L["OPTIONS_ACCENT_COLOR"], 13, "white")
	label:SetPoint("TOPLEFT")

	local swatch = CreateFrame("Button", nil, page)
	swatch:SetSize(28, 28)
	swatch:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)
	-- A plain texture, not a themed fill: it shows the chosen accent value itself.
	swatch.tex = swatch:CreateTexture(nil, "ARTWORK")
	swatch.tex:SetPoint("TOPLEFT", 1, -1)
	swatch.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	swatch.border = Primitives.createBorder(swatch)

	-- Saves the accent to the profile and recolors the whole UI.
	local function setAccent(r, g, b)
		profile.accent = { r = r, g = g, b = b }
		swatch.tex:SetColorTexture(r, g, b)
		Theme:ApplyFromAccent(r, g, b)
	end
	swatch.tex:SetColorTexture(profile.accent.r, profile.accent.g, profile.accent.b)

	local hint = Primitives.createText(page, L["OPTIONS_ACCENT_HINT"], 11, "dim")
	hint:SetPoint("LEFT", swatch, "RIGHT", 12, 0)

	-- The game's color picker. Current clients set it up through SetupColorPickerAndShow (the old
	-- ColorPickerFrame.func fields are ignored there, so picks never reached the addon); older ones
	-- still use the fields. Live preview while picking, restored on Cancel.
	swatch:SetScript("OnClick", function()
		local before = { r = profile.accent.r, g = profile.accent.g, b = profile.accent.b }
		local function onPick()
			setAccent(ColorPickerFrame:GetColorRGB())
		end
		local function onCancel()
			setAccent(before.r, before.g, before.b)
		end
		if ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:SetupColorPickerAndShow({
				r = before.r, g = before.g, b = before.b,
				hasOpacity = false,
				swatchFunc = onPick,
				cancelFunc = onCancel,
			})
		else
			ColorPickerFrame.hasOpacity = false
			ColorPickerFrame.func = onPick
			ColorPickerFrame.cancelFunc = onCancel
			ColorPickerFrame:SetColorRGB(before.r, before.g, before.b)
			ShowUIPanel(ColorPickerFrame)
		end
	end)
	swatch:SetScript("OnEnter", function(self)
		Primitives.setBorderColor(self.border, "accent", 0.85)
	end)
	swatch:SetScript("OnLeave", function(self)
		Primitives.setBorderColor(self.border, "border")
	end)

	local reset = ButtonWidget.createButton(page, L["OPTIONS_ACCENT_RESET"], 130)
	reset:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", 0, -14)
	reset:SetScript("OnClick", function()
		setAccent(DEFAULT_ACCENT.r, DEFAULT_ACCENT.g, DEFAULT_ACCENT.b)
	end)
end

local function ensurePanel()
	if panel then
		return panel
	end

	panel = PanelLayout.Create({
		name = "PixlLootCouncilOptionsFrame",
		width = 560,
		height = 590, -- General stacks 4 checkboxes + 4 sliders under the page header
		title = L["OPTIONS_TITLE"],
	})

	panel:AddSidebarHeader(L["OPTIONS_SECTION_COUNCIL"])
	buildGeneralPage(panel:AddTab("general", L["OPTIONS_TAB_GENERAL"],
		{ icon = "nav_general.png", description = L["OPTIONS_DESC_GENERAL"] }))
	buildResponsesPage(panel:AddTab("responses", L["OPTIONS_TAB_RESPONSES"],
		{ icon = "nav_responses.png", description = L["OPTIONS_DESC_RESPONSES"] }))
	buildCouncilPage(panel:AddTab("council", L["OPTIONS_TAB_COUNCIL"],
		{ icon = "nav_council.png", description = L["OPTIONS_COUNCIL_INTRO"] }))

	panel:AddSidebarHeader(L["OPTIONS_SECTION_SETTINGS"])
	buildAppearancePage(panel:AddTab("appearance", L["OPTIONS_TAB_APPEARANCE"],
		{ icon = "nav_appearance.png", description = L["OPTIONS_DESC_APPEARANCE"] }))

	return panel
end

function OptionsFrame:Open()
	ensurePanel():Show()
end

PLC:RegisterSlashCommand("options", "Open the options window", function()
	OptionsFrame:Open()
end)
