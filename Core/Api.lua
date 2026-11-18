local addonName, addon = ...

-- The ONLY file of this addon that calls WoW client functions for game logic: random numbers, sounds, and (through
-- LibGuildSync's Guild) my identity and the guild roster. Every call is guarded: a missing API never breaks a play.
---@class ApiModule
local Api = {}
addon.Api = Api

local Guild = LibStub("LibGuildSync-1.0").Guild

---@return boolean
function Api.IsGuilded() return Guild.IsGuilded() end
---@return PlayerInformation
function Api.GetPlayerInformation() return Guild.GetPlayerInformation() end
function Api.RequestRoster() return Guild.RequestRoster() end
---@return table<string, boolean>
function Api.GetGuildRoster() return Guild.GetGuildRoster() end

-- A number in [0, 1) for game outcomes (Games.Flip and Slots.Spin take it as their random function; tests inject their own).
---@return number
function Api.Random() return math.random() end

-- The coin sound played on a won flip, or nil when this client has no such sound kit.
---@return integer|nil
function Api.CoinSoundKit()
    return SOUNDKIT and (SOUNDKIT.LOOT_WINDOW_COIN_SOUND or SOUNDKIT.IG_BACKPACK_COIN_SELECT) or nil
end

-- The first of `soundNames` this client's SOUNDKIT table has, or nil.
---@param soundNames string[]
---@return integer|nil
function Api.SoundKitFor(soundNames)
    if not SOUNDKIT then return nil end
    for _, soundName in ipairs(soundNames) do
        if SOUNDKIT[soundName] then return SOUNDKIT[soundName] end
    end
    return nil
end

-- Plays a sound kit; never raises (a missing sound must not break a play).
---@param soundKitID integer|nil
function Api.PlaySound(soundKitID)
    if soundKitID and PlaySound then
        local ok, errorMessage = pcall(PlaySound, soundKitID)
        if not ok then addon.Log.Debug("api.call", "a client function raised an error", { call = "PlaySound", error = tostring(errorMessage) }) end
    end
end
