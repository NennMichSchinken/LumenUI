local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Edit-Modus
--  Bewegliche Lumen-Elemente bekommen ein Drag-Overlay mit Label.
--  Sichtbar/ziehbar, wenn ENTWEDER der manuelle Schalter (Allgemein) an ist
--  ODER WoWs eigener Edit-Modus läuft (ein Ort für alles).
--  Module melden ihr Frame per :Register an.
-- ===========================================================================

local EditMode = { manual = false, blizzard = false, active = false, items = {} }
ns.EditMode = EditMode

local floor = math.floor

local function makeOverlay(frame, label)
	local o = CreateFrame("Frame", nil, frame)
	o:SetAllPoints()
	o:SetFrameStrata("HIGH")
	o:EnableMouse(true)

	o.bg = o:CreateTexture(nil, "BACKGROUND")
	o.bg:SetAllPoints()
	o.bg:SetColorTexture(0.83, 0.64, 0.31, 0.25)

	local function line() local t = o:CreateTexture(nil, "BORDER"); t:SetColorTexture(0.83, 0.64, 0.31, 0.9); return t end
	local t, b, l, r = line(), line(), line(), line()
	t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(1)
	b:SetPoint("BOTTOMLEFT"); b:SetPoint("BOTTOMRIGHT"); b:SetHeight(1)
	l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); l:SetWidth(1)
	r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); r:SetWidth(1)

	o.text = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	o.text:SetPoint("CENTER")
	o.text:SetText(label)
	o.text:SetTextColor(1, 0.95, 0.82)

	o:SetScript("OnMouseDown", function() frame:StartMoving() end)
	o:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		local p, _, _, x, y = frame:GetPoint()
		local info = EditMode.items[frame]
		if info and info.save then info.save(p, floor(x + 0.5), floor(y + 0.5)) end
	end)
	o:Hide()
	return o
end

function EditMode:_refresh()
	self.active = self.manual or self.blizzard
	for _, info in pairs(self.items) do
		info.overlay:SetShown(self.active)
	end
end

function EditMode:Register(frame, label, save)
	if self.items[frame] then return end
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	self.items[frame] = { label = label, save = save, overlay = makeOverlay(frame, label) }
	if self.active then self.items[frame].overlay:Show() end
end

function EditMode:Toggle(on)            -- manueller Schalter (Allgemein)
	self.manual = on and true or false
	self:_refresh()
end

function EditMode:SetBlizzard(on)       -- WoW-Edit-Modus
	self.blizzard = on and true or false
	self:_refresh()
end

function EditMode:IsActive() return self.manual end

-- An WoWs Edit-Modus andocken: Lumen-Rahmen erscheinen dort als beweglich.
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function()
	if EditModeManagerFrame then
		if EditModeManagerFrame.EnterEditMode then
			hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() EditMode:SetBlizzard(true) end)
		end
		if EditModeManagerFrame.ExitEditMode then
			hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() EditMode:SetBlizzard(false) end)
		end
	end
end)
