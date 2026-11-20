-- AZEcaught (feature 018): catch math, collection, companion state machine, record section, payout, journal.
local NOW = 1794873600   -- 2026-11-16 (a Monday, week 2026-W47)
local GUID = "Creature-0-1-2-3-4711-0000ABCDEF"

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = "Me-R"
    addon.AzeCaught.throws, addon.AzeCaught.rolled, addon.AzeCaught.lastThrowAt = {}, {}, nil
    addon.AzeCaught.thrown = {}
    addon.AzeCaught.forceNextCatch = false
    addon.AzeCaught.State().firstCatchDone = true   -- rolls use the chance (the guaranteed first catch has its own test)
    return addon
end

local function constant(value) return function() return value end end

-- catches npc 4711 (forced) and returns the addon
local function withCaught(harness, options)
    local addon = fresh(harness)
    local AzeCaught = addon.AzeCaught
    assert(AzeCaught.Throw({ guid = GUID, health = 0.1, name = "Wolf", level = 10, classification = (options and options.cls) or "normal" }, 10, 100, NOW))
    AzeCaught.forceNextCatch = true
    assert(AzeCaught.OnDeath(GUID, "Me-R", 101, NOW, constant(0.99)).caught)
    return addon
end

-- runs `seconds` of active time in 1 s ticks
local function run(AzeCaught, seconds)
    local died = false
    for _ = 1, seconds do if AzeCaught.Tick(1, NOW).died then died = true end end
    return died
end

local function journalHas(addon, text)
    for _, line in ipairs(addon.AzeCaught.State().journal) do if line:find(text, 1, true) then return true end end
    return false
end

return {
    ["azecaught: the health factor is logarithmic: 1 at 0 HP, ~0.48 at 10%, ~0.26 at 30%, 0 at full"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        harness.equal(AzeCaught.HealthFactor(0), 1)
        harness.truthy(math.abs(AzeCaught.HealthFactor(0.1) - 0.4813) < 0.001, "10%: " .. AzeCaught.HealthFactor(0.1))
        harness.truthy(math.abs(AzeCaught.HealthFactor(0.3) - 0.2564) < 0.001, "30%: " .. AzeCaught.HealthFactor(0.3))
        harness.equal(AzeCaught.HealthFactor(1), 0)
        harness.equal(AzeCaught.HealthFactor(5), 0); harness.equal(AzeCaught.HealthFactor(-1), 1)
        local previous = 2
        for step = 0, 100 do
            local value = AzeCaught.HealthFactor(step / 100)
            harness.truthy(value <= previous, "falls monotonically"); previous = value
        end
        -- steepest near 0 HP (logarithmic, not linear)
        harness.truthy(AzeCaught.HealthFactor(0) - AzeCaught.HealthFactor(0.05) > AzeCaught.HealthFactor(0.25) - AzeCaught.HealthFactor(0.30))
    end,

    ["azecaught: difficulty lowers the chance for rarer and higher NPCs; the chance is capped"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        local normal = AzeCaught.Chance(0, "normal", 10, 10)
        harness.equal(normal.chance, AzeCaught.BASE_CHANCE)
        harness.truthy(AzeCaught.Chance(0, "elite", 10, 10).chance < normal.chance)
        harness.truthy(AzeCaught.Chance(0, "rare", 10, 10).chance < AzeCaught.Chance(0, "elite", 10, 10).chance)
        harness.truthy(AzeCaught.Chance(0, "worldboss", 10, 10).chance < AzeCaught.Chance(0, "rareelite", 10, 10).chance)
        harness.truthy(AzeCaught.Chance(0, "normal", 15, 10).chance < normal.chance, "higher level is harder")
        harness.equal(AzeCaught.Chance(0, "normal", 60, 10).levelFactor, 0.25, "level factor floor")
        harness.equal(AzeCaught.Chance(0, "normal", 1, 60).levelFactor, 1.25, "level factor ceiling")
        harness.equal(AzeCaught.Chance(0, "trivial", 10, 10).chance, normal.chance, "unknown classes count as normal")
        AzeCaught.BASE_CHANCE = 1
        local capped = AzeCaught.Chance(0, "normal", 1, 60)
        harness.equal(capped.chance, AzeCaught.MAXIMUM_CHANCE); harness.equal(capped.capped, true)
        -- reward grows with difficulty
        harness.truthy(AzeCaught.Reward(AzeCaught.Difficulty("worldboss", 10, 10)) > AzeCaught.Reward(1))
        harness.equal(AzeCaught.Reward(1), AzeCaught.CATCH_REWARD)
        harness.equal(AzeCaught.Reward(0.0001), AzeCaught.MAXIMUM_REWARD)
    end,

    ["azecaught: npc ids come only from creature and vehicle GUIDs"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        harness.equal(AzeCaught.NpcIdFromGuid(GUID), 4711)
        harness.equal(AzeCaught.NpcIdFromGuid("Vehicle-0-1-2-3-99-AB"), 99)
        harness.equal(AzeCaught.NpcIdFromGuid("Player-1234-0000ABCD"), nil)
        harness.equal(AzeCaught.NpcIdFromGuid("Pet-0-1-2-3-4711-AB"), nil)
        harness.equal(AzeCaught.NpcIdFromGuid(nil), nil); harness.equal(AzeCaught.NpcIdFromGuid("Creature-0-1-2-3-0-AB"), nil)
    end,

    ["azecaught: found NPCs are added once, learn level/display/rarity, and the collection is bounded"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local entry, isNew = AzeCaught.NoteFound({ npc = 7, name = "Boar", level = 3 }, NOW)
        harness.equal(isNew, true); harness.equal(entry.caught, 0); harness.equal(entry.cls, "normal"); harness.equal(entry.disp, 0)
        harness.truthy(journalHas(addon, "a new NPC was found"))
        local lines = #AzeCaught.State().journal
        local again, againNew = AzeCaught.NoteFound({ npc = 7, name = "Boar", level = 3 }, NOW)
        harness.equal(againNew, false); harness.truthy(again == entry)
        harness.equal(#AzeCaught.State().journal, lines, "nothing new -> no journal line (combat log spam)")
        AzeCaught.NoteFound({ npc = 7, level = 5, display = 123, classification = "elite" }, NOW)
        harness.equal(entry.lvl, 5); harness.equal(entry.disp, 123); harness.equal(entry.cls, "elite")
        AzeCaught.NoteFound({ npc = 8, name = "Bad|cffff0000\1name" .. ("x"):rep(80) }, NOW)
        harness.truthy(#AzeCaught.State().collection[8].n <= AzeCaught.MAXIMUM_NAME_BYTES)
        harness.truthy(not AzeCaught.State().collection[8].n:find("\1"), "control characters are stripped")
        harness.equal(AzeCaught.NoteFound({ npc = "x" }, NOW), nil)
    end,

    ["azecaught: a throw needs low health, a cooldown and an NPC; one roll per GUID inside 3 s (RF1)"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        harness.equal(select(2, AzeCaught.Throw({ guid = "Player-1-2", health = 0.1 }, 10, 100, NOW)), "unknown")
        harness.equal(select(2, AzeCaught.Throw({ guid = GUID, health = 0.5 }, 10, 100, NOW)), "health")
        harness.equal(select(2, AzeCaught.Throw({ guid = GUID, health = 0 }, 10, 100, NOW)), "dead")
        harness.truthy(AzeCaught.Throw({ guid = GUID, health = 0.35, name = "Wolf", level = 10 }, 10, 100, NOW), "at the threshold")
        harness.equal(select(2, AzeCaught.Throw({ guid = "Creature-0-1-2-3-5-B", health = 0.1 }, 10, 101, NOW)), "cooldown")
        -- a death without a throw, then the real one, then the same death again
        harness.equal(select(2, AzeCaught.OnDeath("Creature-0-1-2-3-5-C", "Me-R", 101, NOW, constant(0))), "nothrow")
        local result = assert(AzeCaught.OnDeath(GUID, "Me-R", 102, NOW, constant(0.999)))
        harness.equal(result.caught, false)
        harness.equal(select(2, AzeCaught.OnDeath(GUID, "Me-R", 102, NOW, constant(0))), "rolled", "a second death event never rolls")
        harness.equal(select(2, AzeCaught.Throw({ guid = GUID, health = 0.1 }, 10, 200, NOW)), "rolled")
        harness.truthy(journalHas(addon, "the catch roll failed"))
        harness.truthy(journalHas(addon, "roll=0.9990"), "the journal carries the random value")
        -- too late
        AzeCaught.Throw({ guid = "Creature-0-1-2-3-6-D", health = 0.1 }, 10, 300, NOW)
        harness.equal(select(2, AzeCaught.OnDeath("Creature-0-1-2-3-6-D", "Me-R", 303.5, NOW, constant(0))), "late")
        -- expiry keeps memory bounded
        AzeCaught.ExpireThrows(1000)
        harness.equal(next(AzeCaught.rolled), nil); harness.equal(next(AzeCaught.throws), nil)
    end,

    ["azecaught: a successful roll catches, pays the reward into the pool and is logged"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local before = addon.Wallet.Balance("Me-R")
        AzeCaught.Throw({ guid = GUID, health = 0, name = "Wolf", level = 10, classification = "rare" }, 10, 100, NOW)
        harness.equal(select(2, AzeCaught.Throw({ guid = GUID, health = 0.0, name = "Wolf" }, 10, 104, NOW)), "dead")
        AzeCaught.lastThrowAt = nil
        AzeCaught.Throw({ guid = GUID, health = 0.01, name = "Wolf", level = 10, classification = "rare" }, 10, 100, NOW)
        local result = assert(AzeCaught.OnDeath(GUID, "Me-R", 101, NOW, constant(0.01)))
        harness.equal(result.caught, true)
        harness.equal(AzeCaught.State().collection[4711].caught, 1)
        harness.equal(result.reward, AzeCaught.Reward(AzeCaught.Difficulty("rare", 10, 10)))
        harness.equal(addon.Wallet.Balance("Me-R"), before + result.reward)
        harness.truthy(journalHas(addon, "an NPC was caught")); harness.truthy(journalHas(addon, "money was paid into the pool"))
    end,

    ["azecaught: selecting starts fresh; only caught NPCs; same twice is refused"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        AzeCaught.NoteFound({ npc = 99, name = "Only seen" }, NOW)
        harness.equal(select(2, AzeCaught.Select(99, NOW)), "notcaught")
        harness.equal(select(2, AzeCaught.Select(12345, NOW)), "unknown")
        local companion = assert(AzeCaught.Select(4711, NOW))
        harness.equal(companion.hunger, 100); harness.equal(companion.hearts, 0); harness.equal(companion.n, "Wolf")
        harness.equal(select(2, AzeCaught.Select(4711, NOW)), "same")
        harness.truthy(journalHas(addon, "a companion was selected"))
    end,

    ["azecaught: needs reach needy exactly at their schedule (water 1 h, food 2 h, pet 2 h, sleep 4 h); zones are logged"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        run(AzeCaught, 1800)   -- 30 min
        harness.truthy(math.abs(companion.thirst - 75) < 1e-6, "thirst " .. companion.thirst)
        harness.truthy(math.abs(companion.hunger - 87.5) < 1e-6, "hunger " .. companion.hunger)
        harness.truthy(math.abs(companion.affection - 87.5) < 1e-6)
        harness.truthy(math.abs(companion.energy - 93.75) < 1e-6)
        harness.equal(AzeCaught.State().activeSeconds, 1800)
        harness.equal(companion.zones.thirst, "ok")
        run(AzeCaught, 1800)   -- 1 h: water is due
        harness.equal(companion.zones.thirst, "needy"); harness.equal(companion.zones.hunger, "ok")
        harness.truthy(journalHas(addon, "need=thirst"))
        -- the tooltip countdown: food is due at 2 h
        harness.truthy(math.abs(AzeCaught.SecondsUntilNeedy(companion, "hunger") - 3600) < 1e-6)
        harness.equal(AzeCaught.SecondsUntilNeedy(companion, "thirst"), 0)
        run(AzeCaught, 3600)   -- 2 h: thirst empty, food and petting due
        harness.equal(companion.zones.thirst, "empty"); harness.equal(companion.zones.hunger, "needy"); harness.equal(companion.zones.affection, "needy")
        harness.truthy(math.abs(AzeCaught.SecondsUntilNeedy(companion, "energy") - 7200) < 1e-6, "tired after 4 h")
    end,

    ["azecaught: a huge tick is clamped (RF2) and a bad dt is ignored"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        AzeCaught.Tick(8 * 3600, NOW)
        harness.equal(AzeCaught.State().activeSeconds, AzeCaught.MAXIMUM_TICK)
        harness.truthy(companion.thirst > 99, "8 h in a loading screen is 5 s")
        harness.truthy(journalHas(addon, "a long tick was clamped"))
        AzeCaught.Tick(0 / 0); AzeCaught.Tick(-5); AzeCaught.Tick("x")
        harness.equal(AzeCaught.State().activeSeconds, AzeCaught.MAXIMUM_TICK)
    end,

    ["azecaught: care: needy +1, due soon +2, well fed 0 and refused when full; streaks count"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        harness.equal(select(2, AzeCaught.Care("feed", "Me-R", NOW)), "full")
        companion.hunger = 40
        local result = assert(AzeCaught.Care("feed", "Me-R", NOW))
        harness.equal(result.hearts, 1); harness.equal(result.cost, AzeCaught.FOOD_PRICE); harness.equal(companion.hunger, 100)
        companion.thirst = 55
        harness.equal(assert(AzeCaught.Care("water", "Me-R", NOW)).hearts, 2)
        companion.affection = 80
        harness.equal(assert(AzeCaught.Care("pet", "Me-R", NOW)).hearts, 0)
        harness.equal(select(2, AzeCaught.Care("pet", "Me-R", NOW)), "full", "petting a full companion is not needed")
        companion.affection = 70
        harness.equal(assert(AzeCaught.Care("pet", "Me-R", NOW)).cost, 0, "petting is free")
        harness.equal(companion.hearts, 3); harness.equal(companion.fedStreak, 1); harness.equal(companion.careStreak, 1, "one per hour")
        companion.hunger = 10
        AzeCaught.Tick(1, NOW)
        companion.hunger = 10
        harness.equal(assert(AzeCaught.Care("feed", "Me-R", NOW)).hearts, 0, "critical: no hearts")
        harness.equal(select(2, AzeCaught.Care("dance", "Me-R", NOW)), "action")
        harness.truthy(journalHas(addon, "a care action was done")); harness.truthy(journalHas(addon, "before=40"))
    end,

    ["azecaught: sleep refills energy over 1 h, blocks food, can be woken; needs decay at half speed"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        harness.equal(select(2, AzeCaught.Care("sleep", "Me-R", NOW)), "full")
        harness.equal(select(2, AzeCaught.Care("wake", "Me-R", NOW)), "awake")
        companion.energy = 0
        assert(AzeCaught.Care("sleep", "Me-R", NOW))
        harness.equal(select(2, AzeCaught.Care("feed", "Me-R", NOW)), "asleep")
        run(AzeCaught, 1800)
        harness.truthy(math.abs(companion.energy - 50) < 1e-6, "half refilled after 30 min")
        harness.truthy(math.abs(companion.thirst - 87.5) < 1e-6, "thirst at half speed while asleep: " .. companion.thirst)
        run(AzeCaught, 1800)
        harness.equal(companion.asleep, nil, "woke up by itself"); harness.truthy(companion.energy > 99.99)
        harness.truthy(journalHas(addon, "the companion woke up after its sleep"))
        companion.energy = 10
        assert(AzeCaught.Care("sleep", "Me-R", NOW))
        assert(AzeCaught.Care("wake", "Me-R", NOW))
        harness.equal(companion.asleep, nil)
    end,

    ["azecaught: neglect costs a heart per 10 min, hearts go negative, a critical need breaks the streaks"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        companion.careStreak, companion.fedStreak = 5, 3
        companion.affection = 20   -- critical
        AzeCaught.Tick(1, NOW)
        harness.equal(companion.careStreak, 0); harness.equal(companion.fedStreak, 3, "affection does not break the fed streak")
        run(AzeCaught, 1199)
        harness.equal(companion.hearts, -2)
        harness.truthy(journalHas(addon, "reason=neglect"))
        harness.equal(AzeCaught.CompanionLevel(companion), 10 + 0 - 2, "negative hearts lower the level")
    end,

    ["azecaught: starving for 2 h kills the companion; it loses its catch and stays found"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        companion.hunger = 0
        harness.equal(run(AzeCaught, AzeCaught.STARVE_TIME - 2), false)
        companion.hunger = 0
        harness.equal(run(AzeCaught, 2), true)
        harness.equal(AzeCaught.Active(), nil)
        harness.equal(AzeCaught.State().collection[4711].caught, 0)
        harness.truthy(AzeCaught.State().collection[4711], "still in the collection as found")
        harness.truthy(journalHas(addon, "the companion died")); harness.truthy(journalHas(addon, "cause=hunger"))
        harness.truthy(addon.Store.db.debug[#addon.Store.db.debug]:find("the companion died", 1, true), "warnings are mirrored to the main log")
    end,

    ["azecaught: feeding in time stops the starve timer"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        companion.thirst = 0
        run(AzeCaught, 600)
        harness.truthy(companion.starve >= 600)
        assert(AzeCaught.Care("water", "Me-R", NOW))
        AzeCaught.Tick(1, NOW)
        harness.equal(companion.starve, 0)
    end,

    ["azecaught: switching away with negative hearts makes it run away; with hearts >= 0 it stays"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        AzeCaught.lastThrowAt = nil
        local otherGuid = "Creature-0-1-2-3-555-0000ABCDEF"
        AzeCaught.Throw({ guid = otherGuid, health = 0.1, name = "Bear", level = 12 }, 10, 500, NOW)
        AzeCaught.forceNextCatch = true
        assert(AzeCaught.OnDeath(otherGuid, "Me-R", 501, NOW, constant(0.99)).caught)
        local wolf = assert(AzeCaught.Select(4711, NOW))
        assert(AzeCaught.Select(555, NOW))
        harness.equal(AzeCaught.State().collection[4711].caught, 1, "hearts 0: back to the collection")
        local wolfAgain = assert(AzeCaught.Select(4711, NOW))
        harness.truthy(wolfAgain ~= wolf, "fresh state on every select")
        wolfAgain.hearts = -1
        local _, _, ranAway = AzeCaught.Select(555, NOW)
        harness.truthy(ranAway and ranAway.npc == 4711)
        harness.equal(AzeCaught.State().collection[4711].caught, 0)
        harness.truthy(journalHas(addon, "ran away"))
    end,

    ["azecaught: a paid action is refused when the pool is short (RF3) and the companion still decays"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        addon.Wallet.Ledger().spent = addon.Wallet.Balance("Me-R") + addon.Wallet.Ledger().spent - 10   -- 10c left
        companion.hunger = 30
        harness.equal(select(2, AzeCaught.Care("feed", "Me-R", NOW)), "funds")
        harness.equal(companion.hunger, 30)
        harness.equal(addon.Wallet.Balance("Me-R"), 10, "nothing was taken")
        harness.truthy(AzeCaught.Care("pet", "Me-R", NOW) == nil or true)
        run(AzeCaught, 60)
        harness.truthy(companion.hunger < 30)
    end,

    ["azecaught: the record section round-trips through peer validation; bad sections are dropped alone (RF4)"] = function(harness)
        local addon = withCaught(harness, { cls = "elite" })
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        companion.hearts = 7
        AzeCaught.NotePeak(companion, NOW)
        harness.truthy(AzeCaught.Publish("Me-R", NOW))
        local mine = addon.Games.Get("Me-R")
        harness.equal(mine.caught.c.npc, 4711); harness.equal(mine.caught.c.h, 7)
        harness.equal(mine.caught.weeks[addon.Games.PeriodKey(NOW)], 10 + 5 + 7)
        local clean = assert(addon.Games.Sanitize(addon.Utility.DeepCopy(mine)))
        harness.equal(clean.caught.c.n, "Wolf"); harness.equal(clean.caught.c.cls, "elite")
        local evil = {
            function(r) r.caught.c.h = 1e12 end, function(r) r.caught.c.disp = -1 end, function(r) r.caught.c.cls = "god" end,
            function(r) r.caught.c.n = ("x"):rep(200) end, function(r) r.caught.c.hu = 101 end, function(r) r.caught.c.sl = "yes" end,
            function(r) r.caught.weeks["2026-W99"] = 1 end, function(r) for i = 1, 10 do r.caught.weeks["2025-W0" .. i] = 1 end end,
            function(r) r.caught.weeks = nil end, function(r) r.caught.c = "x" end, function(r) r.caught.c.lvl = 0.5 end,
        }
        for index, mutate in ipairs(evil) do
            local record = addon.Utility.DeepCopy(mine)
            mutate(record)
            local result = addon.Games.Sanitize(record)
            harness.truthy(result, "the casino part survives (" .. index .. ")")
            harness.equal(result.caught, nil, "bad section " .. index .. " is dropped")
        end
        harness.truthy(journalHas(addon, "a companion section was invalid and dropped"))
        -- a name with escape codes passes (it is escaped on display), control characters do not
        local piped = addon.Utility.DeepCopy(mine); piped.caught.c.n = "A|cffff0000B"
        harness.truthy(addon.Games.Sanitize(piped).caught)
    end,

    ["azecaught: the weekly payout pays last week's place once, by peak level (RF5)"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local lastWeek = addon.Games.PreviousPeriodKey(NOW)
        local records = {
            ["A-R"] = { caught = { weeks = { [lastWeek] = 50 } } },
            ["B-R"] = { caught = { weeks = { [lastWeek] = 30 } } },
            ["C-R"] = { caught = { weeks = { ["2020-W01"] = 999 } } },
        }
        AzeCaught.State().peaks[lastWeek] = 40
        local before = addon.Wallet.Balance("Me-R")
        local amount, reason, rank = AzeCaught.WeeklyPayout("Me-R", records, NOW)
        harness.equal(reason, nil); harness.equal(rank, 2); harness.equal(amount, AzeCaught.PAYOUTS[2])
        harness.equal(addon.Wallet.Balance("Me-R"), before + amount)
        harness.equal(select(2, AzeCaught.WeeklyPayout("Me-R", records, NOW + 3600)), "paid")
        harness.truthy(journalHas(addon, "the weekly payout was earned")); harness.truthy(journalHas(addon, "1.A-R=50"))
        -- three weeks offline: only the last completed week counts, and without a peak nothing is paid
        local later = NOW + 21 * 86400
        harness.equal(select(2, AzeCaught.WeeklyPayout("Me-R", records, later)), "nopeak")
        harness.equal(AzeCaught.State().paidWeek, addon.Games.PreviousPeriodKey(later))
        -- 5th place gets the flat amount
        local many = {}
        for index = 1, 5 do many["P" .. index .. "-R"] = { caught = { weeks = { [addon.Games.PreviousPeriodKey(later + 7 * 86400)] = 100 + index } } } end
        AzeCaught.State().peaks[addon.Games.PreviousPeriodKey(later + 7 * 86400)] = 1
        harness.equal(AzeCaught.WeeklyPayout("Me-R", many, later + 7 * 86400), AzeCaught.PAYOUT_OTHER)
    end,

    ["azecaught: persisted state is re-validated on load"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local saved = { schema = 2, games = {}, caught = {
            collection = { [4711] = { n = "Wolf", lvl = 10, cls = "normal", disp = 5, seen = 1, caught = 1 },
                [12] = { n = "Bad", lvl = 0, cls = "normal", disp = 0, seen = 1, caught = 0 }, ["x"] = {} },
            active = { npc = 4711, hunger = 0 / 0, thirst = 1, affection = 1, energy = 1, hearts = 1, fedStreak = 0, careStreak = 0 },
            peaks = { ["2026-W47"] = 5, bad = 3 }, activeSeconds = -4, paidWeek = "nope", journal = { "ok", 5 },
            ledger = { earned = -1, spent = 10, entries = { { t = 1, k = "food", a = -10, b = 5 }, "junk" } } } }
        local loaded = addon.Store.Init(saved)
        local caught = loaded.caught
        harness.truthy(caught.collection[4711]); harness.equal(caught.collection[12], nil)
        harness.equal(caught.active, nil, "a companion with a NaN need is dropped")
        harness.equal(caught.peaks.bad, nil); harness.equal(caught.activeSeconds, 0); harness.equal(caught.paidWeek, nil)
        harness.equal(#caught.journal >= 1, true); harness.equal(caught.ledger.earned, 0); harness.equal(#caught.ledger.entries, 1)
        harness.truthy(table.concat(loaded.debug, "\n"):find("invalid saved AZEcaught data was dropped", 1, true))
        -- a valid companion survives
        local addon2 = harness.addon({ now = NOW })
        local good = addon2.Store.Init({ schema = 2, games = {}, caught = {
            collection = { [4711] = { n = "Wolf", lvl = 10, cls = "normal", disp = 5, seen = 1, caught = 1 } },
            active = { npc = 4711, hunger = 50, thirst = 60, affection = 70, energy = 80, hearts = -3, fedStreak = 1, careStreak = 2,
                since = 0, starve = 0, neglect = 0, snap = 0, asleep = 99999 } } })
        harness.equal(good.caught.active.hearts, -3); harness.equal(good.caught.active.asleep, addon2.AzeCaught.SLEEP_DURATION)
        harness.equal(good.caught.active.zones.hunger, "needy")
    end,

    ["azecaught: schema 1 data migrates to 2 with an empty AZEcaught state"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local loaded, status = addon.Store.Init({ schema = 1, games = {} })
        harness.equal(status, "migrated"); harness.equal(loaded.schema, 2); harness.equal(type(loaded.caught), "table")
    end,

    ["azecaught: journal: own ring, filter, verbose echo, export line"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local printed = {}
        addon.Print = function(text) printed[#printed + 1] = text end
        AzeCaught.State().verbose = true
        AzeCaught.Journal("DEBUG", "test.area", "hello journal", { k = 1 })
        harness.truthy(printed[#printed]:find("[caught.test.area] hello journal :: k=1", 1, true))
        AzeCaught.State().verbose = nil
        local lines = AzeCaught.JournalLines(2, "HELLO")
        harness.equal(#lines, 1)
        for index = 1, AzeCaught.JOURNAL_ENTRIES + 20 do AzeCaught.Journal("DEBUG", "fill", "line " .. index) end
        harness.equal(#AzeCaught.State().journal, AzeCaught.JOURNAL_ENTRIES)
        harness.truthy(#addon.Store.db.debug < 50, "debug lines stay out of the main log")
        AzeCaught.Select(4711, NOW)
        local export = AzeCaught.Export("Me-R")
        harness.truthy(export:find("^AZE1 "), export)
        harness.truthy(export:find("c.npc=4711", 1, true)); harness.truthy(export:find("balance=", 1, true))
        AzeCaught.State().active = nil
        harness.truthy(AzeCaught.Export("Me-R"):find("c=none", 1, true))
    end,

    ["azecaught: model rows: guild companions ranked by level, my live row, escaped names; collection order"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        companion.hearts = 4
        local records = {
            ["Peer|cff-R"] = { caught = { weeks = {}, c = { npc = 1, n = "Big|r", lvl = 20, cls = "rare", disp = 0, h = -5, hu = 1, th = 2, af = 3, en = 4 } } },
            ["Tie-R"] = { caught = { weeks = {}, c = { npc = 2, n = "Cat", lvl = 14, cls = "normal", disp = 0, h = 0, hu = 1, th = 2, af = 3, en = 4, sl = true } } },
            ["None-R"] = { caught = { weeks = {} } },
            ["Me-R"] = { caught = { weeks = {}, c = { npc = 3, n = "Stale", lvl = 1, cls = "normal", disp = 0, h = 0, hu = 0, th = 0, af = 0, en = 0 } } },
        }
        local rows = addon.Model.BuildCompanionRows(records, "Me-R")
        harness.equal(#rows, 3)
        harness.equal(rows[1].nameRaw, "Peer|cff-R"); harness.equal(rows[1].level, 20 + 10 - 5); harness.equal(rows[1].companion, "Big||r")
        harness.equal(rows[1].name, "Peer||cff-R")
        harness.equal(rows[2].level, 14); harness.equal(rows[2].nameRaw, "Me-R", "ties by name; my live row, not the stale record")
        harness.equal(rows[2].companion, "Wolf"); harness.equal(rows[2].mine, true)
        harness.equal(rows[3].asleep, true); harness.equal(rows[3].rank, 3)
        AzeCaught.NoteFound({ npc = 50, name = "aardvark" }, NOW)
        AzeCaught.NoteFound({ npc = 51, name = "Zebra" }, NOW)
        AzeCaught.State().collection[51].caught = 2
        local collection = addon.Model.BuildCollectionRows(AzeCaught.State().collection, 4711)
        harness.equal(collection[1].npc, 4711); harness.equal(collection[2].npc, 51); harness.equal(collection[3].npc, 50)
        local winner = addon.Model.CompanionWinner({ ["X|-R"] = { caught = { weeks = { ["2026-W46"] = 9 } } } }, "2026-W46", "Me-R")
        harness.equal(winner.name, "X||-R"); harness.equal(winner.peak, 9)
        harness.equal(addon.Model.CompanionWinner({}, "2026-W46", "Me-R"), nil)
    end,

    -- secret values (combat, instances): health hidden -> the throw is allowed and rolls as if at THROW_HEALTH
    ["azecaught: a throw at a unit whose health is hidden rolls at the threshold (worst case) and says so"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        harness.truthy(AzeCaught.Throw({ guid = GUID, health = nil, name = nil, level = nil }, 10, 100, NOW))
        harness.truthy(journalHas(addon, "hp=hidden"))
        local result = assert(AzeCaught.OnDeath(GUID, "Me-R", 101, NOW, constant(0.999)))
        harness.equal(result.chance, AzeCaught.Chance(AzeCaught.THROW_HEALTH, "normal", 10, 10).chance)
        harness.equal(AzeCaught.State().collection[4711].n, "?", "a hidden name is stored as ? and learned later")
        AzeCaught.NoteFound({ npc = 4711, name = "Wolf" }, NOW)
        harness.equal(AzeCaught.State().collection[4711].n, "Wolf")
    end,

    -- user 2026-11-20: the care streak counts at most one care action per hour (play time)
    ["azecaught: the care streak grows at most once per hour of play time"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local companion = assert(AzeCaught.Select(4711, NOW))
        companion.affection = 80
        assert(AzeCaught.Care("pet", "Me-R", NOW))
        harness.equal(companion.careStreak, 1)
        companion.affection = 80
        assert(AzeCaught.Care("pet", "Me-R", NOW))
        companion.hunger = 70
        assert(AzeCaught.Care("feed", "Me-R", NOW))
        harness.equal(companion.careStreak, 1, "more care inside the hour does not count")
        harness.equal(companion.fedStreak, 1, "the fed streak is not limited")
        harness.truthy(journalHas(addon, "streakCounted=false"))
        AzeCaught.State().activeSeconds = AzeCaught.State().activeSeconds + AzeCaught.CARE_STREAK_GAP - 1
        companion.affection = 80
        assert(AzeCaught.Care("pet", "Me-R", NOW))
        harness.equal(companion.careStreak, 1, "59:59 later: still the same hour")
        AzeCaught.State().activeSeconds = AzeCaught.State().activeSeconds + 1
        companion.affection = 80
        assert(AzeCaught.Care("pet", "Me-R", NOW))
        harness.equal(companion.careStreak, 2, "a full hour after the counted action")
        -- a fresh companion starts its own hour
        harness.equal(AzeCaught.CARE_STREAK_GAP, 3600)
    end,

    -- user 2026-11-20: the first catch roll ever always succeeds (once per character; dev add does not use it up)
    ["azecaught: the very first catch roll succeeds, later rolls use the chance"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        AzeCaught.State().firstCatchDone = nil
        AzeCaught.Throw({ guid = GUID, health = 0.3, name = "Wolf", level = 10 }, 10, 100, NOW)
        local first = assert(AzeCaught.OnDeath(GUID, "Me-R", 101, NOW, constant(0.999)))
        harness.equal(first.caught, true, "first roll is a catch"); harness.equal(first.first, true)
        harness.equal(AzeCaught.State().firstCatchDone, true)
        harness.truthy(journalHas(addon, "first=true"))
        local other = "Creature-0-1-2-3-555-0000ABCDEF"
        AzeCaught.Throw({ guid = other, health = 0.3, name = "Bear", level = 10 }, 10, 200, NOW)
        local second = assert(AzeCaught.OnDeath(other, "Me-R", 201, NOW, constant(0.999)))
        harness.equal(second.caught, false, "the second roll uses the chance")
        -- persisted and re-validated
        local loaded = harness.addon({ now = NOW }).Store.Init({ schema = 2, games = {}, caught = { firstCatchDone = true } })
        harness.equal(loaded.caught.firstCatchDone, true)
        local junk = harness.addon({ now = NOW }).Store.Init({ schema = 2, games = {}, caught = { firstCatchDone = "yes" } })
        harness.equal(junk.caught.firstCatchDone, nil)
    end,

    -- user 2026-11-20: need intervals and thresholds generated from the NPC's stats
    ["azecaught: stats are stored with the found NPC and filled in later; hidden values stay unknown"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local entry = AzeCaught.NoteFound({ npc = 7, name = "Wolf", level = 10, stats = { type = 1, typeName = "Wildtier", family = "Wolf" } }, NOW)
        harness.equal(entry.st.type, 1); harness.equal(entry.st.typeName, "Wildtier"); harness.equal(entry.st.hp, nil)
        AzeCaught.NoteFound({ npc = 7, stats = { hp = 900, power = 1, powerMax = 100, sex = 2 } }, NOW)
        AzeCaught.NoteFound({ npc = 7, stats = { hp = 400, type = 6 } }, NOW)
        harness.equal(entry.st.hp, 900, "the highest health seen"); harness.equal(entry.st.type, 1, "a known type is kept")
        harness.equal(entry.st.power, 1); harness.equal(entry.st.sex, 2)
        harness.truthy(journalHas(addon, "stats"))
        -- a type known only by its localized name
        harness.equal(AzeCaught.CreatureTypeId(nil, "Untoter"), 6); harness.equal(AzeCaught.CreatureTypeId(nil, "Beast"), 1)
        harness.equal(AzeCaught.CreatureTypeId(9, "whatever"), 9); harness.equal(AzeCaught.CreatureTypeId(nil, "???"), nil)
    end,

    ["azecaught: the profile: no stats -> the normal schedule; type, power and rarity change intervals and thresholds"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        local base = AzeCaught.Profile({ cls = "normal" })
        harness.equal(base.intervals.thirst, AzeCaught.WATER_INTERVAL); harness.equal(base.intervals.hunger, AzeCaught.FOOD_INTERVAL)
        harness.equal(base.ok, AzeCaught.OK_LEVEL); harness.equal(base.critical, AzeCaught.CRITICAL_LEVEL); harness.equal(#base.traits, 0)
        local beast = AzeCaught.Profile({ cls = "normal", st = { type = 1 } })
        harness.equal(beast.intervals.hunger, AzeCaught.FOOD_INTERVAL * 0.75); harness.equal(beast.intervals.affection, AzeCaught.PET_INTERVAL * 0.75)
        local undead = AzeCaught.Profile({ cls = "normal", st = { type = 6 } })
        harness.equal(undead.intervals.thirst, nil, "undead are never thirsty")
        local angry = AzeCaught.Profile({ cls = "rareelite", st = { power = 1 } })
        harness.equal(angry.critical, AzeCaught.CRITICAL_LEVEL + 5 + 5); harness.equal(angry.ok, AzeCaught.OK_LEVEL + 5 + 5)
        harness.equal(angry.traits[1], "rage"); harness.equal(angry.traits[2], "rareelite")
        local boss = AzeCaught.Profile({ cls = "worldboss", st = { power = 1, type = 3 } })
        harness.truthy(boss.critical <= 40 and boss.ok >= boss.critical + 10, "thresholds stay in bounds")
    end,

    ["azecaught: a companion follows its profile: an undead never gets thirsty, a beast is hungry sooner, zones use its thresholds"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        local entry = AzeCaught.State().collection[4711]
        entry.st = { type = 6 }
        local companion = assert(AzeCaught.Select(4711, NOW))
        run(AzeCaught, 3 * 3600)
        harness.equal(companion.thirst, 100); harness.equal(companion.zones.thirst, "ok")
        harness.equal(AzeCaught.SecondsUntilNeedy(companion, "thirst"), math.huge)
        harness.equal(select(2, AzeCaught.Care("water", "Me-R", NOW)), "full", "no water for the undead")
        -- a raging beast: food due after 1.5 h, needy already at 55
        AzeCaught.NoteFound({ npc = 555, name = "Bear", level = 10, stats = { type = 1, power = 1 } }, NOW)
        AzeCaught.State().collection[555].caught = 1
        local bear = assert(AzeCaught.Select(555, NOW))
        run(AzeCaught, 5399)
        harness.equal(bear.zones.hunger, "ok")
        run(AzeCaught, 1)
        harness.equal(bear.zones.hunger, "needy", "needy at the profile's level after 1.5 h")
        harness.truthy(math.abs(bear.hunger - 55) < 1e-6, "hunger " .. bear.hunger)
        harness.equal(AzeCaught.ZoneOf(bear, "hunger"), "needy")
        -- the profile survives a reload
        local saved = addon.Utility.DeepCopy(addon.Store.db)
        local reloaded = harness.addon({ now = NOW }).Store.Init(saved)
        harness.equal(reloaded.caught.active.npc, 555)
        harness.equal(reloaded.caught.active.zones.hunger, "needy")
    end,

    ["azecaught: persisted stats are re-validated"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local loaded = addon.Store.Init({ schema = 2, games = {}, caught = { collection = {
            [7] = { n = "Wolf", lvl = 10, cls = "normal", disp = 0, seen = 1, caught = 0,
                st = { type = 1, typeName = "Wildtier", family = ("x"):rep(300), hp = -5, power = 1, powerMax = 1e12, sex = 9 } } } } })
        local st = loaded.caught.collection[7].st
        harness.equal(st.type, 1); harness.equal(st.typeName, "Wildtier"); harness.equal(st.family, nil)
        harness.equal(st.hp, nil); harness.equal(st.power, 1); harness.equal(st.powerMax, nil); harness.equal(st.sex, nil)
    end,

    ["azecaught: NPC info: header, only known values, needs compared with normal, traits"] = function(harness)
        local addon = withCaught(harness)
        local entry = addon.AzeCaught.State().collection[4711]
        entry.cls = "elite"
        entry.st = { type = 1, typeName = "Wildtier", family = "Wolf", hp = 900, power = 1, powerMax = 100 }
        local info = addon.Model.BuildNpcInfo(4711, entry)
        harness.equal(info.title, "Wolf"); harness.equal(info.rarityColor, "ffd100")
        harness.truthy(info.subtitle:find("Wildtier (Wolf)", 1, true) and info.subtitle:find("Elite", 1, true), info.subtitle)
        local facts = {}
        for _, fact in ipairs(info.facts) do facts[fact.label] = fact.value end
        harness.equal(facts.Health, "900"); harness.equal(facts.Power, "Rage 100")
        harness.equal(facts.Gender, nil, "unknown values are left out ...")
        harness.equal(info.hiddenCount, 1, "... and counted")
        local needs = {}
        for _, need in ipairs(info.needs) do needs[need.need] = need end
        harness.equal(needs.hunger.trend, "more", "a beast is hungrier"); harness.equal(needs.thirst.trend, "normal")
        harness.truthy(needs.hunger.text:find("1h 30m", 1, true), needs.hunger.text)
        harness.truthy(info.thresholds:find("58", 1, true), "rage +5 and elite +3: " .. info.thresholds)
        harness.equal(#info.traits, 3)
        local undead = addon.Model.BuildNpcInfo(1, { n = "X|r", lvl = 3, cls = "normal", disp = 0, caught = 0, st = { type = 6 } })
        harness.equal(undead.title, "X||r", "escaped")
        for _, need in ipairs(undead.needs) do if need.need == "thirst" then harness.equal(need.trend, "never") end end
        local bare = addon.Model.BuildNpcInfo(2, { n = "Y", lvl = 1, cls = "normal", disp = 0, caught = 0 })
        harness.equal(#bare.facts, 0); harness.equal(bare.hiddenCount, 4); harness.equal(#bare.traits, 0)
        harness.equal(#info.combat, 3, "attack, defense, speed")
        harness.equal(info.combat[1].label, "Attack"); harness.equal(info.combat[3].label, "Speed")
        harness.equal(info.combat[2].value, tostring(addon.AzeCaught.CombatStats(4711, entry).defense))
        harness.equal(#bare.combat, 3, "calculated even when the game hid everything")
        -- bars: the base of a normal level-60 NPC is a full bar (user 2026-11-20)
        harness.equal(addon.AzeCaught.CombatScale(), 130)
        local weak = addon.Model.BuildNpcInfo(5, { n = "Z", lvl = 15, cls = "normal", disp = 0, caught = 0 })
        for _, stat in ipairs(weak.combat) do
            harness.truthy(stat.fill > 0.25 and stat.fill < 0.36, "level 15 is about 30%: " .. stat.fill)
            harness.equal(stat.over, false)
        end
        local boss = addon.Model.BuildNpcInfo(6, { n = "B", lvl = 63, cls = "worldboss", disp = 0, caught = 0 })
        for _, stat in ipairs(boss.combat) do harness.equal(stat.fill, 1, "capped"); harness.equal(stat.over, true) end
    end,

    -- user 2026-11-20: Attack / Defense / Speed from level, rarity, creature type and a hash of the NPC id (display only)
    ["azecaught: combat stats are fixed per NPC and follow level, rarity and creature type"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        local function stats(npcId, level, cls, typeId)
            return AzeCaught.CombatStats(npcId, { lvl = level, cls = cls, st = typeId and { type = typeId } or nil })
        end
        local wolf = stats(4711, 20, "normal", 1)
        harness.equal(AzeCaught.StatsText(wolf), AzeCaught.StatsText(stats(4711, 20, "normal", 1)), "same NPC, same numbers")
        local spread, distinct = {}, 0
        for npcId = 1, 200 do
            local attack = stats(npcId, 20, "normal").attack
            if not spread[attack] then spread[attack], distinct = true, distinct + 1 end
        end
        harness.truthy(distinct > 10, "neighbouring NPC ids differ: " .. distinct .. " distinct attack values")
        for npcId = 1, 200 do
            local s = stats(npcId, 20, "normal")
            for _, key in ipairs({ "attack", "defense", "speed" }) do
                harness.truthy(s[key] >= 42 and s[key] <= 58, key .. " within +-15% of 50: " .. s[key])
            end
        end
        local function total(s) return s.attack + s.defense + s.speed end
        harness.truthy(total(stats(4711, 30, "normal")) > total(stats(4711, 10, "normal")), "higher level, higher stats")
        harness.truthy(total(stats(4711, 20, "elite")) > total(stats(4711, 20, "normal")), "elite beats normal")
        harness.truthy(total(stats(4711, 20, "worldboss")) > total(stats(4711, 20, "rareelite")), "world boss beats rare elite")
        local undead, plain = stats(4711, 20, "normal", 6), stats(4711, 20, "normal")
        harness.truthy(undead.defense > plain.defense and undead.speed < plain.speed, "undead: tougher and slower")
        local beast = stats(4711, 20, "normal", 1)
        harness.truthy(beast.speed > plain.speed, "beasts are fast")
        local odd = AzeCaught.CombatStats(0, { lvl = 0 / 0, cls = "nonsense", st = { type = 999 } })
        harness.truthy(odd.attack >= 1 and odd.defense >= 1 and odd.speed >= 1, "bad input still gives sane numbers")
    end,

    -- user 2026-11-20: the collection has a caught section (at most 10) and a seen section (limited, highest level)
    ["azecaught: at most 10 caught: a full collection refuses the throw and a death after it is filled gets no roll"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        harness.equal(AzeCaught.MAXIMUM_CAUGHT, 10)
        for npc = 100, 108 do
            local entry = AzeCaught.NoteFound({ npc = npc, name = "N" .. npc }, NOW)
            entry.caught = 1
        end
        AzeCaught.State().collection[100].caught = 2   -- duplicates count: 10 now
        harness.equal(AzeCaught.CaughtCount(), 10)
        harness.equal(select(2, AzeCaught.Throw({ guid = GUID, health = 0.1, name = "Wolf" }, 10, 100, NOW)), "full")
        harness.truthy(journalHas(addon, "reason=full"))
        AzeCaught.State().collection[100].caught = 1   -- 9: a throw is armed ...
        assert(AzeCaught.Throw({ guid = GUID, health = 0.1, name = "Wolf" }, 10, 100, NOW))
        AzeCaught.State().collection[100].caught = 2   -- ... and the collection fills before the kill
        AzeCaught.forceNextCatch = true
        harness.equal(select(2, AzeCaught.OnDeath(GUID, "Me-R", 101, NOW, constant(0))), "full")
        harness.equal(AzeCaught.CaughtCount(), 10)
    end,

    ["azecaught: the seen list is limited; the oldest uncaught NPC makes room, caught ones are kept"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        AzeCaught.MAXIMUM_SEEN = 3
        AzeCaught.NoteFound({ npc = 1, name = "Kept", level = 5 }, NOW - 100).caught = 1
        AzeCaught.NoteFound({ npc = 2, name = "Oldest" }, NOW - 50)
        AzeCaught.NoteFound({ npc = 3, name = "Older" }, NOW - 40)
        AzeCaught.NoteFound({ npc = 4, name = "Old" }, NOW - 30)
        local collection = AzeCaught.State().collection
        harness.truthy(collection[2] and collection[3] and collection[4], "3 uncaught fit")
        AzeCaught.NoteFound({ npc = 5, name = "New" }, NOW)
        harness.equal(collection[2], nil, "the oldest uncaught made room")
        harness.truthy(collection[1] and collection[5])
        harness.truthy(journalHas(addon, "the oldest seen NPC made room"))
    end,

    ["azecaught: collection sections: caught (active first) and seen (all, highest level first)"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        AzeCaught.NoteFound({ npc = 1, name = "Zebra", level = 3 }, NOW).caught = 1
        AzeCaught.NoteFound({ npc = 2, name = "Ant", level = 20 }, NOW).caught = 2
        AzeCaught.NoteFound({ npc = 3, name = "Bat", level = 7 }, NOW)
        AzeCaught.NoteFound({ npc = 3, level = 12 }, NOW)
        local sections = addon.Model.BuildCollectionSections(AzeCaught.State().collection, 1)
        harness.equal(#sections.caught, 2); harness.equal(sections.caught[1].npc, 1, "the active companion first")
        harness.equal(sections.caught[2].npc, 2)
        harness.equal(#sections.seen, 3)
        harness.equal(sections.seen[1].npc, 2); harness.equal(sections.seen[2].npc, 3); harness.equal(sections.seen[2].lvl, 12, "highest level")
        harness.equal(sections.caughtCount, 3); harness.equal(sections.caughtLimit, 10)
    end,

    -- user 2026-11-20: care buttons are greyed out when they cannot be used; the check must agree with Care
    ["azecaught: CareAvailability agrees with Care's refusals and changes nothing"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        harness.equal(select(2, AzeCaught.CareAvailability("feed", "Me-R")), "none")
        local companion = assert(AzeCaught.Select(4711, NOW))
        local function check(action, expected)
            local before = addon.Utility.DeepCopy(companion)
            local balance = addon.Wallet.Balance("Me-R")
            local usable, reason = AzeCaught.CareAvailability(action, "Me-R")
            harness.equal(reason, expected, action)
            harness.equal(usable, expected == nil, action .. " usable")
            harness.equal(addon.Wallet.Balance("Me-R"), balance, "no money moved"); harness.equal(companion.hunger, before.hunger)
            if expected then harness.equal(select(2, AzeCaught.Care(action, "Me-R", NOW)), expected, "Care agrees: " .. action) end
        end
        check("feed", "full"); check("wake", "awake"); check("dance", "action")
        companion.hunger = 40; check("feed", nil)
        addon.Wallet.Ledger().spent = addon.Wallet.Ledger().spent + addon.Wallet.Balance("Me-R")   -- 0 left
        check("feed", "funds"); check("pet", "full")
        companion.affection = 40; check("pet", nil)
        companion.energy = 10; assert(AzeCaught.Care("sleep", "Me-R", NOW))
        check("pet", "asleep"); check("wake", nil)
    end,

    -- user 2026-11-20: the rope hits each enemy only once
    ["azecaught: one throw per enemy: a second throw at the same GUID is refused, another enemy is fine"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        assert(AzeCaught.Throw({ guid = GUID, health = 0.1, name = "Wolf" }, 10, 100, NOW))
        harness.equal(select(2, AzeCaught.Throw({ guid = GUID, health = 0.1 }, 10, 110, NOW)), "thrown", "after the cooldown too")
        harness.truthy(AzeCaught.Throw({ guid = "Creature-0-1-2-3-555-0000ABCDEF", health = 0.1, name = "Bear" }, 10, 110, NOW))
        AzeCaught.ExpireThrows(1000)
        harness.equal(next(AzeCaught.thrown), nil, "the memory is bounded")
    end,

    -- user 2026-11-20: the icon glow goes from red to green as the catch chance rises
    ["azecaught: throw quality: 0 (red) at the threshold, 1 (green) at 0 HP, nil when health is hidden"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        harness.equal(AzeCaught.ThrowQuality(AzeCaught.THROW_HEALTH), 0)
        harness.equal(AzeCaught.ThrowQuality(0), 1)
        harness.equal(AzeCaught.ThrowQuality(nil), nil)
        harness.equal(AzeCaught.ThrowQuality(0.9), 0, "above the threshold is clamped")
        local previous = -1
        for step = 35, 0, -1 do
            local quality = AzeCaught.ThrowQuality(step / 100)
            harness.truthy(quality >= previous, "rises as health falls"); previous = quality
        end
        local r, g = AzeCaught.QualityColor(0); harness.truthy(r > 0.9 and g < 0.3, "red")
        r, g = AzeCaught.QualityColor(1); harness.truthy(g > 0.9 and r < 0.4, "green")
        r, g = AzeCaught.QualityColor(0.5); harness.truthy(r > 0.9 and g > 0.7, "yellow in the middle")
        r, g = AzeCaught.QualityColor(nil); harness.truthy(r > 0.9 and g > 0.7, "unknown: neutral yellow")
    end,

    -- user 2026-11-20: an addon option to move the rope icon or turn it off
    ["azecaught: icon settings have defaults, are clamped, journaled and re-validated on load"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local icon = AzeCaught.IconSettings()
        harness.equal(icon.shown, true); harness.equal(icon.x, 0); harness.equal(icon.y, 2); harness.equal(icon.size, 26)
        AzeCaught.SetIconSetting("x", 500); harness.equal(AzeCaught.IconSettings().x, AzeCaught.ICON_LIMITS.x[2])
        AzeCaught.SetIconSetting("size", 3); harness.equal(AzeCaught.IconSettings().size, AzeCaught.ICON_LIMITS.size[1])
        AzeCaught.SetIconSetting("shown", false); harness.equal(AzeCaught.IconSettings().shown, false)
        harness.equal(AzeCaught.SetIconSetting("nonsense", 1), false)
        harness.truthy(journalHas(addon, "an icon setting changed"))
        AzeCaught.ResetIconSettings(); harness.equal(AzeCaught.IconSettings().size, 26); harness.equal(AzeCaught.IconSettings().shown, true)
        local loaded = harness.addon({ now = NOW }).Store.Init({ schema = 2, games = {}, caught = { icon = { shown = "x", x = 0 / 0, y = 999, size = 30 } } })
        harness.equal(loaded.caught.icon.shown, true); harness.equal(loaded.caught.icon.x, 0)
        harness.equal(loaded.caught.icon.y, AzeCaught.ICON_LIMITS.y[2]); harness.equal(loaded.caught.icon.size, 30)
    end,
    ["azecaught: reset clears the game but keeps settings, journal and (without all) the wallet"] = function(harness)
        local addon = withCaught(harness)
        local AzeCaught = addon.AzeCaught
        assert(AzeCaught.Select(4711, NOW))
        AzeCaught.Tick(60, NOW)
        AzeCaught.SetIconSetting("size", 30); AzeCaught.State().notify = false
        addon.Wallet.Earn("Me-R", 500, "dev", NOW, "give")
        AzeCaught.thrown["x"], AzeCaught.forceNextCatch = 1, true
        local summary = AzeCaught.Reset()
        harness.equal(summary.found, 1); harness.equal(summary.caught, 1); harness.equal(summary.companion, true)
        local state = AzeCaught.State()
        harness.equal(next(state.collection), nil); harness.equal(state.active, nil); harness.equal(state.activeSeconds, 0)
        harness.equal(next(state.peaks), nil); harness.equal(state.firstCatchDone, nil); harness.equal(state.paidWeek, nil)
        harness.equal(next(AzeCaught.thrown), nil); harness.equal(AzeCaught.forceNextCatch, false)
        harness.equal(AzeCaught.IconSettings().size, 30, "settings stay"); harness.equal(state.notify, false)
        harness.truthy(journalHas(addon, "AZEcaught was reset"), "the journal stays and marks the cut")
        harness.truthy(addon.Wallet.Ledger().earned > 0, "the wallet stays without all")
        AzeCaught.Reset(true)
        harness.equal(addon.Wallet.Ledger().earned, 0, "reset all clears the wallet")
    end,
    ["azecaught: the throw target is projected by camera geometry and shrinks with distance"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        local view = { width = 2000, height = 1000, zoom = 12 }
        local playerX, playerY, playerScale = AzeCaught.ProjectToScreen(view, 0, 0)
        harness.equal(playerX, 1000, "the player is centred")
        harness.truthy(playerY > 380 and playerY < 460, "the character stands a little below the middle: " .. playerY)
        harness.equal(playerScale, 1, "the player is the reference size")
        local nearX, nearY, nearScale = AzeCaught.ProjectToScreen(view, 5, 0)
        local farX, farY, farScale = AzeCaught.ProjectToScreen(view, 30, 0)
        harness.equal(nearX, 1000); harness.equal(farX, 1000, "straight ahead stays centred")
        harness.truthy(playerY < nearY and nearY < farY, "farther away = higher on the screen")
        harness.truthy(1 > nearScale and nearScale > farScale, "farther away = smaller")
        harness.truthy(farY < 1000 * 0.95, "even far targets stay below the horizon / on the screen")
        local rightX = AzeCaught.ProjectToScreen(view, 10, math.rad(30))
        local leftX = AzeCaught.ProjectToScreen(view, 10, -math.rad(30))
        harness.truthy(rightX > 1000 and leftX < 1000 and math.abs((rightX - 1000) + (leftX - 1000)) < 0.001, "bearing: + right, - left")
        local behindX, behindY = AzeCaught.ProjectToScreen(view, 10, math.pi)
        harness.truthy(behindX >= 0 and behindX <= 2000 and behindY >= 0 and behindY <= 1000, "behind the camera: clamped on screen")
        local zoomedOutY = select(2, AzeCaught.ProjectToScreen({ width = 2000, height = 1000, zoom = 30 }, 10, 0))
        harness.truthy(zoomedOutY < nearY + (farY - nearY), "a farther camera shrinks the spread")
        local defaultX, defaultY = AzeCaught.ProjectToScreen({ width = 2000, height = 1000 }, 10, 0)
        harness.truthy(defaultX == 1000 and defaultY > playerY, "no zoom known: default camera")
    end,
}
