local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Eintrag im ESC-Spielmenü.
--  Nutzt Blizzards eigene AddButton-API über den InitButtons-Hook: das Spiel
--  übernimmt Layout + Höhe selbst, dadurch koexistiert es sauber mit anderen
--  Addons (z. B. EllesmereUI) ohne übereinanderliegende Buttons.
--  Der Button wird direkt UNTER „Addons" einsortiert und mit „Addons" optisch
--  zu einer Gruppe zusammengefasst (Luft oben + unten), analog zur Blizzard-
--  Sektionierung (layoutIndex sortiert die Buttons, topPadding macht die Lücken).
-- ===========================================================================

local GROUP_PAD = 20 -- Gruppen-Abstand oben/unten um die Addons+Lumen-Gruppe (wie Blizzards Sektion)

-- Eigene Optik für den Lumen-Button: Cinzel-Gold (wie die Wortmarke) statt Blizzards rotem
-- Standard-Schnitt -> hebt sich klar vom roten Button + Hintergrund ab. Die Farbe steckt als
-- |cff..|-Code im Text (überlebt Blizzards Hover/Enable-Zustände); der Schnitt wird auf die
-- FontString gesetzt. ns.UI ist hier sicher da (GameMenu.lua lädt zuletzt, nach Shell/Tokens).
local LUMEN_GOLD = "E6C883" -- = UI.C.gold300 (Display-/Wortmarken-Gold)
local LUMEN_TEXT = "|cff" .. LUMEN_GOLD .. "Lumen|r"

local DEFAULT_FONT -- {pfad,größe,flags} eines unmarkierten Blizzard-Buttons (einmal gelernt)

-- Stylt NUR unseren Button und macht Pool-Recycling sicher: Blizzard poolt die Menü-Buttons
-- und setzt beim Reuse weder Font noch Text-Farbe zurück. Ändert sich die Button-Anzahl
-- (z. B. Edit-Mode im Kampf weg), kann unser zuvor gestyltes Frame für einen Blizzard-Button
-- wiederverwendet werden -> dann würde unser Cinzel „durchbluten". Daher: jedes Mal die
-- Default-Font lernen, fremde aber noch markierte Buttons zurücksetzen, erst dann unseren stylen.
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
		if b ~= btn and b._lumenStyled then -- recyceltes, früher gestyltes Frame -> zurücksetzen
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
	if ns.Lumen and ns.Lumen.OpenConfig then ns.Lumen:OpenConfig() end -- öffnet die Suite-Shell
end

-- Aktiven Pool-Button anhand seines Textes finden (die Buttons haben keine festen
-- Referenzen; sie liegen im buttonPool und tragen den lokalisierten Text).
local function findButton(menu, text)
	if not (menu.buttonPool and menu.buttonPool.EnumerateActive) then return nil end
	for b in menu.buttonPool:EnumerateActive() do
		if b.GetText and b:GetText() == text then return b end
	end
end

local function placeUnderAddons(menu, btn)
	local addons = findButton(menu, ADDONS)
	if not (addons and btn) then return end -- kein Addons-Button (z. B. Kiosk) -> Button bleibt unten
	local ai = addons.layoutIndex or 1

	-- Den Button, der ORIGINAL direkt nach Addons kommt (kleinster Index > Addons, ohne uns):
	-- der bekommt die Luft DARUNTER, damit [Addons | Lumen] als Gruppe absetzt.
	local nextBtn, nextIdx
	for b in menu.buttonPool:EnumerateActive() do
		local li = b.layoutIndex
		if li and b ~= btn and li > ai and (not nextIdx or li < nextIdx) then
			nextIdx, nextBtn = li, b
		end
	end

	btn.layoutIndex = ai + 0.5 -- direkt hinter Addons (fraktional -> kein Umnummerieren nötig)
	btn.topPadding  = 0
	addons.topPadding = GROUP_PAD       -- Luft ÜBER der Gruppe
	if nextBtn then nextBtn.topPadding = GROUP_PAD end -- Luft UNTER der Gruppe

	menu:MarkDirty()
	if menu.Layout then menu:Layout() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if not (GameMenuFrame and GameMenuFrame.InitButtons) then return end
	-- InitButtons läuft bei jedem Öffnen (Reset + Neuaufbau) -> Button jedes Mal neu anhängen
	-- und neu einsortieren.
	hooksecurefunc(GameMenuFrame, "InitButtons", function(self)
		if not self.AddButton then return end
		local btn = self:AddButton(LUMEN_TEXT, openLumen)
		styleButton(self, btn)
		placeUnderAddons(self, btn)
	end)
end)
