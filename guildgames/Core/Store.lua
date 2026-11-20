local addonName, addon = ...

-- SavedVariables schema and queries. Pure Lua (no WoW calls) so it runs in the offline tests.
--   games[playerName] = GameRecord: that character's game results (Core/Games.lua; the field names are the wire format)
--   ui                = window settings (stakes, scope, selected game, UI language override)
--   me                = my canonical "Name-Realm"
--   debug, trace      = the log and the network trace rings
---@class StoreModule
---@field db table the SavedVariables table this session uses
local Store = {}
addon.Store = Store

-- Schema history:
--   1  0.1.0   games (moved from TalentShare 0.6.0, feature 015 there; nothing imported)
Store.SCHEMA = 2   -- 2: db.caught (AZEcaught, feature 018)

local SECONDS_PER_DAY = 86400
Store.TIME_SLACK = SECONDS_PER_DAY        -- timestamps further than this into the future are rejected (clock skew is seconds)

-- Upper bound for timestamps (rev, play times). If the clock is not usable yet (server time still 0, or a unit test),
-- "the future" cannot be judged: no upper bound, so a slow clock never wipes saved data.
---@return number
function Store.Horizon()
    local now = addon.Utility.Now()
    if now < 1000000000 then return math.huge end
    return now + Store.TIME_SLACK
end

-- every top-level table present (missing or wrong-typed ones become empty)
---@param savedVariables table|nil
---@return table
local function withAllTables(savedVariables)
    savedVariables = savedVariables or {}
    savedVariables.schema = Store.SCHEMA
    for _, key in ipairs({ "games", "ui", "debug", "trace", "caught" }) do
        if type(savedVariables[key]) ~= "table" then savedVariables[key] = {} end
    end
    return savedVariables
end

---@alias MigrationStatus "ok"|"migrated"|"reset"|"newer"

-- schema n -> n+1
---@type table<integer, fun(savedVariables: table)>
local MIGRATIONS = {
    -- 1 -> 2 (feature 018): AZEcaught's local state starts empty; game records are unchanged
    [1] = function(savedVariables) savedVariables.caught = {} end,
}

---@param savedVariables any
---@return table|nil
---@return MigrationStatus
function Store.Migrate(savedVariables)
    if type(savedVariables) ~= "table" then return nil, "reset" end
    local schemaVersion = savedVariables.schema
    if schemaVersion == nil then schemaVersion = Store.SCHEMA end
    if not addon.Utility.SafeInteger(schemaVersion, 1, 1000000) then return nil, "reset" end
    if schemaVersion > Store.SCHEMA then return nil, "newer" end
    local migrated = schemaVersion < Store.SCHEMA
    while schemaVersion < Store.SCHEMA do
        local migration = MIGRATIONS[schemaVersion]
        if migration then
            local ok, errorMessage = pcall(migration, savedVariables)
            if not ok then
                savedVariables.games = {}
                addon.Log.Exception("store.migrate", "a saved-data migration failed; game records were dropped",
                    errorMessage, { fromSchema = schemaVersion, toSchema = schemaVersion + 1 })
            end
        end
        schemaVersion = schemaVersion + 1
        savedVariables.schema = schemaVersion
    end
    return savedVariables, migrated and "migrated" or "ok"
end

-- Re-validates every persisted record (SavedVariables are untrusted on load). Returns the number dropped.
---@param savedVariables table
---@return integer droppedCount
function Store.SanitizePersisted(savedVariables)
    local droppedCount = addon.Games.SanitizePersisted(savedVariables)
    addon.Trace.SanitizePersisted(savedVariables)
    local droppedCaught = addon.AzeCaught and addon.AzeCaught.SanitizePersisted(savedVariables) or 0
    if droppedCaught > 0 then
        addon.AzeCaught.Journal("WARNING", "load", "invalid saved AZEcaught data was dropped", { count = droppedCaught })
    end
    return droppedCount
end

-- Returns savedVariables, status. The caller assigns `savedVariables` back to the SavedVariables global:
--   "newer": returns the ORIGINAL untouched table (the file keeps the newer data); this session runs on a throwaway
--            database that is never saved (db.readonly: plays are refused).
---@param savedVariables table|nil
---@return table
---@return MigrationStatus
function Store.Init(savedVariables)
    if savedVariables == nil then
        savedVariables = withAllTables({})
        Store.db, addon.db = savedVariables, savedVariables
        return savedVariables, "ok"
    end
    local migratedVariables, status = Store.Migrate(savedVariables)
    if status == "newer" then
        local throwawayDatabase = withAllTables({})
        throwawayDatabase.readonly = true
        Store.db, addon.db = throwawayDatabase, throwawayDatabase
        addon.Log.Error("store.load", "saved data was written by a newer build; this session runs without saving",
            { savedSchema = savedVariables.schema, supportedSchema = Store.SCHEMA })
        return savedVariables, status
    end
    local loadedVariables = withAllTables(migratedVariables)
    Store.db, addon.db = loadedVariables, loadedVariables
    local droppedCount = Store.SanitizePersisted(loadedVariables)
    if status == "reset" then
        addon.Log.Warning("store.load", "saved data was not usable and started empty", { savedType = type(savedVariables) })
    elseif status == "migrated" then
        addon.Log.Information("store.load", "saved data was migrated", { schema = Store.SCHEMA })
    end
    if droppedCount > 0 then
        addon.Log.Warning("store.load", "dropped invalid saved records", { count = droppedCount })
    end
    return loadedVariables, status
end

-- Every stored record under its canonical name (after a new spelling of my realm was learned). Two records that meet on
-- one key: the newer revision stays. Returns how many keys changed.
---@return integer changedCount
function Store.CanonicalizeStoredNames()
    local database = Store.db
    if not database then return 0 end
    local Utility = addon.Utility
    local gameRecords, changedCount = {}, 0
    for playerName, gameRecord in pairs(database.games) do
        local canonicalName = Utility.CanonicalName(playerName) or playerName
        if canonicalName ~= playerName then changedCount = changedCount + 1 end
        gameRecord.name = canonicalName
        local keptRecord = gameRecords[canonicalName]
        if not keptRecord or (keptRecord.rev or 0) < (gameRecord.rev or 0) then gameRecords[canonicalName] = gameRecord end
    end
    Utility.Refill(database.games, gameRecords)
    if database.me then database.me = Utility.CanonicalName(database.me) or database.me end
    return changedCount
end

-- Drops the game records of players no longer in the guild roster; never drops `keptName`.
---@param rosterNames table<string, boolean>
---@param keptName string|nil
---@return integer removedCount
function Store.Prune(rosterNames, keptName)
    local removedNames = {}
    for playerName in pairs(Store.db.games) do
        if not rosterNames[playerName] and playerName ~= keptName then
            Store.db.games[playerName] = nil
            removedNames[#removedNames + 1] = playerName
        end
    end
    if #removedNames > 0 then
        table.sort(removedNames)
        -- a prune right after records arrived means the sender's name and the roster's form of it differ
        addon.Trace.System("warn", "prune: not in guild roster", table.concat(removedNames, ", "))
        addon.Log.Information("store.prune", "removed records of players not in the guild roster",
            { count = #removedNames, names = table.concat(removedNames, ", ") })
    end
    return #removedNames
end

-- /gg clean: every game record (mine too), the log and the trace. UI settings, schema and me stay.
---@return integer removedRecords
function Store.Clean()
    local removedRecords = addon.Utility.Count(Store.db.games)
    for _, key in ipairs({ "games", "debug", "trace" }) do addon.Utility.Wipe(Store.db[key]) end
    addon.Log.Reset()
    return removedRecords
end
