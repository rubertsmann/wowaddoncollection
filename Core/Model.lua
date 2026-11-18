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
