local ADDON, ns = ...

-- Addon text localization (game names - professions, recipes, items - live in Names.lua).
--   ns.L[<english text>]            -> text in the UI language; missing translation -> the English key itself (never nil)
--   ns.Locale.Fmt("{n} recipes", {n = 3})   named placeholders (real Lua string.format has no positional %1$s)
--   ns.Locale.Plural(n, L["{n} recipe"], L["{n} recipes"])
--   Locales/<code>.lua call ns.Locale.Register(code, { strings = {...}, professions = { [skillLineID] = name } })
-- clientCode = the game client's language (names learned from the game are in this language);
-- code       = the UI language, normally the same, overridable for testing with /ts locale <code>.
local Loc = {}
ns.Locale = Loc

Loc.strings = {}       -- code -> { [english key] = translation }
Loc.professions = {}   -- code -> { [skillLineID] = name }
Loc.version = 0        -- bumped whenever name data changes (invalidates Names caches)
Loc.clientCode = (GetLocale and GetLocale()) or "enUS"
Loc.code = Loc.clientCode

function Loc.Register(code, data)
    data = data or {}
    local s = Loc.strings[code] or {}
    for k, v in pairs(data.strings or {}) do s[k] = v end
    Loc.strings[code] = s
    local p = Loc.professions[code] or {}
    for id, name in pairs(data.professions or {}) do p[id] = name end
    Loc.professions[code] = p
    Loc.version = Loc.version + 1
end

-- code = nil resets to the client language
function Loc.SetUI(code)
    if type(code) ~= "string" or code == "" then code = Loc.clientCode end
    Loc.code = code
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local t = Loc.strings[Loc.code]
        local v = t and t[key]
        if v == nil then v = key end
        return v
    end,
})

function Loc.Fmt(template, vars)
    return (tostring(template):gsub("{(%w+)}", function(k)
        local v = vars and vars[k]
        if v == nil then return "{" .. k .. "}" end
        return tostring(v)
    end))
end

-- one/many are already translated templates containing {n}
function Loc.Plural(n, one, many)
    return Loc.Fmt(n == 1 and one or many, { n = n })
end

ns.Slash.locale = function(arg)
    arg = (arg or ""):match("^%s*(%S*)") or ""
    if arg == "" then
        ns.Print(("UI language %s, game client %s (use /%s locale <code> or auto, then /reload)"):format(
            Loc.code, Loc.clientCode, ((ns.SLASH[1] or "/ts"):gsub("^/", ""))))
        return
    end
    if not ns.db then return end
    if arg == "auto" then ns.db.ui.locale = nil else ns.db.ui.locale = arg end
    ns.Print(("UI language set to %s: /reload to apply"):format(arg))
end
