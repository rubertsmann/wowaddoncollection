-- Feature 002: locale files stay complete and consistent with the code (RF4), and the UI has no hardcoded text
local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a"); f:close()
    return s
end

local function sourceFiles()
    local out = {}
    local p = io.popen('dir /b /s Core\\*.lua UI\\*.lua 2>nul || find Core UI -name "*.lua"')
    for line in p:lines() do
        local l = "/" .. line:gsub("\\", "/")
        local path = l:match(".*/(Core/[%w_/]+%.lua)$") or l:match(".*/(UI/[%w_/]+%.lua)$")
        if path then out[#out + 1] = path end
    end
    p:close()
    table.sort(out)
    return out
end

local function placeholders(s)
    local set = {}
    for k in s:gmatch("{(%w+)}") do set[k] = true end
    return set
end

local function sameSet(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

return {
    ["locale files: every Text[\"...\"] used in code is translated in deDE and every deDE key is used"] = function(harness)
        local addon = harness.addon()
        local de = addon.Locale.strings.deDE
        local used = {}
        for _, path in ipairs(sourceFiles()) do
            for key in slurp(path):gmatch('%f[%w_]Text%["(.-)"%]') do used[key] = path end
        end
        local missing, unused = {}, {}
        for key, path in pairs(used) do if de[key] == nil then missing[#missing + 1] = key .. "  (" .. path .. ")" end end
        for key in pairs(de) do if not used[key] then unused[#unused + 1] = key end end
        table.sort(missing); table.sort(unused)
        harness.truthy(next(used), "found no Text[...] keys: the lint pattern is broken")
        harness.equal(#missing, 0, "untranslated in deDE: " .. table.concat(missing, " | "))
        harness.equal(#unused, 0, "deDE keys not used by any code (typo or stale): " .. table.concat(unused, " | "))
    end,

    ["locale files: translations keep exactly the placeholders of their key"] = function(harness)
        local addon = harness.addon()
        for code, strings in pairs(addon.Locale.strings) do
            for key, text in pairs(strings) do
                harness.truthy(sameSet(placeholders(key), placeholders(text)), code .. ": placeholder mismatch in '" .. key .. "'")
                harness.truthy(addon.Utility.IsValidUtf8(text), code .. ": invalid UTF-8 in '" .. key .. "'")
            end
        end
    end,

    ["locale files: every language knows the same professions, with unique names"] = function(harness)
        local addon = harness.addon()
        local en = addon.Locale.professions.enUS
        for code, byId in pairs(addon.Locale.professions) do
            local seen = {}
            for id, name in pairs(byId) do
                harness.truthy(en[id], code .. " has profession id " .. id .. " that enUS lacks")
                local k = addon.Utility.SearchKey(name)
                harness.truthy(not seen[k], code .. " has duplicate profession name " .. name)
                seen[k] = true
            end
            for id in pairs(en) do harness.truthy(byId[id], code .. " lacks profession id " .. id) end
        end
    end,

    ["ui lint: no hardcoded user-facing text in UI/ (all labels go through Text)"] = function(harness)
        local src = slurp("UI/Window.lua")
        local bad = {}
        for lit in src:gmatch('SetText%(("[^"]*%a[^"]*")') do
            -- color escapes such as "|cff33ff99" are markup, not text
            local words = lit:gsub("|c%x*", ""):gsub("|r", "")
            if words:find("%a") then bad[#bad + 1] = "SetText(" .. lit end
        end
        for lit in src:gmatch('button%([%w_%.]+,%s*("[^"]*")') do bad[#bad + 1] = "button(" .. lit end
        for lit in src:gmatch('AddLine%(("[^"]*")') do bad[#bad + 1] = "AddLine(" .. lit end
        harness.equal(#bad, 0, "hardcoded UI text, wrap it in Text[...]: " .. table.concat(bad, " | "))
    end,
}
