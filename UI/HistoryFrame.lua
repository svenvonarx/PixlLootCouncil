local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DropdownWidget = PLC.UI.Widgets.Dropdown
local DataTable = PLC.UI.Widgets.DataTable
local PopupMenu = PLC.UI.Widgets.PopupMenu
local Theme = PLC.UI.Theme

-- Loot history browser, modeled on RCLootCouncil's (lootHistory.lua GetFrame/BuildData): a date
-- list and a name list that each toggle a filter on click, the main entry table (newest first),
-- click-a-row details, double-click delete, and an Export button whose output follows the current
-- date/name selection exactly like RC's GetFilteredDB-based exporters. Data: Data/History.lua.
local HistoryFrame = {}
PLC.UI.HistoryFrame = HistoryFrame

local frame
local dateTable, nameTable, mainTable
local headerButtons = {}
local countText, emptyText, formatDropdown, filterButton
local exportFrame, importFrame
local selectedDate, selectedName
local sortKey, sortDesc = "time", true
local infoEntry -- entry whose details tooltip is currently shown

local LIST_ROW_HEIGHT = 20
local MAIN_ROW_HEIGHT = 22
local DOUBLE_CLICK_SECONDS = 0.5

local EXPORT_FORMATS = {
	{ key = "sheets", text = L["HISTORY_EXPORT_SHEETS"], delimiter = ";" },
	{ key = "tsv", text = L["HISTORY_EXPORT_TSV"], delimiter = "," },
}

local function exportFormat()
	local key = PLC.db.profile.historyExport
	for _, f in ipairs(EXPORT_FORMATS) do
		if f.key == key then
			return f
		end
	end
	return EXPORT_FORMATS[1]
end

local function classColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return c.r, c.g, c.b
	end
	return Primitives.color("text")
end

local function itemName(link)
	return link and link:match("%[(.-)%]") or ""
end

local function newerFirst(a, b)
	if a.epoch ~= b.epoch then
		return a.epoch > b.epoch
	end
	return a.counter > b.counter
end

local COMPARATORS = {
	time = function(a, b)
		return newerFirst(a, b)
	end,
	name = function(a, b)
		if a.short ~= b.short then
			return a.short < b.short
		end
		return newerFirst(a, b)
	end,
	item = function(a, b)
		if a.itemName ~= b.itemName then
			return a.itemName < b.itemName
		end
		return newerFirst(a, b)
	end,
	reason = function(a, b)
		if a.response ~= b.response then
			return a.response < b.response
		end
		return newerFirst(a, b)
	end,
}

-- "time" ascending is the reverse of newerFirst; the others reverse their primary order.
local function sortRows(rows)
	local cmp = COMPARATORS[sortKey]
	local primaryDesc = sortKey == "time"
	if sortDesc == primaryDesc then
		table.sort(rows, cmp)
	else
		table.sort(rows, function(a, b) return cmp(b, a) end)
	end
end

local function hideInfo()
	infoEntry = nil
	if GameTooltip:GetOwner() == frame then
		GameTooltip:Hide()
	end
end

-- RC's "more info" essentials (lootHistory.lua UpdateMoreInfo).
local function showInfo(row)
	local e = row.entry
	if infoEntry == e then
		hideInfo()
		return
	end
	infoEntry = e
	local r, g, b = classColor(row.class)
	GameTooltip:SetOwner(frame, "ANCHOR_NONE")
	GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
	GameTooltip:AddLine(row.short, r, g, b)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["HISTORY_INFO_TIME"], (e.time or "?") .. " " .. (e.date or "?"), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["HISTORY_INFO_LOOT"], e.lootWon or _G.UNKNOWN, 1, 1, 1, 1, 1, 1)
	if e.itemReplaced1 then
		GameTooltip:AddDoubleLine(L["HISTORY_INFO_REPLACED"], e.itemReplaced1, 1, 1, 1, 1, 1, 1)
		if e.itemReplaced2 then
			GameTooltip:AddDoubleLine(" ", e.itemReplaced2, 1, 1, 1, 1, 1, 1)
		end
	end
	GameTooltip:AddDoubleLine(L["HISTORY_INFO_BOSS"], e.boss or _G.UNKNOWN, 1, 1, 1, 0.86, 0.08, 0.24)
	GameTooltip:AddDoubleLine(L["HISTORY_INFO_INSTANCE"], e.instance or _G.UNKNOWN, 1, 1, 1, 0.82, 0.41, 0.12)
	GameTooltip:AddDoubleLine(L["HISTORY_INFO_OWNER"], e.owner or _G.UNKNOWN, 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["HISTORY_INFO_VOTES"], tostring(e.votes or 0), 1, 1, 1, 1, 1, 1)
	if e.note and e.note ~= "" then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(L["HISTORY_INFO_NOTE"], e.note, 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function updateHeaders()
	for key, button in pairs(headerButtons) do
		local active = key == sortKey
		local suffix = active and (sortDesc and " v" or " ^") or ""
		button.label:SetText(button.baseText .. suffix)
		local r, g, b = Primitives.color(active and "accent" or "dim")
		button.label:SetTextColor(r, g, b)
	end
end

-- Re-selects the list row matching `value` after a rebuild (row order can shift as data changes).
local function reselect(tbl, rows, field, value)
	local index
	if value then
		for i, row in ipairs(rows) do
			if row[field] == value then
				index = i
				break
			end
		end
	end
	tbl:SetSelectedIndex(index)
	return index ~= nil
end

local function refresh()
	if not frame then
		return
	end
	local db = PLC.History:GetDB()

	-- Date and name lists come from the full DB (like RC), not the filtered view.
	local dates, names, seenDate = {}, {}, {}
	for name, entries in pairs(db) do
		if type(entries) == "table" and #entries > 0 then
			local class
			for _, e in ipairs(entries) do
				local d = e.date or L["HISTORY_UNKNOWN_DATE"]
				if not seenDate[d] then
					seenDate[d] = true
					table.insert(dates, { date = d })
				end
				class = e.class or class
			end
			table.insert(names, { name = name, short = PLC.Roster:ShortName(name), class = class })
		end
	end
	table.sort(dates, function(a, b) return a.date > b.date end)
	table.sort(names, function(a, b) return a.short < b.short end)

	dateTable:SetRows(dates)
	nameTable:SetRows(names)
	if not reselect(dateTable, dates, "date", selectedDate) then
		selectedDate = nil
	end
	if not reselect(nameTable, names, "name", selectedName) then
		selectedName = nil
	end

	local rows = {}
	for name, entries in pairs(PLC.History:GetFilteredDB(selectedDate, selectedName)) do
		local short = PLC.Roster:ShortName(name)
		for _, e in ipairs(entries) do
			local epoch, counter = PLC.History.EntryEpoch(e)
			table.insert(rows, {
				name = name,
				short = short,
				class = e.class,
				entry = e,
				epoch = epoch,
				counter = counter,
				itemName = itemName(e.lootWon),
				response = tostring(e.response or ""),
			})
		end
	end
	sortRows(rows)
	mainTable:SetRows(rows)
	mainTable:SetSelectedIndex(nil)
	hideInfo()

	countText:SetText(string.format(L["HISTORY_COUNT"], #rows))
	emptyText:SetShown(#rows == 0)
	updateHeaders()
	-- RC colors its Filter button orange while any filter is active.
	local r, g, b = Primitives.color(PLC.History:IsFiltering() and "accent" or "text")
	filterButton.label:SetTextColor(r, g, b)
end

-- RC's filter menu, flattened into one list (the popup has no submenus): classes, then responses.
-- Both lists only offer values that actually occur in the stored history.
local function openFilterMenu()
	local f = PLC.db.profile.historyFilters
	local classes, responses, seenClass, seenResponse = {}, {}, {}, {}
	for _, list in pairs(PLC.History:GetDB()) do
		if type(list) == "table" then
			for _, e in ipairs(list) do
				if e.class and not seenClass[e.class] then
					seenClass[e.class] = true
					table.insert(classes, e.class)
				end
				local key = PLC.History:ResponseKey(e)
				if not seenResponse[key] then
					seenResponse[key] = e.color
					table.insert(responses, key)
				end
			end
		end
	end
	table.sort(classes, function(a, b)
		return (LOCALIZED_CLASS_NAMES_MALE[a] or a) < (LOCALIZED_CLASS_NAMES_MALE[b] or b)
	end)
	table.sort(responses)

	local entries = {}
	local classEntries = {}
	table.insert(entries, { text = L["HISTORY_FILTER_CLASS"], header = true })
	for _, class in ipairs(classes) do
		local r, g, b = classColor(class)
		local entry = {
			text = LOCALIZED_CLASS_NAMES_MALE[class] or class,
			color = { r = r, g = g, b = b },
			checked = f.class[class] or false,
			keepOpen = true,
		}
		entry.onClick = function()
			f.class[class] = not f.class[class] or nil
			entry.checked = f.class[class] or false
			refresh()
		end
		table.insert(entries, entry)
		table.insert(classEntries, entry)
	end
	table.insert(entries, {
		text = L["HISTORY_FILTER_ALL_CLASSES"],
		keepOpen = true,
		onClick = function()
			wipe(f.class)
			for _, entry in ipairs(classEntries) do
				entry.checked = false
			end
			refresh()
		end,
	})

	table.insert(entries, { text = L["HISTORY_FILTER_RESPONSES"], header = true })
	for _, key in ipairs(responses) do
		local c = seenResponse[key]
		local entry = {
			text = key ~= "" and key or _G.UNKNOWN,
			color = type(c) == "table" and type(c[1]) == "number" and { r = c[1], g = c[2], b = c[3] } or nil,
			checked = not f.hiddenResponses[key],
			keepOpen = true,
		}
		entry.onClick = function()
			f.hiddenResponses[key] = not f.hiddenResponses[key] or nil
			entry.checked = not f.hiddenResponses[key]
			refresh()
		end
		table.insert(entries, entry)
	end

	PopupMenu.Open(filterButton, entries, { width = 200, maxRows = 18 })
end

-- Export popup: a read-only, auto-selected text box. Above HUGE_EXPORT_LENGTH characters it uses a
-- single-line box instead, RC's approach to avoid freezing the client on a huge multi-line layout
-- (Ctrl+C still copies everything).
local function ensureExportFrame()
	if exportFrame then
		return exportFrame
	end
	local width, height = 700, 360
	exportFrame = CreateFrame("Frame", "PixlLootCouncilHistoryExportFrame", UIParent)
	Primitives.refreshFontsOnShow(exportFrame)
	exportFrame:SetSize(width, height)
	exportFrame:SetPoint("CENTER")
	exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	exportFrame:SetMovable(true)
	exportFrame:EnableMouse(true)
	exportFrame:RegisterForDrag("LeftButton")
	exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
	exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilHistoryExportFrame")

	exportFrame.bg = Primitives.createTexture(exportFrame, "BACKGROUND", "frame")
	exportFrame.bg:SetAllPoints()
	exportFrame.border = Primitives.createBorder(exportFrame)

	local header = CreateFrame("Frame", nil, exportFrame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()
	header.title = Primitives.createText(header, L["HISTORY_EXPORT_TITLE"], 14, "title")
	header.title:SetPoint("LEFT", 10, 0)
	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		exportFrame:Hide()
	end)

	local content = CreateFrame("Frame", nil, exportFrame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	local function readOnly(box)
		box:SetAutoFocus(false)
		box:SetFontObject(ChatFontNormal)
		box:SetMaxLetters(0)
		box:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				self:SetText(exportFrame.text or "")
				self:HighlightText()
			end
		end)
		box:SetScript("OnEditFocusGained", function(self)
			self:HighlightText()
		end)
		box:SetScript("OnEscapePressed", function()
			exportFrame:Hide()
		end)
	end

	-- Normal export: multi-line box inside the shared scroll widget.
	exportFrame.scrollHolder = CreateFrame("Frame", nil, content)
	exportFrame.scrollHolder:SetAllPoints()
	local scroll = PLC.UI.Widgets.ScrollFrame.createScrollFrame(exportFrame.scrollHolder)
	exportFrame.multi = CreateFrame("EditBox", nil, scroll)
	exportFrame.multi:SetMultiLine(true)
	exportFrame.multi:SetWidth(width - 20 - PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH)
	exportFrame.multi:SetHeight(20)
	readOnly(exportFrame.multi)
	scroll:SetScrollChild(exportFrame.multi)
	scroll:SetScript("OnMouseDown", function()
		exportFrame.multi:SetFocus()
	end)

	-- Huge export: single-line box plus an explanation.
	exportFrame.hugeHolder = CreateFrame("Frame", nil, content)
	exportFrame.hugeHolder:SetAllPoints()
	local hugeLabel = Primitives.createText(exportFrame.hugeHolder, L["HISTORY_HUGE_EXPORT"], 11, "dim")
	hugeLabel:SetPoint("TOPLEFT")
	hugeLabel:SetPoint("TOPRIGHT")
	hugeLabel:SetJustifyH("LEFT")
	exportFrame.single = CreateFrame("EditBox", nil, exportFrame.hugeHolder)
	exportFrame.single:SetPoint("TOPLEFT", hugeLabel, "BOTTOMLEFT", 0, -8)
	exportFrame.single:SetPoint("TOPRIGHT", hugeLabel, "BOTTOMRIGHT", 0, -8)
	exportFrame.single:SetHeight(24)
	exportFrame.single.bg = Primitives.createTexture(exportFrame.single, "BACKGROUND", "field")
	exportFrame.single.bg:SetAllPoints()
	exportFrame.single:SetTextInsets(6, 6, 0, 0)
	readOnly(exportFrame.single)

	exportFrame:Hide()
	return exportFrame
end

local function showExport(text)
	local f = ensureExportFrame()
	f.text = text
	local huge = #text >= PLC.History.HUGE_EXPORT_LENGTH
	f.scrollHolder:SetShown(not huge)
	f.hugeHolder:SetShown(huge)
	local box = huge and f.single or f.multi
	box:SetText(text)
	f:Show()
	box:SetFocus()
	box:HighlightText()
end

-- Import popup: paste RC's "Player Export" string, or pull straight from RCLootCouncil's own saved
-- data when RC is installed on this character. The in-game paths (RC's /rc sync, and mirroring an
-- RC master looter's awards) need no window at all -- see Data/HistoryImport.lua.
local function ensureImportFrame()
	if importFrame then
		return importFrame
	end
	local width, height = 560, 340
	importFrame = CreateFrame("Frame", "PixlLootCouncilHistoryImportFrame", UIParent)
	Primitives.refreshFontsOnShow(importFrame)
	importFrame:SetSize(width, height)
	importFrame:SetPoint("CENTER")
	importFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	importFrame:SetMovable(true)
	importFrame:EnableMouse(true)
	importFrame:RegisterForDrag("LeftButton")
	importFrame:SetScript("OnDragStart", importFrame.StartMoving)
	importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilHistoryImportFrame")

	importFrame.bg = Primitives.createTexture(importFrame, "BACKGROUND", "frame")
	importFrame.bg:SetAllPoints()
	importFrame.border = Primitives.createBorder(importFrame)

	local header = CreateFrame("Frame", nil, importFrame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()
	header.title = Primitives.createText(header, L["HISTORY_IMPORT_TITLE"], 14, "title")
	header.title:SetPoint("LEFT", 10, 0)
	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		importFrame:Hide()
	end)

	local content = CreateFrame("Frame", nil, importFrame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	local help = Primitives.createText(content, L["HISTORY_IMPORT_HELP"], 11, "dim")
	help:SetPoint("TOPLEFT")
	help:SetPoint("TOPRIGHT")
	help:SetJustifyH("LEFT")
	help:SetWordWrap(true)

	local importButton = ButtonWidget.createButton(content, L["HISTORY_IMPORT_BUTTON"], 100)
	importButton:SetPoint("BOTTOMRIGHT")

	importFrame.localButton = ButtonWidget.createButton(content, L["HISTORY_IMPORT_FROM_RC"], 220)
	importFrame.localButton:SetPoint("BOTTOMLEFT")
	importFrame.localButton:SetScript("OnClick", function()
		if PLC.History:ImportFromLocalRC() then
			importFrame:Hide()
		end
	end)

	local boxHolder = CreateFrame("Frame", nil, content)
	boxHolder:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -10)
	boxHolder:SetPoint("BOTTOMRIGHT", importButton, "TOPRIGHT", 0, 10)
	boxHolder.bg = Primitives.createTexture(boxHolder, "BACKGROUND", "field")
	boxHolder.bg:SetAllPoints()
	boxHolder.border = Primitives.createBorder(boxHolder, "borderDim")
	local scroll = PLC.UI.Widgets.ScrollFrame.createScrollFrame(boxHolder)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	box:SetMaxLetters(0)
	box:SetWidth(width - 30 - PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH)
	box:SetHeight(20)
	box:SetTextInsets(6, 6, 6, 6)
	box:SetScript("OnEscapePressed", function()
		importFrame:Hide()
	end)
	scroll:SetScrollChild(box)
	scroll:SetScript("OnMouseDown", function()
		box:SetFocus()
	end)
	importFrame.box = box

	importButton:SetScript("OnClick", function()
		if PLC.History:ImportPlayerExport(box:GetText()) then
			box:SetText("")
			importFrame:Hide()
		end
	end)

	importFrame:Hide()
	return importFrame
end

local function showImport()
	local f = ensureImportFrame()
	f.localButton:SetShown(PLC.History:HasLocalRCData())
	f.box:SetText("")
	f:Show()
	f.box:SetFocus()
end

local function onExportClick()
	local fmt = exportFormat()
	showExport(PLC.History:ExportTSV(fmt.delimiter, PLC.History:GetFilteredDB(selectedDate, selectedName)))
end

local function updateFormatDropdown()
	local current = exportFormat()
	local entries = {}
	for _, f in ipairs(EXPORT_FORMATS) do
		table.insert(entries, {
			text = f.text,
			checked = f.key == current.key,
			onClick = function()
				PLC.db.profile.historyExport = f.key
				updateFormatDropdown()
			end,
		})
	end
	DropdownWidget.setEntries(formatDropdown, current.text, entries)
end

local function textHolder(row, width)
	local holder = CreateFrame("Frame", nil, row)
	holder:SetSize(width, MAIN_ROW_HEIGHT)
	holder.text = Primitives.createText(holder, "", 11)
	holder.text:SetPoint("LEFT")
	holder.text:SetPoint("RIGHT")
	holder.text:SetJustifyH("LEFT")
	return holder
end

local MAIN_COLUMNS = {
	{
		width = 20,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(20, MAIN_ROW_HEIGHT)
			holder.icon = Primitives.createClassIcon(holder, nil)
			holder.icon:SetSize(16, 16)
			holder.icon:SetPoint("CENTER")
			return holder
		end,
		update = function(holder, rowData)
			Primitives.setClassIcon(holder.icon, rowData.class)
		end,
	},
	{
		width = 100,
		render = function(rowData)
			local r, g, b = classColor(rowData.class)
			return rowData.short, r, g, b
		end,
	},
	{
		width = 130,
		render = function(rowData)
			local r, g, b = Primitives.color("dim")
			return (rowData.entry.date or "?") .. "-" .. (rowData.entry.time or "?"), r, g, b
		end,
	},
	{
		width = 24,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(20, 20)
			holder.texture = holder:CreateTexture(nil, "ARTWORK")
			holder.texture:SetAllPoints()
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			local icon = rowData.entry.lootWon and select(5, C_Item.GetItemInfoInstant(rowData.entry.lootWon))
			holder.texture:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			holder.itemLink = rowData.entry.lootWon
		end,
	},
	{
		width = 200,
		isWidget = true,
		create = function(row)
			local holder = textHolder(row, 196)
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			holder.text:SetText(rowData.entry.lootWon or "?")
			holder.itemLink = rowData.entry.lootWon
		end,
	},
	{
		width = 150,
		render = function(rowData)
			local c = rowData.entry.color
			if type(c) == "table" and type(c[1]) == "number" then
				return rowData.response, c[1], c[2], c[3]
			end
			return rowData.response, 1, 1, 1
		end,
	},
	{
		width = 24,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(20, 20)
			holder:EnableMouse(true)
			holder.icon = Primitives.createNoteIcon(holder, 10)
			holder.icon:SetPoint("CENTER")
			holder:SetScript("OnEnter", function(self)
				if self.note then
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:SetText(self.note, nil, nil, nil, nil, true)
					GameTooltip:Show()
				end
			end)
			holder:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			return holder
		end,
		update = function(holder, rowData)
			local note = rowData.entry.note
			holder.note = (note and note ~= "") and note or nil
			holder.icon:SetShown(holder.note ~= nil)
		end,
	},
	{
		width = 24,
		isWidget = true,
		create = function(row)
			local button = Primitives.createCloseButton(row, 16)
			button:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(L["HISTORY_DELETE_TIP"])
				GameTooltip:Show()
			end)
			button:HookScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			return button
		end,
		-- RC's delete: two clicks within 0.5s, local only.
		update = function(button, rowData)
			button.lastClick = nil
			button:SetScript("OnClick", function(self)
				local now = GetTime()
				if self.lastClick and now - self.lastClick <= DOUBLE_CLICK_SECONDS then
					self.lastClick = nil
					PLC.History:DeleteEntry(rowData.name, rowData.entry)
				else
					self.lastClick = now
				end
			end)
		end,
	},
}

-- Sortable header captions over the main table's columns (x offsets match MAIN_COLUMNS).
local HEADERS = {
	{ key = "name", text = L["HISTORY_COL_NAME"], x = 20, width = 100 },
	{ key = "time", text = L["HISTORY_COL_TIME"], x = 120, width = 130 },
	{ key = "item", text = L["HISTORY_COL_ITEM"], x = 274, width = 200 },
	{ key = "reason", text = L["HISTORY_COL_REASON"], x = 474, width = 150 },
}

local function ensureFrame()
	if frame then
		return frame
	end

	local mainWidth = 0
	for _, col in ipairs(MAIN_COLUMNS) do
		mainWidth = mainWidth + col.width
	end
	local frameWidth = mainWidth + PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH + 20

	frame = CreateFrame("Frame", "PixlLootCouncilHistoryFrame", UIParent)
	Primitives.refreshFontsOnShow(frame)
	frame:SetSize(frameWidth, 480)
	frame:SetPoint("CENTER")
	-- Its own strata, below every other window here (Options HIGH, Session DIALOG, Loot
	-- FULLSCREEN_DIALOG, Trades TOOLTIP) -- sharing a strata with another window makes their child
	-- frames interleave, so one window's contents draw through the other.
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilHistoryFrame")
	Primitives.makeResizable(frame, frameWidth, 360, frameWidth, 900)
	frame:SetScript("OnHide", hideInfo)

	frame.bg = Primitives.createTexture(frame, "BACKGROUND", "frame")
	frame.bg:SetAllPoints()
	frame.border = Primitives.createBorder(frame)

	local header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()
	header.logo = Primitives.createLogo(header, 20)
	header.logo:SetPoint("LEFT", 10, 0)
	header.title = Primitives.createText(header, L["HISTORY_TITLE"], 18, "title")
	header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, -2)
	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		frame:Hide()
	end)
	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	local listHeight = LIST_ROW_HEIGHT * 5
	local reserve = PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH

	-- Date list
	local dateLabel = Primitives.createText(content, L["HISTORY_COL_DATE"], 11, "dim")
	dateLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	local dateHolder = CreateFrame("Frame", nil, content)
	dateHolder:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -18)
	dateHolder:SetSize(80 + reserve, listHeight)
	dateHolder.border = Primitives.createBorder(dateHolder, "borderDim")
	dateTable = DataTable.Create(dateHolder, LIST_ROW_HEIGHT)
	dateTable:SetColumns({
		{ width = 80, render = function(rowData) return "  " .. rowData.date end },
	})
	dateTable:SetRowClickHandler(function(rowData)
		selectedDate = (selectedDate ~= rowData.date) and rowData.date or nil
		refresh()
	end)

	-- Name list
	local nameX = 80 + reserve + 10
	local nameLabel = Primitives.createText(content, L["HISTORY_COL_NAME"], 11, "dim")
	nameLabel:SetPoint("TOPLEFT", content, "TOPLEFT", nameX, 0)
	local nameHolder = CreateFrame("Frame", nil, content)
	nameHolder:SetPoint("TOPLEFT", content, "TOPLEFT", nameX, -18)
	nameHolder:SetSize(20 + 110 + reserve, listHeight)
	nameHolder.border = Primitives.createBorder(nameHolder, "borderDim")
	nameTable = DataTable.Create(nameHolder, LIST_ROW_HEIGHT)
	nameTable:SetColumns({
		{
			width = 20,
			isWidget = true,
			create = function(row)
				local holder = CreateFrame("Frame", nil, row)
				holder:SetSize(20, LIST_ROW_HEIGHT)
				holder.icon = Primitives.createClassIcon(holder, nil)
				holder.icon:SetSize(14, 14)
				holder.icon:SetPoint("CENTER")
				return holder
			end,
			update = function(holder, rowData)
				Primitives.setClassIcon(holder.icon, rowData.class)
			end,
		},
		{
			width = 110,
			render = function(rowData)
				local r, g, b = classColor(rowData.class)
				return rowData.short, r, g, b
			end,
		},
	})
	nameTable:SetRowClickHandler(function(rowData)
		selectedName = (selectedName ~= rowData.name) and rowData.name or nil
		refresh()
	end)

	-- Controls (right side): Export + format, Clear Selection, entry count.
	local exportButton = ButtonWidget.createButton(content, L["HISTORY_EXPORT"], 90)
	exportButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -18)
	exportButton:SetScript("OnClick", onExportClick)

	formatDropdown = DropdownWidget.createDropdownButton(content)
	formatDropdown:SetSize(240, Theme.LAYOUT.fieldHeight)
	formatDropdown:SetPoint("RIGHT", exportButton, "LEFT", -8, 0)
	updateFormatDropdown()

	local clearButton = ButtonWidget.createButton(content, L["HISTORY_CLEAR_SELECTION"], 140)
	clearButton:SetPoint("TOPRIGHT", exportButton, "BOTTOMRIGHT", 0, -8)
	clearButton:SetScript("OnClick", function()
		selectedDate, selectedName = nil, nil
		refresh()
	end)

	filterButton = ButtonWidget.createButton(content, L["HISTORY_FILTER"], 90)
	filterButton:SetPoint("RIGHT", clearButton, "LEFT", -8, 0)
	filterButton:SetScript("OnClick", function(self)
		if PopupMenu.IsOpen(self) then
			PopupMenu.Close()
		else
			openFilterMenu()
		end
	end)

	local importButton = ButtonWidget.createButton(content, L["HISTORY_IMPORT"], 90)
	importButton:SetPoint("RIGHT", filterButton, "LEFT", -8, 0)
	importButton:SetScript("OnClick", showImport)

	countText = Primitives.createText(content, "", 11, "dim")
	countText:SetPoint("TOPRIGHT", clearButton, "BOTTOMRIGHT", 0, -10)

	-- Sortable header row + main table.
	local mainTop = -(18 + listHeight + 12)
	local headerRow = CreateFrame("Frame", nil, content)
	headerRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, mainTop)
	headerRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, mainTop)
	headerRow:SetHeight(18)
	for _, h in ipairs(HEADERS) do
		local button = CreateFrame("Button", nil, headerRow)
		button:SetPoint("TOPLEFT", headerRow, "TOPLEFT", h.x, 0)
		button:SetSize(h.width, 18)
		button.baseText = h.text
		button.label = Primitives.createText(button, button.baseText, 11, "dim")
		button.label:SetPoint("LEFT")
		button:SetScript("OnClick", function()
			if sortKey == h.key then
				sortDesc = not sortDesc
			else
				sortKey = h.key
				sortDesc = h.key == "time"
			end
			refresh()
		end)
		headerButtons[h.key] = button
	end

	local mainHolder = CreateFrame("Frame", nil, content)
	mainHolder:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -2)
	mainHolder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
	mainHolder.border = Primitives.createBorder(mainHolder, "borderDim")
	mainTable = DataTable.Create(mainHolder, MAIN_ROW_HEIGHT)
	mainTable:SetColumns(MAIN_COLUMNS)
	mainTable:SetRowClickHandler(showInfo)

	emptyText = Primitives.createText(mainHolder, L["HISTORY_EMPTY"], 12, "dim")
	emptyText:SetPoint("CENTER")

	frame:Hide()
	return frame
end

-- Hover helpers for the Loot Session window (UI/VotingFrame.lua candidate names, UI/SessionFrame.lua
-- item icons): append "what has this player received" / "who already received this item" lines to
-- an already-owned tooltip. The caller calls tooltip:Show() afterwards.
local PLAYER_RECENT_LINES = 6
local ITEM_RECIPIENT_LINES = 8

local function responseColor(entry)
	local c = entry.color
	if type(c) == "table" and type(c[1]) == "number" then
		return c[1], c[2], c[3]
	end
	return 1, 1, 1
end

function HistoryFrame.AddPlayerLines(tooltip, fullName, currentLink)
	local rows = PLC.History:GetPlayerEntries(fullName)
	tooltip:AddLine(" ")
	if #rows == 0 then
		tooltip:AddLine(L["HISTORY_TIP_NONE"], 0.6, 0.6, 0.6)
		return
	end

	local currentID = currentLink and PLC.History.GetItemIDFromLink(currentLink)
	for _, row in ipairs(rows) do
		if currentID and PLC.History.GetItemIDFromLink(row.entry.lootWon) == currentID then
			local r, g, b = Primitives.color("warning")
			tooltip:AddLine(string.format(L["HISTORY_TIP_ALREADY_HAS"], row.entry.date or "?"), r, g, b)
			break
		end
	end

	-- Per-response totals, most frequent first (RC's "number of items received" summary).
	local counts, order, colors = {}, {}, {}
	for _, row in ipairs(rows) do
		local key = PLC.History:ResponseKey(row.entry)
		if not counts[key] then
			counts[key] = 0
			colors[key] = row.entry
			table.insert(order, key)
		end
		counts[key] = counts[key] + 1
	end
	table.sort(order, function(a, b)
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	local ar, ag, ab = Primitives.color("accent")
	tooltip:AddLine(string.format(L["HISTORY_TIP_TOTAL"], #rows), ar, ag, ab)
	for _, key in ipairs(order) do
		local r, g, b = responseColor(colors[key])
		tooltip:AddDoubleLine("  " .. (key ~= "" and key or _G.UNKNOWN), tostring(counts[key]), r, g, b, 1, 1, 1)
	end

	tooltip:AddLine(" ")
	tooltip:AddLine(L["HISTORY_TIP_RECENT"], ar, ag, ab)
	for i = 1, math.min(#rows, PLAYER_RECENT_LINES) do
		local e = rows[i].entry
		local r, g, b = responseColor(e)
		tooltip:AddDoubleLine(e.lootWon or "?", (e.response or "") .. "  |cff999999" .. (e.date or "") .. "|r", 1, 1, 1, r, g, b)
	end
	if #rows > PLAYER_RECENT_LINES then
		tooltip:AddLine(string.format(L["HISTORY_TIP_MORE"], #rows - PLAYER_RECENT_LINES), 0.6, 0.6, 0.6)
	end
end

function HistoryFrame.AddItemLines(tooltip, link)
	local itemID = link and PLC.History.GetItemIDFromLink(link)
	if not itemID then
		return
	end
	local rows = PLC.History:GetItemRecipients(itemID)
	tooltip:AddLine(" ")
	if #rows == 0 then
		tooltip:AddLine(L["HISTORY_TIP_ITEM_NONE"], 0.6, 0.6, 0.6)
		return
	end
	local ar, ag, ab = Primitives.color("accent")
	tooltip:AddLine(string.format(L["HISTORY_TIP_ITEM_RECIPIENTS"], #rows), ar, ag, ab)
	for i = 1, math.min(#rows, ITEM_RECIPIENT_LINES) do
		local row = rows[i]
		local cr, cg, cb = classColor(row.entry.class)
		local r, g, b = responseColor(row.entry)
		tooltip:AddDoubleLine("  " .. PLC.Roster:ShortName(row.name),
			(row.entry.response or "") .. "  |cff999999" .. (row.entry.date or "") .. "|r", cr, cg, cb, r, g, b)
	end
	if #rows > ITEM_RECIPIENT_LINES then
		tooltip:AddLine(string.format(L["HISTORY_TIP_MORE"], #rows - ITEM_RECIPIENT_LINES), 0.6, 0.6, 0.6)
	end
end

function HistoryFrame:Open()
	local f = ensureFrame()
	f:Show()
	refresh()
end

function HistoryFrame:Toggle()
	local f = ensureFrame()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		refresh()
	end
end

-- Called from Data/History.lua whenever an entry is recorded, received or deleted.
function HistoryFrame:OnHistoryUpdated()
	if frame and frame:IsShown() then
		refresh()
	end
end

PLC:RegisterSlashCommand("history", "Open the Loot History window", function()
	HistoryFrame:Toggle()
end)
