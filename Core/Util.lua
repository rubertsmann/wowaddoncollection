local ADDON, ns = ...

local U = {}
ns.Util = U

-- "Bob" + "Area 52" -> "Bob-Area52"; names that already contain a realm are returned untouched.
function U.FullName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    realm = (realm:gsub("%s", ""))
    if realm == "" then return name end
    return name .. "-" .. realm
end

function U.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = U.DeepCopy(v) end
    return c
end

function U.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function U.Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

------------------------------------------------------------------ UTF-8 (WoW strings are UTF-8; Lua sees bytes)

-- Strict check: well-formed sequences only (no overlong forms, surrogates or code points above U+10FFFF).
function U.IsValidUtf8(s)
    if type(s) ~= "string" then return false end
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local len
        if c < 0x80 then len = 1
        elseif c >= 0xC2 and c <= 0xDF then len = 2
        elseif c >= 0xE0 and c <= 0xEF then len = 3
        elseif c >= 0xF0 and c <= 0xF4 then len = 4
        else return false end
        if i + len - 1 > n then return false end
        for j = i + 1, i + len - 1 do
            local b = s:byte(j)
            if b < 0x80 or b > 0xBF then return false end
        end
        if len >= 3 then
            local b2 = s:byte(i + 1)
            if c == 0xE0 and b2 < 0xA0 then return false end
            if c == 0xED and b2 > 0x9F then return false end
            if c == 0xF0 and b2 < 0x90 then return false end
            if c == 0xF4 and b2 > 0x8F then return false end
        end
        i = i + len
    end
    return true
end

-- Longest prefix of s that is at most maxBytes long and never ends inside a multi-byte character.
function U.TruncateUtf8(s, maxBytes)
    if #s <= maxBytes then return s end
    local cut = maxBytes
    while cut > 0 do
        local b = s:byte(cut + 1)
        if b and b >= 0x80 and b <= 0xBF then cut = cut - 1 else break end
    end
    return s:sub(1, cut)
end

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)   -- only used for 2-byte results
end

local ASCII_LOWER = {}
for c = 65, 90 do ASCII_LOWER[string.char(c)] = string.char(c + 32) end

-- lower-case of a two-byte (U+0080..U+07FF) character, as a code point
local function lowerCp(cp)
    if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then return cp + 0x20 end          -- Latin-1
    if cp >= 0x100 and cp <= 0x137 and cp % 2 == 0 then return cp + 1 end          -- Latin Extended-A
    if cp >= 0x139 and cp <= 0x148 and cp % 2 == 1 then return cp + 1 end
    if cp >= 0x14A and cp <= 0x177 and cp % 2 == 0 then return cp + 1 end
    if cp == 0x178 then return 0xFF end
    if cp >= 0x179 and cp <= 0x17E and cp % 2 == 1 then return cp + 1 end
    if cp >= 0x391 and cp <= 0x3A9 and cp ~= 0x3A2 then return cp + 0x20 end       -- Greek
    if cp >= 0x410 and cp <= 0x42F then return cp + 0x20 end                       -- Cyrillic
    if cp >= 0x400 and cp <= 0x40F then return cp + 0x50 end
    return cp
end

-- accent-free replacement for lower-case Latin-1 / Cyrillic letters
local BASE = {}
local function base(list, repl) for _, cp in ipairs(list) do BASE[cp] = repl end end
base({ 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0x101, 0x103, 0x105 }, "a")
base({ 0xE7, 0x107, 0x10D }, "c")
base({ 0xE8, 0xE9, 0xEA, 0xEB, 0x113, 0x119, 0x11B }, "e")
base({ 0xEC, 0xED, 0xEE, 0xEF }, "i")
base({ 0xF1, 0x144, 0x148 }, "n")
base({ 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF8, 0x151 }, "o")
base({ 0x161, 0x15B }, "s")
base({ 0xF9, 0xFA, 0xFB, 0xFC, 0x16F, 0x171 }, "u")
base({ 0xFD, 0xFF }, "y")
base({ 0x17A, 0x17C, 0x17E }, "z")
BASE[0xDF] = "ss"; BASE[0xE6] = "ae"; BASE[0x153] = "oe"
local CYR_E = 0x451   -- yo -> ie

-- Case-insensitive form (ASCII, Latin, Greek, Cyrillic). Deterministic: independent of the C locale.
function U.Fold(s)
    s = s:gsub("[A-Z]", ASCII_LOWER)
    return (s:gsub("([\195-\223])([\128-\191])", function(a, b)
        local cp = (a:byte() % 32) * 64 + b:byte() % 64
        local low = lowerCp(cp)
        return low == cp and (a .. b) or utf8char(low)
    end))
end

-- Search/sort key: case- and accent-insensitive. "Kürschnerei" and "KURSCHNEREI" give the same key.
function U.SearchKey(s)
    s = U.Fold(s)
    return (s:gsub("([\195-\223])([\128-\191])", function(a, b)
        local cp = (a:byte() % 32) * 64 + b:byte() % 64
        if cp == CYR_E then return utf8char(0x435) end
        return BASE[cp] or (a .. b)
    end))
end

-- Debug ring buffer persisted in SavedVariables (readable after /reload for offline verification).
ns.Debug = {}
function ns.Debug.Log(tag, ...)
    if not ns.db then return end
    local parts = { tostring(tag) }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local log = ns.db.debug
    log[#log + 1] = U.Now() .. " " .. table.concat(parts, " ")
    while #log > 200 do table.remove(log, 1) end
end

function U.ReportError(err)
    if geterrorhandler then geterrorhandler()(err) else print(err) end
end
