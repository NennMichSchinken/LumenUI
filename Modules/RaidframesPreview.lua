-- ===========================================================================
--  Lumen — Raidframes: PREVIEW surfaces (split out of Modules/Raidframes.lua)
--
--  Everything here is COLD PATH: the settings shell's anchored preview band,
--  its click-to-configure layer, and the two placeable Edit-Mode world
--  previews. None of it runs on a unit event; it redraws only when a setting
--  changes or an Edit-Mode session opens.
--
--  WHY ITS OWN FILE: Lua 5.1 allows 200 locals per chunk and Raidframes.lua
--  had reached that ceiling — exceeding it is a LOAD-TIME error that luacheck
--  cannot see (only an in-game /reload reveals it). A file is its own chunk
--  with its own budget, so moving this block gives both sides room. Same
--  answer the benchmark suite reached: it splits its raidframe module across
--  nine files for exactly this reason.
--
--  BOUNDARY: this file reaches into Raidframes.lua only through the handful of
--  `_`-prefixed members that file exports (see its "preview boundary" block);
--  in the other direction it adds exactly one, `_SetupEditPreviews`, which
--  Raidframes:Setup() calls. Keep that contract small — every new crossing is
--  a fact you have to hold in your head twice.
--  LOAD ORDER: must come AFTER Modules/Raidframes.lua in both .toc files.
-- ===========================================================================
local _, ns = ...

local Raidframes = ns.Raidframes

local CreateFrame, UIParent = CreateFrame, UIParent
local pairs, ipairs, pcall  = pairs, ipairs, pcall
local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

-- Profile accessor — the same one-liner Raidframes.lua uses; re-declared rather
-- than exported because a call across the boundary would buy nothing.
local function db() return ns.Lumen.db.profile.raidframes end

-- Imported from Raidframes.lua (see the boundary block there).
local GROUP_SIZE            = Raidframes._GROUP_SIZE
local Decorate              = Raidframes._Decorate
local GetFakeList           = Raidframes._GetFakeList
local invalidatePreviewIcons = Raidframes._InvalidatePreviewIcons
local setPreviewCtx         = Raidframes._SetPreviewCtx

-- ===========================================================================
--  SHELL PREVIEW (docked live-preview band in the settings shell)
--  A small OWN pool (separate from the test pool: test mode positions `frames`
--  on the real screen container) rendered into a W.PreviewBand's holder. Uses
--  the same Decorate/ApplyConfig/render path as test mode, with previewCtx
--  forcing the tab's context. No unit events — refreshes piggyback on
--  UpdateLayout/RefreshAuras (the paths every settings change already takes).
-- ===========================================================================

-- Curated preview roster: full bar, shield, incoming heal, dispellable debuff,
-- heal absorb, aggro (BOTH stages: yellow warn + red has-aggro) — every render
-- feature visible at a glance (each one can be filtered out via the eyes).
-- `auras` = curated per-category preview icon counts (see RenderAurasFake):
-- varied per frame like a real group; {} = deliberately clean (HP readable);
-- NO field = full-load frame (maxIcons everywhere, judges max/auto-fit).
local PREVIEW_FAKE = {
	{ name = "Owlday",      class = "DRUID",  hp = 1.00, power = 0.72, role = "HEALER", lead = true,
		auras = { hotsOwn = 2, defensives = 1 } },
	{ name = "Elyndra",     class = "MAGE",   hp = 0.82, power = 0.55, absorb = 0.14, role = "DAMAGER",
		auras = {} },
	{ name = "Kaelura",     class = "PRIEST", hp = 0.66, power = 0.38, predict = 0.20, role = "HEALER" },
	{ name = "Nighthollow", class = "ROGUE",  hp = 0.45, power = 0.90, dispel = "Magic", aggro = 2, role = "DAMAGER",
		auras = { hotsOwn = 1, debuffs = 1 } },
	{ name = "Sylfaria",    class = "MONK",   hp = 0.88, power = 0.64, healAbsorb = 0.18, aggro = 3, role = "TANK",
		auras = { defensives = 1, debuffs = 2 } },
}
local shellBands = {}   -- band -> spec: { kind = "base" } | { kind = "ctx", ctx = "raid"|"party" }
local pvFrames = {}     -- shared preview pool (one band visible at a time)

-- ---------------------------------------------------------------------------
--  Click-to-configure (dock preview only): hovering a preview element shows a
--  gold ring + "click to edit" tooltip; clicking jumps to its settings card
--  (Shell:JumpTo). The mouse layer exists SOLELY on the non-secure dock pool
--  (f._c2c) — live secure frames and the world test pool stay untouched.
-- ---------------------------------------------------------------------------
local C2C_LABELS = {
	hotsOwn    = "HoTs",
	defensives = "Defensives & External",
	major      = "Major CDs",
	debuffs    = "Debuffs",
}
local c2cRing
local function c2cGetRing()
	if c2cRing then return c2cRing end
	local r = CreateFrame("Frame", nil, UIParent)
	r:Hide()
	r:EnableMouse(false)
	local function redge()
		local t = r:CreateTexture(nil, "OVERLAY")
		-- brand gold (C1), same tone as the frame mouseover border (combat-path file, kept literal)
		t:SetColorTexture(0.91, 0.73, 0.41, 1)
		return t
	end
	local e1, e2, e3, e4 = redge(), redge(), redge(), redge()
	e1:SetPoint("TOPLEFT"); e1:SetPoint("TOPRIGHT"); e1:SetHeight(2)
	e2:SetPoint("BOTTOMLEFT"); e2:SetPoint("BOTTOMRIGHT"); e2:SetHeight(2)
	e3:SetPoint("TOPLEFT"); e3:SetPoint("BOTTOMLEFT"); e3:SetWidth(2)
	e4:SetPoint("TOPRIGHT"); e4:SetPoint("BOTTOMRIGHT"); e4:SetWidth(2)
	c2cRing = r
	return r
end
local function c2cJump(host, cardKey)
	if not (ns.Shell and ns.Shell.JumpTo) then return end
	Raidframes:_C2CLeave()
	-- Aura icons live on their own tab now; everything else stays on the
	-- context tab the clicked frame belongs to.
	local tab
	if cardKey:find("^aura%-") then
		tab = "Auras"
		-- The Auras tab carries its own context; the target tab name can no longer
		-- express it, so hand it over through the profile before the jump. Flag a
		-- real change so the Shell knows it must rebuild (an unchanged jump only
		-- flashes the card instead of re-rendering the page).
		local d = db()
		if d then
			local want = (host._pvCtx == "raid") and "raid" or "party"
			if d.auraTabCtx ~= want then
				d.auraTabCtx = want
				ns.ShellJumpDirty = true
			end
		end
	else
		tab = (host._pvCtx == "raid") and "Raid" or "Group"
	end
	ns.Shell:JumpTo("Raidframes", tab, cardKey)
end
function Raidframes:_C2CLeave()
	if c2cRing then c2cRing:Hide() end
	if ns.W and ns.W.HideTip then ns.W.HideTip() end
end
-- Ring around all VISIBLE icons of the hovered category. Bounds arithmetic is
-- valid because holder and icons share one effective scale.
local C2C_PAD = 3
function Raidframes:_C2CIconEnter(holder)
	local minL, maxR, minB, maxT
	for i = 1, #holder.icons do
		local ic = holder.icons[i]
		if ic:IsShown() then
			local l, rt, b, t = ic:GetLeft(), ic:GetRight(), ic:GetBottom(), ic:GetTop()
			if l then
				if not minL or l < minL then minL = l end
				if not maxR or rt > maxR then maxR = rt end
				if not minB or b < minB then minB = b end
				if not maxT or t > maxT then maxT = t end
			end
		end
	end
	if not minL then return end
	local r = c2cGetRing()
	r:SetParent(holder)
	-- Hover ring: above the WHOLE aura band (top holder +16 plus its children), not
	-- just above this holder — otherwise hovering the HoT row draws its ring under
	-- the debuff icons. Measured from the overlay so it is the same for all four.
	r:SetFrameLevel(holder._host.overlay:GetFrameLevel() + 24)
	r:ClearAllPoints()
	local hl, hb = holder:GetLeft() or 0, holder:GetBottom() or 0
	r:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", minL - hl - C2C_PAD, minB - hb - C2C_PAD)
	r:SetSize((maxR - minL) + C2C_PAD * 2, (maxT - minB) + C2C_PAD * 2)
	r:Show()
	if ns.W and ns.W.ShowTextTip then
		ns.W.ShowTextTip(r, ns.T(C2C_LABELS[holder._cat] or ""), ns.T("Click to edit"))
	end
end
function Raidframes:_C2CIconClick(holder)
	c2cJump(holder._host, "aura-" .. (holder._cat or ""))
end

local function pvFrame(i, holder)
	local f = pvFrames[i]
	if not f then
		f = CreateFrame("Frame", nil, holder)
		f._c2c = true   -- BEFORE any icon creation: makeAuraIcon keys off this
		Decorate(f)
		f:EnableMouse(false)
		-- Click-to-configure hotspots: ring + tooltip on hover, jump on click.
		-- Anchored to the element's region; pvFillOne gates each on visibility.
		-- `pad` = grow the hotspot beyond its region (default 3, comfortable for
		-- small texts/icons). The resource bar passes 0: it is a thin strip at the
		-- very bottom, and a padded hotspot would swallow clicks on the lower half
		-- of a bottom-anchored aura icon.
		local function hotspot(region, label, cardKey, pad)
			pad = pad or 3
			local b = CreateFrame("Button", nil, f.overlay)
			-- Above the texts + the role/leader layer (+1), but BELOW every aura
			-- holder (+4 and up): where an aura icon overlaps another element's
			-- hotspot the click has to open the AURA card — that is what is drawn on
			-- top there, and the icons carry their own scripts (makeAuraIcon).
			b:SetFrameLevel(f.overlay:GetFrameLevel() + 2)
			b:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
			b:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
			b:SetScript("OnEnter", function()
				local r = c2cGetRing()
				r:SetParent(b)
				r:SetFrameLevel(f.overlay:GetFrameLevel() + 24) -- above the aura band, as for the aura rings
				r:ClearAllPoints()
				r:SetAllPoints(b)
				r:Show()
				if ns.W and ns.W.ShowTextTip then
					ns.W.ShowTextTip(r, ns.T(label), ns.T("Click to edit"))
				end
			end)
			b:SetScript("OnLeave", function() Raidframes:_C2CLeave() end)
			b:SetScript("OnClick", function() c2cJump(f, cardKey) end)
			return b
		end
		f._c2cName  = hotspot(f.name,     "Text — name",       "text-name")
		f._c2cHP    = hotspot(f.htext,    "Text — HP display", "text-hp")
		f._c2cRole  = hotspot(f.roleIcon, "Role icon",         "icon-role")
		f._c2cLead  = hotspot(f.leadIcon, "Leader icon",       "icon-lead")
		f._c2cPower = hotspot(f.power,    "Resource bar",      "power-bar", 0)
		pvFrames[i] = f
	end
	f:SetParent(holder)
	-- Re-home the pooled frame on EVERY call: there is one pool but one anchored
	-- band per raidframe tab now, so a frame built for the first band would stay
	-- there and the other tabs would render an empty stage (Florian 2026-07-29:
	-- switching context on Base left Raid/Group blank). With the single dock
	-- band this could never happen.
	if f:GetParent() ~= holder then
		f:SetParent(holder)
		f:ClearAllPoints()
	end
	return f
end

-- Reset layers a previous eye-pass may have hidden; render + eye-pass then
-- hide again whatever settings/eyes say. Aura holders BEFORE ApplyConfig
-- (which re-hides config-disabled categories).
local function pvResetLayers(f)
	if f.auraHolders then for _, h in pairs(f.auraHolders) do h:Show() end end
	f.shieldStripe:Show(); f.backfillStripe:Show(); f.healStripe:Show()
	f.htext:Show()
end

-- Eyes only HIDE: the fill pass before restored everything the settings show.
-- Aura categories filter INDIVIDUALLY (holder keys = AURA_CATS keys, matching
-- the filter popover's children: hotsOwn/defensives/major/debuffs).
local function pvEyePass(f, eyes)
	if f.auraHolders then
		for key, h in pairs(f.auraHolders) do
			if eyes[key] == false then h:Hide() end
		end
	end
	if eyes.shields == false then
		f.shieldStripe:Hide(); f.backfillStripe:Hide(); f.healStripe:Hide()
	end
	-- Name and HP text are SEPARATE preview layers (Florian 2026-07-26: hiding
	-- one used to hide both). `text` stays understood as the old shared key so
	-- existing profiles keep working.
	if eyes.nameText == false or eyes.text == false then f.name:Hide() end
	if eyes.healthText == false or eyes.text == false then f.htext:Hide() end
	-- Role and leader are SEPARATE preview layers (Florian 2026-07-22): each card's
	-- eye toggles only its own icon (grouped under "Role & leader icons").
	if eyes.roleIcon == false then f.roleIcon:Hide() end
	if eyes.leaderIcon == false then f.leadIcon:Hide() end
end

-- Dispel/aggro filters work at the DATA level (a recolored health bar can't
-- be "hidden" afterwards): render a scratch copy without those fields.
-- The resource bar rides along here for the same reason: just hiding the strip
-- would leave a gap under the health bar, so "eye off" means "this unit has no
-- resource bar" and the health bar gets its height back.
local pvScratch = {}
local function pvEffectiveFake(fake, eyes)
	if (eyes.dispel == false and fake.dispel) or (eyes.aggro == false and fake.aggro)
		or eyes.power == false then
		for k in pairs(pvScratch) do pvScratch[k] = nil end
		for k, v in pairs(fake) do pvScratch[k] = v end
		if eyes.dispel == false then pvScratch.dispel = nil end
		if eyes.aggro == false then pvScratch.aggro = nil end
		if eyes.power == false then pvScratch.noPower = true end
		return pvScratch
	end
	return fake
end

local function pvFillOne(f, fake, ctx, eyes)
	setPreviewCtx(ctx)
	f._pvCtx = ctx   -- click-to-configure: which tab a click on this frame targets
	f.fake = pvEffectiveFake(fake, eyes)
	f.unit = nil
	pvResetLayers(f)
	Raidframes:ApplyConfig(f)
	Raidframes:UpdateUnit(f)
	pvEyePass(f, eyes)
	-- Hotspots only while their element is actually visible (config + eyes).
	if f._c2cName then
		f._c2cName:SetShown(f.name:IsShown())
		f._c2cHP:SetShown(f.htext:IsShown())
		f._c2cRole:SetShown(f.roleIcon:IsShown())
		f._c2cLead:SetShown(f.leadIcon:IsShown())
		f._c2cPower:SetShown(f.power:IsShown())
	end
	setPreviewCtx(nil)
	f:Show()
end

function Raidframes:AttachShellPreview(band, spec)
	shellBands[band] = spec
end

-- Which context a preview spec is showing right now.
local function pvSpecCtx(spec, d)
	if spec.ctxGet then return spec.ctxGet() end
	if spec.baseSwitch then return (d.previewBaseCtx == "raid") and "raid" or "party" end
	return spec.ctx
end

-- Sample size for a spec: the Raid tab has its 5/10/20/25 chips, a spec may pin
-- a raid-context count (Auras tab), everything else shows one group.
local function pvSpecCount(spec, ctx, d)
	local n = GROUP_SIZE
	-- Raid default is 10, not one group: five frames say nothing about a raid
	-- layout (Florian 2026-07-29, matching what the Auras tab pins).
	if spec.ctx == "raid" then n = d.previewSize or 10
	elseif spec.raidN and ctx == "raid" then n = spec.raidN end
	return min(n, 25)
end

-- Grid extent of a preview in HOLDER units (before the true-size scale).
local function pvExtent(spec, ctx, n, d)
	local L = d[ctx]
	local w, h, sp = L.width, L.height, L.spacing
	local horizontal = (L.orientation == "horizontal")
	local groups  = max(1, ceil(n / GROUP_SIZE))
	local inGroup = max(1, min(n, GROUP_SIZE))
	local cols, rows
	if horizontal then cols, rows = inGroup, groups else cols, rows = groups, inGroup end
	return cols * (w + sp) - sp, rows * (h + sp) - sp, horizontal
end

-- VISUAL height a preview needs, in the units of `ref` (the shell frame the
-- stage lives in). The anchored bands are placed by the settings stack BEFORE
-- anything renders, so the screen has to know the height up front — this is the
-- same arithmetic RefreshShellPreview uses, just without touching frames.
function Raidframes:PreviewExtent(spec, ref)
	local d = db()
	if not (d and ref) then return 1, 1 end
	local sUI, sRef = UIParent:GetEffectiveScale(), ref:GetEffectiveScale()
	if not (sUI and sRef) or sRef <= 0 then return 1, 1 end
	local ok, cw, ch = pcall(function()
		local ctx = pvSpecCtx(spec, d)
		local n = pvSpecCount(spec, ctx, d)
		local w, h = pvExtent(spec, ctx, n, d)
		return w, h
	end)
	if not ok then return 1, 1 end
	local s = sUI / sRef
	return (cw or 1) * s, (ch or 1) * s
end

function Raidframes:RefreshShellPreview()
	invalidatePreviewIcons()   -- pick up spec / whitelist changes on each redraw
	-- During an Edit Mode session the world previews mirror the same settings —
	-- refresh them regardless of the dock band's visibility (it starts collapsed),
	-- so live tab edits (size, opacity, auras, card eyes) show on the placed frames.
	-- (RefreshPreview self-guards via ensureEditPreviews.)
	if ns.EditMode and ns.EditMode.session then
		self:RefreshPreview("party")
		self:RefreshPreview("raid")
	end
	local band, spec
	for b, sp in pairs(shellBands) do
		if b:IsVisible() then band, spec = b, sp break end
	end
	if not band then return end
	local holder = band.holder
	local stage = holder:GetParent()
	-- True on-screen size: scale the holder so its effective scale matches
	-- UIParent (where the real frames live) despite the shell's panel scale.
	local sUI, sStage = UIParent:GetEffectiveScale(), stage:GetEffectiveScale()
	if not (sUI and sStage) or sStage <= 0 then return end
	local s = sUI / sStage
	holder:SetScale(s)

	local d = db()
	local eyes = band.GetEyes and band:GetEyes() or {}
	local used, cw, ch, caption = 0, 1, 1, ""

	-- Guarded fill: previewCtx MUST never leak into the real render paths.
	local ok, err = pcall(function()
		-- Context: fixed per tab (Raid/Group) — the Base tab switches via its
		-- Raid/Group chips instead (so Base settings like aggro/dispel are
		-- judged on the real group layout).
		-- Context / sample size / grid: shared with PreviewExtent above, so the
		-- height a screen reserved and the height actually rendered can't drift.
		local ctx = pvSpecCtx(spec, d)
		local n = pvSpecCount(spec, ctx, d)
		local L = d[ctx]
		local w, h, sp = L.width, L.height, L.spacing
		local horizontal = (L.orientation == "horizontal")
		-- 5 = the curated showcase roster; bigger samples use the test-mode
		-- roster incl. its role-sort preview (honest sorting picture).
		local list = (n <= GROUP_SIZE) and PREVIEW_FAKE or GetFakeList(n)
		for i = 1, n do
			local f = pvFrame(i, holder)
			pvFillOne(f, list[i], ctx, eyes)
			-- Same slot math as the test-mode grid: vertical = members
			-- stacked/groups side by side, horizontal = the transpose.
			local idx   = i - 1
			local group = floor(idx / GROUP_SIZE)
			local slot  = idx % GROUP_SIZE
			local col, row
			if horizontal then col, row = slot, group else col, row = group, slot end
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (w + sp), -row * (h + sp))
		end
		used = n
		cw, ch = pvExtent(spec, ctx, n, d)
		caption = ("%s  ·  %d  ·  %s"):format(
			ctx == "raid" and ns.T("Raid") or ns.T("Group"), n,
			horizontal and ns.T("horizontal") or ns.T("vertical"))
	end)
	setPreviewCtx(nil)
	if not ok then
		if ns.Lumen then ns.Lumen:Print("|cffD66A5CPreview:|r " .. tostring(err)) end
		return
	end

	for i = used + 1, #pvFrames do pvFrames[i]:Hide() end
	holder:SetSize(cw, ch)
	-- Report the VISUAL extent (stage units): holder units render at scale s.
	-- The band never resizes itself — the screen reserved its height up front via
	-- PreviewExtent, so 20 raid frames simply make the preview taller and push
	-- the cards further down (Florian 2026-07-29). Always TRUE on-screen size.
	band:SetExtent(cw * s, ch * s, caption)
end

-- ===========================================================================
--  Edit Mode two-frame previews (Group 5 / Raid 20). While a Lumen Edit Mode
--  session runs, the live secure frames are hidden and TWO placeable fake
--  previews are shown — one per context — so Group and Raid can be positioned
--  and sized INDEPENDENTLY (WoW-Edit-Mode style), even solo. Reuses the shell
--  preview fill (pvFillOne + previewCtx). Exiting restores the live frames.
-- ===========================================================================
local epPools = { party = {}, raid = {} }
local epHolders = {}          -- ctx -> world holder frame (mirrors the live 200x200 container)
-- The previews exist to POSITION/SIZE frames, not to judge appearance (that's the
-- tab dock). Show just the class-coloured health bars + names — no auras/shields/
-- icons/dispel/aggro — so overlapping Group/Raid previews stay clean (Florian).
local PREVIEW_EYES = {
	hotsOwn = false, defensives = false, major = false, debuffs = false,
	shields = false, icons = false, dispel = false, aggro = false,
}
local epListenerAdded = false

local function ensureEditPreviews()
	if epHolders.party then return end
	for _, ctx in ipairs({ "party", "raid" }) do
		-- The holder MIRRORS the live container EXACTLY (200x200, positioned by the
		-- same L.point) so a placed preview maps 1:1 to the real frames. The fakes
		-- live in a `.frames` child anchored at the holder TOPLEFT (like the secure
		-- header), which is also the Edit Mode bounds so the overlay hugs the frames.
		local h = CreateFrame("Frame", nil, UIParent)
		h:SetSize(200, 200)
		h:SetFrameStrata("HIGH")
		h:Hide()
		h.frames = CreateFrame("Frame", nil, h)
		h.frames:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
		epHolders[ctx] = h
	end
end

local function epFrame(ctx, i)
	local pool = epPools[ctx]
	local f = pool[i]
	if not f then
		f = CreateFrame("Frame", nil, epHolders[ctx].frames)
		Decorate(f)
		f:EnableMouse(false)   -- the Edit Mode overlay handles the mouse
		pool[i] = f
	end
	f:SetParent(epHolders[ctx].frames)
	return f
end

-- Lay out ctx's fake sample (5 party / 20 raid) at ctx's size/spacing and move
-- the holder to ctx's saved position. Called on show + on every slider change.
function Raidframes:RefreshPreview(ctx)
	invalidatePreviewIcons()   -- pick up spec / whitelist changes on each redraw
	ensureEditPreviews()
	local holder = epHolders[ctx]
	local L = db()[ctx]
	local w, h, sp = L.width or 114, L.height or 60, L.spacing or 6
	local horizontal = (L.orientation == "horizontal")
	local n = (ctx == "raid") and 20 or GROUP_SIZE
	local list = (n <= GROUP_SIZE) and PREVIEW_FAKE or GetFakeList(n)
	-- The LIT context (the one whose settings are open in the Shell) shows its
	-- eye-on layers (card eyes = db().previewEyes); every other context stays
	-- clean (bars + names only) so the world isn't cluttered while placing.
	local eyes = PREVIEW_EYES
	if self._litCtx == ctx then eyes = db().previewEyes or {} end
	local pool = epPools[ctx]
	for i = 1, n do
		local f = epFrame(ctx, i)
		pvFillOne(f, list[i], ctx, eyes)
		local idx   = i - 1
		local group = floor(idx / GROUP_SIZE)
		local slot  = idx % GROUP_SIZE
		local col, row
		if horizontal then col, row = slot, group else col, row = group, slot end
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", holder.frames, "TOPLEFT", col * (w + sp), -row * (h + sp))
	end
	for i = n + 1, #pool do if pool[i] then pool[i]:Hide() end end
	local groups  = max(1, ceil(n / GROUP_SIZE))
	local inGroup = max(1, min(n, GROUP_SIZE))
	local cols, rows
	if horizontal then cols, rows = inGroup, groups else cols, rows = groups, inGroup end
	holder.frames:SetSize(cols * (w + sp) - sp, rows * (h + sp) - sp)
	-- Position the 200x200 holder EXACTLY like the live container (applyHeaderLayout).
	holder:ClearAllPoints()
	holder:SetPoint(L.point or "CENTER", UIParent, L.point or "CENTER", L.x or 0, L.y or 0)
end

-- Session on/off: swap the live secure frames for the two previews, or restore.
-- Bring one preview's whole subtree in front of the other so a grabbed,
-- overlapping frame lies COMPLETELY on top (no interleaving of the two frames'
-- bars). Strata cascades to the fake frames + their bars (they never set their
-- own strata), so bumping the holder is enough.
function Raidframes:RaisePreview(ctx)
	local other = (ctx == "raid") and "party" or "raid"
	if epHolders[ctx] then epHolders[ctx]:SetFrameStrata("DIALOG") end
	if epHolders[other] then epHolders[other]:SetFrameStrata("HIGH") end
end

-- Which context is "lit" = shows its eye-on layers in Edit Mode (the one whose
-- settings are open in the Shell). nil = both clean. Set by the flyout's "Open
-- settings" and cleared when the Shell closes / the session ends.
function Raidframes:SetLitPreview(ctx)
	if self._litCtx == ctx then return end
	self._litCtx = ctx
	if ns.EditMode and ns.EditMode.session and epHolders.party then
		self:RefreshPreview("party")
		self:RefreshPreview("raid")
	end
end

function Raidframes:ShowEditPreviews(on)
	ensureEditPreviews()
	self._litCtx = nil   -- session boundary: start clean, nothing lit
	if on then
		self:HideHeader()
		Raidframes:_SetContainerShown(false)
		self:RefreshPreview("party")
		self:RefreshPreview("raid")
		epHolders.party:Show()
		epHolders.raid:Show()
		-- Defined z-order from the START (both stacked at the same default pos):
		-- without this they sit on the same strata and their bars INTERLEAVE (the
		-- back frame shows through the front, backgrounds look missing) until the
		-- first click raised one. Group on top by default.
		self:RaisePreview("party")
	else
		epHolders.party:Hide()
		epHolders.raid:Hide()
		Raidframes:_SetContainerShown(true)
		self:UpdateLayout()   -- rebuild + reposition the real header
	end
end

-- ===========================================================================
--  Edit-Mode registration — called once from Raidframes:Setup(). Lives here
--  rather than in Setup so `ensureEditPreviews` / `epHolders` / the listener
--  latch stay private to this file instead of crossing the boundary.
-- ===========================================================================
function Raidframes:_SetupEditPreviews()
if ns.EditMode then
	-- Two independent placeable previews (WoW-Edit-Mode style, Florian's call):
	-- "Group Frame" (5) and "Raid Frame" (20) — each edits its OWN context so
	-- Group and Raid can be placed/sized differently, even solo. The flyout is
	-- the spatial subset (size + spacing); visuals stay in the tab (Open settings).
	ensureEditPreviews()
	local function regPreview(ctx, key, label, tab)
		ns.EditMode:Register(epHolders[ctx], ns.T(label),
			function(p, x, y) local L = db()[ctx]; L.point, L.x, L.y = p, x, y end,
			function() return epHolders[ctx].frames end,   -- overlay/physics hug the fakes
			key,
			{ fields = {
				{ kind = "slider", label = ns.T("Width"),   min = 40, max = 240, unit = " px",
					get = function() return db()[ctx].width end,
					set = function(v) db()[ctx].width = v; Raidframes:RefreshPreview(ctx) end },
				{ kind = "slider", label = ns.T("Height"),  min = 20, max = 160, unit = " px",
					get = function() return db()[ctx].height end,
					set = function(v) db()[ctx].height = v; Raidframes:RefreshPreview(ctx) end },
				{ kind = "slider", label = ns.T("Spacing"), min = 0, max = 30, unit = " px",
					get = function() return db()[ctx].spacing end,
					set = function(v) db()[ctx].spacing = v; Raidframes:RefreshPreview(ctx) end },
			},
			-- Non-destructive: the session STAYS open (no CloseSession). The Shell
			-- opens alongside and this context lights up (SetLitPreview) so you
			-- see its auras/shields on the real placed frame while you edit.
			openSettings = function()
				Raidframes:SetLitPreview(ctx)
				if ns.Shell then ns.Shell:OpenTo("Raidframes", tab) end
			end,
			onRaise = function() Raidframes:RaisePreview(ctx) end })
	end
	regPreview("party", "raidframes_group", "Group Frame", "Group")
	regPreview("raid",  "raidframes_raid",  "Raid Frame",  "Raid")
	-- Show the previews (and hide the live frames) only during a Lumen session.
	if not epListenerAdded then
		epListenerAdded = true
		ns.EditMode:AddListener(function() Raidframes:ShowEditPreviews(ns.EditMode.session) end)
	end
end
end
