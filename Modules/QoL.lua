local ADDON, ns = ...

-- ===========================================================================
--  Lumen — QoL (quality-of-life module)
--  Cursor ring: a tintable ring that follows the mouse so the cursor is
--  easier to spot in combat. Event-driven visibility; the follow itself is
--  the one legitimate OnUpdate (there is no event for mouse moves), kept
--  minimal: it only re-anchors when the cursor actually moved, and the
--  handler doesn't run at all while the ring frame is hidden.
--  Vendor: auto repair (optionally from the guild bank) + auto-sell junk on
--  MERCHANT_SHOW — purely event-driven, nothing runs outside the vendor visit.
--  Pull timer: /pull chat command driving the native group countdown, plus a
--  movable Ready/Pull button block (MRT-style, no chat typing needed).
--  Trackers: placeable battle-res-pool + Bloodlust icons (charge badge,
--  cooldown swipe, greyed while unavailable).
--  Quick gossip: dungeon NPC dialogs without the mouse — single options are
--  selected automatically (Shift keeps the window), several options get 1-9
--  number keys. Event-driven (GOSSIP_SHOW), nothing runs outside a dialog.
--  Movable windows: Shift+drag any registered Blizzard panel (map, character
--  frame etc.); the position is saved per window in the profile and re-applied
--  whenever the window opens.
-- ===========================================================================

local QoL = {}
ns.QoL = QoL

local floor, max = math.floor, math.max
local format = string.format
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local GetInstanceInfo = GetInstanceInfo
local IsEncounterInProgress = IsEncounterInProgress
local issecretvalue = issecretvalue or function() return false end
local GetCursorPosition = GetCursorPosition
local UnitClass = UnitClass
local InCombatLockdown = InCombatLockdown
local CanMerchantRepair = CanMerchantRepair
local GetRepairAllCost = GetRepairAllCost
local RepairAllItems = RepairAllItems
local IsInGuild = IsInGuild
local CanGuildBankRepair = CanGuildBankRepair
local GetGuildBankWithdrawMoney = GetGuildBankWithdrawMoney
local GetMoney = GetMoney
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local IsInGroup = IsInGroup
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local DoReadyCheck = DoReadyCheck
local SendChatMessage = SendChatMessage
local IsInRaid = IsInRaid
local GetTime = GetTime
local IsItemKeystoneByID = C_Item and C_Item.IsItemKeystoneByID
local CancelUnitBuff = CancelUnitBuff
local IsInInstance = IsInInstance
local IsShiftKeyDown = IsShiftKeyDown
local C_GossipInfo = C_GossipInfo
local strfind, tsort, tonumber = string.find, table.sort, tonumber
local wipe, min = wipe, math.min
local hooksecurefunc = hooksecurefunc
local GetScreenWidth = GetScreenWidth
local GetScreenHeight = GetScreenHeight
local C_AddOns = C_AddOns

-- Built from the real addon-folder name (ADDON) so the path survives a folder rename.
local TEXDIR = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
-- Thickness = pre-baked ring steps (constant outer diameter, ring grows inward;
-- a single texture can't change stroke width by scaling). 1 = thin .. 5 = thick.
local RING_STEPS = 5
local function ringTexture(step)
	step = floor(tonumber(step) or 3)
	if step < 1 then step = 1 elseif step > RING_STEPS then step = RING_STEPS end
	return TEXDIR .. "cursor-ring-" .. step
end

local function db() return ns.Lumen.db.profile.qol.cursor end

-- ---------------------------------------------------------------------------
--  Cursor ring frame (created lazily on first enable)
-- ---------------------------------------------------------------------------
local ring, ringTex
local lastX, lastY

local function onUpdate()
	local s = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = floor(x / s + 0.5), floor(y / s + 0.5)
	if x ~= lastX or y ~= lastY then -- SetPoint only on actual movement
		lastX, lastY = x, y
		ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	end
	-- Stay on top even of TOOLTIP-strata frames that SetToplevel(true) themselves
	-- above us on interaction (e.g. the Edit Mode settings flyout). We already run
	-- an OnUpdate while shown, so re-topping here keeps the ring above them with no
	-- perceptible lag (one C call/frame, and only while the opt-in ring is visible).
	ring:Raise()
end

local function createRing()
	if ring then return end
	ring = CreateFrame("Frame", "LumenCursorRing", UIParent)
	ring:SetFrameStrata("TOOLTIP")
	ring:SetFrameLevel(9999)
	-- Toplevel frames (e.g. the Edit Mode settings flyout, SetToplevel(true))
	-- render ABOVE non-toplevel frames in the SAME strata regardless of frame
	-- level -> a high level alone left the ring behind the flyout. Join the
	-- toplevel bucket; the OnUpdate Raise() then keeps us topmost within it.
	ring:SetToplevel(true)
	ring:EnableMouse(false)
	ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
	ringTex = ring:CreateTexture(nil, "OVERLAY")
	ringTex:SetAllPoints(ring)
	-- OnUpdate never fires while the frame is hidden -> Show/Hide is the gate,
	-- no self-checking poll needed.
	ring:SetScript("OnUpdate", onUpdate)
	ring:Hide()
end

-- Visibility: enabled + (onlyInCombat -> in combat). Combat state comes from
-- the PLAYER_REGEN events on the driver below (event-driven, no polling).
local function updateVisibility()
	if not ring then return end
	local c = db()
	local show = c.enabled
	if show and c.onlyInCombat then show = InCombatLockdown() end
	if show and not ring:IsShown() then
		-- Snap to the cursor BEFORE showing, otherwise the ring flashes at its
		-- stale last position for one frame (OnUpdate runs on the next frame).
		local s = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		lastX, lastY = floor(x / s + 0.5), floor(y / s + 0.5)
		ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", lastX, lastY)
		ring:Show()
	elseif not show and ring:IsShown() then
		ring:Hide()
	end
end

-- Apply settings (size/thickness/color/visibility). Called from the Shell
-- setters, on profile switches and on login.
function QoL:ApplyCursor()
	local c = db()
	if not c.enabled and not ring then return end -- never built, nothing to do
	createRing()
	ring:SetSize(c.size or 28, c.size or 28)
	ringTex:SetTexture(ringTexture(c.thickness or 3))
	-- Class color is NOT a secret value -> tinting is secret-safe.
	local r, g, b = 1, 1, 1
	if c.classColor then
		local _, class = UnitClass("player")
		local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then r, g, b = cc.r, cc.g, cc.b end
	else
		local col = c.color or {}
		r, g, b = col.r or 1, col.g or 1, col.b or 1
	end
	ringTex:SetVertexColor(r, g, b, 1)
	updateVisibility()
end

-- ---------------------------------------------------------------------------
--  Vendor — auto repair + sell junk, runs once per MERCHANT_SHOW. Junk value
--  is summed BEFORE the sale (the sell API reports nothing back); merchant
--  visits are out of combat, so no secret values are involved here.
-- ---------------------------------------------------------------------------
local POOR = Enum.ItemQuality and Enum.ItemQuality.Poor or 0

local function moneyText(copper)
	local gold = floor(copper / 10000)
	local silver = floor((copper % 10000) / 100)
	return gold .. "|cffE9BB69g|r " .. silver .. "|cffc7c7cfs|r"
end

local function junkSellValue()
	local total = 0
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == POOR and not info.hasNoValue then
				local sellPrice = select(11, GetItemInfo(info.itemID))
				if sellPrice then total = total + sellPrice * (info.stackCount or 1) end
			end
		end
	end
	return total
end

local function onMerchantShow()
	local v = ns.Lumen.db.profile.qol.vendor
	local T = ns.T

	if v.sellJunk and C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
		local value = junkSellValue()
		C_MerchantFrame.SellAllJunkItems()
		if value > 0 then
			ns.Lumen:Print(T("Sold junk for %s."):format(moneyText(value)))
		end
	end

	if v.autoRepair and CanMerchantRepair() then
		local cost, canRepair = GetRepairAllCost()
		if canRepair and cost > 0 then
			-- -1 = unlimited guild-bank access (guild master)
			local withdraw = GetGuildBankWithdrawMoney() or 0
			local useGuild = v.useGuildFunds and IsInGuild() and CanGuildBankRepair()
				and (withdraw == -1 or withdraw >= cost)
			if not useGuild and GetMoney() < cost then
				ns.Lumen:Print(T("Not enough gold to repair."))
				return
			end
			RepairAllItems(useGuild)
			if useGuild then
				-- Guild repair can fail silently (daily cap etc.) -> retry on own gold.
				C_Timer.After(0.5, function()
					local rest, still = GetRepairAllCost()
					if still and rest > 0 and GetMoney() >= rest then RepairAllItems(false) end
				end)
				ns.Lumen:Print(T("Repaired all items for %s (guild bank)."):format(moneyText(cost)))
			else
				ns.Lumen:Print(T("Repaired all items for %s."):format(moneyText(cost)))
			end
		end
	end
end

-- ---------------------------------------------------------------------------
--  Pull timer — /pull runs the native group countdown (C_PartyInfo.DoCountdown,
--  the same one Blizzard's /countdown UI uses; everyone sees it, no addon
--  needed on the receiving end). /pull is a CONTESTED name: boss mods
--  (BigWigs/DBM) register it too, and WoW resolves duplicates via the dispatch
--  hash (hash_SlashCmdList) where effectively a load-order coin flip wins.
--  Blizzard keeps that table global explicitly so addons can manage commands
--  dynamically — so while the option is ON we claim the hash entry directly
--  (deterministic) and re-claim once after PLAYER_ENTERING_WORLD (boss mods
--  register late). The displaced handler is restored when the option goes OFF.
-- ---------------------------------------------------------------------------
local pullRegistered = false
local pullPrev -- handler we displaced from /pull (restored on toggle-off)

-- Countdown + ready check are lead/assist rights in a group -> shared gate
-- with a chat hint instead of a silent no-op.
local function leadOk()
	if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		ns.Lumen:Print(ns.T("Requires group lead or assist."))
		return false
	end
	return true
end

local function startCountdown(sec) -- nil = configured default duration
	local p = ns.Lumen.db.profile.qol.pull
	sec = floor(sec or p.duration or 10)
	if sec < 0 then sec = 0 end
	if not leadOk() then return end
	C_PartyInfo.DoCountdown(sec) -- 0 cancels a running countdown
end

local function onPull(input)
	local p = ns.Lumen.db.profile.qol.pull
	if not p.enabled then return end -- stale dispatch entry after toggle-off
	input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if input == "" then
		startCountdown(nil)
	else
		local sec = tonumber(input)
		if not sec then
			ns.Lumen:Print(ns.T("Usage: /pull <seconds> — /pull 0 cancels."))
			return
		end
		startCountdown(sec)
	end
end

-- ---------------------------------------------------------------------------
--  Ready/Pull buttons — movable two-button block for group leads (no chat
--  typing): Ready = ready check, Pull = countdown (left-click start with the
--  configured duration, right-click cancel). Position is profile-bound
--  (qol.pull.btnPos), movable via the Lumen Edit-Mode registry. Built lazily;
--  styled from the shared UI tokens (Shell/Tokens loads before this file).
-- ---------------------------------------------------------------------------
-- One connected block, MRT-style (Florian 2026-07-11): SQUARE corners (the
-- gameplay layer has no rounding, unlike the shell), both buttons flush with
-- a 1px separator and ONE outer border; hover = the button face brightens,
-- no border highlight.
local btnFrame
local BTN_W, BTN_H = 100, 26

local function makeToolButton(parent, labelText, onClick)
	local UI = ns.UI
	local C = UI.C
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(BTN_W, BTN_H)
	local fill = b:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(b)
	UI.SetColor(fill, C.ink600)
	local txt = UI.FS(b, "checkLabel", C.textBody)
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)
	txt:SetText(labelText)
	b:SetScript("OnEnter", function()
		UI.SetColor(fill, C.ink520) -- lighter face only, border stays quiet
		txt:SetTextColor(C.textStrong.r, C.textStrong.g, C.textStrong.b)
	end)
	b:SetScript("OnLeave", function()
		UI.SetColor(fill, C.ink600)
		txt:SetTextColor(C.textBody.r, C.textBody.g, C.textBody.b)
	end)
	b:SetScript("OnClick", onClick)
	return b
end

local function createButtons()
	if btnFrame then return end
	local UI = ns.UI
	btnFrame = CreateFrame("Frame", "LumenGroupTools", UIParent)
	btnFrame:SetSize(BTN_W, BTN_H * 2 + 1) -- +1 = separator line between the two

	local ready = makeToolButton(btnFrame, ns.T("Ready"), function()
		if not leadOk() then return end
		DoReadyCheck()
	end)
	ready:SetPoint("TOP", btnFrame, "TOP", 0, 0)

	-- "Pull" is raid jargon in both languages -> no translation on purpose.
	local pull = makeToolButton(btnFrame, "Pull", function(_, mouse)
		startCountdown(mouse == "RightButton" and 0 or nil)
	end)
	pull:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pull:SetPoint("BOTTOM", btnFrame, "BOTTOM", 0, 0)

	-- Separator + one shared border -> reads as a single connected block.
	local sep = btnFrame:CreateTexture(nil, "ARTWORK")
	sep:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", 0, -BTN_H)
	sep:SetPoint("TOPRIGHT", btnFrame, "TOPRIGHT", 0, -BTN_H)
	sep:SetHeight(1)
	UI.SetColor(sep, UI.line.mid)
	UI.Border(btnFrame, UI.line.mid, 1, "OVERLAY")

	if ns.EditMode then
		ns.EditMode:Register(btnFrame, ns.T("Ready & Pull"), function(pt, x, y)
			ns.Lumen.db.profile.qol.pull.btnPos = { point = pt, x = x, y = y }
		end, nil, "readypull")
	end
end

function QoL:ApplyPull()
	local p = ns.Lumen.db.profile.qol.pull
	local hash = rawget(_G, "hash_SlashCmdList")
	if p.enabled then
		if not pullRegistered then
			-- Base registration (own SLASH_ key; doesn't touch boss-mod keys).
			pullRegistered = true
			SLASH_LUMENPULL1 = "/pull"
			SlashCmdList["LUMENPULL"] = onPull
		end
		if hash and hash["/PULL"] ~= onPull then
			pullPrev = hash["/PULL"] -- remember the boss mod's handler (if any)
			hash["/PULL"] = onPull
		end
	elseif hash and hash["/PULL"] == onPull then
		hash["/PULL"] = pullPrev -- give /pull back (nil = command unknown again)
		pullPrev = nil
	end

	-- Ready/Pull button block (independent of the /pull command toggle).
	-- Position is re-anchored here so profile switches/imports move it along.
	if p.buttons then
		createButtons()
		local pos = p.btnPos or {}
		btnFrame:ClearAllPoints()
		btnFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or -300)
		btnFrame:Show()
	elseif btnFrame then
		btnFrame:Hide()
	end
	-- Re-anchor Edit Mode links (the block may be a coupled child or anchor).
	if ns.EditMode and ns.EditMode.ApplyLinks then ns.EditMode:ApplyLinks() end
end

-- ---------------------------------------------------------------------------
--  Profession-outfit suppression — WoW re-equips the cosmetic profession gear
--  (chef's hat etc.) on every login/character switch, which puts a buff in
--  the aura bar and breaks the transmog. One switch cancels these auras as
--  they land. Curated aura-ID list of the profession outfit pieces (12.0-
--  verified). Canceling own buffs is combat-locked -> combat additions are
--  swept on PLAYER_REGEN_ENABLED. The fishing outfit persists while the
--  fishing channel runs, so it is cleared when that channel stops instead.
--  The watcher only exists while the switch is on and never touches aura
--  payloads in combat (secret values).
-- ---------------------------------------------------------------------------
local OUTFIT_IDS = {
	[388658] = true, -- Blacksmithing
	[394015] = true, -- Jewelcrafting
	[391312] = true, -- Tailoring
	[394007] = true, -- Engineering
	[394008] = true, -- Enchanting
	[394003] = true, -- Alchemy
	[394016] = true, -- Inscription
	[394001] = true, -- Leatherworking
	[394005] = true, -- Herbalism
	[394006] = true, -- Mining
	[394011] = true, -- Skinning
	[391775] = true, -- Cooking (chef's hat — the classic offender)
	[394009] = true, -- Fishing (sticks during the fishing channel, see below)
}
local FISHING_CHANNEL = 131476

local function cancelOutfits()
	if not ns.Lumen.db.profile.qol.buffs.suppressOutfit then return end
	if InCombatLockdown() then return end
	-- Descending: canceling a buff shifts every index above the freed slot.
	for i = 40, 1, -1 do
		local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
		if a then
			local sid = a.spellId
			if sid and not (issecretvalue and issecretvalue(sid)) and OUTFIT_IDS[sid] then
				pcall(CancelUnitBuff, "player", i, "HELPFUL")
			end
		end
	end
end

local buffWatch
function QoL:ApplyOutfitSuppress()
	local on = ns.Lumen.db.profile.qol.buffs.suppressOutfit and true or false
	if on and not buffWatch then
		buffWatch = CreateFrame("Frame")
		buffWatch:SetScript("OnEvent", function(_, event, _, a2, a3)
			if InCombatLockdown() then return end -- secret payloads; regen sweep catches up
			if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
				-- Fishing ended -> the fishing outfit aura is cancelable now.
				if a3 and not (issecretvalue and issecretvalue(a3)) and a3 == FISHING_CHANNEL then
					cancelOutfits()
				end
				return
			end
			local info = a2 -- UNIT_AURA updateInfo
			if not info then return end
			if info.isFullUpdate then cancelOutfits(); return end
			local added = info.addedAuras
			if not added then return end
			for i = 1, #added do
				local sid = added[i].spellId
				if sid and not (issecretvalue and issecretvalue(sid)) and OUTFIT_IDS[sid] then
					cancelOutfits()
					return
				end
			end
		end)
	end
	if buffWatch then
		if on then
			buffWatch:RegisterUnitEvent("UNIT_AURA", "player")
			buffWatch:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		else
			buffWatch:UnregisterEvent("UNIT_AURA")
			buffWatch:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
		end
	end
	cancelOutfits()
end

-- ---------------------------------------------------------------------------
--  Mythic+ helpers — keystone auto-insert (socket the key when the pedestal
--  window opens; Blizzard's own ItemUtil pattern via IsItemKeystoneByID) +
--  instance-reset chat announce (hooks the ResetInstances ATTEMPT, throttled
--  against spam clicks). Both purely event-driven.
-- ---------------------------------------------------------------------------
local function onKeystoneReceptacle()
	if not ns.Lumen.db.profile.qol.mplus.autoKeystone then return end
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID and IsItemKeystoneByID and IsItemKeystoneByID(itemID) then
				C_Container.UseContainerItem(bag, slot)
				return
			end
		end
	end
end

local lastResetMsg = 0
local function installResetAnnounce()
	-- hooksecurefunc cannot be undone -> installed once, gated by the option.
	hooksecurefunc("ResetInstances", function()
		local v = ns.Lumen.db.profile.qol.mplus
		if not v.resetAnnounce or not IsInGroup() then return end
		local now = GetTime()
		if now - lastResetMsg < 2 then return end -- one message per reset click burst
		lastResetMsg = now
		SendChatMessage(ns.T("Instances reset."), IsInRaid() and "RAID" or "PARTY")
	end)
end

-- ---------------------------------------------------------------------------
--  Quick gossip — dungeon NPC dialogs without the mouse. While in a party/
--  raid/scenario instance: (1) a gossip with exactly ONE option and no quests is
--  selected automatically. Blizzard itself only auto-skips when the NPC's
--  option carries selectOptionWhenOnlyOption (GossipFrameShared.lua HandleShow)
--  — this covers the NPCs that lack the flag (Pit-of-Saron-style "talk to
--  continue"); holding SHIFT keeps the window (escape hatch for single-option
--  gossips that start events). Confirmation popups are NEVER auto-accepted.
--  (2) With SEVERAL options (buff picks etc.) the number keys 1-9 select one;
--  the visible options get "1. " prefixes. Selection goes through the official
--  addon API GossipFrame:SelectGossipOption(i) (same sorted order as the
--  prefixes). The keyboard catcher exists only while a multi-option gossip is
--  open and never in combat (SetPropagateKeyboardInput is combat-restricted;
--  everything unhandled propagates -- memory lumen-secure-binding-gotchas).
-- ---------------------------------------------------------------------------
local gossipKb                       -- keyboard catcher (lazy)
local gossipHooked = false           -- GossipFrame.Update re-render hook installed
local gossipNums = {}                -- reused: gossipOptionID -> displayed number
local lastAutoID, lastAutoAt = nil, 0

local function gossipActive()
	if not ns.Lumen.db.profile.qol.mplus.quickGossip then return false end
	local inInstance, itype = IsInInstance()
	-- Instanced group content only (Florian 2026-07-17): dungeons, raids and
	-- scenarios (delves) -- never the open world. Raid boss-RP gossips are the
	-- reason the Shift escape hatch exists.
	return inInstance and (itype == "party" or itype == "raid" or itype == "scenario") or false
end

local function byOrderIndex(a, b) return a.orderIndex < b.orderIndex end

-- Prefix the visible option buttons with their number key ("1. Name"). Runs
-- deferred after Blizzard populated the scroll box; identifies option buttons
-- by their elementData (quest buttons carry questID, options gossipOptionID).
-- Buttons are pooled/recycled -> the prefix pattern check prevents doubling.
local function decorateGossip()
	if not gossipActive() then return end
	if not (GossipFrame and GossipFrame:IsShown() and GossipFrame.GreetingPanel) then return end
	local sb = GossipFrame.GreetingPanel.ScrollBox
	if not (sb and sb.ForEachFrame) then return end
	local opts = C_GossipInfo.GetOptions()
	if #opts < 2 then return end
	tsort(opts, byOrderIndex)
	wipe(gossipNums)
	for i = 1, min(#opts, 9) do
		if opts[i].gossipOptionID then gossipNums[opts[i].gossipOptionID] = i end
	end
	sb:ForEachFrame(function(btn, elementData)
		local info = elementData and elementData.info
		local num = info and info.gossipOptionID and gossipNums[info.gossipOptionID]
		if num and btn.GetText then
			local txt = btn:GetText()
			-- Keep Blizzard's measured height (no Resize) -- the short prefix
			-- must not re-flow the row after the extents were computed.
			if txt and not strfind(txt, "^%d+%. ") then btn:SetText(num .. ". " .. txt) end
		end
	end)
end

local function hideGossipKeys()
	if gossipKb then gossipKb:EnableKeyboard(false); gossipKb:Hide() end
end

local function ensureGossipKeys()
	if gossipKb then return end
	gossipKb = CreateFrame("Frame", nil, UIParent)
	gossipKb:EnableKeyboard(false)
	gossipKb:Hide()
	-- HARD RULES (memory lumen-secure-binding-gotchas): SetPropagateKeyboardInput
	-- only inside OnKeyDown, everything we don't handle MUST propagate, and the
	-- catcher never has the keyboard while in combat (hidden on REGEN_DISABLED).
	gossipKb:SetScript("OnKeyDown", function(self, key)
		local n = strfind(key, "^%d$") and key or (strfind(key, "^NUMPAD%d$") and key:sub(-1))
		local idx = n and tonumber(n)
		if idx and idx >= 1 and GossipFrame and GossipFrame:IsShown()
			and GossipFrame.SelectGossipOption then
			self:SetPropagateKeyboardInput(false)
			GossipFrame:SelectGossipOption(idx) -- no-ops on an out-of-range index
			return
		end
		self:SetPropagateKeyboardInput(true)
	end)
end

local function onGossipShow()
	if not gossipActive() then return end
	local opts = C_GossipInfo.GetOptions()
	-- (1) Auto-select the single option (no quests offered, Shift not held).
	if #opts == 1 and not IsShiftKeyDown()
		and C_GossipInfo.GetNumAvailableQuests() == 0
		and C_GossipInfo.GetNumActiveQuests() == 0 then
		local id = opts[1].gossipOptionID
		local now = GetTime()
		-- Chain guard: dialog chains re-fire GOSSIP_SHOW per step (fine, each
		-- step has a new option) -- but never re-pick the SAME option in quick
		-- succession (a gossip that re-opens itself would loop otherwise).
		if id and (id ~= lastAutoID or now - lastAutoAt > 1) then
			lastAutoID, lastAutoAt = id, now
			C_GossipInfo.SelectOptionByIndex(opts[1].orderIndex)
			return
		end
	end
	-- (2) Several options -> number prefixes + key selection (out of combat).
	if #opts > 1 then
		if not gossipHooked and GossipFrame and GossipFrame.Update then
			gossipHooked = true
			-- Blizzard re-renders the list on QUEST_LOG_UPDATE -> re-decorate.
			hooksecurefunc(GossipFrame, "Update", function()
				if gossipActive() then C_Timer.After(0, decorateGossip) end
			end)
		end
		C_Timer.After(0, decorateGossip) -- scroll box populates this frame; defer one
		if not InCombatLockdown() then
			ensureGossipKeys()
			gossipKb:EnableKeyboard(true)
			gossipKb:Show()
		end
	end
end

-- ---------------------------------------------------------------------------
--  Trackers — battle-res pool + Bloodlust availability as placeable icons
--  (mockup option B: real spell icon, charge badge, cooldown swipe, greyed
--  while unavailable). Brez pool: C_Spell.GetSpellCharges(20484/Rebirth) IS
--  the shared raid/M+ pool — no combat-log math needed; it only means
--  anything while a key runs or a raid boss is engaged, so visibility gates
--  on those events. Sated: querying KNOWN spell IDs via GetPlayerAuraBySpellID
--  works even in combat (returned fields may be secret -> issecretvalue
--  guards before any arithmetic). ONE shared 0.5s ticker runs only while at
--  least one icon is shown; Edit Mode force-shows both for placement.
-- ---------------------------------------------------------------------------
local BREZ_ID = 20484     -- Rebirth (canonical shared-pool spell)
local LUST_ICON_ID = 2825 -- Bloodlust (used for the icon texture only)
local SATED_IDS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435, 428628 }

local trackerState = { challenge = false, encounter = false }
local trackerTicker
local brezFrame, lustFrame

local function fmtTime(s)
	if not s or s <= 0 then return "" end
	return format("%d:%02d", floor(s / 60), floor(s % 60))
end

local function setGrey(f, on)
	if on == f._grey then return end
	f._grey = on
	f.icon:SetDesaturated(on)
	local v = on and 0.6 or 1
	f.icon:SetVertexColor(v, v, v, 1)
end

local function makeTrackerIcon(name, spellID)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(40, 40)
	f:Hide()
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints(f)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon:SetTexture((C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)) or 134400)
	-- thin dark edge (gameplay layer = square + familiar action-button look)
	local edge = f:CreateTexture(nil, "BACKGROUND", nil, -1)
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0, 0, 0, 0.9)
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f)
	f.cd:SetDrawEdge(false)
	f.cd:SetHideCountdownNumbers(true) -- we render our own timer below the icon
	f.count = f.cd:CreateFontString(nil, "OVERLAY")
	f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	f.timer = f.cd:CreateFontString(nil, "OVERLAY")
	f.timer:SetPoint("TOP", f, "BOTTOM", 0, -3)
	return f
end

local function createTrackers()
	if brezFrame then return end
	brezFrame = makeTrackerIcon("LumenBrezTracker", BREZ_ID)
	lustFrame = makeTrackerIcon("LumenLustTracker", LUST_ICON_ID)
	if ns.EditMode then
		-- Quick descriptor: size lives ONLY in the Edit Mode flyout now (the QoL
		-- tab just toggles the tracker on/off) — the real icon resizes live under
		-- the panel. Reset restores the default size + a non-overlapping position.
		local function trackerQuick(which, defX)
			return {
				fields = { { kind = "slider", label = ns.T("Size"), min = 24, max = 80, unit = " px",
					get = function() return ns.Lumen.db.profile.qol.trackers[which].size end,
					set = function(v) ns.Lumen.db.profile.qol.trackers[which].size = v; QoL:ApplyTrackers() end } },
				reset = function()
					local d = ns.Defaults and ns.Defaults.profile.qol.trackers[which]
					local s = ns.Lumen.db.profile.qol.trackers[which]
					s.size = (d and d.size) or 40
					s.pos = { point = "CENTER", x = defX, y = -240 }
					QoL:ApplyTrackers()
				end,
			}
		end
		ns.EditMode:Register(brezFrame, ns.T("Combat res"), function(p, x, y)
			ns.Lumen.db.profile.qol.trackers.brez.pos = { point = p, x = x, y = y }
		end, nil, "brez", trackerQuick("brez", -30))
		ns.EditMode:Register(lustFrame, "Bloodlust", function(p, x, y)
			ns.Lumen.db.profile.qol.trackers.lust.pos = { point = p, x = x, y = y }
		end, nil, "lust", trackerQuick("lust", 30))
	end
end

local function pollBrez()
	local f = brezFrame
	local info = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(BREZ_ID)
	if not info or not info.maxCharges then
		f.count:SetText(""); f.timer:SetText(""); f.cd:Clear()
		setGrey(f, false)
		return
	end
	local c = info.currentCharges or 0
	f.count:SetText(c)
	if c <= 0 then f.count:SetTextColor(0.95, 0.30, 0.30) else f.count:SetTextColor(1, 1, 1) end
	setGrey(f, c <= 0)
	if c < info.maxCharges and (info.cooldownDuration or 0) > 0 and info.cooldownStartTime then
		f.cd:SetCooldown(info.cooldownStartTime, info.cooldownDuration)
		f.timer:SetText(fmtTime(info.cooldownStartTime + info.cooldownDuration - GetTime()))
	else
		f.cd:Clear(); f.timer:SetText("")
	end
end

local function findSated()
	for i = 1, #SATED_IDS do
		local a = C_UnitAuras.GetPlayerAuraBySpellID(SATED_IDS[i])
		if a then return a end
	end
end

local function pollLust()
	local f = lustFrame
	local a = findSated()
	if not a then
		setGrey(f, false); f.cd:Clear(); f.timer:SetText("")
		return
	end
	setGrey(f, true)
	local exp, dur = a.expirationTime, a.duration
	if exp and dur and not issecretvalue(exp) and not issecretvalue(dur) then
		f.cd:SetCooldown(exp - dur, dur)
		f.timer:SetText(fmtTime(exp - GetTime()))
	else
		f.timer:SetText("") -- secret mid-combat -> blank number, no arithmetic
	end
end

local function pollTrackers()
	if brezFrame and brezFrame:IsShown() then pollBrez() end
	if lustFrame and lustFrame:IsShown() then pollLust() end
end

local function challengeActive()
	return (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
		and C_ChallengeMode.IsChallengeModeActive()) or false
end

local function refreshTrackerState()
	trackerState.challenge = challengeActive()
	local _, itype = GetInstanceInfo()
	trackerState.encounter = ((IsEncounterInProgress and IsEncounterInProgress()) or false)
		and itype == "raid"
end

function QoL:UpdateTrackerVisibility()
	local t = ns.Lumen.db.profile.qol.trackers
	if not brezFrame and not (t.brez.enabled or t.lust.enabled) then return end
	createTrackers()
	local editing = (ns.EditMode and ns.EditMode.active) or false
	local _, itype = GetInstanceInfo()
	local inGroupInstance = (itype == "party" or itype == "raid")
	-- Brez pool only exists while a key runs / a raid boss is engaged.
	local showBrez = t.brez.enabled and (editing or (inGroupInstance and (trackerState.challenge or trackerState.encounter)))
	local showLust = t.lust.enabled and (editing or inGroupInstance)
	brezFrame:SetShown(showBrez)
	lustFrame:SetShown(showLust)
	if showBrez or showLust then
		if not trackerTicker then trackerTicker = C_Timer.NewTicker(0.5, pollTrackers) end
		pollTrackers()
	elseif trackerTicker then
		trackerTicker:Cancel(); trackerTicker = nil
	end
end

-- Apply settings (size/position/visibility) — Shell setters, profile switches, login.
function QoL:ApplyTrackers()
	local t = ns.Lumen.db.profile.qol.trackers
	if not brezFrame and not (t.brez.enabled or t.lust.enabled) then return end
	createTrackers()
	local defs = { { f = brezFrame, s = t.brez }, { f = lustFrame, s = t.lust } }
	for i = 1, 2 do
		local f, s = defs[i].f, defs[i].s
		local size = s.size or 40
		f:SetSize(size, size)
		f.count:SetFont(STANDARD_TEXT_FONT, max(10, floor(size * 0.32)), "OUTLINE")
		f.timer:SetFont(STANDARD_TEXT_FONT, max(10, floor(size * 0.30)), "OUTLINE")
		local pos = s.pos or {}
		f:ClearAllPoints()
		f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or -240)
	end
	self:UpdateTrackerVisibility()
	-- Re-anchor Edit Mode links (a tracker may be a coupled child or anchor).
	if ns.EditMode and ns.EditMode.ApplyLinks then ns.EditMode:ApplyLinks() end
end

-- ---------------------------------------------------------------------------
--  Movable windows — Shift+drag Blizzard panels; the position is saved per
--  window (profile-bound, travels with export) and re-applied on every open.
--
--  TAINT RULE (hard-earned, 12.0): PROTECTED panels (e.g. PVEFrame) must never
--  be touched with insecure SetMovable/StartMoving/SetPoint — that taints the
--  frame's whole tree, and the LFG applicant list then throws "attempt to
--  compare a secret number". Protected frames are therefore dragged via a
--  cursor-delta OnUpdate and positioned ONLY through a SecureHandler snippet
--  (executes securely, cannot taint by construction). Non-protected frames use
--  the cheap native StartMoving path. Hooks are permanent once installed
--  (hooksecurefunc can't be removed); every hook body gates on the option.
-- ---------------------------------------------------------------------------
-- Curated panel registry: the frames people actually want to move. Frames of
-- load-on-demand Blizzard addons are hooked when their addon loads.
local WIN_PRELOADED = {
	"CharacterFrame", "FriendsFrame", "PVEFrame", "DressUpFrame", "BankFrame",
	"MailFrame", "GossipFrame", "QuestFrame", "MerchantFrame", "AddonList",
	"ChatConfigFrame", "ItemTextFrame", "LFGDungeonReadyDialog",
	"GuildInviteFrame", "TabardFrame", "GuildRegistrarFrame",
}

local WIN_ADDON_FRAMES = {
	["Blizzard_AchievementUI"]                     = { "AchievementFrame" },
	["Blizzard_AlliedRacesUI"]                     = { "AlliedRacesFrame" },
	["Blizzard_ArchaeologyUI"]                     = { "ArchaeologyFrame" },
	["Blizzard_ArtifactUI"]                        = { "ArtifactFrame" },
	["Blizzard_AuctionHouseUI"]                    = { "AuctionHouseFrame" },
	["Blizzard_BlackMarketUI"]                     = { "BlackMarketFrame" },
	["Blizzard_Calendar"]                          = { "CalendarFrame", "CalendarViewEventFrame" },
	["Blizzard_ChallengesUI"]                      = { "ChallengesKeystoneFrame" },
	["Blizzard_ChromieTimeUI"]                     = { "ChromieTimeFrame" },
	["Blizzard_ClassTalentUI"]                     = { "ClassTalentFrame" },
	["Blizzard_Collections"]                       = { "CollectionsJournal", "WardrobeFrame" },
	["Blizzard_Communities"]                       = { "CommunitiesFrame" },
	["Blizzard_CooldownViewer"]                    = { "CooldownViewerSettings" },
	["Blizzard_EncounterJournal"]                  = { "EncounterJournal" },
	["Blizzard_ExpansionLandingPage"]              = { "ExpansionLandingPage" },
	["Blizzard_FlightMap"]                         = { "FlightMapFrame" },
	["Blizzard_GenericTraitUI"]                    = { "GenericTraitFrame" },
	["Blizzard_GuildBankUI"]                       = { "GuildBankFrame" },
	["Blizzard_GuildControlUI"]                    = { "GuildControlUI" },
	["Blizzard_InspectUI"]                         = { "InspectFrame" },
	["Blizzard_ItemInteractionUI"]                 = { "ItemInteractionFrame" },
	["Blizzard_ItemSocketingUI"]                   = { "ItemSocketingFrame" },
	["Blizzard_ItemUpgradeUI"]                     = { "ItemUpgradeFrame" },
	["Blizzard_MacroUI"]                           = { "MacroFrame" },
	["Blizzard_MajorFactions"]                     = { "MajorFactionRenownFrame" },
	["Blizzard_PlayerSpells"]                      = { "PlayerSpellsFrame" },
	["Blizzard_Professions"]                       = { "ProfessionsFrame" },
	["Blizzard_ProfessionsBook"]                   = { "ProfessionsBookFrame" },
	["Blizzard_ProfessionsCustomerOrders"]         = { "ProfessionsCustomerOrdersFrame" },
	["Blizzard_ScrappingMachineUI"]                = { "ScrappingMachineFrame" },
	["Blizzard_StableUI"]                          = { "StableFrame" },
	["Blizzard_TokenUI"]                           = { "CurrencyTransferMenu" },
	["Blizzard_TrainerUI"]                         = { "ClassTrainerFrame" },
	["Blizzard_TradeSkillUI"]                      = { "TradeSkillFrame" },
	["Blizzard_Transmog"]                          = { "TransmogFrame" },
	["Blizzard_WeeklyRewards"]                     = { "WeeklyRewardsFrame" },
	["Blizzard_WorldMap"]                          = { "WorldMapFrame" },
	["Blizzard_HousingDashboard"]                  = { "HousingDashboardFrame" },
	["Blizzard_HousingCornerstone"]                = { "HousingCornerstonePurchaseFrame" },
	["Blizzard_HousingHouseFinder"]                = { "HouseFinderFrame" },
	["Blizzard_HousingHouseSettings"]              = { "HousingHouseSettingsFrame" },
	["Blizzard_HousingBulletinBoard"]              = { "HousingBulletinBoardFrame" },
	["Blizzard_HousingModelPreview"]               = { "HousingModelPreviewFrame" },
	["Blizzard_DelvesCompanionConfigurationFrame"] = { "DelvesCompanionConfigurationFrame", "DelvesCompanionAbilityListFrame" },
	["Blizzard_DelvesDifficultyPicker"]            = { "DelvesDifficultyPickerFrame" },
}

-- Frames whose body swallows the drag (map clicks, model rotate): the drag
-- target is a child header element instead of the frame itself.
local WIN_DRAG_HEADERS = {
	["WorldMapFrame"] = "WorldMapTitleButton",
}
-- Extra drag handles ON TOP of the body, where a mouse-enabled child covers it.
local WIN_EXTRA_DRAG = {
	["AchievementFrame"] = function(frame) return frame.Header or _G["AchievementFrameHeader"] end,
}

local function wdb() return ns.Lumen.db.profile.qol.windows end

local winFrames = {}       -- hooked: { frame = f, name = "..." } (apply-on-enable loop)
local winHooked = {}       -- [frame] = true (hooks are one-shot)
local winIgnoreSP = {}     -- [frame] = true while WE position it (recursion guard)
local winDeferred = {}     -- frames that appeared in combat -> SetMovable deferred
local winPendingAddons = {} -- LoD addon -> frame names, hooked on ADDON_LOADED
local winInited = false
local winEvents            -- ADDON_LOADED / PLAYER_REGEN_ENABLED driver (lazy)
local securePositioner     -- SecureHandler for protected frames (lazy)

local function winSecureSetPoint(frame, point, relPoint, x, y)
	if InCombatLockdown() then return end
	if not securePositioner then
		-- Parented to UIParent so self:GetParent() inside the snippet IS UIParent.
		securePositioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
	end
	securePositioner:SetFrameRef("f", frame)
	securePositioner:SetAttribute("p", point)
	securePositioner:SetAttribute("rp", relPoint)
	securePositioner:SetAttribute("x", x)
	securePositioner:SetAttribute("y", y)
	securePositioner:Execute([[
		local f = self:GetFrameRef("f")
		if not f then return end
		f:ClearAllPoints()
		f:SetPoint(self:GetAttribute("p"), self:GetParent(), self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
	]])
end

local function winSavePos(name, point, relPoint, x, y)
	wdb().positions[name] = { point = point, relPoint = relPoint, x = x, y = y }
end

local function winApplyPosition(frame, name)
	if not wdb().enabled then return end
	if InCombatLockdown() and frame:IsProtected() then return end
	local pos = wdb().positions[name]
	if not pos or not pos.point then return end
	winIgnoreSP[frame] = true
	if frame:IsProtected() then
		winSecureSetPoint(frame, pos.point, pos.relPoint, pos.x, pos.y)
	else
		frame:ClearAllPoints()
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	end
	winIgnoreSP[frame] = nil
end

-- Cursor-delta drag for PROTECTED frames: we can't StartMoving them without
-- tainting, so the cursor is tracked and the frame repositioned live through
-- the secure snippet. Position is stored center-relative to UIParent
-- (scale-clean). Only one protected frame drags at a time.
local winDrag = {}
local winDragUpdater = CreateFrame("Frame")
winDragUpdater:Hide()

local function winStopSecureDrag()
	winDragUpdater:Hide()
	local frame = winDrag.frame
	if not frame then return end
	if winDrag.curX then
		winSavePos(winDrag.name, "CENTER", "CENTER", winDrag.curX, winDrag.curY)
	end
	winDrag.frame = nil
end

winDragUpdater:SetScript("OnUpdate", function()
	local frame = winDrag.frame
	if not frame then winDragUpdater:Hide(); return end
	if InCombatLockdown() then winStopSecureDrag(); return end
	local cx, cy = GetCursorPosition()
	local es = frame:GetEffectiveScale()
	local ues = UIParent:GetEffectiveScale()
	local ucx, ucy = UIParent:GetCenter()
	local newX = winDrag.startX + (cx - winDrag.cursorX)
	local newY = winDrag.startY + (cy - winDrag.cursorY)
	-- Keep the center on screen (protected frames skip SetClampedToScreen).
	local sw, sh = GetScreenWidth() * ues, GetScreenHeight() * ues
	if newX < 0 then newX = 0 elseif newX > sw then newX = sw end
	if newY < 0 then newY = 0 elseif newY > sh then newY = sh end
	local x = (newX - ucx * ues) / es
	local y = (newY - ucy * ues) / es
	winDrag.curX, winDrag.curY = x, y
	winIgnoreSP[frame] = true
	winSecureSetPoint(frame, "CENTER", "CENTER", x, y)
	winIgnoreSP[frame] = nil
end)

local function winStartSecureDrag(frame, name)
	local fcx, fcy = frame:GetCenter()
	if not fcx then return end
	local es = frame:GetEffectiveScale()
	winDrag.frame = frame
	winDrag.name = name
	winDrag.cursorX, winDrag.cursorY = GetCursorPosition()
	winDrag.startX, winDrag.startY = fcx * es, fcy * es
	winDrag.curX, winDrag.curY = nil, nil
	winDragUpdater:Show()
end

local function winHookFrame(frame, name)
	if winHooked[frame] then return end
	winHooked[frame] = true
	winFrames[#winFrames + 1] = { frame = frame, name = name }

	-- SetMovable is only needed for StartMoving; protected frames skip it
	-- entirely (insecure write = the taint incident above).
	if not frame:IsProtected() then
		if InCombatLockdown() then
			winDeferred[#winDeferred + 1] = frame
			winEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			frame:SetMovable(true)
			frame:SetClampedToScreen(true)
		end
	end

	local dragging -- non-protected only

	local function attachDrag(target)
		if not target or not target.HookScript then return end
		target:HookScript("OnMouseDown", function(_, button)
			if not wdb().enabled then return end
			if button ~= "LeftButton" or not IsShiftKeyDown() then return end
			if frame:IsProtected() then
				if InCombatLockdown() then return end
				winStartSecureDrag(frame, name)
			else
				dragging = true
				frame:StartMoving()
			end
		end)
		target:HookScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" then return end
			if frame:IsProtected() then
				if winDrag.frame == frame then winStopSecureDrag() end
				return
			end
			if not dragging then return end
			dragging = nil
			frame:StopMovingOrSizing()
			-- Never let Blizzard's layout cache own the spot -- OUR saved
			-- position is the single source of truth (import-safe).
			frame:SetUserPlaced(false)
			local p, _, rp, x, y = frame:GetPoint(1)
			if p then winSavePos(name, p, rp, x, y) end
		end)
	end

	local headerName = WIN_DRAG_HEADERS[name]
	attachDrag((headerName and _G[headerName]) or frame)
	local extra = WIN_EXTRA_DRAG[name]
	if extra then
		attachDrag(type(extra) == "function" and extra(frame) or _G[extra])
	end

	frame:HookScript("OnShow", function()
		winApplyPosition(frame, name)
	end)
	frame:HookScript("OnHide", function()
		if winDrag.frame == frame then winStopSecureDrag() end
	end)

	-- Blizzard's panel manager re-seats UI panels on open/layout passes with
	-- its own SetPoint -> re-assert the user's pin (guarded against our own
	-- writes and against fighting an active drag).
	hooksecurefunc(frame, "SetPoint", function()
		if not wdb().enabled then return end
		if winIgnoreSP[frame] then return end
		if winDrag.frame == frame then return end
		if InCombatLockdown() and frame:IsProtected() then return end
		if wdb().positions[name] then winApplyPosition(frame, name) end
	end)

	if frame:IsVisible() then winApplyPosition(frame, name) end
end

local function winTryHook(name)
	local frame = _G[name]
	if frame and frame.HookScript then winHookFrame(frame, name) end
end

local function winInit()
	if winInited then return end
	winInited = true
	winEvents = CreateFrame("Frame")
	winEvents:SetScript("OnEvent", function(self, event, arg1)
		if event == "ADDON_LOADED" then
			local frames = winPendingAddons[arg1]
			if frames then
				winPendingAddons[arg1] = nil
				for i = 1, #frames do winTryHook(frames[i]) end
				if not next(winPendingAddons) then self:UnregisterEvent("ADDON_LOADED") end
			end
		else -- PLAYER_REGEN_ENABLED: frames that appeared in combat
			self:UnregisterEvent("PLAYER_REGEN_ENABLED")
			for i = 1, #winDeferred do
				winDeferred[i]:SetMovable(true)
				winDeferred[i]:SetClampedToScreen(true)
			end
			wipe(winDeferred)
		end
	end)
	for i = 1, #WIN_PRELOADED do winTryHook(WIN_PRELOADED[i]) end
	for addon, frames in pairs(WIN_ADDON_FRAMES) do
		if C_AddOns.IsAddOnLoaded(addon) then
			for i = 1, #frames do winTryHook(frames[i]) end
		else
			winPendingAddons[addon] = frames
		end
	end
	if next(winPendingAddons) then winEvents:RegisterEvent("ADDON_LOADED") end
end

-- Shell setter, profile switches, login. Toggle-off keeps the hooks installed
-- (they can't be removed) but every body bails on the option; open windows
-- return to Blizzard's spot the next time the panel manager seats them.
function QoL:ApplyWindows()
	if not wdb().enabled then return end
	winInit()
	for i = 1, #winFrames do
		local e = winFrames[i]
		if e.frame:IsVisible() then winApplyPosition(e.frame, e.name) end
	end
end

-- Shell reset button: windows fall back to Blizzard defaults on their next open.
function QoL:ResetWindowPositions()
	wipe(wdb().positions)
end

-- ---------------------------------------------------------------------------
--  Event driver — combat gate + login + merchant + keystone + trackers (plain
--  frame, one place for all QoL features to hook their events).
-- ---------------------------------------------------------------------------
local driver

function QoL:Setup()
	if driver then return end
	driver = CreateFrame("Frame")
	driver:RegisterEvent("PLAYER_ENTERING_WORLD")
	driver:RegisterEvent("PLAYER_REGEN_DISABLED")
	driver:RegisterEvent("PLAYER_REGEN_ENABLED")
	driver:RegisterEvent("MERCHANT_SHOW")
	driver:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
	driver:RegisterEvent("GOSSIP_SHOW")
	driver:RegisterEvent("GOSSIP_CLOSED")
	-- Tracker visibility (brez pool / lust icon in group instances)
	driver:RegisterEvent("ENCOUNTER_START")
	driver:RegisterEvent("ENCOUNTER_END")
	driver:RegisterEvent("CHALLENGE_MODE_START")
	driver:RegisterEvent("CHALLENGE_MODE_COMPLETED")
	driver:RegisterEvent("CHALLENGE_MODE_RESET")
	driver:RegisterEvent("WORLD_STATE_TIMER_START")
	driver:RegisterEvent("WORLD_STATE_TIMER_STOP")
	driver:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			QoL:ApplyCursor()
			-- Boss mods (re)register /pull during login -> re-claim shortly after.
			C_Timer.After(3, function() QoL:ApplyPull() end)
			-- The outfit buff lands slightly AFTER the loading screen -> late pass.
			C_Timer.After(2, cancelOutfits)
			refreshTrackerState()
			QoL:UpdateTrackerVisibility()
		elseif event == "MERCHANT_SHOW" then
			onMerchantShow()
		elseif event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
			onKeystoneReceptacle()
		elseif event == "GOSSIP_SHOW" then
			onGossipShow()
		elseif event == "GOSSIP_CLOSED" then
			hideGossipKeys()
		elseif event == "ENCOUNTER_START" then
			local _, itype = GetInstanceInfo()
			trackerState.encounter = (itype == "raid")
			QoL:UpdateTrackerVisibility()
		elseif event == "ENCOUNTER_END" then
			trackerState.encounter = false
			QoL:UpdateTrackerVisibility()
		elseif event == "CHALLENGE_MODE_START" or event == "WORLD_STATE_TIMER_START" then
			trackerState.challenge = challengeActive()
			QoL:UpdateTrackerVisibility()
		elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET"
			or event == "WORLD_STATE_TIMER_STOP" then
			trackerState.challenge = false
			QoL:UpdateTrackerVisibility()
		elseif event == "PLAYER_REGEN_ENABLED" then
			updateVisibility()
			cancelOutfits() -- catch outfit buffs that appeared during combat
		else -- combat start: cursor visibility + drop the gossip keyboard (the
			-- catcher must never hold the keyboard in combat -- propagation
			-- calls are combat-restricted for insecure frames)
			updateVisibility()
			hideGossipKeys()
		end
	end)
	installResetAnnounce()
	-- Edit Mode force-shows the trackers so they can be placed anywhere.
	if ns.EditMode and ns.EditMode.AddListener then
		ns.EditMode:AddListener(function() QoL:UpdateTrackerVisibility() end)
	end
	self:ApplyCursor()
	self:ApplyPull()
	self:ApplyOutfitSuppress()
	self:ApplyTrackers()
	self:ApplyWindows()
end
