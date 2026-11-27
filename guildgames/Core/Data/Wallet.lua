local addonName, addon = ...

-- The money pool: ONE balance shared by every GuildGames game. Pure Lua.
--
--   balance = STARTING_GRANT + net of every casino game in my record (coin, slots, survivor)
--           - a survivor stake still pending (booked at the start of a run)
--           + ledger.earned (catch rewards, weekly payouts, dev gifts) - ledger.spent (food, water, shop, daily limit)
--
-- The casino net is read from my game record (it is already stored there), so nothing is counted twice. The ledger lives
-- in db.caught.ledger (local only, never sent). Every movement is a ledger entry with the balance after it, and a journal
-- line (AzeCaught journal), so any balance can be explained line by line (/gg caught wallet).
-- Still bookkeeping only: no real gold is read or moved.
--
-- Daily win limit: the house games (coin, slots, survivor) may raise the balance by at most DAILY_WIN_CAP per server day
-- (UTC), net: a loss that day makes room again. The record keeps every play's real result; the part of a win above the
-- limit left is booked here as a "cap" ledger entry (spent), so the balance only rises by what was paid. Playing never
-- stops at the limit: a win just pays nothing more. The day's paid net lives in db.caught.casinoDay (local only).
---@class WalletModule
local Wallet = {}
addon.Wallet = Wallet

Wallet.STARTING_GRANT = 20 * 10000            -- 20g, in copper
Wallet.MAXIMUM_AMOUNT = 2000000000 * 10000    -- same bound as Games.MAXIMUM_TOTAL
Wallet.MAXIMUM_LEDGER = 60                     -- newest ledger entries kept
Wallet.CASINO_GAMES = { "coin", "slots", "survivor", "legacySurvivor" }
Wallet.DAILY_WIN_CAP = 500 * 10000             -- 500g net per server day from the house games
Wallet.SECONDS_PER_DAY = 86400

---@class LedgerEntry
---@field t integer server time
---@field k string kind: "catch"|"payout"|"food"|"water"|"shop"|"dev"|"cap"|...
---@field a integer signed copper (+ earned, - spent)
---@field b integer balance after the movement
---@field note? string short detail (npc name, week key, ...)

---@class Ledger
---@field earned integer
---@field spent integer
---@field entries LedgerEntry[] oldest first

---@return Ledger
function Wallet.Ledger()
    local database = addon.Store.db
    database.caught = type(database.caught) == "table" and database.caught or {}
    local ledger = database.caught.ledger
    if type(ledger) ~= "table" then
        ledger = { earned = 0, spent = 0, entries = {} }
        database.caught.ledger = ledger
    end
    return ledger
end

-- The signed casino net (all time) of my record, per game and summed.
---@param myName string|nil
---@return integer total
---@return table<string, integer> byGame
function Wallet.CasinoNet(myName)
    local byGame, total = {}, 0
    local gameRecord = myName and addon.Games.Get(myName)
    for _, gameKey in ipairs(Wallet.CASINO_GAMES) do
        local section = addon.Games.Section(gameRecord, gameKey)
        local net = section and section.total and ((section.total.won or 0) - (section.total.lost or 0)) or 0
        byGame[gameKey] = net
        total = total + net
    end
    return total, byGame
end

-- The survivor stake booked as pending (a run in progress, or one left open by a /reload), 0 when none.
---@param myName string|nil
---@return integer
function Wallet.PendingStake(myName)
    local database = addon.Store.db
    local pending = database and database.ui and database.ui.survivorPending
    if type(pending) ~= "table" or pending.name ~= myName then return 0 end
    return addon.Utility.SafeInteger(pending.c, 1, addon.Games.MAXIMUM_STAKE) or 0
end

---@class WalletBreakdown
---@field grant integer
---@field casino integer
---@field byGame table<string, integer>
---@field pending integer
---@field earned integer
---@field spent integer
---@field balance integer

---@param myName string|nil
---@return WalletBreakdown
function Wallet.Breakdown(myName)
    local ledger = Wallet.Ledger()
    local casino, byGame = Wallet.CasinoNet(myName)
    local pending = Wallet.PendingStake(myName)
    local balance = Wallet.STARTING_GRANT + casino - pending + ledger.earned - ledger.spent
    return { grant = Wallet.STARTING_GRANT, casino = casino, byGame = byGame, pending = pending, earned = ledger.earned,
        spent = ledger.spent, balance = balance }
end

---@param myName string|nil
---@return integer copper (can be below 0 after past losses)
function Wallet.Balance(myName) return Wallet.Breakdown(myName).balance end

-- "funds" when `stake` is more than my balance, else nil. Used where a play or a wager STARTS (Flip, Slots.Spin,
-- Survivor.Begin, the arena wager), never where a play is settled (a run that started must always be booked).
---@param myName string|nil
---@param stake integer
---@return "funds"|nil
function Wallet.FundsRefusal(myName, stake)
    local balance = Wallet.Balance(myName)
    if type(stake) == "number" and stake > balance then
        addon.AzeCaught.Journal("WARNING", "wallet.funds", "a stake above the balance was refused",
            { stake = stake, balance = balance })
        return "funds"
    end
    return nil
end

---@param ledger Ledger
---@param entry LedgerEntry
local function appendEntry(ledger, entry)
    ledger.entries[#ledger.entries + 1] = entry
    while #ledger.entries > Wallet.MAXIMUM_LEDGER do table.remove(ledger.entries, 1) end
end

-- Pays `amount` copper into the pool. Returns the balance after it, or nil and the refusal.
---@param myName string|nil
---@param amount integer copper > 0
---@param kind string
---@param now integer
---@param note? string
---@return integer|nil balance
---@return "amount"|"readonly"|nil
function Wallet.Earn(myName, amount, kind, now, note)
    if addon.Store.db.readonly then return nil, "readonly" end
    if not addon.Utility.SafeInteger(amount, 1, Wallet.MAXIMUM_AMOUNT) then
        addon.AzeCaught.Journal("ERROR", "wallet.earn", "an invalid amount was not paid", { amount = tostring(amount), kind = kind })
        return nil, "amount"
    end
    local ledger = Wallet.Ledger()
    ledger.earned = math.min(Wallet.MAXIMUM_AMOUNT, ledger.earned + amount)
    local balance = Wallet.Balance(myName)
    appendEntry(ledger, { t = now, k = kind, a = amount, b = balance, note = note })
    addon.AzeCaught.Journal("INFORMATION", "wallet.earn", "money was paid into the pool",
        { amount = amount, kind = kind, note = note, balance = balance })
    return balance
end

-- Takes `amount` copper from the pool. Refused ("funds") when the balance is short: the pool never pays below 0.
---@param myName string|nil
---@param amount integer copper > 0
---@param kind string
---@param now integer
---@param note? string
---@return integer|nil balance
---@return "amount"|"readonly"|"funds"|nil
function Wallet.Spend(myName, amount, kind, now, note)
    if addon.Store.db.readonly then return nil, "readonly" end
    if not addon.Utility.SafeInteger(amount, 1, Wallet.MAXIMUM_AMOUNT) then
        addon.AzeCaught.Journal("ERROR", "wallet.spend", "an invalid amount was not spent", { amount = tostring(amount), kind = kind })
        return nil, "amount"
    end
    local before = Wallet.Balance(myName)
    if amount > before then
        addon.AzeCaught.Journal("WARNING", "wallet.spend", "the balance is too low", { amount = amount, kind = kind, balance = before })
        return nil, "funds"
    end
    local ledger = Wallet.Ledger()
    ledger.spent = math.min(Wallet.MAXIMUM_AMOUNT, ledger.spent + amount)
    local balance = Wallet.Balance(myName)
    appendEntry(ledger, { t = now, k = kind, a = -amount, b = balance, note = note })
    addon.AzeCaught.Journal("INFORMATION", "wallet.spend", "money was spent from the pool",
        { amount = amount, kind = kind, note = note, balance = balance })
    return balance
end

------------------------------------------------------------------ daily win limit

---@param now integer
---@return integer
function Wallet.DayOf(now) return math.floor((tonumber(now) or 0) / Wallet.SECONDS_PER_DAY) end

---@class CasinoDay
---@field d integer server day (days since 1970, UTC)
---@field n integer net copper the house games paid into the pool that day (after the limit)

-- Today's state, reset when the day changed (a fresh table when none is stored yet).
---@param now integer
---@return CasinoDay
function Wallet.CasinoDay(now)
    local database = addon.Store.db
    database.caught = type(database.caught) == "table" and database.caught or {}
    local day, state = Wallet.DayOf(now), database.caught.casinoDay
    if type(state) ~= "table" or state.d ~= day then
        state = { d = day, n = 0 }
        database.caught.casinoDay = state
    end
    return state
end

-- What a win may still add to the pool today (0..DAILY_WIN_CAP plus what was lost today).
---@param now integer
---@return integer copper
function Wallet.WinRemaining(now)
    return math.max(0, Wallet.DAILY_WIN_CAP - Wallet.CasinoDay(now).n)
end

-- Books one house-game play that was just stored in my record: a loss in full, a win up to the limit left; the part of
-- a win above it becomes a "cap" ledger entry so the balance rises by the paid part only. Returns the paid net.
---@param myName string|nil
---@param net integer signed copper of the play (the record's value)
---@param now integer
---@param gameKey string
---@return integer paid
function Wallet.BookCasino(myName, net, now, gameKey)
    local day = Wallet.CasinoDay(now)
    if net <= 0 then
        day.n = math.max(-Wallet.MAXIMUM_AMOUNT, day.n + net)
        return net
    end
    local paid = math.min(net, Wallet.WinRemaining(now))
    day.n = day.n + paid
    local cut = net - paid
    if cut > 0 then
        local ledger = Wallet.Ledger()
        ledger.spent = math.min(Wallet.MAXIMUM_AMOUNT, ledger.spent + cut)
        local balance = Wallet.Balance(myName)
        appendEntry(ledger, { t = now, k = "cap", a = -cut, b = balance, note = gameKey })
        addon.AzeCaught.Journal("INFORMATION", "wallet.cap", "a win above the daily limit was not paid",
            { game = gameKey, won = net, paid = paid, cut = cut, balance = balance })
    end
    return paid
end

-- Re-validates the persisted ledger (SavedVariables are untrusted on load). Returns true when it had to be repaired.
---@param caught table db.caught
---@return boolean repaired
function Wallet.SanitizePersisted(caught)
    local SafeInteger = addon.Utility.SafeInteger
    local dayRepaired = false
    if caught.casinoDay ~= nil then
        local state = caught.casinoDay
        local day = type(state) == "table" and SafeInteger(state.d, 0, 10000000)
        local net = type(state) == "table" and SafeInteger(state.n, -Wallet.MAXIMUM_AMOUNT, Wallet.DAILY_WIN_CAP)
        if day and net then
            caught.casinoDay = { d = day, n = net }
        else
            caught.casinoDay, dayRepaired = nil, true
        end
    end
    local ledger = caught.ledger
    if ledger == nil then return dayRepaired end
    local clean = { earned = SafeInteger(type(ledger) == "table" and ledger.earned, 0, Wallet.MAXIMUM_AMOUNT) or 0,
        spent = SafeInteger(type(ledger) == "table" and ledger.spent, 0, Wallet.MAXIMUM_AMOUNT) or 0, entries = {} }
    local repaired = type(ledger) ~= "table" or clean.earned ~= ledger.earned or clean.spent ~= ledger.spent
    if type(ledger) == "table" and type(ledger.entries) == "table" then
        for _, entry in ipairs(ledger.entries) do
            if type(entry) == "table" and SafeInteger(entry.t, 0) and type(entry.k) == "string" and #entry.k <= 16
                and SafeInteger(entry.a, -Wallet.MAXIMUM_AMOUNT, Wallet.MAXIMUM_AMOUNT)
                and SafeInteger(entry.b, -Wallet.MAXIMUM_AMOUNT * 2, Wallet.MAXIMUM_AMOUNT * 2) then
                clean.entries[#clean.entries + 1] = { t = entry.t, k = entry.k, a = entry.a, b = entry.b,
                    note = addon.Utility.CleanString(entry.note, 64) }
            else
                repaired = true
            end
        end
    end
    while #clean.entries > Wallet.MAXIMUM_LEDGER do table.remove(clean.entries, 1) end
    caught.ledger = clean
    return repaired or dayRepaired
end
