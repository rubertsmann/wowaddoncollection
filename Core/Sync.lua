local addonName, addon = ...

-- GuildGames' protocol on the LibGuildSync-1.0 record-pull engine (LibGuildSync/Sync.lua: HELLO revisions, pulls by
-- whisper with GUILD retries, give-up reset, GUILD answer dedup, asked-name answers, login replies). Pure: all I/O goes
-- through `environment`, so it is testable offline.
-- Messages (prefix addon.PREFIX, every message carries v = addon.PROTOCOL and a type t). The names are the WIRE FORMAT
-- (kept from TalentShare 0.6.0, where the games started):
--   HELLO {grev?, login?}   broadcast (GUILD) or reply (WHISPER): the revision of my game record (left out while I have none)
--   WANTG {names, via?}     "send me your game record"; only the sender's own name is honoured
--   GAMES {games}           a character's game record (Core/Games.lua); only its author may send it
---@class SyncModule
local Sync = {}
addon.Sync = Sync

local library = LibStub("LibGuildSync-1.0")
setmetatable(Sync, { __index = library.Sync })

---@class GamesSyncEnvironment
---@field send fun(message: table, channel: string, target?: string)
---@field now fun(): integer server time
---@field random fun(): number in [0, 1)
---@field me string|fun(): string|nil my canonical name, or a function returning it
---@field onChange fun(kind: "games")

-- A Sync engine with the games record kind.
---@param environment GamesSyncEnvironment
---@return table sync
function Sync.New(environment)
    environment.protocol = environment.protocol or addon.PROTOCOL
    environment.horizon = environment.horizon or addon.Store.Horizon
    environment.log = environment.log or addon.Log
    environment.trace = environment.trace or addon.Trace
    local Games = addon.Games
    local sync = library.Sync.New(environment)
    sync.wantedGames = sync:AddRecordKind({
        name = "games", label = "games", helloField = "grev",
        requestType = "WANTG", answerType = "GAMES", recordField = "games",
        noneNote = "asked for my games but I have none",
        heldRevision = function(playerName)
            local gameRecord = Games.Get(playerName)
            return gameRecord and gameRecord.rev or 0
        end,
        myRecord = function(myName) return Games.Mine(myName) end,   -- never a simulated record: those live outside the db
        sanitize = Games.Sanitize,
        store = function(_, gameRecord) return Games.Put(gameRecord) end,
    })
    return sync
end
