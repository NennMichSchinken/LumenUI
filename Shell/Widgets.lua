local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell widget toolkit (phase 2)
--  Reusable building blocks following the Lumen design system (Shell/Tokens).
--  Pattern: a widget factory (`:Slider/:Dropdown/:Toggle(parent,
--  …, get, set)`), look 1:1 from the prototype (components/core/*.jsx).
--
--  Convention: every widget is SELF-DIMENSIONED (knows its height) and
--  takes an options table `o`. Data comes via `o.get()`/`o.set(v)`
--  (or a static `o.value`). Full width = anchor the parent via TOPLEFT/RIGHT;
--  fixed width via `o.width`. Multi-column rows are built by the caller
--  with W.Row(...) (equal-width cells).
-- ===========================================================================

local UI = ns.UI
local C, L, S, M, P = UI.C, UI.line, UI.S, UI.WIDGET, UI.P
local LO = UI.LAYOUT -- screen-specific measures (NOTE: L is UI.line in this file)
local T = ns.T   -- localization: T("english") -> display in the active language
-- Texture folder, built from the real addon-folder name (survives a rename).
local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"

local W = {}
ns.W = W

-- Popover host + collection list for select menus. Selects inside a ScrollFrame would
-- be clipped -> their menus float on a non-clipped host (set by the Shell onto the
-- panel). The Shell passes a fresh collection list per screen and cleans up the
-- previous one on tab switch (no leak).
W._menuHost = nil
W._popovers = nil
function W.SetMenuHost(frame) W._menuHost = frame end
function W.CapturePopovers(list) W._popovers = list end

local CONTROL_H = M.controlH
local RAD = UI.RADIUS          -- the radius scale (xs/sm/md/lg/xl, see Tokens)
local R_CTRL = UI.ROUND_R_CTRL -- control-face corner radius (= RAD.md)
local CLEAR = { r = 0, g = 0, b = 0, a = 0 } -- transparent reset for round-aware recolors

-- ---------------------------------------------------------------------------
--  Internal helpers
-- ---------------------------------------------------------------------------
local function clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi else return v end
end


-- (SectionDivider + SectionLabel retired with the Click-Cast card migration —
-- every section is a real card now; the gold-rule dividers had no callers left.)

-- ---------------------------------------------------------------------------
--  SquareIcon — square spell/item icon chip with a clear gold border. :SetIcon(tex)
--  (nil = neutral fill). The standard left tile of the Click-Cast catalog rows.
-- ---------------------------------------------------------------------------
function W.SquareIcon(parent, size)
	local t = CreateFrame("Frame", nil, parent)
	t:SetSize(size, size)
	UI.Fill(t, C.ink850)
	UI.Border(t, L.strong, 1, "OVERLAY")
	local tex = t:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	t.tex = tex
	function t:SetIcon(icon)
		if icon then tex:SetTexture(icon)
		else tex:SetColorTexture(C.ink700.r, C.ink700.g, C.ink700.b, 1) end
	end
	return t
end

-- ---------------------------------------------------------------------------
--  IconButton — small square button showing a tinted texture from Textures/ (e.g.
--  the red delete bin). o = { icon (file name, no ext), color?, hoverColor?, size?,
--  onClick, tooltip? }.
-- ---------------------------------------------------------------------------
function W.IconButton(parent, o)
	local b = CreateFrame("Button", nil, parent)
	local sz = o.size or M.iconAction
	b:SetSize(sz, sz)
	-- Hover surface (v2 close-button pattern): the color step alone is too
	-- subtle on small glyphs (danger E1->E2 is near-invisible at 22px). It
	-- extends iconBtnHoverPad past the glyph so it reads as a button face.
	local bg = UI.RoundFill(b, P.elementHover, "BACKGROUND", nil, RAD.sm)
	bg:ClearAllPoints()
	bg:SetPoint("TOPLEFT", b, "TOPLEFT", -M.iconBtnHoverPad, M.iconBtnHoverPad)
	bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", M.iconBtnHoverPad, -M.iconBtnHoverPad)
	bg:Hide()
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints(b)
	tex:SetTexture(TEX .. o.icon)
	-- File textures get no mipmaps: keep sampling smooth instead of texel-snapped.
	tex:SetSnapToPixelGrid(false)
	tex:SetTexelSnappingBias(0)
	-- Two-gold rule: clickable icon = interactive gold (C2), hover = C3.
	local col, hov = o.color or C.gold500, o.hoverColor or C.gold400
	tex:SetVertexColor(col.r, col.g, col.b, 1)
	b:SetScript("OnEnter", function() bg:Show(); tex:SetVertexColor(hov.r, hov.g, hov.b, 1); if o.tooltip then W.ShowTextTip(b, o.tooltip) end end)
	b:SetScript("OnLeave", function() bg:Hide(); tex:SetVertexColor(col.r, col.g, col.b, 1); if o.tooltip then W.HideTip() end end)
	if o.onClick then b:SetScript("OnClick", o.onClick) end
	b._tex = tex
	return b
end

-- ---------------------------------------------------------------------------
--  Field — label above a control (v2: primary text, no longer gold — gold is
--  reserved for headers/actives). Returns (container, contentTopYOffset).
--  The caller anchors its control at TOPLEFT/RIGHT, container, ..., 0, yOff.
-- ---------------------------------------------------------------------------
local function fieldLabel(parent, text)
	local lbl = UI.FS(parent, "fieldLabel", C.textStrong)
	lbl:SetText(text)
	lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	lbl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	lbl:SetJustifyH("LEFT")
	return lbl, -M.fieldGap -- yOffset for the control below
end

-- ---------------------------------------------------------------------------
--  Slider — gold track, label on top, min/max at the ends, value box below.
--  Pointer-driven (no native slider frame). o = {label,min,max,step,
--  get,set,value,unit,width,compact}. Height ~80; compact ~40 (card grid
--  system: label + inline value share the top line, full-width track below).
-- ---------------------------------------------------------------------------
function W.Slider(parent, o)
	local minV, maxV, step = o.min or 0, o.max or 100, o.step or 1
	local compact = o.compact
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(compact and M.sliderCompactH or M.sliderH)
	if o.width then f:SetWidth(o.width) end

	-- Compact = a field cell: label in the same small style as Select/Swatch
	-- labels (the Cinzel slider cap is too wide there and wraps). Classic
	-- keeps the display cap.
	local cap = UI.FS(f, compact and "fieldLabel" or "sliderCap", compact and C.textStrong or C.gold300)
	cap:SetText(o.label or "")
	cap:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
	if compact then -- keep the label clear of the inline value on the right
		cap:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(M.sliderCompactValW + M.sliderEndPad), -2)
		cap:SetWordWrap(false)
	end
	cap:SetJustifyH("LEFT")

	-- Track row: [min] —— track —— [max] (compact: track only, full width —
	-- the bounds still clamp dragging/typing, they just aren't printed).
	local row = CreateFrame("Frame", nil, f)
	row:SetHeight(M.sliderTrackH)
	local capGap = o.capGap or (compact and M.sliderCompactCapGap or M.sliderCapGap)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -capGap)
	row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -capGap)

	local track = CreateFrame("Frame", nil, row)
	track:SetHeight(M.sliderTrackH)
	local minL, maxL
	if compact then
		track:SetPoint("LEFT", row, "LEFT", 0, 0)
		track:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	else
		minL = UI.FS(row, "ends", C.textMuted)
		minL:SetText(tostring(minV)); minL:SetWidth(M.sliderEndW); minL:SetJustifyH("RIGHT")
		minL:SetPoint("LEFT", row, "LEFT", 0, 0)
		maxL = UI.FS(row, "ends", C.textMuted)
		maxL:SetText(tostring(maxV)); maxL:SetWidth(M.sliderEndW); maxL:SetJustifyH("LEFT")
		maxL:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		track:SetPoint("LEFT", minL, "RIGHT", M.sliderEndPad, 0)
		track:SetPoint("RIGHT", maxL, "LEFT", -M.sliderEndPad, 0)
	end
	track:EnableMouse(true)

	-- Track + fill as tiny pills (rounded ends, XS scale). The gold fill's right
	-- cap hides under the thumb disc; min width 6 keeps the 3px cap slices valid.
	local bg = UI.PillFill(track, C.sliderTrack, "ARTWORK", M.sliderBarH)
	bg:ClearAllPoints()
	bg:SetHeight(M.sliderBarH)
	bg:SetPoint("LEFT", track, "LEFT", 0, 0)
	bg:SetPoint("RIGHT", track, "RIGHT", 0, 0)

	local fillbar = UI.PillFill(track, C.gold500, "OVERLAY", M.sliderBarH)
	fillbar:ClearAllPoints()
	fillbar:SetHeight(M.sliderBarH)
	fillbar:SetPoint("LEFT", track, "LEFT", 0, 0)

	local thumb = CreateFrame("Frame", nil, track)
	thumb:SetSize(M.sliderThumb, M.sliderThumb)
	-- Round thumb (widget rounding pass): dark backing disc = the old 2px
	-- border, gold disc on top. Both sizes need a matching circle-<n> asset.
	local tBack = UI.Circle(thumb, { r = 0.10, g = 0.09, b = 0.08, a = 1 }, "ARTWORK", M.sliderThumb + 4)
	tBack:SetPoint("CENTER", thumb, "CENTER", 0, 0)
	local tt = UI.Circle(thumb, C.gold500, "OVERLAY", M.sliderThumb)
	tt:SetPoint("CENTER", thumb, "CENTER", 0, 0)

	-- Value — editable EditBox: click, type a number, Enter confirms (clamped
	-- to min/max + step), Esc discards. Classic: framed box below the track.
	-- Compact: bare gold value inline on the label line (no field chrome; the
	-- text brightens while it has focus instead of a border).
	local box = CreateFrame("EditBox", nil, f)
	local boxEdges
	if compact then
		box:SetSize(M.sliderCompactValW, M.sliderCompactValH)
		box:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
		UI:SetFont(box, "value", C.gold500)
		box:SetJustifyH("RIGHT")
		-- Subtle field affordance so the inline value reads as a TYPEABLE input
		-- (Florian 2026-07-14: the drag can't reliably hit exact px -> click the
		-- value to type an exact number). Border brightens on focus (boxEdges).
		UI.RoundFill(box, P.inset, "BACKGROUND", nil, RAD.xs)
		boxEdges = UI.RoundBorder(box, L.soft, "OVERLAY", nil, RAD.xs)
	else
		box:SetSize(M.valueBoxW, M.valueBoxH)
		box:SetPoint("TOP", row, "BOTTOM", 0, -M.valueBoxGap)
		UI.RoundFill(box, C.ink700, nil, nil, R_CTRL)
		boxEdges = UI.RoundBorder(box, L.soft, "OVERLAY", nil, R_CTRL)
		UI:SetFont(box, "value", C.textStrong)
		box:SetJustifyH("CENTER")
	end
	box:SetAutoFocus(false)
	box:SetTextInsets(6, 6, 0, 0)

	local cur = (o.get and o.get()) or o.value or minV
	local unit = o.unit or ""
	local typing = false -- true while the EditBox is focused (no clobbering)

	local function visual(v)
		local ratio = (maxV > minV) and clamp((v - minV) / (maxV - minV), 0, 1) or 0
		local w = track:GetWidth() or 0
		fillbar:SetWidth(math.max(6, ratio * w))
		thumb:ClearAllPoints()
		thumb:SetPoint("CENTER", track, "LEFT", ratio * w, 0)
		if not typing then box:SetText(v .. unit) end
	end

	local function valFromCursor()
		local cx = GetCursorPosition()
		local sc = track:GetEffectiveScale()
		if not sc or sc == 0 then return cur end
		cx = cx / sc
		local left, w = track:GetLeft(), track:GetWidth()
		if not left or not w or w == 0 then return cur end
		local ratio = clamp((cx - left) / w, 0, 1)
		local v = minV + ratio * (maxV - minV)
		v = math.floor(v / step + 0.5) * step
		return clamp(v, minV, maxV)
	end

	-- commitOnRelease: while dragging, update only the visual (thumb + value text);
	-- o.set fires once on mouse-up. Used where set() is expensive or moves the slider
	-- itself (e.g. the shell-scale slider rescales the whole panel under the cursor).
	local deferSet = o.commitOnRelease
	local function commit(v, defer)
		if v == cur then return end
		cur = v
		visual(v)
		if o.set and not defer then o.set(v) end
	end

	-- EditBox: parse the typed value (leading number, also negative), round,
	-- clamp, apply. Focus colors the border more strongly.
	box:SetScript("OnEditFocusGained", function(self)
		typing = true
		-- Let the Edit Mode keyboard catcher yield while typing here, so digits/
		-- Enter/Esc reach this box instead of nudging/closing the session.
		if ns.EditMode then ns.EditMode._fieldFocused = true end
		if boxEdges then for _, e in ipairs(boxEdges) do UI.SetColor(e, L.strong) end
		else self:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b) end
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		typing = false
		if ns.EditMode then ns.EditMode._fieldFocused = false end
		if boxEdges then for _, e in ipairs(boxEdges) do UI.SetColor(e, L.soft) end
		else self:SetTextColor(C.gold500.r, C.gold500.g, C.gold500.b) end
		self:SetText(cur .. unit) -- reset to the canonical state
	end)
	-- Live clamp to max already while typing: 5555 jumps immediately to the max value,
	-- not only on Enter (Florian feedback). The userInput flag prevents recursion
	-- with our own SetText; min is only clamped on Enter (intermediate inputs).
	box:SetScript("OnTextChanged", function(self, userInput)
		if not userInput then return end
		local num = tonumber((self:GetText():gsub("[^%-%d%.]", "")))
		if num and num > maxV then
			self:SetText(tostring(maxV))
			self:SetCursorPosition(#tostring(maxV))
		end
	end)
	box:SetScript("OnEnterPressed", function(self)
		local num = tonumber((self:GetText():gsub("[^%-%d%.]", "")))
		if num then
			num = clamp(math.floor(num / step + 0.5) * step, minV, maxV)
			commit(num)
		end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	local function onUpd() commit(valFromCursor(), deferSet) end
	local function beginDrag() track:SetScript("OnUpdate", onUpd); commit(valFromCursor(), deferSet) end
	local function stopDrag() track:SetScript("OnUpdate", nil) end
	-- Mouse-up = end of a drag: with deferSet, this is where set() finally fires.
	local function endDrag() stopDrag(); if deferSet and o.set then o.set(cur) end end
	track:SetScript("OnMouseDown", beginDrag)
	track:SetScript("OnMouseUp", endDrag)
	track:SetScript("OnHide", stopDrag)   -- just stop; don't commit on a hide
	-- Make the thumb itself grabbable: at the stops (0/100 %) the square sticks out half
	-- past the track — that part used to be dead (only the track was clickable). Mouse-enabled
	-- + 2px larger hit area (purely clickable, visually unchanged) -> easy to grab.
	thumb:EnableMouse(true)
	thumb:SetHitRectInsets(-2, -2, -2, -2)
	thumb:SetScript("OnMouseDown", beginDrag)
	thumb:SetScript("OnMouseUp", endDrag)
	-- Track width is only known after the layout -> redraw on size change.
	track:SetScript("OnSizeChanged", function() visual(cur) end)
	-- Cold-start self-heal (report 2026-07-03): the very first build after a game
	-- start can run before the track width resolves — fill/thumb land at width 0
	-- and, if OnSizeChanged doesn't fire in that window, stay invisible. The
	-- value EditBox additionally keeps its blank first text layout even after
	-- the glyph cache warms (FontStrings self-heal, EditBoxes re-layout only on
	-- the next SetText). Repainting whenever the slider becomes visible covers
	-- both — and keeps reused (cached) screens fresh for free.
	track:SetScript("OnShow", function() visual(cur) end)

	visual(cur)
	-- Cold-start glyph repaint (report 2026-07-14, QoL tab): when the slider is built
	-- into an ALREADY-VISIBLE parent (opening a tab on a cold client), OnShow never fires,
	-- so the value box + min/max labels keep the blank layout the cold glyph cache produced
	-- on the first paint. A one-shot deferred re-set (next frame, after that first paint
	-- forced rasterization) repaints them — same mechanism W.Button uses from creation.
	C_Timer.After(0, function()
		visual(cur)
		if minL then minL:SetText(tostring(minV)); maxL:SetText(tostring(maxV)) end
	end)
	f.SetValueExternal = function(_, v) cur = v; visual(v) end
	-- Grey out + lock interaction (for dependent sections, e.g. "Show name" off).
	-- RECOLOR instead of frame alpha: alpha'd gold over the dark inset boxes
	-- read as "translucent"/broken (Florian 2026-07-04). Disabled = grey
	-- track/thumb (D3) + muted texts; everything stays opaque and crisp.
	f.SetWidgetEnabled = function(_, on)
		track:EnableMouse(on)
		thumb:EnableMouse(on)
		box:EnableMouse(on)
		if not on then box:ClearFocus() end
		local barC = on and C.gold500 or P.textDisabled
		UI.SetColor(fillbar, barC)
		UI.SetColor(tt, barC)
		local capC = on and (compact and C.textStrong or C.gold300) or C.textFaint
		cap:SetTextColor(capC.r, capC.g, capC.b)
		local valC = on and (compact and C.gold500 or C.textStrong) or C.textFaint
		box:SetTextColor(valC.r, valC.g, valC.b)
		if minL then
			local endC = on and C.textMuted or P.textDisabled
			minL:SetTextColor(endC.r, endC.g, endC.b)
			maxL:SetTextColor(endC.r, endC.g, endC.b)
		end
	end
	return f
end

-- ---------------------------------------------------------------------------
--  Select (dropdown) — gold inset header + popover menu. o = {label?,options,
--  get,set,value,width,tile?}. options: strings OR {value,label}. Height:
--  without label = 40, with label = 62.
-- ---------------------------------------------------------------------------
local function normOptions(options)
	local out = {}
	for i, op in ipairs(options) do
		if type(op) == "table" then out[i] = { value = op.value, label = op.label }
		else out[i] = { value = op, label = op } end
	end
	return out
end

function W.Select(parent, o)
	local opts = normOptions(o.options or {})
	local f = CreateFrame("Frame", nil, parent)
	if o.width then f:SetWidth(o.width) end

	local topY = 0
	if o.label then
		local _, yo = fieldLabel(f, o.label)
		topY = yo
		f:SetHeight(CONTROL_H - topY)
	else
		f:SetHeight(CONTROL_H)
	end

	-- Header-Button
	local btn = CreateFrame("Button", nil, f)
	btn:SetHeight(CONTROL_H)
	btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, topY)
	btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, topY)
	UI.RoundFill(btn, C.ink700, nil, nil, R_CTRL)
	local edges = UI.RoundBorder(btn, L.soft, "OVERLAY", nil, R_CTRL)
	f._control = btn -- anchor for "checkbox right next to the control" (vertically aligned)

	-- Dropdown chevron: Lucide chevron-down glyph (stage-3 glyph swap), tinted
	-- muted; SetSnapToPixelGrid off so the small TGA stays crisp at panel scale.
	local chev = btn:CreateTexture(nil, "OVERLAY")
	chev:SetSize(M.selectChevSize, M.selectChevSize)
	chev:SetPoint("RIGHT", btn, "RIGHT", -12, 0)
	chev:SetTexture(TEX .. "icon-chevron-down")
	chev:SetSnapToPixelGrid(false); chev:SetTexelSnappingBias(0)
	chev:SetVertexColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)

	local lbl = UI.FS(btn, "selectText", C.textStrong)
	lbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
	lbl:SetPoint("RIGHT", chev, "LEFT", -8, 0)
	lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)

	local cur = (o.get and o.get()) or o.value
	local function labelFor(v)
		for _, op in ipairs(opts) do if op.value == v then return op.label end end
		return nil
	end
	local function refreshLabel()
		local t = labelFor(cur)
		if t then lbl:SetText(t); lbl:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
		else lbl:SetText(o.placeholder or T("Select")); lbl:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b) end
	end
	refreshLabel()

	-- Popover menu (floats above everything) + full-screen closer for click-outside.
	-- Host = the non-clipped menu host set by the Shell (the panel); needed because
	-- selects live in the ScrollFrame and its clipping would otherwise cut off the
	-- popover. Fallback without Shell: on f (for non-scroll contexts).
	-- The host inherits the panel scale (0.74); anchoring on btn works across frames.
	-- The Shell collects the popovers per screen (W.CapturePopovers) and cleans them
	-- up on rebuild -> no leak despite host parenting.
	local host = W._menuHost or f
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:Hide()

	local menu = CreateFrame("Frame", nil, host)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(closer:GetFrameLevel() + 10)
	menu:Hide()
	UI.RoundFill(menu, C.ink550) -- floating surface: card radius (8)
	UI.RoundBorder(menu, L.mid, "OVERLAY")

	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = menu end

	-- Forward declaration: the optional search field (o.search) is built further below,
	-- but closeMenu must already be able to clear its focus.
	local search, searchPH

	local function closeMenu()
		menu:Hide(); closer:Hide()
		if search then search:ClearFocus() end
		for _, e in ipairs(edges) do UI.SetColor(e, L.soft) end
	end
	closer:SetScript("OnClick", closeMenu)

	-- Build the menu rows once. Clear separation selected vs. hovered:
	--  • active (selected) row -> gold bar on the LEFT + interactive-gold text (C2,
	--    two-gold rule: a selectable row is clickable, so no brand gold here)
	--  • hovered row           -> element-hover wash + lighter text
	-- The gold bar marks the selection permanently, the wash only the hover
	-- — so selected and hover no longer look almost the same (Florian feedback).
	-- Rows unified with the SpellPicker list (Florian 2026-07-05, one dropdown
	-- language): uniform element cells + faint separators, hover = elementHover
	-- step; the gold left bar stays the SELECTION marker.
	local pad, rowH, gap = 6, M.selectRowH, 0
	local function paintItem(item, hovered)
		local active = (item._val == cur)
		item._bar:SetShown(active)
		if hovered then
			item._wash:SetColorTexture(P.elementHover.r, P.elementHover.g, P.elementHover.b, 1)
			item._txt:SetTextColor(C.gold100.r, C.gold100.g, C.gold100.b)
		else
			item._wash:SetColorTexture(P.element.r, P.element.g, P.element.b, 1)
			local tc = active and UI.P.goldInt or C.textStrong
			item._txt:SetTextColor(tc.r, tc.g, tc.b)
		end
	end
	-- Options into a SCROLL list: with many entries (e.g. bar/shield textures from
	-- other addons/LSM) only N rows visible + mouse wheel/scrollbar, instead of dragging
	-- the menu across the whole screen. Short lists (<= maxRows) show everything, no scrollbar.
	-- With o.search the header gets a real-time search field (typeahead, pattern from W.SpellPicker):
	-- the list filters live, the height stays fixed at maxRows. Only texture dropdowns set this;
	-- shield/heal-absorb dropdowns inherit it via the same component (feature 3 → 4).
	local maxRows = M.selectMaxRows
	local stride  = rowH + gap
	local needScr = (#opts > maxRows) or (o.search and true) or false
	local visN    = needScr and maxRows or math.max(1, #opts)
	local listH   = math.max(rowH, visN * stride - gap)
	local headerH = o.search and (M.spSearchH + 8) or 0

	-- Search field (typeahead) — only with o.search. Filters the once-built options live.
	if o.search then
		search = CreateFrame("EditBox", nil, menu)
		search:SetHeight(M.spSearchH)
		search:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -pad)
		search:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -pad, -pad)
		UI.RoundFill(search, C.ink700, nil, nil, R_CTRL)
		UI.RoundBorder(search, L.soft, "OVERLAY", nil, R_CTRL)
		UI:SetFont(search, "value", C.textStrong) -- role, not an ad-hoc size
		search:SetTextInsets(10, 10, 0, 0)
		search:SetAutoFocus(false)
		searchPH = UI.FS(search, "label", C.textMuted)
		searchPH:SetText(T("Search texture …"))
		searchPH:SetPoint("LEFT", search, "LEFT", 10, 0)
	end

	local sf = CreateFrame("ScrollFrame", nil, menu)
	if search then sf:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	else sf:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -pad) end
	sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -(pad + (needScr and (M.spScrollW + M.spScrollGap) or 0)), pad)
	sf:EnableMouseWheel(needScr)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf:SetScript("OnSizeChanged", function(self2, w) child:SetWidth(w or self2:GetWidth() or 1) end)

	local items = {}
	for _, op in ipairs(opts) do
		local item = CreateFrame("Button", nil, child)
		item:SetHeight(rowH)
		item:SetPoint("LEFT", child, "LEFT", 0, 0)
		item:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		local wash = item:CreateTexture(nil, "BACKGROUND")
		wash:SetAllPoints(item)
		wash:SetColorTexture(0, 0, 0, 0)
		-- Faint separator between rows (SpellPicker pattern).
		local isep = item:CreateTexture(nil, "ARTWORK")
		isep:SetHeight(1)
		isep:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 8, 0)
		isep:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -8, 0)
		UI.SetColor(isep, L.faint)
		-- Gold bar on the left (selection marker), full row height.
		local bar = item:CreateTexture(nil, "ARTWORK")
		bar:SetWidth(3)
		bar:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
		bar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
		UI.SetColor(bar, C.gold500)
		bar:Hide()
		local itxt = UI.FS(item, "selectText", C.textStrong)
		itxt:SetPoint("LEFT", item, "LEFT", 12, 0)
		itxt:SetText(op.label)
		item._wash, item._txt, item._val, item._bar = wash, itxt, op.value, bar
		item._search = (op.label or ""):lower() -- filter basis (lowercased)
		item:SetScript("OnEnter", function(self) paintItem(self, true) end)
		item:SetScript("OnLeave", function(self) paintItem(self, false) end)
		item:SetScript("OnClick", function(self)
			cur = self._val
			refreshLabel()
			closeMenu()
			if o.set then o.set(cur) end
		end)
		items[#items + 1] = item
	end
	menu:SetHeight(listH + headerH + pad * 2)
	menu._paintItem, menu._items = paintItem, items

	-- "no matches" hint (only relevant with an active search).
	local emptyFS = UI.FS(menu, "label", C.textMuted)
	emptyFS:SetText(T("(no matches)"))
	if search then emptyFS:SetPoint("TOP", search, "BOTTOM", 0, -16)
	else emptyFS:SetPoint("TOP", menu, "TOP", 0, -(pad + 16)) end
	emptyFS:Hide()

	-- Re-anchor visible (filtered) rows top→bottom. Without a search this simply shows
	-- all options (q == "") — behaviorally identical to the previous static anchor chain.
	local function relayout()
		local q = (search and (search:GetText() or ""):lower()) or ""
		local shown, prevItem = 0, nil
		for _, item in ipairs(items) do
			if q == "" or item._search:find(q, 1, true) then
				shown = shown + 1
				item:ClearAllPoints()
				item:SetPoint("LEFT", child, "LEFT", 0, 0)
				item:SetPoint("RIGHT", child, "RIGHT", 0, 0)
				if prevItem then item:SetPoint("TOP", prevItem, "BOTTOM", 0, -gap)
				else item:SetPoint("TOP", child, "TOP", 0, 0) end
				item:Show(); prevItem = item
			else
				item:Hide()
			end
		end
		child:SetHeight(math.max(1, shown * stride - gap))
		sf:SetVerticalScroll(0)
		emptyFS:SetShown(shown == 0)
		if menu._updateBar then menu._updateBar() end
	end
	menu._relayout = relayout

	if search then
		search:SetScript("OnTextChanged", function() searchPH:SetShown((search:GetText() or "") == ""); relayout() end)
		search:SetScript("OnEscapePressed", function(self2) self2:ClearFocus(); closeMenu() end)
		search:SetScript("OnEnterPressed", function(self2) self2:ClearFocus() end)
	end

	-- Scrollbar (only when needed) — pattern from W.SpellPicker: mouse wheel + draggable thumb.
	if needScr then
		local sbTrack = CreateFrame("Frame", nil, menu)
		sbTrack:SetWidth(M.spScrollW)
		sbTrack:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -pad, -(pad + headerH))
		sbTrack:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -pad, pad)
		local trackTex = sbTrack:CreateTexture(nil, "ARTWORK")
		trackTex:SetAllPoints(sbTrack); UI.SetColor(trackTex, C.ink700)
		local sth = CreateFrame("Frame", nil, sbTrack)
		sth:SetWidth(M.spScrollW); sth:EnableMouse(true)
		local sthTex = sth:CreateTexture(nil, "OVERLAY"); sthTex:SetAllPoints(sth)
		local function paintThumb(a) sthTex:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, a) end
		paintThumb(0.55)
		local function updateBar()
			local range = sf:GetVerticalScrollRange() or 0
			local h = sf:GetHeight() or 1
			if range <= 0.5 or h <= 1 then sth:Hide(); return end
			sth:Show()
			local total = h + range
			local th = math.max(20, (h / total) * h)
			sth:SetHeight(th)
			local p = (sf:GetVerticalScroll() or 0) / range
			sth:ClearAllPoints(); sth:SetPoint("TOP", sbTrack, "TOP", 0, -p * (h - th))
		end
		local function scrollBy(dd)
			local range = sf:GetVerticalScrollRange() or 0
			sf:SetVerticalScroll(math.max(0, math.min(range, (sf:GetVerticalScroll() or 0) - dd))); updateBar()
		end
		sf:SetScript("OnMouseWheel", function(_, dd) scrollBy(dd * stride * 2) end)
		sf:SetScript("OnScrollRangeChanged", updateBar)
		sth:SetScript("OnMouseDown", function(self2)
			local _, cy = GetCursorPosition()
			local sc = sbTrack:GetEffectiveScale() or 1
			self2._grabOff = (sth:GetTop() or 0) - (cy / (sc ~= 0 and sc or 1))
			self2:SetScript("OnUpdate", function()
				local _, cy2 = GetCursorPosition()
				local s2 = sbTrack:GetEffectiveScale(); if not s2 or s2 == 0 then return end
				cy2 = cy2 / s2
				local top, h = sbTrack:GetTop(), sf:GetHeight() or 1
				local denom = h - (sth:GetHeight() or 0)
				if not top or denom <= 0 then return end
				local rel = math.max(0, math.min(1, (top - (cy2 + (self2._grabOff or 0))) / denom))
				sf:SetVerticalScroll(rel * (sf:GetVerticalScrollRange() or 0)); updateBar()
			end)
		end)
		sth:SetScript("OnMouseUp", function(self2) self2:SetScript("OnUpdate", nil) end)
		sth:SetScript("OnHide", function(self2) self2:SetScript("OnUpdate", nil) end)
		sth:SetScript("OnEnter", function() paintThumb(0.85) end)
		sth:SetScript("OnLeave", function() paintThumb(0.55) end)
		menu._updateBar = updateBar
	end

	relayout() -- initial layout (shows all options; menu._updateBar is now set).

	local function openMenu()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -6)
		menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -6)
		-- Bring the row look up to date (gold bar on the selected row)
		for _, item in ipairs(menu._items) do menu._paintItem(item, false) end
		if search then search:SetText(""); searchPH:Show(); relayout() end
		closer:Show(); menu:Show()
		if menu._updateBar then menu._updateBar() end
		for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end
		if search then search:SetFocus() end
	end

	btn:SetScript("OnClick", function()
		if menu:IsShown() then closeMenu() else openMenu() end
	end)
	btn:SetScript("OnEnter", function()
		if not menu:IsShown() then for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end end
		if o.tooltip then W.ShowTextTip(btn, o.label or o.tooltipTitle, o.tooltip) end
	end)
	btn:SetScript("OnLeave", function()
		if not menu:IsShown() then for _, e in ipairs(edges) do UI.SetColor(e, L.soft) end end
		if o.tooltip then W.HideTip() end
	end)
	btn:HookScript("OnHide", closeMenu)

	-- Fast preview (OPT-IN via o.wheelPreview — only texture dropdowns): mouse wheel over the
	-- CLOSED dropdown cycles live through the options (instead of scrolling the Shell).
	-- Without wheelPreview the button does NOT consume the wheel -> the Shell scrolls normally.
	-- Throttle: label immediately, but the profile write (o.set -> relayout) leading-edge +
	-- throttled -> max ~every 50 ms a re-render; the last chosen value always lands in the profile.
	if o.wheelPreview then
		local PREVIEW_THROTTLE = 0.05
		local lastApply, pendingVal, scheduled = 0, nil, false
		local function cycle(delta)
			if #opts == 0 then return end
			local idx = 1
			for i, op in ipairs(opts) do if op.value == cur then idx = i; break end end
			idx = math.max(1, math.min(#opts, idx - delta)) -- wheel up = previous, down = next option
			local v = opts[idx].value
			if v == cur then return end
			cur = v; refreshLabel()
			local now = GetTime()
			if now - lastApply >= PREVIEW_THROTTLE then
				lastApply = now; pendingVal = nil
				if o.set then o.set(v) end
			else
				pendingVal = v
				if not scheduled then
					scheduled = true
					C_Timer.After(PREVIEW_THROTTLE - (now - lastApply), function()
						scheduled = false; lastApply = GetTime()
						local p = pendingVal; pendingVal = nil
						if p ~= nil and o.set then o.set(p) end
					end)
				end
			end
		end
		btn:EnableMouseWheel(true)
		btn:SetScript("OnMouseWheel", function(_, delta) if not menu:IsShown() then cycle(delta) end end)
	end

	f.SetValueExternal = function(_, v) cur = v; refreshLabel() end
	f.SetWidgetEnabled = function(_, on)
		f:SetAlpha(on and 1 or 0.35)
		btn:EnableMouse(on)
		if o.wheelPreview then btn:EnableMouseWheel(on) end
		if not on and menu:IsShown() then closeMenu() end
	end
	return f
end

-- ---------------------------------------------------------------------------
--  SpellPicker — button opens a searchable, SCROLLABLE selection popover.
--  This is the "real typeahead search": W.Select cannot scroll, here
--  30–60 spells run live-filtered in a scroll list (search field on top +
--  mouse wheel/scrollbar). o = {
--    text,                 -- button label ("+ Add spell")
--    width,                -- button width (optional, default M.spBtnW)
--    fetch  = function() return { {id,name,icon}, ... } end,  -- candidates,
--             -- already deduplicated/whitelist-filtered by the caller, alphabetical.
--    onPick = function(id),  -- chosen spell.
--  }
--  Popover floats on _menuHost (non-clipped, like W.Select) + is collected via
--  W._popovers and cleaned up on tab switch (no leak).
-- ---------------------------------------------------------------------------
function W.SpellPicker(parent, o)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.buttonH)
	f:SetWidth(o.width or M.spBtnW)

	local closeMenu -- forward declaration (row click calls it)

	-- Trigger button. bare = catalog-row style (square gold icon tile + plain name,
	-- no field chrome) so a custom-spell row matches the standard rows + the spell
	-- icon sits in FRONT. Otherwise = inset field with gold border (the "+ Add" look).
	local btn = CreateFrame("Button", nil, f)
	btn:SetAllPoints(f)
	local bEdges = {}
	local bTxt
	if o.bare then
		local tile = W.SquareIcon(btn, LO.clickcast.icon)
		tile:SetPoint("LEFT", btn, "LEFT", 0, 0)
		tile:SetIcon(o.icon)
		bTxt = UI.FS(btn, "selectText", o.icon and C.gold300 or C.textMuted)
		bTxt:SetPoint("LEFT", tile, "RIGHT", 10, 0)
		bTxt:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
		bTxt:SetJustifyH("LEFT"); bTxt:SetWordWrap(false)
		bTxt:SetText(o.text or T("+ Add"))
	else
		-- v2: trigger styled like a SECONDARY button (transparent, gold outline).
		bEdges = UI.RoundBorder(btn, UI.goldA(0.55), "OVERLAY", nil, R_CTRL)
		bTxt = UI.FS(btn, "btn", C.gold500)
		bTxt:SetText(o.text or T("+ Add"))
		if o.icon then
			local bIcon = btn:CreateTexture(nil, "ARTWORK")
			bIcon:SetSize(M.spellIcon, M.spellIcon)
			bIcon:SetPoint("LEFT", btn, "LEFT", 10, 0)
			bIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			bIcon:SetTexture(o.icon)
			bTxt:SetPoint("LEFT", bIcon, "RIGHT", 8, 0)
			bTxt:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
			bTxt:SetJustifyH("LEFT"); bTxt:SetWordWrap(false)
		else
			bTxt:SetPoint("CENTER", btn, "CENTER", 0, 0)
		end
	end
	f._control = btn

	-- Popover (menu + full-screen closer) on the non-clipped host, like W.Select.
	local host = W._menuHost or f
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:Hide()

	local menu = CreateFrame("Frame", nil, host)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(closer:GetFrameLevel() + 10)
	menu:SetWidth(M.spW)
	-- (v2: popover surfaces get a NEUTRAL subtle border, not gold — Florian feedback)
	menu:Hide()
	UI.RoundFill(menu, C.ink550)
	UI.RoundBorder(menu, L.mid, "OVERLAY")
	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = menu end

	local listH = M.spVisibleRows * M.spRowH
	menu:SetHeight(M.spPad * 2 + M.spSearchH + 8 + listH)

	-- Search field (typeahead) -------------------------------------------
	local search = CreateFrame("EditBox", nil, menu)
	search:SetHeight(M.spSearchH)
	search:SetPoint("TOPLEFT", menu, "TOPLEFT", M.spPad, -M.spPad)
	search:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -M.spPad, -M.spPad)
	UI.RoundFill(search, C.ink700, nil, nil, R_CTRL)
	UI.RoundBorder(search, L.soft, "OVERLAY", nil, R_CTRL)
	UI:SetFont(search, "value", C.textStrong) -- role, not an ad-hoc size
	search:SetTextInsets(10, 10, 0, 0)
	search:SetAutoFocus(false)
	local ph = UI.FS(search, "label", C.textMuted)
	ph:SetText(o.searchPlaceholder or T("Search spell …"))
	ph:SetPoint("LEFT", search, "LEFT", 10, 0)

	-- Scroll list ---------------------------------------------------------
	local sf = CreateFrame("ScrollFrame", nil, menu)
	sf:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -(M.spPad + M.spScrollW + M.spScrollGap), M.spPad)
	sf:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf:SetScript("OnSizeChanged", function(self2, w) child:SetWidth(w or self2:GetWidth() or 1) end)

	local emptyFS = UI.FS(menu, "label", C.textMuted)
	emptyFS:SetText(T("(no matches)"))
	emptyFS:SetPoint("TOP", search, "BOTTOM", 0, -16)
	emptyFS:Hide()

	-- Scrollbar (pattern from the Shell ScrollFrame: mouse wheel + draggable thumb).
	local sbTrack = CreateFrame("Frame", nil, menu)
	sbTrack:SetWidth(M.spScrollW)
	sbTrack:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -M.spPad, -(M.spPad + M.spSearchH + 8))
	sbTrack:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -M.spPad, M.spPad)
	local trackTex = sbTrack:CreateTexture(nil, "ARTWORK")
	trackTex:SetAllPoints(sbTrack); UI.SetColor(trackTex, C.ink700)
	local thumb = CreateFrame("Frame", nil, sbTrack)
	thumb:SetWidth(M.spScrollW); thumb:EnableMouse(true)
	local thumbTex = thumb:CreateTexture(nil, "OVERLAY"); thumbTex:SetAllPoints(thumb)
	local function paintThumb(a) thumbTex:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, a) end
	paintThumb(0.55)
	local function updateBar()
		local range = sf:GetVerticalScrollRange() or 0
		local h = sf:GetHeight() or 1
		if range <= 0.5 or h <= 1 then sbTrack:Hide(); return end
		sbTrack:Show()
		local total = h + range
		local th = math.max(20, (h / total) * h)
		thumb:SetHeight(th)
		local pos = (sf:GetVerticalScroll() or 0) / range
		thumb:ClearAllPoints(); thumb:SetPoint("TOP", sbTrack, "TOP", 0, -pos * (h - th))
	end
	local function scrollBy(d)
		local range = sf:GetVerticalScrollRange() or 0
		sf:SetVerticalScroll(math.max(0, math.min(range, (sf:GetVerticalScroll() or 0) - d))); updateBar()
	end
	sf:SetScript("OnMouseWheel", function(_, d) scrollBy(d * M.spRowH * 2) end)
	sf:SetScript("OnScrollRangeChanged", updateBar)
	thumb:SetScript("OnMouseDown", function(self2)
		local _, cy = GetCursorPosition()
		local sc = sbTrack:GetEffectiveScale() or 1
		self2._grabOff = (thumb:GetTop() or 0) - (cy / (sc ~= 0 and sc or 1))
		self2:SetScript("OnUpdate", function()
			local _, cy2 = GetCursorPosition()
			local s2 = sbTrack:GetEffectiveScale(); if not s2 or s2 == 0 then return end
			cy2 = cy2 / s2
			local top, h = sbTrack:GetTop(), sf:GetHeight() or 1
			local denom = h - (thumb:GetHeight() or 0)
			if not top or denom <= 0 then return end
			local rel = math.max(0, math.min(1, (top - (cy2 + (self2._grabOff or 0))) / denom))
			sf:SetVerticalScroll(rel * (sf:GetVerticalScrollRange() or 0)); updateBar()
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self2) self2:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnHide", function(self2) self2:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnEnter", function() paintThumb(0.85) end)
	thumb:SetScript("OnLeave", function() paintThumb(0.55) end)

	-- Row pool (no frame churn while typing): reused, only text/icon refreshed.
	local rows = {}
	local function getRow(i)
		local r = rows[i]
		if r then return r end
		r = CreateFrame("Button", nil, child)
		r:SetHeight(M.spRowH)
		r:SetPoint("LEFT", child, "LEFT", 0, 0)
		r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		if i == 1 then r:SetPoint("TOP", child, "TOP", 0, 0)
		else r:SetPoint("TOP", rows[i - 1], "BOTTOM", 0, 0) end
		local wash = r:CreateTexture(nil, "BACKGROUND"); wash:SetAllPoints(r); wash:SetColorTexture(0, 0, 0, 0)
		r._base = { 0, 0, 0, 0 } -- zebra base colour (set per VISIBLE row in populate)
		local sep = r:CreateTexture(nil, "ARTWORK"); sep:SetHeight(1)
		sep:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 8, 0); sep:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -8, 0)
		UI.SetColor(sep, L.faint)
		-- (No gold left bar here: in the unified dropdown language the bar is
		-- the SELECTION marker — a picker list has none. Florian 2026-07-05.)
		local icon = r:CreateTexture(nil, "ARTWORK")
		icon:SetSize(M.spellIcon, M.spellIcon)
		icon:SetPoint("LEFT", r, "LEFT", 8, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local name = UI.FS(r, "selectText", C.textStrong)
		name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
		name:SetPoint("RIGHT", r, "RIGHT", -8, 0)
		name:SetJustifyH("LEFT"); name:SetWordWrap(false)
		r._wash, r._icon, r._name = wash, icon, name
		r:SetScript("OnEnter", function(self2)
			-- v2: hover = elementHover (rows now sit on P.element, so inkTint would be invisible)
			self2._wash:SetColorTexture(P.elementHover.r, P.elementHover.g, P.elementHover.b, 1)
			self2._name:SetTextColor(C.gold100.r, C.gold100.g, C.gold100.b)
			W.ShowSpellTip(self2, self2._id) -- own Lumen tooltip
		end)
		r:SetScript("OnLeave", function(self2)
			local b = self2._base
			self2._wash:SetColorTexture(b[1], b[2], b[3], b[4])
			self2._name:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
			W.HideTip()
		end)
		r:SetScript("OnClick", function(self2)
			if self2._id then closeMenu(); if o.onPick then o.onPick(self2._id) end end
		end)
		rows[i] = r
		return r
	end

	-- Fetch the candidate list ONCE on open (fetch scans spellbook + talents —
	-- don't repeat per keystroke); typing only filters this cached list.
	local data = {}
	local function populate()
		local q = (search:GetText() or ""):lower()
		local n = 0
		for _, e in ipairs(data) do
			if q == "" or (e.name and e.name:lower():find(q, 1, true)) then
				n = n + 1
				local r = getRow(n)
				r._id = e.id
				r._icon:SetTexture(e.icon or 136243)
				r._name:SetText(e.name or ("Spell " .. tostring(e.id)))
				-- v2: UNIFORM row cells (element on the dark inset menu) — the old zebra
				-- alternation was far too strong on the new palette (Florian feedback);
				-- the faint separators carry the structure instead.
				r._base = { P.element.r, P.element.g, P.element.b, 1 }
				r._wash:SetColorTexture(r._base[1], r._base[2], r._base[3], r._base[4])
				r._name:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
				r:Show()
			end
		end
		for i = n + 1, #rows do rows[i]:Hide() end
		child:SetHeight(math.max(1, n * M.spRowH))
		sf:SetVerticalScroll(0)
		emptyFS:SetShown(n == 0)
		updateBar()
	end

	search:SetScript("OnTextChanged", function() ph:SetShown((search:GetText() or "") == ""); populate() end)
	search:SetScript("OnEscapePressed", function(self2) self2:ClearFocus(); closeMenu() end)
	search:SetScript("OnEnterPressed", function(self2) self2:ClearFocus() end)

	local function openMenu()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -6)
		data = (o.fetch and o.fetch()) or {} -- scan once, then only filter
		search:SetText("") -- OnTextChanged only fires on a real change -> explicit:
		ph:Show()
		populate()
		closer:Show(); menu:Show()
		for _, e in ipairs(bEdges) do UI.SetColor(e, L.strong) end
		search:SetFocus()
	end
	closeMenu = function()
		menu:Hide(); closer:Hide()
		search:ClearFocus()
		for _, e in ipairs(bEdges) do UI.SetColor(e, UI.goldA(0.55)) end
	end
	closer:SetScript("OnClick", closeMenu)

	btn:SetScript("OnClick", function() if menu:IsShown() then closeMenu() else openMenu() end end)
	btn:SetScript("OnEnter", function()
		if not menu:IsShown() then for _, e in ipairs(bEdges) do UI.SetColor(e, L.strong) end end
		bTxt:SetTextColor(C.gold200.r, C.gold200.g, C.gold200.b)
	end)
	btn:SetScript("OnLeave", function()
		if not menu:IsShown() then for _, e in ipairs(bEdges) do UI.SetColor(e, UI.goldA(0.55)) end end
		bTxt:SetTextColor(C.gold500.r, C.gold500.g, C.gold500.b)
	end)
	btn:HookScript("OnHide", closeMenu)

	return f
end

-- ---------------------------------------------------------------------------
--  Confirm — modal confirmation dialog. Dims the Shell (overlay over the menu
--  host = panel) and shows a centered card with title, text and two buttons
--  (confirm = danger / cancel = ghost). Click on the dimmed area = cancel.
--  Singleton (built once, reconfigured per call, like the color picker). Call:
--    W.Confirm{ title, body, confirmText, cancelText, onConfirm, onCancel }
-- ---------------------------------------------------------------------------
local confirmDlg
local function buildConfirm()
	local host = W._menuHost or UIParent
	local overlay = CreateFrame("Button", nil, host)
	overlay:SetAllPoints(host)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:EnableMouse(true) -- swallows clicks on the dimmed Shell (modal)
	local dim = overlay:CreateTexture(nil, "BACKGROUND")
	dim:SetAllPoints(overlay)
	dim:SetColorTexture(0, 0, 0, M.confirmDim)
	overlay:Hide()

	local card = CreateFrame("Frame", nil, overlay)
	card:SetFrameStrata("FULLSCREEN_DIALOG")
	card:SetFrameLevel(overlay:GetFrameLevel() + 10)
	card:SetSize(M.confirmW, M.confirmH)
	card:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	card:EnableMouse(true) -- don't treat clicks on the card as "outside"
	UI.RoundFill(card, C.ink550, nil, nil, RAD.xl) -- modal dialog = XL
	UI.RoundBorder(card, L.mid, "OVERLAY", nil, RAD.xl) -- v2: neutral popover border
	local accent = card:CreateTexture(nil, "OVERLAY") -- gold accent on top (signature)
	accent:SetHeight(3)
	-- Inset by the corner radius: the straight bar stops where the curve starts.
	accent:SetPoint("TOPLEFT", card, "TOPLEFT", RAD.xl, 0)
	accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RAD.xl, 0)
	UI.SetColor(accent, P.goldBrand) -- v2: signature accent = brand gold (C1)

	local title = UI.FS(card, "sectionHead", C.gold300)
	title:SetPoint("TOPLEFT", card, "TOPLEFT", M.confirmPad, -M.confirmPad)
	title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.confirmPad, -M.confirmPad)
	title:SetJustifyH("LEFT")

	local body = UI.FS(card, "hint", C.textBody)
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
	body:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -14)
	body:SetJustifyH("LEFT"); body:SetWordWrap(true)

	-- Confirm action in TWO variants: danger (destructive, default) and primary
	-- (neutral confirms like a UI reload — red is STRICTLY destructive, palette
	-- rule E). W.Button bakes the variant at creation, so both exist side by
	-- side (same spot, same fixed width) and W.Confirm shows the matching one.
	local okBtn = W.Button(card, { text = T("Confirm"), variant = "danger", width = M.confirmBtnW })
	okBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -M.confirmPad, M.confirmPad)
	local okPrim = W.Button(card, { text = T("Confirm"), variant = "primary", width = M.confirmBtnW })
	okPrim:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -M.confirmPad, M.confirmPad)
	local cancelBtn = W.Button(card, { text = T("Cancel"), variant = "ghost", width = M.confirmBtnW })
	cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -M.confirmBtnGap, 0)

	confirmDlg = { overlay = overlay, card = card, title = title, body = body,
		ok = okBtn, okPrim = okPrim, cancel = cancelBtn }
	return confirmDlg
end

-- o = { title, body, confirmText, cancelText, onConfirm, onCancel,
--       variant? } — variant "primary" for neutral confirmations (e.g. reload);
-- default is the red danger button (destructive actions).
function W.Confirm(o)
	local dlg = confirmDlg or buildConfirm()
	local ok = (o.variant == "primary") and dlg.okPrim or dlg.ok
	dlg.ok:SetShown(ok == dlg.ok)
	dlg.okPrim:SetShown(ok == dlg.okPrim)
	dlg.title:SetText(o.title or T("Are you sure?"))
	dlg.body:SetText(o.body or "")
	ok._txt:SetText(o.confirmText or T("Confirm"))
	dlg.cancel._txt:SetText(o.cancelText or T("Cancel"))
	-- Card height follows the text: a long localized body must never collide
	-- with the button row; confirmH stays the minimum for short texts.
	-- (14 = the title->body anchor gap above; 20 = air body -> button row.)
	local textH = (dlg.title:GetStringHeight() or 0) + 14 + (dlg.body:GetStringHeight() or 0)
	dlg.card:SetHeight(math.max(M.confirmH, M.confirmPad * 2 + textH + 20 + M.buttonH))
	local function doCancel()
		dlg.overlay:Hide()
		if o.onCancel then o.onCancel() end
	end
	ok:SetScript("OnClick", function()
		dlg.overlay:Hide()
		if o.onConfirm then o.onConfirm() end
	end)
	dlg.cancel:SetScript("OnClick", doCancel)
	dlg.overlay:SetScript("OnClick", doCancel) -- click on the dimmed area = cancel
	dlg.overlay:Show()
	dlg.overlay:Raise()
end

-- ---------------------------------------------------------------------------
--  ImportDialog — modal profile-import popup. Richer than W.Confirm:
--  profile-name input + module checkboxes (dynamic, only those present in the code)
--  + "Also import layout" + two actions ("Create profile" uses the name,
--  "Overwrite current" ignores it). Built fresh per call + released on close
--  (rarely opened -> no singleton needed). Call:
--    W.ImportDialog{ modules = {{key,label}}, hasLayout, onCreate(name,sel,layout),
--                    onOverwrite(sel,layout), onCancel }
--  sel = { [modKey] = bool } (all default on), layout = bool (default off).
-- ---------------------------------------------------------------------------
function W.ImportDialog(o)
	o = o or {}
	local pad = M.confirmPad
	local host = W._menuHost or UIParent

	local overlay = CreateFrame("Button", nil, host)
	overlay:SetAllPoints(host)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:EnableMouse(true) -- modal: swallows clicks on the dimmed Shell
	local dim = overlay:CreateTexture(nil, "BACKGROUND")
	dim:SetAllPoints(overlay)
	dim:SetColorTexture(0, 0, 0, M.confirmDim)

	local function close() overlay:Hide(); overlay:SetParent(nil) end
	overlay:SetScript("OnClick", function() close(); if o.onCancel then o.onCancel() end end)

	local card = CreateFrame("Frame", nil, overlay)
	card:SetFrameStrata("FULLSCREEN_DIALOG")
	card:SetFrameLevel(overlay:GetFrameLevel() + 10)
	card:SetWidth(M.importDlgW)
	card:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	card:EnableMouse(true) -- don't treat clicks on the card as "outside"
	UI.RoundFill(card, C.ink550, nil, nil, RAD.xl) -- modal dialog = XL
	UI.RoundBorder(card, L.mid, "OVERLAY", nil, RAD.xl) -- v2: neutral popover border
	local accent = card:CreateTexture(nil, "OVERLAY")
	accent:SetHeight(3)
	accent:SetPoint("TOPLEFT", card, "TOPLEFT", RAD.xl, 0)
	accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RAD.xl, 0)
	UI.SetColor(accent, P.goldBrand) -- v2: signature accent = brand gold (C1)

	local y = -pad - 6

	local title = UI.FS(card, "sectionHead", C.gold300)
	title:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
	title:SetText(T("Import profile"))
	y = y - 36

	-- Profile name (for "Create profile"; "Overwrite current" ignores it).
	local nameIn = W.TextInput(card, { label = T("Profile name"), placeholder = T("Name for new profile …") })
	nameIn:ClearAllPoints()
	nameIn:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
	nameIn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, y)
	y = y - (M.controlH + M.fieldGap) - 18

	local lbl = UI.FS(card, "fieldLabel", C.textStrong)
	lbl:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
	lbl:SetText(T("What to import:"))
	y = y - 28

	-- Module checkboxes (all default on).
	local selected = {}
	for _, mod in ipairs(o.modules or {}) do
		local key = mod.key
		selected[key] = true
		local chk = W.Checkbox(card, { label = mod.label,
			get = function() return selected[key] end, set = function(v) selected[key] = v end })
		chk:ClearAllPoints(); chk:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
		y = y - (M.checkBox + 12)
	end

	-- Layout checkbox (only if the code contains positions; default off).
	local withLayout = false
	if o.hasLayout then
		local chk = W.Checkbox(card, { label = T("Also import layout positions"),
			tooltip = T("On = take the sender's frame positions. Off = your current positions stay."),
			get = function() return withLayout end, set = function(v) withLayout = v end })
		chk:ClearAllPoints(); chk:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
		y = y - (M.checkBox + 12)
	end

	y = y - 10

	-- Actions: "Create profile" (primary, needs a name) | "Overwrite current".
	local createBtn = W.Button(card, { text = T("Create profile"), variant = "primary",
		onClick = function()
			local name = (nameIn:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if name == "" then nameIn._edit:SetFocus(); return end -- name is mandatory
			close()
			if o.onCreate then o.onCreate(name, selected, withLayout) end
		end })
	createBtn:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
	local overBtn = W.Button(card, { text = T("Overwrite current"), variant = "ghost",
		onClick = function() close(); if o.onOverwrite then o.onOverwrite(selected, withLayout) end end })
	overBtn:SetPoint("LEFT", createBtn, "RIGHT", M.confirmBtnGap, 0)
	y = y - M.buttonH

	card:SetHeight(-y + pad)

	overlay:Show(); overlay:Raise()
	return overlay
end

-- ---------------------------------------------------------------------------
--  Tooltip — own tooltip styled in the Lumen design (replaces the Blizzard
--  GameTooltip in the WHOLE Shell). Singleton, strata TOOLTIP (above popovers).
--  Two modes via ONE card: spell (icon + name + C_Spell description) OR
--  text (title + hint text, without icon). Height grows with the text. Font via
--  the roles tipTitle/tipBody (UI.ROLE) -> centrally tunable.
--    W.ShowSpellTip(owner, spellID) · W.ShowTextTip(owner, title, body) · W.HideTip()
-- ---------------------------------------------------------------------------
local tipObj
local function buildTip()
	local host = W._menuHost or UIParent
	local tip = CreateFrame("Frame", nil, host)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetWidth(M.tipW)
	tip:SetClampedToScreen(true) -- stays fully readable near a screen edge (e.g. TOP-anchored)
	tip:Hide()
	UI.RoundFill(tip, C.ink850) -- darker than the popover -> clearer tooltip contrast
	UI.RoundBorder(tip, L.mid, "OVERLAY") -- v2: neutral popover border (no gold top accent — Florian 2026-07-05)

	local icon = tip:CreateTexture(nil, "ARTWORK")
	icon:SetSize(M.tipIcon, M.tipIcon)
	icon:SetPoint("TOPLEFT", tip, "TOPLEFT", M.tipPad, -M.tipPad)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = UI.FS(tip, "tipTitle", C.gold250)
	title:SetJustifyH("LEFT"); title:SetJustifyV("MIDDLE")

	local body = UI.FS(tip, "tipBody", C.textBody)
	body:SetJustifyH("LEFT"); body:SetWordWrap(true)

	tipObj = { tip = tip, icon = icon, title = title, body = body }
	return tipObj
end

-- Shared build for both modes: icon=nil -> pure text tooltip.
local function applyTip(owner, icon, titleText, bodyText, anchor)
	if not owner then return end
	local t = tipObj or buildTip()
	local hasIcon = icon ~= nil
	local hasBody = bodyText ~= nil and bodyText ~= ""

	t.icon:SetShown(hasIcon)
	if hasIcon then t.icon:SetTexture(icon) end

	t.title:ClearAllPoints()
	t.title:SetPoint("RIGHT", t.tip, "RIGHT", -M.tipPad, 0)
	if hasIcon then
		t.title:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", M.tipNameGap, 0)
		t.title:SetHeight(M.tipIcon); t.title:SetWordWrap(false) -- name single-line next to the icon
	else
		t.title:SetPoint("TOPLEFT", t.tip, "TOPLEFT", M.tipPad, -M.tipPad)
		t.title:SetHeight(0); t.title:SetWordWrap(true)
	end
	t.title:SetText(titleText or "")

	-- Header height = icon height (spell) resp. title height (text); then optionally the text.
	local headH = hasIcon and M.tipIcon or (t.title:GetStringHeight() or 0)
	t.body:SetShown(hasBody)
	t.body:ClearAllPoints()
	t.body:SetPoint("TOPLEFT", t.tip, "TOPLEFT", M.tipPad, -(M.tipPad + headH + M.tipGap))
	t.body:SetPoint("RIGHT", t.tip, "RIGHT", -M.tipPad, 0)
	t.body:SetText(hasBody and bodyText or "")
	local bodyH = hasBody and (t.body:GetStringHeight() or 0) or 0

	t.tip:SetHeight(M.tipPad + headH + (hasBody and (M.tipGap + bodyH) or 0) + M.tipPad)
	t.tip:ClearAllPoints()
	if anchor == "TOP" then
		-- Open ABOVE the owner (grows upward), so it never covers the row it
		-- belongs to — used by the card-header eye (Florian 2026-07-16).
		t.tip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, M.tipGap)
	else
		t.tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
	end
	t.tip:Show(); t.tip:Raise()
end

function W.ShowSpellTip(owner, spellID)
	if not spellID then return end
	local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	local tx = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
	local ds = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
	applyTip(owner, tx or 136243, nm or ("Spell " .. tostring(spellID)), ds)
end

function W.ShowTextTip(owner, title, body, anchor)
	applyTip(owner, nil, title, body, anchor)
end

function W.HideTip()
	if tipObj then tipObj.tip:Hide() end
end

-- ---------------------------------------------------------------------------
--  Checkbox — gold-fill toggle + checkmark + label, clickable row.
--  o = {label,get,set,value}. Dimensions from UI.WIDGET.
-- ---------------------------------------------------------------------------
function W.Checkbox(parent, o)
	local BOX = M.checkBox
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(BOX)

	local box = CreateFrame("Frame", nil, b)
	box:SetSize(BOX, BOX)
	box:SetPoint("LEFT", b, "LEFT", 0, 0)
	local boxbg = UI.RoundFill(box, CLEAR, "BACKGROUND", nil, RAD.xs)
	local edges = UI.RoundBorder(box, L.mid, "OVERLAY", nil, RAD.xs)

	-- Checkmark: Blizzard's check texture, desaturated + ink-tinted -> cleaner than
	-- self-drawn lines (Florian feedback). Centered, slightly past the box (transparent
	-- edge of the texture) for good proportion.
	local check = box:CreateTexture(nil, "OVERLAY")
	check:SetTexture([[Interface\Buttons\UI-CheckBox-Check]])
	check:SetDesaturated(true)
	check:SetVertexColor(C.onGold.r, C.onGold.g, C.onGold.b, 1)
	check:SetSize(BOX + 8, BOX + 8)
	check:SetPoint("CENTER", box, "CENTER", 0, 0)

	local lbl = UI.FS(b, "checkLabel", C.textBody)
	lbl:SetText(o.label or "")
	lbl:SetPoint("LEFT", box, "RIGHT", M.checkLabelGap, 0)
	if (o.label or "") == "" then
		b:SetWidth(BOX) -- no label (stacked option row) -> hit area = the box itself
	else
		b:SetWidth(BOX + M.checkLabelGap + math.ceil(lbl:GetStringWidth()) + 2)
	end

	local val = (o.get and o.get()) or o.value or false
	local function apply(on)
		if on then
			UI.SetColor(boxbg, C.gold500)
			for _, e in ipairs(edges) do UI.SetColor(e, C.gold500) end
			check:Show()
		else
			UI.SetColor(boxbg, CLEAR)
			for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end
			check:Hide()
		end
	end
	apply(val)

	b:SetScript("OnEnter", function()
		if not val then for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end end
		lbl:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
		-- Labelless boxes (stacked option rows) pass the row label as tooltipTitle.
		if o.tooltip then W.ShowTextTip(b, o.tooltipTitle or o.label, o.tooltip) end
	end)
	b:SetScript("OnLeave", function()
		if not val then for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end end
		lbl:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b)
		if o.tooltip then W.HideTip() end
	end)
	b:SetScript("OnClick", function()
		val = not val
		apply(val)
		if o.set then o.set(val) end
	end)
	b.SetValueExternal = function(_, v) val = v; apply(v) end
	b.SetWidgetEnabled = function(_, on) b:SetAlpha(on and 1 or 0.35); b:EnableMouse(on) end
	return b
end

-- ---------------------------------------------------------------------------
--  Switch — rounded-RECTANGLE on/off toggle (gold-filled track + rounded-square
--  knob slides right when on). Reusable for any boolean. o = { get, set }.
--  Squared off the old pill/circle (Florian 2026-07-05: cleaner, matches the
--  radius scale + the rounded-square checkboxes) — track = sm6, knob = xs4.
-- ---------------------------------------------------------------------------
function W.Switch(parent, o)
	local b = CreateFrame("Button", nil, parent)
	-- o.small: field/header variant (card grid system — label-on-top cells and
	-- collapsible-header master toggles).
	local swH = o.small and M.switchSmallH or M.switchH
	b:SetSize(o.small and M.switchSmallW or M.switchW, swH)
	local track = UI.RoundFill(b, C.ink700, "BACKGROUND", nil, UI.RADIUS.sm)
	local edges = UI.RoundBorder(b, L.mid, "OVERLAY", nil, UI.RADIUS.sm)
	local pad = M.switchKnobPad
	local kS = swH - pad * 2
	local knob = UI.RoundKnob(b, C.textMuted, "OVERLAY", kS, UI.RADIUS.xs)

	local val = (o.get and o.get()) or false
	local function apply(on)
		knob:ClearAllPoints()
		if on then
			UI.SetColor(track, C.gold500)
			for _, e in ipairs(edges) do UI.SetColor(e, C.gold500) end
			knob:SetPoint("RIGHT", b, "RIGHT", -pad, 0)
			UI.SetColor(knob, C.ink850) -- dark knob on gold
		else
			UI.SetColor(track, C.ink700)
			for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end
			knob:SetPoint("LEFT", b, "LEFT", pad, 0)
			UI.SetColor(knob, C.textMuted)
		end
	end
	apply(val)

	b:SetScript("OnEnter", function() if not val then for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end end
		if o.tooltip then W.ShowTextTip(b, o.tooltip) end end)
	b:SetScript("OnLeave", function() if not val then for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end end
		if o.tooltip then W.HideTip() end end)
	b:SetScript("OnClick", function() val = not val; apply(val); if o.set then o.set(val) end end)
	b.SetValueExternal = function(_, v) val = v; apply(v) end
	b.SetWidgetEnabled = function(_, on) b:SetAlpha(on and 1 or 0.35); b:EnableMouse(on) end
	return b
end

-- (SwitchField retired with the stacked-row standard, design bible §8 —
-- compact toggles live in W.OptionRow rows now, never in label-on-top cells.)

-- ---------------------------------------------------------------------------
--  Segment — compact multi-toggle (gold-filled active cell). ONE component,
--  used multiple times: Raid|Group context switch AND inside|outside.
--  o = { label?, options = {{value,label},…} (or strings), get, set, value,
--        width?, cellH?, tooltip? }. With label -> label on top (like Select/Slider), bar
--  below at controlH. Without label -> only the bar (height cellH, e.g. compact
--  header switch). Equal-width cells via OnSizeChanged (width only after layout).
-- ---------------------------------------------------------------------------
function W.Segment(parent, o)
	local opts = normOptions(o.options or {})
	local n = math.max(1, #opts)
	local f = CreateFrame("Frame", nil, parent)
	if o.width then f:SetWidth(o.width) end

	local cellH = o.cellH or CONTROL_H
	local topY = 0
	if o.label then
		local _, yo = fieldLabel(f, o.label); topY = yo
		f:SetHeight(cellH - topY)
	else
		f:SetHeight(cellH)
	end

	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(cellH)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, topY)
	bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, topY)
	UI.RoundFill(bar, C.ink700, nil, nil, R_CTRL)
	UI.RoundBorder(bar, L.mid, "OVERLAY", nil, R_CTRL)
	f._control = bar

	-- Not `(get() or value)` — get() may legitimately return `false` (e.g. inside/outside with
	-- value=false as default "inside"); the `or` would swallow the false value -> no cell
	-- active. So check for nil explicitly.
	local cur = o.get and o.get()
	if cur == nil then cur = o.value end
	local cells = {}
	local function paint()
		for _, c in ipairs(cells) do
			local active = (c._val == cur)
			if active then
				UI.SetColor(c._fill, C.gold500)
				c._txt:SetTextColor(C.onGold.r, C.onGold.g, C.onGold.b)
			else
				UI.SetColor(c._fill, CLEAR)
				c._txt:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
			end
		end
	end
	for i, op in ipairs(opts) do
		local cell = CreateFrame("Button", nil, bar)
		-- Active-cell fill follows the bar's rounded corners: first cell rounds
		-- left, last cell right, middle cells stay plain squares.
		local fill
		if n == 1 then fill = UI.RoundFill(cell, CLEAR, "BACKGROUND", nil, R_CTRL)
		elseif i == 1 then fill = UI.RoundFill(cell, CLEAR, "BACKGROUND", "left", R_CTRL)
		elseif i == n then fill = UI.RoundFill(cell, CLEAR, "BACKGROUND", "right", R_CTRL)
		else
			fill = cell:CreateTexture(nil, "BACKGROUND")
			fill:SetAllPoints(cell); fill:SetColorTexture(0, 0, 0, 0)
		end
		local txt = UI.FS(cell, "selectText", C.textMuted)
		txt:SetPoint("CENTER", cell, "CENTER", 0, 0)
		txt:SetText(op.label); txt:SetWordWrap(false)
		if i > 1 then -- 1px separator on the left edge (between the cells)
			local div = cell:CreateTexture(nil, "OVERLAY")
			div:SetWidth(1)
			div:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
			div:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 0, 0)
			UI.SetColor(div, L.mid)
		end
		cell._fill, cell._txt, cell._val = fill, txt, op.value
		cell:SetScript("OnEnter", function()
			if cell._val ~= cur then txt:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b) end
			-- Tip anchors to the bar (not the cell) so it stays put across cells.
			if o.tooltip then W.ShowTextTip(bar, o.label, o.tooltip) end
		end)
		cell:SetScript("OnLeave", function()
			if cell._val ~= cur then txt:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b) end
			if o.tooltip then W.HideTip() end
		end)
		cell:SetScript("OnClick", function()
			if cur == cell._val then return end
			cur = cell._val; paint()
			if o.set then o.set(cur) end
		end)
		cells[i] = cell
	end

	-- Equal-width cells only at layout time (width is still 0 at build time).
	bar:SetScript("OnSizeChanged", function(self2, w)
		w = w or self2:GetWidth() or 0
		if w <= 0 then return end
		local cw = w / n
		for i, c in ipairs(cells) do
			c:ClearAllPoints()
			c:SetPoint("TOP", bar, "TOP", 0, 0)
			c:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
			c:SetPoint("LEFT", bar, "LEFT", (i - 1) * cw, 0)
			c:SetWidth(cw)
		end
	end)
	paint()

	f.SetValueExternal = function(_, v) cur = v; paint() end
	f.SetWidgetEnabled = function(_, on)
		f:SetAlpha(on and 1 or 0.35)
		for _, c in ipairs(cells) do c:EnableMouse(on) end
	end
	return f
end

-- ---------------------------------------------------------------------------
--  KeybindButton — key capture (for hovercast). Click -> "Press a key …",
--  the next key (incl. Shift/Ctrl/Alt) is bound; ESC or right click cancels;
--  mouse wheel/buttons are captured too. o = { label?, get,
--  set, width, placeholder?, format? }. get/set work with the WoW key string
--  ("SHIFT-F", "BUTTON4", "MOUSEWHEELUP" …); format(key) returns the display.
--  Built like W.Select (gold inset + label on top) so it sits grid-aligned.
-- ---------------------------------------------------------------------------
local KB_IGNORE = { -- pure modifier/unknown keys: ignore, keep waiting
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
local function kbWithMods(key)
	-- Order such that "ALT-CTRL-SHIFT-KEY" results (WoW standard).
	if IsShiftKeyDown()   then key = "SHIFT-" .. key end
	if IsControlKeyDown() then key = "CTRL-"  .. key end
	if IsAltKeyDown()     then key = "ALT-"   .. key end
	return key
end

-- The button currently capturing keys (its stopListen). While a button listens it
-- grabs ALL keyboard input (EnableKeyboard+propagate=false) so movement/ESC are dead
-- by design. The danger: a re-render orphans a listening button — OnHide does NOT
-- fire on a descendant when only an ancestor (the screen) is hidden, so the grab
-- would stick forever. The Shell calls W.StopActiveKeybind() before every
-- RenderContent / on close to release it. Only ONE button can listen at a time.
local activeCapture
function W.StopActiveKeybind() if activeCapture then activeCapture() end end

-- Dashed rectangle border made of small textures along the 4 edges (WoW has no
-- dashed-line primitive). Rebuilds on size change (anchored frames have 0 size at
-- build time). Returns { Show, Hide, SetColor }. Used for the unbound keybind field.
local function makeDashedEdges(frame, dashLen, gapLen)
	local tex, color, shown = {}, L.mid, false
	local thick = M.kbDashThick
	local function rebuild()
		for _, t in ipairs(tex) do t:Hide(); t:SetParent(nil) end
		wipe(tex)
		local fw, fh = frame:GetWidth(), frame:GetHeight()
		if not fw or fw < 2 or not fh or fh < 2 then return end
		local period = dashLen + gapLen
		-- Pixel-snap the THICKNESS (PixelUtil) so dashes never vanish at panel scale;
		-- position via plain SetPoint (snapping position is the vanishing-border bug).
		local function hdash(len, px, py)
			local t = frame:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(color.r, color.g, color.b, color.a or 1)
			t:SetWidth(len); PixelUtil.SetHeight(t, thick)
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -py)
			t:SetShown(shown); tex[#tex + 1] = t
		end
		local function vdash(len, px, py)
			local t = frame:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(color.r, color.g, color.b, color.a or 1)
			PixelUtil.SetWidth(t, thick); t:SetHeight(len)
			t:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -py)
			t:SetShown(shown); tex[#tex + 1] = t
		end
		local x = 0
		while x < fw do
			local w = math.min(dashLen, fw - x)
			hdash(w, x, 0); hdash(w, x, fh - thick)
			x = x + period
		end
		local y = 0
		while y < fh do
			local h = math.min(dashLen, fh - y)
			vdash(h, 0, y); vdash(h, fw - thick, y)
			y = y + period
		end
	end
	frame:HookScript("OnSizeChanged", rebuild)
	rebuild()
	return {
		SetColor = function(c) color = c; for _, t in ipairs(tex) do t:SetColorTexture(c.r, c.g, c.b, c.a or 1) end end,
		Show = function() shown = true; if #tex == 0 then rebuild() end; for _, t in ipairs(tex) do t:Show() end end,
		Hide = function() shown = false; for _, t in ipairs(tex) do t:Hide() end end,
	}
end

-- ---------------------------------------------------------------------------
--  EmptyState — dashed placeholder box for an empty list (v2 refinement no. 5):
--  centered muted text, subtle dashed outline. o = { text }. Height via place().
-- ---------------------------------------------------------------------------
function W.EmptyState(parent, o)
	local f = CreateFrame("Frame", nil, parent)
	local dash = makeDashedEdges(f, M.kbDashLen, M.kbDashGap)
	dash.SetColor(L.mid)
	dash.Show()
	local fs = UI.FS(f, "hint", C.textMuted)
	fs:SetPoint("LEFT", f, "LEFT", 12, 0)
	fs:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	fs:SetJustifyH("CENTER")
	fs:SetText(o.text or "")
	return f
end

function W.KeybindButton(parent, o)
	local f = CreateFrame("Frame", nil, parent)
	if o.width then f:SetWidth(o.width) end

	local topY = 0
	if o.label then
		local _, yo = fieldLabel(f, o.label); topY = yo
		f:SetHeight(CONTROL_H - topY)
	else
		f:SetHeight(CONTROL_H)
	end

	local btn = CreateFrame("Button", nil, f)
	btn:SetHeight(CONTROL_H)
	btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, topY)
	btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, topY)
	btn:RegisterForClicks("AnyUp")
	btn:EnableKeyboard(false) -- idle state: NO keyboard capture (else the button eats movement/action bar)
	UI.RoundFill(btn, C.ink700, nil, nil, UI.ROUND_R_CTRL)
	-- Border per state (Option c: dashed dropped for rounding consistency):
	-- solid gold rounded ring when a key is set (or while capturing), a thin
	-- faint rounded ring when unbound.
	local solid = UI.RoundBorder(btn, C.gold500, "OVERLAY", nil, UI.ROUND_R_CTRL)
	local faint = UI.RoundBorder(btn, L.soft, "OVERLAY", nil, UI.ROUND_R_CTRL)
	f._control = btn

	local lbl = UI.FS(btn, "selectText", C.gold300)
	lbl:SetPoint("LEFT", btn, "LEFT", 10, 0)
	lbl:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
	lbl:SetJustifyH("CENTER"); lbl:SetWordWrap(false)

	local cur = (o.get and o.get()) or ""
	local listening = false
	local function fmt(k)
		if k == "" then return o.placeholder or T("Set key …") end
		if o.format then return o.format(k) end
		return k
	end
	local function setBorder()
		if listening or cur ~= "" then
			for _, e in ipairs(solid) do UI.SetColor(e, C.gold500); e:Show() end
			for _, e in ipairs(faint) do e:Hide() end
		else
			for _, e in ipairs(solid) do e:Hide() end
			for _, e in ipairs(faint) do UI.SetColor(e, L.soft); e:Show() end
		end
	end
	local function refresh()
		if listening then
			lbl:SetText(T("Press a key …"))
			lbl:SetTextColor(C.gold200.r, C.gold200.g, C.gold200.b)
		else
			lbl:SetText(fmt(cur))
			local col = (cur ~= "") and C.gold300 or C.textMuted
			lbl:SetTextColor(col.r, col.g, col.b)
		end
		setBorder()
	end
	refresh()

	local function stopListen()
		if not listening then return end
		listening = false
		if activeCapture == stopListen then activeCapture = nil end
		-- EnableKeyboard(false) drops the button out of the keyboard chain — the real
		-- release. Propagation is managed ENTIRELY inside OnKeyDown (the only valid
		-- context); we never touch it here / on a timer (see OnKeyDown note).
		btn:EnableKeyboard(false)
		btn:EnableMouseWheel(false)
		refresh() -- updates label + border state (setBorder)
	end
	local function startListen()
		if listening then return end
		if activeCapture and activeCapture ~= stopListen then activeCapture() end -- only one listener at a time
		listening = true
		activeCapture = stopListen
		btn:EnableKeyboard(true) -- keys now reach OnKeyDown, which decides pass-through vs consume
		btn:EnableMouseWheel(true)
		refresh() -- updates label + border state (setBorder)
	end
	local function commit(key)
		cur = key
		stopListen()
		if o.set then o.set(key) end
	end

	btn:SetScript("OnClick", function(_, button)
		if not listening then startListen(); return end
		-- ALL mouse buttons (incl. right click, with held modifiers) are bindable here.
		-- Right click no longer cancels — clearing is ESC (see OnKeyDown).
		if button == "LeftButton" then commit(kbWithMods("BUTTON1"))
		elseif button == "RightButton" then commit(kbWithMods("BUTTON2"))
		elseif button == "MiddleButton" then commit(kbWithMods("BUTTON3"))
		elseif button == "Button4" then commit(kbWithMods("BUTTON4"))
		elseif button == "Button5" then commit(kbWithMods("BUTTON5")) end
	end)
	btn:SetScript("OnKeyDown", function(self, key)
		-- SetPropagateKeyboardInput may ONLY be called from inside a keyboard event —
		-- i.e. right here. Pass the key THROUGH when not listening or on a bare modifier
		-- (so it keeps doing its normal thing); consume only a real key while listening.
		-- This is the proven pattern. The earlier code set propagate=false on start and
		-- tried to reset it on a C_Timer (outside any keyboard event) — that is invalid
		-- and left the keyboard globally grabbed: every key dead, mouse still working,
		-- no error message. Never defer the propagate reset.
		if not listening then self:SetPropagateKeyboardInput(true); return end
		if KB_IGNORE[key] then self:SetPropagateKeyboardInput(true); return end
		self:SetPropagateKeyboardInput(false)
		if key == "ESCAPE" then commit(""); return end -- ESC CLEARS the binding ("Set key …")
		commit(kbWithMods(key))
	end)
	btn:SetScript("OnMouseWheel", function(_, delta)
		if not listening then return end
		commit(kbWithMods(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
	end)
	btn:SetScript("OnEnter", function()
		if listening then return end
		if cur ~= "" then for _, e in ipairs(solid) do UI.SetColor(e, C.gold400) end
		else for _, e in ipairs(faint) do UI.SetColor(e, L.strong) end end
	end)
	btn:SetScript("OnLeave", function()
		if listening then return end
		if cur ~= "" then for _, e in ipairs(solid) do UI.SetColor(e, C.gold500) end
		else for _, e in ipairs(faint) do UI.SetColor(e, L.soft) end end
	end)
	btn:HookScript("OnHide", stopListen)

	f.SetValueExternal = function(_, v) cur = v or ""; refresh() end
	f.SetWidgetEnabled = function(_, on)
		f:SetAlpha(on and 1 or 0.35)
		btn:EnableMouse(on)
		if not on then stopListen() end
	end
	return f
end

-- ---------------------------------------------------------------------------
--  GearPopover — a gold settings-cog button (Textures/icon-settings.tga, a white
--  Lucide "settings" glyph tinted gold via vertex color) that opens a floating
--  options popover: a stack of checkboxes + an optional danger "Remove" action at
--  the bottom. Floats on the menu host so the ScrollFrame can't clip it (W.Select
--  pattern). Checkbox set callbacks apply only (NOT RenderContent) so the popover
--  survives the click. o = { defs = { {label,tooltip?,get,set}, ... }, onRemove?,
--  removeText?, size? }
-- ---------------------------------------------------------------------------
function W.GearPopover(parent, o)
	local sz = o.size or LO.clickcast.gearSize
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(sz, sz)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btn)
	icon:SetTexture(TEX .. "icon-settings")
	icon:SetSnapToPixelGrid(false)
	icon:SetTexelSnappingBias(0)
	-- Two-gold rule: clickable = C2, hover = C3 (gold100 became neutral white
	-- in the v2 remap — hovering used to flash white here).
	local hbg = btn:CreateTexture(nil, "BACKGROUND")
	hbg:SetPoint("TOPLEFT", btn, "TOPLEFT", -M.iconBtnHoverPad, M.iconBtnHoverPad)
	hbg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", M.iconBtnHoverPad, -M.iconBtnHoverPad)
	hbg:SetColorTexture(P.elementHover.r, P.elementHover.g, P.elementHover.b, 1)
	hbg:Hide()
	icon:SetVertexColor(C.gold500.r, C.gold500.g, C.gold500.b, 1)
	btn:SetScript("OnEnter", function() hbg:Show(); icon:SetVertexColor(C.gold400.r, C.gold400.g, C.gold400.b, 1) end)
	btn:SetScript("OnLeave", function() hbg:Hide(); icon:SetVertexColor(C.gold500.r, C.gold500.g, C.gold500.b, 1) end)

	local host = W._menuHost or parent
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:Hide()

	local pop = CreateFrame("Frame", nil, host)
	pop:SetFrameStrata("FULLSCREEN_DIALOG")
	pop:SetFrameLevel(closer:GetFrameLevel() + 10)
	pop:Hide()
	UI.RoundFill(pop, C.ink550)
	UI.RoundBorder(pop, L.mid, "OVERLAY")
	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = pop end

	local function closePop() pop:Hide(); closer:Hide() end
	closer:SetScript("OnClick", closePop)

	local pad, gap, rowH = 12, 8, M.checkBox
	local y, maxw = -pad, 1
	local function placeTop(w) w:ClearAllPoints(); w:SetPoint("TOPLEFT", pop, "TOPLEFT", pad, y); y = y - rowH - gap end
	for _, d in ipairs(o.defs) do
		local cb = W.Checkbox(pop, d)
		placeTop(cb)
		local w = cb:GetWidth() or 1; if w > maxw then maxw = w end
	end
	if o.onRemove then
		if #o.defs > 0 then
			local sep = pop:CreateTexture(nil, "OVERLAY")
			PixelUtil.SetHeight(sep, 1)
			sep:SetPoint("TOPLEFT", pop, "TOPLEFT", pad, y + gap * 0.5)
			sep:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -pad, y + gap * 0.5)
			UI.SetColor(sep, L.faint)
		end
		local rm = CreateFrame("Button", nil, pop)
		rm:SetHeight(rowH)
		placeTop(rm)
		rm:SetPoint("RIGHT", pop, "RIGHT", -pad, 0)
		local rtxt = UI.FS(rm, "checkLabel", C.danger500)
		rtxt:SetPoint("LEFT", rm, "LEFT", 0, 0)
		rtxt:SetText(o.removeText or T("Remove"))
		rm:SetScript("OnEnter", function() rtxt:SetTextColor(C.danger300.r, C.danger300.g, C.danger300.b) end)
		rm:SetScript("OnLeave", function() rtxt:SetTextColor(C.danger500.r, C.danger500.g, C.danger500.b) end)
		rm:SetScript("OnClick", function() closePop(); o.onRemove() end)
		local w = math.ceil(rtxt:GetStringWidth()) + 20; if w > maxw then maxw = w end
	end
	pop:SetSize(math.ceil(maxw) + pad * 2, -y - gap + pad)

	btn:SetScript("OnClick", function()
		if pop:IsShown() then closePop(); return end
		pop:ClearAllPoints()
		pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -4)
		closer:Show(); pop:Show(); pop:Raise()
	end)
	return btn
end

-- ===========================================================================
--  Color picker (own popover in Lumen style instead of Blizzard's ColorPickerFrame)
--  HSV model: SV field (saturation x / value y) + hue bar + preview +
--  hex input + apply/cancel. Singleton (built once, reused),
--  on the menu host (panel) -> inherits scale, not clipped. Live preview via onChange.
-- ===========================================================================
local function rgb2hsv(r, g, b)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local v, dd = mx, mx - mn
	local s = (mx == 0) and 0 or dd / mx
	local h = 0
	if dd ~= 0 then
		if mx == r then h = ((g - b) / dd) % 6
		elseif mx == g then h = (b - r) / dd + 2
		else h = (r - g) / dd + 4 end
		h = h / 6; if h < 0 then h = h + 1 end
	end
	return h, s, v
end
local function hsv2rgb(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return v, t, p
	elseif i == 1 then return q, v, p
	elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v
	elseif i == 4 then return t, p, v
	else return v, p, q end
end
local function toHex(r, g, b)
	return string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local colorPicker -- singleton frame (lazy)

local function buildColorPicker()
	local host = W._menuHost or UIParent
	local cp = CreateFrame("Frame", nil, host)
	cp:SetFrameStrata("FULLSCREEN_DIALOG")
	cp:EnableMouse(true) -- swallows clicks (not through to the closer)
	UI.RoundFill(cp, C.ink850, nil, nil, RAD.xl) -- modal-style picker = XL
	UI.RoundBorder(cp, L.strong, "OVERLAY", nil, RAD.xl)

	-- Full-screen closer behind it (click outside = apply/close).
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:SetFrameLevel(cp:GetFrameLevel() - 1)
	cp._closer = closer

	local pad = M.cpPad
	cp:SetSize(pad * 2 + M.cpSVW + M.cpGap + M.cpHueW, pad * 3 + M.cpSVH + M.cpPrevH + M.buttonH + 14)

	-- ---- SV field (saturation x, value y) ----
	local sv = CreateFrame("Frame", nil, cp)
	sv:SetSize(M.cpSVW, M.cpSVH)
	sv:SetPoint("TOPLEFT", cp, "TOPLEFT", pad, -pad)
	sv:EnableMouse(true)
	local svBase = sv:CreateTexture(nil, "BACKGROUND")     -- pure hue color
	svBase:SetAllPoints(sv)
	local svWhite = sv:CreateTexture(nil, "ARTWORK")       -- left white -> right clear (saturation)
	svWhite:SetAllPoints(sv); svWhite:SetColorTexture(1, 1, 1, 1)
	svWhite:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
	local svBlack = sv:CreateTexture(nil, "ARTWORK", nil, 1) -- bottom black -> top clear (value)
	svBlack:SetAllPoints(sv); svBlack:SetColorTexture(0, 0, 0, 1)
	svBlack:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))
	UI.Border(sv, L.mid, 1, "OVERLAY")
	local svMark = CreateFrame("Frame", nil, sv)
	svMark:SetSize(M.cpMarker, M.cpMarker)
	UI.Border(svMark, { r = 1, g = 1, b = 1, a = 1 }, 2, "OVERLAY")

	-- ---- Hue bar (6 segments, each a vertical gradient) ----
	local hue = CreateFrame("Frame", nil, cp)
	hue:SetSize(M.cpHueW, M.cpSVH)
	hue:SetPoint("TOPLEFT", sv, "TOPRIGHT", M.cpGap, 0)
	hue:EnableMouse(true)
	local HUES = { {1,0,0}, {1,1,0}, {0,1,0}, {0,1,1}, {0,0,1}, {1,0,1}, {1,0,0} }
	local segH = M.cpSVH / 6
	for i = 1, 6 do
		local seg = hue:CreateTexture(nil, "ARTWORK")
		seg:SetColorTexture(1, 1, 1, 1)
		seg:SetPoint("TOPLEFT", hue, "TOPLEFT", 0, -(i - 1) * segH)
		seg:SetPoint("TOPRIGHT", hue, "TOPRIGHT", 0, -(i - 1) * segH)
		seg:SetHeight(segH)
		local a, c2 = HUES[i], HUES[i + 1]
		-- top = a (segment start), bottom = c2 -> min(bottom)=c2, max(top)=a
		seg:SetGradient("VERTICAL", CreateColor(c2[1], c2[2], c2[3], 1), CreateColor(a[1], a[2], a[3], 1))
	end
	UI.Border(hue, L.mid, 1, "OVERLAY")
	local hueMark = hue:CreateTexture(nil, "OVERLAY")
	hueMark:SetColorTexture(1, 1, 1, 1)
	hueMark:SetPoint("LEFT", hue, "LEFT", -2, 0)
	hueMark:SetPoint("RIGHT", hue, "RIGHT", 2, 0)
	hueMark:SetHeight(3)

	-- ---- Preview + hex ----
	local preview = CreateFrame("Frame", nil, cp)
	preview:SetSize(M.cpPrevH + 14, M.cpPrevH)
	preview:SetPoint("TOPLEFT", sv, "BOTTOMLEFT", 0, -14)
	local prevTex = preview:CreateTexture(nil, "ARTWORK"); prevTex:SetAllPoints(preview)
	UI.Border(preview, L.mid, 1, "OVERLAY")

	local hexBox = CreateFrame("EditBox", nil, cp)
	hexBox:SetSize(110, M.cpPrevH)
	hexBox:SetPoint("LEFT", preview, "RIGHT", 26, 0)
	UI.RoundFill(hexBox, C.ink700, nil, nil, R_CTRL)
	UI.RoundBorder(hexBox, L.soft, "OVERLAY", nil, R_CTRL)
	UI:SetFont(hexBox, "value", C.textStrong)
	hexBox:SetJustifyH("CENTER"); hexBox:SetAutoFocus(false); hexBox:SetMaxLetters(6)
	hexBox:SetTextInsets(6, 6, 0, 0)
	local hexHash = UI.FS(cp, "value", C.textMuted)
	hexHash:SetText("#"); hexHash:SetPoint("RIGHT", hexBox, "LEFT", -3, 0)

	-- ---- Buttons ----
	-- Apply + cancel grouped at the bottom left, small fixed gap (cpBtnGap).
	local okBtn = W.Button(cp, { text = T("Apply"), variant = "primary" })
	okBtn:SetPoint("BOTTOMLEFT", cp, "BOTTOMLEFT", pad, pad)
	local cancelBtn = W.Button(cp, { text = T("Cancel"), variant = "ghost" })
	cancelBtn:SetPoint("LEFT", okBtn, "RIGHT", M.cpBtnGap, 0)

	-- ---- State + logic ----
	cp._h, cp._s, cp._v = 0, 0, 1
	cp._orig = { 1, 1, 1 }
	cp._onChange, cp._onCancel = nil, nil

	local function curRGB() return hsv2rgb(cp._h, cp._s, cp._v) end
	local function placeMarks()
		svMark:ClearAllPoints()
		svMark:SetPoint("CENTER", sv, "TOPLEFT", cp._s * M.cpSVW, -(1 - cp._v) * M.cpSVH)
		hueMark:ClearAllPoints()
		hueMark:SetPoint("LEFT", hue, "LEFT", -2, 0)
		hueMark:SetPoint("RIGHT", hue, "RIGHT", 2, 0)
		hueMark:SetPoint("TOP", hue, "TOP", 0, -cp._h * M.cpSVH + 1.5)
	end
	local function applyVisual(fromHex)
		local hr, hg, hb = hsv2rgb(cp._h, 1, 1)
		svBase:SetColorTexture(hr, hg, hb, 1)
		local r, g, b = curRGB()
		prevTex:SetColorTexture(r, g, b, 1)
		if not fromHex then hexBox:SetText(toHex(r, g, b)) end
		placeMarks()
	end
	cp._fireChange = function()
		if cp._onChange then local r, g, b = curRGB(); cp._onChange(r, g, b) end
	end

	-- SV-Drag
	local function svFromCursor()
		local cx, cy = GetCursorPosition()
		local sc = sv:GetEffectiveScale(); if not sc or sc == 0 then return end
		cx, cy = cx / sc, cy / sc
		local left, top = sv:GetLeft(), sv:GetTop()
		if not left or not top then return end
		cp._s = clamp((cx - left) / M.cpSVW, 0, 1)
		cp._v = clamp(1 - (top - cy) / M.cpSVH, 0, 1)
		applyVisual(); cp._fireChange()
	end
	sv:SetScript("OnMouseDown", function(self) self:SetScript("OnUpdate", svFromCursor); svFromCursor() end)
	sv:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	sv:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	-- Hue-Drag
	local function hueFromCursor()
		local _, cy = GetCursorPosition()
		local sc = hue:GetEffectiveScale(); if not sc or sc == 0 then return end
		cy = cy / sc
		local top = hue:GetTop(); if not top then return end
		cp._h = clamp((top - cy) / M.cpSVH, 0, 0.999999)
		applyVisual(); cp._fireChange()
	end
	hue:SetScript("OnMouseDown", function(self) self:SetScript("OnUpdate", hueFromCursor); hueFromCursor() end)
	hue:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	hue:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

	-- Hex input
	hexBox:SetScript("OnEnterPressed", function(self)
		local s = self:GetText():gsub("[^0-9A-Fa-f]", "")
		if #s == 6 then
			local r = tonumber(s:sub(1, 2), 16) / 255
			local g = tonumber(s:sub(3, 4), 16) / 255
			local b = tonumber(s:sub(5, 6), 16) / 255
			cp._h, cp._s, cp._v = rgb2hsv(r, g, b)
			applyVisual(true); cp._fireChange()
		end
		self:ClearFocus()
	end)
	hexBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	local function close() cp:Hide(); closer:Hide() end
	cp._close = close
	okBtn:SetScript("OnClick", close) -- onChange was live -> just close
	cancelBtn:SetScript("OnClick", function()
		if cp._onCancel then cp._onCancel() end
		close()
	end)
	closer:SetScript("OnClick", close)

	cp._applyVisual = applyVisual
	return cp
end

-- o = { r,g,b, anchor?, onChange(r,g,b), onCancel() }. Opens the singleton picker.
function W.OpenColorPicker(o)
	colorPicker = colorPicker or buildColorPicker()
	local cp = colorPicker
	-- The host may have changed since build (it shouldn't) — ensure the parent.
	cp._onChange, cp._onCancel = o.onChange, o.onCancel
	cp._orig = { o.r or 1, o.g or 1, o.b or 1 }
	cp._h, cp._s, cp._v = rgb2hsv(o.r or 1, o.g or 1, o.b or 1)
	cp._applyVisual()

	cp:ClearAllPoints()
	if o.anchor then
		cp:SetPoint("TOPLEFT", o.anchor, "BOTTOMLEFT", 0, -8)
	else
		cp:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	cp._closer:Show()
	cp:Show()
	cp:Raise()
end

-- ---------------------------------------------------------------------------
--  ColorSwatch — gold-framed color field + label, opens the Lumen color picker.
--  o = {label, chip?, get -> r,g,b, set(r,g,b)}. Layout like the checkbox (box
--  left, label right) so it sits interchangeably in rows/cells. Dimensions from
--  UI.WIDGET; chip overrides the edge length (stacked rows pass switchSmallH
--  so the chip matches the switches on the same control line).
-- ---------------------------------------------------------------------------
function W.ColorSwatch(parent, o)
	local BOX = o.chip or M.checkBox
	local b = CreateFrame("Button", nil, parent)

	local box = CreateFrame("Frame", nil, b)
	box:SetSize(BOX, BOX)
	-- Color surface slightly inset so the gold frame holds it cleanly. Rounded
	-- (white asset + vertex color) so the chip follows the r4 border.
	local sw = UI.RoundFill(box, { r = 1, g = 1, b = 1, a = 1 }, "ARTWORK", nil, RAD.sm)
	sw:ClearAllPoints()
	sw:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
	sw:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
	local edges = UI.RoundBorder(box, L.mid, "OVERLAY", nil, RAD.sm)

	-- Chip + optional label on the right (compact row); labelless chips are the
	-- stacked-option-row standard (the old label-on-top "field" mode is retired —
	-- design bible §8: swatches are 28px chips in option rows everywhere).
	b:SetHeight(BOX)
	box:SetPoint("LEFT", b, "LEFT", 0, 0)
	local lbl = UI.FS(b, "checkLabel", C.textBody)
	lbl:SetText(o.label or "")
	lbl:SetPoint("LEFT", box, "RIGHT", M.checkLabelGap, 0)
	if (o.label or "") == "" then
		b:SetWidth(BOX) -- no label -> hit area = the chip itself
	else
		b:SetWidth(BOX + M.checkLabelGap + math.ceil(lbl:GetStringWidth()) + 2)
	end

	local function readRGB()
		if o.get then local r, g, bl = o.get(); return r or 1, g or 1, bl or 1 end
		return 1, 1, 1
	end
	local function paint() local r, g, bl = readRGB(); sw:SetVertexColor(r, g, bl, 1) end
	paint()

	b:SetScript("OnClick", function()
		local r, g, bl = readRGB()
		W.OpenColorPicker({
			r = r, g = g, b = bl, anchor = b,
			onChange = function(nr, ng, nb) if o.set then o.set(nr, ng, nb) end; paint() end,
			onCancel = function() if o.set then o.set(r, g, bl) end; paint() end,
		})
	end)
	b:SetScript("OnEnter", function()
		for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end
		lbl:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
	end)
	b:SetScript("OnLeave", function()
		for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end
		lbl:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b)
	end)
	b.SetValueExternal = function() paint() end
	b.SetWidgetEnabled = function(_, on) b:SetAlpha(on and 1 or 0.35); b:EnableMouse(on) end
	return b
end

-- ---------------------------------------------------------------------------
--  Hint — muted body-text line (caption), word-wrapping in its own frame
--  (so the layout stack can treat it like a normal widget with a height).
-- ---------------------------------------------------------------------------
function W.Hint(parent, text, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(height or M.hintH)
	local fs = UI.FS(f, "hint", C.textFaint)
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	fs:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
	fs:SetText(text or "")
	f._fs = fs
	return f
end

-- ---------------------------------------------------------------------------
--  TextInput — single-line input (inset field + gold border, optional gold label
--  on top, placeholder). For profile names etc. o = {label, placeholder, width,
--  get, onEnter, onChange}. Returns f with GetText/SetText/ClearText (+ f._edit).
-- ---------------------------------------------------------------------------
function W.TextInput(parent, o)
	o = o or {}
	local f = CreateFrame("Frame", nil, parent)
	if o.width then f:SetWidth(o.width) end

	local topY = 0
	if o.label then
		local _, yo = fieldLabel(f, o.label)
		topY = yo
		f:SetHeight(CONTROL_H - topY)
	else
		f:SetHeight(CONTROL_H)
	end

	local box = CreateFrame("EditBox", nil, f)
	box:SetHeight(CONTROL_H)
	box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, topY)
	box:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, topY)
	UI.RoundFill(box, C.ink700, nil, nil, R_CTRL)
	UI.RoundBorder(box, L.mid, "OVERLAY", nil, R_CTRL)
	-- Same text role as the dropdown headers (selectText): inputs and selects
	-- sit side by side in rows (Profile tab) and must read as one control family.
	UI:SetFont(box, "selectText", C.textStrong)
	box:SetTextInsets(10, 10, 0, 0)
	box:SetAutoFocus(false)
	if o.get then box:SetText(o.get() or "") end

	local ph
	if o.placeholder then
		ph = UI.FS(box, "selectText", C.textMuted)
		ph:SetText(o.placeholder)
		ph:SetPoint("LEFT", box, "LEFT", 10, 0)
		ph:SetPoint("RIGHT", box, "RIGHT", -10, 0)
		ph:SetJustifyH("LEFT")
		local function upd() ph:SetShown((box:GetText() or "") == "") end
		box:HookScript("OnTextChanged", upd); upd()
	end

	box:SetScript("OnEnterPressed", function(self2)
		self2:ClearFocus()
		if o.onEnter then o.onEnter(self2:GetText()) end
	end)
	box:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
	if o.onChange then box:HookScript("OnTextChanged", function(self2) o.onChange(self2:GetText()) end) end

	f._edit = box
	function f:GetText() return box:GetText() end
	function f:SetText(t) box:SetText(t or "") end
	function f:ClearText() box:SetText("") end
	return f
end

-- ---------------------------------------------------------------------------
--  Textarea — multi-line input (inset box + gold border) with a scrollable
--  multi-line EditBox. For export/import codes. o = {height, width, get,
--  onChange, readOnly, placeholder}. readOnly = selectable/copyable, but typing
--  changes are reset (export code). Returns GetText/SetText.
-- ---------------------------------------------------------------------------
function W.Textarea(parent, o)
	o = o or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(o.height or 120)
	if o.width then f:SetWidth(o.width) end
	UI.RoundFill(f, C.ink700, nil, nil, R_CTRL)
	UI.RoundBorder(f, L.mid, "OVERLAY", nil, R_CTRL)

	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
	sf:EnableMouseWheel(true)

	local edit = CreateFrame("EditBox", nil, sf)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	UI:SetFont(edit, "value", C.textStrong) -- role, not an ad-hoc size
	edit:SetWidth(1)
	edit:SetScript("OnEscapePressed", function(self2) self2:ClearFocus() end)
	sf:SetScrollChild(edit)
	sf:SetScript("OnSizeChanged", function(_, w) edit:SetWidth(w or 1) end)

	-- Keep the cursor in the viewport while typing + mouse wheel scrolls the box.
	edit:SetScript("OnCursorChanged", function(_, _, y, _, cursorH)
		local top = sf:GetVerticalScroll() or 0
		local viewH = sf:GetHeight() or 1
		y = -y
		if y < top then sf:SetVerticalScroll(y)
		elseif (y + cursorH) > (top + viewH) then sf:SetVerticalScroll((y + cursorH) - viewH) end
	end)
	sf:SetScript("OnMouseWheel", function(self2, d)
		local range = self2:GetVerticalScrollRange() or 0
		self2:SetVerticalScroll(math.max(0, math.min(range, (self2:GetVerticalScroll() or 0) - d * 24)))
	end)
	f:EnableMouse(true)
	f:SetScript("OnMouseDown", function() edit:SetFocus() end) -- click anywhere in the box -> focus

	local frozen = (o.get and o.get()) or ""
	edit:SetText(frozen)

	local ph
	if o.placeholder then
		ph = UI.FS(edit, "label", C.textMuted)
		ph:SetText(o.placeholder)
		ph:SetPoint("TOPLEFT", edit, "TOPLEFT", 2, -2)
		local function upd() ph:SetShown((edit:GetText() or "") == "") end
		edit:HookScript("OnTextChanged", upd); upd()
	end

	if o.readOnly then
		edit:HookScript("OnTextChanged", function(self2, user)
			if user and self2:GetText() ~= frozen then self2:SetText(frozen) end
		end)
	elseif o.onChange then
		edit:HookScript("OnTextChanged", function(self2, user) if user then o.onChange(self2:GetText()) end end)
	end

	f._edit = edit
	function f:GetText() return edit:GetText() end
	function f:SetText(t) frozen = t or ""; edit:SetText(frozen) end
	return f
end

-- ---------------------------------------------------------------------------
--  Button — v2 hierarchy (fixed rule): primary = interactive-gold FILL (max
--  one per screen) / secondary = gold outline / neutral = grey element /
--  danger = red outline (strictly destructive). o = {text,variant,onClick,width}.
--  Height 38, width from text + padding if not set. "ghost" = alias of neutral
--  (legacy call sites).
-- ---------------------------------------------------------------------------
local BTN_SIZE = UI.ROLE.btn[2]
local BTN_VARIANTS = {
	primary = {
		bg = P.goldInt, bgHover = P.goldIntHover,
		txt = C.onGold, txtHover = C.onGold,
		line = P.goldInt, lineHover = P.goldIntHover, pad = 26, font = UI.FONT.hankenBold,
	},
	secondary = {
		bg = nil, bgHover = UI.goldA(0.08),
		txt = P.goldInt, txtHover = P.goldIntHover,
		line = UI.goldA(0.55), lineHover = P.goldIntHover, pad = 22, font = UI.FONT.hankenSemi,
	},
	neutral = {
		bg = P.element, bgHover = P.elementHover,
		txt = C.textStrong, txtHover = C.textStrong,
		line = L.mid, lineHover = L.mid, pad = 22, font = UI.FONT.hankenMed,
	},
	danger = {
		bg = nil, bgHover = UI.dangerA(0.10),
		txt = P.danger, txtHover = P.dangerHover,
		line = UI.dangerA(0.55), lineHover = P.dangerHover, pad = 22, font = UI.FONT.hankenSemi,
	},
}
BTN_VARIANTS.ghost = BTN_VARIANTS.neutral

function W.Button(parent, o)
	local variant = o.variant or "primary"
	local v = BTN_VARIANTS[variant]
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(M.buttonH)

	local bg = UI.RoundFill(b, CLEAR, "BACKGROUND", nil, R_CTRL)

	-- v2: FLAT fills only (the old primary gold gradient is gone — flat design line).
	local function paintBg(hover)
		if v.bg or (hover and v.bgHover) then
			UI.SetColor(bg, (hover and v.bgHover) or v.bg)
		else
			UI.SetColor(bg, CLEAR)
		end
	end
	paintBg(false)

	local edges = UI.RoundBorder(b, v.line, "OVERLAY", nil, R_CTRL)
	local txt = UI.FS(b, "btn", v.txt)
	local okFont = txt:SetFont(v.font, BTN_SIZE, "") -- weight per variant (see BTN_VARIANTS)
	txt:SetText(o.text or "")
	-- Self-healing: if the variant font doesn't load (SetFont=false) or doesn't render
	-- the text (0 width despite content — e.g. missing glyphs like "ü" in a weight),
	-- fall back to the role font (btn = hankenSemi, renders umlauts reliably).
	-- This keeps the intended variant weight where it works.
	if (o.text or "") ~= "" and (okFont == false or txt:GetStringWidth() <= 0) then
		UI:SetFont(txt, "btn", v.txt)
		txt:SetText(o.text)
	end

	-- Optional leading Lucide icon (o.icon = texture basename in Textures/),
	-- tinted to match the label in every state (nav-icon pattern: snap off).
	local icon, iconSpan = nil, 0
	if o.icon then
		icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetSize(M.btnIcon, M.btnIcon)
		icon:SetTexture(TEX .. o.icon)
		icon:SetSnapToPixelGrid(false)
		icon:SetTexelSnappingBias(0)
		icon:SetVertexColor(v.txt.r, v.txt.g, v.txt.b)
		iconSpan = M.btnIcon + M.btnIconGap
		icon:SetPoint("RIGHT", txt, "LEFT", -M.btnIconGap, 0)
	end
	-- Center the icon+label pair as one block.
	txt:SetPoint("CENTER", b, "CENTER", iconSpan / 2, 0)

	local function fitWidth()
		b:SetWidth(o.width or (math.ceil(txt:GetStringWidth()) + iconSpan + v.pad * 2))
	end
	fitWidth()

	-- Cold-start guarantee: a cold glyph cache (first session use of the Bold
	-- weight, e.g. the Profile tab's primary buttons) can MEASURE a width while
	-- still rendering the glyphs blank — so gating on width > 0 (the old check)
	-- wrongly skipped the fix. Instead re-apply weight + text ONCE the button is
	-- actually on screen (visibility forces rasterization). Covers both paths:
	-- built visible (Profile tab re-render) via the creation timer, and built
	-- hidden (parked screen) via OnShow.
	if (o.text or "") ~= "" then
		local healed = false
		local function heal()
			if healed or not b:IsVisible() then return end
			healed = true
			if txt:SetFont(v.font, BTN_SIZE, "") == false then UI:SetFont(txt, "btn") end
			-- Re-setting the SAME string can be a client-side no-op (no re-shape,
			-- blank glyphs stay blank) -> clear first so the re-set is a real change.
			txt:SetText("")
			txt:SetText(o.text)
			fitWidth()
		end
		b:HookScript("OnShow", function() C_Timer.After(0, heal) end)
		C_Timer.After(0, heal)
	end

	b:SetScript("OnEnter", function()
		paintBg(true)
		for _, e in ipairs(edges) do UI.SetColor(e, v.lineHover) end
		txt:SetTextColor(v.txtHover.r, v.txtHover.g, v.txtHover.b)
		if icon then icon:SetVertexColor(v.txtHover.r, v.txtHover.g, v.txtHover.b) end
	end)
	b:SetScript("OnLeave", function()
		paintBg(false)
		for _, e in ipairs(edges) do UI.SetColor(e, v.line) end
		txt:SetTextColor(v.txt.r, v.txt.g, v.txt.b)
		if icon then icon:SetVertexColor(v.txt.r, v.txt.g, v.txt.b) end
	end)
	if o.onClick then b:SetScript("OnClick", o.onClick) end
	b._txt = txt
	return b
end

-- ---------------------------------------------------------------------------
--  MenuButton — a button that opens a small popover list of options (labels may
--  carry inline |T..|t icons) and calls o.onPick(value). For "+ Add binding"
--  (pick a catalog action). Floats on the menu host (non-clipped), like W.Select.
--  o = { text, variant?, width?, options = { { value, label }, ... }, onPick }
-- ---------------------------------------------------------------------------
function W.MenuButton(parent, o)
	-- bare = catalog-row style trigger (square gold icon tile + plain "choose …"
	-- text), so a freshly-added standard row matches the others and you pick the
	-- action right in the row. Otherwise = a normal (e.g. green) button.
	local btn
	if o.bare then
		btn = CreateFrame("Button", nil, parent)
		btn:SetHeight(LO.clickcast.rowH)
		if o.width then btn:SetWidth(o.width) end
		local tile = W.SquareIcon(btn, LO.clickcast.icon)
		tile:SetPoint("LEFT", btn, "LEFT", 0, 0)
		tile:SetIcon(o.icon)
		local txt = UI.FS(btn, "selectText", o.icon and C.textBody or C.textMuted)
		txt:SetPoint("LEFT", tile, "RIGHT", 10, 0)
		txt:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
		txt:SetJustifyH("LEFT"); txt:SetWordWrap(false)
		txt:SetText(o.text or T("Select"))
	else
		btn = W.Button(parent, { text = o.text, variant = o.variant or "ghost", width = o.width })
	end

	local host = W._menuHost or parent
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:Hide()
	local menu = CreateFrame("Frame", nil, host)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(closer:GetFrameLevel() + 10)
	menu:Hide()
	UI.RoundFill(menu, C.ink550)
	UI.RoundBorder(menu, L.mid, "OVERLAY")
	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = menu end

	local function closeMenu() menu:Hide(); closer:Hide() end
	closer:SetScript("OnClick", closeMenu)

	local pad, rowH, gap = 6, 30, 2
	local prev, maxw = nil, 1
	for _, op in ipairs(o.options) do
		local item = CreateFrame("Button", nil, menu)
		item:SetHeight(rowH)
		if prev then item:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
		else item:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -pad) end
		item:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
		local wash = item:CreateTexture(nil, "BACKGROUND")
		wash:SetAllPoints(item); wash:SetColorTexture(0, 0, 0, 0)
		local itxt = UI.FS(item, "selectText", C.textStrong)
		itxt:SetPoint("LEFT", item, "LEFT", 10, 0)
		itxt:SetText(op.label)
		item:SetScript("OnEnter", function()
			wash:SetColorTexture(C.inkTint.r, C.inkTint.g, C.inkTint.b, 1)
			itxt:SetTextColor(C.gold100.r, C.gold100.g, C.gold100.b)
		end)
		item:SetScript("OnLeave", function()
			wash:SetColorTexture(0, 0, 0, 0)
			itxt:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
		end)
		item:SetScript("OnClick", function() closeMenu(); if o.onPick then o.onPick(op.value) end end)
		local w = math.ceil(itxt:GetStringWidth()) + 32
		if w > maxw then maxw = w end
		prev = item
	end
	menu:SetWidth(math.max(maxw + pad * 2, btn:GetWidth() or 120))
	menu:SetHeight(pad * 2 + #o.options * rowH + math.max(0, #o.options - 1) * gap)

	btn:SetScript("OnClick", function()
		if menu:IsShown() then closeMenu(); return end
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
		closer:Show(); menu:Show(); menu:Raise()
	end)
	return btn
end

-- ---------------------------------------------------------------------------
--  IconTile — beveled gold chip (signature element) with a Cinzel letter. For
--  spell/module tiles in lists. o = {size,letter}.
-- ---------------------------------------------------------------------------
function W.IconTile(parent, o)
	local size = o.size or 56
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(1, 1, 1, 1)
	bg:SetGradient("VERTICAL",
		CreateColor(C.ink650.r, C.ink650.g, C.ink650.b, 1),
		CreateColor(C.inkTint.r, C.inkTint.g, C.inkTint.b, 1))
	UI.Border(f, L.soft, 1)
	local lt = UI.FS(f, "groupTitle", C.gold300)
	lt:SetPoint("CENTER", f, "CENTER", 0, 0)
	lt:SetText(o.letter or "?")
	f._letter = lt
	return f
end

-- ---------------------------------------------------------------------------
--  Card — raised container (surface #171411, gold hairline). Height set by the
--  caller; anchor content directly into the card or with its own padding.
-- ---------------------------------------------------------------------------
function W.Card(parent)
	local c = CreateFrame("Frame", nil, parent)
	UI.RoundFill(c, C.ink600) -- group box = LG (card default)
	UI.RoundBorder(c, L.soft)
	return c
end

-- ---------------------------------------------------------------------------
--  Collapsible — a clickable section-style header bar (gold accent + title +
--  chevron) that toggles a body. It holds NO content itself: the caller stores
--  the open state, builds the body below ONLY when open, and re-renders on
--  toggle (consistent with the Shell's immediate-mode stacker). Chevron points
--  down when open, right when collapsed. Height = M.sectionHeaderH.
--  o = { title, open, onToggle(newState), subtitle?, summary?, toggle?,
--  attached? (body card follows flush when open -> top-only rounding) }.
--  subtitle: muted description right of the title (v3 mockup). summary: muted
--  STATE text, right-aligned before the toggle/chevron — keeps a collapsed
--  section readable ("Rolle · Tank > Heiler"). toggle = { get, set, tooltip? }:
--  small master switch in the header (own Button, so it doesn't trip the
--  collapse click).
-- ---------------------------------------------------------------------------
function W.Collapsible(parent, o)
	o = o or {}
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(M.sectionHeaderH)
	-- Rounded card (r8). o.attached: the caller places the body card FLUSH
	-- below when open -> only the top corners round (the body card uses
	-- round = "bottom"), so header + body read as one rounded object.
	local shape = (o.open and o.attached) and "top" or nil
	UI.RoundFill(f, C.ink600, nil, shape)
	UI.RoundBorder(f, L.soft, "OVERLAY", shape)

	local title = UI.FS(f, "sectionHead", C.gold300)
	title:SetPoint("LEFT", f, "LEFT", M.sectionPad, 0)
	title:SetText(o.title or "")

	-- Chevron: Lucide chevron-down when open, chevron-right when collapsed (gold).
	local chev = f:CreateTexture(nil, "OVERLAY")
	chev:SetSize(M.chevGlyph, M.chevGlyph)
	chev:SetPoint("RIGHT", f, "RIGHT", -M.sectionTitleX, 0)
	chev:SetTexture(TEX .. (o.open and "icon-chevron-down" or "icon-chevron-right"))
	chev:SetSnapToPixelGrid(false); chev:SetTexelSnappingBias(0)
	chev:SetVertexColor(C.gold300.r, C.gold300.g, C.gold300.b)

	-- Master toggle in the header (right of the summary, left of the chevron).
	local rightAnchor = chev
	if o.toggle then
		local sw = W.Switch(f, { small = true, get = o.toggle.get, set = o.toggle.set, tooltip = o.toggle.tooltip })
		sw:SetPoint("RIGHT", chev, "LEFT", -M.collapsibleToggleGap, 0)
		f._switch = sw
		rightAnchor = sw
	end

	-- Summary: muted single-line STATE text, right-aligned before the toggle/
	-- chevron cluster (v3 mockup).
	local sumLeft = rightAnchor
	if o.summary then
		local sum = UI.FS(f, "value", C.textMuted)
		sum:SetPoint("RIGHT", rightAnchor, "LEFT", -M.collapsibleSummaryGap, 0)
		sum:SetJustifyH("RIGHT")
		sum:SetWordWrap(false)
		sum:SetText(o.summary)
		f._summary = sum
		sumLeft = sum
	end

	-- Subtitle: muted description right of the title, truncates against the
	-- right cluster.
	if o.subtitle then
		local sub = UI.FS(f, "caption", C.textMuted)
		sub:SetPoint("LEFT", title, "RIGHT", M.collapsibleSummaryGap, 0)
		sub:SetPoint("RIGHT", sumLeft, "LEFT", -M.collapsibleSummaryGap, 0)
		sub:SetJustifyH("LEFT")
		sub:SetWordWrap(false)
		sub:SetText(o.subtitle)
		f._subtitle = sub
	end

	-- Optional header EYE (card-eye system): toggles this section's preview /
	-- edit-mode layer. Own Button (doesn't trip the collapse click), left of the
	-- title; the title shifts right. Mirrors makeBox's card eye.
	if o.eye then
		local eb = CreateFrame("Button", nil, f)
		eb:SetSize(M.cardEyeBtn, M.cardEyeBtn)
		eb:SetFrameLevel(f:GetFrameLevel() + 5)
		eb:SetPoint("LEFT", f, "LEFT", M.sectionPad, 0)
		title:ClearAllPoints()
		title:SetPoint("LEFT", f, "LEFT", M.sectionPad + M.cardEyeBtn + S.s3, 0)
		local g = eb:CreateTexture(nil, "ARTWORK")
		g:SetSize(M.cardEyeGlyph, M.cardEyeGlyph)
		g:SetPoint("CENTER", eb, "CENTER", 0, 0)
		g:SetSnapToPixelGrid(false); g:SetTexelSnappingBias(0)
		local hovered = false
		local function paintEye()
			local on = o.eye.get()
			g:SetTexture(TEX .. (on and "icon-eye" or "icon-eye-off"))
			local col = hovered and P.goldIntHover or (on and P.goldInt or C.textMuted)
			g:SetVertexColor(col.r, col.g, col.b)
		end
		paintEye()
		eb:SetScript("OnEnter", function() hovered = true; paintEye()
			if o.eye.tip then W.ShowTextTip(eb, o.eye.tip, nil, "TOP") end end)
		eb:SetScript("OnLeave", function() hovered = false; paintEye(); W.HideTip() end)
		eb:SetScript("OnClick", function() o.eye.set(not o.eye.get()); paintEye() end)
	end

	-- Hover wash (subtle, like the tracking rows) — rounded like the card, so
	-- the wash doesn't poke out of the corners.
	local hov = UI.RoundFill(f, C.inkTint, "BORDER", shape); hov:SetAlpha(0)
	f:SetScript("OnEnter", function() hov:SetAlpha(0.5) end)
	f:SetScript("OnLeave", function() hov:SetAlpha(0) end)
	f:SetScript("OnClick", function() if o.onToggle then o.onToggle(not o.open) end end)
	return f
end

-- ---------------------------------------------------------------------------
--  Disclosure — quiet "advanced" footer row of a section card (card grid
--  system). Immediate-mode like W.Collapsible: the caller owns the open state,
--  builds the advanced rows above/behind it only when open and re-renders on
--  toggle. o = { open, label (localized "Advanced"/"Less"), hint? (contents
--  preview, shown while closed), onToggle(newState) }.
-- ---------------------------------------------------------------------------
function W.Disclosure(parent, o)
	o = o or {}
	local f = CreateFrame("Button", nil, parent)
	f:SetHeight(M.disclosureH)

	-- Hairline on top: separates the footer from the card content.
	local sep = f:CreateTexture(nil, "OVERLAY")
	PixelUtil.SetHeight(sep, 1)
	sep:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	UI.SetColor(sep, L.faint)

	-- Chevron: Lucide chevron-up when open, chevron-right when closed (muted;
	-- brightens to gold on hover via paint()).
	local chev = f:CreateTexture(nil, "OVERLAY")
	chev:SetSize(M.chevGlyph, M.chevGlyph)
	chev:SetPoint("LEFT", f, "LEFT", 0, -1)
	chev:SetTexture(TEX .. (o.open and "icon-chevron-up" or "icon-chevron-right"))
	chev:SetSnapToPixelGrid(false); chev:SetTexelSnappingBias(0)
	local function paint(col) chev:SetVertexColor(col.r, col.g, col.b) end
	paint(C.textMuted)

	local lbl = UI.FS(f, "value", C.textMuted)
	lbl:SetPoint("LEFT", chev, "RIGHT", M.disclosureChevGap, -1)
	lbl:SetText(o.label or "")

	-- Contents preview while closed ("Typ-Farben, Text-Position …") — nothing
	-- becomes unfindable behind the fold.
	if o.hint and not o.open then
		local hint = UI.FS(f, "caption", C.textMuted)
		hint:SetPoint("LEFT", lbl, "RIGHT", M.disclosureHintGap, 0)
		hint:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		hint:SetJustifyH("LEFT")
		hint:SetWordWrap(false)
		hint:SetText(o.hint)
	end

	f:SetScript("OnEnter", function()
		lbl:SetTextColor(P.goldIntHover.r, P.goldIntHover.g, P.goldIntHover.b)
		paint(P.goldIntHover)
	end)
	f:SetScript("OnLeave", function()
		lbl:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
		paint(C.textMuted)
	end)
	f:SetScript("OnClick", function() if o.onToggle then o.onToggle(not o.open) end end)
	return f
end

-- ---------------------------------------------------------------------------
--  GroupPanel — bordered area with a heading + optional inline control on the
--  right (e.g. a "Show" toggle). o = {title}. Returns (frame, contentFrame).
--  Height set by the caller (frame:SetHeight); contentFrame fills below.
-- ---------------------------------------------------------------------------
function W.GroupPanel(parent, o)
	local g = CreateFrame("Frame", nil, parent)
	local bg = g:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(g)
	bg:SetColorTexture(C.ink600.r, C.ink600.g, C.ink600.b, 0.45)
	UI.Border(g, L.soft, 1)

	local title = UI.FS(g, "groupTitle", C.textHeading)
	title:SetText(o.title or "")
	title:SetPoint("TOPLEFT", g, "TOPLEFT", S.cardPad, M.groupTitleY)

	-- Content area below the heading, with card padding.
	local content = CreateFrame("Frame", nil, g)
	content:SetPoint("TOPLEFT", g, "TOPLEFT", S.cardPad, M.groupContentY)
	content:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -S.cardPad, S.cardPad)

	g._title, g._content = title, content
	-- Anchor point for an optional header-right control.
	g._headerRightAnchor = function(ctrl)
		ctrl:SetParent(g)
		ctrl:ClearAllPoints()
		ctrl:SetPoint("RIGHT", g, "TOPRIGHT", -S.cardPad, 0)
		ctrl:SetPoint("TOP", title, "TOP", 0, 4)
	end
	return g, content
end

-- ---------------------------------------------------------------------------
--  Row — N equal-width cells side by side (matches prototype row3/row2).
--  Returns a list of cell frames; anchor the widget per cell into them.
-- ---------------------------------------------------------------------------
function W.Row(parent, count, opts)
	opts = opts or {}
	local gap = opts.gap or M.rowGap
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(opts.height or M.sliderH)
	local cells = {}
	for i = 1, count do
		local cell = CreateFrame("Frame", nil, f)
		cell:SetPoint("TOP", f, "TOP", 0, 0)
		cell:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
		cells[i] = cell
	end
	-- Width distribution only once the row width is known (anchor-dependent).
	f:SetScript("OnSizeChanged", function(self, w)
		w = w or self:GetWidth() or 0
		local cw = (w - gap * (count - 1)) / count
		if cw < 1 then cw = 1 end
		for i, cell in ipairs(cells) do
			cell:ClearAllPoints()
			cell:SetPoint("TOP", self, "TOP", 0, 0)
			cell:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
			cell:SetPoint("LEFT", self, "LEFT", (i - 1) * (cw + gap), 0)
			cell:SetWidth(cw)
		end
	end)
	f._cells = cells
	return f, cells
end

-- ---------------------------------------------------------------------------
--  FieldRow — N field cells at the ONE addon-wide field width (stacked-row
--  standard, design bible §8): half the content width of a 6-track card (the
--  QoL size/thickness measure). Cells sit left-aligned with a cardGap gutter;
--  leftover card width stays AIR — field controls never stretch to the card
--  width and never shrink below the unit. `page` is the screen holder frame
--  the unit derives from, so a dropdown is exactly as wide on an 8-card as on
--  a 6- or 4-card, and the width stays responsive on panel resize.
-- ---------------------------------------------------------------------------
function W.FieldRow(parent, page, count, opts)
	opts = opts or {}
	local G = UI.GRID
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(opts.height or (M.controlH + M.fieldGap))
	local cells = {}
	for i = 1, count do
		local cell = CreateFrame("Frame", nil, f)
		cell:SetPoint("TOP", f, "TOP", 0, 0)
		cell:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
		cells[i] = cell
	end
	-- Cell width resolves once anchors do (page width is unknown at build
	-- time; same OnSizeChanged pattern as W.Row).
	local function layout()
		local pw = page and page:GetWidth() or 0
		if pw <= 0 then return end
		local unit = ((pw - G.cardGap) / 2 - M.sectionPad * 2 - G.cardGap) / 2
		if unit < 1 then return end
		for i, cell in ipairs(cells) do
			cell:SetPoint("LEFT", f, "LEFT", (i - 1) * (unit + G.cardGap), 0)
			cell:SetWidth(unit)
		end
	end
	f:SetScript("OnSizeChanged", layout)
	layout()
	f._cells = cells
	return f, cells
end

-- ---------------------------------------------------------------------------
--  OptionRow — stacked settings row (stacked-row standard, design bible §8):
--  soft top hairline, label LEFT, ONE compact control (switch / checkbox /
--  28px color chip — all switchSmallH tall) attached RIGHT via row:Attach().
--  All rows share one height (M.optionRowH) so nothing jumps inside a card;
--  SetWidgetEnabled greys the label together with the attached control.
-- ---------------------------------------------------------------------------
function W.OptionRow(parent, label)
	local row = CreateFrame("Frame", nil, parent)
	local line = row:CreateTexture(nil, "ARTWORK")
	UI.SetColor(line, L.faint)
	line:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
	-- Thickness pixel-snapped, position plain (the UI.Border rule): a naive
	-- 1px height rounds away under the panel scale depending on the row's y
	-- position — bit the aggro "Color" row on 2026-07-11.
	local function snap() PixelUtil.SetHeight(line, 1) end
	snap()
	C_Timer.After(0, snap)
	row:HookScript("OnSizeChanged", snap)
	row:HookScript("OnShow", snap)
	local lbl = UI.FS(row, "checkLabel", C.textBody)
	lbl:SetText(label)
	lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
	lbl:SetJustifyH("LEFT")
	function row:Attach(ctrl)
		ctrl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row._control = ctrl
		return row
	end
	row.SetWidgetEnabled = function(_, on)
		local col = on and C.textBody or C.textFaint
		lbl:SetTextColor(col.r, col.g, col.b)
		if row._control and row._control.SetWidgetEnabled then row._control:SetWidgetEnabled(on) end
	end
	return row
end

-- ---------------------------------------------------------------------------
--  PreviewBand — content of the Shell's preview DOCK (the satellite window
--  right of / below the panel, see Shell:SetDockLayout). Chrome: a v3 header
--  CARD (PREVIEW title left, right-aligned: context/size chip groups + collapse
--  chevron; the card is the drag handle) and the inset stage with a caption
--  line. Per-layer visibility lives as an eye on each SETTING CARD now (the old
--  funnel filter popover was removed, Florian 2026-07-16); o.eyes() is still the
--  profile table the render reads to hide/restore layers.
--  The owning MODULE fills band.holder with its preview frames (true
--  on-screen size via SetScale on the holder) and reports the VISUAL extent
--  + dock side via band:SetExtent(side, w, h, caption).
--  o = { eyes = fn -> tbl, onEye = fn(),
--        ctx = optional { values = { { v =, label = }, .. }, get, set } —
--              context switch chips (Base tab: Raid/Group),
--        sizes = optional { values = { .. }, get = fn, set = fn(v) },
--        open = optional { get = fn, set = fn(v) } — collapse state,
--        onLayout = fn(side, dockW or nil, dockH),
--        onChrome = optional fn(on) — dock window chrome (now always on),
--        onResetPos = optional fn() — header action (re-dock the window) }
-- ---------------------------------------------------------------------------
function W.PreviewBand(parent, o)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent)

	-- Header CARD (v3 top-card style, like the Base "enable" card): a rounded
	-- fill+border card inset from the dock edges, holding the title + all
	-- controls. It stands out from the dock surface (esp. with the backdrop
	-- hidden via the filter) and IS the drag handle — so the separate grip is
	-- gone (Florian 2026-07-05).
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", M.pvDockPad, -M.pvDockPad)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -M.pvDockPad, -M.pvDockPad)
	head:SetHeight(M.sectionHeaderH)
	-- The head is a REAL card matching the settings cards EXACTLY: same fill
	-- (ink600) and border (L.soft). With the page-colored stage below (no black
	-- box) this reads as page + card — like the settings page itself, not a
	-- nested "double frame" (Florian 2026-07-05).
	UI.RoundFill(head, C.ink600, nil, nil, RAD.lg)
	UI.RoundBorder(head, L.soft, "OVERLAY", nil, RAD.lg)
	local lbl = UI.FS(head, "sectionHead", C.gold300)
	lbl:SetText(T("PREVIEW"))
	lbl:SetPoint("LEFT", head, "LEFT", M.sectionTitleX, 0)

	-- Icon order (right to left): collapse chevron — then the chip groups chain
	-- further left. The old funnel filter popover is GONE (Florian 2026-07-16):
	-- per-layer visibility now lives as an eye on each setting card, so the
	-- preview stays clean and the control lives with the setting it toggles.

	-- Collapse chevron (aura-section pattern): folds the dock away. Direction
	-- follows the dock side (right dock folds LEFT onto the panel edge,
	-- bottom dock folds UP); state lives in o.open.
	local cbtn = CreateFrame("Button", nil, head)
	cbtn:SetSize(M.pvIconBtn, M.pvIconBtn)
	cbtn:SetPoint("RIGHT", head, "RIGHT", -M.pvDockPad, 0)
	UI.RoundFill(cbtn, C.ink700, nil, nil, R_CTRL) -- lighter than the ink600 card, like a dropdown on a settings card
	UI.RoundBorder(cbtn, L.mid, "OVERLAY", nil, R_CTRL)
	local cGlyph = cbtn:CreateTexture(nil, "OVERLAY")
	cGlyph:SetSize(M.pvGlyph, M.pvGlyph)
	cGlyph:SetPoint("CENTER", cbtn, "CENTER", 0, 0)
	cGlyph:SetSnapToPixelGrid(false); cGlyph:SetTexelSnappingBias(0)
	cGlyph:SetVertexColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
	local CHEV_TEX = { up = "icon-chevron-up", down = "icon-chevron-down", left = "icon-chevron-left" }
	local function chevDir(dir)
		cGlyph:SetTexture(TEX .. (CHEV_TEX[dir] or "icon-chevron-down"))
	end
	local function isOpen() return not o.open or o.open.get() end

	-- Header chip groups (right-aligned, left of the collapse button): the Base tab's
	-- Raid/Group context switch (o.ctx) and the sample-size chips (o.sizes).
	-- They live in the STATIONARY header bar on purpose — in a row below it
	-- they moved/jumped whenever a switch resized or re-docked the window,
	-- away from under the cursor. Chain builds right-to-left.
	-- Reset-position button (rotate-ccw glyph), left of the collapse chevron:
	-- snaps a dragged-away dock back onto its panel edge. Direct header action
	-- (Florian 2026-07-06) — you often nudge the dock and just want it home.
	local resetAnchor = cbtn
	if o.onResetPos then
		local rbtn = CreateFrame("Button", nil, head)
		rbtn:SetSize(M.pvIconBtn, M.pvIconBtn)
		rbtn:SetPoint("RIGHT", cbtn, "LEFT", -S.s4, 0)
		UI.RoundFill(rbtn, C.ink700, nil, nil, R_CTRL)
		UI.RoundBorder(rbtn, L.mid, "OVERLAY", nil, R_CTRL)
		local rGlyph = rbtn:CreateTexture(nil, "OVERLAY")
		rGlyph:SetSize(M.pvGlyph, M.pvGlyph)
		rGlyph:SetPoint("CENTER", rbtn, "CENTER", 0, 0)
		rGlyph:SetTexture(TEX .. "icon-reset")
		rGlyph:SetSnapToPixelGrid(false); rGlyph:SetTexelSnappingBias(0)
		rGlyph:SetVertexColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
		rbtn:SetScript("OnClick", function() o.onResetPos() end) -- no hover (matches the collapse icon)
		resetAnchor = rbtn
	end

	local repaints = {}
	local chipsW = 0
	local chainAnchor, chainGap = resetAnchor, M.pvChipGroupGap
	-- items = { { v =, label = }, ... }; paints selection from get(), sets via set(v).
	local function chipGroup(items, get, set)
		local chips = {}
		for i = #items, 1, -1 do
			local item = items[i]
			local chip = CreateFrame("Button", nil, head)
			chip:SetHeight(M.pvEyeH)
			UI.RoundFill(chip, C.ink900, nil, nil, RAD.sm)
			local edges = UI.RoundBorder(chip, L.mid, "OVERLAY", nil, RAD.sm)
			local txt = UI.FS(chip, "value", C.textMuted)
			txt:SetPoint("CENTER", chip, "CENTER", 0, 0)
			txt:SetText(item.label)
			chip:SetWidth(math.max(M.pvEyeH, math.ceil(txt:GetStringWidth()) + M.pvEyePadX * 2))
			chip:SetPoint("RIGHT", chainAnchor, "LEFT", -chainGap, 0)
			chipsW = chipsW + chip:GetWidth() + chainGap
			chainAnchor, chainGap = chip, M.pvEyeGap
			chips[#chips + 1] = { v = item.v, paint = function(on)
				for _, e in ipairs(edges) do UI.SetColor(e, on and L.strong or L.mid) end
				local tc = on and C.gold250 or C.textFaint
				txt:SetTextColor(tc.r, tc.g, tc.b)
			end }
			local v = item.v
			chip:SetScript("OnClick", function() set(v) end)
		end
		chainGap = M.pvChipGroupGap
		repaints[#repaints + 1] = function()
			local cur = get()
			for _, c in ipairs(chips) do c.paint(c.v == cur) end
		end
		repaints[#repaints]()
	end
	if o.sizes then
		local items = {}
		for _, v in ipairs(o.sizes.values) do items[#items + 1] = { v = v, label = tostring(v) } end
		chipGroup(items, o.sizes.get, o.sizes.set)
	end
	if o.ctx then chipGroup(o.ctx.values, o.ctx.get, o.ctx.set) end
	function f:PaintChips()
		for _, rp in ipairs(repaints) do rp() end
	end

	-- Minimum dock width so the header row never collapses onto itself.
	local headMinW = M.sectionTitleX + math.ceil(lbl:GetStringWidth()) + S.s7
		+ chipsW + M.pvIconBtn + S.s4 + M.pvIconBtn + M.pvDockPad * 2

	-- Body below the header card (aligned to it — the card is already inset):
	-- the stage.
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -M.pvDockPad)
	body:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -M.pvDockPad)
	body:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", M.pvDockPad, M.pvDockPad)
	body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -M.pvDockPad, M.pvDockPad)

	-- Stage: the preview surface the frames render on. Now the PAGE color (like
	-- the settings page behind its cards) with no border, so the whole preview
	-- reads as one page-colored area — not a boxed black stage nested in frames
	-- (Florian 2026-07-05). Still toggled by the "Backdrop" filter: hidden ->
	-- frames float freely on the screen, header block stays as the handle.
	local stage = CreateFrame("Frame", nil, body)
	stage:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	stage:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
	stage:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
	stage:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
	local stageFill = UI.RoundFill(stage, P.panel, nil, nil, R_CTRL)
	local stageEdges = {} -- no stage border (merges with the page-colored dock body)
	-- Unscaled positioning pivot: anchor offsets are interpreted in the ANCHORED
	-- frame's own (scaled) units — the pivot stays at scale 1, so the module's
	-- scaled holder can be placed with plain stage-pixel offsets.
	local pos = CreateFrame("Frame", nil, stage)
	pos:SetSize(1, 1)
	pos:SetPoint("CENTER", stage, "CENTER", 0, M.pvCaptionH / 2)
	local holder = CreateFrame("Frame", nil, stage)
	holder:SetPoint("CENTER", pos, "CENTER", 0, 0)
	holder:SetSize(1, 1)

	local caption = UI.FS(stage, "caption", C.textMuted)
	caption:SetPoint("BOTTOM", stage, "BOTTOM", 0, S.s2 + 2)

	f.holder = holder
	f.GetEyes = o.eyes

	-- Collapse wiring: the header's collapse button closes the dock via the
	-- Shell (closed = the dock is fully hidden by _UpdateDock — the old
	-- collapsed vertical face is gone, Florian 2026-07-05).
	local function setOpen(v)
		if o.open then o.open.set(v) end
		if o.onEye then o.onEye() end
	end
	cbtn:SetScript("OnClick", function() setOpen(not isOpen()) end)
	body:SetShown(true)
	chevDir("up")

	-- Layout pass: w/h = VISUAL extent of the holder content (already scale-
	-- corrected by the module). Computes the dock OUTER size (content-driven on
	-- both axes) and hands it to o.onLayout. Only ever runs while the dock is
	-- shown (open); closed = the Shell hides the whole dock.
	function f:SetExtent(side, w, h, cap)
		caption:SetText(cap or "")
		self:PaintChips()
		-- Chevron mirrors the fold-away direction: right dock folds LEFT onto
		-- the panel edge, bottom dock folds UP.
		chevDir(side == "right" and "left" or "up")
		-- Dock chrome is always on now (the Backdrop filter was removed with the
		-- funnel popover; per-layer eyes live on the setting cards).
		stageFill:SetShown(true)
		for _, e in ipairs(stageEdges) do e:SetShown(true) end
		caption:SetShown(true)
		if o.onChrome then o.onChrome(true) end
		local innerW = math.max(w + M.pvStagePad * 2, M.pvStageMinW,
			headMinW - M.pvDockPad * 2)
		local innerH = math.max(h + M.pvStagePad * 2 + M.pvCaptionH, M.pvMinStageH)
		local dockW = innerW + M.pvDockPad * 2
		-- Header card is inset top+bottom now -> one extra pvDockPad vs. the old
		-- flush header bar (pad | head | pad | stage | pad).
		local dockH = M.sectionHeaderH + M.pvDockPad * 3 + innerH
		if side == "right" then o.onLayout("right", dockW, dockH)
		else o.onLayout("bottom", nil, dockH) end
	end

	return f
end
