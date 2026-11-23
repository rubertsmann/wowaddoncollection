-- Messages for the developer: my record, validation, the developer-only pull, statuses, the bug snapshot, migration.
local BIG = 1700000000

local function fresh(harness, me)
    local addon = harness.addon({ now = BIG })
    addon.Store.db.me = me or "Me-R"
    -- a made-up developer: no real names in the repository
    addon.Model.BUILD_VIEWER_HASHES = { [addon.Model.NameHash("test developer")] = true }
    return addon
end

local function peer(harness, bus, name, seed)
    local addon = fresh(harness, name)
    local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    local rng = seed
    local p = { name = name, addon = addon, changes = {} }
    p.sync = addon.Sync.New({
        send = function(msg, dist, target) bus.queue[#bus.queue + 1] = { from = name, msg = msg, dist = dist, target = target } end,
        now = function() return harness.clock end,
        random = function() rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648 end,
        store = addon.Store, orders = orders, me = name,
        onChange = function(kind) p.changes[#p.changes + 1] = kind end,
    })
    bus.peers[name] = p
    return p
end

local function pump(bus)
    local guard = 0
    while #bus.queue > 0 and guard < 2000 do
        guard = guard + 1
        local it = table.remove(bus.queue, 1)
        bus.sent[#bus.sent + 1] = it
        local wire = bus.peers[it.from].addon.Codec.Encode(it.msg)
        for name, p in pairs(bus.peers) do
            local to = (it.dist == "GUILD" and name ~= it.from) or (it.dist == "WHISPER" and name == it.target)
            if to then p.sync:OnMessage(assert(p.addon.Codec.Decode(wire)), it.from) end
        end
    end
end

local function advance(harness, bus, seconds)
    for _ = 1, seconds do
        harness.clock = harness.clock + 1
        for _, p in pairs(bus.peers) do p.sync:Tick(harness.clock) end
        pump(bus)
    end
end

local function countSent(b, messageType)
    local n = 0
    for _, it in ipairs(b.sent) do if it.msg.t == messageType then n = n + 1 end end
    return n
end

return {
    ["feedback: protocol 2.5 and schema 7 are pinned"] = function(harness)
        local addon = fresh(harness)
        harness.equal(addon.PROTOCOL_MINOR, 5); harness.equal(addon.Store.SCHEMA, 7)
    end,

    ["feedback: Add cleans the text, refuses empty/duplicate/unknown type, keeps the newest 10, rev grows"] = function(harness)
        local addon = fresh(harness)
        local Feedback = addon.Feedback
        harness.equal(select(2, Feedback.Add("Me-R", "wish", "x", BIG)), "type")
        harness.equal(select(2, Feedback.Add("Me-R", "bug", "  \n ", BIG)), "empty")
        harness.truthy(Feedback.Add("Me-R", "bug", "line one\nline two\1", BIG))
        local record = Feedback.Get("Me-R")
        harness.equal(record.items[1].text, "line one / line two")
        harness.equal(select(2, Feedback.Add("Me-R", "bug", "line one\nline two", BIG)), "duplicate")
        local previousRevision = record.rev
        for index = 1, 12 do harness.truthy(Feedback.Add("Me-R", "feature", "idea " .. index, BIG)) end
        record = Feedback.Get("Me-R")
        harness.equal(#record.items, 10); harness.equal(record.items[10].text, "idea 12"); harness.equal(record.items[1].text, "idea 3")
        harness.truthy(record.rev > previousRevision)
        local times = {}
        for _, item in ipairs(record.items) do harness.truthy(not times[item.t], "unique send times"); times[item.t] = true end
        harness.truthy(Feedback.Add("Me-R", "feedback", string.rep("\195\164", 400), BIG))   -- 800 bytes of "ä"
        local long = Feedback.Get("Me-R").items[10].text
        harness.truthy(#long <= Feedback.MAXIMUM_TEXT_BYTES and addon.Utility.IsValidUtf8(long), "cut on a character border")
        harness.truthy(Feedback.Sanitize(Feedback.Get("Me-R")), "my own record passes the peer check")
    end,

    ["feedback: only the 3 newest messages keep a snapshot"] = function(harness)
        local addon = fresh(harness)
        local Feedback = addon.Feedback
        for index = 1, 5 do Feedback.Add("Me-R", "bug", "bug " .. index, BIG, "log " .. index) end
        local withLog = {}
        for _, item in ipairs(Feedback.Get("Me-R").items) do if item.log then withLog[#withLog + 1] = item.log end end
        harness.equal(table.concat(withLog, ","), "log 3,log 4,log 5")
    end,

    ["feedback: hostile records are dropped whole"] = function(harness)
        local addon = fresh(harness)
        local Sanitize = addon.Feedback.Sanitize
        local function record(items) return { name = "A-R", rev = BIG, items = items } end
        harness.truthy(Sanitize(record({ { t = BIG, k = "bug", text = "ok |T icon|t" } })), "a bar is fine (escaped on display)")
        local tooMany = {}
        for index = 1, 11 do tooMany[index] = { t = BIG - index, k = "bug", text = "x" } end
        for label, bad in pairs({
            tooMany = record(tooMany),
            longText = record({ { t = BIG, k = "bug", text = string.rep("a", 301) } }),
            badType = record({ { t = BIG, k = "rant", text = "x" } }),
            control = record({ { t = BIG, k = "bug", text = "a\nb" } }),
            notUtf8 = record({ { t = BIG, k = "bug", text = "\255\254" } }),
            sameTime = record({ { t = BIG, k = "bug", text = "x" }, { t = BIG, k = "bug", text = "y" } }),
            future = record({ { t = BIG * 2, k = "bug", text = "x" } }),
            longLog = record({ { t = BIG, k = "bug", text = "x", log = string.rep("a", 1201) } }),
            badLog = record({ { t = BIG, k = "bug", text = "x", log = "a\1b" } }),
            fourLogs = record({ { t = 1, k = "bug", text = "x", log = "l" }, { t = 2, k = "bug", text = "x", log = "l" },
                { t = 3, k = "bug", text = "x", log = "l" }, { t = 4, k = "bug", text = "x", log = "l" } }),
            holes = record({ [1] = { t = 1, k = "bug", text = "x" }, [3] = { t = 3, k = "bug", text = "x" } }),
            badName = { name = "A|r", rev = BIG, items = {} },
            notTable = { name = "A-R", rev = BIG, items = "x" },
        }) do
            harness.equal(Sanitize(bad), nil, label)
        end
        local clean = Sanitize(record({ { t = BIG, k = "bug", text = "x", log = "line 1\nline 2", extra = "dropped" } }))
        harness.equal(clean.items[1].extra, nil); harness.equal(clean.items[1].log, "line 1\nline 2")
    end,

    ["feedback: a member's record reaches the developer only; other members never pull or store it"] = function(harness)
        local b = { peers = {}, queue = {}, sent = {} }
        harness.clock = BIG
        local sender = peer(harness, b, "Sender-R", 7)
        local developer = peer(harness, b, "Test Developer-R", 11)
        local bystander = peer(harness, b, "Bystander-R", 13)
        harness.truthy(developer.addon.Feedback.IsReader("Test Developer-R"))
        harness.truthy(not bystander.addon.Feedback.IsReader("Bystander-R"))
        sender.addon.Feedback.Add("Sender-R", "bug", "the button is broken", BIG, "v1 protocol 2.5")
        sender.sync:Hello(false); pump(b); advance(harness, b, 5)
        local developerRows = developer.addon.Feedback.List()
        harness.equal(#developerRows, 1); harness.equal(developerRows[1].owner, "Sender-R")
        harness.equal(developerRows[1].log, "v1 protocol 2.5")
        harness.equal(bystander.addon.Feedback.Get("Sender-R"), nil)
        harness.equal(countSent(b, "WANTF"), 1, "only the developer asked")
        -- a record broadcast on GUILD (a pull retry answered there) reaches the bystander: not stored
        local record = sender.addon.Feedback.Get("Sender-R")
        bystander.sync:OnMessage({ v = 2, t = "FEEDBACK", feedback = record }, "Sender-R")
        harness.equal(bystander.addon.Feedback.Get("Sender-R"), nil)
        -- the sender sees its message as delivered (the developer's client asked for it); a new one waits
        local summary = sender.addon.Feedback.MySummary("Sender-R")
        harness.equal(summary.sent, 1); harness.equal(summary.delivered, 1); harness.equal(summary.waiting, 0)
        harness.clock = harness.clock + 5
        sender.addon.Feedback.Add("Sender-R", "feature", "one more", harness.clock)
        summary = sender.addon.Feedback.MySummary("Sender-R")
        harness.equal(summary.waiting, 1); harness.equal(summary.rows[1].text, "one more"); harness.equal(summary.rows[1].delivered, false)
        sender.sync:Hello(false); pump(b); advance(harness, b, 5)
        harness.equal(sender.addon.Feedback.MySummary("Sender-R").delivered, 2)
        harness.equal(#developer.addon.Feedback.List(), 2)
        -- the developer's own HELLO announces nothing when it has sent no feedback
        harness.equal(developer.sync:_helloMessage(false).frev, nil)
        harness.equal(sender.sync:_helloMessage(false).frev, sender.addon.Feedback.Get("Sender-R").rev)
    end,

    ["feedback: statuses toggle, survive a reload, and stay with their message"] = function(harness)
        local addon = fresh(harness, "Test Developer-R")
        local Feedback = addon.Feedback
        harness.truthy(Feedback.Put({ name = "A-R", rev = BIG, items = { { t = BIG - 10, k = "feature", text = "older" },
            { t = BIG - 5, k = "bug", text = "newer" } } }, "Test Developer-R"))
        local rows = Feedback.List()
        harness.equal(rows[1].text, "newer")
        harness.equal(Feedback.SetStatus(rows[1].key, "fixed"), "fixed")
        harness.equal(Feedback.SetStatus(rows[1].key, "fixed"), nil, "the same status again clears it")
        Feedback.SetStatus(rows[2].key, "declined")
        harness.equal(Feedback.List()[2].status, "declined")
        local saved = addon.Utility.DeepCopy(addon.Store.db)
        saved.feedbackState["bogus"] = "maybe"
        saved.feedbackDelivered = { [BIG] = true, bad = true, [-1] = true }
        local reloaded = fresh(harness, "Test Developer-R")
        reloaded.Store.Init(saved)
        harness.equal(reloaded.Feedback.List()[2].status, "declined")
        harness.equal(reloaded.Store.db.feedbackState.bogus, nil)
        harness.equal(reloaded.Store.db.feedbackDelivered[BIG], true)
        harness.equal(reloaded.Store.db.feedbackDelivered.bad, nil); harness.equal(reloaded.Store.db.feedbackDelivered[-1], nil)
    end,

    ["feedback: a non-reader keeps only its own record"] = function(harness)
        local addon = fresh(harness, "Me-R")
        harness.equal(addon.Feedback.Put({ name = "A-R", rev = BIG, items = {} }, "Me-R"), false)
        harness.equal(addon.Feedback.Put({ name = "Me-R", rev = BIG, items = {} }, "Me-R"), true)
    end,

    ["feedback: snapshot keeps versions, the newest problems and recent lines within 1200 bytes"] = function(harness)
        local addon = fresh(harness)
        local logLines = {}
        for index = 1, 40 do
            local level = index % 10 == 0 and "ERROR" or (index % 7 == 0 and "WARNING" or "DEBUG")
            logLines[index] = ("2026-11-23 10:%02d %s [area] line %d %s"):format(index, level, index, string.rep("x", 60))
        end
        local snapshot = addon.Feedback.Snapshot({ version = "1.3.0", protocol = "2.5", schema = 7, locale = "deDE",
            client = "1.60.1", sync = "active=true queue=0", logLines = logLines })
        harness.truthy(#snapshot <= addon.Feedback.MAXIMUM_LOG_BYTES)
        harness.truthy(snapshot:find("^v1%.3%.0 protocol 2%.5 schema 7 locale deDE client 1%.60%.1\n"))
        harness.truthy(snapshot:find("active=true queue=0", 1, true))
        harness.truthy(snapshot:find("line 40 ", 1, true), "newest error")
        harness.truthy(snapshot:find("line 39 ", 1, true), "recent line")
        harness.truthy(not snapshot:find("line 5 ", 1, true), "old debug line left out")
        harness.truthy(addon.Feedback.Sanitize({ name = "A-R", rev = BIG, items = { { t = BIG, k = "bug", text = "x", log = snapshot } } }),
            "a snapshot passes the peer check")
        local huge = {}
        for index = 1, 30 do huge[index] = "2026 ERROR [a] " .. string.rep("\195\164", 200) end
        local cut = addon.Feedback.Snapshot({ logLines = huge })
        harness.truthy(#cut <= 1200 and addon.Utility.IsValidUtf8(cut))
    end,

    ["feedback: the developer is found in a roster in any name form, never in an empty or missing one"] = function(harness)
        local addon = fresh(harness)
        local ReaderInRoster = addon.Feedback.ReaderInRoster
        harness.equal(ReaderInRoster({ ["A-R"] = true, ["Test Developer-Other Realm"] = true }), true)
        harness.equal(ReaderInRoster({ ["Test Developer"] = true }), true)
        harness.equal(ReaderInRoster({ ["Test Developers"] = true, ["A-R"] = true }), false)
        harness.equal(ReaderInRoster({}), false); harness.equal(ReaderInRoster(nil), false)
    end,

    ["feedback: migration 6 -> 7 adds the tables and keeps everything"] = function(harness)
        local addon = fresh(harness)
        local sv = { schema = 6, chars = {}, catalog = {}, orders = {}, offers = {}, hidden = {}, ui = {}, me = "Me-R",
            access = { ["A-R"] = { name = "A-R", rev = BIG - 5, keys = { [7146] = { bag = true } }, att = {} } } }
        local out, status = addon.Store.Init(sv)
        harness.equal(status, "migrated"); harness.equal(out.schema, 7)
        harness.truthy(out.access["A-R"]); harness.equal(type(out.feedback), "table"); harness.equal(type(out.feedbackState), "table")
    end,
}
