local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local CheckboxWidget = PLC.UI.Widgets.Checkbox
local ButtonWidget = PLC.UI.Widgets.Button
local DropdownWidget = PLC.UI.Widgets.Dropdown
local SliderWidget = PLC.UI.Widgets.Slider
local PanelLayout = PLC.UI.Widgets.PanelLayout
local Theme = PLC.UI.Theme

-- General / Auto Loot / Master Looter / Responses / Council / Appearance / Preview / About sidebar categories (spec §4.3), reading/writing
-- db.profile.* live -- no /reload needed to see a change take effect (AceDB itself handles
-- writing the change through to disk on logout).
local OptionsFrame = {}
PLC.UI.OptionsFrame = OptionsFrame

local panel

local NAME_ROW_HEIGHT = 20 -- the name lists on the Auto Loot, Council and About pages
local ML_ROW_HEIGHT = 26 -- the master looter list has buttons in its rows

-- Vertical rhythm of a settings page: a group title, then its controls.
local GROUP_TITLE_HEIGHT = 24
local CHECKBOX_STEP = 26
local FIELD_STEP = 36
local SLIDER_STEP = 52
local GROUP_GAP = 18

local QUALITIES = { 2, 3, 4, 5 } -- uncommon to legendary
local LOOT_THRESHOLDS = { 2, 3, 4 } -- the ones the game's own menu offers

local function qualityName(quality)
	return _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
end

local function secondsText(value)
	return string.format(L["OPTIONS_SECONDS"], value)
end

local function minutesText(value)
	return string.format(L[value == 1 and "OPTIONS_MINUTE" or "OPTIONS_MINUTES"], value)
end

-- By name and in the game's own colors: nobody knows what "quality 4" is. With noneText, there's a
-- first choice for no quality, stored as 0.
local function createQualityField(page, y, text, tip, key, qualities, noneText)
	local profile = PLC.db.profile
	local label = Primitives.createText(page, text, 12)
	label:SetPoint("TOPLEFT", 0, y - 7)
	local dropdown = DropdownWidget.createDropdownButton(page)
	dropdown:SetSize(150, Theme.LAYOUT.fieldHeight)
	dropdown:SetPoint("TOPRIGHT", 0, y)
	local function refresh()
		local entries = {}
		local function addEntry(quality, name, color)
			table.insert(entries, {
				text = name,
				color = color,
				checked = quality == profile[key],
				onClick = function()
					profile[key] = quality
					refresh()
				end,
			})
		end
		if noneText then
			addEntry(0, noneText)
		end
		for _, quality in ipairs(qualities) do
			addEntry(quality, qualityName(quality), ITEM_QUALITY_COLORS[quality])
		end
		local current = profile[key]
		DropdownWidget.setEntries(dropdown, current == 0 and noneText or qualityName(current), entries)
		local color = current ~= 0 and ITEM_QUALITY_COLORS[current]
		if color then
			dropdown.text:SetTextColor(color.r, color.g, color.b)
		else
			dropdown.text:SetTextColor(Primitives.color("text"))
		end
	end
	refresh()
	page:HookScript("OnShow", refresh)
	Primitives.attachTooltip(dropdown, text, tip)
end

local function buildGeneralPage(page)
	local profile = PLC.db.profile
	local y = 0

	local function group(title)
		local label = Primitives.createText(page, title, 13, "white")
		label:SetPoint("TOPLEFT", 0, y)
		y = y - GROUP_TITLE_HEIGHT
	end

	local function checkbox(text, tip, getValue, setValue)
		local box = CheckboxWidget.createCheckbox(page, text, setValue)
		box:SetPoint("TOPLEFT", 0, y)
		box:SetChecked(getValue())
		Primitives.attachTooltip(box, text, tip)
		y = y - CHECKBOX_STEP
	end

	local function slider(text, tip, minValue, maxValue, step, key, format)
		local widget = SliderWidget.createSlider(page, text, minValue, maxValue, step, format)
		widget.container:SetPoint("TOPLEFT", 0, y)
		widget.container:SetPoint("TOPRIGHT", 0, y)
		widget:SetValue(profile[key])
		widget:ShowValue(profile[key])
		widget:SetScript("OnValueChanged", function(_, value)
			profile[key] = value
			widget:ShowValue(value)
		end)
		Primitives.attachTooltip(widget.container, text, tip)
		y = y - SLIDER_STEP
	end

	group(L["OPTIONS_GROUP_CHAT"])
	checkbox(L["OPTIONS_ANNOUNCE_START"], L["TIP_ANNOUNCE_START"], function() return profile.announce.sessionStart end,
		function(checked) profile.announce.sessionStart = checked end)
	checkbox(L["OPTIONS_ANNOUNCE_AWARD"], L["TIP_ANNOUNCE_AWARD"], function() return profile.announce.award end,
		function(checked) profile.announce.award = checked end)
	y = y - GROUP_GAP

	group(L["OPTIONS_GROUP_RC"])
	checkbox(L["OPTIONS_RC_BRIDGE"], L["TIP_RC_BRIDGE"], function() return profile.rcBridge end,
		function(checked) profile.rcBridge = checked end)
	checkbox(L["OPTIONS_MIRROR_RC"], L["TIP_MIRROR_RC"], function() return profile.historyMirrorRC end,
		function(checked) profile.historyMirrorRC = checked end)
	y = y - GROUP_GAP

	group(L["OPTIONS_GROUP_LOOT"])
	checkbox(L["OPTIONS_AUTO_START"], L["TIP_AUTO_START"], function() return profile.autoStartSession end,
		function(checked) profile.autoStartSession = checked end)
	y = y - 4
	createQualityField(page, y, L["OPTIONS_LOOT_THRESHOLD"], L["TIP_LOOT_THRESHOLD"], "lootThreshold", QUALITIES)
	y = y - FIELD_STEP - GROUP_GAP + 8

	group(L["OPTIONS_GROUP_TIMING"])
	-- The holder's value at session start wins for every candidate -- see
	-- Data/Session.lua:Start()/OnSessionStartReceived -- so changing this only affects sessions
	-- this character goes on to hold, never a session already in progress.
	slider(L["OPTIONS_RESPONSE_TIMEOUT"], L["TIP_RESPONSE_TIMEOUT"], 15, 300, 5, "responseTimeoutSeconds", secondsText)
	slider(L["OPTIONS_HEARTBEAT_SECONDS"], L["TIP_HEARTBEAT"], 15, 180, 5, "sessionHeartbeatSeconds", secondsText)
	slider(L["OPTIONS_FORCE_END_MINUTES"], L["TIP_FORCE_END"], 1, 30, 1, "sessionForceEndMinutes", minutesText)
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

		Primitives.attachTooltip(row.swatch, L["TIP_RESPONSE_COLOR_TITLE"], L["TIP_RESPONSE_COLOR"])

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

	Primitives.attachTooltip(addButton, L["OPTIONS_RESPONSES_ADD"], L["TIP_RESPONSES_ADD"])

	local resetButton = ButtonWidget.createButton(page, L["OPTIONS_ACCENT_RESET"], 130)
	resetButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
	Primitives.attachTooltip(resetButton, L["OPTIONS_ACCENT_RESET"], L["TIP_RESPONSES_RESET"])
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
	Primitives.attachTooltip(enabled, L["OPTIONS_AUTOLOOT_ENABLED"], L["TIP_AUTOLOOT_ENABLED"])
	Primitives.attachTooltip(gold, L["OPTIONS_AUTOLOOT_GOLD"], L["TIP_AUTOLOOT_GOLD"])
	Primitives.attachTooltip(outside, L["OPTIONS_AUTOLOOT_OUTSIDE"], L["TIP_AUTOLOOT_OUTSIDE"])

	local reviewLabel = Primitives.createText(page, L["OPTIONS_AUTOLOOT_REVIEW"], 13, "white")
	reviewLabel:SetPoint("TOPLEFT", 0, -86)
	local review = createTargetPicker(page, PICKER_DROPDOWN, PICKER_BOX, function(target)
		settings.reviewTarget = target
	end)
	review.dropdown:SetPoint("TOPLEFT", reviewLabel, "BOTTOMLEFT", 0, -6)
	Primitives.attachTooltip(review.dropdown, L["OPTIONS_AUTOLOOT_REVIEW"], L["TIP_AUTOLOOT_REVIEW"])
	Primitives.attachTooltip(review.box, L["OPTIONS_AUTOLOOT_PLAYERS"], L["TIP_AUTOLOOT_NAMES"])

	local otherLabel = Primitives.createText(page, L["OPTIONS_AUTOLOOT_OTHER"], 13, "white")
	otherLabel:SetPoint("TOPLEFT", 0, -142)
	local other = createTargetPicker(page, PICKER_DROPDOWN, PICKER_BOX, function(target)
		settings.otherTarget = target
	end)
	other.dropdown:SetPoint("TOPLEFT", otherLabel, "BOTTOMLEFT", 0, -6)
	Primitives.attachTooltip(other.dropdown, L["OPTIONS_AUTOLOOT_OTHER"], L["TIP_AUTOLOOT_OTHER"])
	Primitives.attachTooltip(other.box, L["OPTIONS_AUTOLOOT_PLAYERS"], L["TIP_AUTOLOOT_NAMES"])

	local exceptionLabel = Primitives.createText(page, L["OPTIONS_AUTOLOOT_EXCEPTIONS"], 13, "white")
	exceptionLabel:SetPoint("TOPLEFT", 0, -198)

	local itemBox = Primitives.createEditBox(page, 110, Theme.LAYOUT.fieldHeight)
	itemBox:SetPoint("TOPLEFT", exceptionLabel, "BOTTOMLEFT", 0, -6)
	local exceptionTarget = createTargetPicker(page, 120, 90)
	exceptionTarget.dropdown:SetPoint("LEFT", itemBox, "RIGHT", 4, 0)
	exceptionTarget:Set(AutoLoot.LEAVE)
	Primitives.attachTooltip(itemBox, L["OPTIONS_AUTOLOOT_EXCEPTIONS"], L["TIP_AUTOLOOT_EXCEPTIONS"])
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

-- What happens when the group switches to Master Loot (Loot/MasterLooterList.lua).
local function buildMasterLooterPage(page)
	local profile = PLC.db.profile

	local enabled = CheckboxWidget.createCheckbox(page, L["OPTIONS_ML_ENABLED"], function(checked)
		profile.autoMasterLooter = checked
	end)
	enabled:SetPoint("TOPLEFT")
	Primitives.attachTooltip(enabled, L["OPTIONS_ML_ENABLED"], L["TIP_ML_ENABLED"])

	createQualityField(page, -CHECKBOX_STEP - 4, L["OPTIONS_ML_THRESHOLD"], L["TIP_ML_THRESHOLD"],
		"masterLootThreshold", LOOT_THRESHOLDS, L["OPTIONS_ML_THRESHOLD_NONE"])

	local listLabel = Primitives.createText(page, L["OPTIONS_ML_LIST"], 13, "white")
	listLabel:SetPoint("TOPLEFT", 0, -CHECKBOX_STEP - 4 - FIELD_STEP - 10)

	local nameBox = Primitives.createEditBox(page, 200, Theme.LAYOUT.fieldHeight)
	nameBox:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -8)
	Primitives.attachTooltip(nameBox, L["OPTIONS_ML_LIST"], L["TIP_ML_LIST"])
	local addButton = ButtonWidget.createButton(page, L["OPTIONS_COUNCIL_ADD"], 70)
	addButton:SetHeight(Theme.LAYOUT.fieldHeight)
	addButton:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)

	local hint = Primitives.createText(page, L["OPTIONS_ML_HINT"], 11, "dim")
	hint:SetPoint("BOTTOMLEFT")
	hint:SetPoint("BOTTOMRIGHT")
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(true)

	local listHolder = CreateFrame("Frame", nil, page)
	listHolder:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -8)
	listHolder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 48)
	listHolder.border = Primitives.createBorder(listHolder, "borderDim")
	local listTable = PLC.UI.Widgets.DataTable.Create(listHolder, ML_ROW_HEIGHT)

	local refreshList
	local function move(index, offset)
		local list = profile.masterLooterList
		if list[index] and list[index + offset] then
			list[index], list[index + offset] = list[index + offset], list[index]
			refreshList()
		end
	end

	local function moveButton(caption, offset)
		return {
			width = 28,
			isWidget = true,
			create = function(row)
				local button = ButtonWidget.createButton(row, caption, 24)
				button:SetHeight(22)
				return button
			end,
			update = function(button, rowData)
				button:SetShown(profile.masterLooterList[rowData.index + offset] ~= nil)
				button:SetScript("OnClick", function()
					move(rowData.index, offset)
				end)
			end,
		}
	end

	listTable:SetColumns({
		{
			width = 290,
			render = function(rowData)
				return string.format("  %d.  %s", rowData.index, rowData.name)
			end,
		},
		moveButton("^", -1),
		moveButton("v", 1),
		{
			width = 24,
			isWidget = true,
			create = function(row)
				return Primitives.createCloseButton(row, 14)
			end,
			update = function(button, rowData)
				button:SetScript("OnClick", function()
					table.remove(profile.masterLooterList, rowData.index)
					refreshList()
				end)
			end,
		},
	})

	function refreshList()
		local rows = {}
		for index, name in ipairs(profile.masterLooterList) do
			rows[index] = { index = index, name = name }
		end
		listTable:SetRows(rows)
	end

	local function addName()
		local name = strtrim(nameBox:GetValue() or "")
		if name == "" then
			return
		end
		-- Character names are stored capitalized, like the game shows them.
		name = name:sub(1, 1):upper() .. name:sub(2)
		for _, existing in ipairs(profile.masterLooterList) do
			if existing:lower() == name:lower() then
				nameBox:SetText("")
				return
			end
		end
		table.insert(profile.masterLooterList, name)
		nameBox:SetText("")
		nameBox:ClearFocus()
		refreshList()
	end
	addButton:SetScript("OnClick", addName)
	nameBox:SetScript("OnEnterPressed", addName)

	local function refreshPage()
		enabled:SetChecked(profile.autoMasterLooter)
		refreshList()
	end
	page:HookScript("OnShow", refreshPage)
	refreshPage()
end

-- Who's on the loot council (Data/CouncilRules.lua:Evaluate). The master looter is always on it
-- and runs the session; these settings add members. While a session runs, the HOLDER's settings
-- decide the council for everyone. Any change rebuilds the roster, which re-broadcasts the council
-- if this client is holding a session (Session:OnRosterRebuilt).
local MAX_RANKS = 10

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
	Primitives.attachTooltip(raidAssist, L["OPTIONS_COUNCIL_RAIDASSIST"], L["TIP_COUNCIL_RAIDASSIST"])

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
		Primitives.attachTooltip(box, L["OPTIONS_COUNCIL_GUILD_RANKS"], L["TIP_COUNCIL_RANKS"])
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
	Primitives.attachTooltip(nameBox, L["OPTIONS_COUNCIL_NAMES"], L["TIP_COUNCIL_NAMES"])
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
local refreshPreview
local function buildPreviewPage(page)
	local text = Primitives.createText(page, L["OPTIONS_PREVIEW_HELP"], 12)
	text:SetPoint("TOPLEFT")
	text:SetPoint("TOPRIGHT")
	text:SetJustifyH("LEFT")
	text:SetWordWrap(true)

	local button = ButtonWidget.createButton(page, L["OPTIONS_PREVIEW_START"], 160)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	Primitives.attachTooltip(button, L["OPTIONS_TAB_PREVIEW"], L["TIP_PREVIEW"])

	function refreshPreview()
		button.label:SetText(L[PLC.Session.preview and "OPTIONS_PREVIEW_STOP" or "OPTIONS_PREVIEW_START"])
	end
	button:SetScript("OnClick", function()
		PLC.Preview:Toggle()
	end)
	page:HookScript("OnShow", refreshPreview)
end

-- Who made this, what it's built on, and which version everyone in the group is running
-- (Data/Presence.lua). Version data comes in as people answer, so the list redraws as it does.
local VERSION_LIST_ROWS = 6
local refreshAbout

local function aboutLine(parent, y, label, value)
	local name = Primitives.createText(parent, label, 11, "dim")
	name:SetPoint("TOPLEFT", 0, y)
	local text = Primitives.createText(parent, value, 11)
	text:SetPoint("TOPLEFT", 92, y)
	text:SetPoint("RIGHT", parent, "RIGHT")
	text:SetJustifyH("LEFT")
end

local function versionRows()
	local Presence = PLC.Presence
	local rows = {}
	for guid, entry in PLC.Roster:IterateGroup() do
		local version = Presence.versions[guid]
		if guid == UnitGUID("player") then
			version = PLC.version or L["ABOUT_DEV_VERSION"]
		end
		local status, color
		if version and Presence.newest and Presence.IsNewer(Presence.newest, version) then
			status, color = L["ABOUT_STATUS_OUTDATED"], "warning"
		elseif version then
			status, color = L["ABOUT_STATUS_CURRENT"], "success"
		elseif Presence:IsPresent(guid) then
			version, status, color = L["ABOUT_VERSION_UNKNOWN"], L["ABOUT_STATUS_OUTDATED"], "warning"
		else
			version, status, color = "-", L["VOTINGFRAME_NO_ADDON"], "dim"
		end
		table.insert(rows, {
			name = PLC.Roster:ShortName(entry.name),
			class = entry.class,
			version = version,
			status = status,
			color = color,
		})
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

local function buildAboutPage(page)
	local logo = Primitives.createLogo(page, 34)
	logo:SetPoint("TOPLEFT")
	local title = Primitives.createText(page, ADDON_NAME, 20, "title")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -1)
	local versionText = Primitives.createText(page, "", 11, "dim")
	versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

	local versionsLabel = Primitives.createText(page, L["ABOUT_VERSIONS"], 13, "white")
	versionsLabel:SetPoint("TOPLEFT", 0, -54)
	local checkButton = ButtonWidget.createButton(page, L["ABOUT_CHECK_GROUP"], 100)
	checkButton:SetHeight(24)
	checkButton:SetPoint("TOPRIGHT", 0, -49)
	checkButton:SetScript("OnClick", function()
		PLC.Presence:CheckGroup()
	end)

	local listHolder = CreateFrame("Frame", nil, page)
	listHolder:SetPoint("TOPLEFT", 0, -78)
	listHolder:SetPoint("TOPRIGHT", 0, -78)
	listHolder:SetHeight(VERSION_LIST_ROWS * NAME_ROW_HEIGHT)
	listHolder.border = Primitives.createBorder(listHolder, "borderDim")
	local versionTable = PLC.UI.Widgets.DataTable.Create(listHolder, NAME_ROW_HEIGHT)
	versionTable:SetColumns({
		{
			width = 130,
			render = function(rowData)
				local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[rowData.class]
				if c then
					return "  " .. rowData.name, c.r, c.g, c.b
				end
				return "  " .. rowData.name
			end,
		},
		{
			width = 100,
			render = function(rowData)
				return rowData.version
			end,
		},
		{
			width = 140,
			render = function(rowData)
				local r, g, b = Primitives.color(rowData.color)
				return rowData.status, r, g, b
			end,
		},
	})

	local notices = CheckboxWidget.createCheckbox(page, L["ABOUT_UPDATE_NOTICES"], function(checked)
		PLC.db.profile.updateNotices = checked
	end)
	notices:SetPoint("TOPLEFT", 0, -(78 + VERSION_LIST_ROWS * NAME_ROW_HEIGHT + 10))
	notices:SetChecked(PLC.db.profile.updateNotices)
	Primitives.attachTooltip(notices, L["ABOUT_UPDATE_NOTICES"], L["TIP_UPDATE_NOTICES"])

	local creditsTop = -(78 + VERSION_LIST_ROWS * NAME_ROW_HEIGHT + 46)
	local creditsLabel = Primitives.createText(page, L["ABOUT_CREDITS"], 13, "white")
	creditsLabel:SetPoint("TOPLEFT", 0, creditsTop)
	aboutLine(page, creditsTop - 24, L["ABOUT_AUTHOR"], PLC.author or "?")
	aboutLine(page, creditsTop - 42, L["ABOUT_LIBRARIES"], L["ABOUT_LIBRARIES_LIST"])
	aboutLine(page, creditsTop - 60, L["ABOUT_FONT"], L["ABOUT_FONT_NAME"])
	aboutLine(page, creditsTop - 78, L["ABOUT_THANKS"], L["ABOUT_THANKS_RC"])
	aboutLine(page, creditsTop - 96, "", L["ABOUT_THANKS_GARGUL"])
	aboutLine(page, creditsTop - 114, L["ABOUT_LICENSE"], L["ABOUT_LICENSE_NAME"])

	-- The game can't open a browser, so the address is there to copy.
	local websiteLabel = Primitives.createText(page, L["ABOUT_WEBSITE"], 11, "dim")
	websiteLabel:SetPoint("TOPLEFT", 0, creditsTop - 138)
	local website = Primitives.createEditBox(page, 290, 24)
	website:SetPoint("TOPLEFT", 92, creditsTop - 132)
	website:SetText(PLC.website or "")
	website:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(PLC.website or "")
			self:HighlightText()
		end
	end)
	website:HookScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)

	function refreshAbout()
		local Presence = PLC.Presence
		local mine = PLC.version or L["ABOUT_DEV_VERSION"]
		if Presence.newest then
			versionText:SetText(string.format(L["ABOUT_VERSION_LINE_OUTDATED"], mine, Presence.newest))
		else
			versionText:SetText(string.format(L["ABOUT_VERSION_LINE"], mine))
		end
		versionTable:SetRows(versionRows())
	end

	page:HookScript("OnShow", function()
		refreshAbout()
		PLC.Presence:CheckGroup()
	end)
	refreshAbout()
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

	Primitives.attachTooltip(swatch, L["OPTIONS_ACCENT_COLOR"], L["TIP_ACCENT"])

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
		width = 580,
		height = 640, -- General, the tallest page, is three groups of settings under the page header
		title = L["OPTIONS_TITLE"],
	})

	panel:AddSidebarHeader(L["OPTIONS_SECTION_COUNCIL"])
	buildGeneralPage(panel:AddTab("general", L["OPTIONS_TAB_GENERAL"],
		{ icon = "nav_general.png", description = L["OPTIONS_DESC_GENERAL"] }))
	buildAutoLootPage(panel:AddTab("autoloot", L["OPTIONS_TAB_AUTOLOOT"],
		{ icon = "nav_autoloot.png", description = L["OPTIONS_DESC_AUTOLOOT"] }))
	buildMasterLooterPage(panel:AddTab("masterlooter", L["OPTIONS_TAB_ML"],
		{ icon = "nav_masterlooter.png", description = L["OPTIONS_DESC_ML"] }))
	buildResponsesPage(panel:AddTab("responses", L["OPTIONS_TAB_RESPONSES"],
		{ icon = "nav_responses.png", description = L["OPTIONS_DESC_RESPONSES"] }))
	buildCouncilPage(panel:AddTab("council", L["OPTIONS_TAB_COUNCIL"],
		{ icon = "nav_council.png", description = L["OPTIONS_COUNCIL_INTRO"] }))

	panel:AddSidebarHeader(L["OPTIONS_SECTION_SETTINGS"])
	buildAppearancePage(panel:AddTab("appearance", L["OPTIONS_TAB_APPEARANCE"],
		{ icon = "nav_appearance.png", description = L["OPTIONS_DESC_APPEARANCE"] }))

	panel:AddSidebarHeader(L["OPTIONS_SECTION_ADDON"])
	buildPreviewPage(panel:AddTab("preview", L["OPTIONS_TAB_PREVIEW"],
		{ icon = "nav_preview.png", description = L["OPTIONS_DESC_PREVIEW"] }))
	buildAboutPage(panel:AddTab("about", L["OPTIONS_TAB_ABOUT"],
		{ icon = "nav_about.png", description = L["OPTIONS_DESC_ABOUT"] }))

	return panel
end

function OptionsFrame:Open(tab)
	ensurePanel():Show()
	if tab then
		panel:SelectTab(tab)
	end
end

-- From Data/Presence.lua, as version answers come in.
-- A preview can start or end from anywhere, not just this page's button (Data/Preview.lua).
function OptionsFrame:OnPreviewChanged()
	if refreshPreview then
		refreshPreview()
	end
end

function OptionsFrame:OnVersionsUpdated()
	if refreshAbout and panel and panel.frame:IsShown() then
		refreshAbout()
	end
end

PLC:RegisterSlashCommand("options", "Open the options window", function()
	OptionsFrame:Open()
end)

PLC:RegisterSlashCommand("about", "Show the version, the group's versions and the credits", function()
	OptionsFrame:Open("about")
end)
