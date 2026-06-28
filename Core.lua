local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Core
--  Addon (Ace3), zentrale Profile (AceDB), /lumen.
-- ===========================================================================

local Lumen = LibStub("AceAddon-3.0"):NewAddon("Lumen", "AceConsole-3.0", "AceEvent-3.0")
ns.Lumen = Lumen

local defaults = {
	profile = {
		raidframes = {
			enabled        = true,

			-- Lebensbalken (geteilt — Tab „Base")
			healthTexture  = "Lumen Gradient",
			useClassColor  = true,
			fillColor      = { r = 0.20, g = 0.60, b = 0.30 },
			healPrediction = true,

			-- Hintergrund & Transparenz (geteilt — Tab „Base"). Alpha 0..1.
			bgColor         = { r = 0.11, g = 0.11, b = 0.11 }, -- Frame-Hintergrundfarbe (war fest 0.11)
			bgAlpha         = 1,                                -- Deckkraft des Hintergrunds
			healthAlpha     = 1,                                -- Deckkraft NUR der Lebensbalken-Füllung
			shieldAlpha     = 1,                                -- Deckkraft des Schild-Overlays
			healAbsorbAlpha = 1,                                -- Deckkraft des Heilabsorb-Overlays
			-- Textur für Schild/Healabsorb. Default = gekacheltes Lumen-Muster (wie bisher);
			-- jede andere Wahl (LSM/Blizzard) wird als glatte Füllung gestreckt (Raidframes.lua).
			-- WICHTIG: Keys müssen zu SHIELD_PATTERN/HEALABS_PATTERN in Modules/Raidframes.lua passen.
			shieldTexture     = "Lumen Schild",
			healAbsorbTexture = "Lumen Heilabsorb",

			-- Text-Optik (geteilt — Tab „Base"): Farbe + Umrandung sind Geschmackswahl und
			-- gelten für Raid UND Party gleich. Größe/Position/Anzeigen liegen PRO KONTEXT
			-- (raid/party, weil von der Frame-Größe abhängig). nameClassColor überschreibt nameColor.
			nameClassColor    = false,
			nameColor         = { r = 1, g = 1, b = 1 },
			nameOutline       = "outline",
			healthTextColor   = { r = 1, g = 1, b = 1 },
			healthTextOutline = "outline",

			-- Frame-Sichtbarkeit: Gruppen-Frame auch alleine zeigen (Default aus -> alleine
			-- kein Frame; an -> immer sichtbar). Setzt das SecureGroupHeader-Attribut showSolo.
			showWhenSolo = false,

			-- Schilde (eigene Texturen, immer sichtbar bei Schild)
			absorbStyle     = "Blizzard",         -- Blizzard | Flach
			healAbsorbStyle = "Blizzard",         -- Blizzard | Flach
			healAbsorbColor = { r = 1, g = 1, b = 1 },

			-- (Name-/HP-Text liegen jetzt PRO KONTEXT in raid/party — siehe unten.)

			-- Dispel (secret-sicher: Blizzard-Filter + Color-Curve, funktioniert im Kampf)
			dispelEnabled = true,
			dispelMode    = "recolor",          -- "recolor" (Balken einfärben) | "overlay" (Rand+Overlay, Klassenfarbe bleibt)
			dispelShowAll = false,              -- false = nur was ich dispellen kann; true = alle dispellbaren
			dispelAlpha   = 0.30,               -- Deckkraft der Overlay-Füllung (nur Modus "overlay")
			dispelColors  = {
				Magic   = { r = 0.20, g = 0.60, b = 1.00 },
				Curse   = { r = 0.64, g = 0.19, b = 0.79 },
				Disease = { r = 0.55, g = 0.41, b = 0.18 },
				Poison  = { r = 0.12, g = 0.69, b = 0.29 },
			},

			-- Aggro-Warnung (secret-sicher: Threat-API ist NICHT secret, event-getrieben).
			-- 2-stufig: gelb = Aggro droht (Status 1-2), rot = hat Aggro (Status 3).
			aggroEnabled = true,
			-- Aggro nur in Dungeon/Raid zeigen (Standard an): solo/Open World hätte man
			-- sonst dauerhaft das Overlay, weil man dort fast immer Aggro hat.
			aggroInstanceOnly = true,
			-- Pro Stufe: Darstellung "border" (nur Rand) | "overlay" (Rand + Overlay).
			-- Text gibt es nur im Overlay-Modus (eigener Toggle). Rot/Gelb nie gleichzeitig
			-- auf einem Frame -> Text-Optik (Position/Größe) ist GETEILT (unten).
			aggroColorAggro = { r = 0.90, g = 0.15, b = 0.15 }, -- rot, "hat Aggro" (Status 3)
			aggroModeAggro  = "overlay",           -- "border" | "overlay"
			aggroTextAggro  = true,                -- "Aggro"-Text (nur im Overlay-Modus)
			aggroColorWarn  = { r = 0.95, g = 0.80, b = 0.20 }, -- gelb, "Aggro droht" (Status 1-2)
			aggroModeWarn   = "border",            -- "border" | "overlay"
			aggroTextWarn   = false,
			-- Geteilte Darstellung beider Stufen:
			aggroFillAlpha   = 0.22,               -- Deckkraft des Overlays
			aggroTextSize    = 12,
			aggroTextPoint   = "TOP",
			aggroTextX       = 0,
			aggroTextY       = -2,
			aggroTextOutline = "thick",            -- none | outline | thick

			-- Sortierung (global, secure über SecureGroupHeader-Attribute). "group" = nach
			-- Raid-Gruppe (Default, wie bisher), "role" = nach zugewiesener Rolle in der
			-- frei umsortierbaren Prioritäts-Reihenfolge. Gilt für Raid UND Party gleich.
			sortMode = "group",                    -- "group" | "role"
			sortRoleOrder = { "TANK", "HEALER", "DAMAGER" },  -- Prioritätsliste (oben = zuerst)
			sortApplyRaid = false,                 -- Rollen-Sortierung auch im Raid? (Dungeon/Party immer)

			-- Test / Beispielgruppe (geteilt)
			testMode = false,
			testSize = 5,

			-- Layout + Position + TEXT PRO KONTEXT (Gruppengröße immer fest 5; nie gemischt).
			-- orientation: "vertical" = Mitglieder untereinander, Gruppen nebeneinander (Standard);
			--              "horizontal" = Mitglieder nebeneinander, Gruppen untereinander.
			-- raid = Schlachtzug (IsInRaid), party = 5er-Gruppe/Dungeon. Eigene Position UND
			-- eigene Text-Einstellungen je Kontext (Frames sind unterschiedlich groß).
			-- PRO KONTEXT bleiben nur größen-/positionsabhängige Felder + Anzeigen/Typ.
			-- Farbe/Umrandung von Name & HP liegen geteilt oben (Base).
			raid = {
				width = 114, height = 60, spacing = 6, orientation = "vertical",
				point = "CENTER", x = 0, y = -120,
				showName = true, nameSize = 12, namePoint = "TOPLEFT", nameX = 4, nameY = -3,
				healthTextType = "Aktuell", healthTextSize = 16, healthTextPoint = "CENTER",
				healthTextX = 0, healthTextY = 0,
			},
			party = {
				width = 114, height = 60, spacing = 6, orientation = "vertical",
				point = "CENTER", x = 0, y = -120,
				showName = true, nameSize = 12, namePoint = "TOPLEFT", nameX = 4, nameY = -3,
				healthTextType = "Aktuell", healthTextSize = 16, healthTextPoint = "CENTER",
				healthTextX = 0, healthTextY = 0,
			},

			-- Aura-Indikatoren (Icon-System; Phase 1: eigene HoTs). Das Layout (Anker,
			-- Wachstumsrichtung, Whitelist, Toggles) ist über raid/party GETEILT — nur die
			-- Icon-Größe ist kontextabhängig: autoFit leitet sie aus der Frame-Höhe ab,
			-- sonst greifen die expliziten sizeRaid/sizeParty. anchor = einer der 9
			-- WoW-Punkte (TOPLEFT…BOTTOMRIGHT); grow = RIGHT|LEFT|UP|DOWN.
			-- Drei Kategorien (HoTs/Defensives/Debuffs), je eigener Anker/Wachstum/Größe. Default:
			-- nur HoTs an, die übrigen aus + an verschiedene Ecken vorbelegt (kollisionsfrei beim Anschalten).
			-- Phase 2 (B2/B3): auras.whitelist[specID][spellID] = "hot"|"def" wird LAZY beim
			-- ersten Betreten einer Spec aus HOT_DEFAULTS ("hot") + DEF_DEFAULTS ("def") geseedet
			-- (Raidframes.lua, whitelistFor) — bewusst NICHT hier in den Defaults, damit der erste
			-- Schreib eine echte profil-eigene Tabelle erzeugt (kein Mutieren der geteilten Defaults).
			auras = {
				hotsOwn = {
					enabled = true,  spacing = 2, maxIcons = 5, autoFit = true, showSwipe = true, hideTooltips = false,
					anchorRaid = "BOTTOMLEFT", anchorParty = "BOTTOMLEFT", growRaid = "RIGHT", growParty = "RIGHT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
				},
				defensives = {
					enabled = false, spacing = 2, maxIcons = 3, autoFit = true, showSwipe = true, hideTooltips = false,
					anchorRaid = "TOPRIGHT", anchorParty = "TOPRIGHT", growRaid = "LEFT", growParty = "LEFT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
				},
				-- Major CDs (große Klassen-Cooldowns). Whitelist "major" (MAJOR_DEFAULTS,
				-- Raidframes.lua). Default-Anker TOPLEFT = die letzte freie Ecke (HoTs=BOTTOMLEFT,
				-- Defensives=TOPRIGHT, Debuffs=BOTTOMRIGHT) -> kollisionsfrei beim Anschalten.
				major = {
					enabled = false, spacing = 2, maxIcons = 3, autoFit = true, showSwipe = true, hideTooltips = false,
					anchorRaid = "TOPLEFT", anchorParty = "TOPLEFT", growRaid = "RIGHT", growParty = "RIGHT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
				},
				debuffs = {
					enabled = false, spacing = 2, maxIcons = 4, autoFit = true, showSwipe = true, hideTooltips = false,
					anchorRaid = "BOTTOMRIGHT", anchorParty = "BOTTOMRIGHT", growRaid = "LEFT", growParty = "LEFT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
					-- Blizzard-Standard-Filter: "raid" = nur raid-relevante Debuffs (wie Blizzards
					-- Default), "all" = alle, "dispellable" = nur selbst dispellbare.
					filterMode = "raid",
				},
			},
		},

		-- Click-Cast (cross-cutting: gilt für alle Unit-Buttons, perspektivisch auch
		-- Unit Frames/Nameplates). Bindings liegen PRO SPEC (Healer wechseln Specs).
		-- Eine frisch betretene Spec wird mit Links=Ziel/Rechts=Menü vorbelegt (siehe
		-- ClickCast.getSpec). Maus-Klick- UND Hovercast-Bindings in EINER Liste,
		-- getrennt über das Feld binding.hovercast.
		clickCast = {
			enabled     = false,
			helpfulOnly = true,   -- Spell-Auswahl auf hilfreiche (auf Freunde wirkbare) Zauber beschränken
			specs       = {},     -- [specID] = { { key=, type=, ... }, ... }
		},
	},

	-- Global (charakter-übergreifend, nicht profilgebunden): zur Laufzeit gelernte
	-- Aura-Signaturen pro Spec. Map [specID] = { ["1:0:1:0"] = spellID }. Wird außer
	-- Kampf passiv gefüllt (spellId dann lesbar) und persistiert -> im Kampf können wir
	-- secret-Auren über ihre Signatur identifizieren (Aura-Whitelist Phase 2). Siehe §10.8.
	global = {
		auraSigs = {},
	},
}

-- Defaults für andere Module sichtbar machen (Share/Import merged darauf, damit fehlende
-- Felder eines importierten Codes sauber mit Lumen-Standards aufgefüllt werden).
ns.Defaults = defaults

-- Name-/HP-Text-Felder, die pro Kontext (raid/party) liegen (für die Migration).
local TEXT_FIELDS = {
	"showName", "nameSize", "namePoint", "nameX", "nameY", "nameColor", "nameOutline",
	"healthTextType", "healthTextSize", "healthTextPoint", "healthTextX", "healthTextY",
	"healthTextColor", "healthTextOutline",
}
-- v3: Text-OPTIK (Farbe + Umrandung) wandert von raid/party zurück in die geteilte Ebene
-- (Geschmackswahl, für beide Kontexte gleich). Größe/Position/Anzeigen bleiben pro Kontext.
local SHARED_TEXT_FIELDS = { "nameColor", "nameOutline", "healthTextColor", "healthTextOutline" }

-- Einmalige Migration: alte flache Werte in raid + party übernehmen, damit bestehende
-- Profile beim Umstieg auf das Kontext-Modell nicht zurückgesetzt werden.
local function migrateLayout(rf)
	if not rf then return end
	-- v1: Layout/Position -> raid/party
	if not rf._layoutMigrated then
		rf._layoutMigrated = true
		if rf.width or rf.height or rf.spacing or rf.orientation or rf.point then
			for _, ctx in ipairs({ "raid", "party" }) do
				local t = rf[ctx]; if t then
					if rf.width       then t.width = rf.width end
					if rf.height      then t.height = rf.height end
					if rf.spacing     then t.spacing = rf.spacing end
					if rf.orientation then t.orientation = rf.orientation end
					if rf.point       then t.point = rf.point end
					if rf.x           then t.x = rf.x end
					if rf.y           then t.y = rf.y end
				end
			end
			rf.width, rf.height, rf.spacing, rf.orientation = nil, nil, nil, nil
			rf.point, rf.x, rf.y = nil, nil, nil
		end
	end
	-- v2: Name-/HP-Text -> raid/party (Farben tief kopieren, sonst teilen sich beide Kontexte
	-- dieselbe Tabelle).
	if not rf._textMigrated then
		rf._textMigrated = true
		local hasOld = false
		for _, k in ipairs(TEXT_FIELDS) do if rf[k] ~= nil then hasOld = true; break end end
		if hasOld then
			for _, ctx in ipairs({ "raid", "party" }) do
				local t = rf[ctx]
				if t then
					for _, k in ipairs(TEXT_FIELDS) do
						local v = rf[k]
						if v ~= nil then
							if type(v) == "table" then t[k] = { r = v.r, g = v.g, b = v.b } else t[k] = v end
						end
					end
				end
			end
			for _, k in ipairs(TEXT_FIELDS) do rf[k] = nil end
		end
	end
	-- v3: Text-Optik (Farbe/Umrandung) von raid/party -> geteilt. Quelle = raid (sonst party);
	-- bei bestehenden Profilen sind beide Kontexte ohnehin meist identisch.
	if not rf._textSharedMigrated then
		rf._textSharedMigrated = true
		local src = rf.raid or rf.party
		if src then
			-- src[k] liefert NUR einen Wert, wenn der Nutzer ihn pro Kontext angepasst hatte
			-- (raid-Defaults haben diese Felder nicht mehr). Kein rf[k]==nil-Guard: der würde
			-- wegen AceDBs Default-Metatable nie greifen und die Anpassung verwerfen.
			for _, k in ipairs(SHARED_TEXT_FIELDS) do
				local v = src[k]
				if v ~= nil then
					if type(v) == "table" then rf[k] = { r = v.r, g = v.g, b = v.b } else rf[k] = v end
				end
			end
		end
		for _, ctx in ipairs({ "raid", "party" }) do
			local t = rf[ctx]
			if t then for _, k in ipairs(SHARED_TEXT_FIELDS) do t[k] = nil end end
		end
	end
	-- v4: Aura-Platzierung (Anker/Wachstum) von geteilt -> pro Kontext (raid/party). Versatz X/Y
	-- + Innen/Außen sind neu (Default 0/innen). Bestehende geteilte anchor/grow auf BEIDE Kontexte
	-- hochziehen. pairs() trifft nur kategorie-Tabellen, die der Nutzer wirklich angefasst hat
	-- (Default-only-Kategorien brauchen nichts -> nutzen die neuen Defaults). Kein cat.x==nil-Guard
	-- nötig: anchor/grow gibt es in den neuen Defaults nicht mehr -> liefert nur gespeicherte Werte.
	if not rf._auraCtxMigrated then
		rf._auraCtxMigrated = true
		local au = rawget(rf, "auras")
		if au then
			for _, cat in pairs(au) do
				if type(cat) == "table" then
					local a, g = rawget(cat, "anchor"), rawget(cat, "grow")
					if a ~= nil then
						cat.anchorRaid = rawget(cat, "anchorRaid") or a
						cat.anchorParty = rawget(cat, "anchorParty") or a
						cat.anchor = nil
					end
					if g ~= nil then
						cat.growRaid = rawget(cat, "growRaid") or g
						cat.growParty = rawget(cat, "growParty") or g
						cat.grow = nil
					end
				end
			end
		end
	end
end

function Lumen:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("LumenDB", defaults, true)
	migrateLayout(self.db.profile.raidframes)
	if ns.SetupOptions then ns.SetupOptions() end

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshAll")
	self.db.RegisterCallback(self, "OnProfileCopied",  "RefreshAll")
	self.db.RegisterCallback(self, "OnProfileReset",   "RefreshAll")

	self:RegisterChatCommand("lumen", "OpenConfig")
	self:RegisterChatCommand("lu",    "OpenConfig")

	self:Print("geladen. |cffD4A34F/lumen|r öffnet die Einstellungen.")
end

function Lumen:OnEnable()
	if ns.Raidframes then
		ns.Raidframes:Setup()
		if self.db.profile.raidframes.enabled then
			ns.Raidframes:Enable()
		end
	end
end

function Lumen:RefreshAll()
	if not ns.Raidframes then return end
	migrateLayout(self.db.profile.raidframes)
	if self.db.profile.raidframes.enabled then
		ns.Raidframes:Enable()
		ns.Raidframes:UpdateLayout()
	else
		ns.Raidframes:Disable()
	end
	-- Profilwechsel: Click-Cast-Bindings neu anwenden (Bindings sind profilgebunden).
	if ns.ClickCast then ns.ClickCast:ApplyBindings() end
	-- Ist die Suite-Shell offen, ihre Controls auf die (ggf. neuen) Profilwerte ziehen.
	if ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown() then
		ns.Shell:RenderContent(true)
	end
end

function Lumen:OpenConfig(input)
	-- /lumen     -> Suite-Shell (Hauptoberfläche; auch der ESC-Menü-Button)
	-- /lumen ace -> klassische AceConfig (Backup, parallel bestehen lassen)
	local arg = input and input:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	if arg == "ace" then
		LibStub("AceConfigDialog-3.0"):Open("Lumen")
		return
	end
	if ns.Shell then ns.Shell:Toggle() else LibStub("AceConfigDialog-3.0"):Open("Lumen") end
end
