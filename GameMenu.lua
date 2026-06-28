local ADDON, ns = ...

-- ===========================================================================
--  Lumen — entry in the ESC game menu.
--  Uses Blizzard's own AddButton API via the InitButtons hook: the game
--  handles layout + height itself, so it coexists cleanly with other addons
--  without overlapping buttons.
--  The button is sorted directly UNDER "AddOns" and visually grouped with it
--  (space above + below), mirroring Blizzard's own sectioning (layoutIndex
--  sorts the buttons, topPadding creates the gaps).
-- ===========================================================================

local GROUP_PAD = 20 -- group spacing above/below the AddOns+Lumen group (like Blizzard's sections)

-- Custom look for the Lumen button: Cinzel gold (like the wordmark) instead of Blizzard's
-- default red face -> stands out clearly from the red button + background. The color is a
-- |cff..|-code in the text (survives Blizzard's hover/enable states); the font face is set
-- on the FontString. ns.UI is safely present here (GameMenu.lua loads last, after Shell/Tokens).
local LUMEN_GOLD = "E6C883" -- = UI.C.gold300 (display/wordmark gold)
local LUMEN_TEXT = "|cff" .. LUMEN_GOLD .. "Lumen|r"

local DEFAULT_FONT -- {path,size,flags} of an unmarked Blizzard button (learned once)

-- Styles ONLY our button and makes pool recycling safe: Blizzard pools the menu buttons
-- and resets neither font nor text color on reuse. If the button count changes (e.g. Edit
-- Mode removed in combat), our previously styled frame may be reused for a Blizzard button
-- -> our Cinzel would "bleed through". So each time: learn the default font, reset foreign
-- but still-marked buttons, then style ours.
local function styleButton(menu, btn)
	if not (menu.buttonPool and menu.buttonPool.EnumerateActive and btn and btn.GetFontString) then return end
	if not DEFAULT_FONT then
		for b in menu.buttonPool:EnumerateActive() do
			if b ~= btn and not b._lumenStyled and b.GetFontString then
				local fs = b:GetFontString()
				if fs then local p, s, fl = fs:GetFont(); if p then DEFAULT_FONT = { p, s, fl }; break end end
			end
		end
	end
	for b in menu.buttonPool:EnumerateActive() do
		if b ~= btn and b._lumenStyled then -- recycled, previously styled frame -> reset
			b._lumenStyled = nil
			local fs = b.GetFontString and b:GetFontString()
			if fs and DEFAULT_FONT then fs:SetFont(DEFAULT_FONT[1], DEFAULT_FONT[2], DEFAULT_FONT[3]) end
		end
	end
	local fs = btn:GetFontString()
	if fs and ns.UI and ns.UI.FONT then
		local size = (DEFAULT_FONT and DEFAULT_FONT[2]) or 14
		if fs:SetFont(ns.UI.FONT.cinzelSemi, size, "") then btn._lumenStyled = true end
	end
end

local function openLumen()
	if InCombatLockdown() then return end
	HideUIPanel(GameMenuFrame)
	if ns.Lumen and ns.Lumen.OpenConfig then ns.Lumen:OpenConfig() end -- opens the suite shell
end

-- Find an active pool button by its text (the buttons have no fixed references;
-- they live in buttonPool and carry the localized text).
local function findButton(menu, text)
	if not (menu.buttonPool and menu.buttonPool.EnumerateActive) then return nil end
	for b in menu.buttonPool:EnumerateActive() do
		if b.GetText and b:GetText() == text then return b end
	end
end

local function placeUnderAddons(menu, btn)
	local addons = findButton(menu, ADDONS)
	if not (addons and btn) then return end -- no AddOns button (e.g. kiosk) -> button stays at the bottom
	local ai = addons.layoutIndex or 1

	-- The button that ORIGINALLY comes right after AddOns (smallest index > AddOns, excluding us):
	-- it gets the space BELOW, so [AddOns | Lumen] sets off as a group.
	local nextBtn, nextIdx
	for b in menu.buttonPool:EnumerateActive() do
		local li = b.layoutIndex
		if li and b ~= btn and li > ai and (not nextIdx or li < nextIdx) then
			nextIdx, nextBtn = li, b
		end
	end

	btn.layoutIndex = ai + 0.5 -- right behind AddOns (fractional -> no renumbering needed)
	btn.topPadding  = 0
	addons.topPadding = GROUP_PAD       -- space ABOVE the group
	if nextBtn then nextBtn.topPadding = GROUP_PAD end -- space BELOW the group

	menu:MarkDirty()
	if menu.Layout then menu:Layout() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if not (GameMenuFrame and GameMenuFrame.InitButtons) then return end
	-- InitButtons runs on every open (reset + rebuild) -> re-add and re-sort the button each time.
	hooksecurefunc(GameMenuFrame, "InitButtons", function(self)
		if not self.AddButton then return end
		local btn = self:AddButton(LUMEN_TEXT, openLumen)
		styleButton(self, btn)
		placeUnderAddons(self, btn)
	end)
end)
