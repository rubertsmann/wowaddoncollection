-- Store rules (newer data is left untouched, names are re-keyed, members who left are pruned) and locale completeness.
local NOW = 1794873600   -- 2026-11-17 00:00 UTC

local function slurp(path)
    local handle = assert(io.open(path, "rb"), path)
    local text = handle:read("*a"); handle:close()
    return text
end

local function sourceFiles()
    local files = {}
    local listing = io.popen('dir /b /s Core\\*.lua UI\\*.lua 2>nul || find Core UI -name "*.lua"')
    for line in listing:lines() do
        local path = ("/" .. line:gsub("\\", "/"))
        local relative = path:match(".*/(Core/[%w_/]+%.lua)$") or path:match(".*/(UI/[%w_/]+%.lua)$")
        if relative then files[#files + 1] = relative end
    end
    listing:close()
    return files
end

local function placeholders(text)
    local set = {}
    for name in text:gmatch("{(%w+)}") do set[name] = true end
    return set
end

return {
    ["store: data from a newer schema is left untouched and this session refuses to play"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local saved = { schema = 3, games = { ["X-R"] = { future = true } } }
        local kept, status = addon.Store.Init(saved)
        harness.equal(status, "newer"); harness.truthy(kept == saved); harness.truthy(saved.games["X-R"].future)
        harness.truthy(addon.db.readonly)
        harness.equal(select(2, addon.Games.Flip("Me-R", 10, "H", NOW, function() return 0.1 end)), "readonly")
    end,

    ["store: corrupt saved data starts empty; a missing schema is today's"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local _, status = addon.Store.Init({ schema = "x" })
        harness.equal(status, "reset", "a corrupt schema marker starts empty")
        local out, plain = addon.Store.Init({ games = {} })
        harness.equal(plain, "ok"); harness.equal(out.schema, 2)
    end,

    ["store: re-keying meets two spellings on one key (newer wins); prune and clean"] = function(harness)
        local addon = harness.addon({ now = NOW })
        local random = function() return 0.1 end
        addon.Games.Flip("Me-R", 10, "H", NOW, random)
        addon.Games.Flip("Peer-R", 10, "H", NOW, random)
        addon.Games.Flip("Gone-R", 10, "H", NOW, random)
        addon.Store.Prune({ ["Me-R"] = true, ["Peer-R"] = true }, "Me-R")
        harness.equal(addon.Games.Get("Gone-R"), nil); harness.truthy(addon.Games.Get("Peer-R"))
        harness.equal(addon.Store.CanonicalizeStoredNames(), 0, "already canonical")
        harness.equal(addon.Store.Clean(), 2)
        harness.equal(addon.Games.Get("Me-R"), nil)
    end,

    ["locale: every Text[...] key is translated in deDE, every deDE key is used, placeholders match"] = function(harness)
        local addon = harness.addon()
        local german = addon.Locale.strings.deDE
        local used = {}
        for _, path in ipairs(sourceFiles()) do
            for key in slurp(path):gmatch('%f[%w_]Text%["(.-)"%]') do used[key] = path end
        end
        harness.truthy(next(used), "found no Text[...] keys: the lint pattern is broken")
        local missing, unused, badPlaceholders = {}, {}, {}
        for key, path in pairs(used) do if german[key] == nil then missing[#missing + 1] = key .. " (" .. path .. ")" end end
        for key, translation in pairs(german) do
            if not used[key] then unused[#unused + 1] = key end
            local keySet, translationSet = placeholders(key), placeholders(translation)
            for name in pairs(keySet) do if not translationSet[name] then badPlaceholders[#badPlaceholders + 1] = key end end
            for name in pairs(translationSet) do if not keySet[name] then badPlaceholders[#badPlaceholders + 1] = key end end
        end
        table.sort(missing); table.sort(unused)
        harness.equal(#missing, 0, "untranslated in deDE: " .. table.concat(missing, " | "))
        harness.equal(#unused, 0, "deDE keys not used by any code: " .. table.concat(unused, " | "))
        harness.equal(#badPlaceholders, 0, "placeholders differ: " .. table.concat(badPlaceholders, " | "))
    end,
}
