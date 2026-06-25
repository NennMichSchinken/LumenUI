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
function W.SectionDivider(parent, text)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.dividerH)
	local head = UI.FS(f, "sectionHead", C.gold300)
	head:SetText(text)
	head:SetPoint("CENTER", f, "CENTER", 0, 0)

	local lr = UI.GradientLine(f, "out", 0.45, 0.0)
	lr:SetPoint("RIGHT", head, "LEFT", -M.dividerGap, 0)
	lr:SetPoint("LEFT", f, "LEFT", 0, 0)
	lr:SetPoint("TOP", head, "CENTER", 0, 0)
	local rr = UI.GradientLine(f, "in", 0.45, 0.0)
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
	cap:SetPoint("TOP", f, "TOP", 0, -2)

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
	UI.SetColor(bg, C.ink700)

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
	track:SetScript("OnMouseDown", function(self)
		self:SetScript("OnUpdate", onUpd)
		commit(valFromCursor())
	end)
	track:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	track:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	-- Track-Breite steht erst nach dem Layout fest -> bei Größenänderung neu zeichnen.
	track:SetScript("OnSizeChanged", function() visual(cur) end)

	visual(cur)
	f.SetValueExternal = function(_, v) cur = v; visual(v) end
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
	-- An f gehängt (nicht UIParent): erbt die Panel-Scale (0.74) und räumt sich
	-- automatisch auf, wenn das Widget beim Tab-Wechsel versteckt wird.
	local closer = CreateFrame("Button", nil, f)
	closer:SetAllPoints(UIParent)
	closer:SetFrameStrata("FULLSCREEN_DIALOG")
	closer:Hide()

	local menu = CreateFrame("Frame", nil, f)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(closer:GetFrameLevel() + 10)
	menu:Hide()
	UI.Fill(menu, C.ink550)
	UI.Border(menu, L.mid, 1, "OVERLAY")

	local function closeMenu()
		menu:Hide(); closer:Hide()
		for _, e in ipairs(edges) do UI.SetColor(e, L.soft) end
	end
	closer:SetScript("OnClick", closeMenu)

	-- Menü-Zeilen einmalig bauen. Drei Zustände: hover (heller Gold-Wash + Gold-
	-- Text), active (dezenter Wash + Gold-Text), off (kein Wash + Parchment-Text).
	-- Der Wash wird über Alpha gesteuert (NICHT Show/Hide — sonst kein Hover-
	-- Feedback auf nicht-aktiven Zeilen).
	local pad, rowH, gap = 6, 34, 2
	-- Hover = warmer Braunton (inkTint), hebt sich dezent vom Menü-Grund (ink550)
	-- ab — KEIN kräftiges Gold (Florian-Feedback). Gold bleibt nur als zarter
	-- Marker auf der aktiven (gewählten) Zeile.
	local function setItemState(item, st)
		if st == "hover" then
			item._wash:SetColorTexture(C.inkTint.r, C.inkTint.g, C.inkTint.b, 1)
			item._txt:SetTextColor(C.gold100.r, C.gold100.g, C.gold100.b)
		elseif st == "active" then
			item._wash:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, 0.10)
			item._txt:SetTextColor(C.gold250.r, C.gold250.g, C.gold250.b)
		else
			item._wash:SetColorTexture(0, 0, 0, 0)
			item._txt:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
		end
	end
	local prev
	for _, op in ipairs(opts) do
		local item = CreateFrame("Button", nil, menu)
		item:SetHeight(rowH)
		item:SetPoint("LEFT", menu, "LEFT", pad, 0)
		item:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
		if prev then item:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
		else item:SetPoint("TOP", menu, "TOP", 0, -pad) end
		local wash = item:CreateTexture(nil, "BACKGROUND")
		wash:SetAllPoints(item)
		wash:SetColorTexture(0, 0, 0, 0)
		local itxt = UI.FS(item, "selectText", C.textStrong)
		itxt:SetPoint("LEFT", item, "LEFT", 10, 0)
		itxt:SetText(op.label)
		item._wash, item._txt, item._val = wash, itxt, op.value
		item:SetScript("OnEnter", function(self) setItemState(self, "hover") end)
		item:SetScript("OnLeave", function(self) setItemState(self, self._val == cur and "active" or "off") end)
		item:SetScript("OnClick", function(self)
			cur = self._val
			refreshLabel()
			closeMenu()
			if o.set then o.set(cur) end
		end)
		prev = item
	end
	menu:SetHeight(#opts * rowH + (#opts - 1) * gap + pad * 2)
	menu._setItemState = setItemState

	local function openMenu()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -6)
		menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -6)
		-- aktive Zeile markieren
		for _, item in ipairs({ menu:GetChildren() }) do
			if item._wash then menu._setItemState(item, item._val == cur and "active" or "off") end
		end
		closer:Show(); menu:Show()
		for _, e in ipairs(edges) do UI.SetColor(e, L.strong) end
	end

	btn:SetScript("OnClick", function()
		if menu:IsShown() then closeMenu() else openMenu() end
	end)
	btn:SetScript("OnEnter", function()
		if not menu:IsShown() then for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end end
	end)
	btn:SetScript("OnLeave", function()
		if not menu:IsShown() then for _, e in ipairs(edges) do UI.SetColor(e, L.soft) end end
	end)
	btn:HookScript("OnHide", closeMenu)

	f.SetValueExternal = function(_, v) cur = v; refreshLabel() end
	return f
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
	end)
	b:SetScript("OnLeave", function()
		if not val then for _, e in ipairs(edges) do UI.SetColor(e, L.mid) end end
		lbl:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b)
	end)
	b:SetScript("OnClick", function()
		val = not val
		apply(val)
		if o.set then o.set(val) end
	end)
	b.SetValueExternal = function(_, v) val = v; apply(v) end
	return b
end

-- ---------------------------------------------------------------------------
--  Button — primary (Gold) / ghost (Rand) / danger (rot). o = {text,variant,
--  onClick,width}. Höhe 38, Breite aus Text + Padding falls nicht gesetzt.
-- ---------------------------------------------------------------------------
local BTN_VARIANTS = {
	primary = {
		bg = C.gold500, bgHover = C.gold400,
		txt = C.onGold, txtHover = C.onGold,
		line = C.gold500, lineHover = C.gold400, pad = 26,
	},
	ghost = {
		bg = nil, bgHover = nil,
		txt = C.textHeading, txtHover = C.textStrong,
		line = L.mid, lineHover = L.strong, pad = 22,
	},
	danger = {
		bg = L.dangerWash, bgHover = { r = C.danger500.r, g = C.danger500.g, b = C.danger500.b, a = 0.20 },
		txt = C.danger500, txtHover = C.danger500,
		line = L.dangerLine, lineHover = C.danger500, pad = 22,
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
	txt:SetText(o.text or "")
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
