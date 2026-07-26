local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell
--  The one and only config UI, following the Lumen design system v2 (flat,
--  square, charcoal surfaces + two-gold rule; see Shell/Tokens). Chrome
--  (header/nav/tabs) + the real screens (Shell/Screens). Opened via /lumen
--  and the ESC-menu button.
-- ===========================================================================

local UI = ns.UI
local S, PANEL = UI.S, UI.PANEL
local Surface, Text, Border, Accent = UI.Surface, UI.Text, UI.Border, UI.Accent
local T = ns.T   -- localization: T("english") -> display in the active language

local Shell = {}
ns.Shell = Shell

-- ---------------------------------------------------------------------------
--  Small build helpers — the primitives now live centrally in Tokens (ns.UI),
--  so Shell chrome AND widget toolkit use the same ones (DRY).
-- ---------------------------------------------------------------------------
local setColor, fill, border, FS = UI.SetColor, UI.Fill, UI.Border, UI.FS
local TEX       = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\icons\\" -- chrome icons (nav, close, eye)
local TEX_ROUND = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\round\\" -- the dot-field corner mask (round-fill-r22)
local TEX_SHELL = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\shell\\" -- chrome bg + glow (dot-tile, dot-vignette, tab-glow)

-- ---------------------------------------------------------------------------
--  Responsive panel scale (ElvUI-style). SetScale is RELATIVE to UIParent, so a
--  fixed 0.80 makes the panel grow/shrink with WoW's UI scale + resolution (huge
--  on one monitor, tiny on another). Instead we anchor the panel to a fraction of
--  UIParent's HEIGHT: since UIParent's height is in the same units as the panel,
--  the panel becomes a CONSTANT fraction of the physical screen on every monitor /
--  UI scale (no GetEffectiveScale needed). The user slider multiplies it linearly.
--  MAX_* clamp overflow on small screens / high user values. Recomputed on show +
--  when the UI scale / display size changes.
local TARGET_H     = 0.92   -- panel fills ~92% of the screen height at user scale 1.0
local MAX_H, MAX_W = 0.95, 0.96
local function computeShellScale()
	-- Optional user multiplier (Global > Interface scale), 0.50 .. 1.30.
	local user = 1
	local g = ns.Lumen and ns.Lumen.db and ns.Lumen.db.global
	if g and type(g.shellScale) == "number" and g.shellScale > 0 then user = g.shellScale end
	local ph, pw = UIParent:GetHeight(), UIParent:GetWidth()
	if not ph or ph <= 0 then return PANEL.scale end   -- safe fallback before layout
	-- Base = fraction of screen height, scaled by the user slider ...
	local s = (TARGET_H * user) * ph / PANEL.h
	-- ... then overflow clamps only (never block the user shrinking it).
	s = math.min(s, MAX_H * ph / PANEL.h)
	if pw and pw > 0 then s = math.min(s, MAX_W * pw / PANEL.w) end
	return s
end
function Shell:ApplyScale()
	if self._frame then self._frame:SetScale(computeShellScale()) end
end

-- ---------------------------------------------------------------------------
--  Sliding indicator (v3) — ONE pill that TWEENS to the active item, mirroring
--  the reference mockup's Navigation component. Nav slides in Y (fixed width),
--  the tab strip slides in X + resizes to the tab width. The motion is a SHORT,
--  self-terminating ease-out (§9-safe: it stops itself after SLIDE_DUR, NOT a
--  persistent OnUpdate). ind._ref = the frame the (ox,oy) offsets are relative to.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
--  Dot-field background (v3) — a fine tiled dot pattern, CONTENT area only
--  (excludes the nav column, which stays plain/flat), behind an inverse
--  vignette (opaque panel-colour centre -> transparent rim) that "erases" the
--  dots back to the background except near the edges: rim-strong, calm centre,
--  frames content without competing with it (mockup 6ab5930f, canvas #dots).
--  Two STATIC baked textures (no OnUpdate/pulse/cursor-repulsion — that part of
--  the reference is explicitly dropped, see design memory NATIVE FEASIBILITY):
--  dot-tile.tga (24px pitch, 3x3 seamless cell with per-dot opacity tiering so
--  the field reads as varied, not flat/plain — matches the mockup's 3-tier
--  diagonal opacity pattern) + dot-vignette.tga (radial erase mask, tinted to
--  the panel colour). Both are clipped to the panel's rounded corners via a
--  MaskTexture (round-fill-r22, straight edges stay opaque -> dots run flush to
--  the true edge, only the 4 corner arcs cut alpha — NOT a flat pixel inset,
--  which read as "walled in"). DOT_ALPHA is the live-tune knob for rim
--  intensity; DOT_COLOR matches the mockup's dot colour (a light neutral grey,
--  not pure white -> subtler than the accent).
-- ---------------------------------------------------------------------------
local DOT_TILE_PX = 72 -- 3x3 cells at 24px pitch (the diagonal opacity tiering needs the full 3x3 unit to stay seamless)
local DOT_ALPHA = 0.35
local DOT_COLOR = { r = 168 / 255, g = 168 / 255, b = 176 / 255 }
-- Aurora ambient (accent map, 2026-07-23, build-order step 1): a soft accent-
-- tinted glow band hugging the TOP of the content area + a faint bottom-left
-- counter-glow (the quiet diagonal). Baked white (aurora.tga, the mockup-
-- approved alphas .43/.32/.21 relative to the shape) and tinted at runtime via
-- SetVertexColor(Accent.color) — so it's near-white in the mono default and
-- takes the user's hue once a colour accent is picked (build-order step 6).
-- AURORA_INTENSITY is the live-tune knob (pure Lua, no re-bake). NOTE the
-- mockup alphas were tuned on a mid-tone accent (Rose); pure white in mono reads
-- a touch stronger, so this may want to sit below 1.0 for the mono default.
local AURORA_INTENSITY = 1.0
-- Aurora-lit dots (accent map step 2): a second dot layer tinted by the accent,
-- masked to the aurora FOOTPRINT (aurora-mask.tga, the normalized-to-1.0 shape)
-- so only the dots UNDER the aurora take colour; everything else stays neutral
-- grey. DOT_LIT_ALPHA = the lit-dot strength (design target base@.50), tuned
-- independently of the glow. Near-white/subtle in mono, the payoff in colour.
local DOT_LIT_ALPHA = 0.50
-- Nav-edge glow (accent map step 3): a crisp 2px accent line over the nav/
-- content divider, alpha baked into nav-edge.tga (top .62 -> gap 42-74% ->
-- bottom .21, mirroring the aurora's left-side profile). NAV_EDGE_INTENSITY
-- scales it; sits over the faint structural divider, tinted by the accent.
local NAV_EDGE_INTENSITY = 1.0
local slideTo = UI.slideTo -- hoisted to UI (Tokens); shared with W.Segment

-- Geometry of `item` in `ref`'s LOCAL coordinate units (what SetPoint offsets on
-- a child of `ref` expect). item and ref share the same effective scale (both
-- inside the 0.80-scaled panel), so their GetLeft/GetTop DELTAS are already in
-- that shared local space — no scale conversion (an earlier ×ratio over-shot the
-- pill by one row/tab). GetWidth/GetHeight are likewise local (= SetSize units).
-- Returns nil while positions are unresolved (panel hidden) -> caller retries.
local itemRectIn = UI.itemRectIn -- hoisted to UI (Tokens); shared with W.Segment

-- ---------------------------------------------------------------------------
--  Nav item (left rail) — v3: text-only, the active pill is the shared sliding
--  indicator; the item only carries the label + a faint hover pill.
-- ---------------------------------------------------------------------------
local function makeNavItem(parent, label, iconFile)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(S.navItemH)
	b:SetPoint("LEFT", parent, "LEFT", 0, 0)
	b:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	-- One state surface, recolored per state (active gold / hover charcoal).
	-- v3 nav mockup (Florian 2026-07-05): a rounded PILL inset from the sidebar
	-- edges instead of the full-width fill.
	local bg = UI.RoundFill(b, Accent.color, "BACKGROUND", nil, UI.RADIUS.md)
	bg:ClearAllPoints()
	bg:SetPoint("TOPLEFT", b, "TOPLEFT", S.navPillPadX, -S.navPillPadY)
	bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -S.navPillPadX, S.navPillPadY)
	bg:Hide()

	-- Lucide module icon (stage 3): white glyph tinted to MATCH the label in
	-- every state (dark on the gold active pill, body grey otherwise). No mipmaps
	-- for TGA -> disable grid snapping so the 32px source stays crisp at ~18px.
	local icon
	if iconFile then
		icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetSize(S.navIconSize, S.navIconSize)
		icon:SetPoint("LEFT", b, "LEFT", S.panelGutter, 0)
		icon:SetTexture(TEX .. iconFile)
		icon:SetSnapToPixelGrid(false)
		icon:SetTexelSnappingBias(0)
		icon:SetVertexColor(Text.Secondary.r, Text.Secondary.g, Text.Secondary.b)
	end

	-- v3 mono nav (mockup): idle = MUTED text, no pill; hover = a faint pill +
	-- brighter text; active = a SUBTLE elevated pill (elementHover) + BRIGHT text
	-- (the sliding-highlight language — bright = active, grey = quiet). No bright
	-- fill / dark-text here (that treatment belongs to the tabs).
	local txt = FS(b, "nav", Text.Description)
	txt:SetPoint("LEFT", icon or b, icon and "RIGHT" or "LEFT", icon and S.navIconGap or S.navGutter, 0)
	txt:SetText(label)

	b._bg, b._txt, b._icon = bg, txt, icon
	b:SetScript("OnEnter", function(self)
		if self._soon then
			if ns.W and ns.W.ShowTextTip then
				ns.W.ShowTextTip(self, T("Coming soon"), T("This module is still in progress and will be unlocked in a later version."))
			end
		elseif not self._active then
			setColor(self._bg, Surface.Input); self._bg:Show()
			self._txt:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
		end
	end)
	b:SetScript("OnLeave", function(self)
		if self._soon then
			if ns.W and ns.W.HideTip then ns.W.HideTip() end
		elseif not self._active then
			self._bg:Hide()
			self._txt:SetTextColor(Text.Description.r, Text.Description.g, Text.Description.b)
		end
	end)
	function b:SetActive(on)
		self._active = on
		self._bg:Hide() -- the active pill is the shared sliding indicator now; item shows only text
		local col = on and Text.Primary or (self._soon and Text.Disabled or Text.Description)
		self._txt:SetTextColor(col.r, col.g, col.b)
		if self._icon then self._icon:SetVertexColor(col.r, col.g, col.b) end
	end
	-- Coming-soon mode: TRUE disabled text (D3; no chip — greyed out + hover tooltip
	-- is enough, a permanent chip would be redundant), never highlighted as active.
	function b:SetComingSoon(on)
		self._soon = on
		if on then
			self._txt:SetTextColor(Text.Disabled.r, Text.Disabled.g, Text.Disabled.b)
			if self._icon then self._icon:SetVertexColor(Text.Disabled.r, Text.Disabled.g, Text.Disabled.b) end
		end
	end
	return b
end

-- ---------------------------------------------------------------------------
--  Tab — v2: active = solid interactive-gold fill (C2) with dark on-gold text
--  (two-gold rule); inactive = element surface + soft border, hover one step up.
-- ---------------------------------------------------------------------------
local function makeTab(parent, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetFrameLevel(parent:GetFrameLevel() + 3) -- above the sliding pill (tabStrip+2) so the label stays on top
	local txt = FS(b, "tab", Text.Description)
	txt:SetText(label)
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:SetHeight(S.tabH)
	-- Width from the string width. On the first game start the custom-font width is
	-- sometimes still 0 (tabs tiny) -> Fit() re-measures once the panel is visible
	-- (OnShow calls it). Anchors LEFT->prev RIGHT pull the positions along automatically.
	function b:Fit() self:SetWidth(math.floor(txt:GetStringWidth() + 44 + 0.5)) end
	b:Fit()

	-- v3: the active pill is the shared sliding indicator (Shell._tabSlider) with
	-- its baked underglow — it slides + resizes to the active tab. The tab itself
	-- only changes TEXT color: active/hover = BRIGHT (#ECEDEF), idle = muted.
	-- (No weight change active/inactive: SemiBold vs Medium have different glyph
	-- widths -> the centered text would jump in the fixed-width button.)
	b._txt = txt
	b:SetScript("OnEnter", function(self)
		if not self._active then self._txt:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self._active then self._txt:SetTextColor(Text.Description.r, Text.Description.g, Text.Description.b) end
	end)
	function b:SetActive(on)
		self._active = on
		local tc = on and Text.Primary or Text.Description
		self._txt:SetTextColor(tc.r, tc.g, tc.b)
	end
	return b
end

-- ---------------------------------------------------------------------------
--  Close X (top right) — v2: flat square, quiet by default (muted line X),
--  hover = element-hover surface + primary-bright X. (The old gold rune ring
--  went with the rune ornaments; ✕ unicode is not reliable in the font.)
-- ---------------------------------------------------------------------------
local function makeCloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(34, 34)

	-- Rounded hover surface (matches the radius scale / other icon-button hovers).
	local hoverFill = UI.RoundFill(b, Surface.Hover, "BACKGROUND", nil, UI.RADIUS.sm)
	hoverFill:Hide()

	-- X: Lucide "x" glyph (stage-3 glyph swap), tinted; brightens on hover.
	local x = b:CreateTexture(nil, "OVERLAY")
	x:SetSize(S.closeGlyph, S.closeGlyph)
	x:SetPoint("CENTER", b, "CENTER", 0, 0)
	x:SetTexture(TEX .. "icon-x")
	x:SetSnapToPixelGrid(false); x:SetTexelSnappingBias(0)
	x:SetVertexColor(Text.Description.r, Text.Description.g, Text.Description.b)

	b:SetScript("OnEnter", function() hoverFill:Show(); x:SetVertexColor(Text.Primary.r, Text.Primary.g, Text.Primary.b) end)
	b:SetScript("OnLeave", function() hoverFill:Hide(); x:SetVertexColor(Text.Description.r, Text.Description.g, Text.Description.b) end)
	b:SetScript("OnClick", onClick)
	return b
end

-- ===========================================================================
--  Building the panel (once)
-- ===========================================================================
-- soon = true: module not ready yet -> nav entry muted + "Coming soon" chip,
-- click only shows the coming-soon placeholder page (no tabs, no activation).
-- `sep = true` starts a new nav group (divider above): suite-wide settings /
-- the frame modules / quality-of-life.
local SECTIONS = {
	{ "Global",      { "Base", "Profile" }, icon = "icon-nav-global" },
	{ "Click-Cast",  { "Bindings" }, icon = "icon-nav-clickcast" },
	{ "Raidframes",  { "Base", "Raid", "Group", "Tracking" }, sep = true, icon = "icon-nav-raidframes" },
	{ "Unitframes",  {}, soon = true, icon = "icon-nav-unitframes" },
	{ "Nameplates",  {}, soon = true, icon = "icon-nav-nameplates" },
	{ "QoL",         { "Base" }, sep = true, icon = "icon-nav-qol" },
}

function Shell:Build()
	if self._frame then return self._frame end

	-- Outer Panel ------------------------------------------------------------
	local f = CreateFrame("Frame", "LumenShellFrame", UIParent)
	f:SetSize(PANEL.w, PANEL.h)
	f:SetScale(computeShellScale())
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	-- Keep the physical size stable when the WoW UI scale / display resolution changes.
	f:RegisterEvent("UI_SCALE_CHANGED")
	f:RegisterEvent("DISPLAY_SIZE_CHANGED")
	f:HookScript("OnEvent", function() Shell:ApplyScale() end)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	-- ESC closes via UISpecialFrames (hides the frame directly, NOT Shell:Hide) — make
	-- sure a listening KeybindButton never survives the close with the keyboard grabbed.
	f:HookScript("OnHide", function() if ns.W and ns.W.StopActiveKeybind then ns.W.StopActiveKeybind() end end)
	-- Coexisting with an Edit Mode session: closing the Shell returns the lit
	-- frame to clean (auras only show while its settings are open).
	f:HookScript("OnHide", function()
		if ns.EditMode and ns.EditMode.session and ns.Raidframes and ns.Raidframes.SetLitPreview then
			ns.Raidframes:SetLitPreview(nil)
		end
	end)
	tinsert(UISpecialFrames, "LumenShellFrame") -- ESC closes
	self._frame = f

	-- Float the select popover on this (non-clipped) panel, otherwise the content
	-- ScrollFrame clips it. RenderContent sets the collection list.
	if ns.W and ns.W.SetMenuHost then ns.W.SetMenuHost(f) end

	-- On show, rebuild the current tab: the first render in Build runs still hidden
	-- (sizes unresolved) -> some cells (e.g. the first dispel color) land wrong until
	-- you switch tabs. Re-render in the visible state.
	f:SetScript("OnShow", function()
		-- Keep the panel at its intended physical size (UI scale / resolution may
		-- have changed while it was closed).
		Shell:ApplyScale()
		-- Coexisting with an Edit Mode session: sit above the frame overlays (same
		-- strata, so Raise() puts the toplevel Shell on top). The Done toolbar
		-- (TOOLTIP) stays above.
		if ns.EditMode and ns.EditMode.session then f:Raise() end
		-- Re-measure tabs: on the first show after game start the font width was maybe
		-- still 0 (tabs tiny). Anchors pull the positions along automatically.
		if Shell._tabButtons then for _, t in ipairs(Shell._tabButtons) do if t.Fit then t:Fit() end end end
		-- v3: snap the sliding indicators to the now-resolved item positions (at
		-- build time the panel was hidden -> item rects were nil). One frame later,
		-- when the subtree has valid rects (mirrors the screen-rebuild timing below).
		C_Timer.After(0, function()
			if Shell._frame and Shell._frame:IsShown() then
				Shell:UpdateNavIndicator(false)
				Shell:UpdateTabIndicator(false)
			end
		end)
		-- The screen built in Build() ran while the panel was hidden (sizes
		-- unresolved) -> rebuild it. ONE FRAME LATER, not inside OnShow: at this
		-- point the subtree has no valid rects yet after /reload — a build now
		-- computes widget layout from width 0 and can stay degenerate until the
		-- next re-layout (slider report 2026-07-03: no track/thumb, blank value
		-- box until scrolling). One frame later the panel is laid out and the
		-- build sees real sizes. Normal re-opens keep their (cached) screens and
		-- skip this entirely.
		if Shell._section and Shell._screen and Shell._screen._builtHidden then
			C_Timer.After(0, function()
				if Shell._frame and Shell._frame:IsShown()
					and Shell._screen and Shell._screen._builtHidden then
					Shell:RenderContent(true)
				end
			end)
		end
	end)

	-- v2: flat main surface (A3), no glow gradient, no rune ornaments.
	-- Rounded main chrome (Florian 2026-07-05): outer radius = inner radius +
	-- padding -> chrome rounds at R_CHROME (16), the cards inside keep 8.
	UI.RoundFill(f, Surface.Window, "BACKGROUND", nil, UI.ROUND_R_CHROME)
	UI.RoundBorder(f, Border.hover, nil, nil, UI.ROUND_R_CHROME)

	-- Dot-field background — CONTENT area only (excludes the nav column entirely;
	-- the sidebar stays plain/flat, Florian 2026-07-22). Clipped to the panel's
	-- own rounded corners via a MaskTexture sharing the SAME 9-slice asset as the
	-- panel fill (round-fill-r22): a 9-slice mask's STRAIGHT edges stay fully
	-- opaque, only the 4 corner arcs cut alpha, so the dots run flush to the true
	-- edge everywhere except right at the curve — a flat pixel inset looked
	-- "walled in" instead of flush against the border (Florian 2026-07-22).
	do
		local mask = f:CreateMaskTexture(nil, "BACKGROUND")
		mask:SetTexture(TEX_ROUND .. "round-fill-r22", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetTextureSliceMargins(23, 23, 23, 23) -- matches Tokens.lua ROUND_MARGIN[22]
		mask:SetAllPoints(f)

		local dotBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
		dotBg:SetTexture(TEX_SHELL .. "dot-tile", true, true)
		dotBg:SetSnapToPixelGrid(false); dotBg:SetTexelSnappingBias(0)
		dotBg:SetPoint("TOPLEFT", f, "TOPLEFT", S.navWidth, 0)
		dotBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		dotBg:SetTexCoord(0, (PANEL.w - S.navWidth) / DOT_TILE_PX, 0, PANEL.h / DOT_TILE_PX)
		dotBg:SetVertexColor(DOT_COLOR.r, DOT_COLOR.g, DOT_COLOR.b, DOT_ALPHA)
		dotBg:AddMaskTexture(mask)

		local dotVign = f:CreateTexture(nil, "BACKGROUND", nil, 2)
		dotVign:SetTexture(TEX_SHELL .. "dot-vignette")
		dotVign:SetSnapToPixelGrid(false); dotVign:SetTexelSnappingBias(0)
		dotVign:SetAllPoints(dotBg)
		dotVign:SetVertexColor(Surface.Window.r, Surface.Window.g, Surface.Window.b, 1)
		dotVign:AddMaskTexture(mask)

		-- Aurora-lit dots: the same dot tile, tinted by the accent, but masked to
		-- the aurora FOOTPRINT so coloured dots appear ONLY where the aurora is
		-- (dots elsewhere stay the neutral grey dotBg). Two masks multiply: the
		-- corner mask (rounded panel) AND the aurora-shape mask.
		local auroraMask = f:CreateMaskTexture(nil, "BACKGROUND")
		auroraMask:SetTexture(TEX_SHELL .. "aurora-mask")
		auroraMask:SetAllPoints(dotBg)

		local dotLit = f:CreateTexture(nil, "BACKGROUND", nil, 3)
		dotLit:SetTexture(TEX_SHELL .. "dot-tile", true, true)
		dotLit:SetSnapToPixelGrid(false); dotLit:SetTexelSnappingBias(0)
		dotLit:SetAllPoints(dotBg)
		dotLit:SetTexCoord(0, (PANEL.w - S.navWidth) / DOT_TILE_PX, 0, PANEL.h / DOT_TILE_PX)
		dotLit:SetVertexColor(Accent.color.r, Accent.color.g, Accent.color.b, DOT_LIT_ALPHA)
		dotLit:AddMaskTexture(mask)
		dotLit:AddMaskTexture(auroraMask)
		f._auroraLit = dotLit -- re-tinted by a future UI.SetAccent (step 6)

		-- Aurora glow OVER the dots (the accent map is specific: aurora on top,
		-- dots peek through — sublevel 4 > the dot/lit layers, still BACKGROUND so
		-- cards/nav on higher-level child frames draw above it). Tinted by the
		-- live accent; near-white in mono, the user's hue once a colour is set.
		local aurora = f:CreateTexture(nil, "BACKGROUND", nil, 4)
		aurora:SetTexture(TEX_SHELL .. "aurora")
		aurora:SetSnapToPixelGrid(false); aurora:SetTexelSnappingBias(0)
		aurora:SetAllPoints(dotBg)
		aurora:SetVertexColor(Accent.color.r, Accent.color.g, Accent.color.b, AURORA_INTENSITY)
		aurora:AddMaskTexture(mask)
		f._auroraTex = aurora -- so a future UI.SetAccent can re-tint it (step 6)
	end

	-- Close X in the top-right corner.
	local closeBtn = makeCloseButton(f, function() Shell:Hide() end)
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
	closeBtn:SetFrameLevel(f:GetFrameLevel() + 50)

	-- Body: Nav-Rail + Main — no footer and no full-width header anymore; the
	-- sidebar runs the FULL panel height and carries the brand block on top
	-- (wordmark moved into the nav column, Florian 2026-07-03).
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

	local nav = CreateFrame("Frame", nil, body)
	nav:SetWidth(S.navWidth)
	nav:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	nav:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	-- v3: the sidebar is SEAMLESS with the panel (same #0B0B0D), so it gets NO own
	-- fill — the panel's rounded fill + border then wrap CONSISTENTLY around the
	-- nav's top/left/bottom (a nav fill, being a child texture, overpainted the
	-- panel border on those edges -> the navbar looked "bigger" / borderless there).
	self._nav = nav
	-- Subtle vertical divider at the nav/content boundary (mockup). Pixel-snap the
	-- THICKNESS only (whole px at scale 0.80 -> never a 0.x hairline); position
	-- stays plain SetPoint (per the border pixel-snap rule). Runs the FULL panel
	-- height (it sits mid-panel at the nav's right edge, clear of the rounded corners).
	local navDiv = nav:CreateTexture(nil, "ARTWORK")
	navDiv:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, 0)
	navDiv:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", 0, 0)
	setColor(navDiv, Border.divider)
	local function snapNavDiv() PixelUtil.SetWidth(navDiv, 1) end
	snapNavDiv(); C_Timer.After(0, snapNavDiv)

	-- v3 sliding nav indicator: ONE subtle elevated pill (#232327) that tweens
	-- vertically to the active module. Created BEFORE the nav items so they (and
	-- their labels) draw ON TOP of it. Positioned by Shell:UpdateNavIndicator.
	local navSlider = CreateFrame("Frame", nil, nav)
	navSlider:SetFrameLevel(nav:GetFrameLevel())
	navSlider._ref = nav
	UI.RoundFill(navSlider, Surface.Hover, "ARTWORK", nil, 12)
	navSlider:Hide()
	self._navSlider = navSlider

	-- Brand block at the top of the sidebar: wordmark + tagline, left-aligned on
	-- the same gutter as the nav labels. v3: NO divider under it (mockup) — brand
	-- is just a positioning container now; the MODULES gap is set explicitly
	-- below (anchored off the tagline's own bottom, not this frame's edge —
	-- anchoring off the frame previously left a big dead gap under a short
	-- tagline, per Florian's mockup-comparison 2026-07-22).
	local brand = CreateFrame("Frame", nil, nav)
	brand:SetHeight(S.navBrandH)
	brand:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
	brand:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, 0)

	local word = FS(brand, "wordmark", Text.Primary) -- v3: off-white (mono), non-clickable
	-- Only the "UI" suffix takes the accent (brand anchor in the nav); "LUMEN"
	-- stays Text.Primary. Colour-escape the tracked tail so it recolours with a
	-- future UI.SetAccent. In mono the accent == off-white, so no visible change.
	local wmHead = UI.Track("LUMEN", " ") -- "L U M E N" (Text.Primary base colour)
	local wmTail = UI.Track("UI", " ")     -- "U I" (accent-escaped)
	local function applyWordmark()
		word:SetText(wmHead .. " " .. UI.ColorCode(Accent.color) .. wmTail .. "|r")
	end
	applyWordmark()
	self._applyWordmarkAccent = applyWordmark -- re-run by a future UI.SetAccent (step 6)
	word:SetPoint("TOPLEFT", brand, "TOPLEFT", S.navGutter, -40) -- v3: pushed down to sit on the tab-row height (more top air), navGutter left inset
	local tag = FS(brand, "tagline", Text.Description)
	tag:SetText(UI.Track("A FOCUSED UI SUITE", " ")) -- v3: uppercase tracked, matches the mockup
	tag:SetPoint("TOPLEFT", word, "BOTTOMLEFT", 0, -9) -- mockup ratio (7px @ 1x -> ~9 design-px)

	-- Settings search — sits between the brand block and the module list ON
	-- PURPOSE: it searches ACROSS modules, and a field inside the content area
	-- would read as "searches this tab".
	-- STRUCTURE: a normal Frame carries the face (fill, border, icons) and the
	-- EditBox is only the text line inside it. Textures parented straight to an
	-- EditBox rendered as blank boxes in-game (Florian 2026-07-26, survived a
	-- client restart, files verified byte-identical to working icons) — every
	-- working glyph in the Shell sits on a plain frame, so this one does too.
	-- Height + edges match the nav PILLS, so the field reads as one of the list.
	local fieldH = S.navItemH - S.navPillPadY * 2
	local sfield = CreateFrame("Frame", nil, nav)
	sfield:SetHeight(fieldH)
	sfield:SetPoint("TOP", tag, "BOTTOM", 0, -S.s9)
	sfield:SetPoint("LEFT", nav, "LEFT", S.navPillPadX, 0)
	sfield:SetPoint("RIGHT", nav, "RIGHT", -S.navPillPadX, 0)
	UI.RoundFill(sfield, Surface.Input, nil, nil, UI.ROUND_R_CTRL)
	-- RoundBorder returns a TABLE of edge textures (a shape can need several),
	-- so recolouring goes through all of them.
	local sboxBorder = UI.RoundBorder(sfield, Border.default, "OVERLAY", nil, UI.ROUND_R_CTRL)
	local function tintBorder(col)
		for _, tex in ipairs(sboxBorder) do setColor(tex, col) end
	end

	-- Magnifier (Lucide "search"): names the field without a caption.
	local sicon = sfield:CreateTexture(nil, "ARTWORK")
	sicon:SetSize(S.navIconSize, S.navIconSize)
	sicon:SetPoint("LEFT", sfield, "LEFT", S.s5, 0)
	sicon:SetTexture(TEX .. "icon-search")
	sicon:SetSnapToPixelGrid(false)
	sicon:SetTexelSnappingBias(0)
	setColor(sicon, Text.Description)

	local textLeft = S.s5 + S.navIconSize + S.s3
	local sbox = CreateFrame("EditBox", nil, sfield)
	sbox:SetPoint("LEFT", sfield, "LEFT", textLeft, 0)
	sbox:SetPoint("RIGHT", sfield, "RIGHT", -(S.s5 + S.closeGlyph + S.s3), 0)
	sbox:SetHeight(fieldH)
	UI:SetFont(sbox, "selectText", Text.Primary)
	sbox:SetAutoFocus(false)
	sbox:SetMaxLetters(40)
	-- The EditBox only spans the text column, so the whole face takes the click.
	sfield:EnableMouse(true)
	sfield:SetScript("OnMouseDown", function() sbox:SetFocus() end)
	local sph = FS(sfield, "selectText", Text.Description)
	sph:SetText(T("Search"))
	sph:SetPoint("LEFT", sfield, "LEFT", textLeft, 0)
	-- Clear glyph, only while there is something to clear.
	local sclear = CreateFrame("Button", nil, sfield)
	sclear:SetSize(fieldH - S.s3 * 2, fieldH - S.s3 * 2)
	sclear:SetPoint("RIGHT", sfield, "RIGHT", -S.s3, 0)
	local sclearTex = sclear:CreateTexture(nil, "OVERLAY")
	sclearTex:SetSize(S.closeGlyph - 4, S.closeGlyph - 4)
	sclearTex:SetPoint("CENTER", sclear, "CENTER", 0, 0)
	sclearTex:SetSnapToPixelGrid(false)
	sclearTex:SetTexelSnappingBias(0)
	sclearTex:SetTexture(TEX .. "icon-x")
	setColor(sclearTex, Text.Description)
	sclear:SetScript("OnEnter", function() setColor(sclearTex, Text.Primary) end)
	sclear:SetScript("OnLeave", function() setColor(sclearTex, Text.Description) end)
	sclear:Hide()
	local function paintSearch()
		local txt = sbox:GetText() or ""
		sph:SetShown(txt == "" and not sbox:HasFocus())
		sclear:SetShown(txt ~= "")
		local live = txt ~= "" or sbox:HasFocus()
		tintBorder(live and Border.hover or Border.default)
		setColor(sicon, live and Text.Secondary or Text.Description)
	end
	sbox:SetScript("OnTextChanged", function(_, user)
		paintSearch()
		if user then Shell:SetSearchQuery(sbox:GetText()) end
	end)
	-- Coming back to the field with a term still in it brings the result list
	-- back (the jump only left the list, it never cleared the query) — that's
	-- what makes working through several hits one after another work.
	sbox:SetScript("OnEditFocusGained", function(self2)
		paintSearch()
		local txt = self2:GetText() or ""
		if txt ~= "" and not Shell:IsSearching() then Shell:SetSearchQuery(txt) end
	end)
	sbox:SetScript("OnEditFocusLost", paintSearch)
	-- ESC clears first and only closes the panel on a second press (a half-typed
	-- query is the more likely thing you want gone).
	sbox:SetScript("OnEscapePressed", function(self2)
		if (self2:GetText() or "") ~= "" then
			self2:SetText(""); Shell:SetSearchQuery("")
		end
		self2:ClearFocus()
	end)
	sbox:SetScript("OnEnterPressed", function() Shell:ActivateSearchSelection() end)
	-- Arrow keys walk the results without leaving the field (the pattern Blizzard's
	-- own group-finder search box uses).
	sbox:SetScript("OnArrowPressed", function(_, key)
		if key == "UP" then Shell:MoveSearchSelection(-1)
		elseif key == "DOWN" then Shell:MoveSearchSelection(1) end
	end)
	sclear:SetScript("OnClick", function()
		sbox:SetText(""); Shell:SetSearchQuery(""); sbox:ClearFocus()
	end)
	self._search = sbox
	self._searchPaint = paintSearch
	paintSearch()

	-- "MODULES" caption above the nav list (v3 mockup, stage 3): a small tracked
	-- uppercase label, same left gutter as the nav items (tag is already inset by
	-- navGutter, so x=0 here). Anchored off the SEARCH field now (it took the gap
	-- that used to sit under the tagline).
	local navLabel = FS(nav, "navGroupLabel", Text.Description)
	navLabel:SetText(UI.Track("MODULES", " "))
	navLabel:SetPoint("TOPLEFT", tag, "BOTTOMLEFT", 0, -(S.s9 + fieldH + S.s9))

	-- Version chip (stage 3): muted "v<x.y.z>" pinned to the very bottom-right of
	-- the sidebar so it never floats when the preview button is hidden (Florian
	-- 2026-07-05: chip + button swapped). Read live from the .toc metadata.
	local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or ""
	local chipH = S.tabBadgeH - 4
	local hasChip = ver ~= ""
	if hasChip then
		local chip = CreateFrame("Frame", nil, nav)
		local cfs = FS(chip, "caption", Text.Description)
		cfs:SetText("v" .. ver)
		cfs:SetPoint("CENTER", chip, "CENTER", 0, 0)
		chip:SetSize(math.ceil(cfs:GetStringWidth()) + S.s5, chipH)
		chip:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -S.panelGutter, S.panelGutter)
		UI.RoundBorder(chip, Border.default, "OVERLAY", nil, UI.RADIUS.xs)
	end

	-- Edit Mode button (v2): a suite-global action, so it lives in the global
	-- chrome — pinned above the version chip, ALWAYS visible on every screen.
	-- Opens the Lumen edit session (Shell hides, mover overlays + toolbar show).
	local emY = hasChip and (S.panelGutter + chipH + S.s4) or S.panelGutter
	local emBtn = ns.W.Button(nav, { text = T("Edit Mode"), variant = "neutral", icon = "icon-move",
		onClick = function() if ns.EditMode then ns.EditMode:OpenSession() end end })
	emBtn:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", S.panelGutter, emY)
	emBtn:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -S.panelGutter, emY)

	-- Preview toggle (v3 mockup): ONE central point to open/close the preview
	-- window. Stacks ABOVE the Edit Mode button. Hidden on screens without a
	-- registered preview; label follows the open state (_UpdateDock keeps it
	-- current).
	local pvY = emY + UI.WIDGET.buttonH + S.s4
	local pvBtn = ns.W.Button(nav, { text = "", variant = "neutral",
		onClick = function() Shell:TogglePreview() end })
	pvBtn:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", S.panelGutter, pvY)
	pvBtn:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -S.panelGutter, pvY)
	pvBtn:Hide()
	self._previewBtn = pvBtn

	local main = CreateFrame("Frame", nil, body)
	main:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
	main:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

	-- Vertical nav divider: on MAIN (draws over nav + its buttons), left edge.
	local nsep = main:CreateTexture(nil, "OVERLAY")
	nsep:SetWidth(1); nsep:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
	nsep:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, 0); setColor(nsep, Border.divider)

	-- Nav-edge glow: a crisp 2px accent line over the divider, its vertical alpha
	-- profile baked into nav-edge.tga (strong at top, gap in the middle, faint at
	-- the bottom — the aurora's left-side presence). Snap the WIDTH only (whole px
	-- at scale 0.80); position plain per the border pixel-snap rule. Sits over the
	-- structural divider so the accent shows only where the aurora is.
	local navEdge = main:CreateTexture(nil, "OVERLAY", nil, 1)
	navEdge:SetTexture(TEX_SHELL .. "nav-edge")
	navEdge:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
	navEdge:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, 0)
	navEdge:SetVertexColor(Accent.color.r, Accent.color.g, Accent.color.b, NAV_EDGE_INTENSITY)
	local function snapNavEdge() PixelUtil.SetWidth(navEdge, 2) end
	snapNavEdge(); C_Timer.After(0, snapNavEdge)
	f._navEdge = navEdge -- re-tinted by a future UI.SetAccent (step 6)

	-- Tab-Strip (main starts at the panel top). Air ABOVE the strip = the same
	-- contentTopGap as BELOW it (Florian 2026-07-05: unequal gaps read like
	-- something was missing between tabs and the first card).
	local tabStrip = CreateFrame("Frame", nil, main)
	tabStrip:SetHeight(S.tabH)
	tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", S.panelGutter, -S.contentTopGap)
	tabStrip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -S.panelGutter, -S.contentTopGap)

	-- v3: solid rounded backing behind the tabs, so the tab row reads as a
	-- distinct strip (esp. later over the dot field). COMPACT — hugs the tabs:
	-- LEFT + padding frames the first tab, RIGHT follows the last tab (re-anchored
	-- per section in RebuildTabs). Created BEFORE the tabs so they draw on top.
	local tabStripBg = CreateFrame("Frame", nil, tabStrip)
	tabStripBg:SetFrameLevel(tabStrip:GetFrameLevel() + 1) -- above the strip frame, below the slider
	-- v3: fully-round capsule (rounded-full, like the mockup) via the pill assets
	-- at the exact strip height (round-fill 9-slice can't do radius > half-height).
	UI.PillFill(tabStripBg, Surface.Card, "BACKGROUND", S.tabH)
	UI.PillBorder(tabStripBg, Border.default, "BORDER", S.tabH)
	tabStripBg:Hide()
	self._tabStripBg = tabStripBg

	-- v3 sliding tab pill: ONE semi-transparent white pill (~10%) + baked underglow
	-- that tweens + resizes to the active tab. Created BEFORE the tabs so they draw
	-- on top. Positioned by Shell:UpdateTabIndicator.
	local tabSlider = CreateFrame("Frame", nil, tabStrip)
	tabSlider:SetFrameLevel(tabStrip:GetFrameLevel() + 2) -- above the strip backing, below the tab text
	tabSlider._ref = tabStrip
	local tglow = tabSlider:CreateTexture(nil, "BACKGROUND")
	tglow:SetTexture(TEX_SHELL .. "tab-glow")
	tglow:SetSnapToPixelGrid(false); tglow:SetTexelSnappingBias(0)
	tglow:SetPoint("TOPLEFT", tabSlider, "TOPLEFT", -S.tabGlowX, S.tabGlowTop)
	tglow:SetPoint("BOTTOMRIGHT", tabSlider, "BOTTOMRIGHT", S.tabGlowX, -S.tabGlowBot)
	local gl = Accent.glow
	tglow:SetVertexColor(gl.r, gl.g, gl.b, gl.a) -- accent glow (mono = white; tints automatically if a colour accent is set); softness baked into the alpha
	local tfill = UI.PillFill(tabSlider, Accent.wash, "ARTWORK", S.tabH - S.tabStripPad * 2) -- accent-wash capsule (fully round)
	tabSlider:Hide()
	self._tabSlider = tabSlider
	self._tabGlow, self._tabFill = tglow, tfill -- re-tinted live by Shell:RefreshAccent

	-- Info badge on the right of the tab strip (v2 refinement no. 4, e.g. the
	-- active spec on the Tracking tab). Screens fill it via Shell:SetTabBadge;
	-- RenderContent clears it before every build, so it never leaks across tabs.
	local badge = CreateFrame("Frame", nil, tabStrip)
	badge:SetHeight(S.tabBadgeH)
	-- Sit LEFT of the close button so they never overlap: the X (34px @ panel
	-- TOPRIGHT -14) has its left edge 34+14=48px from the panel's right, while
	-- the tab strip's right is only panelGutter in — so pull the badge left past
	-- the X + a comfortable gap. Vertical stays centered on the tab strip (RIGHT anchor).
	badge:SetPoint("RIGHT", tabStrip, "RIGHT", -(34 + 14 - S.panelGutter + S.s8), 0)
	UI.RoundFill(badge, Surface.Input, nil, nil, UI.RADIUS.xs)
	UI.RoundBorder(badge, Border.default, "OVERLAY", nil, UI.RADIUS.xs)
	local badgeTxt = FS(badge, "caption", Text.Description)
	badgeTxt:SetPoint("CENTER", badge, "CENTER", 0, 0)
	badge._txt = badgeTxt
	badge:Hide()
	self._tabBadge = badge

	-- Content area: scrollable (screens are taller than the fixed content height).
	-- ScrollFrame + scroll child; the screens build into the child. Slim gold
	-- scrollbar on the right in the gutter (mouse wheel + draggable thumb).
	-- Preview dock: satellite window attached to the panel (right of it for
	-- vertical previews, below it for horizontal ones, UI.WIDGET.pvDockGap
	-- apart so it reads as its own window). Screens register a content builder
	-- in ns.ScreenPreviews[key]; the module sizes it via Shell:SetDockLayout.
	-- Grab it anywhere free to drag it off; dropping it near its docked spot
	-- snaps it back on (float position persists in db.profile.global).
	local MW = UI.WIDGET
	local dock = CreateFrame("Frame", nil, f)
	dock:SetSize(MW.pvStageMinW, MW.pvMinStageH)
	-- Fill/border kept as handles: Shell:SetDockChrome strips them for the
	-- preview's "Backdrop" filter (frames float freely on the screen).
	dock._fill = UI.RoundFill(dock, Surface.Window, nil, nil, UI.ROUND_R_CHROME)
	dock._edges = UI.RoundBorder(dock, Border.hover, nil, nil, UI.ROUND_R_CHROME)
	-- (The former gold accent bar on the panel-facing edge was removed with the
	-- rounded chrome — Florian 2026-07-05.)
	dock:EnableMouse(true)
	dock:SetMovable(true)
	dock:SetClampedToScreen(true)
	-- Well above the panel content: as a plain child (level panel+1) the dock
	-- rendered UNDERNEATH main's nested children whenever it overlapped the
	-- panel (floating/clamped) — content shone through its background.
	dock:SetFrameLevel(f:GetFrameLevel() + 80)
	dock:RegisterForDrag("LeftButton")
	dock:SetScript("OnDragStart", function(d) d:StartMoving() end)
	dock:SetScript("OnDragStop", function(d)
		d:StopMovingOrSizing()
		Shell:_DockDropCheck()
	end)
	dock:Hide()
	self._dock = dock

	local scroll = CreateFrame("ScrollFrame", nil, main)
	scroll:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -S.contentTopGap)
	scroll:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -S.panelGutter, S.panelGutter)
	scroll:EnableMouseWheel(true)
	self._scroll = scroll

	local scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(1, 1)
	scroll:SetScrollChild(scrollChild)
	self._scrollChild = scrollChild
	self._content = scrollChild -- compat: screens anchor into this child

	-- Scroll child follows the width of the ScrollFrame (mandatory, else 0 wide).
	scroll:SetScript("OnSizeChanged", function(self2, w) scrollChild:SetWidth(w or self2:GetWidth() or 1) end)

	-- Scrollbar (to the right of the ScrollFrame, in the panel gutter).
	local sbTrack = CreateFrame("Frame", nil, main)
	sbTrack:SetWidth(S.scrollBarW)
	sbTrack:SetPoint("TOPLEFT", scroll, "TOPRIGHT", S.scrollBarGap, 0)
	sbTrack:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", S.scrollBarGap, 0)
	local trackTex = sbTrack:CreateTexture(nil, "ARTWORK")
	trackTex:SetAllPoints(sbTrack); setColor(trackTex, Surface.Input)

	-- Thumb anchored via TOP (= horizontally centered), width separate -> can widen
	-- on hover (easier to grab). updateBar sets height/position.
	local thumb = CreateFrame("Frame", nil, sbTrack)
	thumb:SetWidth(S.scrollBarW)
	thumb:EnableMouse(true)
	-- Wider grab zone than the thin visual line (Florian 2026-07-22: scrollBarW
	-- halved to 2 for a quieter look; without this the thumb would be fiddly to
	-- catch with the mouse before the hover-widen even triggers). Mirrors the
	-- slider-thumb hit-rect pattern in Widgets.lua.
	thumb:SetHitRectInsets(-4, -4, 0, 0)
	thumb._w = S.scrollBarW
	local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
	thumbTex:SetAllPoints(thumb)
	local function paintThumb(a) thumbTex:SetColorTexture(Accent.color.r, Accent.color.g, Accent.color.b, a) end
	paintThumb(0.55)
	self._paintThumb = paintThumb -- re-tinted to the idle alpha by Shell:RefreshAccent

	local function updateBar()
		-- Derive the range from the scroll child height (always current) instead of
		-- GetVerticalScrollRange(), which updates a frame LATE after a content-height
		-- change (e.g. collapsing the aura section) -> stale -> oversized/overflowing thumb.
		local h = scroll:GetHeight() or 1
		local range = math.max(0, (scrollChild:GetHeight() or 0) - h)
		if range <= 0.5 or h <= 1 then sbTrack:Hide(); return end
		sbTrack:Show()
		local total = h + range
		local th = math.max(24, (h / total) * h)
		thumb:SetHeight(th)
		thumb:SetWidth(thumb._w)
		local pos = (scroll:GetVerticalScroll() or 0) / range
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", sbTrack, "TOP", 0, -pos * (h - th))
	end
	self._updateBar = updateBar

	local function scrollBy(delta)
		local range = scroll:GetVerticalScrollRange() or 0
		local new = math.max(0, math.min(range, (scroll:GetVerticalScroll() or 0) - delta))
		scroll:SetVerticalScroll(new); updateBar()
	end
	scroll:SetScript("OnMouseWheel", function(_, d) scrollBy(d * 48) end)
	scroll:SetScript("OnScrollRangeChanged", updateBar)

	-- Drag the thumb: on grab, remember the grab offset (cursor↔thumb top edge) so
	-- the thumb doesn't jump to the cursor center (felt "janky").
	local function thumbDrag()
		local _, cy = GetCursorPosition()
		local sc = sbTrack:GetEffectiveScale()
		if not sc or sc == 0 then return end
		cy = cy / sc
		local top, h = sbTrack:GetTop(), scroll:GetHeight() or 1
		local denom = h - (thumb:GetHeight() or 0)
		if not top or denom <= 0 then return end
		local desiredTop = cy + (thumb._grabOff or 0)
		local rel = math.max(0, math.min(1, (top - desiredTop) / denom))
		scroll:SetVerticalScroll(rel * (scroll:GetVerticalScrollRange() or 0)); updateBar()
	end
	thumb:SetScript("OnMouseDown", function(self2)
		local _, cy = GetCursorPosition()
		local sc = sbTrack:GetEffectiveScale() or 1
		self2._grabOff = (thumb:GetTop() or 0) - (cy / (sc ~= 0 and sc or 1))
		self2._dragging = true
		self2:SetScript("OnUpdate", thumbDrag)
	end)
	local function endDrag(self2)
		self2._dragging = false
		self2:SetScript("OnUpdate", nil)
		if not self2:IsMouseOver() then self2._w = S.scrollBarW; paintThumb(0.55); updateBar() end
	end
	thumb:SetScript("OnMouseUp", endDrag)
	thumb:SetScript("OnHide", function(self2) self2._dragging = false; self2:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnEnter", function(self2) self2._w = S.scrollBarW + 3; paintThumb(0.85); updateBar() end)
	thumb:SetScript("OnLeave", function(self2)
		if not self2._dragging then self2._w = S.scrollBarW; paintThumb(0.55); updateBar() end
	end)

	-- Nav-Buttons. Entries with `sep = true` start a new GROUP (suite-wide /
	-- frame modules / QoL) — a fine divider line separates it from the one above.
	self._navButtons = {}
	local prev
	for i, sec in ipairs(SECTIONS) do
		local nb = makeNavItem(nav, sec[1]) -- v3: text-only nav (icons dropped per the mockup; pass sec.icon to restore)
		if prev then
			-- v3: uniform spacing, NO group divider lines (mockup) — sec.sep kept in
			-- SECTIONS for later but no longer draws a line or an extra gap.
			nb:SetPoint("TOP", prev, "BOTTOM", 0, -S.navItemGap)
		else
			nb:SetPoint("TOP", navLabel, "BOTTOM", 0, -S.navGroupGap)
		end
		nb._index = i
		if sec.soon then nb:SetComingSoon(true) end
		nb:SetScript("OnClick", function() Shell:SelectSection(i) end)
		self._navButtons[i] = nb
		prev = nb
	end

	self._tabStrip = tabStrip
	self._tabButtons = {}   -- active slice (buttons of the current section)
	self._tabPool = {}      -- reusable tab buttons (perf audit E: no per-switch churn)
	-- Last active tab per section (session-only): switching sections returns you
	-- to where you were, e.g. Raidframes/Tracking -> Click-Cast -> back lands on
	-- Tracking again (saves a click when bouncing between two work areas).
	self._lastTab = {}

	-- Cached screens can go stale on a spec change (Tracking list, Click-Cast
	-- spell sources and the spec badge are spec-bound) -> drop the cache; if the
	-- panel is open, rebuild the visible screen right away.
	local specWatch = CreateFrame("Frame", nil, f)
	specWatch:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	specWatch:SetScript("OnEvent", function(_, _, unit)
		if unit and unit ~= "player" then return end
		if f:IsShown() then Shell:RenderContent(true)
		else Shell:InvalidateScreenCache() end
	end)

	-- Initial state
	Shell:SelectSection(3) -- Raidframes (like the prototype default)
	return f
end

-- Fill the tab strip for the current section. Tab buttons are POOLED (perf
-- audit E): created once per slot, relabeled on section switch — the old
-- rebuild orphaned + recreated them (WoW never frees frames). Slot anchors
-- (left -> previous right) are set once; label changes pull them along.
function Shell:RebuildTabs(sectionIndex)
	local tabs = SECTIONS[sectionIndex][2]
	local pool = self._tabPool
	wipe(self._tabButtons)
	for i, label in ipairs(tabs) do
		local tb = pool[i]
		if not tb then
			tb = makeTab(self._tabStrip, label)
			if i > 1 then tb:SetPoint("LEFT", pool[i - 1], "RIGHT", S.s3, 0)
			else tb:SetPoint("LEFT", self._tabStrip, "LEFT", S.tabStripPad, 0) end -- v3: inset by the strip padding
			tb:SetScript("OnClick", function(selfBtn) Shell:SelectTab(selfBtn._index) end)
			pool[i] = tb
		end
		tb._index = i
		tb._txt:SetText(label)
		tb:Fit()
		tb:SetActive(false)
		tb:Show()
		self._tabButtons[i] = tb
	end
	for i = #tabs + 1, #pool do pool[i]:Hide() end
	-- v3: re-anchor the solid strip backing to hug this section's tabs. The RIGHT
	-- anchor rides the last tab frame, so it auto-follows the deferred Fit() resize.
	local last = self._tabButtons[#tabs]
	if last then
		local sb = self._tabStripBg
		sb:ClearAllPoints()
		sb:SetPoint("TOPLEFT", self._tabStrip, "TOPLEFT", 0, 0)
		sb:SetPoint("BOTTOMLEFT", self._tabStrip, "BOTTOMLEFT", 0, 0)
		sb:SetPoint("RIGHT", last, "RIGHT", S.tabStripPad, 0)
		sb:Show()
	else
		self._tabStripBg:Hide()
	end
	-- Re-measure one frame later: on the very first build (panel still hidden /
	-- fonts maybe not ready) GetStringWidth returns 0 -> tiny tabs.
	C_Timer.After(0, function()
		for _, t in ipairs(self._tabButtons) do if t.Fit then t:Fit() end end
		self:UpdateTabIndicator(false) -- snap the pill to the final (post-Fit) tab widths
	end)
	-- Return to the tab that was active the last time this section was open
	-- (session memory; falls back to the first tab).
	Shell:SelectTab(self._lastTab[sectionIndex] or 1)
end

-- v3 sliding indicators: reposition the nav / tab pill to the active item.
-- Geometry read from the item frames (scale-safe via itemRectIn). animate=false
-- at build/show time (positions just resolved), animate=true on a user click.
-- Silently no-ops while positions are unresolved (panel hidden) -> OnShow retries.
function Shell:UpdateNavIndicator(animate)
	local ind = self._navSlider
	if not ind then return end
	local sec = SECTIONS[self._section or 0]
	local item = self._navButtons[self._section or 0]
	if (not item) or (sec and sec.soon) then ind:Hide(); ind._cx = nil; return end
	local ox, oy, w, h = itemRectIn(item, self._nav)
	if not ox then return end
	slideTo(ind, ox + S.navPillPadX, oy - S.navPillPadY, w - S.navPillPadX * 2, h - S.navPillPadY * 2, animate)
end

function Shell:UpdateTabIndicator(animate)
	local ind = self._tabSlider
	if not ind then return end
	local item = self._tabButtons[self._tab or 0]
	if not item then ind:Hide(); ind._cx = nil; return end
	local ox, oy, w, h = itemRectIn(item, self._tabStrip)
	if not ox then return end
	slideTo(ind, ox, oy - S.tabStripPad, w, h - S.tabStripPad * 2, animate)
end

function Shell:SelectSection(index)
	self._section = index
	local sec = SECTIONS[index]
	-- Never highlight coming-soon modules as active (they stay muted + chip).
	for i, nb in ipairs(self._navButtons) do nb:SetActive(i == index and not sec.soon) end
	self:UpdateNavIndicator(self._frame and self._frame:IsShown())
	if sec.soon then
		-- No tabs, no tab selection — render the placeholder page directly.
		for _, t in ipairs(self._tabPool) do t:Hide() end
		if self._tabStripBg then self._tabStripBg:Hide() end
		if self._tabSlider then self._tabSlider:Hide(); self._tabSlider._cx = nil end
		wipe(self._tabButtons)
		self._tab = nil
		self:RenderContent()
	else
		self:RebuildTabs(index)
	end
end

function Shell:SelectTab(index)
	self._tab = index
	if self._section then self._lastTab[self._section] = index end
	for i, tb in ipairs(self._tabButtons) do tb:SetActive(i == index) end
	self:UpdateTabIndicator(self._frame and self._frame:IsShown())
	self:RenderContent()
end

-- Open the Shell straight to a section (and optional tab) by NAME — used by the
-- Edit Mode flyout's "Open settings" jump for large modules. Name lookup keeps
-- callers stable if the SECTIONS order ever changes.
function Shell:OpenTo(sectionName, tabName)
	-- Cold open? On a warm Shell the normal path is fine; but when OpenTo SHOWS the
	-- panel and immediately selects a section, the target screen is built in the same
	-- tick the panel became visible -> IsShown() is already true, so RenderContent
	-- marks it _builtHidden=false and the Build()-OnShow rebuild safety net (which
	-- only re-runs while _screen._builtHidden) is disarmed by this section switch.
	-- Result: unresolved ScrollFrame widths -> blank slider values / missing first
	-- row, and it even gets cached. Re-render once the layout settles (mirrors the
	-- OnShow safety net; RenderContent(true) invalidates the degenerate cached build).
	local wasShown = self._frame and self._frame:IsShown()
	self:Show()
	for i, sec in ipairs(SECTIONS) do
		if sec[1] == sectionName then
			self:SelectSection(i)
			if tabName and sec[2] then
				for j, t in ipairs(sec[2]) do
					if t == tabName then self:SelectTab(j) break end
				end
			end
			if not wasShown then
				C_Timer.After(0, function()
					if self._frame and self._frame:IsShown() then self:RenderContent(true) end
				end)
			end
			return
		end
	end
end

-- ---------------------------------------------------------------------------
--  Click-to-configure: jump from a preview element straight to its settings
--  card. Screen builders register their jumpable cards (RegisterJumpCard);
--  JumpTo opens section/tab, lets the screen pre-open the target disclosure
--  (ns.ShellJumpPrep, set in Screens.lua), then scrolls to the card and
--  flashes its border gold as confirmation.
-- ---------------------------------------------------------------------------
function Shell:RegisterJumpCard(key, frame)
	local scr = self._screen
	if not (scr and key and frame) then return end
	scr._jumpCards = scr._jumpCards or {}
	scr._jumpCards[key] = frame
end

-- Short gold border pulse on the target card (build lazily, reuse per card).
local function flashCard(card)
	local fl = card._jumpFlash
	if not fl then
		fl = CreateFrame("Frame", nil, card)
		fl:SetAllPoints(card)
		fl:SetFrameLevel(card:GetFrameLevel() + 9)
		UI.RoundBorder(fl, UI.Accent.color, "OVERLAY", nil, UI.RADIUS.lg)
		local ag = fl:CreateAnimationGroup()
		local a = ag:CreateAnimation("Alpha")
		a:SetFromAlpha(1); a:SetToAlpha(0)
		a:SetStartDelay(0.5); a:SetDuration(0.9)
		ag:SetScript("OnFinished", function() fl:Hide() end)
		fl._ag = ag
		card._jumpFlash = fl
	end
	fl:SetAlpha(1); fl:Show()
	fl._ag:Stop(); fl._ag:Play()
end

-- Same pulse for a single settings ROW (search jump): tighter radius, and it
-- also washes the row so a thin line is actually noticeable in a full card.
local function flashRow(row)
	local fl = row._searchFlash
	if not fl then
		fl = CreateFrame("Frame", nil, row)
		fl:SetPoint("TOPLEFT", row, "TOPLEFT", -S.s3, S.s2)
		fl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", S.s3, -S.s2)
		fl:SetFrameLevel(row:GetFrameLevel() + 9)
		UI.RoundFill(fl, Accent.wash, "BACKGROUND", nil, UI.RADIUS.sm)
		UI.RoundBorder(fl, Accent.color, "OVERLAY", nil, UI.RADIUS.sm)
		local ag = fl:CreateAnimationGroup()
		local a = ag:CreateAnimation("Alpha")
		a:SetFromAlpha(1); a:SetToAlpha(0)
		a:SetStartDelay(0.7); a:SetDuration(1.1)
		ag:SetScript("OnFinished", function() fl:Hide() end)
		fl._ag = ag
		row._searchFlash = fl
	end
	fl:SetAlpha(1); fl:Show()
	fl._ag:Stop(); fl._ag:Play()
end

function Shell:JumpTo(sectionName, tabName, cardKey)
	if ns.ShellJumpPrep then ns.ShellJumpPrep(sectionName, tabName, cardKey) end
	-- The prep may have opened a disclosure a cached screen doesn't show yet —
	-- drop the cache so the target screen rebuilds in the prepared state.
	self:InvalidateScreenCache()
	self:OpenTo(sectionName, tabName)
	self:_ResolveJump(cardKey)
end

-- Scroll + flash once the target card has a resolved rect. The cold-open path
-- re-renders one frame later (OpenTo safety net), so retry across a few ticks
-- and always look the card up on the CURRENT screen.
function Shell:_ResolveJump(cardKey)
	if not cardKey then return end
	local tries = 0
	local function attempt()
		if not (self._frame and self._frame:IsShown()) then return end
		local scr = self._screen
		local card = scr and scr._jumpCards and scr._jumpCards[cardKey]
		local childTop = self._scrollChild and self._scrollChild:GetTop()
		if not (card and card:GetTop() and childTop) then
			tries = tries + 1
			if tries < 8 then C_Timer.After(0, attempt) end
			return
		end
		if self._scroll then
			local viewH = self._scroll:GetHeight() or 0
			local maxScroll = math.max(0, (self._scrollChild:GetHeight() or 0) - viewH)
			local off = childTop - card:GetTop()
			self._scroll:SetVerticalScroll(math.min(maxScroll, math.max(0, off - 20)))
			if self._updateBar then self._updateBar() end
		end
		flashCard(card)
	end
	C_Timer.After(0, attempt)
end

-- Repaint the current screen's card-eye glyphs from their get() state — called
-- by the preview's central eye popover (and previewRefresh) after an external
-- toggle, so card eyes and popover never diverge.
function Shell:RepaintEyes()
	local scr = self._screen
	if not (scr and scr._eyePaints) then return end
	for _, p in ipairs(scr._eyePaints) do p() end
end

-- Apply a composed badge text to the tab-strip badge (internal; used by
-- SetTabBadge and by the screen cache when re-showing a cached screen).
function Shell:_ApplyBadge(text)
	local b = self._tabBadge
	if not b then return end
	b._txt:SetText(text)
	b:SetWidth(math.ceil(b._txt:GetStringWidth()) + S.tabBadgePad * 2)
	b:Show()
end

-- v2 refinement no. 4: screens set a right-side info badge in the tab strip
-- (e.g. "Active spec: Restoration"). `label` renders muted, `value` in primary
-- text. Called from a screen builder; RenderContent hides the badge before
-- every build, so a screen without a badge never inherits a stale one. The
-- composed text is recorded in _lastBadge so the screen cache can restore it.
function Shell:SetTabBadge(label, value)
	if self._warming then return end -- index warm-up: collect labels only, touch no live chrome
	if not self._tabBadge then return end
	if not label or label == "" then
		self._lastBadge = nil
		self._tabBadge:Hide()
		return
	end
	local text = label
	if value and value ~= "" then
		text = label .. " " .. UI.ColorCode(Text.Primary) .. value .. "|r"
	end
	self._lastBadge = text
	self:_ApplyBadge(text)
end

-- ---------------------------------------------------------------------------
--  Layout stack: stacks widgets top to bottom into a holder. `place`
--  = full width (TOPLEFT/RIGHT), `placeLeft` = left-aligned with own width
--  (for narrow fields). Screens (Shell/Screens.lua) build exclusively on top of it.
-- ---------------------------------------------------------------------------
local function newStack(holder)
	local y = -4
	local stack = {}
	function stack:place(widget, h, gap)
		widget:SetParent(holder)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
		widget:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, y)
		if h then widget:SetHeight(h) end
		y = y - (h or widget:GetHeight()) - (gap or 22)
	end
	function stack:placeLeft(widget, h, gap)
		widget:SetParent(holder)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
		if h then widget:SetHeight(h) end
		y = y - (h or widget:GetHeight()) - (gap or 22)
	end
	function stack:gap(dy) y = y - (dy or 8) end
	function stack:y() return y end
	function stack:height() return -y + S.panelGutter end

	-- Box primitive: draws a card (background + gold hairline [+ optional header bar
	-- with gold accent + title]) at position `topY`, anchored to `holder` with outer
	-- indent `outerPad`; rows are additionally indented by `pad`. Returns an INNER
	-- stacker (place/placeLeft/gap/y/subgroup/close). `close()` sets the box height
	-- and returns the bottom iy; the caller advances its cursor. This way section
	-- (main card with header) AND subgroup (lighter sub-box without header) use
	-- EXACTLY the same code (DRY; nestable).
	local function makeBox(topY, o)
		local M = UI.WIDGET
		local outerPad, pad = o.outerPad or 0, o.pad
		-- Band cards (card grid system) build into their own column wrapper
		-- instead of the stack holder; everything else is identical.
		local host = o.holder or holder

		local panel = CreateFrame("Frame", nil, host)
		-- Card as background layer: frame level at host level so the later-created
		-- content frames (siblings, NOT children of the card) render above it.
		panel:SetFrameLevel(host:GetFrameLevel())
		panel:SetPoint("TOPLEFT", host, "TOPLEFT", outerPad, topY)
		panel:SetPoint("TOPRIGHT", host, "TOPRIGHT", -outerPad, topY)
		-- Rounded corners (o.round = true | "top" | "bottom"): 9-slice fill+ring
		-- from Tokens instead of the square fill + 4 snapped hairlines. Section/
		-- band cards default to round; subgroups (inset boxes) stay square until
		-- the widget rounding pass.
		if o.round then
			local shape = (o.round ~= true) and o.round or nil
			UI.RoundFill(panel, o.fill, nil, shape)
			UI.RoundBorder(panel, o.border, "OVERLAY", shape)
		else
			fill(panel, o.fill)
			-- Frame on OVERLAY: the header bar (hbar, ARTWORK) would otherwise sit ABOVE the
			-- frame and cover the thin gold line on top + right in the header area.
			border(panel, o.border, 1, "OVERLAY")
		end

		-- Header: heavy (section = gold bar + accent + Cinzel title) | light
		-- (sub-box = only a small gold label) | none (top = inner padding `pad`,
		-- symmetric to the bottom edge).
		local headerH, topInset = 0, pad
		if o.title and o.titleStyle == "light" then
			headerH, topInset = M.subgroupTitleH, 0
			local t = FS(panel, "groupTitle", Text.Primary)
			t:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -M.subgroupPad)
			t:SetText(o.title)
			panel._title = t
		elseif o.title then
			-- v3 (Florian's card mockup): head lives INSIDE the card body — gold
			-- title + optional muted description line; no header bar, no divider,
			-- no accent bar.
			headerH, topInset = (o.subtitle and M.cardHeadSubH or M.cardHeadH), (o.afterHeader or 0)
			local titleFS = FS(panel, "sectionHead", Text.Primary)
			titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -M.cardHeadTop)
			titleFS:SetText(o.title)
			panel._title = titleFS
			-- Vertical center of the TITLE line — the header count chip / action
			-- link / master switch align to THIS (not cardHeadH/2, which centered
			-- on a title-only block and rode ~5px too high, worse with a subtitle).
			local titleH = titleFS:GetStringHeight()
			if not titleH or titleH <= 0 then titleH = 20 end -- cold font fallback (= sectionHead size)
			local titleMidY = -M.cardHeadTop - titleH / 2
			if o.subtitle then
				local subFS = FS(panel, "caption", Text.Description)
				subFS:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -M.cardSubY)
				subFS:SetPoint("RIGHT", panel, "RIGHT", -pad, 0)
				subFS:SetJustifyH("LEFT")
				subFS:SetWordWrap(false)
				subFS:SetText(o.subtitle)
				panel._subtitle = subFS
			end
			-- v2 refinement no. 1: count chip right of the title (muted when 0).
			if o.count ~= nil then
				local nonzero = (tonumber(o.count) or 0) > 0
				local chip = CreateFrame("Frame", nil, panel)
				local cfs = FS(chip, "caption", nonzero and Text.Primary or Text.Description)
				cfs:SetText(tostring(o.count))
				cfs:SetPoint("CENTER", chip, "CENTER", 0, 0)
				chip:SetSize(math.max(M.sectionCountH, math.ceil(cfs:GetStringWidth()) + M.sectionCountPad * 2), M.sectionCountH)
				chip:SetPoint("LEFT", titleFS, "RIGHT", M.sectionCountGap, 0)
				UI.RoundBorder(chip, nonzero and UI.accentA(0.40) or Border.default, "OVERLAY", nil, UI.RADIUS.xs)
			end
			-- v2 refinement no. 2: quiet header action (e.g. "Restore defaults") on the
			-- right — declutters the card footer; muted, golden on hover.
			if o.action then
				local act = CreateFrame("Button", nil, panel)
				local afs = FS(act, "value", Text.Description)
				afs:SetText(o.action.text or "")
				afs:SetPoint("CENTER", act, "CENTER", 0, 0)
				act:SetSize(math.ceil(afs:GetStringWidth()) + 12, M.cardHeadH)
				act:SetPoint("RIGHT", panel, "TOPRIGHT", -pad, titleMidY)
				act:SetScript("OnEnter", function() afs:SetTextColor(Accent.hover.r, Accent.hover.g, Accent.hover.b) end)
				act:SetScript("OnLeave", function() afs:SetTextColor(Text.Description.r, Text.Description.g, Text.Description.b) end)
				if o.action.onClick then act:SetScript("OnClick", o.action.onClick) end
			end
			-- Header master toggle (card grid system): small switch on the right
			-- that enables/disables the card's feature. Used instead of o.action
			-- (both anchor to the same header spot).
			if o.toggle then
				local sw = ns.W.Switch(panel, { small = true, get = o.toggle.get, set = o.toggle.set })
				sw:SetPoint("RIGHT", panel, "TOPRIGHT", -pad, titleMidY)
				panel._switch = sw
			end
			-- Header EYE toggle (card-eye system): shows/hides THIS card's layer in
			-- the live preview (and, from the selected frame, in Edit Mode). Sits
			-- left of the master switch if the card has one, else at the switch
			-- spot. Replaces the preview's grouped filter popover — the eye lives
			-- with the setting it controls (Florian 2026-07-16).
			if o.eye then
				local eb = CreateFrame("Button", nil, panel)
				eb:SetSize(M.cardEyeBtn, M.cardEyeBtn)
				-- Eye sits at the LEFT, BEFORE the title (Florian 2026-07-16: glued
				-- to the master switch it read as part of the switch). The title
				-- shifts right to make room.
				eb:SetPoint("LEFT", panel, "TOPLEFT", pad, titleMidY)
				local textX = pad + M.cardEyeBtn + S.s3
				if panel._title then
					panel._title:ClearAllPoints()
					panel._title:SetPoint("TOPLEFT", panel, "TOPLEFT", textX, -M.cardHeadTop)
				end
				if panel._subtitle then
					panel._subtitle:ClearAllPoints()
					panel._subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", textX, -M.cardSubY)
					panel._subtitle:SetPoint("RIGHT", panel, "RIGHT", -pad, 0)
				end
				local g = eb:CreateTexture(nil, "ARTWORK")
				g:SetSize(M.cardEyeGlyph, M.cardEyeGlyph)
				g:SetPoint("CENTER", eb, "CENTER", 0, 0)
				g:SetSnapToPixelGrid(false); g:SetTexelSnappingBias(0)
				local hovered = false
				local function paint()
					local on = o.eye.get()
					g:SetTexture(TEX .. (on and "icon-eye" or "icon-eye-off"))
					local col = hovered and Accent.hover or (on and Accent.color or Text.Description)
					g:SetVertexColor(col.r, col.g, col.b)
				end
				paint()
				eb:SetScript("OnEnter", function()
					hovered = true; paint()
					if o.eye.tip then ns.W.ShowTextTip(eb, o.eye.tip, nil, "TOP") end
				end)
				eb:SetScript("OnLeave", function() hovered = false; paint(); ns.W.HideTip() end)
				eb:SetScript("OnClick", function() o.eye.set(not o.eye.get()); paint() end)
				panel._eye = eb
				-- Central eye-popover sync: register the paint on the screen so
				-- external toggles (dock popover / same key on another tab)
				-- repaint this glyph (Shell:RepaintEyes + cache re-show).
				local scr = Shell._screen
				if scr then
					scr._eyePaints = scr._eyePaints or {}
					scr._eyePaints[#scr._eyePaints + 1] = paint
				end
			end

			-- Header divider (Florian 2026-07-22, back per the mockup): a fine
			-- hairline under the title/subtitle block, at the header's own bottom
			-- edge, so the header→content gap reads as two deliberate steps
			-- (title-to-line, line-to-content) instead of one big undifferentiated
			-- void. Only the heavy card-title header gets it, not the light
			-- subgroup label style.
			if o.title and o.titleStyle ~= "light" then
				local divider = panel:CreateTexture(nil, "ARTWORK")
				UI.SetColor(divider, Border.faint)
				divider:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -headerH)
				divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad, -headerH)
				PixelUtil.SetHeight(divider, 1)
			end
		end

		local rowPad = outerPad + pad -- row indent of the box WITHIN holder
		local inner, iy, pending = {}, topY - headerH - topInset, nil
		-- Divider de-dup (Florian 2026-07-22): track whether the boundary at the
		-- cursor already carries a hairline (the header divider, or a preceding
		-- OptionRow's bottom line). A subHeadRow/Disclosure draws its OWN top line;
		-- when the boundary is already lined, hide it so the two don't read as a
		-- double divider. A lineless element (FieldRow/segment) leaves it unlined.
		local boundaryLined = (o.title and o.titleStyle ~= "light") and true or false
		local function anchor(widget, h, full)
			if pending then iy = iy - pending end
			widget:SetParent(host)
			widget:ClearAllPoints()
			widget:SetPoint("TOPLEFT", host, "TOPLEFT", rowPad, iy)
			if full then widget:SetPoint("TOPRIGHT", host, "TOPRIGHT", -rowPad, iy) end
			if h then widget:SetHeight(h) end
			iy = iy - (h or widget:GetHeight())
		end
		local function placed(widget)
			if widget._topLine then widget._topLine:SetShown(not boundaryLined) end
			boundaryLined = widget._bottomLine and true or false
		end
		function inner.place(_, widget, h, gap) anchor(widget, h, true); placed(widget); pending = gap or 22 end
		function inner.placeLeft(_, widget, h, gap) anchor(widget, h, false); placed(widget); pending = gap or 22 end
		function inner.gap(_, dy) iy = iy - (dy or 8) end
		function inner.y() return iy end
		-- Nested lighter sub-box at the current position; same API.
		function inner.subgroup(_, o2)
			o2 = o2 or {}
			if pending then iy = iy - pending; pending = nil end -- apply pending BEFORE the box
			local sub = makeBox(iy, {
				holder = host, outerPad = rowPad, pad = M.subgroupPad,
				fill = Surface.Card, border = Border.faint,
				title = o2.title, titleStyle = o2.title and "light" or nil,
			})
			local rawClose = sub.close
			function sub.close()
				iy = rawClose()                    -- cursor to the box bottom edge
				pending = o2.gap or M.subgroupGap  -- gap as pending -> dropped at the parent close (symmetric card end)
				return sub._panel
			end
			return sub
		end
		function inner.close()
			local bottom = iy - pad -- bottom = last row + inner padding (trailing gap dropped)
			panel:SetHeight(topY - bottom) -- topY/bottom = negative offsets -> difference = height
			return bottom
		end
		inner._panel = panel
		return inner
	end

	-- Section card (concept A): box with header + title at the current stack
	-- position. :close() finalizes the card height AND advances the outer stack by
	-- card + sectionGap (subgroups instead advance their parent cursor).
	-- opts (optional): { count = n (header count chip), action = { text, onClick }
	-- (quiet header link on the right) } — v2 refinements no. 1 + 2.
	function stack:section(title, opts)
		local M = UI.WIDGET
		local inner = makeBox(y, {
			outerPad = 0, pad = M.sectionPad, fill = Surface.Card, border = Border.default,
			title = title, afterHeader = M.sectionAfterHeader,
			count = opts and opts.count, action = opts and opts.action,
			toggle = opts and opts.toggle, eye = opts and opts.eye,
			subtitle = opts and opts.subtitle,
			-- Cards are rounded by default; opts.round = "bottom" for bodies
			-- flush-attached under a collapsible header (seam edge square).
			round = (opts and opts.round ~= nil) and opts.round or true,
		})
		local rawClose = inner.close
		function inner.close()
			local bottom = rawClose()
			y = bottom - M.sectionGap
			return inner._panel
		end
		inner._title = inner._panel._title
		return inner
	end

	-- Band (card grid system): one horizontal row of section cards with track
	-- spans out of UI.GRID.cols, e.g. stack:band({ {span=8, title=...},
	-- {span=4, title=...} }). Each entry of the returned .cards array is a
	-- section-like inner stacker (place/gap/subgroup/close); build the cards in
	-- any order, then call band:close(). A card's :close() records its height;
	-- band:close() stretches every card of the band to the tallest one (clean
	-- shared bottom edge — the neighbor gets air, not a ragged gap) and only
	-- then advances the outer stack. Column x/width resolve via OnSizeChanged
	-- (build-time width is unknown; same pattern as W.Row).
	function stack:band(defs)
		local M, G = UI.WIDGET, UI.GRID
		local bandF = CreateFrame("Frame", nil, holder)
		bandF:SetFrameLevel(holder:GetFrameLevel())
		bandF:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
		bandF:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, y)
		local n = #defs
		local cols = {}
		local spanSum = 0
		for i = 1, n do
			local colF = CreateFrame("Frame", nil, bandF)
			colF:SetFrameLevel(bandF:GetFrameLevel())
			cols[i] = colF
			spanSum = spanSum + (defs[i].span or G.cols)
		end
		-- Underfilled band (spans sum < 12, e.g. a lone trailing span-6 card):
		-- reserve the gutter for the EMPTY remainder too, so the card gets the same
		-- width as a paired span-6 card and its edges line up with the 6+6 cards
		-- above/below. Without this a lone span-6 was cardGap/2 wider (n-1=0 gutters)
		-- than a Dispel-style paired card and stuck out (Florian 2026-07-22).
		local phantomGutter = (spanSum < G.cols) and 1 or 0
		local function layout(w)
			if not w or w <= 0 then return end
			local usable = w - G.cardGap * (n - 1 + phantomGutter)
			local x = 0
			for i = 1, n do
				local cw = usable * (defs[i].span or G.cols) / G.cols
				cols[i]:SetPoint("TOPLEFT", bandF, "TOPLEFT", x, 0)
				cols[i]:SetPoint("BOTTOMLEFT", bandF, "BOTTOMLEFT", x, 0)
				cols[i]:SetWidth(cw)
				x = x + cw + G.cardGap
			end
		end
		bandF:SetScript("OnSizeChanged", function(_, w) layout(w) end)
		layout(bandF:GetWidth())

		local band = { cards = {}, _h = {} }
		for i, def in ipairs(defs) do
			local inner = makeBox(0, {
				holder = cols[i], outerPad = 0, pad = M.sectionPad,
				fill = Surface.Card, border = Border.default,
				title = def.title, afterHeader = M.sectionAfterHeader,
				count = def.count, action = def.action, toggle = def.toggle,
				eye = def.eye, subtitle = def.subtitle,
				round = (def.round ~= nil) and def.round or true,
			})
			local rawClose = inner.close
			function inner.close()
				local bottom = rawClose()
				band._h[i] = -bottom
				return inner._panel
			end
			band.cards[i] = inner
		end
		function band.close()
			local h = 0
			for i = 1, n do h = math.max(h, band._h[i] or 0) end
			for i = 1, n do band.cards[i]._panel:SetHeight(h) end
			bandF:SetHeight(h)
			y = y - h - M.sectionGap
		end
		return band
	end

	return stack
end

-- Screens (Shell/Screens.lua) need the same stacker for their own sub-frames
-- (e.g. the Base screen builds its gateable body via its own stack).
Shell.NewStack = newStack

-- ---------------------------------------------------------------------------
--  Screen cache (perf audit E): WoW never garbage-collects frames, so
--  rebuilding a screen on every tab switch grows memory for the whole session.
--  Screens are therefore cached per "Section/Tab" key and reused 1:1 on plain
--  navigation. Any DATA change renders with changed=true (the existing call
--  sites), which drops the WHOLE cache — after an edit every screen rebuilds
--  on its next visit, exactly the pre-cache correctness. Pure browsing between
--  edits costs no new frames (and switches without rebuild flicker).
-- ---------------------------------------------------------------------------
function Shell:InvalidateScreenCache()
	local cache = self._screenCache
	if not cache then return end
	for k, e in pairs(cache) do
		if e.frame ~= self._screen then
			-- parked screen: retire it together with its popovers
			e.frame:Hide(); e.frame:SetParent(nil)
			for _, fr in ipairs(e.popovers) do fr:Hide(); fr:SetParent(nil) end
		end
		-- the DISPLAYED screen just gets forgotten: it keeps working live and is
		-- orphaned/rebuilt by the normal RenderContent path on the next render.
		cache[k] = nil
	end
end

-- Recolour the whole shell to a new accent (the Global-tab picker). EVENT-DRIVEN:
-- fires only on a swatch click — NO loop, NO OnUpdate (perf §9). Re-tints the
-- persistent chrome directly through stored refs (instant, no rebuild); the
-- content of OTHER tabs rebuilds fresh on its next visit via InvalidateScreenCache
-- (the accent-bearing widgets read UI.Accent.* at build time), so there is no
-- full-shell flicker. The Global tab itself has no accent-coloured content
-- widgets (the preset row repaints its own active ring), so the current view is
-- correct immediately.
function Shell:RefreshAccent(col, chromeOnly)
	UI.SetAccent(col)
	local c = Accent.color
	local f = self._frame
	if f then
		if f._auroraTex then f._auroraTex:SetVertexColor(c.r, c.g, c.b, AURORA_INTENSITY) end
		if f._auroraLit then f._auroraLit:SetVertexColor(c.r, c.g, c.b, DOT_LIT_ALPHA) end
		if f._navEdge  then f._navEdge:SetVertexColor(c.r, c.g, c.b, NAV_EDGE_INTENSITY) end
	end
	if self._applyWordmarkAccent then self._applyWordmarkAccent() end
	if self._tabGlow then local g = Accent.glow; self._tabGlow:SetVertexColor(g.r, g.g, g.b, g.a) end
	if self._tabFill then local w = Accent.wash; self._tabFill:SetVertexColor(w.r, w.g, w.b, w.a) end
	if self._paintThumb then self._paintThumb(0.55) end -- scrollbar thumb (idle alpha)
	-- chromeOnly = a LIVE picker drag: only the chrome re-tints, so the picker's
	-- anchor (a widget IN the current content) survives — rebuilding the current
	-- card mid-drag would orphan it. The committed path (preset click, picker
	-- apply/cancel) rebuilds the CURRENT tab too, so its own accent-coloured
	-- widgets (sliders read Accent.color at build) update immediately instead of
	-- only on the next tab visit. Chrome stays put (no full-shell flicker); the
	-- content repaint is the same as a tab switch.
	if chromeOnly then return end
	self:InvalidateScreenCache()
	if f and f:IsShown() then self:RenderContent(true) end
	-- Edit Mode's cached chrome (toolbar / selection panel) rebuilds with the new
	-- accent on its next open; its functional in-world signals stay neutral.
	if ns.EditMode and ns.EditMode.OnAccentChanged then ns.EditMode:OnAccentChanged() end
end

-- ---------------------------------------------------------------------------
--  Preview dock: the satellite window next to the panel that hosts a screen's
--  live preview (Raidframes tabs today). Content builders live in
--  ns.ScreenPreviews[key]; content is built ONCE per key and re-shown on
--  navigation (it refreshes via fr._onShow). The module drives size/side via
--  Shell:SetDockLayout. Dragging is free-floating; dropping the dock within
--  UI.WIDGET.pvSnap of its docked spot snaps it back on. The float position
--  persists ACCOUNT-WIDE in db.global.previewDock (nil = docked) — NOTE:
--  AceDB's account section is db.global, NOT db.profile.global.
-- ---------------------------------------------------------------------------
local function dockStore()
	local db = ns.Lumen and ns.Lumen.db
	return db and db.global
end

-- Preview open state (session-only; the shell always starts with the preview
-- closed). The sidebar button is THE toggle; the band's own collapse chevron
-- also routes here and simply closes the window.
function Shell:IsPreviewOpen() return self._previewOpen == true end
function Shell:SetPreviewOpen(v)
	if self._warming then return end -- index warm-up: collect labels only, touch no live chrome
	self._previewOpen = v and true or false
	self:_UpdateDock(self._previewKey)
end
function Shell:TogglePreview() self:SetPreviewOpen(not self._previewOpen) end

function Shell:_UpdateDock(key)
	if self._warming then return end -- index warm-up: collect labels only, touch no live chrome
	local dock = self._dock
	if not dock then return end
	self._previewKey = key
	local frames = self._dockFrames
	if not frames then frames = {}; self._dockFrames = frames end
	local builder = ns.ScreenPreviews and ns.ScreenPreviews[key]
	-- Sidebar toggle: only screens with a preview get the button.
	if self._previewBtn then
		self._previewBtn:SetShown(builder ~= nil)
		if builder then
			self._previewBtn._txt:SetText(self._previewOpen and T("Close preview") or T("Open preview"))
		end
	end
	for k, fr in pairs(frames) do fr:SetShown(builder ~= nil and k == key) end
	if not builder or not self._previewOpen then
		dock:Hide()
		return
	end
	local fr = frames[key]
	if not fr then
		fr = CreateFrame("Frame", nil, dock)
		fr:SetAllPoints(dock)
		local ok, err = pcall(builder, fr)
		if not ok and ns.Lumen then
			ns.Lumen:Print("|cffD66A5C" .. T("Shell error in") .. " " .. key .. ":|r " .. tostring(err))
		end
		frames[key] = fr
	end
	fr:Show()
	dock:Show()
	-- Refresh the preview (fills the frames + sizes the dock via SetDockLayout).
	if fr._onShow then pcall(fr._onShow) end
end

-- (Re-)anchor the dock: docked = glued to the panel edge for its side;
-- floating = wherever the user dropped it (position in dock units).
function Shell:_DockAnchor()
	local dock, panel = self._dock, self._frame
	if not (dock and panel) then return end
	local st = dockStore()
	local float = st and st.previewDock
	local gap = UI.WIDGET.pvDockGap
	dock:ClearAllPoints()
	if float then
		dock:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", float.x, float.y)
	elseif dock._side == "right" then
		dock:SetPoint("TOPLEFT", panel, "TOPRIGHT", gap, 0)
	else
		dock:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -gap)
		dock:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -gap)
	end
end

-- Called by the active preview band: side = "right"|"bottom". The dock is
-- content-sized on both axes; only the docked bottom variant keeps the
-- panel's width (w = nil there).
function Shell:SetDockLayout(side, w, h)
	if self._warming then return end -- index warm-up: collect labels only, touch no live chrome
	local dock, panel = self._dock, self._frame
	if not (dock and panel) then return end
	dock._side = side
	local st = dockStore()
	local float = st and st.previewDock
	if side == "right" then
		dock:SetSize(w, h)
	else
		dock:SetHeight(h)
		if float then dock:SetWidth(PANEL.w) end
	end
	self:_DockAnchor()
end

-- Dock window chrome (fill, border) — stripped by the preview's "Backdrop"
-- filter so only the frames + header strip remain visible.
function Shell:SetDockChrome(on)
	if self._warming then return end -- index warm-up: collect labels only, touch no live chrome
	local dock = self._dock
	if not dock then return end
	dock._fill:SetShown(on)
	for _, e in ipairs(dock._edges) do e:SetShown(on) end
end

-- Forget the float position and glue the dock back onto its panel edge
-- (popover action row — for docks dragged somewhere unfortunate).
function Shell:ResetDockPosition()
	local st = dockStore()
	if st then st.previewDock = nil end
	self:_DockAnchor()
end

-- Drop check after a drag: near the docked spot -> snap back on (and forget
-- the float position), otherwise remember where it floats now.
function Shell:_DockDropCheck()
	local dock, panel = self._dock, self._frame
	if not (dock and panel) then return end
	local st = dockStore()
	local tx, ty   -- docked TOPLEFT target for the current side (panel units)
	local gap = UI.WIDGET.pvDockGap
	if dock._side == "right" then
		tx, ty = (panel:GetRight() or 0) + gap, panel:GetTop() or 0
	else
		tx, ty = panel:GetLeft() or 0, (panel:GetBottom() or 0) - gap
	end
	local dx, dy = dock:GetLeft() or 0, dock:GetTop() or 0
	local near = math.max(math.abs(dx - tx), math.abs(dy - ty)) <= UI.WIDGET.pvSnap
	if st then
		if near then st.previewDock = nil
		else st.previewDock = { x = dock:GetLeft() or 0, y = dock:GetBottom() or 0 } end
	end
	-- Re-apply size rules for the new state (floating gets explicit both axes).
	if dock._side == "right" then self:SetDockLayout("right", dock:GetWidth(), dock:GetHeight())
	else self:SetDockLayout("bottom", nil, dock:GetHeight()) end
end

-- Render content for the current section/tab: real screen (Shell/Screens.lua)
-- if registered, otherwise the coming-soon card. Then set the scroll child
-- height, restore the scroll position, update the scrollbar.
-- `changed` = a profile value changed: keep the scroll position AND force a
-- rebuild (drops the screen cache). Falsy = pure navigation (cache reuse).
-- ---------------------------------------------------------------------------
--  Settings search — the INDEX.
--  Anti-bloat means few options, but "few" is still ~200 across nine screens,
--  so the honest answer to "where is this setting?" is a search that reaches
--  INTO the screens instead of just filtering module names.
--  The index MUST NOT be a hand-kept list — that drifts at the second new
--  option. Instead the widget builders (W.OptionRow / W.Slider / W.Select)
--  report their label while a screen builds, so every option added later is
--  searchable for free. indexCtx is only set around a builder call, which is
--  what keeps dialogs, the preview dock and the Edit Mode flyout out of it.
--  Two halves, deliberately separate:
--    searchIndex — pure DATA, survives rebuilds (label/tooltip/section/tab).
--    screen._searchRows — the live frames, refilled on every build. Frames die
--    with their screen, so a jump always resolves against the CURRENT screen
--    (same reasoning as _jumpCards).
-- ---------------------------------------------------------------------------
local searchIndex = {}   -- ordered: { label, tip, kind, section, tab, key, hay }
local indexSeen = {}     -- key -> true (an option is listed once, not once per rebuild)
local builtScreens = {}  -- "Section/Tab" -> true (built at least once, warm-up skips it)
local indexCtx           -- { section, tab } — set ONLY while a builder runs

function Shell:IndexOption(label, frame, kind, tip)
	if not (indexCtx and label and label ~= "") then return end
	local key = indexCtx.section .. "/" .. indexCtx.tab .. "/" .. label
	local scr = self._screen
	if scr then
		scr._searchRows = scr._searchRows or {}
		scr._searchRows[key] = frame
	end
	if indexSeen[key] then return end
	indexSeen[key] = true
	searchIndex[#searchIndex + 1] = {
		label = label, tip = tip, kind = kind,
		section = indexCtx.section, tab = indexCtx.tab, key = key,
		-- Tooltips are indexed too: searching "instanz" should find the aggro and
		-- invite options even though neither label contains the word.
		hay = (label .. " " .. (tip or "")):lower(),
	}
end

function Shell:SearchEntries() return searchIndex end

-- Warm-up: screens are built lazily, so on a cold Shell the index only knows
-- the tabs you happened to open. Before the first search we build the missing
-- ones once into a hidden holder purely to collect labels, then throw the
-- frames away. _warming makes the side-effecting Shell hooks (dock, badge)
-- no-ops for that pass, the builder runs in pcall, and a failure only costs
-- that screen's entries — the search still works with what it has.
function Shell:WarmSearchIndex()
	if self._searchWarmed then return end
	self._searchWarmed = true
	local holder = self._searchWarmHolder
	if not holder then
		holder = CreateFrame("Frame", nil, self._frame)
		holder:SetPoint("TOPLEFT", self._scrollChild, "TOPLEFT", 0, 0)
		holder:SetPoint("TOPRIGHT", self._scrollChild, "TOPRIGHT", 0, 0)
		holder:SetHeight(1)
		holder:Hide()
		self._searchWarmHolder = holder
	end
	local savedScreen, savedPopovers, savedBadge = self._screen, self._popovers, self._lastBadge
	self._warming = true
	for _, sec in ipairs(SECTIONS) do
		if not sec.soon then
			for _, tabName in ipairs(sec[2]) do
				local key = sec[1] .. "/" .. tabName
				local builder = ns.Screens and ns.Screens[key]
				if builder and not builtScreens[key] then
					builtScreens[key] = true
					local d = CreateFrame("Frame", nil, holder)
					d:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
					d:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
					self._screen = d
					local throwaway = {}
					if ns.W and ns.W.CapturePopovers then ns.W.CapturePopovers(throwaway) end
					indexCtx = { section = sec[1], tab = tabName }
					pcall(builder, d, newStack(d))
					indexCtx = nil
					d:Hide(); d:SetParent(nil)
					for _, fr in ipairs(throwaway) do fr:Hide(); fr:SetParent(nil) end
				end
			end
		end
	end
	self._warming = false
	self._screen, self._popovers, self._lastBadge = savedScreen, savedPopovers, savedBadge
	if ns.W and ns.W.CapturePopovers then ns.W.CapturePopovers(self._popovers) end
end

-- ---------------------------------------------------------------------------
--  Settings search — matching, state and the result screen (variant A, chosen
--  by Florian 2026-07-26 over an inline-filtered settings page).
-- ---------------------------------------------------------------------------
local SEARCH_KEY = "\1search" -- pseudo screen key; never collides with "Section/Tab"

local function normalize(s) return (s:lower():gsub("[-_%.]", " ")) end

-- Substring match with a stem fallback: plain matching fails the obvious case
-- "hots" -> "HoT-Symbolgröße" (trailing s). Dropping a trailing en/s/n covers
-- German and English plurals alike without dragging in a stemmer.
local function hayHas(hay, term)
	if hay:find(term, 1, true) then return true end
	if #term > 3 then
		local stem = (term:gsub("en$", ""))
		stem = (stem:gsub("[sn]$", ""))
		if #stem > 2 and stem ~= term and hay:find(stem, 1, true) then return true end
	end
	return false
end

function Shell:SearchResults()
	local q = self._searchQuery
	if not q then return nil end
	local terms = {}
	for w in normalize(q):gmatch("%S+") do terms[#terms + 1] = w end
	if #terms == 0 then return nil end
	local out = {}
	for _, e in ipairs(searchIndex) do
		local hay = normalize(e.hay .. " " .. e.section .. " " .. e.tab)
		local all = true
		for _, t in ipairs(terms) do
			if not hayHas(hay, t) then all = false; break end
		end
		if all then out[#out + 1] = e end
	end
	return out
end

-- Hit count per module next to the nav entries — the fastest "where does this
-- live?" answer, before you even read the list.
function Shell:_UpdateNavCounts()
	if not self._navButtons then return end
	local per = {}
	local res = self:SearchResults()
	if res then for _, e in ipairs(res) do per[e.section] = (per[e.section] or 0) + 1 end end
	for i, nb in ipairs(self._navButtons) do
		local sec = SECTIONS[i]
		if not nb._countFS then
			nb._countFS = FS(nb, "caption", Text.Description)
			nb._countFS:SetPoint("RIGHT", nb, "RIGHT", -S.navGutter, 0)
		end
		local n = per[sec[1]]
		nb._countFS:SetText(n and tostring(n) or "")
		nb._countFS:SetShown(n ~= nil)
	end
end

function Shell:SetSearchQuery(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local q = text ~= "" and text or nil
	if q == self._searchQuery then return end
	self._searchQuery = q
	-- Screens are lazy, so the index only knows visited tabs until now.
	if q then self:WarmSearchIndex() end
	self._searchSel = nil
	self:_UpdateNavCounts()
	if q then
		self:RenderContent()
	else
		-- Leaving search: SelectSection restores the tab strip the search hid.
		self:SelectSection(self._section or 1)
	end
	if self._searchPaint then self._searchPaint() end
end

function Shell:IsSearching() return self._searchQuery ~= nil end

-- Enter on the search field: jump to the highlighted result (first one if the
-- user hasn't arrowed anywhere yet).
function Shell:ActivateSearchSelection()
	local res = self:SearchResults()
	if not (res and #res > 0) then return end
	local e = res[math.min(self._searchSel or 1, #res)]
	if e then self:JumpToOption(e) end
end

-- Arrow keys move the highlight without leaving the field.
function Shell:MoveSearchSelection(delta)
	local res = self:SearchResults()
	if not (res and #res > 0) then return end
	local i = (self._searchSel or 0) + delta
	if i < 1 then i = #res elseif i > #res then i = 1 end
	self._searchSel = i
	if self._searchRowButtons then
		for j, b in ipairs(self._searchRowButtons) do b:SetSelected(j == i) end
	end
end

-- Jump to an indexed option: open its section/tab, then scroll to the row and
-- flash it. The frame is resolved on the CURRENT screen (rebuilds invalidate
-- frames), same pattern as _ResolveJump for cards. The query deliberately stays
-- in the field (Florian 2026-07-26) so you can work through several hits.
function Shell:JumpToOption(entry)
	if not entry then return end
	self._searchQuery = nil          -- leave the result screen...
	self:_UpdateNavCounts()          -- ...but keep the text in the box
	self:OpenTo(entry.section, entry.tab)
	local tries = 0
	local function attempt()
		if not (self._frame and self._frame:IsShown()) then return end
		local scr = self._screen
		local row = scr and scr._searchRows and scr._searchRows[entry.key]
		local childTop = self._scrollChild and self._scrollChild:GetTop()
		if not (row and row:GetTop() and childTop) then
			tries = tries + 1
			if tries < 8 then C_Timer.After(0, attempt) end
			return
		end
		if self._scroll then
			local viewH = self._scroll:GetHeight() or 0
			local maxScroll = math.max(0, (self._scrollChild:GetHeight() or 0) - viewH)
			local off = childTop - row:GetTop()
			self._scroll:SetVerticalScroll(math.min(maxScroll, math.max(0, off - 60)))
			if self._updateBar then self._updateBar() end
		end
		flashRow(row)
	end
	C_Timer.After(0, attempt)
end

-- The result screen. Built like any other screen (same stacker, same scroll
-- host) but never cached — it changes with every keystroke.
function Shell:BuildSearchScreen(d, stack)
	local L = UI.LAYOUT.search
	local res = self:SearchResults() or {}
	local q = self._searchQuery or ""
	self._searchRowButtons = {}

	stack:gap(UI.LAYOUT.general.tabTop)

	if #res == 0 then
		stack:gap(L.emptyTop)
		local box = CreateFrame("Frame", nil, d)
		local title = FS(box, "section", Text.Secondary)
		title:SetText(T("Nothing found for") .. " „" .. q .. "“")
		title:SetPoint("TOP", box, "TOP", 0, 0)
		local hint = FS(box, "hint", Text.Description)
		hint:SetText(T("Try part of the name — for example \"aggro\" or \"size\"."))
		hint:SetPoint("TOP", title, "BOTTOM", 0, -S.s4)
		stack:place(box, L.headH + UI.WIDGET.hintH, 0)
		return
	end

	-- The results sit on ONE full-width card (Florian 2026-07-26: loose rows on
	-- the bare panel background read as unplaced). The card header carries the
	-- query and the match count, so no separate heading line is needed.
	-- DOCUMENTED EXCEPTION to the "stacked rows span max 6 tracks" rule (design
	-- bible §6.1/4): that rule exists so CONTROLS don't drift far from their
	-- label. These rows carry no control — only a right-aligned kind caption —
	-- so the full width costs nothing and the list needs the room.
	local band = stack:band({
		{ span = UI.GRID.cols,
		  title = T("Results for") .. " „" .. q .. "“",
		  count = #res },
	})
	local card = band.cards[1]

	local KINDS = { option = T("Switch"), slider = T("Slider"), select = T("Choice") }

	for i, e in ipairs(res) do
		-- Parent is the SCREEN, not the card: a card is a table wrapper ({_panel})
		-- and card:place() reparents the row anyway (same as every Screens.lua row).
		local b = CreateFrame("Button", nil, d)
		local hover = UI.RoundFill(b, Surface.Hover, "BACKGROUND", nil, UI.RADIUS.sm)
		hover:Hide()
		local sel = UI.RoundFill(b, Accent.wash, "BACKGROUND", nil, UI.RADIUS.sm)
		sel:Hide()
		-- Same separator language as the stacked-row standard: hairline on the
		-- BOTTOM, so the last row closes the list and the header keeps its own.
		if i < #res then
			local line = b:CreateTexture(nil, "ARTWORK")
			setColor(line, Border.faint)
			line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
			line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
			local function snap() PixelUtil.SetHeight(line, 1) end
			snap(); C_Timer.After(0, snap)
			b:HookScript("OnSizeChanged", snap)
		end

		local lbl = FS(b, "checkLabel", Text.Secondary)
		lbl:SetText(e.label)
		lbl:SetPoint("LEFT", b, "LEFT", S.s4, L.crumbGap + 6)
		-- The breadcrumb IS the feature: which "HP display" is this one.
		local crumb = FS(b, "caption", Text.Description)
		crumb:SetText(e.section .. "  ›  " .. e.tab)
		crumb:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -L.crumbGap)

		local badge = FS(b, "caption", Text.Disabled)
		badge:SetText(KINDS[e.kind] or "")
		badge:SetPoint("RIGHT", b, "RIGHT", -S.s5, 0)

		b:SetScript("OnEnter", function(self2) if not self2._sel then hover:Show() end end)
		b:SetScript("OnLeave", function() hover:Hide() end)
		b.SetSelected = function(self2, on)
			self2._sel = on
			sel:SetShown(on and true or false)
			if on then hover:Hide() end
		end
		b:SetScript("OnClick", function() Shell:JumpToOption(e) end)

		card:place(b, L.rowH, 0)
		self._searchRowButtons[i] = b
		if self._searchSel == i then b:SetSelected(true) end
	end

	card:close()
	band.close()
end

function Shell:RenderContent(changed)
	-- Release any keybind-capture before switching: hiding the screen orphans a
	-- listening KeybindButton without firing its OnHide, which would leave the
	-- keyboard grabbed (no movement / ESC) until /reload.
	if ns.W and ns.W.StopActiveKeybind then ns.W.StopActiveKeybind() end
	-- Badge is per-screen: hide it first; builder or cache re-sets it.
	if self._tabBadge then self._tabBadge:Hide() end
	local prevScroll = (changed and self._scroll and self._scroll:GetVerticalScroll()) or 0
	local holderParent = self._scrollChild
	local cache = self._screenCache
	if not cache then cache = {}; self._screenCache = cache end

	local sec = SECTIONS[self._section]
	local key = sec[1] .. "/" .. ((not sec.soon and sec[2][self._tab]) or "")

	-- Search mode renders a pseudo screen instead of the tab: results span tabs,
	-- so the tab strip would be lying about where you are -- hide it.
	local searching = self:IsSearching()
	if searching then
		key = SEARCH_KEY
		for _, t in ipairs(self._tabButtons or {}) do t:Hide() end
		if self._tabStripBg then self._tabStripBg:Hide() end
		if self._tabSlider then self._tabSlider:Hide(); self._tabSlider._cx = nil end
	end

	-- Leaving a whole SECTION (not a tab switch within it): reset that section's
	-- open disclosures and drop its cached screens so they rebuild collapsed on
	-- the next visit. Switching tabs inside a section keeps everything open.
	if not searching and self._lastKey and self._lastKey ~= key then
		local oldSec = self._lastKey:match("^[^/]+")
		if oldSec ~= key:match("^[^/]+") and ns.SectionLeft and ns.SectionLeft(oldSec) then
			for k, entry in pairs(cache) do
				if k:match("^[^/]+") == oldSec then
					if entry.frame and entry.frame ~= self._screen then
						entry.frame:Hide(); entry.frame:SetParent(nil)
					end
					cache[k] = nil
				end
			end
		end
	end
	if not searching then self._lastKey = key end

	if changed then self:InvalidateScreenCache() end

	-- Put the current screen away: keep it (hidden) if it's cached for reuse,
	-- otherwise orphan it together with its popovers.
	if self._screen then
		self._screen:Hide()
		local k = self._screen._cacheKey
		local kept = k and cache[k] and cache[k].frame == self._screen
		if self._popovers then
			for _, fr in ipairs(self._popovers) do
				fr:Hide()
				if not kept then fr:SetParent(nil) end
			end
		end
		if not kept then self._screen:SetParent(nil) end
		self._screen, self._popovers = nil, nil
	end

	-- Preview dock (satellite window): show/build the preview of THIS key,
	-- hide the others. Its refresh also sizes/anchors the dock.
	self:_UpdateDock(key)

	-- Cache hit: re-show as-is — values are guaranteed current because every
	-- change since the build would have dropped the cache.
	local hit = not searching and cache[key]
	if hit then
		self._screen, self._popovers = hit.frame, hit.popovers
		-- New (lazily created) popovers of reused widgets must land in THIS
		-- screen's list again, not in the last-built screen's.
		if ns.W and ns.W.CapturePopovers then ns.W.CapturePopovers(hit.popovers) end
		hit.frame:Show()
		-- Eye state may have changed from ANOTHER access point since this screen
		-- was built (dock popover, or the same key's eye on another tab —
		-- aura keys exist on Raid AND Group): repaint from get() on re-show.
		if hit.frame._eyePaints then
			for _, p in ipairs(hit.frame._eyePaints) do p() end
		end
		holderParent:SetHeight(hit.height)
		if hit.badge then self:_ApplyBadge(hit.badge) end
		if self._scroll then
			local maxScroll = math.max(0, hit.height - (self._scroll:GetHeight() or 0))
			self._scroll:SetVerticalScroll(math.min(maxScroll, math.max(0, prevScroll)))
		end
		if self._updateBar then self._updateBar() end
		return
	end

	-- Build fresh.
	self._popovers = {}
	if ns.W and ns.W.CapturePopovers then ns.W.CapturePopovers(self._popovers) end

	local d = CreateFrame("Frame", nil, holderParent)
	d:SetPoint("TOPLEFT", holderParent, "TOPLEFT", 0, 0)
	d:SetPoint("TOPRIGHT", holderParent, "TOPRIGHT", 0, 0)
	d._cacheKey = key
	-- Screens built while the panel is hidden have unresolved sizes (first build
	-- in Build()) -> OnShow forces a rebuild for exactly this case.
	d._builtHidden = not (self._frame and self._frame:IsShown())
	self._screen = d
	self._lastBadge = nil   -- SetTabBadge records what the builder sets (for the cache)

	local stack = newStack(d)
	if searching then
		self:BuildSearchScreen(d, stack)
	elseif sec.soon then
		self:ComingSoon(d, stack, sec[1])
	else
		local builder = ns.Screens and ns.Screens[key]
		if builder then
			-- Wrap the builder defensively: a screen error must NOT empty the whole Shell
			-- (otherwise just an empty tab without a hint). Print the error to chat.
			-- The index context is live for exactly this call (see Shell:IndexOption)
			-- and is cleared OUTSIDE the pcall so an erroring screen can't leak it.
			builtScreens[key] = true
			indexCtx = { section = sec[1], tab = sec[2][self._tab] or "" }
			local ok, err = pcall(builder, d, stack)
			indexCtx = nil
			if not ok and ns.Lumen then
				ns.Lumen:Print("|cffD66A5C" .. T("Shell error in") .. " " .. key .. ":|r " .. tostring(err))
			end
		end
		-- No builder for this section/tab: leave the screen empty (defensive — every
		-- live section currently has a real screen, so this branch is not reached).
	end

	local h = stack:height()
	d:SetHeight(h)
	holderParent:SetHeight(h)
	-- Never CACHE a screen built while hidden (degenerate layout) — it gets
	-- rebuilt by the deferred OnShow pass; caching it could revive it later.
	-- The result screen is never cached: it changes with every keystroke.
	if not d._builtHidden and not searching then
		cache[key] = { frame = d, popovers = self._popovers, height = h, badge = self._lastBadge }
	end
	if self._scroll then
		-- On a forced rebuild (e.g. role reordering, collapsing the aura section) keep
		-- the scroll position, but clamp to the NEW content height. GetVerticalScrollRange()
		-- is a frame late right after SetHeight (stale) -> derive the max from the content height.
		local maxScroll = math.max(0, h - (self._scroll:GetHeight() or 0))
		self._scroll:SetVerticalScroll(math.min(maxScroll, math.max(0, prevScroll)))
	end
	if self._updateBar then self._updateBar() end
end

-- ---------------------------------------------------------------------------
--  Coming-soon placeholder: centered card (Cinzel-gold title + hint) for
--  modules that don't exist yet (Unitframes/Nameplates/QoL). Called by
--  RenderContent for `soon` sections instead of a real screen.
-- ---------------------------------------------------------------------------
function Shell:ComingSoon(d, stack, name)
	stack:gap(70)
	local holder = CreateFrame("Frame", nil, d)
	stack:place(holder, 170, 0)

	local card = CreateFrame("Frame", nil, holder)
	card:SetSize(440, 170)
	card:SetPoint("CENTER", holder, "CENTER", 0, 0)
	UI.RoundFill(card, Surface.Card)
	UI.RoundBorder(card, Border.default, "OVERLAY")

	local head = FS(card, "section", Text.Primary)
	head:SetText(UI.Track("COMING SOON", " "))
	head:SetPoint("TOP", card, "TOP", 0, -40)

	local body = FS(card, "hint", Text.Description)
	body:SetJustifyH("CENTER"); body:SetWordWrap(true)
	body:SetPoint("TOPLEFT", card, "TOPLEFT", 28, -84)
	body:SetPoint("TOPRIGHT", card, "TOPRIGHT", -28, -84)
	body:SetText(T("The \"%s\" module is still in progress and will be unlocked in a later version."):format(name or "?"))
end

-- ===========================================================================
--  API
-- ===========================================================================
function Shell:Toggle()
	local f = self:Build()
	if f:IsShown() then f:Hide() else f:Show() end
end

function Shell:Show()
	self:Build():Show()
end

function Shell:Hide()
	if ns.W and ns.W.StopActiveKeybind then ns.W.StopActiveKeybind() end -- never leave the keyboard grabbed
	if self._frame then self._frame:Hide() end
end
