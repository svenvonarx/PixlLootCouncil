local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- One window, two sections -- not two separate windows -- since the common case of a holder who
-- also won something themselves needs both visible at once anyway (see docs/analysis notes from
-- planning this round). "Items to hand out" is the holder's own un-traded awards; "items to
-- collect" is whatever's been awarded to the local player, from anyone's session. Both sections
-- disappear row-by-row as Loot/Trade.lua confirms each trade, and the whole window hides itself
-- once both are empty.
local TradeFrame = {}
PLC.UI.TradeFrame = TradeFrame

local frame
local header
local handoutLabel
local handoutTable
local collectLabel
local collectTable
local tickerHandle
local userClosed = false -- true once manually closed while something was still pending
local wasEmpty = true -- tracks the previous refresh's total-row-emptiness, see refresh() below

local ROW_HEIGHT = Theme.LAYOUT.buttonHeight + 6 -- same formula every other grid in this addon uses
local TRADE_BUTTON_WIDTH = 54
local FOLLOW_BUTTON_WIDTH = 54
local OVERDUE_SECONDS = 180 -- flat constant, not configurable this round -- see the plan's "known
-- limitations" -- past this, the elapsed-time text turns `warning`-colored. Informational only:
-- nothing times out or auto-cancels, there's just no real deadline to enforce here.

local function buildHandoutRows()
	local rows = {}
	if not PLC.Session:IsHolder() then
		return rows
	end
	for idx, item in pairs(PLC.Session.items) do
		if item.awarded and not item.traded then
			local entry = PLC.Roster:Get(item.awarded)
			table.insert(rows, {
				idx = idx,
				link = item.link,
				icon = item.icon,
				partnerName = (entry and PLC.Roster:ShortName(entry.name)) or "?",
				awardedAt = item.awardedAt,
			})
		end
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

local function buildCollectRows()
	local rows = {}
	local myGuid = UnitGUID("player")
	for idx, item in pairs(PLC.Session.items) do
		if item.awarded == myGuid and not item.traded then
			table.insert(rows, {
				idx = idx,
				link = item.link,
				icon = item.icon,
				partnerName = (PLC.Session.owner and PLC.Roster:ShortName(PLC.Session.owner.name)) or "?",
				awardedAt = item.awardedAt,
			})
		end
	end
	table.sort(rows, function(a, b) return a.idx < b.idx end)
	return rows
end

local function startTicker()
	if tickerHandle then
		return
	end
	tickerHandle = PLC:ScheduleRepeatingTimer(function()
		TradeFrame:Refresh()
	end, 1)
end

local function stopTicker()
	if tickerHandle then
		PLC:CancelTimer(tickerHandle)
		tickerHandle = nil
	end
end

-- Shared by both sections' icon column -- same pattern UI/LootFrame.lua's own icon column already
-- uses (a Frame wrapper, not a bare texture, since a hover tooltip needs SetScript).
local function iconColumn()
	return {
		width = 28,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(24, 24)
			holder.texture = holder:CreateTexture(nil, "ARTWORK")
			holder.texture:SetAllPoints()
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			holder.texture:SetTexture(rowData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
			holder.itemLink = rowData.link
		end,
	}
end

local function nameColumn()
	return {
		width = 140,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(140, 24)
			holder.text = Primitives.createText(holder, "", 11)
			holder.text:SetPoint("LEFT")
			holder.text:SetJustifyH("LEFT")
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			holder.text:SetText(rowData.link or "?")
			holder.itemLink = rowData.link
		end,
	}
end

local function partnerColumn()
	return {
		width = 90,
		justify = "LEFT",
		render = function(rowData)
			return rowData.partnerName
		end,
	}
end

-- "Awarded Xm ago", turning `warning`-colored past OVERDUE_SECONDS -- informational only, see the
-- constant's own comment above.
local function elapsedColumn()
	return {
		width = 90,
		justify = "LEFT",
		render = function(rowData)
			local elapsed = time() - (rowData.awardedAt or time())
			local minutes = math.floor(elapsed / 60)
			local text = minutes <= 0 and L["TRADEFRAME_AWARDED_JUST_NOW"] or string.format(L["TRADEFRAME_AWARDED_AGO"], minutes)
			local r, g, b = Primitives.color(elapsed >= OVERDUE_SECONDS and "warning" or "dim")
			return text, r, g, b
		end,
	}
end

local function tradeColumn(isLast)
	return {
		width = TRADE_BUTTON_WIDTH + (isLast and 0 or 6),
		isWidget = true,
		create = function(row)
			return ButtonWidget.createButton(row, L["TRADEFRAME_TRADE"], TRADE_BUTTON_WIDTH)
		end,
		update = function(button, rowData)
			button:SetScript("OnClick", function()
				PLC.Loot.Trade:StartTrade(rowData.idx)
			end)
		end,
	}
end

-- Collect-section only -- there's nothing for the holder to "follow" on their own hand-out rows.
-- Calls FollowUnit directly from OnClick, synchronously, same hardware-event requirement
-- InitiateTrade has (see Loot/Trade.lua's own file comment).
local function followColumn()
	return {
		width = FOLLOW_BUTTON_WIDTH,
		isWidget = true,
		create = function(row)
			return ButtonWidget.createButton(row, L["TRADEFRAME_FOLLOW"], FOLLOW_BUTTON_WIDTH)
		end,
		update = function(button)
			button:SetScript("OnClick", function()
				local ownerGuid = PLC.Session.owner and PLC.Session.owner.guid
				local unit = ownerGuid and PLC.Loot.Trade:ResolveUnitToken(ownerGuid)
				if unit then
					FollowUnit(unit)
				end
			end)
		end,
	}
end

local function ensureFrame()
	if frame then
		return frame
	end

	-- Width derived from the collect section's own real column widths (the wider of the two
	-- sections, since it has one more button than the handout section) -- same "measure the real
	-- columns, don't hand-pick a window width" discipline UI/SessionFrame.lua and UI/LootFrame.lua
	-- already had to learn the hard way (a stale hardcoded number silently drifted and clipped
	-- content in both of those before it was caught).
	local collectContentWidth = 28 + 140 + 90 + 90 + TRADE_BUTTON_WIDTH + 6 + FOLLOW_BUTTON_WIDTH
	local contentWidth = collectContentWidth + PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH + 10
	local frameWidth = contentWidth + 20 -- content's own 10px left + 10px right insets, see below

	frame = CreateFrame("Frame", "PixlLootCouncilTradeFrame", UIParent)
	frame:SetSize(frameWidth, 340)
	frame:SetPoint("CENTER", 0, 120)
	-- The literal ceiling strata -- the one other thing already at this tier is
	-- UI/Widgets/PopupMenu.lua's dropdown popup (itself transient, closed on the next outside
	-- click), so this is effectively the highest anything in the addon can sit. Trading is
	-- genuinely time-sensitive the way reviewing loot isn't, which is also why this window (unlike
	-- every other one) auto-shows itself -- see refresh() below.
	frame:SetFrameStrata("TOOLTIP")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilTradeFrame")
	Primitives.makeResizable(frame, frameWidth, 260, frameWidth, 600)
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

	header.title = Primitives.createText(header, L["TRADEFRAME_TITLE"], 18, "title")
	header.title:SetPoint("LEFT", header.logo, "RIGHT", 8, -2)

	header.close = Primitives.createCloseButton(header, 20)
	header.close:SetPoint("RIGHT", -6, 0)
	header.close:SetScript("OnClick", function()
		userClosed = true
		frame:Hide()
	end)

	Primitives.createSeparator(frame, -Theme.LAYOUT.headerHeight)

	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -10)
	content:SetPoint("BOTTOMRIGHT", -10, 10)

	-- Explicit RIGHT point (not just TOPLEFT) on both labels below -- a FontString with no RIGHT
	-- point auto-sizes to its own (left-aligned) text width, which would make each section's
	-- *table* container below it (anchored off the label's BOTTOMRIGHT) only as wide as the label
	-- text itself instead of the full content width.
	handoutLabel = Primitives.createText(content, L["TRADEFRAME_HANDOUT_SECTION"], 12, "white")
	handoutLabel:SetPoint("TOPLEFT")
	handoutLabel:SetPoint("RIGHT", content, "RIGHT")

	local handoutContainer = CreateFrame("Frame", nil, content)
	handoutContainer:SetPoint("TOPLEFT", handoutLabel, "BOTTOMLEFT", 0, -6)
	handoutContainer:SetPoint("TOPRIGHT", handoutLabel, "BOTTOMRIGHT", 0, -6)
	handoutContainer:SetHeight(ROW_HEIGHT * 3)
	handoutTable = DataTable.Create(handoutContainer, ROW_HEIGHT)
	handoutTable:SetColumns({ iconColumn(), nameColumn(), partnerColumn(), elapsedColumn(), tradeColumn(true) })

	collectLabel = Primitives.createText(content, L["TRADEFRAME_COLLECT_SECTION"], 12, "white")
	collectLabel:SetPoint("TOPLEFT", handoutContainer, "BOTTOMLEFT", 0, -14)
	collectLabel:SetPoint("RIGHT", content, "RIGHT")

	local collectContainer = CreateFrame("Frame", nil, content)
	collectContainer:SetPoint("TOPLEFT", collectLabel, "BOTTOMLEFT", 0, -6)
	collectContainer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
	collectTable = DataTable.Create(collectContainer, ROW_HEIGHT)
	collectTable:SetColumns({ iconColumn(), nameColumn(), partnerColumn(), elapsedColumn(), tradeColumn(false), followColumn() })

	frame:Hide()
	return frame
end

-- Called from Data/Session.lua's notifyTradeFrame forward-hook on every relevant change (an award
-- committing, a trade completing locally or via the trade_complete broadcast), and once a second
-- while shown (see startTicker) -- same "just rebuild from scratch every time, it's cheap enough"
-- approach UI/LootFrame.lua already uses for an almost identical shape of window.
--
-- Auto-shows itself the moment total rows go from 0 to >0 -- a deliberate, narrow exception to the
-- addon's usual "no reactive popups" principle, since trading has real time pressure review
-- doesn't. Does NOT force itself back open on every subsequent refresh while the player has
-- manually closed it (userClosed) -- unlike UI/LootFrame.lua's own window, which intentionally
-- keeps nagging about an unanswered vote, there's no comparable reason to override a trade window
-- someone deliberately dismissed.
function TradeFrame:Refresh()
	local handoutRows = buildHandoutRows()
	local collectRows = buildCollectRows()
	local total = #handoutRows + #collectRows

	if total == 0 then
		stopTicker()
		if frame then
			frame:Hide()
		end
		wasEmpty = true
		return
	end

	local f = ensureFrame()
	handoutTable:SetRows(handoutRows)
	handoutLabel:SetShown(#handoutRows > 0)
	handoutTable.scroll:SetShown(#handoutRows > 0)

	collectTable:SetRows(collectRows)
	collectLabel:SetShown(#collectRows > 0)
	collectTable.scroll:SetShown(#collectRows > 0)

	if wasEmpty then
		userClosed = false
	end
	wasEmpty = false

	if not userClosed then
		f:Show()
	end
	startTicker()
end

-- Forward-hook target from Data/Session.lua -- same naming convention as OnSessionUpdated on
-- every other window in this addon, even though this one's trigger set is a little different
-- (award/trade changes, not just the item set).
function TradeFrame:OnSessionUpdated()
	self:Refresh()
end

-- Manual reopen, in case the player closed it mid-trade -- overrides userClosed explicitly, unlike
-- Refresh()'s own reactive auto-show.
PLC:RegisterSlashCommand("tradeframe", "Reopen the loot trade window", function()
	userClosed = false
	TradeFrame:Refresh()
end)
