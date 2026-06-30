local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Style (CENTRAL bar look)
--  One place for "our" look: gradient texture + light/shadow layers.
--  Raidframes use it; Unitframes/Target/Focus will too, later on.
--  Adjustments here affect the whole addon.
-- ===========================================================================

local Style = {}
ns.Style = Style

-- Built from the real addon-folder name (ADDON) so the path survives a folder rename.
local T = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
Style.barTexture     = T .. "lumen-gradient"       -- default (bold), tinted by class color
Style.barTextureSoft = T .. "lumen-gradient-soft"  -- soft (subtle)
Style.lightOverlay  = T .. "lumen-light"      -- top light layer
Style.shadowOverlay = T .. "lumen-shadow"     -- bottom shadow layer

-- Apply the Lumen bar look to a StatusBar.
--  statusbar      = the StatusBar (gets the gradient texture)
--  overlayParent  = frame the light/shadow depth layers sit on
--                   (above the fill, below game state like shield/text)
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

-- Set depth-layer strength (1.0 = default, ~0.55 = soft, 0 = off)
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
