-- luacheck configuration for Lumen (WoW Retail addon, Lua 5.1)
-- Call: tools\luacheck.exe .   (or the helper script tools\check.ps1)

std = "lua51"
max_line_length = false          -- long comment lines are ok
unused_args = false              -- event/handler args + implicit 'self' often unused (WoW idiom)

-- 'ADDON' is in every file as `local ADDON, ns = ...`, but only 'ns' is used (standard).
ignore = { "211/ADDON" }

-- Writable WoW globals (we add entries, not only read).
-- LumenDB = our SavedVariables table; read once before AceDB creates it, to tell
-- a fresh install apart from an existing one (see Core:OnInitialize).
globals = { "StaticPopupDialogs", "SlashCmdList", "SLASH_LUMENPULL1", "LumenDB" }

-- Don't check third-party libraries and tools.
exclude_files = { "Libs/", "tools/" }

-- Globals provided by the WoW/Ace3 environment (used read-only).
-- Add newly used API here, otherwise luacheck reports "undefined global".
read_globals = {
    -- Lua/WoW additions
    "wipe", "hooksecurefunc", "issecretvalue", "securecall",
    "tinsert", "tremove", "UISpecialFrames", "PixelUtil",
    -- Frames / core
    "CreateFrame", "CreateFont", "UIParent", "InCombatLockdown", "GetCursorPosition",
    "STANDARD_TEXT_FONT", "GameFontNormal",
    "HideUIPanel", "GameMenuFrame", "EditModeManagerFrame", "GameTooltip", "ColorPickerFrame",
    "ADDONS", -- localized global string (ESC menu "Addons")
    -- Blizzard raid-frame suppression + reload popup
    "CompactRaidFrameContainer", "PartyFrame", "EventUtil", "ReloadUI",
    "StaticPopup_Show",
    -- Units / health
    "UnitExists", "UnitName", "UnitClass", "UnitThreatSituation", "UnitGroupRolesAssigned",
    "UnitIsUnit", "GetSpecializationRole", "UnitIsGroupLeader", "UnitIsGroupAssistant",
    "UnitIsConnected", "UnitIsDeadOrGhost", "UnitIsGhost", "UnitHasIncomingResurrection",
    "GetReadyCheckStatus", "C_IncomingSummon",
    "UnitHealth", "UnitHealthMax", "UnitHealthPercent",
    -- Resource bar (power); UnitPowerPercent resolves the secret value C-side
    "UnitPowerType", "UnitPowerMax", "UnitPowerPercent", "PowerBarColor",
    "UnitGetTotalAbsorbs", "UnitGetTotalHealAbsorbs",
    "UnitGetIncomingHeals", "UnitGetDetailedHealPrediction",
    "CreateUnitHealPredictionCalculator", "UnitGUID",
    "IsInRaid", "IsInGroup", "IsInInstance", "GetNumGroupMembers", "GetNumSubgroupMembers",
    -- Colors / auras / numbers
    "RAID_CLASS_COLORS", "AuraUtil", "CurveConstants",
    "AbbreviateNumbers", "AbbreviateNumbersAlt",
    "CreateColor", "Mixin", "GetTime",
    -- Namespaces
    "C_Timer", "C_UnitAuras", "C_CurveUtil", "C_AddOns", "Enum",
    "C_Spell", "C_SpellBook", "C_Traits", "C_ClassTalents",
    "GetInventoryItemTexture", "GetInventoryItemLink",
    -- Spec / secure bindings (click-cast)
    "GetSpecialization", "GetSpecializationInfo", "GetNumSpecializations",
    "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown",
    "RegisterStateDriver", "UnregisterStateDriver",
    "RegisterAttributeDriver", "UnregisterAttributeDriver",
    "SetOverrideBindingClick", "ClearOverrideBindings",
    -- Pull timer / Mythic+ / buff blocklist / tracker QoL
    "C_PartyInfo", "DoReadyCheck", "SendChatMessage", "CancelUnitBuff",
    "GetInstanceInfo", "IsEncounterInProgress", "C_ChallengeMode",
    -- Quick gossip
    "C_GossipInfo", "GossipFrame",
    -- Auto-accept invites
    "AcceptGroup", "IsGuildMember", "WillAcceptInviteRemoveQueues",
    "C_BattleNet", "C_FriendList", "C_LFGList",
    "StaticPopup_Hide", "StaticPopupSpecial_Hide", "LFGInvitePopup",
    -- Movable windows QoL
    "GetScreenWidth", "GetScreenHeight",
    -- UI scale
    "GetPhysicalScreenSize",
    -- Vendor QoL (repair + junk selling)
    "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems",
    "IsInGuild", "CanGuildBankRepair", "GetGuildBankWithdrawMoney", "GetMoney",
    "C_MerchantFrame", "C_Container", "C_Item", "GetItemInfo",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",
    -- Localization
    "GetLocale",
    -- Ace3
    "LibStub",
    -- Optional foreign addons
    "MiniCCApi",
}
