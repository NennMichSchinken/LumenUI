local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Modul: Click-Cast (Phase 2)
--
--  Zwei Pfade, EINE Bindings-Liste (pro Spec), getrennt über binding.hovercast:
--   1. KLICK auf Frame (Clique-Stil): Maustaste (+Modifier) auf einem Secure-
--      Unit-Button -> Aktion auf dessen Unit. Attribute werden je Button gesetzt
--      (NUR außer Kampf; im Kampf via PLAYER_REGEN_ENABLED nachgeholt).
--   2. HOVERCAST (VuhDo-Stil): Tastatur-Taste, während die Maus über einer Unit
--      schwebt -> Aktion auf @mouseover. Ein globaler Secure-Button hält die
--      Aktionen; ein SecureHandler-State-Driver routet die Tasten via
--      SetBindingClick nur, solange [@mouseover,exists] gilt.
--
--  Secret-/Taint-sicher (12.0.7-Muster, mit bewährtem Vorgehen abgeglichen):
--   * Spell/Dispel/Rez laufen IMMER über @mouseover-Makrotext — beim Klick liegt
--     die Maus über der Unit, beim Hover sowieso -> ein Pfad für beides.
--   * "target"/"togglemenu" sind gated -> über UN-gated "click" an versteckte
--     SecureActionButton-Proxys geroutet (sonst Drop bzw. ADDON_ACTION_FORBIDDEN).
--   * Bindings nur außer Kampf schreiben.
-- ===========================================================================

local CC = {}
ns.ClickCast = CC

local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitClass = UnitClass
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local Enum = Enum
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local RegisterStateDriver, UnregisterStateDriver = RegisterStateDriver, UnregisterStateDriver
local ipairs, pairs, type, tostring = ipairs, pairs, type, tostring
local tinsert, tremove, wipe = table.insert, table.remove, wipe
local format, concat = string.format, table.concat
local sort = table.sort

-- ---------------------------------------------------------------------------
--  Konstanten: Maustasten / Modifier (für das Options-Dropdown) + Anzeige
-- ---------------------------------------------------------------------------
local KEY_DISPLAY = {
	BUTTON1 = "Linksklick", BUTTON2 = "Rechtsklick", BUTTON3 = "Mittlere Maustaste",
	BUTTON4 = "Maus 4", BUTTON5 = "Maus 5",
}
local MOD_DISPLAY = { SHIFT = "Shift", CTRL = "Strg", ALT = "Alt", META = "Meta" }

-- Maustaste und Modifier GETRENNT (Options: Maustasten-Dropdown + optionaler
-- Modifier-Schalter mit Shift/Strg/Alt). Gespeichert wird kombiniert in b.key.
local MOUSE_BUTTON_VALUES = {
	BUTTON1 = "Linksklick", BUTTON2 = "Rechtsklick", BUTTON3 = "Mittlere Maustaste",
	BUTTON4 = "Maus 4", BUTTON5 = "Maus 5",
}
local MOUSE_BUTTON_SORTING = { "BUTTON1", "BUTTON2", "BUTTON3", "BUTTON4", "BUTTON5" }
local MOD_VALUES  = { SHIFT = "Shift", CTRL = "Strg", ALT = "Alt" }
local MOD_SORTING = { "SHIFT", "CTRL", "ALT" }

local BINDING_TYPES = {
	target = "Ziel", menu = "Menü", spell = "Spell", dispel = "Dispel", rez = "Wiederbeleben",
}

-- ---------------------------------------------------------------------------
--  Klassen-Presets (Dispel / Rez) — IDs, Name nur als Fallback.
-- ---------------------------------------------------------------------------
local DISPEL_SPELLS = {
	{ id = 527,    class = "PRIEST" },   -- Purify
	{ id = 213634, class = "PRIEST" },   -- Purify Disease (alt) / fallback
	{ id = 218164, class = "MONK" },     -- Detox
	{ id = 4987,   class = "PALADIN" },  -- Cleanse
	{ id = 213644, class = "PALADIN" },  -- Cleanse Toxins
	{ id = 88423,  class = "DRUID" },    -- Nature's Cure
	{ id = 2782,   class = "DRUID" },    -- Remove Corruption
	{ id = 77130,  class = "SHAMAN" },   -- Purify Spirit
	{ id = 51886,  class = "SHAMAN" },   -- Cleanse Spirit
	{ id = 365585, class = "EVOKER" },   -- Expunge
	{ id = 360823, class = "EVOKER" },   -- Naturalize
	{ id = 89808,  class = "WARLOCK" },  -- Singe Magic (Imp)
	{ id = 475,    class = "MAGE" },     -- Remove Curse
}
local REZ_BY_CLASS = {
	PRIEST      = { single = 2006,   group = 212036 },
	PALADIN     = { single = 7328,   group = 212056, battle = 391054 },
	SHAMAN      = { single = 2008,   group = 212048 },
	DRUID       = { single = 50769,  group = 212040, battle = 20484 },
	MONK        = { single = 115178, group = 212051 },
	EVOKER      = { single = 361227, group = 361178 },
	DEATHKNIGHT = { battle = 61999 },
	WARLOCK     = { battle = 20707 },
}

-- ---------------------------------------------------------------------------
--  DB-Zugriff
-- ---------------------------------------------------------------------------
local function ccDB() return ns.Lumen and ns.Lumen.db and ns.Lumen.db.profile.clickCast end

local function curSpecID()
	local idx = GetSpecialization and GetSpecialization()
	return idx and (GetSpecializationInfo(idx)) or nil
end
function CC:CurrentSpecID() return curSpecID() end
function CC:CurrentSpecName()
	local idx = GetSpecialization and GetSpecialization()
	if idx then local _, n = GetSpecializationInfo(idx); return n end
	return "Keine Spec"
end

-- Alle Specs der Spielerklasse (für das Spec-Auswahl-Dropdown der Options).
function CC:GetSpecList()
	local out = {}
	local n = GetNumSpecializations and GetNumSpecializations() or 0
	for i = 1, n do
		local id, name, _, icon = GetSpecializationInfo(i)
		if id then out[#out + 1] = { id = id, name = name, icon = icon } end
	end
	return out
end

-- Bindings-Liste einer Spec (default = AKTIVE Spec; die Options geben eine andere
-- Spec mit, um sie zu bearbeiten ohne die Live-Spec zu wechseln). create=true legt
-- sie an und belegt sie einmalig mit den Defaults (Links=Ziel, Rechts=Menü). Löschen
-- lässt eine leere Tabelle zurück -> es wird NICHT neu vorbelegt.
local function getSpec(create, specID)
	local cc = ccDB(); if not cc then return nil end
	local id = specID or curSpecID(); if not id then return nil end
	if not cc.specs[id] then
		if not create then return nil end
		cc.specs[id] = {
			{ key = "BUTTON1", type = "target", enabled = true },
			{ key = "BUTTON2", type = "menu",   enabled = true },
		}
	end
	return cc.specs[id]
end
function CC:GetBindings(specID) return getSpec(true, specID) or {} end

-- ---------------------------------------------------------------------------
--  Key-Parsing
-- ---------------------------------------------------------------------------
-- "ALT-CTRL-SHIFT-KEY" -> modifiers (Run aus "MOD-"), key, isMouse, buttonNum.
local function parseKey(keyStr)
	if not keyStr or keyStr == "" then return { modifiers = "", key = "", isMouse = false } end
	local rest, mods = keyStr, ""
	while true do
		local pre = (rest:sub(1, 4) == "ALT-" and "ALT-")
			or (rest:sub(1, 5) == "CTRL-" and "CTRL-")
			or (rest:sub(1, 6) == "SHIFT-" and "SHIFT-")
			or (rest:sub(1, 5) == "META-" and "META-")
		if pre and #rest > #pre then mods = mods .. pre; rest = rest:sub(#pre + 1) else break end
	end
	local btn = rest:match("^BUTTON(%d+)$")
	return { modifiers = mods, key = rest, isMouse = btn ~= nil, buttonNum = btn and tonumber(btn) }
end

function CC:FormatKey(keyStr)
	if not keyStr or keyStr == "" then return "—" end
	local p = parseKey(keyStr)
	local parts = {}
	for m in p.modifiers:gmatch("([^-]+)") do parts[#parts + 1] = MOD_DISPLAY[m] or m end
	parts[#parts + 1] = KEY_DISPLAY[p.key] or p.key
	return concat(parts, " + ")
end

-- Maus-Klick-Key in (Modifier-Token, Maustaste) zerlegen bzw. wieder zusammenbauen.
-- Modifier ist EIN Token ("SHIFT"|"CTRL"|"ALT"|""); bei Mehrfach (Altdaten) das erste.
function CC:KeyParts(keyStr)
	local p = parseKey(keyStr)
	local mod = (p.modifiers:gsub("%-$", "")):match("^[^-]+") or ""
	return mod, p.key
end
function CC:BuildKey(mod, btn)
	if mod and mod ~= "" then return mod .. "-" .. btn end
	return btn
end

-- ---------------------------------------------------------------------------
--  Spell-Auflösung / Makrotext
-- ---------------------------------------------------------------------------
-- Auf den BASIS-Spell auflösen, damit Talent-/Hero-Talent-Overrides mitcasten.
local function resolveSpellName(b)
	local id = b.spellID
	if type(id) == "number" and id > 0 and C_Spell then
		if C_Spell.GetBaseSpell then
			local base = C_Spell.GetBaseSpell(id)
			if type(base) == "number" and base > 0 and C_Spell.GetSpellName then
				local n = C_Spell.GetSpellName(base); if n then return n end
			end
		end
		if C_Spell.GetSpellName then local n = C_Spell.GetSpellName(id); if n then return n end end
	end
	return b.spell
end

local function spellName(id)
	return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or nil
end
local function spellKnown(id)
	if not id then return false end
	if C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum and Enum.SpellBookSpellBank then
		return C_SpellBook.IsSpellInSpellBook(id, Enum.SpellBookSpellBank.Player, true)
	end
	return true
end

local function dispelLines(oocOnly)
	local _, pc = UnitClass("player")
	local cond = oocOnly and "@mouseover,exists,nodead,nocombat" or "@mouseover,exists,nodead"
	local lines = {}
	for _, sp in ipairs(DISPEL_SPELLS) do
		if sp.class == pc and spellKnown(sp.id) then
			local n = spellName(sp.id)
			if n then lines[#lines + 1] = "/cast [" .. cond .. "] " .. n end
		end
	end
	return lines
end

local function rezLines(oocOnly)
	local _, pc = UnitClass("player")
	local kit = REZ_BY_CLASS[pc]; if not kit then return {} end
	local function known(sid) return sid and spellKnown(sid) and spellName(sid) or nil end
	local battle, group, single = known(kit.battle), known(kit.group), known(kit.single)
	local lines = {}
	if battle and not oocOnly then lines[#lines + 1] = "/cast [@mouseover,help,dead,combat] " .. battle end
	if group then lines[#lines + 1] = "/cast [@mouseover,help,dead,nocombat] " .. group
	elseif single then lines[#lines + 1] = "/cast [@mouseover,help,dead,nocombat] " .. single end
	return lines
end

-- Binding -> actionType ("target"|"togglemenu"|"macro"), macrotext.
-- forHover ergänzt friend/harm-Filter bei Spells. Spell/Dispel/Rez sind IMMER
-- @mouseover-Makros (funktioniert für Klick UND Hover).
local function resolveBinding(b, forHover)
	local t = b.type
	if t == "target" then return "target" end
	if t == "menu" then return "togglemenu" end
	if t == "spell" then
		local n = resolveSpellName(b); if not n then return nil end
		local conds = { "@mouseover" }
		if forHover then
			if b.hoverFriendly and not b.hoverEnemy then conds[#conds + 1] = "help"
			elseif b.hoverEnemy and not b.hoverFriendly then conds[#conds + 1] = "harm" end
		end
		conds[#conds + 1] = "exists"; conds[#conds + 1] = "nodead"
		if b.oocOnly then conds[#conds + 1] = "nocombat" end
		return "macro", "/cast [" .. concat(conds, ",") .. "] " .. n
	end
	local lines
	if t == "dispel" then lines = dispelLines(b.oocOnly)
	elseif t == "rez" then lines = rezLines(b.oocOnly) end
	if not lines or #lines == 0 then return nil end
	return "macro", concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
--  Aktive Bindings (gefiltert)
-- ---------------------------------------------------------------------------
local function activeList()
	local cc = ccDB()
	if not cc or not cc.enabled then return {} end
	local out = {}
	for _, b in ipairs(CC:GetBindings()) do
		if b.enabled ~= false and b.key and b.key ~= "" then out[#out + 1] = b end
	end
	return out
end

-- ===========================================================================
--  KLICK-PFAD — Attribute je Secure-Button
-- ===========================================================================
local buttons = setmetatable({}, { __mode = "k" })   -- registrierte Secure-Buttons
local applyDirty = false                              -- im Kampf aufgeschoben?

local function getProxy(button, kind)   -- kind = "togglemenu" | "target"
	-- Menü-Proxy teilen wir mit Raidframes (gleiche Konfiguration) -> kein Doppel-Frame.
	if kind == "togglemenu" and ns.RF_GetMenuProxy then return ns.RF_GetMenuProxy(button) end
	local store = (kind == "target") and "_ccTargetProxy" or "_ccMenuProxy"
	local p = button[store]
	if not p then
		p = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
		p:SetSize(1, 1); p:SetAlpha(0); p:EnableMouse(false)
		p:RegisterForClicks("AnyUp")
		p:SetAttribute("type", kind)
		for i = 1, 5 do p:SetAttribute("type" .. i, kind) end
		p:SetAttribute("useparent-unit", true)
		p:SetAttribute("useOnKeyDown", false)
		button[store] = p
	end
	return p
end

-- Benannter Proxy für den „nur außerhalb Kampf"-Pfad (Menü): ein /click-Makro mit
-- [nocombat]-Bedingung drückt diesen Proxy -> die secure togglemenu-Aktion läuft NUR
-- außerhalb des Kampfes, im Kampf passiert nichts (kein versehentliches Menü in M+).
-- Braucht einen globalen Namen (für /click); pro Button einmalig + wiederverwendet.
local namedCount = 0
local function getNamedProxy(button, kind)   -- kind = "togglemenu" | "target"
	local store = (kind == "target") and "_ccNTgtProxy" or "_ccNMenuProxy"
	local p = button[store]
	if not p then
		namedCount = namedCount + 1
		p = CreateFrame("Button", "LumenCCProxy" .. namedCount, button, "SecureActionButtonTemplate")
		p:SetSize(1, 1); p:SetAlpha(0); p:EnableMouse(false)
		p:RegisterForClicks("AnyUp", "AnyDown")
		p:SetAttribute("type", kind)
		p:SetAttribute("type1", kind)            -- /click ohne Tastenangabe = LeftButton
		p:SetAttribute("useparent-unit", true)
		p:SetAttribute("useOnKeyDown", false)
		button[store] = p
	end
	return p
end

local function rec(button, name) button._ccApplied[#button._ccApplied + 1] = name end

local function clearButton(button)
	local a = button._ccApplied
	if a then for i = 1, #a do button:SetAttribute(a[i], nil) end; wipe(a)
	else button._ccApplied = {} end
end

local function applyClick(button, parsed, aType, macrotext, b)
	local prefix = parsed.modifiers:lower()
	local suffix = tostring(parsed.buttonNum)
	local typeAttr = prefix .. "type" .. suffix
	if aType == "togglemenu" then
		if b and b.oocOnly then
			-- Menü nur außerhalb Kampf: /click [nocombat] auf den benannten Proxy. Die
			-- togglemenu-Aktion läuft secure über den Proxy, /click + [nocombat] ist ungated.
			button:SetAttribute(typeAttr, "macro"); rec(button, typeAttr)
			local mt = prefix .. "macrotext" .. suffix
			button:SetAttribute(mt, "/click [nocombat] " .. getNamedProxy(button, "togglemenu"):GetName()); rec(button, mt)
		else
			button:SetAttribute(typeAttr, "click"); rec(button, typeAttr)
			local cb = prefix .. "clickbutton" .. suffix
			button:SetAttribute(cb, getProxy(button, "togglemenu")); rec(button, cb)
		end
	elseif aType == "target" then
		if suffix == "1" and prefix == "" then
			-- Plain Linksklick zielt nativ (Default-ClickBinding) -> direkt lassen.
			button:SetAttribute(typeAttr, "target"); rec(button, typeAttr)
		else
			button:SetAttribute(typeAttr, "click"); rec(button, typeAttr)
			local cb = prefix .. "clickbutton" .. suffix
			button:SetAttribute(cb, getProxy(button, "target")); rec(button, cb)
		end
	elseif aType == "macro" then
		button:SetAttribute(typeAttr, "macro"); rec(button, typeAttr)
		local mt = prefix .. "macrotext" .. suffix
		button:SetAttribute(mt, macrotext or ""); rec(button, mt)
	end
end

-- Click-Cast übernimmt im aktivierten Zustand die volle Kontrolle: Wildcards
-- neutralisieren, modifizierte Klicks ohne Bindung machen nichts (Clique-Modell).
-- Belegte Tasten überschreiben das danach.
-- SICHERE DEFAULTS: Linksklick = "target" (natives Anvisieren), Rechtsklick = WoW-
-- Einheitenmenü (über den geteilten Menü-Proxy, da "togglemenu" 12.0.7-gated ist).
-- So bleibt die Standard-Belegung (Links=Ziel, Rechts=Menü) immer erhalten, BIS der
-- Nutzer BUTTON1/BUTTON2 selbst belegt -> kein versehentliches Aussperren.
local function applyEnabled(button)
	button:SetAttribute("*type1", nil); rec(button, "*type1")
	button:SetAttribute("*type2", nil); rec(button, "*type2")
	button:SetAttribute("*clickbutton2", nil); rec(button, "*clickbutton2")
	button:SetAttribute("type1", "target"); rec(button, "type1")
	button:SetAttribute("type2", "click"); rec(button, "type2")
	button:SetAttribute("clickbutton2", getProxy(button, "togglemenu")); rec(button, "clickbutton2")
	for _, b in ipairs(activeList()) do
		if not b.hovercast then
			local p = parseKey(b.key)
			if p.isMouse and p.buttonNum and p.buttonNum <= 5 then
				local aType, macrotext = resolveBinding(b, false)
				if aType then applyClick(button, p, aType, macrotext, b) end
			end
		end
	end
end

local function applyToButton(button)
	clearButton(button)
	if ccDB() and ccDB().enabled then
		applyEnabled(button)
	elseif ns.RF_ApplyDefaultClicks then
		ns.RF_ApplyDefaultClicks(button)   -- Phase-1-Defaults zurück (Links=Ziel, Rechts=Menü)
	end
end

-- Naht aus Raidframes: jeder erzeugte Secure-Button meldet sich hier an.
function ns.CC_RegisterButton(button)
	buttons[button] = true
	button._ccApplied = button._ccApplied or {}
	if not InCombatLockdown() then applyToButton(button) end
end

-- ===========================================================================
--  HOVERCAST-PFAD — globaler Secure-Button + State-Driver
-- ===========================================================================
local hoverBtn, driver
local lastHoverCount = 0
local HOVER_BTN_NAME = "LumenCCHover"

-- Hovercast ist P2 (siehe Shell/Screens.lua CC_HOVERCAST): die Secure-Tasten-Treiber-Mechanik
-- gibt die Taste in 12.0.7 nicht mehr sauber frei -> belegte Hovercast-Taste blockiert die
-- Aktionsleiste. Bis zur 12.1.0-Nacharbeit deaktiviert; vorhandene Hovercast-Bindings bleiben
-- im Profil, werden aber NICHT angewendet (applyHover legt alles still). Zum Reaktivieren: true.
local HOVERCAST_ENABLED = false

local function buildHoverFrames()
	if hoverBtn then return end
	hoverBtn = CreateFrame("Button", HOVER_BTN_NAME, UIParent, "SecureActionButtonTemplate")
	hoverBtn:RegisterForClicks("AnyUp", "AnyDown")   -- Tasten-Down/Up beide abdecken
	hoverBtn:EnableMouse(false)
	hoverBtn:SetSize(1, 1); hoverBtn:SetAlpha(0)
	hoverBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -400, 200)
	hoverBtn:Show()

	driver = CreateFrame("Frame", "LumenCCDriver", UIParent, "SecureHandlerStateTemplate")
	driver:SetFrameRef("hb", hoverBtn)
	-- Solange [@mouseover,exists]: die konfigurierten Tasten auf den Hover-Button
	-- routen (Override-Binding). Verlässt die Maus die Unit: alle Overrides lösen.
	driver:SetAttribute("_onstate-mo", [[
		if newstate == "1" then
			self:RunAttribute("hover_set")
		else
			self:ClearBindings()
		end
	]])
end

local function clearHoverAttrs()
	for i = 1, lastHoverCount do
		local s = "lu_hc_" .. i
		hoverBtn:SetAttribute("type-" .. s, nil)
		hoverBtn:SetAttribute("macrotext-" .. s, nil)
		hoverBtn:SetAttribute("unit-" .. s, nil)
	end
end

local function applyHover()
	if not HOVERCAST_ENABLED then
		-- Geparkt: sicherstellen, dass nichts hängen bleibt (Treiber + Override-Bindings lösen),
		-- dann nichts neu aufsetzen -> belegte Hovercast-Bindings blockieren keine Tasten.
		if driver then
			UnregisterStateDriver(driver, "mo")
			pcall(function() driver:Execute("self:ClearBindings()") end)
		end
		if hoverBtn then clearHoverAttrs() end
		lastHoverCount = 0
		return
	end
	buildHoverFrames()
	UnregisterStateDriver(driver, "mo")
	pcall(function() driver:Execute("self:ClearBindings()") end)
	clearHoverAttrs()

	local cc = ccDB()
	if not cc or not cc.enabled then lastHoverCount = 0; return end

	local setLines, count = {}, 0
	for _, b in ipairs(activeList()) do
		if b.hovercast then
			local aType, macrotext = resolveBinding(b, true)
			if aType then
				count = count + 1
				local s = "lu_hc_" .. count
				if aType == "macro" then
					hoverBtn:SetAttribute("type-" .. s, "macro")
					hoverBtn:SetAttribute("macrotext-" .. s, macrotext or "")
				else
					hoverBtn:SetAttribute("type-" .. s, aType)         -- target | togglemenu
					hoverBtn:SetAttribute("unit-" .. s, "mouseover")
				end
				setLines[#setLines + 1] = format(
					[[self:SetBindingClick(true, %q, %q, %q)]], b.key, HOVER_BTN_NAME, s)
			end
		end
	end
	lastHoverCount = count

	driver:SetAttribute("hover_set", concat(setLines, "\n"))
	if count > 0 then
		RegisterStateDriver(driver, "mo", "[@mouseover,exists] 1; 0")
	end
end

-- ===========================================================================
--  Anwenden / Events / öffentliche API
-- ===========================================================================
function CC:ApplyBindings()
	if not ccDB() then return end
	if InCombatLockdown() then applyDirty = true; return end
	for button in pairs(buttons) do applyToButton(button) end
	applyHover()
end

-- Options ruft das nach jeder Änderung.
function ns.CC_Apply() CC:ApplyBindings() end

-- Spell-Liste (Klassen-/Spec-Zauber, nicht passiv) für das Options-Dropdown.
function CC:GetClassSpells()
	local out = {}
	if not (C_SpellBook and Enum and Enum.SpellBookSpellBank) then return out end
	local bank = Enum.SpellBookSpellBank.Player
	local numTabs = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
	local seen = {}
	for tab = 1, numTabs do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(tab)
		if info and not info.shouldHide and not (info.offSpecID and info.offSpecID ~= 0) then
			local offset = info.itemIndexOffset or 0
			for si = offset + 1, offset + (info.numSpellBookItems or 0) do
				local stype, actionId, spellId = C_SpellBook.GetSpellBookItemType(si, bank)
				if stype == Enum.SpellBookItemType.Spell then
					local sid = spellId or actionId
					if sid and not seen[sid] and not (C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(sid)) then
						seen[sid] = true
						local n = spellName(sid)
						if n then
							local icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
							-- "Friendly" = auf Freunde/sich selbst wirkbar (hilfreich ODER nicht
							-- schädlich). API fehlt -> nicht filtern (friendly=true). Best-effort.
							local helpful, harmful
							if C_SpellBook.IsSpellBookItemHelpful then
								local ok, v = pcall(C_SpellBook.IsSpellBookItemHelpful, si, bank); if ok then helpful = v end
							end
							if C_SpellBook.IsSpellBookItemHarmful then
								local ok, v = pcall(C_SpellBook.IsSpellBookItemHarmful, si, bank); if ok then harmful = v end
							end
							local friendly = (helpful == true) or (harmful == false)
								or (helpful == nil and harmful == nil)
							out[#out + 1] = { id = sid, name = n, icon = icon, friendly = friendly }
						end
					end
				end
			end
		end
	end
	sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- Auren-Quelle für den Tracking-/Whitelist-Picker (B4): castbare Zauberbuch-Spells
-- (über GetClassSpells) PLUS nur die TATSÄCHLICH GEWÄHLTEN Talente des aktiven
-- Talentbaums (declutter — nicht der ganze Baum). So sind Talent-Auren wie
-- "Verschmelzung" auswählbar, ohne die Liste mit ungewählten Talenten zu überladen.
-- Dedupe über spellId. Limit: C_Traits liefert nur die AKTIVE Spec -> beim Bearbeiten
-- anderer Specs steht nur das Zauberbuch zur Verfügung (kuratierte Defaults decken die ab).
function CC:GetAuraSpells()
	local out, seen = {}, {}
	local function add(sid, name, icon)
		if not sid or seen[sid] then return end
		name = name or spellName(sid); if not name then return end
		seen[sid] = true
		icon = icon or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
		out[#out + 1] = { id = sid, name = name, icon = icon }
	end
	-- 1. Castbare Zauberbuch-Spells (wie Click-Cast, ohne Passive)
	for _, s in ipairs(self:GetClassSpells()) do add(s.id, s.name, s.icon) end
	-- 2. Nur GEWÄHLTE Talente des aktiven Configs (Talent-Auren inkl. passiver Buffs)
	if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits then
		local cfg   = C_ClassTalents.GetActiveConfigID()
		local cinfo = cfg and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(cfg)
		local function fromEntry(eid)
			local entry = eid and C_Traits.GetEntryInfo(cfg, eid)
			local def   = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			if def and def.spellID then add(def.spellID) end
		end
		if cinfo and cinfo.treeIDs then
			for _, treeID in ipairs(cinfo.treeIDs) do
				local nodes = C_Traits.GetTreeNodes and C_Traits.GetTreeNodes(treeID)
				if nodes then
					for _, nodeID in ipairs(nodes) do
						local node = C_Traits.GetNodeInfo(cfg, nodeID)
						if node and (node.activeRank or 0) > 0 then   -- nur tatsächlich gewählte
							local entryID = node.activeEntry and node.activeEntry.entryID
							if entryID then fromEntry(entryID)
							elseif node.entryIDs then for _, e in ipairs(node.entryIDs) do fromEntry(e) end end
						end
					end
				end
			end
		end
	end
	sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- CRUD auf einer bestimmten Spec (Options gibt die bearbeitete Spec mit).
function CC:AddBinding(specID, binding)
	local list = getSpec(true, specID); if not list then return end
	if binding.enabled == nil then binding.enabled = true end
	tinsert(list, binding)
	self:ApplyBindings()
end
function CC:RemoveBinding(specID, index)
	local list = getSpec(true, specID); if not list then return end
	tremove(list, index)
	self:ApplyBindings()
end

-- Dropdown-Helfer für Options.
CC.MOUSE_BUTTON_VALUES  = MOUSE_BUTTON_VALUES
CC.MOUSE_BUTTON_SORTING = MOUSE_BUTTON_SORTING
CC.MOD_VALUES           = MOD_VALUES
CC.MOD_SORTING          = MOD_SORTING
CC.BINDING_TYPES        = BINDING_TYPES

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if applyDirty then applyDirty = false; CC:ApplyBindings() end
	else
		CC:ApplyBindings()
	end
end)
