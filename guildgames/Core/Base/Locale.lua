local addonName, addon = ...

-- Addon text localization. The text table is a LibGuildSync-1.0 Locale (LibGuildSync/Locale.lua).
--   addon.Text[<english text>]   -> text in the UI language; missing translation -> the English key itself (never nil)
--   addon.Locale.Format("{count} plays", { count = 3 })   named placeholders (Lua string.format has no positional %1$s)
--   Locales/<code>.lua call addon.Locale.Register(code, { strings = {...} })
-- clientCode = the game client's language; code = the UI language, normally the same, overridable for testing with
-- /gg locale <code>. The placeholder names inside the translated strings ({n}, {gold}, ...) are part of the translation
-- files and stay.

---@class LocaleData
---@field strings? table<string, string> english key -> translation

---@class LocaleModule: LocaleInstance
local Locale = LibStub("LibGuildSync-1.0").Locale.New()
addon.Locale = Locale

---@param languageCode string
---@param data? LocaleData
function Locale.Register(languageCode, data) Locale.RegisterStrings(languageCode, data and data.strings) end

---@type table<string, string>
addon.Text = Locale.Text

-- /gg locale [code|auto]: UI language override for testing translations
addon.SlashCommands.locale = function(arguments)
    local languageCode = (arguments or ""):match("^%s*(%S*)") or ""
    if languageCode == "" then
        addon.Print(("UI language %s, game client %s (use /%s locale <code> or auto, then /reload)"):format(
            Locale.code, Locale.clientCode, (addon.SLASH_COMMANDS[1]:gsub("^/", ""))))
        return
    end
    if not addon.db then return end
    addon.db.ui.locale = languageCode ~= "auto" and languageCode or nil
    addon.Print(("UI language set to %s: /reload to apply"):format(languageCode))
end
