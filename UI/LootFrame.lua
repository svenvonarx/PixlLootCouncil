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
local dataTable
local tickerHandle

-- Response buttons and the note field share one row, same as the original layout -- a stacked
-- (buttons-then-note) layout was tried and made every row much taller than before for no real
-- gain. The note box has a fixed size -- same width as the full button row, same height as a
-- single button -- set once and never recalculated against the window's current width (an
-- in-between round made it dynamic, which just made its size unpredictable).
local ROW_HEIGHT = Theme.LAYOUT.buttonHeight + 6

local function myResponse(idx)
	local responses = PLC.Session.responses[idx]
	local guid = UnitGUID("player")
	return responses and responses[guid]
end

local function buildRows()
	local rows = {}
	local now = time()
	for idx, item in pairs(PLC.Session.items) do
		local expired = item.deadlineAt and now > item.deadlineAt
		if not myResponse(idx) and not expired then
			table.insert(rows, { idx = idx, link = item.link, icon = item.icon, deadlineAt = item.deadlineAt })
		end
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
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

local function ensureFrame()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "PixlLootCouncilLootFrame", UIParent)
	-- Wider default than before -- the response row's buttons+note are both fixed-size now (see
	-- the response column below), together wider than the old dynamically-shrinking note field,
	-- so the window needs more starting width to show a full row without the note box spilling
	-- past the right edge (nothing in this row layout clips to the window's own bounds).
	frame:SetSize(780, 260)
	frame:SetPoint("CENTER", 0, -80)
	-- Top of the three main windows on purpose -- one tier above UI/SessionFrame.lua's "DIALOG"
	-- (itself one tier above UI/OptionsFrame.lua's "HIGH") -- responding to loot always needs to
	-- be reachable, so this window must never end up hidden behind either of the others
	-- regardless of which was clicked/opened more recently.
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilLootFrame")
	Primitives.makeResizable(frame, 700, 180, 1000, 600)

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

	header.title = Primitives.createText(header, L["LOOTFRAME_TITLE"], 14, "title")
	header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, 0)

	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		frame:Hide()
	end)

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	dataTable = DataTable.Create(content, ROW_HEIGHT)
	dataTable.scroll:SetAllPoints()

	dataTable:SetColumns({
		{
			width = 28,
			isWidget = true,
			create = function(row)
				local holder = CreateFrame("Frame", nil, row)
				holder:SetSize(24, 24)
				holder.texture = holder:CreateTexture(nil, "ARTWORK")
				holder.texture:SetAllPoints()
				return holder
			end,
			update = function(holder, rowData)
				holder.texture:SetTexture(rowData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			end,
		},
		{
			width = 170,
			render = function(row)
				return row.link or "?"
			end,
		},
		{
			-- Just the number now -- the row's own depleting background (set up below via
			-- SetRowTimerProvider) is the "bar", so this column no longer needs to carry one
			-- itself. Narrower than the old text+bar column; the freed width goes to the
			-- 5-button response row to its right.
			width = 40,
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
			-- Non-binding -- this is the last column in the row, so its declared width is never
			-- used to position anything after it (see UI/Widgets/DataTable.lua:Layout). The
			-- container below sizes itself to its own content instead.
			width = 260,
			isWidget = true,
			create = function(row)
				local container = CreateFrame("Frame", nil, row)
				container.buttons = {}

				local x = 0
				local BUTTON_GAP = 6
				for i, resp in ipairs(PLC.db.profile.responses) do
					-- Omitting a fixed width lets each button size itself to its own label (see
					-- UI/Widgets/Button.lua) -- a shared fixed width left short labels like "OS"
					-- swimming in padding while "Upgrade" looked cramped against its own border.
					local button = ButtonWidget.createButton(container, resp.text)
					button:SetPoint("LEFT", x, 0)
					x = x + button:GetWidth() + BUTTON_GAP
					container.buttons[resp.key] = button
				end
				container.buttonsWidth = x - BUTTON_GAP

				container.divider = Primitives.createTexture(container, "ARTWORK", "borderDim")
				container.divider:SetPoint("TOP", container.buttonsWidth + 6, -2)
				container.divider:SetPoint("BOTTOM", container.buttonsWidth + 6, 2)
				container.divider:SetWidth(1)

				-- Fixed size, matching the button row exactly -- same width as all 5 buttons
				-- together, same height as a single button, set once here and never resized
				-- afterward (a previous round recalculated this dynamically against the row's
				-- current width on every render, which read as the note field randomly changing
				-- size rather than having a stable, predictable size "like the buttons").
				-- `maxLetters` is sized to this exact width so typed text can realistically wrap
				-- to at most ~2 lines -- SetClipsChildren (see Primitives.createEditBox) is a
				-- backstop against overflow, not the primary control; relying on it alone let
				-- someone type a wall of text that silently vanished past line 2.
				local noteWidth = container.buttonsWidth
				local maxLetters = math.max(20, math.floor((noteWidth - 12) / 5.5) * 2)
				container.noteBox = Primitives.createEditBox(
					container, noteWidth, Theme.LAYOUT.buttonHeight, L["LOOTFRAME_NOTE_PLACEHOLDER"], true, maxLetters)
				container.noteBox:SetPoint("LEFT", container.buttonsWidth + 14, 0)

				container:SetSize(container.buttonsWidth + 14 + noteWidth, Theme.LAYOUT.buttonHeight)
				return container
			end,
			-- Only resets the note box when this row-pool slot gets rebound to a DIFFERENT item
			-- (container.idx changes) -- not on every refresh/tick for the same still-pending
			-- item, which would otherwise wipe out whatever the player is actively typing.
			update = function(container, rowData)
				if container.idx ~= rowData.idx then
					container.idx = rowData.idx
					container.noteBox:SetText(container.noteBox.placeholder)
					container.noteBox.showingPlaceholder = true
					local r, g, b = Primitives.color("dim")
					container.noteBox:SetTextColor(r, g, b)
				end
				for key, button in pairs(container.buttons) do
					button:SetScript("OnClick", function()
						local note = container.noteBox:GetValue()
						PLC.Session:SendMyResponse(rowData.idx, key, note ~= "" and note or nil)
					end)
				end
			end,
		},
	})

	-- Whole-row depleting background instead of the old column-local bar -- same math as the
	-- countdown text column above, just relocated (see UI/Widgets/DataTable.lua).
	dataTable:SetRowTimerProvider(function(rowData)
		if not rowData.deadlineAt then
			return nil
		end
		local remaining = math.max(0, rowData.deadlineAt - time())
		local total = math.max(1, PLC.Session.responseTimeoutSeconds)
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
	if PLC.Session.state ~= "active" then
		stopTicker()
		if frame then
			frame:Hide()
		end
		return
	end

	local rows = buildRows()
	if #rows == 0 then
		stopTicker()
		if frame then
			frame:Hide()
		end
		return
	end

	local f = ensureFrame()
	dataTable:SetRows(rows)
	f:Show()
	startTicker()
end

-- Manual reopen, in case the candidate closed it mid-session -- Refresh() only re-shows it
-- reactively, on an actual item/response/tick event.
PLC:RegisterSlashCommand("lootframe", "Reopen the loot response window", function()
	LootFrame:Refresh()
end)
