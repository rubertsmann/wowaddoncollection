-- LibGuildSync: shared helpers. Player names and realms, tables, untrusted input, UTF-8 text. Pure Lua except for a few
-- guarded client lookups (GetNormalizedRealmName, GetRealmName, Ambiguate), so the offline tests run all of it.
-- ONE state for every addon that embeds the library: the realm spellings and surnames learned here belong to the player,
-- not to an addon. Addon-specific identity (who "me" is in that addon's saved data) stays in the addon.
local lib = LibStub("LibGuildSync-1.0")
local Utility = lib:Module("Utility", 1)
if not Utility then return end

---@class UtilityNameState
---@field aliases table<string, boolean> folded realm spellings known to mean my realm (besides the normalized realm itself)
---@field fullCharacterName string|nil my "First Surname" (nil on clients without surnames)
---@field rosterWithoutRealms boolean the guild roster spells every member without a realm suffix
---@field fullNameByFirstName table<string, string|false> first name -> "First Surname" from the roster (false when shared)
---@field signature string signature of fullNameByFirstName, to tell whether a roster update changed it
---@type UtilityNameState
Utility.names = Utility.names or { aliases = {}, fullCharacterName = nil, rosterWithoutRealms = false, fullNameByFirstName = {},
    signature = "" }
local nameState = Utility.names

-- "Bob" + "Area 52" -> "Bob-Area52"; names that already contain a realm are returned untouched.
---@param characterName string|nil
---@param realmName? string defaults to my normalized realm
---@return string|nil
function Utility.FullName(characterName, realmName)
    if type(characterName) ~= "string" or characterName == "" then return nil end
    if characterName:find("-", 1, true) then return characterName end
    realmName = realmName or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    realmName = (realmName:gsub("%s", ""))
    if realmName == "" then return characterName end
    return characterName .. "-" .. realmName
end

------------------------------------------------------------------ canonical player names (feature 008, analysis R1)
-- A player name reaches the addon from three client sources that need not agree on the realm spelling: my own name
-- (UnitName + GetNormalizedRealmName), the CHAT_MSG_ADDON sender, and GetGuildRosterInfo. Every comparison and every
-- stored key uses Utility.CanonicalName, so one character has ONE key: realm spellings that mean MY realm (any case,
-- spaces, apostrophes or hyphens; plus aliases learned from the roster's spelling of my own character) become my
-- normalized realm. Other realms keep their own suffix (spaces removed), so cross-realm characters stay distinct.

---@type integer bumped when an alias is learned: stored keys must then be canonicalized again
Utility.realmAliasVersion = Utility.realmAliasVersion or 0

------------------------------------------------------------------ realm-free identity (WoW Forever; verified 2026-11-16)
-- One Forever guild spans several realms ("CAMWOW EU4 Realm 1/3/5 PvE", "CAMWOW EU5 Realm 3 PvE" in one guild), yet the
-- roster and every chat sender give names WITHOUT a realm ("Drakk Nuk"), and whispers to the bare name arrive. Each
-- client appended its OWN realm to those bare names, so the same member was "Drakk Nuk-...Realm5" on one client and
-- "Drakk Nuk-...Realm3" on the next: requests never matched and records were refused. Where the realm is not part of a
-- name (surnames, or a roster without realm suffixes), every realm counts as mine: one member, one key on every client.

------------------------------------------------------------------ surnames (WoW Forever; verified from a user export 2026-11-16)
-- On Forever a character has a first name AND a surname. UnitName("player") returns ("Drakk", "Nuk") (the surname in the
-- slot retail uses for the realm), while the guild roster and every chat sender use "Drakk Nuk" (space, no realm). The
-- character's identity is the full "First Surname". Data written by 0.4.0 and by the first 0.4.1 builds keyed players by
-- the first name only ("Drakk-Realm"); a first name that is unique in the guild roster is mapped to that member's full name.

-- "Drakk-Realm" -> "drakkrealm": the realm spelling with case, spaces, apostrophes and hyphens removed.
---@param realmName string
---@return string
local function foldRealm(realmName)
    return (realmName:gsub("[%s'%-]", ""):gsub("[A-Z]", function(letter) return letter:lower() end))
end
Utility.FoldRealm = foldRealm

-- my realm in the form FullName appends ("" while the client does not know it yet)
---@return string
function Utility.MyRealm()
    local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    return (myRealm:gsub("%s", ""))
end

---@return boolean
function Utility.RealmFree()
    return nameState.fullCharacterName ~= nil or nameState.rosterWithoutRealms
end

-- true when `realmName` is a spelling of MY realm (the normalized realm, GetRealmName, or a learned alias)
---@param realmName string|nil
---@return boolean
function Utility.IsRealmSpelling(realmName)
    if type(realmName) ~= "string" or realmName == "" then return false end
    local folded = foldRealm(realmName)
    if nameState.aliases[folded] then return true end
    local myRealm = Utility.MyRealm()
    if myRealm ~= "" and foldRealm(myRealm) == folded then return true end
    if GetRealmName then
        local ok, clientRealm = pcall(GetRealmName)
        if ok and type(clientRealm) == "string" and clientRealm ~= "" and foldRealm(clientRealm) == folded then return true end
    end
    return false
end

---@param realmName string|nil
---@return boolean
function Utility.IsMyRealm(realmName)
    if type(realmName) ~= "string" or realmName == "" then return true end
    return Utility.RealmFree() or Utility.IsRealmSpelling(realmName)
end

-- Records another spelling of my realm (from the roster's entry for my own character). True when it was new.
---@param realmName string|nil
---@return boolean
function Utility.LearnMyRealm(realmName)
    if type(realmName) ~= "string" or realmName == "" then return false end
    local folded = foldRealm(realmName)
    if folded == "" or Utility.IsMyRealm(realmName) then return false end
    nameState.aliases[folded] = true
    Utility.realmAliasVersion = Utility.realmAliasVersion + 1
    return true
end

-- The roster lists my own character in the server's spelling: when exactly one roster name has my character name, its
-- realm suffix is my realm. Returns true when a new spelling was learned.
---@param rosterNames string[] the roster as GetGuildRosterInfo spells it
---@param myCharacterName string
---@return boolean
function Utility.LearnFromRoster(rosterNames, myCharacterName)
    if type(myCharacterName) ~= "string" or myCharacterName == "" or type(rosterNames) ~= "table" then return false end
    local foundRealm
    for _, rosterName in ipairs(rosterNames) do
        local characterName, realmName = rosterName:match("^([^-]+)-(.*)$")
        if (characterName or rosterName) == myCharacterName then
            if foundRealm then return false end   -- ambiguous (same name on two realms): learn nothing
            foundRealm = realmName or ""
        end
    end
    return foundRealm ~= nil and Utility.LearnMyRealm(foundRealm)
end

-- for the diagnostic report
---@return string[]
function Utility.RealmAliases()
    return Utility.SortedKeys(nameState.aliases)
end

-- tests: forget everything learned about realms and surnames
function Utility.ResetRealmAliases()
    nameState.aliases, nameState.fullCharacterName, nameState.rosterWithoutRealms = {}, nil, false
    nameState.fullNameByFirstName, nameState.signature = {}, ""
    Utility.realmAliasVersion = Utility.realmAliasVersion + 1
end

---@param characterName string
---@return string|nil
local function firstWord(characterName) return (characterName:match("^(%S+)")) end

-- My "First Surname" (Forever). True when it changed.
---@param fullCharacterName string|nil
---@return boolean
function Utility.NoteMyFullName(fullCharacterName)
    if type(fullCharacterName) ~= "string" or not fullCharacterName:find(" ", 1, true)
        or fullCharacterName == nameState.fullCharacterName then return false end
    nameState.fullCharacterName = fullCharacterName
    Utility.realmAliasVersion = Utility.realmAliasVersion + 1
    return true
end

-- Returns true when the first-name index changed.
---@param rosterNames string[]|nil the roster as GetGuildRosterInfo spells it
---@return boolean
function Utility.SetRosterNames(rosterNames)
    local fullNameIndex, everyNameWithoutRealm, nameCount = {}, true, 0
    for _, rosterName in ipairs(rosterNames or {}) do
        if type(rosterName) == "string" then
            nameCount = nameCount + 1
            if rosterName:find("-", 1, true) then everyNameWithoutRealm = false end
        end
    end
    everyNameWithoutRealm = everyNameWithoutRealm and nameCount > 0
    if everyNameWithoutRealm ~= nameState.rosterWithoutRealms then
        nameState.rosterWithoutRealms = everyNameWithoutRealm
        Utility.realmAliasVersion = Utility.realmAliasVersion + 1
    end
    for _, rosterName in ipairs(rosterNames or {}) do
        if type(rosterName) == "string" then
            local characterName, realmName = rosterName:match("^([^-]+)-(.*)$")
            characterName = characterName or rosterName
            if characterName:find(" ", 1, true) and (realmName == nil or Utility.IsMyRealm(realmName)) then
                local firstName = firstWord(characterName)
                if firstName then
                    if fullNameIndex[firstName] == nil then
                        fullNameIndex[firstName] = characterName
                    elseif fullNameIndex[firstName] ~= characterName then
                        fullNameIndex[firstName] = false
                    end
                end
            end
        end
    end
    local signatureParts = {}
    for firstName, fullName in pairs(fullNameIndex) do signatureParts[#signatureParts + 1] = firstName .. "=" .. tostring(fullName) end
    table.sort(signatureParts)
    local signature = table.concat(signatureParts, "|")
    if signature == nameState.signature then return false end
    nameState.fullNameByFirstName, nameState.signature = fullNameIndex, signature
    Utility.realmAliasVersion = Utility.realmAliasVersion + 1
    return true
end

---@return string|nil
function Utility.MyFullName() return nameState.fullCharacterName end

-- The name a 0.4.0 client uses for ITSELF: first name only ("Mira Holt-Realm" -> "Mira-Realm"). Sent next to the full
-- name in WANT/WANTO so a not-yet-updated member still recognises the request. nil when there is no surname, or when two
-- roster members share the first name (both would answer, and neither record could be told apart).
---@param playerName string|nil a canonical "Name-Realm"
---@return string|nil
function Utility.LegacyName(playerName)
    if type(playerName) ~= "string" then return nil end
    local characterName, realmName = playerName:match("^([^-]+)-(.*)$")
    characterName = characterName or playerName
    local firstName = firstWord(characterName)
    if not firstName or firstName == characterName or nameState.fullNameByFirstName[firstName] == false then return nil end
    return realmName and (firstName .. "-" .. realmName) or firstName
end

-- The one key of a player: "Name-MyRealm" for my realm in any spelling, "Name-OtherRealm" otherwise. A bare "Name" gets
-- my realm (bare names are what same-realm sources give). nil for non-strings and empty names.
---@param playerName string|nil
---@return string|nil
function Utility.CanonicalName(playerName)
    if type(playerName) ~= "string" or playerName == "" then return nil end
    local characterName, realmName = playerName:match("^([^-]+)-(.*)$")
    if not characterName then characterName, realmName = playerName, "" end
    if characterName == "" then return nil end
    if Utility.IsMyRealm(realmName) then
        if not characterName:find(" ", 1, true) then   -- a bare first name: complete it with the surname when that is unambiguous
            local completedName = (nameState.fullCharacterName and firstWord(nameState.fullCharacterName) == characterName and nameState.fullCharacterName)
                or nameState.fullNameByFirstName[characterName]
            if type(completedName) == "string" then characterName = completedName end
        end
        local myRealm = Utility.MyRealm()
        if myRealm == "" then return realmName ~= "" and (characterName .. "-" .. realmName:gsub("%s", "")) or characterName end
        return characterName .. "-" .. myRealm
    end
    return characterName .. "-" .. realmName:gsub("%s", "")
end

-- Whisper target for a stored "Name-Realm": a player on MY realm is addressed by the character name alone, because the
-- game's whisper lookup does not resolve this realm's own suffix on every client ("no player named 'Name-Realm' is
-- online"). Other realms keep "Name-Realm", which cross-realm whispers need.
-- The own-realm comparison decides first (Utility.IsMyRealm: every known spelling of my realm). Ambiguate only decides
-- the rest (connected realms); it is not trusted for my own realm because a client whose Ambiguate does not know the
-- normalized realm returns "Name-Realm" unchanged, and every addon whisper then goes to a player that "is not online".
---@param playerName string|nil
---@return string|nil
function Utility.WhisperTarget(playerName)
    if type(playerName) ~= "string" then return playerName end
    local characterName, realmName = playerName:match("^([^-]+)-(.+)$")
    if not characterName then return playerName end
    if Utility.MyRealm() ~= "" and Utility.IsMyRealm(realmName) then return characterName end
    if Ambiguate then   -- the game knows which realms are connected to mine; "none" drops the suffix only for those
        local ok, shortName = pcall(Ambiguate, playerName, "none")
        if ok and type(shortName) == "string" and shortName ~= "" then return shortName end
    end
    return playerName
end

-- lists show the same form: "Name" on my realm, "Name-Realm" elsewhere
Utility.ShortName = Utility.WhisperTarget

------------------------------------------------------------------ table helpers (the ONE copy of each; see feature 012)

---@generic T
---@param value T
---@return T
function Utility.DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = Utility.DeepCopy(entry) end
    return copy
end

-- number of keys; anything that is not a table counts as empty
---@param map any
---@return integer
function Utility.Count(map)
    local count = 0
    if type(map) == "table" then for _ in pairs(map) do count = count + 1 end end
    return count
end

-- keys of `map` in a stable order: numbers before strings, each in natural order (1 < 2 < 10, "a" < "b"); any other key
-- type after those, by tostring. Never errors on mixed key types. Not a table -> {}.
---@type table<string, integer>
local KEY_TYPE_RANK = { number = 1, string = 2 }
---@param left any
---@param right any
---@return boolean
local function keyComesFirst(left, right)
    local leftType, rightType = type(left), type(right)
    if leftType == rightType and KEY_TYPE_RANK[leftType] then return left < right end
    local leftRank, rightRank = KEY_TYPE_RANK[leftType] or 3, KEY_TYPE_RANK[rightType] or 3
    if leftRank ~= rightRank then return leftRank < rightRank end
    return tostring(left) < tostring(right)
end
---@param map any
---@return any[]
function Utility.SortedKeys(map)
    local keys = {}
    if type(map) == "table" then for key in pairs(map) do keys[#keys + 1] = key end end
    table.sort(keys, keyComesFirst)
    return keys
end

-- empties `map` IN PLACE (other modules may hold a reference to it) and returns it
---@generic T: table
---@param map T
---@return T
function Utility.Wipe(map)
    for key in pairs(map) do map[key] = nil end
    return map
end

-- replaces the contents of `map` with those of `source`, IN PLACE (keeps references valid)
---@generic T: table
---@param map T
---@param source table
---@return T
function Utility.Refill(map, source)
    Utility.Wipe(map)
    for key, value in pairs(source) do map[key] = value end
    return map
end

-- Re-validates a persisted map: keeps map[key] = clean for every entry where pcall(sanitize, value) returns clean and
-- keyIsValid(key, clean) is true; drops the rest. Not a table -> empty map. Returns the new map and the number dropped.
---@param map any
---@param sanitize fun(value: any): any
---@param keyIsValid fun(key: any, clean: any): boolean
---@return table cleanMap
---@return integer droppedCount
function Utility.SanitizeMap(map, sanitize, keyIsValid)
    local cleanMap, droppedCount = {}, 0
    if type(map) ~= "table" then return cleanMap, 0 end
    for key, value in pairs(map) do
        local ok, clean = pcall(sanitize, value)
        if ok and clean and keyIsValid(key, clean) then cleanMap[key] = clean else droppedCount = droppedCount + 1 end
    end
    return cleanMap, droppedCount
end

------------------------------------------------------------------ identity and time

-- server time in seconds (the local clock when the client has no server time, e.g. in the offline tests)
---@return integer
function Utility.Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

------------------------------------------------------------------ untrusted-input helpers (used by the sanitizers)

local INFINITY = math.huge

-- a real, finite number (rejects NaN, +/-inf and non-numbers)
---@param value any
---@return boolean
function Utility.IsFinite(value)
    return type(value) == "number" and value == value and value ~= INFINITY and value ~= -INFINITY
end

-- `value` when it is a finite integer within [lowest, highest], else nil
---@param value any
---@param lowest? number
---@param highest? number
---@return integer|nil
function Utility.SafeInteger(value, lowest, highest)
    if not Utility.IsFinite(value) or value ~= math.floor(value) then return nil end
    if (lowest and value < lowest) or (highest and value > highest) then return nil end
    return value
end

-- remove control characters (incl. NUL and DEL); keeps everything else, including multi-byte UTF-8
---@param text string
---@return string
function Utility.StripControlCharacters(text)
    return (text:gsub("[%z\1-\31\127]", ""))
end

-- `text` when it is a UTF-8 string of at most maximumBytes without control characters; otherwise nil
---@param text any
---@param maximumBytes? integer default 100
---@return string|nil
function Utility.CleanString(text, maximumBytes)
    if type(text) ~= "string" or #text > (maximumBytes or 100) then return nil end
    if text:find("[%z\1-\31\127]") or not Utility.IsValidUtf8(text) then return nil end
    return text
end

-- player/character names: 1..64 bytes, UTF-8, no control characters and no "|" (escape-sequence introducer)
---@param text any
---@return boolean
function Utility.IsSafeName(text)
    return Utility.CleanString(text, 64) ~= nil and text ~= "" and not text:find("|", 1, true)
end

-- Escape text that came from another player before it goes into a FontString: "|" starts colour/texture/hyperlink codes.
---@param text any
---@return string
function Utility.Escape(text)
    if type(text) ~= "string" then text = tostring(text) end
    return (text:gsub("|", "||"))
end

-- Text that came from another player, made safe for a CHAT line (SendChatMessage / print): every "|" (escape codes),
-- "[" / "]" (link brackets) and line break removed. Chat cannot show "||" as a literal bar, so it is removed, not escaped.
---@param text any
---@return string
function Utility.ChatSafe(text)
    if type(text) ~= "string" then text = tostring(text) end
    return (text:gsub("[|%[%]\r\n]", ""))
end

------------------------------------------------------------------ UTF-8 (WoW strings are UTF-8; Lua sees bytes)

-- Strict check: well-formed sequences only (no overlong forms, surrogates or code points above U+10FFFF).
---@param text any
---@return boolean
function Utility.IsValidUtf8(text)
    if type(text) ~= "string" then return false end
    local position, length = 1, #text
    while position <= length do
        local leadByte = text:byte(position)
        local sequenceLength
        if leadByte < 0x80 then sequenceLength = 1
        elseif leadByte >= 0xC2 and leadByte <= 0xDF then sequenceLength = 2
        elseif leadByte >= 0xE0 and leadByte <= 0xEF then sequenceLength = 3
        elseif leadByte >= 0xF0 and leadByte <= 0xF4 then sequenceLength = 4
        else return false end
        if position + sequenceLength - 1 > length then return false end
        for continuationPosition = position + 1, position + sequenceLength - 1 do
            local continuationByte = text:byte(continuationPosition)
            if continuationByte < 0x80 or continuationByte > 0xBF then return false end
        end
        if sequenceLength >= 3 then
            local secondByte = text:byte(position + 1)
            if leadByte == 0xE0 and secondByte < 0xA0 then return false end   -- overlong
            if leadByte == 0xED and secondByte > 0x9F then return false end   -- surrogate
            if leadByte == 0xF0 and secondByte < 0x90 then return false end   -- overlong
            if leadByte == 0xF4 and secondByte > 0x8F then return false end   -- above U+10FFFF
        end
        position = position + sequenceLength
    end
    return true
end

-- Longest prefix of `text` that is at most maximumBytes long and never ends inside a multi-byte character.
---@param text string
---@param maximumBytes integer
---@return string
function Utility.TruncateUtf8(text, maximumBytes)
    if #text <= maximumBytes then return text end
    local cutPosition = maximumBytes
    while cutPosition > 0 do
        local nextByte = text:byte(cutPosition + 1)
        if nextByte and nextByte >= 0x80 and nextByte <= 0xBF then cutPosition = cutPosition - 1 else break end
    end
    return text:sub(1, cutPosition)
end

-- UTF-8 bytes of a code point (only used for two-byte results)
---@param codePoint integer
---@return string
local function utf8Character(codePoint)
    if codePoint < 0x80 then return string.char(codePoint) end
    return string.char(0xC0 + math.floor(codePoint / 64), 0x80 + codePoint % 64)
end

---@type table<string, string>
local ASCII_LOWER_CASE = {}
for letterCode = 65, 90 do ASCII_LOWER_CASE[string.char(letterCode)] = string.char(letterCode + 32) end

-- lower-case of a two-byte (U+0080..U+07FF) character, as a code point
---@param codePoint integer
---@return integer
local function lowerCaseCodePoint(codePoint)
    if codePoint >= 0xC0 and codePoint <= 0xDE and codePoint ~= 0xD7 then return codePoint + 0x20 end          -- Latin-1
    if codePoint >= 0x100 and codePoint <= 0x137 and codePoint % 2 == 0 then return codePoint + 1 end          -- Latin Extended-A
    if codePoint >= 0x139 and codePoint <= 0x148 and codePoint % 2 == 1 then return codePoint + 1 end
    if codePoint >= 0x14A and codePoint <= 0x177 and codePoint % 2 == 0 then return codePoint + 1 end
    if codePoint == 0x178 then return 0xFF end
    if codePoint >= 0x179 and codePoint <= 0x17E and codePoint % 2 == 1 then return codePoint + 1 end
    if codePoint >= 0x391 and codePoint <= 0x3A9 and codePoint ~= 0x3A2 then return codePoint + 0x20 end       -- Greek
    if codePoint >= 0x410 and codePoint <= 0x42F then return codePoint + 0x20 end                               -- Cyrillic
    if codePoint >= 0x400 and codePoint <= 0x40F then return codePoint + 0x50 end
    return codePoint
end

-- accent-free replacement for lower-case Latin-1 / Cyrillic letters, by code point
---@type table<integer, string>
local ACCENT_FREE = {}
---@param codePoints integer[]
---@param replacement string
local function mapToAccentFree(codePoints, replacement)
    for _, codePoint in ipairs(codePoints) do ACCENT_FREE[codePoint] = replacement end
end
mapToAccentFree({ 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0x101, 0x103, 0x105 }, "a")
mapToAccentFree({ 0xE7, 0x107, 0x10D }, "c")
mapToAccentFree({ 0xE8, 0xE9, 0xEA, 0xEB, 0x113, 0x119, 0x11B }, "e")
mapToAccentFree({ 0xEC, 0xED, 0xEE, 0xEF }, "i")
mapToAccentFree({ 0xF1, 0x144, 0x148 }, "n")
mapToAccentFree({ 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF8, 0x151 }, "o")
mapToAccentFree({ 0x161, 0x15B }, "s")
mapToAccentFree({ 0xF9, 0xFA, 0xFB, 0xFC, 0x16F, 0x171 }, "u")
mapToAccentFree({ 0xFD, 0xFF }, "y")
mapToAccentFree({ 0x17A, 0x17C, 0x17E }, "z")
ACCENT_FREE[0xDF] = "ss"; ACCENT_FREE[0xE6] = "ae"; ACCENT_FREE[0x153] = "oe"
local CYRILLIC_SMALL_YO = 0x451   -- searched as ie
local CYRILLIC_SMALL_IE = 0x435

-- Case-insensitive form (ASCII, Latin, Greek, Cyrillic). Deterministic: independent of the C locale.
---@param text string
---@return string
function Utility.FoldCase(text)
    text = text:gsub("[A-Z]", ASCII_LOWER_CASE)
    return (text:gsub("([\195-\223])([\128-\191])", function(leadByte, continuationByte)
        local codePoint = (leadByte:byte() % 32) * 64 + continuationByte:byte() % 64
        local lowerCodePoint = lowerCaseCodePoint(codePoint)
        return lowerCodePoint == codePoint and (leadByte .. continuationByte) or utf8Character(lowerCodePoint)
    end))
end

-- Search/sort key: case- and accent-insensitive. "Kürschnerei" and "KURSCHNEREI" give the same key.
---@param text string
---@return string
function Utility.SearchKey(text)
    text = Utility.FoldCase(text)
    return (text:gsub("([\195-\223])([\128-\191])", function(leadByte, continuationByte)
        local codePoint = (leadByte:byte() % 32) * 64 + continuationByte:byte() % 64
        if codePoint == CYRILLIC_SMALL_YO then return utf8Character(CYRILLIC_SMALL_IE) end
        return ACCENT_FREE[codePoint] or (leadByte .. continuationByte)
    end))
end
