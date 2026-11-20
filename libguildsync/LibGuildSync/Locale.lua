-- LibGuildSync: addon text localization, one instance per addon (Locale.New).
--   locale.Text[<english text>]   -> text in the UI language; missing translation -> the English key itself (never nil)
--   Locale.Format("{count} recipes", { count = 3 })   named placeholders (Lua string.format has no positional %1$s)
--   Locale.Plural(count, Text["{n} recipe"], Text["{n} recipes"])
--   locale.Register(code, { english key = translation, ... })
-- clientCode = the game client's language; code = the UI language, normally the same, overridable for testing.
local lib = LibStub("LibGuildSync-1.0")
local Locale = lib:Module("Locale", 2)
if not Locale then return end

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

---@class LocaleInstance
---@field strings table<string, table<string, string>> language code -> { [english key] = translation }
---@field version integer bumped whenever registered data changes
---@field clientCode string
---@field code string
---@field Text table<string, string>

-- A text table for one addon. Functions are called with a dot.
---@return LocaleInstance
function Locale.New()
    local clientCode = (GetLocale and GetLocale()) or "enUS"
    local instance = { strings = {}, version = 0, clientCode = clientCode, code = clientCode, Format = Locale.Format,
        Plural = Locale.Plural }
    ---@param languageCode string
    ---@param strings? table<string, string>
    function instance.RegisterStrings(languageCode, strings)
        local translations = instance.strings[languageCode] or {}
        for englishKey, translation in pairs(strings or {}) do translations[englishKey] = translation end
        instance.strings[languageCode] = translations
        instance.version = instance.version + 1
    end
    -- nil (or "") resets to the client language
    ---@param languageCode string|nil
    function instance.SetInterfaceLanguage(languageCode)
        if type(languageCode) ~= "string" or languageCode == "" then languageCode = instance.clientCode end
        instance.code = languageCode
    end
    instance.Text = setmetatable({}, {
        __index = function(_, englishKey)
            local translations = instance.strings[instance.code]
            local translation = translations and translations[englishKey]
            if translation == nil then translation = englishKey end
            return translation
        end,
    })
    return instance
end
