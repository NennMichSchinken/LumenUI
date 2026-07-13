local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Edit Mode (v2)
--  Movable Lumen elements get a drag overlay with a label. Overlays show when
--  EITHER a Lumen edit session runs (Shell sidebar button / Global tab button)
--  OR WoW's own Edit Mode is running (same drag physics, no Shell choreography).
--
--  v2 drag physics — hard rule: NEVER magnet-snap. Position is only LIMITED
--  (clamped) or HELD, never pulled toward anything:
--   * WALLS: the other registered elements are solid bodies — the dragged
--     frame stops flush at their edge, slides along it and releases instantly
--     (the desired position always follows the cursor, so nothing sticks).
--   * GROOVES: alignment lines (screen center axes + edges/centers of the
--     other elements) HOLD the position once the user's own movement reaches
--     them (±TOL); a small push across the line releases. While held, a gold
--     guide line is drawn (+ a px gap badge toward the aligned neighbor).
--   * Ctrl bypasses walls AND grooves (free placement/overlap).
--   * Click selects a mover; arrow keys nudge 1 px, Shift+arrow 10 px.
--
--  NOTE: this file loads BEFORE Shell/Tokens.lua (see LumenUI.toc) — no
--  ns.UI/ns.W at file scope. Toolbar, guide lines and badge are built LAZILY
--  on first use (at runtime the tokens/widgets are available).
-- ===========================================================================

local EditMode = { session = false, blizzard = false, active = false, items = {} }
ns.EditMode = EditMode

local floor = math.floor
local abs = math.abs
local pairs = pairs
local GetCursorPosition = GetCursorPosition
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local InCombatLockdown = InCombatLockdown

-- Groove hold zone in PHYSICAL screen px (Florian tuned 4 in the mockup,
-- 2026-07-13). Converted to UIParent units per drag (depends on UI scale).
local TOL_PX = 4
-- Show the px gap badge only for gaps that are worth reading.
local GAP_MIN = 7

-- Brand gold (palette C1 #E9BB69 — kept literal here: this file loads before
-- Shell/Tokens; runtime-built parts below use the real tokens instead).
local GOLD_R, GOLD_G, GOLD_B = 0.91, 0.73, 0.41
-- C2 interactive gold #CDA255 (coupled) + muted text #808283 (idle chain icon).
local GOLDINT_R, GOLDINT_G, GOLDINT_B = 0.80, 0.64, 0.33
local MUTED_R, MUTED_G, MUTED_B = 0.50, 0.51, 0.51

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local CHAIN = 20 -- chain-icon edge length (top-right of the overlay)

-- ---------------------------------------------------------------------------
--  Drag state — file-locals reused across drags (no tables/closures are
--  allocated inside the drag OnUpdate; CLAUDE.md §9 applies even here).
-- ---------------------------------------------------------------------------
-- Obstacle rects (all OTHER registered, visible elements), rebuilt into the
-- SAME arrays at drag start.
local obsL, obsB, obsR, obsT, obsN = {}, {}, {}, {}, 0
-- Alignment lines: position + source obstacle index (0 = screen center axis).
local vLine, vSrc, vN = {}, {}, 0
local hLine, hSrc, hN = {}, {}, 0
local drag = { frame = nil }
-- Frames that move WITH the dragged one (a dragged anchor takes its group) —
-- they must NOT act as walls against it. Rebuilt per drag (reused table).
local moveSet = {}
-- Group-aware physics (Phase 2): edge offsets (relative to the dragged bounds
-- origin) of EVERY moving member, so a groove can align ANY member's edge —
-- and the union bounding box of the whole group for the walls. Rebuilt per drag.
local vEO, vEON = {}, 0   -- vertical edge offsets (left/center/right of each member)
local hEO, hEON = {}, 0   -- horizontal edge offsets (bottom/center/top of each member)

-- Phase 2 (links): stable string key -> frame.
EditMode.byKey = {}

-- Shared event frame (session combat-exit, Blizzard Edit Mode hook, deferred
-- ApplyLinks out of combat). Declared here so ApplyLinks can reach it.
local evt = CreateFrame("Frame")

-- The editLinks profile table ({ [childKey] = { to, offX, offY } }).
local function linksDB()
	local L = ns.Lumen
	return L and L.db and L.db.profile and L.db.profile.editLinks
end

-- Does anchorKey's anchor chain already contain childKey? (cycle guard)
local function chainReaches(startKey, targetKey)
	local links = linksDB()
	local k, guard = startKey, 0
	while k and guard < 64 do
		if k == targetKey then return true end
		local e = links and links[k]
		k = e and e.to
		guard = guard + 1
	end
	return false
end

-- Frame rect in UIParent coordinate space (handles a differing effective
-- scale, e.g. if a registered frame ever runs its own SetScale).
local function rectOf(f)
	local l, b = f:GetLeft(), f:GetBottom()
	if not l then return nil end
	local eff = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * eff, b * eff, f:GetWidth() * eff, f:GetHeight() * eff
end

-- The frame whose VISIBLE bounds represent an element. Some movers (the
-- raidframes) sit inside a larger fixed container — walls/grooves/overlay must
-- follow the actual frames, not the padded container. info.boundsFn returns
-- that inner frame (may not exist yet at Register time -> re-evaluated live).
local function boundsFor(frame, info)
	if info and info.boundsFn then
		local bf = info.boundsFn()
		-- Only trust the inner bounds when it actually has a usable rect (a
		-- header with no visible frames can be 0-sized -> fall back to the frame).
		if bf and bf:GetLeft() and bf:GetWidth() > 8 and bf:GetHeight() > 8 then return bf end
	end
	return frame
end

local function hitsObstacle(x, y, w, h, i)
	return x < obsR[i] and x + w > obsL[i] and y < obsT[i] and y + h > obsB[i]
end

local function hitsAny(x, y, w, h)
	for i = 1, obsN do
		if hitsObstacle(x, y, w, h, i) then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------
--  Guide lines + px gap badge (lazy: needs runtime; badge uses the tokens).
-- ---------------------------------------------------------------------------
local guideHost, lineV, lineH, badge

local function ensureGuides()
	if guideHost then return end
	local UI = ns.UI
	guideHost = CreateFrame("Frame", nil, UIParent)
	guideHost:SetAllPoints(UIParent)
	guideHost:SetFrameStrata("TOOLTIP")
	guideHost:EnableMouse(false)
	guideHost:Hide()
	local function mkLine()
		local t = guideHost:CreateTexture(nil, "OVERLAY")
		if UI then UI.SetColor(t, UI.P.goldBrand)
		else t:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1) end
		t:SetAlpha(0.9)
		t:Hide()
		return t
	end
	lineV, lineH = mkLine(), mkLine()
	-- Pixel-snap rule (memory lumen-border-pixelsnap-rule): snap ONLY the
	-- thickness; positions run via plain SetPoint per update.
	local function snap()
		PixelUtil.SetWidth(lineV, 1)
		PixelUtil.SetHeight(lineH, 1)
	end
	snap()
	guideHost:HookScript("OnShow", snap)

	-- px gap badge (Figma-style spacing readout while a groove holds —
	-- approved by Florian in the mockup round 2026-07-13).
	if UI then
		badge = CreateFrame("Frame", nil, guideHost)
		badge:SetFrameLevel(guideHost:GetFrameLevel() + 2)
		local bg = { r = UI.P.inset.r, g = UI.P.inset.g, b = UI.P.inset.b, a = 0.92 }
		UI.RoundFill(badge, bg, "BACKGROUND", nil, UI.RADIUS.xs)
		UI.RoundBorder(badge, UI.line.mid, "OVERLAY", nil, UI.RADIUS.xs)
		badge.txt = UI.FS(badge, "caption", UI.P.goldBrand)
		badge.txt:SetPoint("CENTER", badge, "CENTER", 0, 0)
		badge:Hide()
	end
end

local function hideGuides()
	if not guideHost then return end
	lineV:Hide(); lineH:Hide()
	if badge then badge:Hide() end
	guideHost:Hide()
end

-- Place the badge showing the gap between the dragged rect and the guide's
-- source obstacle (only along the guide's axis, only for readable gaps).
local function showBadge(gap, bx, by)
	if not badge or gap < GAP_MIN then
		if badge then badge:Hide() end
		return
	end
	badge.txt:SetText(floor(gap + 0.5) .. " px")
	badge:SetSize(badge.txt:GetStringWidth() + 14, 22)
	badge:ClearAllPoints()
	badge:SetPoint("CENTER", guideHost, "BOTTOMLEFT", bx, by)
	badge:Show()
end

local function updateGuides(gvx, gvsrc, ghy, ghsrc, x, y)
	if not gvx and not ghy then
		hideGuides()
		return
	end
	ensureGuides()
	guideHost:Show()
	if gvx then
		lineV:ClearAllPoints()
		lineV:SetPoint("TOP", guideHost, "TOPLEFT", gvx, 0)
		lineV:SetPoint("BOTTOM", guideHost, "BOTTOMLEFT", gvx, 0)
		lineV:Show()
	else
		lineV:Hide()
	end
	if ghy then
		lineH:ClearAllPoints()
		lineH:SetPoint("LEFT", guideHost, "BOTTOMLEFT", 0, ghy)
		lineH:SetPoint("RIGHT", guideHost, "BOTTOMRIGHT", 0, ghy)
		lineH:Show()
	else
		lineH:Hide()
	end
	-- Badge: prefer the vertical guide's gap (element sources only), else the
	-- horizontal one. gvsrc/ghsrc = obstacle index, 0 = screen axis (no gap).
	local shown = false
	if gvx and gvsrc > 0 then
		local i = gvsrc
		if y > obsT[i] then
			showBadge(y - obsT[i], gvx, (y + obsT[i]) / 2); shown = true
		elseif obsB[i] > y + drag.h then
			showBadge(obsB[i] - (y + drag.h), gvx, (y + drag.h + obsB[i]) / 2); shown = true
		end
	end
	if not shown and ghy and ghsrc > 0 then
		local i = ghsrc
		if x > obsR[i] then
			showBadge(x - obsR[i], (x + obsR[i]) / 2, ghy); shown = true
		elseif obsL[i] > x + drag.w then
			showBadge(obsL[i] - (x + drag.w), (x + drag.w + obsL[i]) / 2, ghy); shown = true
		end
	end
	if not shown and badge then badge:Hide() end
end

-- ---------------------------------------------------------------------------
--  Connection lines between coupled elements (Phase 2). A subtle gold line
--  from each child's visible center to its anchor's center, shown while the
--  session runs. Pooled Line objects on a dedicated host BELOW the overlays.
-- ---------------------------------------------------------------------------
local linkHost, linkLines, linkLineN = nil, {}, 0

local function ensureLinkHost()
	if linkHost then return end
	linkHost = CreateFrame("Frame", nil, UIParent)
	linkHost:SetAllPoints(UIParent)
	linkHost:SetFrameStrata("FULLSCREEN") -- above the frames, below the FULLSCREEN_DIALOG overlays
	linkHost:EnableMouse(false)
	linkHost:Hide()
end

local function centerOf(frame, info)
	local l, b, w, h = rectOf(boundsFor(frame, info))
	if not l then return nil end
	return l + w / 2, b + h / 2
end

local function updateLinkLines()
	local links = linksDB()
	if not EditMode.active or not links or not next(links) then
		if linkHost then linkHost:Hide() end
		return
	end
	ensureLinkHost()
	linkHost:Show()
	local n = 0
	for childKey, e in pairs(links) do
		local cf, af = EditMode.byKey[childKey], e.to and EditMode.byKey[e.to]
		if cf and af and cf:IsShown() and af:IsShown() then
			local x1, y1 = centerOf(cf, EditMode.items[cf])
			local x2, y2 = centerOf(af, EditMode.items[af])
			if x1 and x2 then
				n = n + 1
				local ln = linkLines[n]
				if not ln then
					ln = linkHost:CreateLine(nil, "OVERLAY")
					ln:SetThickness(2)
					local col = ns.UI and ns.UI.P.goldBrand
					if col then ln:SetColorTexture(col.r, col.g, col.b, 0.45)
					else ln:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.45) end
					linkLines[n] = ln
				end
				ln:SetStartPoint("BOTTOMLEFT", linkHost, x1, y1)
				ln:SetEndPoint("BOTTOMLEFT", linkHost, x2, y2)
				ln:Show()
			end
		end
	end
	for i = n + 1, linkLineN do linkLines[i]:Hide() end
	linkLineN = n
end

-- Collect the obstacle rects + alignment lines of all OTHER visible movers
-- (using each one's VISIBLE bounds). Screen center axes are always targets.
-- Shared by the drag start and the arrow-key nudge (so nudging also aligns).
local function collectObstacles(frame)
	obsN, vN, hN = 0, 0, 0
	drag.screenW, drag.screenH = UIParent:GetWidth(), UIParent:GetHeight()
	vN = vN + 1; vLine[vN] = drag.screenW / 2; vSrc[vN] = 0
	hN = hN + 1; hLine[hN] = drag.screenH / 2; hSrc[hN] = 0
	for f, inf in pairs(EditMode.items) do
		if f ~= frame and not moveSet[f] and f:IsShown() then
			local ol, ob, ow, oh = rectOf(boundsFor(f, inf))
			if ol then
				obsN = obsN + 1
				obsL[obsN], obsB[obsN] = ol, ob
				obsR[obsN], obsT[obsN] = ol + ow, ob + oh
				vN = vN + 1; vLine[vN] = ol;          vSrc[vN] = obsN
				vN = vN + 1; vLine[vN] = ol + ow / 2; vSrc[vN] = obsN
				vN = vN + 1; vLine[vN] = ol + ow;     vSrc[vN] = obsN
				hN = hN + 1; hLine[hN] = ob;          hSrc[hN] = obsN
				hN = hN + 1; hLine[hN] = ob + oh / 2; hSrc[hN] = obsN
				hN = hN + 1; hLine[hN] = ob + oh;     hSrc[hN] = obsN
			end
		end
	end
end

-- Save a frame's CURRENT absolute position through its module save callback
-- (BOTTOMLEFT in UIParent units) — the always-fresh fallback used when a link's
-- anchor is unavailable.
local function saveAbsolute(f)
	local info = EditMode.items[f]
	if not (info and info.save) then return end
	local l, b = rectOf(f)
	if not l then return end
	local inv = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
	info.save("BOTTOMLEFT", floor(l * inv + 0.5), floor(b * inv + 0.5))
end

-- Fill moveSet with the frame + all elements anchored to it (chain), and
-- return the frame's own anchor frame (if it is itself a coupled child).
local function buildGroup(frame)
	wipe(moveSet)
	moveSet[frame] = true
	local info = EditMode.items[frame]
	local key = info and info.key
	local links = linksDB()
	if key and links then
		for k, e in pairs(links) do
			if e.to and chainReaches(k, key) then
				local cf = EditMode.byKey[k]
				if cf then moveSet[cf] = true end
			end
		end
	end
	if key and links and links[key] and links[key].to then
		return EditMode.byKey[links[key].to]
	end
	return nil
end

-- Persist a move: absolute fallback of the frame + every group member; if the
-- frame is a coupled child, re-freeze its offset to the anchor; re-apply links.
local function commitMove(frame, anchorFrame)
	saveAbsolute(frame)
	for f in pairs(moveSet) do if f ~= frame then saveAbsolute(f) end end
	local info = EditMode.items[frame]
	local key = info and info.key
	local links = linksDB()
	if key and links and links[key] and anchorFrame then
		local cl, cb = rectOf(frame)
		local al, ab = rectOf(anchorFrame)
		if cl and al then
			links[key].offX = floor(cl - al + 0.5)
			links[key].offY = floor(cb - ab + 0.5)
		end
	end
	EditMode:ApplyLinks()
	updateLinkLines()
end

-- ---------------------------------------------------------------------------
--  Drag loop (own SetPoint loop — StartMoving cannot be constrained).
-- ---------------------------------------------------------------------------
local function beginDrag(frame)
	local info = EditMode.items[frame]
	local ui = UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	-- Physics run in the element's VISIBLE-bounds space; the moved frame gets a
	-- translated position (delta = moved-frame origin - bounds origin, constant
	-- while dragging because the bounds frame is anchored inside the moved one).
	local bl, bb, bw, bh = rectOf(boundsFor(frame, info))
	local fl, fb = rectOf(frame)
	if not bl or not fl then return false end
	drag.frame = frame
	drag.deltaX, drag.deltaY = fl - bl, fb - bb
	drag.offX, drag.offY = cx / ui - bl, cy / ui - bb
	drag.grabX, drag.grabY = cx / ui, cy / ui
	drag.w, drag.h = bw, bh
	drag.lastX, drag.lastY = bl, bb
	drag.moved = false
	drag.tol = TOL_PX / ui

	-- Group handling (Phase 2): the dragged element + everything anchored to it
	-- (directly or via a chain) move together — exclude them from the walls so
	-- the group never collides with itself. If the dragged element is itself a
	-- coupled child, remember its anchor to re-freeze the offset on release.
	drag.anchorFrame = buildGroup(frame)
	local links = linksDB()
	drag.hasLinks = (links and next(links)) and true or false

	-- Build the moving group's edge offsets (grooves align ANY member's edge)
	-- + its union bounding box (walls keep the WHOLE group off the obstacles).
	vEON, hEON = 0, 0
	local uMinX, uMinY, uMaxX, uMaxY = 0, 0, bw, bh
	for f in pairs(moveSet) do
		local ml, mb, mw, mh
		if f == frame then ml, mb, mw, mh = bl, bb, bw, bh
		else ml, mb, mw, mh = rectOf(boundsFor(f, EditMode.items[f])) end
		if ml then
			local rdx, rdy = ml - bl, mb - bb
			vEON = vEON + 1; vEO[vEON] = rdx
			vEON = vEON + 1; vEO[vEON] = rdx + mw / 2
			vEON = vEON + 1; vEO[vEON] = rdx + mw
			hEON = hEON + 1; hEO[hEON] = rdy
			hEON = hEON + 1; hEO[hEON] = rdy + mh / 2
			hEON = hEON + 1; hEO[hEON] = rdy + mh
			if rdx < uMinX then uMinX = rdx end
			if rdy < uMinY then uMinY = rdy end
			if rdx + mw > uMaxX then uMaxX = rdx + mw end
			if rdy + mh > uMaxY then uMaxY = rdy + mh end
		end
	end
	drag.uOffX, drag.uOffY = uMinX, uMinY
	drag.uW, drag.uH = uMaxX - uMinX, uMaxY - uMinY

	collectObstacles(frame)
	return true
end

local function dragUpdate()
	local frame = drag.frame
	if not frame then return end
	local ui = UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local ux, uy = cx / ui, cy / ui
	-- A plain click must NEVER move the element (rule 1: nothing snaps/jumps) —
	-- the physics only starts once the cursor really travelled.
	if not drag.moved then
		if abs(ux - drag.grabX) + abs(uy - drag.grabY) < 2 then return end
		drag.moved = true
	end
	local x = ux - drag.offX
	local y = uy - drag.offY

	-- All physics runs on the group's UNION box (uOff/uW/uH); for a single
	-- element that is just its own rect. Screen clamp keeps the whole group on.
	local uox, uoy, uw, uh = drag.uOffX, drag.uOffY, drag.uW, drag.uH
	if x + uox < 0 then x = -uox elseif x + uox + uw > drag.screenW then x = drag.screenW - uox - uw end
	if y + uoy < 0 then y = -uoy elseif y + uoy + uh > drag.screenH then y = drag.screenH - uoy - uh end

	local gvx, ghy   -- active guide line positions (nil = none)
	local gvsrc, ghsrc = 0, 0
	if not IsControlKeyDown() then
		-- WALLS — the group's union box vs the obstacles, resolved PER AXIS so it
		-- slides along edges: first X against the previous Y, then Y against the
		-- resolved X. The clamp falls away as soon as the desired position is free
		-- (the desired position always hangs on the cursor — nothing sticks).
		local lx, ly = drag.lastX, drag.lastY
		for i = 1, obsN do
			if hitsObstacle(x + uox, ly + uoy, uw, uh, i) then
				if lx + uox + uw <= obsL[i] + 0.01 then x = obsL[i] - uw - uox
				elseif lx + uox >= obsR[i] - 0.01 then x = obsR[i] - uox
				else x = lx end
			end
		end
		for i = 1, obsN do
			if hitsObstacle(x + uox, y + uoy, uw, uh, i) then
				if ly + uoy + uh <= obsB[i] + 0.01 then y = obsB[i] - uh - uoy
				elseif ly + uoy >= obsT[i] - 0.01 then y = obsT[i] - uoy
				else y = ly end
			end
		end

		-- GROOVES — hold when ANY moving member's edge/center is within ±tol of a
		-- line (so a coupled child's edge aligns too, not just the dragged one).
		-- Walls have priority: a held position that would collide is discarded.
		local tol = drag.tol
		local bestD, bestX = tol + 0.001, nil
		for i = 1, vN do
			local L = vLine[i]
			for j = 1, vEON do
				local d = abs(x + vEO[j] - L)
				if d < bestD then bestD = d; bestX = L - vEO[j]; gvx = L; gvsrc = vSrc[i] end
			end
		end
		if bestX then
			if not hitsAny(bestX + uox, y + uoy, uw, uh) then x = bestX
			else gvx = nil; gvsrc = 0 end
		end
		local bestY
		bestD = tol + 0.001
		for i = 1, hN do
			local L = hLine[i]
			for j = 1, hEON do
				local d = abs(y + hEO[j] - L)
				if d < bestD then bestD = d; bestY = L - hEO[j]; ghy = L; ghsrc = hSrc[i] end
			end
		end
		if bestY then
			if not hitsAny(x + uox, bestY + uoy, uw, uh) then y = bestY
			else ghy = nil; ghsrc = 0 end
		end
	end

	if x ~= drag.lastX or y ~= drag.lastY then
		drag.lastX, drag.lastY = x, y
		-- Translate the bounds target to the moved frame (add the constant
		-- delta), then convert from UIParent units to the frame's own scale
		-- space (identity while all movers run scale 1).
		local inv = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (x + drag.deltaX) * inv, (y + drag.deltaY) * inv)
		-- Any connection line touching this element (as child or as anchor
		-- dragging its group) follows along.
		if drag.hasLinks then updateLinkLines() end
	end
	updateGuides(gvx, gvsrc, ghy, ghsrc, x, y)
end

local function endDrag(frame)
	if drag.frame ~= frame then return end
	hideGuides()
	if drag.moved then commitMove(frame, drag.anchorFrame) end
	drag.frame = nil
	EditMode:Select(frame) -- click AND drag both select (nudge target)
end

-- ---------------------------------------------------------------------------
--  Overlay per element
-- ---------------------------------------------------------------------------
local function makeOverlay(frame, label)
	local o = CreateFrame("Frame", nil, frame)
	o:SetAllPoints()
	-- Above the unit buttons (container/buttons are HIGH strata, and the buttons
	-- would otherwise eat the mouse over the actual frames — the reason the
	-- raidframes were only grabbable in their empty container padding).
	o:SetFrameStrata("FULLSCREEN_DIALOG")
	o:EnableMouse(true)

	o.bg = o:CreateTexture(nil, "BACKGROUND")
	o.bg:SetAllPoints()
	-- brand gold (palette C1 #E9BB69 — kept literal here: this file loads before Shell/Tokens)
	o.bg:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.25)

	local function line() local t = o:CreateTexture(nil, "BORDER"); t:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.9); return t end
	local t, b, l, r = line(), line(), line(), line()
	t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
	b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(1)
	l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(1)
	r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(1)
	o.edges = { t, b, l, r }

	o.text = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	o.text:SetPoint("CENTER")
	o.text:SetText(label)
	o.text:SetTextColor(1, 0.95, 0.82)

	-- Selection state (nudge target): clearly stronger gold border.
	function o:SetSelected(on)
		local thick = on and 2 or 1
		local alpha = on and 1 or 0.9
		for i = 1, 4 do self.edges[i]:SetAlpha(alpha) end
		t:SetHeight(thick); b:SetHeight(thick)
		l:SetWidth(thick); r:SetWidth(thick)
	end

	-- Chain (link) icon, top-right — Phase 2 coupling. Only keyed elements are
	-- couplable; Register hides it for keyless ones.
	local chain = CreateFrame("Button", nil, o)
	chain:SetSize(CHAIN, CHAIN)
	chain:SetPoint("TOPRIGHT", o, "TOPRIGHT", -1, -1)
	chain:SetFrameLevel(o:GetFrameLevel() + 10)
	local cbg = chain:CreateTexture(nil, "BACKGROUND")
	cbg:SetAllPoints(); cbg:SetColorTexture(0.06, 0.06, 0.07, 0.62)
	local cglyph = chain:CreateTexture(nil, "ARTWORK")
	cglyph:SetPoint("CENTER"); cglyph:SetSize(CHAIN - 8, CHAIN - 8)
	cglyph:SetTexture(TEX .. "icon-link")
	cglyph:SetSnapToPixelGrid(false); cglyph:SetTexelSnappingBias(0)
	cglyph:SetVertexColor(MUTED_R, MUTED_G, MUTED_B)
	o.chain, o.chainGlyph = chain, cglyph
	chain:SetScript("OnClick", function() EditMode:OnChainClick(frame) end)
	chain:SetScript("OnEnter", function()
		if not o._linked then cglyph:SetVertexColor(GOLD_R, GOLD_G, GOLD_B) end
	end)
	chain:SetScript("OnLeave", function()
		if not o._linked then cglyph:SetVertexColor(MUTED_R, MUTED_G, MUTED_B) end
	end)

	-- Coupled: filled gold icon. Idle: muted.
	function o:SetLinked(on)
		self._linked = on
		if on then cglyph:SetVertexColor(GOLDINT_R, GOLDINT_G, GOLDINT_B)
		else cglyph:SetVertexColor(MUTED_R, MUTED_G, MUTED_B) end
	end
	-- Link mode: this element is the source (brand-gold icon) or a candidate
	-- target (brighter fill inviting the click).
	function o:SetLinkSource(on)
		cglyph:SetVertexColor(on and GOLD_R or MUTED_R, on and GOLD_G or MUTED_G, on and GOLD_B or MUTED_B)
	end
	function o:SetLinkTarget(on)
		self.bg:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, on and 0.42 or 0.25)
		local a = on and 1 or 0.9
		for i = 1, 4 do self.edges[i]:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, a) end
	end

	o:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" then return end
		-- In link mode a body click on any OTHER element completes the coupling
		-- (never starts a drag); a click on the source does nothing.
		if EditMode.linkSource then
			if EditMode.linkSource ~= frame then EditMode:CompleteLink(frame) end
			return
		end
		if beginDrag(frame) then
			o:SetScript("OnUpdate", dragUpdate) -- runs ONLY while dragging
		end
	end)
	o:SetScript("OnMouseUp", function()
		o:SetScript("OnUpdate", nil)
		endDrag(frame)
	end)
	o:SetScript("OnHide", function()
		-- Element hidden mid-drag (e.g. combat teardown): stop cleanly.
		if drag.frame == frame then
			o:SetScript("OnUpdate", nil)
			drag.frame = nil
			hideGuides()
		end
	end)
	o:Hide()
	return o
end

-- ---------------------------------------------------------------------------
--  Selection + arrow-key nudge (session only)
-- ---------------------------------------------------------------------------
function EditMode:Select(frame)
	if self.selected == frame then return end
	hideGuides() -- a lingering nudge line belongs to the old selection
	if self.selected and self.items[self.selected] then
		self.items[self.selected].overlay:SetSelected(false)
	end
	self.selected = frame
	if frame and self.items[frame] then
		self.items[frame].overlay:SetSelected(true)
	end
end

-- ---------------------------------------------------------------------------
--  Linking (Phase 2): explicit coupling via the chain icon.
-- ---------------------------------------------------------------------------
local function keyOf(frame)
	local info = EditMode.items[frame]
	return info and info.key
end

-- Reflect each element's coupled state on its chain icon (called on activate +
-- after every link change).
function EditMode:_refreshChains()
	local links = linksDB()
	for frame, info in pairs(self.items) do
		local k = info.key
		info.overlay:SetLinked(k and links and links[k] ~= nil or false)
	end
end

function EditMode:StartLink(frame)
	local k = keyOf(frame)
	if not k then return end
	self.linkSource = frame
	for f, info in pairs(self.items) do
		if info.key and f:IsShown() then
			if f == frame then info.overlay:SetLinkSource(true)
			else info.overlay:SetLinkTarget(true) end
		end
	end
	if ns.Lumen then ns.Lumen:Print(ns.T("Pick an element to couple to (Esc cancels).")) end
end

function EditMode:CancelLink()
	if not self.linkSource then return end
	self.linkSource = nil
	for _, info in pairs(self.items) do
		info.overlay:SetLinkTarget(false)
	end
	self:_refreshChains()
end

function EditMode:CompleteLink(anchorFrame)
	local child = self.linkSource
	if not child or child == anchorFrame then return end
	local childKey, anchorKey = keyOf(child), keyOf(anchorFrame)
	if not childKey or not anchorKey then return end
	-- Cycle guard: refuse if the anchor already hangs (directly/chained) on the
	-- child. Keep link mode active so another target can be chosen.
	if chainReaches(anchorKey, childKey) then
		if ns.Lumen then ns.Lumen:Print(ns.T("Can't couple — that would create a loop.")) end
		return
	end
	local links = linksDB()
	if not links then return end
	-- Freeze the CURRENT offset so nothing jumps on coupling.
	local cl, cb = rectOf(child)
	local al, ab = rectOf(anchorFrame)
	if not cl or not al then return end
	links[childKey] = { to = anchorKey, offX = floor(cl - al + 0.5), offY = floor(cb - ab + 0.5) }
	self:CancelLink()
	self:ApplyLinks()
	self:_refreshChains()
	updateLinkLines()
end

function EditMode:Uncouple(frame)
	local k = keyOf(frame)
	local links = linksDB()
	if not k or not links or not links[k] then return end
	links[k] = nil
	saveAbsolute(frame) -- keep its current absolute position as the fallback
	-- Physically detach from the anchor at the current spot, otherwise its stale
	-- SetPoint would keep following the (now ex-)anchor when that moves.
	local l, b = rectOf(frame)
	if l then
		local inv = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * inv, b * inv)
	end
	self:_refreshChains()
	updateLinkLines()
end

function EditMode:OnChainClick(frame)
	if self.linkSource then
		if frame == self.linkSource then self:CancelLink()
		else self:CompleteLink(frame) end
		return
	end
	local k = keyOf(frame)
	local links = linksDB()
	if k and links and links[k] then self:Uncouple(frame)
	else self:StartLink(frame) end
end

-- Apply all links: anchor each coupled child's BOTTOMLEFT to its anchor frame
-- (the engine then moves the group in-game AND in Edit Mode — zero runtime
-- code). Fallback: anchor missing/hidden -> the child keeps its module-saved
-- absolute position (modules re-save it on every drag/nudge release).
function EditMode:ApplyLinks()
	local links = linksDB()
	if not links then return end
	if InCombatLockdown() then
		self._linkPending = true
		evt:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	for childKey, e in pairs(links) do
		local cf, af = self.byKey[childKey], e.to and self.byKey[e.to]
		if cf and af and af:IsShown() then
			cf:ClearAllPoints()
			cf:SetPoint("BOTTOMLEFT", af, "BOTTOMLEFT", e.offX or 0, e.offY or 0)
		end
	end
end

-- After a nudge, show the guide line(s) if the element now sits exactly on a
-- flight line — so keyboard aligning gets the same feedback as mouse dragging
-- (Florian's request 2026-07-13). Auto-hides shortly after the last nudge.
local nudgeTimer
local function showNudgeGuides(frame)
	local bl, bb, bw, bh = rectOf(boundsFor(frame, EditMode.items[frame]))
	if not bl then return end
	-- moveSet is current (nudgeSelected called buildGroup just before). Scan
	-- EVERY moving member's edges so a coupled child's edge shows a guide too.
	collectObstacles(frame)
	drag.w, drag.h = bw, bh
	local eps = 0.75
	local gvx, gvsrc, ghy, ghsrc
	for f in pairs(moveSet) do
		local ml, mb, mw, mh = rectOf(boundsFor(f, EditMode.items[f]))
		if ml then
			if not gvx then
				for i = 1, vN do
					local Lp = vLine[i]
					if abs(ml - Lp) < eps or abs(ml + mw / 2 - Lp) < eps or abs(ml + mw - Lp) < eps then
						gvx = Lp; gvsrc = vSrc[i]; break
					end
				end
			end
			if not ghy then
				for i = 1, hN do
					local Lp = hLine[i]
					if abs(mb - Lp) < eps or abs(mb + mh / 2 - Lp) < eps or abs(mb + mh - Lp) < eps then
						ghy = Lp; ghsrc = hSrc[i]; break
					end
				end
			end
		end
	end
	updateGuides(gvx, gvsrc or 0, ghy, ghsrc or 0, bl, bb)
	if nudgeTimer then nudgeTimer:Cancel(); nudgeTimer = nil end
	if gvx or ghy then
		nudgeTimer = C_Timer.NewTimer(1.2, function() hideGuides(); nudgeTimer = nil end)
	end
end

local function nudgeSelected(dx, dy)
	local frame = EditMode.selected
	if not frame or not frame:IsShown() then return end
	local l, b = rectOf(frame)
	if not l then return end
	local anchorFrame = buildGroup(frame) -- (also lets a nudged anchor keep its group)
	local inv = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (l + dx) * inv, (b + dy) * inv)
	commitMove(frame, anchorFrame)
	showNudgeGuides(frame)
end

-- Keyboard catcher: active ONLY while a Lumen session runs. HARD RULES from
-- memory lumen-secure-binding-gotchas: SetPropagateKeyboardInput may be called
-- ONLY inside OnKeyDown/OnKeyUp, and everything we don't handle must be
-- propagated — otherwise the keyboard locks up game-wide.
local kb
local function ensureKeyboard()
	if kb then return end
	kb = CreateFrame("Frame", nil, UIParent)
	kb:SetSize(1, 1)
	kb:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	kb:SetFrameStrata("TOOLTIP")
	kb:EnableKeyboard(false)
	kb:Hide()
	kb:SetScript("OnKeyDown", function(self, key)
		if not EditMode.session then
			self:SetPropagateKeyboardInput(true)
			return
		end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			-- Esc first backs out of link mode, then ends the session.
			if EditMode.linkSource then EditMode:CancelLink()
			else EditMode:CloseSession(true) end
			return
		end
		if EditMode.selected then
			local step = IsShiftKeyDown() and 10 or 1
			if key == "UP" then
				self:SetPropagateKeyboardInput(false); nudgeSelected(0, step); return
			elseif key == "DOWN" then
				self:SetPropagateKeyboardInput(false); nudgeSelected(0, -step); return
			elseif key == "LEFT" then
				self:SetPropagateKeyboardInput(false); nudgeSelected(-step, 0); return
			elseif key == "RIGHT" then
				self:SetPropagateKeyboardInput(false); nudgeSelected(step, 0); return
			end
		end
		self:SetPropagateKeyboardInput(true)
	end)
end

-- ---------------------------------------------------------------------------
--  Floating toolbar (lazy: built from tokens/widgets at runtime)
-- ---------------------------------------------------------------------------
local toolbar
local function ensureToolbar()
	if toolbar then return end
	local UI, W = ns.UI, ns.W
	local T = ns.T
	toolbar = CreateFrame("Frame", "LumenEditModeToolbar", UIParent)
	toolbar:SetFrameStrata("TOOLTIP")
	toolbar:SetClampedToScreen(true)
	toolbar:EnableMouse(true)
	toolbar:SetMovable(true)
	toolbar:RegisterForDrag("LeftButton")
	toolbar:SetScript("OnDragStart", toolbar.StartMoving)
	toolbar:SetScript("OnDragStop", toolbar.StopMovingOrSizing)
	UI.RoundFill(toolbar, UI.P.panel, "BACKGROUND", nil, UI.RADIUS.lg)
	UI.RoundBorder(toolbar, UI.line.mid, "BORDER", nil, UI.RADIUS.lg)

	-- Grip glyph (Lucide grip-vertical): a visual "grab me" affordance at the
	-- front (Florian 2026-07-13). The whole toolbar is the drag handle.
	local grip = toolbar:CreateTexture(nil, "ARTWORK")
	grip:SetSize(14, 14)
	grip:SetTexture(TEX .. "icon-grip")
	grip:SetSnapToPixelGrid(false)
	grip:SetTexelSnappingBias(0)
	grip:SetVertexColor(UI.P.textSecondary.r, UI.P.textSecondary.g, UI.P.textSecondary.b)
	toolbar._grip = grip

	-- EDIT MODE wordmark-style label (brand gold, non-clickable = C1).
	local mark = UI.FS(toolbar, "groupTitle", UI.P.goldBrand)
	mark:SetText(UI.Track("EDIT MODE", " "))
	toolbar._mark = mark

	local done = W.Button(toolbar, { text = T("Done"), variant = "primary",
		onClick = function() EditMode:CloseSession(true) end })
	toolbar._done = done

	local hint = UI.FS(toolbar, "caption", UI.P.textSecondary)
	hint:SetText(T("Ctrl = move freely · Arrows = 1 px · Shift = 10 px"))
	toolbar._hint = hint

	-- Horizontal layout: mark | Done | hint. Width from the measured parts;
	-- re-fit on show (cold-start fonts can measure 0 on the very first frame).
	local M = UI.WIDGET
	local pad, gap = M.sectionPad, M.sectionPad
	local gripGap = M.btnIconGap
	function toolbar:_fit()
		local w = pad + grip:GetWidth() + gripGap + mark:GetStringWidth() + gap
			+ done:GetWidth() + gap + hint:GetStringWidth() + pad
		self:SetSize(w, M.buttonH + 24)
		grip:ClearAllPoints()
		grip:SetPoint("LEFT", self, "LEFT", pad, 0)
		mark:ClearAllPoints()
		mark:SetPoint("LEFT", grip, "RIGHT", gripGap, 0)
		done:ClearAllPoints()
		done:SetPoint("LEFT", mark, "RIGHT", gap, 0)
		hint:ClearAllPoints()
		hint:SetPoint("LEFT", done, "RIGHT", gap, 0)
	end
	toolbar:_fit()
	toolbar:HookScript("OnShow", function(self) C_Timer.After(0, function() self:_fit() end) end)
	toolbar:SetPoint("TOP", UIParent, "TOP", 0, -24)
	toolbar:Hide()
end

-- ---------------------------------------------------------------------------
--  Registry + activation
-- ---------------------------------------------------------------------------
-- Anchor every overlay to its element's VISIBLE bounds (the raidframes' inner
-- header may only get its real size a frame after the session opens) so the
-- gold box + label hug the frames, not the padded container.
function EditMode:_anchorOverlays()
	if not self.active then return end
	for frame, info in pairs(self.items) do
		local bf = boundsFor(frame, info)
		info.overlay:ClearAllPoints()
		info.overlay:SetAllPoints(bf)
	end
end

function EditMode:_refresh()
	self.active = self.session or self.blizzard
	for _, info in pairs(self.items) do
		info.overlay:SetShown(self.active)
	end
	-- Notify listeners FIRST (e.g. QoL trackers force-show + register while
	-- unlocked so instance-only elements can be placed anywhere) — so the
	-- chain/link pass below also covers freshly registered elements.
	if self.listeners then
		for i = 1, #self.listeners do pcall(self.listeners[i], self.active) end
	end
	if self.active then
		self:_anchorOverlays()
		self:_refreshChains()
		self:ApplyLinks()
	end
	updateLinkLines() -- shows coupled-pair lines while active, hides otherwise
end

function EditMode:AddListener(fn)
	self.listeners = self.listeners or {}
	self.listeners[#self.listeners + 1] = fn
end

-- boundsFn (optional): a function returning the frame whose VISIBLE bounds
-- represent this element for walls/grooves/overlay, when it differs from the
-- moved frame (e.g. the raidframes live in a larger fixed container).
-- key (optional): a stable string id -> the element is COUPLABLE (Phase 2).
function EditMode:Register(frame, label, save, boundsFn, key)
	if self.items[frame] then return end
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	local info = { label = label, save = save, boundsFn = boundsFn, key = key, overlay = makeOverlay(frame, label) }
	self.items[frame] = info
	if key then self.byKey[key] = frame else info.overlay.chain:Hide() end
	if self.active then
		local bf = boundsFor(frame, info)
		info.overlay:ClearAllPoints()
		info.overlay:SetAllPoints(bf)
		info.overlay:SetLinked(key and linksDB() and linksDB()[key] ~= nil or false)
		info.overlay:Show()
	end
end

-- ---------------------------------------------------------------------------
--  Session (the Lumen path: Shell hides, toolbar shows, ESC/combat ends)
-- ---------------------------------------------------------------------------
function EditMode:OpenSession()
	if self.session then return end
	if InCombatLockdown() then
		if ns.Lumen then ns.Lumen:Print(ns.T("Edit Mode is not available in combat.")) end
		return
	end
	self.session = true
	-- The Shell would cover the elements — hide it and reopen it on Done/ESC
	-- (it keeps its section/tab state itself).
	self._reopenShell = (ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown()) or false
	if self._reopenShell then ns.Shell:Hide() end
	ensureToolbar()
	-- Constant physical size like the Shell (same scale source).
	if ns.Shell and ns.Shell._frame then toolbar:SetScale(ns.Shell._frame:GetScale()) end
	toolbar:Show()
	ensureKeyboard()
	kb:EnableKeyboard(true)
	kb:Show()
	evt:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:_refresh()
	-- Re-anchor once more next frame: the raidframes' header can resolve its
	-- real size only after this frame, leaving the overlay on the container.
	C_Timer.After(0, function() self:_anchorOverlays() end)
end

function EditMode:CloseSession(reopenShell)
	if not self.session then return end
	self.session = false
	self:CancelLink()
	self:Select(nil)
	if toolbar then toolbar:Hide() end
	if kb then kb:EnableKeyboard(false); kb:Hide() end
	hideGuides()
	evt:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:_refresh()
	-- Positions are already saved per drag release / nudge — nothing to flush.
	if reopenShell and self._reopenShell and ns.Shell and not InCombatLockdown() then
		ns.Shell:Show()
	end
	self._reopenShell = false
end

-- Legacy API (pre-v2 callers): manual toggle -> session.
function EditMode:Toggle(on)
	if on then self:OpenSession() else self:CloseSession(false) end
end

function EditMode:SetBlizzard(on)       -- WoW Edit Mode (no Shell choreography)
	self.blizzard = on and true or false
	self:_refresh()
end

function EditMode:IsActive() return self.session end

-- Combat starts -> end the session immediately and cleanly (toolbar closed,
-- overlays hidden, NO Shell reopen in combat).
evt:RegisterEvent("PLAYER_LOGIN")
evt:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		EditMode:CloseSession(false)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		evt:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if EditMode._linkPending then
			EditMode._linkPending = false
			EditMode:ApplyLinks()
		end
		return
	end
	-- PLAYER_LOGIN: hook into WoW's Edit Mode so Lumen movers show up there too.
	if EditModeManagerFrame then
		if EditModeManagerFrame.EnterEditMode then
			hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() EditMode:SetBlizzard(true) end)
		end
		if EditModeManagerFrame.ExitEditMode then
			hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() EditMode:SetBlizzard(false) end)
		end
	end
end)
