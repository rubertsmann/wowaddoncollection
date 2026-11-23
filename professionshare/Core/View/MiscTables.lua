local addonName, addon = ...

-- The Misc Items tab: its modes (Recipe items, Keys, Attunements) and one column table per mode (ColumnTable). Pure.
-- Shown columns, sort and the chosen mode are kept in the SavedVariables `ui` table (local, never sent), one settings
-- key per mode, so each mode remembers its own column choice.
---@class MiscTablesModule
local MiscTables = {}
addon.MiscTables = MiscTables

local Text = addon.Text
local ColumnTable = addon.ColumnTable

---@alias MiscMode "offers"|"keys"|"attunements"

---@type MiscMode[] dropdown order
MiscTables.MODES = { "offers", "keys", "attunements" }
MiscTables.DEFAULT_MODE = "offers"

---@param mode MiscMode
---@return string the mode name in the viewer's language
function MiscTables.ModeLabel(mode)
    if mode == "keys" then return Text["Keys"] end
    if mode == "attunements" then return Text["Attunements"] end
    return Text["Recipe items"]
end

---@type table<MiscMode, table>
MiscTables.tables = {
    offers = ColumnTable.New({
        columns = {
            { key = "name", width = nil, numeric = false, justify = "LEFT", field = "name", label = function() return Text["Name"] end },
            { key = "profession", width = 110, numeric = false, justify = "LEFT", field = "profession",
                label = function() return Text["Profession"] end },
            { key = "owner", width = 110, numeric = false, justify = "LEFT", field = "ownerName", label = function() return Text["Owner"] end },
            { key = "locations", width = 170, numeric = false, justify = "LEFT", field = "locations",
                label = function() return Text["Where"] end },
            { key = "total", width = 44, numeric = true, justify = "RIGHT", field = "total", label = function() return Text["Count"] end },
            { key = "dibs", width = 70, numeric = true, justify = "RIGHT", field = "dibCount", label = function() return Text["# Dibs"] end },
        },
        columnsSetting = "offerColumns", sortSetting = "offerSort",
        defaultSort = { key = "profession", descending = false }, idField = "key",
    }),
    keys = ColumnTable.New({
        columns = {
            { key = "name", width = nil, numeric = false, justify = "LEFT", field = "name", label = function() return Text["Key"] end },
            { key = "instance", width = 150, numeric = false, justify = "LEFT", field = "instance", label = function() return Text["Opens"] end },
            { key = "holderCount", width = 60, numeric = true, justify = "RIGHT", field = "holderCount",
                label = function() return Text["Holders"] end },
            { key = "holderNames", width = 260, numeric = false, justify = "LEFT", field = "holderNames",
                label = function() return Text["Who has it"] end },
        },
        columnsSetting = "keyColumns", sortSetting = "keySort",
        defaultSort = { key = "instance", descending = false }, idField = "itemID",
    }),
    attunements = ColumnTable.New({
        columns = {
            { key = "name", width = nil, numeric = false, justify = "LEFT", field = "name", label = function() return Text["Raid"] end },
            { key = "attunedCount", width = 60, numeric = true, justify = "RIGHT", field = "attunedCount",
                label = function() return Text["Attuned"] end },
            { key = "attuned", width = 240, numeric = false, justify = "LEFT", field = "attuned", label = function() return Text["Who"] end },
            { key = "missingCount", width = 60, numeric = true, justify = "RIGHT", field = "missingCount",
                label = function() return Text["Missing"] end, hidden = true },
            { key = "missing", width = 200, numeric = false, justify = "LEFT", field = "missing",
                label = function() return Text["Not attuned yet"] end },
        },
        columnsSetting = "attunementColumns", sortSetting = "attunementSort",
        defaultSort = { key = "attunedCount", descending = true }, idField = "key",
    }),
}

---@param interfaceSettings table|nil
---@return MiscMode
function MiscTables.GetMode(interfaceSettings)
    local storedMode = type(interfaceSettings) == "table" and interfaceSettings.miscMode or nil
    if MiscTables.tables[storedMode] then return storedMode end
    return MiscTables.DEFAULT_MODE
end

---@param interfaceSettings table|nil
---@param mode any
function MiscTables.SetMode(interfaceSettings, mode)
    if type(interfaceSettings) ~= "table" or not MiscTables.tables[mode] then return end
    interfaceSettings.miscMode = mode
end

---@param mode MiscMode
---@return table the column table of that mode
function MiscTables.Table(mode) return MiscTables.tables[mode] or MiscTables.tables[MiscTables.DEFAULT_MODE] end
