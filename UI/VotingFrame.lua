local ADDON_NAME, PLC = ...

local L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local Primitives = PLC.UI.Widgets.Primitives
local ButtonWidget = PLC.UI.Widgets.Button
local DataTable = PLC.UI.Widgets.DataTable
local Theme = PLC.UI.Theme

-- Embeddable response-grid panel, NOT its own top-level window -- UI/SessionFrame.lua mounts
-- this directly into its own content area as the "same window, all the answers" merged layout
-- (see docs/SPECIFICATION.md §4.3's single-purpose-window guidance -- this is no longer
-- single-purpose on its own, it's a component of SessionFrame).
--
-- Bagged-item workflow: by the time anyone's reviewing an item it's always already in the ML's
-- bags (Data/Session.lua:CollectDetectedItems self-loots everything at collection time), so
-- there's never a live loot slot left for Award to transfer through directly -- Award here means
-- "record who should get it, the holder trades it to them manually" (Session:AwardBaggedItem).
-- Nothing in this panel ever commits directly anymore: both the per-candidate Award button and
-- the header's Disenchant button only ever stage a pick (Session:SetPreAward), then auto-advance
-- to the next item (SessionFrame:AdvanceToNextItem) -- Session:AwardAllPreAwarded is the one and
-- only commit path, pressed once from UI/SessionFrame.lua after reviewing a whole batch.
local VotingFrame = {}
PLC.UI.VotingFrame = VotingFrame

local Panel = {}
local PanelMeta = { __index = Panel }

-- Full words for the role icon's hover tooltip now, not an inline text column -- the icon
-- (Primitives.createRoleIcon) carries the at-a-glance meaning, this is just there so it's never
-- ambiguous to someone unfamiliar with the icon shapes.
local ROLE_ABBR = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage Dealer" }

-- Trailing space after the Award column's own button width, also reused as the row-height
-- formula's own vertical slack (see DataTable.Create below), so the column's own right-edge gap
-- and the vertical gap between two rows' buttons are the same single number.
local BUTTON_GAP = 6

local function classColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then
		return c.r, c.g, c.b
	end
	return Primitives.color("text")
end

local function responseConfig(key)
	if not key then
		return nil
	end
	for _, resp in ipairs(PLC.db.profile.responses) do
		if resp.key == key then
			return resp
		end
	end
	return nil
end

local function findRowIndexByGuid(rowsData, guid)
	for i, row in ipairs(rowsData) do
		if row.guid == guid then
			return i
		end
	end
end

-- nil, nil, nil (not yet synced, or not yet resolved client-side) is a normal, expected result
-- here, not an error -- see Data/Gear.lua.
local function resolveEquippedSlot(guid, slotID)
	if not slotID then
		return nil, nil, nil
	end
	local itemID = PLC.Gear:GetEquipped(guid, slotID)
	if not itemID then
		return nil, nil, nil
	end
	return PLC.Gear:ResolveItem(itemID)
end

function Panel:buildRows()
	local rows = {}
	if not self.currentIdx then
		return rows
	end
	local item = PLC.Session.items[self.currentIdx]
	local responses = PLC.Session.responses[self.currentIdx]

	-- Computed once per shown item, not once per candidate row -- the new item's own ilvl is the
	-- same for every candidate being compared. equipLoc feeds into PLC.Gear:SlotsForEquipLoc
	-- below, which (for weapon/offhand types) still needs a per-candidate check, so it stays as
	-- the raw equipLoc string here rather than being resolved to actual slot IDs yet.
	local newItemLevel, equipLoc
	if item and item.link then
		-- item.link is already resolved/synced reliably by the time an item is visible in this
		-- panel at all (the same guarantee its icon display already relies on, Data/Session.lua),
		-- so no "not cached yet" retry is needed on this side the way Data/Gear.lua needs one for
		-- an opponent's equipped item.
		local _, _, _, itemLevel, _, _, _, _, loc = C_Item.GetItemInfo(item.link)
		newItemLevel = itemLevel
		equipLoc = loc
	end

	for guid, entry in PLC.Roster:IterateGroup() do
		local r = responses and responses[guid]
		local row = {
			guid = guid,
			name = entry.name, -- full "Name-Realm", for the sort below and the history hover
			itemLink = item and item.link,
			shortName = PLC.Roster:ShortName(entry.name),
			class = entry.class,
			role = entry.role,
			response = r and r.response,
			note = r and r.note,
			present = PLC.Presence:IsPresent(guid),
			-- Excludes a disenchant stage even when this candidate happens to BE the current
			-- Enchanter -- they didn't win it as a candidate, so their own Award button shouldn't
			-- read "Staged" just because the item is staged for disenchant (see Panel:Disenchant's
			-- own header-level "Staged" swap instead).
			staged = item ~= nil and item.preAwardGuid == guid and item.preAwardReason ~= "disenchant",
		}

		local slotIDs = equipLoc and PLC.Gear:SlotsForEquipLoc(guid, equipLoc)
		if slotIDs then
			local link1, icon1, ilvl1 = resolveEquippedSlot(guid, slotIDs[1])
			local link2, icon2, ilvl2 = resolveEquippedSlot(guid, slotIDs[2])
			row.gearLink1, row.gearIcon1 = link1, icon1
			row.gearLink2, row.gearIcon2 = link2, icon2

			-- The lower of the two (or whichever single one exists) -- the one more likely to
			-- actually get replaced is the relevant comparison, not an average of both.
			local equippedIlvl
			if ilvl1 and ilvl2 then
				equippedIlvl = math.min(ilvl1, ilvl2)
			else
				equippedIlvl = ilvl1 or ilvl2
			end
			row.equippedIlvl = equippedIlvl
			if newItemLevel and equippedIlvl then
				row.diff = newItemLevel - equippedIlvl
			end
		end

		table.insert(rows, row)
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

-- "N out of M have voted" (RCLootCouncil-style header, from the screenshot comparison) -- M is
-- everyone shown in the table (addon or not), N is actual recorded responses, regardless of
-- presence.
function Panel:updateHeader()
	local responded, total = 0, 0
	for _, row in ipairs(self.rowsData) do
		total = total + 1
		if row.response then
			responded = responded + 1
		end
	end
	self.header:SetText(string.format(L["VOTINGFRAME_VOTE_COUNT"], responded, total))
end

-- Stages, never commits (see the file-header comment) -- then auto-advances the sidebar off this
-- item, same as Disenchant below, so reviewing a whole batch is just "click a choice" repeated.
function Panel:Award(guid)
	if not self.currentIdx then
		return
	end
	PLC.Session:SetPreAward(self.currentIdx, guid, "award")
	PLC.UI.SessionFrame:AdvanceToNextItem()
end

-- Stages to the current Enchanter (Session:GetEnchanterGuid() -- the explicit pick, or the
-- alphabetically-first roster member as a default) rather than to whichever row's button was
-- clicked -- this is why it's a header-level control, not a per-candidate one.
function Panel:Disenchant()
	if not self.currentIdx then
		return
	end
	local enchanterGuid = PLC.Session:GetEnchanterGuid()
	-- GetEnchanterGuid() can genuinely return nil now (nobody's synced Enchanting yet) -- staging
	-- to a nil guid would just surface as a confusing "unknown winner" error later at commit time,
	-- so refuse up front instead. The button's own tooltip already explains why (see below).
	if not enchanterGuid then
		return
	end
	PLC.Session:SetPreAward(self.currentIdx, enchanterGuid, "disenchant")
	PLC.UI.SessionFrame:AdvanceToNextItem()
end

-- Same "Staged" label/color swap the Award column's buttons use, just for the one header-level
-- Disenchant control -- item.preAwardReason == "disenchant" is the one state that matters here,
-- regardless of which candidate (if any) the Enchanter happens to also be.
function Panel:updateDisenchantButton()
	local item = self.currentIdx and PLC.Session.items[self.currentIdx]
	local staged = item ~= nil and item.preAwardReason == "disenchant"
	if staged then
		self.disenchantButton.label:SetText(L["VOTINGFRAME_STAGED"])
		local r, g, b = Primitives.color("accent")
		self.disenchantButton.label:SetTextColor(r, g, b)
	else
		self.disenchantButton.label:SetText(L["VOTINGFRAME_DISENCHANT"])
		local r, g, b = Primitives.color("text")
		self.disenchantButton.label:SetTextColor(r, g, b)
	end
end

function Panel:ShowItem(idx)
	self.currentIdx = idx
	self.rowsData = self:buildRows()
	self.dataTable:SetRows(self.rowsData)
	self:updateHeader()
	self:updateDisenchantButton()
end

-- Session:notifyVotingFrame's target (forwarded via VotingFrame:OnItemUpdated below). guid
-- present means "just this one row changed" (targeted RefreshRow, no full rebuild, per
-- docs/SPECIFICATION.md §4.4); omitted means "rebuild everything" (award/pre-award changes,
-- which can affect multiple rows at once -- e.g. staging a new pre-award un-stages the old one).
function Panel:OnItemUpdated(idx, guid)
	if idx ~= self.currentIdx then
		return
	end
	if not guid then
		self.rowsData = self:buildRows()
		self.dataTable:SetRows(self.rowsData)
		self:updateHeader()
		self:updateDisenchantButton()
		return
	end
	local rowIndex = findRowIndexByGuid(self.rowsData, guid)
	if not rowIndex then
		self.rowsData = self:buildRows()
		self.dataTable:SetRows(self.rowsData)
		self:updateHeader()
		self:updateDisenchantButton()
		return
	end
	local responses = PLC.Session.responses[idx]
	local r = responses and responses[guid]
	self.rowsData[rowIndex].response = r and r.response
	self.rowsData[rowIndex].note = r and r.note
	self.dataTable:RefreshRow(rowIndex)
	self:updateHeader()
end

-- Builds one of the two equipped-gear icon columns -- `suffix` ("1"/"2") picks which half of the
-- row's gearLink*/gearIcon* pair this particular column reads, same factory-function pattern
-- UI/SessionFrame.lua's iconColumn(suffix) already uses for its own two-icons-per-row sidebar.
-- Hidden entirely for a single-slot item's unused second column, not just blank.
local function gearColumn(suffix)
	return {
		width = 24,
		isWidget = true,
		create = function(row)
			local holder = CreateFrame("Frame", nil, row)
			holder:SetSize(20, 20)
			holder.texture = holder:CreateTexture(nil, "ARTWORK")
			-- Inset 1px, not SetAllPoints -- the border below sits at the holder's exact edge, on
			-- the BORDER layer, which an edge-to-edge ARTWORK-layer texture would render over and
			-- hide entirely (same reason UI/SessionFrame.lua's icon texture is inset, see its
			-- iconColumn).
			holder.texture:SetPoint("TOPLEFT", 1, -1)
			holder.texture:SetPoint("BOTTOMRIGHT", -1, 1)
			holder.border = Primitives.createBorder(holder)
			-- Same hover-tooltip helper UI/LootFrame.lua's and UI/SessionFrame.lua's item icons
			-- already use, just pointed at the candidate's equipped item instead of the session
			-- item -- holder.itemLink is read fresh on every hover, set below in update().
			Primitives.attachItemTooltip(holder)
			return holder
		end,
		update = function(holder, rowData)
			local link = rowData["gearLink" .. suffix]
			if link then
				holder.texture:SetTexture(rowData["gearIcon" .. suffix] or "Interface\\Icons\\INV_Misc_QuestionMark")
				holder.itemLink = link
				holder:Show()
			else
				holder.itemLink = nil
				holder:Hide()
			end
		end,
	}
end

-- Builds the candidate/role/response/Award grid into `parent` and returns the panel object. The
-- "N of M voted" text and the Disenchant button are NOT created here -- UI/SessionFrame.lua
-- builds and positions those itself, sharing the same top row as the item name and the Remove
-- button (one compact header bar instead of two stacked ones), and passes them in so this panel
-- can still own their content/click behavior. Only one panel is ever actually live at a time in
-- practice (the one UI/SessionFrame.lua mounts), but nothing here assumes that --
-- VotingFrame.activePanel (set below) is just "whichever panel Session's forward-hooks should
-- talk to."
function VotingFrame.CreatePanel(parent, header, disenchantButton)
	local tableContainer = CreateFrame("Frame", nil, parent)
	tableContainer:SetPoint("TOPLEFT", parent, "TOPLEFT")
	tableContainer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")

	-- No scroll:SetAllPoints() here -- UI/Widgets/ScrollFrame.lua anchors it to `tableContainer`
	-- itself now, reserving its own room for the scrollbar inside that.
	-- Same buttonHeight+BUTTON_GAP formula UI/LootFrame.lua's own row height already uses, not a
	-- separate ad-hoc number -- the resulting vertical slack (split evenly above/below the button
	-- via its "LEFT"-anchor centering) is what makes the gap between two rows' own Award buttons
	-- match BUTTON_GAP, the same number used as the Award column's own trailing space, below.
	local dataTable = DataTable.Create(tableContainer, Theme.LAYOUT.buttonHeight + BUTTON_GAP)

	local self = setmetatable({
		header = header,
		disenchantButton = disenchantButton,
		dataTable = dataTable,
		currentIdx = nil,
		rowsData = {},
	}, PanelMeta)

	disenchantButton:SetScript("OnClick", function()
		self:Disenchant()
	end)
	-- HookScript, not SetScript -- createButton already wired its own OnEnter/OnLeave for the
	-- hover background swap; hooking adds this tooltip on top instead of replacing that.
	disenchantButton:HookScript("OnEnter", function(btn)
		local guid = PLC.Session:GetEnchanterGuid()
		GameTooltip:SetOwner(btn, "ANCHOR_TOP")
		if guid then
			local entry = PLC.Roster:Get(guid)
			GameTooltip:SetText(string.format(L["VOTINGFRAME_DISENCHANT_TARGET"], PLC.Roster:ShortName(entry and entry.name) or "?"))
		else
			GameTooltip:SetText(L["SESSIONFRAME_NO_ENCHANTER"])
		end
		GameTooltip:Show()
	end)
	disenchantButton:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local columns = {
		{
			-- Role icon, then class icon, then name -- replaces what used to be a separate
			-- "DPS"/"Tank"/"Heal" text column entirely (role is now an icon here instead), which
			-- is most of where this column's own width comes back down from: WoW character names
			-- cap at 12 characters, so there's no reason to budget more name space than that
			-- actually needs, on top of removing the old column outright.
			width = 130,
			isWidget = true,
			create = function(row)
				local holder = CreateFrame("Frame", nil, row)
				holder:SetSize(130, 20)
				holder.roleIcon = Primitives.createRoleIcon(holder, nil)
				holder.roleIcon:SetSize(12, 12)
				holder.roleIcon:SetPoint("LEFT")
				holder.roleIcon:EnableMouse(true)
				holder.roleIcon:SetScript("OnEnter", function(self)
					if holder.roleText then
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:SetText(holder.roleText)
						GameTooltip:Show()
					end
				end)
				holder.roleIcon:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
				holder.classIcon = Primitives.createClassIcon(holder, nil)
				holder.classIcon:SetSize(16, 16)
				holder.classIcon:SetPoint("LEFT", holder.roleIcon, "RIGHT", 4, 0)
				holder.text = Primitives.createText(holder, "", 11)
				holder.text:SetPoint("LEFT", holder.classIcon, "RIGHT", 4, 0)
				-- Hovering the name shows what this candidate has already received (loot history,
				-- including anything imported from RCLootCouncil) -- see UI/HistoryFrame.lua.
				holder:EnableMouse(true)
				holder:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.shortName or "?", classColor(self.class))
					PLC.UI.HistoryFrame.AddPlayerLines(GameTooltip, self.fullName, self.itemLink)
					GameTooltip:Show()
				end)
				holder:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
				return holder
			end,
			update = function(holder, rowData)
				holder.fullName, holder.shortName, holder.class = rowData.name, rowData.shortName, rowData.class
				holder.itemLink = rowData.itemLink
				Primitives.setRoleIcon(holder.roleIcon, rowData.role)
				holder.roleText = ROLE_ABBR[rowData.role]
				Primitives.setClassIcon(holder.classIcon, rowData.class)
				local r, g, b = classColor(rowData.class)
				holder.text:SetText(rowData.shortName)
				holder.text:SetTextColor(r, g, b)
			end,
		},
		{
			-- Three real states: already voted > present (addon confirmed, no vote yet) > not
			-- detected at all (see Data/Presence.lua) -- not just a bare "-" for every
			-- not-yet-voted case.
			width = 150,
			isWidget = true,
			create = function(row)
				local holder = CreateFrame("Frame", nil, row)
				holder:SetSize(150, 20)
				holder:EnableMouse(true)
				holder.text = Primitives.createText(holder, "", 11)
				holder.text:SetPoint("LEFT")
				-- Leaves room on the right for the note icon instead of SetAllPoints -- response
				-- text is always short, so this just bounds its width rather than changing how
				-- it looks in the (overwhelmingly common) no-note case.
				holder.text:SetPoint("RIGHT", -14, 0)
				-- A small "has a note" glyph instead of requiring you to already know to hover --
				-- the hover-tooltip itself (below) is unchanged, this is purely a visibility aid.
				holder.noteIcon = Primitives.createNoteIcon(holder, 10)
				holder.noteIcon:SetPoint("RIGHT", -2, 0)
				holder.noteIcon:Hide()
				holder:SetScript("OnEnter", function(frame)
					if frame.note and frame.note ~= "" then
						GameTooltip:SetOwner(frame, "ANCHOR_TOP")
						GameTooltip:SetText(frame.note, nil, nil, nil, nil, true)
						GameTooltip:Show()
					end
				end)
				holder:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
				return holder
			end,
			update = function(holder, rowData)
				local resp = responseConfig(rowData.response)
				if resp then
					holder.text:SetText(resp.text)
					holder.text:SetTextColor(resp.color.r, resp.color.g, resp.color.b)
				elseif rowData.present then
					holder.text:SetText(L["VOTINGFRAME_WAITING"])
					local r, g, b = Primitives.color("dim")
					holder.text:SetTextColor(r, g, b)
				else
					holder.text:SetText(L["VOTINGFRAME_NO_ADDON"])
					local r, g, b = Primitives.color("warning")
					holder.text:SetTextColor(r, g, b)
				end
				holder.note = rowData.note
				holder.noteIcon:SetShown(rowData.note ~= nil and rowData.note ~= "")
			end,
		},
		{
			width = 35,
			justify = "CENTER",
			render = function(row)
				return row.equippedIlvl and tostring(row.equippedIlvl) or "-"
			end,
		},
		{
			-- Green/red/white against the equipped item's ilvl (see Panel:buildRows) -- reuses
			-- Theme.COLORS.success (added for the Award-feedback green) and the existing warning
			-- red, no new Theme entries.
			width = 35,
			justify = "CENTER",
			render = function(row)
				if not row.diff then
					return "-"
				end
				local colorName = row.diff > 0 and "success" or (row.diff < 0 and "warning" or "text")
				local r, g, b = Primitives.color(colorName)
				local sign = row.diff > 0 and "+" or ""
				return sign .. row.diff, r, g, b
			end,
		},
		gearColumn("1"),
		gearColumn("2"),
		{
			-- Non-binding -- last column, see UI/Widgets/DataTable.lua:Layout. Width is the
			-- button's own width plus BUTTON_GAP, explicitly -- not a separately-chosen round
			-- number that happened to leave roughly that much trailing space, which is what made
			-- this gap and the row-height gap drift apart before.
			width = 54 + BUTTON_GAP,
			isWidget = true,
			create = function(row)
				return ButtonWidget.createButton(row, L["VOTINGFRAME_AWARD"], 54)
			end,
			update = function(button, rowData)
				-- "Staged" swap (previously the separate Pre-Award button's own state) now lives
				-- directly on this one button -- there's nothing left for a second column to do.
				if rowData.staged then
					button.label:SetText(L["VOTINGFRAME_STAGED"])
					local r, g, b = Primitives.color("accent")
					button.label:SetTextColor(r, g, b)
				else
					button.label:SetText(L["VOTINGFRAME_AWARD"])
					local r, g, b = Primitives.color("text")
					button.label:SetTextColor(r, g, b)
				end
				button:SetScript("OnClick", function()
					self:Award(rowData.guid)
				end)
			end,
		},
	}
	dataTable:SetColumns(columns)

	-- Sum of every column's own width above, MINUS the trailing BUTTON_GAP the last (Award)
	-- column's own width includes -- that gap is reserved purely for the row-height-formula
	-- symmetry explained on BUTTON_GAP's own comment, and sits past the Award button's actual
	-- right edge, not under it. UI/SessionFrame.lua reads GRID_WIDTH to align its header-row
	-- controls (Disenchant/Remove/vote count) and the window's own width with where the Award
	-- button really ends, so including that trailing gap here would misalign them by exactly
	-- BUTTON_GAP -- small, but enough to read as "not quite lined up." Computed from `columns`
	-- itself, not a separately maintained number, so it can't drift out of sync if a column width
	-- changes.
	local gridWidth = 0
	for _, col in ipairs(columns) do
		gridWidth = gridWidth + col.width
	end
	VotingFrame.GRID_WIDTH = gridWidth - BUTTON_GAP

	VotingFrame.activePanel = self
	return self
end

function VotingFrame:OnItemUpdated(idx, guid)
	if self.activePanel then
		self.activePanel:OnItemUpdated(idx, guid)
	end
end
