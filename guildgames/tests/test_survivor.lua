-- Survivor (third game): targets and payouts, pending stake (a /reload mid-run still loses), simulation rules,
-- item picks, record validation of the survivor section and its own leaderboard.
local NOW = 1794873600   -- 2026-11-17 00:00 UTC

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = "Me-R"
    return addon
end

-- a seeded random function (same runs every time)
local function seeded(seed)
    return function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
end

-- plays a run to its end: `pick` chooses the card index (default the first card)
local function playOut(addon, run, pick)
    local guard = 0
    while not run.finished do
        guard = guard + 1
        assert(guard < 100000, "the run never ended")
        addon.Survivor.Advance(run, 0.1)
        while run.choices do assert(addon.Survivor.Choose(run, pick and pick(run) or 1)) end
    end
    return run
end

return {
    ["survivor: targets pay more the longer they are; the last factor is the validation bound"] = function(harness)
        local addon = fresh(harness)
        local Survivor = addon.Survivor
        harness.equal(Survivor.ENDLESS_MAXIMUM_FACTOR, addon.Games.SURVIVOR_MAXIMUM_FACTOR)
        harness.truthy(Survivor.TARGETS[#Survivor.TARGETS].factor <= addon.Games.SURVIVOR_MAXIMUM_FACTOR)
        harness.truthy(Survivor.Target(Survivor.ENDLESS_INDEX) == Survivor.ENDLESS)
        for index = 2, #Survivor.TARGETS do
            harness.truthy(Survivor.TARGETS[index].seconds > Survivor.TARGETS[index - 1].seconds)
            harness.truthy(Survivor.TARGETS[index].factor > Survivor.TARGETS[index - 1].factor)
        end
        harness.truthy(Survivor.TARGETS[1].factor >= 2, "a win must net at least the stake (record validation)")
        harness.equal(addon.Games.KINDS.survivor.maximumWinFactor, addon.Games.SURVIVOR_MAXIMUM_FACTOR - 1)
        harness.equal(addon.Games.ORDER[3], "survivor")
        for _, item in ipairs(Survivor.ITEMS) do harness.truthy(Survivor.ITEM_BY_KEY[item.key] == item) end
    end,

    ["survivor: a run is booked as pending at the start and settled at the end (won pays factor x stake)"] = function(harness)
        local addon = fresh(harness)
        local run = assert(addon.Survivor.Begin("Me-R", 300, 2, NOW, seeded(3)))
        local pending = addon.db.ui.survivorPending
        harness.equal(pending.c, 300); harness.equal(pending.name, "Me-R")
        harness.equal(addon.Games.Get("Me-R"), nil, "nothing recorded yet")
        run.finished = "won"
        local net = addon.Survivor.Settle(run, NOW + 100)
        harness.equal(net, 300 * (addon.Survivor.TARGETS[2].factor - 1))
        harness.equal(addon.db.ui.survivorPending, nil)
        local mine = addon.Games.Get("Me-R")
        harness.equal(mine.survivor.total.won, net); harness.equal(mine.survivor.total.wins, 1)
        harness.equal(mine.survivor.recent[1].n, net)
        harness.equal(mine.total.wins + mine.total.losses, 0, "the coin section has no play")
        harness.truthy(addon.Games.Sanitize(mine), "my own record passes peer validation")
        -- a lost (or given up) run costs the stake
        local second = assert(addon.Survivor.Begin("Me-R", 50, 4, NOW + 200, seeded(4)))
        second.finished = nil   -- give up: the UI settles an unfinished run as lost
        harness.equal(addon.Survivor.Settle(second, NOW + 210), -50)
        harness.equal(addon.Games.Get("Me-R").survivor.total.lost, 50)
    end,

    ["survivor: a run left open by a reload is lost at the next login; garbage pending data is dropped"] = function(harness)
        local addon = fresh(harness)
        assert(addon.Survivor.Begin("Me-R", 700, 1, NOW, seeded(5)))
        -- /reload: the run is gone, the pending mark stays in the saved data
        harness.equal(addon.Survivor.ResolvePending(NOW + 60), true)
        harness.equal(addon.Games.Get("Me-R").survivor.total.lost, 700)
        harness.equal(addon.db.ui.survivorPending, nil)
        harness.equal(addon.Survivor.ResolvePending(NOW + 61), false, "only once")
        for _, garbage in ipairs({ "x", { c = -5, name = "Me-R" }, { c = 10, name = "bad name|cff" }, { c = 1.5, name = "Me-R" } }) do
            addon.db.ui.survivorPending = garbage
            harness.equal(addon.Survivor.ResolvePending(NOW + 70), false)
            harness.equal(addon.db.ui.survivorPending, nil)
        end
        harness.equal(addon.Games.Get("Me-R").survivor.total.losses, 1)
        -- starting a new run settles a stale pending one first
        addon.db.ui.survivorPending = { name = "Me-R", c = 20, t = NOW }
        assert(addon.Survivor.Begin("Me-R", 30, 1, NOW + 80, seeded(6)))
        harness.equal(addon.Games.Get("Me-R").survivor.total.losses, 2)
        harness.equal(addon.db.ui.survivorPending.c, 30)
    end,

    ["survivor: refused stakes, targets and a readonly db start nothing"] = function(harness)
        local addon = fresh(harness)
        for _, stake in ipairs({ 0, -1, 1.5, addon.Games.MAXIMUM_STAKE + 1, "5" }) do
            harness.equal(select(2, addon.Survivor.Begin("Me-R", stake, 1, NOW, seeded(1))), "stake")
        end
        harness.equal(select(2, addon.Survivor.Begin("Me-R", 10, 0, NOW, seeded(1))), "target")
        harness.equal(select(2, addon.Survivor.Begin("Me-R", 10, addon.Survivor.ENDLESS_INDEX + 1, NOW, seeded(1))), "target")
        harness.equal(select(2, addon.Survivor.Begin("bad|name", 10, 1, NOW, seeded(1))), "name")
        addon.Store.db.readonly = true
        harness.equal(select(2, addon.Survivor.Begin("Me-R", 10, 1, NOW, seeded(1))), "readonly")
        harness.equal(addon.db.ui.survivorPending, nil)
    end,

    ["survivor: the simulation pauses for item picks, ends at the target or at 0 health, and never runs past it"] = function(harness)
        local addon = fresh(harness)
        local Survivor = addon.Survivor
        local results = { won = 0, lost = 0 }
        for seed = 1, 12 do
            local run = Survivor.NewRun("Me-R", 100, Survivor.TARGETS[1], seeded(seed))
            local sawChoice = false
            while not run.finished do
                Survivor.Advance(run, 0.1)
                if run.choices then
                    sawChoice = true
                    local time, enemies = run.time, #run.enemies
                    Survivor.Advance(run, 1)
                    harness.equal(run.time, time, "paused while a choice waits"); harness.equal(#run.enemies, enemies)
                    harness.truthy(#run.choices >= 1 and #run.choices <= 3)
                    local seen = {}
                    for _, choice in ipairs(run.choices) do
                        harness.equal(seen[choice.key], nil, "offers are distinct"); seen[choice.key] = true
                        harness.truthy(choice.level <= Survivor.ITEM_BY_KEY[choice.key].maximum)
                    end
                    while run.choices do assert(Survivor.Choose(run, #run.choices)) end
                end
            end
            harness.truthy(sawChoice, "kills give levels")
            harness.truthy(run.time <= run.target.seconds + 1e-9)
            if run.finished == "won" then harness.equal(run.time, run.target.seconds) else harness.equal(run.hp, 0) end
            harness.truthy(run.kills > 0)
            results[run.finished] = results[run.finished] + 1
            local time = run.time
            Survivor.Advance(run, 5)
            harness.equal(run.time, time, "nothing moves after the end")
        end
        harness.truthy(results.won + results.lost == 12)
    end,

    ["survivor: the same seed and picks replay the same run"] = function(harness)
        local addon = fresh(harness)
        local first = playOut(addon, addon.Survivor.NewRun("Me-R", 1, addon.Survivor.TARGETS[3], seeded(42)))
        local second = playOut(addon, addon.Survivor.NewRun("Me-R", 1, addon.Survivor.TARGETS[3], seeded(42)))
        harness.equal(first.finished, second.finished); harness.equal(first.time, second.time)
        harness.equal(first.kills, second.kills); harness.equal(first.level, second.level)
    end,

    ["survivor: items level up to their maximum; vitality raises and heals health; a maxed tower is offered a heal"] = function(harness)
        local addon = fresh(harness)
        local Survivor = addon.Survivor
        local run = Survivor.NewRun("Me-R", 1, Survivor.TARGETS[1], seeded(9))
        run.hp = 40
        run.choices = { { key = "vitality", level = 1 } }
        assert(Survivor.Choose(run, 1))
        harness.equal(run.maxHp, Survivor.BASE_HP + 25); harness.equal(run.hp, 65); harness.equal(run.choices, nil)
        harness.equal(Survivor.Choose(run, 1), false, "no choice open")
        local boltBefore = Survivor.WeaponStats(run, "bolt")
        harness.equal(Survivor.WeaponStats(run, "nova"), nil, "the nova is not owned yet")
        for _, item in ipairs(Survivor.ITEMS) do run.items[item.key] = item.maximum end
        local boltAfter = Survivor.WeaponStats(run, "bolt")
        harness.truthy(boltAfter.damage > boltBefore.damage and boltAfter.cooldown < boltBefore.cooldown and boltAfter.shots > boltBefore.shots)
        local offer = Survivor.Offer(run)
        harness.equal(#offer, 1); harness.equal(offer[1].key, "vitality")
        run.choices = offer
        assert(Survivor.Choose(run, 1))
        harness.equal(run.items.vitality, Survivor.ITEM_BY_KEY.vitality.maximum, "never past the maximum")
    end,

    ["survivor: Sanitize bounds the survivor section by the top factor; the board is its own"] = function(harness)
        local addon = fresh(harness)
        local run = assert(addon.Survivor.Begin("Me-R", 100, 4, NOW, seeded(2)))
        run.finished = "won"
        addon.Survivor.Settle(run, NOW + 1)
        addon.Games.Flip("Coin-R", 10, "H", NOW, function() return 0.1 end)
        local good = addon.Utility.DeepCopy(addon.Games.Get("Me-R"))
        harness.truthy(addon.Games.Sanitize(good))
        local tooMuch = addon.Utility.DeepCopy(good)
        tooMuch.survivor.recent[1].n = 100 * addon.Games.SURVIVOR_MAXIMUM_FACTOR   -- the top net is (factor - 1) x stake
        harness.equal(addon.Games.Sanitize(tooMuch), nil, "net over (factor - 1) x stake")
        local records = addon.Games.AllRecords()
        local board = addon.Model.BuildLeaderboardRows(records, "all", "2026-W47", "Me-R", "survivor")
        harness.equal(#board, 1); harness.equal(board[1].nameRaw, "Me-R"); harness.equal(board[1].net, 900)
        harness.equal(#addon.Model.BuildFlipFeedRows(records, nil, 15, "survivor"), 1)
        harness.equal(addon.Model.BuildLeaderboardRows(records, "all", "2026-W47", nil, "coin")[1].nameRaw, "Coin-R")
        addon.Games.Simulate(5, NOW, seeded(8))
        for _, record in pairs(addon.Games.simulated) do
            harness.truthy(addon.Games.Sanitize(record), "simulated records stay inside the bounds")
        end
    end,

    ["survivor endless: every minute doubles the payout, capped; before 1:00 the stake is lost"] = function(harness)
        local Survivor = fresh(harness).Survivor
        local expected = { [0] = 0, [59.9] = 0, [60] = 2, [119] = 2, [120] = 4, [180] = 8, [300] = 32, [360] = 64, [3600] = 64 }
        for time, factor in pairs(expected) do harness.equal(Survivor.EndlessFactor(time), factor, "at " .. time) end
        local run = Survivor.NewRun("Me-R", 100, Survivor.ENDLESS, seeded(1))
        run.time = 30; harness.equal(Survivor.Net(run), -100)
        run.time = 125; harness.equal(Survivor.Net(run), 300, "x4 at 2:05")
        run.finished = "lost"; harness.equal(Survivor.Net(run), 300, "the tower fell, the minute reached still pays")
    end,

    ["survivor endless: never ends by time, raises the pending factor at each minute, a reload pays what was reached"] = function(harness)
        local addon = fresh(harness)
        local Survivor = addon.Survivor
        local run = assert(Survivor.Begin("Me-R", 100, Survivor.ENDLESS_INDEX, NOW, seeded(11)))
        local milestones = {}
        while run.time < 130 do
            assert(not run.finished, "the tower is kept alive")
            run.hp, run.maxHp = 1e9, 1e9   -- an unkillable tower: only the clock matters
            Survivor.Advance(run, 0.2)
            while run.choices do Survivor.Choose(run, 1) end
            for _, event in ipairs(Survivor.TakeEvents(run)) do
                if event.kind == "milestone" then milestones[#milestones + 1] = event.factor end
            end
        end
        harness.equal(run.finished, nil, "endless does not stop at a time")
        harness.equal(#milestones, 2); harness.equal(milestones[1], 2); harness.equal(milestones[2], 4)
        harness.equal(addon.db.ui.survivorPending.factor, 4)
        -- /reload now: x4 is paid
        harness.equal(Survivor.ResolvePending(NOW + 200), true)
        harness.equal(addon.Games.Get("Me-R").survivor.recent[1].n, 300)
        harness.truthy(addon.Games.Sanitize(addon.Games.Get("Me-R")))
        addon.db.ui.survivorPending = { name = "Me-R", c = 100, t = NOW, factor = 65 }
        Survivor.ResolvePending(NOW + 201)
        harness.equal(addon.Games.Get("Me-R").survivor.recent[1].n, -100, "a factor over the cap is not trusted")
        -- cash out: settle while the run is open
        local second = assert(Survivor.Begin("Me-R", 10, Survivor.ENDLESS_INDEX, NOW + 300, seeded(12)))
        second.time = 61
        harness.equal(Survivor.Settle(second, NOW + 400), 10)
    end,

    ["survivor weapons: every ranged weapon fires and hurts; chains zap, explosions and strikes blast, the axe comes back"] = function(harness)
        local Survivor = fresh(harness).Survivor
        harness.equal(#Survivor.WEAPON_KEYS, 13)
        for key in pairs(Survivor.RANGED) do harness.truthy(Survivor.ITEM_BY_KEY[key], key .. " is an item") end
        for _, key in ipairs(Survivor.WEAPON_KEYS) do
            local run = Survivor.NewRun("Me-R", 1, Survivor.ENDLESS, seeded(3))
            run.items = { [key] = 3 }
            run.cooldowns = {}
            -- rings of tough monsters around the tower, outside the melee reach
            -- (two rings, so a piercing shot has a monster behind the first one)
            for index = 1, 16 do
                local angle, distance = index * math.pi / 4, index <= 8 and 60 or 95
                run.nextID = run.nextID + 1
                run.enemies[index] = { id = run.nextID, kind = "bear", x = math.cos(angle) * distance, y = math.sin(angle) * distance,
                    hp = 1e6, maxHp = 1e6, radius = 10, speed = 0, damage = 0, slow = 0, flash = 0 }
            end
            run.spawnTimer = 1e9
            local kinds, caught = {}, false
            for _ = 1, 150 do
                Survivor.Advance(run, Survivor.STEP)
                for _, event in ipairs(Survivor.TakeEvents(run)) do kinds[event.kind] = (kinds[event.kind] or 0) + 1 end
                if key == "axe" and kinds.shot and #run.projectiles == 0 then caught = true end
            end
            local damaged = 0
            for _, enemy in ipairs(run.enemies) do if enemy.hp < 1e6 then damaged = damaged + 1 end end
            harness.truthy(damaged > 0, key .. " hurt nothing")
            if key == "lightning" then harness.truthy(kinds.zap, "chain lightning zaps") end
            if key == "fireball" or key == "smite" or key == "starfall" then harness.truthy(kinds.blast, key .. " blasts") end
            if key == "icelance" or key == "nova" then
                local slowed = false
                for _, enemy in ipairs(run.enemies) do if enemy.slow > 0 then slowed = true end end
                harness.truthy(slowed, key .. " slows")
            end
            if key == "shadow" or key == "axe" or key == "lightning" or key == "starfall" then
                harness.truthy(damaged >= 2, key .. " hits several monsters")
            end
            if key == "axe" then harness.truthy(caught, "the axe returns to the tower") end
        end
    end,

    ["survivor weapons: a tower holds at most six weapons; then only owned weapons and passives are offered"] = function(harness)
        local Survivor = fresh(harness).Survivor
        local run = Survivor.NewRun("Me-R", 1, Survivor.TARGETS[1], seeded(5))
        run.items = { bolt = 1, cleave = 1, nova = 1, arcane = 1, shadow = 1, arrows = 1 }
        for _ = 1, 200 do
            for _, choice in ipairs(Survivor.Offer(run)) do
                local item = Survivor.ITEM_BY_KEY[choice.key]
                harness.truthy(item.kind == "passive" or run.items[choice.key], "offered a 7th weapon: " .. choice.key)
            end
        end
        run.items.arrows = nil
        local seenNew = false
        for _ = 1, 200 do
            for _, choice in ipairs(Survivor.Offer(run)) do
                if Survivor.ITEM_BY_KEY[choice.key].kind == "weapon" and not run.items[choice.key] then seenNew = true end
            end
        end
        harness.truthy(seenNew, "with five weapons a new one is offered again")
    end,

    ["survivor upgrades: volley and penetration add projectiles and pierce, reach widens areas"] = function(harness)
        local Survivor = fresh(harness).Survivor
        local run = Survivor.NewRun("Me-R", 1, Survivor.TARGETS[1], seeded(1))
        run.items = { bolt = 1, fireball = 1, cleave = 1, lightning = 1 }
        local bolt, fireball, cleave, lightning = Survivor.WeaponStats(run, "bolt"), Survivor.WeaponStats(run, "fireball"),
            Survivor.WeaponStats(run, "cleave"), Survivor.WeaponStats(run, "lightning")
        run.items.volley, run.items.pierce, run.items.reach = 2, 3, 4
        harness.equal(Survivor.WeaponStats(run, "bolt").count, bolt.count + 2)
        harness.equal(Survivor.WeaponStats(run, "bolt").pierce, bolt.pierce + 3)
        harness.equal(Survivor.WeaponStats(run, "lightning").count, lightning.count, "volley is for projectile weapons")
        harness.truthy(math.abs(Survivor.WeaponStats(run, "fireball").splash - fireball.splash * 1.6) < 1e-9)
        harness.truthy(math.abs(Survivor.WeaponStats(run, "cleave").radius - cleave.radius * 1.6) < 1e-9)
    end,

    ["survivor upgrades: thorns and deflect hurt attackers, deflect and the barrier spare health, leech heals on kills"] = function(harness)
        local Survivor = fresh(harness).Survivor
        -- one monster pressed against the tower; no weapons, no spawns
        local function standoff(items, seconds)
            local run = Survivor.NewRun("Me-R", 1, Survivor.ENDLESS, seeded(2))
            run.items, run.spawnTimer = items, 1e9
            run.enemies[1] = { id = 1, kind = "bear", x = 24, y = 0, hp = 1e6, maxHp = 1e6, radius = 10, speed = 0, damage = 10,
                slow = 0, flash = 0 }
            if items.barrier then run.shield = Survivor.DefenseStats(run).shield end
            for _ = 1, math.floor(seconds / Survivor.STEP + 0.5) do Survivor.Advance(run, Survivor.STEP) end
            return run, 1e6 - run.enemies[1].hp
        end
        local plain, plainDamage = standoff({}, 2)
        harness.truthy(math.abs((Survivor.BASE_HP - plain.hp) - 20) < 0.5, "10 per second for 2 s")
        harness.equal(plainDamage, 0)
        local _, thornsDamage = standoff({ thorns = 2 }, 2)
        harness.truthy(math.abs(thornsDamage - 20) < 0.5, "2 levels of thorns: 10 per second")
        local deflected, reflected = standoff({ deflect = 3 }, 2)
        harness.truthy(math.abs((Survivor.BASE_HP - deflected.hp) - 14) < 0.5, "30% turned away")
        harness.truthy(math.abs(reflected - 18) < 0.5, "and sent back three times over")
        local shielded = standoff({ barrier = 1 }, 1)
        harness.truthy(math.abs((Survivor.BASE_HP - shielded.hp) - 0) < 0.5 and shielded.shield < 15, "the barrier takes the first hits")
        shielded.enemies = {}
        for _ = 1, math.floor((Survivor.BARRIER_PAUSE + 1) / Survivor.STEP) do Survivor.Advance(shielded, Survivor.STEP) end
        harness.truthy(math.abs(shielded.shield - 15) < 1e-6, "refilled after the pause")
        local leeching = Survivor.NewRun("Me-R", 1, Survivor.ENDLESS, seeded(3))
        leeching.items, leeching.hp = { leech = 5 }, 50
        leeching.choices = { { key = "leech", level = 5 } }
        harness.equal(Survivor.DefenseStats(leeching).leech, 3)
    end,
}

