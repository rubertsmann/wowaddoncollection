-- The daily win limit of the house games (coin, slots, survivor), free play, the "run" refusal and the "tower" record
-- section that holds survivor plays with small percent payouts.
local NOW = 1794873600   -- 2026-11-17 00:00 UTC
local DAY = 86400
local GOLD = 10000

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = "Me-R"
    addon.Wallet.Ledger().earned = 100000 * GOLD   -- enough pool for big stakes
    return addon
end

local function constant(value) return function() return value end end

-- heads wins a flip on "H" with constant(0.1); constant(0.9) gives tails
local WIN, LOSE = constant(0.1), constant(0.9)

-- a slot spin whose middle row shows three bags (x3) and nothing else
local function bagRow(addon)
    local Slots = addon.Slots
    for stop = 1, #Slots.STRIP do
        local stops = { stop, stop, stop }
        local lines, multiplier = Slots.Evaluate(Slots.Grid(stops))
        if multiplier > 0 and #lines >= 1 then
            local draws, index = {}, 0
            for reel = 1, Slots.REELS do draws[reel] = (stops[reel] - 1 + 0.5) / #Slots.STRIP end
            return function() index = index + 1; return draws[index] end, multiplier
        end
    end
    error("no winning stop")
end

return {
    ["daily cap: a win above the limit left pays the rest only; the record keeps the real result"] = function(harness)
        local addon = fresh(harness)
        local Wallet = addon.Wallet
        harness.equal(Wallet.DAILY_WIN_CAP, 500 * GOLD)
        local before = Wallet.Balance("Me-R")
        local first = assert(addon.Games.Flip("Me-R", 200 * GOLD, "H", NOW, WIN))
        harness.equal(first.net, 200 * GOLD); harness.equal(first.paid, 200 * GOLD)
        harness.equal(Wallet.WinRemaining(NOW), 300 * GOLD)
        local second = assert(addon.Games.Flip("Me-R", 1000 * GOLD, "H", NOW + 1, WIN))
        harness.equal(second.net, 1000 * GOLD, "the play's real result")
        harness.equal(second.paid, 300 * GOLD, "only the limit left is paid")
        harness.equal(Wallet.Balance("Me-R"), before + 500 * GOLD, "the pool rose by exactly the limit")
        harness.equal(addon.Games.Get("Me-R").total.won, 1200 * GOLD, "the record keeps every win")
        local entries = Wallet.Ledger().entries
        local last = entries[#entries]
        harness.equal(last.k, "cap"); harness.equal(last.a, -700 * GOLD); harness.equal(last.note, "coin")
        harness.equal(last.b, Wallet.Balance("Me-R"), "the cap entry explains the balance")
        harness.equal(Wallet.WinRemaining(NOW + 2), 0)
        harness.truthy(addon.Games.Sanitize(addon.Games.Get("Me-R")), "my record still passes peer validation")
    end,

    ["daily cap: playing goes on at the limit; a win pays nothing more, a loss costs the stake and makes room"] = function(harness)
        local addon = fresh(harness)
        local Wallet = addon.Wallet
        assert(addon.Games.Flip("Me-R", 500 * GOLD, "H", NOW, WIN))
        local full = Wallet.Balance("Me-R")
        local win = assert(addon.Games.Flip("Me-R", 1, "H", NOW + 1, WIN))
        harness.equal(win.paid, 0, "a 1c win at the limit pays nothing")
        harness.equal(Wallet.Balance("Me-R"), full)
        local loss = assert(addon.Games.Flip("Me-R", 50 * GOLD, "H", NOW + 2, LOSE))
        harness.equal(loss.paid, -50 * GOLD)
        harness.equal(Wallet.Balance("Me-R"), full - 50 * GOLD)
        harness.equal(Wallet.WinRemaining(NOW + 3), 50 * GOLD, "net: the loss made room again")
        local back = assert(addon.Games.Flip("Me-R", 80 * GOLD, "H", NOW + 4, WIN))
        harness.equal(back.paid, 50 * GOLD)
        harness.equal(Wallet.Balance("Me-R"), full, "never above +500g for the day")
    end,

    ["daily cap: a loss first raises what may be won back the same day"] = function(harness)
        local addon = fresh(harness)
        local start = addon.Wallet.Balance("Me-R")
        assert(addon.Games.Flip("Me-R", 300 * GOLD, "H", NOW, LOSE))
        harness.equal(addon.Wallet.WinRemaining(NOW), 800 * GOLD)
        local win = assert(addon.Games.Flip("Me-R", 1000 * GOLD, "H", NOW + 1, WIN))
        harness.equal(win.paid, 800 * GOLD)
        harness.equal(addon.Wallet.Balance("Me-R"), start + 500 * GOLD)
    end,

    ["daily cap: the limit is shared by coin, slots and survivor"] = function(harness)
        local addon = fresh(harness)
        local Wallet = addon.Wallet
        assert(addon.Games.Flip("Me-R", 450 * GOLD, "H", NOW, WIN))
        local random, multiplier = bagRow(addon)
        local spin = assert(addon.Slots.Spin("Me-R", 10 * GOLD, NOW + 1, random))
        harness.equal(spin.multiplier, multiplier)
        harness.truthy(spin.net > 50 * GOLD, "the spin won more than was left")
        harness.equal(spin.paid, 50 * GOLD)
        local run = assert(addon.Survivor.Begin("Me-R", 100 * GOLD, 1, NOW + 2, constant(0.5)))
        run.finished = "won"
        local net, paid = addon.Survivor.Settle(run, NOW + 70)
        harness.equal(net, 5 * GOLD, "105% of 100g")
        harness.equal(paid, 0, "the limit was used up by the other games")
        harness.equal(Wallet.CasinoDay(NOW + 70).n, 500 * GOLD)
    end,

    ["daily cap: a new UTC day starts a new limit; garbage day state is repaired on load"] = function(harness)
        local addon = fresh(harness)
        local Wallet = addon.Wallet
        assert(addon.Games.Flip("Me-R", 500 * GOLD, "H", NOW + DAY - 1, WIN))
        harness.equal(Wallet.WinRemaining(NOW + DAY - 1), 0)
        harness.equal(Wallet.WinRemaining(NOW + DAY), 500 * GOLD, "00:00 UTC resets the limit")
        harness.equal(assert(addon.Games.Flip("Me-R", 100 * GOLD, "H", NOW + DAY, WIN)).paid, 100 * GOLD)
        -- a run that started before midnight is settled with the new day's limit
        assert(addon.Games.Flip("Me-R", 400 * GOLD, "H", NOW + DAY + 1, WIN))
        local run = assert(addon.Survivor.Begin("Me-R", 100 * GOLD, 1, NOW + 2 * DAY - 30, constant(0.5)))
        run.finished = "won"
        harness.equal(select(2, addon.Survivor.Settle(run, NOW + 2 * DAY + 30)), 5 * GOLD)
        for _, garbage in ipairs({ "x", { d = "1", n = 0 }, { d = 1, n = 1.5 }, { d = 1, n = Wallet.DAILY_WIN_CAP + 1 } }) do
            local caught = { casinoDay = garbage }
            harness.equal(Wallet.SanitizePersisted(caught), true, "repaired")
            harness.equal(caught.casinoDay, nil)
        end
        local caught = { casinoDay = { d = 20000, n = -5 } }
        harness.equal(Wallet.SanitizePersisted(caught), false)
        harness.equal(caught.casinoDay.n, -5)
    end,

    ["daily cap: the cap total lives in ledger.spent, so pruning old entries never changes the balance"] = function(harness)
        local addon = fresh(harness)
        local Wallet = addon.Wallet
        assert(addon.Games.Flip("Me-R", 600 * GOLD, "H", NOW, WIN))
        local balance = Wallet.Balance("Me-R")
        for index = 1, Wallet.MAXIMUM_LEDGER + 5 do Wallet.Earn("Me-R", 1, "dev", NOW + index) end
        harness.equal(Wallet.Balance("Me-R"), balance + Wallet.MAXIMUM_LEDGER + 5)
        for _, entry in ipairs(Wallet.Ledger().entries) do harness.truthy(entry.k ~= "cap", "the cap entry was pruned") end
    end,

    ["free play: stake 0 draws a result and stores nothing in every game"] = function(harness)
        local addon = fresh(harness)
        local balance = addon.Wallet.Balance("Me-R")
        local flip = assert(addon.Games.Flip("Me-R", 0, "H", NOW, WIN))
        harness.equal(flip.free, true); harness.equal(flip.won, true); harness.equal(flip.paid, 0)
        local random = bagRow(addon)
        local spin = assert(addon.Slots.Spin("Me-R", 0, NOW, random))
        harness.equal(spin.free, true); harness.truthy(spin.multiplier > 0); harness.equal(spin.net, 0); harness.equal(spin.paid, 0)
        local run = assert(addon.Survivor.Begin("Me-R", 0, 1, NOW, constant(0.5)))
        harness.equal(addon.db.ui.survivorPending, nil, "a free run marks nothing pending")
        run.finished = "won"
        harness.equal(addon.Survivor.Settle(run, NOW + 70), 0)
        harness.equal(addon.Games.Get("Me-R"), nil, "nothing recorded")
        harness.equal(addon.Wallet.Balance("Me-R"), balance)
        harness.equal(addon.Wallet.CasinoDay(NOW).n, 0)
        -- free play works at the limit and while read-only
        addon.Store.db.readonly = true
        harness.truthy(addon.Games.Flip("Me-R", 0, "T", NOW, WIN))
    end,

    ["run refusal: coin and slots wait while a survivor stake is pending; free play does not"] = function(harness)
        local addon = fresh(harness)
        local run = assert(addon.Survivor.Begin("Me-R", 10 * GOLD, 1, NOW, constant(0.5)))
        harness.equal(select(2, addon.Games.Flip("Me-R", 1 * GOLD, "H", NOW, WIN)), "run")
        harness.equal(select(2, addon.Slots.Spin("Me-R", 1 * GOLD, NOW, WIN)), "run")
        harness.truthy(addon.Games.Flip("Me-R", 0, "H", NOW, WIN))
        harness.equal(addon.Games.Get("Me-R"), nil)
        addon.Survivor.Settle(run, NOW + 5)
        harness.truthy(addon.Games.Flip("Me-R", 1 * GOLD, "H", NOW + 6, WIN))
        harness.equal(addon.Model.CommonRefusalText("run", "Me-R"), "Finish your Survivor run first.")
    end,

    ["tower section: a survivor win nets 1c..stake; the old survivor field is kept as history and still counts"] = function(harness)
        local addon = fresh(harness)
        local Games = addon.Games
        local function record(fields)
            local base = { name = "Peer-R", rev = NOW, total = { won = 0, lost = 0, wins = 0, losses = 0 }, weeks = {}, recent = {} }
            for key, value in pairs(fields) do base[key] = value end
            return base
        end
        local function section(net)
            local totals = net > 0 and { won = net, lost = 0, wins = 1, losses = 0 } or { won = 0, lost = -net, wins = 0, losses = 1 }
            return { total = totals, weeks = { [Games.PeriodKey(NOW)] = totals }, recent = { { c = 100, n = net, t = NOW } } }
        end
        harness.truthy(Games.Sanitize(record({ tower = section(1) })), "1c on a 100c stake")
        harness.truthy(Games.Sanitize(record({ tower = section(100) })))
        harness.truthy(Games.Sanitize(record({ tower = section(-100) })))
        harness.equal(Games.Sanitize(record({ tower = section(101) })), nil)
        -- the field from before 1.9: 2x..64x wins stay valid, and count in the pool
        local old = assert(Games.Sanitize(record({ survivor = section(6300) })))
        harness.equal(old.survivor.total.won, 6300)
        harness.equal(Games.Sanitize(record({ survivor = section(50) })), nil, "old field: a win below the stake")
        Games.Put(old)
        harness.equal(Games.Section(Games.Get("Peer-R"), "legacySurvivor").total.won, 6300)
        harness.equal(Games.Section(Games.Get("Peer-R"), "survivor"), nil, "no new plays there")
        addon.db.games["Me-R"] = Games.Sanitize(record({ name = "Me-R", survivor = section(6300), tower = section(5) }))
        local _, byGame = addon.Wallet.CasinoNet("Me-R")
        harness.equal(byGame.legacySurvivor, 6300); harness.equal(byGame.survivor, 5)
    end,

    ["tower section: a peer that does not know the field drops it and keeps the record"] = function(harness)
        local addon = fresh(harness)
        local Games = addon.Games
        local run = assert(addon.Survivor.Begin("Me-R", 1000, 1, NOW, constant(0.5)))
        run.finished = "won"
        addon.Survivor.Settle(run, NOW + 70)
        assert(addon.Games.Flip("Me-R", 10, "H", NOW + 71, WIN))
        local mine = addon.Utility.DeepCopy(Games.Get("Me-R"))
        harness.equal(mine.tower.recent[1].n, 50)
        -- a 1.8 peer only knows the fields slots and survivor: emulate its field list
        local stored = Games.STORED
        Games.STORED = { "slots", "legacySurvivor" }
        local seen = Games.Sanitize(mine)
        Games.STORED = stored
        harness.truthy(seen, "the record is kept")
        harness.equal(seen.tower, nil, "the unknown field is dropped")
        harness.equal(seen.total.wins, 1, "the coin results are still there")
    end,

    ["percent text: 105 -> x1.05, 110 -> x1.1, 200 -> x2; German uses a comma"] = function(harness)
        local addon = fresh(harness)
        harness.equal(addon.Model.PercentText(105), "x1.05")
        harness.equal(addon.Model.PercentText(110), "x1.1")
        harness.equal(addon.Model.PercentText(130), "x1.3")
        harness.equal(addon.Model.PercentText(200), "x2")
        harness.equal(addon.Model.WinText(50, 50), "You won |cffeda55f50c|r")
        harness.equal(addon.Locale.Format(addon.Locale.strings.deDE["{whole}.{fraction}"], { whole = 1, fraction = "05" }), "1,05")
        harness.truthy(addon.Model.WinText(100, 40):find("daily win limit", 1, true))
        harness.truthy(addon.Model.WinText(100, 0):find("nothing paid", 1, true))
    end,
}
