local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell Screens (phase 3: real, db-wired pages)
--  One builder per section/tab, registered in ns.Screens["<Section>/<Tab>"].
--  Shell:RenderContent() calls the builder; if there is none, it falls back to
--  the widget gallery. Layout reference: prototype ui_kits/lumen-config/*.jsx.
--
--  Builder signature: function(holder, stack) — `holder` is the content frame,
--  `stack` the layout stacker from Shell:NewStack (place / placeLeft / gap / y).
--  Widgets wire get/set DIRECTLY to the profile (no intermediate store) + trigger
--  a relayout so changes are immediately visible on the frames.
-- ===========================================================================

local UI = ns.UI
local W  = ns.W
local M, C, L = UI.WIDGET, UI.C, UI.LAYOUT
local T = ns.T   -- localization: T("english") -> display in the active language

ns.Screens = ns.Screens or {}

-- ---------------------------------------------------------------------------
--  Selection options (values = profile keys; labels are translated). Build only
--  AFTER the language choice (onLocaleReady), otherwise these would be fixed
--  load-time strings — forward-declared, filled in the builder below.
-- ---------------------------------------------------------------------------
local ALIGN_OPTS, OUTLINE_OPTS, HPTEXT_OPTS, POINT_OPTS, GROW_OPTS
local AURA_FILTER_OPTS, DISPEL_MODE_OPTS, AGGRO_MODE_OPTS, SORT_MODE_OPTS
local TESTSIZE_OPTS, ROLE_LABEL, DISPEL_TYPES

ns.onLocaleReady[#ns.onLocaleReady + 1] = function()
	ALIGN_OPTS = {
		{ value = "vertical",   label = T("Vertical — members stacked") },
		{ value = "horizontal", label = T("Horizontal — members side by side") },
	}
	OUTLINE_OPTS = {
		{ value = "none",    label = T("None") },
		{ value = "outline", label = T("Outline") },
		{ value = "thick",   label = T("Thick outline") },
	}
	HPTEXT_OPTS = {
		{ value = "Keine",   label = T("None") },
		{ value = "Aktuell", label = T("Current") },
		{ value = "Prozent", label = T("Percent") },
	}
	-- 9 WoW anchor points (values are WoW point keys; only labels are translated).
	POINT_OPTS = {
		{ value = "TOPLEFT",     label = T("Top left") },
		{ value = "TOP",         label = T("Top") },
		{ value = "TOPRIGHT",    label = T("Top right") },
		{ value = "LEFT",        label = T("Left") },
		{ value = "CENTER",      label = T("Center") },
		{ value = "RIGHT",       label = T("Right") },
		{ value = "BOTTOMLEFT",  label = T("Bottom left") },
		{ value = "BOTTOM",      label = T("Bottom") },
		{ value = "BOTTOMRIGHT", label = T("Bottom right") },
	}
	-- Auras tab: growth direction (values are profile keys).
	GROW_OPTS = {
		{ value = "RIGHT", label = T("Right") },
		{ value = "LEFT",  label = T("Left") },
		{ value = "UP",    label = T("Up") },
		{ value = "DOWN",  label = T("Down") },
	}
	-- Auras tab: debuff filter mode (only the "debuffs" category).
	AURA_FILTER_OPTS = {
		{ value = "raid",        label = T("Raid-relevant (Blizzard)") },
		{ value = "all",         label = T("All") },
		{ value = "dispellable", label = T("Dispellable only") },
	}
	-- Base tab options.
	DISPEL_MODE_OPTS = {
		{ value = "recolor", label = T("Recolor health bar") },
		{ value = "overlay", label = T("Border + overlay (keeps class color)") },
	}
	-- Values combine mode + text (data model stays split: aggroMode + aggroText).
	-- "overlaytext" = overlay mode WITH text. See aggroStage for the mapping.
	AGGRO_MODE_OPTS = {
		{ value = "border",      label = T("Border only") },
		{ value = "overlay",     label = T("Border + overlay") },
		{ value = "overlaytext", label = T("Border + overlay + text") },
	}
	SORT_MODE_OPTS = {
		{ value = "group", label = T("Group") },
		{ value = "role",  label = T("Role") },
	}
	TESTSIZE_OPTS = {
		{ value = 5,  label = T("5 (party)") },
		{ value = 20, label = T("20 (raid)") },
		{ value = 40, label = T("40") },
	}
	ROLE_LABEL = { TANK = T("Tank"), HEALER = T("Healer"), DAMAGER = T("DPS") }
	DISPEL_TYPES = {
		{ key = "Magic",   label = T("Magic") },
		{ key = "Curse",   label = T("Curse") },
		{ key = "Disease", label = T("Disease") },
		{ key = "Poison",  label = T("Poison") },
	}
end

-- ---------------------------------------------------------------------------
--  Profile access (values live PER CONTEXT in rf().raid resp. rf().party).
-- ---------------------------------------------------------------------------
local function rf() return ns.Lumen.db.profile.raidframes end
local function relayout() if ns.Raidframes then ns.Raidframes:UpdateLayout() end end

local function vget(ctx, key) return function() return (rf()[ctx] or {})[key] end end
local function vset(ctx, key)
	return function(v)
		local t = rf(); t[ctx] = t[ctx] or {}; t[ctx][key] = v; relayout()
	end
end
-- (Per-context color helpers removed: text colors now live SHARED in Base, see tcget/tcset.)

-- Top-level keys (Base tab; live directly under rf(), not in the context).
local function tget(key) return function() return rf()[key] end end
local function tset(key) return function(v) rf()[key] = v; relayout() end end
local function tcget(key) return function() local c = rf()[key] or {}; return c.r or 1, c.g or 1, c.b or 1 end end
local function tcset(key) return function(r, g, b) rf()[key] = { r = r, g = g, b = b }; relayout() end end
-- Dispel colors live nested in rf().dispelColors[<type>].
local function dcget(typ) return function() local c = (rf().dispelColors or {})[typ] or {}; return c.r or 1, c.g or 1, c.b or 1 end end
local function dcset(typ) return function(r, g, b) rf().dispelColors = rf().dispelColors or {}; rf().dispelColors[typ] = { r = r, g = g, b = b }; relayout() end end
-- Percent helpers for alpha sliders (profile holds 0..1, slider shows 0..100).
local function pctget(key) return function() return math.floor((rf()[key] or 0) * 100 + 0.5) end end
local function pctset(key) return function(v) rf()[key] = v / 100; relayout() end end

-- Aura values live in rf().auras[<cat>][key]. Set triggers RefreshAuras() (light
-- + combat-safe; UpdateLayout would abort in combat — like the AceConfig Auras tab).
local function aget(cat, key) return function() return ((rf().auras or {})[cat] or {})[key] end end
local function aset(cat, key)
	return function(v)
		local t = rf(); t.auras = t.auras or {}; t.auras[cat] = t.auras[cat] or {}; t.auras[cat][key] = v
		if ns.Raidframes then ns.Raidframes:RefreshAuras() end
	end
end

-- Expand state of the aura section per context (Feature 1). Default nil = collapsed;
-- the choice is remembered (persisted). Deliberately NOT in the defaults — pure UI
-- state, and default-collapsed == default-nil. ctx = "raid" | "party".
local function auraOpen(ctx) local t = rf().auraEditorOpen; return t and t[ctx] or false end
local function setAuraOpen(ctx, v)
	local t = rf(); t.auraEditorOpen = t.auraEditorOpen or {}; t.auraEditorOpen[ctx] = v
end

-- Defined further below (needs PLACE_OPTS); forward-declared because buildRaid
-- (Raid/Group tabs) builds the per-context aura cards with it.
local auraCat

-- Display labels for Lumen's own texture keys: the VALUE stays the German key
-- (texture/pattern matching in Raidframes.lua relies on it), only the shown label
-- is localized. Built on locale-ready (uses T). Other (LSM/Blizzard) textures keep
-- their own name.
local TEX_LABELS
ns.onLocaleReady[#ns.onLocaleReady + 1] = function()
	TEX_LABELS = {
		["Lumen Schild"]     = T("Lumen Shield"),
		["Lumen Heilabsorb"] = T("Lumen Heal-absorb"),
	}
end

-- Bar textures from Raidframes:TextureValues() -> sorted {value,label} list.
local function texOptsFrom(vals)
	local list = {}
	for k in pairs(vals or {}) do list[#list + 1] = k end
	table.sort(list)
	local opts = {}
	for _, k in ipairs(list) do opts[#opts + 1] = { value = k, label = (TEX_LABELS and TEX_LABELS[k]) or k } end
	return opts
end
local function textureOptions() return texOptsFrom(ns.Raidframes and ns.Raidframes:TextureValues()) end
local function shieldTexOptions() return texOptsFrom(ns.Raidframes and ns.Raidframes:ShieldTextureValues()) end
local function healAbsorbTexOptions() return texOptsFrom(ns.Raidframes and ns.Raidframes:HealAbsorbTextureValues()) end

-- Single dropdown GRID-ALIGNED: cell 1 of a 3-column grid so ALL dropdowns are
-- exactly the same (1 column) width. sideFn(select) may anchor a checkbox to the
-- right of the control (at control height). Returns the select.
local function gridSelect(d, stack, gap, o, sideFn)
	local fieldH = M.controlH + M.fieldGap
	local r, c = W.Row(d, 3, { height = fieldH })
	local sel = W.Select(c[1], o); sel:SetAllPoints(c[1])
	if sideFn then sideFn(sel) end
	stack:place(r, fieldH, gap)
	return sel
end

-- Dims + locks a content frame in the "module disabled" state (same 0.35 look as
-- a greyed-out sub-option). Reusable: Base gates its body frame (master stays
-- operable), Raid/Group/Auras gate the whole screen.
-- The cover button swallows all clicks; mouse-wheel scrolling (on the ScrollFrame) stays.
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
--  RaidScreen — size/arrangement + name/HP text (prototype RaidScreen.jsx).
--  Used for Raid (ctx="raid") AND Group (ctx="party") — identical structure,
--  just a different context in the profile.
-- ---------------------------------------------------------------------------
local function buildRaid(d, stack, ctx)
	local fieldH = M.controlH + M.fieldGap -- height of a select WITH label
	local R = L.rhythm

	-- ===== Size & arrangement ==============================================
	local sSize = stack:section(T("Size & arrangement"))

	local r1, c1 = W.Row(d, 3, { height = M.sliderH })
	W.Slider(c1[1], { label = T("Width"),   min = 40, max = 240, unit = " px", get = vget(ctx, "width"),   set = vset(ctx, "width") }):SetAllPoints(c1[1])
	W.Slider(c1[2], { label = T("Height"),  min = 20, max = 160, unit = " px", get = vget(ctx, "height"),  set = vset(ctx, "height") }):SetAllPoints(c1[2])
	W.Slider(c1[3], { label = T("Spacing"), min = 0,  max = 30,  unit = " px", get = vget(ctx, "spacing"), set = vset(ctx, "spacing") }):SetAllPoints(c1[3])
	sSize:place(r1, M.sliderH, L.sizeArrange.afterSliders)

	-- Alignment — position hint shown as a tooltip (no longer inline).
	gridSelect(d, sSize, L.sizeArrange.afterAlign,
		{ label = T("Alignment"), options = ALIGN_OPTS, get = vget(ctx, "orientation"), set = vset(ctx, "orientation"),
		  tooltip = T("Position: move via \"Unlock frames\" in the Global tab or WoW's Edit Mode. Raid and Group have separate positions.") })
	sSize:close()

	-- ===== Text — name =====================================================
	-- "Show name" is the master (free above the box): off -> box greyed out.
	local sName = stack:section(T("Text — name"))

	local nameDeps = {}
	local function refreshName()
		local on = (rf()[ctx] or {}).showName and true or false
		for _, w in ipairs(nameDeps) do w:SetWidgetEnabled(on) end
	end

	local nameTogRow = CreateFrame("Frame", nil, d)
	local cbName = W.Checkbox(nameTogRow, { label = T("Show name"), get = vget(ctx, "showName"),
		set = function(v) vset(ctx, "showName")(v); refreshName() end })
	cbName:SetPoint("LEFT", nameTogRow, "LEFT", 0, 0)
	sName:place(nameTogRow, M.checkBox, R.afterCheck)

	-- Sub-box (untitled — the master above names it): position / size·X·Y.
	-- Color + outline live SHARED in the Base tab ("Text"). Here only position + size.
	local boxN = sName:subgroup()
	local nr1, nc1 = W.Row(d, 3, { height = fieldH })
	local namePos = W.Select(nc1[1], { label = T("Name position"), options = POINT_OPTS, get = vget(ctx, "namePoint"), set = vset(ctx, "namePoint") })
	namePos:SetAllPoints(nc1[1])
	boxN:place(nr1, fieldH, R.row)

	local nr2, nc2 = W.Row(d, 3, { height = M.sliderH })
	local nameSize = W.Slider(nc2[1], { label = T("Name size"), min = 6, max = 30, get = vget(ctx, "nameSize"), set = vset(ctx, "nameSize") })
	nameSize:SetAllPoints(nc2[1])
	local nameX = W.Slider(nc2[2], { label = T("Name X offset"), min = -40, max = 40, get = vget(ctx, "nameX"), set = vset(ctx, "nameX") })
	nameX:SetAllPoints(nc2[2])
	local nameY = W.Slider(nc2[3], { label = T("Name Y offset"), min = -40, max = 40, get = vget(ctx, "nameY"), set = vset(ctx, "nameY") })
	nameY:SetAllPoints(nc2[3])
	boxN:place(nr2, M.sliderH, R.tight)
	boxN:close()
	sName:close()

	for _, w in ipairs({ namePos, nameSize, nameX, nameY }) do nameDeps[#nameDeps + 1] = w end
	refreshName()

	-- ===== Text — HP display ===============================================
	-- "HP text" is the master (pulled out): "None" greys out the box.
	-- Symmetric to name.
	local sHP = stack:section(T("Text — HP display"))

	local hpDeps = {}
	local function refreshHP()
		local on = (rf()[ctx] or {}).healthTextType ~= "Keine"
		for _, w in ipairs(hpDeps) do w:SetWidgetEnabled(on) end
	end

	-- Master row: HP-text dropdown alone (grid-aligned in column 1).
	local hMaster, hmc = W.Row(d, 3, { height = fieldH })
	local hpType = W.Select(hmc[1], { label = T("HP text"), options = HPTEXT_OPTS,
		tooltip = T("Live, WoW 12.0 shows current HP due to secret values; exact percent in test mode."),
		get = vget(ctx, "healthTextType"), set = function(v) vset(ctx, "healthTextType")(v); refreshHP() end })
	hpType:SetAllPoints(hmc[1])
	sHP:place(hMaster, fieldH, R.afterCheck)

	-- Sub-box (untitled): position / size·X·Y.
	-- Color + outline live SHARED in the Base tab ("Text"). Here only position + size.
	local boxH = sHP:subgroup()
	local hr1, hc1 = W.Row(d, 3, { height = fieldH })
	local hpPos = W.Select(hc1[1], { label = T("HP text position"), options = POINT_OPTS, get = vget(ctx, "healthTextPoint"), set = vset(ctx, "healthTextPoint") })
	hpPos:SetAllPoints(hc1[1])
	boxH:place(hr1, fieldH, R.row)

	local hr2, hc2 = W.Row(d, 3, { height = M.sliderH })
	local hpSize = W.Slider(hc2[1], { label = T("HP text size"), min = 6, max = 30, get = vget(ctx, "healthTextSize"), set = vset(ctx, "healthTextSize") })
	hpSize:SetAllPoints(hc2[1])
	local hpX = W.Slider(hc2[2], { label = T("HP text X offset"), min = -40, max = 40, get = vget(ctx, "healthTextX"), set = vset(ctx, "healthTextX") })
	hpX:SetAllPoints(hc2[2])
	local hpY = W.Slider(hc2[3], { label = T("HP text Y offset"), min = -40, max = 40, get = vget(ctx, "healthTextY"), set = vset(ctx, "healthTextY") })
	hpY:SetAllPoints(hc2[3])
	boxH:place(hr2, M.sliderH, R.tight)
	boxH:close()
	sHP:close()

	for _, w in ipairs({ hpPos, hpSize, hpX, hpY }) do hpDeps[#hpDeps + 1] = w end
	refreshHP()

	-- ===== Aura indicators (Feature 1: per context, collapsible at the bottom) =====
	-- The standalone "Auras" tab is gone — its display settings live here, separated
	-- per context. sfx maps the tab context to the aura field suffix ("Raid"/"Party").
	-- Collapsed by default; the choice is remembered. Toggling re-renders the screen.
	local sfx  = (ctx == "raid") and "Raid" or "Party"
	local open = auraOpen(ctx)
	local auraHead = W.Collapsible(d, { title = T("Aura indicators"), open = open,
		onToggle = function(v) setAuraOpen(ctx, v); ns.Shell:RenderContent(true) end })
	stack:place(auraHead, M.sectionHeaderH, open and R.afterCheck or 0)
	if open then
		local intro = W.Hint(d, T("Aura icons on the frame — set separately for this context. "
			.. "Which spells are tracked is shared and set in the \"Tracking\" tab. "
			.. "Visible in test mode (\"Base\" tab) for preview."), L.tracking.introH)
		stack:place(intro, L.tracking.introH, R.row)
		auraCat(d, stack, "hotsOwn",    T("HoTs"),                  false, sfx)
		auraCat(d, stack, "defensives", T("Defensives & External"), false, sfx)
		auraCat(d, stack, "major",      T("Major CDs"),             false, sfx)
		auraCat(d, stack, "debuffs",    T("Debuffs"),               true,  sfx)
	end

	applyModuleGate(d, rf().enabled) -- module off -> whole Raid/Group screen greyed + locked
end

-- Small arrow button (↑/↓) from two lines (font glyphs ▲▼ are unreliable).
-- Has a disabled state (greyed out, not clickable) -> don't hide it, so the
-- row positions stay stable (no "jumping").
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

-- Role accent color (bar on the left + subtle row wash) for clear separation.
local ROLE_ACCENT = {
	TANK    = { r = 0.40, g = 0.62, b = 0.95 },
	HEALER  = { r = 0.36, g = 0.78, b = 0.46 },
	DAMAGER = { r = 0.90, g = 0.42, b = 0.42 },
}

-- ---------------------------------------------------------------------------
--  BaseScreen — function & look of the module (mirrors the AceConfig Base tab):
--  Enabled, health bar, dispel, aggro, sorting, test. NO layout dimensions
--  (width/height/alignment) — those live in Raid/Group. Value-dependent options
--  are greyed out (convention as in the AceConfig aggro block).
-- ---------------------------------------------------------------------------
local function buildBase(d, stack)
	local fieldH = M.controlH + M.fieldGap
	local R = L.rhythm

	-- ===== Enabled (master — ALWAYS stays operable, outside the gate) ======
	local outerStack = stack
	local body -- forward-declare: the master closure gates this body frame
	stack:gap(L.base.topToToggle) -- more air on top before the master toggle
	local enRow = CreateFrame("Frame", nil, d)
	local cbEnabled = W.Checkbox(enRow, {
		label = T("Raidframes enabled"), get = tget("enabled"),
		set = function(v)
			rf().enabled = v
			if ns.Raidframes then if v then ns.Raidframes:Enable() else ns.Raidframes:Disable() end end
			applyModuleGate(body, v)
		end,
	})
	cbEnabled:SetPoint("LEFT", enRow, "LEFT", 0, 0)
	local cbSolo = W.Checkbox(enRow, { label = T("Show frames even when solo"),
		tooltip = T("Shows the group frame even when you are not in a group."),
		get = tget("showWhenSolo"), set = tset("showWhenSolo") })
	cbSolo:SetPoint("LEFT", cbEnabled, "RIGHT", L.general.checkRowGap, 0)
	stack:place(enRow, M.checkBox, L.base.toggleToSection)

	-- Everything else goes into a gateable body frame: when "off" dimmed + locked
	-- (same 0.35 look as the sub-options). The local names d/stack are redirected
	-- to body/bstack -> the rest of the Base code keeps building unchanged.
	body = CreateFrame("Frame", nil, d)
	local bstack = ns.Shell.NewStack(body)
	d, stack = body, bstack

	-- ===== Health bar ======================================================
	local sBar = stack:section(T("Health bar"))

	-- Row 1: bar texture | shield texture | heal-absorb texture (3 dropdowns, each with row
	-- limit + mouse-wheel preview + search field). Default "Lumen …" = stripe pattern, otherwise LSM/Blizzard.
	local tr1, tc1 = W.Row(d, 3, { height = fieldH })
	W.Select(tc1[1], { label = T("Bar texture"), options = textureOptions(), wheelPreview = true, search = true, get = tget("healthTexture"), set = tset("healthTexture") }):SetAllPoints(tc1[1])
	W.Select(tc1[2], { label = T("Shield texture"), options = shieldTexOptions(), wheelPreview = true, search = true, get = tget("shieldTexture"), set = tset("shieldTexture") }):SetAllPoints(tc1[2])
	W.Select(tc1[3], { label = T("Heal-absorb texture"), options = healAbsorbTexOptions(), wheelPreview = true, search = true, get = tget("healAbsorbTexture"), set = tset("healAbsorbTexture") }):SetAllPoints(tc1[3])
	sBar:place(tr1, fieldH, L.lebensbalken.afterTexHint)
	-- Visible hint (instead of a hover tooltip) for the mouse-wheel preview + search field of the texture dropdowns.
	local texHint = W.Hint(d, T("Scroll the mouse wheel over a texture dropdown to preview textures live. In the open menu, the search box at the top filters."))
	sBar:place(texHint, M.hintH, R.row)

	-- Checkbox offset to vertically align a checkbox to the control band (swatch/select) of a
	-- field row (label on top, control below -> box centered into the lower 40px band).
	local fillOff = -(M.fieldGap + (M.controlH - M.checkBox) / 2)

	-- Row 2: heal prediction + class color (checks) + fill color + background color (swatches).
	local fillDeps = {}
	local function refreshFill()
		local editable = not rf().useClassColor
		for _, w in ipairs(fillDeps) do w:SetWidgetEnabled(editable) end
	end
	local r2, c2 = W.Row(d, 4, { height = fieldH })
	local cbHealPred = W.Checkbox(c2[1], { label = T("Heal prediction"),
		tooltip = T("Incoming healing previewed on the health bar."), get = tget("healPrediction"), set = tset("healPrediction") })
	cbHealPred:SetPoint("TOPLEFT", c2[1], "TOPLEFT", 0, fillOff)
	local cbClass = W.Checkbox(c2[2], { label = T("Class color as fill color"), get = tget("useClassColor"),
		set = function(v) rf().useClassColor = v; relayout(); refreshFill() end })
	cbClass:SetPoint("TOPLEFT", c2[2], "TOPLEFT", 0, fillOff)
	local swFill = W.ColorSwatch(c2[3], { label = T("Fill color"), field = true, get = tcget("fillColor"), set = tcset("fillColor") })
	swFill:SetPoint("TOPLEFT", c2[3], "TOPLEFT", 0, 0)
	local swBg = W.ColorSwatch(c2[4], { label = T("Background color"), field = true, get = tcget("bgColor"), set = tcset("bgColor") })
	swBg:SetPoint("TOPLEFT", c2[4], "TOPLEFT", 0, 0)
	sBar:place(r2, fieldH, R.row)
	fillDeps[1] = swFill; refreshFill()

	-- Sub-box "Transparency": 2×2 opacity sliders (background/health bar · shield/heal-absorb).
	local boxT = sBar:subgroup({ title = T("Transparency") })
	local trA, tcA = W.Row(d, 2, { height = M.sliderH })
	W.Slider(tcA[1], { label = T("Background opacity"), min = 0, max = 100, unit = " %", get = pctget("bgAlpha"), set = pctset("bgAlpha") }):SetAllPoints(tcA[1])
	W.Slider(tcA[2], { label = T("Health bar opacity"), min = 0, max = 100, unit = " %", get = pctget("healthAlpha"), set = pctset("healthAlpha") }):SetAllPoints(tcA[2])
	boxT:place(trA, M.sliderH, R.row)
	local trB, tcB = W.Row(d, 2, { height = M.sliderH })
	W.Slider(tcB[1], { label = T("Shield opacity"), min = 0, max = 100, unit = " %", get = pctget("shieldAlpha"), set = pctset("shieldAlpha") }):SetAllPoints(tcB[1])
	W.Slider(tcB[2], { label = T("Heal-absorb opacity"), min = 0, max = 100, unit = " %", get = pctget("healAbsorbAlpha"), set = pctset("healAbsorbAlpha") }):SetAllPoints(tcB[2])
	boxT:place(trB, M.sliderH, R.tight)
	boxT:close()
	sBar:close()

	-- ===== Text (SHARED: color + outline apply equally to Raid & Group) =====
	local sText = stack:section(T("Text"))
	local nameColDeps = {}
	local function refreshNameCol()
		local on = not rf().nameClassColor
		for _, w in ipairs(nameColDeps) do w:SetWidgetEnabled(on) end
	end
	-- Row 1: name in class color (check) | name outline | HP outline.
	local txR1, txc1 = W.Row(d, 3, { height = fieldH })
	local cbNameCC = W.Checkbox(txc1[1], { label = T("Name in class color"), get = tget("nameClassColor"),
		set = function(v) rf().nameClassColor = v; relayout(); refreshNameCol() end })
	cbNameCC:SetPoint("TOPLEFT", txc1[1], "TOPLEFT", 0, fillOff)
	W.Select(txc1[2], { label = T("Name outline"), options = OUTLINE_OPTS, get = tget("nameOutline"), set = tset("nameOutline") }):SetAllPoints(txc1[2])
	W.Select(txc1[3], { label = T("HP outline"), options = OUTLINE_OPTS, get = tget("healthTextOutline"), set = tset("healthTextOutline") }):SetAllPoints(txc1[3])
	sText:place(txR1, fieldH, R.row)
	-- Row 2: name color | HP text color (field swatches).
	local txR2, txc2 = W.Row(d, 3, { height = fieldH })
	local swName = W.ColorSwatch(txc2[1], { label = T("Name color"), field = true, get = tcget("nameColor"), set = tcset("nameColor") })
	swName:SetPoint("TOPLEFT", txc2[1], "TOPLEFT", 0, 0)
	W.ColorSwatch(txc2[2], { label = T("HP text color"), field = true, get = tcget("healthTextColor"), set = tcset("healthTextColor") }):SetPoint("TOPLEFT", txc2[2], "TOPLEFT", 0, 0)
	sText:place(txR2, fieldH, R.tight)
	sText:close()
	nameColDeps[1] = swName; refreshNameCol()

	-- ===== Dispel display ==================================================
	local sDispel = stack:section(T("Dispel display"))

	local dispelDeps, dispelAlphaW = {}, nil
	local function refreshDispel()
		local on = rf().dispelEnabled and true or false
		for _, w in ipairs(dispelDeps) do w:SetWidgetEnabled(on) end
		if dispelAlphaW then dispelAlphaW:SetWidgetEnabled(on and rf().dispelMode == "overlay") end
	end
	-- Row 1: master + "Show all dispellable" next to it.
	local dRow1 = CreateFrame("Frame", nil, d)
	local cbDispel = W.Checkbox(dRow1, { label = T("Highlight dispellable debuffs (also in combat)"),
		get = tget("dispelEnabled"), set = function(v) rf().dispelEnabled = v; relayout(); refreshDispel() end })
	cbDispel:SetPoint("LEFT", dRow1, "LEFT", 0, 0)
	local cbShowAll = W.Checkbox(dRow1, { label = T("Show all dispellable (not just yours)"),
		get = tget("dispelShowAll"), set = tset("dispelShowAll") })
	cbShowAll:SetPoint("LEFT", cbDispel, "RIGHT", L.general.checkRowGap, 0)
	sDispel:place(dRow1, M.checkBox, R.afterCheck)

	local boxD = sDispel:subgroup() -- sub-box: type colors / display opacity

	-- Row 2: type colors (magic/curse/disease/poison) — before the slider row so
	-- the slider value box below doesn't stick to the colors.
	local dColRow, dcc = W.Row(d, 4, { height = fieldH })
	local dispColW = {}
	for i, t in ipairs(DISPEL_TYPES) do
		local sw = W.ColorSwatch(dcc[i], { label = t.label, field = true, get = dcget(t.key), set = dcset(t.key) })
		sw:SetPoint("TOPLEFT", dcc[i], "TOPLEFT", 0, 0)
		dispColW[i] = sw
	end
	boxD:place(dColRow, fieldH, R.row)

	-- Row 3: display (column 1) + overlay opacity (column 2) in the grid.
	local dr2, dc2 = W.Row(d, 3, { height = M.sliderH })
	local dispMode = W.Select(dc2[1], { label = T("Display"), options = DISPEL_MODE_OPTS,
		get = tget("dispelMode"), set = function(v) tset("dispelMode")(v); refreshDispel() end })
	dispMode:SetAllPoints(dc2[1])
	dispelAlphaW = W.Slider(dc2[2], { label = T("Overlay opacity"), min = 0, max = 100, unit = " %",
		get = pctget("dispelAlpha"), set = pctset("dispelAlpha") })
	dispelAlphaW:SetAllPoints(dc2[2])
	boxD:place(dr2, M.sliderH, R.tight)
	boxD:close()
	sDispel:close()

	for _, w in ipairs({ dispMode, cbShowAll, dispColW[1], dispColW[2], dispColW[3], dispColW[4] }) do
		dispelDeps[#dispelDeps + 1] = w
	end
	refreshDispel()

	-- ===== Aggro warning ===================================================
	local sAggro = stack:section(T("Aggro warning"))

	local aggroAlways = {}                 -- coupled only to aggroEnabled
	local aggroAlphaW
	local aggroTextOpts = {}               -- only active when text is actually shown
	local function refreshAggro()
		local en = rf().aggroEnabled and true or false
		for _, w in ipairs(aggroAlways) do w:SetWidgetEnabled(en) end
		aggroAlphaW:SetWidgetEnabled(en and (rf().aggroModeAggro == "overlay" or rf().aggroModeWarn == "overlay"))
		local textActive = (rf().aggroModeAggro == "overlay" and rf().aggroTextAggro)
			or (rf().aggroModeWarn == "overlay" and rf().aggroTextWarn)
		for _, w in ipairs(aggroTextOpts) do w:SetWidgetEnabled(en and textActive and true or false) end
	end

	local agRow = CreateFrame("Frame", nil, d)
	local cbAggro = W.Checkbox(agRow, { label = T("Show aggro warning (tanks excluded)"),
		get = tget("aggroEnabled"), set = function(v) rf().aggroEnabled = v; relayout(); refreshAggro() end })
	cbAggro:SetPoint("LEFT", agRow, "LEFT", 0, 0)
	local cbAggroInst = W.Checkbox(agRow, { label = T("Dungeon/raid only"),
		tooltip = T("Shows the aggro warning only inside instances (dungeon/raid). Off = everywhere, including solo/open world."),
		get = tget("aggroInstanceOnly"), set = tset("aggroInstanceOnly") })
	cbAggroInst:SetPoint("LEFT", cbAggro, "RIGHT", L.general.checkRowGap, 0)
	aggroAlways[#aggroAlways + 1] = cbAggroInst   -- only operable when aggro warning is on
	sAggro:place(agRow, M.checkBox, R.afterCheck)

	-- One aggro stage (red/yellow) as a titled sub-box: display | color.
	-- The display dropdown combines mode + text (3 options): "Border + overlay +
	-- text" = overlay mode with text. The separate profile fields modeKey + textKey
	-- are still written (data model/render unchanged).
	local function aggroStage(label, colorKey, modeKey, textKey)
		local box = sAggro:subgroup({ title = label })
		local r, c = W.Row(d, 3, { height = fieldH })
		local mode = W.Select(c[1], { label = T("Display"), options = AGGRO_MODE_OPTS,
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
		local sw = W.ColorSwatch(c[2], { label = T("Color"), field = true, get = tcget(colorKey), set = tcset(colorKey) })
		sw:SetPoint("TOPLEFT", c[2], "TOPLEFT", 0, 0)
		box:place(r, fieldH, R.tight)
		box:close()
		aggroAlways[#aggroAlways + 1] = sw
		aggroAlways[#aggroAlways + 1] = mode
	end
	aggroStage(T("Has aggro (red)"),      "aggroColorAggro", "aggroModeAggro", "aggroTextAggro")
	aggroStage(T("Aggro incoming (yellow)"), "aggroColorWarn",  "aggroModeWarn",  "aggroTextWarn")

	-- Shared text display of both stages — own titled sub-box.
	local boxShared = sAggro:subgroup({ title = T("Text (both stages)") })
	-- Row 1: text position | text outline | overlay opacity.
	local ar1, ac1 = W.Row(d, 3, { height = M.sliderH })
	local agPoint = W.Select(ac1[1], { label = T("Text position"), options = POINT_OPTS, get = tget("aggroTextPoint"), set = tset("aggroTextPoint") })
	agPoint:SetAllPoints(ac1[1])
	local agOutline = W.Select(ac1[2], { label = T("Text outline"), options = OUTLINE_OPTS, get = tget("aggroTextOutline"), set = tset("aggroTextOutline") })
	agOutline:SetAllPoints(ac1[2])
	aggroAlphaW = W.Slider(ac1[3], { label = T("Overlay opacity"), min = 0, max = 100, unit = " %",
		get = pctget("aggroFillAlpha"), set = pctset("aggroFillAlpha") })
	aggroAlphaW:SetAllPoints(ac1[3])
	boxShared:place(ar1, M.sliderH, R.row)

	-- Row 2: text size | text X offset | text Y offset.
	local ar2, ac2 = W.Row(d, 3, { height = M.sliderH })
	local agSize = W.Slider(ac2[1], { label = T("Text size"), min = 6, max = 28, get = tget("aggroTextSize"), set = tset("aggroTextSize") })
	agSize:SetAllPoints(ac2[1])
	local agX = W.Slider(ac2[2], { label = T("Text X offset"), min = -60, max = 60, get = tget("aggroTextX"), set = tset("aggroTextX") })
	agX:SetAllPoints(ac2[2])
	local agY = W.Slider(ac2[3], { label = T("Text Y offset"), min = -60, max = 60, get = tget("aggroTextY"), set = tset("aggroTextY") })
	agY:SetAllPoints(ac2[3])
	boxShared:place(ar2, M.sliderH, R.tight)
	boxShared:close()
	sAggro:close()

	for _, w in ipairs({ agPoint, agOutline, agSize, agX, agY }) do aggroTextOpts[#aggroTextOpts + 1] = w end
	refreshAggro()

	-- ===== Sorting =========================================================
	local sSort = stack:section(T("Sorting"))

	-- Row 1: sort by (grid-aligned) + (when "role") "Also in raid" next to it (tooltip).
	gridSelect(d, sSort, L.sort.afterMode,
		{ label = T("Sort by"), options = SORT_MODE_OPTS,
		  get = tget("sortMode"), set = function(v) tset("sortMode")(v); ns.Shell:RenderContent(true) end },
		(rf().sortMode == "role") and function(sel)
			local cbRaid = W.Checkbox(d, { label = T("Also sort by role in raid"),
				tooltip = T("Off: your arrangement is kept in raids. On: role sorting also applies in raids. (Dungeon/party is always sorted.)"),
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
		-- Priority list: card exactly 1 column wide (aligned with "Sort by"),
		-- role-colored rows (accent bar + wash) + ↑/↓ arrows in front (unusable
		-- ones greyed out, no jumping).
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

	-- ===== Test / sample group =============================================
	local sTest = stack:section(T("Test / sample group"))

	local testSizeW
	local function refreshTest() if testSizeW then testSizeW:SetWidgetEnabled(rf().testMode and true or false) end end
	local testRow = CreateFrame("Frame", nil, d)
	local cbTest = W.Checkbox(testRow, { label = T("Test mode — show a sample group (for designing without a real group)"),
		get = tget("testMode"), set = function(v) rf().testMode = v; relayout(); refreshTest() end })
	cbTest:SetPoint("LEFT", testRow, "LEFT", 0, 0)
	sTest:place(testRow, M.checkBox, L.test.afterMaster)

	testSizeW = gridSelect(d, sTest, L.test.afterSize,
		{ label = T("Test group size"), options = TESTSIZE_OPTS, get = tget("testSize"), set = tset("testSize") })
	sTest:close()
	refreshTest()

	-- Hook the body into the outer stack + gate initially (module off -> all grey).
	outerStack:place(body, bstack:height(), 0)
	applyModuleGate(body, rf().enabled)
end

-- ---------------------------------------------------------------------------
--  One aura category as a section card (mirrors auraCatGroup from Options.lua).
--  "Show" is the master: off -> all remaining controls greyed out. "Auto-Fit"
--  additionally greys out the two size sliders. `isDebuff` shows the filter.
-- ---------------------------------------------------------------------------
-- Inside/Outside options (context segment switch): false = icons INSIDE the frame,
-- true = the row is moved fully outside (next to / above / below the frame).
local PLACE_OPTS
ns.onLocaleReady[#ns.onLocaleReady + 1] = function()
	PLACE_OPTS = { { value = false, label = T("Inside") }, { value = true, label = T("Outside") } }
end

-- One aura category card. Since Feature 1 the context is FIXED by the host tab
-- (sfx = "Raid" on the Raid tab, "Party" on the Group tab) — no more in-card
-- switch; ALL display knobs read/write the per-context key (<base> .. sfx).
function auraCat(d, stack, cat, label, isDebuff, sfx)
	local fieldH = M.controlH + M.fieldGap
	local R = L.rhythm
	local s = stack:section(label)

	-- All knobs bind to the host tab's context (sfx) — no in-card switch anymore.
	local function cget(base) return aget(cat, base .. sfx) end
	local function cset(base) return aset(cat, base .. sfx) end

	local deps = {}   -- coupled to "Show" (all controls except the master + size)
	local sizeW       -- size slider (additionally coupled to "Auto-Fit")

	local function refresh()
		local on = cget("enabled")() and true or false
		for _, w in ipairs(deps) do w:SetWidgetEnabled(on) end
		if sizeW then sizeW:SetWidgetEnabled(on and not cget("autoFit")()) end
	end

	-- "Show" (master) — free in the card, ABOVE the sub-boxes.
	local mRow = CreateFrame("Frame", nil, d)
	local cbOn = W.Checkbox(mRow, { label = T("Show"), get = cget("enabled"),
		set = function(v) cset("enabled")(v); refresh() end })
	cbOn:SetPoint("LEFT", mRow, "LEFT", 0, 0)
	s:place(mRow, M.checkBox, R.afterCheck)

	-- ── Sub-box A: amount & behavior ─────────────────────────────────────
	local boxA = s:subgroup({ title = T("Amount & behavior") })
	local a1, ac = W.Row(d, 2, { height = M.sliderH })
	local maxW = W.Slider(ac[1], { label = T("Max. icons"), min = 1, max = 8, get = cget("maxIcons"), set = cset("maxIcons") })
	maxW:SetAllPoints(ac[1])
	local spaceW = W.Slider(ac[2], { label = T("Spacing"), min = 0, max = 20, unit = " px", get = cget("spacing"), set = cset("spacing") })
	spaceW:SetAllPoints(ac[2])
	deps[#deps + 1] = maxW; deps[#deps + 1] = spaceW
	boxA:place(a1, M.sliderH, R.row)

	-- Auto-Fit + cooldown swipe (two checkboxes side by side).
	local a2, ac2 = W.Row(d, 2, { height = M.checkBox })
	local cbFit = W.Checkbox(ac2[1], { label = T("Auto-fit (size from frame height)"), get = cget("autoFit"),
		set = function(v) cset("autoFit")(v); refresh() end })
	cbFit:SetPoint("LEFT", ac2[1], "LEFT", 0, 0)
	local cbSwipe = W.Checkbox(ac2[2], { label = T("Cooldown swipe"), get = cget("showSwipe"), set = cset("showSwipe") })
	cbSwipe:SetPoint("LEFT", ac2[2], "LEFT", 0, 0)
	deps[#deps + 1] = cbFit; deps[#deps + 1] = cbSwipe
	boxA:place(a2, M.checkBox, isDebuff and R.row or R.tight)

	if isDebuff then
		local a3, ac3 = W.Row(d, 2, { height = fieldH })
		local filterW = W.Select(ac3[1], { label = T("Filter"), options = AURA_FILTER_OPTS,
			tooltip = T("Which debuffs are shown. Raid-relevant = Blizzard's default selection."),
			get = cget("filterMode"), set = cset("filterMode") })
		filterW:SetAllPoints(ac3[1])
		deps[#deps + 1] = filterW
		boxA:place(a3, fieldH, R.tight)
	end
	boxA:close()

	-- ── Sub-box B: placement & size ──────────────────────────────────────
	local boxB = s:subgroup({ title = T("Placement & size") })
	-- Row: anchor | growth | inside/outside (all controlH-based -> aligned).
	local b1, bc = W.Row(d, 3, { height = fieldH })
	local anchorW = W.Select(bc[1], { label = T("Position (anchor)"), options = POINT_OPTS, get = cget("anchor"), set = cset("anchor") }); anchorW:SetAllPoints(bc[1])
	local growW   = W.Select(bc[2], { label = T("Growth direction"), options = GROW_OPTS, get = cget("grow"), set = cset("grow") }); growW:SetAllPoints(bc[2])
	local outW    = W.Segment(bc[3], { label = T("Placement"), options = PLACE_OPTS, get = cget("outside"), set = cset("outside") }); outW:SetAllPoints(bc[3])
	deps[#deps + 1] = anchorW; deps[#deps + 1] = growW; deps[#deps + 1] = outW
	boxB:place(b1, fieldH, R.row)

	-- Row: offset X | offset Y | size (all sliders).
	local b2, bc2 = W.Row(d, 3, { height = M.sliderH })
	local offXW = W.Slider(bc2[1], { label = T("Offset X"), min = -80, max = 80, unit = " px", get = cget("offX"), set = cset("offX") }); offXW:SetAllPoints(bc2[1])
	local offYW = W.Slider(bc2[2], { label = T("Offset Y"), min = -80, max = 80, unit = " px", get = cget("offY"), set = cset("offY") }); offYW:SetAllPoints(bc2[2])
	sizeW = W.Slider(bc2[3], { label = T("Size"), min = 8, max = 80, unit = " px", get = cget("size"), set = cset("size") }); sizeW:SetAllPoints(bc2[3])
	deps[#deps + 1] = offXW; deps[#deps + 1] = offYW
	boxB:place(b2, M.sliderH, R.tight)
	boxB:close()

	s:close()
	refresh()
end

-- ---------------------------------------------------------------------------
--  TrackingScreen — whitelist editor (B4): which spells are tracked as aura icons
--  (HoTs + own defensives). Mirrors the AceConfig "Tracking" tab.
--  ALWAYS bound to the ACTIVE spec (talents/spellbook only readable for it;
--  defaults cover other specs). Spell source = ns.ClickCast:GetAuraSpells()
--  (spellbook + chosen talents). Core piece: W.SpellPicker (searchable + scrollable).
-- ---------------------------------------------------------------------------
local TRACK_CATS
ns.onLocaleReady[#ns.onLocaleReady + 1] = function()
	TRACK_CATS = {
		{ typ = "hot", label = T("HoTs"),                desc = T("Your own heal-over-time effects as an icon on the frame.") },
		{ typ = "def", label = T("Defensives & External"), desc = T("Your own defensives. External protection from others is shown automatically anyway.") },
		{ typ = "major", label = T("Major CDs"), desc = T("Your class's big damage and resource cooldowns.") },
	}
end

local function trkSpec() return (ns.ClickCast and ns.ClickCast:CurrentSpecID()) or 0 end

-- One tracked-spell row: icon + name + "Remove" (danger, right).
local function makeTrackRow(parent, e, onRemove)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(M.trackRowH)
	UI.Fill(row, C.ink520)
	UI.Border(row, UI.line.faint, 1, "OVERLAY") -- L here is UI.LAYOUT; gold opacities live in UI.line
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(M.trackIcon, M.trackIcon)
	icon:SetPoint("LEFT", row, "LEFT", 8, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(e.icon or 136243)
	local rm = W.Button(row, { text = T("Remove"), variant = "danger", width = M.trackRemoveW, onClick = onRemove })
	rm:SetHeight(M.trackRowH - 10)
	rm:ClearAllPoints(); rm:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	local name = UI.FS(row, "selectText", C.textStrong)
	name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	name:SetPoint("RIGHT", rm, "LEFT", -10, 0)
	name:SetJustifyH("LEFT"); name:SetWordWrap(false)
	name:SetText(e.name or (T("Spell") .. " " .. tostring(e.id)))
	-- Hover: subtle wash + own Lumen spell tooltip (like the picker list).
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
	local intro = W.Hint(d, T("Which spells are tracked as aura icons — display & position are set per context in the \"Raid\" and \"Group\" tabs. "
		.. "Your active spec is edited automatically (WoW cannot read talents of other specs; their defaults apply automatically once you play them)."))
	stack:place(intro, L.tracking.introH, L.tracking.afterIntro)

	local specRow = CreateFrame("Frame", nil, d)
	specRow:SetHeight(20)
	local specFS = UI.FS(specRow, "label", C.gold250)
	specFS:SetPoint("TOPLEFT", specRow, "TOPLEFT", 0, 0)
	specFS:SetText(T("Active spec:") .. "  " .. ((ns.ClickCast and ns.ClickCast:CurrentSpecName()) or "?"))
	stack:place(specRow, 20, L.tracking.afterSpec)

	for _, cat in ipairs(TRACK_CATS) do
		local s = stack:section(cat.label)

		local desc = W.Hint(d, cat.desc)
		s:place(desc, M.hintH, L.tracking.afterDesc)

		-- Tracked spells as rows (or "(no spells)").
		local entries = (RFm and RFm:WhitelistEntries(spec, cat.typ)) or {}
		if #entries == 0 then
			s:place(W.Hint(d, T("(no spells)")), L.tracking.emptyH, L.tracking.afterList)
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

		-- Action row: spell picker (searchable/scrollable) + "Restore defaults".
		local actionRow = CreateFrame("Frame", nil, d)
		actionRow:SetHeight(M.buttonH)
		local picker = W.SpellPicker(actionRow, {
			text = T("+ Add spell"), width = M.spBtnW,
			fetch = function()
				local out = {}
				local tracked = (RFm and RFm:WhitelistMap(spec)) or {}
				for _, sp in ipairs((ns.ClickCast and ns.ClickCast:GetAuraSpells()) or {}) do
					-- Normalize talent IDs to the real aura ID -> drop already-tracked ones.
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
		local reset = W.Button(actionRow, { text = T("Restore defaults"), variant = "ghost",
			onClick = function()
				W.Confirm({
					title       = T("Restore defaults?"),
					body        = T("This list will be reset to Lumen's curated default for your active spec. Your own entries in this category will be lost."),
					confirmText = T("Reset"),
					cancelText  = T("Cancel"),
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

	applyModuleGate(d, rf().enabled) -- module off -> whole screen greyed + locked
end

-- ===========================================================================
--  Click-Cast screen — mouse bindings ("click on frame") + hovercast (keyboard)
--  in ONE tab, two section cards. Wired against ns.ClickCast (data model + apply
--  stay in the module). Spell selection via W.SpellPicker (real typeahead search),
--  hovercast key via W.KeybindButton. "Out of combat only" now also for the menu
--  (fixes accidental menus in combat — only affects Lumen's frames).
-- ===========================================================================
local function cc() return ns.Lumen.db.profile.clickCast end
local function CCm() return ns.ClickCast end
local function ccApply() if CCm() then CCm():ApplyBindings() end end

local ccSelectedSpec  -- which spec is edited (decoupled from the live spec)

-- Hovercast is P2: the secure key-driver mechanism (key active only on hover,
-- otherwise the normal action bar) no longer releases the key cleanly in 12.0.7 ->
-- an assigned hovercast key blocks the action bar. Until the 12.1.0 rework (possibly
-- a more robust approach) the section is hidden; code + data model stay. ClickCast.lua
-- keeps existing hovercast bindings "asleep" in parallel (applyHover is then a no-op).
local CC_HOVERCAST = false

local CC_MOD_OPTS, CC_ACTION_OPTS
ns.onLocaleReady[#ns.onLocaleReady + 1] = function()
	CC_MOD_OPTS = {
		{ value = "",      label = T("None") },
		{ value = "SHIFT", label = T("Shift") },
		{ value = "CTRL",  label = T("Ctrl") },
		{ value = "ALT",   label = T("Alt") },
	}
	CC_ACTION_OPTS = {
		{ value = "target", label = T("Target") },
		{ value = "menu",   label = T("Menu") },
		{ value = "spell",  label = T("Spell") },
		{ value = "dispel", label = T("Dispel") },
		{ value = "rez",    label = T("Resurrect") },
	}
end
local function ccMouseOpts()
	local opts, m = {}, CCm()
	if m then for _, k in ipairs(m.MOUSE_BUTTON_SORTING) do
		opts[#opts + 1] = { value = k, label = m.MOUSE_BUTTON_VALUES[k] }
	end end
	return opts
end
-- Spec dropdown with icon (FontStrings render |T..|t inline, like the AceConfig tab).
local function ccSpecOpts()
	local opts, m = {}, CCm()
	if m then for _, s in ipairs(m:GetSpecList()) do
		local lbl = (s.icon and ("|T" .. s.icon .. ":14:14:0:0|t  ") or "") .. (s.name or "?")
		opts[#opts + 1] = { value = s.id, label = lbl }
	end end
	return opts
end
-- Spell candidates for the picker (class spellbook, optionally filtered to helpful).
local function ccSpellFetch()
	local out, m = {}, CCm()
	if not m then return out end
	local onlyHelpful = cc().helpfulOnly
	for _, s in ipairs(m:GetClassSpells()) do
		if (not onlyHelpful) or s.friendly then out[#out + 1] = s end
	end
	return out
end

-- One binding box (lighter sub-box with a header "key → action" + remove).
-- s = stacker of the section card; b = binding; isHover = hovercast (keyboard).
local function ccBindingBox(d, s, b, isHover, spec)
	local LC = L.clickcast
	local fieldH = M.controlH + M.fieldGap
	local box = s:subgroup()

	-- Header: ONLY the keycap (combined key/mouse button) + "Remove". Spell name/icon
	-- deliberately NOT here — the picker button below already shows them (else doubled).
	local hd = CreateFrame("Frame", nil, d)
	hd:SetHeight(M.controlH)

	-- Keycap: square (min controlH×controlH), DARKER + stronger gold border +
	-- CENTERED text -> reads as a "key", not a dropdown (lighter, chevron, left-aligned).
	local cap = CreateFrame("Frame", nil, hd)
	cap:SetHeight(M.controlH)
	cap:SetPoint("LEFT", hd, "LEFT", 0, 0)
	UI.Fill(cap, C.ink850)
	UI.Border(cap, UI.line.strong, 1, "OVERLAY")
	local capTxt = UI.FS(cap, "selectText", C.gold300)
	capTxt:SetPoint("CENTER", cap, "CENTER", 0, 0)
	capTxt:SetText((CCm() and CCm():FormatKey(b.key)) or "—")
	cap:SetWidth(math.max(M.controlH, math.ceil(capTxt:GetStringWidth()) + 20))

	local rm = W.Button(hd, { text = T("Remove"), variant = "danger", width = M.trackRemoveW,
		onClick = function()
			local idx
			for i, x in ipairs(CCm():GetBindings(spec)) do if x == b then idx = i; break end end
			if idx then CCm():RemoveBinding(spec, idx) end
			ns.Shell:RenderContent(true)
		end })
	rm:ClearAllPoints(); rm:SetPoint("RIGHT", hd, "RIGHT", 0, 0)
	box:place(hd, M.controlH, LC.headToRow)

	-- Row 1: click = [mouse button | action | modifier]; hover = [key | action | —].
	local r1, c1 = W.Row(d, 3, { height = fieldH })
	if isHover then
		local kb = W.KeybindButton(c1[1], { label = T("Key"),
			format = function(k) return (CCm() and CCm():FormatKey(k)) or k end,
			get = function() return b.key end,
			set = function(v) b.key = v; ccApply(); ns.Shell:RenderContent(true) end })
		kb:SetAllPoints(c1[1])
	else
		local mb = W.Select(c1[1], { label = T("Mouse button"), options = ccMouseOpts(),
			get = function() local _, btn = CCm():KeyParts(b.key); return (btn ~= "" and btn) or "BUTTON1" end,
			set = function(v) local mod = CCm():KeyParts(b.key); b.key = CCm():BuildKey(mod, v); ccApply(); ns.Shell:RenderContent(true) end })
		mb:SetAllPoints(c1[1])
	end
	local act = W.Select(c1[2], { label = T("Action"), options = CC_ACTION_OPTS,
		get = function() return b.type end,
		set = function(v) b.type = v; ccApply(); ns.Shell:RenderContent(true) end })
	act:SetAllPoints(c1[2])
	if not isHover then
		local mod = W.Select(c1[3], { label = T("Modifier"), options = CC_MOD_OPTS,
			get = function() local m = CCm():KeyParts(b.key); return m or "" end,
			set = function(v) local _, btn = CCm():KeyParts(b.key); b.key = CCm():BuildKey(v, (btn ~= "" and btn) or "BUTTON1"); ccApply(); ns.Shell:RenderContent(true) end })
		mod:SetAllPoints(c1[3])
	end
	box:place(r1, fieldH, LC.betweenRows)

	-- Row 2 (only action "Spell"): spell picker (searchable/scrollable).
	if b.type == "spell" then
		local spIcon = b.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID) or nil
		local picker = W.SpellPicker(d, {
			text = b.spell or T("Choose spell …"), icon = spIcon, width = M.spW,
			fetch = ccSpellFetch,
			onPick = function(id)
				b.spellID = id
				b.spell = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or b.spell
				ccApply(); ns.Shell:RenderContent(true)
			end,
		})
		box:placeLeft(picker, M.buttonH, LC.betweenRows)
	end

	-- Row 3: checkboxes. Click: only "Out of combat only" (except action = target).
	-- Hover: "Friendly only"/"Enemy only" (only spell) + "Out of combat only".
	local defs = {}
	if isHover and b.type == "spell" then
		defs[#defs + 1] = { label = T("Friendly only"), tooltip = T("Only act on friendly units."),
			get = function() return b.hoverFriendly end, set = function(v) b.hoverFriendly = v; ccApply() end }
		defs[#defs + 1] = { label = T("Enemy only"), tooltip = T("Only act on enemy units."),
			get = function() return b.hoverEnemy end, set = function(v) b.hoverEnemy = v; ccApply() end }
	end
	if b.type ~= "target" then
		defs[#defs + 1] = { label = T("Out of combat only"),
			tooltip = (b.type == "menu") and T("Prevents accidental menus in combat — only affects Lumen's frames.") or T("Only trigger out of combat."),
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

	-- Master (free above everything) — like "Raidframes enabled".
	local outerStack = stack
	local body
	stack:gap(LC.topToHead)
	local mRow = CreateFrame("Frame", nil, d)
	local cbMaster = W.Checkbox(mRow, { label = T("Click-cast enabled"),
		tooltip = T("Takes over clicks on the raid frame buttons. Off = WoW default (left = target, right = menu)."),
		get = function() return cc().enabled end,
		set = function(v) cc().enabled = v; ccApply(); applyModuleGate(body, v) end })
	cbMaster:SetPoint("LEFT", mRow, "LEFT", 0, 0)
	stack:place(mRow, M.checkBox, LC.afterMaster)

	-- Everything else into a gateable body frame (when "off" dimmed + locked).
	body = CreateFrame("Frame", nil, d)
	local bstack = ns.Shell.NewStack(body)
	d, stack = body, bstack

	-- Spec selection (decoupled from the live spec) — grid-aligned in column 1.
	local sr, sc = W.Row(d, 3, { height = M.controlH + M.fieldGap })
	W.Select(sc[1], { label = T("Spec (edit)"), options = ccSpecOpts(), placeholder = T("No spec"),
		tooltip = T("Which spec you edit here. In game, the bindings of your active spec apply automatically."),
		get = function() return ccSelectedSpec end,
		set = function(v) ccSelectedSpec = v; ns.Shell:RenderContent(true) end }):SetAllPoints(sc[1])
	stack:place(sr, M.controlH + M.fieldGap, LC.afterSpec)

	local specHint = W.Hint(d, T("Active spec in game:") .. "  " .. ((m and m:CurrentSpecName()) or "?")
		.. "  —  " .. T("the bindings of your active spec apply automatically."), 22)
	stack:place(specHint, 22, LC.afterCaption)

	local hRow = CreateFrame("Frame", nil, d)
	hRow:SetHeight(M.checkBox)
	local cbHelpful = W.Checkbox(hRow, { label = T("Show only helpful spells for selection"),
		tooltip = T("Limits the spell list to spells you can cast on yourself/allies. Off = all spells."),
		get = function() return cc().helpfulOnly end, set = function(v) cc().helpfulOnly = v end })
	cbHelpful:SetPoint("LEFT", hRow, "LEFT", 0, 0)
	stack:place(hRow, M.checkBox, LC.afterHelpful)

	local bindings = (m and m:GetBindings(spec)) or {}

	-- ===== Click on frame ==================================================
	local sClick = stack:section(T("Click on frame"))
	local anyClick = false
	for _, b in ipairs(bindings) do
		if not b.hovercast then anyClick = true; ccBindingBox(d, sClick, b, false, spec) end
	end
	if not anyClick then
		sClick:place(W.Hint(d, T("(no bindings)")), LC.emptyH, LC.afterList)
	end
	local addClick = W.Button(d, { text = T("+ Add click binding"), variant = "ghost",
		onClick = function()
			if m then m:AddBinding(spec, { key = "BUTTON3", type = "spell" }) end
			ns.Shell:RenderContent(true)
		end })
	sClick:placeLeft(addClick, M.buttonH, 0)
	sClick:close()

	-- ===== Hovercast (mouseover) — P2, hidden until 12.1.0 (see CC_HOVERCAST) =====
	if CC_HOVERCAST then
		local sHover = stack:section(T("Hovercast (mouseover)"))
		local intro = W.Hint(d, T("Press a key while the mouse hovers over a unit — the action goes to "
			.. "the hovered unit, without a click. The key only works while hovering; otherwise it does its normal thing."), LC.introH)
		sHover:place(intro, LC.introH, LC.afterIntro)
		local anyHover = false
		for _, b in ipairs(bindings) do
			if b.hovercast then anyHover = true; ccBindingBox(d, sHover, b, true, spec) end
		end
		if not anyHover then
			sHover:place(W.Hint(d, T("(no bindings)")), LC.emptyH, LC.afterList)
		end
		local addHover = W.Button(d, { text = T("+ Add hovercast key"), variant = "ghost",
			onClick = function()
				if m then m:AddBinding(spec, { hovercast = true, type = "spell", hoverFriendly = true }) end
				ns.Shell:RenderContent(true)
			end })
		sHover:placeLeft(addHover, M.buttonH, 0)
		sHover:close()
	end

	outerStack:place(body, bstack:height(), 0)
	applyModuleGate(body, cc().enabled) -- Click-Cast off -> everything below the master greyed + locked
end

-- ===========================================================================
--  Global screens — suite-wide settings (mirrors the AceConfig Global node).
--  Base = move/edit mode; Profile = profile management (AceDB)
--  + sharing (export/import, granular per module, via ns.Share).
-- ===========================================================================

-- Global/Base: language, "Unlock frames" (Edit Mode) + "Reset positions".
local function buildGlobalBase(d, stack)
	local R = L.rhythm
	local fieldH = M.controlH + M.fieldGap

	stack:gap(L.base.topToToggle)
	local intro = W.Hint(d, T("Suite-wide settings. Profiles, export and import of your setup are in the \"Profile\" tab."))
	stack:place(intro, M.hintH, R.row)

	-- ===== Language ========================================================
	local sLang = stack:section(T("Language"))
	local langOpts = {
		{ value = "auto", label = T("Automatic (system language)") },
		{ value = "enUS", label = "English" },
		{ value = "deDE", label = "Deutsch" },
	}
	local lr, lc = W.Row(d, 3, { height = fieldH })
	W.Select(lc[1], { label = T("Interface language"), options = langOpts,
		tooltip = T("Language of Lumen's interface. \"Automatic\" follows your WoW client language. A reload is required to apply."),
		get = function() return ns.Lumen.db.global.language or "auto" end,
		set = function(v)
			ns.Lumen.db.global.language = v
			W.Confirm({
				title = T("Reload needed"),
				body = T("The interface language is applied after a UI reload."),
				confirmText = T("Reload now"), cancelText = T("Later"),
				onConfirm = function() ReloadUI() end,
			})
		end }):SetAllPoints(lc[1])
	sLang:place(lr, fieldH, R.tight)
	sLang:close()

	local s = stack:section(T("Move (Edit Mode)"))

	local togRow = CreateFrame("Frame", nil, d)
	local cbEdit = W.Checkbox(togRow, { label = T("Unlock frames — shows all movable Lumen elements"),
		get = function() return ns.EditMode and ns.EditMode:IsActive() end,
		set = function(v) if ns.EditMode then ns.EditMode:Toggle(v) end end })
	cbEdit:SetPoint("LEFT", togRow, "LEFT", 0, 0)
	s:place(togRow, M.checkBox, R.afterCheck)

	local resetBtn = W.Button(d, { text = T("Reset positions"), variant = "ghost",
		onClick = function()
			W.Confirm({
				title = T("Reset positions?"),
				body = T("Resets the frame positions (raid and group) to their default values."),
				confirmText = T("Reset"), cancelText = T("Cancel"),
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

	local hint = W.Hint(d, T("Also works through WoW's own Edit Mode: Lumen frames become movable there too."))
	s:place(hint, M.hintH, R.tight)
	s:close()
end

-- Global/Profile: transient state (file-local -> survives a RenderContent rebuild).
-- Module/layout selection lives in the import popup (W.ImportDialog) itself, not here.
local shareExport    = ""    -- last generated export code
local shareImportRaw = ""    -- pasted import text
local importErr      = nil   -- error text from the last "Import" (or nil)

local function buildGlobalProfile(d, stack)
	local db = ns.Lumen.db
	local R = L.rhythm
	local G = L.global
	local fieldH = M.controlH + M.fieldGap

	stack:gap(L.base.topToToggle)

	-- Profile names as a {value,label} list (optionally excluding the active profile).
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

	-- ===== Profile =========================================================
	local s = stack:section(T("Profile"))

	-- Row 1: current profile | copy from | delete.
	local r1, c1 = W.Row(d, 3, { height = fieldH })
	W.Select(c1[1], { label = T("Current profile"), options = profileOpts(false),
		get = function() return db:GetCurrentProfile() end,
		set = function(v) db:SetProfile(v); ns.Shell:RenderContent(true) end }):SetAllPoints(c1[1])
	W.Select(c1[2], { label = T("Copy from"), options = profileOpts(true), placeholder = T("Choose profile …"),
		tooltip = T("Merges the settings of another profile into your current one."),
		get = function() return nil end,
		set = function(v)
			W.Confirm({
				title = T("Copy profile?"),
				body = T("The settings from \"%s\" will be merged into your current profile and overwrite it."):format(v),
				confirmText = T("Copy"), cancelText = T("Cancel"),
				onConfirm = function() db:CopyProfile(v); ns.Shell:RenderContent(true) end,
				onCancel = function() ns.Shell:RenderContent(true) end,
			})
		end }):SetAllPoints(c1[2])
	W.Select(c1[3], { label = T("Delete"), options = profileOpts(true), placeholder = T("Choose profile …"),
		tooltip = T("Deletes another profile permanently (not the active one)."),
		get = function() return nil end,
		set = function(v)
			W.Confirm({
				title = T("Delete profile?"),
				body = T("The profile \"%s\" will be deleted permanently. This cannot be undone."):format(v),
				confirmText = T("Delete"), cancelText = T("Cancel"),
				onConfirm = function() db:DeleteProfile(v); ns.Shell:RenderContent(true) end,
				onCancel = function() ns.Shell:RenderContent(true) end,
			})
		end }):SetAllPoints(c1[3])
	s:place(r1, fieldH, R.row)

	-- Row 2: new profile (input) + create + reset (right).
	local newRow = CreateFrame("Frame", nil, d)
	newRow:SetHeight(fieldH)
	local resetBtn = W.Button(newRow, { text = T("Reset"), variant = "danger",
		onClick = function()
			W.Confirm({
				title = T("Reset profile?"),
				body = T("Resets the current profile (\"%s\") to Lumen's default values."):format(db:GetCurrentProfile()),
				confirmText = T("Reset"), cancelText = T("Cancel"),
				onConfirm = function() db:ResetProfile(); ns.Shell:RenderContent(true) end,
			})
		end })
	resetBtn:ClearAllPoints(); resetBtn:SetPoint("BOTTOMRIGHT", newRow, "BOTTOMRIGHT", 0, 0)
	local input
	local createBtn = W.Button(newRow, { text = T("Create"), variant = "primary",
		onClick = function()
			local name = input and (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
			if name ~= "" then db:SetProfile(name); ns.Shell:RenderContent(true) end
		end })
	createBtn:ClearAllPoints(); createBtn:SetPoint("BOTTOMRIGHT", resetBtn, "BOTTOMLEFT", -12, 0)
	input = W.TextInput(newRow, { label = T("New profile"), placeholder = T("Enter name …"),
		onEnter = function(v)
			local name = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if name ~= "" then db:SetProfile(name); ns.Shell:RenderContent(true) end
		end })
	input:ClearAllPoints()
	input:SetPoint("TOPLEFT", newRow, "TOPLEFT", 0, 0)
	input:SetPoint("BOTTOMRIGHT", createBtn, "BOTTOMLEFT", -16, 0)
	s:place(newRow, fieldH, R.tight)
	s:close()

	-- ===== Share — export / import =========================================
	local s2 = stack:section(T("Share — export / import"))
	local hint = W.Hint(d, T("Export your complete Lumen setup as a code, or take someone else's code — granular per module."))
	s2:place(hint, M.hintH, R.row)

	-- Export
	local boxE = s2:subgroup({ title = T("Export") })
	local genBtn = W.Button(d, { text = T("Generate export code"), variant = "ghost",
		onClick = function()
			shareExport = (ns.Share and ns.Share:Export()) or ""
			ns.Shell:RenderContent(true)
		end })
	boxE:placeLeft(genBtn, M.buttonH, G.afterExportBtn)
	local expTA = W.Textarea(d, { height = G.taH, readOnly = true,
		placeholder = T("No code yet — click \"Generate export code\", then select here (Ctrl+A) and copy (Ctrl+C)."),
		get = function() return shareExport end })
	boxE:place(expTA, G.taH, R.tight)
	boxE:close()

	-- Import profile: paste code -> "Import" (bottom right) opens the popup
	-- (module/layout selection + "Create profile"/"Overwrite current").
	local function openImportDialog(payload)
		local mods = {}
		for _, mod in ipairs(ns.Share:GetModules()) do
			if payload.modules[mod.key] then mods[#mods + 1] = mod end
		end
		local hasLayout = payload.layout and next(payload.layout) ~= nil
		W.ImportDialog({
			modules = mods, hasLayout = hasLayout,
			onCreate = function(name, sel, withLayout)
				db:SetProfile(name) -- create a fresh profile + switch into it, then merge the selection
				local ok = ns.Share and ns.Share:Import(payload, sel, withLayout)
				if ok and ns.Lumen then ns.Lumen:Print(T("Profile \"%s\" created and imported."):format(name)) end
				shareImportRaw, importErr = "", nil
				ns.Shell:RenderContent(true)
			end,
			onOverwrite = function(sel, withLayout)
				local ok = ns.Share and ns.Share:Import(payload, sel, withLayout)
				if ok and ns.Lumen then ns.Lumen:Print(T("Import merged into the current profile.")) end
				shareImportRaw, importErr = "", nil
				ns.Shell:RenderContent(true)
			end,
		})
	end

	local boxI = s2:subgroup({ title = T("Import profile") })
	local impTA = W.Textarea(d, { height = G.taH, placeholder = T("Paste profile code here (Ctrl+V) …"),
		get = function() return shareImportRaw end,
		onChange = function(t) shareImportRaw = t end })
	boxI:place(impTA, G.taH, importErr and R.tight or R.row)

	if importErr then
		boxI:place(W.Hint(d, "|cffD66A5C" .. T("Invalid code: %s — please paste the complete code."):format(importErr) .. "|r"), M.hintH, R.row)
	end

	-- "Import" button at the bottom right of the box (own row, right-aligned).
	local btnRow = CreateFrame("Frame", nil, d)
	btnRow:SetHeight(M.buttonH)
	local importBtn = W.Button(btnRow, { text = T("Import"), variant = "primary",
		onClick = function()
			local raw = shareImportRaw and shareImportRaw:gsub("%s+", "") or ""
			if not ns.Share or raw == "" then importErr = T("empty"); ns.Shell:RenderContent(true); return end
			local p, err = ns.Share:Decode(shareImportRaw)
			if not p then importErr = err or T("invalid"); ns.Shell:RenderContent(true); return end
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
ns.Screens["Raidframes/Tracking"] = buildTracking
