-- luacheck-Konfiguration für Lumen (WoW Retail Addon, Lua 5.1)
-- Aufruf: tools\luacheck.exe .   (oder das Helfer-Skript tools\check.ps1)

std = "lua51"
max_line_length = false          -- lange deutsche Kommentarzeilen sind ok
unused_args = false              -- event/handler-Args + implizites 'self' oft ungenutzt (WoW-Idiom)

-- 'ADDON' steht in jeder Datei als `local ADDON, ns = ...`, aber nur 'ns' wird genutzt (Standard).
ignore = { "211/ADDON" }

-- Drittanbieter-Bibliotheken und Werkzeuge nicht prüfen.
exclude_files = { "Libs/", "tools/" }

-- Globals, die das WoW-/Ace3-Environment bereitstellt (nur lesend genutzt).
-- Neu genutzte API hier ergänzen, sonst meldet luacheck "undefined global".
read_globals = {
    -- Lua-/WoW-Ergänzungen
    "wipe", "hooksecurefunc", "issecretvalue", "securecall",
    -- Frames / Core
    "CreateFrame", "UIParent", "InCombatLockdown",
    "STANDARD_TEXT_FONT", "GameFontNormal",
    "HideUIPanel", "GameMenuFrame", "EditModeManagerFrame", "GameTooltip",
    -- Einheiten / Leben
    "UnitExists", "UnitName", "UnitClass",
    "UnitHealth", "UnitHealthMax", "UnitHealthPercent",
    "UnitGetTotalAbsorbs", "UnitGetTotalHealAbsorbs",
    "UnitGetIncomingHeals", "UnitGetDetailedHealPrediction",
    "CreateUnitHealPredictionCalculator", "UnitGUID",
    "IsInRaid", "IsInGroup", "GetNumGroupMembers", "GetNumSubgroupMembers",
    -- Farben / Auren / Zahlen
    "RAID_CLASS_COLORS", "AuraUtil",
    "AbbreviateNumbers", "AbbreviateNumbersAlt",
    "CreateColor", "Mixin", "GetTime",
    -- Namespaces
    "C_Timer", "C_UnitAuras", "C_CurveUtil", "C_AddOns", "Enum",
    "C_Spell", "C_SpellBook", "C_Traits", "C_ClassTalents",
    -- Spec / Secure-Bindings (Click-Cast)
    "GetSpecialization", "GetSpecializationInfo", "GetNumSpecializations",
    "RegisterStateDriver", "UnregisterStateDriver",
    "RegisterAttributeDriver", "UnregisterAttributeDriver",
    "SetOverrideBindingClick", "ClearOverrideBindings",
    -- Ace3
    "LibStub",
}
