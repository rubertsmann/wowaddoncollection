-- Offline test runner:  luajit tests/run.lua   (run from the repo root)
-- Each tests/test_*.lua returns a table { ["test name"] = function(harness) ... end }.
-- `harness.addon()` gives a fresh addon table with the pure modules loaded; `harness.equal(actual, expected)` asserts
-- equality, `harness.truthy(value)` asserts a true value, `harness.character(...)` builds a character record.

---@param addon table
---@param path string
local function loadAddonFile(addon, path)
    local chunk, loadError = loadfile(path)
    assert(chunk, loadError)
    chunk("TalentShare", addon)
end

---@class TestHarness
---@field clock integer the server time GetServerTime returns (tests move it forward)
local Harness = {}

-- A fresh addon table with every pure module loaded, in TOC order, and an empty store.
---@param options? { now: integer }
---@return table addon
function Harness.addon(options)
    local addon = { PROTOCOL_MAJOR = 2, PROTOCOL_MINOR = 3, PROTOCOL = 2, PREFIX = "TShare", SlashCommands = {},
        Print = function() end }   -- same values as Core/Base/Init.lua (tests/test_hardening.lua pins them)
    Harness.clock = (options and options.now) or 1000
    GetServerTime = function() return Harness.clock end
    -- same order as the TOC (pure modules only)
    for _, path in ipairs({ "Core/Base/Utility.lua", "Core/Base/Log.lua", "Core/Debug/Trace.lua", "Core/Base/Locale.lua",
        "Locales/enUS.lua", "Locales/deDE.lua", "Core/Data/Store.lua", "Core/View/Names.lua", "Core/Data/Orders.lua",
        "Core/Data/Offers.lua", "Core/Play/Games.lua", "Core/Play/CoinFlip.lua", "Core/Play/Slots.lua", "Core/Net/Codec.lua", "Core/Net/Guard.lua", "Core/Net/Sync.lua", "Core/View/Model.lua",
        "Core/View/ItemText.lua", "Core/View/Notify.lua", "Core/Net/Communication.lua", "Core/Debug/Diagnostics.lua" }) do
        loadAddonFile(addon, path)
    end
    addon.Store.Init({})
    addon.Locale.Register("enUS")  -- (no-op re-register keeps tests independent of GetLocale)
    return addon
end

---@param actual any
---@param expected any
---@param message? string
function Harness.equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

---@param value any
---@param message? string
function Harness.truthy(value, message) if not value then error(message or "expected truthy", 2) end end

-- A level 60 mage character record with one Cooking profession that knows `recipeIDs`.
---@param playerName string
---@param revision integer
---@param recipeIDs? integer[]
---@param rank? integer
---@return CharacterRecord
function Harness.character(playerName, revision, recipeIDs, rank)
    local knownRecipes = {}
    for _, recipeID in ipairs(recipeIDs or {}) do knownRecipes[recipeID] = true end
    return { name = playerName, class = "MAGE", level = 60, rev = revision,
        professions = { Cooking = { name = "Cooking", rank = rank or 100, max = 300, recipes = knownRecipes } } }
end

-- real libraries for the codec tests
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")

local testFiles = {}
local listing = io.popen and io.popen('dir /b tests\\test_*.lua 2>nul || ls tests/test_*.lua')
for line in listing:lines() do
    local fileName = line:match("test_[%w_]+%.lua")
    if fileName then testFiles[#testFiles + 1] = "tests/" .. fileName end
end
listing:close()
table.sort(testFiles)

local passedCount, failedCount = 0, 0
for _, testFile in ipairs(testFiles) do
    local suite = dofile(testFile)
    local testNames = {}
    for testName in pairs(suite) do testNames[#testNames + 1] = testName end
    table.sort(testNames)
    for _, testName in ipairs(testNames) do
        local ok, errorMessage = pcall(suite[testName], Harness)
        if ok then passedCount = passedCount + 1
        else failedCount = failedCount + 1; print("FAIL " .. testFile .. " :: " .. testName .. "\n     " .. tostring(errorMessage)) end
    end
end
print(("%d passed, %d failed"):format(passedCount, failedCount))
os.exit(failedCount == 0 and 0 or 1)
