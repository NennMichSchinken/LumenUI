local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell Widget-Toolkit (Phase 2)
--  Wiederverwendbare Bausteine nach dem Lumen Design System (Shell/Tokens).
--  Vorbild-API: EllesmereUIs WidgetFactory (`:Slider/:Dropdown/:Toggle(parent,
--  …, get, set)`), Look 1:1 aus dem Prototyp (components/core/*.jsx).
--
--  Konvention: jedes Widget ist SELBST-DIMENSIONIERT (kennt seine Höhe) und
--  nimmt eine Options-Tabelle `o`. Daten kommen über `o.get()`/`o.set(v)`
--  (oder ein statisches `o.value`). Volle Breite = parent über TOPLEFT/RIGHT
--  ankern; feste Breite via `o.width`. Mehrspaltige Reihen baut der Aufrufer
--  mit W.Row(...) (gleichbreite Zellen).
-- ===========================================================================

local UI = ns.UI
local C, L, S, M = UI.C, UI.line, UI.S, UI.WIDGET

local W = {}
ns.W = W

-- Popover-Host + Sammelliste für Select-Menüs. Selects in einem ScrollFrame würden
-- vom Clipping abgeschnitten -> ihre Menüs floaten an einem nicht-geclippten Host
-- (von der Shell auf das Panel gesetzt). Die Shell übergibt pro Screen eine frische
-- Sammelliste und räumt die vorige beim Tab-Wechsel auf (kein Leak).
W._menuHost = nil
W._popovers = nil
function W.SetMenuHost(frame) W._menuHost = frame end
function W.CapturePopovers(list) W._popovers = list end

local CONTROL_H = M.controlH

-- ---------------------------------------------------------------------------
--  Interne Helfer
-- ---------------------------------------------------------------------------
local function clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Gold-Chevron (nach unten) aus zwei Linien — Unicode ▼ ist im Font nicht sicher
-- (gleiche Begründung wie das Close-X im Chrome).
local function chevron(parent, col)
	local a = parent:CreateLine(nil, "OVERLAY")
	local b = parent:CreateLine(nil, "OVERLAY")
	a:SetThickness(1.5); b:SetThickness(1.5)
	local function setCol(c)
		a:SetColorTexture(c.r, c.g, c.b, c.a or 1)
		b:SetColorTexture(c.r, c.g, c.b, c.a or 1)
	end
	setCol(col)
	-- relativ zum eigenen 12x8-Anker (CENTER)
	a:SetStartPoint("CENTER", parent, -4, 2); a:SetEndPoint("CENTER", parent, 0, -2)
	b:SetStartPoint("CENTER", parent, 0, -2); b:SetEndPoint("CENTER", parent, 4, 2)
	return setCol
end

-- ---------------------------------------------------------------------------
--  SectionDivider — zentrierte Cinzel-Überschrift mit symmetrisch ausfadenden
--  Gold-Rules. Primärer Seiten-Gliederer. Höhe ~28.
-- ---------------------------------------------------------------------------
function W.SectionDivider(parent, text, small)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.dividerH)
	local strongA = small and 0.30 or 0.45 -- kleinere Unter-Überschrift = dezentere Linien
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
--  Field — Gold-Label über einem Control. Gibt (container, contentTopYOffset).
--  Der Aufrufer ankert sein Control bei TOPLEFT/RIGHT, container, ..., 0, yOff.
-- ---------------------------------------------------------------------------
local function fieldLabel(parent, text)
	local lbl = UI.FS(parent, "fieldLabel", C.gold250)
	lbl:SetText(text)
	lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	lbl:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	lbl:SetJustifyH("LEFT")
	return lbl, -M.fieldGap -- yOffset für das darunterliegende Control
end

-- ---------------------------------------------------------------------------
--  Slider — Gold-Track, Label oben, Min/Max an den Enden, Wert-Box darunter.
--  Pointer-getrieben (kein natives Slider-Frame). o = {label,min,max,step,
--  get,set,value,unit,width}. Höhe ~80.
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

	-- Track-Reihe: [min] —— track —— [max]
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

	-- Wert-Box darunter (zentriert) — editierbare EditBox: anklicken, Zahl
	-- eintippen, Enter bestätigt (auf Min/Max + Schrittweite geclampt), Esc verwirft.
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
	local typing = false -- true während die EditBox fokussiert ist (kein Clobbern)

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

	-- EditBox: getippten Wert parsen (führende Zahl, auch negativ), runden,
	-- clampen, übernehmen. Focus färbt den Rand kräftiger.
	box:SetScript("OnEditFocusGained", function(self)
		typing = true
		for _, e in ipairs(boxEdges) do UI.SetColor(e, L.strong) end
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		typing = false
		for _, e in ipairs(boxEdges) do UI.SetColor(e, L.soft) end
		self:SetText(cur .. unit) -- auf den kanonischen Stand zurücksetzen
	end)
	-- Live-Clamp auf Max schon beim Tippen: 5555 springt sofort auf den Max-Wert,
	-- nicht erst bei Enter (Florian-Feedback). userInput-Flag verhindert Rekursion
	-- mit dem eigenen SetText; Min wird erst bei Enter geclampt (Zwischeneingaben).
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
	-- Thumb selbst greifbar machen: am Anschlag (0/100 %) ragt das Viereck zur Hälfte über
	-- den Track hinaus — dieser Teil war bisher tot (nur der Track war klickbar). Mouse-enabled
	-- + 2px größere Trefferfläche (rein klickbar, optisch unverändert) -> leicht zu greifen.
	thumb:EnableMouse(true)
	thumb:SetHitRectInsets(-2, -2, -2, -2)
	thumb:SetScript("OnMouseDown", beginDrag)
	thumb:SetScript("OnMouseUp", endDrag)
	-- Track-Breite steht erst nach dem Layout fest -> bei Größenänderung neu zeichnen.
	track:SetScript("OnSizeChanged", function() visual(cur) end)

	visual(cur)
	f.SetValueExternal = function(_, v) cur = v; visual(v) end
	-- Ausgrauen + Interaktion sperren (für abhängige Sektionen, z.B. „Name anzeigen" aus).
	f.SetWidgetEnabled = function(_, on)
		f:SetAlpha(on and 1 or 0.35)
		track:EnableMouse(on)
		box:EnableMouse(on)
		if not on then box:ClearFocus() end
	end
	return f
end

-- ---------------------------------------------------------------------------
--  Select (Dropdown) — Gold-Inset-Header + Popover-Menü. o = {label?,options,
--  get,set,value,width,tile?}. options: Strings ODER {value,label}. Höhe:
--  ohne label = 40, mit label = 62.
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
	f._control = btn -- Anker für „Checkbox direkt neben dem Control" (vertikal bündig)

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
		else lbl:SetText(o.placeholder or "Auswählen"); lbl:SetTextColor(C.textMuted.r, C.textMuted.g, C.textMuted.b) end
	end
	refreshLabel()

	-- Popover-Menü (floatet über allem) + Vollbild-Closer für Klick-außerhalb.
	-- Host = der von der Shell gesetzte, NICHT-geclippte Menü-Host (das Panel);
	-- nötig, weil Selects im ScrollFrame liegen und dessen Clipping das Popover
	-- sonst abschneiden würde. Fallback ohne Shell: an f (für Nicht-Scroll-Kontexte).
	-- Der Host erbt die Panel-Scale (0.74); Anker auf btn funktioniert frame-übergreifend.
	-- Die Shell sammelt die Popover je Screen ein (W.CapturePopovers) und räumt sie
	-- beim Neuaufbau auf -> kein Leak trotz Host-Parenting.
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

	local function closeMenu()
		menu:Hide(); closer:Hide()
		for _, e in ipairs(edges) do UI.SetColor(e, L.soft) end
	end
	closer:SetScript("OnClick", closeMenu)

	-- Menü-Zeilen einmalig bauen. Klare Trennung gewählt vs. überfahren:
	--  • aktive (gewählte) Zeile -> Gold-Balken LINKS + Gold-Text (bleibt sichtbar)
	--  • überfahrene Zeile       -> warmer Braun-Wash (inkTint) + heller Text
	-- Der Gold-Balken markiert dauerhaft die Auswahl, der Braun-Wash nur den Hover
	-- — so sehen Selected und Hover nicht mehr fast gleich aus (Florian-Feedback).
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
	-- Optionen in eine SCROLL-Liste: bei vielen Einträgen (z.B. Balken-/Schild-Texturen aus
	-- anderen Addons/LSM) nur N Zeilen sichtbar + Mausrad/Scrollbalken, statt das Menü über
	-- den ganzen Schirm zu ziehen. Kurze Listen (<= maxRows) zeigen alles, ohne Scrollbalken.
	local maxRows = M.selectMaxRows
	local stride  = rowH + gap
	local needScr = #opts > maxRows
	local visN    = needScr and maxRows or math.max(1, #opts)
	local listH   = math.max(rowH, visN * stride - gap)

	local sf = CreateFrame("ScrollFrame", nil, menu)
	sf:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -pad)
	sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -(pad + (needScr and (M.spScrollW + M.spScrollGap) or 0)), pad)
	sf:EnableMouseWheel(needScr)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf:SetScript("OnSizeChanged", function(self2, w) child:SetWidth(w or self2:GetWidth() or 1) end)

	local items = {}
	local prev
	for _, op in ipairs(opts) do
		local item = CreateFrame("Button", nil, child)
		item:SetHeight(rowH)
		item:SetPoint("LEFT", child, "LEFT", 0, 0)
		item:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		if prev then item:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
		else item:SetPoint("TOP", child, "TOP", 0, 0) end
		local wash = item:CreateTexture(nil, "BACKGROUND")
		wash:SetAllPoints(item)
		wash:SetColorTexture(0, 0, 0, 0)
		-- Gold-Balken links (Auswahl-Marker), volle Zeilenhöhe.
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
		item:SetScript("OnEnter", function(self) paintItem(self, true) end)
		item:SetScript("OnLeave", function(self) paintItem(self, false) end)
		item:SetScript("OnClick", function(self)
			cur = self._val
			refreshLabel()
			closeMenu()
			if o.set then o.set(cur) end
		end)
		items[#items + 1] = item
		prev = item
	end
	child:SetHeight(math.max(1, #opts * stride - gap))
	menu:SetHeight(listH + pad * 2)
	menu._paintItem, menu._items = paintItem, items

	-- Scrollbalken (nur wenn nötig) — Muster aus W.SpellPicker: Mausrad + ziehbarer Thumb.
	if needScr then
		local sbTrack = CreateFrame("Frame", nil, menu)
		sbTrack:SetWidth(M.spScrollW)
		sbTrack:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -pad, -pad)
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

	local function openMenu()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -6)
		menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -6)
		-- Zeilen-Optik auf den aktuellen Stand bringen (Gold-Balken auf gewählter Zeile)
		for _, item in ipairs(menu._items) do menu._paintItem(item, false) end
		closer:Show(); menu:Show()
		if menu._updateBar then menu._updateBar() end
		for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end
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

	-- Fast-Preview (OPT-IN über o.wheelPreview — nur Textur-Dropdowns): Mausrad über dem
	-- GESCHLOSSENEN Dropdown blättert live durch die Optionen (statt die Shell zu scrollen).
	-- Ohne wheelPreview konsumiert der Button das Rad NICHT -> die Shell scrollt normal.
	-- Throttle: Label sofort, aber das Profil-Schreiben (o.set -> Relayout) leading-edge +
	-- gedrosselt -> max ~alle 50 ms ein Re-Render; der zuletzt gewählte Wert landet immer im Profil.
	if o.wheelPreview then
		local PREVIEW_THROTTLE = 0.05
		local lastApply, pendingVal, scheduled = 0, nil, false
		local function cycle(delta)
			if #opts == 0 then return end
			local idx = 1
			for i, op in ipairs(opts) do if op.value == cur then idx = i; break end end
			idx = math.max(1, math.min(#opts, idx - delta)) -- Rad hoch = vorige, runter = nächste Option
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
--  SpellPicker — Button öffnet ein suchbares, SCROLLBARES Auswahl-Popover.
--  Das ist die „echte Typeahead-Suche": W.Select kann nicht scrollen, hier
--  laufen 30–60 Spells live gefiltert in einer Scroll-Liste (Suchfeld oben +
--  Mausrad/Scrollbalken). o = {
--    text,                 -- Button-Beschriftung („+ Spell hinzufügen")
--    width,                -- Button-Breite (optional, Default M.spBtnW)
--    fetch  = function() return { {id,name,icon}, ... } end,  -- Kandidaten,
--             -- vom Aufrufer bereits dedupliziert/whitelist-gefiltert, alphabetisch.
--    onPick = function(id),  -- gewählter Spell.
--  }
--  Popover floatet am _menuHost (nicht-geclippt, wie W.Select) + wird über
--  W._popovers eingesammelt und beim Tab-Wechsel aufgeräumt (kein Leak).
-- ---------------------------------------------------------------------------
function W.SpellPicker(parent, o)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.buttonH)
	f:SetWidth(o.width or M.spBtnW)

	local closeMenu -- forward-Deklaration (Zeilen-Klick ruft sie)

	-- Auslöser-Button: Inset-Feld mit Gold-Rand + Gold-Text (wie im Mockup).
	local btn = CreateFrame("Button", nil, f)
	btn:SetAllPoints(f)
	UI.Fill(btn, C.ink700)
	local bEdges = UI.Border(btn, L.mid, 1, "OVERLAY")
	local bTxt = UI.FS(btn, "btn", C.gold300)
	bTxt:SetFont(UI.FONT.hankenSemi, 16, "")
	bTxt:SetText(o.text or "+ Hinzufügen")
	bTxt:SetPoint("CENTER", btn, "CENTER", 0, 0)
	f._control = btn

	-- Popover (Menü + Vollbild-Closer) am nicht-geclippten Host, wie W.Select.
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

	-- Suchfeld (typeahead) ------------------------------------------------
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
	ph:SetText("Spell suchen …")
	ph:SetPoint("LEFT", search, "LEFT", 10, 0)

	-- Scroll-Liste --------------------------------------------------------
	local sf = CreateFrame("ScrollFrame", nil, menu)
	sf:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -(M.spPad + M.spScrollW + M.spScrollGap), M.spPad)
	sf:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf:SetScript("OnSizeChanged", function(self2, w) child:SetWidth(w or self2:GetWidth() or 1) end)

	local emptyFS = UI.FS(menu, "label", C.textMuted)
	emptyFS:SetText("(keine Treffer)")
	emptyFS:SetPoint("TOP", search, "BOTTOM", 0, -16)
	emptyFS:Hide()

	-- Scrollbalken (Muster aus dem Shell-ScrollFrame: Mausrad + ziehbarer Thumb).
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

	-- Zeilen-Pool (kein Frame-Churn beim Tippen): wiederverwendet, nur Text/Icon neu.
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
			W.ShowSpellTip(self2, self2._id) -- eigener Lumen-Tooltip
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

	-- Kandidatenliste EINMAL beim Öffnen holen (fetch scannt Zauberbuch + Talente —
	-- nicht pro Tastendruck wiederholen); Tippen filtert nur diese gecachte Liste.
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
		data = (o.fetch and o.fetch()) or {} -- einmal scannen, dann nur noch filtern
		search:SetText("") -- OnTextChanged feuert nur bei echter Änderung -> explizit:
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
--  Confirm — modaler Bestätigungs-Dialog. Dunkelt die Shell ab (Overlay über
--  dem Menü-Host = Panel) und zeigt eine zentrierte Karte mit Titel, Text und
--  zwei Buttons (Bestätigen = danger / Abbrechen = ghost). Klick auf die
--  abgedunkelte Fläche = Abbrechen. Singleton (einmal gebaut, je Aufruf neu
--  konfiguriert, wie der Color-Picker). Aufruf:
--    W.Confirm{ title, body, confirmText, cancelText, onConfirm, onCancel }
-- ---------------------------------------------------------------------------
local confirmDlg
local function buildConfirm()
	local host = W._menuHost or UIParent
	local overlay = CreateFrame("Button", nil, host)
	overlay:SetAllPoints(host)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:EnableMouse(true) -- schluckt Klicks auf die abgedunkelte Shell (modal)
	local dim = overlay:CreateTexture(nil, "BACKGROUND")
	dim:SetAllPoints(overlay)
	dim:SetColorTexture(0, 0, 0, M.confirmDim)
	overlay:Hide()

	local card = CreateFrame("Frame", nil, overlay)
	card:SetFrameStrata("FULLSCREEN_DIALOG")
	card:SetFrameLevel(overlay:GetFrameLevel() + 10)
	card:SetSize(M.confirmW, M.confirmH)
	card:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	card:EnableMouse(true) -- Klicks auf die Karte NICHT als „außerhalb" werten
	UI.Fill(card, C.ink550)
	UI.Border(card, L.strong, 1, "OVERLAY")
	local accent = card:CreateTexture(nil, "OVERLAY") -- Gold-Akzent oben (Signatur)
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

	local okBtn = W.Button(card, { text = "Bestätigen", variant = "danger", width = M.confirmBtnW })
	okBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -M.confirmPad, M.confirmPad)
	local cancelBtn = W.Button(card, { text = "Abbrechen", variant = "ghost", width = M.confirmBtnW })
	cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -M.confirmBtnGap, 0)

	confirmDlg = { overlay = overlay, card = card, title = title, body = body, ok = okBtn, cancel = cancelBtn }
	return confirmDlg
end

function W.Confirm(o)
	local dlg = confirmDlg or buildConfirm()
	dlg.title:SetText(o.title or "Bist du sicher?")
	dlg.body:SetText(o.body or "")
	dlg.ok._txt:SetText(o.confirmText or "Bestätigen")
	dlg.cancel._txt:SetText(o.cancelText or "Abbrechen")
	local function doCancel()
		dlg.overlay:Hide()
		if o.onCancel then o.onCancel() end
	end
	dlg.ok:SetScript("OnClick", function()
		dlg.overlay:Hide()
		if o.onConfirm then o.onConfirm() end
	end)
	dlg.cancel:SetScript("OnClick", doCancel)
	dlg.overlay:SetScript("OnClick", doCancel) -- Klick auf die abgedunkelte Fläche = Abbrechen
	dlg.overlay:Show()
	dlg.overlay:Raise()
end

-- ---------------------------------------------------------------------------
--  Tooltip — eigener, im Lumen-Design gestylter Tooltip (ersetzt den Blizzard-
--  GameTooltip in der GANZEN Shell). Singleton, Strata TOOLTIP (über Popovers).
--  Zwei Modi über EINE Karte: Spell (Icon + Name + C_Spell-Beschreibung) ODER
--  Text (Titel + Hinweistext, ohne Icon). Höhe wächst mit dem Text. Schrift über
--  die Rollen tipTitle/tipBody (UI.ROLE) -> zentral justierbar.
--    W.ShowSpellTip(owner, spellID) · W.ShowTextTip(owner, title, body) · W.HideTip()
-- ---------------------------------------------------------------------------
local tipObj
local function buildTip()
	local host = W._menuHost or UIParent
	local tip = CreateFrame("Frame", nil, host)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetWidth(M.tipW)
	tip:Hide()
	UI.Fill(tip, C.ink850) -- dunkler als Popover -> klarer Tooltip-Kontrast
	UI.Border(tip, L.strong, 1, "OVERLAY")
	local accent = tip:CreateTexture(nil, "OVERLAY") -- Gold-Akzent oben (Signatur)
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

-- Gemeinsamer Aufbau für beide Modi: icon=nil -> reiner Text-Tooltip.
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
		t.title:SetHeight(M.tipIcon); t.title:SetWordWrap(false) -- Name einzeilig neben dem Icon
	else
		t.title:SetPoint("TOPLEFT", t.tip, "TOPLEFT", M.tipPad, -M.tipPad)
		t.title:SetHeight(0); t.title:SetWordWrap(true)
	end
	t.title:SetText(titleText or "")

	-- Kopfhöhe = Icon-Höhe (Spell) bzw. Titel-Höhe (Text); danach optional der Text.
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
--  Checkbox — Gold-Füll-Toggle + Häkchen + Label, klickbare Zeile.
--  o = {label,get,set,value}. Maße aus UI.WIDGET.
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

	-- Häkchen: Blizzards Check-Textur, entsättigt + ink-getönt -> sauberer als
	-- selbstgezeichnete Linien (Florian-Feedback). Mittig, leicht über die Box
	-- hinaus (transparenter Rand der Textur) für gute Proportion.
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

-- ===========================================================================
--  Color-Picker (eigenes Popover im Lumen-Stil statt Blizzards ColorPickerFrame)
--  HSV-Modell: SV-Feld (Sättigung x / Helligkeit y) + Farbton-Leiste + Vorschau +
--  Hex-Eingabe + Übernehmen/Abbrechen. Singleton (einmal gebaut, wiederverwendet),
--  am Menü-Host (Panel) -> erbt Scale, nicht geclippt. Live-Vorschau über onChange.
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

local colorPicker -- Singleton-Frame (lazy)

local function buildColorPicker()
	local host = W._menuHost or UIParent
	local cp = CreateFrame("Frame", nil, host)
	cp:SetFrameStrata("FULLSCREEN_DIALOG")
	cp:EnableMouse(true) -- schluckt Klicks (nicht durch zum Closer)
	UI.Fill(cp, C.ink850)
	UI.Border(cp, L.strong, 1, "OVERLAY")

	-- Vollbild-Closer dahinter (Klick ausserhalb = übernehmen/schliessen).
	local closer = CreateFrame("Button", nil, host)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:SetFrameLevel(cp:GetFrameLevel() - 1)
	cp._closer = closer

	local pad = M.cpPad
	cp:SetSize(pad * 2 + M.cpSVW + M.cpGap + M.cpHueW, pad * 3 + M.cpSVH + M.cpPrevH + M.buttonH + 14)

	-- ---- SV-Feld (Sättigung x, Helligkeit y) ----
	local sv = CreateFrame("Frame", nil, cp)
	sv:SetSize(M.cpSVW, M.cpSVH)
	sv:SetPoint("TOPLEFT", cp, "TOPLEFT", pad, -pad)
	sv:EnableMouse(true)
	local svBase = sv:CreateTexture(nil, "BACKGROUND")     -- reine Hue-Farbe
	svBase:SetAllPoints(sv)
	local svWhite = sv:CreateTexture(nil, "ARTWORK")       -- links weiss -> rechts klar (Sättigung)
	svWhite:SetAllPoints(sv); svWhite:SetColorTexture(1, 1, 1, 1)
	svWhite:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))
	local svBlack = sv:CreateTexture(nil, "ARTWORK", nil, 1) -- unten schwarz -> oben klar (Helligkeit)
	svBlack:SetAllPoints(sv); svBlack:SetColorTexture(0, 0, 0, 1)
	svBlack:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))
	UI.Border(sv, L.mid, 1, "OVERLAY")
	local svMark = CreateFrame("Frame", nil, sv)
	svMark:SetSize(M.cpMarker, M.cpMarker)
	UI.Border(svMark, { r = 1, g = 1, b = 1, a = 1 }, 2, "OVERLAY")

	-- ---- Farbton-Leiste (6 Segmente, je vertikaler Gradient) ----
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
		-- oben = a (Segmentstart), unten = c2 -> min(unten)=c2, max(oben)=a
		seg:SetGradient("VERTICAL", CreateColor(c2[1], c2[2], c2[3], 1), CreateColor(a[1], a[2], a[3], 1))
	end
	UI.Border(hue, L.mid, 1, "OVERLAY")
	local hueMark = hue:CreateTexture(nil, "OVERLAY")
	hueMark:SetColorTexture(1, 1, 1, 1)
	hueMark:SetPoint("LEFT", hue, "LEFT", -2, 0)
	hueMark:SetPoint("RIGHT", hue, "RIGHT", 2, 0)
	hueMark:SetHeight(3)

	-- ---- Vorschau + Hex ----
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
	-- Übernehmen + Abbrechen unten links gruppiert, kleiner fester Abstand (cpBtnGap).
	local okBtn = W.Button(cp, { text = "Übernehmen", variant = "primary" })
	okBtn:SetPoint("BOTTOMLEFT", cp, "BOTTOMLEFT", pad, pad)
	local cancelBtn = W.Button(cp, { text = "Abbrechen", variant = "ghost" })
	cancelBtn:SetPoint("LEFT", okBtn, "RIGHT", M.cpBtnGap, 0)

	-- ---- State + Logik ----
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

	-- Hex-Eingabe
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
	okBtn:SetScript("OnClick", close) -- onChange war live -> nur schliessen
	cancelBtn:SetScript("OnClick", function()
		if cp._onCancel then cp._onCancel() end
		close()
	end)
	closer:SetScript("OnClick", close)

	cp._applyVisual = applyVisual
	return cp
end

-- o = { r,g,b, anchor?, onChange(r,g,b), onCancel() }. Öffnet den Singleton-Picker.
function W.OpenColorPicker(o)
	colorPicker = colorPicker or buildColorPicker()
	local cp = colorPicker
	-- Host kann sich seit dem Bau geändert haben (eigentlich nicht) — Parent sicherstellen.
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
--  ColorSwatch — Gold-gerahmtes Farbfeld + Label, öffnet den Lumen-ColorPicker.
--  o = {label, get -> r,g,b, set(r,g,b)}. Layout wie die Checkbox (Box links,
--  Label rechts), damit es austauschbar in Reihen/Zellen sitzt. Maße aus UI.WIDGET.
-- ---------------------------------------------------------------------------
function W.ColorSwatch(parent, o)
	local BOX = M.checkBox
	local b = CreateFrame("Button", nil, parent)

	local box = CreateFrame("Frame", nil, b)
	box:SetSize(BOX, BOX)
	-- Farbfläche leicht eingerückt, damit der Gold-Rahmen sie sauber fasst.
	local sw = box:CreateTexture(nil, "ARTWORK")
	sw:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
	sw:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
	local edges = UI.Border(box, L.mid, 1, "OVERLAY")

	-- Zwei Modi: field=true -> Label OBEN (rasterbündig zu Dropdowns, per SetAllPoints
	-- in eine Feld-Zelle); sonst -> Swatch + Label rechts daneben (kompakte Zeile).
	local lbl
	if o.field then
		-- Feld-Modus: Label OBEN, Swatch als kompakter Farb-Chip im Control-Band darunter.
		-- Höhe = controlH (gleiche Flucht wie ein Dropdown), Breite kompakt (swatchFieldW)
		-- -> sitzt sauber in der Reihe, ohne die Spalte als Vollbalken zu dominieren.
		b:SetSize(M.swatchFieldW, M.controlH + M.fieldGap) -- nur Chip-Breite -> Klickfläche = Chip (NICHT die ganze Zelle)
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
--  Hint — gedämpfte Fließtext-Zeile (Caption), wortumbrechend in eigenem Frame
--  (damit der Layout-Stack sie wie ein normales Widget mit Höhe behandeln kann).
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
--  Button — primary (Gold) / ghost (Rand) / danger (rot). o = {text,variant,
--  onClick,width}. Höhe 38, Breite aus Text + Padding falls nicht gesetzt.
-- ---------------------------------------------------------------------------
-- Schriftschnitt je Variante (wie im Prototyp: primary fett/700, ghost 500,
-- danger 600). Größe bleibt die der btn-Rolle.
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

	-- primary trägt einen vertikalen Gold-Gradient (oben heller -> metallischer
	-- Schimmer wie die Wortmarke); Hover schiebt den Gradient eine Stufe heller.
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
	local okFont = txt:SetFont(v.font, BTN_SIZE, "") -- Schnitt je Variante (s. BTN_VARIANTS)
	txt:SetText(o.text or "")
	-- Selbst-heilend: lädt die Variant-Font nicht (SetFont=false) oder rendert sie den
	-- Text nicht (0 Breite trotz Inhalt — z.B. fehlende Glyphen wie „ü" in einem Schnitt),
	-- auf die Rollen-Font (btn = hankenSemi, rendert Umlaute zuverlässig) zurückfallen.
	-- So bleibt der bewusste Variant-Schnitt erhalten, wo er funktioniert.
	if (o.text or "") ~= "" and (okFont == false or txt:GetStringWidth() <= 0) then
		UI:SetFont(txt, "btn", v.txt)
		txt:SetText(o.text)
	end
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)

	b:SetWidth(o.width or (math.ceil(txt:GetStringWidth()) + v.pad * 2))

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
--  IconTile — beveled Gold-Chip (Signatur-Element) mit Cinzel-Letter. Für
--  Spell-/Modul-Kacheln in Listen. o = {size,letter}.
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
--  Card — angehobener Container (Surface #171411, Gold-Hairline). Höhe setzt
--  der Aufrufer; Inhalt direkt in die Card oder mit eigenem Padding ankern.
-- ---------------------------------------------------------------------------
function W.Card(parent)
	local c = CreateFrame("Frame", nil, parent)
	UI.Fill(c, C.ink600)
	UI.Border(c, L.soft, 1)
	return c
end

-- ---------------------------------------------------------------------------
--  GroupPanel — umrandeter Bereich mit Überschrift + optionalem Inline-Control
--  rechts (z.B. „Anzeigen"-Toggle). o = {title}. Gibt (frame, contentFrame).
--  Höhe setzt der Aufrufer (frame:SetHeight); contentFrame füllt darunter.
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

	-- Inhaltsbereich unter der Überschrift, mit Card-Padding.
	local content = CreateFrame("Frame", nil, g)
	content:SetPoint("TOPLEFT", g, "TOPLEFT", S.cardPad, M.groupContentY)
	content:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -S.cardPad, S.cardPad)

	g._title, g._content = title, content
	-- Ankerpunkt für ein optionales Header-Right-Control.
	g._headerRightAnchor = function(ctrl)
		ctrl:SetParent(g)
		ctrl:ClearAllPoints()
		ctrl:SetPoint("RIGHT", g, "TOPRIGHT", -S.cardPad, 0)
		ctrl:SetPoint("TOP", title, "TOP", 0, 4)
	end
	return g, content
end

-- ---------------------------------------------------------------------------
--  Row — N gleichbreite Zellen nebeneinander (entspricht prototype row3/row2).
--  Gibt eine Liste von Zellen-Frames zurück; das Widget je Zelle hineinankern.
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
	-- Breiten-Verteilung erst bei bekannter Reihenbreite (Anker-abhängig).
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
