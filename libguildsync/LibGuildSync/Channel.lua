-- LibGuildSync: transport for one addon prefix (Channel.New). Chunks encoded messages to <= 255 bytes, paces sends,
-- reassembles received chunks, gates inbound traffic to the guild, learns my realm spelling from my own echoes, coalesces
-- HELLOs and wires a Sync engine to the guild. Not in a guild -> inactive (no sends, no errors).
-- SHARED by every channel (every addon that embeds the library): ONE send token bucket and ONE driver frame, because the
-- server throttles addon messages per player, not per addon.
-- Every message in and out is recorded in the addon's trace: one entry per message, whose status is updated as it moves
-- (out: queued -> sent | failed; in: the decision Sync took, or why it never got there). Failures are also logged.
-- The channel's functions are called with a dot (channel.Send(message, "GUILD")), and its state is plain fields
-- (channel.queue, channel.roster, channel.sync, ...), so an addon can expose the channel as its own module.
local lib = LibStub("LibGuildSync-1.0")
local Channel = lib:Module("Channel", 2)
if not Channel then return end

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

---@class GuildAccess
---@field IsGuilded fun(): boolean
---@field GetGuildRoster fun(): table<string, boolean>
---@field RequestRoster fun()

---@class ChannelOptions
---@field prefix string|fun(): string addon-message prefix (at most 16 bytes)
---@field codec table the addon's Codec instance (protocol version)
---@field log table the addon's Log instance
---@field trace table the addon's Trace instance
---@field me fun(): string|nil my canonical name in this addon
---@field version? string addon version, for the log
---@field priorityTypes? table<string, boolean> small single-chunk messages that jump the queue
---@field guild? GuildAccess|fun(): GuildAccess default lib.Guild
---@field newSync fun(channel: table): table builds the Sync engine when the channel starts
---@field onIncompatible? fun(kind: HintKind, sender: string) once per kind and session: tell the player
---@field onIdentityProblem? fun(myName: string|nil, reason: string) once per session: my name is not in the roster
---@field canonicalizeStored? fun(): integer re-keys the addon's stored names; returns how many changed
---@field onRoster? fun(roster: table<string, boolean>) after a roster update (drop records of members who left)
---@field onMinute? fun(now: integer, minutesRunning: integer) once a minute while active

Channel.BUCKET_CAPACITY, Channel.REFILL_PER_SECOND = 5, 0.9   -- burst / refill per second (server allows 10 burst, 1/s)
Channel.MAXIMUM_QUEUED_CHUNKS = 600
Channel.THROTTLE_RESULT_CODE = 3   -- Enum.SendAddonMessageResult.AddonMessageThrottle
Channel.HELLO_INTERVAL_SECONDS = 30
Channel.STALE_BUFFER_SECONDS = 60

---@class ChannelShared
---@field tokens number send tokens available to every channel together
---@field channels table[] every initialized channel, in Init order
---@field minutesRunning integer
Channel.shared = Channel.shared or { tokens = Channel.BUCKET_CAPACITY, channels = {}, minutesRunning = 0 }

---@param value any
---@return any
local function resolve(value)
    if type(value) == "function" then return value() end
    return value
end

---@param channel table
---@return GuildAccess
local function guildOf(channel) return resolve(channel.options.guild) or lib.Guild end

---@param channel table
---@return string
local function prefixOf(channel) return resolve(channel.options.prefix) end

------------------------------------------------------------------ send result codes
-- Modern clients return an Enum.SendAddonMessageResult (0 = Success), older ones a boolean, very old ones nothing.
---@type table<integer, string>
local RESULT_NAMES = { [0] = "Success", "InvalidPrefix", "InvalidMessage", "AddonMessageThrottle", "InvalidChatType",
    "NotInGroup", "TargetRequired", "InvalidChannel", "ChannelThrottle", "GeneralError", "NotInGuild",
    "AddOnMessageLockdown", "TargetOffline" }

---@param resultCode any
---@return string
function Channel.ResultName(resultCode)
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
function Channel.InterpretResult(ok, result)
    if not ok then return false, "lua error: " .. tostring(result) end
    if result == nil or result == true or result == 0 then return true end
    if result == false then return false, "SendAddonMessage returned false" end
    if type(result) == "number" then return false, Channel.ResultName(result) end
    return true
end

------------------------------------------------------------------ outbound

-- Encodes and queues a message (the Sync environment's send). Failures are traced and logged, never thrown.
---@param channel table
---@param message table
---@param chatChannel string
---@param target? string
function Channel.Send(channel, message, chatChannel, target)
    if not channel.active then return end
    local codec, log, trace = channel.options.codec, channel.options.log, channel.options.trace
    local traceEntry = trace.Add({ dir = "out", ch = chatChannel, peer = target, mt = message.t, st = "queued", info = trace.Summarize(message) })
    local ok, encoded = pcall(codec.Encode, message)
    if not ok then
        log.Exception("communication.send", "a message could not be encoded", encoded,
            { messageType = message.t, channel = chatChannel, target = target })
        traceEntry.st, traceEntry.why = "failed", "encode: " .. tostring(encoded)
        return
    end
    channel.messageCounter = channel.messageCounter + 1
    local transferID = string.format("%04x%x", channel.salt % 65536, channel.messageCounter % 65536)
    local partCount = math.ceil(#encoded / codec.CHUNK_BYTES)
    traceEntry.parts, traceEntry.bytes = partCount, #encoded
    if partCount > codec.MAXIMUM_PARTS then
        log.Error("communication.send", "a message is too big to send and was dropped",
            { messageType = message.t, bytes = #encoded, parts = partCount, maximumParts = codec.MAXIMUM_PARTS })
        traceEntry.st, traceEntry.why = "dropped", ("too big: %d chunks > %d"):format(partCount, codec.MAXIMUM_PARTS)
        return
    end
    if #channel.queue + partCount > Channel.MAXIMUM_QUEUED_CHUNKS then
        log.Error("communication.send", "the send queue is full; a message was dropped",
            { messageType = message.t, queuedChunks = #channel.queue, parts = partCount })
        traceEntry.st, traceEntry.why = "dropped", ("send queue full (%d chunks waiting)"):format(#channel.queue)
        return
    end
    traceEntry.sentParts = 0
    local isPriority = channel.options.priorityTypes and channel.options.priorityTypes[message.t]
    for partIndex = 1, partCount do
        local payload = encoded:sub((partIndex - 1) * codec.CHUNK_BYTES + 1, partIndex * codec.CHUNK_BYTES)
        local queuedChunk = { channel = chatChannel, target = target, text = codec.Header(transferID, partIndex, partCount) .. payload,
            traceEntry = traceEntry }
        if isPriority then
            table.insert(channel.queue, 1, queuedChunk)
        else
            channel.queue[#channel.queue + 1] = queuedChunk
        end
    end
end

-- Refills the shared token bucket for `elapsedSeconds`.
---@param elapsedSeconds number
function Channel.Refill(elapsedSeconds)
    local shared = Channel.shared
    shared.tokens = math.min(Channel.BUCKET_CAPACITY, shared.tokens + elapsedSeconds * Channel.REFILL_PER_SECOND)
end

-- Sends up to `maximumChunks` queued chunks of one channel while shared tokens last. Returns false when throttled.
---@param channel table
---@param maximumChunks? integer
---@return boolean notThrottled
function Channel.SendQueued(channel, maximumChunks)
    local shared, log = Channel.shared, channel.options.log
    local sentCount = 0
    while shared.tokens >= 1 and #channel.queue > 0 and (not maximumChunks or sentCount < maximumChunks) do
        local queuedChunk = table.remove(channel.queue, 1)
        -- same realm: name only (Utility.WhisperTarget)
        local resolvedTarget = queuedChunk.channel == "WHISPER" and lib.Utility.WhisperTarget(queuedChunk.target) or queuedChunk.target
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefixOf(channel), queuedChunk.text, queuedChunk.channel, resolvedTarget)
        if ok and type(result) == "number" and result == Channel.THROTTLE_RESULT_CODE then   -- throttled: retry later
            table.insert(channel.queue, 1, queuedChunk)
            shared.tokens = 0
            return false
        end
        local delivered, reason = Channel.InterpretResult(ok, result)
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
            channel.sendFailures = channel.sendFailures + 1
            log.Error("communication.send", "the client refused an addon message",
                { reason = reason, channel = queuedChunk.channel, target = resolvedTarget, messageType = traceEntry and traceEntry.mt })
        end
        channel.chunksSent = channel.chunksSent + 1
        shared.tokens = shared.tokens - 1
        sentCount = sentCount + 1
    end
    return true
end

-- Sends the queued chunks of every active channel while tokens last, one chunk per channel in turn (fair share).
function Channel.SendAll()
    local active = {}
    for _, channel in ipairs(Channel.shared.channels) do
        if channel.active and #channel.queue > 0 then active[#active + 1] = channel end
    end
    while Channel.shared.tokens >= 1 and #active > 0 do
        local stillQueued = {}
        for _, channel in ipairs(active) do
            if Channel.shared.tokens < 1 then break end
            if not Channel.SendQueued(channel, 1) then return end
            if #channel.queue > 0 then stillQueued[#stillQueued + 1] = channel end
        end
        active = stillQueued
    end
end

------------------------------------------------------------------ inbound

---@param channel table
---@param chatChannel string
---@param sender string|nil
---@param raw string
---@param reason string
local function traceRejection(channel, chatChannel, sender, raw, reason)
    -- rejections can arrive once per chunk; one trace entry per (sender, reason) every 30 s is enough to see them
    local rejectionKey = tostring(sender) .. "|" .. reason
    local now = lib.Utility.Now()
    if channel.lastRejectionTraced[rejectionKey] and now - channel.lastRejectionTraced[rejectionKey] < 30 then return end
    channel.lastRejectionTraced[rejectionKey] = now
    channel.options.trace.Add({ dir = "in", ch = chatChannel, peer = sender, raw = raw, st = "rejected", why = reason })
end

-- One notice per kind per session; the sender is only recorded (bounded), never printed.
---@param channel table
---@param kind HintKind
---@param sender string
local function noteIncompatiblePeer(channel, kind, sender)
    channel.rejected = channel.rejected + (kind == "newer-minor" and 0 or 1)
    if not lib.Guard.Note(channel.hints, kind, sender) then return end
    channel.options.log.Warning("communication.version", "a guild member runs an incompatible or newer version", { kind = kind, sender = sender })
    if channel.options.onIncompatible then channel.options.onIncompatible(kind, sender) end
end

-- One accepted chunk: buffered until its message is complete, then decoded and handed to Sync.
---@param channel table
---@param text string
---@param sender string canonical
---@param chatChannel string
---@param raw string the sender as the client reported it
function Channel.OnChunk(channel, text, sender, chatChannel, raw)
    local codec, trace, log = channel.options.codec, channel.options.trace, channel.options.log
    local protocol = codec.protocol
    local header, reason = codec.ParseHeader(text)
    if not header then
        if reason == "legacy" then noteIncompatiblePeer(channel, "older", sender) end   -- builds without a version in the header
        traceRejection(channel, chatChannel, sender, raw, reason == "legacy" and "legacy 0.1/0.2 header" or "malformed chunk header")
        return
    end
    if header.major ~= protocol.major then
        noteIncompatiblePeer(channel, codec.Compatibility(header.major, header.minor), sender)   -- before any buffer is allocated
        traceRejection(channel, chatChannel, sender, raw, ("protocol %d.%d, mine %d.%d"):format(header.major, header.minor,
            protocol.major, protocol.minor))
        return
    end
    if codec.Compatibility(header.major, header.minor) == "newer-minor" then noteIncompatiblePeer(channel, "newer-minor", sender) end
    channel.chunksReceived = channel.chunksReceived + 1
    local bufferKey = sender .. ":" .. header.transferID
    local buffer = channel.buffers[bufferKey]
    if not buffer or buffer.partCount ~= header.partCount then
        buffer = { partCount = header.partCount, parts = {}, receivedCount = 0, startedAt = lib.Utility.Now(), sender = sender,
            channel = chatChannel, raw = raw }
        channel.buffers[bufferKey] = buffer
    end
    if not buffer.parts[header.partIndex] then
        buffer.parts[header.partIndex] = header.payload
        buffer.receivedCount = buffer.receivedCount + 1
    end
    if buffer.receivedCount == header.partCount then
        channel.buffers[bufferKey] = nil
        local encoded = table.concat(buffer.parts)
        local traceEntry = trace.Add({ dir = "in", ch = chatChannel, peer = sender, raw = raw, st = "error", parts = header.partCount,
            bytes = #encoded })
        local message, decodeReason = codec.Decode(encoded)
        if message then
            traceEntry.mt, traceEntry.info = message.t, trace.Summarize(message)
            local status, handlerReason = channel.sync:OnMessage(message, sender)
            traceEntry.st, traceEntry.why = status or "ok", handlerReason
        else
            channel.sync.statistics.dropped = channel.sync.statistics.dropped + 1
            log.Warning("communication.receive", "a received message could not be decoded",
                { sender = sender, reason = decodeReason, bytes = #encoded })
            traceEntry.why = "decode: " .. tostring(decodeReason)
        end
    end
end

-- Entry point for CHAT_MSG_ADDON. The gate runs FIRST: nothing from outside the guild is parsed, buffered or answered.
---@param channel table
---@param prefix string
---@param text string
---@param chatChannel string
---@param rawSender string
function Channel.OnAddonMessage(channel, prefix, text, chatChannel, rawSender)
    if prefix ~= prefixOf(channel) or not channel.active or type(text) ~= "string" or type(rawSender) ~= "string" then return end
    if chatChannel == "GUILD" and Channel.LearnFromEcho(channel, text, rawSender) then   -- only the server-filtered guild channel teaches
        channel.lastEcho = rawSender
        return
    end
    local Utility, trace = lib.Utility, channel.options.trace
    local sender = Utility.CanonicalName(rawSender)
    if sender then Channel.NoteSeen(channel, rawSender, sender) end
    if not sender or sender == channel.options.me() then return end
    local accepted, rejectReason = lib.Guard.Accept(chatChannel, sender, channel.roster)
    if not accepted then
        channel.rejected = channel.rejected + 1
        local reason = rejectReason
        if rejectReason == "not in guild" then
            local rosterSize = Utility.Count(channel.roster)
            if rosterSize == 0 then
                reason = "whisper before the guild roster loaded"
            else
                local lookalikes = trace.RosterLookalikes(sender, channel.roster)
                reason = lookalikes
                    and ("not in roster as " .. sender .. "; roster has " .. table.concat(lookalikes, ", ") .. " (name form mismatch)")
                    or ("not in guild roster (" .. rosterSize .. " members)")
            end
        end
        traceRejection(channel, chatChannel, sender, rawSender, reason)
        return
    end
    local ok, errorMessage = pcall(Channel.OnChunk, channel, text, sender, chatChannel, rawSender)
    if not ok then
        channel.options.log.Exception("communication.receive", "handling a received chunk failed", errorMessage,
            { sender = sender, channel = chatChannel })
        trace.Add({ dir = "in", ch = chatChannel, peer = sender, raw = rawSender, st = "error", why = "chunk: " .. tostring(errorMessage) })
    end
end

------------------------------------------------------------------ identity

-- My name as this client builds it must be the form the roster and the other clients use: the whisper gate, the record
-- requests ("send me YOUR record") and the record check ("record name == sender") all compare those strings. If the roster
-- does not contain my name, every whisper-based sync fails silently: warn once, loudly.
---@param channel table
---@return boolean|nil inRoster nil while the roster is unknown
function Channel.CheckIdentity(channel)
    local rosterSize = lib.Utility.Count(channel.roster)
    if rosterSize == 0 then return nil end
    local myName = channel.options.me()
    if channel.roster[myName] then return true end
    local trace = channel.options.trace
    local lookalikes = trace.RosterLookalikes(myName, channel.roster)
    local reason = lookalikes and ("roster lists me as " .. table.concat(lookalikes, ", ")) or ("not found among " .. rosterSize .. " roster names")
    trace.System("warn", "identity: my name " .. tostring(myName) .. " is not in the guild roster", reason)
    if not channel.identityWarned then
        channel.identityWarned = true
        channel.options.log.Error("communication.identity", "my character name is not in the guild roster; whisper sync will fail",
            { myName = myName, reason = reason })
        if channel.options.onIdentityProblem then channel.options.onIdentityProblem(myName, reason) end
    end
    return false
end

-- My own GUILD messages come back to me. The id in the chunk header starts with this session's salt, so an echo is
-- recognised for certain, and its raw sender is how the server spells MY name for addon senders: a different realm
-- spelling is learned as my realm (Utility.LearnMyRealm). Returns true for an echo (the caller ignores it).
---@param channel table
---@param text string
---@param rawSender string
---@return boolean isEcho
function Channel.LearnFromEcho(channel, text, rawSender)
    local salt = text:match("^%d+%.%d+|(%x%x%x%x)")
    if salt ~= ("%04x"):format(channel.salt % 65536) then return false end
    local myCharacterName = (tostring(channel.options.me())):match("^([^-]+)")
    local characterName, realmName = rawSender:match("^([^-]+)-(.+)$")
    if not characterName then return rawSender == myCharacterName end
    if characterName ~= myCharacterName then return false end
    if lib.Utility.LearnMyRealm(realmName) then
        channel.options.trace.System("info", "learned my realm spelling from my own echo", rawSender)
        channel.options.log.Information("communication.identity", "learned another spelling of my realm from my own echo", { sender = rawSender })
        -- the realm state is shared: every addon's stored names are canonicalized again
        Channel.CanonicalizeStoredNames(channel)
        for _, other in ipairs(Channel.shared.channels) do
            if other ~= channel then Channel.CanonicalizeStoredNames(other) end
        end
    end
    return true
end

-- Raw sender spellings as CHAT_MSG_ADDON delivered them, by canonical name (name check in a debug view; bounded).
---@param channel table
---@param rawSender string
---@param canonicalSender string
function Channel.NoteSeen(channel, rawSender, canonicalSender)
    if channel.seen[canonicalSender] == nil and lib.Utility.Count(channel.seen) >= 20 then return end
    channel.seen[canonicalSender] = rawSender
end

-- After a new spelling of my realm was learned: every stored and cached name is canonicalized again.
---@param channel table
---@return integer changedCount
function Channel.CanonicalizeStoredNames(channel)
    local Utility = lib.Utility
    if channel.canonicalNameVersion == Utility.realmAliasVersion then return 0 end
    channel.canonicalNameVersion = Utility.realmAliasVersion
    local changedCount = channel.options.canonicalizeStored and channel.options.canonicalizeStored() or 0
    local roster = {}
    for playerName in pairs(channel.roster) do roster[Utility.CanonicalName(playerName) or playerName] = true end
    channel.roster = roster
    if channel.sync and channel.sync.CanonicalizePulls then channel.sync:CanonicalizePulls() end
    if changedCount > 0 then
        local me = channel.options.me()
        channel.options.trace.System("info", "names normalized", ("%d stored names rewritten, me=%s"):format(changedCount, tostring(me)))
        channel.options.log.Information("communication.names", "stored player names were normalized", { count = changedCount, me = me })
    end
    return changedCount
end

-- Takes the current guild roster, normalizes names, checks my identity and lets the addon drop records of players who left.
---@param channel table
function Channel.PruneRoster(channel)
    local roster = guildOf(channel).GetGuildRoster()
    local rosterSize = lib.Utility.Count(roster)
    if rosterSize == 0 then return end
    local firstRoster = lib.Utility.Count(channel.roster) == 0
    channel.roster = roster
    Channel.CanonicalizeStoredNames(channel)   -- the roster may have taught a new spelling of my realm
    if firstRoster then
        local me = channel.options.me()
        channel.options.trace.System("info", "roster loaded", ("%d members, me (%s) %s"):format(rosterSize, tostring(me),
            roster[me] and "found" or "NOT found"))
    end
    Channel.CheckIdentity(channel)
    if channel.options.onRoster then channel.options.onRoster(channel.roster) end
end

-- Incomplete transfers waiting for chunks (debug view and export), oldest first.
---@param channel table
---@return InFlightTransfer[]
function Channel.InFlight(channel)
    local transfers, now = {}, lib.Utility.Now()
    for _, buffer in pairs(channel.buffers) do
        transfers[#transfers + 1] = { sender = buffer.sender, receivedCount = buffer.receivedCount, partCount = buffer.partCount,
            ageSeconds = now - buffer.startedAt }
    end
    table.sort(transfers, function(left, right) return left.ageSeconds > right.ageSeconds end)
    return transfers
end

---@param channel table
---@param now integer
function Channel.DropStaleBuffers(channel, now)
    for bufferKey, buffer in pairs(channel.buffers) do
        if now - buffer.startedAt > Channel.STALE_BUFFER_SECONDS then
            channel.buffers[bufferKey] = nil
            -- a multi-chunk message that never completed: chunks were lost on the way
            channel.options.trace.Add({ dir = "in", ch = buffer.channel, peer = buffer.sender, raw = buffer.raw, st = "dropped",
                why = ("incomplete: got %d of %d chunks in %d s"):format(buffer.receivedCount, buffer.partCount, Channel.STALE_BUFFER_SECONDS) })
            channel.options.log.Warning("communication.receive", "an incomplete message was dropped after 60 seconds",
                { sender = buffer.sender, receivedParts = buffer.receivedCount, partCount = buffer.partCount })
        end
    end
end

------------------------------------------------------------------ HELLO

-- Broadcasts my HELLO (at most every HELLO_INTERVAL_SECONDS unless forced or at login).
---@param channel table
---@param isLogin? boolean
---@param force? boolean
function Channel.RequestHello(channel, isLogin, force)
    if not channel.active then return end
    local now = lib.Utility.Now()
    if not force and not isLogin and now - channel.lastHello < Channel.HELLO_INTERVAL_SECONDS then return end
    channel.lastHello = now
    channel.helloDueAt = nil   -- this HELLO carries every change so far
    channel.sync:Hello(isLogin)
end

-- Announces a change that peers may pull lazily (a game play): a HELLO now if the last one is old enough, else one HELLO
-- when the interval is over (SendDueHello, from the 1 s tick). Ten plays in a minute = 2-3 HELLOs.
---@param channel table
function Channel.RequestHelloSoon(channel)
    if not channel.active then return end
    local now = lib.Utility.Now()
    if now - channel.lastHello >= Channel.HELLO_INTERVAL_SECONDS then
        Channel.RequestHello(channel, false, true)
    elseif not channel.helloDueAt then
        channel.helloDueAt = channel.lastHello + Channel.HELLO_INTERVAL_SECONDS
    end
end

-- Sends the coalesced HELLO once it is due. Called every second.
---@param channel table
---@param now integer
function Channel.SendDueHello(channel, now)
    if channel.active and channel.helloDueAt and now >= channel.helloDueAt then
        Channel.RequestHello(channel, false, true)
    end
end

------------------------------------------------------------------ control

-- Idempotent; called at login and whenever guild membership may have changed. Never before the addon set `ready`
-- (until PLAYER_LOGIN the stored name can still be the previously played character).
---@param channel table
function Channel.Start(channel)
    local guild = guildOf(channel)
    if channel.active or not channel.ready or not guild.IsGuilded() then return end
    channel.sync = channel.options.newSync(channel)
    channel.active = true
    channel.roster = guild.GetGuildRoster()   -- may be empty until the first roster update; WHISPERs fail closed meanwhile
    local me, protocol, rosterSize = channel.options.me(), channel.options.codec.protocol, lib.Utility.Count(channel.roster)
    channel.options.log.Information("communication.start", "sync started",
        { me = me, version = channel.options.version, rosterSize = rosterSize })
    channel.options.trace.System("info", "sync started", ("me=%s v%s protocol %d.%d roster=%d"):format(tostring(me),
        tostring(channel.options.version), protocol.major, protocol.minor, rosterSize))
    guild.RequestRoster()
end

-- Every second while active: due sends and pull retries, then a coalesced HELLO.
---@param channel table
---@param now integer
function Channel.Tick(channel, now)
    if not channel.active then return end
    channel.sync:Tick(now)
    Channel.SendDueHello(channel, now)
end

-- Once a minute: start late joiners, drop stale buffers, refresh the roster (5 min), anti-entropy HELLO (15 min).
---@param channel table
---@param minutesRunning integer
function Channel.Minute(channel, minutesRunning)
    if not channel.active then Channel.Start(channel) end
    if not channel.active then return end
    local now = lib.Utility.Now()
    Channel.DropStaleBuffers(channel, now)
    if minutesRunning % 5 == 0 then guildOf(channel).RequestRoster() end
    if minutesRunning % 15 == 0 then Channel.RequestHello(channel, false, true) end   -- changes missed while away are found
    if channel.options.onMinute then channel.options.onMinute(now, minutesRunning) end
end

-- The shared driver: pumps every channel every 0.25 s, ticks them every second.
---@param elapsedSeconds number
function Channel.Drive(elapsedSeconds)
    local shared = Channel.shared
    shared.secondsSincePump = (shared.secondsSincePump or 0) + elapsedSeconds
    if shared.secondsSincePump < 0.25 then return end
    shared.secondsSinceTick = (shared.secondsSinceTick or 0) + shared.secondsSincePump
    Channel.Refill(shared.secondsSincePump)
    shared.secondsSincePump = 0
    Channel.SendAll()
    if shared.secondsSinceTick >= 1 then
        shared.secondsSinceTick = 0
        local now = lib.Utility.Now()
        for _, channel in ipairs(shared.channels) do
            local ok, errorMessage = pcall(Channel.Tick, channel, now)
            if not ok then channel.options.log.Exception("communication.tick", "the sync tick failed", errorMessage) end
        end
    end
end

-- The shared minute ticker.
function Channel.EveryMinute()
    local shared = Channel.shared
    shared.minutesRunning = shared.minutesRunning + 1
    for _, channel in ipairs(shared.channels) do
        local ok, errorMessage = pcall(Channel.Minute, channel, shared.minutesRunning)
        if not ok then channel.options.log.Exception("communication.minute", "the minute ticker failed", errorMessage) end
    end
end

-- Registers the prefix and joins the shared driver. Call once, at ADDON_LOADED.
---@param channel table
function Channel.Initialize(channel)
    channel.salt = math.random(0, 65535)
    local prefix = prefixOf(channel)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, result = pcall(function() return C_ChatInfo.RegisterAddonMessagePrefix(prefix) end)
        if not ok or result == false or (type(result) == "number" and result ~= 0) then
            channel.options.trace.System("warn", "prefix registration failed", tostring(result))
            channel.options.log.Error("communication.init", "the addon-message prefix could not be registered; messages will not arrive",
                { prefix = prefix, result = result })
        end
    end
    local shared = Channel.shared
    local known = false
    for _, other in ipairs(shared.channels) do if other == channel then known = true end end
    if not known then shared.channels[#shared.channels + 1] = channel end
    if not shared.driverFrame and CreateFrame then
        shared.driverFrame = CreateFrame("Frame")
        shared.driverFrame:SetScript("OnUpdate", function(_, elapsedSeconds) Channel.Drive(elapsedSeconds) end)
    end
    if not shared.ticker and C_Timer and C_Timer.NewTicker then
        shared.ticker = C_Timer.NewTicker(60, function() Channel.EveryMinute() end)
    end
end

-- A channel for one addon prefix. Every function is bound to the channel and called with a dot.
---@param options ChannelOptions
---@return table channel
function Channel.New(options)
    local channel = { options = options, active = false, ready = false, queue = {}, buffers = {}, lastHello = 0, helloDueAt = nil,
        messageCounter = 0, salt = 0, roster = {}, hints = lib.Guard.NewHints(), rejected = 0, chunksSent = 0, chunksReceived = 0,
        sendFailures = 0, identityWarned = false, canonicalNameVersion = nil, lastEcho = nil, sync = nil, seen = {},
        lastRejectionTraced = {}, InterpretResult = Channel.InterpretResult }
    function channel.Me() return options.me() end
    function channel.Send(message, chatChannel, target) return Channel.Send(channel, message, chatChannel, target) end
    -- offline tests drive one channel's pump directly
    function channel._pump(elapsedSeconds) Channel.Refill(elapsedSeconds); Channel.SendQueued(channel) end
    function channel.OnAddonMessage(prefix, text, chatChannel, rawSender)
        return Channel.OnAddonMessage(channel, prefix, text, chatChannel, rawSender)
    end
    function channel.CheckIdentity() return Channel.CheckIdentity(channel) end
    function channel.RequestHello(isLogin, force) return Channel.RequestHello(channel, isLogin, force) end
    function channel.RequestHelloSoon() return Channel.RequestHelloSoon(channel) end
    function channel.SendDueHello(now) return Channel.SendDueHello(channel, now) end
    function channel.LearnFromEcho(text, rawSender) return Channel.LearnFromEcho(channel, text, rawSender) end
    function channel.NoteSeen(rawSender, canonicalSender) return Channel.NoteSeen(channel, rawSender, canonicalSender) end
    function channel.CanonicalizeStoredNames() return Channel.CanonicalizeStoredNames(channel) end
    function channel.PruneRoster() return Channel.PruneRoster(channel) end
    function channel.InFlight() return Channel.InFlight(channel) end
    function channel.Start() return Channel.Start(channel) end
    function channel.Init() return Channel.Initialize(channel) end
    return channel
end
