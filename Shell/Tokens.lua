local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell Design Tokens
--  Source of truth: design line v2 (Florian's flat prototype, 2026-07-02).
--  Central, so the Shell + widget toolkit read consistently from it.
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
	-- A: surfaces (layering; the sidebar is DELIBERATELY the lightest base surface)
	-- v3 COOL TINT (2026-07-04, from Florian's card mockup: "bisschen ins
	-- Blau" instead of neutral grey) — same lightness ladder as v2, hue shifted
	-- toward blue. Derived values, pending Florian's eye; v2 neutrals in ().
	inset        = hex("14161A"), -- A1: edit boxes, open dropdown lists, slider value box, scroll troughs (151617)
	sidebar      = hex("1E2128"), -- A2: nav column (1F2022)
	panel        = hex("1A1D23"), -- A3: main window surface (1B1D1E)
	card         = hex("1C1F26"), -- A4: section cards (1D1F20)
	element      = hex("282C35"), -- A5: rows, neutral buttons, closed dropdowns, inactive tabs (292A2B)
	elementHover = hex("333844"), -- A6: hover step for A5 (333436)

	-- B: lines (cool-tinted with the A ladder)
	borderSoft   = hex("2F343E"), -- B1: card/row borders, fine separators (2F3134)
	borderStrong = hex("3A404C"), -- B2: control borders, hover edges, focus (363739)

	-- C: gold — two-gold rule: C1 = brand (non-clickable), C2/C3 = interactive
	goldBrand    = hex("E9BB69"), -- C1: wordmark, logo, section headers, accent bars, text accents
	goldInt      = hex("CDA255"), -- C2: active nav/tab fill, primary button fill, secondary outline+text
	goldIntHover = hex("D4AF6D"), -- C3: hover step for C2

	-- D: text
	textPrimary  = hex("D0D0D1"), -- D1: names, labels, button text
	textSecondary= hex("808283"), -- D2: descriptions, hints, min/max numbers
	textDisabled = hex("3A404C"), -- D3: greyed-out controls (= B2, deliberate reuse)
	textOnGold   = hex("1B1D1E"), -- D4: text on gold fills (= A3, deliberate reuse)

	-- E: status
	danger       = hex("C74B4B"), -- E1: destructive text + outline
	dangerHover  = hex("D65C5C"), -- E2: hover step for E1
	-- (E3 stays free: the v1 success green was dropped 2026-07-03 — add actions
	-- are secondary gold now; red remains the only status color.)
}
UI.P = P

-- Legacy token names -> palette roles. Widgets/Screens/Shell still read UI.C.*;
-- redesign phases 2/3 migrate the call sites onto UI.P directly, then the
-- remaining aliases here shrink away.
UI.C = {
	-- grounds (old warm ink ramp -> new neutral surfaces)
	ink900   = P.inset,        -- app background / dim
	ink850   = P.panel,        -- main panel
	ink800   = P.panel,        -- (was: glow center; flat now)
	ink700   = P.element,      -- closed dropdown header / keybind field (A5 per v2 spec)
	ink650   = P.inset,        -- icon-tile shadow
	ink600   = P.card,         -- raised card
	ink550   = P.inset,        -- popover / open dropdown list (A1 per v2 spec)
	ink520   = P.card,         -- sub-box (grouping is carried by borders now, not a lighter fill)
	inkTint  = P.element,      -- (was: icon-tile gradient top; flat now)
	sliderTrack = P.element,   -- unfilled slider track

	-- gold
	gold500  = P.goldInt,      -- interactive accent: control borders, icons, active
	gold400  = P.goldIntHover, -- button hover
	gold300  = P.goldBrand,    -- wordmark / display heading
	gold250  = P.goldBrand,    -- brand-gold text accents (tooltip title, active list rows)
	gold200  = P.goldIntHover, -- link hover
	gold100  = P.textPrimary,  -- (was: lightest gold-white) -> neutral primary text

	-- text
	textStrong  = P.textPrimary,
	textHeading = P.textPrimary,
	textBody    = P.textPrimary,   -- checkbox/row labels
	textMuted   = P.textSecondary,
	textFaint   = P.textSecondary, -- muted-but-readable (true disabled uses P.textDisabled)
	onGold      = P.textOnGold,

	-- status
	danger500 = P.danger,
	danger300 = P.dangerHover,
}

-- Gold/danger in standard opacities (washes, active borders) — as {r,g,b,a}.
local g = UI.C.gold500
local d = UI.C.danger500
local function goldA(a) return { r = g.r, g = g.g, b = g.b, a = a } end
local function dangerA(a) return { r = d.r, g = d.g, b = d.b, a = a } end
local function withA(c, a) return { r = c.r, g = c.g, b = c.b, a = a } end
UI.goldA = goldA
UI.dangerA = dangerA

-- v2: structural lines are NEUTRAL (B1/B2) instead of gold-at-opacity; gold
-- only remains on ACTIVE/open states and hover washes (interactive accent).
-- Border guideline (Florian 2026-07-05): borders are a SUBTLE separator, not
-- the primary design element — 2px ring assets carry render stability, the
-- reduced opacity below makes them read fine again. THE tuning spot.
UI.line = {
	faint   = withA(P.borderSoft, 0.60),   -- fine separators (content)
	divider = withA(P.borderSoft, 0.80),   -- structural divider lines header/footer/nav
	soft    = withA(P.borderSoft, 0.70),   -- soft control borders (cards, rows)
	mid     = withA(P.borderStrong, 0.85), -- standard control borders
	strong  = withA(P.goldInt, 1),         -- active / open (stays gold)
	washSoft = goldA(0.07),
	wash     = goldA(0.12),
	dangerLine = dangerA(0.55),
	dangerWash = dangerA(0.12),
}

-- ---------------------------------------------------------------------------
--  Fonts — bundled under <addon>/Fonts/ (Cinzel + Hanken Grotesk, SIL OFL)
-- ---------------------------------------------------------------------------
-- Built from the real addon-folder name (ADDON) so the path survives a folder
-- rename (e.g. Lumen -> LumenUI). ADDON is the first vararg = the folder name.
local FP = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
UI.FONT = {
	cinzelSemi   = FP .. "Cinzel-SemiBold.ttf",
	cinzelBold   = FP .. "Cinzel-Bold.ttf",
	hankenReg    = FP .. "HankenGrotesk-Regular.ttf",
	hankenMed    = FP .. "HankenGrotesk-Medium.ttf",
	hankenSemi   = FP .. "HankenGrotesk-SemiBold.ttf",
	hankenBold   = FP .. "HankenGrotesk-Bold.ttf",
}

-- (Font warm-up happens BELOW UI.ROLE — it warms every actually used
-- font+size pair, so it needs the role table first.)

-- Roles -> { path, size, flags }. Sizes from typography.css.
UI.ROLE = {
	wordmark = { UI.FONT.cinzelSemi, 26, "" }, -- LUMENUI (sized to fit the 260px sidebar)
	display  = { UI.FONT.cinzelSemi, 22, "" },
	section  = { UI.FONT.cinzelSemi, 20, "" }, -- section heading (Cinzel)
	nav      = { UI.FONT.hankenMed,  18, "" },
	body     = { UI.FONT.hankenReg,  14, "" },
	label    = { UI.FONT.hankenMed,  14, "" },
	tab      = { UI.FONT.hankenMed,  18, "" },
	caption  = { UI.FONT.hankenReg,  12, "" },
	hint     = { UI.FONT.hankenReg,  16, "" }, -- description/hint text under controls
	tagline  = { UI.FONT.hankenReg,  12, "" },

	-- Widget toolkit (phase 2) — small, control-near roles. Sizes on the
	-- 4px grid (12/16/20). Change here centrally -> propagates everywhere.
	fieldLabel = { UI.FONT.hankenMed,  16, "" }, -- gold label above a control (dropdown etc.)
	sectionHead= { UI.FONT.cinzelSemi, 20, "" }, -- card/section titles + tab heading
	groupTitle = { UI.FONT.cinzelSemi, 16, "" }, -- GroupPanel title / IconTile letter
	sliderCap  = { UI.FONT.cinzelSemi, 16, "" }, -- slider caption
	value      = { UI.FONT.hankenMed,  14, "" }, -- value box
	ends       = { UI.FONT.hankenMed,  14, "" }, -- slider min/max numbers
	selectText = { UI.FONT.hankenMed,  16, "" }, -- dropdown header + rows
	checkLabel = { UI.FONT.hankenMed,  16, "" }, -- checkbox label
	listLabel  = { UI.FONT.hankenMed,  18, "" }, -- list row (role sort list)
	-- (subDivider role retired with SectionDivider/SectionLabel.)
	btn        = { UI.FONT.hankenSemi, 16, "" }, -- button label (weight per variant, see Widgets)

	-- Custom Lumen tooltip — own roles so font size/weight can be tuned
	-- independently (Florian adjusts these himself).
	tipTitle = { UI.FONT.hankenSemi, 18, "" }, -- tooltip title / spell name (gold)
	tipBody  = { UI.FONT.hankenReg,  16, "" }, -- tooltip text / spell description
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
	navWidth    = 275, -- sidebar (spec 220 screen px)
	navBrandH   = 88, -- brand block (wordmark + tagline) at the top of the sidebar
	                  -- (spec "Header 56" maps to app headers, not this block — kept as is)
	tabH        = 48, -- tab strip / tab button height (spec 38 screen px -> 47.5, on-grid 48)
	navItemH    = 58, -- sidebar nav row height (Florian 2026-07-05: +8 taller)
	navPillPadX = 12, -- active-pill inset from the sidebar edges (v3 nav mockup)
	navPillPadY = 4,  -- active-pill vertical inset within the nav row
	navIconSize = 18, -- nav-row Lucide icon (TGA rendered at 32px, shown ~18)
	navIconGap  = 10, -- gap: nav icon -> label
	navGroupGap = 10, -- "MODULES" caption -> first nav item
	closeGlyph  = 18, -- close-button "x" glyph (Lucide) inside the 34px button
	scrollBarW  = 4,  -- width of the content scrollbar
	scrollBarGap = 14, -- gap ScrollFrame -> scrollbar (in the gutter)
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
	controlH    = 45, -- dropdown/input height (spec 36 screen px)
	selectChevSize = 14, -- dropdown chevron glyph (Lucide chevron-down)
	chevGlyph      = 14, -- collapsible / disclosure chevron glyph (Lucide)
	sortArrowGlyph = 14, -- sort up/down arrow glyph (Lucide chevron-up/down)
	buttonH     = 45, -- button height (= controlH: uniform, hierarchy comes from the variant colors — Florian 2026-07-05)
	btnIcon     = 18, -- optional leading Lucide icon inside a W.Button (Edit Mode button)
	btnIconGap  = 8,  -- gap icon -> button label
	fieldGap    = 26, -- vertical gap label -> control below

	-- Checkbox
	checkBox    = 20, -- box edge length (spec 16 screen px)
	checkLabelGap = 10,

	selectRowH  = 38, -- dropdown menu row height (Florian 2026-07-05: 34 read too cramped)

	-- Stacked option row (W.OptionRow — stacked-row standard, design bible §8):
	-- hairline on top, label left, compact control (switchSmallH tall) right.
	optionRowH  = 48, -- row height (28-high control + even air)

	-- Slider
	sliderH     = 86, -- total height (label + track row + value box)
	sliderTrackH= 18, -- height of the clickable track row
	sliderBarH  = 4,  -- thickness of the bar
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
	-- Boxed compact slider (v3 mockup): each slider in its own inset box (A1,
	-- one step darker than the card), so a slider group reads as one unit.
	sliderBoxPadY = 12, -- inner top padding of the box
	sliderBoxPadX = 20, -- inner left/right padding (slider needs air to the box edge; 4pt raster)
	sliderBoxH   = 72, -- box height (row height for boxed slider rows)
	sliderBoxCapGap = 24, -- tighter label -> track gap inside a box

	-- GroupPanel
	groupTitleY = -16, -- yOffset of the title from the top edge
	groupContentY = -48, -- yOffset of the content area

	-- (dividerH/dividerGap retired with SectionDivider/SectionLabel.)

	-- Section panel (concept A: each section = own card with header). Centrally
	-- tunable; stack:section() in Shell.lua only reads from it.
	sectionPad         = 20, -- inner L/R + bottom padding of the card (spec 16 screen px)
	sectionHeaderH     = 46, -- collapsed-card header row (W.Collapsible)
	sectionAfterHeader = 18, -- header bottom edge -> first content row
	-- In-card head (v3, Florian's mockup): title + optional muted description
	-- INSIDE the card body — no header bar, no divider, no accent bar.
	cardHeadTop  = 18, -- top padding above the title
	cardHeadH    = 48, -- head block height without a description line
	cardHeadSubH = 68, -- head block height WITH a description line
	cardSubY     = 42, -- yOffset of the description line from the card top
	cardEyeBtn   = 28, -- header eye toggle button edge length (preview/edit-mode layer visibility)
	cardEyeGlyph = 20, -- Lucide eye glyph inside cardEyeBtn
	sectionGap         = 26, -- gap between two section cards
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
	spSearchH      = 32,  -- height of the search field
	spRowH         = 40,  -- height of a picker list row (roomier: +4px air top & bottom)
	spVisibleRows  = 7,   -- simultaneously visible rows (rest scrolls)
	spScrollW      = 4,   -- width of the picker scrollbar (also used by W.Select)
	spScrollGap    = 6,   -- gap list <-> scrollbar
	selectMaxRows  = 8,   -- W.Select: max. simultaneously visible options (rest scrolls)

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
	pvGlyph      = 16,  -- Lucide glyph inside the pvIconBtn (funnel / collapse chevron)
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
		rowH     = 60,  -- card row height (keeps ~7px air around the keybind field at controlH 45)
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
	w = 1750, h = 1250, scale = 0.80,
}

-- ---------------------------------------------------------------------------
--  Card grid (settings layout system, decided 2026-07-04): the page divides
--  into 12 tracks; section cards span EVEN track counts (4/6/8/12) and sit in
--  horizontal BANDS (stack:band). Vertical rhythm quantizes to the 8pt scale.
-- ---------------------------------------------------------------------------
UI.GRID = {
	cols    = 12, -- page tracks (cards span even counts: 4/6/8/12)
	cardGap = 16, -- gutter between two cards in a band AND between field cells (8pt)
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

-- 1px hairline border (4 edges) around frame, gold-at-opacity. Returns the 4 edge
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
--    LG 10 — cards, panels, group boxes, floating popovers/menus/tooltip
--    XL 16 — main window (panel/sidebar/dock) + modal dialogs
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
local ROUND_TEX    = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local ROUND_MARGIN = { [4] = 5, [6] = 7, [8] = 9, [10] = 11, [16] = 17 } -- source px covering the corner (+1px straight buffer)
local ROUND_SUFFIX = { top = "-top", bottom = "-btm", left = "-left", right = "-right" } -- else full
UI.RADIUS = { xs = 4, sm = 6, md = 8, lg = 10, xl = 16 } -- THE scale (see table above)
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
local PILL_MARGIN = { [32] = 17, [28] = 15, [22] = 12, [18] = 10, [4] = 3 } -- cap width (radius + 1px buffer)

local function pillTexture(parent, file, col, layer, h)
	local m = PILL_MARGIN[h]
	local t = markRound(parent:CreateTexture(nil, layer or "BACKGROUND"))
	t:SetTexture(ROUND_TEX .. file .. "-h" .. h)
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
	t:SetTexture(ROUND_TEX .. "circle-" .. size)
	t:SetSize(size, size)
	t:SetVertexColor(col.r, col.g, col.b, col.a or 1)
	return t
end

-- Rounded-square knob (switch): the round-fill 9-slice asset at an explicit
-- size, positioned by the caller (like UI.Circle, but squared with radius r).
-- Lets the switch match the radius scale + the rounded-square checkboxes
-- instead of a pill/circle (Florian 2026-07-05).
function UI.RoundKnob(parent, col, layer, size, r)
	r = r or UI.RADIUS.xs
	local m = ROUND_MARGIN[r]
	local t = markRound(parent:CreateTexture(nil, layer or "ARTWORK"))
	t:SetTexture(ROUND_TEX .. "round-fill-r" .. r)
	t:SetTextureSliceMargins(m, m, m, m)
	t:SetSize(size, size)
	t:SetVertexColor(col.r, col.g, col.b, col.a or 1)
	return t
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
