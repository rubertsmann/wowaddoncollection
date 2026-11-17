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
local function newBus(harness, opts)
    local bus = { peers = {}, queue = {}, opts = opts or {} }
    function bus.peer(name)
        local addon = harness.addon()
        addon.Store.db.me = name
        local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
        local p = { name = name, addon = addon, orders = orders }
        p.sync = addon.Sync.New({
            send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
            now = function() return harness.clock end, random = function() return 0.5 end,
            store = addon.Store, orders = orders, me = name, onChange = function() end,
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
            local wire = bus.peers[item.from].addon.Codec.Encode(item.msg)
            for name, p in pairs(bus.peers) do
                local to = (item.dist == "GUILD" and name ~= item.from)
                    or (item.dist == "WHISPER" and name == item.target and not bus.opts.dropWhisper)
                if to then p.sync:OnMessage(assert(p.addon.Codec.Decode(wire)), item.from) end
            end
        end
    end
    function bus.advance(seconds)
        for _ = 1, seconds do
            harness.clock = harness.clock + 1
            for _, p in pairs(bus.peers) do p.sync:Tick(harness.clock) end
            bus.pump()
        end
    end
    return bus
end

return {
    ---------------------------------------------------------------- R1 canonical names
    ["canon: every spelling of my realm becomes my normalized realm; other realms stay distinct"] = function(harness)
        withRealm("DieAldor", function()
            local U = harness.addon().Utility
            harness.equal(U.CanonicalName("Bob"), "Bob-DieAldor")
            harness.equal(U.CanonicalName("Bob-DieAldor"), "Bob-DieAldor")
            harness.equal(U.CanonicalName("Bob-Die Aldor"), "Bob-DieAldor")
            harness.equal(U.CanonicalName("Bob-diealdor"), "Bob-DieAldor")
            harness.equal(U.CanonicalName("Bob-Die'Aldor"), "Bob-DieAldor")
            harness.equal(U.CanonicalName("Bob-Other Realm"), "Bob-OtherRealm")
            harness.equal(U.CanonicalName(""), nil); harness.equal(U.CanonicalName(nil), nil); harness.equal(U.CanonicalName(5), nil)
        end)
    end,

    ["canon: the roster's spelling of MY character teaches a realm alias (only when unambiguous)"] = function(harness)
        withRealm("Forever", function()
            local U = harness.addon().Utility
            harness.equal(U.CanonicalName("Bob-WoWForever"), "Bob-WoWForever")
            harness.equal(U.LearnFromRoster({ "Alice-WoWForever", "Me-WoW Forever", "Bob-WoWForever" }, "Me"), true)
            harness.equal(U.CanonicalName("Bob-WoWForever"), "Bob-Forever")
            harness.equal(U.WhisperTarget("Bob-WoWForever"), "Bob")      -- R2: any spelling of my realm is whispered by name
            harness.equal(U.LearnFromRoster({ "Me-WoWForever" }, "Me"), false)   -- already known
            local V = harness.addon().Utility
            harness.equal(V.LearnFromRoster({ "Me-RealmA", "Me-RealmB" }, "Me"), false)   -- two "Me": learn nothing
            harness.equal(V.LearnFromRoster({ "Me" }, "Me"), false)                       -- bare name: nothing to learn
            harness.equal(V.CanonicalName("Bob-RealmA"), "Bob-RealmA")
        end)
    end,

    ["canon: stored data is re-keyed; duplicates keep the newer record; orders and dibs follow"] = function(harness)
        withRealm("Forever", function()
            local addon = harness.addon()
            local S = addon.Store
            S.db.me = "Me-WoWForever"
            S.db.chars["Bob-WoWForever"] = harness.character("Bob-WoWForever", 10, { 1 })
            S.db.chars["Bob-Forever"] = harness.character("Bob-Forever", 20, { 1, 2 })
            S.db.chars["Ann-WoWForever"] = harness.character("Ann-WoWForever", 5, { 3 })
            S.db.offers["Ann-WoWForever"] = { name = "Ann-WoWForever", rev = 3, items = {}, dibs = { ["Bob-WoWForever:77"] = { on = true, t = 1 } } }
            S.db.hidden["Bob-WoWForever:77"] = 9
            S.db.orders["x"] = { id = "x", requester = "Ann-WoWForever", recipeID = 1, qty = 1, note = "", createdAt = 1,
                closed = "done", closedAt = 2, closedBy = "Bob-WoWForever", claims = { ["Bob-WoWForever"] = { state = "claimed", t = 1 } } }
            addon.Utility.LearnMyRealm("WoWForever")
            harness.truthy(S.CanonicalizeStoredNames() > 0)
            harness.equal(S.db.me, "Me-Forever")
            harness.equal(S.db.chars["Bob-WoWForever"], nil)
            harness.equal(S.db.chars["Bob-Forever"].rev, 20)
            harness.equal(S.db.chars["Ann-Forever"].name, "Ann-Forever")
            harness.truthy(S.db.offers["Ann-Forever"].dibs["Bob-Forever:77"])
            harness.equal(S.db.hidden["Bob-Forever:77"], 9)
            local o = S.db.orders["x"]
            harness.equal(o.requester, "Ann-Forever"); harness.equal(o.closedBy, "Bob-Forever"); harness.truthy(o.claims["Bob-Forever"])
            harness.equal(S.CanonicalizeStoredNames(), 0)   -- idempotent
        end)
    end,

    ["canon: requests, records and orders in another spelling of a realm meet on one key"] = function(harness)
        withRealm("Forever", function()
            local bus = newBus(harness)
            local a, b = bus.peer("A-Forever"), bus.peer("B-Forever")
            a.addon.Utility.LearnMyRealm("WoWForever")
            b.addon.Utility.LearnMyRealm("WoWForever")
            a.addon.Store.PutCharacter(harness.character("A-Forever", 50, { 1 }))
            -- B asks for A in the other spelling: A answers
            local st = a.sync:OnMessage({ v = 2, t = "WANT", names = { "A-WoWForever" } }, "B-Forever")
            harness.equal(st, "ok")
            -- a record whose name uses the other spelling is accepted from the canonical sender and stored canonically
            st = b.sync:OnMessage({ v = 2, t = "SNAP", char = harness.character("A-WoWForever", 50, { 1 }), catalog = {} }, "A-Forever")
            harness.equal(st, "ok"); harness.truthy(b.addon.Store.GetCharacter("A-Forever"))
            -- an order from a peer spelling names differently is stored with canonical names
            b.sync:OnMessage({ v = 2, t = "ORDER", order = { id = "o1", requester = "A-WoWForever", recipeID = 1, qty = 1,
                createdAt = harness.clock, claims = { ["B-WoWForever"] = { state = "claimed", t = harness.clock } } } }, "A-Forever")
            local o = b.orders:Get("o1")
            harness.equal(o.requester, "A-Forever"); harness.truthy(o.claims["B-Forever"])
        end)
    end,

    ["canon: my own GUILD echo teaches the server's spelling of my realm"] = function(harness)
        withRealm("Forever", function()
            local addon = harness.addon()
            addon.Store.db.me = "Me-Forever"
            addon.Api = { GetPlayerInformation = function() return { name = "Me-Forever" } end }
            local C = addon.Communication
            C.salt = 0xab12
            local mine = addon.Codec.Header(("%04x%x"):format(C.salt, 7), 1, 1) .. "x"
            local other = addon.Codec.Header("ffff1", 1, 1) .. "x"
            harness.equal(C.LearnFromEcho(other, "Me-WoWForever"), false)        -- not my salt: no proof it is me
            harness.equal(addon.Utility.CanonicalName("X-WoWForever"), "X-WoWForever")
            harness.equal(C.LearnFromEcho(mine, "Me-WoWForever"), true)
            harness.equal(addon.Utility.CanonicalName("X-WoWForever"), "X-Forever")
            harness.equal(C.LearnFromEcho(mine, "Someone-WoWForever"), false)   -- my salt but not my name: not learned
            -- a WHISPER is never treated as an echo (an outsider could forge the header)
            local W = harness.addon()
            W.Store.db.me = "Me-Forever"
            W.Communication.salt, W.Communication.active, W.Communication.roster = 0xab12, true, {}
            W.Communication.OnAddonMessage(W.PREFIX, mine, "WHISPER", "Me-EvilRealm")
            harness.equal(W.Utility.CanonicalName("X-EvilRealm"), "X-EvilRealm")
        end)
    end,

    ---------------------------------------------------------------- R3 + R6 retry with GUILD fallback
    ["retry: an unanswered WANT is repeated on GUILD, answered on GUILD, then given up"] = function(harness)
        local bus = newBus(harness)
        local a = bus.peer("A-R")
        local sent = {}
        a.sync.environment.send = function(msg, dist) sent[#sent + 1] = { t = msg.t, dist = dist, via = msg.via } end
        a.sync:OnMessage({ v = 2, t = "HELLO", rev = 50 }, "B-R")
        harness.equal(sent[1].t, "WANT"); harness.equal(sent[1].dist, "WHISPER")
        local start = harness.clock
        a.sync:Tick(start + 44); harness.equal(#sent, 1)
        a.sync:Tick(start + 45); harness.equal(sent[2].dist, "GUILD"); harness.equal(sent[2].via, "GUILD")
        a.sync:Tick(start + 45 + 90); harness.equal(sent[3].dist, "GUILD")
        a.sync:Tick(start + 45 + 90 + 180); harness.equal(#sent, 3); harness.truthy(a.sync.wanted["B-R"].gaveUp)
        harness.equal(a.addon.Trace.List("problems")[1].mt, "WANT")
        -- a repeated HELLO does not restart a pull that just gave up ...
        a.sync:OnMessage({ v = 2, t = "HELLO", rev = 50 }, "B-R"); harness.equal(#sent, 3)
        -- ... but does after GIVE_UP_RESET
        harness.clock = start + 45 + 90 + 180 + a.addon.Sync.GIVE_UP_RESET_SECONDS
        a.sync:OnMessage({ v = 2, t = "HELLO", rev = 50 }, "B-R"); harness.equal(#sent, 4)
        -- an arrived record ends the pull
        a.addon.Store.PutCharacter(harness.character("B-R", 50, { 1 }))
        a.sync:Tick(harness.clock + 1000); harness.equal(a.sync.wanted["B-R"], nil); harness.equal(#sent, 4)
    end,

    ["retry: a GUILD request is answered once per rev on GUILD; requests for others are ignored quietly"] = function(harness)
        local bus = newBus(harness)
        local b = bus.peer("B-R")
        b.addon.Store.PutCharacter(harness.character("B-R", 50, { 1 }))
        local st = b.sync:OnMessage({ v = 2, t = "WANT", names = { "B-R" }, via = "GUILD" }, "A-R")
        harness.equal(st, "ok"); harness.equal(b.sync.pending[1].channel, "GUILD")
        local st2, why2 = b.sync:OnMessage({ v = 2, t = "WANT", names = { "B-R" }, via = "GUILD" }, "C-R")
        harness.equal(st2, "ignored"); harness.truthy(why2:find("already broadcast", 1, true), why2)
        harness.equal(#b.sync.pending, 1)
        local st3, why3 = b.sync:OnMessage({ v = 2, t = "WANT", names = { "Z-R" }, via = "GUILD" }, "A-R")
        harness.equal(st3, "ignored"); harness.truthy(not why3:find("mismatch", 1, true), why3)
    end,

    ["retry: with every whisper lost, records and offers still converge over GUILD"] = function(harness)
        local bus = newBus(harness, { dropWhisper = true })
        local a, b, c = bus.peer("A-R"), bus.peer("B-R"), bus.peer("C-R")
        a.addon.Store.PutCharacter(harness.character("A-R", 50, { 1, 2 }))
        a.addon.Store.PutCatalog({ [1] = { name = "R1", reagents = {} } })
        a.addon.Offers.Put({ name = "A-R", rev = 40, items = { [777] = { bag = 1 } }, dibs = {} })
        a.sync:Hello(false)
        bus.pump()
        harness.equal(b.addon.Store.GetCharacter("A-R"), nil)   -- the whispered pull got lost
        bus.advance(60)
        for _, p in ipairs({ b, c }) do
            harness.equal(p.addon.Store.GetCharacter("A-R").rev, 50)
            harness.equal(p.addon.Store.GetRecipe(1).name, "R1")
            harness.equal(p.addon.Offers.Get("A-R").rev, 40)
        end
        -- one GUILD SNAP served both B and C (their GUILD requests for the same rev were deduplicated)
        local snaps, guildWants = 0, 0
        for _, item in ipairs(bus.log) do
            if item.msg.t == "SNAP" and item.dist == "GUILD" then snaps = snaps + 1 end
            if item.msg.t == "WANT" and item.dist == "GUILD" then guildWants = guildWants + 1 end
        end
        harness.equal(guildWants, 2); harness.equal(snaps, 1)
    end,

    ---------------------------------------------------------------- R5 recipe name snapshot in orders
    ["orders: the recipe name travels with the order and is shown without a catalog entry"] = function(harness)
        local addon = harness.addon()
        local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
        local o = orders:Create("A-R", 1263067, 1, "", "Eisenofen", "deDE")
        harness.equal(o.name, "Eisenofen"); harness.equal(o.loc, "deDE")
        harness.equal(addon.Orders.Sanitize({ id = "x", requester = "A-R", recipeID = 1, qty = 1, createdAt = 1, claims = {}, name = "a|cffbad" }), nil)
        harness.equal(addon.Orders.Sanitize({ id = "x", requester = "A-R", recipeID = 1, qty = 1, createdAt = 1, claims = {}, name = "ok", loc = "../" }), nil)
        -- a 2.1 peer's copy without the name is completed by a 2.2 copy
        local other = addon.Orders.New(function() return harness.clock end, {})
        local bare = addon.Utility.DeepCopy(o); bare.name, bare.loc = nil, nil
        other:Merge(bare)
        harness.equal(other:Get(o.id).name, nil)
        harness.equal(other:Merge(o), true); harness.equal(other:Get(o.id).name, "Eisenofen")
        -- display: snapshot when there is no catalog entry, catalog when there is
        harness.equal(addon.Model.OrderRecipeName(addon.Store, o), "Eisenofen")
        addon.Store.PutCatalog({ [1263067] = { name = "Iron Oven", loc = "enUS", reagents = {} } })
        harness.equal(addon.Model.OrderRecipeName(addon.Store, o), "Iron Oven")
    end,
}
