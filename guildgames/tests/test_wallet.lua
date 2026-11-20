-- The money pool (feature 018, R15/R18): balance, ledger, the stake limit in every casino game.
local NOW = 1794873600

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = "Me-R"
    return addon
end

local function constant(value) return function() return value end end

return {
    ["wallet: a new player starts with the 20g grant; casino results move the balance"] = function(harness)
        local addon = fresh(harness)
        local Wallet = addon.Wallet
        harness.equal(Wallet.Balance("Me-R"), 20 * 10000)
        assert(addon.Games.Flip("Me-R", 5 * 10000, "H", NOW, constant(0.1)))   -- heads: won 5g
        harness.equal(Wallet.Balance("Me-R"), 25 * 10000)
        assert(addon.Games.Flip("Me-R", 10 * 10000, "T", NOW, constant(0.1)))  -- lost 10g
        local breakdown = Wallet.Breakdown("Me-R")
        harness.equal(breakdown.balance, 15 * 10000); harness.equal(breakdown.byGame.coin, -5 * 10000)
    end,

    ["wallet: a stake above the balance is refused in every game, one exactly at it is allowed (RF6)"] = function(harness)
        local addon = fresh(harness)
        local balance = addon.Wallet.Balance("Me-R")
        harness.equal(select(2, addon.Games.Flip("Me-R", balance + 1, "H", NOW, constant(0.1))), "funds")
        harness.equal(addon.Games.Get("Me-R"), nil, "a refused play records nothing")
        harness.equal(select(2, addon.Slots.Spin("Me-R", balance + 1, NOW, constant(0.1))), "funds")
        harness.equal(addon.Games.Get("Me-R"), nil)
        harness.equal(select(2, addon.Survivor.Begin("Me-R", balance + 1, 1, NOW, constant(0.1))), "funds")
        harness.equal(addon.Store.db.ui.survivorPending, nil, "nothing pending after a refused start")
        harness.truthy(addon.Games.Flip("Me-R", balance, "H", NOW, constant(0.1)), "all in")
        -- a negative balance from history refuses even 1c
        addon.Wallet.Ledger().spent = 10 ^ 9
        harness.equal(select(2, addon.Games.Flip("Me-R", 1, "H", NOW, constant(0.1))), "funds")
        local journal = table.concat(addon.AzeCaught.State().journal, "\n")
        harness.truthy(journal:find("a stake above the balance was refused", 1, true))
    end,

    ["wallet: a running survivor stake counts against the balance; settling is never refused"] = function(harness)
        local addon = fresh(harness)
        local run = assert(addon.Survivor.Begin("Me-R", 15 * 10000, 1, NOW, constant(0.5)))
        harness.equal(addon.Wallet.Balance("Me-R"), 5 * 10000, "the pending stake is booked")
        harness.equal(select(2, addon.Games.Flip("Me-R", 6 * 10000, "H", NOW, constant(0.1))), "funds")
        -- spending during the run (care) must not block the settle
        addon.Wallet.Ledger().spent = addon.Wallet.Ledger().spent + 5 * 10000
        run.finished = "lost"
        addon.Survivor.Settle(run, NOW)
        harness.equal(addon.Games.Get("Me-R").survivor.total.lost, 15 * 10000, "the loss was booked")
        harness.equal(addon.Wallet.Balance("Me-R"), 0)
    end,

    ["wallet: spend refuses below zero, earn rejects bad amounts, the ledger is bounded and explains the balance"] = function(harness)
        local addon = fresh(harness)
        local Wallet = addon.Wallet
        harness.equal(select(2, Wallet.Spend("Me-R", 21 * 10000, "food", NOW)), "funds")
        harness.equal(select(2, Wallet.Earn("Me-R", 0, "dev", NOW)), "amount")
        harness.equal(select(2, Wallet.Earn("Me-R", 1.5, "dev", NOW)), "amount")
        harness.equal(Wallet.Spend("Me-R", 100, "food", NOW, "Wolf"), 20 * 10000 - 100)
        local ledger = Wallet.Ledger()
        harness.equal(ledger.entries[#ledger.entries].b, 20 * 10000 - 100)
        harness.equal(ledger.entries[#ledger.entries].a, -100); harness.equal(ledger.entries[#ledger.entries].note, "Wolf")
        for _ = 1, Wallet.MAXIMUM_LEDGER + 10 do Wallet.Earn("Me-R", 1, "dev", NOW) end
        harness.equal(#ledger.entries, Wallet.MAXIMUM_LEDGER)
        addon.Store.db.readonly = true
        harness.equal(select(2, Wallet.Earn("Me-R", 1, "dev", NOW)), "readonly")
        harness.equal(select(2, Wallet.Spend("Me-R", 1, "dev", NOW)), "readonly")
    end,
}
