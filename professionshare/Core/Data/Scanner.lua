local addonName, addon = ...

-- Builds MY character record from Api and stores it. Re-scanning identical data does not bump `rev`.
---@class ScannerModule
---@field lastScanSummary string what the last scan saw (which profession window, how many recipes), for the log
local Scanner = {}
addon.Scanner = Scanner
Scanner.lastScanSummary = "not scanned yet"

-- cheap content signature (ignores rev)
---@param characterRecord CharacterRecord|nil
---@return string
local function signature(characterRecord)
    if not characterRecord then return "" end
    local professionKeys = addon.Utility.SortedKeys(characterRecord.professions)
    local parts = { tostring(characterRecord.class), tostring(characterRecord.level) }
    for _, professionKey in ipairs(professionKeys) do
        local profession = characterRecord.professions[professionKey]
        local recipeCount, recipeIDSum, recipeIDSquareSum = 0, 0, 0
        for recipeID in pairs(profession.recipes) do
            recipeCount = recipeCount + 1
            recipeIDSum = recipeIDSum + recipeID
            recipeIDSquareSum = (recipeIDSquareSum + (recipeID * recipeID) % 2147483647) % 2147483647
        end
        parts[#parts + 1] = table.concat({ professionKey, profession.id or 0, profession.loc or "", profession.rank or 0,
            profession.max or 0, recipeCount, recipeIDSum, recipeIDSquareSum }, ":")
    end
    return table.concat(parts, "|")
end
Scanner.signature = signature

-- The key under which my record already holds this profession: matched by skill line id first (so a client language
-- switch renames the key instead of losing the recipes), then by name.
---@param characterRecord CharacterRecord
---@param skillLineID integer|nil
---@param professionName string
---@return string|nil
local function findProfessionKey(characterRecord, skillLineID, professionName)
    if skillLineID then
        for professionKey, profession in pairs(characterRecord.professions) do
            if profession.id == skillLineID then return professionKey end
        end
    end
    if characterRecord.professions[professionName] then return professionName end
    return nil
end

-- Returns true when my stored record changed.
---@param now integer server time
---@return boolean
function Scanner.Refresh(now)
    local Store, Api = addon.Store, addon.Api
    local playerInformation = Api.GetPlayerInformation()
    if not playerInformation.name then
        addon.Log.Debug("scanner.refresh", "skipped: the character name is not known yet")
        return false
    end
    local previousRecord = Store.GetCharacter(playerInformation.name)
    local characterRecord = previousRecord and addon.Utility.DeepCopy(previousRecord) or { name = playerInformation.name, professions = {} }
    characterRecord.class, characterRecord.level = playerInformation.class, playerInformation.level
    characterRecord.professions = characterRecord.professions or {}
    local clientLanguageCode = addon.Locale.clientCode

    -- ranks (needs no window). A nil list means "API unsupported": keep what we have (RF2).
    local playerProfessions = Api.GetPlayerProfessions()
    if playerProfessions then
        local presentNames = {}
        for _, playerProfession in ipairs(playerProfessions) do
            presentNames[playerProfession.name] = true
            local previousKey = findProfessionKey(characterRecord, playerProfession.id, playerProfession.name)
            local profession = (previousKey and characterRecord.professions[previousKey]) or { recipes = {} }
            if previousKey and previousKey ~= playerProfession.name then characterRecord.professions[previousKey] = nil end
            profession.name, profession.id, profession.loc = playerProfession.name, playerProfession.id, clientLanguageCode
            profession.rank, profession.max = playerProfession.rank, playerProfession.max
            characterRecord.professions[playerProfession.name] = profession
            addon.Names.Learn(playerProfession.id, playerProfession.name)
        end
        for professionKey in pairs(characterRecord.professions) do
            if not presentNames[professionKey] then characterRecord.professions[professionKey] = nil end
        end
    end

    -- recipes (only while a profession window is open and its list is loaded). An empty list never wipes data (RF2).
    local openProfession = Api.GetOpenProfession()
    Scanner.lastScanSummary = openProfession
        and ("%s#%s recipes=%d"):format(tostring(openProfession.name), tostring(openProfession.id), #openProfession.recipes)
        or "no profession window"
    if openProfession and #openProfession.recipes > 0 then
        local previousKey = findProfessionKey(characterRecord, openProfession.id, openProfession.name)
        local profession = (previousKey and characterRecord.professions[previousKey]) or { recipes = {} }
        if previousKey and previousKey ~= openProfession.name then characterRecord.professions[previousKey] = nil end
        profession.name, profession.loc = openProfession.name, clientLanguageCode
        profession.id = openProfession.id or profession.id
        profession.rank = (openProfession.rank and openProfession.rank > 0) and openProfession.rank or profession.rank or 0
        profession.max = (openProfession.max and openProfession.max > 0) and openProfession.max or profession.max or 0
        if profession.rank > profession.max then profession.max = profession.rank end
        local knownRecipes, catalogEntries = {}, {}
        for _, openRecipe in ipairs(openProfession.recipes) do
            knownRecipes[openRecipe.recipeID] = true
            catalogEntries[openRecipe.recipeID] = { name = openRecipe.name, loc = clientLanguageCode, icon = openRecipe.icon,
                produces = openRecipe.produces, reagents = openRecipe.reagents }
        end
        profession.recipes = knownRecipes
        characterRecord.professions[openProfession.name] = profession
        addon.Names.Learn(profession.id, openProfession.name)
        Store.PutCatalog(catalogEntries)
    end

    if signature(characterRecord) == signature(previousRecord) then
        Store.db.me = playerInformation.name
        return false
    end
    characterRecord.rev = math.max(now, ((previousRecord and previousRecord.rev) or 0) + 1)
    Store.PutCharacter(characterRecord)
    Store.db.me = playerInformation.name
    return true
end

addon.SlashCommands.scan = function()
    local changed = Scanner.Refresh(addon.Utility.Now())
    local myRecord = addon.Store.GetCharacter(addon.Store.db.me or "")
    addon.Print(("scan: %s, %d recipes known"):format(changed and "updated" or "unchanged", addon.Store.RecipeCount(myRecord)))
    -- why a scan finds nothing: recipes are only readable while ONE profession's recipe list is open
    local ok, openProfession = addon.Log.Protected("scanner.command", "reading the open profession window failed",
        addon.Api.GetOpenProfession)
    if not ok then
        addon.Print("profession window check failed: " .. tostring(openProfession))
    elseif not openProfession then
        addon.Print("no profession recipe list detected: open one profession's window (click its name, e.g. Kochkunst) and run this again")
    else
        addon.Print(("open profession: %s (id %s), %d learned recipes visible"):format(tostring(openProfession.name),
            tostring(openProfession.id), #openProfession.recipes))
    end
end

addon.SlashCommands.dump = function()
    local myRecord = addon.Store.GetCharacter(addon.Store.db.me or "")
    if not myRecord then addon.Print("no record yet; try " .. addon.SLASH_COMMANDS[1] .. " scan") return end
    for professionKey, profession in pairs(myRecord.professions) do
        addon.Print(("%s (id %s) %d/%d: %d recipes"):format(
            addon.Names.Profession(addon.Names.ProfessionKey(professionKey, profession), profession), tostring(profession.id),
            profession.rank or 0, profession.max or 0, addon.Utility.Count(profession.recipes)))
    end
end
