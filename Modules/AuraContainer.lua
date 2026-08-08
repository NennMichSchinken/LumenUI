-- Modules/AuraContainer.lua
--
-- Aura Phase 2 (WIP) -- native 12.1 AuraContainer rendering for raid-frame auras.
-- Renders all four aura categories via the native container on the LIVE secure
-- raid buttons: Buffs (Blizzard's group-window list plus the player's extras),
-- Defensives (Blizzard's per-spell flags, with the curated whitelist as fallback)
-- and Debuffs (HARMFUL) via filter-mode groups (raid/all/dispellable). Replaces
-- the old manual scan/signature/secret-icon path -- see NATIVE_CATS.
--
-- Because SetAuraLayout* is CONTAINER-level (one anchor per container) and our
-- categories use different corners, each category gets its OWN container per
-- button: button._rfc = { [catKey] = container }.
--
-- Auto-default ON on 12.1 (detected via build number); `/lumennative on|off` is
-- a manual override. Inert on 12.0.x (the "AuraContainer" frame type does not
-- exist -> attach no-ops, old scan path renders).
--
-- Not final: layout parity for centered anchors is a follow-up, and whether OTHER
-- units' SECRET auras render on the non-secure overlay parent still needs a
-- real-group test.
--
-- Build compatibility: the 12.1 PTR renamed and added API between builds, so every
-- engine call that moved is resolved by presence, never assumed -- see
-- LAYOUT_METHODS (SetAuraLayout* -> SetFlowLayout*), the duration formatter option
-- key, and the pandemic regions (12.1 build 69111 and up).

-- luacheck: globals SLASH_LUMENNATIVE1

local _, ns = ...

local RFC = {}
ns.RFC = RFC

local InCombatLockdown = InCombatLockdown
local CreateFrame       = CreateFrame
local floor, strfind    = math.floor, string.find

RFC.enabled = false

-- Audit counters for /lumenprof. Timing alone cannot see the two costs that
-- matter on this path, because both are paid INSIDE the engine:
--   * groups -- AddAuraGroup pre-creates a whole batch of aura buttons the
--     moment a group is declared (Blizzard_CustomAuraContainer: the frame
--     provider's CreateFrameBatch runs unconditionally, before maxFrameCount is
--     ever read). A group that will never show an icon still costs frames.
--   * filterPush -- SetAuraGroupCandidateFilters calls UpdateAllAuras() with no
--     equality check of its own, so every push is a full re-parse of that
--     unit's auras.
-- Plain integer adds at declaration/reconcile sites, never in a per-aura path.
-- Scaffolding for the 2026-08 audit round; goes out with the dev-only tooling.
-- `buttons` counts BOTH initializers. The first reading missed the dispel ones and
-- reported 8.3 buttons per group where the engine actually creates exactly 10 --
-- a counter that only sees one of two creation paths lies quietly.
RFC.stat = { groups = 0, filterPush = 0, buttons = 0 }

-- Categories the native path owns. HELPFUL ones have TWO possible sources, see
-- `flagFilters` below; debuffs are HARMFUL (harmful=true) and filter by MODE via
-- filter strings (per-spellId matching is not permitted for harmful auras on
-- assistable units -- the Phase 1 constraint).
--
-- flagFilters = Blizzard's own answer to "which auras belong in this category",
-- flagged per spell by them instead of curated per spec by us. Their comment in
-- AuraUtil.AuraFilters names our exact case: RAID_IN_COMBAT is "auras flagged to
-- show on raid frames in combat -- combine with Player & Helpful to return
-- self-cast HoTs". A hand-kept list can only ever have holes (Earth Shield was
-- missing for two shaman specs); a per-spell flag covers every class and spec,
-- including the ones nobody ever tested. Measured on the 12.1 PTR (Florian
-- 2026-08-08): the HoT set arrives IN and OUT of combat, and Earth Shield shows
-- up for Elemental without a whitelist entry -- the gap that started all this.
--
-- A list per category, not one filter, for two reasons:
--   * filter strings are AND-joined (AuraUtil.CreateFilterString), so a category
--     that is a UNION of two flags needs one group per flag, and
--   * Blizzard's flags OVERLAP where ours do not. Ironbark is EXTERNAL_DEFENSIVE
--     *and* BIG_DEFENSIVE, and out of combat it is raid-flagged on top -- it drew
--     three times on the same frame. The negations below make the sets disjoint,
--     the same trick the debuff "raid" preset already uses.
--
-- Where a flag maps to a DIFFERENT category than ours, our curation decides:
-- Barkskin and Ironbark are BIG_DEFENSIVE for Blizzard but sit in DEF_CLASS /
-- DEF_DEFAULTS for us, so BIG_DEFENSIVE feeds Defensives.
--
-- Which source feeds Defensives is a SESSION switch (RFC.useFlags,
-- `/lumennative flags off`) kept as a fallback while the group gates are open.
--
-- hotsOwn takes neither source above: it reads Blizzard's own group-window buff
-- list (Enum.CooldownViewerCategory.GroupBuff), which beats a flag string on the
-- two counts that matter. It is BOUNDED and per spec -- 7 entries for a Resto
-- Druid, 10 for a Resto Shaman -- where RAID_IN_COMBAT is "every spell carrying
-- the flag". And the player CURATES it in Blizzard's own settings, which we can
-- read back (GetHiddenGroupBuffs) and get told about (HIDDEN_GROUP_BUFFS_CHANGED),
-- so there is exactly one list instead of ours competing with theirs.
-- Measured on the PTR (Florian, 2026-08-08): the list carried every HoT we curate
-- for the Resto Druid, and for the Resto Shaman it also held a SECOND Earth Shield
-- id we never had. A Hunter gets an empty list -- that is the signal to switch the
-- category off rather than show an empty row.
local NATIVE_CATS = {
	{ key = "hotsOwn",    wl = "hot", groupBuffSource = true },
	{ key = "defensives", wl = "def", flagFilters = {
		-- Externals first; big personal defensives second, minus the externals so
		-- an aura that is both is drawn once.
		"HELPFUL|EXTERNAL_DEFENSIVE",
		"HELPFUL|BIG_DEFENSIVE|!EXTERNAL_DEFENSIVE" } },
	{ key = "debuffs",    harmful = true },
}
-- Session switch for the Defensives source: true = Blizzard's per-spell flags
-- (the default since the PTR round confirmed them), false = the curated whitelist,
-- kept only as a fallback for comparing the two while the group gates are open.
RFC.useFlags = true
local IS_NATIVE = {}
for _, c in ipairs(NATIVE_CATS) do IS_NATIVE[c.key] = true end

-- Debuff filter modes -> aura filter-string groups. "raid" is a UNION (RAID or
-- RAID_IN_COMBAT), so it declares two non-overlapping groups (the second negates
-- RAID) to avoid a double display. Groups live in ONE debuffs container; the
-- active mode's groups get maxFrameCount = N, the rest 0 (live switching, no
-- container swap).
local DEBUFF_PRESETS = {
	all         = { { key = "db_all",   filter = "HARMFUL" } },
	-- Third group: whatever the GROUP can dispel always gets an icon, even when
	-- Blizzard did not flag it raid-relevant -- otherwise the dispel highlight
	-- fires with nothing on the frame explaining it (mirror of the 12.0 path's
	-- debuffModeAccept, Florian 2026-08-07). RAID_PLAYER_DISPELLABLE means "someone
	-- in the player's raid can dispel it", not "the player can" -- the same set the
	-- highlight uses. Negations keep the three groups disjoint (no double display).
	raid        = { { key = "db_raid",  filter = "HARMFUL|RAID" },
	                { key = "db_raidc", filter = "HARMFUL|RAID_IN_COMBAT|!RAID" },
	                { key = "db_raidd", filter = "HARMFUL|RAID_PLAYER_DISPELLABLE|!RAID|!RAID_IN_COMBAT" } },
	dispellable = { { key = "db_disp",  filter = "HARMFUL|RAID_PLAYER_DISPELLABLE" } },
}
local ALL_DEBUFF_KEYS = { "db_all", "db_raid", "db_raidc", "db_raidd", "db_disp" }

-- Native aura path is available on 12.1.0+ (the "AuraContainer" frame type). On
-- 12.1 it becomes the DEFAULT automatically (no toggle); on 12.0.x it stays off
-- and the old scan path renders. `/lumennative off` is still a manual override.
local IS_121 = (select(4, GetBuildInfo()) or 0) >= 120100

local PREFIX = "|cffD4A34FLumenNative|r "
local function say(m) print(PREFIX .. m) end

local function ctxSfx() return IsInRaid() and "Raid" or "Party" end
local function currentSpecID()
	local idx = GetSpecialization and GetSpecialization()
	if not idx then return 0 end
	return (GetSpecializationInfo and GetSpecializationInfo(idx)) or 0
end

local function auras()
	local rf = ns.Lumen and ns.Lumen.db and ns.Lumen.db.profile.raidframes
	return rf and rf.auras
end
local function catCfg(key)
	local a = auras()
	return a and a[key]
end
local function catEnabled(key)
	local cat = catCfg(key)
	return cat and cat["enabled" .. ctxSfx()] and true or false
end
local function debuffMode()
	local cat = catCfg("debuffs")
	return (cat and cat["filterMode" .. ctxSfx()]) or "raid"
end

-- Whitelist -> includeSpellIDs, by type. Sourced from the curated per-spec
-- whitelist (stable ids), NEVER from live aura reads (12.1 aura.spellId is secret).
local function buildInclude(wlType)
	local include = {}
	local rf = ns.Raidframes
	if not rf or not rf.WhitelistMap then return include end
	for sid, typ in pairs(rf:WhitelistMap(currentSpecID())) do
		if typ == wlType then include[sid] = true end
	end
	return include
end

-- Blizzard's group-window buff list, resolved to the set we actually draw:
--   shown = every item minus the ones the player moved to "not shown"
--   minus anything Blizzard itself flags as a defensive, because the Defensives
--     category already draws those and it would land twice otherwise
-- Blizzard's list is the WHOLE truth here: the extras layer (whitelist type "hot"
-- on top) is gone with the tab's spell pane -- Florian 2026-08-09, and the reason
-- is the point of the rework. Two editable lists for one category is exactly the
-- state we left behind, and the second one could only ever be curated by us.
-- The stored entries are left alone, so bringing the layer back is a one-line
-- change if a spell Blizzard does not carry ever turns up.
-- Cached because syncHelpful runs per button; invalidated by the events below
-- rather than rebuilt per call (CLAUDE.md §9: no allocation in repeated paths).
-- buffCached, not buffInclude, is the early-out sentinel: an EMPTY result has to
-- stay re-askable, see the note where it is set.
local buffInclude, buffOwned, buffIcons, buffHidden, buffCached
local function buildBuffSource()
	if buffCached then return buffInclude, buffOwned end
	local owned = 0
	local CV, UA = C_CooldownViewer, C_UnitAuras
	local ok, items = false, nil
	if CV and CV.GetGroupBuffItems then ok, items = pcall(CV.GetGroupBuffItems) end
	if ok and items and #items > 0 then
		-- Before reading our own extras: a non-empty answer means the data is loaded,
		-- which is the only moment the one-time prune can tell "Blizzard has it" from
		-- "not known yet".
		local all = {}
		for _, it in ipairs(items) do all[it.spellID] = true end
		local rf = ns.Raidframes
		if rf and rf.MigrateGroupBuffs then rf:MigrateGroupBuffs(currentSpecID(), all) end
	end
	local include = {}
	-- pool = what the PREVIEW draws from, include = what the FRAMES draw. They differ
	-- by the player's hidden set on purpose, see the note below.
	local pool, nHidden = {}, 0
	if ok and items then
		local hidden = {}
		if UA and UA.GetHiddenGroupBuffs then
			local ok2, ids = pcall(UA.GetHiddenGroupBuffs)
			if ok2 and ids then for _, id in ipairs(ids) do hidden[id] = true end end
		end
		for _, it in ipairs(items) do
			owned = owned + 1
			local big, ext = false, false
			if C_UnitAuras and C_UnitAuras.AuraIsBigDefensive then
				local o, v = pcall(C_UnitAuras.AuraIsBigDefensive, it.spellID); big = (o and v) and true or false
			end
			if C_Spell and C_Spell.IsExternalDefensive then
				local o, v = pcall(C_Spell.IsExternalDefensive, it.spellID); ext = (o and v) and true or false
			end
			-- A defensive is drawn by the Defensives category, so it belongs in
			-- neither set here -- not even as preview filler.
			if not (big or ext) then
				pool[it.spellID] = true
				if hidden[it.spellID] then nHidden = nHidden + 1
				else include[it.spellID] = true end
			end
		end
	end

	-- Ordered icon list for the preview, built from the FULL list rather than the
	-- shown subset. The preview is a layout sample -- you size a row against it --
	-- and hiding everything in the Cooldown Manager would otherwise leave an empty
	-- preview whose cause is nowhere on this page (Florian, 2026-08-08). Order is
	-- Blizzard's list first, extras sorted after: DETERMINISTIC on purpose, because
	-- the preview re-renders on every slider tick and a set iterated with pairs
	-- would reshuffle mid-drag.
	local icons, seen = {}, {}
	local function push(sid)
		if seen[sid] then return end
		seen[sid] = true
		local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
		if tex then icons[#icons + 1] = tex end
	end
	if ok and items then
		for _, it in ipairs(items) do if pool[it.spellID] then push(it.spellID) end end
	end
	local rest = {}
	for sid in pairs(include) do if not seen[sid] then rest[#rest + 1] = sid end end
	table.sort(rest)
	for _, sid in ipairs(rest) do push(sid) end

	buffInclude, buffOwned, buffIcons, buffHidden = include, owned, icons, nHidden
	-- Cache only a NON-EMPTY answer, the same rule DefensivePool follows. An empty
	-- list has two very different causes that look identical here: a spec Blizzard
	-- offers nothing for (a Hunter), or a client that has not loaded its cooldown
	-- data yet -- and RFC.Enable runs one second after entering the world, well
	-- inside that window. Caching it would take the whole category down for the
	-- session with no way back except a spec change.
	-- Re-asking is cheap in exactly the case where it repeats: with no entries there
	-- is nothing to iterate, so an empty rebuild is two API calls and two empty loops.
	buffCached = (owned > 0)
	return include, owned
end

-- Icons of everything the category would draw, for the preview. Empty means the
-- preview must skip the category entirely rather than fall back to stock art.
function RFC.GroupBuffIcons()
	buildBuffSource()
	return buffIcons
end

-- True while there is nothing to draw at all: Blizzard offers no list for this
-- spec (a Hunter) AND the player added no extras. The category then goes dark
-- instead of reserving space for an empty row.
-- How many entries Blizzard's list carries for the ACTIVE spec. The Auras tab
-- needs this: a category that is switched on in the profile but has no list
-- behind it draws nothing, and saying so beats a settings page that claims
-- otherwise (a Hunter has no group-buff list at all).
-- Returns Blizzard's entry count AND the size of everything we would draw. The
-- two differ when the player has extras: no Blizzard list is not the same as
-- nothing to show, and the tab must not claim it is.
function RFC.GroupBuffState()
	local include, owned = buildBuffSource()
	local total = 0
	for _ in pairs(include) do total = total + 1 end
	return owned, total, buffHidden or 0
end

local function buffSourceEmpty()
	local include, owned = buildBuffSource()
	if owned > 0 then return false end
	return next(include) == nil
end

-- The height the icons actually have available: the HEALTH bar, not the whole
-- button, because a resource strip takes the bottom off (Raidframes _healthHeight
-- is the same value on the layout side). Falls back to the button while the bar
-- has no rect yet.
local function usableHeight(button)
	local hb = button.health
	local h = (hb and hb:GetHeight()) or 0
	if h < 2 then h = button:GetHeight() or 0 end
	return h >= 2 and h or 60
end

-- Icon size of a category. Runs through the SAME resolver as the old path
-- (Raidframes:AuraIconSize) so a given setting produces one size, not one per
-- render path. The local fallback only covers the case of that module not being
-- up yet.
local function iconSizeFor(button, key)
	local cat = catCfg(key)
	if not cat then return 16 end
	local rf = ns.Raidframes
	if rf and rf.AuraIconSize then
		local ok, size = pcall(rf.AuraIconSize, rf, cat, usableHeight(button))
		if ok and size then return size end
	end
	local sfx = ctxSfx()
	if not cat["autoFit" .. sfx] and cat["size" .. sfx] then return cat["size" .. sfx] end
	return math.max(10, math.min(40, floor(usableHeight(button) * 0.3)))
end

-- What the container is measured against. INSIDE icons follow the HEALTH BAR, so
-- a bottom-anchored row sits ON the health bar instead of covering the resource
-- strip underneath it. OUTSIDE means "beyond the frame", so those keep the button
-- as their reference -- measuring them against the health bar would push a bottom
-- row straight onto the resource bar. Same split as the old holder path.
-- The container stays PARENTED to the non-secure overlay either way (that is what
-- makes the engine's icon texture display); only the anchor target changes.
local function anchorRef(button, outside)
	if outside then return button end
	return button.health or button
end

-- Number-only duration formatter: bare seconds under a minute ("14", not "14s"),
-- then "m"/"h" above. Cached; nil if the 12.1 API is unavailable (default
-- formatter -- with unit suffix -- is then used as a graceful fallback).
local durationFormatter
local function getDurationFormatter()
	if durationFormatter ~= nil then return durationFormatter or nil end
	durationFormatter = false
	if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
		and Enum and Enum.NumericRuleFormatRounding then
		local Up   = Enum.NumericRuleFormatRounding.Up
		local Down = Enum.NumericRuleFormatRounding.Down
		local f = C_StringUtil.CreateNumericRuleFormatter()
		local ok = pcall(f.SetBreakpoints, f, {
			{ threshold = 0,    format = "%d",  step = 1, rounding = Up },
			{ threshold = 60,   format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
			{ threshold = 3600, format = "%dh", step = 1, rounding = Down, components = { { div = 3600 } } },
		})
		if ok then durationFormatter = f end
	end
	return durationFormatter or nil
end

-- Aura tooltips and the pandemic marker are SHARED across raid/group (style, not
-- geometry -- CLAUDE.md §4.1), so they carry no context suffix.
local function tipsOn(key)
	local cat = catCfg(key)
	return (cat and cat.showTooltip) and true or false
end
-- HoTs only, decided twice (Florian 2026-08-07, final): the engine lights the
-- marker inside the REFRESH window, so it needs an aura that gets re-cast before
-- it expires. A defensive or a major cooldown is cast once and runs out -- the
-- switch would sit there and never do anything, which is worse than not having it.
local PANDEMIC_CATS = { hotsOwn = true }
local function pandemicOn(key)
	if not PANDEMIC_CATS[key] then return false end
	local cat = catCfg(key)
	return (cat and cat.pandemic) and true or false
end

-- Per-category duration-text options (per context).
local function durOptsFor(key)
	local cat, sfx = catCfg(key), ctxSfx()
	if not cat then return true, 12, "shadow", 60 end
	local on = cat["showDuration" .. sfx]
	if on == nil then on = true end
	local maxSec = cat["durationMax" .. sfx]
	if maxSec == nil then maxSec = 60 end
	return on, cat["durationSize" .. sfx] or 12, cat["durationOutline" .. sfx] or "shadow", maxSec
end

-- "Only show the number once it matters." A 58-minute Earth Shield reads as "58m"
-- -- three characters at a size chosen for "8", hanging far off a 16px icon, and
-- shrinking the font until it fits makes the numbers that DO matter unreadable
-- (Florian 2026-08-09).
-- The remaining duration is secret, so the decision cannot be ours: we hand the
-- engine a colour curve whose ALPHA is 0 above the threshold and 1 below it, keyed
-- to RemainingDuration. It evaluates that internally, exactly like the dispel type
-- curve does for its (also secret) colour. Step type, so it flips rather than
-- fades. One curve per threshold value, built once.
-- ALWAYS built, including for the "no threshold" case -- and that is the point:
-- a re-bind that simply LEAVES OUT the colour curve does not clear the one the
-- binding already carries, so switching back to Always kept the number invisible
-- (Florian 2026-08-09, H3). The zero curve is a single opaque point that
-- overwrites the old one.
local durCurves = {}
local function durationCurve(maxSec)
	if durCurves[maxSec] then return durCurves[maxSec] end
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType) then return nil end
	local c = C_CurveUtil.CreateColorCurve()
	c:SetType(Enum.LuaCurveType.Step)
	c:AddPoint(0, CreateColor(1, 1, 1, 1))
	if maxSec > 0 then c:AddPoint(maxSec + 1, CreateColor(1, 1, 1, 0)) end
	durCurves[maxSec] = c
	return c
end

-- Every aura button the engine has created for us, as { button, fs, key, ring }.
-- Settings changes are applied to this list (duration text, tooltips, pandemic
-- marker, icon size) instead of rebuilding the containers.
local auraBtns = {}

-- Once auras are secret, the aura buttons and their regions belong to the ENGINE:
-- styling the duration FontString from our (tainted) code is a forbidden access,
-- and it is a hard error, not a silent no-op -- hiding a defensive mid-fight threw
-- exactly there (Florian 2026-08-09). So every LOOK change waits for the end of the
-- fight, and this flag remembers that one is owed.
-- The DATA side deliberately does NOT wait: pushing candidate filters is legal in
-- combat, which is why hiding a buff in Blizzard's own panel takes effect
-- immediately, and why the icon still disappears the moment you click.
local pendingRefresh = false

-- Style one duration fontstring from its category's options + (re)register or
-- clear the engine binding for the on/off state. An unstyled FontString hard-errors
-- in the engine's SetText path, so the font is set before the binding is attached.
local function applyDurStyle(e)
	local button, fs = e.button, e.fs
	local on, size, outline, maxSec = durOptsFor(e.key)
	local function style()
		if ns.Raidframes and ns.Raidframes.StyleTextFont then
			ns.Raidframes:StyleTextFont(fs, size, outline)
		end
	end
	style()
	pcall(fs.SetTextColor, fs, 1, 1, 1)   -- VertexColor is a secret aspect once bound
	if on then
		-- The threshold lives in the BINDING, so a change to it needs a re-bind --
		-- unlike size and outline, which are pure font state. Blizzard's own comment
		-- asks for the active binding to be cleared first.
		if e.durBound and e.durMax ~= maxSec then
			pcall(button.ClearDurationText, button)
			e.durBound = false
		end
		if not e.durBound then
			local fmt = getDurationFormatter()
			-- 68914 renamed this option key from `formatter` to `textFormatter`, and
			-- the engine simply IGNORES an unknown key -- so passing the old name on a
			-- new build silently falls back to the default formatter and the text reads
			-- "14s" again instead of "14". No error to notice it by, hence both keys:
			-- each build reads the one it knows.
			local opts
			if fmt then opts = { textFormatter = fmt, formatter = fmt } else opts = {} end
			local curve = durationCurve(maxSec or 0)
			if curve and Enum and Enum.DurationTextBindingProperty then
				opts.textColor = { curve = curve,
					property = Enum.DurationTextBindingProperty.RemainingDuration }
			end
			-- Bound ONCE, not on every settings change: SetDurationText re-arms the
			-- binding and re-stamps the secret aspects, and Blizzard's own comment
			-- warns that replacing an active binding needs the old one disabled first.
			-- Size/outline are pure font state and do not need a re-bind.
			if pcall(button.SetDurationText, button, fs, opts) then
				e.durBound, e.durMax = true, maxSec
			end
		end
		-- Style AGAIN after the binding: taking the string over resets it to the
		-- font object's size, which ate every size change (Florian 2026-08-06).
		style()
		fs:Show()
	else
		if e.durBound then
			pcall(button.ClearDurationText, button)
			e.durBound = false
		end
		fs:Hide()
	end
end

-- ---------------------------------------------------------------------------
--  Pandemic marker (12.1 build 69111+)
--  A pulsing red wash over the icon while re-applying the aura would carry time
--  over -- WoW's refresh window. The ENGINE owns when it shows: AddPandemicRegion
--  stamps SecretAspect.Shown on the region and drives it from the aura's base vs.
--  extended duration, both of which are secret for other players. That is the
--  whole reason this is an engine call and not our own timer.
--  Three consequences we design around:
--   * once registered we may no longer Show/Hide the mark -- the OFF state is
--     therefore alpha 0, not hidden;
--   * the blink animation OWNS the frame's alpha, so it has to be stopped before
--     that alpha 0 sticks;
--   * a registered mark makes the engine run an OnUpdate on that button while an
--     aura with a refresh window sits there, so we register LAZILY: a category
--     that never had the option on never pays for it.
-- ---------------------------------------------------------------------------
-- Bring one button's pandemic marker in line with its category's option.
local function applyPandemic(e)
	local on = pandemicOn(e.key)
	if not e.mark then
		if not on then return end                         -- never enabled -> never built
		if not e.button.AddPandemicRegion then return end  -- pre-69111 build: no API
		local rf = ns.Raidframes
		if not (rf and rf.AuraPandemicMark) then return end
		-- Same builder the preview uses, so both paths draw the identical marker.
		local mark = rf:AuraPandemicMark(e.button, e.level or (e.button:GetFrameLevel() + 3))
		-- Hidden BEFORE it is handed over: afterwards its visibility belongs to the
		-- engine, and a fresh frame is shown by default (one frame of red flash).
		mark:Hide()
		if pcall(e.button.AddPandemicRegion, e.button, mark) then e.mark = mark end
		return
	end
	if on then
		if e.mark.blink then e.mark.blink:Play() end
	else
		if e.mark.blink then e.mark.blink:Stop() end      -- release the alpha first
		pcall(e.mark.SetAlpha, e.mark, 0)
	end
end

-- Tooltips: the native button shows the aura tooltip on hover by itself, so the
-- option is expressed as "does this icon accept mouse motion at all". Clicks are
-- disabled outright -- an aura icon must never swallow a click-cast on the unit
-- button underneath it (same rule as the old icon path).
local function applyMouse(e)
	pcall(e.button.SetMouseClickEnabled, e.button, false)
	pcall(e.button.SetMouseMotionEnabled, e.button, tipsOn(e.key))
end

-- Re-apply every per-button option (called on any aura settings change): duration
-- text, tooltip/mouse, pandemic marker. Dead entries are swapped out as we go.
-- Deferred to the end of combat, both of them: see the note at pendingRefresh.
function RFC.RefreshOptions()
	if InCombatLockdown() then pendingRefresh = true; return end
	for i = #auraBtns, 1, -1 do
		local e = auraBtns[i]
		if e.fs and e.button then
			applyDurStyle(e)
			applyMouse(e)
			applyPandemic(e)
		else
			auraBtns[i] = auraBtns[#auraBtns]; auraBtns[#auraBtns] = nil
		end
	end
end

-- The per-button initializer (runs once per pre-created button). Builds our own
-- child regions and registers them; matches the old icon look (1px black frame,
-- cropped icon, cooldown swipe) and the duration text.
local function makeInitializer(size, key)
	return function(button)
		RFC.stat.buttons = RFC.stat.buttons + 1
		button:SetSize(size, size) -- an unsized aura button renders nothing

		local bg = button:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(button)
		bg:SetColorTexture(0, 0, 0, 1)

		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0)  -- 64px art at ~16px
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button:SetIcon(icon)

		local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		cd:SetAllPoints(icon)
		cd:SetReverse(true) -- aura swipe: icon stays bright, darkens toward expiry
		cd:SetDrawEdge(false)
		cd:SetHideCountdownNumbers(true) -- our own text renders the number
		button:SetDurationCooldown(cd)

		-- Duration text rides a carrier frame ABOVE the swipe (else it greys out).
		local textLayer = CreateFrame("Frame", nil, button)
		textLayer:SetAllPoints(button)
		textLayer:SetFrameLevel(cd:GetFrameLevel() + 1)
		local dt = textLayer:CreateFontString(nil, "OVERLAY")
		-- ONE anchor point: pinned on two corners the string has a fixed width, so a
		-- number larger than the icon came out ellipsised. A single point lets it
		-- size itself and overhang instead.
		-- StyleTextFont additionally clears any width the engine may have set and
		-- re-centres the justify, which is what kept pulling the number left.
		dt:SetPoint("CENTER", button, "CENTER", 0, 0)

		local e = { button = button, fs = dt, key = key,
			level = textLayer:GetFrameLevel() + 1 }  -- pandemic ring rides above the text layer
		auraBtns[#auraBtns + 1] = e
		applyDurStyle(e)
		applyMouse(e)
		applyPandemic(e)
	end
end

-- Growth keyword -> native flow directions (h, v) + whether it's a vertical
-- column (forced via a one-element row width). Centered-anchor parity is a
-- follow-up; corner anchors + outside placement + offsets work.
local function growthDirs(grow)
	local FD = AnchorUtil.FlowDirection
	if grow == "LEFT" then return FD.Left, FD.Down, false
	elseif grow == "UP" then return FD.Right, FD.Up, true
	elseif grow == "DOWN" then return FD.Right, FD.Down, true end
	return FD.Right, FD.Down, false -- RIGHT (default)
end

local function insetFor(point)
	local I, x, y = 1, 0, 0
	if strfind(point, "LEFT") then x = I elseif strfind(point, "RIGHT") then x = -I end
	if strfind(point, "TOP") then y = -I elseif strfind(point, "BOTTOM") then y = I end
	return x, y
end

-- "Outside" placement: push the row/column beyond the anchored edge, perpendicular
-- to the growth axis (mirrors the old positionAuraIcons _outside).
local AURA_OUT_GAP = 2
local function outsideOffset(anchor, grow, size)
	local horiz = (grow == "RIGHT" or grow == "LEFT")
	local ox, oy = 0, 0
	if horiz then
		if strfind(anchor, "TOP") then oy = size + AURA_OUT_GAP
		elseif strfind(anchor, "BOTTOM") then oy = -(size + AURA_OUT_GAP) end
	else
		if strfind(anchor, "LEFT") then ox = -(size + AURA_OUT_GAP)
		elseif strfind(anchor, "RIGHT") then ox = size + AURA_OUT_GAP end
	end
	return ox, oy
end

-- Read a category's layout params for the current context.
local function readLayout(button, key)
	local cat, sfx = catCfg(key), ctxSfx()
	return {
		anchor  = (cat and cat["anchor" .. sfx]) or "BOTTOMLEFT",
		grow    = (cat and cat["grow" .. sfx]) or "RIGHT",
		spacing = (cat and cat["spacing" .. sfx]) or 2,
		maxN    = (cat and cat["maxIcons" .. sfx]) or 5,
		offX    = (cat and cat["offX" .. sfx]) or 0,
		offY    = (cat and cat["offY" .. sfx]) or 0,
		outside = (cat and cat["outside" .. sfx]) or false,
		size    = iconSizeFor(button, key),
	}
end

-- The container layout setters were renamed in 12.1 build 68914: the
-- SetAuraLayout* family became SetFlowLayout*, and RowWidth generalized into
-- MaximumLineSize. Signatures are unchanged, so one name table resolves both
-- generations per container -- the PTR moved three builds in ten days, and an
-- addon that hard-errors on the older name is worse than one that degrades.
-- The pair is {new, old}; a build carrying neither leaves that knob alone.
local LAYOUT_METHODS = {
	anchor = { "SetFlowLayoutAnchorPoint",     "SetAuraLayoutAnchorPoint" },
	growth = { "SetFlowLayoutGrowthDirection", "SetAuraLayoutGrowthDirection" },
	line   = { "SetFlowLayoutMaximumLineSize", "SetAuraLayoutRowWidth" },
}
local function layoutCall(container, which, a, b)
	local names = LAYOUT_METHODS[which]
	local fn = container[names[1]] or container[names[2]]
	if fn then fn(container, a, b) end
end

-- Container-level layout (anchor / growth / position) -- shared by every group
-- in the container. `ref` is the frame the icons are measured against (anchorRef),
-- which is NOT necessarily the container's parent. Live-settable.
local function applyContainerLayout(container, ref, lo)
	local ix, iy = insetFor(lo.anchor)
	local ox, oy = 0, 0
	if lo.outside then ox, oy = outsideOffset(lo.anchor, lo.grow, lo.size) end
	local hDir, vDir, column = growthDirs(lo.grow)
	container:ClearAllPoints()
	container:SetPoint(lo.anchor, ref, lo.anchor, ix + lo.offX + ox, iy + lo.offY + oy)
	layoutCall(container, "anchor", lo.anchor)
	layoutCall(container, "growth", hDir, vDir)
	-- Columns: 68914 added a real flow AXIS, so a vertical growth direction can
	-- say "lines are columns" instead of being faked by capping the line width to
	-- one icon. Where the axis exists it owns the decision and the line size stays
	-- unlimited; on older builds we fall back to the width cap as before.
	local axes = AnchorUtil and AnchorUtil.FlowLayoutAxis
	if axes and container.SetFlowLayoutAxis then
		container:SetFlowLayoutAxis(column and axes.Vertical or axes.Horizontal)
		layoutCall(container, "line", nil)
	else
		layoutCall(container, "line", column and (lo.size + 0.5) or nil)
	end
end

-- Per-group size/spacing/count. The group must already exist.
local function applyGroupLayout(container, gkey, lo, maxN)
	container:SetAuraGroupMaxFrameCount(gkey, maxN)
	container:SetAuraGroupLayout(gkey, {
		elementWidth = lo.size, elementHeight = lo.size,
		elementSpacingX = lo.spacing, elementSpacingY = lo.spacing,
	})
end

-- Lust lockouts (Exhaustion/Sated/…) never belong on a raid frame: the tracker icon
-- already says the group is locked out, and the debuff row would carry it on every
-- member for ten minutes. The old scan path filtered them by id; the native path
-- needs excludeSpellIDs for the same result.
-- This works despite the rule that identity filters are refused for HARMFUL auras on
-- a friendly unit (Blizzard's anti-abuse gate, so nobody can rebuild boss debuffs as
-- exact readouts): the gate lets NeverSecret spells through, and the lockouts are
-- NeverSecret. Blizzard names this exact case in Blizzard_AuraContainerUtil -- "this
-- allows noisy debuffs (Exhaustion/Sated) to be filtered out on friendly units".
-- Confirmed present under the native path before the fix (Florian, PTR 2026-08-08).
local function debuffCandidateFilters()
	local ids = ns.LustLockoutIDs
	if not ids then return nil end
	local excl = {}
	for i = 1, #ids do excl[ids[i]] = true end
	return { excludeSpellIDs = excl }
end

-- Declare a debuff group on demand (engine groups are add-only) + configure it.
local function ensureDebuffGroup(container, gkey, filter, lo, maxN)
	container._dbGroups = container._dbGroups or {}
	if not container._dbGroups[gkey] then
		container._dbGroups[gkey] = true
		RFC.stat.groups = RFC.stat.groups + 1
		container:AddAuraGroup(gkey, filter, {
			maxFrameCount    = maxN,
			candidateFilters = debuffCandidateFilters(),
			initializeFrame  = makeInitializer(lo.size, "debuffs"),
		})
	end
	applyGroupLayout(container, gkey, lo, maxN)
end

-- Declare + reconcile the sources of ONE helpful category. The whitelist group and
-- the flag group(s) all live in the same container and only one SIDE carries a
-- frame budget at a time: switching the source is a max-frame-count flip, the same
-- move the debuff modes make above. So there is no container churn, no
-- re-initialization of aura buttons that already exist, and the switch works in a
-- live raid -- which is the point, since the two sources can only be judged against
-- each other.
-- Every group runs through the SAME initializer, so both sources look identical and
-- only the SET of icons differs.
local function flagGroupKey(key, i) return key .. "_f" .. i end

-- What the player took OUT of a flag-fed category (Raidframes owns the data, see
-- its "Defensives -- the SHOWN / HIDDEN list" block). A flag set cannot be
-- enumerated, so excluding by id is the only way to drop a single aura out of it.
-- Kept as our OWN copy rather than handing the profile table to the engine: the
-- engine holds on to whatever table it is given, and the API promises nothing
-- about noticing an edit made behind its back -- every change goes in as a new
-- table through RFC.RefreshDefensiveSource.
local defExcl, defExclArg
local function defExcludeSet()
	if defExcl then return defExcl end
	local rf = ns.Raidframes
	local h = (rf and rf.DefensiveHidden) and rf:DefensiveHidden() or nil
	local out = {}
	if h then for sid in pairs(h) do out[sid] = true end end
	defExcl = out
	return out
end
-- The argument table is cached too: a relayout pushes it once per group per live
-- button, and building 40 identical tables for a raid would be allocation in a
-- path that runs on every layout change. We never mutate it -- a change replaces
-- both tables.
local function defExcludeArg()
	if not defExclArg then defExclArg = { excludeSpellIDs = defExcludeSet() } end
	return defExclArg
end

local function syncHelpful(container, c, lo)
	local key, filters = c.key, c.flagFilters
	local useFlags = (RFC.useFlags and filters) and true or false
	-- The group-buff category has ONE group and no source switch: the ids come from
	-- Blizzard's list, the filter string only narrows it to auras WE applied (without
	-- PLAYER a second druid's Rejuvenation would show up as ours).
	if c.groupBuffSource then
		if not container._helpfulGroups then
			container._helpfulGroups = true
			RFC.stat.groups = RFC.stat.groups + 1
			container:AddAuraGroup(key, "HELPFUL|PLAYER", {
				maxFrameCount    = lo.maxN,
				candidateFilters = { includeSpellIDs = buildBuffSource() },
				initializeFrame  = makeInitializer(lo.size, key),
			})
		end
		applyGroupLayout(container, key, lo, lo.maxN)
		return
	end
	if not container._helpfulGroups then
		container._helpfulGroups = true
		RFC.stat.groups = RFC.stat.groups + 1
		container:AddAuraGroup(key, "HELPFUL", {
			maxFrameCount    = lo.maxN,
			candidateFilters = { includeSpellIDs = buildInclude(c.wl) },
			initializeFrame  = makeInitializer(lo.size, key),
		})
		for i = 1, (filters and #filters or 0) do
			-- Declared with the full budget and corrected below, the way the debuff
			-- groups are: a group that only ever sees 0 is untested ground.
			RFC.stat.groups = RFC.stat.groups + 1
			container:AddAuraGroup(flagGroupKey(key, i), filters[i], {
				maxFrameCount    = lo.maxN,
				candidateFilters = defExcludeArg(),
				initializeFrame  = makeInitializer(lo.size, key),
			})
		end
		container._defCF = defExcludeArg()   -- the groups were born with this set
	end
	applyGroupLayout(container, key, lo, useFlags and 0 or lo.maxN)
	-- Re-push the hide list when it CHANGED, not on every reconcile: a profile
	-- switch or an import replaces the stored set behind a container that is
	-- already built, and its groups would otherwise keep the old exclusions --
	-- but pushing it unconditionally is far from free. SetAuraGroupCandidateFilters
	-- has no equality check of its own and ends in UpdateAllAuras(), i.e. a full
	-- re-parse of every aura on that unit, per group. A Relayout in a 40-man was
	-- paying 80 of those for a set that had not moved.
	-- Identity is the right test, not a deep compare: defExcludeArg hands out a
	-- CACHED table that is never mutated -- a change replaces it (see the note there).
	local excl = defExcludeArg()
	local push = (container._defCF ~= excl)
	for i = 1, (filters and #filters or 0) do
		local gk = flagGroupKey(key, i)
		applyGroupLayout(container, gk, lo, useFlags and lo.maxN or 0)
		if push then
			RFC.stat.filterPush = RFC.stat.filterPush + 1
			pcall(container.SetAuraGroupCandidateFilters, container, gk, excl)
		end
	end
	if push then container._defCF = excl end
end

-- Reconcile the debuffs container to the active filter mode: the active preset's
-- groups get maxFrameCount = N, every other already-declared debuff group 0.
local function syncDebuffs(container, ref, lo)
	local active = {}
	for _, g in ipairs(DEBUFF_PRESETS[debuffMode()] or DEBUFF_PRESETS.raid) do
		active[g.key] = true
		ensureDebuffGroup(container, g.key, g.filter, lo, lo.maxN)
	end
	for _, gkey in ipairs(ALL_DEBUFF_KEYS) do
		if not active[gkey] and container._dbGroups and container._dbGroups[gkey] then
			container:SetAuraGroupMaxFrameCount(gkey, 0)
		end
	end
	applyContainerLayout(container, ref, lo)
end

-- ---------------------------------------------------------------------------
--  Dispel overlay, native (12.1)
--  12.1 denies the aura SCAN to tainted callers, and that scan was how the old
--  path answered "is a dispellable debuff up, and of which type". The native
--  container answers both without us reading anything: a group filtered to
--  dispellable harmful auras shows its single button exactly while such an aura
--  sits on the unit, and AddDispelTypeTexture colours OUR textures through the
--  same colour curve the old path fed to GetAuraDispelTypeColor — the engine
--  resolves the secret type internally.
--  Both display modes are covered. The OVERLAY mode is a translucent wash plus
--  four edges over the frame. The RECOLOUR mode reaches the same result the old
--  path got from tinting the bar: a texture anchored to the health bar's FILL
--  region, which covers exactly the filled portion and follows it. Level-tied to
--  the health frame at ARTWORK sublevel 2 — above the fill, below heal absorb and
--  prediction, which live a level up.
-- ---------------------------------------------------------------------------
-- One container per MODE, because the per-button initializer runs once at frame
-- creation and cannot be re-written afterwards (post-creation writes to an aura
-- button are denied while auras are secret). Switching the mode enables the other
-- container instead of rebuilding this one.
local DISPEL_MODES = { overlay = "dispel_ov", recolor = "dispel_bar" }

local function rfCfg()
	return ns.Lumen and ns.Lumen.db and ns.Lumen.db.profile.raidframes
end
local function dispelOn()
	local d = rfCfg()
	return (d and d.dispelEnabled) and true or false
end
local function dispelMode()
	local d = rfCfg()
	return (d and d.dispelMode == "recolor") and "recolor" or "overlay"
end

-- The engine colours whatever textures we register. CustomAsset with NO asset map
-- leaves our own texture in place and takes only the colour (every other style
-- would stamp a Blizzard border atlas over it).
local function initDispelFrame(mode, w, h, health)
	return function(button)
		RFC.stat.buttons = RFC.stat.buttons + 1
		button:SetSize(w, h)
		local rf = ns.Raidframes
		local edgeCurve, fillCurve = rf:DispelCurves()
		local function reg(tex, curve)
			pcall(button.AddDispelTypeTexture, button, tex, {
				style = Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset,
				customDispelColorCurve = curve,
			})
		end
		pcall(button.SetMouseClickEnabled, button, false)
		pcall(button.SetMouseMotionEnabled, button, false)

		if mode == "recolor" then
			-- Sort with the health bar's own regions, not above them.
			pcall(button.SetFrameLevel, button, health:GetFrameLevel())
			local tex = button:CreateTexture(nil, "ARTWORK", nil, 2)
			tex:SetColorTexture(1, 1, 1, 1)
			-- Anchor to the bar's fill REGION, not the bar frame: the fill shrinks
			-- with the health, so the tint covers what is actually filled.
			local target = health
			if health.GetStatusBarTexture then target = health:GetStatusBarTexture() or health end
			tex:SetAllPoints(target)
			reg(tex, edgeCurve)   -- opaque curve: this REPLACES the bar colour
			return
		end

		local fill = button:CreateTexture(nil, "ARTWORK")
		fill:SetAllPoints(button)
		fill:SetColorTexture(1, 1, 1, 1)
		reg(fill, fillCurve or edgeCurve)
		local function edge(p1, p2, ww, hh)
			local t = button:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(1, 1, 1, 1)
			t:SetPoint(p1); t:SetPoint(p2)
			if ww then t:SetWidth(ww) else t:SetHeight(hh) end
			reg(t, edgeCurve)
		end
		edge("TOPLEFT", "TOPRIGHT", nil, 2)
		edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
		edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
		edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
	end
end

-- Attach / reconcile the dispel containers on one button: the container of the
-- ACTIVE mode is (built and) enabled, the other one is switched off. The overlay
-- one stays BELOW the aura containers so icons and duration text are never
-- covered; the recolour one sorts with the health bar (see the initializer).
local function syncDispel(button, parent)
	button._rfc = button._rfc or {}
	local mode = dispelMode()
	local on = dispelOn()
	-- Whatever is not the active mode goes quiet.
	for m, key in pairs(DISPEL_MODES) do
		local c = button._rfc[key]
		if c and (not on or m ~= mode) then c:SetEnabled(false); c:Hide() end
	end
	if not on then return end

	local key = DISPEL_MODES[mode]
	local container = button._rfc[key]
	local w, h = button:GetWidth() or 0, button:GetHeight() or 0
	if w < 2 or h < 2 then return end
	-- Scope comes from Raidframes so the native and the scan path cannot drift.
	local filter = (ns.Raidframes and ns.Raidframes.DispelFilter
		and ns.Raidframes:DispelFilter()) or "HARMFUL|RAID"
	if not container then
		local health = button.health or button
		local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
		if not ok or not c then return end
		container = c
		button._rfc[key] = container
		pcall(container.SetFrameLevel, container, parent:GetFrameLevel())
		local built = pcall(function()
			container:SetSize(1, 1)
			container:ClearAllPoints()
			container:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
			layoutCall(container, "anchor", "TOPLEFT")
			RFC.stat.groups = RFC.stat.groups + 1
			container:AddAuraGroup(key, filter, {
				maxFrameCount   = 1,
				initializeFrame = initDispelFrame(mode, w, h, health),
			})
			container._dispelFilter = filter
			local u = button.unit or button:GetAttribute("unit")
			if u then container:SetUnit(u) end
			container:SetEnabled(true)
			container:UpdateAllAuras()
		end)
		if not built then button._rfc[key] = nil end
		return
	end
	-- Live changes: the filter mode swaps through the group (no container churn),
	-- the size follows the frame.
	if container._dispelFilter ~= filter and container.SetAuraGroupFilterString then
		if pcall(container.SetAuraGroupFilterString, container, key, filter) then
			container._dispelFilter = filter
		end
	end
	pcall(container.SetAuraGroupLayout, container, key, { elementWidth = w, elementHeight = h })
	container:Show(); container:SetEnabled(true)
	pcall(container.UpdateAllAuras, container)
end

-- True while the native path draws the dispel overlay -> the old scan-driven one
-- stays off (it cannot run on 12.1 anyway, see ns.AurasRestricted).
function RFC.OwnsDispel()
	return RFC.enabled and true or false
end

local function forEachLiveButton(fn)
	local rf = ns.Raidframes
	if not (rf and rf.GetLiveButtons) then return end
	for _, btn in ipairs(rf:GetLiveButtons()) do fn(btn) end
end

-- Create + configure ONE category's container on a button. OOC only (containers
-- cannot be created in combat). Idempotent per category. `c` = NATIVE_CATS entry.
local function attachCat(button, parent, c)
	local key = c.key
	button._rfc = button._rfc or {}
	if button._rfc[key] then return button._rfc[key] end

	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not container then return nil end -- not 12.1 -> silently inert
	button._rfc[key] = container
	-- Two levels above the overlay: the dispel container sits AT the overlay level,
	-- so icons and their duration text always draw over the dispel wash — the
	-- layering standard the old holder path follows as well.
	pcall(container.SetFrameLevel, container, parent:GetFrameLevel() + 2)

	local lo  = readLayout(button, key)
	local ref = anchorRef(button, lo.outside)
	local built = pcall(function()
		container:SetSize(1, 1)
		if c.harmful then
			syncDebuffs(container, ref, lo)
		else
			syncHelpful(container, c, lo)
			applyContainerLayout(container, ref, lo)
		end
		local u = button.unit or button:GetAttribute("unit")
		if u then container:SetUnit(u) end
		container:SetEnabled(true)
		container:UpdateAllAuras()
	end)

	if not built then button._rfc[key] = nil end
	return button._rfc[key]
end

-- Attach every ENABLED native category on a button (idempotent).
-- Enabled in the profile AND with something to draw. The second half only ever
-- says no for the group-buff category on a spec Blizzard has no list for.
local function catActive(c)
	if not catEnabled(c.key) then return false end
	if c.groupBuffSource and buffSourceEmpty() then return false end
	return true
end

function RFC.Attach(button)
	if not button or InCombatLockdown() then return end
	local parent = button.overlay or button
	for _, c in ipairs(NATIVE_CATS) do
		if catActive(c) then attachCat(button, parent, c) end
	end
	syncDispel(button, parent)
end

-- Re-point every category container's unit when the header (re)assigns a button.
-- Same-unit early-out avoids a raid-wide reparse storm on roster re-processing.
function RFC.SetUnit(button, unit)
	if not (button and button._rfc) then return end
	if button._rfcUnit == unit then return end
	button._rfcUnit = unit
	if not unit then return end
	for _, c in pairs(button._rfc) do
		-- Direct pcalls (no closure): this runs per container inside the secure
		-- header's unit-attribute hook, which fires on roster shuffles IN COMBAT --
		-- a wrapper closure here would allocate garbage in a hot path (CLAUDE.md §9).
		pcall(c.SetUnit, c, unit)
		pcall(c.UpdateAllAuras, c)
	end
end

-- Reconcile all live buttons: attach newly-enabled categories, hide disabled
-- ones, re-apply layout + resize the rest (called on any aura settings change).
function RFC.Relayout()
	if not RFC.enabled then return end
	if InCombatLockdown() then pendingRefresh = true; return end
	-- Drop the cached hide list first: a profile switch or an import lands here
	-- (UpdateLayout -> Relayout) and brings a different set with it.
	defExcl, defExclArg = nil, nil
	local sizes = {}
	forEachLiveButton(function(btn)
		if InCombatLockdown() then return end
		local parent = btn.overlay or btn
		for _, c in ipairs(NATIVE_CATS) do
			local on = catActive(c)
			local container = btn._rfc and btn._rfc[c.key]
			if on then
				if not container then
					container = attachCat(btn, parent, c)
					if container then RFC.SetUnit(btn, btn.unit or btn:GetAttribute("unit")) end
				end
				if container then
					local lo  = readLayout(btn, c.key)
					local ref = anchorRef(btn, lo.outside)
					sizes[c.key] = lo.size
					container:Show(); container:SetEnabled(true)
					if c.harmful then
						pcall(syncDebuffs, container, ref, lo)
					else
						pcall(function()
							applyContainerLayout(container, ref, lo)
							syncHelpful(container, c, lo)
						end)
					end
				end
			elseif container then
				container:SetEnabled(false); container:Hide()
			end
		end
		syncDispel(btn, parent)
	end)
	-- Resize existing aura buttons to their category's current icon size.
	for _, e in ipairs(auraBtns) do
		if e.button and sizes[e.key] then pcall(e.button.SetSize, e.button, sizes[e.key], sizes[e.key]) end
	end
end

-- True while the native path owns category `key` -> the old holder stays suppressed.
function RFC.Suppresses(key)
	return RFC.enabled and IS_NATIVE[key] ~= nil
end

-- Audit read-out for /lumenprof: declared groups, containers currently living on
-- live buttons, aura buttons the engine created for us (= how many times our
-- initializer ran), and candidate-filter pushes. See the RFC.stat block up top
-- for why these cannot be derived from timings.
function RFC.Stats()
	local containers, buttons = 0, 0
	forEachLiveButton(function(btn)
		buttons = buttons + 1
		if btn._rfc then for _ in pairs(btn._rfc) do containers = containers + 1 end end
	end)
	return RFC.stat.groups, containers, RFC.stat.buttons, RFC.stat.filterPush, buttons, #auraBtns
end

function RFC.Enable(quiet)
	if InCombatLockdown() then if not quiet then say("|cffff5555Out of combat only.|r") end return end
	RFC.enabled = true
	forEachLiveButton(function(btn)
		RFC.Attach(btn)
		RFC.SetUnit(btn, btn.unit or btn:GetAttribute("unit"))
		if btn._rfc then for _, c in pairs(btn._rfc) do c:SetEnabled(true); c:Show() end end
		-- ... except the dispel container of the mode that is NOT active: the blanket
		-- show above does not know about modes, syncDispel does.
		syncDispel(btn, btn.overlay or btn)
	end)
	if ns.Raidframes and ns.Raidframes.RefreshAuras then ns.Raidframes:RefreshAuras() end
	if not quiet then say("Native auras |cff44ff44ON|r (Buffs · Defensives · Debuffs).") end
end

-- Auto-default: on 12.1 turn native on by itself (once, after login), so no
-- manual toggle is needed. RFC.enabled=true also makes buttons assigned later
-- attach via their unit-change hook. A manual `/lumennative off` still overrides
-- for the session. On 12.0.x this never fires -> old path stays.
local autoDone = false
local autoFrame = CreateFrame("Frame")
autoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- The group-buff set changes without any settings change of ours: the player edits
-- it in Blizzard's own panel, or the spec (and with it the whole list) changes.
-- Pushing new candidate filters keeps the existing aura buttons -- no container
-- rebuild, so this is legal while a container already lives on a frame.
function RFC.RefreshBuffSource()
	buffInclude, buffOwned, buffIcons = nil, nil, nil
	-- The preview caches its icons per spec, and this can change without one.
	local rf = ns.Raidframes
	if rf and rf._InvalidatePreviewIcons then pcall(rf._InvalidatePreviewIcons) end
	if not RFC.enabled then return end
	local include = buildBuffSource()
	forEachLiveButton(function(btn)
		local container = btn._rfc and btn._rfc.hotsOwn
		if container then
			RFC.stat.filterPush = RFC.stat.filterPush + 1
			pcall(container.SetAuraGroupCandidateFilters, container, "hotsOwn",
				{ includeSpellIDs = include })
		end
	end)
	-- An empty source has to take the whole category down (or bring it back), and
	-- that is an attach/detach -- Relayout owns it, and it is out-of-combat only.
	if not InCombatLockdown() then RFC.Relayout() end
	-- The settings page reports how many entries are hidden, so it goes stale the
	-- moment the player edits Blizzard's panel with the shell open beside it --
	-- which is exactly how they will do it.
	local S = ns.Shell
	if S and S.RenderContent and S._frame and S._frame:IsShown() then
		pcall(S.RenderContent, S, true)
	end
end

-- The player took a defensive off the list (or put it back). Same move as the
-- buff source above: push new candidate filters instead of rebuilding anything,
-- so this is legal with containers already sitting on live frames -- and it works
-- in combat, because nothing is created or destroyed.
function RFC.RefreshDefensiveSource()
	defExcl, defExclArg = nil, nil
	if not RFC.enabled then return end
	local arg = defExcludeArg()
	local filters
	for _, c in ipairs(NATIVE_CATS) do if c.key == "defensives" then filters = c.flagFilters end end
	if not filters then return end
	forEachLiveButton(function(btn)
		local container = btn._rfc and btn._rfc.defensives
		if container then
			for i = 1, #filters do
				RFC.stat.filterPush = RFC.stat.filterPush + 1
				pcall(container.SetAuraGroupCandidateFilters, container,
					flagGroupKey("defensives", i), arg)
			end
			-- Record what the container now carries, or the next reconcile would push
			-- the very same set again (syncHelpful compares against this).
			container._defCF = arg
		end
	end)
end

-- pcall per event: this file loads on 12.0.7 as well, where RegisterEvent on an
-- event the client does not know is a hard error, not a no-op.
for _, e in ipairs({ "HIDDEN_GROUP_BUFFS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
	"COOLDOWN_VIEWER_DATA_LOADED" }) do
	pcall(autoFrame.RegisterEvent, autoFrame, e)
end
autoFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
autoFrame:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_REGEN_ENABLED" then
		if pendingRefresh then
			pendingRefresh = false
			RFC.Relayout()
			RFC.RefreshOptions()
		end
		return
	end
	if event ~= "PLAYER_ENTERING_WORLD" then
		-- PLAYER_SPECIALIZATION_CHANGED carries a unit and fires for OTHER group
		-- members too. Only our own spec can change the group-buff list, and the
		-- work behind this is not small: a rebuild of the source, a candidate-filter
		-- push to every live button and a full Relayout over all 40 of them. Without
		-- the filter every stranger's respec paid for all of that. Raidframes and
		-- ClickCast carry the same guard (2026-07-03 audit, A4).
		if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
		if IS_121 then RFC.RefreshBuffSource() end
		return
	end
	if autoDone or not IS_121 then return end
	autoDone = true
	C_Timer.After(1, function() if IS_121 and not RFC.enabled then RFC.Enable(true) end end)
end)

-- Flip the SOURCE of the three helpful categories (see NATIVE_CATS). Relayout
-- carries it to every live button; buttons that have no container yet pick the
-- current setting up when they build one. Out of combat only, like everything
-- that touches a container.
function RFC.SetFlagSource(on)
	on = on and true or false
	if RFC.useFlags == on then return end
	if InCombatLockdown() then say("|cffff5555Out of combat only.|r"); return end
	RFC.useFlags = on
	RFC.Relayout()
	say("HoTs + Defensives now from |cff44ff44" ..
		(on and "Blizzard's per-spell flags" or "the curated whitelist") ..
		"|r.")
	-- On 12.0.x the native path is inert, so the switch is set but renders nothing.
	-- Saying so beats letting an unchanged frame read as "the flags show nothing".
	if not RFC.enabled then
		say("|cffffcc00Note:|r the native path is off, so nothing changes on screen yet.")
	end
end

-- Blizzard's own verdict on a spell, used to keep the categories disjoint.
local function cdmFlags(spellID)
	local big, ext = false, false
	if C_UnitAuras and C_UnitAuras.AuraIsBigDefensive then
		local ok, v = pcall(C_UnitAuras.AuraIsBigDefensive, spellID); big = (ok and v) and true or false
	end
	if C_Spell and C_Spell.IsExternalDefensive then
		local ok, v = pcall(C_Spell.IsExternalDefensive, spellID); ext = (ok and v) and true or false
	end
	return big, ext
end

local function spellName(id)
	return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or ("#" .. tostring(id))
end


-- ---------------------------------------------------------------------------
--  Blizzard's own per-spec "Buffs (Group window)" list (CooldownViewerCategory
--  .GroupBuff). It is the closest thing to a maintained HoT list that exists:
--  bounded (16 entries max), scoped to the spec, aimed at group frames by name
--  -- and the user curates it in Blizzard's own settings, which we can read back.
--    * GetGroupBuffItems  = the candidates, with a HideByDefault flag
--    * GetHiddenGroupBuffs = what the user has moved to "not shown"
--    * shown = candidates minus hidden (that is exactly how Blizzard's own UI
--      builds its two sections)
--  An empty list means Blizzard offers nothing for this spec -- a Hunter has no
--  such tab at all -- which is the signal a "use Blizzard's list" switch gates on.
-- ---------------------------------------------------------------------------
function RFC.DumpGroupBuffs()
	local CV, UA = C_CooldownViewer, C_UnitAuras
	if not (CV and CV.GetGroupBuffItems) then
		say("|cffff5555GetGroupBuffItems does not exist on this build.|r"); return
	end
	local ok, items = pcall(CV.GetGroupBuffItems)
	if not (ok and items) then say("|cffff5555GetGroupBuffItems failed.|r"); return end

	local hidden = {}
	if UA and UA.GetHiddenGroupBuffs then
		local ok2, ids = pcall(UA.GetHiddenGroupBuffs)
		if ok2 and ids then for _, id in ipairs(ids) do hidden[id] = true end end
	end

	local spec = currentSpecID()
	local wl = (ns.Raidframes and ns.Raidframes.WhitelistMap and ns.Raidframes:WhitelistMap(spec)) or {}
	say(("Group Buffs (Blizzard's group-window list), spec %d -- %d entries:"):format(spec, #items))
	if #items == 0 then
		say("  |cffffcc00none -- Blizzard offers no group-buff list for this spec.|r")
	end

	local blizz, blizzByName = {}, {}
	local defFlag = (Enum and Enum.GroupBuffItemFlags and Enum.GroupBuffItemFlags.HideByDefault) or 1
	for _, it in ipairs(items) do
		blizz[it.spellID] = true
		if it.name then
			local l = blizzByName[it.name]; if not l then l = {}; blizzByName[it.name] = l end
			l[#l + 1] = it.spellID
		end
		local state = hidden[it.spellID] and "|cff888888not shown|r" or "|cff44ff44shown|r"
		local note = ""
		if bit.band(it.flags or 0, defFlag) ~= 0 then note = note .. "  |cff888888hidden by default|r" end
		if not it.isKnown then note = note .. "  |cff888888unlearned|r" end
		-- Which of these Blizzard itself considers a defensive decides the category
		-- boundary: those belong to Defensives (already flag-sourced), not to HoTs.
		local big, ext = cdmFlags(it.spellID)
		if big or ext then note = note .. "  |cffffcc00is a defensive|r" end
		-- After the migration our whitelist holds only the EXTRAS, so an entry that is
		-- not in it is the normal case: Blizzard's list owns it. Saying "we do NOT
		-- track this" here read like a fault when it is the working state.
		if wl[it.spellID] then note = note .. "  |cffffcc00also in your extras|r" end
		say(("  %s (%d)  %s%s"):format(it.name or "?", it.spellID, state, note))
	end

	-- Our own additions: spells Blizzard's list does not carry at all, which is the
	-- only reason the extras layer exists.
	local extras = 0
	for sid, typ in pairs(wl) do
		if typ == "hot" and not blizz[sid] then
			extras = extras + 1
			say("  |cff44ff44your extra:|r " .. spellName(sid) .. " (" .. sid .. ")")
		end
	end
	if extras == 0 and #items > 0 then
		say("Everything shown comes from Blizzard's list; you have no extras on this spec.")
	end

	-- Same name, different id = we are almost certainly tracking the CAST spell while
	-- the aura that lands on the frame has its own id. That is the bug the Resto Druid
	-- major slot had, and a name audit cannot see it -- both ids resolve to a name.
	for sid in pairs(wl) do
		local ids = blizzByName[spellName(sid)]
		if ids and not blizz[sid] then
			for _, other in ipairs(ids) do
				say(("  |cffffcc00same name, other id:|r we track %s (%d), Blizzard's list has %d")
					:format(spellName(sid), sid, other))
			end
		end
	end
end

function RFC.Disable()
	if InCombatLockdown() then say("|cffff5555Out of combat only.|r"); return end
	RFC.enabled = false
	forEachLiveButton(function(btn)
		if btn._rfc then for _, c in pairs(btn._rfc) do c:SetEnabled(false); c:Hide() end end
	end)
	if ns.Raidframes and ns.Raidframes.RefreshAuras then ns.Raidframes:RefreshAuras() end
	say("Native auras |cffffcc00OFF|r (old path renders again).")
end

SLASH_LUMENNATIVE1 = "/lumennative"
SlashCmdList["LUMENNATIVE"] = function(arg)
	arg = (arg or ""):lower():gsub("%s", "")
	if arg == "on" then RFC.Enable()
	elseif arg == "off" then RFC.Disable()
	elseif arg == "refresh" then RFC.Disable(); RFC.Enable()
	elseif arg == "flagson" then RFC.SetFlagSource(true)
	elseif arg == "flagsoff" then RFC.SetFlagSource(false)
	elseif arg == "buffs" then RFC.DumpGroupBuffs()
	elseif arg == "curated" then
		if ns.Raidframes and ns.Raidframes.DumpCurated then ns.Raidframes:DumpCurated(say) end
	else
		say("Auras through the native 12.1 container. Enabled automatically on 12.1.")
		say("  /lumennative on | off | refresh   (currently: "
			.. (RFC.enabled and "ON" or "OFF") .. (IS_121 and ", 12.1 detected" or ", not 12.1") .. ")")
		say("  /lumennative flags on | off   -- source of the Defensives: "
			.. (RFC.useFlags and "|cff44ff44Blizzard flags|r" or "|cffffcc00curated whitelist|r"))
		say("  /lumennative buffs   -- Blizzard's own group-window buff list for this spec")
		say("  /lumennative curated   -- our own default lists, resolved to spell names")
	end
end
