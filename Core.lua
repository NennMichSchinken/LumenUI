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

			-- Größe / Layout
			width          = 114,
			height         = 60,
			spacing        = 6,
			unitsPerColumn = 5,

			-- Lebensbalken
			healthTexture  = "Lumen Gradient",
			useClassColor  = true,
			fillColor      = { r = 0.20, g = 0.60, b = 0.30 },
			healPrediction = true,

			-- Schilde (eigene Texturen, immer sichtbar bei Schild)
			absorbStyle     = "Blizzard",         -- Blizzard | Flach
			healAbsorbStyle = "Blizzard",         -- Blizzard | Flach
			healAbsorbColor = { r = 1, g = 1, b = 1 },

			-- Text: Name
			showName   = true,
			nameSize   = 12,
			namePoint  = "TOPLEFT",
			nameX      = 4,
			nameY      = -3,
			nameColor  = { r = 1, g = 1, b = 1 },

			-- Text: HP-Anzeige
			healthTextType  = "Aktuell",          -- Keine/Aktuell/Prozent
			healthTextSize  = 16,
			healthTextPoint = "CENTER",
			healthTextX     = 0,
			healthTextY     = 0,
			healthTextColor = { r = 1, g = 1, b = 1 },

			-- Dispel
			dispelRecolor = true,

			-- Position (Verschieben über globalen Edit-Modus, siehe Allgemein)
			point = "CENTER",
			x     = 0,
			y     = -120,

			-- Test / Beispielgruppe
			testMode = false,
			testSize = 5,
		},
	},
}

function Lumen:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("LumenDB", defaults, true)
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
	if self.db.profile.raidframes.enabled then
		ns.Raidframes:Enable()
		ns.Raidframes:UpdateLayout()
	else
		ns.Raidframes:Disable()
	end
end

function Lumen:OpenConfig()
	LibStub("AceConfigDialog-3.0"):Open("Lumen")
end
