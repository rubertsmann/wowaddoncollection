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
