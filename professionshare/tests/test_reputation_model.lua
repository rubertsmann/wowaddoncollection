-- Misc Items, Reputation mode: rows (Model), faction filter, search, hint lines, the column table (MiscTables).
local BIG = 1700000000
local THORIUM, ARGENT, HYDRAXIAN = 59, 529, 749

local function fresh(harness)
    local addon = harness.addon({ now = BIG })
    addon.Store.db.me = "Me-R"
    local R = addon.Reputation
    R.Put({ name = "Me-R", rev = BIG - 100, f = { [THORIUM] = { s = 6, v = 4200, m = 12000 }, [ARGENT] = { s = 5, v = 10, m = 6000 } } })
    R.Put({ name = "Anna-R", rev = BIG - 50, f = { [THORIUM] = { s = 6, v = 9000, m = 12000 } } })
    R.Put({ name = "Ben-R", rev = BIG - 10, f = { [THORIUM] = { s = 5, v = 100, m = 6000 }, [HYDRAXIAN] = { s = 7, v = 0, m = 21000 } } })
    return addon
end

local LOOKUPS = {
    factionName = function(id) return ({ [THORIUM] = "Thoriumbruderschaft" })[id] end,
    standingLabel = function(s) return ({ [6] = "Wohlwollend" })[s] end,
}

local function byKey(rows)
    local out = {}
    for _, row in ipairs(rows) do out[row.key] = row end
    return out
end

return {
    ["reputation rows: one row per member and faction, names from the client, English as fallback"] = function(harness)
        local addon = fresh(harness)
        local rows = byKey(addon.Model.BuildReputationRows({ me = "Me-R" }, LOOKUPS))
        local count = 0
        for _ in pairs(rows) do count = count + 1 end
        harness.equal(count, 5)
        local mine = rows["Me-R#" .. THORIUM]
        harness.equal(mine.name, "Thoriumbruderschaft"); harness.equal(mine.standingLabel, "Wohlwollend"); harness.truthy(mine.mine)
        harness.equal(mine.progressText, "4200/12000"); harness.equal(mine.updated, BIG - 100)
        harness.equal(rows["Me-R#" .. ARGENT].name, "Argent Dawn", "no client name: the hint data's English name")
        harness.equal(rows["Me-R#" .. ARGENT].standingLabel, "Friendly", "no client label: the addon's translation")
        harness.equal(rows["Anna-R#" .. THORIUM].mine, false)
    end,

    ["reputation rows: standing sorts by level, then progress inside it"] = function(harness)
        local addon = fresh(harness)
        local rows = addon.Model.BuildReputationRows({ me = "Me-R", faction = THORIUM }, LOOKUPS)
        local columnTable = addon.MiscTables.Table("reputation")
        columnTable.Sort(rows, { key = "standing", descending = true })
        harness.equal(rows[1].who, "Anna-R"); harness.equal(rows[2].who, "Me-R"); harness.equal(rows[3].who, "Ben-R")
        harness.truthy(rows[2].standingRank < 7, "progress never lifts a row into the next level")
        columnTable.Sort(rows, { key = "player", descending = false })
        harness.equal(rows[1].who, "Anna-R")
    end,

    ["reputation rows: the faction filter keeps one faction"] = function(harness)
        local addon = fresh(harness)
        local rows = addon.Model.BuildReputationRows({ faction = HYDRAXIAN }, LOOKUPS)
        harness.equal(#rows, 1); harness.equal(rows[1].who, "Ben-R")
        harness.equal(#addon.Model.BuildReputationRows({ faction = 424242 }, LOOKUPS), 0)
    end,

    ["reputation rows: search needs every word, matches faction (client and English name), player and standing"] = function(harness)
        local addon = fresh(harness)
        local function search(text) return #addon.Model.BuildReputationRows({ text = text }, LOOKUPS) end
        harness.equal(search(""), 5)
        harness.equal(search("thorium"), 3, "the English name matches in a German client")
        harness.equal(search("bruderschaft"), 3)
        harness.equal(search("thorium wohlwollend"), 2)
        harness.equal(search("anna wohlwollend"), 1)
        harness.equal(search("ben thorium"), 1)
        harness.equal(search("zzz"), 0)
    end,

    ["reputation rows (RF1): peer names are escaped, unlisted factions in the store are skipped"] = function(harness)
        local addon = fresh(harness)
        addon.Store.db.rep["X|r-R"] = { name = "X|r-R", rev = 1, f = { [THORIUM] = { s = 4, v = 0, m = 3000 }, [99999] = { s = 8, v = 0, m = 999 } } }
        local rows = addon.Model.BuildReputationRows({}, LOOKUPS)
        local found = 0
        for _, row in ipairs(rows) do
            if row.who == "X|r-R" then found = found + 1; harness.truthy(row.playerName:find("X||r", 1, true), "escaped") end
        end
        harness.equal(found, 1)
    end,

    ["reputation factions: the dropdown lists factions somebody has, by name"] = function(harness)
        local addon = fresh(harness)
        local choices = addon.Model.ReputationFactions(LOOKUPS)
        harness.equal(#choices, 3)
        harness.equal(choices[1].name, "Argent Dawn"); harness.equal(choices[2].name, "Hydraxian Waterlords")
        harness.equal(choices[3].id, THORIUM)
    end,

    ["hint lines: reached, next and later relative to the player's standing; language"] = function(harness)
        local addon = fresh(harness)
        local lines = addon.Model.FactionHintLines(HYDRAXIAN, 6, "enUS", LOOKUPS)
        harness.equal(#lines, 2)
        harness.equal(lines[1].state, "reached"); harness.equal(lines[2].state, "next")
        harness.equal(lines[1].label, "Wohlwollend")
        harness.truthy(lines[1].text:find("Quintessence", 1, true))
        local german = addon.Model.FactionHintLines(HYDRAXIAN, 4, "deDE", LOOKUPS)
        harness.equal(german[1].state, "next"); harness.equal(german[2].state, "later")
        harness.truthy(german[1].text:find("Quintessenz", 1, true))
        local unknown = addon.Model.FactionHintLines(HYDRAXIAN, nil, "enUS", LOOKUPS)
        harness.equal(unknown[1].state, "later")
    end,

    ["misc tables: reputation mode with its own columns, Updated hidden by default, standing sorts first"] = function(harness)
        local addon = fresh(harness)
        local MiscTables = addon.MiscTables
        local settings = {}
        MiscTables.SetMode(settings, "reputation")
        harness.equal(MiscTables.GetMode(settings), "reputation")
        harness.equal(MiscTables.ModeLabel("reputation"), "Reputation")
        local columnTable = MiscTables.Table("reputation")
        harness.equal(columnTable.ColumnShown(settings, "updated"), false)
        harness.equal(columnTable.ColumnShown(settings, "progress"), true)
        harness.equal(columnTable.GetSort(settings).key, "standing")
        harness.equal(columnTable.ColumnLabel("name"), "Faction")
    end,
}
