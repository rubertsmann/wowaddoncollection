local addonName, addon = ...

-- Network trace: a LibGuildSync-1.0 Trace (entry fields and statuses: LibGuildSync/Trace.lua). One entry per addon
-- message in or out, plus "sys" entries for identity checks and roster prunes. Persisted in addon.db.trace (bounded ring)
-- so a /reload keeps the evidence; read it with /gg trace. What is GuildGames' own here: the one-line summary of each of
-- its message types.

-- Short human summary of a protocol message (never the payload). The message fields are the wire format.
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
        return ("owner=%s rev=%s recent=%d"):format(tostring(gameRecord.name), tostring(gameRecord.rev),
            addon.Utility.Count(gameRecord.recent))
    end
    return ""
end

---@class TraceModule
addon.Trace = LibStub("LibGuildSync-1.0").Trace.New({
    entries = function()
        local database = addon.db
        if not database then return nil end
        if type(database.trace) ~= "table" then database.trace = {} end
        return database.trace
    end,
    log = addon.Log,
    summarize = summarize,
})
