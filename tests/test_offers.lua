-- Recipe items board (feature 007): offers records, dibs, local hide, validation, persistence, sync over the codec.
local BIG = 1700000000   -- a realistic server time, so "timestamp from the future" is decidable

local function fresh(h, me, now)
    local ns = h.ns({ now = now or BIG })
    ns.Store.db.me = me or "Me-R"
    return ns
end

local function item(count, loc) return { [loc or "bag"] = count or 1 } end

local function peer(h, bus, name, seed)
    local ns = fresh(h, name)
    local orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
    local rng = seed
    local p = { name = name, ns = ns, changes = 0 }
    p.sync = ns.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return h.clock end,
        rand = function() rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648 end,
        store = ns.Store, orders = orders, me = name,
        onChange = function() p.changes = p.changes + 1 end,
    })
    bus.peers[name] = p
    return p
end

local function pump(bus)
    local guard = 0
    while #bus.queue > 0 and guard < 2000 do
        guard = guard + 1
        local it = table.remove(bus.queue, 1)
        local wire = bus.peers[it.from].ns.Codec.Encode(it.msg)
        for name, p in pairs(bus.peers) do
            local to = (it.dist == "GUILD" and name ~= it.from) or (it.dist == "WHISPER" and name == it.target)
            if to then p.sync:OnMessage(assert(p.ns.Codec.Decode(wire)), it.from) end
        end
    end
end

local function advance(h, bus, seconds)
    for _ = 1, seconds do
        h.clock = h.clock + 1
        for _, p in pairs(bus.peers) do p.sync:Tick(h.clock) end
        pump(bus)
    end
end

local function bus() return { peers = {}, queue = {} } end

return {
    ["offers: update builds my record, an identical scan changes nothing, a new item bumps rev"] = function(h)
        local ns = fresh(h)
        h.truthy(ns.Offers.Update("Me-R", { bag = { [6661] = 2 } }, h.clock))
        local rec = ns.Offers.Get("Me-R")
        h.eq(rec.items[6661].bag, 2); h.eq(rec.rev, h.clock)
        h.eq(ns.Offers.Update("Me-R", { bag = { [6661] = 2 } }, h.clock + 5), false)
        h.eq(ns.Offers.Get("Me-R").rev, h.clock)
        h.truthy(ns.Offers.Update("Me-R", { bag = { [6661] = 2, [6662] = 1 } }, h.clock + 5))
        h.eq(ns.Offers.Get("Me-R").rev, h.clock + 5)
    end,

    ["offers: an empty first scan creates no record; rev never goes backwards (RF1)"] = function(h)
        local ns = fresh(h)
        h.eq(ns.Offers.Update("Me-R", { bag = {} }, h.clock), false)
        h.eq(ns.Offers.Get("Me-R"), nil)
        ns.Offers.Update("Me-R", { bag = { [1] = 1 } }, h.clock)
        ns.Offers.Update("Me-R", { bag = {} }, h.clock - 100)   -- clock went back: rev still grows
        h.truthy(ns.Offers.Get("Me-R").rev > h.clock)
    end,

    ["offers: update keeps locations that were not scanned and replaces the ones that were (RF1)"] = function(h)
        local ns = fresh(h)
        ns.Offers.Update("Me-R", { bag = { [1] = 1 }, bank = { [1] = 1, [2] = 3 }, gbank2 = { [9] = 1 } }, h.clock)
        ns.Offers.Update("Me-R", { bag = {} }, h.clock + 1)            -- bank/mail/gbank not readable now
        local it = ns.Offers.Get("Me-R").items
        h.eq(it[1].bag, nil); h.eq(it[1].bank, 1); h.eq(it[2].bank, 3); h.eq(it[9].gbank2, 1)
        ns.Offers.Update("Me-R", { bank = {} }, h.clock + 2)           -- bank open and really empty
        it = ns.Offers.Get("Me-R").items
        h.eq(it[1], nil); h.eq(it[2], nil); h.eq(it[9].gbank2, 1)
        ns.Offers.Update("Me-R", { gbank2 = { [9] = 1 } }, h.clock + 3)
        h.eq(ns.Offers.Get("Me-R").items[9].gbank2, 1)
    end,

    ["offers: the same item in several places keeps one count per location"] = function(h)
        local ns = fresh(h)
        ns.Offers.Update("Me-R", { bag = { [5] = 1 }, mail = { [5] = 2 }, auction = { [5] = 1 } }, h.clock)
        local rows = ns.Offers.List("Me-R")
        h.eq(#rows, 1); h.eq(rows[1].total, 4); h.eq(#rows[1].locs, 3); h.eq(rows[1].locs[1].loc, "bag"); h.eq(rows[1].locs[3].loc, "auction")
    end,

    ["offers: an oversized scan is capped to what peers accept"] = function(h)
        local ns = fresh(h)
        local set = {}
        for i = 1, 500 do set[i] = 1 end
        ns.Offers.Update("Me-R", { bag = set }, h.clock)
        local n = 0
        for _ in pairs(ns.Offers.Get("Me-R").items) do n = n + 1 end
        h.eq(n, 300)
        h.truthy(ns.Offers.Sanitize(ns.Offers.Get("Me-R")), "own record must pass the peers' validation")
    end,

    ["offers: Sanitize copies only known fields and rejects hostile records whole (RF3)"] = function(h)
        local ns = fresh(h)
        local O = ns.Offers
        local good = { name = "A-R", rev = BIG, items = { [6661] = { bag = 1 } }, dibs = { ["B-R:77"] = { on = true, t = BIG } }, evil = "x" }
        local c = O.Sanitize(good)
        h.truthy(c); h.eq(c.evil, nil); h.eq(c.dibs["B-R:77"].on, true)
        local function bad(mutate, why)
            local r = { name = "A-R", rev = BIG, items = { [6661] = { bag = 1 } }, dibs = { ["B-R:77"] = { on = true, t = BIG } } }
            mutate(r)
            h.eq(O.Sanitize(r), nil, why)
        end
        bad(function(r) r.name = "A|cffff0000R" end, "name with escape")
        bad(function(r) r.name = nil end, "no name")
        bad(function(r) r.rev = 1 / 0 end, "inf rev")
        bad(function(r) r.rev = 0 / 0 end, "nan rev")
        bad(function(r) r.rev = BIG + 10 * 86400 end, "rev from the future")
        bad(function(r) r.rev = -1 end, "negative rev")
        bad(function(r) r.items = "no" end, "items not a table")
        bad(function(r) r.items[0] = { bag = 1 } end, "item id 0")
        bad(function(r) r.items[1.5] = { bag = 1 } end, "fractional item id")
        bad(function(r) r.items[3] = { bag = 0 } end, "count 0")
        bad(function(r) r.items[3] = { bag = 10000 } end, "count too big")
        bad(function(r) r.items[3] = { bag = 1 / 0 } end, "count inf")
        bad(function(r) r.items[3] = { vault = 1 } end, "unknown location")
        bad(function(r) r.items[3] = { gbank9 = 1 } end, "gbank tab 9")
        bad(function(r) r.items[3] = {} end, "item without location")
        bad(function(r) r.items[3] = "bag" end, "location list not a table")
        bad(function(r) r.dibs["A-R:77"] = { on = true, t = BIG } end, "dib on own item")
        bad(function(r) r.dibs["nonsense"] = { on = true, t = BIG } end, "malformed dib key")
        bad(function(r) r.dibs["B|cffff0000R:77"] = { on = true, t = BIG } end, "dib key with escape")
        bad(function(r) r.dibs["B-R:77"].on = "yes" end, "dib flag not boolean")
        bad(function(r) r.dibs["B-R:77"].t = BIG * 2 end, "dib from the future")
        bad(function(r) r.dibs = 5 end, "dibs not a table")
        bad(function(r) local many = {}; for i = 1, 301 do many[i] = { bag = 1 } end; r.items = many end, "too many items")
        bad(function(r) local many = {}; for i = 1, 201 do many["B-R:" .. i] = { on = true, t = BIG } end; r.dibs = many end, "too many dibs")
    end,

    ["offers: dib toggles on and off, t only grows, you cannot dib your own or a missing item"] = function(h)
        local ns = fresh(h)
        local O = ns.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1) }, dibs = {} })
        h.eq(O.ToggleDib("Me-R", "Own-R", 6661, h.clock), "on")
        local d1 = O.Get("Me-R").dibs["Own-R:6661"]
        h.eq(d1.on, true)
        h.eq(O.ToggleDib("Me-R", "Own-R", 6661, h.clock), "off")           -- same second: still strictly newer
        local d2 = O.Get("Me-R").dibs["Own-R:6661"]
        h.eq(d2.on, false); h.truthy(d2.t > d1.t)
        h.eq(O.ToggleDib("Me-R", "Own-R", 6661, h.clock), "on")
        local _, why = O.ToggleDib("Me-R", "Me-R", 6661, h.clock); h.eq(why, "self")
        local _, why2 = O.ToggleDib("Me-R", "Own-R", 12345, h.clock); h.eq(why2, "gone")
        local _, why3 = O.ToggleDib("Me-R", "Nobody-R", 6661, h.clock); h.eq(why3, "gone")
        h.truthy(O.Sanitize(O.Get("Me-R")), "my own record passes validation")
    end,

    ["offers: several players dib the same item; the list shows all of them, oldest first, and marks mine (RF4)"] = function(h)
        local ns = fresh(h, "Zed-R")
        local O = ns.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1) }, dibs = {} })
        O.Put({ name = "Bob-R", rev = BIG, items = {}, dibs = { ["Own-R:6661"] = { on = true, t = BIG + 20 } } })
        O.Put({ name = "Amy-R", rev = BIG, items = {}, dibs = { ["Own-R:6661"] = { on = true, t = BIG + 10 } } })
        O.Put({ name = "Cat-R", rev = BIG, items = {}, dibs = { ["Own-R:6661"] = { on = false, t = BIG + 30 } } })   -- withdrawn
        h.clock = BIG + 40
        O.ToggleDib("Zed-R", "Own-R", 6661, h.clock)
        local rows = O.List("Zed-R")
        h.eq(#rows, 1)
        local d = rows[1].dibs
        h.eq(#d, 3); h.eq(d[1].who, "Amy-R"); h.eq(d[2].who, "Bob-R"); h.eq(d[3].who, "Zed-R")
        h.truthy(rows[1].mine)
    end,

    ["offers: only the author can change a dib: a record claiming to be someone else is dropped (RF3)"] = function(h)
        local bus1 = bus()
        local a, b, c = peer(h, bus1, "A-R", 1), peer(h, bus1, "B-R", 2), peer(h, bus1, "C-R", 3)
        a.ns.Offers.Update("A-R", { bag = { [6661] = 1 } }, h.clock)
        advance(h, bus1, 1); b.sync:Hello(true); advance(h, bus1, 20)
        h.truthy(b.ns.Offers.Get("A-R"))
        -- C forges a record in B's name that removes B's dib / adds one for B
        local forged = { name = "B-R", rev = h.clock + 50, items = {}, dibs = { ["A-R:6661"] = { on = true, t = h.clock } } }
        a.sync:OnMessage({ t = "OFFERS", v = a.ns.PROTOCOL, offers = forged }, "C-R")
        h.eq(a.ns.Offers.Get("B-R"), nil)
        h.truthy(a.sync.stats.dropped >= 1)
    end,

    ["offers: Maintain drops MY dibs on vanished items only when the owner's record is known"] = function(h)
        local ns = fresh(h)
        local O = ns.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [1] = item(1), [2] = item(1) }, dibs = {} })
        O.ToggleDib("Me-R", "Own-R", 1, h.clock); O.ToggleDib("Me-R", "Own-R", 2, h.clock)
        O.Put({ name = "Away-R", rev = BIG, items = { [3] = item(1) }, dibs = {} })
        O.ToggleDib("Me-R", "Away-R", 3, h.clock)
        h.eq(O.Maintain("Me-R", h.clock + 1), false)
        O.Put({ name = "Own-R", rev = BIG + 5, items = { [2] = item(1) }, dibs = {} })      -- item 1 is gone
        h.truthy(O.Maintain("Me-R", h.clock + 2))
        local d = O.Get("Me-R").dibs
        h.eq(d["Own-R:1"], nil); h.truthy(d["Own-R:2"].on); h.truthy(d["Away-R:3"].on)
        h.eq(O.Maintain("Me-R", h.clock + 3), false)
        ns.Store.db.offers["Away-R"] = nil                                                  -- unknown owner: keep
        h.eq(O.Maintain("Me-R", h.clock + 4), false); h.truthy(O.Get("Me-R").dibs["Away-R:3"])
    end,

    ["offers: hiding is local, keeps my dib, and the offer returns when the owner's record changes (RF5)"] = function(h)
        local ns = fresh(h)
        local O = ns.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1), [7] = item(1) }, dibs = {} })
        O.ToggleDib("Me-R", "Own-R", 6661, h.clock)
        h.truthy(O.Hide("Own-R", 6661))
        h.eq(#O.List("Me-R"), 1)
        h.eq(O.Get("Me-R").dibs["Own-R:6661"].on, true, "my dib survives hiding")
        h.eq(O.Maintain("Me-R", h.clock + 1), false, "hiding must not look like a vanished item")
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1) }, dibs = {} })       -- same rev: stays hidden
        h.eq(#O.List("Me-R"), 1)
        O.Put({ name = "Own-R", rev = BIG + 1, items = { [6661] = item(1), [7] = item(2) }, dibs = {} })
        h.eq(#O.List("Me-R"), 2, "new sync of the owner brings it back")
        O.PruneHidden()
        h.eq(ns.Store.db.hidden["Own-R:6661"], nil)
    end,

    ["offers: persisted data is re-validated on load, schema 2 -> 3 keeps everything else (RF3)"] = function(h)
        local ns = h.ns({ now = BIG })
        local sv = { schema = 2, chars = {}, catalog = {}, orders = {}, ui = { minimapAngle = 5 }, me = "Me-R" }
        local out, status = ns.Store.Init(sv)
        h.eq(status, "migrated"); h.eq(out.schema, 3); h.truthy(out.offers); h.truthy(out.hidden); h.eq(out.ui.minimapAngle, 5)
        local sv3 = { schema = 3, chars = {}, catalog = {}, orders = {},
            offers = { ["A-R"] = { name = "A-R", rev = BIG, items = { [6661] = { bag = 1 } }, dibs = {} },
                ["B-R"] = { name = "B-R", rev = 1 / 0, items = {}, dibs = {} },                 -- hostile
                ["C-R"] = { name = "X-R", rev = BIG, items = {}, dibs = {} } },                 -- key/name mismatch
            hidden = { ["A-R:6661"] = BIG, ["junk"] = 1, ["A-R:5"] = "x" } }
        local ns2 = h.ns({ now = BIG })
        local out2 = ns2.Store.Init(sv3)
        h.truthy(out2.offers["A-R"]); h.eq(out2.offers["B-R"], nil); h.eq(out2.offers["C-R"], nil)
        h.eq(out2.hidden["A-R:6661"], BIG); h.eq(out2.hidden["junk"], nil); h.eq(out2.hidden["A-R:5"], nil)
    end,

    ["offers: /ts clean empties offers in place, departed members' offers are pruned"] = function(h)
        local ns = fresh(h)
        local offers, hidden = ns.db.offers, ns.db.hidden
        ns.Offers.Put({ name = "Own-R", rev = BIG, items = { [1] = item(1) }, dibs = {} })
        ns.Offers.Put({ name = "Gone-R", rev = BIG, items = { [1] = item(1) }, dibs = {} })
        ns.Offers.Hide("Own-R", 1)
        h.eq(ns.Store.Counts().offers, 2)
        ns.Store.Prune({ ["Own-R"] = true }, "Me-R")
        h.eq(ns.Offers.Get("Gone-R"), nil); h.truthy(ns.Offers.Get("Own-R"))
        local removed = ns.Store.Clean()
        h.eq(removed.offers, 1)
        h.eq(next(offers), nil); h.eq(next(hidden), nil)
        h.truthy(rawequal(ns.db.offers, offers), "tables are emptied in place")
    end,

    ["sync: offers travel HELLO(orev) -> WANTO -> OFFERS over the codec; dibs travel the same way back"] = function(h)
        local b1 = bus()
        local a, b = peer(h, b1, "A-R", 11), peer(h, b1, "B-R", 22)
        a.ns.Offers.Update("A-R", { bag = { [6661] = 1 }, bank = { [6661] = 1, [99] = 2 } }, h.clock)
        a.sync:Hello(true)
        advance(h, b1, 20)
        local rec = b.ns.Offers.Get("A-R")
        h.truthy(rec); h.eq(rec.items[6661].bank, 1); h.eq(rec.items[99].bank, 2)
        -- B calls dibs, announces it, A learns it
        h.eq(b.ns.Offers.ToggleDib("B-R", "A-R", 6661, h.clock), "on")
        b.sync:Hello(false)
        advance(h, b1, 20)
        local rows = a.ns.Offers.List("A-R")
        local found
        for _, r in ipairs(rows) do if r.itemID == 6661 then found = r end end
        h.truthy(found); h.eq(#found.dibs, 1); h.eq(found.dibs[1].who, "B-R")
        -- B removes it again: A sees it disappear
        h.eq(b.ns.Offers.ToggleDib("B-R", "A-R", 6661, h.clock + 1), "off")
        h.clock = h.clock + 1
        b.sync:Hello(false)
        advance(h, b1, 20)
        rows = a.ns.Offers.List("A-R")
        for _, r in ipairs(rows) do if r.itemID == 6661 then found = r end end
        h.eq(#found.dibs, 0)
    end,

    ["sync: an unchanged offers record is not pulled again, a hello without orev works (2.0 peers)"] = function(h)
        local b1 = bus()
        local a, b = peer(h, b1, "A-R", 1), peer(h, b1, "B-R", 2)
        a.ns.Offers.Update("A-R", { bag = { [1] = 1 } }, h.clock)
        a.sync:Hello(false); advance(h, b1, 20)
        local before = b.sync.stats.sent
        a.sync:Hello(false); advance(h, b1, 20)
        h.eq(b.sync.stats.sent, before, "no second WANTO for the same rev")
        b.sync:OnMessage({ t = "HELLO", v = b.ns.PROTOCOL, rev = 0 }, "A-R")                    -- no orev at all
        h.truthy(true)
    end,

    ["sync: hostile OFFERS and HELLO values are dropped without changing state (RF3)"] = function(h)
        local b1 = bus()
        local a = peer(h, b1, "A-R", 1)
        local P = a.ns.PROTOCOL
        local bad = {
            { name = "B-R", rev = 1 / 0, items = {}, dibs = {} },
            { name = "B-R", rev = BIG, items = { [1] = { bag = 0 / 0 } }, dibs = {} },
            { name = "C-R", rev = BIG, items = {}, dibs = {} },                  -- sender is B-R
            "string", 5,
        }
        for _, r in ipairs(bad) do a.sync:OnMessage({ t = "OFFERS", v = P, offers = r }, "B-R") end
        h.eq(a.ns.Offers.Get("B-R"), nil); h.eq(a.ns.Offers.Get("C-R"), nil)
        a.sync:OnMessage({ t = "HELLO", v = P, rev = 0, orev = 1 / 0 }, "B-R")
        a.sync:OnMessage({ t = "HELLO", v = P, rev = 0, orev = "x" }, "B-R")
        a.sync:OnMessage({ t = "HELLO", v = P, rev = 0, orev = BIG * 5 }, "B-R")
        a.sync:OnMessage({ t = "WANTO", v = P, names = "A-R" }, "B-R")
        h.eq(#b1.queue, 0, "no WANTO answer to a hostile orev")
    end,

    ["sync: WANTO is only answered for my own name"] = function(h)
        local b1 = bus()
        local a = peer(h, b1, "A-R", 1)
        a.ns.Offers.Update("A-R", { bag = { [1] = 1 } }, h.clock)
        a.sync:OnMessage({ t = "WANTO", v = a.ns.PROTOCOL, names = { "Other-R" } }, "B-R")
        a.sync:Tick(h.clock + 5)
        h.eq(#b1.queue, 0)
        a.sync:OnMessage({ t = "WANTO", v = a.ns.PROTOCOL, names = { "A-R" } }, "B-R")
        a.sync:Tick(h.clock + 5)
        h.eq(#b1.queue, 1); h.eq(b1.queue[1].msg.t, "OFFERS"); h.eq(b1.queue[1].dist, "WHISPER")
    end,
}
