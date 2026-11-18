-- Channel: chunking, reassembly, the guild gate, echo learning, the SHARED send bucket (spec RF2) and HELLO coalescing.

-- C_ChatInfo stub that records every SendAddonMessage call; returns 0 (Success) unless `result` says otherwise.
local function withChat(result, body)
    local saved = C_ChatInfo
    local calls = {}
    C_ChatInfo = { SendAddonMessage = function(prefix, text, channel, target)
        calls[#calls + 1] = { prefix = prefix, text = text, channel = channel, target = target }
        return result
    end, RegisterAddonMessagePrefix = function() return true end }
    local ok, errorMessage = pcall(body, calls)
    C_ChatInfo = saved
    if not ok then error(errorMessage, 0) end
end

-- A channel for `prefix` with a recording sync; `me` and `roster` as given.
local function newChannel(harness, lib, prefix, me, roster, major)
    local log, trace, db = harness.logAndTrace(lib)
    local received = {}
    local codec = lib.Codec.New({ major = major or 1, minor = 0 })
    local channel = lib.Channel.New({
        prefix = prefix, codec = codec, log = log, trace = trace, me = function() return me end,
        priorityTypes = { HELLO = true },
        guild = { IsGuilded = function() return true end, GetGuildRoster = function() return roster or {} end, RequestRoster = function() end },
        newSync = function()
            return { statistics = { dropped = 0 }, Hello = function() received.hello = (received.hello or 0) + 1 end, Tick = function() end,
                OnMessage = function(_, message, sender) received[#received + 1] = { message = message, sender = sender }; return "ok" end }
        end,
    })
    channel.ready = true
    channel.Start()
    channel.salt = #prefix * 1000
    return channel, received, db
end

-- delivers every chunk `calls` holds (from index `from`) to `channel` as CHAT_MSG_ADDON with `sender`
local function deliver(channel, calls, sender, from)
    for index = from or 1, #calls do
        local call = calls[index]
        channel.OnAddonMessage(call.prefix, call.text, call.channel, sender)
    end
end

return {
    ["channel: a big message is chunked, sent under the channel's prefix and reassembled"] = function(harness)
        local lib = harness.library()
        withChat(0, function(calls)
            local sender = newChannel(harness, lib, "GGames", "A-R", { ["B-R"] = true })
            local receiver, received = newChannel(harness, lib, "GGames", "B-R", { ["A-R"] = true })
            local big = {}
            for index = 1, 400 do big[index] = ("entry %d %x"):format(index, index * 7919) end
            sender.Send({ t = "GAMES", list = big }, "WHISPER", "B-R")
            harness.truthy(#sender.queue > 1, "several chunks")
            while #sender.queue > 0 do sender._pump(10) end
            for _, call in ipairs(calls) do
                harness.equal(call.prefix, "GGames")
                harness.truthy(#call.text <= 255, "chunk too long: " .. #call.text)
            end
            deliver(receiver, calls, "A-R")
            harness.equal(#received, 1)
            harness.equal(received[1].message.list[400], big[400])
            harness.equal(received[1].sender, "A-R")
        end)
    end,

    ["channel: whispers from outside the roster and foreign prefixes are dropped before parsing"] = function(harness)
        local lib = harness.library()
        withChat(0, function(calls)
            local sender = newChannel(harness, lib, "GGames", "M-R", {})
            local receiver, received, db = newChannel(harness, lib, "GGames", "B-R", { ["A-R"] = true })
            sender.Send({ t = "HELLO" }, "WHISPER", "B-R"); sender._pump(10)
            deliver(receiver, calls, "M-R")
            harness.equal(#received, 0)
            harness.equal(db.trace[#db.trace].st, "rejected")
            receiver.OnAddonMessage("TShare", calls[1].text, "GUILD", "A-R")
            harness.equal(#received, 0, "another addon's prefix is not ours")
        end)
    end,

    ["channel: another major is reported once and never buffered"] = function(harness)
        local lib = harness.library()
        withChat(0, function(calls)
            local hints = {}
            local sender = newChannel(harness, lib, "GGames", "A-R", {}, 2)
            local receiver, received = newChannel(harness, lib, "GGames", "B-R", {})
            receiver.options.onIncompatible = function(kind) hints[#hints + 1] = kind end
            sender.Send({ t = "HELLO" }, "GUILD"); sender.Send({ t = "HELLO" }, "GUILD"); sender._pump(10)
            deliver(receiver, calls, "A-R")
            harness.equal(#received, 0); harness.equal(#hints, 1); harness.equal(hints[1], "newer")
            harness.equal(next(receiver.buffers), nil)
        end)
    end,

    ["channel: one token bucket for every channel (two addons together keep the server rate)"] = function(harness)
        local lib = harness.library()
        withChat(0, function(calls)
            local first = newChannel(harness, lib, "TShare", "A-R", {})
            local second = newChannel(harness, lib, "GGames", "A-R", {})
            lib.Channel.Initialize(first); lib.Channel.Initialize(second)
            for index = 1, 10 do first.Send({ t = "X", n = index }, "GUILD"); second.Send({ t = "X", n = index }, "GUILD") end
            lib.Channel.shared.tokens = lib.Channel.BUCKET_CAPACITY
            lib.Channel.SendAll()
            harness.equal(#calls, lib.Channel.BUCKET_CAPACITY, "the burst is shared")
            local prefixes = {}
            for _, call in ipairs(calls) do prefixes[call.prefix] = (prefixes[call.prefix] or 0) + 1 end
            harness.truthy(prefixes.TShare and prefixes.GGames, "both channels get a turn")
            lib.Channel.Refill(1); lib.Channel.SendAll()
            harness.equal(#calls, lib.Channel.BUCKET_CAPACITY, "less than one token after 1 s at 0.9/s")
            lib.Channel.Refill(10); lib.Channel.SendAll()
            harness.equal(#calls, 2 * lib.Channel.BUCKET_CAPACITY, "refill is capped at the burst")
        end)
    end,

    ["channel: a throttled send stays queued and empties the bucket"] = function(harness)
        local lib = harness.library()
        withChat(lib.Channel.THROTTLE_RESULT_CODE, function(calls)
            local channel = newChannel(harness, lib, "GGames", "A-R", {})
            channel.Send({ t = "X" }, "GUILD")
            channel._pump(10)
            harness.equal(#channel.queue, 1); harness.equal(lib.Channel.shared.tokens, 0)
            harness.equal(#calls, 1)
        end)
    end,

    ["channel: my own GUILD echo is recognised and teaches my realm spelling to every channel"] = function(harness)
        local lib = harness.library()
        local saved = GetNormalizedRealmName
        GetNormalizedRealmName = function() return "MyRealm" end
        local ok, errorMessage = pcall(withChat, 0, function(calls)
            local renamed = 0
            local first = newChannel(harness, lib, "TShare", "Me-MyRealm", {})
            local second = newChannel(harness, lib, "GGames", "Me-MyRealm", {})
            second.options.canonicalizeStored = function() renamed = renamed + 1; return 0 end
            lib.Channel.Initialize(first); lib.Channel.Initialize(second)
            first.Send({ t = "HELLO" }, "GUILD"); first._pump(10)
            first.OnAddonMessage("TShare", calls[1].text, "GUILD", "Me-Other Spelling")
            harness.equal(first.lastEcho, "Me-Other Spelling")
            harness.truthy(lib.Utility.IsMyRealm("OtherSpelling"), "alias learned")
            harness.equal(renamed, 1, "the other addon re-keyed its names too")
        end)
        GetNormalizedRealmName = saved
        if not ok then error(errorMessage, 0) end
    end,

    ["channel: HELLOs are coalesced to one per interval"] = function(harness)
        local lib = harness.library()
        withChat(0, function()
            local channel, received = newChannel(harness, lib, "GGames", "A-R", {})
            channel.RequestHelloSoon()
            harness.equal(received.hello, 1)
            for _ = 1, 5 do channel.RequestHelloSoon() end
            harness.equal(received.hello, 1)
            harness.clock = harness.clock + lib.Channel.HELLO_INTERVAL_SECONDS
            channel.SendDueHello(harness.clock)
            harness.equal(received.hello, 2)
            channel.SendDueHello(harness.clock + 100)
            harness.equal(received.hello, 2, "nothing due")
        end)
    end,

    ["channel: not in a guild -> not started, sends are ignored"] = function(harness)
        local lib = harness.library()
        local log, trace = harness.logAndTrace(lib)
        local channel = lib.Channel.New({ prefix = "GGames", codec = lib.Codec.New({ major = 1, minor = 0 }), log = log, trace = trace,
            me = function() return "A-R" end, guild = { IsGuilded = function() return false end },
            newSync = function() error("must not start") end })
        channel.ready = true
        channel.Start()
        harness.equal(channel.active, false)
        channel.Send({ t = "HELLO" }, "GUILD")
        harness.equal(#channel.queue, 0)
        channel.RequestHelloSoon()
    end,

    ["channel: the pump resolves whisper targets with Utility.WhisperTarget"] = function(harness)
        local lib = harness.library()
        local saved = GetNormalizedRealmName
        GetNormalizedRealmName = function() return "MyRealm" end
        local ok, errorMessage = pcall(withChat, 0, function(calls)
            local channel = newChannel(harness, lib, "GGames", "A-MyRealm", {})
            channel.Send({ t = "X" }, "WHISPER", "Peer-MyRealm"); channel._pump(10)
            harness.equal(calls[1].target, "Peer", "same realm: the name alone")
        end)
        GetNormalizedRealmName = saved
        if not ok then error(errorMessage, 0) end
    end,
}
