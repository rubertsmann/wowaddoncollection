local addonName, addon = ...

-- THE logging helper: a LibGuildSync-1.0 Log (line format, levels and caller rules: LibGuildSync/Log.lua). Its lines are
-- stored in addon.db.debug, readable after /reload with /gg debug. Error lines are also printed to the chat frame in the
-- development build.
--   addon.Log.Error / Warning / Information / Debug (area, message, details)
--   addon.Log.Exception(area, message, errorObject, details)   addon.Log.Protected(area, message, func, ...)
---@class LogModule
addon.Log = LibStub("LibGuildSync-1.0").Log.New({
    entries = function()
        local database = addon.db
        return type(database) == "table" and type(database.debug) == "table" and database.debug or nil
    end,
    title = function() return addon.TITLE end,
    isDevelopment = function() return addon.IS_DEVELOPMENT_BUILD end,
})
