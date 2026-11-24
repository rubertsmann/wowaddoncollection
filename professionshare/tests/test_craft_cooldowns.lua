-- Craft cooldowns: group data, records, validation, persistence, migration, sync over the codec with differing clocks.
local BIG = 1700000000   -- a realistic server time, so "timestamp from the future" is decidable
local DAY = 86400

local function fresh(harness, me)
    local addon = harness.addon({ now = BIG })
    addon.Store.db.me = me or "Me-R"
    return addon
end

-- a peer on the shared test bus; `skew` seconds are added to its clock (its GetServerTime differs from the others')
local function peer(harness, bus, name, seed, skew)
    local addon = fresh(harness, name)
    local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    local rng = seed
    local p = { name = name, addon = addon, changes = {}, skew = skew or 0 }
    p.now = function() return harness.clock + p.skew end
    p.sync = addon.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = p.now,
        random = function() rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648 end,
        store = addon.Store, orders = orders, me = name,
        onChange = function(kind) p.changes[#p.changes + 1] = kind end,
    })
    bus.peers[name] = p
    return p
end

local function pump(bus)
    local guard = 0
    while #bus.queue > 0 and guard < 2000 do
        guard = guard + 1
        local it = table.remove(bus.queue, 1)
        bus.sent[#bus.sent + 1] = it
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
        for _, p in pairs(bus.peers) do p.sync:Tick(p.now()) end
        pump(bus)
    end
end

local function bus() return { peers = {}, queue = {}, sent = {} } end

local KNOWN_TRANSMUTE = { transmute = true }

return {
    ["craft cooldowns: needs protocol 2.8 or newer and schema 9 or newer"] = function(harness)
        local addon = fresh(harness)
        harness.equal(addon.PROTOCOL_MAJOR, 2); harness.truthy(addon.PROTOCOL_MINOR >= 8); harness.truthy(addon.Store.SCHEMA >= 9)
    end,

    ["craft cooldowns: groups well formed, unique keys, no recipe or cast in two groups"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        local keys, recipes, casts = {}, {}, {}
        harness.truthy(#C.GROUPS >= 3)
        for _, group in ipairs(C.GROUPS) do
            harness.truthy(type(group.key) == "string" and group.key:match("^%l+$") and not keys[group.key], "unique key " .. tostring(group.key))
            keys[group.key] = true
            harness.truthy(type(group.name) == "string" and group.name ~= "" and type(group.profession) == "string")
            harness.truthy(type(group.skillLine) == "number" and type(group.produces) == "number")
            harness.truthy(group.fallback > 0 and group.fallback <= C.MAXIMUM_REMAINING, group.key .. ": fallback in range")
            harness.truthy(#group.recipes > 0 or group.item, group.key .. ": needs recipes or an item")
            harness.truthy(#group.casts > 0, group.key .. ": a cast must start it")
            for _, recipeID in ipairs(group.recipes) do
                harness.truthy(not recipes[recipeID], "recipe in two groups"); recipes[recipeID] = true
                harness.equal(C.GroupOfRecipe(recipeID), group)
            end
            for _, spellID in ipairs(group.casts) do
                harness.truthy(not casts[spellID], "cast in two groups"); casts[spellID] = true
                harness.equal(C.GroupOfCast(spellID), group)
            end
            for _, reagent in ipairs(group.reagents) do harness.truthy(reagent.itemID > 0 and reagent.count > 0) end
            harness.equal(C.Group(group.key), group)
        end
        harness.truthy(keys.transmute and keys.mooncloth and keys.saltshaker)
        harness.equal(C.GroupOfRecipe(17187), C.Group("transmute"), "Arcanite shares the transmute group")
    end,

    ["craft cooldowns (RF1): sanitize rejects malformed records, skips unknown groups"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        local good = { name = "A-R", rev = BIG - 5, c = { transmute = BIG + 100, mooncloth = 0 }, e = { transmute = true } }
        local clean = C.Sanitize(good)
        harness.truthy(clean); harness.equal(clean.c.transmute, BIG + 100); harness.equal(clean.e.transmute, true)
        harness.truthy(clean ~= good and clean.c ~= good.c, "a copy")
        for label, bad in pairs({
            noName = { rev = 1, c = {} }, badName = { name = "a|b", rev = 1, c = {} }, noC = { name = "A-R", rev = 1 },
            futureRev = { name = "A-R", rev = BIG + 10 * DAY, c = {} },
            nanTime = { name = "A-R", rev = 1, c = { transmute = 0 / 0 } },
            negativeTime = { name = "A-R", rev = 1, c = { transmute = -5 } },
            hugeTime = { name = "A-R", rev = 1, c = { transmute = 2 ^ 40 } },
            fractionTime = { name = "A-R", rev = 1, c = { transmute = 1.5 } },
            numericKey = { name = "A-R", rev = 1, c = { [1] = 5 } },
            badEstimate = { name = "A-R", rev = 1, c = { transmute = 5 }, e = { transmute = "yes" } },
            eNotTable = { name = "A-R", rev = 1, c = {}, e = 5 },
        }) do
            harness.equal(C.Sanitize(bad), nil, label)
        end
        local many = { name = "A-R", rev = 1, c = {} }
        for index = 1, 500 do many.c["g" .. index] = 0 end
        harness.equal(C.Sanitize(many), nil, "500 groups rejected")
        local newer = C.Sanitize({ name = "A-R", rev = 1, c = { transmute = 0, futurecraft = 99 }, e = { futurecraft = true } })
        harness.truthy(newer, "a group from a newer build does not reject the record")
        harness.equal(newer.c.futurecraft, nil); harness.equal(newer.e.futurecraft, nil); harness.equal(newer.c.transmute, 0)
    end,

    ["craft cooldowns (RF3): FromWire keeps the time left across differing clocks, drops impossible times"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        local ownerNow = BIG + 7200   -- the owner's clock is 2 h ahead of mine
        local record = C.Sanitize({ name = "A-R", rev = BIG, c = { transmute = ownerNow + 3600, mooncloth = 0,
            saltshaker = ownerNow - 50 }, e = { transmute = true } })
        local mine = C.FromWire(record, ownerNow, BIG)
        harness.equal(mine.c.transmute, BIG + 3600, "1 h left stays 1 h left")
        harness.equal(mine.e.transmute, true)
        harness.equal(mine.c.mooncloth, 0); harness.equal(mine.c.saltshaker, 0, "already passed = ready")
        harness.equal(mine.seen, BIG)
        local noStamp = C.FromWire(record, nil, BIG)
        harness.equal(noStamp.c.transmute, ownerNow + 3600, "no stamp: clocks taken as equal")
        local garbageStamp = C.FromWire(record, 0 / 0, BIG)
        harness.equal(garbageStamp.c.transmute, ownerNow + 3600)
        local far = C.Sanitize({ name = "A-R", rev = BIG, c = { transmute = BIG + 365 * DAY } })
        harness.equal(C.FromWire(far, BIG, BIG).c.transmute, nil, "a year of cooldown is dropped")
    end,

    ["craft cooldowns: put keeps the newer revision only"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        harness.truthy(C.Put({ name = "A-R", rev = 5, c = {}, e = {} }))
        harness.truthy(not C.Put({ name = "A-R", rev = 5, c = { transmute = 0 }, e = {} }))
        harness.truthy(C.Put({ name = "A-R", rev = 6, c = { transmute = 0 }, e = {} }))
        harness.equal(C.Get("A-R").c.transmute, 0)
    end,

    ["craft cooldowns: update bumps rev only on real changes (jitter, ready stays ready)"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        harness.truthy(not C.Update("Me-R", {}, {}, BIG), "nothing known, no record")
        harness.equal(C.Get("Me-R"), nil)
        harness.truthy(C.Update("Me-R", KNOWN_TRANSMUTE, { transmute = { remaining = 0, source = "spell" } }, BIG))
        local first = C.Get("Me-R")
        harness.equal(first.c.transmute, 0); harness.equal(first.rev, BIG)
        harness.truthy(not C.Update("Me-R", KNOWN_TRANSMUTE, { transmute = { remaining = 0, source = "spell" } }, BIG + 10), "still ready")
        harness.truthy(C.Update("Me-R", KNOWN_TRANSMUTE, { transmute = { remaining = DAY, source = "spell" } }, BIG + 20), "crafted")
        local cooling = C.Get("Me-R")
        harness.equal(cooling.c.transmute, BIG + 20 + DAY); harness.equal(cooling.e.transmute, nil)
        harness.truthy(not C.Update("Me-R", KNOWN_TRANSMUTE, { transmute = { remaining = DAY - 130, source = "spell" } }, BIG + 150),
            "the same cooldown read again (20 s later in game time is jitter)")
        harness.truthy(not C.Update("Me-R", KNOWN_TRANSMUTE, {}, BIG + 200), "no answer from the game: the value stays")
        harness.equal(C.Get("Me-R").c.transmute, BIG + 20 + DAY)
        -- after the ready time passed the stored time counts as ready: a 0 reading is no change
        harness.truthy(not C.Update("Me-R", KNOWN_TRANSMUTE, { transmute = { remaining = 0, source = "spell" } }, BIG + 2 * DAY))
        harness.truthy(C.Update("Me-R", {}, {}, BIG + 2 * DAY), "the profession was dropped: the group goes")
        harness.equal(C.Get("Me-R").c.transmute, nil)
        harness.clock = BIG + 2 * DAY   -- the record's rev is from that time
        harness.truthy(C.Sanitize(C.Get("Me-R")), "my own record passes the peers' validation")
    end,

    ["craft cooldowns: garbage readings are ignored, unknown group keys skipped"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        harness.truthy(C.Update("Me-R", { transmute = true, bogus = true }, {
            transmute = { remaining = 0 / 0, source = "spell" }, bogus = { remaining = 5, source = "spell" } }, BIG) == false)
        harness.truthy(C.Update("Me-R", KNOWN_TRANSMUTE, { transmute = { remaining = 100 * DAY, source = "spell" } }, BIG) == false,
            "an impossible remaining time is not taken")
        harness.truthy(C.Update("Me-R", KNOWN_TRANSMUTE, { transmute = { remaining = -5, source = "spell" } }, BIG) == false)
        harness.equal(C.Get("Me-R"), nil)
    end,

    ["craft cooldowns: a seen cast sets the estimate, the real reading replaces it"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        harness.truthy(not C.NoteCast("Me-R", 12345, KNOWN_TRANSMUTE, BIG), "not a group spell")
        harness.truthy(C.NoteCast("Me-R", 18560, {}, BIG), "Mooncloth cast")
        local record = C.Get("Me-R")
        harness.equal(record.c.mooncloth, BIG + 4 * DAY); harness.equal(record.e.mooncloth, true)
        harness.truthy(C.Update("Me-R", { mooncloth = true }, { mooncloth = { remaining = 4 * DAY - 2, source = "spell" } }, BIG + 2),
            "the estimate became a real reading (rev bumps: the flag changed)")
        harness.equal(C.Get("Me-R").e.mooncloth, nil)
    end,

    ["craft cooldowns: crafters' groups come from their recipes"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        local character = harness.character("A-R", 1, { 17187, 1234 })
        local groups = C.GroupsOfCharacter(character)
        harness.truthy(groups.transmute); harness.equal(groups.mooncloth, nil)
        harness.equal(next(C.GroupsOfCharacter(nil)), nil); harness.equal(next(C.GroupsOfCharacter({ professions = 5 })), nil)
    end,

    ["craft cooldowns: persisted records are re-validated; migration 8 -> 9 keeps everything"] = function(harness)
        local addon = fresh(harness)
        local sv = { schema = 8, chars = {}, catalog = {}, orders = {}, offers = {}, hidden = {}, ui = {}, me = "Me-R", access = {},
            rep = { ["A-R"] = { name = "A-R", rev = BIG - 5, f = { [59] = { s = 6, v = 1, m = 12000 } } } },
            feedback = {}, feedbackState = {}, feedbackDelivered = {} }
        local out, status = addon.Store.Init(sv)
        harness.equal(status, "migrated"); harness.equal(out.schema, 9)
        harness.truthy(out.rep["A-R"]); harness.equal(type(out.cds), "table")
        local out2 = addon.Store.Init({ schema = 9, cds = {
            ["A-R"] = { name = "A-R", rev = BIG - 5, c = { transmute = BIG + 5 }, e = {}, seen = BIG - 5 },
            ["B-R"] = { name = "B-R", rev = BIG - 5, c = { transmute = -1 }, e = {} },
            ["C-R"] = { name = "X-R", rev = BIG - 5, c = {}, e = {} } } })
        harness.truthy(out2.cds["A-R"]); harness.equal(out2.cds["A-R"].seen, BIG - 5, "seen survives a reload")
        harness.equal(out2.cds["B-R"], nil); harness.equal(out2.cds["C-R"], nil, "key and name differ")
    end,

    ["craft cooldowns (RF4): version reset drops peers' records, clean and prune remove them"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        for _, name in ipairs({ "Me-R", "B-R", "C-R" }) do C.Put({ name = name, rev = 1, c = {}, e = {} }) end
        local removed = addon.Store.ResetPeerData("Me-R")
        harness.equal(removed.cds, 2); harness.truthy(C.Get("Me-R")); harness.equal(C.Get("B-R"), nil)
        C.Put({ name = "B-R", rev = 1, c = {}, e = {} })
        addon.Store.Prune({ ["Me-R"] = true }, "Me-R")
        harness.equal(C.Get("B-R"), nil); harness.truthy(C.Get("Me-R"))
        addon.Store.Clean()
        harness.equal(C.Get("Me-R"), nil)
    end,

    ["craft cooldowns (RF3): two peers 2 h apart see the same time left (HELLO crev -> WANTC -> CDS)"] = function(harness)
        local b = bus()
        local a = peer(harness, b, "A-R", 7, 7200)   -- A's clock runs 2 h ahead
        local c = peer(harness, b, "C-R", 11, 0)
        a.addon.CraftCooldowns.Update("A-R", KNOWN_TRANSMUTE, { transmute = { remaining = 3600, source = "spell" } }, a.now())
        a.sync:Hello(true); c.sync:Hello(true)
        pump(b); advance(harness, b, 30)
        local got = c.addon.CraftCooldowns.Get("A-R")
        harness.truthy(got, "C pulled A's record")
        local leftAtC = got.c.transmute - c.now()
        local leftAtA = a.addon.CraftCooldowns.Get("A-R").c.transmute - a.now()
        harness.truthy(math.abs(leftAtC - leftAtA) <= 5, ("time left differs: C %d, A %d"):format(leftAtC, leftAtA))
        local sawWant, sawRecord = false, false
        for _, it in ipairs(b.sent) do
            if it.msg.t == "WANTC" then sawWant = true end
            if it.msg.t == "CDS" then
                sawRecord = true
                harness.truthy(it.msg.at, "the answer carries the sender's time")
                harness.equal(it.msg.cds.seen, nil, "my local 'seen' is not sent")
            end
        end
        harness.truthy(sawWant and sawRecord)
        harness.truthy(table.concat(c.changes, ","):find("cds", 1, true), "onChange(cds) fired")
    end,

    ["craft cooldowns: a peer cannot write another member's record"] = function(harness)
        local b = bus()
        local c = peer(harness, b, "C-R", 11)
        c.sync:OnMessage({ v = 2, t = "CDS", at = BIG, cds = { name = "Victim-R", rev = BIG + 1, c = { transmute = 0 }, e = {} } }, "Evil-R")
        harness.equal(c.addon.CraftCooldowns.Get("Victim-R"), nil)
    end,

    ["craft cooldowns (RF5 protocol): a 1.3-style peer ignores crev and WANTC, the other records still sync"] = function(harness)
        local b = bus()
        local a = peer(harness, b, "A-R", 7)
        local old = peer(harness, b, "Old-R", 13)
        old.sync.kinds.cds = nil
        for index, kind in ipairs(old.sync.kindOrder) do if kind.name == "cds" then table.remove(old.sync.kindOrder, index) end end
        local status = old.sync:OnMessage({ v = 2, t = "WANTC", names = { "Old-R" } }, "A-R")
        harness.truthy(status ~= "ok" and status ~= "error", "an unknown request type is not processed: " .. tostring(status))
        a.addon.CraftCooldowns.Update("A-R", KNOWN_TRANSMUTE, { transmute = { remaining = 0, source = "spell" } }, harness.clock)
        a.addon.Reputation.Update("A-R", { [59] = { s = 5, v = 1, m = 6000 } }, harness.clock)
        a.sync:Hello(false); old.sync:Hello(false)
        advance(harness, b, 40)
        harness.truthy(old.addon.Reputation.Get("A-R"), "rep still syncs next to cds")
        local wantCount = 0
        for _, it in ipairs(b.sent) do if it.msg.t == "WANTC" then wantCount = wantCount + 1 end end
        harness.equal(wantCount, 0, "the old peer never asks for cds")
    end,
}
