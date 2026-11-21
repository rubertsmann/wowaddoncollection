local addonName, addon = ...

-- Transport: a LibGuildSync-1.0 Channel for addon.PREFIX (LibGuildSync/Channel.lua: chunking, the send bucket shared with
-- every other addon that embeds the library, reassembly, the guild gate, echo/realm learning, HELLO coalescing, roster and
-- identity check, the minute ticker). This file adds what is ProfessionShare's own: its Sync, its stored names, the notices
-- in its language and the slash commands. Not in a guild -> inactive (no sends, no errors).
-- Every message in and out is recorded in the network trace (Core/Debug/Trace.lua, feature 008).
-- The channel IS this module: Communication.Send, .OnAddonMessage, .RequestHello, .queue, .roster, .sync, ... are the
-- channel's own functions and fields.

local Text = addon.Text
local library = LibStub("LibGuildSync-1.0")

---@type table<string, boolean> small single-chunk control messages that jump the queue
local PRIORITY_TYPES = { ORDER = true, WANT = true, WANTO = true, HELLO = true }

---@return string|nil
local function me() return addon.Utility.Me() end

---@class CommunicationModule
local Communication = library.Channel.New({
    prefix = function() return addon.PREFIX end,   -- read at use time: the build decides it (Core/Base/Init.lua)
    codec = addon.Codec,
    log = addon.Log,
    trace = addon.Trace,
    me = me,
    version = addon.VERSION,
    priorityTypes = PRIORITY_TYPES,
    guild = function() return addon.Api end,       -- Api delegates to LibGuildSync's Guild; tests replace it
    newSync = function(channel)
        return addon.Sync.New({
            send = channel.Send,
            now = addon.Utility.Now,
            random = math.random,
            store = addon.Store,
            orders = addon.orders,
            me = me,   -- a function: read at use time
            onChange = function(kind) addon.Events.Fire("DATA_CHANGED", kind) end,
        })
    end,
    onIncompatible = function(kind)
        if kind == "newer" then
            addon.Print(Text["A guild member runs a newer ProfessionShare that cannot sync with this version. Please update the addon."])
        elseif kind == "older" then
            addon.Print(Text["A guild member runs an older ProfessionShare that cannot sync with this version."])
        else
            addon.Print(Text["A guild member runs a newer ProfessionShare with extra features. Updating is recommended."])
        end
    end,
    onIdentityProblem = function()
        addon.Print(addon.Locale.Format(Text["Sync problem: your character name does not match the guild roster, so recipes and items cannot be exchanged. Please send the {cmd} export report to the addon author."],
            { cmd = (addon.SLASH_COMMANDS or {})[1] }))
    end,
    canonicalizeStored = function() return addon.Store.CanonicalizeStoredNames() end,
    onRoster = function(roster) addon.Store.Prune(roster, addon.Store.db.me) end,
    onMinute = function(now) if addon.orders then addon.orders:Prune(now) end end,
})
addon.Communication = Communication

---@param order Order
function Communication.BroadcastOrder(order)
    if Communication.active then Communication.sync:BroadcastOrder(order) end
end

------------------------------------------------------------------ slash commands

-- comm, hello, debug [count], trace [count] [problems]: LibGuildSync-1.0 Addon.AddDiagnosticCommands (shared with GuildGames)
library.Addon.AddDiagnosticCommands(addon)

addon.SlashCommands.chars = function()
    for _, characterRecord in ipairs(addon.Store.ListCharacters()) do
        print(("%s lvl %s rev %s recipes %d"):format(characterRecord.name, tostring(characterRecord.level),
            tostring(characterRecord.rev), addon.Store.RecipeCount(characterRecord)))
    end
end
