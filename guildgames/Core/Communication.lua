local addonName, addon = ...

-- Transport: a LibGuildSync-1.0 Channel for addon.PREFIX (LibGuildSync/Channel.lua: chunking, the send bucket shared with
-- TalentShare and every other addon that embeds the library, reassembly, the guild gate, echo/realm learning, HELLO
-- coalescing, roster and identity check, the minute ticker). Not in a guild -> inactive (no sends, no errors).
-- The channel IS this module: Communication.Send, .OnAddonMessage, .RequestHelloSoon, .roster, .sync, ...

local Text = addon.Text

---@return string|nil
local function me() return addon.Utility.Me() end

---@class CommunicationModule
local Communication = LibStub("LibGuildSync-1.0").Channel.New({
    prefix = function() return addon.PREFIX end,
    codec = addon.Codec,
    log = addon.Log,
    trace = addon.Trace,
    me = me,
    version = addon.VERSION,
    priorityTypes = { HELLO = true, WANTG = true },
    guild = function() return addon.Api end,
    newSync = function(channel)
        return addon.Sync.New({
            send = channel.Send,
            now = addon.Utility.Now,
            random = math.random,
            me = me,
            onChange = function(kind) addon.Events.Fire("DATA_CHANGED", kind) end,
        })
    end,
    onIncompatible = function(kind)
        if kind == "newer" then
            addon.Print(Text["A guild member runs a newer GuildGames that cannot sync with this version. Please update the addon."])
        elseif kind == "older" then
            addon.Print(Text["A guild member runs an older GuildGames that cannot sync with this version."])
        else
            addon.Print(Text["A guild member runs a newer GuildGames with extra features. Updating is recommended."])
        end
    end,
    onIdentityProblem = function()
        addon.Print(Text["Sync problem: your character name does not match the guild roster, so game results cannot be exchanged."])
    end,
    canonicalizeStored = function() return addon.Store.CanonicalizeStoredNames() end,
    onRoster = function(roster) addon.Store.Prune(roster, addon.Store.db.me) end,
})
addon.Communication = Communication

------------------------------------------------------------------ slash commands (diagnostics, English on purpose)

addon.SlashCommands.comm = function()
    local statistics = Communication.sync and Communication.sync.statistics or { sent = 0, received = 0, dropped = 0 }
    addon.Print(("comm: active=%s protocol=%d.%d sent=%d received=%d dropped=%d rejected=%d queue=%d chunks out/in=%d/%d send failures=%d roster=%d"):format(
        tostring(Communication.active), addon.PROTOCOL_MAJOR, addon.PROTOCOL_MINOR, statistics.sent, statistics.received,
        statistics.dropped, Communication.rejected, #Communication.queue, Communication.chunksSent, Communication.chunksReceived,
        Communication.sendFailures, addon.Utility.Count(Communication.roster)))
end

addon.SlashCommands.hello = function()
    if not Communication.active then addon.Print("not active (not in a guild?)") return end
    Communication.RequestHello(false, true)
    addon.Print("hello sent")
end

-- /gg debug [count]: the last log lines (default 15); /gg trace [count] [problems]: the last network trace entries
addon.SlashCommands.debug = function(arguments)
    local lineCount = tonumber((arguments or ""):match("%d+")) or 15
    local logLines = addon.db and addon.db.debug or {}
    for index = math.max(1, #logLines - lineCount + 1), #logLines do print(logLines[index]) end
end

addon.SlashCommands.trace = function(arguments)
    local entryCount = tonumber((arguments or ""):match("%d+")) or 20
    local traceEntries = addon.Trace.List((arguments or ""):match("problems") and "problems" or nil)
    for index = math.min(entryCount, #traceEntries), 1, -1 do print(addon.Utility.Escape(addon.Trace.Format(traceEntries[index]))) end
end
