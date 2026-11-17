local addonName, addon = ...

-- THE logging helper. There is no live debugger in the game client: this log (and the network trace in Trace.lua) is the
-- only evidence of what happened on a player's machine. Every module writes through these functions, never through
-- print() or a hand-made string, so every line has the same shape and can be read the same way:
--
--   <date time> <LEVEL> [<area>] <message> :: <key>=<value> <key>=<value> ...
--   2026-11-17 10:42:07 ERROR [communication.send] the client refused an addon message :: channel=GUILD reason=... target=-
--
-- Rules for callers:
--   * area    = "<module>.<operation>" in lower camelCase, e.g. "store.load", "scanner.profession", "window.craft".
--               The module part is the file name; grep for the area to find the code that wrote the line.
--   * message = one plain sentence: WHAT happened (not where; the area says where). No values pasted into it.
--   * details = a table of the values needed to understand the line (ids, names, counts, the error). Never a long dump.
--   * Error       : something failed and a feature did not do its job (a send was refused, a scan threw, data dropped).
--   * Warning     : something unexpected that was handled (a fallback was used, input was rejected, a limit was hit).
--   * Information : a normal but noteworthy step (a scan found changes, a version reset, a window opened).
--   * Debug       : detail that is only useful while chasing a specific problem (every click, every probe).
--   * Exception   : a caught Lua error. Logs it as Error with the stack and also hands it to the game's error handler
--                   (shown with /console scriptErrors 1), because a swallowed error is invisible otherwise.
--   * Protected   : pcall that logs a failure through Exception. Use it wherever an error must not stop the caller.
--
-- Storage: the newest MAXIMUM_ENTRIES lines in SavedVariables (addon.db.debug: the key is kept for saved-data
-- compatibility), readable after /reload with /ts debug and in the /ts export report. The same line repeated right after
-- itself is stored once with a repeat count, so a hot loop cannot push everything else out. Peer text is escaped ("|"
-- would start a colour or link code when /ts debug prints the line to the chat frame). Error lines are also printed to the
-- chat frame in the development build.

---@alias LogLevel "ERROR"|"WARNING"|"INFORMATION"|"DEBUG"

---@class LogModule
local Log = {}
addon.Log = Log

Log.MAXIMUM_ENTRIES = 300
Log.MAXIMUM_VALUE_LENGTH = 200

---@type string|nil the last stored line without its time stamp and repeat count, to fold repeats
local lastLineBody = nil
---@type integer how often lastLineBody was repeated
local lastLineRepeats = 0

---@param seconds number
---@return string
local function formatTime(seconds)
    if type(date) == "function" then
        local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S", seconds)
        if ok and type(formatted) == "string" then return formatted end
    end
    if os and type(os.date) == "function" then return os.date("%Y-%m-%d %H:%M:%S", seconds) end
    return tostring(seconds)
end

---@param value any
---@return string
local function formatValue(value)
    local text = type(value) == "string" and value or tostring(value)
    text = text:gsub("[\r\n]+", " / ")
    if #text > Log.MAXIMUM_VALUE_LENGTH then
        text = addon.Utility.TruncateUtf8(text, Log.MAXIMUM_VALUE_LENGTH) .. "..."
    end
    return addon.Utility.Escape(text)
end

-- "key=value key=value" in a stable (sorted) key order; nil or an empty table gives ""
---@param details table<string, any>|nil
---@return string
local function formatDetails(details)
    if type(details) ~= "table" then return "" end
    local parts = {}
    for _, key in ipairs(addon.Utility.SortedKeys(details)) do
        parts[#parts + 1] = tostring(key) .. "=" .. formatValue(details[key])
    end
    return table.concat(parts, " ")
end

-- The line without its time stamp (also used by the tests).
---@param level LogLevel
---@param area string
---@param message string
---@param details table<string, any>|nil
---@return string
function Log.FormatBody(level, area, message, details)
    local body = ("%s [%s] %s"):format(level, tostring(area), formatValue(message))
    local detailText = formatDetails(details)
    if detailText ~= "" then body = body .. " :: " .. detailText end
    return body
end

---@param level LogLevel
---@param area string
---@param message string
---@param details table<string, any>|nil
---@return string body the stored line without the time stamp
local function write(level, area, message, details)
    local body = Log.FormatBody(level, area, message, details)
    local database = addon.db
    if type(database) == "table" and type(database.debug) == "table" then
        local entries = database.debug
        if body == lastLineBody and #entries > 0 then
            lastLineRepeats = lastLineRepeats + 1
            entries[#entries] = formatTime(addon.Utility.Now()) .. " " .. body .. (" (repeated %d times)"):format(lastLineRepeats + 1)
        else
            lastLineBody, lastLineRepeats = body, 0
            entries[#entries + 1] = formatTime(addon.Utility.Now()) .. " " .. body
            while #entries > Log.MAXIMUM_ENTRIES do table.remove(entries, 1) end
        end
    end
    if level == "ERROR" and addon.IS_DEVELOPMENT_BUILD and type(print) == "function" then
        print("|cffff4040" .. tostring(addon.TITLE) .. " error|r " .. body)
    end
    return body
end

---@param area string "<module>.<operation>"
---@param message string what failed, one sentence
---@param details? table<string, any>
---@return string body
function Log.Error(area, message, details) return write("ERROR", area, message, details) end

---@param area string "<module>.<operation>"
---@param message string what was unexpected, one sentence
---@param details? table<string, any>
---@return string body
function Log.Warning(area, message, details) return write("WARNING", area, message, details) end

---@param area string "<module>.<operation>"
---@param message string what happened, one sentence
---@param details? table<string, any>
---@return string body
function Log.Information(area, message, details) return write("INFORMATION", area, message, details) end

---@param area string "<module>.<operation>"
---@param message string what happened, one sentence
---@param details? table<string, any>
---@return string body
function Log.Debug(area, message, details) return write("DEBUG", area, message, details) end

-- A caught Lua error: logged as ERROR with the error text and the stack, then forwarded to the game's error handler.
---@param area string "<module>.<operation>"
---@param message string what the failing code was trying to do
---@param errorObject any the value pcall returned
---@param details? table<string, any>
---@param stack? string a stack trace taken where the error was caught (xpcall handler); taken here when omitted
---@return string body
function Log.Exception(area, message, errorObject, details, stack)
    local merged = {}
    for key, value in pairs(details or {}) do merged[key] = value end
    merged.error = tostring(errorObject)
    if not stack then
        stack = (type(debugstack) == "function" and debugstack(2, 6, 0))
            or (debug and type(debug.traceback) == "function" and debug.traceback("", 2)) or nil
    end
    if stack then merged.stack = stack end
    local body = write("ERROR", area, message, merged)
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    if handler then pcall(handler, ("%s %s: %s"):format(tostring(addon.TITLE), tostring(area), tostring(errorObject))) end
    return body
end

-- pcall(func, ...) that logs a failure through Log.Exception (with the stack of the failing code).
-- Returns exactly what pcall returns: true and the results, or false and the error.
---@param area string "<module>.<operation>"
---@param message string what func does, for the log line when it fails
---@param func function
---@param ... any arguments for func
---@return boolean ok
---@return any ...
function Log.Protected(area, message, func, ...)
    local stack
    local function handler(errorObject)
        stack = (type(debugstack) == "function" and debugstack(2, 8, 0))
            or (debug and type(debug.traceback) == "function" and debug.traceback("", 2)) or nil
        return errorObject
    end
    local argumentCount, arguments = select("#", ...), { ... }
    local results = { xpcall(function() return func(unpack(arguments, 1, argumentCount)) end, handler) }
    if not results[1] then Log.Exception(area, message, results[2], nil, stack) end
    return unpack(results, 1, table.maxn(results))
end

-- Forget the repeat-folding state (tests; /ts clean empties the stored lines).
function Log.Reset()
    lastLineBody, lastLineRepeats = nil, 0
end
