local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Lokalisierung (schlankes Eigen-System, Anti-Bloat)
--  Der Code nutzt ENGLISCHE Quelltexte als Keys über ns.L. Eine Sprachtabelle
--  (z.B. deDE) überschreibt einzelne Keys; fehlt ein Key, fällt L auf den Key
--  selbst zurück (= das englische Original). Die aktive Sprache wird beim Laden
--  gesetzt (Core:OnInitialize, nach dem Profil) — Wechsel erfordert /reload.
--
--  Nutzung:  local L = ns.L ;  myLabel = L["Raidframes enabled"]
--  Übersetzen: in Locales/deDE.lua  ns.RegisterLocale("deDE", { ["…"] = "…" })
-- ===========================================================================

local registry = {}   -- lang -> { [englishKey] = translated }
local active = {}      -- aktuell angewandte Übersetzungstabelle (oder leer = Englisch)

-- Eine Sprachtabelle registrieren (immer, unabhängig von der Client-Sprache —
-- damit eine manuelle Sprachwahl auch auf anderssprachigen Clients greift).
function ns.RegisterLocale(lang, tbl)
	registry[lang] = tbl
end

-- ns.L: Übersetzung falls vorhanden, sonst der Key selbst (englisches Original).
ns.L = setmetatable({}, { __index = function(_, k) return active[k] or k end })

-- ns.T("..."): Funktions-Form (für Dateien, in denen `L` schon vergeben ist).
function ns.T(s) return active[s] or s end

-- Sprach-Präferenz ("auto"/"enUS"/"deDE") auf eine konkrete Sprache auflösen und
-- anwenden. "auto" => WoW-Client-Sprache (GetLocale). Unbekannt/enUS => Englisch.
function ns.ApplyLocale(pref)
	local lang = (not pref or pref == "auto") and GetLocale() or pref
	active = registry[lang] or {}
end

-- „Locale-ready"-Register: Modul-Konstanten mit übersetzten Strings (z.B. Dropdown-
-- Optionslisten) werden beim Datei-Laden gebaut — also VOR ApplyLocale. Damit sie die
-- gewählte Sprache (inkl. manueller Override) treffen, registrieren die Dateien hier
-- einen Builder, den Core direkt NACH ApplyLocale (in OnInitialize) ausführt.
ns.onLocaleReady = {}
function ns.RunLocaleReady()
	for i = 1, #ns.onLocaleReady do ns.onLocaleReady[i]() end
end
