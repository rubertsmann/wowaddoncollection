-- Feature 009: craft from the Orders tab, whisper with the recipe link from the list icons (pure parts).
local ME = "Me Holt"

local function setup(h)
    local ns = h.ns()
    ns.Store.PutChar(h.char(ME, 10, { 100 }))
    ns.Store.PutChar(h.char("Mira Holt", 20, { 100, 200 }, 250))
    return ns
end

local LIVE = { { name = "Cooking", id = 185, icon = 1, rank = 100, max = 300, spells = { "Cooking" } } }

return {
    ["craft: the target is my live profession that holds the recipe"] = function(h)
        local ns = setup(h)
        local t = ns.Model.CraftTarget(ns.Store, ME, 100, LIVE)
        h.truthy(t, "target")
        h.eq(t.spellName, "Cooking")
        h.eq(ns.Model.CastMacro(t), "/cast Cooking")
    end,

    ["craft: no target for a recipe I do not know"] = function(h)
        local ns = setup(h)
        local t, why = ns.Model.CraftTarget(ns.Store, ME, 200, LIVE)
        h.eq(t, nil); h.eq(why, "unknown")
    end,

    ["craft: no target without a live profession"] = function(h)
        local ns = setup(h)
        local t, why = ns.Model.CraftTarget(ns.Store, ME, 100, {})
        h.eq(t, nil); h.eq(why, "noprof")
    end,

    ["craft: order rows say whether I can craft them"] = function(h)
        local ns = setup(h)
        local orders = ns.Orders.New(function() return h.clock end, {})
        local o = orders:Create("Mira Holt", 100, 2, "", "Stew")
        local o2 = orders:Create("Mira Holt", 200, 1, "", "Roast")
        local rows = ns.Model.BuildOrderRows(ns.Store, orders, "all", false, ME)
        local by = {}
        for _, r in ipairs(rows) do by[r.id] = r end
        h.eq(by[o.id].canCraft, true)
        h.eq(by[o2.id].canCraft, false)
    end,

    ["whisper: never to myself"] = function(h)
        local ns = h.ns()
        h.eq(ns.Model.OrderContact({ requester = ME, claimers = {} }, ME), nil)
        h.eq(ns.Model.OrderContact({ requester = ME, claimersRaw = { ME, "Orin Vale" } }, ME), "Orin Vale")
        h.eq(ns.Model.OrderContact({ requester = "Orin Vale", claimersRaw = { ME } }, ME), "Orin Vale")
        h.eq(ns.Model.RecipeContact({ { name = ME } }, ME), nil)
        h.eq(ns.Model.RecipeContact({ { name = ME }, { name = "Tam Reed" } }, ME), "Tam Reed")
    end,

    ["whisper: the recipe crafter is the highest rank that is not me"] = function(h)
        local ns = setup(h)
        h.eq(ns.Model.RecipeContact(ns.Store.Crafters(100), ME), "Mira Holt")
    end,

    ["whisper: a peer recipe name cannot inject a link"] = function(h)
        local ns = h.ns()
        local t = ns.Model.ChatText(nil, "|cffff0000|Hitem:1|h[Evil]|h|r\nx", 3)
        h.eq(t:find("|", 1, true), nil)
        h.eq(t:find("\n", 1, true), nil)
        h.eq(t, "[cffff0000Hitem:1hEvilhrx] x3")
    end,

    ["whisper: a local link is used as is, quantity 1 is not shown"] = function(h)
        local ns = h.ns()
        local link = "|cffffffff|Hitem:42::::::::60:::::|h[Stew]|h|r"
        h.eq(ns.Model.ChatText(link, "ignored", 1), link)
        h.eq(ns.Model.ChatText(link, "ignored", 2), link .. " x2")
    end,
}
