local ADDON, ns = ...

-- ===========================================================================
--  Lumen — Share (Export / Import)
--  Ein Textcode für das ganze Setup (Prinzip WeakAuras/ElvUI). Granular pro
--  Modul + getrennter Schalter für Layout-Positionen.
--
--  Pipeline:  AceSerializer  ->  LibDeflate (Deflate)  ->  EncodeForPrint
--
--  Wichtig (AceDB): unveränderte Werte liegen NICHT physisch im Profil, sondern
--  kommen lazy aus den Defaults-Metatables. Der Export ist daher bewusst „sparse"
--  (nur abweichende Werte). Der Import merged das Empfangene deshalb auf eine
--  frische Kopie der Lumen-Defaults — fehlende Felder werden so sauber gefüllt.
-- ===========================================================================

local Share = {}
ns.Share = Share

local AceSerializer = LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub("LibDeflate", true)

local FORMAT_VERSION = 1

-- Welche Module exportiert/importiert werden. label = Anzeige im Import-Dialog.
-- Neue Module hier eintragen (und ggf. unten in extractLayout berücksichtigen,
-- falls sie verschiebbare Positionen haben).
local MODULES = {
	{ key = "raidframes", label = "Raidframes" },
	{ key = "clickCast",  label = "Click-Cast" },
}

function Share:GetModules() return MODULES end

-- Positions-Felder, die als „Layout" getrennt behandelt werden (eigener
-- Import-Schalter). Bei den Raidframes liegen sie pro Kontext in raid/party.
local POS_FIELDS = { "point", "x", "y" }
local LAYOUT_CTX = { "raid", "party" }

-- ---- Hilfen ---------------------------------------------------------------

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deepcopy(v) end
	return r
end

-- src tief in dst mischen: Tabellen rekursiv, Skalare überschreiben.
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

-- private/transiente Felder (Migrations-Flags etc.) aus einer Kopie entfernen.
local function stripPrivate(t)
	if type(t) ~= "table" then return end
	for k in pairs(t) do
		if type(k) == "string" and k:sub(1, 1) == "_" then t[k] = nil end
	end
end

-- Positionen der Raidframes auslesen (über die Metatable, also immer vollständig).
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

-- Positions-Felder aus einer (sparse) Modul-Kopie entfernen — die Positionen
-- reisen getrennt im layout-Block.
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
	if not (AceSerializer and LibDeflate) then return nil, "Bibliotheken fehlen" end
	local serialized = AceSerializer:Serialize(payload)
	local compressed = LibDeflate:CompressDeflate(serialized)
	return LibDeflate:EncodeForPrint(compressed)
end

function Share:Decode(str)
	if not (AceSerializer and LibDeflate) then return nil, "Bibliotheken fehlen" end
	if type(str) ~= "string" then return nil, ns.T("empty") end
	str = str:gsub("%s+", "")           -- Zeilenumbrüche/Leerzeichen vom Kopieren entfernen
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
	if not p then return nil, "kein Profil" end

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

	return self:Encode(payload)
end

-- ---- Import ---------------------------------------------------------------

-- payload: dekodiert (Share:Decode). selected: { [modKey]=bool }. withLayout:
-- ob die Positionen des Absenders übernommen werden (sonst bleiben die eigenen).
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
			-- Frische Defaults als Basis, Empfangenes drübermischen -> fehlende Felder gefüllt.
			local merged = deepcopy(defs[key]) or {}
			deepmerge(merged, incoming)

			if key == "raidframes" then
				-- Positionen entscheiden: Absender (withLayout) ODER aktuelle behalten.
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

	if applied and L.RefreshAll then L:RefreshAll() end
	return applied
end
