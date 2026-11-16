-- Feature 006: hardening and version compatibility. Adversarial cases RF1-RF7 (features/006-*/spec.md).

local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a"); f:close()
    return s
end

-- a namespace with Comm wired to a recording Sync, as in the game after Comm.Start()
local function commNs(h, me, roster, now)
    local ns = h.ns({ now = now })
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
        store = ns.Store, orders = ns.orders, me = me, onChange = function() end,
    })
    out.ns, out.C = ns, C
    return out
end

local function chunk(ns, msg, id)
    return ns.Codec.Header(id or "a1", 1, 1) .. ns.Codec.Encode(msg)
end

local function bufferCount(C)
    local n = 0
    for _ in pairs(C.buffers) do n = n + 1 end
    return n
end

return {
    ---------------------------------------------------------------- helpers (T1)
    ["util: finite numbers, bounded integers, clean strings, names and escaping"] = function(h)
        local U = h.ns().Util
        h.eq(U.IsFinite(1), true); h.eq(U.IsFinite(math.huge), false); h.eq(U.IsFinite(-math.huge), false)
        h.eq(U.IsFinite(0 / 0), false); h.eq(U.IsFinite("1"), false); h.eq(U.IsFinite(nil), false)
        h.eq(U.SafeInt(5, 1, 10), 5); h.eq(U.SafeInt(0, 1, 10), nil); h.eq(U.SafeInt(11, 1, 10), nil)
        h.eq(U.SafeInt(1.5, 1, 10), nil); h.eq(U.SafeInt(math.huge, 1, nil), nil); h.eq(U.SafeInt("5", 1, 10), nil)
        h.eq(U.CleanString("Kürschnerei", 20), "Kürschnerei"); h.eq(U.CleanString("a\nb", 20), nil)
        h.eq(U.CleanString("a\0b", 20), nil); h.eq(U.CleanString("x\128", 20), nil); h.eq(U.CleanString("toolong", 3), nil)
        h.eq(U.CleanString({}, 5), nil)
        h.eq(U.IsSafeName("Bob-Area52"), true); h.eq(U.IsSafeName("Bo|b"), false); h.eq(U.IsSafeName(""), false)
        h.eq(U.IsSafeName(string.rep("x", 65)), false); h.eq(U.IsSafeName("a\tb"), false)
        h.eq(U.StripControl("a\1b\127c\0d"), "abcd")
        h.eq(U.Esc("|cffff0000red|r"), "||cffff0000red||r"); h.eq(U.Esc(5), "5")
    end,

    ["util: the debug log escapes peer text, because /ts debug prints it to the chat frame"] = function(h)
        local ns = h.ns()
        ns.Debug.Log("comm.decode", "|cffff0000Evil-R", "|Hitem:1|h")
        local line = ns.db.debug[#ns.db.debug]
        h.truthy(line:find("||cffff0000Evil-R", 1, true), line)
        h.truthy(not line:find("[^|]|[^|]"), "unescaped | in: " .. line)
    end,

    ["codec: the parser rejects non-finite numbers that tonumber() would accept (RF3)"] = function(h)
        local ns = h.ns()
        for _, raw in ipairs({ "{s1:an1e999;}", "{s1:an-1e999;}", "{s1:ann;}", "n1e400;" }) do
            local t, err = ns.Codec.Deserialize(raw)
            h.eq(t, nil, "accepted " .. raw)
            h.truthy(err)
        end
        h.truthy(ns.Codec.Deserialize("{s1:an1.5;}"))
    end,

    ---------------------------------------------------------------- header / compat / limits (T2)
    ["codec: chunk header round-trips and carries major.minor"] = function(h)
        local ns = h.ns()
        local text = ns.Codec.Header("3fa2", 2, 5) .. "payload|with|bars"
        h.truthy(text:find("^2%.0|3fa2|2|5|"))
        local p = assert(ns.Codec.ParseHeader(text))
        h.eq(p.major, 2); h.eq(p.minor, 0); h.eq(p.id, "3fa2"); h.eq(p.idx, 2); h.eq(p.total, 5); h.eq(p.part, "payload|with|bars")
    end,

    ["codec: malformed headers are rejected, legacy 0.1/0.2 headers are recognised, foreign majors only expose the version"] = function(h)
        local ns = h.ns()
        for _, bad in ipairs({ "", "garbage", "2.0|", "2.0|zz|1|1|x", "2.0|a|0|1|x", "2.0|a|2|1|x", "2.0|a|1|0|x",
            "2.0|a|1|201|x", "2.0|a|1|99999|x", "2.0|" .. string.rep("a", 13) .. "|1|1|x", "1234.0|a|1|1|x" }) do
            h.eq((ns.Codec.ParseHeader(bad)), nil, "accepted: " .. bad)
        end
        local _, why = ns.Codec.ParseHeader("3fa|1|2|abc")   -- the 0.1/0.2 layout
        h.eq(why, "legacy")
        local f = assert(ns.Codec.ParseHeader("3.7|anything we cannot know|"))
        h.eq(f.major, 3); h.eq(f.minor, 7); h.eq(f.id, nil)
        h.eq((ns.Codec.ParseHeader(nil)), nil)
    end,

    ["codec: compatibility rule: major must match, minor may differ"] = function(h)
        local ns = h.ns()
        h.eq(ns.Codec.Compat(2, 0), "ok"); h.eq(ns.Codec.Compat(ns.PROTO_MAJOR, 0), "ok")
        h.eq(ns.Codec.Compat(ns.PROTO_MAJOR, ns.PROTO_MINOR + 1), "newer-minor")
        h.eq(ns.Codec.Compat(ns.PROTO_MAJOR + 1, 0), "newer"); h.eq(ns.Codec.Compat(ns.PROTO_MAJOR - 1, 9), "older")
    end,

    ["codec: transport limits are defined once and Decode accepts what the transport can deliver"] = function(h)
        local ns = h.ns()
        h.eq(ns.Codec.MAX_ENCODED, ns.Codec.CHUNK * ns.Codec.MAX_PARTS)
        h.truthy(ns.Codec.CHUNK + 30 <= 255, "header + payload must fit one addon message")
        h.eq((ns.Codec.Decode(string.rep("x", ns.Codec.MAX_ENCODED + 1))), nil)
        local comm = slurp("Core/Comm.lua")
        h.truthy(not comm:find("local CHUNK = %d"), "Comm must not define its own CHUNK")
        h.truthy(not comm:find("local MAX_PARTS = %d"), "Comm must not define its own MAX_PARTS")
    end,

    ["guard: only GUILD, or WHISPER from a roster member, is accepted; everything else fails closed"] = function(h)
        local G = h.ns().Guard
        local roster = { ["Bob-R"] = true }
        h.eq((G.Accept("GUILD", "Anyone-R", roster)), true)
        h.eq((G.Accept("GUILD", "Anyone-R", nil)), true)
        h.eq((G.Accept("WHISPER", "Bob-R", roster)), true)
        h.eq((G.Accept("WHISPER", "Stranger-R", roster)), false)
        h.eq((G.Accept("WHISPER", "Bob-R", {})), false)       -- roster not loaded yet: fail closed
        h.eq((G.Accept("WHISPER", "Bob-R", nil)), false)
        for _, ch in ipairs({ "PARTY", "RAID", "SAY", "YELL", "CHANNEL", "INSTANCE_CHAT", "OFFICER", "", "guild" }) do
            h.eq((G.Accept(ch, "Bob-R", roster)), false, ch)
        end
        h.eq((G.Accept(nil, "Bob-R", roster)), false)
        h.eq((G.Accept("GUILD", nil, roster)), false); h.eq((G.Accept("GUILD", "", roster)), false)
    end,

    ["guard: one notice per kind and a bounded record of who was seen"] = function(h)
        local G = h.ns().Guard
        local hints = G.NewHints()
        h.eq(G.Note(hints, "newer", "A-R"), true)
        h.eq(G.Note(hints, "newer", "B-R"), false)
        h.eq(G.Note(hints, "older", "B-R"), true)
        for i = 1, G.MAX_SEEN + 50 do G.Note(hints, "older", "P" .. i) end
        h.truthy(hints.count <= G.MAX_SEEN, "seen record grew unbounded: " .. hints.count)
    end,

    ---------------------------------------------------------------- Comm gate and versions (RF1, RF2, RF7)
    ["comm: a WHISPER from a non-guild character is dropped before anything is buffered or answered (RF1)"] = function(h)
        local c = commNs(h, "Me-R", { ["Bob-R"] = true })
        c.ns.Store.PutChar(h.char("Me-R", 50, { 1 }))
        local want = chunk(c.ns, { t = "WANT", names = { "Me-R" } })
        c.C.OnAddonMessage("TShare", want, "WHISPER", "Stranger-R")
        h.eq(bufferCount(c.C), 0); h.eq(c.C.sync.stats.received, 0); h.eq(#c.C.sync.pending, 0)
        h.eq(c.C.rejected, 1)
        c.C.OnAddonMessage("TShare", want, "WHISPER", "Bob-R")       -- a roster member is served
        h.eq(c.C.sync.stats.received, 1); h.eq(#c.C.sync.pending, 1)
    end,

    ["comm: foreign channels and a missing roster are rejected; GUILD is accepted"] = function(h)
        local c = commNs(h, "Me-R", {})
        local hello = chunk(c.ns, { t = "HELLO", rev = 0 })
        for _, ch in ipairs({ "PARTY", "RAID", "SAY", "CHANNEL", "WHISPER" }) do c.C.OnAddonMessage("TShare", hello, ch, "Bob-R") end
        h.eq(c.C.sync.stats.received, 0)
        c.C.OnAddonMessage("TShare", hello, "GUILD", "Bob-R")
        h.eq(c.C.sync.stats.received, 1)
        c.C.OnAddonMessage("Other", hello, "GUILD", "Bob-R")         -- not our prefix
        c.C.OnAddonMessage("TShare", hello, "GUILD", "Me-R")         -- own echo
        h.eq(c.C.sync.stats.received, 1)
    end,

    ["comm: a newer major or a legacy header creates no buffer and prints ONE hint per kind (RF2)"] = function(h)
        local c = commNs(h, "Me-R", {})
        local newer = "3.0|aa|1|1|" .. string.rep("x", 40)
        c.C.OnAddonMessage("TShare", newer, "GUILD", "A-R")
        c.C.OnAddonMessage("TShare", newer, "GUILD", "B-R")
        h.eq(#c.prints, 1); h.truthy(c.prints[1]:lower():find("newer", 1, true), c.prints[1])
        c.C.OnAddonMessage("TShare", "3fa|1|1|legacypayload", "GUILD", "C-R")
        c.C.OnAddonMessage("TShare", "3fa|1|1|legacypayload", "GUILD", "D-R")
        h.eq(#c.prints, 2); h.truthy(c.prints[2]:lower():find("older", 1, true), c.prints[2])
        h.eq(bufferCount(c.C), 0); h.eq(c.C.sync.stats.received, 0); h.eq(c.C.hints.count, 4)
        c.C.OnAddonMessage("TShare", "total garbage", "GUILD", "E-R")   -- malformed: silently ignored, no hint
        h.eq(#c.prints, 2)
    end,

    ["comm: a newer MINOR is processed and noted; an older minor is processed silently (RF7)"] = function(h)
        local c = commNs(h, "Me-R", {})
        local enc = c.ns.Codec.Encode({ t = "HELLO", rev = 0 })
        c.C.OnAddonMessage("TShare", "2.9|a1|1|1|" .. enc, "GUILD", "A-R")
        h.eq(c.C.sync.stats.received, 1); h.eq(#c.prints, 1)
        c.C.OnAddonMessage("TShare", "2.0|a2|1|1|" .. enc, "GUILD", "B-R")
        h.eq(c.C.sync.stats.received, 2); h.eq(#c.prints, 1)
    end,

    ["comm: two clients on different minors sync; different majors do not (RF7)"] = function(h)
        local function pair(minorB, majorB)
            local a, b = commNs(h, "A-R", {}), commNs(h, "B-R", {})
            b.ns.PROTO_MINOR, b.ns.PROTO_MAJOR, b.ns.PROTOCOL = minorB, majorB, majorB
            a.ns.Store.PutChar(h.char("A-R", 50, { 1 }))
            a.C.Send({ t = "HELLO", rev = 50 }, "GUILD")
            b.C.Send({ t = "HELLO", rev = 0 }, "GUILD")
            for _, item in ipairs(a.C.queue) do b.C.OnAddonMessage("TShare", item.text, "GUILD", "A-R") end
            for _, item in ipairs(b.C.queue) do a.C.OnAddonMessage("TShare", item.text, "GUILD", "B-R") end
            return a, b
        end
        local a, b = pair(3, 2)                                  -- B has extra (additive) features
        h.eq(a.C.sync.stats.received, 1); h.eq(b.C.sync.stats.received, 1)
        local a2, b2 = pair(0, 3)                                -- B speaks a different major
        h.eq(a2.C.sync.stats.received, 0); h.eq(b2.C.sync.stats.received, 0)
        h.eq(#a2.prints, 1); h.eq(#b2.prints, 1)                 -- both sides are told
    end,

    ["comm: message ids start with the per-session salt, so a reload cannot reuse an id (V6)"] = function(h)
        local c1, c2 = commNs(h, "A-R", {}), commNs(h, "A-R", {})
        c1.C.salt, c2.C.salt = 0x1234, 0x5678
        c1.C.Send({ t = "HELLO", rev = 1 }, "GUILD"); c2.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
        local id1 = c1.ns.Codec.ParseHeader(c1.C.queue[1].text).id
        local id2 = c2.ns.Codec.ParseHeader(c2.C.queue[1].text).id
        h.truthy(id1:find("^1234"), id1); h.truthy(id2:find("^5678"), id2); h.truthy(id1 ~= id2)
        h.truthy(#id1 <= 12)
    end,

    ["comm: every chunk fits one addon message"] = function(h)
        local c = commNs(h, "A-R", {})
        local big = {}
        for i = 1, 4000 do big[i] = math.random(1, 1e9) end    -- incompressible-ish payload
        c.C.Send({ t = "OPUSH", orders = { { id = table.concat(big, ",") } } }, "WHISPER", "B-R")
        h.truthy(#c.C.queue > 1)
        for _, item in ipairs(c.C.queue) do h.truthy(#item.text <= 255, "chunk of " .. #item.text .. " bytes") end
    end,

    ---------------------------------------------------------------- numeric bounds (RF3, R6)
    ["sync: HELLO with a non-finite, negative or future rev is dropped and triggers no pull (RF3)"] = function(h)
        local c = commNs(h, "Me-R", { ["Bob-R"] = true }, 1.8e9)   -- a realistic server time: "future" is judged against it
        local sync = c.C.sync
        for _, rev in ipairs({ 2 ^ 60, -5, 1e15, h.clock + 86400 + 1 }) do
            sync:OnMessage({ v = c.ns.PROTOCOL, t = "HELLO", rev = rev }, "Bob-R")
        end
        h.eq(sync.stats.dropped, 4); h.eq(#c.sent, 0)
        sync:OnMessage({ v = c.ns.PROTOCOL, t = "HELLO", rev = h.clock + 10 }, "Bob-R")   -- small clock skew is fine
        h.eq(sync.stats.dropped, 4); h.eq(#c.sent, 1); h.eq(c.sent[1].msg.t, "WANT")
    end,

    ["orders: far-future or negative timestamps and unsafe names are rejected, so they cannot win merges or evade pruning (RF3)"] = function(h)
        local ns = h.ns({ now = 1.8e9 })
        local o = ns.Orders.New(function() return h.clock end, {})
        local base = function() return { id = "Bob-R:1:1", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, claims = {} } end
        h.truthy(o:Merge(base()))
        local function rejected(mut) local x = base(); x.id = "X" .. math.random(1e9); mut(x); return o:Merge(x) == false end
        h.truthy(rejected(function(x) x.createdAt = 1e15 end))
        h.truthy(rejected(function(x) x.createdAt = -1 end))
        h.truthy(rejected(function(x) x.createdAt = 2 ^ 60 end))
        h.truthy(rejected(function(x) x.closed, x.closedAt = "cancelled", -1e18 end))
        h.truthy(rejected(function(x) x.closed, x.closedAt = "done", 1e15 end))
        h.truthy(rejected(function(x) x.claims = { ["A-R"] = { state = "claimed", t = 1e15 } } end))
        h.truthy(rejected(function(x) x.claims = { ["A|cffff0000-R"] = { state = "claimed", t = 1 } } end))
        h.truthy(rejected(function(x) x.requester = "Bob|cffff0000" end))
        h.truthy(rejected(function(x) x.requester = {} end))
        h.truthy(rejected(function(x) x.closedBy = {} end))
        h.truthy(rejected(function(x) x.recipeID = 1e15 end))
        h.truthy(rejected(function(x) x.recipeID = 0 end))
        -- an attack on an EXISTING order: a tiny closedAt would have won every merge forever
        local cancel = base(); cancel.closed, cancel.closedAt = "cancelled", -1e18
        h.eq(o:Merge(cancel), false); h.eq(o:Get("Bob-R:1:1").closed, nil)
    end,

    ["orders: control characters are stripped from notes; the note stays UTF-8"] = function(h)
        local ns = h.ns()
        local o = ns.Orders.New(function() return h.clock end, {})
        local ord = { id = "Bob-R:1:2", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, claims = {}, note = "a\nb\0c" }
        h.truthy(o:Merge(ord)); h.eq(o:Get("Bob-R:1:2").note, "abc")
        ord.id, ord.note = "Bob-R:1:3", "x\255y"
        h.eq(o:Merge(ord), false)
    end,

    ---------------------------------------------------------------- strict sanitizing (RF4, R7, R8)
    ["sync: SNAP stores a clean copy: unknown keys are dropped, extra catalog ids are refused, bad entries never stored (RF4)"] = function(h)
        local c = commNs(h, "Me-R", { ["Bob-R"] = true })
        local char = h.char("Bob-R", 50, { 1 })
        char.evil, char.professions.Cooking.evil, char.professions.Cooking.recipes[1] = { 1, 2, 3 }, "x", true
        local good = { name = "Roast Boar", reagents = { { itemID = 10, count = 2 } }, evil = "x", icon = 133 }
        c.C.sync:OnMessage({ v = c.ns.PROTOCOL, t = "SNAP", char = char, catalog = {
            [1] = good,
            [2] = { name = "Not Bobs Recipe", reagents = {} },                          -- Bob does not know recipe 2
        } }, "Bob-R")
        local stored = c.ns.Store.GetChar("Bob-R")
        h.truthy(stored); h.eq(stored.evil, nil); h.eq(stored.professions.Cooking.evil, nil)
        h.eq(c.ns.Store.GetRecipe(1).name, "Roast Boar"); h.eq(c.ns.Store.GetRecipe(1).evil, nil)
        h.eq(c.ns.Store.GetRecipe(2), nil)
    end,

    ["store: catalog entries with hostile or wrongly typed fields are rejected (RF4)"] = function(h)
        local S = h.ns().Store
        local function entry(mut) local e = { name = "X", reagents = { { itemID = 1, count = 1, name = "R" } } }; mut(e); return e end
        local bad = {
            entry(function(e) e.reagents[1].name = {} end), entry(function(e) e.reagents[1].name = 5 end),
            entry(function(e) e.reagents[1].name = "a|cffff0000b" end), entry(function(e) e.icon = {} end),
            entry(function(e) e.icon = "../../etc/passwd:x" end), entry(function(e) e.icon = 2 ^ 60 end),
            entry(function(e) e.produces = "1" end), entry(function(e) e.produces = {} end),
            entry(function(e) e.name = "a|Hitem:1|h[x]|h" end), entry(function(e) e.name = string.rep("x", 101) end),
            entry(function(e) e.reagents[1].itemID = 1e15 end), entry(function(e) e.reagents[1].itemID = "item:1|h" end),
            entry(function(e) e.reagents[1].count = 0 end), entry(function(e) e.reagents[1].count = 1e9 end),
            entry(function(e) e.minSkill = {} end), entry(function(e) e.loc = "|cffff0000" end),
            entry(function(e) e.reagents = string.rep("x", 10) end),
        }
        for i, e in ipairs(bad) do h.eq(S.ValidateCatalogEntry(e), false, "entry " .. i .. " accepted") end
        local many = {}
        for i = 1, 13 do many[i] = { itemID = i, count = 1 } end
        h.eq(S.ValidateCatalogEntry({ name = "X", reagents = many }), false)
        h.eq(S.ValidateCatalogEntry({ name = "Kürschnerei", loc = "deDE", icon = 133, produces = 5, reagents = {} }), true)
        h.eq(S.ValidateCatalogEntry({ name = "X", icon = "Interface\\Icons\\INV_Misc_Food_01", reagents = {} }), true)
        -- PutCatalog stores nothing but clean copies, and a bad entry does not block a later good one
        S.PutCatalog({ [7] = { name = "X", reagents = { { itemID = 1, count = 1, name = {} } } } })
        h.eq(S.GetRecipe(7), nil)
        S.PutCatalog({ [7] = { name = "X", reagents = {} }, [-3] = { name = "neg", reagents = {} }, [1.5] = { name = "frac", reagents = {} } })
        h.truthy(S.GetRecipe(7)); h.eq(S.GetRecipe(-3), nil); h.eq(S.GetRecipe(1.5), nil)
    end,

    ["store: character records with out-of-range or hostile values are rejected (RF3)"] = function(h)
        local S = h.ns({ now = 1.8e9 }).Store
        local function rec(mut) local r = h.char("Bob-R", 50, { 1 }); mut(r); return r end
        local bad = {
            rec(function(r) r.rev = 2 ^ 60 end), rec(function(r) r.rev = -1 end), rec(function(r) r.rev = 0.5 end),
            rec(function(r) r.level = 0 end), rec(function(r) r.level = 101 end), rec(function(r) r.level = 1 / 0 end),
            rec(function(r) r.name = "Bo|b" end), rec(function(r) r.name = "" end), rec(function(r) r.class = "MA|GE" end),
            rec(function(r) r.professions.Cooking.rank = -1 end), rec(function(r) r.professions.Cooking.max = 1001 end),
            rec(function(r) r.professions.Cooking.recipes[1e15] = true end), rec(function(r) r.professions.Cooking.recipes[0] = true end),
            rec(function(r) r.professions.Cooking.recipes[2] = "yes" end), rec(function(r) r.professions["Coo|king"] = r.professions.Cooking end),
            rec(function(r) r.professions.Cooking.id = 1e9 end), rec(function(r) r.professions.Cooking.name = "x\n" end),
            rec(function(r) for i = 1, 17 do r.professions["P" .. i] = { rank = 1, max = 1, recipes = {} } end end),
        }
        for i, r in ipairs(bad) do h.eq(S.ValidateChar(r), false, "record " .. i .. " accepted") end
        h.eq(S.ValidateChar(h.char("Bob-R", 50, { 1, 2, 3 })), true)
        h.eq(S.ValidateChar(h.char("Bob-R", h.clock + 3600, { 1 })), true)      -- small skew is fine
    end,

    ---------------------------------------------------------------- display escaping (RF5)
    ["model: peer text is escaped so colour, texture and hyperlink codes show as literal text (RF5)"] = function(h)
        local ns = h.ns()
        local attack = "|cffff0000|Hitem:1|h[Free gold]|h|r|TInterface\\Icons\\x:16|t"
        local escaped = attack:gsub("|", "||")
        local o = ns.Orders.New(function() return h.clock end, {})
        h.truthy(o:Merge({ id = "Bob-R:1:9", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, note = attack,
            claims = { ["Al-R"] = { state = "claimed", t = 901 } } }))
        local rows = ns.Model.BuildOrderRows(ns.Store, o, "all", false, "Me-R")
        h.eq(rows[1].note, escaped)
        h.eq(rows[1].claimers[1], "Al-R")
        -- defence in depth: values that were stored before the sanitizer existed still cannot inject codes
        ns.Store.db.catalog[5] = { name = "A|cff00ff00B", reagents = { { itemID = 9, count = 1, name = "R|r" } } }
        h.eq(ns.Model.RecipeName(ns.Store, 5), "A||cff00ff00B")
        h.eq(ns.Model.RecipeDetail(ns.Store, 5).reagents[1].name, "R||r")
        ns.Store.db.chars["Bob-R"] = { name = "Bob-R", rev = 1, level = 1, professions = { ["Cook|cffff0000ing"] =
            { name = "Cook|cffff0000ing", rank = 1, max = 1, recipes = { [5] = true } } } }
        h.eq(ns.Model.Professions(ns.Store)[1].name, "Cook||cffff0000ing")
        h.eq(ns.Model.BuildRecipeRows(ns.Store, { text = "" })[1].profession, "Cook||cffff0000ing")
    end,

    ---------------------------------------------------------------- migration and downgrade guard (RF6)
    ["store: a missing, corrupt or non-table SavedVariable starts empty"] = function(h)
        local ns = h.ns()
        for _, junk in ipairs({ false, "text", 42, { schema = "x" }, { schema = 0 }, { schema = 1.5 }, { schema = 0 / 0 } }) do
            local sv, status = ns.Store.Init(junk)
            h.eq(status, "reset", tostring(junk)); h.eq(sv.schema, ns.Store.SCHEMA); h.truthy(sv.chars and sv.orders and sv.catalog)
            h.truthy(sv == ns.db)
        end
        local sv, status = ns.Store.Init(nil)
        h.eq(status, "ok"); h.eq(sv.schema, ns.Store.SCHEMA)
    end,

    ["store: saved data from a NEWER schema is left untouched and the session runs on a throwaway DB (RF6)"] = function(h)
        local ns = h.ns()
        local saved = { schema = ns.Store.SCHEMA + 1, chars = { ["X-R"] = { future = true } }, shiny = "new feature data" }
        local sv, status = ns.Store.Init(saved)
        h.eq(status, "newer"); h.truthy(sv == saved, "must hand back the ORIGINAL table so the file is not overwritten")
        h.eq(saved.schema, ns.Store.SCHEMA + 1); h.truthy(saved.chars["X-R"].future); h.eq(saved.shiny, "new feature data")
        h.truthy(ns.db ~= saved); h.eq(ns.db.readonly, true)
        ns.Store.PutChar(h.char("Me-R", 50, { 1 }))              -- the session still works...
        h.eq(saved.chars["Me-R"], nil)                           -- ...but never writes into the saved table
        h.eq(ns.db.schema, ns.Store.SCHEMA)
    end,

    ["store: schema 1 data is migrated: valid records kept, hostile or corrupt ones dropped (RF6)"] = function(h)
        local ns = h.ns({ now = 1.8e9 })
        local legacy = {
            schema = 1,
            chars = {
                ["A-R"] = h.char("A-R", 50, { 1, 2 }),
                ["B-R"] = { name = "B-R", rev = 1 / 0, level = 60, professions = {} },                 -- inf rev
                ["C-R"] = h.char("D-R", 50, { 1 }),                                                     -- key does not match name
                ["E-R"] = "garbage",
            },
            catalog = {
                [1] = { name = "Good", reagents = { { itemID = 3, count = 1 } } },
                [2] = { name = "Bad", reagents = { { itemID = 3, count = 1, name = {} } } },
                ["x"] = { name = "Key not a number", reagents = {} },
            },
            orders = {
                ["Bob-R:1:1"] = { id = "Bob-R:1:1", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, claims = {} },
                ["Bob-R:1:2"] = { id = "Bob-R:1:2", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 1e15, claims = {} },
                ["wrong-key"] = { id = "Bob-R:1:3", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, claims = {} },
            },
            profNames = { deDE = { [165] = "Lederverarbeitung", [166] = {} }, ["bad|code"] = { [1] = "x" } },
            debug = "not a table", ui = 5,
        }
        local sv, status = ns.Store.Init(legacy)
        h.eq(status, "migrated"); h.eq(sv.schema, ns.Store.SCHEMA)
        h.truthy(sv.chars["A-R"]); h.eq(sv.chars["B-R"], nil); h.eq(sv.chars["C-R"], nil); h.eq(sv.chars["E-R"], nil)
        h.truthy(sv.catalog[1]); h.eq(sv.catalog[2], nil); h.eq(sv.catalog["x"], nil)
        h.truthy(sv.orders["Bob-R:1:1"]); h.eq(sv.orders["Bob-R:1:2"], nil); h.eq(sv.orders["wrong-key"], nil)
        h.eq(sv.profNames.deDE[165], "Lederverarbeitung"); h.eq(sv.profNames.deDE[166], nil)
        h.eq(sv.profNames["bad|code"], nil)
        h.eq(type(sv.debug), "table"); h.eq(type(sv.ui), "table")
        local again, st2 = ns.Store.Init(sv)                      -- idempotent: a second load changes nothing
        h.eq(st2, "ok"); h.truthy(again.chars["A-R"] and again.orders["Bob-R:1:1"])
    end,

    ["store: an unsynced clock (server time 0) never wipes saved data; the future bound only applies once time is known"] = function(h)
        local ns = h.ns({ now = 0 })
        h.eq(ns.Store.Horizon(), math.huge)
        local sv, status = ns.Store.Init({ schema = 1, chars = { ["A-R"] = h.char("A-R", 1.79e9, { 1 }) },
            orders = { ["Bob-R:1:1"] = { id = "Bob-R:1:1", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 1.79e9, claims = {} } } })
        h.eq(status, "migrated"); h.truthy(sv.chars["A-R"]); h.truthy(sv.orders["Bob-R:1:1"])
        local synced = h.ns({ now = 1.8e9 })
        h.eq(synced.Store.Horizon(), 1.8e9 + synced.Store.TIME_SLACK)
    end,

    ---------------------------------------------------------------- one version source (R11)
    ["version: the protocol constants match Core/Init.lua and the TOC version has a CHANGELOG entry"] = function(h)
        local ns = {}
        assert(loadfile("Core/Init.lua"))("TalentShare", ns)
        local pure = h.ns()
        h.eq(pure.PROTO_MAJOR, ns.PROTO_MAJOR, "tests/run.lua harness differs from Init.lua")
        h.eq(pure.PROTO_MINOR, ns.PROTO_MINOR); h.eq(pure.PROTOCOL, ns.PROTOCOL); h.eq(ns.PROTOCOL, ns.PROTO_MAJOR)
        local toc = slurp("TalentShare.toc")
        local version = toc:match("## Version:%s*(%S+)")
        h.truthy(version, "no ## Version in the TOC")
        h.eq(ns.BASE_VERSION, version, "Init.lua fallback differs from the TOC version")
        h.truthy(slurp("CHANGELOG.md"):find("## " .. version:gsub("%.", "%%."), 1), "CHANGELOG.md has no '## " .. version .. "' section")
    end,

    ["version: Init reads the version from addon metadata when the client provides it"] = function(h)
        local saved = _G.GetAddOnMetadata
        _G.GetAddOnMetadata = function(addon, field) return (addon == "TalentShare" and field == "Version") and "9.9.9" or nil end
        local ns = {}
        local ok, err = pcall(function() assert(loadfile("Core/Init.lua"))("TalentShare", ns) end)
        _G.GetAddOnMetadata = saved
        assert(ok, err)
        h.eq(ns.BASE_VERSION, "9.9.9")
    end,

    ["workflow: releases trigger on v* tags only and the token is not workflow-wide"] = function(h)
        local wf = slurp(".github/workflows/release.yml")
        h.truthy(wf:find("'v%*'") or wf:find('"v%*"'), "tag filter must be v*")
        h.truthy(not wf:find("'%*%*'"), "tag filter must not be '**'")
        local top = wf:match("^(.-)\njobs:") or ""
        h.truthy(not top:find("CF_API_TOKEN"), "CF_API_TOKEN must be scoped to the packager step, not the whole workflow")
        h.truthy(wf:find("CF_API_TOKEN"), "packager step lost its token")
    end,
}
