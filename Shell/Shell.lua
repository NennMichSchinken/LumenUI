local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Suite-Shell (Phase 1: Optisches Gerüst)
--  Eigene gerunte Config-Optik nach dem Lumen Design System (siehe Shell/Tokens).
--  Phase 1 = Chrome (Header/Nav/Tabs/Footer/Rune) + Dummy-Inhalt zum Look-Check.
--  Läuft PARALLEL zur bestehenden AceConfig (die bleibt auf /lumen). Aufruf der
--  Shell während der Entwicklung: /lumen shell.
--  Widget-Toolkit + echte Screens folgen in Phase 2/3.
-- ===========================================================================

local UI = ns.UI
local C, L, S, PANEL = UI.C, UI.line, UI.S, UI.PANEL

local Shell = {}
ns.Shell = Shell

-- ---------------------------------------------------------------------------
--  Kleine Bau-Helfer — die Primitive liegen jetzt zentral in Tokens (ns.UI),
--  damit Shell-Chrome UND Widget-Toolkit dieselben nutzen (DRY).
-- ---------------------------------------------------------------------------
local setColor, fill, border, FS = UI.SetColor, UI.Fill, UI.Border, UI.FS

-- ---------------------------------------------------------------------------
--  Rune-Ornament (concentric circles + rotated square + radiating ticks),
--  vektoriell über CreateLine. Eckenmarke, low-opacity.
-- ---------------------------------------------------------------------------
local function runeLine(holder, x1, y1, x2, y2, a)
	local ln = holder:CreateLine(nil, "ARTWORK")
	ln:SetThickness(1)
	ln:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, a)
	ln:SetStartPoint("CENTER", holder, x1, y1)
	ln:SetEndPoint("CENTER", holder, x2, y2)
	return ln
end

local function runeCircle(holder, radius, segments, a)
	local prevX, prevY
	for i = 0, segments do
		local ang = (i / segments) * math.pi * 2
		local x, y = math.cos(ang) * radius, math.sin(ang) * radius
		if prevX then runeLine(holder, prevX, prevY, x, y, a) end
		prevX, prevY = x, y
	end
end

local function drawRune(parent, point, ox, oy, scaleF, alpha)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(2, 2)
	holder:SetPoint("CENTER", parent, point, ox, oy)
	local s = scaleF or 1
	local a = alpha or 0.40
	runeCircle(holder, 60 * s, 40, a)
	runeCircle(holder, 43 * s, 36, a)
	runeCircle(holder, 20 * s, 28, a)
	-- rotiertes Quadrat (Diamant) — Eckpunkte bei ±30
	local q = 30 * s
	runeLine(holder, 0, q, q, 0, a)
	runeLine(holder, q, 0, 0, -q, a)
	runeLine(holder, 0, -q, -q, 0, a)
	runeLine(holder, -q, 0, 0, q, a)
	-- 8 radiale Ticks (von r=60 nach r=70)
	for i = 0, 7 do
		local ang = (i / 8) * math.pi * 2
		local cx, cy = math.cos(ang), math.sin(ang)
		runeLine(holder, cx * 60 * s, cy * 60 * s, cx * 70 * s, cy * 70 * s, a)
	end
	return holder
end

-- ---------------------------------------------------------------------------
--  Nav-Item (linke Rail) — aktiv: 3px Gold-Bar links + Gold-Wash + Gold-Label.
-- ---------------------------------------------------------------------------
local function makeNavItem(parent, label)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(44)
	b:SetPoint("LEFT", parent, "LEFT", 0, 0)
	b:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	-- Gold-Wash, der nach rechts ausläuft (Gold links -> transparent rechts).
	local wash = b:CreateTexture(nil, "BACKGROUND")
	wash:SetAllPoints(b)
	wash:SetColorTexture(1, 1, 1, 1)
	wash:SetGradient("HORIZONTAL",
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.14),
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.00))
	wash:Hide()

	-- Gold-Balken links, volle Höhe des Menüpunkts.
	local barL = b:CreateTexture(nil, "ARTWORK")
	barL:SetWidth(3)
	barL:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	barL:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
	setColor(barL, C.gold500)
	barL:Hide()

	local txt = FS(b, "nav", C.textBody)
	txt:SetPoint("LEFT", b, "LEFT", S.panelGutter, 0)
	txt:SetText(label)

	b._wash, b._bar, b._txt = wash, barL, txt
	b:SetScript("OnEnter", function(self)
		if not self._active then self._txt:SetTextColor(C.gold200.r, C.gold200.g, C.gold200.b) end
	end)
	b:SetScript("OnLeave", function(self)
		if not self._active then self._txt:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b) end
	end)
	function b:SetActive(on)
		self._active = on
		self._wash:SetShown(on); self._bar:SetShown(on)
		local col = on and C.gold250 or C.textBody
		self._txt:SetTextColor(col.r, col.g, col.b)
	end
	return b
end

-- ---------------------------------------------------------------------------
--  Tab (Pill) — aktiv: Gold-Border + Gold-Label + feiner Wash.
-- ---------------------------------------------------------------------------
local function makeTab(parent, label)
	local b = CreateFrame("Button", nil, parent)
	local txt = FS(b, "tab", C.textBody)
	txt:SetText(label)
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)
	b:SetSize(math.floor(txt:GetStringWidth() + 44 + 0.5), 36)

	-- gefüllte Card-Fläche (inaktiv) — wie Prototyp (surface-card).
	local base = b:CreateTexture(nil, "BACKGROUND")
	base:SetAllPoints(b); setColor(base, C.ink600)
	-- aktiver Gold-Gradient (oben heller, fadet nach unten) -> "Fade".
	local grad = b:CreateTexture(nil, "ARTWORK")
	grad:SetAllPoints(b); grad:SetColorTexture(1, 1, 1, 1)
	grad:SetGradient("VERTICAL",
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.00),
		CreateColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.16))
	grad:Hide()
	-- Borders auf OVERLAY (ÜBER dem Gradient) -> aktiver Tab behält rundum den Rahmen.
	local edges = border(b, L.soft, 1, "OVERLAY")
	b._txt, b._grad, b._edges = txt, grad, edges

	b:SetScript("OnEnter", function(self)
		if not self._active then
			self._txt:SetTextColor(C.textHeading.r, C.textHeading.g, C.textHeading.b)
			for _, e in ipairs(self._edges) do setColor(e, L.mid) end
		end
	end)
	b:SetScript("OnLeave", function(self)
		if not self._active then
			self._txt:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b)
			for _, e in ipairs(self._edges) do setColor(e, L.soft) end
		end
	end)
	function b:SetActive(on)
		self._active = on
		self._grad:SetShown(on)
		local ec = on and L.strong or L.soft
		for _, e in ipairs(self._edges) do setColor(e, ec) end
		local tc = on and C.gold250 or C.textBody
		self._txt:SetTextColor(tc.r, tc.g, tc.b)
		-- aktiv = SemiBold (fontWeight 600), inaktiv = Medium.
		self._txt:SetFont(on and UI.FONT.hankenSemi or UI.FONT.hankenMed, 18, "")
	end
	return b
end

-- ---------------------------------------------------------------------------
--  Close-X (oben rechts) — zwei Gold-Linien, Hover hellt auf. Passt zur
--  Line-SVG-Iconografie des Design-Systems (✕-Unicode ist im Font nicht sicher).
-- ---------------------------------------------------------------------------
local function makeCloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(34, 34)
	local radius = 15

	-- Runde Hover-Fläche (kreisförmig via Alpha-Maske), erst beim Hovern sichtbar.
	local hoverFill = b:CreateTexture(nil, "BACKGROUND")
	hoverFill:SetSize(radius * 2, radius * 2); hoverFill:SetPoint("CENTER", b, "CENTER", 0, 0)
	hoverFill:SetTexture([[Interface\Buttons\WHITE8X8]])
	hoverFill:SetVertexColor(C.gold500.r, C.gold500.g, C.gold500.b, 0.12)
	local mask = b:CreateMaskTexture()
	mask:SetAllPoints(hoverFill)
	mask:SetTexture([[Interface\CharacterFrame\TempPortraitAlphaMask]], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	hoverFill:AddMaskTexture(mask)
	hoverFill:Hide()

	-- Dünner Gold-Ring (wie die Eck-Runen) — immer sichtbar, macht es zur Rune.
	local ring, seg, prevX, prevY = {}, 32, nil, nil
	for i = 0, seg do
		local ang = (i / seg) * math.pi * 2
		local x, y = math.cos(ang) * radius, math.sin(ang) * radius
		if prevX then
			local ln = b:CreateLine(nil, "ARTWORK")
			ln:SetThickness(1)
			ln:SetColorTexture(C.gold500.r, C.gold500.g, C.gold500.b, 0.50)
			ln:SetStartPoint("CENTER", b, prevX, prevY)
			ln:SetEndPoint("CENTER", b, x, y)
			ring[#ring + 1] = ln
		end
		prevX, prevY = x, y
	end

	-- X im Zentrum.
	local g7 = 7
	local function arm(x1, y1, x2, y2)
		local ln = b:CreateLine(nil, "OVERLAY")
		ln:SetThickness(2)
		ln:SetColorTexture(C.gold300.r, C.gold300.g, C.gold300.b, 1)
		ln:SetStartPoint("CENTER", b, x1, y1)
		ln:SetEndPoint("CENTER", b, x2, y2)
		return ln
	end
	local a1 = arm(-g7, g7, g7, -g7)
	local a2 = arm(-g7, -g7, g7, g7)

	local function setRing(c, a)
		for _, ln in ipairs(ring) do ln:SetColorTexture(c.r, c.g, c.b, a) end
	end
	local function setArms(c)
		a1:SetColorTexture(c.r, c.g, c.b, 1); a2:SetColorTexture(c.r, c.g, c.b, 1)
	end
	b:SetScript("OnEnter", function() hoverFill:Show(); setRing(C.gold200, 0.9); setArms(C.gold100) end)
	b:SetScript("OnLeave", function() hoverFill:Hide(); setRing(C.gold500, 0.5); setArms(C.gold300) end)
	b:SetScript("OnClick", onClick)
	return b
end

-- ===========================================================================
--  Aufbau des Panels (einmalig)
-- ===========================================================================
local SECTIONS = {
	{ "Global",      { "Base", "Profile" } },
	{ "Click-Cast",  { "Bindings", "Hovercast" } },
	{ "Raidframes",  { "Base", "Raid", "Group", "Auras", "Tracking" } },
	{ "Unitframes",  { "Base" } },
	{ "Nameplates",  { "Base" } },
	{ "QoL",         { "Base" } },
}

function Shell:Build()
	if self._frame then return self._frame end

	-- Outer Panel ------------------------------------------------------------
	local f = CreateFrame("Frame", "LumenShellFrame", UIParent)
	f:SetSize(PANEL.w, PANEL.h)
	f:SetScale(PANEL.scale)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "LumenShellFrame") -- ESC schließt
	self._frame = f

	fill(f, C.ink850, "BACKGROUND")
	-- Radial-Glow-Approx: vertikaler Gradient (oben heller) als Overlay.
	local glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	glow:SetAllPoints(f)
	glow:SetColorTexture(1, 1, 1, 1)
	glow:SetGradient("VERTICAL",
		CreateColor(C.ink900.r, C.ink900.g, C.ink900.b, 1),
		CreateColor(C.ink800.r, C.ink800.g, C.ink800.b, 1))
	glow:SetAlpha(0.6)
	border(f, L.mid, 1)

	-- Rune-Ecken (low-opacity Ornament)
	drawRune(f, "TOPLEFT",      80,  -80, 1, 0.40)
	drawRune(f, "TOPRIGHT",    -80,  -80, 1, 0.40)
	drawRune(f, "BOTTOMRIGHT", -80,   80, 1, 0.40)
	drawRune(f, "BOTTOMLEFT",   80,   80, 1, 0.40)

	-- Header -----------------------------------------------------------------
	local header = CreateFrame("Frame", nil, f)
	header:SetHeight(PANEL.headerH)
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
	local hsep = header:CreateTexture(nil, "ARTWORK")
	hsep:SetHeight(1); hsep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	hsep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0); setColor(hsep, L.divider)

	local word = FS(header, "wordmark", C.gold300)
	word:SetText(UI.Track("LUMEN", "  ")) -- tracking-Emulation
	word:SetPoint("CENTER", header, "CENTER", 0, 8)
	local tag = FS(header, "tagline", C.textMuted)
	tag:SetText(UI.Track("a focused ui suite", " "))
	tag:SetPoint("TOP", word, "BOTTOM", 0, -8)

	-- Footer -----------------------------------------------------------------
	local footer = CreateFrame("Frame", nil, f)
	footer:SetHeight(PANEL.footerH)
	footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
	footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
	local fsep = footer:CreateTexture(nil, "ARTWORK")
	fsep:SetHeight(1); fsep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
	fsep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0); setColor(fsep, L.divider)

	-- Close-X oben rechts in der Ecke.
	local closeBtn = makeCloseButton(f, function() Shell:Hide() end)
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
	closeBtn:SetFrameLevel(f:GetFrameLevel() + 50)

	-- Body: Nav-Rail + Main --------------------------------------------------
	local body = CreateFrame("Frame", nil, f)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	body:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)

	local nav = CreateFrame("Frame", nil, body)
	nav:SetWidth(S.navWidth)
	nav:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
	nav:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)

	local main = CreateFrame("Frame", nil, body)
	main:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
	main:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

	-- Vertikaler Nav-Divider: auf MAIN (zeichnet über nav + dessen Buttons), linke Kante.
	local nsep = main:CreateTexture(nil, "OVERLAY")
	nsep:SetWidth(1); nsep:SetPoint("TOPLEFT", main, "TOPLEFT", 0, 0)
	nsep:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, 0); setColor(nsep, L.divider)

	-- Tab-Strip
	local tabStrip = CreateFrame("Frame", nil, main)
	tabStrip:SetHeight(36)
	tabStrip:SetPoint("TOPLEFT", main, "TOPLEFT", S.panelGutter, -22)
	tabStrip:SetPoint("TOPRIGHT", main, "TOPRIGHT", -S.panelGutter, -22)

	-- Content-Bereich (Dummy in Phase 1)
	local content = CreateFrame("Frame", nil, main)
	content:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -26)
	content:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -S.panelGutter, S.panelGutter)
	self._content = content

	-- Nav-Buttons
	self._navButtons = {}
	local prev
	for i, sec in ipairs(SECTIONS) do
		local nb = makeNavItem(nav, sec[1])
		if prev then nb:SetPoint("TOP", prev, "BOTTOM", 0, -2)
		else nb:SetPoint("TOP", nav, "TOP", 0, -S.s8) end
		nb._index = i
		nb:SetScript("OnClick", function() Shell:SelectSection(i) end)
		self._navButtons[i] = nb
		prev = nb
	end

	self._tabStrip = tabStrip
	self._tabButtons = {}

	-- Erststand
	Shell:SelectSection(3) -- Raidframes (wie Prototyp-Default)
	return f
end

-- Tab-Strip für die aktuelle Sektion neu bauen.
function Shell:RebuildTabs(sectionIndex)
	for _, t in ipairs(self._tabButtons) do t:Hide(); t:SetParent(nil) end
	wipe(self._tabButtons)
	local tabs = SECTIONS[sectionIndex][2]
	local prev
	for i, label in ipairs(tabs) do
		local tb = makeTab(self._tabStrip, label)
		if prev then tb:SetPoint("LEFT", prev, "RIGHT", S.s3, 0)
		else tb:SetPoint("LEFT", self._tabStrip, "LEFT", 0, 0) end
		tb._index = i
		tb:SetScript("OnClick", function() Shell:SelectTab(i) end)
		self._tabButtons[i] = tb
		prev = tb
	end
	Shell:SelectTab(1)
end

function Shell:SelectSection(index)
	self._section = index
	for i, nb in ipairs(self._navButtons) do nb:SetActive(i == index) end
	self:RebuildTabs(index)
end

function Shell:SelectTab(index)
	self._tab = index
	for i, tb in ipairs(self._tabButtons) do tb:SetActive(i == index) end
	self:RenderDummy()
end

-- ---------------------------------------------------------------------------
--  Widget-Galerie (Phase 2): zeigt das komplette Toolkit (Divider, Slider,
--  Select, Checkbox, GroupPanel, Buttons, Card) live bedienbar — damit Florian
--  Look UND Feel in-game beurteilen kann. Sandbox-Daten (noch nicht db-verdrahtet).
-- ---------------------------------------------------------------------------
local W = ns.W

-- Sandbox-State, damit die Widgets interaktiv reagieren (kein db-Schreiben).
local demo = {
	breite = 114, hoehe = 60, abstand = 2,
	ausrichtung = "vertical",
	nameShow = true, nameColor = false, nameSize = 12,
	outline = "none",
	hotsOn = true,
}
local function g(k) return function() return demo[k] end end
local function s(k) return function(v) demo[k] = v end end

local ALIGN_OPTS = {
	{ value = "vertical",   label = "Vertikal — Mitglieder untereinander" },
	{ value = "horizontal", label = "Horizontal — Mitglieder nebeneinander" },
}
local OUTLINE_OPTS = {
	{ value = "none", label = "Keine" }, { value = "thin", label = "Dünn" },
	{ value = "thick", label = "Dick" }, { value = "mono", label = "Monochrom" },
}

function Shell:RenderDummy()
	local content = self._content
	if self._dummy then self._dummy:Hide(); self._dummy:SetParent(nil) end
	local d = CreateFrame("Frame", nil, content)
	d:SetAllPoints(content)
	self._dummy = d

	local secName = SECTIONS[self._section][1]
	local tabName = SECTIONS[self._section][2][self._tab] or "?"

	-- y-Cursor: stapelt Blöcke von oben nach unten in den Content-Bereich.
	local y = -4
	local function place(widget, h, dy)
		widget:SetParent(d)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", d, "TOPLEFT", 0, y)
		widget:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, y)
		if h then widget:SetHeight(h) end
		y = y - (h or widget:GetHeight()) - (dy or 22)
	end

	-- 1) Section-Divider
	place(W.SectionDivider(d, secName .. " · " .. tabName), 36, 24)

	-- 2) Drei Slider nebeneinander (row3)
	local sliderRow, cells = W.Row(d, 3, { height = 86 })
	W.Slider(cells[1], { label = "Breite", min = 40, max = 240, value = demo.breite, unit = " px",
		get = g("breite"), set = s("breite") }):SetAllPoints(cells[1])
	W.Slider(cells[2], { label = "Höhe", min = 20, max = 160, value = demo.hoehe, unit = " px",
		get = g("hoehe"), set = s("hoehe") }):SetAllPoints(cells[2])
	W.Slider(cells[3], { label = "Abstand", min = 0, max = 30, value = demo.abstand, unit = " px",
		get = g("abstand"), set = s("abstand") }):SetAllPoints(cells[3])
	place(sliderRow, 86, 22)

	-- 3) Zwei Dropdowns (Ausrichtung + Umrandung) als 2er-Reihe
	local ddRow, ddCells = W.Row(d, 2, { height = 66 })
	W.Select(ddCells[1], { label = "Ausrichtung", options = ALIGN_OPTS,
		get = g("ausrichtung"), set = s("ausrichtung") }):SetAllPoints(ddCells[1])
	W.Select(ddCells[2], { label = "Namens-Umrandung", options = OUTLINE_OPTS,
		get = g("outline"), set = s("outline") }):SetAllPoints(ddCells[2])
	place(ddRow, 66, 24)

	-- 4) Checkbox-Reihe
	local cbRow = CreateFrame("Frame", nil, d)
	local cb1 = W.Checkbox(cbRow, { label = "Name anzeigen", get = g("nameShow"), set = s("nameShow") })
	cb1:SetPoint("LEFT", cbRow, "LEFT", 0, 0)
	local cb2 = W.Checkbox(cbRow, { label = "Namensfarbe", get = g("nameColor"), set = s("nameColor") })
	cb2:SetPoint("LEFT", cb1, "RIGHT", 28, 0)
	place(cbRow, 22, 26)

	-- 5) GroupPanel mit Header-Right-Toggle + Inhalt
	local panel, pc = W.GroupPanel(d, { title = "HoTs" })
	panel._headerRightAnchor(W.Checkbox(panel, { label = "Anzeigen", get = g("hotsOn"), set = s("hotsOn") }))
	local pcSlider = W.Slider(pc, { label = "Namensgröße", min = 6, max = 30, value = demo.nameSize,
		get = g("nameSize"), set = s("nameSize") })
	pcSlider:SetPoint("TOPLEFT", pc, "TOPLEFT", 0, 0)
	pcSlider:SetWidth(320)
	place(panel, 165, 24)

	-- 6) Button-Reihe (primary / ghost / danger)
	local btnRow = CreateFrame("Frame", nil, d)
	local pb = W.Button(btnRow, { text = "Übernehmen", variant = "primary" })
	pb:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
	local gb = W.Button(btnRow, { text = "Standard", variant = "ghost" })
	gb:SetPoint("LEFT", pb, "RIGHT", 12, 0)
	local db = W.Button(btnRow, { text = "Zurücksetzen", variant = "danger" })
	db:SetPoint("LEFT", gb, "RIGHT", 12, 0)
	place(btnRow, 38, 22)

	-- 7) Card mit IconTile + Text (Signatur-Surface)
	local card = W.Card(d)
	local tile = W.IconTile(card, { size = 52, letter = "L" })
	tile:SetPoint("LEFT", card, "LEFT", S.cardPad, 0)
	local ct = FS(card, "body", C.textBody)
	ct:SetJustifyH("LEFT"); ct:SetWordWrap(true)
	ct:SetPoint("LEFT", tile, "RIGHT", 16, 0)
	ct:SetPoint("RIGHT", card, "RIGHT", -S.cardPad, 0)
	ct:SetText("Toolkit-Bausteine: Slider, Select, Checkbox, Button, GroupPanel, "
		.. "Card, IconTile — alle auf den Design-Tokens und pixel-gesnappten Borders.")
	place(card, 92, 22)

	-- 8) Hinweis
	local hint = FS(d, "caption", C.textFaint)
	hint:SetText("Phase 2 — Widget-Toolkit (live bedienbar, noch Sandbox-Daten). "
		.. "/lumen öffnet weiterhin die klassische Konfiguration.")
	hint:SetPoint("TOPLEFT", d, "TOPLEFT", 0, y)
end

-- ===========================================================================
--  API
-- ===========================================================================
function Shell:Toggle()
	local f = self:Build()
	if f:IsShown() then f:Hide() else f:Show() end
end

function Shell:Show()
	self:Build():Show()
end

function Shell:Hide()
	if self._frame then self._frame:Hide() end
end
