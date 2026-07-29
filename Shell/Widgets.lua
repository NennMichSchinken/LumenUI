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
local S, M = UI.S, UI.WIDGET
local Surface, Text, Border, Accent, Status = UI.Surface, UI.Text, UI.Border, UI.Accent, UI.Status
local LO = UI.LAYOUT -- screen-specific measures
local T = ns.T   -- localization: T("english") -> display in the active language
-- Texture folder, built from the real addon-folder name (survives a rename).
local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\icons\\" -- Widgets only draws icon-* textures

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
	UI.Fill(t, Surface.Window)
	UI.Stroke(t, Border.default, 1, "OVERLAY") -- subtle edge, not a bright-white frame (Florian 2026-07-22: the icon border read too thick)
	local tex = t:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	t.tex = tex
	function t:SetIcon(icon)
		if icon then tex:SetTexture(icon)
		else tex:SetColorTexture(Surface.Input.r, Surface.Input.g, Surface.Input.b, 1) end
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
	local bg = UI.RoundFill(b, Surface.Hover, "BACKGROUND", nil, RAD.sm)
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
	local col, hov = o.color or Accent.color, o.hoverColor or Accent.hover
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
	-- Muted, not bright (Florian 2026-07-22 + mockup .flabel = --txt-2 #8A8A90):
	-- every slider/select/segment cell carries one of these labels, so bright-
	-- white on all of them made the screens read "overloaded". The VALUE readout
	-- beside it stays bright — the label recedes, the value + control lead.
	local lbl = UI.FS(parent, "fieldLabel", Text.Description)
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
	-- Settings search: field controls carry their own label (they sit in a
	-- FieldRow cell, not in a W.OptionRow), so they register themselves.
	if o.label and ns.Shell and ns.Shell.IndexOption then
		ns.Shell:IndexOption(o.label, f, "slider", o.tooltip)
	end
	if o.width then f:SetWidth(o.width) end

	-- Compact = a field cell: label in the same small style as Select/Swatch
	-- labels (the Cinzel slider cap is too wide there and wraps). Classic
	-- keeps the display cap.
	local cap = UI.FS(f, compact and "fieldLabel" or "sliderCap", compact and Text.Description or Text.Primary)
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
		-- Inset by the thumb's own radius (Florian 2026-07-22): the thumb's
		-- CENTER travels end-to-end across the track below, so at 0%/100% half
		-- its disc used to overhang past the cell edge -- eating into the gap
		-- to the next card at 100%, feeling like zero space. Insetting the
		-- track keeps the thumb's OUTER edge flush with the cell at both
		-- extremes instead, never spilling out, while the value still reads 0/100.
		local thumbR = M.sliderThumb / 2
		track:SetPoint("LEFT", row, "LEFT", thumbR, 0)
		track:SetPoint("RIGHT", row, "RIGHT", -thumbR, 0)
	else
		minL = UI.FS(row, "ends", Text.Description)
		minL:SetText(tostring(minV)); minL:SetWidth(M.sliderEndW); minL:SetJustifyH("RIGHT")
		minL:SetPoint("LEFT", row, "LEFT", 0, 0)
		maxL = UI.FS(row, "ends", Text.Description)
		maxL:SetText(tostring(maxV)); maxL:SetWidth(M.sliderEndW); maxL:SetJustifyH("LEFT")
		maxL:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		track:SetPoint("LEFT", minL, "RIGHT", M.sliderEndPad, 0)
		track:SetPoint("RIGHT", maxL, "LEFT", -M.sliderEndPad, 0)
	end
	track:EnableMouse(true)

	-- Track + fill as tiny pills (rounded ends, XS scale). The gold fill's right
	-- cap hides under the thumb disc; min width 6 keeps the 3px cap slices valid.
	-- The "-h4" baked pill texture is reused at the ACTUAL frame height
	-- M.sliderBarH=5 (Florian 2026-07-22: was 4, a raw mockup-px copy missing
	-- the x1.25 physical-scale conversion). PillFill's own rule is "h must
	-- match the frame height exactly" (a new pill-fill-h5.tga would be the
	-- textbook fix), but a 4->5px vertical stretch of a flat, detail-less pill
	-- is visually imperceptible -- not worth a new baked asset for 1px. Revisit
	-- if sliderBarH moves further away from 4.
	-- Re-enable pixel-grid snapping on the two bars (Florian 2026-07-22): PillFill
	-- goes through markRound, which SetSnapToPixelGrid(false) so ROUNDED CORNERS
	-- stay smooth. But a thin horizontal bar with snapping OFF renders a
	-- DIFFERENT apparent thickness depending on its sub-pixel Y position -- so the
	-- SAME slider looked thicker in a card high on the screen than in one lower
	-- down (both cards at different Y -> different half-pixel alignment). Snapping
	-- the bar's top/bottom edges to whole physical pixels makes the thickness
	-- IDENTICAL everywhere; the 3px pill caps lose a hair of curve smoothness,
	-- imperceptible at this size and worth it for uniform bars.
	local bg = UI.PillFill(track, Surface.Hover, "ARTWORK", 4)
	bg:ClearAllPoints()
	bg:SetSnapToPixelGrid(true)
	bg:SetHeight(M.sliderBarH)
	bg:SetPoint("LEFT", track, "LEFT", 0, 0)
	bg:SetPoint("RIGHT", track, "RIGHT", 0, 0)

	local fillbar = UI.PillFill(track, Accent.color, "OVERLAY", 4)
	fillbar:ClearAllPoints()
	fillbar:SetSnapToPixelGrid(true)
	fillbar:SetHeight(M.sliderBarH)
	fillbar:SetPoint("LEFT", track, "LEFT", 0, 0)

	local thumb = CreateFrame("Frame", nil, track)
	thumb:SetSize(M.sliderThumb, M.sliderThumb)
	-- Round thumb (widget rounding pass): dark backing disc = the old 2px
	-- border, gold disc on top. Both sizes need a matching circle-<n> asset.
	local tBack = UI.Circle(thumb, { r = 0.10, g = 0.09, b = 0.08, a = 1 }, "ARTWORK", M.sliderThumb + 4)
	tBack:SetPoint("CENTER", thumb, "CENTER", 0, 0)
	local tt = UI.Circle(thumb, Accent.color, "OVERLAY", M.sliderThumb)
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
		UI:SetFont(box, "value", Text.Value) -- calm light, not pure white (brightens on focus)
		box:SetJustifyH("RIGHT")
		-- Bare value text (Florian 2026-07-22, Option A follow-up): the mockup
		-- shows the value flush with the track's right edge, no box/fill/border
		-- at all -- just brighter text than the label. The "this is typeable"
		-- affordance from 2026-07-14 now lives purely in the text brightening on
		-- focus (boxEdges stays nil -> OnEditFocusGained/Lost below already fall
		-- back to SetTextColor when there's no border to color).
	else
		box:SetSize(M.valueBoxW, M.valueBoxH)
		box:SetPoint("TOP", row, "BOTTOM", 0, -M.valueBoxGap)
		UI.RoundFill(box, Surface.Input, nil, nil, R_CTRL)
		boxEdges = UI.RoundBorder(box, Border.default, "OVERLAY", nil, R_CTRL)
		UI:SetFont(box, "value", Text.Primary)
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
		if boxEdges then for _, e in ipairs(boxEdges) do UI.SetColor(e, Accent.color) end
		else self:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b) end
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		typing = false
		if ns.EditMode then ns.EditMode._fieldFocused = false end
		if boxEdges then for _, e in ipairs(boxEdges) do UI.SetColor(e, Border.default) end
		else self:SetTextColor(Text.Value.r, Text.Value.g, Text.Value.b) end
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
	-- Force the value EditBox to actually re-rasterize. `box:SetText` with an
	-- UNCHANGED string is a no-op — so a box that first painted blank (built
	-- hidden / cold glyph cache) keeps the blank layout through visual()'s SetText
	-- and even through a tab-return re-show (report 2026-07-21, first Group-tab
	-- slider). Clear first so the set is always a real change; min/max labels are
	-- plain FontStrings that self-heal but re-set them here for free.
	local function repaint()
		visual(cur)
		if not typing then box:SetText(""); box:SetText(cur .. unit) end
		if minL then minL:SetText(tostring(minV)); maxL:SetText(tostring(maxV)) end
	end
	-- Track width is only known after the layout -> redraw on size change.
	track:SetScript("OnSizeChanged", function() visual(cur) end)
	-- Cold-start self-heal (report 2026-07-03): the very first build after a game
	-- start can run before the track width resolves — fill/thumb land at width 0
	-- and, if OnSizeChanged doesn't fire in that window, stay invisible. The value
	-- EditBox additionally keeps its blank first text layout even after the glyph
	-- cache warms. Repainting (force-re-set) whenever the slider becomes visible
	-- covers both — and keeps reused (cached) screens fresh for free.
	track:SetScript("OnShow", repaint)

	visual(cur)
	-- Cold-start glyph repaint (report 2026-07-14, QoL tab): when the slider is built
	-- into an ALREADY-VISIBLE parent (opening a tab on a cold client), OnShow never
	-- fires, so the box + min/max labels keep the blank layout the cold glyph cache
	-- produced on the first paint. One next-frame re-set isn't always enough for the
	-- VERY FIRST widget of a screen (the atlas can still be cold a frame later, and
	-- the track width may not have resolved yet — report 2026-07-21, first Group-tab
	-- slider missing entirely on cold start / reload). Retry over the first ~0.3s.
	for _, delay in ipairs({ 0, 0.05, 0.15, 0.3 }) do
		C_Timer.After(delay, repaint)
	end
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
		local barC = on and Accent.color or Text.Disabled
		UI.SetColor(fillbar, barC)
		UI.SetColor(tt, barC)
		-- Enabled colours must MATCH the creation-time compact styling (muted label
		-- + calm value), or a dependent slider (Name/HP cards call SetWidgetEnabled
		-- via refreshName/HP) would get re-brightened to white and diverge from the
		-- untoggled sliders (Size & arrangement) that never run this path (Florian
		-- 2026-07-22). Classic (non-compact) keeps its bright caption/value.
		local capC = on and (compact and Text.Description or Text.Primary) or Text.Description
		cap:SetTextColor(capC.r, capC.g, capC.b)
		local valC = on and (compact and Text.Value or Text.Primary) or Text.Description
		box:SetTextColor(valC.r, valC.g, valC.b)
		if minL then
			local endC = on and Text.Description or Text.Disabled
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
	if o.label and ns.Shell and ns.Shell.IndexOption then
		ns.Shell:IndexOption(o.label, f, "select", o.tooltip)
	end

	-- Header-Button
	local btn = CreateFrame("Button", nil, f)
	btn:SetHeight(CONTROL_H)
	btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, topY)
	btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, topY)
	UI.RoundFill(btn, Surface.Input, nil, nil, R_CTRL)
	local edges = UI.RoundBorder(btn, Border.default, "OVERLAY", nil, R_CTRL)
	f._control = btn -- anchor for "checkbox right next to the control" (vertically aligned)

	-- Dropdown chevron: Lucide chevron-down glyph (stage-3 glyph swap), tinted
	-- muted; SetSnapToPixelGrid off so the small TGA stays crisp at panel scale.
	local chev = btn:CreateTexture(nil, "OVERLAY")
	chev:SetSize(M.selectChevSize, M.selectChevSize)
	chev:SetPoint("RIGHT", btn, "RIGHT", -12, 0)
	chev:SetTexture(TEX .. "icon-chevron-down")
	chev:SetSnapToPixelGrid(false); chev:SetTexelSnappingBias(0)
	chev:SetVertexColor(Text.Description.r, Text.Description.g, Text.Description.b)

	local lbl = UI.FS(btn, "selectText", Text.Primary)
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
		if t then lbl:SetText(t); lbl:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
		else lbl:SetText(o.placeholder or T("Select")); lbl:SetTextColor(Text.Description.r, Text.Description.g, Text.Description.b) end
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
	UI.RoundFill(menu, Surface.Input) -- floating surface: subtly elevated inset (#161618); selection uses a check, hover an elementHover pill
	UI.RoundBorder(menu, Border.default, "OVERLAY") -- borderless-ish (Florian 2026-07-22: Border.hover read too boxy)

	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = menu end

	-- Forward declaration: the optional search field (o.search) is built further below,
	-- but closeMenu must already be able to clear its focus.
	local search, searchPH

	local function closeMenu()
		menu:Hide(); closer:Hide()
		if search then search:ClearFocus() end
		for _, e in ipairs(edges) do UI.SetColor(e, Border.default) end
	end
	closer:SetScript("OnClick", closeMenu)

	-- Menu rows = the sidebar-nav language 1:1 (Florian 2026-07-22): plain text on
	-- the dark menu when idle, a rounded inset pill on hover/selection + bright text.
	--  • selected -> elementHover pill (persistent, the brighter step)
	--  • hovered  -> element pill
	--  • idle     -> no pill, muted text
	-- No separators, no gold left bar (the pill carries both hover AND selection).
	local pad, rowH, gap = M.selectMenuPad, M.selectRowH, 0
	local function paintItem(item, hovered)
		local active = (item._val == cur)
		item._check:SetShown(active) -- selection = a right-aligned check (mockup ItemIndicator)
		if hovered then
			UI.SetColor(item._pill, Surface.Hover); item._pill:Show()
			item._txt:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
		else
			item._pill:Hide()
			local tc = active and Text.Primary or Text.Description -- selected stays bright, the rest quiet
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
		UI.RoundFill(search, Surface.Input, nil, nil, R_CTRL)
		UI.RoundBorder(search, Border.default, "OVERLAY", nil, R_CTRL)
		UI:SetFont(search, "value", Text.Primary) -- role, not an ad-hoc size
		search:SetTextInsets(10, 10, 0, 0)
		search:SetAutoFocus(false)
		searchPH = UI.FS(search, "label", Text.Description)
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
		-- Rounded inset hover pill (nav-item language), hidden when idle.
		local pill = UI.RoundFill(item, Surface.Input, "BACKGROUND", nil, RAD.md)
		pill:ClearAllPoints()
		pill:SetPoint("TOPLEFT", item, "TOPLEFT", M.menuItemPadX, -M.menuItemPadY)
		pill:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -M.menuItemPadX, M.menuItemPadY)
		pill:Hide()
		-- Right-aligned check = the SELECTION indicator (mockup ItemIndicator).
		local check = item:CreateTexture(nil, "OVERLAY")
		check:SetSize(M.selectCheckSize, M.selectCheckSize)
		check:SetPoint("RIGHT", item, "RIGHT", -(M.menuItemPadX + 10), 0)
		check:SetTexture(TEX .. "icon-check")
		check:SetSnapToPixelGrid(false); check:SetTexelSnappingBias(0)
		check:SetVertexColor(Accent.color.r, Accent.color.g, Accent.color.b)
		check:Hide()
		local itxt = UI.FS(item, "selectText", Text.Description)
		itxt:SetPoint("LEFT", item, "LEFT", M.menuItemPadX + 10, 0)
		itxt:SetText(op.label)
		item._pill, item._txt, item._val, item._check = pill, itxt, op.value, check
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
	local emptyFS = UI.FS(menu, "label", Text.Description)
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
		trackTex:SetAllPoints(sbTrack); UI.SetColor(trackTex, Surface.Input)
		local sth = CreateFrame("Frame", nil, sbTrack)
		sth:SetWidth(M.spScrollW); sth:EnableMouse(true)
		local sthTex = sth:CreateTexture(nil, "OVERLAY"); sthTex:SetAllPoints(sth)
		local function paintThumb(a) sthTex:SetColorTexture(Accent.color.r, Accent.color.g, Accent.color.b, a) end
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
		-- Open = no border-status change (Florian 2026-07-22): the bright Accent.color
		-- edge read too heavy/"fett" against the open list. The list itself is the
		-- open indicator; keep the trigger's quiet idle border.
		for _, e in ipairs(edges) do UI.SetColor(e, Border.default) end
		if search then search:SetFocus() end
	end

	btn:SetScript("OnClick", function()
		if menu:IsShown() then closeMenu() else openMenu() end
	end)
	btn:SetScript("OnEnter", function()
		if not menu:IsShown() then for _, e in ipairs(edges) do UI.SetColor(e, Border.hover) end end
		if o.tooltip then W.ShowTextTip(btn, o.label or o.tooltipTitle, o.tooltip) end
	end)
	btn:SetScript("OnLeave", function()
		if not menu:IsShown() then for _, e in ipairs(edges) do UI.SetColor(e, Border.default) end end
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
		-- Wheel-preview is gated behind SHIFT/CTRL (Florian 2026-07-22): a plain
		-- scroll over the dropdown kept silently changing the texture while paging
		-- past it. No modifier -> forward the wheel to the Shell scroll frame so the
		-- page scrolls as usual; hold Shift/Ctrl to cycle+preview textures.
		btn:SetScript("OnMouseWheel", function(_, delta)
			if menu:IsShown() then return end
			if IsShiftKeyDown() or IsControlKeyDown() then
				cycle(delta)
			else
				local sc = ns.Shell and ns.Shell._scroll
				local h = sc and sc:GetScript("OnMouseWheel")
				if h then h(sc, delta) end
			end
		end)
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
		bTxt = UI.FS(btn, "selectText", o.icon and Text.Primary or Text.Description)
		bTxt:SetPoint("LEFT", tile, "RIGHT", 10, 0)
		bTxt:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
		bTxt:SetJustifyH("LEFT"); bTxt:SetWordWrap(false)
		bTxt:SetText(o.text or T("+ Add"))
	else
		-- v2: trigger styled like a SECONDARY button (transparent, gold outline).
		bEdges = UI.RoundBorder(btn, UI.accentA(0.55), "OVERLAY", nil, R_CTRL)
		bTxt = UI.FS(btn, "btn", Accent.color)
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
	UI.RoundFill(menu, Surface.Input)
	UI.RoundBorder(menu, Border.hover, "OVERLAY")
	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = menu end

	local listH = M.spVisibleRows * M.spRowH
	menu:SetHeight(M.spPad * 2 + M.spSearchH + 8 + listH)

	-- Search field (typeahead) -------------------------------------------
	local search = CreateFrame("EditBox", nil, menu)
	search:SetHeight(M.spSearchH)
	search:SetPoint("TOPLEFT", menu, "TOPLEFT", M.spPad, -M.spPad)
	search:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -M.spPad, -M.spPad)
	UI.RoundFill(search, Surface.Input, nil, nil, R_CTRL)
	UI.RoundBorder(search, Border.default, "OVERLAY", nil, R_CTRL)
	UI:SetFont(search, "value", Text.Primary) -- role, not an ad-hoc size
	search:SetTextInsets(10, 10, 0, 0)
	search:SetAutoFocus(false)
	local ph = UI.FS(search, "label", Text.Description)
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

	local emptyFS = UI.FS(menu, "label", Text.Description)
	emptyFS:SetText(T("(no matches)"))
	emptyFS:SetPoint("TOP", search, "BOTTOM", 0, -16)
	emptyFS:Hide()

	-- Scrollbar (pattern from the Shell ScrollFrame: mouse wheel + draggable thumb).
	local sbTrack = CreateFrame("Frame", nil, menu)
	sbTrack:SetWidth(M.spScrollW)
	sbTrack:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -M.spPad, -(M.spPad + M.spSearchH + 8))
	sbTrack:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -M.spPad, M.spPad)
	local trackTex = sbTrack:CreateTexture(nil, "ARTWORK")
	trackTex:SetAllPoints(sbTrack); UI.SetColor(trackTex, Surface.Input)
	local thumb = CreateFrame("Frame", nil, sbTrack)
	thumb:SetWidth(M.spScrollW); thumb:EnableMouse(true)
	local thumbTex = thumb:CreateTexture(nil, "OVERLAY"); thumbTex:SetAllPoints(thumb)
	local function paintThumb(a) thumbTex:SetColorTexture(Accent.color.r, Accent.color.g, Accent.color.b, a) end
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
		UI.SetColor(sep, Border.faint)
		-- (No gold left bar here: in the unified dropdown language the bar is
		-- the SELECTION marker — a picker list has none. Florian 2026-07-05.)
		local icon = r:CreateTexture(nil, "ARTWORK")
		icon:SetSize(M.spellIcon, M.spellIcon)
		icon:SetPoint("LEFT", r, "LEFT", 8, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local name = UI.FS(r, "selectText", Text.Primary)
		name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
		name:SetPoint("RIGHT", r, "RIGHT", -8, 0)
		name:SetJustifyH("LEFT"); name:SetWordWrap(false)
		r._wash, r._icon, r._name = wash, icon, name
		r:SetScript("OnEnter", function(self2)
			-- v2: hover = elementHover (rows now sit on Surface.Input, so inkTint would be invisible)
			self2._wash:SetColorTexture(Surface.Hover.r, Surface.Hover.g, Surface.Hover.b, 1)
			self2._name:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
			W.ShowSpellTip(self2, self2._id) -- own Lumen tooltip
		end)
		r:SetScript("OnLeave", function(self2)
			local b = self2._base
			self2._wash:SetColorTexture(b[1], b[2], b[3], b[4])
			self2._name:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
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
				r._base = { Surface.Input.r, Surface.Input.g, Surface.Input.b, 1 }
				r._wash:SetColorTexture(r._base[1], r._base[2], r._base[3], r._base[4])
				r._name:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
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
		for _, e in ipairs(bEdges) do UI.SetColor(e, Border.default) end -- quiet open border (see W.Select openMenu)
		search:SetFocus()
	end
	closeMenu = function()
		menu:Hide(); closer:Hide()
		search:ClearFocus()
		for _, e in ipairs(bEdges) do UI.SetColor(e, UI.accentA(0.55)) end
	end
	closer:SetScript("OnClick", closeMenu)

	btn:SetScript("OnClick", function() if menu:IsShown() then closeMenu() else openMenu() end end)
	btn:SetScript("OnEnter", function()
		if not menu:IsShown() then for _, e in ipairs(bEdges) do UI.SetColor(e, Accent.color) end end
		bTxt:SetTextColor(Accent.hover.r, Accent.hover.g, Accent.hover.b)
	end)
	btn:SetScript("OnLeave", function()
		if not menu:IsShown() then for _, e in ipairs(bEdges) do UI.SetColor(e, UI.accentA(0.55)) end end
		bTxt:SetTextColor(Accent.color.r, Accent.color.g, Accent.color.b)
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
	UI.RoundFill(card, Surface.Input, nil, nil, RAD.xl) -- modal dialog = XL
	UI.RoundBorder(card, Border.hover, "OVERLAY", nil, RAD.xl) -- v2: neutral popover border
	local accent = card:CreateTexture(nil, "OVERLAY") -- gold accent on top (signature)
	accent:SetHeight(3)
	-- Inset by the corner radius: the straight bar stops where the curve starts.
	accent:SetPoint("TOPLEFT", card, "TOPLEFT", RAD.xl, 0)
	accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RAD.xl, 0)
	UI.SetColor(accent, Text.Primary) -- v2: signature accent = brand gold (C1)

	local title = UI.FS(card, "sectionHead", Text.Primary)
	title:SetPoint("TOPLEFT", card, "TOPLEFT", M.confirmPad, -M.confirmPad)
	title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.confirmPad, -M.confirmPad)
	title:SetJustifyH("LEFT")

	local body = UI.FS(card, "hint", Text.Secondary)
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
	UI.RoundFill(card, Surface.Input, nil, nil, RAD.xl) -- modal dialog = XL
	UI.RoundBorder(card, Border.hover, "OVERLAY", nil, RAD.xl) -- v2: neutral popover border
	local accent = card:CreateTexture(nil, "OVERLAY")
	accent:SetHeight(3)
	accent:SetPoint("TOPLEFT", card, "TOPLEFT", RAD.xl, 0)
	accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RAD.xl, 0)
	UI.SetColor(accent, Text.Primary) -- v2: signature accent = brand gold (C1)

	local y = -pad - 6

	local title = UI.FS(card, "sectionHead", Text.Primary)
	title:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
	title:SetText(T("Import profile"))
	y = y - 36

	-- Profile name (for "Create profile"; "Overwrite current" ignores it).
	local nameIn = W.TextInput(card, { label = T("Profile name"), placeholder = T("Name for new profile …") })
	nameIn:ClearAllPoints()
	nameIn:SetPoint("TOPLEFT", card, "TOPLEFT", pad, y)
	nameIn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, y)
	y = y - (M.controlH + M.fieldGap) - 18

	local lbl = UI.FS(card, "fieldLabel", Text.Primary)
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
	UI.RoundFill(tip, Surface.Window) -- darker than the popover -> clearer tooltip contrast
	UI.RoundBorder(tip, Border.hover, "OVERLAY") -- v2: neutral popover border (no gold top accent — Florian 2026-07-05)

	local icon = tip:CreateTexture(nil, "ARTWORK")
	icon:SetSize(M.tipIcon, M.tipIcon)
	icon:SetPoint("TOPLEFT", tip, "TOPLEFT", M.tipPad, -M.tipPad)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = UI.FS(tip, "tipTitle", Text.Primary)
	title:SetJustifyH("LEFT"); title:SetJustifyV("MIDDLE")

	local body = UI.FS(tip, "tipBody", Text.Secondary)
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
	-- Same-strata rivals: the Edit Mode flyout/toolbar also live on TOOLTIP strata
	-- and are toplevel (every click raises their frame level). Raise() alone is
	-- unreliable here — the tip's new rect isn't resolved yet at this point, so
	-- overlap detection can miss. A fixed high level always wins: the rivals only
	-- get raised above frames they overlap while those are SHOWN, and the tip is
	-- hidden whenever they are clicked.
	t.tip:SetFrameLevel(9000)
	t.tip:Show()
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
	b._searchTip = o.tooltip -- settings search indexes tooltip text too (W.OptionRow reads this)
	b:SetHeight(BOX)

	local box = CreateFrame("Frame", nil, b)
	box:SetSize(BOX, BOX)
	box:SetPoint("LEFT", b, "LEFT", 0, 0)
	local boxbg = UI.RoundFill(box, CLEAR, "BACKGROUND", nil, RAD.xs)
	local edges = UI.RoundBorder(box, Border.hover, "OVERLAY", nil, RAD.xs)

	-- Checkmark: our own Lucide check glyph (shared with the dropdown selection
	-- indicator — Florian 2026-07-22, replacing Blizzard's UI-CheckBox-Check).
	-- Tinted dark (Text.OnAccent) so it reads on the light-accent box when checked.
	local check = box:CreateTexture(nil, "OVERLAY")
	check:SetTexture(TEX .. "icon-check")
	check:SetSnapToPixelGrid(false); check:SetTexelSnappingBias(0)
	check:SetVertexColor(Text.OnAccent.r, Text.OnAccent.g, Text.OnAccent.b, 1)
	check:SetSize(BOX - 4, BOX - 4)
	check:SetPoint("CENTER", box, "CENTER", 0, 0)

	local lbl = UI.FS(b, "checkLabel", Text.Secondary)
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
			UI.SetColor(boxbg, Accent.color)
			for _, e in ipairs(edges) do UI.SetColor(e, Accent.color) end
			check:Show()
		else
			UI.SetColor(boxbg, CLEAR)
			for _, e in ipairs(edges) do UI.SetColor(e, Border.hover) end
			check:Hide()
		end
	end
	apply(val)

	b:SetScript("OnEnter", function()
		if not val then for _, e in ipairs(edges) do UI.SetColor(e, Accent.color) end end
		lbl:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
		-- Labelless boxes (stacked option rows) pass the row label as tooltipTitle.
		if o.tooltip then W.ShowTextTip(b, o.tooltipTitle or o.label, o.tooltip) end
	end)
	b:SetScript("OnLeave", function()
		if not val then for _, e in ipairs(edges) do UI.SetColor(e, Border.hover) end end
		lbl:SetTextColor(Text.Secondary.r, Text.Secondary.g, Text.Secondary.b)
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
--  Switch — rounded CAPSULE on/off toggle (pill track + circular knob that
--  slides right when on). Reusable for any boolean. o = { get, set }.
--  v3 (2026-07-22): back to a fully-round switch (Florian) — pill-<h> track +
--  circle-<h-2pad> knob. The knob INVERTS with state so it stays visible either
--  way: OFF = light knob on the dark track, ON = dark knob on the light-accent
--  track (a light knob on the light track would vanish — the cost of a pure-
--  light accent on filled controls, solved by inverting the knob).
-- ---------------------------------------------------------------------------
function W.Switch(parent, o)
	local b = CreateFrame("Button", nil, parent)
	b._searchTip = o.tooltip -- settings search indexes tooltip text too (W.OptionRow reads this)
	-- o.small: field/header variant (card grid system — label-on-top cells and
	-- collapsible-header master toggles).
	local swH = o.small and M.switchSmallH or M.switchH
	b:SetSize(o.small and M.switchSmallW or M.switchW, swH)
	local track = UI.PillFill(b, Surface.Input, "BACKGROUND", swH)
	-- The pill-fill traces the FULL radius (~h/2) to the bounding box, but the
	-- pill-edge ring sits on a 1px-inset path (radius-1). So the bright ON fill
	-- overhangs the ring by ~1px at the caps and reads squarer/larger than the
	-- OFF state (which shows only the inset ring). Inset the fill 1px so its curve
	-- lands ON the ring = both states share the exact same rounded outline
	-- (Florian 2026-07-22; OFF fill is dark-on-dark so the inset is invisible there).
	track:ClearAllPoints()
	track:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	track:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
	local edges = UI.PillBorder(b, Border.hover, "OVERLAY", swH)
	local pad = M.switchKnobPad
	local kS = swH - pad * 2
	local knob = UI.Circle(b, Text.Secondary, "OVERLAY", kS)

	local val = (o.get and o.get()) or false
	local function apply(on)
		knob:ClearAllPoints()
		if on then
			UI.SetColor(track, Accent.switchOn) -- softened light (anti-bloom, matches OFF's size/feel)
			for _, e in ipairs(edges) do UI.SetColor(e, Accent.switchOn) end
			knob:SetPoint("RIGHT", b, "RIGHT", -pad, 0)
			UI.SetColor(knob, Surface.Window) -- dark knob on the light track
		else
			UI.SetColor(track, Surface.Input)
			for _, e in ipairs(edges) do UI.SetColor(e, Border.hover) end
			knob:SetPoint("LEFT", b, "LEFT", pad, 0)
			UI.SetColor(knob, Text.Secondary) -- light knob on the dark track
		end
	end
	apply(val)

	b:SetScript("OnEnter", function() if not val then for _, e in ipairs(edges) do UI.SetColor(e, Accent.color) end end
		if o.tooltip then W.ShowTextTip(b, o.tooltip) end end)
	b:SetScript("OnLeave", function() if not val then for _, e in ipairs(edges) do UI.SetColor(e, Border.hover) end end
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

	local cellH = o.cellH or S.tabH -- 1:1 with the tab bar (Florian 2026-07-22): same height + pill + glow
	local topY = 0
	if o.label then
		local _, yo = fieldLabel(f, o.label); topY = yo
		f:SetHeight(cellH - topY)
	else
		f:SetHeight(cellH)
	end
	-- Settings search: like the slider and the select, a labelled segment carries
	-- its own label (it sits in a FieldRow cell, not a W.OptionRow) and so has to
	-- register itself — otherwise the mode switches (HP display, outline, dispel,
	-- aggro, fill colour, frame font) stay unfindable by search.
	if o.label and ns.Shell and ns.Shell.IndexOption then
		ns.Shell:IndexOption(o.label, f, "segment", o.tooltip)
	end

	-- Strip backing + a sliding translucent PILL for the active option (tab style,
	-- Florian 2026-07-22): same "switch between mutually-exclusive options" logic as
	-- the tabs, and it takes the solid-white active cell out of the picture. §9-safe:
	-- UI.slideTo is a short self-terminating tween (shared with the Shell tabs), not
	-- a per-frame poll.
	local hug = o.hug -- content-width strip (like the tabs), not stretched to fill
	local bar = CreateFrame("Frame", nil, f)
	bar:SetHeight(cellH)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, topY)
	if not hug then bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, topY) end -- hug sets its own width
	-- Rounded RECTANGLE, not a capsule (Florian 2026-07-29): the capsule pulled a
	-- lot of attention and sat apart from the dropdowns / inputs / cards, which
	-- are all softly-rounded rectangles. Same radius as a control face.
	UI.RoundFill(bar, Surface.Input, "BACKGROUND", nil, R_CTRL)
	UI.RoundBorder(bar, Border.default, "OVERLAY", nil, R_CTRL)
	f._control = bar

	-- Sliding indicator: inset by tabStripPad, rounded a step tighter than the
	-- strip so the two curves nest instead of fighting. NO glow — the tabs'
	-- underglow read too heavy on the smaller inline segments (Florian 2026-07-22).
	local pad = S.tabStripPad
	local slider = CreateFrame("Frame", nil, bar)
	slider:SetFrameLevel(bar:GetFrameLevel() + 1) -- above the strip, below the cell text
	slider._ref = bar
	UI.RoundFill(slider, Accent.wash, "ARTWORK", nil, UI.RADIUS.sm)
	slider:Hide()

	-- Not `(get() or value)` — get() may legitimately return `false` (e.g. inside/
	-- outside with value=false as default "inside"); `or` would swallow it. Check nil.
	local cur = o.get and o.get()
	if cur == nil then cur = o.value end
	local cells = {}

	-- Slide the pill onto the active cell. Geometry resolves only after layout/show,
	-- so callers retry from OnSizeChanged + OnShow (like the tab indicator).
	local function positionSlider(animate)
		local active
		for _, c in ipairs(cells) do if c._val == cur then active = c; break end end
		if not active then slider:Hide(); return end
		local ox, oy, w, h = UI.itemRectIn(active, bar)
		if not ox then return end
		UI.slideTo(slider, ox + pad, oy - pad, w - pad * 2, h - pad * 2, animate)
	end
	local function paint(animate)
		for _, c in ipairs(cells) do
			local col = (c._val == cur) and Text.Primary or Text.Description
			c._txt:SetTextColor(col.r, col.g, col.b)
		end
		positionSlider(animate)
	end

	for i, op in ipairs(opts) do
		local cell = CreateFrame("Button", nil, bar)
		cell:SetFrameLevel(bar:GetFrameLevel() + 2) -- text draws above the sliding pill
		local txt = UI.FS(cell, "selectText", Text.Description)
		txt:SetPoint("CENTER", cell, "CENTER", 0, 0)
		txt:SetText(op.label); txt:SetWordWrap(false)
		cell._txt, cell._val = txt, op.value
		cell:SetScript("OnEnter", function()
			if cell._val ~= cur then txt:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b) end
			-- Tip anchors to the bar (not the cell) so it stays put across cells.
			if o.tooltip then W.ShowTextTip(bar, o.label, o.tooltip) end
		end)
		cell:SetScript("OnLeave", function()
			if cell._val ~= cur then txt:SetTextColor(Text.Description.r, Text.Description.g, Text.Description.b) end
			if o.tooltip then W.HideTip() end
		end)
		cell:SetScript("OnClick", function()
			if cur == cell._val then return end
			cur = cell._val; paint(true)
			if o.set then o.set(cur) end
		end)
		cells[i] = cell
	end

	-- Layout: hug = each cell as wide as its text + padding (content-width strip,
	-- like the tabs — left-aligned, never over-stretched); default = equal-width
	-- cells across the field cell. Both snap the pill once widths resolve (text /
	-- bar width are 0 at build time, so hug retries on a few short timers + OnShow).
	if hug then
		local function fitHug()
			local x = 0
			for _, c in ipairs(cells) do
				local tw = math.ceil(c._txt:GetStringWidth() or 0)
				if tw <= 0 then return end -- font not measured yet; a later retry catches it
				local cw = tw + M.segHugPad * 2
				c:ClearAllPoints()
				c:SetPoint("TOP", bar, "TOP", 0, 0)
				c:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
				c:SetPoint("LEFT", bar, "LEFT", x, 0)
				c:SetWidth(cw)
				x = x + cw
			end
			bar:SetWidth(x)
			positionSlider(false)
		end
		fitHug()
		for _, dl in ipairs({ 0, 0.05, 0.15, 0.3 }) do C_Timer.After(dl, fitHug) end
		bar:HookScript("OnShow", fitHug)
	else
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
			positionSlider(false)
		end)
		bar:HookScript("OnShow", function() positionSlider(false) end) -- build-time rects were nil
	end
	paint(false)

	f.SetValueExternal = function(_, v) cur = v; paint(true) end
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
	local tex, color, shown = {}, Border.hover, false
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
	dash.SetColor(Border.hover)
	dash.Show()
	local fs = UI.FS(f, "hint", Text.Description)
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
	UI.RoundFill(btn, Surface.Input, nil, nil, UI.ROUND_R_CTRL)
	-- Border per state (Option c: dashed dropped for rounding consistency):
	-- solid gold rounded ring when a key is set (or while capturing), a thin
	-- faint rounded ring when unbound.
	local solid = UI.RoundBorder(btn, Accent.color, "OVERLAY", nil, UI.ROUND_R_CTRL)
	local faint = UI.RoundBorder(btn, Border.default, "OVERLAY", nil, UI.ROUND_R_CTRL)
	f._control = btn

	local lbl = UI.FS(btn, "selectText", Text.Primary)
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
		if listening then -- capturing a key: bright ring as live feedback (transient)
			for _, e in ipairs(solid) do UI.SetColor(e, Accent.color); e:Show() end
			for _, e in ipairs(faint) do e:Hide() end
		elseif cur ~= "" then -- bound: subtle ring (Florian 2026-07-22: the bright white
			-- ring read too heavy on the input fields); the bright label already signals "set".
			for _, e in ipairs(solid) do UI.SetColor(e, Border.hover); e:Show() end
			for _, e in ipairs(faint) do e:Hide() end
		else
			for _, e in ipairs(solid) do e:Hide() end
			for _, e in ipairs(faint) do UI.SetColor(e, Border.default); e:Show() end
		end
	end
	local function refresh()
		if listening then
			lbl:SetText(T("Press a key …"))
			lbl:SetTextColor(Accent.hover.r, Accent.hover.g, Accent.hover.b)
		else
			lbl:SetText(fmt(cur))
			local col = (cur ~= "") and Text.Primary or Text.Description
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
	-- Hover keeps the border SUBTLE (Florian 2026-07-22): a bright accent hover
	-- left a bound field stuck with a thick white ring until /reload
	-- (OnLeave reset it to bright, overriding setBorder's Border.hover). Bound stays Border.hover;
	-- unbound gets a faint Border.default->Border.hover hover step and back.
	btn:SetScript("OnEnter", function()
		if listening then return end
		if cur ~= "" then for _, e in ipairs(solid) do UI.SetColor(e, Border.hover) end
		else for _, e in ipairs(faint) do UI.SetColor(e, Border.hover) end end
	end)
	btn:SetScript("OnLeave", function()
		if listening then return end
		if cur ~= "" then for _, e in ipairs(solid) do UI.SetColor(e, Border.hover) end
		else for _, e in ipairs(faint) do UI.SetColor(e, Border.default) end end
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
	-- Accent hover kept subtle (mono: hovering used to flash white here).
	local hbg = btn:CreateTexture(nil, "BACKGROUND")
	hbg:SetPoint("TOPLEFT", btn, "TOPLEFT", -M.iconBtnHoverPad, M.iconBtnHoverPad)
	hbg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", M.iconBtnHoverPad, -M.iconBtnHoverPad)
	hbg:SetColorTexture(Surface.Hover.r, Surface.Hover.g, Surface.Hover.b, 1)
	hbg:Hide()
	icon:SetVertexColor(Accent.color.r, Accent.color.g, Accent.color.b, 1)
	btn:SetScript("OnEnter", function() hbg:Show(); icon:SetVertexColor(Accent.hover.r, Accent.hover.g, Accent.hover.b, 1) end)
	btn:SetScript("OnLeave", function() hbg:Hide(); icon:SetVertexColor(Accent.color.r, Accent.color.g, Accent.color.b, 1) end)

	local host = W._menuHost or parent
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:Hide()

	local pop = CreateFrame("Frame", nil, host)
	pop:SetFrameStrata("FULLSCREEN_DIALOG")
	pop:SetFrameLevel(closer:GetFrameLevel() + 10)
	pop:Hide()
	UI.RoundFill(pop, Surface.Input)
	UI.RoundBorder(pop, Border.hover, "OVERLAY")
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
			UI.SetColor(sep, Border.faint)
		end
		local rm = CreateFrame("Button", nil, pop)
		rm:SetHeight(rowH)
		placeTop(rm)
		rm:SetPoint("RIGHT", pop, "RIGHT", -pad, 0)
		local rtxt = UI.FS(rm, "checkLabel", Status.danger)
		rtxt:SetPoint("LEFT", rm, "LEFT", 0, 0)
		rtxt:SetText(o.removeText or T("Remove"))
		rm:SetScript("OnEnter", function() rtxt:SetTextColor(Status.dangerHover.r, Status.dangerHover.g, Status.dangerHover.b) end)
		rm:SetScript("OnLeave", function() rtxt:SetTextColor(Status.danger.r, Status.danger.g, Status.danger.b) end)
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
	UI.RoundFill(cp, Surface.Window, nil, nil, RAD.xl) -- modal-style picker = XL
	UI.RoundBorder(cp, Border.default, "OVERLAY", nil, RAD.xl) -- soft neutral (the accent border read too strong)

	-- Full-screen closer behind it (click outside = apply/close).
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:SetFrameLevel(cp:GetFrameLevel() - 1)
	cp._closer = closer

	local pad = M.cpPad
	local chip = math.floor((M.cpSVW - 8 * M.cpPresetGap) / 9) -- 9 quick-pick chips span the SV width
	local hueW = M.cpSVW - M.cpShuffle - M.cpGap
	cp:SetSize(pad * 2 + M.cpSVW,
		pad * 2 + chip + M.cpSVH + M.cpShuffle + M.cpPrevH + M.buttonH + 4 * M.cpGap)

	-- ---- Quick-pick strip (HeroUI-style presets across the top) ----
	local PICKER_PRESETS = { "EF4444", "F97316", "EAB308", "22C55E", "06B6D4", "3B82F6", "8B5CF6", "EC4899", "F43F5E" }
	local strip = CreateFrame("Frame", nil, cp)
	strip:SetPoint("TOPLEFT", cp, "TOPLEFT", pad, -pad)
	strip:SetSize(M.cpSVW, chip)
	for i, h in ipairs(PICKER_PRESETS) do
		local pc = UI.hex(h)
		local sc = CreateFrame("Button", nil, strip)
		sc:SetSize(chip, chip)
		sc:SetPoint("LEFT", strip, "LEFT", (i - 1) * (chip + M.cpPresetGap), 0)
		UI.RoundFill(sc, pc, "ARTWORK", nil, RAD.sm)
		UI.RoundBorder(sc, Border.hover, "OVERLAY", nil, RAD.sm)
		sc:SetScript("OnClick", function()
			cp._h, cp._s, cp._v = rgb2hsv(pc.r, pc.g, pc.b)
			cp._applyVisual(); cp._fireChange()
		end)
	end

	-- ---- SV field (saturation x, value y) ----
	local sv = CreateFrame("Frame", nil, cp)
	sv:SetSize(M.cpSVW, M.cpSVH)
	sv:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -M.cpGap)
	sv:EnableMouse(true)
	local svBase = sv:CreateTexture(nil, "BACKGROUND")     -- pure hue color
	svBase:SetAllPoints(sv)
	local svWhite = sv:CreateTexture(nil, "ARTWORK")       -- left white -> right clear (saturation)
	svWhite:SetAllPoints(sv); svWhite:SetColorTexture(1, 1, 1, 1)
	svWhite:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
	local svBlack = sv:CreateTexture(nil, "ARTWORK", nil, 1) -- bottom black -> top clear (value)
	svBlack:SetAllPoints(sv); svBlack:SetColorTexture(0, 0, 0, 1)
	svBlack:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))
	UI.Stroke(sv, Border.hover, 1, "OVERLAY")
	local svMark = CreateFrame("Frame", nil, sv)
	svMark:SetSize(M.cpMarker, M.cpMarker)
	UI.Stroke(svMark, { r = 1, g = 1, b = 1, a = 1 }, 2, "OVERLAY")

	-- ---- Hue slider (horizontal, 6 segments) + shuffle ----
	local hueRow = CreateFrame("Frame", nil, cp)
	hueRow:SetPoint("TOPLEFT", sv, "BOTTOMLEFT", 0, -M.cpGap)
	hueRow:SetSize(M.cpSVW, M.cpShuffle)
	local hue = CreateFrame("Frame", nil, hueRow)
	hue:SetSize(hueW, M.cpHueH)
	hue:SetPoint("LEFT", hueRow, "LEFT", 0, 0)
	hue:EnableMouse(true)
	local HUES = { {1,0,0}, {1,1,0}, {0,1,0}, {0,1,1}, {0,0,1}, {1,0,1}, {1,0,0} }
	local segW = hueW / 6
	for i = 1, 6 do
		local seg = hue:CreateTexture(nil, "ARTWORK")
		seg:SetColorTexture(1, 1, 1, 1)
		seg:SetPoint("TOPLEFT", hue, "TOPLEFT", (i - 1) * segW, 0)
		seg:SetPoint("BOTTOMLEFT", hue, "BOTTOMLEFT", (i - 1) * segW, 0)
		seg:SetWidth(segW)
		local a, c2 = HUES[i], HUES[i + 1]
		-- left = a (segment start), right = c2 -> min(left)=a, max(right)=c2
		seg:SetGradient("HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(c2[1], c2[2], c2[3], 1))
	end
	UI.Stroke(hue, Border.hover, 1, "OVERLAY")
	local hueMark = hue:CreateTexture(nil, "OVERLAY")
	hueMark:SetColorTexture(1, 1, 1, 1)
	hueMark:SetWidth(3)

	-- Randomize button (icon-reset = reroll) beside the hue slider.
	local shuffle = CreateFrame("Button", nil, hueRow)
	shuffle:SetSize(M.cpShuffle, M.cpShuffle)
	shuffle:SetPoint("RIGHT", hueRow, "RIGHT", 0, 0)
	UI.RoundFill(shuffle, Surface.Input, "BACKGROUND", nil, RAD.sm)
	local shEdges = UI.RoundBorder(shuffle, Border.hover, "OVERLAY", nil, RAD.sm)
	local shIcon = shuffle:CreateTexture(nil, "ARTWORK")
	shIcon:SetTexture(TEX .. "icon-reset")
	shIcon:SetSize(M.cpShuffle - 12, M.cpShuffle - 12)
	shIcon:SetPoint("CENTER", shuffle, "CENTER", 0, 0)
	shIcon:SetVertexColor(Text.Description.r, Text.Description.g, Text.Description.b)
	shuffle:SetScript("OnEnter", function()
		shIcon:SetVertexColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
		for _, e in ipairs(shEdges) do UI.SetColor(e, Accent.color) end
		W.ShowTextTip(shuffle, T("Random color"))
	end)
	shuffle:SetScript("OnLeave", function()
		shIcon:SetVertexColor(Text.Description.r, Text.Description.g, Text.Description.b)
		for _, e in ipairs(shEdges) do UI.SetColor(e, Border.hover) end
		W.HideTip()
	end)
	shuffle:SetScript("OnClick", function()
		cp._h = math.random()
		cp._s = 0.5 + math.random() * 0.5 -- 50-100% saturation
		cp._v = 0.4 + math.random() * 0.5 -- 40-90% value
		cp._applyVisual(); cp._fireChange()
	end)

	-- ---- Swatch + hex ----
	local preview = CreateFrame("Frame", nil, cp)
	preview:SetSize(M.cpPrevH, M.cpPrevH)
	preview:SetPoint("TOPLEFT", hueRow, "BOTTOMLEFT", 0, -M.cpGap)
	local prevTex = UI.RoundFill(preview, { r = 1, g = 1, b = 1, a = 1 }, "ARTWORK", nil, RAD.sm)
	UI.RoundBorder(preview, Border.hover, "OVERLAY", nil, RAD.sm)

	local hexBox = CreateFrame("EditBox", nil, cp)
	hexBox:SetSize(110, M.cpPrevH)
	hexBox:SetPoint("LEFT", preview, "RIGHT", M.cpGap, 0)
	UI.RoundFill(hexBox, Surface.Input, nil, nil, R_CTRL)
	UI.RoundBorder(hexBox, Border.default, "OVERLAY", nil, R_CTRL)
	UI:SetFont(hexBox, "value", Text.Primary)
	hexBox:SetJustifyH("CENTER"); hexBox:SetAutoFocus(false); hexBox:SetMaxLetters(6)
	hexBox:SetTextInsets(16, 6, 0, 0)
	local hexHash = UI.FS(hexBox, "value", Text.Description)
	hexHash:SetText("#"); hexHash:SetPoint("LEFT", hexBox, "LEFT", 7, 0)

	-- ---- Buttons ----
	-- Apply + cancel grouped at the bottom left, small fixed gap (cpBtnGap).
	local btnW = (M.cpSVW - M.cpBtnGap) / 2 -- two equal buttons fill the picker width (German labels overflowed auto-size)
	local okBtn = W.Button(cp, { text = T("Apply"), variant = "primary", width = btnW })
	okBtn:SetPoint("BOTTOMLEFT", cp, "BOTTOMLEFT", pad, pad)
	local cancelBtn = W.Button(cp, { text = T("Cancel"), variant = "ghost", width = btnW })
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
		hueMark:SetPoint("TOP", hue, "TOPLEFT", cp._h * hueW, 2)
		hueMark:SetPoint("BOTTOM", hue, "BOTTOMLEFT", cp._h * hueW, -2)
	end
	local function applyVisual(fromHex)
		local hr, hg, hb = hsv2rgb(cp._h, 1, 1)
		svBase:SetColorTexture(hr, hg, hb, 1)
		local r, g, b = curRGB()
		prevTex:SetVertexColor(r, g, b, 1) -- rounded swatch (white asset, tinted)
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
		local cx = GetCursorPosition()
		local sc = hue:GetEffectiveScale(); if not sc or sc == 0 then return end
		cx = cx / sc
		local left = hue:GetLeft(); if not left then return end
		cp._h = clamp((cx - left) / hueW, 0, 0.999999)
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
	-- Apply / click-outside = COMMIT: onChange was a live preview; fire onApply so
	-- the caller can do a full refresh (e.g. rebuild the current tab so its own
	-- accent widgets settle), then close.
	cp._fireApply = function() if cp._onApply then local r, g, b = curRGB(); cp._onApply(r, g, b) end end
	local function commit() cp._fireApply(); close() end
	okBtn:SetScript("OnClick", commit)
	cancelBtn:SetScript("OnClick", function()
		if cp._onCancel then cp._onCancel() end
		close()
	end)
	closer:SetScript("OnClick", commit)

	cp._applyVisual = applyVisual
	return cp
end

-- o = { r,g,b, anchor?, onChange(r,g,b), onCancel() }. Opens the singleton picker.
function W.OpenColorPicker(o)
	colorPicker = colorPicker or buildColorPicker()
	local cp = colorPicker
	-- The host may have changed since build (it shouldn't) — ensure the parent.
	cp._onChange, cp._onCancel, cp._onApply = o.onChange, o.onCancel, o.onApply
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
--  AccentPresets — a row of curated accent colour chips (Global tab). Clicking
--  one calls o.set(hex, col) (store + Shell:RefreshAccent) and rings the active
--  chip. A custom hue (step 6b) matches no preset, so no chip is ringed.
-- ---------------------------------------------------------------------------
function W.AccentPresets(parent, o)
	local size = M.switchSmallH
	local gap = UI.S.s3
	local f = CreateFrame("Frame", nil, parent)
	local tiles = {}
	local cFill, cRing, cPlus -- custom tile (built after the presets, forward-declared)
	local function refresh()
		local cur = (o.get() or ""):upper()
		local anyMatch = false
		for _, t in ipairs(tiles) do
			local on = t._hex == cur
			if on then anyMatch = true end
			for _, e in ipairs(t._ring) do UI.SetColor(e, on and Text.Primary or Border.hover) end
		end
		-- Custom tile: neutral "+" when a preset is active; when a custom hue is
		-- live (no preset matches) it fills with that colour and takes the ring.
		if anyMatch then
			UI.SetColor(cFill, Surface.Input); cPlus:Show()
			for _, e in ipairs(cRing) do UI.SetColor(e, Border.hover) end
		else
			local c = UI.hex(cur ~= "" and cur or "F4F4F6")
			cFill:SetVertexColor(c.r, c.g, c.b, 1); cPlus:Hide()
			for _, e in ipairs(cRing) do UI.SetColor(e, Text.Primary) end
		end
	end
	local x = 0
	for i, p in ipairs(UI.ACCENT_PRESETS) do
		local t = CreateFrame("Button", nil, f)
		t:SetSize(size, size)
		t:SetPoint("LEFT", f, "LEFT", x, 0)
		UI.RoundFill(t, p.col, "ARTWORK", nil, RAD.sm)
		t._ring = UI.RoundBorder(t, Border.hover, "OVERLAY", nil, RAD.sm)
		t._hex = p.hex:upper()
		t:SetScript("OnClick", function() o.set(p.hex, p.col); refresh() end)
		if p.name then
			t:SetScript("OnEnter", function() W.ShowTextTip(t, p.name) end)
			t:SetScript("OnLeave", function() W.HideTip() end)
		end
		tiles[i] = t
		x = x + size + gap
	end
	-- Custom tile: opens the HSV picker. onChange is a LIVE preview (o.set stores +
	-- Shell:RefreshAccent every drag frame); Cancel reverts to the colour on open.
	local custom = CreateFrame("Button", nil, f)
	custom:SetSize(size, size)
	custom:SetPoint("LEFT", f, "LEFT", x, 0)
	cFill = UI.RoundFill(custom, Surface.Input, "ARTWORK", nil, RAD.sm)
	cRing = UI.RoundBorder(custom, Border.hover, "OVERLAY", nil, RAD.sm)
	cPlus = UI.FS(custom, "value", Text.Description)
	cPlus:SetText("+"); cPlus:SetPoint("CENTER", custom, "CENTER", 0, 0)
	custom:SetScript("OnClick", function()
		local origHex = (o.get() or "F4F4F6"):upper()
		local oc = UI.hex(origHex)
		W.OpenColorPicker({
			r = oc.r, g = oc.g, b = oc.b, anchor = custom,
			-- Live drag = chrome-only preview (true); commit/cancel = full refresh so
			-- the current tab rebuilds and its own accent widgets settle.
			onChange = function(r, g, b) o.set(toHex(r, g, b), { r = r, g = g, b = b, a = 1 }, true); refresh() end,
			onApply  = function(r, g, b) o.set(toHex(r, g, b), { r = r, g = g, b = b, a = 1 }) end,
			onCancel = function() o.set(origHex, oc) end,
		})
	end)
	custom:SetScript("OnEnter", function() W.ShowTextTip(custom, T("Custom color")) end)
	custom:SetScript("OnLeave", function() W.HideTip() end)
	x = x + size + gap
	f:SetWidth(x - gap); f:SetHeight(size)
	f.Refresh = refresh
	refresh()
	return f
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
	local edges = UI.RoundBorder(box, Border.hover, "OVERLAY", nil, RAD.sm)

	-- Chip + optional label on the right (compact row); labelless chips are the
	-- stacked-option-row standard (the old label-on-top "field" mode is retired —
	-- design bible §8: swatches are 28px chips in option rows everywhere).
	b:SetHeight(BOX)
	box:SetPoint("LEFT", b, "LEFT", 0, 0)
	local lbl = UI.FS(b, "checkLabel", Text.Secondary)
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
		for _, e in ipairs(edges) do UI.SetColor(e, Accent.color) end
		lbl:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
	end)
	b:SetScript("OnLeave", function()
		for _, e in ipairs(edges) do UI.SetColor(e, Border.hover) end
		lbl:SetTextColor(Text.Secondary.r, Text.Secondary.g, Text.Secondary.b)
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
	local fs = UI.FS(f, "hint", Text.Description)
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
	UI.RoundFill(box, Surface.Input, nil, nil, R_CTRL)
	UI.RoundBorder(box, Border.default, "OVERLAY", nil, R_CTRL) -- subtle edge, matches the dropdown (Florian 2026-07-22: Border.hover read too strong)
	-- Same text role as the dropdown headers (selectText): inputs and selects
	-- sit side by side in rows (Profile tab) and must read as one control family.
	UI:SetFont(box, "selectText", Text.Primary)
	box:SetTextInsets(10, 10, 0, 0)
	box:SetAutoFocus(false)
	if o.get then box:SetText(o.get() or "") end

	local ph
	if o.placeholder then
		ph = UI.FS(box, "selectText", Text.Description)
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
	UI.RoundFill(f, Surface.Input, nil, nil, R_CTRL)
	UI.RoundBorder(f, Border.hover, "OVERLAY", nil, R_CTRL)

	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
	sf:EnableMouseWheel(true)

	local edit = CreateFrame("EditBox", nil, sf)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	UI:SetFont(edit, "value", Text.Primary) -- role, not an ad-hoc size
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
		ph = UI.FS(edit, "label", Text.Description)
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
		-- Softened light (switchOn), not pure accent: a pure-white fill blooms
		-- (irradiation) and read TALLER/fatter than the outlined dropdown of the
		-- same height (Florian 2026-07-22). Hover steps up to the full accent.
		bg = Accent.switchOn, bgHover = Accent.color,
		txt = Text.OnAccent, txtHover = Text.OnAccent,
		line = Accent.switchOn, lineHover = Accent.color, pad = 26, font = UI.FONT.bold,
	},
	-- NOTE: these accent references FREEZE to the mono default at file load and are
	-- NOT refreshed by W.RefreshButtonVariants -> secondary stays neutral white in
	-- every theme (only PRIMARY follows the accent, Florian 2026-07-23).
	secondary = {
		bg = nil, bgHover = UI.accentA(0.08),
		txt = Accent.color, txtHover = Accent.hover,
		-- Outline alpha lowered from .55 (Florian 2026-07-29: the ring read as a
		-- heavy border once the buttons stopped being capsules). The ring asset
		-- has a fixed 2px stroke, so ALPHA is the way to make an edge thinner —
		-- the same lever UI.Border uses.
		line = UI.accentA(0.30), lineHover = UI.accentA(0.65), pad = 22, font = UI.FONT.semibold,
	},
	neutral = {
		bg = Surface.Input, bgHover = Surface.Hover,
		txt = Text.Primary, txtHover = Text.Primary,
		line = Border.hover, lineHover = Border.hover, pad = 22, font = UI.FONT.medium,
	},
	danger = {
		bg = nil, bgHover = UI.dangerA(0.10),
		txt = Status.danger, txtHover = Status.dangerHover,
		line = UI.dangerA(0.30), lineHover = UI.dangerA(0.65), pad = 22, font = UI.FONT.semibold,
	},
}
BTN_VARIANTS.ghost = BTN_VARIANTS.neutral

-- The accent-derived button colours are copied BY VALUE at file load; SetAccent
-- REPLACES UI.Accent.*, so those copies go stale (a rebuilt button would keep the
-- old accent, while sliders/switches update because they read Accent.* directly
-- at build). Re-point ONLY the PRIMARY variant at the live accent on every accent
-- change (SetAccent calls this), before any button rebuilds. The SECONDARY (and
-- danger) variants deliberately keep their load-time (mono = white) colours so
-- they stay neutral in every theme — only the primary action carries the accent
-- (Florian 2026-07-23: an accent-only-on-primary hierarchy; a coloured secondary
-- read as accent-everywhere).
function W.RefreshButtonVariants()
	local p = BTN_VARIANTS.primary
	p.bg, p.bgHover, p.line, p.lineHover = Accent.switchOn, Accent.color, Accent.switchOn, Accent.color
end

function W.Button(parent, o)
	local variant = o.variant or "primary"
	local v = BTN_VARIANTS[variant]
	local b = CreateFrame("Button", nil, parent)
	-- o.height: free now that the face is a rounded rectangle (the old capsule
	-- only existed at the heights that had pill assets).
	b:SetHeight(o.height or M.buttonH)

	-- Rounded RECTANGLE (Florian 2026-07-29, replacing the 2026-07-22 pill): the
	-- capsules read as their own form language next to the rounded-rectangle
	-- dropdowns, inputs and cards. Same control-face radius as those.
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
	-- fall back to the role font (btn = semibold, renders umlauts reliably).
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
		local txt = UI.FS(btn, "selectText", o.icon and Text.Secondary or Text.Description)
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
	UI.RoundFill(menu, Surface.Input)
	UI.RoundBorder(menu, Border.hover, "OVERLAY")
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
		local itxt = UI.FS(item, "selectText", Text.Primary)
		itxt:SetPoint("LEFT", item, "LEFT", 10, 0)
		itxt:SetText(op.label)
		item:SetScript("OnEnter", function()
			wash:SetColorTexture(Surface.Hover.r, Surface.Hover.g, Surface.Hover.b, 1) -- lift off the Surface.Input menu bg
			itxt:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
		end)
		item:SetScript("OnLeave", function()
			wash:SetColorTexture(0, 0, 0, 0)
			itxt:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
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
		CreateColor(Surface.Scrim.r, Surface.Scrim.g, Surface.Scrim.b, 1),
		CreateColor(Surface.Input.r, Surface.Input.g, Surface.Input.b, 1))
	UI.Stroke(f, Border.default, 1)
	local lt = UI.FS(f, "groupTitle", Text.Primary)
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
	UI.RoundFill(c, Surface.Card) -- group box = LG (card default)
	UI.RoundBorder(c, Border.default)
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
	-- Rounded card (default card radius). o.attached: the caller places the body card FLUSH
	-- below when open -> only the top corners round (the body card uses
	-- round = "bottom"), so header + body read as one rounded object.
	local shape = (o.open and o.attached) and "top" or nil
	UI.RoundFill(f, Surface.Card, nil, shape)
	UI.RoundBorder(f, Border.default, "OVERLAY", shape)

	local title = UI.FS(f, "sectionHead", Text.Primary)
	title:SetPoint("LEFT", f, "LEFT", M.sectionPad, 0)
	title:SetText(o.title or "")

	-- Chevron: Lucide chevron-down when open, chevron-right when collapsed (gold).
	local chev = f:CreateTexture(nil, "OVERLAY")
	chev:SetSize(M.chevGlyph, M.chevGlyph)
	chev:SetPoint("RIGHT", f, "RIGHT", -M.sectionTitleX, 0)
	chev:SetTexture(TEX .. (o.open and "icon-chevron-down" or "icon-chevron-right"))
	chev:SetSnapToPixelGrid(false); chev:SetTexelSnappingBias(0)
	chev:SetVertexColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)

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
		local sum = UI.FS(f, "value", Text.Description)
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
		local sub = UI.FS(f, "caption", Text.Description)
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
			local col = hovered and Accent.hover or (on and Accent.color or Text.Description)
			g:SetVertexColor(col.r, col.g, col.b)
		end
		paintEye()
		eb:SetScript("OnEnter", function() hovered = true; paintEye()
			if o.eye.tip then W.ShowTextTip(eb, o.eye.tip, nil, "TOP") end end)
		eb:SetScript("OnLeave", function() hovered = false; paintEye(); W.HideTip() end)
		eb:SetScript("OnClick", function() o.eye.set(not o.eye.get()); paintEye() end)
		-- Central eye-popover sync: register the paint on the screen so external
		-- toggles (dock popover / same key on another tab) repaint this glyph too
		-- (Shell:RepaintEyes + cache re-show). Mirrors makeBox's card eye.
		local scr = ns.Shell and ns.Shell._screen
		if scr then
			scr._eyePaints = scr._eyePaints or {}
			scr._eyePaints[#scr._eyePaints + 1] = paintEye
		end
	end

	-- Hover wash (subtle, like the tracking rows) — rounded like the card, so
	-- the wash doesn't poke out of the corners.
	local hov = UI.RoundFill(f, Surface.Input, "BORDER", shape); hov:SetAlpha(0)
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

	-- Hairline on top: separates the footer from the card content. Hidden by the
	-- card stacker when the boundary above already carries a line (a preceding
	-- OptionRow's bottom line), so the two don't read as a double divider.
	local sep = f:CreateTexture(nil, "OVERLAY")
	PixelUtil.SetHeight(sep, 1)
	sep:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	UI.SetColor(sep, Border.faint)
	f._topLine = sep

	-- Chevron: Lucide chevron-up when open, chevron-right when closed (muted;
	-- brightens to gold on hover via paint()).
	local chev = f:CreateTexture(nil, "OVERLAY")
	chev:SetSize(M.chevGlyph, M.chevGlyph)
	chev:SetPoint("LEFT", f, "LEFT", 0, -1)
	chev:SetTexture(TEX .. (o.open and "icon-chevron-up" or "icon-chevron-right"))
	chev:SetSnapToPixelGrid(false); chev:SetTexelSnappingBias(0)
	local function paint(col) chev:SetVertexColor(col.r, col.g, col.b) end
	paint(Text.Description)

	local lbl = UI.FS(f, "value", Text.Description)
	lbl:SetPoint("LEFT", chev, "RIGHT", M.disclosureChevGap, -1)
	lbl:SetText(o.label or "")

	-- Contents preview while closed ("Typ-Farben, Text-Position …") — nothing
	-- becomes unfindable behind the fold.
	if o.hint and not o.open then
		local hint = UI.FS(f, "caption", Text.Description)
		hint:SetPoint("LEFT", lbl, "RIGHT", M.disclosureHintGap, 0)
		hint:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		hint:SetJustifyH("LEFT")
		hint:SetWordWrap(false)
		hint:SetText(o.hint)
	end

	f:SetScript("OnEnter", function()
		lbl:SetTextColor(Accent.hover.r, Accent.hover.g, Accent.hover.b)
		paint(Accent.hover)
	end)
	f:SetScript("OnLeave", function()
		lbl:SetTextColor(Text.Description.r, Text.Description.g, Text.Description.b)
		paint(Text.Description)
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
	bg:SetColorTexture(Surface.Card.r, Surface.Card.g, Surface.Card.b, 0.45)
	UI.Stroke(g, Border.default, 1)

	local title = UI.FS(g, "groupTitle", Text.Primary)
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
--  soft BOTTOM hairline, label LEFT, ONE compact control (switch / checkbox /
--  28px color chip — all switchSmallH tall) attached RIGHT via row:Attach().
--  All rows share one height (M.optionRowH) so nothing jumps inside a card;
--  SetWidgetEnabled greys the label together with the attached control.
--  Line at the BOTTOM, not the top (Florian 2026-07-22): a top line on the
--  first row doubled up with the card-header divider right above it; owning the
--  separator on the bottom means the first row has none (no double line under
--  the header) and the LAST row closes the group cleanly. Flush-stacked rows
--  keep every in-between separator at the same boundary as before.
-- ---------------------------------------------------------------------------
function W.OptionRow(parent, label)
	local row = CreateFrame("Frame", nil, parent)
	row._bottomLine = true -- owns the group separator on its bottom edge; the card
	-- stacker reads this to de-dup a following subHeadRow/Disclosure top line.
	local line = row:CreateTexture(nil, "ARTWORK")
	UI.SetColor(line, Border.faint)
	line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	-- Thickness pixel-snapped, position plain (the UI.Border rule): a naive
	-- 1px height rounds away under the panel scale depending on the row's y
	-- position — bit the aggro "Color" row on 2026-07-11.
	local function snap() PixelUtil.SetHeight(line, 1) end
	snap()
	C_Timer.After(0, snap)
	row:HookScript("OnSizeChanged", snap)
	row:HookScript("OnShow", snap)
	local lbl = UI.FS(row, "checkLabel", Text.Secondary)
	lbl:SetText(label)
	lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
	lbl:SetJustifyH("LEFT")
	function row:Attach(ctrl)
		ctrl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row._control = ctrl
		-- Settings search: the row reports itself once its control is known (the
		-- control carries the tooltip, which the search indexes as well). No-op
		-- outside a screen build — see Shell:IndexOption.
		if ns.Shell and ns.Shell.IndexOption then
			ns.Shell:IndexOption(label, row, "option", ctrl and ctrl._searchTip)
		end
		return row
	end
	row.SetWidgetEnabled = function(_, on)
		local col = on and Text.Secondary or Text.Description
		lbl:SetTextColor(col.r, col.g, col.b)
		if row._control and row._control.SetWidgetEnabled then row._control:SetWidgetEnabled(on) end
	end
	return row
end

-- ---------------------------------------------------------------------------
--  ChipBar — the category selector above an inline editor (Auras tab; Unit
--  Frames inherits it). One chip per category: a state DOT (category colour
--  when the category is on, muted when off), the label, and a badge showing
--  either the icon count or "off". The selected chip carries the hover surface
--  + a brighter label, so "what am I editing" reads at a glance.
--  o = { defs = { { key, label, color = {r,g,b}, on = fn -> bool,
--                   badge = fn -> string }, .. },
--        get = fn -> key, set = fn(key) }
--  :Repaint() re-reads on/badge without a rebuild (a master toggle in the
--  editor must show up on its chip immediately).
-- ---------------------------------------------------------------------------
function W.ChipBar(parent, o)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.chipH)
	local chips = {}

	local function paintOne(c)
		local sel = (o.get() == c._key)
		local on  = c._def.on and c._def.on() or false
		UI.SetColor(c._fill, sel and Surface.Hover or Surface.Input)
		-- RoundBorder returns a TABLE of edge textures (one 9-slice ring here).
		UI.SetColor(c._ring[1], sel and Border.hover or Border.faint)
		c._label:SetTextColor(sel and Text.Primary.r or Text.Description.r,
			sel and Text.Primary.g or Text.Description.g,
			sel and Text.Primary.b or Text.Description.b)
		-- Dot: the category's own colour while it renders, muted while it's off —
		-- the one place semantic colour is allowed in the chrome (it mirrors the
		-- preview, where the same colour identifies the icon row).
		if on and c._def.color then
			c._dot:SetVertexColor(c._def.color.r, c._def.color.g, c._def.color.b, 1)
		else
			c._dot:SetVertexColor(Text.Disabled.r, Text.Disabled.g, Text.Disabled.b, 1)
		end
		local badge = c._def.badge and c._def.badge() or ""
		c._badgeText:SetText(badge)
		c._badgeText:SetTextColor(sel and Text.Description.r or Text.Disabled.r,
			sel and Text.Description.g or Text.Disabled.g,
			sel and Text.Description.b or Text.Disabled.b)
		local bw = math.ceil(c._badgeText:GetStringWidth()) + M.chipCountPad * 2
		c._badge:SetWidth(math.max(bw, M.chipCountH))
		-- Width follows the content (dot + label + badge + padding).
		local w = M.chipPadX * 2 + M.chipDot + M.chipDotGap
			+ math.ceil(c._label:GetStringWidth()) + M.chipCountGap + math.max(bw, M.chipCountH)
		c:SetWidth(w)
	end

	local function relayoutChips()
		local x = 0
		for _, c in ipairs(chips) do
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
			x = x + (c:GetWidth() or 0) + M.chipGap
		end
	end

	for _, def in ipairs(o.defs) do
		local c = CreateFrame("Button", nil, f)
		c:SetHeight(M.chipH)
		c._key, c._def = def.key, def
		c._fill = UI.RoundFill(c, Surface.Input, nil, nil, R_CTRL)
		c._ring = UI.RoundBorder(c, Border.faint, "OVERLAY", nil, R_CTRL)
		-- Disc assets exist at 12/16/20/24 only -> chipDot must stay one of those.
		c._dot = UI.Circle(c, Text.Disabled, "OVERLAY", M.chipDot)
		c._dot:SetPoint("LEFT", c, "LEFT", M.chipPadX, 0)
		c._label = UI.FS(c, "checkLabel", Text.Description)
		c._label:SetPoint("LEFT", c._dot, "RIGHT", M.chipDotGap, 0)
		c._label:SetText(def.label)
		c._badge = CreateFrame("Frame", nil, c)
		c._badge:SetHeight(M.chipCountH)
		c._badge:SetPoint("LEFT", c._label, "RIGHT", M.chipCountGap, 0)
		UI.RoundFill(c._badge, Border.faint, nil, nil, UI.RADIUS.xs)
		c._badgeText = UI.FS(c._badge, "caption", Text.Disabled)
		c._badgeText:SetPoint("CENTER", c._badge, "CENTER", 0, 0)
		c:SetScript("OnEnter", function()
			if o.get() ~= c._key then UI.SetColor(c._fill, Surface.Hover) end
		end)
		c:SetScript("OnLeave", function()
			if o.get() ~= c._key then UI.SetColor(c._fill, Surface.Input) end
		end)
		c:SetScript("OnClick", function()
			if o.get() == c._key then return end
			o.set(c._key)
		end)
		chips[#chips + 1] = c
	end

	function f:Repaint()
		for _, c in ipairs(chips) do paintOne(c) end
		relayoutChips()
	end
	f:Repaint()
	-- Font glyphs may still be cold at build time -> widths measure short. One
	-- deferred repaint settles the layout (same cure as the button text heal).
	C_Timer.After(0, function() if f:IsShown() then f:Repaint() end end)
	f:HookScript("OnShow", function() f:Repaint() end)
	return f
end

-- ---------------------------------------------------------------------------
--  CopyPopover — "copy these settings somewhere else", opened from an editor
--  header. TWO questions, in this order:
--    WHAT  — one checkbox per settings GROUP (the groups are the editor's own
--            cards, so what you see is what you copy; no second taxonomy).
--    WHERE — a GRID of every possible destination (rows = categories, columns =
--            contexts). The source cell is marked and not selectable.
--  Why a grid and not a list: destinations have TWO dimensions. A flat list
--  ("Group", "Debuffs", ..) mixes them, and picking two entries has no
--  guessable meaning (Florian 2026-07-29). Column headers select a whole
--  context, row labels a whole category.
--  o = { groups = { { key, label, hint }, .. }, defaults = { [key] = bool },
--        rows = { { key, label, color }, .. },      -- categories
--        cols = { { key, label }, .. },             -- contexts
--        source = fn -> rowKey, colKey,
--        warn = optional fn(groupSel, targets) -> string or nil,
--        onCopy = fn(groupKeys, targets)  -- targets = { {row=, col=}, .. }
--      }
--  Returns the trigger BUTTON (label + copy glyph).
-- ---------------------------------------------------------------------------
function W.CopyPopover(parent, o)
	-- Text-only trigger: the Lucide set has no copy glyph yet (Textures/icons/).
	local btn = W.Button(parent, { text = o.text or T("Copy"), variant = "secondary",
		width = o.width, height = o.height })

	local host = W._menuHost or parent
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:Hide()
	local pop = CreateFrame("Frame", nil, host)
	pop:SetFrameStrata("FULLSCREEN_DIALOG")
	pop:SetFrameLevel(closer:GetFrameLevel() + 10)
	pop:SetWidth(M.copyPopW)
	pop:Hide()
	UI.RoundFill(pop, Surface.Card)
	UI.RoundBorder(pop, Border.hover, "OVERLAY")
	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = pop end

	local groupSel, targets = {}, {}   -- what / where, both reset on every open
	local rebuild                       -- forward: repaint after each click
	local function closePop() pop:Hide(); closer:Hide() end
	closer:SetScript("OnClick", closePop)

	local function targetList()
		local out = {}
		for key in pairs(targets) do
			local r, c = key:match("^(.-)|(.+)$")
			if r then out[#out + 1] = { row = r, col = c } end
		end
		return out
	end
	local function anyGroup()
		for _, g in ipairs(o.groups) do if groupSel[g.key] then return true end end
		return false
	end

	-- Children are rebuilt on every repaint (the popover is small and only
	-- redraws on a click — no hot path). Kept in a pool-free list so the old
	-- widgets are released with the popover, not leaked per click.
	local kids = {}
	local function clearKids()
		for _, k in ipairs(kids) do k:Hide(); k:SetParent(nil) end
		wipe(kids)
	end

	function rebuild()
		clearKids()
		local pad = M.copyPopPad
		local y = -pad
		local srcRow, srcCol = o.source()

		local function add(frame) kids[#kids + 1] = frame; return frame end
		-- FontStrings can't be re-parented away like frames, so each rebuild parks
		-- them on a throwaway holder frame that IS in `kids`.
		local textHost = add(CreateFrame("Frame", nil, pop))
		textHost:SetAllPoints(pop)
		local function label(text, role, col, x, yy)
			local fs = UI.FS(textHost, role, col)
			fs:SetPoint("TOPLEFT", pop, "TOPLEFT", x, yy)
			fs:SetText(text)
			return fs
		end

		-- Title + source line
		local title = label(o.title or T("Copy settings"), "sectionHead", Text.Primary, pad, y)
		y = y - math.ceil(title:GetStringHeight()) - 4
		local fromRow, fromCol
		for _, r in ipairs(o.rows) do if r.key == srcRow then fromRow = r.label end end
		for _, c in ipairs(o.cols) do if c.key == srcCol then fromCol = c.label end end
		local sub = label(("%s %s · %s"):format(T("From"), fromRow or "?", fromCol or "?"),
			"caption", Text.Description, pad, y)
		y = y - math.ceil(sub:GetStringHeight()) - M.copyGroupGap

		-- WHAT
		local wh = label(T("What"), "caption", Text.Disabled, pad, y)
		y = y - math.ceil(wh:GetStringHeight()) - 6
		for _, g in ipairs(o.groups) do
			local row = add(CreateFrame("Frame", nil, pop))
			row:SetHeight(M.copyRowH)
			row:SetPoint("TOPLEFT", pop, "TOPLEFT", pad, y)
			row:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -pad, y)
			local cb = W.Checkbox(row, {
				label = g.label, tooltipTitle = g.label,
				get = function() return groupSel[g.key] end,
				set = function(v) groupSel[g.key] = v or nil; rebuild() end,
			})
			cb:SetPoint("LEFT", row, "LEFT", 0, 0)
			if g.hint then
				local h = UI.FS(row, "caption", Text.Disabled)
				h:SetPoint("RIGHT", row, "RIGHT", 0, 0)
				h:SetText(g.hint)
			end
			y = y - M.copyRowH
		end
		y = y - M.copyGroupGap

		-- WHERE (grid)
		local wt = label(T("Where to"), "caption", Text.Disabled, pad, y)
		y = y - math.ceil(wt:GetStringHeight()) - 6

		local labelColW = M.copyPopW - pad * 2 - (#o.cols * (M.copyCellW + M.copyGridGap))
		-- Column headers double as "select this whole context".
		for ci, c in ipairs(o.cols) do
			local hb = add(CreateFrame("Button", nil, pop))
			hb:SetSize(M.copyCellW, M.copyHeadH)
			hb:SetPoint("TOPLEFT", pop, "TOPLEFT",
				pad + labelColW + (ci - 1) * (M.copyCellW + M.copyGridGap), y)
			local fs = UI.FS(hb, "caption", Text.Disabled)
			fs:SetPoint("CENTER", hb, "CENTER", 0, 0)
			fs:SetText(c.label)
			hb:SetScript("OnEnter", function() fs:SetTextColor(Text.Secondary.r, Text.Secondary.g, Text.Secondary.b) end)
			hb:SetScript("OnLeave", function() fs:SetTextColor(Text.Disabled.r, Text.Disabled.g, Text.Disabled.b) end)
			hb:SetScript("OnClick", function()
				local all = true
				for _, r in ipairs(o.rows) do
					if not (r.key == srcRow and c.key == srcCol) and not targets[r.key .. "|" .. c.key] then all = false end
				end
				for _, r in ipairs(o.rows) do
					if not (r.key == srcRow and c.key == srcCol) then
						targets[r.key .. "|" .. c.key] = (not all) or nil
					end
				end
				rebuild()
			end)
		end
		y = y - M.copyHeadH - 2

		for _, r in ipairs(o.rows) do
			-- Row label = "select this category in every context".
			local rb = add(CreateFrame("Button", nil, pop))
			rb:SetSize(labelColW - M.copyGridGap, M.copyCellH)
			rb:SetPoint("TOPLEFT", pop, "TOPLEFT", pad, y)
			local dot = rb:CreateTexture(nil, "OVERLAY")
			dot:SetTexture(TEX .. "circle-20")
			dot:SetSize(M.chipDot - 3, M.chipDot - 3)
			dot:SetPoint("LEFT", rb, "LEFT", 0, 0)
			dot:SetSnapToPixelGrid(false); dot:SetTexelSnappingBias(0)
			if r.color then dot:SetVertexColor(r.color.r, r.color.g, r.color.b, 1)
			else dot:SetVertexColor(Text.Disabled.r, Text.Disabled.g, Text.Disabled.b, 1) end
			local rfs = UI.FS(rb, "checkLabel", Text.Secondary)
			rfs:SetPoint("LEFT", dot, "RIGHT", 8, 0)
			-- Bound to the row's own width so a long category name is clipped
			-- instead of running under the first tick cell.
			rfs:SetPoint("RIGHT", rb, "RIGHT", 0, 0)
			rfs:SetJustifyH("LEFT"); rfs:SetWordWrap(false)
			rfs:SetText(r.label)
			rb:SetScript("OnEnter", function() rfs:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b) end)
			rb:SetScript("OnLeave", function() rfs:SetTextColor(Text.Secondary.r, Text.Secondary.g, Text.Secondary.b) end)
			rb:SetScript("OnClick", function()
				local all = true
				for _, c in ipairs(o.cols) do
					if not (r.key == srcRow and c.key == srcCol) and not targets[r.key .. "|" .. c.key] then all = false end
				end
				for _, c in ipairs(o.cols) do
					if not (r.key == srcRow and c.key == srcCol) then
						targets[r.key .. "|" .. c.key] = (not all) or nil
					end
				end
				rebuild()
			end)

			for ci, c in ipairs(o.cols) do
				local key = r.key .. "|" .. c.key
				local cx = pad + labelColW + (ci - 1) * (M.copyCellW + M.copyGridGap)
				if r.key == srcRow and c.key == srcCol then
					-- The source: dashed, inert, labelled — never a destination.
					local src = add(CreateFrame("Frame", nil, pop))
					src:SetSize(M.copyCellW, M.copyCellH)
					src:SetPoint("TOPLEFT", pop, "TOPLEFT", cx, y)
					UI.RoundBorder(src, Border.default, "OVERLAY", nil, R_CTRL)
					local sfs = UI.FS(src, "caption", Text.Disabled)
					sfs:SetPoint("CENTER", src, "CENTER", 0, 0)
					sfs:SetText(T("Source"))
				else
					local cell = add(CreateFrame("Button", nil, pop))
					cell:SetSize(M.copyCellW, M.copyCellH)
					cell:SetPoint("TOPLEFT", pop, "TOPLEFT", cx, y)
					local on = targets[key] and true or false
					local cf = UI.RoundFill(cell, on and Accent.selection or Surface.Input, nil, nil, R_CTRL)
					UI.RoundBorder(cell, on and Border.hover or Border.faint, "OVERLAY", nil, R_CTRL)
					local tick = cell:CreateTexture(nil, "OVERLAY")
					tick:SetSize(M.copyTick, M.copyTick)
					tick:SetPoint("CENTER", cell, "CENTER", 0, 0)
					if on then
						tick:SetTexture(TEX .. "icon-check")
						tick:SetVertexColor(Accent.color.r, Accent.color.g, Accent.color.b, 1)
					else
						tick:SetTexture(TEX .. "icon-check")
						tick:SetVertexColor(Text.Disabled.r, Text.Disabled.g, Text.Disabled.b, 0.28)
					end
					tick:SetSnapToPixelGrid(false); tick:SetTexelSnappingBias(0)
					cell:SetScript("OnEnter", function() if not targets[key] then UI.SetColor(cf, Surface.Hover) end end)
					cell:SetScript("OnLeave", function() if not targets[key] then UI.SetColor(cf, Surface.Input) end end)
					cell:SetScript("OnClick", function()
						targets[key] = (not targets[key]) or nil
						rebuild()
					end)
				end
			end
			y = y - M.copyCellH - M.copyGridGap
		end
		y = y - 4

		-- Optional warning (e.g. copying placement across categories).
		local picked = targetList()
		local warnText = o.warn and o.warn(groupSel, picked) or nil
		if warnText then
			local wf = add(CreateFrame("Frame", nil, pop))
			wf:SetHeight(M.copyWarnH)
			wf:SetPoint("TOPLEFT", pop, "TOPLEFT", pad, y)
			wf:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -pad, y)
			UI.RoundFill(wf, Border.faint, nil, nil, R_CTRL)
			local wfs = UI.FS(wf, "caption", Text.Description)
			wfs:SetPoint("TOPLEFT", wf, "TOPLEFT", 10, -8)
			wfs:SetPoint("BOTTOMRIGHT", wf, "BOTTOMRIGHT", -10, 8)
			wfs:SetJustifyH("LEFT"); wfs:SetJustifyV("TOP")
			wfs:SetText(warnText)
			y = y - M.copyWarnH - 8
		end

		-- Footer: cancel + the counting confirm button.
		local foot = add(CreateFrame("Frame", nil, pop))
		foot:SetHeight(M.buttonH)
		foot:SetPoint("TOPLEFT", pop, "TOPLEFT", pad, y)
		foot:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -pad, y)
		local cancel = W.Button(foot, { text = T("Cancel"), variant = "secondary",
			width = (M.copyPopW - pad * 2 - 10) / 2, onClick = closePop })
		cancel:SetPoint("LEFT", foot, "LEFT", 0, 0)
		local n = #picked
		local go = W.Button(foot, {
			text = (n > 0) and (T("Copy") .. " (" .. n .. ")") or T("Copy"),
			variant = "primary", width = (M.copyPopW - pad * 2 - 10) / 2,
			onClick = function()
				if not (anyGroup() and n > 0) then return end
				local keys = {}
				for _, g in ipairs(o.groups) do if groupSel[g.key] then keys[#keys + 1] = g.key end end
				closePop()
				o.onCopy(keys, picked)
			end,
		})
		go:SetPoint("RIGHT", foot, "RIGHT", 0, 0)
		-- W.Button has no SetWidgetEnabled — same dim+deafen pattern the other
		-- widgets use for their disabled state.
		local usable = anyGroup() and n > 0
		go:SetAlpha(usable and 1 or 0.35)
		go:EnableMouse(usable)
		y = y - M.buttonH

		pop:SetHeight(-y + pad)
	end

	btn:SetScript("OnClick", function()
		if pop:IsShown() then closePop(); return end
		wipe(targets)
		for _, g in ipairs(o.groups) do
			groupSel[g.key] = (o.defaults and o.defaults[g.key]) or nil
		end
		rebuild()
		pop:ClearAllPoints()
		pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -6)
		pop:SetClampedToScreen(true)
		closer:Show(); pop:Show(); pop:Raise()
	end)
	return btn
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
	local stageFill -- forward-declared: the eye popover's "Background" row toggles it via RepaintEyes (created below with the stage)
	-- The stage fill AND the dock's own fill are BOTH Surface.Window, so hiding just the
	-- stage reveals an identical colour = no visible change. The "Background" eye
	-- hides both, so the shell's dotted content shows through (frames "float").
	local dockFrame = parent:GetParent() -- the Shell dock (carries ._fill)

	-- Header CARD (v3 top-card style, like the Base "enable" card): a rounded
	-- fill+border card inset from the dock edges, holding the title + all
	-- controls. It stands out from the dock surface (esp. with the backdrop
	-- hidden via the filter) and IS the drag handle — so the separate grip is
	-- gone (Florian 2026-07-05).
	-- INLINE: the whole band is ONE card — header row on top, hairline, stage
	-- below. A separate header card floating over a separate stage read as two
	-- unrelated things sitting next to each other (Florian 2026-07-29).
	if o.inline then
		UI.RoundFill(f, Surface.Card, nil, nil, RAD.lg)
		UI.RoundBorder(f, Border.default, "OVERLAY", nil, RAD.lg)
	end

	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", f, "TOPLEFT", M.pvDockPad, -M.pvDockPad)
	head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -M.pvDockPad, -M.pvDockPad)
	head:SetHeight(o.inline and M.pvInlineHeadH or M.sectionHeaderH)
	if o.inline then
		-- Header row INSIDE the card: no fill, no border and NO divider either —
		-- a hairline right under the title read as cramped, and the stage below
		-- is already its own surface (Florian 2026-07-29).
		local _ = head
	else
		-- The head is a REAL card matching the settings cards EXACTLY: same fill
		-- (Surface.Card) and border (Border.default). With the page-colored stage below (no black
		-- box) this reads as page + card — like the settings page itself, not a
		-- nested "double frame" (Florian 2026-07-05).
		UI.RoundFill(head, Surface.Card, nil, nil, RAD.lg)
		UI.RoundBorder(head, Border.default, "OVERLAY", nil, RAD.lg)
	end
	local lbl = UI.FS(head, "sectionHead", Text.Primary)
	-- Inline: the title slot names what the switch next to it DOES ("Editing"),
	-- because that switch picks the context whose values you are editing — not
	-- merely what the preview shows. Dock: it is just a preview window.
	lbl:SetText((o.inline and o.ctx and o.ctx.caption) and o.ctx.caption or T("PREVIEW"))

	-- Inline: a collapse chevron leads the row, sitting on the left edge the
	-- content blocks below use, with the title right beside it (Florian
	-- 2026-07-29). Folding the preview away is worth having when it is in the
	-- way — it is anchored, so it cannot simply be pushed aside.
	local foldBtn
	if o.inline and o.fold then
		foldBtn = CreateFrame("Button", nil, head)
		-- Same footprint as a card's eye button: the title then starts at the
		-- exact x a card title does.
		foldBtn:SetSize(M.cardEyeBtn, M.cardEyeBtn)
		foldBtn:SetPoint("LEFT", head, "LEFT", M.pvInlineTitleX, 0)
		local fg = foldBtn:CreateTexture(nil, "OVERLAY")
		fg:SetSize(M.chevGlyph, M.chevGlyph)
		fg:SetPoint("CENTER", foldBtn, "CENTER", 0, 0)
		fg:SetSnapToPixelGrid(false); fg:SetTexelSnappingBias(0)
		local function paintFold()
			fg:SetTexture(TEX .. (o.fold.get() and "icon-chevron-right" or "icon-chevron-down"))
			local c = Text.Description
			fg:SetVertexColor(c.r, c.g, c.b)
		end
		paintFold()
		foldBtn:SetScript("OnEnter", function() fg:SetVertexColor(Text.Primary.r, Text.Primary.g, Text.Primary.b) end)
		foldBtn:SetScript("OnLeave", function() paintFold() end)
		foldBtn:SetScript("OnClick", function() o.fold.set(not o.fold.get()) end)
		lbl:SetPoint("LEFT", foldBtn, "RIGHT", S.s3, 0)
	elseif o.inline then
		lbl:SetPoint("LEFT", head, "LEFT", M.pvInlineTitleX, 0)
	else
		lbl:SetPoint("LEFT", head, "LEFT", M.sectionTitleX, 0)
	end

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
	-- Inline bands sit IN the page and are always visible — nothing to fold away.
	if o.inline then cbtn:Hide() end
	UI.RoundFill(cbtn, Surface.Input, nil, nil, R_CTRL) -- lighter than the card, like a dropdown on a settings card
	UI.RoundBorder(cbtn, Border.hover, "OVERLAY", nil, R_CTRL)
	local cGlyph = cbtn:CreateTexture(nil, "OVERLAY")
	cGlyph:SetSize(M.pvGlyph, M.pvGlyph)
	cGlyph:SetPoint("CENTER", cbtn, "CENTER", 0, 0)
	cGlyph:SetSnapToPixelGrid(false); cGlyph:SetTexelSnappingBias(0)
	cGlyph:SetVertexColor(Text.Description.r, Text.Description.g, Text.Description.b)
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
		UI.RoundFill(rbtn, Surface.Input, nil, nil, R_CTRL)
		UI.RoundBorder(rbtn, Border.hover, "OVERLAY", nil, R_CTRL)
		local rGlyph = rbtn:CreateTexture(nil, "OVERLAY")
		rGlyph:SetSize(M.pvGlyph, M.pvGlyph)
		rGlyph:SetPoint("CENTER", rbtn, "CENTER", 0, 0)
		rGlyph:SetTexture(TEX .. "icon-reset")
		rGlyph:SetSnapToPixelGrid(false); rGlyph:SetTexelSnappingBias(0)
		rGlyph:SetVertexColor(Text.Description.r, Text.Description.g, Text.Description.b)
		rbtn:SetScript("OnClick", function() o.onResetPos() end) -- no hover (matches the collapse icon)
		resetAnchor = rbtn
	end

	-- Central eye popover (Florian 2026-07-17): ONE overview of all preview
	-- layers, left of the reset button — the eyes stay on their cards as the
	-- contextual access, this is the collection point (no tab hopping to hide
	-- shields while judging auras). Reads/writes the SAME previewEyes state the
	-- card eyes use, so both access points sync automatically: rows call
	-- o.onEye (repaints card eyes via the Shell), card eyes funnel back through
	-- band:RepaintEyes. Row list comes from o.eyeDefs (built next to the
	-- eyeToggle call sites in Screens — no second catalog that can drift).
	local ebtn, eyePop
	local eyeRepaints = {}
	local eGlyph, eEdges
	local function paintEyeBtn()
		if not ebtn then return end
		local t = o.eyes and o.eyes() or {}
		local filtered = false
		local function scan(list)
			for _, def in ipairs(list) do
				if def.children then scan(def.children)
				elseif t[def.key] == false then filtered = true end
			end
		end
		scan(o.eyeDefs)
		eGlyph:SetTexture(TEX .. (filtered and "icon-eye-off" or "icon-eye"))
		local col = filtered and Text.Primary or Text.Description
		eGlyph:SetVertexColor(col.r, col.g, col.b)
		-- Filtered = the glyph goes accent; keep the border subtle (Florian 2026-07-22:
		-- the Accent.color ring read as a hard white outline).
		for _, e in ipairs(eEdges) do UI.SetColor(e, Border.hover) end
	end
	if o.eyeDefs then
		ebtn = CreateFrame("Button", nil, head)
		ebtn:SetSize(M.pvIconBtn, M.pvIconBtn)
		-- Inline: the collapse button is hidden, so anchoring off it would leave
		-- the eye floating short of the right edge.
		if o.inline then ebtn:SetPoint("RIGHT", head, "RIGHT", 0, 0)
		else ebtn:SetPoint("RIGHT", resetAnchor, "LEFT", -S.s4, 0) end
		UI.RoundFill(ebtn, Surface.Input, nil, nil, R_CTRL)
		eEdges = UI.RoundBorder(ebtn, Border.hover, "OVERLAY", nil, R_CTRL)
		eGlyph = ebtn:CreateTexture(nil, "ARTWORK")
		eGlyph:SetSize(M.pvGlyph, M.pvGlyph)
		eGlyph:SetPoint("CENTER", ebtn, "CENTER", 0, 0)
		eGlyph:SetSnapToPixelGrid(false); eGlyph:SetTexelSnappingBias(0)

		-- The popover floats on the menu HOST, not inside the band: an inline band
		-- lives in the panel's content area, where a plain child would open
		-- BEHIND the surrounding shell chrome (Florian 2026-07-29). Same host and
		-- strata the dropdowns use. Deliberately NOT registered in W._popovers —
		-- that list is wiped per screen, and the band outlives a screen.
		local popHost = W._menuHost or f
		eyePop = CreateFrame("Frame", nil, popHost)
		eyePop:SetFrameStrata("FULLSCREEN_DIALOG")
		eyePop:SetFrameLevel(popHost:GetFrameLevel() + 60)
		eyePop:SetClampedToScreen(true)
		UI.RoundFill(eyePop, Surface.Input, nil, nil, RAD.lg)
		UI.RoundBorder(eyePop, Border.default, "OVERLAY", nil, RAD.lg) -- subtle, matches the new dropdown (Florian 2026-07-22: Accent.color read as a hard white outline)
		eyePop:Hide()
		local rowIdx, popW = 0, M.pvFilterW
		local function popRow(label, indent, isOn, onClick)
			local row = CreateFrame("Button", nil, eyePop)
			row:SetHeight(M.pvFilterRowH)
			local y = -(M.pvFilterPad + rowIdx * M.pvFilterRowH)
			rowIdx = rowIdx + 1
			row:SetPoint("TOPLEFT", eyePop, "TOPLEFT", M.pvFilterPad + indent, y)
			row:SetPoint("TOPRIGHT", eyePop, "TOPRIGHT", -M.pvFilterPad, y)
			local box = CreateFrame("Frame", nil, row)
			box:SetSize(M.pvFilterCheck, M.pvFilterCheck)
			box:SetPoint("LEFT", row, "LEFT", 0, 0)
			UI.RoundBorder(box, Border.hover, "OVERLAY", nil, RAD.xs)
			local mark = box:CreateTexture(nil, "ARTWORK")
			mark:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
			mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
			UI.SetColor(mark, Accent.color)
			local rl = UI.FS(row, "value", Text.Secondary)
			rl:SetPoint("LEFT", box, "RIGHT", S.s4, 0)
			rl:SetText(label)
			-- Popover width follows the longest (localized) label.
			popW = math.max(popW, M.pvFilterPad * 2 + indent + M.pvFilterCheck
				+ S.s4 + math.ceil(rl:GetStringWidth()))
			local function repaint() mark:SetShown(isOn()) end
			repaint()
			row:SetScript("OnClick", function()
				onClick()
				for _, rp in ipairs(eyeRepaints) do rp() end
				paintEyeBtn()
				if o.onEye then o.onEye() end
			end)
			eyeRepaints[#eyeRepaints + 1] = repaint
		end
		for _, def in ipairs(o.eyeDefs) do
			if def.children then
				-- Parent row ("Aura indicators"): flips all category children.
				local kids = def.children
				local function allOn()
					local t = o.eyes()
					for _, c in ipairs(kids) do if t[c.key] == false then return false end end
					return true
				end
				popRow(def.label, 0, allOn, function()
					local t, target = o.eyes(), not allOn()
					for _, c in ipairs(kids) do t[c.key] = target end
				end)
				for _, c in ipairs(kids) do
					local key = c.key
					popRow(c.label, M.pvFilterCheck + S.s4,
						function() return o.eyes()[key] ~= false end,
						function() local t = o.eyes(); t[key] = (t[key] == false) end)
				end
			else
				local key = def.key
				popRow(def.label, 0,
					function() return o.eyes()[key] ~= false end,
					function() local t = o.eyes(); t[key] = (t[key] == false) end)
			end
		end
		eyePop:SetSize(popW, M.pvFilterPad * 2 + rowIdx * M.pvFilterRowH)
		ebtn:SetScript("OnClick", function()
			if eyePop:IsShown() then eyePop:Hide() return end
			for _, rp in ipairs(eyeRepaints) do rp() end
			paintEyeBtn()
			-- Inline bands re-anchor per render (SetExtent runs for the dock
			-- variant only), so pin the popover under the button on every open.
			if o.inline then
				eyePop:ClearAllPoints()
				eyePop:SetPoint("TOPRIGHT", ebtn, "BOTTOMRIGHT", 0, -S.s3)
			end
			eyePop:Show()
			eyePop:Raise()
		end)
		paintEyeBtn()
		resetAnchor = ebtn
	end
	-- Card-eye clicks funnel through here (Screens' previewRefresh) so both
	-- access points stay in sync while the popover is open.
	function f:RepaintEyes()
		paintEyeBtn()
		-- The "Background" eye toggles the stage backdrop live (RepaintEyes runs on
		-- every eye click via previewRefresh; SetExtent only fires on a re-layout).
		-- Hide the dock fill too, else the identical-coloured dock shows through.
		if stageFill and o.eyes then
			local show = o.eyes().background ~= false
			stageFill:SetShown(show)
			if dockFrame and dockFrame._fill then dockFrame._fill:SetShown(show) end
		end
		if eyePop and eyePop:IsShown() then
			for _, rp in ipairs(eyeRepaints) do rp() end
		end
	end
	f._eyePop = eyePop

	local repaints = {}
	local chipsW = 0
	-- Dock: chips chain RIGHT-to-left from the collapse button. Inline: they sit
	-- directly after the title, so "Editing [Group|Raid]" reads as one phrase.
	local leftChain = o.inline and true or false
	local chainAnchor, chainGap = leftChain and lbl or resetAnchor, M.pvChipGroupGap
	-- items = { { v =, label = }, ... }; paints selection from get(), sets via set(v).
	local function chipGroup(items, get, set)
		local chips = {}
		local order = {}
		if leftChain then for i = 1, #items do order[#order + 1] = i end
		else for i = #items, 1, -1 do order[#order + 1] = i end end
		for _, i in ipairs(order) do
			local item = items[i]
			local chip = CreateFrame("Button", nil, head)
			chip:SetHeight(M.pvEyeH)
			UI.RoundFill(chip, Surface.Scrim, nil, nil, RAD.sm)
			local edges = UI.RoundBorder(chip, Border.hover, "OVERLAY", nil, RAD.sm)
			local txt = UI.FS(chip, "value", Text.Description)
			txt:SetPoint("CENTER", chip, "CENTER", 0, 0)
			txt:SetText(item.label)
			chip:SetWidth(math.max(M.pvEyeH, math.ceil(txt:GetStringWidth()) + M.pvEyePadX * 2))
			if leftChain then chip:SetPoint("LEFT", chainAnchor, "RIGHT", chainGap, 0)
			else chip:SetPoint("RIGHT", chainAnchor, "LEFT", -chainGap, 0) end
			chipsW = chipsW + chip:GetWidth() + chainGap
			chainAnchor, chainGap = chip, M.pvEyeGap
			chips[#chips + 1] = { v = item.v, paint = function(on)
				for _, e in ipairs(edges) do UI.SetColor(e, on and Accent.color or Border.hover) end
				local tc = on and Text.Primary or Text.Description
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
	if o.ctx and o.inline then
		-- Inline: a real W.Segment, the same control the settings use for every
		-- other either/or choice — the little bordered chips were their own
		-- language and read dated next to it (Florian 2026-07-29).
		local opts2 = {}
		for _, it in ipairs(o.ctx.values) do opts2[#opts2 + 1] = { value = it.v, label = it.label } end
		local seg = W.Segment(head, { options = opts2, get = o.ctx.get, set = o.ctx.set,
			width = M.pvCtxSegW, cellH = M.segCompactH })
		seg:SetPoint("LEFT", lbl, "RIGHT", M.pvChipGroupGap, 0)
		f._ctxSeg = seg
	elseif o.ctx then
		chipGroup(o.ctx.values, o.ctx.get, o.ctx.set)
	end
	-- Inline: a quiet right-aligned hint that the stage is clickable (the
	-- click-to-configure affordance is otherwise only discoverable by hovering).
	if o.inline and o.hint then
		local hint = UI.FS(head, "caption", Text.Disabled)
		hint:SetPoint("RIGHT", head, "RIGHT", 0, 0)
		hint:SetText(o.hint)
	end
	function f:PaintChips()
		for _, rp in ipairs(repaints) do rp() end
	end

	-- Minimum dock width so the header row never collapses onto itself.
	local headMinW = M.sectionTitleX + math.ceil(lbl:GetStringWidth()) + S.s7
		+ chipsW + M.pvIconBtn + S.s4 + M.pvIconBtn + M.pvDockPad * 2
		+ (ebtn and (S.s4 + M.pvIconBtn) or 0)

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
	stageFill = UI.RoundFill(stage, Surface.Window, nil, nil, R_CTRL) -- assigns the forward-declared upvalue
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

	local caption = UI.FS(stage, "caption", Text.Description)
	caption:SetPoint("BOTTOM", stage, "BOTTOM", 0, S.s2 + 2)

	f.holder = holder
	f.GetEyes = o.eyes
	f.stage = stage
	f.inline = o.inline and true or false

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
		-- Eye popover opens away from the stage (old grouped-filter rule):
		-- right dock -> outward right, bottom dock -> upward above the header.
		if eyePop then
			eyePop:ClearAllPoints()
			if side == "right" then
				eyePop:SetPoint("TOPLEFT", head, "TOPRIGHT", S.s3, 0)
			else
				eyePop:SetPoint("BOTTOMRIGHT", head, "TOPRIGHT", 0, S.s3)
			end
		end
		-- Stage backdrop is togglable again via the eye popover's "Background" row
		-- (Florian 2026-07-22): hidden -> stage + dock fills off, shell dots show through.
		local bgShow = not o.eyes or o.eyes().background ~= false
		stageFill:SetShown(bgShow)
		if dockFrame and dockFrame._fill then dockFrame._fill:SetShown(bgShow) end
		for _, e in ipairs(stageEdges) do e:SetShown(true) end
		caption:SetShown(true)
		if o.onChrome then o.onChrome(true) end
		-- Inline (anchored in the content area, Auras tab): the band's height is
		-- FIXED by the screen, so there is no dock to resize — the module scales
		-- its holder to fit the stage instead. Reporting a layout here would
		-- fight the stack that placed us.
		if o.inline then return end
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

	-- Folded: only the header row remains (the screen shrinks the sticky area to
	-- match). The frames stay built — unfolding must not have to rebuild them.
	function f:SetFolded(on)
		body:SetShown(not on)
		if foldBtn then foldBtn:GetScript("OnLeave")(foldBtn) end -- repaint the chevron
	end

	-- Usable stage size for an inline band (module fit-scaling); caption row and
	-- stage padding are already deducted.
	function f:GetStageSpace()
		local sw, sh = stage:GetWidth() or 0, stage:GetHeight() or 0
		return math.max(1, sw - M.pvStagePad * 2), math.max(1, sh - M.pvStagePad * 2 - M.pvCaptionH)
	end

	return f
end
