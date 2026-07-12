local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell
--  The one and only config UI, following the Lumen design system v2 (flat,
--  square, charcoal surfaces + two-gold rule; see Shell/Tokens). Chrome
--  (header/nav/tabs) + the real screens (Shell/Screens). Opened via /lumen
--  and the ESC-menu button.
-- ===========================================================================

local UI = ns.UI
local C, L, S, PANEL, P = UI.C, UI.line, UI.S, UI.PANEL, UI.P
local T = ns.T   -- localization: T("english") -> display in the active language

local Shell = {}
ns.Shell = Shell

-- ---------------------------------------------------------------------------
--  Small build helpers — the primitives now live centrally in Tokens (ns.UI),
--  so Shell chrome AND widget toolkit use the same ones (DRY).
-- ---------------------------------------------------------------------------
local setColor, fill, border, FS = UI.SetColor, UI.Fill, UI.Border, UI.FS
local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"

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
--  Nav item (left rail) — v2: active = solid interactive-gold fill (C2) with
--  dark on-gold text (two-gold rule); inactive hover = element-hover surface.
-- ---------------------------------------------------------------------------
local function makeNavItem(parent, label, iconFile)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(S.navItemH)
	b:SetPoint("LEFT", parent, "LEFT", 0, 0)
	b:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	-- One state surface, recolored per state (active gold / hover charcoal).
	-- v3 nav mockup (Florian 2026-07-05): a rounded PILL inset from the sidebar
	-- edges instead of the full-width fill.
	local bg = UI.RoundFill(b, P.goldInt, "BACKGROUND", nil, UI.RADIUS.md)
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
		icon:SetVertexColor(C.textBody.r, C.textBody.g, C.textBody.b)
	end

	local txt = FS(b, "nav", C.textBody)
	txt:SetPoint("LEFT", icon or b, icon and "RIGHT" or "LEFT", icon and S.navIconGap or S.panelGutter, 0)
	txt:SetText(label)

	b._bg, b._txt, b._icon = bg, txt, icon
	b:SetScript("OnEnter", function(self)
		if self._soon then
			if ns.W and ns.W.ShowTextTip then
				ns.W.ShowTextTip(self, T("Coming soon"), T("This module is still in progress and will be unlocked in a later version."))
			end
		elseif not self._active then
			setColor(self._bg, P.elementHover); self._bg:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		if self._soon then
			if ns.W and ns.W.HideTip then ns.W.HideTip() end
		elseif not self._active then
			self._bg:Hide()
		end
	end)
	function b:SetActive(on)
		self._active = on
		if on then setColor(self._bg, P.goldInt) end
		self._bg:SetShown(on)
		local col = on and P.textOnGold or (self._soon and P.textDisabled or C.textBody)
		self._txt:SetTextColor(col.r, col.g, col.b)
		if self._icon then self._icon:SetVertexColor(col.r, col.g, col.b) end
	end
	-- Coming-soon mode: TRUE disabled text (D3; no chip — greyed out + hover tooltip
	-- is enough, a permanent chip would be redundant), never highlighted as active.
	function b:SetComingSoon(on)
		self._soon = on
		if on then
			self._txt:SetTextColor(P.textDisabled.r, P.textDisabled.g, P.textDisabled.b)
			if self._icon then self._icon:SetVertexColor(P.textDisabled.r, P.textDisabled.g, P.textDisabled.b) end
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
	local txt = FS(b, "tab", C.textBody)
	txt:SetText(label)
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:SetHeight(S.tabH)
	-- Width from the string width. On the first game start the custom-font width is
	-- sometimes still 0 (tabs tiny) -> Fit() re-measures once the panel is visible
	-- (OnShow calls it). Anchors LEFT->prev RIGHT pull the positions along automatically.
	function b:Fit() self:SetWidth(math.floor(txt:GetStringWidth() + 44 + 0.5)) end
	b:Fit()

	-- State surface: element (inactive) / element-hover / interactive gold (active).
	-- Rounded at MD per the radius scale ("Tabs" row); recolors stay UI.SetColor.
	local base = UI.RoundFill(b, P.element, "BACKGROUND", nil, UI.RADIUS.md)
	local edges = UI.RoundBorder(b, L.soft, "OVERLAY", nil, UI.RADIUS.md)
	b._txt, b._base, b._edges = txt, base, edges

	b:SetScript("OnEnter", function(self)
		if not self._active then
			setColor(self._base, P.elementHover)
			for _, e in ipairs(self._edges) do setColor(e, L.mid) end
		end
	end)
	b:SetScript("OnLeave", function(self)
		if not self._active then
			setColor(self._base, P.element)
			for _, e in ipairs(self._edges) do setColor(e, L.soft) end
		end
	end)
	function b:SetActive(on)
		self._active = on
		setColor(self._base, on and P.goldInt or P.element)
		local ec = on and L.strong or L.soft
		for _, e in ipairs(self._edges) do setColor(e, ec) end
		local tc = on and P.textOnGold or C.textBody
		self._txt:SetTextColor(tc.r, tc.g, tc.b)
		-- NO weight change active/inactive: SemiBold vs Medium have different glyph
		-- widths -> the centered text would "jump" in the fixed-width button (the width
		-- was measured once via Fit() with the tab-role font = hankenMed). The active tab
		-- stands out via the gold fill; the weight stays constant (hankenMed) so
		-- nothing jumps.
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
	local hoverFill = UI.RoundFill(b, P.elementHover, "BACKGROUND", nil, UI.RADIUS.sm)
	hoverFill:Hide()

	-- X: Lucide "x" glyph (stage-3 glyph swap), tinted; brightens on hover.
	local x = b:CreateTexture(nil, "OVERLAY")
	x:SetSize(S.closeGlyph, S.closeGlyph)
	x:SetPoint("CENTER", b, "CENTER", 0, 0)
	x:SetTexture(TEX .. "icon-x")
	x:SetSnapToPixelGrid(false); x:SetTexelSnappingBias(0)
	x:SetVertexColor(P.textSecondary.r, P.textSecondary.g, P.textSecondary.b)

	b:SetScript("OnEnter", function() hoverFill:Show(); x:SetVertexColor(P.textPrimary.r, P.textPrimary.g, P.textPrimary.b) end)
	b:SetScript("OnLeave", function() hoverFill:Hide(); x:SetVertexColor(P.textSecondary.r, P.textSecondary.g, P.textSecondary.b) end)
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
		-- Re-measure tabs: on the first show after game start the font width was maybe
		-- still 0 (tabs tiny). Anchors pull the positions along automatically.
		if Shell._tabButtons then for _, t in ipairs(Shell._tabButtons) do if t.Fit then t:Fit() end end end
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
	UI.RoundFill(f, P.panel, "BACKGROUND", nil, UI.ROUND_R_CHROME)
	UI.RoundBorder(f, L.mid, nil, nil, UI.ROUND_R_CHROME)

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
	-- v2: the sidebar is DELIBERATELY the lightest base surface (A2) — light nav
	-- column against the darker work area. Left-rounded: it sits flush in the
	-- panel's left edge, so its corners must follow the panel's chrome curve.
	UI.RoundFill(nav, P.sidebar, "BACKGROUND", "left", UI.ROUND_R_CHROME)

	-- Brand block at the top of the sidebar: wordmark + tagline, left-aligned on
	-- the same gutter as the nav labels, divider below.
	local brand = CreateFrame("Frame", nil, nav)
	brand:SetHeight(S.navBrandH)
	brand:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
	brand:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, 0)
	local bsep = brand:CreateTexture(nil, "ARTWORK")
	bsep:SetHeight(1); bsep:SetPoint("BOTTOMLEFT", brand, "BOTTOMLEFT", 0, 0)
	bsep:SetPoint("BOTTOMRIGHT", brand, "BOTTOMRIGHT", 0, 0); setColor(bsep, L.divider)

	local word = FS(brand, "wordmark", P.goldBrand) -- C1 brand gold (non-clickable)
	word:SetText(UI.Track("LUMENUI", " ")) -- tracking emulation (single space: fits the column)
	word:SetPoint("TOPLEFT", brand, "TOPLEFT", S.panelGutter, -22)
	local tag = FS(brand, "tagline", P.textSecondary)
	tag:SetText(UI.Track("a focused ui suite", " "))
	tag:SetPoint("TOPLEFT", word, "BOTTOMLEFT", 0, -6)

	-- "MODULES" caption above the nav list (v3 mockup, stage 3): a small tracked
	-- uppercase label, same left gutter as the nav items. The first nav item
	-- anchors below it (see the nav loop).
	local navLabel = FS(nav, "caption", C.textMuted)
	navLabel:SetText(UI.Track("MODULES", " "))
	navLabel:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", S.panelGutter, -S.s6)

	-- Version chip (stage 3): muted "v<x.y.z>" pinned to the very bottom-right of
	-- the sidebar so it never floats when the preview button is hidden (Florian
	-- 2026-07-05: chip + button swapped). Read live from the .toc metadata.
	local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or ""
	local chipH = S.tabBadgeH - 4
	local hasChip = ver ~= ""
	if hasChip then
		local chip = CreateFrame("Frame", nil, nav)
		local cfs = FS(chip, "caption", C.textMuted)
		cfs:SetText("v" .. ver)
		cfs:SetPoint("CENTER", chip, "CENTER", 0, 0)
		chip:SetSize(math.ceil(cfs:GetStringWidth()) + S.s5, chipH)
		chip:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -S.panelGutter, S.panelGutter)
		UI.RoundBorder(chip, L.soft, "OVERLAY", nil, UI.RADIUS.xs)
	end

	-- Preview toggle (v3 mockup): ONE central point to open/close the preview
	-- window. Sits ABOVE the version chip (or at the sidebar bottom if there's no
	-- chip). Hidden on screens without a registered preview; label follows the
	-- open state (_UpdateDock keeps it current).
	local pvY = hasChip and (S.panelGutter + chipH + S.s4) or S.panelGutter
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
	nsep:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, 0); setColor(nsep, L.divider)

	-- Tab-Strip (main starts at the panel top). Air ABOVE the strip = the same
	-- contentTopGap as BELOW it (Florian 2026-07-05: unequal gaps read like
	-- something was missing between tabs and the first card).
	local tabStrip = CreateFrame("Frame", nil, main)
	tabStrip:SetHeight(S.tabH)
	tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", S.panelGutter, -S.contentTopGap)
	tabStrip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -S.panelGutter, -S.contentTopGap)

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
	UI.RoundFill(badge, P.element, nil, nil, UI.RADIUS.xs)
	UI.RoundBorder(badge, L.soft, "OVERLAY", nil, UI.RADIUS.xs)
	local badgeTxt = FS(badge, "caption", C.textMuted)
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
	dock._fill = UI.RoundFill(dock, P.panel, nil, nil, UI.ROUND_R_CHROME)
	dock._edges = UI.RoundBorder(dock, L.mid, nil, nil, UI.ROUND_R_CHROME)
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
	trackTex:SetAllPoints(sbTrack); setColor(trackTex, C.ink700)

	-- Thumb anchored via TOP (= horizontally centered), width separate -> can widen
	-- on hover (easier to grab). updateBar sets height/position.
	local thumb = CreateFrame("Frame", nil, sbTrack)
	thumb:SetWidth(S.scrollBarW)
	thumb:EnableMouse(true)
	thumb._w = S.scrollBarW
	local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
	thumbTex:SetAllPoints(thumb)
	local function paintThumb(a) thumbTex:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, a) end
	paintThumb(0.55)

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
		local nb = makeNavItem(nav, sec[1], sec.icon)
		if prev then
			if sec.sep then
				local div = nav:CreateTexture(nil, "ARTWORK")
				div:SetHeight(1)
				setColor(div, L.divider)
				div:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", S.s4, -S.s3)
				div:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", -S.s4, -S.s3)
				nb:SetPoint("TOP", prev, "BOTTOM", 0, -(S.s3 * 2 + 1))
			else
				nb:SetPoint("TOP", prev, "BOTTOM", 0, -2)
			end
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
			else tb:SetPoint("LEFT", self._tabStrip, "LEFT", 0, 0) end
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
	-- Re-measure one frame later: on the very first build (panel still hidden /
	-- fonts maybe not ready) GetStringWidth returns 0 -> tiny tabs.
	C_Timer.After(0, function()
		for _, t in ipairs(self._tabButtons) do if t.Fit then t:Fit() end end
	end)
	-- Return to the tab that was active the last time this section was open
	-- (session memory; falls back to the first tab).
	Shell:SelectTab(self._lastTab[sectionIndex] or 1)
end

function Shell:SelectSection(index)
	self._section = index
	local sec = SECTIONS[index]
	-- Never highlight coming-soon modules as active (they stay muted + chip).
	for i, nb in ipairs(self._navButtons) do nb:SetActive(i == index and not sec.soon) end
	if sec.soon then
		-- No tabs, no tab selection — render the placeholder page directly.
		for _, t in ipairs(self._tabPool) do t:Hide() end
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
	self:RenderContent()
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
	if not self._tabBadge then return end
	if not label or label == "" then
		self._lastBadge = nil
		self._tabBadge:Hide()
		return
	end
	local text = label
	if value and value ~= "" then
		text = label .. " " .. UI.ColorCode(P.textPrimary) .. value .. "|r"
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
			local t = FS(panel, "groupTitle", C.gold300)
			t:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -M.subgroupPad)
			t:SetText(o.title)
			panel._title = t
		elseif o.title then
			-- v3 (Florian's card mockup): head lives INSIDE the card body — gold
			-- title + optional muted description line; no header bar, no divider,
			-- no accent bar.
			headerH, topInset = (o.subtitle and M.cardHeadSubH or M.cardHeadH), (o.afterHeader or 0)
			local titleFS = FS(panel, "sectionHead", C.gold300)
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
				local subFS = FS(panel, "caption", C.textMuted)
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
				local cfs = FS(chip, "caption", nonzero and P.goldBrand or C.textMuted)
				cfs:SetText(tostring(o.count))
				cfs:SetPoint("CENTER", chip, "CENTER", 0, 0)
				chip:SetSize(math.max(M.sectionCountH, math.ceil(cfs:GetStringWidth()) + M.sectionCountPad * 2), M.sectionCountH)
				chip:SetPoint("LEFT", titleFS, "RIGHT", M.sectionCountGap, 0)
				UI.RoundBorder(chip, nonzero and UI.goldA(0.40) or L.soft, "OVERLAY", nil, UI.RADIUS.xs)
			end
			-- v2 refinement no. 2: quiet header action (e.g. "Restore defaults") on the
			-- right — declutters the card footer; muted, golden on hover.
			if o.action then
				local act = CreateFrame("Button", nil, panel)
				local afs = FS(act, "value", C.textMuted)
				afs:SetText(o.action.text or "")
				afs:SetPoint("CENTER", act, "CENTER", 0, 0)
				act:SetSize(math.ceil(afs:GetStringWidth()) + 12, M.cardHeadH)
				act:SetPoint("RIGHT", panel, "TOPRIGHT", -pad, titleMidY)
				act:SetScript("OnEnter", function() afs:SetTextColor(P.goldIntHover.r, P.goldIntHover.g, P.goldIntHover.b) end)
				act:SetScript("OnLeave", function() afs:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b) end)
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
		end

		local rowPad = outerPad + pad -- row indent of the box WITHIN holder
		local inner, iy, pending = {}, topY - headerH - topInset, nil
		local function anchor(widget, h, full)
			if pending then iy = iy - pending end
			widget:SetParent(host)
			widget:ClearAllPoints()
			widget:SetPoint("TOPLEFT", host, "TOPLEFT", rowPad, iy)
			if full then widget:SetPoint("TOPRIGHT", host, "TOPRIGHT", -rowPad, iy) end
			if h then widget:SetHeight(h) end
			iy = iy - (h or widget:GetHeight())
		end
		function inner.place(_, widget, h, gap) anchor(widget, h, true); pending = gap or 22 end
		function inner.placeLeft(_, widget, h, gap) anchor(widget, h, false); pending = gap or 22 end
		function inner.gap(_, dy) iy = iy - (dy or 8) end
		function inner.y() return iy end
		-- Nested lighter sub-box at the current position; same API.
		function inner.subgroup(_, o2)
			o2 = o2 or {}
			if pending then iy = iy - pending; pending = nil end -- apply pending BEFORE the box
			local sub = makeBox(iy, {
				holder = host, outerPad = rowPad, pad = M.subgroupPad,
				fill = C.ink520, border = L.faint,
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
			outerPad = 0, pad = M.sectionPad, fill = C.ink600, border = L.soft,
			title = title, afterHeader = M.sectionAfterHeader,
			count = opts and opts.count, action = opts and opts.action,
			toggle = opts and opts.toggle, subtitle = opts and opts.subtitle,
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
		for i = 1, n do
			local colF = CreateFrame("Frame", nil, bandF)
			colF:SetFrameLevel(bandF:GetFrameLevel())
			cols[i] = colF
		end
		local function layout(w)
			if not w or w <= 0 then return end
			local usable = w - G.cardGap * (n - 1)
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
				fill = C.ink600, border = L.soft,
				title = def.title, afterHeader = M.sectionAfterHeader,
				count = def.count, action = def.action, toggle = def.toggle,
				subtitle = def.subtitle,
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
	self._previewOpen = v and true or false
	self:_UpdateDock(self._previewKey)
end
function Shell:TogglePreview() self:SetPreviewOpen(not self._previewOpen) end

function Shell:_UpdateDock(key)
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

	-- Leaving a screen (navigation): it may ask to be rebuilt fresh on its
	-- next visit (ns.ScreenLeft — e.g. the Raid/Group tabs auto-collapse
	-- their sections). Dropping the cache entry BEFORE the put-away below
	-- orphans the old frame instead of parking it.
	if self._lastKey and self._lastKey ~= key
		and ns.ScreenLeft and ns.ScreenLeft(self._lastKey) then
		cache[self._lastKey] = nil
	end
	self._lastKey = key

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
	local hit = cache[key]
	if hit then
		self._screen, self._popovers = hit.frame, hit.popovers
		-- New (lazily created) popovers of reused widgets must land in THIS
		-- screen's list again, not in the last-built screen's.
		if ns.W and ns.W.CapturePopovers then ns.W.CapturePopovers(hit.popovers) end
		hit.frame:Show()
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
	if sec.soon then
		self:ComingSoon(d, stack, sec[1])
	else
		local builder = ns.Screens and ns.Screens[key]
		if builder then
			-- Wrap the builder defensively: a screen error must NOT empty the whole Shell
			-- (otherwise just an empty tab without a hint). Print the error to chat.
			local ok, err = pcall(builder, d, stack)
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
	if not d._builtHidden then
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
	UI.RoundFill(card, C.ink600)
	UI.RoundBorder(card, L.soft, "OVERLAY")

	local head = FS(card, "section", C.gold300)
	head:SetText(UI.Track("COMING SOON", " "))
	head:SetPoint("TOP", card, "TOP", 0, -40)

	local body = FS(card, "hint", C.textMuted)
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
