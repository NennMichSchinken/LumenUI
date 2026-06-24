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
local InCombatLockdown = InCombatLockdown
local UnitExists, UnitHealth, UnitHealthMax = UnitExists, UnitHealth, UnitHealthMax
local UnitName, UnitClass = UnitName, UnitClass
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local IsInRaid = IsInRaid
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local strfind, format = string.find, string.format
local pcall = pcall
local GetTime = GetTime
local issecretvalue = issecretvalue or function() return false end

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local AbbrevNum = _G.AbbreviateNumbersAlt or _G.AbbreviateNumbers or tostring

local T = "Interface\\AddOns\\Lumen\\Textures\\"
local SHIELD_OVL_TEX = T .. "blizzard-shield"      -- 256x40, deckend, Diagonalstreifen + Schattierung
local HEALABS_TEX    = T .. "blizzard-absorb.png"  -- 256x128, halbtransparent, Heilabsorb-Muster
local STRIPE_TEX_W   = 256                          -- Texturbreite beider Streifentexturen (für TexCoord-Tiling)
local HEALABS_TEX_H  = 128                           -- blizzard-absorb: 256x128 (vertikal kachelbar, Zweierpotenz)

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
-- Default-Dispel-Farben (Fallback, wenn der Nutzer keine eigenen gesetzt hat).
local DISPEL_DEFAULTS = {
	Magic   = { r = 0.20, g = 0.60, b = 1.00 },
	Curse   = { r = 0.64, g = 0.19, b = 0.79 },
	Disease = { r = 0.55, g = 0.41, b = 0.18 },
	Poison  = { r = 0.12, g = 0.69, b = 0.29 },
}
-- Blizzard-Dispel-Typ-Enum-Indizes (für die Color-Curve): 1 Magic, 2 Curse, 3 Disease, 4 Poison.
local C_UnitAuras = C_UnitAuras

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

local GROUP_SIZE = 5   -- feste Gruppengröße: Raid-Gruppen & Dungeon-Gruppe sind immer 5 (nie gemischt)

-- Fake-Icon-Texturen für den Testmodus (Vorschau ohne echte Auren), je Kategorie passend.
local FAKE_HOTS      = { 136081, 136085, 236153, 135953, 134914 }
local FAKE_DEFENSIVE = {
	"Interface\\Icons\\Spell_Holy_PowerWordShield",
	"Interface\\Icons\\Spell_Holy_SealOfSacrifice",
	"Interface\\Icons\\Spell_Nature_SkinofEarth",
}
local FAKE_DEBUFF = {
	"Interface\\Icons\\Spell_Shadow_CurseOfSargeras",
	"Interface\\Icons\\Ability_Creature_Poison_03",
	"Interface\\Icons\\Spell_Nature_NullifyDisease",
}

-- Aura-Indikatoren: Kategorien-Registry. filter = Blizzard-Aura-Filter für GetAuraDataByIndex
-- (secret-sicher). subExclude/subInclude verfeinern secret-sicher über IsAuraFilteredOutByInstanceID:
--   subExclude -> nur Auren, die dieser Unterfilter AUSschließt (z.B. "nicht von mir" = fremd).
--   subInclude -> nur Auren, die dieser Unterfilter EINschließt (z.B. externe Defensives).
-- "PLAYER" = selbst gewirkt, "EXTERNAL_DEFENSIVE" = Blizzards kuratierte externe Defensiven.
-- Stufe A (v0.9.11): der "RAID"-Filter = nur im Schlachtzug relevante Hilfsauren
-- (HoTs/Schilde) -> Essen/Flask/Allgemeinbuffs fallen raus. Secret-sicher und auch für
-- fremde Auren nutzbar (Stufe B = exakte Signatur-Whitelist nur für EIGENE HoTs).
local AURA_CATS = {
	{ key = "hotsOwn",    filter = "HELPFUL", whitelist = "hot", ownOnly = true,     fake = FAKE_HOTS },
	{ key = "defensives", filter = "HELPFUL", subInclude = "HELPFUL|EXTERNAL_DEFENSIVE", whitelist = "def", whitelistOr = true, fake = FAKE_DEFENSIVE },
	{ key = "debuffs",    filter = "HARMFUL", harmfulModes = true,                  fake = FAKE_DEBUFF },
}
-- Debuff-Filter-Modi (Blizzard-Standard): "raid" = Blizzards kuratierte raid-relevante
-- Debuffs (HARMFUL|RAID bzw. RAID_IN_COMBAT), "dispellable" = nur selbst dispellbare,
-- "all" = alle. Secret-sicher über IsAuraFilteredOutByInstanceID (nur Bool).
local function debuffModeAccept(u, iid, mode, fn)
	if mode == "none" then return false end
	if mode == "all" then return true end
	if not (fn and iid) then return true end   -- kann nicht filtern -> lieber zeigen
	if mode == "dispellable" then
		return not fn(u, iid, "HARMFUL|RAID_PLAYER_DISPELLABLE")
	end
	-- "raid" (Default, Blizzard-relevant) + Fallback
	return (not fn(u, iid, "HARMFUL|RAID")) or (not fn(u, iid, "HARMFUL|RAID_IN_COMBAT"))
end

-- ---- Aura-Signatur-Lernen (Phase 2 / Stufe B1) ------------------------------
-- 4-Filter-Fingerprint (RAID, RAID_IN_COMBAT, EXTERNAL_DEFENSIVE, RAID_PLAYER_DISPELLABLE;
-- alle PLAYER|HELPFUL) -> identifiziert NUR selbst gewirkte Auren. Wir LERNEN die Zuordnung
-- Signatur->SpellID selbst (außer Kampf, spellId lesbar) und persistieren in
-- db.global.auraSigs[specID] -> im Kampf (spellId secret) per Signatur nachschlagen.
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local function currentSpecID()
	local idx = GetSpecialization and GetSpecialization()
	if not idx then return 0 end
	local id = GetSpecializationInfo and GetSpecializationInfo(idx)
	return id or 0
end
local function auraSig(u, iid)
	local fn = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
	if not (fn and iid) then return nil end
	local r   = not fn(u, iid, "PLAYER|HELPFUL|RAID")
	local ric = not fn(u, iid, "PLAYER|HELPFUL|RAID_IN_COMBAT")
	local ext = not fn(u, iid, "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE")
	local dsp = not fn(u, iid, "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE")
	-- Nichts Distinktives (Essen/Flask/Allgemeinbuffs passieren keinen der vier Filter) -> raus.
	-- (B3: ext/dsp wandern VOR den Early-Out, damit auch eigene Defensiven, die zwar nicht
	-- RAID, aber EXTERNAL_DEFENSIVE/dispellbar sind, lernbar werden.)
	if not (r or ric or ext or dsp) then return nil end
	return (r and "1" or "0") .. ":" .. (ric and "1" or "0") .. ":" .. (ext and "1" or "0") .. ":" .. (dsp and "1" or "0")
end
-- Bereits gefingerprintete Aura-Instanzen -> jede Instanz nur EINMAL berechnen. Hält die
-- OOC-Steady-State-Kosten faktisch bei einem reinen Aura-Scan. Bei Spec-Wechsel geleert.
local learnedIID = {}
-- Passiv lernen: NUR außer Kampf (im Kampf null Kosten -> früher Early-Out), die eigenen
-- Auren auf u scannen, neue Signatur->SpellID merken. Aufruf einmal je UNIT_AURA der Unit.
local function learnUnitSigs(u)
	if InCombatLockdown() then return end           -- Hot-Path im Kampf: ein einziger Check
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and ns.Lumen and ns.Lumen.db) then return end
	local g = ns.Lumen.db.global
	local store = g and g.auraSigs
	if not store then return end
	local spec = currentSpecID()
	if spec == 0 then return end
	local s = store[spec]; if not s then s = {}; store[spec] = s end
	local i = 1
	while i <= 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL|PLAYER")
		if not aura then break end
		i = i + 1
		local iid = aura.auraInstanceID
		if iid and not issecretvalue(iid) and not learnedIID[iid] then
			learnedIID[iid] = true                  -- nur neue Instanzen fingerprinten
			local sid = aura.spellId
			if sid and not issecretvalue(sid) then
				local sig = auraSig(u, iid)
				if sig and not s[sig] then s[sig] = sid end
			end
		end
	end
end

-- ---- HoT-/Defensiv-Whitelist (Phase 2 / Stufe B2+B3) -----------------------
-- Kuratierte Standard-Spells je Heiler-Spec (spellID), an EllesmereUIs Liste als
-- Benchmark ausgerichtet (eigenständig nachgebaut). Werden lazy in
-- db.profile.raidframes.auras.whitelist[specID] geseedet (HoTs Typ "hot",
-- Defensiven Typ "def"). Im Whitelist-Editor (B4) pro Spec anpassbar.
local HOT_DEFAULTS = {
	[105]  = { 774, 8936, 33763, 155777, 48438, 439530 },          -- Resto Druid: Rejuv, Regrowth, Lifebloom, Germination, Wild Growth, Symbiotic Blooms
	[256]  = { 17, 194384, 1253593, 41635 },                       -- Disc Priest: PW:Shield, Atonement, Void Shield, PoM
	[257]  = { 139, 77489, 41635 },                                -- Holy Priest: Renew, Echo of Light, PoM
	[270]  = { 119611, 124682, 115175, 450769 },                   -- MW Monk: Renewing/Enveloping/Soothing Mist, Aspect of Harmony
	[264]  = { 61295, 974, 382024, 207400, 444490 },               -- Resto Shaman: Riptide, Earth Shield, Earthliving, Ancestral Vigor, Hydrobubble
	[65]   = { 156910, 156322, 53563, 1244893, 200025 },           -- Holy Pala: Beacon of Faith, Eternal Flame, Beacon of Light, Beacon of Savior, Beacon of Virtue
	[1468] = { 364343, 366155, 367364, 355941, 376788, 363502, 373267 }, -- Pres Evoker: Echo, Reversion, Echo Reversion, Dream Breath, Echo Dream Breath, Dream Flight, Lifebind
}
-- specID -> classToken. Für die klassenweiten Defensiv-Defaults (DEF_CLASS) und
-- B4-tauglich (unabhängig von der Live-Klasse).
local SPEC_CLASS = {
	[71]="WARRIOR",[72]="WARRIOR",[73]="WARRIOR",
	[65]="PALADIN",[66]="PALADIN",[70]="PALADIN",
	[253]="HUNTER",[254]="HUNTER",[255]="HUNTER",
	[259]="ROGUE",[260]="ROGUE",[261]="ROGUE",
	[256]="PRIEST",[257]="PRIEST",[258]="PRIEST",
	[250]="DEATHKNIGHT",[251]="DEATHKNIGHT",[252]="DEATHKNIGHT",
	[262]="SHAMAN",[263]="SHAMAN",[264]="SHAMAN",
	[62]="MAGE",[63]="MAGE",[64]="MAGE",
	[265]="WARLOCK",[266]="WARLOCK",[267]="WARLOCK",
	[268]="MONK",[269]="MONK",[270]="MONK",
	[102]="DRUID",[103]="DRUID",[104]="DRUID",[105]="DRUID",
	[577]="DEMONHUNTER",[581]="DEMONHUNTER",
	[1467]="EVOKER",[1468]="EVOKER",[1473]="EVOKER",
}
-- Defensiven (Typ "def"). Externe (auf andere gewirkt) -> über Signatur lernbar, Kampf-Icon
-- sauber. Persönliche Selbst-CDs erscheinen nur auf dem EIGENEN Frame und (noch) nur außer
-- Kampf, wenn sie KEINEN der vier Signatur-Filter passieren (spellId secret); zuverlässig
-- für alle im Kampf käme später über Cast-Events (UNIT_SPELLCAST_SUCCEEDED). Gute Defaults
-- out-of-the-box für JEDE Klasse/Spec (Anti-Bloat: nutzbar ohne Customizing), im B4-Editor
-- pro Spec anpassbar. spellIds live geprüft/zu prüfen — fehlende/falsche melden -> hier fixen.
-- DEF_CLASS = klassenweite Defensiven (alle Specs der Klasse), DEF_DEFAULTS = spec-spezifisch.
local DEF_CLASS = {
	WARRIOR     = { 97462, 23920 },                  -- Rallying Cry, Spell Reflection
	PALADIN     = { 642, 498, 1022, 1044, 6940 },    -- Divine Shield, Divine Protection, Blessing of Protection/Freedom/Sacrifice
	HUNTER      = { 186265, 264735 },                -- Aspect of the Turtle, Survival of the Fittest
	ROGUE       = { 31224, 5277, 1966 },             -- Cloak of Shadows, Evasion, Feint
	PRIEST      = { 19236 },                          -- Desperate Prayer
	DEATHKNIGHT = { 48707, 48792, 51052 },           -- Anti-Magic Shell, Icebound Fortitude, Anti-Magic Zone
	SHAMAN      = { 108271 },                          -- Astral Shift
	MAGE        = { 45438, 342245 },                 -- Ice Block, Alter Time
	WARLOCK     = { 104773, 108416 },                -- Unending Resolve, Dark Pact
	MONK        = { 115203, 122278, 122783 },        -- Fortifying Brew, Dampen Harm, Diffuse Magic
	DRUID       = { 22812 },                           -- Barkskin
	DEMONHUNTER = { 196718 },                          -- Darkness
	EVOKER      = { 363916, 374348 },                -- Obsidian Scales, Renewing Blaze
}
local DEF_DEFAULTS = {
	-- Warrior
	[71]   = { 118038 },                             -- Arms: Die by the Sword
	[72]   = { 184364 },                             -- Fury: Enraged Regeneration
	[73]   = { 871, 12975 },                         -- Prot: Shield Wall, Last Stand
	-- Paladin (Class deckt Divine Shield/Protection, BoP, Freedom, Sacrifice)
	[65]   = { 432502 },                             -- Holy: Holy Armaments
	[66]   = { 31850, 86659, 204018 },               -- Prot: Ardent Defender, Guardian of Ancient Kings, Blessing of Spellwarding
	[70]   = { 184662 },                             -- Ret: Shield of Vengeance
	-- Priest
	[256]  = { 33206, 81782, 10060 },                -- Disc: Pain Suppression, Power Word: Barrier, Power Infusion
	[257]  = { 47788, 10060 },                       -- Holy: Guardian Spirit, Power Infusion
	[258]  = { 47585 },                              -- Shadow: Dispersion
	-- Death Knight
	[250]  = { 55233, 49028, 48743, 194679 },        -- Blood: Vampiric Blood, Dancing Rune Weapon, Death Pact, Rune Tap
	-- Shaman
	[264]  = { 98008 },                              -- Resto: Spirit Link Totem
	-- Mage (Class deckt Ice Block/Alter Time)
	[62]   = { 235450 },                             -- Arcane: Prismatic Barrier
	[63]   = { 235313 },                             -- Fire: Blazing Barrier
	[64]   = { 11426 },                              -- Frost: Ice Barrier
	-- Monk
	[268]  = { 115176, 322507 },                     -- Brewmaster: Zen Meditation, Celestial Brew
	[269]  = { 122470 },                             -- Windwalker: Touch of Karma
	[270]  = { 116849, 443113 },                     -- Mistweaver: Life Cocoon, Strength of the Black Ox
	-- Druid (Class deckt Barkskin)
	[103]  = { 61336, 22842 },                       -- Feral: Survival Instincts, Frenzied Regeneration
	[104]  = { 61336, 22842, 200851 },               -- Guardian: Survival Instincts, Frenzied Regeneration, Rage of the Sleeper
	[105]  = { 102342 },                             -- Resto: Ironbark
	-- Demon Hunter
	[577]  = { 198589, 196555 },                     -- Havoc: Blur, Netherwalk
	[581]  = { 187827, 204021 },                     -- Vengeance: Metamorphosis, Fiery Brand
	-- Evoker (Class deckt Obsidian Scales/Renewing Blaze)
	[1468] = { 357170, 363534 },                     -- Preservation: Time Dilation, Rewind
}

local frames = {}            -- Nicht-Secure-Pool für Preview/Test
local container
local header                 -- SecureGroupHeader (Live-Pfad)
local secureLayoutDirty = false   -- Layout im Kampf aufgeschoben? -> bei PLAYER_REGEN_ENABLED nachholen
local playerDispels = {}
local unitToButton = {}      -- Live-Routing: Unit -> Secure-Button (Preview/Test routet nicht)

local function db() return ns.Lumen.db.profile.raidframes end

-- Whitelist der aktiven Spec holen; Defaults (HoT/Def) lazy einmischen.
-- Liegt im Profil (teil-/resetbar). NICHT in den Core-Defaults -> der erste Schreib
-- erzeugt eine echte profil-eigene Tabelle (kein Mutieren der geteilten Defaults).
-- whitelistSeeded[spec][spellID]=true merkt sich bereits ANGEBOTENE Defaults: so kommen
-- echte Neuzugänge (z.B. neue Def-Defaults in einem Update, oder ein altes B2-Profil mit
-- nur HoTs) dazu, ohne vom Nutzer (B4) bewusst entfernte Spells wieder hinzuzufügen.
local function whitelistFor(spec)
	if spec == 0 then return nil end
	local A = db().auras
	if not A then return nil end
	local wl = A.whitelist
	if not wl then wl = {}; A.whitelist = wl end
	local seeded = A.whitelistSeeded
	if not seeded then seeded = {}; A.whitelistSeeded = seeded end
	local s = wl[spec];      if not s  then s = {};  wl[spec] = s end
	local ss = seeded[spec]; if not ss then ss = {}; seeded[spec] = ss end
	local function ensure(list, typ)
		if not list then return end
		for _, sid in ipairs(list) do
			if not ss[sid] then
				ss[sid] = true
				if s[sid] == nil then s[sid] = typ end
			end
		end
	end
	ensure(HOT_DEFAULTS[spec], "hot")
	ensure(DEF_DEFAULTS[spec], "def")
	ensure(DEF_CLASS[SPEC_CLASS[spec]], "def")   -- klassenweite Defensiven
	return s
end

-- ---------------------------------------------------------------------------
--  Whitelist-Editor (B4, Options-Tab "Tracking") — öffentliche API.
--  Arbeitet auf db().auras.whitelist[specID] (spellID -> "hot"|"def"); seedt die
--  Spec lazy über whitelistFor. Reine OOC-Bedienfunktionen (kein Hot-Path).
-- ---------------------------------------------------------------------------
-- Einträge eines Typs ("hot"|"def") einer Spec als {id,name,icon}, alphabetisch.
function Raidframes:WhitelistEntries(specID, typ)
	local out = {}
	if not specID or specID == 0 then return out end
	local s = whitelistFor(specID); if not s then return out end
	for sid, t in pairs(s) do
		if t == typ then
			local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)) or ("Spell " .. sid)
			local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)) or 136243
			out[#out + 1] = { id = sid, name = name, icon = icon }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end
-- Roh-Map {spellID = "hot"|"def"} einer Spec (für die Picker-Dedupe: schon getrackte
-- Spells aus dem Auswahl-Dropdown ausblenden). Seedt die Spec lazy.
function Raidframes:WhitelistMap(specID)
	if not specID or specID == 0 then return {} end
	return whitelistFor(specID) or {}
end
-- Spell in die Whitelist aufnehmen.
function Raidframes:AddWhitelist(specID, spellID, typ)
	if not specID or specID == 0 or not spellID then return end
	local s = whitelistFor(specID); if not s then return end
	s[spellID] = typ
	self:RefreshAuras()
end
-- Spell entfernen. Der seeded-Marker bleibt absichtlich gesetzt -> ein per Default
-- geseedeter Spell kommt NICHT von allein zurück (bewusste Entfernung bleibt bestehen).
function Raidframes:RemoveWhitelist(specID, spellID)
	if not specID or specID == 0 or not spellID then return end
	local A = db().auras; if not A or not A.whitelist then return end
	local s = A.whitelist[specID]; if not s then return end
	s[spellID] = nil
	self:RefreshAuras()
end
-- Auf die kuratierten Defaults dieses Typs zurücksetzen: erst alle Einträge des Typs
-- raus (auch vom Nutzer hinzugefügte), dann die Defaults DIREKT wieder eintragen und
-- als geseedet markieren. Unbedingt (kein Seed-Guard) -> bringt ALLE Defaults zurück.
function Raidframes:ResetWhitelist(specID, typ)
	if not specID or specID == 0 then return end
	local A = db().auras; if not A then return end
	A.whitelist = A.whitelist or {}; A.whitelistSeeded = A.whitelistSeeded or {}
	local s  = A.whitelist[specID];       if not s  then s  = {}; A.whitelist[specID]       = s end
	local ss = A.whitelistSeeded[specID]; if not ss then ss = {}; A.whitelistSeeded[specID] = ss end
	for sid, t in pairs(s) do if t == typ then s[sid] = nil end end
	local function restore(list)
		if not list then return end
		for _, sid in ipairs(list) do s[sid] = typ; ss[sid] = true end
	end
	if typ == "hot" then
		restore(HOT_DEFAULTS[specID])
	else
		restore(DEF_DEFAULTS[specID])
		restore(DEF_CLASS[SPEC_CLASS[specID]])
	end
	self:RefreshAuras()
end
-- SpellID einer Aura ermitteln — secret-sicher:
--   * außer Kampf ist aura.spellId direkt lesbar.
--   * im Kampf ist sie secret -> über die (außer Kampf gelernte) Signatur nachschlagen.
-- Rückgabe nil = (noch) nicht auflösbar (z.B. im Kampf vor dem ersten OOC-Lernen).
-- Manche Auren werden mit einer ANDEREN spellId angewendet als der getrackten
-- (Cast-ID != Aura-ID). Hier auf die in der Whitelist geführte Haupt-ID mappen.
-- (Muster + Earth-Shield-Beispiel an EllesmereUI orientiert.)
local PRIMARY_BY_ALT = {
	[383648] = 974,   -- Earth Shield (alternative Aura-ID -> Haupt-ID)
}
local function resolveSpellId(u, aura, spec)
	local sid = aura.spellId
	if sid ~= nil and not issecretvalue(sid) then return PRIMARY_BY_ALT[sid] or sid end
	local iid = aura.auraInstanceID
	if not iid or issecretvalue(iid) then return nil end
	local sig = auraSig(u, iid)
	if not sig then return nil end
	local g = ns.Lumen.db and ns.Lumen.db.global
	local store = g and g.auraSigs
	local s = store and store[spec]
	return s and s[sig] or nil
end

-- Whitelist-Typ einer spellId: direkt ODER über den Basis-Zauber (GetBaseSpell), damit
-- talent-/rang-modifizierte Override-IDs auf den getrackten Basis-Spell matchen.
local function wlType(wl, sid)
	if not (wl and sid) then return nil end
	local t = wl[sid]
	if t then return t end
	if C_Spell and C_Spell.GetBaseSpell then
		local base = C_Spell.GetBaseSpell(sid)
		if base and base ~= sid then return wl[base] end
	end
	return nil
end

-- Icon einer Aura setzen. aura.icon ist im Kampf secret (12.0), aber StatusBar/Texture-
-- Setter nehmen secret-Werte NATIV an und rendern sie korrekt — bestätigtes Vorgehen
-- (EllesmereUI: "texture may be SECRET: SetTexture accepts it natively"). Dadurch echte
-- Icons auch im Kampf, für EIGENE wie FREMDE Auren (entscheidend für Debuffs). Nur wenn
-- gar kein Icon vorliegt (nil) der Zahnrad-Fallback.
local function applyAuraIcon(ic, aura)
	local tex = aura.icon
	if tex ~= nil then ic.tex:SetTexture(tex) else ic.tex:SetTexture(136243) end
end

-- Aktiver Layout-/Positions-Kontext: Schlachtzug (raid) vs. 5er-Gruppe/Dungeon (party).
-- Im Testmodus nach Test-Größe (5 = party, sonst raid).
local function layoutCtx()
	local d = db()
	if d.testMode then return (d.testSize == 5) and d.party or d.raid end
	return IsInRaid() and d.raid or d.party
end

local function classColor(class)
	local c = RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end
-- Konfigurierte Dispel-Farbe (oder Default) für einen Typ.
local function dispelCol(d, key)
	local c = (d.dispelColors and d.dispelColors[key]) or DISPEL_DEFAULTS[key]
	return c.r or 0.5, c.g or 0.5, c.b or 0.5
end
-- Grundfarbe des Lebensbalkens: Klassenfarbe oder feste Füllfarbe (KEINE Dispel-Logik mehr).
local function fillRGB(d, class)
	if d.useClassColor then return classColor(class) end
	local c = d.fillColor or {}
	return c.r or 0.2, c.g or 0.6, c.b or 0.3
end

-- Dispel-Farb-Curve (12.0): Blizzard wertet den (secret) Dispel-Typ intern gegen die
-- Curve aus und liefert die Farbe -> typ-genau im Kampf, ohne den secret-Wert zu lesen.
-- Wird lazily gebaut und bei Settings-Änderungen invalidiert (siehe UpdateLayout).
local dispelCurve
local function buildDispelCurve()
	dispelCurve = nil
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType) then return end
	local d = db()
	local function pt(c, idx, key)
		local r, g, b = dispelCol(d, key)
		c:AddPoint(idx, CreateColor(r, g, b))
	end
	local c = C_CurveUtil.CreateColorCurve()
	c:SetType(Enum.LuaCurveType.Step)
	pt(c, 0, "Magic")   -- none/Fallback
	pt(c, 1, "Magic")
	pt(c, 2, "Curse")
	pt(c, 3, "Disease")
	pt(c, 4, "Poison")
	dispelCurve = c
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
-- Schrift-Umrandung: gespeicherter Wert -> WoW-SetFont-Flag
local OUTLINE_FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local function applyText(fs, frame, point, x, y, size, color, outline)
	point = point or "CENTER"
	fs:SetFont(STANDARD_TEXT_FONT, max(6, size or 12), OUTLINE_FLAGS[outline] or "OUTLINE")
	fs:ClearAllPoints()
	local ix, iy = pointInset(point, x, y)
	fs:SetPoint(point, frame, point, ix, iy)
	fs:SetJustifyH(justifyFor(point))
	if color then fs:SetTextColor(color.r or 1, color.g or 1, color.b or 1) end
end

local function GetFakeList(size)
	local list = {}
	for i = 1, size do list[i] = FAKE[((i - 1) % #FAKE) + 1] end
	return list
end

-- Wiederverwendete Scratch-Farbe (keine Tabelle pro Aufruf im heißen Pfad).
local dispelScratch = { r = 1, g = 1, b = 1 }

-- Secret-sichere Dispel-Erkennung (12.0):
--  * Filter "HARMFUL|RAID_PLAYER_DISPELLABLE" -> Blizzard liefert nur, was ICH dispellen
--    kann (intern in C++, kein Lua-Vergleich auf secret). "Alle" -> "HARMFUL" + nil-Check.
--  * dispelName ~= nil ist ein secret-sicherer nil-Check (liest den Wert nicht) und sagt,
--    OB ein (typisierter) dispellbarer Debuff anliegt — auch bei secret Boss-Debuffs.
--  * Farbe via GetAuraDispelTypeColor + Curve: Blizzard wertet den secret Typ intern aus
--    und gibt die Farbe zurück -> typ-genau im Kampf, ohne den secret-Wert zu lesen.
-- Rückgabe: hasDispel(bool, secret-frei), r, g, b (ggf. secret -> nur an C++-Setter geben).
function Raidframes:GetDispel(u, d)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
	if not dispelCurve then buildDispelCurve() end
	local filter = d.dispelShowAll and "HARMFUL" or "HARMFUL|RAID_PLAYER_DISPELLABLE"
	local i = 1
	while true do
		local aura = C_UnitAuras.GetAuraDataByIndex(u, i, filter)
		if not aura then break end
		i = i + 1
		if aura.dispelName ~= nil then   -- secret-sicher
			if dispelCurve and C_UnitAuras.GetAuraDispelTypeColor then
				local col = C_UnitAuras.GetAuraDispelTypeColor(u, aura.auraInstanceID, dispelCurve)
				if col then
					local sc = dispelScratch
					sc.r, sc.g, sc.b = col:GetRGB()
					return true, sc.r, sc.g, sc.b
				end
			end
			-- Fallback (API fehlt): generische Magic-Farbe als „dispellbar"-Hinweis.
			local r, g, b = dispelCol(d, "Magic")
			return true, r, g, b
		end
	end
	return false
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
-- vTile=true -> auch VERTIKAL in fester Pixelgröße kacheln (nur für Zweierpotenz-Höhen wie
-- die 128px-Healabsorb-Textur sauber). vTile=false -> vertikal CLAMP (Schild: 256x40, NICHT
-- Zweierpotenz -> REPEAT zeigte eine Naht; CLAMP streckt die Diagonale, fällt aber nicht auf).
-- Den TexCoord-Faktor (Frame-Größe / Texturgröße) setzt ApplyConfig.
local function makeStripe(clipParent, spanFrame, stripeTex, vTile)
	local s = clipParent:CreateTexture(nil, "ARTWORK", nil, 2)
	s:SetTexture(stripeTex, "REPEAT", vTile and "REPEAT" or "CLAMP")
	s:SetAllPoints(spanFrame)
	return s
end

-- ----- Aura-Indikatoren (Phase 1): Icon-Pool, Anker, Auto-Fit-Größe -----
-- Welcher Kontext bestimmt die explizite Icon-Größe (Auto-Fit aus)? raid vs party.
local function isRaidContext()
	local d = db()
	if d.testMode then return d.testSize ~= 5 end
	return IsInRaid()
end
-- Icon-Größe einer Kategorie: Auto-Fit -> aus der Frame-Höhe abgeleitet (skaliert also
-- automatisch zwischen Raid/Gruppe mit), sonst explizit pro Kontext.
local function auraIconSize(cat, L)
	if not cat.autoFit then
		return isRaidContext() and (cat.sizeRaid or 16) or (cat.sizeParty or 22)
	end
	-- Auto-Fit: ~30% der Frame-Höhe, ABER so gedeckelt, dass die volle Reihe/Spalte in
	-- den Frame passt (kein Überlauf über den Rand bei schmalen/kurzen Frames):
	-- horizontales Wachstum an der Breite deckeln, vertikales an der Höhe.
	local h, w = L.height or 60, L.width or 114
	local n  = max(1, cat.maxIcons or 5)
	local sp = cat.spacing or 0
	local size = h * 0.30
	local grow = cat.grow or "RIGHT"
	if grow == "UP" or grow == "DOWN" then
		size = min(size, (h - sp * (n - 1)) / n)
	else
		size = min(size, (w - sp * (n - 1)) / n)
	end
	return max(8, min(48, floor(size)))
end
-- Kleiner Versatz nach innen, damit Icons nicht auf der Frame-Kante kleben.
local function auraInset(point)
	local I, x, y = 1, 0, 0
	if strfind(point, "LEFT") then x = I elseif strfind(point, "RIGHT") then x = -I end
	if strfind(point, "TOP") then y = -I elseif strfind(point, "BOTTOM") then y = I end
	return x, y
end
-- Positioniert die SICHTBAREN Icons (count Stück) entlang der Wachstumsrichtung. Liegt der
-- Anker auf der Wachstums-Achse mittig (z.B. „Unten"/„Mitte"), wird die Reihe ZENTRIERT —
-- und zwar anhand der tatsächlichen Anzahl, also auch bei wechselnder HoT-Zahl mittig.
-- Läuft beim Rendern (count ist erst dann bekannt).
local function positionAuraIcons(holder, count)
	if count < 1 then return end
	local anchor = holder._anchor or "BOTTOMLEFT"
	local grow   = holder._grow or "RIGHT"
	local step   = (holder._size or 16) + (holder._spacing or 0)
	local dirX, dirY = 0, 0
	if grow == "RIGHT" then dirX = 1 elseif grow == "LEFT" then dirX = -1
	elseif grow == "UP" then dirY = 1 elseif grow == "DOWN" then dirY = -1 end
	local horiz = (dirX ~= 0)
	local centerX = horiz and not (strfind(anchor, "LEFT") or strfind(anchor, "RIGHT"))
	local centerY = (not horiz) and not (strfind(anchor, "TOP") or strfind(anchor, "BOTTOM"))
	local ix, iy = auraInset(anchor)
	local sx = centerX and (-dirX * (count - 1) * step / 2) or 0
	local sy = centerY and (-dirY * (count - 1) * step / 2) or 0
	for i = 1, count do
		local ic = holder.icons[i]
		if ic then
			ic:ClearAllPoints()
			ic:SetPoint(anchor, holder, anchor, ix + sx + (i - 1) * dirX * step, iy + sy + (i - 1) * dirY * step)
		end
	end
end
local function makeAuraIcon(holder)
	local ic = CreateFrame("Frame", nil, holder)
	ic.bg = ic:CreateTexture(nil, "BACKGROUND")
	ic.bg:SetAllPoints()
	ic.bg:SetColorTexture(0, 0, 0, 1)            -- 1px schwarzer Rahmen
	ic.tex = ic:CreateTexture(nil, "ARTWORK")
	ic.tex:SetPoint("TOPLEFT", 1, -1)
	ic.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- Icon-Standardrand wegschneiden
	ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
	ic.cd:SetAllPoints(ic.tex)
	ic.cd:SetDrawEdge(false)
	ic.cd:SetHideCountdownNumbers(true)
	ic:Hide()
	return ic
end
-- Einen Kategorie-Block layouten: Holder + Icon-Pool an Anker/Größe/Wachstumsrichtung
-- positionieren. Befüllt (Textur/Swipe/Show) wird erst beim Rendern. NUR im Layout-Pfad
-- aufrufen (erzeugt ggf. Frames -> out-of-combat).
local function layoutAuraCat(f, key, cat, size)
	local holder = f.auraHolders[key]
	if not (cat and cat.enabled) then
		if holder then holder:Hide() end
		return
	end
	if not holder then
		holder = CreateFrame("Frame", nil, f.overlay)
		holder:SetAllPoints(f)
		holder.icons = {}
		f.auraHolders[key] = holder
	end
	holder:Show()
	-- Layout-Parameter für die render-zeitige Positionierung (positionAuraIcons) merken.
	holder._anchor  = cat.anchor or "BOTTOMLEFT"
	holder._grow    = cat.grow or "RIGHT"
	holder._size    = size
	holder._spacing = cat.spacing or 0
	local maxN = cat.maxIcons or 5
	for i = 1, maxN do
		local ic = holder.icons[i] or makeAuraIcon(holder)
		holder.icons[i] = ic
		ic:SetSize(size, size)
		if cat.showSwipe then ic.cd:Show() else ic.cd:Hide() end
		ic:Hide()
	end
	for i = maxN + 1, #holder.icons do holder.icons[i]:Hide() end
end

-- Dekoriert einen beliebigen Host (Nicht-Secure-Frame für Preview ODER Secure-Button
-- für Live) mit dem kompletten Render-Stack (bg, Leben, Clips, Schilde, Heilabsorb,
-- Overlay, Texte, Dispel-/Maus-Ränder). Erzeugt den Host NICHT und setzt KEINE
-- Maus-/Klick-Scripts — das ist host-spezifisch (Preview: SetScript; Secure: HookScript).
-- So teilen sich Live- und Test-Pfad genau einen Render-Code.
local function Decorate(f)
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
	f.healStripe = makeStripe(f.healAbsClip, f.health, HEALABS_TEX, true)

	-- ----- Overlay (Tiefe, Texte, Maus-Rand) -----
	f.overlay = CreateFrame("Frame", nil, f)
	f.overlay:SetAllPoints()
	f.overlay:SetFrameLevel(base + 6)
	if ns.Style then ns.Style:ApplyBar(f.health, f.overlay) end

	f.auraHolders = {}   -- [catKey] = Holder-Frame mit Icon-Pool (lazy in ApplyConfig)

	f.name = f.overlay:CreateFontString(nil, "OVERLAY")
	f.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
	f.name:SetPoint("TOPLEFT", 4, -3)
	f.htext = f.overlay:CreateFontString(nil, "OVERLAY")
	f.htext:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
	f.htext:SetPoint("CENTER")

	-- Dispel-Overlay (Modus "overlay"): farbiger Rand + leichte Füllung in Dispel-Farbe.
	-- Weiße Texturen -> Farbe per SetVertexColor (verträgt secret-Werte).
	f.dFill = f.overlay:CreateTexture(nil, "ARTWORK", nil, 1)
	f.dFill:SetColorTexture(1, 1, 1, 1); f.dFill:SetAllPoints(f.health); f.dFill:Hide()
	local function dedge()
		local t = f.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
		t:SetColorTexture(1, 1, 1, 1); t:Hide(); return t
	end
	f.dT, f.dB, f.dL, f.dR = dedge(), dedge(), dedge(), dedge()
	f.dT:SetPoint("TOPLEFT"); f.dT:SetPoint("TOPRIGHT"); f.dT:SetHeight(2)
	f.dB:SetPoint("BOTTOMLEFT"); f.dB:SetPoint("BOTTOMRIGHT"); f.dB:SetHeight(2)
	f.dL:SetPoint("TOPLEFT"); f.dL:SetPoint("BOTTOMLEFT"); f.dL:SetWidth(2)
	f.dR:SetPoint("TOPRIGHT"); f.dR:SetPoint("BOTTOMRIGHT"); f.dR:SetWidth(2)

	local function edge()
		local t = f.overlay:CreateTexture(nil, "OVERLAY", nil, 3)
		t:SetColorTexture(0.83, 0.64, 0.31, 1); t:Hide(); return t
	end
	f.eT, f.eB, f.eL, f.eR = edge(), edge(), edge(), edge()
end

-- Preview-/Test-Host: gewöhnlicher (Nicht-Secure-)Frame, mit direkten Maus-Scripts.
-- Der Live-Pfad nutzt stattdessen Secure-Buttons (siehe Header-Setup) und HookScript.
local function CreateUnitFrame(i)
	local f = CreateFrame("Frame", "LumenUnit" .. i, container)
	Decorate(f)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self) Raidframes:SetHighlight(self, true) end)
	f:SetScript("OnLeave", function(self) Raidframes:SetHighlight(self, false) end)

	frames[i] = f
	return f
end

function Raidframes:SetHighlight(f, on)
	f.eT:SetShown(on); f.eB:SetShown(on); f.eL:SetShown(on); f.eR:SetShown(on)
end

-- Dispel-Overlay setzen (Modus "overlay"): Rand + Füllung in Dispel-Farbe ein/aus.
-- r,g,b dürfen secret sein -> nur an SetVertexColor (C++) geben.
function Raidframes:SetDispelOverlay(f, on, r, g, b, alpha)
	if on then
		f.dFill:SetVertexColor(r, g, b, alpha or 0.3); f.dFill:Show()
		f.dT:SetVertexColor(r, g, b, 1); f.dT:Show()
		f.dB:SetVertexColor(r, g, b, 1); f.dB:Show()
		f.dL:SetVertexColor(r, g, b, 1); f.dL:Show()
		f.dR:SetVertexColor(r, g, b, 1); f.dR:Show()
	else
		f.dFill:Hide(); f.dT:Hide(); f.dB:Hide(); f.dL:Hide(); f.dR:Hide()
	end
end

function Raidframes:ApplyConfig(f)
	local d = db()
	local L = layoutCtx()
	f:SetSize(L.width, L.height)
	f.health:SetStatusBarTexture(FetchTexture(d.healthTexture))
	-- Segment-Bars auf Lebensgröße halten (Anker liefern Höhe/Position)
	f.predictBar:SetSize(L.width, L.height)
	f.shieldBar:SetSize(L.width, L.height)
	f.healAbsorbBar:SetSize(L.width, L.height)

	-- Streifen-Overlays horizontal in FESTER Pixelgröße kacheln (Frame-Breite / Texturbreite).
	-- Schild vertikal voll (0..1, CLAMP) wie bisher — die 40px-Textur ist keine Zweierpotenz,
	-- vertikales REPEAT zeigte eine Naht. Healabsorb (128px, Zweierpotenz) auch vertikal in
	-- fester Pixelgröße -> X-Muster wird nicht mehr gestreckt.
	local txW = L.width / STRIPE_TEX_W
	f.shieldStripe:SetTexCoord(0, txW, 0, 1)
	f.backfillStripe:SetTexCoord(0, txW, 0, 1)
	f.healStripe:SetTexCoord(0, txW, 0, L.height / HEALABS_TEX_H)

	if ns.Style then
		local t = d.healthTexture
		if t == "Lumen Gradient" then ns.Style:SetDepth(f.overlay, 1.0)
		elseif t == "Lumen Soft" then ns.Style:SetDepth(f.overlay, 0.55)
		else ns.Style:SetDepth(f.overlay, 0) end
	end
	f.name:SetShown(L.showName)
	applyText(f.name, f, L.namePoint, L.nameX, L.nameY, L.nameSize, L.nameColor, L.nameOutline)
	applyText(f.htext, f, L.healthTextPoint, L.healthTextX, L.healthTextY, L.healthTextSize, L.healthTextColor, L.healthTextOutline)
	f.eT:ClearAllPoints(); f.eT:SetPoint("TOPLEFT"); f.eT:SetPoint("TOPRIGHT"); f.eT:SetHeight(2)
	f.eB:ClearAllPoints(); f.eB:SetPoint("BOTTOMLEFT"); f.eB:SetPoint("BOTTOMRIGHT"); f.eB:SetHeight(2)
	f.eL:ClearAllPoints(); f.eL:SetPoint("TOPLEFT"); f.eL:SetPoint("BOTTOMLEFT"); f.eL:SetWidth(2)
	f.eR:ClearAllPoints(); f.eR:SetPoint("TOPRIGHT"); f.eR:SetPoint("BOTTOMRIGHT"); f.eR:SetWidth(2)

	-- Aura-Indikatoren layouten. Auto-Fit zieht die Icon-Größe aus L.height.
	if d.auras then
		for _, c in ipairs(AURA_CATS) do
			local cat  = d.auras[c.key]
			local size = (cat and auraIconSize(cat, L)) or 16
			layoutAuraCat(f, c.key, cat, size)
		end
	end
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
	-- Secure-Buttons NIE selbst Show/Hide (im Kampf verboten) -> der Header steuert ihre
	-- Sichtbarkeit. Nur die Nicht-Secure-Preview-Frames blenden wir selbst aus/ein.
	if not u or not UnitExists(u) then if not f._secure then f:Hide() end return end
	if not f._secure then f:Show() end
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
	local hasDispel, dr, dg, dbb
	if d.dispelEnabled then hasDispel, dr, dg, dbb = self:GetDispel(u, d) end
	if hasDispel and d.dispelMode == "recolor" then
		f.health:SetStatusBarColor(dr, dg, dbb)
	else
		f.health:SetStatusBarColor(fillRGB(d, class))
	end
	self:SetDispelOverlay(f, hasDispel and d.dispelMode == "overlay", dr, dg, dbb, d.dispelAlpha)

	local L = layoutCtx()
	if L.showName then f.name:SetText(UnitName(u) or "") end

	local t = L.healthTextType
	if t == "Keine" then
		f.htext:SetText("")
	elseif t == "Prozent" and _G.UnitHealthPercent then
		-- UnitHealthPercent liefert ohne ScaleTo100-Kurve eine 0..1-Fraktion (nicht secret)
		-- -> *100, sonst zeigt volles Leben "1%".
		local ok, p = pcall(UnitHealthPercent, u, true)
		f.htext:SetText(ok and p and format("%d%%", p * 100) or "")
	else
		local ok, str = pcall(AbbrevNum, UnitHealth(u))
		f.htext:SetText(ok and str or "")
	end

	self:RenderAurasLive(f)
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

	-- Testmodus: kein echtes Aura-Objekt -> Typ direkt auf konfigurierte Farbe mappen.
	local hasDispel, dr, dg, dbb = false
	if d.dispelEnabled and fk.dispel and (d.dispelShowAll or playerDispels[fk.dispel]) then
		dr, dg, dbb = dispelCol(d, fk.dispel)
		hasDispel = true
	end
	if hasDispel and d.dispelMode == "recolor" then
		f.health:SetStatusBarColor(dr, dg, dbb)
	else
		f.health:SetStatusBarColor(fillRGB(d, fk.class))
	end
	self:SetDispelOverlay(f, hasDispel and d.dispelMode == "overlay", dr, dg, dbb, d.dispelAlpha)

	local L = layoutCtx()
	if L.showName then f.name:SetText(fk.name) end

	local t = L.healthTextType
	if t == "Keine" then f.htext:SetText("")
	elseif t == "Prozent" then f.htext:SetText(floor(hp * 100) .. "%")
	else f.htext:SetText(AbbrevNum(floor(hp * FAKE_MAX))) end

	self:RenderAurasFake(f)
end

-- Aura-Icons befüllen — LIVE (secret-sicher: Filter-Scan, Swipe via Duration-Objekt).
-- Holder/Icons sind im Layout-Pfad vorab erzeugt; hier nur Textur/Swipe/Show setzen.
function Raidframes:RenderAurasLive(f)
	local u = f.unit
	local A = db().auras
	if not (A and u and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	learnUnitSigs(u)   -- passives Signatur-Lernen (außer Kampf; Groundwork für die Whitelist)
	local spec = currentSpecID()
	local wl   = whitelistFor(spec)   -- Whitelist der aktiven Spec (lazy geseedet)
	for _, c in ipairs(AURA_CATS) do
		local cat    = A[c.key]
		local holder = f.auraHolders and f.auraHolders[c.key]
		if cat and cat.enabled and holder then
			local maxN = cat.maxIcons or 5
			local fn   = C_UnitAuras.IsAuraFilteredOutByInstanceID
			local shown, i = 0, 1
			while shown < maxN do
				local aura = C_UnitAuras.GetAuraDataByIndex(u, i, c.filter)
				if not aura then break end
				i = i + 1
				local iid = aura.auraInstanceID
				-- Sub-Filter secret-sicher anwenden (nur Bool-Rückgabe, kein secret-Lesen).
				local subPass = true
				if c.subExclude or c.subInclude then
					if iid and fn then
						local out = fn(u, iid, c.subExclude or c.subInclude)
						subPass = (c.subExclude and out == true) or (not c.subExclude and out == false)
					else
						subPass = false
					end
				elseif c.harmfulModes then
					-- Debuffs: Blizzard-Standard-Filter (Alle/Raid-relevant/Dispellbar).
					subPass = debuffModeAccept(u, iid, cat.filterMode, fn)
				end
				-- Whitelist: welche Spells diese Kategorie zeigt. sid auch fuer das secret-freie Icon.
				--  * whitelistOr (Defensives, B3): Filter-Treffer (externe Def) ODER eigene "def"-
				--    Whitelist; eigene Auren vorab via isFromPlayerOrPlayerPet (12.0.5, nicht secret).
				--  * sonst (HoTs, B2): nur positiver Whitelist-Treffer zeigt (kein Filter-Fallback).
				local sid, accept
				if c.whitelist then
					if c.whitelistOr then
						if subPass then
							accept = true
						elseif aura.isFromPlayerOrPlayerPet then
							sid = resolveSpellId(u, aura, spec)
							accept = (wlType(wl, sid) == c.whitelist) or false
						else
							accept = false
						end
					elseif c.ownOnly and not aura.isFromPlayerOrPlayerPet then
						-- HoTs: nur eigene. Filter ist jetzt "HELPFUL" (zeigt auch Proc-/
						-- Talent-HoTs ohne PLAYER-Quell-Flag) -> Eigenheit hier separat prüfen.
						accept = false
					else
						-- HoTs (whitelist, kein Or): NUR zeigen, wenn die Aura positiv auf einen
						-- Whitelist-Spell aufgelöst wird. KEIN subPass-Fallback mehr — sonst rutschen
						-- im Kampf nicht auflösbare Eigenbuffs (Toys/Trinkets/Allgemeinbuffs, die
						-- Blizzard im Buffrahmen führt) durch, weil der Filter jetzt "HELPFUL" ist.
						sid = resolveSpellId(u, aura, spec)
						accept = (sid ~= nil and subPass and wlType(wl, sid) == c.whitelist) or false
					end
				else
					accept = subPass
				end
				if accept then
					shown = shown + 1
					local ic = holder.icons[shown]
					if ic then
						applyAuraIcon(ic, aura)
						if cat.showSwipe and ic.cd then
							local durObj = iid and C_UnitAuras.GetAuraDuration and C_UnitAuras.GetAuraDuration(u, iid)
							if durObj and ic.cd.SetCooldownFromDurationObject then
								pcall(ic.cd.SetCooldownFromDurationObject, ic.cd, durObj)
							else
								ic.cd:Clear()
							end
						end
						ic:Show()
					end
				end
			end
			positionAuraIcons(holder, shown)
			for j = shown + 1, #holder.icons do holder.icons[j]:Hide() end
		end
	end
end

-- Aura-Icons befüllen — TESTMODUS (Fake-HoTs mit Beispiel-Swipe; läuft out-of-combat).
function Raidframes:RenderAurasFake(f)
	local A = db().auras
	if not A then return end
	for _, c in ipairs(AURA_CATS) do
		local cat    = A[c.key]
		local holder = f.auraHolders and f.auraHolders[c.key]
		if cat and cat.enabled and holder then
			local n = min(cat.maxIcons or 5, 3)
			local fakeTex = c.fake or FAKE_HOTS
			for k = 1, n do
				local ic = holder.icons[k]
				if ic then
					ic.tex:SetTexture(fakeTex[((k - 1) % #fakeTex) + 1])
					if cat.showSwipe and ic.cd then
						ic.cd:SetCooldown(GetTime() - k * 1.5, 6 + k * 4)
					elseif ic.cd then
						ic.cd:Clear()
					end
					ic:Show()
				end
			end
			positionAuraIcons(holder, n)
			for k = n + 1, #holder.icons do holder.icons[k]:Hide() end
		end
	end
end

function Raidframes:UpdateUnit(f)
	if f.fake then return self:RenderFake(f) end
	return self:RenderLive(f)
end

-- ===========================================================================
--  PREVIEW / TEST  (Nicht-Secure-Frame-Pool, Fake-Daten) — eigenes SetPoint-Gitter.
--  Bleibt erhalten, damit Florians Screenshot-Schleife voll funktioniert.
-- ===========================================================================
function Raidframes:LayoutPreview(d)
	local L = layoutCtx()
	local w, h, sp = L.width, L.height, L.spacing
	local horizontal = (L.orientation == "horizontal")

	container:ClearAllPoints()
	container:SetPoint(L.point or "CENTER", UIParent, L.point or "CENTER", L.x or 0, L.y or 0)

	local list = GetFakeList(d.testSize or 5)
	local n = #list

	for i = 1, n do
		local f = frames[i] or CreateUnitFrame(i)
		f.fake = list[i]; f.unit = nil
		local idx   = i - 1
		local group = floor(idx / GROUP_SIZE)   -- welche 5er-Gruppe
		local slot  = idx % GROUP_SIZE          -- Position innerhalb der Gruppe
		-- vertical (Standard): Mitglieder untereinander (slot=Zeile), Gruppen nebeneinander (group=Spalte).
		-- horizontal: Mitglieder nebeneinander (slot=Spalte), Gruppen untereinander (group=Zeile).
		local col, row
		if horizontal then col, row = slot, group else col, row = group, slot end
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", container, "TOPLEFT", col * (w + sp), -row * (h + sp))
		self:ApplyConfig(f)
		self:UpdateUnit(f)
	end
	for i = n + 1, #frames do
		frames[i]:Hide(); frames[i].unit = nil; frames[i].fake = nil
	end

	local groups  = max(1, ceil(n / GROUP_SIZE))   -- Anzahl 5er-Gruppen
	local inGroup = max(1, min(n, GROUP_SIZE))      -- belegte Plätze pro Gruppe
	local cols, rows
	if horizontal then cols, rows = inGroup, groups else cols, rows = groups, inGroup end
	container:SetSize(max(1, cols * (w + sp) - sp), max(1, rows * (h + sp) - sp))
end

function Raidframes:HidePreview()
	for i = 1, #frames do
		frames[i]:Hide(); frames[i].unit = nil; frames[i].fake = nil
	end
end

-- ===========================================================================
--  LIVE  (SecureGroupHeader + SecureUnitButtons) — klickbar/targetbar (Phase 1).
-- ===========================================================================

-- Secure Rechtsklick-Menü (12.0.7): ein "togglemenu" direkt auf dem Unit-Button wird
-- gated (stumm verworfen ohne passende ClickBinding); aus Insecure-Lua öffnen TAINTET
-- das Menü (geschützte Einträge wie "Fokus setzen" werfen ADDON_ACTION_FORBIDDEN).
-- Lösung (Muster aus EllesmereUI): Rechtsklick über die UN-gated "click"-Action an einen
-- versteckten SecureActionButton-Proxy routen, der selbst "togglemenu" sicher ausführt.
-- "useparent-unit" -> der Proxy holt die Unit vom Eltern-Button (header-verwaltet).
local function getMenuProxy(button)
	local proxy = button._lumenMenuProxy
	if not proxy then
		proxy = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
		proxy:SetSize(1, 1); proxy:SetAlpha(0); proxy:EnableMouse(false)
		proxy:RegisterForClicks("AnyUp")
		proxy:SetAttribute("type", "togglemenu")
		for i = 1, 5 do proxy:SetAttribute("type" .. i, "togglemenu") end  -- per Button-Suffix aufgelöst
		proxy:SetAttribute("useparent-unit", true)
		proxy:SetAttribute("useOnKeyDown", false)
		button._lumenMenuProxy = proxy
	end
	return proxy
end
ns.RF_GetMenuProxy = getMenuProxy

-- Phase-1-Defaultklicks: Links=Ziel, Rechts=WoW-Menü (über Proxy). Wird beim Erstellen
-- gesetzt UND von ClickCast wiederhergestellt, wenn der Nutzer Click-Cast deaktiviert.
-- NUR außer Kampf aufrufen (Attribute setzen ist geschützt).
local function applyDefaultClicks(button)
	button:SetAttribute("type1", "target")
	button:SetAttribute("*type1", "target")
	button:SetAttribute("type2", nil)
	button:SetAttribute("*type2", "click")
	button:SetAttribute("*clickbutton2", getMenuProxy(button))
end
ns.RF_ApplyDefaultClicks = applyDefaultClicks

-- Einen vom Header erzeugten Secure-Button einmalig mit unserem Render-Stack + Klick-
-- Verhalten ausstatten. NUR außer Kampf aufrufen (Attribute setzen ist geschützt).
local function styleSecureButton(button)
	if button._lumenSecured then return end
	button._lumenSecured = true
	button._secure = true
	Decorate(button)
	-- Klick: Links=Ziel (unmodifiziert hat eine Default-ClickBinding), Rechts=Menü via Proxy.
	button:EnableMouse(true)
	button:RegisterForClicks("AnyUp")
	applyDefaultClicks(button)
	-- Maus-Highlight: HookScript (NICHT SetScript) -> die sicheren Header-Handler bleiben intakt.
	button:HookScript("OnEnter", function(self) Raidframes:SetHighlight(self, true) end)
	button:HookScript("OnLeave", function(self) Raidframes:SetHighlight(self, false) end)
	-- (Neu-)Zuweisung der Unit: zuverlässiges Per-Button-Signal -> Routing-Map + sofortiger Repaint.
	button:HookScript("OnAttributeChanged", function(self, name)
		if name ~= "unit" then return end
		local u = self:GetAttribute("unit")
		if u and UnitExists(u) then
			self.unit = u; self.fake = nil
			unitToButton[u] = self
			Raidframes:RenderLive(self)
		else
			self.unit = nil
		end
	end)
	-- Naht für späteres volles Click-Cast (Phase 2): hier dockt die Bindings-Engine an.
	if ns.CC_RegisterButton then ns.CC_RegisterButton(button) end
end

-- Header-Layout-Attribute aus dem aktiven Kontext (Orientierung + Abstand). NUR außer Kampf.
local function applyHeaderLayout()
	if not header then return end
	local L = layoutCtx()
	local sp = L.spacing or 2
	local horizontal = (L.orientation == "horizontal")
	-- Innerhalb der 5er-Gruppe wachsen die Mitglieder; perpendicular wachsen die Gruppen.
	local point, xOff, yOff, colAnchor
	if horizontal then
		point, xOff, yOff, colAnchor = "LEFT", sp, 0, "TOP"   -- Mitglieder nach rechts, Gruppen nach unten
	else
		point, xOff, yOff, colAnchor = "TOP", 0, -sp, "LEFT"  -- Mitglieder nach unten, Gruppen nach rechts
	end
	header:SetAttribute("point", point)
	header:SetAttribute("xOffset", xOff)
	header:SetAttribute("yOffset", yOff)
	header:SetAttribute("columnAnchorPoint", colAnchor)
	header:SetAttribute("columnSpacing", sp)
	header:SetAttribute("unitsPerColumn", GROUP_SIZE)
	header:SetAttribute("maxColumns", 8)

	container:ClearAllPoints()
	container:SetPoint(L.point or "CENTER", UIParent, L.point or "CENTER", L.x or 0, L.y or 0)
	header:ClearAllPoints()
	header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
end

-- Größe/Textur/Text auf alle (vorab erzeugten) Buttons anwenden + belegte rendern. NUR außer Kampf.
local function configureSecureButtons()
	if not header then return end
	for i = 1, 40 do
		local btn = header[i]
		if btn then
			Raidframes:ApplyConfig(btn)   -- setzt u.a. SetSize -> im Kampf verboten, hier OOC sicher
			-- Unit live vom Attribut lesen: Zuweisungen, die beim allerersten Header-Show
			-- VOR dem Anhängen der OnAttributeChanged-Hooks passierten, sonst erst beim
			-- nächsten Event sichtbar. Map + btn.unit hier nachziehen.
			local u = btn.unit or btn:GetAttribute("unit")
			if u and UnitExists(u) then
				btn.unit = u; unitToButton[u] = btn
				Raidframes:RenderLive(btn)
			end
		end
	end
end

-- Header einmalig bauen + 40 Buttons vorab erzeugen (startingIndex-Trick) und dekorieren.
local function buildHeader()
	if header then return end
	local L = layoutCtx()
	local bw, bh = L.width or 114, L.height or 60
	header = CreateFrame("Frame", "LumenRaidHeader", container, "SecureGroupHeaderTemplate")
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("templateType", "Button")
	-- initialConfigFunction läuft im Restricted-Env beim Button-Erzeugen -> nur Größe setzen.
	header:SetAttribute("initialConfigFunction", ([[
		self:SetWidth(%d)
		self:SetHeight(%d)
	]]):format(bw, bh))
	header:SetAttribute("showRaid", true)
	header:SetAttribute("showParty", true)
	header:SetAttribute("showPlayer", true)
	header:SetAttribute("showSolo", true)   -- solo sieht man den eigenen Frame (gut zum Live-Testen)
	header:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
	header:SetAttribute("sortMethod", "INDEX")
	applyHeaderLayout()

	header:SetAttribute("startingIndex", -39)
	header:Show()
	header:SetAttribute("startingIndex", 1)
	for i = 1, 40 do
		local btn = header[i]
		if btn then styleSecureButton(btn) end
	end
end

function Raidframes:LayoutLive()
	if InCombatLockdown() then secureLayoutDirty = true; return end
	if not header then buildHeader() end
	applyHeaderLayout()
	-- Buttongröße geändert (z.B. Kontextwechsel Raid<->Party)? Dann den Header zur
	-- Neuanordnung zwingen (Hide/Show) -> sonst rechnet er mit der alten Größe weiter.
	local L = layoutCtx()
	local sizeChanged = (header._appliedW ~= L.width or header._appliedH ~= L.height)
	header._appliedW, header._appliedH = L.width, L.height
	configureSecureButtons()   -- ApplyConfig setzt u.a. die Buttongröße
	if sizeChanged and header:IsShown() then
		header:Hide(); header:Show()
	else
		header:Show()
	end
end

function Raidframes:HideHeader()
	if not header then return end
	if InCombatLockdown() then secureLayoutDirty = true; return end
	header:Hide()
end

-- Nur die Aura-Indikatoren neu layouten + rendern (Anker/Wachstum/Größe/Toggles).
-- KAMPF-SICHER: Holder/Icons sind eigene, NICHT-geschützte Frames auf dem Overlay
-- (kein Secure-Template, keine Button-Größe) -> SetPoint/SetSize/CreateFrame darauf
-- sind auch im Kampf erlaubt. Deshalb hier KEIN InCombatLockdown-Defer wie in
-- LayoutLive (das wegen des Secure-Headers abbricht) -> Aura-Einstellungen greifen
-- sofort, auch auf der Zielpuppe im Kampf.
function Raidframes:RefreshAuras()
	if not container then return end
	local d = db()
	if not d.auras then return end
	local L = layoutCtx()
	local function relayout(f)
		if not f.auraHolders then return end
		for _, c in ipairs(AURA_CATS) do
			local cat  = d.auras[c.key]
			local size = (cat and auraIconSize(cat, L)) or 16
			layoutAuraCat(f, c.key, cat, size)
		end
	end
	if d.testMode then
		for i = 1, #frames do
			local f = frames[i]
			if f and f:IsShown() then relayout(f); self:RenderAurasFake(f) end
		end
	elseif header then
		for i = 1, 40 do
			local b = header[i]
			if b and b._lumenSecured and b.unit and UnitExists(b.unit) then
				relayout(b); self:RenderAurasLive(b)
			end
		end
	end
end

-- Dispatcher: Test -> Preview-Frames, sonst -> Secure-Header. Immer nur eine Seite sichtbar.
function Raidframes:UpdateLayout()
	if not container then return end
	dispelCurve = nil   -- Dispel-Farben könnten sich geändert haben -> Curve neu bauen lassen
	local d = db()
	if d.testMode then
		self:HideHeader()
		self:LayoutPreview(d)
	else
		self:HidePreview()
		self:LayoutLive()
	end
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
	local f = unitToButton[unit]
	if f and f:IsShown() then Raidframes:RenderLive(f) end
end

function Raidframes:Setup()
	if container then return end
	container = CreateFrame("Frame", "LumenRaidContainer", UIParent)
	container:SetSize(200, 200)
	container:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
	container:RegisterEvent("PLAYER_ENTERING_WORLD")
	container:RegisterEvent("GROUP_ROSTER_UPDATE")
	container:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	container:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Kampfende -> aufgeschobenes Layout nachholen
	for _, ev in ipairs(UNIT_EVENTS) do container:RegisterEvent(ev) end
	container:SetScript("OnEvent", function(_, event, unit)
		if isUnitEvent(event) then
			OnUnitEvent(unit)
		elseif event == "PLAYER_REGEN_ENABLED" then
			if secureLayoutDirty then
				secureLayoutDirty = false
				Raidframes:UpdateLayout()
			end
		else
			-- Spec-Wechsel: Signaturen sind spec-scoped -> Skip-Cache leeren (neu lernen).
			if event == "PLAYER_SPECIALIZATION_CHANGED" then wipe(learnedIID) end
			local _, class = UnitClass("player")
			playerDispels = CLASS_DISPELS[class] or {}
			Raidframes:UpdateLayout()
		end
	end)
	local _, class = UnitClass("player")
	playerDispels = CLASS_DISPELS[class] or {}

	if ns.EditMode then
		ns.EditMode:Register(container, "Raidframes", function(p, x, y)
			-- Position in den AKTIVEN Kontext (raid/party) speichern.
			local L = layoutCtx(); L.point, L.x, L.y = p, x, y
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
	-- Container ist Elternframe des Secure-Headers -> Hide im Kampf wäre an geschützten
	-- Kindern verboten. Im Kampf aufschieben (greift bei RefreshAll/Regen erneut).
	if InCombatLockdown() then secureLayoutDirty = true; return end
	if header then header:Hide() end
	container:Hide()
end
