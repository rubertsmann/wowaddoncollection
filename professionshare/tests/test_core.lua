-- Util, Store, Codec, Model
return {
    ["util: FullName strips realm spaces and keeps existing realms"] = function(harness)
        local addon = harness.addon()
        harness.equal(addon.Utility.FullName("Bob", "Area 52"), "Bob-Area52")
        harness.equal(addon.Utility.FullName("Bob-Area52"), "Bob-Area52")
        harness.equal(addon.Utility.Count({ a = 1, b = 2 }), 2)
    end,

    ["store: PutChar keeps the newer rev only"] = function(harness)
        local addon = harness.addon()
        harness.truthy(addon.Store.PutCharacter(harness.character("A-R", 10, { 1 })))
        harness.equal(addon.Store.PutCharacter(harness.character("A-R", 5, { 1, 2 })), false)
        harness.equal(addon.Store.GetCharacter("A-R").rev, 10)
    end,

    ["store: Crafters lists only characters knowing the recipe, best rank first"] = function(harness)
        local addon = harness.addon()
        addon.Store.PutCharacter(harness.character("A-R", 1, { 42 }, 50))
        addon.Store.PutCharacter(harness.character("B-R", 1, { 42 }, 200))
        addon.Store.PutCharacter(harness.character("C-R", 1, { 7 }, 300))
        local c = addon.Store.Crafters(42)
        harness.equal(#c, 2); harness.equal(c[1].name, "B-R")
    end,

    ["store: Prune removes members who left the guild but never me"] = function(harness)
        local addon = harness.addon()
        addon.Store.PutCharacter(harness.character("A-R", 1, {})); addon.Store.PutCharacter(harness.character("Gone-R", 1, {})); addon.Store.PutCharacter(harness.character("Me-R", 1, {}))
        harness.equal(addon.Store.Prune({ ["A-R"] = true }, "Me-R"), 1)
        harness.truthy(addon.Store.GetCharacter("Me-R")); harness.equal(addon.Store.GetCharacter("Gone-R"), nil)
    end,

    ["store: ValidateChar rejects rank > max and non-numeric recipe ids"] = function(harness)
        local addon = harness.addon()
        harness.truthy(addon.Store.ValidateCharacter(harness.character("A-R", 1, { 1 })))
        local bad = harness.character("A-R", 1, { 1 }, 400)
        harness.equal(addon.Store.ValidateCharacter(bad), false)
        local bad2 = harness.character("A-R", 1, {}); bad2.professions.Cooking.recipes.x = true
        harness.equal(addon.Store.ValidateCharacter(bad2), false)
    end,

    ["codec: round trip a snapshot message"] = function(harness)
        local addon = harness.addon()
        local msg = { t = "SNAP", char = harness.character("A-R", 99, { 1, 2, 3 }), catalog = { [1] = { name = "x", reagents = { { itemID = 5, count = 2 } } } } }
        local out = assert(addon.Codec.Decode(addon.Codec.Encode(msg)))
        harness.equal(out.t, "SNAP"); harness.equal(out.char.rev, 99); harness.equal(out.catalog[1].reagents[1].count, 2)
    end,

    ["codec: garbage never throws (RF5)"] = function(harness)
        local addon = harness.addon()
        for _, s in ipairs({ "", "garbage", string.rep("x", 100), "\1\2\3" }) do
            local m, err = addon.Codec.Decode(s)
            harness.equal(m, nil); harness.truthy(err)
        end
        harness.equal((addon.Codec.Decode(nil)), nil)
        harness.equal((addon.Codec.Deserialize("{n1;")), nil)
        harness.equal((addon.Codec.Deserialize(("{"):rep(50))), nil)
    end,

    ["codec: a different protocol version is rejected"] = function(harness)
        local addon = harness.addon()
        local enc = addon.Codec.Encode({ t = "HELLO" })
        addon.PROTOCOL_MAJOR = addon.PROTOCOL_MAJOR + 1; addon.PROTOCOL = addon.PROTOCOL_MAJOR   -- aliases (Core/Base/Init.lua)
        harness.equal((addon.Codec.Decode(enc)), nil)
    end,

    ["model: recipe rows filter by profession and search recipe or reagent, merging crafters"] = function(harness)
        local addon = harness.addon()
        addon.Store.PutCharacter(harness.character("A-R", 1, { 1, 2 }))
        addon.Store.PutCharacter(harness.character("B-R", 1, { 2 }))
        addon.Store.PutCatalog({ [1] = { name = "Roast Boar", reagents = { { itemID = 10, count = 1, name = "Boar Meat" } } },
            [2] = { name = "Spiced Wolf", reagents = { { itemID = 11, count = 2, name = "Wolf Meat" } } } })
        local rows = addon.Model.BuildRecipeRows(addon.Store, { text = "" })
        harness.equal(#rows, 2)
        local byName = {}
        for _, r in ipairs(rows) do byName[r.name] = r end
        harness.equal(byName["Spiced Wolf"].crafterCount, 2)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "boar" }), 1)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "wolf meat" }), 1)   -- reagent search
        -- profession filters use the canonical key (Names.ProfKey), not the raw name
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { profession = addon.Names.ProfessionKey("Tailoring"), text = "" }), 0)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { profession = addon.Names.ProfessionKey("Cooking"), text = "" }), 2)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "", mineOnly = true, me = "B-R" }), 1)
    end,

    ["store: Clean empties everything in place, keeps preferences, and holders of the tables keep working"] = function(harness)
        local addon = harness.addon()
        addon.db.ui.minimapAngle = 99; addon.db.me = "A-R"
        addon.Store.PutCharacter(harness.character("A-R", 1, { 1, 2 })); addon.Store.PutCharacter(harness.character("B-R", 1, { 2 }))
        addon.Store.PutCatalog({ [1] = { name = "x", reagents = {} } })
        addon.db.profNames.deDE = { [185] = "Kochkunst" }
        addon.db.debug[1] = "log"
        local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
        orders:Create("A-R", 1, 1, "")
        local n = addon.Store.Counts()
        harness.equal(n.chars, 2); harness.equal(n.recipes, 3); harness.equal(n.orders, 1); harness.equal(n.catalog, 1); harness.equal(n.names, 1)

        local removed = addon.Store.Clean()
        harness.equal(removed.chars, 2); harness.equal(removed.orders, 1)
        local after = addon.Store.Counts()
        harness.equal(after.chars + after.recipes + after.orders + after.catalog + after.names, 0)
        harness.equal(#addon.db.debug, 0)
        harness.equal(addon.db.ui.minimapAngle, 99, "preferences must survive"); harness.equal(addon.db.me, "A-R"); harness.equal(addon.db.schema, addon.Store.SCHEMA)
        harness.equal(#orders:List({ showClosed = true }), 0, "the order board must see the wipe")
        local o = orders:Create("A-R", 2, 1, "")                    -- the same object still stores into the live table
        harness.truthy(o and addon.db.orders[o.id], "orders holder lost its table")
        harness.equal(addon.Store.PutCharacter(harness.character("C-R", 1, { 1 })), true)
        harness.equal(addon.Store.Clean().chars, 1)
    end,

    ["model: recipe detail computes have/enough and tolerates missing item names"] = function(harness)
        local addon = harness.addon()
        addon.Store.PutCatalog({ [1] = { name = "Roast", reagents = { { itemID = 10, count = 3 }, { itemID = 11, count = 1 } } } })
        local d = addon.Model.RecipeDetail(addon.Store, 1, function(id) return id == 10 and 2 or 5 end, function() return nil end)
        harness.equal(d.reagents[1].enough, false); harness.equal(d.reagents[2].enough, true); harness.equal(d.reagents[1].name, "Item #10")
        harness.equal(addon.Model.RecipeDetail(addon.Store, 999).name, "Recipe #999")
    end,
}
