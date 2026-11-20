-- Offline test runner:  luajit tests/run.lua   (run from the repo root)
-- Each tests/test_*.lua returns a table { ["test name"] = function(harness) ... end }.
-- `harness.addon()` gives a fresh addon table with the pure modules loaded (and a fresh LibGuildSync, whose shared state
-- would otherwise leak between tests); `harness.equal(actual, expected)` / `harness.truthy(value)` assert.

dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")

-- LibGuildSync-1.0 (embedded, Libs/LibGuildSync = a link to ../libguildsync/LibGuildSync in a working copy)
local LIBRARY_FOLDER, LIBRARY_MAJOR = "Libs/LibGuildSync/", "LibGuildSync-1.0"
---@return string[]
local function libraryFiles()
    local handle = assert(io.open(LIBRARY_FOLDER .. "LibGuildSync.xml", "rb"),
        "Libs/LibGuildSync is missing: run powershell tools/deploy.ps1 (it links ../libguildsync/LibGuildSync)")
    local xml = handle:read("*a"); handle:close()
    local files = {}
    for fileName in xml:gmatch('<Script%s+file="([^"]+)"') do files[#files + 1] = LIBRARY_FOLDER .. fileName end
    return files
end
local function loadFreshLibrary()
    LibStub.libs[LIBRARY_MAJOR], LibStub.minors[LIBRARY_MAJOR] = nil, nil
    for _, path in ipairs(libraryFiles()) do dofile(path) end
end
loadFreshLibrary()   -- for test files that load addon files themselves (test_load)

---@param addon table
---@param path string
local function loadAddonFile(addon, path)
    local chunk, loadError = loadfile(path)
    assert(chunk, loadError)
    chunk("GuildGames", addon)
end

---@class TestHarness
---@field clock integer the server time GetServerTime returns (tests move it forward)
local Harness = {}

-- the pure modules, in TOC order
Harness.PURE_FILES = { "Core/Base/Utility.lua", "Core/Base/Log.lua", "Core/Debug/Trace.lua", "Core/Base/Locale.lua",
    "Locales/enUS.lua", "Locales/deDE.lua", "Core/Net/Codec.lua", "Core/Net/Guard.lua", "Core/Data/Store.lua",
    "Core/Data/Games.lua", "Core/Minigames/CoinFlip.lua", "Core/Minigames/Slots.lua", "Core/Minigames/Survivor.lua",
    "Core/Data/Wallet.lua", "Core/Minigames/AzeCaught.lua", "Core/View/Model.lua", "Core/Net/Sync.lua",
    "Core/Net/Communication.lua" }

-- A fresh addon table with every pure module loaded and an empty store.
---@param options? { now: integer }
---@return table addon
function Harness.addon(options)
    local addon = { PROTOCOL_MAJOR = 1, PROTOCOL_MINOR = 1, PROTOCOL = 1, PREFIX = "GGames", SlashCommands = {},
        Print = function() end }   -- same values as Core/Base/Init.lua (tests/test_load.lua pins them)
    Harness.clock = (options and options.now) or 1000
    GetServerTime = function() return Harness.clock end
    loadFreshLibrary()
    for _, path in ipairs(Harness.PURE_FILES) do loadAddonFile(addon, path) end
    addon.Store.Init({})
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

local testFiles, seenFiles = {}, {}
local listing = io.popen('dir /b tests\test_*.lua 2>nul || ls tests/test_*.lua')
for line in listing:lines() do
    local fileName = line:match("test_[%w_]+%.lua")
    if fileName and not seenFiles[fileName] then seenFiles[fileName] = true; testFiles[#testFiles + 1] = "tests/" .. fileName end
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
