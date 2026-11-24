local addonName, addon = ...

-- The Misc Items tab: its modes (Recipe items, Keys, Attunements, Reputation, Cooldowns) and one column table per table mode
-- (ColumnTable); the Cooldowns mode is a grid (UI/CooldownGrid.lua), not a table. Pure.
-- Shown columns, sort and the chosen mode are kept in the SavedVariables `ui` table (local, never sent), one settings
-- key per mode, so each mode remembers its own column choice.
---@class MiscTablesModule
local MiscTables = {}
addon.MiscTables = MiscTables

local Text = addon.Text
local ColumnTable = addon.ColumnTable

---@alias MiscMode "offers"|"keys"|"attunements"|"reputation"|"cooldowns"

---@type MiscMode[] dropdown order
MiscTables.MODES = { "offers", "keys", "attunements", "reputation", "cooldowns" }
MiscTables.DEFAULT_MODE = "offers"

---@param mode MiscMode
---@return string the mode name in the viewer's language
function MiscTables.ModeLabel(mode)
    if mode == "keys" then return Text["Keys"] end
    if mode == "attunements" then return Text["Attunements"] end
    if mode == "reputation" then return Text["Reputation"] end
    if mode == "cooldowns" then return Text["Cooldowns"] end
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
    -- one row per member and faction; Standing sorts by level, then progress inside it
    reputation = ColumnTable.New({
        columns = {
            { key = "name", width = nil, numeric = false, justify = "LEFT", field = "name", label = function() return Text["Faction"] end },
            { key = "player", width = 120, numeric = false, justify = "LEFT", field = "playerName", label = function() return Text["Player"] end },
            { key = "standing", width = 110, numeric = true, justify = "LEFT", field = "standingRank",
                label = function() return Text["Standing"] end },
            { key = "progress", width = 100, numeric = true, justify = "RIGHT", field = "progress",
                label = function() return Text["Progress"] end },
            { key = "updated", width = 90, numeric = true, justify = "RIGHT", field = "updated",
                label = function() return Text["Updated"] end, hidden = true },
        },
        columnsSetting = "reputationColumns", sortSetting = "reputationSort",
        defaultSort = { key = "standing", descending = true }, idField = "key",
    }),
}

-- whether the mode shows a grid instead of a table
---@param mode any
---@return boolean
function MiscTables.IsGrid(mode) return mode == "cooldowns" end

---@param interfaceSettings table|nil
---@return MiscMode
function MiscTables.GetMode(interfaceSettings)
    local storedMode = type(interfaceSettings) == "table" and interfaceSettings.miscMode or nil
    if MiscTables.tables[storedMode] or MiscTables.IsGrid(storedMode) then return storedMode end
    return MiscTables.DEFAULT_MODE
end

---@param interfaceSettings table|nil
---@param mode any
function MiscTables.SetMode(interfaceSettings, mode)
    if type(interfaceSettings) ~= "table" or not (MiscTables.tables[mode] or MiscTables.IsGrid(mode)) then return end
    interfaceSettings.miscMode = mode
end

---@param mode MiscMode
---@return table the column table of that mode (grid modes: the default mode's, never shown)
function MiscTables.Table(mode) return MiscTables.tables[mode] or MiscTables.tables[MiscTables.DEFAULT_MODE] end
