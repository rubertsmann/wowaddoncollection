local _, addon = ...

-- Companion arena: guild members' companions fight in a hands-off auto battle. Challenges, answers and
-- side bets travel in the owner's game record (section "arena", protocol 1.2), so it works while the other player is
-- offline. Every client computes the fight itself from the two stored fighter snapshots and the fight id (no reported
-- result is trusted) and settles ONLY its own money. Pure: no WoW calls; the clock, records and names are passed in.
local Arena = {}
addon.Arena = Arena

------------------------------------------------------------------ tuning (all pinned by tests/test_arena.lua)

Arena.STATS = { "atk", "def", "spd", "vit" }
Arena.TRAIN_COST = 5000              -- copper per training point already reached + 1 (50s, 1g, 1g50s, ...)
Arena.TRAIN_ENERGY = 15              -- energy a session takes from the companion
Arena.TRAIN_SECONDS = 600            -- active time a session needs
Arena.TRAIN_BONUS = 0.04             -- +4% per point on that stat
Arena.MAXIMUM_TRAINING = 25          -- points per stat
Arena.XP_ENTER, Arena.XP_KNOCKOUT = 15, 25   -- every companion that entered a fight; each opponent it beat
Arena.TEAM_SIZE = 3                  -- every fight is a team of 3 against 3, in the picked order
Arena.XP_PER_LEVEL = 50              -- level n -> n + 1 needs n x 50 XP
Arena.MAXIMUM_LEVEL = 50
Arena.LEVEL_BONUS = 0.03             -- +3% on every stat per level above 1
Arena.HEALTH_PER_VITALITY = 8
Arena.MAXIMUM_ACTIONS = 80           -- then the higher health share wins
Arena.ABILITY_EVERY = 3              -- every 3rd action of a fighter is its ability
Arena.CHALLENGE_TTL = 24 * 3600      -- an unanswered challenge expires (refund)
Arena.ANSWER_GRACE = 24 * 3600       -- the refund waits this long more: a late-synced answer still counts
Arena.BET_WINDOW = 300               -- the fight is decided this long after the accept; bets until then
Arena.REVEAL_AFTER = 3600            -- a decided fight nobody watched is settled anyway this long after the fight time
Arena.KEEP_SECONDS = 3 * 86400       -- settled entries leave my record after this
Arena.MAXIMUM_WAGER = 1000 * 10000   -- 1000g
Arena.MINIMUM_WAGER = 10000          -- 1g: each fighter is the first stake on its side of the pot, so no side is empty
Arena.MINIMUM_BET, Arena.MAXIMUM_BET = 1000, 500 * 10000
Arena.ODDS_LIMITS = { 110, 1000 }    -- hundredths: 1.1x .. 10x (only bets from before the pot carry odds)
Arena.MAXIMUM_ENTRIES = 20           -- per record table (ch, an, bt)
Arena.MAXIMUM_HISTORY = 30
Arena.MAXIMUM_STAT = 1000000
Arena.CHANCE_SAMPLES = 40            -- fights simulated for the win chance (odds)

-- creature type id -> ability (WoW creature types: 1 beast, 2 dragonkin, 3 demon, 4 elemental, 5 giant, 6 undead,
-- 7 humanoid, 9 mechanical); anything else: strike
Arena.ABILITY_BY_TYPE = { [1] = "rend", [2] = "breath", [3] = "burn", [4] = "surge", [5] = "smash", [6] = "drain",
    [7] = "focus", [9] = "barrier" }
-- every ability is worth about 1.6 plain hits: the multiplier plus its effect (tests/test_arena.lua balance check)
Arena.MULTIPLIER = { strike = 1.6, surge = 1.7, breath = 1.2, drain = 1.1, focus = 1.1, smash = 1.0 }
Arena.BARRIER_SHARE = 0.10           -- a barrier absorbs 10% of the maximum health
Arena.ABILITIES = { rend = true, breath = true, burn = true, surge = true, smash = true, drain = true, focus = true,
    barrier = true, strike = true }

------------------------------------------------------------------ local state (db.caught.arena)

---@class ArenaProgress
---@field xp integer
---@field w integer rounds won
---@field l integer rounds lost
---@field tr table<string, integer> training points by stat

---@return table db.caught.arena, created on first use
function Arena.State()
    local caught = addon.AzeCaught.State()
    local state = caught.arena
    if type(state) ~= "table" then
        state = {}
        caught.arena = state
    end
    state.ch, state.an, state.bt, state.co = state.ch or {}, state.an or {}, state.bt or {}, state.co or {}
    state.settled, state.noticed, state.history = state.settled or {}, state.noticed or {}, state.history or {}
    state.watched, state.uids = state.watched or {}, state.uids or {}
    state.w, state.l = state.w or 0, state.l or 0
    return state
end

-- A clean arena progress (saved data, untrusted): missing or bad values start at 0.
---@param raw any
---@return ArenaProgress
function Arena.CleanProgress(raw)
    local SafeInteger = addon.Utility.SafeInteger
    raw = type(raw) == "table" and raw or {}
    local progress = { xp = SafeInteger(raw.xp, 0, 1e9) or 0, w = SafeInteger(raw.w, 0, 1e6) or 0, l = SafeInteger(raw.l, 0, 1e6) or 0, tr = {} }
    local training = type(raw.tr) == "table" and raw.tr or {}
    for _, stat in ipairs(Arena.STATS) do progress.tr[stat] = SafeInteger(training[stat], 0, Arena.MAXIMUM_TRAINING) or 0 end
    return progress
end

-- The arena progress of one roster companion (its own XP, rounds and training).
---@param companion CompanionState
---@return ArenaProgress
function Arena.Progress(companion)
    if type(companion.ar) ~= "table" then companion.ar = Arena.CleanProgress(nil) end
    return companion.ar
end

------------------------------------------------------------------ levels and training

-- The arena level for `xp` and the XP into / needed for the next level.
---@param xp integer
---@return integer level
---@return integer into
---@return integer needed 0 at the maximum level
function Arena.Level(xp)
    xp = math.max(0, math.floor(tonumber(xp) or 0))
    local level = 1
    while level < Arena.MAXIMUM_LEVEL and xp >= Arena.XP_PER_LEVEL * level do
        xp = xp - Arena.XP_PER_LEVEL * level
        level = level + 1
    end
    return level, xp, level < Arena.MAXIMUM_LEVEL and Arena.XP_PER_LEVEL * level or 0
end

---@param points integer already reached on that stat
---@return integer copper
function Arena.TrainCost(points) return Arena.TRAIN_COST * ((points or 0) + 1) end

-- Starts a training session on `stat` for my companion. Returns true or nil and why: "nocompanion", "busy", "stat",
-- "maximum", "asleep", "energy", "funds", "readonly".
---@param myName string
---@param stat string
---@param now integer
---@return boolean|nil
---@return string|nil reason
function Arena.Train(myName, stat, now)
    local AzeCaught = addon.AzeCaught
    if addon.Store.db.readonly then return nil, "readonly" end
    local companion = AzeCaught.Active()
    if not companion then return nil, "nocompanion" end
    local state = Arena.State()
    if state.training then return nil, "busy" end
    local valid = false
    for _, key in ipairs(Arena.STATS) do if key == stat then valid = true end end
    if not valid then return nil, "stat" end
    local npc = Arena.Progress(companion)
    if npc.tr[stat] >= Arena.MAXIMUM_TRAINING then return nil, "maximum" end
    if companion.asleep then return nil, "asleep" end
    if companion.energy < Arena.TRAIN_ENERGY then return nil, "energy" end
    local cost = Arena.TrainCost(npc.tr[stat])
    local _, refusal = addon.Wallet.Spend(myName, cost, "train", now, companion.n)
    if refusal then return nil, refusal end
    companion.energy = companion.energy - Arena.TRAIN_ENERGY
    state.training = { stat = stat, uid = companion.uid, done = AzeCaught.State().activeSeconds + Arena.TRAIN_SECONDS }
    AzeCaught.Journal("INFORMATION", "arena.train", "a training session started", { stat = stat, uid = companion.uid, npc = companion.npc, cost = cost })
    return true
end

-- Seconds of active time the running session still needs, or nil when none runs.
---@return number|nil
function Arena.TrainingLeft()
    local training = Arena.State().training
    if not training then return nil end
    return math.max(0, training.done - addon.AzeCaught.State().activeSeconds)
end

-- Finishes the session when its time has passed. Returns {stat, npc, uid, points} once, else nil.
---@return table|nil
function Arena.FinishTraining()
    local state = Arena.State()
    local training = state.training
    if not training or addon.AzeCaught.State().activeSeconds < training.done then return nil end
    state.training = nil
    local companion = addon.AzeCaught.Companion(training.uid)
    if not companion then return nil end
    local npc = Arena.Progress(companion)
    npc.tr[training.stat] = math.min(Arena.MAXIMUM_TRAINING, npc.tr[training.stat] + 1)
    addon.AzeCaught.Journal("INFORMATION", "arena.trained", "a training session finished",
        { stat = training.stat, uid = training.uid, npc = companion.npc, points = npc.tr[training.stat] })
    return { stat = training.stat, npc = companion.npc, uid = training.uid, points = npc.tr[training.stat] }
end

-- Stops a running training session (switching or releasing the companion). Gold and energy are not refunded.
-- Returns true when one was running.
---@return boolean
function Arena.CancelTraining()
    local state = Arena.State()
    if not state.training then return false end
    addon.AzeCaught.Journal("INFORMATION", "arena.trainCancelled", "a training session was cancelled",
        { stat = state.training.stat, uid = state.training.uid })
    state.training = nil
    return true
end

------------------------------------------------------------------ fighters

---@class Fighter
---@field npc integer
---@field n string NPC name
---@field nk? string the owner's nickname for it (display only: never part of the fight)
---@field cls string
---@field disp integer
---@field ty integer creature type id (0 unknown)
---@field al integer arena level
---@field atk integer
---@field def integer
---@field spd integer
---@field vit integer
---@field ab string ability key

-- The fighter snapshot of a companion: combat stats + vitality, x training, x arena level, x morale (hearts), attack
-- -10% when hungry or thirsty, x the running arena buffs (their ids in `bf`). Nil without a collection entry. The buffs
-- are part of the stats, so a client that does not know `bf` computes the same fight.
---@param companion CompanionState
---@return Fighter|nil
function Arena.Fighter(companion)
    local AzeCaught = addon.AzeCaught
    if type(companion) ~= "table" then return nil end
    local entry = AzeCaught.State().collection[companion.npc]
    if not entry then return nil end
    local base = AzeCaught.CombatStats(companion.npc, entry)
    local values = { atk = base.attack, def = base.defense, spd = base.speed,
        vit = math.floor((base.attack + base.defense) / 2 + 0.5) }
    local npc = Arena.Progress(companion)
    local level = Arena.Level(npc.xp)
    local morale = 1 + addon.Utility.Clamp(companion.hearts or 0, -10, 10) / 100
    local fighter = { npc = companion.npc, n = entry.n, cls = entry.cls, disp = entry.disp or 0,
        ty = type(entry.st) == "table" and entry.st.type or 0, al = level,
        nk = type(companion.info) == "table" and companion.info.nick or nil,
        tl = AzeCaught.CompanionLevel(companion) }   -- the TLevel when the team was sent (display only)
    for _, stat in ipairs(Arena.STATS) do
        local factor = (1 + Arena.TRAIN_BONUS * npc.tr[stat]) * (1 + Arena.LEVEL_BONUS * (level - 1)) * morale
        fighter[stat] = math.max(1, math.min(Arena.MAXIMUM_STAT, math.floor(values[stat] * factor + 0.5)))
    end
    local zones = companion.zones or {}
    if (zones.hunger and zones.hunger ~= "ok") or (zones.thirst and zones.thirst ~= "ok") then
        fighter.atk = math.max(1, math.floor(fighter.atk * 0.9 + 0.5))
    end
    local buffs = addon.Items.RunningArenaBuffs()
    for _, item in ipairs(buffs) do
        fighter[item.stat] = math.max(1, math.min(Arena.MAXIMUM_STAT, math.floor(fighter[item.stat] * item.factor + 0.5)))
    end
    if #buffs > 0 then
        fighter.bf = {}
        for index, item in ipairs(buffs) do fighter.bf[index] = item.id end
    end
    fighter.ab = Arena.ABILITY_BY_TYPE[fighter.ty] or "strike"
    return fighter
end

Arena.MAXIMUM_BUFFS = 3

-- A clean list of arena buff ids (known arenaBuff items, no repeats, at most MAXIMUM_BUFFS), or nil when none is left.
---@param raw any
---@return string[]|nil
function Arena.SanitizeBuffs(raw)
    if type(raw) ~= "table" then return nil end
    local clean, seen = {}, {}
    for index = 1, math.min(#raw, Arena.MAXIMUM_BUFFS) do
        local item = addon.Items.Get(raw[index])
        if item and item.kind == "arenaBuff" and not seen[item.id] then
            seen[item.id] = true
            clean[#clean + 1] = item.id
        end
    end
    return #clean > 0 and clean or nil
end

-- A clean copy of a peer's fighter or nil.
---@param raw any
---@return Fighter|nil
function Arena.SanitizeFighter(raw)
    local Utility, AzeCaught = addon.Utility, addon.AzeCaught
    if type(raw) ~= "table" then return nil end
    local SafeInteger = Utility.SafeInteger
    local clean = { npc = SafeInteger(raw.npc, 1, AzeCaught.MAXIMUM_ID), n = Utility.CleanString(raw.n, AzeCaught.MAXIMUM_NAME_BYTES),
        cls = AzeCaught.RARITY_MALUS[raw.cls] and raw.cls or nil, disp = SafeInteger(raw.disp, 0, AzeCaught.MAXIMUM_ID),
        ty = SafeInteger(raw.ty, 0, 100), al = SafeInteger(raw.al, 1, Arena.MAXIMUM_LEVEL),
        ab = Arena.ABILITIES[raw.ab] and raw.ab or nil }
    for _, stat in ipairs(Arena.STATS) do clean[stat] = SafeInteger(raw[stat], 1, Arena.MAXIMUM_STAT) end
    for _, key in ipairs({ "npc", "n", "cls", "disp", "ty", "al", "ab", "atk", "def", "spd", "vit" }) do
        if clean[key] == nil then return nil end
    end
    clean.bf = Arena.SanitizeBuffs(raw.bf)
    clean.nk = AzeCaught.CleanNickname(raw.nk)   -- optional: a bad one is dropped alone
    -- optional, display only: the TLevel (NPC level + rarity + hearts) when the team was sent
    clean.tl = SafeInteger(raw.tl, -AzeCaught.MAXIMUM_HEARTS, AzeCaught.MAXIMUM_HEARTS + AzeCaught.MAXIMUM_LEVEL + 25)
    return clean
end

-- A clean copy of a peer's team: exactly TEAM_SIZE clean fighters in order, or nil.
---@param raw any
---@return Fighter[]|nil
function Arena.SanitizeTeam(raw)
    if type(raw) ~= "table" or addon.Utility.Count(raw) ~= Arena.TEAM_SIZE then return nil end
    local team = {}
    for index = 1, Arena.TEAM_SIZE do
        team[index] = Arena.SanitizeFighter(raw[index])
        if not team[index] then return nil end
    end
    return team
end

-- My team for a fight: the fighters of TEAM_SIZE different roster companions (uids) in the given order. Reasons:
-- "team" (not exactly TEAM_SIZE different companions of mine), "nocompanion" (one has no fighter).
---@param uids any
---@return Fighter[]|nil
---@return string|nil reason
function Arena.Team(uids)
    if type(uids) ~= "table" or #uids ~= Arena.TEAM_SIZE then return nil, "team" end
    local team, seen = {}, {}
    for index, uid in ipairs(uids) do
        local companion = addon.AzeCaught.Companion(uid)
        if not companion or seen[uid] then return nil, "team" end
        seen[uid] = true
        team[index] = Arena.Fighter(companion)
        if not team[index] then return nil, "nocompanion" end
    end
    return team
end

-- How many more companions I need for a team (0 = enough).
---@return integer
function Arena.MissingForTeam()
    return math.max(0, Arena.TEAM_SIZE - addon.Utility.Count(addon.AzeCaught.State().roster))
end

-- The addon version `name` runs, as their arena section says (mine: this build), or nil when unknown.
---@param records table<string, table>|nil
---@param name string
---@param myName string|nil
---@return string|nil
function Arena.VersionOf(records, name, myName)
    if name == myName then return addon.VERSION end
    local gameRecord = records and records[name]
    local section = type(gameRecord) == "table" and gameRecord.arena
    return type(section) == "table" and Arena.SanitizeVersion(section.ver) or nil
end

-- A peer's version string (short, plain), or nil.
---@param value any
---@return string|nil
function Arena.SanitizeVersion(value)
    if type(value) ~= "string" or value == "" or #value > 32 or not value:match("^[%w%.%-%+_]+$") then return nil end
    return value
end

-- Fights need both players on exactly the same addon version. Returns true, or false and the opponent's version (nil
-- when unknown).
---@param records table<string, table>|nil
---@param opponent string
---@return boolean
---@return string|nil theirs
function Arena.SameVersion(records, opponent)
    local theirs = Arena.VersionOf(records, opponent)
    return theirs ~= nil and theirs == addon.VERSION, theirs
end

------------------------------------------------------------------ the battle

local MODULUS, MULTIPLIER = 2147483647, 48271   -- Park-Miller: exact in doubles, the same on every client

-- A seed from a fight id (string hash, 1..MODULUS-1).
---@param id string
---@return integer
function Arena.Seed(id)
    local hash = 7
    id = tostring(id)
    for index = 1, #id do hash = (hash * 31 + id:byte(index)) % (MODULUS - 1) end
    return hash + 1
end

---@param seed integer
---@return fun(): number in [0, 1)
local function generator(seed)
    local value = seed
    return function()
        value = (value * MULTIPLIER) % MODULUS
        return (value - 1) / (MODULUS - 1)
    end
end

local function round(value) return math.floor(value + 0.5) end

---@class FightEvent
---@field s string "a" or "b": who acts (or enters)
---@field k string "hit", "crit", "dodge", "dot", "stun", "shield", "enter" (the side's next fighter came in)
---@field ab? string ability used
---@field d? integer damage (or shield / heal amount)
---@field heal? integer
---@field ha integer a's current fighter's health after the event
---@field hb integer b's current fighter's health after the event
---@field ia integer a's current fighter (team slot)
---@field ib integer b's current fighter (team slot)
---@field ma integer a's current fighter's maximum health
---@field mb integer b's current fighter's maximum health

---@class FightResult
---@field winner string "a" or "b"
---@field events FightEvent[]
---@field maxA integer the first fighters' maximum health
---@field maxB integer
---@field reason string how the last round ended: "ko" or "time"
---@field entered { a: integer, b: integer } fighters that came in per side
---@field knockouts { a: integer[], b: integer[] } opponents beaten per team slot

---@param value table a fighter or a team (list of fighters)
---@return Fighter[]
local function asTeam(value)
    if value.atk then return { value } end
    return value
end

-- Fights team `a` against team `b` (lists of fighter snapshots; a single fighter is a team of one). The first of each
-- side fight; the winner of a round stays in with everything as it is (health, shield, damage over time, stun, focus,
-- ability cadence, action gauge) and meets the loser's next fighter, who enters fresh. A round that reaches
-- MAXIMUM_ACTIONS goes to the higher health share. The side without fighters left loses. The same inputs always give
-- the same result.
---@param teamA Fighter[]|Fighter
---@param teamB Fighter[]|Fighter
---@param id string fight id (the seed)
---@return FightResult
function Arena.Fight(teamA, teamB, id)
    teamA, teamB = asTeam(teamA), asTeam(teamB)
    local random = generator(Arena.Seed(id))
    local teams, slot, sides = { a = teamA, b = teamB }, { a = 1, b = 1 }, {}
    local function enter(key)
        local fighter = teams[key][slot[key]]
        local maximum = fighter.vit * Arena.HEALTH_PER_VITALITY
        sides[key] = { f = fighter, hp = maximum, max = maximum, gauge = 0, shield = 0, dot = 0, dotTurns = 0,
            focus = false, stunned = false, actions = 0 }
    end
    enter("a")
    enter("b")
    -- a random head start (0..25 of the 100-point gauge): with equal speed the challenger would always act first
    sides.a.gauge, sides.b.gauge = random() * 25, random() * 25
    local maxA, maxB = sides.a.max, sides.b.max
    local events = {}
    local function log(event)
        event.ha, event.hb = sides.a.hp, sides.b.hp
        event.ia, event.ib, event.ma, event.mb = slot.a, slot.b, sides.a.max, sides.b.max
        events[#events + 1] = event
    end
    local function hurt(target, amount)
        local absorbed = math.min(target.shield, amount)
        target.shield = target.shield - absorbed
        target.hp = math.max(0, target.hp - (amount - absorbed))
    end
    local knockouts = { a = {}, b = {} }
    local winner, reason
    while true do
        winner, reason = nil, nil
        for _ = 1, Arena.MAXIMUM_ACTIONS do
            -- the action gauge: who reaches 100 first acts (ties: the faster, then a)
            local timeA = (100 - sides.a.gauge) / sides.a.f.spd
            local timeB = (100 - sides.b.gauge) / sides.b.f.spd
            local actorKey = (timeA < timeB or (timeA == timeB and sides.a.f.spd >= sides.b.f.spd)) and "a" or "b"
            local elapsed = math.min(timeA, timeB)
            sides.a.gauge = sides.a.gauge + sides.a.f.spd * elapsed
            sides.b.gauge = sides.b.gauge + sides.b.f.spd * elapsed
            local actor, targetKey = sides[actorKey], actorKey == "a" and "b" or "a"
            local target = sides[targetKey]
            actor.gauge = math.max(0, actor.gauge - 100)
            if actor.dotTurns > 0 then
                actor.dotTurns = actor.dotTurns - 1
                hurt(actor, actor.dot)
                log({ s = actorKey, k = "dot", d = actor.dot })
                if actor.hp <= 0 then winner, reason = targetKey, "ko" break end
            end
            if actor.stunned then
                actor.stunned = false
                log({ s = actorKey, k = "stun" })
            else
                actor.actions = actor.actions + 1
                local ability = actor.actions % Arena.ABILITY_EVERY == 0 and actor.f.ab or nil
                if ability == "barrier" then
                    local amount = round(actor.max * Arena.BARRIER_SHARE)
                    actor.shield = actor.shield + amount
                    log({ s = actorKey, k = "shield", ab = ability, d = amount })
                else
                    local attack, defense = actor.f.atk, target.f.def
                    if ability == "breath" then defense = defense / 2 end
                    local speedShare = (actor.f.spd - target.f.spd) / (actor.f.spd + target.f.spd)
                    local dodge = addon.Utility.Clamp(0.05 - speedShare * 0.4, 0.05, 0.25)
                    local critical = addon.Utility.Clamp(0.05 + speedShare * 0.3, 0.05, 0.3)
                    local rollDodge, rollCritical, rollSpread = random(), random(), random()
                    if rollDodge < dodge and ability ~= "focus" then
                        log({ s = actorKey, k = "dodge", ab = ability })
                    else
                        local multiplier = Arena.MULTIPLIER[ability] or 1
                        local isCritical = actor.focus or rollCritical < critical
                        actor.focus = ability == "focus"   -- focus: this hit as usual, the next one crits
                        local damage = attack * attack / (attack + defense) * multiplier * (0.9 + 0.2 * rollSpread)
                        if isCritical then damage = damage * 1.5 end
                        damage = math.max(1, round(damage))
                        hurt(target, damage)
                        local event = { s = actorKey, k = isCritical and "crit" or "hit", ab = ability, d = damage }
                        if ability == "drain" then
                            local heal = math.min(actor.max - actor.hp, round(damage / 2))
                            actor.hp = actor.hp + heal
                            event.heal = heal
                        elseif ability == "rend" then target.dot, target.dotTurns = math.max(1, round(damage * 0.2)), 3
                        elseif ability == "burn" then target.dot, target.dotTurns = math.max(1, round(damage * 0.3)), 2
                        elseif ability == "smash" and rollSpread < 0.5 then
                            target.stunned = true
                            event.stun = true
                        end
                        log(event)
                    end
                end
                if target.hp <= 0 then winner, reason = actorKey, "ko" break end
            end
        end
        if not winner then
            reason = "time"
            local shareA, shareB = sides.a.hp / sides.a.max, sides.b.hp / sides.b.max
            if shareA == shareB then winner = Arena.Seed(id) % 2 == 0 and "a" or "b"
            else winner = shareA > shareB and "a" or "b" end
        end
        local loser = winner == "a" and "b" or "a"
        knockouts[winner][slot[winner]] = (knockouts[winner][slot[winner]] or 0) + 1
        if slot[loser] >= #teams[loser] then break end
        slot[loser] = slot[loser] + 1
        enter(loser)
        sides[loser].gauge = random() * 25
        log({ s = loser, k = "enter" })
    end
    for _, key in ipairs({ "a", "b" }) do
        for index = 1, #teams[key] do knockouts[key][index] = knockouts[key][index] or 0 end
    end
    return { winner = winner, events = events, maxA = maxA, maxB = maxB, reason = reason,
        entered = { a = slot.a, b = slot.b }, knockouts = knockouts }
end

-- The share of fights `a` wins against `b` (fighters or teams; CHANCE_SAMPLES fights with derived ids; deterministic).
---@param a Fighter[]|Fighter
---@param b Fighter[]|Fighter
---@param id string
---@return number 0..1
function Arena.WinChance(a, b, id)
    local wins = 0
    for index = 1, Arena.CHANCE_SAMPLES do
        if Arena.Fight(a, b, id .. "~" .. index).winner == "a" then wins = wins + 1 end
    end
    return wins / Arena.CHANCE_SAMPLES
end

------------------------------------------------------------------ record section

-- My section for the game record: totals and the open entries (copies; the record is replaced as a whole).
---@return table
function Arena.BuildSection()
    local state = Arena.State()
    local section = { w = state.w, l = state.l, ver = addon.VERSION, ch = {}, an = {}, bt = {}, co = {} }
    for _, key in ipairs({ "ch", "an", "bt", "co" }) do
        for id, entry in pairs(state[key]) do section[key][id] = addon.Utility.DeepCopy(entry) end
    end
    return section
end

---@param id any
---@return string|nil challenger
---@return integer|nil at
function Arena.ParseID(id)
    if type(id) ~= "string" or #id > 80 then return nil end
    local name, at = id:match("^(.+)#(%d+)$")
    if not name or not addon.Utility.IsSafeName(name) then return nil end
    return name, tonumber(at)
end

-- A clean copy of a peer's (or my stored) arena section, or nil (dropped alone; the record stays).
---@param section any
---@param owner string the record's name
---@param horizon number
---@return table|nil
function Arena.SanitizeSection(section, owner, horizon)
    local Utility = addon.Utility
    local SafeInteger = Utility.SafeInteger
    if type(section) ~= "table" then return nil end
    local clean = { w = SafeInteger(section.w or 0, 0, 1000000), l = SafeInteger(section.l or 0, 0, 1000000),
        ver = Arena.SanitizeVersion(section.ver), ch = {}, an = {}, bt = {}, co = {} }
    if not clean.w or not clean.l then return nil end
    local function each(key, check)
        local raw = section[key]
        if raw == nil then return true end
        if type(raw) ~= "table" or Utility.Count(raw) > Arena.MAXIMUM_ENTRIES then return false end
        for id, entry in pairs(raw) do
            local challenger, idTime = Arena.ParseID(id)
            if not challenger or type(entry) ~= "table" then return false end
            local value = check(entry, challenger, idTime)
            if not value then return false end
            clean[key][id] = value
        end
        return true
    end
    local ok = each("ch", function(entry, challenger, idTime)
        if challenger ~= owner then return nil end   -- only my own challenges are in my record
        local to, at = entry.to, SafeInteger(entry.at, 0, horizon)
        local wager, fighter = SafeInteger(entry.wg or 0, 0, Arena.MAXIMUM_WAGER), Arena.SanitizeTeam(entry.t)
        if not Utility.IsSafeName(to) or to == owner or not at or at ~= idTime or not wager or not fighter then return nil end
        local withdrawn = entry.wd ~= nil and SafeInteger(entry.wd, at, horizon) or nil
        if entry.wd ~= nil and not withdrawn then return nil end
        -- the answer to a counter offer (protocol 1.3): accepted at / declined at, at most one of them
        local counterAccepted = entry.ca ~= nil and SafeInteger(entry.ca, at, horizon) or nil
        local counterDeclined = entry.cd ~= nil and SafeInteger(entry.cd, at, horizon) or nil
        if (entry.ca ~= nil and not counterAccepted) or (entry.cd ~= nil and not counterDeclined) or (counterAccepted and counterDeclined) then return nil end
        return { to = to, at = at, wg = wager, t = fighter, wd = withdrawn, ca = counterAccepted, cd = counterDeclined }
    end) and each("an", function(entry, challenger)
        if challenger == owner then return nil end
        local at = SafeInteger(entry.at, 0, horizon)
        if not at or type(entry.ok) ~= "boolean" then return nil end
        local fighter = entry.ok and Arena.SanitizeTeam(entry.t) or nil
        if entry.ok and not fighter then return nil end
        -- the accepting player's own wager (missing in accepts from before the pot: the challenger's wager)
        local wager = entry.wg ~= nil and SafeInteger(entry.wg, 0, Arena.MAXIMUM_WAGER) or nil
        if entry.wg ~= nil and not wager then return nil end
        return { ok = entry.ok, at = at, t = fighter, wg = entry.ok and wager or nil }
    end) and each("bt", function(entry, challenger)
        if challenger == owner then return nil end
        local side, stake = entry.s, SafeInteger(entry.c, Arena.MINIMUM_BET, Arena.MAXIMUM_BET)
        local at = SafeInteger(entry.at, 0, horizon)
        -- fixed odds: only bets placed before the pot have them (they are paid by their odds, outside the pot)
        local odds = entry.o ~= nil and SafeInteger(entry.o, Arena.ODDS_LIMITS[1], Arena.ODDS_LIMITS[2]) or nil
        if (side ~= "a" and side ~= "b") or not stake or (entry.o ~= nil and not odds) or not at then return nil end
        return { s = side, c = stake, o = odds, at = at }
    end) and each("co", function(entry, challenger)
        if challenger == owner then return nil end
        local wager, at = SafeInteger(entry.wg, 0, Arena.MAXIMUM_WAGER), SafeInteger(entry.at, 0, horizon)
        local fighter = Arena.SanitizeTeam(entry.t)
        if not wager or not at or not fighter then return nil end
        return { wg = wager, at = at, t = fighter }
    end)
    if not ok then return nil end
    return clean
end

------------------------------------------------------------------ fights over all records

---@class ArenaFight
---@field id string
---@field a string challenger
---@field b string challenged
---@field at integer
---@field wager integer the challenger's stake
---@field wagerB integer|nil the challenged player's own stake (once accepted)
---@field ta Fighter[] the challenger's team
---@field tb Fighter[]|nil the challenged player's team (once accepted)
---@field fa Fighter the first of ta
---@field fb Fighter|nil the first of tb
---@field state string "pending", "lapsed", "countered", "declined", "rejected" (counter declined), "expired", "withdrawn", "open", "done", "version" (the two players run different versions: void)
---@field counter table|nil the challenged player's counter offer {wg, at, f}
---@field answerAt integer|nil
---@field fightAt integer|nil
---@field bets table<string, table> bettor -> bet

-- The arena section of `name` (my own from the local state, others from their records).
local function sectionOf(records, name, myName)
    if name == myName then return Arena.BuildSection() end
    local gameRecord = records and records[name]
    return type(gameRecord) == "table" and type(gameRecord.arena) == "table" and gameRecord.arena or nil
end

-- Every fight visible to me: challenges in all records joined with the challenged player's answer and all bets.
---@param records table<string, table>
---@param myName string
---@param now integer
---@return table<string, ArenaFight>
function Arena.Fights(records, myName, now)
    local fights = {}
    local names = {}
    for name in pairs(records or {}) do names[name] = true end
    if myName then names[myName] = true end
    for name in pairs(names) do
        local section = sectionOf(records, name, myName)
        for id, challenge in pairs(section and section.ch or {}) do
            local now = now + (Arena.devShift[id] or 0)   -- dev: a fake fight moved forward in time (memory only)
            local fight = { id = id, a = name, b = challenge.to, at = challenge.at, wager = challenge.wg or 0, ta = challenge.t,
                fa = challenge.t[1], bets = {} }
            local answers = sectionOf(records, challenge.to, myName)
            local answer = answers and answers.an and answers.an[id]
            local counter = answers and answers.co and answers.co[id]
            local function inTime(at, from) return at >= from and at <= from + Arena.CHALLENGE_TTL and (not challenge.wd or at < challenge.wd) end
            -- an answer (or a counter offer) only counts from the challenged player, inside the challenge's lifetime
            -- and before the challenger stopped it; the challenger's answer to a counter inside the counter's lifetime
            if answer and inTime(answer.at, challenge.at) then
                fight.answerAt = answer.at
                if answer.ok then
                    fight.tb, fight.fb, fight.fightAt = answer.t, answer.t[1], answer.at + Arena.BET_WINDOW
                    fight.wagerB = answer.wg or fight.wager
                    -- dev: the waiting time of a dummy fight was cut short (memory only, Arena.SkipDummyWait)
                    if Arena.skipped[id] then fight.fightAt = math.max(answer.at, math.min(fight.fightAt, Arena.skipped[id])) end
                    fight.state = now >= fight.fightAt and "done" or "open"
                else
                    fight.state = "declined"
                end
            elseif counter and inTime(counter.at, challenge.at) then
                fight.counter = counter
                if challenge.ca and inTime(challenge.ca, counter.at) then
                    fight.answerAt, fight.wager, fight.wagerB = challenge.ca, counter.wg, counter.wg
                    fight.tb, fight.fb, fight.fightAt = counter.t, counter.t[1], challenge.ca + Arena.BET_WINDOW
                    if Arena.skipped[id] then fight.fightAt = math.max(challenge.ca, math.min(fight.fightAt, Arena.skipped[id])) end
                    fight.state = now >= fight.fightAt and "done" or "open"
                elseif challenge.cd and inTime(challenge.cd, counter.at) then
                    fight.state = "rejected"
                elseif challenge.wd then
                    fight.state, fight.withdrawnAt = "withdrawn", challenge.wd
                else
                    fight.state = now > counter.at + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE and "expired" or "countered"
                end
            elseif challenge.wd then
                fight.state, fight.withdrawnAt = "withdrawn", challenge.wd
            else
                fight.state = now > challenge.at + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE and "expired"
                    or now > challenge.at + Arena.CHALLENGE_TTL and "lapsed" or "pending"
            end
            -- both players must run the same version; a fight between different versions is void (stakes come back)
            local versionA, versionB = Arena.VersionOf(records, name, myName), Arena.VersionOf(records, challenge.to, myName)
            if versionA and versionB and versionA ~= versionB and fight.state ~= "declined" and fight.state ~= "expired"
                and fight.state ~= "withdrawn" and fight.state ~= "rejected" then
                fight.state = "version"
            end
            fights[id] = fight
        end
    end
    -- bets: not from the two fighters, placed while the fight was open, and from a bettor on the fighters' version
    for name in pairs(names) do
        local section = sectionOf(records, name, myName)
        local bettorVersion = Arena.VersionOf(records, name, myName)
        for id, bet in pairs(section and section.bt or {}) do
            local fight = fights[id]
            local fightVersion = fight and Arena.VersionOf(records, fight.a, myName)
            if fight and name ~= fight.a and name ~= fight.b and fight.fightAt and bet.at < fight.fightAt and bet.at >= (fight.answerAt or 0)
                and (not bettorVersion or not fightVersion or bettorVersion == fightVersion) then
                fight.bets[name] = bet
            end
        end
    end
    return fights
end

------------------------------------------------------------------ the pot

---@class ArenaPot
---@field a integer the challenger's side: their wager plus the bets on them
---@field b integer the challenged player's side
---@field stakes table<string, {s: "a"|"b", c: integer}> every stake in the pot by player

-- The pot of an accepted fight: each fighter's wager is the first stake on their own side, every counted bet joins
-- its side (bets with fixed odds from before the pot are paid by their odds and stay out). Each client builds it from
-- the bets it has seen; Arena.Fights already left out late bets, the fighters' own and other versions'.
---@param fight ArenaFight|nil
---@return ArenaPot
function Arena.Pot(fight)
    local pot = { a = 0, b = 0, stakes = {} }
    if not fight or not fight.tb then return pot end
    local function add(name, side, amount)
        if type(name) ~= "string" or pot.stakes[name] or type(amount) ~= "number" or amount <= 0 then return end
        pot.stakes[name] = { s = side, c = amount }
        pot[side] = pot[side] + amount
    end
    add(fight.a, "a", fight.wager)
    add(fight.b, "b", fight.wagerB or fight.wager)
    for name, bet in pairs(fight.bets or {}) do
        if not bet.o then add(name, bet.s, bet.c) end
    end
    return pot
end

-- What `name` gets from the pot when `winner` won: their own stake back plus the losing side's total, split by
-- their share of the winning side (rounded down to copper). A stake on the losing side (or none) gets 0.
---@param pot ArenaPot
---@param winner "a"|"b"
---@param name string
---@return integer
function Arena.Payout(pot, winner, name)
    local stake = pot and pot.stakes[name]
    if not stake or stake.s ~= winner or (pot[winner] or 0) <= 0 then return 0 end
    local loser = winner == "a" and "b" or "a"
    return stake.c + math.floor(pot[loser] * stake.c / pot[winner])
end

local resultCache, resultCount = {}, 0
-- The fight's result (cached by id: a fight's inputs never change once accepted).
---@param fight ArenaFight
---@return FightResult|nil
function Arena.Result(fight)
    if not fight or not fight.fb then return nil end
    local cached = resultCache[fight.id]
    if cached then return cached end
    resultCount = resultCount + 1
    if resultCount > 200 then resultCache, resultCount = {}, 1 end
    cached = Arena.Fight(fight.ta, fight.tb, fight.id)
    resultCache[fight.id] = cached
    return cached
end

------------------------------------------------------------------ actions (each returns true or nil, reason)

-- One fight at a time: `name` is busy with an open (accepted, not yet fought) fight, or, when
-- `outgoing`, also with an own challenge still waiting for an answer. Returns that fight's id or nil.
---@param fights table<string, ArenaFight>
---@param name string
---@param outgoing boolean
---@return string|nil
function Arena.Busy(fights, name, outgoing)
    for id, fight in pairs(fights) do
        if fight.state == "open" and (fight.a == name or fight.b == name) then return id end
        if outgoing and fight.a == name and (fight.state == "pending" or fight.state == "lapsed" or fight.state == "countered") then return id end
        if outgoing and fight.b == name and fight.state == "countered" then return id end
    end
    return nil
end

---@class ArenaCandidate
---@field name string
---@field reason string|nil why they can't be challenged: "version", "fewcompanions", "theybusy", "offline"; nil: they can
---@field version string|nil the version they run (when known)
---@field companions integer|nil how many companions they have (when their record says)

-- Everybody I could challenge: every other member with a companion record, the ones that can be challenged first
-- (then by name). `isOnline(name)` returns false for a member known to be offline (nil: unknown, not greyed).
---@param records table<string, table>
---@param myName string
---@param now integer
---@param isOnline? fun(name: string): boolean|nil
---@return ArenaCandidate[]
function Arena.Candidates(records, myName, now, isOnline)
    local fights = Arena.Fights(records, myName, now)
    local list = {}
    for name, gameRecord in pairs(records or {}) do
        if name ~= myName and addon.Utility.IsSafeName(name) and type(gameRecord) == "table" and type(gameRecord.caught) == "table" then
            local same, theirs = Arena.SameVersion(records, name)
            local companions = tonumber(gameRecord.caught.rc)
            local reason
            if not same then reason = "version"
            elseif companions and companions < Arena.TEAM_SIZE then reason = "fewcompanions"
            elseif Arena.Busy(fights, name, false) then reason = "theybusy"
            elseif Arena.devOffline[name] or (isOnline and isOnline(name) == false) then reason = "offline" end
            list[#list + 1] = { name = name, reason = reason, version = theirs, companions = companions }
        end
    end
    table.sort(list, function(left, right)
        if (left.reason == nil) ~= (right.reason == nil) then return left.reason == nil end
        return left.name < right.name
    end)
    return list
end

-- Challenges `opponent` (who must have a companion in their record and run my version) with `wager` copper and my team
-- (TEAM_SIZE roster uids in fighting order). Reasons: "readonly", "self", "opponent", "nocompanionthere", "version",
-- "team", "nocompanion", "busy" (my one fight is running or waiting), "theybusy" (they are in a fight), "open",
-- "wager", "funds".
---@param uids string[]
---@return string|nil id
---@return string|nil reason
function Arena.Challenge(records, myName, opponent, wager, now, uids)
    if addon.Store.db.readonly then return nil, "readonly" end
    if opponent == myName then return nil, "self" end
    if not addon.Utility.IsSafeName(opponent) then return nil, "opponent" end
    local theirs = records and records[opponent]
    if not (type(theirs) == "table" and type(theirs.caught) == "table" and type(theirs.caught.c) == "table") then
        return nil, "nocompanionthere"
    end
    if not Arena.SameVersion(records, opponent) then return nil, "version" end
    local team, teamRefusal = Arena.Team(uids)
    if not team then return nil, teamRefusal end
    wager = math.floor(tonumber(wager) or 0)
    if wager < Arena.MINIMUM_WAGER or wager > Arena.MAXIMUM_WAGER then return nil, "wager" end
    local state = Arena.State()
    local fights = Arena.Fights(records, myName, now)
    if Arena.Busy(fights, myName, true) then return nil, "busy" end
    if Arena.Busy(fights, opponent, false) then return nil, "theybusy" end
    if addon.Utility.Count(state.ch) >= Arena.MAXIMUM_ENTRIES then return nil, "open" end
    local at = now
    while state.ch[myName .. "#" .. at] do at = at + 1 end
    local id = myName .. "#" .. at
    local _, refusal = addon.Wallet.Spend(myName, wager, "wager", now, opponent)
    if refusal then return nil, refusal end
    state.ch[id] = { to = opponent, at = at, wg = wager, t = team }
    state.uids[id] = { uids[1], uids[2], uids[3] }
    addon.Items.SpendArenaBuffs(team[1].bf)
    addon.AzeCaught.Journal("INFORMATION", "arena.challenge", "a challenge was sent", { id = id, to = opponent, wager = wager })
    return id
end

-- Accepts (with my team: TEAM_SIZE roster uids in fighting order, and my own wager MINIMUM_WAGER..MAXIMUM_WAGER) or
-- declines a challenge to me. Reasons: "readonly", "unknown", "answered", "late", "version", "busy" (accepting while
-- my one fight runs or my own challenge waits), "team", "nocompanion", "wager", "funds".
---@param uids string[]|nil
---@param wager integer|nil copper (accepting only)
---@return boolean|nil
---@return string|nil reason
function Arena.Answer(records, myName, id, accept, now, uids, wager)
    if addon.Store.db.readonly then return nil, "readonly" end
    local fight = Arena.Fights(records, myName, now)[id]
    if not fight or fight.b ~= myName then return nil, "unknown" end
    local state = Arena.State()
    if state.an[id] or state.co[id] then return nil, "answered" end
    if fight.state == "version" then return nil, "version" end
    if fight.state ~= "pending" then return nil, "late" end
    if not accept then
        state.an[id] = { ok = false, at = now }
        addon.AzeCaught.Journal("INFORMATION", "arena.decline", "a challenge was declined", { id = id })
        return true
    end
    if not Arena.SameVersion(records, fight.a) then return nil, "version" end
    if Arena.Busy(Arena.Fights(records, myName, now), myName, true) then return nil, "busy" end
    local team, teamRefusal = Arena.Team(uids)
    if not team then return nil, teamRefusal end
    wager = math.floor(tonumber(wager) or 0)
    if wager < Arena.MINIMUM_WAGER or wager > Arena.MAXIMUM_WAGER then return nil, "wager" end
    local _, refusal = addon.Wallet.Spend(myName, wager, "wager", now, fight.a)
    if refusal then return nil, refusal end
    state.an[id] = { ok = true, at = now, t = team, wg = wager }
    state.uids[id] = { uids[1], uids[2], uids[3] }
    addon.Items.SpendArenaBuffs(team[1].bf)
    addon.AzeCaught.Journal("INFORMATION", "arena.accept", "a challenge was accepted", { id = id, wager = wager, theirs = fight.wager })
    return true
end

-- The fight `id` was watched (the replay started), so its result may be settled and shown.
---@param id string
---@param now integer
function Arena.MarkWatched(id, now)
    local state = Arena.State()
    if type(id) == "string" and not state.watched[id] then state.watched[id] = now end
end

-- Whether a decided fight's result may be shown and settled: I watched it, or REVEAL_AFTER passed since the fight time.
---@param fight ArenaFight
---@param now integer
---@return boolean
function Arena.Revealed(fight, now)
    if not fight or fight.state ~= "done" then return false end
    return Arena.State().watched[fight.id] ~= nil or now + (Arena.devShift[fight.id] or 0) >= fight.fightAt + Arena.REVEAL_AFTER
end

-- Stops my own challenge that was not answered yet. The stake comes back on the next settlement.
-- Reasons: "readonly", "unknown", "late" (answered, or already over).
---@return boolean|nil
---@return string|nil reason
function Arena.Withdraw(records, myName, id, now)
    if addon.Store.db.readonly then return nil, "readonly" end
    local state = Arena.State()
    local challenge = state.ch[id]
    local fight = Arena.Fights(records, myName, now)[id]
    if not challenge or not fight or fight.a ~= myName then return nil, "unknown" end
    if fight.state ~= "pending" and fight.state ~= "lapsed" and fight.state ~= "countered" then return nil, "late" end
    challenge.wd = math.max(now, challenge.at)
    addon.AzeCaught.Journal("INFORMATION", "arena.withdraw", "a challenge was stopped", { id = id, wager = challenge.wg })
    return true
end

-- Bets `stake` copper on `side` ("a" challenger, "b" challenged) of an open fight: the stake joins that side of the
-- pot. Reasons: "readonly", "unknown", "closed", "own", "version", "twice", "side", "stake", "funds".
---@return boolean|nil
---@return string|nil reason
function Arena.Bet(records, myName, id, side, stake, now)
    if addon.Store.db.readonly then return nil, "readonly" end
    local fight = Arena.Fights(records, myName, now)[id]
    if not fight then return nil, "unknown" end
    if fight.state ~= "open" then return nil, "closed" end
    if fight.a == myName or fight.b == myName then return nil, "own" end
    if not Arena.SameVersion(records, fight.a) then return nil, "version" end
    local state = Arena.State()
    if state.bt[id] then return nil, "twice" end
    if side ~= "a" and side ~= "b" then return nil, "side" end
    stake = math.floor(tonumber(stake) or 0)
    if stake < Arena.MINIMUM_BET or stake > Arena.MAXIMUM_BET then return nil, "stake" end
    local _, refusal = addon.Wallet.Spend(myName, stake, "bet", now, id)
    if refusal then return nil, refusal end
    state.bt[id] = { s = side, c = stake, at = now }
    addon.AzeCaught.Journal("INFORMATION", "arena.bet", "a bet was placed", { id = id, side = side, stake = stake })
    return true
end

------------------------------------------------------------------ settlement

local function pay(myName, amount, kind, now, note)
    if amount > 0 then addon.Wallet.Earn(myName, amount, kind, now, note) end
end

-- Settles everything of mine that is due, once each, and cleans old entries. Returns notices
-- { kind = "challenged"|"answered"|"won"|"lost"|"refund"|"betwon"|"betlost", id, ... } for chat.
---@param records table<string, table>
---@param myName string
---@param now integer
---@return table[] notices
---@return boolean changed my section changed (publish)
function Arena.Settle(records, myName, now)
    local state = Arena.State()
    if addon.Store.db.readonly or not myName then return {}, false end
    local notices, changed = {}, false
    -- stakes of one-against-one fights that were still open when every fight became a team fight: back once
    if (state.legacyRefund or 0) > 0 then
        pay(myName, state.legacyRefund, "refund", now, "1v1")
        notices[#notices + 1] = { kind = "refund", id = "1v1", wager = state.legacyRefund, why = "legacy" }
        state.legacyRefund, changed = nil, true
    end
    local fights = Arena.Fights(records, myName, now)
    local function once(key)
        if state.settled[key] then return false end
        state.settled[key] = now
        return true
    end
    local function notice(key, entry)
        if state.noticed[key] then return end
        state.noticed[key] = now
        notices[#notices + 1] = entry
    end
    for id, fight in pairs(fights) do
        local mine = fight.a == myName and "a" or fight.b == myName and "b" or nil
        if fight.b == myName and fight.state == "pending" and not state.an[id] then
            notice("c:" .. id, { kind = "challenged", id = id, from = fight.a, wager = fight.wager })
        end
        if fight.a == myName and fight.answerAt and not fight.counter then
            notice("a:" .. id, { kind = "answered", id = id, by = fight.b, accepted = fight.state ~= "declined" })
        end
        if fight.a == myName and fight.state == "countered" then
            notice("co:" .. id, { kind = "countered", id = id, by = fight.b, wager = fight.counter.wg, offered = fight.wager })
        end
        if fight.b == myName and fight.counter and (fight.answerAt or fight.state == "rejected") then
            notice("ca:" .. id, { kind = "counteranswered", id = id, by = fight.a, accepted = fight.answerAt ~= nil, wager = fight.counter.wg })
        end
        -- (never after the fight itself was settled: a record that vanished, like the dev dummy after a reload, must not pay twice)
        if mine == "a" and (fight.state == "declined" or fight.state == "expired" or fight.state == "withdrawn" or fight.state == "rejected"
            or fight.state == "version")
            and not state.settled["f:" .. id] and once("r:" .. id) then
            pay(myName, fight.wager, "refund", now, fight.b)
            notices[#notices + 1] = { kind = "refund", id = id, opponent = fight.b, wager = fight.wager, why = fight.state }
        end
        -- I accepted, but the challenger had stopped it before (my accept synced late): my stake comes back
        local myAnswer = state.an[id]
        if mine == "b" and (fight.state == "withdrawn" or fight.state == "version") and myAnswer and myAnswer.ok
            and not state.settled["f:" .. id] and once("r:" .. id) then
            local myStake = myAnswer.wg or fight.wager
            pay(myName, myStake, "refund", now, fight.a)
            notices[#notices + 1] = { kind = "refund", id = id, opponent = fight.a, wager = myStake, why = fight.state }
        end
        -- my counter offer was declined, stopped or not answered in time: my counter stake comes back
        local myCounter = state.co[id]
        if mine == "b" and myCounter and (fight.state == "rejected" or fight.state == "withdrawn" or fight.state == "expired"
            or fight.state == "version") and not state.settled["f:" .. id]
            and once("r:" .. id) then
            pay(myName, myCounter.wg, "refund", now, fight.a)
            notices[#notices + 1] = { kind = "refund", id = id, opponent = fight.a, wager = myCounter.wg, why = fight.state }
        end
        -- a decided fight waits until I watched it (or REVEAL_AFTER passed): until then only "it is ready"
        local revealed = Arena.Revealed(fight, now)
        if mine and fight.state == "done" and not revealed and not state.settled["f:" .. id] then
            notice("w:" .. id, { kind = "ready", id = id, opponent = mine == "a" and fight.b or fight.a })
        end
        if mine and revealed and once("f:" .. id) then
            local result = Arena.Result(fight)
            local won = result.winner == mine
            local fighter = mine == "a" and fight.fa or fight.fb
            -- every companion of mine that entered: XP for taking part and for each opponent it beat, its rounds
            local entered, knockouts = result.entered[mine], result.knockouts[mine]
            for slot, uid in ipairs(state.uids[id] or {}) do
                local companion = addon.AzeCaught.Companion(uid)
                if companion and slot <= entered then
                    local progress = Arena.Progress(companion)
                    local beaten = slot < entered or not won
                    progress.xp = progress.xp + Arena.XP_ENTER + Arena.XP_KNOCKOUT * (knockouts[slot] or 0)
                    progress.w = progress.w + (knockouts[slot] or 0)
                    progress.l = progress.l + (beaten and 1 or 0)
                end
            end
            if won then state.w = state.w + 1 else state.l = state.l + 1 end
            -- a stop refunded my stake, then an accept from before the stop turned up: the fight counts, the refund is undone
            local refunded = mine == "a" and state.settled["r:" .. id] and fight.wager or 0
            local myStake = mine == "a" and fight.wager or (fight.wagerB or fight.wager)
            local payout = won and Arena.Payout(Arena.Pot(fight), mine, myName) or 0
            if won then
                pay(myName, payout - refunded, "arena", now, mine == "a" and fight.b or fight.a)
            elseif refunded > 0 then
                addon.Wallet.Spend(myName, refunded, "wager", now, fight.b)
            end
            local opponent = mine == "a" and fight.b or fight.a
            local theirs = mine == "a" and fight.fb or fight.fa
            table.insert(state.history, 1, { id = id, opp = opponent, me = fighter.n, them = theirs.n,
                mi = fighter.npc, mk = fighter.nk, ti = theirs.npc, tk = theirs.nk,
                won = won, wg = myStake, t = fight.fightAt })
            while #state.history > Arena.MAXIMUM_HISTORY do table.remove(state.history) end
            changed = true
            addon.AzeCaught.Journal("INFORMATION", "arena.fight", won and "an arena fight was won" or "an arena fight was lost",
                { id = id, side = mine, wager = myStake, payout = payout, reason = result.reason, actions = #result.events })
            notices[#notices + 1] = { kind = won and "won" or "lost", id = id, opponent = opponent, wager = myStake, payout = payout }
        end
        local bet = state.bt[id]
        if bet and fight.state == "done" and not revealed and not state.settled["b:" .. id] then
            notice("bw:" .. id, { kind = "betready", id = id, fighter = bet.s == "a" and fight.a or fight.b })
        end
        if bet and revealed and once("b:" .. id) then
            local result = Arena.Result(fight)
            local pot = Arena.Pot(fight)
            if not bet.o and not pot.stakes[myName] then
                -- my bet did not make it into the pot (placed too late): it comes back
                pay(myName, bet.c, "refund", now, id)
                notices[#notices + 1] = { kind = "refund", id = id, wager = bet.c, why = "late" }
            else
                local payout = bet.o and (result.winner == bet.s and math.floor(bet.c * bet.o / 100) or 0)
                    or Arena.Payout(pot, result.winner, myName)
                pay(myName, payout, "betwin", now, id)
                notices[#notices + 1] = { kind = payout > 0 and "betwon" or "betlost", id = id, stake = bet.c, payout = payout,
                    fighter = bet.s == "a" and fight.a or fight.b }
            end
        end
    end
    -- a bet whose fight is gone (records pruned) or never happened: refund after the grace time
    for id, bet in pairs(state.bt) do
        local fight = fights[id]
        if (not fight or fight.state == "declined" or fight.state == "expired" or fight.state == "rejected"
            or fight.state == "withdrawn" or fight.state == "version")
            and now > bet.at + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE and once("b:" .. id) then
            pay(myName, bet.c, "refund", now, id)
            notices[#notices + 1] = { kind = "refund", id = id, wager = bet.c, why = "bet" }
        end
    end
    -- my entries leave the record once settled and old
    for _, key in ipairs({ "ch", "an", "bt", "co" }) do
        for id, entry in pairs(state[key]) do
            if now > entry.at + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE + Arena.KEEP_SECONDS then
                state[key][id] = nil
                changed = true
            end
        end
    end
    for id in pairs(state.uids) do
        if not state.ch[id] and not state.an[id] and not state.co[id] then state.uids[id] = nil end
    end
    for key, at in pairs(state.settled) do
        if type(at) ~= "number" or now > at + 2 * Arena.KEEP_SECONDS + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE then state.settled[key] = nil end
    end
    for key, at in pairs(state.noticed) do
        if type(at) ~= "number" or now > at + 2 * Arena.KEEP_SECONDS + Arena.CHALLENGE_TTL then state.noticed[key] = nil end
    end
    for key, at in pairs(state.watched) do
        if type(at) ~= "number" or now > at + 2 * Arena.KEEP_SECONDS + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE then state.watched[key] = nil end
    end
    return notices, changed
end

------------------------------------------------------------------ persistence

-- Re-validates db.caught.arena on load (untrusted). Returns true when something was repaired.
---@param caught table db.caught
---@param me string|nil my character (savedVariables.me; my own challenges are keyed by it)
---@return boolean
function Arena.SanitizePersisted(caught, me)
    local raw = caught.arena
    if raw == nil then return false end
    local SafeInteger = addon.Utility.SafeInteger
    local clean = { settled = {}, noticed = {}, watched = {}, history = {}, uids = {} }
    local repaired = type(raw) ~= "table"
    raw = type(raw) == "table" and raw or {}
    if raw.npcs ~= nil then repaired = true end   -- the progress per NPC moved to the companions (AzeCaught)
    -- one-against-one entries (a single fighter `f`, no team): void; the stakes I paid and that were not settled come
    -- back once (Arena.Settle pays legacyRefund)
    local settled = type(raw.settled) == "table" and raw.settled or {}
    local legacy = SafeInteger(raw.legacyRefund, 0, 1e12) or 0
    for _, key in ipairs({ "ch", "an", "co" }) do
        for id, entry in pairs(type(raw[key]) == "table" and raw[key] or {}) do
            if type(entry) == "table" and entry.t == nil and entry.f ~= nil then
                local stake = SafeInteger(key == "an" and 0 or entry.wg, 0, Arena.MAXIMUM_WAGER) or 0
                if key == "ch" and entry.wd ~= nil then stake = 0 end
                if not settled["f:" .. tostring(id)] and not settled["r:" .. tostring(id)] then legacy = legacy + stake end
                raw[key][id] = nil
                repaired = true
            end
        end
    end
    clean.legacyRefund = legacy > 0 and legacy or nil
    local section = Arena.SanitizeSection({ w = raw.w, l = raw.l, ch = raw.ch, an = raw.an, bt = raw.bt, co = raw.co }, me or "", math.huge)
    if section then
        clean.w, clean.l, clean.ch, clean.an, clean.bt, clean.co = section.w, section.l, section.ch, section.an, section.bt, section.co
    else
        repaired = true
        clean.w, clean.l, clean.ch, clean.an, clean.bt, clean.co = SafeInteger(raw.w, 0, 1e6) or 0, SafeInteger(raw.l, 0, 1e6) or 0, {}, {}, {}, {}
    end
    for _, key in ipairs({ "settled", "noticed", "watched" }) do
        for id, at in pairs(type(raw[key]) == "table" and raw[key] or {}) do
            if type(id) == "string" and #id <= 90 and SafeInteger(at, 0) then clean[key][id] = at else repaired = true end
        end
    end
    for _, entry in ipairs(type(raw.history) == "table" and raw.history or {}) do
        if type(entry) == "table" and type(entry.id) == "string" and addon.Utility.IsSafeName(entry.opp) and #clean.history < Arena.MAXIMUM_HISTORY then
            clean.history[#clean.history + 1] = { id = entry.id, opp = entry.opp, me = addon.Utility.CleanString(entry.me, 48) or "?",
                them = addon.Utility.CleanString(entry.them, 48) or "?", won = entry.won == true, wg = SafeInteger(entry.wg, 0, Arena.MAXIMUM_WAGER) or 0,
                t = SafeInteger(entry.t, 0) or 0,
                mi = SafeInteger(entry.mi, 1, addon.AzeCaught.MAXIMUM_ID), mk = addon.AzeCaught.CleanNickname(entry.mk),
                ti = SafeInteger(entry.ti, 1, addon.AzeCaught.MAXIMUM_ID), tk = addon.AzeCaught.CleanNickname(entry.tk) }
        end
    end
    -- my team per fight (roster uids, local only); a uid that left the roster stays and is skipped when settling
    for id, uids in pairs(type(raw.uids) == "table" and raw.uids or {}) do
        local valid = type(id) == "string" and #id <= 90 and type(uids) == "table" and #uids == Arena.TEAM_SIZE
        if valid then
            for index = 1, Arena.TEAM_SIZE do
                if type(uids[index]) ~= "string" or addon.AzeCaught.UidNumber(uids[index]) == math.huge then valid = false end
            end
        end
        if valid and (clean.ch[id] or clean.an[id] or clean.co[id]) then
            clean.uids[id] = { uids[1], uids[2], uids[3] }
        else
            repaired = true
        end
    end
    local training = raw.training
    local roster = type(caught.roster) == "table" and caught.roster or {}
    if type(training) == "table" and type(training.uid) == "string" and roster[training.uid] and addon.Utility.IsFinite(training.done) then
        for _, stat in ipairs(Arena.STATS) do
            if stat == training.stat then clean.training = { stat = stat, uid = training.uid, done = training.done } end
        end
    end
    if training ~= nil and not clean.training then repaired = true end
    caught.arena = clean
    return repaired
end

------------------------------------------------------------------ the dev dummy (dev build only)

-- A fake guild member for testing the arena alone: a record in Games.simulated (memory only: never stored, never sent).
Arena.DUMMY_NAME = "Arenadummy-Test"

-- The dummy's record: a team of TEAM_SIZE that mirrors my fighters (the models always load), each with stats
-- -15%..+15% from `seed`. It runs my version.
---@param myTeam Fighter[]|Fighter|nil my fighters (fewer than TEAM_SIZE: repeated; none: wolves)
---@param now integer
---@param seed? integer
---@return table record
function Arena.DummyRecord(myTeam, now, seed)
    if type(myTeam) == "table" and myTeam.atk then myTeam = { myTeam } end
    myTeam = type(myTeam) == "table" and #myTeam > 0 and myTeam
        or { { npc = 299, n = "Young Wolf", cls = "normal", disp = 0, ty = 1, al = 1, atk = 40, def = 40, spd = 40, vit = 40, ab = "rend" } }
    local random = generator((math.floor(seed or now) % (MODULUS - 1)) + 1)
    local team = {}
    for index = 1, Arena.TEAM_SIZE do
        local base = myTeam[(index - 1) % #myTeam + 1]
        local fighter = addon.Utility.DeepCopy(base)
        fighter.bf = nil
        for _, stat in ipairs(Arena.STATS) do
            fighter[stat] = math.max(1, math.floor(base[stat] * (0.85 + 0.3 * random()) + 0.5))
        end
        fighter.nk = "Dummy " .. index   -- a nickname like a player's: the species stays on hover
        team[index] = fighter
    end
    local first = team[1]
    return { name = Arena.DUMMY_NAME, rev = now, dummyTeam = team,
        caught = { weeks = {}, c = { npc = first.npc, n = first.n, lvl = 20, cls = first.cls, disp = first.disp, h = 0,
            hu = 80, th = 80, af = 60, en = 90, fs = 0 } },
        arena = { w = 0, l = 0, ver = addon.VERSION, ch = {}, an = {}, bt = {}, co = {} } }
end

-- Dev: the dummy's open fights (with me) are decided at `now` instead of after the bet window. Only fights with the
-- dummy (a memory-only record, so no real player computes them differently). Returns the number cut short.
Arena.skipped = {}
---@param records table<string, table>
---@param myName string
---@param now integer
---@return integer
function Arena.SkipDummyWait(records, myName, now)
    local count = 0
    for id, fight in pairs(Arena.Fights(records, myName, now)) do
        if fight.state == "open" and (fight.a == Arena.DUMMY_NAME or fight.b == Arena.DUMMY_NAME) then
            Arena.skipped[id] = now
            count = count + 1
        end
    end
    return count
end

Arena.DUMMY_DELAY = 20   -- seconds the dummy waits before it accepts on its own (time for the dev decline button)

-- The dummy's own wager for a challenge: 0.5x..2x the challenger's, from the fight id (the same on every call).
---@param id string
---@param theirs integer
---@return integer
function Arena.DummyWager(id, theirs)
    local factor = 50 + Arena.Seed(id) % 151
    return addon.Utility.Clamp(math.floor((theirs or 0) * factor / 100), Arena.MINIMUM_WAGER, Arena.MAXIMUM_WAGER)
end

-- The dummy answers my pending challenges to it: with `onlyID` that one at once (`accept` false declines), without it
-- every challenge older than DUMMY_DELAY is accepted with the dummy's own wager. Returns the number answered.
---@param dummy table the dummy's record
---@param myName string
---@param now integer
---@param onlyID? string
---@param accept? boolean
---@return integer
function Arena.DummyRespond(dummy, myName, now, onlyID, accept)
    local answered = 0
    for id, challenge in pairs(Arena.State().ch) do
        if challenge.to == dummy.name and not dummy.arena.an[id] and not challenge.wd and now <= challenge.at + Arena.CHALLENGE_TTL
            and (onlyID == id or (not onlyID and now >= challenge.at + Arena.DUMMY_DELAY)) then
            if onlyID and accept == false then
                dummy.arena.an[id] = { ok = false, at = math.max(now, challenge.at) }
            else
                dummy.arena.an[id] = { ok = true, at = math.max(now, challenge.at), t = addon.Utility.DeepCopy(dummy.dummyTeam),
                    wg = Arena.DummyWager(id, challenge.wg) }
            end
            answered = answered + 1
        end
    end
    if answered > 0 then dummy.rev = now end
    return answered
end

-- The dummy challenges me with `wager` copper. Returns the fight id.
---@param dummy table
---@param myName string
---@param wager integer
---@param now integer
---@return string id
function Arena.DummyChallenge(dummy, myName, wager, now)
    local at = now
    while dummy.arena.ch[dummy.name .. "#" .. at] do at = at + 1 end
    local id = dummy.name .. "#" .. at
    dummy.arena.ch[id] = { to = myName, at = at, wg = addon.Utility.Clamp(math.floor(tonumber(wager) or 0), Arena.MINIMUM_WAGER, Arena.MAXIMUM_WAGER),
        t = addon.Utility.DeepCopy(dummy.dummyTeam) }
    dummy.rev = now
    return id
end

------------------------------------------------------------------ dev events (dev build only, memory only)

-- Fake fights, members and bettors for trying the request, the pot and the dropdown alone. They live in
-- Games.simulated (never stored, never sent) and in the tables below; Arena.DevClear removes them all.
Arena.devShift = {}     -- fight id -> seconds a fake fight is moved forward in time (expire, reveal)
Arena.devOffline = {}   -- fake member -> true: shown as offline in the dropdown
Arena.devNames = {}     -- fake records made here
Arena.DEV_BETTORS = 4

-- A fake member's record, a copy of the dummy's (its companion and team), on my version with a team's worth of companions.
local function fakeRecord(simulated, name, now)
    local dummy = simulated[Arena.DUMMY_NAME] or Arena.DummyRecord(nil, now)
    local record = addon.Utility.DeepCopy(dummy)
    record.name, record.rev = name, now
    record.caught.rc = Arena.TEAM_SIZE
    record.arena = { w = 0, l = 0, ver = addon.VERSION, ch = {}, an = {}, bt = {}, co = {} }
    simulated[name] = record
    Arena.devNames[name] = true
    return record
end

-- Fake bettors place one bet each on both sides of the open fight `id`. Returns the number of bets, or nil and
-- "closed" when the fight is not open.
---@param simulated table<string, table> Games.simulated
---@return integer|nil
---@return string|nil reason
function Arena.DevCrowd(records, simulated, myName, id, now, seed)
    local fight = id and Arena.Fights(records, myName, now)[id]
    if not fight or fight.state ~= "open" then return nil, "closed" end
    local random = generator((math.floor(seed or now) % (MODULUS - 1)) + 1)
    for index = 1, Arena.DEV_BETTORS do
        local record = fakeRecord(simulated, "Bettor" .. string.char(64 + index) .. "-Test", now)
        record.arena.bt[id] = { s = index % 2 == 1 and "a" or "b", c = (1 + math.floor(random() * 20)) * 10000,
            at = math.max(now, fight.answerAt or now) }
    end
    return Arena.DEV_BETTORS
end

-- A fake bet on the accepted fight `id` stamped at its fight time: too late, it must stay out of the pot.
---@return boolean|nil
---@return string|nil reason
function Arena.DevLateBet(records, simulated, myName, id, now)
    local fight = id and Arena.Fights(records, myName, now)[id]
    if not fight or not fight.fightAt then return nil, "closed" end
    local record = fakeRecord(simulated, "Latebettor-Test", now)
    record.arena.bt[id] = { s = "a", c = 50000, at = fight.fightAt }
    return true
end

Arena.DEV_SPARRING = "Sparring-Test"   -- the fake member that can be challenged (it answers like the dummy)

-- Fake members for the dropdown: one that can be challenged (it accepts like the dummy) and one per greyed reason:
-- another version, fewer than 3 companions, in a fight (with a partner), offline. Returns the names shown.
---@return string[]
function Arena.DevMembers(simulated, now)
    fakeRecord(simulated, Arena.DEV_SPARRING, now)
    local old = fakeRecord(simulated, "Oldversion-Test", now); old.arena.ver = "0.0.0-old"
    local few = fakeRecord(simulated, "Fewpets-Test", now); few.caught.rc = Arena.TEAM_SIZE - 1
    local busy = fakeRecord(simulated, "Busy-Test", now)
    local pal = fakeRecord(simulated, "Busypal-Test", now)
    local id = "Busy-Test#" .. now
    busy.arena.ch[id] = { to = "Busypal-Test", at = now, wg = Arena.MINIMUM_WAGER, t = addon.Utility.DeepCopy(busy.dummyTeam) }
    pal.arena.an[id] = { ok = true, at = now, t = addon.Utility.DeepCopy(pal.dummyTeam), wg = Arena.MINIMUM_WAGER }
    fakeRecord(simulated, "Offline-Test", now)
    Arena.devOffline["Offline-Test"] = true
    return { Arena.DEV_SPARRING, "Oldversion-Test", "Fewpets-Test", "Busy-Test", "Offline-Test" }
end

-- The fake members that answer my challenges: the dummy and the sparring member (when they are there).
---@return table[] records
function Arena.DevResponders(simulated)
    local list = {}
    for _, name in ipairs({ Arena.DUMMY_NAME, Arena.DEV_SPARRING }) do
        if simulated[name] then list[#list + 1] = simulated[name] end
    end
    return list
end

-- A fake member answers my waiting challenge to it now (accept with its own wager, or decline). Returns the number
-- answered.
---@return integer
function Arena.DevAnswer(simulated, myName, now, accept)
    for _, responder in ipairs(Arena.DevResponders(simulated)) do
        for id, challenge in pairs(Arena.State().ch) do
            if challenge.to == responder.name and not responder.arena.an[id] then
                return Arena.DummyRespond(responder, myName, now, id, accept)
            end
        end
    end
    return 0
end

-- Moves fake fights forward: "expire" (waiting challenges with a fake member: past the time to live and the grace, so
-- the stake comes back) or "reveal" (decided fights nobody watched: past REVEAL_AFTER, so they settle). Only fights
-- with a fake member: a real player's fight never changes. Returns the number moved.
---@param kind "expire"|"reveal"
---@return integer
function Arena.DevShift(records, simulated, myName, now, kind)
    local count = 0
    for id, fight in pairs(Arena.Fights(records, myName, now)) do
        local fake = simulated[fight.a] ~= nil or simulated[fight.b] ~= nil
        if fake and kind == "expire" and (fight.state == "pending" or fight.state == "lapsed" or fight.state == "countered") then
            Arena.devShift[id] = (Arena.devShift[id] or 0) + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE + 1
            count = count + 1
        elseif fake and kind == "reveal" and fight.state == "done" and not Arena.Revealed(fight, now) then
            Arena.devShift[id] = (Arena.devShift[id] or 0) + Arena.REVEAL_AFTER
            count = count + 1
        end
    end
    return count
end

-- Removes every fake member, bettor and time shift, and the dummy. Returns the number of records removed.
---@return integer
function Arena.DevClear(simulated)
    local count = 0
    for name in pairs(Arena.devNames) do
        if simulated[name] then simulated[name] = nil; count = count + 1 end
    end
    if simulated[Arena.DUMMY_NAME] then simulated[Arena.DUMMY_NAME] = nil; count = count + 1 end
    Arena.devNames, Arena.devOffline, Arena.devShift, Arena.skipped = {}, {}, {}, {}
    return count
end
