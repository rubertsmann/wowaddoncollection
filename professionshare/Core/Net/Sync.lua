local addonName, addon = ...

-- ProfessionShare's protocol on the LibGuildSync-1.0 record-pull engine (LibGuildSync/Sync.lua: HELLO revisions, pulls by
-- whisper with GUILD retries, give-up reset, GUILD answer dedup, asked-name answers, login replies). This file registers
-- what is ProfessionShare's own. Pure: all I/O goes through `environment`, so it is testable offline.
-- OnMessage returns (status, reason): "ok" | "ignored" | "dropped" | "error", for the network trace (Core/Debug/Trace.lua).
-- Messages (every message carries v = addon.PROTOCOL and a string type t). The field names are the WIRE FORMAT and stay:
--   HELLO {rev, login?, odig, xdig?, orev?, ver?}  broadcast (GUILD) or reply (WHISPER): my record versions + digest of
--                               my orders; xdig = digest of their chat and history (2.9+)
--   WANT  {names, via?}         "send me your record"; only the sender's own name is honoured
--   SNAP  {char, catalog}       a character record + catalog entries of its recipes
--   OPUSH {orders}              whisper: orders the receiver lacks (<= 10 per message)
--   ORDER {order}               broadcast: one order changed (order may carry a recipe name snapshot, 2.2+)
--   OMSG {id, m}                broadcast: one chat message on an order, only in the sender's own name (2.9+); orders
--                               carry optional msgs (chat) and ev (history); ORDER leaves msgs out
--   WANTO {names, via?}         "send me your offers record" (2.1+)
--   OFFERS {offers}             a character's offers/dibs record (2.1+)
--   HELLO.arev, WANTA {names, via?}, ACCESS {access}   a character's dungeon keys and raid attunements (2.4+)
--   HELLO.rrev, WANTR {names, via?}, REP {rep}   a character's faction standings (2.6+)
--   HELLO.crev, WANTC {names, via?}, CDS {cds, at}   a character's craft cooldowns; `at` = the sender's server time when
--                               it answered, so the receiver converts the ready times to its own clock (2.8+)
--   HELLO.frev, WANTF {names, via?}, FEEDBACK {feedback}   a character's messages for the developer (2.5+); only the
--                               developer's client pulls them (Feedback.IsReader)
--   HELLO.wsp                   "skillLine:spellID,..." the spells that opened my profession windows; diagnosis only,
--                               kept by the developer's client (ProfessionSpells); protocol stays 2.8 (like `ver`)
-- Protocol 2.3 also had HELLO.grev, WANTG and GAMES (guild games, 0.6.0). They moved to the GuildGames addon: a 0.6
-- peer's grev is ignored, its WANTG/GAMES are dropped as unknown message types.
-- A peer can only author its OWN record (SNAP char.name / OFFERS name must equal the sender). Every player name from the
-- wire is compared and stored in canonical form (Utility.CanonicalName), so differently spelled realms meet on one key.

---@class ProfessionShareSyncEnvironment
---@field send fun(message: table, channel: string, target?: string)
---@field now fun(): integer server time
---@field random fun(): number in [0, 1)
---@field store StoreModule
---@field orders OrderBoard
---@field onChange fun(kind: "chars"|"offers"|"orders"|"access"|"rep"|"cds"|"feedback")
---@field me string|fun(): string|nil my canonical name, or a function returning it
---@field windowSpells? fun(): string|nil my HELLO.wsp
---@field onWindowSpells? fun(sender: string, decoded: table) a peer's HELLO.wsp, decoded

---@class SyncModule
local Sync = {}
addon.Sync = Sync

local library = LibStub("LibGuildSync-1.0")
local ORDERS_PER_PUSH = 10
local MAXIMUM_PUSH_BYTES = 8000

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
    for _, listField in ipairs({ "msgs", "ev" }) do
        if type(order[listField]) == "table" then
            local entries = {}
            for index, entry in ipairs(order[listField]) do
                if type(entry) == "table" and type(entry.b) == "string" then
                    local entryCopy = {}
                    for key, value in pairs(entry) do entryCopy[key] = value end
                    entryCopy.b = canonical(entry.b)
                    entry = entryCopy
                end
                entries[index] = entry
            end
            copy[listField] = entries
        end
    end
    return copy
end
Sync.CanonicalOrder = canonicalOrder

-- The character record: required in every HELLO (rev 0 = none yet), pulled with WANT, answered with SNAP plus the
-- catalog entries of its recipes.
---@param environment ProfessionShareSyncEnvironment
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

-- The access record (protocol 2.4): keys and attunements. Registered last, so its pulls queue behind the other records;
-- it changes once or twice in a character's life, so after the first exchange only `arev` travels.
---@return RecordKind
local function accessKind()
    local Access = addon.Access
    return {
        name = "access", label = "access", helloField = "arev", absentNote = "access: peer has none",
        requestType = "WANTA", answerType = "ACCESS", recordField = "access",
        noneNote = "asked for my access record but I have none",
        heldRevision = function(playerName)
            local accessRecord = Access.Get(playerName)
            return accessRecord and accessRecord.rev or 0
        end,
        myRecord = function(myName) return Access.Get(myName) end,
        sanitize = Access.Sanitize,
        store = function(_, accessRecord) return Access.Put(accessRecord) end,
    }
end

-- The reputation record (protocol 2.6): faction standings. A level change is announced at once, progress at most every
-- Reputation.PROGRESS_INTERVAL, so `rrev` changes seldom and the record is pulled only after a change.
---@return RecordKind
local function reputationKind()
    local Reputation = addon.Reputation
    return {
        name = "rep", label = "rep", helloField = "rrev", absentNote = "rep: peer has none",
        requestType = "WANTR", answerType = "REP", recordField = "rep",
        noneNote = "asked for my reputation record but I have none",
        heldRevision = function(playerName)
            local reputationRecord = Reputation.Get(playerName)
            return reputationRecord and reputationRecord.rev or 0
        end,
        myRecord = function(myName) return Reputation.Get(myName) end,
        sanitize = Reputation.Sanitize,
        store = function(_, reputationRecord) return Reputation.Put(reputationRecord) end,
    }
end

-- The craft cooldown record (protocol 2.8): ready times in the owner's clock. The answer carries the owner's server time
-- (`at`); the receiver keeps the time left and adds it to its own clock (CraftCooldowns.FromWire).
---@return RecordKind
local function cooldownKind()
    local CraftCooldowns = addon.CraftCooldowns
    return {
        name = "cds", label = "cds", helloField = "crev", absentNote = "cds: peer has none",
        requestType = "WANTC", answerType = "CDS", recordField = "cds",
        noneNote = "asked for my cooldown record but I have none",
        heldRevision = function(playerName)
            local cooldownRecord = CraftCooldowns.Get(playerName)
            return cooldownRecord and cooldownRecord.rev or 0
        end,
        myRecord = function(myName) return CraftCooldowns.Get(myName) end,
        sanitize = CraftCooldowns.Sanitize,
        store = function(sync, cooldownRecord, message)
            return CraftCooldowns.Put(CraftCooldowns.FromWire(cooldownRecord, message.at, sync.environment.now()))
        end,
        answer = function(sync, cooldownRecord)
            return { t = "CDS", cds = CraftCooldowns.ToWire(cooldownRecord), at = sync.environment.now() }
        end,
    }
end

-- The feedback record (protocol 2.5): messages for the developer. Only a reader (the developer's client) pulls them:
-- for everyone else every announced revision counts as held, and a record that still arrives (a pull retry answered on
-- GUILD reaches every member) is not stored.
---@return RecordKind
local function feedbackKind()
    local Feedback = addon.Feedback
    return {
        name = "feedback", label = "feedback", helloField = "frev",
        requestType = "WANTF", answerType = "FEEDBACK", recordField = "feedback",
        noneNote = "asked for my feedback record but I have none",
        heldRevision = function(playerName)
            if not Feedback.IsReader(addon.Utility.Me()) then return math.huge end
            local feedbackRecord = Feedback.Get(playerName)
            return feedbackRecord and feedbackRecord.rev or 0
        end,
        myRecord = function(myName) return Feedback.Get(myName) end,
        sanitize = Feedback.Sanitize,
        store = function(sync, feedbackRecord) return Feedback.Put(feedbackRecord, sync:_me()) end,
        -- answering means a reader asked: my messages in this record count as delivered (shown to me only)
        answer = function(_, feedbackRecord)
            Feedback.MarkDelivered(feedbackRecord)
            if addon.Events then addon.Events.Fire("DATA_CHANGED", "feedback") end
            return { t = "FEEDBACK", feedback = feedbackRecord }
        end,
    }
end

-- A rough size of an order on the wire before compression, so an OPUSH with long chats stays well below the codec's size limit.
---@param order Order
---@return integer
local function estimatedBytes(order)
    local bytes = 200 + #(order.note or "") + 40 * #(order.ev or {})
    for _ in pairs(order.claims or {}) do bytes = bytes + 40 end
    for _, message in ipairs(order.msgs or {}) do bytes = bytes + 50 + #message.x end
    return bytes
end
Sync.EstimatedOrderBytes = estimatedBytes

-- `orders` cut into OPUSH batches of at most ORDERS_PER_PUSH orders and about MAXIMUM_PUSH_BYTES each
---@param orders Order[]
---@return Order[][]
local function pushBatches(orders)
    local batches, batch, batchBytes = {}, {}, 0
    for _, order in ipairs(orders) do
        local bytes = estimatedBytes(order)
        if #batch > 0 and (#batch >= ORDERS_PER_PUSH or batchBytes + bytes > MAXIMUM_PUSH_BYTES) then
            batches[#batches + 1] = batch
            batch, batchBytes = {}, 0
        end
        batch[#batch + 1] = order
        batchBytes = batchBytes + bytes
    end
    if #batch > 0 then batches[#batches + 1] = batch end
    return batches
end
Sync.PushBatches = pushBatches

-- HELLO.odig: the digest of my orders; HELLO.xdig (2.9): the digest of their chat and history. A peer that lacks some
-- gets them pushed (OPUSH, at most 10 orders per message, fewer when they carry long chats).
---@param environment ProfessionShareSyncEnvironment
---@return SyncHelloHook
local function ordersHelloHook(environment)
    return {
        build = function(_, message)
            message.odig = environment.orders:Digest(100)
            message.xdig = environment.orders:ExtraDigest(100)
        end,
        handle = function(sync, message, sender, notes)
            if type(message.odig) ~= "table" then return end
            local missingOrders = environment.orders:Missing(message.odig, 40, message.xdig)
            for _, batch in ipairs(pushBatches(missingOrders)) do
                sync:_later(1 + environment.random() * 5, { t = "OPUSH", orders = batch }, "WHISPER", sender)
            end
            if #missingOrders > 0 then notes[#notes + 1] = ("orders: peer lacks %d -> OPUSH"):format(#missingOrders) end
        end,
    }
end

-- HELLO.wsp: which spell opened which of my profession windows (sent like the build tag; never used for decisions).
---@param environment ProfessionShareSyncEnvironment
---@return table
local function windowSpellsHelloHook(environment)
    return {
        build = function(_, message) message.wsp = environment.windowSpells and environment.windowSpells() or nil end,
        handle = function(_, message, sender, notes)
            if message.wsp == nil then return end
            local decoded = addon.ProfessionSpells.Decode(message.wsp)
            if not decoded then notes[#notes + 1] = "window spells: invalid, ignored" return end
            notes[#notes + 1] = "window spells " .. #decoded
            if environment.onWindowSpells then environment.onWindowSpells(sender, decoded) end
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

-- OMSG {id, m}: one chat message on an order (2.9). Only in the sender's own name; an order this client does not hold
-- yet is ignored (the message comes with the order through OPUSH).
---@param sync table
---@param message table
---@param sender string
local function onOrderMessage(sync, message, sender)
    local chatMessage = message.m
    if type(message.id) ~= "string" or type(chatMessage) ~= "table" then error("bad message") end
    if canonical(chatMessage.b) ~= sender then
        sync:_note("dropped", "chat message in another member's name")
        return
    end
    local canonicalMessage = { b = sender, t = chatMessage.t, x = chatMessage.x }
    if sync.environment.orders:MergeMessage(message.id, canonicalMessage) then
        sync.environment.onChange("orders")
        sync:_note("ok", "chat message")
    else
        sync:_note("ignored", sync.environment.orders:Get(message.id) and "known or invalid" or "unknown order")
    end
end

-- DROP {item}: a member's recipe item just dropped into their bags. The client decides from its own tooltip whether to
-- answer and alert (environment.onRecipeDrop, Core/Game/Drops.lua).
---@param sync table
---@param message table
---@param sender string
local function onRecipeDrop(sync, message, sender)
    local itemID = addon.RecipeDrops.SanitizeDrop(message)
    if not itemID then error("bad item") end
    local onDrop = sync.environment.onRecipeDrop
    if onDrop then onDrop(sender, itemID) end
    sync:_note("ok", "recipe drop " .. itemID)
end

-- DROPA {item, s, r}: a member's answer to one of MY recipe drops (shown in that item's tooltip).
---@param sync table
---@param message table
---@param sender string
local function onRecipeDropAnswer(sync, message, sender)
    if not addon.RecipeDrops.SanitizeAnswer(message) then error("bad answer") end
    if addon.RecipeDrops.AddAnswer(sender, message, sync.environment.now()) then
        sync.environment.onChange("drops")
        sync:_note("ok", "answer " .. tostring(message.s) .. " " .. tostring(message.r))
    else
        sync:_note("ignored", "not one of my recent drops")
    end
end

-- A Sync engine with ProfessionShare's record kinds, the orders digest and the order messages. The result keeps the names
-- older code and tests use: sync.wanted (character pulls), sync.wantedOffers, sync.pending, sync.statistics.
---@param environment ProfessionShareSyncEnvironment
---@return table sync
function Sync.New(environment)
    environment.protocol = environment.protocol or addon.PROTOCOL
    environment.horizon = environment.horizon or addon.Store.Horizon
    environment.log = environment.log or addon.Log
    environment.trace = environment.trace or addon.Trace
    local sync = library.Sync.New(environment)
    sync.wanted = sync:AddRecordKind(characterKind(environment))
    sync.wantedOffers = sync:AddRecordKind(offersKind())
    sync.wantedAccess = sync:AddRecordKind(accessKind())
    sync.wantedReputation = sync:AddRecordKind(reputationKind())
    sync.wantedCooldowns = sync:AddRecordKind(cooldownKind())
    sync.wantedFeedback = sync:AddRecordKind(feedbackKind())
    sync:AddHelloHook(ordersHelloHook(environment))
    sync:AddHelloHook(windowSpellsHelloHook(environment))
    sync:AddHandler("OPUSH", onOrderPush)
    sync:AddHandler("ORDER", onOrder)
    sync:AddHandler("OMSG", onOrderMessage)
    sync:AddHandler("DROP", onRecipeDrop)
    sync:AddHandler("DROPA", onRecipeDropAnswer)
    -- the order without its chat: chat messages go out one by one (BroadcastOrderMessage)
    ---@param order Order
    function sync:BroadcastOrder(order) self:_send({ t = "ORDER", order = addon.Orders.WithoutChat(order) }, "GUILD") end
    ---@param orderID string
    ---@param chatMessage OrderMessage
    function sync:BroadcastOrderMessage(orderID, chatMessage) self:_send({ t = "OMSG", id = orderID, m = chatMessage }, "GUILD") end
    ---@param itemID integer
    function sync:BroadcastDrop(itemID) self:_send({ t = "DROP", item = itemID }, "GUILD") end
    ---@param target string the looter
    ---@param itemID integer
    ---@param status "g"|"r"
    ---@param rank integer
    function sync:AnswerDrop(target, itemID, status, rank) self:_send({ t = "DROPA", item = itemID, s = status, r = rank }, "WHISPER", target) end
    return sync
end
