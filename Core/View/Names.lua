local addonName, addon = ...

-- Game names resolved for the VIEWER. Stored/sent data carries ids (plus a name snapshot tagged with its language);
-- display names are computed here, on the viewer's client. Pure Lua: WoW lookups come in through Names.environment.
---@class NamesEnvironment
---@field spellName? fun(spellID: integer): string|nil localized spell/recipe name (set by Api.lua)

---@class NamesModule
---@field environment NamesEnvironment
local Names = {}
addon.Names = Names
Names.environment = {}

local Utility = addon.Utility
local Locale = addon.Locale

---@return string
local function clientLanguageCode() return Locale.clientCode end

-- names the viewer's own client reported: db.profNames[clientLocale][skillLineID] = name
---@return table<integer, string>
local function learnedProfessionNames()
    local database = addon.db
    if not database then return {} end
    database.profNames = database.profNames or {}
    local namesBySkillLine = database.profNames[clientLanguageCode()]
    if not namesBySkillLine then namesBySkillLine = {}; database.profNames[clientLanguageCode()] = namesBySkillLine end
    return namesBySkillLine
end

-- Remembers the profession name this client reports for a skill line id.
---@param skillLineID any
---@param professionName any
function Names.Learn(skillLineID, professionName)
    if type(skillLineID) ~= "number" or type(professionName) ~= "string" or professionName == "" then return end
    local namesBySkillLine = learnedProfessionNames()
    if namesBySkillLine[skillLineID] ~= professionName then
        namesBySkillLine[skillLineID] = professionName
        Locale.version = Locale.version + 1
    end
end

-- folded name -> skill line id over every registered language and every learned name (cached per Locale.version)
---@type table<string, integer>|nil
local skillLineByFoldedName
---@type integer|nil
local skillLineIndexVersion
---@return table<string, integer>
local function skillLineIndex()
    if skillLineByFoldedName and skillLineIndexVersion == Locale.version then return skillLineByFoldedName end
    skillLineByFoldedName, skillLineIndexVersion = {}, Locale.version
    for _, namesBySkillLine in pairs(Locale.professions) do
        for skillLineID, professionName in pairs(namesBySkillLine) do skillLineByFoldedName[Utility.SearchKey(professionName)] = skillLineID end
    end
    local database = addon.db
    for _, namesBySkillLine in pairs(database and database.profNames or {}) do
        for skillLineID, professionName in pairs(namesBySkillLine) do skillLineByFoldedName[Utility.SearchKey(professionName)] = skillLineID end
    end
    return skillLineByFoldedName
end

-- Canonical identity of a profession entry: its skill line id when known (sent by 0.2+ clients or found through the
-- name tables), else a folded-name string. Both spellings of "Cooking" give the same key.
---@param professionKey any the key in the record's professions table
---@param profession? table the profession entry
---@return integer|string
function Names.ProfessionKey(professionKey, profession)
    if profession and type(profession.id) == "number" then return profession.id end
    if type(professionKey) == "number" then return professionKey end
    local professionName = (profession and type(profession.name) == "string" and profession.name)
        or (type(professionKey) == "string" and professionKey) or "?"
    local folded = Utility.SearchKey(professionName)
    return skillLineIndex()[folded] or ("n:" .. folded)
end

-- Display name in the viewer's language.
---@param canonicalKey integer|string a Names.ProfessionKey result
---@param profession? table
---@return string
function Names.Profession(canonicalKey, profession)
    local skillLineID = type(canonicalKey) == "number" and canonicalKey
        or (profession and type(profession.id) == "number" and profession.id) or nil
    local languageCode = clientLanguageCode()
    if skillLineID then
        local learnedName = learnedProfessionNames()[skillLineID]
        if learnedName then return learnedName end
        if profession and profession.name and profession.loc == languageCode then return profession.name end
        local staticNames = Locale.professions[languageCode]
        if staticNames and staticNames[skillLineID] then return staticNames[skillLineID] end
        local englishNames = Locale.professions.enUS
        if englishNames and englishNames[skillLineID] then return englishNames[skillLineID] end
    end
    if profession and type(profession.name) == "string" and profession.name ~= "" then return profession.name end
    if skillLineID then return Locale.Format(addon.Text["Profession #{id}"], { id = skillLineID }) end
    return (tostring(canonicalKey):gsub("^n:", ""))
end

-- Recipe name in the viewer's language. `catalogEntry` may be nil.
---@param recipeID integer
---@param catalogEntry? CatalogEntry
---@return string
function Names.Recipe(recipeID, catalogEntry)
    if catalogEntry and catalogEntry.name and catalogEntry.loc == clientLanguageCode() then return catalogEntry.name end
    local spellName = Names.environment.spellName
    local spellLookup = spellName and spellName(recipeID)
    if type(spellLookup) == "string" and spellLookup ~= "" then return spellLookup end
    if catalogEntry and catalogEntry.name then return catalogEntry.name end
    return Locale.Format(addon.Text["Recipe #{id}"], { id = recipeID })
end
