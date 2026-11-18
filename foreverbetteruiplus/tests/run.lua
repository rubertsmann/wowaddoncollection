-- Offline tests for the pure parts:  luajit tests/run.lua   (from the repo root)
local addon = {}
for _, path in ipairs({ "Logic.lua", "Elements.lua" }) do
    local chunk = assert(loadfile(path))
    chunk("ForeverBetterUIPlus", addon)
end
local Logic, Elements = addon.Logic, addon.Elements

local function near(actual, expected, label)
    assert(math.abs(actual - expected) < 1e-6, string.format("%s: expected %s, got %s", label or "value", expected, actual))
end

local tests = {}

tests["new settings get defaults and keep saved values"] = function()
    local db = Logic.NewSettings()
    near(db.global, Logic.DEFAULT_GLOBAL)
    assert(type(db.elements) == "table" and db.combatFull == false)
    db = Logic.NewSettings({ global = 0.3, elements = { minimap = 0.1 }, combatFull = true })
    near(db.global, 0.3); near(db.elements.minimap, 0.1); assert(db.combatFull)
    db = Logic.NewSettings({ global = 7, elements = "broken" })
    near(db.global, 1, "clamped"); assert(type(db.elements) == "table")
end

tests["base alpha: global, custom and off"] = function()
    local db = Logic.NewSettings({ global = 0.5, elements = { a = 0.2, b = "off", c = "global" } })
    near(Logic.BaseAlpha(db, "a"), 0.2)
    assert(Logic.BaseAlpha(db, "b") == nil)
    near(Logic.BaseAlpha(db, "c"), 0.5)
    near(Logic.BaseAlpha(db, "unknown"), 0.5)
    assert(Logic.ModeName(db, "a") == "custom" and Logic.ModeName(db, "b") == "off" and Logic.ModeName(db, "c") == "global")
end

tests["hover, edit mode and combat show the element fully"] = function()
    near(Logic.TargetAlpha(0.3, {}), 0.3)
    near(Logic.TargetAlpha(0.3, { hovered = true }), 1)
    near(Logic.TargetAlpha(0.3, { editMode = true }), 1)
    near(Logic.TargetAlpha(0.3, { inCombat = true }), 0.3, "combat without the option")
    near(Logic.TargetAlpha(0.3, { inCombat = true, combatFull = true }), 1)
end

tests["combat visibility per element overrides the global switch"] = function()
    local db = Logic.NewSettings({ combatFull = false, combat = { target = true, minimap = false } })
    assert(Logic.CombatFull(db, "target") == true)
    assert(Logic.CombatFull(db, "minimap") == false)
    assert(Logic.CombatFull(db, "player") == false, "falls back to global")
    db.combatFull = true
    assert(Logic.CombatFull(db, "player") == true and Logic.CombatFull(db, "minimap") == false)
    assert(Logic.CombatModeName(db, "target") == "full" and Logic.CombatModeName(db, "minimap") == "faded"
        and Logic.CombatModeName(db, "player") == "global")
    local value, valid = Logic.ParseCombatMode("FULL"); assert(value == true and valid)
    value, valid = Logic.ParseCombatMode("faded"); assert(value == false and valid)
    value, valid = Logic.ParseCombatMode("global"); assert(value == nil and valid)
    value, valid = Logic.ParseCombatMode("x"); assert(not valid)
    assert(type(Logic.NewSettings({ combat = "broken" }).combat) == "table")
end

tests["fade steps towards the target and never overshoots"] = function()
    near(Logic.Step(0.2, 1, 0.1, 0.2), 0.7)
    near(Logic.Step(0.9, 1, 0.1, 0.2), 1)
    near(Logic.Step(1, 0.4, 0.1, 0.2), 0.5)
    near(Logic.Step(0.45, 0.4, 0.1, 0.2), 0.4)
    near(Logic.Step(0.2, 1, 0.01, 0), 1, "no fade time jumps")
end

tests["opacity parsing accepts percent, fractions and modes"] = function()
    near(Logic.ParseOpacity("40"), 0.4)
    near(Logic.ParseOpacity("40%"), 0.4)
    near(Logic.ParseOpacity("0.25"), 0.25)
    near(Logic.ParseOpacity("150"), 1)
    assert(Logic.ParseOpacity("GLOBAL") == "global" and Logic.ParseOpacity("off") == "off")
    assert(Logic.ParseOpacity("abc") == nil and Logic.ParseOpacity(nil) == nil)
    assert(Logic.Percent(0.404) == "40%")
end

tests["element keys are unique and every element names a frame"] = function()
    local seen = {}
    for _, element in ipairs(Elements.list) do
        assert(not seen[element.key], "duplicate " .. element.key)
        seen[element.key] = true
        assert(type(element.label) == "string" and #element.frames > 0, element.key)
    end
    assert(Elements.ByKey("minimap") and Elements.ByKey("minimap").label == "Minimap")
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failed = 0
for _, name in ipairs(names) do
    local ok, problem = pcall(tests[name])
    print((ok and "ok    " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(problem))))
    if not ok then failed = failed + 1 end
end
print(string.format("%d tests, %d failed", #names, failed))
os.exit(failed == 0 and 0 or 1)
