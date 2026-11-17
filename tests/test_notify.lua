-- Feature 010: notifications about new orders (pure part: relevance, unseen, seen, fresh, settings).
local ME = "Me Holt"

local function prof(name, id, recipes)
    local set = {}
    for _, r in ipairs(recipes) do set[r] = true end
    return { name = name, id = id, rank = 50, max = 300, recipes = set }
end

local function setup(harness, myProfs)
    local addon = harness.addon()
    addon.Store.PutCharacter({ name = ME, class = "MAGE", level = 60, rev = 1, professions = myProfs })
    addon.Store.PutCharacter({ name = "Mira Holt", class = "MAGE", level = 60, rev = 1, professions = {
        Cooking = prof("Cooking", 185, { 100, 101 }), Tailoring = prof("Tailoring", 197, { 300 }) } })
    local orders = addon.Orders.New(function() return harness.clock end, {})
    return addon, orders
end

local ALL = { scope = "all", mine = true }
local PROF = { scope = "profession", mine = true }
local KNOWN = { scope = "known", mine = true }

local function ids(list)
    local out = {}
    for _, it in ipairs(list) do out[#out + 1] = it.kind .. ":" .. it.order.recipeID end
    return table.concat(out, ",")
end

return {
    ["notify: settings fall back to defaults, bad values are ignored"] = function(harness)
        local addon = harness.addon()
        local N = addon.Notify
        harness.equal(N.Get(nil, "sound"), true)
        harness.equal(N.Get({ notify = { sound = false } }, "sound"), false)
        harness.equal(N.Get({ notify = { sound = "yes" } }, "sound"), true)
        harness.equal(N.Get({ notify = { scope = "evil" } }, "scope"), "profession")
        harness.equal(N.Get({ notify = { soundName = "PlaySoundFile('x')" } }, "soundName"), "IG_PLAYER_INVITE")
        harness.equal(N.Get({ notify = { soundName = "MAP_PING" } }, "soundName"), "MAP_PING")
        local ui = {}
        N.Set(ui, "screen", true); N.Set(ui, "nonsense", true)
        harness.equal(ui.notify.screen, true); harness.equal(ui.notify.nonsense, nil)
    end,

    ["notify: only orders for my profession count (scope profession)"] = function(harness)
        local addon, orders = setup(harness, { Cooking = prof("Cooking", 185, { 100 }) })
        orders:Create("Mira Holt", 101, 1, "")   -- Cooking, I do not know it yet: relevant
        orders:Create("Mira Holt", 300, 1, "")   -- Tailoring: not relevant
        harness.equal(ids(addon.Notify.Unseen(addon.Store, orders, ME, {}, PROF)), "new:101")
        harness.equal(ids(addon.Notify.Unseen(addon.Store, orders, ME, {}, KNOWN)), "")
        harness.equal(#addon.Notify.Unseen(addon.Store, orders, ME, {}, ALL), 2)
    end,

    ["notify: without any profession nothing is relevant"] = function(harness)
        local addon, orders = setup(harness, {})
        orders:Create("Mira Holt", 101, 1, "")
        harness.equal(#addon.Notify.Unseen(addon.Store, orders, ME, {}, PROF), 0)
    end,

    ["notify: profession match works across languages (skill line id)"] = function(harness)
        local addon, orders = setup(harness, { Kochkunst = prof("Kochkunst", 185, {}) })
        orders:Create("Mira Holt", 101, 1, "")
        harness.equal(ids(addon.Notify.Unseen(addon.Store, orders, ME, {}, PROF)), "new:101")
    end,

    ["notify: my own new order, claimed or closed orders of others are not new"] = function(harness)
        local addon, orders = setup(harness, { Cooking = prof("Cooking", 185, { 100 }) })
        orders:Create(ME, 100, 1, "")
        local o2 = orders:Create("Mira Holt", 100, 1, ""); orders:Claim(o2.id, "Orin Vale")
        local o3 = orders:Create("Mira Holt", 100, 1, ""); orders:Close(o3.id, "Mira Holt", "cancelled")
        harness.equal(#addon.Notify.Unseen(addon.Store, orders, ME, {}, PROF), 0)
    end,

    ["notify: seen orders stay seen, a new one appears"] = function(harness)
        local addon, orders = setup(harness, { Cooking = prof("Cooking", 185, { 100 }) })
        orders:Create("Mira Holt", 100, 1, "")
        local seen = addon.Notify.MarkSeen(orders, nil)
        harness.equal(#addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF), 0)
        harness.clock = harness.clock + 5
        orders:Create("Mira Holt", 101, 2, "")
        harness.equal(ids(addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF)), "new:101")
    end,

    ["notify: my order claimed or done by someone else is news, by me it is not"] = function(harness)
        local addon, orders = setup(harness, { Cooking = prof("Cooking", 185, { 100 }) })
        local o = orders:Create(ME, 100, 1, "")
        local seen = addon.Notify.MarkSeen(orders, nil)
        orders:Claim(o.id, ME)
        harness.equal(#addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF), 0)
        harness.clock = harness.clock + 1
        orders:Claim(o.id, "Mira Holt")
        harness.equal(ids(addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF)), "claimed:100")
        harness.equal(#addon.Notify.Unseen(addon.Store, orders, ME, seen, { scope = "profession", mine = false }), 0)
        seen = addon.Notify.MarkSeen(orders, seen)
        harness.clock = harness.clock + 1
        orders:Close(o.id, "Mira Holt", "done")
        harness.equal(ids(addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF)), "done:100")
    end,

    ["notify: fresh reports each item once, a new claimer again"] = function(harness)
        local addon, orders = setup(harness, { Cooking = prof("Cooking", 185, { 100 }) })
        local o = orders:Create(ME, 100, 1, "")
        local seen = addon.Notify.MarkSeen(orders, nil)
        orders:Claim(o.id, "Mira Holt")
        local fresh, prev = addon.Notify.Fresh(nil, addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF))
        harness.equal(#fresh, 1)
        fresh, prev = addon.Notify.Fresh(prev, addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF))
        harness.equal(#fresh, 0)
        harness.clock = harness.clock + 1
        orders:Claim(o.id, "Orin Vale")
        fresh = addon.Notify.Fresh(prev, addon.Notify.Unseen(addon.Store, orders, ME, seen, PROF))
        harness.equal(#fresh, 1)
    end,

    ["notify: mark seen forgets pruned orders and ignores garbage"] = function(harness)
        local addon, orders = setup(harness, {})
        local seen = addon.Notify.MarkSeen(orders, { gone = "open" })
        harness.equal(seen.gone, nil)
        harness.equal(type(addon.Notify.MarkSeen(orders, "garbage")), "table")
        harness.equal(#addon.Notify.Unseen(addon.Store, orders, ME, "garbage", ALL), 0)
    end,
}
