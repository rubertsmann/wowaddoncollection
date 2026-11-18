local addonName, addon = ...

-- Network trace (feature 008): a LibGuildSync-1.0 Trace (entry fields and statuses: LibGuildSync/Trace.lua). One entry per
-- addon message in or out, plus "sys" entries for identity checks, roster prunes and incomplete transfers. Persisted in
-- addon.db.trace (bounded ring) so a /reload keeps the evidence; shown in the Debug tab and the /ts export report.
-- What is TalentShare's own here: the one-line summary of each of its message types.

local count = addon.Utility.Count

-- Short human summary of a protocol message (never the full payload). The message fields are the wire format.
---@param message any
---@return string
local function summarize(message)
    local messageType = message.t
    if messageType == "HELLO" then
        return ("rev=%s orev=%s odig=%d%s"):format(tostring(message.rev), tostring(message.orev), count(message.odig),
            message.login and " login" or "")
    elseif messageType == "WANT" or messageType == "WANTO" then
        local names = {}
        if type(message.names) == "table" then for index, playerName in ipairs(message.names) do names[index] = tostring(playerName) end end
        return "names=" .. table.concat(names, ",") .. (message.via and (" via=" .. tostring(message.via)) or "")
    elseif messageType == "SNAP" then
        local characterRecord = type(message.char) == "table" and message.char or {}
        local recipeCount = addon.Store.RecipeCount(characterRecord)
        return ("char=%s rev=%s recipes=%d catalog=%d"):format(tostring(characterRecord.name), tostring(characterRecord.rev),
            recipeCount, count(message.catalog))
    elseif messageType == "OFFERS" then
        local offerRecord = type(message.offers) == "table" and message.offers or {}
        return ("owner=%s rev=%s items=%d dibs=%d"):format(tostring(offerRecord.name), tostring(offerRecord.rev),
            count(offerRecord.items), count(offerRecord.dibs))
    elseif messageType == "OPUSH" then
        return ("orders=%d"):format(count(message.orders))
    elseif messageType == "ORDER" then
        local order = type(message.order) == "table" and message.order or {}
        return ("id=%s requester=%s recipe=%s"):format(tostring(order.id), tostring(order.requester), tostring(order.recipeID))
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
