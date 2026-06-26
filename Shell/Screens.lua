local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell Screens (Phase 3: echte, db-verdrahtete Seiten)
--  Ein Builder je Sektion/Tab, registriert in ns.Screens["<Sektion>/<Tab>"].
--  Shell:RenderContent() ruft den Builder; gibt es keinen, fällt es auf die
--  Widget-Galerie zurück. Vorbild-Layout: Prototyp ui_kits/lumen-config/*.jsx.
--
--  Builder-Signatur: function(holder, stack) — `holder` ist der Content-Frame,
--  `stack` der Layout-Stapler aus Shell:NewStack (place / placeLeft / gap / y).
--  Widgets ankern get/set DIREKT ans Profil (kein Zwischenspeicher) + lösen ein
--  Relayout aus, damit Änderungen sofort an den Frames sichtbar sind.
-- ===========================================================================

local UI = ns.UI
local W  = ns.W
local M, C, L = UI.WIDGET, UI.C, UI.LAYOUT

ns.Screens = ns.Screens or {}

-- ---------------------------------------------------------------------------
--  Auswahl-Optionen (Werte = Profil-Keys, Labels = deutsch wie in der AceConfig).
-- ---------------------------------------------------------------------------
local ALIGN_OPTS = {
	{ value = "vertical",   label = "Vertikal — Mitglieder untereinander" },
	{ value = "horizontal", label = "Horizontal — Mitglieder nebeneinander" },
}
local OUTLINE_OPTS = {
	{ value = "none",    label = "Keine" },
	{ value = "outline", label = "Outline" },
	{ value = "thick",   label = "Dicker Outline" },
}
local HPTEXT_OPTS = {
	{ value = "Keine",   label = "Keine" },
	{ value = "Aktuell", label = "Aktuell" },
	{ value = "Prozent", label = "Prozent" },
}
-- 9 WoW-Ankerpunkte (gleiche Labels wie Options.lua POINTS).
local POINT_OPTS = {
	{ value = "TOPLEFT",     label = "Oben links" },
	{ value = "TOP",         label = "Oben" },
	{ value = "TOPRIGHT",    label = "Oben rechts" },
	{ value = "LEFT",        label = "Links" },
	{ value = "CENTER",      label = "Mitte" },
	{ value = "RIGHT",       label = "Rechts" },
	{ value = "BOTTOMLEFT",  label = "Unten links" },
	{ value = "BOTTOM",      label = "Unten" },
	{ value = "BOTTOMRIGHT", label = "Unten rechts" },
}
-- Base-Tab-Optionen.
local DISPEL_MODE_OPTS = {
	{ value = "recolor", label = "Lebensbalken einfärben" },
	{ value = "overlay", label = "Rand + Overlay (Klassenfarbe bleibt)" },
}
local AGGRO_MODE_OPTS = {
	{ value = "border",  label = "Nur Rand" },
	{ value = "overlay", label = "Rand + Overlay" },
}
local SORT_MODE_OPTS = {
	{ value = "group", label = "Gruppe" },
	{ value = "role",  label = "Rolle" },
}
local TESTSIZE_OPTS = {
	{ value = 5,  label = "5er (Party)" },
	{ value = 20, label = "20er (Raid)" },
	{ value = 40, label = "40er" },
}
local ROLE_LABEL = { TANK = "Tank", HEALER = "Heiler", DAMAGER = "DPS" }
local DISPEL_TYPES = {
	{ key = "Magic",   label = "Magie" },
	{ key = "Curse",   label = "Fluch" },
	{ key = "Disease", label = "Krankheit" },
	{ key = "Poison",  label = "Gift" },
}

-- ---------------------------------------------------------------------------
--  Profil-Zugriff (Werte liegen PRO KONTEXT in rf().raid bzw. rf().party).
-- ---------------------------------------------------------------------------
local function rf() return ns.Lumen.db.profile.raidframes end
local function relayout() if ns.Raidframes then ns.Raidframes:UpdateLayout() end end

local function vget(ctx, key) return function() return (rf()[ctx] or {})[key] end end
local function vset(ctx, key)
	return function(v)
		local t = rf(); t[ctx] = t[ctx] or {}; t[ctx][key] = v; relayout()
	end
end
local function cget(ctx, key)
	return function()
		local c = (rf()[ctx] or {})[key] or {}
		return c.r or 1, c.g or 1, c.b or 1
	end
end
local function cset(ctx, key)
	return function(r, g, b)
		local t = rf(); t[ctx] = t[ctx] or {}; t[ctx][key] = { r = r, g = g, b = b }; relayout()
	end
end

-- Top-Level-Keys (Base-Tab; liegen direkt unter rf(), nicht im Kontext).
local function tget(key) return function() return rf()[key] end end
local function tset(key) return function(v) rf()[key] = v; relayout() end end
local function tcget(key) return function() local c = rf()[key] or {}; return c.r or 1, c.g or 1, c.b or 1 end end
local function tcset(key) return function(r, g, b) rf()[key] = { r = r, g = g, b = b }; relayout() end end
-- Dispel-Farben liegen verschachtelt in rf().dispelColors[<Typ>].
local function dcget(typ) return function() local c = (rf().dispelColors or {})[typ] or {}; return c.r or 1, c.g or 1, c.b or 1 end end
local function dcset(typ) return function(r, g, b) rf().dispelColors = rf().dispelColors or {}; rf().dispelColors[typ] = { r = r, g = g, b = b }; relayout() end end
-- Prozent-Helfer für Alpha-Slider (Profil hält 0..1, Slider zeigt 0..100).
local function pctget(key) return function() return math.floor((rf()[key] or 0) * 100 + 0.5) end end
local function pctset(key) return function(v) rf()[key] = v / 100; relayout() end end

-- Balken-Texturen aus Raidframes:TextureValues() -> sortierte {value,label}-Liste.
local function textureOptions()
	local vals = (ns.Raidframes and ns.Raidframes:TextureValues()) or {}
	local list = {}
	for k in pairs(vals) do list[#list + 1] = k end
	table.sort(list)
	local opts = {}
	for _, k in ipairs(list) do opts[#opts + 1] = { value = k, label = k } end
	return opts
end

-- Linksbündige Unter-Überschrift (für Aggro-Stufen-Blöcke etc.).
local function subHead(parent, text)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(M.subHeadH)
	local fs = UI.FS(f, "groupTitle", C.gold300)
	fs:SetPoint("LEFT", f, "LEFT", 0, 0)
	fs:SetText(text)
	return f
end

-- Einzelnes Dropdown RASTERBÜNDIG: Zelle 1 eines 3-Spalten-Rasters, damit ALLE
-- Dropdowns exakt gleich (1 Spalte) breit sind. sideFn(select) darf rechts neben
-- dem Control eine Checkbox ankern (auf Control-Höhe). Gibt das Select zurück.
local function gridSelect(d, stack, gap, o, sideFn)
	local fieldH = M.controlH + M.fieldGap
	local r, c = W.Row(d, 3, { height = fieldH })
	local sel = W.Select(c[1], o); sel:SetAllPoints(c[1])
	if sideFn then sideFn(sel) end
	stack:place(r, fieldH, gap)
	return sel
end

-- ---------------------------------------------------------------------------
--  RaidScreen — Größe/Anordnung + Name-/HP-Text (Prototyp RaidScreen.jsx).
--  Wird für Raid (ctx="raid") UND Group (ctx="party") genutzt — identische
--  Struktur, nur ein anderer Kontext im Profil.
-- ---------------------------------------------------------------------------
local function buildRaid(d, stack, ctx)
	local fieldH = M.controlH + M.fieldGap -- Höhe eines Selects MIT Label

	-- ===== Größe & Anordnung ===============================================
	local sSize = stack:section("Größe & Anordnung")

	local r1, c1 = W.Row(d, 3, { height = M.sliderH })
	W.Slider(c1[1], { label = "Breite",  min = 40, max = 240, unit = " px", get = vget(ctx, "width"),   set = vset(ctx, "width") }):SetAllPoints(c1[1])
	W.Slider(c1[2], { label = "Höhe",    min = 20, max = 160, unit = " px", get = vget(ctx, "height"),  set = vset(ctx, "height") }):SetAllPoints(c1[2])
	W.Slider(c1[3], { label = "Abstand", min = 0,  max = 30,  unit = " px", get = vget(ctx, "spacing"), set = vset(ctx, "spacing") }):SetAllPoints(c1[3])
	sSize:place(r1, M.sliderH, L.sizeArrange.afterSliders)

	-- Ausrichtung — Positions-Hinweis als Tooltip (nicht mehr inline).
	gridSelect(d, sSize, L.sizeArrange.afterAlign,
		{ label = "Ausrichtung", options = ALIGN_OPTS, get = vget(ctx, "orientation"), set = vset(ctx, "orientation"),
		  tooltip = "Position: über „Rahmen entsperren“ im Global-Tab bzw. WoWs Edit-Modus verschieben. "
			.. "Raid und Group haben getrennte Positionen." })
	sSize:close()

	-- ===== Text — Name =====================================================
	-- „Name anzeigen" ist der Master: aus -> alle übrigen Name-Controls ausgegraut.
	-- Reihenfolge (Florian): Master / Umrandung·Position / Größe·X·Y / Farbe.
	local sName = stack:section("Text — Name")

	local nameDeps = {}
	local function refreshName()
		local on = (rf()[ctx] or {}).showName and true or false
		for _, w in ipairs(nameDeps) do w:SetWidgetEnabled(on) end
	end

	local nameTogRow = CreateFrame("Frame", nil, d)
	local cbName = W.Checkbox(nameTogRow, { label = "Name anzeigen", get = vget(ctx, "showName"),
		set = function(v) vset(ctx, "showName")(v); refreshName() end })
	cbName:SetPoint("LEFT", nameTogRow, "LEFT", 0, 0)
	sName:place(nameTogRow, M.checkBox, L.nameText.afterMaster)

	-- Reihe: Umrandung | Position | (frei)
	local nr1, nc1 = W.Row(d, 3, { height = fieldH })
	local nameOutline = W.Select(nc1[1], { label = "Namens-Umrandung", options = OUTLINE_OPTS, get = vget(ctx, "nameOutline"), set = vset(ctx, "nameOutline") })
	nameOutline:SetAllPoints(nc1[1])
	local namePos = W.Select(nc1[2], { label = "Namensposition", options = POINT_OPTS, get = vget(ctx, "namePoint"), set = vset(ctx, "namePoint") })
	namePos:SetAllPoints(nc1[2])
	sName:place(nr1, fieldH, L.nameText.afterOutline)

	-- Reihe: Größe | X-Versatz | Y-Versatz
	local nr2, nc2 = W.Row(d, 3, { height = M.sliderH })
	local nameSize = W.Slider(nc2[1], { label = "Namensgröße", min = 6, max = 30, get = vget(ctx, "nameSize"), set = vset(ctx, "nameSize") })
	nameSize:SetAllPoints(nc2[1])
	local nameX = W.Slider(nc2[2], { label = "Name X-Versatz", min = -40, max = 40, get = vget(ctx, "nameX"), set = vset(ctx, "nameX") })
	nameX:SetAllPoints(nc2[2])
	local nameY = W.Slider(nc2[3], { label = "Name Y-Versatz", min = -40, max = 40, get = vget(ctx, "nameY"), set = vset(ctx, "nameY") })
	nameY:SetAllPoints(nc2[3])
	sName:place(nr2, M.sliderH, L.nameText.afterSize)

	-- Reihe: Farbe (allein)
	local nameColRow = CreateFrame("Frame", nil, d)
	local swName = W.ColorSwatch(nameColRow, { label = "Farbe", get = cget(ctx, "nameColor"), set = cset(ctx, "nameColor") })
	swName:SetPoint("LEFT", nameColRow, "LEFT", 0, 0)
	sName:place(nameColRow, M.checkBox, L.nameText.afterColor)
	sName:close()

	for _, w in ipairs({ nameOutline, namePos, nameSize, nameX, nameY, swName }) do nameDeps[#nameDeps + 1] = w end
	refreshName()

	-- ===== Text — HP-Anzeige ===============================================
	-- Reihenfolge: HP-Text·Umrandung·Position / Größe·X·Y / Farbe. „Keine" graut den Rest.
	local sHP = stack:section("Text — HP-Anzeige")

	local hpDeps = {}
	local function refreshHP()
		local on = (rf()[ctx] or {}).healthTextType ~= "Keine"
		for _, w in ipairs(hpDeps) do w:SetWidgetEnabled(on) end
	end

	-- Reihe: HP-Text | Umrandung | Position. Live-Hinweis als Tooltip auf HP-Text.
	local hr1, hc1 = W.Row(d, 3, { height = fieldH })
	local hpType = W.Select(hc1[1], { label = "HP-Text", options = HPTEXT_OPTS,
		tooltip = "Live zeigt WoW (12.0) secret-bedingt die aktuelle HP; exaktes Prozent im Testmodus.",
		get = vget(ctx, "healthTextType"), set = function(v) vset(ctx, "healthTextType")(v); refreshHP() end })
	hpType:SetAllPoints(hc1[1])
	local hpOutline = W.Select(hc1[2], { label = "HP-Text-Umrandung", options = OUTLINE_OPTS, get = vget(ctx, "healthTextOutline"), set = vset(ctx, "healthTextOutline") })
	hpOutline:SetAllPoints(hc1[2])
	local hpPos = W.Select(hc1[3], { label = "HP-Textposition", options = POINT_OPTS, get = vget(ctx, "healthTextPoint"), set = vset(ctx, "healthTextPoint") })
	hpPos:SetAllPoints(hc1[3])
	sHP:place(hr1, fieldH, L.hpText.afterType)

	-- Reihe: Größe | X-Versatz | Y-Versatz
	local hr2, hc2 = W.Row(d, 3, { height = M.sliderH })
	local hpSize = W.Slider(hc2[1], { label = "HP-Textgröße", min = 6, max = 30, get = vget(ctx, "healthTextSize"), set = vset(ctx, "healthTextSize") })
	hpSize:SetAllPoints(hc2[1])
	local hpX = W.Slider(hc2[2], { label = "HP-Text X-Versatz", min = -40, max = 40, get = vget(ctx, "healthTextX"), set = vset(ctx, "healthTextX") })
	hpX:SetAllPoints(hc2[2])
	local hpY = W.Slider(hc2[3], { label = "HP-Text Y-Versatz", min = -40, max = 40, get = vget(ctx, "healthTextY"), set = vset(ctx, "healthTextY") })
	hpY:SetAllPoints(hc2[3])
	sHP:place(hr2, M.sliderH, L.hpText.afterSize)

	-- Reihe: Farbe (allein)
	local hpColRow = CreateFrame("Frame", nil, d)
	local swHP = W.ColorSwatch(hpColRow, { label = "Farbe", get = cget(ctx, "healthTextColor"), set = cset(ctx, "healthTextColor") })
	swHP:SetPoint("LEFT", hpColRow, "LEFT", 0, 0)
	sHP:place(hpColRow, M.checkBox, L.hpText.afterColor)
	sHP:close()

	for _, w in ipairs({ hpOutline, hpPos, hpSize, hpX, hpY, swHP }) do hpDeps[#hpDeps + 1] = w end
	refreshHP()
end

-- Kleiner Pfeil-Button (↑/↓) aus zwei Linien (Font-Glyphen ▲▼ sind unsicher).
-- Hat einen Disabled-Zustand (ausgegraut, nicht klickbar) -> nicht verstecken,
-- damit die Reihen-Positionen stabil bleiben (kein „Springen").
local function arrowButton(parent, dir, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 18)
	local l1 = b:CreateLine(nil, "OVERLAY"); l1:SetThickness(2)
	local l2 = b:CreateLine(nil, "OVERLAY"); l2:SetThickness(2)
	local function setCol(c) l1:SetColorTexture(c.r, c.g, c.b, 1); l2:SetColorTexture(c.r, c.g, c.b, 1) end
	if dir == "up" then
		l1:SetStartPoint("CENTER", b, -5, -2); l1:SetEndPoint("CENTER", b, 0, 3)
		l2:SetStartPoint("CENTER", b, 0, 3);   l2:SetEndPoint("CENTER", b, 5, -2)
	else
		l1:SetStartPoint("CENTER", b, -5, 2);  l1:SetEndPoint("CENTER", b, 0, -3)
		l2:SetStartPoint("CENTER", b, 0, -3);  l2:SetEndPoint("CENTER", b, 5, 2)
	end
	b._on = true
	setCol(C.gold300)
	b:SetScript("OnEnter", function() if b._on then setCol(C.gold100) end end)
	b:SetScript("OnLeave", function() if b._on then setCol(C.gold300) end end)
	b:SetScript("OnClick", function() if b._on then onClick() end end)
	b.setDim = function(on)
		b._on = not on
		if on then setCol(C.textFaint); b:EnableMouse(false)
		else setCol(C.gold300); b:EnableMouse(true) end
	end
	return b
end

-- Rollen-Akzentfarbe (Balken links + dezenter Reihen-Wash) zur klaren Abgrenzung.
local ROLE_ACCENT = {
	TANK    = { r = 0.40, g = 0.62, b = 0.95 },
	HEALER  = { r = 0.36, g = 0.78, b = 0.46 },
	DAMAGER = { r = 0.90, g = 0.42, b = 0.42 },
}

-- ---------------------------------------------------------------------------
--  BaseScreen — Funktion & Optik des Moduls (spiegelt den AceConfig-Base-Tab):
--  Aktiviert, Lebensbalken, Dispel, Aggro, Sortierung, Test. KEINE Layout-Maße
--  (Breite/Höhe/Ausrichtung) — die liegen in Raid/Group. Wertabhängige Optionen
--  werden ausgegraut (Konvention wie im Aggro-Block des AceConfig).
-- ---------------------------------------------------------------------------
local function buildBase(d, stack)
	local fieldH = M.controlH + M.fieldGap

	-- ===== Aktiviert =======================================================
	stack:gap(L.base.topToToggle) -- oben mehr Luft vor dem Master-Schalter
	local enRow = CreateFrame("Frame", nil, d)
	local cbEnabled = W.Checkbox(enRow, {
		label = "Raidframes aktiviert", get = tget("enabled"),
		set = function(v)
			rf().enabled = v
			if ns.Raidframes then if v then ns.Raidframes:Enable() else ns.Raidframes:Disable() end end
		end,
	})
	cbEnabled:SetPoint("LEFT", enRow, "LEFT", 0, 0)
	stack:place(enRow, M.checkBox, L.base.toggleToSection)

	-- ===== Lebensbalken ====================================================
	local sBar = stack:section("Lebensbalken")

	-- Reihe 1: Balken-Textur (rasterbündig) + Heilvorhersage daneben.
	gridSelect(d, sBar, L.lebensbalken.afterTexture,
		{ label = "Balken-Textur", options = textureOptions(), get = tget("healthTexture"), set = tset("healthTexture") },
		function(sel)
			local cbHealPred = W.Checkbox(d, { label = "Heilvorhersage (eingehende Heilung)",
				get = tget("healPrediction"), set = tset("healPrediction") })
			cbHealPred:SetPoint("LEFT", sel._control, "RIGHT", L.general.sideGap, 0)
		end)

	-- Reihe 2: Klassenfarbe (Master) + Füllfarbe.
	local fillDeps = {}
	local function refreshFill()
		local editable = not rf().useClassColor
		for _, w in ipairs(fillDeps) do w:SetWidgetEnabled(editable) end
	end
	local barTogRow = CreateFrame("Frame", nil, d)
	local cbClass = W.Checkbox(barTogRow, { label = "Klassenfarbe als Füllfarbe", get = tget("useClassColor"),
		set = function(v) rf().useClassColor = v; relayout(); refreshFill() end })
	cbClass:SetPoint("LEFT", barTogRow, "LEFT", 0, 0)
	local swFill = W.ColorSwatch(barTogRow, { label = "Füllfarbe", get = tcget("fillColor"), set = tcset("fillColor") })
	swFill:SetPoint("LEFT", cbClass, "RIGHT", L.general.checkRowGap, 0)
	sBar:place(barTogRow, M.checkBox, L.lebensbalken.afterClass)
	sBar:close()
	fillDeps[1] = swFill; refreshFill()

	-- ===== Dispel-Anzeige ==================================================
	local sDispel = stack:section("Dispel-Anzeige")

	local dispelDeps, dispelAlphaW = {}, nil
	local function refreshDispel()
		local on = rf().dispelEnabled and true or false
		for _, w in ipairs(dispelDeps) do w:SetWidgetEnabled(on) end
		if dispelAlphaW then dispelAlphaW:SetWidgetEnabled(on and rf().dispelMode == "overlay") end
	end
	-- Reihe 1: Master + „Alle dispellbaren zeigen" daneben.
	local dRow1 = CreateFrame("Frame", nil, d)
	local cbDispel = W.Checkbox(dRow1, { label = "Dispellbare Debuffs hervorheben (auch im Kampf)",
		get = tget("dispelEnabled"), set = function(v) rf().dispelEnabled = v; relayout(); refreshDispel() end })
	cbDispel:SetPoint("LEFT", dRow1, "LEFT", 0, 0)
	local cbShowAll = W.Checkbox(dRow1, { label = "Alle dispellbaren zeigen (nicht nur eigene)",
		get = tget("dispelShowAll"), set = tset("dispelShowAll") })
	cbShowAll:SetPoint("LEFT", cbDispel, "RIGHT", L.general.checkRowGap, 0)
	sDispel:place(dRow1, M.checkBox, L.dispel.afterMaster)

	-- Reihe 2: Typ-Farben (Magie/Fluch/Krankheit/Gift) — vor der Slider-Reihe, damit
	-- die Slider-Wertbox unten nicht an den Farben klebt.
	local dColRow, dcc = W.Row(d, 4, { height = M.checkBox })
	local dispColW = {}
	for i, t in ipairs(DISPEL_TYPES) do
		local sw = W.ColorSwatch(dcc[i], { label = t.label, get = dcget(t.key), set = dcset(t.key) })
		sw:SetPoint("LEFT", dcc[i], "LEFT", 0, 0)
		dispColW[i] = sw
	end
	sDispel:place(dColRow, M.checkBox, L.dispel.afterColors)

	-- Reihe 3: Darstellung (Spalte 1) + Overlay-Deckkraft (Spalte 2) im Raster.
	local dr2, dc2 = W.Row(d, 3, { height = M.sliderH })
	local dispMode = W.Select(dc2[1], { label = "Darstellung", options = DISPEL_MODE_OPTS,
		get = tget("dispelMode"), set = function(v) tset("dispelMode")(v); refreshDispel() end })
	dispMode:SetAllPoints(dc2[1])
	dispelAlphaW = W.Slider(dc2[2], { label = "Overlay-Deckkraft", min = 0, max = 100, unit = " %",
		get = pctget("dispelAlpha"), set = pctset("dispelAlpha") })
	dispelAlphaW:SetAllPoints(dc2[2])
	sDispel:place(dr2, M.sliderH, L.dispel.afterMode)
	sDispel:close()

	for _, w in ipairs({ dispMode, cbShowAll, dispColW[1], dispColW[2], dispColW[3], dispColW[4] }) do
		dispelDeps[#dispelDeps + 1] = w
	end
	refreshDispel()

	-- ===== Aggro-Warnung ===================================================
	local sAggro = stack:section("Aggro-Warnung")

	local aggroAlways = {}                 -- nur an aggroEnabled gekoppelt
	local aggroTextAggroW, aggroTextWarnW  -- zusätzlich modusabhängig
	local aggroAlphaW
	local aggroTextOpts = {}               -- nur aktiv, wenn Text wirklich angezeigt wird
	local function refreshAggro()
		local en = rf().aggroEnabled and true or false
		for _, w in ipairs(aggroAlways) do w:SetWidgetEnabled(en) end
		aggroTextAggroW:SetWidgetEnabled(en and rf().aggroModeAggro == "overlay")
		aggroTextWarnW:SetWidgetEnabled(en and rf().aggroModeWarn == "overlay")
		aggroAlphaW:SetWidgetEnabled(en and (rf().aggroModeAggro == "overlay" or rf().aggroModeWarn == "overlay"))
		local textActive = (rf().aggroModeAggro == "overlay" and rf().aggroTextAggro)
			or (rf().aggroModeWarn == "overlay" and rf().aggroTextWarn)
		for _, w in ipairs(aggroTextOpts) do w:SetWidgetEnabled(en and textActive and true or false) end
	end

	local agRow = CreateFrame("Frame", nil, d)
	local cbAggro = W.Checkbox(agRow, { label = "Aggro-Warnung anzeigen (Tanks ausgenommen)",
		get = tget("aggroEnabled"), set = function(v) rf().aggroEnabled = v; relayout(); refreshAggro() end })
	cbAggro:SetPoint("LEFT", agRow, "LEFT", 0, 0)
	sAggro:place(agRow, M.checkBox, L.aggro.afterMaster)

	-- Ein Aggro-Stufen-Block (rot/gelb): Darstellung (1 Spalte) | Farbe | "Aggro"-Text,
	-- Farbe + Text direkt neben dem Control gepackt (nicht über die Breite verteilt).
	local function aggroStage(label, colorKey, modeKey, textKey, trailGap)
		sAggro:place(subHead(d, label), M.subHeadH, L.general.subHeadToRow)
		local r, c = W.Row(d, 3, { height = fieldH })
		local mode = W.Select(c[1], { label = "Darstellung", options = AGGRO_MODE_OPTS,
			get = tget(modeKey), set = function(v) tset(modeKey)(v); refreshAggro() end })
		mode:SetAllPoints(c[1])
		local sw = W.ColorSwatch(d, { label = "Farbe", get = tcget(colorKey), set = tcset(colorKey) })
		sw:SetPoint("LEFT", mode._control, "RIGHT", L.general.sideGap, 0)
		local cbTxt = W.Checkbox(d, { label = "\"Aggro\"-Text anzeigen", get = tget(textKey),
			set = function(v) tset(textKey)(v); refreshAggro() end })
		cbTxt:SetPoint("LEFT", sw, "RIGHT", L.general.sideGap, 0)
		sAggro:place(r, fieldH, trailGap)
		aggroAlways[#aggroAlways + 1] = sw
		aggroAlways[#aggroAlways + 1] = mode
		return cbTxt
	end
	aggroTextAggroW = aggroStage("Hat Aggro (rot)",   "aggroColorAggro", "aggroModeAggro", "aggroTextAggro", L.aggro.afterStage)
	aggroTextWarnW  = aggroStage("Aggro droht (gelb)", "aggroColorWarn",  "aggroModeWarn",  "aggroTextWarn", L.aggro.beforeSubDivider)

	-- Geteilte Darstellung beider Stufen — zentrierter Sub-Divider INNERHALB der Karte.
	sAggro:place(W.SectionDivider(d, "Darstellung (beide Stufen)", true), M.dividerH, L.aggro.afterSubDivider)
	-- Reihe 1: Textposition | Text-Umrandung | Overlay-Deckkraft.
	local ar1, ac1 = W.Row(d, 3, { height = M.sliderH })
	local agPoint = W.Select(ac1[1], { label = "Textposition", options = POINT_OPTS, get = tget("aggroTextPoint"), set = tset("aggroTextPoint") })
	agPoint:SetAllPoints(ac1[1])
	local agOutline = W.Select(ac1[2], { label = "Text-Umrandung", options = OUTLINE_OPTS, get = tget("aggroTextOutline"), set = tset("aggroTextOutline") })
	agOutline:SetAllPoints(ac1[2])
	aggroAlphaW = W.Slider(ac1[3], { label = "Overlay-Deckkraft", min = 0, max = 100, unit = " %",
		get = pctget("aggroFillAlpha"), set = pctset("aggroFillAlpha") })
	aggroAlphaW:SetAllPoints(ac1[3])
	sAggro:place(ar1, M.sliderH, L.aggro.betweenShared)

	-- Reihe 2: Textgröße | Text X-Versatz | Text Y-Versatz.
	local ar2, ac2 = W.Row(d, 3, { height = M.sliderH })
	local agSize = W.Slider(ac2[1], { label = "Textgröße", min = 6, max = 28, get = tget("aggroTextSize"), set = tset("aggroTextSize") })
	agSize:SetAllPoints(ac2[1])
	local agX = W.Slider(ac2[2], { label = "Text X-Versatz", min = -60, max = 60, get = tget("aggroTextX"), set = tset("aggroTextX") })
	agX:SetAllPoints(ac2[2])
	local agY = W.Slider(ac2[3], { label = "Text Y-Versatz", min = -60, max = 60, get = tget("aggroTextY"), set = tset("aggroTextY") })
	agY:SetAllPoints(ac2[3])
	sAggro:place(ar2, M.sliderH, L.aggro.afterShared)
	sAggro:close()

	for _, w in ipairs({ agPoint, agOutline, agSize, agX, agY }) do aggroTextOpts[#aggroTextOpts + 1] = w end
	refreshAggro()

	-- ===== Sortierung ======================================================
	local sSort = stack:section("Sortierung")

	-- Reihe 1: Sortieren nach (rasterbündig) + (bei „Rolle") „Auch im Raid" daneben (Tooltip).
	gridSelect(d, sSort, L.sort.afterMode,
		{ label = "Sortieren nach", options = SORT_MODE_OPTS,
		  get = tget("sortMode"), set = function(v) tset("sortMode")(v); ns.Shell:RenderContent(true) end },
		(rf().sortMode == "role") and function(sel)
			local cbRaid = W.Checkbox(d, { label = "Auch im Raid nach Rolle sortieren",
				tooltip = "Aus: im Raid bleibt deine selbst gebaute Anordnung nach Gruppe. An: die Rollen-Sortierung "
					.. "gilt auch im Raid. (Dungeon/Party wird immer sortiert.)",
				get = tget("sortApplyRaid"), set = tset("sortApplyRaid") })
			cbRaid:SetPoint("LEFT", sel._control, "RIGHT", L.general.sideGap, 0)
		end or nil)

	if rf().sortMode == "role" then
		local function swapRole(i, j)
			local o = rf().sortRoleOrder
			if not (o and o[i] and o[j]) then return end
			o[i], o[j] = o[j], o[i]
			relayout(); ns.Shell:RenderContent(true)
		end
		-- Prioritätsliste: Card genau 1 Spalte breit (bündig mit „Sortieren nach"),
		-- rollenfarbene Reihen (Akzent-Balken + Wash) + ↑/↓-Pfeile vorne (nicht
		-- nutzbare ausgegraut, kein Springen).
		local order = rf().sortRoleOrder or {}
		local pad, rowH = M.sortCardPad, M.sortRowH
		local cardH = #order * rowH + pad * 2
		local cr, cc = W.Row(d, 3, { height = cardH })
		local card = W.Card(cc[1]); card:SetAllPoints(cc[1])
		local prevRow
		for i = 1, #order do
			local role = order[i]
			local acc = ROLE_ACCENT[role] or { r = 0.6, g = 0.6, b = 0.6 }
			local row = CreateFrame("Frame", nil, card)
			row:SetHeight(rowH)
			row:SetPoint("LEFT", card, "LEFT", pad, 0)
			row:SetPoint("RIGHT", card, "RIGHT", -pad, 0)
			if prevRow then row:SetPoint("TOP", prevRow, "BOTTOM", 0, 0)
			else row:SetPoint("TOP", card, "TOP", 0, -pad) end
			local bg = row:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints(row); UI.SetColor(bg, C.ink600)
			local wash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
			wash:SetAllPoints(row); wash:SetColorTexture(acc.r, acc.g, acc.b, 0.10)
			local barL = row:CreateTexture(nil, "ARTWORK")
			barL:SetWidth(M.sortAccentW)
			barL:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
			barL:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
			barL:SetColorTexture(acc.r, acc.g, acc.b, 0.95)
			local up = arrowButton(row, "up", function() swapRole(i, i - 1) end)
			up:SetPoint("LEFT", row, "LEFT", 14, 0)
			local down = arrowButton(row, "down", function() swapRole(i, i + 1) end)
			down:SetPoint("LEFT", up, "RIGHT", 2, 0)
			if i == 1 then up.setDim(true) end
			if i == #order then down.setDim(true) end
			local lbl = UI.FS(row, "listLabel", C.textStrong)
			lbl:SetPoint("LEFT", down, "RIGHT", 16, 0)
			lbl:SetText(ROLE_LABEL[role] or "?")
			prevRow = row
		end
		sSort:place(cr, cardH, L.sort.afterCard)
	end
	sSort:close()

	-- ===== Test / Beispielgruppe ===========================================
	local sTest = stack:section("Test / Beispielgruppe")

	local testSizeW
	local function refreshTest() if testSizeW then testSizeW:SetWidgetEnabled(rf().testMode and true or false) end end
	local testRow = CreateFrame("Frame", nil, d)
	local cbTest = W.Checkbox(testRow, { label = "Testmodus — Beispielgruppe anzeigen (zum Designen, ohne echte Gruppe)",
		get = tget("testMode"), set = function(v) rf().testMode = v; relayout(); refreshTest() end })
	cbTest:SetPoint("LEFT", testRow, "LEFT", 0, 0)
	sTest:place(testRow, M.checkBox, L.test.afterMaster)

	testSizeW = gridSelect(d, sTest, L.test.afterSize,
		{ label = "Test-Gruppengröße", options = TESTSIZE_OPTS, get = tget("testSize"), set = tset("testSize") })
	sTest:close()
	refreshTest()
end

ns.Screens["Raidframes/Base"]  = buildBase
ns.Screens["Raidframes/Raid"]  = function(d, stack) buildRaid(d, stack, "raid") end
ns.Screens["Raidframes/Group"] = function(d, stack) buildRaid(d, stack, "party") end
