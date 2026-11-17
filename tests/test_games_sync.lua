-- Guild games over the wire (feature 014, R5, RF1, RF4, RF5): HELLO.grev -> WANTG -> GAMES, retries, forgery, coalesced HELLO.
local BIG = 1794873600   -- 2026-11-17 00:00 UTC: week keys are valid and "the future" is decidable

local function peer(harness, bus, name, seed)
    local addon = harness.addon({ now = harness.clock > 1e9 and harness.clock or BIG })
    addon.Store.db.me = name
    local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    local rngState = seed
    local p = { name = name, addon = addon, changes = {} }
    p.sync = addon.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return harness.clock end,
        random = function() rngState = (rngState * 1103515245 + 12345) % 2147483648; return rngState / 2147483648 end,
        store = addon.Store, orders = orders, me = name,
        onChange = function(kind) p.changes[#p.changes + 1] = kind end,
    })
    bus.peers[name] = p
    return p
end

local function newBus() return { peers = {}, queue = {}, log = {} } end

local function pump(bus, drop)
    local guard = 0
    while #bus.queue > 0 and guard < 20000 do
        guard = guard + 1
        local item = table.remove(bus.queue, 1)
        bus.log[#bus.log + 1] = item
        local wire = bus.peers[item.from].addon.Codec.Encode(item.msg)
        for name, p in pairs(bus.peers) do
            local to = (item.dist == "GUILD" and name ~= item.from) or (item.dist == "WHISPER" and name == item.target)
            if to and not (drop and drop(item)) then p.sync:OnMessage(assert(p.addon.Codec.Decode(wire)), item.from) end
        end
    end
end

local function advance(harness, bus, seconds, drop)
    for _ = 1, seconds do
        harness.clock = harness.clock + 1
        for _, p in pairs(bus.peers) do p.sync:Tick(harness.clock) end
        pump(bus, drop)
    end
end

local function sent(bus, messageType)
    local found = {}
    for _, item in ipairs(bus.log) do if item.msg.t == messageType then found[#found + 1] = item end end
    return found
end

local function flip(p, harness, stake, random)
    return assert(p.addon.Games.Flip(p.name, stake, "H", harness.clock, function() return random or 0.1 end))
end

return {
    ["games sync: HELLO(grev) -> WANTG whisper -> GAMES stores the record and reports 'games'"] = function(harness)
        harness.clock = BIG
        local bus = newBus()
        local a, b = peer(harness, bus, "A-R", 1), peer(harness, bus, "B-R", 2)
        flip(a, harness, 250)
        a.sync:Hello(false)
        harness.equal(bus.queue[1].msg.grev, a.addon.Games.Get("A-R").rev)
        pump(bus); advance(harness, bus, 5)
        local wants = sent(bus, "WANTG")
        harness.equal(#wants, 1); harness.equal(wants[1].dist, "WHISPER"); harness.equal(wants[1].target, "A-R")
        local got = b.addon.Games.Get("A-R")
        harness.truthy(got); harness.equal(got.total.won, 250); harness.equal(got.recent[1].c, 250)
        harness.equal(b.changes[#b.changes], "games")
        -- the same rev announced again pulls nothing
        a.sync:Hello(false); pump(bus); advance(harness, bus, 5)
        harness.equal(#sent(bus, "WANTG"), 1)
    end,

    ["games sync: an unanswered whisper is retried on GUILD with via and answered on GUILD"] = function(harness)
        harness.clock = BIG
        local bus = newBus()
        local a, b, c = peer(harness, bus, "A-R", 1), peer(harness, bus, "B-R", 2), peer(harness, bus, "C-R", 3)
        flip(a, harness, 10)
        local function dropWhispers(item) return item.dist == "WHISPER" end
        a.sync:Hello(false); pump(bus, dropWhispers)
        advance(harness, bus, 50, dropWhispers)
        local guildWants = {}
        for _, item in ipairs(sent(bus, "WANTG")) do if item.dist == "GUILD" then guildWants[#guildWants + 1] = item end end
        harness.truthy(#guildWants >= 1); harness.equal(guildWants[1].msg.via, "GUILD")
        harness.truthy(b.addon.Games.Get("A-R"), "B got it on GUILD"); harness.truthy(c.addon.Games.Get("A-R"), "C got it too")
    end,

    ["games sync: forged, broken and older GAMES are refused; invalid grev is noted (RF1)"] = function(harness)
        harness.clock = BIG
        local bus = newBus()
        local a, b = peer(harness, bus, "A-R", 1), peer(harness, bus, "B-R", 2)
        flip(b, harness, 10)
        local real = b.addon.Utility.DeepCopy(b.addon.Games.Get("B-R"))
        local P = a.addon.PROTOCOL
        -- C claims to author B's record
        local status = a.sync:OnMessage({ t = "GAMES", v = P, games = real }, "C-R")
        harness.equal(status, "error"); harness.equal(a.addon.Games.Get("B-R"), nil)
        local broken = a.addon.Utility.DeepCopy(real); broken.total.won = 1e15   -- more than wins * MAXIMUM_STAKE
        harness.equal(a.sync:OnMessage({ t = "GAMES", v = P, games = broken }, "B-R"), "error")
        harness.equal(a.sync:OnMessage({ t = "GAMES", v = P, games = "x" }, "B-R"), "error")
        harness.equal(a.sync:OnMessage({ t = "GAMES", v = P, games = real }, "B-R"), "ok")
        local older = a.addon.Utility.DeepCopy(real); older.rev = real.rev - 1
        local olderStatus, reason = a.sync:OnMessage({ t = "GAMES", v = P, games = older }, "B-R")
        harness.equal(olderStatus, "ignored"); harness.truthy(reason:find("not newer"))
        for _, grev in ipairs({ 1 / 0, "x", BIG * 5, -1 }) do
            local _, note = a.sync:OnMessage({ t = "HELLO", v = P, rev = 0, grev = grev }, "B-R")
            harness.truthy(note:find("games: invalid grev ignored", 1, true), tostring(grev))
        end
        harness.equal(#bus.queue, 0, "no WANTG for a hostile grev")
        -- a 2.2 peer's HELLO has no grev: nothing about games
        local _, note = a.sync:OnMessage({ t = "HELLO", v = P, rev = 0 }, "B-R")
        harness.truthy(not note:find("games", 1, true))
    end,

    ["games sync: WANTG is answered only for my own name, never with simulated records (RF5)"] = function(harness)
        harness.clock = BIG
        local bus = newBus()
        local a = peer(harness, bus, "A-R", 1)
        local P = a.addon.PROTOCOL
        a.addon.Games.Simulate(5, harness.clock, function() return 0.3 end)
        local status, reason = a.sync:OnMessage({ t = "WANTG", v = P, names = { "A-R" } }, "B-R")
        harness.equal(status, "ignored"); harness.truthy(reason:find("none"))
        a.sync:OnMessage({ t = "WANTG", v = P, names = { "Sim1-Test" } }, "B-R")
        a.sync:Hello(false)
        harness.equal(bus.queue[1].msg.grev, nil, "no grev without a real record")
        flip(a, harness, 5)
        a.sync:OnMessage({ t = "WANTG", v = P, names = { "Other-R" } }, "B-R")
        a.sync:OnMessage({ t = "WANTG", v = P, names = { "A-R" } }, "B-R")
        advance(harness, bus, 3)
        local answers = sent(bus, "GAMES")
        harness.equal(#answers, 1); harness.equal(answers[1].msg.games.name, "A-R"); harness.equal(answers[1].dist, "WHISPER")
    end,

    ["games sync: flip spam is announced by coalesced HELLOs, at most one per 30 s (RF5)"] = function(harness)
        harness.clock = BIG
        local addon = harness.addon({ now = BIG })
        local Communication = addon.Communication
        local hellos = {}
        Communication.active = true
        Communication.sync = { Hello = function() hellos[#hellos + 1] = harness.clock end }
        Communication.lastHello = 0
        for second = 0, 59 do
            harness.clock = BIG + second
            if second % 6 == 0 then Communication.RequestHelloSoon() end   -- ten flips in a minute
            Communication.SendDueHello(harness.clock)
        end
        harness.equal(#hellos, 2, "one at once, one due after 30 s (so far)")
        harness.equal(hellos[1], BIG); harness.equal(hellos[2], BIG + 30)
        harness.clock = BIG + 60   -- the flips at 36..54 s are announced by one more HELLO
        Communication.SendDueHello(harness.clock)
        harness.equal(#hellos, 3); harness.equal(hellos[3], BIG + 60)
        harness.clock = BIG + 200
        Communication.SendDueHello(harness.clock)
        harness.equal(#hellos, 3, "nothing due without a new flip")
        Communication.active = false
        Communication.RequestHelloSoon()
        harness.equal(#hellos, 3, "inactive: nothing sent")
    end,

    ["games soak: 10 peers flipping under 10% loss converge on every leaderboard"] = function(harness)
        harness.clock = BIG
        local bus = newBus()
        local peers = {}
        for index = 1, 10 do peers[index] = peer(harness, bus, "P" .. index .. "-R", index) end
        math.randomseed(14)
        local function lossy() return math.random() < 0.10 end
        for minute = 1, 10 do
            for second = 1, 60 do
                harness.clock = harness.clock + 1
                for _, p in ipairs(peers) do p.sync:Tick(harness.clock) end
                if second == 1 then
                    for _, p in ipairs(peers) do
                        if math.random() < 0.6 then flip(p, harness, math.random(1, 500), math.random()) end
                        p.sync:Hello(minute == 1)
                    end
                end
                pump(bus, lossy)
            end
        end
        -- quiet anti-entropy rounds on a reliable network, long enough for the retry schedule (45 + 90 + 180 s) of a pull
        -- whose messages were lost at the end of the lossy phase
        for _ = 1, 6 do
            for _, p in ipairs(peers) do p.sync:Hello(false) end
            advance(harness, bus, 60)
        end
        for _, p in ipairs(peers) do
            for _, q in ipairs(peers) do
                local theirs = q.addon.Games.Get(q.name)
                if theirs then
                    local held = p.addon.Games.Get(q.name)
                    harness.truthy(held, p.name .. " lacks " .. q.name)
                    harness.equal(held.rev, theirs.rev, p.name .. " holds an old record of " .. q.name)
                    harness.equal(held.total.won - held.total.lost, theirs.total.won - theirs.total.lost)
                end
            end
        end
    end,
}
