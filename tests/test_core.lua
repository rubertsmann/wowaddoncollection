-- Util, Store, Codec, Model
return {
    ["util: FullName strips realm spaces and keeps existing realms"] = function(h)
        local ns = h.ns()
        h.eq(ns.Util.FullName("Bob", "Area 52"), "Bob-Area52")
        h.eq(ns.Util.FullName("Bob-Area52"), "Bob-Area52")
        h.eq(ns.Util.Count({ a = 1, b = 2 }), 2)
    end,

    ["store: PutChar keeps the newer rev only"] = function(h)
        local ns = h.ns()
        h.truthy(ns.Store.PutChar(h.char("A-R", 10, { 1 })))
        h.eq(ns.Store.PutChar(h.char("A-R", 5, { 1, 2 })), false)
        h.eq(ns.Store.GetChar("A-R").rev, 10)
    end,

    ["store: Crafters lists only characters knowing the recipe, best rank first"] = function(h)
        local ns = h.ns()
        ns.Store.PutChar(h.char("A-R", 1, { 42 }, 50))
        ns.Store.PutChar(h.char("B-R", 1, { 42 }, 200))
        ns.Store.PutChar(h.char("C-R", 1, { 7 }, 300))
        local c = ns.Store.Crafters(42)
        h.eq(#c, 2); h.eq(c[1].name, "B-R")
    end,

    ["store: Prune removes members who left the guild but never me"] = function(h)
        local ns = h.ns()
        ns.Store.PutChar(h.char("A-R", 1, {})); ns.Store.PutChar(h.char("Gone-R", 1, {})); ns.Store.PutChar(h.char("Me-R", 1, {}))
        h.eq(ns.Store.Prune({ ["A-R"] = true }, "Me-R"), 1)
        h.truthy(ns.Store.GetChar("Me-R")); h.eq(ns.Store.GetChar("Gone-R"), nil)
    end,

    ["store: ValidateChar rejects rank > max and non-numeric recipe ids"] = function(h)
        local ns = h.ns()
        h.truthy(ns.Store.ValidateChar(h.char("A-R", 1, { 1 })))
        local bad = h.char("A-R", 1, { 1 }, 400)
        h.eq(ns.Store.ValidateChar(bad), false)
        local bad2 = h.char("A-R", 1, {}); bad2.professions.Cooking.recipes.x = true
        h.eq(ns.Store.ValidateChar(bad2), false)
    end,

    ["codec: round trip a snapshot message"] = function(h)
        local ns = h.ns()
        local msg = { t = "SNAP", char = h.char("A-R", 99, { 1, 2, 3 }), catalog = { [1] = { name = "x", reagents = { { itemID = 5, count = 2 } } } } }
        local out = assert(ns.Codec.Decode(ns.Codec.Encode(msg)))
        h.eq(out.t, "SNAP"); h.eq(out.char.rev, 99); h.eq(out.catalog[1].reagents[1].count, 2)
    end,

    ["codec: garbage never throws (RF5)"] = function(h)
        local ns = h.ns()
        for _, s in ipairs({ "", "garbage", string.rep("x", 100), "\1\2\3" }) do
            local m, err = ns.Codec.Decode(s)
            h.eq(m, nil); h.truthy(err)
        end
        h.eq((ns.Codec.Decode(nil)), nil)
        h.eq((ns.Codec.Deserialize("{n1;")), nil)
        h.eq((ns.Codec.Deserialize(("{"):rep(50))), nil)
    end,

    ["codec: a different protocol version is rejected"] = function(h)
        local ns = h.ns()
        local enc = ns.Codec.Encode({ t = "HELLO" })
        ns.PROTOCOL = ns.PROTO_MAJOR + 1
        h.eq((ns.Codec.Decode(enc)), nil)
    end,

    ["model: recipe rows filter by profession and search recipe or reagent, merging crafters"] = function(h)
        local ns = h.ns()
        ns.Store.PutChar(h.char("A-R", 1, { 1, 2 }))
        ns.Store.PutChar(h.char("B-R", 1, { 2 }))
        ns.Store.PutCatalog({ [1] = { name = "Roast Boar", reagents = { { itemID = 10, count = 1, name = "Boar Meat" } } },
            [2] = { name = "Spiced Wolf", reagents = { { itemID = 11, count = 2, name = "Wolf Meat" } } } })
        local rows = ns.Model.BuildRecipeRows(ns.Store, { text = "" })
        h.eq(#rows, 2)
        local byName = {}
        for _, r in ipairs(rows) do byName[r.name] = r end
        h.eq(byName["Spiced Wolf"].crafterCount, 2)
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { text = "boar" }), 1)
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { text = "wolf meat" }), 1)   -- reagent search
        -- profession filters use the canonical key (Names.ProfKey), not the raw name
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { profession = ns.Names.ProfKey("Tailoring"), text = "" }), 0)
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { profession = ns.Names.ProfKey("Cooking"), text = "" }), 2)
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { text = "", mineOnly = true, me = "B-R" }), 1)
    end,

    ["store: Clean empties everything in place, keeps preferences, and holders of the tables keep working"] = function(h)
        local ns = h.ns()
        ns.db.ui.minimapAngle = 99; ns.db.me = "A-R"
        ns.Store.PutChar(h.char("A-R", 1, { 1, 2 })); ns.Store.PutChar(h.char("B-R", 1, { 2 }))
        ns.Store.PutCatalog({ [1] = { name = "x", reagents = {} } })
        ns.db.profNames.deDE = { [185] = "Kochkunst" }
        ns.db.debug[1] = "log"
        local orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
        orders:Create("A-R", 1, 1, "")
        local n = ns.Store.Counts()
        h.eq(n.chars, 2); h.eq(n.recipes, 3); h.eq(n.orders, 1); h.eq(n.catalog, 1); h.eq(n.names, 1)

        local removed = ns.Store.Clean()
        h.eq(removed.chars, 2); h.eq(removed.orders, 1)
        local after = ns.Store.Counts()
        h.eq(after.chars + after.recipes + after.orders + after.catalog + after.names, 0)
        h.eq(#ns.db.debug, 0)
        h.eq(ns.db.ui.minimapAngle, 99, "preferences must survive"); h.eq(ns.db.me, "A-R"); h.eq(ns.db.schema, ns.Store.SCHEMA)
        h.eq(#orders:List({ showClosed = true }), 0, "the order board must see the wipe")
        local o = orders:Create("A-R", 2, 1, "")                    -- the same object still stores into the live table
        h.truthy(o and ns.db.orders[o.id], "orders holder lost its table")
        h.eq(ns.Store.PutChar(h.char("C-R", 1, { 1 })), true)
        h.eq(ns.Store.Clean().chars, 1)
    end,

    ["model: recipe detail computes have/enough and tolerates missing item names"] = function(h)
        local ns = h.ns()
        ns.Store.PutCatalog({ [1] = { name = "Roast", reagents = { { itemID = 10, count = 3 }, { itemID = 11, count = 1 } } } })
        local d = ns.Model.RecipeDetail(ns.Store, 1, function(id) return id == 10 and 2 or 5 end, function() return nil end)
        h.eq(d.reagents[1].enough, false); h.eq(d.reagents[2].enough, true); h.eq(d.reagents[1].name, "Item #10")
        h.eq(ns.Model.RecipeDetail(ns.Store, 999).name, "Recipe #999")
    end,
}
