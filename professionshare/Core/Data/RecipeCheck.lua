local addonName, addon = ...

-- Reads a recipe item's own tooltip on THIS client, for THIS character: which profession and skill it needs, whether the
-- client marks that line red, whether it is already known, whether it binds when picked up. Also tells my own loot chat
-- lines from other loot lines. Pure: the WoW strings and tooltip lines are handed in (Core/Game/Api.lua reads them).
-- No external data: every pattern is built from the client's own format strings, so it works in every client language.

---@class RecipeCheckStrings
---@field minSkill string|nil ITEM_MIN_SKILL, "Requires %s (%d)"
---@field known string|nil ITEM_SPELL_KNOWN, "Already known"
---@field bindOnPickup string|nil ITEM_BIND_ON_PICKUP, "Binds when picked up"
---@field loot { self: string[], pushed: string[], other: string[] }|nil loot chat formats by kind

---@class TooltipLine
---@field text string
---@field r? number
---@field g? number
---@field b? number

---@class RecipeReading
---@field lines integer
---@field profession string|nil profession name as the tooltip writes it
---@field required integer|nil required skill
---@field requiredRed boolean|nil the client coloured the requirement line red (nil: no colour known)
---@field known boolean
---@field bindOnPickup boolean

---@alias RecipeStatus "learnable"|"low"|"known"|"noProfession"|"unreadable"

---@class RecipeDecision
---@field status RecipeStatus
---@field rank integer|nil my skill in the required profession
---@field mismatch boolean the red colour disagrees with the stored skill

---@class RecipeCheckModule
local RecipeCheck = {}
addon.RecipeCheck = RecipeCheck

local MAGIC_CHARACTERS = "[%(%)%.%+%-%*%?%[%]%^%$]"

---@type table<string, { pattern: string, order: integer[] }|false>
local compiledFormats = {}

-- A Lua pattern for a client format string ("Requires %s (%d)", "%1$s bekommt Beute: %2$s."), anchored at both ends,
-- and the argument index of every capture. nil for anything that is not a usable format string.
---@param formatString any
---@return string|nil pattern
---@return integer[]|nil order argument index of each capture
function RecipeCheck.PatternFromFormat(formatString)
    if type(formatString) ~= "string" or formatString == "" then return nil end
    local cached = compiledFormats[formatString]
    if cached ~= nil then
        if not cached then return nil end
        return cached.pattern, cached.order
    end
    local parts, order, position, nextArgument = { "^" }, {}, 1, 1
    while position <= #formatString do
        local argumentText, conversion = formatString:match("^%%(%d+)%$([sd])", position)
        local length
        if argumentText then
            length = #argumentText + 3
        else
            conversion = formatString:match("^%%([sd%%])", position)
            length = 2
        end
        if conversion == "s" or conversion == "d" then
            parts[#parts + 1] = conversion == "s" and "(.+)" or "(%d+)"
            order[#order + 1] = argumentText and tonumber(argumentText) or nextArgument
            nextArgument = nextArgument + 1
            position = position + length
        elseif conversion == "%" then
            parts[#parts + 1] = "%%"
            position = position + 2
        else
            local character = formatString:sub(position, position)
            parts[#parts + 1] = character:find(MAGIC_CHARACTERS) and ("%" .. character) or character
            position = position + 1
        end
    end
    parts[#parts + 1] = "$"
    if #order == 0 then compiledFormats[formatString] = false return nil end
    local pattern = table.concat(parts)
    compiledFormats[formatString] = { pattern = pattern, order = order }
    return pattern, order
end

-- The arguments a format string was filled with to give `text`, by argument index; nil when it does not match.
---@param formatString any
---@param text any
---@return table<integer, string>|nil
function RecipeCheck.Match(formatString, text)
    if type(text) ~= "string" then return nil end
    local pattern, order = RecipeCheck.PatternFromFormat(formatString)
    if not pattern then return nil end
    local captures = { text:match(pattern) }
    if #captures == 0 then return nil end
    local arguments = {}
    for captureIndex, argumentIndex in ipairs(order) do arguments[argumentIndex] = captures[captureIndex] end
    return arguments
end

---@param line any
---@return boolean|nil
local function isRed(line)
    if type(line) ~= "table" or type(line.r) ~= "number" or type(line.g) ~= "number" or type(line.b) ~= "number" then return nil end
    return line.r > 0.9 and line.g < 0.3 and line.b < 0.3
end

---@param line any
---@return string
local function lineText(line)
    if type(line) == "table" then return type(line.text) == "string" and line.text or "" end
    return type(line) == "string" and line or ""
end

-- What a recipe tooltip says. Only the LAST "Requires <profession> (n)" line counts: the client shows the tooltip of the
-- item the recipe makes first (it can carry its own requirement) and the recipe's own requirement after the reagents
-- (seen on Forever). nil for no lines.
---@param lines (TooltipLine|string)[]|nil
---@param strings RecipeCheckStrings|nil
---@return RecipeReading|nil
function RecipeCheck.ReadTooltip(lines, strings)
    if type(lines) ~= "table" or #lines == 0 then return nil end
    strings = type(strings) == "table" and strings or {}
    local reading = { lines = #lines, known = false, bindOnPickup = false }
    for _, line in ipairs(lines) do
        local text = lineText(line)
        local arguments = RecipeCheck.Match(strings.minSkill, text)
        local required = arguments and tonumber(arguments[2])
        if arguments and arguments[1] and required then
            reading.profession, reading.required, reading.requiredRed = arguments[1], math.floor(required), isRed(line)
        end
        if strings.known and text == strings.known then reading.known = true end
        if strings.bindOnPickup and text == strings.bindOnPickup then reading.bindOnPickup = true end
    end
    return reading
end

---@param text any
---@return string
local function folded(text) return type(text) == "string" and text:lower() or "" end

-- My stored skill in the profession the tooltip names (matched by name, or by the profession key), or nil.
---@param professionName string
---@param myProfessions table<string, ProfessionEntry>|nil
---@return integer|nil
local function myRank(professionName, myProfessions)
    if type(myProfessions) ~= "table" then return nil end
    local wanted = folded(professionName)
    for professionKey, profession in pairs(myProfessions) do
        if type(profession) == "table" and (folded(profession.name) == wanted or folded(professionKey) == wanted) then
            return tonumber(profession.rank) or 0
        end
    end
    return nil
end

-- Whether this character can learn the recipe now, from the reading and my own stored professions.
---@param reading RecipeReading|nil
---@param myProfessions table<string, ProfessionEntry>|nil
---@return RecipeDecision
function RecipeCheck.Decide(reading, myProfessions)
    if type(reading) ~= "table" or not reading.required or not reading.profession then
        return { status = "unreadable", mismatch = false }
    end
    local rank = myRank(reading.profession, myProfessions)
    local status
    if reading.known then status = "known"
    elseif rank == nil then status = "noProfession"
    elseif rank >= reading.required then status = "learnable"
    else status = "low" end
    local mismatch = false
    if reading.requiredRed ~= nil and (status == "learnable" or status == "low") then
        mismatch = (status == "learnable") == reading.requiredRed
    end
    return { status = status, rank = rank, mismatch = mismatch }
end

---@class LootLine
---@field kind "self"|"pushed"|"other"
---@field link string
---@field itemID integer|nil
---@field count integer

-- Which kind of loot chat line `message` is, by the client's own formats (my loot first, so another player's line can
-- never count as mine). nil when it is no loot line with an item link.
---@param message any
---@param lootFormats { self: string[], pushed: string[], other: string[] }|nil
---@return LootLine|nil
function RecipeCheck.ParseLoot(message, lootFormats)
    if type(message) ~= "string" or type(lootFormats) ~= "table" then return nil end
    for _, kind in ipairs({ "self", "pushed", "other" }) do
        for _, formatString in ipairs(type(lootFormats[kind]) == "table" and lootFormats[kind] or {}) do
            local arguments = RecipeCheck.Match(formatString, message)
            if arguments then
                -- my own lines: 1 = link, 2 = count; another player's: 1 = name, 2 = link, 3 = count
                local link = kind == "other" and arguments[2] or arguments[1]
                local countText = kind == "other" and arguments[3] or arguments[2]
                local itemID = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
                if itemID then
                    return { kind = kind, link = link, itemID = itemID, count = tonumber(countText) or 1 }
                end
            end
        end
    end
    return nil
end
