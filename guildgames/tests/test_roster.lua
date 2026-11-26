-- The companion roster: every catch is its own companion, one is active, the resting ones are frozen, switching keeps
-- every state, training belongs to one companion, the move from the one-companion data and the sanitizer.
local NOW = 1794873600
local ME = "Me-R"

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = ME
    addon.AzeCaught.throws, addon.AzeCaught.rolled, addon.AzeCaught.thrown, addon.AzeCaught.lastThrowAt = {}, {}, {}, nil
    addon.AzeCaught.again, addon.AzeCaught.forceNextCatch = {}, false
    addon.AzeCaught.State().firstCatchDone = true
    return addon
end

-- catches NPC `npc` once through the real throw and roll
local function catch(addon, npc, serial)
    local AzeCaught = addon.AzeCaught
    local guid = ("Creature-0-1-2-3-%d-%08X"):format(npc, serial)
    AzeCaught.lastThrowAt = nil
    assert(AzeCaught.Throw({ guid = guid, health = 0.1, name = "Npc" .. npc, level = 10 }, 10, serial * 10, NOW))
    AzeCaught.forceNextCatch = true
    local result = AzeCaught.OnDeath(guid, ME, serial * 10 + 1, NOW, function() return 0.99 end)
    assert(result and result.caught, "caught")
    return result
end

local function run(AzeCaught, seconds)
    for _ = 1, seconds do AzeCaught.Tick(1, NOW) end
end

return {
    ["roster: two catches of one NPC are two companions with their own ids; the first becomes active"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local first = catch(addon, 4711, 1)
        harness.truthy(first.companion, "the first catch became the companion")
        catch(addon, 4711, 2)
        catch(addon, 555, 3)
        local roster = AzeCaught.Roster()
        harness.equal(#roster, 3)
        harness.equal(AzeCaught.State().collection[4711].caught, 2)
        harness.truthy(roster[1] == AzeCaught.Active(), "the active one is listed first")
        local ids = {}
        for _, companion in ipairs(roster) do
            harness.truthy(type(companion.uid) == "string" and not ids[companion.uid], "an own id")
            ids[companion.uid] = true
        end
        local wolves = {}
        for _, companion in ipairs(roster) do if companion.npc == 4711 then wolves[#wolves + 1] = companion end end
        harness.equal(#wolves, 2)
        harness.truthy(wolves[1] ~= wolves[2], "two separate companions")
        addon.Arena.Progress(wolves[1]).xp = 500
        harness.equal(addon.Arena.Progress(wolves[2]).xp, 0, "arena progress per companion")
    end,

    ["roster: the resting companion is frozen for 10 h, the active one decays; switching back continues"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        catch(addon, 4711, 1)
        catch(addon, 555, 2)
        local wolf = AzeCaught.Active()
        wolf.hunger, wolf.affection = 64, 81
        local streakAt = wolf.streakAt
        local bear = assert(AzeCaught.Select(555, NOW))
        run(AzeCaught, 10 * 3600)
        harness.truthy(bear.hunger < 64, "the active one decays")
        harness.equal(wolf.hunger, 64); harness.equal(wolf.affection, 81)
        local back, refusal, trainingCancelled = AzeCaught.Select(wolf.uid, NOW)
        harness.truthy(back == wolf, tostring(refusal))
        harness.equal(trainingCancelled, nil)
        harness.equal(wolf.restAt, nil)
        harness.equal(AzeCaught.State().activeSeconds - wolf.since < 10 * 3600, true, "its age does not grow while resting")
        harness.equal(wolf.streakAt, streakAt and streakAt + 10 * 3600 or nil)
        harness.equal(select(2, AzeCaught.Select("u999", NOW)), "unknown")
    end,

    ["roster: switching cancels a running training without refund; it never finishes on another companion"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught, Arena = addon.AzeCaught, addon.Arena
        addon.Wallet.Earn(ME, 100000, "dev", NOW, "test")
        catch(addon, 4711, 1)
        catch(addon, 555, 2)
        local wolf = AzeCaught.Active()
        assert(Arena.Train(ME, "atk", NOW))
        local money = addon.Wallet.Balance(ME)
        local bear, _, cancelled = AzeCaught.Select(555, NOW)
        harness.truthy(bear and cancelled, "cancelled")
        harness.equal(Arena.State().training, nil)
        harness.equal(addon.Wallet.Balance(ME), money, "no refund")
        AzeCaught.State().activeSeconds = AzeCaught.State().activeSeconds + Arena.TRAIN_SECONDS
        harness.equal(Arena.FinishTraining(), nil)
        harness.equal(Arena.Progress(wolf).tr.atk, 0); harness.equal(Arena.Progress(bear).tr.atk, 0)
        -- a finished training belongs to the companion that trained
        assert(Arena.Train(ME, "def", NOW))
        AzeCaught.State().activeSeconds = AzeCaught.State().activeSeconds + Arena.TRAIN_SECONDS
        local done = assert(Arena.FinishTraining())
        harness.equal(done.uid, bear.uid); harness.equal(Arena.Progress(bear).tr.def, 1); harness.equal(Arena.Progress(wolf).tr.def, 0)
    end,

    ["roster: release and death remove exactly one companion; the collection count follows"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        catch(addon, 4711, 1)
        catch(addon, 4711, 2)
        catch(addon, 4711, 3)
        local roster = AzeCaught.Roster()
        local resting = roster[2]
        assert(AzeCaught.Release(resting.uid))
        harness.equal(AzeCaught.State().collection[4711].caught, 2)
        harness.equal(AzeCaught.Companion(resting.uid), nil)
        harness.equal(select(2, AzeCaught.Release(resting.uid)), "unknown")
        -- the active one starves: only it leaves
        local active = AzeCaught.Active()
        active.hunger, active.thirst = 0, 0
        local died = false
        for _ = 1, AzeCaught.STARVE_TIME + 10 do if AzeCaught.Tick(1, NOW).died then died = true break end end
        harness.truthy(died, "it died")
        harness.equal(AzeCaught.Active(), nil)
        harness.equal(#AzeCaught.Roster(), 1)
        harness.equal(AzeCaught.State().collection[4711].caught, 1)
        harness.equal(AzeCaught.State().collection[4711].got, 3, "the catches ever stay")
    end,

    ["roster: one-companion data moves to the roster; the active keeps its state and the arena progress per NPC"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local loaded = addon.Store.Init({ schema = 2, games = {}, me = ME, caught = {
            collection = {
                [4711] = { n = "Wolf", lvl = 5, cls = "normal", disp = 0, seen = NOW, caught = 2 },
                [555] = { n = "Bear", lvl = 9, cls = "elite", disp = 0, seen = NOW, caught = 1 },
                [99] = { n = "Rat", lvl = 1, cls = "normal", disp = 0, seen = NOW, caught = 0 },
            },
            active = { npc = 4711, hearts = 4, fedStreak = 1, careStreak = 0, hunger = 40, thirst = 50, affection = 60, energy = 70,
                since = 10, starve = 0, neglect = 0, snap = 0 },
            activeSeconds = 500,
            arena = { npcs = { [4711] = { xp = 120, w = 3, l = 1, tr = { atk = 2 } }, [555] = { xp = 60, w = 1, l = 0, tr = { def = 1 } } },
                training = { stat = "spd", npc = 4711, done = 900 } },
        } })
        harness.equal(loaded.schema, addon.Store.SCHEMA)
        local caught = loaded.caught
        harness.equal(addon.Utility.Count(caught.roster), 3, "two wolves and a bear")
        local active = caught.active
        harness.truthy(active and caught.roster[active.uid] == active, "the active companion is in the roster")
        harness.equal(active.hunger, 40); harness.equal(active.hearts, 4)
        harness.equal(active.ar.xp, 120); harness.equal(active.ar.tr.atk, 2)
        harness.equal(caught.arena.training.uid, active.uid, "the running training belongs to it")
        local otherWolf, bear
        for _, companion in pairs(caught.roster) do
            if companion.npc == 4711 and companion ~= active then otherWolf = companion end
            if companion.npc == 555 then bear = companion end
        end
        harness.equal(otherWolf.hunger, 100, "the other wolf starts fresh")
        harness.equal(otherWolf.ar, nil, "the wolves' progress went to the active one only")
        harness.equal(bear.ar.xp, 60); harness.equal(bear.ar.tr.def, 1)
        harness.equal(caught.arena.npcs, nil)
        -- loading the moved data again changes nothing
        local again = harness.addon({ now = NOW }).Store.Init(addon.Utility.DeepCopy(loaded))
        harness.equal(addon.Utility.Count(again.caught.roster), 3, "nothing duplicated")
        harness.equal(again.caught.active.uid, active.uid)
    end,

    ["roster: garbage entries, a dangling active id and the cap are handled on load"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local roster = {
            u1 = { npc = 4711, hearts = 1, fedStreak = 0, careStreak = 0, hunger = 50, thirst = 50, affection = 50, energy = 50 },
            u2 = { npc = 12345, hearts = 0, fedStreak = 0, careStreak = 0, hunger = 50, thirst = 50, affection = 50, energy = 50 },
            u3 = { npc = 4711, hearts = "x" },
            bogus = { npc = 4711, hearts = 0, fedStreak = 0, careStreak = 0, hunger = 50, thirst = 50, affection = 50, energy = 50 },
        }
        local loaded = addon.Store.Init({ schema = 3, games = {}, me = ME, caught = {
            collection = { [4711] = { n = "Wolf", lvl = 5, cls = "normal", disp = 0, seen = NOW, caught = 9 } },
            roster = roster, activeID = "u7", nextID = 3 } })
        local caught = loaded.caught
        harness.equal(addon.Utility.Count(caught.roster), 1, "only the valid wolf stays")
        harness.truthy(caught.roster.u1)
        harness.equal(caught.collection[4711].caught, 1, "the count follows the roster")
        harness.equal(caught.active, nil, "a dangling active id means no companion")
        -- a new catch does not reuse an id
        addon.AzeCaught.State().collection[4711].caught = 2
        addon.AzeCaught.Reconcile()
        for uid in pairs(addon.AzeCaught.State().roster) do harness.truthy(uid == "u1" or addon.AzeCaught.UidNumber(uid) > 3, uid) end
        -- the cap: a full roster refuses the throw
        local AzeCaught = addon.AzeCaught
        local saved = AzeCaught.ROSTER_LIMIT
        AzeCaught.ROSTER_LIMIT = 2
        local ok, reason = AzeCaught.Throw({ guid = "Creature-0-1-2-3-4711-00000001", health = 0.1, name = "Wolf", level = 5 }, 10, 1, NOW)
        AzeCaught.ROSTER_LIMIT = saved
        harness.equal(ok, nil); harness.equal(reason, "rosterfull")
    end,
}
