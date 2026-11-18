local addonName, addon = ...

-- Feature 016: the Recipes tab as a table. Pure (no frames): which columns exist and which are shown, where each column
-- sits for a given width, how rows are sorted, the item-quality colour of a name and the saved window size.
-- Settings live in the SavedVariables `ui` table (local to this account, never sent): every read is validated and falls
-- back to the default, so a corrupted or future value can never break the window.
---@class RecipeTableModule
local RecipeTable = {}
addon.RecipeTable = RecipeTable

local Text = addon.Text

---@alias RecipeColumnKey "name"|"itemLevel"|"requiredLevel"|"profession"|"skill"|"category"

---@class RecipeColumn
---@field key RecipeColumnKey
---@field width number|nil fixed width; nil = takes the rest (name)
---@field numeric boolean sorts as a number (highest first on the first click)
---@field justify "LEFT"|"RIGHT"
---@field field string the RecipeRow field the column shows and sorts by

-- display order; "name" is always shown, the others are optional
---@type RecipeColumn[]
RecipeTable.COLUMNS = {
    { key = "name", width = nil, numeric = false, justify = "LEFT", field = "name" },
    { key = "itemLevel", width = 58, numeric = true, justify = "RIGHT", field = "itemLevel" },
    { key = "requiredLevel", width = 58, numeric = true, justify = "RIGHT", field = "requiredLevel" },
    { key = "profession", width = 104, numeric = false, justify = "LEFT", field = "profession" },
    { key = "skill", width = 44, numeric = true, justify = "RIGHT", field = "skill" },
    { key = "category", width = 104, numeric = false, justify = "LEFT", field = "categoryLabel" },
}
---@type RecipeColumnKey[]
RecipeTable.OPTIONAL_KEYS = { "itemLevel", "requiredLevel", "profession", "skill", "category" }
RecipeTable.NAME_MINIMUM_WIDTH = 140
RecipeTable.COLUMN_GAP = 8
RecipeTable.DEFAULT_SORT = { key = "itemLevel", descending = true }
RecipeTable.MINIMUM_WIDTH, RecipeTable.MINIMUM_HEIGHT = 780, 520

---@type table<string, RecipeColumn>
local columnByKey = {}
for _, column in ipairs(RecipeTable.COLUMNS) do columnByKey[column.key] = column end

---@param columnKey any
---@return RecipeColumn|nil
function RecipeTable.Column(columnKey) return columnByKey[columnKey] end

-- column title in the viewer's language
---@param columnKey RecipeColumnKey
---@return string
function RecipeTable.ColumnLabel(columnKey)
    local labels = { name = Text["Name"], itemLevel = Text["Item level"], requiredLevel = Text["Req. level"],
        profession = Text["Profession"], skill = Text["Skill"], category = Text["Category"] }
    return labels[columnKey] or tostring(columnKey)
end

------------------------------------------------------------------ settings

---@param interfaceSettings table|nil the SavedVariables ui table
---@param columnKey string
---@return boolean
function RecipeTable.ColumnShown(interfaceSettings, columnKey)
    if columnKey == "name" then return true end
    if not columnByKey[columnKey] then return false end
    local storedColumns = type(interfaceSettings) == "table" and type(interfaceSettings.recipeColumns) == "table"
        and interfaceSettings.recipeColumns or nil
    local storedValue = storedColumns and storedColumns[columnKey]
    if type(storedValue) ~= "boolean" then return true end   -- default: on
    return storedValue
end

---@param interfaceSettings table|nil
---@param columnKey string
---@param shown boolean
function RecipeTable.SetColumn(interfaceSettings, columnKey, shown)
    if type(interfaceSettings) ~= "table" or columnKey == "name" or not columnByKey[columnKey] then return end
    interfaceSettings.recipeColumns = type(interfaceSettings.recipeColumns) == "table" and interfaceSettings.recipeColumns or {}
    interfaceSettings.recipeColumns[columnKey] = shown and true or false
end

---@param interfaceSettings table|nil
---@return RecipeColumn[] the shown columns in display order
function RecipeTable.VisibleColumns(interfaceSettings)
    local visibleColumns = {}
    for _, column in ipairs(RecipeTable.COLUMNS) do
        if RecipeTable.ColumnShown(interfaceSettings, column.key) then visibleColumns[#visibleColumns + 1] = column end
    end
    return visibleColumns
end

---@class RecipeSort
---@field key RecipeColumnKey
---@field descending boolean

---@param interfaceSettings table|nil
---@return RecipeSort a copy; changing it does not change the setting
function RecipeTable.GetSort(interfaceSettings)
    local storedSort = type(interfaceSettings) == "table" and type(interfaceSettings.recipeSort) == "table"
        and interfaceSettings.recipeSort or nil
    if not storedSort or not columnByKey[storedSort.key] or type(storedSort.descending) ~= "boolean" then
        return { key = RecipeTable.DEFAULT_SORT.key, descending = RecipeTable.DEFAULT_SORT.descending }
    end
    return { key = storedSort.key, descending = storedSort.descending }
end

---@param interfaceSettings table|nil
---@param columnKey string
---@param descending boolean
function RecipeTable.SetSort(interfaceSettings, columnKey, descending)
    if type(interfaceSettings) ~= "table" or not columnByKey[columnKey] then return end
    interfaceSettings.recipeSort = { key = columnKey, descending = descending and true or false }
end

-- a header click: another column sorts by it (numbers highest first, text A-Z), the same column flips the direction
---@param interfaceSettings table|nil
---@param columnKey string
function RecipeTable.ClickHeader(interfaceSettings, columnKey)
    local column = columnByKey[columnKey]
    if not column then return end
    local currentSort = RecipeTable.GetSort(interfaceSettings)
    if currentSort.key == columnKey then RecipeTable.SetSort(interfaceSettings, columnKey, not currentSort.descending)
    else RecipeTable.SetSort(interfaceSettings, columnKey, column.numeric) end
end

-- the sortable keys in the order the options panel cycles through them
---@return RecipeColumnKey[]
function RecipeTable.SortKeys()
    local sortKeys = {}
    for _, column in ipairs(RecipeTable.COLUMNS) do sortKeys[#sortKeys + 1] = column.key end
    return sortKeys
end

------------------------------------------------------------------ window size

---@param value any
---@return boolean
local function isSize(value) return type(value) == "number" and value == value and value > 0 and value < 100000 end

-- the saved window size clamped to [minimum, screen]; nil when nothing (valid) is saved
---@param interfaceSettings table|nil
---@param screenWidth number
---@param screenHeight number
---@return number|nil width
---@return number|nil height
function RecipeTable.WindowSize(interfaceSettings, screenWidth, screenHeight)
    local storedSize = type(interfaceSettings) == "table" and type(interfaceSettings.windowSize) == "table"
        and interfaceSettings.windowSize or nil
    if not storedSize or not isSize(storedSize.width) or not isSize(storedSize.height) then return nil end
    local function clamp(value, minimum, maximum)
        value = math.floor(value + 0.5)
        if maximum and maximum >= minimum and value > maximum then value = maximum end
        return math.max(minimum, value)
    end
    return clamp(storedSize.width, RecipeTable.MINIMUM_WIDTH, screenWidth),
        clamp(storedSize.height, RecipeTable.MINIMUM_HEIGHT, screenHeight)
end

---@param interfaceSettings table|nil
---@param width number
---@param height number
function RecipeTable.SetWindowSize(interfaceSettings, width, height)
    if type(interfaceSettings) ~= "table" or not isSize(width) or not isSize(height) then return end
    interfaceSettings.windowSize = { width = width, height = height }
end

------------------------------------------------------------------ layout, sort, colour

---@class RecipeCell
---@field key RecipeColumnKey
---@field left number
---@field width number
---@field column RecipeColumn

-- Fixed columns keep their width; name takes what is left (at least NAME_MINIMUM_WIDTH, so a narrow table overflows to
-- the right instead of squeezing the name away). Hidden columns take no space.
---@param visibleColumns RecipeColumn[]
---@param totalWidth number
---@return RecipeCell[]
function RecipeTable.Layout(visibleColumns, totalWidth)
    local fixedWidth = 0
    for _, column in ipairs(visibleColumns) do
        if column.width then fixedWidth = fixedWidth + column.width + RecipeTable.COLUMN_GAP end
    end
    local nameWidth = math.max(RecipeTable.NAME_MINIMUM_WIDTH, totalWidth - fixedWidth)
    local cells, left = {}, 0
    for _, column in ipairs(visibleColumns) do
        local width = column.width or nameWidth
        if column.width then left = left + RecipeTable.COLUMN_GAP end
        cells[#cells + 1] = { key = column.key, left = left, width = width, column = column }
        left = left + width
    end
    return cells
end

---@param text any
---@return string
local function sortKey(text) return addon.Utility.SearchKey(type(text) == "string" and text or "") end

-- In place. Missing values (no item, item not cached yet) always go last, in either direction; ties by name, then id.
---@param recipeRows RecipeRow[]
---@param sort RecipeSort
---@return RecipeRow[] the same table
function RecipeTable.Sort(recipeRows, sort)
    local column = columnByKey[sort and sort.key] or columnByKey[RecipeTable.DEFAULT_SORT.key]
    local descending = sort and sort.descending
    local field = column.field
    local function value(recipeRow)
        local fieldValue = recipeRow[field]
        if column.numeric then return type(fieldValue) == "number" and fieldValue or nil end
        if type(fieldValue) ~= "string" or fieldValue == "" then return nil end
        return sortKey(fieldValue)
    end
    local function byNameThenID(left, right)
        local leftName, rightName = sortKey(left.name), sortKey(right.name)
        if leftName ~= rightName then return leftName < rightName end
        return left.recipeID < right.recipeID
    end
    table.sort(recipeRows, function(left, right)
        local leftValue, rightValue = value(left), value(right)
        if leftValue == nil and rightValue == nil then return byNameThenID(left, right) end
        if leftValue == nil then return false end
        if rightValue == nil then return true end
        if leftValue ~= rightValue then
            if descending then return leftValue > rightValue end
            return leftValue < rightValue
        end
        return byNameThenID(left, right)
    end)
    return recipeRows
end

-- the usual item quality colours (poor .. heirloom), used when the client offers none
---@type table<integer, string>
local QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
    [6] = "e6cc80", [7] = "00ccff" }

---@param quality any
---@return string|nil "rrggbb"
function RecipeTable.QualityHex(quality) return QUALITY_HEX[quality] end

-- `text` must already be escaped (Model); the colour code wraps it
---@param text string
---@param hex string|nil
---@return string
function RecipeTable.Coloured(text, hex)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then return text end
    return "|cff" .. hex .. text .. "|r"
end
