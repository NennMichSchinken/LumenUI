-- Modules/AuraContainer.lua
--
-- Aura Phase 2 (WIP) -- native 12.1 AuraContainer rendering for raid-frame auras.
-- Renders all four aura categories via the native container on the LIVE secure
-- raid buttons: the HELPFUL categories (HoTs, Defensives, Major CDs) from either
-- the curated whitelist (per-spellId includeSpellIDs) or Blizzard's own per-spell
-- category flags, and Debuffs (HARMFUL) via filter-mode groups (raid/all/
-- dispellable). Replaces the old manual scan/signature/secret-icon path.
-- Which source the helpful categories use is a session switch while its two open
-- in-game questions are unanswered -- see NATIVE_CATS.
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
-- DEF_DEFAULTS for us, so BIG_DEFENSIVE feeds Defensives, not Major CDs.
--
-- Major CDs has NO flag source on purpose. It is Tree of Life, Innervate, Power
-- Infusion, Divine Hymn -- healing THROUGHPUT cooldowns, and Blizzard has no flag
-- for those (BIG_DEFENSIVE is about surviving, which is the other card). It also
-- does not need one: two or three signature buttons per healer spec is a set that
-- a curated list can actually hold complete, unlike every HoT in the game.
--
-- Which source feeds the two flagged categories is a SESSION switch for now
-- (RFC.useFlags, `/lumennative flags on`), not a profile setting -- the override
-- layer (deselected -> excludeSpellIDs, extras -> their own group) still has to
-- be designed together with the Auras tab that explains it.
local NATIVE_CATS = {
	{ key = "hotsOwn",    wl = "hot", flagFilters = {
		-- Self-cast raid-relevant buffs, minus anything that is really a defensive
		-- (out of combat Ironbark matched here too).
		"HELPFUL|PLAYER|RAID_IN_COMBAT|!EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE" } },
	{ key = "defensives", wl = "def", flagFilters = {
		-- Externals first; big personal defensives second, minus the externals so
		-- an aura that is both is drawn once.
		"HELPFUL|EXTERNAL_DEFENSIVE",
		"HELPFUL|BIG_DEFENSIVE|!EXTERNAL_DEFENSIVE" } },
	{ key = "major",      wl = "major" },
	{ key = "debuffs",    harmful = true },
}
-- Session switch: false = the curated whitelist feeds the three helpful
-- categories (today's behaviour), true = Blizzard's per-spell flags do.
RFC.useFlags = false
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
	if not cat then return true, 12, "shadow" end
	local on = cat["showDuration" .. sfx]
	if on == nil then on = true end
	return on, cat["durationSize" .. sfx] or 12, cat["durationOutline" .. sfx] or "shadow"
end

-- Every aura button the engine has created for us, as { button, fs, key, ring }.
-- Settings changes are applied to this list (duration text, tooltips, pandemic
-- marker, icon size) instead of rebuilding the containers.
local auraBtns = {}

-- Style one duration fontstring from its category's options + (re)register or
-- clear the engine binding for the on/off state. An unstyled FontString hard-errors
-- in the engine's SetText path, so the font is set before the binding is attached.
local function applyDurStyle(e)
	local button, fs = e.button, e.fs
	local on, size, outline = durOptsFor(e.key)
	local function style()
		if ns.Raidframes and ns.Raidframes.StyleTextFont then
			ns.Raidframes:StyleTextFont(fs, size, outline)
		end
	end
	style()
	pcall(fs.SetTextColor, fs, 1, 1, 1)   -- VertexColor is a secret aspect once bound
	if on then
		if not e.durBound then
			local fmt = getDurationFormatter()
			-- 68914 renamed this option key from `formatter` to `textFormatter`, and
			-- the engine simply IGNORES an unknown key -- so passing the old name on a
			-- new build silently falls back to the default formatter and the text reads
			-- "14s" again instead of "14". No error to notice it by, hence both keys:
			-- each build reads the one it knows.
			local opts
			if fmt then opts = { textFormatter = fmt, formatter = fmt } else opts = {} end
			-- Bound ONCE, not on every settings change: SetDurationText re-arms the
			-- binding and re-stamps the secret aspects, and Blizzard's own comment
			-- warns that replacing an active binding needs the old one disabled first.
			-- Size/outline are pure font state and do not need a re-bind.
			if pcall(button.SetDurationText, button, fs, opts) then e.durBound = true end
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
function RFC.RefreshOptions()
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
-- A category without flagFilters (Major CDs) simply keeps its whitelist group in
-- both modes -- see the note on NATIVE_CATS for why it has no flag source.
local function flagGroupKey(key, i) return key .. "_f" .. i end

local function syncHelpful(container, c, lo)
	local key, filters = c.key, c.flagFilters
	local useFlags = (RFC.useFlags and filters) and true or false
	if not container._helpfulGroups then
		container._helpfulGroups = true
		container:AddAuraGroup(key, "HELPFUL", {
			maxFrameCount    = lo.maxN,
			candidateFilters = { includeSpellIDs = buildInclude(c.wl) },
			initializeFrame  = makeInitializer(lo.size, key),
		})
		for i = 1, (filters and #filters or 0) do
			-- Declared with the full budget and corrected below, the way the debuff
			-- groups are: a group that only ever sees 0 is untested ground.
			container:AddAuraGroup(flagGroupKey(key, i), filters[i], {
				maxFrameCount   = lo.maxN,
				initializeFrame = makeInitializer(lo.size, key),
			})
		end
	end
	applyGroupLayout(container, key, lo, useFlags and 0 or lo.maxN)
	for i = 1, (filters and #filters or 0) do
		applyGroupLayout(container, flagGroupKey(key, i), lo, useFlags and lo.maxN or 0)
	end
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
function RFC.Attach(button)
	if not button or InCombatLockdown() then return end
	local parent = button.overlay or button
	for _, c in ipairs(NATIVE_CATS) do
		if catEnabled(c.key) then attachCat(button, parent, c) end
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
	local sizes = {}
	forEachLiveButton(function(btn)
		if InCombatLockdown() then return end
		local parent = btn.overlay or btn
		for _, c in ipairs(NATIVE_CATS) do
			local on = catEnabled(c.key)
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
	if not quiet then say("Native auras |cff44ff44ON|r (HoTs · Defensives · Major CDs · Debuffs).") end
end

-- Auto-default: on 12.1 turn native on by itself (once, after login), so no
-- manual toggle is needed. RFC.enabled=true also makes buttons assigned later
-- attach via their unit-change hook. A manual `/lumennative off` still overrides
-- for the session. On 12.0.x this never fires -> old path stays.
local autoDone = false
local autoFrame = CreateFrame("Frame")
autoFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
autoFrame:SetScript("OnEvent", function()
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
		"|r (Major CDs stay curated either way).")
	-- On 12.0.x the native path is inert, so the switch is set but renders nothing.
	-- Saying so beats letting an unchanged frame read as "the flags show nothing".
	if not RFC.enabled then
		say("|cffffcc00Note:|r the native path is off, so nothing changes on screen yet.")
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
	else
		say("Auras through the native 12.1 container. Enabled automatically on 12.1.")
		say("  /lumennative on | off | refresh   (currently: "
			.. (RFC.enabled and "ON" or "OFF") .. (IS_121 and ", 12.1 detected" or ", not 12.1") .. ")")
		say("  /lumennative flags on | off   -- source of HoTs/Defensives (Major CDs stay curated): "
			.. (RFC.useFlags and "|cff44ff44Blizzard flags|r" or "|cffffcc00curated whitelist|r"))
	end
end
