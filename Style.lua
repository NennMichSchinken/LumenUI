local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Style (ZENTRALE Balken-Optik)
--  Ein Ort für „unseren" Look: Gradient-Textur + Licht-/Schattenschicht.
--  Raidframes nutzen das; Unitframes/Target/Focus später genauso.
--  Anpassungen hier wirken im ganzen Addon.
-- ===========================================================================

local Style = {}
ns.Style = Style

local T = "Interface\\AddOns\\Lumen\\Textures\\"
Style.barTexture     = T .. "lumen-gradient"       -- Standard (kräftig), per Klassenfarbe getönt
Style.barTextureSoft = T .. "lumen-gradient-soft"  -- Soft (dezent)
Style.lightOverlay  = T .. "lumen-light"      -- obere Lichtschicht
Style.shadowOverlay = T .. "lumen-shadow"     -- untere Schattenebene

-- Lumen-Balkenoptik auf eine StatusBar anwenden.
--  statusbar      = die StatusBar (bekommt die Gradient-Textur)
--  overlayParent  = Frame, auf dem Licht/Schatten als Tiefenschichten liegen
--                   (über der Füllung, unter Spielstatus wie Schild/Text)
function Style:ApplyBar(statusbar, overlayParent)
	statusbar:SetStatusBarTexture(self.barTexture)
	if not overlayParent._lumenDepth then
		local light = overlayParent:CreateTexture(nil, "ARTWORK", nil, -2)
		light:SetTexture(self.lightOverlay)
		light:SetAllPoints(overlayParent)

		local shadow = overlayParent:CreateTexture(nil, "ARTWORK", nil, -1)
		shadow:SetTexture(self.shadowOverlay)
		shadow:SetAllPoints(overlayParent)

		overlayParent._lumenDepth = { light = light, shadow = shadow }
	end
end

-- Tiefenschichten-Stärke setzen (1.0 = Standard, ~0.55 = Soft, 0 = aus)
function Style:SetDepth(overlayParent, strength)
	local d = overlayParent._lumenDepth
	if not d then return end
	if strength and strength > 0 then
		d.light:SetAlpha(strength); d.shadow:SetAlpha(strength)
		d.light:Show(); d.shadow:Show()
	else
		d.light:Hide(); d.shadow:Hide()
	end
end
