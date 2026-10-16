local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- Every awarded item this client still has to deal with, in one list: items the session owner
-- has to hand out (or disenchant themselves), and items awarded to this player that they still
-- have to collect. Rows disappear as Loot/Trade.lua confirms each handoff; the window hides itself
-- once the list is empty. Layout deliberately mirrors UI/LootFrame.lua (one DataTable filling the
-- content area) -- an earlier two-section version with stacked labels/containers anchored its
-- tables outside the window, so rows never rendered.
local TradeFrame = {}
PLC.UI.TradeFrame = TradeFrame

local frame
local dataTable
local tickerHandle
local userClosed = false -- true once manually closed while something was still pending
local wasEmpty = true -- previous refresh had no rows; see Refresh()

local ROW_HEIGHT = Theme.LAYOUT.buttonHeight + 6
local TRADE_BUTTON_WIDTH = 54
local FOLLOW_BUTTON_WIDTH = 54
local OVERDUE_SECONDS = 180 -- elapsed text turns warning-colored past this; informational only
local DOUBLE_CLICK_SECONDS = 0.5

-- kind: "handout" (I own the session, item goes to someone else), "self" (I own the session and
-- awarded it to myself -- only reachable for disenchant, a self-award auto-completes), or
-- "collect" (someone else's session awarded it to me).
local function classify(item, myGuid)
	if not item.awarded or item.traded then
		return nil
	end
	if PLC.Session:IsOwner() then
		return item.awarded == myGuid and "self" or "handout"
	end
	if item.awarded == myGuid then
		return "collect"
	end
	return nil
end

local function buildRows()
	local rows = {}
	local myGuid = UnitGUID("player")
	for idx, item in pairs(PLC.Session.items) do
		local kind = classify(item, myGuid)
		if kind then
			local partnerName
			if kind == "handout" then
				local entry = PLC.Roster:Get(item.awarded)
				partnerName = string.format(L["TRADEFRAME_TO"], (entry and PLC.Roster:ShortName(entry.name)) or "?")
			elseif kind == "collect" then
				local owner = PLC.Session.owner
				partnerName = string.format(L["TRADEFRAME_FROM"], (owner and PLC.Roster:ShortName(owner.name)) or "?")
			else
				partnerName = L["TRADEFRAME_SELF"]
			end
			table.insert(rows, {
				idx = idx,
				link = item.link,
				icon = item.icon,
				kind = kind,
				isSelf = kind == "self",
				partnerName = partnerName,
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

local COLUMNS = {
	{
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
	},
	{
		width = 140,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(140, 24)
			holder.text = Primitives.createText(holder, "", 11)
			holder.text:SetPoint("LEFT")
			holder.text:SetPoint("RIGHT")
			holder.text:SetJustifyH("LEFT")
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			holder.text:SetText(rowData.link or "?")
			holder.itemLink = rowData.link
		end,
	},
	{
		width = 110,
		justify = "LEFT",
		render = function(rowData)
			return rowData.partnerName
		end,
	},
	{
		width = 90,
		justify = "LEFT",
		render = function(rowData)
			local elapsed = time() - (rowData.awardedAt or time())
			local minutes = math.floor(elapsed / 60)
			local text = minutes <= 0 and L["TRADEFRAME_AWARDED_JUST_NOW"] or string.format(L["TRADEFRAME_AWARDED_AGO"], minutes)
			local r, g, b = Primitives.color(elapsed >= OVERDUE_SECONDS and "warning" or "dim")
			return text, r, g, b
		end,
	},
	{
		-- One slot, two buttons: Trade for a normal row, a secure macro-driven Disenchant for a
		-- self-disenchant row (casting a spell must go through Blizzard's macro engine -- see
		-- UI/Widgets/Button.lua:createActionButton -- so it never gets a Lua OnClick).
		width = TRADE_BUTTON_WIDTH + 6,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(TRADE_BUTTON_WIDTH, Theme.LAYOUT.buttonHeight)
			holder.tradeButton = ButtonWidget.createButton(holder, L["TRADEFRAME_TRADE"], TRADE_BUTTON_WIDTH)
			holder.tradeButton:SetPoint("LEFT")
			holder.disenchantButton = ButtonWidget.createActionButton(holder, L["VOTINGFRAME_DISENCHANT"], TRADE_BUTTON_WIDTH)
			holder.disenchantButton:SetPoint("LEFT")
			return holder
		end,
		update = function(holder, rowData)
			holder.tradeButton:SetShown(not rowData.isSelf)
			holder.tradeButton:SetScript("OnClick", function()
				PLC.Loot.Trade:StartTrade(rowData.idx)
			end)
			holder.disenchantButton:SetShown(rowData.isSelf)
			if rowData.isSelf then
				PLC.Loot.Trade:ConfigureDisenchantButton(holder.disenchantButton, rowData.idx)
			end
		end,
	},
	{
		width = FOLLOW_BUTTON_WIDTH,
		isWidget = true,
		create = function(row)
			return ButtonWidget.createButton(row, L["TRADEFRAME_FOLLOW"], FOLLOW_BUTTON_WIDTH)
		end,
		update = function(button, rowData)
			button:SetShown(not rowData.isSelf)
			button:SetScript("OnClick", function()
				PLC.Loot.Trade:FollowPartner(rowData.idx)
			end)
		end,
	},
	{
		-- Manual removal for a stuck row: two clicks within DOUBLE_CLICK_SECONDS, same as the
		-- history window's delete (UI/HistoryFrame.lua). See Session:DismissTradeItem.
		width = 24,
		isWidget = true,
		create = function(row)
			local button = Primitives.createCloseButton(row, 16)
			button:HookScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(L["TRADEFRAME_REMOVE_TIP"], nil, nil, nil, nil, true)
				GameTooltip:Show()
			end)
			button:HookScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			return button
		end,
		update = function(button, rowData)
			if button.idx ~= rowData.idx then
				button.lastClick = nil
			end
			button.idx = rowData.idx
			button:SetScript("OnClick", function(self)
				local now = GetTime()
				if self.lastClick and now - self.lastClick <= DOUBLE_CLICK_SECONDS then
					self.lastClick = nil
					GameTooltip:Hide()
					PLC.Session:DismissTradeItem(rowData.idx)
				else
					self.lastClick = now
				end
			end)
		end,
	},
}

local function ensureFrame()
	if frame then
		return frame
	end

	-- Width from the real column widths, same discipline as UI/LootFrame.lua/UI/SessionFrame.lua.
	local rowContentWidth = 0
	for _, col in ipairs(COLUMNS) do
		rowContentWidth = rowContentWidth + col.width
	end
	local frameWidth = rowContentWidth + PLC.UI.Widgets.ScrollFrame.RESERVED_WIDTH + 10 + 20

	frame = CreateFrame("Frame", "PixlLootCouncilTradeFrame", UIParent)
	Primitives.refreshFontsOnShow(frame)
	frame:SetSize(frameWidth, 220)
	frame:SetPoint("CENTER", 0, 120)
	-- Highest strata, per the explicit "highest prio" ask.
	frame:SetFrameStrata("TOOLTIP")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PixlLootCouncilTradeFrame")
	Primitives.makeResizable(frame, frameWidth, 140, frameWidth, 600)
	frame:SetScript("OnHide", function()
		stopTicker()
	end)

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

	dataTable = DataTable.Create(content, ROW_HEIGHT)
	dataTable:SetColumns(COLUMNS)

	-- This window sits on the TOOLTIP strata (the "highest prio" ask), the same strata as
	-- GameTooltip -- so a tooltip shown from inside it (remove button, item icons) rendered
	-- underneath the window. Raise any tooltip owned by something in this window above it.
	local function isInFrame(owner)
		-- Item comparison tooltips are owned by GameTooltip itself; follow it to its owner.
		if owner == GameTooltip then
			owner = GameTooltip:GetOwner()
		end
		while owner do
			if owner == frame then
				return true
			end
			owner = owner.GetParent and owner:GetParent()
		end
		return false
	end
	local function raiseTooltip(tooltip)
		if frame:IsShown() and isInFrame(tooltip:GetOwner()) then
			tooltip:SetFrameStrata("TOOLTIP")
			tooltip:SetFrameLevel(frame:GetFrameLevel() + 100)
		end
	end
	for _, tooltip in ipairs({ GameTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
		if tooltip then
			tooltip:HookScript("OnShow", raiseTooltip)
		end
	end

	frame:Hide()
	return frame
end

-- Called from Data/Session.lua's notifyTradeFrame on every award/trade/session change, and once a
-- second while shown. Auto-shows when the list goes from empty to non-empty, but never reopens
-- itself after a manual close while items are still pending (unlike UI/LootFrame.lua, which
-- deliberately keeps nagging about an unanswered vote).
function TradeFrame:Refresh()
	local rows = buildRows()
	if #rows == 0 then
		stopTicker()
		if frame then
			frame:Hide()
		end
		wasEmpty = true
		return
	end

	local f = ensureFrame()
	dataTable:SetRows(rows)

	if wasEmpty then
		userClosed = false
	end
	wasEmpty = false

	if not userClosed then
		f:Show()
	end
	startTicker()
end

function TradeFrame:OnSessionUpdated()
	self:Refresh()
end

-- Forces the window open even if it was manually closed (still hides itself if there's nothing to
-- trade). Called on Award All and when an award for this player arrives.
function TradeFrame:Open()
	userClosed = false
	self:Refresh()
end

PLC:RegisterSlashCommand("trades", "Reopen the Loot Trades window", function()
	if #buildRows() == 0 then
		print(L["CHAT_PREFIX"] .. L["TRADEFRAME_NO_ITEMS"])
		return
	end
	TradeFrame:Open()
end)
