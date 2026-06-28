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

local GROW = {
	RIGHT = "Nach rechts", LEFT = "Nach links", UP = "Nach oben", DOWN = "Nach unten",
}

-- Eigenes AceGUI-Dropdown-Item: verhält sich wie "Dropdown-Item-Toggle", zeigt aber beim
-- Hovern den echten Spell-Tooltip (Item-Wert = spellID). Für den langen Tracking-Picker,
-- damit man Spells nicht nur an Icon+Name erkennen muss. Per itemControl am select gesetzt.
do
	local AceGUI = LibStub("AceGUI-3.0", true)
	local IBLib  = LibStub("AceGUI-3.0-DropDown-ItemBase", true)
	if AceGUI and IBLib then
		local ItemBase     = IBLib.GetItemBase()
		local widgetType   = "LumenSpellDropdownItem"
		local widgetVersion = 1

		local function UpdateToggle(self)
			if self.value then self.check:Show() else self.check:Hide() end
		end
		local function OnRelease(self) ItemBase.OnRelease(self); self.value = nil end
		local function Frame_OnClick(this)
			local self = this.obj
			if self.disabled then return end
			self.value = not self.value
			UpdateToggle(self)
			self:Fire("OnValueChanged", self.value)
		end
		local function SetValue(self, value) self.value = value; UpdateToggle(self) end
		local function GetValue(self) return self.value end

		-- userdata.value = der Key (= spellID), vom Dropdown bei AddListItem gesetzt.
		local function ShowTip(this)
			local self = this.obj
			local sid = self.userdata and self.userdata.value
			if sid and GameTooltip then
				GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
				if pcall(GameTooltip.SetSpellByID, GameTooltip, sid) then
					GameTooltip:Show()
					-- Das Pullout hebt sich selbst auf TOOLTIP-Strata (AceGUI fixstrata) -> gleiche
					-- Strata reicht nicht; innerhalb der Strata per höherem Frame-Level drüber heben.
					GameTooltip:SetFrameStrata("TOOLTIP")
					GameTooltip:SetFrameLevel((self.frame:GetFrameLevel() or 0) + 50)
				else
					GameTooltip:Hide()
				end
			end
		end
		local function HideTip() if GameTooltip then GameTooltip:Hide() end end

		local function Constructor()
			local self = ItemBase.Create(widgetType)
			self.frame:SetScript("OnClick", Frame_OnClick)
			self.SetValue  = SetValue
			self.GetValue  = GetValue
			self.OnRelease = OnRelease
			-- HookScript: lässt ItemBases OnEnter (Fire + Pullout-Submenu-Handling) intakt
			-- und ergänzt nur den Tooltip.
			self.frame:HookScript("OnEnter", ShowTip)
			self.frame:HookScript("OnLeave", HideTip)
			AceGUI:RegisterAsWidget(self)
			return self
		end

		AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion + ItemBase.version)
	end
end

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
	-- Aggro: Text ist in einer Stufe aktiv, wenn sie "overlay" zeigt UND deren Text-Toggle an ist.
	local AGGRO_TEXT_DESC = "Nur verfügbar, wenn in einer Stufe der Text aktiv ist (Darstellung „Rand + Overlay\" + „Text anzeigen\")."
	local function aggroTextActive()
		return (rf().aggroModeAggro == "overlay" and rf().aggroTextAggro)
			or (rf().aggroModeWarn == "overlay" and rf().aggroTextWarn)
	end
	local function aggroTextDisabled()
		return not rf().aggroEnabled or not aggroTextActive()
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

	-- Aura-Kategorie-Get/Set (Werte liegen in rf().auras[<catKey>][key]).
	local function auraGetSet(catKey)
		local function get(info) local t = (rf().auras and rf().auras[catKey]) or {}; return t[info[#info]] end
		local function set(info, val)
			rf().auras = rf().auras or {}
			rf().auras[catKey] = rf().auras[catKey] or {}
			rf().auras[catKey][info[#info]] = val
			-- Aura-Optionen brauchen kein Header-Relayout -> leichter, kampf-sicherer
			-- Refresh (greift sofort, auch im Kampf; UpdateLayout würde im Kampf abbrechen).
			if ns.Raidframes then ns.Raidframes:RefreshAuras() end
		end
		return get, set
	end
	-- Kategorien im Auras-Tab (Reihenfolge + Label). Filter/Render liegen in Raidframes.lua.
	local AURA_TAB_CATS = {
		{ key = "hotsOwn",    label = "HoTs" },
		{ key = "defensives", label = "Defensives & Externe" },
		{ key = "debuffs",    label = "Debuffs" },
	}
	-- Ein Kategorie-Block (inline-group mit eigenem Get/Set). Regler je Kategorie identisch.
	local function auraCatGroup(catKey, label, order)
		local get, set = auraGetSet(catKey)
		local function isAutoFit() local t = rf().auras and rf().auras[catKey]; return t and t.autoFit end
		return {
			type = "group", inline = true, order = order, name = label,
			get = get, set = set,
			args = {
				enabled   = { type = "toggle", order = 1, width = "full", name = "Anzeigen" },
				filterMode = {
					type = "select", order = 1.5, name = "Filter",
					desc = "Welche Debuffs gezeigt werden. Raid-relevant = Blizzards Standard-Auswahl.",
					values = { raid = "Raid-relevant (Blizzard)", all = "Alle", dispellable = "Nur dispellbar" },
					hidden = function() return catKey ~= "debuffs" end,
				},
				anchor    = { type = "select", order = 2, name = "Position (Anker)", values = POINTS },
				grow      = { type = "select", order = 3, name = "Wachstumsrichtung", values = GROW },
				spacing   = { type = "range",  order = 4, name = "Abstand", min = 0, max = 20, step = 1 },
				maxIcons  = { type = "range",  order = 5, name = "Max. Icons", min = 1, max = 8, step = 1 },
				showSwipe = { type = "toggle", order = 6, name = "Cooldown-Swipe" },
				autoFit   = {
					type = "toggle", order = 7, width = "full", name = "Auto-Fit (Größe aus Frame-Höhe)",
					desc = "An: Icon-Größe automatisch aus der Frame-Höhe (gedeckelt an Breite/Höhe). Aus: feste Größen für Raid/Gruppe.",
				},
				sizeRaid  = { type = "range", order = 8, name = "Größe (Raid)",   min = 8, max = 48, step = 1, disabled = isAutoFit },
				sizeParty = { type = "range", order = 9, name = "Größe (Gruppe)", min = 8, max = 48, step = 1, disabled = isAutoFit },
			},
		}
	end
	local aurasArgs = {
		intro = {
			type = "description", order = 0,
			name = "Aura-Indikatoren am Frame: eigene/fremde HoTs, Defensives & Externe, Debuffs. " ..
			       "Jede Kategorie hat eigenen Anker, Wachstum und Größe. Im |cffD4A34FTestmodus|r (Tab Base) zur Vorschau sichtbar.\n",
		},
	}
	for i, cat in ipairs(AURA_TAB_CATS) do
		aurasArgs[cat.key] = auraCatGroup(cat.key, cat.label, i * 10)
	end

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

	-- ===== Sortierung: Rollen-Prioritätsliste (Hoch/Runter) =====================
	local ROLE_LABEL = { TANK = "Tank", HEALER = "Heiler", DAMAGER = "DPS" }
	local function swapRole(i, j)
		local o = rf().sortRoleOrder
		if not (o and o[i] and o[j]) then return end
		o[i], o[j] = o[j], o[i]
		if ns.Raidframes then ns.Raidframes:UpdateLayout() end
		if AceRegistry then AceRegistry:NotifyChange("Lumen") end
	end
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
			-- Lazy auflösen: beim Bau in OnInitialize ist GetSpecialization() oft noch
			-- nil (vor dem Login). Beim ersten Anzeigen in-world steht sie -> nachziehen.
			get = function()
				if not selectedSpec and CC() then selectedSpec = CC():CurrentSpecID() end
				return selectedSpec
			end,
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

	-- ===== Tracking: Whitelist-Editor (B4) ======================================
	-- Pro Spec festlegen, welche Spells als Aura-Icons getrackt werden (HoTs + eigene
	-- Defensiven). Wie Click-Cast: Spec-Dropdown folgt der aktiven Spec, ist aber
	-- umschaltbar. Spell-Quelle = CC():GetAuraSpells() (Zauberbuch INKL. Passive +
	-- Talentbaum), damit auch Talent-Auren wie "Verschmelzung" auswählbar sind.
	local function RF() return ns.Raidframes end
	local function trkRefresh() if AceRegistry then AceRegistry:NotifyChange("Lumen") end end
	local trkSpec               -- bearbeitete Spec (entkoppelt von der Live-Spec)
	local trkSearch  = {}       -- [typ] = Suchtext (transient)
	local trkPick    = {}       -- [typ] = im Add-Dropdown gewählte spellID (transient)
	local trkSpells  = {}       -- Auren-Spell-Quelle (Zauberbuch+Passive+Talente), je Rebuild frisch
	local trackArgs  = {}
	local rebuildTrack

	local function refreshTrkSpells()
		wipe(trkSpells)
		if not CC() then return end
		for _, s in ipairs(CC():GetAuraSpells()) do trkSpells[#trkSpells + 1] = s end
	end

	-- Nur diese zwei Kategorien bekommen einen Editor (Debuffs laufen über Filtermodi).
	local TRACK_CATS = {
		{ typ = "hot", label = "HoTs",                 desc = "Eigene Heilung über Zeit als Icon am Frame." },
		{ typ = "def", label = "Defensives & Externe", desc = "Eigene Defensiven. Externe Schutzzauber anderer zeigt Lumen ohnehin automatisch." },
	}

	-- Ein Editor-Block je Typ: Liste (Icon+Name+Entfernen) + Suche/Dropdown/Hinzufügen + Reset.
	local function trackCatArgs(cat, baseOrder)
		local a = {}
		a[cat.typ .. "Head"] = { type = "header", order = baseOrder, name = cat.label }
		a[cat.typ .. "Desc"] = { type = "description", order = baseOrder + 0.1, name = "|cff888888" .. cat.desc .. "|r" }
		local entries = (RF() and RF():WhitelistEntries(trkSpec, cat.typ)) or {}
		if #entries == 0 then
			a[cat.typ .. "Empty"] = { type = "description", order = baseOrder + 0.2, name = "|cff666666(keine Spells)|r" }
		end
		for i, e in ipairs(entries) do
			a[cat.typ .. "row" .. i] = {
				type = "execute", order = baseOrder + 0.2 + i * 0.001, width = "full",
				name = iconText(e.icon, e.name) .. "   |cffD4A34F✕ Entfernen|r",
				func = function() if RF() then RF():RemoveWhitelist(trkSpec, e.id) end; rebuildTrack(); trkRefresh() end,
			}
		end
		a[cat.typ .. "search"] = {
			type = "input", order = baseOrder + 5, name = "Spell suchen", width = 1.0,
			get = function() return trkSearch[cat.typ] or "" end,
			set = function(_, v) trkSearch[cat.typ] = v; trkRefresh() end,
		}
		-- schon getrackte Spells (beide Kategorien) aus dem Dropdown ausblenden — keine Doppelten.
		local function pickMatch(s, q, tracked)
			-- Talent-IDs auf die echte Aura-ID normalisieren, damit redundante Talent-
			-- Einträge ausgeblendet werden, wenn die Aura bereits getrackt ist.
			local rid = (RF() and RF().ResolveTrackId) and RF():ResolveTrackId(s.id) or s.id
			if tracked[rid] then return false end
			return q == "" or s.name:lower():find(q, 1, true) ~= nil
		end
		a[cat.typ .. "pick"] = {
			type = "select", order = baseOrder + 6, name = "Spell", width = 1.4,
			itemControl = "LumenSpellDropdownItem",   -- Spell-Tooltip beim Hovern im Dropdown
			values = function()
				local q = (trkSearch[cat.typ] or ""):lower()
				local tracked = (RF() and RF():WhitelistMap(trkSpec)) or {}
				local t = {}
				for _, s in ipairs(trkSpells) do if pickMatch(s, q, tracked) then t[s.id] = iconText(s.icon, s.name) end end
				return t
			end,
			sorting = function()
				local q = (trkSearch[cat.typ] or ""):lower()
				local tracked = (RF() and RF():WhitelistMap(trkSpec)) or {}
				local t = {}
				for _, s in ipairs(trkSpells) do if pickMatch(s, q, tracked) then t[#t + 1] = s.id end end
				return t
			end,
			get = function() return trkPick[cat.typ] end,
			set = function(_, v) trkPick[cat.typ] = v end,
		}
		a[cat.typ .. "add"] = {
			type = "execute", order = baseOrder + 7, name = "Hinzufügen", width = 0.7,
			disabled = function() return not trkPick[cat.typ] end,
			func = function()
				if RF() and trkPick[cat.typ] then RF():AddWhitelist(trkSpec, trkPick[cat.typ], cat.typ) end
				trkPick[cat.typ] = nil
				rebuildTrack(); trkRefresh()
			end,
		}
		a[cat.typ .. "reset"] = {
			type = "execute", order = baseOrder + 8, name = "Standard wiederherstellen", width = 1.3,
			confirm = true, confirmText = "Diese Liste auf Lumens kuratierten Standard zurücksetzen?",
			func = function() if RF() then RF():ResetWhitelist(trkSpec, cat.typ) end; rebuildTrack(); trkRefresh() end,
		}
		return a
	end

	rebuildTrack = function()
		wipe(trackArgs)
		refreshTrkSpells()
		-- Tracking ist immer an die AKTIVE Spec gebunden (Talente/Zauberbuch nur dafür
		-- auslesbar) -> kein Spec-Switcher (anders als Click-Cast, das talent-unabhängig ist).
		trkSpec = (CC() and CC():CurrentSpecID()) or trkSpec
		trackArgs.intro = {
			type = "description", order = 0,
			name = "Welche Spells als Aura-Icons getrackt werden — Anzeige & Position regelt der Tab |cffD4A34FAuras|r.\n" ..
			       "Bearbeitet wird automatisch deine |cffD4A34Faktive Spec|r (Talente anderer Specs kann WoW nicht auslesen; deren Defaults greifen automatisch, sobald du sie spielst).\n",
		}
		trackArgs.specInfo = {
			type = "description", order = 1,
			name = function()
				return "|cff888888Aktive Spec: |r|cffD4A34F" .. (CC() and CC():CurrentSpecName() or "?") .. "|r"
			end,
		}
		local o = 10
		for _, cat in ipairs(TRACK_CATS) do
			for k, v in pairs(trackCatArgs(cat, o)) do trackArgs[k] = v end
			o = o + 10
		end
	end
	rebuildTrack()

	-- QoL: bei Spec-Wechsel im Spiel die bearbeitete Spec automatisch auf die jetzt
	-- aktive umstellen (manuelle Auswahl im Dropdown gilt bis zum nächsten Wechsel).
	-- PLAYER_LOGIN/ENTERING_WORLD: erste Auflösung, sobald die Spec-API verfügbar ist
	-- (rebuildCC lief in OnInitialize noch vor dem Login -> selectedSpec war nil/blank).
	local specWatcher = CreateFrame("Frame")
	specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	specWatcher:RegisterEvent("PLAYER_LOGIN")
	specWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	specWatcher:SetScript("OnEvent", function()
		if CC() then selectedSpec = CC():CurrentSpecID(); trkSpec = CC():CurrentSpecID() end
		rebuildCC(); rebuildTrack(); ccRefresh()
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
					nameClassColor = {
						type = "toggle", order = 24.5, name = "Name in Klassenfarbe",
						desc = "Färbt den Namens-Text in der Klassenfarbe der Einheit (überschreibt die je Kontext eingestellte Namensfarbe).",
					},
					bgHead = { type = "header", order = 24.6, name = "Hintergrund & Transparenz" },
					bgColor = {
						type = "color", order = 24.7, name = "Hintergrundfarbe",
						get = getColor, set = setColor,
					},
					bgAlpha = {
						type = "range", order = 24.8, name = "Hintergrund-Deckkraft",
						min = 0, max = 1, step = 0.05, isPercent = true,
					},
					healthAlpha = {
						type = "range", order = 24.9, name = "Lebensbalken-Deckkraft",
						desc = "Nur die Lebensbalken-Füllung wird durchsichtig — Schild und Heilabsorb bleiben voll sichtbar.",
						min = 0, max = 1, step = 0.05, isPercent = true,
					},
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

					aggroHead = { type = "header", order = 30, name = "Aggro-Warnung" },
					aggroEnabled = {
						type = "toggle", order = 30.1, width = "full",
						name = "Aggro-Warnung anzeigen (Tanks ausgenommen)",
					},
					aggroInstanceOnly = {
						type = "toggle", order = 30.2, width = "full",
						name = "Nur in Dungeon/Raid",
						desc = "Zeigt die Aggro-Warnung nur in Instanzen (Dungeon/Raid). Aus = überall, auch solo/Open World.",
						disabled = function() return not rf().aggroEnabled end,
					},

					-- Block: hat Aggro (rot, Status 3)
					aggroAggroHead = { type = "header", order = 31, name = "Hat Aggro (rot)" },
					aggroColorAggro = {
						type = "color", order = 31.1, name = "Farbe",
						get = getColor, set = setColor,
						disabled = function() return not rf().aggroEnabled end,
					},
					aggroModeAggro = {
						type = "select", order = 31.2, name = "Darstellung",
						values = { border = "Nur Rand", overlay = "Rand + Overlay" },
						disabled = function() return not rf().aggroEnabled end,
					},
					aggroTextAggro = {
						type = "toggle", order = 31.3, name = "\"Aggro\"-Text anzeigen",
						desc = "Nur verfügbar, wenn Darstellung „Rand + Overlay\" ist.",
						disabled = function() return not rf().aggroEnabled or rf().aggroModeAggro ~= "overlay" end,
					},

					-- Block: Aggro droht (gelb, Status 1-2)
					aggroWarnHead = { type = "header", order = 32, name = "Aggro droht (gelb)" },
					aggroColorWarn = {
						type = "color", order = 32.1, name = "Farbe",
						get = getColor, set = setColor,
						disabled = function() return not rf().aggroEnabled end,
					},
					aggroModeWarn = {
						type = "select", order = 32.2, name = "Darstellung",
						values = { border = "Nur Rand", overlay = "Rand + Overlay" },
						disabled = function() return not rf().aggroEnabled end,
					},
					aggroTextWarn = {
						type = "toggle", order = 32.3, name = "\"Aggro\"-Text anzeigen",
						desc = "Nur verfügbar, wenn Darstellung „Rand + Overlay\" ist.",
						disabled = function() return not rf().aggroEnabled or rf().aggroModeWarn ~= "overlay" end,
					},

					-- Block: geteilte Darstellung beider Stufen
					aggroSharedHead = { type = "header", order = 33, name = "Darstellung (beide Stufen)" },
					aggroFillAlpha = {
						type = "range", order = 33.1, name = "Overlay-Deckkraft", min = 0, max = 1, step = 0.05, isPercent = true,
						desc = "Nur verfügbar, wenn mindestens eine Stufe „Rand + Overlay\" nutzt.",
						disabled = function() return not rf().aggroEnabled or (rf().aggroModeAggro ~= "overlay" and rf().aggroModeWarn ~= "overlay") end,
					},
					aggroTextSize = {
						type = "range", order = 33.2, name = "Textgröße", min = 6, max = 28, step = 1,
						desc = AGGRO_TEXT_DESC, disabled = aggroTextDisabled,
					},
					aggroTextPoint = {
						type = "select", order = 33.3, name = "Textposition", values = POINTS,
						desc = AGGRO_TEXT_DESC, disabled = aggroTextDisabled,
					},
					aggroTextX = {
						type = "range", order = 33.4, name = "Text X-Versatz", min = -60, max = 60, step = 1,
						desc = AGGRO_TEXT_DESC, disabled = aggroTextDisabled,
					},
					aggroTextY = {
						type = "range", order = 33.5, name = "Text Y-Versatz", min = -60, max = 60, step = 1,
						desc = AGGRO_TEXT_DESC, disabled = aggroTextDisabled,
					},
					aggroTextOutline = {
						type = "select", order = 33.6, name = "Text-Umrandung", values = OUTLINES,
						desc = AGGRO_TEXT_DESC, disabled = aggroTextDisabled,
					},

					sortHead = { type = "header", order = 40, name = "Sortierung" },
					sortMode = {
						type = "select", order = 40.1, name = "Sortieren nach",
						values = { group = "Gruppe", role = "Rolle" },
					},
					sortApplyRaid = {
						type = "toggle", order = 40.15, width = "full",
						name = "Auch im Raid nach Rolle sortieren",
						desc = "Aus: im Raid bleibt deine selbst gebaute Anordnung nach Gruppe. An: die Rollen-Sortierung gilt auch im Raid. (Dungeon/Party wird immer sortiert.)",
						hidden = function() return rf().sortMode ~= "role" end,
					},
					sortRoleDesc = {
						type = "description", order = 40.2,
						name = "|cff888888Prioritätsliste — oben wird zuerst angezeigt:|r",
						hidden = function() return rf().sortMode ~= "role" end,
					},
					sortSlot1 = {
						type = "group", inline = true, order = 40.3,
						name = function() return "1. " .. (ROLE_LABEL[rf().sortRoleOrder[1]] or "?") end,
						hidden = function() return rf().sortMode ~= "role" end,
						args = {
							down = { type = "execute", order = 2, width = 0.8, name = "▼ Runter", func = function() swapRole(1, 2) end },
						},
					},
					sortSlot2 = {
						type = "group", inline = true, order = 40.4,
						name = function() return "2. " .. (ROLE_LABEL[rf().sortRoleOrder[2]] or "?") end,
						hidden = function() return rf().sortMode ~= "role" end,
						args = {
							up   = { type = "execute", order = 1, width = 0.8, name = "▲ Hoch",   func = function() swapRole(2, 1) end },
							down = { type = "execute", order = 2, width = 0.8, name = "▼ Runter", func = function() swapRole(2, 3) end },
						},
					},
					sortSlot3 = {
						type = "group", inline = true, order = 40.5,
						name = function() return "3. " .. (ROLE_LABEL[rf().sortRoleOrder[3]] or "?") end,
						hidden = function() return rf().sortMode ~= "role" end,
						args = {
							up = { type = "execute", order = 1, width = 0.8, name = "▲ Hoch", func = function() swapRole(3, 2) end },
						},
					},

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
				auras = {
					type = "group", name = "Auras", order = 4,
					args = aurasArgs,
				},
				tracking = {
					type = "group", name = "Tracking", order = 5,
					args = trackArgs,
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
