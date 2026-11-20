local addonName, addon = ...

-- Rows for the window (pure Lua): money text, leaderboards, recent plays, last week's winner. Names come from peers and
-- are escaped here, before any FontString shows them.
---@class ModelModule
local Model = {}
addon.Model = Model

local escape = addon.Utility.Escape

---@type table<string, string> WoW's coin colours
local MONEY_COLOR = { g = "ffd700", s = "c7c7cf", c = "eda55f" }

-- "1g 50s 25c" with each part in its coin colour; zero parts are left out ("50s", "3c"); 0 -> "0c". Amounts in copper.
---@param copper integer
---@return string
function Model.MoneyText(copper)
    local gold, silver, rest = addon.Games.SplitMoney(math.abs(copper or 0))
    local Text, Format = addon.Text, addon.Locale.Format
    local parts = {}
    local function add(colorKey, text) parts[#parts + 1] = "|cff" .. MONEY_COLOR[colorKey] .. text .. "|r" end
    if gold > 0 then add("g", Format(Text["{n}g"], { n = gold })) end
    if silver > 0 then add("s", Format(Text["{n}s"], { n = silver })) end
    if rest > 0 or #parts == 0 then add("c", Format(Text["{n}c"], { n = rest })) end
    return table.concat(parts, " ")
end

---@class LeaderboardRow
---@field rank integer
---@field name string escaped display name
---@field nameRaw string the record key
---@field net integer won - lost
---@field won integer
---@field lost integer
---@field wins integer
---@field losses integer
---@field flips integer
---@field mine boolean

---@param left LeaderboardRow
---@param right LeaderboardRow
---@return boolean
local function leaderboardOrder(left, right)
    if left.net ~= right.net then return left.net > right.net end
    if left.flips ~= right.flips then return left.flips > right.flips end
    return left.nameRaw < right.nameRaw
end

-- Leaderboard of one game and scope: "week" (the totals under `periodKey`) or "all" (all-time totals). Every game has its
-- own board (gameKey, default "coin"). Sorted by net, then plays, then name; players without a play in the scope are left
-- out. Names come from peers and are escaped.
---@param records table<string, GameRecord>
---@param scope "week"|"all"
---@param periodKey string the week shown for scope "week"
---@param myName string|nil
---@param gameKey? GameKey
---@return LeaderboardRow[]
function Model.BuildLeaderboardRows(records, scope, periodKey, myName, gameKey)
    local rows = {}
    for playerName, gameRecord in pairs(records or {}) do
        local section = addon.Games.Section(gameRecord, gameKey)
        local totals = section and section.total
        if scope == "week" then totals = section and section.weeks and section.weeks[periodKey] end
        local flips = totals and (totals.wins + totals.losses) or 0
        if flips > 0 then
            rows[#rows + 1] = { name = escape(playerName), nameRaw = playerName, net = totals.won - totals.lost, won = totals.won,
                lost = totals.lost, wins = totals.wins, losses = totals.losses, flips = flips, mine = playerName == myName }
        end
    end
    table.sort(rows, leaderboardOrder)
    for index, row in ipairs(rows) do row.rank = index end
    return rows
end

---@class FlipFeedRow
---@field name string escaped
---@field nameRaw string
---@field net integer +stake or -stake
---@field t integer server time of the flip
---@field mine boolean

-- The newest plays of one game (default "coin") by every player, merged (newest first; same second: by name).
-- Default limit 15.
---@param records table<string, GameRecord>
---@param myName string|nil
---@param limit? integer
---@param gameKey? GameKey
---@return FlipFeedRow[]
function Model.BuildFlipFeedRows(records, myName, limit, gameKey)
    local rows = {}
    for playerName, gameRecord in pairs(records or {}) do
        local section = addon.Games.Section(gameRecord, gameKey)
        for _, entry in ipairs(section and section.recent or {}) do
            rows[#rows + 1] = { name = escape(playerName), nameRaw = playerName, net = addon.Games.EntryNet(entry),
                t = entry.t, mine = playerName == myName }
        end
    end
    table.sort(rows, function(left, right)
        if left.t ~= right.t then return left.t > right.t end
        if left.nameRaw ~= right.nameRaw then return left.nameRaw < right.nameRaw end
        return left.net > right.net
    end)
    for index = #rows, (limit or 15) + 1, -1 do rows[index] = nil end
    return rows
end

-- The winner of one game (default "coin") in the week `previousPeriodKey`: the top leaderboard row of that week when its
-- net is positive, else nil.
---@param records table<string, GameRecord>
---@param previousPeriodKey string
---@param gameKey? GameKey
---@return LeaderboardRow|nil
function Model.PreviousWinner(records, previousPeriodKey, gameKey)
    local top = Model.BuildLeaderboardRows(records, "week", previousPeriodKey, nil, gameKey)[1]
    if top and top.net > 0 then return top end
    return nil
end

------------------------------------------------------------------ AZEcaught (feature 018)

---@class CompanionRow
---@field rank integer
---@field name string escaped owner
---@field nameRaw string
---@field companion string escaped NPC name
---@field npc integer
---@field disp integer
---@field lvl integer
---@field cls string
---@field hearts integer
---@field level integer ranking value (NPC level + rarity bonus + hearts)
---@field hunger integer
---@field thirst integer
---@field affection integer
---@field energy integer
---@field asleep boolean
---@field fedStreak integer
---@field mine boolean

-- The guild's current companions as a leaderboard (R16): by companion level, then owner name. My own row is built from
-- my live state (fresher than my published record). Names come from peers and are escaped.
---@param records table<string, GameRecord>
---@param myName string|nil
---@return CompanionRow[]
function Model.BuildCompanionRows(records, myName)
    local AzeCaught = addon.AzeCaught
    local rows = {}
    local function add(ownerName, companion)
        rows[#rows + 1] = { name = escape(ownerName), nameRaw = ownerName, companion = escape(companion.n), npc = companion.npc,
            disp = companion.disp, lvl = companion.lvl, cls = companion.cls, hearts = companion.h,
            level = AzeCaught.CompanionLevel({ lvl = companion.lvl, cls = companion.cls, hearts = companion.h }),
            hunger = companion.hu, thirst = companion.th, affection = companion.af, energy = companion.en,
            asleep = companion.sl == true, fedStreak = companion.fs or 0, mine = ownerName == myName }
    end
    for ownerName, gameRecord in pairs(records or {}) do
        local section = type(gameRecord) == "table" and gameRecord.caught
        if ownerName ~= myName and type(section) == "table" and type(section.c) == "table" then add(ownerName, section.c) end
    end
    if myName and AzeCaught.Active() then add(myName, AzeCaught.BuildSection().c) end
    table.sort(rows, function(left, right)
        if left.level ~= right.level then return left.level > right.level end
        return left.nameRaw < right.nameRaw
    end)
    for index, row in ipairs(rows) do row.rank = index end
    return rows
end

---@class CollectionRow
---@field npc integer
---@field name string escaped
---@field lvl integer
---@field cls string
---@field disp integer
---@field caught integer
---@field active boolean
---@field seen integer

-- My collection (R6): the active companion first, then caught NPCs, then only-found ones; each group by name.
---@param collection table<integer, CollectionEntry>
---@param activeNpc integer|nil
---@return CollectionRow[]
function Model.BuildCollectionRows(collection, activeNpc)
    local rows = {}
    for npcId, entry in pairs(collection or {}) do
        rows[#rows + 1] = { npc = npcId, name = escape(entry.n), nameKey = (entry.n or ""):lower(), lvl = entry.lvl, cls = entry.cls,
            disp = entry.disp, caught = entry.caught, active = npcId == activeNpc, seen = entry.seen }
    end
    table.sort(rows, function(left, right)
        if left.active ~= right.active then return left.active end
        if (left.caught > 0) ~= (right.caught > 0) then return left.caught > 0 end
        if left.nameKey ~= right.nameKey then return left.nameKey < right.nameKey end
        return left.npc < right.npc
    end)
    return rows
end

-- The collection's two sections (user 2026-11-20): caught (the active companion first, then by name) and seen (every
-- found NPC with its highest level, highest first).
---@param collection table<integer, CollectionEntry>
---@param activeNpc integer|nil
---@return { caught: CollectionRow[], seen: CollectionRow[], caughtCount: integer, caughtLimit: integer }
function Model.BuildCollectionSections(collection, activeNpc)
    local all = Model.BuildCollectionRows(collection, activeNpc)
    local caught, seen, caughtCount = {}, {}, 0
    for _, row in ipairs(all) do
        if row.caught > 0 then caught[#caught + 1] = row; caughtCount = caughtCount + row.caught end
        seen[#seen + 1] = row
    end
    table.sort(seen, function(left, right)
        if left.lvl ~= right.lvl then return left.lvl > right.lvl end
        if left.nameKey ~= right.nameKey then return left.nameKey < right.nameKey end
        return left.npc < right.npc
    end)
    return { caught = caught, seen = seen, caughtCount = caughtCount, caughtLimit = addon.AzeCaught.MAXIMUM_CAUGHT }
end

-- Last week's best companion owner (the weekly winner line), or nil.
---@param records table<string, GameRecord>
---@param previousPeriodKey string
---@param myName string|nil
---@return { name: string, peak: integer }|nil
function Model.CompanionWinner(records, previousPeriodKey, myName)
    local first = addon.AzeCaught.WeekRanking(records, previousPeriodKey, myName)[1]
    if not first then return nil end
    return { name = escape(first.name), peak = first.peak }
end

------------------------------------------------------------------ AZEcaught: NPC info (hover overlay, user 2026-11-20)

---@param classification string|nil
---@return string
function Model.RarityText(classification)
    local Text = addon.Text
    if classification == "elite" then return Text["Elite"] end
    if classification == "rare" then return Text["Rare"] end
    if classification == "rareelite" then return Text["Rare elite"] end
    if classification == "worldboss" then return Text["Boss"] end
    return Text["Normal"]
end

-- "1h 30m" / "45m" / "-" (never)
---@param seconds number|nil
---@return string
function Model.Duration(seconds)
    local Text, Format = addon.Text, addon.Locale.Format
    if not seconds or seconds == math.huge then return "-" end
    local minutes = math.max(0, math.floor(seconds / 60 + 0.5))
    if minutes >= 60 and minutes % 60 == 0 then return Format(Text["{h}h"], { h = minutes / 60 }) end
    if minutes >= 60 then return Format(Text["{h}h {m}m"], { h = math.floor(minutes / 60), m = minutes % 60 }) end
    return Format(Text["{m}m"], { m = minutes })
end

---@param powerType integer|nil
---@return string
local function powerName(powerType)
    local Text = addon.Text
    if powerType == 0 then return Text["Mana"] end
    if powerType == 1 then return Text["Rage"] end
    if powerType == 2 then return Text["Focus"] end
    if powerType == 3 then return Text["Energy"] end
    return Text["other"]
end

-- what a trait does, for the overlay
---@param trait string
---@return string
function Model.TraitText(trait)
    local Text, Format = addon.Text, addon.Locale.Format
    if trait == "beast" then return Text["Beast: hungrier, wants more petting"] end
    if trait == "dragonkin" then return Text["Dragonkin: hungrier, stays awake longer"] end
    if trait == "demon" then return Text["Demon: hungrier, needs little petting, stays awake longer"] end
    if trait == "elemental" then return Text["Elemental: eats rarely, thirstier"] end
    if trait == "giant" then return Text["Giant: eats and drinks a lot"] end
    if trait == "undead" then return Text["Undead: never thirsty, eats rarely, sleeps little"] end
    if trait == "critter" then return Text["Critter: wants a lot of petting"] end
    if trait == "mechanical" then return Text["Mechanical: never thirsty, eats rarely, sleeps little"] end
    if trait == "aberration" then return Text["Aberration: needs less petting"] end
    if trait == "mana" then return Text["Mana: needs less petting"] end
    if trait == "rage" then return Text["Rage: gets cranky sooner"] end
    if trait == "focus" then return Text["Focus: tires a little faster"] end
    if trait == "energy" then return Text["Energy: tires faster"] end
    return Format(Text["{rarity}: gets needy sooner"], { rarity = Model.RarityText(trait) })   -- elite, rare, rare elite, boss
end

---@class NpcInfoFact
---@field label string
---@field value string

---@class NpcInfoNeed
---@field need string hunger|thirst|affection|energy
---@field label string
---@field text string "every 1h 30m" / "never"
---@field trend "more"|"less"|"normal"|"never" compared with the base schedule

---@class NpcInfo
---@field title string escaped name
---@field rarityColor string hex
---@field subtitle string "Level 36 · Elite · Beast (Wolf)"
---@field facts NpcInfoFact[] only the values the game told
---@field hiddenCount integer values the game did not tell (type, health, power, gender)
---@field needs NpcInfoNeed[]
---@field thresholds string
---@field traits string[]

local RARITY_COLOR = { normal = "ffffff", elite = "ffd100", rare = "c0c0c0", rareelite = "a335ee", worldboss = "ff8000" }
local NEED_BASE = { hunger = "FOOD_INTERVAL", thirst = "WATER_INTERVAL", affection = "PET_INTERVAL", energy = "AWAKE_INTERVAL" }

-- Everything known about a found NPC, grouped for the hover panel (user 2026-11-20: clear and short). Unknown values
-- are not listed one by one, only counted. Peer/client text is escaped.
---@param npcId integer
---@param entry CollectionEntry
---@return NpcInfo
function Model.BuildNpcInfo(npcId, entry)
    local Text, Format = addon.Text, addon.Locale.Format
    local AzeCaught = addon.AzeCaught
    local stats = type(entry.st) == "table" and entry.st or {}
    local info = { title = escape(entry.n), rarityColor = RARITY_COLOR[entry.cls] or "ffffff", facts = {}, hiddenCount = 0,
        needs = {}, traits = {} }
    local subtitle = { Format(Text["Level {n}"], { n = entry.lvl or 0 }) }
    if entry.cls ~= "normal" then subtitle[#subtitle + 1] = Model.RarityText(entry.cls) end   -- "Normal" says nothing
    if stats.typeName then
        subtitle[#subtitle + 1] = escape(stats.typeName) .. (stats.family and (" (" .. escape(stats.family) .. ")") or "")
    else
        info.hiddenCount = info.hiddenCount + 1
    end
    info.subtitle = table.concat(subtitle, " · ")
    local function fact(label, value)
        if value then info.facts[#info.facts + 1] = { label = label, value = value } else info.hiddenCount = info.hiddenCount + 1 end
    end
    fact(Text["Health"], stats.hp and tostring(stats.hp) or nil)
    fact(Text["Power"], stats.power ~= nil and (powerName(stats.power) .. (stats.powerMax and (" " .. stats.powerMax) or "")) or nil)
    fact(Text["Gender"], stats.sex == 2 and Text["male"] or stats.sex == 3 and Text["female"] or nil)
    local profile = AzeCaught.Profile(entry)
    local labels = { thirst = Text["Water"], hunger = Text["Food"], affection = Text["Petting"], energy = Text["Sleep"] }
    for _, need in ipairs({ "thirst", "hunger", "affection", "energy" }) do
        local interval, base = profile.intervals[need], AzeCaught[NEED_BASE[need]]
        local trend = not interval and "never" or interval < base * 0.99 and "more" or interval > base * 1.01 and "less" or "normal"
        local text
        if not interval then text = Text["never"]
        elseif need == "energy" then
            text = Format(Text["{sleep} every {awake}"], { sleep = Model.Duration(AzeCaught.SLEEP_DURATION), awake = Model.Duration(interval) })
        else text = Format(Text["every {time}"], { time = Model.Duration(interval) }) end
        info.needs[#info.needs + 1] = { need = need, label = labels[need], text = text, trend = trend }
    end
    info.thresholds = Format(Text["Needy below {ok}%, critical below {critical}%"], { ok = profile.ok, critical = profile.critical })
    for _, trait in ipairs(profile.traits) do info.traits[#info.traits + 1] = Model.TraitText(trait) end
    return info
end
