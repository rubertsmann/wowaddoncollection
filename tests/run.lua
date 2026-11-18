-- Offline test runner:  luajit tests/run.lua   (run from the repo root)
-- Each tests/test_*.lua returns { ["test name"] = function(harness) ... end }.
-- harness.library() reloads LibGuildSync from scratch (fresh shared state) and returns it; harness.equal / harness.truthy
-- assert; harness.clock is the server time GetServerTime returns.

dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")

local LIBRARY_FOLDER = "LibGuildSync/"
local MAJOR = "LibGuildSync-1.0"

---@class LibraryTestHarness
local Harness = { clock = 1000, LIBRARY_FOLDER = LIBRARY_FOLDER }

-- The library's files in LibGuildSync.xml order.
---@param folder? string
---@return string[]
function Harness.libraryFiles(folder)
    folder = folder or LIBRARY_FOLDER
    local handle = assert(io.open(folder .. "LibGuildSync.xml", "rb"))
    local xml = handle:read("*a"); handle:close()
    local files = {}
    for fileName in xml:gmatch('<Script%s+file="([^"]+)"') do files[#files + 1] = folder .. fileName end
    return files
end

-- Forget every loaded copy of the library (LibStub keeps them in two tables).
function Harness.unloadLibrary()
    LibStub.libs[MAJOR], LibStub.minors[MAJOR] = nil, nil
end

-- Runs the library's files; `transform(source, path)` may rewrite a file first (to fake another copy's MINOR).
---@param transform? fun(source: string, path: string): string
function Harness.loadLibrary(transform)
    for _, path in ipairs(Harness.libraryFiles()) do
        local handle = assert(io.open(path, "rb"))
        local source = handle:read("*a"); handle:close()
        if transform then source = transform(source, path) end
        local chunk = assert(loadstring(source, "@" .. path))
        chunk()
    end
end

-- A fresh library (shared state reset) and a clock under test control.
---@param options? { now: integer }
---@return table lib
function Harness.library(options)
    Harness.clock = (options and options.now) or 1000
    GetServerTime = function() return Harness.clock end
    Harness.unloadLibrary()
    Harness.loadLibrary()
    return LibStub(MAJOR)
end

-- A Log + Trace pair writing into `db` (db.debug, db.trace).
---@param lib table
---@param db? table
---@return table log, table trace, table db
function Harness.logAndTrace(lib, db)
    db = db or { debug = {}, trace = {} }
    local log = lib.Log.New({ entries = function() return db.debug end, title = "Test", isDevelopment = false })
    local trace = lib.Trace.New({ entries = function() return db.trace end, log = log })
    return log, trace, db
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
