local addonName, addon = ...

-- Protocol state machine. Pure: all I/O goes through `environment`, so it is testable offline.
-- `me` may be a function so the identity is read at use time: Communication can start before PLAYER_LOGIN has set the
-- current character (SavedVariables are account-wide, so the stored name may still be the previously played character).
-- OnMessage returns (status, reason): "ok" | "ignored" | "dropped" | "error", for the network trace (Core/Debug/Trace.lua).
-- Messages (every message carries v = addon.PROTOCOL and a string type t). The field names are the WIRE FORMAT and stay:
--   HELLO {rev, login?, odig, orev?, grev?}  broadcast (GUILD) or reply (WHISPER): my record versions + digest of my orders
--   WANT  {names, via?}         "send me your record"; only the sender's own name is honoured
--   SNAP  {char, catalog}       a character record + catalog entries of its recipes
--   OPUSH {orders}              whisper: orders the receiver lacks (<= 10 per message)
--   ORDER {order}               broadcast: one order changed (order may carry a recipe name snapshot, 2.2+)
--   WANTO {names, via?}         "send me your offers record" (2.1+)
--   OFFERS {offers}             a character's offers/dibs record (2.1+)
--   WANTG {names, via?}         "send me your games record" (2.3+)
--   GAMES {games}               a character's game results record (2.3+, Core/Play/Games.lua)
-- Pulls (2.2): the first WANT/WANTO is a whisper. If the record has not arrived after RETRY_SECONDS[1] seconds the request
-- is repeated on GUILD with via = "GUILD", and the owner answers on GUILD, so a failing whisper path (wrong target form,
-- server restrictions) cannot block sync; one GUILD answer also serves every other member that was behind. A 2.1 peer
-- ignores `via` and answers by whisper as before.
-- A peer can only author its OWN record (SNAP char.name / OFFERS name / GAMES name must equal the sender). Every player name from the
-- wire is compared and stored in canonical form (Utility.CanonicalName), so differently spelled realms meet on one key.

---@class SyncEnvironment
---@field send fun(message: table, channel: string, target?: string)
---@field now fun(): integer server time
---@field random fun(): number in [0, 1)
---@field store StoreModule
---@field orders OrderBoard
---@field onChange fun(kind: "chars"|"offers"|"orders"|"games")
---@field me string|fun(): string|nil my canonical name, or a function returning it

---@class PendingSend
---@field dueAt number
---@field message table
---@field channel string
---@field target? string

---@class RecordPull
---@field revision integer the revision the peer announced
---@field startedAt integer time of the last attempt (or of giving up)
---@field attempts integer
---@field gaveUp? boolean

---@class SyncResult
---@field status "ok"|"ignored"|"dropped"|"error"
---@field reason? string

---@class SyncStatistics
---@field sent integer
---@field received integer
---@field dropped integer

---@class Sync
---@field environment SyncEnvironment
---@field pending PendingSend[] messages waiting for their send time
---@field wanted table<string, RecordPull> character-record pulls by peer
---@field wantedOffers table<string, RecordPull> offers-record pulls by peer
---@field wantedGames table<string, RecordPull> games-record pulls by peer
---@field guildSent table<string, { revision: integer, sentAt: integer }> last GUILD answer per record kind
---@field peerRealm table<string, string> the realm each peer appends to names (learned from its requests)
---@field loginReplyBudget integer login introductions sent in the current minute
---@field loginReplyBudgetStartedAt integer
---@field statistics SyncStatistics
---@field result SyncResult|nil outcome of the message being handled
local Sync = {}
addon.Sync = Sync
Sync.__index = Sync

---@type integer[] seconds to wait after attempt n before the next one; after the last: give up
Sync.RETRY_SECONDS = { 45, 90, 180 }
-- A HELLO is fresh proof that the peer is online: it restarts a pull that gave up once this long has passed (the 0.4.0
-- rule, one pull per peer and minute). A longer lock (first 0.4.1 draft: 10 min) left members without a record for up
-- to 10 min after a few lost messages; tests/test_soak.lua caught it (about 1 failed run in 100).
Sync.GIVE_UP_RESET_SECONDS = 60
-- an answer on GUILD for the same revision is sent at most once per this many seconds
Sync.GUILD_DEDUPLICATION_SECONDS = 60
local MAXIMUM_LOGIN_REPLIES_PER_MINUTE = 20
local ORDERS_PER_PUSH = 10

---@param playerName any
---@return any
local function canonical(playerName) return addon.Utility.CanonicalName(playerName) or playerName end

---@param environment SyncEnvironment
---@return Sync
function Sync.New(environment)
    return setmetatable({ environment = environment, pending = {}, wanted = {}, wantedOffers = {}, wantedGames = {}, guildSent = {},
        peerRealm = {}, loginReplyBudget = 0, loginReplyBudgetStartedAt = 0,
        statistics = { sent = 0, received = 0, dropped = 0 } }, Sync)
end

---@return string|nil
function Sync:_me()
    local me = self.environment.me
    if type(me) == "function" then return me() end
    return me
end

-- the outcome of the message being handled (read by OnMessage and returned to the transport for the trace)
---@param status "ok"|"ignored"
---@param reason? string
function Sync:_note(status, reason)
    self.result = { status = status, reason = reason }
end

---@param message table
---@param channel string
---@param target? string
function Sync:_send(message, channel, target)
    self.statistics.sent = self.statistics.sent + 1
    self.environment.send(message, channel, target)
end

---@param delaySeconds number
---@param message table
---@param channel string
---@param target? string
function Sync:_later(delaySeconds, message, channel, target)
    table.insert(self.pending, { dueAt = self.environment.now() + delaySeconds, message = message, channel = channel, target = target })
end

---@return integer
function Sync:_myRevision()
    local characterRecord = self.environment.store.GetCharacter(self:_me())
    return characterRecord and characterRecord.rev or 0
end

---@param isLogin? boolean
---@return table message
function Sync:_helloMessage(isLogin)
    local offerRecord = addon.Offers.Get(self:_me())
    local gameRecord = addon.Games.Get(self:_me())
    return { t = "HELLO", rev = self:_myRevision(), login = isLogin or nil, odig = self.environment.orders:Digest(100),
        orev = (offerRecord and offerRecord.rev > 0) and offerRecord.rev or nil,
        grev = (gameRecord and gameRecord.rev > 0) and gameRecord.rev or nil }
end

---@param isLogin? boolean
function Sync:Hello(isLogin)
    self:_send(self:_helloMessage(isLogin), "GUILD")
end

---@param order Order
function Sync:BroadcastOrder(order)
    self:_send({ t = "ORDER", order = order }, "GUILD")
end

-- Handles one decoded message. A handler error is caught, logged with its stack and reported as "error".
---@param message any
---@param sender any canonical sender name
---@return "ok"|"ignored"|"dropped"|"error" status
---@return string|nil reason
function Sync:OnMessage(message, sender)
    self.statistics.received = self.statistics.received + 1
    if type(message) ~= "table" or type(message.t) ~= "string" or message.v ~= addon.PROTOCOL then
        self.statistics.dropped = self.statistics.dropped + 1
        return "dropped", "malformed or other protocol version"
    end
    if type(sender) ~= "string" or sender == self:_me() then
        self.statistics.dropped = self.statistics.dropped + 1
        return "dropped", "own echo"
    end
    local handler = self["_on" .. message.t]
    if not handler then
        self.statistics.dropped = self.statistics.dropped + 1
        return "dropped", "unknown message type " .. message.t
    end
    self.result = nil
    local ok, errorMessage = pcall(handler, self, message, sender)
    if not ok then
        self.statistics.dropped = self.statistics.dropped + 1
        -- a handler error is how invalid peer data is rejected (error("bad rev") etc.): a warning, not a crash report
        addon.Log.Warning("sync.message", "a message was rejected by its handler",
            { messageType = message.t, sender = sender, error = tostring(errorMessage) })
        return "error", (tostring(errorMessage):gsub("^.-:%d+: ", ""))   -- strip "file:line: " so the reason reads like the error()
    end
    local result = self.result or { status = "ok" }
    return result.status, result.reason
end

------------------------------------------------------------------ record pulls (character record and offers record)

---@class RecordKind
---@field requestType string message type of the request
---@field pullList string field of Sync holding the pulls of this kind
---@field label string
---@field heldRevision fun(sync: Sync, playerName: string): integer

---@type table<"char"|"offers"|"games", RecordKind>
local RECORD_KINDS = {
    char = { requestType = "WANT", pullList = "wanted", label = "char",
        heldRevision = function(sync, playerName)
            local characterRecord = sync.environment.store.GetCharacter(playerName)
            return characterRecord and characterRecord.rev or 0
        end },
    offers = { requestType = "WANTO", pullList = "wantedOffers", label = "offers",
        heldRevision = function(_, playerName)
            local offerRecord = addon.Offers.Get(playerName)
            return offerRecord and offerRecord.rev or 0
        end },
    games = { requestType = "WANTG", pullList = "wantedGames", label = "games",
        heldRevision = function(_, playerName)
            local gameRecord = addon.Games.Get(playerName)
            return gameRecord and gameRecord.rev or 0
        end },
}
Sync.RECORD_KINDS = RECORD_KINDS

-- Names a request carries: the full name, plus the first-name form a 0.4.0 member uses for itself (Utility.LegacyName).
-- `peerRealm` is the realm the member appends to names (learned from its own requests): a 0.4.0 member on another
-- realm of the guild only answers to "First-<its realm>", so that form is added too.
---@param sender string
---@param peerRealm string|nil
---@return string[]
function Sync.AskNames(sender, peerRealm)
    local legacyName = addon.Utility.LegacyName(sender)
    local names = legacyName and { sender, legacyName } or { sender }
    if legacyName and type(peerRealm) == "string" and peerRealm ~= "" then
        local firstName = legacyName:match("^([^-]+)")
        local nameOnPeerRealm = firstName .. "-" .. peerRealm
        if nameOnPeerRealm ~= legacyName then names[#names + 1] = nameOnPeerRealm end
    end
    return names
end

-- A member builds every name in a request with ITS realm: remember it, so requests to that member use its spelling.
---@param sender string
---@param names any
function Sync:_learnRealm(sender, names)
    if type(names) ~= "table" or type(names[1]) ~= "string" then return end
    local realmName = names[1]:match("^[^-]+-(.+)$")
    if realmName and addon.Utility.IsSafeName(realmName) and #realmName <= 48 then self.peerRealm[sender] = realmName end
end

-- A peer announced `revision` for its record of `kind`. Starts a pull when I am behind; returns a note for the trace.
---@param kind "char"|"offers"|"games"
---@param sender string
---@param revision integer
---@param now integer
---@return string note
function Sync:_pull(kind, sender, revision, now)
    local recordKind = RECORD_KINDS[kind]
    local heldRevision = recordKind.heldRevision(self, sender)
    if heldRevision >= revision then return recordKind.label .. ": up to date" end
    local pulls = self[recordKind.pullList]
    local pull = pulls[sender]
    if pull and pull.revision >= revision and not (pull.gaveUp and now - pull.startedAt >= Sync.GIVE_UP_RESET_SECONDS) then
        if pull.gaveUp then
            return ("%s: have %d < %d, gave up after %d tries"):format(recordKind.label, heldRevision, revision, pull.attempts)
        end
        return ("%s: have %d < %d, %s pending (try %d, %ds ago)"):format(recordKind.label, heldRevision, revision,
            recordKind.requestType, pull.attempts, now - pull.startedAt)
    end
    pulls[sender] = { revision = revision, startedAt = now, attempts = 1 }
    self:_send({ t = recordKind.requestType, names = Sync.AskNames(sender, self.peerRealm[sender]) }, "WHISPER", sender)
    return ("%s: have %d < %d -> %s"):format(recordKind.label, heldRevision, revision, recordKind.requestType)
end

-- Retries pulls that got no answer: tries 2 and 3 go out on GUILD (answered on GUILD). Satisfied pulls are forgotten.
---@param now integer
function Sync:_retry(now)
    for kind, recordKind in pairs(RECORD_KINDS) do
        local pulls = self[recordKind.pullList]
        for sender, pull in pairs(pulls) do
            if recordKind.heldRevision(self, sender) >= pull.revision then
                pulls[sender] = nil
            elseif not pull.gaveUp and now - pull.startedAt >= Sync.RETRY_SECONDS[pull.attempts] then
                if pull.attempts >= #Sync.RETRY_SECONDS then
                    pull.gaveUp, pull.startedAt = true, now
                    addon.Trace.Add({ dir = "sys", st = "warn", peer = sender, mt = recordKind.requestType,
                        why = ("no %s record after %d tries; their next HELLO starts a new pull"):format(kind, pull.attempts) })
                    addon.Log.Warning("sync.pull", "a record pull got no answer and was given up",
                        { kind = kind, peer = sender, attempts = pull.attempts, revision = pull.revision })
                else
                    pull.attempts, pull.startedAt = pull.attempts + 1, now
                    self:_send({ t = recordKind.requestType, names = Sync.AskNames(sender, self.peerRealm[sender]), via = "GUILD" }, "GUILD")
                end
            end
        end
    end
end

-- Answers a WANT/WANTO for my own record. `via = "GUILD"` answers on GUILD (deduplicated per revision), else by whisper.
---@param kind "char"|"offers"|"games"
---@param message table the request
---@param sender string
---@param answer table the message to send
---@param revision integer
function Sync:_answer(kind, message, sender, answer, revision)
    if message.via == "GUILD" then
        local lastGuildAnswer = self.guildSent[kind]
        local now = self.environment.now()
        if lastGuildAnswer and lastGuildAnswer.revision == revision and now - lastGuildAnswer.sentAt < Sync.GUILD_DEDUPLICATION_SECONDS then
            self:_note("ignored", ("asked on GUILD; rev %d already broadcast %ds ago"):format(revision, now - lastGuildAnswer.sentAt))
            return
        end
        self.guildSent[kind] = { revision = revision, sentAt = now }
        self:_later(self.environment.random() * 2, answer, "GUILD")
        self:_note("ok", "-> " .. answer.t .. " on GUILD scheduled")
    else
        self:_later(self.environment.random() * 2, answer, "WHISPER", sender)
        self:_note("ok", "-> " .. answer.t .. " scheduled")
    end
end

-- the name in `names` that means me (in any spelling of my realm), or nil
---@param names table
---@param myName string|nil
---@return string|nil
local function nameThatMeansMe(names, myName)
    for _, playerName in ipairs(names) do
        if type(playerName) == "string" and canonical(playerName) == myName then return playerName end
    end
    return nil
end

-- A whispered answer carries my record under the name the member asked with: a 0.4.0 member on another realm of the
-- guild accepts a record only when its name equals "my name-<its realm>". Updated members fold the realm either way.
---@param record table
---@param askedName string|nil
---@param message table the request
---@return table
local function recordUnderAskedName(record, askedName, message)
    if message.via == "GUILD" or type(askedName) ~= "string" or askedName == record.name then return record end
    local copy = {}
    for key, value in pairs(record) do copy[key] = value end
    copy.name = askedName
    return copy
end

---@param names table
---@return string
local function joinedNames(names)
    local texts = {}
    for index, playerName in ipairs(names) do texts[index] = tostring(playerName) end
    return table.concat(texts, ",")
end

------------------------------------------------------------------ handlers (named after the message type: _on<t>)

---@param message table
---@param sender string
function Sync:_onHELLO(message, sender)
    local environment = self.environment
    local now = environment.now()
    -- a rev is a server timestamp: finite, not negative, not from the future (+inf would make every client pull forever)
    if not addon.Utility.SafeInteger(message.rev, 0, addon.Store.Horizon()) then error("bad rev") end
    local notes = {}
    if message.rev > 0 then
        notes[#notes + 1] = self:_pull("char", sender, message.rev, now)
    else
        notes[#notes + 1] = "char: peer has no record yet"
    end
    -- offers record (protocol 2.1): same pull rule as the character record, validated like it
    if message.orev ~= nil and addon.Utility.SafeInteger(message.orev, 1, addon.Store.Horizon()) then
        notes[#notes + 1] = self:_pull("offers", sender, message.orev, now)
    elseif message.orev ~= nil then
        notes[#notes + 1] = "offers: invalid orev ignored"
    else
        notes[#notes + 1] = "offers: peer has none"
    end
    -- games record (protocol 2.3): same rule; a 2.2 peer simply never sends grev
    if message.grev ~= nil and addon.Utility.SafeInteger(message.grev, 1, addon.Store.Horizon()) then
        notes[#notes + 1] = self:_pull("games", sender, message.grev, now)
    elseif message.grev ~= nil then
        notes[#notes + 1] = "games: invalid grev ignored"
    end
    if message.login then -- a member just logged in: introduce myself after a random delay (storm control)
        if now - self.loginReplyBudgetStartedAt >= 60 then self.loginReplyBudgetStartedAt, self.loginReplyBudget = now, 0 end
        if self.loginReplyBudget < MAXIMUM_LOGIN_REPLIES_PER_MINUTE then
            self.loginReplyBudget = self.loginReplyBudget + 1
            self:_later(environment.random() * 10, self:_helloMessage(false), "WHISPER", sender)
            notes[#notes + 1] = "login -> HELLO reply scheduled"
        else
            notes[#notes + 1] = "login reply skipped (budget)"
        end
    end
    if type(message.odig) == "table" then
        local missingOrders = environment.orders:Missing(message.odig, 40)
        local batchStart = 1
        while batchStart <= #missingOrders do
            local batch = {}
            for index = batchStart, math.min(batchStart + ORDERS_PER_PUSH - 1, #missingOrders) do batch[#batch + 1] = missingOrders[index] end
            self:_later(1 + environment.random() * 5, { t = "OPUSH", orders = batch }, "WHISPER", sender)
            batchStart = batchStart + ORDERS_PER_PUSH
        end
        if #missingOrders > 0 then notes[#notes + 1] = ("orders: peer lacks %d -> OPUSH"):format(#missingOrders) end
    end
    self:_note("ok", table.concat(notes, "; "))
end

-- shared by WANT and WANTO: returns the name the request used for me, or nil after noting why it is ignored
---@param message table
---@param sender string
---@return string|nil askedName
function Sync:_requestedName(message, sender)
    if type(message.names) ~= "table" then error("bad names") end
    self:_learnRealm(sender, message.names)
    local myName = self:_me()
    local askedName = nameThatMeansMe(message.names, myName)
    if askedName then return askedName end
    -- on GUILD every member sees every request: only a whisper asking for "me" in a foreign form is a real mismatch
    if message.via == "GUILD" then
        self:_note("ignored", "request for " .. joinedNames(message.names))
    else
        self:_note("ignored", ("asked for %s but I am %s (name mismatch)"):format(joinedNames(message.names), tostring(myName)))
    end
    return nil
end

---@param message table
---@param sender string
function Sync:_onWANT(message, sender)
    local environment = self.environment
    local askedName = self:_requestedName(message, sender)
    if not askedName then return end
    local myRecord = environment.store.GetCharacter(self:_me())
    if not myRecord then self:_note("ignored", "asked for my record but I have none (no profession scanned)") return end
    local catalogEntries = {}
    for _, profession in pairs(myRecord.professions or {}) do
        for recipeID in pairs(profession.recipes or {}) do
            local catalogEntry = environment.store.GetRecipe(recipeID)
            if catalogEntry then catalogEntries[recipeID] = catalogEntry end
        end
    end
    self:_answer("char", message, sender,
        { t = "SNAP", char = recordUnderAskedName(myRecord, askedName, message), catalog = catalogEntries }, myRecord.rev or 0)
end

---@param message table
---@param sender string
function Sync:_onWANTO(message, sender)
    local askedName = self:_requestedName(message, sender)
    if not askedName then return end
    local myOffers = addon.Offers.Get(self:_me())
    if not myOffers then self:_note("ignored", "asked for my offers but I have none") return end
    self:_answer("offers", message, sender, { t = "OFFERS", offers = recordUnderAskedName(myOffers, askedName, message) },
        myOffers.rev or 0)
end

---@param message table
---@param sender string
function Sync:_onOFFERS(message, sender)
    local offerRecord = addon.Offers.Sanitize(message.offers)
    if not offerRecord then error("invalid offers") end
    if canonical(offerRecord.name) ~= sender then   -- a peer authors only its own record
        error(("offers/sender mismatch: record %s from %s"):format(offerRecord.name, sender))
    end
    offerRecord.name = sender
    local dibs = {}   -- dib keys name other players: stored under their canonical names too
    for offerKey, dib in pairs(offerRecord.dibs) do
        local owner, itemID = addon.Offers.ParseKey(offerKey)
        if owner then dibs[addon.Offers.Key(canonical(owner), itemID)] = dib end
    end
    offerRecord.dibs = dibs
    if addon.Offers.Put(offerRecord) then
        self.environment.onChange("offers")
        self:_note("ok", "stored")
    else
        self:_note("ignored", "not newer than what I hold")
    end
end

---@param message table
---@param sender string
function Sync:_onWANTG(message, sender)
    local askedName = self:_requestedName(message, sender)
    if not askedName then return end
    local myGames = addon.Games.Mine(self:_me())   -- never a simulated record: those live outside the db
    if not myGames then self:_note("ignored", "asked for my games but I have none") return end
    self:_answer("games", message, sender, { t = "GAMES", games = recordUnderAskedName(myGames, askedName, message) },
        myGames.rev or 0)
end

---@param message table
---@param sender string
function Sync:_onGAMES(message, sender)
    local gameRecord = addon.Games.Sanitize(message.games)
    if not gameRecord then error("invalid games") end
    if canonical(gameRecord.name) ~= sender then   -- a peer authors only its own record
        error(("games/sender mismatch: record %s from %s"):format(gameRecord.name, sender))
    end
    gameRecord.name = sender
    if addon.Games.Put(gameRecord) then
        self.environment.onChange("games")
        self:_note("ok", "stored")
    else
        self:_note("ignored", "not newer than what I hold")
    end
end

---@param message table
---@param sender string
function Sync:_onSNAP(message, sender)
    local environment = self.environment
    -- allow-list copy: only validated fields of the record are ever stored
    local characterRecord = environment.store.SanitizeCharacter(message.char)
    if not characterRecord then error("invalid char") end
    if canonical(characterRecord.name) ~= sender then
        error(("char/sender mismatch: record %s from %s"):format(characterRecord.name, sender))
    end
    characterRecord.name = sender
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
    environment.store.PutCatalog(acceptedEntries)
    if environment.store.PutCharacter(characterRecord) then
        environment.onChange("chars")
        self:_note("ok", "stored")
    else
        self:_note("ignored", "not newer than what I hold")
    end
end

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

---@param message table
function Sync:_onOPUSH(message)
    local environment = self.environment
    if type(message.orders) ~= "table" then error("bad orders") end
    local changed, changedCount = false, 0
    for index, order in ipairs(message.orders) do
        if index > ORDERS_PER_PUSH then break end
        if environment.orders:Merge(canonicalOrder(order)) then changed = true; changedCount = changedCount + 1 end
    end
    if changed then environment.onChange("orders") end
    self:_note(changed and "ok" or "ignored", ("%d of %d orders changed"):format(changedCount, math.min(#message.orders, ORDERS_PER_PUSH)))
end

---@param message table
function Sync:_onORDER(message)
    if self.environment.orders:Merge(canonicalOrder(message.order)) then
        self.environment.onChange("orders")
        self:_note("ok", "merged")
    else
        self:_note("ignored", addon.Orders.Sanitize(message.order) and "no change" or "invalid order")
    end
end

-- Send everything that is due and retry unanswered pulls. Call about once per second.
---@param now integer
function Sync:Tick(now)
    local stillPending = {}
    for _, pendingSend in ipairs(self.pending) do
        if pendingSend.dueAt <= now then self:_send(pendingSend.message, pendingSend.channel, pendingSend.target)
        else stillPending[#stillPending + 1] = pendingSend end
    end
    self.pending = stillPending
    self:_retry(now)
end
