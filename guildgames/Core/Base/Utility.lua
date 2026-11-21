local addonName, addon = ...

-- Shared helpers (player names and realms, tables, untrusted input, UTF-8 text) live in LibGuildSync-1.0 (Utility.lua),
-- shared with every addon that embeds it. This table reads everything from there and adds what is GuildGames' own: who
-- "me" is in GuildGames' saved data.
---@class UtilityModule
local Utility = setmetatable({}, { __index = LibStub("LibGuildSync-1.0").Utility })
addon.Utility = Utility

-- My "Name-Realm": the stored identity, else the client's (before Store.Init or PLAYER_LOGIN). nil when neither is known.
---@return string|nil
function Utility.Me()
    local database = addon.Store and addon.Store.db   -- nil before Store.Init
    if database and database.me then return database.me end
    -- Api is client-only: the offline tests run this without it
    local playerInformation = addon.Api and addon.Api.GetPlayerInformation()
    return playerInformation and playerInformation.name
end

-- `value` limited to [lowest, highest]; NaN counts as `lowest` (it compares false with everything and would pass through).
---@param value number
---@param lowest number
---@param highest number
---@return number
function Utility.Clamp(value, lowest, highest)
    if value ~= value or value < lowest then return lowest end
    if value > highest then return highest end
    return value
end

-- `text` cut to at most `maximumCharacters` UTF-8 characters, with "…" at the end when it was cut (user 2026-11-21:
-- long pet names broke the layout). Use it before Escape. Not a string: "".
---@param text any
---@param maximumCharacters integer
---@return string
function Utility.ShortText(text, maximumCharacters)
    if type(text) ~= "string" then return "" end
    local starts = {}
    for position in text:gmatch("()[^\128-\191][\128-\191]*") do
        starts[#starts + 1] = position
        if #starts > maximumCharacters then return text:sub(1, starts[maximumCharacters] - 1) .. "…" end
    end
    return text
end
