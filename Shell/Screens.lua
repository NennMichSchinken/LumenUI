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
local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"

ns.Screens = ns.Screens or {}

-- ---------------------------------------------------------------------------
--  Selection options (values = profile keys; labels are translated). Build only
--  AFTER the language choice (onLocaleReady), otherwise these would be fixed
--  load-time strings — forward-declared, filled in the builder below.
-- ---------------------------------------------------------------------------
local ALIGN_OPTS, HPTEXT_SEG_OPTS, POINT_OPTS, GROW_OPTS
local AURA_FILTER_OPTS, SORT_MODE_OPTS
local ROLE_LABEL, DISPEL_TYPES
local OUTLINE_SEG_OPTS, DISPEL_SEG_OPTS, AGGRO_SEG_OPTS

ns.onLocaleReady[#ns.onLocaleReady + 1] = function()
	ALIGN_OPTS = {
		{ value = "vertical",   label = T("Vertical — members stacked") },
		{ value = "horizontal", label = T("Horizontal — members side by side") },
	}
	-- HP display mode as a 2-way segment; "off" ("Keine") lives on the card's
	-- header master toggle instead (tab migration feedback 2026-07-05).
	HPTEXT_SEG_OPTS = {
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
	SORT_MODE_OPTS = {
		{ value = "group", label = T("Group") },
		{ value = "role",  label = T("Role") },
	}
	ROLE_LABEL = { TANK = T("Tank"), HEALER = T("Healer"), DAMAGER = T("DPS") }
	DISPEL_TYPES = {
		{ key = "Magic",   label = T("Magic") },
		{ key = "Curse",   label = T("Curse") },
		{ key = "Disease", label = T("Disease") },
		{ key = "Poison",  label = T("Poison") },
	}
	-- Card grid (Base tab): segments show all options at once, so the labels
	-- must be SHORT — same profile values as the dropdown lists above.
	OUTLINE_SEG_OPTS = {
		{ value = "none",    label = T("None") },
		{ value = "shadow",  label = T("Shadow") },
		{ value = "outline", label = T("Thin") },
		{ value = "thick",   label = T("Thick") },
	}
	DISPEL_SEG_OPTS = {
		{ value = "recolor", label = T("Recolor") },
		{ value = "overlay", label = T("Overlay") },
	}
	AGGRO_SEG_OPTS = {
		{ value = "border",      label = T("Border") },
		{ value = "overlay",     label = T("+ Overlay") },
		{ value = "overlaytext", label = T("+ Text") },
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

-- ---------------------------------------------------------------------------
--  Live preview in the Shell's satellite dock (right of / below the panel).
--  The band chrome is generic (W.PreviewBand); the raidframes module fills it
--  with fake frames at true on-screen size and refreshes it from UpdateLayout/
--  RefreshAuras; the dock window itself (position, drag, snap) is Shell infra.
--  Eye state + the Raid sample size persist in the profile (previewEyes/
--  previewSize; deliberately not part of the defaults — auraEditorOpen pattern).
-- ---------------------------------------------------------------------------
local function previewEyes()
	local t = rf()
	if not t.previewEyes then t.previewEyes = { auras = true, shields = true, text = true } end
	return t.previewEyes
end
local function previewRefresh()
	if ns.Raidframes then ns.Raidframes:RefreshShellPreview() end
end
-- Open state lives in the SHELL (sidebar "Open preview" button = the single
-- toggle, v3; session-only — the shell always starts with the preview closed).

ns.ScreenPreviews = ns.ScreenPreviews or {}
local function previewDock(spec)
	return function(holder)
		local band = W.PreviewBand(holder, {
			eyes = previewEyes,
			onEye = previewRefresh,
			onLayout = function(side, w, h) ns.Shell:SetDockLayout(side, w, h) end,
			onChrome = function(v) ns.Shell:SetDockChrome(v) end,
			onResetPos = function() ns.Shell:ResetDockPosition() end,
			-- Open state (session-only, shared across the three tabs; the band's
			-- collapse chevron just closes the window via the Shell).
			open = {
				get = function() return ns.Shell:IsPreviewOpen() end,
				set = function(v) ns.Shell:SetPreviewOpen(v) end,
			},
			-- Base tab: Raid/Group switch — Base settings (aggro, dispel,
			-- colors) are judged on the real context layout of choice.
			ctx = spec.baseSwitch and {
				values = {
					{ v = "party", label = T("Group") },
					{ v = "raid",  label = T("Raid") },
				},
				get = function() return rf().previewBaseCtx or "party" end,
				set = function(v) rf().previewBaseCtx = v; previewRefresh() end,
			} or nil,
			sizes = spec.sizes and {
				values = { 5, 10, 20, 25 },
				-- Clamp: profiles from the 5/10/20/40 era may still hold 40.
				get = function() return math.min(rf().previewSize or 5, 25) end,
				set = function(v) rf().previewSize = v; previewRefresh() end,
			} or nil,
		})
		if ns.Raidframes then ns.Raidframes:AttachShellPreview(band, spec) end
		holder._onShow = previewRefresh
	end
end
ns.ScreenPreviews["Raidframes/Base"]  = previewDock({ kind = "ctx", baseSwitch = true })
ns.ScreenPreviews["Raidframes/Raid"]  = previewDock({ kind = "ctx", ctx = "raid", sizes = true })
ns.ScreenPreviews["Raidframes/Group"] = previewDock({ kind = "ctx", ctx = "party" })

-- Expand state of the aura/icon sections per context — SESSION-ONLY and
-- auto-collapsed on navigation (Florian 2026-07-04: a section left open made
-- the page long and buried the ones below on the next visit; pages now always
-- start short and predictable). ctx = "raid" | "party".
local auraOpenState, iconOpenState = {}, {}
local function auraOpen(ctx) return auraOpenState[ctx] or false end
local function setAuraOpen(ctx, v) auraOpenState[ctx] = v end
local function iconOpen(ctx) return iconOpenState[ctx] or false end
local function setIconOpen(ctx, v) iconOpenState[ctx] = v end
-- "More options" disclosure per aura category card ([ctx][cat] = true) —
-- same session-only rule as the collapsibles above.
local auraAdvState = {}

-- Base tab (card grid): "Advanced" disclosures per card (text/dispel/aggro +
-- the Sorting card's role-priority list) — same session-only rule as the aura
-- sections above: navigating away resets to the calm default state.
local baseAdvState = {}

-- Called by the Shell when the MAIN SECTION changes (NOT on tab switches within
-- a section). Open disclosures therefore persist while you move between a
-- module's tabs (e.g. check Tracking, jump back to Auras) and only reset to the
-- calm collapsed default once you leave the module entirely (Florian 2026-07-15).
-- Returns true if any state was cleared (so the Shell rebuilds the screens).
function ns.SectionLeft(section)
	if section ~= "Raidframes" then return false end
	local had = next(baseAdvState) or next(auraAdvState)
		or next(auraOpenState) or next(iconOpenState)
	baseAdvState = {}
	auraAdvState, auraOpenState, iconOpenState = {}, {}, {}
	return had ~= nil
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

-- ---------------------------------------------------------------------------
--  Stacked-row standard helpers (design bible §8): every COMPACT option is ONE
--  full-width W.OptionRow (hairline, label left, control right, uniform
--  M.optionRowH); FIELD controls (dropdown / slider box / segment) sit in
--  W.FieldRow cells at the addon-wide unit width. These three wrappers build
--  the compact rows.
-- ---------------------------------------------------------------------------
local function switchRow(d, label, o)
	local row = W.OptionRow(d, label)
	return row:Attach(W.Switch(row, { small = true, get = o.get, set = o.set, tooltip = o.tooltip }))
end
local function checkRow(d, label, o)
	local row = W.OptionRow(d, label)
	return row:Attach(W.Checkbox(row, { tooltipTitle = label, get = o.get, set = o.set, tooltip = o.tooltip }))
end
local function colorRow(d, label, get, set)
	local row = W.OptionRow(d, label)
	return row:Attach(W.ColorSwatch(row, { chip = M.switchSmallH, get = get, set = set }))
end
-- Sub-heading inside a card (stage/section separator — aggro stages, merged
-- scale card): muted label with the same TOP hairline as option rows (line
-- rule: always above). Thickness pixel-snapped, position plain (UI.Border rule).
local function subHeadRow(d, label)
	local head = CreateFrame("Frame", nil, d)
	local hline = head:CreateTexture(nil, "ARTWORK")
	UI.SetColor(hline, UI.line.faint)
	hline:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
	hline:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, 0)
	local function snapH() PixelUtil.SetHeight(hline, 1) end
	snapH()
	C_Timer.After(0, snapH)
	head:HookScript("OnSizeChanged", snapH)
	head:HookScript("OnShow", snapH)
	local fs = UI.FS(head, "checkLabel", C.textMuted)
	fs:SetPoint("LEFT", head, "LEFT", 0, 0)
	fs:SetText(label)
	return head
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

-- Boxed compact slider (v3 mockup): inset box per slider so slider groups read
-- as one unit (design rule: a slider on a card ALWAYS sits in a box). Shared
-- by the Base and Raid/Group builders.
local function sliderBox(cell, o2)
	local box = CreateFrame("Frame", nil, cell)
	box:SetAllPoints(cell)
	UI.RoundFill(box, UI.P.inset, nil, nil, UI.ROUND_R_CTRL) -- A1: one step darker than the card (sunken, not raised)
	UI.RoundBorder(box, UI.line.faint, "OVERLAY", nil, UI.ROUND_R_CTRL)
	o2.compact, o2.capGap = true, M.sliderBoxCapGap
	local s = W.Slider(box, o2)
	s:SetPoint("TOPLEFT", box, "TOPLEFT", M.sliderBoxPadX, -M.sliderBoxPadY)
	s:SetPoint("TOPRIGHT", box, "TOPRIGHT", -M.sliderBoxPadX, -M.sliderBoxPadY)
	return s
end

-- ---------------------------------------------------------------------------
--  RaidScreen — size/arrangement + name/HP text on the card grid (like Base).
--  Used for Raid (ctx="raid") AND Group (ctx="party") — identical structure,
--  just a different context in the profile. Same options as before, only the
--  layout anatomy changed (tab migration 2026-07-05).
-- ---------------------------------------------------------------------------
local function buildRaid(d, stack, ctx)
	local fieldH = M.controlH + M.fieldGap -- height of a select WITH label
	local R = L.rhythm

	-- ===== Size & arrangement (12-card with exactly ONE field row) ==========
	-- Full width is fine here BECAUSE there are no stacked rows: four unit
	-- fields fill the top band side by side (a lone 6-card left the upper
	-- right corner empty — Florian 2026-07-11). Alignment's position hint is
	-- a tooltip (no longer inline).
	local sSize = stack:section(T("Size & arrangement"))
	local r1, c1 = W.FieldRow(d, d, 4, { height = M.sliderBoxH })
	sliderBox(c1[1], { label = T("Width"),   min = 40, max = 240, unit = " px", get = vget(ctx, "width"),   set = vset(ctx, "width") })
	sliderBox(c1[2], { label = T("Height"),  min = 20, max = 160, unit = " px", get = vget(ctx, "height"),  set = vset(ctx, "height") })
	sliderBox(c1[3], { label = T("Spacing"), min = 0,  max = 30,  unit = " px", get = vget(ctx, "spacing"), set = vset(ctx, "spacing") })
	W.Select(c1[4], { label = T("Alignment"), options = ALIGN_OPTS, get = vget(ctx, "orientation"), set = vset(ctx, "orientation"),
		tooltip = T("Position: move via the Edit Mode button (sidebar) or WoW's Edit Mode. Raid and Group have separate positions.") }):SetAllPoints(c1[4])
	sSize:place(r1, M.sliderBoxH, R.tight)
	sSize:close()

	-- ===== Band: Text — name (6) + Text — HP display (6) ===================
	-- Color + outline live SHARED in the Base tab ("Text") — here only
	-- position + size per context. Both cards carry the SAME row anatomy
	-- (position+size, then X/Y) so the sliders line up across the band;
	-- "Show" = header master toggle on BOTH cards. The HP toggle maps onto
	-- healthTextType ("Keine" = off); Current/Percent is a segment in the
	-- card's extra bottom row (shared rows first, card-specific extras last).
	local nameDeps, hpDeps = {}, {}
	local refreshName, refreshHP
	-- Last non-off mode; restored when the HP header toggle switches back on.
	local hpMode = (rf()[ctx] or {}).healthTextType
	if hpMode == nil or hpMode == "Keine" then hpMode = "Aktuell" end
	local tb = stack:band({
		{ span = 6, title = T("Text — name"), toggle = {
			get = vget(ctx, "showName"),
			set = function(v) vset(ctx, "showName")(v); refreshName() end } },
		{ span = 6, title = T("Text — HP display"), toggle = {
			get = function() return (rf()[ctx] or {}).healthTextType ~= "Keine" end,
			set = function(v) vset(ctx, "healthTextType")(v and hpMode or "Keine"); refreshHP() end } },
	})

	local sName = tb.cards[1]
	local nr1, nc1 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	local namePos = W.Select(nc1[1], { label = T("Name position"), options = POINT_OPTS, get = vget(ctx, "namePoint"), set = vset(ctx, "namePoint") })
	namePos:SetAllPoints(nc1[1])
	local nameSize = sliderBox(nc1[2], { label = T("Name size"), min = 6, max = 30, get = vget(ctx, "nameSize"), set = vset(ctx, "nameSize") })
	sName:place(nr1, M.sliderBoxH, R.row)
	local nr2, nc2 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	local nameX = sliderBox(nc2[1], { label = T("Name X offset"), min = -40, max = 40, get = vget(ctx, "nameX"), set = vset(ctx, "nameX") })
	local nameY = sliderBox(nc2[2], { label = T("Name Y offset"), min = -40, max = 40, get = vget(ctx, "nameY"), set = vset(ctx, "nameY") })
	sName:place(nr2, M.sliderBoxH, R.tight)
	sName:close()

	local sHP = tb.cards[2]
	local hr1, hc1 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	local hpPos = W.Select(hc1[1], { label = T("HP text position"), options = POINT_OPTS, get = vget(ctx, "healthTextPoint"), set = vset(ctx, "healthTextPoint") })
	hpPos:SetAllPoints(hc1[1])
	local hpSize = sliderBox(hc1[2], { label = T("HP text size"), min = 6, max = 30, get = vget(ctx, "healthTextSize"), set = vset(ctx, "healthTextSize") })
	sHP:place(hr1, M.sliderBoxH, R.row)
	local hr2, hc2 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	local hpX = sliderBox(hc2[1], { label = T("HP text X offset"), min = -40, max = 40, get = vget(ctx, "healthTextX"), set = vset(ctx, "healthTextX") })
	local hpY = sliderBox(hc2[2], { label = T("HP text Y offset"), min = -40, max = 40, get = vget(ctx, "healthTextY"), set = vset(ctx, "healthTextY") })
	sHP:place(hr2, M.sliderBoxH, R.group) -- deliberate break: shared rows -> extra
	local hr3, hc3 = W.FieldRow(d, d, 1, { height = fieldH })
	local hpModeW = W.Segment(hc3[1], { label = T("Display"), options = HPTEXT_SEG_OPTS,
		tooltip = T("Live, WoW 12.0 shows current HP due to secret values; exact percent in the preview."),
		get = function() return hpMode end,
		set = function(v) hpMode = v; vset(ctx, "healthTextType")(v) end })
	hpModeW:SetAllPoints(hc3[1])
	sHP:place(hr3, fieldH, R.tight)
	sHP:close()
	tb.close()

	function refreshName()
		local on = (rf()[ctx] or {}).showName and true or false
		for _, w in ipairs(nameDeps) do w:SetWidgetEnabled(on) end
	end
	function refreshHP()
		local on = (rf()[ctx] or {}).healthTextType ~= "Keine"
		for _, w in ipairs(hpDeps) do w:SetWidgetEnabled(on) end
	end
	for _, w in ipairs({ namePos, nameSize, nameX, nameY }) do nameDeps[#nameDeps + 1] = w end
	for _, w in ipairs({ hpPos, hpSize, hpX, hpY, hpModeW }) do hpDeps[#hpDeps + 1] = w end
	refreshName(); refreshHP()

	-- ===== Indicator icons (role / leader; per context, collapsible) =====
	-- Same pattern as the aura section below: collapsed by default, state
	-- remembered per context, toggling re-renders the screen.
	local iOpen = iconOpen(ctx)
	local iconHead = W.Collapsible(d, { title = T("Role & leader icons"), open = iOpen,
		onToggle = function(v) setIconOpen(ctx, v); ns.Shell:RenderContent(true) end })
	-- Closed headers used to stack flush (gap 0, borders merged); with rounded
	-- cards they need a small gap so each reads as its own card (no pinched seam).
	stack:place(iconHead, M.sectionHeaderH, iOpen and R.afterCheck or M.headerStackGap)
	if iOpen then
		-- Band 6+6: Role icon | Leader icon — "Show" = header master toggle,
		-- same card anatomy as the text band above.
		local roleDeps, leadDeps = {}, {}
		local refreshRole, refreshLead
		local ib = stack:band({
			{ span = 6, title = T("Role icon"), toggle = {
				get = vget(ctx, "roleShow"),
				set = function(v) vset(ctx, "roleShow")(v); refreshRole() end } },
			{ span = 6, title = T("Leader icon"), toggle = {
				get = vget(ctx, "leadShow"),
				set = function(v) vset(ctx, "leadShow")(v); refreshLead() end } },
		})

		local sRole = ib.cards[1]
		local ir1, ic1 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		local rolePos = W.Select(ic1[1], { label = T("Role icon position"), options = POINT_OPTS,
			get = vget(ctx, "rolePoint"), set = vset(ctx, "rolePoint") })
		rolePos:SetAllPoints(ic1[1])
		local roleSize = sliderBox(ic1[2], { label = T("Size"), min = 8, max = 32, unit = " px",
			get = vget(ctx, "roleSize"), set = vset(ctx, "roleSize") })
		sRole:place(ir1, M.sliderBoxH, R.row)
		local ir2, ic2 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		local roleX = sliderBox(ic2[1], { label = T("X offset"), min = -40, max = 40,
			get = vget(ctx, "roleX"), set = vset(ctx, "roleX") })
		local roleY = sliderBox(ic2[2], { label = T("Y offset"), min = -40, max = 40,
			get = vget(ctx, "roleY"), set = vset(ctx, "roleY") })
		sRole:place(ir2, M.sliderBoxH, R.group) -- deliberate break: shared rows -> extra
		-- "Hide DPS icon" sits BELOW the sliders (tab-migration feedback): both
		-- icon cards share the same top rows, the card-specific option comes last.
		local cbDps = checkRow(d, T("Hide DPS icon"), { get = vget(ctx, "roleHideDps"),
			set = vset(ctx, "roleHideDps") })
		sRole:place(cbDps, M.optionRowH, R.tight)
		sRole:close()

		local sLead = ib.cards[2]
		local lr1, lc1 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		local leadPos = W.Select(lc1[1], { label = T("Leader icon position"), options = POINT_OPTS,
			get = vget(ctx, "leadPoint"), set = vset(ctx, "leadPoint") })
		leadPos:SetAllPoints(lc1[1])
		local leadSize = sliderBox(lc1[2], { label = T("Size"), min = 8, max = 32, unit = " px",
			get = vget(ctx, "leadSize"), set = vset(ctx, "leadSize") })
		sLead:place(lr1, M.sliderBoxH, R.row)
		local lr2, lc2 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		local leadX = sliderBox(lc2[1], { label = T("X offset"), min = -40, max = 40,
			get = vget(ctx, "leadX"), set = vset(ctx, "leadX") })
		local leadY = sliderBox(lc2[2], { label = T("Y offset"), min = -40, max = 40,
			get = vget(ctx, "leadY"), set = vset(ctx, "leadY") })
		sLead:place(lr2, M.sliderBoxH, R.tight)
		sLead:close()
		ib.close()

		function refreshRole()
			local on = (rf()[ctx] or {}).roleShow and true or false
			for _, w in ipairs(roleDeps) do w:SetWidgetEnabled(on) end
		end
		function refreshLead()
			local on = (rf()[ctx] or {}).leadShow and true or false
			for _, w in ipairs(leadDeps) do w:SetWidgetEnabled(on) end
		end
		for _, w in ipairs({ cbDps, rolePos, roleSize, roleX, roleY }) do roleDeps[#roleDeps + 1] = w end
		for _, w in ipairs({ leadPos, leadSize, leadX, leadY }) do leadDeps[#leadDeps + 1] = w end
		refreshRole(); refreshLead()
	end

	-- ===== Aura indicators (Feature 1: per context, collapsible at the bottom) =====
	-- The standalone "Auras" tab is gone — its display settings live here, separated
	-- per context. sfx maps the tab context to the aura field suffix ("Raid"/"Party").
	-- Collapsed by default; the choice is remembered. Toggling re-renders the screen.
	local sfx  = (ctx == "raid") and "Raid" or "Party"
	local open = auraOpen(ctx)
	local auraHead = W.Collapsible(d, { title = T("Aura indicators"), open = open,
		onToggle = function(v) setAuraOpen(ctx, v); ns.Shell:RenderContent(true) end })
	stack:place(auraHead, M.sectionHeaderH, open and R.afterCheck or M.headerStackGap)
	if open then
		local intro = W.Hint(d, T("Aura icons on the frame — set separately for this context. "
			.. "Which spells are tracked is shared and set in the \"Tracking\" tab. "
			.. "Shown in the live preview."), L.raidframes.tracking.introH)
		stack:place(intro, L.raidframes.tracking.introH, R.row)
		-- Two 6+6 bands (aura compaction 2026-07-05). The header toggles are
		-- wired at band creation; each card's refresh lands in auraRefresh via
		-- auraCat, so toggling greys the card without a rebuild.
		local auraRefresh = {}
		local function catToggle(cat)
			return {
				get = aget(cat, "enabled" .. sfx),
				set = function(v)
					aset(cat, "enabled" .. sfx)(v)
					if auraRefresh[cat] then auraRefresh[cat]() end
				end,
			}
		end
		local ab1 = stack:band({
			{ span = 6, title = T("HoTs"),                  toggle = catToggle("hotsOwn") },
			{ span = 6, title = T("Defensives & External"), toggle = catToggle("defensives") },
		})
		auraCat(d, ab1.cards[1], "hotsOwn",    false, ctx, sfx, auraRefresh)
		auraCat(d, ab1.cards[2], "defensives", false, ctx, sfx, auraRefresh)
		ab1.close()
		local ab2 = stack:band({
			{ span = 6, title = T("Major CDs"), toggle = catToggle("major") },
			{ span = 6, title = T("Debuffs"),   toggle = catToggle("debuffs") },
		})
		auraCat(d, ab2.cards[1], "major",   false, ctx, sfx, auraRefresh)
		auraCat(d, ab2.cards[2], "debuffs", true,  ctx, sfx, auraRefresh)
		ab2.close()
	end

	applyModuleGate(d, rf().enabled) -- module off -> whole Raid/Group screen greyed + locked
end

-- Small arrow button (Lucide chevron-up/down glyph; stage-3 glyph swap).
-- Has a disabled state (greyed out, not clickable) -> don't hide it, so the
-- row positions stay stable (no "jumping").
local function arrowButton(parent, dir, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 18)
	local glyph = b:CreateTexture(nil, "OVERLAY")
	glyph:SetSize(M.sortArrowGlyph, M.sortArrowGlyph)
	glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
	glyph:SetTexture(TEX .. (dir == "up" and "icon-chevron-up" or "icon-chevron-down"))
	glyph:SetSnapToPixelGrid(false); glyph:SetTexelSnappingBias(0)
	local function setCol(c) glyph:SetVertexColor(c.r, c.g, c.b) end
	-- Two-gold rule: the arrows are clickable -> interactive gold (C2/C3), not
	-- brand gold; a dimmed arrow (already at the edge) is TRUE disabled -> D3.
	b._on = true
	setCol(UI.P.goldInt)
	b:SetScript("OnEnter", function() if b._on then setCol(UI.P.goldIntHover) end end)
	b:SetScript("OnLeave", function() if b._on then setCol(UI.P.goldInt) end end)
	b:SetScript("OnClick", function() if b._on then onClick() end end)
	b.setDim = function(on)
		b._on = not on
		if on then setCol(UI.P.textDisabled); b:EnableMouse(false)
		else setCol(UI.P.goldInt); b:EnableMouse(true) end
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
	local G = UI.GRID
	stack:gap(L.general.tabTop) -- more air on top before the master toggle
	-- Full-width card with the global module switches (v3 mockup); each
	-- checkbox carries a muted description line below its label.
	local function checkDesc(cell, opts, desc)
		local cb = W.Checkbox(cell, opts)
		cb:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
		local fs = UI.FS(cell, "caption", C.textMuted)
		fs:SetPoint("TOPLEFT", cell, "TOPLEFT", M.checkBox + M.checkLabelGap, -(M.checkBox + 2))
		fs:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		fs:SetText(desc)
		return cb
	end
	local sTop = stack:section(nil)
	local enRow, enCells = W.Row(d, 2, { gap = G.cellGap, height = M.controlH })
	checkDesc(enCells[1], {
		label = T("Raidframes enabled"), get = tget("enabled"),
		set = function(v)
			rf().enabled = v
			if ns.Raidframes then if v then ns.Raidframes:Enable() else ns.Raidframes:Disable() end end
			applyModuleGate(body, v)
			-- The sibling tabs (Raid/Group/Tracking) bake this gate at build time ->
			-- drop cached screens so they rebuild with the new enabled state.
			if ns.Shell and ns.Shell.InvalidateScreenCache then ns.Shell:InvalidateScreenCache() end
		end,
	}, T("Turns the raidframe display on or off."))
	checkDesc(enCells[2], { label = T("Show frames even when solo"),
		get = tget("showWhenSolo"), set = tset("showWhenSolo") },
		T("Shows the group frame even when you are not in a group."))
	sTop:place(enRow, M.controlH, R.tight)
	sTop:close()

	-- Everything else goes into a gateable body frame: when "off" dimmed + locked
	-- (same 0.35 look as the sub-options). The local names d/stack are redirected
	-- to body/bstack -> the rest of the Base code keeps building unchanged.
	body = CreateFrame("Frame", nil, d)
	local bstack = ns.Shell.NewStack(body)
	d, stack = body, bstack

	-- ===== Band 1: Health bar (8) + Text (4) — card grid system ============
	-- (Boxed sliders come from the file-level sliderBox helper, shared with
	-- the Raid/Group builder.)
	local b1 = stack:band({
		{ span = 8, title = T("Health bar"), subtitle = T("Health bar and texture settings") },
		{ span = 4, title = T("Text"), subtitle = T("Name and text color settings") },
	})
	local sBar = b1.cards[1]

	-- Stacked rows first (§8: compact options on top, field blocks below):
	-- heal prediction, class color and the two color chips — the fill chip
	-- greys while the class color runs.
	local fillDeps = {}
	local function refreshFill()
		local editable = not rf().useClassColor
		for _, w in ipairs(fillDeps) do w:SetWidgetEnabled(editable) end
	end
	sBar:place(switchRow(d, T("Heal prediction"), {
		tooltip = T("Incoming healing previewed on the health bar."),
		get = tget("healPrediction"), set = tset("healPrediction") }), M.optionRowH, 0)
	sBar:place(switchRow(d, T("Class color as fill color"), { get = tget("useClassColor"),
		set = function(v) rf().useClassColor = v; relayout(); refreshFill() end }), M.optionRowH, 0)
	local rowFill = colorRow(d, T("Fill color"), tcget("fillColor"), tcset("fillColor"))
	sBar:place(rowFill, M.optionRowH, 0)
	sBar:place(colorRow(d, T("Background color"), tcget("bgColor"), tcset("bgColor")), M.optionRowH, R.row)
	fillDeps[1] = rowFill; refreshFill()

	-- Texture fields at the unit width: bar + shield share a row, heal-absorb
	-- wraps below (§8: the old 3-up row becomes 2+1 on the 8-card). Each with
	-- mouse-wheel preview + search field. Default "Lumen …" = stripe pattern,
	-- otherwise LSM/Blizzard.
	local tr1, tc1 = W.FieldRow(d, d, 2, { height = fieldH })
	W.Select(tc1[1], { label = T("Bar texture"), options = textureOptions(), wheelPreview = true, search = true, get = tget("healthTexture"), set = tset("healthTexture") }):SetAllPoints(tc1[1])
	W.Select(tc1[2], { label = T("Shield texture"), options = shieldTexOptions(), wheelPreview = true, search = true, get = tget("shieldTexture"), set = tset("shieldTexture") }):SetAllPoints(tc1[2])
	sBar:place(tr1, fieldH, R.tight)
	local tr1b, tc1b = W.FieldRow(d, d, 1, { height = fieldH })
	W.Select(tc1b[1], { label = T("Heal-absorb texture"), options = healAbsorbTexOptions(), wheelPreview = true, search = true, get = tget("healAbsorbTexture"), set = tset("healAbsorbTexture") }):SetAllPoints(tc1b[1])
	sBar:place(tr1b, fieldH, L.raidframes.base.healthbar.afterTexHint)
	-- Visible hint (instead of a hover tooltip) for the mouse-wheel preview + search field of the texture dropdowns.
	local texHint = W.Hint(d, T("Scroll the mouse wheel over a texture dropdown to preview textures live. In the open menu, the search box at the top filters."))
	sBar:place(texHint, M.hintH, R.row)

	-- The four opacity values as BOXED compact sliders, two unit cells per row.
	local trA, tcA = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	sliderBox(tcA[1], { label = T("Background opacity"), min = 0, max = 100, unit = " %", get = pctget("bgAlpha"), set = pctset("bgAlpha") })
	sliderBox(tcA[2], { label = T("Health bar opacity"), min = 0, max = 100, unit = " %", get = pctget("healthAlpha"), set = pctset("healthAlpha") })
	sBar:place(trA, M.sliderBoxH, R.row)
	local trB, tcB = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	sliderBox(tcB[1], { label = T("Shield opacity"), min = 0, max = 100, unit = " %", get = pctget("shieldAlpha"), set = pctset("shieldAlpha") })
	sliderBox(tcB[2], { label = T("Heal-absorb opacity"), min = 0, max = 100, unit = " %", get = pctget("healAbsorbAlpha"), set = pctset("healAbsorbAlpha") })
	sBar:place(trB, M.sliderBoxH, R.tight)
	sBar:close()

	-- ===== Text (SHARED: color + outline apply equally to Raid & Group) =====
	local sText = b1.cards[2]
	local nameColDeps = {}
	local function refreshNameCol()
		local on = not rf().nameClassColor
		for _, w in ipairs(nameColDeps) do w:SetWidgetEnabled(on) end
	end
	sText:place(switchRow(d, T("Name in class color"), { get = tget("nameClassColor"),
		set = function(v) rf().nameClassColor = v; relayout(); refreshNameCol() end }), M.optionRowH, R.row)
	-- Narrow 4-card -> ONE unit field per row (§8).
	local txR1, txc1 = W.FieldRow(d, d, 1, { height = fieldH })
	W.Segment(txc1[1], { label = T("Name outline"), options = OUTLINE_SEG_OPTS, get = tget("nameOutline"), set = tset("nameOutline") }):SetAllPoints(txc1[1])
	sText:place(txR1, fieldH, R.tight)
	local txR2, txc2 = W.FieldRow(d, d, 1, { height = fieldH })
	W.Segment(txc2[1], { label = T("HP outline"), options = OUTLINE_SEG_OPTS, get = tget("healthTextOutline"), set = tset("healthTextOutline") }):SetAllPoints(txc2[1])
	sText:place(txR2, fieldH, R.row)
	-- Advanced: the two text colors as chip rows (rarely touched — most run
	-- class color/white; curation 2026-07-04).
	if baseAdvState.text then
		local rowName = colorRow(d, T("Name color"), tcget("nameColor"), tcset("nameColor"))
		sText:place(rowName, M.optionRowH, 0)
		sText:place(colorRow(d, T("HP text color"), tcget("healthTextColor"), tcset("healthTextColor")), M.optionRowH, R.row)
		nameColDeps[1] = rowName
	end
	sText:place(W.Disclosure(d, { open = baseAdvState.text,
		label = baseAdvState.text and T("Less") or T("More options"),
		hint = T("Name color") .. " · " .. T("HP text color"),
		onToggle = function(v) baseAdvState.text = v; ns.Shell:RenderContent(true) end }), M.disclosureH, R.tight)
	sText:close()
	b1.close()
	refreshNameCol()

	-- ===== Band 2: Dispel (6) + Aggro (6) — master toggles in the header ====
	local dispelDeps, dispelAlphaW = {}, nil
	local refreshDispel, refreshAggro -- forward: the header toggles call them
	local b2 = stack:band({
		{ span = 6, title = T("Dispel display"), subtitle = T("Dispel highlight settings"), toggle = {
			get = tget("dispelEnabled"),
			set = function(v) rf().dispelEnabled = v; relayout(); refreshDispel() end } },
		{ span = 6, title = T("Aggro warning"), subtitle = T("Aggro warning settings"), toggle = {
			get = tget("aggroEnabled"),
			set = function(v) rf().aggroEnabled = v; relayout(); refreshAggro() end } },
	})
	local sDispel = b2.cards[1]

	function refreshDispel()
		local on = rf().dispelEnabled and true or false
		for _, w in ipairs(dispelDeps) do w:SetWidgetEnabled(on) end
		if dispelAlphaW then dispelAlphaW:SetWidgetEnabled(on and rf().dispelMode == "overlay") end
	end

	-- Stacked row first (§8), then the two field controls (2 unit cells fill
	-- the 6-card exactly): display segment | overlay opacity inset box.
	local rowShowAll = checkRow(d, T("Show all dispellable (not just yours)"), {
		get = tget("dispelShowAll"), set = tset("dispelShowAll") })
	sDispel:place(rowShowAll, M.optionRowH, R.row)
	local dr1, dc1 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	local dispMode = W.Segment(dc1[1], { label = T("Display"), options = DISPEL_SEG_OPTS,
		get = tget("dispelMode"), set = function(v) tset("dispelMode")(v); refreshDispel() end })
	dispMode:SetAllPoints(dc1[1])
	dispelAlphaW = sliderBox(dc1[2], { label = T("Overlay opacity"), min = 0, max = 100, unit = " %",
		get = pctget("dispelAlpha"), set = pctset("dispelAlpha") })
	sDispel:place(dr1, M.sliderBoxH, R.row)

	-- Advanced: the four dispel type colors as chip rows (set once; curation 2026-07-04).
	local dispColW = {}
	if baseAdvState.dispel then
		for i, t in ipairs(DISPEL_TYPES) do
			local row = colorRow(d, t.label, dcget(t.key), dcset(t.key))
			sDispel:place(row, M.optionRowH, i == #DISPEL_TYPES and R.row or 0)
			dispColW[i] = row
		end
	end
	local dispelHint = {}
	for i, t in ipairs(DISPEL_TYPES) do dispelHint[i] = t.label end
	sDispel:place(W.Disclosure(d, { open = baseAdvState.dispel,
		label = baseAdvState.dispel and T("Less") or T("More options"),
		hint = table.concat(dispelHint, " · "),
		onToggle = function(v) baseAdvState.dispel = v; ns.Shell:RenderContent(true) end }), M.disclosureH, R.tight)
	sDispel:close()

	for _, w in ipairs({ dispMode, rowShowAll, dispColW[1], dispColW[2], dispColW[3], dispColW[4] }) do
		dispelDeps[#dispelDeps + 1] = w
	end
	refreshDispel()

	-- ===== Aggro warning ===================================================
	local sAggro = b2.cards[2]
	local aggroAlways = {}                 -- coupled only to aggroEnabled
	local aggroAlphaW
	local aggroTextOpts = {}               -- only active when text is actually shown

	function refreshAggro()
		local en = rf().aggroEnabled and true or false
		for _, w in ipairs(aggroAlways) do w:SetWidgetEnabled(en) end
		if aggroAlphaW then
			aggroAlphaW:SetWidgetEnabled(en and (rf().aggroModeAggro == "overlay" or rf().aggroModeWarn == "overlay"))
		end
		local textActive = (rf().aggroModeAggro == "overlay" and rf().aggroTextAggro)
			or (rf().aggroModeWarn == "overlay" and rf().aggroTextWarn)
		for _, w in ipairs(aggroTextOpts) do w:SetWidgetEnabled(en and textActive and true or false) end
	end

	-- One stage = slim heading row (stage name) + display segment at the unit
	-- width + color chip row (§8: never two control types side by side). The
	-- segment combines mode + text like the old dropdown: "+ Text" = overlay
	-- mode WITH text. The separate profile fields modeKey + textKey are still
	-- written (data model/render unchanged).
	local function aggroStage(label, colorKey, modeKey, textKey)
		-- Stage heading with the shared top hairline (rule: the line always
		-- sits ABOVE — Florian 2026-07-11; without it the stages blurred).
		sAggro:place(subHeadRow(d, label), M.subHeadH, R.tight)
		local r, c = W.FieldRow(d, d, 1, { height = fieldH })
		local mode = W.Segment(c[1], { label = T("Display"), options = AGGRO_SEG_OPTS,
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
		sAggro:place(r, fieldH, R.tight)
		local sw = colorRow(d, T("Color"), tcget(colorKey), tcset(colorKey))
		sAggro:place(sw, M.optionRowH, R.row)
		aggroAlways[#aggroAlways + 1] = sw
		aggroAlways[#aggroAlways + 1] = mode
	end
	aggroStage(T("Has aggro (red)"),         "aggroColorAggro", "aggroModeAggro", "aggroTextAggro")
	aggroStage(T("Aggro incoming (yellow)"), "aggroColorWarn",  "aggroModeWarn",  "aggroTextWarn")

	-- Advanced: text fine-tuning (both stages), overlay opacity and the
	-- instance filter (curation 2026-07-04: all set-once).
	if baseAdvState.aggro then
		-- Stacked row first (§8: instance filter), then the field rows —
		-- 2 unit cells fill the 6-card exactly.
		local rowInst = checkRow(d, T("Dungeon/raid only"), {
			tooltip = T("Shows the aggro warning only inside instances (dungeon/raid). Off = everywhere, including solo/open world."),
			get = tget("aggroInstanceOnly"), set = tset("aggroInstanceOnly") })
		sAggro:place(rowInst, M.optionRowH, R.row)
		aggroAlways[#aggroAlways + 1] = rowInst

		local ar1, ac1 = W.FieldRow(d, d, 2, { height = fieldH })
		local agPoint = W.Select(ac1[1], { label = T("Text position"), options = POINT_OPTS, get = tget("aggroTextPoint"), set = tset("aggroTextPoint") })
		agPoint:SetAllPoints(ac1[1])
		local agOutline = W.Segment(ac1[2], { label = T("Text outline"), options = OUTLINE_SEG_OPTS, get = tget("aggroTextOutline"), set = tset("aggroTextOutline") })
		agOutline:SetAllPoints(ac1[2])
		sAggro:place(ar1, fieldH, R.row)

		-- Sliders in inset boxes like everywhere else (consistency — Florian).
		local ar2, ac2 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		aggroAlphaW = sliderBox(ac2[1], { label = T("Overlay opacity"), min = 0, max = 100, unit = " %",
			get = pctget("aggroFillAlpha"), set = pctset("aggroFillAlpha") })
		local agSize = sliderBox(ac2[2], { label = T("Text size"), min = 6, max = 28, get = tget("aggroTextSize"), set = tset("aggroTextSize") })
		sAggro:place(ar2, M.sliderBoxH, R.row)

		local ar3, ac3 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		local agX = sliderBox(ac3[1], { label = T("Text X offset"), min = -60, max = 60, get = tget("aggroTextX"), set = tset("aggroTextX") })
		local agY = sliderBox(ac3[2], { label = T("Text Y offset"), min = -60, max = 60, get = tget("aggroTextY"), set = tset("aggroTextY") })
		sAggro:place(ar3, M.sliderBoxH, R.row)

		for _, w in ipairs({ agPoint, agOutline, agSize, agX, agY }) do aggroTextOpts[#aggroTextOpts + 1] = w end
	end
	sAggro:place(W.Disclosure(d, { open = baseAdvState.aggro,
		label = baseAdvState.aggro and T("Less") or T("More options"),
		hint = T("Text position") .. " · " .. T("Text size") .. " · " .. T("Dungeon/raid only"),
		onToggle = function(v) baseAdvState.aggro = v; ns.Shell:RenderContent(true) end }), M.disclosureH, R.tight)
	sAggro:close()
	b2.close()
	refreshAggro()

	-- ===== Sorting (6) + Status (6): one paired row ========================
	-- Sorting is a NORMAL card (no collapse). When role-sorting, the reorderable
	-- role-priority list lives behind a "More options" disclosure (Florian
	-- 2026-07-16) so the card stays calm and closer in height to the Status card
	-- beside it. Sorting (left) + Status (right) share ONE span=6 | span=6 row;
	-- each column keeps its natural height (top-aligned) and builds into its own
	-- sub-stack. A full-width wrapper resolves the two half columns on resize.
	local pairF = CreateFrame("Frame", nil, d)
	pairF:SetFrameLevel(d:GetFrameLevel())
	local sortCol = CreateFrame("Frame", nil, pairF)   -- left: Sorting collapsible
	local statCol = CreateFrame("Frame", nil, pairF)   -- right: Status card
	sortCol:SetFrameLevel(pairF:GetFrameLevel())
	statCol:SetFrameLevel(pairF:GetFrameLevel())
	sortCol:SetPoint("TOPLEFT", pairF, "TOPLEFT", 0, 0)
	sortCol:SetPoint("BOTTOMLEFT", pairF, "BOTTOMLEFT", 0, 0)
	local function pairLayout(w)
		if not w or w <= 0 then return end
		local cw = (w - UI.GRID.cardGap) / 2
		sortCol:SetWidth(cw)
		statCol:ClearAllPoints()
		statCol:SetPoint("TOPLEFT", pairF, "TOPLEFT", cw + UI.GRID.cardGap, 0)
		statCol:SetPoint("BOTTOMLEFT", pairF, "BOTTOMLEFT", cw + UI.GRID.cardGap, 0)
		statCol:SetWidth(cw)
	end
	pairF:SetScript("OnSizeChanged", function(_, w) pairLayout(w) end)
	-- LEFT column: Sorting (normal section card).
	local lstack = ns.Shell.NewStack(sortCol)
	local sSort = lstack:section(T("Sorting"), { subtitle = T("Order and role priority") })

	-- Row 1: "Sort by" (one unit field; leftover card width = air).
	local smr, smc = W.FieldRow(sortCol, d, 1, { height = fieldH })
	local sortSel = W.Select(smc[1], { label = T("Sort by"), options = SORT_MODE_OPTS,
		get = tget("sortMode"), set = function(v) tset("sortMode")(v); ns.Shell:RenderContent(true) end })
	sortSel:SetAllPoints(smc[1])
	sSort:place(smr, fieldH, rf().sortMode == "role" and R.row or 0)

	if rf().sortMode == "role" then
		-- "Also in raid" as its own row below the dropdown.
		sSort:place(checkRow(d, T("Also sort by role in raid"), {
			tooltip = T("Off: your arrangement is kept in raids. On: role sorting also applies in raids. (Dungeon/party is always sorted.)"),
			get = tget("sortApplyRaid"), set = tset("sortApplyRaid") }), M.optionRowH, R.row)

		-- Advanced (Zusatzoptionen): the reorderable role-priority list — only
		-- relevant when role-sorting, so it lives behind the disclosure below.
		if baseAdvState.sort then
			local function swapRole(i, j)
				local o = rf().sortRoleOrder
				if not (o and o[i] and o[j]) then return end
				o[i], o[j] = o[j], o[i]
				relayout(); ns.Shell:RenderContent(true)
			end
			-- Priority list: card exactly one unit field wide (aligned with "Sort
			-- by"), role-colored rows (accent bar + wash) + ↑/↓ arrows in front
			-- (unusable ones greyed out, no jumping).
			local order = rf().sortRoleOrder or {}
			local pad, rowH = L.raidframes.base.sort.cardPad, L.raidframes.base.sort.rowH
			local cardH = #order * rowH + pad * 2
			local cr, cc = W.FieldRow(sortCol, d, 1, { height = cardH })
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
				barL:SetWidth(L.raidframes.base.sort.accentW)
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
			sSort:place(cr, cardH, R.tight)
		end

		-- Disclosure footer: closed hint shows the current order (Tank > Heiler > DPS).
		local hintParts = {}
		for _, role in ipairs(rf().sortRoleOrder or {}) do hintParts[#hintParts + 1] = ROLE_LABEL[role] or "?" end
		sSort:place(W.Disclosure(d, { open = baseAdvState.sort,
			label = baseAdvState.sort and T("Less") or T("More options"),
			hint = (not baseAdvState.sort) and table.concat(hintParts, " > ") or nil,
			onToggle = function(v) baseAdvState.sort = v; ns.Shell:RenderContent(true) end }), M.disclosureH, R.tight)
	end
	sSort:close()
	-- Sub-stack content height (trailing sectionGap dropped).
	local sortH = -lstack:y() - M.sectionGap

	-- ===== Status (center icon: ready check / summon) — RIGHT column ========
	-- The Dead/Ghost/Offline/Rez center TEXT is always on (core correctness,
	-- deliberately option-free); only the two icon feeds are toggleable.
	local rstack = ns.Shell.NewStack(statCol)
	local sStat = rstack:section(T("Status"), { subtitle = T("Ready check and summon on the frames") })
	sStat:place(checkRow(d, T("Show ready check"), {
		tooltip = T("Blizzard's familiar icons in the frame center: hourglass, green check, red X. Results stay visible for a few seconds."),
		get = tget("showReadyCheck"),
		set = function(v) rf().showReadyCheck = v; if ns.Raidframes then ns.Raidframes:RefreshCenterIcons() end end }), M.optionRowH, 0)
	sStat:place(checkRow(d, T("Show summon status"), {
		tooltip = T("Incoming summon: pending, accepted or declined (red X)."),
		get = tget("showSummon"),
		set = function(v) rf().showSummon = v; if ns.Raidframes then ns.Raidframes:RefreshCenterIcons() end end }), M.optionRowH, R.tight)
	sStat:close()
	local statH = -rstack:y() - M.sectionGap

	-- Row height = the taller column (natural heights, top-aligned); then place
	-- the full-width wrapper into the outer stack so the two halves resolve.
	local pairH = math.max(sortH, statH)
	stack:place(pairF, pairH, M.sectionGap)
	pairLayout(pairF:GetWidth())

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

-- One aura category as a compact 6-span band card (aura compaction 2026-07-05:
-- four full-width cards were too tall). The context is FIXED by the host tab
-- (sfx = "Raid" on the Raid tab, "Party" on the Group tab); ALL display knobs
-- read/write the per-context key (<base> .. sfx). Visible = what you touch when
-- setting a category up: count + size, then where the row lives (anchor +
-- growth; Florian: "wo + wohin" belong together). Set-once fine-tuning
-- (spacing, inside/outside, offsets, auto-fit, swipe) lives in "More options".
-- `s` = the band card's inner stacker; the "Show" master toggle is wired at
-- band creation and reaches this card's refresh via `refreshReg[cat]`.
function auraCat(d, s, cat, isDebuff, ctx, sfx, refreshReg)
	local fieldH = M.controlH + M.fieldGap
	local R = L.rhythm

	local function cget(base) return aget(cat, base .. sfx) end
	local function cset(base) return aset(cat, base .. sfx) end

	local deps = {}   -- coupled to "Show" (all controls except the master + size)
	local sizeW       -- size slider (additionally coupled to "Auto-Fit")
	local function refresh()
		local on = cget("enabled")() and true or false
		for _, w in ipairs(deps) do w:SetWidgetEnabled(on) end
		if sizeW then sizeW:SetWidgetEnabled(on and not cget("autoFit")()) end
	end
	refreshReg[cat] = refresh

	-- Count + size (boxed sliders).
	local a1, ac = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	local maxW = sliderBox(ac[1], { label = T("Max. icons"), min = 1, max = 8, get = cget("maxIcons"), set = cset("maxIcons") })
	sizeW = sliderBox(ac[2], { label = T("Size"), min = 8, max = 80, unit = " px", get = cget("size"), set = cset("size") })
	deps[#deps + 1] = maxW
	s:place(a1, M.sliderBoxH, R.row)

	-- Where the icon row lives: anchor + growth direction.
	local b1, bc = W.FieldRow(d, d, 2, { height = fieldH })
	local anchorW = W.Select(bc[1], { label = T("Position (anchor)"), options = POINT_OPTS, get = cget("anchor"), set = cset("anchor") }); anchorW:SetAllPoints(bc[1])
	local growW   = W.Select(bc[2], { label = T("Growth direction"), options = GROW_OPTS, get = cget("grow"), set = cset("grow") }); growW:SetAllPoints(bc[2])
	deps[#deps + 1] = anchorW; deps[#deps + 1] = growW
	s:place(b1, fieldH, R.row)

	-- Debuffs only: which debuffs are shown (important enough to stay visible).
	if isDebuff then
		local f1, fc = W.FieldRow(d, d, 1, { height = fieldH })
		local filterW = W.Select(fc[1], { label = T("Filter"), options = AURA_FILTER_OPTS,
			tooltip = T("Which debuffs are shown. Raid-relevant = Blizzard's default selection."),
			get = cget("filterMode"), set = cset("filterMode") })
		filterW:SetAllPoints(fc[1])
		deps[#deps + 1] = filterW
		s:place(f1, fieldH, R.row)
	end

	-- More options: auto-fit + swipe (stacked rows first, §8), then spacing +
	-- inside/outside and the offsets as unit-width field rows.
	if (auraAdvState[ctx] or {})[cat] then
		local cbFit = checkRow(d, T("Auto-fit (size from frame height)"), { get = cget("autoFit"),
			set = function(v) cset("autoFit")(v); refresh() end })
		s:place(cbFit, M.optionRowH, 0)
		local cbSwipe = checkRow(d, T("Cooldown swipe"), { get = cget("showSwipe"), set = cset("showSwipe") })
		s:place(cbSwipe, M.optionRowH, R.row)
		deps[#deps + 1] = cbFit; deps[#deps + 1] = cbSwipe

		local e1, ec = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		local spaceW = sliderBox(ec[1], { label = T("Spacing"), min = 0, max = 20, unit = " px", get = cget("spacing"), set = cset("spacing") })
		local outW = W.Segment(ec[2], { label = T("Placement"), options = PLACE_OPTS, get = cget("outside"), set = cset("outside") })
		outW:SetAllPoints(ec[2])
		deps[#deps + 1] = spaceW; deps[#deps + 1] = outW
		s:place(e1, M.sliderBoxH, R.row)

		local e2, ec2 = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
		local offXW = sliderBox(ec2[1], { label = T("Offset X"), min = -80, max = 80, unit = " px", get = cget("offX"), set = cset("offX") })
		local offYW = sliderBox(ec2[2], { label = T("Offset Y"), min = -80, max = 80, unit = " px", get = cget("offY"), set = cset("offY") })
		deps[#deps + 1] = offXW; deps[#deps + 1] = offYW
		s:place(e2, M.sliderBoxH, R.row)
	end
	local advOpen = (auraAdvState[ctx] or {})[cat]
	s:place(W.Disclosure(d, { open = advOpen,
		label = advOpen and T("Less") or T("More options"),
		hint = T("Spacing") .. " · " .. T("Placement") .. " · " .. T("Offsets") .. " · " .. T("Cooldown swipe"),
		onToggle = function(v)
			auraAdvState[ctx] = auraAdvState[ctx] or {}
			auraAdvState[ctx][cat] = v
			ns.Shell:RenderContent(true)
		end }), M.disclosureH, R.tight)

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

-- One tracked-spell row (v2 refinement no. 3): icon + name + quiet trash button
-- on the right (red only on hover); row hover = lighter surface + gold left edge.
local function makeTrackRow(parent, e, onRemove)
	local P = UI.P
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(L.raidframes.tracking.rowH)
	UI.RoundFill(row, P.element, nil, nil, UI.ROUND_R_CTRL)
	UI.RoundBorder(row, UI.line.soft, "OVERLAY", nil, UI.ROUND_R_CTRL) -- L here is UI.LAYOUT; line colors live in UI.line
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(M.spellIcon, M.spellIcon)
	icon:SetPoint("LEFT", row, "LEFT", 10, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(e.icon or 136243)
	-- Trash: permanently red (grey drowned next to the row text — Florian feedback),
	-- lighter red on hover, NO tooltip (it fought the row's spell tooltip = jumpy),
	-- same size as the Click-Cast catalog trash.
	local rm = W.IconButton(row, { icon = "icon-delete", size = M.iconAction,
		color = C.danger500, hoverColor = C.danger300, onClick = onRemove })
	rm:SetPoint("RIGHT", row, "RIGHT", -12, 0)
	local name = UI.FS(row, "selectText", C.textStrong)
	name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	name:SetPoint("RIGHT", rm, "LEFT", -10, 0)
	name:SetJustifyH("LEFT"); name:SetWordWrap(false)
	name:SetText(e.name or (T("Spell") .. " " .. tostring(e.id)))
	-- Hover: elementHover surface + gold left edge + own Lumen spell tooltip.
	local hov = UI.RoundFill(row, P.elementHover, "BORDER", nil, UI.ROUND_R_CTRL); hov:SetAlpha(0)
	local bar = row:CreateTexture(nil, "OVERLAY")
	bar:SetWidth(3)
	-- Straight edge bar stops before the rounded corners.
	bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -UI.ROUND_R_CTRL)
	bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, UI.ROUND_R_CTRL)
	UI.SetColor(bar, P.goldBrand); bar:Hide()
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self2)
		hov:SetAlpha(1); bar:Show(); W.ShowSpellTip(self2, e.id)
	end)
	row:SetScript("OnLeave", function() hov:SetAlpha(0); bar:Hide(); W.HideTip() end)
	return row
end

local function buildTracking(d, stack)
	local RFm  = ns.Raidframes
	local spec = trkSpec()

	stack:gap(L.general.tabTop)
	local intro = W.Hint(d, T("Which spells are tracked as aura icons — display & position are set per context in the \"Raid\" and \"Group\" tabs. "
		.. "Your active spec is edited automatically (WoW cannot read talents of other specs; their defaults apply automatically once you play them)."))
	stack:place(intro, L.raidframes.tracking.introH, L.raidframes.tracking.afterIntro)

	-- v2 refinement no. 4: active spec as a badge in the tab strip (chrome)
	-- instead of an inline text row in the content.
	ns.Shell:SetTabBadge(T("Active spec:"), (ns.ClickCast and ns.ClickCast:CurrentSpecName()) or "?")

	-- Band def for one category card: header shows the count (v2 refinement
	-- no. 1) + "Restore defaults" as a quiet header action (no. 2); the
	-- category description is the muted subtitle line.
	local function catDef(cat, entries)
		local catTyp = cat.typ
		return { span = 6, title = cat.label, subtitle = cat.desc, count = #entries,
			action = { text = T("Restore defaults"), onClick = function()
				W.Confirm({
					title       = T("Restore defaults?"),
					body        = T("This list will be reset to Lumen's curated default for your active spec. Your own entries in this category will be lost."),
					confirmText = T("Reset"),
					cancelText  = T("Cancel"),
					onConfirm   = function()
						if RFm then RFm:ResetWhitelist(spec, catTyp) end
						ns.Shell:RenderContent(true)
					end,
				})
			end } }
	end

	-- Card body: tracked spells ONE per row (in a 6-card a full row is about
	-- the old 2-up cell width), or an empty state; picker action row last.
	local function fillCat(s, cat, entries)
		local catTyp = cat.typ
		if #entries == 0 then
			s:place(W.EmptyState(d, { text = T("No spells tracked yet — add the first one.") }),
				L.raidframes.tracking.emptyH, L.raidframes.tracking.afterList)
		else
			local rowH = L.raidframes.tracking.rowH
			for i, e in ipairs(entries) do
				local tr = makeTrackRow(d, e, function()
					if RFm then RFm:RemoveWhitelist(spec, e.id) end
					ns.Shell:RenderContent(true)
				end)
				s:place(tr, rowH, (i == #entries) and L.raidframes.tracking.afterList or L.raidframes.tracking.betweenRows)
			end
		end

		-- Action row: only the spell picker ("Restore defaults" lives in the header).
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
				if RFm then RFm:AddWhitelist(spec, id, catTyp) end
				ns.Shell:RenderContent(true)
			end,
		})
		picker:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
		s:place(actionRow, M.buttonH, 0)
		s:close()
	end

	-- 6-card layout (no full-width cards, Florian 2026-07-11): HoTs |
	-- Defensives as a band, Major CDs below it.
	local entries = {}
	for i, cat in ipairs(TRACK_CATS) do
		entries[i] = (RFm and RFm:WhitelistEntries(spec, cat.typ)) or {}
	end
	local tb1 = stack:band({ catDef(TRACK_CATS[1], entries[1]), catDef(TRACK_CATS[2], entries[2]) })
	fillCat(tb1.cards[1], TRACK_CATS[1], entries[1])
	fillCat(tb1.cards[2], TRACK_CATS[2], entries[2])
	tb1.close()
	local tb2 = stack:band({ catDef(TRACK_CATS[3], entries[3]) })
	fillCat(tb2.cards[1], TRACK_CATS[3], entries[3])
	tb2.close()

	applyModuleGate(d, rf().enabled) -- module off -> whole screen greyed + locked
end

-- ===========================================================================
--  Click-Cast screen — the action CATALOG. One compact row per binding:
--  [spell-icon | name+hint | keybind | gear options | enable], in two sections
--  (Standard catalog actions + Custom spells). ONE keybind field per row: a mouse
--  button casts on CLICK, a keyboard key casts on HOVER (routed automatically by
--  key type; modifiers captured inline by holding Shift/Ctrl/Alt). Wired against
--  ns.ClickCast (data model + apply stay in the module).
-- ===========================================================================
local function cc() return ns.Lumen.db.profile.clickCast end
local function CCm() return ns.ClickCast end
local function ccApply() if CCm() then CCm():ApplyBindings() end end

local ccSelectedSpec  -- which spec is edited (decoupled from the live spec)

-- Standard catalog actions still available to add via "+ Add binding". Labels carry
-- the inline icon + the real spell/trinket name (FontStrings render |T..|t), so the
-- user sees exactly what they are adding (e.g. the equipped trinket's icon + name).
-- Standard catalog actions for the action picker (same searchable popover as the
-- spell picker): {id=type, name=label, icon}. Only the actions the class has.
local function ccActionFetch()
	local out, m = {}, CCm()
	if m then for _, t in ipairs(m.STANDARD_TYPES) do
		if m:ActionAvailable(t) then out[#out + 1] = { id = t, name = m:ActionLabel(t), icon = m:ActionIcon(t) } end
	end end
	return out
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

-- One catalog row, drawn as its own ROUNDED card with a small gap to the next
-- (tab migration Option b: the old flush shared-line stack is gone — every row
-- rounds like the tracked-spell rows, for a consistent card look). Right cluster
-- (from the RIGHT): [keybind][gear][trash][switch]. Left: a clickable picker
-- (custom = spell, standard = action) using the SAME searchable popover. Turning
-- the switch OFF dims + LOCKS the row (a cover blocks all but the switch).
local function ccCatalogRow(d, s, b, spec)
	local m = CCm()
	local custom = (b.type == "spell")
	local configured = (b.type and b.type ~= "" and not custom)
	local H, PAD, GAPX = L.clickcast.rowH, L.clickcast.rowPad, L.clickcast.rowGapX
	local row = CreateFrame("Frame", nil, d)
	row:SetHeight(H)
	UI.RoundFill(row, C.ink600, nil, nil, UI.ROUND_R_CTRL)
	UI.RoundBorder(row, UI.line.soft, "OVERLAY", nil, UI.ROUND_R_CTRL)

	-- right cluster (from the RIGHT): trash (delete, FAR right) <- switch <- gear <- keybind
	local trash = W.IconButton(row, { icon = "icon-delete", color = C.danger500, hoverColor = C.danger300,
		size = M.iconAction,
		onClick = function()
			local idx
			for i, x in ipairs(m:GetBindings(spec)) do if x == b then idx = i; break end end
			if idx then m:RemoveBinding(spec, idx) end
			ns.Shell:RenderContent(true)
		end })
	trash:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)

	local sw = W.Switch(row, {
		get = function() return b.enabled ~= false end,
		set = function(v) b.enabled = v; ccApply(); if row._setEnabled then row._setEnabled(v) end end })
	sw:SetPoint("RIGHT", trash, "LEFT", -GAPX, 0)

	-- options gear (only when the row HAS options) in a reserved slot so columns align
	local defs = {}
	if configured and b.type ~= "target" then
		defs[#defs + 1] = { label = T("Out of combat only"),
			tooltip = (b.type == "menu") and T("Prevents accidental menus in combat — only affects Lumen's frames.") or T("Only trigger out of combat."),
			get = function() return b.oocOnly end, set = function(v) b.oocOnly = v; ccApply() end }
	end
	if custom then
		defs[#defs + 1] = { label = T("Friendly only"), tooltip = T("Only act on friendly units."),
			get = function() return b.hoverFriendly end, set = function(v) b.hoverFriendly = v; ccApply() end }
		defs[#defs + 1] = { label = T("Enemy only"), tooltip = T("Only act on enemy units."),
			get = function() return b.hoverEnemy end, set = function(v) b.hoverEnemy = v; ccApply() end }
	end
	local gearSlot = CreateFrame("Frame", nil, row)
	gearSlot:SetSize(M.iconAction, M.iconAction)
	gearSlot:SetPoint("RIGHT", sw, "LEFT", -GAPX, 0)
	if #defs > 0 then
		local gear = W.GearPopover(gearSlot, { defs = defs, size = M.iconAction })
		gear:SetPoint("CENTER", gearSlot, "CENTER", 0, 0)
	end

	-- keybind — ALL rows editable (incl. Target/Menu, which a user may want to remap).
	-- bound = solid gold rounded ring, unbound = faint ring; ESC clears, every
	-- mouse button + modifiers are bindable.
	local kb = W.KeybindButton(row, { width = L.clickcast.keyW,
		format = function(k) return (m and m:FormatKey(k)) or k end,
		get = function() return b.key end,
		set = function(v) b.key = v; ccApply(); ns.Shell:RenderContent(true) end })
	kb:ClearAllPoints(); kb:SetPoint("RIGHT", gearSlot, "LEFT", -GAPX, 0)

	-- left side (clickable picker, fills from the left padding up to the keybind)
	local function fillLeft(w)
		w:ClearAllPoints()
		w:SetPoint("LEFT", row, "LEFT", PAD, 0)
		w:SetPoint("RIGHT", kb, "LEFT", -GAPX, 0)
	end
	if custom then
		local icon = b.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID) or nil
		fillLeft(W.SpellPicker(row, { bare = true,
			text = b.spell or T("Choose spell …"), icon = icon,
			fetch = ccSpellFetch,
			onPick = function(id)
				b.spellID = id
				b.spell = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or b.spell
				ccApply(); ns.Shell:RenderContent(true)
			end }))
	else
		-- standard row — a clickable action picker (SAME searchable popover as the spell
		-- rows). Configured shows the action's icon + name + grey hint; click to change.
		local label
		if configured then
			local hint = m and m:ActionHint(b.type)
			label = ((m and m:ActionLabel(b.type)) or b.type)
				.. (hint and ("  |cff8c8472— " .. hint .. "|r") or "")
		else
			label = T("Choose action …")
		end
		fillLeft(W.SpellPicker(row, { bare = true,
			icon = configured and m and m:ActionIcon(b.type) or nil, text = label,
			searchPlaceholder = T("Search action …"), fetch = ccActionFetch,
			onPick = function(v) b.type = v; ccApply(); ns.Shell:RenderContent(true) end }))
	end

	-- dim + LOCK when disabled: a dark cover over everything except the switch.
	-- Left corners rounded to sit flush inside the card; right edge is straight
	-- (it ends at the switch, which stays operable).
	local cover = CreateFrame("Button", nil, row)
	cover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
	cover:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1) -- full row HEIGHT (not the switch's)
	cover:SetPoint("RIGHT", sw, "LEFT", -GAPX, 0)          -- horizontally up to the switch
	cover:SetFrameLevel(row:GetFrameLevel() + 60)
	cover:EnableMouse(true)
	UI.RoundFill(cover, { r = C.ink850.r, g = C.ink850.g, b = C.ink850.b, a = 0.55 },
		"OVERLAY", "left", UI.ROUND_R_CTRL)
	row._setEnabled = function(on) cover:SetShown(not on) end
	row._setEnabled(b.enabled ~= false)

	s:place(row, H, L.clickcast.rowGap)
end

local function buildClickCast(d, stack)
	local LC = L.clickcast
	local R = L.rhythm
	local m = CCm()
	local spec = ccSelectedSpec
	if not spec and m then spec = m:CurrentSpecID(); ccSelectedSpec = spec end

	-- ===== Master card (like the Base tab: stays operable outside the gate) =
	-- Master + helpful filter (LEFT) and the Spec dropdown (RIGHT); the
	-- checkboxes are vertically centered on the dropdown's control band.
	local outerStack = stack
	local body
	stack:gap(L.general.tabTop)
	local sTop = stack:section(nil)
	local topRow = CreateFrame("Frame", nil, d)
	local topH = M.controlH + M.fieldGap
	local specSel, cbHelpful -- forward refs so the master toggle can grey them too
	local cbMaster = W.Checkbox(topRow, { label = T("Click-cast enabled"),
		tooltip = T("Takes over clicks on the raid frame buttons. Off = WoW default (left = target, right = menu)."),
		get = function() return cc().enabled end,
		set = function(v)
			cc().enabled = v; ccApply(); applyModuleGate(body, v)
			-- Spec + filter live in the master card, outside the body gate.
			if specSel then specSel:SetWidgetEnabled(v) end
			if cbHelpful then cbHelpful:SetWidgetEnabled(v) end
		end })
	cbMaster:ClearAllPoints()
	cbMaster:SetPoint("BOTTOMLEFT", topRow, "BOTTOMLEFT", 0, (M.controlH - M.checkBox) / 2)
	cbHelpful = W.Checkbox(topRow, { label = T("Show only helpful spells for selection"),
		tooltip = T("Limits the spell list to spells you can cast on yourself/allies. Off = all spells."),
		get = function() return cc().helpfulOnly end, set = function(v) cc().helpfulOnly = v end })
	cbHelpful:ClearAllPoints()
	cbHelpful:SetPoint("LEFT", cbMaster, "RIGHT", L.general.checkRowGap, 0)
	specSel = W.Select(topRow, { label = T("Spec (edit)"), options = ccSpecOpts(), placeholder = T("No spec"),
		tooltip = T("Which spec you edit here. In game, the bindings of your active spec apply automatically."),
		get = function() return ccSelectedSpec end,
		set = function(v) ccSelectedSpec = v; ns.Shell:RenderContent(true) end })
	specSel:SetWidth(LC.specW)
	specSel:ClearAllPoints(); specSel:SetPoint("TOPRIGHT", topRow, "TOPRIGHT", 0, 0)
	specSel:SetWidgetEnabled(cc().enabled); cbHelpful:SetWidgetEnabled(cc().enabled) -- initial state
	sTop:place(topRow, topH, R.tight)
	sTop:close()

	-- Everything else into a gateable body frame (when "off" dimmed + locked).
	body = CreateFrame("Frame", nil, d)
	local bstack = ns.Shell.NewStack(body)
	d, stack = body, bstack

	local bindings = (m and m:GetBindings(spec)) or {}
	local stdRows, cusRows = {}, {}
	for _, b in ipairs(bindings) do
		if b.type == "spell" then cusRows[#cusRows + 1] = b
		elseif m and m:ActionAvailable(b.type) then stdRows[#stdRows + 1] = b end
	end

	-- ===== Standard bindings (predefined catalog) ==========================
	-- Full-width section card (12 = the documented catalog exception, §8) with
	-- a count chip; each binding stays its own rounded row card inside.
	local sStd = stack:section(T("Standard bindings"), { count = #stdRows })
	for _, b in ipairs(stdRows) do ccCatalogRow(d, sStd, b, spec) end
	if #stdRows == 0 then sStd:place(W.Hint(d, T("(no bindings)")), LC.emptyH, LC.afterList) end
	-- "+ Add binding" adds a new (action-not-yet-chosen) row, like "+ Add
	-- spell". You then pick the action right in the row (no popover dropdown).
	sStd:gap(LC.addGap) -- breathing room off the last row
	local addStd = W.Button(d, { text = T("+ Add binding"), variant = "secondary",
		onClick = function()
			if m then m:AddBinding(spec, { type = "", key = "", enabled = true }) end
			ns.Shell:RenderContent(true)
		end })
	sStd:placeLeft(addStd, M.buttonH, R.tight)
	sStd:close()

	-- ===== Custom spells ===================================================
	local sCus = stack:section(T("Custom spells"), { count = #cusRows })
	for _, b in ipairs(cusRows) do ccCatalogRow(d, sCus, b, spec) end
	if #cusRows == 0 then sCus:place(W.Hint(d, T("(no bindings)")), LC.emptyH, LC.afterList) end
	sCus:gap(LC.addGap) -- breathing room off the last row
	local addSpell = W.Button(d, { text = T("+ Add spell"), variant = "secondary",
		onClick = function()
			if m then m:AddBinding(spec, { type = "spell", key = "", enabled = true }) end
			ns.Shell:RenderContent(true)
		end })
	sCus:placeLeft(addSpell, M.buttonH, R.tight)
	sCus:close()

	-- Footnote: how the one keybind field routes click vs hover + the modifier trick.
	local note = W.Hint(d, T("Mouse button = cast on click, keyboard key = cast on hover (routed automatically). "
		.. "Hold Shift, Ctrl or Alt while setting a key to add a modifier."), 34)
	stack:place(note, 34, 0)

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

	stack:gap(L.general.tabTop)
	local intro = W.Hint(d, T("Suite-wide settings. Profiles, export and import of your setup are in the \"Profile\" tab."))
	stack:place(intro, M.hintH, R.row)

	-- ===== Band 1: Language (6) + Move/Edit Mode (6) ========================
	-- No full-width 12-cards on settings tabs (Florian 2026-07-11: stacked-row
	-- controls drift too far right on the full panel width).
	local b1 = stack:band({
		{ span = 6, title = T("Language"), subtitle = T("Applies after a UI reload.") },
		{ span = 6, title = T("Move (Edit Mode)"), subtitle = T("Also works through WoW's own Edit Mode.") },
	})

	local sLang = b1.cards[1]
	local langOpts = {
		{ value = "auto", label = T("Automatic (system language)") },
		{ value = "enUS", label = "English" },
		{ value = "deDE", label = "Deutsch" },
	}
	local lr, lc = W.FieldRow(d, d, 1, { height = fieldH })
	W.Select(lc[1], { label = T("Interface language"), options = langOpts,
		tooltip = T("Language of Lumen's interface. \"Automatic\" follows your WoW client language. A reload is required to apply."),
		get = function() return ns.Lumen.db.global.language or "auto" end,
		set = function(v)
			ns.Lumen.db.global.language = v
			W.Confirm({
				title = T("Reload needed"),
				body = T("The interface language is applied after a UI reload."),
				confirmText = T("Reload now"), cancelText = T("Later"),
				variant = "primary", -- neutral confirm, nothing destructive (red = destructive only)
				onConfirm = function() ReloadUI() end,
			})
		end }):SetAllPoints(lc[1])
	sLang:place(lr, fieldH, R.tight)
	sLang:close()

	local sMove = b1.cards[2]
	-- v2: the old "Unlock frames" checkbox became the Edit Mode session — the
	-- sidebar button is the primary entry, this one keeps it findable where
	-- movement topics live. Both buttons share one row (uniform anatomy).
	local btnRow = CreateFrame("Frame", nil, d)
	local openBtn = W.Button(btnRow, { text = T("Open Edit Mode"), variant = "neutral", icon = "icon-move",
		onClick = function() if ns.EditMode then ns.EditMode:OpenSession() end end })
	openBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)

	local resetBtn = W.Button(btnRow, { text = T("Reset positions"), variant = "ghost",
		onClick = function()
			W.Confirm({
				title = T("Reset positions?"),
				body = T("Resets all movable Lumen elements to their default positions and removes couplings."),
				confirmText = T("Reset"), cancelText = T("Cancel"),
				onConfirm = function()
					-- Drop Edit Mode couplings first so the elements fall back to
					-- the default absolute positions set below.
					wipe(ns.Lumen.db.profile.editLinks)
					local r = rf()
					for _, ctx in ipairs({ "raid", "party" }) do
						local t = r[ctx]; if t then t.point, t.x, t.y = "CENTER", 0, -120 end
					end
					relayout()
					local q = ns.Lumen.db.profile.qol.pull
					q.btnPos = { point = "CENTER", x = 0, y = -300 }
					local tk = ns.Lumen.db.profile.qol.trackers
					tk.brez.pos = { point = "CENTER", x = -30, y = -240 }
					tk.lust.pos = { point = "CENTER", x = 30, y = -240 }
					if ns.QoL then ns.QoL:ApplyPull(); ns.QoL:ApplyTrackers() end
					if ns.EditMode then ns.EditMode:_refresh() end
				end,
			})
		end })
	resetBtn:SetPoint("LEFT", openBtn, "RIGHT", UI.GRID.cardGap, 0)
	sMove:place(btnRow, M.buttonH, R.tight)
	sMove:close()
	b1.close()

	-- ===== Band 2: UI scale (6, ONE card) ===================================
	-- Game UI scale + settings-window scale merged into one card, separated by
	-- a sub-heading (Florian 2026-07-11). The air on the right is the growth
	-- spot for future global options.
	-- UI scale: profile-bound + exported — with "pixel perfect" (768/screen
	-- height, the ElvUI-style formula) a profile renders identically on every
	-- machine, so imported layouts stop jumping between UI-scale settings.
	local function us() return ns.Lumen.db.profile.uiScale end
	local function applyUIScale() ns.Lumen:ApplyUIScale() end
	local ppLabel
	do
		local _, physH = GetPhysicalScreenSize()
		ppLabel = T("Pixel perfect (%s on this screen)"):format(string.format("%.4f", 768 / physH))
	end

	local b2 = stack:band({
		{ span = 6, title = T("UI scale"), subtitle = T("Scales the whole game interface. Off: Lumen leaves WoW's own setting untouched.") },
	})

	local sUI = b2.cards[1]
	local rowPP, slUS
	local function refreshUS()
		local on = us().enabled and true or false
		rowPP:SetWidgetEnabled(on)
		slUS:SetWidgetEnabled(on and not us().pixelPerfect)
	end

	sUI:place(checkRow(d, T("Let Lumen manage the UI scale"), {
		tooltip = T("Sets the game's UI scale from this profile — exported profiles then look the same everywhere. Off: back to WoW's own setting after the next reload."),
		get = function() return us().enabled end,
		set = function(v) us().enabled = v; applyUIScale(); refreshUS() end }), M.optionRowH, 0)

	rowPP = checkRow(d, ppLabel, {
		tooltip = T("768 divided by your screen height — crisp 1:1 pixels and identical proportions on every machine."),
		get = function() return us().pixelPerfect end,
		set = function(v) us().pixelPerfect = v; applyUIScale(); refreshUS() end })
	sUI:place(rowPP, M.optionRowH, R.afterCheck)

	local usr, usc = W.FieldRow(d, d, 1, { height = M.sliderBoxH })
	slUS = sliderBox(usc[1], { label = T("Scale"), min = 40, max = 115, step = 1, unit = " %",
		get = function() return math.floor((us().scale or 0.71) * 100 + 0.5) end,
		set = function(v) us().scale = v / 100; applyUIScale() end })
	sUI:place(usr, M.sliderBoxH, R.group) -- deliberate break before the sub-section

	-- Sub-section: settings-window scale (machine-global, not in the profile).
	sUI:place(subHeadRow(d, T("Settings window")), M.subHeadH, R.tight)
	sUI:place(W.Hint(d, T("Size of this settings window. Independent of WoW's UI scale.")), M.hintH, R.tight)
	local scr, scc = W.FieldRow(d, d, 1, { height = M.sliderBoxH })
	sliderBox(scc[1], { label = T("Scale"), min = 50, max = 130, step = 1, unit = " %",
		commitOnRelease = true, -- rescaling the panel mid-drag moves the slider under the cursor
		get = function() return math.floor(((ns.Lumen.db.global.shellScale or 1) * 100) + 0.5) end,
		set = function(v)
			ns.Lumen.db.global.shellScale = v / 100
			if ns.Shell and ns.Shell.ApplyScale then ns.Shell:ApplyScale() end
		end })
	sUI:place(scr, M.sliderBoxH, R.tight)
	sUI:close()
	refreshUS()
	b2.close()
end

-- Global/Profile: transient state (file-local -> survives a RenderContent rebuild).
-- Module/layout selection lives in the import popup (W.ImportDialog) itself, not here.
local shareExport    = ""    -- last generated export code
local shareImportRaw = ""    -- pasted import text
local importErr      = nil   -- error text from the last "Import" (or nil)

local function buildGlobalProfile(d, stack)
	local db = ns.Lumen.db
	local R = L.rhythm
	local G = L.global.profile
	local fieldH = M.controlH + M.fieldGap

	stack:gap(L.general.tabTop)

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

	-- ===== Band: Profile (6) + New profile (6) ==============================
	-- No full-width 12-cards on settings tabs (Florian 2026-07-11).
	local pb = stack:band({
		{ span = 6, title = T("Profile"), subtitle = T("Switch, copy, create or reset your setup.") },
		{ span = 6, title = T("New profile"), subtitle = T("Creates a fresh profile and switches into it.") },
	})

	local sProf = pb.cards[1]
	local r1, c1 = W.FieldRow(d, d, 2, { height = fieldH })
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
	sProf:place(r1, fieldH, R.tight)
	local r2, c2 = W.FieldRow(d, d, 1, { height = fieldH })
	W.Select(c2[1], { label = T("Delete"), options = profileOpts(true), placeholder = T("Choose profile …"),
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
		end }):SetAllPoints(c2[1])
	sProf:place(r2, fieldH, R.row)
	local resetBtn = W.Button(d, { text = T("Reset"), variant = "danger",
		onClick = function()
			W.Confirm({
				title = T("Reset profile?"),
				body = T("Resets the current profile (\"%s\") to Lumen's default values."):format(db:GetCurrentProfile()),
				confirmText = T("Reset"), cancelText = T("Cancel"),
				onConfirm = function() db:ResetProfile(); ns.Shell:RenderContent(true) end,
			})
		end })
	sProf:placeLeft(resetBtn, M.buttonH, R.tight)
	sProf:close()

	local sNew = pb.cards[2]
	local input
	local nr, ncells = W.FieldRow(d, d, 1, { height = fieldH })
	input = W.TextInput(ncells[1], { label = T("Name"), placeholder = T("Enter name …"),
		onEnter = function(v)
			local name = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if name ~= "" then db:SetProfile(name); ns.Shell:RenderContent(true) end
		end })
	input:SetAllPoints(ncells[1])
	sNew:place(nr, fieldH, R.row)
	local createBtn = W.Button(d, { text = T("Create"), variant = "primary",
		onClick = function()
			local name = input and (input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
			if name ~= "" then db:SetProfile(name); ns.Shell:RenderContent(true) end
		end })
	sNew:placeLeft(createBtn, M.buttonH, R.tight)
	sNew:close()
	pb.close()

	-- ===== Share — Export | Import (6+6 band; tab migration: titled sub-boxes
	-- retired for two flat cards, description = v3 subtitle) =================
	-- Paste code -> "Import" (bottom right) opens the popup (module/layout
	-- selection + "Create profile"/"Overwrite current"). Declared before the
	-- band so the import card's button can call it.
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

	local sb = stack:band({
		{ span = 6, title = T("Export"), subtitle = T("Share your complete setup as a code.") },
		{ span = 6, title = T("Import"), subtitle = T("Take someone else's code — granular per module.") },
	})

	-- Export card
	local sExp = sb.cards[1]
	local genBtn = W.Button(d, { text = T("Generate export code"), variant = "ghost",
		onClick = function()
			shareExport = (ns.Share and ns.Share:Export()) or ""
			ns.Shell:RenderContent(true)
		end })
	sExp:placeLeft(genBtn, M.buttonH, G.afterExportBtn)
	local expTA = W.Textarea(d, { height = G.taH, readOnly = true,
		placeholder = T("No code yet — click \"Generate export code\", then select here (Ctrl+A) and copy (Ctrl+C)."),
		get = function() return shareExport end })
	sExp:place(expTA, G.taH, R.tight)
	sExp:close()

	-- Import card
	local sImp = sb.cards[2]
	local impTA = W.Textarea(d, { height = G.taH, placeholder = T("Paste profile code here (Ctrl+V) …"),
		get = function() return shareImportRaw end,
		onChange = function(t) shareImportRaw = t end })
	sImp:place(impTA, G.taH, importErr and R.tight or R.row)

	if importErr then
		sImp:place(W.Hint(d, "|cffD66A5C" .. T("Invalid code: %s — please paste the complete code."):format(importErr) .. "|r"), M.hintH, R.row)
	end

	-- "Import" button at the bottom right of the card (own row, right-aligned).
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
	sImp:place(btnRow, M.buttonH, R.tight)
	sImp:close()

	sb.close()
end

-- ===========================================================================
--  QoL screens — quality-of-life module. This tab piloted the stacked-row
--  layout (decided 2026-07-07); with the layout pass it IS the addon-wide
--  standard (design bible §8): compact options = W.OptionRow rows, field
--  controls = W.FieldRow cells at the unit width (like Size/Thickness here).
-- ===========================================================================

-- Profile access + apply (QoL values live under db.profile.qol.<feature>).
local function qc() return ns.Lumen.db.profile.qol.cursor end
local function applyCursor() if ns.QoL then ns.QoL:ApplyCursor() end end
local function qget(key) return function() return qc()[key] end end
local function qset(key) return function(v) qc()[key] = v; applyCursor() end end
-- Vendor values are only READ on MERCHANT_SHOW -> setters just store, no apply.
-- (vget/vset are taken by the raidframes context helpers above -> vnget/vnset.)
local function qv() return ns.Lumen.db.profile.qol.vendor end
local function vnget(key) return function() return qv()[key] end end
local function vnset(key) return function(v) qv()[key] = v end end
-- Pull timer (slash-command registration reacts to the toggle -> ApplyPull).
local function qp() return ns.Lumen.db.profile.qol.pull end
local function applyPull() if ns.QoL then ns.QoL:ApplyPull() end end
local function pget(key) return function() return qp()[key] end end
local function pset(key) return function(v) qp()[key] = v end end

local function buildQoLBase(d, stack)
	local R = L.rhythm

	stack:gap(L.general.tabTop)
	local intro = W.Hint(d, T("Small quality-of-life helpers — more features will follow."))
	stack:place(intro, M.hintH, R.row)

	-- ===== Cursor ring + Vendor (6+6 band) ==================================
	-- Cursor: master toggle in the header. Vendor: each row IS its own feature,
	-- so no master — three independent switches.
	local refreshCursor
	local cursorDeps = {}   -- rows greyed by the master toggle
	local rowColor          -- additionally gated by "class color"
	local b = stack:band({
		{ span = 6, title = T("Cursor"), subtitle = T("Ring around the mouse cursor"), toggle = {
			get = qget("enabled"),
			set = function(v) qc().enabled = v; applyCursor(); refreshCursor() end } },
		{ span = 6, title = T("Vendor"), subtitle = T("Automatic repair and junk selling") },
	})
	local sc = b.cards[1]
	local vc = b.cards[2]

	function refreshCursor()
		local on = qc().enabled and true or false
		for _, w in ipairs(cursorDeps) do w:SetWidgetEnabled(on) end
		if rowColor then rowColor:SetWidgetEnabled(on and not qc().classColor) end
	end

	-- Stacked rows: hairlines separate the options, controls right-aligned.
	local rowH = M.optionRowH
	local rowClass = switchRow(d, T("Class color"), { get = qget("classColor"),
		set = function(v) qc().classColor = v; applyCursor(); refreshCursor() end,
		tooltip = T("Tint the ring in your class color. Off: pick your own color below.") })
	sc:place(rowClass, rowH, 0)

	rowColor = colorRow(d, T("Ring color"),
		function() local col = qc().color or {}; return col.r or 1, col.g or 1, col.b or 1 end,
		function(r, g, bl) qc().color = { r = r, g = g, b = bl }; applyCursor() end)
	sc:place(rowColor, rowH, 0)

	local rowCombat = switchRow(d, T("Only in combat"), { get = qget("onlyInCombat"), set = qset("onlyInCombat"),
		tooltip = T("Show the ring only while you are in combat.") })
	sc:place(rowCombat, rowH, R.row)

	-- Size + thickness as a slider pair (2 unit cells fill the 6-card exactly).
	local sr, scc = W.FieldRow(d, d, 2, { height = M.sliderBoxH })
	local slSize = sliderBox(scc[1], { label = T("Size"), min = 16, max = 96, unit = " px",
		get = qget("size"), set = qset("size") })
	local slThick = sliderBox(scc[2], { label = T("Thickness"), min = 1, max = 5, step = 1,
		get = qget("thickness"), set = qset("thickness") })
	sc:place(sr, M.sliderBoxH, R.tight)

	cursorDeps[1] = rowClass
	cursorDeps[2] = rowCombat
	cursorDeps[3] = slSize
	cursorDeps[4] = slThick

	sc:close()

	-- ===== Vendor card ======================================================
	local rowGuild -- greyed unless auto repair is on
	local function refreshVendor()
		rowGuild:SetWidgetEnabled(qv().autoRepair and true or false)
	end

	local rowRepair = switchRow(d, T("Auto repair"), { get = vnget("autoRepair"),
		set = function(v) qv().autoRepair = v; refreshVendor() end,
		tooltip = T("Repair all your items automatically when you visit a merchant.") })
	vc:place(rowRepair, rowH, 0)

	rowGuild = switchRow(d, T("Use guild funds"), { get = vnget("useGuildFunds"), set = vnset("useGuildFunds"),
		tooltip = T("Pay repairs from the guild bank when possible — falls back to your own gold.") })
	vc:place(rowGuild, rowH, 0)

	local rowJunk = switchRow(d, T("Sell junk"), { get = vnget("sellJunk"), set = vnset("sellJunk"),
		tooltip = T("Sell all junk (grey) items automatically when you visit a merchant.") })
	vc:place(rowJunk, rowH, 0)

	vc:close()
	b.close()

	-- ===== Pull timer + Mythic+ (6+6 band) ==================================
	local pb = stack:band({
		{ span = 6, title = T("Pull timer"), subtitle = T("Countdown for the group (/pull)") },
		{ span = 6, title = "Mythic+", subtitle = T("Keystone and instance-reset helpers") },
	})
	local pc = pb.cards[1]
	local mc = pb.cards[2]
	-- M+ values are only read event-side -> setters just store.
	local function qm() return ns.Lumen.db.profile.qol.mplus end
	local function mpget(key) return function() return qm()[key] end end
	local function mpset(key) return function(v) qm()[key] = v end end

	local slPull -- duration feeds /pull AND the Pull button -> greyed only if both are off
	local function refreshPull() slPull:SetWidgetEnabled((qp().enabled or qp().buttons) and true or false) end

	local rowPull = switchRow(d, T("Enable /pull"), { get = pget("enabled"),
		set = function(v) qp().enabled = v; applyPull(); refreshPull() end,
		tooltip = T("Adds the /pull chat command: /pull starts the countdown below, /pull <seconds> overrides it, /pull 0 cancels.") })
	pc:place(rowPull, rowH, 0)

	local rowBtns = switchRow(d, T("Show Ready & Pull buttons"), { get = pget("buttons"),
		set = function(v) qp().buttons = v; applyPull(); refreshPull() end,
		tooltip = T("Movable button block (unlock via Edit Mode). Pull: left-click starts the countdown, right-click cancels. Ready starts a ready check.") })
	pc:place(rowBtns, rowH, R.row)

	local pr, pcells = W.FieldRow(d, d, 1, { height = M.sliderBoxH })
	slPull = sliderBox(pcells[1], { label = T("Duration"), min = 3, max = 30, step = 1, unit = " s",
		get = pget("duration"), set = pset("duration") })
	pc:place(pr, M.sliderBoxH, R.tight)
	pc:close()

	-- ===== Mythic+ card =====================================================
	local rowKey = switchRow(d, T("Auto-insert keystone"), { get = mpget("autoKeystone"), set = mpset("autoKeystone"),
		tooltip = T("Puts your keystone into the Font of Power automatically when its window opens.") })
	mc:place(rowKey, rowH, 0)

	local rowReset = switchRow(d, T("Announce instance reset"), { get = mpget("resetAnnounce"), set = mpset("resetAnnounce"),
		tooltip = T("Posts a short message to your group when you reset instances.") })
	mc:place(rowReset, rowH, 0)

	mc:close()
	pb.close()

	-- ===== Buffs + Trackers band ============================================
	local bb = stack:band({
		{ span = 6, title = T("Buffs"), subtitle = T("Cosmetic buff cleanup") },
		{ span = 6, title = T("Trackers"), subtitle = T("Battle res and Bloodlust at a glance") },
	})
	local bc = bb.cards[1]
	local tc = bb.cards[2]
	local function qb() return ns.Lumen.db.profile.qol.buffs end
	local function qt() return ns.Lumen.db.profile.qol.trackers end
	local function applyTrackers() if ns.QoL then ns.QoL:ApplyTrackers() end end

	local rowOutfit = switchRow(d, T("Suppress profession outfits"), {
		get = function() return qb().suppressOutfit end,
		set = function(v) qb().suppressOutfit = v; if ns.QoL then ns.QoL:ApplyOutfitSuppress() end end,
		tooltip = T("Removes the cosmetic profession-gear buffs (chef's hat etc.) that WoW re-applies on every login — they break your transmog.") })
	bc:place(rowOutfit, rowH, 0)
	bc:close()

	-- ===== Trackers card ====================================================
	-- Size + position are edited live in Edit Mode (per-element flyout), so the
	-- tab only toggles the trackers on/off — no duplicate size sliders here.
	local function trackerHint()
		if ns.Lumen then ns.Lumen:Print(T("Set its size and position in Edit Mode.")) end
	end

	local rowBrez = switchRow(d, T("Combat res tracker"), {
		get = function() return qt().brez.enabled end,
		set = function(v) qt().brez.enabled = v; applyTrackers(); if v then trackerHint() end end,
		tooltip = T("Shared battle-res pool as an icon (charges + recharge timer) — visible during Mythic+ runs and raid bosses, greyed while no charge is up. Place it via Edit Mode.") })
	tc:place(rowBrez, rowH, 0)

	local rowLust = switchRow(d, T("Bloodlust tracker"), {
		get = function() return qt().lust.enabled end,
		set = function(v) qt().lust.enabled = v; applyTrackers(); if v then trackerHint() end end,
		tooltip = T("Shows whether Bloodlust is available: normal icon when ready, greyed with a timer while you are Sated. Visible in dungeons and raids. Place it via Edit Mode.") })
	tc:place(rowLust, rowH, R.row)

	local trHint = W.Hint(d, T("Size and position: adjust each tracker in Edit Mode."))
	tc:place(trHint, M.hintH, R.row)

	tc:close()
	bb.close()

	refreshCursor()
	refreshVendor()
	refreshPull()
end

ns.Screens["Global/Base"]    = buildGlobalBase
ns.Screens["Global/Profile"] = buildGlobalProfile
ns.Screens["QoL/Base"]       = buildQoLBase

ns.Screens["Click-Cast/Bindings"] = buildClickCast

ns.Screens["Raidframes/Base"]     = buildBase
ns.Screens["Raidframes/Raid"]     = function(d, stack) buildRaid(d, stack, "raid") end
ns.Screens["Raidframes/Group"]    = function(d, stack) buildRaid(d, stack, "party") end
ns.Screens["Raidframes/Tracking"] = buildTracking
