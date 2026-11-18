-- LibGuildSync: generic record-pull protocol engine, one instance per addon channel (Sync.New). Pure: all I/O goes
-- through `environment`, so it is testable offline.
--
-- An addon registers RECORD KINDS: records that one character authors and every guild member keeps a copy of (the newer
-- `rev` wins). For every kind the engine runs the same protocol:
--   HELLO {<helloField> = my revision, login?, ...}   broadcast (GUILD) or reply (WHISPER)
--   <requestType> {names, via?}                         "send me your record" (whisper; retries on GUILD with via="GUILD")
--   <answerType>  {<recordField> = record, ...}         the record; only its author may send it (name == sender)
-- Pulls: the first request is a whisper. If the record has not arrived after RETRY_SECONDS[1] seconds the request is
-- repeated on GUILD with via = "GUILD", and the owner answers on GUILD, so a failing whisper path cannot block sync;
-- one GUILD answer also serves every other member that was behind. After the last try the pull gives up; the peer's next
-- HELLO restarts it once GIVE_UP_RESET_SECONDS have passed.
-- Addons add their own HELLO fields and message types with AddHelloHook and AddHandler (TalentShare's orders).
-- OnMessage returns (status, reason): "ok" | "ignored" | "dropped" | "error", for the network trace.
-- Every player name from the wire is compared and stored in canonical form (Utility.CanonicalName).
local lib = LibStub("LibGuildSync-1.0")
local Sync = lib:Module("Sync", 1)
if not Sync then return end

---@class SyncEnvironment
---@field send fun(message: table, channel: string, target?: string)
---@field now fun(): integer server time
---@field random fun(): number in [0, 1)
---@field me string|fun(): string|nil my canonical name, or a function returning it (read at use time)
---@field protocol integer the protocol major every message must carry in `v`
---@field horizon? fun(): number the latest acceptable timestamp (default: no upper bound)
---@field onChange? fun(changeKind: string) a record of that kind was stored
---@field log? table the addon's Log instance
---@field trace? table the addon's Trace instance

---@class RecordKind
---@field name string key of the kind ("char", "offers", "games")
---@field label string prefix of trace notes and error texts
---@field helloField string HELLO field carrying the owner's revision
---@field required? boolean the field must be in every HELLO (0 = "no record yet"); otherwise it is optional (>= 1)
---@field absentNote? string trace note when an optional field is missing
---@field requestType string message type of the request
---@field answerType string message type of the record message
---@field recordField string field of the record message holding the record
---@field changeKind? string passed to environment.onChange (default: name)
---@field heldRevision fun(playerName: string): integer revision of that player's record I hold (0 = none)
---@field myRecord fun(myName: string|nil): table|nil my own record (to announce and to answer with)
---@field noneNote? string trace note when asked for my record while I have none
---@field sanitize fun(record: any): table|nil a CLEAN COPY of a peer's record, or nil when it is invalid
---@field store fun(sync: table, record: table, message: table, sender: string): boolean keeps the record; true when it was newer
---@field answer? fun(sync: table, record: table, message: table): table builds the answer (default: { t = answerType, [recordField] = record })

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

---@class SyncHelloHook
---@field build? fun(sync: table, message: table) adds fields to my HELLO
---@field handle? fun(sync: table, message: table, sender: string, notes: string[]) reads a peer's HELLO

---@type integer[] seconds to wait after attempt n before the next one; after the last: give up
Sync.RETRY_SECONDS = Sync.RETRY_SECONDS or { 45, 90, 180 }
-- A HELLO is fresh proof that the peer is online: it restarts a pull that gave up once this long has passed. A longer
-- lock (TalentShare 0.4.1 draft: 10 min) left members without a record for minutes after a few lost messages.
Sync.GIVE_UP_RESET_SECONDS = 60
-- an answer on GUILD for the same revision is sent at most once per this many seconds
Sync.GUILD_DEDUPLICATION_SECONDS = 60
Sync.MAXIMUM_LOGIN_REPLIES_PER_MINUTE = 20

---@param playerName any
---@return any
local function canonical(playerName) return lib.Utility.CanonicalName(playerName) or playerName end

-- the instance methods (sync:Tick(now), sync:OnMessage(...)) are looked up on the module table at call time
Sync.instanceMetatable = Sync.instanceMetatable or {}
Sync.instanceMetatable.__index = Sync

---@param environment SyncEnvironment
---@return table sync
function Sync.New(environment)
    return setmetatable({ environment = environment, pending = {}, pulls = {}, kinds = {}, kindOrder = {}, helloHooks = {},
        handlers = {}, guildSent = {}, peerRealm = {}, loginReplyBudget = 0, loginReplyBudgetStartedAt = 0,
        statistics = { sent = 0, received = 0, dropped = 0 } }, Sync.instanceMetatable)
end

-- Registers a record kind (see RecordKind). Kinds announce and are checked in registration order.
---@param kind RecordKind
---@return table pulls the kind's pull table (peer -> RecordPull)
function Sync:AddRecordKind(kind)
    assert(type(kind.name) == "string" and not self.kinds[kind.name], "record kind needs a new name")
    kind.label = kind.label or kind.name
    self.kinds[kind.name] = kind
    self.kindOrder[#self.kindOrder + 1] = kind
    self.pulls[kind.name] = self.pulls[kind.name] or {}
    return self.pulls[kind.name]
end

-- Adds fields to my HELLO and/or reads a peer's (runs after the record kinds and the login reply).
---@param hook SyncHelloHook
function Sync:AddHelloHook(hook) self.helloHooks[#self.helloHooks + 1] = hook end

-- Handles an addon-specific message type: handler(sync, message, sender). Errors reject the message ("error").
---@param messageType string
---@param handler fun(sync: table, message: table, sender: string)
function Sync:AddHandler(messageType, handler) self.handlers[messageType] = handler end

---@return string|nil
function Sync:_me()
    local me = self.environment.me
    if type(me) == "function" then return me() end
    return me
end

---@return number
function Sync:_horizon()
    local horizon = self.environment.horizon
    return horizon and horizon() or math.huge
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

---@param isLogin? boolean
---@return table message
function Sync:_helloMessage(isLogin)
    local message = { t = "HELLO", login = isLogin or nil }
    local myName = self:_me()
    for _, kind in ipairs(self.kindOrder) do
        local record = kind.myRecord(myName)
        local revision = record and tonumber(record.rev) or 0
        if kind.required then message[kind.helloField] = revision
        elseif revision > 0 then message[kind.helloField] = revision end
    end
    for _, hook in ipairs(self.helloHooks) do
        if hook.build then hook.build(self, message) end
    end
    return message
end

---@param isLogin? boolean
function Sync:Hello(isLogin)
    self:_send(self:_helloMessage(isLogin), "GUILD")
end

---@param messageType string
---@return function|nil
function Sync:_handlerFor(messageType)
    if messageType == "HELLO" then return Sync._onHello end
    for _, kind in ipairs(self.kindOrder) do
        if messageType == kind.requestType then return function(sync, message, sender) return sync:_onRequest(kind, message, sender) end end
        if messageType == kind.answerType then return function(sync, message, sender) return sync:_onRecord(kind, message, sender) end end
    end
    return self.handlers[messageType]
end

-- Handles one decoded message. A handler error is caught, logged and reported as "error".
---@param message any
---@param sender any canonical sender name
---@return "ok"|"ignored"|"dropped"|"error" status
---@return string|nil reason
function Sync:OnMessage(message, sender)
    self.statistics.received = self.statistics.received + 1
    if type(message) ~= "table" or type(message.t) ~= "string" or message.v ~= self.environment.protocol then
        self.statistics.dropped = self.statistics.dropped + 1
        return "dropped", "malformed or other protocol version"
    end
    if type(sender) ~= "string" or sender == self:_me() then
        self.statistics.dropped = self.statistics.dropped + 1
        return "dropped", "own echo"
    end
    local handler = self:_handlerFor(message.t)
    if not handler then
        self.statistics.dropped = self.statistics.dropped + 1
        return "dropped", "unknown message type " .. message.t
    end
    self.result = nil
    local ok, errorMessage = pcall(handler, self, message, sender)
    if not ok then
        self.statistics.dropped = self.statistics.dropped + 1
        -- a handler error is how invalid peer data is rejected (error("bad rev") etc.): a warning, not a crash report
        if self.environment.log then
            self.environment.log.Warning("sync.message", "a message was rejected by its handler",
                { messageType = message.t, sender = sender, error = tostring(errorMessage) })
        end
        return "error", (tostring(errorMessage):gsub("^.-:%d+: ", ""))   -- strip "file:line: " so the reason reads like the error()
    end
    local result = self.result or { status = "ok" }
    return result.status, result.reason
end

------------------------------------------------------------------ record pulls

-- Names a request carries: the full name, plus the first-name form an old client uses for itself (Utility.LegacyName).
-- `peerRealm` is the realm the member appends to names (learned from its own requests): such a member on another realm
-- only answers to "First-<its realm>", so that form is added too.
---@param sender string
---@param peerRealm string|nil
---@return string[]
function Sync.AskNames(sender, peerRealm)
    local legacyName = lib.Utility.LegacyName(sender)
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
    if realmName and lib.Utility.IsSafeName(realmName) and #realmName <= 48 then self.peerRealm[sender] = realmName end
end

-- A peer announced `revision` for its record of `kind`. Starts a pull when I am behind; returns a note for the trace.
---@param kind RecordKind
---@param sender string
---@param revision integer
---@param now integer
---@return string note
function Sync:_pull(kind, sender, revision, now)
    local heldRevision = kind.heldRevision(sender)
    if heldRevision >= revision then return kind.label .. ": up to date" end
    local pulls = self.pulls[kind.name]
    local pull = pulls[sender]
    if pull and pull.revision >= revision and not (pull.gaveUp and now - pull.startedAt >= Sync.GIVE_UP_RESET_SECONDS) then
        if pull.gaveUp then
            return ("%s: have %d < %d, gave up after %d tries"):format(kind.label, heldRevision, revision, pull.attempts)
        end
        return ("%s: have %d < %d, %s pending (try %d, %ds ago)"):format(kind.label, heldRevision, revision,
            kind.requestType, pull.attempts, now - pull.startedAt)
    end
    pulls[sender] = { revision = revision, startedAt = now, attempts = 1 }
    self:_send({ t = kind.requestType, names = Sync.AskNames(sender, self.peerRealm[sender]) }, "WHISPER", sender)
    return ("%s: have %d < %d -> %s"):format(kind.label, heldRevision, revision, kind.requestType)
end

-- Retries pulls that got no answer: tries 2 and 3 go out on GUILD (answered on GUILD). Satisfied pulls are forgotten.
---@param now integer
function Sync:_retry(now)
    for _, kind in ipairs(self.kindOrder) do
        local pulls = self.pulls[kind.name]
        for sender, pull in pairs(pulls) do
            if kind.heldRevision(sender) >= pull.revision then
                pulls[sender] = nil
            elseif not pull.gaveUp and now - pull.startedAt >= Sync.RETRY_SECONDS[pull.attempts] then
                if pull.attempts >= #Sync.RETRY_SECONDS then
                    pull.gaveUp, pull.startedAt = true, now
                    if self.environment.trace then
                        self.environment.trace.Add({ dir = "sys", st = "warn", peer = sender, mt = kind.requestType,
                            why = ("no %s record after %d tries; their next HELLO starts a new pull"):format(kind.name, pull.attempts) })
                    end
                    if self.environment.log then
                        self.environment.log.Warning("sync.pull", "a record pull got no answer and was given up",
                            { kind = kind.name, peer = sender, attempts = pull.attempts, revision = pull.revision })
                    end
                else
                    pull.attempts, pull.startedAt = pull.attempts + 1, now
                    self:_send({ t = kind.requestType, names = Sync.AskNames(sender, self.peerRealm[sender]), via = "GUILD" }, "GUILD")
                end
            end
        end
    end
end

-- Re-keys every pull table by canonical name (after a new spelling of my realm was learned).
function Sync:CanonicalizePulls()
    for _, pulls in pairs(self.pulls) do
        local canonicalPulls = {}
        for playerName, pull in pairs(pulls) do canonicalPulls[canonical(playerName)] = pull end
        lib.Utility.Refill(pulls, canonicalPulls)
    end
end

-- Answers a request for my own record. `via = "GUILD"` answers on GUILD (deduplicated per revision), else by whisper.
---@param kindName string
---@param message table the request
---@param sender string
---@param answer table the message to send
---@param revision integer
function Sync:_answer(kindName, message, sender, answer, revision)
    if message.via == "GUILD" then
        local lastGuildAnswer = self.guildSent[kindName]
        local now = self.environment.now()
        if lastGuildAnswer and lastGuildAnswer.revision == revision and now - lastGuildAnswer.sentAt < Sync.GUILD_DEDUPLICATION_SECONDS then
            self:_note("ignored", ("asked on GUILD; rev %d already broadcast %ds ago"):format(revision, now - lastGuildAnswer.sentAt))
            return
        end
        self.guildSent[kindName] = { revision = revision, sentAt = now }
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

-- A whispered answer carries my record under the name the member asked with: an old client on another realm accepts a
-- record only when its name equals "my name-<its realm>". Updated members fold the realm either way.
---@param record table
---@param askedName string|nil
---@param message table the request
---@return table
function Sync.RecordUnderAskedName(record, askedName, message)
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

------------------------------------------------------------------ built-in handlers

---@param message table
---@param sender string
function Sync:_onHello(message, sender)
    local environment = self.environment
    local now = environment.now()
    local horizon = self:_horizon()
    local SafeInteger = lib.Utility.SafeInteger
    local notes = {}
    for _, kind in ipairs(self.kindOrder) do
        local revision = message[kind.helloField]
        if kind.required then
            -- a rev is a server timestamp: finite, not negative, not from the future (+inf would make every client pull forever)
            if not SafeInteger(revision, 0, horizon) then error("bad " .. kind.helloField) end
            if revision > 0 then
                notes[#notes + 1] = self:_pull(kind, sender, revision, now)
            else
                notes[#notes + 1] = kind.label .. ": peer has no record yet"
            end
        elseif revision ~= nil and SafeInteger(revision, 1, horizon) then
            notes[#notes + 1] = self:_pull(kind, sender, revision, now)
        elseif revision ~= nil then
            notes[#notes + 1] = kind.label .. ": invalid " .. kind.helloField .. " ignored"
        elseif kind.absentNote then
            notes[#notes + 1] = kind.absentNote
        end
    end
    if message.login then -- a member just logged in: introduce myself after a random delay (storm control)
        if now - self.loginReplyBudgetStartedAt >= 60 then self.loginReplyBudgetStartedAt, self.loginReplyBudget = now, 0 end
        if self.loginReplyBudget < Sync.MAXIMUM_LOGIN_REPLIES_PER_MINUTE then
            self.loginReplyBudget = self.loginReplyBudget + 1
            self:_later(environment.random() * 10, self:_helloMessage(false), "WHISPER", sender)
            notes[#notes + 1] = "login -> HELLO reply scheduled"
        else
            notes[#notes + 1] = "login reply skipped (budget)"
        end
    end
    for _, hook in ipairs(self.helloHooks) do
        if hook.handle then hook.handle(self, message, sender, notes) end
    end
    self:_note("ok", table.concat(notes, "; "))
end

-- returns the name the request used for me, or nil after noting why it is ignored
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

---@param kind RecordKind
---@param message table
---@param sender string
function Sync:_onRequest(kind, message, sender)
    local askedName = self:_requestedName(message, sender)
    if not askedName then return end
    local myRecord = kind.myRecord(self:_me())
    if not myRecord then self:_note("ignored", kind.noneNote or ("asked for my " .. kind.label .. " but I have none")) return end
    local record = Sync.RecordUnderAskedName(myRecord, askedName, message)
    local answer = kind.answer and kind.answer(self, record, message) or { t = kind.answerType, [kind.recordField] = record }
    self:_answer(kind.name, message, sender, answer, myRecord.rev or 0)
end

---@param kind RecordKind
---@param message table
---@param sender string
function Sync:_onRecord(kind, message, sender)
    local record = kind.sanitize(message[kind.recordField])   -- allow-list copy: only validated fields are ever stored
    if not record then error("invalid " .. kind.label) end
    if canonical(record.name) ~= sender then   -- a peer authors only its own record
        error(("%s/sender mismatch: record %s from %s"):format(kind.label, tostring(record.name), sender))
    end
    record.name = sender
    if kind.store(self, record, message, sender) then
        if self.environment.onChange then self.environment.onChange(kind.changeKind or kind.name) end
        self:_note("ok", "stored")
    else
        self:_note("ignored", "not newer than what I hold")
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
