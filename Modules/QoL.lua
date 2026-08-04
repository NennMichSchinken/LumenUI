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
--  Auto-accept invites: group invites from friends and guild members are taken
--  without the popup, guarded so it can never cost you a group, an instance or
--  a queue.
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
local RegisterStateDriver = RegisterStateDriver
local IsInInstance = IsInInstance
local IsShiftKeyDown = IsShiftKeyDown
local C_GossipInfo = C_GossipInfo
local C_BattleNet = C_BattleNet
local C_FriendList = C_FriendList
local C_LFGList = C_LFGList
local AcceptGroup = AcceptGroup
local IsGuildMember = IsGuildMember
local WillAcceptInviteRemoveQueues = WillAcceptInviteRemoveQueues
local StaticPopup_Hide = StaticPopup_Hide
local StaticPopupSpecial_Hide = StaticPopupSpecial_Hide
local GetSpecialization = GetSpecialization
local GetSpecializationRole = GetSpecializationRole
local strfind, tsort, tonumber = string.find, table.sort, tonumber
local wipe, min = wipe, math.min
local hooksecurefunc = hooksecurefunc
local GetScreenWidth = GetScreenWidth
local GetScreenHeight = GetScreenHeight
local C_AddOns = C_AddOns

-- Built from the real addon-folder name (ADDON) so the path survives a folder rename.
local TEXDIR = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\cursor\\" -- QoL draws the cursor-ring-* textures
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

local raiseAcc = 0
local function onUpdate(_, elapsed)
	local s = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = floor(x / s + 0.5), floor(y / s + 0.5)
	if x ~= lastX or y ~= lastY then -- SetPoint only on actual movement
		lastX, lastY = x, y
		ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	end
	-- Stay on top even of TOOLTIP-strata frames that SetToplevel(true) themselves
	-- above us on interaction (e.g. the Edit Mode settings flyout). Throttled: a
	-- frame raising itself over us is a rare, interaction-driven event, while this
	-- ran ~200 times a second and was measured as the ring's dominant cost (98% of
	-- its ticks changed nothing at all). Four times a second is still faster than
	-- anyone can notice, and the position above stays per-frame exact.
	raiseAcc = raiseAcc + (elapsed or 0)
	if raiseAcc >= 0.25 then
		raiseAcc = 0
		ring:Raise()
	end
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

-- Shared chrome for the free-floating gameplay widgets (Ready/Pull block, marker
-- bar): one flat card with padding, a single background and a single border,
-- square corners like the rest of the gameplay layer. Without it the buttons read
-- as loose parts floating on the world (Florian 2026-08-05).
local WIDGET_PAD = 6
local function panelFrame(name)
	local UI = ns.UI
	local f = CreateFrame("Frame", name, UIParent)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	UI.SetColor(bg, UI.Surface.Window)
	bg:SetAlpha(0.9) -- a hair of the world shows through; it is not a window
	UI.Stroke(f, UI.Border.hover, 1, "OVERLAY")
	return f
end

local function makeToolButton(parent, labelText, onClick)
	local UI = ns.UI
	local Surface, Text = UI.Surface, UI.Text
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(BTN_W, BTN_H)
	local fill = b:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(b)
	UI.SetColor(fill, Surface.Card)
	local txt = UI.FS(b, "checkLabel", Text.Secondary)
	txt:SetPoint("CENTER", b, "CENTER", 0, 0)
	txt:SetText(labelText)
	b:SetScript("OnEnter", function()
		UI.SetColor(fill, Surface.Hover) -- lighter face on hover, border stays quiet
		txt:SetTextColor(Text.Primary.r, Text.Primary.g, Text.Primary.b)
	end)
	b:SetScript("OnLeave", function()
		UI.SetColor(fill, Surface.Card)
		txt:SetTextColor(Text.Secondary.r, Text.Secondary.g, Text.Secondary.b)
	end)
	b:SetScript("OnClick", onClick)
	return b
end

local function createButtons()
	if btnFrame then return end
	local UI = ns.UI
	btnFrame = panelFrame("LumenGroupTools")
	btnFrame:SetSize(BTN_W + WIDGET_PAD * 2, BTN_H * 2 + 1 + WIDGET_PAD * 2) -- +1 = separator

	local ready = makeToolButton(btnFrame, ns.T("Ready"), function()
		if not leadOk() then return end
		DoReadyCheck()
	end)
	ready:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", WIDGET_PAD, -WIDGET_PAD)

	-- "Pull" is raid jargon in both languages -> no translation on purpose.
	local pull = makeToolButton(btnFrame, "Pull", function(_, mouse)
		startCountdown(mouse == "RightButton" and 0 or nil)
	end)
	pull:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pull:SetPoint("BOTTOMLEFT", btnFrame, "BOTTOMLEFT", WIDGET_PAD, WIDGET_PAD)

	-- Hairline between the two faces -> they read as one connected block inside
	-- the card (the outer border comes from panelFrame).
	local sep = btnFrame:CreateTexture(nil, "ARTWORK")
	sep:SetPoint("TOPLEFT", ready, "BOTTOMLEFT", 0, 0)
	sep:SetPoint("TOPRIGHT", ready, "BOTTOMRIGHT", 0, 0)
	sep:SetHeight(1)
	UI.SetColor(sep, UI.Border.hover)

	if ns.EditMode then
		local function pdb() return ns.Lumen.db.profile.qol.pull end
		-- Offsets stored in UIParent units, not the block's own scaled ones — see the
		-- same note on the marker bar. Otherwise resizing walks the block away.
		ns.EditMode:Register(btnFrame, ns.T("Ready & Pull"), function(pt, x, y)
			local s = pdb().btnScale or 1
			pdb().btnPos = { point = pt, x = x * s, y = y * s }
		end, nil, "readypull", {
			fields = {
				{ kind = "slider", label = ns.T("Size"), min = 70, max = 160, unit = " %",
					get = function() return math.floor((pdb().btnScale or 1) * 100 + 0.5) end,
					set = function(v) pdb().btnScale = v / 100; QoL:ApplyPull() end },
			},
			reset = function()
				local p = pdb()
				p.btnScale = 1
				p.btnPos = { point = "CENTER", x = 0, y = -300 }
				QoL:ApplyPull()
			end,
		})
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
		local pos, s = p.btnPos or {}, p.btnScale or 1
		btnFrame:SetScale(s)
		btnFrame:ClearAllPoints()
		btnFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER",
			(pos.x or 0) / s, (pos.y or -300) / s)
		btnFrame:Show()
	elseif btnFrame then
		btnFrame:Hide()
	end
	-- Re-anchor Edit Mode links (the block may be a coupled child or anchor).
	if ns.EditMode and ns.EditMode.ApplyLinks then ns.EditMode:ApplyLinks() end
end

-- ---------------------------------------------------------------------------
--  Marker bar — two rows of buttons: target markers (skull, cross, …) on your
--  current target, and world markers on the ground. WoW ships secure action
--  types for exactly this ("raidtarget" / "worldmarker"), so the bar keeps
--  working IN COMBAT, which is the only time anyone needs it. Position is
--  profile-bound (qol.markers.pos) and movable through the Edit-Mode registry.
--
--  Two consequences of the buttons being secure (= protected frames):
--   * visibility runs through a STATE DRIVER, never :Hide() — hiding a frame
--     that has a protected child is refused outright ([[protected ancestor]]).
--   * anchoring/creating is combat-locked -> ApplyMarkers defers to regen.
-- ---------------------------------------------------------------------------
local markerFrame
local markerRows = {}         -- ["target"|"world"] = row frame (own visibility driver)
local markerDeferred          -- an apply arrived in combat -> redo it on regen
local markerEvents
local MK_BTN, MK_GAP, MK_COLS = 22, 2, 9   -- 8 markers + clear
local MK_LABEL_H = 12                       -- row caption ("Target" / "World")
local MK_PAD = WIDGET_PAD                   -- card padding, shared with Ready/Pull
local MK_ROW_W = MK_COLS * MK_BTN + (MK_COLS - 1) * MK_GAP
-- Symbol -> world-marker id. The two are NOT the same numbering: the buttons show
-- the SYMBOL sheet (1 star … 8 skull), while the ground flares have their own ids.
-- Blizzard's own panel resolves it by walking its row in reverse and mapping
-- through WORLD_RAID_MARKER_ORDER, so we read that table at runtime instead of
-- baking a second copy of the mapping (fallback = the table's current contents).
local MK_WORLD_ORDER = { 8, 4, 1, 7, 2, 3, 6, 5 }
local function worldMarkerFor(symbol)
	local order = _G.WORLD_RAID_MARKER_ORDER or MK_WORLD_ORDER
	return order[MK_COLS - symbol] or symbol
end

-- symbol = 1..8 (the icon the button shows), nil = the clear button.
--
-- Everything that has to survive combat runs through MACROS, not through the
-- matching secure action types: 12.0.7 GATES those (`raidtarget` set by an addon
-- is dropped silently — the first version of this bar did exactly nothing), and
-- Click-Cast hit the same wall with "target"/"togglemenu". Slash commands are
-- ungated. Two consequences dictated by that route:
--   * slash names come from the SLASH_* globals — they are LOCALIZED, a literal
--     "/tm" would break every non-English client, including Florian's.
--   * "!<n>" is the toggle form: set the marker, or clear it if the unit already
--     wears it. Hence AnyDown only — down AND up would toggle twice.
-- The two X buttons are NOT symmetric, and that is a hard limit, not a choice:
-- "/cwm All" wipes every ground marker, but there is no slash form for "clear all
-- TARGET markers" — calling RemoveRaidTargets() straight out of an addon is
-- forbidden (ADDON_ACTION_FORBIDDEN, Florian 2026-08-05; pcall does not swallow
-- that, it is an event). Only Blizzard's own raid panel may do it. So the target X
-- clears the marker of the current target, and "[exists]" keeps it QUIET when
-- there is none instead of throwing "You can't do that right now".
local function makeMarkerButton(parent, symbol, world)
	local UI = ns.UI
	local slashTM = _G.SLASH_TARGET_MARKER1 or "/tm"
	local slashWM = _G.SLASH_WORLD_MARKER1 or "/wm"
	local slashCWM = _G.SLASH_CLEAR_WORLD_MARKER1 or "/cwm"
	local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
	b:SetSize(MK_BTN, MK_BTN)
	b:RegisterForClicks("AnyDown")
	b:SetAttribute("type", "macro")
	if world then
		if symbol then
			-- Left places the flare, right takes that one away again.
			local id = worldMarkerFor(symbol)
			b:SetAttribute("macrotext1", slashWM .. " " .. id)
			b:SetAttribute("macrotext2", slashCWM .. " " .. id)
		else
			b:SetAttribute("macrotext", slashCWM .. " " .. (_G.ALL or "All"))
		end
	elseif symbol then
		b:SetAttribute("macrotext1", slashTM .. " !" .. symbol) -- left: set
		b:SetAttribute("macrotext2", slashTM .. " [exists] 0")  -- right: clear
	else
		b:SetAttribute("macrotext", slashTM .. " [exists] 0")
	end
	local fill = b:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(b)
	UI.SetColor(fill, UI.Surface.Card)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
	icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
	icon:SetTexture(symbol and ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. symbol)
		or "Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	-- HIGHLIGHT draw layer = the client shows it on hover by itself, no scripts —
	-- and unlike recolouring the 3px background border behind the icon, an additive
	-- wash over the whole button is actually visible (Florian 2026-08-05).
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	hl:SetColorTexture(1, 1, 1, 0.25)
	hl:SetBlendMode("ADD")
	return b
end

local function createMarkerBar()
	if markerFrame then return end
	local UI = ns.UI
	markerFrame = panelFrame("LumenMarkerBar")

	for _, row in ipairs({ { key = "target", world = false }, { key = "world", world = true } }) do
		-- Each row is its own frame: switching one off means hiding it, and a frame
		-- holding protected buttons may only be hidden by a state driver — which
		-- needs something of its own to act on.
		local rf = CreateFrame("Frame", nil, markerFrame)
		rf:SetSize(MK_ROW_W, MK_LABEL_H + MK_GAP + MK_BTN)
		local head = UI.FS(rf, "checkLabel", UI.Text.Secondary)
		head:SetPoint("TOPLEFT", rf, "TOPLEFT", 0, 0)
		head:SetText(row.world and ns.T("World") or ns.T("Target"))
		for i = 1, MK_COLS do
			-- Last column = clear (no symbol).
			local b = makeMarkerButton(rf, i < MK_COLS and i or nil, row.world)
			b:SetPoint("TOPLEFT", rf, "TOPLEFT", (i - 1) * (MK_BTN + MK_GAP), -(MK_LABEL_H + MK_GAP))
		end
		markerRows[row.key] = rf
	end

	if ns.EditMode then
		local function mdb() return ns.Lumen.db.profile.qol.markers end
		-- Anchor offsets are read back in the FRAME's own units, i.e. already divided
		-- by its scale. Store them in UIParent units (x * scale) so the saved spot
		-- means the same thing at every size — ApplyMarkers divides again. Without
		-- this the bar walked across the screen while the size slider moved
		-- (Florian 2026-08-05); it should grow in place like the trackers.
		ns.EditMode:Register(markerFrame, ns.T("Markers"), function(pt, x, y)
			local s = mdb().scale or 1
			mdb().pos = { point = pt, x = x * s, y = y * s }
		end, nil, "markers", {
			fields = {
				{ kind = "slider", label = ns.T("Size"), min = 70, max = 160, unit = " %",
					get = function() return math.floor((mdb().scale or 1) * 100 + 0.5) end,
					set = function(v) mdb().scale = v / 100; QoL:ApplyMarkers() end },
				{ kind = "check", label = ns.T("Target"),
					get = function() return mdb().target end,
					set = function(v) mdb().target = v; QoL:ApplyMarkers() end },
				{ kind = "check", label = ns.T("World"),
					get = function() return mdb().world end,
					set = function(v) mdb().world = v; QoL:ApplyMarkers() end },
			},
			reset = function()
				local d = ns.Defaults and ns.Defaults.profile.qol.markers
				local s = mdb()
				s.scale, s.target, s.world = (d and d.scale) or 1, true, true
				s.pos = { point = "CENTER", x = 0, y = -260 }
				QoL:ApplyMarkers()
			end,
		})
	end
end

function QoL:ApplyMarkers()
	local m = ns.Lumen.db.profile.qol.markers
	if not (m.enabled or markerFrame) then return end -- never built, still off: nothing to do
	-- Creating, anchoring and scaling protected buttons is combat-locked. Later.
	if InCombatLockdown() then
		markerDeferred = true
		if not markerEvents then
			markerEvents = CreateFrame("Frame")
			markerEvents:SetScript("OnEvent", function(evtFrame)
				evtFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
				if markerDeferred then markerDeferred = nil; QoL:ApplyMarkers() end
			end)
		end
		markerEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	-- Never both rows off: an empty card cannot be clicked in Edit Mode, so there
	-- would be no way back to it.
	if not (m.target or m.world) then m.target = true end
	createMarkerBar()
	markerFrame:SetScale(m.scale or 1)

	-- Stack whichever rows are on; the card shrinks to what is left. Both off is
	-- treated as "bar off" rather than an empty card.
	local y, rows = -MK_PAD, 0
	for _, key in ipairs({ "target", "world" }) do
		local rf = markerRows[key]
		local on = m[key] and true or false
		RegisterStateDriver(rf, "visibility", on and "show" or "hide")
		if on then
			rows = rows + 1
			rf:ClearAllPoints()
			rf:SetPoint("TOPLEFT", markerFrame, "TOPLEFT", MK_PAD, y)
			y = y - rf:GetHeight() - MK_GAP * 2
		end
	end
	markerFrame:SetSize(MK_ROW_W + MK_PAD * 2, (rows > 0 and (-y - MK_GAP * 2 + MK_PAD) or MK_PAD * 2))

	local pos, s = m.pos or {}, m.scale or 1
	markerFrame:ClearAllPoints()
	markerFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER",
		(pos.x or 0) / s, (pos.y or -260) / s) -- see the note on the save callback
	-- Secure visibility: the driver flips the frame, we never do (see header).
	RegisterStateDriver(markerFrame, "visibility", (m.enabled and rows > 0) and "show" or "hide")
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
		-- Same typeface funnel as the raid frames (Global tab: client font vs. Inter).
		if ns.UI and ns.UI.SetFrameFont then
			ns.UI:SetFrameFont(f.count, max(10, floor(size * 0.32)), "OUTLINE")
			ns.UI:SetFrameFont(f.timer, max(10, floor(size * 0.30)), "OUTLINE")
		else
			f.count:SetFont(STANDARD_TEXT_FONT, max(10, floor(size * 0.32)), "OUTLINE")
			f.timer:SetFont(STANDARD_TEXT_FONT, max(10, floor(size * 0.30)), "OUTLINE")
		end
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

-- Load-on-demand panels: these only exist once their Blizzard addon has loaded,
-- so they are hooked from ADDON_LOADED. Listed BY WINDOW (that is how someone
-- looks for one), with the addon that carries it; winInit inverts this into the
-- addon->windows map the event needs. Every addon name below was verified
-- against the 12.1 client source -- the names drift between expansions, and a
-- wrong one silently means "that window is simply never movable".
local WIN_LOD = {
	{ "AchievementFrame",                  "Blizzard_AchievementUI" },
	{ "AlliedRacesFrame",                  "Blizzard_AlliedRacesUI" },
	{ "ArchaeologyFrame",                  "Blizzard_ArchaeologyUI" },
	{ "ArtifactFrame",                     "Blizzard_ArtifactUI" },
	{ "AuctionHouseFrame",                 "Blizzard_AuctionHouseUI" },
	{ "BlackMarketFrame",                  "Blizzard_BlackMarketUI" },
	{ "CalendarFrame",                     "Blizzard_Calendar" },
	{ "CalendarViewEventFrame",            "Blizzard_Calendar" },
	{ "ChallengesKeystoneFrame",           "Blizzard_ChallengesUI" },
	{ "ChromieTimeFrame",                  "Blizzard_ChromieTimeUI" },
	{ "ClassTrainerFrame",                 "Blizzard_TrainerUI" },
	{ "CollectionsJournal",                "Blizzard_Collections" },
	{ "CommunitiesFrame",                  "Blizzard_Communities" },
	{ "CooldownViewerSettings",            "Blizzard_CooldownViewer" },
	{ "CurrencyTransferMenu",              "Blizzard_TokenUI" },
	{ "DelvesCompanionAbilityListFrame",   "Blizzard_DelvesCompanionConfiguration" },
	{ "DelvesCompanionConfigurationFrame", "Blizzard_DelvesCompanionConfiguration" },
	{ "DelvesDifficultyPickerFrame",       "Blizzard_DelvesDifficultyPicker" },
	{ "EncounterJournal",                  "Blizzard_EncounterJournal" },
	{ "ExpansionLandingPage",              "Blizzard_ExpansionLandingPage" },
	{ "FlightMapFrame",                    "Blizzard_FlightMap" },
	{ "GenericTraitFrame",                 "Blizzard_GenericTraitUI" },
	{ "GuildBankFrame",                    "Blizzard_GuildBankUI" },
	{ "GuildControlUI",                    "Blizzard_GuildControlUI" },
	{ "HouseFinderFrame",                  "Blizzard_HousingHouseFinder" },
	{ "HousingBulletinBoardFrame",         "Blizzard_HousingBulletinBoard" },
	{ "HousingCornerstonePurchaseFrame",   "Blizzard_HousingCornerstone" },
	{ "HousingDashboardFrame",             "Blizzard_HousingDashboard" },
	{ "HousingHouseSettingsFrame",         "Blizzard_HousingHouseSettings" },
	{ "HousingModelPreviewFrame",          "Blizzard_HousingModelPreview" },
	{ "InspectFrame",                      "Blizzard_InspectUI" },
	{ "ItemInteractionFrame",              "Blizzard_ItemInteractionUI" },
	{ "ItemSocketingFrame",                "Blizzard_ItemSocketingUI" },
	{ "ItemUpgradeFrame",                  "Blizzard_ItemUpgradeUI" },
	{ "MacroFrame",                        "Blizzard_MacroUI" },
	{ "MajorFactionRenownFrame",           "Blizzard_MajorFactions" },
	{ "PlayerSpellsFrame",                 "Blizzard_PlayerSpells" },
	{ "ProfessionsBookFrame",              "Blizzard_ProfessionsBook" },
	{ "ProfessionsCustomerOrdersFrame",    "Blizzard_ProfessionsCustomerOrders" },
	{ "ProfessionsFrame",                  "Blizzard_Professions" },
	{ "ScrappingMachineFrame",             "Blizzard_ScrappingMachineUI" },
	{ "StableFrame",                       "Blizzard_StableUI" },
	{ "TransmogFrame",                     "Blizzard_Transmog" },
	{ "WardrobeFrame",                     "Blizzard_Collections" },
	{ "WeeklyRewardsFrame",                "Blizzard_WeeklyRewards" },
	{ "WorldMapFrame",                     "Blizzard_WorldMap" },
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

-- The snippet reads its inputs back out of the handler, so the four values are
-- staged as attributes first and the frame as a ref. Anchoring happens against
-- self:GetParent(), which is UIParent because that is what the handler is
-- parented to -- the snippet therefore needs no reference to UIParent itself.
local WIN_MOVE_SNIPPET = [[
	local target = self:GetFrameRef("target")
	if not target then return end
	target:ClearAllPoints()
	target:SetPoint(
		self:GetAttribute("anchor"),
		self:GetParent(),
		self:GetAttribute("relAnchor"),
		self:GetAttribute("offsetX"),
		self:GetAttribute("offsetY")
	)
]]

local function winSecureSetPoint(frame, point, relPoint, x, y)
	if InCombatLockdown() then return end
	if not securePositioner then
		securePositioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
	end
	local h = securePositioner
	h:SetFrameRef("target", frame)
	h:SetAttribute("anchor", point)
	h:SetAttribute("relAnchor", relPoint)
	h:SetAttribute("offsetX", x)
	h:SetAttribute("offsetY", y)
	h:Execute(WIN_MOVE_SNIPPET)
end

local function winSavePos(name, point, relPoint, x, y)
	wdb().positions[name] = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Saved window spots travel with an imported profile, and the defaults describe
-- no shape for them (positions starts empty), so Share's type guard cannot vet
-- these — check them here, right before they reach SetPoint. A malformed entry
-- would otherwise throw on every open of that window.
local function winPosValid(pos)
	return type(pos) == "table"
		and type(pos.point) == "string" and type(pos.relPoint) == "string"
		and type(pos.x) == "number" and type(pos.y) == "number"
end

local function winApplyPosition(frame, name)
	if not wdb().enabled then return end
	if InCombatLockdown() and frame:IsProtected() then return end
	local pos = wdb().positions[name]
	if not winPosValid(pos) then return end
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
	-- Invert the by-window list into the addon->windows map ADDON_LOADED needs.
	-- Already-loaded addons are hooked straight away; the rest wait for their event.
	for i = 1, #WIN_LOD do
		local frame, addon = WIN_LOD[i][1], WIN_LOD[i][2]
		if C_AddOns.IsAddOnLoaded(addon) then
			winTryHook(frame)
		else
			local pending = winPendingAddons[addon]
			if pending then
				pending[#pending + 1] = frame
			else
				winPendingAddons[addon] = { frame }
			end
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
--  Auto-accept invites — group invites from people you actually know (Battle.net
--  and character friends, guild members) go through without the popup; everything
--  else keeps Blizzard's dialog.
--  The guards matter more than the feature itself, so they are HARD rules rather
--  than options: accepting an invite while already grouped DROPS you from your
--  current group, and joining a group while you are inside an instance removes
--  you from that instance moments later. Same reasoning for invites that would
--  drop your LFG queues (Blizzard warns about that in its own dialog) and for
--  quest-session invites, which are a bigger commitment than a group. Whenever a
--  guard blocks, nothing is lost: the normal dialog appears as usual.
--  The relationship checks mirror Blizzard's SocialQueueUtil_GetRelationshipInfo.
-- ---------------------------------------------------------------------------
local function idb() return ns.Lumen.db.profile.qol.invites end

local function inviterIsKnown(guid)
	if not guid then return false end
	local i = idb()
	if i.friends then
		if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid) then
			return true
		end
		-- The classic (character) friend list can be switched off account-wide.
		if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsLegacyFriendSystemEnabled
			and C_FriendList.IsLegacyFriendSystemEnabled() and C_FriendList.IsFriend(guid) then
			return true
		end
	end
	if i.guild and IsGuildMember and IsGuildMember(guid) then return true end
	return false
end

-- Role-picker invites (LFGInvitePopup instead of the plain dialog): accept with
-- the role of the current spec -- but only if the inviter offered it AND the
-- game allows it for this character. No clean match = leave the dialog alone,
-- because then the role really is the player's decision.
local function autoRole(isTank, isHealer, isDamage)
	local spec = GetSpecialization and GetSpecialization()
	local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
	if not role then return nil end
	local canTank, canHeal, canDps
	if C_LFGList and C_LFGList.GetAvailableRoles then
		canTank, canHeal, canDps = C_LFGList.GetAvailableRoles()
	end
	if role == "TANK"    and isTank   and canTank then return true, false, false end
	if role == "HEALER"  and isHealer and canHeal then return false, true, false end
	if role == "DAMAGER" and isDamage and canDps  then return false, false, true end
	return nil
end

local function onPartyInvite(name, isTank, isHealer, isDamage, _, _, inviterGUID, questSessionActive)
	if not idb().enabled then return end
	if IsInGroup() then return end        -- accepting would drop your current group
	if IsInInstance() then return end     -- joining would remove you from the instance
	if questSessionActive then return end
	if WillAcceptInviteRemoveQueues and WillAcceptInviteRemoveQueues() then return end
	if not inviterIsKnown(inviterGUID) then return end

	if isTank or isHealer or isDamage then
		local t, h, d = autoRole(isTank, isHealer, isDamage)
		if t == nil then return end
		AcceptGroup(t, h, d)
	else
		AcceptGroup()
	end
	-- Blizzard's handler runs independently of ours and may raise the dialog
	-- AFTER we accepted -> clear it on the next frame, not right here.
	C_Timer.After(0, function()
		StaticPopup_Hide("PARTY_INVITE")
		if LFGInvitePopup and LFGInvitePopup:IsShown() then StaticPopupSpecial_Hide(LFGInvitePopup) end
	end)
	-- Always announce it: being pulled into a group without a click is
	-- confusing unless you can see why it happened.
	ns.Lumen:Print(ns.T("Invite from %s accepted automatically."):format(name or "?"))
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
	driver:RegisterEvent("PARTY_INVITE_REQUEST")
	-- Tracker visibility (brez pool / lust icon in group instances)
	driver:RegisterEvent("ENCOUNTER_START")
	driver:RegisterEvent("ENCOUNTER_END")
	driver:RegisterEvent("CHALLENGE_MODE_START")
	driver:RegisterEvent("CHALLENGE_MODE_COMPLETED")
	driver:RegisterEvent("CHALLENGE_MODE_RESET")
	driver:RegisterEvent("WORLD_STATE_TIMER_START")
	driver:RegisterEvent("WORLD_STATE_TIMER_STOP")
	driver:SetScript("OnEvent", function(_, event, ...)
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
		elseif event == "PARTY_INVITE_REQUEST" then
			onPartyInvite(...)
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
	self:ApplyMarkers()
	self:ApplyOutfitSuppress()
	self:ApplyTrackers()
	self:ApplyWindows()
end
