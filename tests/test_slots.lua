-- Slot machine rules (feature 014, second game): strip, paylines, payouts, storage before animation, reel motion,
-- record validation of the slots section, and the per-game leaderboards.
local NOW = 1794873600   -- 2026-11-17 00:00 UTC

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = "Me-R"
    return addon
end

-- a random function that returns the given values in turn
local function sequence(values)
    local index = 0
    return function() index = index % #values + 1; return values[index] end
end

-- the random value that makes Slots.Spin pick 1-based stop `stop`
local function stopValue(addon, stop) return (stop - 1 + 0.5) / #addon.Slots.STRIP end

-- first strip index whose three consecutive symbols are a, b, c (nil = any)
local function findStop(addon, wanted)
    for stop = 1, #addon.Slots.STRIP do
        local ok = true
        for row = 1, 3 do
            if wanted[row] and addon.Slots.SymbolAt(stop + row - 1) ~= wanted[row] then ok = false end
        end
        if ok then return stop end
    end
end

return {
    ["slots: the strip holds every symbol `weight` times and the constants agree"] = function(harness)
        local addon = fresh(harness)
        local Slots = addon.Slots
        local counts, total = {}, 0
        for _, key in ipairs(Slots.STRIP) do counts[key] = (counts[key] or 0) + 1 end
        for _, symbol in ipairs(Slots.SYMBOLS) do harness.equal(counts[symbol.key], symbol.weight, symbol.key); total = total + symbol.weight end
        harness.equal(#Slots.STRIP, total)
        harness.equal(Slots.MAXIMUM_MULTIPLIER, addon.Games.SLOTS_MAXIMUM_MULTIPLIER)
        harness.equal(#Slots.LINES, 5)
        harness.equal(Slots.SymbolAt(#Slots.STRIP + 1), Slots.STRIP[1]); harness.equal(Slots.SymbolAt(0), Slots.STRIP[#Slots.STRIP])
    end,

    ["slots: rows, both diagonals and several lines at once are paid; anything else is not"] = function(harness)
        local Slots = fresh(harness).Slots
        local pays = function(key) return Slots.BY_KEY[key].pays end
        local lines, multiplier = Slots.Evaluate({ { "bag", "bag", "bag" }, { "rune", "sword", "potion" }, { "coin", "crown", "coin" } })
        harness.equal(#lines, 1); harness.equal(lines[1].line, 1); harness.equal(multiplier, pays("bag"))
        lines, multiplier = Slots.Evaluate({ { "crown", "bag", "rune" }, { "bag", "crown", "sword" }, { "rune", "potion", "crown" } })
        harness.equal(#lines, 1); harness.equal(lines[1].line, 4, "top-left to bottom-right"); harness.equal(multiplier, pays("crown"))
        lines = Slots.Evaluate({ { "bag", "bag", "sword" }, { "rune", "sword", "potion" }, { "sword", "crown", "coin" } })
        harness.equal(#lines, 1); harness.equal(lines[1].line, 5, "bottom-left to top-right")
        lines, multiplier = Slots.Evaluate({ { "coin", "coin", "coin" }, { "coin", "coin", "coin" }, { "coin", "coin", "coin" } })
        harness.equal(#lines, 5); harness.equal(multiplier, Slots.MAXIMUM_MULTIPLIER)
        lines, multiplier = Slots.Evaluate({ { "bag", "rune", "bag" }, { "rune", "bag", "rune" }, { "potion", "sword", "potion" } })
        harness.equal(#lines, 0); harness.equal(multiplier, 0)
    end,

    ["slots: return to player is about 94% and a long simulation agrees"] = function(harness)
        local addon = fresh(harness)
        local rtp = addon.Slots.ReturnToPlayer()
        harness.truthy(rtp > 0.9 and rtp < 0.97, "rtp " .. rtp)
        local seed, paid, staked = 11, 0, 0
        local random = function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
        for _ = 1, 20000 do
            local result = assert(addon.Slots.Spin("Me-R", 100, NOW, random))
            paid, staked = paid + result.payout, staked + 100
        end
        harness.truthy(math.abs(paid / staked - rtp) < 0.08, "simulated " .. paid / staked .. " vs " .. rtp)
    end,

    ["slots: a spin is stored in the slots section before any animation; the coin board is untouched (R3)"] = function(harness)
        local addon = fresh(harness)
        local stop = assert(findStop(addon, { "bag" }))
        local result = assert(addon.Slots.Spin("Me-R", 250, NOW, sequence({ stopValue(addon, stop) })))
        harness.equal(result.stops[1], stop); harness.equal(result.stops[2], stop); harness.equal(result.stops[3], stop)
        harness.truthy(result.multiplier >= addon.Slots.BY_KEY.bag.pays, "same stop on every reel: every row pays")
        harness.equal(result.payout, 250 * result.multiplier); harness.equal(result.net, result.payout - 250)
        local mine = addon.Games.Get("Me-R")
        harness.equal(mine.slots.total.won, result.net); harness.equal(mine.slots.total.wins, 1)
        harness.equal(mine.slots.recent[1].c, 250); harness.equal(mine.slots.recent[1].n, result.net)
        harness.equal(mine.total.wins + mine.total.losses, 0, "the coin flip section has no play")
        harness.truthy(addon.Games.Sanitize(mine), "my own record passes peer validation")
        -- a losing spin costs exactly the stake
        local loss
        for first = 1, #addon.Slots.STRIP do
            local candidate = addon.Slots.Grid({ first, first + 5, first + 11 })
            if select(2, addon.Slots.Evaluate(candidate)) == 0 then loss = first break end
        end
        local L = #addon.Slots.STRIP
        local values = { stopValue(addon, loss), stopValue(addon, (loss + 4) % L + 1), stopValue(addon, (loss + 10) % L + 1) }
        local lost = assert(addon.Slots.Spin("Me-R", 40, NOW + 1, sequence(values)))
        harness.equal(lost.multiplier, 0); harness.equal(lost.net, -40)
        harness.equal(addon.Games.Get("Me-R").slots.total.lost, 40)
    end,

    ["slots: refused stakes and a readonly db record nothing"] = function(harness)
        local addon = fresh(harness)
        for _, stake in ipairs({ 0, -1, 1.5, addon.Games.MAXIMUM_STAKE + 1, "5" }) do
            harness.equal(select(2, addon.Slots.Spin("Me-R", stake, NOW, math.random)), "stake")
        end
        addon.Store.db.readonly = true
        harness.equal(select(2, addon.Slots.Spin("Me-R", 10, NOW, math.random)), "readonly")
        harness.equal(addon.Games.Get("Me-R"), nil)
    end,

    ["slots: Sanitize checks the slots section like the coin section (RF1)"] = function(harness)
        local addon = fresh(harness)
        local seed = 5
        local random = function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
        for index = 1, 30 do addon.Slots.Spin("Me-R", 100 + index, NOW + index, random) end
        addon.Games.Flip("Me-R", 10, "H", NOW + 40, function() return 0.1 end)
        local good = addon.Utility.DeepCopy(addon.Games.Get("Me-R"))
        harness.truthy(addon.Games.Sanitize(good))
        local function broken(change)
            local copy = addon.Utility.DeepCopy(good); change(copy)
            return addon.Games.Sanitize(copy)
        end
        local cases = {
            ["net between -c and c"] = function(r) r.slots.recent[1].n = 5 end,
            ["loss not equal to the stake"] = function(r) r.slots.recent[1].n = -1 end,
            ["net over the maximum"] = function(r) r.slots.recent[1].n = r.slots.recent[1].c * addon.Games.SLOTS_MAXIMUM_MULTIPLIER end,
            ["missing net"] = function(r) r.slots.recent[1].n = nil end,
            ["won over the maximum"] = function(r) r.slots.total.won = 1e18 end,
            ["slots not a table"] = function(r) r.slots = "x" end,
            ["21 recent"] = function(r) for index = 1, 21 do r.slots.recent[index] = { c = 1, n = -1, t = NOW } end end,
        }
        for caseName, change in pairs(cases) do harness.equal(broken(change), nil, caseName) end
        local withoutSlots = addon.Utility.DeepCopy(good); withoutSlots.slots = nil
        harness.equal(assert(addon.Games.Sanitize(withoutSlots)).slots, nil, "a record without slots is fine")
        harness.equal(pcall(addon.Games.RecordPlay, "Me-R", "coin", 10, 10, NOW), false, "coin plays go through Flip")
        harness.equal(pcall(addon.Games.RecordPlay, "Me-R", "slots", 10, 3, NOW), false, "a net between -stake and stake is a bug")
    end,

    ["slots: each game has its own leaderboard and feed (R6, R7)"] = function(harness)
        local addon = fresh(harness)
        addon.Games.Flip("Coin-R", 500, "H", NOW, function() return 0.1 end)
        local stop = assert(findStop(addon, { "bag" }))
        addon.Slots.Spin("Slot-R", 100, NOW, sequence({ stopValue(addon, stop) }))
        local records = addon.Games.AllRecords()
        local coinBoard = addon.Model.BuildLeaderboardRows(records, "all", "2026-W47", nil, "coin")
        local slotBoard = addon.Model.BuildLeaderboardRows(records, "all", "2026-W47", nil, "slots")
        harness.equal(#coinBoard, 1); harness.equal(coinBoard[1].nameRaw, "Coin-R")
        harness.equal(#slotBoard, 1); harness.equal(slotBoard[1].nameRaw, "Slot-R"); harness.truthy(slotBoard[1].net > 0)
        harness.equal(#addon.Model.BuildLeaderboardRows(records, "week", "2026-W47", nil, "slots"), 1)
        local feed = addon.Model.BuildFlipFeedRows(records, nil, 15, "slots")
        harness.equal(#feed, 1); harness.equal(feed[1].net, slotBoard[1].net)
        harness.equal(addon.Model.BuildFlipFeedRows(records, nil, 15)[1].nameRaw, "Coin-R", "default game is the coin flip")
    end,

    ["slots: reels start where they stood, run past the stop, settle exactly on it, left to right"] = function(harness)
        local Slots = fresh(harness).Slots
        local L = #Slots.STRIP
        for reel = 1, Slots.REELS do
            local fromStop, toStop = 7, 30
            local start = Slots.ReelPose(0, reel, fromStop, toStop)
            harness.equal(start.index, fromStop)
            local finish = Slots.ReelPose(Slots.ReelDuration(reel), reel, fromStop, toStop)
            harness.truthy(finish.done); harness.equal(finish.index, toStop)
            local beforeSettle = Slots.ReelPose(Slots.ReelDuration(reel) - Slots.SETTLE_SECONDS, reel, fromStop, toStop)
            local normalized = (beforeSettle.index - toStop) % L
            harness.truthy(math.abs(normalized - (L - Slots.OVERSHOOT)) < 1e-6, "overshoot past the stop")
            local previous = start.index
            for step = 1, 100 do
                local pose = Slots.ReelPose((Slots.ReelDuration(reel) - Slots.SETTLE_SECONDS) * step / 100, reel, fromStop, toStop)
                harness.truthy(pose.index <= previous + 1e-9, "the reel only turns one way before settling")
                previous = pose.index
            end
            if reel > 1 then harness.truthy(Slots.ReelDuration(reel) > Slots.ReelDuration(reel - 1)) end
        end
        harness.equal(Slots.SpinDuration(), Slots.ReelDuration(Slots.REELS))
    end,
}
