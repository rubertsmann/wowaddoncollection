-- LibGuildSync: network trace, one instance per addon (Trace.New). One entry per addon message in or out, plus "sys"
-- entries for identity checks, roster prunes and incomplete transfers. Pure Lua. Persisted in the table options.entries()
-- returns (a bounded ring in the addon's SavedVariables) so a /reload keeps the evidence.
-- The trace is about MESSAGES (what went over the wire and what became of it); everything else goes to the Log.
-- Status values: out: queued -> sent | failed | dropped;  in: ok | ignored | dropped | rejected | error;  sys: info | warn
--
-- The short field names below are stored in SavedVariables and read by older builds' reports: they stay as they are.
---@class TraceEntry
---@field seq integer running number within this session
---@field t integer server time
---@field dir "in"|"out"|"sys" direction
---@field ch? string channel: "GUILD"|"WHISPER"|...
---@field peer? string the other player (canonical name)
---@field raw? string the sender exactly as the client reported it, when different from peer
---@field via? string the whisper target actually used
---@field mt? string message type ("HELLO", ...)
---@field st string status (see above)
---@field why? string reason for the status
---@field info? string short summary of the message (never the payload)
---@field parts? integer number of chunks
---@field bytes? integer encoded size
local lib = LibStub("LibGuildSync-1.0")
local Trace = lib:Module("Trace", 2)
if not Trace then return end

---@class TraceOptions
---@field entries fun(): TraceEntry[]|nil the persisted ring (nil while the saved data is not loaded)
---@field log table the addon's Log instance
---@field summarize? fun(message: table): string short summary of one protocol message (default: "")

Trace.MAXIMUM_ENTRIES = 400
---@type table<string, boolean> statuses shown by the "problems" filter
Trace.PROBLEM_STATUSES = { failed = true, dropped = true, rejected = true, error = true, warn = true }

---@type table<string, string>
local DIRECTION_ARROW = { ["in"] = "<-", out = "->", sys = "**" }

-- UTC wall clock "hh:mm:ss" of a server timestamp
---@param timestamp any
---@return string
function Trace.Clock(timestamp)
    timestamp = tonumber(timestamp) or 0
    local secondsOfDay = timestamp % 86400
    return ("%02d:%02d:%02d"):format(math.floor(secondsOfDay / 3600), math.floor(secondsOfDay % 3600 / 60),
        math.floor(secondsOfDay % 60))
end

-- One plain-text line (export, chat).
---@param traceEntry TraceEntry
---@return string
function Trace.Format(traceEntry)
    local parts = { Trace.Clock(traceEntry.t), DIRECTION_ARROW[traceEntry.dir] or "?" }
    if traceEntry.ch then parts[#parts + 1] = traceEntry.ch end
    if traceEntry.peer then parts[#parts + 1] = tostring(traceEntry.peer) end
    if traceEntry.raw and traceEntry.raw ~= traceEntry.peer then parts[#parts + 1] = "(raw " .. tostring(traceEntry.raw) .. ")" end
    if traceEntry.via then parts[#parts + 1] = "(to " .. tostring(traceEntry.via) .. ")" end
    if traceEntry.mt then parts[#parts + 1] = traceEntry.mt end
    parts[#parts + 1] = "[" .. tostring(traceEntry.st) .. "]"
    if traceEntry.parts then parts[#parts + 1] = ("%dch/%dB"):format(traceEntry.parts, traceEntry.bytes or 0) end
    if traceEntry.info and traceEntry.info ~= "" then parts[#parts + 1] = traceEntry.info end
    if traceEntry.why then parts[#parts + 1] = "- " .. tostring(traceEntry.why) end
    return table.concat(parts, " ")
end

-- The name part of "Name-Realm" (used to explain a roster miss: same character name, different realm string).
---@param playerName any
---@return string|nil
function Trace.NamePart(playerName)
    if type(playerName) ~= "string" then return nil end
    return (playerName:match("^([^-]+)")) or playerName
end

-- Roster entries with the same character name as `sender` but a different full string, or nil.
---@param sender string
---@param roster table<string, boolean>
---@return string[]|nil
function Trace.RosterLookalikes(sender, roster)
    local wantedName = Trace.NamePart(sender)
    if not wantedName or type(roster) ~= "table" then return nil end
    local lookalikes = {}
    for rosterName in pairs(roster) do
        if rosterName ~= sender and Trace.NamePart(rosterName) == wantedName then lookalikes[#lookalikes + 1] = rosterName end
    end
    table.sort(lookalikes)
    return #lookalikes > 0 and lookalikes or nil
end

---@param instance table
---@return TraceEntry[]|nil
local function storedEntries(instance)
    local entries = instance.options.entries()
    if type(entries) ~= "table" then return nil end
    return entries
end

-- Adds an entry and returns it (callers may update st/why later). Strings are kept raw; the UI escapes them.
---@param instance table
---@param traceEntry TraceEntry
---@return TraceEntry
function Trace.AddEntry(instance, traceEntry)
    local entries = storedEntries(instance)
    if not entries then return traceEntry end
    instance.sequenceNumber = instance.sequenceNumber + 1
    traceEntry.seq = instance.sequenceNumber
    traceEntry.t = traceEntry.t or lib.Utility.Now()
    entries[#entries + 1] = traceEntry
    while #entries > instance.MAXIMUM_ENTRIES do table.remove(entries, 1) end
    return traceEntry
end

-- newest first
---@param instance table
---@param filter? "all"|"in"|"out"|"sys"|"problems"
---@return TraceEntry[]
function Trace.ListEntries(instance, filter)
    local entries = storedEntries(instance) or {}
    local selected = {}
    for index = #entries, 1, -1 do
        local traceEntry = entries[index]
        if type(traceEntry) == "table" then
            local keep = not filter or filter == "all" or traceEntry.dir == filter
                or (filter == "problems" and Trace.PROBLEM_STATUSES[traceEntry.st] ~= nil)
            if keep then selected[#selected + 1] = traceEntry end
        end
    end
    return selected
end

-- counts per "direction type status" for a report header
---@param instance table
---@return table<string, integer>
function Trace.CountEntries(instance)
    local countByKind = {}
    for _, traceEntry in ipairs(storedEntries(instance) or {}) do
        if type(traceEntry) == "table" then
            local kind = ("%s %s %s"):format(tostring(traceEntry.dir), tostring(traceEntry.mt or "-"), tostring(traceEntry.st))
            countByKind[kind] = (countByKind[kind] or 0) + 1
        end
    end
    return countByKind
end

-- Load-time hygiene: the persisted ring is untrusted like everything else in SavedVariables. Keep only tables, cap size.
---@param instance table
---@param savedVariables table holds the ring under `trace`
function Trace.SanitizeStored(instance, savedVariables)
    if type(savedVariables.trace) ~= "table" then savedVariables.trace = {} return end
    local kept = {}
    for _, traceEntry in ipairs(savedVariables.trace) do
        if type(traceEntry) == "table" then kept[#kept + 1] = traceEntry end
    end
    local droppedCount = #savedVariables.trace - #kept
    while #kept > instance.MAXIMUM_ENTRIES do table.remove(kept, 1) end
    savedVariables.trace = kept
    if droppedCount > 0 then
        instance.options.log.Warning("trace.load", "dropped stored trace entries that were not tables", { count = droppedCount })
    end
end

-- A trace for one addon; functions are called with a dot (trace.Add(entry)).
---@param options TraceOptions
---@return table trace
function Trace.New(options)
    local instance = { options = options, sequenceNumber = 0, MAXIMUM_ENTRIES = Trace.MAXIMUM_ENTRIES,
        PROBLEM_STATUSES = Trace.PROBLEM_STATUSES, Clock = Trace.Clock, Format = Trace.Format, NamePart = Trace.NamePart,
        RosterLookalikes = Trace.RosterLookalikes }
    function instance.Add(traceEntry) return Trace.AddEntry(instance, traceEntry) end
    function instance.System(status, reason, information)
        return Trace.AddEntry(instance, { dir = "sys", st = status or "info", why = reason, info = information })
    end
    function instance.Clear()
        local entries = storedEntries(instance)
        if entries then for index = #entries, 1, -1 do entries[index] = nil end end
    end
    function instance.List(filter) return Trace.ListEntries(instance, filter) end
    function instance.Counts() return Trace.CountEntries(instance) end
    function instance.Summarize(message)
        if type(message) ~= "table" then return "?" end
        if not instance.options.summarize then return "" end
        return instance.options.summarize(message)
    end
    function instance.SanitizePersisted(savedVariables) return Trace.SanitizeStored(instance, savedVariables) end
    return instance
end
