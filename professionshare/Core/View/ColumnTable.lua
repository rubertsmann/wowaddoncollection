local addonName, addon = ...

-- A table definition: which columns exist and which are shown, where each column sits for a given width, and how rows
-- are sorted. Pure (no frames). The Recipes tab and every mode of the Misc Items tab are one definition each.
-- Settings live in the SavedVariables `ui` table under the definition's own keys (local to this account, never sent):
-- every read is validated and falls back to the default, so a corrupted or future value can never break the window.
---@class ColumnTableModule
local ColumnTable = {}
addon.ColumnTable = ColumnTable

---@class TableColumn
---@field key string
---@field width number|nil fixed width; nil = takes the rest (the name column)
---@field numeric boolean sorts as a number (highest first on the first click)
---@field justify "LEFT"|"RIGHT"
---@field field string the row field the column shows and sorts by
---@field label fun(): string the column title in the viewer's language
---@field hidden? boolean hidden until the player turns it on

---@class TableSort
---@field key string
---@field descending boolean

---@class TableCell
---@field key string
---@field left number
---@field width number
---@field column TableColumn

---@class ColumnTableDefinition
---@field columns TableColumn[] display order; the first column without a width is the name column and always shown
---@field columnsSetting string ui key of the shown-columns map
---@field sortSetting string ui key of the sort
---@field defaultSort TableSort
---@field idField string tie-breaker after the name
---@field nameMinimumWidth? number
---@field columnGap? number

---@param text any
---@return string
local function sortKey(text) return addon.Utility.SearchKey(type(text) == "string" and text or "") end

-- A table object with the definition's columns and settings keys. Its functions take the SavedVariables ui table.
---@param definition ColumnTableDefinition
---@return table
function ColumnTable.New(definition)
    local columnTable = {
        COLUMNS = definition.columns,
        NAME_MINIMUM_WIDTH = definition.nameMinimumWidth or 140,
        COLUMN_GAP = definition.columnGap or 8,
        DEFAULT_SORT = definition.defaultSort,
        OPTIONAL_KEYS = {},
    }
    local columnByKey, nameKey = {}, nil
    for _, column in ipairs(definition.columns) do
        columnByKey[column.key] = column
        if column.width == nil and not nameKey then nameKey = column.key
        else columnTable.OPTIONAL_KEYS[#columnTable.OPTIONAL_KEYS + 1] = column.key end
    end
    columnTable.NAME_KEY = nameKey

    ---@param columnKey any
    ---@return TableColumn|nil
    function columnTable.Column(columnKey) return columnByKey[columnKey] end

    -- column title in the viewer's language
    ---@param columnKey string
    ---@return string
    function columnTable.ColumnLabel(columnKey)
        local column = columnByKey[columnKey]
        return column and column.label() or tostring(columnKey)
    end

    ---@param interfaceSettings table|nil
    ---@param columnKey string
    ---@return boolean
    function columnTable.ColumnShown(interfaceSettings, columnKey)
        if columnKey == nameKey then return true end
        local column = columnByKey[columnKey]
        if not column then return false end
        local storedColumns = type(interfaceSettings) == "table" and type(interfaceSettings[definition.columnsSetting]) == "table"
            and interfaceSettings[definition.columnsSetting] or nil
        local storedValue = storedColumns and storedColumns[columnKey]
        if type(storedValue) ~= "boolean" then return not column.hidden end
        return storedValue
    end

    ---@param interfaceSettings table|nil
    ---@param columnKey string
    ---@param shown boolean
    function columnTable.SetColumn(interfaceSettings, columnKey, shown)
        if type(interfaceSettings) ~= "table" or columnKey == nameKey or not columnByKey[columnKey] then return end
        local settingKey = definition.columnsSetting
        interfaceSettings[settingKey] = type(interfaceSettings[settingKey]) == "table" and interfaceSettings[settingKey] or {}
        interfaceSettings[settingKey][columnKey] = shown and true or false
    end

    ---@param interfaceSettings table|nil
    ---@return TableColumn[] the shown columns in display order
    function columnTable.VisibleColumns(interfaceSettings)
        local visibleColumns = {}
        for _, column in ipairs(definition.columns) do
            if columnTable.ColumnShown(interfaceSettings, column.key) then visibleColumns[#visibleColumns + 1] = column end
        end
        return visibleColumns
    end

    ---@param interfaceSettings table|nil
    ---@return TableSort a copy; changing it does not change the setting
    function columnTable.GetSort(interfaceSettings)
        local storedSort = type(interfaceSettings) == "table" and type(interfaceSettings[definition.sortSetting]) == "table"
            and interfaceSettings[definition.sortSetting] or nil
        if not storedSort or not columnByKey[storedSort.key] or type(storedSort.descending) ~= "boolean" then
            return { key = definition.defaultSort.key, descending = definition.defaultSort.descending }
        end
        return { key = storedSort.key, descending = storedSort.descending }
    end

    ---@param interfaceSettings table|nil
    ---@param columnKey string
    ---@param descending boolean
    function columnTable.SetSort(interfaceSettings, columnKey, descending)
        if type(interfaceSettings) ~= "table" or not columnByKey[columnKey] then return end
        interfaceSettings[definition.sortSetting] = { key = columnKey, descending = descending and true or false }
    end

    -- a header click: another column sorts by it (numbers highest first, text A-Z), the same column flips the direction
    ---@param interfaceSettings table|nil
    ---@param columnKey string
    function columnTable.ClickHeader(interfaceSettings, columnKey)
        local column = columnByKey[columnKey]
        if not column then return end
        local currentSort = columnTable.GetSort(interfaceSettings)
        if currentSort.key == columnKey then columnTable.SetSort(interfaceSettings, columnKey, not currentSort.descending)
        else columnTable.SetSort(interfaceSettings, columnKey, column.numeric) end
    end

    -- the sortable keys in the order the options panel cycles through them
    ---@return string[]
    function columnTable.SortKeys()
        local sortKeys = {}
        for _, column in ipairs(definition.columns) do sortKeys[#sortKeys + 1] = column.key end
        return sortKeys
    end

    -- Fixed columns keep their width; the name column takes what is left (at least NAME_MINIMUM_WIDTH, so a narrow table
    -- overflows to the right instead of squeezing the name away). Hidden columns take no space.
    ---@param visibleColumns TableColumn[]
    ---@param totalWidth number
    ---@return TableCell[]
    function columnTable.Layout(visibleColumns, totalWidth)
        local gap = columnTable.COLUMN_GAP
        local fixedWidth = 0
        for _, column in ipairs(visibleColumns) do
            if column.width then fixedWidth = fixedWidth + column.width + gap end
        end
        local nameWidth = math.max(columnTable.NAME_MINIMUM_WIDTH, totalWidth - fixedWidth)
        local cells, left = {}, 0
        for _, column in ipairs(visibleColumns) do
            local width = column.width or nameWidth
            if column.width then left = left + gap end
            cells[#cells + 1] = { key = column.key, left = left, width = width, column = column }
            left = left + width
        end
        return cells
    end

    -- The width the cells of Layout span (the right edge of the last one; 0 for none). More than the width the layout
    -- was given when the name hit its minimum: the window then scrolls the table sideways.
    ---@param cells TableCell[]
    ---@return number
    function columnTable.TableWidth(cells)
        local right = 0
        for _, cell in ipairs(cells or {}) do right = math.max(right, cell.left + cell.width) end
        return right
    end

    -- In place. Missing values (no item, item not cached yet) always go last, in either direction; ties by name, then id.
    ---@param rows table[]
    ---@param sort TableSort
    ---@return table[] the same table
    function columnTable.Sort(rows, sort)
        local column = columnByKey[sort and sort.key] or columnByKey[definition.defaultSort.key]
        local descending = sort and sort.descending
        local field, idField, nameField = column.field, definition.idField, columnByKey[nameKey].field
        local function value(row)
            local fieldValue = row[field]
            if column.numeric then return type(fieldValue) == "number" and fieldValue or nil end
            if type(fieldValue) ~= "string" or fieldValue == "" then return nil end
            return sortKey(fieldValue)
        end
        local function byNameThenID(left, right)
            local leftName, rightName = sortKey(left[nameField]), sortKey(right[nameField])
            if leftName ~= rightName then return leftName < rightName end
            local leftID, rightID = left[idField], right[idField]
            if type(leftID) == "number" and type(rightID) == "number" then return leftID < rightID end
            return tostring(leftID) < tostring(rightID)
        end
        table.sort(rows, function(left, right)
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
        return rows
    end

    return columnTable
end
