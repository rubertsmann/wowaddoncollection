-- Feature 010: notifications about new orders (pure part: relevance, unseen, seen, fresh, settings).
local ME = "Me Holt"

local function prof(name, id, recipes)
    local set = {}
    for _, r in ipairs(recipes) do set[r] = true end
    return { name = name, id = id, rank = 50, max = 300, recipes = set }
end

local function setup(h, myProfs)
    local ns = h.ns()
    ns.Store.PutChar({ name = ME, class = "MAGE", level = 60, rev = 1, professions = myProfs })
    ns.Store.PutChar({ name = "Mira Holt", class = "MAGE", level = 60, rev = 1, professions = {
        Cooking = prof("Cooking", 185, { 100, 101 }), Tailoring = prof("Tailoring", 197, { 300 }) } })
    local orders = ns.Orders.New(function() return h.clock end, {})
    return ns, orders
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
    ["notify: settings fall back to defaults, bad values are ignored"] = function(h)
        local ns = h.ns()
        local N = ns.Notify
        h.eq(N.Get(nil, "sound"), true)
        h.eq(N.Get({ notify = { sound = false } }, "sound"), false)
        h.eq(N.Get({ notify = { sound = "yes" } }, "sound"), true)
        h.eq(N.Get({ notify = { scope = "evil" } }, "scope"), "profession")
        h.eq(N.Get({ notify = { soundName = "PlaySoundFile('x')" } }, "soundName"), "IG_PLAYER_INVITE")
        h.eq(N.Get({ notify = { soundName = "MAP_PING" } }, "soundName"), "MAP_PING")
        local ui = {}
        N.Set(ui, "screen", true); N.Set(ui, "nonsense", true)
        h.eq(ui.notify.screen, true); h.eq(ui.notify.nonsense, nil)
    end,

    ["notify: only orders for my profession count (scope profession)"] = function(h)
        local ns, orders = setup(h, { Cooking = prof("Cooking", 185, { 100 }) })
        orders:Create("Mira Holt", 101, 1, "")   -- Cooking, I do not know it yet: relevant
        orders:Create("Mira Holt", 300, 1, "")   -- Tailoring: not relevant
        h.eq(ids(ns.Notify.Unseen(ns.Store, orders, ME, {}, PROF)), "new:101")
        h.eq(ids(ns.Notify.Unseen(ns.Store, orders, ME, {}, KNOWN)), "")
        h.eq(#ns.Notify.Unseen(ns.Store, orders, ME, {}, ALL), 2)
    end,

    ["notify: without any profession nothing is relevant"] = function(h)
        local ns, orders = setup(h, {})
        orders:Create("Mira Holt", 101, 1, "")
        h.eq(#ns.Notify.Unseen(ns.Store, orders, ME, {}, PROF), 0)
    end,

    ["notify: profession match works across languages (skill line id)"] = function(h)
        local ns, orders = setup(h, { Kochkunst = prof("Kochkunst", 185, {}) })
        orders:Create("Mira Holt", 101, 1, "")
        h.eq(ids(ns.Notify.Unseen(ns.Store, orders, ME, {}, PROF)), "new:101")
    end,

    ["notify: my own new order, claimed or closed orders of others are not new"] = function(h)
        local ns, orders = setup(h, { Cooking = prof("Cooking", 185, { 100 }) })
        orders:Create(ME, 100, 1, "")
        local o2 = orders:Create("Mira Holt", 100, 1, ""); orders:Claim(o2.id, "Orin Vale")
        local o3 = orders:Create("Mira Holt", 100, 1, ""); orders:Close(o3.id, "Mira Holt", "cancelled")
        h.eq(#ns.Notify.Unseen(ns.Store, orders, ME, {}, PROF), 0)
    end,

    ["notify: seen orders stay seen, a new one appears"] = function(h)
        local ns, orders = setup(h, { Cooking = prof("Cooking", 185, { 100 }) })
        orders:Create("Mira Holt", 100, 1, "")
        local seen = ns.Notify.MarkSeen(orders, nil)
        h.eq(#ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF), 0)
        h.clock = h.clock + 5
        orders:Create("Mira Holt", 101, 2, "")
        h.eq(ids(ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF)), "new:101")
    end,

    ["notify: my order claimed or done by someone else is news, by me it is not"] = function(h)
        local ns, orders = setup(h, { Cooking = prof("Cooking", 185, { 100 }) })
        local o = orders:Create(ME, 100, 1, "")
        local seen = ns.Notify.MarkSeen(orders, nil)
        orders:Claim(o.id, ME)
        h.eq(#ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF), 0)
        h.clock = h.clock + 1
        orders:Claim(o.id, "Mira Holt")
        h.eq(ids(ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF)), "claimed:100")
        h.eq(#ns.Notify.Unseen(ns.Store, orders, ME, seen, { scope = "profession", mine = false }), 0)
        seen = ns.Notify.MarkSeen(orders, seen)
        h.clock = h.clock + 1
        orders:Close(o.id, "Mira Holt", "done")
        h.eq(ids(ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF)), "done:100")
    end,

    ["notify: fresh reports each item once, a new claimer again"] = function(h)
        local ns, orders = setup(h, { Cooking = prof("Cooking", 185, { 100 }) })
        local o = orders:Create(ME, 100, 1, "")
        local seen = ns.Notify.MarkSeen(orders, nil)
        orders:Claim(o.id, "Mira Holt")
        local fresh, prev = ns.Notify.Fresh(nil, ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF))
        h.eq(#fresh, 1)
        fresh, prev = ns.Notify.Fresh(prev, ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF))
        h.eq(#fresh, 0)
        h.clock = h.clock + 1
        orders:Claim(o.id, "Orin Vale")
        fresh = ns.Notify.Fresh(prev, ns.Notify.Unseen(ns.Store, orders, ME, seen, PROF))
        h.eq(#fresh, 1)
    end,

    ["notify: mark seen forgets pruned orders and ignores garbage"] = function(h)
        local ns, orders = setup(h, {})
        local seen = ns.Notify.MarkSeen(orders, { gone = "open" })
        h.eq(seen.gone, nil)
        h.eq(type(ns.Notify.MarkSeen(orders, "garbage")), "table")
        h.eq(#ns.Notify.Unseen(ns.Store, orders, ME, "garbage", ALL), 0)
    end,
}
