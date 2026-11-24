local addonName, addon = ...

-- Craft cooldowns: the timegated crafts of Classic / Forever (GROUPS) and each character's cooldown record. Pure Lua: the
-- WoW side is Api.ReadCraftCooldowns, the UI side is Model.BuildCooldownTiles and UI/CooldownGrid.lua.
--
-- A group is one shared cooldown: every transmute is one group, because the game gives all of them one timer.
-- One record per character, authored ONLY by that character and replaced as a whole by the newer `rev`. The owner stores
-- its ready times in its own server time. A record that is sent carries the owner's server time at sending (`at`, in
-- the message). The receiver keeps `readyAt - at` (the time left) and adds it to its own clock, so two clients whose clocks
-- differ still show the same time left. A ready time of 0 means "ready"; a group missing from the record means "not known".
-- The field names are the wire and saved-data format and stay as they are.

---@class CraftCooldownGroup
---@field key string record key (never shown)
---@field name string English name (fallback when the client knows neither the spell nor the item)
---@field profession string English profession name (fallback label)
---@field skillLine integer profession skill line id (colour and localized name)
---@field recipes integer[] recipe ids whose crafters share this cooldown (empty: item groups)
---@field casts integer[] spell ids whose successful cast starts the cooldown
---@field item? integer item whose own cooldown is the group's cooldown (Salt Shaker)
---@field produces integer item the craft makes (icon, link, tooltip)
---@field reagents { itemID: integer, count: integer }[] what one craft needs (empty: differs per recipe)
---@field fallback integer seconds; used only after an observed cast that the game did not report a cooldown for
---@field verified boolean ids and fallback confirmed in game (/ps cd)

---@class CraftCooldownRecord
---@field name string the owner, canonical name
---@field rev integer revision: the newer one wins (owner's server time of the last shared change)
---@field c table<string, integer> group key -> ready time (owner's clock in my own record, my clock in a peer's), 0 = ready
---@field e table<string, boolean> group key -> the ready time is an estimate (cast seen, no cooldown reported)
---@field seen? integer my clock when the record arrived (peers' records) or was last read from the game (my own)

---@class CraftCooldownsModule
local CraftCooldowns = {}
addon.CraftCooldowns = CraftCooldowns

local MAXIMUM_TIME = 2147483647
local MAXIMUM_GROUPS = 16
-- a ready time further away than this is garbage (the longest Classic cooldown is a few days)
CraftCooldowns.MAXIMUM_REMAINING = 8 * 86400
-- ready times that move by less than this are the same reading (the game rounds, the clock ticks between reads)
CraftCooldowns.JITTER = 60

-- Timegated crafts of Classic / Forever. Recipe ids are the classic spell ids (enchant recipes on Forever showed
-- that classic recipes keep them; docs/api-findings.md). Not confirmed in game yet: run /ps cd.
---@type CraftCooldownGroup[]
CraftCooldowns.GROUPS = {
    { key = "transmute", name = "Transmute", profession = "Alchemy", skillLine = 171,
        recipes = { 11479, 11480, 17187, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 25146 },
        casts = { 11479, 11480, 17187, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 25146 },
        produces = 12360, reagents = {}, fallback = 86400, verified = false },
    { key = "mooncloth", name = "Mooncloth", profession = "Tailoring", skillLine = 197,
        recipes = { 18560 }, casts = { 18560 },
        produces = 14342, reagents = { { itemID = 14256, count = 2 } }, fallback = 4 * 86400, verified = false },
    { key = "saltshaker", name = "Refined Deeprock Salt", profession = "Leatherworking", skillLine = 165,
        recipes = {}, casts = { 19566 }, item = 15846,
        produces = 15409, reagents = { { itemID = 8150, count = 1 } }, fallback = 3 * 86400, verified = false },
}

local groupByKey, groupByRecipe, groupByCast = {}, {}, {}
for _, group in ipairs(CraftCooldowns.GROUPS) do
    groupByKey[group.key] = group
    for _, recipeID in ipairs(group.recipes) do groupByRecipe[recipeID] = group end
    for _, spellID in ipairs(group.casts) do groupByCast[spellID] = group end
end

---@param groupKey any
---@return CraftCooldownGroup|nil
function CraftCooldowns.Group(groupKey) return groupByKey[groupKey] end

---@param recipeID any
---@return CraftCooldownGroup|nil
function CraftCooldowns.GroupOfRecipe(recipeID) return groupByRecipe[recipeID] end

---@param spellID any
---@return CraftCooldownGroup|nil
function CraftCooldowns.GroupOfCast(spellID) return groupByCast[spellID] end

---@return table
local function database() return addon.Store.db end

------------------------------------------------------------------ validation (network and persisted data)

-- Returns a CLEAN COPY of a cooldown record or nil. A malformed entry rejects the whole record; a well-formed entry for a
-- group this build does not know (a newer peer) is skipped.
---@param cooldownRecord any
---@return CraftCooldownRecord|nil
function CraftCooldowns.Sanitize(cooldownRecord)
    local Utility = addon.Utility
    if type(cooldownRecord) ~= "table" or not Utility.IsSafeName(cooldownRecord.name) then return nil end
    local revision = Utility.SafeInteger(cooldownRecord.rev, 0, addon.Store.Horizon())
    if not revision or type(cooldownRecord.c) ~= "table" then return nil end
    if cooldownRecord.e ~= nil and type(cooldownRecord.e) ~= "table" then return nil end
    local readyTimes, estimates, groupCount = {}, {}, 0
    for groupKey, readyAt in pairs(cooldownRecord.c) do
        groupCount = groupCount + 1
        if groupCount > MAXIMUM_GROUPS or type(groupKey) ~= "string" or #groupKey > 24 then return nil end
        if not Utility.SafeInteger(readyAt, 0, MAXIMUM_TIME) then return nil end
        if groupByKey[groupKey] then readyTimes[groupKey] = readyAt end
    end
    for groupKey, isEstimate in pairs(cooldownRecord.e or {}) do
        if isEstimate ~= true then return nil end
        if readyTimes[groupKey] then estimates[groupKey] = true end
    end
    local clean = { name = cooldownRecord.name, rev = revision, c = readyTimes, e = estimates }
    local seen = Utility.SafeInteger(cooldownRecord.seen, 0, MAXIMUM_TIME)
    if seen then clean.seen = seen end
    return clean
end

-- A peer's record as received (owner's clock) -> the same record in MY clock. `sentAt` is the owner's server time when it
-- sent the record (nil from a peer that does not send it: the clocks are taken as equal). A group whose time left is
-- negative is ready; one with more time left than any cooldown has is dropped.
---@param cooldownRecord CraftCooldownRecord a sanitized record
---@param sentAt any
---@param receiverNow integer
---@return CraftCooldownRecord
function CraftCooldowns.FromWire(cooldownRecord, sentAt, receiverNow)
    local ownerNow = addon.Utility.SafeInteger(sentAt, 1, MAXIMUM_TIME) or receiverNow
    local readyTimes, estimates = {}, {}
    for groupKey, readyAt in pairs(cooldownRecord.c) do
        local remaining = readyAt > 0 and (readyAt - ownerNow) or 0
        if remaining <= CraftCooldowns.MAXIMUM_REMAINING then
            readyTimes[groupKey] = remaining > 0 and (receiverNow + remaining) or 0
            estimates[groupKey] = cooldownRecord.e[groupKey]
        end
    end
    return { name = cooldownRecord.name, rev = cooldownRecord.rev, c = readyTimes, e = estimates, seen = receiverNow }
end

-- My record as it goes on the wire: without my local `seen`.
---@param cooldownRecord CraftCooldownRecord
---@return CraftCooldownRecord
function CraftCooldowns.ToWire(cooldownRecord)
    return { name = cooldownRecord.name, rev = cooldownRecord.rev, c = cooldownRecord.c, e = cooldownRecord.e }
end

------------------------------------------------------------------ store access

---@param playerName string
---@return CraftCooldownRecord|nil
function CraftCooldowns.Get(playerName) return database().cds[playerName] end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
---@param cooldownRecord CraftCooldownRecord
---@return boolean
function CraftCooldowns.Put(cooldownRecord)
    if type(cooldownRecord) ~= "table" or type(cooldownRecord.name) ~= "string" then return false end
    local storedRecord = database().cds[cooldownRecord.name]
    if storedRecord and (storedRecord.rev or 0) >= (cooldownRecord.rev or 0) then return false end
    database().cds[cooldownRecord.name] = cooldownRecord
    return true
end

-- Re-validates persisted records (SavedVariables are untrusted on load). Returns the number dropped.
---@param savedVariables table
---@return integer droppedCount
function CraftCooldowns.SanitizePersisted(savedVariables)
    local cooldownRecords, droppedCount = addon.Utility.SanitizeMap(savedVariables.cds, CraftCooldowns.Sanitize,
        function(playerName, clean) return clean.name == playerName end)
    savedVariables.cds = cooldownRecords
    return droppedCount
end

------------------------------------------------------------------ my record

---@class CooldownReading
---@field remaining number seconds until ready (0 = ready)
---@field source "spell"|"trade"|"item"|"cast" where the value came from

-- the ready time as compared: anything at or before `now` is "ready" (0)
---@param readyAt integer|nil
---@param now integer
---@return integer|nil
local function effective(readyAt, now)
    if readyAt == nil then return nil end
    if readyAt <= now then return 0 end
    return readyAt
end

-- Updates my record from what the game told me.
-- known: group key -> true for every group I can do (I know one of its recipes, or I hold its item).
-- readings: group key -> CooldownReading for the groups the game answered for. A known group without a reading keeps its
-- last value (the game did not answer this time); a group I can no longer do is removed.
-- Returns true when my record changed in a way the guild should see (rev bumped).
---@param myName string
---@param known table<string, boolean>
---@param readings table<string, CooldownReading>
---@param now integer
---@return boolean changed
function CraftCooldowns.Update(myName, known, readings, now)
    if type(myName) ~= "string" or type(known) ~= "table" or type(readings) ~= "table" then return false end
    local previousRecord = database().cds[myName]
    local previousTimes = previousRecord and previousRecord.c or {}
    local previousEstimates = previousRecord and previousRecord.e or {}
    local readyTimes, estimates, changed = {}, {}, false
    for groupKey in pairs(known) do
        if groupByKey[groupKey] then
            local reading = readings[groupKey]
            local remaining = reading and addon.Utility.IsFinite(reading.remaining) and reading.remaining or nil
            if remaining and remaining >= 0 and remaining <= CraftCooldowns.MAXIMUM_REMAINING then
                readyTimes[groupKey] = remaining > 0 and math.floor(now + remaining + 0.5) or 0
                estimates[groupKey] = reading.source == "cast" or nil
            elseif previousTimes[groupKey] then
                readyTimes[groupKey], estimates[groupKey] = previousTimes[groupKey], previousEstimates[groupKey]
            end
            local before, after = effective(previousTimes[groupKey], now), effective(readyTimes[groupKey], now)
            if (before == nil) ~= (after == nil)
                or (before and after and math.abs(before - after) > CraftCooldowns.JITTER)
                or (previousEstimates[groupKey] or false) ~= (estimates[groupKey] or false) then
                changed = true
            end
        end
    end
    for groupKey in pairs(previousTimes) do
        if readyTimes[groupKey] == nil then changed = true end
    end
    if not previousRecord and next(readyTimes) == nil then return false end
    if not changed then
        previousRecord.seen = now
        return false
    end
    local previousRevision = previousRecord and previousRecord.rev or 0
    database().cds[myName] = { name = myName, rev = math.max(now, previousRevision + 1), c = readyTimes, e = estimates, seen = now }
    return true
end

-- A cast of a group spell was seen: until the game reports the real cooldown, the group's fallback duration is used and
-- marked as an estimate. Returns true when my record changed.
---@param myName string
---@param spellID integer
---@param known table<string, boolean>
---@param now integer
---@return boolean changed
function CraftCooldowns.NoteCast(myName, spellID, known, now)
    local group = groupByCast[spellID]
    if not group then return false end
    local knownWithCast = {}
    for groupKey in pairs(known or {}) do knownWithCast[groupKey] = true end
    knownWithCast[group.key] = true
    return CraftCooldowns.Update(myName, knownWithCast, { [group.key] = { remaining = group.fallback, source = "cast" } }, now)
end

------------------------------------------------------------------ listing

-- Which groups a character record can do through its recipes.
---@param characterRecord any
---@return table<string, boolean>
function CraftCooldowns.GroupsOfCharacter(characterRecord)
    local groups = {}
    if type(characterRecord) ~= "table" or type(characterRecord.professions) ~= "table" then return groups end
    for _, profession in pairs(characterRecord.professions) do
        if type(profession) == "table" and type(profession.recipes) == "table" then
            for recipeID in pairs(profession.recipes) do
                local group = groupByRecipe[recipeID]
                if group then groups[group.key] = true end
            end
        end
    end
    return groups
end

-- counts for the diagnostics: number of records, number of group entries
---@return integer recordCount
---@return integer entryCount
function CraftCooldowns.Counts()
    local entryCount = 0
    for _, cooldownRecord in pairs(database().cds) do entryCount = entryCount + addon.Utility.Count(cooldownRecord.c) end
    return addon.Utility.Count(database().cds), entryCount
end
