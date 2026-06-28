local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell Design Tokens
--  1:1-Übersetzung des Lumen Design Systems (tokens/*.css) nach Lua/WoW.
--  Quelle der Wahrheit: "WoW Addon Einstellungsseite" Prototyp (Claude Design).
--  Zentral, damit Shell + späteres Widget-Toolkit konsistent daraus lesen.
-- ===========================================================================

local UI = {}
ns.UI = UI

-- ---------------------------------------------------------------------------
--  Farben — Hex → {r,g,b,a} (0..1)
-- ---------------------------------------------------------------------------
local function hex(s, a)
	return {
		r = tonumber(s:sub(1, 2), 16) / 255,
		g = tonumber(s:sub(3, 4), 16) / 255,
		b = tonumber(s:sub(5, 6), 16) / 255,
		a = a or 1,
	}
end
UI.hex = hex

UI.C = {
	-- Ink-Rampe (Grounds, dunkel → hell)
	ink900   = hex("070605"), -- App-Hintergrund
	ink850   = hex("0F0D0B"), -- Haupt-Panel
	ink800   = hex("110d09"), -- Glow-Zentrum
	ink700   = hex("13100C"), -- Inset-Feld (Dropdown-Kopf, Keybind)
	ink650   = hex("15100a"), -- Icon-Tile-Schatten
	ink600   = hex("171411"), -- Raised Card
	ink550   = hex("1B1712"), -- Popover / Floating
	ink520   = hex("1E1A13"), -- Unter-Box (heller als Card, für Funktionsgruppen in einer Karte)
	inkTint  = hex("2c2318"), -- Icon-Tile-Gradient oben
	sliderTrack = hex("3A3122"), -- ungefüllter Slider-Track (deutlich sichtbar, nicht „in der Luft")

	-- Gold — die eine Akzentfarbe, in vielen Deckkräften
	gold500  = hex("D4A34F"), -- Kern-Akzent: Borders, Icons, aktiv
	gold400  = hex("E6B863"), -- Button-Hover
	gold300  = hex("E6C883"), -- Wordmark / Display-Heading
	gold250  = hex("E8C988"), -- aktives Nav/Tab-Label
	gold200  = hex("F0D89B"), -- Link-Hover
	gold100  = hex("F1E6D3"), -- hellstes Gold-Weiß

	-- Parchment-Text (warme Neutrale)
	textStrong  = hex("F1E6D3"),
	textHeading = hex("E2D6C0"),
	textBody    = hex("B5AA98"),
	textMuted   = hex("8a8072"),
	textFaint   = hex("7E766A"),
	onGold      = hex("1A1714"), -- Ink-Text auf Gold-Füllung

	-- Danger — ausschließlich destruktiv
	danger500 = hex("D66A5C"),
}

-- Gold/Danger in Standard-Deckkräften (Borders, Washes) — als {r,g,b,a}.
local g = UI.C.gold500
local d = UI.C.danger500
local function goldA(a) return { r = g.r, g = g.g, b = g.b, a = a } end
local function dangerA(a) return { r = d.r, g = d.g, b = d.b, a = a } end
UI.goldA = goldA
UI.dangerA = dangerA

UI.line = {
	faint   = goldA(0.12), -- feine Trenner (Inhalt)
	divider = goldA(0.28), -- strukturelle Trennlinien Header/Footer/Nav (im Spiel sichtbar)
	soft   = goldA(0.22), -- weiche Control-Borders
	mid    = goldA(0.35), -- Standard
	strong = goldA(0.60), -- aktiv / offen
	washSoft = goldA(0.07),
	wash     = goldA(0.12),
	dangerLine = dangerA(0.40),
	dangerWash = dangerA(0.12),
}

-- ---------------------------------------------------------------------------
--  Schriften — gebündelt unter Lumen/Fonts/ (Cinzel + Hanken Grotesk, SIL OFL)
-- ---------------------------------------------------------------------------
local FP = [[Interface\AddOns\Lumen\Fonts\]]
UI.FONT = {
	cinzelSemi   = FP .. "Cinzel-SemiBold.ttf",
	cinzelBold   = FP .. "Cinzel-Bold.ttf",
	hankenReg    = FP .. "HankenGrotesk-Regular.ttf",
	hankenMed    = FP .. "HankenGrotesk-Medium.ttf",
	hankenSemi   = FP .. "HankenGrotesk-SemiBold.ttf",
	hankenBold   = FP .. "HankenGrotesk-Bold.ttf",
}

-- Font-Warm-up: Beim KALTSTART rendert der ERSTE SetFont je custom-TTF-Pfad leer, bis der
-- Client-Glyph-Cache den Font aufgebaut hat (nach /reload ist er aus der Vorsitzung noch warm
-- -> Text da, Kaltstart -> unsichtbar). Hier jeden Pfad einmal auf einer versteckten,
-- gerenderten FontString „anfassen" -> Cache ist warm, BEVOR die Shell je gebaut wird.
do
	-- Glyphen, die die UI real nutzt (deutsche Labels inkl. Umlaute/ß + Ziffern + Zeichen).
	-- Pro Font EINE bleibende, voll-transparente FontString — NICHT :Hide(): eine versteckte
	-- FontString rendert nie, also würden ihre Glyphen nie rasterisiert (genau das war der
	-- Kaltstart-Bug: bei /reload ist der Client-Glyph-Cache aus der Vorsitzung warm, beim
	-- echten Spielstart kalt -> der erste SetText, z.B. der primäre „Übernehmen"-Button im
	-- Color-Picker (hankenBold), maß 0 Breite und blieb unsichtbar). Sichtbar (alpha 0) im
	-- Bildschirm verankert (off-screen würde gecullt -> keine Rasterung), rendert einmal beim
	-- ersten Frame und hält den Cache warm, BEVOR Shell/Color-Picker je gebaut werden.
	-- WICHTIG: SetFont MUSS vor SetText kommen (SetText ohne Font wirft „Font not set").
	local GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÄÖÜäöüß0123456789 %+-#/.,()"
	for _, path in pairs(UI.FONT) do
		local warm = UIParent:CreateFontString(nil, "BACKGROUND")
		warm:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 4)
		warm:SetAlpha(0)
		if pcall(warm.SetFont, warm, path, 16, "") then pcall(warm.SetText, warm, GLYPHS) end
	end
end

-- Rollen → { Pfad, Größe, Flags }. Größen aus typography.css.
UI.ROLE = {
	wordmark = { UI.FONT.cinzelSemi, 30, "" }, -- LUMEN
	display  = { UI.FONT.cinzelSemi, 22, "" },
	section  = { UI.FONT.cinzelSemi, 20, "" }, -- Section-Heading (Cinzel)
	nav      = { UI.FONT.hankenMed,  18, "" },
	body     = { UI.FONT.hankenReg,  14, "" },
	label    = { UI.FONT.hankenMed,  14, "" },
	tab      = { UI.FONT.hankenMed,  18, "" },
	caption  = { UI.FONT.hankenReg,  12, "" },
	hint     = { UI.FONT.hankenReg,  16, "" }, -- Beschreibungs-/Hinweistext unter Controls
	eyebrow  = { UI.FONT.hankenMed,  12, "" },
	tagline  = { UI.FONT.hankenReg,  12, "" },

	-- Widget-Toolkit (Phase 2) — kleine, control-nahe Rollen. Größen auf dem
	-- 4er-Raster (12/16/20). Hier zentral ändern -> schlägt überall durch.
	fieldLabel = { UI.FONT.hankenMed,  16, "" }, -- Gold-Label über einem Control (Dropdown etc.)
	sectionHead= { UI.FONT.cinzelSemi, 20, "" }, -- SectionDivider / Tab-Überschrift
	groupTitle = { UI.FONT.cinzelSemi, 16, "" }, -- GroupPanel-Titel / IconTile-Letter
	sliderCap  = { UI.FONT.cinzelSemi, 16, "" }, -- Slider-Beschriftung
	value      = { UI.FONT.hankenMed,  14, "" }, -- Wert-Box
	ends       = { UI.FONT.hankenMed,  14, "" }, -- Slider Min/Max-Zahlen
	selectText = { UI.FONT.hankenMed,  16, "" }, -- Dropdown-Header + -Zeilen
	checkLabel = { UI.FONT.hankenMed,  16, "" }, -- Checkbox-Label
	listLabel  = { UI.FONT.hankenMed,  18, "" }, -- Listen-Zeile (Rollen-Sortierliste)
	subDivider = { UI.FONT.cinzelSemi, 16, "" }, -- kleinere zentrierte Unter-Überschrift
	btn        = { UI.FONT.hankenSemi, 16, "" }, -- Button-Label (Schnitt je Variante, s. Widgets)

	-- Eigener Lumen-Tooltip — eigene Rollen, damit Schriftgröße/Schnitt unabhängig
	-- justierbar sind (Florian stellt hier selbst ein).
	tipTitle = { UI.FONT.hankenSemi, 18, "" }, -- Tooltip-Titel / Spell-Name (Gold)
	tipBody  = { UI.FONT.hankenReg,  16, "" }, -- Tooltip-Text / Spell-Beschreibung
}

-- FontString auf eine Rolle setzen. Gibt das FontString zurück (chainbar).
function UI:SetFont(fs, role, color)
	local r = self.ROLE[role] or self.ROLE.body
	-- Fallback: scheitert der custom-TTF-SetFont (Kaltstart, Datei noch nicht bereit),
	-- lieber der Standardfont in gleicher Größe als unsichtbarer Text.
	if not fs:SetFont(r[1], r[2], r[3]) then
		fs:SetFont(STANDARD_TEXT_FONT, r[2], r[3])
	end
	if color then fs:SetTextColor(color.r, color.g, color.b, color.a or 1) end
	return fs
end

-- Letter-Spacing-Emulation: WoW-FontStrings können kein tracking. Für Wordmark/
-- Tagline/Eyebrow fügen wir Leerzeichen zwischen die Zeichen ein.
function UI.Track(text, gap)
	gap = gap or " "
	local out = {}
	for i = 1, #text do out[i] = text:sub(i, i) end
	return table.concat(out, gap)
end

-- ---------------------------------------------------------------------------
--  Spacing & Radien (spacing.css). Shell baut in Design-Pixeln; das Panel
--  selbst wird per SetScale auf den Bildschirm verkleinert.
-- ---------------------------------------------------------------------------
UI.S = {
	s1 = 2, s2 = 6, s3 = 8, s4 = 12, s5 = 14, s6 = 16, s7 = 20, s8 = 24, s9 = 36,
	controlH    = 40,
	cardPad     = 20,
	panelGutter = 36,
	navWidth    = 260,
	scrollBarW  = 4,  -- Breite der Content-Scrollleiste
	scrollBarGap = 14, -- Abstand ScrollFrame -> Scrollleiste (im Gutter)
}
UI.R = {
	panel = 2, control = 8, popover = 9, card = 10, check = 4,
}

-- ---------------------------------------------------------------------------
--  Widget-Maße — ALLE Dimensionen des Widget-Toolkits zentral. Hier ändern,
--  dann zieht es überall nach (Shell/Widgets.lua liest nur daraus, keine
--  Magic Numbers mehr im Widget-Code). Werte auf dem 4er-Raster halten.
-- ---------------------------------------------------------------------------
UI.WIDGET = {
	controlH    = 40, -- Dropdown/Eingabe-Höhe
	buttonH     = 40, -- Button-Höhe
	fieldGap    = 26, -- vertikaler Abstand Label -> Control darunter

	-- Checkbox
	checkBox    = 22, -- Box-Kantenlänge
	checkLabelGap = 10,

	-- Field-Swatch (ColorSwatch field=true): quadratischer Farb-Chip auf Dropdown-Höhe
	-- (controlH × swatchFieldW) -> sitzt sauber in der Reihe, dominiert die Spalte nicht.
	swatchFieldW = 40,

	-- Slider
	sliderH     = 86, -- Gesamthöhe (Label + Track-Reihe + Wert-Box)
	sliderTrackH= 18, -- Höhe der klickbaren Track-Reihe
	sliderBarH  = 4,  -- Dicke des Balkens
	sliderThumb = 14, -- Knopf-Kantenlänge
	sliderCapGap= 30, -- yOffset Label -> Track-Reihe
	sliderEndW  = 28, -- Breite der Min/Max-Zahlenfelder
	sliderEndPad= 10, -- Abstand Zahl <-> Track
	valueBoxW   = 92, -- Wert-Box Breite
	valueBoxH   = 28, -- Wert-Box Höhe
	valueBoxGap = 10, -- yOffset Track-Reihe -> Wert-Box

	-- GroupPanel
	groupTitleY = -16, -- yOffset des Titels von der oberen Kante
	groupContentY = -48, -- yOffset des Inhaltsbereichs

	-- Section-Divider (zentrierte Gold-Linie — jetzt nur noch für UNTER-Überschriften
	-- innerhalb einer Sektions-Karte; Haupt-Sektionen tragen den Panel-Header).
	dividerH    = 36, -- Höhe des Divider-Blocks
	dividerGap  = 16, -- Abstand Text <-> Gold-Rule

	-- Sektions-Panel (Konzept A: jede Sektion = eigene Karte mit Header). Zentral
	-- justierbar; stack:section() in Shell.lua liest nur daraus.
	sectionPad         = 22, -- innerer L/R- + Boden-Abstand der Karte
	sectionHeaderH     = 46, -- Höhe der Header-Leiste (Titel)
	sectionAfterHeader = 18, -- Header-Unterkante -> erste Inhalts-Reihe
	sectionGap         = 26, -- Abstand zwischen zwei Sektions-Karten
	sectionHeaderBarW  = 3,  -- Breite des Gold-Akzent-Balkens am Header links
	sectionTitleX      = 18, -- X-Einzug des Header-Titels

	-- Unter-Box (subgroup): hellere Funktionsgruppe INNERHALB einer Sektions-Karte.
	subgroupPad   = 16, -- innerer Einzug der Unter-Box (Reihen zur Box-Kante)
	subgroupGap   = 14, -- Abstand zwischen zwei Unter-Boxen / nach der letzten
	subgroupTitleH = 40, -- Titel-Bereich einer GETITELTEN Unter-Box (Label + Abstand zur 1. Reihe)

	-- Hint (gedämpfte Fließtext-Zeile)
	hintH       = 40, -- Default-Höhe eines Hint-Blocks (1–2 Zeilen)
	subHeadH    = 26, -- linksbündige Unter-Überschrift (z.B. Aggro-Stufen-Blöcke)

	-- (Die LAYOUT-ABSTÄNDE der Screens liegen zentral & pro Kategorie in UI.LAYOUT
	-- weiter unten — hier in UI.WIDGET nur die WIDGET-Maße.)
	sortRowH      = 42, -- Höhe einer Reihe in der Rollen-Prioritätsliste
	sortCardPad   = 6,  -- Innenabstand der Rollen-Prioritäts-Card
	sortAccentW   = 4,  -- Breite des rollenfarbenen Akzent-Balkens links

	-- Color-Picker (eigenes Popover im Lumen-Stil)
	cpSVW    = 280, -- Breite des Sättigung/Helligkeit-Feldes (breit genug, dass die Buttons + rechter Rand passen)
	cpSVH    = 168, -- Höhe des SV-Feldes (= Höhe der Hue-Leiste)
	cpHueW   = 20,  -- Breite der Farbton-Leiste
	cpPad    = 16,  -- Innenabstand des Pickers
	cpGap    = 12,  -- Abstand SV-Feld <-> Hue-Leiste
	cpMarker = 10,  -- Kantenlänge der Marker
	cpPrevH  = 30,  -- Höhe der Vorschau-/Hex-Reihe
	cpBtnGap = 8,   -- Abstand zwischen Übernehmen/Abbrechen im Color-Picker

	rowGap      = 30, -- Spaltenabstand in W.Row (row3/row2)

	-- Tracking-Tab: getrackte-Spell-Zeile (Icon + Name + „Entfernen") + Spell-Picker.
	-- Der Picker ist die „echte Typeahead-Suche": W.Select kann nicht scrollen — hier
	-- laufen 30–60 Spells gefiltert in einer SCROLLBAREN Liste (Suchfeld oben + Liste).
	trackRowH      = 36, -- Höhe einer getrackten-Spell-Zeile
	trackIcon      = 22, -- Icon-Kantenlänge (Tracking-Liste UND Picker)
	trackRemoveW   = 104, -- Breite des „✕ Entfernen"-Buttons rechts in der Zeile
	spBtnW         = 210, -- Breite des „+ Spell hinzufügen"-Auslöse-Buttons
	spW            = 340, -- Breite des Spell-Picker-Popovers
	spPad          = 10,  -- Innenabstand des Popovers
	spSearchH      = 32,  -- Höhe des Suchfelds
	spRowH         = 32,  -- Höhe einer Picker-Listenzeile
	spVisibleRows  = 7,   -- gleichzeitig sichtbare Zeilen (Rest scrollt)
	spScrollW      = 4,   -- Breite des Picker-Scrollbalkens (auch von W.Select genutzt)
	spScrollGap    = 6,   -- Abstand Liste <-> Scrollbalken
	selectMaxRows  = 8,   -- W.Select: max. gleichzeitig sichtbare Optionen (Rest scrollt)

	-- Confirm-Dialog (modaler Bestätigungs-Popup; dunkelt die Shell dahinter ab).
	confirmW      = 460, -- Karten-Breite
	confirmH      = 188, -- Karten-Höhe (Titel + 2–3 Zeilen Text + Button-Reihe)
	confirmPad    = 24,  -- Innenabstand der Karte
	confirmBtnGap = 12,  -- Abstand zwischen Bestätigen/Abbrechen
	confirmBtnW   = 150, -- feste Button-Breite (Text-Wechsel bricht das Layout nicht)
	confirmDim    = 0.62, -- Deckkraft der Abdunklung hinter dem Popup

	-- Eigener Spell-Tooltip (Lumen-Design statt Blizzard-GameTooltip).
	tipW       = 320, -- feste Tooltip-Breite
	tipPad     = 14,  -- Innenabstand
	tipIcon    = 28,  -- Icon-Kantenlänge im Kopf
	tipNameGap = 10,  -- Icon -> Name
	tipGap     = 10,  -- Kopf (Icon/Name) -> Beschreibung
}

-- ---------------------------------------------------------------------------
--  LAYOUT-ABSTÄNDE — ZENTRAL & PRO KATEGORIE. Hier justiert Florian die Abstände
--  jeder Sektion EINZELN. `general` = globale Standardwerte (Divider-Abstand,
--  Sektions-Trennung, Side-/Checkbox-Gaps). Darunter ein Block je Kategorie mit
--  „nach welcher Reihe wie viel Platz". Werte in Design-Pixeln (4er-Raster).
--  HINWEIS: die ELEMENT-/Reihen-REIHENFOLGE je Sektion liegt im jeweiligen Block
--  in Shell/Screens.lua (klar kommentiert) — für ein Umsortieren kurz Bescheid
--  geben, dann tausche ich die Reihen.
-- ---------------------------------------------------------------------------
UI.LAYOUT = {
	-- RHYTHMUS — semantische Reihen-Abstände. Abstand über die BEZIEHUNG zweier Reihen
	-- wählen, nicht über eine geratene Zahl. Prinzip: ein Höhensprung (kurzes Control
	-- wie Checkbox/Swatch -> hohes wie Dropdown/Slider) braucht mehr Luft.
	rhythm = {
		tight      = 14, -- eng zusammengehörige Reihen (Slider->Slider, Größe/X/Y->Farbe)
		row        = 22, -- Standard zwischen zwei Control-Reihen
		afterCheck = 30, -- nach Checkbox/kurzem Control -> hohes Control (Dropdown/Slider)
		group      = 32, -- bewusster Bruch zwischen zwei Unter-Gruppen in einer Karte
	},
	general = {
		afterDivider  = 16, -- Divider -> erstes Element der Sektion
		beforeSection = 52, -- Sektions-Ende -> nächste Kategorie (große Trennung)
		sideGap       = 28, -- Control -> direkt daneben sitzende Checkbox
		checkRowGap   = 40, -- zwischen zwei Checkboxen in einer Reihe
		subHeadToRow  = 8,  -- Unter-Überschrift -> ihre Reihe
	},
	base = {                    -- Base-Tab: freistehender „Raidframes aktiviert"-Schalter
		topToToggle    = 30,    -- Tab-Strip -> Checkbox (oben mehr Platz)
		toggleToSection = 16,   -- Checkbox -> erste Sektions-Karte (unten weniger, näher dran)
	},
	lebensbalken = {
		afterTexHint = 10,  -- Textur-Reihe -> Mausrad/Such-Hinweis (eng darunter)
		afterTexture = 22,  -- Balken-Textur-Reihe -> Klassenfarbe-Reihe
		afterClass   = 22,  -- Klassenfarbe-Reihe -> „Name in Klassenfarbe"-Reihe
		afterNameCC  = 52,  -- „Name in Klassenfarbe"-Reihe -> nächste Kategorie
	},
	transparenz = {
		afterColor = 30,    -- Hintergrundfarbe-Reihe (kurz) -> Deckkraft-Slider (hoch): Höhensprung
		afterAlpha = 52,    -- Deckkraft-Slider-Reihe -> nächste Kategorie
	},
	sort = {
		afterMode = 22,     -- „Sortieren nach" -> Prioritäts-Card
		afterCard = 52,     -- Card -> nächste Kategorie
	},
	test = {
		afterMaster = 14,   -- „Testmodus" -> Test-Gruppengröße
		afterSize   = 14,   -- Test-Gruppengröße -> Ende
	},
	sizeArrange = {         -- Raid/Group: Größe & Anordnung
		afterSliders = 22,  -- Breite/Höhe/Abstand -> Ausrichtung
		afterAlign   = 52,  -- Ausrichtung -> Text — Name
	},
	auras = {               -- Auras-Tab (die Reihen-Abstände kommen aus rhythm oben)
		afterIntro = 22,    -- Intro-Hinweis -> erste Kategorie-Karte
	},
	tracking = {            -- Tracking-Tab (Whitelist-Editor)
		introH      = 58,   -- Höhe des mehrzeiligen Intro-Hinweises
		afterIntro  = 14,   -- Intro -> Spec-Zeile
		afterSpec   = 22,   -- Spec-Zeile -> erste Kategorie-Karte
		afterDesc   = 14,   -- Kategorie-Beschreibung -> getrackte Liste
		betweenRows = 6,    -- zwischen zwei getrackten Spell-Zeilen
		emptyH      = 30,   -- Höhe der „(keine Spells)"-Zeile bei leerer Liste
		afterList   = 18,   -- Liste -> Aktions-Buttons (Picker + Reset)
	},
	clickcast = {           -- Click-Cast-Tab (Maus-Bindings + Hovercast)
		topToHead    = 30,  -- Tab-Strip -> Master-Schalter
		afterMaster  = 22,  -- Master -> Spec-Dropdown
		afterSpec    = 8,   -- Spec-Dropdown -> Aktive-Spec-Hinweis
		afterCaption = 18,  -- Hinweis -> „Nur hilfreiche Zauber"-Checkbox
		afterHelpful = 26,  -- Checkbox -> erste Sektionskarte
		introH       = 50,  -- Höhe des Hovercast-Intro-Hinweises
		afterIntro   = 14,  -- Intro -> erste Binding-Box
		headToRow    = 14,  -- Box-Kopf (Summary + Entfernen) -> Reihe 1
		betweenRows  = 14,  -- Reihe -> nächste Reihe innerhalb einer Box
		afterList    = 8,   -- letzte Box -> „+ hinzufügen"-Button
		emptyH       = 30,  -- Höhe der „(keine Bindings)"-Zeile
	},
}

-- Panel-Maße (Design 1500×1060). Auf dem Bildschirm via SetScale verkleinert.
-- scale 0.80 + Höhe 1060: spürbar größer, Inhalt atmet (Florian-Wunsch). Hier
-- nachjustieren — w/h ändern den Platz, scale die Gesamtgröße inkl. Schrift.
UI.PANEL = {
	w = 1500, h = 1060, headerH = 88, footerH = 78, scale = 0.80,
}

-- ---------------------------------------------------------------------------
--  Gemeinsame Bau-Primitive (Shell-Chrome + Widget-Toolkit lesen daraus — DRY).
--  Standen vorher als Datei-Locals in Shell.lua; hochgezogen, damit beide sie
--  teilen. Verhalten identisch (reine Verschiebung).
-- ---------------------------------------------------------------------------
function UI.SetColor(t, col) t:SetColorTexture(col.r, col.g, col.b, col.a or 1) end

-- Vollflächige Füll-Textur über parent.
function UI.Fill(parent, col, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints(parent)
	UI.SetColor(t, col)
	return t
end

-- 1px-Hairline-Border (4 Kanten) um frame, Gold-at-opacity. Pixel-Snapping via
-- PixelUtil: rechnet die effektive Scale ein -> Linien liegen exakt auf dem
-- physischen Pixelraster und verschwinden NICHT bei skaliertem Panel (SetScale).
-- Gibt die 4 Kanten-Texturen zurück (für späteres Umfärben, z.B. Hover/aktiv).
function UI.Border(frame, col, thick, layer)
	thick = thick or 1
	local edges = {}
	local function mk()
		local t = frame:CreateTexture(nil, layer or "BORDER")
		UI.SetColor(t, col)
		edges[#edges + 1] = t
		return t
	end
	local top, bot, left, right = mk(), mk(), mk(), mk()
	-- Pixel-Snap der Kanten. WICHTIG: muss NACH dem finalen Layout erneut laufen — zur
	-- Bauzeit (im RenderContent, vor gesetzter Scrollposition) steht die absolute Position
	-- noch nicht, dann landet die 1px-Linie zwischen zwei Pixeln und verschwindet bis zum
	-- nächsten Scroll (der bekannte Tab-/Dropdown-Border-Bug). Daher: sofort + einen Frame
	-- später (C_Timer.After 0, nach dem Layout-Pass) + bei jeder Größenänderung neu snappen.
	local function snap()
		PixelUtil.SetHeight(top, thick)
		PixelUtil.SetPoint(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
		PixelUtil.SetPoint(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
		PixelUtil.SetHeight(bot, thick)
		PixelUtil.SetPoint(bot, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
		PixelUtil.SetPoint(bot, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		PixelUtil.SetWidth(left, thick)
		PixelUtil.SetPoint(left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
		PixelUtil.SetPoint(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
		PixelUtil.SetWidth(right, thick)
		PixelUtil.SetPoint(right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
		PixelUtil.SetPoint(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	end
	snap()
	C_Timer.After(0, snap)
	frame:HookScript("OnSizeChanged", snap)
	return edges
end

-- FontString in einer Design-Rolle.
function UI.FS(parent, role, col, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	UI:SetFont(fs, role, col)
	return fs
end

-- Horizontale 1px-Fade-Linie (Gold fadet zur Kante aus). dir: "out"=stark am
-- rechten Ende (an der Überschrift) | "in"=stark am linken Ende.
-- ABSICHTLICH aus 3 soliden Segmenten, REIN ÜBER ANKER (kein SetGradient, kein
-- OnSizeChanged): beides braucht einen Layout-/Render-Pass, der im ScrollFrame
-- für Inhalt unter dem Sichtbereich verzögert wird -> Linien fehlen oben/flackern.
-- Solide, anker-positionierte Flächen rendern sofort (auch off-screen) und ruhig.
-- Die zwei „Detail"-Segmente nahe der Überschrift haben feste Breite, das lange
-- blasse Segment füllt variabel bis zur Kante.
function UI.GradientLine(parent, dir, strongA, faintA)
	local gc = UI.C.gold500
	strongA, faintA = strongA or 0.45, faintA or 0.0
	local midA  = (strongA + faintA) / 2
	local SEG   = 70 -- feste Breite der beiden Detail-Segmente nahe der Überschrift
	local f = CreateFrame("Frame", nil, parent)
	PixelUtil.SetHeight(f, 1) -- pixel-gesnappt: naive 1px-Höhe verschwindet unter SetScale beim Scrollen
	local function mk(a)
		local t = f:CreateTexture(nil, "ARTWORK"); PixelUtil.SetHeight(t, 1)
		t:SetColorTexture(gc.r, gc.g, gc.b, a)
		return t
	end
	local strong, mid, faint = mk(strongA), mk(midA), mk(faintA + 0.05)
	if dir == "in" then
		-- Überschrift am LINKEN Ende: stark links -> blass zur rechten Kante.
		strong:SetPoint("LEFT", f, "LEFT", 0, 0); strong:SetWidth(SEG)
		mid:SetPoint("LEFT", strong, "RIGHT", 0, 0); mid:SetWidth(SEG)
		faint:SetPoint("LEFT", mid, "RIGHT", 0, 0); faint:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	else
		-- Überschrift am RECHTEN Ende: stark rechts -> blass zur linken Kante.
		strong:SetPoint("RIGHT", f, "RIGHT", 0, 0); strong:SetWidth(SEG)
		mid:SetPoint("RIGHT", strong, "LEFT", 0, 0); mid:SetWidth(SEG)
		faint:SetPoint("RIGHT", mid, "LEFT", 0, 0); faint:SetPoint("LEFT", f, "LEFT", 0, 0)
	end
	return f
end
