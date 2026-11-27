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

-- A payout percent as a multiplier: 105 -> "x1.05", 110 -> "x1.1", 200 -> "x2" (decimal mark from the locale).
---@param pct integer
---@return string
function Model.PercentText(pct)
    local Text, Format = addon.Text, addon.Locale.Format
    pct = math.max(0, math.floor(pct or 0))
    local whole, fraction = math.floor(pct / 100), pct % 100
    local number = tostring(whole)
    if fraction > 0 then
        local digits = fraction % 10 == 0 and tostring(fraction / 10) or string.format("%02d", fraction)
        number = Format(Text["{whole}.{fraction}"], { whole = whole, fraction = digits })
    end
    return Format(Text["x{n}"], { n = number })
end

-- The result line of a won play: the win, and when the daily win limit cut it, what was paid.
---@param net integer the play's win (record value)
---@param paid integer what the money pool got
---@return string
function Model.WinText(net, paid)
    local Text, Format = addon.Text, addon.Locale.Format
    if paid >= net then return Format(Text["You won {gold}"], { gold = Model.MoneyText(net) }) end
    if paid <= 0 then
        return Format(Text["You won {gold}, but the daily win limit is reached: nothing paid."], { gold = Model.MoneyText(net) })
    end
    return Format(Text["You won {gold}, paid {paid} (daily win limit)."], { gold = Model.MoneyText(net), paid = Model.MoneyText(paid) })
end

-- The daily win limit for the header: what a win may still add today, or that the limit is reached.
---@param now integer
---@return string
function Model.WinLimitText(now)
    local Text, Format = addon.Text, addon.Locale.Format
    local remaining = addon.Wallet.WinRemaining(now)
    if remaining <= 0 then return "|cffff9933" .. Text["Daily win limit reached"] .. "|r" end
    return Format(Text["Win limit today: {gold} left"], { gold = Model.MoneyText(remaining) })
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
---@field net integer signed net copper of the play
---@field t integer server time of the play
---@field mine boolean
---@field item boolean an item was used in the play

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
                t = entry.t, mine = playerName == myName, item = entry.it == 1 }
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

------------------------------------------------------------------ AZEcaught

---@class CompanionRow
---@field rank integer
---@field name string escaped owner
---@field nameRaw string
---@field companion string escaped shown name (the nickname, else the NPC name)
---@field species string escaped NPC name (from the NPC id in my collection first)
---@field nicknamed boolean
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

-- The guild's current companions as a leaderboard: by companion level, then owner name. My own row is built from
-- my live state (fresher than my published record). Names come from peers and are escaped.
---@param records table<string, GameRecord>
---@param myName string|nil
---@return CompanionRow[]
function Model.BuildCompanionRows(records, myName)
    local AzeCaught = addon.AzeCaught
    local rows = {}
    local function add(ownerName, companion)
        rows[#rows + 1] = { name = escape(ownerName), nameRaw = ownerName, companion = escape(AzeCaught.ShownName(companion)),
            species = escape(AzeCaught.SpeciesName(companion)), nicknamed = AzeCaught.HasNickname(companion), npc = companion.npc,
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
---@field nameKey string lower-case name (sorting)
---@field history table AzeCaught.History
---@field uid? string roster rows: the companion's id
---@field species? string roster rows: the species name, escaped (the name may be a nickname)
---@field nicknamed? boolean roster rows: the name is a nickname
---@field caughtAt? integer roster rows: server time of the catch
---@field caughtMap? integer roster rows: uiMapID of the catch

-- My collection: the active companion first, then caught NPCs, then only-found ones; each group by name.
---@param collection table<integer, CollectionEntry>
---@param activeNpc integer|nil
---@return CollectionRow[]
function Model.BuildCollectionRows(collection, activeNpc)
    local rows = {}
    for npcID, entry in pairs(collection or {}) do
        rows[#rows + 1] = { npc = npcID, name = escape(entry.n), nameKey = (entry.n or ""):lower(), lvl = entry.lvl, cls = entry.cls,
            disp = entry.disp, caught = entry.caught, active = npcID == activeNpc, seen = entry.seen,
            history = addon.AzeCaught.History(entry) }
    end
    table.sort(rows, function(left, right)
        if left.active ~= right.active then return left.active end
        if (left.caught > 0) ~= (right.caught > 0) then return left.caught > 0 end
        if left.nameKey ~= right.nameKey then return left.nameKey < right.nameKey end
        return left.npc < right.npc
    end)
    return rows
end


-- My roster as collection rows: one row per companion (uid), the active one first, then by name and catch order.
---@param roster CompanionState[] AzeCaught.Roster()
---@param collection table<integer, CollectionEntry>
---@param active CompanionState|nil
---@return CollectionRow[]
function Model.BuildRosterRows(roster, collection, active)
    local rows = {}
    for _, companion in ipairs(roster or {}) do
        local entry = collection and collection[companion.npc]
        if entry then
            local progress = type(companion.ar) == "table" and companion.ar or { xp = 0 }
            local shown = addon.AzeCaught.ShownName(companion)
            local caughtAt, caughtMap = addon.AzeCaught.CatchOrigin(companion)
            rows[#rows + 1] = { uid = companion.uid, npc = companion.npc, name = escape(shown), nameKey = shown:lower(),
                species = escape(entry.n), nicknamed = addon.AzeCaught.HasNickname(companion), caughtAt = caughtAt, caughtMap = caughtMap,
                lvl = entry.lvl, cls = entry.cls, disp = entry.disp, caught = 1, active = companion == active, seen = entry.seen,
                hearts = companion.hearts or 0, arenaLevel = addon.Arena.Level(progress.xp or 0), history = addon.AzeCaught.History(entry) }
        end
    end
    return rows
end
-- The collection's two sections: caught (the active companion first, then by name) and seen (every
-- found NPC with its highest level, highest first).
---@param collection table<integer, CollectionEntry>
---@param activeNpc integer|nil
---@return { caught: CollectionRow[], seen: CollectionRow[], caughtCount: integer }
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
    return { caught = caught, seen = seen, caughtCount = caughtCount }
end

-- A short age for a badge ("now", "5m", "3h", "2d"); nil when unknown.
---@param timestamp integer|nil
---@param now integer
---@return string|nil
function Model.ShortAge(timestamp, now)
    if type(timestamp) ~= "number" then return nil end
    local Text, Format = addon.Text, addon.Locale.Format
    local seconds = math.max(0, now - timestamp)
    if seconds < 90 then return Text["now"] end
    if seconds < 5400 then return Format(Text["{n}m"], { n = math.floor(seconds / 60) }) end
    if seconds < 129600 then return Format(Text["{n}h"], { n = math.floor(seconds / 3600) }) end
    return Format(Text["{n}d"], { n = math.floor(seconds / 86400) })
end

-- "Caught <date> in <zone>" for one of my companions. `mapName` is the client's name of its uiMapID (nil when not
-- recorded or unknown); `formatDate` turns server time into a date (the client's date(); nil in the offline tests).
---@param at integer|nil server time of the catch
---@param mapName string|nil
---@param formatDate fun(format: string, time: integer): string|nil
---@return string
function Model.CatchOriginText(at, mapName, formatDate)
    local Text, Format = addon.Text, addon.Locale.Format
    if type(at) ~= "number" then return Text["Caught: before this was recorded"] end
    local day = formatDate and formatDate(Text["%Y-%m-%d"], at) or tostring(at)
    if type(mapName) ~= "string" or mapName == "" then return Format(Text["Caught {date}"], { date = day }) end
    return Format(Text["Caught {date} in {zone}"], { date = day, zone = escape(mapName) })
end

-- The history as icon badges: key, the number to count up to (nil: text only), the badge text, whether it is "empty"
-- (shown dimmed).
---@param history table AzeCaught.History
---@param now integer server time
---@return { key: string, value: integer|nil, text: string, empty: boolean }[]
function Model.HistoryBadges(history, now)
    return {
        { key = "seen", value = history.seen, text = tostring(history.seen), empty = false },
        { key = "kills", value = history.kills, text = tostring(history.kills), empty = history.kills == 0 },
        { key = "caught", value = history.caught, text = history.caught .. "/" .. history.throws, empty = history.caught == 0 },
        { key = "last", text = Model.ShortAge(history.last, now) or "?", empty = false },
    }
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

------------------------------------------------------------------ AZEcaught: NPC info (hover overlay)

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

-- "1h 30m" / "2h" / "45m" / "-" (never)
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

-- The text for a refusal every game shares (the saved data is read-only, the pool is too small), or nil for any other
-- refusal: the caller words its own ones. Literal Text[...] keys, so the locale test sees them.
---@param refusal string|nil
---@param myName string|nil whose pool balance the "funds" text shows
---@return string|nil
function Model.CommonRefusalText(refusal, myName)
    local Text, Format = addon.Text, addon.Locale.Format
    if refusal == "readonly" then return Text["Saved data is read-only in this session."] end
    if refusal == "run" then return Text["Finish your Survivor run first."] end
    if refusal == "funds" then
        return Format(Text["Not enough money in the pool ({gold})."], { gold = Model.MoneyText(addon.Wallet.Balance(myName)) })
    end
    return nil
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
---@field history table AzeCaught.History
---@field combat { key: string, label: string, value: string, fill: number, over: boolean }[] attack, defense, speed

local RARITY_COLOR = { normal = "ffffff", elite = "ffd100", rare = "c0c0c0", rareelite = "a335ee", worldboss = "ff8000" }
local NEED_BASE = { hunger = "FOOD_INTERVAL", thirst = "WATER_INTERVAL", affection = "PET_INTERVAL", energy = "AWAKE_INTERVAL" }

-- Everything known about a found NPC, grouped for the hover panel. Unknown values
-- are not listed one by one, only counted. Peer/client text is escaped.
---@param npcID integer
---@param entry CollectionEntry
---@return NpcInfo
function Model.BuildNpcInfo(npcID, entry)
    local Text, Format = addon.Text, addon.Locale.Format
    local AzeCaught = addon.AzeCaught
    local stats = type(entry.st) == "table" and entry.st or {}
    local npcView = { title = escape(entry.n), rarityColor = RARITY_COLOR[entry.cls] or "ffffff", facts = {}, hiddenCount = 0,
        needs = {}, traits = {}, history = AzeCaught.History(entry) }
    local subtitle = { Format(Text["Level {n}"], { n = entry.lvl or 0 }) }
    if entry.cls ~= "normal" then subtitle[#subtitle + 1] = Model.RarityText(entry.cls) end   -- "Normal" says nothing
    if stats.typeName then
        subtitle[#subtitle + 1] = escape(stats.typeName) .. (stats.family and (" (" .. escape(stats.family) .. ")") or "")
    else
        npcView.hiddenCount = npcView.hiddenCount + 1
    end
    npcView.subtitle = table.concat(subtitle, " · ")
    local function fact(label, value)
        if value then npcView.facts[#npcView.facts + 1] = { label = label, value = value } else npcView.hiddenCount = npcView.hiddenCount + 1 end
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
        npcView.needs[#npcView.needs + 1] = { need = need, label = labels[need], text = text, trend = trend }
    end
    npcView.thresholds = Format(Text["Needy below {ok}%, critical below {critical}%"], { ok = profile.ok, critical = profile.critical })
    for _, trait in ipairs(profile.traits) do npcView.traits[#npcView.traits + 1] = Model.TraitText(trait) end
    -- calculated, so always known; fill = share of a full bar (capped), over = stronger than full
    local combat, scale = AzeCaught.CombatStats(npcID, entry), AzeCaught.CombatScale()
    npcView.combat = {}
    for _, stat in ipairs({ { "attack", Text["Attack"] }, { "defense", Text["Defense"] }, { "speed", Text["Speed"] } }) do
        local value = combat[stat[1]]
        npcView.combat[#npcView.combat + 1] = { key = stat[1], label = stat[2], value = tostring(value),
            fill = math.min(1, value / scale), over = value > scale }
    end
    return npcView
end

------------------------------------------------------------------ the pet view (minimal window)

Model.PET_VIEW_DEFAULTS = { startMode = "minimal", opacity = 1, scale = 1, locked = false, hideInCombat = true }
Model.PET_VIEW_LIMITS = { opacity = { 0.2, 1 }, scale = { 0.5, 2 } }
Model.PET_VIEW_GAUGES = { "feed", "water", "pet", "sleep" }
Model.GAUGE_NEED = { feed = "hunger", water = "thirst", pet = "affection", sleep = "energy" }
Model.GAUGE_ZONE_COLOR = { ok = { 0.3, 0.85, 0.35 }, needy = { 1, 0.75, 0.15 }, critical = { 1, 0.25, 0.2 }, empty = { 0.6, 0.1, 0.1 },
    never = { 0.45, 0.45, 0.45 } }

---@param value any
---@return boolean
local function isNumber(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end

---@param value any
---@param limits number[]
---@param default number
---@return number
local function clampOr(value, limits, default)
    if not isNumber(value) then return default end
    return math.max(limits[1], math.min(limits[2], value))
end

-- The pet view's options from db.ui.petView, with defaults for missing or broken values (the saved table is not changed).
---@param raw any
---@return { startMode: "minimal"|"full", opacity: number, scale: number, locked: boolean, hideInCombat: boolean, open: boolean, mode: "minimal"|"full", left: number|nil, top: number|nil }
function Model.PetViewSettings(raw)
    raw = type(raw) == "table" and raw or {}
    local defaults, limits = Model.PET_VIEW_DEFAULTS, Model.PET_VIEW_LIMITS
    local function mode(value, default) return (value == "minimal" or value == "full") and value or default end
    local function flag(value, default) if type(value) == "boolean" then return value end return default end
    local startMode = mode(raw.startMode, defaults.startMode)
    return {
        startMode = startMode,
        mode = mode(raw.mode, startMode),
        opacity = clampOr(raw.opacity, limits.opacity, defaults.opacity),
        scale = clampOr(raw.scale, limits.scale, defaults.scale),
        locked = flag(raw.locked, defaults.locked),
        hideInCombat = flag(raw.hideInCombat, defaults.hideInCombat),
        open = raw.open == true,
        left = isNumber(raw.left) and raw.left or nil,
        top = isNumber(raw.top) and raw.top or nil,
    }
end

-- The share of a gauge's ring for a need value of 0..100: 0..1, broken values show none.
---@param value any
---@return number
function Model.GaugeShare(value)
    if not isNumber(value) then return 0 end
    return math.max(0, math.min(100, value)) / 100
end

-- The arc cell for `share` (0..1) out of `cells` drawn arcs (cell n = n/cells of the ring); nil when nothing shows.
-- Rounded to the nearest cell, so a sliver above 0 still shows one cell and almost-full shows the whole ring.
---@param share number
---@param cells integer
---@return integer|nil
function Model.RingArc(share, cells)
    local value = Model.GaugeShare((tonumber(share) or 0) * 100)
    if value <= 0 then return nil end
    return math.max(1, math.min(cells, math.floor(value * cells + 0.5)))
end

-- Texture coordinates (left, right, top, bottom) of arc cell `cell` (1-based, row by row) in a `columns` x `columns` grid.
---@param cell integer
---@param columns integer
---@return number left, number right, number top, number bottom
function Model.ArcTexCoord(cell, columns)
    local index = cell - 1
    local column, row = index % columns, math.floor(index / columns)
    return column / columns, (column + 1) / columns, row / columns, (row + 1) / columns
end

-- Animations an idle companion may play on its own (AnimationData ids: roar, dance, laugh, wave, cheer, bow, talk,
-- exclamation, question, flex, point, eat, unarmed and one-handed attack, special attack). A model plays only those
-- it has (HasAnimation); creatures mostly have roar and the attacks.
Model.IDLE_EMOTES = { 74, 69, 70, 67, 68, 66, 60, 64, 65, 82, 84, 61, 16, 17, 57 }
Model.IDLE_EMOTE_DELAY = { 90, 240 }   -- seconds between two of them, at random

-- Seconds until the next idle emote.
---@param random fun(low: integer, high: integer): integer
---@return integer
function Model.IdleEmoteDelay(random)
    return random(Model.IDLE_EMOTE_DELAY[1], Model.IDLE_EMOTE_DELAY[2])
end

-- The idle emotes in a random order (Fisher-Yates; the list itself stays as it is).
---@param random fun(low: integer, high: integer): integer
---@return integer[]
function Model.ShuffledIdleEmotes(random)
    local order = {}
    for index, animationID in ipairs(Model.IDLE_EMOTES) do order[index] = animationID end
    for index = #order, 2, -1 do
        local other = random(1, index)
        order[index], order[other] = order[other], order[index]
    end
    return order
end

-- The colour of a gauge: its need's zone, grey when the companion never has this need.
---@param zone string|nil
---@return number[]
function Model.GaugeColor(zone)
    return Model.GAUGE_ZONE_COLOR[zone] or Model.GAUGE_ZONE_COLOR.never
end

-- Where everything of the pet view sits, as offsets from the frame's top-left corner (x right, y down is negative).
-- The pet is the circle in the middle; the four gauges sit around its lower half (left, lower left, lower right,
-- right); the switch icon is in the top-left corner and the heart in the top-right one.
---@param petSize number diameter of the pet circle
---@param gaugeSize number diameter of a gauge
---@param cornerSize number size of the switch icon and the heart
---@return { width: number, height: number, pet: { x: number, y: number }, gauges: table<string, { x: number, y: number }>, switch: { x: number, y: number }, heart: { x: number, y: number } }
function Model.PetViewLayout(petSize, gaugeSize, cornerSize)
    local orbit = petSize / 2 + gaugeSize / 2 + 5
    local angles = { feed = 270, water = 215, pet = 145, sleep = 90 }   -- degrees clockwise from 12 o'clock
    local margin = 2
    local half = math.max(orbit + gaugeSize / 2, petSize / 2) + margin
    local width = half * 2
    -- the training button sits at 6 o'clock on the same orbit (between water and pet)
    local below = math.max(orbit * math.cos(math.rad(180 - 145)) + gaugeSize / 2, orbit + cornerSize / 2) + margin
    local above = math.max(petSize / 2, cornerSize) + margin + cornerSize / 2
    local height = above + below
    local centerX, centerY = width / 2, -above
    local layout = { width = width, height = height, pet = { x = centerX, y = centerY }, gauges = {} }
    for key, degrees in pairs(angles) do
        local angle = math.rad(degrees)
        layout.gauges[key] = { x = centerX + math.sin(angle) * orbit, y = centerY + math.cos(angle) * orbit }
    end
    layout.switch = { x = margin + cornerSize / 2, y = -(margin + cornerSize / 2) }
    layout.heart = { x = width - margin - cornerSize / 2, y = -(margin + cornerSize / 2) }
    layout.train = { x = centerX, y = centerY - orbit }
    return layout
end

-- A window's top-left corner moved so the window stays on the screen (all in UIParent units, y up).
---@param left number
---@param top number
---@param width number
---@param height number
---@param screenWidth number
---@param screenHeight number
---@return number left, number top
function Model.KeepOnScreen(left, top, width, height, screenWidth, screenHeight)
    if not isNumber(left) then left = (screenWidth - width) / 2 end
    if not isNumber(top) then top = (screenHeight + height) / 2 end
    left = math.max(0, math.min(screenWidth - math.min(width, screenWidth), left))
    top = math.min(screenHeight, math.max(math.min(height, screenHeight), top))
    return left, top
end
