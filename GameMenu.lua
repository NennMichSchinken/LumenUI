local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Eintrag im ESC-Spielmenü.
--  Nutzt Blizzards eigene AddButton-API über den InitButtons-Hook: das Spiel
--  übernimmt Layout + Höhe selbst, dadurch koexistiert es sauber mit anderen
--  Addons (z. B. EllesmereUI) ohne übereinanderliegende Buttons.
-- ===========================================================================

local function openLumen()
	if InCombatLockdown() then return end
	HideUIPanel(GameMenuFrame)
	if ns.Lumen and ns.Lumen.OpenConfig then ns.Lumen:OpenConfig() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	if not (GameMenuFrame and GameMenuFrame.InitButtons) then return end
	hooksecurefunc(GameMenuFrame, "InitButtons", function(self)
		if self.AddButton then
			self:AddButton("|cffD4A34FLumen|r", openLumen)
		end
	end)
end)
