local addonName, addon = ...

-- Slash commands: /fbui (or /betterui). Without arguments it opens the options window.
local Logic, Elements, Fader, Options = addon.Logic, addon.Elements, addon.Fader, addon.Options

function addon.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffBetterUI:|r " .. message)
end

local HELP = {
    "/fbui - open the options window",
    "/fbui global <0-100> - opacity of every element set to Global",
    "/fbui set <element> <0-100|global|off> - one element (see /fbui list)",
    "/fbui list - elements with their mode and opacity",
    "/fbui combat - toggle full opacity in combat (global) | /fbui fade <seconds>",
    "/fbui combat <element> full|faded|global - per element in combat",
    "/fbui disable | enable - stop / resume (disable restores full opacity)",
    "/fbui editmode - list Edit Mode settings, marking the ones the dialog hides",
    "/fbui reset | debug | log [n] | clearlog",
}

local function list()
    local settings = ForeverBetterUIPlusDB
    addon.Print(string.format("global %s, fade %.2f s, combat %s%s", Logic.Percent(settings.global),
        settings.fadeSeconds, settings.combatFull and "full" or "faded", settings.disabled and ", DISABLED" or ""))
    for _, element in ipairs(Elements.list) do
        local mode = Logic.ModeName(settings, element.key)
        local base = Logic.BaseAlpha(settings, element.key)
        local frames, hovered = Fader.Info(element.key)
        local combat = Logic.CombatModeName(settings, element.key)
        if combat == "global" then combat = Logic.CombatFull(settings, element.key) and "full*" or "faded*" end
        addon.Print(string.format("  %-12s %-7s %-5s combat %-7s%s%s", element.key, mode,
            base and Logic.Percent(base) or "-", combat,
            #frames == 0 and "  (frame not found)" or "", hovered and "  (hovered)" or ""))
    end
end

local handlers = {
    [""] = function() Options.Toggle() end,
    options = function() Options.Toggle() end,
    global = function(argument)
        local value = Logic.ParseOpacity(argument)
        if type(value) ~= "number" then return addon.Print("usage: /fbui global <0-100>") end
        ForeverBetterUIPlusDB.global = value
        addon.Print("global opacity " .. Logic.Percent(value))
        Options.Refresh()
    end,
    set = function(argument)
        local key, text = (argument or ""):lower():match("^(%S+)%s+(%S+)$")
        local value = Logic.ParseOpacity(text)
        if not key or not Elements.ByKey(key) or value == nil then
            return addon.Print("usage: /fbui set <element> <0-100|global|off>; elements: /fbui list")
        end
        ForeverBetterUIPlusDB.elements[key] = value ~= Logic.MODE_GLOBAL and value or nil
        addon.Print(string.format("%s: %s", key, type(value) == "number" and Logic.Percent(value) or value))
        Options.Refresh()
    end,
    list = list,
    status = list,
    combat = function(argument)
        local key, text = (argument or ""):lower():match("^(%S+)%s*(%S*)$")
        if not key then
            ForeverBetterUIPlusDB.combatFull = not ForeverBetterUIPlusDB.combatFull
            addon.Print((ForeverBetterUIPlusDB.combatFull and "full opacity in combat" or "stays faded in combat")
                .. " (elements whose combat setting is global).")
            return Options.Refresh()
        end
        local value, valid = Logic.ParseCombatMode(text)
        if not Elements.ByKey(key) or not valid then
            return addon.Print("usage: /fbui combat [<element> full|faded|global]; elements: /fbui list")
        end
        ForeverBetterUIPlusDB.combat[key] = value
        addon.Print(string.format("%s in combat: %s", key, Logic.CombatModeName(ForeverBetterUIPlusDB, key)))
        Options.Refresh()
    end,
    fade = function(argument)
        local seconds = tonumber(argument)
        if not seconds or seconds < 0 or seconds > 3 then return addon.Print("usage: /fbui fade <0-3 seconds>") end
        ForeverBetterUIPlusDB.fadeSeconds = seconds
        Options.Refresh()
    end,
    disable = function()
        ForeverBetterUIPlusDB.disabled = true
        Fader.RestoreAll()
        addon.Print("disabled, everything back to full opacity. /fbui enable to resume.")
    end,
    enable = function()
        ForeverBetterUIPlusDB.disabled = nil
        addon.Print("enabled.")
    end,
    reset = function()
        Fader.RestoreAll()
        local log, debug = ForeverBetterUIPlusDB.log, ForeverBetterUIPlusDB.debug
        ForeverBetterUIPlusDB = Logic.NewSettings({ log = log, debug = debug })
        addon.Print("settings reset.")
        Options.Refresh()
    end,
    editmode = function()
        local ok, problem = pcall(addon.EditModeProbe.Run, addon.Print)
        if not ok then
            addon.Log.Write("error", "edit mode probe failed", { error = tostring(problem) })
            addon.Print("probe failed: " .. tostring(problem))
        end
    end,
    debug = function()
        ForeverBetterUIPlusDB.debug = not ForeverBetterUIPlusDB.debug
        addon.Log.Write("debug", ForeverBetterUIPlusDB.debug and "debug on" or "debug off")
        addon.Print(ForeverBetterUIPlusDB.debug and "debug log on (also printed to chat)." or "debug log off.")
    end,
    log = function(argument)
        for _, line in ipairs(addon.Log.Tail(tonumber(argument) or 20)) do DEFAULT_CHAT_FRAME:AddMessage(line) end
    end,
    clearlog = function() addon.Log.Clear(); addon.Print("log cleared.") end,
    help = function() for _, line in ipairs(HELP) do addon.Print(line) end end,
}

SLASH_FOREVERBETTERUIPLUS1 = "/fbui"
SLASH_FOREVERBETTERUIPLUS2 = "/betterui"
SlashCmdList.FOREVERBETTERUIPLUS = function(message)
    if not ForeverBetterUIPlusDB or not ForeverBetterUIPlusDB.elements then return end   -- before PLAYER_LOGIN
    local command, argument = strtrim(message or ""):match("^(%S*)%s*(.-)$")
    local handler = handlers[(command or ""):lower()] or handlers.help
    handler(argument)
end
