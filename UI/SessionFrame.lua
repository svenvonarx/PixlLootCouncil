local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DropdownWidget = PLC.UI.Widgets.Dropdown
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- The single ML-facing window (header+content, no PanelLayout sidebar-nav -- spec §4.3, this is
-- a different kind of sidebar, see below): master-detail, RCLootCouncil-style -- a narrow
-- left-hand strip of item icons (status shown via border color + a tooltip, no room for inline
-- text at this width), click one to load its full candidate/response/Award grid
-- (UI/VotingFrame.lua, embedded, not its own window) into the content area on the right. A
-- session-wide Enchanter picker (who disenchanted items get staged to) sits in its own toolbar
-- row between the header and this master-detail area -- see ensureFrame's enchanterRow.
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
local enchanterRow
local enchanterDropdown
local content
local itemListContainer
local dataTable
local detailArea
local detailItemLabel
local detailItemHover
local detailRemoveButton
local detailVoteCountText
local detailDisenchantButton
local detailContainer
local detailNotice
local votingPanel
local startButton
local endButton
local awardAllButton
local removeAllButton
local selectedIdx -- which session item's response grid is currently shown in the detail area
local refresh -- forward-declared: onRemoveClick (defined before it) calls it
local showDetailFor -- forward-declared: iconColumn's OnClick (defined before it) calls it
local tickerHandle

-- Item name plus its trade status ("Tradable for 1h 52m", Loot/BagTracker.lua) in the detail header.
local function setDetailLabel(item)
	local tradeText, tradeColor = PLC.Loot.BagTracker:StatusText(item)
	if tradeText then
		local r, g, b = Primitives.color(tradeColor)
		detailItemLabel:SetText(string.format("%s  |cff%02x%02x%02x%s|r", item.link or "?",
			math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), tradeText))
	else
		detailItemLabel:SetText(item.link or "?")
	end
end

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
		local item = selectedIdx and PLC.Session.items[selectedIdx]
		if item and detailItemLabel then
			setDetailLabel(item)
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
		-- Trade-window timers (Loot/BagTracker.lua) count down too.
		local item = PLC.Session.items[row.idx]
		if item and item.tradeExpiresAt and now < item.tradeExpiresAt then
			return true
		end
	end
	return false
end

-- Remaining trade time on an icon: "1h 52m" / "45m" (colored by urgency), "BoE", or "exp".
local function applyTradeBadge(holder, item)
	local BagTracker = PLC.Loot.BagTracker
	local left = BagTracker:SecondsLeft(item)
	if left == 0 then
		holder.tradeBadge:SetText(L["TRADETIME_SHORT_EXPIRED"])
		holder.tradeBadge:SetTextColor(Primitives.color("warning", 1))
	elseif left then
		local text = left >= 3600 and string.format("%dh", math.floor(left / 3600)) or BagTracker.FormatShort(left)
		holder.tradeBadge:SetText(text)
		holder.tradeBadge:SetTextColor(Primitives.color(BagTracker.ColorFor(left)))
	elseif item and item.boe then
		holder.tradeBadge:SetText(L["TRADETIME_SHORT_BOE"])
		holder.tradeBadge:SetTextColor(Primitives.color("dim"))
	else
		holder.tradeBadge:SetText("")
	end
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
-- The two icon columns, plus UI/Widgets/ScrollFrame.lua's own reserved strip for the scrollbar
-- (it carves that out of whatever width it's given, rather than needing extra room outside it --
-- see ScrollFrame.lua for why), so the icon columns still get their full width and the scrollbar
-- still fits, both within this one container.
local ICON_SIDEBAR_WIDTH = ICON_SIZE * 2 + ICON_GAP + PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH

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

			-- Remaining trade time, bottom-right on the icon (see applyTradeBadge). Its own frame
			-- level above the icon so the text draws over the texture.
			local badgeFrame = CreateFrame("Frame", nil, holder.iconFrame)
			badgeFrame:SetAllPoints()
			badgeFrame:SetFrameLevel(holder.iconFrame:GetFrameLevel() + 2)
			holder.tradeBadge = Primitives.createText(badgeFrame, "", 10)
			holder.tradeBadge:SetPoint("BOTTOMRIGHT", -1, 1)
			holder.tradeBadge:SetShadowColor(0, 0, 0, 1)
			holder.tradeBadge:SetShadowOffset(1, -1)

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
				local item = holder.itemIdx and PLC.Session.items[holder.itemIdx]
				local tradeText, tradeColor = PLC.Loot.BagTracker:StatusText(item)
				if tradeText then
					local r, g, b = Primitives.color(tradeColor)
					GameTooltip:AddLine(tradeText, r, g, b)
				end
				-- Who already received this item (UI/HistoryFrame.lua).
				PLC.UI.HistoryFrame.AddItemLines(GameTooltip, item and item.link)
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
			local awardReason = rowData["awardReason" .. suffix]
			local preAwardGuid = rowData["preAwardGuid" .. suffix]
			local preAwardReason = rowData["preAwardReason" .. suffix]
			local deadlineAt = rowData["deadlineAt" .. suffix]

			holder.texture:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			holder.tooltipName = link or "?"
			holder.selectionGlow:SetShown(selectedIdx == idx)

			local borderColor
			holder.tooltipRemaining = nil
			if awarded then
				if awardReason == "disenchant" then
					holder.tooltipStatus = L["SESSIONFRAME_DISENCHANTED"]
				else
					local entry = PLC.Roster:Get(awarded)
					holder.tooltipStatus = string.format(L["SESSIONFRAME_AWARDED_TO"], PLC.Roster:ShortName(entry and entry.name) or "?")
				end
				-- Green, not the dim gray this used to be -- that was nearly indistinguishable
				-- from a plain pending icon, so clicking Award looked like it did nothing (the
				-- auto-advance to the next pending item made it worse, since the view moves away
				-- immediately). Distinct from the accent/orange "Staged" pre-award color on
				-- purpose -- Awarded is final, staged isn't. Disenchant isn't a third visual
				-- state, just different tooltip wording on these same two border colors.
				borderColor = "success"
			elseif preAwardGuid then
				if preAwardReason == "disenchant" then
					local entry = PLC.Roster:Get(preAwardGuid)
					holder.tooltipStatus = string.format(L["SESSIONFRAME_STAGED_DISENCHANT"], PLC.Roster:ShortName(entry and entry.name) or "?")
				else
					local entry = PLC.Roster:Get(preAwardGuid)
					holder.tooltipStatus = string.format(L["SESSIONFRAME_PREAWARDED_TO"], PLC.Roster:ShortName(entry and entry.name) or "?")
				end
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
			local item = PLC.Session.items[idx]
			applyTradeBadge(holder, item)
			if item and (item.untradable or PLC.Loot.BagTracker:SecondsLeft(item) == 0) and not awarded then
				Primitives.setBorderColor(holder.border, "warning")
			end

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
		-- Awarded items stay in Session.items until traded (so UI/TradeFrame.lua can track them),
		-- but they're never shown here -- otherwise they'd reappear in the next review pass.
		if not item.awarded then
			table.insert(rows, {
				idx = idx,
				link = item.link,
				icon = item.icon,
				awarded = item.awarded,
				awardReason = item.awardReason,
				preAwardGuid = item.preAwardGuid,
				preAwardReason = item.preAwardReason,
				deadlineAt = item.deadlineAt,
			})
		end
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
			awarded1 = a.awarded, awardReason1 = a.awardReason,
			preAwardGuid1 = a.preAwardGuid, preAwardReason1 = a.preAwardReason,
			deadlineAt1 = a.deadlineAt,
		}
		if b then
			row.idx2, row.link2, row.icon2 = b.idx, b.link, b.icon
			row.awarded2, row.awardReason2 = b.awarded, b.awardReason
			row.preAwardGuid2, row.preAwardReason2 = b.preAwardGuid, b.preAwardReason
			row.deadlineAt2 = b.deadlineAt
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

-- Remove and Disenchant+vote-count share the same top-right slot (see ensureFrame) rather than
-- needing separate rows -- they're never both meaningful at once: Remove only applies outside an
-- active review (Session:IsHolder() itself requires state == "active", so Session:SetPreAward/
-- SetEnchanter are no-ops the whole time Remove would be shown anyway), so showing one always
-- means hiding the other, never both or neither.
function showDetailFor(idx)
	selectedIdx = idx
	local item = idx and PLC.Session.items[idx]
	-- Only the council sees the voting grid (responses, staged picks); only the holder gets the
	-- controls (Disenchant here, Award in the grid -- see UI/VotingFrame.lua). Everyone else sees
	-- the item list and a short notice.
	local isCouncil = PLC.Session:IsCouncilMember() or PLC.Session:IsHolder()
	detailNotice:SetShown(item ~= nil and not isCouncil)
	if item and not isCouncil then
		setDetailLabel(item)
		detailItemHover.itemLink = item.link
		detailRemoveButton:Hide()
		detailDisenchantButton:Hide()
		detailVoteCountText:Hide()
		detailContainer:Hide()
	elseif item then
		setDetailLabel(item)
		detailItemHover.itemLink = item.link
		local active = PLC.Session.state == "active"
		detailRemoveButton:SetShown(not active and not item.awarded and PLC.Session:CanManage())
		detailDisenchantButton:SetShown(active and PLC.Session:IsHolder())
		detailVoteCountText:SetShown(active)
		detailContainer:Show()
		votingPanel:ShowItem(idx)
	else
		detailItemLabel:SetText(L["SESSIONFRAME_NO_ITEMS"])
		detailItemHover.itemLink = nil
		detailRemoveButton:Hide()
		detailDisenchantButton:Hide()
		detailVoteCountText:Hide()
		detailContainer:Hide()
	end
end

-- Start: whoever may start a review pass (the master looter -- Session:CanStart). End / Award
-- All: only the holder of the running session. Remove All: whoever manages the item list.
local function updateButtons(flat)
	local isHolder = PLC.Session:IsHolder()
	startButton:SetShown(PLC.Session.state ~= "active" and PLC.Session:CanStart())
	endButton:SetShown(isHolder)
	awardAllButton:SetShown(isHolder)
	removeAllButton:SetShown(#flat > 0 and PLC.Session:CanManage())
end

-- Shows who holds the current review pass directly in the window's own title bar (previously
-- only a one-time chat line on session start, easy to miss/scroll past) -- hidden entirely
-- outside an active session, since there's no "holder" otherwise.
local function updateHeaderOwner()
	if not header then
		return
	end
	if PLC.Session.state == "active" and PLC.Session.owner then
		header.ownerLabel:SetText(string.format(L["STARTED_BY_LABEL"], PLC.Roster:ShortName(PLC.Session.owner.name) or "?"))
		header.ownerLabel:Show()
	else
		header.ownerLabel:Hide()
	end
end

-- Rebuilds the Enchanter dropdown's display text + entry list -- called from refresh() so it
-- stays live across roster changes, profession syncs, and holder picks alike. Hard-filtered to
-- roster members Data/Professions.lua currently shows as actually having Enchanting trained --
-- NOT "everyone, with enchanters just highlighted green" like an earlier round of this had it.
-- That softer version is exactly what let a non-enchanter get picked (by the alphabetical default,
-- or by a holder clicking the wrong name in a long list) in the first place; hard-filtering closes
-- it at the source instead of trying to make the wrong option merely less likely. Entries are
-- sorted alphabetically by short name (PLC.Roster:ShortName), `checked` (not `selected` -- see
-- UI/Widgets/PopupMenu.lua's Render, which only ever reads `checked` for its checkmark) matches
-- Session:GetEnchanterGuid()'s current pick. When the list is empty (nobody's Enchanting has
-- synced yet) the dropdown shows a placeholder and opens to an empty popup rather than silently
-- falling back to someone without Enchanting.
local function updateEnchanterDropdown()
	if not enchanterDropdown then
		return
	end
	local list = {}
	for guid, entry in PLC.Roster:IterateGroup() do
		if PLC.Professions:HasProfession(guid, PLC.Professions.ENCHANTING_KEY) then
			table.insert(list, { guid = guid, name = PLC.Roster:ShortName(entry.name) })
		end
	end
	table.sort(list, function(a, b) return a.name < b.name end)

	local currentGuid = PLC.Session:GetEnchanterGuid()
	local displayText = L["SESSIONFRAME_NO_ENCHANTER"]
	local entries = {}
	for _, candidate in ipairs(list) do
		local checked = candidate.guid == currentGuid
		if checked then
			displayText = candidate.name
		end
		table.insert(entries, {
			text = candidate.name,
			checked = checked,
			onClick = function()
				PLC.Session:SetEnchanter(candidate.guid)
			end,
		})
	end
	-- Read-only for everyone but the holder (Session:SetEnchanter is holder-only anyway).
	local canEdit = PLC.Session:IsHolder()
	DropdownWidget.setEntries(enchanterDropdown, displayText, canEdit and entries or nil)
	enchanterDropdown:EnableMouse(canEdit)
	enchanterDropdown.arrow:SetShown(canEdit)
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

	updateButtons(flat)
	updateHeaderOwner()
	updateEnchanterDropdown()

	if hasLiveCountdown(flat) then
		startTicker()
	else
		stopTicker()
	end
end

-- Exposed for UI/VotingFrame.lua's Award/Disenchant buttons -- both only ever stage a pick
-- (Session:SetPreAward), never commit directly, then call this to move the sidebar on to the
-- next item automatically. Walks the same flat, index-sorted list refresh() builds; a staged-but-
-- not-yet-final item is still a valid stop (that's the whole point of the stage-everything flow)
-- -- only a truly finished (awarded) item is skipped. No-ops at the end of the list (stays put
-- rather than wrapping or clearing the selection) -- the holder presses Award All from there.
function SessionFrame:AdvanceToNextItem()
	if not dataTable then
		return
	end
	local flat = flatItemRows()
	local currentPos
	for i, row in ipairs(flat) do
		if row.idx == selectedIdx then
			currentPos = i
			break
		end
	end
	if not currentPos then
		return
	end
	for i = currentPos + 1, #flat do
		if not flat[i].awarded then
			selectedIdx = flat[i].idx
			refresh()
			return
		end
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

StaticPopupDialogs["PIXLLOOTCOUNCIL_REMOVE_ALL"] = {
	text = L["SESSIONFRAME_REMOVE_ALL_CONFIRM"],
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		PLC.Session:RemoveAllItems()
		refresh()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function onRemoveAllClick()
	local count = #flatItemRows()
	if count > 0 then
		StaticPopup_Show("PIXLLOOTCOUNCIL_REMOVE_ALL", count)
	end
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
	Primitives.refreshFontsOnShow(frame)
	-- Width is fixed (set at the very end of this function, once VotingFrame.GRID_WIDTH is known
	-- -- see the comment down there) but every child below positions itself via relative anchors,
	-- not absolute pixel coordinates, so building them before the frame has a final size is fine;
	-- WoW only resolves actual pixel positions at render time, well after ensureFrame() returns.
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

	-- Bigger than before, and centered on the logo same as always. The subtitle below is already
	-- at Primitives.createText's hard minimum render size (11 floors to the same 9px as a
	-- smaller value would -- there's no more room to shrink it), so widening the gap to make it
	-- read as "smaller in comparison" means growing the title instead.
	header.title = Primitives.createText(header, L["SESSIONFRAME_TITLE"], 18, "title")
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

	-- New toolbar row for the Enchanter picker, between the header and the icon-sidebar+detail
	-- content area -- not inside `content` itself, since it's a session-wide setting rather than
	-- part of the per-item master-detail layout below it.
	enchanterRow = CreateFrame("Frame", nil, frame)
	enchanterRow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -8)
	enchanterRow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -10, -8)
	enchanterRow:SetHeight(Theme.LAYOUT.fieldHeight)

	enchanterRow.label = Primitives.createText(enchanterRow, L["SESSIONFRAME_ENCHANTER_LABEL"], 12, "white")
	enchanterRow.label:SetPoint("LEFT")

	-- Resized down from Dropdown.createDropdownButton's 260px default -- this window's width is
	-- derived from the detail grid below (see the end of this function) and isn't wide enough to
	-- spare for a full-size dropdown on top of the sidebar/grid it already has to fit.
	enchanterDropdown = DropdownWidget.createDropdownButton(enchanterRow)
	enchanterDropdown:SetSize(180, Theme.LAYOUT.fieldHeight)
	enchanterDropdown:SetPoint("LEFT", enchanterRow.label, "RIGHT", 8, 0)

	-- Shortcuts to every other window, right-aligned in the same toolbar row (built right to left).
	-- Each window's own Open() prints a short note instead when there's nothing to show. Fixed
	-- widths, not label-sized: on a cold start the font may not be loaded yet when this is built, so
	-- measuring the label would come out too narrow (see Primitives.RefreshFonts).
	local shortcuts = {
		{ L["SESSIONFRAME_OPEN_OPTIONS"], 66, function() PLC.UI.OptionsFrame:Open() end },
		{ L["SESSIONFRAME_OPEN_HISTORY"], 66, function() PLC.UI.HistoryFrame:Open() end },
		{ L["SESSIONFRAME_OPEN_TRADES"], 62, function() PLC.UI.TradeFrame:OpenOrNotify() end },
		{ L["SESSIONFRAME_OPEN_LOOT"], 50, function() PLC.UI.LootFrame:Open() end },
	}
	local anchor
	for _, shortcut in ipairs(shortcuts) do
		local button = ButtonWidget.createButton(enchanterRow, shortcut[1], shortcut[2])
		button:SetHeight(Theme.LAYOUT.fieldHeight)
		if anchor then
			button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
		else
			button:SetPoint("RIGHT")
		end
		button:SetScript("OnClick", shortcut[3])
		anchor = button
	end

	startButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_START"], 160)
	startButton:SetPoint("BOTTOM", 0, 12)
	startButton:SetScript("OnClick", onStartClick)

	endButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_END"], 140)
	endButton:SetPoint("BOTTOM", 90, 12)
	endButton:SetScript("OnClick", onEndClick)

	awardAllButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_AWARDALL"], 140)
	awardAllButton:SetPoint("BOTTOM", -90, 12)
	awardAllButton:SetScript("OnClick", onAwardAllClick)

	-- Bottom-left, away from the main actions: clears every not-yet-awarded item (confirmed first).
	removeAllButton = ButtonWidget.createButton(frame, L["SESSIONFRAME_REMOVE_ALL"], 100)
	removeAllButton:SetPoint("BOTTOMLEFT", 10, 12)
	removeAllButton:SetScript("OnClick", onRemoveAllClick)

	-- Anchored to frame's actual corners, not a button's position -- see git history for why
	-- this matters (a prior version anchored to a centered button's TOPRIGHT and silently
	-- clipped everything past ~half the window's real width). Left inset trimmed down from the
	-- detail area's -- the icon sidebar reads better flush-ish against the window's edge.
	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", enchanterRow, "BOTTOMLEFT", -4, -10)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 50)

	itemListContainer = CreateFrame("Frame", nil, content)
	itemListContainer:SetPoint("TOPLEFT", content, "TOPLEFT")
	itemListContainer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT")
	itemListContainer:SetWidth(ICON_SIDEBAR_WIDTH)

	-- No scroll:SetAllPoints() here -- UI/Widgets/ScrollFrame.lua anchors it to itemListContainer
	-- itself now, reserving its own room for the scrollbar inside that (see ICON_SIDEBAR_WIDTH
	-- above), so the icon columns and the scrollbar both fit within the sidebar's own bounds.
	dataTable = DataTable.Create(itemListContainer, ICON_ROW_HEIGHT)
	dataTable:SetColumns(ICON_COLUMNS)

	local divider = Primitives.createTexture(content, "ARTWORK", "borderDim")
	divider:SetPoint("TOPLEFT", itemListContainer, "TOPRIGHT")
	divider:SetPoint("BOTTOMLEFT", itemListContainer, "BOTTOMRIGHT")
	divider:SetWidth(1)

	detailArea = CreateFrame("Frame", nil, content)
	detailArea:SetPoint("TOPLEFT", itemListContainer, "TOPRIGHT", 8, 0)
	detailArea:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")

	-- One compact header bar: item name (left) and, sharing the same top-right slot (see
	-- showDetailFor), either the Remove button (outside an active review) or the vote count +
	-- Disenchant button (during one) -- previously two stacked rows (item name+Remove, then the
	-- embedded panel's own "N of M voted"+Disenchant row below a second separator), which ate
	-- extra vertical space for no reason once Disenchant existed. Both buttons' final TOPRIGHT
	-- anchor is set further below, once VotingFrame.GRID_WIDTH is known (set by CreatePanel) --
	-- they line up with the embedded grid's own right edge, not detailArea's full width, which is
	-- wider than the grid's fixed-width columns actually fill (see frame:SetSize's width comment).

	-- Only ever meaningful pre-Start()/post-End() for a not-yet-awarded item -- there's no wire
	-- command to retract an item once it's been broadcast (Session:RemoveItem enforces the same
	-- rule independently); showDetailFor keeps this hidden the rest of the time.
	detailRemoveButton = ButtonWidget.createButton(detailArea, L["SESSIONFRAME_REMOVE"], 70)
	detailRemoveButton:SetScript("OnClick", onRemoveClick)

	-- Same top-right slot as detailRemoveButton -- showDetailFor shows exactly one of the two,
	-- never both (see its own comment for why that's always safe).
	detailDisenchantButton = ButtonWidget.createButton(detailArea, L["VOTINGFRAME_DISENCHANT"], 90)

	detailVoteCountText = Primitives.createText(detailArea, "", 11, "dim")
	detailVoteCountText:SetPoint("RIGHT", detailDisenchantButton, "LEFT", -10, 0)
	detailVoteCountText:SetPoint("TOP", detailDisenchantButton, "TOP", 0, -8)

	-- A Frame wrapping the label, not the label itself -- a FontString has no SetScript, so
	-- showing a tooltip on hover needs an actual Frame to own OnEnter/OnLeave. RIGHT is reserved
	-- against the vote-count text's own left edge (not a fixed number), so it stays correct
	-- regardless of exactly where that text and the button end up. This only bounds the hover-
	-- tooltip trigger area, not the rendered text itself (detailItemLabel has no RIGHT point of
	-- its own, so a very long item name can still visually extend further than this if it has to).
	detailItemHover = CreateFrame("Frame", nil, detailArea)
	detailItemHover:SetPoint("TOPLEFT")
	detailItemHover:SetPoint("RIGHT", detailVoteCountText, "LEFT", -10, 0)
	detailItemHover:SetHeight(20)
	Primitives.attachItemTooltip(detailItemHover)
	-- Appends "who already received this item" below the item's own tooltip (UI/HistoryFrame.lua).
	detailItemHover:HookScript("OnEnter", function(self)
		if self.itemLink then
			PLC.UI.HistoryFrame.AddItemLines(GameTooltip, self.itemLink)
			GameTooltip:Show()
		end
	end)

	detailItemLabel = Primitives.createText(detailItemHover, "", 13, "white")
	detailItemLabel:SetPoint("LEFT")
	detailItemLabel:SetJustifyH("LEFT")

	Primitives.createSeparator(detailArea, -28)

	detailContainer = CreateFrame("Frame", nil, detailArea)
	detailContainer:SetPoint("TOPLEFT", 0, -36)
	detailContainer:SetPoint("BOTTOMRIGHT")

	detailNotice = Primitives.createText(detailArea, L["SESSIONFRAME_COUNCIL_ONLY"], 12, "dim")
	detailNotice:SetPoint("TOPLEFT", 0, -48)
	detailNotice:SetPoint("RIGHT", detailArea, "RIGHT", -10, 0)
	detailNotice:SetJustifyH("LEFT")
	detailNotice:SetWordWrap(true)
	detailNotice:Hide()

	votingPanel = PLC.UI.VotingFrame.CreatePanel(detailContainer, detailVoteCountText, detailDisenchantButton)

	-- Only now does VotingFrame.GRID_WIDTH exist (CreatePanel just set it) -- both buttons' right
	-- edge lands exactly on the grid's own right edge (the Award column's), measured from
	-- detailArea's LEFT since the grid itself starts flush with detailArea's left edge too.
	detailDisenchantButton:SetPoint("TOPRIGHT", detailArea, "TOPLEFT", PLC.UI.VotingFrame.GRID_WIDTH, 0)
	detailRemoveButton:SetPoint("TOPRIGHT", detailArea, "TOPLEFT", PLC.UI.VotingFrame.GRID_WIDTH, 0)

	-- The window's own width is derived from the grid's real content width instead of a
	-- hand-picked number -- a hardcoded width (630, from before this round) drifted out of sync
	-- with an earlier column-narrowing pass and left a growing stripe of genuinely unused space
	-- between the grid/buttons and the window's right border. Deriving it means it can't drift
	-- again the same way if a column width ever changes: detailArea needs to fit the grid's
	-- content (GRID_WIDTH) plus the grid's own scrollbar gutter (ScrollFrame.RESERVED_WIDTH,
	-- reserved -- as blank space -- even when not actively scrolling, which is the common case for
	-- a small council; this is a pre-existing characteristic of every DataTable in the addon, not
	-- something specific to this window, so it's not shrunk here even though it reads as "more
	-- wasted space" right next to the margin below); frame width then adds back everything between
	-- the window's edge and detailArea's left edge (content's left/right insets below, the icon
	-- sidebar, and the gap between the sidebar and detailArea). No added margin beyond that -- the
	-- Award/Disenchant buttons sit right at detailArea's true edge, with content's own small right
	-- inset (3px, see below) the only deliberate breathing room left before the window's border.
	local detailAreaWidth = PLC.UI.VotingFrame.GRID_WIDTH + PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH
	local frameWidth = 6 + ICON_SIDEBAR_WIDTH + 8 + detailAreaWidth + 3

	-- Height stays freely resizable -- a taller window genuinely shows more item icons in the
	-- sidebar. +30 over the pre-Enchanter-row baseline, to compensate for the toolbar row below
	-- the header without shrinking the visible item list.
	frame:SetSize(frameWidth, 530)
	-- Width min and max are the same value -- fixes the width (see the comment above) while
	-- leaving height genuinely resizable between 390 and 830.
	Primitives.makeResizable(frame, frameWidth, 390, frameWidth, 830)

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

-- Plain `/plc` -- the main entry point. There's no automatic popup on loot (collection is
-- deliberately silent across the whole raid, see Loot/Detection.lua); any council member, not just
-- the live ML, can use this to check progress or reach the controls for a running session.
function SessionFrame:Open()
	local f = ensureFrame()
	refresh()
	f:Show()
end

PLC:SetDefaultSlashHandler(function()
	SessionFrame:Open()
end)
