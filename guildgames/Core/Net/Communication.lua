local addonName, addon = ...

-- Transport: a LibGuildSync-1.0 Channel for addon.PREFIX (LibGuildSync/Channel.lua: chunking, the send bucket shared with
-- TalentShare and every other addon that embeds the library, reassembly, the guild gate, echo/realm learning, HELLO
-- coalescing, roster and identity check, the minute ticker). Not in a guild -> inactive (no sends, no errors).
-- The channel IS this module: Communication.Send, .OnAddonMessage, .RequestHelloSoon, .roster, .sync, ...

local Text = addon.Text

local me = addon.Utility.Me

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

-- comm, hello, debug [count], trace [count] [problems]: LibGuildSync-1.0 Addon.AddDiagnosticCommands (shared with
-- TalentShare; English on purpose)
LibStub("LibGuildSync-1.0").Addon.AddDiagnosticCommands(addon)
