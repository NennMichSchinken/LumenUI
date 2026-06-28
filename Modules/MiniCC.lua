local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Module: MiniCC bridge (optional)
--  Registers our live raid frames as a frame provider with MiniCC so MiniCC can
--  attach its cooldown/defensive icons to our frames (like to Cell/ElvUI/
--  Blizzard). Purely optional: without MiniCC nothing happens.
--
--  Mechanism: MiniCC exposes a stable global API object `MiniCCApi.v1`.
--  Via :RegisterFrameProvider we register with:
--    * GetFrames()            -> array of our visible secure buttons
--    * RegisterRefreshFrames  -> MiniCC gives us a callback we invoke when the
--                                frame list changes.
--  MiniCC reads the unit per frame via frame.unit or :GetAttribute("unit")
--  and filters for visible/allowed itself -> our buttons are compatible.
--
--  Timing: MiniCCApi only exists once MiniCC's Api/v1.lua has loaded. Load
--  order is not guaranteed -> try on PLAYER_LOGIN AND react to
--  ADDON_LOADED == "MiniCC". All defensive in pcall. NO hard .toc dependency
--  (only register if MiniCC is present).
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
watcher:RegisterEvent("PLAYER_LOGIN")        -- MiniCC already loaded (loaded before us)
watcher:RegisterEvent("ADDON_LOADED")        -- MiniCC loads after us
watcher:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name ~= "MiniCC" then return end
	tryRegister()
	if registered then self:UnregisterAllEvents() end
end)
