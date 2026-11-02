local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local CheckboxWidget = PLC.UI.Widgets.Checkbox
local ButtonWidget = PLC.UI.Widgets.Button
local DropdownWidget = PLC.UI.Widgets.Dropdown
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

	local rcBridge = CheckboxWidget.createCheckbox(page, L["OPTIONS_RC_BRIDGE"], function(checked)
		profile.rcBridge = checked
	end)
	rcBridge:SetPoint("TOPLEFT", 0, y)
	rcBridge:SetChecked(profile.rcBridge)
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

-- The game's color picker. Current clients set it up through SetupColorPickerAndShow (the old
-- ColorPickerFrame.func fields are ignored there, so picks never reached the addon); older ones
-- still use the fields. onChange(r, g, b) runs live while picking, and with the old color on Cancel.
local function openColorPicker(r, g, b, onChange)
	local function onPick()
		onChange(ColorPickerFrame:GetColorRGB())
	end
	local function onCancel()
		onChange(r, g, b)
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b,
			hasOpacity = false,
			swatchFunc = onPick,
			cancelFunc = onCancel,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = onPick
		ColorPickerFrame.cancelFunc = onCancel
		ColorPickerFrame:SetColorRGB(r, g, b)
		ShowUIPanel(ColorPickerFrame)
	end
end

-- This character's response buttons (Data/Responses.lua). They apply to sessions this character
-- starts: a running session keeps the set it started with, and the holder's set wins for everyone.
local RESPONSE_ROW_HEIGHT = 30
local NEW_RESPONSE_COLOR = { r = 0.70, g = 0.70, b = 0.70 }

local function buildResponsesPage(page)
	local Responses = PLC.Responses
	local rows = {}
	local refreshRows

	-- Every edit works on a fresh copy of the list and saves the whole result.
	local function edit(change)
		local list = Responses:GetConfigured()
		change(list)
		Responses:Save(list)
		refreshRows()
	end

	local function moveRow(index, offset)
		edit(function(list)
			if list[index] and list[index + offset] then
				list[index], list[index + offset] = list[index + offset], list[index]
			end
		end)
	end

	local function commitText(index, box)
		local text = strtrim(((box:GetText() or ""):gsub("|", "")))
		local current = Responses:GetConfigured()[index]
		if current and text ~= "" and text ~= current.text then
			edit(function(list)
				list[index].text = text
			end)
		else
			refreshRows()
		end
	end

	for index = 1, Responses.MAX_COUNT do
		local row = CreateFrame("Frame", nil, page)
		row:SetSize(360, RESPONSE_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * RESPONSE_ROW_HEIGHT)

		-- A plain texture, not a themed fill: it shows the response's own color.
		row.swatch = CreateFrame("Button", nil, row)
		row.swatch:SetSize(22, 22)
		row.swatch:SetPoint("LEFT")
		row.swatch.tex = row.swatch:CreateTexture(nil, "ARTWORK")
		row.swatch.tex:SetPoint("TOPLEFT", 1, -1)
		row.swatch.tex:SetPoint("BOTTOMRIGHT", -1, 1)
		row.swatch.border = Primitives.createBorder(row.swatch)
		row.swatch:SetScript("OnClick", function()
			local current = Responses:GetConfigured()[index]
			if not current then
				return
			end
			openColorPicker(current.color.r, current.color.g, current.color.b, function(r, g, b)
				edit(function(list)
					if list[index] then
						list[index].color = { r = r, g = g, b = b }
					end
				end)
			end)
		end)

		row.box = Primitives.createEditBox(row, 180, 24)
		row.box:SetMaxLetters(Responses.MAX_TEXT_LETTERS)
		row.box:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
		row.box:HookScript("OnEditFocusLost", function(self)
			commitText(index, self)
		end)

		row.up = ButtonWidget.createButton(row, "^", 24)
		row.up:SetHeight(24)
		row.up:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
		row.up:SetScript("OnClick", function()
			moveRow(index, -1)
		end)

		row.down = ButtonWidget.createButton(row, "v", 24)
		row.down:SetHeight(24)
		row.down:SetPoint("LEFT", row.up, "RIGHT", 4, 0)
		row.down:SetScript("OnClick", function()
			moveRow(index, 1)
		end)

		row.remove = Primitives.createCloseButton(row, 16)
		row.remove:SetPoint("LEFT", row.down, "RIGHT", 8, 0)
		row.remove:SetScript("OnClick", function()
			edit(function(list)
				table.remove(list, index)
			end)
		end)

		rows[index] = row
	end

	local buttonsTop = -(Responses.MAX_COUNT * RESPONSE_ROW_HEIGHT + 8)
	local addButton = ButtonWidget.createButton(page, L["OPTIONS_RESPONSES_ADD"], 130)
	addButton:SetPoint("TOPLEFT", 0, buttonsTop)
	addButton:SetScript("OnClick", function()
		edit(function(list)
			if #list < Responses.MAX_COUNT then
				table.insert(list, { key = Responses.NewKey(list), text = L["OPTIONS_RESPONSES_NEW"], color = NEW_RESPONSE_COLOR })
			end
		end)
	end)

	local resetButton = ButtonWidget.createButton(page, L["OPTIONS_ACCENT_RESET"], 130)
	resetButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
	resetButton:SetScript("OnClick", function()
		Responses:Reset()
		refreshRows()
	end)

	local hint = Primitives.createText(page, L["OPTIONS_RESPONSES_HINT"], 11, "dim")
	hint:SetPoint("TOPLEFT", addButton, "BOTTOMLEFT", 0, -12)
	hint:SetPoint("RIGHT", page, "RIGHT")
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(true)

	function refreshRows()
		local list = Responses:GetConfigured()
		for index, row in ipairs(rows) do
			local resp = list[index]
			row:SetShown(resp ~= nil)
			if resp then
				row.swatch.tex:SetColorTexture(resp.color.r, resp.color.g, resp.color.b)
				if not row.box:HasFocus() then
					row.box:SetText(resp.text)
				end
				row.up:SetShown(index > 1)
				row.down:SetShown(index < #list)
				row.remove:SetShown(#list > 1)
			end
		end
		addButton:SetShown(#list < Responses.MAX_COUNT)
	end

	page:HookScript("OnShow", refreshRows)
	refreshRows()
end

-- An auto loot target (Loot/AutoLoot.lua) as a dropdown plus, for "Players...", a box for the names.
-- picker:Set(target) shows a target; picker:Get() returns the chosen one, nil if no names are typed
-- yet. onChange(target) runs when a complete choice is made.
local function createTargetPicker(parent, dropdownWidth, boxWidth, onChange)
	local AutoLoot = PLC.Loot.AutoLoot
	local PLAYERS = "players"
	local mode = AutoLoot.SELF
	local picker = {}

	picker.dropdown = DropdownWidget.createDropdownButton(parent)
	picker.dropdown:SetSize(dropdownWidth, Theme.LAYOUT.fieldHeight)
	picker.box = Primitives.createEditBox(parent, boxWidth, Theme.LAYOUT.fieldHeight)
	picker.box:SetPoint("LEFT", picker.dropdown, "RIGHT", 4, 0)

	local function names()
		return strtrim((picker.box:GetValue() or ""))
	end

	function picker:Get()
		if mode ~= PLAYERS then
			return mode
		end
		return names() ~= "" and names() or nil
	end

	local function changed()
		local target = picker:Get()
		if onChange and target then
			onChange(target)
		end
	end

	local function selectMode(newMode)
		mode = newMode
		picker.box:SetShown(mode == PLAYERS)
		local labels = {
			[AutoLoot.SELF] = L["OPTIONS_AUTOLOOT_SELF"],
			[AutoLoot.LEAVE] = L["OPTIONS_AUTOLOOT_LEAVE"],
			[PLAYERS] = L["OPTIONS_AUTOLOOT_PLAYERS"],
		}
		local entries = {}
		for _, value in ipairs({ AutoLoot.SELF, AutoLoot.LEAVE, PLAYERS }) do
			table.insert(entries, {
				text = labels[value],
				checked = value == mode,
				onClick = function()
					selectMode(value)
					changed()
					if value == PLAYERS then
						picker.box:SetFocus()
					end
				end,
			})
		end
		DropdownWidget.setEntries(picker.dropdown, labels[mode], entries)
	end

	function picker:Set(target)
		if target == AutoLoot.SELF or target == AutoLoot.LEAVE then
			picker.box:SetText("")
			selectMode(target)
		else
			picker.box:SetText(target or "")
			selectMode(PLAYERS)
		end
	end

	picker.box:HookScript("OnEditFocusLost", changed)
	picker:Set(AutoLoot.SELF)
	return picker
end

local function buildAutoLootPage(page)
	local AutoLoot = PLC.Loot.AutoLoot
	local settings = PLC.db.profile.autoLoot
	local PICKER_DROPDOWN = 150
	local PICKER_BOX = 200

	local enabled = CheckboxWidget.createCheckbox(page, L["OPTIONS_AUTOLOOT_ENABLED"], function(checked)
		settings.enabled = checked
	end)
	enabled:SetPoint("TOPLEFT", 0, 0)

	local gold = CheckboxWidget.createCheckbox(page, L["OPTIONS_AUTOLOOT_GOLD"], function(checked)
		settings.lootGold = checked
	end)
	gold:SetPoint("TOPLEFT", 0, -26)

	local outside = CheckboxWidget.createCheckbox(page, L["OPTIONS_AUTOLOOT_OUTSIDE"], function(checked)
		settings.outsideInstances = checked
	end)
	outside:SetPoint("TOPLEFT", 0, -52)

	local reviewLabel = Primitives.createText(page, L["OPTIONS_AUTOLOOT_REVIEW"], 13, "white")
	reviewLabel:SetPoint("TOPLEFT", 0, -86)
	local review = createTargetPicker(page, PICKER_DROPDOWN, PICKER_BOX, function(target)
		settings.reviewTarget = target
	end)
	review.dropdown:SetPoint("TOPLEFT", reviewLabel, "BOTTOMLEFT", 0, -6)

	local otherLabel = Primitives.createText(page, L["OPTIONS_AUTOLOOT_OTHER"], 13, "white")
	otherLabel:SetPoint("TOPLEFT", 0, -142)
	local other = createTargetPicker(page, PICKER_DROPDOWN, PICKER_BOX, function(target)
		settings.otherTarget = target
	end)
	other.dropdown:SetPoint("TOPLEFT", otherLabel, "BOTTOMLEFT", 0, -6)

	local exceptionLabel = Primitives.createText(page, L["OPTIONS_AUTOLOOT_EXCEPTIONS"], 13, "white")
	exceptionLabel:SetPoint("TOPLEFT", 0, -198)

	local itemBox = Primitives.createEditBox(page, 110, Theme.LAYOUT.fieldHeight)
	itemBox:SetPoint("TOPLEFT", exceptionLabel, "BOTTOMLEFT", 0, -6)
	local exceptionTarget = createTargetPicker(page, 120, 90)
	exceptionTarget.dropdown:SetPoint("LEFT", itemBox, "RIGHT", 4, 0)
	exceptionTarget:Set(AutoLoot.LEAVE)
	local addButton = ButtonWidget.createButton(page, L["OPTIONS_AUTOLOOT_ADD"], 52)
	addButton:SetHeight(Theme.LAYOUT.fieldHeight)
	addButton:SetPoint("LEFT", exceptionTarget.box, "RIGHT", 4, 0)

	-- Shift-clicking an item inserts its link into the box while it has focus.
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
			if itemBox:HasFocus() then
				itemBox:SetText(text or "")
			end
		end)
	end

	local hint = Primitives.createText(page, L["OPTIONS_AUTOLOOT_HINT"], 11, "dim")
	hint:SetPoint("BOTTOMLEFT")
	hint:SetPoint("BOTTOMRIGHT")
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(true)

	local listHolder = CreateFrame("Frame", nil, page)
	listHolder:SetPoint("TOPLEFT", itemBox, "BOTTOMLEFT", 0, -8)
	listHolder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 62)
	listHolder.border = Primitives.createBorder(listHolder, "borderDim")
	local exceptionTable = PLC.UI.Widgets.DataTable.Create(listHolder, NAME_ROW_HEIGHT)

	local function targetLabel(target)
		if target == AutoLoot.SELF then
			return L["OPTIONS_AUTOLOOT_SELF"]
		elseif target == AutoLoot.LEAVE then
			return L["OPTIONS_AUTOLOOT_LEAVE"]
		end
		return target
	end

	local refreshExceptions
	exceptionTable:SetColumns({
		{
			width = 200,
			render = function(rowData)
				return "  " .. rowData.name
			end,
		},
		{
			width = 140,
			render = function(rowData)
				return targetLabel(rowData.target)
			end,
		},
		{
			width = 24,
			isWidget = true,
			create = function(row)
				return Primitives.createCloseButton(row, 14)
			end,
			update = function(button, rowData)
				button:SetShown(not rowData.builtIn)
				button:SetScript("OnClick", function()
					settings.exceptions[rowData.itemID] = nil
					refreshExceptions()
				end)
			end,
		},
	})

	-- Everyone's own exceptions, then the curated list (Data/ExcludedItems.lua) for whatever they
	-- didn't override. The curated entries can be overridden but not removed.
	function refreshExceptions()
		local rows = {}
		for itemID, target in pairs(settings.exceptions) do
			table.insert(rows, { itemID = itemID, target = target, name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID) })
		end
		for itemID in pairs(PLC.ExcludedItems) do
			if not settings.exceptions[itemID] then
				table.insert(rows, { itemID = itemID, target = AutoLoot.LEAVE, builtIn = true, name = C_Item.GetItemInfo(itemID) or ("item:" .. itemID) })
			end
		end
		table.sort(rows, function(a, b) return a.name < b.name end)
		exceptionTable:SetRows(rows)
	end

	local function addException()
		local text = strtrim(itemBox:GetValue() or "")
		local itemID = tonumber(text) or tonumber(text:match("item:(%d+)")) or C_Item.GetItemInfoInstant(text)
		if not itemID then
			print(L["CHAT_PREFIX"] .. L["OPTIONS_AUTOLOOT_UNKNOWN_ITEM"])
			return
		end
		local target = exceptionTarget:Get()
		if target then
			settings.exceptions[itemID] = target
			itemBox:SetText("")
			itemBox:ClearFocus()
			refreshExceptions()
		end
	end
	addButton:SetScript("OnClick", addException)
	itemBox:SetScript("OnEnterPressed", addException)

	local function refreshPage()
		enabled:SetChecked(settings.enabled)
		gold:SetChecked(settings.lootGold)
		outside:SetChecked(settings.outsideInstances)
		review:Set(settings.reviewTarget)
		other:Set(settings.otherTarget)
		refreshExceptions()
	end
	page:HookScript("OnShow", refreshPage)
	refreshPage()
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

-- A practice run for the whole group (Data/Preview.lua). Also /plc preview.
local function buildPreviewPage(page)
	local text = Primitives.createText(page, L["OPTIONS_PREVIEW_HELP"], 12)
	text:SetPoint("TOPLEFT")
	text:SetPoint("TOPRIGHT")
	text:SetJustifyH("LEFT")
	text:SetWordWrap(true)

	local button = ButtonWidget.createButton(page, L["OPTIONS_PREVIEW_START"], 160)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)

	local function refresh()
		button.label:SetText(L[PLC.Session.preview and "OPTIONS_PREVIEW_STOP" or "OPTIONS_PREVIEW_START"])
	end
	button:SetScript("OnClick", function()
		PLC.Preview:Toggle()
		refresh()
	end)
	page:HookScript("OnShow", refresh)
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

	-- Live preview while picking, restored on Cancel.
	swatch:SetScript("OnClick", function()
		openColorPicker(profile.accent.r, profile.accent.g, profile.accent.b, setAccent)
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
		height = 610, -- General stacks 5 checkboxes + 4 sliders under the page header
		title = L["OPTIONS_TITLE"],
	})

	panel:AddSidebarHeader(L["OPTIONS_SECTION_COUNCIL"])
	buildGeneralPage(panel:AddTab("general", L["OPTIONS_TAB_GENERAL"],
		{ icon = "nav_general.png", description = L["OPTIONS_DESC_GENERAL"] }))
	buildAutoLootPage(panel:AddTab("autoloot", L["OPTIONS_TAB_AUTOLOOT"],
		{ icon = "nav_general.png", description = L["OPTIONS_DESC_AUTOLOOT"] }))
	buildResponsesPage(panel:AddTab("responses", L["OPTIONS_TAB_RESPONSES"],
		{ icon = "nav_responses.png", description = L["OPTIONS_DESC_RESPONSES"] }))
	buildCouncilPage(panel:AddTab("council", L["OPTIONS_TAB_COUNCIL"],
		{ icon = "nav_council.png", description = L["OPTIONS_COUNCIL_INTRO"] }))

	panel:AddSidebarHeader(L["OPTIONS_SECTION_SETTINGS"])
	buildPreviewPage(panel:AddTab("preview", L["OPTIONS_TAB_PREVIEW"],
		{ icon = "nav_general.png", description = L["OPTIONS_DESC_PREVIEW"] }))
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
