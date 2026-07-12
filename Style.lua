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
Style.auroraTexture = T .. "lumen-aurora"      -- additive "Nordlicht" glow, wavy curtains (tinted by class color)
Style.auroraDarkTexture = T .. "lumen-aurora-dark" -- MOD layer: darkens the wave TROUGHS so waves read on bright classes too
Style.glowTexture   = T .. "lumen-glow"        -- additive glow, smooth/even variant (same mechanism, no waves)

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

		-- Aurora glow: ADDITIVE layer, tinted with the class color at render time.
		-- A grayscale "curtain" texture (bright bottom -> transparent top) so that,
		-- added onto the class-colored fill, each class shifts into its own luminous
		-- tone (orange->gold, purple->magenta ...) while the top stays plain class
		-- color. Anchored to the health FILL texture so only the filled part glows
		-- and it tracks the fill width (empty/deficit area stays clean and dark).
		local aurora = overlayParent:CreateTexture(nil, "ARTWORK", nil, 0)
		aurora:SetTexture(self.auroraTexture)
		aurora:SetBlendMode("ADD")
		aurora:SetAllPoints(statusbar:GetStatusBarTexture())
		aurora:Hide()

		-- Aurora DARK: a BLACK layer (normal BLEND) whose ALPHA rises only in the wave
		-- TROUGHS near the bottom. Additive crests alone can't show waves on bright
		-- classes (orange + orange = just brighter, no contrast); darkening the troughs
		-- creates visible bands on EVERY class incl. white. Texture = white RGB, alpha
		-- = trough mask (near 0 elsewhere, so no black-out); tinted black here.
		local auroraDark = overlayParent:CreateTexture(nil, "ARTWORK", nil, 1)
		auroraDark:SetTexture(self.auroraDarkTexture)
		auroraDark:SetBlendMode("BLEND")
		auroraDark:SetVertexColor(0, 0, 0)
		auroraDark:SetAllPoints(statusbar:GetStatusBarTexture())
		auroraDark:Hide()

		overlayParent._lumenDepth = { light = light, shadow = shadow, aurora = aurora, auroraDark = auroraDark }
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

-- Aurora mode: additive class-tinted glow instead of the gradient light/shadow.
-- on=true hides the depth layers and shows the glow; strength = glow alpha;
-- texPath swaps the glow texture (aurora waves vs smooth glow); darkTexPath
-- (optional) enables the MOD trough-darkening layer (aurora only, not glow).
function Style:SetAurora(overlayParent, on, strength, texPath, darkTexPath)
	local d = overlayParent._lumenDepth
	if not d or not d.aurora then return end
	if on then
		if texPath then d.aurora:SetTexture(texPath) end
		d.light:Hide(); d.shadow:Hide()
		d.aurora:SetAlpha(strength or 1)
		d.aurora:Show()
		if d.auroraDark then
			if darkTexPath then
				d.auroraDark:SetTexture(darkTexPath)
				d.auroraDark:SetAlpha(strength or 1)
				d.auroraDark:Show()
			else
				d.auroraDark:Hide()
			end
		end
	else
		d.aurora:Hide()
		if d.auroraDark then d.auroraDark:Hide() end
	end
end

-- Tint the aurora glow with the current bar color (class / fill / dispel color).
-- rgb may be a SECRET dispel color in combat -> only ever handed to this C++ setter.
function Style:SetAuroraColor(overlayParent, r, g, b)
	local d = overlayParent._lumenDepth
	if d and d.aurora then d.aurora:SetVertexColor(r, g, b) end
end
