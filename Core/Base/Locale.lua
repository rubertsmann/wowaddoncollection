local addonName, addon = ...

-- Addon text localization (game names - professions, recipes, items - live in Names.lua).
--   addon.Text[<english text>]   -> text in the UI language; missing translation -> the English key itself (never nil)
--   addon.Locale.Format("{count} recipes", { count = 3 })   named placeholders (Lua string.format has no positional %1$s)
--   addon.Locale.Plural(count, Text["{n} recipe"], Text["{n} recipes"])
--   Locales/<code>.lua call addon.Locale.Register(code, { strings = {...}, professions = { [skillLineID] = name } })
-- clientCode = the game client's language (names learned from the game are in this language);
-- code       = the UI language, normally the same, overridable for testing with /ts locale <code>.
-- The placeholder names inside the translated strings ({n}, {name}, ...) are part of the translation files and stay.

---@class LocaleData
---@field strings? table<string, string> english key -> translation
---@field professions? table<integer, string> skill line id -> profession name

---@class LocaleModule
local Locale = {}
addon.Locale = Locale

---@type table<string, table<string, string>> language code -> { [english key] = translation }
Locale.strings = {}
---@type table<string, table<integer, string>> language code -> { [skillLineID] = name }
Locale.professions = {}
---@type integer bumped whenever name data changes (invalidates Names caches)
Locale.version = 0
---@type string
Locale.clientCode = (GetLocale and GetLocale()) or "enUS"
---@type string
Locale.code = Locale.clientCode

---@param languageCode string
---@param data? LocaleData
function Locale.Register(languageCode, data)
    data = data or {}
    local translations = Locale.strings[languageCode] or {}
    for englishKey, translation in pairs(data.strings or {}) do translations[englishKey] = translation end
    Locale.strings[languageCode] = translations
    local professionNames = Locale.professions[languageCode] or {}
    for skillLineID, professionName in pairs(data.professions or {}) do professionNames[skillLineID] = professionName end
    Locale.professions[languageCode] = professionNames
    Locale.version = Locale.version + 1
end

-- nil (or "") resets to the client language
---@param languageCode string|nil
function Locale.SetInterfaceLanguage(languageCode)
    if type(languageCode) ~= "string" or languageCode == "" then languageCode = Locale.clientCode end
    Locale.code = languageCode
end

---@type table<string, string>
addon.Text = setmetatable({}, {
    __index = function(_, englishKey)
        local translations = Locale.strings[Locale.code]
        local translation = translations and translations[englishKey]
        if translation == nil then translation = englishKey end
        return translation
    end,
})

-- "{name}" placeholders filled from `values`; an unknown placeholder stays visible ("{name}") instead of vanishing.
---@param template any
---@param values? table<string, any>
---@return string
function Locale.Format(template, values)
    return (tostring(template):gsub("{(%w+)}", function(placeholder)
        local value = values and values[placeholder]
        if value == nil then return "{" .. placeholder .. "}" end
        return tostring(value)
    end))
end

-- singularTemplate / pluralTemplate are already translated templates containing {n}
---@param count integer
---@param singularTemplate string
---@param pluralTemplate string
---@return string
function Locale.Plural(count, singularTemplate, pluralTemplate)
    return Locale.Format(count == 1 and singularTemplate or pluralTemplate, { n = count })
end

addon.SlashCommands.locale = function(arguments)
    local languageCode = (arguments or ""):match("^%s*(%S*)") or ""
    if languageCode == "" then
        addon.Print(("UI language %s, game client %s (use /%s locale <code> or auto, then /reload)"):format(
            Locale.code, Locale.clientCode, (addon.SLASH_COMMANDS[1]:gsub("^/", ""))))
        return
    end
    if not addon.db then return end
    if languageCode == "auto" then addon.db.ui.locale = nil else addon.db.ui.locale = languageCode end
    addon.Print(("UI language set to %s: /reload to apply"):format(languageCode))
end
