-- Feature 017 (probe): the dev "Fake enchanter" record must survive the guild-roster prune, and the exemption list is
-- empty unless something fills it (the live build never does).
return {
    ["search: an enchant is found by its effect text; recipes with an item are not asked"] = function(harness)
        local addon = harness.addon()
        addon.Store.PutCharacter(harness.character("A-R", 1, { 13419, 1 }))
        addon.Store.PutCatalog({
            [13419] = { name = "Enchant Cloak - Minor Agility", reagents = {} },
            [1] = { name = "Boots", produces = 2302, reagents = {} },
        })
        local asked = {}
        local lookups = { effect = function(recipeID) asked[recipeID] = true; return recipeID == 13419 and "Permanently enchant a cloak to give +1 Beweglichkeit." or nil end }
        local recipeRows = addon.Model.BuildRecipeRows(addon.Store, { text = "beweglichkeit" }, nil, lookups)
        harness.equal(#recipeRows, 1); harness.equal(recipeRows[1].recipeID, 13419)
        harness.equal(asked[1], nil, "a recipe with an item uses the item text, not the spell")
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "stamina" }, nil, lookups), 0)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "beweglichkeit" }), 0, "without the lookup nothing breaks")
    end,

    ["prune: a name in Store.keptNames survives, other non-members do not"] = function(harness)
        local addon = harness.addon()
        local Store = addon.Store
        harness.equal(next(Store.keptNames), nil, "empty by default")
        Store.PutCharacter(harness.character("Fake Enchanter-R", 1, { 13419 }))
        Store.PutCharacter(harness.character("Gone-R", 1, { 1 }))
        Store.PutCharacter(harness.character("Me-R", 1, { 2 }))
        Store.keptNames["Fake Enchanter-R"] = true
        Store.Prune({}, "Me-R")
        harness.truthy(Store.db.chars["Fake Enchanter-R"], "kept")
        harness.truthy(Store.db.chars["Me-R"], "my own record is kept")
        harness.equal(Store.db.chars["Gone-R"], nil, "a member who left is still pruned")
    end,
}
