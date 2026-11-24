-- Craft cooldowns view: tiles per craft, crafter states, the whisper target, the expanded view, time formats.
local BIG = 1700000000
local DAY = 86400

local function fresh(harness)
    local addon = harness.addon({ now = BIG })
    addon.Store.db.me = "Me-R"
    return addon
end

local function alchemist(harness, addon, name)
    addon.Store.PutCharacter(harness.character(name, 1, { 17187 }))
end

local function tileOf(tiles, key)
    for _, tile in ipairs(tiles) do if tile.key == key then return tile end end
end

local function onlineSet(names)
    return { isOnline = function(name) return names[name] == true end }
end

return {
    ["cooldown tiles: one tile per craft, in data order, also without crafters"] = function(harness)
        local addon = fresh(harness)
        local tiles = addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" })
        harness.equal(#tiles, #addon.CraftCooldowns.GROUPS)
        for index, group in ipairs(addon.CraftCooldowns.GROUPS) do
            harness.equal(tiles[index].key, group.key)
            harness.equal(tiles[index].state, "none"); harness.equal(tiles[index].best, nil); harness.equal(#tiles[index].crafters, 0)
        end
        harness.equal(tileOf(tiles, "transmute").name, "Transmute")
    end,

    ["cooldown tiles: crafters from recipes and from records; states ready, cooling, unknown"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        alchemist(harness, addon, "Ready-R"); alchemist(harness, addon, "Cool-R"); alchemist(harness, addon, "Quiet-R")
        C.Put({ name = "Ready-R", rev = 1, c = { transmute = 0 }, e = {} })
        C.Put({ name = "Cool-R", rev = 1, c = { transmute = BIG + 3600 }, e = { transmute = true } })
        C.Put({ name = "Salt-R", rev = 1, c = { saltshaker = BIG - 10 }, e = {} })   -- holds the Salt Shaker, no recipe needed
        local tiles = addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" },
            onlineSet({ ["Ready-R"] = true, ["Cool-R"] = true, ["Quiet-R"] = true, ["Salt-R"] = true }))
        local transmute = tileOf(tiles, "transmute")
        harness.equal(#transmute.crafters, 3)
        harness.equal(transmute.crafters[1].who, "Ready-R"); harness.equal(transmute.crafters[1].state, "ready")
        harness.equal(transmute.crafters[2].who, "Quiet-R"); harness.equal(transmute.crafters[2].state, "unknown")
        harness.equal(transmute.crafters[3].who, "Cool-R"); harness.equal(transmute.crafters[3].state, "cooling")
        harness.equal(transmute.crafters[3].remaining, 3600); harness.equal(transmute.crafters[3].estimated, true)
        harness.equal(transmute.state, "ready"); harness.equal(transmute.readyCount, 1); harness.equal(transmute.best.who, "Ready-R")
        local salt = tileOf(tiles, "saltshaker")
        harness.equal(#salt.crafters, 1); harness.equal(salt.state, "ready", "a passed ready time is ready")
        harness.equal(tileOf(tiles, "mooncloth").state, "none")
    end,

    ["cooldown tiles: whisper target is online and never me; offline crafters come last"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        alchemist(harness, addon, "Me-R"); alchemist(harness, addon, "Away-R"); alchemist(harness, addon, "Busy-R")
        C.Put({ name = "Me-R", rev = 1, c = { transmute = 0 }, e = {} })
        C.Put({ name = "Away-R", rev = 1, c = { transmute = 0 }, e = {} })
        C.Put({ name = "Busy-R", rev = 1, c = { transmute = BIG + 7200 }, e = {} })
        local tiles = addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" }, onlineSet({ ["Busy-R"] = true }))
        local transmute = tileOf(tiles, "transmute")
        harness.equal(transmute.crafters[1].who, "Me-R", "I am online and ready")
        harness.equal(transmute.crafters[#transmute.crafters].who, "Away-R", "offline last")
        harness.equal(transmute.best.who, "Busy-R", "the only other online crafter, even while cooling")
        harness.truthy(transmute.mine)
        local nobody = addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" }, onlineSet({}))
        harness.equal(tileOf(nobody, "transmute").best, nil, "nobody else online: no whisper target")
    end,

    ["cooldown tiles: all cooling -> the soonest online cooldown is shown, with its sweep length"] = function(harness)
        local addon = fresh(harness)
        local C = addon.CraftCooldowns
        alchemist(harness, addon, "Long-R"); alchemist(harness, addon, "Short-R"); alchemist(harness, addon, "Off-R")
        C.Put({ name = "Long-R", rev = 1, c = { transmute = BIG + 20000 }, e = {} })
        C.Put({ name = "Short-R", rev = 1, c = { transmute = BIG + 5000 }, e = {} })
        C.Put({ name = "Off-R", rev = 1, c = { transmute = BIG + 100 }, e = {} })
        local tiles = addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" }, onlineSet({ ["Long-R"] = true, ["Short-R"] = true }))
        local transmute = tileOf(tiles, "transmute")
        harness.equal(transmute.state, "cooling"); harness.equal(transmute.remaining, 5000, "the online one, not the offline 100 s")
        harness.equal(transmute.duration, DAY); harness.equal(transmute.best.who, "Short-R")
        local allOffline = tileOf(addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" }, onlineSet({})), "transmute")
        harness.equal(allOffline.remaining, 100, "with nobody online the soonest of all")
    end,

    ["cooldown tiles: peer names are escaped, the search matches craft and crafter"] = function(harness)
        local addon = fresh(harness)
        alchemist(harness, addon, "Ev|cffil-R")
        local tiles = addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" })
        local crafter = tileOf(tiles, "transmute").crafters[1]
        harness.truthy(crafter.playerName:find("||c", 1, true) and not crafter.playerName:gsub("||", ""):find("|", 1, true),
            "escaped: " .. crafter.playerName)
        local found = addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R", text = "transm" })
        harness.equal(#found, 1); harness.equal(found[1].key, "transmute")
        harness.equal(#addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R", text = "zzzz" }), 0)
    end,

    ["cooldown tiles: the expanded view has one tile per crafter"] = function(harness)
        local addon = fresh(harness)
        alchemist(harness, addon, "A-R"); alchemist(harness, addon, "B-R")
        addon.CraftCooldowns.Put({ name = "A-R", rev = 1, c = { transmute = BIG + 60 }, e = {} })
        local expanded = addon.Model.ExpandCooldownTiles(addon.Model.BuildCooldownTiles({ now = BIG, me = "Me-R" }, onlineSet({ ["A-R"] = true })))
        harness.equal(#expanded, 2)
        harness.equal(expanded[1].key, "transmute#A-R"); harness.equal(expanded[1].state, "cooling"); harness.equal(expanded[1].best.who, "A-R")
        harness.equal(expanded[2].state, "unknown"); harness.equal(expanded[2].best, nil, "offline")
    end,

    ["cooldown formats: short like an action button, long for the tooltip"] = function(harness)
        local addon = fresh(harness)
        local M = addon.Model
        harness.equal(M.FormatCooldownShort(2 * DAY + 5), "2d"); harness.equal(M.FormatCooldownShort(5 * 3600 + 1), "5h")
        harness.equal(M.FormatCooldownShort(61), "2m"); harness.equal(M.FormatCooldownShort(40.2), "41s"); harness.equal(M.FormatCooldownShort(-3), "0s")
        harness.equal(M.FormatCooldownLong(2 * DAY + 4 * 3600 + 59), "2d 4h"); harness.equal(M.FormatCooldownLong(3 * 3600 + 12 * 60), "3h 12m")
        harness.equal(M.FormatCooldownLong(12 * 60 + 30), "12:30"); harness.equal(M.FormatCooldownLong(-1), "0:00")
    end,
}
