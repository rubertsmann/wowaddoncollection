local addonName, addon = ...

-- Transport: chunks encoded messages to <= 255 bytes, paces sends (token bucket), reassembles received chunks,
-- and wires Sync to the guild. Not in a guild -> inactive (no sends, no errors).
-- Every message in and out is recorded in the network trace (Core/Debug/Trace.lua, feature 008): one entry per message,
-- whose status is updated as it moves (out: queued -> sent | failed; in: the decision Sync took, or why it never got
-- there). Failures are also written to the log (addon.Log) with the details needed to explain them.

---@class QueuedChunk
---@field channel string "GUILD"|"WHISPER"
---@field target? string canonical whisper target (resolved to the client's form when sent)
---@field text string header + payload, one addon message
---@field traceEntry TraceEntry the message's trace entry (status updated as chunks leave)

---@class ReceiveBuffer
---@field partCount integer
---@field parts table<integer, string>
---@field receivedCount integer
---@field startedAt integer
---@field sender string canonical
---@field channel string
---@field raw string the sender as the client reported it

---@class InFlightTransfer
---@field sender string
---@field receivedCount integer
---@field partCount integer
---@field ageSeconds integer

---@class CommunicationModule
local Communication = {}
addon.Communication = Communication

local Text = addon.Text
local Codec, Guard, Trace = addon.Codec, addon.Guard, addon.Trace
-- one definition (Codec): Decode accepts what we can send
local CHUNK_BYTES, MAXIMUM_PARTS = Codec.CHUNK_BYTES, Codec.MAXIMUM_PARTS
local BUCKET_CAPACITY, REFILL_PER_SECOND = 5, 0.9   -- messages burst / refill per second (server allows 10 burst, 1/s)
local MAXIMUM_QUEUED_CHUNKS = 600
local THROTTLE_RESULT_CODE = 3   -- Enum.SendAddonMessageResult.AddonMessageThrottle

---@type boolean
Communication.active = false
---@type boolean set at PLAYER_LOGIN: before it, the current character's name is not known yet
Communication.ready = false
---@type QueuedChunk[]
Communication.queue = {}
---@type table<string, ReceiveBuffer> by "sender:transferID"
Communication.buffers = {}
---@type number send tokens available
Communication.tokens = BUCKET_CAPACITY
---@type integer
Communication.lastHello = 0
---@type integer
Communication.messageCounter = 0
---@type integer random per session (Communication.Init): ids never repeat across /reload while stale buffers exist
Communication.salt = 0
---@type table<string, boolean> set of "Name-Realm" as of the last roster update; WHISPERs from anyone else are dropped
Communication.roster = {}
---@type IncompatibilityHints
Communication.hints = Guard.NewHints()
---@type integer chunks dropped by the gate or for a foreign protocol (shown by /ts comm)
Communication.rejected = 0
Communication.chunksSent, Communication.chunksReceived = 0, 0
---@type integer
Communication.sendFailures = 0
---@type boolean
Communication.identityWarned = false
---@type integer|nil the Utility.realmAliasVersion stored names were last canonicalized for
Communication.canonicalNameVersion = nil
---@type string|nil my own name as the server spelled it in my last GUILD echo
Communication.lastEcho = nil
---@type Sync|nil
Communication.sync = nil

---@return string|nil
local function me() return addon.Utility.Me() end
Communication.Me = me

------------------------------------------------------------------ send result codes
-- Modern clients return an Enum.SendAddonMessageResult (0 = Success), older ones a boolean, very old ones nothing.
---@type table<integer, string>
local RESULT_NAMES = { [0] = "Success", "InvalidPrefix", "InvalidMessage", "AddonMessageThrottle", "InvalidChatType",
    "NotInGroup", "TargetRequired", "InvalidChannel", "ChannelThrottle", "GeneralError", "NotInGuild",
    "AddOnMessageLockdown", "TargetOffline" }

---@param resultCode any
---@return string
local function resultName(resultCode)
    local resultEnumeration = Enum and Enum.SendAddonMessageResult
    if type(resultEnumeration) == "table" then
        for name, code in pairs(resultEnumeration) do if code == resultCode then return name end end
    end
    return RESULT_NAMES[resultCode] or ("code " .. tostring(resultCode))
end

-- Whether a SendAddonMessage call (as returned by pcall) delivered the chunk to the client; false and why otherwise.
---@param ok boolean
---@param result any
---@return boolean delivered
---@return string|nil reason
local function interpretResult(ok, result)
    if not ok then return false, "lua error: " .. tostring(result) end
    if result == nil or result == true or result == 0 then return true end
    if result == false then return false, "SendAddonMessage returned false" end
    if type(result) == "number" then return false, resultName(result) end
    return true
end
Communication.InterpretResult = interpretResult

------------------------------------------------------------------ outbound

---@type table<string, boolean> small single-chunk control messages that jump the queue
local PRIORITY_TYPES = { ORDER = true, WANT = true, WANTO = true, HELLO = true }

-- Encodes and queues a message (Sync's environment.send). Failures are traced and logged, never thrown.
---@param message table
---@param channel string
---@param target? string
function Communication.Send(message, channel, target)
    if not Communication.active then return end
    local traceEntry = Trace.Add({ dir = "out", ch = channel, peer = target, mt = message.t, st = "queued", info = Trace.Summarize(message) })
    local ok, encoded = pcall(Codec.Encode, message)
    if not ok then
        addon.Log.Exception("communication.send", "a message could not be encoded", encoded,
            { messageType = message.t, channel = channel, target = target })
        traceEntry.st, traceEntry.why = "failed", "encode: " .. tostring(encoded)
        return
    end
    Communication.messageCounter = Communication.messageCounter + 1
    local transferID = string.format("%04x%x", Communication.salt % 65536, Communication.messageCounter % 65536)
    local partCount = math.ceil(#encoded / CHUNK_BYTES)
    traceEntry.parts, traceEntry.bytes = partCount, #encoded
    if partCount > MAXIMUM_PARTS then
        addon.Log.Error("communication.send", "a message is too big to send and was dropped",
            { messageType = message.t, bytes = #encoded, parts = partCount, maximumParts = MAXIMUM_PARTS })
        traceEntry.st, traceEntry.why = "dropped", ("too big: %d chunks > %d"):format(partCount, MAXIMUM_PARTS)
        return
    end
    if #Communication.queue + partCount > MAXIMUM_QUEUED_CHUNKS then
        addon.Log.Error("communication.send", "the send queue is full; a message was dropped",
            { messageType = message.t, queuedChunks = #Communication.queue, parts = partCount })
        traceEntry.st, traceEntry.why = "dropped", ("send queue full (%d chunks waiting)"):format(#Communication.queue)
        return
    end
    traceEntry.sentParts = 0
    for partIndex = 1, partCount do
        local payload = encoded:sub((partIndex - 1) * CHUNK_BYTES + 1, partIndex * CHUNK_BYTES)
        local queuedChunk = { channel = channel, target = target, text = Codec.Header(transferID, partIndex, partCount) .. payload,
            traceEntry = traceEntry }
        if PRIORITY_TYPES[message.t] then
            table.insert(Communication.queue, 1, queuedChunk)
        else
            Communication.queue[#Communication.queue + 1] = queuedChunk
        end
    end
end

-- Sends queued chunks while tokens last. `elapsedSeconds` refills the bucket.
---@param elapsedSeconds number
local function pump(elapsedSeconds)
    Communication.tokens = math.min(BUCKET_CAPACITY, Communication.tokens + elapsedSeconds * REFILL_PER_SECOND)
    while Communication.tokens >= 1 and #Communication.queue > 0 do
        local queuedChunk = table.remove(Communication.queue, 1)
        -- same realm: name only (Utility.WhisperTarget)
        local resolvedTarget = queuedChunk.channel == "WHISPER" and addon.Utility.WhisperTarget(queuedChunk.target) or queuedChunk.target
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, addon.PREFIX, queuedChunk.text, queuedChunk.channel, resolvedTarget)
        if ok and type(result) == "number" and result == THROTTLE_RESULT_CODE then   -- throttled: retry later
            table.insert(Communication.queue, 1, queuedChunk)
            Communication.tokens = 0
            break
        end
        local delivered, reason = interpretResult(ok, result)
        local traceEntry = queuedChunk.traceEntry
        if traceEntry then
            if resolvedTarget ~= queuedChunk.target then traceEntry.via = resolvedTarget end
            if delivered then
                traceEntry.sentParts = (traceEntry.sentParts or 0) + 1
                if traceEntry.st == "queued" and traceEntry.sentParts >= (traceEntry.parts or 1) then traceEntry.st = "sent" end
            else
                traceEntry.st, traceEntry.why = "failed", reason
            end
        end
        if not delivered then
            Communication.sendFailures = Communication.sendFailures + 1
            addon.Log.Error("communication.send", "the client refused an addon message",
                { reason = reason, channel = queuedChunk.channel, target = resolvedTarget,
                  messageType = traceEntry and traceEntry.mt })
        end
        Communication.chunksSent = Communication.chunksSent + 1
        Communication.tokens = Communication.tokens - 1
    end
end

Communication._pump = pump   -- offline tests drive the pump directly

------------------------------------------------------------------ inbound

-- Rejections can arrive once per chunk; one trace entry per (sender, reason) every 30 s is enough to see them.
---@type table<string, integer>
local lastRejectionTraced = {}
---@param channel string
---@param sender string|nil
---@param raw string
---@param reason string
local function traceRejection(channel, sender, raw, reason)
    local rejectionKey = tostring(sender) .. "|" .. reason
    local now = addon.Utility.Now()
    if lastRejectionTraced[rejectionKey] and now - lastRejectionTraced[rejectionKey] < 30 then return end
    lastRejectionTraced[rejectionKey] = now
    Trace.Add({ dir = "in", ch = channel, peer = sender, raw = raw, st = "rejected", why = reason })
end

-- One notice per kind per session; the sender is only recorded (bounded), never printed.
---@param kind HintKind
---@param sender string
local function noteIncompatiblePeer(kind, sender)
    Communication.rejected = Communication.rejected + (kind == "newer-minor" and 0 or 1)
    if not Guard.Note(Communication.hints, kind, sender) then return end
    addon.Log.Warning("communication.version", "a guild member runs an incompatible or newer version", { kind = kind, sender = sender })
    if kind == "newer" then
        addon.Print(Text["A guild member runs a newer TalentShare that cannot sync with this version. Please update the addon."])
    elseif kind == "older" then
        addon.Print(Text["A guild member runs an older TalentShare that cannot sync with this version."])
    else
        addon.Print(Text["A guild member runs a newer TalentShare with extra features. Updating is recommended."])
    end
end

-- One accepted chunk: buffered until its message is complete, then decoded and handed to Sync.
---@param text string
---@param sender string canonical
---@param channel string
---@param raw string the sender as the client reported it
local function onChunk(text, sender, channel, raw)
    local header, reason = Codec.ParseHeader(text)
    if not header then
        if reason == "legacy" then noteIncompatiblePeer("older", sender) end   -- 0.1/0.2 builds: no version in the header
        traceRejection(channel, sender, raw, reason == "legacy" and "legacy 0.1/0.2 header" or "malformed chunk header")
        return
    end
    if header.major ~= addon.PROTOCOL_MAJOR then
        noteIncompatiblePeer(Codec.Compatibility(header.major, header.minor), sender)   -- before any buffer is allocated
        traceRejection(channel, sender, raw, ("protocol %d.%d, mine %d.%d"):format(header.major, header.minor,
            addon.PROTOCOL_MAJOR, addon.PROTOCOL_MINOR))
        return
    end
    if Codec.Compatibility(header.major, header.minor) == "newer-minor" then noteIncompatiblePeer("newer-minor", sender) end
    Communication.chunksReceived = Communication.chunksReceived + 1
    local bufferKey = sender .. ":" .. header.transferID
    local buffer = Communication.buffers[bufferKey]
    if not buffer or buffer.partCount ~= header.partCount then
        buffer = { partCount = header.partCount, parts = {}, receivedCount = 0, startedAt = addon.Utility.Now(), sender = sender,
            channel = channel, raw = raw }
        Communication.buffers[bufferKey] = buffer
    end
    if not buffer.parts[header.partIndex] then
        buffer.parts[header.partIndex] = header.payload
        buffer.receivedCount = buffer.receivedCount + 1
    end
    if buffer.receivedCount == header.partCount then
        Communication.buffers[bufferKey] = nil
        local encoded = table.concat(buffer.parts)
        local traceEntry = Trace.Add({ dir = "in", ch = channel, peer = sender, raw = raw, st = "error", parts = header.partCount,
            bytes = #encoded })
        local message, decodeReason = Codec.Decode(encoded)
        if message then
            traceEntry.mt, traceEntry.info = message.t, Trace.Summarize(message)
            local status, handlerReason = Communication.sync:OnMessage(message, sender)
            traceEntry.st, traceEntry.why = status or "ok", handlerReason
        else
            Communication.sync.statistics.dropped = Communication.sync.statistics.dropped + 1
            addon.Log.Warning("communication.receive", "a received message could not be decoded",
                { sender = sender, reason = decodeReason, bytes = #encoded })
            traceEntry.why = "decode: " .. tostring(decodeReason)
        end
    end
end

-- Entry point for CHAT_MSG_ADDON. The gate runs FIRST: nothing from outside the guild is parsed, buffered or answered.
---@param prefix string
---@param text string
---@param channel string
---@param rawSender string
function Communication.OnAddonMessage(prefix, text, channel, rawSender)
    if prefix ~= addon.PREFIX or not Communication.active or type(text) ~= "string" or type(rawSender) ~= "string" then return end
    if channel == "GUILD" and Communication.LearnFromEcho(text, rawSender) then   -- only the server-filtered guild channel teaches
        Communication.lastEcho = rawSender
        return
    end
    local sender = addon.Utility.CanonicalName(rawSender)
    if sender then Communication.NoteSeen(rawSender, sender) end
    if not sender or sender == me() then return end
    local accepted, rejectReason = Guard.Accept(channel, sender, Communication.roster)
    if not accepted then
        Communication.rejected = Communication.rejected + 1
        local reason = rejectReason
        if rejectReason == "not in guild" then
            local rosterSize = addon.Utility.Count(Communication.roster)
            if rosterSize == 0 then
                reason = "whisper before the guild roster loaded"
            else
                local lookalikes = Trace.RosterLookalikes(sender, Communication.roster)
                reason = lookalikes
                    and ("not in roster as " .. sender .. "; roster has " .. table.concat(lookalikes, ", ") .. " (name form mismatch)")
                    or ("not in guild roster (" .. rosterSize .. " members)")
            end
        end
        traceRejection(channel, sender, rawSender, reason)
        return
    end
    local ok, errorMessage = pcall(onChunk, text, sender, channel, rawSender)
    if not ok then
        addon.Log.Exception("communication.receive", "handling a received chunk failed", errorMessage,
            { sender = sender, channel = channel })
        Trace.Add({ dir = "in", ch = channel, peer = sender, raw = rawSender, st = "error", why = "chunk: " .. tostring(errorMessage) })
    end
end

------------------------------------------------------------------ identity check

-- My name as this client builds it ("Name-" .. GetNormalizedRealmName()) must be the form the roster and the other
-- clients use: the whisper gate, WANT/WANTO ("send me YOUR record") and SNAP/OFFERS ("record name == sender") all compare
-- those strings. If the roster does not contain my name, every whisper-based sync fails silently: warn once, loudly.
---@return boolean|nil inRoster nil while the roster is unknown
function Communication.CheckIdentity()
    local rosterSize = addon.Utility.Count(Communication.roster)
    if rosterSize == 0 then return nil end
    local myName = me()
    if Communication.roster[myName] then return true end
    local lookalikes = Trace.RosterLookalikes(myName, Communication.roster)
    local reason = lookalikes and ("roster lists me as " .. table.concat(lookalikes, ", ")) or ("not found among " .. rosterSize .. " roster names")
    Trace.System("warn", "identity: my name " .. tostring(myName) .. " is not in the guild roster", reason)
    if not Communication.identityWarned then
        Communication.identityWarned = true
        addon.Log.Error("communication.identity", "my character name is not in the guild roster; whisper sync will fail",
            { myName = myName, reason = reason })
        addon.Print(addon.Locale.Format(Text["Sync problem: your character name does not match the guild roster, so recipes and items cannot be exchanged. Please send the {cmd} export report to the addon author."],
            { cmd = (addon.SLASH_COMMANDS or {})[1] }))
    end
    return false
end

------------------------------------------------------------------ control

-- Broadcasts my HELLO (at most every 30 s unless forced or at login).
---@param isLogin? boolean
---@param force? boolean
function Communication.RequestHello(isLogin, force)
    if not Communication.active then return end
    local now = addon.Utility.Now()
    if not force and not isLogin and now - Communication.lastHello < 30 then return end
    Communication.lastHello = now
    Communication.sync:Hello(isLogin)
end

---@param order Order
function Communication.BroadcastOrder(order)
    if Communication.active then Communication.sync:BroadcastOrder(order) end
end

-- My own GUILD messages come back to me. The id in the chunk header starts with this session's salt, so an echo is
-- recognised for certain, and its raw sender is how the server spells MY name for addon senders: a different realm
-- spelling is learned as my realm (Utility.LearnMyRealm). Returns true for an echo (the caller ignores it).
---@param text string
---@param rawSender string
---@return boolean isEcho
function Communication.LearnFromEcho(text, rawSender)
    local salt = text:match("^%d+%.%d+|(%x%x%x%x)")
    if salt ~= ("%04x"):format(Communication.salt % 65536) then return false end
    local myCharacterName = (tostring(me())):match("^([^-]+)")
    local characterName, realmName = rawSender:match("^([^-]+)-(.+)$")
    if not characterName then return rawSender == myCharacterName end
    if characterName ~= myCharacterName then return false end
    if addon.Utility.LearnMyRealm(realmName) then
        Trace.System("info", "learned my realm spelling from my own echo", rawSender)
        addon.Log.Information("communication.identity", "learned another spelling of my realm from my own echo", { sender = rawSender })
        Communication.CanonicalizeStoredNames()
    end
    return true
end

-- Raw sender spellings as CHAT_MSG_ADDON delivered them, by canonical name (name check in the Debug tab; bounded).
---@type table<string, string>
Communication.seen = {}
---@param rawSender string
---@param canonicalSender string
function Communication.NoteSeen(rawSender, canonicalSender)
    if Communication.seen[canonicalSender] == nil and addon.Utility.Count(Communication.seen) >= 20 then return end
    Communication.seen[canonicalSender] = rawSender
end

-- After a new spelling of my realm was learned: every stored and cached name is canonicalized again.
---@return integer changedCount
function Communication.CanonicalizeStoredNames()
    if Communication.canonicalNameVersion == addon.Utility.realmAliasVersion then return 0 end
    Communication.canonicalNameVersion = addon.Utility.realmAliasVersion
    local changedCount = addon.Store.CanonicalizeStoredNames()
    local roster = {}
    for playerName in pairs(Communication.roster) do roster[addon.Utility.CanonicalName(playerName) or playerName] = true end
    Communication.roster = roster
    if Communication.sync then
        for _, pulls in ipairs({ Communication.sync.wanted, Communication.sync.wantedOffers }) do
            local canonicalPulls = {}
            for playerName, pull in pairs(pulls) do canonicalPulls[addon.Utility.CanonicalName(playerName) or playerName] = pull end
            addon.Utility.Refill(pulls, canonicalPulls)
        end
    end
    if changedCount > 0 then
        Trace.System("info", "names normalized", ("%d stored names rewritten, me=%s"):format(changedCount, tostring(me())))
        addon.Log.Information("communication.names", "stored player names were normalized", { count = changedCount, me = me() })
    end
    return changedCount
end

-- Takes the current guild roster, normalizes names, checks my identity and drops records of players who left.
function Communication.PruneRoster()
    local roster = addon.Api.GetGuildRoster()
    local rosterSize = addon.Utility.Count(roster)
    if rosterSize == 0 then return end
    local firstRoster = addon.Utility.Count(Communication.roster) == 0
    Communication.roster = roster
    Communication.CanonicalizeStoredNames()   -- the roster may have taught a new spelling of my realm (Api.GetGuildRoster)
    if firstRoster then
        Trace.System("info", "roster loaded", ("%d members, me (%s) %s"):format(rosterSize, tostring(me()),
            roster[me()] and "found" or "NOT found"))
    end
    Communication.CheckIdentity()
    addon.Store.Prune(roster, addon.Store.db.me)
end

-- Incomplete transfers waiting for chunks (Debug tab and export), oldest first.
---@return InFlightTransfer[]
function Communication.InFlight()
    local transfers, now = {}, addon.Utility.Now()
    for _, buffer in pairs(Communication.buffers) do
        transfers[#transfers + 1] = { sender = buffer.sender, receivedCount = buffer.receivedCount, partCount = buffer.partCount,
            ageSeconds = now - buffer.startedAt }
    end
    table.sort(transfers, function(left, right) return left.ageSeconds > right.ageSeconds end)
    return transfers
end

-- Idempotent; called at login and whenever guild membership may have changed. Never before PLAYER_LOGIN: until then the
-- stored name can still be the previously played character (SavedVariables are account-wide).
function Communication.Start()
    if Communication.active or not Communication.ready or not addon.Api.IsGuilded() then return end
    Communication.sync = addon.Sync.New({
        send = Communication.Send,
        now = addon.Utility.Now,
        random = math.random,
        store = addon.Store,
        orders = addon.orders,
        me = me,   -- a function: read at use time
        onChange = function(kind) addon.Events.Fire("DATA_CHANGED", kind) end,
    })
    Communication.active = true
    Communication.roster = addon.Api.GetGuildRoster()   -- may be empty until the first roster update; WHISPERs fail closed meanwhile
    addon.Log.Information("communication.start", "sync started",
        { me = me(), version = addon.VERSION, rosterSize = addon.Utility.Count(Communication.roster) })
    Trace.System("info", "sync started", ("me=%s v%s protocol %d.%d roster=%d"):format(tostring(me()), tostring(addon.VERSION),
        addon.PROTOCOL_MAJOR, addon.PROTOCOL_MINOR, addon.Utility.Count(Communication.roster)))
    addon.Api.RequestRoster()
end

-- drops receive buffers that waited longer than 60 s for their missing chunks
---@param now integer
local function dropStaleBuffers(now)
    for bufferKey, buffer in pairs(Communication.buffers) do
        if now - buffer.startedAt > 60 then
            Communication.buffers[bufferKey] = nil
            -- a multi-chunk message (SNAP, OFFERS, OPUSH) that never completed: chunks were lost on the way
            Trace.Add({ dir = "in", ch = buffer.channel, peer = buffer.sender, raw = buffer.raw, st = "dropped",
                why = ("incomplete: got %d of %d chunks in 60 s"):format(buffer.receivedCount, buffer.partCount) })
            addon.Log.Warning("communication.receive", "an incomplete message was dropped after 60 seconds",
                { sender = buffer.sender, receivedParts = buffer.receivedCount, partCount = buffer.partCount })
        end
    end
end

-- Registers the prefix and starts the send pump (every 0.25 s) and the minute ticker.
function Communication.Init()
    Communication.salt = math.random(0, 65535)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, result = pcall(function() return C_ChatInfo.RegisterAddonMessagePrefix(addon.PREFIX) end)
        if not ok or result == false or (type(result) == "number" and result ~= 0) then
            Trace.System("warn", "prefix registration failed", tostring(result))
            addon.Log.Error("communication.init", "the addon-message prefix could not be registered; messages will not arrive",
                { prefix = addon.PREFIX, result = result })
        end
    end
    local pumpFrame = CreateFrame("Frame")
    local secondsSincePump, secondsSinceTick = 0, 0
    pumpFrame:SetScript("OnUpdate", function(_, elapsedSeconds)
        secondsSincePump = secondsSincePump + elapsedSeconds
        if secondsSincePump < 0.25 then return end
        secondsSinceTick = secondsSinceTick + secondsSincePump
        local pumpedSeconds = secondsSincePump
        secondsSincePump = 0
        if Communication.active then
            pump(pumpedSeconds)
            if secondsSinceTick >= 1 then
                Communication.sync:Tick(addon.Utility.Now())
            end
        end
        if secondsSinceTick >= 1 then secondsSinceTick = 0 end
    end)
    local minutesRunning = 0
    C_Timer.NewTicker(60, function()
        minutesRunning = minutesRunning + 1
        if not Communication.active then Communication.Start() end
        if Communication.active then
            local now = addon.Utility.Now()
            dropStaleBuffers(now)
            if minutesRunning % 5 == 0 then addon.Api.RequestRoster() end
            if minutesRunning % 15 == 0 then Communication.RequestHello(false, true) end   -- anti-entropy: changes missed while away are found
            addon.orders:Prune(now)
        end
    end)
end

------------------------------------------------------------------ slash commands

addon.SlashCommands.comm = function()
    local statistics = Communication.sync and Communication.sync.statistics or { sent = 0, received = 0, dropped = 0 }
    addon.Print(("comm: active=%s protocol=%d.%d sent=%d received=%d dropped=%d rejected=%d queue=%d chunks out/in=%d/%d send failures=%d roster=%d incompatible peers=%d"):format(
        tostring(Communication.active), addon.PROTOCOL_MAJOR, addon.PROTOCOL_MINOR, statistics.sent, statistics.received,
        statistics.dropped, Communication.rejected, #Communication.queue, Communication.chunksSent, Communication.chunksReceived,
        Communication.sendFailures, addon.Utility.Count(Communication.roster), Communication.hints.count))
end

addon.SlashCommands.hello = function()
    if not Communication.active then addon.Print("not active (not in a guild?)") return end
    Communication.RequestHello(false, true)
    addon.Print("hello sent")
end

-- /ts debug [count]: the last log lines (default 15); /ts trace [count] [problems]: the last network trace entries
addon.SlashCommands.debug = function(arguments)
    local lineCount = tonumber((arguments or ""):match("%d+")) or 15
    local logLines = addon.db and addon.db.debug or {}
    for index = math.max(1, #logLines - lineCount + 1), #logLines do print(logLines[index]) end
end

addon.SlashCommands.trace = function(arguments)
    local entryCount = tonumber((arguments or ""):match("%d+")) or 20
    local traceEntries = Trace.List((arguments or ""):match("problems") and "problems" or nil)
    for index = math.min(entryCount, #traceEntries), 1, -1 do print(addon.Utility.Escape(Trace.Format(traceEntries[index]))) end
end

addon.SlashCommands.chars = function()
    for _, characterRecord in ipairs(addon.Store.ListCharacters()) do
        print(("%s lvl %s rev %s recipes %d"):format(characterRecord.name, tostring(characterRecord.level),
            tostring(characterRecord.rev), addon.Store.RecipeCount(characterRecord)))
    end
end
