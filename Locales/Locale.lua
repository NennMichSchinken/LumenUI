local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Localization (lightweight in-house system, anti-bloat)
--  The code uses ENGLISH source strings as keys via ns.L. A language table
--  (e.g. deDE) overrides individual keys; if a key is missing, L falls back to
--  the key itself (= the English original). The active language is set at load
--  (Core:OnInitialize, after the profile) — switching requires /reload.
--
--  Usage:  local L = ns.L ;  myLabel = L["Raidframes enabled"]
--  Translate: in Locales/deDE.lua  ns.RegisterLocale("deDE", { ["…"] = "…" })
-- ===========================================================================

local registry = {}   -- lang -> { [englishKey] = translated }
local active = {}      -- currently applied translation table (or empty = English)

-- Register a language table (always, regardless of client language — so a manual
-- language choice also works on clients of other languages).
function ns.RegisterLocale(lang, tbl)
	registry[lang] = tbl
end

-- ns.L: translation if present, otherwise the key itself (English original).
ns.L = setmetatable({}, { __index = function(_, k) return active[k] or k end })

-- ns.T("..."): function form (for files where `L` is already taken).
function ns.T(s) return active[s] or s end

-- Resolve a language preference ("auto"/"enUS"/"deDE") to a concrete language and
-- apply it. "auto" => WoW client language (GetLocale). Unknown/enUS => English.
function ns.ApplyLocale(pref)
	local lang = (not pref or pref == "auto") and GetLocale() or pref
	active = registry[lang] or {}
end

-- "Locale-ready" registry: module constants with translated strings (e.g. dropdown
-- option lists) are built at file load — i.e. BEFORE ApplyLocale. So they pick up
-- the chosen language (incl. manual override), files register a builder here that
-- Core runs right AFTER ApplyLocale (in OnInitialize).
ns.onLocaleReady = {}
function ns.RunLocaleReady()
	for i = 1, #ns.onLocaleReady do ns.onLocaleReady[i]() end
end
