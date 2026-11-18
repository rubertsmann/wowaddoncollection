-- Sync engine: the generic record-pull protocol over a fake guild bus (codec round trip on every delivery).
local PROTOCOL = 1

-- One peer holding "note" records { name, rev, text }: a minimal record kind, like GuildGames' games record.
local function peer(harness, lib, bus, name, options)
    options = options or {}
    local p = { name = name, records = {}, changes = {}, log = {} }
    local log, trace, db = harness.logAndTrace(lib)
    p.db = db
    p.sync = lib.Sync.New({
        send = function(message, channel, target) bus.queue[#bus.queue + 1] = { from = name, msg = message, dist = channel, target = target } end,
        now = function() return harness.clock end,
        random = function() return 0.5 end,
        me = name, protocol = PROTOCOL, log = log, trace = trace,
        horizon = function() return harness.clock + 86400 end,
        onChange = function(kind) p.changes[#p.changes + 1] = kind end,
    })
    p.sync:AddRecordKind({
        name = "note", label = "note", helloField = options.helloField or "nrev", required = options.required,
        absentNote = "note: peer has none",
        requestType = "WANTN", answerType = "NOTE", recordField = "note",
        heldRevision = function(playerName) local record = p.records[playerName]; return record and record.rev or 0 end,
        myRecord = function(myName) return p.records[myName] end,
        sanitize = function(record)
            if type(record) ~= "table" or type(record.name) ~= "string" or type(record.rev) ~= "number" or type(record.text) ~= "string" then return nil end
            return { name = record.name, rev = record.rev, text = record.text }
        end,
        store = function(_, record)
            local held = p.records[record.name]
            if held and held.rev >= record.rev then return false end
            p.records[record.name] = record
            return true
        end,
    })
    p.codec = lib.Codec.New({ major = PROTOCOL, minor = 0 })
    bus.peers[name] = p
    return p
end

local function newBus() return { peers = {}, queue = {}, log = {} } end

local function pump(bus, drop)
    local guard = 0
    while #bus.queue > 0 and guard < 10000 do
        guard = guard + 1
        local item = table.remove(bus.queue, 1)
        bus.log[#bus.log + 1] = item
        local wire = bus.peers[item.from].codec.Encode(item.msg)
        for name, p in pairs(bus.peers) do
            local to = (item.dist == "GUILD" and name ~= item.from) or (item.dist == "WHISPER" and name == item.target)
            if to and not (drop and drop(item)) then
                local status, reason = p.sync:OnMessage(assert(p.codec.Decode(wire)), item.from)
                p.log[#p.log + 1] = { t = item.msg.t, status = status, reason = reason }
            end
        end
    end
end

local function advance(harness, bus, seconds, drop)
    for _ = 1, seconds do
        harness.clock = harness.clock + 1
        for _, p in pairs(bus.peers) do p.sync:Tick(harness.clock) end
        pump(bus, drop)
    end
end

local function sent(bus, messageType, dist)
    local found = {}
    for _, item in ipairs(bus.log) do
        if item.msg.t == messageType and (not dist or item.dist == dist) then found[#found + 1] = item end
    end
    return found
end

return {
    ["sync: HELLO announces the revision, the peer pulls by whisper and stores the record"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local a, b = peer(harness, lib, bus, "A-R"), peer(harness, lib, bus, "B-R")
        a.records["A-R"] = { name = "A-R", rev = 500, text = "hi" }
        a.sync:Hello(); pump(bus)
        harness.equal(sent(bus, "HELLO")[1].msg.nrev, 500)
        harness.equal(#sent(bus, "WANTN", "WHISPER"), 1)
        advance(harness, bus, 3)
        harness.equal(b.records["A-R"].text, "hi")
        harness.equal(b.changes[1], "note")
        b.sync:Hello(); pump(bus)
        harness.equal(sent(bus, "HELLO")[2].msg.nrev, nil, "an optional field is left out when I have no record")
        harness.equal(a.log[#a.log].reason, "note: peer has none")
    end,

    ["sync: lost whispers -> retries on GUILD, the owner answers on GUILD once per revision"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local a, b, c = peer(harness, lib, bus, "A-R"), peer(harness, lib, bus, "B-R"), peer(harness, lib, bus, "C-R")
        a.records["A-R"] = { name = "A-R", rev = 700, text = "x" }
        local function dropWhispers(item) return item.dist == "WHISPER" end
        a.sync:Hello(); pump(bus, dropWhispers)
        advance(harness, bus, 50, dropWhispers)
        harness.truthy(#sent(bus, "WANTN", "GUILD") >= 1, "retry went out on GUILD")
        harness.equal(#sent(bus, "NOTE", "GUILD"), 1, "one GUILD answer serves both")
        harness.equal(b.records["A-R"].rev, 700); harness.equal(c.records["A-R"].rev, 700)
    end,

    ["sync: a pull gives up after the last retry and a HELLO a minute later restarts it"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local a, b = peer(harness, lib, bus, "A-R"), peer(harness, lib, bus, "B-R")
        a.records["A-R"] = { name = "A-R", rev = 900, text = "x" }
        local function dropAll(item) return item.msg.t ~= "HELLO" end
        a.sync:Hello(); pump(bus, dropAll)
        advance(harness, bus, 45 + 90 + 180 + 1, dropAll)
        harness.truthy(b.sync.pulls.note["A-R"].gaveUp, "gave up")
        harness.equal(b.db.trace[#b.db.trace].st, "warn")
        a.sync:Hello(); pump(bus, dropAll)
        harness.truthy(b.sync.pulls.note["A-R"].gaveUp, "still locked right after giving up")
        harness.clock = harness.clock + lib.Sync.GIVE_UP_RESET_SECONDS
        a.sync:Hello(); pump(bus)
        advance(harness, bus, 3)
        harness.equal(b.records["A-R"].rev, 900)
    end,

    ["sync: a record can only come from its author; invalid records are errors"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local b = peer(harness, lib, bus, "B-R")
        local status, reason = b.sync:OnMessage({ v = PROTOCOL, t = "NOTE", note = { name = "A-R", rev = 5, text = "forged" } }, "M-R")
        harness.equal(status, "error"); harness.truthy(reason:find("note/sender mismatch", 1, true), reason)
        status, reason = b.sync:OnMessage({ v = PROTOCOL, t = "NOTE", note = { name = "M-R", rev = "x" } }, "M-R")
        harness.equal(status, "error"); harness.equal(reason, "invalid note")
        status = b.sync:OnMessage({ v = 99, t = "NOTE" }, "M-R")
        harness.equal(status, "dropped")
        status, reason = b.sync:OnMessage({ v = PROTOCOL, t = "NOPE" }, "M-R")
        harness.equal(reason, "unknown message type NOPE")
        harness.equal(b.records["A-R"], nil)
    end,

    ["sync: a required HELLO field must be a sane revision"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local b = peer(harness, lib, bus, "B-R", { required = true, helloField = "rev" })
        local status, reason = b.sync:OnMessage({ v = PROTOCOL, t = "HELLO" }, "A-R")
        harness.equal(status, "error"); harness.equal(reason, "bad rev")
        status, reason = b.sync:OnMessage({ v = PROTOCOL, t = "HELLO", rev = 1 / 0 }, "A-R")
        harness.equal(status, "error")
        status, reason = b.sync:OnMessage({ v = PROTOCOL, t = "HELLO", rev = 0 }, "A-R")
        harness.equal(status, "ok"); harness.equal(reason, "note: peer has no record yet")
        harness.equal(b.sync:_helloMessage().rev, 0, "a required field is always sent")
    end,

    ["sync: login HELLOs are answered with a whispered HELLO, within a budget per minute"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local b = peer(harness, lib, bus, "B-R")
        for index = 1, lib.Sync.MAXIMUM_LOGIN_REPLIES_PER_MINUTE + 3 do
            b.sync:OnMessage({ v = PROTOCOL, t = "HELLO", login = true }, "P" .. index .. "-R")
        end
        harness.equal(#b.sync.pending, lib.Sync.MAXIMUM_LOGIN_REPLIES_PER_MINUTE)
        harness.equal(b.log[1], nil)
        harness.truthy(b.sync.pending[1].channel == "WHISPER")
    end,

    ["sync: a request names me in any realm spelling; a request for someone else is ignored"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local a = peer(harness, lib, bus, "A-R")
        a.records["A-R"] = { name = "A-R", rev = 3, text = "x" }
        local status, reason = a.sync:OnMessage({ v = PROTOCOL, t = "WANTN", names = { "Z-R" } }, "B-R")
        harness.equal(status, "ignored"); harness.truthy(reason:find("name mismatch", 1, true), reason)
        status = a.sync:OnMessage({ v = PROTOCOL, t = "WANTN", names = { "A-R" } }, "B-R")
        harness.equal(status, "ok"); harness.equal(#a.sync.pending, 1)
        harness.equal(a.sync.pending[1].message.note.rev, 3)
    end,

    ["sync: hello hooks and custom handlers extend the protocol"] = function(harness)
        local lib = harness.library()
        local bus = newBus()
        local a, b = peer(harness, lib, bus, "A-R"), peer(harness, lib, bus, "B-R")
        local seen = {}
        a.sync:AddHelloHook({ build = function(_, message) message.extra = 42 end })
        b.sync:AddHelloHook({ handle = function(_, message, sender, notes) seen.extra = message.extra; notes[#notes + 1] = "extra seen" end })
        b.sync:AddHandler("PING", function(sync, message, sender) seen.ping = sender; sync:_note("ok", "pong") end)
        a.sync:Hello(); a.sync:_send({ t = "PING" }, "GUILD"); pump(bus)
        harness.equal(seen.extra, 42); harness.equal(seen.ping, "A-R")
        harness.truthy(b.log[1].reason:find("extra seen", 1, true))
        harness.equal(b.log[2].reason, "pong")
    end,
}
