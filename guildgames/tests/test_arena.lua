-- Companion arena: fighters, training, levels, the deterministic battle, odds, the record section and
-- the challenge / answer / bet / settle flow between two (three) simulated players exchanging records.
local NOW = 1794873600   -- 2026-11-17 00:00 UTC

-- a player with three caught companions of `npc` (beast unless `typeID`), the first active; `addon.team` holds their
-- uids, and Challenge / Answer / Counter use that team unless a test passes its own
local function player(harness, name, npc, typeID, level)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = name
    local AzeCaught = addon.AzeCaught
    local entry = AzeCaught.NoteFound({ npc = npc, name = "Npc" .. npc, level = level or 20, classification = "normal",
        stats = { type = typeID or 1 } }, NOW)
    entry.caught = 3
    assert(AzeCaught.Select(npc, NOW))
    addon.team = {}
    for index, companion in ipairs(AzeCaught.Roster()) do addon.team[index] = companion.uid end
    local Arena = addon.Arena
    for _, action in ipairs({ "Challenge", "Answer", "Counter" }) do
        local original = Arena[action]
        Arena[action] = function(records, myName, first, second, now, uids)
            return original(records, myName, first, second, now, uids or addon.team)
        end
    end
    return addon
end

-- what `owner`'s record looks like to everybody else (the wire: sanitized section)
local function recordOf(addon, owner)
    local AzeCaught, Arena = addon.AzeCaught, addon.Arena
    local section = Arena.SanitizeSection(Arena.BuildSection(), owner, math.huge)
    assert(section, "my own section must survive validation")
    return { name = owner, caught = AzeCaught.BuildSection(), arena = section }
end

-- the records `viewer` holds: everybody else's
local function recordsFor(players, viewer)
    local records = {}
    for name, addon in pairs(players) do if name ~= viewer then records[name] = recordOf(addon, name) end end
    return records
end

local function balance(addon, name) return addon.Wallet.Balance(name) end

local function fighter(overrides)
    local base = { npc = 1, n = "A", cls = "normal", disp = 0, ty = 1, al = 1, atk = 50, def = 50, spd = 50, vit = 50, ab = "strike" }
    for key, value in pairs(overrides or {}) do base[key] = value end
    return base
end

return {
    ["arena: levels need n x 50 XP; training costs grow, take energy and active time, and raise one stat"] = function(harness)
        local addon = player(harness, "A-R", 100)
        local Arena, AzeCaught = addon.Arena, addon.AzeCaught
        harness.equal(Arena.Level(0), 1); harness.equal(Arena.Level(49), 1); harness.equal(Arena.Level(50), 2)
        local level, into, needed = Arena.Level(160)   -- 50 + 100 = 150 -> level 3, 10 into 150
        harness.equal(level, 3); harness.equal(into, 10); harness.equal(needed, 150)
        harness.equal(Arena.Level(1e9), Arena.MAXIMUM_LEVEL)
        local before = Arena.Fighter(AzeCaught.Active())
        local money = balance(addon, "A-R")
        assert(Arena.Train("A-R", "atk", NOW))
        harness.equal(balance(addon, "A-R"), money - Arena.TrainCost(0))
        harness.equal(AzeCaught.Active().energy, 100 - Arena.TRAIN_ENERGY)
        local busy, reason = Arena.Train("A-R", "def", NOW)
        harness.equal(busy, nil); harness.equal(reason, "busy")
        harness.equal(Arena.FinishTraining(), nil, "not yet")
        AzeCaught.State().activeSeconds = AzeCaught.State().activeSeconds + Arena.TRAIN_SECONDS
        local done = assert(Arena.FinishTraining())
        harness.equal(done.stat, "atk"); harness.equal(done.points, 1)
        harness.equal(Arena.FinishTraining(), nil, "once")
        local after = Arena.Fighter(AzeCaught.Active())
        harness.truthy(after.atk > before.atk and after.def == before.def, "only attack rose")
        harness.equal(Arena.TrainCost(1), 2 * Arena.TRAIN_COST)
        local _, unknown = Arena.Train("A-R", "luck", NOW); harness.equal(unknown, "stat")
        AzeCaught.Active().energy = 5
        local _, tired = Arena.Train("A-R", "def", NOW); harness.equal(tired, "energy")
        -- a level makes every stat stronger; hunger weakens the attack
        AzeCaught.Active().energy = 100
        Arena.Progress(AzeCaught.Active()).xp = 50 * 10
        local leveled = Arena.Fighter(AzeCaught.Active())
        harness.truthy(leveled.def > after.def and leveled.al > 1)
        AzeCaught.Active().zones.hunger = "needy"
        harness.truthy(Arena.Fighter(AzeCaught.Active()).atk < leveled.atk, "hungry: weaker attack")
    end,

    ["arena: the battle is deterministic, uses abilities, and the stronger fighter usually wins"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local Arena = addon.Arena
        local a, b = fighter({ ab = "rend" }), fighter({ npc = 2, n = "B", ab = "barrier" })
        local first, second = Arena.Fight(a, b, "X-R#1"), Arena.Fight(a, b, "X-R#1")
        harness.equal(first.winner, second.winner); harness.equal(#first.events, #second.events)
        for index, event in ipairs(first.events) do
            harness.equal(event.k, second.events[index].k); harness.equal(event.d, second.events[index].d)
        end
        local kinds = {}
        for _, event in ipairs(first.events) do kinds[event.ab or event.k] = true end
        harness.truthy(kinds.rend and kinds.barrier, "both abilities were used")
        harness.truthy(first.events[#first.events].ha >= 0 and first.events[#first.events].hb >= 0)
        local strong = fighter({ npc = 3, atk = 120, def = 120, spd = 70, vit = 120 })
        local chance = Arena.WinChance(strong, b, "X-R#2")
        harness.truthy(chance > 0.8, "strong wins most: " .. chance)
        harness.truthy(Arena.WinChance(a, b, "X-R#3") > 0.1 and Arena.WinChance(a, b, "X-R#3") < 0.9, "even fight is open")
        -- every ability runs without error
        for ability in pairs(Arena.ABILITIES) do
            local result = Arena.Fight(fighter({ ab = ability }), fighter({ npc = 2, ab = ability }), "X-R#" .. ability)
            harness.truthy(result.winner == "a" or result.winner == "b", ability)
        end
        -- odds: 0.95 / chance in hundredths, bounded
        harness.equal(Arena.Odds(0.5), 190); harness.equal(Arena.Odds(0.99), 110); harness.equal(Arena.Odds(0.01), 1000)
        harness.equal(Arena.Odds(0), 1000)
    end,

    -- balance: with equal stats no ability wins much more than half its fights, and a mirror match is even
    ["arena: abilities are balanced (each wins 35..65% against all others with equal stats)"] = function(harness)
        local Arena = harness.addon({ now = NOW }).Arena
        local names = {}
        for ability in pairs(Arena.ABILITIES) do names[#names + 1] = ability end
        table.sort(names)
        local mirror = 0
        for _, ability in ipairs(names) do
            local total = 0
            for _, other in ipairs(names) do
                local chance = Arena.WinChance(fighter({ ty = 0, atk = 100, def = 100, spd = 100, vit = 100, ab = ability }),
                    fighter({ npc = 2, ty = 0, atk = 100, def = 100, spd = 100, vit = 100, ab = other }), ability .. "-" .. other)
                total = total + chance
                if ability == other then mirror = mirror + chance end
            end
            local average = total / #names
            harness.truthy(average > 0.35 and average < 0.65, ability .. " wins " .. average)
        end
        mirror = mirror / #names
        harness.truthy(mirror > 0.4 and mirror < 0.6, "the challenger has no edge in mirror matches: " .. mirror)
    end,

    ["arena: challenge, accept, bets and settlement pay each player once; the winner takes both stakes"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100, 1), ["B-R"] = player(harness, "B-R", 200, 6), ["C-R"] = player(harness, "C-R", 300, 7) }
        local A, B, C = players["A-R"], players["B-R"], players["C-R"]
        local wager = 10000
        local startA, startB, startC = balance(A, "A-R"), balance(B, "B-R"), balance(C, "C-R")
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", wager, NOW))
        harness.equal(balance(A, "A-R"), startA - wager, "the stake left at once")
        local _, twice = A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", wager, NOW + 1)
        harness.equal(twice, "busy", "one fight at a time")
        -- B sees the challenge (a notice once), C cannot answer it
        local notices = B.Arena.Settle(recordsFor(players, "B-R"), "B-R", NOW + 10)
        harness.equal(#notices, 1); harness.equal(notices[1].kind, "challenged")
        harness.equal(#B.Arena.Settle(recordsFor(players, "B-R"), "B-R", NOW + 11), 0, "noticed once")
        local _, notMine = C.Arena.Answer(recordsFor(players, "C-R"), "C-R", id, true, NOW + 20)
        harness.equal(notMine, "unknown")
        -- C cannot bet before the accept
        local _, closed = C.Arena.Bet(recordsFor(players, "C-R"), "C-R", id, "a", 5000, NOW + 20)
        harness.equal(closed, "closed")
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 30))
        harness.equal(balance(B, "B-R"), startB - wager)
        -- C bets now; A cannot bet on its own fight
        local odds = assert(C.Arena.Bet(recordsFor(players, "C-R"), "C-R", id, "b", 5000, NOW + 40))
        harness.truthy(odds >= 110 and odds <= 1000)
        local _, own = A.Arena.Bet(recordsFor(players, "A-R"), "A-R", id, "a", 5000, NOW + 40)
        harness.equal(own, "own")
        local fights = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 50)
        harness.equal(fights[id].state, "open"); harness.truthy(fights[id].bets["C-R"], "everyone sees C's bet")
        -- after the fight time every client computes the same winner
        local fightTime = NOW + 30 + 300
        local resultA = A.Arena.Result(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id])
        local resultB = B.Arena.Result(B.Arena.Fights(recordsFor(players, "B-R"), "B-R", fightTime)[id])
        harness.equal(resultA.winner, resultB.winner)
        local winner = resultA.winner
        -- decided, but nobody watched yet: no money, no W/L, a "ready" notice once each
        local readyA = A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime)
        local readyC = C.Arena.Settle(recordsFor(players, "C-R"), "C-R", fightTime)
        local function kinds(notices)
            local list = {}
            for _, entry in ipairs(notices) do list[#list + 1] = entry.kind end
            table.sort(list)
            return table.concat(list, ",")
        end
        harness.equal(kinds(readyA), "answered,ready", "A: the accept and the ready fight, no result")
        harness.equal(kinds(readyC), "betready")
        harness.equal(#A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime + 1), 0, "ready noticed once")
        harness.equal(balance(A, "A-R"), startA - wager, "nothing paid before watching")
        harness.equal(A.Arena.State().w + A.Arena.State().l, 0, "no result before watching")
        A.Arena.MarkWatched(id, fightTime); B.Arena.MarkWatched(id, fightTime); C.Arena.MarkWatched(id, fightTime)
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime)
        B.Arena.Settle(recordsFor(players, "B-R"), "B-R", fightTime)
        C.Arena.Settle(recordsFor(players, "C-R"), "C-R", fightTime)
        -- settling again changes nothing
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime + 5)
        B.Arena.Settle(recordsFor(players, "B-R"), "B-R", fightTime + 5)
        C.Arena.Settle(recordsFor(players, "C-R"), "C-R", fightTime + 5)
        if winner == "a" then
            harness.equal(balance(A, "A-R"), startA + wager); harness.equal(balance(B, "B-R"), startB - wager)
            harness.equal(balance(C, "C-R"), startC - 5000, "C bet on b and lost")
            harness.equal(A.Arena.State().w, 1); harness.equal(B.Arena.State().l, 1)
        else
            harness.equal(balance(A, "A-R"), startA - wager); harness.equal(balance(B, "B-R"), startB + wager)
            harness.equal(balance(C, "C-R"), startC - 5000 + math.floor(5000 * odds / 100))
            harness.equal(B.Arena.State().w, 1); harness.equal(A.Arena.State().l, 1)
        end
        harness.equal(#A.Arena.State().history, 1); harness.equal(#B.Arena.State().history, 1)
        harness.truthy(A.Arena.Progress(A.AzeCaught.Companion(A.team[1])).xp > 0 and B.Arena.Progress(B.AzeCaught.Companion(B.team[1])).xp > 0, "both gained XP")
    end,

    ["arena: a decline or an expired challenge refunds once; a lapsed one waits for a late answer"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local start = balance(A, "A-R")
        local declined = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 20000, NOW))
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", declined, false, NOW + 5))
        harness.equal(balance(B, "B-R"), 200000, "a decline costs nothing")
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", NOW + 10)
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", NOW + 20)
        harness.equal(balance(A, "A-R"), start, "refunded once")
        local unanswered = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 30000, NOW + 100))
        local lapsed = NOW + 100 + A.Arena.CHALLENGE_TTL + 10
        harness.equal(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", lapsed)[unanswered].state, "lapsed")
        local _, late = B.Arena.Answer(recordsFor(players, "B-R"), "B-R", unanswered, true, lapsed)
        harness.equal(late, "late")
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", lapsed)
        harness.equal(balance(A, "A-R"), start - 30000, "no refund while an answer may still arrive")
        local expired = lapsed + A.Arena.ANSWER_GRACE
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", expired)
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", expired + 1)
        harness.equal(balance(A, "A-R"), start)
        -- old entries leave the record later
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", expired + A.Arena.KEEP_SECONDS + 10)
        harness.equal(next(A.Arena.State().ch), nil)
    end,

    ["arena: hostile sections are dropped alone; answers from others and foreign challenges do not count"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local Arena = addon.Arena
        local good = { npc = 1, n = "Wolf", cls = "normal", disp = 0, ty = 1, al = 1, atk = 5, def = 5, spd = 5, vit = 5, ab = "rend" }
        local function with(changes)
            local f = {}
            for key, value in pairs(good) do f[key] = value end
            for key, value in pairs(changes) do f[key] = value end
            return f
        end
        local okSection = { w = 1, l = 2, ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = 0, t = { good, good, good } } } }
        harness.truthy(Arena.SanitizeSection(okSection, "Me-R", 1e10))
        harness.equal(Arena.SanitizeSection(okSection, "Other-R", 1e10), nil, "a challenge in someone else's name")
        for _, bad in ipairs({
            { ch = { ["Me-R#10"] = { to = "You-R", at = 11, wg = 0, t = { good, good, good } } } },            -- id time mismatch
            { ch = { ["Me-R#10"] = { to = "Me-R", at = 10, wg = 0, t = { good, good, good } } } },             -- self
            { ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = -1, t = { good, good, good } } } },
            { ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = 0, t = { good, with{ atk = 1e12 }, good } } } },
            { ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = 0, t = { good, with{ ab = "nuke" }, good } } } },
            { ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = 0, t = { good, with{ n = "x\124cffff0000y" .. string.rep("z", 60) }, good } } } },
            { an = { ["You-R#5"] = { ok = true, at = 6 } } },                                    -- accepted without a team
            { ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = 0, t = { good, good } } } },    -- two fighters
            { ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = 0, t = { good, good, good, good } } } },
            { ch = { ["Me-R#10"] = { to = "You-R", at = 10, wg = 0, f = good } } },            -- a one-against-one challenge
            { bt = { ["You-R#5"] = { s = "c", c = 5000, o = 200, at = 6 } } },
            { bt = { ["You-R#5"] = { s = "a", c = 5000, o = 5000, at = 6 } } },
            { w = -1 }, { ch = "x" }, "x",
        }) do
            harness.equal(Arena.SanitizeSection(bad, "Me-R", 1e10), nil)
        end
        -- an answer by a third player for someone else's fight is ignored
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200), ["C-R"] = player(harness, "C-R", 300) }
        local A = players["A-R"]
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 0, NOW))
        players["C-R"].Arena.State().an[id] = { ok = true, at = NOW + 5, t = { good, good, good } }
        harness.equal(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 10)[id].state, "pending")
        -- a record with an invalid arena section keeps the rest (dropped alone)
        local record = { name = "B-R", rev = 5, total = { won = 0, lost = 0, wins = 0, losses = 0 }, weeks = {}, recent = {}, arena = { w = "x" } }
        local clean = addon.Games.Sanitize(record)
        harness.truthy(clean and clean.arena == nil, "dropped alone")
    end,

    ["arena: the local state survives a reload and is repaired when edited"] = function(harness)
        local A = player(harness, "A-R", 100)
        local active = A.AzeCaught.Active()
        A.Arena.Progress(active).tr.atk = 3
        A.Arena.Progress(active).xp = 120
        A.Arena.State().history = { { id = "A-R#1", opp = "B-R", me = "Npc100", them = "Wolf", won = true, wg = 5, t = NOW } }
        A.Arena.State().training = { stat = "def", uid = active.uid, done = 50 }
        local loaded = harness.addon({ now = NOW }).Store.Init({ schema = 3, games = {}, me = "A-R", caught = A.AzeCaught.State() })
        local arena = loaded.caught.arena
        local reloaded = loaded.caught.roster[active.uid]
        harness.equal(reloaded.ar.tr.atk, 3); harness.equal(reloaded.ar.xp, 120)
        harness.equal(#arena.history, 1); harness.equal(arena.training.stat, "def"); harness.equal(arena.training.uid, active.uid)
        harness.truthy(loaded.caught.active == reloaded, "the active companion is the roster entry")
        local broken = harness.addon({ now = NOW }).Store.Init({ schema = 3, games = {}, me = "A-R",
            caught = { collection = {}, roster = { u1 = { npc = 5 } }, arena = { training = { stat = "atk", uid = "u9", done = 1 },
                ch = { bad = 1 }, history = "x" } } })
        local repaired = broken.caught.arena
        harness.equal(next(broken.caught.roster), nil, "a companion without a collection entry is dropped")
        harness.equal(repaired.training, nil, "a training of a companion that is not there")
        harness.equal(next(repaired.ch), nil)
    end,

    ["arena: the dev dummy accepts my challenge, fights and pays once; its challenge comes in; a vanished record never refunds a settled fight"] = function(harness)
        local addon = player(harness, "A-R", 100)
        local Arena, AzeCaught = addon.Arena, addon.AzeCaught
        local dummy = Arena.DummyRecord(Arena.Fighter(AzeCaught.Active()), NOW)
        harness.equal(dummy.name, Arena.DUMMY_NAME)
        harness.truthy(addon.Utility.IsSafeName(dummy.name))
        harness.truthy(Arena.SanitizeTeam(dummy.dummyTeam), "the dummy's team is valid")
        harness.truthy(AzeCaught.SanitizeSection(dummy.caught, math.huge), "the dummy's companion is valid")
        local records = { [dummy.name] = dummy }
        local start = balance(addon, "A-R")
        local id = assert(Arena.Challenge(records, "A-R", dummy.name, 10000, NOW))
        harness.equal(Arena.DummyRespond(dummy, "A-R", NOW + 5), 1)
        harness.equal(Arena.DummyRespond(dummy, "A-R", NOW + 6), 0, "answers once")
        harness.equal(Arena.Fights(records, "A-R", NOW + 10)[id].state, "open")
        -- dev skip: only dummy fights, decided at once (then the normal flow; reset for the rest of the test)
        harness.equal(Arena.SkipDummyWait(records, "A-R", NOW + 20), 1)
        harness.equal(Arena.Fights(records, "A-R", NOW + 20)[id].state, "done")
        Arena.skipped[id] = nil
        local fightTime = NOW + 5 + Arena.BET_WINDOW
        Arena.MarkWatched(id, fightTime)
        Arena.Settle(records, "A-R", fightTime)
        local won = Arena.State().w == 1
        harness.equal(Arena.State().w + Arena.State().l, 1)
        harness.equal(balance(addon, "A-R"), won and start + 10000 or start - 10000)
        -- the dummy is gone (a reload): the challenge looks unanswered and expires, but the fight was settled: no refund
        local late = NOW + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE + 10
        local notices = Arena.Settle({}, "A-R", late)
        for _, notice in ipairs(notices) do harness.truthy(notice.kind ~= "refund", "no refund after a settled fight") end
        harness.equal(balance(addon, "A-R"), won and start + 10000 or start - 10000)
        -- the dummy challenges me: an incoming fight I can accept
        local later = fightTime + 100
        local incoming = Arena.DummyChallenge(dummy, "A-R", 5000, later)
        local fight = Arena.Fights(records, "A-R", later + 1)[incoming]
        harness.equal(fight.state, "pending"); harness.equal(fight.b, "A-R"); harness.equal(fight.wager, 5000)
        harness.truthy(Arena.SanitizeSection(dummy.arena, dummy.name, math.huge), "the dummy's section is valid")
        assert(Arena.Answer(records, "A-R", incoming, true, later + 2))
        harness.equal(Arena.Fights(records, "A-R", later + 3)[incoming].state, "open")
    end,

    ["arena: one fight at a time on both sides; a stopped challenge refunds both once, an accept from before the stop still counts"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200), ["C-R"] = player(harness, "C-R", 300) }
        local A, B, C = players["A-R"], players["B-R"], players["C-R"]
        local wager = 10000
        local startA, startB = balance(A, "A-R"), balance(B, "B-R")
        local first = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", wager, NOW))
        -- the requesting side: no second challenge while mine waits
        local _, busy = A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "C-R", 0, NOW + 1)
        harness.equal(busy, "busy")
        -- the accepting side: C challenges A, A cannot accept while A's own challenge waits
        local fromC = assert(C.Arena.Challenge(recordsFor(players, "C-R"), "C-R", "A-R", 0, NOW + 2))
        local _, acceptBusy = A.Arena.Answer(recordsFor(players, "A-R"), "A-R", fromC, true, NOW + 3)
        harness.equal(acceptBusy, "busy")
        harness.truthy(A.Arena.Answer(recordsFor(players, "A-R"), "A-R", fromC, false, NOW + 3), "a decline is always possible")
        -- A stops the first challenge: refunded once, B can no longer accept
        assert(A.Arena.Withdraw(recordsFor(players, "A-R"), "A-R", first, NOW + 10))
        local _, again = A.Arena.Withdraw(recordsFor(players, "A-R"), "A-R", first, NOW + 11)
        harness.equal(again, "late")
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", NOW + 12)
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", NOW + 13)
        harness.equal(balance(A, "A-R"), startA, "refunded once")
        local _, late = B.Arena.Answer(recordsFor(players, "B-R"), "B-R", first, true, NOW + 20)
        harness.equal(late, "late")
        harness.equal(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 20)[first].state, "withdrawn")
        -- a free player can challenge again; B, in an open fight, is busy for others
        local second = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", wager, NOW + 30))
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", second, true, NOW + 40))
        local _, theyBusy = C.Arena.Challenge(recordsFor(players, "C-R"), "C-R", "B-R", 0, NOW + 50)
        harness.equal(theyBusy, "theybusy")
        local _, stopOpen = A.Arena.Withdraw(recordsFor(players, "A-R"), "A-R", second, NOW + 50)
        harness.equal(stopOpen, "late", "an accepted fight cannot be stopped")
        -- after the fight everyone is free again; the money adds up
        local fightTime = NOW + 40 + 300
        A.Arena.MarkWatched(second, fightTime); B.Arena.MarkWatched(second, fightTime)
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime)
        B.Arena.Settle(recordsFor(players, "B-R"), "B-R", fightTime)
        harness.equal(balance(A, "A-R") + balance(B, "B-R"), startA + startB, "nothing created or lost")
        harness.truthy(C.Arena.Challenge(recordsFor(players, "C-R"), "C-R", "B-R", 0, fightTime + 1), "B is free after the fight")
    end,

    ["arena: an accept made before the stop but synced after the refund still counts, and the refund is undone"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local wager = 10000
        local startA, startB = balance(A, "A-R"), balance(B, "B-R")
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", wager, NOW))
        local recordsOfB = recordsFor(players, "B-R")   -- B accepts before seeing the stop
        assert(A.Arena.Withdraw(recordsFor(players, "A-R"), "A-R", id, NOW + 20))
        A.Arena.Settle({}, "A-R", NOW + 21)              -- A has not seen the accept yet: refund
        harness.equal(balance(A, "A-R"), startA)
        assert(B.Arena.Answer(recordsOfB, "B-R", id, true, NOW + 10))
        local fightTime = NOW + 10 + 300
        harness.equal(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id].state, "done", "the accept was first")
        A.Arena.MarkWatched(id, fightTime); B.Arena.MarkWatched(id, fightTime)
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime)
        B.Arena.Settle(recordsFor(players, "B-R"), "B-R", fightTime)
        harness.equal(balance(A, "A-R") + balance(B, "B-R"), startA + startB, "the refund was undone")
        harness.equal(A.Arena.State().w + A.Arena.State().l, 1)
    end,

    ["arena: an unwatched fight settles by itself after REVEAL_AFTER; watched state survives a reload"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local startA, startB = balance(A, "A-R"), balance(B, "B-R")
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW))
        assert(B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 10))
        local fightTime = NOW + 10 + A.Arena.BET_WINDOW
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime)
        harness.equal(A.Arena.State().w + A.Arena.State().l, 0)
        local fight = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id]
        harness.equal(A.Arena.Revealed(fight, fightTime), false)
        harness.equal(A.Arena.Revealed(fight, fightTime + A.Arena.REVEAL_AFTER), true)
        A.Arena.Settle(recordsFor(players, "A-R"), "A-R", fightTime + A.Arena.REVEAL_AFTER)
        B.Arena.Settle(recordsFor(players, "B-R"), "B-R", fightTime + A.Arena.REVEAL_AFTER)
        harness.equal(A.Arena.State().w + A.Arena.State().l, 1, "settled without watching")
        harness.equal(balance(A, "A-R") + balance(B, "B-R"), startA + startB)
        -- watched marks are kept over a reload and garbage is dropped
        A.Arena.MarkWatched("X-R#1", NOW)
        local caught = A.AzeCaught.State()
        caught.arena.watched["bad"] = "x"
        harness.truthy(A.Arena.SanitizePersisted(caught, "A-R"), "repaired")
        harness.equal(caught.arena.watched["X-R#1"], NOW); harness.equal(caught.arena.watched["bad"], nil)
    end,

    ["arena: a counter offer (higher or lower) accepted by the challenger fights with the new wager; money adds up"] = function(harness)
        for _, counterWager in ipairs({ 30000, 4000 }) do
            local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200), ["C-R"] = player(harness, "C-R", 300) }
            local A, B, C = players["A-R"], players["B-R"], players["C-R"]
            local startA, startB = balance(A, "A-R"), balance(B, "B-R")
            local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW))
            local _, same = B.Arena.Counter(recordsFor(players, "B-R"), "B-R", id, 10000, NOW + 5)
            harness.equal(same, "same")
            local _, notMine = C.Arena.Counter(recordsFor(players, "C-R"), "C-R", id, 5000, NOW + 5)
            harness.equal(notMine, "unknown")
            assert(B.Arena.Counter(recordsFor(players, "B-R"), "B-R", id, counterWager, NOW + 10))
            harness.equal(balance(B, "B-R"), startB - counterWager, "the counter stake left at once")
            local _, twice = B.Arena.Counter(recordsFor(players, "B-R"), "B-R", id, 20000, NOW + 11)
            harness.equal(twice, "answered")
            local _, noAccept = B.Arena.Answer(recordsFor(players, "B-R"), "B-R", id, true, NOW + 11)
            harness.equal(noAccept, "answered", "after a counter the original cannot be accepted")
            -- A sees the counter (notice once), both are busy, nobody can bet yet
            local notices = A.Arena.Settle(recordsFor(players, "A-R"), "A-R", NOW + 20)
            harness.equal(#notices, 1); harness.equal(notices[1].kind, "countered"); harness.equal(notices[1].wager, counterWager)
            local fights = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 20)
            harness.equal(fights[id].state, "countered")
            harness.equal(A.Arena.Busy(fights, "A-R", true), id); harness.equal(A.Arena.Busy(fights, "B-R", true), id)
            local _, closed = C.Arena.Bet(recordsFor(players, "C-R"), "C-R", id, "a", 5000, NOW + 20)
            harness.equal(closed, "closed")
            local _, notB = B.Arena.AnswerCounter(recordsFor(players, "B-R"), "B-R", id, true, NOW + 25)
            harness.equal(notB, "unknown", "only the challenger answers a counter")
            assert(A.Arena.AnswerCounter(recordsFor(players, "A-R"), "A-R", id, true, NOW + 30))
            harness.equal(balance(A, "A-R"), startA - counterWager, "the difference was paid or given back")
            local open = A.Arena.Fights(recordsFor(players, "A-R"), "A-R", NOW + 40)[id]
            harness.equal(open.state, "open"); harness.equal(open.wager, counterWager); harness.equal(open.fightAt, NOW + 30 + A.Arena.BET_WINDOW)
            local notifyB = B.Arena.Settle(recordsFor(players, "B-R"), "B-R", NOW + 40)
            harness.equal(#notifyB, 1); harness.equal(notifyB[1].kind, "counteranswered"); harness.equal(notifyB[1].accepted, true)
            assert(C.Arena.Bet(recordsFor(players, "C-R"), "C-R", id, "a", 5000, NOW + 50), "bets open after the counter was accepted")
            -- every client computes the same fight from the counter's fighter
            local fightTime = NOW + 30 + A.Arena.BET_WINDOW
            local resultA = A.Arena.Result(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", fightTime)[id])
            local resultC = C.Arena.Result(C.Arena.Fights(recordsFor(players, "C-R"), "C-R", fightTime)[id])
            harness.equal(resultA.winner, resultC.winner); harness.equal(#resultA.events, #resultC.events)
            for _, name in ipairs({ "A-R", "B-R" }) do
                players[name].Arena.MarkWatched(id, fightTime)
                players[name].Arena.Settle(recordsFor(players, name), name, fightTime)
                players[name].Arena.Settle(recordsFor(players, name), name, fightTime + 5)
            end
            harness.equal(balance(A, "A-R") + balance(B, "B-R"), startA + startB, "nothing created or lost (" .. counterWager .. ")")
            local winnerA = resultA.winner == "a"
            harness.equal(balance(A, "A-R"), winnerA and startA + counterWager or startA - counterWager, "the countered wager was at stake")
        end
    end,

    ["arena: a declined, stopped or expired counter offer refunds both stakes once"] = function(harness)
        for _, ending in ipairs({ "declined", "stopped", "expired" }) do
            local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
            local A, B = players["A-R"], players["B-R"]
            local startA, startB = balance(A, "A-R"), balance(B, "B-R")
            local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW))
            assert(B.Arena.Counter(recordsFor(players, "B-R"), "B-R", id, 25000, NOW + 10))
            local finish = NOW + 30
            if ending == "declined" then
                assert(A.Arena.AnswerCounter(recordsFor(players, "A-R"), "A-R", id, false, NOW + 20))
                harness.equal(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", finish)[id].state, "rejected")
            elseif ending == "stopped" then
                assert(A.Arena.Withdraw(recordsFor(players, "A-R"), "A-R", id, NOW + 20))
                harness.equal(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", finish)[id].state, "withdrawn")
            else
                local lateAnswer = NOW + 10 + A.Arena.CHALLENGE_TTL + 5
                local _, late = A.Arena.AnswerCounter(recordsFor(players, "A-R"), "A-R", id, true, lateAnswer)
                harness.equal(late, "late")
                finish = NOW + 10 + A.Arena.CHALLENGE_TTL + A.Arena.ANSWER_GRACE + 5
                harness.equal(A.Arena.Fights(recordsFor(players, "A-R"), "A-R", finish)[id].state, "expired")
            end
            for _ = 1, 2 do
                A.Arena.Settle(recordsFor(players, "A-R"), "A-R", finish)
                B.Arena.Settle(recordsFor(players, "B-R"), "B-R", finish)
            end
            harness.equal(balance(A, "A-R"), startA, ending .. ": the challenger got its stake back once")
            harness.equal(balance(B, "B-R"), startB, ending .. ": the counter stake came back once")
        end
    end,

    ["arena: counter sections from peers are validated; a 1.2 peer's view of a countered record keeps the section"] = function(harness)
        local players = { ["A-R"] = player(harness, "A-R", 100), ["B-R"] = player(harness, "B-R", 200) }
        local A, B = players["A-R"], players["B-R"]
        local Arena = A.Arena
        local id = assert(A.Arena.Challenge(recordsFor(players, "A-R"), "A-R", "B-R", 10000, NOW))
        assert(B.Arena.Counter(recordsFor(players, "B-R"), "B-R", id, 20000, NOW + 10))
        local section = B.Arena.BuildSection()
        harness.truthy(Arena.SanitizeSection(section, "B-R", math.huge), "a real counter section is valid")
        local function withCounter(entry)
            local copy = { w = 0, l = 0, ch = {}, an = {}, bt = {}, co = { [id] = entry } }
            return Arena.SanitizeSection(copy, "B-R", math.huge)
        end
        local good = section.co[id]
        harness.equal(withCounter({ wg = Arena.MAXIMUM_WAGER + 1, at = good.at, t = good.t }), nil, "wager too high")
        harness.equal(withCounter({ wg = 100, at = good.at, t = { { npc = 1 } } }), nil, "bad fighter")
        harness.equal(Arena.SanitizeSection({ w = 0, l = 0, co = { [id] = good } }, "A-R", math.huge), nil, "a counter to my own challenge in my record")
        -- the challenger's answer fields: at most one, inside the horizon
        assert(A.Arena.AnswerCounter(recordsFor(players, "A-R"), "A-R", id, true, NOW + 20))
        local mine = A.Arena.BuildSection()
        harness.truthy(Arena.SanitizeSection(mine, "A-R", math.huge), "ca is valid")
        mine.ch[id].cd = NOW + 21
        harness.equal(Arena.SanitizeSection(mine, "A-R", math.huge), nil, "ca and cd together")
        -- what a 1.2 peer keeps: its sanitizer copies ch/an/bt only, so B's counter (in co) is ignored, not fatal
        local oldView = { w = section.w, l = section.l, ch = section.ch, an = section.an, bt = section.bt }
        harness.truthy(Arena.SanitizeSection(oldView, "B-R", math.huge), "without co the section stays valid")
        harness.equal(next(section.an), nil, "a counter is not an answer entry")
    end,

    ["arena: the dev dummy accepts my counter offer to its challenge"] = function(harness)
        local addon = player(harness, "A-R", 100)
        local Arena, AzeCaught = addon.Arena, addon.AzeCaught
        local dummy = Arena.DummyRecord(Arena.Fighter(AzeCaught.Active()), NOW)
        local records = { [dummy.name] = dummy }
        local id = Arena.DummyChallenge(dummy, "A-R", 5000, NOW)
        assert(Arena.Counter(records, "A-R", id, 8000, NOW + 1))
        harness.equal(Arena.Fights(records, "A-R", NOW + 2)[id].state, "countered")
        harness.equal(Arena.DummyRespond(dummy, "A-R", NOW + 3), 1)
        harness.truthy(Arena.SanitizeSection(dummy.arena, dummy.name, math.huge), "the dummy's section stays valid")
        local fight = Arena.Fights(records, "A-R", NOW + 4)[id]
        harness.equal(fight.state, "open"); harness.equal(fight.wager, 8000)
    end,
}
