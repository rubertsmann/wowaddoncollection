-- Feature 008 follow-up (analysis R1, R2, R3, R5, R6): canonical names, retry with GUILD fallback, order name snapshot.

-- runs fn with GetNormalizedRealmName returning `realm` (and no Ambiguate / GetRealmName), restoring the globals after
local function withRealm(realm, fn)
    local saved = { GetNormalizedRealmName, Ambiguate, GetRealmName }
    GetNormalizedRealmName = realm and function() return realm end or nil
    Ambiguate, GetRealmName = nil, nil
    local ok, err = pcall(fn)
    GetNormalizedRealmName, Ambiguate, GetRealmName = saved[1], saved[2], saved[3]
    if not ok then error(err, 0) end
end

-- in-memory guild: GUILD reaches everyone else, WHISPER only the target; `dropWhisper` simulates a broken whisper path
local function newBus(h, opts)
    local bus = { peers = {}, queue = {}, opts = opts or {} }
    function bus.peer(name)
        local ns = h.ns()
        ns.Store.db.me = name
        local orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
        local p = { name = name, ns = ns, orders = orders }
        p.sync = ns.Sync.New({
            send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
            now = function() return h.clock end, rand = function() return 0.5 end,
            store = ns.Store, orders = orders, me = name, onChange = function() end,
        })
        bus.peers[name] = p
        return p
    end
    function bus.pump()
        local guard = 0
        while #bus.queue > 0 and guard < 5000 do
            guard = guard + 1
            local item = table.remove(bus.queue, 1)
            bus.log = bus.log or {}
            bus.log[#bus.log + 1] = item
            local wire = bus.peers[item.from].ns.Codec.Encode(item.msg)
            for name, p in pairs(bus.peers) do
                local to = (item.dist == "GUILD" and name ~= item.from)
                    or (item.dist == "WHISPER" and name == item.target and not bus.opts.dropWhisper)
                if to then p.sync:OnMessage(assert(p.ns.Codec.Decode(wire)), item.from) end
            end
        end
    end
    function bus.advance(seconds)
        for _ = 1, seconds do
            h.clock = h.clock + 1
            for _, p in pairs(bus.peers) do p.sync:Tick(h.clock) end
            bus.pump()
        end
    end
    return bus
end

return {
    ---------------------------------------------------------------- R1 canonical names
    ["canon: every spelling of my realm becomes my normalized realm; other realms stay distinct"] = function(h)
        withRealm("DieAldor", function()
            local U = h.ns().Util
            h.eq(U.Canon("Bob"), "Bob-DieAldor")
            h.eq(U.Canon("Bob-DieAldor"), "Bob-DieAldor")
            h.eq(U.Canon("Bob-Die Aldor"), "Bob-DieAldor")
            h.eq(U.Canon("Bob-diealdor"), "Bob-DieAldor")
            h.eq(U.Canon("Bob-Die'Aldor"), "Bob-DieAldor")
            h.eq(U.Canon("Bob-Other Realm"), "Bob-OtherRealm")
            h.eq(U.Canon(""), nil); h.eq(U.Canon(nil), nil); h.eq(U.Canon(5), nil)
        end)
    end,

    ["canon: the roster's spelling of MY character teaches a realm alias (only when unambiguous)"] = function(h)
        withRealm("Forever", function()
            local U = h.ns().Util
            h.eq(U.Canon("Bob-WoWForever"), "Bob-WoWForever")
            h.eq(U.LearnFromRoster({ "Alice-WoWForever", "Me-WoW Forever", "Bob-WoWForever" }, "Me"), true)
            h.eq(U.Canon("Bob-WoWForever"), "Bob-Forever")
            h.eq(U.WhisperTarget("Bob-WoWForever"), "Bob")      -- R2: any spelling of my realm is whispered by name
            h.eq(U.LearnFromRoster({ "Me-WoWForever" }, "Me"), false)   -- already known
            local V = h.ns().Util
            h.eq(V.LearnFromRoster({ "Me-RealmA", "Me-RealmB" }, "Me"), false)   -- two "Me": learn nothing
            h.eq(V.LearnFromRoster({ "Me" }, "Me"), false)                       -- bare name: nothing to learn
            h.eq(V.Canon("Bob-RealmA"), "Bob-RealmA")
        end)
    end,

    ["canon: stored data is re-keyed; duplicates keep the newer record; orders and dibs follow"] = function(h)
        withRealm("Forever", function()
            local ns = h.ns()
            local S = ns.Store
            S.db.me = "Me-WoWForever"
            S.db.chars["Bob-WoWForever"] = h.char("Bob-WoWForever", 10, { 1 })
            S.db.chars["Bob-Forever"] = h.char("Bob-Forever", 20, { 1, 2 })
            S.db.chars["Ann-WoWForever"] = h.char("Ann-WoWForever", 5, { 3 })
            S.db.offers["Ann-WoWForever"] = { name = "Ann-WoWForever", rev = 3, items = {}, dibs = { ["Bob-WoWForever:77"] = { on = true, t = 1 } } }
            S.db.hidden["Bob-WoWForever:77"] = 9
            S.db.orders["x"] = { id = "x", requester = "Ann-WoWForever", recipeID = 1, qty = 1, note = "", createdAt = 1,
                closed = "done", closedAt = 2, closedBy = "Bob-WoWForever", claims = { ["Bob-WoWForever"] = { state = "claimed", t = 1 } } }
            ns.Util.LearnMyRealm("WoWForever")
            h.truthy(S.Recanon() > 0)
            h.eq(S.db.me, "Me-Forever")
            h.eq(S.db.chars["Bob-WoWForever"], nil)
            h.eq(S.db.chars["Bob-Forever"].rev, 20)
            h.eq(S.db.chars["Ann-Forever"].name, "Ann-Forever")
            h.truthy(S.db.offers["Ann-Forever"].dibs["Bob-Forever:77"])
            h.eq(S.db.hidden["Bob-Forever:77"], 9)
            local o = S.db.orders["x"]
            h.eq(o.requester, "Ann-Forever"); h.eq(o.closedBy, "Bob-Forever"); h.truthy(o.claims["Bob-Forever"])
            h.eq(S.Recanon(), 0)   -- idempotent
        end)
    end,

    ["canon: requests, records and orders in another spelling of a realm meet on one key"] = function(h)
        withRealm("Forever", function()
            local bus = newBus(h)
            local a, b = bus.peer("A-Forever"), bus.peer("B-Forever")
            a.ns.Util.LearnMyRealm("WoWForever")
            b.ns.Util.LearnMyRealm("WoWForever")
            a.ns.Store.PutChar(h.char("A-Forever", 50, { 1 }))
            -- B asks for A in the other spelling: A answers
            local st = a.sync:OnMessage({ v = 2, t = "WANT", names = { "A-WoWForever" } }, "B-Forever")
            h.eq(st, "ok")
            -- a record whose name uses the other spelling is accepted from the canonical sender and stored canonically
            st = b.sync:OnMessage({ v = 2, t = "SNAP", char = h.char("A-WoWForever", 50, { 1 }), catalog = {} }, "A-Forever")
            h.eq(st, "ok"); h.truthy(b.ns.Store.GetChar("A-Forever"))
            -- an order from a peer spelling names differently is stored with canonical names
            b.sync:OnMessage({ v = 2, t = "ORDER", order = { id = "o1", requester = "A-WoWForever", recipeID = 1, qty = 1,
                createdAt = h.clock, claims = { ["B-WoWForever"] = { state = "claimed", t = h.clock } } } }, "A-Forever")
            local o = b.orders:Get("o1")
            h.eq(o.requester, "A-Forever"); h.truthy(o.claims["B-Forever"])
        end)
    end,

    ["canon: my own GUILD echo teaches the server's spelling of my realm"] = function(h)
        withRealm("Forever", function()
            local ns = h.ns()
            ns.Store.db.me = "Me-Forever"
            ns.Api = { GetPlayerInfo = function() return { name = "Me-Forever" } end }
            local C = ns.Comm
            C.salt = 0xab12
            local mine = ns.Codec.Header(("%04x%x"):format(C.salt, 7), 1, 1) .. "x"
            local other = ns.Codec.Header("ffff1", 1, 1) .. "x"
            h.eq(C.LearnFromEcho(other, "Me-WoWForever"), false)        -- not my salt: no proof it is me
            h.eq(ns.Util.Canon("X-WoWForever"), "X-WoWForever")
            h.eq(C.LearnFromEcho(mine, "Me-WoWForever"), true)
            h.eq(ns.Util.Canon("X-WoWForever"), "X-Forever")
            h.eq(C.LearnFromEcho(mine, "Someone-WoWForever"), false)   -- my salt but not my name: not learned
            -- a WHISPER is never treated as an echo (an outsider could forge the header)
            local W = h.ns()
            W.Store.db.me = "Me-Forever"
            W.Comm.salt, W.Comm.active, W.Comm.roster = 0xab12, true, {}
            W.Comm.OnAddonMessage(W.PREFIX, mine, "WHISPER", "Me-EvilRealm")
            h.eq(W.Util.Canon("X-EvilRealm"), "X-EvilRealm")
        end)
    end,

    ---------------------------------------------------------------- R3 + R6 retry with GUILD fallback
    ["retry: an unanswered WANT is repeated on GUILD, answered on GUILD, then given up"] = function(h)
        local bus = newBus(h)
        local a = bus.peer("A-R")
        local sent = {}
        a.sync.env.send = function(msg, dist) sent[#sent + 1] = { t = msg.t, dist = dist, via = msg.via } end
        a.sync:OnMessage({ v = 2, t = "HELLO", rev = 50 }, "B-R")
        h.eq(sent[1].t, "WANT"); h.eq(sent[1].dist, "WHISPER")
        local start = h.clock
        a.sync:Tick(start + 44); h.eq(#sent, 1)
        a.sync:Tick(start + 45); h.eq(sent[2].dist, "GUILD"); h.eq(sent[2].via, "GUILD")
        a.sync:Tick(start + 45 + 90); h.eq(sent[3].dist, "GUILD")
        a.sync:Tick(start + 45 + 90 + 180); h.eq(#sent, 3); h.truthy(a.sync.wanted["B-R"].done)
        h.eq(a.ns.Trace.List("problems")[1].mt, "WANT")
        -- a repeated HELLO does not restart a pull that just gave up ...
        a.sync:OnMessage({ v = 2, t = "HELLO", rev = 50 }, "B-R"); h.eq(#sent, 3)
        -- ... but does after GIVE_UP_RESET
        h.clock = start + 45 + 90 + 180 + a.ns.Sync.GIVE_UP_RESET
        a.sync:OnMessage({ v = 2, t = "HELLO", rev = 50 }, "B-R"); h.eq(#sent, 4)
        -- an arrived record ends the pull
        a.ns.Store.PutChar(h.char("B-R", 50, { 1 }))
        a.sync:Tick(h.clock + 1000); h.eq(a.sync.wanted["B-R"], nil); h.eq(#sent, 4)
    end,

    ["retry: a GUILD request is answered once per rev on GUILD; requests for others are ignored quietly"] = function(h)
        local bus = newBus(h)
        local b = bus.peer("B-R")
        b.ns.Store.PutChar(h.char("B-R", 50, { 1 }))
        local st = b.sync:OnMessage({ v = 2, t = "WANT", names = { "B-R" }, via = "GUILD" }, "A-R")
        h.eq(st, "ok"); h.eq(b.sync.pending[1].dist, "GUILD")
        local st2, why2 = b.sync:OnMessage({ v = 2, t = "WANT", names = { "B-R" }, via = "GUILD" }, "C-R")
        h.eq(st2, "ignored"); h.truthy(why2:find("already broadcast", 1, true), why2)
        h.eq(#b.sync.pending, 1)
        local st3, why3 = b.sync:OnMessage({ v = 2, t = "WANT", names = { "Z-R" }, via = "GUILD" }, "A-R")
        h.eq(st3, "ignored"); h.truthy(not why3:find("mismatch", 1, true), why3)
    end,

    ["retry: with every whisper lost, records and offers still converge over GUILD"] = function(h)
        local bus = newBus(h, { dropWhisper = true })
        local a, b, c = bus.peer("A-R"), bus.peer("B-R"), bus.peer("C-R")
        a.ns.Store.PutChar(h.char("A-R", 50, { 1, 2 }))
        a.ns.Store.PutCatalog({ [1] = { name = "R1", reagents = {} } })
        a.ns.Offers.Put({ name = "A-R", rev = 40, items = { [777] = { bag = 1 } }, dibs = {} })
        a.sync:Hello(false)
        bus.pump()
        h.eq(b.ns.Store.GetChar("A-R"), nil)   -- the whispered pull got lost
        bus.advance(60)
        for _, p in ipairs({ b, c }) do
            h.eq(p.ns.Store.GetChar("A-R").rev, 50)
            h.eq(p.ns.Store.GetRecipe(1).name, "R1")
            h.eq(p.ns.Offers.Get("A-R").rev, 40)
        end
        -- one GUILD SNAP served both B and C (their GUILD requests for the same rev were deduplicated)
        local snaps, guildWants = 0, 0
        for _, item in ipairs(bus.log) do
            if item.msg.t == "SNAP" and item.dist == "GUILD" then snaps = snaps + 1 end
            if item.msg.t == "WANT" and item.dist == "GUILD" then guildWants = guildWants + 1 end
        end
        h.eq(guildWants, 2); h.eq(snaps, 1)
    end,

    ---------------------------------------------------------------- R5 recipe name snapshot in orders
    ["orders: the recipe name travels with the order and is shown without a catalog entry"] = function(h)
        local ns = h.ns()
        local orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
        local o = orders:Create("A-R", 1263067, 1, "", "Eisenofen", "deDE")
        h.eq(o.name, "Eisenofen"); h.eq(o.loc, "deDE")
        h.eq(ns.Orders.Sanitize({ id = "x", requester = "A-R", recipeID = 1, qty = 1, createdAt = 1, claims = {}, name = "a|cffbad" }), nil)
        h.eq(ns.Orders.Sanitize({ id = "x", requester = "A-R", recipeID = 1, qty = 1, createdAt = 1, claims = {}, name = "ok", loc = "../" }), nil)
        -- a 2.1 peer's copy without the name is completed by a 2.2 copy
        local other = ns.Orders.New(function() return h.clock end, {})
        local bare = ns.Util.DeepCopy(o); bare.name, bare.loc = nil, nil
        other:Merge(bare)
        h.eq(other:Get(o.id).name, nil)
        h.eq(other:Merge(o), true); h.eq(other:Get(o.id).name, "Eisenofen")
        -- display: snapshot when there is no catalog entry, catalog when there is
        h.eq(ns.Model.OrderRecipeName(ns.Store, o), "Eisenofen")
        ns.Store.PutCatalog({ [1263067] = { name = "Iron Oven", loc = "enUS", reagents = {} } })
        h.eq(ns.Model.OrderRecipeName(ns.Store, o), "Iron Oven")
    end,
}
