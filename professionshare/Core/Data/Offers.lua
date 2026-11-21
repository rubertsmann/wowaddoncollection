local addonName, addon = ...

-- Recipe items on offer (feature 007). Pure Lua: the WoW side is Api.ScanItems, the UI side is Model/Window.
--
-- One record per character, authored ONLY by that character and replaced as a whole by the newer `rev` (like a character
-- record). Because a record is only ever written by its author, nobody can set or remove somebody else's dib.
-- Locations: bag bank reagent mail auction gbank1..gbank8. A scan replaces only the locations it could read.
-- Local removal ("hide") is never sent: hidden[offerKey] = the owner's rev at that time; a newer rev shows the offer again.
-- The field names are the wire and saved-data format and stay as they are.

---@class OfferDib
---@field on boolean
---@field t integer server time of the toggle; only grows per key

---@class OfferRecord
---@field name string the owner, canonical "Name-Realm"
---@field rev integer revision: the newer one wins
---@field items table<integer, table<string, integer>> itemID -> location -> count (what the owner holds)
---@field dibs table<string, OfferDib> offerKey ("Owner-Realm:itemID") -> MY dib on someone else's item

---@class OfferLocationCount
---@field loc string
---@field count integer

---@class OfferDibRow
---@field who string the player holding the dib
---@field t integer

---@class OfferRow
---@field key string offerKey
---@field owner string
---@field itemID integer
---@field locs OfferLocationCount[] in display order
---@field total integer
---@field ownerRev integer
---@field dibs OfferDibRow[] oldest first
---@field mine boolean I hold an active dib on it

---@class OffersModule
local Offers = {}
addon.Offers = Offers

local MAXIMUM_ID, MAXIMUM_ITEMS, MAXIMUM_DIBS, MAXIMUM_COUNT, MAXIMUM_HIDDEN = 2147483647, 300, 200, 9999, 500

---@type integer item class of recipes
Offers.RECIPE_CLASS = 9
-- recipe item subclass -> skill line id of the profession that uses it (book/others have none)
---@type table<integer, integer>
Offers.SUBCLASS_SKILL = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356,
    [10] = 755, [11] = 773 }
-- display order of locations
---@type string[]
Offers.LOCATION_ORDER = { "bag", "bank", "reagent", "mail", "auction", "gbank1", "gbank2", "gbank3", "gbank4", "gbank5",
    "gbank6", "gbank7", "gbank8" }

---@type table<string, integer>
local LOCATION_POSITION = {}
for position, location in ipairs(Offers.LOCATION_ORDER) do LOCATION_POSITION[location] = position end

---@param location any
---@return boolean
function Offers.IsLocation(location) return type(location) == "string" and LOCATION_POSITION[location] ~= nil end

---@param location string
---@return integer
function Offers.LocationIndex(location) return LOCATION_POSITION[location] or 99 end

---@param owner string
---@param itemID integer
---@return string offerKey
function Offers.Key(owner, itemID) return owner .. ":" .. itemID end

-- "Owner-Realm:12345" -> owner, itemID (nil when malformed; owner must be a safe name)
---@param offerKey any
---@return string|nil owner
---@return integer|nil itemID
function Offers.ParseKey(offerKey)
    if type(offerKey) ~= "string" or #offerKey > 100 then return nil end
    local owner, itemIDText = offerKey:match("^(.+):(%d+)$")
    local itemID = tonumber(itemIDText)
    if not owner or not addon.Utility.IsSafeName(owner) or not addon.Utility.SafeInteger(itemID, 1, MAXIMUM_ID) then return nil end
    return owner, itemID
end

---@return table
local function database() return addon.Store.db end

------------------------------------------------------------------ validation (network and persisted data)

---@param items any
---@return table<integer, table<string, integer>>|nil
local function sanitizeItems(items)
    local Utility = addon.Utility
    if type(items) ~= "table" then return nil end
    local cleanItems, itemCount = {}, 0
    for itemID, countByLocation in pairs(items) do
        itemCount = itemCount + 1
        if itemCount > MAXIMUM_ITEMS or not Utility.SafeInteger(itemID, 1, MAXIMUM_ID) or type(countByLocation) ~= "table" then return nil end
        local cleanCounts, locationCount = {}, 0
        for location, count in pairs(countByLocation) do
            locationCount = locationCount + 1
            if locationCount > #Offers.LOCATION_ORDER or not Offers.IsLocation(location)
                or not Utility.SafeInteger(count, 1, MAXIMUM_COUNT) then return nil end
            cleanCounts[location] = count
        end
        if locationCount == 0 then return nil end
        cleanItems[itemID] = cleanCounts
    end
    return cleanItems
end

-- Returns a CLEAN COPY of an offers record or nil. A single bad entry rejects the whole record.
---@param offerRecord any
---@return OfferRecord|nil
function Offers.Sanitize(offerRecord)
    local Utility = addon.Utility
    if type(offerRecord) ~= "table" or not Utility.IsSafeName(offerRecord.name) then return nil end
    local revision = Utility.SafeInteger(offerRecord.rev, 0, addon.Store.Horizon())
    if not revision then return nil end
    local items = sanitizeItems(offerRecord.items)
    if not items then return nil end
    local dibs, dibCount = {}, 0
    if offerRecord.dibs ~= nil then
        if type(offerRecord.dibs) ~= "table" then return nil end
        for offerKey, dib in pairs(offerRecord.dibs) do
            dibCount = dibCount + 1
            local owner = Offers.ParseKey(offerKey)
            if dibCount > MAXIMUM_DIBS or not owner or owner == offerRecord.name or type(dib) ~= "table" or type(dib.on) ~= "boolean"
                or not Utility.SafeInteger(dib.t, 0, addon.Store.Horizon()) then
                return nil
            end
            dibs[offerKey] = { on = dib.on, t = dib.t }
        end
    end
    return { name = offerRecord.name, rev = revision, items = items, dibs = dibs }
end

------------------------------------------------------------------ store access

---@param playerName string
---@return OfferRecord|nil
function Offers.Get(playerName) return database().offers[playerName] end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
---@param offerRecord OfferRecord
---@return boolean
function Offers.Put(offerRecord)
    if type(offerRecord) ~= "table" or type(offerRecord.name) ~= "string" then return false end
    local storedRecord = database().offers[offerRecord.name]
    if storedRecord and (storedRecord.rev or 0) >= (offerRecord.rev or 0) then return false end
    database().offers[offerRecord.name] = offerRecord
    return true
end

-- Re-validates persisted records (SavedVariables are untrusted on load). Returns the number dropped.
---@param savedVariables table
---@return integer droppedCount
function Offers.SanitizePersisted(savedVariables)
    local offerRecords, droppedCount = addon.Utility.SanitizeMap(savedVariables.offers, Offers.Sanitize,
        function(playerName, clean) return clean.name == playerName end)
    local hiddenOffers = {}
    if type(savedVariables.hidden) == "table" then
        local hiddenCount = 0
        for offerKey, ownerRevision in pairs(savedVariables.hidden) do
            hiddenCount = hiddenCount + 1
            if hiddenCount <= MAXIMUM_HIDDEN and Offers.ParseKey(offerKey) and addon.Utility.SafeInteger(ownerRevision, 0, 1e15) then
                hiddenOffers[offerKey] = ownerRevision
            else
                droppedCount = droppedCount + 1
            end
        end
    end
    savedVariables.offers, savedVariables.hidden = offerRecords, hiddenOffers
    return droppedCount
end

------------------------------------------------------------------ my record

-- content signature (ignores rev), to tell whether a scan changed anything
---@param offerRecord OfferRecord|nil
---@return string
local function signature(offerRecord)
    if not offerRecord then return "" end
    local itemIDs = addon.Utility.SortedKeys(offerRecord.items)
    local itemParts = {}
    for _, itemID in ipairs(itemIDs) do
        local locationParts = {}
        for _, location in ipairs(Offers.LOCATION_ORDER) do
            local count = offerRecord.items[itemID][location]
            if count then locationParts[#locationParts + 1] = location .. "=" .. count end
        end
        itemParts[#itemParts + 1] = itemID .. "{" .. table.concat(locationParts, ",") .. "}"
    end
    local dibParts = {}
    for offerKey, dib in pairs(offerRecord.dibs or {}) do dibParts[#dibParts + 1] = offerKey .. (dib.on and "+" or "-") .. dib.t end
    table.sort(dibParts)
    return table.concat(itemParts, ";") .. "|" .. table.concat(dibParts, ";")
end

---@param myName string
---@return OfferRecord
local function emptyRecord(myName) return { name = myName, rev = 0, items = {}, dibs = {} } end

-- stores my changed record with a revision newer than both the clock and the previous one
---@param myName string
---@param offerRecord OfferRecord
---@param now integer
---@param previousRecord OfferRecord|nil
---@return OfferRecord
local function commit(myName, offerRecord, now, previousRecord)
    offerRecord.rev = math.max(now, (previousRecord and previousRecord.rev or 0) + 1)
    database().offers[myName] = offerRecord
    return offerRecord
end

-- A location that is NOT a key of `scans` was not readable and keeps its old state.
-- Returns true when my record changed (rev bumped).
---@param myName string
---@param scans table<string, table<integer, integer>> location -> itemID -> count
---@param now integer
---@return boolean
function Offers.Update(myName, scans, now)
    if type(myName) ~= "string" or type(scans) ~= "table" then return false end
    local previousRecord = database().offers[myName]
    local offerRecord = previousRecord and addon.Utility.DeepCopy(previousRecord) or emptyRecord(myName)
    for itemID, countByLocation in pairs(offerRecord.items) do
        for location in pairs(countByLocation) do
            if scans[location] ~= nil then countByLocation[location] = nil end
        end
        if next(countByLocation) == nil then offerRecord.items[itemID] = nil end
    end
    for location, countByItem in pairs(scans) do
        if Offers.IsLocation(location) and type(countByItem) == "table" then
            for itemID, count in pairs(countByItem) do
                if addon.Utility.SafeInteger(itemID, 1, MAXIMUM_ID) and addon.Utility.SafeInteger(count, 1, MAXIMUM_COUNT) then
                    offerRecord.items[itemID] = offerRecord.items[itemID] or {}
                    offerRecord.items[itemID][location] = count
                end
            end
        end
    end
    -- hard cap: never exceed what peers accept (an oversized record would be dropped whole by everyone)
    local itemCount = addon.Utility.Count(offerRecord.items)
    if itemCount > MAXIMUM_ITEMS then
        local itemIDs = addon.Utility.SortedKeys(offerRecord.items)
        for index = MAXIMUM_ITEMS + 1, #itemIDs do offerRecord.items[itemIDs[index]] = nil end
        addon.Log.Warning("offers.update", "more recipe items than peers accept; the highest item ids were left out",
            { itemCount = itemCount, maximum = MAXIMUM_ITEMS })
    end
    if not previousRecord and next(offerRecord.items) == nil and next(offerRecord.dibs) == nil then return false end
    if signature(offerRecord) == signature(previousRecord) then return false end
    commit(myName, offerRecord, now, previousRecord)
    return true
end

-- Drops MY dibs on offers that vanished: the owner's record is known and no longer lists the item. Returns true when changed.
---@param myName string
---@param now integer
---@return boolean
function Offers.Maintain(myName, now)
    local previousRecord = database().offers[myName]
    if not previousRecord then return false end
    local offerRecord, changed = addon.Utility.DeepCopy(previousRecord), false
    for offerKey in pairs(previousRecord.dibs) do
        local owner, itemID = Offers.ParseKey(offerKey)
        local ownerRecord = owner and database().offers[owner]
        if not owner or (ownerRecord and not ownerRecord.items[itemID]) then
            offerRecord.dibs[offerKey] = nil
            changed = true
        end
    end
    if not changed then return false end
    commit(myName, offerRecord, now, previousRecord)
    return true
end

---@alias DibRefusal "self"|"gone"|"limit"|"unsafe"

-- Toggles MY dib on owner's item. Returns "on" | "off", or nil and the refusal reason.
---@param myName string
---@param owner string
---@param itemID integer
---@param now integer
---@return "on"|"off"|nil
---@return DibRefusal|nil
function Offers.ToggleDib(myName, owner, itemID, now)
    if owner == myName then return nil, "self" end
    local ownerRecord = owner and database().offers[owner]
    if not Offers.ParseKey(Offers.Key(owner or "", itemID or 0)) then return nil, "unsafe" end
    if not (ownerRecord and ownerRecord.items[itemID]) then return nil, "gone" end
    local previousRecord = database().offers[myName]
    local offerRecord = previousRecord and addon.Utility.DeepCopy(previousRecord) or emptyRecord(myName)
    local offerKey = Offers.Key(owner, itemID)
    local previousDib = offerRecord.dibs[offerKey]
    local turnOn = not (previousDib and previousDib.on)
    if turnOn then
        local activeDibs = 0
        for _, dib in pairs(offerRecord.dibs) do if dib.on then activeDibs = activeDibs + 1 end end
        if activeDibs >= MAXIMUM_DIBS then return nil, "limit" end
    end
    -- t only grows per key, so the newest toggle wins on every client
    offerRecord.dibs[offerKey] = { on = turnOn, t = math.max(now, (previousDib and previousDib.t or 0) + 1) }
    -- keep the record inside the transport/validation limit: drop the oldest switched-off entries first
    local totalDibs = addon.Utility.Count(offerRecord.dibs)
    if totalDibs > MAXIMUM_DIBS then
        local switchedOffKeys = {}
        for dibKey, dib in pairs(offerRecord.dibs) do if not dib.on then switchedOffKeys[#switchedOffKeys + 1] = dibKey end end
        table.sort(switchedOffKeys, function(left, right) return offerRecord.dibs[left].t < offerRecord.dibs[right].t end)
        for index = 1, math.min(#switchedOffKeys, totalDibs - MAXIMUM_DIBS) do offerRecord.dibs[switchedOffKeys[index]] = nil end
    end
    commit(myName, offerRecord, now, previousRecord)
    return turnOn and "on" or "off"
end

------------------------------------------------------------------ hide (local only)

-- Hides an offer for this viewer until the owner's record changes. False when the owner is unknown or the limit is hit.
---@param owner string
---@param itemID integer
---@return boolean
function Offers.Hide(owner, itemID)
    local ownerRecord = database().offers[owner]
    if not ownerRecord then return false end
    if addon.Utility.Count(database().hidden) >= MAXIMUM_HIDDEN then
        addon.Log.Warning("offers.hide", "too many hidden offers; this one was not hidden", { maximum = MAXIMUM_HIDDEN })
        return false
    end
    database().hidden[Offers.Key(owner, itemID)] = ownerRecord.rev
    return true
end

---@param owner string
---@param itemID integer
---@param ownerRevision integer
---@return boolean
local function isHidden(owner, itemID, ownerRevision)
    local hiddenAtRevision = database().hidden[Offers.Key(owner, itemID)]
    return hiddenAtRevision ~= nil and hiddenAtRevision >= ownerRevision
end

-- forget hide entries that no longer apply (owner changed or left)
function Offers.PruneHidden()
    for offerKey, hiddenAtRevision in pairs(database().hidden) do
        local owner, itemID = Offers.ParseKey(offerKey)
        local ownerRecord = owner and database().offers[owner]
        if not ownerRecord or ownerRecord.rev > hiddenAtRevision or not ownerRecord.items[itemID] then
            database().hidden[offerKey] = nil
        end
    end
end

------------------------------------------------------------------ listing

-- All visible offers. Hidden offers are left out. The owner's own items are included (so one sees them).
---@param myName string|nil
---@return OfferRow[]
function Offers.List(myName)
    local dibsByOfferKey = {}
    for dibHolder, offerRecord in pairs(database().offers) do
        for offerKey, dib in pairs(offerRecord.dibs or {}) do
            if dib.on then
                local dibRows = dibsByOfferKey[offerKey]
                if not dibRows then dibRows = {}; dibsByOfferKey[offerKey] = dibRows end
                dibRows[#dibRows + 1] = { who = dibHolder, t = dib.t }
            end
        end
    end
    local offerRows = {}
    for owner, offerRecord in pairs(database().offers) do
        for itemID, countByLocation in pairs(offerRecord.items) do
            if not isHidden(owner, itemID, offerRecord.rev) then
                local offerKey = Offers.Key(owner, itemID)
                local locationCounts, total, dibRows = {}, 0, dibsByOfferKey[offerKey] or {}
                for location, count in pairs(countByLocation) do
                    locationCounts[#locationCounts + 1] = { loc = location, count = count }
                    total = total + count
                end
                table.sort(locationCounts, function(left, right)
                    return Offers.LocationIndex(left.loc) < Offers.LocationIndex(right.loc)
                end)
                table.sort(dibRows, function(left, right)
                    if left.t ~= right.t then return left.t < right.t end
                    return left.who < right.who
                end)
                local mine = false
                for _, dibRow in ipairs(dibRows) do if dibRow.who == myName then mine = true end end
                offerRows[#offerRows + 1] = { key = offerKey, owner = owner, itemID = itemID, locs = locationCounts,
                    total = total, ownerRev = offerRecord.rev, dibs = dibRows, mine = mine }
            end
        end
    end
    return offerRows
end

-- counts for /ps clean: number of records, number of offered items
---@return integer recordCount
---@return integer itemCount
function Offers.Counts()
    local itemCount = 0
    for _, offerRecord in pairs(database().offers) do itemCount = itemCount + addon.Utility.Count(offerRecord.items) end
    return addon.Utility.Count(database().offers), itemCount
end
