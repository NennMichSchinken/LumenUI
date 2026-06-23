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

	-- ===== Click-Cast: dynamische Binding-Zeilen =================================
	local AceRegistry = LibStub("AceConfigRegistry-3.0", true)
	local function ccRefresh() if AceRegistry then AceRegistry:NotifyChange("Lumen") end end
	local function CC() return ns.ClickCast end
	local function ccApply() if CC() then CC():ApplyBindings() end end
	local rebuildCC   -- vorwärts deklariert (buildRow.remove ruft es vor der Definition)

	local selectedSpec        -- welche Spec bearbeitet wird (entkoppelt von der Live-Spec)
	local allSpells = {}      -- volle Spell-Liste der Klasse (mit Icon), je Rebuild frisch
	local searchText = {}     -- [binding] = Suchtext (transient, nicht im Profil gespeichert)

	local function refreshSpellList()
		wipe(allSpells)
		if not CC() then return end
		for _, s in ipairs(CC():GetClassSpells()) do allSpells[#allSpells + 1] = s end
	end
	local function iconText(icon, name)
		if icon then return "|T" .. icon .. ":16:16:0:0|t " .. (name or "") end
		return name or ""
	end
	local function helpfulOnly() return L.db.profile.clickCast.helpfulOnly end
	-- Trifft ein Spell den Filter (Hilfreich-Toggle + Suchtext)?
	local function spellMatches(s, q)
		if helpfulOnly() and not s.friendly then return false end
		return q == "" or s.name:lower():find(q, 1, true) ~= nil
	end

	local function bindingIndex(b)
		if not CC() then return nil end
		for i, x in ipairs(CC():GetBindings(selectedSpec)) do if x == b then return i end end
	end
	local function actionLabel(b)
		if b.type == "spell" then return b.spell or "|cff888888Spell wählen…|r" end
		return (CC() and CC().BINDING_TYPES[b.type]) or b.type or "?"
	end
	local function rowName(b)
		local k = CC() and CC():FormatKey(b.key) or (b.key or "—")
		return k .. "  |cffD4A34F→|r  " .. actionLabel(b)
	end

	local ccArgs = {}   -- in-place gehaltene args des Click-Cast-Knotens

	local function buildRow(b, isHover, order)
		local a = {}
		if isHover then
			-- Hovercast = Tastatur -> keybinding-Widget (drücke Taste).
			a.key = {
				type = "keybinding", order = 1, name = "Taste", width = 1.0,
				get = function() return b.key end,
				set = function(_, v) b.key = v; ccApply(); ccRefresh() end,
			}
		else
			-- Klick = Maustaste (Dropdown) + optionaler Modifier (Schalter + Auswahl).
			a.mousebtn = {
				type = "select", order = 1, name = "Maustaste", width = 1.0,
				values = CC().MOUSE_BUTTON_VALUES, sorting = CC().MOUSE_BUTTON_SORTING,
				get = function() local _, btn = CC():KeyParts(b.key); return (btn ~= "" and btn) or "BUTTON1" end,
				set = function(_, v) local mod = CC():KeyParts(b.key); b.key = CC():BuildKey(mod, v); ccApply(); ccRefresh() end,
			}
			a.usemod = {
				type = "toggle", order = 1.1, name = "Modifier", width = 0.6,
				desc = "Zusatztaste (Shift/Strg/Alt) verlangen.",
				get = function() local mod = CC():KeyParts(b.key); return mod ~= "" end,
				set = function(_, v)
					local _, btn = CC():KeyParts(b.key)
					b.key = CC():BuildKey(v and "SHIFT" or "", (btn ~= "" and btn) or "BUTTON1")
					ccApply(); ccRefresh()
				end,
			}
			a.mod = {
				type = "select", order = 1.2, name = "", width = 0.7,
				values = CC().MOD_VALUES, sorting = CC().MOD_SORTING,
				hidden = function() local mod = CC():KeyParts(b.key); return mod == "" end,
				get = function() local mod = CC():KeyParts(b.key); return (mod ~= "" and mod) or "SHIFT" end,
				set = function(_, v) local _, btn = CC():KeyParts(b.key); b.key = CC():BuildKey(v, (btn ~= "" and btn) or "BUTTON1"); ccApply(); ccRefresh() end,
			}
		end
		a.btype = {
			type = "select", order = 2, name = "Aktion", width = 0.9,
			values = CC().BINDING_TYPES,
			get = function() return b.type end,
			set = function(_, v) b.type = v; ccApply(); ccRefresh() end,
		}
		-- Spell-Suche (filtert das Dropdown) — nur bei Aktion „Spell".
		a.spellSearch = {
			type = "input", order = 2.9, name = "Spell suchen", width = 1.0,
			hidden = function() return b.type ~= "spell" end,
			get = function() return searchText[b] or "" end,
			set = function(_, v) searchText[b] = v; ccRefresh() end,
		}
		a.spell = {
			type = "select", order = 3, name = "Spell", width = 1.4,
			hidden = function() return b.type ~= "spell" end,
			values = function()
				local q = (searchText[b] or ""):lower()
				local t = {}
				for _, s in ipairs(allSpells) do
					if spellMatches(s, q) then t[s.id] = iconText(s.icon, s.name) end
				end
				if b.spellID and not t[b.spellID] then t[b.spellID] = iconText(nil, b.spell) end
				return t
			end,
			sorting = function()
				local q = (searchText[b] or ""):lower()
				local t = {}
				local selPresent = false
				for _, s in ipairs(allSpells) do
					if spellMatches(s, q) then
						if s.id == b.spellID then selPresent = true end
						t[#t + 1] = s.id
					end
				end
				if b.spellID and not selPresent then table.insert(t, 1, b.spellID) end
				return t
			end,
			get = function() return b.spellID end,
			set = function(_, v)
				b.spellID = v
				for _, s in ipairs(allSpells) do if s.id == v then b.spell = s.name; break end end
				ccApply(); ccRefresh()
			end,
		}
		a.ooc = {
			type = "toggle", order = 4, name = "Nur OOC", width = 0.6,
			desc = "Nur außerhalb des Kampfes auslösen.",
			hidden = function() return b.type == "target" or b.type == "menu" end,
			get = function() return b.oocOnly end,
			set = function(_, v) b.oocOnly = v; ccApply() end,
		}
		if isHover then
			a.friendly = {
				type = "toggle", order = 5, name = "Freund", width = 0.6,
				hidden = function() return b.type ~= "spell" end,
				get = function() return b.hoverFriendly end,
				set = function(_, v) b.hoverFriendly = v; ccApply() end,
			}
			a.enemy = {
				type = "toggle", order = 6, name = "Feind", width = 0.6,
				hidden = function() return b.type ~= "spell" end,
				get = function() return b.hoverEnemy end,
				set = function(_, v) b.hoverEnemy = v; ccApply() end,
			}
		end
		a.remove = {
			type = "execute", order = 7, name = "Entfernen", width = 0.7,
			func = function() local i = bindingIndex(b); if i and CC() then CC():RemoveBinding(selectedSpec, i) end; rebuildCC(); ccRefresh() end,
		}
		return { type = "group", inline = true, order = order, name = function() return rowName(b) end, args = a }
	end

	rebuildCC = function()
		wipe(ccArgs)
		refreshSpellList()
		if selectedSpec == nil and CC() then selectedSpec = CC():CurrentSpecID() end
		local cc = L.db.profile.clickCast
		ccArgs.enabled = {
			type = "toggle", order = 1, width = "full", name = "Click-Cast aktiviert",
			desc = "Übernimmt die Klicks auf die Raidframe-Buttons. Aus = WoW-Standard (Links=Ziel, Rechts=Menü).",
			get = function() return cc.enabled end,
			set = function(_, v) cc.enabled = v; ccApply(); rebuildCC(); ccRefresh() end,
		}
		-- Spec-Auswahl: entkoppelt von der Live-Spec, damit man jede Spec hier bearbeiten kann.
		ccArgs.specSel = {
			type = "select", order = 3, name = "Spec (bearbeiten)", width = "double",
			desc = "Wähle, welche Spec du hier bearbeitest. Im Spiel gelten automatisch die Bindings deiner aktiven Spec.",
			disabled = function() return not cc.enabled end,
			values = function()
				local t = {}
				if CC() then for _, s in ipairs(CC():GetSpecList()) do t[s.id] = iconText(s.icon, s.name) end end
				return t
			end,
			sorting = function()
				local t = {}
				if CC() then for _, s in ipairs(CC():GetSpecList()) do t[#t + 1] = s.id end end
				return t
			end,
			get = function() return selectedSpec end,
			set = function(_, v) selectedSpec = v; rebuildCC(); ccRefresh() end,
		}
		ccArgs.specInfo = {
			type = "description", order = 4,
			name = function()
				return "|cff888888Aktive Spec im Spiel: |r|cffD4A34F" .. (CC() and CC():CurrentSpecName() or "?") .. "|r"
			end,
		}
		if not cc.enabled then return end

		ccArgs.helpfulOnly = {
			type = "toggle", order = 5, width = "full",
			name = "Nur hilfreiche Zauber zur Auswahl anzeigen",
			desc = "Beschränkt die Spell-Liste auf Zauber, die du auf dich/Verbündete wirken kannst (Heils, Schilde, Dispels, Rez …). Aus = alle Zauber.",
			get = function() return cc.helpfulOnly end,
			set = function(_, v) cc.helpfulOnly = v; ccRefresh() end,
		}

		local bindings = CC() and CC():GetBindings(selectedSpec) or {}
		ccArgs.clickHead = { type = "header", order = 10, name = "Klick auf Frame" }
		local o = 11
		for _, b in ipairs(bindings) do
			if not b.hovercast then ccArgs["row" .. o] = buildRow(b, false, o); o = o + 1 end
		end
		ccArgs.addClick = {
			type = "execute", order = 400, name = "Klick-Binding hinzufügen",
			func = function() if CC() then CC():AddBinding(selectedSpec, { key = "BUTTON3", type = "spell" }) end; rebuildCC(); ccRefresh() end,
		}

		ccArgs.hoverHead = { type = "header", order = 500, name = "Hovercast (Mouseover)" }
		ccArgs.hoverInfo = {
			type = "description", order = 501,
			name = "|cff888888Taste drücken, während die Maus über einer Unit schwebt — der Spell geht auf die gehoverte Unit, ohne Klick. Die Taste wirkt nur beim Hovern; sonst macht sie ihr normales Ding.|r",
		}
		o = 510
		for _, b in ipairs(bindings) do
			if b.hovercast then ccArgs["row" .. o] = buildRow(b, true, o); o = o + 1 end
		end
		ccArgs.addHover = {
			type = "execute", order = 900, name = "Hovercast-Taste hinzufügen",
			func = function() if CC() then CC():AddBinding(selectedSpec, { hovercast = true, type = "spell", hoverFriendly = true }) end; rebuildCC(); ccRefresh() end,
		}
	end
	rebuildCC()

	-- QoL: bei Spec-Wechsel im Spiel die bearbeitete Spec automatisch auf die jetzt
	-- aktive umstellen (manuelle Auswahl im Dropdown gilt bis zum nächsten Wechsel).
	local specWatcher = CreateFrame("Frame")
	specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	specWatcher:SetScript("OnEvent", function()
		if CC() then selectedSpec = CC():CurrentSpecID() end
		rebuildCC(); ccRefresh()
	end)

	-- ===== Share (Export / Import) — Zustand für den Profile-Tab =================
	local shareExport   = ""     -- zuletzt erzeugter Export-Code
	local shareImportRaw = ""    -- eingefügter Text
	local importPayload  = nil   -- dekodierter Code (oder nil)
	local importErr      = nil   -- Fehlertext (oder nil)
	local importSel      = {}    -- [modKey] = bool (was übernommen wird)
	local importLayout   = false -- Layout-Positionen mitimportieren?

	local options = {
		type = "group", name = "Lumen", childGroups = "tree",
		args = {
			intro = {
				type = "description", order = 0, fontSize = "large",
				name = "|cffD4A34FLumen|r — a focused UI suite\n",
			},

			-- ---- Global (suite-weit; Tabs: Base | Profile) -----------------
			general = {
				type = "group", name = "Global", order = 1, childGroups = "tab",
				args = {
					base = {
						type = "group", name = "Base", order = 1,
						args = {
							about = {
								type = "description", order = 1,
								name = "Zentrale Profile liegen im Tab |cffD4A34FProfile|r. " ..
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
					-- profile-Tab wird unten nach dem Bau der AceDBOptions eingehängt.
				},
			},

			-- ---- Click-Cast (eigener Knoten; dynamische Binding-Zeilen) -----
			clickcast = {
				type = "group", name = "Click-Cast", order = 2,
				args = ccArgs,
			},

			-- ---- Raidframes (Tabs: Base | Raid | Group) --------------------
			raidframes = {
				type = "group", name = "Raidframes", order = 3, childGroups = "tab",
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

	-- Profile sind globale Einstellungen -> als Tab IN den Global-Knoten.
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(L.db)
	profiles.order = 2
	profiles.name = "Profile"
	options.args.general.args.profile = profiles

	-- ----- Share (Export / Import) unten in den Profile-Tab ---------------------
	local function Share() return ns.Share end
	local pa = profiles.args

	pa.shareHeader = { type = "header", order = 100, name = "Teilen — Export / Import" }
	pa.shareDesc = {
		type = "description", order = 101,
		name = "Exportiere dein komplettes Lumen-Setup als Code oder übernimm den Code von jemand anderem — granular pro Modul.\n",
	}

	-- Export
	pa.exportBtn = {
		type = "execute", order = 110, name = "Export-Code erzeugen",
		func = function()
			shareExport = (Share() and Share():Export()) or ""
			ccRefresh()
		end,
	}
	pa.exportBox = {
		type = "input", order = 111, multiline = 6, width = "full",
		name = "Export-Code  |cff888888(Feld anklicken, Strg+A, Strg+C)|r",
		hidden = function() return shareExport == "" end,
		get = function() return shareExport end,
		set = function() end,   -- nur lesen
	}

	-- Import
	pa.importBox = {
		type = "input", order = 120, multiline = 6, width = "full",
		name = "Import-Code hier einfügen",
		get = function() return shareImportRaw end,
		set = function(_, v)
			shareImportRaw = v or ""
			importPayload, importErr = nil, nil
			wipe(importSel)
			importLayout = false
			if Share() and shareImportRaw:gsub("%s+", "") ~= "" then
				local p, err = Share():Decode(shareImportRaw)
				if p then
					importPayload = p
					for k in pairs(p.modules) do importSel[k] = true end
				else
					importErr = err or "ungültig"
				end
			end
			ccRefresh()
		end,
	}
	pa.importStatus = {
		type = "description", order = 121,
		hidden = function() return not (importErr or importPayload) end,
		name = function()
			if importErr then return "|cffff5555Code ungültig: " .. importErr .. "|r" end
			return "|cff66dd66Code erkannt.|r Wähle, was übernommen werden soll:"
		end,
	}
	-- Modul-Häkchen (dynamisch aus der Modulliste; nur sichtbar, wenn im Code enthalten).
	if Share() then
		local o = 122
		for _, m in ipairs(Share():GetModules()) do
			local key = m.key
			pa["imp_" .. key] = {
				type = "toggle", order = o, name = m.label,
				hidden = function() return not (importPayload and importPayload.modules[key]) end,
				get = function() return importSel[key] end,
				set = function(_, v) importSel[key] = v end,
			}
			o = o + 1
		end
	end
	pa.impLayout = {
		type = "toggle", order = 140, width = "full",
		name = "Layout-Positionen mitimportieren",
		desc = "An = die Frame-Positionen des Absenders übernehmen. Aus = deine aktuellen Positionen bleiben.",
		hidden = function()
			return not (importPayload and importPayload.layout and next(importPayload.layout) ~= nil)
		end,
		get = function() return importLayout end,
		set = function(_, v) importLayout = v end,
	}
	pa.importBtn = {
		type = "execute", order = 141, name = "Import ausführen",
		hidden = function() return not importPayload end,
		confirm = true,
		confirmText = "Die ausgewählten Module überschreiben deine aktuellen Einstellungen. Fortfahren?",
		func = function()
			if Share() and importPayload then
				local ok = Share():Import(importPayload, importSel, importLayout)
				if ok then L:Print("Import übernommen.") end
			end
			shareImportRaw, importPayload, importErr = "", nil, nil
			wipe(importSel)
			ccRefresh()
		end,
	}

	LibStub("AceConfig-3.0"):RegisterOptionsTable("Lumen", options)
	LibStub("AceConfigDialog-3.0"):SetDefaultSize("Lumen", 640, 560)
end
