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
-- Auras-Tab: Wachstumsrichtung (Werte = Profil-Keys wie in Options.lua GROW).
local GROW_OPTS = {
	{ value = "RIGHT", label = "Nach rechts" },
	{ value = "LEFT",  label = "Nach links" },
	{ value = "UP",    label = "Nach oben" },
	{ value = "DOWN",  label = "Nach unten" },
}
-- Auras-Tab: Debuff-Filtermodus (nur Kategorie „debuffs").
local AURA_FILTER_OPTS = {
	{ value = "raid",        label = "Raid-relevant (Blizzard)" },
	{ value = "all",         label = "Alle" },
	{ value = "dispellable", label = "Nur dispellbar" },
}
-- Base-Tab-Optionen.
local DISPEL_MODE_OPTS = {
	{ value = "recolor", label = "Lebensbalken einfärben" },
	{ value = "overlay", label = "Rand + Overlay (Klassenfarbe bleibt)" },
}
-- Werte kombinieren Modus + Text (das Datenmodell bleibt getrennt: aggroMode +
-- aggroText). „overlaytext" = overlay-Modus MIT Text. Map siehe aggroStage.
local AGGRO_MODE_OPTS = {
	{ value = "border",      label = "Nur Rand" },
	{ value = "overlay",     label = "Rand + Overlay" },
	{ value = "overlaytext", label = "Rand + Overlay + Text" },
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
-- (Per-Kontext-Farb-Helfer entfernt: Text-Farben liegen jetzt GETEILT in Base, siehe tcget/tcset.)

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

-- Aura-Werte liegen in rf().auras[<cat>][key]. Set löst RefreshAuras() aus (leicht
-- + kampf-sicher; UpdateLayout würde im Kampf abbrechen — wie der AceConfig-Auras-Tab).
local function aget(cat, key) return function() return ((rf().auras or {})[cat] or {})[key] end end
local function aset(cat, key)
	return function(v)
		local t = rf(); t.auras = t.auras or {}; t.auras[cat] = t.auras[cat] or {}; t.auras[cat][key] = v
		if ns.Raidframes then ns.Raidframes:RefreshAuras() end
	end
end

-- Balken-Texturen aus Raidframes:TextureValues() -> sortierte {value,label}-Liste.
local function texOptsFrom(vals)
	local list = {}
	for k in pairs(vals or {}) do list[#list + 1] = k end
	table.sort(list)
	local opts = {}
	for _, k in ipairs(list) do opts[#opts + 1] = { value = k, label = k } end
	return opts
end
local function textureOptions() return texOptsFrom(ns.Raidframes and ns.Raidframes:TextureValues()) end
local function shieldTexOptions() return texOptsFrom(ns.Raidframes and ns.Raidframes:ShieldTextureValues()) end
local function healAbsorbTexOptions() return texOptsFrom(ns.Raidframes and ns.Raidframes:HealAbsorbTextureValues()) end

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

-- Dimmt + sperrt einen Inhalts-Frame im „Modul deaktiviert"-Zustand (gleicher
-- 0.35-Look wie eine ausgegraute Unter-Option). Wiederverwendbar: Base gated sein
-- Body-Frame (Master bleibt bedienbar), Raid/Group/Auras gaten den ganzen Screen.
-- Der Cover-Button schluckt alle Klicks; Mausrad-Scrollen (am ScrollFrame) bleibt.
local function applyModuleGate(holder, enabled)
	if not holder._gateCover then
		local cover = CreateFrame("Button", nil, holder)
		cover:SetAllPoints(holder)
		cover:SetFrameLevel(holder:GetFrameLevel() + 1000)
		cover:EnableMouse(true)
		cover:Hide()
		holder._gateCover = cover
	end
	if enabled then
		holder:SetAlpha(1); holder._gateCover:Hide()
	else
		holder:SetAlpha(0.35); holder._gateCover:Show()
	end
end

-- ---------------------------------------------------------------------------
--  RaidScreen — Größe/Anordnung + Name-/HP-Text (Prototyp RaidScreen.jsx).
--  Wird für Raid (ctx="raid") UND Group (ctx="party") genutzt — identische
--  Struktur, nur ein anderer Kontext im Profil.
-- ---------------------------------------------------------------------------
local function buildRaid(d, stack, ctx)
	local fieldH = M.controlH + M.fieldGap -- Höhe eines Selects MIT Label
	local R = L.rhythm

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
	-- „Name anzeigen" ist der Master (frei über der Box): aus -> Box ausgegraut.
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
	sName:place(nameTogRow, M.checkBox, R.afterCheck)

	-- Unter-Box (untitelt — der Master darüber benennt sie): Umrandung/Position /
	-- Größe·X·Y / Farbe.
	-- Farbe + Umrandung liegen GETEILT im Base-Tab („Text"). Hier nur Position + Größe.
	local boxN = sName:subgroup()
	local nr1, nc1 = W.Row(d, 3, { height = fieldH })
	local namePos = W.Select(nc1[1], { label = "Namensposition", options = POINT_OPTS, get = vget(ctx, "namePoint"), set = vset(ctx, "namePoint") })
	namePos:SetAllPoints(nc1[1])
	boxN:place(nr1, fieldH, R.row)

	local nr2, nc2 = W.Row(d, 3, { height = M.sliderH })
	local nameSize = W.Slider(nc2[1], { label = "Namensgröße", min = 6, max = 30, get = vget(ctx, "nameSize"), set = vset(ctx, "nameSize") })
	nameSize:SetAllPoints(nc2[1])
	local nameX = W.Slider(nc2[2], { label = "Name X-Versatz", min = -40, max = 40, get = vget(ctx, "nameX"), set = vset(ctx, "nameX") })
	nameX:SetAllPoints(nc2[2])
	local nameY = W.Slider(nc2[3], { label = "Name Y-Versatz", min = -40, max = 40, get = vget(ctx, "nameY"), set = vset(ctx, "nameY") })
	nameY:SetAllPoints(nc2[3])
	boxN:place(nr2, M.sliderH, R.tight)
	boxN:close()
	sName:close()

	for _, w in ipairs({ namePos, nameSize, nameX, nameY }) do nameDeps[#nameDeps + 1] = w end
	refreshName()

	-- ===== Text — HP-Anzeige ===============================================
	-- „HP-Text" ist der Master (frei rausgezogen): „Keine" graut die Box aus.
	-- Symmetrisch zu Name.
	local sHP = stack:section("Text — HP-Anzeige")

	local hpDeps = {}
	local function refreshHP()
		local on = (rf()[ctx] or {}).healthTextType ~= "Keine"
		for _, w in ipairs(hpDeps) do w:SetWidgetEnabled(on) end
	end

	-- Master-Reihe: HP-Text-Dropdown allein (rasterbündig in Spalte 1).
	local hMaster, hmc = W.Row(d, 3, { height = fieldH })
	local hpType = W.Select(hmc[1], { label = "HP-Text", options = HPTEXT_OPTS,
		tooltip = "Live zeigt WoW (12.0) secret-bedingt die aktuelle HP; exaktes Prozent im Testmodus.",
		get = vget(ctx, "healthTextType"), set = function(v) vset(ctx, "healthTextType")(v); refreshHP() end })
	hpType:SetAllPoints(hmc[1])
	sHP:place(hMaster, fieldH, R.afterCheck)

	-- Unter-Box (untitelt): Umrandung/Position / Größe·X·Y / Farbe.
	-- Farbe + Umrandung liegen GETEILT im Base-Tab („Text"). Hier nur Position + Größe.
	local boxH = sHP:subgroup()
	local hr1, hc1 = W.Row(d, 3, { height = fieldH })
	local hpPos = W.Select(hc1[1], { label = "HP-Textposition", options = POINT_OPTS, get = vget(ctx, "healthTextPoint"), set = vset(ctx, "healthTextPoint") })
	hpPos:SetAllPoints(hc1[1])
	boxH:place(hr1, fieldH, R.row)

	local hr2, hc2 = W.Row(d, 3, { height = M.sliderH })
	local hpSize = W.Slider(hc2[1], { label = "HP-Textgröße", min = 6, max = 30, get = vget(ctx, "healthTextSize"), set = vset(ctx, "healthTextSize") })
	hpSize:SetAllPoints(hc2[1])
	local hpX = W.Slider(hc2[2], { label = "HP-Text X-Versatz", min = -40, max = 40, get = vget(ctx, "healthTextX"), set = vset(ctx, "healthTextX") })
	hpX:SetAllPoints(hc2[2])
	local hpY = W.Slider(hc2[3], { label = "HP-Text Y-Versatz", min = -40, max = 40, get = vget(ctx, "healthTextY"), set = vset(ctx, "healthTextY") })
	hpY:SetAllPoints(hc2[3])
	boxH:place(hr2, M.sliderH, R.tight)
	boxH:close()
	sHP:close()

	for _, w in ipairs({ hpPos, hpSize, hpX, hpY }) do hpDeps[#hpDeps + 1] = w end
	refreshHP()

	applyModuleGate(d, rf().enabled) -- Modul aus -> ganzer Raid/Group-Screen grau + gesperrt
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
	local R = L.rhythm

	-- ===== Aktiviert (Master — bleibt IMMER bedienbar, außerhalb des Gates) =
	local outerStack = stack
	local body -- forward-declare: die Master-Closure gated dieses Body-Frame
	stack:gap(L.base.topToToggle) -- oben mehr Luft vor dem Master-Schalter
	local enRow = CreateFrame("Frame", nil, d)
	local cbEnabled = W.Checkbox(enRow, {
		label = "Raidframes aktiviert", get = tget("enabled"),
		set = function(v)
			rf().enabled = v
			if ns.Raidframes then if v then ns.Raidframes:Enable() else ns.Raidframes:Disable() end end
			applyModuleGate(body, v)
		end,
	})
	cbEnabled:SetPoint("LEFT", enRow, "LEFT", 0, 0)
	local cbSolo = W.Checkbox(enRow, { label = "Frames auch alleine anzeigen",
		tooltip = "Zeigt den Gruppen-Frame auch, wenn du nicht in einer Gruppe bist.",
		get = tget("showWhenSolo"), set = tset("showWhenSolo") })
	cbSolo:SetPoint("LEFT", cbEnabled, "RIGHT", L.general.checkRowGap, 0)
	stack:place(enRow, M.checkBox, L.base.toggleToSection)

	-- Alles Weitere läuft in ein gate-bares Body-Frame: bei „aus" gedimmt + gesperrt
	-- (gleicher 0.35-Look wie die Unter-Optionen). Die lokalen Namen d/stack werden
	-- auf body/bstack umgebogen -> der restliche Base-Code baut unverändert weiter.
	body = CreateFrame("Frame", nil, d)
	local bstack = ns.Shell.NewStack(body)
	d, stack = body, bstack

	-- ===== Lebensbalken ====================================================
	local sBar = stack:section("Lebensbalken")

	-- Reihe 1: Balken-Textur | Schild-Textur | Healabsorb-Textur (3 Dropdowns, je mit Zeilen-
	-- begrenzung + Mausrad-Vorschau + Suchfeld). Default „Lumen …" = Streifen-Muster, sonst LSM/Blizzard.
	local tr1, tc1 = W.Row(d, 3, { height = fieldH })
	W.Select(tc1[1], { label = "Balken-Textur", options = textureOptions(), wheelPreview = true, search = true, get = tget("healthTexture"), set = tset("healthTexture") }):SetAllPoints(tc1[1])
	W.Select(tc1[2], { label = "Schild-Textur", options = shieldTexOptions(), wheelPreview = true, search = true, get = tget("shieldTexture"), set = tset("shieldTexture") }):SetAllPoints(tc1[2])
	W.Select(tc1[3], { label = "Healabsorb-Textur", options = healAbsorbTexOptions(), wheelPreview = true, search = true, get = tget("healAbsorbTexture"), set = tset("healAbsorbTexture") }):SetAllPoints(tc1[3])
	sBar:place(tr1, fieldH, L.lebensbalken.afterTexHint)
	-- Sichtbarer Hinweis (statt Hover-Tooltip) zur Mausrad-Vorschau + zum Suchfeld der Textur-Dropdowns.
	local texHint = W.Hint(d, "Mausrad über einem Textur-Dropdown blättert live durch die Texturen (Vorschau). Im geöffneten Menü filtert das Suchfeld am Kopf.")
	sBar:place(texHint, M.hintH, R.row)

	-- Checkbox-Versatz, um eine Checkbox vertikal aufs Control-Band (Swatch/Select) einer
	-- Field-Reihe auszurichten (Label oben, Control unten -> Box mittig ins untere 40er-Band).
	local fillOff = -(M.fieldGap + (M.controlH - M.checkBox) / 2)

	-- Reihe 2: Heilvorhersage + Klassenfarbe (Checks) + Füllfarbe + Hintergrundfarbe (Swatches).
	local fillDeps = {}
	local function refreshFill()
		local editable = not rf().useClassColor
		for _, w in ipairs(fillDeps) do w:SetWidgetEnabled(editable) end
	end
	local r2, c2 = W.Row(d, 4, { height = fieldH })
	local cbHealPred = W.Checkbox(c2[1], { label = "Heilvorhersage",
		tooltip = "Eingehende Heilung als Vorschau am Lebensbalken.", get = tget("healPrediction"), set = tset("healPrediction") })
	cbHealPred:SetPoint("TOPLEFT", c2[1], "TOPLEFT", 0, fillOff)
	local cbClass = W.Checkbox(c2[2], { label = "Klassenfarbe als Füllfarbe", get = tget("useClassColor"),
		set = function(v) rf().useClassColor = v; relayout(); refreshFill() end })
	cbClass:SetPoint("TOPLEFT", c2[2], "TOPLEFT", 0, fillOff)
	local swFill = W.ColorSwatch(c2[3], { label = "Füllfarbe", field = true, get = tcget("fillColor"), set = tcset("fillColor") })
	swFill:SetPoint("TOPLEFT", c2[3], "TOPLEFT", 0, 0)
	local swBg = W.ColorSwatch(c2[4], { label = "Hintergrundfarbe", field = true, get = tcget("bgColor"), set = tcset("bgColor") })
	swBg:SetPoint("TOPLEFT", c2[4], "TOPLEFT", 0, 0)
	sBar:place(r2, fieldH, R.row)
	fillDeps[1] = swFill; refreshFill()

	-- Unter-Box „Transparenz": 2×2 Deckkraft-Slider (Hintergrund/Lebensbalken · Schild/Healabsorb).
	local boxT = sBar:subgroup({ title = "Transparenz" })
	local trA, tcA = W.Row(d, 2, { height = M.sliderH })
	W.Slider(tcA[1], { label = "Hintergrund-Deckkraft", min = 0, max = 100, unit = " %", get = pctget("bgAlpha"), set = pctset("bgAlpha") }):SetAllPoints(tcA[1])
	W.Slider(tcA[2], { label = "Lebensbalken-Deckkraft", min = 0, max = 100, unit = " %", get = pctget("healthAlpha"), set = pctset("healthAlpha") }):SetAllPoints(tcA[2])
	boxT:place(trA, M.sliderH, R.row)
	local trB, tcB = W.Row(d, 2, { height = M.sliderH })
	W.Slider(tcB[1], { label = "Schild-Deckkraft", min = 0, max = 100, unit = " %", get = pctget("shieldAlpha"), set = pctset("shieldAlpha") }):SetAllPoints(tcB[1])
	W.Slider(tcB[2], { label = "Healabsorb-Deckkraft", min = 0, max = 100, unit = " %", get = pctget("healAbsorbAlpha"), set = pctset("healAbsorbAlpha") }):SetAllPoints(tcB[2])
	boxT:place(trB, M.sliderH, R.tight)
	boxT:close()
	sBar:close()

	-- ===== Text (GETEILT: Farbe + Umrandung gelten für Raid & Gruppe gleich) =====
	local sText = stack:section("Text")
	local nameColDeps = {}
	local function refreshNameCol()
		local on = not rf().nameClassColor
		for _, w in ipairs(nameColDeps) do w:SetWidgetEnabled(on) end
	end
	-- Reihe 1: Name in Klassenfarbe (Check) | Namens-Umrandung | HP-Umrandung.
	local txR1, txc1 = W.Row(d, 3, { height = fieldH })
	local cbNameCC = W.Checkbox(txc1[1], { label = "Name in Klassenfarbe", get = tget("nameClassColor"),
		set = function(v) rf().nameClassColor = v; relayout(); refreshNameCol() end })
	cbNameCC:SetPoint("TOPLEFT", txc1[1], "TOPLEFT", 0, fillOff)
	W.Select(txc1[2], { label = "Namens-Umrandung", options = OUTLINE_OPTS, get = tget("nameOutline"), set = tset("nameOutline") }):SetAllPoints(txc1[2])
	W.Select(txc1[3], { label = "HP-Umrandung", options = OUTLINE_OPTS, get = tget("healthTextOutline"), set = tset("healthTextOutline") }):SetAllPoints(txc1[3])
	sText:place(txR1, fieldH, R.row)
	-- Reihe 2: Namensfarbe | HP-Text-Farbe (Field-Swatches).
	local txR2, txc2 = W.Row(d, 3, { height = fieldH })
	local swName = W.ColorSwatch(txc2[1], { label = "Namensfarbe", field = true, get = tcget("nameColor"), set = tcset("nameColor") })
	swName:SetPoint("TOPLEFT", txc2[1], "TOPLEFT", 0, 0)
	W.ColorSwatch(txc2[2], { label = "HP-Text-Farbe", field = true, get = tcget("healthTextColor"), set = tcset("healthTextColor") }):SetPoint("TOPLEFT", txc2[2], "TOPLEFT", 0, 0)
	sText:place(txR2, fieldH, R.tight)
	sText:close()
	nameColDeps[1] = swName; refreshNameCol()

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
	sDispel:place(dRow1, M.checkBox, R.afterCheck)

	local boxD = sDispel:subgroup() -- Unter-Box: Typ-Farben / Darstellung-Deckkraft

	-- Reihe 2: Typ-Farben (Magie/Fluch/Krankheit/Gift) — vor der Slider-Reihe, damit
	-- die Slider-Wertbox unten nicht an den Farben klebt.
	local dColRow, dcc = W.Row(d, 4, { height = fieldH })
	local dispColW = {}
	for i, t in ipairs(DISPEL_TYPES) do
		local sw = W.ColorSwatch(dcc[i], { label = t.label, field = true, get = dcget(t.key), set = dcset(t.key) })
		sw:SetPoint("TOPLEFT", dcc[i], "TOPLEFT", 0, 0)
		dispColW[i] = sw
	end
	boxD:place(dColRow, fieldH, R.row)

	-- Reihe 3: Darstellung (Spalte 1) + Overlay-Deckkraft (Spalte 2) im Raster.
	local dr2, dc2 = W.Row(d, 3, { height = M.sliderH })
	local dispMode = W.Select(dc2[1], { label = "Darstellung", options = DISPEL_MODE_OPTS,
		get = tget("dispelMode"), set = function(v) tset("dispelMode")(v); refreshDispel() end })
	dispMode:SetAllPoints(dc2[1])
	dispelAlphaW = W.Slider(dc2[2], { label = "Overlay-Deckkraft", min = 0, max = 100, unit = " %",
		get = pctget("dispelAlpha"), set = pctset("dispelAlpha") })
	dispelAlphaW:SetAllPoints(dc2[2])
	boxD:place(dr2, M.sliderH, R.tight)
	boxD:close()
	sDispel:close()

	for _, w in ipairs({ dispMode, cbShowAll, dispColW[1], dispColW[2], dispColW[3], dispColW[4] }) do
		dispelDeps[#dispelDeps + 1] = w
	end
	refreshDispel()

	-- ===== Aggro-Warnung ===================================================
	local sAggro = stack:section("Aggro-Warnung")

	local aggroAlways = {}                 -- nur an aggroEnabled gekoppelt
	local aggroAlphaW
	local aggroTextOpts = {}               -- nur aktiv, wenn Text wirklich angezeigt wird
	local function refreshAggro()
		local en = rf().aggroEnabled and true or false
		for _, w in ipairs(aggroAlways) do w:SetWidgetEnabled(en) end
		aggroAlphaW:SetWidgetEnabled(en and (rf().aggroModeAggro == "overlay" or rf().aggroModeWarn == "overlay"))
		local textActive = (rf().aggroModeAggro == "overlay" and rf().aggroTextAggro)
			or (rf().aggroModeWarn == "overlay" and rf().aggroTextWarn)
		for _, w in ipairs(aggroTextOpts) do w:SetWidgetEnabled(en and textActive and true or false) end
	end

	local agRow = CreateFrame("Frame", nil, d)
	local cbAggro = W.Checkbox(agRow, { label = "Aggro-Warnung anzeigen (Tanks ausgenommen)",
		get = tget("aggroEnabled"), set = function(v) rf().aggroEnabled = v; relayout(); refreshAggro() end })
	cbAggro:SetPoint("LEFT", agRow, "LEFT", 0, 0)
	sAggro:place(agRow, M.checkBox, R.afterCheck)

	-- Eine Aggro-Stufe (rot/gelb) als getitelte Unter-Box: Darstellung | Farbe.
	-- Das Darstellung-Dropdown vereint Modus + Text (3 Optionen): „Rand + Overlay +
	-- Text" = overlay-Modus mit Text. Geschrieben werden weiter die getrennten
	-- Profil-Felder modeKey + textKey (Datenmodell/Render unverändert).
	local function aggroStage(label, colorKey, modeKey, textKey)
		local box = sAggro:subgroup({ title = label })
		local r, c = W.Row(d, 3, { height = fieldH })
		local mode = W.Select(c[1], { label = "Darstellung", options = AGGRO_MODE_OPTS,
			get = function()
				if rf()[modeKey] == "overlay" and rf()[textKey] then return "overlaytext" end
				return rf()[modeKey]
			end,
			set = function(v)
				if v == "overlaytext" then rf()[modeKey] = "overlay"; rf()[textKey] = true
				elseif v == "overlay" then rf()[modeKey] = "overlay"; rf()[textKey] = false
				else rf()[modeKey] = "border"; rf()[textKey] = false end
				relayout(); refreshAggro()
			end })
		mode:SetAllPoints(c[1])
		local sw = W.ColorSwatch(c[2], { label = "Farbe", field = true, get = tcget(colorKey), set = tcset(colorKey) })
		sw:SetPoint("TOPLEFT", c[2], "TOPLEFT", 0, 0)
		box:place(r, fieldH, R.tight)
		box:close()
		aggroAlways[#aggroAlways + 1] = sw
		aggroAlways[#aggroAlways + 1] = mode
	end
	aggroStage("Hat Aggro (rot)",    "aggroColorAggro", "aggroModeAggro", "aggroTextAggro")
	aggroStage("Aggro droht (gelb)", "aggroColorWarn",  "aggroModeWarn",  "aggroTextWarn")

	-- Geteilte Text-Darstellung beider Stufen — eigene getitelte Unter-Box.
	local boxShared = sAggro:subgroup({ title = "Text (beide Stufen)" })
	-- Reihe 1: Textposition | Text-Umrandung | Overlay-Deckkraft.
	local ar1, ac1 = W.Row(d, 3, { height = M.sliderH })
	local agPoint = W.Select(ac1[1], { label = "Textposition", options = POINT_OPTS, get = tget("aggroTextPoint"), set = tset("aggroTextPoint") })
	agPoint:SetAllPoints(ac1[1])
	local agOutline = W.Select(ac1[2], { label = "Text-Umrandung", options = OUTLINE_OPTS, get = tget("aggroTextOutline"), set = tset("aggroTextOutline") })
	agOutline:SetAllPoints(ac1[2])
	aggroAlphaW = W.Slider(ac1[3], { label = "Overlay-Deckkraft", min = 0, max = 100, unit = " %",
		get = pctget("aggroFillAlpha"), set = pctset("aggroFillAlpha") })
	aggroAlphaW:SetAllPoints(ac1[3])
	boxShared:place(ar1, M.sliderH, R.row)

	-- Reihe 2: Textgröße | Text X-Versatz | Text Y-Versatz.
	local ar2, ac2 = W.Row(d, 3, { height = M.sliderH })
	local agSize = W.Slider(ac2[1], { label = "Textgröße", min = 6, max = 28, get = tget("aggroTextSize"), set = tset("aggroTextSize") })
	agSize:SetAllPoints(ac2[1])
	local agX = W.Slider(ac2[2], { label = "Text X-Versatz", min = -60, max = 60, get = tget("aggroTextX"), set = tset("aggroTextX") })
	agX:SetAllPoints(ac2[2])
	local agY = W.Slider(ac2[3], { label = "Text Y-Versatz", min = -60, max = 60, get = tget("aggroTextY"), set = tset("aggroTextY") })
	agY:SetAllPoints(ac2[3])
	boxShared:place(ar2, M.sliderH, R.tight)
	boxShared:close()
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
				tooltip = "Aus: im Raid bleibt deine Anordnung. An: die Rollen-Sortierung greift! "
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

	-- Body in den äußeren Stack einhängen + initial gaten (Modul aus -> alles grau).
	outerStack:place(body, bstack:height(), 0)
	applyModuleGate(body, rf().enabled)
end

-- ---------------------------------------------------------------------------
--  Eine Aura-Kategorie als Sektions-Karte (spiegelt auraCatGroup aus Options.lua).
--  „Anzeigen" ist der Master: aus -> alle übrigen Controls ausgegraut. „Auto-Fit"
--  graut zusätzlich die beiden Größen-Slider. `isDebuff` blendet den Filter ein.
-- ---------------------------------------------------------------------------
-- Innen/Außen-Optionen (kontextabhängiger Segment-Schalter): false = Icons IM Frame,
-- true = Reihe komplett nach außen ausgelagert (neben/über/unter dem Frame).
local PLACE_OPTS = { { value = false, label = "Innen" }, { value = true, label = "Außen" } }
local CTX_OPTS   = { { value = "Raid", label = "Raid" }, { value = "Party", label = "Gruppe" } }

local function auraCat(d, stack, cat, label, isDebuff)
	local fieldH = M.controlH + M.fieldGap
	local R = L.rhythm
	local s = stack:section(label)

	-- Kontext-Zustand DIESER Karte: welchen Kontext die Platzierungs-Box zeigt/speichert.
	-- „Menge & Verhalten" ist geteilt und davon unberührt. Default Raid (Label macht's eindeutig).
	local ctx = "Raid"
	local function cget(base) return function() return aget(cat, base .. ctx)() end end
	local function cset(base) return function(v) aset(cat, base .. ctx)(v) end end

	local deps = {}            -- an „Anzeigen" gekoppelt (alle Controls außer Master + Größe)
	local placeRefresh = {}    -- Platzierungs-Controls: Wert beim Kontextwechsel neu ziehen
	local sizeW                -- Größen-Slider (zusätzlich an „Auto-Fit" gekoppelt)

	local function refresh()
		local on = aget(cat, "enabled")() and true or false
		for _, w in ipairs(deps) do w:SetWidgetEnabled(on) end
		if sizeW then sizeW:SetWidgetEnabled(on and not aget(cat, "autoFit")()) end
	end
	local function switchCtx(v)
		ctx = v
		for _, fn in ipairs(placeRefresh) do fn() end
	end
	-- Platzierungs-Control: an „Anzeigen" koppeln + beim Kontextwechsel auf den neuen Wert ziehen.
	local function place(widget, getter)
		deps[#deps + 1] = widget
		placeRefresh[#placeRefresh + 1] = function() if widget.SetValueExternal then widget:SetValueExternal(getter()) end end
		return widget
	end

	-- „Anzeigen" (Master) — frei in der Karte, ÜBER den Unter-Boxen.
	local mRow = CreateFrame("Frame", nil, d)
	local cbOn = W.Checkbox(mRow, { label = "Anzeigen", get = aget(cat, "enabled"),
		set = function(v) aset(cat, "enabled")(v); refresh() end })
	cbOn:SetPoint("LEFT", mRow, "LEFT", 0, 0)
	s:place(mRow, M.checkBox, R.afterCheck)

	-- ── Unter-Box A: Menge & Verhalten (GETEILT für Raid + Gruppe) ───────
	local boxA = s:subgroup({ title = "Menge & Verhalten" })
	local a1, ac = W.Row(d, 2, { height = M.sliderH })
	local maxW = W.Slider(ac[1], { label = "Max. Icons", min = 1, max = 8, get = aget(cat, "maxIcons"), set = aset(cat, "maxIcons") })
	maxW:SetAllPoints(ac[1])
	local spaceW = W.Slider(ac[2], { label = "Abstand", min = 0, max = 20, unit = " px", get = aget(cat, "spacing"), set = aset(cat, "spacing") })
	spaceW:SetAllPoints(ac[2])
	deps[#deps + 1] = maxW; deps[#deps + 1] = spaceW
	boxA:place(a1, M.sliderH, R.row)

	-- Auto-Fit + Cooldown-Swipe (zwei Checkboxen nebeneinander).
	local a2, ac2 = W.Row(d, 2, { height = M.checkBox })
	local cbFit = W.Checkbox(ac2[1], { label = "Auto-Fit (Größe aus Frame-Höhe)", get = aget(cat, "autoFit"),
		set = function(v) aset(cat, "autoFit")(v); refresh() end })
	cbFit:SetPoint("LEFT", ac2[1], "LEFT", 0, 0)
	local cbSwipe = W.Checkbox(ac2[2], { label = "Cooldown-Swipe", get = aget(cat, "showSwipe"), set = aset(cat, "showSwipe") })
	cbSwipe:SetPoint("LEFT", ac2[2], "LEFT", 0, 0)
	deps[#deps + 1] = cbFit; deps[#deps + 1] = cbSwipe
	boxA:place(a2, M.checkBox, isDebuff and R.row or R.tight)

	if isDebuff then
		local a3, ac3 = W.Row(d, 2, { height = fieldH })
		local filterW = W.Select(ac3[1], { label = "Filter", options = AURA_FILTER_OPTS,
			tooltip = "Welche Debuffs gezeigt werden. Raid-relevant = Blizzards Standard-Auswahl.",
			get = aget(cat, "filterMode"), set = aset(cat, "filterMode") })
		filterW:SetAllPoints(ac3[1])
		deps[#deps + 1] = filterW
		boxA:place(a3, fieldH, R.tight)
	end
	boxA:close()

	-- ── Unter-Box B: Platzierung & Größe (PRO KONTEXT — Raid/Gruppe-Schalter) ──
	local boxB = s:subgroup({ title = "Platzierung & Größe" })
	-- Raid|Gruppe-Schalter im Box-Header rechts: schaltet NUR diese Box, lokal (kein Hochscrollen).
	local ctxSeg = W.Segment(boxB._panel, { options = CTX_OPTS, get = function() return ctx end, set = switchCtx, width = 150, cellH = 26 })
	ctxSeg:SetPoint("TOPRIGHT", boxB._panel, "TOPRIGHT", -M.subgroupPad, -10)
	ctxSeg:SetFrameLevel(boxB._panel:GetFrameLevel() + 5)
	deps[#deps + 1] = ctxSeg

	-- Reihe: Anker | Wachstum | Innen/Außen (alle controlH-basiert -> aligned).
	local b1, bc = W.Row(d, 3, { height = fieldH })
	place(W.Select(bc[1], { label = "Position (Anker)", options = POINT_OPTS, get = cget("anchor"), set = cset("anchor") }), cget("anchor")):SetAllPoints(bc[1])
	place(W.Select(bc[2], { label = "Wachstumsrichtung", options = GROW_OPTS, get = cget("grow"), set = cset("grow") }), cget("grow")):SetAllPoints(bc[2])
	place(W.Segment(bc[3], { label = "Platzierung", options = PLACE_OPTS, get = cget("outside"), set = cset("outside") }), cget("outside")):SetAllPoints(bc[3])
	boxB:place(b1, fieldH, R.row)

	-- Reihe: Versatz X | Versatz Y | Größe (alle Slider).
	local b2, bc2 = W.Row(d, 3, { height = M.sliderH })
	place(W.Slider(bc2[1], { label = "Versatz X", min = -80, max = 80, unit = " px", get = cget("offX"), set = cset("offX") }), cget("offX")):SetAllPoints(bc2[1])
	place(W.Slider(bc2[2], { label = "Versatz Y", min = -80, max = 80, unit = " px", get = cget("offY"), set = cset("offY") }), cget("offY")):SetAllPoints(bc2[2])
	sizeW = W.Slider(bc2[3], { label = "Größe", min = 8, max = 80, unit = " px", get = cget("size"), set = cset("size") })
	sizeW:SetAllPoints(bc2[3])
	placeRefresh[#placeRefresh + 1] = function() sizeW:SetValueExternal(cget("size")()) end
	boxB:place(b2, M.sliderH, R.tight)
	boxB:close()

	s:close()
	refresh()
end

-- ---------------------------------------------------------------------------
--  AurasScreen — Aura-Indikatoren je Kategorie (Prototyp/AceConfig-Auras-Tab).
--  Drei Kategorien: eigene HoTs, Defensives & Externe, Debuffs.
-- ---------------------------------------------------------------------------
local function buildAuras(d, stack)
	stack:gap(L.base.topToToggle)
	local intro = W.Hint(d, "Aura-Indikatoren am Frame: eigene HoTs, Defensives & Externe, Debuffs. "
		.. "Menge & Verhalten gelten für Raid und Gruppe; Platzierung & Größe stellst du pro Kontext "
		.. "ein (Raid/Gruppe-Schalter in der Karte). Welche Spells getrackt werden, regelt der Tab "
		.. "\"Tracking\". Im Testmodus (Tab \"Base\") zur Vorschau sichtbar.", L.tracking.introH)
	stack:place(intro, L.tracking.introH, L.auras.afterIntro)

	auraCat(d, stack, "hotsOwn",    "HoTs",                 false)
	auraCat(d, stack, "defensives", "Defensives & Externe", false)
	auraCat(d, stack, "major",      "Major CDs",            false)
	auraCat(d, stack, "debuffs",    "Debuffs",              true)

	applyModuleGate(d, rf().enabled) -- Modul aus -> ganzer Auras-Screen grau + gesperrt
end

-- ---------------------------------------------------------------------------
--  TrackingScreen — Whitelist-Editor (B4): welche Spells als Aura-Icons getrackt
--  werden (HoTs + eigene Defensiven). Spiegelt den AceConfig-Tab „Tracking".
--  IMMER an die AKTIVE Spec gebunden (Talente/Zauberbuch nur dafür auslesbar;
--  Defaults decken andere Specs ab). Spell-Quelle = ns.ClickCast:GetAuraSpells()
--  (Zauberbuch + gewählte Talente). Kernstück: W.SpellPicker (suchbar + scrollbar).
-- ---------------------------------------------------------------------------
local TRACK_CATS = {
	{ typ = "hot", label = "HoTs",                 desc = "Eigene Heilung über Zeit als Icon am Frame." },
	{ typ = "def", label = "Defensives & Externe", desc = "Eigene Defensiven. Externe Schutzzauber anderer zeigt Lumen ohnehin automatisch." },
	{ typ = "major", label = "Major CDs", desc = "Große Schadens- und Ressourcen-Cooldowns deiner Klasse" },
}

local function trkSpec() return (ns.ClickCast and ns.ClickCast:CurrentSpecID()) or 0 end

-- Eine getrackte-Spell-Zeile: Icon + Name + „Entfernen" (danger, rechts).
local function makeTrackRow(parent, e, onRemove)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(M.trackRowH)
	UI.Fill(row, C.ink520)
	UI.Border(row, UI.line.faint, 1, "OVERLAY") -- L ist hier UI.LAYOUT; Gold-Deckkräfte liegen in UI.line
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(M.trackIcon, M.trackIcon)
	icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(e.icon or 136243)
	local rm = W.Button(row, { text = "Entfernen", variant = "danger", width = M.trackRemoveW, onClick = onRemove })
	rm:SetHeight(M.trackRowH - 10)
	rm:ClearAllPoints(); rm:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	local name = UI.FS(row, "selectText", C.textStrong)
	name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	name:SetPoint("RIGHT", rm, "LEFT", -10, 0)
	name:SetJustifyH("LEFT"); name:SetWordWrap(false)
	name:SetText(e.name or ("Spell " .. tostring(e.id)))
	-- Hover: dezenter Wash + eigener Lumen-Spell-Tooltip (wie die Picker-Liste).
	local hov = UI.Fill(row, C.inkTint, "BORDER"); hov:SetAllPoints(row); hov:SetAlpha(0)
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self2)
		hov:SetAlpha(0.5); W.ShowSpellTip(self2, e.id)
	end)
	row:SetScript("OnLeave", function() hov:SetAlpha(0); W.HideTip() end)
	return row
end

local function buildTracking(d, stack)
	local RFm  = ns.Raidframes
	local spec = trkSpec()

	stack:gap(L.base.topToToggle)
	local intro = W.Hint(d, "Welche Spells als Aura-Icons getrackt werden — Anzeige & Position regelt der Tab \"Auras\". "
		.. "Bearbeitet wird automatisch deine aktive Spec (Talente anderer Specs kann WoW nicht auslesen; deren Defaults greifen automatisch, sobald du sie spielst).")
	stack:place(intro, L.tracking.introH, L.tracking.afterIntro)

	local specRow = CreateFrame("Frame", nil, d)
	specRow:SetHeight(20)
	local specFS = UI.FS(specRow, "label", C.gold250)
	specFS:SetPoint("TOPLEFT", specRow, "TOPLEFT", 0, 0)
	specFS:SetText("Aktive Spec:  " .. ((ns.ClickCast and ns.ClickCast:CurrentSpecName()) or "?"))
	stack:place(specRow, 20, L.tracking.afterSpec)

	for _, cat in ipairs(TRACK_CATS) do
		local s = stack:section(cat.label)

		local desc = W.Hint(d, cat.desc)
		s:place(desc, M.hintH, L.tracking.afterDesc)

		-- Getrackte Spells als Zeilen (oder „(keine Spells)").
		local entries = (RFm and RFm:WhitelistEntries(spec, cat.typ)) or {}
		if #entries == 0 then
			s:place(W.Hint(d, "(keine Spells)"), L.tracking.emptyH, L.tracking.afterList)
		else
			for i, e in ipairs(entries) do
				local last = (i == #entries)
				local row = makeTrackRow(d, e, function()
					if RFm then RFm:RemoveWhitelist(spec, e.id) end
					ns.Shell:RenderContent(true)
				end)
				s:place(row, M.trackRowH, last and L.tracking.afterList or L.tracking.betweenRows)
			end
		end

		-- Aktions-Reihe: Spell-Picker (suchbar/scrollbar) + „Standard wiederherstellen".
		local actionRow = CreateFrame("Frame", nil, d)
		actionRow:SetHeight(M.buttonH)
		local picker = W.SpellPicker(actionRow, {
			text = "+ Spell hinzufügen", width = M.spBtnW,
			fetch = function()
				local out = {}
				local tracked = (RFm and RFm:WhitelistMap(spec)) or {}
				for _, sp in ipairs((ns.ClickCast and ns.ClickCast:GetAuraSpells()) or {}) do
					-- Talent-IDs auf die echte Aura-ID normalisieren -> schon getrackte raus.
					local rid = (RFm and RFm.ResolveTrackId) and RFm:ResolveTrackId(sp.id) or sp.id
					if not tracked[rid] then out[#out + 1] = sp end
				end
				return out
			end,
			onPick = function(id)
				if RFm then RFm:AddWhitelist(spec, id, cat.typ) end
				ns.Shell:RenderContent(true)
			end,
		})
		picker:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
		local reset = W.Button(actionRow, { text = "Standard wiederherstellen", variant = "ghost",
			onClick = function()
				W.Confirm({
					title       = "Standard wiederherstellen?",
					body        = "Diese Liste wird auf Lumens kuratierten Standard für deine aktive Spec zurückgesetzt. Eigene Einträge in dieser Kategorie gehen dabei verloren.",
					confirmText = "Zurücksetzen",
					cancelText  = "Abbrechen",
					onConfirm   = function()
						if RFm then RFm:ResetWhitelist(spec, cat.typ) end
						ns.Shell:RenderContent(true)
					end,
				})
			end })
		reset:SetPoint("LEFT", picker, "RIGHT", 12, 0)
		s:place(actionRow, M.buttonH, 0)

		s:close()
	end

	applyModuleGate(d, rf().enabled) -- Modul aus -> ganzer Screen grau + gesperrt
end

-- ===========================================================================
--  Click-Cast-Screen — Maus-Bindings („Klick auf Frame") + Hovercast (Tastatur)
--  in EINEM Tab, zwei Sektionskarten. Verdrahtet gegen ns.ClickCast (Datenmodell
--  + Apply bleiben im Modul). Spell-Auswahl über W.SpellPicker (echte Typeahead-
--  Suche), Hovercast-Taste über W.KeybindButton. „Nur außerhalb Kampf" jetzt auch
--  für Menü (löst versehentliche Menüs im Kampf — wirkt nur auf Lumens Frames).
-- ===========================================================================
local function cc() return ns.Lumen.db.profile.clickCast end
local function CCm() return ns.ClickCast end
local function ccApply() if CCm() then CCm():ApplyBindings() end end

local ccSelectedSpec  -- welche Spec bearbeitet wird (entkoppelt von der Live-Spec)

-- Hovercast ist P2: Die Secure-Tasten-Treiber-Mechanik (Taste nur beim Hovern aktiv,
-- sonst normale Aktionsleiste) gibt die Taste in 12.0.7 nicht mehr sauber frei -> belegte
-- Hovercast-Taste blockiert die Aktionsleiste. Bis zur 12.1.0-Nacharbeit (ggf. robusterer
-- Ansatz) Sektion ausgeblendet; Code + Datenmodell bleiben. ClickCast.lua legt
-- vorhandene Hovercast-Bindings parallel „schlafend" (applyHover ist dann ein No-op).
local CC_HOVERCAST = false

local CC_MOD_OPTS = {
	{ value = "",      label = "Kein" },
	{ value = "SHIFT", label = "Shift" },
	{ value = "CTRL",  label = "Strg" },
	{ value = "ALT",   label = "Alt" },
}
local CC_ACTION_OPTS = {
	{ value = "target", label = "Ziel" },
	{ value = "menu",   label = "Menü" },
	{ value = "spell",  label = "Spell" },
	{ value = "dispel", label = "Dispel" },
	{ value = "rez",    label = "Wiederbeleben" },
}
local function ccMouseOpts()
	local opts, m = {}, CCm()
	if m then for _, k in ipairs(m.MOUSE_BUTTON_SORTING) do
		opts[#opts + 1] = { value = k, label = m.MOUSE_BUTTON_VALUES[k] }
	end end
	return opts
end
-- Spec-Dropdown mit Icon (FontStrings rendern |T..|t inline, wie der AceConfig-Tab).
local function ccSpecOpts()
	local opts, m = {}, CCm()
	if m then for _, s in ipairs(m:GetSpecList()) do
		local lbl = (s.icon and ("|T" .. s.icon .. ":14:14:0:0|t  ") or "") .. (s.name or "?")
		opts[#opts + 1] = { value = s.id, label = lbl }
	end end
	return opts
end
-- Spell-Kandidaten für den Picker (Klassen-Zauberbuch, optional auf hilfreiche gefiltert).
local function ccSpellFetch()
	local out, m = {}, CCm()
	if not m then return out end
	local onlyHelpful = cc().helpfulOnly
	for _, s in ipairs(m:GetClassSpells()) do
		if (not onlyHelpful) or s.friendly then out[#out + 1] = s end
	end
	return out
end

-- Eine Binding-Box (hellere Unter-Box mit Kopfzeile „Taste → Aktion" + Entfernen).
-- s = Stapler der Sektionskarte; b = Bindung; isHover = Hovercast (Tastatur).
local function ccBindingBox(d, s, b, isHover, spec)
	local LC = L.clickcast
	local fieldH = M.controlH + M.fieldGap
	local box = s:subgroup()

	-- Kopf: NUR die Keycap (kombinierte Taste/Maustaste) + „Entfernen". Spell-Name/Icon
	-- bewusst NICHT hier — der Picker-Button unten zeigt sie schon (sonst doppelt).
	local hd = CreateFrame("Frame", nil, d)
	hd:SetHeight(M.controlH)

	-- Keycap: quadratisch (min controlH×controlH), DUNKLER + kräftigerer Gold-Rand +
	-- ZENTRIERTER Text -> liest sich als „Taste", nicht als Dropdown (heller, chevron, linksbündig).
	local cap = CreateFrame("Frame", nil, hd)
	cap:SetHeight(M.controlH)
	cap:SetPoint("LEFT", hd, "LEFT", 0, 0)
	UI.Fill(cap, C.ink850)
	UI.Border(cap, UI.line.strong, 1, "OVERLAY")
	local capTxt = UI.FS(cap, "selectText", C.gold300)
	capTxt:SetPoint("CENTER", cap, "CENTER", 0, 0)
	capTxt:SetText((CCm() and CCm():FormatKey(b.key)) or "—")
	cap:SetWidth(math.max(M.controlH, math.ceil(capTxt:GetStringWidth()) + 20))

	local rm = W.Button(hd, { text = "Entfernen", variant = "danger", width = M.trackRemoveW,
		onClick = function()
			local idx
			for i, x in ipairs(CCm():GetBindings(spec)) do if x == b then idx = i; break end end
			if idx then CCm():RemoveBinding(spec, idx) end
			ns.Shell:RenderContent(true)
		end })
	rm:ClearAllPoints(); rm:SetPoint("RIGHT", hd, "RIGHT", 0, 0)
	box:place(hd, M.controlH, LC.headToRow)

	-- Reihe 1: Klick = [Maustaste | Aktion | Modifier]; Hover = [Taste | Aktion | —].
	local r1, c1 = W.Row(d, 3, { height = fieldH })
	if isHover then
		local kb = W.KeybindButton(c1[1], { label = "Taste",
			format = function(k) return (CCm() and CCm():FormatKey(k)) or k end,
			get = function() return b.key end,
			set = function(v) b.key = v; ccApply(); ns.Shell:RenderContent(true) end })
		kb:SetAllPoints(c1[1])
	else
		local mb = W.Select(c1[1], { label = "Maustaste", options = ccMouseOpts(),
			get = function() local _, btn = CCm():KeyParts(b.key); return (btn ~= "" and btn) or "BUTTON1" end,
			set = function(v) local mod = CCm():KeyParts(b.key); b.key = CCm():BuildKey(mod, v); ccApply(); ns.Shell:RenderContent(true) end })
		mb:SetAllPoints(c1[1])
	end
	local act = W.Select(c1[2], { label = "Aktion", options = CC_ACTION_OPTS,
		get = function() return b.type end,
		set = function(v) b.type = v; ccApply(); ns.Shell:RenderContent(true) end })
	act:SetAllPoints(c1[2])
	if not isHover then
		local mod = W.Select(c1[3], { label = "Modifier", options = CC_MOD_OPTS,
			get = function() local m = CCm():KeyParts(b.key); return m or "" end,
			set = function(v) local _, btn = CCm():KeyParts(b.key); b.key = CCm():BuildKey(v, (btn ~= "" and btn) or "BUTTON1"); ccApply(); ns.Shell:RenderContent(true) end })
		mod:SetAllPoints(c1[3])
	end
	box:place(r1, fieldH, LC.betweenRows)

	-- Reihe 2 (nur Aktion „Spell"): Spell-Picker (suchbar/scrollbar).
	if b.type == "spell" then
		local spIcon = b.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID) or nil
		local picker = W.SpellPicker(d, {
			text = b.spell or "Spell wählen …", icon = spIcon, width = M.spW,
			fetch = ccSpellFetch,
			onPick = function(id)
				b.spellID = id
				b.spell = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or b.spell
				ccApply(); ns.Shell:RenderContent(true)
			end,
		})
		box:placeLeft(picker, M.buttonH, LC.betweenRows)
	end

	-- Reihe 3: Checkboxen. Klick: nur „Nur außerhalb Kampf" (außer Aktion = Ziel).
	-- Hover: „Nur Freundlich"/„Nur Feindlich" (nur Spell) + „Nur außerhalb Kampf".
	local defs = {}
	if isHover and b.type == "spell" then
		defs[#defs + 1] = { label = "Nur Freundlich", tooltip = "Nur auf freundliche Units wirken.",
			get = function() return b.hoverFriendly end, set = function(v) b.hoverFriendly = v; ccApply() end }
		defs[#defs + 1] = { label = "Nur Feindlich", tooltip = "Nur auf feindliche Units wirken.",
			get = function() return b.hoverEnemy end, set = function(v) b.hoverEnemy = v; ccApply() end }
	end
	if b.type ~= "target" then
		defs[#defs + 1] = { label = "Nur außerhalb Kampf",
			tooltip = (b.type == "menu") and "Verhindert versehentliche Menüs im Kampf — wirkt nur auf Lumens Frames." or "Nur außerhalb des Kampfes auslösen.",
			get = function() return b.oocOnly end, set = function(v) b.oocOnly = v; ccApply() end }
	end
	if #defs > 0 then
		local cr = CreateFrame("Frame", nil, d)
		cr:SetHeight(M.checkBox)
		local prev
		for _, dc in ipairs(defs) do
			local chk = W.Checkbox(cr, dc)
			chk:ClearAllPoints()
			if prev then chk:SetPoint("LEFT", prev, "RIGHT", L.general.checkRowGap, 0)
			else chk:SetPoint("LEFT", cr, "LEFT", 0, 0) end
			prev = chk
		end
		box:place(cr, M.checkBox, 0)
	end

	box:close()
end

local function buildClickCast(d, stack)
	local LC = L.clickcast
	local m = CCm()
	local spec = ccSelectedSpec
	if not spec and m then spec = m:CurrentSpecID(); ccSelectedSpec = spec end

	-- Master (frei über allem) — wie „Raidframes aktiviert".
	local outerStack = stack
	local body
	stack:gap(LC.topToHead)
	local mRow = CreateFrame("Frame", nil, d)
	local cbMaster = W.Checkbox(mRow, { label = "Click-Cast aktiviert",
		tooltip = "Übernimmt die Klicks auf die Raidframe-Buttons. Aus = WoW-Standard (Links = Ziel, Rechts = Menü).",
		get = function() return cc().enabled end,
		set = function(v) cc().enabled = v; ccApply(); applyModuleGate(body, v) end })
	cbMaster:SetPoint("LEFT", mRow, "LEFT", 0, 0)
	stack:place(mRow, M.checkBox, LC.afterMaster)

	-- Alles Weitere in ein gate-bares Body-Frame (bei „aus" gedimmt + gesperrt).
	body = CreateFrame("Frame", nil, d)
	local bstack = ns.Shell.NewStack(body)
	d, stack = body, bstack

	-- Spec-Auswahl (entkoppelt von der Live-Spec) — rasterbündig in Spalte 1.
	local sr, sc = W.Row(d, 3, { height = M.controlH + M.fieldGap })
	W.Select(sc[1], { label = "Spec (bearbeiten)", options = ccSpecOpts(), placeholder = "Keine Spec",
		tooltip = "Welche Spec du hier bearbeitest. Im Spiel gelten automatisch die Bindings deiner aktiven Spec.",
		get = function() return ccSelectedSpec end,
		set = function(v) ccSelectedSpec = v; ns.Shell:RenderContent(true) end }):SetAllPoints(sc[1])
	stack:place(sr, M.controlH + M.fieldGap, LC.afterSpec)

	local specHint = W.Hint(d, "Aktive Spec im Spiel:  " .. ((m and m:CurrentSpecName()) or "?")
		.. "  —  es gelten automatisch die Bindings deiner aktiven Spec.", 22)
	stack:place(specHint, 22, LC.afterCaption)

	local hRow = CreateFrame("Frame", nil, d)
	hRow:SetHeight(M.checkBox)
	local cbHelpful = W.Checkbox(hRow, { label = "Nur hilfreiche Zauber zur Auswahl anzeigen",
		tooltip = "Beschränkt die Spell-Liste auf Zauber, die du auf dich/Verbündete wirken kannst. Aus = alle Zauber.",
		get = function() return cc().helpfulOnly end, set = function(v) cc().helpfulOnly = v end })
	cbHelpful:SetPoint("LEFT", hRow, "LEFT", 0, 0)
	stack:place(hRow, M.checkBox, LC.afterHelpful)

	local bindings = (m and m:GetBindings(spec)) or {}

	-- ===== Klick auf Frame =================================================
	local sClick = stack:section("Klick auf Frame")
	local anyClick = false
	for _, b in ipairs(bindings) do
		if not b.hovercast then anyClick = true; ccBindingBox(d, sClick, b, false, spec) end
	end
	if not anyClick then
		sClick:place(W.Hint(d, "(keine Bindings)"), LC.emptyH, LC.afterList)
	end
	local addClick = W.Button(d, { text = "+ Klick-Binding hinzufügen", variant = "ghost",
		onClick = function()
			if m then m:AddBinding(spec, { key = "BUTTON3", type = "spell" }) end
			ns.Shell:RenderContent(true)
		end })
	sClick:placeLeft(addClick, M.buttonH, 0)
	sClick:close()

	-- ===== Hovercast (Mouseover) — P2, bis 12.1.0 ausgeblendet (siehe CC_HOVERCAST) =====
	if CC_HOVERCAST then
		local sHover = stack:section("Hovercast (Mouseover)")
		local intro = W.Hint(d, "Taste drücken, während die Maus über einer Unit schwebt — die Aktion geht auf "
			.. "die gehoverte Unit, ohne Klick. Die Taste wirkt nur beim Hovern; sonst macht sie ihr normales Ding.", LC.introH)
		sHover:place(intro, LC.introH, LC.afterIntro)
		local anyHover = false
		for _, b in ipairs(bindings) do
			if b.hovercast then anyHover = true; ccBindingBox(d, sHover, b, true, spec) end
		end
		if not anyHover then
			sHover:place(W.Hint(d, "(keine Bindings)"), LC.emptyH, LC.afterList)
		end
		local addHover = W.Button(d, { text = "+ Hovercast-Taste hinzufügen", variant = "ghost",
			onClick = function()
				if m then m:AddBinding(spec, { hovercast = true, type = "spell", hoverFriendly = true }) end
				ns.Shell:RenderContent(true)
			end })
		sHover:placeLeft(addHover, M.buttonH, 0)
		sHover:close()
	end

	outerStack:place(body, bstack:height(), 0)
	applyModuleGate(body, cc().enabled) -- Click-Cast aus -> alles unter dem Master grau + gesperrt
end

-- ===========================================================================
--  Global-Screens — suite-weite Einstellungen (spiegelt den AceConfig-Global-
--  Knoten). Base = Verschieben/Edit-Modus; Profile = Profilverwaltung (AceDB)
--  + Teilen (Export/Import, granular pro Modul, via ns.Share).
-- ===========================================================================

-- Global/Base: „Rahmen entsperren" (Edit-Modus) + „Positionen zurücksetzen".
local function buildGlobalBase(d, stack)
	local R = L.rhythm

	stack:gap(L.base.topToToggle)
	local intro = W.Hint(d, "Suite-weite Einstellungen. Profile, Export und Import deines Setups liegen im Tab \"Profile\".")
	stack:place(intro, M.hintH, R.row)

	local s = stack:section("Verschieben (Edit-Modus)")

	local togRow = CreateFrame("Frame", nil, d)
	local cbEdit = W.Checkbox(togRow, { label = "Rahmen entsperren — zeigt alle beweglichen Lumen-Elemente",
		get = function() return ns.EditMode and ns.EditMode:IsActive() end,
		set = function(v) if ns.EditMode then ns.EditMode:Toggle(v) end end })
	cbEdit:SetPoint("LEFT", togRow, "LEFT", 0, 0)
	s:place(togRow, M.checkBox, R.afterCheck)

	local resetBtn = W.Button(d, { text = "Positionen zurücksetzen", variant = "ghost",
		onClick = function()
			W.Confirm({
				title = "Positionen zurücksetzen?",
				body = "Setzt die Frame-Positionen (Raid und Gruppe) auf die Standardwerte zurück.",
				confirmText = "Zurücksetzen", cancelText = "Abbrechen",
				onConfirm = function()
					local r = rf()
					for _, ctx in ipairs({ "raid", "party" }) do
						local t = r[ctx]; if t then t.point, t.x, t.y = "CENTER", 0, -120 end
					end
					relayout()
				end,
			})
		end })
	s:placeLeft(resetBtn, M.buttonH, R.row)

	local hint = W.Hint(d, "Funktioniert auch über WoWs eigenen Edit-Modus: Lumen-Rahmen werden dort beweglich angezeigt.")
	s:place(hint, M.hintH, R.tight)
	s:close()
end

-- Global/Profile: transienter Zustand (file-local -> überlebt RenderContent-Neuaufbau).
-- Modul-/Layout-Auswahl lebt im Import-Popup (W.ImportDialog) selbst, nicht hier.
local shareExport    = ""    -- zuletzt erzeugter Export-Code
local shareImportRaw = ""    -- eingefügter Import-Text
local importErr      = nil   -- Fehlertext beim letzten „Importieren" (oder nil)

local function buildGlobalProfile(d, stack)
	local db = ns.Lumen.db
	local R = L.rhythm
	local G = L.global
	local fieldH = M.controlH + M.fieldGap

	stack:gap(L.base.topToToggle)

	-- Profilnamen als {value,label}-Liste (optional das aktive Profil ausklammern).
	local function profileOpts(excludeCurrent)
		local names = db:GetProfiles() or {}
		table.sort(names)
		local cur = db:GetCurrentProfile()
		local opts = {}
		for _, n in ipairs(names) do
			if not (excludeCurrent and n == cur) then opts[#opts + 1] = { value = n, label = n } end
		end
		return opts
	end

	-- ===== Profil ==========================================================
	local s = stack:section("Profil")

	-- Reihe 1: Aktuelles Profil | Kopieren von | Löschen.
	local r1, c1 = W.Row(d, 3, { height = fieldH })
	W.Select(c1[1], { label = "Aktuelles Profil", options = profileOpts(false),
		get = function() return db:GetCurrentProfile() end,
		set = function(v) db:SetProfile(v); ns.Shell:RenderContent(true) end }):SetAllPoints(c1[1])
	W.Select(c1[2], { label = "Kopieren von", options = profileOpts(true), placeholder = "Profil wählen …",
		tooltip = "Übernimmt die Einstellungen eines anderen Profils in dein aktuelles.",
		get = function() return nil end,
		set = function(v)
			W.Confirm({
				title = "Profil kopieren?",
				body = "Die Einstellungen aus „" .. v .. "“ werden in dein aktuelles Profil übernommen und überschreiben es.",
				confirmText = "Kopieren", cancelText = "Abbrechen",
				onConfirm = function() db:CopyProfile(v); ns.Shell:RenderContent(true) end,
				onCancel = function() ns.Shell:RenderContent(true) end,
			})
		end }):SetAllPoints(c1[2])
	W.Select(c1[3], { label = "Löschen", options = profileOpts(true), placeholder = "Profil wählen …",
		tooltip = "Löscht ein anderes Profil endgültig (nicht das aktive).",
		get = function() return nil end,
		set = function(v)
			W.Confirm({
				title = "Profil löschen?",
				body = "Das Profil „" .. v .. "“ wird endgültig gelöscht. Das lässt sich nicht rückgängig machen.",
				confirmText = "Löschen", cancelText = "Abbrechen",
				onConfirm = function() db:DeleteProfile(v); ns.Shell:RenderContent(true) end,
				onCancel = function() ns.Shell:RenderContent(true) end,
			})
		end }):SetAllPoints(c1[3])
	s:place(r1, fieldH, R.row)

	-- Reihe 2: Neues Profil (Eingabe) + Erstellen + Zurücksetzen (rechts).
	local newRow = CreateFrame("Frame", nil, d)
	newRow:SetHeight(fieldH)
	local resetBtn = W.Button(newRow, { text = "Zurücksetzen", variant = "danger",
		onClick = function()
			W.Confirm({
				title = "Profil zurücksetzen?",
				body = "Setzt das aktuelle Profil („" .. db:GetCurrentProfile() .. "“) auf die Lumen-Standardwerte zurück.",
				confirmText = "Zurücksetzen", cancelText = "Abbrechen",
				onConfirm = function() db:ResetProfile(); ns.Shell:RenderContent(true) end,
			})
		end })
	resetBtn:ClearAllPoints(); resetBtn:SetPoint("BOTTOMRIGHT", newRow, "BOTTOMRIGHT", 0, 0)
	local input
	local createBtn = W.Button(newRow, { text = "Erstellen", variant = "primary",
		onClick = function()
			local name = input and (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
			if name ~= "" then db:SetProfile(name); ns.Shell:RenderContent(true) end
		end })
	createBtn:ClearAllPoints(); createBtn:SetPoint("BOTTOMRIGHT", resetBtn, "BOTTOMLEFT", -12, 0)
	input = W.TextInput(newRow, { label = "Neues Profil", placeholder = "Name eingeben …",
		onEnter = function(v)
			local name = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if name ~= "" then db:SetProfile(name); ns.Shell:RenderContent(true) end
		end })
	input:ClearAllPoints()
	input:SetPoint("TOPLEFT", newRow, "TOPLEFT", 0, 0)
	input:SetPoint("BOTTOMRIGHT", createBtn, "BOTTOMLEFT", -16, 0)
	s:place(newRow, fieldH, R.tight)
	s:close()

	-- ===== Teilen — Export / Import ========================================
	local s2 = stack:section("Teilen — Export / Import")
	local hint = W.Hint(d, "Exportiere dein komplettes Lumen-Setup als Code oder übernimm den Code von jemand anderem — granular pro Modul.")
	s2:place(hint, M.hintH, R.row)

	-- Export
	local boxE = s2:subgroup({ title = "Export" })
	local genBtn = W.Button(d, { text = "Export-Code erzeugen", variant = "ghost",
		onClick = function()
			shareExport = (ns.Share and ns.Share:Export()) or ""
			ns.Shell:RenderContent(true)
		end })
	boxE:placeLeft(genBtn, M.buttonH, G.afterExportBtn)
	local expTA = W.Textarea(d, { height = G.taH, readOnly = true,
		placeholder = "Noch kein Code — „Export-Code erzeugen“ klicken, dann hier markieren (Strg+A) und kopieren (Strg+C).",
		get = function() return shareExport end })
	boxE:place(expTA, G.taH, R.tight)
	boxE:close()

	-- Import Profil: Code einfügen -> „Importieren" (unten rechts) öffnet das Popup
	-- (Modul-/Layout-Auswahl + „Profil erstellen"/„Aktuelles überschreiben").
	local function openImportDialog(payload)
		local mods = {}
		for _, mod in ipairs(ns.Share:GetModules()) do
			if payload.modules[mod.key] then mods[#mods + 1] = mod end
		end
		local hasLayout = payload.layout and next(payload.layout) ~= nil
		W.ImportDialog({
			modules = mods, hasLayout = hasLayout,
			onCreate = function(name, sel, withLayout)
				db:SetProfile(name) -- frisches Profil anlegen + hineinwechseln, dann Auswahl einmischen
				local ok = ns.Share and ns.Share:Import(payload, sel, withLayout)
				if ok and ns.Lumen then ns.Lumen:Print("Profil „" .. name .. "“ erstellt und importiert.") end
				shareImportRaw, importErr = "", nil
				ns.Shell:RenderContent(true)
			end,
			onOverwrite = function(sel, withLayout)
				local ok = ns.Share and ns.Share:Import(payload, sel, withLayout)
				if ok and ns.Lumen then ns.Lumen:Print("Import in das aktuelle Profil übernommen.") end
				shareImportRaw, importErr = "", nil
				ns.Shell:RenderContent(true)
			end,
		})
	end

	local boxI = s2:subgroup({ title = "Import Profil" })
	local impTA = W.Textarea(d, { height = G.taH, placeholder = "Profil-Code hier einfügen (Strg+V) …",
		get = function() return shareImportRaw end,
		onChange = function(t) shareImportRaw = t end })
	boxI:place(impTA, G.taH, importErr and R.tight or R.row)

	if importErr then
		boxI:place(W.Hint(d, "|cffD66A5CCode ungültig: " .. importErr .. " — bitte den kompletten Code einfügen.|r"), M.hintH, R.row)
	end

	-- „Importieren"-Button unten rechts in der Box (eigene Reihe, rechtsbündig).
	local btnRow = CreateFrame("Frame", nil, d)
	btnRow:SetHeight(M.buttonH)
	local importBtn = W.Button(btnRow, { text = "Importieren", variant = "primary",
		onClick = function()
			local raw = shareImportRaw and shareImportRaw:gsub("%s+", "") or ""
			if not ns.Share or raw == "" then importErr = "leer"; ns.Shell:RenderContent(true); return end
			local p, err = ns.Share:Decode(shareImportRaw)
			if not p then importErr = err or "ungültig"; ns.Shell:RenderContent(true); return end
			importErr = nil
			openImportDialog(p)
		end })
	importBtn:ClearAllPoints(); importBtn:SetPoint("RIGHT", btnRow, "RIGHT", 0, 0)
	boxI:place(btnRow, M.buttonH, R.tight)
	boxI:close()
	s2:close()
end

ns.Screens["Global/Base"]    = buildGlobalBase
ns.Screens["Global/Profile"] = buildGlobalProfile

ns.Screens["Click-Cast/Bindings"] = buildClickCast

ns.Screens["Raidframes/Base"]     = buildBase
ns.Screens["Raidframes/Raid"]     = function(d, stack) buildRaid(d, stack, "raid") end
ns.Screens["Raidframes/Group"]    = function(d, stack) buildRaid(d, stack, "party") end
ns.Screens["Raidframes/Auras"]    = buildAuras
ns.Screens["Raidframes/Tracking"] = buildTracking
