local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- The single ML-facing window (header+content, no PanelLayout sidebar-nav -- spec §4.3, this is
-- a different kind of sidebar, see below): master-detail, RCLootCouncil-style -- a narrow
-- left-hand strip of item icons (status shown via border color + a tooltip, no room for inline
-- text at this width), click one to load its full candidate/response/Award/Pre-Award grid
-- (UI/VotingFrame.lua, embedded, not its own window) into the content area on the right.
--
-- Items accumulate in Data/Session.lua's PLC.Session.items from the moment they're silently
-- self-looted (Session:CollectDetectedItems), long before any review pass -- the icon list
-- always reflects that directly, not a separate pre-Start() "curation of the live loot window"
-- step (that step doesn't exist anymore under the bagged-item workflow: by the time anyone could
-- react to an item it's already bagged).
local SessionFrame = {}
PLC.UI.SessionFrame = SessionFrame

local frame
local header
local content
local itemListContainer
local dataTable
local detailArea
local detailItemLabel
local detailRemoveButton
local detailContainer
local votingPanel
local startButton
local endButton
local awardAllButton
local selectedIdx -- which session item's response grid is currently shown in the detail area
local refresh -- forward-declared: onRemoveClick (defined before it) calls it
local showDetailFor -- forward-declared: iconColumn's OnClick (defined before it) calls it
local tickerHandle

-- Mirrors UI/LootFrame.lua's ticker -- this window has no per-second updates driving it
-- otherwise (unlike LootFrame, nothing re-renders it on a timer), so without this the sidebar's
-- depleting bars and the tooltip's remaining-time line would only ever update on the next
-- item/award/click event, not while someone's just watching the clock run down.
local function startTicker()
	if tickerHandle then
		return
	end
	tickerHandle = PLC:ScheduleRepeatingTimer(function()
		if dataTable then
			dataTable:Refresh()
		end
	end, 1)
end

local function stopTicker()
	if tickerHandle then
		PLC:CancelTimer(tickerHandle)
		tickerHandle = nil
	end
end

-- Only worth ticking while there's an unawarded item still actively counting down -- an
-- all-awarded or all-expired session has nothing left that changes second to second.
local function hasLiveCountdown(rows)
	local now = time()
	for _, row in ipairs(rows) do
		if not row.awarded and row.deadlineAt and now < row.deadlineAt then
			return true
		end
	end
	return false
end

-- Two icons per sidebar row instead of one -- a raid can easily bag a dozen+ items over a few
-- hours, and a single-wide column meant a lot of scrolling for not much payoff at this narrow a
-- width. Status is shown via the icon's border color (no room for inline text at this width)
-- plus a tooltip naming the item and its status on hover; a depleting bar directly under each
-- icon is its own per-item countdown visual (see docs/SPECIFICATION.md's bagged-item workflow
-- notes for the Awarded > Pre-awarded > Expired > Pending status priority).
local ICON_SIZE = 28
local ICON_GAP = 2 -- between the two icon columns -- kept tight on purpose, see user feedback
local BAR_GAP = 1
local BAR_HEIGHT = 3
local ICON_CELL_HEIGHT = ICON_SIZE + BAR_GAP + BAR_HEIGHT
-- No added slack -- DataTable centers each cell vertically within its row (see
-- UI/Widgets/DataTable.lua:Layout's `cell:SetPoint("LEFT", row, "LEFT", x, 0)`), so a row any
-- taller than the cell itself shows up as unwanted top/bottom padding on every icon.
local ICON_ROW_HEIGHT = ICON_CELL_HEIGHT
-- Just the two icon columns -- no scrollbar width baked in here anymore (see ensureFrame below,
-- where the scrollbar now lives in the existing sidebar/detail-area gap instead of eating into
-- the icons' own width and showing up as blank padding after them).
local ICON_SIDEBAR_WIDTH = ICON_SIZE * 2 + ICON_GAP

-- Recomputes just the depleting bar from whatever update() last stashed on the holder
-- (holder.deadlineAt/holder.awardedState) -- factored out so it can run both from update() (for
-- immediate correctness whenever the underlying data actually changes) and from a per-frame
-- OnUpdate (see iconColumn below) for smooth continuous motion in between. Driving the bar purely
-- from the once-a-second ticker made it visibly step/jump instead of sliding.
local function applyIconTimerVisual(holder)
	if holder.awardedState or not holder.deadlineAt or time() >= holder.deadlineAt then
		holder.timerTrack:Hide()
		holder.timerBar:Hide()
		return
	end
	local remaining = holder.deadlineAt - time()
	local total = math.max(1, PLC.Session.responseTimeoutSeconds)
	local colorName = remaining <= 10 and "warning" or "accent"
	local r, g, b = Primitives.color(colorName)
	holder.timerTrack:Show()
	holder.timerBar:Show()
	holder.timerBar:SetWidth(math.max(0.5, ICON_SIZE * math.min(1, remaining / total)))
	holder.timerBar:SetColorTexture(r, g, b, 1)
end

-- Each DataTable row holds up to two items (see pairItemRows below) -- `suffix` ("1"/"2") picks
-- which half of the row this particular column reads/writes, so the same builder serves both
-- columns. Each icon is its own clickable Button (not a generic DataTable row click, which only
-- ever gets ONE data item per row) with its own hover tooltip and selection highlight.
local function iconColumn(suffix)
	return {
		width = suffix == "1" and (ICON_SIZE + ICON_GAP) or ICON_SIZE,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Button", nil, row)
			holder:SetSize(ICON_SIZE, ICON_CELL_HEIGHT)

			holder.iconFrame = CreateFrame("Frame", nil, holder)
			holder.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
			-- TOPLEFT, not TOP -- column 1's holder is ICON_GAP wider than the icon itself (the
			-- gap reserved between the two columns), and centering would have split that gap
			-- evenly on both sides of the icon instead of putting all of it on the right, between
			-- the two icons, which read as an unwanted left-edge padding on every single icon.
			holder.iconFrame:SetPoint("TOPLEFT")

			holder.texture = holder.iconFrame:CreateTexture(nil, "ARTWORK")
			holder.texture:SetPoint("TOPLEFT", 1, -1)
			holder.texture:SetPoint("BOTTOMRIGHT", -1, 1)
			holder.border = Primitives.createBorder(holder.iconFrame)

			holder.selectionGlow = Primitives.createTexture(holder.iconFrame, "OVERLAY", "accent", 0.35)
			holder.selectionGlow:SetAllPoints()
			holder.selectionGlow:Hide()

			-- Depleting bar directly beneath the icon -- a full-strength colored fill on its own
			-- small track reads far more clearly at a glance than a faint tint behind an icon that
			-- already covers almost the entire cell (the previous row-background approach).
			holder.timerTrack = Primitives.createTexture(holder, "BACKGROUND", "scroll")
			holder.timerTrack:SetPoint("TOPLEFT", holder.iconFrame, "BOTTOMLEFT", 0, -BAR_GAP)
			holder.timerTrack:SetSize(ICON_SIZE, BAR_HEIGHT)
			holder.timerTrack:Hide()

			holder.timerBar = holder:CreateTexture(nil, "ARTWORK")
			holder.timerBar:SetPoint("TOPLEFT", holder.timerTrack, "TOPLEFT")
			holder.timerBar:SetHeight(BAR_HEIGHT)
			holder.timerBar:Hide()

			-- Only a Frame/Button can run OnUpdate (plain Texture regions can't -- there's no
			-- `texture:SetScript`), which is why this lives on `holder` itself rather than on the
			-- bar texture directly. WoW already skips OnUpdate for hidden frames, so this costs
			-- nothing while the row is scrolled out of view.
			holder:SetScript("OnUpdate", function()
				applyIconTimerVisual(holder)
			end)

			holder:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(holder.tooltipName or "?")
				if holder.tooltipStatus then
					GameTooltip:AddLine(holder.tooltipStatus, 1, 1, 1)
				end
				if holder.tooltipRemaining then
					GameTooltip:AddLine(holder.tooltipRemaining, 0.6, 0.6, 0.6)
				end
				GameTooltip:Show()
			end)
			holder:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			holder:SetScript("OnClick", function()
				if holder.itemIdx then
					showDetailFor(holder.itemIdx)
					if dataTable then
						dataTable:Refresh()
					end
				end
			end)

			return holder
		end,
		update = function(holder, rowData)
			local idx = rowData["idx" .. suffix]
			holder.itemIdx = idx
			if not idx then
				holder:Hide()
				return
			end
			holder:Show()

			local link = rowData["link" .. suffix]
			local icon = rowData["icon" .. suffix]
			local awarded = rowData["awarded" .. suffix]
			local preAwardGuid = rowData["preAwardGuid" .. suffix]
			local deadlineAt = rowData["deadlineAt" .. suffix]

			holder.texture:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			holder.tooltipName = link or "?"
			holder.selectionGlow:SetShown(selectedIdx == idx)

			local borderColor
			holder.tooltipRemaining = nil
			if awarded then
				local entry = PLC.Roster:Get(awarded)
				holder.tooltipStatus = string.format(L["SESSIONFRAME_AWARDED_TO"], PLC.Roster:ShortName(entry and entry.name) or "?")
				-- Green, not the dim gray this used to be -- that was nearly indistinguishable
				-- from a plain pending icon, so clicking Award looked like it did nothing (the
				-- auto-advance to the next pending item made it worse, since the view moves away
				-- immediately). Distinct from the accent/orange "Staged" pre-award color on
				-- purpose -- Awarded is final, Pre-Award isn't.
				borderColor = "success"
			elseif preAwardGuid then
				local entry = PLC.Roster:Get(preAwardGuid)
				holder.tooltipStatus = string.format(L["SESSIONFRAME_PREAWARDED_TO"], PLC.Roster:ShortName(entry and entry.name) or "?")
				borderColor = "accent"
			elseif deadlineAt and time() > deadlineAt then
				holder.tooltipStatus = L["SESSIONFRAME_EXPIRED"]
				borderColor = "warning"
			else
				holder.tooltipStatus = L["SESSIONFRAME_PENDING"]
				borderColor = "border"
			end
			Primitives.setBorderColor(holder.border, borderColor)

			-- Not just an "expired" check -- awarded/pre-awarded items keep their own deadline in
			-- the background too (CollectDetectedItems/AddManualItem never clear it just because a
			-- decision was staged), so the bar/tooltip line only show while still actually counting
			-- down for someone to respond to.
			holder.deadlineAt = deadlineAt
			holder.awardedState = awarded
			if not awarded and deadlineAt and time() < deadlineAt then
				holder.tooltipRemaining = string.format(L["SESSIONFRAME_TIME_LEFT"], math.ceil(deadlineAt - time()))
			end
			applyIconTimerVisual(holder)
		end,
	}
end

local ICON_COLUMNS = { iconColumn("1"), iconColumn("2") }

local function flatItemRows()
	local rows = {}
	for idx, item in pairs(PLC.Session.items) do
		table.insert(rows, {
			idx = idx,
			link = item.link,
			icon = item.icon,
			awarded = item.awarded,
			preAwardGuid = item.preAwardGuid,
			deadlineAt = item.deadlineAt,
		})
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

-- Packs the flat, sorted item list into the two-icons-per-row shape ICON_COLUMNS expects --
-- row.idx2/link2/etc. are simply absent (not nil-filled) for a trailing odd item out, which
-- iconColumn's update() reads as "nothing in this cell" and hides it.
local function pairItemRows(flat)
	local rows = {}
	for i = 1, #flat, 2 do
		local a, b = flat[i], flat[i + 1]
		local row = {
			idx1 = a.idx, link1 = a.link, icon1 = a.icon,
			awarded1 = a.awarded, preAwardGuid1 = a.preAwardGuid, deadlineAt1 = a.deadlineAt,
		}
		if b then
			row.idx2, row.link2, row.icon2 = b.idx, b.link, b.icon
			row.awarded2, row.preAwardGuid2, row.deadlineAt2 = b.awarded, b.preAwardGuid, b.deadlineAt
		end
		table.insert(rows, row)
	end
	return rows
end

local function firstPendingIdx(rows)
	for _, row in ipairs(rows) do
		if not row.awarded then
			return row.idx
		end
	end
	return nil
end

-- Session:RemoveItem already triggers notifySessionFrame -> OnSessionUpdated -> refresh() on
-- success, but stays silent on its (defensive, shouldn't-happen-given-the-button's-own-visibility-
-- rule) no-op paths -- the explicit refresh() call after this keeps selectedIdx consistent with
-- reality either way, not just in the success case.
local function onRemoveClick()
	if not selectedIdx then
		return
	end
	PLC.Session:RemoveItem(selectedIdx)
	selectedIdx = nil
	refresh()
end

function showDetailFor(idx)
	selectedIdx = idx
	local item = idx and PLC.Session.items[idx]
	if item then
		detailItemLabel:SetText(item.link or "?")
		detailRemoveButton:SetShown(PLC.Session.state ~= "active" and not item.awarded)
		detailContainer:Show()
		votingPanel:ShowItem(idx)
	else
		detailItemLabel:SetText(L["SESSIONFRAME_NO_ITEMS"])
		detailRemoveButton:Hide()
		detailContainer:Hide()
	end
end

local function updateButtons()
	if PLC.Session.state == "active" then
		startButton:Hide()
		endButton:Show()
		awardAllButton:Show()
	else
		startButton:Show()
		endButton:Hide()
		awardAllButton:Hide()
	end
end

-- Shows who holds the current review pass directly in the window's own title bar (previously
-- only a one-time chat line on session start, easy to miss/scroll past) -- hidden entirely
-- outside an active session, since there's no "holder" otherwise.
local function updateHeaderOwner()
	if not header then
		return
	end
	if PLC.Session.state == "active" and PLC.Session.owner then
		header.ownerLabel:SetText(string.format(L["SESSIONFRAME_STARTED_BY"], PLC.Roster:ShortName(PLC.Session.owner.name) or "?"))
		header.ownerLabel:Show()
	else
		header.ownerLabel:Hide()
	end
end

-- Rebuilds the icon list, keeps/advances the selection, and updates the bottom button row --
-- called whenever the frame is (re)shown, after Start()/End()/Award All/Remove, and from
-- Session's notifySessionFrame forward-hook whenever the item set or an award/pre-award changes
-- while this window is open. Assigns to the forward-declared local above (not `local function`
-- again here) since onRemoveClick, defined earlier in the file, already calls it.
function refresh()
	if not dataTable then
		return
	end

	local flat = flatItemRows()

	-- Auto-selects the first not-yet-awarded item, and auto-advances off whatever was selected
	-- once it gets awarded -- never auto-advances AWAY from an item the user deliberately picked
	-- while it's still pending. Resolved before SetRows below, since icon cells read `selectedIdx`
	-- directly (a closed-over upvalue, not a parameter) while rendering.
	if not selectedIdx or (PLC.Session.items[selectedIdx] and PLC.Session.items[selectedIdx].awarded) then
		selectedIdx = firstPendingIdx(flat)
	end

	dataTable:SetRows(pairItemRows(flat))
	showDetailFor(selectedIdx)

	updateButtons()
	updateHeaderOwner()

	if hasLiveCountdown(flat) then
		startTicker()
	else
		stopTicker()
	end
end

local function onStartClick()
	PLC.Session:Start()
	refresh()
end

local function onEndClick()
	PLC.Session:End()
	refresh()
end

local function onAwardAllClick()
	PLC.Session:AwardAllPreAwarded()
	refresh()
end

local function ensureFrame()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "PixlLootCouncilSessionFrame", UIParent)
	frame:SetSize(640, 500)
	frame:SetPoint("CENTER", 0, 50)
	-- Deliberately stays at "DIALOG" -- the middle of the three main windows: UI/OptionsFrame.lua
	-- (built on UI/Widgets/PanelLayout.lua) sits one tier below at "HIGH", UI/LootFrame.lua sits
	-- one tier above at "FULLSCREEN_DIALOG", so responding to loot is always reachable regardless
	-- of which window was clicked/opened more recently.
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilSessionFrame")
	Primitives.makeResizable(frame, 520, 360, 900, 800)
	-- Covers every way the window can close -- the header's own close button, Escape (via
	-- UISpecialFrames), or a future caller just calling frame:Hide() directly -- without needing
	-- to duplicate stopTicker() at each of those call sites.
	frame:SetScript("OnHide", function()
		stopTicker()
	end)

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

	header.title = Primitives.createText(header, L["SESSIONFRAME_TITLE"], 14, "title")
	header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, 0)

	header.ownerLabel = Primitives.createText(header, "", 11, "dim")
	header.ownerLabel:SetPoint("LEFT", header.title, "RIGHT", 10, 0)
	header.ownerLabel:Hide()

	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		frame:Hide()
	end)

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	startButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_START"], 160)
	startButton:SetPoint("BOTTOM", 0, 12)
	startButton:SetScript("OnClick", onStartClick)

	endButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_END"], 140)
	endButton:SetPoint("BOTTOM", 90, 12)
	endButton:SetScript("OnClick", onEndClick)

	awardAllButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_AWARDALL"], 140)
	awardAllButton:SetPoint("BOTTOM", -90, 12)
	awardAllButton:SetScript("OnClick", onAwardAllClick)

	-- Anchored to frame's actual corners, not a button's position -- see git history for why
	-- this matters (a prior version anchored to a centered button's TOPRIGHT and silently
	-- clipped everything past ~half the window's real width). Left inset trimmed down from the
	-- detail area's -- the icon sidebar reads better flush-ish against the window's edge.
	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 6, -10)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 50)

	itemListContainer = CreateFrame("Frame", nil, content)
	itemListContainer:SetPoint("TOPLEFT", content, "TOPLEFT")
	itemListContainer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT")
	itemListContainer:SetWidth(ICON_SIDEBAR_WIDTH)

	dataTable = DataTable.Create(itemListContainer, ICON_ROW_HEIGHT)
	-- Flush on every edge -- no reserved scrollbar gutter inside itemListContainer anymore (that
	-- showed up as dead space to the right of the icons). UI/Widgets/ScrollFrame.lua's scrollbar
	-- draws 10-17px to the right of the scroll frame's own right edge, which now lands in the
	-- existing gap between the sidebar and the detail area (widened below) instead.
	dataTable.scroll:SetAllPoints()
	dataTable:SetColumns(ICON_COLUMNS)

	local divider = Primitives.createTexture(content, "ARTWORK", "borderDim")
	divider:SetPoint("TOPLEFT", itemListContainer, "TOPRIGHT")
	divider:SetPoint("BOTTOMLEFT", itemListContainer, "BOTTOMRIGHT")
	divider:SetWidth(1)

	detailArea = CreateFrame("Frame", nil, content)
	-- Widened from the detail area's old flat 8px gap -- it now also has to fit the sidebar's
	-- scrollbar (see dataTable.scroll above), which draws past itemListContainer's own edge.
	detailArea:SetPoint("TOPLEFT", itemListContainer, "TOPRIGHT", 20, 0)
	detailArea:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")

	detailItemLabel = Primitives.createText(detailArea, "", 13, "white")
	detailItemLabel:SetPoint("TOPLEFT")
	detailItemLabel:SetPoint("RIGHT", detailArea, "RIGHT", -80, 0)
	detailItemLabel:SetJustifyH("LEFT")

	-- Only ever meaningful pre-Start()/post-End() for a not-yet-awarded item -- there's no wire
	-- command to retract an item once it's been broadcast (Session:RemoveItem enforces the same
	-- rule independently); showDetailFor keeps this hidden the rest of the time.
	detailRemoveButton = ButtonWidget.createButton(detailArea, L["SESSIONFRAME_REMOVE"], 70)
	detailRemoveButton:SetPoint("TOPRIGHT")
	detailRemoveButton:SetScript("OnClick", onRemoveClick)

	Primitives.createSeparator(detailArea, -28)

	detailContainer = CreateFrame("Frame", nil, detailArea)
	detailContainer:SetPoint("TOPLEFT", 0, -36)
	detailContainer:SetPoint("BOTTOMRIGHT")

	votingPanel = PLC.UI.VotingFrame.CreatePanel(detailContainer)

	frame:Hide()
	return frame
end

-- Forward-hook target from Data/Session.lua whenever the item set or an award/pre-award status
-- changes -- only does anything while this window is actually open, same guard style as every
-- other UI forward-hook in this codebase.
function SessionFrame:OnSessionUpdated()
	if not frame or not frame:IsShown() then
		return
	end
	refresh()
end

-- Manual open -- there's no automatic popup on loot anymore (collection is deliberately silent
-- across the whole raid, see Loot/Detection.lua); any council member, not just the live ML, can
-- use this to check progress or reach the controls for a session already running.
PLC:RegisterSlashCommand("sessionframe", "Open the loot session window", function()
	local f = ensureFrame()
	refresh()
	f:Show()
end)

-- Debug seed: adds a real item -- Hearthstone (itemID 6948), always cached client-side since
-- every character starts with one, so C_Item.GetItemInfo resolves it instantly -- via the same
-- Session:AddManualItem path /plc additem uses, so the layout's scrolling/selection/row-
-- recycling can be exercised solo with real resolved item data (name/icon/link), not a
-- hand-typed placeholder string. See docs/TESTING.md.
PLC:RegisterSlashCommand("testdata", "Debug: seed a real test item and open the session window", function()
	PLC.Session:AddManualItem(6948)

	local f = ensureFrame()
	refresh()
	f:Show()
end)
