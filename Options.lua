local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Options (funktionale Ace-Oberfläche; eigene Shell kommt später).
-- ===========================================================================

local POINTS = {
	TOPLEFT = "Oben links", TOP = "Oben", TOPRIGHT = "Oben rechts",
	LEFT = "Links", CENTER = "Mitte", RIGHT = "Rechts",
	BOTTOMLEFT = "Unten links", BOTTOM = "Unten", BOTTOMRIGHT = "Unten rechts",
}

local OUTLINES = {
	none    = "Keine",
	outline = "Outline",
	thick   = "Dicker Outline",
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
	-- Dispel-Farben liegen verschachtelt in rf().dispelColors[<Typ>]
	local DISPEL_KEYS = { dispelMagic = "Magic", dispelCurse = "Curse", dispelDisease = "Disease", dispelPoison = "Poison" }
	local function getDispelColor(info)
		local c = (rf().dispelColors and rf().dispelColors[DISPEL_KEYS[info[#info]]]) or {}
		return c.r or 1, c.g or 1, c.b or 1
	end
	local function setDispelColor(info, r, g, b)
		rf().dispelColors = rf().dispelColors or {}
		rf().dispelColors[DISPEL_KEYS[info[#info]]] = { r = r, g = g, b = b }
		if ns.Raidframes then ns.Raidframes:UpdateLayout() end
	end
	-- Layout-Werte liegen PRO KONTEXT in rf().raid bzw. rf().party.
	local function ctxGetSet(ctxKey)
		local function get(info) local t = rf()[ctxKey] or {}; return t[info[#info]] end
		local function set(info, val)
			rf()[ctxKey] = rf()[ctxKey] or {}
			rf()[ctxKey][info[#info]] = val
			if ns.Raidframes then ns.Raidframes:UpdateLayout() end
		end
		return get, set
	end
	local getRaid, setRaid   = ctxGetSet("raid")
	local getGroup, setGroup = ctxGetSet("party")
	-- Kontext-bewusste Farb-Get/Set (Farben liegen verschachtelt in rf().<ctx>[key]).
	local function ctxColorGetSet(ctxKey)
		local function get(info) local c = (rf()[ctxKey] or {})[info[#info]] or {}; return c.r or 1, c.g or 1, c.b or 1 end
		local function set(info, r, g, b)
			rf()[ctxKey] = rf()[ctxKey] or {}
			rf()[ctxKey][info[#info]] = { r = r, g = g, b = b }
			if ns.Raidframes then ns.Raidframes:UpdateLayout() end
		end
		return get, set
	end
	local raidColGet, raidColSet   = ctxColorGetSet("raid")
	local groupColGet, groupColSet = ctxColorGetSet("party")

	-- Layout- + Text-Optionen (Raid- und Group-Tab identisch; Text pro Kontext, da Frames
	-- unterschiedlich groß sind). colGet/colSet binden die Farb-Picker an den Kontext.
	-- Frische Tabelle je Aufruf.
	local function layoutArgs(colGet, colSet)
		return {
			sizeHead = { type = "header", order = 10, name = "Größe & Anordnung" },
			width  = { type = "range", order = 11, name = "Breite",  min = 40, max = 240, step = 1 },
			height = { type = "range", order = 12, name = "Höhe",    min = 20, max = 160, step = 1 },
			spacing= { type = "range", order = 13, name = "Abstand", min = 0,  max = 30,  step = 1 },
			orientation = {
				type = "select", order = 14, name = "Ausrichtung",
				desc = "Gruppen sind immer fest 5 Einheiten (Raid-Gruppen & Dungeon).",
				values = {
					vertical   = "Vertikal — Mitglieder untereinander, Gruppen nebeneinander (Standard)",
					horizontal = "Horizontal — Mitglieder nebeneinander, Gruppen untereinander",
				},
			},
			posInfo = {
				type = "description", order = 20,
				name = "|cff888888Position: über „Rahmen entsperren“ im |cffD4A34FGlobal|r|cff888888-Tab bzw. WoWs Edit-Modus verschieben. Raid und Group haben getrennte Positionen.|r",
			},

			nameHead  = { type = "header", order = 40, name = "Text — Name" },
			showName  = { type = "toggle", order = 41, name = "Name anzeigen" },
			nameColor = { type = "color", order = 42, name = "Namensfarbe", get = colGet, set = colSet },
			nameSize  = { type = "range", order = 43, name = "Namensgröße", min = 6, max = 30, step = 1 },
			nameOutline = { type = "select", order = 43.5, name = "Namens-Umrandung", values = OUTLINES },
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
				name = "|cff888888Live zeigt WoW (12.0) secret-bedingt die aktuelle HP; exaktes Prozent im Testmodus.|r",
			},
			healthTextColor = { type = "color", order = 52, name = "HP-Textfarbe", get = colGet, set = colSet },
			healthTextSize  = { type = "range", order = 53, name = "HP-Textgröße", min = 6, max = 30, step = 1 },
			healthTextOutline = { type = "select", order = 53.5, name = "HP-Text-Umrandung", values = OUTLINES },
			healthTextPoint = { type = "select", order = 54, name = "HP-Textposition", values = POINTS },
			healthTextX = { type = "range", order = 55, name = "HP-Text X-Versatz", min = -40, max = 40, step = 1 },
			healthTextY = { type = "range", order = 56, name = "HP-Text Y-Versatz", min = -40, max = 40, step = 1 },
		}
	end

	local options = {
		type = "group", name = "Lumen", childGroups = "tree",
		args = {
			intro = {
				type = "description", order = 0, fontSize = "large",
				name = "|cffD4A34FLumen|r — a focused UI suite\n",
			},

			-- ---- Global (suite-weit) ---------------------------------------
			general = {
				type = "group", name = "Global", order = 1,
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
							for _, ctx in ipairs({ "raid", "party" }) do
								local t = d[ctx]
								if t then t.point, t.x, t.y = "CENTER", 0, -120 end
							end
							if ns.Raidframes then ns.Raidframes:UpdateLayout() end
						end,
					},
					moveInfo = {
						type = "description", order = 8,
						name = "|cff888888Funktioniert auch über WoWs eigenen Edit-Modus: Lumen-Rahmen werden dort beweglich angezeigt.|r",
					},
				},
			},

			-- ---- Raidframes (Tabs: Base | Raid | Group) --------------------
			raidframes = {
				type = "group", name = "Raidframes", order = 10, childGroups = "tab",
				args = {
				base = {
					type = "group", name = "Base", order = 1,
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
					dispelHead = { type = "header", order = 25, name = "Dispel-Anzeige" },
					dispelEnabled = {
						type = "toggle", order = 25.1, width = "full",
						name = "Dispellbare Debuffs hervorheben (secret-sicher, auch im Kampf)",
					},
					dispelMode = {
						type = "select", order = 25.2, name = "Darstellung",
						values = {
							recolor = "Lebensbalken einfärben",
							overlay = "Rand + Overlay (Klassenfarbe bleibt)",
						},
						disabled = function() return not rf().dispelEnabled end,
					},
					dispelShowAll = {
						type = "toggle", order = 25.3, name = "Alle dispellbaren zeigen (nicht nur eigene)",
						disabled = function() return not rf().dispelEnabled end,
					},
					dispelAlpha = {
						type = "range", order = 25.4, name = "Overlay-Deckkraft", min = 0, max = 1, step = 0.05, isPercent = true,
						disabled = function() return not rf().dispelEnabled or rf().dispelMode ~= "overlay" end,
					},
					dispelMagic   = { type = "color", order = 25.5, name = "Farbe: Magie",     get = getDispelColor, set = setDispelColor, disabled = function() return not rf().dispelEnabled end },
					dispelCurse   = { type = "color", order = 25.6, name = "Farbe: Fluch",     get = getDispelColor, set = setDispelColor, disabled = function() return not rf().dispelEnabled end },
					dispelDisease = { type = "color", order = 25.7, name = "Farbe: Krankheit", get = getDispelColor, set = setDispelColor, disabled = function() return not rf().dispelEnabled end },
					dispelPoison  = { type = "color", order = 25.8, name = "Farbe: Gift",      get = getDispelColor, set = setDispelColor, disabled = function() return not rf().dispelEnabled end },

					-- (Name-/HP-Text-Optionen liegen jetzt PRO KONTEXT in den Tabs Raid & Group.)

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
				raid = {
					type = "group", name = "Raid", order = 2,
					get = getRaid, set = setRaid,
					args = layoutArgs(raidColGet, raidColSet),
				},
				group = {
					type = "group", name = "Group", order = 3,
					get = getGroup, set = setGroup,
					args = layoutArgs(groupColGet, groupColSet),
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
