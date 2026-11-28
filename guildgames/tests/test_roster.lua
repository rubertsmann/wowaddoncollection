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

    ["roster: the move still happens when a guild record writes a journal line before the companions are sanitized"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local outdated = { name = "B-R", rev = 1, total = { won = 0, lost = 0, wins = 0, losses = 0 }, weeks = {}, recent = {},
            arena = { ch = { ["B-R#1"] = { to = ME, at = 1, wg = 0, f = { npc = 6500 } } } } }
        local loaded = addon.Store.Init({ schema = 2, games = { ["B-R"] = outdated }, me = ME, caught = {
            collection = {
                [6500] = { n = "Saur", lvl = 55, cls = "elite", disp = 0, seen = NOW, caught = 1 },
                [99] = { n = "Rat", lvl = 1, cls = "normal", disp = 0, seen = NOW, caught = 2 },
            },
            active = { npc = 6500, hearts = 19, fedStreak = 5, careStreak = 0, hunger = 88, thirst = 82, affection = 88, energy = 100,
                since = 10, starve = 0, neglect = 0, snap = 0 },
            activeSeconds = 500,
            arena = { npcs = { [6500] = { xp = 40, w = 1, l = 0, tr = { atk = 10, def = 1 } } } },
        } })
        harness.equal(loaded.games["B-R"].arena, nil, "the outdated arena section was dropped (and journaled)")
        local caught = loaded.caught
        harness.equal(addon.Utility.Count(caught.roster), 3, "the saur and two rats")
        harness.equal(caught.collection[6500].caught, 1); harness.equal(caught.collection[99].caught, 2)
        local active = caught.active
        harness.truthy(active and active.npc == 6500, "the active companion survived")
        harness.equal(active.hearts, 19)
        harness.equal(active.ar.xp, 40); harness.equal(active.ar.w, 1); harness.equal(active.ar.tr.atk, 10); harness.equal(active.ar.tr.def, 1)
        harness.equal(caught.moveRoster, nil, "the move marker is cleared")
    end,

    ["roster: a restore code brings a wiped companion back once, with hearts and arena training, and survives a reload"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local code = AzeCaught.RestoreCode({ npc = 6500, hearts = 19, fedStreak = 5, careStreak = 0, hunger = 88.6, thirst = 82.9,
            affection = 88.6, energy = 100, ar = { xp = 40, w = 1, l = 0, tr = { atk = 10, def = 1 } } },
            { n = "Tyrant Saur", lvl = 55, cls = "elite" })
        harness.equal(code, "GGR1;6500;55;elite;19;5;0;89;83;89;100;40;1;0;10;1;0;0;Tyrant Saur")
        -- the wiped state: the collection entry stays with 0 caught, a newer catch is active
        AzeCaught.State().collection[6500] = { n = "Tyrant Saur", lvl = 55, cls = "elite", disp = 0, seen = NOW, caught = 0, cnt = 3 }
        catch(addon, 555, 1)
        local other = AzeCaught.Active()
        harness.equal(select(2, AzeCaught.Restore("GGR1;6500;55", NOW)), "code")
        harness.equal(select(2, AzeCaught.Restore("XXX1;6500;55;elite;19;5;0;89;83;89;100;40;1;0;10;1;0;0;Saur", NOW)), "code")
        harness.equal(select(2, AzeCaught.Restore("GGR1;6500;55;boss;19;5;0;89;83;89;100;40;1;0;10;1;0;0;Saur", NOW)), "code")
        local saur = assert(AzeCaught.Restore(code, NOW))
        harness.truthy(AzeCaught.Active() == saur, "the restored companion is active")
        harness.truthy(other.restAt ~= nil, "the other one rests")
        harness.equal(saur.hearts, 19); harness.equal(saur.fedStreak, 5); harness.equal(saur.hunger, 89)
        harness.equal(saur.n, "Tyrant Saur"); harness.equal(saur.lvl, 55)
        harness.equal(saur.ar.xp, 40); harness.equal(saur.ar.w, 1); harness.equal(saur.ar.tr.atk, 10); harness.equal(saur.ar.tr.def, 1)
        harness.equal(AzeCaught.State().collection[6500].caught, 1)
        harness.equal(AzeCaught.State().collection[6500].cnt, 3, "the history stays")
        harness.equal(addon.Utility.Count(AzeCaught.State().roster), 2)
        harness.equal(select(2, AzeCaught.Restore(code, NOW)), "used", "once per character")
        local again = harness.addon({ now = NOW }).Store.Init({ schema = 3, games = {}, me = ME,
            caught = addon.Utility.DeepCopy(AzeCaught.State()) })
        harness.equal(again.caught.active.uid, saur.uid); harness.equal(again.caught.active.ar.tr.atk, 10)
        harness.equal(again.caught.collection[6500].caught, 1)
        harness.equal(again.caught.restoredAt, NOW)
    end,

    ["roster: a restore code also works when the collection entry is gone"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local saur = assert(AzeCaught.Restore("GGR1;6500;55;elite;19;5;0;89;83;89;100;40;1;0;10;1;0;0;Tyrant; Saur", NOW))
        harness.equal(saur.n, "Tyrant; Saur", "the name may hold the separator")
        harness.equal(AzeCaught.State().collection[6500].caught, 1)
        harness.truthy(AzeCaught.Active() == saur)
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

    ["roster: each catch keeps the look of the creature it was made of, not the NPC's first-seen look"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        -- the found list already shows the female look of NPC 1564
        AzeCaught.NoteFound({ npc = 1564, name = "Guard", level = 10, display = 4462 }, NOW)
        local guid = "Creature-0-1-2-3-1564-00000001"
        assert(AzeCaught.Throw({ guid = guid, health = 0.1, name = "Guard", level = 10, display = 4461 }, 10, 10, NOW))
        AzeCaught.forceNextCatch = true
        local male = assert(AzeCaught.OnDeath(guid, ME, 11, NOW, function() return 0.99 end))
        harness.equal(AzeCaught.Companion(male.uid).disp, 4461, "the caught male keeps the male look")
        harness.equal(AzeCaught.State().collection[1564].disp, 4462, "the found list keeps its own look")
        local trapped = assert(AzeCaught.TrapCatch({ guid = "Creature-0-1-2-3-1564-00000002", health = 0.9, name = "Guard",
            level = 10, display = 4462 }, addon.Items.Get("trap"), ME, 20, NOW))
        harness.equal(AzeCaught.Companion(trapped.uid).disp, 4462, "a trapped female keeps the female look")
        -- no look read at the catch: the NPC's look, as before
        local unknown = catch(addon, 1564, 3)
        harness.equal(AzeCaught.Companion(unknown.uid).disp, 4462)
        -- the arena fighter and the collection's caught rows show the companion's own look
        harness.equal(addon.Arena.Fighter(AzeCaught.Companion(male.uid)).disp, 4461)
        local looks = {}
        for _, row in ipairs(addon.Model.BuildRosterRows(AzeCaught.Roster(), AzeCaught.State().collection, AzeCaught.Active())) do
            looks[row.uid] = row.disp
        end
        harness.equal(looks[male.uid], 4461, "the caught row shows the male"); harness.equal(looks[trapped.uid], 4462)
    end,

    ["roster: a companion's gender is the one its look was seen with"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        AzeCaught.NoteFound({ npc = 1564, name = "Warlock", level = 10, display = 4462, stats = { sex = 3 } }, NOW)
        local male = catch(addon, 1564, 1)
        harness.truthy(AzeCaught.SetDisplay(male.uid, 4461))
        local companion = AzeCaught.Companion(male.uid)
        harness.equal(AzeCaught.CompanionSex(companion), nil, "the male look was never seen: unknown, not the NPC's female")
        harness.equal(AzeCaught.WantsLook(1564), true, "a sighting of NPC 1564 should read its look")
        -- a male of NPC 1564 is seen (a nameplate, a throw)
        AzeCaught.NoteFound({ npc = 1564, display = 4461, stats = { sex = 2 } }, NOW)
        harness.equal(AzeCaught.CompanionSex(companion), 2)
        harness.equal(AzeCaught.WantsLook(1564), false)
        harness.equal(AzeCaught.State().collection[1564].disp, 4462, "the found list keeps its look")
        AzeCaught.NoteFound({ npc = 1564, display = 4461, stats = { sex = 1 } }, NOW)
        harness.equal(AzeCaught.CompanionSex(companion), 2, "neutral or unknown never overwrites")
        -- kept over a reload, garbage dropped
        local entry = AzeCaught.State().collection[1564]
        entry.sx[777] = 9; entry.sx.x = 2
        AzeCaught.SanitizePersisted(addon.Store.db)
        entry = AzeCaught.State().collection[1564]
        harness.equal(entry.sx[4461], 2); harness.equal(entry.sx[4462], 3)
        harness.equal(entry.sx[777], nil); harness.equal(entry.sx.x, nil)
        -- bounded
        for display = 1, 20 do AzeCaught.NoteFound({ npc = 1564, display = 5000 + display, stats = { sex = 2 } }, NOW) end
        harness.equal(addon.Utility.Count(AzeCaught.State().collection[1564].sx), AzeCaught.MAXIMUM_LOOKS)
    end,

    ["roster: the look whose model matches the caught creature is picked from the NPC's loads"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        -- the client loads NPC 1564 as female (4462, file 1000764) or male (4461, file 1011653)
        local function loads(sequence)
            local index = 0
            return function()
                index = index + 1
                local look = sequence[(index - 1) % #sequence + 1]
                if look == false then return nil end
                return look[1], look[2]
            end
        end
        local female, male = { 4462, 1000764 }, { 4461, 1011653 }
        local display, matched, tries = AzeCaught.PickDisplay(loads({ female, female, male }), 1011653, 6)
        harness.equal(display, 4461); harness.equal(matched, true); harness.equal(tries, 3)
        display, matched = AzeCaught.PickDisplay(loads({ female }), 1011653, 6)
        harness.equal(display, 4462, "never the male: the first look, so it stays the same"); harness.equal(matched, false)
        display, matched, tries = AzeCaught.PickDisplay(loads({ male, female }), nil, 6)
        harness.equal(display, 4461); harness.equal(matched, false); harness.equal(tries, 1, "no model file to match: the first")
        display, matched, tries = AzeCaught.PickDisplay(loads({ false, false, female }), 1000764, 6)
        harness.equal(display, 4462); harness.equal(matched, true, "loads without a display are skipped"); harness.equal(tries, 3)
        harness.equal(AzeCaught.PickDisplay(loads({ false }), 1000764, 6), nil, "nothing loaded")
    end,

    ["roster: a companion without a look gets one once and keeps it; bad values are refused"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1)
        local uid = result.uid
        harness.equal(AzeCaught.Companion(uid).disp, 0, "nothing known yet")
        harness.equal(#AzeCaught.WithoutDisplay(), 1)
        harness.truthy(AzeCaught.SetDisplay(uid, 7197))
        harness.equal(AzeCaught.Companion(uid).disp, 7197)
        harness.equal(#AzeCaught.WithoutDisplay(), 0, "filled ones are left alone")
        harness.truthy(AzeCaught.SetDisplay(uid, 7198), "a new look can be set (the dev command)")
        harness.equal(AzeCaught.Companion(uid).disp, 7198)
        for _, bad in ipairs({ 0, -1, 1.5, "x", 1e12 }) do
            harness.equal(AzeCaught.SetDisplay(uid, bad), false, "refused: " .. tostring(bad))
        end
        harness.equal(AzeCaught.SetDisplay("u999", 7197), false, "no such companion")
        harness.equal(AzeCaught.Companion(uid).disp, 7198)
        -- the stored look survives a reload (the load sanitizer); one without a look still takes the NPC's
        local other = catch(addon, 555, 2).uid
        AzeCaught.State().collection[555].disp = 300
        harness.equal(AzeCaught.SanitizePersisted(addon.Store.db), 0, "clean data needs no repair")
        harness.equal(AzeCaught.Companion(uid).disp, 7198, "kept over a reload")
        harness.equal(AzeCaught.Companion(other).disp, 300)
        AzeCaught.Companion(uid).disp = "garbage"
        AzeCaught.SanitizePersisted(addon.Store.db)
        harness.equal(AzeCaught.Companion(uid).disp, 0, "a broken look falls back to the NPC's (unknown here)")
        addon.Store.db.readonly = true
        harness.equal(AzeCaught.SetDisplay(uid, 7197), false, "read-only data stays untouched")
        addon.Store.db.readonly = false
    end,
}
