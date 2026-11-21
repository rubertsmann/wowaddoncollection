local addonName, addon = ...

-- Diagnostic report (feature 008): one plain-text block a guild member copies from the export window (/ps export or the
-- Debug tab) and pastes to the addon author. It holds everything needed to explain a sync problem from ONE client:
-- identity (every source of "my name" and the roster's form of it), transport state, what this client holds about each
-- member, pending pulls, the network trace and the log. Built from plain tables, so the offline tests run it with stubs.
---@class DiagnosticsModule
local Diagnostics = {}
addon.Diagnostics = Diagnostics

local Utility = addon.Utility
local Text = addon.Text
local count = Utility.Count
local sortedKeys = Utility.SortedKeys

------------------------------------------------------------------ name check (Debug tab "Name check", /ps ident, export)
-- One row per place a player name comes from or is turned into.

---@alias IdentityStatus "ok"|"fixed"|"bad"|"info"|"unknown"
-- ok, fixed (differs, but 0.4.1 normalizes it), bad (breaks sync), info, unknown

---@class IdentityRow
---@field method string the client call or source
---@field where string code location that uses it
---@field value string what the client returned
---@field expected string
---@field behaviour string what the addon does with it
---@field status IdentityStatus

---@class IdentityContext
---@field identity table Api.IdentityInformation()
---@field me string|nil the stored key
---@field roster table<string, boolean>|nil canonical roster set
---@field echo string|nil raw sender of my own echo
---@field seen table<string, string>|nil canonical -> raw sender spellings

---@type IdentityStatus[]
Diagnostics.STATUS = { "ok", "fixed", "bad", "info", "unknown" }

---@param status IdentityStatus|string
---@return string
function Diagnostics.StatusLabel(status)
    local labels = { ok = Text["OK"], fixed = Text["normalized"], bad = Text["PROBLEM"], info = Text["info"], unknown = Text["unknown"] }
    return labels[status] or status
end

---@param playerName any
---@return string|nil
local function namePart(playerName) return type(playerName) == "string" and (playerName:match("^([^-]+)") or playerName) or nil end

-- how a raw spelling of MY name compares with my stored key
---@param rawName any
---@param myName string|nil
---@return IdentityStatus
local function compareWithMyName(rawName, myName)
    if type(rawName) ~= "string" or rawName == "" then return "unknown" end
    if rawName == myName or rawName == namePart(myName) then return "ok" end
    if Utility.CanonicalName(rawName) == myName then return "fixed" end
    return "bad"
end

---@param context IdentityContext
---@return IdentityRow[]
function Diagnostics.IdentityRows(context)
    local identity, myName, roster = context.identity or {}, context.me, context.roster or {}
    local rows = {}
    local function addRow(method, where, value, expected, behaviour, status)
        rows[#rows + 1] = { method = method, where = where, value = value == nil and "nil" or tostring(value),
            expected = expected, behaviour = behaviour, status = status }
    end
    local normalizedRealm = Utility.MyRealm()

    addRow('UnitName("player")', "Core/Game/Api.lua MyBaseName",
        tostring(identity.unitName) .. (identity.unitRealm and (" / " .. tostring(identity.unitRealm)) or ""),
        Text["character name (and on Forever the surname as 2nd value)"],
        Text["first name + surname form my name; the addon appends the realm"],
        (type(identity.unitName) == "string" and identity.unitName ~= "" and not identity.unitName:find("-", 1, true)) and "ok" or "bad")

    -- WoW Forever (seen 2026-11-21): the client may report no realm at all (both realm calls return nothing). With realm-free
    -- names (surnames, or a roster without realm suffixes) nothing needs it: every name is kept without a realm. A problem
    -- only where names do carry realms.
    local realmMissing = identity.normalizedRealm == nil or identity.normalizedRealm == ""
    local realmStatus = (type(identity.normalizedRealm) == "string" and identity.normalizedRealm ~= ""
        and not identity.normalizedRealm:find(" ", 1, true)) and "ok" or "bad"
    if realmMissing and Utility.RealmFree() then realmStatus = "fixed" end
    addRow("GetNormalizedRealmName()", "Core/Base/Utility.lua MyRealm", identity.normalizedRealm, Text["my realm, not empty, no spaces"],
        realmStatus == "fixed" and Text["no realm on this client: names are kept without a realm"] or Text["realm part of every stored name"],
        realmStatus)

    local clientRealm = identity.realmName
    addRow("GetRealmName()", "Core/Base/Utility.lua IsMyRealm", clientRealm, Text["same realm as above (spaces allowed)"],
        Text["accepted as another spelling of my realm"],
        type(clientRealm) ~= "string" and "unknown"
            or ((normalizedRealm ~= "" and Utility.FoldRealm(clientRealm) == Utility.FoldRealm(normalizedRealm)) and "ok" or "fixed"))

    addRow('UnitFullName("player")', "Core/Game/Api.lua IdentityInformation", identity.unitFullName, Text["name / realm as above"],
        Text["shown for comparison only"], "info")

    local expectedKey = Utility.CanonicalName(identity.base or identity.unitName)
    addRow(Text["stored key (me)"], "Core/Game/Api.lua GetPlayerInformation -> Utility.CanonicalName", myName, expectedKey or "?",
        Text["key of my records; peers must address me by this name"],
        (myName and myName == expectedKey) and "ok" or (myName and "bad" or "unknown"))

    local rosterStatus = compareWithMyName(identity.rosterMe, myName)
    if identity.rosterMe == nil and (identity.rosterCount or 0) == 0 then rosterStatus = "unknown"
    elseif identity.rosterMe == nil then rosterStatus = "bad" end
    addRow(Text["GetGuildRosterInfo (my entry)"], "Core/Game/Api.lua GetGuildRoster", identity.rosterMe, myName or "?",
        Text["guild check for whispers and roster clean-up compare against this; a different realm spelling is learned"], rosterStatus)

    local inRoster = myName and roster[myName]
    addRow(Text["guild roster contains me"], "Core/Net/Communication.lua PruneRoster",
        myName and (inRoster and Text["yes"] or Text["NO"]) or "?", Text["yes"],
        Text["otherwise others drop my whispers and delete my records"],
        count(roster) == 0 and "unknown" or (inRoster and "ok" or "bad"))

    addRow(Text["CHAT_MSG_ADDON sender (my own echo)"], "Core/Net/Communication.lua LearnFromEcho", context.echo, myName or "?",
        Text["how the server labels my messages; a different realm spelling is learned"],
        context.echo == nil and "unknown" or compareWithMyName(context.echo, myName))

    local samples, sendersStatus, senderCount = {}, "unknown", 0
    for canonicalSender, rawSender in pairs(context.seen or {}) do
        senderCount = senderCount + 1
        if senderCount <= 3 then samples[#samples + 1] = rawSender == canonicalSender and rawSender or (rawSender .. " -> " .. canonicalSender) end
        -- worst wins: bad (not in roster) > fixed (spelled differently, normalized) > ok
        local senderStatus = (roster[canonicalSender] == nil) and "bad"
            or ((rawSender ~= canonicalSender and rawSender ~= namePart(canonicalSender)) and "fixed" or "ok")
        if sendersStatus == "unknown" or senderStatus == "bad" or (senderStatus == "fixed" and sendersStatus == "ok") then
            sendersStatus = senderStatus
        end
    end
    if count(roster) == 0 then sendersStatus = "unknown" end
    if senderCount > 3 then samples[#samples + 1] = "+" .. (senderCount - 3) end
    addRow(Text["CHAT_MSG_ADDON sender (others)"], "Core/Net/Communication.lua OnAddonMessage",
        senderCount > 0 and table.concat(samples, ", ") or nil,
        Text["normalized name is in the guild roster"], Text["compared with the roster and with record names"], sendersStatus)

    local ambiguatedName = identity.ambiguated
    addRow('Ambiguate(me, "none")', "Core/Base/Utility.lua WhisperTarget", ambiguatedName, namePart(myName) or "?",
        Text["0.4.0 whispered to this; 0.4.1 ignores it for my own realm"],
        ambiguatedName == nil and "unknown" or (ambiguatedName == namePart(myName) and "ok" or "fixed"))

    local whisperTarget = myName and Utility.WhisperTarget(myName)
    addRow(Text["whisper address for me"], "Core/Base/Utility.lua WhisperTarget", whisperTarget, namePart(myName) or "?",
        Text["the name others whisper to reach me"],
        whisperTarget == nil and "unknown" or (whisperTarget == namePart(myName) and "ok" or "bad"))

    local realmAliases = Utility.RealmAliases()
    addRow(Text["learned realm spellings"], "Core/Base/Utility.lua LearnMyRealm", #realmAliases > 0 and table.concat(realmAliases, ", ") or "-",
        Text["empty when all sources agree"], Text["every listed spelling counts as my realm"], #realmAliases > 0 and "fixed" or "ok")

    local realmFree = Utility.RealmFree()
    addRow(Text["realm in player names"], "Core/Base/Utility.lua RealmFree", realmFree and Text["ignored"] or Text["compared"],
        Text["ignored on Forever (guild spans several realms)"],
        Text["members on other realms of the guild keep one name on every client"], realmFree and "ok" or "info")
    return rows
end

---@return IdentityContext
function Diagnostics.IdentityContext()
    return { identity = addon.Api.IdentityInformation(), me = addon.db and addon.db.me, roster = addon.Communication.roster,
        echo = addon.Communication.lastEcho, seen = addon.Communication.seen }
end

---@param row IdentityRow
---@return string
function Diagnostics.FormatIdentityRow(row)
    return ("[%s] %s | %s | %s: %s | %s: %s | %s"):format(Diagnostics.StatusLabel(row.status), row.method, row.where,
        Text["value"], row.value, Text["expected"], tostring(row.expected), row.behaviour)
end

---@class ReportOptions
---@field identity? table Api.IdentityInformation() result
---@field communication? CommunicationModule
---@field traceLines? integer default all

---@param options? ReportOptions
---@return string
function Diagnostics.Report(options)
    options = options or {}
    local lines = {}
    ---@param template string
    local function addLine(template, ...)
        lines[#lines + 1] = select("#", ...) > 0 and template:format(...) or template
    end
    local database = addon.db or {}
    local now = Utility.Now()
    local communication = options.communication
    local myName = database.me

    addLine("=== ProfessionShare diagnostic report ===")
    addLine("generated: server time %d (%s UTC)", now, addon.Trace.Clock(now))
    addLine("addon: v%s build=%s protocol=%d.%d schema=%s prefix=%s locale=%s", tostring(addon.VERSION), tostring(addon.BUILD),
        addon.PROTOCOL_MAJOR or 0, addon.PROTOCOL_MINOR or 0, tostring(addon.Store.SCHEMA), tostring(addon.PREFIX),
        tostring(addon.Locale.clientCode))
    if database.readonly then addLine("STORE IS READ-ONLY (saved data from a newer version)") end

    addLine("")
    addLine("--- identity ---")
    addLine("me (stored key): %s | whisper target others would use for me: %s", tostring(myName), tostring(Utility.WhisperTarget(myName)))
    addLine("my realm: %s | learned spellings of it: %s", tostring(Utility.MyRealm()), table.concat(Utility.RealmAliases(), ", "))
    local identity = options.identity
    if identity then
        addLine("client: %s", tostring(identity.build))
        addLine("UnitName: %s realm=%s | UnitFullName: %s", tostring(identity.unitName), tostring(identity.unitRealm), tostring(identity.unitFullName))
        addLine("GetRealmName: %s | GetNormalizedRealmName: %s", tostring(identity.realmName), tostring(identity.normalizedRealm))
        addLine("built full name: %s | Ambiguate(none): %s", tostring(identity.built), tostring(identity.ambiguated))
        addLine("guild: %s | roster count (client): %s", tostring(identity.guild), tostring(identity.rosterCount))
        addLine("roster spells me as: %s", tostring(identity.rosterMe))
        addLine("roster sample (raw): %s", table.concat(identity.rosterSample or {}, ", "))
        addLine("")
        addLine("--- name check: status | method | location | value | expected | behaviour ---")
        for _, row in ipairs(Diagnostics.IdentityRows({ identity = identity, me = myName, roster = communication and communication.roster,
            echo = communication and communication.lastEcho, seen = communication and communication.seen })) do
            addLine(Diagnostics.FormatIdentityRow(row))
        end
    end
    if communication then
        local roster = communication.roster or {}
        local inRoster = myName and roster[myName] and "yes" or "NO"
        addLine("me in cached roster: %s (cached roster %d names)", inRoster, count(roster))
        local lookalikes = myName and addon.Trace.RosterLookalikes(myName, roster)
        if lookalikes then addLine("roster names with my character name: %s", table.concat(lookalikes, ", ")) end

        addLine("")
        addLine("--- transport ---")
        local statistics = communication.sync and communication.sync.statistics or { sent = 0, received = 0, dropped = 0 }
        addLine("active=%s ready=%s messages sent=%d received=%d dropped=%d | chunks out=%d in=%d | send failures=%d | rejected chunks=%d | queue=%d chunks | incompatible peers=%d",
            tostring(communication.active), tostring(communication.ready), statistics.sent, statistics.received, statistics.dropped,
            communication.chunksSent or 0, communication.chunksReceived or 0, communication.sendFailures or 0,
            communication.rejected or 0, #(communication.queue or {}), communication.hints and communication.hints.count or 0)
        for _, transfer in ipairs(communication.InFlight and communication.InFlight() or {}) do
            addLine("incomplete transfer from %s: %d/%d chunks, %ds old", tostring(transfer.sender), transfer.receivedCount,
                transfer.partCount, transfer.ageSeconds)
        end
        if communication.sync then
            for _, playerName in ipairs(sortedKeys(communication.sync.wanted)) do
                local pull = communication.sync.wanted[playerName]
                addLine("pulled record of %s (rev %s) %ds ago", playerName, tostring(pull.revision), now - (pull.startedAt or now))
            end
            for _, playerName in ipairs(sortedKeys(communication.sync.wantedOffers)) do
                local pull = communication.sync.wantedOffers[playerName]
                addLine("pulled offers of %s (rev %s) %ds ago", playerName, tostring(pull.revision), now - (pull.startedAt or now))
            end
            addLine("scheduled sends: %d", #(communication.sync.pending or {}))
        end
    end

    addLine("")
    addLine("--- characters held (%d) ---", count(database.chars))
    for _, playerName in ipairs(sortedKeys(database.chars)) do
        local characterRecord = database.chars[playerName]
        addLine("%s%s rev=%s level=%s professions=%d recipes=%d", playerName, playerName == myName and " (me)" or "",
            tostring(characterRecord.rev), tostring(characterRecord.level), count(characterRecord.professions),
            addon.Store.RecipeCount(characterRecord))
    end
    addLine("catalog entries: %d", count(database.catalog))

    addLine("")
    addLine("--- offers held (%d) ---", count(database.offers))
    for _, playerName in ipairs(sortedKeys(database.offers)) do
        local offerRecord = database.offers[playerName]
        addLine("%s%s rev=%s items=%d dibs=%d", playerName, playerName == myName and " (me)" or "", tostring(offerRecord.rev),
            count(offerRecord.items), count(offerRecord.dibs))
    end

    addLine("")
    addLine("--- orders held (%d) ---", count(database.orders))
    local spellName = addon.Names.environment.spellName   -- nil until Api.lua has loaded (offline tests)
    for _, orderID in ipairs(sortedKeys(database.orders)) do
        local order = database.orders[orderID]
        local catalogEntry = database.catalog and database.catalog[order.recipeID]
        local spellLookup = spellName and spellName(order.recipeID)
        -- where the shown recipe name comes from: the catalog (from the crafter's SNAP) or a spell lookup by recipe id
        addLine("%s requester=%s recipe=%s qty=%s closed=%s claims=%d | catalog name=%s | order snapshot=%s | spell lookup=%s", orderID,
            tostring(order.requester), tostring(order.recipeID), tostring(order.qty), tostring(order.closed), count(order.claims),
            catalogEntry and tostring(catalogEntry.name) or "-", tostring(order.name or "-"), tostring(spellLookup))
    end

    addLine("")
    addLine("--- trace summary ---")
    local countByKind = addon.Trace.Counts()
    for _, kind in ipairs(sortedKeys(countByKind)) do addLine("%s: %d", kind, countByKind[kind]) end

    addLine("")
    local traceEntries = addon.Trace.List()
    local shownCount = math.min(options.traceLines or #traceEntries, #traceEntries)
    addLine("--- network trace (last %d of %d, oldest first; times UTC) ---", shownCount, #traceEntries)
    addLine("legend: -> out, <- in, ** local event | [sent] = accepted by this client, NOT proof of delivery: compare with the")
    addLine("        receiver's report | [ignored] = arrived, nothing to do (reason follows) | (to X) = whisper target used")
    for index = shownCount, 1, -1 do addLine(addon.Trace.Format(traceEntries[index])) end

    addLine("")
    local logLines = database.debug or {}
    addLine("--- log (%d lines, last 100; format: time LEVEL [area] message :: details) ---", #logLines)
    for index = math.max(1, #logLines - 99), #logLines do addLine(tostring(logLines[index])) end
    addLine("=== end of report ===")
    return table.concat(lines, "\n")
end

-- /ps ident: the name check table in the chat frame
addon.SlashCommands.ident = function()
    for _, row in ipairs(Diagnostics.IdentityRows(Diagnostics.IdentityContext())) do
        print(Utility.Escape(Diagnostics.FormatIdentityRow(row)))
    end
end

addon.SlashCommands.export = function()
    local reportText = Diagnostics.Report({ identity = addon.Api.IdentityInformation(), communication = addon.Communication })
    addon.UI.ShowExport(reportText)
end
