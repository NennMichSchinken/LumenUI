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
	inkTint  = hex("2c2318"), -- Icon-Tile-Gradient oben

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
}

-- Rollen → { Pfad, Größe, Flags }. Größen aus typography.css.
UI.ROLE = {
	wordmark = { UI.FONT.cinzelSemi, 30, "" }, -- LUMEN
	display  = { UI.FONT.cinzelSemi, 21, "" },
	section  = { UI.FONT.cinzelSemi, 19, "" }, -- Section-Heading (Cinzel)
	nav      = { UI.FONT.hankenMed,  18, "" },
	body     = { UI.FONT.hankenReg,  14, "" },
	label    = { UI.FONT.hankenMed,  14, "" },
	tab      = { UI.FONT.hankenMed,  18, "" },
	caption  = { UI.FONT.hankenReg,  12, "" },
	eyebrow  = { UI.FONT.hankenMed,  12, "" },
	tagline  = { UI.FONT.hankenReg,  12, "" },

	-- Widget-Toolkit (Phase 2) — kleine, control-nahe Rollen.
	fieldLabel = { UI.FONT.hankenMed,  13, "" }, -- Gold-Label über einem Control
	groupTitle = { UI.FONT.cinzelSemi, 15, "" }, -- GroupPanel- / Divider-Überschrift
	sliderCap  = { UI.FONT.cinzelSemi, 13, "" }, -- Slider-Beschriftung
	value      = { UI.FONT.hankenMed,  14, "" }, -- Wert-Box
	ends       = { UI.FONT.hankenReg,  11, "" }, -- Slider Min/Max-Zahlen
	option     = { UI.FONT.hankenMed,  14, "" }, -- Dropdown-Header/-Zeilen, Checkbox-Label
	btn        = { UI.FONT.hankenSemi, 14, "" }, -- Button-Label
}

-- FontString auf eine Rolle setzen. Gibt das FontString zurück (chainbar).
function UI:SetFont(fs, role, color)
	local r = self.ROLE[role] or self.ROLE.body
	fs:SetFont(r[1], r[2], r[3])
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
}
UI.R = {
	panel = 2, control = 8, popover = 9, card = 10, check = 4,
}

-- Panel-Maße (Design 1500×1000). Auf dem Bildschirm via SetScale verkleinert.
UI.PANEL = {
	w = 1500, h = 1000, headerH = 88, footerH = 78, scale = 0.74,
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
	local top = mk();   PixelUtil.SetHeight(top, thick)
	PixelUtil.SetPoint(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	local bot = mk();   PixelUtil.SetHeight(bot, thick)
	PixelUtil.SetPoint(bot, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	PixelUtil.SetPoint(bot, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	local left = mk();  PixelUtil.SetWidth(left, thick)
	PixelUtil.SetPoint(left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
	PixelUtil.SetPoint(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	local right = mk(); PixelUtil.SetWidth(right, thick)
	PixelUtil.SetPoint(right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	PixelUtil.SetPoint(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	return edges
end

-- FontString in einer Design-Rolle.
function UI.FS(parent, role, col, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	UI:SetFont(fs, role, col)
	return fs
end

-- Horizontale 1px-Gradient-Linie (Gold fadet aus). dir: "out"=Gold stark links →
-- schwach rechts | "in"=umgekehrt. Für Section-Divider-Rules u.ä.
function UI.GradientLine(parent, dir, strongA, faintA)
	local gc = UI.C.gold500
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	t:SetColorTexture(1, 1, 1, 1)
	local strong = CreateColor(gc.r, gc.g, gc.b, strongA or 0.45)
	local faint  = CreateColor(gc.r, gc.g, gc.b, faintA or 0.0)
	if dir == "in" then t:SetGradient("HORIZONTAL", faint, strong)
	else t:SetGradient("HORIZONTAL", strong, faint) end
	return t
end
