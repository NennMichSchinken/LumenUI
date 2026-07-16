-- Modules/AuraContainer.lua
--
-- Aura Phase 2 (WIP) -- native 12.1 AuraContainer rendering for raid-frame auras.
-- Renders all four aura categories via the native container on the LIVE secure
-- raid buttons: the HELPFUL whitelist categories (HoTs, Defensives, Major CDs)
-- via per-spellId includeSpellIDs, and Debuffs (HARMFUL) via filter-mode groups
-- (raid/all/dispellable). Replaces the old manual scan/signature/secret-icon path.
--
-- Because SetAuraLayout* is CONTAINER-level (one anchor per container) and our
-- categories use different corners, each category gets its OWN container per
-- button: button._rfc = { [catKey] = container }.
--
-- Auto-default ON on 12.1 (detected via build number); `/lumennative on|off` is
-- a manual override. Inert on 12.0.x (the "AuraContainer" frame type does not
-- exist -> attach no-ops, old scan path renders).
--
-- Not final: layout parity for centered anchors, the pandemic warning, and the
-- debuff category are follow-ups; whether OTHER units' SECRET auras render on the
-- non-secure overlay parent still needs a real-group test.

-- luacheck: globals SLASH_LUMENNATIVE1

local _, ns = ...

local RFC = {}
ns.RFC = RFC

local InCombatLockdown = InCombatLockdown
local CreateFrame       = CreateFrame
local floor, strfind    = math.floor, string.find

RFC.enabled = false

-- Categories the native path owns. HELPFUL ones (wl) filter by a per-spellId
-- whitelist; debuffs are HARMFUL (harmful=true) and filter by MODE via filter
-- strings (per-spellId matching is not permitted for harmful auras on assistable
-- units -- the Phase 1 constraint).
local NATIVE_CATS = {
	{ key = "hotsOwn",    wl = "hot" },
	{ key = "defensives", wl = "def" },
	{ key = "major",      wl = "major" },
	{ key = "debuffs",    harmful = true },
}
local IS_NATIVE = {}
for _, c in ipairs(NATIVE_CATS) do IS_NATIVE[c.key] = true end

-- Debuff filter modes -> aura filter-string groups. "raid" is a UNION (RAID or
-- RAID_IN_COMBAT), so it declares two non-overlapping groups (the second negates
-- RAID) to avoid a double display. Groups live in ONE debuffs container; the
-- active mode's groups get maxFrameCount = N, the rest 0 (live switching, no
-- container swap -- mirrors the EllesmereUI approach).
local DEBUFF_PRESETS = {
	all         = { { key = "db_all",   filter = "HARMFUL" } },
	raid        = { { key = "db_raid",  filter = "HARMFUL|RAID" },
	                { key = "db_raidc", filter = "HARMFUL|RAID_IN_COMBAT|!RAID" } },
	dispellable = { { key = "db_disp",  filter = "HARMFUL|RAID_PLAYER_DISPELLABLE" } },
}
local ALL_DEBUFF_KEYS = { "db_all", "db_raid", "db_raidc", "db_disp" }

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

-- Icon size of a category (explicit only when auto-fit is off, else derived from
-- the frame height; the exact auto-fit math from Raidframes is a follow-up).
local function iconSizeFor(button, key)
	local cat, sfx = catCfg(key), ctxSfx()
	if cat and not cat["autoFit" .. sfx] and cat["size" .. sfx] then
		return cat["size" .. sfx]
	end
	return math.max(10, math.min(40, floor((button:GetHeight() or 60) * 0.3)))
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

-- Per-category duration-text options (per context).
local function durOptsFor(key)
	local cat, sfx = catCfg(key), ctxSfx()
	if not cat then return true, 12, "shadow" end
	local on = cat["showDuration" .. sfx]
	if on == nil then on = true end
	return on, cat["durationSize" .. sfx] or 12, cat["durationOutline" .. sfx] or "shadow"
end

-- Tracked { button, fs, key } so duration text can be RESTYLED live (size /
-- outline / show) on a settings change without rebuilding the containers.
local durText = {}

-- Style one duration fontstring from its category's options + (re)register or
-- clear the engine binding for the on/off state. An unstyled FontString hard-errors
-- in the engine's SetText path, so the font is set before the binding is attached.
local function applyDurStyle(button, fs, key)
	local on, size, outline = durOptsFor(key)
	if ns.Raidframes and ns.Raidframes.StyleTextFont then
		ns.Raidframes:StyleTextFont(fs, size, outline)
	end
	fs:SetTextColor(1, 1, 1)
	if on then
		local fmt = getDurationFormatter()
		pcall(button.SetDurationText, button, fs, fmt and { formatter = fmt } or {})
		fs:Show()
	else
		pcall(button.ClearDurationText, button)
		fs:Hide()
	end
end

-- Re-apply duration styling to every tracked button (called on settings change).
function RFC.RestyleDuration()
	for i = #durText, 1, -1 do
		local e = durText[i]
		if e.fs and e.button then
			applyDurStyle(e.button, e.fs, e.key)
		else
			durText[i] = durText[#durText]; durText[#durText] = nil
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
		dt:SetPoint("CENTER", button, "CENTER", 0, 0)
		durText[#durText + 1] = { button = button, fs = dt, key = key }
		applyDurStyle(button, dt, key)
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

-- Container-level layout (anchor / growth / position) -- shared by every group
-- in the container. Live-settable.
local function applyContainerLayout(container, parent, lo)
	local ix, iy = insetFor(lo.anchor)
	local ox, oy = 0, 0
	if lo.outside then ox, oy = outsideOffset(lo.anchor, lo.grow, lo.size) end
	local hDir, vDir, column = growthDirs(lo.grow)
	container:ClearAllPoints()
	container:SetPoint(lo.anchor, parent, lo.anchor, ix + lo.offX + ox, iy + lo.offY + oy)
	container:SetAuraLayoutAnchorPoint(lo.anchor)
	container:SetAuraLayoutGrowthDirection(hDir, vDir)
	container:SetAuraLayoutRowWidth(column and (lo.size + 0.5) or nil) -- nil = unlimited
end

-- Per-group size/spacing/count. The group must already exist.
local function applyGroupLayout(container, gkey, lo, maxN)
	container:SetAuraGroupMaxFrameCount(gkey, maxN)
	container:SetAuraGroupLayout(gkey, {
		elementWidth = lo.size, elementHeight = lo.size,
		elementSpacingX = lo.spacing, elementSpacingY = lo.spacing,
	})
end

-- Declare a debuff group on demand (engine groups are add-only) + configure it.
local function ensureDebuffGroup(container, gkey, filter, lo, maxN)
	container._dbGroups = container._dbGroups or {}
	if not container._dbGroups[gkey] then
		container._dbGroups[gkey] = true
		container:AddAuraGroup(gkey, filter, {
			maxFrameCount   = maxN,
			initializeFrame = makeInitializer(lo.size, "debuffs"),
		})
	end
	applyGroupLayout(container, gkey, lo, maxN)
end

-- Reconcile the debuffs container to the active filter mode: the active preset's
-- groups get maxFrameCount = N, every other already-declared debuff group 0.
local function syncDebuffs(container, parent, lo)
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
	applyContainerLayout(container, parent, lo)
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

	local lo = readLayout(button, key)
	local built = pcall(function()
		container:SetSize(1, 1)
		if c.harmful then
			syncDebuffs(container, parent, lo)
		else
			container:AddAuraGroup(key, "HELPFUL", {
				maxFrameCount    = lo.maxN,
				candidateFilters = { includeSpellIDs = buildInclude(c.wl) },
				initializeFrame  = makeInitializer(lo.size, key),
			})
			applyContainerLayout(container, parent, lo)
			applyGroupLayout(container, key, lo, lo.maxN)
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
					local lo = readLayout(btn, c.key)
					sizes[c.key] = lo.size
					container:Show(); container:SetEnabled(true)
					if c.harmful then
						pcall(syncDebuffs, container, parent, lo)
					else
						pcall(function()
							applyContainerLayout(container, parent, lo)
							applyGroupLayout(container, c.key, lo, lo.maxN)
						end)
					end
				end
			elseif container then
				container:SetEnabled(false); container:Hide()
			end
		end
	end)
	-- Resize existing aura buttons to their category's current icon size.
	for _, e in ipairs(durText) do
		if e.button and sizes[e.key] then pcall(e.button.SetSize, e.button, sizes[e.key], sizes[e.key]) end
	end
end

-- True while the native path owns category `key` -> the old holder stays suppressed.
function RFC.Suppresses(key)
	return RFC.enabled and IS_NATIVE[key] ~= nil
end

function RFC.Enable(quiet)
	if InCombatLockdown() then if not quiet then say("|cffff5555OOC schalten (Kampf).|r") end return end
	RFC.enabled = true
	forEachLiveButton(function(btn)
		RFC.Attach(btn)
		RFC.SetUnit(btn, btn.unit or btn:GetAttribute("unit"))
		if btn._rfc then for _, c in pairs(btn._rfc) do c:SetEnabled(true); c:Show() end end
	end)
	if ns.Raidframes and ns.Raidframes.RefreshAuras then ns.Raidframes:RefreshAuras() end
	if not quiet then say("Native Auren |cff44ff44AN|r (HoTs · Defensives · Major CDs · Debuffs).") end
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

function RFC.Disable()
	if InCombatLockdown() then say("|cffff5555OOC schalten (Kampf).|r"); return end
	RFC.enabled = false
	forEachLiveButton(function(btn)
		if btn._rfc then for _, c in pairs(btn._rfc) do c:SetEnabled(false); c:Hide() end end
	end)
	if ns.Raidframes and ns.Raidframes.RefreshAuras then ns.Raidframes:RefreshAuras() end
	say("Native Auren |cffffcc00AUS|r (altes System zurück).")
end

SLASH_LUMENNATIVE1 = "/lumennative"
SlashCmdList["LUMENNATIVE"] = function(arg)
	arg = (arg or ""):lower():gsub("%s", "")
	if arg == "on" then RFC.Enable()
	elseif arg == "off" then RFC.Disable()
	elseif arg == "refresh" then RFC.Disable(); RFC.Enable()
	else
		say("Auren über den nativen 12.1-Container. Auf 12.1 automatisch AN.")
		say("  /lumennative on | off | refresh   (aktuell: "
			.. (RFC.enabled and "AN" or "AUS") .. (IS_121 and ", 12.1 erkannt" or ", kein 12.1") .. ")")
	end
end
