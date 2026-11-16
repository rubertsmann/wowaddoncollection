-- Offline test runner:  luajit tests/run.lua   (run from the repo root)
-- Each tests/test_*.lua returns a table { ["test name"] = function(h) ... end }.
-- `h.ns()` gives a fresh namespace with the pure modules loaded; `h.eq(a, b)` asserts equality.

local function loadAddonFile(ns, path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("TalentShare", ns)
end

local H = {}

function H.ns(opts)
    local ns = { PROTO_MAJOR = 2, PROTO_MINOR = 0, PROTOCOL = 2, PREFIX = "TShare", Slash = {},
        Print = function() end }   -- same values as Core/Init.lua (tests/test_hardening.lua pins them)
    local now = (opts and opts.now) or 1000
    H.clock = now
    GetServerTime = function() return H.clock end
    -- same order as the TOC (pure modules only)
    for _, path in ipairs({ "Core/Util.lua", "Core/Locale.lua", "Locales/enUS.lua", "Locales/deDE.lua", "Core/Store.lua",
        "Core/Names.lua", "Core/Orders.lua", "Core/Codec.lua", "Core/Guard.lua", "Core/Sync.lua", "Core/Model.lua", "Core/Comm.lua" }) do
        loadAddonFile(ns, path)
    end
    ns.Store.Init({})
    ns.Locale.Register("enUS")  -- (no-op re-register keeps tests independent of GetLocale)
    return ns
end

function H.eq(a, b, msg)
    if a ~= b then error((msg or "values differ") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

function H.truthy(v, msg) if not v then error(msg or "expected truthy", 2) end end

function H.char(name, rev, recipes, rank)
    local set = {}
    for _, id in ipairs(recipes or {}) do set[id] = true end
    return { name = name, class = "MAGE", level = 60, rev = rev,
        professions = { Cooking = { name = "Cooking", rank = rank or 100, max = 300, recipes = set } } }
end

-- real libraries for the codec tests
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")

local files = {}
local p = io.popen and io.popen('dir /b tests\\test_*.lua 2>nul || ls tests/test_*.lua')
for line in p:lines() do
    local name = line:match("test_[%w_]+%.lua")
    if name then files[#files + 1] = "tests/" .. name end
end
p:close()
table.sort(files)

local passed, failed = 0, 0
for _, file in ipairs(files) do
    local suite = dofile(file)
    local names = {}
    for n in pairs(suite) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local ok, err = pcall(suite[n], H)
        if ok then passed = passed + 1
        else failed = failed + 1; print("FAIL " .. file .. " :: " .. n .. "\n     " .. tostring(err)) end
    end
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
