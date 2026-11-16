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

------------------------------------------------------------------ canonical player names (feature 008, analysis R1)
-- A player name reaches the addon from three client sources that need not agree on the realm spelling: my own name
-- (UnitName + GetNormalizedRealmName), the CHAT_MSG_ADDON sender, and GetGuildRosterInfo. Every comparison and every
-- stored key uses U.Canon, so one character has ONE key: realm spellings that mean MY realm (any case, spaces,
-- apostrophes or hyphens; plus aliases learned from the roster's spelling of my own character) become my normalized realm.
-- Other realms keep their own suffix (spaces removed), so cross-realm characters stay distinct.

local myRealmAliases = {}   -- folded realm spellings known to mean my realm (besides the normalized realm itself)
U.realmAliasVersion = 0     -- bumped when an alias is learned: stored keys must then be canonicalized again

local function foldRealm(r)
    return (r:gsub("[%s'%-]", ""):gsub("[A-Z]", function(c) return c:lower() end))
end
U.FoldRealm = foldRealm

-- my realm in the form FullName appends ("" while the client does not know it yet)
function U.MyRealm()
    local mine = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    return (mine:gsub("%s", ""))
end

------------------------------------------------------------------ realm-free identity (WoW Forever; verified 2026-11-16)
-- One Forever guild spans several realms ("CAMWOW EU4 Realm 1/3/5 PvE", "CAMWOW EU5 Realm 3 PvE" in one guild), yet the
-- roster and every chat sender give names WITHOUT a realm ("Drakk Nuk"), and whispers to the bare name arrive. Each
-- client appended its OWN realm to those bare names, so the same member was "Drakk Nuk-...Realm5" on one client and
-- "Drakk Nuk-...Realm3" on the next: requests never matched and records were refused. Where the realm is not part of a
-- name (surnames, or a roster without realm suffixes), every realm counts as mine: one member, one key on every client.
local myBase              -- my "First Surname" (nil on clients without surnames); see the surname section below
local rosterBare = false  -- the guild roster spells every member without a realm suffix

function U.RealmFree()
    return myBase ~= nil or rosterBare
end

-- true when `realm` is a spelling of MY realm (the normalized realm, GetRealmName, or a learned alias)
function U.IsRealmSpelling(realm)
    if type(realm) ~= "string" or realm == "" then return false end
    local f = foldRealm(realm)
    if myRealmAliases[f] then return true end
    local mine = U.MyRealm()
    if mine ~= "" and foldRealm(mine) == f then return true end
    if GetRealmName then
        local ok, r = pcall(GetRealmName)
        if ok and type(r) == "string" and r ~= "" and foldRealm(r) == f then return true end
    end
    return false
end

function U.IsMyRealm(realm)
    if type(realm) ~= "string" or realm == "" then return true end
    return U.RealmFree() or U.IsRealmSpelling(realm)
end

-- Records another spelling of my realm (from the roster's entry for my own character). True when it was new.
function U.LearnMyRealm(realm)
    if type(realm) ~= "string" or realm == "" then return false end
    local f = foldRealm(realm)
    if f == "" or U.IsMyRealm(realm) then return false end
    myRealmAliases[f] = true
    U.realmAliasVersion = U.realmAliasVersion + 1
    return true
end

-- The roster lists my own character in the server's spelling: when exactly one roster name has my character name, its
-- realm suffix is my realm. Returns true when a new spelling was learned.
function U.LearnFromRoster(rawNames, myCharName)
    if type(myCharName) ~= "string" or myCharName == "" or type(rawNames) ~= "table" then return false end
    local found
    for _, full in ipairs(rawNames) do
        local name, realm = full:match("^([^-]+)-(.*)$")
        if (name or full) == myCharName then
            if found then return false end   -- ambiguous (same name on two realms): learn nothing
            found = realm or ""
        end
    end
    return found ~= nil and U.LearnMyRealm(found)
end

function U.RealmAliases()   -- for the diagnostic report
    local out = {}
    for f in pairs(myRealmAliases) do out[#out + 1] = f end
    table.sort(out)
    return out
end

function U.ResetRealmAliases()   -- tests
    myRealmAliases, myBase, firstIndex, firstSig, rosterBare = {}, nil, {}, "", false
    U.realmAliasVersion = U.realmAliasVersion + 1
end

-- The one key of a player: "Name-MyRealm" for my realm in any spelling, "Name-OtherRealm" otherwise. A bare "Name" gets
-- my realm (bare names are what same-realm sources give). nil for non-strings and empty names.
------------------------------------------------------------------ surnames (WoW Forever; verified from a user export 2026-11-16)
-- On Forever a character has a first name AND a surname. UnitName("player") returns ("Drakk", "Nuk") (the surname in the
-- slot retail uses for the realm), while the guild roster and every chat sender use "Drakk Nuk" (space, no realm). The
-- character's identity is the full "First Surname". Data written by 0.4.0 and by the first 0.4.1 builds keyed players by
-- the first name only ("Drakk-Realm"); a first name that is unique in the guild roster is mapped to that member's full name.
local firstIndex = {}     -- first name -> "First Surname" from the roster (false when two members share the first name)
local firstSig = ""

local function firstToken(n) return (n:match("^(%S+)")) end

function U.NoteMyFullName(base)
    if type(base) ~= "string" or not base:find(" ", 1, true) or base == myBase then return false end
    myBase = base
    U.realmAliasVersion = U.realmAliasVersion + 1
    return true
end

-- rawNames: the roster as GetGuildRosterInfo spells it. Returns true when the first-name index changed.
function U.SetRosterNames(rawNames)
    local idx, bare, n = {}, true, 0
    for _, raw in ipairs(rawNames or {}) do
        if type(raw) == "string" then
            n = n + 1
            if raw:find("-", 1, true) then bare = false end
        end
    end
    bare = bare and n > 0
    if bare ~= rosterBare then
        rosterBare = bare
        U.realmAliasVersion = U.realmAliasVersion + 1
    end
    for _, raw in ipairs(rawNames or {}) do
        if type(raw) == "string" then
            local base, realm = raw:match("^([^-]+)-(.*)$")
            base = base or raw
            if base:find(" ", 1, true) and (realm == nil or U.IsMyRealm(realm)) then
                local ft = firstToken(base)
                if ft then
                    if idx[ft] == nil then idx[ft] = base elseif idx[ft] ~= base then idx[ft] = false end
                end
            end
        end
    end
    local keys = {}
    for k, v in pairs(idx) do keys[#keys + 1] = k .. "=" .. tostring(v) end
    table.sort(keys)
    local sig = table.concat(keys, "|")
    if sig == firstSig then return false end
    firstIndex, firstSig = idx, sig
    U.realmAliasVersion = U.realmAliasVersion + 1
    return true
end

function U.MyFullName() return myBase end

-- The name a 0.4.0 client uses for ITSELF: first name only ("Mira Holt-Realm" -> "Mira-Realm"). Sent next to the full
-- name in WANT/WANTO so a not-yet-updated member still recognises the request. nil when there is no surname, or when two
-- roster members share the first name (both would answer, and neither record could be told apart).
function U.LegacyName(canon)
    if type(canon) ~= "string" then return nil end
    local base, realm = canon:match("^([^-]+)-(.*)$")
    base = base or canon
    local first = firstToken(base)
    if not first or first == base or firstIndex[first] == false then return nil end
    return realm and (first .. "-" .. realm) or first
end

function U.Canon(full)
    if type(full) ~= "string" or full == "" then return nil end
    local name, realm = full:match("^([^-]+)-(.*)$")
    if not name then name, realm = full, "" end
    if name == "" then return nil end
    if U.IsMyRealm(realm) then
        if not name:find(" ", 1, true) then   -- a bare first name: complete it with the surname when that is unambiguous
            local full2 = (myBase and firstToken(myBase) == name and myBase) or firstIndex[name]
            if type(full2) == "string" then name = full2 end
        end
        local mine = U.MyRealm()
        if mine == "" then return realm ~= "" and (name .. "-" .. realm:gsub("%s", "")) or name end
        return name .. "-" .. mine
    end
    return name .. "-" .. realm:gsub("%s", "")
end

-- Whisper target for a stored "Name-Realm": a player on MY realm is addressed by the character name alone, because the
-- game's whisper lookup does not resolve this realm's own suffix on every client ("no player named 'Name-Realm' is
-- online"). Other realms keep "Name-Realm", which cross-realm whispers need.
-- The own-realm comparison decides first (U.IsMyRealm: every known spelling of my realm). Ambiguate only decides the rest
-- (connected realms); it is not trusted for my own realm because a client whose Ambiguate does not know the normalized
-- realm returns "Name-Realm" unchanged, and every addon whisper then goes to a player that "is not online".
function U.WhisperTarget(full)
    if type(full) ~= "string" then return full end
    local name, realm = full:match("^([^-]+)-(.+)$")
    if not name then return full end
    if U.MyRealm() ~= "" and U.IsMyRealm(realm) then return name end
    if Ambiguate then   -- the game knows which realms are connected to mine; "none" drops the suffix only for those
        local ok, short = pcall(Ambiguate, full, "none")
        if ok and type(short) == "string" and short ~= "" then return short end
    end
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
