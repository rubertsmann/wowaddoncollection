local addonName, addon = ...

-- STATIC DATA, NOT READ FROM THE GAME: the spell that opens a profession's recipe window, cast by id so the client's
-- language does not matter. On WoW Forever these are hidden spells (not in the spellbook); "/cast <profession>" resolves
-- to them. Spellbook spells are never cast: Skinning's are a wilderness camp spell (1278068, it toggles the open window
-- closed) and the gathering spell named like the profession. Ids were read in game (UNIT_SPELLCAST_SUCCEEDED after
-- "/cast <profession>"); a profession not listed here falls back to "/cast <profession>". PURE Lua: no WoW calls.
---@class ProfessionSpellsModule
local ProfessionSpells = {}
addon.ProfessionSpells = ProfessionSpells

-- skill line id -> the spell that opens its recipe window
---@type table<integer, integer>
ProfessionSpells.WINDOW = {
    [165] = 1240961,    -- Leatherworking
    [185] = 1240956,    -- Cooking
    [393] = 1240974,    -- Skinning
}

-- The window spell of a profession, or nil when it is not known (the caller then casts by name).
---@param skillLineID integer|nil
---@return integer|nil
function ProfessionSpells.WindowSpellID(skillLineID)
    return ProfessionSpells.WINDOW[skillLineID or 0]
end

------------------------------------------------------------------ reports from guild members (filling WINDOW)
-- Every client notes which spell opened which of its profession windows (Core/Game/Events.lua) and sends the pairs in
-- its HELLO (field `wsp`, "165:1240961,393:1240974"), like the build tag. Only the developer's client keeps what it
-- receives (db.windowSpellReports); nothing else uses the reports.

ProfessionSpells.MAXIMUM_SKILL_LINES = 16
ProfessionSpells.MAXIMUM_SPELLS_PER_SKILL_LINE = 4
ProfessionSpells.MAXIMUM_REPORTERS = 10   -- names kept per reported pair
ProfessionSpells.MAXIMUM_WIRE_LENGTH = 200

---@param value any
---@return boolean
local function isID(value) return type(value) == "number" and value >= 1 and value <= 99999999 and value % 1 == 0 end

---@param table_ table
---@return integer
local function count(table_) local total = 0 for _ in pairs(table_) do total = total + 1 end return total end

-- Notes that `spellID` opened the window of `skillLineID` (own: skill line -> { [spellID] = true }). True when new.
---@param own table
---@param skillLineID any
---@param spellID any
---@return boolean
function ProfessionSpells.Note(own, skillLineID, spellID)
    if type(own) ~= "table" or not isID(skillLineID) or not isID(spellID) then return false end
    local spells = own[skillLineID]
    if spells == nil then
        if count(own) >= ProfessionSpells.MAXIMUM_SKILL_LINES then return false end
        spells = {}; own[skillLineID] = spells
    end
    if spells[spellID] or count(spells) >= ProfessionSpells.MAXIMUM_SPELLS_PER_SKILL_LINE then return false end
    spells[spellID] = true
    return true
end

-- The HELLO field: "skillLine:spellID" pairs, sorted, comma separated; nil when there is nothing to report.
---@param own table|nil
---@return string|nil
function ProfessionSpells.Encode(own)
    local pairsText = {}
    for skillLineID, spells in pairs(type(own) == "table" and own or {}) do
        if isID(skillLineID) and type(spells) == "table" then
            for spellID in pairs(spells) do
                if isID(spellID) then pairsText[#pairsText + 1] = skillLineID .. ":" .. spellID end
            end
        end
    end
    if #pairsText == 0 then return nil end
    table.sort(pairsText)
    local text = table.concat(pairsText, ",")
    while #text > ProfessionSpells.MAXIMUM_WIRE_LENGTH and #pairsText > 1 do
        pairsText[#pairsText] = nil
        text = table.concat(pairsText, ",")
    end
    return text
end

-- A peer's HELLO field as { { skillLine, spellID }, ... }, or nil when it is not a short list of number pairs.
---@param value any
---@return { [1]: integer, [2]: integer }[]|nil
function ProfessionSpells.Decode(value)
    if type(value) ~= "string" or value == "" or #value > ProfessionSpells.MAXIMUM_WIRE_LENGTH then return nil end
    if not value:match("^[%d:,]+$") then return nil end
    local decoded = {}
    for skillLineText, spellText in value:gmatch("(%d+):(%d+)") do
        local skillLineID, spellID = tonumber(skillLineText), tonumber(spellText)
        if not isID(skillLineID) or not isID(spellID) then return nil end
        decoded[#decoded + 1] = { skillLineID, spellID }
        if #decoded >= ProfessionSpells.MAXIMUM_SKILL_LINES * ProfessionSpells.MAXIMUM_SPELLS_PER_SKILL_LINE then break end
    end
    return #decoded > 0 and decoded or nil
end

-- Adds a peer's pairs to the developer's collection: reports[skillLine][spellID] = { by = { [name] = true }, at }.
-- True when something new was added.
---@param reports table
---@param decoded { [1]: integer, [2]: integer }[]
---@param sender string
---@param now integer
---@return boolean
function ProfessionSpells.AddReport(reports, decoded, sender, now)
    if type(reports) ~= "table" or type(sender) ~= "string" then return false end
    local changed = false
    for _, pair in ipairs(decoded or {}) do
        local skillLineID, spellID = pair[1], pair[2]
        local spells = reports[skillLineID]
        if spells == nil and count(reports) < 64 then spells = {}; reports[skillLineID] = spells end
        if spells and (spells[spellID] or count(spells) < 16) then
            local entry = spells[spellID]
            if entry == nil then entry = { by = {} }; spells[spellID] = entry; changed = true end
            if not entry.by[sender] and count(entry.by) < ProfessionSpells.MAXIMUM_REPORTERS then entry.by[sender] = true; changed = true end
            entry.at = now
        end
    end
    return changed
end

---@class WindowSpellReportRow
---@field skillLine integer
---@field spellID integer
---@field reporters integer
---@field static "same"|"other"|"new" same as WINDOW, WINDOW has another id, or WINDOW has none for this skill line

-- The collection as rows sorted by skill line and spell id, each compared with WINDOW.
---@param reports table|nil
---@return WindowSpellReportRow[]
function ProfessionSpells.ReportRows(reports)
    local rows = {}
    for skillLineID, spells in pairs(type(reports) == "table" and reports or {}) do
        for spellID, entry in pairs(type(spells) == "table" and spells or {}) do
            local staticID = ProfessionSpells.WINDOW[skillLineID]
            rows[#rows + 1] = { skillLine = skillLineID, spellID = spellID, reporters = count(type(entry) == "table" and entry.by or {}),
                static = staticID == spellID and "same" or (staticID and "other" or "new") }
        end
    end
    table.sort(rows, function(left, right)
        if left.skillLine ~= right.skillLine then return left.skillLine < right.skillLine end
        return left.spellID < right.spellID
    end)
    return rows
end
