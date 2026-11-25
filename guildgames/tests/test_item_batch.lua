-- The second item batch: charms (one slot), care items, arena buffs on the published fighter, Companion Dash items and the
-- Survivor Bomb, with their saved data and the marks on the boards.
local NOW = 1794873600
local GUID = "Creature-0-1-2-3-4711-0000ABCDEF"
local ME = "Me-R"

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = ME
    addon.AzeCaught.throws, addon.AzeCaught.rolled, addon.AzeCaught.thrown, addon.AzeCaught.lastThrowAt = {}, {}, {}, nil
    addon.AzeCaught.again = {}
    addon.AzeCaught.forceNextCatch = false
    addon.AzeCaught.State().firstCatchDone = true
    return addon
end

-- a fresh addon with an active companion (a beast)
local function withCompanion(harness, name)
    local addon = fresh(harness)
    if name then addon.Store.db.me = name end
    local AzeCaught = addon.AzeCaught
    local entry = AzeCaught.NoteFound({ npc = 100, name = "Npc100", level = 20, classification = "normal", stats = { type = 1 } }, NOW)
    entry.caught = 1
    assert(AzeCaught.Select(100, NOW))
    return addon
end

local function target(options)
    options = options or {}
    return { guid = options.guid or GUID, health = options.health == nil and 1 or options.health, name = "Wolf", level = 10,
        classification = options.cls or "normal" }
end

-- a list of fixed random values, then 0.5
local function sequence(...)
    local values, index = { ... }, 0
    return function() index = index + 1; return values[index] or 0.5 end
end

local function seeded(seed)
    return function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
end

return {
    ["item batch: a charm is bought once, equipped in the one slot, swapped and taken off for free"] = function(harness)
        local addon = fresh(harness)
        local Items = addon.Items
        addon.Wallet.Earn(ME, 1000 * 10000, "dev", NOW)
        harness.equal(Items.Buy("charmLuck", ME, NOW), 1)
        harness.equal(select(2, Items.Buy("charmLuck", ME, NOW)), "stack", "a charm is owned at most once")
        Items.Buy("charmLure", ME, NOW)
        harness.equal(Items.Equipped(), nil, "bought is not equipped")
        local balance = addon.Wallet.Balance(ME)
        harness.truthy(Items.Use("charmLuck", { myName = ME, now = NOW }))
        harness.equal(Items.Equipped().id, "charmLuck"); harness.equal(Items.Count("charmLuck"), 1, "equipping keeps the charm")
        Items.Use("charmLure", { myName = ME, now = NOW })
        harness.equal(Items.Equipped().id, "charmLure", "one slot: the other charm comes off")
        Items.Use("charmLure", { myName = ME, now = NOW })
        harness.equal(Items.Equipped(), nil, "using the equipped charm takes it off")
        harness.equal(addon.Wallet.Balance(ME), balance, "equipping is free")
        harness.truthy(not Items.Equip("meat"), "only charms go into the slot")
        harness.truthy(not Items.Equip("charmSteady"), "only owned charms")
    end,

    ["item batch: charm effects on catches (reward, lure, best moment, second throw); none without equipping"] = function(harness)
        local addon = fresh(harness)
        local Items, AzeCaught = addon.Items, addon.AzeCaught
        local inventory = Items.Inventory()
        inventory.charmLuck, inventory.charmLure, inventory.charmSteady, inventory.charmSecond = 1, 1, 1, 1
        -- the reward
        harness.equal(AzeCaught.CharmRewardFactor("elite"), 1, "nothing equipped")
        Items.Equip("charmLuck")
        harness.equal(AzeCaught.CharmRewardFactor("normal"), 1.10)
        assert(AzeCaught.Throw(target({ health = 0.05 }), 10, 100, NOW))
        local result = AzeCaught.OnDeath(GUID, ME, 101, NOW + 1, sequence(0))
        harness.truthy(result.caught)
        harness.equal(result.reward, math.floor(AzeCaught.Reward(result.chance) * 1.10 + 0.5))
        Items.Equip("charmLure")
        harness.equal(AzeCaught.CharmRewardFactor("normal"), 1); harness.equal(AzeCaught.CharmRewardFactor("rare"), 1.25)
        harness.equal(AzeCaught.CharmRewardFactor("rareelite"), 1.25)
        -- the best moment
        harness.equal(AzeCaught.Chance(0.12, "normal").best, false)
        Items.Equip("charmSteady")
        harness.equal(AzeCaught.Chance(0.12, "normal").best, true, "Steady Hand: 12% health is already the best moment")
        harness.truthy(math.abs(AzeCaught.Chance(0.13, "normal").chance - AzeCaught.CHANCE_AT_BEST) < 1e-9)
        -- without Second Chance a rope that slipped off ends the NPC: no second throw
        local other = "Creature-0-1-2-3-4712-0000ABCDEF"
        assert(AzeCaught.Throw(target({ guid = other, health = 0.3 }), 10, 200, NOW + 10))
        local late = AzeCaught.EndLateThrows(204)
        harness.equal(#late, 1); harness.equal(late[1].again, nil)
        harness.equal(select(2, AzeCaught.Throw(target({ guid = other, health = 0.2 }), 10, 210, NOW + 20)), "rolled")
        -- with Second Chance: one more throw at the same NPC, then the next slip ends it
        Items.Equip("charmSecond")
        local third = "Creature-0-1-2-3-4713-0000ABCDEF"
        assert(AzeCaught.Throw(target({ guid = third, health = 0.3 }), 10, 300, NOW + 30))
        late = AzeCaught.EndLateThrows(304)
        harness.equal(late[1].again, true, "the rope slipped off: a second throw is allowed")
        harness.truthy(AzeCaught.Throw(target({ guid = third, health = 0.2 }), 10, 305, NOW + 35), "thrown again")
        late = AzeCaught.EndLateThrows(309)
        harness.equal(late[1].again, nil, "only one second throw")
        harness.equal(select(2, AzeCaught.Throw(target({ guid = third, health = 0.1 }), 10, 312, NOW + 40)), "rolled")
        -- a second throw that lands rolls normally and is marked
        local fourth = "Creature-0-1-2-3-4714-0000ABCDEF"
        assert(AzeCaught.Throw(target({ guid = fourth, health = 0.3 }), 10, 400, NOW + 50))
        AzeCaught.EndLateThrows(404)
        assert(AzeCaught.Throw(target({ guid = fourth, health = 0.05 }), 10, 405, NOW + 55))
        local result2 = AzeCaught.OnDeath(fourth, ME, 406, NOW + 56, sequence(0))
        harness.truthy(result2.caught and result2.second, "caught with the second throw")
    end,

    ["item batch: Feast and Toy fill their needs, a refusal keeps the item; the Elixir stops the decay"] = function(harness)
        local addon = withCompanion(harness)
        local Items, AzeCaught = addon.Items, addon.AzeCaught
        local inventory = Items.Inventory()
        inventory.feast, inventory.toy, inventory.elixir = 2, 1, 1
        harness.equal(select(2, Items.Use("feast", { myName = ME, now = NOW })), "full", "nothing to fill")
        harness.equal(Items.Count("feast"), 2)
        local companion = AzeCaught.Active()
        companion.hunger, companion.thirst, companion.affection = 20, 40, 10
        local ok, result = Items.Use("feast", { myName = ME, now = NOW })
        harness.truthy(ok); harness.equal(#result.filled, 2)
        harness.equal(companion.hunger, 100); harness.equal(companion.thirst, 100); harness.equal(companion.affection, 10)
        assert(Items.Use("toy", { myName = ME, now = NOW }))
        harness.equal(companion.affection, 100)
        companion.asleep = 100
        companion.hunger = 50
        harness.equal(select(2, Items.Use("feast", { myName = ME, now = NOW })), "asleep")
        companion.asleep = nil
        -- the Elixir: no decay of hunger, thirst and affection while it runs, energy still drops
        companion.hunger, companion.thirst, companion.affection, companion.energy = 80, 80, 80, 80
        assert(Items.Use("elixir", { myName = ME, now = NOW }))
        AzeCaught.Tick(60, NOW + 60)
        harness.equal(companion.hunger, 80); harness.equal(companion.thirst, 80); harness.equal(companion.affection, 80)
        harness.truthy(companion.energy < 80, "energy still drops")
        AzeCaught.Tick(60, NOW + 4 * 3600 + 1)
        harness.truthy(companion.hunger < 80, "the decay resumes after 4 h")
        AzeCaught.Tick(60, NOW - 99999)
        harness.truthy(companion.hunger >= 0)
        -- no companion
        AzeCaught.State().active = nil
        harness.equal(select(2, Items.Use("feast", { myName = ME, now = NOW })), "none")
    end,

    ["item batch: arena buffs raise the published fighter, list their ids and are spent per published fighter"] = function(harness)
        local A = withCompanion(harness, "A-R")
        local Items, Arena = A.Items, A.Arena
        local plain = Arena.Fighter(A.AzeCaught.Active())
        harness.equal(plain.bf, nil)
        Items.Inventory().warPaint, Items.Inventory().swiftTonic = 2, 1
        assert(Items.Use("warPaint", { myName = "A-R", now = NOW }))
        harness.equal(select(2, Items.Use("warPaint", { myName = "A-R", now = NOW })), "running", "no stacking of the same buff")
        harness.equal(Items.Count("warPaint"), 1)
        assert(Items.Use("swiftTonic", { myName = "A-R", now = NOW }))
        local buffed = Arena.Fighter(A.AzeCaught.Active())
        harness.equal(buffed.atk, math.floor(plain.atk * 1.10 + 0.5))
        harness.equal(buffed.spd, math.floor(plain.spd * 1.25 + 0.5))
        harness.equal(buffed.def, plain.def)
        harness.equal(table.concat(buffed.bf, ","), "warPaint,swiftTonic")
        -- a peer's copy keeps the stats, cleans the ids
        local copy = Arena.SanitizeFighter(buffed)
        harness.equal(copy.atk, buffed.atk); harness.equal(table.concat(copy.bf, ","), "warPaint,swiftTonic")
        local garbage = Arena.SanitizeFighter(setmetatable({ bf = { "meat", "warPaint", "warPaint", "nope", "barkSkin", "swiftTonic" } },
            { __index = buffed }))
        harness.equal(table.concat(garbage.bf, ","), "warPaint", "only known arena buffs, no repeats, the first 3 entries")
        harness.equal(Arena.SanitizeFighter(setmetatable({ bf = "x" }, { __index = buffed })).bf, nil)
        -- spending: one fight per published fighter
        Items.SpendArenaBuffs(buffed.bf)
        harness.equal(Items.ArenaBuffs().warPaint, 2); harness.equal(Items.ArenaBuffs().swiftTonic, nil)
        harness.equal(Arena.Fighter(A.AzeCaught.Active()).bf[1], "warPaint")
    end,

    ["item batch: a challenge spends the buffs once; the fight is the same for a client that drops bf"] = function(harness)
        local A = withCompanion(harness, "A-R")
        local B = withCompanion(harness, "B-R")
        A.Items.Inventory().barkSkin = 1
        assert(A.Items.Use("barkSkin", { myName = "A-R", now = NOW }))
        local records = { ["B-R"] = { name = "B-R", caught = B.AzeCaught.BuildSection() } }
        local id = assert(A.Arena.Challenge(records, "A-R", "B-R", 0, NOW))
        harness.equal(A.Items.ArenaBuffs().barkSkin, 2, "one of 3 fights used")
        local challenge = A.Arena.State().ch[id]
        harness.equal(challenge.f.bf[1], "barkSkin")
        local old = {}
        for key, value in pairs(challenge.f) do if key ~= "bf" then old[key] = value end end
        local other = B.Arena.Fighter(B.AzeCaught.Active())
        local withBuffs, withoutBuffs = A.Arena.Fight(challenge.f, other, id), A.Arena.Fight(old, other, id)
        harness.equal(withBuffs.winner, withoutBuffs.winner)
        harness.equal(#withBuffs.events, #withoutBuffs.events)
    end,

    ["item batch: the Dash Shield absorbs one hit, the Head Start starts at 200 m and pays only beyond it"] = function(harness)
        local addon = fresh(harness)
        local Runner = addon.Runner
        local pool = { { npc = 1, disp = 0, n = "A", fly = false } }
        local run = Runner.New(pool, 3, { shield = true })
        local shielded = false
        for _ = 1, 60 * 60 do
            Runner.Step(run, 1 / 60, {})
            for _, event in ipairs(Runner.TakeEvents(run)) do if event.kind == "shield" then shielded = true end end
            if run.finished then break end
        end
        harness.truthy(shielded, "the first hit was absorbed")
        harness.truthy(run.finished, "the second hit ends the run")
        harness.equal(run.shield, 0)
        local start = Runner.New(pool, 3, { start = true })
        harness.equal(Runner.Meters(start), 200)
        harness.truthy(start.speed > Runner.START_SPEED, "at the speed of 200 m")
        harness.equal(start.milestones, 2)
        start.distance = 450 * Runner.PIXELS_PER_METER
        local result = Runner.Finish(start, ME, NOW)
        harness.equal(result.meters, 450); harness.equal(result.gold, 2, "250 paid meters")
        local state = Runner.State()
        harness.equal(state.recent[1].it, 1); harness.equal(state.bi, 1)
        -- a plain run is not marked
        local plain = Runner.New(pool, 4)
        plain.distance = 500 * Runner.PIXELS_PER_METER
        Runner.Finish(plain, ME, NOW + 10)
        harness.equal(state.recent[1].it, nil); harness.equal(state.bi, nil, "the new best is plain")
        -- the marks survive the wire and show on the board and feed
        local section = Runner.SanitizeSection(Runner.BuildSection(), math.huge)
        harness.equal(section.recent[2].it, 1)
        local records = { [ME] = { runner = section } }
        harness.equal(Runner.FeedRows(records, ME)[2].item, true)
        harness.equal(Runner.BoardRows(records, "all", "x", ME)[1].item, false)
        section.recent[1].it = "yes"
        harness.equal(Runner.SanitizeSection(section, math.huge).recent[1].it, nil)
    end,

    ["item batch: runner items are used only when a run starts"] = function(harness)
        local addon = fresh(harness)
        local Items = addon.Items
        Items.Inventory().dashShield = 1
        harness.equal(select(2, Items.Use("dashShield", { myName = ME, now = NOW })), "norun")
        harness.equal(Items.Count("dashShield"), 1)
        local ok, result = Items.Use("dashShield", { myName = ME, now = NOW, runStart = true })
        harness.truthy(ok); harness.equal(result.run, "shield"); harness.equal(Items.Count("dashShield"), 0)
    end,

    ["item batch: the Survivor Bomb clears the screen once per run, only up to a 250g stake; the play is marked"] = function(harness)
        local addon = fresh(harness)
        local Items, Survivor = addon.Items, addon.Survivor
        addon.Wallet.Earn(ME, 1000 * 10000, "dev", NOW)
        Items.Inventory().bomb = 3
        harness.equal(select(2, Items.Use("bomb", { myName = ME, now = NOW })), "norun")
        local big = assert(Survivor.Begin(ME, 300 * 10000, 1, NOW, seeded(2)))
        harness.equal(select(2, Items.Use("bomb", { myName = ME, now = NOW, survivorRun = big })), "stake")
        big.finished = "lost"; Survivor.Settle(big, NOW)
        local run = assert(Survivor.Begin(ME, 100 * 10000, 1, NOW, seeded(3)))
        for _ = 1, 60 do Survivor.Advance(run, 0.1) while run.choices do Survivor.Choose(run, 1) end end
        local alive = 0
        for _, enemy in ipairs(run.enemies) do if enemy.hp > 0 then alive = alive + 1 end end
        harness.truthy(alive > 0, "monsters are on the screen")
        local ok, result = Items.Use("bomb", { myName = ME, now = NOW, survivorRun = run })
        harness.truthy(ok); harness.equal(result.killed, alive)
        for _, enemy in ipairs(run.enemies) do harness.truthy(enemy.hp <= 0) end
        harness.equal(select(2, Items.Use("bomb", { myName = ME, now = NOW, survivorRun = run })), "used")
        harness.equal(Items.Count("bomb"), 2)
        run.finished = "lost"
        Survivor.Settle(run, NOW + 30)
        local mine = addon.Games.Get(ME)
        harness.equal(mine.survivor.recent[1].it, 1); harness.equal(mine.survivor.recent[2].it, nil)
        harness.truthy(addon.Games.Sanitize(mine), "a marked play passes peer validation")
    end,

    ["item batch: saved charm slot and arena buffs are sanitized"] = function(harness)
        local addon = fresh(harness)
        local caught = addon.AzeCaught.State()
        caught.items = { charmLuck = 1 }
        caught.equipped = "charmLure"
        caught.arenaBuffs = { warPaint = 3, swiftTonic = 5, meat = 1, barkSkin = 0, nope = 2 }
        harness.truthy(addon.AzeCaught.SanitizePersisted(addon.Store.db) > 0)
        harness.equal(caught.equipped, nil, "a charm that is not owned is not equipped")
        harness.equal(caught.arenaBuffs.warPaint, 3); harness.equal(caught.arenaBuffs.swiftTonic, nil)
        harness.equal(caught.arenaBuffs.meat, nil); harness.equal(caught.arenaBuffs.barkSkin, nil)
        caught.equipped = "charmLuck"
        caught.arenaBuffs = "x"
        addon.AzeCaught.SanitizePersisted(addon.Store.db)
        harness.equal(caught.equipped, "charmLuck"); harness.equal(type(caught.arenaBuffs), "table")
        harness.equal(addon.AzeCaught.SanitizePersisted(addon.Store.db), 0, "clean data needs no repair")
    end,
}
