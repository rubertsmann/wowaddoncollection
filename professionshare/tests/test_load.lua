-- Load-time smoke test: every file in the TOC compiles and runs its top level against stubbed WoW globals, in TOC order.
-- Catches wrong load order, missing files, and nil globals at load. It does NOT replace testing in the game.
local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a"); f:close()
    return s
end

-- Universal widget stub: every method returns the stub itself, except the few that must return plain values.
local PLAIN = { GetStringWidth = 40, GetWidth = 100, GetHeight = 20, GetText = "", IsShown = true, GetEffectiveScale = 1,
    GetCenter = 0, GetNumPoints = 0, GetFontString = false, GetFrameLevel = 1 }
local function stub()
    local s = {}
    return setmetatable(s, {
        __index = function(_, k)
            return function(self, ...)
                local v = PLAIN[k]
                if v == nil then return s end
                if v == false then return s end
                return v
            end
        end,
        __call = function() return s end,
    })
end

local function tocFiles(path)
    local out = {}
    for line in slurp(path):gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%.lua%s*$") then out[#out + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/")) end
    end
    return out
end

-- the standard minimap-button libraries (LibDBIcon and what it needs) run against the stubs too; the other Libs are
-- loaded by tests/run.lua
local function isMinimapLibrary(file)
    return file:match("^Libs/CallbackHandler%-1%.0/") or file:match("^Libs/LibDataBroker%-1%.1/") or file:match("^Libs/LibDBIcon%-1%.0/")
end

local function listDir(pattern)
    local out = {}
    local top = pattern:match("^([%w_]+)/")
    local p = io.popen('dir /b /s ' .. pattern:gsub("/", "\\") .. ' 2>nul || find ' .. top .. ' -name "*.lua"')
    for line in p:lines() do
        -- repo-relative path from the top folder on, at any depth (Core/Net/Communication.lua)
        local rel = ("/" .. line:gsub("\\", "/")):match(".*/(" .. top .. "/[%w_/]+%.lua)$")
        if rel then out[#out + 1] = rel end
    end
    p:close()
    return out
end

return {
    ["load: the TOC lists every addon file and every listed file exists"] = function(harness)
        local listed = {}
        for _, f in ipairs(tocFiles("ProfessionShare.toc")) do listed[f] = true; assert(io.open(f, "rb"), "TOC lists missing file " .. f):close() end
        for _, dir in ipairs({ "Core/*.lua", "UI/*.lua", "Locales/*.lua" }) do
            for _, f in ipairs(listDir(dir)) do harness.truthy(listed[f], f .. " exists but is not in ProfessionShare.toc") end
        end
    end,

    ["load: all TOC files run in order for both identities without errors"] = function(harness)
        local saved = {}
        local globals = { CreateFrame = stub, UIParent = stub(), Minimap = stub(), GameTooltip = stub(), C_Timer = stub(),
            C_ChatInfo = stub(), UISpecialFrames = {}, SlashCmdList = {}, RAID_CLASS_COLORS = {}, print = function() end }
        for k, v in pairs(globals) do saved[k] = _G[k]; _G[k] = (k == "CreateFrame") and function() return stub() end or v end
        local ok, err = pcall(function()
            for _, addonFolderName in ipairs({ "ProfessionShare", "ProfessionShare-Dev" }) do
                local addon = {}
                for _, file in ipairs(tocFiles("ProfessionShare.toc")) do
                    if not file:match("^Libs/") or isMinimapLibrary(file) then
                        local chunk = assert(loadfile(file), file)
                        chunk(addonFolderName, addon)
                    end
                end
                harness.truthy(addon.UI and addon.Communication and addon.Scanner and addon.Names and addon.Locale and addon.Text and addon.Model, "namespace incomplete")
                harness.truthy(addon.SlashCommands.i18n and addon.SlashCommands.locale and addon.SlashCommands.scan and addon.SlashCommands.version and addon.SlashCommands.clean, "slash commands missing")
                -- addon code must never try to open professions itself (blocked on Forever): the API must not exist
                harness.equal(addon.Api.OpenProfession, nil, "Api.OpenProfession would be blocked by the client")
                harness.equal(addon.AutoScan, nil)

                -- build the window against stubbed widgets and refresh it with some data: catches runtime errors in the
                -- UI code (typos, nil globals, wrong argument types). It cannot judge layout or secure-button behaviour.
                addon.Store.Init({})
                addon.Store.db.me = "A-R"
                addon.orders = addon.Orders.New(addon.Utility.Now, addon.db.orders)
                addon.Events = addon.Events or { On = function() end, Fire = function() end }
                addon.Store.PutCharacter({ name = "A-R", class = "MAGE", level = 30, rev = 1, professions = {
                    Kochkunst = { name = "Kochkunst", id = 185, loc = "deDE", rank = 10, max = 75, recipes = { [1] = true } } } })
                addon.Store.PutCatalog({ [1] = { name = "Gebratener Eber", loc = "deDE", reagents = { { itemID = 5, count = 2 } } } })
                addon.orders:Create("A-R", 1, 1, "Notiz")
                local okT, errT = pcall(addon.UI.Toggle); harness.truthy(okT, "building the window failed: " .. tostring(errT))
                harness.truthy(pcall(addon.UI.Refresh), "refreshing the window failed")
                local okO, errO = pcall(addon.UI.SelectTab, "orders"); harness.truthy(okO, "switching to the orders tab failed: " .. tostring(errO))
                addon.Offers.Put({ name = "B-R", rev = 5, items = { [6661] = { bag = 1 } }, dibs = {} })
                harness.truthy(pcall(addon.UI.SelectTab, "available"), "switching to the available tab failed")
                harness.truthy(pcall(addon.UI.Refresh), "refreshing the available tab failed")
                -- the Misc Items modes: keys and attunements with a peer's record, then back to recipe items
                addon.Access.Put({ name = "B-R", rev = 5, keys = { [7146] = { keyring = true } }, att = { mc = true, bwl = false } })
                addon.Reputation.Put({ name = "B-R", rev = 5, f = { [59] = { s = 6, v = 4200, m = 12000 } } })
                for _, mode in ipairs({ "keys", "attunements", "reputation", "offers" }) do
                    addon.MiscTables.SetMode(addon.db.ui, mode)
                    local okM, errM = pcall(addon.UI.Refresh)
                    harness.truthy(okM, "refreshing the " .. mode .. " mode failed: " .. tostring(errM))
                end
                harness.truthy(addon.SlashCommands.access, "/ps access missing")
                harness.truthy(pcall(addon.SlashCommands.access, ""), "/ps access failed")
                harness.truthy(addon.SlashCommands.rep, "/ps rep missing")
                local okR, errR = pcall(addon.SlashCommands.rep, "")
                harness.truthy(okR, "/ps rep failed: " .. tostring(errR))
                -- the games moved to the GuildGames addon; no tab, no dev commands, no game module
                harness.equal(addon.Games, nil); harness.equal(addon.GamesTab, nil)
                harness.truthy(not slurp("UI/Window.lua"):find('key = "games"', 1, true), "the window still defines a games tab")
                harness.equal(addon.SlashCommands.anim, nil); harness.equal(addon.SlashCommands.game, nil)
                addon.Trace.Add({ dir = "in", ch = "GUILD", peer = "B-R", mt = "HELLO", st = "ok", why = "char: up to date" })
                -- Feedback tab: the form for everyone, the developer list on a reader's client (the dev build is one)
                -- live build: hidden while the developer is not in my guild roster (a made-up developer name here)
                addon.Model.BUILD_VIEWER_HASHES = { [addon.Model.NameHash("test developer")] = true }
                addon.Communication.roster = { ["A-R"] = true, ["B-R"] = true }
                harness.truthy(pcall(addon.UI.SelectTab, "feedback"), "switching to the feedback tab failed")
                harness.equal(addon.UI.CurrentTab(), addon.IS_DEVELOPMENT_BUILD and "feedback" or "recipes",
                    "the live build hides the Feedback tab when the developer is not in the guild")
                addon.Communication.roster = { ["A-R"] = true, ["B-R"] = true, ["Test Developer-R"] = true }
                addon.UI.SelectTab("feedback")
                harness.equal(addon.UI.CurrentTab(), "feedback", "shown once the developer is in the roster")
                addon.Communication.roster = { ["A-R"] = true }
                addon.UI.Refresh()
                harness.equal(addon.UI.CurrentTab(), addon.IS_DEVELOPMENT_BUILD and "feedback" or "recipes",
                    "the developer left the guild: the open Feedback tab closes")
                addon.Communication.roster = { ["A-R"] = true, ["Test Developer-R"] = true }
                addon.UI.SelectTab("feedback")
                local okS, errS = pcall(addon.UI.SendFeedback)   -- the stub box holds "": refused, nothing stored
                harness.truthy(okS, "sending feedback failed: " .. tostring(errS))
                harness.equal(addon.Feedback.MyCount("A-R"), 0)
                addon.Feedback.Put({ name = "B-R", rev = 5, items = { { t = 1, k = "bug", text = "x |cffff0000red", log = "v1" } } }, "A-R")
                harness.truthy(pcall(addon.UI.Refresh), "refreshing the feedback tab failed")
                -- the Debug tab: live build only after /ps debug, the dev build always
                addon.UI.SelectTab("debug")
                harness.equal(addon.UI.CurrentTab(), addon.IS_DEVELOPMENT_BUILD and "debug" or "recipes", "the live build hides the Debug tab")
                local okD, errD = pcall(addon.SlashCommands.debug, "3")
                harness.truthy(okD, "/ps debug failed: " .. tostring(errD))
                harness.equal(addon.UI.CurrentTab(), "debug", "/ps debug shows the Debug tab")
                local okN, errN = pcall(addon.Diagnostics.IdentityRows, { identity = {}, me = "A-R", roster = {} })
                harness.truthy(okN, "name check rows failed: " .. tostring(errN))
                local okE, errE = pcall(addon.UI.ShowExport, addon.Diagnostics.Report({ communication = addon.Communication }))
                harness.truthy(okE, "the export window failed: " .. tostring(errE))
                harness.truthy(addon.SlashCommands.offers, "/ps offers missing")
                -- dev fake enchanter: works when the client knows no realm (no "name not known yet")
                do
                    local savedRealm = GetNormalizedRealmName
                    GetNormalizedRealmName = function() return nil end
                    addon.Store.db.me = "First Surname"
                    local okF, errF = pcall(addon.DevProbe.AddFakeEnchanter)
                    harness.truthy(okF, "fake enchanter failed: " .. tostring(errF))
                    harness.truthy(addon.Store.db.chars["Fake Enchanter"], "the realm-free fake enchanter was added")
                    harness.truthy(addon.Store.keptNames["Fake Enchanter"], "and kept from the prune")
                    -- dev fake key holder: keys, then Naxxramas on the same local-only record
                    local okK, errK = pcall(addon.DevProbe.AddFakeKeys)
                    harness.truthy(okK, "fake keys failed: " .. tostring(errK))
                    local okX, errX = pcall(addon.DevProbe.AddFakeNaxxramas)
                    harness.truthy(okX, "fake Naxxramas failed: " .. tostring(errX))
                    local fakeKeyholder = addon.Access.Get("Fake Keyholder")
                    harness.truthy(fakeKeyholder and fakeKeyholder.keys[7146], "fake keys stored")
                    harness.equal(fakeKeyholder.att.naxx, true); harness.equal(fakeKeyholder.att.mc, true, "the keys are kept")
                    harness.truthy(addon.Store.keptNames["Fake Keyholder"], "kept from the prune")
                    harness.truthy(addon.Access.Sanitize(fakeKeyholder), "the fake record is a valid record")
                    harness.equal(addon.SlashCommands.fakekeys ~= nil, addon.IS_DEVELOPMENT_BUILD and true or false,
                        "/ps fakekeys exists only in the dev build")
                    harness.equal(addon.SlashCommands.fakenaxx ~= nil, addon.IS_DEVELOPMENT_BUILD and true or false,
                        "/ps fakenaxx exists only in the dev build")
                    harness.equal(addon.SlashCommands.fakefeedback ~= nil, addon.IS_DEVELOPMENT_BUILD and true or false,
                        "/ps fakefeedback exists only in the dev build")
                    if addon.IS_DEVELOPMENT_BUILD then
                        local okB, fakeRecord = pcall(addon.DevProbe.AddFakeFeedback)
                        harness.truthy(okB and fakeRecord, "fake feedback failed: " .. tostring(fakeRecord))
                        harness.truthy(addon.Feedback.Sanitize(fakeRecord), "the fake record is a valid record")
                    end
                    -- dev fake request: the realm-named request is answered under the asked name
                    addon.Utility.NoteMyFullName("First Surname")
                    addon.Store.PutCharacter({ name = "First Surname", class = "MAGE", level = 30, rev = 5, professions = {
                        Kochkunst = { name = "Kochkunst", id = 185, loc = "deDE", rank = 10, max = 75, recipes = { [1] = true } } } })
                    addon.Offers.Put({ name = "First Surname", rev = 6, items = { [777] = { bag = 1 } }, dibs = {} })
                    local sentBefore = #(addon.Communication.queue or {})
                    local okR, results = pcall(addon.DevProbe.SimulateRealmRequest)
                    GetNormalizedRealmName = savedRealm
                    harness.truthy(okR, "fake request failed: " .. tostring(results))
                    harness.equal(#results, 2)
                    for _, result in ipairs(results) do
                        harness.truthy(result.answer, result.type .. " not answered: " .. result.status .. " " .. result.reason)
                        harness.equal(result.answerName, "First Surname-CAMWOWEU4Realm3PvE")
                    end
                    harness.equal(#(addon.Communication.queue or {}), sentBefore, "the simulation must not send anything")
                    addon.Store.db.me = "A-R"
                end
                harness.truthy(addon.Events.ScanItems, "item scan hook missing")
                -- my own changes are announced coalesced, never with an immediate forced HELLO each
                do
                    local hellos = {}
                    local savedSoon, savedNow = addon.Communication.RequestHelloSoon, addon.Communication.RequestHello
                    addon.Communication.RequestHelloSoon = function() hellos[#hellos + 1] = "soon" end
                    addon.Communication.RequestHello = function() hellos[#hellos + 1] = "now" end
                    for _, eventName in ipairs({ "LOCAL_CHANGED", "OFFERS_CHANGED", "ACCESS_CHANGED", "FEEDBACK_CHANGED" }) do addon.Events.Fire(eventName) end
                    addon.Communication.RequestHelloSoon, addon.Communication.RequestHello = savedSoon, savedNow
                    harness.equal(table.concat(hellos, ","), "soon,soon,soon,soon")
                end
                harness.truthy(addon.Names.environment.spellName, "Api did not wire Names.env.spellName")
            end
        end)
        for k in pairs(globals) do _G[k] = saved[k] end
        if not ok then error(err, 0) end
    end,

    -- ProfessionShare-Dev.toc is GENERATED by tools/deploy.ps1 from ProfessionShare.toc and is not versioned. It goes stale as soon
    -- as the live TOC gains a file, and the dev client then dies with "attempt to index local 'Guard' (a nil value)".
    ["load: the generated ProfessionShare-Dev.toc (when present) lists the same files, in the same order, as ProfessionShare.toc"] = function(harness)
        local f = io.open("ProfessionShare-Dev.toc", "rb")
        if not f then return end   -- not generated on this machine (CI): nothing to compare
        f:close()
        local live, dev = tocFiles("ProfessionShare.toc"), tocFiles("ProfessionShare-Dev.toc")
        local inDev, inLive, missing, extra = {}, {}, {}, {}
        for _, x in ipairs(dev) do inDev[x] = true end
        for _, x in ipairs(live) do inLive[x] = true; if not inDev[x] then missing[#missing + 1] = x end end
        for _, x in ipairs(dev) do if not inLive[x] then extra[#extra + 1] = x end end
        local why = "ProfessionShare-Dev.toc is stale (missing: " .. table.concat(missing, ", ") .. "; extra: " .. table.concat(extra, ", ") ..
            "). Regenerate it: powershell tools/deploy.ps1, then restart the game"
        harness.equal(#missing + #extra, 0, why)
        harness.equal(table.concat(dev, "\n"), table.concat(live, "\n"), "ProfessionShare-Dev.toc loads the files in a different order")
        local liveVersion = slurp("ProfessionShare.toc"):match("## Version:%s*(%S+)")
        harness.equal(slurp("ProfessionShare-Dev.toc"):match("## Version:%s*(%S+)"), liveVersion .. "-dev", "dev TOC version is stale: run tools/deploy.ps1")
    end,

    -- a TOC that misses a file must produce ONE plain message instead of a chain of nil-index errors
    ["load: Events names the missing modules and the fix when a TOC lacks a file"] = function(harness)
        local saved, said = {}, {}
        local globals = { CreateFrame = function() return stub() end, UIParent = stub(), Minimap = stub(), GameTooltip = stub(),
            C_Timer = stub(), C_ChatInfo = stub(), UISpecialFrames = {}, SlashCmdList = {}, RAID_CLASS_COLORS = {},
            print = function(...) said[#said + 1] = table.concat({ ... }, " ") end }
        for k, v in pairs(globals) do saved[k] = _G[k]; _G[k] = v end
        local addon = {}
        for _, file in ipairs(tocFiles("ProfessionShare.toc")) do
            if not file:match("^Libs/") and file ~= "Core/Net/Guard.lua" then   -- the stale dev TOC
                local chunk = assert(loadfile(file), file)
                pcall(chunk, "ProfessionShare-Dev", addon)                          -- Communication.lua fails here, later files must still load
            end
        end
        for k in pairs(globals) do _G[k] = saved[k] end
        local text = table.concat(said, "\n")
        harness.truthy(text:find("Guard", 1, true), "no message naming the missing module: " .. text)
        harness.truthy(text:find("deploy.ps1", 1, true), "no message naming the fix: " .. text)
    end,

    -- A helper removed from a file but still called in it compiles fine and only fails in the game ("attempt to call a nil
    -- value": Window.lua's setButtonLabel). The stubbed load test cannot see it (stub widgets answer every
    -- method), so read the bytecode instead: every lowercase global a file reads must be a known Lua/WoW function.
    ["load: no file reads an unknown lowercase global (a removed local helper)"] = function(harness)
        local known = {}
        for name in ([[type pairs ipairs tostring tonumber select pcall xpcall error assert setmetatable getmetatable unpack print
            next rawget rawset math string table os debug date time tinsert wipe debugstack geterrorhandler loadstring strtrim
            debugprofilestop hooksecurefunc]]):gmatch("%S+") do known[name] = true end
        local unknown = {}
        for _, file in ipairs(tocFiles("ProfessionShare.toc")) do
            if not file:match("^Libs/") then
                local listing = assert(io.popen('luajit -bl "' .. file .. '"'))
                for name in listing:read("*a"):gmatch('GGET[^\n]-"([a-z][%w_]*)"') do
                    if not known[name] then unknown[#unknown + 1] = file .. ": " .. name end
                end
                listing:close()
            end
        end
        harness.equal(#unknown, 0, "unknown globals (missing local?): " .. table.concat(unknown, ", "))
    end,
}
