local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Modul: Raidframes (v0.9 — secret-sicher, nach EllesmereUI-Muster)
--
--  Bestätigtes 12.0-Vorgehen (mit EllesmereUI abgeglichen):
--   * maxHealth IMMER aus calc:GetMaximumHealth() — UnitHealthMax ist secret.
--   * Rohe Werte (UnitHealth/UnitGetTotalAbsorbs/...HealAbsorbs/...IncomingHeals)
--     direkt an StatusBar:SetValue() — die Bar verträgt secret.
--   * Positionierung über CLIP-FRAMES, an die Lebens-Fülltextur verankert.
--     Die Clips erledigen die Mathematik -> nie secret-Werte vergleichen.
--
--  Schichten:  Leben | (im Fehl-Bereich) Vorhersage -> Schild
--                    | (im Füll-Bereich, von rechts) Heilabsorb
-- ===========================================================================

local Raidframes = {}
ns.Raidframes = Raidframes

local CreateFrame, UIParent = CreateFrame, UIParent
local UnitExists, UnitHealth, UnitHealthMax = UnitExists, UnitHealth, UnitHealthMax
local UnitName, UnitClass = UnitName, UnitClass
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local AuraUtil = AuraUtil
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local strfind, format = string.find, string.format
local pcall = pcall

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local AbbrevNum = _G.AbbreviateNumbersAlt or _G.AbbreviateNumbers or tostring

local T = "Interface\\AddOns\\Lumen\\Textures\\"
local SHIELD_OVL_TEX = T .. "blizzard-shield"      -- 256x40, deckend, Diagonalstreifen + Schattierung
local HEALABS_TEX    = T .. "blizzard-absorb.png"  -- 256x128, halbtransparent, Heilabsorb-Muster
local STRIPE_TEX_W   = 256                          -- Texturbreite beider Streifentexturen (für TexCoord-Tiling)

local CLASS_DISPELS = {
	PRIEST  = { Magic = true, Disease = true },
	PALADIN = { Magic = true, Poison = true, Disease = true },
	SHAMAN  = { Magic = true, Curse = true },
	DRUID   = { Magic = true, Curse = true, Poison = true },
	MONK    = { Magic = true, Poison = true, Disease = true },
	EVOKER  = { Magic = true, Poison = true, Disease = true, Curse = true },
	MAGE    = { Curse = true },
	WARLOCK = { Magic = true },
}
local DISPEL_COLORS = {
	Magic   = { 0.20, 0.60, 1.00 },
	Curse   = { 0.64, 0.19, 0.79 },
	Disease = { 0.55, 0.41, 0.18 },
	Poison  = { 0.12, 0.69, 0.29 },
}

local TEXTURES = {
	["Lumen Gradient"] = (ns.Style and ns.Style.barTexture) or (T .. "lumen-gradient"),
	["Lumen Soft"]     = (ns.Style and ns.Style.barTextureSoft) or (T .. "lumen-gradient-soft"),
	["Blizzard"]       = "Interface\\TargetingFrame\\UI-StatusBar",
	["Classic Raid"]   = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
local function getLSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local function FetchTexture(key)
	if TEXTURES[key] then return TEXTURES[key] end
	local LSM = getLSM()
	if LSM then local p = LSM:Fetch("statusbar", key, true); if p then return p end end
	return WHITE8X8
end
function Raidframes:TextureValues()
	local t = {}
	for k in pairs(TEXTURES) do t[k] = k end
	local LSM = getLSM()
	if LSM then for _, n in ipairs(LSM:List("statusbar")) do t[n] = n end end
	return t
end

-- Heilvorhersage-Calculator (12.0). Einer, wird je Einheit gefüttert.
-- Liefert secret-sicher maxHealth (UnitHealthMax wäre im Kampf secret).
local calc
local function getCalc()
	if calc == nil then
		if _G.CreateUnitHealPredictionCalculator then
			calc = CreateUnitHealPredictionCalculator()
		else
			calc = false
		end
	end
	return calc or nil
end

-- Beispiel-Roster (Testmodus)
local FAKE_MAX = 600000
local FAKE = {
	{ name = "Owlday",     class = "DRUID",   hp = 0.84 },
	{ name = "Elyndra",    class = "MAGE",    hp = 0.90, absorb = 0.25 },
	{ name = "Zakhar",     class = "WARLOCK", hp = 0.62, dispel = "Curse" },
	{ name = "Briar",      class = "PALADIN", hp = 0.55, dispel = "Poison" },
	{ name = "Tormund",    class = "SHAMAN",  hp = 0.60, absorb = 0.22 },
	{ name = "Kaelura",    class = "PRIEST",  hp = 0.77, healAbsorb = 0.20 },
	{ name = "Nighthollow",class = "ROGUE",   hp = 0.43, dispel = "Magic" },
	{ name = "Sylfaria",   class = "MONK",    hp = 0.55, predict = 0.25 },
	{ name = "Grimoak",    class = "WARRIOR", hp = 1.00, healAbsorb = 0.35 },
	{ name = "Velisara",   class = "EVOKER",  hp = 0.71, dispel = "Disease" },
	{ name = "Ravynne",    class = "HUNTER",  hp = 0.95, absorb = 0.10 },
	{ name = "Stormhelm",  class = "DEATHKNIGHT", hp = 0.66, predict = 0.20 },
	{ name = "Brightwing", class = "PALADIN", hp = 0.50, predict = 0.30 },
	{ name = "Embertide",  class = "MAGE",    hp = 0.50, dispel = "Curse" },
	{ name = "Drelvar",    class = "DEMONHUNTER", hp = 0.80, healAbsorb = 0.30 },
	{ name = "Solveig",    class = "PRIEST",  hp = 0.40, healAbsorb = 0.25 },
	{ name = "Zulkhar",    class = "SHAMAN",  hp = 0.58, dispel = "Poison" },
	{ name = "Fenwick",    class = "HUNTER",  hp = 1.00, absorb = 0.30 },
	{ name = "Morgath",    class = "WARRIOR", hp = 0.72, predict = 0.15 },
	{ name = "Aldris",     class = "DRUID",   hp = 0.45, absorb = 0.15 },
}

local frames = {}
local container
local playerDispels = {}
local unitToFrame = {}

local function db() return ns.Lumen.db.profile.raidframes end

local function classColor(class)
	local c = RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end
local function dispelColor(dt)
	local c = DISPEL_COLORS[dt]
	if c then return c[1], c[2], c[3] end
end
local function fillRGB(d, class, dt)
	if d.dispelRecolor and dt then
		local r, g, b = dispelColor(dt)
		if r then return r, g, b end
	end
	if d.useClassColor then return classColor(class) end
	local c = d.fillColor or {}
	return c.r or 0.2, c.g or 0.6, c.b or 0.3
end

local function pointInset(point, x, y)
	local ix, iy, I = x or 0, y or 0, 3
	if point == "TOPLEFT"     then ix = ix + I; iy = iy - I
	elseif point == "TOPRIGHT"    then ix = ix - I; iy = iy - I
	elseif point == "BOTTOMLEFT"  then ix = ix + I; iy = iy + I
	elseif point == "BOTTOMRIGHT" then ix = ix - I; iy = iy + I
	elseif point == "TOP"     then iy = iy - I
	elseif point == "BOTTOM"  then iy = iy + I
	elseif point == "LEFT"    then ix = ix + I
	elseif point == "RIGHT"   then ix = ix - I end
	return ix, iy
end
local function justifyFor(point)
	if strfind(point, "LEFT") then return "LEFT"
	elseif strfind(point, "RIGHT") then return "RIGHT" end
	return "CENTER"
end
local function applyText(fs, frame, point, x, y, size, color)
	point = point or "CENTER"
	fs:SetFont(STANDARD_TEXT_FONT, max(6, size or 12), "OUTLINE")
	fs:ClearAllPoints()
	local ix, iy = pointInset(point, x, y)
	fs:SetPoint(point, frame, point, ix, iy)
	fs:SetJustifyH(justifyFor(point))
	if color then fs:SetTextColor(color.r or 1, color.g or 1, color.b or 1) end
end

local function BuildLiveUnits()
	local u = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do u[#u + 1] = "raid" .. i end
	elseif IsInGroup() then
		u[#u + 1] = "player"
		for i = 1, GetNumGroupMembers() - 1 do u[#u + 1] = "party" .. i end
	else
		u[#u + 1] = "player"
	end
	return u
end
local function GetFakeList(size)
	local list = {}
	for i = 1, size do list[i] = FAKE[((i - 1) % #FAKE) + 1] end
	return list
end

-- Dispel-Typ. Im Kampf ist dispelName secret -> pcall, liefert dann nil.
function Raidframes:GetDispelType(u)
	if not (AuraUtil and AuraUtil.ForEachAura) then return nil end
	local found
	local ok = pcall(function()
		AuraUtil.ForEachAura(u, "HARMFUL", nil, function(aura)
			local dt = aura and aura.dispelName
			if dt and playerDispels[dt] then found = dt; return true end
		end, true)
	end)
	if ok then return found end
	return nil
end

local function makeBar(parent, tex, level)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture(tex or WHITE8X8)
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	if level then b:SetFrameLevel(level) end
	return b
end

-- Streifen-Overlay in einem Clip-Frame — MANUELLES TexCoord-Tiling (Blizzards echte
-- Methode), secret-sicher. Hintergrund: SetHorizTile kachelt über eine StatusBar-Füllung
-- NICHT korrekt (es streckt die Textur), und eine MaskTexture folgt der Füllung nicht.
-- Deshalb:
--  * Die Streifentextur wird über das GANZE Frame (spanFrame = f.health) gespannt und per
--    TexCoord in FESTER Pixelgröße gekachelt (REPEAT horizontal; TexCoord in ApplyConfig).
--    Gleicher Ursprung für Forward + Backfill -> die Diagonale läuft nahtlos über die Kante.
--  * clipParent ist ein Clip-Frame, das an die Absorb-FÜLLUNG verankert ist und damit
--    secret-sicher dem SetValue folgt (wie missClip/curClip der Lebensfüllung folgen) ->
--    der Streifen erscheint NUR über dem tatsächlichen Absorb-Anteil.
local function makeStripe(clipParent, spanFrame, stripeTex)
	local s = clipParent:CreateTexture(nil, "ARTWORK", nil, 2)
	-- Horizontal kacheln (REPEAT, 256px = Power-of-2), vertikal voll zeigen (CLAMP ->
	-- verträgt auch Nicht-Power-of-2-Höhe wie 40px; zeigt die Schattierung einmal).
	s:SetTexture(stripeTex, "REPEAT", "CLAMP")
	s:SetAllPoints(spanFrame)
	return s
end

local function CreateUnitFrame(i)
	local f = CreateFrame("Frame", "LumenUnit" .. i, container)
	local base = f:GetFrameLevel()

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.11, 0.11, 0.11, 1)

	-- Lebensbalken (Basis; seine Fülltextur steuert die Clips)
	f.health = makeBar(f, WHITE8X8, base + 2)
	f.health:SetAllPoints(f)
	local hpTex = f.health:GetStatusBarTexture()

	-- ----- Fehl-Bereich (rechts vom aktuellen Leben): Vorhersage + Schild -----
	f.missClip = CreateFrame("Frame", nil, f.health)
	f.missClip:SetFrameLevel(base + 3)
	f.missClip:SetClipsChildren(true)
	f.missClip:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", -1, 0)
	f.missClip:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", 0, 0)

	f.predictBar = makeBar(f.missClip, WHITE8X8, base + 3)
	f.predictBar:SetStatusBarColor(0.30, 0.85, 0.40, 0.55)
	f.predictBar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
	f.predictBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)

	-- Schild FORWARD: ab der Leben-Kante in den freien Platz rechts. Die UNSICHTBARE
	-- StatusBar-Füllung treibt nur die Geometrie (SetValue=Absorb, secret-sicher); der
	-- shieldClip ist an ihre Füllung verankert und begrenzt das Streifen-Overlay exakt
	-- auf den Absorb-Anteil.
	f.shieldBar = makeBar(f.missClip, WHITE8X8, base + 4)
	f.shieldBar:SetStatusBarColor(1, 1, 1, 0)
	f.shieldBar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
	f.shieldBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)
	f.shieldClip = CreateFrame("Frame", nil, f.missClip)
	f.shieldClip:SetFrameLevel(base + 4)
	f.shieldClip:SetClipsChildren(true)
	f.shieldClip:SetPoint("TOPLEFT", f.shieldBar, "TOPLEFT", 0, 0)
	f.shieldClip:SetPoint("BOTTOMRIGHT", f.shieldBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
	f.shieldStripe = makeStripe(f.shieldClip, f.health, SHIELD_OVL_TEX)

	-- Schild BACKFILL: Overschild über gefülltem Leben (Reverse-Fill von rechts). curClip
	-- begrenzt auf den GEFÜLLTEN Bereich; der backfillClip (an die Backfill-Füllung verankert)
	-- begrenzt auf den Absorb-Anteil. Forward + Backfill teilen denselben Roh-Absorb -> die
	-- Clips machen min(absorb,leben) bzw. max(0,absorb-leben) rein visuell.
	f.curClip = CreateFrame("Frame", nil, f.health)
	f.curClip:SetFrameLevel(base + 4)
	f.curClip:SetClipsChildren(true)
	f.curClip:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, 0)
	f.curClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)

	f.backfillBar = makeBar(f.curClip, WHITE8X8, base + 4)
	f.backfillBar:SetStatusBarColor(1, 1, 1, 0)
	f.backfillBar:SetReverseFill(true)
	f.backfillBar:SetAllPoints(f.health)
	f.backfillClip = CreateFrame("Frame", nil, f.curClip)
	f.backfillClip:SetFrameLevel(base + 4)
	f.backfillClip:SetClipsChildren(true)
	f.backfillClip:SetPoint("TOPLEFT", f.backfillBar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
	f.backfillClip:SetPoint("BOTTOMRIGHT", f.backfillBar, "BOTTOMRIGHT", 0, 0)
	f.backfillStripe = makeStripe(f.backfillClip, f.health, SHIELD_OVL_TEX)

	-- ----- Füll-Bereich (über dem aktuellen Leben): Heilabsorb von rechts -----
	f.healClip = CreateFrame("Frame", nil, f.health)
	f.healClip:SetFrameLevel(base + 5)
	f.healClip:SetClipsChildren(true)
	f.healClip:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, 0)
	f.healClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)

	-- Heilabsorb: unsichtbare Füllung treibt die Geometrie, healAbsClip begrenzt das
	-- (halbtransparente) Muster-Overlay auf den Heilabsorb-Anteil.
	f.healAbsorbBar = makeBar(f.healClip, WHITE8X8, base + 5)
	f.healAbsorbBar:SetStatusBarColor(1, 1, 1, 0)
	f.healAbsorbBar:SetReverseFill(true)
	f.healAbsorbBar:SetPoint("TOPRIGHT", hpTex, "TOPRIGHT", 0, 0)
	f.healAbsorbBar:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)
	f.healAbsClip = CreateFrame("Frame", nil, f.healClip)
	f.healAbsClip:SetFrameLevel(base + 5)
	f.healAbsClip:SetClipsChildren(true)
	f.healAbsClip:SetPoint("TOPLEFT", f.healAbsorbBar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
	f.healAbsClip:SetPoint("BOTTOMRIGHT", f.healAbsorbBar, "BOTTOMRIGHT", 0, 0)
	f.healStripe = makeStripe(f.healAbsClip, f.health, HEALABS_TEX)

	-- ----- Overlay (Tiefe, Texte, Maus-Rand) -----
	f.overlay = CreateFrame("Frame", nil, f)
	f.overlay:SetAllPoints()
	f.overlay:SetFrameLevel(base + 6)
	if ns.Style then ns.Style:ApplyBar(f.health, f.overlay) end

	f.name = f.overlay:CreateFontString(nil, "OVERLAY")
	f.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
	f.name:SetPoint("TOPLEFT", 4, -3)
	f.htext = f.overlay:CreateFontString(nil, "OVERLAY")
	f.htext:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
	f.htext:SetPoint("CENTER")

	local function edge()
		local t = f.overlay:CreateTexture(nil, "OVERLAY", nil, 3)
		t:SetColorTexture(0.83, 0.64, 0.31, 1); t:Hide(); return t
	end
	f.eT, f.eB, f.eL, f.eR = edge(), edge(), edge(), edge()
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self) Raidframes:SetHighlight(self, true) end)
	f:SetScript("OnLeave", function(self) Raidframes:SetHighlight(self, false) end)

	frames[i] = f
	return f
end

function Raidframes:SetHighlight(f, on)
	f.eT:SetShown(on); f.eB:SetShown(on); f.eL:SetShown(on); f.eR:SetShown(on)
end

function Raidframes:ApplyConfig(f)
	local d = db()
	f:SetSize(d.width, d.height)
	f.health:SetStatusBarTexture(FetchTexture(d.healthTexture))
	-- Segment-Bars auf Lebensgröße halten (Anker liefern Höhe/Position)
	f.predictBar:SetSize(d.width, d.height)
	f.shieldBar:SetSize(d.width, d.height)
	f.healAbsorbBar:SetSize(d.width, d.height)

	-- Streifen-Overlays horizontal in FESTER Pixelgröße kacheln: TexCoord-Breite =
	-- Frame-Breite / Texturbreite -> Streifenbreite bleibt konstant, egal wie breit der
	-- Schild/Absorb (kein Stauchen, nahtloser Übergang). Vertikal 0..1 = volle Höhe einmal.
	local tx = d.width / STRIPE_TEX_W
	f.shieldStripe:SetTexCoord(0, tx, 0, 1)
	f.backfillStripe:SetTexCoord(0, tx, 0, 1)
	f.healStripe:SetTexCoord(0, tx, 0, 1)

	if ns.Style then
		local t = d.healthTexture
		if t == "Lumen Gradient" then ns.Style:SetDepth(f.overlay, 1.0)
		elseif t == "Lumen Soft" then ns.Style:SetDepth(f.overlay, 0.55)
		else ns.Style:SetDepth(f.overlay, 0) end
	end
	f.name:SetShown(d.showName)
	applyText(f.name, f, d.namePoint, d.nameX, d.nameY, d.nameSize, d.nameColor)
	applyText(f.htext, f, d.healthTextPoint, d.healthTextX, d.healthTextY, d.healthTextSize, d.healthTextColor)
	f.eT:ClearAllPoints(); f.eT:SetPoint("TOPLEFT"); f.eT:SetPoint("TOPRIGHT"); f.eT:SetHeight(2)
	f.eB:ClearAllPoints(); f.eB:SetPoint("BOTTOMLEFT"); f.eB:SetPoint("BOTTOMRIGHT"); f.eB:SetHeight(2)
	f.eL:ClearAllPoints(); f.eL:SetPoint("TOPLEFT"); f.eL:SetPoint("BOTTOMLEFT"); f.eL:SetWidth(2)
	f.eR:ClearAllPoints(); f.eR:SetPoint("TOPRIGHT"); f.eR:SetPoint("BOTTOMRIGHT"); f.eR:SetWidth(2)
end

-- Alle Bars teilen die Skala 0..maxH. Werte dürfen secret sein; 0 -> unsichtbar.
local function setSegments(f, maxH, healthVal, incoming, absorb, healAbsorb)
	f.health:SetMinMaxValues(0, maxH);        f.health:SetValue(healthVal)
	f.predictBar:SetMinMaxValues(0, maxH);    f.predictBar:SetValue(incoming or 0)
	f.shieldBar:SetMinMaxValues(0, maxH);     f.shieldBar:SetValue(absorb or 0)
	f.backfillBar:SetMinMaxValues(0, maxH);   f.backfillBar:SetValue(absorb or 0)
	f.healAbsorbBar:SetMinMaxValues(0, maxH); f.healAbsorbBar:SetValue(healAbsorb or 0)
end

-- LIVE — secret-sicher (Calculator nur für maxHealth, Rohwerte an die Bars)
function Raidframes:RenderLive(f)
	local u = f.unit
	if not u or not UnitExists(u) then f:Hide(); return end
	f:Show()
	local d = db()

	local maxH
	local c = getCalc()
	if c and UnitGetDetailedHealPrediction then
		pcall(UnitGetDetailedHealPrediction, u, nil, c)
		if c.SetMaximumHealthMode and Enum and Enum.UnitMaximumHealthMode then
			c:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
		end
		maxH = c:GetMaximumHealth()
	end
	maxH = maxH or UnitHealthMax(u)

	local incoming = (d.healPrediction and UnitGetIncomingHeals and UnitGetIncomingHeals(u)) or 0
	local absorb   = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(u)) or 0
	local healAbs  = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(u)) or 0
	setSegments(f, maxH, UnitHealth(u), incoming, absorb, healAbs)

	local _, class = UnitClass(u)
	local dt = d.dispelRecolor and self:GetDispelType(u) or nil
	f.health:SetStatusBarColor(fillRGB(d, class, dt))

	if d.showName then f.name:SetText(UnitName(u) or "") end

	local t = d.healthTextType
	if t == "Keine" then
		f.htext:SetText("")
	elseif t == "Prozent" and _G.UnitHealthPercent then
		local ok, p = pcall(UnitHealthPercent, u, true)
		f.htext:SetText(ok and p and format("%d%%", p) or "")
	else
		local ok, str = pcall(AbbrevNum, UnitHealth(u))
		f.htext:SetText(ok and str or "")
	end
end

-- TESTMODUS — Fake-Zahlen, identischer StatusBar-/Clip-Pfad
function Raidframes:RenderFake(f)
	local fk = f.fake
	local d = db()
	f:Show()

	local hp = fk.hp or 1
	local incoming   = (d.healPrediction and fk.predict or 0) * FAKE_MAX
	local absorb     = (fk.absorb or 0) * FAKE_MAX
	local healAbsorb = (fk.healAbsorb or 0) * FAKE_MAX
	setSegments(f, FAKE_MAX, hp * FAKE_MAX, incoming, absorb, healAbsorb)

	f.health:SetStatusBarColor(fillRGB(d, fk.class, fk.dispel))
	if d.showName then f.name:SetText(fk.name) end

	local t = d.healthTextType
	if t == "Keine" then f.htext:SetText("")
	elseif t == "Prozent" then f.htext:SetText(floor(hp * 100) .. "%")
	else f.htext:SetText(AbbrevNum(floor(hp * FAKE_MAX))) end
end

function Raidframes:UpdateUnit(f)
	if f.fake then return self:RenderFake(f) end
	return self:RenderLive(f)
end

function Raidframes:UpdateLayout()
	if not container then return end
	local d = db()
	local w, h, sp, perCol = d.width, d.height, d.spacing, max(1, d.unitsPerColumn)

	container:ClearAllPoints()
	container:SetPoint(d.point or "CENTER", UIParent, d.point or "CENTER", d.x or 0, d.y or 0)

	local testMode = d.testMode
	local list = testMode and GetFakeList(d.testSize or 5) or BuildLiveUnits()
	local n = #list
	wipe(unitToFrame)

	for i = 1, n do
		local f = frames[i] or CreateUnitFrame(i)
		if testMode then f.fake = list[i]; f.unit = nil else f.unit = list[i]; f.fake = nil; unitToFrame[f.unit] = f end
		local idx = i - 1
		local col = floor(idx / perCol)
		local row = idx % perCol
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", container, "TOPLEFT", col * (w + sp), -row * (h + sp))
		self:ApplyConfig(f)
		self:UpdateUnit(f)
	end
	for i = n + 1, #frames do
		frames[i]:Hide(); frames[i].unit = nil; frames[i].fake = nil
	end

	local cols = max(1, ceil(n / perCol))
	local rows = max(1, min(n, perCol))
	container:SetSize(max(1, cols * (w + sp) - sp), max(1, rows * (h + sp) - sp))
end

local UNIT_EVENTS = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH",
	"UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
	"UNIT_HEAL_PREDICTION", "UNIT_AURA",
}
local function isUnitEvent(e)
	return e == "UNIT_HEALTH" or e == "UNIT_MAXHEALTH"
		or e == "UNIT_ABSORB_AMOUNT_CHANGED" or e == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
		or e == "UNIT_HEAL_PREDICTION" or e == "UNIT_AURA"
end
local function OnUnitEvent(unit)
	if db().testMode then return end
	local f = unitToFrame[unit]
	if f and f:IsShown() then Raidframes:UpdateUnit(f) end
end

function Raidframes:Setup()
	if container then return end
	container = CreateFrame("Frame", "LumenRaidContainer", UIParent)
	container:SetSize(200, 200)
	container:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
	container:RegisterEvent("PLAYER_ENTERING_WORLD")
	container:RegisterEvent("GROUP_ROSTER_UPDATE")
	container:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	for _, ev in ipairs(UNIT_EVENTS) do container:RegisterEvent(ev) end
	container:SetScript("OnEvent", function(_, event, unit)
		if isUnitEvent(event) then
			OnUnitEvent(unit)
		else
			local _, class = UnitClass("player")
			playerDispels = CLASS_DISPELS[class] or {}
			Raidframes:UpdateLayout()
		end
	end)
	local _, class = UnitClass("player")
	playerDispels = CLASS_DISPELS[class] or {}

	if ns.EditMode then
		ns.EditMode:Register(container, "Raidframes", function(p, x, y)
			local d = db(); d.point, d.x, d.y = p, x, y
		end)
	end
end

function Raidframes:Enable()
	self:Setup()
	container:Show()
	self:UpdateLayout()
end
function Raidframes:Disable()
	if not container then return end
	container:Hide()
end
