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
--     guide line is drawn.
--   * SPACING: while moving/nudging, a Figma-style measure (short gold segment
--     with end ticks + a px badge) shows the LIVE gap to the nearest element
--     that shares the moving group's row/column — so fine-tuning a distance is
--     readable without needing an edge to snap. Nearest neighbour per axis,
--     capped to nearby elements.
--   * Ctrl bypasses walls AND grooves (free placement/overlap).
--   * Click selects a mover; arrow keys nudge 1 px, Shift+arrow 10 px.
--
--  NOTE: this file loads BEFORE Shell/Tokens.lua (see LumenUI.toc) — no
--  ns.UI/ns.W at file scope. Toolbar, guide lines and measures are built LAZILY
--  on first use (at runtime the tokens/widgets are available).
-- ===========================================================================

local EditMode = { session = false, blizzard = false, active = false, items = {} }
ns.EditMode = EditMode

local floor = math.floor
local abs = math.abs
local min = math.min
local max = math.max
local pairs = pairs
local GetCursorPosition = GetCursorPosition
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local InCombatLockdown = InCombatLockdown

-- Groove hold zone in PHYSICAL screen px (Florian tuned 4 in the mockup,
-- 2026-07-13). Converted to UIParent units per drag (depends on UI scale).
local TOL_PX = 4

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
-- Alignment (flight) line positions — screen center axes + edges/centers of the
-- other elements. Rebuilt per drag/nudge.
local vLine, vN = {}, 0
local hLine, hN = {}, 0
local drag = { frame = nil }
-- Soft-wall pass-through per obstacle (Florian): a wall RESISTS, but pushing the
-- group into an obstacle breaks through (overlap) without Ctrl, and re-arms only
-- once the group is fully clear again. Breakaway triggers at a modest PENETRATION
-- (BREAK_FRAC of the dragged box on BOTH axes) -- earlier than "drag the majority
-- over" (the old center-crossing rule felt locked). Tunable. Rebuilt per drag.
local BREAK_FRAC = 0.15
local passThrough = {}
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

-- True if the box hits any ARMED obstacle (pass-through ones are ignored) — so a
-- groove can align (e.g. center the Raid inside the Group frame) once broken through.
local function hitsAnyWall(x, y, w, h)
	for i = 1, obsN do
		if not passThrough[i] and hitsObstacle(x, y, w, h, i) then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------
--  Alignment guide lines + Figma-style neighbour spacing measures. Everything
--  is drawn on one TOOLTIP-strata host, built lazily (this file loads before
--  Shell/Tokens, so the badge chrome is only built once ns.UI is available).
-- ---------------------------------------------------------------------------
local guideHost, lineV, lineH
local measH, measV            -- neighbour spacing measure per axis: { line, cap1, cap2, badge }
local CAP_LEN = 6             -- measure end-tick length (UIParent units)

local function ensureGuides()
	if guideHost then return end
	local UI = ns.UI
	guideHost = CreateFrame("Frame", nil, UIParent)
	guideHost:SetAllPoints(UIParent)
	guideHost:SetFrameStrata("TOOLTIP")
	guideHost:EnableMouse(false)
	guideHost:Hide()
	local function mkTex(a)
		local t = guideHost:CreateTexture(nil, "OVERLAY")
		if UI then UI.SetColor(t, UI.P.goldBrand)
		else t:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1) end
		t:SetAlpha(a or 0.9)
		t:Hide()
		return t
	end
	lineV, lineH = mkTex(), mkTex()
	-- Pixel-snap rule (memory lumen-border-pixelsnap-rule): snap ONLY the
	-- thickness; positions run via plain SetPoint per update.
	local function snap()
		PixelUtil.SetWidth(lineV, 1)
		PixelUtil.SetHeight(lineH, 1)
	end
	snap()
	guideHost:HookScript("OnShow", snap)

	-- Neighbour spacing measure = a short gold segment with end ticks + a px
	-- badge broken into its middle (Figma-style; Florian 2026-07-15). Shows the
	-- live gap to the nearest element that shares a row/column while moving.
	if UI then
		local function mkBadge()
			local b = CreateFrame("Frame", nil, guideHost)
			b:SetFrameLevel(guideHost:GetFrameLevel() + 2)
			local bg = { r = UI.P.inset.r, g = UI.P.inset.g, b = UI.P.inset.b, a = 0.92 }
			UI.RoundFill(b, bg, "BACKGROUND", nil, UI.RADIUS.xs)
			UI.RoundBorder(b, UI.line.mid, "OVERLAY", nil, UI.RADIUS.xs)
			b.txt = UI.FS(b, "caption", UI.P.goldBrand)
			b.txt:SetPoint("CENTER", b, "CENTER", 0, 0)
			b:Hide()
			return b
		end
		measH = { line = mkTex(), cap1 = mkTex(), cap2 = mkTex(), badge = mkBadge() }
		measV = { line = mkTex(), cap1 = mkTex(), cap2 = mkTex(), badge = mkBadge() }
	end
end

local function hideMeasure(m)
	if not m then return end
	m.line:Hide(); m.cap1:Hide(); m.cap2:Hide(); m.badge:Hide()
end

local function hideGuides()
	if not guideHost then return end
	lineV:Hide(); lineH:Hide()
	hideMeasure(measH); hideMeasure(measV)
	guideHost:Hide()
end

-- Draw a horizontal spacing measure (gap along X) between xa<xb at height y.
local function drawMeasureH(gap, xa, xb, y)
	if not measH then return false end
	local m = measH
	local mid = (xa + xb) / 2
	m.line:ClearAllPoints(); m.line:SetPoint("CENTER", guideHost, "BOTTOMLEFT", mid, y)
	m.line:SetWidth(xb - xa); PixelUtil.SetHeight(m.line, 1)
	m.cap1:ClearAllPoints(); m.cap1:SetPoint("CENTER", guideHost, "BOTTOMLEFT", xa, y)
	m.cap1:SetHeight(CAP_LEN); PixelUtil.SetWidth(m.cap1, 1)
	m.cap2:ClearAllPoints(); m.cap2:SetPoint("CENTER", guideHost, "BOTTOMLEFT", xb, y)
	m.cap2:SetHeight(CAP_LEN); PixelUtil.SetWidth(m.cap2, 1)
	m.badge.txt:SetText(floor(gap + 0.5) .. " px")
	m.badge:SetSize(m.badge.txt:GetStringWidth() + 14, 22)
	m.badge:ClearAllPoints(); m.badge:SetPoint("CENTER", guideHost, "BOTTOMLEFT", mid, y)
	m.line:Show(); m.cap1:Show(); m.cap2:Show(); m.badge:Show()
	return true
end

-- Draw a vertical spacing measure (gap along Y) between ya<yb at column x.
local function drawMeasureV(gap, ya, yb, x)
	if not measV then return false end
	local m = measV
	local mid = (ya + yb) / 2
	m.line:ClearAllPoints(); m.line:SetPoint("CENTER", guideHost, "BOTTOMLEFT", x, mid)
	m.line:SetHeight(yb - ya); PixelUtil.SetWidth(m.line, 1)
	m.cap1:ClearAllPoints(); m.cap1:SetPoint("CENTER", guideHost, "BOTTOMLEFT", x, ya)
	m.cap1:SetWidth(CAP_LEN); PixelUtil.SetHeight(m.cap1, 1)
	m.cap2:ClearAllPoints(); m.cap2:SetPoint("CENTER", guideHost, "BOTTOMLEFT", x, yb)
	m.cap2:SetWidth(CAP_LEN); PixelUtil.SetHeight(m.cap2, 1)
	m.badge.txt:SetText(floor(gap + 0.5) .. " px")
	m.badge:SetSize(m.badge.txt:GetStringWidth() + 14, 22)
	m.badge:ClearAllPoints(); m.badge:SetPoint("CENTER", guideHost, "BOTTOMLEFT", x, mid)
	m.line:Show(); m.cap1:Show(); m.cap2:Show(); m.badge:Show()
	return true
end

-- Figma-style live spacing: for the moving group's union box, show the gap to
-- the NEAREST other element that overlaps it on the cross axis (a row → the
-- horizontal gap; a column → the vertical gap). Capped to nearby neighbours so
-- a lone far element (the old "722 px to screen centre" annoyance) never shows.
-- Runs every drag/nudge frame, independent of whether a groove line is holding.
local MEAS_MIN = 2   -- below this the elements are touching (wall feedback covers it)
local function computeSpacing(gl, gb, gw, gh)
	local gr, gt = gl + gw, gb + gh
	local ui = UIParent:GetEffectiveScale()
	local ovl = 12 / ui       -- cross-axis overlap tolerance (≈ physical px)
	local cap = 500 / ui      -- max neighbour distance worth reading
	local hGap, hxa, hxb, hy
	local vGap, vya, vyb, vx
	for i = 1, obsN do
		local ol, ob, orr, ot = obsL[i], obsB[i], obsR[i], obsT[i]
		-- horizontal spacing needs a VERTICAL overlap (neighbour shares the row)
		if min(gt, ot) - max(gb, ob) > -ovl then
			local yMid = (max(gb, ob) + min(gt, ot)) / 2
			local g = ol - gr                       -- neighbour to the right
			if g >= MEAS_MIN and g <= cap and (not hGap or g < hGap) then hGap, hxa, hxb, hy = g, gr, ol, yMid end
			g = gl - orr                            -- neighbour to the left
			if g >= MEAS_MIN and g <= cap and (not hGap or g < hGap) then hGap, hxa, hxb, hy = g, orr, gl, yMid end
		end
		-- vertical spacing needs a HORIZONTAL overlap (neighbour shares the column)
		if min(gr, orr) - max(gl, ol) > -ovl then
			local xMid = (max(gl, ol) + min(gr, orr)) / 2
			local g = ob - gt                       -- neighbour above
			if g >= MEAS_MIN and g <= cap and (not vGap or g < vGap) then vGap, vya, vyb, vx = g, gt, ob, xMid end
			g = gb - ot                             -- neighbour below
			if g >= MEAS_MIN and g <= cap and (not vGap or g < vGap) then vGap, vya, vyb, vx = g, ot, gb, xMid end
		end
	end
	local any = false
	if hGap then any = drawMeasureH(hGap, hxa, hxb, hy) or any else hideMeasure(measH) end
	if vGap then any = drawMeasureV(vGap, vya, vyb, vx) or any else hideMeasure(measV) end
	return any
end

-- Draw the alignment flight lines (gvx/ghy, nil = none) AND the neighbour
-- spacing measures for the moving group's union box, then show/hide the host.
-- Returns true if anything is visible (used to arm the nudge auto-hide timer).
local function renderFeedback(gvx, ghy, gl, gb, gw, gh)
	ensureGuides()
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
	local anyMeas = computeSpacing(gl, gb, gw, gh)
	local shown = (gvx and true) or (ghy and true) or anyMeas
	if shown then guideHost:Show() else hideGuides() end
	return shown
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
	vN = vN + 1; vLine[vN] = drag.screenW / 2
	hN = hN + 1; hLine[hN] = drag.screenH / 2
	for f, inf in pairs(EditMode.items) do
		if f ~= frame and not moveSet[f] and f:IsShown() then
			local ol, ob, ow, oh = rectOf(boundsFor(f, inf))
			if ol then
				obsN = obsN + 1
				obsL[obsN], obsB[obsN] = ol, ob
				obsR[obsN], obsT[obsN] = ol + ow, ob + oh
				vN = vN + 1; vLine[vN] = ol
				vN = vN + 1; vLine[vN] = ol + ow / 2
				vN = vN + 1; vLine[vN] = ol + ow
				hN = hN + 1; hLine[hN] = ob
				hN = hN + 1; hLine[hN] = ob + oh / 2
				hN = hN + 1; hLine[hN] = ob + oh
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
	-- Soft-wall init: obstacles the group ALREADY overlaps start passed-through, so
	-- a stacked default (Group inside Raid) never feels locked — you can drag out.
	for i = 1, obsN do
		passThrough[i] = hitsObstacle(drag.lastX + drag.uOffX, drag.lastY + drag.uOffY, drag.uW, drag.uH, i)
	end
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
		EditMode:_hidePanel() -- a flyout would sit stale over the moving element
	end
	local x = ux - drag.offX
	local y = uy - drag.offY

	-- All physics runs on the group's UNION box (uOff/uW/uH); for a single
	-- element that is just its own rect. Screen clamp keeps the whole group on.
	local uox, uoy, uw, uh = drag.uOffX, drag.uOffY, drag.uW, drag.uH
	if x + uox < 0 then x = -uox elseif x + uox + uw > drag.screenW then x = drag.screenW - uox - uw end
	if y + uoy < 0 then y = -uoy elseif y + uoy + uh > drag.screenH then y = drag.screenH - uoy - uh end

	local gvx, ghy   -- active guide line positions (nil = none)
	if not IsControlKeyDown() then
		-- WALLS — the group's union box vs the obstacles, resolved PER AXIS so it
		-- slides along edges: first X against the previous Y, then Y against the
		-- resolved X. The clamp falls away as soon as the desired position is free
		-- (the desired position always hangs on the cursor — nothing sticks).
		local lx, ly = drag.lastX, drag.lastY
		-- Soft walls: a wall for obstacle i turns OFF once the group's desired box
		-- penetrates i by BREAK_FRAC on BOTH axes (breakaway → overlap without Ctrl,
		-- from any side, well before the majority is over) and re-arms only when the
		-- group is FULLY clear of i again (so dragging back out stays free too).
		local bx, by = x + uox, y + uoy
		for i = 1, obsN do
			if passThrough[i] then
				if not hitsObstacle(bx, by, uw, uh, i) then passThrough[i] = false end
			else
				local ox = min(bx + uw, obsR[i]) - max(bx, obsL[i])
				local oy = min(by + uh, obsT[i]) - max(by, obsB[i])
				if ox > BREAK_FRAC * uw and oy > BREAK_FRAC * uh then passThrough[i] = true end
			end
		end
		for i = 1, obsN do
			if not passThrough[i] and hitsObstacle(x + uox, ly + uoy, uw, uh, i) then
				if lx + uox + uw <= obsL[i] + 0.01 then x = obsL[i] - uw - uox
				elseif lx + uox >= obsR[i] - 0.01 then x = obsR[i] - uox
				else x = lx end
			end
		end
		for i = 1, obsN do
			if not passThrough[i] and hitsObstacle(x + uox, y + uoy, uw, uh, i) then
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
				if d < bestD then bestD = d; bestX = L - vEO[j]; gvx = L end
			end
		end
		if bestX then
			if not hitsAnyWall(bestX + uox, y + uoy, uw, uh) then x = bestX
			else gvx = nil end
		end
		local bestY
		bestD = tol + 0.001
		for i = 1, hN do
			local L = hLine[i]
			for j = 1, hEON do
				local d = abs(y + hEO[j] - L)
				if d < bestD then bestD = d; bestY = L - hEO[j]; ghy = L end
			end
		end
		if bestY then
			if not hitsAnyWall(x + uox, bestY + uoy, uw, uh) then y = bestY
			else ghy = nil end
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
	renderFeedback(gvx, ghy, x + uox, y + uoy, uw, uh)
end

local function endDrag(frame)
	if drag.frame ~= frame then return end
	hideGuides()
	local moved = drag.moved
	if moved then commitMove(frame, drag.anchorFrame) end
	drag.frame = nil
	if moved then
		EditMode:Select(frame) -- a drag just re-affirms the dragged element
	else
		-- Click: if this element is already selected and peers sit under the cursor,
		-- cycle to the next (reach a stacked frame); raise it so a follow-up drag
		-- grabs it. Then open the flyout.
		local target = frame
		if EditMode.selected == frame then
			local nxt = EditMode:_nextUnderCursor(frame)
			if nxt then target = nxt end
		end
		EditMode:Select(target)
		EditMode:_raise(target)
		EditMode:_updatePanel()
	end
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
		self.bg:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, on and 0.40 or 0.25)
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
			EditMode:_raise(frame) -- grabbed element comes fully to the front
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
	-- Hover highlight so you see which stacked element you'd grab before clicking.
	o:SetScript("OnEnter", function()
		if EditMode.selected ~= frame and not EditMode.linkSource then
			o.bg:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.36)
		end
	end)
	o:SetScript("OnLeave", function()
		if EditMode.selected ~= frame and not EditMode.linkSource then
			o.bg:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 0.25)
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
		-- Shell already open (coexisting)? Selecting another element jumps straight
		-- to its settings tab + relights it — no second "Open settings" click
		-- (Florian 2026-07-16). When the Shell is closed, selection just shows the
		-- flyout (below); its "Open settings" is the explicit opener.
		local info = self.items[frame]
		if info.quick and info.quick.openSettings
			and ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown() then
			info.quick.openSettings()
		end
	end
	-- NB: selection no longer opens the flyout — that's driven explicitly so a
	-- DRAG doesn't pop it open on release (only a plain click does; see endDrag).
end

-- Overlap grab (Florian): elements can be stacked (e.g. Group over Raid). Clicking
-- cycles selection through everything under the cursor (stable by registration
-- order); the selected one is raised so a following drag isn't blocked by a peer.
function EditMode:_nextUnderCursor(frame)
	local ui = UIParent:GetEffectiveScale()
	local mx, my = GetCursorPosition()
	mx, my = mx / ui, my / ui
	local hits, n = nil, 0
	for f, info in pairs(self.items) do
		if f:IsShown() then
			local l, b, w, h = rectOf(boundsFor(f, info))
			if l and mx >= l and mx <= l + w and my >= b and my <= b + h then
				hits = hits or {}; n = n + 1; hits[n] = f
			end
		end
	end
	if n < 2 then return nil end
	table.sort(hits, function(a, b) return self.items[a].regIndex < self.items[b].regIndex end)
	local ci = 1
	for i = 1, n do if hits[i] == frame then ci = i break end end
	return hits[(ci % n) + 1]
end

function EditMode:_raise(frame)
	local info = frame and self.items[frame]
	if not info then return end
	self._raiseLvl = (self._raiseLvl or 400) + 1
	info.overlay:SetFrameLevel(self._raiseLvl)
	-- Let the element lift its own render order too (e.g. an overlapping raid
	-- preview brings its whole frame subtree to the front, not just the overlay).
	if info.quick and info.quick.onRaise then info.quick.onRaise(frame) end
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

-- After a nudge, show the flight line(s) if the element now sits exactly on one
-- AND the live neighbour spacing to whatever it shares a row/column with — so
-- keyboard aligning gets the same feedback as mouse dragging (Florian's request
-- 2026-07-13, spacing 2026-07-15). Auto-hides shortly after the last nudge.
local nudgeTimer
local function showNudgeGuides(frame)
	local bl, bb, bw, bh = rectOf(boundsFor(frame, EditMode.items[frame]))
	if not bl then return end
	-- moveSet is current (nudgeSelected called buildGroup just before). Scan
	-- EVERY moving member's edges so a coupled child's edge shows a guide too,
	-- and build the group's union box for the neighbour spacing measures.
	collectObstacles(frame)
	local eps = 0.75
	local gvx, ghy
	local gl, gb, gr, gt
	for f in pairs(moveSet) do
		local ml, mb, mw, mh = rectOf(boundsFor(f, EditMode.items[f]))
		if ml then
			if not gl then gl, gb, gr, gt = ml, mb, ml + mw, mb + mh
			else
				if ml < gl then gl = ml end
				if mb < gb then gb = mb end
				if ml + mw > gr then gr = ml + mw end
				if mb + mh > gt then gt = mb + mh end
			end
			if not gvx then
				for i = 1, vN do
					local Lp = vLine[i]
					if abs(ml - Lp) < eps or abs(ml + mw / 2 - Lp) < eps or abs(ml + mw - Lp) < eps then
						gvx = Lp; break
					end
				end
			end
			if not ghy then
				for i = 1, hN do
					local Lp = hLine[i]
					if abs(mb - Lp) < eps or abs(mb + mh / 2 - Lp) < eps or abs(mb + mh - Lp) < eps then
						ghy = Lp; break
					end
				end
			end
		end
	end
	local any = renderFeedback(gvx, ghy, gl or bl, gb or bb, (gr and gr - gl) or bw, (gt and gt - gb) or bh)
	if nudgeTimer then nudgeTimer:Cancel(); nudgeTimer = nil end
	if any then
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
	EditMode:_positionPanel() -- keep the flyout beside the element as it nudges
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
		-- A flyout value field has focus -> pass EVERY key through to it (typing an
		-- exact number), never nudge or close the session while editing.
		if EditMode._fieldFocused then
			self:SetPropagateKeyboardInput(true)
			return
		end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			-- Esc staggers: link mode -> open Shell -> the session itself.
			if EditMode.linkSource then EditMode:CancelLink()
			elseif ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown() then
				ns.Shell:Hide()   -- Shell OnHide clears the lit frame (back to clean)
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
--  Selection settings flyout (Phase 3): click-selecting an element opens a
--  Lumen-skinned panel beside it (side chosen by the available room) with that
--  element's QUICK settings — size etc. live on the real element, an X to close,
--  an optional "Reset to default" and "Open settings" (large modules point back
--  to the Shell tab). Built lazily (this file loads before Tokens/W). Descriptor-
--  based (info.quick) so future modules plug in without touching this file.
-- ---------------------------------------------------------------------------
local panel
local PANEL_INNER  = 220   -- content width in panel-local units
local PANEL_HEADER = 40    -- title + subtitle block below the top padding

local function ensurePanel()
	if panel then return end
	local UI, W, T = ns.UI, ns.W, ns.T
	local M, S = UI.WIDGET, UI.S
	panel = CreateFrame("Frame", "LumenEditModePanel", UIParent)
	panel:SetFrameStrata("TOOLTIP")       -- above the FULLSCREEN_DIALOG overlays
	panel:SetToplevel(true)
	panel:EnableMouse(true)               -- eat clicks so they don't fall through
	panel:SetClampedToScreen(true)
	panel:SetWidth(PANEL_INNER + M.sectionPad * 2)
	UI.RoundFill(panel, UI.P.panel, "BACKGROUND", nil, UI.RADIUS.lg)
	UI.RoundBorder(panel, UI.line.mid, "BORDER", nil, UI.RADIUS.lg)

	panel._title = UI.FS(panel, "groupTitle", UI.P.goldBrand)
	panel._title:SetPoint("TOPLEFT", panel, "TOPLEFT", M.sectionPad, -M.sectionPad)

	panel._sub = UI.FS(panel, "caption", UI.P.textSecondary)
	panel._sub:SetText(T("Quick settings"))
	panel._sub:SetPoint("TOPLEFT", panel._title, "BOTTOMLEFT", 0, -2)

	panel._x = W.IconButton(panel, { icon = "icon-x", size = S.closeGlyph,
		color = UI.P.textSecondary, hoverColor = UI.P.goldBrand,
		onClick = function() EditMode:Select(nil); EditMode:_updatePanel() end })
	panel._x:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -M.sectionPad, -M.sectionPad)

	-- Draggable like the toolbar: the header/padding is the grab area (the
	-- sliders/buttons are mouse children, so a drag starting on them goes to
	-- them, not the panel). Once the user moves it, auto-placement backs off
	-- until the selection changes.
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", function(self) self:StartMoving(); self._userMoved = true end)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

	panel._contents = {}   -- frame -> its cached content sub-frame
	panel:Hide()
end

-- Build (once, cached) the control column for one element from its descriptor.
local function buildContent(frame, info)
	local existing = panel._contents[frame]
	if existing then return existing end
	local UI, W, T = ns.UI, ns.W, ns.T
	local M, S = UI.WIDGET, UI.S
	local q = info.quick
	-- Parented straight to the panel (a 0-height intermediate frame gives its
	-- children NO rect -> they render invisibly; memory lumen-beta-roadmap-plan).
	local c = CreateFrame("Frame", nil, panel)
	c:SetPoint("TOPLEFT", panel, "TOPLEFT", M.sectionPad, -(M.sectionPad + PANEL_HEADER))
	c:SetWidth(PANEL_INNER)
	c._syncers = {}
	local y = 0
	if q.fields then
		for i = 1, #q.fields do
			local fd = q.fields[i]
			if fd.kind == "slider" then
				local sl = W.Slider(c, { label = fd.label, min = fd.min, max = fd.max,
					step = fd.step or 1, unit = fd.unit or "", width = PANEL_INNER, compact = true,
					get = fd.get, set = fd.set })
				sl:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
				y = y - (M.sliderCompactH + S.s3)
				c._syncers[#c._syncers + 1] = function() sl:SetValueExternal(fd.get()) end
			end
		end
	end
	local function addBtn(text, variant, fn)
		local b = W.Button(c, { text = text, variant = variant, width = PANEL_INNER, onClick = fn })
		b:SetPoint("TOPLEFT", c, "TOPLEFT", 0, y)
		y = y - (M.buttonH + S.s3)
	end
	if q.openSettings then
		-- Non-destructive (Florian 2026-07-16): keep the session OPEN and let the
		-- Shell come up alongside — the element's settings + its lit frame coexist
		-- with Edit Mode. The flyout closes (Shell has the full settings); ESC
		-- closes the Shell first, then the session.
		addBtn(T("Open settings"), "secondary", function()
			EditMode:_hidePanel()
			q.openSettings()
		end)
	end
	if q.reset then
		addBtn(T("Reset to default"), "neutral", function()
			q.reset()
			for i = 1, #c._syncers do c._syncers[i]() end
			EditMode:_anchorOverlays()
			EditMode:_positionPanel()
		end)
	end
	c._height = (-y) - S.s3   -- drop the trailing gap after the last control
	if c._height < M.buttonH then c._height = M.buttonH end
	c:SetHeight(c._height)
	c:Hide()
	panel._contents[frame] = c
	return c
end

function EditMode:_hidePanel()
	if panel and panel:IsShown() then panel:Hide() end
end

-- Show/refresh the flyout for the current selection (or hide it).
function EditMode:_updatePanel()
	local frame = self.selected
	local info = frame and self.items[frame]
	if not (self.active and info and info.quick) then
		if panel then panel._forFrame = nil; panel:Hide() end
		return
	end
	-- Coexisting with the Shell (it holds the full settings): suppress the flyout
	-- so it doesn't sit on top of the open Shell (Florian 2026-07-16).
	if ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown() then
		if panel then panel._forFrame = nil; panel:Hide() end
		return
	end
	ensurePanel()
	if ns.Shell and ns.Shell._frame then panel:SetScale(ns.Shell._frame:GetScale()) end
	if panel._current and panel._current ~= panel._contents[frame] then panel._current:Hide() end
	local c = buildContent(frame, info)
	c:Show()
	panel._current = c
	if panel._forFrame ~= frame then panel._userMoved = false end -- new element -> auto-place again
	panel._forFrame = frame
	panel._title:SetText(info.label or "")
	for i = 1, #c._syncers do c._syncers[i]() end   -- fresh values (size may have changed)
	panel:SetHeight(ns.UI.WIDGET.sectionPad * 2 + PANEL_HEADER + c._height)
	panel:Show()
	self:_positionPanel()
end

-- Place the flyout beside the selected element: right if it fits, else left,
-- else clamped below/centered. All math in UIParent units; convert to the
-- panel's own (scaled) space for the final SetPoint.
function EditMode:_positionPanel()
	if not panel or not panel._forFrame or not panel:IsShown() then return end
	if panel._userMoved then return end -- respect a manual drag until selection changes
	local info = self.items[panel._forFrame]
	local bl, bb, bw, bh = rectOf(boundsFor(panel._forFrame, info))
	if not bl then return end
	local r = panel:GetScale()
	local ew, eh = panel:GetWidth() * r, panel:GetHeight() * r
	local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
	local gap = 16
	local elR, elT = bl + bw, bb + bh
	local px
	if elR + gap + ew <= sw then px = elR + gap
	elseif bl - gap - ew >= 0 then px = bl - gap - ew
	else px = math.min(math.max(4, bl + bw / 2 - ew / 2), sw - ew - 4) end
	local pyTop = elT
	if pyTop > sh - 4 then pyTop = sh - 4 end
	if pyTop - eh < 4 then pyTop = eh + 4 end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", px / r, pyTop / r)
end

-- ---------------------------------------------------------------------------
--  Session chrome: a subtle world dim (so it's obvious you're in Edit Mode,
--  Ellesmere/Blizzard style — behind all UI so the frames stay bright) + a
--  persistent screen-center crosshair as a fixed alignment reference.
-- ---------------------------------------------------------------------------
local editChrome
local function ensureEditChrome()
	if editChrome then return end
	local dim = CreateFrame("Frame", nil, UIParent)
	dim:SetFrameStrata("BACKGROUND")   -- over the world, under all UI/frames
	dim:SetAllPoints(UIParent)
	dim:EnableMouse(false)
	local dt = dim:CreateTexture(nil, "BACKGROUND")
	dt:SetAllPoints()
	dt:SetColorTexture(0, 0, 0, 0.28)
	dim:Hide()

	local host = CreateFrame("Frame", nil, UIParent)
	host:SetFrameStrata("MEDIUM")       -- reference lines sit behind the HIGH frames
	host:SetAllPoints(UIParent)
	host:EnableMouse(false)
	local function mkLine()
		local t = host:CreateTexture(nil, "OVERLAY")
		if ns.UI then ns.UI.SetColor(t, ns.UI.P.goldBrand) else t:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1) end
		t:SetAlpha(0.30)
		return t
	end
	local cv, chz = mkLine(), mkLine()
	local function place()
		local w, h = host:GetWidth(), host:GetHeight()
		if not w or w == 0 then return end
		cv:ClearAllPoints()
		cv:SetPoint("TOP", host, "TOPLEFT", w / 2, 0)
		cv:SetPoint("BOTTOM", host, "BOTTOMLEFT", w / 2, 0)
		PixelUtil.SetWidth(cv, 1)
		chz:ClearAllPoints()
		chz:SetPoint("LEFT", host, "BOTTOMLEFT", 0, h / 2)
		chz:SetPoint("RIGHT", host, "BOTTOMRIGHT", 0, h / 2)
		PixelUtil.SetHeight(chz, 1)
	end
	host:HookScript("OnShow", place)
	host:HookScript("OnSizeChanged", place)
	host:Hide()
	editChrome = { dim = dim, host = host, place = place }
end

local function showEditChrome(on)
	if on then
		ensureEditChrome()
		editChrome.dim:Show()
		editChrome.host:Show()
		editChrome.place()
	elseif editChrome then
		editChrome.dim:Hide()
		editChrome.host:Hide()
	end
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
-- quick (optional): a settings descriptor { fields = { {kind="slider", label,
--   min, max, step?, unit?, get, set}, ... }, reset = fn, openSettings = fn }.
--   Click-selecting the element in a session opens a Lumen flyout beside it with
--   these controls (Phase 3). Small widgets carry their full settings; large
--   modules just carry openSettings (a jump back to the Shell tab).
function EditMode:Register(frame, label, save, boundsFn, key, quick)
	if self.items[frame] then return end
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	self._regCount = (self._regCount or 0) + 1
	local info = { label = label, save = save, boundsFn = boundsFn, key = key, quick = quick,
		regIndex = self._regCount, overlay = makeOverlay(frame, label) }
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
	-- Coexistence: while a session runs the Shell sits ABOVE the frame overlays
	-- (which are FULLSCREEN_DIALOG). It's toplevel, so raising its strata to match
	-- + toplevel keeps the whole Shell on top of the previews/overlays; the Done
	-- toolbar (TOOLTIP) stays above it. Restored on CloseSession.
	if ns.Shell and ns.Shell._frame then
		ns.Shell._frame:SetFrameStrata("FULLSCREEN_DIALOG")
	end
	ensureToolbar()
	-- Constant physical size like the Shell (same scale source).
	if ns.Shell and ns.Shell._frame then toolbar:SetScale(ns.Shell._frame:GetScale()) end
	toolbar:Show()
	showEditChrome(true)   -- world dim + screen-center crosshair
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
	self:_updatePanel() -- selection cleared -> hides the flyout
	if toolbar then toolbar:Hide() end
	showEditChrome(false)
	if kb then kb:EnableKeyboard(false); kb:Hide() end
	hideGuides()
	evt:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:_refresh()
	-- Positions are already saved per drag release / nudge — nothing to flush.
	-- Only reopen if the Shell isn't already up (it may coexist with the session
	-- now — "Open settings" leaves it open; then don't flip it hidden->shown).
	local shellUp = ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown()
	-- Restore the normal config-window strata (raised during the session so it sat
	-- above the frame overlays).
	if ns.Shell and ns.Shell._frame then ns.Shell._frame:SetFrameStrata("DIALOG") end
	if reopenShell and self._reopenShell and ns.Shell and not InCombatLockdown() and not shellUp then
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
