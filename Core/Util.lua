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

-- Whisper target for a stored "Name-Realm": a player on MY realm is addressed by the character name alone, because the
-- game's whisper lookup does not resolve this realm's own suffix on every client ("no player named 'Name-Realm' is
-- online"). Other realms keep "Name-Realm", which cross-realm whispers need.
function U.WhisperTarget(full)
    if type(full) ~= "string" then return full end
    if Ambiguate then   -- the game knows which realm is mine; "none" drops the suffix only for my own realm
        local ok, short = pcall(Ambiguate, full, "none")
        if ok and type(short) == "string" and short ~= "" then return short end
    end
    local name, realm = full:match("^([^-]+)-(.+)$")   -- offline fallback (tests)
    if not name then return full end
    local mine = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    mine = (mine:gsub("%s", ""))
    if mine ~= "" and (realm:gsub("%s", "")) == mine then return name end
    return full
end

U.ShortName = U.WhisperTarget   -- lists show the same form: "Name" on my realm, "Name-Realm" elsewhere

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

------------------------------------------------------------------ untrusted-input helpers (used by the sanitizers)

local INF = math.huge

-- a real, finite number (rejects NaN, +/-inf and non-numbers)
function U.IsFinite(v)
    return type(v) == "number" and v == v and v ~= INF and v ~= -INF
end

-- v when it is a finite integer within [lo, hi], else nil
function U.SafeInt(v, lo, hi)
    if not U.IsFinite(v) or v ~= math.floor(v) then return nil end
    if (lo and v < lo) or (hi and v > hi) then return nil end
    return v
end

-- remove control characters (incl. NUL and DEL); keeps everything else, including multi-byte UTF-8
function U.StripControl(s)
    return (s:gsub("[%z\1-\31\127]", ""))
end

-- s when it is a UTF-8 string of at most maxBytes without control characters; otherwise nil
function U.CleanString(s, maxBytes)
    if type(s) ~= "string" or #s > (maxBytes or 100) then return nil end
    if s:find("[%z\1-\31\127]") or not U.IsValidUtf8(s) then return nil end
    return s
end

-- player/character names: 1..64 bytes, UTF-8, no control characters and no "|" (escape-sequence introducer)
function U.IsSafeName(s)
    return U.CleanString(s, 64) ~= nil and s ~= "" and not s:find("|", 1, true)
end

-- Escape text that came from another player before it goes into a FontString: "|" starts colour/texture/hyperlink codes.
function U.Esc(s)
    if type(s) ~= "string" then s = tostring(s) end
    return (s:gsub("|", "||"))
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
    -- parts can contain peer text (names, message types); /ts debug prints them to the chat frame, so escape "|"
    for i = 1, select("#", ...) do parts[#parts + 1] = U.Esc(tostring((select(i, ...)))) end
    local log = ns.db.debug
    log[#log + 1] = U.Now() .. " " .. table.concat(parts, " ")
    while #log > 200 do table.remove(log, 1) end
end

function U.ReportError(err)
    if geterrorhandler then geterrorhandler()(err) else print(err) end
end
