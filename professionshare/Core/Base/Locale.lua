local addonName, addon = ...

-- Addon text localization (game names - professions, recipes, items - live in Names.lua). The text table is a
-- LibGuildSync-1.0 Locale (LibGuildSync/Locale.lua); ProfessionShare adds profession names per language.
--   addon.Text[<english text>]   -> text in the UI language; missing translation -> the English key itself (never nil)
--   addon.Locale.Format("{count} recipes", { count = 3 })   named placeholders (Lua string.format has no positional %1$s)
--   addon.Locale.Plural(count, Text["{n} recipe"], Text["{n} recipes"])
--   Locales/<code>.lua call addon.Locale.Register(code, { strings = {...}, professions = { [skillLineID] = name } })
-- clientCode = the game client's language (names learned from the game are in this language);
-- code       = the UI language, normally the same, overridable for testing with /ps locale <code>.
-- The placeholder names inside the translated strings ({n}, {name}, ...) are part of the translation files and stay.

---@class LocaleData
---@field strings? table<string, string> english key -> translation
---@field professions? table<integer, string> skill line id -> profession name

---@class LocaleModule: LocaleInstance
local Locale = LibStub("LibGuildSync-1.0").Locale.New()
addon.Locale = Locale

---@type table<string, table<integer, string>> language code -> { [skillLineID] = name }
Locale.professions = {}

---@param languageCode string
---@param data? LocaleData
function Locale.Register(languageCode, data)
    data = data or {}
    local professionNames = Locale.professions[languageCode] or {}
    for skillLineID, professionName in pairs(data.professions or {}) do professionNames[skillLineID] = professionName end
    Locale.professions[languageCode] = professionNames
    Locale.RegisterStrings(languageCode, data.strings)   -- bumps Locale.version (invalidates Names caches)
end

---@type table<string, string>
addon.Text = Locale.Text

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
