local ADDON, ns = ...

-- Table <-> string for the addon channel: own safe serializer (no loadstring) + LibDeflate + addon-channel encoding.
local Codec = {}
ns.Codec = Codec

local MAX_RAW = 200000
local MAX_ENCODED = 60000
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
        if not num then error("bad number") end
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
