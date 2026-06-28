local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell (phase 1: visual scaffold)
--  Own runed config look following the Lumen design system (see Shell/Tokens).
--  Phase 1 = chrome (header/nav/tabs/footer/rune) + dummy content for a look check.
--  Runs IN PARALLEL to the existing AceConfig (which stays on /lumen). Calling the
--  Shell during development: /lumen shell.
--  Widget toolkit + real screens follow in phase 2/3.
-- ===========================================================================

local UI = ns.UI
local C, L, S, PANEL = UI.C, UI.line, UI.S, UI.PANEL
local T = ns.T   -- localization: T("english") -> display in the active language

local Shell = {}
ns.Shell = Shell

-- ---------------------------------------------------------------------------
--  Small build helpers — the primitives now live centrally in Tokens (ns.UI),
--  so Shell chrome AND widget toolkit use the same ones (DRY).
-- ---------------------------------------------------------------------------
local setColor, fill, border, FS = UI.SetColor, UI.Fill, UI.Border, UI.FS

-- ---------------------------------------------------------------------------
--  Rune-Ornament (concentric circles + rotated square + radiating ticks),
--  vector-drawn via CreateLine. Corner mark, low-opacity.
-- ---------------------------------------------------------------------------
local function runeLine(holder, x1, y1, x2, y2, a)
	local ln = holder:CreateLine(nil, "ARTWORK")
	ln:SetThickness(1)
	ln:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, a)
	ln:SetStartPoint("CENTER", holder, x1, y1)
	ln:SetEndPoint("CENTER", holder, x2, y2)
	return ln
end

local function runeCircle(holder, radius, segments, a)
	local prevX, prevY
	for i = 0, segments do
		local ang = (i / segments) * math.pi * 2
		local x, y = math.cos(ang) * radius, math.sin(ang) * radius
		if prevX then runeLine(holder, prevX, prevY, x, y, a) end
		prevX, prevY = x, y
	end
end

local function drawRune(parent, point, ox, oy, scaleF, alpha)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(2, 2)
	holder:SetPoint("CENTER", parent, point, ox, oy)
	local s = scaleF or 1
	local a = alpha or 0.40
	runeCircle(holder, 60 * s, 40, a)
	runeCircle(holder, 43 * s, 36, a)
	runeCircle(holder, 20 * s, 28, a)
	-- rotated square (diamond) — corner points at ±30
	local q = 30 * s
	runeLine(holder, 0, q, q, 0, a)
	runeLine(holder, q, 0, 0, -q, a)
	runeLine(holder, 0, -q, -q, 0, a)
	runeLine(holder, -q, 0, 0, q, a)
	-- 8 radial ticks (from r=60 to r=70)
	for i = 0, 7 do
		local ang = (i / 8) * math.pi * 2
		local cx, cy = math.cos(ang), math.sin(ang)
		runeLine(holder, cx * 60 * s, cy * 60 * s, cx * 70 * s, cy * 70 * s, a)
	end
	return holder
end

-- ---------------------------------------------------------------------------
--  Nav item (left rail) — active: 3px gold bar on the left + gold wash + gold label.
-- ---------------------------------------------------------------------------
local function makeNavItem(parent, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(44)
	b:SetPoint("LEFT", parent, "LEFT", 0, 0)
	b:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	-- Gold wash fading to the right (gold left -> transparent right).
	local wash = b:CreateTexture(nil, "BACKGROUND")
	wash:SetAllPoints(b)
	wash:SetColorTexture(1, 1, 1, 1)
	wash:SetGradient("HORIZONTAL",
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.14),
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.00))
	wash:Hide()

	-- Gold bar on the left, full height of the menu item.
	local barL = b:CreateTexture(nil, "ARTWORK")
	barL:SetWidth(3)
	barL:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	barL:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	setColor(barL, C.gold500)
	barL:Hide()

	local txt = FS(b, "nav", C.textBody)
	txt:SetPoint("LEFT", b, "LEFT", S.panelGutter, 0)
	txt:SetText(label)

	b._wash, b._bar, b._txt = wash, barL, txt
	b:SetScript("OnEnter", function(self)
		if self._soon then
			if ns.W and ns.W.ShowTextTip then
				ns.W.ShowTextTip(self, T("Coming soon"), T("This module is still in progress and will be unlocked in a later version."))
			end
		elseif not self._active then
			self._txt:SetTextColor(C.gold200.r, C.gold200.g, C.gold200.b)
		end
	end)
	b:SetScript("OnLeave", function(self)
		if self._soon then
			if ns.W and ns.W.HideTip then ns.W.HideTip() end
		elseif not self._active then
			self._txt:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b)
		end
	end)
	function b:SetActive(on)
		self._active = on
		self._wash:SetShown(on); self._bar:SetShown(on)
		local col = on and C.gold250 or (self._soon and C.textFaint or C.textBody)
		self._txt:SetTextColor(col.r, col.g, col.b)
	end
	-- Coming-soon mode: text muted (no chip — greyed out + hover tooltip is enough,
	-- a permanent chip would be redundant), never highlighted as active.
	function b:SetComingSoon(on)
		self._soon = on
		if on then self._txt:SetTextColor(C.textFaint.r, C.textFaint.g, C.textFaint.b) end
	end
	return b
end

-- ---------------------------------------------------------------------------
--  Tab (pill) — active: gold border + gold label + subtle wash.
-- ---------------------------------------------------------------------------
local function makeTab(parent, label)
	local b = CreateFrame("Button", nil, parent)
	local txt = FS(b, "tab", C.textBody)
	txt:SetText(label)
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:SetHeight(36)
	-- Width from the string width. On the first game start the custom-font width is
	-- sometimes still 0 (tabs tiny) -> Fit() re-measures once the panel is visible
	-- (OnShow calls it). Anchors LEFT->prev RIGHT pull the positions along automatically.
	function b:Fit() self:SetWidth(math.floor(txt:GetStringWidth() + 44 + 0.5)) end
	b:Fit()

	-- filled card surface (inactive) — like the prototype (surface-card).
	local base = b:CreateTexture(nil, "BACKGROUND")
	base:SetAllPoints(b); setColor(base, C.ink600)
	-- active gold gradient (lighter on top, fades downward) -> "fade".
	local grad = b:CreateTexture(nil, "ARTWORK")
	grad:SetAllPoints(b); grad:SetColorTexture(1, 1, 1, 1)
	grad:SetGradient("VERTICAL",
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.00),
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.16))
	grad:Hide()
	-- Borders on OVERLAY (ABOVE the gradient) -> active tab keeps the frame all around.
	local edges = border(b, L.soft, 1, "OVERLAY")
	b._txt, b._grad, b._edges = txt, grad, edges

	b:SetScript("OnEnter", function(self)
		if not self._active then
			self._txt:SetTextColor(C.textHeading.r, C.textHeading.g, C.textHeading.b)
			for _, e in ipairs(self._edges) do setColor(e, L.mid) end
		end
	end)
	b:SetScript("OnLeave", function(self)
		if not self._active then
			self._txt:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b)
			for _, e in ipairs(self._edges) do setColor(e, L.soft) end
		end
	end)
	function b:SetActive(on)
		self._active = on
		self._grad:SetShown(on)
		local ec = on and L.strong or L.soft
		for _, e in ipairs(self._edges) do setColor(e, ec) end
		local tc = on and C.gold250 or C.textBody
		self._txt:SetTextColor(tc.r, tc.g, tc.b)
		-- NO weight change active/inactive: SemiBold vs Medium have different glyph
		-- widths -> the centered text would "jump" in the fixed-width button (the width
		-- was measured once via Fit() with the tab-role font = hankenMed). The active tab
		-- stands out via gold color + gradient + a stronger frame; the weight stays
		-- constant (hankenMed) so nothing jumps.
	end
	return b
end

-- ---------------------------------------------------------------------------
--  Close X (top right) — two gold lines, hover brightens. Fits the line-SVG
--  iconography of the design system (✕ unicode is not reliable in the font).
-- ---------------------------------------------------------------------------
local function makeCloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(34, 34)
	local radius = 15

	-- Round hover surface (circular via alpha mask), visible only on hover.
	local hoverFill = b:CreateTexture(nil, "BACKGROUND")
	hoverFill:SetSize(radius * 2, radius * 2); hoverFill:SetPoint("CENTER", b, "CENTER", 0, 0)
	hoverFill:SetTexture([[Interface\Buttons\WHITE8X8]])
	hoverFill:SetVertexColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.12)
	local mask = b:CreateMaskTexture()
	mask:SetAllPoints(hoverFill)
	mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	hoverFill:AddMaskTexture(mask)
	hoverFill:Hide()

	-- Thin gold ring (like the corner runes) — always visible, makes it a rune.
	local ring, seg, prevX, prevY = {}, 32, nil, nil
	for i = 0, seg do
		local ang = (i / seg) * math.pi * 2
		local x, y = math.cos(ang) * radius, math.sin(ang) * radius
		if prevX then
			local ln = b:CreateLine(nil, "ARTWORK")
			ln:SetThickness(1)
			ln:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, 0.50)
			ln:SetStartPoint("CENTER", b, prevX, prevY)
			ln:SetEndPoint("CENTER", b, x, y)
			ring[#ring + 1] = ln
		end
		prevX, prevY = x, y
	end

	-- X in the center.
	local g7 = 7
	local function arm(x1, y1, x2, y2)
		local ln = b:CreateLine(nil, "OVERLAY")
		ln:SetThickness(2)
		ln:SetColorTexture(C.gold300.r, C.gold300.g, C.gold300.b, 1)
		ln:SetStartPoint("CENTER", b, x1, y1)
		ln:SetEndPoint("CENTER", b, x2, y2)
		return ln
	end
	local a1 = arm(-g7, g7, g7, -g7)
	local a2 = arm(-g7, -g7, g7, g7)

	local function setRing(c, a)
		for _, ln in ipairs(ring) do ln:SetColorTexture(c.r, c.g, c.b, a) end
	end
	local function setArms(c)
		a1:SetColorTexture(c.r, c.g, c.b, 1); a2:SetColorTexture(c.r, c.g, c.b, 1)
	end
	b:SetScript("OnEnter", function() hoverFill:Show(); setRing(C.gold200, 0.9); setArms(C.gold100) end)
	b:SetScript("OnLeave", function() hoverFill:Hide(); setRing(C.gold500, 0.5); setArms(C.gold300) end)
	b:SetScript("OnClick", onClick)
	return b
end

-- ===========================================================================
--  Building the panel (once)
-- ===========================================================================
-- soon = true: module not ready yet -> nav entry muted + "Coming soon" chip,
-- click only shows the coming-soon placeholder page (no tabs, no activation).
local SECTIONS = {
	{ "Global",      { "Base", "Profile" } },
	{ "Click-Cast",  { "Bindings" } },
	{ "Raidframes",  { "Base", "Raid", "Group", "Auras", "Tracking" } },
	{ "Unitframes",  {}, soon = true },
	{ "Nameplates",  {}, soon = true },
	{ "QoL",         {}, soon = true },
}

function Shell:Build()
	if self._frame then return self._frame end

	-- Outer Panel ------------------------------------------------------------
	local f = CreateFrame("Frame", "LumenShellFrame", UIParent)
	f:SetSize(PANEL.w, PANEL.h)
	f:SetScale(PANEL.scale)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "LumenShellFrame") -- ESC closes
	self._frame = f

	-- Float the select popover on this (non-clipped) panel, otherwise the content
	-- ScrollFrame clips it. RenderContent sets the collection list.
	if ns.W and ns.W.SetMenuHost then ns.W.SetMenuHost(f) end

	-- On show, rebuild the current tab: the first render in Build runs still hidden
	-- (sizes unresolved) -> some cells (e.g. the first dispel color) land wrong until
	-- you switch tabs. Re-render in the visible state.
	f:SetScript("OnShow", function()
		-- Re-measure tabs: on the first show after game start the font width was maybe
		-- still 0 (tabs tiny). Anchors pull the positions along automatically.
		if Shell._tabButtons then for _, t in ipairs(Shell._tabButtons) do if t.Fit then t:Fit() end end end
		if Shell._section then Shell:RenderContent() end
	end)

	fill(f, C.ink850, "BACKGROUND")
	-- Radial-glow approximation: vertical gradient (lighter on top) as an overlay.
	local glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	glow:SetAllPoints(f)
	glow:SetColorTexture(1, 1, 1, 1)
	glow:SetGradient("VERTICAL",
		CreateColor(C.ink900.r, C.ink900.g, C.ink900.b, 1),
		CreateColor(C.ink800.r, C.ink800.g, C.ink800.b, 1))
	glow:SetAlpha(0.6)
	border(f, L.mid, 1)

	-- Rune corners (low-opacity ornament)
	drawRune(f, "TOPLEFT",      80,  -80, 1, 0.40)
	drawRune(f, "TOPRIGHT",    -80,  -80, 1, 0.40)
	drawRune(f, "BOTTOMRIGHT", -80,   80, 1, 0.40)
	drawRune(f, "BOTTOMLEFT",   80,   80, 1, 0.40)

	-- Header -----------------------------------------------------------------
	local header = CreateFrame("Frame", nil, f)
	header:SetHeight(PANEL.headerH)
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	local hsep = header:CreateTexture(nil, "ARTWORK")
	hsep:SetHeight(1); hsep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	hsep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0); setColor(hsep, L.divider)

	local word = FS(header, "wordmark", C.gold300)
	word:SetText(UI.Track("LUMEN", "  ")) -- tracking emulation
	word:SetPoint("CENTER", header, "CENTER", 0, 8)
	local tag = FS(header, "tagline", C.textMuted)
	tag:SetText(UI.Track("a focused ui suite", " "))
	tag:SetPoint("TOP", word, "BOTTOM", 0, -8)

	-- Footer -----------------------------------------------------------------
	local footer = CreateFrame("Frame", nil, f)
	footer:SetHeight(PANEL.footerH)
	footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	local fsep = footer:CreateTexture(nil, "ARTWORK")
	fsep:SetHeight(1); fsep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
	fsep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0); setColor(fsep, L.divider)

	-- Close X in the top-right corner.
	local closeBtn = makeCloseButton(f, function() Shell:Hide() end)
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
	closeBtn:SetFrameLevel(f:GetFrameLevel() + 50)

	-- Body: Nav-Rail + Main --------------------------------------------------
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	body:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)

	local nav = CreateFrame("Frame", nil, body)
	nav:SetWidth(S.navWidth)
	nav:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	nav:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)

	local main = CreateFrame("Frame", nil, body)
	main:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
	main:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

	-- Vertical nav divider: on MAIN (draws over nav + its buttons), left edge.
	local nsep = main:CreateTexture(nil, "OVERLAY")
	nsep:SetWidth(1); nsep:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
	nsep:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, 0); setColor(nsep, L.divider)

	-- Tab-Strip
	local tabStrip = CreateFrame("Frame", nil, main)
	tabStrip:SetHeight(36)
	tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", S.panelGutter, -22)
	tabStrip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -S.panelGutter, -22)

	-- Content area: scrollable (screens are taller than the fixed content height).
	-- ScrollFrame + scroll child; the screens build into the child. Slim gold
	-- scrollbar on the right in the gutter (mouse wheel + draggable thumb).
	local scroll = CreateFrame("ScrollFrame", nil, main)
	scroll:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -26)
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
		local range = scroll:GetVerticalScrollRange() or 0
		local h = scroll:GetHeight() or 1
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

	-- Nav-Buttons
	self._navButtons = {}
	local prev
	for i, sec in ipairs(SECTIONS) do
		local nb = makeNavItem(nav, sec[1])
		if prev then nb:SetPoint("TOP", prev, "BOTTOM", 0, -2)
		else nb:SetPoint("TOP", nav, "TOP", 0, -S.s8) end
		nb._index = i
		if sec.soon then nb:SetComingSoon(true) end
		nb:SetScript("OnClick", function() Shell:SelectSection(i) end)
		self._navButtons[i] = nb
		prev = nb
	end

	self._tabStrip = tabStrip
	self._tabButtons = {}

	-- Initial state
	Shell:SelectSection(3) -- Raidframes (like the prototype default)
	return f
end

-- Rebuild the tab strip for the current section.
function Shell:RebuildTabs(sectionIndex)
	for _, t in ipairs(self._tabButtons) do t:Hide(); t:SetParent(nil) end
	wipe(self._tabButtons)
	local tabs = SECTIONS[sectionIndex][2]
	local prev
	for i, label in ipairs(tabs) do
		local tb = makeTab(self._tabStrip, label)
		if prev then tb:SetPoint("LEFT", prev, "RIGHT", S.s3, 0)
		else tb:SetPoint("LEFT", self._tabStrip, "LEFT", 0, 0) end
		tb._index = i
		tb:SetScript("OnClick", function() Shell:SelectTab(i) end)
		self._tabButtons[i] = tb
		prev = tb
	end
	-- Re-measure one frame later: on the very first build (panel still hidden /
	-- fonts maybe not ready) GetStringWidth returns 0 -> tiny tabs.
	C_Timer.After(0, function()
		for _, t in ipairs(self._tabButtons) do if t.Fit then t:Fit() end end
	end)
	Shell:SelectTab(1)
end

function Shell:SelectSection(index)
	self._section = index
	local sec = SECTIONS[index]
	-- Never highlight coming-soon modules as active (they stay muted + chip).
	for i, nb in ipairs(self._navButtons) do nb:SetActive(i == index and not sec.soon) end
	if sec.soon then
		-- No tabs, no tab selection — render the placeholder page directly.
		for _, t in ipairs(self._tabButtons) do t:Hide(); t:SetParent(nil) end
		wipe(self._tabButtons)
		self._tab = nil
		self:RenderContent()
	else
		self:RebuildTabs(index)
	end
end

function Shell:SelectTab(index)
	self._tab = index
	for i, tb in ipairs(self._tabButtons) do tb:SetActive(i == index) end
	self:RenderContent()
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

		local panel = CreateFrame("Frame", nil, holder)
		-- Card as background layer: frame level at holder level so the later-created
		-- content frames (siblings, NOT children of the card) render above it.
		panel:SetFrameLevel(holder:GetFrameLevel())
		panel:SetPoint("TOPLEFT", holder, "TOPLEFT", outerPad, topY)
		panel:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -outerPad, topY)
		fill(panel, o.fill)
		-- Frame on OVERLAY: the header bar (hbar, ARTWORK) would otherwise sit ABOVE the
		-- frame and cover the thin gold line on top + right in the header area.
		border(panel, o.border, 1, "OVERLAY")

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
			headerH, topInset = M.sectionHeaderH, (o.afterHeader or 0)
			-- Header bar (slightly lighter) + fine divider below it + gold accent on the left.
			local hbar = panel:CreateTexture(nil, "ARTWORK")
			hbar:SetHeight(headerH)
			hbar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
			hbar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
			setColor(hbar, C.ink550)
			local hsep = panel:CreateTexture(nil, "OVERLAY")
			PixelUtil.SetHeight(hsep, 1)
			hsep:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -headerH)
			hsep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -headerH)
			setColor(hsep, L.faint)
			local accent = panel:CreateTexture(nil, "OVERLAY")
			accent:SetWidth(M.sectionHeaderBarW)
			accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
			accent:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, -headerH)
			setColor(accent, C.gold500)
			local titleFS = FS(panel, "sectionHead", C.gold300)
			titleFS:SetPoint("LEFT", panel, "TOPLEFT", M.sectionTitleX, -headerH / 2)
			titleFS:SetText(o.title)
			panel._title = titleFS
		end

		local rowPad = outerPad + pad -- row indent of the box WITHIN holder
		local inner, iy, pending = {}, topY - headerH - topInset, nil
		local function anchor(widget, h, full)
			if pending then iy = iy - pending end
			widget:SetParent(holder)
			widget:ClearAllPoints()
			widget:SetPoint("TOPLEFT", holder, "TOPLEFT", rowPad, iy)
			if full then widget:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -rowPad, iy) end
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
				outerPad = rowPad, pad = M.subgroupPad,
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
	function stack:section(title)
		local M = UI.WIDGET
		local inner = makeBox(y, {
			outerPad = 0, pad = M.sectionPad, fill = C.ink600, border = L.soft,
			title = title, afterHeader = M.sectionAfterHeader,
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

	return stack
end

-- Screens (Shell/Screens.lua) need the same stacker for their own sub-frames
-- (e.g. the Base screen builds its gateable body via its own stack).
Shell.NewStack = newStack

-- Render content for the current section/tab: real screen (Shell/Screens.lua) if
-- registered, otherwise the widget gallery (phase-2 fallback). Then set the scroll
-- child height, scroll to top, update the scrollbar.
function Shell:RenderContent(keepScroll)
	local prevScroll = (keepScroll and self._scroll and self._scroll:GetVerticalScroll()) or 0
	local holderParent = self._scrollChild
	if self._screen then self._screen:Hide(); self._screen:SetParent(nil); self._screen = nil end
	-- Release the previous screen's popovers (on the panel host), then set a fresh list.
	if self._popovers then
		for _, fr in ipairs(self._popovers) do fr:Hide(); fr:SetParent(nil) end
	end
	self._popovers = {}
	if ns.W and ns.W.CapturePopovers then ns.W.CapturePopovers(self._popovers) end

	local d = CreateFrame("Frame", nil, holderParent)
	d:SetPoint("TOPLEFT", holderParent, "TOPLEFT", 0, 0)
	d:SetPoint("TOPRIGHT", holderParent, "TOPRIGHT", 0, 0)
	self._screen = d

	local stack = newStack(d)
	local sec = SECTIONS[self._section]
	if sec.soon then
		self:ComingSoon(d, stack, sec[1])
	else
		local key = sec[1] .. "/" .. (sec[2][self._tab] or "")
		local builder = ns.Screens and ns.Screens[key]
		if builder then
			-- Wrap the builder defensively: a screen error must NOT empty the whole Shell
			-- (otherwise just an empty tab without a hint). Print the error to chat.
			local ok, err = pcall(builder, d, stack)
			if not ok and ns.Lumen then
				ns.Lumen:Print("|cffD66A5CShell-Fehler in " .. key .. ":|r " .. tostring(err))
			end
		else
			self:Gallery(d, stack)
		end
	end

	local h = stack:height()
	d:SetHeight(h)
	holderParent:SetHeight(h)
	if self._scroll then
		-- On a forced rebuild (e.g. role reordering) keep the scroll position,
		-- otherwise it jumps to the top.
		local range = self._scroll:GetVerticalScrollRange() or 0
		self._scroll:SetVerticalScroll(math.max(0, math.min(range, prevScroll)))
	end
	if self._updateBar then self._updateBar() end
end

-- ---------------------------------------------------------------------------
--  Widget gallery (phase 2): shows the complete toolkit (divider, slider,
--  select, checkbox, GroupPanel, buttons, card) live-operable — so Florian can
--  judge look AND feel in-game. Sandbox data (not yet db-wired).
-- ---------------------------------------------------------------------------
local W = ns.W
local M = UI.WIDGET

-- Sandbox state so the widgets react interactively (no db writes).
local demo = {
	breite = 114, hoehe = 60, abstand = 2,
	ausrichtung = "vertical",
	nameShow = true, nameColor = false, nameSize = 12,
	outline = "none",
	hotsOn = true,
}
local function g(k) return function() return demo[k] end end
local function s(k) return function(v) demo[k] = v end end

local ALIGN_OPTS = {
	{ value = "vertical",   label = "Vertikal — Mitglieder untereinander" },
	{ value = "horizontal", label = "Horizontal — Mitglieder nebeneinander" },
}
local OUTLINE_OPTS = {
	{ value = "none", label = "Keine" }, { value = "thin", label = "Dünn" },
	{ value = "thick", label = "Dick" }, { value = "mono", label = "Monochrom" },
}

function Shell:Gallery(d, stack)
	local place = function(w, h, dy) stack:place(w, h, dy) end

	local secName = SECTIONS[self._section][1]
	local tabName = SECTIONS[self._section][2][self._tab] or "?"

	-- 1) Section-Divider
	place(W.SectionDivider(d, secName .. " · " .. tabName), M.dividerH, 24)

	-- 2) Three sliders side by side (row3)
	local sliderRow, cells = W.Row(d, 3, { height = M.sliderH })
	W.Slider(cells[1], { label = "Breite", min = 40, max = 240, value = demo.breite, unit = " px",
		get = g("breite"), set = s("breite") }):SetAllPoints(cells[1])
	W.Slider(cells[2], { label = "Höhe", min = 20, max = 160, value = demo.hoehe, unit = " px",
		get = g("hoehe"), set = s("hoehe") }):SetAllPoints(cells[2])
	W.Slider(cells[3], { label = "Abstand", min = 0, max = 30, value = demo.abstand, unit = " px",
		get = g("abstand"), set = s("abstand") }):SetAllPoints(cells[3])
	place(sliderRow, M.sliderH, 22)

	-- 3) Two dropdowns (alignment + outline) as a 2-column row
	local fieldH = M.controlH + M.fieldGap
	local ddRow, ddCells = W.Row(d, 2, { height = fieldH })
	W.Select(ddCells[1], { label = "Ausrichtung", options = ALIGN_OPTS,
		get = g("ausrichtung"), set = s("ausrichtung") }):SetAllPoints(ddCells[1])
	W.Select(ddCells[2], { label = "Namens-Umrandung", options = OUTLINE_OPTS,
		get = g("outline"), set = s("outline") }):SetAllPoints(ddCells[2])
	place(ddRow, fieldH, 24)

	-- 4) Checkbox row
	local cbRow = CreateFrame("Frame", nil, d)
	local cb1 = W.Checkbox(cbRow, { label = "Name anzeigen", get = g("nameShow"), set = s("nameShow") })
	cb1:SetPoint("LEFT", cbRow, "LEFT", 0, 0)
	local cb2 = W.Checkbox(cbRow, { label = "Namensfarbe", get = g("nameColor"), set = s("nameColor") })
	cb2:SetPoint("LEFT", cb1, "RIGHT", 28, 0)
	place(cbRow, M.checkBox, 26)

	-- 5) GroupPanel with header-right toggle + content
	local panel, pc = W.GroupPanel(d, { title = "HoTs" })
	panel._headerRightAnchor(W.Checkbox(panel, { label = "Anzeigen", get = g("hotsOn"), set = s("hotsOn") }))
	local pcSlider = W.Slider(pc, { label = "Namensgröße", min = 6, max = 30, value = demo.nameSize,
		get = g("nameSize"), set = s("nameSize") })
	pcSlider:SetPoint("TOPLEFT", pc, "TOPLEFT", 0, 0)
	pcSlider:SetWidth(320)
	place(panel, -M.groupContentY + M.sliderH + S.cardPad, 24)

	-- 6) Button row (primary / ghost / danger)
	local btnRow = CreateFrame("Frame", nil, d)
	local pb = W.Button(btnRow, { text = "Übernehmen", variant = "primary" })
	pb:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
	local gb = W.Button(btnRow, { text = "Standard", variant = "ghost" })
	gb:SetPoint("LEFT", pb, "RIGHT", 12, 0)
	local db = W.Button(btnRow, { text = "Zurücksetzen", variant = "danger" })
	db:SetPoint("LEFT", gb, "RIGHT", 12, 0)
	place(btnRow, M.buttonH, 22)

	-- 7) Card with IconTile + text (signature surface)
	local card = W.Card(d)
	local tile = W.IconTile(card, { size = 52, letter = "L" })
	tile:SetPoint("LEFT", card, "LEFT", S.cardPad, 0)
	local ct = FS(card, "body", C.textBody)
	ct:SetJustifyH("LEFT"); ct:SetWordWrap(true)
	ct:SetPoint("LEFT", tile, "RIGHT", 16, 0)
	ct:SetPoint("RIGHT", card, "RIGHT", -S.cardPad, 0)
	ct:SetText("Toolkit-Bausteine: Slider, Select, Checkbox, Button, GroupPanel, "
		.. "Card, IconTile — alle auf den Design-Tokens und pixel-gesnappten Borders.")
	place(card, 92, 22)

	-- 8) Hint
	local hint = FS(d, "caption", C.textFaint)
	hint:SetText("Phase 2 — Widget-Toolkit (live bedienbar, noch Sandbox-Daten). "
		.. "/lumen öffnet weiterhin die klassische Konfiguration.")
	hint:SetPoint("TOPLEFT", d, "TOPLEFT", 0, stack:y())
	stack:gap(M.hintH) -- account for the hint block in the height
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
	fill(card, C.ink600)
	border(card, L.soft, 1, "OVERLAY")

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
	if self._frame then self._frame:Hide() end
end
