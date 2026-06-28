local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell Design Tokens
--  1:1 translation of the Lumen design system (tokens/*.css) into Lua/WoW.
--  Source of truth: "WoW Addon Einstellungsseite" prototype (Claude Design).
--  Central, so the Shell + later widget toolkit read consistently from it.
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

UI.C = {
	-- Ink ramp (grounds, dark -> light)
	ink900   = hex("070605"), -- app background
	ink850   = hex("0F0D0B"), -- main panel
	ink800   = hex("110d09"), -- glow center
	ink700   = hex("13100C"), -- inset field (dropdown header, keybind)
	ink650   = hex("15100a"), -- icon-tile shadow
	ink600   = hex("171411"), -- raised card
	ink550   = hex("1B1712"), -- popover / floating
	ink520   = hex("1E1A13"), -- sub-box (lighter than card, for function groups inside a card)
	inkTint  = hex("2c2318"), -- icon-tile gradient top
	sliderTrack = hex("3A3122"), -- unfilled slider track (clearly visible, not "floating")

	-- Gold — the single accent color, in many opacities
	gold500  = hex("D4A34F"), -- core accent: borders, icons, active
	gold400  = hex("E6B863"), -- button hover
	gold300  = hex("E6C883"), -- wordmark / display heading
	gold250  = hex("E8C988"), -- active nav/tab label
	gold200  = hex("F0D89B"), -- link hover
	gold100  = hex("F1E6D3"), -- lightest gold-white

	-- Parchment text (warm neutrals)
	textStrong  = hex("F1E6D3"),
	textHeading = hex("E2D6C0"),
	textBody    = hex("B5AA98"),
	textMuted   = hex("8a8072"),
	textFaint   = hex("7E766A"),
	onGold      = hex("1A1714"), -- ink text on gold fill

	-- Danger — strictly destructive
	danger500 = hex("D66A5C"),
}

-- Gold/danger in standard opacities (borders, washes) — as {r,g,b,a}.
local g = UI.C.gold500
local d = UI.C.danger500
local function goldA(a) return { r = g.r, g = g.g, b = g.b, a = a } end
local function dangerA(a) return { r = d.r, g = d.g, b = d.b, a = a } end
UI.goldA = goldA
UI.dangerA = dangerA

UI.line = {
	faint   = goldA(0.12), -- fine separators (content)
	divider = goldA(0.28), -- structural divider lines header/footer/nav (visible in-game)
	soft   = goldA(0.22), -- soft control borders
	mid    = goldA(0.35), -- standard
	strong = goldA(0.60), -- active / open
	washSoft = goldA(0.07),
	wash     = goldA(0.12),
	dangerLine = dangerA(0.40),
	dangerWash = dangerA(0.12),
}

-- ---------------------------------------------------------------------------
--  Fonts — bundled under Lumen/Fonts/ (Cinzel + Hanken Grotesk, SIL OFL)
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

-- Font warm-up: on a COLD START the FIRST SetFont per custom-TTF path renders empty
-- until the client glyph cache has built the font (after /reload it is still warm from
-- the previous session -> text shows; cold start -> invisible). Here we "touch" each
-- path once on a hidden, rendered FontString -> the cache is warm BEFORE the Shell is
-- ever built.
do
	-- Glyphs the UI actually uses (German labels incl. umlauts/ß + digits + symbols).
	-- ONE persistent, fully transparent FontString per font — NOT :Hide(): a hidden
	-- FontString never renders, so its glyphs would never be rasterized (exactly the
	-- cold-start bug: on /reload the client glyph cache is warm from the previous
	-- session, on a real game start it is cold -> the first SetText, e.g. the primary
	-- "Apply" button in the color picker (hankenBold), measured 0 width and stayed
	-- invisible). Visible (alpha 0), anchored on-screen (off-screen would be culled ->
	-- no rasterization), renders once on the first frame and keeps the cache warm
	-- BEFORE Shell/color picker are ever built.
	-- IMPORTANT: SetFont MUST come before SetText (SetText without a font throws "Font not set").
	local GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÄÖÜäöüß0123456789 %+-#/.,()"
	for _, path in pairs(UI.FONT) do
		local warm = UIParent:CreateFontString(nil, "BACKGROUND")
		warm:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 4, 4)
		warm:SetAlpha(0)
		if pcall(warm.SetFont, warm, path, 16, "") then pcall(warm.SetText, warm, GLYPHS) end
	end
end

-- Roles -> { path, size, flags }. Sizes from typography.css.
UI.ROLE = {
	wordmark = { UI.FONT.cinzelSemi, 30, "" }, -- LUMEN
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
	sectionHead= { UI.FONT.cinzelSemi, 20, "" }, -- SectionDivider / tab heading
	groupTitle = { UI.FONT.cinzelSemi, 16, "" }, -- GroupPanel title / IconTile letter
	sliderCap  = { UI.FONT.cinzelSemi, 16, "" }, -- slider caption
	value      = { UI.FONT.hankenMed,  14, "" }, -- value box
	ends       = { UI.FONT.hankenMed,  14, "" }, -- slider min/max numbers
	selectText = { UI.FONT.hankenMed,  16, "" }, -- dropdown header + rows
	checkLabel = { UI.FONT.hankenMed,  16, "" }, -- checkbox label
	listLabel  = { UI.FONT.hankenMed,  18, "" }, -- list row (role sort list)
	subDivider = { UI.FONT.cinzelSemi, 16, "" }, -- smaller centered sub-heading
	btn        = { UI.FONT.hankenSemi, 16, "" }, -- button label (weight per variant, see Widgets)

	-- Custom Lumen tooltip — own roles so font size/weight can be tuned
	-- independently (Florian adjusts these himself).
	tipTitle = { UI.FONT.hankenSemi, 18, "" }, -- tooltip title / spell name (gold)
	tipBody  = { UI.FONT.hankenReg,  16, "" }, -- tooltip text / spell description
}

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
-- ---------------------------------------------------------------------------
UI.S = {
	s1 = 2, s2 = 6, s3 = 8, s4 = 12, s5 = 14, s6 = 16, s7 = 20, s8 = 24, s9 = 36,
	controlH    = 40,
	cardPad     = 20,
	panelGutter = 36,
	navWidth    = 260,
	scrollBarW  = 4,  -- width of the content scrollbar
	scrollBarGap = 14, -- gap ScrollFrame -> scrollbar (in the gutter)
}
UI.R = {
	panel = 2, control = 8, popover = 9, card = 10, check = 4,
}

-- ---------------------------------------------------------------------------
--  Widget dimensions — ALL dimensions of the widget toolkit, central. Change
--  here, then it propagates everywhere (Shell/Widgets.lua only reads from it,
--  no more magic numbers in the widget code). Keep values on the 4px grid.
-- ---------------------------------------------------------------------------
UI.WIDGET = {
	controlH    = 40, -- dropdown/input height
	buttonH     = 40, -- button height
	fieldGap    = 26, -- vertical gap label -> control below

	-- Checkbox
	checkBox    = 22, -- box edge length
	checkLabelGap = 10,

	-- Field swatch (ColorSwatch field=true): square color chip at dropdown height
	-- (controlH × swatchFieldW) -> sits cleanly in the row, doesn't dominate the column.
	swatchFieldW = 40,

	-- Slider
	sliderH     = 86, -- total height (label + track row + value box)
	sliderTrackH= 18, -- height of the clickable track row
	sliderBarH  = 4,  -- thickness of the bar
	sliderThumb = 14, -- thumb edge length
	sliderCapGap= 30, -- yOffset label -> track row
	sliderEndW  = 28, -- width of the min/max number fields
	sliderEndPad= 10, -- gap number <-> track
	valueBoxW   = 92, -- value box width
	valueBoxH   = 28, -- value box height
	valueBoxGap = 10, -- yOffset track row -> value box

	-- GroupPanel
	groupTitleY = -16, -- yOffset of the title from the top edge
	groupContentY = -48, -- yOffset of the content area

	-- Section divider (centered gold line — now only for SUB-headings inside a
	-- section card; main sections carry the panel header).
	dividerH    = 36, -- height of the divider block
	dividerGap  = 16, -- gap text <-> gold rule

	-- Section panel (concept A: each section = own card with header). Centrally
	-- tunable; stack:section() in Shell.lua only reads from it.
	sectionPad         = 22, -- inner L/R + bottom padding of the card
	sectionHeaderH     = 46, -- height of the header bar (title)
	sectionAfterHeader = 18, -- header bottom edge -> first content row
	sectionGap         = 26, -- gap between two section cards
	sectionHeaderBarW  = 3,  -- width of the gold accent bar on the header left
	sectionTitleX      = 18, -- X indent of the header title

	-- Sub-box (subgroup): lighter function group INSIDE a section card.
	subgroupPad   = 16, -- inner indent of the sub-box (rows to box edge)
	subgroupGap   = 14, -- gap between two sub-boxes / after the last
	subgroupTitleH = 40, -- title area of a TITLED sub-box (label + gap to 1st row)

	-- Hint (muted body-text line)
	hintH       = 40, -- default height of a hint block (1–2 lines)
	subHeadH    = 26, -- left-aligned sub-heading (e.g. aggro-stage blocks)

	-- (The LAYOUT SPACINGS of the screens live centrally & per category in UI.LAYOUT
	-- further below — here in UI.WIDGET only the WIDGET dimensions.)
	sortRowH      = 42, -- height of a row in the role priority list
	sortCardPad   = 6,  -- inner padding of the role priority card
	sortAccentW   = 4,  -- width of the role-colored accent bar on the left

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

	-- Tracking tab: tracked-spell row (icon + name + "Remove") + spell picker.
	-- The picker is the "real typeahead search": W.Select cannot scroll — here
	-- 30–60 spells run filtered in a SCROLLABLE list (search field on top + list).
	trackRowH      = 36, -- height of a tracked-spell row
	trackIcon      = 22, -- icon edge length (tracking list AND picker)
	trackRemoveW   = 104, -- width of the "✕ Remove" button on the right of the row
	spBtnW         = 210, -- width of the "+ Add spell" trigger button
	spW            = 340, -- width of the spell-picker popover
	spPad          = 10,  -- inner padding of the popover
	spSearchH      = 32,  -- height of the search field
	spRowH         = 32,  -- height of a picker list row
	spVisibleRows  = 7,   -- simultaneously visible rows (rest scrolls)
	spScrollW      = 4,   -- width of the picker scrollbar (also used by W.Select)
	spScrollGap    = 6,   -- gap list <-> scrollbar
	selectMaxRows  = 8,   -- W.Select: max. simultaneously visible options (rest scrolls)

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
}

-- ---------------------------------------------------------------------------
--  LAYOUT SPACINGS — CENTRAL & PER CATEGORY. Here Florian tunes the spacings of
--  each section INDIVIDUALLY. `general` = global default values (divider gap,
--  section separation, side/checkbox gaps). Below it one block per category with
--  "after which row how much space". Values in design pixels (4px grid).
--  NOTE: the ELEMENT/row ORDER per section lives in the respective block in
--  Shell/Screens.lua (clearly commented) — to reorder just say so, then I swap
--  the rows.
-- ---------------------------------------------------------------------------
UI.LAYOUT = {
	-- RHYTHM — semantic row spacings. Choose spacing via the RELATIONSHIP of two
	-- rows, not via a guessed number. Principle: a height jump (short control like
	-- checkbox/swatch -> tall one like dropdown/slider) needs more air.
	rhythm = {
		tight      = 14, -- tightly related rows (slider->slider, size/X/Y->color)
		row        = 22, -- standard between two control rows
		afterCheck = 30, -- after checkbox/short control -> tall control (dropdown/slider)
		group      = 32, -- deliberate break between two sub-groups in a card
	},
	general = {
		afterDivider  = 16, -- divider -> first element of the section
		beforeSection = 52, -- section end -> next category (large separation)
		sideGap       = 28, -- control -> checkbox sitting right next to it
		checkRowGap   = 40, -- between two checkboxes in a row
		subHeadToRow  = 8,  -- sub-heading -> its row
	},
	base = {                    -- Base tab: free-standing "Raidframes enabled" toggle
		topToToggle    = 30,    -- tab strip -> checkbox (more space on top)
		toggleToSection = 16,   -- checkbox -> first section card (less below, closer)
	},
	global = {                  -- Global tab (Base = edit mode; Profile = profiles + export/import)
		taH            = 120,   -- height of the export/import textarea
		afterExportBtn = 14,    -- "Generate export code" -> export textarea
	},
	lebensbalken = {
		afterTexHint = 10,  -- texture row -> mouse-wheel/search hint (close below)
		afterTexture = 22,  -- bar texture row -> class color row
		afterClass   = 22,  -- class color row -> "Name in class color" row
		afterNameCC  = 52,  -- "Name in class color" row -> next category
	},
	transparenz = {
		afterColor = 30,    -- background color row (short) -> opacity slider (tall): height jump
		afterAlpha = 52,    -- opacity slider row -> next category
	},
	sort = {
		afterMode = 22,     -- "Sort by" -> priority card
		afterCard = 52,     -- card -> next category
	},
	test = {
		afterMaster = 14,   -- "Test mode" -> test group size
		afterSize   = 14,   -- test group size -> end
	},
	sizeArrange = {         -- Raid/Group: size & arrangement
		afterSliders = 22,  -- width/height/spacing -> alignment
		afterAlign   = 52,  -- alignment -> Text — Name
	},
	auras = {               -- Auras tab (the row spacings come from rhythm above)
		afterIntro = 22,    -- intro hint -> first category card
	},
	tracking = {            -- Tracking tab (whitelist editor)
		introH      = 58,   -- height of the multi-line intro hint
		afterIntro  = 14,   -- intro -> spec row
		afterSpec   = 22,   -- spec row -> first category card
		afterDesc   = 14,   -- category description -> tracked list
		betweenRows = 6,    -- between two tracked spell rows
		emptyH      = 30,   -- height of the "(no spells)" row when the list is empty
		afterList   = 18,   -- list -> action buttons (picker + reset)
	},
	clickcast = {           -- Click-Cast tab (mouse bindings + hovercast)
		topToHead    = 30,  -- tab strip -> master toggle
		afterMaster  = 22,  -- master -> spec dropdown
		afterSpec    = 8,   -- spec dropdown -> active-spec hint
		afterCaption = 18,  -- hint -> "Only helpful spells" checkbox
		afterHelpful = 26,  -- checkbox -> first section card
		introH       = 50,  -- height of the hovercast intro hint
		afterIntro   = 14,  -- intro -> first binding box
		headToRow    = 14,  -- box header (summary + remove) -> row 1
		betweenRows  = 14,  -- row -> next row inside a box
		afterList    = 8,   -- last box -> "+ add" button
		emptyH       = 30,  -- height of the "(no bindings)" row
	},
}

-- Panel dimensions (design 1500×1060). Scaled down to the screen via SetScale.
-- scale 0.80 + height 1060: noticeably larger, content breathes (Florian's wish).
-- Tune here — w/h change the space, scale the overall size incl. font.
UI.PANEL = {
	w = 1500, h = 1060, headerH = 88, footerH = 78, scale = 0.80,
}

-- ---------------------------------------------------------------------------
--  Shared build primitives (Shell chrome + widget toolkit read from it — DRY).
--  Previously file-locals in Shell.lua; hoisted so both can share them.
--  Behavior identical (pure relocation).
-- ---------------------------------------------------------------------------
function UI.SetColor(t, col) t:SetColorTexture(col.r, col.g, col.b, col.a or 1) end

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

-- FontString in a design role.
function UI.FS(parent, role, col, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	UI:SetFont(fs, role, col)
	return fs
end

-- Horizontal 1px fade line (gold fades toward the edge). dir: "out"=strong at the
-- right end (at the heading) | "in"=strong at the left end.
-- INTENTIONALLY made of 3 solid segments, PURELY VIA ANCHORS (no SetGradient, no
-- OnSizeChanged): both need a layout/render pass, which inside the ScrollFrame is
-- deferred for content below the visible area -> lines missing on top/flicker.
-- Solid, anchor-positioned surfaces render immediately (even off-screen) and calm.
-- The two "detail" segments near the heading have a fixed width, the long pale
-- segment fills variably up to the edge.
function UI.GradientLine(parent, dir, strongA, faintA)
	local gc = UI.C.gold500
	strongA, faintA = strongA or 0.45, faintA or 0.0
	local midA  = (strongA + faintA) / 2
	local SEG   = 70 -- fixed width of the two detail segments near the heading
	local f = CreateFrame("Frame", nil, parent)
	PixelUtil.SetHeight(f, 1) -- pixel-snapped: a naive 1px height vanishes under SetScale when scrolling
	local function mk(a)
		local t = f:CreateTexture(nil, "ARTWORK"); PixelUtil.SetHeight(t, 1)
		t:SetColorTexture(gc.r, gc.g, gc.b, a)
		return t
	end
	local strong, mid, faint = mk(strongA), mk(midA), mk(faintA + 0.05)
	if dir == "in" then
		-- Heading at the LEFT end: strong left -> pale toward the right edge.
		strong:SetPoint("LEFT", f, "LEFT", 0, 0); strong:SetWidth(SEG)
		mid:SetPoint("LEFT", strong, "RIGHT", 0, 0); mid:SetWidth(SEG)
		faint:SetPoint("LEFT", mid, "RIGHT", 0, 0); faint:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	else
		-- Heading at the RIGHT end: strong right -> pale toward the left edge.
		strong:SetPoint("RIGHT", f, "RIGHT", 0, 0); strong:SetWidth(SEG)
		mid:SetPoint("RIGHT", strong, "LEFT", 0, 0); mid:SetWidth(SEG)
		faint:SetPoint("RIGHT", mid, "LEFT", 0, 0); faint:SetPoint("LEFT", f, "LEFT", 0, 0)
	end
	return f
end
