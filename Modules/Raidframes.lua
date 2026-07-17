local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Module: Raidframes (v0.9 — secret-safe, secret-safe 12.0 pattern)
--
--  Confirmed secret-safe 12.0 approach:
--   * maxHealth ALWAYS from calc:GetMaximumHealth() — UnitHealthMax is secret.
--   * Raw values (UnitHealth/UnitGetTotalAbsorbs/...HealAbsorbs/...IncomingHeals)
--     directly to StatusBar:SetValue() — the bar tolerates secret.
--   * Positioning via CLIP FRAMES anchored to the health fill texture.
--     The clips do the math -> never compare secret values.
--
--  Layers:  health | (in the missing area) prediction -> shield
--                  | (in the filled area, from the right) heal-absorb
-- ===========================================================================

local Raidframes = {}
ns.Raidframes = Raidframes

local CreateFrame, UIParent = CreateFrame, UIParent
local InCombatLockdown = InCombatLockdown
local UnitExists, UnitHealth, UnitHealthMax = UnitExists, UnitHealth, UnitHealthMax
local UnitName, UnitClass = UnitName, UnitClass
local UnitThreatSituation = UnitThreatSituation
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction
local UnitHealthPercent = UnitHealthPercent
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local GetReadyCheckStatus = GetReadyCheckStatus
local C_IncomingSummon = C_IncomingSummon
local CurveConstants = CurveConstants
local IsInRaid = IsInRaid
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local strfind, format = string.find, string.format
local pcall = pcall
local GetTime = GetTime
local issecretvalue = issecretvalue or function() return false end

local WHITE8X8 = "Interface\\Buttons\\WHITE8X8"
local AbbrevNum = _G.AbbreviateNumbersAlt or _G.AbbreviateNumbers or tostring

-- Built from the real addon-folder name (ADDON) so the path survives a folder rename.
local T = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local SHIELD_OVL_TEX = T .. "blizzard-shield"      -- 256x40, opaque, diagonal stripes + shading
local HEALABS_TEX    = T .. "blizzard-absorb.png"  -- 256x128, semi-transparent, heal-absorb pattern
local STRIPE_TEX_W   = 256                          -- texture width of both stripe textures (for TexCoord tiling)
local HEALABS_TEX_H  = 128                           -- blizzard-absorb: 256x128 (vertically tileable, power of two)
-- Shield/heal-absorb texture choice: these pattern keys = the tiled Lumen pattern (fixed
-- pixel size, secret/clip-safe as before). ANY other choice (LSM/Blizzard statusbar) is
-- stretched as a smooth fill over the absorb area. The clips stay untouched.
local SHIELD_PATTERN  = "Lumen Schild"
local HEALABS_PATTERN = "Lumen Heilabsorb"
-- Shield/heal-absorb textures. Render spec per entry: pattern = tiled Lumen stripe pattern
-- (default, unchanged look). Own Lumen shield textures come later (Florian) -> just extend
-- here. (Blizzard's shield consists of several atlases + edges and is only assembled
-- correctly later.) Additionally, LibSharedMedia textures from other addons are added
-- (see *TextureValues + resolveTexSpec) -> those are stretched as a smooth fill.
local SHIELD_TEX_SPEC  = { [SHIELD_PATTERN]  = { pattern = true } }
local HEALABS_TEX_SPEC = { [HEALABS_PATTERN] = { pattern = true } }
-- Resolver: known key -> its spec; LSM/file key -> pooled {texKey} fill (no garbage
-- per relayout); nil -> pattern default.
local fillSpecCache = {}
local function resolveTexSpec(key, specTable, patternKey)
	if not key then return specTable[patternKey] end
	local s = specTable[key]; if s then return s end
	local fs = fillSpecCache[key]; if not fs then fs = { texKey = key }; fillSpecCache[key] = fs end
	return fs
end

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
-- Default dispel colors (fallback when the user hasn't set their own).
local DISPEL_DEFAULTS = {
	Magic   = { r = 0.20, g = 0.60, b = 1.00 },
	Curse   = { r = 0.64, g = 0.19, b = 0.79 },
	Disease = { r = 0.55, g = 0.41, b = 0.18 },
	Poison  = { r = 0.12, g = 0.69, b = 0.29 },
}
-- Blizzard dispel-type enum indices (for the color curve): 1 Magic, 2 Curse, 3 Disease, 4 Poison.
local C_UnitAuras = C_UnitAuras

local TEXTURES = {
	-- Aurora / Glow = flat class-color fill (WHITE8X8); the look comes from the
	-- additive glow layer in Style.lua, so the base fill stays plain class color.
	["Lumen Aurora"]   = WHITE8X8,
	["Lumen Glow"]     = WHITE8X8,
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
-- Shield/heal-absorb dropdown: the tiled Lumen pattern first + all statusbar textures
-- (Lumen/Blizzard/LSM) usable as a smooth fill.
-- Shield/heal-absorb dropdown = Lumen entries + all LibSharedMedia statusbar textures
-- (other addons) -> "people have more". Deliberately WITHOUT Lumen's health-bar gradients.
local function withLSM(t)
	local LSM = getLSM()
	if LSM then for _, n in ipairs(LSM:List("statusbar")) do t[n] = n end end
	return t
end
function Raidframes:ShieldTextureValues()
	local t = {}; for k in pairs(SHIELD_TEX_SPEC) do t[k] = k end; return withLSM(t)
end
function Raidframes:HealAbsorbTextureValues()
	local t = {}; for k in pairs(HEALABS_TEX_SPEC) do t[k] = k end; return withLSM(t)
end

-- Heal-prediction calculator (12.0). One, fed per unit.
-- Provides maxHealth secret-safely (UnitHealthMax would be secret in combat).
local calc
local function getCalc()
	if calc == nil then
		if _G.CreateUnitHealPredictionCalculator then
			calc = CreateUnitHealPredictionCalculator()
			-- Configure ONCE here, not per render (the mode never changes).
			if calc.SetMaximumHealthMode and Enum and Enum.UnitMaximumHealthMode then
				calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
			end
		else
			calc = false
		end
	end
	return calc or nil
end

-- Sample roster (test mode)
local FAKE_MAX = 600000
local FAKE = {
	{ name = "Owlday",     class = "DRUID",   hp = 0.84, aggro = 3, role = "HEALER", lead = true },
	{ name = "Elyndra",    class = "MAGE",    hp = 0.90, absorb = 0.25, role = "DAMAGER" },
	{ name = "Zakhar",     class = "WARLOCK", hp = 0.62, dispel = "Curse", role = "DAMAGER" },
	{ name = "Briar",      class = "PALADIN", hp = 0.55, dispel = "Poison", role = "TANK" },
	{ name = "Tormund",    class = "SHAMAN",  hp = 0.60, absorb = 0.22, aggro = 1, role = "DAMAGER" },
	{ name = "Kaelura",    class = "PRIEST",  hp = 0.77, healAbsorb = 0.20, role = "HEALER" },
	{ name = "Nighthollow",class = "ROGUE",   hp = 0.43, dispel = "Magic", role = "DAMAGER" },
	{ name = "Sylfaria",   class = "MONK",    hp = 0.55, predict = 0.25, role = "HEALER" },
	{ name = "Grimoak",    class = "WARRIOR", hp = 1.00, healAbsorb = 0.35, role = "TANK" },
	{ name = "Velisara",   class = "EVOKER",  hp = 0.71, dispel = "Disease", role = "HEALER" },
	{ name = "Ravynne",    class = "HUNTER",  hp = 0.95, absorb = 0.10, role = "DAMAGER" },
	{ name = "Stormhelm",  class = "DEATHKNIGHT", hp = 0.66, predict = 0.20, role = "TANK" },
	{ name = "Brightwing", class = "PALADIN", hp = 0.50, predict = 0.30, role = "HEALER" },
	{ name = "Embertide",  class = "MAGE",    hp = 0.50, dispel = "Curse", role = "DAMAGER" },
	{ name = "Drelvar",    class = "DEMONHUNTER", hp = 0.80, healAbsorb = 0.30, role = "DAMAGER" },
	{ name = "Solveig",    class = "PRIEST",  hp = 0.40, healAbsorb = 0.25, role = "DAMAGER" },
	{ name = "Zulkhar",    class = "SHAMAN",  hp = 0.58, dispel = "Poison", role = "DAMAGER" },
	{ name = "Fenwick",    class = "HUNTER",  hp = 1.00, absorb = 0.30, role = "DAMAGER" },
	{ name = "Morgath",    class = "WARRIOR", hp = 0.72, predict = 0.15, role = "DAMAGER" },
	{ name = "Aldris",     class = "DRUID",   hp = 0.45, absorb = 0.15, role = "DAMAGER" },
}

local GROUP_SIZE = 5   -- fixed group size: raid groups & dungeon group are always 5 (never mixed)
local DEFAULT_ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }   -- fallback priority list

-- Fake icon textures for test mode (preview without real auras), matching each category.
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
-- Major raid cooldowns (Bloodlust / Barrier / Tranquility / Aura Mastery) so the
-- preview reads as big CDs, not HoTs (Florian 2026-07-16).
local FAKE_MAJOR = {
	"Interface\\Icons\\Spell_Nature_BloodLust",
	"Interface\\Icons\\Spell_Holy_PowerWordBarrier",
	"Interface\\Icons\\Spell_Nature_Tranquility",
	"Interface\\Icons\\Spell_Holy_AuraMastery",
}

-- Aura indicators: category registry. filter = Blizzard aura filter for GetAuraDataByIndex
-- (secret-safe). subExclude/subInclude refine secret-safely via IsAuraFilteredOutByInstanceID:
--   subExclude -> only auras this sub-filter EXCLUDES (e.g. "not from me" = foreign).
--   subInclude -> only auras this sub-filter INCLUDES (e.g. external defensives).
-- "PLAYER" = self-cast, "EXTERNAL_DEFENSIVE" = Blizzard's curated external defensives.
-- Stage A (v0.9.11): the "RAID" filter = only raid-relevant helpful auras
-- (HoTs/shields) -> food/flask/general buffs drop out. Secret-safe and also usable for
-- foreign auras (stage B = exact signature whitelist only for OWN HoTs).
local AURA_CATS = {
	{ key = "hotsOwn",    filter = "HELPFUL", whitelist = "hot", ownOnly = true,     fake = FAKE_HOTS },
	{ key = "defensives", filter = "HELPFUL", subInclude = "HELPFUL|EXTERNAL_DEFENSIVE", whitelist = "def", whitelistOr = true, fake = FAKE_DEFENSIVE },
	{ key = "major",      filter = "HELPFUL", whitelist = "major", ownOnly = true,   fake = FAKE_MAJOR },
	{ key = "debuffs",    filter = "HARMFUL", harmfulModes = true,                  fake = FAKE_DEBUFF },
}
-- Debuff filter modes (Blizzard standard): "raid" = Blizzard's curated raid-relevant
-- debuffs (HARMFUL|RAID resp. RAID_IN_COMBAT), "dispellable" = only self-dispellable,
-- "all" = all. Secret-safe via IsAuraFilteredOutByInstanceID (only bool).
local function debuffModeAccept(u, iid, mode, fn)
	if mode == "none" then return false end
	if mode == "all" then return true end
	if not (fn and iid) then return true end   -- can't filter -> rather show
	if mode == "dispellable" then
		return not fn(u, iid, "HARMFUL|RAID_PLAYER_DISPELLABLE")
	end
	-- "raid" (default, Blizzard-relevant) + fallback
	return (not fn(u, iid, "HARMFUL|RAID")) or (not fn(u, iid, "HARMFUL|RAID_IN_COMBAT"))
end

-- ---- Aura signature learning (phase 2 / stage B1) ---------------------------
-- 4-filter fingerprint (RAID, RAID_IN_COMBAT, EXTERNAL_DEFENSIVE, RAID_PLAYER_DISPELLABLE;
-- all PLAYER|HELPFUL) -> identifies ONLY self-cast auras. We LEARN the mapping
-- signature->spellID ourselves (out of combat, spellId readable) and persist in
-- db.global.auraSigs[specID] -> in combat (spellId secret) look up by signature.
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
	-- Nothing distinctive (food/flask/general buffs pass none of the four filters) -> out.
	-- (B3: ext/dsp move BEFORE the early-out so that own defensives which aren't
	-- RAID but are EXTERNAL_DEFENSIVE/dispellable become learnable too.)
	if not (r or ric or ext or dsp) then return nil end
	return (r and "1" or "0") .. ":" .. (ric and "1" or "0") .. ":" .. (ext and "1" or "0") .. ":" .. (dsp and "1" or "0")
end
-- Already-fingerprinted aura instances -> compute each instance only ONCE. Keeps the
-- OOC steady-state cost effectively at a pure aura scan. Cleared on spec change.
local learnedIID = {}
-- Learn passively: ONLY out of combat (in combat zero cost -> early early-out), scan
-- the own auras on u, remember new signature->spellID. Called once per UNIT_AURA of the unit.
local function learnUnitSigs(u)
	if InCombatLockdown() then return end           -- hot path in combat: a single check
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
			learnedIID[iid] = true                  -- only fingerprint new instances
			local sid = aura.spellId
			if sid and not issecretvalue(sid) then
				local sig = auraSig(u, iid)
				if sig and not s[sig] then s[sig] = sid end
			end
		end
	end
end

-- ---- HoT/defensive whitelist (phase 2 / stage B2+B3) -----------------------
-- Curated standard spells per healer spec (spellID), compiled independently.
-- Seeded lazily into db.profile.raidframes.auras.whitelist[specID] (HoTs type "hot",
-- defensives type "def"). Adjustable per spec in the whitelist editor (B4).
local HOT_DEFAULTS = {
	[105]  = { 774, 8936, 33763, 155777, 48438, 439530 },          -- Resto Druid: Rejuv, Regrowth, Lifebloom, Germination, Wild Growth, Symbiotic Blooms
	[256]  = { 17, 194384, 1253593, 41635 },                       -- Disc Priest: PW:Shield, Atonement, Void Shield, PoM
	[257]  = { 139, 77489, 41635 },                                -- Holy Priest: Renew, Echo of Light, PoM
	[270]  = { 119611, 124682, 115175, 450769 },                   -- MW Monk: Renewing/Enveloping/Soothing Mist, Aspect of Harmony
	[264]  = { 61295, 974, 382024, 207400, 444490 },               -- Resto Shaman: Riptide, Earth Shield, Earthliving, Ancestral Vigor, Hydrobubble
	[65]   = { 156910, 156322, 53563, 1244893, 200025, 431381 },   -- Holy Pala: Beacon of Faith, Eternal Flame, Beacon of Light, Beacon of Savior, Beacon of Virtue, Dawnlight
	[1468] = { 364343, 366155, 367364, 355941, 376788, 363502, 373267 }, -- Pres Evoker: Echo, Reversion, Echo Reversion, Dream Breath, Echo Dream Breath, Dream Flight, Lifebind
}
-- specID -> classToken. For the class-wide defensive defaults (DEF_CLASS) and
-- B4-capable (independent of the live class).
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
-- Defensives (type "def"). External (cast on others) -> learnable via signature, combat icon
-- clean. Personal self-CDs appear only on the OWN frame and (for now) only out of combat,
-- when they pass NONE of the four signature filters (spellId secret); reliable for all in
-- combat would come later via cast events (UNIT_SPELLCAST_SUCCEEDED). Good defaults
-- out-of-the-box for EVERY class/spec (anti-bloat: usable without customizing), adjustable
-- per spec in the B4 editor. spellIds checked/to be checked live — report missing/wrong -> fix here.
-- DEF_CLASS = class-wide defensives (all specs of the class), DEF_DEFAULTS = spec-specific.
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
local MAJOR_DEFAULTS = {
	[65]   = { 31884 },       -- Holy Paladin: Avenging Wrath (Wings)
	[105]  = { 102558, 29166 },-- Resto Druid: Incarnation: Tree of Life, Innervate
	[256]  = { 10060, 246287 },-- Disc Priest: Power Infusion, Evangelism
	[257]  = { 10060, 265202 },-- Holy Priest: Power Infusion, Divine Hymn
	[270]  = { 322118, 325197 },-- MW Monk: Invoke Yu'lon, Invoke Chi-Ji
	[264]  = { 114052, 16191 }, -- Resto Shaman: Ascendance, Mana Tide Totem
	[1468] = { 375087 },      -- Pres Evoker: Dragonrage
}

local container
local header                 -- SecureGroupHeader (live path)
local secureLayoutDirty = false   -- layout deferred in combat? -> catch up on PLAYER_REGEN_ENABLED
local playerDispels = {}
local unitToButton = {}      -- live routing: unit -> secure button (the shell preview doesn't route)

local function db() return ns.Lumen.db.profile.raidframes end

-- Get the whitelist of the active spec; merge in defaults (HoT/Def) lazily.
-- Lives in the profile (partly/resettable). NOT in the core defaults -> the first write
-- creates a real profile-owned table (no mutating the shared defaults).
-- whitelistSeeded[spec][spellID]=true remembers already-OFFERED defaults: this way real
-- additions (e.g. new def defaults in an update, or an old B2 profile with only HoTs)
-- get added without re-adding spells the user (B4) deliberately removed.
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
	ensure(DEF_CLASS[SPEC_CLASS[spec]], "def")   -- class-wide defensives
	ensure(MAJOR_DEFAULTS[spec], "major")
	return s
end

-- Hot-path view of whitelistFor: the seeding loops above run once per spec, not
-- on every UNIT_AURA render. The cache holds a REFERENCE to the live profile
-- table (editor add/remove mutate that same table -> stays correct); it only
-- needs invalidating when the table itself could be replaced: spec change and
-- profile switch/import (wlInvalidate below, called from the event handler and
-- UpdateLayout).
local wlCache, wlCacheSpec
local function wlInvalidate() wlCacheSpec = nil end
local function whitelistCached(spec)
	if spec ~= wlCacheSpec then
		wlCacheSpec, wlCache = spec, whitelistFor(spec)
	end
	return wlCache
end

-- Talent -> aura remap (tracking editor). Some talents are offered in the dropdown
-- with their TALENT spellId (from C_Traits), but on proc create a buff with a DIFFERENT
-- aura spellId -> the talent ID then never matches an aura.
-- Map to the real aura ID here so "Add" works reliably.
--  * 155675 (talent "Germination") -> 155777 (aura "Rejuvenation (Germination)")
local TALENT_TO_AURA = {
	[155675] = 155777,
}
-- Public: normalize a tracked/offered spellId to the aura ID that actually appears
-- (for add + dropdown dedupe in options).
function Raidframes:ResolveTrackId(spellID)
	return (spellID and TALENT_TO_AURA[spellID]) or spellID
end

-- ---------------------------------------------------------------------------
--  Whitelist editor (B4, options tab "Tracking") — public API.
--  Works on db().auras.whitelist[specID] (spellID -> "hot"|"def"); seeds the
--  spec lazily via whitelistFor. Pure OOC operations (no hot path).
-- ---------------------------------------------------------------------------
-- Entries of a type ("hot"|"def") of a spec as {id,name,icon}, alphabetical.
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
-- Raw map {spellID = "hot"|"def"} of a spec (for the picker dedupe: hide already-tracked
-- spells from the selection dropdown). Seeds the spec lazily.
function Raidframes:WhitelistMap(specID)
	if not specID or specID == 0 then return {} end
	return whitelistFor(specID) or {}
end
-- Add a spell to the whitelist.
function Raidframes:AddWhitelist(specID, spellID, typ)
	if not specID or specID == 0 or not spellID then return end
	spellID = TALENT_TO_AURA[spellID] or spellID   -- talent ID -> real aura ID
	local s = whitelistFor(specID); if not s then return end
	s[spellID] = typ
	self:RefreshAuras()
end
-- Remove a spell. The seeded marker stays set deliberately -> a default-seeded spell
-- does NOT come back on its own (a deliberate removal persists).
function Raidframes:RemoveWhitelist(specID, spellID)
	if not specID or specID == 0 or not spellID then return end
	local A = db().auras; if not A or not A.whitelist then return end
	local s = A.whitelist[specID]; if not s then return end
	s[spellID] = nil
	self:RefreshAuras()
end
-- Reset to the curated defaults of this type: first remove all entries of the type
-- (including user-added ones), then re-add the defaults DIRECTLY and mark them as
-- seeded. Unconditionally (no seed guard) -> brings back ALL defaults.
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
	elseif typ == "major" then
		restore(MAJOR_DEFAULTS[specID])
	else
		restore(DEF_DEFAULTS[specID])
		restore(DEF_CLASS[SPEC_CLASS[specID]])
	end
	self:RefreshAuras()
end
-- Determine a spellId of an aura — secret-safe:
--   * out of combat aura.spellId is directly readable.
--   * in combat it is secret -> look up via the (out-of-combat learned) signature.
-- Returns nil = not (yet) resolvable (e.g. in combat before the first OOC learning).
-- Some auras are applied with a DIFFERENT spellId than the tracked one
-- (cast ID != aura ID). Map here to the main ID listed in the whitelist.
-- (Example: Earth Shield — cast ID differs from the aura ID.)
local PRIMARY_BY_ALT = {
	[383648] = 974,   -- Earth Shield (alternative aura ID -> main ID)
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

-- Whitelist type of a spellId: directly OR via the base spell (GetBaseSpell) so that
-- talent/rank-modified override IDs match the tracked base spell.
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

-- Set an aura's icon. aura.icon is secret in combat (12.0), but StatusBar/texture
-- setters accept secret values NATIVELY and render them correctly — confirmed approach
-- (a SECRET texture is accepted natively by SetTexture). This gives real icons
-- even in combat, for OWN and FOREIGN auras (crucial for debuffs). Only if no icon
-- is present at all (nil) the cog fallback.
local function applyAuraIcon(ic, aura)
	local tex = aura.icon
	if tex ~= nil then ic.tex:SetTexture(tex) else ic.tex:SetTexture(136243) end
end

-- Active layout/position context: raid vs. 5-man group/dungeon (party).
-- previewCtx: set ONLY while the shell preview fills its frames — forces the
-- context ("raid"/"party") so the band renders the tab's context regardless of
-- the group state. Always cleared right after the (synchronous) fill.
local previewCtx
local function layoutCtx()
	local d = db()
	if previewCtx then return d[previewCtx] end
	return IsInRaid() and d.raid or d.party
end

local function classColor(class)
	local c = RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

-- Aggro context active? With aggroInstanceOnly (default) only in dungeon/raid —
-- otherwise the overlay would be on almost permanently solo/open world. instanceType is
-- not secret, safely readable in combat.
local function aggroContextActive(d)
	if not d.aggroInstanceOnly then return true end
	local _, it = IsInInstance()
	return it == "party" or it == "raid"
end

-- Tank? Primarily the assigned group role. If NONE is assigned ("NONE"/nil —
-- e.g. solo or group without a role check), fall back to the spec role for the
-- PLAYER themselves (otherwise e.g. a Guardian druid shows the aggro overlay solo).
-- For foreign units without an assigned role only the group role remains.
local function unitIsTank(u)
	local r = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
	if r == "TANK" then return true end
	if r and r ~= "NONE" then return false end
	if UnitIsUnit and UnitIsUnit(u, "player") then
		local spec = GetSpecialization and GetSpecialization()
		if spec and GetSpecializationRole then
			return GetSpecializationRole(spec) == "TANK"
		end
	end
	return false
end
-- Configured dispel color (or default) for a type.
local function dispelCol(d, key)
	local c = (d.dispelColors and d.dispelColors[key]) or DISPEL_DEFAULTS[key]
	return c.r or 0.5, c.g or 0.5, c.b or 0.5
end
-- Base color of the health bar: class color or fixed fill color (NO dispel logic anymore).
local function fillRGB(d, class)
	if d.useClassColor then return classColor(class) end
	local c = d.fillColor or {}
	return c.r or 0.2, c.g or 0.6, c.b or 0.3
end

-- Dispel color curve (12.0): Blizzard evaluates the (secret) dispel type internally
-- against the curve and returns the color -> type-accurate in combat, without reading
-- the secret value. Built lazily and invalidated on settings changes (see UpdateLayout).
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
	pt(c, 0, "Magic")   -- none/fallback
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
-- Font outline: stored value -> WoW SetFont flag. "shadow" = no engine outline, a
-- soft drop shadow instead (cleaner than the chunky OUTLINE flag on our font).
-- NOTE (12.0.7): FontString:SetShadowColor/SetShadowOffset called at RUNTIME no
-- longer render a shadow. The shadow must be INHERITED from a FontObject via
-- SetFontObject *before* SetFont (the inherited shadow survives the SetFont
-- typeface/size call). One shared font object per shadow strength.
local OUTLINE_FLAGS = { none = "", shadow = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local SHADOW_FONTS
local function shadowFonts()
	if SHADOW_FONTS then return SHADOW_FONTS end
	local function mk(name, a)
		local o = CreateFont("LumenText" .. name)
		o:SetFont(STANDARD_TEXT_FONT, 12, "")
		o:SetShadowColor(0, 0, 0, a)
		o:SetShadowOffset(a > 0 and 1 or 0, a > 0 and -1 or 0)
		return o
	end
	-- full soft shadow for "shadow"; a faint one GROUNDS the outline modes; none = none.
	local faint = mk("Faint", 0.4)
	SHADOW_FONTS = { none = mk("None", 0), shadow = mk("Soft", 0.6), outline = faint, thick = faint }
	return SHADOW_FONTS
end
local function applyText(fs, frame, point, x, y, size, color, outline)
	point = point or "CENTER"
	local sf = shadowFonts()
	fs:SetFontObject(sf[outline] or sf.none)   -- inherit shadow BEFORE SetFont (12.0.7)
	fs:SetFont(STANDARD_TEXT_FONT, max(6, size or 12), OUTLINE_FLAGS[outline] or "")
	fs:ClearAllPoints()
	local ix, iy = pointInset(point, x, y)
	fs:SetPoint(point, frame, point, ix, iy)
	fs:SetJustifyH(justifyFor(point))
	if color then fs:SetTextColor(color.r or 1, color.g or 1, color.b or 1) end
end

local function GetFakeList(size)
	local list = {}
	for i = 1, size do list[i] = FAKE[((i - 1) % #FAKE) + 1] end
	-- Test-mode preview of role sorting: stably sort into buckets by the priority list
	-- (within a role the order is preserved). Live this is done by the SecureGroupHeader
	-- via groupBy=ASSIGNEDROLE — here only the visual preview.
	local d = db()
	if d.sortMode == "role" and (size == 5 or d.sortApplyRaid) then
		local order = d.sortRoleOrder or DEFAULT_ROLE_ORDER
		local rank = {}
		for i, r in ipairs(order) do rank[r] = i end
		local buckets = {}
		local n = #order + 1   -- last bucket = without/unknown role
		for i = 1, n do buckets[i] = {} end
		for i = 1, #list do
			local b = buckets[rank[list[i].role] or n]
			b[#b + 1] = list[i]
		end
		local out = {}
		for rk = 1, n do
			local b = buckets[rk]
			for j = 1, #b do out[#out + 1] = b[j] end
		end
		list = out
	end
	return list
end

-- Reused scratch color (no table per call in the hot path).
local dispelScratch = { r = 1, g = 1, b = 1 }

-- Secret-safe dispel detection (12.0):
--  * filter "HARMFUL|RAID_PLAYER_DISPELLABLE" -> Blizzard returns only what I can dispel
--    (internally in C++, no Lua compare on secret). "All" -> "HARMFUL" + nil check.
--  * dispelName ~= nil is a secret-safe nil check (doesn't read the value) and says
--    WHETHER a (typed) dispellable debuff is present — even for secret boss debuffs.
--  * color via GetAuraDispelTypeColor + curve: Blizzard evaluates the secret type internally
--    and returns the color -> type-accurate in combat, without reading the secret value.
-- Returns: hasDispel(bool, secret-free), r, g, b (possibly secret -> only to C++ setters).
function Raidframes:GetDispel(u, d)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false end
	if not dispelCurve then buildDispelCurve() end
	local filter = d.dispelShowAll and "HARMFUL" or "HARMFUL|RAID_PLAYER_DISPELLABLE"
	local i = 1
	while true do
		local aura = C_UnitAuras.GetAuraDataByIndex(u, i, filter)
		if not aura then break end
		i = i + 1
		if aura.dispelName ~= nil then   -- secret-safe
			if dispelCurve and C_UnitAuras.GetAuraDispelTypeColor then
				local col = C_UnitAuras.GetAuraDispelTypeColor(u, aura.auraInstanceID, dispelCurve)
				if col then
					local sc = dispelScratch
					sc.r, sc.g, sc.b = col:GetRGB()
					return true, sc.r, sc.g, sc.b
				end
			end
			-- Fallback (API missing): generic magic color as a "dispellable" hint.
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

-- Stripe overlay in a clip frame — MANUAL TexCoord tiling (Blizzard's real method),
-- secret-safe. Background: SetHorizTile does NOT tile correctly over a StatusBar fill
-- (it stretches the texture), and a MaskTexture doesn't follow the fill. Therefore:
--  * The stripe texture is spanned over the WHOLE frame (spanFrame = f.health) and tiled
--    via TexCoord at FIXED pixel size (REPEAT horizontal; TexCoord in ApplyConfig).
--    Same origin for forward + backfill -> the diagonal runs seamlessly across the edge.
--  * clipParent is a clip frame anchored to the absorb FILL and thus follows the SetValue
--    secret-safely (like missClip/curClip follow the health fill) -> the stripe appears
--    ONLY over the actual absorb portion.
-- vTile=true -> also tile VERTICALLY at fixed pixel size (only clean for power-of-two heights
-- like the 128px heal-absorb texture). vTile=false -> vertical CLAMP (shield: 256x40, NOT a
-- power of two -> REPEAT showed a seam; CLAMP stretches the diagonal but isn't noticeable).
-- ApplyConfig sets the TexCoord factor (frame size / texture size).
local function makeStripe(clipParent, spanFrame, stripeTex, vTile)
	local s = clipParent:CreateTexture(nil, "ARTWORK", nil, 2)
	s:SetTexture(stripeTex, "REPEAT", vTile and "REPEAT" or "CLAMP")
	s:SetAllPoints(spanFrame)
	return s
end
-- Set the stripe texture in ApplyConfig. patternKey -> tiled Lumen pattern (REPEAT, fixed
-- pixel size as before; vCoord/vRepeat control the vertical tiling). Any other choice ->
-- stretched as a smooth fill (CLAMP, 0..1) -> any LSM/Blizzard statusbar usable. The clip
-- limits to the absorb portion in both cases (unchanged).
local function applyStripeTex(stripe, spec, patternTex, L, vCoord, vRepeat)
	if not spec or spec.pattern then
		stripe:SetTexture(patternTex, "REPEAT", vRepeat and "REPEAT" or "CLAMP")
		stripe:SetTexCoord(0, L.width / STRIPE_TEX_W, 0, vCoord)
	elseif spec.atlas then
		stripe:SetTexCoord(0, 1, 0, 1)          -- SetAtlas sets its own coords; reset first
		pcall(stripe.SetAtlas, stripe, spec.atlas, false)
	else
		stripe:SetTexture(FetchTexture(spec.texKey or ""))
		stripe:SetTexCoord(0, 1, 0, 1)
	end
end

-- ----- Aura indicators (phase 1): icon pool, anchor, auto-fit size -----
-- Which context determines the explicit icon size (auto-fit off)? raid vs party.
local function isRaidContext()
	if previewCtx then return previewCtx == "raid" end
	return IsInRaid()
end
-- Suffix of the context-dependent aura fields (anchorRaid/anchorParty, growRaid/…, sizeRaid/…,
-- offX/offY, outside) — position/size are separate per context (like frame size/text).
local function auraCtxSuffix() return isRaidContext() and "Raid" or "Party" end
-- Icon size of a category: auto-fit -> derived from the frame height (so it scales
-- automatically between raid/group), otherwise explicit per context.
local function auraIconSize(cat, L)
	local sfx = auraCtxSuffix()
	if not cat["autoFit" .. sfx] then
		return cat["size" .. sfx] or (sfx == "Raid" and 16 or 22)
	end
	-- Auto-fit: ~30% of the frame height, BUT capped so the full row/column fits into
	-- the frame (no overflow past the edge on narrow/short frames):
	-- cap horizontal growth at the width, vertical at the height.
	local h, w = L.height or 60, L.width or 114
	local n  = max(1, cat["maxIcons" .. sfx] or 5)
	local sp = cat["spacing" .. sfx] or 0
	local size = h * 0.30
	local grow = cat["grow" .. sfx] or "RIGHT"
	if grow == "UP" or grow == "DOWN" then
		size = min(size, (h - sp * (n - 1)) / n)
	else
		size = min(size, (w - sp * (n - 1)) / n)
	end
	return max(8, min(48, floor(size)))
end
-- Small inward offset so icons don't stick to the frame edge.
local function auraInset(point)
	local I, x, y = 1, 0, 0
	if strfind(point, "LEFT") then x = I elseif strfind(point, "RIGHT") then x = -I end
	if strfind(point, "TOP") then y = -I elseif strfind(point, "BOTTOM") then y = I end
	return x, y
end
-- Positions the VISIBLE icons (count of them) along the growth direction. If the anchor
-- is centered on the growth axis (e.g. "Bottom"/"Center"), the row is CENTERED — based
-- on the actual count, so it stays centered even with a changing HoT count.
-- Runs at render time (count is only known then).
local AURA_OUT_GAP = 2 -- small gap between frame edge and the outsourced ("outside") icon row
local function positionAuraIcons(holder, count)
	if count < 1 then holder._posCount = 0; return end
	-- Avoid SetPoint churn (§9.5): icon positions depend ONLY on count + the layout
	-- parameters (anchor/growth/size/offset). The parameters change exclusively in
	-- layoutAuraCat (which invalidates _posCount there). If count stays the same,
	-- nothing needs re-anchoring -> the frequent UNIT_AURA path saves the work.
	if count == holder._posCount then return end
	local anchor = holder._anchor or "BOTTOMLEFT"
	local grow   = holder._grow or "RIGHT"
	local size   = holder._size or 16
	local step   = size + (holder._spacing or 0)
	local dirX, dirY = 0, 0
	if grow == "RIGHT" then dirX = 1 elseif grow == "LEFT" then dirX = -1
	elseif grow == "UP" then dirY = 1 elseif grow == "DOWN" then dirY = -1 end
	local horiz = (dirX ~= 0)
	local centerX = horiz and not (strfind(anchor, "LEFT") or strfind(anchor, "RIGHT"))
	local centerY = (not horiz) and not (strfind(anchor, "TOP") or strfind(anchor, "BOTTOM"))
	-- Base offset: "inside" = small inset inward (doesn't stick to the edge);
	-- "outside" = the row sits entirely BEYOND the anchored edge (perpendicular to the
	-- growth axis) -> next to/above/below the frame, without extra frames.
	local bx, by
	if holder._outside then
		bx, by = 0, 0
		if horiz then
			if strfind(anchor, "TOP") then by = size + AURA_OUT_GAP
			elseif strfind(anchor, "BOTTOM") then by = -(size + AURA_OUT_GAP) end
		else
			if strfind(anchor, "LEFT") then bx = -(size + AURA_OUT_GAP)
			elseif strfind(anchor, "RIGHT") then bx = size + AURA_OUT_GAP end
		end
	else
		bx, by = auraInset(anchor)
	end
	local ox, oy = holder._offX or 0, holder._offY or 0 -- freely chosen X/Y offset (both modes)
	local sx = centerX and (-dirX * (count - 1) * step / 2) or 0
	local sy = centerY and (-dirY * (count - 1) * step / 2) or 0
	for i = 1, count do
		local ic = holder.icons[i]
		if ic then
			ic:ClearAllPoints()
			ic:SetPoint(anchor, holder, anchor, bx + ox + sx + (i - 1) * dirX * step, by + oy + sy + (i - 1) * dirY * step)
		end
	end
	holder._posCount = count
end
local function makeAuraIcon(holder)
	local ic = CreateFrame("Frame", nil, holder)
	ic.bg = ic:CreateTexture(nil, "BACKGROUND")
	ic.bg:SetAllPoints()
	ic.bg:SetColorTexture(0, 0, 0, 1)            -- 1px black frame
	ic.tex = ic:CreateTexture(nil, "ARTWORK")
	ic.tex:SetPoint("TOPLEFT", 1, -1)
	ic.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- cut off the default icon border
	ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
	ic.cd:SetAllPoints(ic.tex)
	ic.cd:SetDrawEdge(false)
	ic.cd:SetHideCountdownNumbers(true)
	ic:Hide()
	return ic
end
-- Layout a category block: position holder + icon pool at anchor/size/growth direction.
-- Filling (texture/swipe/show) happens only at render time. Call ONLY in the layout path
-- (may create frames -> out of combat).
local function layoutAuraCat(f, key, cat, size)
	local holder = f.auraHolders[key]
	-- All display knobs are per context (raid/party) since Feature 1.
	local sfx = auraCtxSuffix()
	if not (cat and cat["enabled" .. sfx]) then
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
	-- Remember layout parameters for the render-time positioning (positionAuraIcons).
	holder._anchor  = cat["anchor" .. sfx] or "BOTTOMLEFT"
	holder._grow    = cat["grow" .. sfx] or "RIGHT"
	holder._offX    = cat["offX" .. sfx] or 0
	holder._offY    = cat["offY" .. sfx] or 0
	holder._outside = cat["outside" .. sfx] or false
	holder._size    = size
	holder._spacing = cat["spacing" .. sfx] or 0
	holder._posCount = nil   -- layout params reset -> discard position cache
	local showSwipe = cat["showSwipe" .. sfx]
	local maxN = cat["maxIcons" .. sfx] or 5
	for i = 1, maxN do
		local ic = holder.icons[i] or makeAuraIcon(holder)
		holder.icons[i] = ic
		ic:SetSize(size, size)
		if showSwipe then ic.cd:Show() else ic.cd:Hide() end
		ic:Hide()
	end
	for i = maxN + 1, #holder.icons do holder.icons[i]:Hide() end
end

-- Decorates an arbitrary host (non-secure frame for preview OR secure button for live)
-- with the complete render stack (bg, health, clips, shields, heal-absorb, overlay, texts,
-- dispel/mouse borders). Does NOT create the host and sets NO mouse/click scripts — that
-- is host-specific (preview: SetScript; secure: HookScript).
-- This way the live and test paths share exactly one render code.
local function Decorate(f)
	local base = f:GetFrameLevel()

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.11, 0.11, 0.11, 1)

	-- Health bar (base; its fill texture drives the clips)
	f.health = makeBar(f, WHITE8X8, base + 2)
	f.health:SetAllPoints(f)
	local hpTex = f.health:GetStatusBarTexture()

	-- ----- Missing area (right of the current health): prediction + shield -----
	f.missClip = CreateFrame("Frame", nil, f.health)
	f.missClip:SetFrameLevel(base + 3)
	f.missClip:SetClipsChildren(true)
	f.missClip:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", -1, 0)
	f.missClip:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", 0, 0)

	f.predictBar = makeBar(f.missClip, WHITE8X8, base + 3)
	f.predictBar:SetStatusBarColor(0.30, 0.85, 0.40, 0.55)
	f.predictBar:SetPoint("TOPLEFT", hpTex, "TOPRIGHT", 0, 0)
	f.predictBar:SetPoint("BOTTOMLEFT", hpTex, "BOTTOMRIGHT", 0, 0)

	-- Shield FORWARD: from the health edge into the free space on the right. The INVISIBLE
	-- StatusBar fill only drives the geometry (SetValue=absorb, secret-safe); the shieldClip
	-- is anchored to its fill and limits the stripe overlay exactly to the absorb portion.
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

	-- Shield BACKFILL: overshield over filled health (reverse fill from the right). curClip
	-- limits to the FILLED area; the backfillClip (anchored to the backfill fill) limits to
	-- the absorb portion. Forward + backfill share the same raw absorb -> the clips do
	-- min(absorb,health) resp. max(0,absorb-health) purely visually.
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

	-- ----- Filled area (over the current health): heal-absorb from the right -----
	f.healClip = CreateFrame("Frame", nil, f.health)
	f.healClip:SetFrameLevel(base + 5)
	f.healClip:SetClipsChildren(true)
	f.healClip:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, 0)
	f.healClip:SetPoint("BOTTOMRIGHT", hpTex, "BOTTOMRIGHT", 0, 0)

	-- Heal-absorb: invisible fill drives the geometry, healAbsClip limits the
	-- (semi-transparent) pattern overlay to the heal-absorb portion.
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

	-- ----- Depth / aurora glow: own frame ABOVE the health fill but BELOW the
	-- game-state absorb layers (prediction/shield/heal-absorb, base+3..+5). The
	-- additive, class-tinted aurora must NOT wash over the absorb overlays -- an
	-- overshield or heal-absorb sitting over filled health would otherwise pick up
	-- the glow and look see-through (see Style.lua: depth sits below game state).
	-- Child of f.health -> always drawn above its fill texture.
	f.depth = CreateFrame("Frame", nil, f.health)
	f.depth:SetAllPoints(f.health)
	f.depth:SetFrameLevel(base + 2)
	if ns.Style then ns.Style:ApplyBar(f.health, f.depth) end

	-- ----- Overlay (texts, dispel, mouse border) -----
	f.overlay = CreateFrame("Frame", nil, f)
	f.overlay:SetAllPoints()
	f.overlay:SetFrameLevel(base + 6)

	f.auraHolders = {}   -- [catKey] = holder frame with icon pool (lazy in ApplyConfig)

	f.name = f.overlay:CreateFontString(nil, "OVERLAY")
	f.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
	f.name:SetPoint("TOPLEFT", 4, -3)
	f.htext = f.overlay:CreateFontString(nil, "OVERLAY")
	f.htext:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
	f.htext:SetPoint("CENTER")

	-- Status layer: center text (Offline/Dead/Ghost/Rez — replaces the HP text
	-- while shown) + center icon (ready check / incoming summon).
	f.stext = f.overlay:CreateFontString(nil, "OVERLAY")
	f.stext:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	f.stext:SetPoint("CENTER")
	f.stext:Hide()
	f.statusIcon = f.overlay:CreateTexture(nil, "OVERLAY", nil, 3)
	f.statusIcon:SetSize(20, 20)
	f.statusIcon:SetPoint("CENTER")
	f.statusIcon:Hide()

	-- Dispel overlay (mode "overlay"): colored border + light fill in the dispel color.
	-- White textures -> color via SetVertexColor (tolerates secret values).
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
		-- brand gold (palette C1 #E9BB69 — kept literal: combat-path file, no Shell coupling)
		t:SetColorTexture(0.91, 0.73, 0.41, 1); t:Hide(); return t
	end
	f.eT, f.eB, f.eL, f.eR = edge(), edge(), edge(), edge()

	-- Aggro warning: a complete own layer with a clearly higher frame level ABOVE the
	-- aura holders (which are children of f.overlay) so that overlay fill, border AND
	-- "Aggro" text sit above the aura icons. White textures -> color via SetVertexColor.
	f.aggroLayer = CreateFrame("Frame", nil, f)
	f.aggroLayer:SetAllPoints(f)
	f.aggroLayer:SetFrameLevel(base + 10)
	f.aggroFill = f.aggroLayer:CreateTexture(nil, "ARTWORK")
	f.aggroFill:SetColorTexture(1, 1, 1, 1); f.aggroFill:SetAllPoints(f.health); f.aggroFill:Hide()
	local function aedge()
		local t = f.aggroLayer:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(1, 1, 1, 1); t:Hide(); return t
	end
	f.aT, f.aB, f.aL, f.aR = aedge(), aedge(), aedge(), aedge()
	f.aT:SetPoint("TOPLEFT"); f.aT:SetPoint("TOPRIGHT"); f.aT:SetHeight(2)
	f.aB:SetPoint("BOTTOMLEFT"); f.aB:SetPoint("BOTTOMRIGHT"); f.aB:SetHeight(2)
	f.aL:SetPoint("TOPLEFT"); f.aL:SetPoint("BOTTOMLEFT"); f.aL:SetWidth(2)
	f.aR:SetPoint("TOPRIGHT"); f.aR:SetPoint("BOTTOMRIGHT"); f.aR:SetWidth(2)
	f.aggroText = f.aggroLayer:CreateFontString(nil, "OVERLAY")
	f.aggroText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	f.aggroText:SetText(ns.T("Aggro")); f.aggroText:Hide()

	-- Indicator icons: role (Blizzard LFG atlases) + leader/assistant crown.
	-- Own layer ABOVE the aggro layer — the icons stay readable even while
	-- the aggro overlay/border is up. Anchored/sized per context in
	-- ApplyConfig, filled in the render pass.
	f.iconLayer = CreateFrame("Frame", nil, f)
	f.iconLayer:SetAllPoints(f)
	f.iconLayer:SetFrameLevel(base + 11)
	f.roleIcon = f.iconLayer:CreateTexture(nil, "OVERLAY")
	f.roleIcon:Hide()
	f.leadIcon = f.iconLayer:CreateTexture(nil, "OVERLAY")
	f.leadIcon:Hide()
end

function Raidframes:SetHighlight(f, on)
	f.eT:SetShown(on); f.eB:SetShown(on); f.eL:SetShown(on); f.eR:SetShown(on)
end

-- Set dispel overlay (mode "overlay"): border + fill in the dispel color on/off.
-- r,g,b may be secret -> only pass to SetVertexColor (C++).
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

-- Set aggro warning. status = Blizzard's UnitThreatSituation (nil/0 = off, 1-2 = yellow
-- "aggro incoming", 3 = red "has aggro"). Display PER STAGE: "border" (border only) or
-- "overlay" (border + fill); text only in overlay mode + own toggle per stage.
-- Threat values are NOT secret -> compare/show in combat allowed.
function Raidframes:SetAggro(f, status)
	if not status or status == 0 then
		f.aT:Hide(); f.aB:Hide(); f.aL:Hide(); f.aR:Hide()
		f.aggroFill:Hide(); f.aggroText:Hide()
		return
	end
	local d = db()
	local isAggro = status >= 3
	local c      = isAggro and d.aggroColorAggro or d.aggroColorWarn
	local mode   = isAggro and d.aggroModeAggro  or d.aggroModeWarn
	local textOn = isAggro and d.aggroTextAggro  or d.aggroTextWarn
	local r, g, b = c.r, c.g, c.b
	-- Border always (both modes contain it).
	f.aT:SetVertexColor(r, g, b, 1); f.aT:Show()
	f.aB:SetVertexColor(r, g, b, 1); f.aB:Show()
	f.aL:SetVertexColor(r, g, b, 1); f.aL:Show()
	f.aR:SetVertexColor(r, g, b, 1); f.aR:Show()
	-- Fill + text only in overlay mode; text additionally per stage toggle.
	if mode == "overlay" then
		f.aggroFill:SetVertexColor(r, g, b, d.aggroFillAlpha or 0.22); f.aggroFill:Show()
		if textOn then f.aggroText:SetTextColor(r, g, b, 1); f.aggroText:Show() else f.aggroText:Hide() end
	else
		f.aggroFill:Hide(); f.aggroText:Hide()
	end
end

function Raidframes:ApplyConfig(f)
	local d = db()
	local L = layoutCtx()
	f:SetSize(L.width, L.height)
	f.health:SetStatusBarTexture(FetchTexture(d.healthTexture))
	-- Keep segment bars at health size (anchors provide height/position)
	f.predictBar:SetSize(L.width, L.height)
	f.shieldBar:SetSize(L.width, L.height)
	f.healAbsorbBar:SetSize(L.width, L.height)

	-- Tile stripe overlays horizontally at FIXED pixel size (frame width / texture width).
	-- Shield vertically full (0..1, CLAMP) as before — the 40px texture is not a power of two,
	-- vertical REPEAT showed a seam. Heal-absorb (128px, power of two) also vertically at
	-- fixed pixel size -> the X pattern is no longer stretched.
	-- Shield (forward + backfill) + heal-absorb: Lumen pattern tiled OR chosen texture
	-- stretched (see applyStripeTex). Clips stay untouched.
	local sSpec = resolveTexSpec(d.shieldTexture, SHIELD_TEX_SPEC, SHIELD_PATTERN)
	applyStripeTex(f.shieldStripe,   sSpec, SHIELD_OVL_TEX, L, 1, false)
	applyStripeTex(f.backfillStripe, sSpec, SHIELD_OVL_TEX, L, 1, false)
	applyStripeTex(f.healStripe, resolveTexSpec(d.healAbsorbTexture, HEALABS_TEX_SPEC, HEALABS_PATTERN), HEALABS_TEX, L, L.height / HEALABS_TEX_H, true)

	if ns.Style then
		local t = d.healthTexture
		if t == "Lumen Aurora" then
			ns.Style:SetDepth(f.depth, 0)
			ns.Style:SetAurora(f.depth, true, d.auroraStrength or 1, ns.Style.auroraTexture, nil)
		elseif t == "Lumen Glow" then
			ns.Style:SetDepth(f.depth, 0)
			ns.Style:SetAurora(f.depth, true, d.auroraStrength or 1, ns.Style.glowTexture, nil)
		elseif t == "Lumen Gradient" then
			ns.Style:SetAurora(f.depth, false); ns.Style:SetDepth(f.depth, 1.0)
		elseif t == "Lumen Soft" then
			ns.Style:SetAurora(f.depth, false); ns.Style:SetDepth(f.depth, 0.55)
		else
			ns.Style:SetAurora(f.depth, false); ns.Style:SetDepth(f.depth, 0)
		end
	end
	-- Background color + opacity (shared). The health-bar opacity is NOT set here:
	-- f.health:SetAlpha would propagate to the clip children (shield/heal-absorb/prediction).
	-- Instead at render time as the alpha argument of SetStatusBarColor.
	local bg = d.bgColor or {}
	f.bg:SetColorTexture(bg.r or 0.11, bg.g or 0.11, bg.b or 0.11, d.bgAlpha or 1)
	-- Opacity of the absorb overlays (shield = forward+backfill stripe, heal-absorb = stripe).
	local sa = d.shieldAlpha or 1
	f.shieldStripe:SetAlpha(sa); f.backfillStripe:SetAlpha(sa)
	f.healStripe:SetAlpha(d.healAbsorbAlpha or 1)

	-- Color + outline are SHARED (d), size/position/show per context (L).
	f.name:SetShown(L.showName)
	applyText(f.name, f, L.namePoint, L.nameX, L.nameY, L.nameSize, d.nameColor, d.nameOutline)
	applyText(f.htext, f, L.healthTextPoint, L.healthTextX, L.healthTextY, L.healthTextSize, d.healthTextColor, d.healthTextOutline)
	-- Status text mirrors the HP-text style (shared Base look); position fixed center.
	applyText(f.stext, f, "CENTER", 0, 0, L.healthTextSize, d.healthTextColor, d.healthTextOutline)
		applyText(f.aggroText, f, d.aggroTextPoint, d.aggroTextX, d.aggroTextY, d.aggroTextSize, nil, d.aggroTextOutline)

	-- Indicator icons: anchor/size per context (visibility is render business).
	f.roleIcon:ClearAllPoints()
	f.roleIcon:SetPoint(L.rolePoint or "TOPRIGHT", f, L.rolePoint or "TOPRIGHT", L.roleX or 0, L.roleY or 0)
	f.roleIcon:SetSize(L.roleSize or 14, L.roleSize or 14)
	f.leadIcon:ClearAllPoints()
	f.leadIcon:SetPoint(L.leadPoint or "TOPLEFT", f, L.leadPoint or "TOPLEFT", L.leadX or 0, L.leadY or 0)
	f.leadIcon:SetSize(L.leadSize or 12, L.leadSize or 12)
	f.eT:ClearAllPoints(); f.eT:SetPoint("TOPLEFT"); f.eT:SetPoint("TOPRIGHT"); f.eT:SetHeight(2)
	f.eB:ClearAllPoints(); f.eB:SetPoint("BOTTOMLEFT"); f.eB:SetPoint("BOTTOMRIGHT"); f.eB:SetHeight(2)
	f.eL:ClearAllPoints(); f.eL:SetPoint("TOPLEFT"); f.eL:SetPoint("BOTTOMLEFT"); f.eL:SetWidth(2)
	f.eR:ClearAllPoints(); f.eR:SetPoint("TOPRIGHT"); f.eR:SetPoint("BOTTOMRIGHT"); f.eR:SetWidth(2)

	-- Layout aura indicators. Auto-fit derives the icon size from L.height.
	if d.auras then
		for _, c in ipairs(AURA_CATS) do
			local cat  = d.auras[c.key]
			local size = (cat and auraIconSize(cat, L)) or 16
			layoutAuraCat(f, c.key, cat, size)
		end
	end
end

-- All bars share the scale 0..maxH. Values may be secret; 0 -> invisible.
local function setSegments(f, maxH, healthVal, incoming, absorb, healAbsorb)
	f.health:SetMinMaxValues(0, maxH);        f.health:SetValue(healthVal)
	f.predictBar:SetMinMaxValues(0, maxH);    f.predictBar:SetValue(incoming or 0)
	f.shieldBar:SetMinMaxValues(0, maxH);     f.shieldBar:SetValue(absorb or 0)
	f.backfillBar:SetMinMaxValues(0, maxH);   f.backfillBar:SetValue(absorb or 0)
	f.healAbsorbBar:SetMinMaxValues(0, maxH); f.healAbsorbBar:SetValue(healAbsorb or 0)
end

-- LIVE — secret-safe (calculator only for maxHealth, raw values to the bars).
--
-- PERF (audit 2026-07-03): the render is SPLIT BY EVENT TYPE. Before, every
-- unit event ran the full pipeline — a single UNIT_HEALTH tick re-scanned all
-- auras (dispel + 4 indicator categories) across the whole raid. Now:
--   * health-ish events -> RenderHealth (bars + health color + HP text)
--   * UNIT_AURA         -> RenderDispelAuras (dispel scan + aura icons)
--   * threat event      -> RenderAggro
--   * RenderLive        -> full pass (unit assignment, roster, layout)
-- The dispel result is CACHED on the frame (f._dOn + rgb) so health ticks can
-- recolor without re-scanning auras. The cached rgb may be SECRET — stored
-- untouched and only ever passed back into C++ setters (no Lua ops on it).
-- Bright class colors clip the ADDITIVE aurora toward white (the curtain structure
-- washes out). Dampen the glow tint by perceptual luminance: Druid-orange (~0.59 =
-- Florian's sweet spot) and darker classes stay full; brighter classes (yellow /
-- green / white) are progressively reduced. Ref 0.60 keeps Druid unchanged.
local function auroraDamp(r, g, b)
	local L = 0.299 * r + 0.587 * g + 0.114 * b
	if L <= 0.60 then return 1 end
	local k = 1 - (L - 0.60)
	return k < 0.5 and 0.5 or k
end

local function applyHealthColor(f, d, u)
	local ha = d.healthAlpha or 1   -- dim only the health-bar fill (4th alpha arg)
	if f._greyed then
		-- Dead/offline: neutral grey bar + glow (the status layer owns this flag).
		f.health:SetStatusBarColor(0.35, 0.35, 0.35, ha)
		if ns.Style then ns.Style:SetAuroraColor(f.depth, 0.30, 0.30, 0.30) end
		return
	end
	if f._dOn and d.dispelMode == "recolor" then
		local r, g, b = f._dR, f._dG, f._dB     -- may be SECRET -> only to C++ setters, no math
		f.health:SetStatusBarColor(r, g, b, ha)
		if ns.Style then ns.Style:SetAuroraColor(f.depth, r, g, b) end
	else
		local _, class = UnitClass(u)
		local r, g, b = fillRGB(d, class)
		f.health:SetStatusBarColor(r, g, b, ha)
		-- Tint the aurora glow to match the bar (no-op unless the aurora texture is on).
		if ns.Style then
			local k = auroraDamp(r, g, b)
			ns.Style:SetAuroraColor(f.depth, r * k, g * k, b * k)
		end
	end
end

-- Health-ish events: segment bars + health color (from the dispel cache) + HP text.
function Raidframes:RenderHealth(f)
	local u = f.unit
	if not u or not UnitExists(u) then return end
	local d = db()

	local maxH
	local c = getCalc()
	if c and UnitGetDetailedHealPrediction then
		pcall(UnitGetDetailedHealPrediction, u, nil, c)
		maxH = c:GetMaximumHealth()
	end
	maxH = maxH or UnitHealthMax(u)

	local incoming = (d.healPrediction and UnitGetIncomingHeals and UnitGetIncomingHeals(u)) or 0
	local absorb   = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(u)) or 0
	local healAbs  = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(u)) or 0
	setSegments(f, maxH, UnitHealth(u), incoming, absorb, healAbs)

	self:RenderStatus(f) -- death/alive + offline transitions ride on health events
	applyHealthColor(f, d, u)

	local L = layoutCtx()
	local t = L.healthTextType
	if t == "Keine" then
		f.htext:SetText("")
	elseif t == "Prozent" and UnitHealthPercent then
		-- ScaleTo100 curve -> guaranteed NON-secret 0..100 (secret-safe 12.0 pattern).
		-- IMPORTANT: without the curve 12.0.7 returns a value that throws on arithmetic
		-- (p*100) in combat. With the curve p is already 0..100 and non-secret,
		-- format is safe (no arithmetic outside). pcall per guide recommendation.
		local curve = CurveConstants and CurveConstants.ScaleTo100
		local ok, p = pcall(UnitHealthPercent, u, true, curve)
		f.htext:SetText((ok and p) and format("%d%%", p) or "")
	else
		-- AbbreviateNumbers accepts a secret number and returns a non-secret string
		-- (official 12.0 formatter); pcall only as a belt for exotic clients.
		local ok, str = pcall(AbbrevNum, UnitHealth(u))
		f.htext:SetText(ok and str or "")
	end
end

-- UNIT_AURA: dispel scan (result cached on the frame) + recolor + aura icons.
function Raidframes:RenderDispelAuras(f)
	local u = f.unit
	if not u or not UnitExists(u) then return end
	local d = db()

	local hasDispel, dr, dg, dbb
	if d.dispelEnabled then hasDispel, dr, dg, dbb = self:GetDispel(u, d) end
	f._dOn, f._dR, f._dG, f._dB = hasDispel or false, dr, dg, dbb
	applyHealthColor(f, d, u)
	self:SetDispelOverlay(f, hasDispel and d.dispelMode == "overlay", dr, dg, dbb, d.dispelAlpha)

	self:RenderAurasLive(f)
end

-- UNIT_THREAT_SITUATION_UPDATE: aggro warning only.
function Raidframes:RenderAggro(f)
	local u = f.unit
	if not u or not UnitExists(u) then return end
	local d = db()
	if d.aggroEnabled and aggroContextActive(d) then
		-- Exclude tanks: they're supposed to have aggro -> no permanent red.
		local st = (not unitIsTank(u)) and UnitThreatSituation and UnitThreatSituation(u) or nil
		self:SetAggro(f, st)
	else
		self:SetAggro(f, nil)
	end
end

-- Unit status: Offline > Rez (incoming resurrection while dead) > Ghost/Dead.
-- UnitIsConnected/UnitIsDeadOrGhost return CLEAN booleans for group units in
-- 12.0 (only UnitIsAFK can be secret) -> safe in plain conditionals. Cached
-- as f._statusMode so health ticks don't re-write identical text; the grey
-- repaint runs only on an actual transition.
function Raidframes:RenderStatus(f)
	local u = f.unit
	if not u or not UnitExists(u) then return end
	local mode
	if UnitIsConnected and not UnitIsConnected(u) then
		mode = "offline"
	elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost(u) then
		if UnitHasIncomingResurrection and UnitHasIncomingResurrection(u) then
			mode = "rez"
		elseif UnitIsGhost and UnitIsGhost(u) then
			mode = "ghost"
		else
			mode = "dead"
		end
	end
	if mode == f._statusMode then return end
	f._statusMode = mode
	if mode then
		f.stext:SetText(mode == "offline" and ns.T("Offline")
			or mode == "rez" and ns.T("Rez")
			or mode == "ghost" and ns.T("Ghost") or ns.T("Dead"))
		f.stext:Show()
		f.htext:Hide()
	else
		f.stext:Hide()
		f.htext:Show()
	end
	-- Grey the bar while dead/offline; dim the whole frame only when offline.
	f._greyed = (mode ~= nil) or nil
	f:SetAlpha(mode == "offline" and 0.55 or 1)
	applyHealthColor(f, db(), u)
end

-- Center icon: ready check (priority) + incoming summon — Blizzard's own
-- icons/atlases (instantly familiar under pressure). ONE shared texture; the
-- two barely ever overlap. Ready-check results linger a few seconds after the
-- check finishes so you can see WHO wasn't ready ("waiting" counts as not
-- ready then — same rule as the Blizzard frames).
local READY_TEX = {
	ready    = "Interface\\RaidFrame\\ReadyCheck-Ready",
	notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
	waiting  = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local SUMMON_ATLAS = Enum.SummonStatus and {
	[Enum.SummonStatus.Pending]  = "RaidFrame-Icon-SummonPending",
	[Enum.SummonStatus.Accepted] = "RaidFrame-Icon-SummonAccepted",
	[Enum.SummonStatus.Declined] = "RaidFrame-Icon-SummonDeclined",
} or {}
local READY_LINGER = 6
local readyCheckActive, readyCheckFinished = false, false

function Raidframes:RenderCenterIcon(f)
	local u = f.unit
	if not u or not UnitExists(u) then return end
	local d = db()
	local tex = f.statusIcon
	if d.showReadyCheck and readyCheckActive and GetReadyCheckStatus then
		local s = GetReadyCheckStatus(u)
		if readyCheckFinished and s == "waiting" then s = "notready" end
		if s and READY_TEX[s] then
			tex:SetTexCoord(0, 1, 0, 1) -- reset a possible previous SetAtlas
			tex:SetTexture(READY_TEX[s])
			tex:Show()
			return
		end
	end
	if d.showSummon and C_IncomingSummon and C_IncomingSummon.HasIncomingSummon(u) then
		local atlas = SUMMON_ATLAS[C_IncomingSummon.IncomingSummonStatus(u)]
		if atlas then tex:SetAtlas(atlas); tex:Show(); return end
	end
	tex:Hide()
end

function Raidframes:RefreshCenterIcons()
	if not header then return end
	for i = 1, 40 do
		local b = header[i]
		if b and b._lumenSecured and b.unit and UnitExists(b.unit) then
			self:RenderCenterIcon(b)
		end
	end
end

function Raidframes:OnReadyCheck(event)
	if event == "READY_CHECK" then
		readyCheckActive, readyCheckFinished = true, false
	elseif event == "READY_CHECK_FINISHED" then
		readyCheckFinished = true
		C_Timer.After(READY_LINGER, function()
			readyCheckActive, readyCheckFinished = false, false
			Raidframes:RefreshCenterIcons()
		end)
	end
	self:RefreshCenterIcons()
end

-- Indicator icons: role (LFG atlases, like the group finder) + leader/
-- assistant crown. Shared by the live and fake render paths; role/leader
-- flags are NOT secret (safe to branch on in combat).
local ROLE_ATLAS = {
	TANK    = "UI-LFG-RoleIcon-Tank",
	HEALER  = "UI-LFG-RoleIcon-Healer",
	DAMAGER = "UI-LFG-RoleIcon-DPS",
}
local LEAD_TEX   = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ASSIST_TEX = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local function setIndicators(f, role, isLead, isAssist)
	local L = layoutCtx()
	if L.roleShow and ROLE_ATLAS[role] and not (L.roleHideDps and role == "DAMAGER") then
		f.roleIcon:SetAtlas(ROLE_ATLAS[role])
		f.roleIcon:Show()
	else
		f.roleIcon:Hide()
	end
	if L.leadShow and (isLead or isAssist) then
		f.leadIcon:SetTexture(isLead and LEAD_TEX or ASSIST_TEX)
		f.leadIcon:Show()
	else
		f.leadIcon:Hide()
	end
end

-- Leadership/role changes: light repaint of just the indicator icons on the
-- visible live buttons (rare events; texture set/show is combat-safe).
function Raidframes:RefreshIndicators()
	if not header then return end
	for i = 1, 40 do
		local b = header[i]
		if b and b._lumenSecured and b.unit and UnitExists(b.unit) then
			setIndicators(b, UnitGroupRolesAssigned and UnitGroupRolesAssigned(b.unit),
				UnitIsGroupLeader and UnitIsGroupLeader(b.unit),
				UnitIsGroupAssistant and UnitIsGroupAssistant(b.unit))
		end
	end
end

-- Full pass: name + all parts. Used on unit (re-)assignment, roster/layout
-- changes and the initial paint — NOT per unit event.
function Raidframes:RenderLive(f)
	local u = f.unit
	-- NEVER Show/Hide secure buttons ourselves (forbidden in combat) -> the header controls
	-- their visibility. Only the non-secure preview frames we hide/show ourselves.
	if not u or not UnitExists(u) then if not f._secure then f:Hide() end return end
	if not f._secure then f:Show() end
	local d = db()

	local L = layoutCtx()
	if L.showName then f.name:SetText(UnitName(u) or "") end
	-- Name in class color (shared): overrides the configured nameColor (the class is
	-- only known here). Off -> applyText in ApplyConfig set the configured color.
	if d.nameClassColor then local _, class = UnitClass(u); f.name:SetTextColor(classColor(class)) end

	self:RenderDispelAuras(f)   -- fills the dispel cache + colors the bar + aura icons
	self:RenderHealth(f)        -- segments + HP text + status (color re-uses the fresh cache)
	self:RenderAggro(f)
	self:RenderCenterIcon(f)
	setIndicators(f, UnitGroupRolesAssigned and UnitGroupRolesAssigned(u),
		UnitIsGroupLeader and UnitIsGroupLeader(u),
		UnitIsGroupAssistant and UnitIsGroupAssistant(u))
end

-- TEST MODE — fake numbers, identical StatusBar/clip path
function Raidframes:RenderFake(f)
	local fk = f.fake
	local d = db()
	f:Show()

	-- Test mode has no real units -> neutral status layer.
	f.stext:Hide(); f.statusIcon:Hide(); f.htext:Show()
	f._statusMode, f._greyed = nil, nil
	f:SetAlpha(1)

	local hp = fk.hp or 1
	local incoming   = (d.healPrediction and fk.predict or 0) * FAKE_MAX
	local absorb     = (fk.absorb or 0) * FAKE_MAX
	local healAbsorb = (fk.healAbsorb or 0) * FAKE_MAX
	setSegments(f, FAKE_MAX, hp * FAKE_MAX, incoming, absorb, healAbsorb)

	-- Test mode: no real aura object -> map the type directly to the configured color.
	local hasDispel, dr, dg, dbb = false
	if d.dispelEnabled and fk.dispel and (d.dispelShowAll or playerDispels[fk.dispel]) then
		dr, dg, dbb = dispelCol(d, fk.dispel)
		hasDispel = true
	end
	local ha = d.healthAlpha or 1
	local hr, hg, hb, hk
	if hasDispel and d.dispelMode == "recolor" then
		hr, hg, hb, hk = dr, dg, dbb, 1
	else
		hr, hg, hb = fillRGB(d, fk.class); hk = auroraDamp(hr, hg, hb)
	end
	f.health:SetStatusBarColor(hr, hg, hb, ha)
	if ns.Style and ns.Style.SetAuroraColor then ns.Style:SetAuroraColor(f.depth, hr * hk, hg * hk, hb * hk) end
	self:SetDispelOverlay(f, hasDispel and d.dispelMode == "overlay", dr, dg, dbb, d.dispelAlpha)

	if d.aggroEnabled then self:SetAggro(f, fk.aggro) else self:SetAggro(f, nil) end

	local L = layoutCtx()
	if L.showName then f.name:SetText(fk.name) end
	if d.nameClassColor then f.name:SetTextColor(classColor(fk.class)) end

	local t = L.healthTextType
	if t == "Keine" then f.htext:SetText("")
	elseif t == "Prozent" then f.htext:SetText(floor(hp * 100) .. "%")
	else f.htext:SetText(AbbrevNum(floor(hp * FAKE_MAX))) end

	setIndicators(f, fk.role, fk.lead, fk.assist)

	self:RenderAurasFake(f)
end

-- Fill aura icons — LIVE (secret-safe: filter scan, swipe via duration object).
-- Holder/icons are pre-created in the layout path; here only set texture/swipe/show.
function Raidframes:RenderAurasLive(f)
	local u = f.unit
	local A = db().auras
	if not (A and u and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	learnUnitSigs(u)   -- passive signature learning (out of combat; groundwork for the whitelist)
	local spec = currentSpecID()
	local wl   = whitelistCached(spec)   -- whitelist of the active spec (cached; seeded once)
	local sfx  = auraCtxSuffix()       -- display knobs are per context (Feature 1)
	for _, c in ipairs(AURA_CATS) do
		local cat    = A[c.key]
		local holder = f.auraHolders and f.auraHolders[c.key]
		if cat and cat["enabled" .. sfx] and holder then
			local maxN     = cat["maxIcons" .. sfx] or 5
			local showSwipe = cat["showSwipe" .. sfx]
			local filterMode = cat["filterMode" .. sfx]
			local fn   = C_UnitAuras.IsAuraFilteredOutByInstanceID
			local shown, i = 0, 1
			while shown < maxN do
				local aura = C_UnitAuras.GetAuraDataByIndex(u, i, c.filter)
				if not aura then break end
				i = i + 1
				local iid = aura.auraInstanceID
				-- Apply sub-filter secret-safely (only bool return, no secret read).
				local subPass = true
				if c.subExclude or c.subInclude then
					if iid and fn then
						local out = fn(u, iid, c.subExclude or c.subInclude)
						subPass = (c.subExclude and out == true) or (not c.subExclude and out == false)
					else
						subPass = false
					end
				elseif c.harmfulModes then
					-- Debuffs: Blizzard standard filter (all/raid-relevant/dispellable).
					subPass = debuffModeAccept(u, iid, filterMode, fn)
				end
				-- Whitelist: which spells this category shows. sid also for the secret-free icon.
				--  * whitelistOr (defensives, B3): filter hit (external def) OR own "def"
				--    whitelist; own auras checked first via isFromPlayerOrPlayerPet (12.0.5, not secret).
				--  * otherwise (HoTs, B2): only a positive whitelist hit shows (no filter fallback).
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
						-- HoTs: only own. The filter is now "HELPFUL" (also shows proc/
						-- talent HoTs without a PLAYER source flag) -> check ownership separately here.
						accept = false
					else
						-- HoTs (whitelist, no Or): show ONLY if the aura resolves positively to a
						-- whitelist spell. NO subPass fallback anymore — otherwise in-combat
						-- unresolvable self-buffs (toys/trinkets/general buffs that Blizzard
						-- lists in the buff frame) slip through, because the filter is now "HELPFUL".
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
						if showSwipe and ic.cd then
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

-- Preview icons for a category: prefer the player's ACTUALLY-tracked spells (the
-- active spec's whitelist for the category type) so the sample reads per-class /
-- per-spec; fall back to the generic fake set (empty whitelist, or debuffs which
-- aren't tracked). Cached per spec + invalidated at the preview redraw roots
-- (RefreshShellPreview / RefreshPreview) so it never allocates in the fill loop.
local pvIcons = { spec = -1, lists = {} }
local function invalidatePreviewIcons() pvIcons.spec = -1 end
local function previewIconsFor(c)
	if not c.whitelist then return c.fake or FAKE_HOTS end
	local sid = currentSpecID()
	if pvIcons.spec ~= sid then
		pvIcons.spec = sid
		for k in pairs(pvIcons.lists) do pvIcons.lists[k] = nil end
	end
	local list = pvIcons.lists[c.key]
	if list == nil then
		list = false   -- cached "nothing tracked" (avoid re-scanning each frame)
		if sid ~= 0 then
			local entries = Raidframes:WhitelistEntries(sid, c.whitelist)
			if #entries > 0 then
				list = {}
				for i = 1, #entries do list[i] = entries[i].icon end
			end
		end
		pvIcons.lists[c.key] = list
	end
	return list or c.fake or FAKE_HOTS
end

-- Fill aura icons — TEST MODE (fake HoTs with sample swipe; runs out of combat).
function Raidframes:RenderAurasFake(f)
	local A = db().auras
	if not A then return end
	local sfx = auraCtxSuffix()        -- display knobs are per context (Feature 1)
	for _, c in ipairs(AURA_CATS) do
		local cat    = A[c.key]
		local holder = f.auraHolders and f.auraHolders[c.key]
		if cat and cat["enabled" .. sfx] and holder then
			local n = min(cat["maxIcons" .. sfx] or 5, 3)
			local showSwipe = cat["showSwipe" .. sfx]
			local fakeTex = previewIconsFor(c)
			for k = 1, n do
				local ic = holder.icons[k]
				if ic then
					ic.tex:SetTexture(fakeTex[((k - 1) % #fakeTex) + 1])
					if showSwipe and ic.cd then
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
--  SHELL PREVIEW (docked live-preview band in the settings shell)
--  A small OWN pool (separate from the test pool: test mode positions `frames`
--  on the real screen container) rendered into a W.PreviewBand's holder. Uses
--  the same Decorate/ApplyConfig/render path as test mode, with previewCtx
--  forcing the tab's context. No unit events — refreshes piggyback on
--  UpdateLayout/RefreshAuras (the paths every settings change already takes).
-- ===========================================================================

-- Curated preview roster: full bar, shield, incoming heal, dispellable debuff,
-- heal absorb, aggro — every render feature visible at a glance (each one can
-- be filtered out via the band's filter popover).
local PREVIEW_FAKE = {
	{ name = "Owlday",      class = "DRUID",  hp = 1.00, role = "HEALER", lead = true },
	{ name = "Elyndra",     class = "MAGE",   hp = 0.82, absorb = 0.14, role = "DAMAGER" },
	{ name = "Kaelura",     class = "PRIEST", hp = 0.66, predict = 0.20, role = "HEALER" },
	{ name = "Nighthollow", class = "ROGUE",  hp = 0.45, dispel = "Magic", role = "DAMAGER" },
	{ name = "Sylfaria",    class = "MONK",   hp = 0.88, healAbsorb = 0.18, aggro = 3, role = "TANK" },
}
local shellBands = {}   -- band -> spec: { kind = "base" } | { kind = "ctx", ctx = "raid"|"party" }
local pvFrames = {}     -- shared preview pool (one band visible at a time)

local function pvFrame(i, holder)
	local f = pvFrames[i]
	if not f then
		f = CreateFrame("Frame", nil, holder)
		Decorate(f)
		f:EnableMouse(false)
		pvFrames[i] = f
	end
	f:SetParent(holder)
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
	if eyes.text == false then f.name:Hide(); f.htext:Hide() end
	if eyes.icons == false then f.roleIcon:Hide(); f.leadIcon:Hide() end
end

-- Dispel/aggro filters work at the DATA level (a recolored health bar can't
-- be "hidden" afterwards): render a scratch copy without those fields.
local pvScratch = {}
local function pvEffectiveFake(fake, eyes)
	if (eyes.dispel == false and fake.dispel) or (eyes.aggro == false and fake.aggro) then
		for k in pairs(pvScratch) do pvScratch[k] = nil end
		for k, v in pairs(fake) do pvScratch[k] = v end
		if eyes.dispel == false then pvScratch.dispel = nil end
		if eyes.aggro == false then pvScratch.aggro = nil end
		return pvScratch
	end
	return fake
end

local function pvFillOne(f, fake, ctx, eyes)
	previewCtx = ctx
	f.fake = pvEffectiveFake(fake, eyes)
	f.unit = nil
	pvResetLayers(f)
	Raidframes:ApplyConfig(f)
	Raidframes:UpdateUnit(f)
	pvEyePass(f, eyes)
	previewCtx = nil
	f:Show()
end

function Raidframes:AttachShellPreview(band, spec)
	shellBands[band] = spec
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
	local used, cw, ch, caption, side = 0, 1, 1, "", "bottom"

	-- Guarded fill: previewCtx MUST never leak into the real render paths.
	local ok, err = pcall(function()
		-- Context: fixed per tab (Raid/Group) — the Base tab switches via its
		-- Raid/Group chips instead (so Base settings like aggro/dispel are
		-- judged on the real group layout).
		local ctx = spec.ctx
		if spec.baseSwitch then ctx = (d.previewBaseCtx == "raid") and "raid" or "party" end
		local L = d[ctx]
		local w, h, sp = L.width, L.height, L.spacing
		local horizontal = (L.orientation == "horizontal")
		-- Sample size: the Raid tab has 5/10/20/25 chips; Base/Group show one
		-- group. Clamp legacy values (the first chip set went up to 40).
		local n = min((spec.ctx == "raid" and d.previewSize) or GROUP_SIZE, 25)
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
		local groups  = max(1, ceil(n / GROUP_SIZE))
		local inGroup = max(1, min(n, GROUP_SIZE))
		local cols, rows
		if horizontal then cols, rows = inGroup, groups else cols, rows = groups, inGroup end
		cw, ch = cols * (w + sp) - sp, rows * (h + sp) - sp
		caption = ("%s  ·  %d  ·  %s"):format(
			ctx == "raid" and ns.T("Raid") or ns.T("Group"), n,
			horizontal and ns.T("horizontal") or ns.T("vertical"))
		-- Dock side (Florian's rule): the Raid TAB always docks right (below
		-- the panel it collides with the screen bottom); otherwise right when
		-- vertical, below when horizontal.
		if spec.ctx == "raid" or not horizontal then side = "right" end
	end)
	previewCtx = nil
	if not ok then
		if ns.Lumen then ns.Lumen:Print("|cffD66A5CPreview:|r " .. tostring(err)) end
		return
	end

	for i = used + 1, #pvFrames do pvFrames[i]:Hide() end
	holder:SetSize(cw, ch)
	-- Report side + VISUAL extent (stage units): holder units render at scale s.
	band:SetExtent(side, cw * s, ch * s, caption)
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
		if container then container:Hide() end
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
		if container then container:Show() end
		self:UpdateLayout()   -- rebuild + reposition the real header
	end
end

-- ===========================================================================
--  LIVE  (SecureGroupHeader + SecureUnitButtons) — clickable/targetable (phase 1).
-- ===========================================================================

-- Secure right-click menu (12.0.7): a "togglemenu" directly on the unit button is
-- gated (silently dropped without a matching click binding); opening from insecure Lua
-- TAINTS the menu (protected entries like "Set focus" throw ADDON_ACTION_FORBIDDEN).
-- Solution (secure-conform pattern): route the right click via the UN-gated "click" action
-- to a hidden SecureActionButton proxy that safely runs "togglemenu" itself.
-- "useparent-unit" -> the proxy gets the unit from the parent button (header-managed).
local function getMenuProxy(button)
	local proxy = button._lumenMenuProxy
	if not proxy then
		proxy = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
		proxy:SetSize(1, 1); proxy:SetAlpha(0); proxy:EnableMouse(false)
		proxy:RegisterForClicks("AnyUp")
		proxy:SetAttribute("type", "togglemenu")
		for i = 1, 5 do proxy:SetAttribute("type" .. i, "togglemenu") end  -- resolved per button suffix
		proxy:SetAttribute("useparent-unit", true)
		proxy:SetAttribute("useOnKeyDown", false)
		button._lumenMenuProxy = proxy
	end
	return proxy
end
ns.RF_GetMenuProxy = getMenuProxy

-- Phase-1 default clicks: left=target, right=WoW menu (via proxy). Set on creation
-- AND restored by ClickCast when the user disables click-cast.
-- Call ONLY out of combat (setting attributes is protected).
local function applyDefaultClicks(button)
	button:SetAttribute("type1", "target")
	button:SetAttribute("*type1", "target")
	button:SetAttribute("type2", nil)
	button:SetAttribute("*type2", "click")
	button:SetAttribute("*clickbutton2", getMenuProxy(button))
end
ns.RF_ApplyDefaultClicks = applyDefaultClicks

-- Equip a header-created secure button once with our render stack + click behavior.
-- Call ONLY out of combat (setting attributes is protected).
local function styleSecureButton(button)
	if button._lumenSecured then return end
	button._lumenSecured = true
	button._secure = true
	Decorate(button)
	-- Click: left=target (unmodified has a default click binding), right=menu via proxy.
	button:EnableMouse(true)
	button:RegisterForClicks("AnyUp")
	applyDefaultClicks(button)
	-- Mouse highlight: HookScript (NOT SetScript) -> the secure header handlers stay intact.
	button:HookScript("OnEnter", function(self) Raidframes:SetHighlight(self, true) end)
	button:HookScript("OnLeave", function(self) Raidframes:SetHighlight(self, false) end)
	-- (Re-)assignment of the unit: reliable per-button signal -> routing map + immediate repaint.
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
	-- Seam for later full click-cast (phase 2): the bindings engine docks here.
	if ns.CC_RegisterButton then ns.CC_RegisterButton(button) end
end

-- Header layout attributes from the active context (orientation + spacing). ONLY out of combat.
local function applyHeaderLayout()
	if not header then return end
	local L = layoutCtx()
	local sp = L.spacing or 2
	local horizontal = (L.orientation == "horizontal")
	-- Within the 5-man group the members grow; perpendicular the groups grow.
	local point, xOff, yOff, colAnchor
	if horizontal then
		point, xOff, yOff, colAnchor = "LEFT", sp, 0, "TOP"   -- members to the right, groups downward
	else
		point, xOff, yOff, colAnchor = "TOP", 0, -sp, "LEFT"  -- members downward, groups to the right
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

-- Apply size/texture/text to all (pre-created) buttons + render occupied ones. ONLY out of combat.
local function configureSecureButtons()
	if not header then return end
	for i = 1, 40 do
		local btn = header[i]
		if btn then
			Raidframes:ApplyConfig(btn)   -- sets e.g. SetSize -> forbidden in combat, safe here OOC
			-- Read the unit live from the attribute: assignments that happened on the very
			-- first header show BEFORE attaching the OnAttributeChanged hooks would otherwise
			-- only show on the next event. Catch up map + btn.unit here.
			local u = btn.unit or btn:GetAttribute("unit")
			if u and UnitExists(u) then
				btn.unit = u; unitToButton[u] = btn
				Raidframes:RenderLive(btn)
			end
		end
	end
end

-- Build the header once + pre-create 40 buttons (startingIndex trick) and decorate them.
local function buildHeader()
	if header then return end
	local L = layoutCtx()
	local bw, bh = L.width or 114, L.height or 60
	header = CreateFrame("Frame", "LumenRaidHeader", container, "SecureGroupHeaderTemplate")
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("templateType", "Button")
	-- initialConfigFunction runs in the restricted env on button creation -> only set size.
	header:SetAttribute("initialConfigFunction", ([[
		self:SetWidth(%d)
		self:SetHeight(%d)
	]]):format(bw, bh))
	header:SetAttribute("showRaid", true)
	header:SetAttribute("showParty", true)
	header:SetAttribute("showPlayer", true)
	header:SetAttribute("showSolo", db().showWhenSolo and true or false)   -- option: show frame even when solo
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
	-- Sorting via header attributes (secure-conform):
	--  * "group" -> no groupBy, sortMethod INDEX (raid group/roster order).
	--  * "role"  -> groupBy ASSIGNEDROLE, sortMethod NAME, groupingOrder = priority list
	--               + ",NONE" (otherwise units without an assigned role would drop out).
	local d = db()
	-- Catch up "show frame even when solo" live (toggle takes effect immediately OOC).
	local wantSolo = d.showWhenSolo and true or false
	if header:GetAttribute("showSolo") ~= wantSolo then
		header:SetAttribute("showSolo", wantSolo)
	end
	-- Role sorting always applies in dungeon/party; in raid only if explicitly enabled
	-- (fixed raids are often built by group manually). isRaidContext() separates that.
	local byRole = (d.sortMode == "role") and (not isRaidContext() or d.sortApplyRaid)
	local gb = byRole and "ASSIGNEDROLE" or nil
	local sm = byRole and "NAME" or "INDEX"
	local go = byRole and (table.concat(d.sortRoleOrder or DEFAULT_ROLE_ORDER, ",") .. ",NONE") or ""
	local sortChanged = (header:GetAttribute("groupBy") ~= gb)
		or (header:GetAttribute("sortMethod") ~= sm)
		or (header:GetAttribute("groupingOrder") ~= go)
	if sortChanged then
		-- ORDER MATTERS: groupingOrder MUST come before groupBy. Each SetAttribute
		-- immediately triggers SecureGroupHeader_Update; if you set groupBy first,
		-- groupingOrder is still nil there -> Blizzard error. So groupBy last.
		header:SetAttribute("groupingOrder", go)
		header:SetAttribute("sortMethod", sm)
		header:SetAttribute("groupBy", gb)
	end
	-- Size / orientation / spacing / sorting change all alter the header's layout
	-- attributes (size via initialConfig; point/xOffset/yOffset/columnAnchorPoint/
	-- columnSpacing via applyHeaderLayout). A plain SetAttribute does NOT reliably
	-- reflow the ALREADY created buttons -> force the header to re-arrange (Hide/Show),
	-- otherwise a change like horizontal<->vertical only snaps into place on /reload.
	local L = layoutCtx()
	local orient  = L.orientation or "vertical"
	local spacing = L.spacing or 2
	local sizeChanged   = (header._appliedW ~= L.width or header._appliedH ~= L.height)
	local layoutChanged = (header._appliedOrient ~= orient or header._appliedSpacing ~= spacing)
	header._appliedW, header._appliedH = L.width, L.height
	header._appliedOrient, header._appliedSpacing = orient, spacing
	configureSecureButtons()   -- ApplyConfig sets e.g. the button size
	if (sizeChanged or sortChanged or layoutChanged) and header:IsShown() then
		header:Hide()
		-- Blizzard's configureChildren re-anchors active buttons with SetPoint but
		-- never ClearAllPoints them first. Flipping the anchor `point` (orientation
		-- change: TOP<->LEFT) therefore ADDS a second anchor instead of replacing it,
		-- so the buttons get pulled diagonally until a /reload recreates them. Clear
		-- the stale anchors ourselves (OOC only) so the reflow on Show() is clean.
		for i = 1, 40 do
			local btn = header[i]
			if btn then btn:ClearAllPoints() end
		end
		header:Show()
	else
		header:Show()
	end
	self:NotifyFrameChange()   -- inform foreign providers (e.g. MiniCC) about the new frame list
end

function Raidframes:HideHeader()
	if not header then return end
	if InCombatLockdown() then secureLayoutDirty = true; return end
	header:Hide()
end

-- Re-layout + render only the aura indicators (anchor/growth/size/toggles).
-- COMBAT-SAFE: holder/icons are own, NON-protected frames on the overlay (no secure
-- template, no button size) -> SetPoint/SetSize/CreateFrame on them are allowed even
-- in combat. So NO InCombatLockdown defer here like in LayoutLive (which aborts due
-- to the secure header) -> aura settings take effect immediately, even on the
-- target dummy in combat.
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
	if header then
		for i = 1, 40 do
			local b = header[i]
			if b and b._lumenSecured and b.unit and UnitExists(b.unit) then
				relayout(b); self:RenderAurasLive(b)
			end
		end
	end
	self:RefreshShellPreview()   -- aura setters route through here -> keep the band live
end

-- Settings/roster changes funnel through here -> relayout the secure header.
function Raidframes:UpdateLayout()
	if not container then return end
	-- During an Edit Mode session the PREVIEWS are the display — never rebuild/show
	-- the live secure header (it would pop up behind the previews when a tab setting
	-- changes while the Shell coexists). Just refresh the previews with the new
	-- settings; a full live layout follows when the session ends (ShowEditPreviews).
	if ns.EditMode and ns.EditMode.session then
		self:RefreshShellPreview()
		return
	end
	local d = db()
	-- Module off: build/show NOTHING live. Important, because roster/world events
	-- (e.g. PLAYER_ENTERING_WORLD after /reload) would otherwise rebuild and show
	-- the header even though "Raidframes enabled" is off.
	if not d.enabled then
		self:HideHeader()
		container:Hide()
		self:RefreshShellPreview()   -- the shell band keeps rendering while disabled
		return
	end
	dispelCurve = nil   -- dispel colors may have changed -> have the curve rebuilt
	wlInvalidate()      -- profile may have switched -> re-resolve the whitelist table
	self:LayoutLive()
	self:RefreshShellPreview()   -- settings changes route through here -> keep the band live
	-- If the raidframes are a coupled child, LayoutLive just reset the container
	-- to its absolute position -> re-anchor it onto its Edit Mode link anchor.
	if ns.EditMode and ns.EditMode.ApplyLinks then ns.EditMode:ApplyLinks() end
end

-- Unit events -> the SPLIT render part they need (PERF: a health tick no longer
-- re-scans auras). Registered globally, so they also fire for units we don't
-- own (nameplates/target/boss) — the handler bails on ONE hash lookup
-- (unitToButton) before touching anything else.
local UNIT_EVENT_METHOD = {
	UNIT_HEALTH                     = "RenderHealth",
	UNIT_MAXHEALTH                  = "RenderHealth",
	UNIT_ABSORB_AMOUNT_CHANGED      = "RenderHealth",
	UNIT_HEAL_ABSORB_AMOUNT_CHANGED = "RenderHealth",
	UNIT_HEAL_PREDICTION            = "RenderHealth",
	UNIT_AURA                       = "RenderDispelAuras",
	UNIT_THREAT_SITUATION_UPDATE    = "RenderAggro",
	-- Status layer (offline/ghost/rez transitions + summon; death rides on UNIT_HEALTH)
	UNIT_CONNECTION                 = "RenderStatus",
	UNIT_FLAGS                      = "RenderStatus",
	INCOMING_RESURRECT_CHANGED      = "RenderStatus",
	INCOMING_SUMMON_CHANGED         = "RenderCenterIcon",
}

-- ---- Foreign provider interface (e.g. MiniCC) -----------------------------
-- External addons (CD trackers) may dock icons onto our live frames.
-- GetLiveButtons returns the visible secure buttons; the caller iterates
-- immediately -> we return a REUSED scratch buffer (no garbage).
-- NotifyFrameChange reports (debounced to the next tick) to registered
-- callbacks when the frame list has changed.
local liveScratch = {}
function Raidframes:GetLiveButtons()
	wipe(liveScratch)
	if not header then return liveScratch end
	local n = 0
	for i = 1, 40 do
		local btn = header[i]
		if btn and btn:IsVisible() then
			local u = btn.unit or btn:GetAttribute("unit")
			if u and UnitExists(u) then
				n = n + 1
				liveScratch[n] = btn
			end
		end
	end
	return liveScratch
end

local frameChangeCbs
local frameChangeQueued = false
local function fireFrameChange()
	frameChangeQueued = false
	if not frameChangeCbs then return end
	for i = 1, #frameChangeCbs do pcall(frameChangeCbs[i]) end
end
function Raidframes:OnFrameChange(cb)
	frameChangeCbs = frameChangeCbs or {}
	frameChangeCbs[#frameChangeCbs + 1] = cb
end
function Raidframes:NotifyFrameChange()
	if frameChangeQueued or not frameChangeCbs then return end
	frameChangeQueued = true
	C_Timer.After(0, fireFrameChange)   -- only fire once the layout positions are final
end

-- ---- Suppress Blizzard's default raid frames ------------------------------
-- Lumen builds its own frames ALONGSIDE; without this, Lumen-only users would see double.
-- Robust + taint-safe: reparent the protected Blizzard containers onto a permanently
-- hidden parent frame (then they NEVER render, even in combat) + unregister events
-- (no double processing, performance). Edit mode re-shows its systems on entering +
-- resets their scale -> make the selection box invisible separately via alpha/scale and
-- catch up on the relevant events.
-- Reparent/scale are forbidden in combat -> only OOC resp. deferred.
-- The way back (toggle off) needs a /reload (events are unregistered) -> popup.
local blizzParent                 -- permanently hidden parent frame
local blizzSuppressed = false     -- are WE currently suppressing? (controls the popup)
local blizzInit = false           -- attach hooks/watcher only once
local blizzHooked = {}            -- SetParent hook per frame only once
local blizzLoose  = {}            -- frames not reparentable in combat -> catch up on regen

-- Deliberately do NOT touch the Manager (left leader/marker bar): it contains leader
-- tools (ready check, markers). Only remove the unit containers.
local function blizzRaidFrames()
	local t = { CompactRaidFrameContainer, PartyFrame, _G.CompactPartyFrame }
	for i = 1, 5 do t[#t + 1] = _G["CompactPartyFrameMember" .. i] end
	return t
end

local function blizzResetParent(self, parent)
	if not blizzSuppressed or parent == blizzParent then return end
	if InCombatLockdown() and self:IsProtected() then
		blizzLoose[self] = true            -- forbidden in combat -> on PLAYER_REGEN_ENABLED
	else
		self:SetParent(blizzParent)
	end
end

local function blizzHandleFrame(frame)
	if not frame then return end
	frame:UnregisterAllEvents()   -- not a protected op, fine even in combat
	-- Hide/SetParent on a protected frame are BLOCKED in combat (would throw
	-- ADDON_ACTION_BLOCKED, e.g. profile switch mid-fight) -> defer to regen.
	if InCombatLockdown() and frame:IsProtected() then
		blizzLoose[frame] = true
	else
		frame:Hide()
		if frame:GetParent() ~= blizzParent then frame:SetParent(blizzParent) end
	end
	if not blizzHooked[frame] then
		blizzHooked[frame] = true
		hooksecurefunc(frame, "SetParent", blizzResetParent)
		frame:HookScript("OnShow", function(self)
			if not blizzSuppressed then return end
			if not InCombatLockdown() then self:Hide() end
		end)
	end
	-- Also silence child bars/auras (no double processing).
	local hb = frame.healthBar or frame.healthbar or frame.HealthBar
		or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
	if hb then hb:UnregisterAllEvents() end
end

-- Make the edit-mode selection box invisible (hide/reparent is NOT enough: edit mode
-- forces showing its systems). Scale is forbidden in combat.
local function blizzSuppressOverlay(frame)
	if not frame then return end
	pcall(function()
		frame:SetAlpha(0)
		if not InCombatLockdown() then frame:SetScale(0.001) end
		if frame.selectionHighlight and frame.selectionHighlight.SetShown then
			frame.selectionHighlight:SetShown(false)
		end
		if frame.selectionIndicator and frame.selectionIndicator.SetShown then
			frame.selectionIndicator:SetShown(false)
		end
	end)
end

local function blizzApplyOverlay()
	if not blizzSuppressed then return end
	blizzSuppressOverlay(CompactRaidFrameContainer)
	blizzSuppressOverlay(PartyFrame)
	blizzSuppressOverlay(_G.CompactPartyFrame)
end

local function suppressBlizzard()
	blizzSuppressed = true
	if not blizzParent then
		blizzParent = CreateFrame("Frame", "LumenHiddenParent", UIParent)
		blizzParent:Hide()
	end
	for _, f in ipairs(blizzRaidFrames()) do blizzHandleFrame(f) end
	blizzApplyOverlay()

	if blizzInit then return end
	blizzInit = true
	-- Catch up reparents deferred during combat.
	local regen = CreateFrame("Frame")
	regen:RegisterEvent("PLAYER_REGEN_ENABLED")
	regen:SetScript("OnEvent", function()
		if not blizzSuppressed then return end
		for f in next, blizzLoose do f:Hide(); f:SetParent(blizzParent) end
		wipe(blizzLoose)
	end)
	-- Re-suppress the overlay after world/edit-mode events (re-show + scale reset).
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	watcher:SetScript("OnEvent", function() C_Timer.After(0, blizzApplyOverlay) end)
	if type(_G.CompactRaidFrameManager_UpdateShown) == "function" then
		hooksecurefunc("CompactRaidFrameManager_UpdateShown", function()
			C_Timer.After(0, blizzApplyOverlay)
		end)
	end
	local function hookEM()
		if not EditModeManagerFrame then return end
		EditModeManagerFrame:HookScript("OnShow", function() C_Timer.After(0, blizzApplyOverlay) end)
		hooksecurefunc(EditModeManagerFrame, "Hide", function() C_Timer.After(0, blizzApplyOverlay) end)
	end
	if EditModeManagerFrame then hookEM()
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", hookEM)
	end
end

-- A clean way back (Blizzard frames restored) requires /reload -> ask.
-- Prefer the Lumen confirm dialog (shell look); only if the shell is closed
-- (e.g. profile switch in the background), Blizzard's StaticPopup as a fallback.
-- Read texts only at display time via T() (the language is fixed by then).
StaticPopupDialogs["LUMEN_RAIDFRAMES_RELOAD"] = {
	text = "%s",   -- filled at display time (promptBlizzReload)
	button1 = "", button2 = "",   -- set at display time via T()
	OnAccept = function() ReloadUI() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
local function promptBlizzReload()
	local title = ns.T("Raidframes disabled")
	local body  = ns.T("Lumen's raid frames are off. Reloading the UI brings Blizzard's default raid frames back.")
	local shellOpen = ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown()
	if shellOpen and ns.W and ns.W.Confirm then
		ns.W.Confirm({
			title = title, body = body,
			confirmText = ns.T("Reload now"), cancelText = ns.T("Later"),
			variant = "primary", -- neutral confirm, nothing destructive (red = destructive only)
			onConfirm = function() ReloadUI() end,
		})
	else
		local dlg = StaticPopupDialogs["LUMEN_RAIDFRAMES_RELOAD"]
		dlg.button1, dlg.button2 = ns.T("Reload now"), ns.T("Later")
		StaticPopup_Show("LUMEN_RAIDFRAMES_RELOAD", title .. "\n" .. body)
	end
end

function Raidframes:Setup()
	if container then return end
	container = CreateFrame("Frame", "LumenRaidContainer", UIParent)
	container:SetSize(200, 200)
	container:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
	-- HIGH strata: raidframes must never sit under action-bar/HUD elements
	-- (both default to MEDIUM, so hotkey text bled through on overlap). Set
	-- BEFORE any child exists so the whole subtree inherits one base; dialogs/
	-- tooltips (DIALOG+) still cover us.
	container:SetFrameStrata("HIGH")
	container:RegisterEvent("PLAYER_ENTERING_WORLD")
	container:RegisterEvent("GROUP_ROSTER_UPDATE")
	container:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	container:RegisterEvent("PLAYER_REGEN_ENABLED")   -- combat end -> catch up deferred layout
	container:RegisterEvent("PARTY_LEADER_CHANGED")   -- leader/assist + role icons repaint
	container:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	container:RegisterEvent("READY_CHECK")            -- status center icon
	container:RegisterEvent("READY_CHECK_CONFIRM")
	container:RegisterEvent("READY_CHECK_FINISHED")
	for ev in pairs(UNIT_EVENT_METHOD) do container:RegisterEvent(ev) end
	container:SetScript("OnEvent", function(_, event, unit)
		-- HOT PATH first: unit events fire for EVERY unit in the world (incl.
		-- nameplates). One table lookup routes/bails; IsVisible also covers
		-- test mode + disabled module (header hidden -> buttons not visible).
		local m = UNIT_EVENT_METHOD[event]
		if m then
			local f = unitToButton[unit]
			if f and f:IsVisible() then Raidframes[m](Raidframes, f) end
			return
		end
		if event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" or event == "READY_CHECK_FINISHED" then
			Raidframes:OnReadyCheck(event)
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if secureLayoutDirty then
				secureLayoutDirty = false
				Raidframes:UpdateLayout()
			end
			return
		end
		if event == "PARTY_LEADER_CHANGED" or event == "PLAYER_ROLES_ASSIGNED" then
			Raidframes:RefreshIndicators()
			return
		end
		if event == "PLAYER_SPECIALIZATION_CHANGED" then
			-- Fires for OTHER group members too -> only the player's own spec
			-- change matters here (whitelist + signatures are player-scoped).
			if unit and unit ~= "player" then return end
			wipe(learnedIID)   -- signatures are spec-scoped -> relearn
			wlInvalidate()
		elseif event == "PLAYER_ENTERING_WORLD" then
			wipe(learnedIID)   -- fresh world: drop stale aura-instance fingerprints
		elseif event == "GROUP_ROSTER_UPDATE" and InCombatLockdown() then
			-- Mid-combat roster change: the secure header re-sorts on its own, but a
			-- unit token can change OCCUPANT without its attribute value changing ->
			-- refresh the routing map + repaint content (textures/text only, allowed
			-- in combat). The layout part defers to PLAYER_REGEN_ENABLED as usual.
			secureLayoutDirty = true
			if header then
				for i = 1, 40 do
					local b = header[i]
					if b and b:IsVisible() then
						local u2 = b:GetAttribute("unit")
						if u2 and UnitExists(u2) then
							b.unit = u2; unitToButton[u2] = b
							Raidframes:RenderLive(b)
						end
					end
				end
			end
			return
		end
		local _, class = UnitClass("player")
		playerDispels = CLASS_DISPELS[class] or {}
		Raidframes:UpdateLayout()
	end)
	local _, class = UnitClass("player")
	playerDispels = CLASS_DISPELS[class] or {}

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
	container:Hide()   -- default = off; only Enable() shows the container (else frames despite "off")
end

function Raidframes:Enable()
	self:Setup()
	container:Show()
	self:UpdateLayout()
	suppressBlizzard()   -- hide Blizzard's default raid frames while Lumen's are active
end
function Raidframes:Disable()
	if not container then return end
	-- Did WE suppress Blizzard's frames? A clean way back needs /reload
	-- (events are unregistered) -> ask once. Popup/ReloadUI are combat-safe.
	if blizzSuppressed then
		blizzSuppressed = false
		promptBlizzReload()
	end
	-- The container is the parent frame of the secure header -> Hide in combat would be
	-- forbidden on protected children. Defer in combat (takes effect again on RefreshAll/regen).
	if InCombatLockdown() then secureLayoutDirty = true; return end
	if header then header:Hide() end
	container:Hide()
end
