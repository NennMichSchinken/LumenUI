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
local C, L, S, M = UI.C, UI.line, UI.S, UI.WIDGET
local T = ns.T   -- localization: T("english") -> display in the active language

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

-- ---------------------------------------------------------------------------
--  Internal helpers
-- ---------------------------------------------------------------------------
local function clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Gold chevron (pointing down) from two lines — unicode ▼ is not reliable in the
-- font (same reasoning as the close X in the chrome).
local function chevron(parent, col)
	local a = parent:CreateLine(nil, "OVERLAY")
	local b = parent:CreateLine(nil, "OVERLAY")
	a:SetThickness(1.5); b:SetThickness(1.5)
	local function setCol(c)
		a:SetColorTexture(c.r, c.g, c.b, c.a or 1)
		b:SetColorTexture(c.r, c.g, c.b, c.a or 1)
	end
	setCol(col)
	-- relative to its own 12x8 anchor (CENTER)
	a:SetStartPoint("CENTER", parent, -4, 2); a:SetEndPoint("CENTER", parent, 0, -2)
	b:SetStartPoint("CENTER", parent, 0, -2); b:SetEndPoint("CENTER", parent, 4, 2)
	return setCol
end

-- ---------------------------------------------------------------------------
--  SectionDivider — centered Cinzel heading with symmetrically fading gold
--  rules. Primary page divider. Height ~28.
-- ---------------------------------------------------------------------------
function W.SectionDivider(parent, text, small)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.dividerH)
	local strongA = small and 0.30 or 0.45 -- smaller sub-heading = subtler lines
	local head = UI.FS(f, small and "subDivider" or "sectionHead", small and C.gold250 or C.gold300)
	head:SetText(text)
	head:SetPoint("CENTER", f, "CENTER", 0, 0)

	local lr = UI.GradientLine(f, "out", strongA, 0.0)
	lr:SetPoint("RIGHT", head, "LEFT", -M.dividerGap, 0)
	lr:SetPoint("LEFT", f, "LEFT", 0, 0)
	lr:SetPoint("TOP", head, "CENTER", 0, 0)
	local rr = UI.GradientLine(f, "in", strongA, 0.0)
	rr:SetPoint("LEFT", head, "RIGHT", M.dividerGap, 0)
	rr:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	rr:SetPoint("TOP", head, "CENTER", 0, 0)
	f._head = head
	return f
end

-- ---------------------------------------------------------------------------
--  Field — gold label above a control. Returns (container, contentTopYOffset).
--  The caller anchors its control at TOPLEFT/RIGHT, container, ..., 0, yOff.
-- ---------------------------------------------------------------------------
local function fieldLabel(parent, text)
	local lbl = UI.FS(parent, "fieldLabel", C.gold250)
	lbl:SetText(text)
	lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	lbl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	lbl:SetJustifyH("LEFT")
	return lbl, -M.fieldGap -- yOffset for the control below
end

-- ---------------------------------------------------------------------------
--  Slider — gold track, label on top, min/max at the ends, value box below.
--  Pointer-driven (no native slider frame). o = {label,min,max,step,
--  get,set,value,unit,width}. Height ~80.
-- ---------------------------------------------------------------------------
function W.Slider(parent, o)
	local minV, maxV, step = o.min or 0, o.max or 100, o.step or 1
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.sliderH)
	if o.width then f:SetWidth(o.width) end

	local cap = UI.FS(f, "sliderCap", C.gold300)
	cap:SetText(o.label or "")
	cap:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
	cap:SetJustifyH("LEFT")

	-- Track row: [min] —— track —— [max]
	local row = CreateFrame("Frame", nil, f)
	row:SetHeight(M.sliderTrackH)
	row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -M.sliderCapGap)
	row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -M.sliderCapGap)

	local minL = UI.FS(row, "ends", C.textMuted)
	minL:SetText(tostring(minV)); minL:SetWidth(M.sliderEndW); minL:SetJustifyH("RIGHT")
	minL:SetPoint("LEFT", row, "LEFT", 0, 0)
	local maxL = UI.FS(row, "ends", C.textMuted)
	maxL:SetText(tostring(maxV)); maxL:SetWidth(M.sliderEndW); maxL:SetJustifyH("LEFT")
	maxL:SetPoint("RIGHT", row, "RIGHT", 0, 0)

	local track = CreateFrame("Frame", nil, row)
	track:SetHeight(M.sliderTrackH)
	track:SetPoint("LEFT", minL, "RIGHT", M.sliderEndPad, 0)
	track:SetPoint("RIGHT", maxL, "LEFT", -M.sliderEndPad, 0)
	track:EnableMouse(true)

	local bg = track:CreateTexture(nil, "ARTWORK")
	bg:SetHeight(M.sliderBarH)
	bg:SetPoint("LEFT", track, "LEFT", 0, 0)
	bg:SetPoint("RIGHT", track, "RIGHT", 0, 0)
	UI.SetColor(bg, C.sliderTrack)

	local fillbar = track:CreateTexture(nil, "ARTWORK", nil, 1)
	fillbar:SetHeight(M.sliderBarH)
	fillbar:SetPoint("LEFT", track, "LEFT", 0, 0)
	UI.SetColor(fillbar, C.gold500)

	local thumb = CreateFrame("Frame", nil, track)
	thumb:SetSize(M.sliderThumb, M.sliderThumb)
	local tt = thumb:CreateTexture(nil, "OVERLAY")
	tt:SetAllPoints(thumb); UI.SetColor(tt, C.gold500)
	UI.Border(thumb, { r = 0.10, g = 0.09, b = 0.08, a = 1 }, 2, "OVERLAY")

	-- Value box below (centered) — editable EditBox: click, type a number,
	-- Enter confirms (clamped to min/max + step), Esc discards.
	local box = CreateFrame("EditBox", nil, f)
	box:SetSize(M.valueBoxW, M.valueBoxH)
	box:SetPoint("TOP", row, "BOTTOM", 0, -M.valueBoxGap)
	UI.Fill(box, C.ink700)
	local boxEdges = UI.Border(box, L.soft, 1, "OVERLAY")
	UI:SetFont(box, "value", C.textStrong)
	box:SetJustifyH("CENTER")
	box:SetAutoFocus(false)
	box:SetTextInsets(6, 6, 0, 0)

	local cur = (o.get and o.get()) or o.value or minV
	local unit = o.unit or ""
	local typing = false -- true while the EditBox is focused (no clobbering)

	local function visual(v)
		local ratio = (maxV > minV) and clamp((v - minV) / (maxV - minV), 0, 1) or 0
		local w = track:GetWidth() or 0
		fillbar:SetWidth(math.max(0.5, ratio * w))
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

	local function commit(v)
		if v == cur then return end
		cur = v
		visual(v)
		if o.set then o.set(v) end
	end

	-- EditBox: parse the typed value (leading number, also negative), round,
	-- clamp, apply. Focus colors the border more strongly.
	box:SetScript("OnEditFocusGained", function(self)
		typing = true
		for _, e in ipairs(boxEdges) do UI.SetColor(e, L.strong) end
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		typing = false
		for _, e in ipairs(boxEdges) do UI.SetColor(e, L.soft) end
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

	local function onUpd() commit(valFromCursor()) end
	local function beginDrag() track:SetScript("OnUpdate", onUpd); commit(valFromCursor()) end
	local function endDrag() track:SetScript("OnUpdate", nil) end
	track:SetScript("OnMouseDown", beginDrag)
	track:SetScript("OnMouseUp", endDrag)
	track:SetScript("OnHide", endDrag)
	-- Make the thumb itself grabbable: at the stops (0/100 %) the square sticks out half
	-- past the track — that part used to be dead (only the track was clickable). Mouse-enabled
	-- + 2px larger hit area (purely clickable, visually unchanged) -> easy to grab.
	thumb:EnableMouse(true)
	thumb:SetHitRectInsets(-2, -2, -2, -2)
	thumb:SetScript("OnMouseDown", beginDrag)
	thumb:SetScript("OnMouseUp", endDrag)
	-- Track width is only known after the layout -> redraw on size change.
	track:SetScript("OnSizeChanged", function() visual(cur) end)

	visual(cur)
	f.SetValueExternal = function(_, v) cur = v; visual(v) end
	-- Grey out + lock interaction (for dependent sections, e.g. "Show name" off).
	f.SetWidgetEnabled = function(_, on)
		f:SetAlpha(on and 1 or 0.35)
		track:EnableMouse(on)
		box:EnableMouse(on)
		if not on then box:ClearFocus() end
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
	UI.Fill(btn, C.ink700)
	local edges = UI.Border(btn, L.soft, 1, "OVERLAY")
	f._control = btn -- anchor for "checkbox right next to the control" (vertically aligned)

	local chev = CreateFrame("Frame", nil, btn)
	chev:SetSize(12, 8)
	chev:SetPoint("RIGHT", btn, "RIGHT", -12, 0)
	chevron(chev, C.textMuted)

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
	UI.Fill(menu, C.ink550)
	UI.Border(menu, L.mid, 1, "OVERLAY")

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
	--  • active (selected) row -> gold bar on the LEFT + gold text (stays visible)
	--  • hovered row           -> warm brown wash (inkTint) + lighter text
	-- The gold bar marks the selection permanently, the brown wash only the hover
	-- — so selected and hover no longer look almost the same (Florian feedback).
	local pad, rowH, gap = 6, 34, 2
	local function paintItem(item, hovered)
		local active = (item._val == cur)
		item._bar:SetShown(active)
		if hovered then
			item._wash:SetColorTexture(C.inkTint.r, C.inkTint.g, C.inkTint.b, 1)
			item._txt:SetTextColor(C.gold100.r, C.gold100.g, C.gold100.b)
		else
			item._wash:SetColorTexture(0, 0, 0, 0)
			local tc = active and C.gold250 or C.textStrong
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
		UI.Fill(search, C.ink700)
		UI.Border(search, L.soft, 1, "OVERLAY")
		search:SetFont(UI.FONT.hankenMed, 14, "")
		search:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
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

	-- Trigger button: inset field with gold border + gold text (like in the mockup).
	local btn = CreateFrame("Button", nil, f)
	btn:SetAllPoints(f)
	UI.Fill(btn, C.ink700)
	local bEdges = UI.Border(btn, L.mid, 1, "OVERLAY")
	local bTxt = UI.FS(btn, "btn", C.gold300)
	bTxt:SetFont(UI.FONT.hankenSemi, 16, "")
	bTxt:SetText(o.text or T("+ Add"))
	-- With o.icon (chosen spell): icon on the left + text left-aligned next to it; otherwise centered.
	if o.icon then
		local bIcon = btn:CreateTexture(nil, "ARTWORK")
		bIcon:SetSize(M.trackIcon, M.trackIcon)
		bIcon:SetPoint("LEFT", btn, "LEFT", 10, 0)
		bIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		bIcon:SetTexture(o.icon)
		bTxt:SetPoint("LEFT", bIcon, "RIGHT", 8, 0)
		bTxt:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
		bTxt:SetJustifyH("LEFT"); bTxt:SetWordWrap(false)
	else
		bTxt:SetPoint("CENTER", btn, "CENTER", 0, 0)
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
	menu:Hide()
	UI.Fill(menu, C.ink550)
	UI.Border(menu, L.strong, 1, "OVERLAY")
	if W._popovers then W._popovers[#W._popovers + 1] = closer; W._popovers[#W._popovers + 1] = menu end

	local listH = M.spVisibleRows * M.spRowH
	menu:SetHeight(M.spPad * 2 + M.spSearchH + 8 + listH)

	-- Search field (typeahead) -------------------------------------------
	local search = CreateFrame("EditBox", nil, menu)
	search:SetHeight(M.spSearchH)
	search:SetPoint("TOPLEFT", menu, "TOPLEFT", M.spPad, -M.spPad)
	search:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -M.spPad, -M.spPad)
	UI.Fill(search, C.ink700)
	UI.Border(search, L.soft, 1, "OVERLAY")
	search:SetFont(UI.FONT.hankenMed, 14, "")
	search:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
	search:SetTextInsets(10, 10, 0, 0)
	search:SetAutoFocus(false)
	local ph = UI.FS(search, "label", C.textMuted)
	ph:SetText(T("Search spell …"))
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
		local bar = r:CreateTexture(nil, "ARTWORK"); bar:SetWidth(3)
		bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
		UI.SetColor(bar, C.gold500); bar:Hide()
		local icon = r:CreateTexture(nil, "ARTWORK")
		icon:SetSize(M.trackIcon, M.trackIcon)
		icon:SetPoint("LEFT", r, "LEFT", 8, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local name = UI.FS(r, "selectText", C.textStrong)
		name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
		name:SetPoint("RIGHT", r, "RIGHT", -8, 0)
		name:SetJustifyH("LEFT"); name:SetWordWrap(false)
		r._bar, r._wash, r._icon, r._name = bar, wash, icon, name
		r:SetScript("OnEnter", function(self2)
			self2._wash:SetColorTexture(C.inkTint.r, C.inkTint.g, C.inkTint.b, 1)
			self2._bar:Show()
			self2._name:SetTextColor(C.gold100.r, C.gold100.g, C.gold100.b)
			W.ShowSpellTip(self2, self2._id) -- own Lumen tooltip
		end)
		r:SetScript("OnLeave", function(self2)
			self2._wash:SetColorTexture(0, 0, 0, 0); self2._bar:Hide()
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
				r._wash:SetColorTexture(0, 0, 0, 0); r._bar:Hide()
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
		for _, e in ipairs(bEdges) do UI.SetColor(e, L.mid) end
	end
	closer:SetScript("OnClick", closeMenu)

	btn:SetScript("OnClick", function() if menu:IsShown() then closeMenu() else openMenu() end end)
	btn:SetScript("OnEnter", function()
		if not menu:IsShown() then for _, e in ipairs(bEdges) do UI.SetColor(e, L.strong) end end
		bTxt:SetTextColor(C.gold200.r, C.gold200.g, C.gold200.b)
	end)
	btn:SetScript("OnLeave", function()
		if not menu:IsShown() then for _, e in ipairs(bEdges) do UI.SetColor(e, L.mid) end end
		bTxt:SetTextColor(C.gold300.r, C.gold300.g, C.gold300.b)
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
	UI.Fill(card, C.ink550)
	UI.Border(card, L.strong, 1, "OVERLAY")
	local accent = card:CreateTexture(nil, "OVERLAY") -- gold accent on top (signature)
	accent:SetHeight(3)
	accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
	accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
	UI.SetColor(accent, C.gold500)

	local title = UI.FS(card, "sectionHead", C.gold300)
	title:SetPoint("TOPLEFT", card, "TOPLEFT", M.confirmPad, -M.confirmPad)
	title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.confirmPad, -M.confirmPad)
	title:SetJustifyH("LEFT")

	local body = UI.FS(card, "hint", C.textBody)
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -14)
	body:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -14)
	body:SetJustifyH("LEFT"); body:SetWordWrap(true)

	local okBtn = W.Button(card, { text = T("Confirm"), variant = "danger", width = M.confirmBtnW })
	okBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -M.confirmPad, M.confirmPad)
	local cancelBtn = W.Button(card, { text = T("Cancel"), variant = "ghost", width = M.confirmBtnW })
	cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -M.confirmBtnGap, 0)

	confirmDlg = { overlay = overlay, card = card, title = title, body = body, ok = okBtn, cancel = cancelBtn }
	return confirmDlg
end

function W.Confirm(o)
	local dlg = confirmDlg or buildConfirm()
	dlg.title:SetText(o.title or T("Are you sure?"))
	dlg.body:SetText(o.body or "")
	dlg.ok._txt:SetText(o.confirmText or T("Confirm"))
	dlg.cancel._txt:SetText(o.cancelText or T("Cancel"))
	local function doCancel()
		dlg.overlay:Hide()
		if o.onCancel then o.onCancel() end
	end
	dlg.ok:SetScript("OnClick", function()
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
	UI.Fill(card, C.ink550)
	UI.Border(card, L.strong, 1, "OVERLAY")
	local accent = card:CreateTexture(nil, "OVERLAY")
	accent:SetHeight(3)
	accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
	accent:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
	UI.SetColor(accent, C.gold500)

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

	local lbl = UI.FS(card, "fieldLabel", C.gold250)
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
	tip:Hide()
	UI.Fill(tip, C.ink850) -- darker than the popover -> clearer tooltip contrast
	UI.Border(tip, L.strong, 1, "OVERLAY")
	local accent = tip:CreateTexture(nil, "OVERLAY") -- gold accent on top (signature)
	accent:SetHeight(2)
	accent:SetPoint("TOPLEFT", tip, "TOPLEFT", 0, 0)
	accent:SetPoint("TOPRIGHT", tip, "TOPRIGHT", 0, 0)
	UI.SetColor(accent, C.gold500)

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
local function applyTip(owner, icon, titleText, bodyText)
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
	t.tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 8, 0)
	t.tip:Show(); t.tip:Raise()
end

function W.ShowSpellTip(owner, spellID)
	if not spellID then return end
	local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
	local tx = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
	local ds = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
	applyTip(owner, tx or 136243, nm or ("Spell " .. tostring(spellID)), ds)
end

function W.ShowTextTip(owner, title, body)
	applyTip(owner, nil, title, body)
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
	local boxbg = box:CreateTexture(nil, "BACKGROUND")
	boxbg:SetAllPoints(box); boxbg:SetColorTexture(0, 0, 0, 0)
	local edges = UI.Border(box, L.mid, 1, "OVERLAY")

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
	b:SetWidth(BOX + M.checkLabelGap + math.ceil(lbl:GetStringWidth()) + 2)

	local val = (o.get and o.get()) or o.value or false
	local function apply(on)
		if on then
			UI.SetColor(boxbg, C.gold500)
			for _, e in ipairs(edges) do UI.SetColor(e, C.gold500) end
			check:Show()
		else
			boxbg:SetColorTexture(0, 0, 0, 0)
			for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end
			check:Hide()
		end
	end
	apply(val)

	b:SetScript("OnEnter", function()
		if not val then for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end end
		lbl:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
		if o.tooltip then W.ShowTextTip(b, o.label, o.tooltip) end
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
--  Segment — compact multi-toggle (gold-filled active cell). ONE component,
--  used multiple times: Raid|Group context switch AND inside|outside.
--  o = { label?, options = {{value,label},…} (or strings), get, set, value,
--        width?, cellH? }. With label -> label on top (like Select/Slider), bar
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
	UI.Fill(bar, C.ink700)
	UI.Border(bar, L.mid, 1, "OVERLAY")
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
				c._fill:SetColorTexture(0, 0, 0, 0)
				c._txt:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b)
			end
		end
	end
	for i, op in ipairs(opts) do
		local cell = CreateFrame("Button", nil, bar)
		local fill = cell:CreateTexture(nil, "BACKGROUND")
		fill:SetAllPoints(cell); fill:SetColorTexture(0, 0, 0, 0)
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
		cell:SetScript("OnEnter", function() if cell._val ~= cur then txt:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b) end end)
		cell:SetScript("OnLeave", function() if cell._val ~= cur then txt:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b) end end)
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
	UI.Fill(btn, C.ink700)
	local edges = UI.Border(btn, L.soft, 1, "OVERLAY")
	f._control = btn

	local lbl = UI.FS(btn, "selectText", C.gold300)
	lbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
	lbl:SetPoint("RIGHT", btn, "RIGHT", -12, 0)
	lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)

	local cur = (o.get and o.get()) or ""
	local listening = false
	local function fmt(k)
		if k == "" then return o.placeholder or T("Set key …") end
		if o.format then return o.format(k) end
		return k
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
	end
	refresh()

	local function stopListen()
		if not listening then return end
		listening = false
		btn:EnableKeyboard(false)
		btn:EnableMouseWheel(false)
		-- Do NOT set propagation to true in the same key event (would pass an ESC through
		-- -> Shell closes). Reset ONE frame later: then the idle state is clean
		-- (propagate=true -> the button no longer eats movement/action bar), but the ESC
		-- that just triggered stopListen stays consumed.
		C_Timer.After(0, function() if not listening then btn:SetPropagateKeyboardInput(true) end end)
		for _, e in ipairs(edges) do UI.SetColor(e, L.soft) end
		refresh()
	end
	local function startListen()
		if listening then return end
		listening = true
		btn:EnableKeyboard(true)
		btn:EnableMouseWheel(true)
		btn:SetPropagateKeyboardInput(false) -- consume keys (ESC would otherwise close the Shell)
		for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end
		refresh()
	end
	local function commit(key)
		cur = key
		stopListen()
		if o.set then o.set(key) end
	end

	btn:SetScript("OnClick", function(_, button)
		if not listening then startListen(); return end
		if button == "RightButton" then stopListen()
		elseif button == "LeftButton" then commit(kbWithMods("BUTTON1"))
		elseif button == "MiddleButton" then commit(kbWithMods("BUTTON3"))
		elseif button == "Button4" then commit(kbWithMods("BUTTON4"))
		elseif button == "Button5" then commit(kbWithMods("BUTTON5")) end
	end)
	btn:SetScript("OnKeyDown", function(_, key)
		if not listening then return end
		if key == "ESCAPE" then stopListen(); return end
		if KB_IGNORE[key] then return end
		commit(kbWithMods(key))
	end)
	btn:SetScript("OnMouseWheel", function(_, delta)
		if not listening then return end
		commit(kbWithMods(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
	end)
	btn:SetScript("OnEnter", function() if not listening then for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end end end)
	btn:SetScript("OnLeave", function() if not listening then for _, e in ipairs(edges) do UI.SetColor(e, L.soft) end end end)
	btn:HookScript("OnHide", stopListen)

	f.SetValueExternal = function(_, v) cur = v or ""; refresh() end
	f.SetWidgetEnabled = function(_, on)
		f:SetAlpha(on and 1 or 0.35)
		btn:EnableMouse(on)
		if not on then stopListen() end
	end
	return f
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
	UI.Fill(cp, C.ink850)
	UI.Border(cp, L.strong, 1, "OVERLAY")

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
	UI.Fill(hexBox, C.ink700)
	UI.Border(hexBox, L.soft, 1, "OVERLAY")
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
--  o = {label, get -> r,g,b, set(r,g,b)}. Layout like the checkbox (box left,
--  label right) so it sits interchangeably in rows/cells. Dimensions from UI.WIDGET.
-- ---------------------------------------------------------------------------
function W.ColorSwatch(parent, o)
	local BOX = M.checkBox
	local b = CreateFrame("Button", nil, parent)

	local box = CreateFrame("Frame", nil, b)
	box:SetSize(BOX, BOX)
	-- Color surface slightly inset so the gold frame holds it cleanly.
	local sw = box:CreateTexture(nil, "ARTWORK")
	sw:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
	sw:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
	local edges = UI.Border(box, L.mid, 1, "OVERLAY")

	-- Two modes: field=true -> label ON TOP (grid-aligned with dropdowns, via SetAllPoints
	-- into a field cell); otherwise -> swatch + label next to it on the right (compact row).
	local lbl
	if o.field then
		-- Field mode: label ON TOP, swatch as a compact color chip in the control band below.
		-- Height = controlH (same line as a dropdown), width compact (swatchFieldW)
		-- -> sits cleanly in the row without dominating the column as a full bar.
		b:SetSize(M.swatchFieldW, M.controlH + M.fieldGap) -- only chip width -> hit area = chip (NOT the whole cell)
		box:SetSize(M.swatchFieldW, M.controlH)
		box:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -M.fieldGap)
		lbl = UI.FS(b, "fieldLabel", C.gold250)
		lbl:SetText(o.label or "")
		lbl:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		lbl:SetJustifyH("LEFT")
	else
		b:SetHeight(BOX)
		box:SetPoint("LEFT", b, "LEFT", 0, 0)
		lbl = UI.FS(b, "checkLabel", C.textBody)
		lbl:SetText(o.label or "")
		lbl:SetPoint("LEFT", box, "RIGHT", M.checkLabelGap, 0)
		b:SetWidth(BOX + M.checkLabelGap + math.ceil(lbl:GetStringWidth()) + 2)
	end

	local function readRGB()
		if o.get then local r, g, bl = o.get(); return r or 1, g or 1, bl or 1 end
		return 1, 1, 1
	end
	local function paint() local r, g, bl = readRGB(); sw:SetColorTexture(r, g, bl, 1) end
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
		if not o.field then lbl:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b) end
	end)
	b:SetScript("OnLeave", function()
		for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end
		if not o.field then lbl:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b) end
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
	UI.Fill(box, C.ink700)
	UI.Border(box, L.mid, 1, "OVERLAY")
	box:SetFont(UI.FONT.hankenMed, 15, "")
	box:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
	box:SetTextInsets(10, 10, 0, 0)
	box:SetAutoFocus(false)
	if o.get then box:SetText(o.get() or "") end

	local ph
	if o.placeholder then
		ph = UI.FS(box, "label", C.textMuted)
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
	UI.Fill(f, C.ink700)
	UI.Border(f, L.mid, 1, "OVERLAY")

	local sf = CreateFrame("ScrollFrame", nil, f)
	sf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
	sf:EnableMouseWheel(true)

	local edit = CreateFrame("EditBox", nil, sf)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFont(UI.FONT.hankenMed, 14, "")
	edit:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
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
--  Button — primary (gold) / ghost (border) / danger (red). o = {text,variant,
--  onClick,width}. Height 38, width from text + padding if not set.
-- ---------------------------------------------------------------------------
-- Font weight per variant (like the prototype: primary bold/700, ghost 500,
-- danger 600). Size stays that of the btn role.
local BTN_SIZE = UI.ROLE.btn[2]
local BTN_VARIANTS = {
	primary = {
		bg = C.gold500, bgHover = C.gold400,
		txt = C.onGold, txtHover = C.onGold,
		line = C.gold500, lineHover = C.gold400, pad = 26, font = UI.FONT.hankenBold,
	},
	ghost = {
		bg = nil, bgHover = nil,
		txt = C.textHeading, txtHover = C.textStrong,
		line = L.mid, lineHover = L.strong, pad = 22, font = UI.FONT.hankenMed,
	},
	danger = {
		bg = L.dangerWash, bgHover = { r = C.danger500.r, g = C.danger500.g, b = C.danger500.b, a = 0.20 },
		txt = C.danger500, txtHover = C.danger500,
		line = L.dangerLine, lineHover = C.danger500, pad = 22, font = UI.FONT.hankenSemi,
	},
}

function W.Button(parent, o)
	local variant = o.variant or "primary"
	local v = BTN_VARIANTS[variant]
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(M.buttonH)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(b)

	-- primary carries a vertical gold gradient (lighter on top -> metallic
	-- shimmer like the wordmark); hover shifts the gradient one step lighter.
	local function paintBg(hover)
		if variant == "primary" then
			bg:SetColorTexture(1, 1, 1, 1)
			local top = hover and C.gold200 or C.gold300
			local bot = hover and C.gold400 or C.gold500
			bg:SetGradient("VERTICAL",
				CreateColor(bot.r, bot.g, bot.b, 1),
				CreateColor(top.r, top.g, top.b, 1))
		elseif v.bg then
			UI.SetColor(bg, hover and v.bgHover or v.bg)
		else
			bg:SetColorTexture(0, 0, 0, 0)
		end
	end
	paintBg(false)

	local edges = UI.Border(b, v.line, 1, "OVERLAY")
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
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)

	b:SetWidth(o.width or (math.ceil(txt:GetStringWidth()) + v.pad * 2))

	-- Cold-start guarantee: if the button becomes VISIBLE and its text still has 0 width (glyph
	-- cache was cold at build time -> esp. the primary "Apply" in the lazily built color picker),
	-- re-set weight + text once after ONE frame (now visible -> glyphs rasterized).
	if (o.text or "") ~= "" then
		b:HookScript("OnShow", function()
			if (txt:GetStringWidth() or 0) > 0 then return end
			C_Timer.After(0, function()
				if (txt:GetStringWidth() or 0) > 0 then return end
				if txt:SetFont(v.font, BTN_SIZE, "") == false then UI:SetFont(txt, "btn") end
				txt:SetText(o.text)
				b:SetWidth(o.width or (math.ceil(txt:GetStringWidth()) + v.pad * 2))
			end)
		end)
	end

	b:SetScript("OnEnter", function()
		paintBg(true)
		for _, e in ipairs(edges) do UI.SetColor(e, v.lineHover) end
		txt:SetTextColor(v.txtHover.r, v.txtHover.g, v.txtHover.b)
	end)
	b:SetScript("OnLeave", function()
		paintBg(false)
		for _, e in ipairs(edges) do UI.SetColor(e, v.line) end
		txt:SetTextColor(v.txt.r, v.txt.g, v.txt.b)
	end)
	if o.onClick then b:SetScript("OnClick", o.onClick) end
	b._txt = txt
	return b
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
	UI.Fill(c, C.ink600)
	UI.Border(c, L.soft, 1)
	return c
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
