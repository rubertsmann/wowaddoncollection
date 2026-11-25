local addonName, addon = ...

-- Companion Dash, the runner game. Pure Lua: physics, spawning, collision, distance, the daily payout, the local stats and
-- the guild section, so it all runs offline. UI/RunnerView.lua draws a run and forwards the input.
--
-- The companion runs to the right on the ground line; monsters from the collection come from the right. Ground monsters
-- are jumped over, flying ones (bats, birds, dragonkin, ...) come at head height and are ducked under. Every monster has
-- the same box. One collision ends the run; the speed rises steadily up to a cap and the gaps shrink with it.
--
-- Free play: no stake. A finished run pays 1g per full 100 m into the money pool, at most DAILY_CAP_GOLD per server day.
-- The run is booked when it ends; a run cut short by /reload or logout pays nothing and is not counted.
--
-- Coordinates: pixels of the play area, x to the right from its left edge, y up from the ground line.

---@class RunnerModule
local Runner = {}
addon.Runner = Runner

Runner.TICK = 1 / 120                 -- fixed simulation step (no tunnelling at the top speed)
Runner.MAXIMUM_FRAME = 0.1            -- a longer frame (loading screen, hitch) is cut to this
Runner.WIDTH = 290                    -- play area width
Runner.RUNNER_X = 46                  -- left edge of the runner box
Runner.RUNNER_WIDTH, Runner.RUNNER_HEIGHT, Runner.DUCK_HEIGHT = 34, 40, 22
Runner.BOX = 36                       -- every monster's box (width and height)
Runner.INSET = 4                      -- hitboxes are this much smaller on every side than the drawn boxes
Runner.FLYER_Y = 24                   -- bottom of a flying monster's box
Runner.GRAVITY = 1800
Runner.JUMP_SPEED = 560
Runner.HOLD_SECONDS = 0.2             -- holding jump this long keeps the lighter gravity (a higher jump)
Runner.HOLD_GRAVITY = 0.45            -- gravity factor while jump is held on the way up
Runner.FAST_FALL = 3                  -- gravity factor while ducking in the air
Runner.JUMP_BUFFER = 0.12             -- a jump pressed this shortly before landing still jumps
Runner.START_SPEED, Runner.MAXIMUM_SPEED, Runner.ACCELERATION = 260, 620, 6
Runner.PIXELS_PER_METER = 40
Runner.MILESTONE_METERS = 100
Runner.GOLD_PER_MILESTONE = 1
Runner.DAILY_CAP_GOLD = 50
Runner.MAXIMUM_METERS = 1000000
Runner.MAXIMUM_RECENT = 10
Runner.MAXIMUM_RUNS = 1000000000
Runner.FLYER_CHANCE = 0.25            -- once flyers are allowed
Runner.FLYERS_FROM_METERS = 150
Runner.PAIR_CHANCE = 0.15             -- two ground monsters side by side, once fast enough
Runner.PAIR_FROM_SPEED = 380
local SECONDS_PER_DAY = 86400

-- creature type ids and beast families (enUS/deDE, lower case) that fly
local FLYING_TYPES = { [2] = true }   -- dragonkin
local FLYING_FAMILIES = { bat = true, fledermaus = true, ["carrion bird"] = true, aasvogel = true, owl = true, eule = true,
    ["wind serpent"] = true, windnatter = true, ["bird of prey"] = true, raubvogel = true, dragonhawk = true,
    drachenfalke = true, ["nether ray"] = true, netherrochen = true }
-- obstacles while the collection knows fewer than MINIMUM_POOL monsters (creature ids; the model loads by creature)
Runner.MINIMUM_POOL = 3
Runner.FALLBACK_POOL = {
    { npc = 299, disp = 0, n = "Young Wolf" },
    { npc = 1984, disp = 0, n = "Young Thistle Boar" },
    { npc = 1512, disp = 0, n = "Duskbat", fly = true },
}

---@class RunnerObstacle
---@field id integer
---@field x number left edge
---@field y number bottom (0 on the ground)
---@field fly boolean
---@field pick integer index into run.pool

---@class RunnerRun
---@field pool table[] { npc, disp, n, fly }
---@field seed integer
---@field time number
---@field distance number pixels run
---@field speed number
---@field y number runner bottom
---@field vy number
---@field grounded boolean
---@field ducking boolean
---@field holdLeft number seconds of the lighter gravity left in this jump
---@field jumpHeld boolean
---@field bufferLeft number
---@field obstacles RunnerObstacle[]
---@field nextID integer
---@field spawnIn number pixels until the next spawn
---@field milestones integer
---@field finished boolean
---@field crashedInto RunnerObstacle|nil
---@field shield integer hits a Dash Shield still absorbs
---@field graceLeft number seconds without crashes after a shield absorbed a hit
---@field startMeters integer meters a Head Start skipped (no gold for them)
---@field item boolean an item was used in this run (the run is marked on the boards)
---@field events table[]
---@field carry number simulation time not stepped yet

------------------------------------------------------------------ random (own generator: a seed replays a run)

---@param run RunnerRun
---@return number 0 <= r < 1
local function random(run)
    run.seed = (run.seed * 1103515245 + 12345) % 2147483648
    return run.seed / 2147483648
end

------------------------------------------------------------------ pool

-- True when the stats say the creature flies (dragonkin or a flying beast family).
---@param stats any
---@return boolean
function Runner.Flies(stats)
    if type(stats) ~= "table" then return false end
    if FLYING_TYPES[stats.type] then return true end
    return type(stats.family) == "string" and FLYING_FAMILIES[stats.family:lower()] == true
end

-- The obstacle pool from a collection (found and caught NPCs), sorted by NPC id so a seed replays the same run. Fewer than
-- MINIMUM_POOL known: the built-in monsters fill it.
---@param collection table<integer, CollectionEntry>|nil
---@return table[] pool { npc, disp, n, fly }
function Runner.BuildPool(collection)
    local pool = {}
    for npcID, entry in pairs(type(collection) == "table" and collection or {}) do
        if type(npcID) == "number" and type(entry) == "table" then
            pool[#pool + 1] = { npc = npcID, disp = tonumber(entry.disp) or 0, n = type(entry.n) == "string" and entry.n or "?",
                fly = Runner.Flies(entry.st) }
        end
    end
    table.sort(pool, function(left, right) return left.npc < right.npc end)
    if #pool < Runner.MINIMUM_POOL then
        for _, monster in ipairs(Runner.FALLBACK_POOL) do
            pool[#pool + 1] = { npc = monster.npc, disp = monster.disp, n = monster.n, fly = monster.fly or false }
        end
    end
    return pool
end

------------------------------------------------------------------ a run

Runner.HEAD_START_METERS = 200
Runner.SHIELD_GRACE = 1   -- seconds without crashes after the shield absorbed a hit

-- A new run. `options.shield`: one hit is absorbed; `options.start`: the run starts at HEAD_START_METERS (at the
-- speed it would have there).
---@param pool table[]
---@param seed integer
---@param options? { shield: boolean, start: boolean }
---@return RunnerRun
function Runner.New(pool, seed, options)
    options = options or {}
    local run = { pool = pool, seed = math.floor(math.abs(tonumber(seed) or 1)) % 2147483648, time = 0, distance = 0,
        speed = Runner.START_SPEED, y = 0, vy = 0, grounded = true, ducking = false, holdLeft = 0, jumpHeld = false,
        bufferLeft = 0, obstacles = {}, nextID = 0, spawnIn = Runner.START_SPEED * 1.2, milestones = 0, finished = false,
        events = {}, carry = 0, shield = options.shield and 1 or 0, graceLeft = 0, startMeters = 0,
        item = (options.shield or options.start) and true or false }
    if run.seed == 0 then run.seed = 1 end
    if options.start then
        -- distance = v0 t + a t^2 / 2 solved for t: the time a run needs to reach the head start
        local pixels = Runner.HEAD_START_METERS * Runner.PIXELS_PER_METER
        local a, v0 = Runner.ACCELERATION, Runner.START_SPEED
        run.time = (math.sqrt(v0 * v0 + 2 * a * pixels) - v0) / a
        run.speed = math.min(Runner.MAXIMUM_SPEED, v0 + a * run.time)
        run.distance, run.startMeters = pixels, Runner.HEAD_START_METERS
        run.milestones = math.floor(Runner.HEAD_START_METERS / Runner.MILESTONE_METERS)
    end
    return run
end

---@param run RunnerRun
---@param event table
local function emit(run, event) run.events[#run.events + 1] = event end

-- The events since the last call (jump, land, spawn, milestone, crash), oldest first.
---@param run RunnerRun
---@return table[]
function Runner.TakeEvents(run)
    local events = run.events
    run.events = {}
    return events
end

---@param run RunnerRun
---@return integer
function Runner.Meters(run) return math.floor(run.distance / Runner.PIXELS_PER_METER) end

-- The runner's hitbox: left, bottom, right, top.
---@param run RunnerRun
---@return number, number, number, number
function Runner.RunnerBox(run)
    local height = run.ducking and Runner.DUCK_HEIGHT or Runner.RUNNER_HEIGHT
    local inset = Runner.INSET
    return Runner.RUNNER_X + inset, run.y + inset, Runner.RUNNER_X + Runner.RUNNER_WIDTH - inset, run.y + height - inset
end

---@param obstacle RunnerObstacle
---@return number, number, number, number
function Runner.ObstacleBox(obstacle)
    local inset = Runner.INSET
    return obstacle.x + inset, obstacle.y + inset, obstacle.x + Runner.BOX - inset, obstacle.y + Runner.BOX - inset
end

-- Axis-aligned overlap of two boxes (left, bottom, right, top); touching edges do not collide.
---@return boolean
function Runner.Overlaps(left1, bottom1, right1, top1, left2, bottom2, right2, top2)
    return left1 < right2 and left2 < right1 and bottom1 < top2 and bottom2 < top1
end

---@param run RunnerRun
---@param fly boolean
---@return integer index into run.pool
local function pick(run, fly)
    local pool = run.pool
    if fly then
        local flyers = {}
        for index, monster in ipairs(pool) do if monster.fly then flyers[#flyers + 1] = index end end
        if #flyers > 0 then return flyers[1 + math.floor(random(run) * #flyers)] end
    end
    return 1 + math.floor(random(run) * #pool)
end

---@param run RunnerRun
---@param x number
---@param fly boolean
local function spawnOne(run, x, fly)
    run.nextID = run.nextID + 1
    local obstacle = { id = run.nextID, x = x, y = fly and Runner.FLYER_Y or 0, fly = fly, pick = pick(run, fly) }
    run.obstacles[#run.obstacles + 1] = obstacle
    emit(run, { kind = "spawn", obstacle = obstacle })
end

-- The gap to the next spawn in pixels: 0.9..1.7 s of running at the start, 0.6..1.2 s at the top speed, never shorter
-- than one full jump.
---@param run RunnerRun
---@return number
function Runner.Gap(run)
    local share = (run.speed - Runner.START_SPEED) / (Runner.MAXIMUM_SPEED - Runner.START_SPEED)
    local shortest = 0.9 - 0.3 * share
    local longest = 1.7 - 0.5 * share
    local seconds = shortest + (longest - shortest) * random(run)
    local airTime = 2 * Runner.JUMP_SPEED / Runner.GRAVITY
    return run.speed * math.max(seconds, airTime + 0.15)
end

---@param run RunnerRun
local function spawn(run)
    local x = Runner.WIDTH + 4
    local fly = Runner.Meters(run) >= Runner.FLYERS_FROM_METERS and random(run) < Runner.FLYER_CHANCE
    spawnOne(run, x, fly)
    if not fly and run.speed >= Runner.PAIR_FROM_SPEED and random(run) < Runner.PAIR_CHANCE then
        spawnOne(run, x + Runner.BOX, false)
    end
    run.spawnIn = Runner.Gap(run)
end

---@param run RunnerRun
---@param input { jump: boolean|nil, duck: boolean|nil }
local function stepInput(run, input)
    local jump, duck = input.jump and true or false, input.duck and true or false
    if jump and not run.jumpHeld then run.bufferLeft = Runner.JUMP_BUFFER end
    run.jumpHeld = jump
    if run.grounded and run.bufferLeft > 0 and not duck then
        run.grounded, run.vy, run.holdLeft, run.bufferLeft = false, Runner.JUMP_SPEED, Runner.HOLD_SECONDS, 0
        emit(run, { kind = "jump" })
    end
    if duck ~= run.ducking then
        run.ducking = duck
        emit(run, { kind = duck and "duck" or "stand" })
    end
end

---@param run RunnerRun
---@param dt number
local function stepPhysics(run, dt)
    run.bufferLeft = math.max(0, run.bufferLeft - dt)
    if not run.grounded then
        local factor = 1
        if run.ducking then
            factor = Runner.FAST_FALL
        elseif run.jumpHeld and run.vy > 0 and run.holdLeft > 0 then
            factor = Runner.HOLD_GRAVITY
        end
        if not run.jumpHeld then run.holdLeft = 0 end
        run.holdLeft = math.max(0, run.holdLeft - dt)
        run.vy = run.vy - Runner.GRAVITY * factor * dt
        run.y = run.y + run.vy * dt
        if run.y <= 0 then
            run.y, run.vy, run.grounded = 0, 0, true
            emit(run, { kind = "land" })
        end
    end
end

---@param run RunnerRun
---@param dt number
local function stepWorld(run, dt)
    run.time = run.time + dt
    run.speed = math.min(Runner.MAXIMUM_SPEED, Runner.START_SPEED + Runner.ACCELERATION * run.time)
    local move = run.speed * dt
    run.distance = run.distance + move
    local kept = {}
    for _, obstacle in ipairs(run.obstacles) do
        obstacle.x = obstacle.x - move
        if obstacle.x + Runner.BOX > -8 then kept[#kept + 1] = obstacle end
    end
    run.obstacles = kept
    run.spawnIn = run.spawnIn - move
    if run.spawnIn <= 0 then spawn(run) end
    local reached = math.floor(Runner.Meters(run) / Runner.MILESTONE_METERS)
    if reached > run.milestones then
        run.milestones = reached
        emit(run, { kind = "milestone", meters = reached * Runner.MILESTONE_METERS })
    end
end

---@param run RunnerRun
local function checkCrash(run, dt)
    if run.graceLeft > 0 then
        run.graceLeft = math.max(0, run.graceLeft - dt)
        return
    end
    local left, bottom, right, top = Runner.RunnerBox(run)
    for index, obstacle in ipairs(run.obstacles) do
        if Runner.Overlaps(left, bottom, right, top, Runner.ObstacleBox(obstacle)) then
            if run.shield > 0 then
                run.shield, run.graceLeft = run.shield - 1, Runner.SHIELD_GRACE
                table.remove(run.obstacles, index)
                emit(run, { kind = "shield", obstacle = obstacle })
                return
            end
            run.finished, run.crashedInto = true, obstacle
            emit(run, { kind = "crash", obstacle = obstacle })
            return
        end
    end
end

-- Advances an open run by `elapsedSeconds` (cut to MAXIMUM_FRAME) in fixed ticks with the held `input`.
---@param run RunnerRun
---@param elapsedSeconds number
---@param input { jump: boolean|nil, duck: boolean|nil }
function Runner.Step(run, elapsedSeconds, input)
    if run.finished then return end
    input = input or {}
    run.carry = run.carry + math.min(math.max(tonumber(elapsedSeconds) or 0, 0), Runner.MAXIMUM_FRAME)
    while run.carry >= Runner.TICK and not run.finished do
        run.carry = run.carry - Runner.TICK
        stepInput(run, input)
        stepPhysics(run, Runner.TICK)
        stepWorld(run, Runner.TICK)
        checkCrash(run, Runner.TICK)
    end
end

------------------------------------------------------------------ local stats and the daily payout

---@class RunnerState
---@field day integer server day (time / 86400) of `paid`
---@field paid integer gold paid on that day
---@field b integer best distance in meters
---@field n integer runs
---@field weeks table<string, integer> period key -> best meters that week
---@field recent { d: integer, g: integer, t: integer, it?: integer }[] newest first (`it` = 1: an item was used)
---@field bi? integer 1: the best run used an item

---@return RunnerState
function Runner.State()
    local database = addon.Store.db
    if type(database.runner) ~= "table" then database.runner = {} end
    local state = database.runner
    state.day, state.paid = state.day or 0, state.paid or 0
    state.b, state.n = state.b or 0, state.n or 0
    if type(state.weeks) ~= "table" then state.weeks = {} end
    if type(state.recent) ~= "table" then state.recent = {} end
    return state
end

---@param now integer
---@return integer
local function dayOf(now) return math.floor((tonumber(now) or 0) / SECONDS_PER_DAY) end

-- Gold already paid today and what is left of the daily cap.
---@param now integer
---@return integer paid
---@return integer left
function Runner.PaidToday(now)
    local state = Runner.State()
    local paid = state.day == dayOf(now) and state.paid or 0
    return paid, math.max(0, Runner.DAILY_CAP_GOLD - paid)
end

-- Gold a run of `meters` pays when `paidToday` gold was already paid today.
---@param meters integer
---@param paidToday integer
---@return integer gold
function Runner.Payout(meters, paidToday)
    local earned = math.floor(math.max(0, meters) / Runner.MILESTONE_METERS) * Runner.GOLD_PER_MILESTONE
    return math.max(0, math.min(earned, Runner.DAILY_CAP_GOLD - math.max(0, paidToday)))
end

-- keeps the MAXIMUM_WEEKS newest week keys
---@param weeks table<string, integer>
local function pruneWeeks(weeks)
    local keys = {}
    for periodKey in pairs(weeks) do keys[#keys + 1] = periodKey end
    table.sort(keys, function(left, right) return left > right end)
    for index = addon.Games.MAXIMUM_WEEKS + 1, #keys do weeks[keys[index]] = nil end
end

---@class RunnerResult
---@field meters integer
---@field gold integer paid into the pool
---@field capped boolean the daily cap cut the payout
---@field best boolean a new personal best
---@field paidToday integer after this run

-- Books a finished run: the payout (daily cap), best, weekly best, recent runs; refreshes my guild section. Nothing is
-- stored while the saved data is read-only.
---@param run RunnerRun
---@param myName string|nil
---@param now integer
---@return RunnerResult
function Runner.Finish(run, myName, now)
    local meters = math.min(Runner.Meters(run), Runner.MAXIMUM_METERS)
    local result = { meters = meters, gold = 0, capped = false, best = false, paidToday = 0 }
    if addon.Store.db.readonly then return result end
    local state = Runner.State()
    local day = dayOf(now)
    if state.day ~= day then state.day, state.paid = day, 0 end
    local paidMeters = math.max(0, meters - (run.startMeters or 0))
    local gold = Runner.Payout(paidMeters, state.paid)
    result.capped = gold < math.floor(paidMeters / Runner.MILESTONE_METERS) * Runner.GOLD_PER_MILESTONE
    if gold > 0 and addon.Wallet.Earn(myName, gold * addon.Games.COPPER_PER_GOLD, "runner", now, meters .. " m") then
        state.paid = state.paid + gold
        result.gold = gold
    end
    result.paidToday = state.paid
    result.best = meters > state.b
    if result.best then state.b, state.bi = meters, run.item and 1 or nil end
    state.n = math.min(Runner.MAXIMUM_RUNS, state.n + 1)
    local periodKey = addon.Games.PeriodKey(now)
    if meters > (state.weeks[periodKey] or 0) then state.weeks[periodKey] = meters end
    pruneWeeks(state.weeks)
    table.insert(state.recent, 1, { d = meters, g = result.gold, t = now, it = run.item and 1 or nil })
    for index = #state.recent, Runner.MAXIMUM_RECENT + 1, -1 do state.recent[index] = nil end
    Runner.Publish(myName, now)
    return result
end

------------------------------------------------------------------ guild section

-- My section for the guild: { b, bi?, n, weeks, recent } (protocol 1.4; `bi` and the recent `it` since 1.5).
---@return table
function Runner.BuildSection()
    local state = Runner.State()
    local section = { b = state.b, bi = state.bi, n = state.n, weeks = {}, recent = {} }
    for periodKey, meters in pairs(state.weeks) do section.weeks[periodKey] = meters end
    for index, entry in ipairs(state.recent) do section.recent[index] = { d = entry.d, g = entry.g, t = entry.t, it = entry.it } end
    return section
end

-- Puts my section into my game record (a new revision, sent with the next sync). Returns true when stored.
---@param myName string|nil
---@param now integer
---@return boolean
function Runner.Publish(myName, now)
    return addon.Games.SetSection(myName, "runner", Runner.BuildSection(), now)
end

-- A clean copy of a runner section (mine or a peer's), or nil when anything is wrong. `horizon` bounds the times.
---@param section any
---@param horizon number
---@return table|nil
function Runner.SanitizeSection(section, horizon)
    local SafeInteger = addon.Utility.SafeInteger
    if type(section) ~= "table" or type(section.weeks) ~= "table" or type(section.recent) ~= "table" then return nil end
    local best = SafeInteger(section.b, 0, Runner.MAXIMUM_METERS)
    local runs = SafeInteger(section.n, 0, Runner.MAXIMUM_RUNS)
    if not best or not runs then return nil end
    local clean = { b = best, bi = section.bi == 1 and 1 or nil, n = runs, weeks = {}, recent = {} }
    local latestKey = horizon ~= math.huge and addon.Games.PeriodKey(horizon) or nil
    local weekCount = 0
    for periodKey, meters in pairs(section.weeks) do
        weekCount = weekCount + 1
        if weekCount > addon.Games.MAXIMUM_WEEKS or not addon.Games.IsPeriodKey(periodKey) then return nil end
        if latestKey and periodKey > latestKey then return nil end
        local clamped = SafeInteger(meters, 0, Runner.MAXIMUM_METERS)
        if not clamped then return nil end
        clean.weeks[periodKey] = clamped
    end
    if #section.recent > Runner.MAXIMUM_RECENT then return nil end
    for index = 1, #section.recent do
        local entry = section.recent[index]
        if type(entry) ~= "table" then return nil end
        local meters, gold = SafeInteger(entry.d, 0, Runner.MAXIMUM_METERS), SafeInteger(entry.g, 0, Runner.DAILY_CAP_GOLD)
        local playTime = SafeInteger(entry.t, 0, horizon)
        if not meters or not gold or not playTime then return nil end
        clean.recent[index] = { d = meters, g = gold, t = playTime, it = entry.it == 1 and 1 or nil }
    end
    return clean
end

-- Re-validates db.runner on load. Returns true when it had to be repaired.
---@param savedVariables table
---@return boolean repaired
function Runner.SanitizePersisted(savedVariables)
    local saved = savedVariables.runner
    if saved == nil then return false end
    local SafeInteger = addon.Utility.SafeInteger
    local horizon = addon.Store.Horizon()
    local section = type(saved) == "table" and Runner.SanitizeSection({ b = saved.b, bi = saved.bi, n = saved.n,
        weeks = type(saved.weeks) == "table" and saved.weeks or {}, recent = type(saved.recent) == "table" and saved.recent or {} }, horizon)
    local clean = section or { b = 0, n = 0, weeks = {}, recent = {} }
    clean.day = type(saved) == "table" and SafeInteger(saved.day, 0, 1000000) or 0
    clean.paid = type(saved) == "table" and SafeInteger(saved.paid, 0, Runner.DAILY_CAP_GOLD) or 0
    local repaired = section == nil or type(saved) ~= "table" or clean.day ~= saved.day or clean.paid ~= saved.paid
    savedVariables.runner = clean
    return repaired
end

------------------------------------------------------------------ leaderboard

---@class RunnerBoardRow
---@field rank integer
---@field name string escaped
---@field nameRaw string
---@field meters integer best in the scope
---@field runs integer all-time runs
---@field mine boolean
---@field item boolean the all-time best used an item

-- Best distances of every player with a runner section, in `scope` ("week": this week's best, "all": all-time best).
---@param records table<string, GameRecord>
---@param scope "week"|"all"
---@param periodKey string
---@param myName string|nil
---@return RunnerBoardRow[]
function Runner.BoardRows(records, scope, periodKey, myName)
    local rows = {}
    for playerName, gameRecord in pairs(records or {}) do
        local section = type(gameRecord) == "table" and gameRecord.runner
        if type(section) == "table" then
            local meters = scope == "week" and (type(section.weeks) == "table" and section.weeks[periodKey]) or section.b
            if type(meters) == "number" and meters > 0 then
                rows[#rows + 1] = { name = addon.Utility.Escape(playerName), nameRaw = playerName, meters = meters,
                    runs = tonumber(section.n) or 0, mine = playerName == myName, item = scope == "all" and section.bi == 1 }
            end
        end
    end
    table.sort(rows, function(left, right)
        if left.meters ~= right.meters then return left.meters > right.meters end
        return left.nameRaw < right.nameRaw
    end)
    for index, row in ipairs(rows) do row.rank = index end
    return rows
end

-- The newest runs of every player, merged, newest first (at most `limit`, default 15).
---@param records table<string, GameRecord>
---@param myName string|nil
---@param limit? integer
---@return { name: string, nameRaw: string, meters: integer, gold: integer, t: integer, mine: boolean, item: boolean }[]
function Runner.FeedRows(records, myName, limit)
    local rows = {}
    for playerName, gameRecord in pairs(records or {}) do
        local section = type(gameRecord) == "table" and gameRecord.runner
        for _, entry in ipairs(type(section) == "table" and type(section.recent) == "table" and section.recent or {}) do
            rows[#rows + 1] = { name = addon.Utility.Escape(playerName), nameRaw = playerName, meters = entry.d, gold = entry.g,
                t = entry.t, mine = playerName == myName, item = entry.it == 1 }
        end
    end
    table.sort(rows, function(left, right)
        if left.t ~= right.t then return left.t > right.t end
        return left.nameRaw < right.nameRaw
    end)
    for index = #rows, (limit or 15) + 1, -1 do rows[index] = nil end
    return rows
end
