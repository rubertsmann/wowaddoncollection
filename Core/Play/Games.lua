local addonName, addon = ...

-- Guild games (feature 014), first game: the coin flip. Pure Lua: the WoW side is UI/GamesTab.lua, the UI side Model.
--
-- One record per character (GameRecord), authored ONLY by that character and replaced as a whole by the newer `rev`
-- (the Offers pattern). Results are self-reported: peers check shape, bounds and internal consistency, not truth.
-- Gold is bookkeeping only: nothing here (or anywhere in the addon) reads or moves real gold.
-- Every amount is in COPPER (1g = 100s = 10000c), so stakes can be small ("2s 50c").
-- The field names are the wire and saved-data format and stay as they are (protocol major 2).

---@class GameTotals
---@field won integer copper won in the scope (sum of winning stakes)
---@field lost integer copper lost in the scope
---@field wins integer number of won flips
---@field losses integer number of lost flips

---@class GameFlip
---@field c integer stake in copper, 1..MAXIMUM_STAKE
---@field r "W"|"L"
---@field t integer server time of the flip

---@class GameRecord
---@field name string owner, canonical "Name-Realm"
---@field rev integer newer wins (commit rule as Offers: max(now, previous + 1))
---@field total GameTotals all time
---@field weeks table<string, GameTotals> "YYYY-Www" -> totals; at most MAXIMUM_WEEKS newest keys
---@field recent GameFlip[] newest first, at most MAXIMUM_RECENT

---@class FlipResult
---@field outcome "H"|"T"
---@field won boolean
---@field stake integer copper
---@field net integer +stake or -stake (copper)

---@alias FlipRefusal "stake"|"pick"|"readonly"|"name"

---@class GamesModule
---@field simulated table<string, GameRecord> fake records (dev command), never stored, never sent
local Games = {}
addon.Games = Games

Games.COPPER_PER_SILVER = 100
Games.COPPER_PER_GOLD = 10000
Games.MAXIMUM_STAKE = 100000 * Games.COPPER_PER_GOLD           -- 100 000 gold, in copper
Games.MAXIMUM_TOTAL = 2000000000 * Games.COPPER_PER_GOLD       -- 2e13 copper: exact in a double (< 2^53) and on the wire
Games.MAXIMUM_COUNT = 1000000
Games.MAXIMUM_WEEKS = 4
Games.MAXIMUM_RECENT = 20
Games.simulated = {}

local SECONDS_PER_DAY = 86400

---@return table
local function database() return addon.Store.db end

------------------------------------------------------------------ ISO week (UTC, integer arithmetic)

-- days since 1970-01-01 -> civil year (Howard Hinnant's civil_from_days; only the year is needed)
---@param days integer
---@return integer year
local function yearOfDays(days)
    local shifted = days + 719468
    local era = math.floor(shifted / 146097)
    local dayOfEra = shifted - era * 146097
    local yearOfEra = math.floor((dayOfEra - math.floor(dayOfEra / 1460) + math.floor(dayOfEra / 36524)
        - math.floor(dayOfEra / 146096)) / 365)
    local dayOfYear = dayOfEra - (365 * yearOfEra + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100))
    local monthIndex = math.floor((5 * dayOfYear + 2) / 153)   -- 0 = March
    local year = yearOfEra + era * 400
    if monthIndex >= 10 then year = year + 1 end              -- January, February belong to the next civil year
    return year
end

-- 1 January of `year` as days since 1970-01-01 (Hinnant's days_from_civil for month 1, day 1)
---@param year integer
---@return integer days
local function januaryFirst(year)
    local shiftedYear = year - 1                               -- January counts to the previous March-based year
    local era = math.floor(shiftedYear / 400)
    local yearOfEra = shiftedYear - era * 400
    local dayOfYear = math.floor((153 * 10 + 2) / 5)          -- month 1 -> index 10 (March-based), day 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
    return era * 146097 + dayOfEra - 719468
end

-- ISO 8601 week of a server time, in UTC: "YYYY-Www". No os.date (local time in tests, limited in the client).
---@param serverTime number
---@return string
function Games.PeriodKey(serverTime)
    local days = math.floor((tonumber(serverTime) or 0) / SECONDS_PER_DAY)
    local weekday = (days + 3) % 7          -- 0 = Monday (1970-01-01 was a Thursday)
    local thursday = days - weekday + 3      -- the ISO year is the year of this week's Thursday
    local isoYear = yearOfDays(thursday)
    local week = math.floor((thursday - januaryFirst(isoYear)) / 7) + 1
    return ("%04d-W%02d"):format(isoYear, week)
end

-- The ISO week before `periodKey`'s week, for a server time inside it.
---@param serverTime number
---@return string
function Games.PreviousPeriodKey(serverTime)
    return Games.PeriodKey((tonumber(serverTime) or 0) - 7 * SECONDS_PER_DAY)
end

------------------------------------------------------------------ validation (network and persisted data)

---@param totals any
---@return GameTotals|nil
local function sanitizeTotals(totals)
    local SafeInteger = addon.Utility.SafeInteger
    if type(totals) ~= "table" then return nil end
    local won, lost = SafeInteger(totals.won, 0, Games.MAXIMUM_TOTAL), SafeInteger(totals.lost, 0, Games.MAXIMUM_TOTAL)
    local wins, losses = SafeInteger(totals.wins, 0, Games.MAXIMUM_COUNT), SafeInteger(totals.losses, 0, Games.MAXIMUM_COUNT)
    if not (won and lost and wins and losses) then return nil end
    -- every win is worth 1..MAXIMUM_STAKE gold (clamping at the maxima keeps this true, see applyFlip)
    if won < wins or won > wins * Games.MAXIMUM_STAKE then return nil end
    if lost < losses or lost > losses * Games.MAXIMUM_STAKE then return nil end
    return { won = won, lost = lost, wins = wins, losses = losses }
end

---@param periodKey any
---@return boolean
function Games.IsPeriodKey(periodKey)
    if type(periodKey) ~= "string" then return false end
    local year, week = periodKey:match("^(%d%d%d%d)%-W(%d%d)$")
    year, week = tonumber(year), tonumber(week)
    return year ~= nil and year >= 2020 and year <= 2100 and week >= 1 and week <= 53
end

-- Returns a CLEAN COPY of a game record or nil. A single bad entry rejects the whole record.
---@param gameRecord any
---@return GameRecord|nil
function Games.Sanitize(gameRecord)
    local Utility = addon.Utility
    if type(gameRecord) ~= "table" or not Utility.IsSafeName(gameRecord.name) then return nil end
    local horizon = addon.Store.Horizon()
    local revision = Utility.SafeInteger(gameRecord.rev, 0, horizon)
    if not revision then return nil end
    local total = sanitizeTotals(gameRecord.total)
    if not total then return nil end
    if type(gameRecord.weeks) ~= "table" then return nil end
    local latestKey = horizon ~= math.huge and Games.PeriodKey(horizon) or nil
    local weeks, weekCount = {}, 0
    for periodKey, totals in pairs(gameRecord.weeks) do
        weekCount = weekCount + 1
        if weekCount > Games.MAXIMUM_WEEKS or not Games.IsPeriodKey(periodKey) then return nil end
        if latestKey and periodKey > latestKey then return nil end   -- "YYYY-Www" compares correctly as text
        local cleanTotals = sanitizeTotals(totals)
        if not cleanTotals then return nil end
        weeks[periodKey] = cleanTotals
    end
    if type(gameRecord.recent) ~= "table" then return nil end
    local recentCount = Utility.Count(gameRecord.recent)
    if recentCount > Games.MAXIMUM_RECENT then return nil end
    local recent = {}
    for index = 1, recentCount do
        local flip = gameRecord.recent[index]   -- a sparse array leaves a hole here
        if type(flip) ~= "table" or not Utility.SafeInteger(flip.c, 1, Games.MAXIMUM_STAKE)
            or (flip.r ~= "W" and flip.r ~= "L") or not Utility.SafeInteger(flip.t, 0, horizon) then
            return nil
        end
        recent[index] = { c = flip.c, r = flip.r, t = flip.t }
    end
    return { name = gameRecord.name, rev = revision, total = total, weeks = weeks, recent = recent }
end

------------------------------------------------------------------ money (gold / silver / copper)

-- Copper from the three stake boxes. Empty boxes count as 0; silver and copper must be 0..99. nil when anything is not a
-- whole number in range (the total range is checked by Games.Flip).
---@param gold any
---@param silver any
---@param copper any
---@return integer|nil copper
function Games.Money(gold, silver, copper)
    local SafeInteger = addon.Utility.SafeInteger
    gold, silver, copper = gold or 0, silver or 0, copper or 0
    if not (SafeInteger(gold, 0, 100000) and SafeInteger(silver, 0, 99) and SafeInteger(copper, 0, 99)) then return nil end
    return gold * Games.COPPER_PER_GOLD + silver * Games.COPPER_PER_SILVER + copper
end

-- copper -> gold, silver, copper (of a non-negative amount)
---@param copper integer
---@return integer gold
---@return integer silver
---@return integer copper
function Games.SplitMoney(copper)
    copper = math.max(0, math.floor(copper or 0))
    return math.floor(copper / Games.COPPER_PER_GOLD), math.floor(copper / Games.COPPER_PER_SILVER) % 100, copper % 100
end

------------------------------------------------------------------ store access

---@param playerName string
---@return GameRecord|nil
function Games.Get(playerName) return database().games[playerName] end

-- My record (nil when I never flipped).
---@param myName string|nil
---@return GameRecord|nil
function Games.Mine(myName) return myName and database().games[myName] or nil end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
---@param gameRecord GameRecord
---@return boolean
function Games.Put(gameRecord)
    if type(gameRecord) ~= "table" or type(gameRecord.name) ~= "string" then return false end
    local storedRecord = database().games[gameRecord.name]
    if storedRecord and (storedRecord.rev or 0) >= (gameRecord.rev or 0) then return false end
    database().games[gameRecord.name] = gameRecord
    return true
end

-- Re-validates persisted records (SavedVariables are untrusted on load). Returns the number dropped.
---@param savedVariables table
---@return integer droppedCount
function Games.SanitizePersisted(savedVariables)
    local gameRecords, droppedCount = addon.Utility.SanitizeMap(savedVariables.games, Games.Sanitize,
        function(playerName, clean) return clean.name == playerName end)
    savedVariables.games = gameRecords
    return droppedCount
end

------------------------------------------------------------------ flipping

---@param myName string
---@return GameRecord
local function emptyRecord(myName)
    return { name = myName, rev = 0, total = { won = 0, lost = 0, wins = 0, losses = 0 }, weeks = {}, recent = {} }
end

---@param totals GameTotals
---@param stake integer
---@param won boolean
local function addToTotals(totals, stake, won)
    if won then
        totals.won = math.min(Games.MAXIMUM_TOTAL, totals.won + stake)
        totals.wins = math.min(Games.MAXIMUM_COUNT, totals.wins + 1)
    else
        totals.lost = math.min(Games.MAXIMUM_TOTAL, totals.lost + stake)
        totals.losses = math.min(Games.MAXIMUM_COUNT, totals.losses + 1)
    end
end

-- Adds one flip to `gameRecord` (in place): totals, this week's totals, recent list; prunes old weeks and flips.
---@param gameRecord GameRecord
---@param stake integer
---@param won boolean
---@param now integer
local function applyFlip(gameRecord, stake, won, now)
    addToTotals(gameRecord.total, stake, won)
    local periodKey = Games.PeriodKey(now)
    gameRecord.weeks[periodKey] = gameRecord.weeks[periodKey] or { won = 0, lost = 0, wins = 0, losses = 0 }
    addToTotals(gameRecord.weeks[periodKey], stake, won)
    local periodKeys = addon.Utility.SortedKeys(gameRecord.weeks)
    for index = 1, #periodKeys - Games.MAXIMUM_WEEKS do gameRecord.weeks[periodKeys[index]] = nil end
    table.insert(gameRecord.recent, 1, { c = stake, r = won and "W" or "L", t = now })
    for index = #gameRecord.recent, Games.MAXIMUM_RECENT + 1, -1 do gameRecord.recent[index] = nil end
end

-- One coin flip against the house. The outcome is decided AND stored here, before any animation (a /reload cannot lose
-- or re-roll it). Returns the result, or nil and the refusal reason.
---@param myName string|nil
---@param stake any copper, 1..MAXIMUM_STAKE
---@param pick any "H" or "T"
---@param now integer server time
---@param randomFunction fun(): number in [0, 1)
---@return FlipResult|nil
---@return FlipRefusal|nil
function Games.Flip(myName, stake, pick, now, randomFunction)
    if not addon.Utility.SafeInteger(stake, 1, Games.MAXIMUM_STAKE) then return nil, "stake" end
    if pick ~= "H" and pick ~= "T" then return nil, "pick" end
    if database().readonly then return nil, "readonly" end
    if not addon.Utility.IsSafeName(myName) then return nil, "name" end
    local outcome = randomFunction() < 0.5 and "H" or "T"
    local won = outcome == pick
    local previousRecord = database().games[myName]
    local gameRecord = previousRecord and addon.Utility.DeepCopy(previousRecord) or emptyRecord(myName)
    applyFlip(gameRecord, stake, won, now)
    gameRecord.rev = math.max(now, (previousRecord and previousRecord.rev or 0) + 1)
    database().games[myName] = gameRecord
    return { outcome = outcome, won = won, stake = stake, net = won and stake or -stake }
end

------------------------------------------------------------------ simulated players (dev only)

-- Fills Games.simulated with `count` fake records "Sim<i>-Test" (0 clears). Never stored in the db, never sent:
-- Get/Mine/Put only see the db, so Sync can never answer with a simulated record.
---@param count integer
---@param now integer
---@param randomFunction fun(): number
---@return integer count of simulated records
function Games.Simulate(count, now, randomFunction)
    Games.simulated = {}
    count = math.max(0, math.min(50, math.floor(tonumber(count) or 0)))
    for index = 1, count do
        local playerName = "Sim" .. index .. "-Test"
        local gameRecord = emptyRecord(playerName)
        local flipCount = 1 + math.floor(randomFunction() * 25)
        for flipIndex = flipCount, 1, -1 do
            local stake = 1 + math.floor(randomFunction() ^ 3 * 5000 * Games.COPPER_PER_GOLD)
            -- spread the flips over the last three weeks, oldest first
            local flipTime = now - math.floor(flipIndex * 21 * SECONDS_PER_DAY / flipCount * randomFunction())
            applyFlip(gameRecord, stake, randomFunction() < 0.5, flipTime)
        end
        table.sort(gameRecord.recent, function(left, right) return left.t > right.t end)
        gameRecord.rev = now
        Games.simulated[playerName] = gameRecord
    end
    return count
end

-- Every record to show: the db's plus the simulated ones (simulated never shadow a real player).
---@return table<string, GameRecord>
function Games.AllRecords()
    local records = {}
    for playerName, gameRecord in pairs(Games.simulated) do records[playerName] = gameRecord end
    for playerName, gameRecord in pairs(database().games) do records[playerName] = gameRecord end
    return records
end
