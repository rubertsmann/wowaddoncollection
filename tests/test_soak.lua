-- T19 offline half: fuzzing (RF5) and a lossy-network soak with order churn (RF3/RF4)
local function peer(h, bus, name, seed)
    local ns = h.ns()
    ns.Store.db.me = name
    local orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
    local s = seed
    local p = { name = name, ns = ns, orders = orders }
    p.sync = ns.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return h.clock end,
        rand = function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end,
        store = ns.Store, orders = orders, me = name, onChange = function() end,
    })
    bus.peers[name] = p
    return p
end

return {
    ["fuzz: Codec.Decode and Sync.OnMessage never throw on random input (RF5)"] = function(h)
        local ns = h.ns()
        local p = peer(h, { peers = {}, queue = {} }, "A-R", 7)
        math.randomseed(12345)
        for _ = 1, 3000 do
            local len = math.random(0, 120)
            local bytes = {}
            for i = 1, len do bytes[i] = string.char(math.random(0, 255)) end
            local s = table.concat(bytes)
            local ok = pcall(ns.Codec.Decode, s)
            h.truthy(ok, "Decode threw")
            -- structurally plausible but hostile tables
            local msg = { v = ns.PROTOCOL, t = ({ "HELLO", "WANT", "SNAP", "OPUSH", "ORDER", "X" })[math.random(1, 6)],
                rev = math.random(-5, 5) == 0 and "x" or math.random(0, 1e9), names = math.random(0, 1) == 0 and 5 or { "A-R" },
                char = math.random(0, 1) == 0 and {} or { name = s, rev = 1, level = 999, professions = 3 },
                orders = math.random(0, 1) == 0 and "no" or { {}, 5, { id = s } }, order = { id = s, qty = {} }, odig = "z" }
            h.truthy(pcall(p.sync.OnMessage, p.sync, msg, "B-R"), "OnMessage threw")
        end
        h.eq(p.ns.Store.GetChar(s), nil)
    end,

    ["soak: 30 peers, 10% loss, order churn for 20 simulated minutes converge"] = function(h)
        local bus = { peers = {}, queue = {} }
        local peers, names = {}, {}
        for i = 1, 30 do
            local p = peer(h, bus, "P" .. i .. "-R", i)
            p.ns.Store.PutChar(h.char(p.name, 100 + i, { i }))
            peers[#peers + 1] = p; names[#names + 1] = p.name
        end
        math.randomseed(99)
        local function drop() return math.random() < 0.10 end
        local function pump()
            local guard = 0
            while #bus.queue > 0 and guard < 20000 do
                guard = guard + 1
                local item = table.remove(bus.queue, 1)
                local sender = bus.peers[item.from]
                local wire = sender.ns.Codec.Encode(item.msg)
                for name, p in pairs(bus.peers) do
                    local to = (item.dist == "GUILD" and name ~= item.from) or (item.dist == "WHISPER" and name == item.target)
                    if to and not drop() then
                        local m = assert(p.ns.Codec.Decode(wire))
                        p.sync:OnMessage(m, item.from)
                    end
                end
            end
        end
        local created = {}
        for minute = 1, 20 do
            for sec = 1, 60 do
                h.clock = h.clock + 1
                for _, p in ipairs(peers) do p.sync:Tick(h.clock) end
                if sec == 1 then
                    for _, p in ipairs(peers) do p.sync:Hello(minute == 1) end   -- periodic anti-entropy
                    local who = peers[math.random(1, #peers)]
                    local o = who.orders:Create(who.name, math.random(1, 50), 1)
                    created[#created + 1] = o.id
                    who.sync:BroadcastOrder(o)
                    local claimer = peers[math.random(1, #peers)]
                    if who.orders:Get(o.id) then claimer.orders:Merge(who.orders:Get(o.id)) end
                    local c = claimer.orders:Claim(o.id, claimer.name)
                    if c then claimer.sync:BroadcastOrder(c) end
                end
                pump()
            end
        end
        -- final quiet period with a few more anti-entropy rounds on a reliable network
        drop = function() return false end
        for _ = 1, 3 do
            for _, p in ipairs(peers) do p.sync:Hello(false) end
            for _ = 1, 20 do
                h.clock = h.clock + 1
                for _, p in ipairs(peers) do p.sync:Tick(h.clock) end
                pump()
            end
        end
        for _, p in ipairs(peers) do
            for _, q in ipairs(peers) do
                h.truthy(p.ns.Store.GetChar(q.name), p.name .. " lacks character " .. q.name)
            end
            for _, id in ipairs(created) do
                local mine, theirs = p.orders:Get(id), peers[1].orders:Get(id)
                h.truthy(mine, p.name .. " lacks order " .. id)
                h.eq(p.orders.Version(mine), p.orders.Version(theirs), "order versions differ")
            end
        end
    end,
}
