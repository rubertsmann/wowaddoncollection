local addonName, addon = ...

-- Guild games (feature 014), first game: the coin flip. Pure Lua: the WoW side is UI/GamesTab.lua, the UI side Model.
--
-- One record per character (GameRecord), authored ONLY by that character and replaced as a whole by the newer `rev`
-- (the Offers pattern). Results are self-reported: peers check shape, bounds and internal consistency, not truth.
-- Gold is bookkeeping only: nothing here (or anywhere in the addon) reads or moves real gold.
-- Every amount is in COPPER (1g = 100s = 10000c), so stakes can be small ("2s 50c").
-- The field names are the wire and saved-data format and stay as they are (GuildGames protocol 1, same shape as in
-- TalentShare 0.6.0 protocol 2.3).

---@class GameTotals
---@field won integer copper won in the scope (sum of winning stakes)
---@field lost integer copper lost in the scope
---@field wins integer number of won flips
---@field losses integer number of lost flips

---@class GameFlip
---@field c integer stake in copper, 1..MAXIMUM_STAKE
---@field r? "W"|"L" coin flip entries
---@field n? integer signed net copper (entries of the other games: -c, or c..factor*c)
---@field t integer server time of the play

---@class GameSection one game's results (the coin flip's section is the record itself)
---@field total GameTotals
---@field weeks table<string, GameTotals>
---@field recent GameFlip[]

---@class GameRecord
---@field name string owner, canonical "Name-Realm"
---@field rev integer newer wins (commit rule as Offers: max(now, previous + 1))
---@field total GameTotals all time
---@field weeks table<string, GameTotals> "YYYY-Www" -> totals; at most MAXIMUM_WEEKS newest keys
---@field recent GameFlip[] newest first, at most MAXIMUM_RECENT
---@field slots? GameSection slot machine results (feature 014)
---@field survivor? GameSection survivor results (feature 016)
---@field caught? table AZEcaught: { c = current companion | nil, weeks = { [periodKey] = peak level } } (feature 018,
---  protocol 1.1; 1.0 peers drop it). Not a GameSection: not in Games.ORDER, sanitized by AzeCaught.SanitizeSection.

---@class FlipResult
---@field outcome "H"|"T"
---@field won boolean
---@field stake integer copper
---@field net integer +stake or -stake (copper)

---@alias FlipRefusal "stake"|"pick"|"readonly"|"name"|"funds"

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

------------------------------------------------------------------ games and their sections of the record
-- One record holds every game: the coin flip's section is the record itself (total, weeks, recent: the 0.6 draft shape),
-- every later game has its own optional sub-table with the same shape (record.slots). Each section feeds its own
-- leaderboard. A play is binary for the leaderboard: a loss costs exactly the stake, a win nets 1..maximumWinFactor x stake.

---@alias GameKey "coin"|"slots"|"survivor"

---@class GameKind
---@field maximumWinFactor integer the most a win can net, in stakes

-- Highest total multiplier of one slot spin (every payline paying the top symbol): Slots.MAXIMUM_MULTIPLIER must equal it
-- (tests/test_slots.lua pins both).
Games.SLOTS_MAXIMUM_MULTIPLIER = 375
-- Highest payout factor of a survivor run (endless mode's cap): Survivor.ENDLESS_MAXIMUM_FACTOR must equal it.
Games.SURVIVOR_MAXIMUM_FACTOR = 64

---@type table<GameKey, GameKind>
Games.KINDS = {
    coin = { maximumWinFactor = 1 },
    slots = { maximumWinFactor = Games.SLOTS_MAXIMUM_MULTIPLIER - 1 },
    survivor = { maximumWinFactor = Games.SURVIVOR_MAXIMUM_FACTOR - 1 },
}
---@type GameKey[] display order of the games
Games.ORDER = { "coin", "slots", "survivor" }

-- The section of `gameRecord` that holds `gameKey`'s results (nil when that game was never played).
---@param gameRecord GameRecord|nil
---@param gameKey GameKey|nil default "coin"
---@return GameSection|nil
function Games.Section(gameRecord, gameKey)
    if type(gameRecord) ~= "table" then return nil end
    if gameKey == nil or gameKey == "coin" then return gameRecord end
    return gameRecord[gameKey]
end

-- net copper of one recent entry: coin entries carry r = "W"|"L", other games the signed net n
---@param entry GameFlip
---@return integer
function Games.EntryNet(entry)
    if entry.n ~= nil then return entry.n end
    return entry.r == "W" and entry.c or -entry.c
end

------------------------------------------------------------------ validation (network and persisted data)

---@param totals any
---@param maximumWinFactor integer
---@return GameTotals|nil
local function sanitizeTotals(totals, maximumWinFactor)
    local SafeInteger = addon.Utility.SafeInteger
    if type(totals) ~= "table" then return nil end
    local won, lost = SafeInteger(totals.won, 0, Games.MAXIMUM_TOTAL), SafeInteger(totals.lost, 0, Games.MAXIMUM_TOTAL)
    local wins, losses = SafeInteger(totals.wins, 0, Games.MAXIMUM_COUNT), SafeInteger(totals.losses, 0, Games.MAXIMUM_COUNT)
    if not (won and lost and wins and losses) then return nil end
    -- every win nets 1..factor x MAXIMUM_STAKE, every loss 1..MAXIMUM_STAKE (clamping at the maxima keeps this true)
    if won < wins or won > wins * Games.MAXIMUM_STAKE * maximumWinFactor then return nil end
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

-- A clean copy of one recent entry, or nil. Coin: { c, r, t }; other games: { c, n, t } with n = -c or c..factor*c.
---@param entry any
---@param gameKey GameKey
---@param horizon number
---@return GameFlip|nil
local function sanitizeEntry(entry, gameKey, horizon)
    local SafeInteger = addon.Utility.SafeInteger
    if type(entry) ~= "table" or not SafeInteger(entry.c, 1, Games.MAXIMUM_STAKE) or not SafeInteger(entry.t, 0, horizon) then
        return nil
    end
    if gameKey == "coin" then
        if entry.r ~= "W" and entry.r ~= "L" then return nil end
        return { c = entry.c, r = entry.r, t = entry.t }
    end
    local net = SafeInteger(entry.n, -entry.c, entry.c * Games.KINDS[gameKey].maximumWinFactor)
    if not net or (net < 0 and net ~= -entry.c) or (net >= 0 and net < entry.c) then return nil end
    return { c = entry.c, n = net, t = entry.t }
end

-- A clean copy of one game section { total, weeks, recent }, or nil when any part is bad.
---@param section any
---@param gameKey GameKey
---@param horizon number
---@return GameSection|nil
local function sanitizeSection(section, gameKey, horizon)
    local Utility = addon.Utility
    if type(section) ~= "table" then return nil end
    local factor = Games.KINDS[gameKey].maximumWinFactor
    local total = sanitizeTotals(section.total, factor)
    if not total or type(section.weeks) ~= "table" or type(section.recent) ~= "table" then return nil end
    local latestKey = horizon ~= math.huge and Games.PeriodKey(horizon) or nil
    local weeks, weekCount = {}, 0
    for periodKey, totals in pairs(section.weeks) do
        weekCount = weekCount + 1
        if weekCount > Games.MAXIMUM_WEEKS or not Games.IsPeriodKey(periodKey) then return nil end
        if latestKey and periodKey > latestKey then return nil end   -- "YYYY-Www" compares correctly as text
        local cleanTotals = sanitizeTotals(totals, factor)
        if not cleanTotals then return nil end
        weeks[periodKey] = cleanTotals
    end
    local recentCount = Utility.Count(section.recent)
    if recentCount > Games.MAXIMUM_RECENT then return nil end
    local recent = {}
    for index = 1, recentCount do
        local clean = sanitizeEntry(section.recent[index], gameKey, horizon)   -- a sparse array leaves a hole: nil
        if not clean then return nil end
        recent[index] = clean
    end
    return { total = total, weeks = weeks, recent = recent }
end

-- Returns a CLEAN COPY of a game record or nil. A single bad entry rejects the whole record. Unknown fields (a game a
-- newer 2.x minor added) are dropped, not fatal.
---@param gameRecord any
---@return GameRecord|nil
function Games.Sanitize(gameRecord)
    local Utility = addon.Utility
    if type(gameRecord) ~= "table" or not Utility.IsSafeName(gameRecord.name) then return nil end
    local horizon = addon.Store.Horizon()
    local revision = Utility.SafeInteger(gameRecord.rev, 0, horizon)
    if not revision then return nil end
    local coin = sanitizeSection(gameRecord, "coin", horizon)
    if not coin then return nil end
    local clean = { name = gameRecord.name, rev = revision, total = coin.total, weeks = coin.weeks, recent = coin.recent }
    for _, gameKey in ipairs(Games.ORDER) do
        if gameKey ~= "coin" and gameRecord[gameKey] ~= nil then
            local section = sanitizeSection(gameRecord[gameKey], gameKey, horizon)
            if not section then return nil end
            clean[gameKey] = section
        end
    end
    -- AZEcaught (feature 018): a bad companion section is dropped alone; the casino results stay
    if gameRecord.caught ~= nil and addon.AzeCaught then
        local section = addon.AzeCaught.SanitizeSection(gameRecord.caught, horizon)
        if section then
            clean.caught = section
        else
            addon.AzeCaught.Journal("WARNING", "sanitize", "a companion section was invalid and dropped", { owner = gameRecord.name })
        end
    end
    return clean
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

------------------------------------------------------------------ playing

---@return GameSection
local function emptySection() return { total = { won = 0, lost = 0, wins = 0, losses = 0 }, weeks = {}, recent = {} } end

---@param myName string
---@return GameRecord
local function emptyRecord(myName)
    local record = emptySection()
    record.name, record.rev = myName, 0
    return record
end

---@param totals GameTotals
---@param net integer signed copper
local function addToTotals(totals, net)
    if net > 0 then
        totals.won = math.min(Games.MAXIMUM_TOTAL, totals.won + net)
        totals.wins = math.min(Games.MAXIMUM_COUNT, totals.wins + 1)
    else
        totals.lost = math.min(Games.MAXIMUM_TOTAL, totals.lost - net)
        totals.losses = math.min(Games.MAXIMUM_COUNT, totals.losses + 1)
    end
end

-- Adds one play to `section` (in place): totals, this week's totals, recent list; prunes old weeks and entries.
---@param section GameSection
---@param entry GameFlip the recent entry ({c, r, t} or {c, n, t})
local function applyPlay(section, entry)
    local net = Games.EntryNet(entry)
    addToTotals(section.total, net)
    local periodKey = Games.PeriodKey(entry.t)
    section.weeks[periodKey] = section.weeks[periodKey] or { won = 0, lost = 0, wins = 0, losses = 0 }
    addToTotals(section.weeks[periodKey], net)
    local periodKeys = addon.Utility.SortedKeys(section.weeks)
    for index = 1, #periodKeys - Games.MAXIMUM_WEEKS do section.weeks[periodKeys[index]] = nil end
    table.insert(section.recent, 1, entry)
    for index = #section.recent, Games.MAXIMUM_RECENT + 1, -1 do section.recent[index] = nil end
end

-- Checks the common preconditions of a play. Returns nil when it may go ahead, else the refusal. `checkFunds`: the
-- stake must not be more than the money pool holds (feature 018 R18). Only where a play STARTS; a settle never checks.
---@param myName any
---@param stake any
---@param checkFunds? boolean
---@return FlipRefusal|nil
local function refusal(myName, stake, checkFunds)
    if not addon.Utility.SafeInteger(stake, 1, Games.MAXIMUM_STAKE) then return "stake" end
    if database().readonly then return "readonly" end
    if not addon.Utility.IsSafeName(myName) then return "name" end
    if checkFunds and addon.Wallet then return addon.Wallet.FundsRefusal(myName, stake) end
    return nil
end
Games.Refusal = refusal

-- Stores one play of `gameKey` in my record (a copy, committed with a new rev). The caller has checked `refusal`.
---@param myName string
---@param gameKey GameKey
---@param entry GameFlip
---@param now integer
local function record(myName, gameKey, entry, now)
    local previousRecord = database().games[myName]
    local gameRecord = previousRecord and addon.Utility.DeepCopy(previousRecord) or emptyRecord(myName)
    if gameKey ~= "coin" then gameRecord[gameKey] = gameRecord[gameKey] or emptySection() end
    applyPlay(Games.Section(gameRecord, gameKey), entry)
    gameRecord.rev = math.max(now, (previousRecord and previousRecord.rev or 0) + 1)
    database().games[myName] = gameRecord
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
    local refused = refusal(myName, stake, true)
    if refused then return nil, refused end
    local outcome = randomFunction() < 0.5 and "H" or "T"
    local won = outcome == pick
    record(myName, "coin", { c = stake, r = won and "W" or "L", t = now }, now)
    return { outcome = outcome, won = won, stake = stake, net = won and stake or -stake }
end

-- Stores a play of another game whose outcome the caller decided (Slots.Spin). net: -stake, or stake..factor*stake.
---@param myName string|nil
---@param gameKey GameKey
---@param stake any copper
---@param net integer
---@param now integer
---@return boolean stored
---@return FlipRefusal|nil
function Games.RecordPlay(myName, gameKey, stake, net, now)
    local refused = refusal(myName, stake)
    if refused then return false, refused end
    local entry = sanitizeEntry({ c = stake, n = net, t = now }, gameKey, math.huge)
    if gameKey == "coin" or not entry then error("invalid play for " .. tostring(gameKey) .. ": net " .. tostring(net)) end
    record(myName, gameKey, entry, now)
    return true
end

-- Replaces one non-play section of my record (AZEcaught's "caught") and commits a new rev. Returns true when stored.
---@param myName string
---@param key "caught"
---@param section table
---@param now integer
---@return boolean
function Games.SetSection(myName, key, section, now)
    if database().readonly or not addon.Utility.IsSafeName(myName) or key ~= "caught" then return false end
    local previousRecord = database().games[myName]
    local gameRecord = previousRecord and addon.Utility.DeepCopy(previousRecord) or emptyRecord(myName)
    gameRecord[key] = section
    gameRecord.rev = math.max(now, (previousRecord and previousRecord.rev or 0) + 1)
    database().games[myName] = gameRecord
    return true
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
    count = addon.Utility.Clamp(math.floor(tonumber(count) or 0), 0, 50)
    for index = 1, count do
        local playerName = "Sim" .. index .. "-Test"
        local gameRecord = emptyRecord(playerName)
        for _, gameKey in ipairs(Games.ORDER) do
            if gameKey ~= "coin" then gameRecord[gameKey] = emptySection() end
        end
        for _, gameKey in ipairs(Games.ORDER) do
            local section = Games.Section(gameRecord, gameKey)
            local playCount = 1 + math.floor(randomFunction() * 25)
            for playIndex = playCount, 1, -1 do
                local stake = 1 + math.floor(randomFunction() ^ 3 * 5000 * Games.COPPER_PER_GOLD)
                -- spread the plays over the last three weeks
                local playTime = now - math.floor(playIndex * 21 * SECONDS_PER_DAY / playCount * randomFunction())
                local entry
                if gameKey == "coin" then
                    entry = { c = stake, r = randomFunction() < 0.5 and "W" or "L", t = playTime }
                else
                    local roll = randomFunction()
                    local factor = math.min(Games.KINDS[gameKey].maximumWinFactor, 1 + math.floor(roll * 40))
                    entry = { c = stake, n = roll < 0.25 and stake * factor or -stake, t = playTime }
                end
                applyPlay(section, entry)
            end
            table.sort(section.recent, function(left, right) return left.t > right.t end)
        end
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
