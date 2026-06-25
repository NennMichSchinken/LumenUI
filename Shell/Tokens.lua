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
