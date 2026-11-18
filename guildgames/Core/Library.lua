local addonName, addon = ...

-- GuildGames' instances of the shared LibGuildSync-1.0 modules (Libs\LibGuildSync, embedded; one copy is active per
-- client, shared with TalentShare). Every module of this addon calls them as addon.<Module>.<Function>.
local library = LibStub("LibGuildSync-1.0")

-- Utility: the shared helpers, plus who "me" is in GuildGames' saved data.
---@class UtilityModule
local Utility = setmetatable({}, { __index = library.Utility })
addon.Utility = Utility

-- My "Name-Realm": the stored identity, else the client's (before Store.Init or PLAYER_LOGIN). nil when neither is known.
---@return string|nil
function Utility.Me()
    local database = addon.Store and addon.Store.db
    if database and database.me then return database.me end
    local playerInformation = addon.Api and addon.Api.GetPlayerInformation()
    return playerInformation and playerInformation.name
end

-- Log: lines in addon.db.debug (/gg debug); errors also printed in the development build.
addon.Log = library.Log.New({
    entries = function()
        local database = addon.db
        return type(database) == "table" and type(database.debug) == "table" and database.debug or nil
    end,
    title = function() return addon.TITLE end,
    isDevelopment = function() return addon.IS_DEVELOPMENT_BUILD end,
})

-- one-line summaries of GuildGames' messages for the network trace (never the payload)
---@param message table
---@return string
local function summarize(message)
    local messageType = message.t
    if messageType == "HELLO" then
        return ("grev=%s%s"):format(tostring(message.grev), message.login and " login" or "")
    elseif messageType == "WANTG" then
        local names = {}
        if type(message.names) == "table" then for index, playerName in ipairs(message.names) do names[index] = tostring(playerName) end end
        return "names=" .. table.concat(names, ",") .. (message.via and (" via=" .. tostring(message.via)) or "")
    elseif messageType == "GAMES" then
        local gameRecord = type(message.games) == "table" and message.games or {}
        return ("owner=%s rev=%s recent=%d"):format(tostring(gameRecord.name), tostring(gameRecord.rev), Utility.Count(gameRecord.recent))
    end
    return ""
end

-- Trace: the network trace ring in addon.db.trace (/gg trace).
addon.Trace = library.Trace.New({
    entries = function()
        local database = addon.db
        if not database then return nil end
        if type(database.trace) ~= "table" then database.trace = {} end
        return database.trace
    end,
    log = addon.Log,
    summarize = summarize,
})

-- Locale: addon.Text[<english>] -> UI language; Locales/<code>.lua call addon.Locale.Register(code, { strings = {...} }).
local Locale = library.Locale.New()
addon.Locale = Locale
---@param languageCode string
---@param data? { strings: table<string, string> }
function Locale.Register(languageCode, data) Locale.RegisterStrings(languageCode, data and data.strings) end
addon.Text = Locale.Text

-- Codec and Guard for GuildGames' protocol (version read from addon.PROTOCOL_* at use time).
addon.Codec = library.Codec.New(setmetatable({}, {
    __index = function(_, field)
        if field == "major" then return addon.PROTOCOL_MAJOR end
        if field == "minor" then return addon.PROTOCOL_MINOR end
        return nil
    end,
}))
addon.Guard = library.Guard

-- Internal events: DATA_CHANGED(kind), GAMES_CHANGED, WINDOW_OPENED (handlers run protected).
addon.Events = library.Events.New(addon.Log)
