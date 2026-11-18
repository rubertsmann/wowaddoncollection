-- Feature 012: the shared helpers that replaced the per-module copies (Util table helpers, U.Me, U.ChatSafe,
-- Store.Knows / Store.RecipeCount). Each test pins the behaviour the old copies had, incl. their malformed-input cases.
local T = {}

T["Count: table, empty, non-table"] = function(harness)
    local U = harness.addon().Utility
    harness.equal(U.Count({ a = 1, b = 2, [3] = true }), 3)
    harness.equal(U.Count({}), 0)
    harness.equal(U.Count(nil), 0)
    harness.equal(U.Count(false), 0)
    harness.equal(U.Count("abc"), 0)
end

T["SortedKeys: numbers natural, strings after, mixed never errors"] = function(harness)
    local U = harness.addon().Utility
    harness.equal(table.concat(U.SortedKeys({ [10] = 1, [2] = 1, [1] = 1 }), ","), "1,2,10")   -- not "1,10,2"
    harness.equal(table.concat(U.SortedKeys({ b = 1, a = 1, C = 1 }), ","), "C,a,b")
    harness.equal(table.concat(U.SortedKeys({ b = 1, [5] = 1, a = 1, [3] = 1 }), ","), "3,5,a,b")
    local k = U.SortedKeys({ [true] = 1, x = 1, [1] = 1 })
    harness.equal(#k, 3); harness.equal(k[1], 1); harness.equal(k[2], "x"); harness.equal(k[3], true)
    harness.equal(#U.SortedKeys(nil), 0)
end

T["Wipe and Refill keep the table identity"] = function(harness)
    local U = harness.addon().Utility
    local t = { a = 1, b = 2 }
    local ref = t
    harness.equal(U.Wipe(t), ref)
    harness.equal(next(t), nil)
    t.old = true
    U.Refill(t, { x = 1, y = 2 })
    harness.equal(ref, t); harness.equal(t.old, nil); harness.equal(t.x, 1); harness.equal(t.y, 2)
end

T["SanitizeMap: drops failures, errors and bad keys; non-table -> empty"] = function(harness)
    local U = harness.addon().Utility
    local function san(v)
        if v == "boom" then error("bad") end
        return type(v) == "number" and { n = v } or nil
    end
    local out, dropped = U.SanitizeMap({ a = 1, b = "x", c = "boom", d = 4 }, san, function(k) return k ~= "d" end)
    harness.equal(out.a.n, 1); harness.equal(out.b, nil); harness.equal(out.c, nil); harness.equal(out.d, nil)
    harness.equal(dropped, 3)
    local e, n = U.SanitizeMap("nope", san, function() return true end)
    harness.equal(next(e), nil); harness.equal(n, 0)
end

T["Me: stored identity first, then the client, nil before either"] = function(harness)
    local addon = harness.addon()
    addon.Store.db.me = nil
    addon.Api = nil
    harness.equal(addon.Utility.Me(), nil)
    addon.Api = { GetPlayerInformation = function() return { name = "Client-Realm" } end }
    harness.equal(addon.Utility.Me(), "Client-Realm")
    addon.Store.db.me = "Stored-Realm"
    harness.equal(addon.Utility.Me(), "Stored-Realm")
    local store = addon.Store
    addon.Store = { }            -- before Store.Init: no db yet (the Comm copy guarded this, the UI copies did not)
    harness.equal(addon.Utility.Me(), "Client-Realm")
    addon.Store = store
end

T["ChatSafe strips escape codes, link brackets and line breaks"] = function(harness)
    local U = harness.addon().Utility
    harness.equal(U.ChatSafe("|cffff0000Red|r [Link]\nx\r"), "cffff0000Redr Linkx")
    harness.equal(U.ChatSafe(nil), "nil")
    harness.equal(U.ChatSafe(12), "12")
end

T["Store.Knows: any profession; malformed records are false, never an error"] = function(harness)
    local S = harness.addon().Store
    local rec = harness.character("A-R", 1, { 100, 200 })
    harness.equal(S.Knows(rec, 100), true)
    harness.equal(S.Knows(rec, 300), false)
    harness.equal(S.Knows(nil, 100), false)
    harness.equal(S.Knows({ professions = { X = { name = "X" } } }, 100), false)   -- recipes missing (old Model copy threw here)
    harness.equal(S.Knows({ professions = { X = "junk" } }, 100), false)
    harness.equal(S.Knows({ professions = "junk" }, 100), false)
end

T["Store.RecipeCount sums every profession and ignores junk"] = function(harness)
    local S = harness.addon().Store
    local rec = harness.character("A-R", 1, { 1, 2, 3 })
    rec.professions.Alchemy = { name = "Alchemy", recipes = { [7] = true } }
    rec.professions.Bad = "junk"
    harness.equal(S.RecipeCount(rec), 4)
    harness.equal(S.RecipeCount(nil), 0)
    harness.equal(S.RecipeCount({}), 0)
end

T["Store.Counts uses the shared helpers and still counts everything"] = function(harness)
    local addon = harness.addon()
    local S = addon.Store
    S.db.chars["A-R"] = harness.character("A-R", 1, { 1, 2 })
    S.db.chars["B-R"] = harness.character("B-R", 1, { 3 })
    S.db.catalog[1] = { name = "x" }
    S.db.offers["A-R"] = { name = "A-R", rev = 1, items = { [10] = { bag = 1 }, [11] = { bag = 2 } }, dibs = {} }
    S.db.profNames.enUS = { [1] = "Cooking", [2] = "Alchemy" }
    local n = S.Counts()
    harness.equal(n.chars, 2); harness.equal(n.recipes, 3); harness.equal(n.catalog, 1); harness.equal(n.offers, 2); harness.equal(n.names, 2); harness.equal(n.orders, 0)
    local records, items = addon.Offers.Counts()
    harness.equal(records, 1); harness.equal(items, 2)
end

T["Model.ChatText still builds a safe [Name] x qty"] = function(harness)
    local addon = harness.addon()
    harness.equal(addon.Model.ChatText(nil, "|Hevil|h[Bad]", 3), "[HevilhBad] x3")
    harness.equal(addon.Model.ChatText("|Hitem:1|h[Real]|h", "ignored", 1), "|Hitem:1|h[Real]|h")
end

return T
