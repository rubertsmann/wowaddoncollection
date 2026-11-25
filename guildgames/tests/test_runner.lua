-- Runner game: physics, fair spawning, collision, the daily payout, saved data and the guild section.
local NOW = 1794873600
local ME = "Me-R"
local FRAME = 1 / 60

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = ME
    return addon
end

local POOL = { { npc = 1, disp = 0, n = "A", fly = false }, { npc = 2, disp = 0, n = "B", fly = true } }

-- an obstacle-free run: no spawns for a long while
local function emptyRun(Runner)
    local run = Runner.New(POOL, 7)
    run.spawnIn = 1e9
    return run
end

-- the input a careful player gives this frame: jump at a ground monster just ahead, duck under a flyer near the runner
local function autopilot(Runner, run)
    local front = Runner.RUNNER_X + Runner.RUNNER_WIDTH
    local input = {}
    for _, obstacle in ipairs(run.obstacles) do
        local ahead = obstacle.x - front
        if obstacle.fly then
            if ahead < run.speed * 0.12 and obstacle.x + Runner.BOX > Runner.RUNNER_X then input.duck = true end
        elseif ahead > 0 and ahead < run.speed * 0.09 then
            input.jump = true
        end
    end
    if input.duck and run.grounded then input.jump = nil end
    if input.jump and not run.grounded then input.jump = nil end
    return input
end

return {
    ["runner: standing still crashes into the first ground monster"] = function(harness)
        local Runner = fresh(harness).Runner
        local run = Runner.New(POOL, 3)
        for _ = 1, 60 * 20 do Runner.Step(run, FRAME, {}) if run.finished then break end end
        harness.truthy(run.finished, "a run without input ends")
        harness.truthy(run.crashedInto ~= nil)
        harness.equal(run.crashedInto.fly, false, "before 150 m only ground monsters come")
    end,

    ["runner: a jump clears a ground monster; a duck passes under a flyer; standing hits the flyer"] = function(harness)
        local Runner = fresh(harness).Runner
        -- ground monster: jump when it is close
        local run = emptyRun(Runner)
        run.obstacles = { { id = 1, x = 150, y = 0, fly = false, pick = 1 } }
        for _ = 1, 120 do Runner.Step(run, FRAME, autopilot(Runner, run)) end
        harness.equal(run.finished, false, "the jump cleared it")
        -- flyer: duck
        run = emptyRun(Runner)
        run.obstacles = { { id = 1, x = 150, y = Runner.FLYER_Y, fly = true, pick = 2 } }
        for _ = 1, 120 do Runner.Step(run, FRAME, { duck = true }) end
        harness.equal(run.finished, false, "ducking passed under it")
        -- flyer: standing still hits it
        run = emptyRun(Runner)
        run.obstacles = { { id = 1, x = 150, y = Runner.FLYER_Y, fly = true, pick = 2 } }
        for _ = 1, 120 do Runner.Step(run, FRAME, {}) end
        harness.truthy(run.finished, "standing hits the flyer")
    end,

    ["runner: holding jump jumps higher; ducking in the air falls faster"] = function(harness)
        local Runner = fresh(harness).Runner
        local function peak(holdFrames, duckAfter)
            local run = emptyRun(Runner)
            local highest, frames = 0, 0
            for frame = 1, 90 do
                local input = { jump = frame <= holdFrames, duck = duckAfter and frame > duckAfter or nil }
                Runner.Step(run, FRAME, input)
                highest = math.max(highest, run.y)
                if run.grounded and frame > 2 and frames == 0 then frames = frame end
            end
            return highest, frames
        end
        local tapPeak, tapLanding = peak(1)
        local holdPeak = peak(30)
        harness.truthy(holdPeak > tapPeak * 1.3, ("held %.1f vs tap %.1f"):format(holdPeak, tapPeak))
        harness.truthy(tapPeak > Runner.BOX, "a tap clears a monster's height")
        local _, duckLanding = peak(1, 10)
        harness.truthy(duckLanding < tapLanding, "the fast fall lands sooner")
    end,

    ["runner: a careful player survives 1500 m on several seeds (spawns are always passable)"] = function(harness)
        local Runner = fresh(harness).Runner
        for seed = 1, 6 do
            local run = Runner.New(POOL, seed * 7919)
            while not run.finished and Runner.Meters(run) < 1500 do Runner.Step(run, FRAME, autopilot(Runner, run)) end
            harness.equal(run.finished, false, "seed " .. seed .. " crashed at " .. Runner.Meters(run) .. " m")
            harness.equal(run.speed, Runner.MAXIMUM_SPEED, "the speed reached its cap")
        end
    end,

    ["runner: the same seed replays the same run; a long frame is cut (no tunnelling)"] = function(harness)
        local Runner = fresh(harness).Runner
        local first, second = Runner.New(POOL, 42), Runner.New(POOL, 42)
        for _ = 1, 600 do
            Runner.Step(first, FRAME, autopilot(Runner, first)); Runner.Step(second, FRAME, autopilot(Runner, second))
        end
        harness.equal(first.distance, second.distance)
        harness.equal(#first.obstacles, #second.obstacles)
        local run = emptyRun(Runner)
        run.obstacles = { { id = 1, x = 90, y = 0, fly = false, pick = 1 } }
        Runner.Step(run, 5, {})   -- a 5 s hitch
        harness.truthy(run.time <= Runner.MAXIMUM_FRAME + 1e-9, "only MAXIMUM_FRAME was simulated")
        harness.truthy(run.finished, "the monster was hit, not skipped")
    end,

    ["runner: the pool uses the collection, flags flyers, falls back to built-in monsters"] = function(harness)
        local Runner = fresh(harness).Runner
        local fallback = Runner.BuildPool({})
        harness.equal(#fallback, #Runner.FALLBACK_POOL)
        local collection = {
            [10] = { n = "Bat", disp = 5, st = { family = "Fledermaus" } },
            [11] = { n = "Whelp", disp = 6, st = { type = 2 } },
            [12] = { n = "Wolf", disp = 7, st = { type = 1, family = "Wolf" } },
            [13] = { n = "Old", disp = 0 },
        }
        local pool = Runner.BuildPool(collection)
        harness.equal(#pool, 4)
        harness.equal(pool[1].npc, 10); harness.equal(pool[1].fly, true)
        harness.equal(pool[2].fly, true); harness.equal(pool[3].fly, false); harness.equal(pool[4].fly, false)
        harness.equal(#Runner.BuildPool({ [12] = collection[12] }), 1 + #Runner.FALLBACK_POOL, "too few: the built-ins join")
        -- no flagged flyer: any monster may fly
        local run = Runner.New({ { npc = 1, disp = 0, n = "A", fly = false } }, 5)
        run.distance = Runner.FLYERS_FROM_METERS * Runner.PIXELS_PER_METER
        local flyers = 0
        for _ = 1, 200 do
            run.spawnIn = 0; run.obstacles = {}
            Runner.Step(run, Runner.TICK, {})
            for _, obstacle in ipairs(run.obstacles) do if obstacle.fly then flyers = flyers + 1 end end
        end
        harness.truthy(flyers > 0, "a ground-only pool still sends flyers")
    end,

    ["runner: payout 1g per 100 m, 99 m pays nothing, 50g daily cap, the next day resets"] = function(harness)
        local addon = fresh(harness)
        local Runner = addon.Runner
        harness.equal(Runner.Payout(99, 0), 0)
        harness.equal(Runner.Payout(250, 0), 2)
        harness.equal(Runner.Payout(9000, 45), 5)
        harness.equal(Runner.Payout(9000, 50), 0)
        local function finish(meters, now)
            local run = Runner.New(POOL, 1)
            run.distance = meters * Runner.PIXELS_PER_METER
            return Runner.Finish(run, ME, now)
        end
        local before = addon.Wallet.Balance(ME)
        local result = finish(4000, NOW)
        harness.equal(result.gold, 40); harness.equal(result.best, true)
        harness.equal(addon.Wallet.Balance(ME) - before, 40 * 10000)
        result = finish(3000, NOW + 60)
        harness.equal(result.gold, 10); harness.equal(result.capped, true); harness.equal(result.paidToday, 50)
        result = finish(500, NOW + 120)
        harness.equal(result.gold, 0); harness.equal(result.best, false)
        result = finish(500, NOW + 86400)
        harness.equal(result.gold, 5, "a new server day")
        local state = Runner.State()
        harness.equal(state.b, 4000); harness.equal(state.n, 4); harness.equal(#state.recent, 4)
        harness.equal(state.recent[1].d, 500)
        -- the section went into my record
        local mine = addon.Games.Mine(ME)
        harness.truthy(mine and mine.runner, "my record carries the runner section")
        harness.equal(mine.runner.b, 4000)
    end,

    ["runner: read-only saved data books nothing"] = function(harness)
        local addon = fresh(harness)
        addon.Store.db.readonly = true
        local run = addon.Runner.New(POOL, 1)
        run.distance = 1000 * addon.Runner.PIXELS_PER_METER
        local result = addon.Runner.Finish(run, ME, NOW)
        harness.equal(result.gold, 0)
        harness.equal(addon.Store.db.runner, nil)
    end,

    ["runner: section sanitize drops garbage and keeps the rest of the record"] = function(harness)
        local addon = fresh(harness)
        local Runner, Games = addon.Runner, addon.Games
        local week = Games.PeriodKey(NOW)
        local good = { b = 900, n = 3, weeks = { [week] = 900 }, recent = { { d = 900, g = 9, t = NOW } } }
        harness.truthy(Runner.SanitizeSection(good, NOW + 86400))
        local bad = {
            { b = 1e300, n = 1, weeks = {}, recent = {} },
            { b = "far", n = 1, weeks = {}, recent = {} },
            { b = 1, n = 1, weeks = { nope = 3 }, recent = {} },
            { b = 1, n = 1, weeks = {}, recent = { { d = 1, g = 51, t = NOW } } },
            { b = 1, n = 1, weeks = {}, recent = { { d = 1, g = 1, t = NOW + 10 * 86400 } } },
            { b = 1, n = 1, weeks = {} },
            "runner",
        }
        local many = { b = 1, n = 1, weeks = {}, recent = {} }
        for index = 1, 1000 do many.recent[index] = { d = 1, g = 0, t = NOW } end
        bad[#bad + 1] = many
        for index, section in ipairs(bad) do
            harness.equal(Runner.SanitizeSection(section, NOW + 86400), nil, "bad section " .. index)
        end
        -- inside a record: the runner section is dropped alone
        local record = { name = "Peer-R", rev = NOW, total = { won = 0, lost = 0, wins = 0, losses = 0 }, weeks = {}, recent = {},
            runner = bad[1], extra = { x = 1 } }
        local clean = Games.Sanitize(record)
        harness.truthy(clean, "the record stays")
        harness.equal(clean.runner, nil); harness.equal(clean.extra, nil)
        record.runner = good
        harness.equal(Games.Sanitize(record).runner.b, 900)
    end,

    ["runner: saved data is repaired on load"] = function(harness)
        local addon = fresh(harness)
        local saved = { runner = { day = "x", paid = 999, b = -5, n = 2, weeks = "w", recent = { { d = 1 } } } }
        harness.equal(addon.Runner.SanitizePersisted(saved), true)
        harness.equal(saved.runner.paid, 0); harness.equal(saved.runner.b, 0); harness.equal(saved.runner.day, 0)
        local healthy = { runner = { day = 3, paid = 7, b = 120, n = 2, weeks = {}, recent = { { d = 120, g = 1, t = NOW } } } }
        harness.equal(addon.Runner.SanitizePersisted(healthy), false)
        harness.equal(healthy.runner.b, 120); harness.equal(healthy.runner.paid, 7)
        harness.equal(addon.Runner.SanitizePersisted({}), false)
    end,

    ["runner: leaderboard by best distance per scope; feed newest first"] = function(harness)
        local addon = fresh(harness)
        local Runner, Games = addon.Runner, addon.Games
        local week = Games.PeriodKey(NOW)
        local records = {
            ["A-R"] = { runner = { b = 500, n = 4, weeks = { [week] = 100 }, recent = { { d = 100, g = 1, t = NOW - 5 } } } },
            ["B-R"] = { runner = { b = 300, n = 1, weeks = { [week] = 300 }, recent = { { d = 300, g = 3, t = NOW } } } },
            ["C-R"] = { total = {} },
        }
        local all = Runner.BoardRows(records, "all", week, "B-R")
        harness.equal(#all, 2); harness.equal(all[1].nameRaw, "A-R"); harness.equal(all[2].mine, true)
        local thisWeek = Runner.BoardRows(records, "week", week, nil)
        harness.equal(thisWeek[1].nameRaw, "B-R"); harness.equal(thisWeek[1].meters, 300)
        local feed = Runner.FeedRows(records, nil)
        harness.equal(#feed, 2); harness.equal(feed[1].nameRaw, "B-R")
    end,
}
