-- Spikes/AuraContainerSpike.lua
--
-- Aura Phase 1 -- the two show-stopper feasibility spikes for the 12.1 native
-- AuraContainer migration (see Lumen_Spec_AuraContainer_12.1_Migration.md §3).
-- THROWAWAY: delete this file (and its .toc lines) before the Phase 2 build.
--
-- The two questions this answers in-game on the 12.1 PTR:
--   Spike 2  (/lumenspike2): does CreateFrame("AuraContainer", ...) render on a
--            plain NON-secure frame? -> needed for our test/preview pool.
--   Spike 1  (/lumenspike1): can a per-spellId whitelist be expressed via
--            candidateFilters.includeSpellIDs? -> our Anti-Bloat whitelist.
--
-- Every AuraContainer call is guarded. On live 12.0.x (no "AuraContainer" frame
-- type) the commands print a clear "needs 12.1" message and change nothing, so
-- this file is inert on the retail dev build.

-- luacheck: globals SLASH_LUMENSPIKEONE1 SLASH_LUMENSPIKETWO1 SLASH_LUMENSPIKECLR1 SLASH_LUMENSPIKEHELP1

local CreateFrame       = CreateFrame
local InCombatLockdown  = InCombatLockdown
local C_UnitAuras       = C_UnitAuras
local issecretvalue     = issecretvalue or function() return false end

local ICON_SIZE = 30

-- Fixed, well-known Resto-Druid HoT/buff spellIds. A whitelist MUST be sourced
-- from stable ids like these (spellbook / curated defaults), NOT from scanning
-- live auras: on 12.1 aura.spellId can be a SECRET value, and a map keyed by
-- secrets never matches the real id inside Blizzard's secure filter. This is
-- exactly how EllesmereUI builds includeSpellIDs (curated ids, never scans).
local WL_IDS = {
	[774]    = "Verjüngung (Rejuvenation)",
	[8936]   = "Nachwachsen (Regrowth)",
	[48438]  = "Wildwuchs (Wild Growth)",
	[33763]  = "Blühendes Leben (Lifebloom)",
	[188550] = "Blühendes Leben, 2. Ziel (Lifebloom)",
	[155777] = "Verjüngung/Verschmelzung (Germination)",
	[207386] = "Frühlingsblüte (Spring Blossoms)",
	[102352] = "Cenarion-Hort (Cenarion Ward)",
}
local PREFIX = "|cffD4A34FLumenSpike|r "

local function say(msg) print(PREFIX .. msg) end

-- Tracked hosts/containers so a re-run (or /lumenspikeclear) tidies up first.
local spikeFrames = {}

local function clearSpikes()
	for _, f in ipairs(spikeFrames) do
		f:Hide()
		f:ClearAllPoints()
		f:SetParent(nil)
	end
	wipe(spikeFrames)
end

-- Icon-only button initializer. CustomAuraButtonTemplate ships with NO regions
-- of its own -- without this callback the engine renders nothing visible. We
-- deliberately attach only an Icon texture (no cooldown / duration / stack
-- FontStrings): an unstyled FontString hard-errors inside the engine's SetText
-- path, and an icon alone is enough to answer "does it render?".
local function initButton(button)
	button:SetSize(ICON_SIZE, ICON_SIZE)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetIcon(icon)
end

-- A visible, plainly NON-secure host frame to anchor containers onto. This is
-- the crux of Spike 2: an ordinary UIParent child, nothing secure about it.
local function makeHost(width, height, label)
	local host = CreateFrame("Frame", nil, UIParent)
	host:SetSize(width, height)
	host:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	local bg = host:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(host)
	bg:SetColorTexture(0, 0, 0, 0.55)
	local title = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 2, 3)
	title:SetText(label or "")
	spikeFrames[#spikeFrames + 1] = host
	return host
end

-- Build one native AuraContainer on `parent`, watching "player", with the given
-- group specs. Returns the container, or nil on the "not 12.1" / error path.
-- Order matters: layout + groups first, SetUnit LAST (unit assignment
-- re-evaluates event registration, which is gated on having groups).
local function buildContainer(parent, point, groups)
	if InCombatLockdown() then
		say("|cffff5555Im Kampf -- bitte OOC ausführen.|r")
		return nil
	end

	local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not container then
		say("|cffff5555Frame-Typ 'AuraContainer' nicht verfügbar -- das braucht den 12.1-Client.|r ("
			.. tostring(container) .. ")")
		return nil
	end

	local built, err = pcall(function()
		container:SetPoint(unpack(point))
		container:SetSize(1, 1) -- engine replaces this on each layout pass
		container:SetAuraLayoutAnchorPoint("TOPLEFT")
		container:SetAuraLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)

		for _, g in ipairs(groups) do
			container:AddAuraGroup(g.key, "HELPFUL", {
				maxFrameCount    = 20,
				candidateFilters = g.candidateFilters,
				initializeFrame  = initButton,
				layout = {
					elementWidth   = ICON_SIZE,
					elementHeight  = ICON_SIZE,
					elementSpacingX = 3,
					elementSpacingY = 3,
					forceNewRow    = g.forceNewRow, -- drop this group onto its own row
				},
			})
		end

		container:SetUnit("player")
		container:SetEnabled(true)
		container:UpdateAllAuras()
	end)

	if not built then
		say("|cffff5555Fehler beim Aufbau:|r " .. tostring(err))
	end
	return container
end

-- Diagnostic: how many of the player's current HELPFUL auras expose a SECRET
-- spellId? If any are secret we've proven why a whitelist must never be sourced
-- from live aura reads. Returns total, secretCount, or nil if restricted.
local function diagnoseBuffSecrecy()
	local total, secret = 0, 0
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok then return nil end -- restricted (in combat) -> bail
		if not aura then break end
		total = total + 1
		if issecretvalue(aura.spellId) then secret = secret + 1 end
	end
	return total, secret
end

--------------------------------------------------------------------------------
-- Spike 2: bare render on a non-secure frame
--------------------------------------------------------------------------------
local function runSpike2()
	clearSpikes()
	local host = makeHost(20 * ICON_SIZE, ICON_SIZE + 8,
		"LumenSpike 2 -- alle eigenen Buffs (non-secure Frame)")
	local c = buildContainer(host, { "TOPLEFT", host, "TOPLEFT", 4, -4 }, {
		{ key = "all" }, -- no candidateFilters = every HELPFUL aura
	})
	if c then
		say("Spike 2 aktiv. |cff44ff44ERWARTET:|r deine aktuellen Buff-Icons erscheinen")
		say("in der schwarzen Box oben. Kein Icon trotz vorhandener Buffs = FAIL")
		say("(non-secure Render geht nicht). /lumenspikeclear zum Aufräumen.")
	end
end

--------------------------------------------------------------------------------
-- Spike 1: per-spellId whitelist via candidateFilters.includeSpellIDs
--------------------------------------------------------------------------------
local function runSpike1()
	clearSpikes()

	local total, secret = diagnoseBuffSecrecy()
	if not total then
		say("|cffff5555Auren gerade restricted (Kampf?) -- bitte OOC ausführen.|r")
		return
	end

	-- Whitelist = fixed known ids (WL_IDS). Never sourced from live aura reads.
	local include, wlNames = {}, {}
	for id, name in pairs(WL_IDS) do
		include[id] = true
		wlNames[#wlNames + 1] = name .. " (" .. id .. ")"
	end

	local host = makeHost(20 * ICON_SIZE, 2 * ICON_SIZE + 16,
		"LumenSpike 1 -- oben: ALLE  |  unten: nur Whitelist (feste IDs)")

	local c = buildContainer(host, { "TOPLEFT", host, "TOPLEFT", 4, -4 }, {
		{ key = "all" },                                   -- control: all buffs (row 1)
		{ key = "wl", forceNewRow = true,                  -- whitelisted only (row 2)
		  candidateFilters = { includeSpellIDs = include } },
	})

	if c then
		say(("Diagnose: %d eigene Buffs, davon |cffffcc00%d mit SECRET spellId|r.")
			:format(total, secret))
		if secret > 0 then
			say("=> Das erklärt den leeren Test davor: eine Whitelist darf NICHT aus")
			say("   Live-Auren gebaut werden. Jetzt aus festen IDs (Resto-HoTs).")
		end
		say("Whitelist (nur diese Resto-HoTs dürfen unten stehen):")
		say("|cff88ccff" .. table.concat(wlNames, ", ") .. "|r")
		say("|cff44ff44ERWARTET:|r untere Reihe = NUR die HoTs aus der Liste, die")
		say("gerade auf dir liegen (leg ein paar an). Obere Reihe = alle Buffs.")
	end
end

--------------------------------------------------------------------------------
-- Slash dispatch
--------------------------------------------------------------------------------
local function help()
	say("12.1 AuraContainer-Spikes:")
	say("  /lumenspike2  -- rendert der Container auf einem non-secure Frame?")
	say("  /lumenspike1  -- greift die per-spellId-Whitelist?")
	say("  /lumenspikeclear  -- Test-Frames wieder entfernen")
	say("Interface: " .. tostring(select(4, GetBuildInfo())) .. " (braucht >= 120100 fürs Rendern).")
end

-- Note: WoW derives the handler key by stripping trailing digits from the
-- SLASH_<KEY><n> global, so distinct commands need distinct alpha keys (a
-- "LUMENSPIKE1"/"LUMENSPIKE2" pair would both collapse to key "LUMENSPIKE").
SLASH_LUMENSPIKEONE1 = "/lumenspike1"
SlashCmdList["LUMENSPIKEONE"] = runSpike1
SLASH_LUMENSPIKETWO1 = "/lumenspike2"
SlashCmdList["LUMENSPIKETWO"] = runSpike2
SLASH_LUMENSPIKECLR1 = "/lumenspikeclear"
SlashCmdList["LUMENSPIKECLR"] = function()
	clearSpikes()
	say("Test-Frames entfernt.")
end
SLASH_LUMENSPIKEHELP1 = "/lumenspike"
SlashCmdList["LUMENSPIKEHELP"] = help
