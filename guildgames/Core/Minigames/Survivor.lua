local addonName, addon = ...

-- Survivor (third game). Pure Lua: the whole simulation, so it runs and is balanced offline. UI/SurvivorArena.lua only
-- draws a run and forwards the item choices.
--
-- A tower stands in the middle of the arena. Monsters walk in from the edges and hurt the tower while they touch it. The
-- tower fights on its own with its weapons: a bolt (projectile at the nearest monster), a cleave (melee, hits everything
-- near the tower) and later a frost nova. Kills give experience; every level offers 3 items (a new weapon, a weapon
-- level, or a passive) and the run pauses until one is picked.
--
-- Betting: the stake goes on a survival time (Survivor.TARGETS). Survive until then and the payout is factor x stake;
-- fall earlier (or give up, or leave the game mid-run) and the stake is lost. A run is a game of skill (the item picks),
-- so it cannot be decided before it is played like the coin flip: instead the stake is marked PENDING in the saved data
-- when the run starts. A /reload or logout mid-run then still books the loss (Survivor.ResolvePending, at login).
--
-- Endless mode (Survivor.ENDLESS): no fixed end. Every full minute survived doubles the payout (1:00 x2, 2:00 x4, ...,
-- capped at Games.SURVIVOR_MAXIMUM_FACTOR). The run ends when the tower falls or the player cashes out (the Give up
-- button); either way the last minute reached is paid, and before 1:00 the stake is lost. The reached factor is kept
-- in the pending mark, so a /reload mid-run pays what was already reached, no more.

---@class SurvivorTarget
---@field seconds number the time to survive (math.huge in endless mode)
---@field factor integer payout multiplier (payout = factor x stake, net = (factor - 1) x stake); 0 in endless mode
---@field endless? boolean

---@class SurvivorEnemy
---@field id integer
---@field kind string key into Survivor.ENEMY_BY_KEY
---@field x number
---@field y number
---@field hp number
---@field maxHp number
---@field radius number
---@field speed number
---@field damage number per second while touching the tower
---@field slow number seconds of nova slow left
---@field flash number seconds of hit flash left (drawing only)

---@class SurvivorProjectile
---@field weapon string
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field life number seconds left
---@field damage number
---@field radius number hit radius
---@field pierce integer monsters it may still pass through (below 0: gone)
---@field hits table<integer, boolean> enemy ids already hit (each monster once per projectile)
---@field splash? number
---@field slow? number
---@field homing? number
---@field boomerang? number
---@field maxLife number

---@class SurvivorEvent
---@field kind "shot"|"hit"|"kill"|"cleave"|"nova"|"blast"|"zap"|"hurt"|"shieldbreak"|"levelup"|"milestone"|"won"|"lost"
---@field weapon? string shot, blast, zap: the weapon key
---@field points? number[][] zap: the chain's points { x, y }, from the tower
---@field factor? integer milestone: the endless payout factor reached
---@field x? number
---@field y? number
---@field radius? number
---@field enemy? string

---@class SurvivorChoice
---@field key string item key (Survivor.ITEM_BY_KEY)
---@field level integer the level it reaches when picked

---@class SurvivorRun
---@field name string
---@field stake integer copper
---@field target SurvivorTarget
---@field random fun(): number
---@field time number seconds survived
---@field hp number
---@field maxHp number
---@field level integer
---@field xp integer
---@field xpNext integer
---@field kills integer
---@field items table<string, integer> item key -> level (0 or missing = not owned)
---@field cooldowns table<string, number>
---@field enemies SurvivorEnemy[]
---@field projectiles SurvivorProjectile[]
---@field spawnTimer number
---@field nextId integer
---@field choices SurvivorChoice[]|nil set while a level-up waits for a pick (the run is paused)
---@field pendingLevels integer level-ups still to offer after the current choice
---@field finished "won"|"lost"|nil
---@field events SurvivorEvent[] what happened since the UI last took them
---@field accumulator number unsimulated seconds (fixed step)
---@field reachedFactor? integer endless: the payout factor reached so far
---@field shield number barrier points left
---@field shieldPause number seconds until the barrier refills
---@field net? integer set by Settle

---@class SurvivorModule
local Survivor = {}
addon.Survivor = Survivor

Survivor.STEP = 1 / 30                     -- fixed simulation step (seconds)
Survivor.HALF_WIDTH, Survivor.HALF_HEIGHT = 145, 100   -- arena, tower at (0, 0); y grows upwards
Survivor.TOWER_RADIUS = 14
Survivor.BASE_HP = 100

---@type SurvivorTarget[] shortest first; the factor of the last one is Games.SURVIVOR_MAXIMUM_FACTOR
Survivor.TARGETS = {
    { seconds = 60, factor = 2 },
    { seconds = 90, factor = 3 },
    { seconds = 120, factor = 5 },
    { seconds = 180, factor = 10 },
}

---@type SurvivorTarget endless mode: index #TARGETS + 1 (Survivor.Target)
Survivor.ENDLESS = { seconds = math.huge, factor = 0, endless = true }
Survivor.ENDLESS_INDEX = #Survivor.TARGETS + 1
Survivor.MILESTONE_SECONDS = 60
Survivor.ENDLESS_MAXIMUM_FACTOR = 64   -- 6 minutes; Games.SURVIVOR_MAXIMUM_FACTOR must equal it

-- The payout factor of an endless run after `time` seconds: 0 before the first minute, then 2, 4, 8, ... (capped).
---@param time number
---@return integer
function Survivor.EndlessFactor(time)
    local minutes = math.floor((time or 0) / Survivor.MILESTONE_SECONDS)
    if minutes < 1 then return 0 end
    return math.min(Survivor.ENDLESS_MAXIMUM_FACTOR, 2 ^ minutes)
end

---@class SurvivorEnemyKind
---@field key string
---@field hp number at 0 s (grows with time)
---@field speed number px per second
---@field damage number per second while touching
---@field radius number
---@field xp integer
---@field from number seconds into the run before it appears
---@field weight integer spawn weight once it appears
---@field icon string
---@field color number[] fallback colour

---@type SurvivorEnemyKind[]
Survivor.ENEMIES = {
    { key = "spider", hp = 9, speed = 24, damage = 6, radius = 7, xp = 1, from = 0, weight = 6,
        icon = "Interface\\Icons\\Ability_Hunter_Pet_Spider", color = { 0.5, 0.35, 0.6 } },
    { key = "wolf", hp = 6, speed = 46, damage = 4, radius = 7, xp = 1, from = 25, weight = 4,
        icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf", color = { 0.6, 0.6, 0.65 } },
    { key = "bear", hp = 45, speed = 14, damage = 14, radius = 10, xp = 4, from = 40, weight = 2,
        icon = "Interface\\Icons\\Ability_Hunter_Pet_Bear", color = { 0.55, 0.35, 0.2 } },
}
---@type table<string, SurvivorEnemyKind>
Survivor.ENEMY_BY_KEY = {}
for _, kind in ipairs(Survivor.ENEMIES) do Survivor.ENEMY_BY_KEY[kind.key] = kind end

---@class SurvivorItem
---@field key string
---@field kind "weapon"|"passive"
---@field maximum integer highest level
---@field icon string
---@field color number[]

---@type SurvivorItem[] (names and descriptions: UI/SurvivorArena.lua, localized)
Survivor.ITEMS = {
    { key = "bolt", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Fire_FireBolt02", color = { 1, 0.6, 0.2 } },
    { key = "cleave", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Ability_Warrior_Cleave", color = { 0.8, 0.8, 0.9 } },
    { key = "nova", kind = "weapon", maximum = 4, icon = "Interface\\Icons\\Spell_Frost_FrostNova", color = { 0.4, 0.7, 1 } },
    { key = "arcane", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Nature_StarFall", color = { 0.85, 0.45, 1 } },
    { key = "shadow", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt", color = { 0.6, 0.25, 0.85 } },
    { key = "arrows", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Ability_UpgradeMoonGlaive", color = { 0.85, 0.8, 0.55 } },
    { key = "lightning", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Nature_ChainLightning", color = { 0.55, 0.8, 1 } },
    { key = "fireball", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Fire_FlameBolt", color = { 1, 0.4, 0.1 } },
    { key = "icelance", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02", color = { 0.6, 0.9, 1 } },
    { key = "smite", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Holy_HolySmite", color = { 1, 0.95, 0.6 } },
    { key = "knives", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\INV_ThrowingKnife_02", color = { 0.8, 0.85, 0.8 } },
    { key = "axe", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\INV_ThrowingAxe_01", color = { 0.75, 0.55, 0.35 } },
    { key = "starfall", kind = "weapon", maximum = 5, icon = "Interface\\Icons\\Spell_Arcane_StarFire", color = { 0.7, 0.6, 1 } },
    { key = "might", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Spell_Nature_Strength", color = { 1, 0.3, 0.3 } },
    { key = "haste", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Spell_Nature_Invisibilty", color = { 1, 1, 0.4 } },
    { key = "armor", kind = "passive", maximum = 5, icon = "Interface\\Icons\\INV_Shield_06", color = { 0.7, 0.7, 0.7 } },
    { key = "vitality", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Spell_Holy_Heal", color = { 0.3, 1, 0.4 } },
    { key = "regen", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Spell_Nature_Rejuvenation", color = { 0.3, 0.9, 0.6 } },
    { key = "volley", kind = "passive", maximum = 2, icon = "Interface\\Icons\\Ability_Marksmanship", color = { 1, 0.85, 0.4 } },
    { key = "pierce", kind = "passive", maximum = 3, icon = "Interface\\Icons\\Ability_ImpalingBolt", color = { 0.85, 0.85, 1 } },
    { key = "reach", kind = "passive", maximum = 4, icon = "Interface\\Icons\\Spell_Nature_WispSplode", color = { 0.6, 0.6, 1 } },
    { key = "thorns", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Spell_Nature_Thorns", color = { 0.5, 0.8, 0.3 } },
    { key = "deflect", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Ability_Parry", color = { 0.9, 0.9, 0.6 } },
    { key = "barrier", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", color = { 0.4, 0.7, 1 } },
    { key = "leech", kind = "passive", maximum = 5, icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02", color = { 0.8, 0.2, 0.3 } },
}
---@type table<string, SurvivorItem>
Survivor.ITEM_BY_KEY = {}
---@type string[] every texture the game uses (the dev probe checks they exist on this client)
Survivor.ICONS = {}
---@type string[] weapon keys in item order (the order they fire in)
Survivor.WEAPON_KEYS = {}
for _, item in ipairs(Survivor.ITEMS) do
    Survivor.ITEM_BY_KEY[item.key] = item
    Survivor.ICONS[#Survivor.ICONS + 1] = item.icon
    if item.kind == "weapon" then Survivor.WEAPON_KEYS[#Survivor.WEAPON_KEYS + 1] = item.key end
end
Survivor.MAXIMUM_WEAPONS = 6   -- a tower holds at most this many weapons; then only owned ones are offered
for _, kind in ipairs(Survivor.ENEMIES) do Survivor.ICONS[#Survivor.ICONS + 1] = kind.icon end
Survivor.TOWER_ICON = "Interface\\Icons\\Spell_Holy_DivineIntervention"
Survivor.ICONS[#Survivor.ICONS + 1] = Survivor.TOWER_ICON

------------------------------------------------------------------ item stats (one place, also shown in the UI)

-- damage multiplier of "might"
---@param run SurvivorRun
---@return number
local function might(run) return 1 + 0.2 * (run.items.might or 0) end

-- cooldown multiplier of "haste"
---@param run SurvivorRun
---@return number
local function haste(run) return 0.88 ^ (run.items.haste or 0) end

---@class WeaponStats
---@field damage number
---@field cooldown number seconds
---@field count? integer projectiles per volley, chain jumps or strikes
---@field shots? integer the same as count (bolt)
---@field pierce? integer extra monsters a projectile passes through
---@field splash? number explosion radius on impact
---@field radius? number cleave and nova reach, strike radius

---@class RangedWeapon
---@field fire "projectile"|"chain"|"strike"
---@field aim? "nearest"|"spread"|"spiral" projectile: at the nearest monsters, a fan at the nearest one, or a rotating ring
---@field speed? number projectile px per second
---@field life? number projectile seconds
---@field radius? number projectile hit radius
---@field size? number drawn size
---@field spread? number fan width (radians)
---@field step? number spiral: turn per volley (radians)
---@field homing? number turn rate towards the nearest monster (radians per second)
---@field slow? number seconds of slow on hit
---@field boomerang? number pull back to the tower (px per second squared): the projectile flies out and returns
---@field jump? number chain: reach of each jump
---@field stats fun(level: integer): WeaponStats base numbers at a level (before might and haste)

-- Every ranged weapon: how it fires and its numbers per level. Data only; fire() and moveProjectiles() run them.
---@type table<string, RangedWeapon>
Survivor.RANGED = {
    bolt = { fire = "projectile", aim = "nearest", speed = 240, life = 0.9, radius = 6, size = 14,
        stats = function(level) return { damage = 10 + 3 * (level - 1), cooldown = 0.8 * 0.9 ^ (level - 1), count = 1 + math.floor(level / 2) } end },
    arcane = { fire = "projectile", aim = "spread", spread = 1.2, speed = 150, life = 1.8, radius = 6, size = 11, homing = 6,
        stats = function(level) return { damage = 4 + 2 * (level - 1), cooldown = 1.6 * 0.92 ^ (level - 1), count = 2 + math.floor(level / 2) } end },
    shadow = { fire = "projectile", aim = "nearest", speed = 120, life = 2.2, radius = 9, size = 20,
        stats = function(level) return { damage = 14 + 6 * (level - 1), cooldown = 2.4 * 0.9 ^ (level - 1), count = 1,
            pierce = 2 + math.floor(level / 2) } end },
    arrows = { fire = "projectile", aim = "spread", spread = 0.6, speed = 280, life = 0.8, radius = 5, size = 9,
        stats = function(level) return { damage = 5 + 2 * (level - 1), cooldown = 1.3 * 0.92 ^ (level - 1), count = 2 + level } end },
    lightning = { fire = "chain", jump = 60,
        stats = function(level) return { damage = 7 + 3 * (level - 1), cooldown = 2 * 0.92 ^ (level - 1), count = 2 + level } end },
    fireball = { fire = "projectile", aim = "nearest", speed = 170, life = 1.4, radius = 7, size = 17,
        stats = function(level) return { damage = 8 + 4 * (level - 1), cooldown = 2.2 * 0.9 ^ (level - 1),
            count = 1 + math.floor((level - 1) / 2), splash = 30 + 4 * level } end },
    icelance = { fire = "projectile", aim = "nearest", speed = 260, life = 1, radius = 5, size = 12, slow = 1.5,
        stats = function(level) return { damage = 6 + 3 * (level - 1), cooldown = 1.4 * 0.92 ^ (level - 1),
            count = 1 + math.floor(level / 3), pierce = 1 + math.floor(level / 2) } end },
    smite = { fire = "strike",
        stats = function(level) return { damage = 10 + 5 * (level - 1), cooldown = 2 * 0.92 ^ (level - 1),
            count = 1 + math.floor(level / 2), radius = 22 + 3 * level } end },
    knives = { fire = "projectile", aim = "spiral", step = 0.7, speed = 230, life = 0.8, radius = 5, size = 9,
        stats = function(level) return { damage = 5 + 2 * (level - 1), cooldown = 0.5 * 0.92 ^ (level - 1),
            count = 1 + math.floor(level / 2) } end },
    axe = { fire = "projectile", aim = "nearest", speed = 210, life = 2, radius = 8, size = 16, boomerang = 260,
        stats = function(level) return { damage = 8 + 4 * (level - 1), cooldown = 2 * 0.92 ^ (level - 1),
            count = 1 + math.floor((level - 1) / 2), pierce = 99 } end },
    starfall = { fire = "strike",
        stats = function(level) return { damage = 6 + 3 * (level - 1), cooldown = 3.2 * 0.92 ^ (level - 1),
            count = 2 + level, radius = 18 } end },
}

------------------------------------------------------------------ item stats (one place, also shown in the UI)

-- damage multiplier of "might"
---@param run SurvivorRun
---@return number
local function might(run) return 1 + 0.2 * (run.items.might or 0) end

-- cooldown multiplier of "haste"
---@param run SurvivorRun
---@return number
local function haste(run) return 0.88 ^ (run.items.haste or 0) end

-- radius multiplier of "reach" (cleave, nova, explosions, strikes)
---@param run SurvivorRun
---@return number
local function area(run) return 1 + 0.15 * (run.items.reach or 0) end

---@class DefenseStats
---@field armor number share of contact damage taken after armor
---@field deflect number share of contact damage turned away (and sent back to the attacker)
---@field reflect number damage multiplier of what is deflected
---@field thorns number damage per second to every monster touching the tower
---@field shield number barrier capacity (absorbs damage first; refills after a pause)
---@field leech number health per kill

Survivor.BARRIER_PAUSE, Survivor.BARRIER_REFILL = 3, 20   -- seconds without damage, then refill per second

-- The tower's defensive numbers from its items (one place, also shown in the UI).
---@param run SurvivorRun
---@return DefenseStats
function Survivor.DefenseStats(run)
    local items = run.items
    return { armor = 0.85 ^ (items.armor or 0), deflect = math.min(0.6, 0.1 * (items.deflect or 0)), reflect = 3,
        thorns = 5 * (items.thorns or 0) * might(run), shield = 15 * (items.barrier or 0), leech = 0.6 * (items.leech or 0) }
end

-- The current numbers of a weapon (nil when not owned).
---@param run SurvivorRun
---@param key string a weapon key
---@return WeaponStats|nil
function Survivor.WeaponStats(run, key)
    local level = run.items[key] or 0
    if level <= 0 then return nil end
    local ranged = Survivor.RANGED[key]
    if ranged then
        local stats = ranged.stats(level)
        stats.damage, stats.cooldown = stats.damage * might(run), stats.cooldown * haste(run)
        if ranged.fire == "projectile" then
            stats.count = stats.count + (run.items.volley or 0)                 -- volley: +1 projectile per volley
            stats.pierce = (stats.pierce or 0) + (run.items.pierce or 0)        -- penetration: +1 monster passed through
        end
        if stats.splash then stats.splash = stats.splash * area(run) end
        if stats.radius then stats.radius = stats.radius * area(run) end
        stats.shots = stats.count
        return stats
    elseif key == "cleave" then
        return { damage = (9 + 5 * (level - 1)) * might(run), cooldown = 1.5 * 0.9 ^ (level - 1) * haste(run),
            radius = (36 + 5 * level) * area(run) }
    end
    return { damage = (5 + 4 * (level - 1)) * might(run), cooldown = 4.5 * 0.9 ^ (level - 1) * haste(run),
        radius = (70 + 10 * level) * area(run) }
end

Survivor.NOVA_SLOW_SECONDS, Survivor.NOVA_SLOW_FACTOR = 2, 0.45
Survivor.CLEAVE_KNOCKBACK = 10

------------------------------------------------------------------ run

---@param level integer
---@return integer experience to the next level
local function experienceFor(level) return 3 + 2 * level end

-- A new run (no storage; Survivor.Begin also books the stake as pending).
---@param name string
---@param stake integer
---@param target SurvivorTarget
---@param randomFunction fun(): number
---@return SurvivorRun
function Survivor.NewRun(name, stake, target, randomFunction)
    return { name = name, stake = stake, target = target, random = randomFunction, time = 0, hp = Survivor.BASE_HP,
        maxHp = Survivor.BASE_HP, level = 1, xp = 0, xpNext = experienceFor(1), kills = 0, items = { bolt = 1 },
        cooldowns = { bolt = 0.4 }, spirals = {}, enemies = {}, projectiles = {}, spawnTimer = 0.5, nextId = 0,
        choices = nil, pendingLevels = 0, finished = nil, events = {}, accumulator = 0, shield = 0, shieldPause = 0 }
end

---@param run SurvivorRun
---@param event SurvivorEvent
local function emit(run, event) run.events[#run.events + 1] = event end

-- seconds between spawns and enemy health factor at `time`
---@param time number
---@return number interval
---@return number healthFactor
function Survivor.Difficulty(time)
    return math.max(0.16, 1.05 - time * 0.0065), 1 + time / 50 + (time / 70) ^ 2.1
end

---@param run SurvivorRun
local function spawn(run)
    local random = run.random
    local total, available = 0, {}
    for _, kind in ipairs(Survivor.ENEMIES) do
        if run.time >= kind.from then total = total + kind.weight; available[#available + 1] = kind end
    end
    local pick, chosen = random() * total, available[1]
    for _, kind in ipairs(available) do
        pick = pick - kind.weight
        if pick < 0 then chosen = kind break end
    end
    -- a point on the arena's edge
    local w, h = Survivor.HALF_WIDTH, Survivor.HALF_HEIGHT
    local along = random() * 2 * (w + h) * 2
    local x, y
    if along < 2 * w then x, y = -w + along, h
    elseif along < 2 * w + 2 * h then x, y = w, h - (along - 2 * w)
    elseif along < 4 * w + 2 * h then x, y = w - (along - 2 * w - 2 * h), -h
    else x, y = -w, -h + (along - 4 * w - 2 * h) end
    local _, healthFactor = Survivor.Difficulty(run.time)
    run.nextId = run.nextId + 1
    local hp = chosen.hp * healthFactor
    run.enemies[#run.enemies + 1] = { id = run.nextId, kind = chosen.key, x = x, y = y, hp = hp, maxHp = hp,
        radius = chosen.radius, speed = chosen.speed * (0.9 + 0.2 * random()), damage = chosen.damage * (1 + run.time / 90),
        slow = 0, flash = 0 }
end

---@param enemy SurvivorEnemy
---@return number
local function distance(enemy) return math.sqrt(enemy.x * enemy.x + enemy.y * enemy.y) end

-- the alive enemies sorted by distance to the tower (nearest first)
---@param run SurvivorRun
---@return SurvivorEnemy[]
local function nearest(run)
    local sorted = {}
    for _, enemy in ipairs(run.enemies) do if enemy.hp > 0 then sorted[#sorted + 1] = enemy end end
    table.sort(sorted, function(left, right)
        local leftDistance, rightDistance = distance(left), distance(right)
        if leftDistance ~= rightDistance then return leftDistance < rightDistance end
        return left.id < right.id
    end)
    return sorted
end

---@param run SurvivorRun
---@param enemy SurvivorEnemy
---@param damage number
local function hurtEnemy(run, enemy, damage)
    if enemy.hp <= 0 then return end
    enemy.hp = enemy.hp - damage
    enemy.flash = 0.12
    if enemy.hp <= 0 then
        run.kills = run.kills + 1
        if (run.items.leech or 0) > 0 then run.hp = math.min(run.maxHp, run.hp + Survivor.DefenseStats(run).leech) end
        run.xp = run.xp + Survivor.ENEMY_BY_KEY[enemy.kind].xp
        emit(run, { kind = "kill", x = enemy.x, y = enemy.y, enemy = enemy.kind })
    else
        emit(run, { kind = "hit", x = enemy.x, y = enemy.y })
    end
end

-- Up to three different items that can still level up, drawn at random; "vitality" (a heal) when everything is maxed.
---@param run SurvivorRun
---@return SurvivorChoice[]
function Survivor.Offer(run)
    local open, weaponCount = {}, 0
    for _, key in ipairs(Survivor.WEAPON_KEYS) do if (run.items[key] or 0) > 0 then weaponCount = weaponCount + 1 end end
    for _, item in ipairs(Survivor.ITEMS) do
        local level = run.items[item.key] or 0
        local blocked = item.kind == "weapon" and level == 0 and weaponCount >= Survivor.MAXIMUM_WEAPONS
        if level < item.maximum and not blocked then open[#open + 1] = item.key end
    end
    local choices = {}
    while #choices < 3 and #open > 0 do
        local index = math.min(#open, 1 + math.floor(run.random() * #open))
        local key = table.remove(open, index)
        choices[#choices + 1] = { key = key, level = (run.items[key] or 0) + 1 }
    end
    if #choices == 0 then choices[1] = { key = "vitality", level = run.items.vitality or 0 } end
    return choices
end

-- Takes one of the offered items (index into run.choices). Returns false when there is no such choice.
---@param run SurvivorRun
---@param index integer
---@return boolean
function Survivor.Choose(run, index)
    local choice = run.choices and run.choices[index]
    if not choice then return false end
    local item = Survivor.ITEM_BY_KEY[choice.key]
    run.items[choice.key] = math.min(item.maximum, (run.items[choice.key] or 0) + 1)
    if choice.key == "barrier" then run.shield = Survivor.DefenseStats(run).shield end
    if choice.key == "vitality" then
        run.maxHp = Survivor.BASE_HP + 25 * run.items.vitality
        run.hp = math.min(run.maxHp, run.hp + 25)
    end
    run.choices = nil
    if run.pendingLevels > 0 then
        run.pendingLevels = run.pendingLevels - 1
        run.choices = Survivor.Offer(run)
    end
    return true
end

---@param x number
---@param y number
---@return number
local function length(x, y) return math.sqrt(x * x + y * y) end

-- Damages every monster within `radius` of (x, y) (an explosion or a strike from the sky).
---@param run SurvivorRun
---@param x number
---@param y number
---@param radius number
---@param damage number
---@param weapon string
local function blast(run, x, y, radius, damage, weapon)
    for _, enemy in ipairs(run.enemies) do
        if enemy.hp > 0 and length(enemy.x - x, enemy.y - y) <= radius + enemy.radius then hurtEnemy(run, enemy, damage) end
    end
    emit(run, { kind = "blast", x = x, y = y, radius = radius, weapon = weapon })
end

---@param run SurvivorRun
---@param key string
---@param spec RangedWeapon
---@param stats WeaponStats
---@param angle number
local function launch(run, key, spec, stats, angle)
    run.projectiles[#run.projectiles + 1] = { weapon = key, x = 0, y = 0, vx = math.cos(angle) * spec.speed,
        vy = math.sin(angle) * spec.speed, life = spec.life, maxLife = spec.life, damage = stats.damage, radius = spec.radius,
        pierce = stats.pierce or 0, hits = {}, splash = stats.splash, slow = spec.slow, homing = spec.homing,
        boomerang = spec.boomerang }
end

---@param enemy SurvivorEnemy
---@return number
local function angleTo(enemy) return math.atan2(enemy.y, enemy.x) end

-- Fires one volley of a ranged weapon. Returns false when it had nothing to aim at (it then fires next step).
---@param run SurvivorRun
---@param key string
---@param stats WeaponStats
---@param targets SurvivorEnemy[] alive monsters, nearest first
---@return boolean
local function fireRanged(run, key, stats, targets)
    local spec = Survivor.RANGED[key]
    if #targets == 0 then return false end
    if spec.fire == "projectile" then
        if spec.aim == "spiral" then
            local base = run.spirals[key] or 0
            for index = 1, stats.count do launch(run, key, spec, stats, base + (index - 1) * 2 * math.pi / stats.count) end
            run.spirals[key] = base + spec.step
        elseif spec.aim == "spread" then
            local centre = angleTo(targets[1])
            for index = 1, stats.count do
                local offset = stats.count == 1 and 0 or ((index - 1) / (stats.count - 1) - 0.5) * spec.spread
                launch(run, key, spec, stats, centre + offset)
            end
        else   -- nearest: one projectile per monster, nearest first; more projectiles than monsters fan out a little
            for index = 1, stats.count do
                local round = math.floor((index - 1) / #targets)
                launch(run, key, spec, stats, angleTo(targets[(index - 1) % #targets + 1]) + round * 0.25)
            end
        end
    elseif spec.fire == "chain" then
        local current, points, struck = targets[1], { { 0, 0 } }, {}
        for _ = 1, stats.count do
            struck[current.id] = true
            points[#points + 1] = { current.x, current.y }
            hurtEnemy(run, current, stats.damage)
            local nextEnemy, best = nil, spec.jump
            for _, enemy in ipairs(run.enemies) do
                if enemy.hp > 0 and not struck[enemy.id] then
                    local gap = length(enemy.x - current.x, enemy.y - current.y)
                    if gap <= best then nextEnemy, best = enemy, gap end
                end
            end
            if not nextEnemy then break end
            current = nextEnemy
        end
        emit(run, { kind = "zap", points = points, weapon = key })
    else   -- strike: random monsters anywhere in the arena
        local pool = {}
        for index, enemy in ipairs(targets) do pool[index] = enemy end
        for _ = 1, math.min(stats.count, #pool) do
            local enemy = table.remove(pool, math.min(#pool, 1 + math.floor(run.random() * #pool)))
            blast(run, enemy.x, enemy.y, stats.radius, stats.damage, key)
        end
    end
    emit(run, { kind = "shot", weapon = key })
    return true
end

---@param run SurvivorRun
---@param dt number
local function fire(run, dt)
    local targets = nil
    for _, key in ipairs(Survivor.WEAPON_KEYS) do
        local stats = Survivor.WeaponStats(run, key)
        if stats then
            run.cooldowns[key] = (run.cooldowns[key] or 0) - dt
            if run.cooldowns[key] <= 0 then
                targets = targets or nearest(run)
                if Survivor.RANGED[key] then
                    if fireRanged(run, key, stats, targets) then
                        run.cooldowns[key] = stats.cooldown
                        targets = nil   -- monsters may have died
                    end
                else
                    local hitAny = false
                    for _, enemy in ipairs(targets) do
                        local reach = distance(enemy) - enemy.radius
                        if enemy.hp > 0 and reach <= stats.radius then
                            hitAny = true
                            if key == "nova" then enemy.slow = Survivor.NOVA_SLOW_SECONDS end
                            if key == "cleave" and enemy.hp > stats.damage then   -- survivors are pushed back
                                local away = math.max(1, distance(enemy))
                                enemy.x = enemy.x + enemy.x / away * Survivor.CLEAVE_KNOCKBACK
                                enemy.y = enemy.y + enemy.y / away * Survivor.CLEAVE_KNOCKBACK
                            end
                            hurtEnemy(run, enemy, stats.damage)
                        end
                    end
                    -- only swing when something is in reach; the nova always pulses on cooldown
                    if hitAny or key == "nova" then
                        emit(run, { kind = key, radius = stats.radius })
                        run.cooldowns[key] = stats.cooldown
                        targets = nil
                    end
                end
            end
        end
    end
end

-- turns a projectile towards the nearest monster by at most `rate` x dt radians, keeping its speed
---@param run SurvivorRun
---@param projectile SurvivorProjectile
---@param dt number
local function steer(run, projectile, dt)
    local target, best = nil, math.huge
    for _, enemy in ipairs(run.enemies) do
        if enemy.hp > 0 and not projectile.hits[enemy.id] then
            local gap = length(enemy.x - projectile.x, enemy.y - projectile.y)
            if gap < best then target, best = enemy, gap end
        end
    end
    if not target then return end
    local speed = length(projectile.vx, projectile.vy)
    local heading = math.atan2(projectile.vy, projectile.vx)
    local wanted = math.atan2(target.y - projectile.y, target.x - projectile.x)
    local turn = (wanted - heading + math.pi) % (2 * math.pi) - math.pi
    local maximum = projectile.homing * dt
    heading = heading + math.max(-maximum, math.min(maximum, turn))
    projectile.vx, projectile.vy = math.cos(heading) * speed, math.sin(heading) * speed
end

---@param run SurvivorRun
---@param dt number
local function moveProjectiles(run, dt)
    local kept = {}
    for _, projectile in ipairs(run.projectiles) do
        if projectile.homing then steer(run, projectile, dt) end
        if projectile.boomerang then   -- pulled back to the tower: flies out, slows, returns; caught at the tower
            local away = length(projectile.x, projectile.y)
            if away > 0 then
                projectile.vx = projectile.vx - projectile.x / away * projectile.boomerang * dt
                projectile.vy = projectile.vy - projectile.y / away * projectile.boomerang * dt
            end
            if projectile.life < projectile.maxLife * 0.6 and away < Survivor.TOWER_RADIUS then projectile.life = 0 end
        end
        projectile.x, projectile.y = projectile.x + projectile.vx * dt, projectile.y + projectile.vy * dt
        projectile.life = projectile.life - dt
        local alive = true
        for _, enemy in ipairs(run.enemies) do
            if enemy.hp > 0 and not projectile.hits[enemy.id] then
                local reach = enemy.radius + projectile.radius
                local dx, dy = enemy.x - projectile.x, enemy.y - projectile.y
                if dx * dx + dy * dy <= reach * reach then
                    projectile.hits[enemy.id] = true
                    if projectile.slow then enemy.slow = math.max(enemy.slow, projectile.slow) end
                    hurtEnemy(run, enemy, projectile.damage)
                    if projectile.splash then
                        blast(run, projectile.x, projectile.y, projectile.splash, projectile.damage * 0.6, projectile.weapon)
                    end
                    projectile.pierce = projectile.pierce - 1
                    if projectile.pierce < 0 then alive = false break end
                end
            end
        end
        if alive and projectile.life > 0 then kept[#kept + 1] = projectile end
    end
    run.projectiles = kept
end

---@param run SurvivorRun
---@param dt number
local function moveEnemies(run, dt)
    local defense = Survivor.DefenseStats(run)
    local touching, incoming = false, 0
    local kept = {}
    for _, enemy in ipairs(run.enemies) do
        if enemy.hp > 0 then
            enemy.flash = math.max(0, enemy.flash - dt)
            enemy.slow = math.max(0, enemy.slow - dt)
            local length = distance(enemy)
            local contact = Survivor.TOWER_RADIUS + enemy.radius
            if length > contact then
                local step = enemy.speed * dt * (enemy.slow > 0 and Survivor.NOVA_SLOW_FACTOR or 1)
                step = math.min(step, length - contact)
                enemy.x, enemy.y = enemy.x - enemy.x / length * step, enemy.y - enemy.y / length * step
            else
                touching = true
                local damage = enemy.damage * defense.armor * dt
                local deflected = damage * defense.deflect
                incoming = incoming + damage - deflected
                local back = deflected * defense.reflect + defense.thorns * dt
                if back > 0 then hurtEnemy(run, enemy, back) end
            end
            if enemy.hp > 0 then kept[#kept + 1] = enemy end
        end
    end
    run.enemies = kept
    -- the barrier takes the hit first; it refills after a pause without damage
    if incoming > 0 then
        local absorbed = math.min(run.shield, incoming)
        if absorbed > 0 and absorbed == run.shield and defense.shield > 0 then emit(run, { kind = "shieldbreak" }) end
        run.shield = run.shield - absorbed
        run.hp = run.hp - (incoming - absorbed)
        run.shieldPause = Survivor.BARRIER_PAUSE
    else
        run.shieldPause = math.max(0, run.shieldPause - dt)
        if run.shieldPause == 0 then run.shield = math.min(defense.shield, run.shield + Survivor.BARRIER_REFILL * dt) end
    end
    return touching
end

---@param run SurvivorRun
---@param dt number
local function step(run, dt)
    run.time = run.time + dt
    -- spawning
    run.spawnTimer = run.spawnTimer - dt
    while run.spawnTimer <= 0 do
        spawn(run)
        run.spawnTimer = run.spawnTimer + Survivor.Difficulty(run.time)
    end
    fire(run, dt)
    moveProjectiles(run, dt)
    local wasHp = run.hp
    if moveEnemies(run, dt) and math.floor(wasHp / 5) ~= math.floor(run.hp / 5) then emit(run, { kind = "hurt" }) end
    run.hp = math.min(run.maxHp, run.hp + 0.8 * (run.items.regen or 0) * dt)
    -- levels
    while run.xp >= run.xpNext do
        run.xp = run.xp - run.xpNext
        run.level = run.level + 1
        run.xpNext = experienceFor(run.level)
        if run.choices then run.pendingLevels = run.pendingLevels + 1 else run.choices = Survivor.Offer(run) end
        emit(run, { kind = "levelup" })
    end
    -- endless: a new minute raises the payout (and the pending mark, so a reload pays what was reached)
    if run.target.endless then
        local factor = Survivor.EndlessFactor(run.time)
        if factor > (run.reachedFactor or 0) then
            run.reachedFactor = factor
            local database = addon.Store.db
            local pending = database and database.ui and database.ui.survivorPending
            if type(pending) == "table" and pending.name == run.name then pending.factor = factor end
            emit(run, { kind = "milestone", factor = factor })
        end
    end
    -- the end
    if run.hp <= 0 then
        run.hp, run.finished = 0, "lost"
        emit(run, { kind = "lost" })
    elseif run.time >= run.target.seconds then
        run.time, run.finished = run.target.seconds, "won"
        emit(run, { kind = "won" })
    end
end

-- Advances the run by `elapsedSeconds` of real time in fixed steps. Nothing moves while a choice waits or after the end.
---@param run SurvivorRun
---@param elapsedSeconds number
function Survivor.Advance(run, elapsedSeconds)
    run.accumulator = math.min(run.accumulator + math.max(0, elapsedSeconds or 0), 0.25)   -- a hitch skips, not races
    while run.accumulator >= Survivor.STEP and not run.choices and not run.finished do
        run.accumulator = run.accumulator - Survivor.STEP
        step(run, Survivor.STEP)
    end
    if run.choices or run.finished then run.accumulator = 0 end
end

-- Takes (and clears) what happened since the last call.
---@param run SurvivorRun
---@return SurvivorEvent[]
function Survivor.TakeEvents(run)
    local events = run.events
    run.events = {}
    return events
end

------------------------------------------------------------------ betting and storage

---@return table db.ui (free-form settings)
local function settings() return addon.Store.db.ui end

-- A target by index (1 = shortest), or nil.
---@param index any
---@return SurvivorTarget|nil
function Survivor.Target(index)
    if index == Survivor.ENDLESS_INDEX then return Survivor.ENDLESS end
    return type(index) == "number" and Survivor.TARGETS[index] or nil
end

-- The net of a run if it ended now: fixed target won -> (factor - 1) x stake; endless -> the minute reached; else -stake.
---@param run SurvivorRun
---@return integer
function Survivor.Net(run)
    local factor = 0
    if run.target.endless then factor = Survivor.EndlessFactor(run.time)
    elseif run.finished == "won" then factor = run.target.factor end
    return factor >= 2 and run.stake * (factor - 1) or -run.stake
end

-- Starts a run: checks the stake like every play, then books it as PENDING (so leaving mid-run still loses it).
-- Returns the run, or nil and the refusal.
---@param myName string|nil
---@param stake any copper
---@param targetIndex integer
---@param now integer
---@param randomFunction fun(): number
---@return SurvivorRun|nil
---@return FlipRefusal|"target"|nil
function Survivor.Begin(myName, stake, targetIndex, now, randomFunction)
    local target = Survivor.Target(targetIndex)
    if not target then return nil, "target" end
    Survivor.ResolvePending(now)   -- a run left open by a crash is lost before the next one starts (and before the funds check)
    local refused = addon.Games.Refusal(myName, stake, true)
    if refused then return nil, refused end
    settings().survivorPending = { name = myName, c = stake, t = now }
    return Survivor.NewRun(myName, stake, target, randomFunction)
end

-- Books the end of a run: won -> (factor - 1) x stake, anything else (lost, given up) -> -stake. Clears the pending mark.
-- Returns the signed net in copper.
---@param run SurvivorRun
---@param now integer
---@return integer net
function Survivor.Settle(run, now)
    settings().survivorPending = nil
    run.finished = run.finished or "lost"
    local net = Survivor.Net(run)
    run.net = net
    addon.Games.RecordPlay(run.name, "survivor", run.stake, net, now)
    return net
end

-- A run that was still pending (the game was closed or reloaded mid-run) is booked as lost, or for an endless run as
-- the factor it had reached. Returns true when one was booked.
---@param now integer
---@return boolean
function Survivor.ResolvePending(now)
    local database = addon.Store.db
    local pending = database and database.ui and database.ui.survivorPending
    if pending == nil then return false end
    database.ui.survivorPending = nil
    if type(pending) ~= "table" or database.readonly then return false end
    local stake = addon.Utility.SafeInteger(pending.c, 1, addon.Games.MAXIMUM_STAKE)
    if not stake or not addon.Utility.IsSafeName(pending.name) then return false end
    local factor = addon.Utility.SafeInteger(pending.factor, 2, Survivor.ENDLESS_MAXIMUM_FACTOR)
    local stored = addon.Games.RecordPlay(pending.name, "survivor", stake, factor and stake * (factor - 1) or -stake, now)
    return stored and true or false
end
