local _, addon = ...

-- Companion arena (feature 020): guild members' companions fight in a hands-off auto battle. Challenges, answers and
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
Arena.XP_WIN, Arena.XP_LOSS = 40, 15
Arena.XP_PER_LEVEL = 50              -- level n -> n + 1 needs n x 50 XP
Arena.MAXIMUM_LEVEL = 50
Arena.LEVEL_BONUS = 0.03             -- +3% on every stat per level above 1
Arena.HEALTH_PER_VITALITY = 8
Arena.MAXIMUM_ACTIONS = 80           -- then the higher health share wins
Arena.ABILITY_EVERY = 3              -- every 3rd action of a fighter is its ability
Arena.CHALLENGE_TTL = 24 * 3600      -- an unanswered challenge expires (refund)
Arena.ANSWER_GRACE = 24 * 3600       -- the refund waits this long more: a late-synced answer still counts
Arena.BET_WINDOW = 300               -- the fight is decided this long after the accept; bets until then
Arena.KEEP_SECONDS = 3 * 86400       -- settled entries leave my record after this
Arena.MAXIMUM_WAGER = 1000 * 10000   -- 1000g
Arena.MINIMUM_BET, Arena.MAXIMUM_BET = 1000, 500 * 10000
Arena.ODDS_LIMITS = { 110, 1000 }    -- hundredths: 1.1x .. 10x
Arena.MAXIMUM_OPEN = 3               -- my open challenges
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

---@class ArenaNpc
---@field xp integer
---@field w integer
---@field l integer
---@field tr table<string, integer> training points by stat

---@return table db.caught.arena, created on first use
function Arena.State()
    local caught = addon.AzeCaught.State()
    local state = caught.arena
    if type(state) ~= "table" then
        state = {}
        caught.arena = state
    end
    state.npcs = state.npcs or {}
    state.ch, state.an, state.bt = state.ch or {}, state.an or {}, state.bt or {}
    state.settled, state.noticed, state.history = state.settled or {}, state.noticed or {}, state.history or {}
    state.w, state.l = state.w or 0, state.l or 0
    return state
end

---@param npcID integer
---@return ArenaNpc
function Arena.Npc(npcID)
    local npcs = Arena.State().npcs
    local entry = npcs[npcID]
    if not entry then
        entry = { xp = 0, w = 0, l = 0, tr = { atk = 0, def = 0, spd = 0, vit = 0 } }
        npcs[npcID] = entry
    end
    return entry
end

------------------------------------------------------------------ levels and training (R2, R3)

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
    local npc = Arena.Npc(companion.npc)
    if npc.tr[stat] >= Arena.MAXIMUM_TRAINING then return nil, "maximum" end
    if companion.asleep then return nil, "asleep" end
    if companion.energy < Arena.TRAIN_ENERGY then return nil, "energy" end
    local cost = Arena.TrainCost(npc.tr[stat])
    local _, refusal = addon.Wallet.Spend(myName, cost, "train", now, companion.n)
    if refusal then return nil, refusal end
    companion.energy = companion.energy - Arena.TRAIN_ENERGY
    state.training = { stat = stat, npc = companion.npc, done = AzeCaught.State().activeSeconds + Arena.TRAIN_SECONDS }
    AzeCaught.Journal("INFORMATION", "arena.train", "a training session started", { stat = stat, npc = companion.npc, cost = cost })
    return true
end

-- Seconds of active time the running session still needs, or nil when none runs.
---@return number|nil
function Arena.TrainingLeft()
    local training = Arena.State().training
    if not training then return nil end
    return math.max(0, training.done - addon.AzeCaught.State().activeSeconds)
end

-- Finishes the session when its time has passed. Returns {stat, npc, points} once, else nil.
---@return table|nil
function Arena.FinishTraining()
    local state = Arena.State()
    local training = state.training
    if not training or addon.AzeCaught.State().activeSeconds < training.done then return nil end
    state.training = nil
    local npc = Arena.Npc(training.npc)
    npc.tr[training.stat] = math.min(Arena.MAXIMUM_TRAINING, npc.tr[training.stat] + 1)
    addon.AzeCaught.Journal("INFORMATION", "arena.trained", "a training session finished",
        { stat = training.stat, npc = training.npc, points = npc.tr[training.stat] })
    return { stat = training.stat, npc = training.npc, points = npc.tr[training.stat] }
end

------------------------------------------------------------------ fighters (R1)

---@class Fighter
---@field npc integer
---@field n string NPC name
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
-- -10% when hungry or thirsty. Nil without a collection entry.
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
    local npc = Arena.Npc(companion.npc)
    local level = Arena.Level(npc.xp)
    local morale = 1 + addon.Utility.Clamp(companion.hearts or 0, -10, 10) / 100
    local fighter = { npc = companion.npc, n = entry.n, cls = entry.cls, disp = entry.disp or 0,
        ty = type(entry.st) == "table" and entry.st.type or 0, al = level }
    for _, stat in ipairs(Arena.STATS) do
        local factor = (1 + Arena.TRAIN_BONUS * npc.tr[stat]) * (1 + Arena.LEVEL_BONUS * (level - 1)) * morale
        fighter[stat] = math.max(1, math.min(Arena.MAXIMUM_STAT, math.floor(values[stat] * factor + 0.5)))
    end
    local zones = companion.zones or {}
    if (zones.hunger and zones.hunger ~= "ok") or (zones.thirst and zones.thirst ~= "ok") then
        fighter.atk = math.max(1, math.floor(fighter.atk * 0.9 + 0.5))
    end
    fighter.ab = Arena.ABILITY_BY_TYPE[fighter.ty] or "strike"
    return fighter
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
    return clean
end

------------------------------------------------------------------ the battle (R4)

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
---@field s string "a" or "b": who acts
---@field k string "hit", "crit", "dodge", "dot", "stun", "shield", "focus"
---@field ab? string ability used
---@field d? integer damage (or shield / heal amount)
---@field heal? integer
---@field ha integer a's health after the event
---@field hb integer b's health after the event

---@class FightResult
---@field winner string "a" or "b"
---@field events FightEvent[]
---@field maxA integer
---@field maxB integer
---@field reason string "ko" or "time"

-- Fights `a` against `b` (fighter snapshots). The same inputs always give the same result.
---@param a Fighter
---@param b Fighter
---@param id string fight id (the seed)
---@return FightResult
function Arena.Fight(a, b, id)
    local random = generator(Arena.Seed(id))
    local sides = {}
    for key, fighter in pairs({ a = a, b = b }) do
        local maximum = fighter.vit * Arena.HEALTH_PER_VITALITY
        sides[key] = { f = fighter, hp = maximum, max = maximum, gauge = 0, shield = 0, dot = 0, dotTurns = 0,
            focus = false, stunned = false, actions = 0 }
    end
    -- a random head start (0..25 of the 100-point gauge): with equal speed the challenger would always act first
    sides.a.gauge, sides.b.gauge = random() * 25, random() * 25
    local events = {}
    local function log(event)
        event.ha, event.hb = sides.a.hp, sides.b.hp
        events[#events + 1] = event
    end
    local function hurt(target, amount)
        local absorbed = math.min(target.shield, amount)
        target.shield = target.shield - absorbed
        target.hp = math.max(0, target.hp - (amount - absorbed))
    end
    local winner, reason
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
    return { winner = winner, events = events, maxA = sides.a.max, maxB = sides.b.max, reason = reason }
end

-- The share of fights `a` wins against `b` (CHANCE_SAMPLES fights with derived ids; deterministic).
---@param a Fighter
---@param b Fighter
---@param id string
---@return number 0..1
function Arena.WinChance(a, b, id)
    local wins = 0
    for index = 1, Arena.CHANCE_SAMPLES do
        if Arena.Fight(a, b, id .. "~" .. index).winner == "a" then wins = wins + 1 end
    end
    return wins / Arena.CHANCE_SAMPLES
end

-- Fixed odds in hundredths for a side with win chance `chance` (0.95 / chance, ODDS_LIMITS).
---@param chance number
---@return integer
function Arena.Odds(chance)
    chance = math.max(0.001, tonumber(chance) or 0)
    return addon.Utility.Clamp(math.floor(95 / chance), Arena.ODDS_LIMITS[1], Arena.ODDS_LIMITS[2])
end

------------------------------------------------------------------ record section (R5-R8)

-- My section for the game record: totals and the open entries (copies; the record is replaced as a whole).
---@return table
function Arena.BuildSection()
    local state = Arena.State()
    local section = { w = state.w, l = state.l, ch = {}, an = {}, bt = {} }
    for _, key in ipairs({ "ch", "an", "bt" }) do
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
    local clean = { w = SafeInteger(section.w or 0, 0, 1000000), l = SafeInteger(section.l or 0, 0, 1000000), ch = {}, an = {}, bt = {} }
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
        local wager, fighter = SafeInteger(entry.wg or 0, 0, Arena.MAXIMUM_WAGER), Arena.SanitizeFighter(entry.f)
        if not Utility.IsSafeName(to) or to == owner or not at or at ~= idTime or not wager or not fighter then return nil end
        return { to = to, at = at, wg = wager, f = fighter }
    end) and each("an", function(entry, challenger)
        if challenger == owner then return nil end
        local at = SafeInteger(entry.at, 0, horizon)
        if not at or type(entry.ok) ~= "boolean" then return nil end
        local fighter = entry.ok and Arena.SanitizeFighter(entry.f) or nil
        if entry.ok and not fighter then return nil end
        return { ok = entry.ok, at = at, f = fighter }
    end) and each("bt", function(entry, challenger)
        if challenger == owner then return nil end
        local side, stake = entry.s, SafeInteger(entry.c, Arena.MINIMUM_BET, Arena.MAXIMUM_BET)
        local odds, at = SafeInteger(entry.o, Arena.ODDS_LIMITS[1], Arena.ODDS_LIMITS[2]), SafeInteger(entry.at, 0, horizon)
        if (side ~= "a" and side ~= "b") or not stake or not odds or not at then return nil end
        return { s = side, c = stake, o = odds, at = at }
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
---@field wager integer
---@field fa Fighter
---@field fb Fighter|nil
---@field state string "pending", "declined", "expired", "open", "done"
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
            local fight = { id = id, a = name, b = challenge.to, at = challenge.at, wager = challenge.wg or 0, fa = challenge.f, bets = {} }
            local answers = sectionOf(records, challenge.to, myName)
            local answer = answers and answers.an and answers.an[id]
            -- an answer only counts from the challenged player, inside the challenge's lifetime
            if answer and answer.at >= challenge.at and answer.at <= challenge.at + Arena.CHALLENGE_TTL then
                fight.answerAt = answer.at
                if answer.ok then
                    fight.fb, fight.fightAt = answer.f, answer.at + Arena.BET_WINDOW
                    fight.state = now >= fight.fightAt and "done" or "open"
                else
                    fight.state = "declined"
                end
            else
                fight.state = now > challenge.at + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE and "expired"
                    or now > challenge.at + Arena.CHALLENGE_TTL and "lapsed" or "pending"
            end
            fights[id] = fight
        end
    end
    for name in pairs(names) do
        local section = sectionOf(records, name, myName)
        for id, bet in pairs(section and section.bt or {}) do
            local fight = fights[id]
            if fight and name ~= fight.a and name ~= fight.b and fight.fightAt and bet.at < fight.fightAt and bet.at >= (fight.answerAt or 0) then
                fight.bets[name] = bet
            end
        end
    end
    return fights
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
    cached = Arena.Fight(fight.fa, fight.fb, fight.id)
    resultCache[fight.id] = cached
    return cached
end

local chanceCache = {}
-- a's win chance for a fight (cached).
---@param fight ArenaFight
---@return number|nil
function Arena.Chance(fight)
    if not fight or not fight.fb then return nil end
    if chanceCache[fight.id] == nil then chanceCache[fight.id] = Arena.WinChance(fight.fa, fight.fb, fight.id) end
    return chanceCache[fight.id]
end

------------------------------------------------------------------ actions (each returns true or nil, reason)

-- Challenges `opponent` (who must have a companion in their record) with `wager` copper. Reasons: "readonly",
-- "nocompanion", "self", "opponent", "nocompanionthere", "open", "twice", "wager", "funds".
---@return string|nil id
---@return string|nil reason
function Arena.Challenge(records, myName, opponent, wager, now)
    if addon.Store.db.readonly then return nil, "readonly" end
    local companion = addon.AzeCaught.Active()
    if not companion then return nil, "nocompanion" end
    if opponent == myName then return nil, "self" end
    if not addon.Utility.IsSafeName(opponent) then return nil, "opponent" end
    local theirs = records and records[opponent]
    if not (type(theirs) == "table" and type(theirs.caught) == "table" and type(theirs.caught.c) == "table") then
        return nil, "nocompanionthere"
    end
    wager = math.floor(tonumber(wager) or 0)
    if wager < 0 or wager > Arena.MAXIMUM_WAGER then return nil, "wager" end
    local state = Arena.State()
    local open = 0
    for _, fight in pairs(Arena.Fights(records, myName, now)) do
        if fight.a == myName and (fight.state == "pending" or fight.state == "lapsed" or fight.state == "open") then
            open = open + 1
            if fight.b == opponent then return nil, "twice" end
        end
    end
    if open >= Arena.MAXIMUM_OPEN or addon.Utility.Count(state.ch) >= Arena.MAXIMUM_ENTRIES then return nil, "open" end
    local fighter = Arena.Fighter(companion)
    if not fighter then return nil, "nocompanion" end
    local at = now
    while state.ch[myName .. "#" .. at] do at = at + 1 end
    local id = myName .. "#" .. at
    if wager > 0 then
        local _, refusal = addon.Wallet.Spend(myName, wager, "wager", now, opponent)
        if refusal then return nil, refusal end
    end
    state.ch[id] = { to = opponent, at = at, wg = wager, f = fighter }
    addon.AzeCaught.Journal("INFORMATION", "arena.challenge", "a challenge was sent", { id = id, to = opponent, wager = wager })
    return id
end

-- Accepts or declines a challenge to me. Reasons: "readonly", "unknown", "answered", "late", "nocompanion", "funds".
---@return boolean|nil
---@return string|nil reason
function Arena.Answer(records, myName, id, accept, now)
    if addon.Store.db.readonly then return nil, "readonly" end
    local fight = Arena.Fights(records, myName, now)[id]
    if not fight or fight.b ~= myName then return nil, "unknown" end
    local state = Arena.State()
    if state.an[id] or fight.state ~= "pending" then return nil, fight.state == "pending" and "answered" or "late" end
    if not accept then
        state.an[id] = { ok = false, at = now }
        addon.AzeCaught.Journal("INFORMATION", "arena.decline", "a challenge was declined", { id = id })
        return true
    end
    local fighter = Arena.Fighter(addon.AzeCaught.Active())
    if not fighter then return nil, "nocompanion" end
    if fight.wager > 0 then
        local _, refusal = addon.Wallet.Spend(myName, fight.wager, "wager", now, fight.a)
        if refusal then return nil, refusal end
    end
    state.an[id] = { ok = true, at = now, f = fighter }
    addon.AzeCaught.Journal("INFORMATION", "arena.accept", "a challenge was accepted", { id = id, wager = fight.wager })
    return true
end

-- Bets `stake` copper on `side` ("a" challenger, "b" challenged) of an open fight. Reasons: "readonly", "unknown",
-- "closed", "own", "twice", "side", "stake", "funds".
---@return integer|nil odds hundredths
---@return string|nil reason
function Arena.Bet(records, myName, id, side, stake, now)
    if addon.Store.db.readonly then return nil, "readonly" end
    local fight = Arena.Fights(records, myName, now)[id]
    if not fight then return nil, "unknown" end
    if fight.state ~= "open" then return nil, "closed" end
    if fight.a == myName or fight.b == myName then return nil, "own" end
    local state = Arena.State()
    if state.bt[id] then return nil, "twice" end
    if side ~= "a" and side ~= "b" then return nil, "side" end
    stake = math.floor(tonumber(stake) or 0)
    if stake < Arena.MINIMUM_BET or stake > Arena.MAXIMUM_BET then return nil, "stake" end
    local chance = Arena.Chance(fight)
    local odds = Arena.Odds(side == "a" and chance or 1 - chance)
    local _, refusal = addon.Wallet.Spend(myName, stake, "bet", now, id)
    if refusal then return nil, refusal end
    state.bt[id] = { s = side, c = stake, o = odds, at = now }
    addon.AzeCaught.Journal("INFORMATION", "arena.bet", "a bet was placed", { id = id, side = side, stake = stake, odds = odds })
    return odds
end

------------------------------------------------------------------ settlement (R7, R8, RF2)

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
        if fight.a == myName and fight.answerAt then
            notice("a:" .. id, { kind = "answered", id = id, by = fight.b, accepted = fight.state ~= "declined" })
        end
        if mine == "a" and (fight.state == "declined" or fight.state == "expired") and once("r:" .. id) then
            pay(myName, fight.wager, "refund", now, fight.b)
            notices[#notices + 1] = { kind = "refund", id = id, opponent = fight.b, wager = fight.wager, why = fight.state }
        end
        if mine and fight.state == "done" and once("f:" .. id) then
            local result = Arena.Result(fight)
            local won = result.winner == mine
            local fighter = mine == "a" and fight.fa or fight.fb
            local npc = Arena.Npc(fighter.npc)
            npc.xp = npc.xp + (won and Arena.XP_WIN or Arena.XP_LOSS)
            if won then npc.w, state.w = npc.w + 1, state.w + 1 else npc.l, state.l = npc.l + 1, state.l + 1 end
            if won then pay(myName, fight.wager * 2, "arena", now, mine == "a" and fight.b or fight.a) end
            local opponent = mine == "a" and fight.b or fight.a
            table.insert(state.history, 1, { id = id, opp = opponent, me = fighter.n, them = (mine == "a" and fight.fb or fight.fa).n,
                won = won, wg = fight.wager, t = fight.fightAt })
            while #state.history > Arena.MAXIMUM_HISTORY do table.remove(state.history) end
            changed = true
            addon.AzeCaught.Journal("INFORMATION", "arena.fight", won and "an arena fight was won" or "an arena fight was lost",
                { id = id, side = mine, wager = fight.wager, reason = result.reason, actions = #result.events })
            notices[#notices + 1] = { kind = won and "won" or "lost", id = id, opponent = opponent, wager = fight.wager }
        end
        local bet = state.bt[id]
        if bet and fight.state == "done" and once("b:" .. id) then
            local result = Arena.Result(fight)
            local payout = result.winner == bet.s and math.floor(bet.c * bet.o / 100) or 0
            pay(myName, payout, "betwin", now, id)
            notices[#notices + 1] = { kind = payout > 0 and "betwon" or "betlost", id = id, stake = bet.c, payout = payout,
                fighter = bet.s == "a" and fight.a or fight.b }
        end
    end
    -- a bet whose fight is gone (records pruned) or never happened: refund after the grace time
    for id, bet in pairs(state.bt) do
        local fight = fights[id]
        if (not fight or fight.state == "declined" or fight.state == "expired")
            and now > bet.at + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE and once("b:" .. id) then
            pay(myName, bet.c, "refund", now, id)
            notices[#notices + 1] = { kind = "refund", id = id, wager = bet.c, why = "bet" }
        end
    end
    -- my entries leave the record once settled and old
    for _, key in ipairs({ "ch", "an", "bt" }) do
        for id, entry in pairs(state[key]) do
            if now > entry.at + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE + Arena.KEEP_SECONDS then
                state[key][id] = nil
                changed = true
            end
        end
    end
    for key, at in pairs(state.settled) do
        if type(at) ~= "number" or now > at + 2 * Arena.KEEP_SECONDS + Arena.CHALLENGE_TTL + Arena.ANSWER_GRACE then state.settled[key] = nil end
    end
    for key, at in pairs(state.noticed) do
        if type(at) ~= "number" or now > at + 2 * Arena.KEEP_SECONDS + Arena.CHALLENGE_TTL then state.noticed[key] = nil end
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
    local clean = { npcs = {}, settled = {}, noticed = {}, history = {} }
    local repaired = type(raw) ~= "table"
    raw = type(raw) == "table" and raw or {}
    for npcID, entry in pairs(type(raw.npcs) == "table" and raw.npcs or {}) do
        local id = SafeInteger(npcID, 1, addon.AzeCaught.MAXIMUM_ID)
        if id and type(entry) == "table" and type(entry.tr) == "table" and addon.Utility.Count(clean.npcs) < addon.AzeCaught.MAXIMUM_COLLECTION then
            local npc = { xp = SafeInteger(entry.xp, 0, 1e9) or 0, w = SafeInteger(entry.w, 0, 1e6) or 0, l = SafeInteger(entry.l, 0, 1e6) or 0, tr = {} }
            for _, stat in ipairs(Arena.STATS) do npc.tr[stat] = SafeInteger(entry.tr[stat], 0, Arena.MAXIMUM_TRAINING) or 0 end
            clean.npcs[id] = npc
        else
            repaired = true
        end
    end
    local section = Arena.SanitizeSection({ w = raw.w, l = raw.l, ch = raw.ch, an = raw.an, bt = raw.bt }, me or "", math.huge)
    if section then
        clean.w, clean.l, clean.ch, clean.an, clean.bt = section.w, section.l, section.ch, section.an, section.bt
    else
        repaired = true
        clean.w, clean.l, clean.ch, clean.an, clean.bt = SafeInteger(raw.w, 0, 1e6) or 0, SafeInteger(raw.l, 0, 1e6) or 0, {}, {}, {}
    end
    for _, key in ipairs({ "settled", "noticed" }) do
        for id, at in pairs(type(raw[key]) == "table" and raw[key] or {}) do
            if type(id) == "string" and #id <= 90 and SafeInteger(at, 0) then clean[key][id] = at else repaired = true end
        end
    end
    for _, entry in ipairs(type(raw.history) == "table" and raw.history or {}) do
        if type(entry) == "table" and type(entry.id) == "string" and addon.Utility.IsSafeName(entry.opp) and #clean.history < Arena.MAXIMUM_HISTORY then
            clean.history[#clean.history + 1] = { id = entry.id, opp = entry.opp, me = addon.Utility.CleanString(entry.me, 48) or "?",
                them = addon.Utility.CleanString(entry.them, 48) or "?", won = entry.won == true, wg = SafeInteger(entry.wg, 0, Arena.MAXIMUM_WAGER) or 0,
                t = SafeInteger(entry.t, 0) or 0 }
        end
    end
    local training = raw.training
    if type(training) == "table" and clean.npcs[training.npc] and addon.Utility.IsFinite(training.done) then
        for _, stat in ipairs(Arena.STATS) do
            if stat == training.stat then clean.training = { stat = stat, npc = training.npc, done = training.done } end
        end
    end
    caught.arena = clean
    return repaired
end
