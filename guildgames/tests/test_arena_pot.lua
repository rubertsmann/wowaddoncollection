-- Arena pot: both fighters set their own wager, the guild bets into one pot per fight, the winning side splits the
-- whole pot by share; late bets, the fighters' own bets, other versions and bets with old fixed odds stay out.
local NOW = 1794873600

local function player(harness, name, npc)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = name
    local entry = addon.AzeCaught.NoteFound({ npc = npc, name = "Npc" .. npc, level = 20, classification = "normal", stats = { type = 1 } }, NOW)
    entry.caught = 3
    assert(addon.AzeCaught.Select(npc, NOW))
    addon.team = {}
    for index, companion in ipairs(addon.AzeCaught.Roster()) do addon.team[index] = companion.uid end
    addon.Wallet.Earn(name, 2000 * 10000, "test", NOW)
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

local function balances(players)
    local list = {}
    for name, addon in pairs(players) do list[name] = addon.Wallet.Balance(name) end
    return list
end

-- A challenges B, B accepts with its own wager; returns the fight id and the fight time
local function acceptedFight(players, wagerA, wagerB, start)
    start = start or NOW
    local A, B = players["A-R"], players["B-R"]
    local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", wagerA, start, A.team))
    assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, start + 10, B.team, wagerB))
    return id, start + 10 + B.Arena.BET_WINDOW
end

local function settleAll(players, id, at)
    for name, addon in pairs(players) do
        addon.Arena.MarkWatched(id, at)
        addon.Arena.Settle(recordsFor(players, name), name, at)
        addon.Arena.Settle(recordsFor(players, name), name, at + 5)
    end
end

return {
    ["pot: the winning side gets its stakes back plus the losing side's total, split by share"] = function(harness)
        local Arena = harness.addon({ now = NOW }).Arena
        local fight = { a = "A-R", b = "B-R", wager = 10000, wagerB = 5000000, tb = {},
            bets = { ["C-R"] = { s = "a", c = 20000, at = NOW }, ["D-R"] = { s = "b", c = 10000, at = NOW },
                ["E-R"] = { s = "a", c = 90000, o = 200, at = NOW } } }
        local pot = Arena.Pot(fight)
        harness.equal(pot.a, 30000, "A's wager plus C's bet; E's bet with fixed odds stays out")
        harness.equal(pot.b, 5010000)
        harness.equal(Arena.Payout(pot, "a", "A-R"), 10000 + 1670000)
        harness.equal(Arena.Payout(pot, "a", "C-R"), 20000 + 3340000)
        harness.equal(Arena.Payout(pot, "a", "B-R"), 0, "the losing side loses everything")
        harness.equal(Arena.Payout(pot, "a", "E-R"), 0, "not in the pot")
        harness.equal(Arena.Payout(pot, "a", "A-R") + Arena.Payout(pot, "a", "C-R"), pot.a + pot.b, "the whole pot, nothing more")
        -- a lone 1g fighter against 500g takes 501g
        local alone = Arena.Pot({ a = "A-R", b = "B-R", wager = 10000, wagerB = 5000000, tb = {}, bets = {} })
        harness.equal(Arena.Payout(alone, "a", "A-R"), 5010000)
        -- rounding: three equal shares of 1 copper over never pay more than the pot
        local odd = Arena.Pot({ a = "A-R", b = "B-R", wager = 10000, wagerB = 10001, tb = {},
            bets = { ["C-R"] = { s = "a", c = 10000, at = NOW }, ["D-R"] = { s = "a", c = 10000, at = NOW } } })
        local paid = Arena.Payout(odd, "a", "A-R") + Arena.Payout(odd, "a", "C-R") + Arena.Payout(odd, "a", "D-R")
        harness.truthy(paid <= odd.a + odd.b and paid >= odd.a + odd.b - 3, "rounded down to copper: " .. paid)
        -- not accepted yet: an empty pot
        harness.equal(Arena.Pot({ a = "A-R", b = "B-R", wager = 10000, bets = {} }).a, 0)
    end,

    ["pot: wagers below 1g are refused on both sides, and the defender's own wager is in the fight"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local _, low = A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 9999, NOW, A.team)
        harness.equal(low, "wager")
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW, A.team))
        local _, none = B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 5, B.team, 0)
        harness.equal(none, "wager")
        harness.equal(B.Arena.Counter, nil, "counter offers are gone")
        local before = B.Wallet.Balance("B-R")
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 10, B.team, 70000))
        harness.equal(B.Wallet.Balance("B-R"), before - 70000, "B paid its own wager")
        local fight = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 20)[id]
        harness.equal(fight.wager, 10000); harness.equal(fight.wagerB, 70000)
    end,

    ["pot: fighters and the guild settle the same pot; no gold is created or lost; a late bet comes back"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200),
            ["C-R"] = player(harness, "C-R", 300), ["D-R"] = player(harness, "D-R", 400) }
        local A, C, D = players["A-R"], players["C-R"], players["D-R"]
        local start = balances(players)
        local id, fightTime = acceptedFight(players, 10000, 50000)
        local _, own = A.Arena.Bet(recordsFor(players, "A-R"), "A-R", id, "a", 5000, NOW + 20)
        harness.equal(own, "own", "fighters stake only through their wager")
        assert(C.Arena.Bet(recordsFor(players, "C-R"), "C-R", id, "a", 30000, NOW + 30))
        assert(D.Arena.Bet(recordsFor(players, "D-R"), "D-R", id, "b", 20000, NOW + 40))
        local _, twice = D.Arena.Bet(recordsFor(players, "D-R"), "D-R", id, "a", 20000, NOW + 41)
        harness.equal(twice, "twice")
        local pot = A.Arena.Pot(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id])
        harness.equal(pot.a, 40000); harness.equal(pot.b, 70000)
        local winner = A.Arena.Result(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id]).winner
        settleAll(players, id, fightTime)
        local now, total = balances(players), 0
        for name in pairs(players) do total = total + now[name] - start[name] end
        harness.truthy(total <= 0 and total >= -2, "the pot only moves gold between the players (rounded down to copper): " .. total)
        if winner == "a" then
            harness.equal(now["A-R"] - start["A-R"], 10000 + math.floor(70000 * 10000 / 40000) - 10000)
            harness.equal(now["C-R"] - start["C-R"], math.floor(70000 * 30000 / 40000))
            harness.equal(now["D-R"] - start["D-R"], -20000)
        else
            harness.equal(now["B-R"] - start["B-R"], math.floor(40000 * 50000 / 70000))
            harness.equal(now["D-R"] - start["D-R"], math.floor(40000 * 20000 / 70000))
            harness.equal(now["C-R"] - start["C-R"], -30000)
        end
        -- a bet stamped at the fight time (a dev late bet or a clock off) is not in the pot and comes back
        local id2, fightTime2 = acceptedFight(players, 10000, 10000, fightTime + 10)
        C.Wallet.Spend("C-R", 7000, "bet", fightTime2, id2)
        C.Arena.State().bt[id2] = { s = "a", c = 7000, at = fightTime2 }
        local fight2 = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime2)[id2]
        harness.equal(fight2.bets["C-R"], nil, "the late bet does not count")
        local beforeC = C.Wallet.Balance("C-R")
        C.Arena.MarkWatched(id2, fightTime2)
        local notices = C.Arena.Settle(recordsFor(players, "C-R"), "C-R", fightTime2)
        harness.equal(C.Wallet.Balance("C-R"), beforeC + 7000, "refunded")
        local refunded = false
        for _, notice in ipairs(notices) do if notice.kind == "refund" and notice.why == "late" then refunded = true end end
        harness.truthy(refunded, "a late-bet refund notice")
        C.Arena.Settle(recordsFor(players, "C-R"), "C-R", fightTime2 + 9)
        harness.equal(C.Wallet.Balance("C-R"), beforeC + 7000, "only once")
    end,

    ["pot: a bet from a player on another version stays out; a bet with old fixed odds is paid by its odds"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200),
            ["C-R"] = player(harness, "C-R", 300) }
        local A, C = players["A-R"], players["C-R"]
        local id, fightTime = acceptedFight(players, 10000, 10000)
        local records = recordsFor(players, "A-R")
        records["E-R"] = { name = "E-R", arena = { w = 0, l = 0, ver = "0.0.1", ch = {}, an = {}, co = {},
            bt = { [id] = { s = "a", c = 90000, at = NOW + 20 } } } }
        harness.equal(A.Arena.Fights(records, "A-R", NOW + 30)[id].bets["E-R"], nil, "another version's bet is ignored")
        -- C's bet from before the pot (fixed odds 2.00): paid 2x on a win, outside the pot
        C.Wallet.Spend("C-R", 10000, "bet", NOW + 20, id)
        C.Arena.State().bt[id] = { s = "a", c = 10000, o = 200, at = NOW + 20 }
        local fight = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id]
        harness.truthy(fight.bets["C-R"], "the bet is visible")
        harness.equal(A.Arena.Pot(fight).a, 10000, "but not in the pot")
        local before = C.Wallet.Balance("C-R")
        C.Arena.MarkWatched(id, fightTime)
        C.Arena.Settle(recordsFor(players, "C-R"), "C-R", fightTime)
        local won = A.Arena.Result(fight).winner == "a"
        harness.equal(C.Wallet.Balance("C-R") - before, won and 20000 or 0)
    end,

    ["pot: an accept from before the pot (no own wager) stakes the challenger's wager"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 30000, NOW, A.team))
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 10, B.team, 30000))
        B.Arena.State().an[id].wg = nil
        local fight = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 20)[id]
        harness.equal(fight.wagerB, 30000)
        harness.equal(A.Arena.Pot(fight).b, 30000)
    end,

    ["candidates: every other member is listed; other versions, fewer than 3 companions, busy and offline are greyed with the reason"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200), ["C-R"] = player(harness, "C-R", 300),
            ["D-R"] = player(harness, "D-R", 400) }
        local A = players["A-R"]
        local records = recordsFor(players, "A-R")
        harness.equal(records["B-R"].caught.rc, 3, "the record says how many companions they have")
        records["Old-R"] = { name = "Old-R", caught = { weeks = {} }, arena = { w = 0, l = 0, ver = "0.0.1" } }
        records["Few-R"] = { name = "Few-R", caught = { weeks = {}, rc = 2 }, arena = { w = 0, l = 0, ver = A.VERSION } }
        records["Away-R"] = { name = "Away-R", caught = { weeks = {}, rc = 5 }, arena = { w = 0, l = 0, ver = A.VERSION } }
        records["NoPet-R"] = { name = "NoPet-R" }
        -- C and D are in a fight
        local C, D = players["C-R"], players["D-R"]
        local id = assert(C.Arena.Challenge(recordsFor(players, "C-R"), "C-R", "D-R", 10000, NOW, C.team))
        assert(D.Arena.Answer(recordsFor(players, "D-R"), "D-R", id, true, NOW + 5, D.team, 10000))
        for name, record in pairs(recordsFor(players, "A-R")) do records[name] = record end
        local list = A.Arena.Candidates(records, "A-R", NOW + 10, function(name) if name == "Away-R" then return false end end)
        local byName = {}
        for index, entry in ipairs(list) do byName[entry.name] = entry; entry.index = index end
        harness.equal(byName["A-R"], nil, "not me"); harness.equal(byName["NoPet-R"], nil, "no companion record")
        harness.equal(byName["B-R"].reason, nil); harness.equal(byName["B-R"].index, 1, "the ones I can challenge come first")
        harness.equal(byName["Old-R"].reason, "version"); harness.equal(byName["Old-R"].version, "0.0.1")
        harness.equal(byName["Few-R"].reason, "fewcompanions")
        harness.equal(byName["C-R"].reason, "theybusy"); harness.equal(byName["D-R"].reason, "theybusy")
        harness.equal(byName["Away-R"].reason, "offline")
        -- a hostile companion count drops the section
        harness.equal(A.AzeCaught.SanitizeSection({ weeks = {}, rc = -1 }, math.huge), nil)
        harness.equal(A.AzeCaught.SanitizeSection({ weeks = {}, rc = 4 }, math.huge).rc, 4)
    end,

    ["dev events: fake bettors join the pot, a late fake bet stays out, fake fights expire and reveal, clear removes all"] = function(harness)
        local addon = player(harness, "A-R", 100)
        local Arena = addon.Arena
        local simulated = {}
        simulated[Arena.DUMMY_NAME] = Arena.DummyRecord(assert(Arena.Team(addon.team)), NOW)
        local function records() return simulated end
        -- my challenge to the dummy: it declines on the decline button, a second one it accepts with its own wager
        local first = assert(Arena.Challenge(records(), "A-R", Arena.DUMMY_NAME, 10000, NOW, addon.team))
        harness.equal(Arena.DevAnswer(simulated, "A-R", NOW + 1, false), 1)
        harness.equal(Arena.Fights(records(), "A-R", NOW + 2)[first].state, "declined")
        Arena.Settle(records(), "A-R", NOW + 3)
        local id = assert(Arena.Challenge(records(), "A-R", Arena.DUMMY_NAME, 10000, NOW + 10, addon.team))
        harness.equal(Arena.DevAnswer(simulated, "A-R", NOW + 11, true), 1)
        -- fake bettors on both sides, all in the pot; the late one is not
        harness.equal(select(2, Arena.DevCrowd(records(), simulated, "A-R", "nope", NOW + 12)), "closed")
        harness.equal(Arena.DevCrowd(records(), simulated, "A-R", id, NOW + 12), Arena.DEV_BETTORS)
        assert(Arena.DevLateBet(records(), simulated, "A-R", id, NOW + 12))
        local fight = Arena.Fights(records(), "A-R", NOW + 13)[id]
        harness.equal(addon.Utility.Count(fight.bets), Arena.DEV_BETTORS, "the late bet is not counted")
        local pot = Arena.Pot(fight)
        harness.truthy(pot.a > 10000 and pot.b > fight.wagerB, "bets on both sides")
        for name in pairs(simulated) do
            harness.truthy(Arena.SanitizeSection(simulated[name].arena, name, math.huge), "a valid fake section: " .. name)
        end
        -- greyed members
        Arena.DevMembers(simulated, NOW + 14)
        local reasons, pickable = {}, {}
        for _, entry in ipairs(Arena.Candidates(records(), "A-R", NOW + 15)) do
            if entry.reason then reasons[entry.reason] = true else pickable[entry.name] = true end
        end
        harness.truthy(reasons.version and reasons.fewcompanions and reasons.theybusy and reasons.offline, "every reason")
        harness.truthy(pickable[Arena.DEV_SPARRING], "one fake member can be challenged")
        -- reveal: the decided, unwatched fight settles at once
        local fightTime = NOW + 11 + Arena.BET_WINDOW
        harness.equal(Arena.DevShift(records(), simulated, "A-R", fightTime, "reveal"), 1)
        Arena.Settle(records(), "A-R", fightTime)
        harness.equal(Arena.State().w + Arena.State().l, 1, "settled without watching")
        -- expire: a waiting challenge to a fake member is refunded at once
        local waiting = assert(Arena.Challenge(records(), "A-R", "Fewpets-Test", 10000, fightTime + 10, addon.team))
        local before = addon.Wallet.Balance("A-R")
        harness.equal(Arena.DevShift(records(), simulated, "A-R", fightTime + 11, "expire"), 1)
        Arena.Settle(records(), "A-R", fightTime + 12)
        harness.equal(addon.Wallet.Balance("A-R"), before + 10000, "the stake came back")
        harness.equal(Arena.Fights(records(), "A-R", fightTime + 12)[waiting].state, "expired")
        -- the sparring member answers like the dummy: on its own after the delay, with its own wager
        local sparring = assert(Arena.Challenge(records(), "A-R", Arena.DEV_SPARRING, 30000, fightTime + 20, addon.team))
        harness.equal(Arena.DummyRespond(simulated[Arena.DEV_SPARRING], "A-R", fightTime + 20 + Arena.DUMMY_DELAY), 1)
        local open = Arena.Fights(records(), "A-R", fightTime + 21 + Arena.DUMMY_DELAY)[sparring]
        harness.equal(open.state, "open"); harness.equal(open.wagerB, Arena.DummyWager(sparring, 30000))
        harness.equal(#Arena.DevResponders(simulated), 2, "the dummy and the sparring member answer")
        -- clear
        harness.truthy(Arena.DevClear(simulated) > 0)
        harness.equal(next(simulated), nil, "nothing fake is left")
        harness.equal(next(Arena.devShift), nil); harness.equal(next(Arena.devOffline), nil)
    end,
}
