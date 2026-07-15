local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Share (export / import)
--  One text code for the whole setup (WeakAuras/ElvUI style). Granular per
--  module + a separate switch for layout positions.
--
--  Pipeline:  AceSerializer  ->  LibDeflate (Deflate)  ->  EncodeForPrint
--
--  Important (AceDB): unchanged values do NOT physically live in the profile,
--  they come lazily from the defaults metatables. The export is therefore
--  intentionally "sparse" (only differing values). On import the received data
--  is merged onto a fresh copy of the Lumen defaults — so missing fields are
--  filled cleanly.
-- ===========================================================================

local Share = {}
ns.Share = Share

local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub("LibDeflate", true)

local FORMAT_VERSION = 1

-- Which modules are exported/imported. label = display in the import dialog.
-- Add new modules here (and consider them below in extractLayout if they have
-- movable positions).
local MODULES = {
	{ key = "raidframes", label = "Raidframes" },
	{ key = "clickCast",  label = "Click-Cast" },
	{ key = "qol",        label = "QoL" },   -- no movable positions yet (cursor ring follows the mouse)
	{ key = "uiScale",    label = "UI scale" }, -- game UI scale (pixel perfect / manual)
}

function Share:GetModules() return MODULES end

-- Position fields treated separately as "layout" (own import switch). For the
-- raid frames they live per context in raid/party.
local POS_FIELDS = { "point", "x", "y" }
local LAYOUT_CTX = { "raid", "party" }

-- ---- Helpers --------------------------------------------------------------

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deepcopy(v) end
	return r
end

-- Deep-merge src into dst: tables recursively, scalars overwrite.
local function deepmerge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			deepmerge(dst[k], v)
		else
			dst[k] = deepcopy(v)
		end
	end
	return dst
end

-- Remove private/transient fields (migration flags etc.) from a copy.
local function stripPrivate(t)
	if type(t) ~= "table" then return end
	for k in pairs(t) do
		if type(k) == "string" and k:sub(1, 1) == "_" then t[k] = nil end
	end
end

-- Read raid frame positions (via the metatable, so always complete).
local function extractLayout(rf)
	if type(rf) ~= "table" then return nil end
	local lay = {}
	for _, ctx in ipairs(LAYOUT_CTX) do
		local c = rf[ctx]
		if c then
			lay[ctx] = {}
			for _, f in ipairs(POS_FIELDS) do lay[ctx][f] = c[f] end
		end
	end
	return lay
end

-- Remove position fields from a (sparse) module copy — positions travel
-- separately in the layout block.
local function stripLayout(rfCopy)
	for _, ctx in ipairs(LAYOUT_CTX) do
		local c = rfCopy[ctx]
		if type(c) == "table" then
			for _, f in ipairs(POS_FIELDS) do c[f] = nil end
		end
	end
end

-- ---- Codec ----------------------------------------------------------------

function Share:Encode(payload)
	if not (AceSerializer and LibDeflate) then return nil, "libraries missing" end
	local serialized = AceSerializer:Serialize(payload)
	local compressed = LibDeflate:CompressDeflate(serialized)
	return LibDeflate:EncodeForPrint(compressed)
end

function Share:Decode(str)
	if not (AceSerializer and LibDeflate) then return nil, "libraries missing" end
	if type(str) ~= "string" then return nil, ns.T("empty") end
	str = str:gsub("%s+", "")           -- strip line breaks/spaces from copying
	if str == "" then return nil, ns.T("empty") end
	local decoded = LibDeflate:DecodeForPrint(str)
	if not decoded then return nil, ns.T("invalid code") end
	local decompressed = LibDeflate:DecompressDeflate(decoded)
	if not decompressed then return nil, ns.T("decompression failed") end
	local ok, payload = AceSerializer:Deserialize(decompressed)
	if not ok or type(payload) ~= "table" then return nil, ns.T("corrupt code") end
	if payload.addon ~= "Lumen" then return nil, ns.T("not a Lumen code") end
	if type(payload.modules) ~= "table" then return nil, ns.T("no module data") end
	return payload
end

-- ---- Export ---------------------------------------------------------------

function Share:Export()
	local p = ns.Lumen and ns.Lumen.db and ns.Lumen.db.profile
	if not p then return nil, "no profile" end

	local payload = { v = FORMAT_VERSION, addon = "Lumen", modules = {}, layout = {} }

	for _, m in ipairs(MODULES) do
		local key = m.key
		if p[key] then
			local copy = deepcopy(p[key])
			stripPrivate(copy)
			if key == "raidframes" then
				payload.layout.raidframes = extractLayout(p.raidframes)
				stripLayout(copy)
			end
			payload.modules[key] = copy
		end
	end

	-- Edit Mode links belong to the layout (positions) -> travel with the
	-- "import layout positions" switch, not with any single module.
	if p.editLinks and next(p.editLinks) then
		payload.layout.editLinks = deepcopy(p.editLinks)
	end

	return self:Encode(payload)
end

-- ---- Import ---------------------------------------------------------------

-- payload: decoded (Share:Decode). selected: { [modKey]=bool }. withLayout:
-- whether the sender's positions are applied (otherwise yours stay).
function Share:Import(payload, selected, withLayout)
	local L = ns.Lumen
	local p = L and L.db and L.db.profile
	if not (p and payload and payload.modules) then return false end

	local defs = ns.Defaults and ns.Defaults.profile or {}
	local applied = false

	for _, m in ipairs(MODULES) do
		local key = m.key
		local incoming = payload.modules[key]
		if incoming and selected[key] then
			-- Fresh defaults as base, received data merged on top -> missing fields filled.
			local merged = deepcopy(defs[key]) or {}
			deepmerge(merged, incoming)

			if key == "raidframes" then
				-- Decide positions: sender (withLayout) OR keep current.
				local keepPos = extractLayout(p.raidframes)
				local fromCode = payload.layout and payload.layout.raidframes
				for _, ctx in ipairs(LAYOUT_CTX) do
					merged[ctx] = merged[ctx] or {}
					local src = (withLayout and fromCode and fromCode[ctx]) or (keepPos and keepPos[ctx])
					if src then
						for _, f in ipairs(POS_FIELDS) do merged[ctx][f] = src[f] end
					end
				end
			end

			p[key] = merged
			applied = true
		end
	end

	-- Edit Mode links ride the layout switch (they ARE positions). Only replace
	-- when the sender's layout is taken; otherwise keep the receiver's own links.
	if withLayout and payload.layout and payload.layout.editLinks then
		p.editLinks = deepcopy(payload.layout.editLinks)
		applied = true
	end

	if applied and L.RefreshAll then L:RefreshAll() end
	return applied
end
