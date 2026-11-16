local ADDON, ns = ...

-- Network trace (feature 008): one entry per addon message in or out, plus "sys" entries for identity checks, roster
-- prunes and incomplete transfers. Pure Lua (no WoW calls) so it is tested offline. Persisted in ns.db.trace (bounded
-- ring) so a /reload keeps the evidence; shown in the Debug tab and written into the /ts export report.
--   entry = { seq, t, dir = "in"|"out"|"sys", ch = "GUILD"|"WHISPER"|..., peer, raw, mt (message type),
--             st (status), why (reason), info (message summary), parts (chunks), bytes }
-- Status values: out: queued -> sent | failed | dropped;  in: ok | ignored | dropped | rejected | error;  sys: info | warn
local Trace = {}
ns.Trace = Trace

Trace.MAX = 400
Trace.PROBLEM = { failed = true, dropped = true, rejected = true, error = true, warn = true }

local seq = 0

local function log()
    local db = ns.db
    if not db then return nil end
    if type(db.trace) ~= "table" then db.trace = {} end
    return db.trace
end

-- Adds an entry and returns it (callers may update st/why later: an outbound message is "queued" until its last chunk
-- left the pump). Strings are kept raw here; the UI escapes them before display.
function Trace.Add(e)
    local t = log()
    if not t then return e end
    seq = seq + 1
    e.seq = seq
    e.t = e.t or ns.Util.Now()
    t[#t + 1] = e
    while #t > Trace.MAX do table.remove(t, 1) end
    return e
end

function Trace.Sys(st, why, info)
    return Trace.Add({ dir = "sys", st = st or "info", why = why, info = info })
end

function Trace.Clear()
    local t = log()
    if t then for i = #t, 1, -1 do t[i] = nil end end
end

-- filter: nil/"all" | "in" | "out" | "sys" | "problems"; newest first
function Trace.List(filter)
    local t = log() or {}
    local out = {}
    for i = #t, 1, -1 do
        local e = t[i]
        if type(e) == "table" then
            local keep = not filter or filter == "all" or e.dir == filter
                or (filter == "problems" and Trace.PROBLEM[e.st] ~= nil)
            if keep then out[#out + 1] = e end
        end
    end
    return out
end

-- counts per "dir type status" for the report header
function Trace.Counts()
    local c = {}
    for _, e in ipairs(log() or {}) do
        if type(e) == "table" then
            local k = ("%s %s %s"):format(tostring(e.dir), tostring(e.mt or "-"), tostring(e.st))
            c[k] = (c[k] or 0) + 1
        end
    end
    return c
end

local function count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

-- Short human summary of a protocol message (never the full payload).
function Trace.Summarize(msg)
    if type(msg) ~= "table" then return "?" end
    local t = msg.t
    if t == "HELLO" then
        return ("rev=%s orev=%s odig=%d%s"):format(tostring(msg.rev), tostring(msg.orev), count(msg.odig), msg.login and " login" or "")
    elseif t == "WANT" or t == "WANTO" then
        local names = {}
        if type(msg.names) == "table" then for i, n in ipairs(msg.names) do names[i] = tostring(n) end end
        return "names=" .. table.concat(names, ",") .. (msg.via and (" via=" .. tostring(msg.via)) or "")
    elseif t == "SNAP" then
        local c = type(msg.char) == "table" and msg.char or {}
        local recipes = 0
        if type(c.professions) == "table" then
            for _, p in pairs(c.professions) do recipes = recipes + count(type(p) == "table" and p.recipes) end
        end
        return ("char=%s rev=%s recipes=%d catalog=%d"):format(tostring(c.name), tostring(c.rev), recipes, count(msg.catalog))
    elseif t == "OFFERS" then
        local o = type(msg.offers) == "table" and msg.offers or {}
        return ("owner=%s rev=%s items=%d dibs=%d"):format(tostring(o.name), tostring(o.rev), count(o.items), count(o.dibs))
    elseif t == "OPUSH" then
        return ("orders=%d"):format(count(msg.orders))
    elseif t == "ORDER" then
        local o = type(msg.order) == "table" and msg.order or {}
        return ("id=%s requester=%s recipe=%s"):format(tostring(o.id), tostring(o.requester), tostring(o.recipeID))
    end
    return ""
end

local function clock(ts)
    ts = tonumber(ts) or 0
    local d = ts % 86400
    return ("%02d:%02d:%02d"):format(math.floor(d / 3600), math.floor(d % 3600 / 60), math.floor(d % 60))
end
Trace.Clock = clock   -- UTC wall clock of a server timestamp

local ARROW = { ["in"] = "<-", out = "->", sys = "**" }

-- One plain-text line (export, chat). The UI builds its own coloured form from the same fields.
function Trace.Format(e)
    local parts = { clock(e.t), ARROW[e.dir] or "?" }
    if e.ch then parts[#parts + 1] = e.ch end
    if e.peer then parts[#parts + 1] = tostring(e.peer) end
    if e.raw and e.raw ~= e.peer then parts[#parts + 1] = "(raw " .. tostring(e.raw) .. ")" end
    if e.via then parts[#parts + 1] = "(to " .. tostring(e.via) .. ")" end   -- the whisper target actually used
    if e.mt then parts[#parts + 1] = e.mt end
    parts[#parts + 1] = "[" .. tostring(e.st) .. "]"
    if e.parts then parts[#parts + 1] = ("%dch/%dB"):format(e.parts, e.bytes or 0) end
    if e.info and e.info ~= "" then parts[#parts + 1] = e.info end
    if e.why then parts[#parts + 1] = "- " .. tostring(e.why) end
    return table.concat(parts, " ")
end

-- The name part of "Name-Realm" (used to explain a roster miss: same character name, different realm string).
function Trace.NamePart(full)
    if type(full) ~= "string" then return nil end
    return (full:match("^([^-]+)")) or full
end

-- Roster entries with the same character name as `sender` but a different full string, or nil.
function Trace.RosterLookalikes(sender, roster)
    local want = Trace.NamePart(sender)
    if not want or type(roster) ~= "table" then return nil end
    local out = {}
    for full in pairs(roster) do
        if full ~= sender and Trace.NamePart(full) == want then out[#out + 1] = full end
    end
    table.sort(out)
    return #out > 0 and out or nil
end

-- Load-time hygiene: the persisted ring is untrusted like everything else in SavedVariables. Keep only tables, cap size.
function Trace.SanitizePersisted(sv)
    if type(sv.trace) ~= "table" then sv.trace = {} return end
    local keep = {}
    for _, e in ipairs(sv.trace) do
        if type(e) == "table" then keep[#keep + 1] = e end
    end
    while #keep > Trace.MAX do table.remove(keep, 1) end
    sv.trace = keep
end
