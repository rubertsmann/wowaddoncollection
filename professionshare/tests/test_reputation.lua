-- Faction standings: hint data, reputation records, validation, persistence, migration, sync over the codec.
local BIG = 1700000000   -- a realistic server time, so "timestamp from the future" is decidable

local function fresh(harness, me)
    local addon = harness.addon({ now = BIG })
    addon.Store.db.me = me or "Me-R"
    return addon
end

local function peer(harness, bus, name, seed)
    local addon = fresh(harness, name)
    local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    local rng = seed
    local p = { name = name, addon = addon, changes = {} }
    p.sync = addon.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return harness.clock end,
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
        for _, p in pairs(bus.peers) do p.sync:Tick(harness.clock) end
        pump(bus)
    end
end

local function bus() return { peers = {}, queue = {}, sent = {} } end

local THORIUM, ARGENT, TIMBERMAW = 59, 529, 576

return {
    ["reputation: needs protocol 2.6 or newer and schema 8 or newer"] = function(harness)
        local addon = fresh(harness)
        harness.equal(addon.PROTOCOL_MAJOR, 2); harness.truthy(addon.PROTOCOL_MINOR >= 6); harness.truthy(addon.Store.SCHEMA >= 8)
    end,

    ["faction hints: every faction well formed, unique ids, hints ascending, both languages, known group"] = function(harness)
        local addon = fresh(harness)
        local FactionHints = addon.FactionHints
        local groups, seen = {}, {}
        for _, group in ipairs(FactionHints.GROUP_ORDER) do groups[group] = true end
        harness.truthy(FactionHints.CHECKED:match("^%d%d%d%d%-%d%d%-%d%d$"), "CHECKED is a date")
        harness.truthy(#FactionHints.FACTIONS >= 10)
        for _, faction in ipairs(FactionHints.FACTIONS) do
            harness.truthy(type(faction.id) == "number" and faction.id > 0 and not seen[faction.id], "unique id " .. tostring(faction.id))
            seen[faction.id] = true
            harness.truthy(groups[faction.group], faction.name .. ": unknown group")
            harness.truthy(type(faction.name) == "string" and faction.name ~= "" and type(faction.icon) == "string")
            harness.truthy(#faction.hints > 0, faction.name .. ": no hints")
            local lastStanding = 0
            for _, hint in ipairs(faction.hints) do
                harness.truthy(hint.standing > lastStanding and hint.standing <= 8, faction.name .. ": hints not ascending")
                lastStanding = hint.standing
                harness.truthy(type(hint.en) == "string" and hint.en ~= "" and type(hint.de) == "string" and hint.de ~= "",
                    faction.name .. ": a hint lacks a language")
                harness.truthy(addon.Utility.IsValidUtf8(hint.de))
                harness.truthy(not hint.en:find("|", 1, true) and not hint.de:find("|", 1, true), "no escape codes in hints")
                for _, itemID in ipairs(hint.items or {}) do harness.truthy(type(itemID) == "number" and itemID > 0) end
            end
            harness.equal(FactionHints.Faction(faction.id), faction)
        end
    end,

    ["faction hints: text follows the UI language, next hint above a standing"] = function(harness)
        local addon = fresh(harness)
        local FactionHints = addon.FactionHints
        local hint = FactionHints.Faction(749).hints[1]
        harness.equal(FactionHints.HintText(hint, "deDE"), hint.de)
        harness.equal(FactionHints.HintText(hint, "enUS"), hint.en)
        harness.equal(FactionHints.HintText(hint, "frFR"), hint.en, "other languages fall back to English")
        harness.equal(FactionHints.NextHint(749, 4).standing, 6)
        harness.equal(FactionHints.NextHint(749, 6).standing, 7)
        harness.equal(FactionHints.NextHint(749, 8), nil)
        harness.equal(FactionHints.NextHint(424242, 1), nil)
    end,

    ["reputation (RF1): sanitize rejects malformed records and standings"] = function(harness)
        local addon = fresh(harness)
        local R = addon.Reputation
        local good = { name = "A-R", rev = BIG, f = { [THORIUM] = { s = 6, v = 4200, m = 12000 } } }
        local clean = R.Sanitize(good)
        harness.truthy(clean); harness.equal(clean.f[THORIUM].v, 4200)
        harness.truthy(clean ~= good, "a copy")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = { [THORIUM] = { s = 9, v = 0, m = 1 } } }), nil, "standing 9")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = { [THORIUM] = { s = 0, v = 0, m = 1 } } }), nil, "standing 0")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = { [THORIUM] = { s = 5, v = 7, m = 6 } } }), nil, "progress over size")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = { [THORIUM] = { s = 5, v = -1, m = 6 } } }), nil, "negative")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = { [THORIUM] = { s = 5, v = 0.5, m = 6 } } }), nil, "fraction")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = { [THORIUM] = "x" } }), nil)
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = { x = { s = 5, v = 0, m = 6 } } }), nil, "string id")
        harness.equal(R.Sanitize({ name = "A|r-R", rev = BIG, f = {} }), nil, "unsafe name")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG + 10 * 86400, f = {} }), nil, "from the future")
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG }), nil, "no faction map")
        local many = {}
        for id = 1, 65 do many[id] = { s = 4, v = 0, m = 3000 } end
        harness.equal(R.Sanitize({ name = "A-R", rev = BIG, f = many }), nil, "too many factions")
    end,

    ["reputation (RF2): a faction this build does not list is skipped, the record kept"] = function(harness)
        local addon = fresh(harness)
        local clean = addon.Reputation.Sanitize({ name = "A-R", rev = BIG,
            f = { [THORIUM] = { s = 5, v = 10, m = 6000 }, [99999] = { s = 8, v = 0, m = 999 } } })
        harness.truthy(clean); harness.truthy(clean.f[THORIUM]); harness.equal(clean.f[99999], nil)
    end,

    ["reputation: put keeps the newer revision only"] = function(harness)
        local addon = fresh(harness)
        local R = addon.Reputation
        harness.truthy(R.Put({ name = "A-R", rev = 5, f = {} }))
        harness.equal(R.Put({ name = "A-R", rev = 5, f = {} }), false)
        harness.equal(R.Put({ name = "A-R", rev = 4, f = {} }), false)
        harness.truthy(R.Put({ name = "A-R", rev = 6, f = {} }))
        harness.equal(R.Get("A-R").rev, 6)
    end,

    ["reputation (RF3): level changes are shared at once, progress at most every interval"] = function(harness)
        local addon = fresh(harness)
        local R = addon.Reputation
        local now = BIG
        harness.equal(R.Update("Me-R", {}, now), false, "no factions met, no record")
        harness.equal(R.Update("Me-R", nil, now), false, "no scan")
        harness.truthy(R.Update("Me-R", { [THORIUM] = { s = 5, v = 100, m = 6000 } }, now))
        local firstRevision = R.Get("Me-R").rev
        harness.equal(R.Update("Me-R", { [THORIUM] = { s = 5, v = 100, m = 6000 } }, now + 1), false, "unchanged")
        local changed, retryAfter = R.Update("Me-R", { [THORIUM] = { s = 5, v = 300, m = 6000 } }, now + 60)
        harness.equal(changed, false, "progress only, too soon"); harness.equal(retryAfter, R.PROGRESS_INTERVAL - 60)
        harness.equal(R.Get("Me-R").f[THORIUM].v, 100, "held back")
        harness.truthy(R.Update("Me-R", { [THORIUM] = { s = 6, v = 0, m = 12000 } }, now + 120), "a new level goes at once")
        harness.truthy(R.Get("Me-R").rev > firstRevision)
        harness.truthy(R.Update("Me-R", { [THORIUM] = { s = 6, v = 50, m = 12000 }, [ARGENT] = { s = 4, v = 0, m = 3000 } }, now + 180),
            "a newly met faction goes at once")
        harness.truthy(R.Update("Me-R", { [THORIUM] = { s = 6, v = 900, m = 12000 }, [ARGENT] = { s = 4, v = 0, m = 3000 } },
            now + 180 + R.PROGRESS_INTERVAL), "progress after the interval")
        harness.equal(R.Get("Me-R").f[THORIUM].v, 900)
    end,

    ["reputation: update ignores unlisted factions and garbage from the scan"] = function(harness)
        local addon = fresh(harness)
        local R = addon.Reputation
        harness.truthy(R.Update("Me-R", { [THORIUM] = { s = 5, v = 1, m = 6000 }, [99999] = { s = 8, v = 0, m = 999 },
            [TIMBERMAW] = { s = 12, v = 0, m = 1 } }, BIG))
        local record = R.Get("Me-R")
        harness.truthy(record.f[THORIUM]); harness.equal(record.f[99999], nil); harness.equal(record.f[TIMBERMAW], nil)
        harness.truthy(R.Sanitize(record), "my own record passes the peers' validation")
    end,

    ["reputation: persisted records are re-validated; migration 7 -> 8 keeps everything"] = function(harness)
        local addon = fresh(harness)
        local sv = { schema = 7, chars = {}, catalog = {}, orders = {}, offers = {}, hidden = {}, ui = {}, me = "Me-R",
            access = { ["A-R"] = { name = "A-R", rev = BIG - 5, keys = { [7146] = { bag = true } }, att = {} } },
            feedback = {}, feedbackState = {}, feedbackDelivered = {} }
        local out, status = addon.Store.Init(sv)
        harness.equal(status, "migrated"); harness.equal(out.schema, addon.Store.SCHEMA)
        harness.truthy(out.access["A-R"]); harness.equal(type(out.rep), "table")
        local sv2 = { schema = 8, rep = {
            ["A-R"] = { name = "A-R", rev = BIG - 5, f = { [THORIUM] = { s = 6, v = 1, m = 12000 } } },
            ["B-R"] = { name = "B-R", rev = BIG - 5, f = { [THORIUM] = { s = 99, v = 1, m = 12000 } } },
            ["C-R"] = { name = "X-R", rev = BIG - 5, f = {} } } }
        local out2 = addon.Store.Init(sv2)
        harness.truthy(out2.rep["A-R"]); harness.equal(out2.rep["B-R"], nil); harness.equal(out2.rep["C-R"], nil, "key and name differ")
    end,

    ["reputation: version reset drops peers' records, clean and prune remove them"] = function(harness)
        local addon = fresh(harness)
        local R = addon.Reputation
        R.Put({ name = "Me-R", rev = 1, f = {} }); R.Put({ name = "B-R", rev = 1, f = {} }); R.Put({ name = "C-R", rev = 1, f = {} })
        local removed = addon.Store.ResetPeerData("Me-R")
        harness.equal(removed.rep, 2); harness.truthy(R.Get("Me-R")); harness.equal(R.Get("B-R"), nil)
        R.Put({ name = "B-R", rev = 1, f = {} })
        addon.Store.Prune({ ["Me-R"] = true }, "Me-R")
        harness.equal(R.Get("B-R"), nil); harness.truthy(R.Get("Me-R"))
        addon.Store.Clean()
        harness.equal(R.Get("Me-R"), nil)
    end,

    ["reputation: two peers exchange their records over the codec (HELLO rrev -> WANTR -> REP)"] = function(harness)
        local b = bus()
        local a = peer(harness, b, "A-R", 7)
        local c = peer(harness, b, "C-R", 11)
        a.addon.Reputation.Update("A-R", { [THORIUM] = { s = 7, v = 500, m = 21000 } }, harness.clock)
        a.sync:Hello(true); c.sync:Hello(true)
        pump(b); advance(harness, b, 30)
        local got = c.addon.Reputation.Get("A-R")
        harness.truthy(got, "C pulled A's record"); harness.equal(got.f[THORIUM].s, 7)
        local sawWant, sawRep = false, false
        for _, it in ipairs(b.sent) do
            if it.msg.t == "WANTR" then sawWant = true end
            if it.msg.t == "REP" then sawRep = true end
        end
        harness.truthy(sawWant and sawRep)
        local changedKinds = table.concat(c.changes, ",")
        harness.truthy(changedKinds:find("rep", 1, true), "onChange(rep) fired: " .. changedKinds)
    end,

    ["reputation: a peer cannot write another member's record"] = function(harness)
        local b = bus()
        local c = peer(harness, b, "C-R", 11)
        local forged = { v = 2, t = "REP", rep = { name = "Victim-R", rev = BIG + 1, f = { [THORIUM] = { s = 8, v = 0, m = 999 } } } }
        c.sync:OnMessage(forged, "Evil-R")
        harness.equal(c.addon.Reputation.Get("Victim-R"), nil)
    end,

    ["reputation (RF5): a 1.3.0-style peer ignores rrev and WANTR, the other records still sync"] = function(harness)
        local b = bus()
        local a = peer(harness, b, "A-R", 7)
        local old = peer(harness, b, "Old-R", 13)
        -- a 1.3.0 build (protocol 2.5): no rep record kind at all
        old.sync.kinds.rep = nil
        for index, kind in ipairs(old.sync.kindOrder) do if kind.name == "rep" then table.remove(old.sync.kindOrder, index) end end
        local status = old.sync:OnMessage({ v = 2, t = "WANTR", names = { "Old-R" } }, "A-R")
        harness.truthy(status ~= "ok" and status ~= "error", "an unknown request type is not processed: " .. tostring(status))
        a.addon.Reputation.Update("A-R", { [THORIUM] = { s = 5, v = 1, m = 6000 } }, harness.clock)
        a.addon.Access.Update("A-R", { keys = { bag = { [7146] = true } }, att = {} }, harness.clock)
        a.sync:Hello(false); old.sync:Hello(false)
        advance(harness, b, 40)
        harness.truthy(old.addon.Access.Get("A-R"), "access still syncs next to rep")
        local wantCount = 0
        for _, it in ipairs(b.sent) do if it.msg.t == "WANTR" then wantCount = wantCount + 1 end end
        harness.equal(wantCount, 0, "the old peer never asks for rep")
    end,
}
