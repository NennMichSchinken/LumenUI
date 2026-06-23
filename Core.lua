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

			-- Test / Beispielgruppe (geteilt)
			testMode = false,
			testSize = 5,

			-- Layout + Position + TEXT PRO KONTEXT (Gruppengröße immer fest 5; nie gemischt).
			-- orientation: "vertical" = Mitglieder untereinander, Gruppen nebeneinander (Standard);
			--              "horizontal" = Mitglieder nebeneinander, Gruppen untereinander.
			-- raid = Schlachtzug (IsInRaid), party = 5er-Gruppe/Dungeon. Eigene Position UND
			-- eigene Text-Einstellungen je Kontext (Frames sind unterschiedlich groß).
			raid = {
				width = 114, height = 60, spacing = 6, orientation = "vertical",
				point = "CENTER", x = 0, y = -120,
				showName = true, nameSize = 12, namePoint = "TOPLEFT", nameX = 4, nameY = -3,
				nameColor = { r = 1, g = 1, b = 1 }, nameOutline = "outline",
				healthTextType = "Aktuell", healthTextSize = 16, healthTextPoint = "CENTER",
				healthTextX = 0, healthTextY = 0, healthTextColor = { r = 1, g = 1, b = 1 }, healthTextOutline = "outline",
			},
			party = {
				width = 114, height = 60, spacing = 6, orientation = "vertical",
				point = "CENTER", x = 0, y = -120,
				showName = true, nameSize = 12, namePoint = "TOPLEFT", nameX = 4, nameY = -3,
				nameColor = { r = 1, g = 1, b = 1 }, nameOutline = "outline",
				healthTextType = "Aktuell", healthTextSize = 16, healthTextPoint = "CENTER",
				healthTextX = 0, healthTextY = 0, healthTextColor = { r = 1, g = 1, b = 1 }, healthTextOutline = "outline",
			},

			-- Aura-Indikatoren (Icon-System; Phase 1: eigene HoTs). Das Layout (Anker,
			-- Wachstumsrichtung, Whitelist, Toggles) ist über raid/party GETEILT — nur die
			-- Icon-Größe ist kontextabhängig: autoFit leitet sie aus der Frame-Höhe ab,
			-- sonst greifen die expliziten sizeRaid/sizeParty. anchor = einer der 9
			-- WoW-Punkte (TOPLEFT…BOTTOMRIGHT); grow = RIGHT|LEFT|UP|DOWN.
			-- Vier Kategorien, je eigener Anker/Wachstum/Größe. Default: nur eigene HoTs an,
			-- die übrigen aus + an verschiedene Ecken vorbelegt (kollidieren nicht beim Anschalten).
			auras = {
				hotsOwn = {
					enabled = true,  anchor = "BOTTOMLEFT", grow = "RIGHT", spacing = 2, maxIcons = 5,
					autoFit = true,  sizeRaid = 16, sizeParty = 22, showSwipe = true, hideTooltips = false,
				},
				hotsOther = {
					enabled = false, anchor = "TOPLEFT", grow = "RIGHT", spacing = 2, maxIcons = 4,
					autoFit = true,  sizeRaid = 14, sizeParty = 20, showSwipe = true, hideTooltips = false,
				},
				defensives = {
					enabled = false, anchor = "TOPRIGHT", grow = "LEFT", spacing = 2, maxIcons = 3,
					autoFit = true,  sizeRaid = 16, sizeParty = 22, showSwipe = true, hideTooltips = false,
				},
				debuffs = {
					enabled = false, anchor = "BOTTOMRIGHT", grow = "LEFT", spacing = 2, maxIcons = 4,
					autoFit = true,  sizeRaid = 16, sizeParty = 22, showSwipe = true, hideTooltips = false,
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
end

function Lumen:OpenConfig()
	LibStub("AceConfigDialog-3.0"):Open("Lumen")
end
