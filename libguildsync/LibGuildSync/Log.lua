-- LibGuildSync: THE logging helper, one instance per addon (Log.New). There is no live debugger in the game client: this
-- log (and the network trace, Trace.lua) is the only evidence of what happened on a player's machine. Every line has the
-- same shape:
--
--   <date time> <LEVEL> [<area>] <message> :: <key>=<value> <key>=<value> ...
--   2026-11-17 10:42:07 ERROR [communication.send] the client refused an addon message :: channel=GUILD reason=... target=-
--
-- Rules for callers:
--   * area    = "<module>.<operation>" in lower camelCase, e.g. "store.load", "scanner.profession", "window.craft".
--   * message = one plain sentence: WHAT happened (not where; the area says where). No values pasted into it.
--   * details = a table of the values needed to understand the line (ids, names, counts, the error). Never a long dump.
--   * Error       : something failed and a feature did not do its job.
--   * Warning     : something unexpected that was handled (a fallback was used, input was rejected, a limit was hit).
--   * Information : a normal but noteworthy step.
--   * Debug       : detail that is only useful while chasing a specific problem.
--   * Exception   : a caught Lua error. Logged as Error with the stack and handed to the game's error handler.
--   * Protected   : pcall that logs a failure through Exception.
--
-- Storage: the newest MAXIMUM_ENTRIES lines in the table options.entries() returns (the addon's SavedVariables). The same
-- line repeated right after itself is stored once with a repeat count. Peer text is escaped. Error lines are also printed
-- to the chat frame in a development build.
local lib = LibStub("LibGuildSync-1.0")
local Log = lib:Module("Log", 1)
if not Log then return end

---@alias LogLevel "ERROR"|"WARNING"|"INFORMATION"|"DEBUG"

---@class LogOptions
---@field entries fun(): string[]|nil the stored lines (nil while the saved data is not loaded)
---@field title string|fun(): string shown in front of printed errors
---@field isDevelopment? boolean|fun(): boolean print ERROR lines to the chat frame

---@class LogInstance
---@field MAXIMUM_ENTRIES integer
---@field MAXIMUM_VALUE_LENGTH integer
---@field options LogOptions
---@field lastLineBody string|nil
---@field lastLineRepeats integer

Log.MAXIMUM_ENTRIES = 300
Log.MAXIMUM_VALUE_LENGTH = 200

---@param value any
---@return any
local function resolve(value)
    if type(value) == "function" then return value() end
    return value
end

---@param seconds number
---@return string
function Log.FormatTime(seconds)
    if type(date) == "function" then
        local ok, formatted = pcall(date, "%Y-%m-%d %H:%M:%S", seconds)
        if ok and type(formatted) == "string" then return formatted end
    end
    if os and type(os.date) == "function" then return os.date("%Y-%m-%d %H:%M:%S", seconds) end
    return tostring(seconds)
end

---@param instance LogInstance
---@param value any
---@return string
function Log.FormatValue(instance, value)
    local Utility = lib.Utility
    local text = type(value) == "string" and value or tostring(value)
    text = text:gsub("[\r\n]+", " / ")
    if #text > instance.MAXIMUM_VALUE_LENGTH then
        text = Utility.TruncateUtf8(text, instance.MAXIMUM_VALUE_LENGTH) .. "..."
    end
    return Utility.Escape(text)
end

-- The line without its time stamp: "LEVEL [area] message :: key=value ..." (details in sorted key order).
---@param instance LogInstance
---@param level LogLevel
---@param area string
---@param message string
---@param details table<string, any>|nil
---@return string
function Log.Body(instance, level, area, message, details)
    local body = ("%s [%s] %s"):format(level, tostring(area), Log.FormatValue(instance, message))
    if type(details) == "table" then
        local parts = {}
        for _, key in ipairs(lib.Utility.SortedKeys(details)) do
            parts[#parts + 1] = tostring(key) .. "=" .. Log.FormatValue(instance, details[key])
        end
        if #parts > 0 then body = body .. " :: " .. table.concat(parts, " ") end
    end
    return body
end

---@param instance LogInstance
---@param level LogLevel
---@param area string
---@param message string
---@param details table<string, any>|nil
---@return string body the stored line without the time stamp
function Log.Write(instance, level, area, message, details)
    local body = Log.Body(instance, level, area, message, details)
    local entries = instance.options.entries()
    if type(entries) == "table" then
        local stamp = Log.FormatTime(lib.Utility.Now())
        if body == instance.lastLineBody and #entries > 0 then
            instance.lastLineRepeats = instance.lastLineRepeats + 1
            entries[#entries] = stamp .. " " .. body .. (" (repeated %d times)"):format(instance.lastLineRepeats + 1)
        else
            instance.lastLineBody, instance.lastLineRepeats = body, 0
            entries[#entries + 1] = stamp .. " " .. body
            while #entries > instance.MAXIMUM_ENTRIES do table.remove(entries, 1) end
        end
    end
    if level == "ERROR" and resolve(instance.options.isDevelopment) and type(print) == "function" then
        print("|cffff4040" .. tostring(resolve(instance.options.title)) .. " error|r " .. body)
    end
    return body
end

---@param instance LogInstance
---@param area string
---@param message string
---@param errorObject any
---@param details? table<string, any>
---@param stack? string
---@return string body
function Log.WriteException(instance, area, message, errorObject, details, stack)
    local merged = {}
    for key, value in pairs(details or {}) do merged[key] = value end
    merged.error = tostring(errorObject)
    if not stack then
        stack = (type(debugstack) == "function" and debugstack(3, 6, 0))
            or (debug and type(debug.traceback) == "function" and debug.traceback("", 3)) or nil
    end
    if stack then merged.stack = stack end
    local body = Log.Write(instance, "ERROR", area, message, merged)
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    if handler then pcall(handler, ("%s %s: %s"):format(tostring(resolve(instance.options.title)), tostring(area), tostring(errorObject))) end
    return body
end

---@param instance LogInstance
---@param area string
---@param message string
---@param func function
---@param ... any
---@return boolean ok
---@return any ...
function Log.RunProtected(instance, area, message, func, ...)
    local stack
    local function handler(errorObject)
        stack = (type(debugstack) == "function" and debugstack(2, 8, 0))
            or (debug and type(debug.traceback) == "function" and debug.traceback("", 2)) or nil
        return errorObject
    end
    local argumentCount, arguments = select("#", ...), { ... }
    local results = { xpcall(function() return func(unpack(arguments, 1, argumentCount)) end, handler) }
    if not results[1] then Log.WriteException(instance, area, message, results[2], nil, stack) end
    return unpack(results, 1, table.maxn(results))
end

-- A log for one addon. Its functions are called with a dot (log.Error(area, message, details)); they look the code up
-- on the module at call time, so a library upgrade reaches logs created before it.
---@param options LogOptions
---@return table log with Error, Warning, Information, Debug, Exception, Protected, FormatBody, Reset
function Log.New(options)
    local instance = { options = options, MAXIMUM_ENTRIES = Log.MAXIMUM_ENTRIES, MAXIMUM_VALUE_LENGTH = Log.MAXIMUM_VALUE_LENGTH,
        lastLineBody = nil, lastLineRepeats = 0 }
    function instance.FormatBody(level, area, message, details) return Log.Body(instance, level, area, message, details) end
    function instance.Error(area, message, details) return Log.Write(instance, "ERROR", area, message, details) end
    function instance.Warning(area, message, details) return Log.Write(instance, "WARNING", area, message, details) end
    function instance.Information(area, message, details) return Log.Write(instance, "INFORMATION", area, message, details) end
    function instance.Debug(area, message, details) return Log.Write(instance, "DEBUG", area, message, details) end
    function instance.Exception(area, message, errorObject, details, stack)
        return Log.WriteException(instance, area, message, errorObject, details, stack)
    end
    function instance.Protected(area, message, func, ...) return Log.RunProtected(instance, area, message, func, ...) end
    -- forget the repeat-folding state (tests; a "clean" command empties the stored lines)
    function instance.Reset() instance.lastLineBody, instance.lastLineRepeats = nil, 0 end
    return instance
end
