local addonName, addon = ...

-- TalentShare's protocol on the LibGuildSync-1.0 record-pull engine (LibGuildSync/Sync.lua: HELLO revisions, pulls by
-- whisper with GUILD retries, give-up reset, GUILD answer dedup, asked-name answers, login replies). This file registers
-- what is TalentShare's own. Pure: all I/O goes through `environment`, so it is testable offline.
-- OnMessage returns (status, reason): "ok" | "ignored" | "dropped" | "error", for the network trace (Core/Debug/Trace.lua).
-- Messages (every message carries v = addon.PROTOCOL and a string type t). The field names are the WIRE FORMAT and stay:
--   HELLO {rev, login?, odig, orev?}  broadcast (GUILD) or reply (WHISPER): my record versions + digest of my orders
--   WANT  {names, via?}         "send me your record"; only the sender's own name is honoured
--   SNAP  {char, catalog}       a character record + catalog entries of its recipes
--   OPUSH {orders}              whisper: orders the receiver lacks (<= 10 per message)
--   ORDER {order}               broadcast: one order changed (order may carry a recipe name snapshot, 2.2+)
--   WANTO {names, via?}         "send me your offers record" (2.1+)
--   OFFERS {offers}             a character's offers/dibs record (2.1+)
-- Protocol 2.3 also had HELLO.grev, WANTG and GAMES (guild games, 0.6.0). They moved to the GuildGames addon (feature
-- 015): a 0.6 peer's grev is ignored, its WANTG/GAMES are dropped as unknown message types.
-- A peer can only author its OWN record (SNAP char.name / OFFERS name must equal the sender). Every player name from the
-- wire is compared and stored in canonical form (Utility.CanonicalName), so differently spelled realms meet on one key.

---@class TalentShareSyncEnvironment
---@field send fun(message: table, channel: string, target?: string)
---@field now fun(): integer server time
---@field random fun(): number in [0, 1)
---@field store StoreModule
---@field orders OrderBoard
---@field onChange fun(kind: "chars"|"offers"|"orders")
---@field me string|fun(): string|nil my canonical name, or a function returning it

---@class SyncModule
local Sync = {}
addon.Sync = Sync

local library = LibStub("LibGuildSync-1.0")
local ORDERS_PER_PUSH = 10

-- the engine's names, so older callers keep working (Sync.AskNames, Sync.GIVE_UP_RESET_SECONDS, ...)
setmetatable(Sync, { __index = library.Sync })

---@param playerName any
---@return any
local function canonical(playerName) return addon.Utility.CanonicalName(playerName) or playerName end

-- an order with every player name in canonical form (a shallow copy; Orders.Merge validates it)
---@param order any
---@return any
local function canonicalOrder(order)
    if type(order) ~= "table" then return order end
    local copy = {}
    for key, value in pairs(order) do copy[key] = value end
    if type(order.requester) == "string" then copy.requester = canonical(order.requester) end
    if type(order.closedBy) == "string" then copy.closedBy = canonical(order.closedBy) end
    if type(order.claims) == "table" then
        local claims = {}
        for crafter, claim in pairs(order.claims) do claims[type(crafter) == "string" and canonical(crafter) or crafter] = claim end
        copy.claims = claims
    end
    return copy
end
Sync.CanonicalOrder = canonicalOrder

-- The character record: required in every HELLO (rev 0 = none yet), pulled with WANT, answered with SNAP plus the
-- catalog entries of its recipes.
---@param environment TalentShareSyncEnvironment
---@return RecordKind
local function characterKind(environment)
    local store = environment.store
    return {
        name = "char", label = "char", changeKind = "chars", helloField = "rev", required = true,
        requestType = "WANT", answerType = "SNAP", recordField = "char",
        noneNote = "asked for my record but I have none (no profession scanned)",
        heldRevision = function(playerName)
            local characterRecord = store.GetCharacter(playerName)
            return characterRecord and characterRecord.rev or 0
        end,
        myRecord = function(myName) return store.GetCharacter(myName) end,
        answer = function(_, record)
            local catalogEntries = {}
            for _, profession in pairs(record.professions or {}) do
                for recipeID in pairs(profession.recipes or {}) do
                    local catalogEntry = store.GetRecipe(recipeID)
                    if catalogEntry then catalogEntries[recipeID] = catalogEntry end
                end
            end
            return { t = "SNAP", char = record, catalog = catalogEntries }
        end,
        sanitize = store.SanitizeCharacter,   -- allow-list copy: only validated fields of the record are ever stored
        store = function(_, characterRecord, message)
            -- catalog entries are accepted only for recipes the sender itself knows (it cannot seed names for other recipes)
            local senderKnows = {}
            for _, profession in pairs(characterRecord.professions) do
                for recipeID in pairs(profession.recipes) do senderKnows[recipeID] = true end
            end
            local acceptedEntries, entryCount = {}, 0
            if type(message.catalog) == "table" then
                for recipeID, catalogEntry in pairs(message.catalog) do
                    entryCount = entryCount + 1
                    if entryCount > 2000 then break end
                    if senderKnows[recipeID] then acceptedEntries[recipeID] = catalogEntry end   -- PutCatalog rebuilds each by allow-list copy
                end
            end
            store.PutCatalog(acceptedEntries)
            return store.PutCharacter(characterRecord)
        end,
    }
end

-- The offers record (protocol 2.1): optional in HELLO (orev), pulled with WANTO, answered with OFFERS.
---@return RecordKind
local function offersKind()
    local Offers = addon.Offers
    return {
        name = "offers", label = "offers", helloField = "orev", absentNote = "offers: peer has none",
        requestType = "WANTO", answerType = "OFFERS", recordField = "offers",
        noneNote = "asked for my offers but I have none",
        heldRevision = function(playerName)
            local offerRecord = Offers.Get(playerName)
            return offerRecord and offerRecord.rev or 0
        end,
        myRecord = function(myName) return Offers.Get(myName) end,
        sanitize = Offers.Sanitize,
        store = function(_, offerRecord)
            local dibs = {}   -- dib keys name other players: stored under their canonical names too
            for offerKey, dib in pairs(offerRecord.dibs) do
                local owner, itemID = Offers.ParseKey(offerKey)
                if owner then dibs[Offers.Key(canonical(owner), itemID)] = dib end
            end
            offerRecord.dibs = dibs
            return Offers.Put(offerRecord)
        end,
    }
end

-- HELLO.odig: the digest of my orders; a peer that lacks some gets them pushed (OPUSH, 10 per message).
---@param environment TalentShareSyncEnvironment
---@return SyncHelloHook
local function ordersHelloHook(environment)
    return {
        build = function(_, message) message.odig = environment.orders:Digest(100) end,
        handle = function(sync, message, sender, notes)
            if type(message.odig) ~= "table" then return end
            local missingOrders = environment.orders:Missing(message.odig, 40)
            local batchStart = 1
            while batchStart <= #missingOrders do
                local batch = {}
                for index = batchStart, math.min(batchStart + ORDERS_PER_PUSH - 1, #missingOrders) do batch[#batch + 1] = missingOrders[index] end
                sync:_later(1 + environment.random() * 5, { t = "OPUSH", orders = batch }, "WHISPER", sender)
                batchStart = batchStart + ORDERS_PER_PUSH
            end
            if #missingOrders > 0 then notes[#notes + 1] = ("orders: peer lacks %d -> OPUSH"):format(#missingOrders) end
        end,
    }
end

---@param sync table
---@param message table
local function onOrderPush(sync, message)
    local environment = sync.environment
    if type(message.orders) ~= "table" then error("bad orders") end
    local changed, changedCount = false, 0
    for index, order in ipairs(message.orders) do
        if index > ORDERS_PER_PUSH then break end
        if environment.orders:Merge(canonicalOrder(order)) then changed = true; changedCount = changedCount + 1 end
    end
    if changed then environment.onChange("orders") end
    sync:_note(changed and "ok" or "ignored", ("%d of %d orders changed"):format(changedCount, math.min(#message.orders, ORDERS_PER_PUSH)))
end

---@param sync table
---@param message table
local function onOrder(sync, message)
    if sync.environment.orders:Merge(canonicalOrder(message.order)) then
        sync.environment.onChange("orders")
        sync:_note("ok", "merged")
    else
        sync:_note("ignored", addon.Orders.Sanitize(message.order) and "no change" or "invalid order")
    end
end

-- A Sync engine with TalentShare's record kinds, the orders digest and the order messages. The result keeps the names
-- older code and tests use: sync.wanted (character pulls), sync.wantedOffers, sync.pending, sync.statistics.
---@param environment TalentShareSyncEnvironment
---@return table sync
function Sync.New(environment)
    environment.protocol = environment.protocol or addon.PROTOCOL
    environment.horizon = environment.horizon or addon.Store.Horizon
    environment.log = environment.log or addon.Log
    environment.trace = environment.trace or addon.Trace
    local sync = library.Sync.New(environment)
    sync.wanted = sync:AddRecordKind(characterKind(environment))
    sync.wantedOffers = sync:AddRecordKind(offersKind())
    sync:AddHelloHook(ordersHelloHook(environment))
    sync:AddHandler("OPUSH", onOrderPush)
    sync:AddHandler("ORDER", onOrder)
    ---@param order Order
    function sync:BroadcastOrder(order) self:_send({ t = "ORDER", order = order }, "GUILD") end
    return sync
end
