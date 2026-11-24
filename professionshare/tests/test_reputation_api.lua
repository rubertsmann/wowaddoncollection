-- Api.ScanReputation against stubbed WoW globals: met / unmet factions, the two client APIs, missing or erroring APIs.
local GLOBALS = { "GetFactionInfoByID", "GetFactionInfo", "GetNumFactions", "C_Reputation", "FACTION_STANDING_LABEL6",
    "UnitFactionGroup" }

local function withGlobals(harness, setup, fn)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k]; _G[k] = nil end
    local ok, err = pcall(function()
        local addon = harness.addon()
        assert(loadfile("Core/Game/Api.lua"))("ProfessionShare", addon)
        setup()
        fn(addon)
    end)
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

local THORIUM, ARGENT, TIMBERMAW, GADGETZAN, STORMPIKE, ORGRIMMAR, WINTERSABER = 59, 529, 576, 369, 730, 76, 589

-- faction id -> name, standing, barMin, barMax, barValue (classic signature; factionID is the 14th value)
local FACTIONS = {
    [THORIUM] = { "Thorium Brotherhood", 6, 9000, 21000, 13200 },   -- Honored 4200/12000, in the shown list
    [ARGENT] = { "Argent Dawn", 4, 0, 3000, 0 },                     -- Neutral 0, in the shown list: met
    [TIMBERMAW] = { "Timbermaw Hold", 4, 0, 3000, 0 },               -- Neutral 0, not listed: never met
    [GADGETZAN] = { "Gadgetzan", 5, 3000, 9000, 3500 },              -- Friendly, under a collapsed header: met
    [STORMPIKE] = { "Stormpike Guard", 1, -42000, -6000, -42000 },   -- Alliance only: a Horde client says Hated 0/36000
    [ORGRIMMAR] = { "Orgrimmar", 6, 9000, 21000, 12388 },            -- Horde city, Honored
    [WINTERSABER] = { "Wintersaber Trainers", 2, -6000, -3000, -3500 }, -- Alliance only, not Hated 0: still skipped by side
}
local SHOWN = { THORIUM, ARGENT }

local function classicClient()
    GetFactionInfoByID = function(id)
        local f = FACTIONS[id]
        if not f then return nil end
        return f[1], "", f[2], f[3], f[4], f[5]
    end
    GetNumFactions = function() return #SHOWN end
    GetFactionInfo = function(index)
        local id = SHOWN[index]
        local f = FACTIONS[id]
        return f[1], "", f[2], f[3], f[4], f[5], false, false, false, false, true, false, false, id
    end
end

return {
    ["reputation api: standings of met factions (listed or not untouched), unmet ones left out"] = function(harness)
        withGlobals(harness, classicClient, function(addon)
            local scan = addon.Api.ScanReputation()
            harness.truthy(scan)
            harness.equal(scan[THORIUM].s, 6); harness.equal(scan[THORIUM].v, 4200); harness.equal(scan[THORIUM].m, 12000)
            harness.equal(scan[ARGENT].s, 4, "listed: met even at Neutral 0")
            harness.equal(scan[TIMBERMAW], nil, "never met")
            harness.equal(scan[GADGETZAN].v, 500, "met under a collapsed header")
            harness.equal(addon.Api.reputationStatistics.listed, 2); harness.equal(addon.Api.reputationStatistics.met, 5, "Thorium, Argent, Gadgetzan, Orgrimmar, Wintersaber (no side known)")
            harness.truthy(addon.Reputation.Update("Me-R", scan, 1000), "the scan feeds the record")
            harness.truthy(addon.Reputation.Sanitize(addon.Reputation.Get("Me-R")))
        end)
    end,

    ["reputation api: the C_Reputation table API of newer clients works too"] = function(harness)
        withGlobals(harness, function()
            C_Reputation = {
                GetFactionDataByID = function(id)
                    if id ~= THORIUM then return nil end
                    return { name = "Thoriumbruderschaft", reaction = 7, currentReactionThreshold = 21000,
                        nextReactionThreshold = 42000, currentStanding = 22000, factionID = id }
                end,
                GetNumFactions = function() return 1 end,
                GetFactionDataByIndex = function() return { factionID = THORIUM } end,
            }
        end, function(addon)
            local scan = addon.Api.ScanReputation()
            harness.equal(scan[THORIUM].s, 7); harness.equal(scan[THORIUM].v, 1000); harness.equal(scan[THORIUM].m, 21000)
            harness.equal(addon.Api.FactionName(THORIUM), "Thoriumbruderschaft")
        end)
    end,

    ["reputation api (RF4): no API or an erroring API -> nil (the record stays), never an error"] = function(harness)
        withGlobals(harness, function() end, function(addon)
            harness.equal(addon.Api.ScanReputation(), nil)
            harness.equal(addon.Api.FactionName(THORIUM), nil)
            GetFactionInfoByID = function() error("boom") end
            GetNumFactions = function() error("boom") end
            harness.equal(addon.Api.ScanReputation(), nil)
            harness.equal(addon.Api.reputationStatistics.api, false)
        end)
    end,

    ["reputation api: standing label from the game, nil when the client has none"] = function(harness)
        withGlobals(harness, function() FACTION_STANDING_LABEL6 = "Wohlwollend" end, function(addon)
            harness.equal(addon.Api.StandingLabel(6), "Wohlwollend")
            harness.equal(addon.Api.StandingLabel(2), nil)
        end)
    end,

    ["reputation api: factions of the other side are skipped, Hated 0 counts as never met"] = function(harness)
        withGlobals(harness, function() classicClient(); UnitFactionGroup = function() return "Horde", "Horde" end end, function(addon)
            local scan = addon.Api.ScanReputation()
            harness.equal(scan[STORMPIKE], nil, "Alliance battleground faction on a Horde client")
            harness.equal(scan[WINTERSABER], nil, "Alliance-only faction skipped by its side")
            harness.equal(scan[ORGRIMMAR].s, 6, "own side kept")
        end)
        withGlobals(harness, function() classicClient() end, function(addon)
            local scan = addon.Api.ScanReputation()
            harness.equal(scan[STORMPIKE], nil, "no side known: Hated 0 still counts as never met")
            harness.equal(scan[WINTERSABER].s, 2, "no side known: a touched standing is kept")
        end)
    end,
}
