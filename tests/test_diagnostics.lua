-- Feature 008: sync diagnostics (network trace, decision reasons, identity checks, export report).

local function commNs(harness, me, roster)
    local addon = harness.addon()
    local out = { prints = {}, sent = {} }
    addon.Print = function(m) out.prints[#out.prints + 1] = m end
    addon.Store.db.me = me
    addon.Api = { GetPlayerInformation = function() return { name = me } end, GetGuildRoster = function() return roster or {} end,
        IsGuilded = function() return true end, RequestRoster = function() end }
    addon.orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    local C = addon.Communication
    C.active = true
    C.roster = roster or {}
    C.sync = addon.Sync.New({
        send = function(msg, dist, target) out.sent[#out.sent + 1] = { msg = msg, dist = dist, target = target } end,
        now = function() return harness.clock end, random = function() return 0 end,
        store = addon.Store, orders = addon.orders, me = function() return addon.Store.db.me end, onChange = function() end,
    })
    out.addon, out.C = addon, C
    return out
end

local function chunk(addon, msg, id)
    return addon.Codec.Header(id or "a1", 1, 1) .. addon.Codec.Encode(msg)
end

local function newest(addon, filter) return addon.Trace.List(filter)[1] end

return {
    ["trace: ring is capped, newest first, problems filter"] = function(harness)
        local addon = harness.addon()
        for i = 1, addon.Trace.MAXIMUM_ENTRIES + 25 do addon.Trace.Add({ dir = "out", mt = "HELLO", st = (i % 10 == 0) and "failed" or "sent" }) end
        harness.equal(#addon.db.trace, addon.Trace.MAXIMUM_ENTRIES)
        local list = addon.Trace.List()
        harness.truthy(list[1].seq > list[2].seq, "newest first")
        for _, e in ipairs(addon.Trace.List("problems")) do harness.equal(e.st, "failed") end
        harness.equal(#addon.Trace.List("in"), 0)
        addon.Trace.Clear()
        harness.equal(#addon.Trace.List(), 0)
    end,

    ["trace: persisted ring is sanitized on load (non-tables dropped, capped)"] = function(harness)
        local addon = harness.addon()
        local junk = { "x", 5, { dir = "in", st = "ok" } }
        for _ = 1, addon.Trace.MAXIMUM_ENTRIES + 3 do junk[#junk + 1] = { dir = "sys", st = "info" } end
        addon.Store.Init({ schema = addon.Store.SCHEMA, trace = junk })
        harness.equal(#addon.db.trace, addon.Trace.MAXIMUM_ENTRIES)
        for _, e in ipairs(addon.db.trace) do harness.equal(type(e), "table") end
        addon.Store.Init({ schema = addon.Store.SCHEMA, trace = "garbage" })
        harness.equal(type(addon.db.trace), "table")
    end,

    ["trace: summaries name the payload without dumping it"] = function(harness)
        local T = harness.addon().Trace
        harness.equal(T.Summarize({ t = "HELLO", rev = 5, orev = 7, odig = { a = 1, b = 2 }, login = true }), "rev=5 orev=7 odig=2 login")
        harness.equal(T.Summarize({ t = "WANT", names = { "A-R" } }), "names=A-R")
        harness.equal(T.Summarize({ t = "SNAP", char = harness.character("A-R", 9, { 1, 2, 3 }), catalog = { [1] = {} } }), "char=A-R rev=9 recipes=3 catalog=1")
        harness.equal(T.Summarize("junk"), "?")
        harness.equal(T.RosterLookalikes("Bob-RealmA", { ["Bob-Realm A"] = true, ["Bobby-RealmA"] = true })[1], "Bob-Realm A")
        harness.equal(T.RosterLookalikes("Bob-RealmA", { ["Bob-RealmA"] = true }), nil)
    end,

    ["sync: every handled message reports a decision"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        local S = c.C.sync
        local st, why = S:OnMessage({ v = c.addon.PROTOCOL, t = "HELLO", rev = 50 }, "Peer-R")
        harness.equal(st, "ok"); harness.truthy(why:find("-> WANT", 1, true), why)
        st, why = S:OnMessage({ v = c.addon.PROTOCOL, t = "HELLO", rev = 50 }, "Peer-R")
        harness.truthy(why:find("WANT pending (try 1", 1, true), why)
        st, why = S:OnMessage({ v = c.addon.PROTOCOL, t = "NOPE" }, "Peer-R")
        harness.equal(st, "dropped")
        st, why = S:OnMessage({ v = c.addon.PROTOCOL, t = "HELLO", rev = 1 }, "Me-R")
        harness.equal(why, "own echo")
        st, why = S:OnMessage({ v = c.addon.PROTOCOL + 1, t = "HELLO", rev = 1 }, "Peer-R")
        harness.equal(st, "dropped")
    end,

    ["sync: a WANT for another form of my name is reported as a name mismatch"] = function(harness)
        local c = commNs(harness, "Me-RealmA", {})
        c.addon.Store.PutCharacter(harness.character("Me-RealmA", 10, { 1 }))
        local st, why = c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "WANT", names = { "Me-OtherRealm" } }, "Peer-R")
        harness.equal(st, "ignored"); harness.truthy(why:find("name mismatch", 1, true), why)
        st, why = c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "WANT", names = { "Me-RealmA" } }, "Peer-R")
        harness.equal(st, "ok"); harness.equal(#c.C.sync.pending, 1)
        st, why = c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "WANTO", names = { "Me-OtherRealm" } }, "Peer-R")
        harness.truthy(why:find("name mismatch", 1, true), why)
    end,

    ["sync: SNAP/OFFERS whose record name differs from the sender say so"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        local st, why = c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "SNAP", char = harness.character("Bob-X", 5, { 1 }), catalog = {} }, "Bob-R")
        harness.equal(st, "error"); harness.truthy(why:find("record Bob-X from Bob-R", 1, true), why)
        st, why = c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "SNAP", char = harness.character("Bob-R", 5, { 1 }), catalog = {} }, "Bob-R")
        harness.equal(st, "ok"); harness.equal(why, "stored")
        st, why = c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "SNAP", char = harness.character("Bob-R", 5, { 1 }), catalog = {} }, "Bob-R")
        harness.equal(st, "ignored")
    end,

    ["sync: identity is read at use time (Comm may start before the character is known)"] = function(harness)
        local c = commNs(harness, "OldAlt-R", {})
        c.addon.Store.db.me = "Main-R"   -- PLAYER_LOGIN set the real character after Sync was created
        c.addon.Store.PutCharacter(harness.character("Main-R", 10, { 1 }))
        local st = c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "WANT", names = { "Main-R" } }, "Peer-R")
        harness.equal(st, "ok")
        harness.equal(c.C.sync:_helloMessage(false).rev, 10)
    end,

    ["comm: Start refuses to run before PLAYER_LOGIN"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        c.C.active, c.C.ready = false, false
        c.C.Start()
        harness.equal(c.C.active, false)
    end,

    ["comm: inbound messages are traced with Sync's decision"] = function(harness)
        local c = commNs(harness, "Me-R", { ["Peer-R"] = true })
        c.C.OnAddonMessage(c.addon.PREFIX, chunk(c.addon, { t = "HELLO", rev = 7 }), "GUILD", "Peer-R")
        local e = newest(c.addon, "in")
        harness.equal(e.mt, "HELLO"); harness.equal(e.st, "ok"); harness.equal(e.peer, "Peer-R"); harness.truthy(e.why:find("WANT", 1, true))
        c.C.OnAddonMessage(c.addon.PREFIX, c.addon.Codec.Header("b2", 1, 1) .. "garbage", "GUILD", "Peer-R")
        e = newest(c.addon, "in")
        harness.equal(e.st, "error"); harness.truthy(e.why:find("decode", 1, true))
    end,

    ["comm: a whisper rejected by the gate names the roster's form of the sender"] = function(harness)
        local c = commNs(harness, "Me-R", { ["Bob-Other Realm"] = true })
        c.C.OnAddonMessage(c.addon.PREFIX, chunk(c.addon, { t = "WANT", names = { "Me-R" } }), "WHISPER", "Bob-OtherRealm")
        local e = newest(c.addon, "in")
        harness.equal(e.st, "rejected"); harness.truthy(e.why:find("Bob-Other Realm", 1, true), e.why)
        -- repeated chunks of the same rejection do not flood the trace
        c.C.OnAddonMessage(c.addon.PREFIX, chunk(c.addon, { t = "WANT", names = { "Me-R" } }, "a2"), "WHISPER", "Bob-OtherRealm")
        harness.equal(#c.addon.Trace.List("in"), 1)
        local empty = commNs(harness, "Me-R", {})
        empty.C.OnAddonMessage(empty.addon.PREFIX, chunk(empty.addon, { t = "WANT", names = { "Me-R" } }), "WHISPER", "Bob-R")
        harness.truthy(newest(empty.addon, "in").why:find("before the guild roster loaded", 1, true))
    end,

    ["comm: outbound entries go queued -> sent, and failed with the result name"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        local savedChat, savedAmb = C_ChatInfo, Ambiguate
        local code = 0
        C_ChatInfo = { SendAddonMessage = function() return code end }
        Ambiguate = nil
        local ok, err = pcall(function()
            c.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
            local e = newest(c.addon, "out")
            harness.equal(e.st, "queued"); harness.equal(e.parts, 1)
            c.C._pump(10)
            harness.equal(e.st, "sent")
            code = 12
            c.C.Send({ t = "WANT", names = { "Bob-R" } }, "WHISPER", "Bob-R")
            c.C._pump(10)
            e = newest(c.addon, "out")
            harness.equal(e.st, "failed"); harness.equal(e.why, "TargetOffline")
            harness.equal(c.C.sendFailures, 1)
            code = false
            c.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
            c.C._pump(10)
            harness.equal(newest(c.addon, "out").st, "failed")
            code = true   -- classic-style boolean success
            c.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
            c.C._pump(10)
            harness.equal(newest(c.addon, "out").st, "sent")
        end)
        C_ChatInfo, Ambiguate = savedChat, savedAmb
        if not ok then error(err, 0) end
    end,

    ["comm: an oversized message is traced as dropped instead of vanishing"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        local big = {}
        for i = 1, 20000 do big[i] = tostring(math.random()) .. i end
        c.C.Send({ t = "SNAP", char = { name = "Me-R", junk = big } }, "WHISPER", "Bob-R")
        local e = newest(c.addon, "out")
        harness.equal(e.st, "dropped"); harness.truthy(e.why:find("too big", 1, true), e.why)
    end,

    ["identity: my name missing from the roster warns once and names the roster's form"] = function(harness)
        local c = commNs(harness, "Me-RealmA", { ["Me-Realm A"] = true, ["Bob-Realm A"] = true })
        harness.equal(c.C.CheckIdentity(), false)
        harness.equal(c.C.CheckIdentity(), false)
        harness.equal(#c.prints, 1)
        local e = newest(c.addon, "sys")
        harness.equal(e.st, "warn"); harness.truthy(e.info:find("Me-Realm A", 1, true), e.info)
        local ok = commNs(harness, "Me-R", { ["Me-R"] = true })
        harness.equal(ok.C.CheckIdentity(), true); harness.equal(#ok.prints, 0)
        harness.equal(commNs(harness, "Me-R", {}).C.CheckIdentity(), nil)   -- roster not loaded: no verdict
    end,

    ["identity: a roster prune that drops received records is traced"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        c.addon.Store.PutCharacter(harness.character("Bob-R", 5, { 1 }))
        c.addon.Store.Prune({ ["Me-R"] = true }, "Me-R")
        local e = newest(c.addon, "sys")
        harness.equal(e.st, "warn"); harness.truthy(e.info:find("Bob-R", 1, true))
    end,

    ["name check: statuses for agreeing, normalized and broken name sources"] = function(harness)
        local saved = GetNormalizedRealmName
        GetNormalizedRealmName = function() return "Mirrormoor" end
        local ok, err = pcall(function()
            local addon = harness.addon()
            local D = addon.Diagnostics
            local function byMethod(rows)
                local m = {}
                for _, r in ipairs(rows) do m[r.method] = r end
                return m
            end
            local base = { unitName = "Thalia", normalizedRealm = "Mirrormoor", realmName = "Mirrormoor", rosterCount = 3,
                ambiguated = "Thalia" }
            -- all sources agree
            local info = {}
            for k, v in pairs(base) do info[k] = v end
            info.rosterMe = "Thalia-Mirrormoor"
            local rows = byMethod(D.IdentityRows({ identity = info, me = "Thalia-Mirrormoor", roster = { ["Thalia-Mirrormoor"] = true, ["Bob-Mirrormoor"] = true },
                echo = "Thalia-Mirrormoor", seen = { ["Bob-Mirrormoor"] = "Bob-Mirrormoor" } }))
            for _, r in pairs(rows) do harness.truthy(r.status == "ok" or r.status == "info", r.method .. " = " .. r.status) end
            -- roster and chat spell the realm with a space: normalized, not broken
            info.rosterMe = "Thalia-Mirror Moor"
            rows = byMethod(D.IdentityRows({ identity = info, me = "Thalia-Mirrormoor", roster = { ["Thalia-Mirrormoor"] = true, ["Bob-Mirrormoor"] = true },
                echo = "Thalia-Mirror Moor", seen = { ["Bob-Mirrormoor"] = "Bob-Mirror Moor" } }))
            harness.equal(rows["GetGuildRosterInfo (my entry)"].status, "fixed")
            harness.equal(rows["CHAT_MSG_ADDON sender (my own echo)"].status, "fixed")
            harness.equal(rows["CHAT_MSG_ADDON sender (others)"].status, "fixed")
            -- a sender whose normalized name is not in the roster, an empty realm, me missing from the roster: problems
            info.normalizedRealm = ""
            rows = byMethod(D.IdentityRows({ identity = info, me = "Thalia-Mirrormoor", roster = { ["Bob-Mirrormoor"] = true },
                seen = { ["Zed-Elsewhere"] = "Zed-Elsewhere" } }))
            harness.equal(rows["GetNormalizedRealmName()"].status, "bad")
            harness.equal(rows["guild roster contains me"].status, "bad")
            harness.equal(rows["CHAT_MSG_ADDON sender (others)"].status, "bad")
            harness.equal(rows["CHAT_MSG_ADDON sender (my own echo)"].status, "unknown")
            -- every row is printable
            for _, r in pairs(rows) do harness.truthy(D.FormatIdentityRow(r):find(r.method, 1, true)) end
        end)
        GetNormalizedRealmName = saved
        if not ok then error(err, 0) end
    end,

    ["export: the report holds identity, transport, records, orders and the trace"] = function(harness)
        local c = commNs(harness, "Me-R", { ["Me-R"] = true, ["Bob-R"] = true })
        c.addon.Store.PutCharacter(harness.character("Bob-R", 5, { 1, 2 }))
        c.addon.Offers.Put({ name = "Bob-R", rev = 3, items = {}, dibs = {} })
        c.addon.orders:Create("Bob-R", 77, 1, "")
        c.C.OnAddonMessage(c.addon.PREFIX, chunk(c.addon, { t = "HELLO", rev = 9 }), "GUILD", "Bob-R")
        local text = c.addon.Diagnostics.Report({ communication = c.C, identity = { unitName = "Me", normalizedRealm = "R", rosterSample = { "Me-R" } } })
        for _, needle in ipairs({ "--- identity ---", "me in cached roster: yes", "GetNormalizedRealmName: R", "--- transport ---",
            "Bob-R rev=5 level=60 professions=1 recipes=2", "Bob-R rev=3 items=0 dibs=0", "requester=Bob-R recipe=77",
            "pulled record of Bob-R (rev 9)", "<- GUILD Bob-R HELLO [ok]", "=== end of report ===" }) do
            harness.truthy(text:find(needle, 1, true), "report lacks: " .. needle)
        end
        -- no client needed and no identity table: still a report
        harness.truthy(c.addon.Diagnostics.Report():find("=== end of report ===", 1, true))
    end,
}
