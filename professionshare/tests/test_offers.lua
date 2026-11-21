-- Recipe items board (feature 007): offers records, dibs, local hide, validation, persistence, sync over the codec.
local BIG = 1700000000   -- a realistic server time, so "timestamp from the future" is decidable

local function fresh(harness, me, now)
    local addon = harness.addon({ now = now or BIG })
    addon.Store.db.me = me or "Me-R"
    return addon
end

local function item(count, loc) return { [loc or "bag"] = count or 1 } end

local function peer(harness, bus, name, seed)
    local addon = fresh(harness, name)
    local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    local rng = seed
    local p = { name = name, addon = addon, changes = 0 }
    p.sync = addon.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return harness.clock end,
        random = function() rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648 end,
        store = addon.Store, orders = orders, me = name,
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
        local wire = bus.peers[it.from].addon.Codec.Encode(it.msg)
        for name, p in pairs(bus.peers) do
            local to = (it.dist == "GUILD" and name ~= it.from) or (it.dist == "WHISPER" and name == it.target)
            if to then p.sync:OnMessage(assert(p.addon.Codec.Decode(wire)), it.from) end
        end
    end
end

local function advance(harness, bus, seconds)
    for _ = 1, seconds do
        harness.clock = harness.clock + 1
        for _, p in pairs(bus.peers) do p.sync:Tick(harness.clock) end
        pump(bus)
    end
end

local function bus() return { peers = {}, queue = {} } end

return {
    ["offers: update builds my record, an identical scan changes nothing, a new item bumps rev"] = function(harness)
        local addon = fresh(harness)
        harness.truthy(addon.Offers.Update("Me-R", { bag = { [6661] = 2 } }, harness.clock))
        local rec = addon.Offers.Get("Me-R")
        harness.equal(rec.items[6661].bag, 2); harness.equal(rec.rev, harness.clock)
        harness.equal(addon.Offers.Update("Me-R", { bag = { [6661] = 2 } }, harness.clock + 5), false)
        harness.equal(addon.Offers.Get("Me-R").rev, harness.clock)
        harness.truthy(addon.Offers.Update("Me-R", { bag = { [6661] = 2, [6662] = 1 } }, harness.clock + 5))
        harness.equal(addon.Offers.Get("Me-R").rev, harness.clock + 5)
    end,

    ["offers: an empty first scan creates no record; rev never goes backwards (RF1)"] = function(harness)
        local addon = fresh(harness)
        harness.equal(addon.Offers.Update("Me-R", { bag = {} }, harness.clock), false)
        harness.equal(addon.Offers.Get("Me-R"), nil)
        addon.Offers.Update("Me-R", { bag = { [1] = 1 } }, harness.clock)
        addon.Offers.Update("Me-R", { bag = {} }, harness.clock - 100)   -- clock went back: rev still grows
        harness.truthy(addon.Offers.Get("Me-R").rev > harness.clock)
    end,

    ["offers: update keeps locations that were not scanned and replaces the ones that were (RF1)"] = function(harness)
        local addon = fresh(harness)
        addon.Offers.Update("Me-R", { bag = { [1] = 1 }, bank = { [1] = 1, [2] = 3 }, gbank2 = { [9] = 1 } }, harness.clock)
        addon.Offers.Update("Me-R", { bag = {} }, harness.clock + 1)            -- bank/mail/gbank not readable now
        local it = addon.Offers.Get("Me-R").items
        harness.equal(it[1].bag, nil); harness.equal(it[1].bank, 1); harness.equal(it[2].bank, 3); harness.equal(it[9].gbank2, 1)
        addon.Offers.Update("Me-R", { bank = {} }, harness.clock + 2)           -- bank open and really empty
        it = addon.Offers.Get("Me-R").items
        harness.equal(it[1], nil); harness.equal(it[2], nil); harness.equal(it[9].gbank2, 1)
        addon.Offers.Update("Me-R", { gbank2 = { [9] = 1 } }, harness.clock + 3)
        harness.equal(addon.Offers.Get("Me-R").items[9].gbank2, 1)
    end,

    ["offers: the same item in several places keeps one count per location"] = function(harness)
        local addon = fresh(harness)
        addon.Offers.Update("Me-R", { bag = { [5] = 1 }, mail = { [5] = 2 }, auction = { [5] = 1 } }, harness.clock)
        local rows = addon.Offers.List("Me-R")
        harness.equal(#rows, 1); harness.equal(rows[1].total, 4); harness.equal(#rows[1].locs, 3); harness.equal(rows[1].locs[1].loc, "bag"); harness.equal(rows[1].locs[3].loc, "auction")
    end,

    ["offers: an oversized scan is capped to what peers accept"] = function(harness)
        local addon = fresh(harness)
        local set = {}
        for i = 1, 500 do set[i] = 1 end
        addon.Offers.Update("Me-R", { bag = set }, harness.clock)
        local n = 0
        for _ in pairs(addon.Offers.Get("Me-R").items) do n = n + 1 end
        harness.equal(n, 300)
        harness.truthy(addon.Offers.Sanitize(addon.Offers.Get("Me-R")), "own record must pass the peers' validation")
    end,

    ["offers: Sanitize copies only known fields and rejects hostile records whole (RF3)"] = function(harness)
        local addon = fresh(harness)
        local O = addon.Offers
        local good = { name = "A-R", rev = BIG, items = { [6661] = { bag = 1 } }, dibs = { ["B-R:77"] = { on = true, t = BIG } }, evil = "x" }
        local c = O.Sanitize(good)
        harness.truthy(c); harness.equal(c.evil, nil); harness.equal(c.dibs["B-R:77"].on, true)
        local function bad(mutate, why)
            local r = { name = "A-R", rev = BIG, items = { [6661] = { bag = 1 } }, dibs = { ["B-R:77"] = { on = true, t = BIG } } }
            mutate(r)
            harness.equal(O.Sanitize(r), nil, why)
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

    ["offers: dib toggles on and off, t only grows, you cannot dib your own or a missing item"] = function(harness)
        local addon = fresh(harness)
        local O = addon.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1) }, dibs = {} })
        harness.equal(O.ToggleDib("Me-R", "Own-R", 6661, harness.clock), "on")
        local d1 = O.Get("Me-R").dibs["Own-R:6661"]
        harness.equal(d1.on, true)
        harness.equal(O.ToggleDib("Me-R", "Own-R", 6661, harness.clock), "off")           -- same second: still strictly newer
        local d2 = O.Get("Me-R").dibs["Own-R:6661"]
        harness.equal(d2.on, false); harness.truthy(d2.t > d1.t)
        harness.equal(O.ToggleDib("Me-R", "Own-R", 6661, harness.clock), "on")
        local _, why = O.ToggleDib("Me-R", "Me-R", 6661, harness.clock); harness.equal(why, "self")
        local _, why2 = O.ToggleDib("Me-R", "Own-R", 12345, harness.clock); harness.equal(why2, "gone")
        local _, why3 = O.ToggleDib("Me-R", "Nobody-R", 6661, harness.clock); harness.equal(why3, "gone")
        harness.truthy(O.Sanitize(O.Get("Me-R")), "my own record passes validation")
    end,

    ["offers: several players dib the same item; the list shows all of them, oldest first, and marks mine (RF4)"] = function(harness)
        local addon = fresh(harness, "Zed-R")
        local O = addon.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1) }, dibs = {} })
        O.Put({ name = "Bob-R", rev = BIG, items = {}, dibs = { ["Own-R:6661"] = { on = true, t = BIG + 20 } } })
        O.Put({ name = "Amy-R", rev = BIG, items = {}, dibs = { ["Own-R:6661"] = { on = true, t = BIG + 10 } } })
        O.Put({ name = "Cat-R", rev = BIG, items = {}, dibs = { ["Own-R:6661"] = { on = false, t = BIG + 30 } } })   -- withdrawn
        harness.clock = BIG + 40
        O.ToggleDib("Zed-R", "Own-R", 6661, harness.clock)
        local rows = O.List("Zed-R")
        harness.equal(#rows, 1)
        local d = rows[1].dibs
        harness.equal(#d, 3); harness.equal(d[1].who, "Amy-R"); harness.equal(d[2].who, "Bob-R"); harness.equal(d[3].who, "Zed-R")
        harness.truthy(rows[1].mine)
    end,

    ["offers: only the author can change a dib: a record claiming to be someone else is dropped (RF3)"] = function(harness)
        local bus1 = bus()
        local a, b, c = peer(harness, bus1, "A-R", 1), peer(harness, bus1, "B-R", 2), peer(harness, bus1, "C-R", 3)
        a.addon.Offers.Update("A-R", { bag = { [6661] = 1 } }, harness.clock)
        advance(harness, bus1, 1); b.sync:Hello(true); advance(harness, bus1, 20)
        harness.truthy(b.addon.Offers.Get("A-R"))
        -- C forges a record in B's name that removes B's dib / adds one for B
        local forged = { name = "B-R", rev = harness.clock + 50, items = {}, dibs = { ["A-R:6661"] = { on = true, t = harness.clock } } }
        a.sync:OnMessage({ t = "OFFERS", v = a.addon.PROTOCOL, offers = forged }, "C-R")
        harness.equal(a.addon.Offers.Get("B-R"), nil)
        harness.truthy(a.sync.statistics.dropped >= 1)
    end,

    ["offers: Maintain drops MY dibs on vanished items only when the owner's record is known"] = function(harness)
        local addon = fresh(harness)
        local O = addon.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [1] = item(1), [2] = item(1) }, dibs = {} })
        O.ToggleDib("Me-R", "Own-R", 1, harness.clock); O.ToggleDib("Me-R", "Own-R", 2, harness.clock)
        O.Put({ name = "Away-R", rev = BIG, items = { [3] = item(1) }, dibs = {} })
        O.ToggleDib("Me-R", "Away-R", 3, harness.clock)
        harness.equal(O.Maintain("Me-R", harness.clock + 1), false)
        O.Put({ name = "Own-R", rev = BIG + 5, items = { [2] = item(1) }, dibs = {} })      -- item 1 is gone
        harness.truthy(O.Maintain("Me-R", harness.clock + 2))
        local d = O.Get("Me-R").dibs
        harness.equal(d["Own-R:1"], nil); harness.truthy(d["Own-R:2"].on); harness.truthy(d["Away-R:3"].on)
        harness.equal(O.Maintain("Me-R", harness.clock + 3), false)
        addon.Store.db.offers["Away-R"] = nil                                                  -- unknown owner: keep
        harness.equal(O.Maintain("Me-R", harness.clock + 4), false); harness.truthy(O.Get("Me-R").dibs["Away-R:3"])
    end,

    ["offers: hiding is local, keeps my dib, and the offer returns when the owner's record changes (RF5)"] = function(harness)
        local addon = fresh(harness)
        local O = addon.Offers
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1), [7] = item(1) }, dibs = {} })
        O.ToggleDib("Me-R", "Own-R", 6661, harness.clock)
        harness.truthy(O.Hide("Own-R", 6661))
        harness.equal(#O.List("Me-R"), 1)
        harness.equal(O.Get("Me-R").dibs["Own-R:6661"].on, true, "my dib survives hiding")
        harness.equal(O.Maintain("Me-R", harness.clock + 1), false, "hiding must not look like a vanished item")
        O.Put({ name = "Own-R", rev = BIG, items = { [6661] = item(1) }, dibs = {} })       -- same rev: stays hidden
        harness.equal(#O.List("Me-R"), 1)
        O.Put({ name = "Own-R", rev = BIG + 1, items = { [6661] = item(1), [7] = item(2) }, dibs = {} })
        harness.equal(#O.List("Me-R"), 2, "new sync of the owner brings it back")
        O.PruneHidden()
        harness.equal(addon.Store.db.hidden["Own-R:6661"], nil)
    end,

    ["offers: persisted data is re-validated on load, schema 2 -> 3 keeps everything else (RF3)"] = function(harness)
        local addon = harness.addon({ now = BIG })
        local sv = { schema = 2, chars = {}, catalog = {}, orders = {}, ui = { minimapAngle = 5 }, me = "Me-R" }
        local out, status = addon.Store.Init(sv)
        harness.equal(status, "migrated"); harness.equal(out.schema, addon.Store.SCHEMA); harness.truthy(out.offers); harness.truthy(out.hidden); harness.equal(out.ui.minimapAngle, 5)
        local sv3 = { schema = 3, chars = {}, catalog = {}, orders = {},
            offers = { ["A-R"] = { name = "A-R", rev = BIG, items = { [6661] = { bag = 1 } }, dibs = {} },
                ["B-R"] = { name = "B-R", rev = 1 / 0, items = {}, dibs = {} },                 -- hostile
                ["C-R"] = { name = "X-R", rev = BIG, items = {}, dibs = {} } },                 -- key/name mismatch
            hidden = { ["A-R:6661"] = BIG, ["junk"] = 1, ["A-R:5"] = "x" } }
        local ns2 = harness.addon({ now = BIG })
        local out2 = ns2.Store.Init(sv3)
        harness.truthy(out2.offers["A-R"]); harness.equal(out2.offers["B-R"], nil); harness.equal(out2.offers["C-R"], nil)
        harness.equal(out2.hidden["A-R:6661"], BIG); harness.equal(out2.hidden["junk"], nil); harness.equal(out2.hidden["A-R:5"], nil)
    end,

    ["offers: /ps clean empties offers in place, departed members' offers are pruned"] = function(harness)
        local addon = fresh(harness)
        local offers, hidden = addon.db.offers, addon.db.hidden
        addon.Offers.Put({ name = "Own-R", rev = BIG, items = { [1] = item(1) }, dibs = {} })
        addon.Offers.Put({ name = "Gone-R", rev = BIG, items = { [1] = item(1) }, dibs = {} })
        addon.Offers.Hide("Own-R", 1)
        harness.equal(addon.Store.Counts().offers, 2)
        addon.Store.Prune({ ["Own-R"] = true }, "Me-R")
        harness.equal(addon.Offers.Get("Gone-R"), nil); harness.truthy(addon.Offers.Get("Own-R"))
        local removed = addon.Store.Clean()
        harness.equal(removed.offers, 1)
        harness.equal(next(offers), nil); harness.equal(next(hidden), nil)
        harness.truthy(rawequal(addon.db.offers, offers), "tables are emptied in place")
    end,

    ["sync: offers travel HELLO(orev) -> WANTO -> OFFERS over the codec; dibs travel the same way back"] = function(harness)
        local b1 = bus()
        local a, b = peer(harness, b1, "A-R", 11), peer(harness, b1, "B-R", 22)
        a.addon.Offers.Update("A-R", { bag = { [6661] = 1 }, bank = { [6661] = 1, [99] = 2 } }, harness.clock)
        a.sync:Hello(true)
        advance(harness, b1, 20)
        local rec = b.addon.Offers.Get("A-R")
        harness.truthy(rec); harness.equal(rec.items[6661].bank, 1); harness.equal(rec.items[99].bank, 2)
        -- B calls dibs, announces it, A learns it
        harness.equal(b.addon.Offers.ToggleDib("B-R", "A-R", 6661, harness.clock), "on")
        b.sync:Hello(false)
        advance(harness, b1, 20)
        local rows = a.addon.Offers.List("A-R")
        local found
        for _, r in ipairs(rows) do if r.itemID == 6661 then found = r end end
        harness.truthy(found); harness.equal(#found.dibs, 1); harness.equal(found.dibs[1].who, "B-R")
        -- B removes it again: A sees it disappear
        harness.equal(b.addon.Offers.ToggleDib("B-R", "A-R", 6661, harness.clock + 1), "off")
        harness.clock = harness.clock + 1
        b.sync:Hello(false)
        advance(harness, b1, 20)
        rows = a.addon.Offers.List("A-R")
        for _, r in ipairs(rows) do if r.itemID == 6661 then found = r end end
        harness.equal(#found.dibs, 0)
    end,

    ["sync: an unchanged offers record is not pulled again, a hello without orev works (2.0 peers)"] = function(harness)
        local b1 = bus()
        local a, b = peer(harness, b1, "A-R", 1), peer(harness, b1, "B-R", 2)
        a.addon.Offers.Update("A-R", { bag = { [1] = 1 } }, harness.clock)
        a.sync:Hello(false); advance(harness, b1, 20)
        local before = b.sync.statistics.sent
        a.sync:Hello(false); advance(harness, b1, 20)
        harness.equal(b.sync.statistics.sent, before, "no second WANTO for the same rev")
        b.sync:OnMessage({ t = "HELLO", v = b.addon.PROTOCOL, rev = 0 }, "A-R")                    -- no orev at all
        harness.truthy(true)
    end,

    ["sync: hostile OFFERS and HELLO values are dropped without changing state (RF3)"] = function(harness)
        local b1 = bus()
        local a = peer(harness, b1, "A-R", 1)
        local P = a.addon.PROTOCOL
        local bad = {
            { name = "B-R", rev = 1 / 0, items = {}, dibs = {} },
            { name = "B-R", rev = BIG, items = { [1] = { bag = 0 / 0 } }, dibs = {} },
            { name = "C-R", rev = BIG, items = {}, dibs = {} },                  -- sender is B-R
            "string", 5,
        }
        for _, r in ipairs(bad) do a.sync:OnMessage({ t = "OFFERS", v = P, offers = r }, "B-R") end
        harness.equal(a.addon.Offers.Get("B-R"), nil); harness.equal(a.addon.Offers.Get("C-R"), nil)
        a.sync:OnMessage({ t = "HELLO", v = P, rev = 0, orev = 1 / 0 }, "B-R")
        a.sync:OnMessage({ t = "HELLO", v = P, rev = 0, orev = "x" }, "B-R")
        a.sync:OnMessage({ t = "HELLO", v = P, rev = 0, orev = BIG * 5 }, "B-R")
        a.sync:OnMessage({ t = "WANTO", v = P, names = "A-R" }, "B-R")
        harness.equal(#b1.queue, 0, "no WANTO answer to a hostile orev")
    end,

    ["sync: WANTO is only answered for my own name"] = function(harness)
        local b1 = bus()
        local a = peer(harness, b1, "A-R", 1)
        a.addon.Offers.Update("A-R", { bag = { [1] = 1 } }, harness.clock)
        a.sync:OnMessage({ t = "WANTO", v = a.addon.PROTOCOL, names = { "Other-R" } }, "B-R")
        a.sync:Tick(harness.clock + 5)
        harness.equal(#b1.queue, 0)
        a.sync:OnMessage({ t = "WANTO", v = a.addon.PROTOCOL, names = { "A-R" } }, "B-R")
        a.sync:Tick(harness.clock + 5)
        harness.equal(#b1.queue, 1); harness.equal(b1.queue[1].msg.t, "OFFERS"); harness.equal(b1.queue[1].dist, "WHISPER")
    end,
}
