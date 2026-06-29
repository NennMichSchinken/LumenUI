local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Module: Click-Cast (Phase 2)
--
--  Two paths, ONE bindings list (per spec), separated via binding.hovercast:
--   1. CLICK on frame (Clique style): mouse button (+modifier) on a secure
--      unit button -> action on its unit. Attributes are set per button
--      (ONLY out of combat; in combat caught up via PLAYER_REGEN_ENABLED).
--   2. HOVERCAST (VuhDo style): keyboard key while the mouse hovers over a unit
--      -> action on @mouseover. A global secure button holds the actions;
--      a SecureHandler state driver routes the keys via SetBindingClick only
--      while [@mouseover,exists] holds.
--
--  Secret/taint-safe (12.0.7 pattern, checked against a proven approach):
--   * Spell/dispel/rez ALWAYS run via @mouseover macrotext — on a click the
--     mouse is over the unit, on hover anyway -> one path for both.
--   * "target"/"togglemenu" are gated -> routed via UN-gated "click" to hidden
--     SecureActionButton proxies (otherwise dropped resp. ADDON_ACTION_FORBIDDEN).
--   * Only write bindings out of combat.
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
--  Constants: mouse buttons / modifiers (for the options dropdown) + display
-- ---------------------------------------------------------------------------
-- Display tables for FormatKey — filled IN PLACE on locale-ready (stable upvalue
-- references captured by FormatKey at module load). META has no translation.
local KEY_DISPLAY = {}
local MOD_DISPLAY = { META = "Meta" }

-- Mouse button and modifier SEPARATE (options: mouse-button dropdown + optional
-- modifier toggle with Shift/Ctrl/Alt). Stored combined in b.key.
-- Localized display tables — filled IN PLACE on locale-ready (stable references,
-- because they are exported as CC.* and captured by FormatKey at module load).
local T = ns.T
local MOUSE_BUTTON_VALUES = {}
local MOUSE_BUTTON_SORTING = { "BUTTON1", "BUTTON2", "BUTTON3", "BUTTON4", "BUTTON5" }
local MOD_VALUES  = {}
local MOD_SORTING = { "SHIFT", "CTRL", "ALT" }
local BINDING_TYPES = {}

ns.onLocaleReady[#ns.onLocaleReady + 1] = function()
	MOUSE_BUTTON_VALUES.BUTTON1 = T("Left click")
	MOUSE_BUTTON_VALUES.BUTTON2 = T("Right click")
	MOUSE_BUTTON_VALUES.BUTTON3 = T("Middle mouse button")
	MOUSE_BUTTON_VALUES.BUTTON4 = T("Mouse 4")
	MOUSE_BUTTON_VALUES.BUTTON5 = T("Mouse 5")
	MOD_VALUES.SHIFT = T("Shift"); MOD_VALUES.CTRL = T("Ctrl"); MOD_VALUES.ALT = T("Alt")
	BINDING_TYPES.target = T("Target"); BINDING_TYPES.menu = T("Menu")
	BINDING_TYPES.spell = T("Spell"); BINDING_TYPES.dispel = T("Dispel"); BINDING_TYPES.rez = T("Resurrect")
	KEY_DISPLAY.BUTTON1 = T("Left click"); KEY_DISPLAY.BUTTON2 = T("Right click")
	KEY_DISPLAY.BUTTON3 = T("Middle mouse button")
	KEY_DISPLAY.BUTTON4 = T("Mouse 4"); KEY_DISPLAY.BUTTON5 = T("Mouse 5")
	MOD_DISPLAY.SHIFT = T("Shift"); MOD_DISPLAY.CTRL = T("Ctrl"); MOD_DISPLAY.ALT = T("Alt")
end

-- ---------------------------------------------------------------------------
--  Class presets (dispel / rez) — IDs, name only as fallback.
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
--  DB access
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
	return ns.T("No spec")
end

-- All specs of the player's class (for the spec-selection dropdown of the options).
function CC:GetSpecList()
	local out = {}
	local n = GetNumSpecializations and GetNumSpecializations() or 0
	for i = 1, n do
		local id, name, _, icon = GetSpecializationInfo(i)
		if id then out[#out + 1] = { id = id, name = name, icon = icon } end
	end
	return out
end

-- Bindings list of a spec (default = ACTIVE spec; the options pass a different
-- spec to edit it without switching the live spec). create=true creates it and
-- seeds it once with the defaults (left=target, right=menu). Deleting leaves an
-- empty table behind -> it is NOT re-seeded.
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
--  Key parsing
-- ---------------------------------------------------------------------------
-- "ALT-CTRL-SHIFT-KEY" -> modifiers (run of "MOD-"), key, isMouse, buttonNum.
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

-- Split a mouse-click key into (modifier token, mouse button) resp. reassemble it.
-- Modifier is ONE token ("SHIFT"|"CTRL"|"ALT"|""); on multiple (legacy data) the first.
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
--  Spell resolution / macrotext
-- ---------------------------------------------------------------------------
-- Resolve to the BASE spell so talent/hero-talent overrides cast along.
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
-- forHover adds friend/harm filters for spells. Spell/dispel/rez are ALWAYS
-- @mouseover macros (works for click AND hover).
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
--  Active bindings (filtered)
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
--  CLICK PATH — attributes per secure button
-- ===========================================================================
local buttons = setmetatable({}, { __mode = "k" })   -- registered secure buttons
local applyDirty = false                              -- deferred during combat?

local function getProxy(button, kind)   -- kind = "togglemenu" | "target"
	-- We share the menu proxy with Raidframes (same configuration) -> no double frame.
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

-- Named proxy for the "out of combat only" path (menu): a /click macro with a
-- [nocombat] condition presses this proxy -> the secure togglemenu action runs ONLY
-- out of combat, in combat nothing happens (no accidental menu in M+).
-- Needs a global name (for /click); created once per button + reused.
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
		p:SetAttribute("type1", kind)            -- /click without a button = LeftButton
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
			-- Menu out of combat only: /click [nocombat] on the named proxy. The
			-- togglemenu action runs secure via the proxy, /click + [nocombat] is ungated.
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
			-- Plain left click targets natively (default click binding) -> leave as is.
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

-- When enabled, Click-Cast takes full control: neutralize wildcards, modified
-- clicks without a binding do nothing (Clique model). Assigned keys override that
-- afterwards.
-- SAFE DEFAULTS: left click = "target" (native targeting), right click = WoW unit
-- menu (via the shared menu proxy, since "togglemenu" is 12.0.7-gated).
-- This keeps the standard mapping (left=target, right=menu) intact UNTIL the user
-- assigns BUTTON1/BUTTON2 themselves -> no accidental lockout.
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
		ns.RF_ApplyDefaultClicks(button)   -- restore phase-1 defaults (left=target, right=menu)
	end
end

-- Seam from Raidframes: every created secure button registers here.
function ns.CC_RegisterButton(button)
	buttons[button] = true
	button._ccApplied = button._ccApplied or {}
	if not InCombatLockdown() then applyToButton(button) end
end

-- ===========================================================================
--  HOVERCAST PATH — global secure button + state driver
-- ===========================================================================
local hoverBtn, driver
local lastHoverCount = 0
local HOVER_BTN_NAME = "LumenCCHover"

-- Hovercast is P2 (see Shell/Screens.lua CC_HOVERCAST): the secure key-driver mechanism
-- no longer releases the key cleanly in 12.0.7 -> an assigned hovercast key blocks the
-- action bar. Disabled until the 12.1.0 rework; existing hovercast bindings stay in the
-- profile but are NOT applied (applyHover silences everything). To re-enable: true.
local HOVERCAST_ENABLED = false

local function buildHoverFrames()
	if hoverBtn then return end
	hoverBtn = CreateFrame("Button", HOVER_BTN_NAME, UIParent, "SecureActionButtonTemplate")
	hoverBtn:RegisterForClicks("AnyUp", "AnyDown")   -- cover both key down/up
	hoverBtn:EnableMouse(false)
	hoverBtn:SetSize(1, 1); hoverBtn:SetAlpha(0)
	hoverBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -400, 200)
	hoverBtn:Show()

	driver = CreateFrame("Frame", "LumenCCDriver", UIParent, "SecureHandlerStateTemplate")
	driver:SetFrameRef("hb", hoverBtn)
	-- While [@mouseover,exists]: route the configured keys to the hover button
	-- (override binding). When the mouse leaves the unit: clear all overrides.
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
		-- Parked: make sure nothing stays stuck (clear driver + override bindings),
		-- then set up nothing new -> assigned hovercast bindings block no keys.
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
--  Apply / events / public API
-- ===========================================================================
function CC:ApplyBindings()
	if not ccDB() then return end
	if InCombatLockdown() then applyDirty = true; return end
	for button in pairs(buttons) do applyToButton(button) end
	applyHover()
end

-- Options calls this after every change.
function ns.CC_Apply() CC:ApplyBindings() end

-- Spell list (class/spec spells, not passive) for the options dropdown.
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
							-- "Friendly" = castable on friends/self (helpful OR not harmful).
							-- API missing -> don't filter (friendly=true). Best-effort.
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

-- Aura source for the tracking/whitelist picker (B4): castable spellbook spells
-- (via GetClassSpells) PLUS only the ACTUALLY CHOSEN talents of the active talent
-- tree (declutter — not the whole tree). This makes talent auras selectable
-- without overloading the list with unchosen talents.
-- Dedupe via spellId. Limit: C_Traits only returns the ACTIVE spec -> when editing
-- other specs only the spellbook is available (curated defaults cover those).
function CC:GetAuraSpells()
	local out, seen = {}, {}
	local function add(sid, name, icon)
		if not sid or seen[sid] then return end
		name = name or spellName(sid); if not name then return end
		seen[sid] = true
		icon = icon or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid))
		out[#out + 1] = { id = sid, name = name, icon = icon }
	end
	-- 1. Castable spellbook spells (like Click-Cast, without passives)
	for _, s in ipairs(self:GetClassSpells()) do add(s.id, s.name, s.icon) end
	-- 2. Only CHOSEN talents of the active config (talent auras incl. passive buffs)
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
						if node and (node.activeRank or 0) > 0 then   -- only actually chosen
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

-- CRUD on a specific spec (options pass the edited spec).
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

-- Dropdown helpers for options.
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
