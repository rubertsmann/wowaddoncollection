-- Sync protocol over an in-memory network (RF3, RF5)
local function peer(h, bus, name, seed)
    local ns = h.ns()
    ns.Store.db.me = name
    local orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
    local rngState = seed
    local p = { name = name, ns = ns, orders = orders, changes = 0 }
    p.sync = ns.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return h.clock end,
        rand = function() rngState = (rngState * 1103515245 + 12345) % 2147483648; return rngState / 2147483648 end,
        store = ns.Store, orders = orders, me = name,
        onChange = function() p.changes = p.changes + 1 end,
    })
    bus.peers[name] = p
    return p
end

local function newBus() return { peers = {}, queue = {}, delivered = 0 } end

-- deliver everything queued (messages are tables; round-trip through the codec so the wire format is covered)
local function pump(h, bus, drop)
    local guard = 0
    while #bus.queue > 0 and guard < 5000 do
        guard = guard + 1
        local item = table.remove(bus.queue, 1)
        local sender = bus.peers[item.from]
        local wire = sender.ns.Codec.Encode(item.msg)
        for name, p in pairs(bus.peers) do
            local to = (item.dist == "GUILD" and name ~= item.from) or (item.dist == "WHISPER" and name == item.target)
            if to and not (drop and drop()) then
                local msg = assert(p.ns.Codec.Decode(wire))
                p.sync:OnMessage(msg, item.from)
                bus.delivered = bus.delivered + 1
            end
        end
    end
end

local function advance(h, bus, seconds)
    for _ = 1, seconds do
        h.clock = h.clock + 1
        for _, p in pairs(bus.peers) do p.sync:Tick(h.clock) end
        pump(h, bus)
    end
end

return {
    ["sync: a peer with a newer record is pulled via HELLO -> WANT -> SNAP"] = function(h)
        local bus = newBus()
        local a, b = peer(h, bus, "A-R", 1), peer(h, bus, "B-R", 2)
        a.ns.Store.PutChar(h.char("A-R", 50, { 1, 2 }))
        a.ns.Store.PutCatalog({ [1] = { name = "R1", reagents = { { itemID = 9, count = 1 } } } })
        a.sync:Hello(false)
        pump(h, bus); advance(h, bus, 5)
        local got = b.ns.Store.GetChar("A-R")
        h.truthy(got); h.eq(got.rev, 50); h.eq(b.ns.Store.GetRecipe(1).name, "R1")
    end,

    ["sync: own echo, garbage and wrong version are dropped without errors (RF5)"] = function(h)
        local bus = newBus()
        local a = peer(h, bus, "A-R", 1)
        a.sync:OnMessage({ v = 1, t = "HELLO", rev = 1 }, "A-R")
        a.sync:OnMessage("junk", "B-R")
        a.sync:OnMessage({ v = 9, t = "HELLO", rev = 1 }, "B-R")
        a.sync:OnMessage({ v = 1, t = "NOPE" }, "B-R")
        a.sync:OnMessage({ v = 1, t = "HELLO", rev = "x" }, "B-R")
        a.sync:OnMessage({ v = 1, t = "SNAP", char = h.char("C-R", 5, {}) }, "B-R")   -- B claims to author C
        h.eq(a.sync.stats.dropped, 6); h.eq(a.ns.Store.GetChar("C-R"), nil)
    end,

    ["sync: a peer cannot overwrite my record with an older revision"] = function(h)
        local bus = newBus()
        local a = peer(h, bus, "A-R", 1)
        a.ns.Store.PutChar(h.char("B-R", 100, { 1 }))
        a.sync:OnMessage({ v = 1, t = "SNAP", char = h.char("B-R", 10, { 1, 2, 3 }), catalog = {} }, "B-R")
        h.eq(a.ns.Store.GetChar("B-R").rev, 100)
    end,

    ["sync: orders propagate by broadcast and reach a latecomer via HELLO digest"] = function(h)
        local bus = newBus()
        local a, b, c = peer(h, bus, "A-R", 1), peer(h, bus, "B-R", 2), peer(h, bus, "C-R", 3)
        local ord = a.orders:Create("A-R", 7, 2)
        a.sync:BroadcastOrder(ord)
        pump(h, bus)
        h.truthy(b.orders:Get(ord.id)); h.truthy(c.orders:Get(ord.id))
        local d = peer(h, bus, "D-R", 4)            -- joins later, has nothing
        d.sync:Hello(true)
        pump(h, bus); advance(h, bus, 15)
        h.truthy(d.orders:Get(ord.id))
    end,

    ["sync: concurrent claims over the wire converge on all peers (RF4)"] = function(h)
        local bus = newBus()
        local a, b, c = peer(h, bus, "A-R", 1), peer(h, bus, "B-R", 2), peer(h, bus, "C-R", 3)
        local ord = a.orders:Create("C-R", 7, 1)
        a.sync:BroadcastOrder(ord); pump(h, bus)
        h.clock = h.clock + 1
        a.sync:BroadcastOrder(a.orders:Claim(ord.id, "A-R"))
        b.sync:BroadcastOrder(b.orders:Claim(ord.id, "B-R"))
        pump(h, bus)
        for _, p in pairs({ a, b, c }) do h.eq(#p.orders:Claimers(p.orders:Get(ord.id)), 2, p.name) end
    end,

    ["sync: 40 peers logging in at once converge and stay within a bounded message count (RF3)"] = function(h)
        local bus = newBus()
        local peers = {}
        for i = 1, 40 do
            local p = peer(h, bus, "P" .. i .. "-R", i)
            p.ns.Store.PutChar(h.char(p.name, 100 + i, { i }))
            peers[#peers + 1] = p
        end
        for _, p in ipairs(peers) do p.sync:Hello(true) end
        pump(h, bus); advance(h, bus, 40)
        for _, p in ipairs(peers) do
            for _, q in ipairs(peers) do
                h.truthy(p.ns.Store.GetChar(q.name), p.name .. " lacks " .. q.name)
            end
        end
        local maxSent = 0
        for _, p in ipairs(peers) do maxSent = math.max(maxSent, p.sync.stats.sent) end
        -- 1 hello + <= 20 login replies + one WANT and one SNAP per other peer: linear, no duplicate pulls
        h.truthy(maxSent <= 3 * #peers, "a peer sent " .. maxSent .. " messages")
    end,
}
