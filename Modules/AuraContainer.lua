-- Modules/AuraContainer.lua
--
-- Aura Phase 2 (WIP) -- native 12.1 AuraContainer rendering for raid-frame auras.
-- FIRST INCREMENT: the HoTs category only, on the LIVE secure raid buttons,
-- proving the native path end-to-end (per-button container, unit binding,
-- per-spellId whitelist, icon + cooldown swipe + duration text) before we rip
-- out the old manual scan/signature/secret-icon apparatus.
--
-- Toggle-gated so it does NOT disturb the shipping behavior: `/lumennative on`
-- swaps the native HoTs path in (and suppresses the old HoTs holder); `off`
-- restores the current system. Default OFF. This whole file is inert on live
-- 12.0.x (the "AuraContainer" frame type does not exist -> Attach no-ops).
--
-- Not final: layout parity for vertical growth / centered anchors and the
-- new duration/pandemic options are follow-ups; this increment hardcodes a
-- sensible duration text so the render can be validated on the PTR.

-- luacheck: globals SLASH_LUMENNATIVE1

local _, ns = ...

local RFC = {}
ns.RFC = RFC

local InCombatLockdown = InCombatLockdown
local CreateFrame       = CreateFrame
local floor, strfind    = math.floor, string.find

RFC.enabled = false

local PREFIX = "|cffD4A34FLumenNative|r "
local function say(m) print(PREFIX .. m) end

-- Context + spec helpers (kept local; we don't reach into Raidframes internals).
local function ctxSfx() return IsInRaid() and "Raid" or "Party" end
local function currentSpecID()
	local idx = GetSpecialization and GetSpecialization()
	if not idx then return 0 end
	return (GetSpecializationInfo and GetSpecializationInfo(idx)) or 0
end

local function hotsCat()
	local rf = ns.Lumen and ns.Lumen.db and ns.Lumen.db.profile.raidframes
	local auras = rf and rf.auras
	return auras and auras.hotsOwn
end

-- Whitelist -> includeSpellIDs. Sourced from the curated per-spec HoT whitelist
-- (stable ids), NEVER from live aura reads (12.1 aura.spellId is secret).
local function buildHotInclude()
	local include = {}
	local rf = ns.Raidframes
	if not rf or not rf.WhitelistMap then return include end
	for sid, typ in pairs(rf:WhitelistMap(currentSpecID())) do
		if typ == "hot" then include[sid] = true end
	end
	return include
end

-- Icon size for the HoTs category (explicit or a simple auto-fit off the button
-- height; the exact auto-fit math from Raidframes is a follow-up).
local function hotIconSize(button)
	local cat, sfx = hotsCat(), ctxSfx()
	-- Explicit size only when auto-fit is off (mirrors the old system); otherwise
	-- derive from the frame height.
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

-- Current duration-text options for the HoTs category (per context). Falls back
-- to sensible values if the profile hasn't been migrated yet.
local function currentDurOpts()
	local cat, sfx = hotsCat(), ctxSfx()
	if not cat then return true, 12, "outline" end
	local on = cat["showDuration" .. sfx]
	if on == nil then on = true end
	return on, cat["durationSize" .. sfx] or 12, cat["durationOutline" .. sfx] or "shadow"
end

-- Tracked { button, fs } pairs so duration text can be RESTYLED live (size /
-- outline / show) on a settings change without rebuilding the containers.
local durText = {}

-- Style one duration fontstring from the current options + (re)register or clear
-- the engine binding for the on/off state. An unstyled FontString hard-errors in
-- the engine's SetText path, so the font is set before the binding is attached.
local function applyDurStyle(button, fs)
	local on, size, outline = currentDurOpts()
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
			applyDurStyle(e.button, e.fs)
		else
			durText[i] = durText[#durText]; durText[#durText] = nil
		end
	end
end

-- The per-button initializer (runs once per pre-created button). Builds our own
-- child regions and registers them; matches the old icon look (1px black frame,
-- cropped icon, cooldown swipe) and adds the requested duration text.
local function makeInitializer(size)
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

		-- Duration text rides a carrier frame ABOVE the cooldown swipe, else the
		-- swipe darkens/greys the number. Created once; visibility/size/outline are
		-- driven live by applyDurStyle (from the per-category options).
		local textLayer = CreateFrame("Frame", nil, button)
		textLayer:SetAllPoints(button)
		textLayer:SetFrameLevel(cd:GetFrameLevel() + 1)
		local dt = textLayer:CreateFontString(nil, "OVERLAY")
		dt:SetPoint("CENTER", button, "CENTER", 0, 0)
		durText[#durText + 1] = { button = button, fs = dt }
		applyDurStyle(button, dt)
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

-- "Outside" placement: push the whole row/column beyond the anchored edge,
-- perpendicular to the growth axis (mirrors the old positionAuraIcons _outside).
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

-- Read the hotsOwn layout params for the current context.
local function readLayout(button)
	local cat, sfx = hotsCat(), ctxSfx()
	return {
		anchor  = (cat and cat["anchor" .. sfx]) or "BOTTOMLEFT",
		grow    = (cat and cat["grow" .. sfx]) or "RIGHT",
		spacing = (cat and cat["spacing" .. sfx]) or 2,
		maxN    = (cat and cat["maxIcons" .. sfx]) or 5,
		offX    = (cat and cat["offX" .. sfx]) or 0,
		offY    = (cat and cat["offY" .. sfx]) or 0,
		outside = (cat and cat["outside" .. sfx]) or false,
		size    = hotIconSize(button),
	}
end

-- Apply position + layout to an EXISTING container via the live-settable native
-- setters (used both at Attach and on every settings change). The "hotsOwn"
-- group must already exist.
local function applyLayout(container, parent, lo)
	local ix, iy = insetFor(lo.anchor)
	local ox, oy = 0, 0
	if lo.outside then ox, oy = outsideOffset(lo.anchor, lo.grow, lo.size) end
	local hDir, vDir, column = growthDirs(lo.grow)
	container:ClearAllPoints()
	container:SetPoint(lo.anchor, parent, lo.anchor, ix + lo.offX + ox, iy + lo.offY + oy)
	container:SetAuraLayoutAnchorPoint(lo.anchor)
	container:SetAuraLayoutGrowthDirection(hDir, vDir)
	container:SetAuraLayoutRowWidth(column and (lo.size + 0.5) or nil) -- nil = unlimited
	container:SetAuraGroupMaxFrameCount("hotsOwn", lo.maxN)
	container:SetAuraGroupLayout("hotsOwn", {
		elementWidth = lo.size, elementHeight = lo.size,
		elementSpacingX = lo.spacing, elementSpacingY = lo.spacing,
	})
end

local function forEachLiveButton(fn)
	local rf = ns.Raidframes
	if not (rf and rf.GetLiveButtons) then return end
	for _, btn in ipairs(rf:GetLiveButtons()) do fn(btn) end
end

-- Create + configure the container on one secure button. OOC only (containers
-- cannot be created in combat). Idempotent.
function RFC.Attach(button)
	if button._rfc or not button then return end
	if InCombatLockdown() then return end

	-- Parent the container to the NON-secure overlay (where the old aura icons
	-- render), not the secure unit button: on the protected button our tainted
	-- icon texture stays blank (swipe/text still show), while on the overlay the
	-- engine's secret-safe SetTexture displays -- same as the old path + the
	-- Phase-1 spike. NOTE: whether OTHER units' SECRET auras also render on a
	-- non-secure parent is the next thing to verify in a real group.
	local parent = button.overlay or button
	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not container then return end -- not 12.1 -> silently inert
	button._rfc = container

	local lo = readLayout(button)

	local built = pcall(function()
		container:SetSize(1, 1)
		container:AddAuraGroup("hotsOwn", "HELPFUL", {
			maxFrameCount    = lo.maxN,
			candidateFilters = { includeSpellIDs = buildHotInclude() },
			initializeFrame  = makeInitializer(lo.size),
		})
		applyLayout(container, parent, lo)

		local u = button.unit or button:GetAttribute("unit")
		if u then container:SetUnit(u) end
		container:SetEnabled(true)
		container:UpdateAllAuras()
	end)

	if not built then button._rfc = nil end
	return button._rfc
end

-- Re-apply position/size/layout to all live containers + resize existing aura
-- buttons (called on any aura settings change so the position options are live).
function RFC.Relayout()
	local size
	forEachLiveButton(function(btn)
		local c = btn._rfc
		if c then
			local lo = readLayout(btn)
			size = lo.size
			pcall(applyLayout, c, btn.overlay or btn, lo)
		end
	end)
	if size then
		for _, e in ipairs(durText) do
			if e.button then pcall(e.button.SetSize, e.button, size, size) end
		end
	end
end

-- Re-point the container's unit when the secure header (re)assigns the button.
-- Same-unit early-out avoids a raid-wide reparse storm on roster re-processing.
function RFC.SetUnit(button, unit)
	local c = button and button._rfc
	if not c then return end
	if button._rfcUnit == unit then return end
	button._rfcUnit = unit
	if unit then
		pcall(function() c:SetUnit(unit); c:UpdateAllAuras() end)
	end
end

-- True while the native path owns HoTs -> the old holder must stay suppressed.
function RFC.SuppressesHots()
	return RFC.enabled
end

function RFC.Enable()
	if InCombatLockdown() then say("|cffff5555OOC schalten (Kampf).|r"); return end
	RFC.enabled = true
	forEachLiveButton(function(btn)
		RFC.Attach(btn)
		RFC.SetUnit(btn, btn.unit or btn:GetAttribute("unit"))
		if btn._rfc then btn._rfc:SetEnabled(true); btn._rfc:Show() end
	end)
	-- Drop the old HoTs holder so we don't double-render.
	if ns.Raidframes and ns.Raidframes.RefreshAuras then ns.Raidframes:RefreshAuras() end
	say("Native HoTs |cff44ff44AN|r.")
end

function RFC.Disable()
	if InCombatLockdown() then say("|cffff5555OOC schalten (Kampf).|r"); return end
	RFC.enabled = false
	forEachLiveButton(function(btn)
		if btn._rfc then btn._rfc:SetEnabled(false); btn._rfc:Hide() end
	end)
	if ns.Raidframes and ns.Raidframes.RefreshAuras then ns.Raidframes:RefreshAuras() end
	say("Native HoTs |cffffcc00AUS|r (altes System zurück).")
end

SLASH_LUMENNATIVE1 = "/lumennative"
SlashCmdList["LUMENNATIVE"] = function(arg)
	arg = (arg or ""):lower():gsub("%s", "")
	if arg == "on" then RFC.Enable()
	elseif arg == "off" then RFC.Disable()
	elseif arg == "refresh" then RFC.Disable(); RFC.Enable()
	else
		say("HoTs über den nativen 12.1-Container (Testschalter).")
		say("  /lumennative on | off | refresh   (aktuell: "
			.. (RFC.enabled and "AN" or "AUS") .. ")")
	end
end
