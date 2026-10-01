local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local ScrollFrame = PLC.UI.Widgets.ScrollFrame

-- New widget -- no direct upstream pattern to port (see docs/SPECIFICATION.md §4.4; neither
-- RCLootCouncil_Classic's lib-st nor FojjiCore's createScrollFrame describe a row-recycling
-- virtualized list internally). Fixed pool of row frames sized to visible rows, rebound on
-- scroll/column change instead of created/destroyed per row.
--
-- Column spec: either a text column { width, justify, render = function(rowData) return text,
-- r, g, b end }, or a widget column { width, isWidget = true, create = function(row) return
-- widget end, update = function(widget, rowData) end } -- used for VotingFrame's per-row Award
-- button.
local DataTable = {}
PLC.UI.Widgets.DataTable = DataTable

local Table = {}
local TableMeta = { __index = Table }

local DEFAULT_ROW_HEIGHT = 24

function DataTable.Create(parent, rowHeight)
	local scroll = ScrollFrame.createScrollFrame(parent)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local self = setmetatable({
		scroll = scroll,
		content = content,
		rowHeight = rowHeight or DEFAULT_ROW_HEIGHT,
		columns = {},
		rows = {}, -- pool of row frames, index 1..currently-visible
		data = {}, -- full current dataset (array)
	}, TableMeta)

	scroll:SetScript("OnSizeChanged", function()
		self:Layout()
	end)
	scroll:SetScript("OnVerticalScroll", function()
		self:Refresh()
	end)

	return self
end

local function getRow(self, index)
	local row = self.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, self.content)
	row:SetHeight(self.rowHeight)
	row.cells = {}
	self.rows[index] = row
	return row
end

function Table:SetColumns(columns)
	self.columns = columns
	for _, row in ipairs(self.rows) do
		row.cells = {}
	end
	self:Layout()
end

-- Builds/repositions exactly as many row frames as currently fit (plus one partial), and each
-- row's per-column cells -- called on resize or column change, not on every data update.
function Table:Layout()
	local width = self.scroll:GetWidth()
	local height = self.scroll:GetHeight()
	if not width or width <= 0 or not height or height <= 0 then
		return
	end

	local visible = math.max(1, math.floor(height / self.rowHeight) + 1)
	for index = 1, visible do
		local row = getRow(self, index)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(index - 1) * self.rowHeight)
		row:SetWidth(width)

		local x = 0
		for colIndex, col in ipairs(self.columns) do
			local cell = row.cells[colIndex]
			if not cell then
				if col.isWidget then
					cell = col.create(row)
				else
					cell = Primitives.createText(row, "", 11)
					cell:SetJustifyH(col.justify or "LEFT")
				end
				row.cells[colIndex] = cell
			end
			cell:ClearAllPoints()
			cell:SetPoint("LEFT", row, "LEFT", x, 0)
			if not col.isWidget then
				cell:SetWidth(col.width)
			end
			x = x + col.width
		end
	end
	for index = visible + 1, #self.rows do
		self.rows[index]:Hide()
	end

	self.content:SetSize(width, math.max(1, #self.data * self.rowHeight))
	self:Refresh()
end

-- Full rebuild of what each visible row frame is bound to -- call when the row SET changes
-- (items added/removed/reordered/scrolled), not for a single value changing on an existing row.
function Table:SetRows(data)
	self.data = data
	self.content:SetSize(self.content:GetWidth(), math.max(1, #data * self.rowHeight))
	self:Refresh()
end

function Table:Refresh()
	local offset = math.floor((self.scroll:GetVerticalScroll() or 0) / self.rowHeight)
	for index, row in ipairs(self.rows) do
		local dataIndex = offset + index
		local rowData = self.data[dataIndex]
		if rowData then
			row.dataIndex = dataIndex
			row:Show()
			self:RenderRow(row, rowData)
		else
			row.dataIndex = nil
			row:Hide()
		end
	end
end

-- Targeted single-row update -- touches only this row's cells, not a full table rebuild. This is
-- the path a live candidate response takes (see docs/SPECIFICATION.md §4.4 stage-4 test).
function Table:RefreshRow(dataIndex)
	for _, row in ipairs(self.rows) do
		if row.dataIndex == dataIndex then
			self:RenderRow(row, self.data[dataIndex])
			return
		end
	end
end

function Table:RenderRow(row, rowData)
	for colIndex, col in ipairs(self.columns) do
		local cell = row.cells[colIndex]
		if cell then
			if col.isWidget then
				if col.update then
					col.update(cell, rowData)
				end
			else
				local text, r, g, b = col.render(rowData)
				cell:SetText(text or "")
				if r then
					cell:SetTextColor(r, g, b)
				end
			end
		end
	end
end
