local addonName, addon = ...

-- The Recipes tab as a table. Pure (no frames): its column definition (ColumnTable), the item-quality colour of a
-- name and the saved window size.
-- Settings live in the SavedVariables `ui` table (local to this account, never sent): every read is validated and falls
-- back to the default, so a corrupted or future value can never break the window.
---@class RecipeTableModule
local RecipeTable = {}
addon.RecipeTable = RecipeTable

local Text = addon.Text

---@alias RecipeColumnKey "name"|"itemLevel"|"requiredLevel"|"profession"|"skill"|"category"
---@alias RecipeColumn TableColumn
---@alias RecipeSort TableSort
---@alias RecipeCell TableCell

-- columns, settings, layout and sort come from ColumnTable; "name" is always shown, the others are optional
do
    local definition = addon.ColumnTable.New({
        columns = {
            { key = "name", width = nil, numeric = false, justify = "LEFT", field = "name", label = function() return Text["Name"] end },
            { key = "itemLevel", width = 58, numeric = true, justify = "RIGHT", field = "itemLevel", label = function() return Text["Item level"] end },
            { key = "requiredLevel", width = 58, numeric = true, justify = "RIGHT", field = "requiredLevel", label = function() return Text["Req. level"] end },
            { key = "profession", width = 104, numeric = false, justify = "LEFT", field = "profession", label = function() return Text["Profession"] end },
            { key = "skill", width = 44, numeric = true, justify = "RIGHT", field = "skill", label = function() return Text["Skill"] end },
            { key = "category", width = 104, numeric = false, justify = "LEFT", field = "categoryLabel", label = function() return Text["Category"] end },
        },
        columnsSetting = "recipeColumns", sortSetting = "recipeSort",
        defaultSort = { key = "itemLevel", descending = true }, idField = "recipeID",
    })
    for fieldName, value in pairs(definition) do RecipeTable[fieldName] = value end
end
RecipeTable.MINIMUM_WIDTH, RecipeTable.MINIMUM_HEIGHT = 780, 520

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

------------------------------------------------------------------ colour

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
