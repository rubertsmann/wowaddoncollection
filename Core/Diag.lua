local ADDON, ns = ...

-- Diagnostic report (feature 008): one plain-text block a guild member copies from the export window (/ts export or the
-- Debug tab) and pastes to the addon author. It holds everything needed to explain a sync problem from ONE client:
-- identity (every source of "my name" and the roster's form of it), transport state, what this client holds about each
-- member, pending pulls, and the network trace. Built from plain tables, so the offline tests run it with stubs.
local Diag = {}
ns.Diag = Diag

local U = ns.Util

local function count(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function recipes(rec)
    local n = 0
    for _, p in pairs(type(rec) == "table" and rec.professions or {}) do n = n + count(type(p) == "table" and p.recipes) end
    return n
end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

------------------------------------------------------------------ name check (Debug tab "Name check", /ts ident, export)
-- One row per place a player name comes from or is turned into:
--   { method, where (code location), value (what the client returned), expected, behaviour (what the addon does with it),
--     status = "ok" | "fixed" (differs, but 0.4.1 normalizes it) | "bad" (breaks sync) | "info" | "unknown" }
-- ctx = { info = Api.IdentityInfo(), me = db.me, roster = canonical set, echo = raw sender of my own echo, seen = { [canon] = raw } }
local L = ns.L
Diag.STATUS = { "ok", "fixed", "bad", "info", "unknown" }

function Diag.StatusLabel(st)
    local map = { ok = L["OK"], fixed = L["normalized"], bad = L["PROBLEM"], info = L["info"], unknown = L["unknown"] }
    return map[st] or st
end

local function namePart(full) return type(full) == "string" and (full:match("^([^-]+)") or full) or nil end

-- how a raw spelling of MY name compares with my stored key
local function compareMine(raw, me)
    if type(raw) ~= "string" or raw == "" then return "unknown" end
    if raw == me or raw == namePart(me) then return "ok" end
    if U.Canon(raw) == me then return "fixed" end
    return "bad"
end

function Diag.IdentityRows(ctx)
    local info, me, roster = ctx.info or {}, ctx.me, ctx.roster or {}
    local rows = {}
    local function row(method, where, value, expected, behaviour, status)
        rows[#rows + 1] = { method = method, where = where, value = value == nil and "nil" or tostring(value),
            expected = expected, behaviour = behaviour, status = status }
    end
    local norm = U.MyRealm()

    row('UnitName("player")', "Core/Api.lua MyBaseName",
        tostring(info.unitName) .. (info.unitRealm and (" / " .. tostring(info.unitRealm)) or ""),
        L["character name (and on Forever the surname as 2nd value)"],
        L["first name + surname form my name; the addon appends the realm"],
        (type(info.unitName) == "string" and info.unitName ~= "" and not info.unitName:find("-", 1, true)) and "ok" or "bad")

    row("GetNormalizedRealmName()", "Core/Util.lua MyRealm", info.normalizedRealm, L["my realm, not empty, no spaces"],
        L["realm part of every stored name"],
        (type(info.normalizedRealm) == "string" and info.normalizedRealm ~= "" and not info.normalizedRealm:find(" ", 1, true)) and "ok" or "bad")

    local rn = info.realmName
    row("GetRealmName()", "Core/Util.lua IsMyRealm", rn, L["same realm as above (spaces allowed)"],
        L["accepted as another spelling of my realm"],
        type(rn) ~= "string" and "unknown" or ((norm ~= "" and U.FoldRealm(rn) == U.FoldRealm(norm)) and "ok" or "fixed"))

    row('UnitFullName("player")', "Core/Api.lua IdentityInfo", info.unitFullName, L["name / realm as above"],
        L["shown for comparison only"], "info")

    local wantMe = U.Canon(info.base or info.unitName)
    row(L["stored key (me)"], "Core/Api.lua GetPlayerInfo -> Util.Canon", me, wantMe or "?",
        L["key of my records; peers must address me by this name"],
        (me and me == wantMe) and "ok" or (me and "bad" or "unknown"))

    local rosterSt = compareMine(info.rosterMe, me)
    if info.rosterMe == nil and (info.rosterCount or 0) == 0 then rosterSt = "unknown" elseif info.rosterMe == nil then rosterSt = "bad" end
    row(L["GetGuildRosterInfo (my entry)"], "Core/Api.lua GetGuildRoster", info.rosterMe, me or "?",
        L["guild check for whispers and roster clean-up compare against this; a different realm spelling is learned"], rosterSt)

    local inRoster = me and roster[me]
    row(L["guild roster contains me"], "Core/Comm.lua PruneRoster", me and (inRoster and L["yes"] or L["NO"]) or "?", L["yes"],
        L["otherwise others drop my whispers and delete my records"],
        U.Count(roster) == 0 and "unknown" or (inRoster and "ok" or "bad"))

    row(L["CHAT_MSG_ADDON sender (my own echo)"], "Core/Comm.lua LearnFromEcho", ctx.echo, me or "?",
        L["how the server labels my messages; a different realm spelling is learned"],
        ctx.echo == nil and "unknown" or compareMine(ctx.echo, me))

    local parts, st, n = {}, "unknown", 0
    for canon, raw in pairs(ctx.seen or {}) do
        n = n + 1
        if n <= 3 then parts[#parts + 1] = raw == canon and raw or (raw .. " -> " .. canon) end
        -- worst wins: bad (not in roster) > fixed (spelled differently, normalized) > ok
        local one = (roster[canon] == nil) and "bad" or ((raw ~= canon and raw ~= namePart(canon)) and "fixed" or "ok")
        if st == "unknown" or one == "bad" or (one == "fixed" and st == "ok") then st = one end
    end
    if U.Count(roster) == 0 then st = "unknown" end
    if n > 3 then parts[#parts + 1] = "+" .. (n - 3) end
    row(L["CHAT_MSG_ADDON sender (others)"], "Core/Comm.lua OnAddonMessage", n > 0 and table.concat(parts, ", ") or nil,
        L["normalized name is in the guild roster"], L["compared with the roster and with record names"], st)

    local amb = info.ambiguated
    row('Ambiguate(me, "none")', "Core/Util.lua WhisperTarget", amb, namePart(me) or "?",
        L["0.4.0 whispered to this; 0.4.1 ignores it for my own realm"],
        amb == nil and "unknown" or (amb == namePart(me) and "ok" or "fixed"))

    local wt = me and U.WhisperTarget(me)
    row(L["whisper address for me"], "Core/Util.lua WhisperTarget", wt, namePart(me) or "?",
        L["the name others whisper to reach me"], wt == nil and "unknown" or (wt == namePart(me) and "ok" or "bad"))

    local aliases = U.RealmAliases()
    row(L["learned realm spellings"], "Core/Util.lua LearnMyRealm", #aliases > 0 and table.concat(aliases, ", ") or "-",
        L["empty when all sources agree"], L["every listed spelling counts as my realm"], #aliases > 0 and "fixed" or "ok")

    local free = U.RealmFree()
    row(L["realm in player names"], "Core/Util.lua RealmFree", free and L["ignored"] or L["compared"],
        L["ignored on Forever (guild spans several realms)"],
        L["members on other realms of the guild keep one name on every client"], free and "ok" or "info")
    return rows
end

function Diag.IdentityContext()
    return { info = ns.Api.IdentityInfo(), me = ns.db and ns.db.me, roster = ns.Comm.roster,
        echo = ns.Comm.lastEcho, seen = ns.Comm.seen }
end

function Diag.FormatIdentityRow(r)
    return ("[%s] %s | %s | %s: %s | %s: %s | %s"):format(Diag.StatusLabel(r.status), r.method, r.where, L["value"], r.value,
        L["expected"], tostring(r.expected), r.behaviour)
end

-- opts = { identity = Api.IdentityInfo() result (optional), comm = ns.Comm (optional), traceLines = n (default all) }
function Diag.Report(opts)
    opts = opts or {}
    local out = {}
    local function add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
    local db = ns.db or {}
    local now = U.Now()
    local comm = opts.comm
    local me = db.me

    add("=== TalentShare diagnostic report ===")
    add("generated: server time %d (%s UTC)", now, ns.Trace.Clock(now))
    add("addon: v%s build=%s protocol=%d.%d schema=%s prefix=%s locale=%s", tostring(ns.VERSION), tostring(ns.BUILD),
        ns.PROTO_MAJOR or 0, ns.PROTO_MINOR or 0, tostring(ns.Store and ns.Store.SCHEMA), tostring(ns.PREFIX),
        tostring(ns.Locale and ns.Locale.clientCode))
    if db.readonly then add("STORE IS READ-ONLY (saved data from a newer version)") end

    add("")
    add("--- identity ---")
    add("me (stored key): %s | whisper target others would use for me: %s", tostring(me), tostring(U.WhisperTarget(me)))
    add("my realm: %s | learned spellings of it: %s", tostring(U.MyRealm()), table.concat(U.RealmAliases(), ", "))
    local id = opts.identity
    if id then
        add("client: %s", tostring(id.build))
        add("UnitName: %s realm=%s | UnitFullName: %s", tostring(id.unitName), tostring(id.unitRealm), tostring(id.unitFullName))
        add("GetRealmName: %s | GetNormalizedRealmName: %s", tostring(id.realmName), tostring(id.normalizedRealm))
        add("built full name: %s | Ambiguate(none): %s", tostring(id.built), tostring(id.ambiguated))
        add("guild: %s | roster count (client): %s", tostring(id.guild), tostring(id.rosterCount))
        add("roster spells me as: %s", tostring(id.rosterMe))
        add("roster sample (raw): %s", table.concat(id.rosterSample or {}, ", "))
    end
    if id then
        add("")
        add("--- name check: status | method | location | value | expected | behaviour ---")
        for _, r in ipairs(Diag.IdentityRows({ info = id, me = me, roster = comm and comm.roster, echo = comm and comm.lastEcho,
            seen = comm and comm.seen })) do
            add(Diag.FormatIdentityRow(r))
        end
    end
    if comm then
        local roster = comm.roster or {}
        local inRoster = me and roster[me] and "yes" or "NO"
        add("me in cached roster: %s (cached roster %d names)", inRoster, count(roster))
        local like = me and ns.Trace.RosterLookalikes(me, roster)
        if like then add("roster names with my character name: %s", table.concat(like, ", ")) end
    end

    if comm then
        add("")
        add("--- transport ---")
        local s = comm.sync and comm.sync.stats or { sent = 0, received = 0, dropped = 0 }
        add("active=%s ready=%s messages sent=%d received=%d dropped=%d | chunks out=%d in=%d | send failures=%d | rejected chunks=%d | queue=%d chunks | incompatible peers=%d",
            tostring(comm.active), tostring(comm.ready), s.sent, s.received, s.dropped, comm.chunksSent or 0,
            comm.chunksReceived or 0, comm.sendFailures or 0, comm.rejected or 0, #(comm.queue or {}), comm.hints and comm.hints.count or 0)
        for _, b in ipairs(comm.InFlight and comm.InFlight() or {}) do
            add("incomplete transfer from %s: %d/%d chunks, %ds old", tostring(b.sender), b.got, b.total, b.age)
        end
        if comm.sync then
            for _, k in ipairs(sortedKeys(comm.sync.wanted)) do
                local w = comm.sync.wanted[k]
                add("pulled record of %s (rev %s) %ds ago", k, tostring(w.rev), now - (w.t or now))
            end
            for _, k in ipairs(sortedKeys(comm.sync.wantedO)) do
                local w = comm.sync.wantedO[k]
                add("pulled offers of %s (rev %s) %ds ago", k, tostring(w.rev), now - (w.t or now))
            end
            add("scheduled sends: %d", #(comm.sync.pending or {}))
        end
    end

    add("")
    add("--- characters held (%d) ---", count(db.chars))
    for _, name in ipairs(sortedKeys(db.chars)) do
        local rec = db.chars[name]
        add("%s%s rev=%s level=%s professions=%d recipes=%d", name, name == me and " (me)" or "", tostring(rec.rev),
            tostring(rec.level), count(rec.professions), recipes(rec))
    end
    add("catalog entries: %d", count(db.catalog))

    add("")
    add("--- offers held (%d) ---", count(db.offers))
    for _, name in ipairs(sortedKeys(db.offers)) do
        local o = db.offers[name]
        add("%s%s rev=%s items=%d dibs=%d", name, name == me and " (me)" or "", tostring(o.rev), count(o.items), count(o.dibs))
    end

    add("")
    add("--- orders held (%d) ---", count(db.orders))
    local nameFn = ns.Names and ns.Names.env and ns.Names.env.spellName
    for _, oid in ipairs(sortedKeys(db.orders)) do
        local o = db.orders[oid]
        local cat = db.catalog and db.catalog[o.recipeID]
        local spell = nameFn and nameFn(o.recipeID)
        -- where the shown recipe name comes from: the catalog (from the crafter's SNAP) or a spell lookup by recipe id
        add("%s requester=%s recipe=%s qty=%s closed=%s claims=%d | catalog name=%s | order snapshot=%s | spell lookup=%s", oid,
            tostring(o.requester), tostring(o.recipeID), tostring(o.qty), tostring(o.closed), count(o.claims),
            cat and tostring(cat.name) or "-", tostring(o.name or "-"), tostring(spell))
    end

    add("")
    add("--- trace summary ---")
    local counts = ns.Trace.Counts()
    for _, k in ipairs(sortedKeys(counts)) do add("%s: %d", k, counts[k]) end

    add("")
    local list = ns.Trace.List()
    local n = math.min(opts.traceLines or #list, #list)
    add("--- network trace (last %d of %d, oldest first; times UTC) ---", n, #list)
    add("legend: -> out, <- in, ** local event | [sent] = accepted by this client, NOT proof of delivery: compare with the")
    add("        receiver's report | [ignored] = arrived, nothing to do (reason follows) | (to X) = whisper target used")
    for i = n, 1, -1 do add(ns.Trace.Format(list[i])) end

    add("")
    local dbg = db.debug or {}
    add("--- debug log (%d) ---", #dbg)
    for i = math.max(1, #dbg - 99), #dbg do add(tostring(dbg[i])) end
    add("=== end of report ===")
    return table.concat(out, "\n")
end

-- /ts ident: the identity part only, in the chat frame
-- /ts ident: the name check table in the chat frame
ns.Slash.ident = function()
    for _, r in ipairs(Diag.IdentityRows(Diag.IdentityContext())) do print(U.Esc(Diag.FormatIdentityRow(r))) end
end

ns.Slash.export = function()
    local text = Diag.Report({ identity = ns.Api.IdentityInfo(), comm = ns.Comm })
    if ns.UI and ns.UI.ShowExport then ns.UI.ShowExport(text) else print(text) end
end
