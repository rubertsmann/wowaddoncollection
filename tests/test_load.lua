-- Load-time smoke test: every file in the TOC compiles and runs its top level against stubbed WoW globals, in TOC order.
-- Catches wrong load order, missing files, and nil globals at load. It does NOT replace testing in the game.
local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a"); f:close()
    return s
end

local function stub()
    local s = {}
    return setmetatable(s, { __index = function() return function() return s end end, __call = function() return s end })
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
                h.truthy(ns.UI and ns.Comm and ns.Scanner and ns.Names and ns.Locale and ns.L and ns.Model and ns.AutoScan, "namespace incomplete")
                h.truthy(ns.Slash.i18n and ns.Slash.locale and ns.Slash.scan and ns.Slash.version and ns.Slash.autoscan, "slash commands missing")
                -- on a client without C_TradeSkillUI.OpenTradeSkill the automatic scan must say so, not error (R4)
                h.eq(ns.Api.CanOpenProfession(), false)
                h.eq(ns.AutoScan.Instance():Start(false), false)
                h.truthy(ns.Names.env.spellName, "Api did not wire Names.env.spellName")
            end
        end)
        for k in pairs(globals) do _G[k] = saved[k] end
        if not ok then error(err, 0) end
    end,
}
