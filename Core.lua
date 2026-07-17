local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Core
--  Addon (Ace3), central profiles (AceDB), /lumen.
-- ===========================================================================

local Lumen = LibStub("AceAddon-3.0"):NewAddon("LumenUI", "AceConsole-3.0", "AceEvent-3.0")
ns.Lumen = Lumen

local defaults = {
	profile = {
		raidframes = {
			enabled        = true,

			-- Health bar (shared — "Base" tab)
			healthTexture  = "Lumen Aurora",
			auroraStrength = 0.85,   -- glow alpha for the "Lumen Aurora" texture (bright classes clip toward white at 1.0)
			useClassColor  = true,
			fillColor      = { r = 0.20, g = 0.60, b = 0.30 },
			healPrediction = true,

			-- Status center icon (Base tab). The Dead/Ghost/Offline/Rez center
			-- text is always on (core correctness, no options).
			showReadyCheck = true,  -- ready-check icons in the frame center
			showSummon     = true,  -- incoming-summon status (pending/accepted/declined)

			-- Background & transparency (shared — "Base" tab). Alpha 0..1.
			bgColor         = { r = 0.11, g = 0.11, b = 0.11 }, -- frame background color (was fixed 0.11)
			bgAlpha         = 1,                                -- background opacity
			healthAlpha     = 1,                                -- opacity of the health bar FILL only
			shieldAlpha     = 1,                                -- shield overlay opacity
			healAbsorbAlpha = 1,                                -- heal-absorb overlay opacity
			-- Texture for shield/heal-absorb. Default = tiled Lumen pattern (as before);
			-- any other choice (LSM/Blizzard) is stretched as a smooth fill (Raidframes.lua).
			-- IMPORTANT: keys must match SHIELD_PATTERN/HEALABS_PATTERN in Modules/Raidframes.lua.
			shieldTexture     = "Lumen Schild",
			healAbsorbTexture = "Lumen Heilabsorb",

			-- Text look (shared — "Base" tab): color + outline are taste choices and apply
			-- to raid AND party alike. Size/position/show live PER CONTEXT
			-- (raid/party, because they depend on frame size). nameClassColor overrides nameColor.
			nameClassColor    = false,
			nameColor         = { r = 1, g = 1, b = 1 },
			nameOutline       = "shadow",   -- none | shadow | outline | thick
			healthTextColor   = { r = 1, g = 1, b = 1 },
			healthTextOutline = "shadow",

			-- Frame visibility: show the group frame even when solo (default off -> no frame
			-- when alone; on -> always visible). Sets the SecureGroupHeader attribute showSolo.
			showWhenSolo = false,

			-- Shields (own textures, always visible when shielded)
			absorbStyle     = "Blizzard",         -- Blizzard | Flach
			healAbsorbStyle = "Blizzard",         -- Blizzard | Flach
			healAbsorbColor = { r = 1, g = 1, b = 1 },

			-- (Name/HP text now live PER CONTEXT in raid/party — see below.)

			-- Dispel (secret-safe: Blizzard filter + color curve, works in combat)
			dispelEnabled = true,
			dispelMode    = "recolor",          -- "recolor" (recolor bar) | "overlay" (border+overlay, keeps class color)
			dispelShowAll = false,              -- false = only what I can dispel; true = all dispellable
			dispelAlpha   = 0.30,               -- overlay fill opacity (only mode "overlay")
			dispelColors  = {
				Magic   = { r = 0.20, g = 0.60, b = 1.00 },
				Curse   = { r = 0.64, g = 0.19, b = 0.79 },
				Disease = { r = 0.55, g = 0.41, b = 0.18 },
				Poison  = { r = 0.12, g = 0.69, b = 0.29 },
			},

			-- Aggro warning (secret-safe: the threat API is NOT secret, event-driven).
			-- Two stages: yellow = aggro incoming (status 1-2), red = has aggro (status 3).
			aggroEnabled = true,
			-- Show aggro only in dungeon/raid (default on): solo/open world would otherwise
			-- have the overlay permanently, since you almost always have aggro there.
			aggroInstanceOnly = true,
			-- Per stage: display "border" (border only) | "overlay" (border + overlay).
			-- Text only exists in overlay mode (own toggle). Red/yellow never at the same
			-- time on one frame -> text look (position/size) is SHARED (below).
			aggroColorAggro = { r = 0.90, g = 0.15, b = 0.15 }, -- red, "has aggro" (status 3)
			aggroModeAggro  = "overlay",           -- "border" | "overlay"
			aggroTextAggro  = true,                -- "Aggro" text (only in overlay mode)
			aggroColorWarn  = { r = 0.95, g = 0.80, b = 0.20 }, -- yellow, "aggro incoming" (status 1-2)
			aggroModeWarn   = "border",            -- "border" | "overlay"
			aggroTextWarn   = false,
			-- Shared display for both stages:
			aggroFillAlpha   = 0.22,               -- overlay opacity
			aggroTextSize    = 12,
			aggroTextPoint   = "TOP",
			aggroTextX       = 0,
			aggroTextY       = -2,
			aggroTextOutline = "thick",            -- none | outline | thick

			-- Sorting (global, secure via SecureGroupHeader attributes). "group" = by
			-- raid group (default, as before), "role" = by assigned role in the freely
			-- reorderable priority order. Applies to raid AND party alike.
			sortMode = "group",                    -- "group" | "role"
			sortRoleOrder = { "TANK", "HEALER", "DAMAGER" },  -- priority list (top = first)
			sortApplyRaid = false,                 -- role sorting in raid too? (dungeon/party always)

			-- Layout + position + TEXT PER CONTEXT (group size always fixed 5; never mixed).
			-- orientation: "vertical" = members stacked, groups side by side (default);
			--              "horizontal" = members side by side, groups stacked.
			-- raid = raid (IsInRaid), party = 5-man group/dungeon. Own position AND own
			-- text settings per context (frames have different sizes).
			-- PER CONTEXT only size-/position-dependent fields + show/type remain.
			-- Color/outline of name & HP live shared above (Base).
			raid = {
				width = 114, height = 60, spacing = 6, orientation = "vertical",
				point = "CENTER", x = 0, y = -120,
				showName = true, nameSize = 12, namePoint = "TOPLEFT", nameX = 4, nameY = -3,
				healthTextType = "Aktuell", healthTextSize = 16, healthTextPoint = "CENTER",
				healthTextX = 0, healthTextY = 0,
				-- Indicator icons (role / leader) — per context like all size/
				-- position knobs. Raid defaults OFF (40 icons = noise).
				roleShow = false, roleHideDps = false, roleSize = 14,
				rolePoint = "TOPRIGHT", roleX = -2, roleY = -2,
				leadShow = false, leadSize = 12,
				leadPoint = "TOPLEFT", leadX = -4, leadY = 6,
			},
			party = {
				width = 114, height = 60, spacing = 6, orientation = "vertical",
				point = "CENTER", x = 0, y = -120,
				showName = true, nameSize = 12, namePoint = "TOPLEFT", nameX = 4, nameY = -3,
				healthTextType = "Aktuell", healthTextSize = 16, healthTextPoint = "CENTER",
				healthTextX = 0, healthTextY = 0,
				-- Group defaults ON (5 frames carry the icons well).
				roleShow = true, roleHideDps = false, roleSize = 14,
				rolePoint = "TOPRIGHT", roleX = -2, roleY = -2,
				leadShow = true, leadSize = 12,
				leadPoint = "TOPLEFT", leadX = -4, leadY = 6,
			},

			-- Aura indicators (icon system). Since Feature 1 ALL display knobs are
			-- per context (raid vs party) — the standalone "Auras" tab is gone; the
			-- settings live at the bottom of the Raid resp. Group tab, separated per
			-- context. Every knob therefore exists as <key>Raid / <key>Party:
			-- enabled/spacing/maxIcons/autoFit/showSwipe + anchor/grow/offX/offY/outside/size
			-- (+ filterMode for debuffs). autoFit derives the icon size from the frame
			-- height, otherwise sizeRaid/sizeParty apply. anchor = one of the 9 WoW points
			-- (TOPLEFT…BOTTOMRIGHT); grow = RIGHT|LEFT|UP|DOWN. The tracked-spell list
			-- stays SHARED (whitelist, below). Four categories (HoTs/Defensives/Major/Debuffs);
			-- default only HoTs on, the rest off + pre-placed in different corners
			-- (collision-free when enabled).
			-- Phase 2 (B2/B3): auras.whitelist[specID][spellID] = "hot"|"def"|"major" is seeded
			-- LAZILY on first entering a spec from HOT_DEFAULTS ("hot") + DEF_DEFAULTS ("def")
			-- (Raidframes.lua, whitelistFor) — deliberately NOT here in the defaults, so the first
			-- write creates a real profile-owned table (no mutating of the shared defaults).
			auras = {
				hotsOwn = {
					enabledRaid = true,  enabledParty = true,
					spacingRaid = 2, spacingParty = 2, maxIconsRaid = 5, maxIconsParty = 5,
					autoFitRaid = true, autoFitParty = true, showSwipeRaid = true, showSwipeParty = true,
					anchorRaid = "BOTTOMLEFT", anchorParty = "BOTTOMLEFT", growRaid = "RIGHT", growParty = "RIGHT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
				},
				defensives = {
					enabledRaid = false, enabledParty = false,
					spacingRaid = 2, spacingParty = 2, maxIconsRaid = 3, maxIconsParty = 3,
					autoFitRaid = true, autoFitParty = true, showSwipeRaid = true, showSwipeParty = true,
					anchorRaid = "TOPRIGHT", anchorParty = "TOPRIGHT", growRaid = "LEFT", growParty = "LEFT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
				},
				-- Major CDs (big class cooldowns). Whitelist "major" (MAJOR_DEFAULTS,
				-- Raidframes.lua). Default anchor TOPLEFT = the last free corner (HoTs=BOTTOMLEFT,
				-- Defensives=TOPRIGHT, Debuffs=BOTTOMRIGHT) -> collision-free when enabled.
				major = {
					enabledRaid = false, enabledParty = false,
					spacingRaid = 2, spacingParty = 2, maxIconsRaid = 3, maxIconsParty = 3,
					autoFitRaid = true, autoFitParty = true, showSwipeRaid = true, showSwipeParty = true,
					anchorRaid = "TOPLEFT", anchorParty = "TOPLEFT", growRaid = "RIGHT", growParty = "RIGHT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
				},
				debuffs = {
					enabledRaid = false, enabledParty = false,
					spacingRaid = 2, spacingParty = 2, maxIconsRaid = 4, maxIconsParty = 4,
					autoFitRaid = true, autoFitParty = true, showSwipeRaid = true, showSwipeParty = true,
					anchorRaid = "BOTTOMRIGHT", anchorParty = "BOTTOMRIGHT", growRaid = "LEFT", growParty = "LEFT",
					offXRaid = 0, offXParty = 0, offYRaid = 0, offYParty = 0, outsideRaid = false, outsideParty = false,
					sizeRaid = 16, sizeParty = 22,
					-- Blizzard default filter (per context): "raid" = only raid-relevant debuffs
					-- (like Blizzard's default), "all" = all, "dispellable" = only self-dispellable.
					filterModeRaid = "raid", filterModeParty = "raid",
				},
			},
		},

		-- Click-Cast (cross-cutting: applies to all unit buttons, eventually also
		-- Unit Frames/Nameplates). Bindings live PER SPEC (healers switch specs).
		-- A freshly entered spec is pre-populated with left=target/right=menu (see
		-- ClickCast.getSpec). Mouse-click AND hovercast bindings in ONE list,
		-- separated by the binding.hovercast field.
		clickCast = {
			enabled     = false,
			helpfulOnly = true,   -- limit spell selection to helpful (castable-on-allies) spells
			specs       = {},     -- [specID] = { { key=, type=, ... }, ... }
		},

		-- QoL (quality-of-life module; each feature has its own sub-table).
		qol = {
			cursor = {
				enabled      = false,                      -- cursor ring off by default (opt-in)
				classColor   = true,                       -- tint the ring in the player's class color
				color        = { r = 0.914, g = 0.733, b = 0.412 }, -- custom ring color (Lumen brand gold #E9BB69)
				size         = 28,                         -- ring diameter in px
				thickness    = 3,                          -- ring thickness step (1 thin .. 5 thick)
				onlyInCombat = false,                      -- show only while in combat
			},
			vendor = {
				autoRepair    = false, -- repair all items automatically at merchants (opt-in)
				useGuildFunds = false, -- pay repairs from the guild bank when possible
				sellJunk      = false, -- sell junk (grey) items automatically at merchants
			},
			pull = {
				enabled  = false, -- register the /pull chat command (opt-in; BigWigs/DBM claim /pull too)
				duration = 10,    -- default countdown seconds (plain /pull + Pull button)
				buttons  = false, -- movable Ready/Pull button block (MRT-style)
				btnPos   = { point = "CENTER", x = 0, y = -300 }, -- block position (Edit Mode)
			},
			mplus = {
				autoKeystone  = false, -- auto-insert the keystone when the pedestal opens
				resetAnnounce = false, -- announce instance resets to the group
				quickGossip   = false, -- dungeon gossip: auto-select single options, 1-9 keys
			},
			buffs = {
				suppressOutfit = false, -- auto-cancel cosmetic profession-gear buffs (chef's hat etc.)
			},
			trackers = {
				-- Placeable icons (Edit Mode). Brez shows only while a key runs /
				-- a raid boss is engaged; lust shows in group instances.
				brez = { enabled = false, size = 40, pos = { point = "CENTER", x = -30, y = -240 } },
				lust = { enabled = false, size = 40, pos = { point = "CENTER", x = 30, y = -240 } },
			},
		},

		-- Edit Mode links (Phase 2): explicit coupling of movable elements.
		-- [childKey] = { to = anchorKey, offX = n, offY = n }. The child's
		-- BOTTOMLEFT anchors to the anchor frame's BOTTOMLEFT + (offX, offY);
		-- the engine then moves the group. Empty by default (nothing coupled).
		editLinks = {},

		-- UI scale (PROFILE-bound so it travels with export/import): optional
		-- management of the GAME's UI scale. "Pixel perfect" = 768/screen height
		-- (the ElvUI-style formula) -> crisp 1:1 pixels and a profile that looks
		-- identical on every machine, which keeps imported layouts from jumping.
		uiScale = {
			enabled      = false, -- off = Lumen never touches the game's UI scale
			pixelPerfect = true,  -- compute 768/screenHeight (recommended)
			scale        = 0.71,  -- manual scale when pixelPerfect is off (0.40..1.15)
		},
	},

	-- Global (account-wide, not profile-bound): runtime-learned aura signatures per
	-- spec. Map [specID] = { ["1:0:1:0"] = spellID }. Filled passively out of combat
	-- (spellId is readable then) and persisted -> in combat we can identify secret
	-- auras by their signature (aura whitelist phase 2). See §10.8.
	global = {
		auraSigs = {},
		language = "auto",   -- UI language: "auto" (system language) | "enUS" | "deDE"
		shellScale = 0.7,    -- user multiplier on the responsive Suite-Shell scale (0.7 = Florian's sweet spot, 2026-07-16)
	},
}

-- Expose the defaults to other modules (Share/Import merges onto them, so missing
-- fields of an imported code are filled cleanly with Lumen defaults).
ns.Defaults = defaults

-- Name/HP text fields that live per context (raid/party) (for the migration).
local TEXT_FIELDS = {
	"showName", "nameSize", "namePoint", "nameX", "nameY", "nameColor", "nameOutline",
	"healthTextType", "healthTextSize", "healthTextPoint", "healthTextX", "healthTextY",
	"healthTextColor", "healthTextOutline",
}
-- v3: text LOOK (color + outline) moves from raid/party back to the shared level
-- (taste choice, same for both contexts). Size/position/show stay per context.
local SHARED_TEXT_FIELDS = { "nameColor", "nameOutline", "healthTextColor", "healthTextOutline" }

-- One-time migration: carry old flat values into raid + party, so existing profiles
-- are not reset when moving to the context model.
local function migrateLayout(rf)
	if not rf then return end
	-- v1: layout/position -> raid/party
	if not rf._layoutMigrated then
		rf._layoutMigrated = true
		if rf.width or rf.height or rf.spacing or rf.orientation or rf.point then
			for _, ctx in ipairs({ "raid", "party" }) do
				local t = rf[ctx]; if t then
					if rf.width       then t.width = rf.width end
					if rf.height      then t.height = rf.height end
					if rf.spacing     then t.spacing = rf.spacing end
					if rf.orientation then t.orientation = rf.orientation end
					if rf.point       then t.point = rf.point end
					if rf.x           then t.x = rf.x end
					if rf.y           then t.y = rf.y end
				end
			end
			rf.width, rf.height, rf.spacing, rf.orientation = nil, nil, nil, nil
			rf.point, rf.x, rf.y = nil, nil, nil
		end
	end
	-- v2: name/HP text -> raid/party (deep-copy colors, otherwise both contexts share
	-- the same table).
	if not rf._textMigrated then
		rf._textMigrated = true
		local hasOld = false
		for _, k in ipairs(TEXT_FIELDS) do if rf[k] ~= nil then hasOld = true; break end end
		if hasOld then
			for _, ctx in ipairs({ "raid", "party" }) do
				local t = rf[ctx]
				if t then
					for _, k in ipairs(TEXT_FIELDS) do
						local v = rf[k]
						if v ~= nil then
							if type(v) == "table" then t[k] = { r = v.r, g = v.g, b = v.b } else t[k] = v end
						end
					end
				end
			end
			for _, k in ipairs(TEXT_FIELDS) do rf[k] = nil end
		end
	end
	-- v3: text look (color/outline) from raid/party -> shared. Source = raid (else party);
	-- for existing profiles both contexts are usually identical anyway.
	if not rf._textSharedMigrated then
		rf._textSharedMigrated = true
		local src = rf.raid or rf.party
		if src then
			-- src[k] only returns a value if the user customized it per context
			-- (raid defaults no longer have these fields). No rf[k]==nil guard: it would
			-- never trigger due to AceDB's default metatable and would discard the change.
			for _, k in ipairs(SHARED_TEXT_FIELDS) do
				local v = src[k]
				if v ~= nil then
					if type(v) == "table" then rf[k] = { r = v.r, g = v.g, b = v.b } else rf[k] = v end
				end
			end
		end
		for _, ctx in ipairs({ "raid", "party" }) do
			local t = rf[ctx]
			if t then for _, k in ipairs(SHARED_TEXT_FIELDS) do t[k] = nil end end
		end
	end
	-- v4: aura placement (anchor/growth) from shared -> per context (raid/party). Offset X/Y
	-- + inside/outside are new (default 0/inside). Carry existing shared anchor/grow up to BOTH
	-- contexts. pairs() only hits category tables the user actually touched
	-- (default-only categories need nothing -> use the new defaults). No cat.x==nil guard
	-- needed: anchor/grow no longer exist in the new defaults -> only returns saved values.
	if not rf._auraCtxMigrated then
		rf._auraCtxMigrated = true
		local au = rawget(rf, "auras")
		if au then
			for _, cat in pairs(au) do
				if type(cat) == "table" then
					local a, g = rawget(cat, "anchor"), rawget(cat, "grow")
					if a ~= nil then
						cat.anchorRaid = rawget(cat, "anchorRaid") or a
						cat.anchorParty = rawget(cat, "anchorParty") or a
						cat.anchor = nil
					end
					if g ~= nil then
						cat.growRaid = rawget(cat, "growRaid") or g
						cat.growParty = rawget(cat, "growParty") or g
						cat.grow = nil
					end
				end
			end
		end
		-- v5: aura DISPLAY knobs (enabled/spacing/maxIcons/autoFit/showSwipe/filterMode)
		-- also moved from shared -> per context (Feature 1). Deliberately NO carry-over
		-- (fresh defaults, agreed) — just strip the now-obsolete unsuffixed fields so they
		-- don't linger in saved profiles / exports. hideTooltips is dropped entirely (unused).
		if not rf._auraDisplayCtxMigrated then
			rf._auraDisplayCtxMigrated = true
			local aud = rawget(rf, "auras")
			if aud then
				for _, cat in pairs(aud) do
					if type(cat) == "table" then
						cat.enabled, cat.spacing, cat.maxIcons = nil, nil, nil
						cat.autoFit, cat.showSwipe, cat.filterMode = nil, nil, nil
						cat.hideTooltips = nil
					end
				end
			end
		end
	end
end

function Lumen:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("LumenDB", defaults, true)
	-- 'global' is an AceDB top-level namespace (db.global), NOT db.profile.global.
	if ns.ApplyLocale then ns.ApplyLocale(self.db.global.language) end
	if ns.RunLocaleReady then ns.RunLocaleReady() end   -- build localized module constants now (after language choice)
	migrateLayout(self.db.profile.raidframes)
	if ns.ClickCast then ns.ClickCast:MigrateCatalog() end

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshAll")
	self.db.RegisterCallback(self, "OnProfileCopied",  "RefreshAll")
	self.db.RegisterCallback(self, "OnProfileReset",   "RefreshAll")

	self:RegisterChatCommand("lumenui", "OpenConfig")
	self:RegisterChatCommand("lumen",   "OpenConfig") -- short alias (kept)
	self:RegisterChatCommand("lu",      "OpenConfig")

	self:Print(ns.T("loaded. |cffE9BB69/lumen|r opens the settings."))
end

function Lumen:OnEnable()
	if ns.Raidframes then
		ns.Raidframes:Setup()
		if self.db.profile.raidframes.enabled then
			ns.Raidframes:Enable()
		end
	end
	if ns.QoL then ns.QoL:Setup() end
	-- UI scale: Blizzard re-applies the CVar scale on these -> assert ours after.
	self:RegisterEvent("UI_SCALE_CHANGED", "ApplyUIScale")
	self:RegisterEvent("DISPLAY_SIZE_CHANGED", "ApplyUIScale")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyUIScale")
	self:ApplyUIScale()
end

-- ---------------------------------------------------------------------------
--  UI scale — optional management of the game's UI scale (defaults: uiScale).
--  UIParent:SetScale (not the CVar: the CVar floor is 0.64, pixel perfect on
--  1440p needs 0.5333). Deferred to combat end when called in combat.
-- ---------------------------------------------------------------------------
function Lumen:ApplyUIScale()
	local s = self.db.profile.uiScale
	if not s or not s.enabled then return end
	if InCombatLockdown() then
		-- Rescaling UIParent mid-combat shifts protected frames -> defer.
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "ApplyUIScale")
		return
	end
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	local target
	if s.pixelPerfect then
		local _, physH = GetPhysicalScreenSize()
		target = 768 / physH
	else
		target = s.scale or 0.71
	end
	if target < 0.4 then target = 0.4 elseif target > 1.15 then target = 1.15 end
	if math.abs(UIParent:GetScale() - target) > 0.0005 then
		UIParent:SetScale(target)
		-- The shell computes its physical size from the effective scale.
		if ns.Shell and ns.Shell.ApplyScale then ns.Shell:ApplyScale() end
	end
end

function Lumen:RefreshAll()
	if not ns.Raidframes then return end
	migrateLayout(self.db.profile.raidframes)
	if self.db.profile.raidframes.enabled then
		ns.Raidframes:Enable()
		ns.Raidframes:UpdateLayout()
	else
		ns.Raidframes:Disable()
	end
	-- Profile switch: re-apply Click-Cast bindings (bindings are profile-bound).
	if ns.ClickCast then ns.ClickCast:MigrateCatalog(); ns.ClickCast:ApplyBindings() end
	-- QoL features re-read the (possibly new) profile.
	if ns.QoL then
		ns.QoL:ApplyCursor(); ns.QoL:ApplyPull()
		ns.QoL:ApplyOutfitSuppress(); ns.QoL:ApplyTrackers()
	end
	-- UI scale is profile-bound -> re-assert on profile switch/import.
	self:ApplyUIScale()
	-- Edit Mode links are profile-bound: after every module re-applied its own
	-- (absolute) positions, re-anchor coupled children onto their anchors.
	if ns.EditMode and ns.EditMode.ApplyLinks then ns.EditMode:ApplyLinks() end
	-- If the suite shell is open, pull its controls onto the (possibly new) profile
	-- values. Closed: still drop its screen cache — cached screens would otherwise
	-- show the OLD profile's values on the next open.
	if ns.Shell and ns.Shell._frame and ns.Shell._frame:IsShown() then
		ns.Shell:RenderContent(true)
	elseif ns.Shell and ns.Shell.InvalidateScreenCache then
		ns.Shell:InvalidateScreenCache()
	end
end

function Lumen:OpenConfig()
	-- /lumen -> suite shell (the one and only UI; also the ESC-menu button).
	if ns.Shell then ns.Shell:Toggle() end
end
