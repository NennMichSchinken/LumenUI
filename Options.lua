local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Options (funktionale Ace-Oberfläche; eigene Shell kommt später).
-- ===========================================================================

local POINTS = {
	TOPLEFT = "Oben links", TOP = "Oben", TOPRIGHT = "Oben rechts",
	LEFT = "Links", CENTER = "Mitte", RIGHT = "Rechts",
	BOTTOMLEFT = "Unten links", BOTTOM = "Unten", BOTTOMRIGHT = "Unten rechts",
}

function ns.SetupOptions()
	local L = ns.Lumen

	local function rf() return L.db.profile.raidframes end
	local function getRF(info) return rf()[info[#info]] end
	local function setRF(info, val)
		rf()[info[#info]] = val
		if ns.Raidframes then ns.Raidframes:UpdateLayout() end
	end
	local function getColor(info)
		local c = rf()[info[#info]] or {}
		return c.r or 1, c.g or 1, c.b or 1
	end
	local function setColor(info, r, g, b)
		rf()[info[#info]] = { r = r, g = g, b = b }
		if ns.Raidframes then ns.Raidframes:UpdateLayout() end
	end

	local options = {
		type = "group", name = "Lumen", childGroups = "tree",
		args = {
			intro = {
				type = "description", order = 0, fontSize = "large",
				name = "|cffD4A34FLumen|r — a focused UI suite\n",
			},

			-- ---- Allgemein -------------------------------------------------
			general = {
				type = "group", name = "Allgemein", order = 1,
				args = {
					about = {
						type = "description", order = 1,
						name = "Zentrale Profile liegen unter |cffD4A34FProfile|r. " ..
						       "Export/Import (granular pro Modul) folgt später.\n",
					},
					moveHead = { type = "header", order = 5, name = "Verschieben (Edit-Modus)" },
					editMode = {
						type = "toggle", order = 6, width = "full",
						name = "Rahmen entsperren — zeigt alle beweglichen Lumen-Elemente",
						get = function() return ns.EditMode and ns.EditMode:IsActive() end,
						set = function(_, v) if ns.EditMode then ns.EditMode:Toggle(v) end end,
					},
					resetPos = {
						type = "execute", order = 7, name = "Positionen zurücksetzen",
						func = function()
							local d = rf()
							d.point, d.x, d.y = "CENTER", 0, -120
							if ns.Raidframes then ns.Raidframes:UpdateLayout() end
						end,
					},
					moveInfo = {
						type = "description", order = 8,
						name = "|cff888888Funktioniert auch über WoWs eigenen Edit-Modus: Lumen-Rahmen werden dort beweglich angezeigt.|r",
					},
				},
			},

			-- ---- Raidframes ------------------------------------------------
			raidframes = {
				type = "group", name = "Raidframes", order = 10,
				get = getRF, set = setRF,
				args = {
					enabled = {
						type = "toggle", order = 1, name = "Aktiviert", width = "full",
						get = function() return rf().enabled end,
						set = function(_, v)
							rf().enabled = v
							if v then ns.Raidframes:Enable() else ns.Raidframes:Disable() end
						end,
					},

					sizeHead = { type = "header", order = 10, name = "Größe" },
					width  = { type = "range", order = 11, name = "Breite",  min = 40, max = 240, step = 1 },
					height = { type = "range", order = 12, name = "Höhe",    min = 20, max = 160, step = 1 },
					spacing= { type = "range", order = 13, name = "Abstand", min = 0,  max = 30,  step = 1 },
					unitsPerColumn = {
						type = "range", order = 14, name = "Einheiten pro Spalte",
						min = 1, max = 40, step = 1,
					},

					barHead = { type = "header", order = 20, name = "Lebensbalken" },
					healthTexture = {
						type = "select", order = 21, name = "Balken-Textur",
						values = function() return ns.Raidframes:TextureValues() end,
					},
					useClassColor = { type = "toggle", order = 22, name = "Klassenfarbe als Füllfarbe" },
					fillColor = {
						type = "color", order = 23, name = "Füllfarbe (wenn nicht Klassenfarbe)",
						get = getColor, set = setColor,
						disabled = function() return rf().useClassColor end,
					},
					healPrediction = { type = "toggle", order = 24, name = "Heilvorhersage (eingehende Heilung)" },
					dispelRecolor = {
						type = "toggle", order = 25, width = "full",
						name = "Dispel-Umfärbung des Pools (Magie/Fluch/Krankheit/Gift)",
					},


					nameHead = { type = "header", order = 40, name = "Text — Name" },
					showName = { type = "toggle", order = 41, name = "Name anzeigen" },
					nameColor = { type = "color", order = 42, name = "Namensfarbe", get = getColor, set = setColor },
					nameSize  = { type = "range", order = 43, name = "Namensgröße", min = 6, max = 30, step = 1 },
					namePoint = { type = "select", order = 44, name = "Namensposition", values = POINTS },
					nameX = { type = "range", order = 45, name = "Name X-Versatz", min = -40, max = 40, step = 1 },
					nameY = { type = "range", order = 46, name = "Name Y-Versatz", min = -40, max = 40, step = 1 },

					htHead = { type = "header", order = 50, name = "Text — HP-Anzeige" },
					healthTextType = {
						type = "select", order = 51, name = "HP-Text",
						values = { Keine = "Keine", Aktuell = "Aktuell", Prozent = "Prozent" },
					},
					htInfo = {
						type = "description", order = 51.5,
						name = "|cff888888Live zeigt WoW (12.0) secret-bedingt die aktuelle HP; exaktes Prozent im Testmodus. Weitere HP-Text-Optionen folgen.|r",
					},
					healthTextColor = { type = "color", order = 52, name = "HP-Textfarbe", get = getColor, set = setColor },
					healthTextSize  = { type = "range", order = 53, name = "HP-Textgröße", min = 6, max = 30, step = 1 },
					healthTextPoint = { type = "select", order = 54, name = "HP-Textposition", values = POINTS },
					healthTextX = { type = "range", order = 55, name = "HP-Text X-Versatz", min = -40, max = 40, step = 1 },
					healthTextY = { type = "range", order = 56, name = "HP-Text Y-Versatz", min = -40, max = 40, step = 1 },

					testHead = { type = "header", order = 60, name = "Test / Beispielgruppe" },
					testMode = {
						type = "toggle", order = 61, width = "full",
						name = "Testmodus — Beispielgruppe anzeigen (zum Designen, ohne echte Gruppe)",
					},
					testSize = {
						type = "select", order = 62, name = "Test-Gruppengröße",
						values = { [5] = "5er (Party)", [20] = "20er (Raid)", [40] = "40er" },
						disabled = function() return not rf().testMode end,
					},
				},
			},
		},
	}

	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(L.db)
	profiles.order = 2
	profiles.name = "Profile"
	options.args.profiles = profiles

	LibStub("AceConfig-3.0"):RegisterOptionsTable("Lumen", options)
	LibStub("AceConfigDialog-3.0"):SetDefaultSize("Lumen", 600, 520)
end
