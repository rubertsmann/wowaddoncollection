-- Whisper buttons: a player on my own realm is addressed by character name only; other realms keep "Name-Realm".
local function withRealm(realm, fn)
    local saved = GetNormalizedRealmName
    GetNormalizedRealmName = realm and function() return realm end or nil
    local ok, err = pcall(fn)
    GetNormalizedRealmName = saved
    if not ok then error(err, 0) end
end

return {
    ["whisper: same-realm characters are addressed by name only"] = function(h)
        local U = h.ns().Util
        withRealm("Test Realm-1", function()
            h.eq(U.WhisperTarget("Alice-TestRealm-1"), "Alice")
        end)
    end,

    ["names: lists show the short form on my realm (ShortName = WhisperTarget)"] = function(h)
        local U = h.ns().Util
        withRealm("TestRealm", function()
            h.eq(U.ShortName("Alice-TestRealm"), "Alice")
            h.eq(U.ShortName("Bob-OtherRealm"), "Bob-OtherRealm")
        end)
    end,

    -- the game's own Ambiguate decides when the client has it; the realm comparison is only the offline fallback
    ["names: the game's Ambiguate is used when available"] = function(h)
        local U = h.ns().Util
        local saved = Ambiguate
        local calls = {}
        Ambiguate = function(name, ctx) calls[#calls + 1] = ctx; return "Short" end
        local ok, err = pcall(function() h.eq(U.ShortName("Alice-AnyRealm"), "Short") end)
        Ambiguate = saved
        if not ok then error(err, 0) end
        h.eq(calls[1], "none")
    end,

    ["whisper: other realms keep the realm suffix"] = function(h)
        local U = h.ns().Util
        withRealm("Mine", function()
            h.eq(U.WhisperTarget("Peer-Other"), "Peer-Other")
        end)
    end,

    ["whisper: realm spaces are ignored in the comparison, odd input passes through"] = function(h)
        local U = h.ns().Util
        withRealm("Die Aldor", function()
            h.eq(U.WhisperTarget("Peer-DieAldor"), "Peer")
            h.eq(U.WhisperTarget("Peer"), "Peer")
            h.eq(U.WhisperTarget(nil), nil)
        end)
    end,

    -- the same "no player named 'Name-Realm' is online" error comes from addon whispers (WANT/SNAP/OPUSH replies)
    ["whisper: addon whispers use the same target rule"] = function(h)
        local f = assert(io.open("Core/Comm.lua", "rb"))
        local src = f:read("*a"); f:close()
        local line = src:match("[^\r\n]*SendAddonMessage,[^\r\n]*")
        h.truthy(line and line:find("target", 1, true) and not line:find("item.target", 1, true), "SendAddonMessage must get the resolved target")
        h.truthy(src:find('item.dist == "WHISPER" and ns.Util.WhisperTarget(item.target)', 1, true), "pump must resolve whisper targets")
    end,

    ["whisper: without a known own realm the full name is kept"] = function(h)
        local U = h.ns().Util
        withRealm(nil, function() h.eq(U.WhisperTarget("Peer-Realm"), "Peer-Realm") end)
    end,
}
