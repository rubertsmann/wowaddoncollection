-- RecipeCheck: reading a recipe tooltip and loot chat lines with the client's own format strings (no external data).
local EN = {
    minSkill = "Requires %s (%d)", known = "Already known", bindOnPickup = "Binds when picked up",
    loot = {
        self = { "You receive loot: %sx%d.", "You receive loot: %s." },
        pushed = { "You receive item: %sx%d.", "You receive item: %s." },
        other = { "%s receives loot: %sx%d.", "%s receives loot: %s." },
    },
}
local DE = { minSkill = "Benötigt %1$s (%2$d)", known = "Bereits bekannt", bindOnPickup = "Wird beim Aufheben gebunden",
    loot = { self = { "Ihr erhaltet Beute: %s." }, pushed = {}, other = { "%1$s erhält Beute: %2$s." } } }

local RED, WHITE = { 1, 0.125, 0.125 }, { 1, 1, 1 }
local function line(text, color)
    color = color or WHITE
    return { text = text, r = color[1], g = color[2], b = color[3] }
end
local LINK = "|cff1eff00|Hitem:14468:0:0:0|h[Pattern: Runecloth Bag]|h|r"

-- a pattern tooltip in the order Forever shows it: name, the item it makes (which can carry its own "Requires" line),
-- the teach line, the reagents, then the recipe's own requirement
local function patternTooltip(requiredColor, extra)
    local lines = { line("Pattern: Runecloth Bag"), line(" "), line("Runecloth Bag"), line("Requires Engineering (300)", RED),
        line("Requires Level 50"), line("Use: Teaches you how to sew a Runecloth Bag."), line("Runecloth (5), Rugged Leather"),
        line("Requires Tailoring (260)", requiredColor), line(" ") }
    for _, text in ipairs(extra or {}) do table.insert(lines, 2, line(text)) end
    return lines
end

local function professions(rank) return { Tailoring = { name = "Tailoring", rank = rank, max = 300, recipes = {} } } end

return {
    ["recipe check: patterns from client format strings, positional arguments reordered"] = function(harness)
        local addon = harness.addon()
        local RecipeCheck = addon.RecipeCheck
        harness.equal(RecipeCheck.PatternFromFormat("Requires %s (%d)"), "^Requires (.+) %((%d+)%)$")
        harness.equal(RecipeCheck.PatternFromFormat("no conversion"), nil)
        harness.equal(RecipeCheck.PatternFromFormat(nil), nil)
        local arguments = RecipeCheck.Match("%2$s erhält Beute: %1$s.", "Anna erhält Beute: [Muster].")
        harness.equal(arguments[2], "Anna"); harness.equal(arguments[1], "[Muster]")
        harness.equal(RecipeCheck.Match("100%% sure %s", "100% sure yes")[1], "yes")
        harness.equal(RecipeCheck.Match("Requires %s (%d)", "Requires Level 40"), nil, "a level line is not a skill line")
    end,

    ["recipe check (RF1): only the last Requires line counts, colour and flags read"] = function(harness)
        local RecipeCheck = harness.addon().RecipeCheck
        local reading = RecipeCheck.ReadTooltip(patternTooltip(WHITE), EN)
        harness.equal(reading.profession, "Tailoring"); harness.equal(reading.required, 260)
        harness.equal(reading.requiredRed, false, "the created item's red Engineering line is ignored")
        harness.equal(reading.known, false); harness.equal(reading.bindOnPickup, false)
        local known = RecipeCheck.ReadTooltip(patternTooltip(RED, { "Already known", "Binds when picked up" }), EN)
        harness.equal(known.known, true); harness.equal(known.bindOnPickup, true); harness.equal(known.requiredRed, true)
        harness.equal(RecipeCheck.ReadTooltip({ "Requires Tailoring (75)" }, EN).requiredRed, nil, "plain text: colour unknown")
        harness.equal(RecipeCheck.ReadTooltip({}, EN), nil)
        harness.equal(RecipeCheck.ReadTooltip(nil, EN), nil)
    end,

    ["recipe check (RF2): German client strings with positional arguments"] = function(harness)
        local RecipeCheck = harness.addon().RecipeCheck
        local reading = RecipeCheck.ReadTooltip({ line("Muster: Runenstofftasche"), line("Benötigt Schneiderei (260)", RED),
            line("Bereits bekannt") }, DE)
        harness.equal(reading.profession, "Schneiderei"); harness.equal(reading.required, 260); harness.equal(reading.known, true)
        local decision = RecipeCheck.Decide(reading, { ["197"] = { name = "Schneiderei", rank = 280 } })
        harness.equal(decision.status, "known")
    end,

    ["recipe check: a real Forever tooltip (deDE cooking recipe, item 274972, read in game)"] = function(harness)
        local RecipeCheck = harness.addon().RecipeCheck
        local GOLD, GREEN = { 1, 0.82, 0 }, { 0, 1, 0 }
        local lines = { line("Rezept: Salziger Meeresfrüchteeintopf"), line("Wird beim Aufheben gebunden"), line(" ", GOLD),
            line("\nSalziger Meeresfrüchteeintopf"), line("Benutzen: Stellt im Verlauf von 27 Sek. 841 Punkt(e) Gesundheit wieder her.", GREEN),
            line("Benötigt Stufe 25"), line("Benutzen: Lehrt Euch, wie man einen salzigen Meeresfrüchteeintopf zubereitet."),
            line("Murlocauge (2), Zartes Krebsfleisch, Scharfe Gewürze"), line("Benötigt Kochkunst (200)", { 1, 0.13, 0.13 }),
            line(" ", GOLD) }
        local reading = RecipeCheck.ReadTooltip(lines, DE)
        harness.equal(reading.profession, "Kochkunst"); harness.equal(reading.required, 200)
        harness.equal(reading.requiredRed, true); harness.equal(reading.bindOnPickup, true); harness.equal(reading.known, false)
        local decision = RecipeCheck.Decide(reading, { Kochkunst = { name = "Kochkunst", rank = 150, max = 150 } })
        harness.equal(decision.status, "low"); harness.equal(decision.mismatch, false)
    end,

    ["recipe check: decision from my stored skill, colour cross-check flags a mismatch"] = function(harness)
        local RecipeCheck = harness.addon().RecipeCheck
        local white = RecipeCheck.ReadTooltip(patternTooltip(WHITE), EN)
        local red = RecipeCheck.ReadTooltip(patternTooltip(RED), EN)
        local learnable = RecipeCheck.Decide(white, professions(280))
        harness.equal(learnable.status, "learnable"); harness.equal(learnable.rank, 280); harness.equal(learnable.mismatch, false)
        local exactly = RecipeCheck.Decide(white, professions(260))
        harness.equal(exactly.status, "learnable", "skill equal to the requirement is enough")
        local low = RecipeCheck.Decide(red, professions(240))
        harness.equal(low.status, "low"); harness.equal(low.mismatch, false)
        harness.equal(RecipeCheck.Decide(red, professions(280)).mismatch, true, "red but my stored skill is enough: stale skill?")
        harness.equal(RecipeCheck.Decide(white, professions(100)).mismatch, true)
        harness.equal(RecipeCheck.Decide(red, { Mining = { name = "Mining", rank = 300 } }).status, "noProfession")
        harness.equal(RecipeCheck.Decide(red, nil).status, "noProfession")
        harness.equal(RecipeCheck.Decide(white, { tailoring = { rank = 270 } }).status, "learnable", "matched by key")
        harness.equal(RecipeCheck.Decide(nil, professions(300)).status, "unreadable")
        harness.equal(RecipeCheck.Decide({ lines = 3, known = false }, professions(300)).status, "unreadable", "no Requires line")
    end,

    ["recipe check (RF4): my loot, pushed items and other players' loot are told apart"] = function(harness)
        local RecipeCheck = harness.addon().RecipeCheck
        local mine = RecipeCheck.ParseLoot("You receive loot: " .. LINK .. ".", EN.loot)
        harness.equal(mine.kind, "self"); harness.equal(mine.itemID, 14468); harness.equal(mine.count, 1)
        local two = RecipeCheck.ParseLoot("You receive loot: " .. LINK .. "x2.", EN.loot)
        harness.equal(two.kind, "self"); harness.equal(two.count, 2); harness.equal(two.link, LINK)
        harness.equal(RecipeCheck.ParseLoot("You receive item: " .. LINK .. ".", EN.loot).kind, "pushed")
        local other = RecipeCheck.ParseLoot("Anna receives loot: " .. LINK .. ".", EN.loot)
        harness.equal(other.kind, "other"); harness.equal(other.itemID, 14468)
        local german = RecipeCheck.ParseLoot("Anna erhält Beute: " .. LINK .. ".", DE.loot)
        harness.equal(german.kind, "other"); harness.equal(german.itemID, 14468)
        harness.equal(RecipeCheck.ParseLoot("You receive loot: 3 Silver.", EN.loot), nil, "no item link")
        harness.equal(RecipeCheck.ParseLoot("hello", EN.loot), nil)
        harness.equal(RecipeCheck.ParseLoot(nil, EN.loot), nil)
        harness.equal(RecipeCheck.ParseLoot("You receive loot: " .. LINK .. ".", nil), nil)
    end,
    ["recipe check api: client strings without the MULTIPLE forms, tooltip lines with colours, unloaded item"] = function(harness)
        local names = { "ITEM_MIN_SKILL", "ITEM_SPELL_KNOWN", "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM", "LOOT_ITEM_MULTIPLE", "C_TooltipInfo",
            "GetItemInfo", "C_Item" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = _G[name]; _G[name] = nil end
        local ok, err = pcall(function()
            local addon = harness.addon()
            assert(loadfile("Core/Game/Api.lua"))("ProfessionShare", addon)
            ITEM_MIN_SKILL, LOOT_ITEM_SELF = "Requires %s (%d)", "You receive loot: %s."
            local strings = addon.Api.RecipeCheckStrings()
            harness.equal(strings.minSkill, "Requires %s (%d)")
            harness.equal(#strings.loot.self, 1, "the single form is kept when the MULTIPLE form is missing")
            harness.equal(#strings.loot.other, 0)
            harness.equal(addon.Api.ItemTooltipLinesWithColor(14468), nil, "no item data: nil, no error")
            GetItemInfo = function(itemID) return itemID == 14468 and "Pattern: Runecloth Bag" or nil end
            C_TooltipInfo = { GetItemByID = function() return { lines = {
                { leftText = "Pattern: Runecloth Bag", leftColor = { r = 1, g = 1, b = 1 } },
                { leftText = "Requires Tailoring (260)", leftColor = { GetRGB = function() return 1, 0.125, 0.125 end } } } } end }
            local lines = addon.Api.ItemTooltipLinesWithColor(14468)
            harness.equal(#lines, 2); harness.equal(lines[2].g, 0.125)
            local reading = addon.RecipeCheck.ReadTooltip(lines, strings)
            harness.equal(reading.required, 260); harness.equal(reading.requiredRed, true)
            harness.equal(addon.Api.ItemTooltipLinesWithColor("14468"), nil)
        end)
        for _, name in ipairs(names) do _G[name] = saved[name] end
        if not ok then error(err, 0) end
    end,
}
