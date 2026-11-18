-- LibGuildSync: table <-> string for the addon channel. Own safe serializer (no loadstring) + LibDeflate + addon-channel
-- encoding, and the plain-text chunk header that carries the protocol version. The serializer is shared; the protocol
-- version is per addon (Codec.New{ major, minor }), because every addon has its own prefix and wire protocol.
local lib = LibStub("LibGuildSync-1.0")
local Codec = lib:Module("Codec", 1)
if not Codec then return end

-- Transport limits, defined ONCE: Channel chunks with CHUNK_BYTES and rejects more than MAXIMUM_PARTS; Decode accepts
-- exactly what the transport can deliver, so the two can never drift apart.
---@type integer payload bytes per addon message (the header adds < 30; the client limit is 255)
Codec.CHUNK_BYTES = 225
---@type integer
Codec.MAXIMUM_PARTS = 200
---@type integer
Codec.MAXIMUM_ENCODED_BYTES = Codec.CHUNK_BYTES * Codec.MAXIMUM_PARTS

local MAXIMUM_SERIALIZED_BYTES = 200000
local MAXIMUM_ENCODED_BYTES = Codec.MAXIMUM_ENCODED_BYTES
local MAXIMUM_DEPTH = 8
local MAXIMUM_TABLE_ENTRIES = 20000

---@return table|nil LibDeflate
local function deflateLibrary()
    return LibStub and LibStub:GetLibrary("LibDeflate", true)
end

-- Serialized forms: n<number>;  s<length>:<bytes>  T  F  { key value key value ... }
---@param value any
---@param output string[]
---@param depth integer
local function serializeValue(value, output, depth)
    local valueType = type(value)
    if valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then error("bad number") end
        output[#output + 1] = "n" .. string.format("%.17g", value) .. ";"
    elseif valueType == "string" then
        output[#output + 1] = "s" .. #value .. ":" .. value
    elseif valueType == "boolean" then
        output[#output + 1] = value and "T" or "F"
    elseif valueType == "table" then
        if depth >= MAXIMUM_DEPTH then error("too deep") end
        output[#output + 1] = "{"
        for key, entry in pairs(value) do
            local keyType = type(key)
            if keyType == "number" or keyType == "string" then
                serializeValue(key, output, depth + 1)
                serializeValue(entry, output, depth + 1)
            end
        end
        output[#output + 1] = "}"
    else
        error("unsupported type " .. valueType)
    end
end

-- Parses one value at `position`; returns it and the position after it. Throws on malformed input (Deserialize catches).
---@param text string
---@param position integer
---@param depth integer
---@return any value
---@return integer nextPosition
local function parseValue(text, position, depth)
    if depth > MAXIMUM_DEPTH then error("too deep") end
    local token = text:sub(position, position)
    if token == "n" then
        local terminator = text:find(";", position, true)
        if not terminator then error("bad number") end
        local number = tonumber(text:sub(position + 1, terminator - 1))
        -- tonumber("1e999") is +inf: peers must not be able to smuggle non-finite values past the serializer's own check
        if not number or number ~= number or number == math.huge or number == -math.huge then error("bad number") end
        return number, terminator + 1
    elseif token == "s" then
        local colon = text:find(":", position, true)
        if not colon then error("bad string") end
        local length = tonumber(text:sub(position + 1, colon - 1))
        if not length or length < 0 or length ~= math.floor(length) then error("bad string") end
        local stringValue = text:sub(colon + 1, colon + length)
        if #stringValue ~= length then error("short string") end
        return stringValue, colon + length + 1
    elseif token == "T" then
        return true, position + 1
    elseif token == "F" then
        return false, position + 1
    elseif token == "{" then
        local tableValue, entryCount = {}, 0
        position = position + 1
        while true do
            local nextToken = text:sub(position, position)
            if nextToken == "}" then return tableValue, position + 1 end
            if nextToken == "" then error("eof") end
            local key, entry
            key, position = parseValue(text, position, depth + 1)
            if type(key) ~= "number" and type(key) ~= "string" then error("bad key") end
            entry, position = parseValue(text, position, depth + 1)
            tableValue[key] = entry
            entryCount = entryCount + 1
            if entryCount > MAXIMUM_TABLE_ENTRIES then error("table too big") end
        end
    end
    error("bad token")
end

---@param value table
---@return string
function Codec.Serialize(value)
    local output = {}
    serializeValue(value, output, 0)
    return table.concat(output)
end

-- Never throws; returns nil and the reason on any malformed input.
---@param serialized any
---@return table|nil
---@return string|nil reason
function Codec.Deserialize(serialized)
    if type(serialized) ~= "string" or #serialized == 0 or #serialized > MAXIMUM_SERIALIZED_BYTES then return nil, "bad input" end
    local ok, value, nextPosition = pcall(parseValue, serialized, 1, 0)
    if not ok then return nil, tostring(value) end
    if nextPosition ~= #serialized + 1 then return nil, "trailing data" end
    if type(value) ~= "table" then return nil, "not a table" end
    return value
end

------------------------------------------------------------------ chunk header and version compatibility
-- Wire layout of one addon message (plain text, so ANY version can read the version before buffering or inflating):
--   <major>.<minor>|<transfer id>|<part index>|<part count>|<payload>        e.g. "2.0|3fa2c|1|3|..."
-- Compatibility rule: major must match exactly; a different minor is compatible (additive changes).
-- The legacy layout "<id>|<index>|<count>|<payload>" (no version) is recognised so it can be reported.

---@class ChunkHeader
---@field major integer
---@field minor integer
---@field transferID? string hex id shared by all parts of one message (only when the major is ours)
---@field partIndex? integer 1-based
---@field partCount? integer
---@field payload? string

---@alias Compatibility "ok"|"newer-minor"|"newer"|"older"

---@class CodecProtocol
---@field major integer must match exactly between peers; the payload's `v` field carries it
---@field minor integer may differ (additive changes only)

-- Sets message.v and returns the channel-safe compressed text. Throws when the message cannot be serialized or
-- LibDeflate is missing (the caller logs it).
---@param protocol CodecProtocol
---@param message table
---@return string
function Codec.EncodeMessage(protocol, message)
    message.v = protocol.major
    local deflate = deflateLibrary()
    if not deflate then error("LibDeflate is not loaded") end
    return deflate:EncodeForWoWAddonChannel(deflate:CompressDeflate(Codec.Serialize(message)))
end

-- Returns the message table, or nil and the reason. Rejects wrong protocol versions and messages without a string type.
---@param protocol CodecProtocol
---@param encoded any
---@return table|nil message
---@return string|nil reason
function Codec.DecodeMessage(protocol, encoded)
    if type(encoded) ~= "string" or #encoded == 0 or #encoded > MAXIMUM_ENCODED_BYTES then return nil, "bad input" end
    local deflate = deflateLibrary()
    if not deflate then return nil, "no LibDeflate" end
    local ok, serialized = pcall(function()
        local compressed = deflate:DecodeForWoWAddonChannel(encoded)
        return compressed and deflate:DecompressDeflate(compressed)
    end)
    if not ok or not serialized then return nil, "inflate failed" end
    local message, reason = Codec.Deserialize(serialized)
    if not message then return nil, reason end
    if message.v ~= protocol.major then return nil, "protocol version" end
    if type(message.t) ~= "string" then return nil, "no type" end
    return message
end

---@param protocol CodecProtocol
---@param transferID string
---@param partIndex integer
---@param partCount integer
---@return string
function Codec.HeaderText(protocol, transferID, partIndex, partCount)
    return protocol.major .. "." .. protocol.minor .. "|" .. transferID .. "|" .. partIndex .. "|" .. partCount .. "|"
end

-- Returns the header, or nil and "legacy" | "malformed". The layout after the version is only parsed when the major is
-- ours: a foreign major may have changed it, and only the version number is meaningful then.
---@param protocol CodecProtocol
---@param text any
---@return ChunkHeader|nil
---@return "legacy"|"malformed"|nil reason
function Codec.ParseHeaderText(protocol, text)
    if type(text) ~= "string" then return nil, "malformed" end
    local majorText, minorText, rest = text:match("^(%d%d?%d?)%.(%d%d?%d?)|(.*)$")
    if not majorText then
        if text:match("^%x+|%d+|%d+|") then return nil, "legacy" end
        return nil, "malformed"
    end
    local header = { major = tonumber(majorText), minor = tonumber(minorText) }
    if header.major ~= protocol.major then return header end
    local transferID, partIndexText, partCountText, payload = rest:match("^(%x+)|(%d+)|(%d+)|(.*)$")
    if not transferID or #transferID > 12 or #partIndexText > 4 or #partCountText > 4 then return nil, "malformed" end
    local partIndex, partCount = tonumber(partIndexText), tonumber(partCountText)
    if partCount < 1 or partCount > Codec.MAXIMUM_PARTS or partIndex < 1 or partIndex > partCount then return nil, "malformed" end
    header.transferID, header.partIndex, header.partCount, header.payload = transferID, partIndex, partCount, payload
    return header
end

-- "ok" | "newer-minor" (compatible, peer has more features) | "newer" | "older" (both: cannot talk)
---@param protocol CodecProtocol
---@param major integer
---@param minor integer
---@return Compatibility
function Codec.CompatibilityOf(protocol, major, minor)
    if major == protocol.major then
        return (minor > protocol.minor) and "newer-minor" or "ok"
    end
    return (major > protocol.major) and "newer" or "older"
end

-- A codec for one addon's protocol; functions are called with a dot (codec.Encode(message)).
---@param protocol CodecProtocol
---@return table codec
function Codec.New(protocol)
    local instance = { protocol = protocol, CHUNK_BYTES = Codec.CHUNK_BYTES, MAXIMUM_PARTS = Codec.MAXIMUM_PARTS,
        MAXIMUM_ENCODED_BYTES = Codec.MAXIMUM_ENCODED_BYTES, Serialize = Codec.Serialize, Deserialize = Codec.Deserialize }
    function instance.Encode(message) return Codec.EncodeMessage(protocol, message) end
    function instance.Decode(encoded) return Codec.DecodeMessage(protocol, encoded) end
    function instance.Header(transferID, partIndex, partCount) return Codec.HeaderText(protocol, transferID, partIndex, partCount) end
    function instance.ParseHeader(text) return Codec.ParseHeaderText(protocol, text) end
    function instance.Compatibility(major, minor) return Codec.CompatibilityOf(protocol, major, minor) end
    return instance
end
