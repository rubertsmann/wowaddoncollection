-- Sync protocol over an in-memory network (RF3, RF5)
local function peer(harness, bus, name, seed)
    local addon = harness.addon()
    addon.Store.db.me = name
    local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    local rngState = seed
    local p = { name = name, addon = addon, orders = orders, changes = 0 }
    p.sync = addon.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return harness.clock end,
        random = function() rngState = (rngState * 1103515245 + 12345) % 2147483648; return rngState / 2147483648 end,
        store = addon.Store, orders = orders, me = name,
        onChange = function() p.changes = p.changes + 1 end,
    })
    bus.peers[name] = p
    return p
end

local function newBus() return { peers = {}, queue = {}, delivered = 0 } end

-- deliver everything queued (messages are tables; round-trip through the codec so the wire format is covered)
local function pump(harness, bus, drop)
    local guard = 0
    while #bus.queue > 0 and guard < 5000 do
        guard = guard + 1
        local item = table.remove(bus.queue, 1)
        local sender = bus.peers[item.from]
        local wire = sender.addon.Codec.Encode(item.msg)
        for name, p in pairs(bus.peers) do
            local to = (item.dist == "GUILD" and name ~= item.from) or (item.dist == "WHISPER" and name == item.target)
            if to and not (drop and drop()) then
                local msg = assert(p.addon.Codec.Decode(wire))
                p.sync:OnMessage(msg, item.from)
                bus.delivered = bus.delivered + 1
            end
        end
    end
end

local function advance(harness, bus, seconds)
    for _ = 1, seconds do
        harness.clock = harness.clock + 1
        for _, p in pairs(bus.peers) do p.sync:Tick(harness.clock) end
        pump(harness, bus)
    end
end

return {
    ["sync: a peer with a newer record is pulled via HELLO -> WANT -> SNAP"] = function(harness)
        local bus = newBus()
        local a, b = peer(harness, bus, "A-R", 1), peer(harness, bus, "B-R", 2)
        a.addon.Store.PutCharacter(harness.character("A-R", 50, { 1, 2 }))
        a.addon.Store.PutCatalog({ [1] = { name = "R1", reagents = { { itemID = 9, count = 1 } } } })
        a.sync:Hello(false)
        pump(harness, bus); advance(harness, bus, 5)
        local got = b.addon.Store.GetCharacter("A-R")
        harness.truthy(got); harness.equal(got.rev, 50); harness.equal(b.addon.Store.GetRecipe(1).name, "R1")
    end,

    ["sync: own echo, garbage and wrong version are dropped without errors (RF5)"] = function(harness)
        local bus = newBus()
        local a = peer(harness, bus, "A-R", 1)
        a.sync:OnMessage({ v = a.addon.PROTOCOL, t = "HELLO", rev = 1 }, "A-R")
        a.sync:OnMessage("junk", "B-R")
        a.sync:OnMessage({ v = 9, t = "HELLO", rev = 1 }, "B-R")
        a.sync:OnMessage({ v = a.addon.PROTOCOL, t = "NOPE" }, "B-R")
        a.sync:OnMessage({ v = a.addon.PROTOCOL, t = "HELLO", rev = "x" }, "B-R")
        a.sync:OnMessage({ v = a.addon.PROTOCOL, t = "SNAP", char = harness.character("C-R", 5, {}) }, "B-R")   -- B claims to author C
        harness.equal(a.sync.statistics.dropped, 6); harness.equal(a.addon.Store.GetCharacter("C-R"), nil)
    end,

    ["sync: a peer cannot overwrite my record with an older revision"] = function(harness)
        local bus = newBus()
        local a = peer(harness, bus, "A-R", 1)
        a.addon.Store.PutCharacter(harness.character("B-R", 100, { 1 }))
        a.sync:OnMessage({ v = a.addon.PROTOCOL, t = "SNAP", char = harness.character("B-R", 10, { 1, 2, 3 }), catalog = {} }, "B-R")
        harness.equal(a.addon.Store.GetCharacter("B-R").rev, 100)
    end,

    ["sync: orders propagate by broadcast and reach a latecomer via HELLO digest"] = function(harness)
        local bus = newBus()
        local a, b, c = peer(harness, bus, "A-R", 1), peer(harness, bus, "B-R", 2), peer(harness, bus, "C-R", 3)
        local ord = a.orders:Create("A-R", 7, 2)
        a.sync:BroadcastOrder(ord)
        pump(harness, bus)
        harness.truthy(b.orders:Get(ord.id)); harness.truthy(c.orders:Get(ord.id))
        local d = peer(harness, bus, "D-R", 4)            -- joins later, has nothing
        d.sync:Hello(true)
        pump(harness, bus); advance(harness, bus, 15)
        harness.truthy(d.orders:Get(ord.id))
    end,

    ["sync: concurrent claims over the wire converge on all peers (RF4)"] = function(harness)
        local bus = newBus()
        local a, b, c = peer(harness, bus, "A-R", 1), peer(harness, bus, "B-R", 2), peer(harness, bus, "C-R", 3)
        local ord = a.orders:Create("C-R", 7, 1)
        a.sync:BroadcastOrder(ord); pump(harness, bus)
        harness.clock = harness.clock + 1
        a.sync:BroadcastOrder(a.orders:Claim(ord.id, "A-R"))
        b.sync:BroadcastOrder(b.orders:Claim(ord.id, "B-R"))
        pump(harness, bus)
        for _, p in pairs({ a, b, c }) do harness.equal(#p.orders:Claimers(p.orders:Get(ord.id)), 2, p.name) end
    end,

    ["sync: 40 peers logging in at once converge and stay within a bounded message count (RF3)"] = function(harness)
        local bus = newBus()
        local peers = {}
        for i = 1, 40 do
            local p = peer(harness, bus, "P" .. i .. "-R", i)
            p.addon.Store.PutCharacter(harness.character(p.name, 100 + i, { i }))
            peers[#peers + 1] = p
        end
        for _, p in ipairs(peers) do p.sync:Hello(true) end
        pump(harness, bus); advance(harness, bus, 40)
        for _, p in ipairs(peers) do
            for _, q in ipairs(peers) do
                harness.truthy(p.addon.Store.GetCharacter(q.name), p.name .. " lacks " .. q.name)
            end
        end
        local maxSent = 0
        for _, p in ipairs(peers) do maxSent = math.max(maxSent, p.sync.statistics.sent) end
        -- 1 hello + <= 20 login replies + one WANT and one SNAP per other peer: linear, no duplicate pulls
        harness.truthy(maxSent <= 3 * #peers, "a peer sent " .. maxSent .. " messages")
    end,
}
