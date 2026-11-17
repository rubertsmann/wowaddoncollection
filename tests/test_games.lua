-- Guild games (feature 014): ISO week keys, coin flip rules, record validation, persistence, simulated players.
local NOW = 1794873600   -- 2026-11-17 00:00 UTC (a Tuesday, ISO 2026-W47)
local DAY = 86400

local function fresh(harness, now)
    local addon = harness.addon({ now = now or NOW })
    addon.Store.db.me = "Me-R"
    return addon
end

local function constant(value) return function() return value end end

-- a valid record of `name` with `count` flips of `stake` gold each (alternating win/loss), built through Games.Flip
local function record(harness, name, count, stake)
    local addon = fresh(harness)
    for index = 1, count do addon.Games.Flip(name, stake or 10, "H", NOW + index, constant(index % 2 == 1 and 0.1 or 0.9)) end
    return addon.Utility.DeepCopy(addon.Games.Get(name))
end

return {
    ["games: PeriodKey gives ISO 8601 weeks in UTC, including year edges (RF2)"] = function(harness)
        local addon = fresh(harness)
        local vectors = {
            { 1794873600, "2026-W47" },   -- 2026-11-17
            { 1798675200, "2026-W53" },   -- 2026-12-31
            { 1798934400, "2026-W53" },   -- 2027-01-03 (Sunday)
            { 1799020800, "2027-W01" },   -- 2027-01-04 (Monday)
            { 1609459200, "2020-W53" },   -- 2021-01-01
            { 1735516800, "2025-W01" },   -- 2024-12-30
        }
        for _, vector in ipairs(vectors) do harness.equal(addon.Games.PeriodKey(vector[1]), vector[2], "time " .. vector[1]) end
        -- Sunday 23:59:59 UTC is still that week; Monday 00:00:00 the next
        harness.equal(addon.Games.PeriodKey(1795392000 - 1), "2026-W47")
        harness.equal(addon.Games.PeriodKey(1795392000), "2026-W48")
        harness.equal(addon.Games.PreviousPeriodKey(NOW), "2026-W46")
    end,

    ["games: a flip wins or loses the stake and is stored at once (R2, R3)"] = function(harness)
        local addon = fresh(harness)
        local result = assert(addon.Games.Flip("Me-R", 250, "H", NOW, constant(0.1)))
        harness.equal(result.outcome, "H"); harness.equal(result.won, true); harness.equal(result.net, 250)
        local mine = addon.Games.Get("Me-R")
        harness.equal(mine.total.won, 250); harness.equal(mine.total.wins, 1); harness.equal(mine.rev, NOW)
        harness.equal(mine.weeks["2026-W47"].won, 250)
        harness.equal(mine.recent[1].c, 250); harness.equal(mine.recent[1].r, "W"); harness.equal(mine.recent[1].t, NOW)
        result = assert(addon.Games.Flip("Me-R", 40, "H", NOW, constant(0.9)))
        harness.equal(result.outcome, "T"); harness.equal(result.won, false); harness.equal(result.net, -40)
        mine = addon.Games.Get("Me-R")
        harness.equal(mine.total.lost, 40); harness.equal(mine.total.losses, 1); harness.equal(mine.recent[1].r, "L")
        harness.equal(mine.rev, NOW + 1, "rev strictly increases with an unchanged clock")
        harness.truthy(addon.Games.Sanitize(mine), "my own record passes peer validation")
        -- tails pick wins on tails
        harness.equal(assert(addon.Games.Flip("Me-R", 1, "T", NOW, constant(0.7))).won, true)
    end,

    ["games: invalid stakes and picks are refused and record nothing (R2)"] = function(harness)
        local addon = fresh(harness)
        for _, stake in ipairs({ 0, -5, 1.5, 1000000001, 0 / 0, 1 / 0, "10" }) do
            local result, refusal = addon.Games.Flip("Me-R", stake, "H", NOW, constant(0.1))
            harness.equal(result, nil); harness.equal(refusal, "stake", "stake " .. tostring(stake))
        end
        harness.equal(select(2, addon.Games.Flip("Me-R", 10, "X", NOW, constant(0.1))), "pick")
        harness.equal(addon.Games.Get("Me-R"), nil)
        harness.truthy(addon.Games.Flip("Me-R", 1000000000, "H", NOW, constant(0.1)), "the maximum stake (100 000g) is allowed")
    end,

    ["games: a readonly database refuses the flip (RF3)"] = function(harness)
        local addon = fresh(harness)
        addon.Store.db.readonly = true
        harness.equal(select(2, addon.Games.Flip("Me-R", 10, "H", NOW, constant(0.1))), "readonly")
        harness.equal(addon.Games.Get("Me-R"), nil)
    end,

    ["games: recent keeps the 20 newest, weeks keep the 4 newest"] = function(harness)
        local addon = fresh(harness)
        for index = 1, 25 do addon.Games.Flip("Me-R", index, "H", NOW + index, constant(0.1)) end
        local mine = addon.Games.Get("Me-R")
        harness.equal(#mine.recent, 20); harness.equal(mine.recent[1].c, 25); harness.equal(mine.recent[20].c, 6)
        harness.equal(mine.total.wins, 25)
        for week = 1, 5 do addon.Games.Flip("Me-R", 1, "H", NOW + week * 7 * DAY, constant(0.1)) end
        mine = addon.Games.Get("Me-R")
        harness.equal(addon.Utility.Count(mine.weeks), 4)
        harness.equal(mine.weeks["2026-W47"], nil, "the oldest week was pruned")
        harness.truthy(mine.weeks["2026-W52"])
    end,

    ["games: Sanitize rejects broken and forged records whole (RF1)"] = function(harness)
        local addon = fresh(harness)
        local good = record(harness, "Peer-R", 3, 10)
        harness.truthy(addon.Games.Sanitize(good))
        local function broken(change)
            local copy = addon.Utility.DeepCopy(good)
            change(copy)
            return addon.Games.Sanitize(copy)
        end
        local cases = {
            ["21 recent"] = function(r) for index = 1, 21 do r.recent[index] = { c = 1, r = "W", t = NOW } end end,
            ["bad r"] = function(r) r.recent[1].r = "X" end,
            ["c 0"] = function(r) r.recent[1].c = 0 end,
            ["c over max"] = function(r) r.recent[1].c = 1000000001 end,
            ["won < wins"] = function(r) r.total.won = 1; r.total.wins = 2 end,
            ["won > wins * max"] = function(r) r.total.won = 3000000000; r.total.wins = 2 end,
            ["lost > losses * max"] = function(r) r.total.lost = 2000000001 end,
            ["negative"] = function(r) r.total.lost = -1 end,
            ["week 54"] = function(r) r.weeks["2026-W54"] = r.weeks["2026-W47"] end,
            ["short key"] = function(r) r.weeks["26-W1"] = r.weeks["2026-W47"] end,
            ["future week"] = function(r) r.weeks["2026-W49"] = r.weeks["2026-W47"] end,
            ["5 weeks"] = function(r)
                for _, key in ipairs({ "2026-W40", "2026-W41", "2026-W42", "2026-W43" }) do r.weeks[key] = { won = 0, lost = 0, wins = 0, losses = 0 } end
            end,
            ["sparse recent"] = function(r) r.recent[5] = { c = 1, r = "W", t = NOW } end,
            ["recent not a table"] = function(r) r.recent = "x" end,
            ["inf rev"] = function(r) r.rev = 1 / 0 end,
            ["future flip"] = function(r) r.recent[1].t = NOW + 5 * DAY end,
            ["unsafe name"] = function(r) r.name = "A|cff-R" end,
        }
        for caseName, change in pairs(cases) do harness.equal(broken(change), nil, caseName) end
        harness.equal(addon.Games.Sanitize("record"), nil); harness.equal(addon.Games.Sanitize(nil), nil)
        -- next week's key is fine while the clock slack allows it (peer clock up to a day ahead on Sunday night)
        local sundayNight = fresh(harness, 1795392000 - 60)
        local ahead = addon.Utility.DeepCopy(good)
        ahead.weeks = { ["2026-W48"] = ahead.weeks["2026-W47"] }
        harness.truthy(sundayNight.Games.Sanitize(ahead), "a peer already in the next week")
        -- extra fields from a newer 2.x minor are dropped, not fatal (RF4)
        local extra = addon.Utility.DeepCopy(good); extra.future = { 1, 2 }; extra.total.bonus = 5
        local clean = assert(addon.Games.Sanitize(extra))
        harness.equal(clean.future, nil); harness.equal(clean.total.bonus, nil)
    end,

    ["games: totals clamp at the maxima and stay valid"] = function(harness)
        local addon = fresh(harness)
        addon.Store.db.games["Me-R"] = { name = "Me-R", rev = NOW, recent = {}, weeks = {},
            total = { won = addon.Games.MAXIMUM_TOTAL - 5, lost = 0, wins = 30000, losses = 0 } }
        addon.Games.Flip("Me-R", 1000000000, "H", NOW, constant(0.1))
        local mine = addon.Games.Get("Me-R")
        harness.equal(mine.total.won, addon.Games.MAXIMUM_TOTAL)
        harness.truthy(addon.Games.Sanitize(mine))
    end,

    ["games: persisted records are re-validated on load; key must equal the name"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local good = record(harness, "A-R", 2)
        local sv = { schema = 4, chars = {}, catalog = {}, orders = {}, offers = {}, hidden = {},
            games = { ["A-R"] = good, ["B-R"] = record(harness, "X-R", 1), ["C-R"] = { name = "C-R", rev = 1 / 0 } } }
        local out = addon.Store.Init(sv)
        harness.truthy(out.games["A-R"]); harness.equal(out.games["B-R"], nil); harness.equal(out.games["C-R"], nil)
    end,

    ["games: Put keeps only newer revisions"] = function(harness)
        local addon = fresh(harness)
        local peer = record(harness, "P-R", 2)
        harness.truthy(addon.Games.Put(peer))
        harness.equal(addon.Games.Put(addon.Utility.DeepCopy(peer)), false)
        local newer = addon.Utility.DeepCopy(peer); newer.rev = peer.rev + 1
        harness.truthy(addon.Games.Put(newer))
        harness.equal(addon.Games.Mine("P-R").rev, peer.rev + 1)
        harness.equal(addon.Games.Mine(nil), nil)
    end,

    ["games: simulated players never reach the db or Get (RF5)"] = function(harness)
        local addon = fresh(harness)
        local seed = 7
        local random = function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
        harness.equal(addon.Games.Simulate(12, NOW, random), 12)
        harness.equal(addon.Utility.Count(addon.Store.db.games), 0)
        harness.equal(addon.Games.Get("Sim1-Test"), nil)
        harness.equal(addon.Utility.Count(addon.Games.AllRecords()), 12)
        for _, simulatedRecord in pairs(addon.Games.simulated) do harness.truthy(addon.Games.Sanitize(simulatedRecord)) end
        addon.Games.Flip("Me-R", 5, "H", NOW, constant(0.1))
        harness.equal(addon.Utility.Count(addon.Games.AllRecords()), 13)
        addon.Games.Simulate(0, NOW, random)
        harness.equal(addon.Utility.Count(addon.Games.AllRecords()), 1)
    end,

    ["games: stakes are copper; gold/silver/copper boxes convert and split exactly"] = function(harness)
        local addon = fresh(harness)
        local Games = addon.Games
        harness.equal(Games.Money(1, 50, 25), 15025); harness.equal(Games.Money(nil, nil, 3), 3); harness.equal(Games.Money(0, 0, 0), 0)
        harness.equal(Games.Money(100000, 0, 0), Games.MAXIMUM_STAKE)
        for _, bad in ipairs({ { 0, 100, 0 }, { 0, 0, 100 }, { -1, 0, 0 }, { 1.5, 0, 0 }, { 100001, 0, 0 }, { "1", 0, 0 } }) do
            harness.equal(Games.Money(bad[1], bad[2], bad[3]), nil, table.concat({ tostring(bad[1]), tostring(bad[2]), tostring(bad[3]) }, ","))
        end
        local gold, silver, copper = Games.SplitMoney(15025)
        harness.equal(gold, 1); harness.equal(silver, 50); harness.equal(copper, 25)
        harness.equal(assert(Games.Flip("Me-R", 1, "H", NOW, constant(0.1))).net, 1, "one copper is a valid stake")
        harness.equal(addon.Model.MoneyText(15025):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "1g 50s 25c")
        harness.equal(addon.Model.MoneyText(5000):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "50s")
        harness.equal(addon.Model.MoneyText(0):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "0c")
    end,
}
