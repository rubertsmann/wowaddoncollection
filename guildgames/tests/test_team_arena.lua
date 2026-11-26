-- Team arena fights: 3 against 3 in order, the round winner carries everything into the next round, rewards per
-- companion, the same-version gate, peer teams and the leftovers of one-against-one fights.
local NOW = 1794873600

local function fighter(overrides)
    local base = { npc = 1, n = "A", cls = "normal", disp = 0, ty = 1, al = 1, atk = 50, def = 50, spd = 50, vit = 50, ab = "strike" }
    for key, value in pairs(overrides or {}) do base[key] = value end
    return base
end

-- a player with `count` companions of `npc` (the first active)
local function player(harness, name, npc, count)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = name
    local entry = addon.AzeCaught.NoteFound({ npc = npc, name = "Npc" .. npc, level = 20, classification = "normal", stats = { type = 1 } }, NOW)
    entry.caught = count or 3
    assert(addon.AzeCaught.Select(npc, NOW))
    addon.team = {}
    for index, companion in ipairs(addon.AzeCaught.Roster()) do addon.team[index] = companion.uid end
    return addon
end

local function recordOf(addon, owner)
    local section = addon.Arena.SanitizeSection(addon.Arena.BuildSection(), owner, math.huge)
    assert(section, "my own section must survive validation")
    return { name = owner, caught = addon.AzeCaught.BuildSection(), arena = section }
end

local function recordsFor(players, viewer)
    local records = {}
    for name, addon in pairs(players) do if name ~= viewer then records[name] = recordOf(addon, name) end end
    return records
end

return {
    ["team arena: a 3 vs 3 fight runs in order; the round winner keeps its health; the same teams give the same fight"] = function(harness)
        local Arena = harness.addon({ now = NOW }).Arena
        local strong = fighter({ n = "Strong", atk = 140, def = 120, vit = 140 })
        local teamA = { strong, fighter({ n = "A2" }), fighter({ n = "A3" }) }
        local teamB = { fighter({ npc = 2, n = "B1" }), fighter({ npc = 2, n = "B2" }), fighter({ npc = 2, n = "B3" }) }
        local result = Arena.Fight(teamA, teamB, "T-R#1")
        local again = Arena.Fight(teamA, teamB, "T-R#1")
        harness.equal(result.winner, again.winner); harness.equal(#result.events, #again.events)
        for index, event in ipairs(result.events) do
            harness.equal(event.k, again.events[index].k); harness.equal(event.d, again.events[index].d)
            harness.equal(event.ia, again.events[index].ia); harness.equal(event.ib, again.events[index].ib)
        end
        -- B's fighters enter one after the other while A's first one stays in with its health
        local enters, healthBefore, carried = 0, nil, true
        for index, event in ipairs(result.events) do
            if event.k == "enter" and event.s == "b" then
                enters = enters + 1
                healthBefore = result.events[index - 1].ha
                if event.ha ~= healthBefore then carried = false end
                harness.equal(event.hb, event.mb, "the new fighter enters fresh")
                harness.equal(event.ib, enters + 1)
            end
        end
        harness.truthy(enters >= 1, "at least one of B's fighters came in")
        harness.truthy(carried, "the winner of a round keeps its health into the next")
        harness.equal(result.entered.b, enters + 1)
        local total = 0
        for slot = 1, 3 do total = total + result.knockouts[result.winner][slot] end
        harness.equal(total, result.winner == "a" and result.entered.b or result.entered.a, "every opponent beaten is counted")
        -- the side that lost has no fighter left
        local loser = result.winner == "a" and "b" or "a"
        harness.equal(result.entered[loser], 3)
        -- one against one stays the old duel
        local duel = Arena.Fight(teamA[2], teamB[1], "T-R#2")
        local asTeams = Arena.Fight({ teamA[2] }, { teamB[1] }, "T-R#2")
        harness.equal(duel.winner, asTeams.winner); harness.equal(#duel.events, #asTeams.events)
        local chance = Arena.WinChance(teamA, teamB, "T-R#3")
        harness.truthy(chance > 0.5, "the team with the strong lead wins more: " .. chance)
    end,

    ["team arena: a team needs exactly 3 different companions of mine"] = function(harness)
        local addon = player(harness, "A-R", 100, 4)
        local Arena, team = addon.Arena, addon.team
        harness.truthy(Arena.Team({ team[1], team[2], team[3] }))
        harness.equal(select(2, Arena.Team({ team[1], team[2] })), "team")
        harness.equal(select(2, Arena.Team({ team[1], team[2], team[3], team[4] })), "team")
        harness.equal(select(2, Arena.Team({ team[1], team[1], team[2] })), "team", "no companion twice")
        harness.equal(select(2, Arena.Team({ team[1], team[2], "u999" })), "team", "not mine")
        harness.equal(Arena.MissingForTeam(), 0)
        local small = player(harness, "S-R", 100, 1)
        harness.equal(small.Arena.MissingForTeam(), 2)
    end,

    ["team arena: challenge and accept with teams; rewards go to every companion that entered; money adds up"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100, 3), ["B-R"] = player(harness, "B-R", 200, 4) }
        local A, B = players["A-R"], players["B-R"]
        local startA, startB = A.Wallet.Balance("A-R"), B.Wallet.Balance("B-R")
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW, A.team))
        local challenge = A.Arena.State().ch[id]
        harness.equal(#challenge.t, 3); harness.equal(challenge.f, nil)
        -- B sees A's whole team, picks its last three
        local fight = B.Arena.Fights(recordsFor(players, "B-R"), "B-R", NOW + 5)[id]
        harness.equal(#fight.ta, 3); harness.equal(fight.ta[3].atk, challenge.t[3].atk)
        local _, noTeam = B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 10, { B.team[2], B.team[3] })
        harness.equal(noTeam, "team")
        local pick = { B.team[4], B.team[3], B.team[2] }
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 10, pick))
        local fightTime = NOW + 10 + A.Arena.BET_WINDOW
        local resultA = A.Arena.Result(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id])
        local resultB = B.Arena.Result(B.Arena.Fights(recordsFor(players, "B-R"), "B-R", fightTime)[id])
        harness.equal(resultA.winner, resultB.winner); harness.equal(#resultA.events, #resultB.events)
        for _, name in ipairs({ "A-R", "B-R" }) do
            players[name].Arena.MarkWatched(id, fightTime)
            players[name].Arena.Settle(recordsFor(players, name), name, fightTime)
            players[name].Arena.Settle(recordsFor(players, name), name, fightTime + 5)
        end
        harness.equal(A.Wallet.Balance("A-R") + B.Wallet.Balance("B-R"), startA + startB, "nothing created or lost")
        -- XP: every companion that entered got the entry XP plus its knockouts; the bench got nothing
        local function check(addon, side, uids)
            local entered = resultA.entered[side]
            for slot, uid in ipairs(uids) do
                local progress = addon.Arena.Progress(addon.AzeCaught.Companion(uid))
                if slot <= entered then
                    harness.equal(progress.xp, addon.Arena.XP_ENTER + addon.Arena.XP_KNOCKOUT * resultA.knockouts[side][slot], side .. slot)
                    harness.equal(progress.w, resultA.knockouts[side][slot])
                else
                    harness.equal(progress.xp, 0, "never entered")
                end
            end
        end
        check(A, "a", A.team)
        check(B, "b", pick)
        harness.equal(B.Arena.Progress(B.AzeCaught.Companion(B.team[1])).xp, 0, "B's bench")
        harness.equal(A.Arena.State().w + A.Arena.State().l, 1, "one team fight on the player record")
    end,

    ["team arena: a counter offer brings the defender's team; the challenger accepts it"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW, A.team))
        assert(B.Arena.Counter(recordsFor(players, "B-R"), "B-R", id, 20000, NOW + 5, B.team))
        local fight = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 6)[id]
        harness.equal(#fight.counter.t, 3, "the challenger sees the counter team")
        assert(A.Arena.AnswerCounter(recordsFor(players, "A-R"), "A-R", id, true, NOW + 10))
        local open = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 11)[id]
        harness.equal(open.state, "open"); harness.equal(#open.tb, 3)
    end,

    ["team arena: different versions can neither challenge nor accept; a fight that turns mixed is void and refunded"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local startA, startB = A.Wallet.Balance("A-R"), B.Wallet.Balance("B-R")
        local records = recordsFor(players, "A-R")
        records["B-R"].arena.ver = "0.0.1"
        harness.equal(select(2, A.Arena.Challenge(records, "A-R", "B-R", 0, NOW, A.team)), "version")
        local same, theirs = A.Arena.SameVersion(records, "B-R")
        harness.equal(same, false); harness.equal(theirs, "0.0.1")
        records["B-R"].arena.ver = nil
        harness.equal(select(2, A.Arena.Challenge(records, "A-R", "B-R", 0, NOW, A.team)), "version", "an unknown version")
        -- same version: the challenge goes out and is accepted, then B updates before the fight
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW, A.team))
        local forB = recordsFor(players, "B-R")
        forB["A-R"].arena.ver = "9.9.9"
        harness.equal(select(2, B.Arena.Answer(forB, "B-R", id, true, NOW + 5, B.team)), "version")
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 5, B.team))
        local mixedA = recordsFor(players, "A-R")
        mixedA["B-R"].arena.ver = "9.9.9"
        local fight = A.Arena.Fights(mixedA, "A-R", NOW + 10)[id]
        harness.equal(fight.state, "version")
        local mixedB = recordsFor(players, "B-R")
        B.VERSION = "9.9.9"
        for _ = 1, 2 do
            A.Arena.Settle(mixedA, "A-R", NOW + 20)
            B.Arena.Settle(mixedB, "B-R", NOW + 20)
        end
        harness.equal(A.Wallet.Balance("A-R"), startA, "the challenger got its stake back once")
        harness.equal(B.Wallet.Balance("B-R"), startB, "the defender got its stake back once")
        harness.equal(A.Arena.State().w + A.Arena.State().l, 0, "no result")
    end,

    ["team arena: peer teams with 2, 4 or bad fighters are dropped; one-against-one leftovers are refunded once"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local Arena = addon.Arena
        local good = fighter()
        harness.truthy(Arena.SanitizeTeam({ good, good, good }))
        harness.equal(Arena.SanitizeTeam({ good, good }), nil)
        harness.equal(Arena.SanitizeTeam({ good, good, good, good }), nil)
        harness.equal(Arena.SanitizeTeam({ good, fighter({ atk = -5 }), good }), nil)
        harness.equal(Arena.SanitizeTeam({ [1] = good, [2] = good, [4] = good }), nil)
        harness.equal(Arena.SanitizeTeam("x"), nil)
        -- my own one-against-one challenge with a paid stake and an unanswered counter: void, the stakes come back once
        local loaded = addon.Store.Init({ schema = 3, games = {}, me = "A-R", caught = { collection = {}, arena = {
            ch = { ["A-R#100"] = { to = "B-R", at = 100, wg = 30000, f = good } },
            co = { ["C-R#90"] = { wg = 5000, at = 95, f = good } },
            settled = {} } } })
        harness.equal(loaded.caught.arena.legacyRefund, 35000)
        harness.equal(next(loaded.caught.arena.ch), nil)
        local before = addon.Wallet.Balance("A-R")
        addon.Arena.Settle({}, "A-R", NOW)
        addon.Arena.Settle({}, "A-R", NOW + 1)
        harness.equal(addon.Wallet.Balance("A-R"), before + 35000, "refunded once")
    end,

    ["team arena: the dummy fields a valid team of three in my version"] = function(harness)
        local addon = player(harness, "A-R", 100)
        local Arena = addon.Arena
        local mine = assert(Arena.Team(addon.team))
        local dummy = Arena.DummyRecord(mine, NOW)
        harness.truthy(Arena.SanitizeTeam(dummy.dummyTeam), "a valid team")
        harness.equal(dummy.arena.ver, addon.VERSION)
        local records = { [dummy.name] = dummy }
        local id = assert(Arena.Challenge(records, "A-R", dummy.name, 0, NOW, addon.team))
        harness.equal(Arena.DummyRespond(dummy, "A-R", NOW + 1), 1)
        local fight = Arena.Fights(records, "A-R", NOW + 2)[id]
        harness.equal(fight.state, "open"); harness.equal(#fight.tb, 3)
        harness.truthy(Arena.SanitizeSection(dummy.arena, dummy.name, math.huge), "the dummy's section is valid")
    end,
}
