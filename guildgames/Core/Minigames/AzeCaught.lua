local addonName, addon = ...

-- AZEcaught (feature 018): catch hostile NPCs and raise one as a companion. PURE Lua: no WoW calls. The client side is
-- Core/Game/Catcher.lua (combat log, nameplates, model capture) and UI/AzeCaughtPanel.lua. Clocks and random numbers are
-- PARAMETERS, so any bug report can be replayed offline from `/gg caught export` and the journal.
--
-- Time: needs change only during ACTIVE time (logged in, R10). The client calls AzeCaught.Tick(dt) once a second with
-- the GetTime() delta; each tick is clamped to MAXIMUM_TICK so a hang or loading screen cannot age the companion (RF2).
--
-- Debugging (R19): every step writes one structured line to the AZEcaught JOURNAL (db.caught.journal, its own ring so
-- combat noise cannot push casino lines out of /gg debug). WARNING and ERROR lines are mirrored to the main log.
-- `verbose` echoes every journal line to the chat frame.
---@class AzeCaughtModule
local AzeCaught = {}
addon.AzeCaught = AzeCaught

local library = LibStub("LibGuildSync-1.0")

------------------------------------------------------------------ constants (tunable; tests pin the important ones)

AzeCaught.THROW_HEALTH = 0.35            -- the rope icon shows at or below this health fraction
AzeCaught.CATCH_WINDOW = 3               -- seconds from the throw in which the death must happen
AzeCaught.THROW_COOLDOWN = 3             -- seconds between throws
AzeCaught.BASE_CHANCE = 0.15
AzeCaught.MAXIMUM_CHANCE = 0.25
AzeCaught.CATCH_REWARD = 2 * 10000       -- 2g x 1/difficulty
AzeCaught.MAXIMUM_REWARD = 50 * 10000
AzeCaught.RARITY_FACTOR = { normal = 1.0, elite = 0.6, rare = 0.5, rareelite = 0.35, worldboss = 0.15 }
AzeCaught.RARITY_BONUS = { normal = 0, elite = 5, rare = 10, rareelite = 15, worldboss = 25 }
AzeCaught.CLASSIFICATIONS = { "normal", "elite", "rare", "rareelite", "worldboss" }

AzeCaught.NEEDS = { "hunger", "thirst", "affection", "energy" }
-- the care schedule (R6/R14): seconds of active time from full to NEEDY (50%); empty after twice that
AzeCaught.FOOD_INTERVAL = 2 * 3600
AzeCaught.WATER_INTERVAL = 1 * 3600
AzeCaught.PET_INTERVAL = 2 * 3600
AzeCaught.AWAKE_INTERVAL = 4 * 3600
AzeCaught.SLEEP_DURATION = 1 * 3600
AzeCaught.ASLEEP_DECAY = 0.5             -- hunger/thirst/affection decay at half speed while asleep
AzeCaught.OK_LEVEL = 50                  -- above: ok
AzeCaught.CRITICAL_LEVEL = 25            -- below: critical; between: needy
AzeCaught.DUE_LEVEL = 60                 -- ok but at or below this: "just in time" care (+2 hearts)
AzeCaught.FULL_LEVEL = 95                -- at or above: feeding/watering is refused ("full")
AzeCaught.CARE_STREAK_GAP = 3600         -- the care streak counts at most one care action per hour of play time
AzeCaught.NEGLECT_STEP = 600             -- -1 heart per 10 min with any need critical
AzeCaught.STARVE_TIME = 2 * 3600         -- hunger or thirst at 0 this long: the companion dies
AzeCaught.SNAPSHOT_EVERY = 300           -- a state line in the journal every 5 min of active time
AzeCaught.MAXIMUM_TICK = 5
AzeCaught.FOOD_PRICE = 50 * 100          -- 50s
AzeCaught.WATER_PRICE = 25 * 100         -- 25s
AzeCaught.PAYOUTS = { 500 * 10000, 300 * 10000, 150 * 10000 }
AzeCaught.PAYOUT_OTHER = 25 * 10000
AzeCaught.MAXIMUM_COLLECTION = 2000     -- bound for saved data (the real limits are the two below)
AzeCaught.MAXIMUM_CAUGHT = 10           -- caught NPCs, duplicates count (user 2026-11-20)
AzeCaught.MAXIMUM_SEEN = 100            -- seen-only NPCs; the oldest makes room for a new one
AzeCaught.MAXIMUM_NAME_BYTES = 48
AzeCaught.MAXIMUM_LEVEL = 200
AzeCaught.MAXIMUM_HEARTS = 1000000
AzeCaught.MAXIMUM_ID = 2147483647
AzeCaught.MAXIMUM_WEEKS = 4
AzeCaught.JOURNAL_ENTRIES = 400

-- Stats -> needs (user 2026-11-20): each NPC's need intervals and thresholds come from what the client tells about it.
-- Factors multiply the base interval (smaller = needed more often); false = never needed. Unknown stats: base values.
-- creature type ids: CreatureType (1 beast, 2 dragonkin, 3 demon, 4 elemental, 5 giant, 6 undead, 7 humanoid, 8 critter,
-- 9 mechanical, 15 aberration)
AzeCaught.TYPE_TRAITS = {
    [1] = { key = "beast", hunger = 0.75, affection = 0.75 },
    [2] = { key = "dragonkin", hunger = 0.75, energy = 1.25 },
    [3] = { key = "demon", hunger = 0.75, affection = 1.5, energy = 1.5 },
    [4] = { key = "elemental", hunger = 2, thirst = 0.75 },
    [5] = { key = "giant", hunger = 0.6, thirst = 0.8 },
    [6] = { key = "undead", thirst = false, hunger = 1.5, energy = 2 },
    [8] = { key = "critter", affection = 0.6, hunger = 1.25 },
    [9] = { key = "mechanical", thirst = false, hunger = 1.5, energy = 2 },
    [15] = { key = "aberration", affection = 1.25 },
}
-- power types: 0 mana, 1 rage, 2 focus, 3 energy. bump raises both thresholds (needy and critical come sooner)
AzeCaught.POWER_TRAITS = {
    [0] = { key = "mana", affection = 1.2 },
    [1] = { key = "rage", bump = 5 },
    [2] = { key = "focus", energy = 0.9 },
    [3] = { key = "energy", energy = 0.8 },
}
AzeCaught.RARITY_PICKY = { normal = 0, elite = 3, rare = 3, rareelite = 5, worldboss = 8 }
-- localized creature type names (when the client gives no id): enUS and deDE
AzeCaught.TYPE_NAMES = { beast = 1, wildtier = 1, dragonkin = 2, drachkin = 2, demon = 3, ["d\195\164mon"] = 3, elemental = 4,
    elementar = 4, giant = 5, riese = 5, undead = 6, untoter = 6, humanoid = 7, critter = 8, kleintier = 8, mechanical = 9,
    mechanisch = 9, aberration = 15 }
AzeCaught.MAXIMUM_STAT = 2000000000

-- runtime only (never stored): armed throws by GUID, GUIDs already rolled, last throw time, dev "force next catch"
AzeCaught.throws = {}
AzeCaught.rolled = {}
AzeCaught.thrown = {}   -- GUID -> clock of its throw: one throw per enemy (user 2026-11-20)
AzeCaught.lastThrowAt = nil
AzeCaught.forceNextCatch = false

------------------------------------------------------------------ state and journal

---@class CollectionEntry
---@field n string NPC name (client text)
---@field lvl integer highest level seen
---@field cls string classification (AzeCaught.CLASSIFICATIONS)
---@field disp integer CreatureDisplayInfo id, 0 when unknown
---@field seen integer server time first found
---@field caught integer how many are caught (0 = only found)

---@class CompanionState
---@field npc integer
---@field n string
---@field lvl integer
---@field cls string
---@field disp integer
---@field since number active seconds when selected
---@field hunger number 0..100
---@field thirst number
---@field affection number
---@field energy number
---@field asleep number|nil seconds of sleep left; nil = awake
---@field hearts integer
---@field fedStreak integer
---@field careStreak integer
---@field streakAt number|nil active seconds of the last care action the care streak counted
---@field starve number seconds with hunger or thirst at 0
---@field neglect number seconds with a critical need, not yet turned into a lost heart
---@field snap number seconds since the last snapshot line
---@field zones table<string, string> last zone of each need

-- db.caught, every table present.
---@return table
function AzeCaught.State()
    local database = addon.Store.db
    if type(database.caught) ~= "table" then database.caught = {} end
    local caught = database.caught
    if type(caught.collection) ~= "table" then caught.collection = {} end
    if type(caught.journal) ~= "table" then caught.journal = {} end
    if type(caught.peaks) ~= "table" then caught.peaks = {} end
    if type(caught.activeSeconds) ~= "number" then caught.activeSeconds = 0 end
    if caught.notify == nil then caught.notify = true end
    return caught
end

local journalLog = library.Log.New({
    entries = function()
        local database = addon.Store and addon.Store.db
        if type(database) ~= "table" then return nil end
        return AzeCaught.State().journal
    end,
    title = function() return (addon.TITLE or "GuildGames") .. " AZEcaught" end,
    isDevelopment = function() return addon.IS_DEVELOPMENT_BUILD end,
})
journalLog.MAXIMUM_ENTRIES = AzeCaught.JOURNAL_ENTRIES
AzeCaught.journalLog = journalLog

local LEVEL_FUNCTION = { ERROR = "Error", WARNING = "Warning", INFORMATION = "Information", DEBUG = "Debug" }

-- One journal line (R19). area is "<part>.<step>" and is shown as "caught.<area>". WARNING/ERROR also go to the main log.
---@param level LogLevel
---@param area string
---@param message string
---@param details? table
---@return string body
function AzeCaught.Journal(level, area, message, details)
    local functionName = LEVEL_FUNCTION[level] or "Debug"
    local fullArea = "caught." .. area
    local body = journalLog[functionName](fullArea, message, details)
    if (level == "WARNING" or level == "ERROR") and addon.Log then addon.Log[functionName](fullArea, message, details) end
    local database = addon.Store and addon.Store.db
    if type(database) == "table" and type(database.caught) == "table" and database.caught.verbose and addon.Print then
        addon.Print("|cff88ccff[journal]|r " .. body)
    end
    return body
end

-- A protected call whose failure lands in the journal AND the main log (with the stack).
---@param area string
---@param message string
---@param func function
---@return boolean ok
---@return any ...
function AzeCaught.Protected(area, message, func, ...)
    return addon.Log.Protected("caught." .. area, message, func, ...)
end

-- The last `count` journal lines that contain `filter` (plain text, case-insensitive), oldest first.
---@param count integer
---@param filter? string
---@return string[]
function AzeCaught.JournalLines(count, filter)
    local lines, matched = AzeCaught.State().journal, {}
    local needle = filter and filter ~= "" and filter:lower() or nil
    for index = #lines, 1, -1 do
        if not needle or lines[index]:lower():find(needle, 1, true) then
            table.insert(matched, 1, lines[index])
            if #matched >= count then break end
        end
    end
    return matched
end

------------------------------------------------------------------ helpers

---@param value number
---@param lowest number
---@param highest number
---@return number
local function clamp(value, lowest, highest)
    if value < lowest then return lowest end
    if value > highest then return highest end
    return value
end

---@param value number
---@return number rounded to one decimal (journal values)
local function round1(value) return math.floor(value * 10 + 0.5) / 10 end

-- A known classification ("trivial"/"minus" and unknown values count as normal).
---@param classification any
---@return string
function AzeCaught.Classification(classification)
    if AzeCaught.RARITY_FACTOR[classification] then return classification end
    return "normal"
end

-- The NPC id of a creature/vehicle GUID ("Creature-0-1-2-3-<npcId>-<spawn>"), nil for players, pets and the rest.
---@param guid any
---@return integer|nil
function AzeCaught.NpcIdFromGuid(guid)
    if type(guid) ~= "string" then return nil end
    local unitType, npcId = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    return addon.Utility.SafeInteger(tonumber(npcId), 1, AzeCaught.MAXIMUM_ID)
end

------------------------------------------------------------------ catch chance (R4)

-- 1 at 0 HP, falling logarithmically (steepest near 0 HP): ~0.48 at 10%, ~0.26 at 30%, ~0.23 at 35%, 0 at full health.
-- f(h) = 1 - ln(1 + 99h) / ln(100)
---@param healthFraction number 0..1
---@return number
function AzeCaught.HealthFactor(healthFraction)
    local fraction = clamp(tonumber(healthFraction) or 1, 0, 1)
    return clamp(1 - math.log(1 + 99 * fraction) / math.log(100), 0, 1)
end

---@param classification string
---@param npcLevel integer
---@param playerLevel integer
---@return number difficulty factor (smaller = harder)
---@return number rarityFactor
---@return number levelFactor
function AzeCaught.Difficulty(classification, npcLevel, playerLevel)
    local rarityFactor = AzeCaught.RARITY_FACTOR[AzeCaught.Classification(classification)]
    local levelFactor = clamp(1 - 0.05 * ((npcLevel or playerLevel or 1) - (playerLevel or npcLevel or 1)), 0.25, 1.25)
    return rarityFactor * levelFactor, rarityFactor, levelFactor
end

---@class ChanceBreakdown
---@field chance number
---@field base number
---@field health number health fraction at the throw
---@field healthFactor number
---@field difficulty number
---@field rarityFactor number
---@field levelFactor number
---@field capped boolean

---@param healthFraction number
---@param classification string
---@param npcLevel integer
---@param playerLevel integer
---@return ChanceBreakdown
function AzeCaught.Chance(healthFraction, classification, npcLevel, playerLevel)
    local healthFactor = AzeCaught.HealthFactor(healthFraction)
    local difficulty, rarityFactor, levelFactor = AzeCaught.Difficulty(classification, npcLevel, playerLevel)
    local raw = AzeCaught.BASE_CHANCE * healthFactor * difficulty
    return { chance = math.min(raw, AzeCaught.MAXIMUM_CHANCE), base = AzeCaught.BASE_CHANCE, health = healthFraction,
        healthFactor = healthFactor, difficulty = difficulty, rarityFactor = rarityFactor, levelFactor = levelFactor,
        capped = raw > AzeCaught.MAXIMUM_CHANCE }
end

-- How good a moment to throw is (user 2026-11-20: the icon glow goes from red to green): 0 at THROW_HEALTH (the worst
-- chance the icon is shown for), 1 at 0 HP (the best). It follows the health factor, so it rises like the chance.
-- nil when the client hides the health.
---@param healthFraction number|nil
---@return number|nil
function AzeCaught.ThrowQuality(healthFraction)
    if type(healthFraction) ~= "number" or healthFraction ~= healthFraction then return nil end
    local worst = AzeCaught.HealthFactor(AzeCaught.THROW_HEALTH)
    return clamp((AzeCaught.HealthFactor(healthFraction) - worst) / (1 - worst), 0, 1)
end

-- red (0) -> yellow (0.5) -> green (1); nil (unknown) -> yellow
---@param quality number|nil
---@return number r
---@return number g
---@return number b
function AzeCaught.QualityColor(quality)
    if not quality then return 1, 0.82, 0.2 end
    if quality < 0.5 then return 1, 0.15 + 0.7 * quality * 2, 0.1 end
    return 1 - 0.8 * (quality - 0.5) * 2, 0.85 + 0.15 * (quality - 0.5) * 2, 0.1 + 0.2 * (quality - 0.5) * 2
end

------------------------------------------------------------------ throw effect: where the target is on the screen

-- The client hides nameplate positions (restricted regions; measuring one taints the addon), so the rope's landing
-- point is estimated with a pinhole camera behind the player (user 2026-11-20: "trigonometrically calculated and scale
-- accordingly like its getting distance"). World units are yards: x right, y ahead (the camera looks along the
-- player's facing), z up from the ground. The screen centre is the camera's focus point above the player.
AzeCaught.CAMERA = {
    zoom = 12,                      -- yards behind the focus point when GetCameraZoom is unknown
    pitch = math.rad(20),           -- the camera looks down this much (the default follow camera)
    verticalFov = math.rad(50),     -- WoW keeps the vertical field of view (wide screens see more to the sides)
    focusHeight = 2,                -- the camera looks at this height above the player's feet
    bodyHeight = 1,                 -- the rope aims at this height (the middle of a body)
    margin = 24,                    -- a projected point stays this far inside the screen
}

-- Screen point (UIParent units, from the bottom-left) and size factor (1 = the player's body) of a body `distance` yards
-- away at `bearing` radians from straight ahead (+ right). view = { width, height, zoom? }.
---@param view { width: number, height: number, zoom: number|nil }
---@param distance number
---@param bearing number
---@return number x
---@return number y
---@return number scale
function AzeCaught.ProjectToScreen(view, distance, bearing)
    local camera = AzeCaught.CAMERA
    local zoom = (type(view.zoom) == "number" and view.zoom > 0) and view.zoom or camera.zoom
    local cosPitch, sinPitch = math.cos(camera.pitch), math.sin(camera.pitch)
    local focal = (view.height / 2) / math.tan(camera.verticalFov / 2)
    local function depthAndOffsets(ahead, right)
        -- from the camera (behind and above the focus point) to the body
        local toAhead = ahead + zoom * cosPitch
        local toUp = camera.bodyHeight - camera.focusHeight - zoom * sinPitch
        return toAhead * cosPitch - toUp * sinPitch, right, toAhead * sinPitch + toUp * cosPitch
    end
    local referenceDepth = depthAndOffsets(0, 0)
    local depth, right, up = depthAndOffsets(distance * math.cos(bearing), distance * math.sin(bearing))
    depth = math.max(depth, 1)   -- beside or behind the camera: pinned near the edge instead of mirrored
    local x = view.width / 2 + focal * right / depth
    local y = view.height / 2 + focal * up / depth
    local margin = camera.margin
    x = math.max(margin, math.min(view.width - margin, x))
    y = math.max(margin, math.min(view.height - margin, y))
    return x, y, referenceDepth / depth
end

-- Copper paid for a catch: CATCH_REWARD / difficulty, at most MAXIMUM_REWARD.
---@param difficulty number
---@return integer
function AzeCaught.Reward(difficulty)
    return math.min(AzeCaught.MAXIMUM_REWARD, math.floor(AzeCaught.CATCH_REWARD / math.max(difficulty, 0.01)))
end

------------------------------------------------------------------ collection (R1, R6)

---@class NpcStats what the client told about an NPC (any field may be missing: hidden or never seen)
---@field type? integer creature type id
---@field typeName? string creature type as the client names it (display only)
---@field family? string beast family (display only)
---@field hp? integer highest maximum health seen
---@field power? integer power type (0 mana, 1 rage, 2 focus, 3 energy, ...)
---@field powerMax? integer
---@field sex? integer 1 neutral, 2 male, 3 female

---@class NpcInformation
---@field npc integer
---@field name? string
---@field level? integer
---@field classification? string
---@field display? integer
---@field stats? NpcStats

-- The creature type id from the client's id or its localized name (enUS/deDE), nil when unknown.
---@param typeId any
---@param typeName any
---@return integer|nil
function AzeCaught.CreatureTypeId(typeId, typeName)
    local id = addon.Utility.SafeInteger(typeId, 1, 100)
    if id then return id end
    if type(typeName) ~= "string" then return nil end
    return AzeCaught.TYPE_NAMES[typeName:lower()]
end

-- A clean copy of a stats table (bounded; bad fields dropped), or nil when nothing is left.
---@param stats any
---@return NpcStats|nil
function AzeCaught.CleanStats(stats)
    if type(stats) ~= "table" then return nil end
    local Utility = addon.Utility
    local clean = { type = Utility.SafeInteger(stats.type, 1, 100), typeName = Utility.CleanString(stats.typeName, 32),
        family = Utility.CleanString(stats.family, 32), hp = Utility.SafeInteger(stats.hp, 1, AzeCaught.MAXIMUM_STAT),
        power = Utility.SafeInteger(stats.power, 0, 30), powerMax = Utility.SafeInteger(stats.powerMax, 0, AzeCaught.MAXIMUM_STAT),
        sex = Utility.SafeInteger(stats.sex, 1, 3) }
    if next(clean) == nil then return nil end
    return clean
end

-- Fills the stats an entry does not know yet (a known type stays; the highest health counts). Returns true on a change.
---@param entry CollectionEntry
---@param stats NpcStats|nil
---@return boolean changed
local function mergeStats(entry, stats)
    stats = AzeCaught.CleanStats(stats)
    if not stats then return false end
    entry.st = entry.st or {}
    local changed = false
    for _, field in ipairs({ "type", "typeName", "family", "power", "powerMax", "sex" }) do
        if entry.st[field] == nil and stats[field] ~= nil then entry.st[field], changed = stats[field], true end
    end
    if stats.hp and (entry.st.hp == nil or stats.hp > entry.st.hp) then entry.st.hp, changed = stats.hp, true end
    return changed
end

-- Adds or updates a found NPC. Fast and silent when nothing new is learned (the combat log calls it on every hit).
---@param info NpcInformation
---@param now integer server time
---@return CollectionEntry|nil entry
---@return boolean isNew
function AzeCaught.NoteFound(info, now)
    local Utility = addon.Utility
    local npcId = type(info) == "table" and Utility.SafeInteger(info.npc, 1, AzeCaught.MAXIMUM_ID)
    if not npcId then return nil, false end
    local collection = AzeCaught.State().collection
    local entry = collection[npcId]
    local level = Utility.SafeInteger(info.level, 1, AzeCaught.MAXIMUM_LEVEL)
    local display = Utility.SafeInteger(info.display, 1, AzeCaught.MAXIMUM_ID)
    if entry then
        local changed = mergeStats(entry, info.stats)
        if changed then AzeCaught.ForgetProfile(npcId) end
        if level and level > entry.lvl then entry.lvl, changed = level, true end
        if display and entry.disp == 0 then entry.disp, changed = display, true end
        if info.classification and AzeCaught.RARITY_FACTOR[info.classification] and entry.cls == "normal"
            and info.classification ~= "normal" then
            entry.cls, changed = info.classification, true
        end
        if (entry.n == "?" or entry.n == "") and type(info.name) == "string" and info.name ~= "" then
            entry.n = Utility.TruncateUtf8(Utility.StripControlCharacters(info.name), AzeCaught.MAXIMUM_NAME_BYTES)
            changed = true
        end
        if changed then
            AzeCaught.Journal("DEBUG", "found.update", "a found NPC was updated",
                { npc = npcId, name = entry.n, level = entry.lvl, class = entry.cls, display = entry.disp,
                  stats = AzeCaught.StatsText(entry.st) })
        end
        return entry, false
    end
    -- the seen list is limited: the NPC seen longest ago that is not caught makes room (caught ones are never dropped)
    local seenOnly, oldestId, oldestSeen = 0, nil, math.huge
    for otherId, other in pairs(collection) do
        if (other.caught or 0) < 1 then
            seenOnly = seenOnly + 1
            if other.seen < oldestSeen then oldestId, oldestSeen = otherId, other.seen end
        end
    end
    if seenOnly >= AzeCaught.MAXIMUM_SEEN and oldestId then
        AzeCaught.Journal("DEBUG", "found.evicted", "the oldest seen NPC made room", { npc = oldestId, name = collection[oldestId].n,
            limit = AzeCaught.MAXIMUM_SEEN })
        collection[oldestId] = nil
    end
    local name = type(info.name) == "string" and info.name ~= "" and info.name or "?"
    entry = { n = Utility.TruncateUtf8(Utility.StripControlCharacters(name), AzeCaught.MAXIMUM_NAME_BYTES),
        lvl = level or 1, cls = AzeCaught.Classification(info.classification), disp = display or 0, seen = now, caught = 0 }
    mergeStats(entry, info.stats)
    collection[npcId] = entry
    AzeCaught.Journal("INFORMATION", "found.new", "a new NPC was found",
        { npc = npcId, name = entry.n, level = entry.lvl, class = entry.cls, display = entry.disp, stats = AzeCaught.StatsText(entry.st) })
    return entry, true
end

-- How many NPCs are caught (duplicates count); at most MAXIMUM_CAUGHT.
---@return integer
function AzeCaught.CaughtCount()
    local count = 0
    for _, entry in pairs(AzeCaught.State().collection) do count = count + (entry.caught or 0) end
    return count
end

------------------------------------------------------------------ throwing and rolling (R2, R3, R5)

---@class ThrowTarget : NpcInformation
---@field guid string
---@field health number fraction 0..1

-- Arms a throw at a unit. Returns true, or nil and why: "unknown" (no NPC), "health" (above THROW_HEALTH),
-- "cooldown", "dead", "rolled" (this GUID already had its roll).
---@param target ThrowTarget
---@param playerLevel integer
---@param clockSeconds number GetTime()
---@param now integer server time
---@return boolean|nil
---@return string|nil reason
function AzeCaught.Throw(target, playerLevel, clockSeconds, now)
    local npcId = type(target) == "table" and AzeCaught.NpcIdFromGuid(target.guid)
    local function refuse(reason, extra)
        local details = { reason = reason, guid = type(target) == "table" and tostring(target.guid) or "nil" }
        for key, value in pairs(extra or {}) do details[key] = value end
        AzeCaught.Journal("DEBUG", "throw.refused", "a throw was refused", details)
        return nil, reason
    end
    if not npcId then return refuse("unknown") end
    if AzeCaught.rolled[target.guid] then return refuse("rolled", { npc = npcId }) end
    if AzeCaught.thrown[target.guid] then return refuse("thrown", { npc = npcId }) end
    if AzeCaught.CaughtCount() >= AzeCaught.MAXIMUM_CAUGHT then
        return refuse("full", { npc = npcId, caught = AzeCaught.CaughtCount(), limit = AzeCaught.MAXIMUM_CAUGHT })
    end
    -- the client may hide the health (a secret in combat/instances): then the throw is allowed and rolls as if the NPC
    -- were at THROW_HEALTH, the worst case
    local healthKnown = type(target.health) == "number" and target.health == target.health
    local health = healthKnown and target.health or AzeCaught.THROW_HEALTH
    if healthKnown and health <= 0 then return refuse("dead", { npc = npcId }) end
    if healthKnown and health > AzeCaught.THROW_HEALTH then return refuse("health", { npc = npcId, hp = round1(health * 100) }) end
    if AzeCaught.lastThrowAt and clockSeconds - AzeCaught.lastThrowAt < AzeCaught.THROW_COOLDOWN then
        return refuse("cooldown", { npc = npcId, left = round1(AzeCaught.THROW_COOLDOWN - (clockSeconds - AzeCaught.lastThrowAt)) })
    end
    AzeCaught.NoteFound({ npc = npcId, name = target.name, level = target.level, classification = target.classification,
        display = target.display }, now)
    AzeCaught.lastThrowAt = clockSeconds
    AzeCaught.thrown[target.guid] = clockSeconds
    AzeCaught.throws[target.guid] = { at = clockSeconds, npc = npcId, health = health, playerLevel = playerLevel,
        level = target.level, classification = AzeCaught.Classification(target.classification) }
    AzeCaught.Journal("INFORMATION", "throw.armed", "a rope was thrown",
        { npc = npcId, guid = target.guid, hp = healthKnown and round1(health * 100) or "hidden", level = target.level, class = target.classification,
          playerLevel = playerLevel, window = AzeCaught.CATCH_WINDOW })
    return true
end

-- Forgets armed throws and rolled GUIDs older than a minute (bounded memory).
---@param clockSeconds number
function AzeCaught.ExpireThrows(clockSeconds)
    for guid, throw in pairs(AzeCaught.throws) do
        if clockSeconds - throw.at > 60 then AzeCaught.throws[guid] = nil end
    end
    for guid, at in pairs(AzeCaught.rolled) do
        if clockSeconds - at > 60 then AzeCaught.rolled[guid] = nil end
    end
    for guid, at in pairs(AzeCaught.thrown) do
        if clockSeconds - at > 600 then AzeCaught.thrown[guid] = nil end
    end
end

---@class RollResult
---@field caught boolean
---@field npc integer
---@field chance number
---@field roll number
---@field reward integer copper paid (0 when not caught)
---@field forced boolean
---@field first boolean the guaranteed first catch (user 2026-11-20)

-- A unit died. Rolls ONCE when it was thrown at within CATCH_WINDOW (RF1). Returns the roll, or nil and why:
-- "nothrow", "late", "rolled".
---@param guid string
---@param myName string|nil
---@param clockSeconds number GetTime()
---@param now integer server time
---@param randomFunction fun(): number
---@return RollResult|nil
---@return string|nil reason
function AzeCaught.OnDeath(guid, myName, clockSeconds, now, randomFunction)
    if AzeCaught.rolled[guid] then return nil, "rolled" end
    local throw = AzeCaught.throws[guid]
    if not throw then return nil, "nothrow" end
    AzeCaught.throws[guid] = nil
    AzeCaught.rolled[guid] = clockSeconds
    local elapsed = clockSeconds - throw.at
    if elapsed > AzeCaught.CATCH_WINDOW then
        AzeCaught.Journal("INFORMATION", "roll.late", "the NPC died after the catch window",
            { npc = throw.npc, guid = guid, elapsed = round1(elapsed), window = AzeCaught.CATCH_WINDOW })
        return nil, "late"
    end
    if AzeCaught.CaughtCount() >= AzeCaught.MAXIMUM_CAUGHT then
        AzeCaught.Journal("INFORMATION", "roll.full", "no roll: the caught list filled up before the kill",
            { npc = throw.npc, guid = guid, limit = AzeCaught.MAXIMUM_CAUGHT })
        return nil, "full"
    end
    local entry = AzeCaught.State().collection[throw.npc]
    -- a level never seen (hidden by the client: stored as 1) counts as the player's own level, never as an easy catch
    local npcLevel = throw.level or (entry and entry.lvl > 1 and entry.lvl) or throw.playerLevel
    local breakdown = AzeCaught.Chance(throw.health, throw.classification, npcLevel, throw.playerLevel)
    local roll = randomFunction()
    local forced = AzeCaught.forceNextCatch
    AzeCaught.forceNextCatch = false
    -- the first catch roll a character ever makes succeeds (a player's first companion is never left to luck)
    local caughtState = AzeCaught.State()
    local first = not caughtState.firstCatchDone and not addon.Store.db.readonly
    local caught = forced or first or roll < breakdown.chance
    if caught then caughtState.firstCatchDone = true end
    local result = { caught = caught, npc = throw.npc, chance = breakdown.chance, roll = roll, reward = 0, forced = forced,
        first = first }
    AzeCaught.Journal("INFORMATION", "roll", caught and "the catch roll succeeded" or "the catch roll failed",
        { npc = throw.npc, guid = guid, elapsed = round1(elapsed), chance = ("%.4f"):format(breakdown.chance),
          roll = ("%.4f"):format(roll), base = breakdown.base, hp = round1(breakdown.health * 100),
          healthFactor = ("%.3f"):format(breakdown.healthFactor), rarity = breakdown.rarityFactor,
          levelFactor = ("%.2f"):format(breakdown.levelFactor), capped = breakdown.capped, forced = forced or nil,
          first = first or nil })
    if not caught then return result end
    if entry then
        entry.caught = math.min(AzeCaught.MAXIMUM_ID, entry.caught + 1)
        result.reward = AzeCaught.Reward(breakdown.difficulty)
        AzeCaught.Journal("INFORMATION", "catch", "an NPC was caught",
            { npc = throw.npc, name = entry.n, timesCaught = entry.caught, reward = result.reward })
        if result.reward > 0 then addon.Wallet.Earn(myName, result.reward, "catch", now, entry.n) end
    else
        AzeCaught.Journal("ERROR", "catch", "a caught NPC is missing from the collection", { npc = throw.npc })
    end
    return result
end

------------------------------------------------------------------ companion (R7-R13)

---@param value number
---@return "ok"|"needy"|"critical"|"empty"
---@param okLevel? number default OK_LEVEL
---@param criticalLevel? number default CRITICAL_LEVEL
function AzeCaught.Zone(value, okLevel, criticalLevel)
    -- a tiny tolerance: second-by-second decay lands on 50.0000001 after exactly one interval, which is "due"
    local epsilon = 1e-6
    if value <= epsilon then return "empty" end
    if value < (criticalLevel or AzeCaught.CRITICAL_LEVEL) - epsilon then return "critical" end
    if value <= (okLevel or AzeCaught.OK_LEVEL) + epsilon then return "needy" end
    return "ok"
end

---@class NeedProfile
---@field intervals table<string, number|nil> seconds from full to needy per need; nil = never needed
---@field ok number needy at or below
---@field critical number critical below
---@field traits string[] trait keys (type, power, rarity) that shaped it

local NEED_INTERVAL = { hunger = "FOOD_INTERVAL", thirst = "WATER_INTERVAL", affection = "PET_INTERVAL", energy = "AWAKE_INTERVAL" }

-- The needs of an NPC from its stats (user 2026-11-20). No stats: the base schedule and thresholds.
---@param entry { cls: string, st?: NpcStats }|nil
---@return NeedProfile
function AzeCaught.Profile(entry)
    local stats = type(entry) == "table" and type(entry.st) == "table" and entry.st or {}
    local factors = { hunger = 1, thirst = 1, affection = 1, energy = 1 }
    local bump, traits = 0, {}
    local function apply(trait)
        if not trait then return end
        traits[#traits + 1] = trait.key
        for need in pairs(factors) do
            local factor = trait[need]
            if factor == false then factors[need] = false
            elseif type(factor) == "number" and factors[need] then factors[need] = factors[need] * factor end
        end
        bump = bump + (trait.bump or 0)
    end
    apply(AzeCaught.TYPE_TRAITS[stats.type])
    apply(AzeCaught.POWER_TRAITS[stats.power])
    local classification = AzeCaught.Classification(type(entry) == "table" and entry.cls)
    local picky = AzeCaught.RARITY_PICKY[classification] or 0
    if picky > 0 then traits[#traits + 1] = classification; bump = bump + picky end
    local intervals = {}
    for need, constant in pairs(NEED_INTERVAL) do
        intervals[need] = factors[need] and AzeCaught[constant] * factors[need] or nil
    end
    local critical = clamp(AzeCaught.CRITICAL_LEVEL + bump, 10, 40)
    local ok = clamp(AzeCaught.OK_LEVEL + bump, critical + 10, 80)
    return { intervals = intervals, ok = ok, critical = critical, traits = traits }
end

local profileCache = setmetatable({}, { __mode = "k" })

-- The profile of a companion (from its collection entry; cached until the entry's stats change).
---@param companion CompanionState|nil
---@return NeedProfile
function AzeCaught.ProfileOf(companion)
    if type(companion) ~= "table" then return AzeCaught.Profile(nil) end
    local cached = profileCache[companion]
    if cached then return cached end
    local database = addon.Store and addon.Store.db
    local collection = type(database) == "table" and type(database.caught) == "table" and database.caught.collection
    local entry = type(collection) == "table" and collection[companion.npc] or { cls = companion.cls }
    local profile = AzeCaught.Profile(entry)
    profileCache[companion] = profile
    return profile
end

-- Forgets cached profiles of `npcId` (its stats changed).
---@param npcId integer
function AzeCaught.ForgetProfile(npcId)
    for companion in pairs(profileCache) do
        if companion.npc == npcId then profileCache[companion] = nil end
    end
end

-- The zone of one need of a companion, with the companion's own thresholds.
---@param companion CompanionState
---@param need string
---@return "ok"|"needy"|"critical"|"empty"
function AzeCaught.ZoneOf(companion, need)
    local profile = AzeCaught.ProfileOf(companion)
    return AzeCaught.Zone(companion[need], profile.ok, profile.critical)
end

------------------------------------------------------------------ combat stats (display only, user 2026-11-20)
-- Attack / Defense / Speed are calculated, never stored or sent: the same NPC shows the same numbers to everyone, and a
-- formula change applies to every NPC at once. value = (10 + 2 x level) x rarity x type weight x NPC spread (+-15%).

AzeCaught.COMBAT_BASE, AzeCaught.COMBAT_PER_LEVEL, AzeCaught.COMBAT_SPREAD = 10, 2, 0.15
AzeCaught.COMBAT_RARITY = { normal = 1, elite = 1.5, rare = 1.4, rareelite = 1.8, worldboss = 3 }
-- creature type id -> { attack, defense, speed }; types not listed (and unknown ones) are 1/1/1
AzeCaught.COMBAT_TYPES = {
    [1] = { 1.1, 0.9, 1.3 },   -- beast: quick
    [3] = { 1.3, 0.9, 1.0 },   -- demon: hits hard
    [6] = { 1.0, 1.3, 0.7 },   -- undead: tough and slow
    [9] = { 0.9, 1.4, 0.8 },   -- mechanical: armoured
}
AzeCaught.COMBAT_REFERENCE_LEVEL = 60   -- the base of a normal NPC of this level is a full bar (user 2026-11-20)
local COMBAT_KEYS = { "attack", "defense", "speed" }

-- The value of a full stat bar: the base of a normal NPC at COMBAT_REFERENCE_LEVEL.
---@return number
function AzeCaught.CombatScale()
    return AzeCaught.COMBAT_BASE + AzeCaught.COMBAT_PER_LEVEL * AzeCaught.COMBAT_REFERENCE_LEVEL
end
local HASH_MODULUS, HASH_MULTIPLIER = 2147483647, 48271   -- Park-Miller: exact in doubles (no bit library needed)

-- Three fixed rolls in [0, 1) for an NPC id. Warm-up steps spread neighbouring ids apart.
---@param npcId integer
---@return number[]
local function npcRolls(npcId)
    local value = (math.floor(math.abs(tonumber(npcId) or 0)) % (HASH_MODULUS - 1)) + 1
    for _ = 1, 4 do value = (value * HASH_MULTIPLIER) % HASH_MODULUS end
    local rolls = {}
    for index = 1, 3 do
        value = (value * HASH_MULTIPLIER) % HASH_MODULUS
        rolls[index] = (value - 1) / (HASH_MODULUS - 1)
    end
    return rolls
end

-- The Attack / Defense / Speed of a collection entry (any field may be missing or bad: neutral values are used).
---@param npcId integer
---@param entry { lvl?: integer, cls?: string, st?: NpcStats }|nil
---@return { attack: integer, defense: integer, speed: integer }
function AzeCaught.CombatStats(npcId, entry)
    entry = type(entry) == "table" and entry or {}
    local level = addon.Utility.SafeInteger(entry.lvl, 1, AzeCaught.MAXIMUM_LEVEL) or 1
    local base = (AzeCaught.COMBAT_BASE + AzeCaught.COMBAT_PER_LEVEL * level)
        * AzeCaught.COMBAT_RARITY[AzeCaught.Classification(entry.cls)]
    local typeId = type(entry.st) == "table" and entry.st.type or nil
    local weights = AzeCaught.COMBAT_TYPES[typeId] or { 1, 1, 1 }
    local rolls, result = npcRolls(npcId), {}
    for index, key in ipairs(COMBAT_KEYS) do
        local spread = 1 - AzeCaught.COMBAT_SPREAD + 2 * AzeCaught.COMBAT_SPREAD * rolls[index]
        result[key] = math.max(1, math.floor(base * weights[index] * spread + 0.5))
    end
    return result
end

-- One line of stats for the journal ("hp:900,power:1,type:1").
---@param stats NpcStats|nil
---@return string
function AzeCaught.StatsText(stats)
    if type(stats) ~= "table" then return "none" end
    local parts = {}
    for _, key in ipairs(addon.Utility.SortedKeys(stats)) do parts[#parts + 1] = key .. ":" .. tostring(stats[key]) end
    return #parts > 0 and table.concat(parts, ",") or "none"
end

-- points per second a need loses while awake: full (100) to needy takes its interval (0 when it is never needed)
---@param need string
---@param companion? CompanionState its profile; nil = the base schedule
---@return number
function AzeCaught.DecayPerSecond(need, companion)
    local profile = AzeCaught.ProfileOf(companion)
    local interval = profile.intervals[need]
    if not interval then return 0 end
    return (100 - profile.ok) / interval
end

-- Seconds of active time until `need` falls to the needy zone (0 when it is already there), for the minimap tooltip.
---@param companion CompanionState
---@param need string
---@return number
function AzeCaught.SecondsUntilNeedy(companion, need)
    local value = companion[need]
    if AzeCaught.ZoneOf(companion, need) ~= "ok" then return 0 end
    local perSecond = AzeCaught.DecayPerSecond(need, companion)
    if perSecond <= 0 then return math.huge end
    local profile = AzeCaught.ProfileOf(companion)
    if companion.asleep then
        if need == "energy" then return math.huge end
        perSecond = perSecond * AzeCaught.ASLEEP_DECAY
    end
    return (value - profile.ok) / perSecond
end

-- The companion's ranking value (R16): NPC level + rarity bonus + hearts.
---@param companion { lvl: integer, cls: string, hearts: integer }|nil
---@return integer|nil
function AzeCaught.CompanionLevel(companion)
    if type(companion) ~= "table" then return nil end
    return (companion.lvl or 0) + (AzeCaught.RARITY_BONUS[AzeCaught.Classification(companion.cls)] or 0) + (companion.hearts or 0)
end

---@return CompanionState|nil
function AzeCaught.Active() return AzeCaught.State().active end

-- Every value of the companion in one table (journal details for select, death, run-away, snapshot).
---@param companion CompanionState
---@return table
function AzeCaught.Describe(companion)
    return { npc = companion.npc, name = companion.n, level = companion.lvl, class = companion.cls, display = companion.disp,
        hunger = round1(companion.hunger), thirst = round1(companion.thirst), affection = round1(companion.affection),
        energy = round1(companion.energy), asleep = companion.asleep and round1(companion.asleep) or nil,
        hearts = companion.hearts, fedStreak = companion.fedStreak, careStreak = companion.careStreak,
        starve = round1(companion.starve), neglect = round1(companion.neglect),
        age = round1(AzeCaught.State().activeSeconds - companion.since), rank = AzeCaught.CompanionLevel(companion),
        streakIn = companion.streakAt and math.max(0, round1(AzeCaught.CARE_STREAK_GAP
            - (AzeCaught.State().activeSeconds - companion.streakAt))) or 0 }
end

---@param companion CompanionState
---@param delta integer
---@param reason string
local function changeHearts(companion, delta, reason)
    if delta == 0 then return end
    local before = companion.hearts
    companion.hearts = clamp(before + delta, -AzeCaught.MAXIMUM_HEARTS, AzeCaught.MAXIMUM_HEARTS)
    AzeCaught.Journal("INFORMATION", "hearts", "hearts changed",
        { delta = delta, reason = reason, before = before, after = companion.hearts, npc = companion.npc })
    AzeCaught.NotePeak(companion)
end

-- Remembers my best companion level of this week (the weekly ranking, R17).
---@param companion CompanionState
---@param now? integer
function AzeCaught.NotePeak(companion, now)
    local caught = AzeCaught.State()
    local periodKey = addon.Games.PeriodKey(now or addon.Utility.Now())
    local level = AzeCaught.CompanionLevel(companion)
    if level and (caught.peaks[periodKey] == nil or level > caught.peaks[periodKey]) then
        caught.peaks[periodKey] = level
        local keys = addon.Utility.SortedKeys(caught.peaks)
        for index = 1, #keys - AzeCaught.MAXIMUM_WEEKS do caught.peaks[keys[index]] = nil end
    end
end

-- Removes one catch of `npcId` (death, running away). The entry stays in the collection as found.
---@param npcId integer
local function releaseOne(npcId)
    local entry = AzeCaught.State().collection[npcId]
    if entry then entry.caught = math.max(0, entry.caught - 1) end
end

---@alias SelectRefusal "unknown"|"notcaught"|"same"|"readonly"

-- Makes a caught NPC the active companion, fresh (R7). A previous companion with negative hearts runs away.
---@param npcId any
---@param now integer server time
---@return CompanionState|nil
---@return SelectRefusal|nil
---@return table|nil ranAway the description of the companion that ran away
function AzeCaught.Select(npcId, now)
    local caught = AzeCaught.State()
    if addon.Store.db.readonly then return nil, "readonly" end
    local entry = caught.collection[npcId]
    if not entry then return nil, "unknown" end
    if (entry.caught or 0) < 1 then return nil, "notcaught" end
    local previous = caught.active
    if previous and previous.npc == npcId then return nil, "same" end
    local ranAway
    if previous then
        if previous.hearts < 0 then
            ranAway = AzeCaught.Describe(previous)
            releaseOne(previous.npc)
            AzeCaught.Journal("INFORMATION", "companion.ranAway", "the old companion ran away (negative hearts)", ranAway)
        else
            AzeCaught.Journal("INFORMATION", "companion.switch", "the old companion went back to the collection",
                AzeCaught.Describe(previous))
        end
    end
    local companion = { npc = npcId, n = entry.n, lvl = entry.lvl, cls = entry.cls, disp = entry.disp,
        since = caught.activeSeconds, hunger = 100, thirst = 100, affection = 100, energy = 100, asleep = nil, hearts = 0,
        fedStreak = 0, careStreak = 0, starve = 0, neglect = 0, snap = 0,
        zones = { hunger = "ok", thirst = "ok", affection = "ok", energy = "ok" } }
    caught.active = companion
    AzeCaught.NotePeak(companion, now)
    local description = AzeCaught.Describe(companion)
    local profile = AzeCaught.ProfileOf(companion)
    description.profile = ("ok<=%d critical<%d food=%s water=%s pet=%s awake=%s traits=%s"):format(profile.ok, profile.critical,
        tostring(profile.intervals.hunger), tostring(profile.intervals.thirst), tostring(profile.intervals.affection),
        tostring(profile.intervals.energy), table.concat(profile.traits, ","))
    AzeCaught.Journal("INFORMATION", "companion.select", "a companion was selected", description)
    return companion, nil, ranAway
end

-- The companion dies (R13): it loses its catch and the active slot is emptied.
---@param companion CompanionState
---@param cause string
local function die(companion, cause)
    local description = AzeCaught.Describe(companion)
    description.cause = cause
    AzeCaught.Journal("WARNING", "companion.death", "the companion died", description)
    releaseOne(companion.npc)
    AzeCaught.State().active = nil
    AzeCaught.lastDeath = description
end

---@class TickResult
---@field died boolean
---@field changed boolean a zone or the hearts changed (the UI and the published record should refresh)

-- Advances active time by `dt` seconds (R10). Clamped to MAXIMUM_TICK (RF2).
---@param dt number
---@param now? integer server time (for the weekly peak)
---@return TickResult
function AzeCaught.Tick(dt, now)
    local caught = AzeCaught.State()
    local result = { died = false, changed = false }
    dt = tonumber(dt) or 0
    if dt ~= dt or dt <= 0 then return result end
    if dt > AzeCaught.MAXIMUM_TICK then
        AzeCaught.Journal("DEBUG", "tick.clamped", "a long tick was clamped", { dt = round1(dt), used = AzeCaught.MAXIMUM_TICK })
        dt = AzeCaught.MAXIMUM_TICK
    end
    caught.activeSeconds = caught.activeSeconds + dt
    local companion = caught.active
    if not companion then return result end
    local heartsBefore = companion.hearts

    -- decay / sleep
    local otherFactor = companion.asleep and AzeCaught.ASLEEP_DECAY or 1
    companion.hunger = clamp(companion.hunger - dt * AzeCaught.DecayPerSecond("hunger", companion) * otherFactor, 0, 100)
    companion.thirst = clamp(companion.thirst - dt * AzeCaught.DecayPerSecond("thirst", companion) * otherFactor, 0, 100)
    companion.affection = clamp(companion.affection - dt * AzeCaught.DecayPerSecond("affection", companion) * otherFactor, 0, 100)
    if companion.asleep then
        companion.energy = clamp(companion.energy + dt * 100 / AzeCaught.SLEEP_DURATION, 0, 100)
        companion.asleep = companion.asleep - dt
        if companion.asleep <= 0 then
            companion.asleep = nil
            AzeCaught.Journal("INFORMATION", "companion.wake", "the companion woke up after its sleep",
                { npc = companion.npc, energy = round1(companion.energy) })
            result.changed = true
        end
    else
        companion.energy = clamp(companion.energy - dt * AzeCaught.DecayPerSecond("energy", companion), 0, 100)
    end

    -- zone crossings (streaks break when a need turns critical)
    local anyCritical = false
    for _, need in ipairs(AzeCaught.NEEDS) do
        local zone = AzeCaught.ZoneOf(companion, need)
        if zone == "critical" or zone == "empty" then anyCritical = true end
        if zone ~= companion.zones[need] then
            AzeCaught.Journal("INFORMATION", "need.zone", "a need changed zone",
                { need = need, from = companion.zones[need], to = zone, value = round1(companion[need]), npc = companion.npc })
            if (zone == "critical" or zone == "empty") and companion.zones[need] ~= "empty" and companion.zones[need] ~= "critical" then
                if need == "hunger" and companion.fedStreak > 0 then
                    AzeCaught.Journal("INFORMATION", "streak.broken", "the fed streak was broken", { streak = companion.fedStreak })
                    companion.fedStreak = 0
                end
                if companion.careStreak > 0 then
                    AzeCaught.Journal("INFORMATION", "streak.broken", "the care streak was broken",
                        { streak = companion.careStreak, need = need })
                    companion.careStreak = 0
                end
            end
            companion.zones[need] = zone
            result.changed = true
        end
    end

    -- neglect: -1 heart per NEGLECT_STEP with any need critical
    if anyCritical then
        companion.neglect = companion.neglect + dt
        while companion.neglect >= AzeCaught.NEGLECT_STEP do
            companion.neglect = companion.neglect - AzeCaught.NEGLECT_STEP
            changeHearts(companion, -1, "neglect")
        end
    end

    -- starving / dying of thirst
    if companion.hunger <= 0 or companion.thirst <= 0 then
        if companion.starve == 0 then
            AzeCaught.Journal("WARNING", "companion.starving", "the companion started starving",
                { hunger = round1(companion.hunger), thirst = round1(companion.thirst), dieIn = AzeCaught.STARVE_TIME })
        end
        companion.starve = companion.starve + dt
        if companion.starve >= AzeCaught.STARVE_TIME then
            die(companion, companion.hunger <= 0 and "hunger" or "thirst")
            result.died, result.changed = true, true
            return result
        end
    elseif companion.starve > 0 then
        AzeCaught.Journal("INFORMATION", "companion.starving", "the companion stopped starving", { after = round1(companion.starve) })
        companion.starve = 0
    end

    -- periodic snapshot (the decay can be reconstructed from these lines)
    companion.snap = companion.snap + dt
    if companion.snap >= AzeCaught.SNAPSHOT_EVERY then
        companion.snap = 0
        AzeCaught.Journal("DEBUG", "snapshot", "companion state", AzeCaught.Describe(companion))
    end
    if companion.hearts ~= heartsBefore then result.changed = true end
    if now then AzeCaught.NotePeak(companion, now) end
    return result
end

---@alias CareAction "feed"|"water"|"pet"|"sleep"|"wake"
---@alias CareRefusal "none"|"asleep"|"awake"|"full"|"funds"|"readonly"|"action"

AzeCaught.CARE = {
    feed = { need = "hunger", price = "FOOD_PRICE", ledger = "food" },
    water = { need = "thirst", price = "WATER_PRICE", ledger = "water" },
    pet = { need = "affection" },
    sleep = { need = "energy" },
    wake = {},
}

---@class CareResult
---@field action CareAction
---@field hearts integer change
---@field cost integer copper spent
---@field balance? integer after a paid action

-- One care action (R11, R12). Returns the result, or nil and the refusal.
---@param action any
---@param myName string|nil
---@param now integer server time
---@return CareResult|nil
---@return CareRefusal|nil
-- Whether a care action can be done now, without doing it (the panel greys out the buttons with it, user 2026-11-20).
-- Returns true, or false and the refusal Care would give.
---@param action any
---@param myName string|nil
---@return boolean usable
---@return CareRefusal|nil
function AzeCaught.CareAvailability(action, myName)
    local companion = AzeCaught.Active()
    local care = AzeCaught.CARE[action]
    if not care then return false, "action" end
    if not companion then return false, "none" end
    if addon.Store.db.readonly then return false, "readonly" end
    if action == "wake" then return companion.asleep ~= nil, not companion.asleep and "awake" or nil end
    if companion.asleep then return false, "asleep" end
    local need = care.need
    if not AzeCaught.ProfileOf(companion).intervals[need] then return false, "full" end   -- never needed (e.g. undead and water)
    if companion[need] >= AzeCaught.FULL_LEVEL then return false, "full" end
    if care.price and AzeCaught[care.price] > addon.Wallet.Balance(myName) then return false, "funds" end
    return true, nil
end

function AzeCaught.Care(action, myName, now)
    local companion = AzeCaught.Active()
    local function refuse(reason)
        AzeCaught.Journal("DEBUG", "care.refused", "a care action was refused",
            { action = tostring(action), reason = reason, npc = companion and companion.npc or nil })
        return nil, reason
    end
    local usable, unusable = AzeCaught.CareAvailability(action, myName)
    if not usable then return refuse(unusable) end
    local care = AzeCaught.CARE[action]
    if action == "wake" then
        AzeCaught.Journal("INFORMATION", "care.wake", "the companion was woken up",
            { npc = companion.npc, sleptLeft = round1(companion.asleep), energy = round1(companion.energy) })
        companion.asleep = nil
        return { action = action, hearts = 0, cost = 0 }
    end
    local need = care.need
    local before = companion[need]
    local profile = AzeCaught.ProfileOf(companion)
    local cost, balance = 0, nil
    if care.price then
        cost = AzeCaught[care.price]
        local refusal
        balance, refusal = addon.Wallet.Spend(myName, cost, care.ledger, now, companion.n)
        if not balance then return refuse(refusal) end
    end
    -- hearts: needy +1, ok but due soon +2, critical/empty or well fed 0
    local zone = AzeCaught.Zone(before, profile.ok, profile.critical)
    local hearts = 0
    if zone == "needy" then hearts = 1
    elseif zone == "ok" and before <= profile.ok + (AzeCaught.DUE_LEVEL - AzeCaught.OK_LEVEL) then hearts = 2 end
    if action == "sleep" then
        companion.asleep = AzeCaught.SLEEP_DURATION
    else
        companion[need] = 100
    end
    local streakCounted = false
    if zone ~= "critical" and zone ~= "empty" then
        -- the care streak: at most one action per CARE_STREAK_GAP of play time (user 2026-11-20)
        local activeSeconds = AzeCaught.State().activeSeconds
        if companion.streakAt == nil or activeSeconds - companion.streakAt >= AzeCaught.CARE_STREAK_GAP then
            companion.careStreak = companion.careStreak + 1
            companion.streakAt = activeSeconds
            streakCounted = true
        end
        if action == "feed" then companion.fedStreak = companion.fedStreak + 1 end
    end
    AzeCaught.Journal("INFORMATION", "care." .. action, "a care action was done",
        { npc = companion.npc, need = need, before = round1(before), after = round1(companion[need]), zone = zone,
          hearts = hearts, cost = cost, balance = balance, fedStreak = companion.fedStreak, careStreak = companion.careStreak,
          streakCounted = streakCounted,
          streakIn = not streakCounted and companion.streakAt
              and round1(AzeCaught.CARE_STREAK_GAP - (AzeCaught.State().activeSeconds - companion.streakAt)) or nil })
    changeHearts(companion, hearts, action)
    companion.zones[need] = AzeCaught.ZoneOf(companion, need)
    return { action = action, hearts = hearts, cost = cost, balance = balance }
end

------------------------------------------------------------------ guild record section (R16) and sanitizing

-- The `caught` section of my game record: my current companion (or none) and my weekly peaks.
---@return table section
function AzeCaught.BuildSection()
    local caught = AzeCaught.State()
    local section = { weeks = {} }
    for periodKey, peak in pairs(caught.peaks) do section.weeks[periodKey] = math.floor(peak) end
    local companion = caught.active
    if companion then
        section.c = { npc = companion.npc, n = companion.n, lvl = companion.lvl, cls = companion.cls, disp = companion.disp,
            h = companion.hearts, hu = math.floor(companion.hunger + 0.5), th = math.floor(companion.thirst + 0.5),
            af = math.floor(companion.affection + 0.5), en = math.floor(companion.energy + 0.5), sl = companion.asleep and true or nil,
            fs = companion.fedStreak }
    end
    return section
end

-- A clean copy of a peer's (or my stored) `caught` section, or nil (the record keeps everything else).
---@param section any
---@param horizon number
---@return table|nil
function AzeCaught.SanitizeSection(section, horizon)
    local Utility = addon.Utility
    local SafeInteger = Utility.SafeInteger
    if type(section) ~= "table" or type(section.weeks) ~= "table" then return nil end
    local clean = { weeks = {} }
    local latestKey = horizon ~= math.huge and addon.Games.PeriodKey(horizon) or nil
    local weekCount = 0
    for periodKey, peak in pairs(section.weeks) do
        weekCount = weekCount + 1
        if weekCount > AzeCaught.MAXIMUM_WEEKS or not addon.Games.IsPeriodKey(periodKey) then return nil end
        if latestKey and periodKey > latestKey then return nil end
        if not SafeInteger(peak, -AzeCaught.MAXIMUM_HEARTS, AzeCaught.MAXIMUM_HEARTS + AzeCaught.MAXIMUM_LEVEL + 25) then return nil end
        clean.weeks[periodKey] = peak
    end
    local companion = section.c
    if companion ~= nil then
        if type(companion) ~= "table" then return nil end
        local name = Utility.CleanString(companion.n, AzeCaught.MAXIMUM_NAME_BYTES)
        local values = { npc = SafeInteger(companion.npc, 1, AzeCaught.MAXIMUM_ID), lvl = SafeInteger(companion.lvl, 1, AzeCaught.MAXIMUM_LEVEL),
            disp = SafeInteger(companion.disp, 0, AzeCaught.MAXIMUM_ID), h = SafeInteger(companion.h, -AzeCaught.MAXIMUM_HEARTS, AzeCaught.MAXIMUM_HEARTS),
            hu = SafeInteger(companion.hu, 0, 100), th = SafeInteger(companion.th, 0, 100), af = SafeInteger(companion.af, 0, 100),
            en = SafeInteger(companion.en, 0, 100), fs = SafeInteger(companion.fs or 0, 0, AzeCaught.MAXIMUM_HEARTS) }
        for _, field in ipairs({ "npc", "lvl", "disp", "h", "hu", "th", "af", "en", "fs" }) do
            if values[field] == nil then return nil end   -- (pairs would skip the nil a failed check leaves)
        end
        if not name or not AzeCaught.RARITY_FACTOR[companion.cls] then return nil end
        if companion.sl ~= nil and companion.sl ~= true then return nil end
        values.n, values.cls, values.sl = name, companion.cls, companion.sl
        clean.c = values
    end
    return clean
end

-- Writes my current companion into my game record (a new rev) so the guild sees it. Returns true when stored.
---@param myName string|nil
---@param now integer
---@return boolean
function AzeCaught.Publish(myName, now)
    if not addon.Utility.IsSafeName(myName) or addon.Store.db.readonly then return false end
    local stored = addon.Games.SetSection(myName, "caught", AzeCaught.BuildSection(), now)
    AzeCaught.Journal("DEBUG", "publish", "the companion was written into my game record", { stored = stored })
    return stored
end

------------------------------------------------------------------ weekly payout (R17)

-- The ranking of `periodKey`: { name, peak } sorted by peak (desc), then name. My own entry comes from db.caught.peaks.
---@param records table<string, GameRecord>
---@param periodKey string
---@param myName string|nil
---@return { name: string, peak: integer }[]
function AzeCaught.WeekRanking(records, periodKey, myName)
    local ranking = {}
    for playerName, gameRecord in pairs(records or {}) do
        if playerName ~= myName then
            local section = type(gameRecord) == "table" and gameRecord.caught
            local peak = type(section) == "table" and type(section.weeks) == "table" and section.weeks[periodKey]
            if type(peak) == "number" then ranking[#ranking + 1] = { name = playerName, peak = peak } end
        end
    end
    local myPeak = myName and AzeCaught.State().peaks[periodKey]
    if type(myPeak) == "number" then ranking[#ranking + 1] = { name = myName, peak = myPeak } end
    table.sort(ranking, function(left, right)
        if left.peak ~= right.peak then return left.peak > right.peak end
        return left.name < right.name
    end)
    return ranking
end

-- Pays last week's place once (R17, RF5). Returns the amount paid (0 when nothing), and why nothing: "paid", "nopeak",
-- "readonly".
---@param myName string|nil
---@param records table<string, GameRecord>
---@param now integer
---@return integer amount
---@return string|nil reason
---@return integer|nil rank
function AzeCaught.WeeklyPayout(myName, records, now)
    local caught = AzeCaught.State()
    local previousKey = addon.Games.PreviousPeriodKey(now)
    if caught.paidWeek == previousKey then return 0, "paid" end
    if addon.Store.db.readonly then return 0, "readonly" end
    caught.paidWeek = previousKey
    local ranking = AzeCaught.WeekRanking(records, previousKey, myName)
    local listing = {}
    for index, row in ipairs(ranking) do
        if index <= 10 then listing[#listing + 1] = index .. "." .. row.name .. "=" .. row.peak end
    end
    local rank
    for index, row in ipairs(ranking) do if row.name == myName then rank = index break end end
    if not rank then
        AzeCaught.Journal("INFORMATION", "payout", "no weekly payout: no companion last week",
            { week = previousKey, players = #ranking, ranking = table.concat(listing, " ") })
        return 0, "nopeak"
    end
    local amount = AzeCaught.PAYOUTS[rank] or AzeCaught.PAYOUT_OTHER
    AzeCaught.Journal("INFORMATION", "payout", "the weekly payout was earned",
        { week = previousKey, rank = rank, peak = ranking[rank].peak, amount = amount, players = #ranking,
          ranking = table.concat(listing, " ") })
    addon.Wallet.Earn(myName, amount, "payout", now, previousKey .. " #" .. rank)
    return amount, nil, rank
end

------------------------------------------------------------------ persisted state (untrusted on load)

---@param companion any
---@param collection table
---@return CompanionState|nil
local function sanitizeCompanion(companion, collection)
    local SafeInteger = addon.Utility.SafeInteger
    if type(companion) ~= "table" then return nil end
    local npcId = SafeInteger(companion.npc, 1, AzeCaught.MAXIMUM_ID)
    local entry = npcId and collection[npcId]
    if not entry then return nil end
    local clean = { npc = npcId, n = entry.n, lvl = entry.lvl, cls = entry.cls, disp = entry.disp,
        hearts = SafeInteger(companion.hearts, -AzeCaught.MAXIMUM_HEARTS, AzeCaught.MAXIMUM_HEARTS),
        fedStreak = SafeInteger(companion.fedStreak, 0, AzeCaught.MAXIMUM_HEARTS),
        careStreak = SafeInteger(companion.careStreak, 0, AzeCaught.MAXIMUM_HEARTS), zones = {} }
    if not (clean.hearts and clean.fedStreak and clean.careStreak) then return nil end
    for _, need in ipairs(AzeCaught.NEEDS) do
        local value = companion[need]
        if not addon.Utility.IsFinite(value) then return nil end
        clean[need] = clamp(value, 0, 100)
        clean.zones[need] = AzeCaught.ZoneOf(clean, need)
    end
    for _, field in ipairs({ "since", "starve", "neglect", "snap" }) do
        local value = companion[field]
        clean[field] = addon.Utility.IsFinite(value) and value >= 0 and value or 0
    end
    if addon.Utility.IsFinite(companion.streakAt) and companion.streakAt >= 0 then clean.streakAt = companion.streakAt end
    if companion.asleep ~= nil then
        clean.asleep = addon.Utility.IsFinite(companion.asleep) and clamp(companion.asleep, 0, AzeCaught.SLEEP_DURATION) or nil
    end
    return clean
end

-- Re-validates db.caught on load. Logs what was dropped. Returns the number of dropped items.
---@param savedVariables table
---@return integer dropped
function AzeCaught.SanitizePersisted(savedVariables)
    local caught = savedVariables.caught
    if type(caught) ~= "table" then savedVariables.caught = {} return 0 end
    local Utility = addon.Utility
    local SafeInteger = Utility.SafeInteger
    local dropped = 0
    local collection = {}
    for npcId, entry in pairs(type(caught.collection) == "table" and caught.collection or {}) do
        local id = SafeInteger(npcId, 1, AzeCaught.MAXIMUM_ID)
        if id and type(entry) == "table" and Utility.CleanString(entry.n, AzeCaught.MAXIMUM_NAME_BYTES)
            and SafeInteger(entry.lvl, 1, AzeCaught.MAXIMUM_LEVEL) and AzeCaught.RARITY_FACTOR[entry.cls]
            and SafeInteger(entry.disp, 0, AzeCaught.MAXIMUM_ID) and SafeInteger(entry.seen, 0)
            and SafeInteger(entry.caught, 0, AzeCaught.MAXIMUM_ID) and Utility.Count(collection) < AzeCaught.MAXIMUM_COLLECTION then
            collection[id] = { n = entry.n, lvl = entry.lvl, cls = entry.cls, disp = entry.disp, seen = entry.seen, caught = entry.caught,
                st = AzeCaught.CleanStats(entry.st) }
        else
            dropped = dropped + 1
        end
    end
    caught.collection = collection
    if caught.active ~= nil then
        local companion = sanitizeCompanion(caught.active, collection)
        if not companion or (collection[companion.npc].caught or 0) < 1 then
            dropped = dropped + 1
            companion = nil
        end
        caught.active = companion
    end
    local peaks = {}
    for periodKey, peak in pairs(type(caught.peaks) == "table" and caught.peaks or {}) do
        if addon.Games.IsPeriodKey(periodKey) and SafeInteger(peak, -AzeCaught.MAXIMUM_HEARTS, AzeCaught.MAXIMUM_HEARTS * 2) then
            peaks[periodKey] = peak
        else
            dropped = dropped + 1
        end
    end
    caught.peaks = peaks
    if not (Utility.IsFinite(caught.activeSeconds) and caught.activeSeconds >= 0) then caught.activeSeconds = 0 end
    if caught.paidWeek ~= nil and not addon.Games.IsPeriodKey(caught.paidWeek) then caught.paidWeek = nil end
    if type(caught.journal) ~= "table" then caught.journal = {} end
    for index = #caught.journal, 1, -1 do
        if type(caught.journal[index]) ~= "string" then table.remove(caught.journal, index) end
    end
    while #caught.journal > AzeCaught.JOURNAL_ENTRIES do table.remove(caught.journal, 1) end
    caught.notify = caught.notify ~= false
    caught.firstCatchDone = caught.firstCatchDone == true or nil
    if caught.icon ~= nil then caught.icon = AzeCaught.CleanIconSettings(caught.icon) end
    caught.verbose = caught.verbose == true or nil
    if addon.Wallet.SanitizePersisted(caught) then dropped = dropped + 1 end
    return dropped
end

------------------------------------------------------------------ rope icon settings (user 2026-11-20)

AzeCaught.ICON_DEFAULTS = { shown = true, x = 0, y = 2, size = 26 }
-- lowest, highest per numeric setting (pixels: offset from the top centre of the nameplate, icon size)
AzeCaught.ICON_LIMITS = { x = { -80, 80 }, y = { -40, 80 }, size = { 16, 48 } }

---@param raw any
---@return { shown: boolean, x: number, y: number, size: number }
local function cleanIconSettings(raw)
    raw = type(raw) == "table" and raw or {}
    local clean = { shown = raw.shown ~= false }
    if raw.shown ~= nil and type(raw.shown) ~= "boolean" then clean.shown = true end
    for key, limits in pairs(AzeCaught.ICON_LIMITS) do
        local value = raw[key]
        clean[key] = addon.Utility.IsFinite(value) and clamp(math.floor(value + 0.5), limits[1], limits[2]) or AzeCaught.ICON_DEFAULTS[key]
    end
    return clean
end
AzeCaught.CleanIconSettings = cleanIconSettings

-- The rope icon settings (db.caught.icon), complete and in range.
---@return { shown: boolean, x: number, y: number, size: number }
function AzeCaught.IconSettings()
    local caught = AzeCaught.State()
    caught.icon = cleanIconSettings(caught.icon)
    return caught.icon
end

-- Changes one icon setting ("shown", "x", "y", "size"); numbers are clamped. Returns false for an unknown key.
---@param key string
---@param value any
---@return boolean
function AzeCaught.SetIconSetting(key, value)
    if key ~= "shown" and not AzeCaught.ICON_LIMITS[key] then return false end
    local settings = AzeCaught.IconSettings()
    local before = settings[key]
    if key == "shown" then settings.shown = value and true or false
    else
        local limits = AzeCaught.ICON_LIMITS[key]
        settings[key] = clamp(math.floor((tonumber(value) or AzeCaught.ICON_DEFAULTS[key]) + 0.5), limits[1], limits[2])
    end
    AzeCaught.Journal("INFORMATION", "icon.setting", "an icon setting changed", { key = key, before = tostring(before), after = tostring(settings[key]) })
    return true
end

function AzeCaught.ResetIconSettings()
    AzeCaught.State().icon = cleanIconSettings(nil)
    AzeCaught.Journal("INFORMATION", "icon.setting", "the icon settings were reset")
end

------------------------------------------------------------------ reset (dev build, user 2026-11-20)

-- Starts AZEcaught over: collection, companion, active time, weekly peaks/payout and the guaranteed first catch are
-- cleared, and so are the runtime throw tables. Kept: settings (icon, notify, verbose) and the journal (the reset line
-- marks the cut). `withWallet` also clears the ledger; casino results live in the guild's game records and stay.
---@param withWallet boolean|nil
---@return { found: integer, caught: integer, companion: boolean, wallet: boolean }
function AzeCaught.Reset(withWallet)
    local caught = AzeCaught.State()
    local summary = { found = addon.Utility.Count(caught.collection), caught = AzeCaught.CaughtCount(),
        companion = caught.active ~= nil, wallet = withWallet == true }
    caught.collection, caught.active, caught.activeSeconds, caught.peaks = {}, nil, 0, {}
    caught.paidWeek, caught.firstCatchDone = nil, nil
    if withWallet then caught.ledger = nil end
    AzeCaught.throws, AzeCaught.rolled, AzeCaught.thrown = {}, {}, {}
    AzeCaught.lastThrowAt, AzeCaught.forceNextCatch = nil, false
    AzeCaught.Journal("INFORMATION", "dev.reset", "AZEcaught was reset", summary)
    return summary
end

------------------------------------------------------------------ export (manual debugging, R20)

-- The whole local state as one line: "AZE1 key=value ..." (paste into a bug report; tests replay it).
---@param myName string|nil
---@return string
function AzeCaught.Export(myName)
    local caught = AzeCaught.State()
    local breakdown = addon.Wallet.Breakdown(myName)
    local parts = { "AZE1", "v=" .. tostring(addon.VERSION), "active=" .. round1(caught.activeSeconds),
        "found=" .. addon.Utility.Count(caught.collection), "balance=" .. breakdown.balance, "casino=" .. breakdown.casino,
        "earned=" .. breakdown.earned, "spent=" .. breakdown.spent, "pending=" .. breakdown.pending,
        "paidWeek=" .. tostring(caught.paidWeek) }
    local caughtCount = 0
    for _, entry in pairs(caught.collection) do if entry.caught > 0 then caughtCount = caughtCount + 1 end end
    parts[#parts + 1] = "caught=" .. caughtCount
    for _, periodKey in ipairs(addon.Utility.SortedKeys(caught.peaks)) do parts[#parts + 1] = "peak" .. periodKey .. "=" .. caught.peaks[periodKey] end
    local companion = caught.active
    if companion then
        local description = AzeCaught.Describe(companion)
        for _, key in ipairs(addon.Utility.SortedKeys(description)) do
            parts[#parts + 1] = "c." .. key .. "=" .. tostring(description[key])
        end
    else
        parts[#parts + 1] = "c=none"
    end
    return table.concat(parts, " ")
end
