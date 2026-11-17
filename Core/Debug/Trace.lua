local addonName, addon = ...

-- Network trace (feature 008): one entry per addon message in or out, plus "sys" entries for identity checks, roster
-- prunes and incomplete transfers. Pure Lua (no WoW calls) so it is tested offline. Persisted in addon.db.trace (bounded
-- ring) so a /reload keeps the evidence; shown in the Debug tab and written into the /ts export report.
-- The trace is about MESSAGES (what went over the wire and what became of it); everything else goes to addon.Log.
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
---@field mt? string message type ("HELLO", "SNAP", ...)
---@field st string status (see above)
---@field why? string reason for the status
---@field info? string short summary of the message (never the payload)
---@field parts? integer number of chunks
---@field bytes? integer encoded size

---@class TraceModule
local Trace = {}
addon.Trace = Trace

Trace.MAXIMUM_ENTRIES = 400
---@type table<string, boolean> statuses shown by the "problems" filter
Trace.PROBLEM_STATUSES = { failed = true, dropped = true, rejected = true, error = true, warn = true }

---@type integer
local sequenceNumber = 0

-- the persisted ring, created on first use; nil before the saved data exists
---@return TraceEntry[]|nil
local function storedEntries()
    local database = addon.db
    if not database then return nil end
    if type(database.trace) ~= "table" then database.trace = {} end
    return database.trace
end

-- Adds an entry and returns it (callers may update st/why later: an outbound message is "queued" until its last chunk
-- left the pump). Strings are kept raw here; the UI escapes them before display.
---@param traceEntry TraceEntry
---@return TraceEntry
function Trace.Add(traceEntry)
    local entries = storedEntries()
    if not entries then return traceEntry end
    sequenceNumber = sequenceNumber + 1
    traceEntry.seq = sequenceNumber
    traceEntry.t = traceEntry.t or addon.Utility.Now()
    entries[#entries + 1] = traceEntry
    while #entries > Trace.MAXIMUM_ENTRIES do table.remove(entries, 1) end
    return traceEntry
end

-- A local event that belongs next to the messages (identity checks, roster prunes, incomplete transfers).
---@param status "info"|"warn"
---@param reason string
---@param information? string
---@return TraceEntry
function Trace.System(status, reason, information)
    return Trace.Add({ dir = "sys", st = status or "info", why = reason, info = information })
end

function Trace.Clear()
    local entries = storedEntries()
    if entries then for index = #entries, 1, -1 do entries[index] = nil end end
end

-- newest first
---@param filter? "all"|"in"|"out"|"sys"|"problems" nil = all
---@return TraceEntry[]
function Trace.List(filter)
    local entries = storedEntries() or {}
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

-- counts per "direction type status" for the report header
---@return table<string, integer>
function Trace.Counts()
    local countByKind = {}
    for _, traceEntry in ipairs(storedEntries() or {}) do
        if type(traceEntry) == "table" then
            local kind = ("%s %s %s"):format(tostring(traceEntry.dir), tostring(traceEntry.mt or "-"), tostring(traceEntry.st))
            countByKind[kind] = (countByKind[kind] or 0) + 1
        end
    end
    return countByKind
end

local count = addon.Utility.Count

-- Short human summary of a protocol message (never the full payload). The message fields are the wire format.
---@param message any
---@return string
function Trace.Summarize(message)
    if type(message) ~= "table" then return "?" end
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

-- UTC wall clock "hh:mm:ss" of a server timestamp
---@param timestamp any
---@return string
local function clock(timestamp)
    timestamp = tonumber(timestamp) or 0
    local secondsOfDay = timestamp % 86400
    return ("%02d:%02d:%02d"):format(math.floor(secondsOfDay / 3600), math.floor(secondsOfDay % 3600 / 60),
        math.floor(secondsOfDay % 60))
end
Trace.Clock = clock

---@type table<string, string>
local DIRECTION_ARROW = { ["in"] = "<-", out = "->", sys = "**" }

-- One plain-text line (export, chat). The UI builds its own coloured form from the same fields.
---@param traceEntry TraceEntry
---@return string
function Trace.Format(traceEntry)
    local parts = { clock(traceEntry.t), DIRECTION_ARROW[traceEntry.dir] or "?" }
    if traceEntry.ch then parts[#parts + 1] = traceEntry.ch end
    if traceEntry.peer then parts[#parts + 1] = tostring(traceEntry.peer) end
    if traceEntry.raw and traceEntry.raw ~= traceEntry.peer then parts[#parts + 1] = "(raw " .. tostring(traceEntry.raw) .. ")" end
    if traceEntry.via then parts[#parts + 1] = "(to " .. tostring(traceEntry.via) .. ")" end   -- the whisper target actually used
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

-- Load-time hygiene: the persisted ring is untrusted like everything else in SavedVariables. Keep only tables, cap size.
---@param savedVariables table
function Trace.SanitizePersisted(savedVariables)
    if type(savedVariables.trace) ~= "table" then savedVariables.trace = {} return end
    local kept = {}
    for _, traceEntry in ipairs(savedVariables.trace) do
        if type(traceEntry) == "table" then kept[#kept + 1] = traceEntry end
    end
    local droppedCount = #savedVariables.trace - #kept
    while #kept > Trace.MAXIMUM_ENTRIES do table.remove(kept, 1) end
    savedVariables.trace = kept
    if droppedCount > 0 then
        addon.Log.Warning("trace.load", "dropped stored trace entries that were not tables", { count = droppedCount })
    end
end
