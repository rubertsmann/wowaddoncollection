local ADDON, ns = ...

-- Table <-> string for the addon channel: own safe serializer (no loadstring) + LibDeflate + addon-channel encoding.
local Codec = {}
ns.Codec = Codec

-- Transport limits, defined ONCE: Comm chunks with CHUNK and rejects more than MAX_PARTS; Decode accepts exactly what
-- the transport can deliver, so the two can never drift apart.
Codec.CHUNK = 225                                   -- payload bytes per addon message (header adds < 30; limit is 255)
Codec.MAX_PARTS = 200
Codec.MAX_ENCODED = Codec.CHUNK * Codec.MAX_PARTS

local MAX_RAW = 200000
local MAX_ENCODED = Codec.MAX_ENCODED
local MAX_DEPTH = 8
local MAX_TABLE_ITEMS = 20000

local function lib()
    return LibStub and LibStub:GetLibrary("LibDeflate", true)
end

local function ser(v, out, depth)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("bad number") end
        out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        if depth >= MAX_DEPTH then error("too deep") end
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "number" or kt == "string" then
                ser(k, out, depth + 1)
                ser(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    else
        error("unsupported type " .. t)
    end
end

local function parse(s, pos, depth)
    if depth > MAX_DEPTH then error("too deep") end
    local c = s:sub(pos, pos)
    if c == "n" then
        local e = s:find(";", pos, true)
        if not e then error("bad number") end
        local num = tonumber(s:sub(pos + 1, e - 1))
        -- tonumber("1e999") is +inf: peers must not be able to smuggle non-finite values past the serializer's own check
        if not num or num ~= num or num == math.huge or num == -math.huge then error("bad number") end
        return num, e + 1
    elseif c == "s" then
        local colon = s:find(":", pos, true)
        if not colon then error("bad string") end
        local len = tonumber(s:sub(pos + 1, colon - 1))
        if not len or len < 0 or len ~= math.floor(len) then error("bad string") end
        local str = s:sub(colon + 1, colon + len)
        if #str ~= len then error("short string") end
        return str, colon + len + 1
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "{" then
        local t, count = {}, 0
        pos = pos + 1
        while true do
            local ch = s:sub(pos, pos)
            if ch == "}" then return t, pos + 1 end
            if ch == "" then error("eof") end
            local k, v
            k, pos = parse(s, pos, depth + 1)
            if type(k) ~= "number" and type(k) ~= "string" then error("bad key") end
            v, pos = parse(s, pos, depth + 1)
            t[k] = v
            count = count + 1
            if count > MAX_TABLE_ITEMS then error("table too big") end
        end
    end
    error("bad token")
end

function Codec.Serialize(t)
    local out = {}
    ser(t, out, 0)
    return table.concat(out)
end

-- Never throws; returns nil, err on any malformed input.
function Codec.Deserialize(raw)
    if type(raw) ~= "string" or #raw == 0 or #raw > MAX_RAW then return nil, "bad input" end
    local ok, res, pos = pcall(parse, raw, 1, 0)
    if not ok then return nil, tostring(res) end
    if pos ~= #raw + 1 then return nil, "trailing data" end
    if type(res) ~= "table" then return nil, "not a table" end
    return res
end

function Codec.Encode(msg)
    msg.v = ns.PROTOCOL
    local L = lib()
    return L:EncodeForWoWAddonChannel(L:CompressDeflate(Codec.Serialize(msg)))
end

-- Returns msg table or nil, err. Rejects wrong protocol versions and messages without a string type.
function Codec.Decode(s)
    if type(s) ~= "string" or #s == 0 or #s > MAX_ENCODED then return nil, "bad input" end
    local L = lib()
    if not L then return nil, "no LibDeflate" end
    local ok, raw = pcall(function()
        local c = L:DecodeForWoWAddonChannel(s)
        return c and L:DecompressDeflate(c)
    end)
    if not ok or not raw then return nil, "inflate failed" end
    local msg, err = Codec.Deserialize(raw)
    if not msg then return nil, err end
    if msg.v ~= ns.PROTOCOL then return nil, "protocol version" end
    if type(msg.t) ~= "string" then return nil, "no type" end
    return msg
end

------------------------------------------------------------------ chunk header and version compatibility
-- Wire layout of one addon message (plain text, so ANY version can read the version before buffering or inflating):
--   <major>.<minor>|<id>|<idx>|<total>|<part>        e.g. "2.0|3fa2c|1|3|..."
-- Compatibility rule (docs/protocol.md): major must match exactly; a different minor is compatible (additive changes).
-- 0.1/0.2 builds used the legacy layout "<id>|<idx>|<total>|<part>" without a version.

function Codec.Header(id, idx, total)
    return ns.PROTO_MAJOR .. "." .. ns.PROTO_MINOR .. "|" .. id .. "|" .. idx .. "|" .. total .. "|"
end

-- Returns a table { major, minor [, id, idx, total, part] }, or nil, "legacy" | "malformed".
-- The layout after the version is only parsed when the major is ours: a foreign major may have changed it, and only the
-- version number is meaningful then.
function Codec.ParseHeader(text)
    if type(text) ~= "string" then return nil, "malformed" end
    local maj, min, rest = text:match("^(%d%d?%d?)%.(%d%d?%d?)|(.*)$")
    if not maj then
        if text:match("^%x+|%d+|%d+|") then return nil, "legacy" end
        return nil, "malformed"
    end
    local h = { major = tonumber(maj), minor = tonumber(min) }
    if h.major ~= ns.PROTO_MAJOR then return h end
    local id, idx, total, part = rest:match("^(%x+)|(%d+)|(%d+)|(.*)$")
    if not id or #id > 12 or #idx > 4 or #total > 4 then return nil, "malformed" end
    idx, total = tonumber(idx), tonumber(total)
    if total < 1 or total > Codec.MAX_PARTS or idx < 1 or idx > total then return nil, "malformed" end
    h.id, h.idx, h.total, h.part = id, idx, total, part
    return h
end

-- "ok" | "newer-minor" (compatible, peer has more features) | "newer" | "older" (both: cannot talk)
function Codec.Compat(major, minor)
    if major == ns.PROTO_MAJOR then
        return (minor > ns.PROTO_MINOR) and "newer-minor" or "ok"
    end
    return (major > ns.PROTO_MAJOR) and "newer" or "older"
end
