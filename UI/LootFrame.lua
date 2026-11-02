local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- Candidate-side response UI (header+content, no sidebar -- spec §4.3). One row per active
-- session item THIS PLAYER HASN'T RESPONDED TO YET -- once you vote, or the item's response
-- deadline passes, it simply stops being in buildRows() and vanishes from the table (matching
-- RCLootCouncil's behavior, per user feedback from the first live playtest -- no "you voted"
-- label to leave behind).
local LootFrame = {}
PLC.UI.LootFrame = LootFrame

local frame
local header
local dataTable
local tickerHandle
local builtSignature -- which response sets the buttons were built for, see applyResponseSets
local builtSets = {} -- those sets, in order
local columns -- the current ones, resized by fitColumns
local buttonsWidth = 0 -- the widest set's buttons
local openingWidth -- the width the window last opened at, see applyResponseSets
local minWidth, maxWidth = 1, 2000 -- set by applyResponseSets
local fittedCount -- how many items the height was last fitted to, see fitHeight
local sizingFrom -- the height when the player took hold of the resize grip

-- Response buttons and the note field share one row, same as the original layout -- a stacked
-- (buttons-then-note) layout was tried and made every row much taller than before for no real
-- gain. Rows run edge to edge, so the countdown fill crosses the whole window, and the icon, the
-- buttons and the note are all one height.
--
-- The window resizes in width. It opens with the note at NOTE_WIDTH; wider, the note gets the extra
-- room. Narrower, the name gives way first (down to NAME_MIN, truncated), then the note (down to
-- NOTE_MIN), and then the name goes altogether; the icon's tooltip still names the item.
local ICON_SIZE = 26
local PAD = 3 -- around the icon, and at the row's right end
local ROW_GAP = 1
local ROW_HEIGHT = ICON_SIZE + 2 * PAD + ROW_GAP
local ICON_COLUMN = PAD + ICON_SIZE + 8
local NAME_WIDTH, NAME_MIN = 170, 90
local NAME_GAP = 6
local TIMER_COLUMN = 40
local BUTTON_GAP = 6
local NOTE_LEAD = 15 -- buttons to note, with the divider in the middle
local NOTE_WIDTH, NOTE_MIN = 300, 120
local NOTE_MAX_LETTERS = 50 -- about what NOTE_WIDTH shows at once, so a note stays one line
local MAX_EXTRA_WIDTH = 400 -- how much wider than it opens the window can go
local BOTTOM_SPACE = 14 -- below the rows, for the resize grip
local SCREEN_MARGIN = 80 -- room the window leaves on screen at its tallest

local function myResponse(idx)
	local responses = PLC.Session.responses[idx]
	local guid = UnitGUID("player")
	return responses and responses[guid]
end

-- A row is everything this window needs from a source of items, so a session of this addon and one
-- from an RCLootCouncil master looter (Data/RCBridge.lua) look the same here.
local function sessionRows()
	local rows = {}
	local Session = PLC.Session
	if Session.state ~= "active" then
		return rows
	end
	local now = time()
	local responses = PLC.Responses:GetActive()
	for idx, item in pairs(Session.items) do
		local expired = item.deadlineAt and now > item.deadlineAt
		if not item.awarded and not myResponse(idx) and not expired then
			table.insert(rows, {
				id = "session" .. idx,
				idx = idx,
				link = item.link,
				icon = item.icon,
				deadlineAt = item.deadlineAt,
				timeoutSeconds = Session.responseTimeoutSeconds,
				responses = responses,
				ownerName = Session.owner and PLC.Roster:ShortName(Session.owner.name) or "?",
				respond = function(key, note)
					Session:SendMyResponse(idx, key, note)
				end,
			})
		end
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

local function buildRows()
	local rows = sessionRows()
	for _, row in ipairs(PLC.RCBridge:GetRows()) do
		table.insert(rows, row)
	end
	return rows
end

-- Every set of response buttons in play. From the whole session rather than the rows on screen, so
-- answering one kind of item doesn't rebuild the buttons under someone typing a note.
local function currentResponseSets()
	local sets = {}
	if PLC.Session.state == "active" then
		table.insert(sets, PLC.Responses:GetActive())
	end
	for set in pairs(PLC.RCBridge:GetResponseSets()) do
		table.insert(sets, set)
	end
	table.sort(sets, function(a, b) return PLC.Responses.Signature(a) < PLC.Responses.Signature(b) end)
	return sets
end

-- Ticks once a second while the frame is visible so remaining-time text counts down and expired
-- rows disappear promptly, instead of only updating on the next vote/item-add event.
local function startTicker()
	if tickerHandle then
		return
	end
	tickerHandle = PLC:ScheduleRepeatingTimer(function()
		LootFrame:Refresh()
	end, 1)
end

local function stopTicker()
	if tickerHandle then
		PLC:CancelTimer(tickerHandle)
		tickerHandle = nil
	end
end

-- Shows who's holding the current review pass directly in this window's title bar too (not just
-- UI/SessionFrame.lua's) -- a candidate deciding how to respond benefits from knowing who's
-- actually running the session just as much as the holder does.
-- Each response button sizes itself to its own label (Button.lua), and the label SET itself comes
-- from the session holder (Data/Responses.lua, Data/RCBridge.lua) -- so there's no fixed literal to
-- sum the way VotingFrame's fixed-width Award column has for its own window-sizing math. Builds
-- one throwaway instance purely to read back the real total width, rather than duplicating
-- Button.lua's own sizing formula a second time just to predict it. A button's width is reliable
-- immediately after creation (an explicit SetSize, not an anchor-resolved one), unlike content/
-- scroll's own width below, which only resolves once the window actually has a size -- so this is
-- safe to call before frame:SetSize, unlike trying to read the real row's own container width.
local function measureResponseButtonsWidth(set)
	local scratch = CreateFrame("Frame", nil, UIParent)
	scratch:Hide()
	local width = 0
	for _, resp in ipairs(set) do
		local button = ButtonWidget.createButton(scratch, resp.text)
		width = width + button:GetWidth() + BUTTON_GAP
	end
	return math.max(0, width - BUTTON_GAP)
end

local function updateHeaderOwner(rows)
	local text = string.format(L["STARTED_BY_LABEL"], rows[1].ownerName)
	header.ownerLabel:SetText(PLC.Session.preview and (text .. "  " .. L["PREVIEW_LABEL"]) or text)
	header.ownerLabel:Show()
end

-- The response columns are built per response set, since a row's buttons are fixed once created.
-- Columns 2 (the name) and 4 (buttons and note) change width with the window, see fitColumns.
local function buildColumns()
	return {
		{
			width = ICON_COLUMN,
			inset = PAD,
			isWidget = true,
			create = function(row)
				local holder = CreateFrame("Frame", nil, row)
				holder:SetSize(ICON_SIZE, ICON_SIZE)
				holder.texture = holder:CreateTexture(nil, "ARTWORK")
				holder.texture:SetAllPoints()
				Primitives.attachItemTooltip(holder)
				return holder
			end,
			update = function(holder, rowData)
				holder.texture:SetTexture(rowData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
				holder.itemLink = rowData.link
			end,
		},
		{
			-- A widget column, not a plain text one -- a FontString has no SetScript, so showing a
			-- tooltip on hover needs an actual Frame wrapping the text. One line, cut short with an
			-- ellipsis when it doesn't fit; hidden at width 0.
			width = NAME_WIDTH + NAME_GAP,
			isWidget = true,
			create = function(row)
				local holder = CreateFrame("Frame", nil, row)
				holder.text = Primitives.createText(holder, "", 11)
				holder.text:SetPoint("LEFT")
				holder.text:SetPoint("RIGHT")
				holder.text:SetJustifyH("LEFT")
				holder.text:SetWordWrap(false)
				Primitives.attachItemTooltip(holder)
				return holder
			end,
			resize = function(holder, width)
				holder:SetSize(math.max(1, width - NAME_GAP), ICON_SIZE)
				holder:SetShown(width > 0)
			end,
			update = function(holder, rowData)
				holder.text:SetText(rowData.link or "?")
				holder.itemLink = rowData.link
			end,
		},
		{
			-- Just the number -- the row's own depleting background (SetRowTimerProvider below) is
			-- the "bar".
			width = TIMER_COLUMN,
			justify = "CENTER",
			render = function(rowData)
				if not rowData.deadlineAt then
					return "-"
				end
				local remaining = math.max(0, rowData.deadlineAt - time())
				local secs = math.ceil(remaining)
				local colorName = secs <= 10 and "warning" or "text"
				local r, g, b = Primitives.color(colorName)
				return secs .. "s", r, g, b
			end,
		},
		{
			-- The buttons, then the note, which takes whatever this column's width leaves.
			width = buttonsWidth + NOTE_LEAD + NOTE_WIDTH + PAD,
			isWidget = true,
			create = function(row)
				local container = CreateFrame("Frame", nil, row)
				-- [set's signature] = { [key] = button }, one shown per row. By content, not by table:
				-- an RC master resending the same settings makes new tables with the same buttons.
				container.groups = {}

				container.buttonsWidth = 0
				for _, set in ipairs(builtSets) do
					local group = {}
					local x = 0
					for _, resp in ipairs(set) do
						-- Omitting a fixed width lets each button size itself to its own label (see
						-- UI/Widgets/Button.lua) -- a shared fixed width left short labels like "OS"
						-- swimming in padding while "Upgrade" looked cramped against its own border.
						local button = ButtonWidget.createButton(container, resp.text)
						button:SetHeight(ICON_SIZE)
						button:SetPoint("LEFT", x, 0)
						x = x + button:GetWidth() + BUTTON_GAP
						group[resp.key] = button
					end
					container.groups[PLC.Responses.Signature(set)] = group
					container.buttonsWidth = math.max(container.buttonsWidth, x - BUTTON_GAP)
				end

				container.divider = Primitives.createTexture(container, "ARTWORK", "borderDim")
				container.divider:SetPoint("TOP", container, "TOPLEFT", container.buttonsWidth + 7, -2)
				container.divider:SetPoint("BOTTOM", container, "BOTTOMLEFT", container.buttonsWidth + 7, 2)
				container.divider:SetWidth(1)

				-- One line: a single-line box never wraps, and the letter cap keeps a note about as
				-- long as the box shows at its usual width.
				container.noteBox = Primitives.createEditBox(
					container, NOTE_WIDTH, ICON_SIZE, L["LOOTFRAME_NOTE_PLACEHOLDER"], false, NOTE_MAX_LETTERS)
				container.noteBox:SetPoint("LEFT", container.buttonsWidth + NOTE_LEAD, 0)
				return container
			end,
			resize = function(container, width)
				container:SetSize(width, ICON_SIZE)
				container.noteBox:SetWidth(math.max(1, width - container.buttonsWidth - NOTE_LEAD - PAD))
			end,
			-- Only resets the note box when this row-pool slot gets rebound to a DIFFERENT item
			-- (container.id changes) -- not on every refresh/tick for the same still-pending
			-- item, which would otherwise wipe out whatever the player is actively typing.
			update = function(container, rowData)
				if container.id ~= rowData.id then
					container.id = rowData.id
					container.noteBox:SetText(container.noteBox.placeholder)
					container.noteBox.showingPlaceholder = true
					local r, g, b = Primitives.color("dim")
					container.noteBox:SetTextColor(r, g, b)
				end
				local shownSet = PLC.Responses.Signature(rowData.responses)
				for signature, group in pairs(container.groups) do
					local shown = signature == shownSet
					for key, button in pairs(group) do
						button:SetShown(shown)
						if shown then
							button:SetScript("OnClick", function()
								local note = container.noteBox:GetValue()
								rowData.respond(key, note ~= "" and note or nil)
							end)
						end
					end
				end
			end,
		},
	}
end

-- Everything in a row but the name and the note, which share the rest.
local function fixedWidth()
	return ICON_COLUMN + TIMER_COLUMN + buttonsWidth + NOTE_LEAD + PAD
end

-- Splits the room between the name and the note (see the top of this file). Runs before every
-- layout of the table, so on every resize.
local function fitColumns(rowWidth)
	if not columns then
		return
	end
	local room = rowWidth - fixedWidth()
	local name
	if room >= NAME_WIDTH + NAME_GAP + NOTE_WIDTH then
		name = NAME_WIDTH + NAME_GAP
	elseif room >= NAME_MIN + NAME_GAP + NOTE_WIDTH then
		name = room - NOTE_WIDTH
	elseif room >= NAME_MIN + NAME_GAP + NOTE_MIN then
		name = NAME_MIN + NAME_GAP
	else
		name = 0
	end
	columns[2].width = name
	columns[4].width = buttonsWidth + NOTE_LEAD + math.max(NOTE_MIN, room - name) + PAD
end

-- Rebuilds the buttons and refits the window whenever the response sets differ from the ones they
-- were built for: the holder's set arrives with session_start or the resync, so it can't be known
-- when the window is first created. Width is derived from the widest set's real total width, not a
-- literal. The window opens at the width that gives the note NOTE_WIDTH, and keeps a width the
-- player chose, within the new bounds.
local function applyResponseSets()
	local sets = currentResponseSets()
	local parts = {}
	for i, set in ipairs(sets) do
		parts[i] = PLC.Responses.Signature(set)
	end
	local signature = table.concat(parts, "\n\n")
	if signature == builtSignature then
		return
	end
	builtSignature = signature
	builtSets = sets

	buttonsWidth = 0
	for _, set in ipairs(sets) do
		buttonsWidth = math.max(buttonsWidth, measureResponseButtonsWidth(set))
	end
	local EDGES = 2 -- the window's 1px border, each side
	local opening = fixedWidth() + NAME_WIDTH + NAME_GAP + NOTE_WIDTH + EDGES
	minWidth = fixedWidth() + NOTE_MIN + EDGES
	maxWidth = opening + MAX_EXTRA_WIDTH
	local current = frame:GetWidth() or 0
	local chosen = openingWidth and math.abs(current - openingWidth) >= 1
	frame:SetWidth(chosen and math.max(minWidth, math.min(maxWidth, current)) or opening)
	openingWidth = opening
	fittedCount = nil -- the bounds changed: fitHeight sets them again
	columns = buildColumns()
	dataTable:SetColumns(columns)
end

-- Exactly `count` whole rows, nothing to scroll.
local function heightFor(count)
	return Theme.LAYOUT.headerHeight + 1 + ROW_GAP + count * ROW_HEIGHT - ROW_GAP + BOTTOM_SPACE
end

local function rowsOnScreen()
	local screen = UIParent:GetHeight() or 0
	if screen <= 0 then
		return math.huge
	end
	return math.max(1, math.floor((screen - SCREEN_MARGIN - heightFor(0)) / ROW_HEIGHT))
end

-- As tall as the rows the player chose to see (profile.lootResponseRows), but never taller than the
-- items there are: fewer items shrink the window, more grow it back to that. It can't be dragged
-- taller than all of them either, so there's no blank space below the rows and no scrollbar
-- unless there are more items than the player chose to see.
-- Keeps the top edge where it is, so the window grows and shrinks at the bottom.
local function setHeightKeepingTop(height)
	local left, top = frame:GetLeft(), frame:GetTop()
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	frame:SetHeight(height)
end

local function fitHeight(count)
	local most = math.max(1, math.min(count, rowsOnScreen()))
	Primitives.setResizeBounds(frame, minWidth, heightFor(1), maxWidth, heightFor(most))
	if not sizingFrom then
		setHeightKeepingTop(heightFor(math.min(most, PLC.db.profile.lootResponseRows)))
	end
end

-- Letting go of the grip keeps the height as the player's choice, in whole rows, if it changed:
-- a plain click on the grip while fewer items have shrunk the window mustn't lower it.
local function finishSizing()
	local from = sizingFrom
	sizingFrom = nil
	if not from then
		return
	end
	local height = frame:GetHeight() or from
	if math.abs(height - from) >= 1 then
		PLC.db.profile.lootResponseRows = math.max(1, math.floor((height - heightFor(0)) / ROW_HEIGHT + 0.5))
	end
	fitHeight(fittedCount or 1)
end

local function ensureFrame()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "PixlLootCouncilLootFrame", UIParent)
	-- Comes to the front when a session opens it, like any window (Primitives.makeWindow).
	Primitives.makeWindow(frame)
	-- The height follows the items and the player's choice, see fitHeight.
	frame:SetHeight(heightFor(1)) -- fitted to the items by Refresh
	frame:SetPoint("TOP", UIParent, "CENTER", 0, 60)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilLootFrame")
	-- The bounds are set by fitHeight, once the buttons and the items are known.
	local grip = Primitives.makeResizable(frame, 1, 1, 2000, 2000)
	grip:HookScript("OnMouseDown", function()
		sizingFrom = frame:GetHeight()
	end)
	grip:HookScript("OnMouseUp", finishSizing)
	grip:HookScript("OnHide", finishSizing)

	frame.bg = Primitives.createTexture(frame, "BACKGROUND", "frame")
	frame.bg:SetAllPoints()
	frame.border = Primitives.createBorder(frame)

	header = CreateFrame("Frame", nil, frame)
	header:SetHeight(Theme.LAYOUT.headerHeight)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header.bg = Primitives.createTexture(header, "BACKGROUND", "header")
	header.bg:SetAllPoints()

	header.logo = Primitives.createLogo(header, 20)
	header.logo:SetPoint("LEFT", 10, 0)

	-- Bigger than before, and centered on the logo same as always. The subtitle below is already
	-- at Primitives.createText's hard minimum render size (11 floors to the same 9px as a
	-- smaller value would -- there's no more room to shrink it), so widening the gap to make it
	-- read as "smaller in comparison" means growing the title instead.
	header.title = Primitives.createText(header, L["LOOTFRAME_TITLE"], 18, "title")
	-- The -2 is an empirical nudge, not 0 like every other "LEFT"-anchored pairing in this
	-- codebase: a FontString's "LEFT" anchor centers its full ascent+descent line box, not the
	-- actual rendered glyphs -- most fonts give more room below the baseline (for descenders)
	-- than above the cap-height, so the visible text sits a bit above true center once the box
	-- is tightly auto-fit with no slack for WoW's own layout to correct for that. Barely
	-- noticeable at the old 14pt size; visibly "too high" once bumped to 18pt, since the
	-- asymmetry scales with font size.
	header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, -2)

	-- Anchored BOTTOMLEFT-to-BOTTOMRIGHT (baseline-ish), not the LEFT-to-RIGHT (box-center)
	-- anchor every other text pairing in this codebase uses -- box-centering a much smaller
	-- subtitle against a much bigger title left it looking like it was sitting too low, since
	-- the two texts' vertical centers matched but their baselines didn't. The +1 is a small
	-- empirical nudge for the smaller font's own baseline sitting a touch higher in its line box.
	header.ownerLabel = Primitives.createText(header, "", 11, "dim")
	header.ownerLabel:SetPoint("BOTTOMLEFT", header.title, "BOTTOMRIGHT", 10, 1)
	header.ownerLabel:Hide()

	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		frame:Hide()
	end)

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	-- Edge to edge inside the 1px border, starting one row gap below the header's separator. The
	-- bottom keeps clear of the resize grip.
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 1, -1 - ROW_GAP)
	content:SetPoint("BOTTOMRIGHT", -1, BOTTOM_SPACE)

	-- UI/Widgets/ScrollFrame.lua anchors dataTable.scroll to `content` itself, so no SetAllPoints
	-- here -- calling it would override that anchoring.
	dataTable = DataTable.Create(content, ROW_HEIGHT, { rowGap = ROW_GAP, rowBackground = "content", overlayBar = true })
	dataTable:SetLayoutHandler(fitColumns)

	-- Whole-row depleting background instead of the old column-local bar -- same math as the
	-- countdown text column above, just relocated (see UI/Widgets/DataTable.lua).
	dataTable:SetRowTimerProvider(function(rowData)
		if not rowData.deadlineAt then
			return nil
		end
		local remaining = math.max(0, rowData.deadlineAt - time())
		local total = math.max(1, rowData.timeoutSeconds)
		local fraction = remaining / total
		local colorName = math.ceil(remaining) <= 10 and "warning" or "accent"
		local r, g, b = Primitives.color(colorName)
		return fraction, r, g, b, 0.14
	end)

	frame:Hide()
	return frame
end

-- Called (defensively) from Data/Session.lua whenever the item set or this player's own
-- responses change (session_start/item_add received, SendMyResponse's own optimistic update),
-- and once a second while shown (see startTicker). Hides itself once there's nothing left to
-- respond to, rather than showing an empty window.
function LootFrame:Refresh()
	local rows = buildRows()
	if #rows == 0 then
		stopTicker()
		if frame then
			frame:Hide()
		end
		return
	end

	local f = ensureFrame()
	applyResponseSets()
	if #rows ~= fittedCount then
		fittedCount = #rows
		fitHeight(#rows)
	end
	dataTable:SetRows(rows)
	updateHeaderOwner(rows)
	f:Show()
	startTicker()
end

-- Manual reopen (slash command, Loot Session toolbar), in case the candidate closed it
-- mid-session -- Refresh() only re-shows it reactively, on an actual item/response/tick event.
function LootFrame:Open()
	if #buildRows() == 0 then
		print(L["CHAT_PREFIX"] .. L["LOOTFRAME_NOTHING"])
		return
	end
	self:Refresh()
	Primitives.bringToFront(frame)
end

PLC:RegisterSlashCommand("loot", L["SLASH_LOOT"], function()
	LootFrame:Open()
end)
