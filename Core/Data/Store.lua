local addonName, addon = ...

-- SavedVariables schema and queries. Pure Lua (no WoW calls) so it runs in the offline tests.
-- The field names of the stored records are the saved-data format (and, for chars/catalog, the wire format): they stay
-- short and unchanged; only code names are written out in full.
--   chars[playerName]  = CharacterRecord
--   catalog[recipeID]  = CatalogEntry
--   orders[orderID]    = Order (see Orders.lua)
--   offers[playerName] = OfferRecord: recipe items on offer + that character's dibs (see Offers.lua)
--   hidden[offerKey]   = owner's revision when the viewer hid that offer

---@class ProfessionEntry
---@field id? integer skill line id
---@field loc? string language code of `name`
---@field name? string profession name snapshot in that language
---@field rank integer
---@field max integer
---@field recipes table<integer, true>

---@class CharacterRecord
---@field name string canonical "Name-Realm"
---@field class? string class file name ("MAGE")
---@field level integer
---@field rev integer revision: the newer one wins
---@field professions table<string, ProfessionEntry> by profession key (name or skill line id as text)

---@class ReagentEntry
---@field itemID integer
---@field count integer
---@field name? string

---@class CatalogEntry
---@field name? string recipe name snapshot
---@field loc? string language code of `name`
---@field icon? integer|string texture
---@field produces? integer item id the recipe makes
---@field minSkill? integer
---@field reagents ReagentEntry[]

---@class CrafterRow
---@field name string
---@field class? string
---@field level integer
---@field rev integer
---@field profession string profession key
---@field pentry ProfessionEntry the profession entry itself
---@field rank integer
---@field max integer

---@class StoreModule
---@field db table the SavedVariables table this session uses
local Store = {}
addon.Store = Store

-- Schema history (docs/protocol.md "Stored data"):
--   1  0.1.0 / 0.2.0   raw records as received
--   2  0.3.0           every persisted record is re-validated on load (allow-list copy); hostile or corrupt entries dropped
--   3  0.4.0           + offers, hidden (recipe items board); additive, schema 2 data is kept
--   4  0.6.0           + games (guild games, feature 014); additive, schema 3 data is kept
--   5  0.7.0           - games and the games UI settings (moved to the GuildGames addon, feature 015; fresh start)
Store.SCHEMA = 5

local SECONDS_PER_DAY = 86400
local MAXIMUM_ID = 2147483647              -- recipe / item / spell ids fit a signed 32-bit integer
Store.TIME_SLACK = SECONDS_PER_DAY        -- timestamps further than this into the future are rejected (clock skew is seconds)

-- Upper bound for timestamps (rev, createdAt, closedAt, claim time). If the clock is not usable yet (server time still 0,
-- or a unit test), "the future" cannot be judged: no upper bound, so a slow clock never wipes saved data.
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
    for _, key in ipairs({ "chars", "catalog", "orders", "offers", "hidden", "debug", "ui" }) do
        if type(savedVariables[key]) ~= "table" then savedVariables[key] = {} end
    end
    -- network trace ring (Core/Debug/Trace.lua, feature 008)
    if type(savedVariables.trace) ~= "table" then savedVariables.trace = {} end
    -- [clientLocale][skillLineID] = profession name the viewer's own client reported
    if type(savedVariables.profNames) ~= "table" then savedVariables.profNames = {} end
    -- feature 011: { locale, items = { [itemID] = tooltip text } }, this client only
    if type(savedVariables.itemText) ~= "table" then savedVariables.itemText = {} end
    return savedVariables
end

---@class StoreCounts
---@field chars integer
---@field recipes integer
---@field orders integer
---@field catalog integer
---@field names integer
---@field offers integer

-- Sizes of everything held locally (for /ts clean).
---@return StoreCounts
function Store.Counts()
    local Count = addon.Utility.Count
    local counts = { chars = Count(Store.db.chars), recipes = 0, orders = Count(Store.db.orders), catalog = Count(Store.db.catalog),
        names = 0, offers = 0 }
    for _, offerRecord in pairs(Store.db.offers) do counts.offers = counts.offers + Count(offerRecord.items) end
    for _, namesBySkillLine in pairs(Store.db.profNames) do counts.names = counts.names + Count(namesBySkillLine) end
    for _, characterRecord in pairs(Store.db.chars) do counts.recipes = counts.recipes + Store.RecipeCount(characterRecord) end
    return counts
end

-- Number of recipes a character record holds, over all its professions (0 for anything malformed).
---@param characterRecord any
---@return integer
function Store.RecipeCount(characterRecord)
    local recipeCount = 0
    if type(characterRecord) ~= "table" or type(characterRecord.professions) ~= "table" then return 0 end
    for _, profession in pairs(characterRecord.professions) do
        recipeCount = recipeCount + addon.Utility.Count(type(profession) == "table" and profession.recipes)
    end
    return recipeCount
end

-- Whether a character record knows recipeID in any of its professions (false for anything malformed).
---@param characterRecord any
---@param recipeID integer
---@return boolean
function Store.Knows(characterRecord, recipeID)
    if type(characterRecord) ~= "table" or type(characterRecord.professions) ~= "table" then return false end
    for _, profession in pairs(characterRecord.professions) do
        if type(profession) == "table" and type(profession.recipes) == "table" and profession.recipes[recipeID] then return true end
    end
    return false
end

-- Removes every cached and synced thing. The tables are emptied IN PLACE (Orders and Sync hold references to them);
-- UI preferences, `schema` and `me` stay. Returns the counts that were removed.
---@return StoreCounts
function Store.Clean()
    local removed = Store.Counts()
    for _, key in ipairs({ "chars", "catalog", "orders", "offers", "hidden", "profNames", "debug", "trace", "itemText" }) do
        addon.Utility.Wipe(Store.db[key])
    end
    addon.Log.Reset()
    return removed
end

-- After an update (or a switch to another version) everything that came from other members is dropped, because an older
-- build may have stored it under other name keys or other rules, and mixed state broke the UI until /ts clean. Kept: my
-- own character record and offers (re-scanning needs a profession window per profession), the catalog entries of my own
-- recipes, the orders (the only copy of an order may be mine; CanonicalizeStoredNames has given them the current keys),
-- UI settings. Everything dropped is fetched again from online members. Tables are emptied IN PLACE.
---@param myName string|nil
---@return { chars: integer, offers: integer, catalog: integer } removed
function Store.ResetPeerData(myName)
    local database = Store.db
    local removed = { chars = 0, offers = 0, catalog = 0 }
    local myRecipeIDs = {}
    local myRecord = myName and database.chars[myName]
    for _, profession in pairs(myRecord and myRecord.professions or {}) do
        for recipeID in pairs(profession.recipes or {}) do myRecipeIDs[recipeID] = true end
    end
    for playerName in pairs(database.chars) do
        if playerName ~= myName then database.chars[playerName] = nil removed.chars = removed.chars + 1 end
    end
    for playerName in pairs(database.offers) do
        if playerName ~= myName then database.offers[playerName] = nil removed.offers = removed.offers + 1 end
    end
    for recipeID in pairs(database.catalog) do
        if not myRecipeIDs[recipeID] then database.catalog[recipeID] = nil removed.catalog = removed.catalog + 1 end
    end
    for _, key in ipairs({ "hidden", "trace" }) do
        addon.Utility.Wipe(database[key])
    end
    return removed
end

-- Re-validates every persisted peer record by allow-list copy and drops what fails. Returns the number dropped.
-- SavedVariables are untrusted on load: older/newer builds, hand edits and corruption all end up here.
---@param savedVariables table
---@return integer droppedCount
function Store.SanitizePersisted(savedVariables)
    local Utility = addon.Utility
    local droppedCount, droppedHere = 0, 0
    savedVariables.chars, droppedHere = Utility.SanitizeMap(savedVariables.chars, Store.SanitizeCharacter,
        function(playerName, clean) return clean.name == playerName end)
    droppedCount = droppedCount + droppedHere
    savedVariables.catalog, droppedHere = Utility.SanitizeMap(savedVariables.catalog, Store.SanitizeCatalogEntry,
        function(recipeID) return Utility.SafeInteger(recipeID, 1, MAXIMUM_ID) ~= nil end)
    droppedCount = droppedCount + droppedHere
    savedVariables.orders, droppedHere = Utility.SanitizeMap(savedVariables.orders, addon.Orders.Sanitize,
        function(orderID, clean) return clean.id == orderID end)
    droppedCount = droppedCount + droppedHere
    droppedCount = droppedCount + addon.Offers.SanitizePersisted(savedVariables)
    local professionNamesByLanguage = {}
    if type(savedVariables.profNames) == "table" then
        for languageCode, namesBySkillLine in pairs(savedVariables.profNames) do
            if type(languageCode) == "string" and #languageCode >= 2 and #languageCode <= 8 and languageCode:match("^[%a_]+$")
                and type(namesBySkillLine) == "table" then
                local cleanNames = {}
                for skillLineID, professionName in pairs(namesBySkillLine) do
                    if Utility.SafeInteger(skillLineID, 1, 1000000) and Utility.CleanString(professionName, 60) then
                        cleanNames[skillLineID] = professionName
                    else
                        droppedCount = droppedCount + 1
                    end
                end
                professionNamesByLanguage[languageCode] = cleanNames
            else
                droppedCount = droppedCount + 1
            end
        end
    end
    savedVariables.profNames = professionNamesByLanguage
    addon.Trace.SanitizePersisted(savedVariables)
    return droppedCount
end

-- schema n -> n+1. Peer-derived caches (chars, catalog) are re-fetchable via HELLO/WANT, so migrations may simply drop
-- them; only orders (and the viewer's own record) deserve care.
---@type table<integer, fun(savedVariables: table)>
local MIGRATIONS = {
    [1] = function(savedVariables) Store.SanitizePersisted(savedVariables) end,
    [2] = function(savedVariables)   -- additive: new tables only
        savedVariables.offers, savedVariables.hidden = savedVariables.offers or {}, savedVariables.hidden or {}
    end,
    [3] = function(savedVariables)   -- additive: guild games (feature 014)
        if type(savedVariables.games) ~= "table" then savedVariables.games = {} end
    end,
    [4] = function(savedVariables)   -- feature 015: the games moved to the GuildGames addon (fresh start, nothing imported)
        savedVariables.games = nil
        if type(savedVariables.ui) == "table" then
            for _, key in ipairs({ "lastStakeCopper", "lastSlotStakeCopper", "gamesScope", "gameKey" }) do savedVariables.ui[key] = nil end
        end
    end,
}

---@alias MigrationStatus "ok"|"migrated"|"newer"|"reset"

-- Returns savedVariables, status:
--   "ok" | "migrated"   usable table (modified in place)
--   "newer"             saved by a newer build: nil table, caller must NOT overwrite the file
--   "reset"             not a table / corrupt schema marker: nil table, start empty
---@param savedVariables any
---@return table|nil
---@return MigrationStatus
function Store.Migrate(savedVariables)
    if type(savedVariables) ~= "table" then return nil, "reset" end
    local schemaVersion = savedVariables.schema
    if schemaVersion == nil then schemaVersion = 1 end
    if not addon.Utility.SafeInteger(schemaVersion, 1, 1000000) then return nil, "reset" end
    if schemaVersion > Store.SCHEMA then return nil, "newer" end
    local migrated = schemaVersion < Store.SCHEMA
    while schemaVersion < Store.SCHEMA do
        local migration = MIGRATIONS[schemaVersion]
        if migration then
            local ok, errorMessage = pcall(migration, savedVariables)
            if not ok then
                -- a failed migration must not leave half-converted caches; both are re-fetched from the guild
                savedVariables.chars, savedVariables.catalog = {}, {}
                addon.Log.Exception("store.migrate", "a saved-data migration failed; cached characters and catalog were dropped",
                    errorMessage, { fromSchema = schemaVersion, toSchema = schemaVersion + 1 })
            end
        end
        schemaVersion = schemaVersion + 1
        savedVariables.schema = schemaVersion
    end
    return savedVariables, migrated and "migrated" or "ok"
end

-- Returns savedVariables, status. The caller assigns `savedVariables` back to the SavedVariables global:
--   "newer": returns the ORIGINAL untouched table (so the file on disk keeps the newer data) and runs this session on a
--            throwaway database that is never saved.
---@param savedVariables table|nil
---@return table
---@return MigrationStatus
function Store.Init(savedVariables)
    if savedVariables == nil then   -- first run: nothing to migrate
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
    local droppedCount = Store.SanitizePersisted(loadedVariables)   -- every load, not only migrations
    Store.db, addon.db = loadedVariables, loadedVariables
    if status == "reset" then
        addon.Log.Warning("store.load", "saved data was not usable and started empty", { savedType = type(savedVariables) })
    elseif status == "migrated" then
        addon.Log.Information("store.load", "saved data was migrated", { schema = Store.SCHEMA })
    end
    if droppedCount > 0 then
        addon.Log.Warning("store.load", "dropped stored records that failed validation", { count = droppedCount })
    end
    return loadedVariables, status or "ok"
end

---@param playerName string
---@return CharacterRecord|nil
function Store.GetCharacter(playerName)
    return Store.db.chars[playerName]
end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
---@param characterRecord CharacterRecord
---@return boolean
function Store.PutCharacter(characterRecord)
    if type(characterRecord) ~= "table" or type(characterRecord.name) ~= "string" then return false end
    local storedRecord = Store.db.chars[characterRecord.name]
    if storedRecord and (storedRecord.rev or 0) >= (characterRecord.rev or 0) then return false end
    Store.db.chars[characterRecord.name] = characterRecord
    return true
end

-- every cached character, sorted by name
---@return CharacterRecord[]
function Store.ListCharacters()
    local characterRecords = {}
    for _, characterRecord in pairs(Store.db.chars) do characterRecords[#characterRecords + 1] = characterRecord end
    table.sort(characterRecords, function(left, right) return left.name < right.name end)
    return characterRecords
end

-- First writer wins. Every entry is rebuilt by allow-list copy, so nothing but validated fields is ever stored.
---@param catalogEntries table<integer, any>
function Store.PutCatalog(catalogEntries)
    if type(catalogEntries) ~= "table" then return end
    for recipeID, catalogEntry in pairs(catalogEntries) do
        if addon.Utility.SafeInteger(recipeID, 1, MAXIMUM_ID) and Store.db.catalog[recipeID] == nil then
            local clean = Store.SanitizeCatalogEntry(catalogEntry)
            if clean then Store.db.catalog[recipeID] = clean end
        end
    end
end

---@param recipeID integer
---@return CatalogEntry|nil
function Store.GetRecipe(recipeID)
    return Store.db.catalog[recipeID]
end

-- Everyone (cached) who knows recipeID, with their rank in the owning profession; highest rank first.
---@param recipeID integer
---@return CrafterRow[]
function Store.Crafters(recipeID)
    local crafterRows = {}
    for _, characterRecord in pairs(Store.db.chars) do
        for professionKey, profession in pairs(characterRecord.professions or {}) do
            if profession.recipes and profession.recipes[recipeID] then
                crafterRows[#crafterRows + 1] = { name = characterRecord.name, class = characterRecord.class,
                    level = characterRecord.level, rev = characterRecord.rev, profession = professionKey,
                    pentry = profession, rank = profession.rank, max = profession.max }
                break
            end
        end
    end
    table.sort(crafterRows, function(left, right)
        if (left.rank or 0) ~= (right.rank or 0) then return (left.rank or 0) > (right.rank or 0) end
        return left.name < right.name
    end)
    return crafterRows
end

-- Re-keys every stored player name with Utility.CanonicalName (on login, and whenever a new spelling of my realm was
-- learned), so a record received under one spelling and the roster's other spelling become the same key. Two keys that
-- become one keep the newer record. Tables are rewritten IN PLACE (Orders and Sync hold references).
---@return integer changedCount number of names that changed
function Store.CanonicalizeStoredNames()
    local CanonicalName = addon.Utility.CanonicalName
    local Refill = addon.Utility.Refill
    local changedCount = 0
    ---@param playerName any
    ---@return any
    local function canonical(playerName)
        local canonicalName = type(playerName) == "string" and CanonicalName(playerName) or nil
        if canonicalName and canonicalName ~= playerName then changedCount = changedCount + 1 end
        return canonicalName or playerName
    end
    ---@param offerKey any "Owner-Realm:itemID"
    ---@return any
    local function canonicalOfferKey(offerKey)
        local owner, itemID = tostring(offerKey):match("^(.+):(%d+)$")
        if not owner then return offerKey end
        return canonical(owner) .. ":" .. itemID
    end
    local database = Store.db
    if database.me then database.me = canonical(database.me) end
    local characterRecords = {}
    for playerName, characterRecord in pairs(database.chars) do
        local canonicalName = canonical(playerName)
        characterRecord.name = canonicalName
        local keptRecord = characterRecords[canonicalName]
        if not keptRecord or (keptRecord.rev or 0) < (characterRecord.rev or 0) then characterRecords[canonicalName] = characterRecord end
    end
    Refill(database.chars, characterRecords)
    local offerRecords = {}
    for playerName, offerRecord in pairs(database.offers) do
        local canonicalName = canonical(playerName)
        offerRecord.name = canonicalName
        local dibs = {}
        for offerKey, dib in pairs(offerRecord.dibs or {}) do dibs[canonicalOfferKey(offerKey)] = dib end
        offerRecord.dibs = dibs
        local keptRecord = offerRecords[canonicalName]
        if not keptRecord or (keptRecord.rev or 0) < (offerRecord.rev or 0) then offerRecords[canonicalName] = offerRecord end
    end
    Refill(database.offers, offerRecords)
    local hiddenOffers = {}
    for offerKey, ownerRevision in pairs(database.hidden) do hiddenOffers[canonicalOfferKey(offerKey)] = ownerRevision end
    Refill(database.hidden, hiddenOffers)
    for _, order in pairs(database.orders) do
        order.requester = canonical(order.requester)
        if order.closedBy then order.closedBy = canonical(order.closedBy) end
        local claims = {}
        for crafter, claim in pairs(order.claims or {}) do
            local canonicalCrafter = canonical(crafter)
            local keptClaim = claims[canonicalCrafter]
            if not keptClaim or (claim.t or 0) > (keptClaim.t or 0) then claims[canonicalCrafter] = claim end
        end
        order.claims = claims
    end
    return changedCount
end

-- Drop cached characters (and their offers) that are no longer in the guild roster; never drops `keptName`.
---@param rosterNames table<string, boolean>
---@param keptName string|nil
---@return integer removedCount characters removed
function Store.Prune(rosterNames, keptName)
    local removedCount, removedNames = 0, {}
    for playerName in pairs(Store.db.chars) do
        if not rosterNames[playerName] and playerName ~= keptName then
            Store.db.chars[playerName] = nil
            removedCount = removedCount + 1
            removedNames[#removedNames + 1] = playerName
        end
    end
    for playerName in pairs(Store.db.offers) do   -- offers of members who left the guild go with them
        if not rosterNames[playerName] and playerName ~= keptName then
            Store.db.offers[playerName] = nil
            removedNames[#removedNames + 1] = playerName .. "(offers)"
        end
    end
    -- a prune that removes records right after they arrived means the sender's name and the roster's form of it differ
    if #removedNames > 0 then
        table.sort(removedNames)
        addon.Trace.System("warn", "prune: not in guild roster", table.concat(removedNames, ", "))
        addon.Log.Information("store.prune", "removed records of players not in the guild roster",
            { count = #removedNames, names = table.concat(removedNames, ", ") })
    end
    return removedCount
end

------------------------------------------------------------------ allow-list sanitizers (network and persisted data)

-- optional localization fields: id = skill line id, loc = language code of the name snapshot, name = that snapshot
---@param languageCode any
---@return boolean
local function isValidLanguageCode(languageCode)
    return languageCode == nil
        or (type(languageCode) == "string" and #languageCode >= 2 and #languageCode <= 8 and languageCode:match("^[%a_]+$") ~= nil)
end

---@param professionName any
---@return boolean
local function isValidProfessionName(professionName)
    return professionName == nil
        or (addon.Utility.CleanString(professionName, 60) ~= nil and professionName ~= "" and not professionName:find("|", 1, true))
end

---@param profession table
---@return boolean
function Store.ValidateProfessionMetadata(profession)
    if profession.id ~= nil and not addon.Utility.SafeInteger(profession.id, 1, 1000000) then return false end
    if not isValidLanguageCode(profession.loc) then return false end
    if not isValidProfessionName(profession.name) then return false end
    return true
end

-- Returns a CLEAN COPY of a character record (only known fields, bounded, finite, UTF-8, no control characters) or nil.
-- `rev` must not lie in the future (it decides which snapshot wins; +inf or a far-future value would freeze a record).
---@param characterRecord any
---@return CharacterRecord|nil
function Store.SanitizeCharacter(characterRecord)
    local Utility = addon.Utility
    if type(characterRecord) ~= "table" then return nil end
    if not Utility.IsSafeName(characterRecord.name) then return nil end
    local revision = Utility.SafeInteger(characterRecord.rev, 0, Store.Horizon())
    local level = Utility.SafeInteger(characterRecord.level, 1, 100)
    if not revision or not level then return nil end
    local className = characterRecord.class
    if className ~= nil and (Utility.CleanString(className, 20) == nil or className:find("|", 1, true)) then return nil end
    if type(characterRecord.professions) ~= "table" then return nil end
    local clean = { name = characterRecord.name, class = className, level = level, rev = revision }
    local cleanProfessions, totalRecipes, professionCount = {}, 0, 0
    for professionKey, profession in pairs(characterRecord.professions) do
        professionCount = professionCount + 1
        if professionCount > 16 then return nil end
        if type(professionKey) ~= "string" or professionKey == "" or not Utility.CleanString(professionKey, 60)
            or professionKey:find("|", 1, true) or type(profession) ~= "table" or not Store.ValidateProfessionMetadata(profession) then
            return nil
        end
        local rank, maximumRank = Utility.SafeInteger(profession.rank, 0, 1000), Utility.SafeInteger(profession.max, 0, 1000)
        if not rank or not maximumRank or rank > maximumRank or type(profession.recipes) ~= "table" then return nil end
        local recipes = {}
        for recipeID, known in pairs(profession.recipes) do
            if not Utility.SafeInteger(recipeID, 1, MAXIMUM_ID) or known ~= true then return nil end
            totalRecipes = totalRecipes + 1
            if totalRecipes > 2000 then return nil end
            recipes[recipeID] = true
        end
        cleanProfessions[professionKey] = { id = profession.id, loc = profession.loc, name = profession.name, rank = rank,
            max = maximumRank, recipes = recipes }
    end
    clean.professions = cleanProfessions
    return clean
end

---@param characterRecord any
---@return boolean
function Store.ValidateCharacter(characterRecord) return Store.SanitizeCharacter(characterRecord) ~= nil end

-- Safe texture reference: a numeric file id, or a path made of plain path characters.
---@param icon any
---@return boolean
local function isValidIcon(icon)
    if icon == nil then return true end
    if type(icon) == "number" then return addon.Utility.SafeInteger(icon, 0, MAXIMUM_ID) ~= nil end
    return type(icon) == "string" and addon.Utility.CleanString(icon, 200) ~= nil and icon:match("^[%w_%-%. \\/]+$") ~= nil
end

-- Returns a clean copy of a catalog entry or nil. Optional fields must be valid or absent; a bad one rejects the entry.
---@param catalogEntry any
---@return CatalogEntry|nil
function Store.SanitizeCatalogEntry(catalogEntry)
    local Utility = addon.Utility
    if type(catalogEntry) ~= "table" then return nil end
    if not isValidLanguageCode(catalogEntry.loc) then return nil end
    if catalogEntry.name ~= nil and (not Utility.CleanString(catalogEntry.name, 100) or catalogEntry.name:find("|", 1, true)) then return nil end
    if not isValidIcon(catalogEntry.icon) then return nil end
    if catalogEntry.produces ~= nil and not Utility.SafeInteger(catalogEntry.produces, 1, MAXIMUM_ID) then return nil end
    if catalogEntry.minSkill ~= nil and not Utility.SafeInteger(catalogEntry.minSkill, 0, 1000) then return nil end
    if type(catalogEntry.reagents) ~= "table" or #catalogEntry.reagents > 12 then return nil end
    local reagents = {}
    for index, reagent in ipairs(catalogEntry.reagents) do
        if type(reagent) ~= "table" or not Utility.SafeInteger(reagent.itemID, 1, MAXIMUM_ID)
            or not Utility.SafeInteger(reagent.count, 1, 1000) then return nil end
        if reagent.name ~= nil and (not Utility.CleanString(reagent.name, 100) or reagent.name:find("|", 1, true)) then return nil end
        reagents[index] = { itemID = reagent.itemID, count = reagent.count, name = reagent.name }
    end
    return { name = catalogEntry.name, loc = catalogEntry.loc, icon = catalogEntry.icon, produces = catalogEntry.produces,
        minSkill = catalogEntry.minSkill, reagents = reagents }
end

---@param catalogEntry any
---@return boolean
function Store.ValidateCatalogEntry(catalogEntry) return Store.SanitizeCatalogEntry(catalogEntry) ~= nil end
