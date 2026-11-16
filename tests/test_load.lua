-- Load-time smoke test: every file in the TOC compiles and runs its top level against stubbed WoW globals, in TOC order.
-- Catches wrong load order, missing files, and nil globals at load. It does NOT replace testing in the game.
local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a"); f:close()
    return s
end

-- Universal widget stub: every method returns the stub itself, except the few that must return plain values.
local PLAIN = { GetStringWidth = 40, GetWidth = 100, GetHeight = 20, GetText = "", IsShown = true, GetEffectiveScale = 1,
    GetCenter = 0, GetNumPoints = 0, GetFontString = false }
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

local function listDir(pattern)
    local out = {}
    local p = io.popen('dir /b /s ' .. pattern:gsub("/", "\\") .. ' 2>nul || find ' .. pattern:match("^[^*]+") .. ' -name "*.lua"')
    for line in p:lines() do
        local rel = line:gsub("\\", "/"):match("([%w_]+/[%w_]+%.lua)$")
        if rel then out[#out + 1] = rel end
    end
    p:close()
    return out
end

return {
    ["load: the TOC lists every addon file and every listed file exists"] = function(h)
        local listed = {}
        for _, f in ipairs(tocFiles("TalentShare.toc")) do listed[f] = true; assert(io.open(f, "rb"), "TOC lists missing file " .. f):close() end
        for _, dir in ipairs({ "Core/*.lua", "UI/*.lua", "Locales/*.lua" }) do
            for _, f in ipairs(listDir(dir)) do h.truthy(listed[f], f .. " exists but is not in TalentShare.toc") end
        end
    end,

    ["load: all TOC files run in order for both identities without errors"] = function(h)
        local saved = {}
        local globals = { CreateFrame = stub, UIParent = stub(), Minimap = stub(), GameTooltip = stub(), C_Timer = stub(),
            C_ChatInfo = stub(), UISpecialFrames = {}, SlashCmdList = {}, RAID_CLASS_COLORS = {}, print = function() end }
        for k, v in pairs(globals) do saved[k] = _G[k]; _G[k] = (k == "CreateFrame") and function() return stub() end or v end
        local ok, err = pcall(function()
            for _, addon in ipairs({ "TalentShare", "TalentShare-Dev" }) do
                local ns = {}
                for _, file in ipairs(tocFiles("TalentShare.toc")) do
                    if not file:match("^Libs/") then
                        local chunk = assert(loadfile(file), file)
                        chunk(addon, ns)
                    end
                end
                h.truthy(ns.UI and ns.Comm and ns.Scanner and ns.Names and ns.Locale and ns.L and ns.Model, "namespace incomplete")
                h.truthy(ns.Slash.i18n and ns.Slash.locale and ns.Slash.scan and ns.Slash.version and ns.Slash.clean, "slash commands missing")
                -- addon code must never try to open professions itself (blocked on Forever): the API must not exist
                h.eq(ns.Api.OpenProfession, nil, "Api.OpenProfession would be blocked by the client")
                h.eq(ns.AutoScan, nil)

                -- build the window against stubbed widgets and refresh it with some data: catches runtime errors in the
                -- UI code (typos, nil globals, wrong argument types). It cannot judge layout or secure-button behaviour.
                ns.Store.Init({})
                ns.Store.db.me = "A-R"
                ns.orders = ns.Orders.New(ns.Util.Now, ns.db.orders)
                ns.Events = ns.Events or { On = function() end, Fire = function() end }
                ns.Store.PutChar({ name = "A-R", class = "MAGE", level = 30, rev = 1, professions = {
                    Kochkunst = { name = "Kochkunst", id = 185, loc = "deDE", rank = 10, max = 75, recipes = { [1] = true } } } })
                ns.Store.PutCatalog({ [1] = { name = "Gebratener Eber", loc = "deDE", reagents = { { itemID = 5, count = 2 } } } })
                ns.orders:Create("A-R", 1, 1, "Notiz")
                h.truthy(pcall(ns.UI.Toggle), "building the window failed")
                h.truthy(pcall(ns.UI.Refresh), "refreshing the window failed")
                h.truthy(pcall(ns.UI.SelectTab, "orders"), "switching to the orders tab failed")
                h.truthy(ns.Names.env.spellName, "Api did not wire Names.env.spellName")
            end
        end)
        for k in pairs(globals) do _G[k] = saved[k] end
        if not ok then error(err, 0) end
    end,
}
