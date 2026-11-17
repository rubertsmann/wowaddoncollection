-- Feature 009: craft from the Orders tab, whisper with the recipe link from the list icons (pure parts).
local ME = "Me Holt"

local function setup(harness)
    local addon = harness.addon()
    addon.Store.PutCharacter(harness.character(ME, 10, { 100 }))
    addon.Store.PutCharacter(harness.character("Mira Holt", 20, { 100, 200 }, 250))
    return addon
end

local LIVE = { { name = "Cooking", id = 185, icon = 1, rank = 100, max = 300, spells = { "Cooking" } } }

return {
    ["craft: the target is my live profession that holds the recipe"] = function(harness)
        local addon = setup(harness)
        local t = addon.Model.CraftTarget(addon.Store, ME, 100, LIVE)
        harness.truthy(t, "target")
        harness.equal(t.spellName, "Cooking")
        harness.equal(addon.Model.CastMacro(t), "/cast Cooking")
    end,

    ["craft: no target for a recipe I do not know"] = function(harness)
        local addon = setup(harness)
        local t, why = addon.Model.CraftTarget(addon.Store, ME, 200, LIVE)
        harness.equal(t, nil); harness.equal(why, "unknown")
    end,

    ["craft: no target without a live profession"] = function(harness)
        local addon = setup(harness)
        local t, why = addon.Model.CraftTarget(addon.Store, ME, 100, {})
        harness.equal(t, nil); harness.equal(why, "noprof")
    end,

    ["craft: order rows say whether I can craft them"] = function(harness)
        local addon = setup(harness)
        local orders = addon.Orders.New(function() return harness.clock end, {})
        local o = orders:Create("Mira Holt", 100, 2, "", "Stew")
        local o2 = orders:Create("Mira Holt", 200, 1, "", "Roast")
        local rows = addon.Model.BuildOrderRows(addon.Store, orders, "all", false, ME)
        local by = {}
        for _, r in ipairs(rows) do by[r.id] = r end
        harness.equal(by[o.id].canCraft, true)
        harness.equal(by[o2.id].canCraft, false)
    end,

    ["whisper: never to myself"] = function(harness)
        local addon = harness.addon()
        harness.equal(addon.Model.OrderContact({ requester = ME, claimers = {} }, ME), nil)
        harness.equal(addon.Model.OrderContact({ requester = ME, claimersRaw = { ME, "Orin Vale" } }, ME), "Orin Vale")
        harness.equal(addon.Model.OrderContact({ requester = "Orin Vale", claimersRaw = { ME } }, ME), "Orin Vale")
        harness.equal(addon.Model.RecipeContact({ { name = ME } }, ME), nil)
        harness.equal(addon.Model.RecipeContact({ { name = ME }, { name = "Tam Reed" } }, ME), "Tam Reed")
    end,

    ["whisper: the recipe crafter is the highest rank that is not me"] = function(harness)
        local addon = setup(harness)
        harness.equal(addon.Model.RecipeContact(addon.Store.Crafters(100), ME), "Mira Holt")
    end,

    ["whisper: a peer recipe name cannot inject a link"] = function(harness)
        local addon = harness.addon()
        local t = addon.Model.ChatText(nil, "|cffff0000|Hitem:1|h[Evil]|h|r\nx", 3)
        harness.equal(t:find("|", 1, true), nil)
        harness.equal(t:find("\n", 1, true), nil)
        harness.equal(t, "[cffff0000Hitem:1hEvilhrx] x3")
    end,

    ["whisper: a local link is used as is, quantity 1 is not shown"] = function(harness)
        local addon = harness.addon()
        local link = "|cffffffff|Hitem:42::::::::60:::::|h[Stew]|h|r"
        harness.equal(addon.Model.ChatText(link, "ignored", 1), link)
        harness.equal(addon.Model.ChatText(link, "ignored", 2), link .. " x2")
    end,
}
