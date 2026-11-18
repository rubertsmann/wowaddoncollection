-- Feature 016: Recipes table columns, sort, quality colour, window size (Core/View/RecipeTable.lua) and the item
-- details BuildRecipeRows adds (Core/View/Model.lua).

local function keys(columns)
    local out = {}
    for _, column in ipairs(columns) do out[#out + 1] = column.key end
    return table.concat(out, ",")
end

local function recipeNames(rows)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = row.name end
    return table.concat(out, ",")
end

-- item id -> quality, item level, required level (nil = not cached / no item)
local DETAILS = { [101] = { 2, 20, 15 }, [102] = { 3, 35, 30 }, [103] = { 1, 5, nil }, [104] = { 4, 35, 33 } }
local function itemDetails(itemID)
    local details = DETAILS[itemID]
    if details then return details[1], details[2], details[3] end
end

local function setup(harness)
    local addon = harness.addon()
    addon.Store.PutCharacter(harness.character("A-R", 1, { 1, 2, 3, 4, 5, 6 }))
    addon.Store.PutCatalog({
        [1] = { name = "Green", produces = 101, minSkill = 50, reagents = {} },
        [2] = { name = "Blue", produces = 102, minSkill = 150, reagents = {} },
        [3] = { name = "White", produces = 103, reagents = {} },
        [4] = { name = "Purple", produces = 104, minSkill = 200, reagents = {} },
        [5] = { name = "Enchant", reagents = {} },                  -- no item
        [6] = { name = "Uncached", produces = 999, reagents = {} }, -- item data not loaded yet
    })
    return addon
end

local function rows(addon)
    return addon.Model.BuildRecipeRows(addon.Store, { text = "" }, nil, { itemDetails = itemDetails })
end

return {
    ["recipe table: defaults are all columns on and item level, highest first"] = function(harness)
        local RecipeTable = harness.addon().RecipeTable
        harness.equal(keys(RecipeTable.VisibleColumns(nil)), "name,itemLevel,requiredLevel,profession,skill,category")
        local sort = RecipeTable.GetSort({})
        harness.equal(sort.key, "itemLevel"); harness.equal(sort.descending, true)
    end,

    ["recipe table: switching columns off hides them, name always stays"] = function(harness)
        local RecipeTable = harness.addon().RecipeTable
        local ui = {}
        RecipeTable.SetColumn(ui, "skill", false)
        RecipeTable.SetColumn(ui, "profession", false)
        RecipeTable.SetColumn(ui, "name", false)      -- not optional: ignored
        harness.equal(keys(RecipeTable.VisibleColumns(ui)), "name,itemLevel,requiredLevel,category")
        harness.equal(RecipeTable.ColumnShown(ui, "skill"), false)
        RecipeTable.SetColumn(ui, "skill", true)
        harness.equal(keys(RecipeTable.VisibleColumns(ui)), "name,itemLevel,requiredLevel,skill,category")
    end,

    ["recipe table: corrupted or unknown saved settings fall back to defaults (RF2)"] = function(harness)
        local RecipeTable = harness.addon().RecipeTable
        local ui = { recipeColumns = "x", recipeSort = { key = "foo", descending = "yes" }, windowSize = { width = 1e9, height = "tall" } }
        harness.equal(keys(RecipeTable.VisibleColumns(ui)), "name,itemLevel,requiredLevel,profession,skill,category")
        local sort = RecipeTable.GetSort(ui)
        harness.equal(sort.key, "itemLevel"); harness.equal(sort.descending, true)
        harness.equal(RecipeTable.WindowSize(ui, 1920, 1080), nil)
        ui.recipeColumns = { itemLevel = "no", category = false, bogus = false }
        harness.equal(keys(RecipeTable.VisibleColumns(ui)), "name,itemLevel,requiredLevel,profession,skill")
        RecipeTable.SetSort(ui, "bogus", false)   -- refused
        harness.equal(RecipeTable.GetSort(ui).key, "itemLevel")
    end,

    ["recipe table: header click picks a column, a second click flips the direction"] = function(harness)
        local RecipeTable = harness.addon().RecipeTable
        local ui = {}
        RecipeTable.ClickHeader(ui, "name")
        harness.equal(RecipeTable.GetSort(ui).key, "name"); harness.equal(RecipeTable.GetSort(ui).descending, false)   -- text: A-Z first
        RecipeTable.ClickHeader(ui, "name")
        harness.equal(RecipeTable.GetSort(ui).descending, true)
        RecipeTable.ClickHeader(ui, "requiredLevel")
        harness.equal(RecipeTable.GetSort(ui).key, "requiredLevel"); harness.equal(RecipeTable.GetSort(ui).descending, true)   -- numbers: highest first
    end,

    ["recipe table: layout gives name the rest, hidden columns leave no gap, name keeps its minimum (RF3)"] = function(harness)
        local RecipeTable = harness.addon().RecipeTable
        local ui = {}
        local layout = RecipeTable.Layout(RecipeTable.VisibleColumns(ui), 700)
        harness.equal(layout[1].key, "name"); harness.equal(layout[1].left, 0)
        local right = 0
        for _, cell in ipairs(layout) do
            harness.truthy(cell.left >= right, "cells do not overlap")
            right = cell.left + cell.width
        end
        harness.equal(right, 700, "the last column ends at the table width")
        for _, key in ipairs(RecipeTable.OPTIONAL_KEYS) do RecipeTable.SetColumn(ui, key, false) end
        layout = RecipeTable.Layout(RecipeTable.VisibleColumns(ui), 500)
        harness.equal(#layout, 1); harness.equal(layout[1].width, 500)
        for _, key in ipairs(RecipeTable.OPTIONAL_KEYS) do RecipeTable.SetColumn(ui, key, true) end
        layout = RecipeTable.Layout(RecipeTable.VisibleColumns(ui), 100)
        harness.equal(layout[1].width, RecipeTable.NAME_MINIMUM_WIDTH)
    end,

    ["recipe table: quality colours, unknown quality gives no colour"] = function(harness)
        local RecipeTable = harness.addon().RecipeTable
        harness.equal(RecipeTable.QualityHex(0), "9d9d9d")
        harness.equal(RecipeTable.QualityHex(4), "a335ee")
        harness.equal(RecipeTable.QualityHex(nil), nil)
        harness.equal(RecipeTable.QualityHex(42), nil)
        harness.equal(RecipeTable.Coloured("Robe", "1eff00"), "|cff1eff00Robe|r")
        harness.equal(RecipeTable.Coloured("Robe", nil), "Robe")
    end,

    ["recipe table: window size is clamped between the minimum and the screen"] = function(harness)
        local RecipeTable = harness.addon().RecipeTable
        local ui = {}
        harness.equal(RecipeTable.WindowSize(ui, 1920, 1080), nil, "nothing saved yet")
        RecipeTable.SetWindowSize(ui, 400, 300)
        local width, height = RecipeTable.WindowSize(ui, 1920, 1080)
        harness.equal(width, RecipeTable.MINIMUM_WIDTH); harness.equal(height, RecipeTable.MINIMUM_HEIGHT)
        RecipeTable.SetWindowSize(ui, 5000, 3000)
        width, height = RecipeTable.WindowSize(ui, 1920, 1080)
        harness.equal(width, 1920); harness.equal(height, 1080)
        RecipeTable.SetWindowSize(ui, 1000.6, 700.2)
        width, height = RecipeTable.WindowSize(ui, 1920, 1080)
        harness.equal(width, 1001); harness.equal(height, 700)
    end,

    ["recipe rows: item details and skill are filled, uncached and itemless stay nil (RF1)"] = function(harness)
        local addon = setup(harness)
        local byName = {}
        for _, row in ipairs(rows(addon)) do byName[row.name] = row end
        harness.equal(byName.Blue.quality, 3); harness.equal(byName.Blue.itemLevel, 35); harness.equal(byName.Blue.requiredLevel, 30)
        harness.equal(byName.Blue.skill, 150)
        harness.equal(byName.White.requiredLevel, nil)
        harness.equal(byName.Enchant.itemLevel, nil); harness.equal(byName.Enchant.quality, nil)
        harness.equal(byName.Uncached.itemLevel, nil)
        harness.truthy(type(byName.Blue.categoryLabel) == "string")
    end,

    ["recipe rows: without the item lookup nothing breaks"] = function(harness)
        local addon = setup(harness)
        local recipeRows = addon.Model.BuildRecipeRows(addon.Store, { text = "" })
        harness.equal(#recipeRows, 6)
        harness.equal(recipeRows[1].itemLevel, nil)
    end,

    ["recipe sort: item level highest first, missing values last, ties by name"] = function(harness)
        local addon = setup(harness)
        local recipeRows = rows(addon)
        addon.RecipeTable.Sort(recipeRows, { key = "itemLevel", descending = true })
        harness.equal(recipeNames(recipeRows), "Blue,Purple,Green,White,Enchant,Uncached")
        addon.RecipeTable.Sort(recipeRows, { key = "itemLevel", descending = false })
        harness.equal(recipeNames(recipeRows), "White,Green,Blue,Purple,Enchant,Uncached", "missing values stay last ascending too")
        addon.RecipeTable.Sort(recipeRows, { key = "requiredLevel", descending = true })
        harness.equal(recipeNames(recipeRows), "Purple,Blue,Green,Enchant,Uncached,White")
        addon.RecipeTable.Sort(recipeRows, { key = "name", descending = false })
        harness.equal(recipeNames(recipeRows), "Blue,Enchant,Green,Purple,Uncached,White")
        addon.RecipeTable.Sort(recipeRows, { key = "skill", descending = false })
        harness.equal(recipeNames(recipeRows), "Green,Blue,Purple,Enchant,Uncached,White")
    end,

    ["recipe rows: a peer's recipe name with markup stays escaped inside the quality colour (RF5)"] = function(harness)
        local addon = harness.addon()
        -- the store refuses such a name outright; the colour must stay safe even if one got through (Model escapes)
        addon.Store.PutCatalog({ [7] = { name = "Evil|cffff0000Red|r", produces = 101, reagents = {} } })
        harness.equal(addon.Store.GetRecipe(7), nil, "the store refuses a recipe name with escape codes")
        local escapedName = addon.Utility.Escape("Evil|cffff0000Red|r")
        local coloured = addon.RecipeTable.Coloured(escapedName, addon.RecipeTable.QualityHex(2))
        harness.truthy(coloured:find("Evil||cffff0000Red||r", 1, true), "the peer's colour code is escaped (shown as text)")
        harness.truthy(coloured:find("^|cff1eff00"), "our colour code wraps it")
    end,
}
