local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Modul: MiniCC-Brücke (optional)
--  Meldet unsere Live-Raidframes als Frame-Provider bei MiniCC an, damit MiniCC
--  seine Cooldown-/Defensiv-Icons an unsere Frames anheften kann (wie an Cell/
--  ElvUI/Blizzard). Rein optional: ohne MiniCC passiert nichts.
--
--  Mechanik: MiniCC stellt ein stabiles globales API-Objekt `MiniCCApi.v1`
--  bereit. Über :RegisterFrameProvider melden wir uns mit:
--    * GetFrames()            -> Array unserer sichtbaren Secure-Buttons
--    * RegisterRefreshFrames  -> MiniCC gibt uns einen Callback, den wir bei
--                                Änderung der Frame-Liste aufrufen.
--  MiniCC liest die Einheit je Frame über frame.unit bzw. :GetAttribute("unit")
--  und filtert selbst auf sichtbar/erlaubt -> unsere Buttons sind kompatibel.
--
--  Timing: MiniCCApi existiert erst, wenn MiniCCs Api/v1.lua geladen ist. Lade-
--  Reihenfolge ist nicht garantiert -> bei PLAYER_LOGIN versuchen UND auf
--  ADDON_LOADED == "MiniCC" reagieren. Alles defensiv in pcall. KEINE harte
--  .toc-Abhängigkeit (nur registrieren, wenn MiniCC vorhanden ist).
-- ===========================================================================

local CreateFrame = CreateFrame

local Mini = {}
ns.MiniCC = Mini

local registered = false

local function tryRegister()
	if registered then return end
	if not (MiniCCApi and MiniCCApi.v1 and MiniCCApi.v1.RegisterFrameProvider) then return end
	local ok = pcall(function()
		MiniCCApi.v1:RegisterFrameProvider({
			Name = "Lumen",
			GetFrames = function()
				return (ns.Raidframes and ns.Raidframes:GetLiveButtons()) or {}
			end,
			RegisterRefreshFrames = function(cb)
				if ns.Raidframes and ns.Raidframes.OnFrameChange then
					ns.Raidframes:OnFrameChange(cb)
				end
			end,
		})
	end)
	if ok then registered = true end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")        -- MiniCC schon geladen (lud vor uns)
watcher:RegisterEvent("ADDON_LOADED")        -- MiniCC lädt nach uns
watcher:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name ~= "MiniCC" then return end
	tryRegister()
	if registered then self:UnregisterAllEvents() end
end)
