-- Games leaderboard view-models (feature 014, R6-R8).
local function totals(won, lost, wins, losses) return { won = won, lost = lost, wins = wins, losses = losses } end

local function gameRecord(name, total, weeks, recent)
    return { name = name, rev = 1, total = total, weeks = weeks or {}, recent = recent or {} }
end

return {
    ["games model: leaderboard sorts by net, then flips, then name; hides players without flips (R6)"] = function(harness)
        local Model = harness.addon().Model
        local records = {
            ["B-R"] = gameRecord("B-R", totals(100, 0, 1, 0)),
            ["A-R"] = gameRecord("A-R", totals(300, 200, 2, 2)),     -- net 100, 4 flips
            ["C-R"] = gameRecord("C-R", totals(100, 0, 1, 0)),       -- same as B: name order
            ["D-R"] = gameRecord("D-R", totals(0, 50, 0, 1)),
            ["E-R"] = gameRecord("E-R", totals(0, 0, 0, 0)),
        }
        local rows = Model.BuildLeaderboardRows(records, "all", "2026-W47", "C-R")
        harness.equal(#rows, 4)
        local order = {}
        for index, row in ipairs(rows) do order[index] = row.nameRaw; harness.equal(row.rank, index) end
        harness.equal(table.concat(order, ","), "A-R,B-R,C-R,D-R")
        harness.equal(rows[4].net, -50); harness.equal(rows[1].flips, 4)
        harness.truthy(rows[3].mine); harness.truthy(not rows[1].mine)
    end,

    ["games model: scope week reads the week's totals only (R6)"] = function(harness)
        local Model = harness.addon().Model
        local records = {
            ["A-R"] = gameRecord("A-R", totals(1000, 0, 5, 0), { ["2026-W46"] = totals(1000, 0, 5, 0) }),
            ["B-R"] = gameRecord("B-R", totals(10, 20, 1, 1), { ["2026-W47"] = totals(10, 20, 1, 1) }),
        }
        local week = Model.BuildLeaderboardRows(records, "week", "2026-W47", nil)
        harness.equal(#week, 1); harness.equal(week[1].nameRaw, "B-R"); harness.equal(week[1].net, -10)
        harness.equal(#Model.BuildLeaderboardRows(records, "all", "2026-W47", nil), 2)
    end,

    ["games model: peer names are escaped"] = function(harness)
        local Model = harness.addon().Model
        local records = { ["Evil|cff-R"] = gameRecord("Evil|cff-R", totals(5, 0, 1, 0), {}, { { c = 5, r = "W", t = 9 } }) }
        harness.equal(Model.BuildLeaderboardRows(records, "all", "x", nil)[1].name, "Evil||cff-R")
        harness.equal(Model.BuildFlipFeedRows(records, nil)[1].name, "Evil||cff-R")
    end,

    ["games model: the flip feed merges every player's flips, newest first, limit 15 (R7)"] = function(harness)
        local Model = harness.addon().Model
        local recentA, recentB = {}, {}
        for index = 1, 10 do recentA[index] = { c = index, r = "W", t = 200 - index * 2 } end      -- 198, 196, ...
        for index = 1, 10 do recentB[index] = { c = index, r = "L", t = 199 - index * 2 } end      -- 197, 195, ...
        local records = { ["A-R"] = gameRecord("A-R", totals(55, 0, 10, 0), {}, recentA),
            ["B-R"] = gameRecord("B-R", totals(0, 55, 0, 10), {}, recentB) }
        local rows = Model.BuildFlipFeedRows(records, "B-R")
        harness.equal(#rows, 15)
        harness.equal(rows[1].nameRaw, "A-R"); harness.equal(rows[1].net, 1); harness.equal(rows[1].t, 198)
        harness.equal(rows[2].nameRaw, "B-R"); harness.equal(rows[2].net, -1); harness.truthy(rows[2].mine)
        for index = 2, #rows do harness.truthy(rows[index - 1].t >= rows[index].t) end
        harness.equal(#Model.BuildFlipFeedRows(records, nil, 5), 5)
        harness.equal(#Model.BuildFlipFeedRows({}, nil), 0)
    end,

    ["games model: last week's winner: none, best net, tie by flips then name (R8)"] = function(harness)
        local Model = harness.addon().Model
        harness.equal(Model.PreviousWinner({}, "2026-W46"), nil)
        local losers = { ["A-R"] = gameRecord("A-R", totals(0, 9, 0, 1), { ["2026-W46"] = totals(0, 9, 0, 1) }) }
        harness.equal(Model.PreviousWinner(losers, "2026-W46"), nil, "nobody ended the week ahead")
        local records = {
            ["B-R"] = gameRecord("B-R", totals(50, 0, 1, 0), { ["2026-W46"] = totals(50, 0, 1, 0) }),
            ["A-R"] = gameRecord("A-R", totals(50, 0, 1, 0), { ["2026-W46"] = totals(50, 0, 1, 0) }),
            ["C-R"] = gameRecord("C-R", totals(150, 100, 2, 1), { ["2026-W46"] = totals(150, 100, 2, 1) }),
            ["D-R"] = gameRecord("D-R", totals(999, 0, 1, 0), { ["2026-W47"] = totals(999, 0, 1, 0) }),   -- this week
        }
        local winner = Model.PreviousWinner(records, "2026-W46")
        harness.equal(winner.nameRaw, "C-R", "same net 50: more flips wins"); harness.equal(winner.net, 50)
        records["C-R"] = nil
        harness.equal(Model.PreviousWinner(records, "2026-W46").nameRaw, "A-R", "then by name")
    end,

    -- feature 019: the one duration text (companion panel, minimap tooltip and NPC info used three copies)
    ["model: Duration rounds to minutes, whole hours without minutes, never is a dash"] = function(harness)
        local Model = harness.addon().Model
        harness.equal(Model.Duration(math.huge), "-"); harness.equal(Model.Duration(nil), "-")
        harness.equal(Model.Duration(0), "0m"); harness.equal(Model.Duration(-30), "0m")
        harness.equal(Model.Duration(89), "1m"); harness.equal(Model.Duration(91), "2m")
        harness.equal(Model.Duration(7200), "2h"); harness.equal(Model.Duration(5400), "1h 30m")
    end,

    ["model: CommonRefusalText words read-only and funds, leaves every other refusal to the caller"] = function(harness)
        local addon = harness.addon()
        local Model = addon.Model
        harness.equal(Model.CommonRefusalText("readonly", "Me-R"), "Saved data is read-only in this session.")
        local fundsText = Model.CommonRefusalText("funds", "Me-R")
        harness.truthy(fundsText:find("Not enough money in the pool", 1, true), fundsText)
        harness.truthy(fundsText:find(Model.MoneyText(addon.Wallet.Balance("Me-R")), 1, true), "shows the balance: " .. fundsText)
        for _, refusal in ipairs({ "name", "stake", "full", "asleep", "cooldown" }) do
            harness.equal(Model.CommonRefusalText(refusal, "Me-R"), nil, refusal)
        end
        harness.equal(Model.CommonRefusalText(nil, "Me-R"), nil)
    end,
}
