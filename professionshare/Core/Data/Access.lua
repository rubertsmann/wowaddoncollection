local addonName, addon = ...

-- Dungeon keys and raid attunements: which guild member can open which door or enter which raid. Pure Lua: the WoW side
-- is Api.ScanAccess, the UI side is Model/Window.
--
-- One record per character, authored ONLY by that character and replaced as a whole by the newer `rev` (like an offers
-- record). It changes once or twice in a character's life, so only its revision rides in HELLO (`arev`) and the record
-- itself is pulled (WANTA/ACCESS) only after a change.
-- A key is an item of class Key (13) or listed in Access.KEYS (entry items of another class); Access.DENY removes keys
-- that only matter inside one run. An attunement is held when one of its quests is completed or its item is held;
-- att[key] = false means "known not held", a missing key means "not known" (no quest API, item data not loaded yet).
-- The field names are the wire and saved-data format and stay as they are.

---@class AccessRecord
---@field name string the owner, canonical name
---@field rev integer revision: the newer one wins
---@field keys table<integer, table<string, true>> itemID -> location -> true
---@field att table<string, boolean> attunement key -> held

---@class AttunementDefinition
---@field key string the wire key
---@field instance string instance key (Access.INSTANCE_NAMES)
---@field quests integer[] any completed quest counts as attuned
---@field item integer|nil an item that counts as attuned while held
---@field icon string texture shown in the list

---@class AccessModule
local Access = {}
addon.Access = Access

local MAXIMUM_ID, MAXIMUM_KEYS = 2147483647, 60

---@type integer item class of keys
Access.KEY_CLASS = 13

-- key item -> instance it opens. Ids from the Warcraft Tavern keys guide and warcraft.wiki.gg, checked in game with
-- /ps access. Entry items of another class (Seal of Ascension, Drakefire Amulet) only count through this list.
---@type table<integer, string>
Access.KEYS = {
    [6893] = "gnomeregan",       -- Workshop Key
    [7146] = "scarlet",          -- The Scarlet Key
    [5396] = "searingGorge",     -- Key to Searing Gorge
    [11000] = "blackrockDepths", -- Shadowforge Key
    [11140] = "blackrockDepths", -- Prison Cell Key
    [13704] = "scholomance",     -- Skeleton Key
    [12382] = "stratholme",      -- Key to the City
    [18249] = "direMaul",        -- Crescent Key
    [12344] = "upperBlackrock",  -- Seal of Ascension
    [16309] = "onyxia",          -- Drakefire Amulet
}

-- class Key items that are left out: they only open something inside one run and vanish or are used up
---@type table<integer, true>
Access.DENY = {
    [11078] = true,   -- Relic Coffer Key
    [13873] = true,   -- Viewing Room Key
    [18250] = true,   -- Gordok Shackle Key
    [18266] = true,   -- Gordok Courtyard Key
    [18268] = true,   -- Gordok Inner Door Key
    [21761] = true,   -- Scarab Coffer Key
    [21762] = true,   -- Greater Scarab Coffer Key
}

-- display order of the attunements
---@type AttunementDefinition[]
Access.ATTUNEMENTS = {
    { key = "mc", instance = "moltenCore", quests = { 7848 }, icon = "Interface\\Icons\\Spell_Fire_LavaSpawn" },
    { key = "ony", instance = "onyxia", quests = { 6502, 6602 }, item = 16309, icon = "Interface\\Icons\\INV_Jewelry_Talisman_11" },
    { key = "bwl", instance = "blackwingLair", quests = { 7761 }, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Black" },
    { key = "naxx", instance = "naxxramas", quests = { 9121, 9122, 9123 }, icon = "Interface\\Icons\\INV_Trinket_Naxxramas06" },
    { key = "ubrs", instance = "upperBlackrock", quests = { 4743 }, item = 12344, icon = "Interface\\Icons\\INV_Jewelry_Ring_01" },
}

---@type table<string, AttunementDefinition>
local attunementByKey = {}
for _, attunement in ipairs(Access.ATTUNEMENTS) do attunementByKey[attunement.key] = attunement end

---@param attunementKey any
---@return AttunementDefinition|nil
function Access.Attunement(attunementKey) return attunementByKey[attunementKey] end

---@param instanceKey string|nil
---@return string|nil the instance name in the viewer's language
function Access.InstanceName(instanceKey)
    local Text = addon.Text
    local names = {
        gnomeregan = Text["Gnomeregan"], scarlet = Text["Scarlet Monastery"], searingGorge = Text["Searing Gorge"],
        blackrockDepths = Text["Blackrock Depths"], scholomance = Text["Scholomance"], stratholme = Text["Stratholme"],
        direMaul = Text["Dire Maul"], upperBlackrock = Text["Upper Blackrock Spire"], onyxia = Text["Onyxia's Lair"],
        moltenCore = Text["Molten Core"], blackwingLair = Text["Blackwing Lair"], naxxramas = Text["Naxxramas"],
    }
    return instanceKey and names[instanceKey] or nil
end

-- display order of key locations
---@type string[]
Access.LOCATION_ORDER = { "bag", "keyring", "bank" }
---@type table<string, integer>
local LOCATION_POSITION = {}
for position, location in ipairs(Access.LOCATION_ORDER) do LOCATION_POSITION[location] = position end

---@param location any
---@return boolean
function Access.IsLocation(location) return type(location) == "string" and LOCATION_POSITION[location] ~= nil end

-- Whether an item counts as a key. classID is the viewer's own client data (nil while the item is not loaded).
---@param itemID any
---@param classID any
---@return boolean
function Access.IsKey(itemID, classID)
    if type(itemID) ~= "number" or Access.DENY[itemID] then return false end
    return Access.KEYS[itemID] ~= nil or classID == Access.KEY_CLASS
end

---@return table
local function database() return addon.Store.db end

------------------------------------------------------------------ validation (network and persisted data)

-- Returns a CLEAN COPY of an access record or nil. A single bad entry rejects the whole record.
---@param accessRecord any
---@return AccessRecord|nil
function Access.Sanitize(accessRecord)
    local Utility = addon.Utility
    if type(accessRecord) ~= "table" or not Utility.IsSafeName(accessRecord.name) then return nil end
    local revision = Utility.SafeInteger(accessRecord.rev, 0, addon.Store.Horizon())
    if not revision then return nil end
    if type(accessRecord.keys) ~= "table" then return nil end
    local keys, keyCount = {}, 0
    for itemID, locations in pairs(accessRecord.keys) do
        keyCount = keyCount + 1
        if keyCount > MAXIMUM_KEYS or not Utility.SafeInteger(itemID, 1, MAXIMUM_ID) or type(locations) ~= "table" then return nil end
        local cleanLocations, locationCount = {}, 0
        for location, held in pairs(locations) do
            locationCount = locationCount + 1
            if locationCount > #Access.LOCATION_ORDER or not Access.IsLocation(location) or held ~= true then return nil end
            cleanLocations[location] = true
        end
        if locationCount == 0 then return nil end
        keys[itemID] = cleanLocations
    end
    local attunements = {}
    if accessRecord.att ~= nil then
        if type(accessRecord.att) ~= "table" then return nil end
        for attunementKey, held in pairs(accessRecord.att) do
            if not attunementByKey[attunementKey] or type(held) ~= "boolean" then return nil end
            attunements[attunementKey] = held
        end
    end
    return { name = accessRecord.name, rev = revision, keys = keys, att = attunements }
end

------------------------------------------------------------------ store access

---@param playerName string
---@return AccessRecord|nil
function Access.Get(playerName) return database().access[playerName] end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
---@param accessRecord AccessRecord
---@return boolean
function Access.Put(accessRecord)
    if type(accessRecord) ~= "table" or type(accessRecord.name) ~= "string" then return false end
    local storedRecord = database().access[accessRecord.name]
    if storedRecord and (storedRecord.rev or 0) >= (accessRecord.rev or 0) then return false end
    database().access[accessRecord.name] = accessRecord
    return true
end

-- Re-validates persisted records (SavedVariables are untrusted on load). Returns the number dropped.
---@param savedVariables table
---@return integer droppedCount
function Access.SanitizePersisted(savedVariables)
    local accessRecords, droppedCount = addon.Utility.SanitizeMap(savedVariables.access, Access.Sanitize,
        function(playerName, clean) return clean.name == playerName end)
    savedVariables.access = accessRecords
    return droppedCount
end

------------------------------------------------------------------ my record

-- content signature (ignores rev), to tell whether a scan changed anything
---@param accessRecord AccessRecord|nil
---@return string
local function signature(accessRecord)
    if not accessRecord then return "" end
    local keyParts = {}
    for _, itemID in ipairs(addon.Utility.SortedKeys(accessRecord.keys)) do
        local locationParts = {}
        for _, location in ipairs(Access.LOCATION_ORDER) do
            if accessRecord.keys[itemID][location] then locationParts[#locationParts + 1] = location end
        end
        keyParts[#keyParts + 1] = itemID .. "{" .. table.concat(locationParts, ",") .. "}"
    end
    local attunementParts = {}
    for _, attunement in ipairs(Access.ATTUNEMENTS) do
        local held = accessRecord.att[attunement.key]
        if held ~= nil then attunementParts[#attunementParts + 1] = attunement.key .. (held and "+" or "-") end
    end
    return table.concat(keyParts, ";") .. "|" .. table.concat(attunementParts, ";")
end

---@class AccessScan
---@field keys table<string, table<integer, true>> location -> itemID -> true, only the locations that could be read
---@field att table<string, boolean> attunement key -> held, only the attunements that could be judged

-- A location that is NOT a key of scan.keys was not readable and keeps its old state; an attunement missing from scan.att
-- keeps its old value. Returns true when my record changed (rev bumped).
---@param myName string
---@param scan AccessScan
---@param now integer
---@return boolean
function Access.Update(myName, scan, now)
    if type(myName) ~= "string" or type(scan) ~= "table" then return false end
    local Utility = addon.Utility
    local previousRecord = database().access[myName]
    local accessRecord = previousRecord and Utility.DeepCopy(previousRecord) or { name = myName, rev = 0, keys = {}, att = {} }
    local scannedKeys = type(scan.keys) == "table" and scan.keys or {}
    for itemID, locations in pairs(accessRecord.keys) do
        for location in pairs(locations) do
            if scannedKeys[location] ~= nil then locations[location] = nil end
        end
        if next(locations) == nil then accessRecord.keys[itemID] = nil end
    end
    for location, heldItems in pairs(scannedKeys) do
        if Access.IsLocation(location) and type(heldItems) == "table" then
            for itemID in pairs(heldItems) do
                if Utility.SafeInteger(itemID, 1, MAXIMUM_ID) and not Access.DENY[itemID] then
                    accessRecord.keys[itemID] = accessRecord.keys[itemID] or {}
                    accessRecord.keys[itemID][location] = true
                end
            end
        end
    end
    -- hard cap: never exceed what peers accept (an oversized record would be dropped whole by everyone)
    local keyCount = Utility.Count(accessRecord.keys)
    if keyCount > MAXIMUM_KEYS then
        local itemIDs = Utility.SortedKeys(accessRecord.keys)
        for index = MAXIMUM_KEYS + 1, #itemIDs do accessRecord.keys[itemIDs[index]] = nil end
        addon.Log.Warning("access.update", "more keys than peers accept; the highest item ids were left out",
            { keyCount = keyCount, maximum = MAXIMUM_KEYS })
    end
    for attunementKey, held in pairs(type(scan.att) == "table" and scan.att or {}) do
        if attunementByKey[attunementKey] and type(held) == "boolean" then accessRecord.att[attunementKey] = held end
    end
    if not previousRecord and next(accessRecord.keys) == nil and next(accessRecord.att) == nil then return false end
    if signature(accessRecord) == signature(previousRecord) then return false end
    accessRecord.rev = math.max(now, (previousRecord and previousRecord.rev or 0) + 1)
    database().access[myName] = accessRecord
    return true
end

------------------------------------------------------------------ listing

---@class KeyHolderRow
---@field who string
---@field locations string[] in display order

-- itemID -> holders (sorted by name) over every known record
---@return table<integer, KeyHolderRow[]>
function Access.KeyHolders()
    local holdersByItem = {}
    for owner, accessRecord in pairs(database().access) do
        for itemID, locations in pairs(accessRecord.keys) do
            if not Access.DENY[itemID] then
                local holderLocations = {}
                for _, location in ipairs(Access.LOCATION_ORDER) do
                    if locations[location] then holderLocations[#holderLocations + 1] = location end
                end
                holdersByItem[itemID] = holdersByItem[itemID] or {}
                table.insert(holdersByItem[itemID], { who = owner, locations = holderLocations })
            end
        end
    end
    for _, holderRows in pairs(holdersByItem) do table.sort(holderRows, function(left, right) return left.who < right.who end) end
    return holdersByItem
end

---@class AttunementStatus
---@field yes string[] members who hold it, sorted
---@field no string[] members known not to hold it, sorted

-- attunement key -> who holds it and who is known not to
---@return table<string, AttunementStatus>
function Access.AttunementStatus()
    local statusByKey = {}
    for _, attunement in ipairs(Access.ATTUNEMENTS) do statusByKey[attunement.key] = { yes = {}, no = {} } end
    for owner, accessRecord in pairs(database().access) do
        for attunementKey, held in pairs(accessRecord.att) do
            local status = statusByKey[attunementKey]
            if status then table.insert(held and status.yes or status.no, owner) end
        end
    end
    for _, status in pairs(statusByKey) do table.sort(status.yes); table.sort(status.no) end
    return statusByKey
end

-- counts for the diagnostics: number of records, number of held keys
---@return integer recordCount
---@return integer keyCount
function Access.Counts()
    local keyCount = 0
    for _, accessRecord in pairs(database().access) do keyCount = keyCount + addon.Utility.Count(accessRecord.keys) end
    return addon.Utility.Count(database().access), keyCount
end
