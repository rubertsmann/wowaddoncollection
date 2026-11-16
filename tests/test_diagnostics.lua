-- Feature 008: sync diagnostics (network trace, decision reasons, identity checks, export report).

local function commNs(h, me, roster)
    local ns = h.ns()
    local out = { prints = {}, sent = {} }
    ns.Print = function(m) out.prints[#out.prints + 1] = m end
    ns.Store.db.me = me
    ns.Api = { GetPlayerInfo = function() return { name = me } end, GetGuildRoster = function() return roster or {} end,
        IsGuilded = function() return true end, RequestRoster = function() end }
    ns.orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
    local C = ns.Comm
    C.active = true
    C.roster = roster or {}
    C.sync = ns.Sync.New({
        send = function(msg, dist, target) out.sent[#out.sent + 1] = { msg = msg, dist = dist, target = target } end,
        now = function() return h.clock end, rand = function() return 0 end,
        store = ns.Store, orders = ns.orders, me = function() return ns.Store.db.me end, onChange = function() end,
    })
    out.ns, out.C = ns, C
    return out
end

local function chunk(ns, msg, id)
    return ns.Codec.Header(id or "a1", 1, 1) .. ns.Codec.Encode(msg)
end

local function newest(ns, filter) return ns.Trace.List(filter)[1] end

return {
    ["trace: ring is capped, newest first, problems filter"] = function(h)
        local ns = h.ns()
        for i = 1, ns.Trace.MAX + 25 do ns.Trace.Add({ dir = "out", mt = "HELLO", st = (i % 10 == 0) and "failed" or "sent" }) end
        h.eq(#ns.db.trace, ns.Trace.MAX)
        local list = ns.Trace.List()
        h.truthy(list[1].seq > list[2].seq, "newest first")
        for _, e in ipairs(ns.Trace.List("problems")) do h.eq(e.st, "failed") end
        h.eq(#ns.Trace.List("in"), 0)
        ns.Trace.Clear()
        h.eq(#ns.Trace.List(), 0)
    end,

    ["trace: persisted ring is sanitized on load (non-tables dropped, capped)"] = function(h)
        local ns = h.ns()
        local junk = { "x", 5, { dir = "in", st = "ok" } }
        for _ = 1, ns.Trace.MAX + 3 do junk[#junk + 1] = { dir = "sys", st = "info" } end
        ns.Store.Init({ schema = ns.Store.SCHEMA, trace = junk })
        h.eq(#ns.db.trace, ns.Trace.MAX)
        for _, e in ipairs(ns.db.trace) do h.eq(type(e), "table") end
        ns.Store.Init({ schema = ns.Store.SCHEMA, trace = "garbage" })
        h.eq(type(ns.db.trace), "table")
    end,

    ["trace: summaries name the payload without dumping it"] = function(h)
        local T = h.ns().Trace
        h.eq(T.Summarize({ t = "HELLO", rev = 5, orev = 7, odig = { a = 1, b = 2 }, login = true }), "rev=5 orev=7 odig=2 login")
        h.eq(T.Summarize({ t = "WANT", names = { "A-R" } }), "names=A-R")
        h.eq(T.Summarize({ t = "SNAP", char = h.char("A-R", 9, { 1, 2, 3 }), catalog = { [1] = {} } }), "char=A-R rev=9 recipes=3 catalog=1")
        h.eq(T.Summarize("junk"), "?")
        h.eq(T.RosterLookalikes("Bob-RealmA", { ["Bob-Realm A"] = true, ["Bobby-RealmA"] = true })[1], "Bob-Realm A")
        h.eq(T.RosterLookalikes("Bob-RealmA", { ["Bob-RealmA"] = true }), nil)
    end,

    ["sync: every handled message reports a decision"] = function(h)
        local c = commNs(h, "Me-R", {})
        local S = c.C.sync
        local st, why = S:OnMessage({ v = c.ns.PROTOCOL, t = "HELLO", rev = 50 }, "Peer-R")
        h.eq(st, "ok"); h.truthy(why:find("-> WANT", 1, true), why)
        st, why = S:OnMessage({ v = c.ns.PROTOCOL, t = "HELLO", rev = 50 }, "Peer-R")
        h.truthy(why:find("WANT pending (try 1", 1, true), why)
        st, why = S:OnMessage({ v = c.ns.PROTOCOL, t = "NOPE" }, "Peer-R")
        h.eq(st, "dropped")
        st, why = S:OnMessage({ v = c.ns.PROTOCOL, t = "HELLO", rev = 1 }, "Me-R")
        h.eq(why, "own echo")
        st, why = S:OnMessage({ v = c.ns.PROTOCOL + 1, t = "HELLO", rev = 1 }, "Peer-R")
        h.eq(st, "dropped")
    end,

    ["sync: a WANT for another form of my name is reported as a name mismatch"] = function(h)
        local c = commNs(h, "Me-RealmA", {})
        c.ns.Store.PutChar(h.char("Me-RealmA", 10, { 1 }))
        local st, why = c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "WANT", names = { "Me-OtherRealm" } }, "Peer-R")
        h.eq(st, "ignored"); h.truthy(why:find("name mismatch", 1, true), why)
        st, why = c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "WANT", names = { "Me-RealmA" } }, "Peer-R")
        h.eq(st, "ok"); h.eq(#c.C.sync.pending, 1)
        st, why = c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "WANTO", names = { "Me-OtherRealm" } }, "Peer-R")
        h.truthy(why:find("name mismatch", 1, true), why)
    end,

    ["sync: SNAP/OFFERS whose record name differs from the sender say so"] = function(h)
        local c = commNs(h, "Me-R", {})
        local st, why = c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "SNAP", char = h.char("Bob-X", 5, { 1 }), catalog = {} }, "Bob-R")
        h.eq(st, "error"); h.truthy(why:find("record Bob-X from Bob-R", 1, true), why)
        st, why = c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "SNAP", char = h.char("Bob-R", 5, { 1 }), catalog = {} }, "Bob-R")
        h.eq(st, "ok"); h.eq(why, "stored")
        st, why = c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "SNAP", char = h.char("Bob-R", 5, { 1 }), catalog = {} }, "Bob-R")
        h.eq(st, "ignored")
    end,

    ["sync: identity is read at use time (Comm may start before the character is known)"] = function(h)
        local c = commNs(h, "OldAlt-R", {})
        c.ns.Store.db.me = "Main-R"   -- PLAYER_LOGIN set the real character after Sync was created
        c.ns.Store.PutChar(h.char("Main-R", 10, { 1 }))
        local st = c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "WANT", names = { "Main-R" } }, "Peer-R")
        h.eq(st, "ok")
        h.eq(c.C.sync:_helloMsg(false).rev, 10)
    end,

    ["comm: Start refuses to run before PLAYER_LOGIN"] = function(h)
        local c = commNs(h, "Me-R", {})
        c.C.active, c.C.ready = false, false
        c.C.Start()
        h.eq(c.C.active, false)
    end,

    ["comm: inbound messages are traced with Sync's decision"] = function(h)
        local c = commNs(h, "Me-R", { ["Peer-R"] = true })
        c.C.OnAddonMessage(c.ns.PREFIX, chunk(c.ns, { t = "HELLO", rev = 7 }), "GUILD", "Peer-R")
        local e = newest(c.ns, "in")
        h.eq(e.mt, "HELLO"); h.eq(e.st, "ok"); h.eq(e.peer, "Peer-R"); h.truthy(e.why:find("WANT", 1, true))
        c.C.OnAddonMessage(c.ns.PREFIX, c.ns.Codec.Header("b2", 1, 1) .. "garbage", "GUILD", "Peer-R")
        e = newest(c.ns, "in")
        h.eq(e.st, "error"); h.truthy(e.why:find("decode", 1, true))
    end,

    ["comm: a whisper rejected by the gate names the roster's form of the sender"] = function(h)
        local c = commNs(h, "Me-R", { ["Bob-Other Realm"] = true })
        c.C.OnAddonMessage(c.ns.PREFIX, chunk(c.ns, { t = "WANT", names = { "Me-R" } }), "WHISPER", "Bob-OtherRealm")
        local e = newest(c.ns, "in")
        h.eq(e.st, "rejected"); h.truthy(e.why:find("Bob-Other Realm", 1, true), e.why)
        -- repeated chunks of the same rejection do not flood the trace
        c.C.OnAddonMessage(c.ns.PREFIX, chunk(c.ns, { t = "WANT", names = { "Me-R" } }, "a2"), "WHISPER", "Bob-OtherRealm")
        h.eq(#c.ns.Trace.List("in"), 1)
        local empty = commNs(h, "Me-R", {})
        empty.C.OnAddonMessage(empty.ns.PREFIX, chunk(empty.ns, { t = "WANT", names = { "Me-R" } }), "WHISPER", "Bob-R")
        h.truthy(newest(empty.ns, "in").why:find("before the guild roster loaded", 1, true))
    end,

    ["comm: outbound entries go queued -> sent, and failed with the result name"] = function(h)
        local c = commNs(h, "Me-R", {})
        local savedChat, savedAmb = C_ChatInfo, Ambiguate
        local code = 0
        C_ChatInfo = { SendAddonMessage = function() return code end }
        Ambiguate = nil
        local ok, err = pcall(function()
            c.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
            local e = newest(c.ns, "out")
            h.eq(e.st, "queued"); h.eq(e.parts, 1)
            c.C._pump(10)
            h.eq(e.st, "sent")
            code = 12
            c.C.Send({ t = "WANT", names = { "Bob-R" } }, "WHISPER", "Bob-R")
            c.C._pump(10)
            e = newest(c.ns, "out")
            h.eq(e.st, "failed"); h.eq(e.why, "TargetOffline")
            h.eq(c.C.sendFailures, 1)
            code = false
            c.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
            c.C._pump(10)
            h.eq(newest(c.ns, "out").st, "failed")
            code = true   -- classic-style boolean success
            c.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
            c.C._pump(10)
            h.eq(newest(c.ns, "out").st, "sent")
        end)
        C_ChatInfo, Ambiguate = savedChat, savedAmb
        if not ok then error(err, 0) end
    end,

    ["comm: an oversized message is traced as dropped instead of vanishing"] = function(h)
        local c = commNs(h, "Me-R", {})
        local big = {}
        for i = 1, 20000 do big[i] = tostring(math.random()) .. i end
        c.C.Send({ t = "SNAP", char = { name = "Me-R", junk = big } }, "WHISPER", "Bob-R")
        local e = newest(c.ns, "out")
        h.eq(e.st, "dropped"); h.truthy(e.why:find("too big", 1, true), e.why)
    end,

    ["identity: my name missing from the roster warns once and names the roster's form"] = function(h)
        local c = commNs(h, "Me-RealmA", { ["Me-Realm A"] = true, ["Bob-Realm A"] = true })
        h.eq(c.C.CheckIdentity(), false)
        h.eq(c.C.CheckIdentity(), false)
        h.eq(#c.prints, 1)
        local e = newest(c.ns, "sys")
        h.eq(e.st, "warn"); h.truthy(e.info:find("Me-Realm A", 1, true), e.info)
        local ok = commNs(h, "Me-R", { ["Me-R"] = true })
        h.eq(ok.C.CheckIdentity(), true); h.eq(#ok.prints, 0)
        h.eq(commNs(h, "Me-R", {}).C.CheckIdentity(), nil)   -- roster not loaded: no verdict
    end,

    ["identity: a roster prune that drops received records is traced"] = function(h)
        local c = commNs(h, "Me-R", {})
        c.ns.Store.PutChar(h.char("Bob-R", 5, { 1 }))
        c.ns.Store.Prune({ ["Me-R"] = true }, "Me-R")
        local e = newest(c.ns, "sys")
        h.eq(e.st, "warn"); h.truthy(e.info:find("Bob-R", 1, true))
    end,

    ["name check: statuses for agreeing, normalized and broken name sources"] = function(h)
        local saved = GetNormalizedRealmName
        GetNormalizedRealmName = function() return "Mirrormoor" end
        local ok, err = pcall(function()
            local ns = h.ns()
            local D = ns.Diag
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
            local rows = byMethod(D.IdentityRows({ info = info, me = "Thalia-Mirrormoor", roster = { ["Thalia-Mirrormoor"] = true, ["Bob-Mirrormoor"] = true },
                echo = "Thalia-Mirrormoor", seen = { ["Bob-Mirrormoor"] = "Bob-Mirrormoor" } }))
            for _, r in pairs(rows) do h.truthy(r.status == "ok" or r.status == "info", r.method .. " = " .. r.status) end
            -- roster and chat spell the realm with a space: normalized, not broken
            info.rosterMe = "Thalia-Mirror Moor"
            rows = byMethod(D.IdentityRows({ info = info, me = "Thalia-Mirrormoor", roster = { ["Thalia-Mirrormoor"] = true, ["Bob-Mirrormoor"] = true },
                echo = "Thalia-Mirror Moor", seen = { ["Bob-Mirrormoor"] = "Bob-Mirror Moor" } }))
            h.eq(rows["GetGuildRosterInfo (my entry)"].status, "fixed")
            h.eq(rows["CHAT_MSG_ADDON sender (my own echo)"].status, "fixed")
            h.eq(rows["CHAT_MSG_ADDON sender (others)"].status, "fixed")
            -- a sender whose normalized name is not in the roster, an empty realm, me missing from the roster: problems
            info.normalizedRealm = ""
            rows = byMethod(D.IdentityRows({ info = info, me = "Thalia-Mirrormoor", roster = { ["Bob-Mirrormoor"] = true },
                seen = { ["Zed-Elsewhere"] = "Zed-Elsewhere" } }))
            h.eq(rows["GetNormalizedRealmName()"].status, "bad")
            h.eq(rows["guild roster contains me"].status, "bad")
            h.eq(rows["CHAT_MSG_ADDON sender (others)"].status, "bad")
            h.eq(rows["CHAT_MSG_ADDON sender (my own echo)"].status, "unknown")
            -- every row is printable
            for _, r in pairs(rows) do h.truthy(D.FormatIdentityRow(r):find(r.method, 1, true)) end
        end)
        GetNormalizedRealmName = saved
        if not ok then error(err, 0) end
    end,

    ["export: the report holds identity, transport, records, orders and the trace"] = function(h)
        local c = commNs(h, "Me-R", { ["Me-R"] = true, ["Bob-R"] = true })
        c.ns.Store.PutChar(h.char("Bob-R", 5, { 1, 2 }))
        c.ns.Offers.Put({ name = "Bob-R", rev = 3, items = {}, dibs = {} })
        c.ns.orders:Create("Bob-R", 77, 1, "")
        c.C.OnAddonMessage(c.ns.PREFIX, chunk(c.ns, { t = "HELLO", rev = 9 }), "GUILD", "Bob-R")
        local text = c.ns.Diag.Report({ comm = c.C, identity = { unitName = "Me", normalizedRealm = "R", rosterSample = { "Me-R" } } })
        for _, needle in ipairs({ "--- identity ---", "me in cached roster: yes", "GetNormalizedRealmName: R", "--- transport ---",
            "Bob-R rev=5 level=60 professions=1 recipes=2", "Bob-R rev=3 items=0 dibs=0", "requester=Bob-R recipe=77",
            "pulled record of Bob-R (rev 9)", "<- GUILD Bob-R HELLO [ok]", "=== end of report ===" }) do
            h.truthy(text:find(needle, 1, true), "report lacks: " .. needle)
        end
        -- no client needed and no identity table: still a report
        h.truthy(c.ns.Diag.Report():find("=== end of report ===", 1, true))
    end,
}
