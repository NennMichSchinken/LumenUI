local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell Design Tokens (v3 Design System, 2026-07-22)
--  THE source of truth. Components read SEMANTIC tokens only — never a raw hex,
--  never a legacy alias: UI.Surface (window/sidebar/card/input/hover/scrim),
--  UI.Text (primary/secondary/description/disabled/value/onAccent), UI.Border
--  (faint/default/hover/divider/active), UI.Accent (color/hover/pressed/
--  selection/focus/glow/wash/switchOn), UI.Status (danger*). The raw palette
--  (UI.P) + Accent engine (UI.SetAccent) live here and ONLY here.
-- ===========================================================================

local UI = {}
ns.UI = UI

-- ---------------------------------------------------------------------------
--  Colors — hex -> {r,g,b,a} (0..1)
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

-- ---------------------------------------------------------------------------
--  PALETTE — design line v2 (Florian's values, locked 2026-07-02).
--  THE single central color block: every hex in the addon lives HERE and only
--  here, in the agreed A/B/C/D/E schema. Future colors continue this scheme
--  (next free code within the matching group), never as hardcoded values in
--  widget/screen code.
-- ---------------------------------------------------------------------------
local P = {
	-- v3 MONOCHROME-CALM + OBSIDIAN LAYERS (2026-07-22, Florian's Design-System
	-- doc). Graduated blue-black surfaces: the visible STEP between layers (panel
	-- -> sidebar -> card -> input) is what reads calm/premium — the earlier v3
	-- palette had panel and sidebar identical, so nothing lifted. Accent = LIGHT
	-- ITSELF for now (monochrome, no chrome colour); a real user-chosen
	-- AccentColor can be swapped in later via the Accent engine below with NO
	-- component edits. Semantic colour (class/role/dispel) lives only in the
	-- preview island, never in the chrome.
	-- NEVER pure #000/#FFF. The A/B/C/D/E slot NAMES are load-bearing (referenced
	-- directly across Shell/Widgets/Screens/EditMode) — keep every key; the
	-- forward-looking semantic API is UI.Surface/UI.Text/UI.Border below.

	-- A: surface layers — PURE NEUTRAL, anchored at panel #0C0C0C (Florian
	-- 2026-07-22). The DEPTH comes from the lightness STEP between layers (panel ->
	-- sidebar -> card -> input), NOT from any hue — so this is fully neutral grey
	-- (R=G=B), the most flexible canvas for a future user-chosen AccentColor: warm
	-- (gold/orange/red) and cool (blue/violet) accents both sit cleanly on a
	-- neutral ground, whereas a tinted base would fight the opposite temperature.
	-- The lightness steps are preserved 1:1 from the tinted version, so cards stay
	-- as lifted/premium as before — it never collapses back to the flat "panel ==
	-- card" black. Panel is a hair darker than the earlier value (reads deeper).
	page         = hex("070707"), -- dim behind the panel (a step under Window)
	panel        = hex("0C0C0C"), -- A3: main window surface (doc: Window)
	sidebar      = hex("111111"), -- A2: nav column (a real step lighter than the panel)
	card         = hex("151515"), -- A4: section cards (doc: Cards)
	inset        = hex("191919"), -- A1: edit boxes, open dropdown lists, slider value box, troughs (doc: Inputs)
	element      = hex("191919"), -- A5: rows, neutral buttons, closed dropdowns, inactive tabs (= Inputs layer)
	elementHover = hex("222222"), -- A6: hover step (doc: Hover)

	-- B: lines — pure white; UI.Border applies the (low) alpha. THE tuning spot.
	borderSoft   = hex("FFFFFF"), -- B1: card/row borders, fine separators (used at ~.05 alpha)
	borderStrong = hex("FFFFFF"), -- B2: control borders, hover edges, focus (used at ~.10 alpha)

	-- C: interactive accent = pure light (monochrome-now). Brightness IS the
	-- accent (bright = active/interactive, grey = quiet). Names kept from the
	-- two-gold era; goldInt is the ACCENT BASE the engine below derives from —
	-- swap it (or call UI.SetAccent) to introduce a coloured theme later.
	goldBrand    = hex("F4F4F4"), -- C1 (was brand gold): brand/headers/wordmark -> heading off-white (non-clickable)
	goldInt      = hex("F4F4F6"), -- C2 = ACCENT BASE: active nav/tab fill, primary button fill, control accents
	goldIntHover = hex("FFFFFF"), -- C3: accent hover (a touch brighter)
	-- Softened light for FILLED toggle tracks: the switch ON track. A pure-white
	-- fill "blooms" (irradiation) next to the dark OFF track + dark knob, reading
	-- larger/harder than OFF; this calmer light keeps it clearly "on" without the
	-- blare and matches OFF's soft, round feel (Florian 2026-07-22).
	switchOn     = hex("D6D6DA"),
	-- Slider VALUE readout (default/blurred): leads clearly over the muted field
	-- label but is NOT the blaring pure-white accent — a card of 4 sliders side by
	-- side put 4 near-white values in a row and read "overloaded" (Florian
	-- 2026-07-22). Brightens to textPrimary while the value box has focus.
	sliderValue  = hex("C2C2C8"),

	-- D: text — FOUR tiers (doc: Heading / Body / Description / Disabled). The new
	-- Body tier is what calms the page: row & checkbox labels drop off the bright
	-- Heading so card titles keep the hierarchy alone.
	textPrimary  = hex("F4F4F4"), -- D1 Heading: card titles, wordmark, active nav, values
	textBody     = hex("D7D7D7"), -- D2 Body: row & checkbox labels (the calm mid tier)
	textSecondary= hex("9A9FA5"), -- D3 Description: descriptions, hints, field labels, idle nav, min/max
	textDisabled = hex("666A70"), -- D4 Disabled: greyed-out controls
	textOnGold   = hex("0C0C0C"), -- text/knob ON the light accent (dark = Window, so it reads)

	-- E: status (the one non-mono colour — destructive actions)
	danger       = hex("C74B4B"), -- E1: destructive text + outline
	dangerHover  = hex("D65C5C"), -- E2: hover step for E1
	-- (E3 stays free.)
}
UI.P = P

local function withA(c, a) return { r = c.r, g = c.g, b = c.b, a = a } end

-- ---------------------------------------------------------------------------
--  ACCENT ENGINE (v3, 2026-07-22) — the whole app derives its interactive
--  accent from ONE base colour. Today the accent is LIGHT ITSELF (monochrome
--  premium look, per Florian: build it clean-mono first, keep the colour option
--  ready). Later a user could pick any hue via UI.SetAccent and every derived
--  state recomputes with no component edits. Components read UI.Accent.* (and
--  UI.Surface/UI.Text/UI.Border/UI.Status), never a raw hex — the legacy UI.C
--  and UI.line alias tables are gone.
-- ---------------------------------------------------------------------------
local function mixTo(c, o, t) -- linear blend c -> o by t (0..1)
	return { r = c.r + (o.r - c.r) * t, g = c.g + (o.g - c.g) * t, b = c.b + (o.b - c.b) * t, a = 1 }
end
local WHITE = { r = 1, g = 1, b = 1 }
local BLACK = { r = 0, g = 0, b = 0 }
function UI.BuildAccent(base)
	return {
		color     = base,                 -- fills, active nav/tab, primary button, active borders
		hover     = mixTo(base, WHITE, 0.35), -- brighter on hover
		pressed   = mixTo(base, BLACK, 0.12), -- slightly darker while pressed
		selection = withA(base, 0.14),    -- selected-row / range wash
		focus     = withA(base, 0.55),    -- keyboard-focus ring
		glow      = withA(base, 0.35),    -- soft glow behind an active pill/indicator
		wash      = withA(base, 0.10),    -- accent wash (open/hover fills)
		washSoft  = withA(base, 0.06),    -- faint accent wash
		-- switchOn (filled toggle track) is a FIXED softened light in mono (anti-
		-- bloom, see P.switchOn); set after the build so it survives a live
		-- SetAccent until a coloured theme derives its own softened track.
	}
end
UI.ACCENT_BASE = P.goldInt
UI.Accent = UI.BuildAccent(UI.ACCENT_BASE)
UI.Accent.switchOn = P.switchOn -- softened light for the switch ON track (anti-bloom)
-- Accent colour at an arbitrary alpha (replaces the old UI.goldA). Reads the
-- live base so a future SetAccent flows through.
function UI.accentA(a) return withA(UI.ACCENT_BASE, a) end
-- Swap the interactive accent at runtime (future user theme). Rebuilds the
-- derived table IN PLACE so existing UI.Accent references stay valid.
function UI.SetAccent(col)
	local a = UI.BuildAccent(col)
	for k, v in pairs(a) do UI.Accent[k] = v end
	UI.ACCENT_BASE = col
end

-- ---------------------------------------------------------------------------
--  SEMANTIC TOKENS (v3 Design-System doc) — the forward-looking API. Components
--  should name a role (Surface.Card, Text.Body, Border.Default, Accent.color),
--  never a colour. Legacy UI.C.* aliases keep the existing ~7900 lines working
--  until call sites migrate onto these names.
-- ---------------------------------------------------------------------------
UI.Surface = {
	Window  = P.panel,        -- main window surface
	Sidebar = P.sidebar,      -- nav column
	Card    = P.card,         -- section cards
	Input   = P.inset,        -- edit boxes, dropdowns (closed & open), rows, neutral buttons, inactive tabs
	Hover   = P.elementHover, -- hover step; also the unfilled slider track channel
	Scrim   = P.page,         -- dim behind the panel + soft icon shadow
}
UI.Text = {
	Primary     = P.textPrimary,   -- Heading (brightest): titles, wordmark, active nav, values
	Secondary   = P.textBody,      -- Body (mid): row & checkbox labels
	Description = P.textSecondary,  -- muted: descriptions, hints, field labels, min/max, idle nav
	Disabled    = P.textDisabled,  -- greyed-out
	Value       = P.sliderValue,   -- slider readout (leads over the label, not pure white)
	OnAccent    = P.textOnGold,    -- text/knob ON the light accent (dark, so it reads)
}
-- Border lines — pure white at LOW alpha (hierarchy leans on the graduated
-- surface layers + fill, not on heavy borders). "active" = the pure-light accent
-- for open/selected edges. THE tuning spot.
UI.Border = {
	faint    = withA(P.borderSoft, 0.04),   -- finest content separators
	default  = withA(P.borderSoft, 0.05),   -- card / row borders
	hover    = withA(P.borderStrong, 0.10), -- standard control borders / hover edges
	divider  = withA(P.borderSoft, 0.10),   -- structural divider lines (header / nav)
	active   = UI.Accent.color,             -- active / open border (= accent)
}
UI.Status = {
	danger      = P.danger,
	dangerHover = P.dangerHover,
	dangerLine  = withA(P.danger, 0.55), -- destructive outline
	dangerWash  = withA(P.danger, 0.12), -- destructive fill wash
}

-- Danger colour at an arbitrary alpha (destructive control variants). Reads the
-- palette directly (UI.C is gone — every call site now uses UI.Surface/Text/
-- Border/Accent/Status).
function UI.dangerA(a) return withA(P.danger, a) end

-- ---------------------------------------------------------------------------
--  Fonts — bundled under <addon>/Fonts/ (Inter, SIL OFL)
-- ---------------------------------------------------------------------------
-- Built from the real addon-folder name (ADDON) so the path survives a folder
-- rename (e.g. Lumen -> LumenUI). ADDON is the first vararg = the folder name.
local FP = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
-- v3: ONE clean UI sans everywhere — Inter (SIL OFL). The mockup dropped Cinzel's
-- serif display face + Hanken for a single uniform sans (the SF-Pro-like look; SF
-- Pro itself is Apple-proprietary and can't be bundled). Inter switches heading
-- case to sentence case automatically (Cinzel was caps-only). The old Cinzel/
-- Hanken TTFs were removed in the v3 cleanup.
UI.FONT = {
	interReg  = FP .. "Inter-Regular.ttf",
	interMed  = FP .. "Inter-Medium.ttf",
	interSemi = FP .. "Inter-SemiBold.ttf",
	interBold = FP .. "Inter-Bold.ttf",
}
-- Semantic weight names (v3 cleanup): components/roles name a WEIGHT, not a
-- typeface — so the bundled font can be swapped in one place. Every UI.ROLE
-- entry + call site reads these; the old cinzel/hanken aliases are gone.
UI.FONT.regular  = UI.FONT.interReg
UI.FONT.medium   = UI.FONT.interMed
UI.FONT.semibold = UI.FONT.interSemi
UI.FONT.bold     = UI.FONT.interBold

-- (Font warm-up happens BELOW UI.ROLE — it warms every actually used
-- font+size pair, so it needs the role table first.)

-- Roles -> { path, size, flags }. Sizes from typography.css.
UI.ROLE = {
	wordmark = { UI.FONT.bold, 23, "" }, -- LUMENUI (mockup ratio: 18px@680w -> ~23px design-px, Bold = nearest cut to 680)
	display  = { UI.FONT.semibold, 22, "" },
	section  = { UI.FONT.semibold, 20, "" }, -- section heading (Cinzel)
	nav      = { UI.FONT.medium,  18, "" },
	body     = { UI.FONT.regular,  14, "" },
	label    = { UI.FONT.medium,  14, "" },
	tab      = { UI.FONT.medium,  18, "" },
	caption  = { UI.FONT.regular,  12, "" },
	hint     = { UI.FONT.regular,  16, "" }, -- description/hint text under controls
	tagline  = { UI.FONT.medium,  12, "" }, -- mockup ratio: 10px@500w -> Medium
	navGroupLabel = { UI.FONT.semibold, 12, "" }, -- "MODULES" nav-group caption (mockup: 10px@600w -> SemiBold; distinct from the shared "caption" role so it doesn't collapse onto the tagline's weight)

	-- Widget toolkit (phase 2) — small, control-near roles. Sizes on the
	-- 4px grid (12/16/20). Change here centrally -> propagates everywhere.
	fieldLabel = { UI.FONT.medium,  16, "" }, -- MUTED label above a control (slider/dropdown/segment); coloured Text.Description, not bright (mockup .flabel)
	sectionHead= { UI.FONT.semibold, 20, "" }, -- card/section titles + tab heading
	groupTitle = { UI.FONT.semibold, 16, "" }, -- GroupPanel title / IconTile letter
	sliderCap  = { UI.FONT.semibold, 16, "" }, -- slider caption
	value      = { UI.FONT.semibold, 14, "" }, -- value box (mockup ratio: 12px@580w -> nearest cut SemiBold)
	ends       = { UI.FONT.medium,  14, "" }, -- slider min/max numbers
	selectText = { UI.FONT.medium,  16, "" }, -- dropdown header + rows
	checkLabel = { UI.FONT.medium,  16, "" }, -- checkbox label
	listLabel  = { UI.FONT.medium,  18, "" }, -- list row (role sort list)
	-- (subDivider role retired with SectionDivider/SectionLabel.)
	btn        = { UI.FONT.semibold, 16, "" }, -- button label (weight per variant, see Widgets)

	-- Custom Lumen tooltip — own roles so font size/weight can be tuned
	-- independently (Florian adjusts these himself).
	tipTitle = { UI.FONT.semibold, 18, "" }, -- tooltip title / spell name (gold)
	tipBody  = { UI.FONT.regular,  16, "" }, -- tooltip text / spell description
}

-- Font warm-up: on a COLD START the FIRST SetFont per custom TTF renders empty
-- until the client glyph cache has rasterized the font (after /reload it is
-- still warm from the previous session -> text shows; real game start -> cold).
-- The cache is per FONT **AND SIZE**: warming one size does not cover the
-- others (cold-start report 2026-07-03: slider value box stayed blank while
-- other texts showed). So warm every unique font+size pair the roles use, on
-- persistent, fully transparent FontStrings — NOT :Hide() (hidden FontStrings
-- never render -> never rasterize) and anchored on-screen (off-screen would be
-- culled). Renders once on the first frame, warm BEFORE the Shell is built.
-- IMPORTANT: SetFont MUST come before SetText (SetText without a font throws).
do
	-- Glyphs the UI actually uses (German labels incl. umlauts/ß + digits + symbols).
	local GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÄÖÜäöüß0123456789 %+-#/.,()"
	local warmed = {}
	for _, r in pairs(UI.ROLE) do
		local key = r[1] .. "#" .. r[2]
		if not warmed[key] then
			warmed[key] = true
			local warm = UIParent:CreateFontString(nil, "BACKGROUND")
			warm:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 4)
			warm:SetAlpha(0)
			if pcall(warm.SetFont, warm, r[1], r[2], "") then pcall(warm.SetText, warm, GLYPHS) end
		end
	end
end

-- Set a FontString to a role. Returns the FontString (chainable).
function UI:SetFont(fs, role, color)
	local r = self.ROLE[role] or self.ROLE.body
	-- Fallback: if the custom-TTF SetFont fails (cold start, file not ready yet),
	-- prefer the default font at the same size over invisible text.
	if not fs:SetFont(r[1], r[2], r[3]) then
		fs:SetFont(STANDARD_TEXT_FONT, r[2], r[3])
	end
	if color then fs:SetTextColor(color.r, color.g, color.b, color.a or 1) end
	return fs
end

-- Letter-spacing emulation: WoW FontStrings have no tracking. For wordmark/
-- tagline/eyebrow we insert spaces between the characters.
function UI.Track(text, gap)
	gap = gap or " "
	local out = {}
	for i = 1, #text do out[i] = text:sub(i, i) end
	return table.concat(out, gap)
end

-- ---------------------------------------------------------------------------
--  Spacing & radii (spacing.css). Shell builds in design pixels; the panel
--  itself is scaled down to the screen via SetScale.
--  UNIT DECISION (design review 2026-07-05): the internal component spec table
--  is written in SCREEN pixels — design px =
--  screen px x 1.25 (the inverse of the 0.80 panel scale). A 4px screen grid
--  therefore maps to a 5px design grid (36 -> 45, 40 -> 50, 220 -> 275 ...).
-- ---------------------------------------------------------------------------
UI.S = {
	s1 = 2, s2 = 6, s3 = 8, s4 = 12, s5 = 14, s6 = 16, s7 = 20, s8 = 24, s9 = 36,
	cardPad     = 20,
	panelGutter = 30, -- content padding (spec 24 screen px)
	navWidth    = 315, -- sidebar (v3: +40 wider so the navbar gains L/R breathing room without cramping content)
	navGutter   = 50, -- v3: nav-specific left inset for wordmark/tagline/MODULES/items (more air than the content panelGutter)
	navBrandH   = 108, -- brand block (wordmark + tagline) at the top of the sidebar
	                  -- (v3: taller -> more air between the tagline and the MODULES caption / first item)
	tabH        = 52, -- tab strip / tab button height (v3: +4 taller, more generous row)
	tabStripPad = 7,  -- v3: inner padding of the tab-strip capsule around the tab pills (also the pill's vertical inset; pill height = tabH - 2*this = 38)
	tabGlowX    = 26, -- v3: baked glow horizontal bleed beyond the sliding tab pill (soft halo LARGER than the tab, spills past the strip edge)
	tabGlowTop  = 18, -- v3: glow bleed above the pill (broad halo, not just an underglow)
	tabGlowBot  = 22, -- v3: glow bleed below the pill
	navItemH    = 58, -- sidebar nav row height (Florian 2026-07-05: +8 taller)
	navPillPadX = 32, -- active-pill / hover-pill inset from the sidebar edges (v3: more L/R air, matches the wider navGutter)
	navPillPadY = 4,  -- active-pill vertical inset within the nav row
	navIconSize = 18, -- nav-row Lucide icon (TGA rendered at 32px, shown ~18)
	navIconGap  = 10, -- gap: nav icon -> label
	navGroupGap = 18, -- "MODULES" caption -> first nav item (mockup ratio: 14px @ 1x -> ~18 design-px)
	navItemGap  = 4,  -- v3: uniform gap between nav rows (group divider lines removed per the mockup)
	closeGlyph  = 18, -- close-button "x" glyph (Lucide) inside the 34px button
	scrollBarW  = 2,  -- width of the content scrollbar (Florian 2026-07-22: halved from 4 for a quieter, unobtrusive line; the thumb's hit-rect is padded in Shell.lua so grabbing it stays easy despite the thinner visual)
	scrollBarGap = 20, -- gap ScrollFrame -> scrollbar (Florian 2026-07-22: raised from 14 to match the unified 20px card rhythm, so the right-side gutter reads as generous as the left)
	tabBadgeH   = 26, -- tab-strip info badge height (v2 refinement no. 4, e.g. active spec)
	tabBadgePad = 12, -- inner L/R padding of the tab-strip badge
	contentTopGap = 26, -- tab strip -> content area (carried by the banner zone height)
}
UI.R = {
	panel = 2, control = 8, popover = 9, card = 10, check = 4,
}

-- ---------------------------------------------------------------------------
--  Widget dimensions — ALL dimensions of the widget toolkit, central. Change
--  here, then it propagates everywhere (Shell/Widgets.lua only reads from it,
--  no more magic numbers in the widget code). Values on the 4px grid — spec-
--  table conversions land on the 5px design grid instead (see UI.S note).
-- ---------------------------------------------------------------------------
UI.WIDGET = {
	controlH    = 51, -- dropdown/input height (v3 2026-07-22: 45->51 to match the mockup's taller select — padding 11px @ ~1x -> ~51 design-px)
	selectChevSize = 17, -- dropdown chevron glyph (Lucide chevron-down; mockup 14px @ ~1x -> ~17)
	segHugPad   = 20, -- horizontal padding per cell for a content-width (hug) segment (tab-like, not stretched)
	menuItemPadX = 6, -- horizontal inset of a dropdown item's rounded hover pill (nav-item language)
	menuItemPadY = 3, -- vertical inset of the pill (also the gap between stacked pills)
	chevGlyph      = 14, -- collapsible / disclosure chevron glyph (Lucide)
	sortArrowGlyph = 14, -- sort up/down arrow glyph (Lucide chevron-up/down)
	buttonH     = 48, -- button height (v3 2026-07-22: 48, deliberately < controlH 51 + fully-round PILL shape, matching the mockup where buttons are shorter pills than the taller selects; uses the existing pill-*-h48 assets)
	btnIcon     = 18, -- optional leading Lucide icon inside a W.Button (Edit Mode button)
	btnIconGap  = 8,  -- gap icon -> button label
	fieldGap    = 26, -- vertical gap label -> control below

	-- Checkbox
	checkBox    = 20, -- box edge length (spec 16 screen px)
	checkLabelGap = 10,

	selectRowH  = 50, -- dropdown menu row height (Florian 2026-07-22: 38 -> 44 -> 50, comfortable list rows)
	selectMenuPad = 10, -- inner padding of the dropdown popover (was 6; more air around the list + search)
	selectCheckSize = 15, -- selected-item check glyph (Lucide check, right-aligned like the mockup's ItemIndicator)

	-- Stacked option row (W.OptionRow — stacked-row standard, design bible §8):
	-- hairline on top, label left, compact control (switchSmallH tall) right.
	optionRowH  = 62, -- row height (28-high control + even air; Florian 2026-07-22: raised from 48 to match the mockup's more generous row padding, better readability)

	-- Slider
	sliderH     = 86, -- total height (label + track row + value box)
	sliderTrackH= 18, -- height of the clickable track row
	sliderBarH  = 5,  -- thickness of the bar (Florian 2026-07-22: was 4, a raw copy of the mockup's 4 CSS-px without the x1.25 physical-scale conversion used elsewhere -> rendered thinner than intended at our 0.80 panel scale)
	sliderThumb = 20, -- thumb disc diameter (spec 16 screen px; needs circle-<n> + circle-<n+4> assets -> circle-20 + circle-24)
	sliderCapGap= 30, -- yOffset label -> track row
	sliderEndW  = 28, -- width of the min/max number fields
	sliderEndPad= 10, -- gap number <-> track
	valueBoxW   = 92, -- value box width
	valueBoxH   = 28, -- value box height
	valueBoxGap = 10, -- yOffset track row -> value box
	-- Compact slider (card grid system, o.compact): label + inline editable
	-- value share the top line, full-width track below; no min/max ends, no
	-- framed value box. Sized as a FIELD CELL (label line + controlH band, like
	-- Select/Swatch) so mixed rows share one anatomy and the track centers in
	-- the control band: H = fieldGap + controlH, capGap = fieldGap + (controlH
	-- - sliderTrackH) / 2.
	sliderCompactH      = 71, -- field-cell height (26 + 45)
	sliderCompactCapGap = 39, -- label line -> track row (26 + (45 - 18) / 2, rounded down)
	sliderCompactValW   = 64, -- width of the inline value EditBox (right-aligned)
	sliderCompactValH   = 18, -- height of the inline value EditBox (one text line)
	-- Bare compact slider (Florian 2026-07-22, Option A -> matches the mockup):
	-- no sunken box, no fill/border/extra L-R padding -- just the label above a
	-- thin track, full cell width. sliderBoxH is still the standard row height
	-- every FieldRow-based slider is placed at (name kept for the moment; the
	-- "box" itself is gone).
	sliderBoxH = 72, -- row height for slider rows (matches sliderCompactH=71)

	-- GroupPanel
	groupTitleY = -16, -- yOffset of the title from the top edge
	groupContentY = -48, -- yOffset of the content area

	-- (dividerH/dividerGap retired with SectionDivider/SectionLabel.)

	-- Section panel (concept A: each section = own card with header). Centrally
	-- tunable; stack:section() in Shell.lua only reads from it.
	sectionPad         = 30, -- inner L/R + bottom padding of the card (Florian 2026-07-22: raised from 20 to match the mockup's card padding, less cramped)
	sectionHeaderH     = 46, -- collapsed-card header row (W.Collapsible)
	sectionAfterHeader = 26, -- DIVIDER -> first content row (Florian 2026-07-22: split from the title-to-divider gap, which now lives in cardHeadH/cardHeadSubH below, so this only covers the mockup's post-divider margin — no more double-counting now that the divider is real)
	-- In-card head (v3, Florian's mockup): title + optional muted description
	-- INSIDE the card body — no header bar, no divider, no accent bar.
	cardHeadTop  = 28, -- top padding above the title (Florian 2026-07-22: raised from 18 to match the mockup's card padding)
	cardHeadH    = 66, -- head block height without a description line -- DIVIDER sits at -cardHeadH, so this must clear cardHeadTop + the title's own rendered height + a little breathing room (Florian 2026-07-22: was 48, too short once cardHeadTop grew -> the divider cut through the title; re-check live, may need a nudge)
	cardHeadSubH = 84, -- head block height WITH a description line -- same fix, sized to clear cardHeadTop + title + subtitle line (was 68)
	cardSubY     = 52, -- yOffset of the description line from the card top (shifted +10 with cardHeadTop, same internal gap)
	cardEyeBtn   = 28, -- header eye toggle button edge length (preview/edit-mode layer visibility)
	cardEyeGlyph = 20, -- Lucide eye glyph inside cardEyeBtn
	sectionGap         = 20, -- gap between two section cards (Florian 2026-07-22: unified with G.cardGap so the horizontal and vertical card rhythm read as ONE consistent grid, per the mockup)
	headerStackGap     = 8,  -- gap between stacked COLLAPSED headers (ctx tabs; Florian: tighter than sectionGap)
	sectionTitleX      = 18, -- X indent of the header title
	sectionCountGap    = 10, -- gap title -> count chip (v2 refinement no. 1)
	sectionCountH      = 20, -- count chip height (width grows with the number)
	sectionCountPad    = 8,  -- inner L/R padding of the count chip

	-- Sub-box (subgroup): lighter function group INSIDE a section card.
	subgroupPad   = 16, -- inner indent of the sub-box (rows to box edge)
	subgroupGap   = 14, -- gap between two sub-boxes / after the last
	subgroupTitleH = 40, -- title area of a TITLED sub-box (label + gap to 1st row)

	-- Disclosure (card grid system): quiet "advanced" footer row of a section card.
	disclosureH        = 28,
	disclosureChevGap  = 8,  -- gap chevron -> label
	disclosureHintGap  = 10, -- gap label -> contents hint (shown while closed)
	-- Collapsible header extras (summary text + master toggle).
	collapsibleSummaryGap = 12, -- gap title -> summary text
	collapsibleToggleGap  = 14, -- gap switch -> chevron

	-- Hint (muted body-text line)
	hintH       = 40, -- default height of a hint block (1–2 lines)
	subHeadH    = 26, -- left-aligned sub-heading (e.g. aggro-stage blocks)

	-- (SCREEN-SPECIFIC measures live in UI.LAYOUT below, mirroring the nav tree —
	-- here in UI.WIDGET only dimensions of SHARED components. Rule: visible in
	-- more than one screen -> UI.WIDGET; only in one screen -> UI.LAYOUT.<screen>.)

	-- Color picker (own popover in Lumen style)
	cpSVW    = 280, -- width of the saturation/value field (wide enough for buttons + right margin)
	cpSVH    = 168, -- height of the SV field (= height of the hue bar)
	cpHueW   = 20,  -- width of the hue bar
	cpPad    = 16,  -- inner padding of the picker
	cpGap    = 12,  -- gap SV field <-> hue bar
	cpMarker = 10,  -- edge length of the markers
	cpPrevH  = 30,  -- height of the preview/hex row
	cpBtnGap = 8,   -- gap between Apply/Cancel in the color picker

	rowGap      = 30, -- column gap in W.Row (row3/row2)

	-- Spell picker (shared widget: Tracking tab, Click-Cast custom spells).
	-- The picker is the "real typeahead search": W.Select cannot scroll — here
	-- 30–60 spells run filtered in a SCROLLABLE list (search field on top + list).
	spellIcon      = 22, -- spell-icon edge length (picker rows, tracking rows, catalog)
	spBtnW         = 210, -- width of the "+ Add spell" trigger button
	spW            = 340, -- width of the spell-picker popover
	spPad          = 10,  -- inner padding of the popover
	spSearchH      = 44,  -- height of the search field (Florian 2026-07-22: 32 -> 44, taller/roomier; shared by W.Select + SpellPicker)
	spRowH         = 40,  -- height of a picker list row (roomier: +4px air top & bottom)
	spVisibleRows  = 7,   -- simultaneously visible rows (rest scrolls)
	spScrollW      = 4,   -- width of the picker scrollbar (also used by W.Select)
	spScrollGap    = 6,   -- gap list <-> scrollbar
	selectMaxRows  = 6,   -- W.Select: max. simultaneously visible options (rest scrolls) — Florian 2026-07-22: 8 -> 6

	-- Switch (pill on/off toggle) — reusable beyond Click-Cast. Grown +8 screen
	-- px in height (Florian 2026-07-05 in-game review: switches read too small).
	-- Heights need matching pill-<h> assets; knob = h - 2*knobPad -> circle-24 / circle-20.
	switchW       = 56,
	switchH       = 32,
	switchKnobPad = 4, -- inset of the sliding knob from the track edge
	-- Small variant (o.small): field cells + collapsible-header master toggles.
	switchSmallW  = 48,
	switchSmallH  = 28,
	-- Icon buttons (gear/trash/...): the hover surface extends past the glyph so
	-- it reads as a button face, not as a tight container around the icon.
	iconBtnHoverPad = 3,
	iconAction    = 22, -- gear/trash glyph edge length (catalog + tracking rows; decoupled from switchH)
	-- Keybind field: rounded face, solid gold ring when bound, faint ring when
	-- unbound (the dashed border was dropped for rounding consistency).
	-- Dash tokens still drive W.EmptyState's dashed placeholder box.
	kbDashLen     = 7, -- dash length of the dashed placeholder border
	kbDashGap     = 4, -- gap between dashes
	kbDashThick   = 2, -- dash thickness (pixel-snapped so it never vanishes at panel scale)

	-- Confirm dialog (modal confirmation popup; dims the Shell behind it).
	confirmW      = 460, -- card width
	confirmH      = 188, -- card height (title + 2–3 lines of text + button row)
	importDlgW    = 520, -- width of the import popup (W.ImportDialog; height grows with content)
	confirmPad    = 24,  -- inner padding of the card
	confirmBtnGap = 12,  -- gap between Confirm/Cancel
	confirmBtnW   = 150, -- fixed button width (text change doesn't break the layout)
	confirmDim    = 0.62, -- opacity of the dimming behind the popup

	-- Custom spell tooltip (Lumen design instead of Blizzard GameTooltip).
	tipW       = 320, -- fixed tooltip width
	tipPad     = 14,  -- inner padding
	tipIcon    = 28,  -- icon edge length in the header
	tipNameGap = 10,  -- icon -> name
	tipGap     = 10,  -- header (icon/name) -> description

	-- Preview dock (W.PreviewBand inside the Shell's satellite dock window —
	-- right of the panel for vertical layouts, below it for horizontal ones;
	-- used by the Raidframes screens, later by Unit Frames/Nameplates too).
	pvDockGap    = 8,   -- gap panel -> dock window (reads as its own window)
	pvDockPad    = 12,  -- inner padding of the dock body
	pvChipGroupGap = 14, -- gap between header chip groups / chips -> icons
	pvIconBtn    = 26,  -- filter/collapse icon button edge length
	pvGlyph      = 16,  -- Lucide glyph inside the pvIconBtn (collapse chevron / reset)
	pvFilterW    = 210, -- filter popover width
	pvFilterRowH = 32,  -- filter popover row height
	pvFilterPad  = 12,  -- filter popover inner padding
	pvFilterCheck = 18, -- filter checkbox edge length
	pvStagePad   = 24,  -- stage inner padding around the preview content
	pvCaptionH   = 18,  -- caption line at the stage bottom
	pvMinStageH  = 110, -- stage never collapses below this (empty-ish previews)
	pvStageMinW  = 240, -- right dock never narrower than this
	pvEyeH       = 28,  -- chip height (eye + size chips)
	pvEyePadX    = 12,  -- inner L/R padding of a chip
	pvEyeGap     = 6,   -- gap between chips
	pvSnap       = 60,  -- drop within this distance of the docked spot -> snap back on
}

-- ---------------------------------------------------------------------------
--  LAYOUT — SCREEN-SPECIFIC measures & spacings, same idea as the color palette:
--  ONE central block whose structure MIRRORS THE NAVIGATION (left nav -> tabs),
--  top-down. Finding a measure = walking the UI path (e.g. the height of a
--  tracked-spell row lives at LAYOUT.raidframes.tracking.rowH). Rule: a measure
--  visible in MORE than one screen belongs in UI.WIDGET (shared components);
--  a measure of exactly one screen belongs HERE under its screen. Values in
--  design pixels (4px grid).
--  NOTE: the ELEMENT/row ORDER per section lives in the respective block in
--  Shell/Screens.lua (clearly commented) — to reorder just say so.
-- ---------------------------------------------------------------------------
UI.LAYOUT = {
	-- RHYTHM — semantic row spacings (cross-screen). Choose spacing via the
	-- RELATIONSHIP of two rows, not via a guessed number. Principle: a height
	-- jump (short control -> tall control) needs more air.
	rhythm = {
		tight      = 14, -- tightly related rows (slider->slider, size/X/Y->color)
		row        = 22, -- standard between two control rows
		afterCheck = 30, -- after checkbox/short control -> tall control (dropdown/slider)
		group      = 32, -- deliberate break between two sub-groups in a card
	},
	-- GENERAL — cross-screen constants used by several tabs.
	general = {
		tabTop      = 0, -- tab strip -> first element (0: air above/below the strip is EQUAL — Florian 2026-07-05)
		sideGap     = 28, -- control -> checkbox sitting right next to it
		checkRowGap = 40, -- between two checkboxes in a row
	},

	-- ==== From here on the tree mirrors the LEFT NAV, top-down. ====

	global = {
		profile = {             -- Global -> Profile tab (profiles + export/import)
			taH            = 120, -- height of the export/import textarea
			afterExportBtn = 14,  -- "Generate export code" -> export textarea
		},
	},

	-- (qol block retired: the stacked-row pilot became the addon-wide standard —
	-- the row height lives in UI.WIDGET.optionRowH now.)

	clickcast = {               -- Click-Cast (mouse bindings + hovercast + catalog)
		-- spacings (the pre-card-migration divider/master gaps are retired —
		-- the master card + section cards space themselves via sectionGap)
		afterList    = 8,   -- last box -> "+ add" button
		emptyH       = 30,  -- height of the "(no bindings)" row
		-- dimensions (catalog rows)
		rowH     = 66,  -- card row height (keeps ~7px air around the keybind field at controlH 51)
		rowGap   = 8,   -- gap between rounded row cards (Option b: no longer flush)
		                -- so adjacent rows share ONE 1px line (no doubled border)
		rowPad   = 20,  -- inner left/right padding inside a row card
		rowGapX  = 14,  -- horizontal gap between the right-cluster items (keybind/gear/switch)
		addGap   = 8,   -- gap above the "+ Add binding/spell" buttons (off the last row)
		keyW     = 150, -- keybind field width
		specW    = 230, -- spec dropdown width (top-right, on the master toggle row)
		icon     = 30,  -- spell-icon tile edge length (square, gold border)
		gearSize = 18,  -- options gear icon size
	},

	raidframes = {
		base = {                -- Raidframes -> Base tab
			toggleToSection = 16, -- master checkbox -> first section card
			healthbar = {
				afterTexHint = 10, -- texture row -> mouse-wheel/search hint (close below)
			},
			sort = {              -- role/group sort priority card
				afterMode = 22, -- "Sort by" -> priority card
				afterCard = 52, -- card -> next category
				rowH      = 42, -- height of a row in the role priority list
				cardPad   = 6,  -- inner padding of the priority card
				accentW   = 4,  -- width of the role-colored accent bar on the left
			},
		},
		-- (sizeArrange spacings retired with the Raid/Group card-grid migration —
		-- those rows now use the shared rhythm tokens like every other card.)
		tracking = {            -- Tracking tab (whitelist editor)
			introH      = 58,  -- height of the multi-line intro hint
			afterIntro  = 22,  -- intro -> first category card (spec moved to the tab-strip badge)
			-- (afterDesc retired: the category description is the card subtitle now)
			betweenRows = 8,   -- between two tracked spell rows (v2: more air)
			emptyH      = 52,  -- height of the empty-state box when the list is empty
			afterList   = 18,  -- list -> action buttons (picker)
			rowH        = 44,  -- height of a tracked-spell row (v2: roomier)
			-- (trash icon size lives in UI.WIDGET.iconAction — shared with the
			-- Click-Cast catalog rows per the shared-component rule)
		},
	},
}

-- Panel dimensions. Scaled down to the screen via SetScale — 1750×1250 at
-- scale 0.80 = exactly the spec window of 1400×1000 SCREEN px (Florian's
-- component table, 2026-07-05). Tune here — w/h change the space, scale the
-- overall size incl. font.
-- (v2: no footer and no full-width header anymore — the sidebar runs the full
-- panel height and carries the brand block; see S.navBrandH.)
UI.PANEL = {
	w = 1790, h = 1250, scale = 0.80, -- v3: +40 wider (the nav gained +40; content width unchanged)
}

-- ---------------------------------------------------------------------------
--  Card grid (settings layout system, decided 2026-07-04): the page divides
--  into 12 tracks; section cards span EVEN track counts (4/6/8/12) and sit in
--  horizontal BANDS (stack:band). Vertical rhythm quantizes to the 8pt scale.
-- ---------------------------------------------------------------------------
UI.GRID = {
	cols    = 12, -- page tracks (cards span even counts: 4/6/8/12)
	cardGap = 20, -- gutter between two cards in a band AND between field cells (Florian 2026-07-22: raised from 16, unified with M.sectionGap so horizontal + vertical card rhythm match)
	cellGap = 8,  -- gutter between tight utility cells (tracked-spell grid etc., 8pt)
	pairGap = 32, -- gutter between WIDE controls sharing a row (8pt)
	-- Control layout inside a card (stacked-row standard, design bible §8):
	-- COMPACT options (switch / checkbox / color chip) = stacked W.OptionRow
	-- rows, one per option. FIELD controls (dropdown / slider box / segment)
	-- = W.FieldRow cells at the ONE addon-wide unit width (half a 6-card):
	-- 2 per row fill a 6-card exactly, 8-cards keep air on the right, a 4-card
	-- takes 1 per row. Doesn't fit -> next row; nothing stretches or shrinks.
}

-- ---------------------------------------------------------------------------
--  Shared build primitives (Shell chrome + widget toolkit read from it — DRY).
--  Previously file-locals in Shell.lua; hoisted so both can share them.
--  Behavior identical (pure relocation).
-- ---------------------------------------------------------------------------
-- Round-aware: the rounded/pill/circle FILE textures (marked _round at
-- creation) must be tinted via SetVertexColor — SetColorTexture would replace
-- the file with a solid quad and kill the shape. All state/hover recolor
-- call sites keep working unchanged through this one switch.
function UI.SetColor(t, col)
	if t._round then t:SetVertexColor(col.r, col.g, col.b, col.a or 1)
	else t:SetColorTexture(col.r, col.g, col.b, col.a or 1) end
end

-- Full-surface fill texture over parent.
function UI.Fill(parent, col, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints(parent)
	UI.SetColor(t, col)
	return t
end

-- Draw a 1px hairline border (4 edges) around a frame in the given colour.
-- Named UI.Stroke (not UI.Border) because UI.Border is the border-COLOUR token
-- table; this is the drawing primitive, the hairline counterpart to UI.Fill.
-- Returns the 4 edge
-- textures (for later recoloring, e.g. hover/active).
--
-- IMPORTANT RULE (hard-learned, DO NOT revert): ONLY the THICKNESS is pixel-
-- snapped (PixelUtil.SetHeight/SetWidth -> crisp 1px even under SetScale=0.80).
-- The POSITION runs via plain SetPoint(0,0) to the frame edges. Previously the
-- position was also snapped via PixelUtil.SetPoint — but that baked in an ABSOLUTE,
-- position-dependent offset: as soon as the frame was moved/re-anchored AFTERWARDS
-- (placeLeft, newly set anchors) OR scrolled inside the ScrollFrame, the offset was
-- "off" and the 1px line fell between two pixels -> vanished (the recurring tab/
-- dropdown/button border bug). Plain anchoring glues the line ALWAYS to the edge ->
-- the whole bug class is eliminated.
function UI.Stroke(frame, col, thick, layer)
	thick = thick or 1
	local edges = {}
	local function mk()
		local t = frame:CreateTexture(nil, layer or "BORDER")
		UI.SetColor(t, col)
		edges[#edges + 1] = t
		return t
	end
	local top, bot, left, right = mk(), mk(), mk(), mk()
	top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	bot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	bot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	-- Thickness pixel-exact (even when the effective scale is only final after the
	-- layout/show -> immediately + one frame later + on size/visibility change).
	local function snapThickness()
		PixelUtil.SetHeight(top, thick)
		PixelUtil.SetHeight(bot, thick)
		PixelUtil.SetWidth(left, thick)
		PixelUtil.SetWidth(right, thick)
	end
	snapThickness()
	C_Timer.After(0, snapThickness)
	frame:HookScript("OnSizeChanged", snapThickness)
	frame:HookScript("OnShow", snapThickness)
	return edges
end

-- ---------------------------------------------------------------------------
--  Rounded surfaces (decided 2026-07-05): white 9-slice TGAs tinted via
--  vertex color — ONE asset set covers every color/state, generated with the
--  Lucide SVG->TGA pipeline. Counterpart to UI.Fill/UI.Border; call sites opt
--  in per surface.
--  Radii follow Florian's formalized SCALE (2026-07-05):
--    XS 4  — checkboxes, slider track, small badges/chips (count chip, tab badge)
--    SM 6  — color swatches, small icons with a hover face, header chips
--    MD 8  — buttons, dropdowns, tabs, text fields, segments, slider thumb/boxes
--    LG 18 — cards, panels, group boxes, floating popovers/menus/tooltip (v3: 10->18)
--    XL 22 — main window (panel/sidebar/dock) + modal dialogs (v3: 16->22)
--  Nesting rule stays: outer radius = inner radius + padding.
--  Shapes: "full" (default) | "top" | "bottom" | "left" | "right" — the
--  half-rounded variants are for flush-attached surfaces (collapsible header
--  + body card, the sidebar in the panel's left edge, segment end cells):
--  the seam edge stays square so the pair reads as ONE rounded object.
--  Ring assets carry a 2px stroke (Florian 2026-07-05: the 1px ring got lost
--  at the 0.80 panel scale — 2px source px never drop below a full pixel).
--  NOTE: never recolor these via SetColorTexture (that would replace the file
--  texture with a solid quad) — UI.SetColor routes them to SetVertexColor.
-- ---------------------------------------------------------------------------
local ROUND_TEX    = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\round\\" -- round-fill/round-edge 9-slice assets
local PILL_TEX     = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\pill\\"  -- pill-fill/pill-edge capsules + circle discs
local ROUND_MARGIN = { [4] = 5, [6] = 7, [8] = 9, [10] = 11, [12] = 13, [14] = 15, [16] = 17, [18] = 19, [22] = 23 } -- source px covering the corner (+1px straight buffer)
local ROUND_SUFFIX = { top = "-top", bottom = "-btm", left = "-left", right = "-right" } -- else full
-- v3 (2026-07-21): radii bumped toward GENEROUS on the headline surfaces —
-- cards lg 10->18, chrome xl 16->22 (new 9-slice assets generated for both;
-- 14 was too subtle at the 0.80 panel scale, bumped to 18). Controls: sm/xs
-- unchanged; md later bumped 8->14 (v3 2026-07-22) so control faces (dropdowns/
-- buttons/segments/inputs) match the mockup's rounder select — r14 assets baked,
-- old r8 control assets now unused but left in place (harmless).
UI.RADIUS = { xs = 4, sm = 6, md = 14, lg = 18, xl = 22 } -- THE scale (see table above; md 8->14 in v3 2026-07-22 = control faces rounder to match the mockup's ~11px@1x select radius. r14 fill/left/right/edge assets baked)
UI.ROUND_R        = UI.RADIUS.lg -- cards/panels/popovers (default radius)
UI.ROUND_R_CHROME = UI.RADIUS.xl -- main chrome: panel, sidebar, preview dock + modals
UI.ROUND_R_CTRL   = UI.RADIUS.md -- control faces: fields, buttons, segments, inset boxes

local function markRound(t)
	-- Texel snapping off: the antialiased curve must not be forced onto the
	-- pixel grid (would alias visibly under the shell's SetScale 0.80).
	t:SetSnapToPixelGrid(false)
	t:SetTexelSnappingBias(0)
	t._round = true -- UI.SetColor routes recolors through SetVertexColor
	return t
end

local function roundTexture(parent, file, col, layer, shape, r)
	r = r or UI.ROUND_R
	local m = ROUND_MARGIN[r]
	local t = markRound(parent:CreateTexture(nil, layer or "BACKGROUND"))
	t:SetTexture(ROUND_TEX .. file .. "-r" .. r .. (ROUND_SUFFIX[shape] or ""))
	t:SetTextureSliceMargins(m, m, m, m)
	t:SetAllPoints(parent)
	t:SetVertexColor(col.r, col.g, col.b, col.a or 1)
	return t
end

-- Rounded counterpart of UI.Fill. radius: nil = ROUND_R | UI.ROUND_R_CHROME.
function UI.RoundFill(parent, col, layer, shape, radius)
	return roundTexture(parent, "round-fill", col, layer, shape, radius)
end

-- Rounded counterpart of UI.Border: ONE 9-slice ring texture instead of 4
-- snapped edges (thickness = 1 source px, baked into the asset). Returned in
-- a table so call sites treating the result like UI.Border's edge list work.
function UI.RoundBorder(frame, col, layer, shape, radius)
	return { roundTexture(frame, "round-edge", col, layer or "BORDER", shape, radius) }
end

-- Pill surfaces (switch tracks): capsule assets at the EXACT display height
-- (32 / 28 switches; 4 slider bars) so only the straight middle stretches
-- horizontally — vertical scale stays 1:1 and the end caps keep their curve.
-- h must match the frame's height exactly.
local PILL_MARGIN = { [52] = 27, [48] = 25, [38] = 20, [36] = 19, [32] = 17, [28] = 15, [22] = 12, [18] = 10, [4] = 3 } -- cap width (radius + 1px buffer)

local function pillTexture(parent, file, col, layer, h)
	local m = PILL_MARGIN[h]
	local t = markRound(parent:CreateTexture(nil, layer or "BACKGROUND"))
	t:SetTexture(PILL_TEX .. file .. "-h" .. h)
	t:SetTextureSliceMargins(m, 0, m, 0)
	t:SetAllPoints(parent)
	t:SetVertexColor(col.r, col.g, col.b, col.a or 1)
	return t
end

function UI.PillFill(parent, col, layer, h)
	return pillTexture(parent, "pill-fill", col, layer, h)
end

function UI.PillBorder(frame, col, layer, h)
	return { pillTexture(frame, "pill-edge", col, layer or "BORDER", h) }
end

-- Circle disc (slider thumb, switch knobs): plain full-bleed texture at the
-- EXACT display size (no slicing — a circle cannot 9-slice). The caller
-- anchors it; recolor via UI.SetColor/SetVertexColor.
function UI.Circle(parent, col, layer, size)
	local t = markRound(parent:CreateTexture(nil, layer or "ARTWORK"))
	t:SetTexture(PILL_TEX .. "circle-" .. size)
	t:SetSize(size, size)
	t:SetVertexColor(col.r, col.g, col.b, col.a or 1)
	return t
end

-- ---------------------------------------------------------------------------
--  Sliding indicator engine (v3) — ONE pill that TWEENS to the active item.
--  A SHORT, self-terminating ease-out-cubic (§9-safe: the OnUpdate stops itself
--  after SLIDE_DUR, NOT a persistent per-frame poll). Shared by the Shell chrome
--  (tabs slide in X + resize; nav slides in Y) AND the Segment control (Widgets),
--  so they animate identically. ind._ref = the frame the (ox,oy) offsets anchor to.
-- ---------------------------------------------------------------------------
UI.SLIDE_DUR = 0.28
function UI.slideTo(ind, ox, oy, w, h, animate)
	w = math.max(1, w); h = math.max(1, h)
	local function apply(x, y, ww, hh)
		ind:ClearAllPoints()
		ind:SetPoint("TOPLEFT", ind._ref, "TOPLEFT", x, y)
		ind:SetSize(ww, hh)
	end
	if (not animate) or ind._cx == nil then
		ind._cx, ind._cy, ind._cw, ind._ch = ox, oy, w, h
		ind:SetScript("OnUpdate", nil)
		apply(ox, oy, w, h); ind:Show()
		return
	end
	local sx, sy, sw, sh = ind._cx, ind._cy, ind._cw, ind._ch
	ind:Show()
	local el = 0
	ind:SetScript("OnUpdate", function(self, dt)
		el = el + dt
		local t = el / UI.SLIDE_DUR; if t > 1 then t = 1 end
		local e = 1 - (1 - t) * (1 - t) * (1 - t) -- ease-out cubic
		local x  = sx + (ox - sx) * e
		local y  = sy + (oy - sy) * e
		local ww = sw + (w - sw) * e
		local hh = sh + (h - sh) * e
		self._cx, self._cy, self._cw, self._ch = x, y, ww, hh
		apply(x, y, ww, hh)
		if t >= 1 then self:SetScript("OnUpdate", nil) end
	end)
end

-- Geometry of `item` in `ref`'s LOCAL coordinate units (item and ref share the
-- same effective scale, so their GetLeft/GetTop deltas are already local — no
-- scale conversion). Returns nil while positions are unresolved (parent hidden).
function UI.itemRectIn(item, ref)
	local iL, iT = item:GetLeft(), item:GetTop()
	local rL, rT = ref:GetLeft(), ref:GetTop()
	if not (iL and iT and rL and rT) then return nil end
	return (iL - rL), (iT - rT), item:GetWidth(), item:GetHeight()
end

-- WoW inline color escape ("|cffRRGGBB") from a palette color — keeps hex values
-- out of call sites (the palette block above stays the only place hexes exist).
function UI.ColorCode(col)
	return ("|cff%02x%02x%02x"):format(
		math.floor(col.r * 255 + 0.5),
		math.floor(col.g * 255 + 0.5),
		math.floor(col.b * 255 + 0.5))
end

-- FontString in a design role.
function UI.FS(parent, role, col, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	UI:SetFont(fs, role, col)
	return fs
end

-- (UI.GradientLine retired with SectionDivider/SectionLabel — no callers left.)
