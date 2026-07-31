local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Profiler  (developer / beta tool, OFF by default)
--
--  Purpose: never claim a performance number we have not measured. The tool
--  answers three questions and nothing else.
--
--    1. What does Lumen cost the client?      -> engine layer, C_AddOnProfiler
--    2. Where inside Lumen does that sit?     -> our own timing wrappers
--    3. How much of it was REDUNDANT?         -> the probes
--
--  (3) is the one that matters most here: it measures how often a render pass
--  repainted state that had not changed since the previous pass. That RATIO
--  is a property of the render path, not of the group size — a solo capture
--  at a target dummy predicts the raid case, which a raw millisecond number
--  never could.
--
--  ZERO footprint while off, in the literal sense: nothing is instrumented
--  until it is switched on. The measured functions carry no flag check, no
--  branch, nothing — they are the untouched originals. Switching on swaps
--  them for wrappers; switching off puts the originals back.
--
--  Because of that, all instrumentation lives HERE. No render file needs a
--  single profiler line, which also keeps the 200-local budget of
--  Modules/Raidframes.lua untouched.
--
--    /lumenprof              report
--    /lumenprof on | off     persists (account-wide) -> survives /reload,
--                            which is how a LOGIN capture is taken
--    /lumenprof reset        clear counters, keep running
--    /lumenprof cpu          engine layer only (works even while off)
-- ===========================================================================

local Prof = {}
ns.Prof = Prof

local debugprofilestop = debugprofilestop
local format, tsort, wipe = string.format, table.sort, wipe
local UnitClass, UnitGroupRolesAssigned = UnitClass, UnitGroupRolesAssigned
local issecretvalue = issecretvalue

-- ---------------------------------------------------------------------------
--  State
-- ---------------------------------------------------------------------------
Prof.on = false

local stats   = {}      -- key -> { n, ms (SELF time), peak }
local probes  = {}      -- key -> { n, hit }  (hit = would have been skippable)
local hooked  = {}      -- [i] = { tbl, name, fn } — originals, for restore
local nHooked = 0

local tStart  = 0       -- capture start (debugprofilestop ms)
local totalMs = 0       -- sum of all measured SELF time in this capture
local tWorld            -- wall ms from capture start to the first world state
local msWorld           -- our own measured time inside that window
-- Snapshot of what was measured BEFORE the first world state, kept apart from
-- the live counters: the login pass happens once per session, so a `reset`
-- taken before a combat capture must not be able to wipe it.
local loginRows, loginN = {}, 0

-- Non-allocating call stack: wrappers nest (RenderLive -> RenderHealth -> …)
-- and we want SELF time per key, so each level accumulates its children's
-- inclusive time and subtracts it.
local depth, sT0, sChild = 0, {}, {}

local function bump(key, selfMs)
	local s = stats[key]
	if not s then s = { n = 0, ms = 0, peak = 0 }; stats[key] = s end
	s.n = s.n + 1
	s.ms = s.ms + selfMs
	totalMs = totalMs + selfMs
	if selfMs > s.peak then s.peak = selfMs end
end

local function probe(key, skippable)
	local p = probes[key]
	if not p then p = { n = 0, hit = 0 }; probes[key] = p end
	p.n = p.n + 1
	if skippable then p.hit = p.hit + 1 end
end

-- ---------------------------------------------------------------------------
--  Wrapper
--  `post` runs AFTER the timing is closed, so a probe never inflates its own
--  measurement. Instrumented functions must not return more than 4 values
--  (everything we measure returns 0..4).
-- ---------------------------------------------------------------------------
local function makeWrapper(key, orig, post)
	return function(...)
		local d = depth + 1
		depth = d
		sT0[d], sChild[d] = debugprofilestop(), 0
		local a, b, c, e = orig(...)
		local incl = debugprofilestop() - sT0[d]
		depth = d - 1
		if d > 1 then sChild[d - 1] = sChild[d - 1] + incl end
		bump(key, incl - sChild[d])
		if post then post(...) end
		return a, b, c, e
	end
end

local function hook(tbl, name, key, post)
	if type(tbl) ~= "table" then return end
	local orig = tbl[name]
	if type(orig) ~= "function" then return end
	nHooked = nHooked + 1
	hooked[nHooked] = { tbl = tbl, name = name, fn = orig }
	tbl[name] = makeWrapper(key or name, orig, post)
end

local function unhookAll()
	for i = nHooked, 1, -1 do
		local h = hooked[i]
		h.tbl[h.name] = h.fn
		hooked[i] = nil
	end
	nHooked = 0
	depth = 0
end

-- ---------------------------------------------------------------------------
--  Probes — read the INPUTS of a paint and count how often they were
--  unchanged since the previous paint of the same frame. Read after the call,
--  so the values are the ones the pass actually used.
--
--  A class token can be SECRET on identity-restricted units (12.1) and a
--  secret cannot be compared, so it is folded to a constant first — the probe
--  must never be able to throw inside a render pass.
-- ---------------------------------------------------------------------------
local SECRET = "?secret"

local function classOf(u)
	local _, class = UnitClass(u)
	if class == nil then return "?" end
	if issecretvalue and issecretvalue(class) then return SECRET end
	return class
end

-- RenderHealth re-pushes the bar colour on every health event, but the colour
-- only depends on the dispel flag, the dead/offline flag and the class.
local function postHealth(_, f)
	local u = f and f.unit
	if not u then return end
	local class = classOf(u)
	local grey  = f._greyed and true or false
	local dOn   = f._dOn and true or false
	probe("health.color", f.__pSeen and f.__pClass == class
		and f.__pGrey == grey and f.__pDOn == dOn or false)
	f.__pSeen, f.__pClass, f.__pGrey, f.__pDOn = true, class, grey, dOn
end

-- RenderPower re-reads role and class on every energy/rage/mana tick, though
-- both only move on a re-assignment or a role change.
local function postPower(_, f)
	local u = f and f.unit
	if not u then return end
	local class = classOf(u)
	local role  = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u) or "?"
	probe("power.style", f.__qSeen and f.__qClass == class and f.__qRole == role or false)
	f.__qSeen, f.__qClass, f.__qRole = true, class, role
end

-- ---------------------------------------------------------------------------
--  Cursor ring: the suite's only permanent per-frame script. Wrapped through
--  the frame's OnUpdate handler (the ring is a named global frame, so this
--  needs no hook inside the QoL module). Counts how many ticks moved nothing.
-- ---------------------------------------------------------------------------
local ringOrig, ringFrame
local function hookRing()
	local f = _G.LumenCursorRing
	if not f or ringFrame then return end
	local orig = f:GetScript("OnUpdate")
	if not orig then return end
	ringFrame, ringOrig = f, orig
	local lx, ly
	f:SetScript("OnUpdate", function(self, elapsed)
		local t = debugprofilestop()
		orig(self, elapsed)
		bump("qol.cursorRing", debugprofilestop() - t)
		local x, y = GetCursorPosition()
		probe("cursor.idleTick", x == lx and y == ly)
		lx, ly = x, y
	end)
end
local function unhookRing()
	if ringFrame then ringFrame:SetScript("OnUpdate", ringOrig) end
	ringFrame, ringOrig = nil, nil
end

-- ---------------------------------------------------------------------------
--  Install / remove
-- ---------------------------------------------------------------------------
local function install()
	local RF = ns.Raidframes
	-- Login / layout (cold path, but this is where loading-screen time goes).
	hook(RF, "Setup",            "rf.Setup")
	hook(RF, "Enable",           "rf.Enable")
	hook(RF, "UpdateLayout",     "rf.UpdateLayout")
	hook(RF, "ApplyConfig",      "rf.ApplyConfig")
	-- Render path (hot).
	hook(RF, "RenderLive",       "rf.RenderLive")
	hook(RF, "RenderHealth",     "rf.RenderHealth", postHealth)
	hook(RF, "RenderPower",      "rf.RenderPower",  postPower)
	hook(RF, "RenderDispelAuras","rf.RenderDispelAuras")
	hook(RF, "RenderAurasLive",  "rf.RenderAuras")
	hook(RF, "RenderStatus",     "rf.RenderStatus")
	hook(RF, "RenderAggro",      "rf.RenderAggro")
	hook(RF, "RenderCenterIcon", "rf.RenderCenterIcon")
	hook(RF, "GetDispel",        "rf.GetDispel")
	hook(RF, "RefreshIndicators","rf.RefreshIndicators")
	hook(RF, "RefreshPower",     "rf.RefreshPower")
	-- Settings surface (cold, but the first shell open is a visible hitch).
	hook(ns.Shell, "Build",         "shell.Build")
	hook(ns.Shell, "RenderContent", "shell.RenderContent")
	hookRing()
end

-- ---------------------------------------------------------------------------
--  Engine layer — C_AddOnProfiler is always on since 12.0 (the old
--  scriptProfile CVar and GetAddOnCPUUsage were removed). Values are
--  milliseconds of Lua time per frame, attributed by the engine itself.
--  ADDON is our real folder name, so this also reports correctly from the
--  _Dev install.
-- ---------------------------------------------------------------------------
local function metric(name)
	local api = C_AddOnProfiler
	if not (api and api.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then return nil end
	local m = Enum.AddOnProfilerMetric[name]
	if m == nil then return nil end
	local ok, v = pcall(api.GetAddOnMetric, ADDON, m)
	if ok then return v end
	return nil
end

local function reportEngine()
	local avg = metric("SessionAverageTime")
	if not avg then
		print("|cffE9BB69Lumen prof|r  engine layer unavailable (C_AddOnProfiler missing)")
		return
	end
	-- Four decimals on purpose: a lean addon rounds to 0.000 at three, which
	-- reads like "not measured" rather than "small".
	print(format("|cffE9BB69Lumen prof|r  engine (%s): session %.4f ms/frame · recent %.4f · encounter %.4f · peak %.2f",
		ADDON, avg, metric("RecentAverageTime") or 0,
		metric("EncounterAverageTime") or 0, metric("PeakTime") or 0))
	print(format("                 frames over budget: >1ms %d · >5ms %d · >10ms %d · >50ms %d",
		metric("CountTimeOver1Ms") or 0, metric("CountTimeOver5Ms") or 0,
		metric("CountTimeOver10Ms") or 0, metric("CountTimeOver50Ms") or 0))
end

-- ---------------------------------------------------------------------------
--  Report
-- ---------------------------------------------------------------------------
local sortBuf = {}
local function byMs(a, b) return stats[a].ms > stats[b].ms end

local function report()
	-- The ring is opt-in and may have been switched on after the capture
	-- started; picking it up here beats silently reporting nothing for it.
	if Prof.on then hookRing() end
	local dur = (debugprofilestop() - tStart) / 1000    -- seconds
	if dur <= 0 then dur = 0.001 end
	print(format("|cffE9BB69Lumen prof|r  %.1f s captured%s", dur, Prof.on and "" or " (stopped)"))
	reportEngine()

	wipe(sortBuf)
	local n = 0
	for k in pairs(stats) do n = n + 1; sortBuf[n] = k end
	if n == 0 then
		print("                 no samples — is it on? (/lumenprof on, then /reload)")
	else
		tsort(sortBuf, byMs)
		print("                 |cff9d9d9dkey                    calls    ms tot   ms/s    avg µs  peak µs|r")
		for i = 1, n do
			local k, s = sortBuf[i], stats[sortBuf[i]]
			print(format("                 %-22s %6d %8.1f %6.2f %9.1f %8.1f",
				k, s.n, s.ms, s.ms / dur, (s.ms / s.n) * 1000, s.peak * 1000))
		end
	end

	local any = false
	for k, p in pairs(probes) do
		if not any then
			print("                 |cff9d9d9dredundant work (paints over unchanged state)|r")
			any = true
		end
		print(format("                 %-22s %6d calls · %d skippable (%d%%)",
			k, p.n, p.hit, p.n > 0 and (p.hit / p.n * 100) or 0))
	end

	-- The wall-clock window to the first world state is dominated by the
	-- LOADING SCREEN (world load, Blizzard UI), not by us — quoting it as a
	-- Lumen cost would be plain wrong. What is ours is the measured time
	-- inside that window, so report the share and label the rest as theirs.
	if loginN > 0 then
		print("                 |cff9d9d9dlogin pass (snapshot, survives reset)|r")
		for i = 1, loginN do
			local r = loginRows[i]
			print(format("                 %-22s %6d %8.1f", r.key, r.n, r.ms))
		end
	end
	if tWorld then
		if msWorld and msWorld > 0 then
			print(format("                 |cff9d9d9dlogin: Lumen used %.1f ms of the %.1f s until the world appeared (%.2f%%); the rest is the loading screen|r",
				msWorld, tWorld / 1000, msWorld / tWorld * 100))
		else
			print(format("                 |cff9d9d9dlogin: world reached after %.1f s — loading screen, not Lumen (profiler was off, no share measured)|r",
				tWorld / 1000))
		end
	end
end

-- ---------------------------------------------------------------------------
--  Control
-- ---------------------------------------------------------------------------
local function resetCounters()
	wipe(stats); wipe(probes)
	depth, totalMs = 0, 0
	tStart = debugprofilestop()
end

function Prof:Start(silent)
	if self.on then return end
	self.on = true
	resetCounters()
	install()
	if not silent then print("|cffE9BB69Lumen prof|r  on — /lumenprof shows the report") end
end

function Prof:Stop()
	if not self.on then return end
	self.on = false
	unhookAll()
	unhookRing()
end

-- Called from Core:OnInitialize, i.e. BEFORE OnEnable builds the raid frames —
-- so an armed profiler captures the login pass too.
function Prof:Init()
	tStart = debugprofilestop()
	local db = ns.Lumen and ns.Lumen.db
	if db and db.global and db.global.profiler then
		self:Start(true)
		print("|cffE9BB69Lumen prof|r  armed at login — /lumenprof for the report, /lumenprof off to stop")
	end
end

local function persist(on)
	local db = ns.Lumen and ns.Lumen.db
	if db and db.global then db.global.profiler = on or nil end
end

function Prof:Command(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)")
	if cmd == "on" then
		persist(true); self:Start()
		print("                 for a LOGIN capture: /reload now (the setting survives)")
	elseif cmd == "off" then
		persist(false); self:Stop()
		print("|cffE9BB69Lumen prof|r  off")
	elseif cmd == "reset" then
		resetCounters()
		print("|cffE9BB69Lumen prof|r  counters cleared")
	elseif cmd == "cpu" then
		reportEngine()
	elseif cmd == "" or cmd == "report" then
		report()
	else
		print("|cffE9BB69Lumen prof|r  /lumenprof [on|off|reset|cpu]")
	end
end

SLASH_LUMENPROF1 = "/lumenprof"
SlashCmdList["LUMENPROF"] = function(input) Prof:Command(input) end

-- The ring is built lazily on the first ApplyCursor, so a profiler armed at
-- login has to pick it up once the world is there. Same event gives us the
-- login timeline mark.
local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:SetScript("OnEvent", function()
	if not tWorld then
		tWorld  = debugprofilestop() - tStart
		msWorld = totalMs
		for k, s in pairs(stats) do
			loginN = loginN + 1
			loginRows[loginN] = { key = k, n = s.n, ms = s.ms }
		end
		tsort(loginRows, function(a, b) return a.ms > b.ms end)
	end
	if Prof.on then hookRing() end
end)
