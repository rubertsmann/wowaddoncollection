-- Whisper buttons: a player on my own realm is addressed by character name only; other realms keep "Name-Realm".
local function withRealm(realm, fn)
    local saved = GetNormalizedRealmName
    GetNormalizedRealmName = realm and function() return realm end or nil
    local ok, err = pcall(fn)
    GetNormalizedRealmName = saved
    if not ok then error(err, 0) end
end

return {
    ["whisper: same-realm characters are addressed by name only"] = function(harness)
        local U = harness.addon().Utility
        withRealm("Test Realm-1", function()
            harness.equal(U.WhisperTarget("Alice-TestRealm-1"), "Alice")
        end)
    end,

    ["names: lists show the short form on my realm (ShortName = WhisperTarget)"] = function(harness)
        local U = harness.addon().Utility
        withRealm("TestRealm", function()
            harness.equal(U.ShortName("Alice-TestRealm"), "Alice")
            harness.equal(U.ShortName("Bob-OtherRealm"), "Bob-OtherRealm")
        end)
    end,

    -- for realms other than my own, the game's Ambiguate decides when the client has it (connected realms)
    ["names: the game's Ambiguate is used when available"] = function(harness)
        local U = harness.addon().Utility
        local saved = Ambiguate
        local calls = {}
        Ambiguate = function(name, ctx) calls[#calls + 1] = ctx; return "Short" end
        local ok, err = pcall(function() harness.equal(U.ShortName("Alice-AnyRealm"), "Short") end)
        Ambiguate = saved
        if not ok then error(err, 0) end
        harness.equal(calls[1], "none")
    end,

    -- Ambiguate that does not know the normalized realm returns the name unchanged: my own realm must still be stripped
    ["whisper: my own realm is stripped even when Ambiguate returns the full name"] = function(harness)
        local U = harness.addon().Utility
        local saved = Ambiguate
        Ambiguate = function(name) return name end
        local ok, err = pcall(withRealm, "Mine", function()
            harness.equal(U.WhisperTarget("Peer-Mine"), "Peer")
            harness.equal(U.WhisperTarget("Peer-Other"), "Peer-Other")
        end)
        Ambiguate = saved
        if not ok then error(err, 0) end
    end,

    ["whisper: other realms keep the realm suffix"] = function(harness)
        local U = harness.addon().Utility
        withRealm("Mine", function()
            harness.equal(U.WhisperTarget("Peer-Other"), "Peer-Other")
        end)
    end,

    ["whisper: realm spaces are ignored in the comparison, odd input passes through"] = function(harness)
        local U = harness.addon().Utility
        withRealm("Die Aldor", function()
            harness.equal(U.WhisperTarget("Peer-DieAldor"), "Peer")
            harness.equal(U.WhisperTarget("Peer"), "Peer")
            harness.equal(U.WhisperTarget(nil), nil)
        end)
    end,

    -- the same "no player named 'Name-Realm' is online" error comes from addon whispers (WANT/SNAP/OPUSH replies)
    ["whisper: addon whispers use the same target rule"] = function(harness)
        local f = assert(io.open("Core/Net/Communication.lua", "rb"))
        local src = f:read("*a"); f:close()
        local line = src:match("[^\r\n]*SendAddonMessage,[^\r\n]*")
        harness.truthy(line and line:find("resolvedTarget", 1, true) and not line:find("queuedChunk.target", 1, true), "SendAddonMessage must get the resolved target")
        harness.truthy(src:find('queuedChunk.channel == "WHISPER" and addon.Utility.WhisperTarget(queuedChunk.target)', 1, true), "pump must resolve whisper targets")
    end,

    ["whisper: without a known own realm the full name is kept"] = function(harness)
        local U = harness.addon().Utility
        withRealm(nil, function() harness.equal(U.WhisperTarget("Peer-Realm"), "Peer-Realm") end)
    end,
}
