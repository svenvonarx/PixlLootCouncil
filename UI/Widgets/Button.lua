local ADDON_NAME, PLC = ...

local Primitives = PLC.UI.Widgets.Primitives
local Theme = PLC.UI.Theme

local Button = {}
PLC.UI.Widgets.Button = Button

-- Ported from FojjiCore (Options.lua:260-283, see docs/analysis/fojjicore-ui-style.md): flat
-- fill + 1px border, centered label, hover swaps bg to buttonHover and borders to accent.
--
-- `width` is optional -- omit it (or pass nil/false) for a button that sizes itself to its own
-- label instead of a caller-chosen fixed width. UI/LootFrame.lua's 5 response buttons used to
-- share one fixed width, which left short labels like "OS" swimming in padding while longer ones
-- like "Upgrade" looked cramped against their own border.
local BUTTON_PADDING_X = 20
local MIN_BUTTON_WIDTH = 36

local function styleButton(button, text, width)
	button.bg = Primitives.createTexture(button, "BACKGROUND", "button")
	button.bg:SetAllPoints()

	button.border = Primitives.createBorder(button)

	button.label = Primitives.createText(button, text, 12)
	button.label:SetPoint("CENTER")

	if width then
		button:SetSize(width, Theme.LAYOUT.buttonHeight)
	else
		button:SetSize(math.max(MIN_BUTTON_WIDTH, button.label:GetStringWidth() + BUTTON_PADDING_X), Theme.LAYOUT.buttonHeight)
	end

	button:SetScript("OnEnter", function(self)
		self.bg:SetColorTexture(Primitives.color("buttonHover"))
		Primitives.setBorderColor(self.border, "accent", 0.75)
	end)

	button:SetScript("OnLeave", function(self)
		self.bg:SetColorTexture(Primitives.color("button"))
		Primitives.setBorderColor(self.border, "border")
	end)

	return button
end

function Button.createButton(parent, text, width)
	return styleButton(CreateFrame("Button", nil, parent), text, width)
end

-- A secure, macro-driven button -- for an action that has to cast a protected spell (right now:
-- Disenchant, see Loot/Trade.lua) rather than call a protected API directly from insecure Lua,
-- which risks ADDON_ACTION_BLOCKED/taint (docs/SPECIFICATION.md principles 2/7 -- this addon has
-- avoided secure templates everywhere else precisely to not need this, but spell-casting is the
-- one action class that genuinely requires it; Blizzard's own macro engine is the taint-safe way
-- to do it, not a workaround). Same visual styling as createButton -- only the underlying frame
-- type and click behavior differ. Caller sets the actual action via
-- :SetAttribute("macrotext", "...") after creation, and must never do so during combat lockdown
-- (InCombatLockdown()) -- secure-frame attribute changes aren't allowed then.
function Button.createActionButton(parent, text, width)
	local button = styleButton(CreateFrame("Button", nil, parent, "SecureActionButtonTemplate"), text, width)
	button:SetAttribute("type", "macro")
	button:RegisterForClicks("AnyUp", "AnyDown")
	return button
end
