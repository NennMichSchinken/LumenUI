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

-- Frame rect in UIParent coordinate space (handles a differing effective
-- scale, e.g. if a registered frame ever runs its own SetScale).
local function rectOf(f)
	local l, b = f:GetLeft(), f:GetBottom()
	if not l then return nil end
	local eff = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return l * eff, b * eff, f:GetWidth() * eff, f:GetHeight() * eff
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
--  Drag loop (own SetPoint loop — StartMoving cannot be constrained).
-- ---------------------------------------------------------------------------
local function beginDrag(frame)
	local ui = UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local l, b, w, h = rectOf(frame)
	if not l then return false end
	drag.frame = frame
	drag.offX, drag.offY = cx / ui - l, cy / ui - b
	drag.grabX, drag.grabY = cx / ui, cy / ui
	drag.w, drag.h = w, h
	drag.lastX, drag.lastY = l, b
	drag.moved = false
	drag.screenW, drag.screenH = UIParent:GetWidth(), UIParent:GetHeight()
	drag.tol = TOL_PX / ui

	-- Collect obstacles + alignment lines ONCE per drag (the others don't
	-- move while this one is dragged). Screen center axes are always targets.
	obsN, vN, hN = 0, 0, 0
	vN = vN + 1; vLine[vN] = drag.screenW / 2; vSrc[vN] = 0
	hN = hN + 1; hLine[hN] = drag.screenH / 2; hSrc[hN] = 0
	for f in pairs(EditMode.items) do
		if f ~= frame and f:IsShown() then
			local ol, ob, ow, oh = rectOf(f)
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

	-- Keep the desired position on screen (physics stays honest at the edges).
	local maxX, maxY = drag.screenW - drag.w, drag.screenH - drag.h
	if x < 0 then x = 0 elseif x > maxX then x = maxX end
	if y < 0 then y = 0 elseif y > maxY then y = maxY end

	local gvx, ghy   -- active guide line positions (nil = none)
	local gvsrc, ghsrc = 0, 0
	if not IsControlKeyDown() then
		-- WALLS — resolved PER AXIS so the frame slides along edges: first X
		-- against the previous Y, then Y against the resolved X. The clamp
		-- falls away as soon as the desired position is free (the desired
		-- position always hangs on the cursor — that's why nothing sticks).
		local lx, ly = drag.lastX, drag.lastY
		for i = 1, obsN do
			if hitsObstacle(x, ly, drag.w, drag.h, i) then
				if lx + drag.w <= obsL[i] + 0.01 then x = obsL[i] - drag.w
				elseif lx >= obsR[i] - 0.01 then x = obsR[i]
				else x = lx end
			end
		end
		for i = 1, obsN do
			if hitsObstacle(x, y, drag.w, drag.h, i) then
				if ly + drag.h <= obsB[i] + 0.01 then y = obsB[i] - drag.h
				elseif ly >= obsT[i] - 0.01 then y = obsT[i]
				else y = ly end
			end
		end

		-- GROOVES — hold when an edge or the center of the dragged frame is
		-- within ±tol of a line. Walls have priority: a held position that
		-- would collide is discarded.
		local tol = drag.tol
		local bestD, bestX = tol + 0.001, nil
		for i = 1, vN do
			local L = vLine[i]
			local d = abs(x - L)
			if d < bestD then bestD = d; bestX = L; gvx = L; gvsrc = vSrc[i] end
			d = abs(x + drag.w / 2 - L)
			if d < bestD then bestD = d; bestX = L - drag.w / 2; gvx = L; gvsrc = vSrc[i] end
			d = abs(x + drag.w - L)
			if d < bestD then bestD = d; bestX = L - drag.w; gvx = L; gvsrc = vSrc[i] end
		end
		if bestX then
			if not hitsAny(bestX, y, drag.w, drag.h) then x = bestX
			else gvx = nil; gvsrc = 0 end
		end
		local bestY
		bestD = tol + 0.001
		for i = 1, hN do
			local L = hLine[i]
			local d = abs(y - L)
			if d < bestD then bestD = d; bestY = L; ghy = L; ghsrc = hSrc[i] end
			d = abs(y + drag.h / 2 - L)
			if d < bestD then bestD = d; bestY = L - drag.h / 2; ghy = L; ghsrc = hSrc[i] end
			d = abs(y + drag.h - L)
			if d < bestD then bestD = d; bestY = L - drag.h; ghy = L; ghsrc = hSrc[i] end
		end
		if bestY then
			if not hitsAny(x, bestY, drag.w, drag.h) then y = bestY
			else ghy = nil; ghsrc = 0 end
		end
	end

	if x ~= drag.lastX or y ~= drag.lastY then
		drag.lastX, drag.lastY = x, y
		-- SetPoint offsets live in the FRAME's own scale space — convert back
		-- from UIParent units (identity while all movers run scale 1).
		local inv = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x * inv, y * inv)
	end
	updateGuides(gvx, gvsrc, ghy, ghsrc, x, y)
end

local function endDrag(frame)
	if drag.frame ~= frame then return end
	hideGuides()
	local info = EditMode.items[frame]
	if info and info.save and drag.moved then
		local p, _, _, px, py = frame:GetPoint()
		info.save(p, floor(px + 0.5), floor(py + 0.5))
	end
	drag.frame = nil
	EditMode:Select(frame) -- click AND drag both select (nudge target)
end

-- ---------------------------------------------------------------------------
--  Overlay per element
-- ---------------------------------------------------------------------------
local function makeOverlay(frame, label)
	local o = CreateFrame("Frame", nil, frame)
	o:SetAllPoints()
	o:SetFrameStrata("HIGH")
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

	o:SetScript("OnMouseDown", function(_, btn)
		if btn ~= "LeftButton" then return end
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
	if self.selected and self.items[self.selected] then
		self.items[self.selected].overlay:SetSelected(false)
	end
	self.selected = frame
	if frame and self.items[frame] then
		self.items[frame].overlay:SetSelected(true)
	end
end

local function nudgeSelected(dx, dy)
	local frame = EditMode.selected
	if not frame or not frame:IsShown() then return end
	local l, b = rectOf(frame)
	if not l then return end
	local inv = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (l + dx) * inv, (b + dy) * inv)
	local info = EditMode.items[frame]
	if info and info.save then
		local p, _, _, px, py = frame:GetPoint()
		info.save(p, floor(px + 0.5), floor(py + 0.5))
	end
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
			EditMode:CloseSession(true)
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
	function toolbar:_fit()
		local w = pad + mark:GetStringWidth() + gap + done:GetWidth() + gap + hint:GetStringWidth() + pad
		self:SetSize(w, M.buttonH + 24)
		mark:ClearAllPoints()
		mark:SetPoint("LEFT", self, "LEFT", pad, 0)
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
function EditMode:_refresh()
	self.active = self.session or self.blizzard
	for _, info in pairs(self.items) do
		info.overlay:SetShown(self.active)
	end
	-- Notify listeners (e.g. QoL trackers force-show while unlocked so
	-- instance-only elements can be placed anywhere).
	if self.listeners then
		for i = 1, #self.listeners do pcall(self.listeners[i], self.active) end
	end
end

function EditMode:AddListener(fn)
	self.listeners = self.listeners or {}
	self.listeners[#self.listeners + 1] = fn
end

function EditMode:Register(frame, label, save)
	if self.items[frame] then return end
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	self.items[frame] = { label = label, save = save, overlay = makeOverlay(frame, label) }
	if self.active then self.items[frame].overlay:Show() end
end

-- ---------------------------------------------------------------------------
--  Session (the Lumen path: Shell hides, toolbar shows, ESC/combat ends)
-- ---------------------------------------------------------------------------
local evt = CreateFrame("Frame")

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
end

function EditMode:CloseSession(reopenShell)
	if not self.session then return end
	self.session = false
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
