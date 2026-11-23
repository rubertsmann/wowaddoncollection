-- Misc Items tab: key and attunement rows (Model), the per-mode column tables (MiscTables, ColumnTable).
local BIG = 1700000000

local function fresh(harness)
    local addon = harness.addon({ now = BIG })
    addon.Store.db.me = "Me-R"
    return addon
end

-- client item data: 7146 and 99001 are keys (class 13), 12344 a ring (listed entry item), 555 a sword
local CLASS = { [7146] = 13, [99001] = 13, [12344] = 4, [555] = 2, [11078] = 13 }
local function itemClass(id) return CLASS[id], 0, "icon" .. id end
local function itemName(id) return ({ [7146] = "The Scarlet Key", [12344] = "Seal of Ascension" })[id] end

return {
    ["key rows: one row per key with holders; non-keys, deny-listed and unknown ids are not shown"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        Access.Put({ name = "B-R", rev = 1, keys = { [7146] = { bag = true }, [555] = { bag = true }, [424242] = { bag = true } }, att = {} })
        Access.Put({ name = "Me-R", rev = 1, keys = { [7146] = { keyring = true }, [12344] = { bank = true }, [11078] = { bag = true } }, att = {} })
        local rows = addon.Model.BuildKeyRows({ me = "Me-R" }, itemClass, itemName)
        harness.equal(#rows, 2)
        local byID = {}
        for _, row in ipairs(rows) do byID[row.itemID] = row end
        harness.equal(byID[7146].holderCount, 2); harness.truthy(byID[7146].mine)
        harness.equal(byID[7146].instance, "Scarlet Monastery"); harness.equal(byID[7146].name, "The Scarlet Key")
        harness.equal(byID[12344].instance, "Upper Blackrock Spire")
        harness.equal(byID[555], nil, "a peer cannot list a sword as a key")
        harness.equal(addon.Model.KeyContact(byID[7146], "Me-R"), "B-R")
        harness.equal(addon.Model.KeyContact(byID[12344], "Me-R"), nil, "only I hold it")
    end,

    ["key rows: search matches key, dungeon and holder; peer names are escaped"] = function(harness)
        local addon = fresh(harness)
        addon.Access.Put({ name = "B-R", rev = 1, keys = { [7146] = { bag = true } }, att = {} })
        addon.Access.Put({ name = "C-R", rev = 1, keys = { [12344] = { bag = true } }, att = {} })
        local function search(text) return #addon.Model.BuildKeyRows({ text = text, me = "Me-R" }, itemClass, itemName) end
        harness.equal(search("scarlet"), 1); harness.equal(search("blackrock"), 1); harness.equal(search("c-r"), 1)
        harness.equal(search("zzz"), 0)
        addon.Store.db.access["X|r-R"] = { name = "X|r-R", rev = 1, keys = { [7146] = { bag = true } }, att = {} }
        local rows = addon.Model.BuildKeyRows({ me = "Me-R" }, itemClass, itemName)
        local scarletRow
        for _, row in ipairs(rows) do if row.itemID == 7146 then scarletRow = row end end
        harness.truthy(scarletRow.holderNames:find("X||r", 1, true), "the bar is escaped")
    end,

    ["attunement rows: every attunement listed, counts and my state"] = function(harness)
        local addon = fresh(harness)
        addon.Access.Put({ name = "B-R", rev = 1, keys = {}, att = { mc = true, bwl = false } })
        addon.Access.Put({ name = "Me-R", rev = 1, keys = {}, att = { mc = true } })
        local rows = addon.Model.BuildAttunementRows({ me = "Me-R" }, itemClass)
        harness.equal(#rows, #addon.Access.ATTUNEMENTS)
        local byKey = {}
        for _, row in ipairs(rows) do byKey[row.key] = row end
        harness.equal(byKey.mc.attunedCount, 2); harness.equal(byKey.mc.mine, true); harness.equal(byKey.mc.name, "Molten Core")
        harness.equal(byKey.bwl.missingCount, 1); harness.equal(byKey.bwl.mine, nil, "my bwl state is not known")
        harness.equal(byKey.ubrs.icon, "icon12344", "the item icon from this client")
        harness.equal(#addon.Model.BuildAttunementRows({ text = "molten", me = "Me-R" }, itemClass), 1)
    end,

    ["misc tables: mode setting validated, each mode keeps its own columns and sort"] = function(harness)
        local addon = fresh(harness)
        local MiscTables = addon.MiscTables
        local ui = {}
        harness.equal(MiscTables.GetMode(ui), "offers"); harness.equal(MiscTables.GetMode(nil), "offers")
        MiscTables.SetMode(ui, "keys"); harness.equal(MiscTables.GetMode(ui), "keys")
        MiscTables.SetMode(ui, "bogus"); harness.equal(MiscTables.GetMode(ui), "keys")
        ui.miscMode = 42; harness.equal(MiscTables.GetMode(ui), "offers")
        local keys, attunements = MiscTables.Table("keys"), MiscTables.Table("attunements")
        keys.SetColumn(ui, "holderNames", false)
        harness.equal(keys.ColumnShown(ui, "holderNames"), false)
        harness.equal(keys.ColumnShown(ui, "name"), true, "the name column is always shown")
        harness.equal(attunements.ColumnShown(ui, "missingCount"), false, "hidden by default")
        attunements.SetColumn(ui, "missingCount", true); harness.equal(attunements.ColumnShown(ui, "missingCount"), true)
        harness.equal(MiscTables.Table("offers").ColumnShown(ui, "owner"), true)
        keys.ClickHeader(ui, "holderCount")
        harness.equal(keys.GetSort(ui).key, "holderCount"); harness.equal(keys.GetSort(ui).descending, true)
        harness.equal(MiscTables.Table("offers").GetSort(ui).key, "profession", "another mode's sort is untouched")
        ui.keySort = { key = "nope", descending = 1 }
        harness.equal(keys.GetSort(ui).key, "instance", "a broken saved sort falls back to the default")
        harness.equal(keys.ColumnLabel("instance"), "Opens")
    end,

    ["misc tables: layout gives the name the rest; sort puts missing values last and ties by name"] = function(harness)
        local addon = fresh(harness)
        local keys = addon.MiscTables.Table("keys")
        local cells = keys.Layout(keys.VisibleColumns({}), 800)
        harness.equal(cells[1].key, "name"); harness.equal(keys.TableWidth(cells), 800)
        local rows = { { name = "B", itemID = 2, instance = "" }, { name = "A", itemID = 1, instance = "Stratholme" },
            { name = "C", itemID = 3, instance = "Dire Maul" } }
        keys.Sort(rows, { key = "instance", descending = false })
        harness.equal(rows[1].name, "C"); harness.equal(rows[2].name, "A"); harness.equal(rows[3].name, "B")
        keys.Sort(rows, { key = "holderCount", descending = true })
        harness.equal(rows[1].name, "A", "no counts: by name")
    end,

    ["recipe table keeps its API on top of ColumnTable"] = function(harness)
        local addon = fresh(harness)
        local RecipeTable = addon.RecipeTable
        harness.equal(#RecipeTable.OPTIONAL_KEYS, 5); harness.equal(RecipeTable.ColumnLabel("itemLevel"), "Item level")
        local ui = { recipeColumns = { skill = false } }
        harness.equal(RecipeTable.ColumnShown(ui, "skill"), false); harness.equal(RecipeTable.ColumnShown(ui, "name"), true)
        local rows = { { name = "x", recipeID = 10, itemLevel = 5 }, { name = "x", recipeID = 9, itemLevel = 5 } }
        RecipeTable.Sort(rows, { key = "itemLevel", descending = true })
        harness.equal(rows[1].recipeID, 9, "ties by id, numerically")
    end,
}
