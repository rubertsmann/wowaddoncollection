-- Dungeon keys and raid attunements: access records, validation, persistence, migration, sync over the codec.
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

local function countSent(b, messageType)
    local n = 0
    for _, it in ipairs(b.sent) do if it.msg.t == messageType then n = n + 1 end end
    return n
end

return {
    ["access: protocol 2.4 and schema 6 are pinned"] = function(harness)
        local addon = fresh(harness)
        harness.equal(addon.PROTOCOL_MAJOR, 2); harness.equal(addon.PROTOCOL_MINOR, 4); harness.equal(addon.Store.SCHEMA, 6)
    end,

    ["access: a scan builds my record, the same scan changes nothing, a new key bumps rev"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        harness.truthy(Access.Update("Me-R", { keys = { bag = { [7146] = true } }, att = { mc = false } }, harness.clock))
        local rec = Access.Get("Me-R")
        harness.truthy(rec.keys[7146].bag); harness.equal(rec.att.mc, false); harness.equal(rec.rev, harness.clock)
        harness.equal(Access.Update("Me-R", { keys = { bag = { [7146] = true } }, att = { mc = false } }, harness.clock + 9), false)
        harness.equal(Access.Get("Me-R").rev, harness.clock)
        harness.truthy(Access.Update("Me-R", { keys = { bag = { [7146] = true, [12382] = true } } }, harness.clock + 9))
        harness.equal(Access.Get("Me-R").rev, harness.clock + 9)
    end,

    ["access: nothing held and nothing known creates no record (no rev churn on every login)"] = function(harness)
        local addon = fresh(harness)
        harness.equal(addon.Access.Update("Me-R", { keys = { bag = {} }, att = {} }, harness.clock), false)
        harness.equal(addon.Access.Get("Me-R"), nil)
    end,

    ["access (RF2): an unreadable location keeps its keys; a readable empty one drops them"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        Access.Update("Me-R", { keys = { bag = { [7146] = true }, bank = { [12382] = true } } }, harness.clock)
        -- bank closed: only the bags are in the scan
        Access.Update("Me-R", { keys = { bag = { [7146] = true } } }, harness.clock + 1)
        harness.truthy(Access.Get("Me-R").keys[12382], "bank key kept while the bank is closed")
        Access.Update("Me-R", { keys = { bag = { [7146] = true }, bank = {} } }, harness.clock + 2)
        harness.equal(Access.Get("Me-R").keys[12382], nil)
    end,

    ["access (RF3): an attunement the scan could not judge keeps its value; false and true are both kept"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        Access.Update("Me-R", { keys = {}, att = { mc = true, bwl = false } }, harness.clock)
        harness.equal(Access.Update("Me-R", { keys = {}, att = {} }, harness.clock + 5), false, "quest API missing: no change")
        harness.equal(Access.Get("Me-R").att.mc, true); harness.equal(Access.Get("Me-R").att.bwl, false)
        harness.truthy(Access.Update("Me-R", { keys = {}, att = { bwl = true } }, harness.clock + 6))
        harness.equal(Access.Get("Me-R").att.bwl, true)
        -- unknown attunement keys from a scan are ignored
        harness.equal(Access.Update("Me-R", { keys = {}, att = { aq40 = true } }, harness.clock + 7), false)
    end,

    ["access: deny-listed one-run keys are never recorded or listed"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        harness.equal(Access.IsKey(11078, 13), false); harness.equal(Access.IsKey(99999, 13), true)
        harness.equal(Access.IsKey(12344, 4), true, "Seal of Ascension is not class 13 but listed")
        harness.equal(Access.IsKey(99999, 4), false); harness.equal(Access.IsKey("7146", 13), false)
        Access.Update("Me-R", { keys = { bag = { [11078] = true, [7146] = true } } }, harness.clock)
        harness.equal(Access.Get("Me-R").keys[11078], nil); harness.truthy(Access.Get("Me-R").keys[7146])
    end,

    ["access (RF1): sanitize rejects bad records whole and copies good ones"] = function(harness)
        local addon = fresh(harness)
        local S = addon.Access.Sanitize
        local good = { name = "A-R", rev = BIG, keys = { [7146] = { bag = true, keyring = true } }, att = { mc = true, ony = false } }
        local clean = S(good)
        harness.truthy(clean and clean ~= good); harness.truthy(clean.keys[7146].keyring); harness.equal(clean.att.ony, false)
        harness.truthy(S({ name = "A-R", rev = BIG, keys = {} }), "att is optional")
        harness.equal(S({ name = "A-R", rev = BIG, keys = { [7146] = { vault = true } } }), nil, "unknown location")
        harness.equal(S({ name = "A-R", rev = BIG, keys = { [7146] = { bag = 1 } } }), nil, "location value must be true")
        harness.equal(S({ name = "A-R", rev = BIG, keys = { [7146] = {} } }), nil, "empty locations")
        harness.equal(S({ name = "A-R", rev = BIG, keys = {}, att = { mc = "yes" } }), nil, "non-boolean attunement")
        harness.equal(S({ name = "A-R", rev = BIG, keys = {}, att = { aq40 = true } }), nil, "unknown attunement key")
        harness.equal(S({ name = "A-R", rev = BIG + 10 * 86400, keys = {} }), nil, "revision from the future")
        harness.equal(S({ name = "|cffA-R", rev = BIG, keys = {} }), nil, "unsafe name")
        harness.equal(S({ name = "A-R", rev = BIG, keys = { [-1] = { bag = true } } }), nil, "bad item id")
        local many = {}
        for id = 1, 61 do many[id] = { bag = true } end
        harness.equal(S({ name = "A-R", rev = BIG, keys = many }), nil, "too many keys")
    end,

    ["access: a newer record replaces, an older or equal one does not"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        harness.truthy(Access.Put({ name = "A-R", rev = 10, keys = {}, att = {} }))
        harness.equal(Access.Put({ name = "A-R", rev = 10, keys = { [7146] = { bag = true } }, att = {} }), false)
        harness.truthy(Access.Put({ name = "A-R", rev = 11, keys = { [7146] = { bag = true } }, att = {} }))
    end,

    ["access: lists holders per key and attunement status per raid"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        Access.Put({ name = "B-R", rev = 1, keys = { [7146] = { bag = true } }, att = { mc = true, bwl = false } })
        Access.Put({ name = "A-R", rev = 1, keys = { [7146] = { bank = true, keyring = true }, [11078] = { bag = true } }, att = { mc = true } })
        local holders = Access.KeyHolders()
        harness.equal(#holders[7146], 2); harness.equal(holders[7146][1].who, "A-R")
        harness.equal(holders[7146][1].locations[1], "keyring"); harness.equal(holders[7146][1].locations[2], "bank")
        harness.equal(holders[11078], nil, "deny-listed key from an older record is not listed")
        local status = Access.AttunementStatus()
        harness.equal(#status.mc.yes, 2); harness.equal(#status.bwl.no, 1); harness.equal(#status.naxx.yes, 0)
        local records, keys = Access.Counts()
        harness.equal(records, 2); harness.equal(keys, 3)
    end,

    ["access: migration 5 -> 6 adds the table and keeps everything; persisted records are re-validated"] = function(harness)
        local addon = fresh(harness)
        local sv = { schema = 5, chars = {}, catalog = {}, orders = {}, me = "Me-R",
            offers = { ["A-R"] = { name = "A-R", rev = BIG - 5, items = { [6661] = { bag = 1 } }, dibs = {} } }, hidden = {}, ui = {} }
        local out, status = addon.Store.Init(sv)
        harness.equal(status, "migrated"); harness.equal(out.schema, 6)
        harness.truthy(out.offers["A-R"]); harness.equal(type(out.access), "table")
        local other = fresh(harness)
        local out2 = other.Store.Init({ schema = 6, chars = {}, catalog = {}, orders = {}, offers = {}, hidden = {}, ui = {},
            access = { ["A-R"] = { name = "A-R", rev = BIG - 5, keys = { [7146] = { bag = true } } },
                ["B-R"] = { name = "C-R", rev = BIG - 5, keys = {} },
                ["D-R"] = { name = "D-R", rev = BIG - 5, keys = { [7146] = { bag = "x" } } } } })
        harness.truthy(out2.access["A-R"]); harness.equal(out2.access["B-R"], nil, "key and name differ")
        harness.equal(out2.access["D-R"], nil)
    end,

    ["access: roster prune, peer reset and clean include access records"] = function(harness)
        local addon = fresh(harness)
        local Access = addon.Access
        Access.Put({ name = "Me-R", rev = 1, keys = {}, att = { mc = true } })
        Access.Put({ name = "Gone-R", rev = 1, keys = {}, att = { mc = true } })
        Access.Put({ name = "Fake Keyholder-R", rev = 1, keys = {}, att = { naxx = true } })
        addon.Store.keptNames["Fake Keyholder-R"] = true
        addon.Store.Prune({ ["Me-R"] = true }, "Me-R")
        harness.equal(Access.Get("Gone-R"), nil); harness.truthy(Access.Get("Me-R"))
        harness.truthy(Access.Get("Fake Keyholder-R"), "a dev fake record in keptNames survives the prune")
        Access.Put({ name = "Peer-R", rev = 1, keys = {}, att = { mc = true } })
        local removed = addon.Store.ResetPeerData("Me-R")
        harness.equal(removed.access, 2, "the peer and the dev fake record"); harness.truthy(Access.Get("Me-R"))
        addon.Store.Clean()
        harness.equal(Access.Get("Me-R"), nil)
    end,

    ["access sync: a changed record reaches a peer once; afterwards only arev travels"] = function(harness)
        local b = bus()
        local alice = peer(harness, b, "Alice-R", 7)
        local bob = peer(harness, b, "Bob-R", 11)
        alice.addon.Access.Update("Alice-R", { keys = { keyring = { [13704] = true } }, att = { mc = true } }, harness.clock)
        alice.sync:Hello(false); bob.sync:Hello(false)
        advance(harness, b, 40)
        local got = bob.addon.Access.Get("Alice-R")
        harness.truthy(got, "bob holds alice's access record"); harness.truthy(got.keys[13704].keyring); harness.equal(got.att.mc, true)
        local answers = countSent(b, "ACCESS")
        harness.equal(answers, 1)
        alice.sync:Hello(false); bob.sync:Hello(false)
        advance(harness, b, 40)
        harness.equal(countSent(b, "ACCESS"), answers, "no new ACCESS without a change")
        harness.equal(countSent(b, "WANTA"), 1)
    end,

    ["access sync (RF1): an ACCESS record authored by someone else is dropped"] = function(harness)
        local b = bus()
        local bob = peer(harness, b, "Bob-R", 11)
        local status = bob.sync:OnMessage({ v = 2, t = "ACCESS", access = { name = "Carol-R", rev = BIG, keys = {}, att = { mc = true } } }, "Mallory-R")
        harness.truthy(status ~= "ok"); harness.equal(bob.addon.Access.Get("Carol-R"), nil)
        bob.sync:OnMessage({ v = 2, t = "ACCESS", access = { name = "Mallory-R", rev = BIG, keys = { [1] = { bag = 2 } } } }, "Mallory-R")
        harness.equal(bob.addon.Access.Get("Mallory-R"), nil, "invalid record dropped")
    end,

    ["access sync (RF4): a 2.3 peer without the access kind keeps syncing offers and ignores arev"] = function(harness)
        local b = bus()
        local alice = peer(harness, b, "Alice-R", 7)
        local old = peer(harness, b, "Old-R", 11)
        -- a 2.3 build: no access record kind at all
        old.sync.kinds.access = nil
        for index, kind in ipairs(old.sync.kindOrder) do if kind.name == "access" then table.remove(old.sync.kindOrder, index) end end
        alice.addon.Access.Update("Alice-R", { keys = { bag = { [7146] = true } } }, harness.clock)
        alice.addon.Offers.Update("Alice-R", { bag = { [6661] = 1 } }, harness.clock)
        alice.sync:Hello(false); old.sync:Hello(false)
        advance(harness, b, 40)
        harness.truthy(old.addon.Offers.Get("Alice-R"), "offers still sync")
        harness.equal(old.addon.Access.Get("Alice-R"), nil)
        harness.equal(countSent(b, "WANTA"), 0)
    end,
}
