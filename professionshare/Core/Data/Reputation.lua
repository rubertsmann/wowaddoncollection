local addonName, addon = ...

-- Reputation: each character's standing with the factions of FactionHints.FACTIONS. Pure Lua: the WoW side is
-- Api.ScanReputation, the UI side is Model/Window.
--
-- One record per character, authored ONLY by that character and replaced as a whole by the newer `rev` (like an access
-- record). Standing levels change rarely, progress inside a level all the time while a player farms: a level change bumps
-- the revision at once, a progress-only change at most every PROGRESS_INTERVAL seconds, so the guild is not asked to pull
-- the record after every kill. Factions the character has not met are not in the record.
-- The field names are the wire and saved-data format and stay as they are.

---@class FactionStanding
---@field s integer standing 1 Hated .. 8 Exalted
---@field v integer progress inside the standing
---@field m integer size of the standing (v <= m)

---@class ReputationRecord
---@field name string the owner, canonical name
---@field rev integer revision: the newer one wins (server time of the last shared change)
---@field f table<integer, FactionStanding> faction id -> standing

---@class ReputationModule
local Reputation = {}
addon.Reputation = Reputation

local MAXIMUM_FACTION_ID, MAXIMUM_FACTIONS, MAXIMUM_BAR = 100000, 64, 1000000

---@type integer standing ids
Reputation.HATED, Reputation.EXALTED = 1, 8
---@type integer seconds between two shared progress-only changes
Reputation.PROGRESS_INTERVAL = 1800

---@return table
local function database() return addon.Store.db end

------------------------------------------------------------------ validation (network and persisted data)

-- A clean copy of one standing, or nil.
---@param standing any
---@return FactionStanding|nil
function Reputation.SanitizeStanding(standing)
    local Utility = addon.Utility
    if type(standing) ~= "table" then return nil end
    local level = Utility.SafeInteger(standing.s, Reputation.HATED, Reputation.EXALTED)
    local size = Utility.SafeInteger(standing.m, 0, MAXIMUM_BAR)
    local progress = size and Utility.SafeInteger(standing.v, 0, size)
    if not level or not progress then return nil end
    return { s = level, v = progress, m = size }
end

-- Returns a CLEAN COPY of a reputation record or nil. A malformed entry rejects the whole record; a well-formed entry for
-- a faction this build does not list (a newer peer tracks more factions) is skipped.
---@param reputationRecord any
---@return ReputationRecord|nil
function Reputation.Sanitize(reputationRecord)
    local Utility = addon.Utility
    if type(reputationRecord) ~= "table" or not Utility.IsSafeName(reputationRecord.name) then return nil end
    local revision = Utility.SafeInteger(reputationRecord.rev, 0, addon.Store.Horizon())
    if not revision or type(reputationRecord.f) ~= "table" then return nil end
    local factions, factionCount = {}, 0
    for factionID, standing in pairs(reputationRecord.f) do
        factionCount = factionCount + 1
        if factionCount > MAXIMUM_FACTIONS or not Utility.SafeInteger(factionID, 1, MAXIMUM_FACTION_ID) then return nil end
        local cleanStanding = Reputation.SanitizeStanding(standing)
        if not cleanStanding then return nil end
        if addon.FactionHints.Faction(factionID) then factions[factionID] = cleanStanding end
    end
    return { name = reputationRecord.name, rev = revision, f = factions }
end

------------------------------------------------------------------ store access

---@param playerName string
---@return ReputationRecord|nil
function Reputation.Get(playerName) return database().rep[playerName] end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
---@param reputationRecord ReputationRecord
---@return boolean
function Reputation.Put(reputationRecord)
    if type(reputationRecord) ~= "table" or type(reputationRecord.name) ~= "string" then return false end
    local storedRecord = database().rep[reputationRecord.name]
    if storedRecord and (storedRecord.rev or 0) >= (reputationRecord.rev or 0) then return false end
    database().rep[reputationRecord.name] = reputationRecord
    return true
end

-- Re-validates persisted records (SavedVariables are untrusted on load). Returns the number dropped.
---@param savedVariables table
---@return integer droppedCount
function Reputation.SanitizePersisted(savedVariables)
    local reputationRecords, droppedCount = addon.Utility.SanitizeMap(savedVariables.rep, Reputation.Sanitize,
        function(playerName, clean) return clean.name == playerName end)
    savedVariables.rep = reputationRecords
    return droppedCount
end

------------------------------------------------------------------ my record

---@alias ReputationChange "none"|"progress"|"level"

-- What differs between two faction maps: "level" (a faction appeared, disappeared or changed its level), "progress"
-- (only progress inside a level) or "none".
---@param previousFactions table<integer, FactionStanding>
---@param factions table<integer, FactionStanding>
---@return ReputationChange
local function compare(previousFactions, factions)
    local change = "none"
    for factionID, standing in pairs(factions) do
        local previous = previousFactions[factionID]
        if not previous or previous.s ~= standing.s then return "level" end
        if previous.v ~= standing.v or previous.m ~= standing.m then change = "progress" end
    end
    for factionID in pairs(previousFactions) do
        if not factions[factionID] then return "level" end
    end
    return change
end

-- scan: faction id -> { s, v, m } for the listed factions the character has met (Api.ScanReputation). nil = the client
-- could not be asked: the record stays as it is. Returns true when my record changed (rev bumped), and as second value the
-- seconds after which a held-back progress change may be shared (the caller scans again then), else nil.
---@param myName string
---@param scan table<integer, FactionStanding>|nil
---@param now integer
---@param force? boolean share a progress-only change at once (/ps rep scan)
---@return boolean changed
---@return integer|nil retryAfter
function Reputation.Update(myName, scan, now, force)
    if type(myName) ~= "string" or type(scan) ~= "table" then return false end
    local factions = {}
    for factionID, standing in pairs(scan) do
        local cleanStanding = addon.FactionHints.Faction(factionID) and Reputation.SanitizeStanding(standing)
        if cleanStanding then factions[factionID] = cleanStanding end
    end
    local previousRecord = database().rep[myName]
    if not previousRecord and next(factions) == nil then return false end
    local change = compare(previousRecord and previousRecord.f or {}, factions)
    if change == "none" then return false end
    local previousRevision = previousRecord and previousRecord.rev or 0
    if change == "progress" and not force and now - previousRevision < Reputation.PROGRESS_INTERVAL then
        return false, Reputation.PROGRESS_INTERVAL - (now - previousRevision)
    end
    database().rep[myName] = { name = myName, rev = math.max(now, previousRevision + 1), f = factions }
    return true
end

------------------------------------------------------------------ listing

-- counts for the diagnostics: number of records, number of faction standings
---@return integer recordCount
---@return integer standingCount
function Reputation.Counts()
    local standingCount = 0
    for _, reputationRecord in pairs(database().rep) do standingCount = standingCount + addon.Utility.Count(reputationRecord.f) end
    return addon.Utility.Count(database().rep), standingCount
end
