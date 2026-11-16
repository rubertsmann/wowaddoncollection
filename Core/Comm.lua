local ADDON, ns = ...

-- Transport: chunks encoded messages to <= 255 bytes, paces sends (token bucket), reassembles received chunks,
-- and wires Sync to the guild. Not in a guild -> inactive (no sends, no errors).
-- Every message in and out is recorded in the network trace (Core/Trace.lua, feature 008): one entry per message, whose
-- status is updated as it moves (out: queued -> sent | failed; in: the decision Sync took, or why it never got there).
local Comm = {}
ns.Comm = Comm

local L = ns.L
local Codec, Guard, Trace = ns.Codec, ns.Guard, ns.Trace
local CHUNK, MAX_PARTS = Codec.CHUNK, Codec.MAX_PARTS   -- one definition (Codec): Decode accepts what we can send
local BUCKET_MAX, REFILL = 5, 0.9   -- messages burst / refill per second (server allows 10 burst, 1/s)

Comm.active = false
Comm.ready = false           -- set at PLAYER_LOGIN: before it, the current character's name is not known yet
Comm.queue = {}
Comm.buffers = {}
Comm.tokens = BUCKET_MAX
Comm.lastHello = 0
Comm.msgCounter = 0
Comm.salt = 0                -- random per session (Comm.Init): ids never repeat across /reload while stale buffers exist
Comm.roster = {}             -- set of "Name-Realm" as of the last roster update; WHISPERs from anyone else are dropped
Comm.hints = Guard.NewHints()
Comm.rejected = 0            -- chunks dropped by the gate or for a foreign protocol (shown by /ts comm)
Comm.chunksSent, Comm.chunksReceived = 0, 0
Comm.sendFailures = 0
Comm.identityWarned = false

local function me() return ns.Store.db and ns.Store.db.me or (ns.Api.GetPlayerInfo().name) end
Comm.Me = me

------------------------------------------------------------------ send result codes
-- Modern clients return an Enum.SendAddonMessageResult (0 = Success), older ones a boolean, very old ones nothing.
local RESULT_FALLBACK = { [0] = "Success", "InvalidPrefix", "InvalidMessage", "AddonMessageThrottle", "InvalidChatType",
    "NotInGroup", "TargetRequired", "InvalidChannel", "ChannelThrottle", "GeneralError", "NotInGuild",
    "AddOnMessageLockdown", "TargetOffline" }

local function resultName(code)
    local E = Enum and Enum.SendAddonMessageResult
    if type(E) == "table" then
        for k, v in pairs(E) do if v == code then return k end end
    end
    return RESULT_FALLBACK[code] or ("code " .. tostring(code))
end

-- true | false, reason
local function interpret(ok, res)
    if not ok then return false, "lua error: " .. tostring(res) end
    if res == nil or res == true or res == 0 then return true end
    if res == false then return false, "SendAddonMessage returned false" end
    if type(res) == "number" then return false, resultName(res) end
    return true
end
Comm.InterpretResult = interpret

------------------------------------------------------------------ outbound

function Comm.Send(msg, dist, target)
    if not Comm.active then return end
    local entry = Trace.Add({ dir = "out", ch = dist, peer = target, mt = msg.t, st = "queued", info = Trace.Summarize(msg) })
    local ok, enc = pcall(ns.Codec.Encode, msg)
    if not ok then
        ns.Debug.Log("comm.encode", enc)
        entry.st, entry.why = "failed", "encode: " .. tostring(enc)
        return
    end
    Comm.msgCounter = Comm.msgCounter + 1
    local id = string.format("%04x%x", Comm.salt % 65536, Comm.msgCounter % 65536)
    local total = math.ceil(#enc / CHUNK)
    entry.parts, entry.bytes = total, #enc
    if total > MAX_PARTS then
        ns.Debug.Log("comm.toobig", msg.t, #enc)
        entry.st, entry.why = "dropped", ("too big: %d chunks > %d"):format(total, MAX_PARTS)
        return
    end
    if #Comm.queue + total > 600 then
        ns.Debug.Log("comm.queuefull", msg.t)
        entry.st, entry.why = "dropped", ("send queue full (%d chunks waiting)"):format(#Comm.queue)
        return
    end
    entry.sentParts = 0
    for i = 1, total do
        local part = enc:sub((i - 1) * CHUNK + 1, i * CHUNK)
        local item = { dist = dist, target = target, text = Codec.Header(id, i, total) .. part, entry = entry }
        if msg.t == "ORDER" or msg.t == "WANT" or msg.t == "WANTO" or msg.t == "HELLO" then
            table.insert(Comm.queue, 1, item)  -- small control messages jump the queue (single chunk)
        else
            Comm.queue[#Comm.queue + 1] = item
        end
    end
end

local function pump(dt)
    Comm.tokens = math.min(BUCKET_MAX, Comm.tokens + dt * REFILL)
    while Comm.tokens >= 1 and #Comm.queue > 0 do
        local item = table.remove(Comm.queue, 1)
        local target = item.dist == "WHISPER" and ns.Util.WhisperTarget(item.target) or item.target   -- same realm: name only
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, item.text, item.dist, target)
        if ok and type(res) == "number" and res == 3 then   -- AddonMessageThrottle: retry later
            table.insert(Comm.queue, 1, item)
            Comm.tokens = 0
            break
        end
        local good, why = interpret(ok, res)
        local e = item.entry
        if e then
            if target ~= item.target then e.via = target end
            if good then
                e.sentParts = (e.sentParts or 0) + 1
                if e.st == "queued" and e.sentParts >= (e.parts or 1) then e.st = "sent" end
            else
                e.st, e.why = "failed", why
            end
        end
        if not good then
            Comm.sendFailures = Comm.sendFailures + 1
            ns.Debug.Log("comm.send", why)
        end
        Comm.chunksSent = Comm.chunksSent + 1
        Comm.tokens = Comm.tokens - 1
    end
end

Comm._pump = pump   -- offline tests drive the pump directly

------------------------------------------------------------------ inbound

-- Rejections can arrive once per chunk; one trace entry per (sender, reason) every 30 s is enough to see them.
local rejectSeen = {}
local function traceReject(channel, sender, raw, why)
    local key = tostring(sender) .. "|" .. why
    local now = ns.Util.Now()
    if rejectSeen[key] and now - rejectSeen[key] < 30 then return end
    rejectSeen[key] = now
    Trace.Add({ dir = "in", ch = channel, peer = sender, raw = raw, st = "rejected", why = why })
end

-- One notice per kind per session; the sender is only recorded (bounded), never printed.
local function incompatible(kind, sender)
    Comm.rejected = Comm.rejected + (kind == "newer-minor" and 0 or 1)
    if not Guard.Note(Comm.hints, kind, sender) then return end
    if kind == "newer" then
        ns.Print(L["A guild member runs a newer TalentShare that cannot sync with this version. Please update the addon."])
    elseif kind == "older" then
        ns.Print(L["A guild member runs an older TalentShare that cannot sync with this version."])
    else
        ns.Print(L["A guild member runs a newer TalentShare with extra features. Updating is recommended."])
    end
end

local function onChunk(text, sender, channel, raw)
    local h, why = Codec.ParseHeader(text)
    if not h then
        if why == "legacy" then incompatible("older", sender) end   -- 0.1/0.2 builds: no version in the header
        traceReject(channel, sender, raw, why == "legacy" and "legacy 0.1/0.2 header" or "malformed chunk header")
        return
    end
    if h.major ~= ns.PROTO_MAJOR then
        incompatible(Codec.Compat(h.major, h.minor), sender)        -- before any buffer is allocated
        traceReject(channel, sender, raw, ("protocol %d.%d, mine %d.%d"):format(h.major, h.minor, ns.PROTO_MAJOR, ns.PROTO_MINOR))
        return
    end
    if Codec.Compat(h.major, h.minor) == "newer-minor" then incompatible("newer-minor", sender) end
    local id, idx, total, part = h.id, h.idx, h.total, h.part
    Comm.chunksReceived = Comm.chunksReceived + 1
    local key = sender .. ":" .. id
    local buf = Comm.buffers[key]
    if not buf or buf.total ~= total then
        buf = { total = total, parts = {}, got = 0, t = ns.Util.Now(), sender = sender, ch = channel, raw = raw }
        Comm.buffers[key] = buf
    end
    if not buf.parts[idx] then
        buf.parts[idx] = part
        buf.got = buf.got + 1
    end
    if buf.got == total then
        Comm.buffers[key] = nil
        local encoded = table.concat(buf.parts)
        local e = Trace.Add({ dir = "in", ch = channel, peer = sender, raw = raw, st = "error", parts = total, bytes = #encoded })
        local msg, err = Codec.Decode(encoded)
        if msg then
            e.mt, e.info = msg.t, Trace.Summarize(msg)
            local st, reason = Comm.sync:OnMessage(msg, sender)
            e.st, e.why = st or "ok", reason
        else
            Comm.sync.stats.dropped = Comm.sync.stats.dropped + 1
            ns.Debug.Log("comm.decode", sender, err)
            e.why = "decode: " .. tostring(err)
        end
    end
end

-- Entry point for CHAT_MSG_ADDON. The gate runs FIRST: nothing from outside the guild is parsed, buffered or answered.
function Comm.OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= ns.PREFIX or not Comm.active or type(text) ~= "string" or type(sender) ~= "string" then return end
    local raw = sender
    if channel == "GUILD" and Comm.LearnFromEcho(text, raw) then   -- only the server-filtered guild channel teaches
        Comm.lastEcho = raw
        return
    end
    sender = ns.Util.Canon(sender)
    if sender then Comm.NoteSeen(raw, sender) end
    if not sender or sender == me() then return end
    local ok, why = Guard.Accept(channel, sender, Comm.roster)
    if not ok then
        Comm.rejected = Comm.rejected + 1
        local reason = why
        if why == "not in guild" then
            local n = ns.Util.Count(Comm.roster)
            if n == 0 then
                reason = "whisper before the guild roster loaded"
            else
                local like = Trace.RosterLookalikes(sender, Comm.roster)
                reason = like and ("not in roster as " .. sender .. "; roster has " .. table.concat(like, ", ") .. " (name form mismatch)")
                    or ("not in guild roster (" .. n .. " members)")
            end
        end
        traceReject(channel, sender, raw, reason)
        return
    end
    local ok2, err = pcall(onChunk, text, sender, channel, raw)
    if not ok2 then
        ns.Debug.Log("comm.chunk", err)
        Trace.Add({ dir = "in", ch = channel, peer = sender, raw = raw, st = "error", why = "chunk: " .. tostring(err) })
    end
end

------------------------------------------------------------------ identity check

-- My name as this client builds it ("Name-" .. GetNormalizedRealmName()) must be the form the roster and the other
-- clients use: the whisper gate, WANT/WANTO ("send me YOUR record") and SNAP/OFFERS ("record name == sender") all compare
-- those strings. If the roster does not contain my name, every whisper-based sync fails silently: warn once, loudly.
function Comm.CheckIdentity()
    local n = ns.Util.Count(Comm.roster)
    if n == 0 then return nil end
    local my = me()
    if Comm.roster[my] then return true end
    local like = Trace.RosterLookalikes(my, Comm.roster)
    local why = like and ("roster lists me as " .. table.concat(like, ", ")) or ("not found among " .. n .. " roster names")
    Trace.Sys("warn", "identity: my name " .. tostring(my) .. " is not in the guild roster", why)
    if not Comm.identityWarned then
        Comm.identityWarned = true
        ns.Print(ns.Locale.Fmt(L["Sync problem: your character name does not match the guild roster, so recipes and items cannot be exchanged. Please send the {cmd} export report to the addon author."], { cmd = (ns.SLASH or {})[1] }))
    end
    return false
end

------------------------------------------------------------------ control

function Comm.RequestHello(login, force)
    if not Comm.active then return end
    local now = ns.Util.Now()
    if not force and not login and now - Comm.lastHello < 30 then return end
    Comm.lastHello = now
    Comm.sync:Hello(login)
end

function Comm.BroadcastOrder(order)
    if Comm.active then Comm.sync:BroadcastOrder(order) end
end

-- My own GUILD messages come back to me. The id in the chunk header starts with this session's salt, so an echo is
-- recognised for certain, and its raw sender is how the server spells MY name for addon senders: a different realm
-- spelling is learned as my realm (Util.LearnMyRealm). Returns true for an echo (the caller ignores it).
function Comm.LearnFromEcho(text, raw)
    local salt = text:match("^%d+%.%d+|(%x%x%x%x)")
    if salt ~= ("%04x"):format(Comm.salt % 65536) then return false end
    local myName = (tostring(me())):match("^([^-]+)")
    local name, realm = raw:match("^([^-]+)-(.+)$")
    if not name then return raw == myName end
    if name ~= myName then return false end
    if ns.Util.LearnMyRealm(realm) then
        Trace.Sys("info", "learned my realm spelling from my own echo", raw)
        Comm.Recanon()
    end
    return true
end

-- Raw sender spellings as CHAT_MSG_ADDON delivered them, by canonical name (name check in the Debug tab; bounded).
Comm.seen = {}
function Comm.NoteSeen(raw, canon)
    if Comm.seen[canon] == nil and ns.Util.Count(Comm.seen) >= 20 then return end
    Comm.seen[canon] = raw
end

-- After a new spelling of my realm was learned: every stored and cached name is canonicalized again.
function Comm.Recanon()
    if Comm.canonVersion == ns.Util.realmAliasVersion then return 0 end
    Comm.canonVersion = ns.Util.realmAliasVersion
    local n = ns.Store.Recanon()
    local roster = {}
    for name in pairs(Comm.roster) do roster[ns.Util.Canon(name) or name] = true end
    Comm.roster = roster
    if Comm.sync then
        for _, list in ipairs({ Comm.sync.wanted, Comm.sync.wantedO }) do
            local copy = {}
            for k, v in pairs(list) do copy[ns.Util.Canon(k) or k] = v end
            for k in pairs(list) do list[k] = nil end
            for k, v in pairs(copy) do list[k] = v end
        end
    end
    if n > 0 then Trace.Sys("info", "names normalized", ("%d stored names rewritten, me=%s"):format(n, tostring(me()))) end
    return n
end

function Comm.PruneRoster()
    local roster = ns.Api.GetGuildRoster()
    local count = ns.Util.Count(roster)
    if count == 0 then return end
    local first = ns.Util.Count(Comm.roster) == 0
    Comm.roster = roster
    Comm.Recanon()   -- the roster may have taught a new spelling of my realm (Api.GetGuildRoster)
    if first then
        Trace.Sys("info", "roster loaded", ("%d members, me (%s) %s"):format(count, tostring(me()), roster[me()] and "found" or "NOT found"))
    end
    Comm.CheckIdentity()
    local n = ns.Store.Prune(roster, ns.Store.db.me)
    if n > 0 then ns.Debug.Log("prune", n) end
end

-- Incomplete transfers waiting for chunks (Debug tab and export): { { sender, got, total, age } }
function Comm.InFlight()
    local out, now = {}, ns.Util.Now()
    for _, b in pairs(Comm.buffers) do
        out[#out + 1] = { sender = b.sender, got = b.got, total = b.total, age = now - b.t }
    end
    table.sort(out, function(a, b) return a.age > b.age end)
    return out
end

-- Idempotent; called at login and whenever guild membership may have changed. Never before PLAYER_LOGIN: until then the
-- stored name can still be the previously played character (SavedVariables are account-wide).
function Comm.Start()
    if Comm.active or not Comm.ready or not ns.Api.IsGuilded() then return end
    Comm.sync = ns.Sync.New({
        send = Comm.Send,
        now = ns.Util.Now,
        rand = math.random,
        store = ns.Store,
        orders = ns.orders,
        me = me,   -- a function: read at use time
        onChange = function(kind) ns.Events.Fire("DATA_CHANGED", kind) end,
    })
    Comm.active = true
    Comm.roster = ns.Api.GetGuildRoster()   -- may be empty until the first roster update; WHISPERs fail closed meanwhile
    ns.Debug.Log("comm.start", me())
    Trace.Sys("info", "sync started", ("me=%s v%s protocol %d.%d roster=%d"):format(tostring(me()), tostring(ns.VERSION),
        ns.PROTO_MAJOR, ns.PROTO_MINOR, ns.Util.Count(Comm.roster)))
    ns.Api.RequestRoster()
end

function Comm.Init()
    Comm.salt = math.random(0, 65535)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, res = pcall(function() return C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX) end)
        if not ok or res == false or (type(res) == "number" and res ~= 0) then
            Trace.Sys("warn", "prefix registration failed", tostring(res))
        end
    end
    local f = CreateFrame("Frame")
    local acc, secAcc = 0, 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        secAcc = secAcc + acc
        local step = acc
        acc = 0
        if Comm.active then
            pump(step)
            if secAcc >= 1 then
                Comm.sync:Tick(ns.Util.Now())
            end
        end
        if secAcc >= 1 then secAcc = 0 end
    end)
    local t = 0
    C_Timer.NewTicker(60, function()
        t = t + 1
        if not Comm.active then Comm.Start() end
        if Comm.active then
            local now = ns.Util.Now()
            for k, b in pairs(Comm.buffers) do
                if now - b.t > 60 then
                    Comm.buffers[k] = nil
                    -- a multi-chunk message (SNAP, OFFERS, OPUSH) that never completed: chunks were lost on the way
                    Trace.Add({ dir = "in", ch = b.ch, peer = b.sender, raw = b.raw, st = "dropped",
                        why = ("incomplete: got %d of %d chunks in 60 s"):format(b.got, b.total) })
                end
            end
            if t % 5 == 0 then ns.Api.RequestRoster() end
            if t % 15 == 0 then Comm.RequestHello(false, true) end   -- anti-entropy: changes missed while away are found
            ns.orders:Prune(now)
        end
    end)
end

------------------------------------------------------------------ slash commands

ns.Slash.comm = function()
    local s = Comm.sync and Comm.sync.stats or { sent = 0, received = 0, dropped = 0 }
    ns.Print(("comm: active=%s protocol=%d.%d sent=%d received=%d dropped=%d rejected=%d queue=%d chunks out/in=%d/%d send failures=%d roster=%d incompatible peers=%d"):format(
        tostring(Comm.active), ns.PROTO_MAJOR, ns.PROTO_MINOR, s.sent, s.received, s.dropped, Comm.rejected, #Comm.queue,
        Comm.chunksSent, Comm.chunksReceived, Comm.sendFailures, ns.Util.Count(Comm.roster), Comm.hints.count))
end

ns.Slash.hello = function()
    if not Comm.active then ns.Print("not active (not in a guild?)") return end
    Comm.RequestHello(false, true)
    ns.Print("hello sent")
end

-- /ts debug [n]: the last n lines of the debug log (default 15); /ts trace [n]: the last n network trace entries
ns.Slash.debug = function(arg)
    local n = tonumber((arg or ""):match("%d+")) or 15
    local log = ns.db and ns.db.debug or {}
    for i = math.max(1, #log - n + 1), #log do print(log[i]) end
end

ns.Slash.trace = function(arg)
    local n = tonumber((arg or ""):match("%d+")) or 20
    local list = Trace.List((arg or ""):match("problems") and "problems" or nil)
    for i = math.min(n, #list), 1, -1 do print(ns.Util.Esc(Trace.Format(list[i]))) end
end

ns.Slash.chars = function()
    for _, rec in ipairs(ns.Store.ListChars()) do
        local n = 0
        for _, p in pairs(rec.professions) do n = n + ns.Util.Count(p.recipes) end
        print(("%s lvl %s rev %s recipes %d"):format(rec.name, tostring(rec.level), tostring(rec.rev), n))
    end
end
