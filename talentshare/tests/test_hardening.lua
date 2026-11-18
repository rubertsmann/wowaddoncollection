-- Feature 006: hardening and version compatibility. Adversarial cases RF1-RF7 (features/006-*/spec.md).

local function slurp(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("*a"); f:close()
    return s
end

-- a namespace with Comm wired to a recording Sync, as in the game after Comm.Start()
local function commNs(harness, me, roster, now)
    local addon = harness.addon({ now = now })
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
        store = addon.Store, orders = addon.orders, me = me, onChange = function() end,
    })
    out.addon, out.C = addon, C
    return out
end

local function chunk(addon, msg, id)
    return addon.Codec.Header(id or "a1", 1, 1) .. addon.Codec.Encode(msg)
end

local function bufferCount(C)
    local n = 0
    for _ in pairs(C.buffers) do n = n + 1 end
    return n
end

return {
    ---------------------------------------------------------------- helpers (T1)
    ["util: finite numbers, bounded integers, clean strings, names and escaping"] = function(harness)
        local U = harness.addon().Utility
        harness.equal(U.IsFinite(1), true); harness.equal(U.IsFinite(math.huge), false); harness.equal(U.IsFinite(-math.huge), false)
        harness.equal(U.IsFinite(0 / 0), false); harness.equal(U.IsFinite("1"), false); harness.equal(U.IsFinite(nil), false)
        harness.equal(U.SafeInteger(5, 1, 10), 5); harness.equal(U.SafeInteger(0, 1, 10), nil); harness.equal(U.SafeInteger(11, 1, 10), nil)
        harness.equal(U.SafeInteger(1.5, 1, 10), nil); harness.equal(U.SafeInteger(math.huge, 1, nil), nil); harness.equal(U.SafeInteger("5", 1, 10), nil)
        harness.equal(U.CleanString("Kürschnerei", 20), "Kürschnerei"); harness.equal(U.CleanString("a\nb", 20), nil)
        harness.equal(U.CleanString("a\0b", 20), nil); harness.equal(U.CleanString("x\128", 20), nil); harness.equal(U.CleanString("toolong", 3), nil)
        harness.equal(U.CleanString({}, 5), nil)
        harness.equal(U.IsSafeName("Bob-Area52"), true); harness.equal(U.IsSafeName("Bo|b"), false); harness.equal(U.IsSafeName(""), false)
        harness.equal(U.IsSafeName(string.rep("x", 65)), false); harness.equal(U.IsSafeName("a\tb"), false)
        harness.equal(U.StripControlCharacters("a\1b\127c\0d"), "abcd")
        harness.equal(U.Escape("|cffff0000red|r"), "||cffff0000red||r"); harness.equal(U.Escape(5), "5")
    end,

    ["codec: the parser rejects non-finite numbers that tonumber() would accept (RF3)"] = function(harness)
        local addon = harness.addon()
        for _, raw in ipairs({ "{s1:an1e999;}", "{s1:an-1e999;}", "{s1:ann;}", "n1e400;" }) do
            local t, err = addon.Codec.Deserialize(raw)
            harness.equal(t, nil, "accepted " .. raw)
            harness.truthy(err)
        end
        harness.truthy(addon.Codec.Deserialize("{s1:an1.5;}"))
    end,

    ---------------------------------------------------------------- header / compat / limits (T2)
    ["codec: chunk header round-trips and carries major.minor"] = function(harness)
        local addon = harness.addon()
        local text = addon.Codec.Header("3fa2", 2, 5) .. "payload|with|bars"
        harness.truthy(text:find("^2%." .. addon.PROTOCOL_MINOR .. "|3fa2|2|5|"))
        local p = assert(addon.Codec.ParseHeader(text))
        harness.equal(p.major, 2); harness.equal(p.minor, addon.PROTOCOL_MINOR); harness.equal(p.transferID, "3fa2"); harness.equal(p.partIndex, 2); harness.equal(p.partCount, 5); harness.equal(p.payload, "payload|with|bars")
    end,

    ["codec: malformed headers are rejected, legacy 0.1/0.2 headers are recognised, foreign majors only expose the version"] = function(harness)
        local addon = harness.addon()
        for _, bad in ipairs({ "", "garbage", "2.0|", "2.0|zz|1|1|x", "2.0|a|0|1|x", "2.0|a|2|1|x", "2.0|a|1|0|x",
            "2.0|a|1|201|x", "2.0|a|1|99999|x", "2.0|" .. string.rep("a", 13) .. "|1|1|x", "1234.0|a|1|1|x" }) do
            harness.equal((addon.Codec.ParseHeader(bad)), nil, "accepted: " .. bad)
        end
        local _, why = addon.Codec.ParseHeader("3fa|1|2|abc")   -- the 0.1/0.2 layout
        harness.equal(why, "legacy")
        local f = assert(addon.Codec.ParseHeader("3.7|anything we cannot know|"))
        harness.equal(f.major, 3); harness.equal(f.minor, 7); harness.equal(f.id, nil)
        harness.equal((addon.Codec.ParseHeader(nil)), nil)
    end,

    ["codec: compatibility rule: major must match, minor may differ"] = function(harness)
        local addon = harness.addon()
        harness.equal(addon.Codec.Compatibility(2, 0), "ok"); harness.equal(addon.Codec.Compatibility(addon.PROTOCOL_MAJOR, 0), "ok")
        harness.equal(addon.Codec.Compatibility(addon.PROTOCOL_MAJOR, addon.PROTOCOL_MINOR + 1), "newer-minor")
        harness.equal(addon.Codec.Compatibility(addon.PROTOCOL_MAJOR + 1, 0), "newer"); harness.equal(addon.Codec.Compatibility(addon.PROTOCOL_MAJOR - 1, 9), "older")
    end,

    ["codec: transport limits are defined once and Decode accepts what the transport can deliver"] = function(harness)
        local addon = harness.addon()
        harness.equal(addon.Codec.MAXIMUM_ENCODED_BYTES, addon.Codec.CHUNK_BYTES * addon.Codec.MAXIMUM_PARTS)
        harness.truthy(addon.Codec.CHUNK_BYTES + 30 <= 255, "header + payload must fit one addon message")
        harness.equal((addon.Codec.Decode(string.rep("x", addon.Codec.MAXIMUM_ENCODED_BYTES + 1))), nil)
        local comm = slurp("Core/Net/Communication.lua")
        harness.truthy(not comm:find("local CHUNK_BYTES = %d"), "Communication must not define its own CHUNK_BYTES")
        harness.truthy(not comm:find("local MAXIMUM_PARTS = %d"), "Communication must not define its own MAXIMUM_PARTS")
    end,

    ["guard: only GUILD, or WHISPER from a roster member, is accepted; everything else fails closed"] = function(harness)
        local G = harness.addon().Guard
        local roster = { ["Bob-R"] = true }
        harness.equal((G.Accept("GUILD", "Anyone-R", roster)), true)
        harness.equal((G.Accept("GUILD", "Anyone-R", nil)), true)
        harness.equal((G.Accept("WHISPER", "Bob-R", roster)), true)
        harness.equal((G.Accept("WHISPER", "Stranger-R", roster)), false)
        harness.equal((G.Accept("WHISPER", "Bob-R", {})), false)       -- roster not loaded yet: fail closed
        harness.equal((G.Accept("WHISPER", "Bob-R", nil)), false)
        for _, ch in ipairs({ "PARTY", "RAID", "SAY", "YELL", "CHANNEL", "INSTANCE_CHAT", "OFFICER", "", "guild" }) do
            harness.equal((G.Accept(ch, "Bob-R", roster)), false, ch)
        end
        harness.equal((G.Accept(nil, "Bob-R", roster)), false)
        harness.equal((G.Accept("GUILD", nil, roster)), false); harness.equal((G.Accept("GUILD", "", roster)), false)
    end,

    ["guard: one notice per kind and a bounded record of who was seen"] = function(harness)
        local G = harness.addon().Guard
        local hints = G.NewHints()
        harness.equal(G.Note(hints, "newer", "A-R"), true)
        harness.equal(G.Note(hints, "newer", "B-R"), false)
        harness.equal(G.Note(hints, "older", "B-R"), true)
        for i = 1, G.MAXIMUM_SEEN + 50 do G.Note(hints, "older", "P" .. i) end
        harness.truthy(hints.count <= G.MAXIMUM_SEEN, "seen record grew unbounded: " .. hints.count)
    end,

    ---------------------------------------------------------------- Comm gate and versions (RF1, RF2, RF7)
    ["comm: a WHISPER from a non-guild character is dropped before anything is buffered or answered (RF1)"] = function(harness)
        local c = commNs(harness, "Me-R", { ["Bob-R"] = true })
        c.addon.Store.PutCharacter(harness.character("Me-R", 50, { 1 }))
        local want = chunk(c.addon, { t = "WANT", names = { "Me-R" } })
        c.C.OnAddonMessage("TShare", want, "WHISPER", "Stranger-R")
        harness.equal(bufferCount(c.C), 0); harness.equal(c.C.sync.statistics.received, 0); harness.equal(#c.C.sync.pending, 0)
        harness.equal(c.C.rejected, 1)
        c.C.OnAddonMessage("TShare", want, "WHISPER", "Bob-R")       -- a roster member is served
        harness.equal(c.C.sync.statistics.received, 1); harness.equal(#c.C.sync.pending, 1)
    end,

    ["comm: foreign channels and a missing roster are rejected; GUILD is accepted"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        local hello = chunk(c.addon, { t = "HELLO", rev = 0 })
        for _, ch in ipairs({ "PARTY", "RAID", "SAY", "CHANNEL", "WHISPER" }) do c.C.OnAddonMessage("TShare", hello, ch, "Bob-R") end
        harness.equal(c.C.sync.statistics.received, 0)
        c.C.OnAddonMessage("TShare", hello, "GUILD", "Bob-R")
        harness.equal(c.C.sync.statistics.received, 1)
        c.C.OnAddonMessage("Other", hello, "GUILD", "Bob-R")         -- not our prefix
        c.C.OnAddonMessage("TShare", hello, "GUILD", "Me-R")         -- own echo
        harness.equal(c.C.sync.statistics.received, 1)
    end,

    ["comm: a newer major or a legacy header creates no buffer and prints ONE hint per kind (RF2)"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        local newer = "3.0|aa|1|1|" .. string.rep("x", 40)
        c.C.OnAddonMessage("TShare", newer, "GUILD", "A-R")
        c.C.OnAddonMessage("TShare", newer, "GUILD", "B-R")
        harness.equal(#c.prints, 1); harness.truthy(c.prints[1]:lower():find("newer", 1, true), c.prints[1])
        c.C.OnAddonMessage("TShare", "3fa|1|1|legacypayload", "GUILD", "C-R")
        c.C.OnAddonMessage("TShare", "3fa|1|1|legacypayload", "GUILD", "D-R")
        harness.equal(#c.prints, 2); harness.truthy(c.prints[2]:lower():find("older", 1, true), c.prints[2])
        harness.equal(bufferCount(c.C), 0); harness.equal(c.C.sync.statistics.received, 0); harness.equal(c.C.hints.count, 4)
        c.C.OnAddonMessage("TShare", "total garbage", "GUILD", "E-R")   -- malformed: silently ignored, no hint
        harness.equal(#c.prints, 2)
    end,

    ["comm: a newer MINOR is processed and noted; an older minor is processed silently (RF7)"] = function(harness)
        local c = commNs(harness, "Me-R", {})
        local enc = c.addon.Codec.Encode({ t = "HELLO", rev = 0 })
        c.C.OnAddonMessage("TShare", "2.9|a1|1|1|" .. enc, "GUILD", "A-R")
        harness.equal(c.C.sync.statistics.received, 1); harness.equal(#c.prints, 1)
        c.C.OnAddonMessage("TShare", "2.0|a2|1|1|" .. enc, "GUILD", "B-R")
        harness.equal(c.C.sync.statistics.received, 2); harness.equal(#c.prints, 1)
    end,

    ["comm: two clients on different minors sync; different majors do not (RF7)"] = function(harness)
        local function pair(minorB, majorB)
            local a, b = commNs(harness, "A-R", {}), commNs(harness, "B-R", {})
            b.addon.PROTOCOL_MINOR, b.addon.PROTOCOL_MAJOR, b.addon.PROTOCOL = minorB, majorB, majorB
            a.addon.Store.PutCharacter(harness.character("A-R", 50, { 1 }))
            a.C.Send({ t = "HELLO", rev = 50 }, "GUILD")
            b.C.Send({ t = "HELLO", rev = 0 }, "GUILD")
            for _, item in ipairs(a.C.queue) do b.C.OnAddonMessage("TShare", item.text, "GUILD", "A-R") end
            for _, item in ipairs(b.C.queue) do a.C.OnAddonMessage("TShare", item.text, "GUILD", "B-R") end
            return a, b
        end
        local a, b = pair(3, 2)                                  -- B has extra (additive) features
        harness.equal(a.C.sync.statistics.received, 1); harness.equal(b.C.sync.statistics.received, 1)
        local a2, b2 = pair(0, 3)                                -- B speaks a different major
        harness.equal(a2.C.sync.statistics.received, 0); harness.equal(b2.C.sync.statistics.received, 0)
        harness.equal(#a2.prints, 1); harness.equal(#b2.prints, 1)                 -- both sides are told
    end,

    ["comm: message ids start with the per-session salt, so a reload cannot reuse an id (V6)"] = function(harness)
        local c1, c2 = commNs(harness, "A-R", {}), commNs(harness, "A-R", {})
        c1.C.salt, c2.C.salt = 0x1234, 0x5678
        c1.C.Send({ t = "HELLO", rev = 1 }, "GUILD"); c2.C.Send({ t = "HELLO", rev = 1 }, "GUILD")
        local id1 = c1.addon.Codec.ParseHeader(c1.C.queue[1].text).transferID
        local id2 = c2.addon.Codec.ParseHeader(c2.C.queue[1].text).transferID
        harness.truthy(id1:find("^1234"), id1); harness.truthy(id2:find("^5678"), id2); harness.truthy(id1 ~= id2)
        harness.truthy(#id1 <= 12)
    end,

    ["comm: every chunk fits one addon message"] = function(harness)
        local c = commNs(harness, "A-R", {})
        local big = {}
        for i = 1, 4000 do big[i] = math.random(1, 1e9) end    -- incompressible-ish payload
        c.C.Send({ t = "OPUSH", orders = { { id = table.concat(big, ",") } } }, "WHISPER", "B-R")
        harness.truthy(#c.C.queue > 1)
        for _, item in ipairs(c.C.queue) do harness.truthy(#item.text <= 255, "chunk of " .. #item.text .. " bytes") end
    end,

    ---------------------------------------------------------------- numeric bounds (RF3, R6)
    ["sync: HELLO with a non-finite, negative or future rev is dropped and triggers no pull (RF3)"] = function(harness)
        local c = commNs(harness, "Me-R", { ["Bob-R"] = true }, 1.8e9)   -- a realistic server time: "future" is judged against it
        local sync = c.C.sync
        for _, rev in ipairs({ 2 ^ 60, -5, 1e15, harness.clock + 86400 + 1 }) do
            sync:OnMessage({ v = c.addon.PROTOCOL, t = "HELLO", rev = rev }, "Bob-R")
        end
        harness.equal(sync.statistics.dropped, 4); harness.equal(#c.sent, 0)
        sync:OnMessage({ v = c.addon.PROTOCOL, t = "HELLO", rev = harness.clock + 10 }, "Bob-R")   -- small clock skew is fine
        harness.equal(sync.statistics.dropped, 4); harness.equal(#c.sent, 1); harness.equal(c.sent[1].msg.t, "WANT")
    end,

    ["orders: far-future or negative timestamps and unsafe names are rejected, so they cannot win merges or evade pruning (RF3)"] = function(harness)
        local addon = harness.addon({ now = 1.8e9 })
        local o = addon.Orders.New(function() return harness.clock end, {})
        local base = function() return { id = "Bob-R:1:1", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, claims = {} } end
        harness.truthy(o:Merge(base()))
        local function rejected(mut) local x = base(); x.id = "X" .. math.random(1e9); mut(x); return o:Merge(x) == false end
        harness.truthy(rejected(function(x) x.createdAt = 1e15 end))
        harness.truthy(rejected(function(x) x.createdAt = -1 end))
        harness.truthy(rejected(function(x) x.createdAt = 2 ^ 60 end))
        harness.truthy(rejected(function(x) x.closed, x.closedAt = "cancelled", -1e18 end))
        harness.truthy(rejected(function(x) x.closed, x.closedAt = "done", 1e15 end))
        harness.truthy(rejected(function(x) x.claims = { ["A-R"] = { state = "claimed", t = 1e15 } } end))
        harness.truthy(rejected(function(x) x.claims = { ["A|cffff0000-R"] = { state = "claimed", t = 1 } } end))
        harness.truthy(rejected(function(x) x.requester = "Bob|cffff0000" end))
        harness.truthy(rejected(function(x) x.requester = {} end))
        harness.truthy(rejected(function(x) x.closedBy = {} end))
        harness.truthy(rejected(function(x) x.recipeID = 1e15 end))
        harness.truthy(rejected(function(x) x.recipeID = 0 end))
        -- an attack on an EXISTING order: a tiny closedAt would have won every merge forever
        local cancel = base(); cancel.closed, cancel.closedAt = "cancelled", -1e18
        harness.equal(o:Merge(cancel), false); harness.equal(o:Get("Bob-R:1:1").closed, nil)
    end,

    ["orders: control characters are stripped from notes; the note stays UTF-8"] = function(harness)
        local addon = harness.addon()
        local o = addon.Orders.New(function() return harness.clock end, {})
        local ord = { id = "Bob-R:1:2", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, claims = {}, note = "a\nb\0c" }
        harness.truthy(o:Merge(ord)); harness.equal(o:Get("Bob-R:1:2").note, "abc")
        ord.id, ord.note = "Bob-R:1:3", "x\255y"
        harness.equal(o:Merge(ord), false)
    end,

    ---------------------------------------------------------------- strict sanitizing (RF4, R7, R8)
    ["sync: SNAP stores a clean copy: unknown keys are dropped, extra catalog ids are refused, bad entries never stored (RF4)"] = function(harness)
        local c = commNs(harness, "Me-R", { ["Bob-R"] = true })
        local char = harness.character("Bob-R", 50, { 1 })
        char.evil, char.professions.Cooking.evil, char.professions.Cooking.recipes[1] = { 1, 2, 3 }, "x", true
        local good = { name = "Roast Boar", reagents = { { itemID = 10, count = 2 } }, evil = "x", icon = 133 }
        c.C.sync:OnMessage({ v = c.addon.PROTOCOL, t = "SNAP", char = char, catalog = {
            [1] = good,
            [2] = { name = "Not Bobs Recipe", reagents = {} },                          -- Bob does not know recipe 2
        } }, "Bob-R")
        local stored = c.addon.Store.GetCharacter("Bob-R")
        harness.truthy(stored); harness.equal(stored.evil, nil); harness.equal(stored.professions.Cooking.evil, nil)
        harness.equal(c.addon.Store.GetRecipe(1).name, "Roast Boar"); harness.equal(c.addon.Store.GetRecipe(1).evil, nil)
        harness.equal(c.addon.Store.GetRecipe(2), nil)
    end,

    ["store: catalog entries with hostile or wrongly typed fields are rejected (RF4)"] = function(harness)
        local S = harness.addon().Store
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
        for i, e in ipairs(bad) do harness.equal(S.ValidateCatalogEntry(e), false, "entry " .. i .. " accepted") end
        local many = {}
        for i = 1, 13 do many[i] = { itemID = i, count = 1 } end
        harness.equal(S.ValidateCatalogEntry({ name = "X", reagents = many }), false)
        harness.equal(S.ValidateCatalogEntry({ name = "Kürschnerei", loc = "deDE", icon = 133, produces = 5, reagents = {} }), true)
        harness.equal(S.ValidateCatalogEntry({ name = "X", icon = "Interface\\Icons\\INV_Misc_Food_01", reagents = {} }), true)
        -- PutCatalog stores nothing but clean copies, and a bad entry does not block a later good one
        S.PutCatalog({ [7] = { name = "X", reagents = { { itemID = 1, count = 1, name = {} } } } })
        harness.equal(S.GetRecipe(7), nil)
        S.PutCatalog({ [7] = { name = "X", reagents = {} }, [-3] = { name = "neg", reagents = {} }, [1.5] = { name = "frac", reagents = {} } })
        harness.truthy(S.GetRecipe(7)); harness.equal(S.GetRecipe(-3), nil); harness.equal(S.GetRecipe(1.5), nil)
    end,

    ["store: character records with out-of-range or hostile values are rejected (RF3)"] = function(harness)
        local S = harness.addon({ now = 1.8e9 }).Store
        local function rec(mut) local r = harness.character("Bob-R", 50, { 1 }); mut(r); return r end
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
        for i, r in ipairs(bad) do harness.equal(S.ValidateCharacter(r), false, "record " .. i .. " accepted") end
        harness.equal(S.ValidateCharacter(harness.character("Bob-R", 50, { 1, 2, 3 })), true)
        harness.equal(S.ValidateCharacter(harness.character("Bob-R", harness.clock + 3600, { 1 })), true)      -- small skew is fine
    end,

    ---------------------------------------------------------------- display escaping (RF5)
    ["model: peer text is escaped so colour, texture and hyperlink codes show as literal text (RF5)"] = function(harness)
        local addon = harness.addon()
        local attack = "|cffff0000|Hitem:1|h[Free gold]|h|r|TInterface\\Icons\\x:16|t"
        local escaped = attack:gsub("|", "||")
        local o = addon.Orders.New(function() return harness.clock end, {})
        harness.truthy(o:Merge({ id = "Bob-R:1:9", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 900, note = attack,
            claims = { ["Al-R"] = { state = "claimed", t = 901 } } }))
        local rows = addon.Model.BuildOrderRows(addon.Store, o, "all", false, "Me-R")
        harness.equal(rows[1].note, escaped)
        harness.equal(rows[1].claimers[1], "Al-R")
        -- defence in depth: values that were stored before the sanitizer existed still cannot inject codes
        addon.Store.db.catalog[5] = { name = "A|cff00ff00B", reagents = { { itemID = 9, count = 1, name = "R|r" } } }
        harness.equal(addon.Model.RecipeName(addon.Store, 5), "A||cff00ff00B")
        harness.equal(addon.Model.RecipeDetail(addon.Store, 5).reagents[1].name, "R||r")
        addon.Store.db.chars["Bob-R"] = { name = "Bob-R", rev = 1, level = 1, professions = { ["Cook|cffff0000ing"] =
            { name = "Cook|cffff0000ing", rank = 1, max = 1, recipes = { [5] = true } } } }
        harness.equal(addon.Model.Professions(addon.Store)[1].name, "Cook||cffff0000ing")
        harness.equal(addon.Model.BuildRecipeRows(addon.Store, { text = "" })[1].profession, "Cook||cffff0000ing")
    end,

    ---------------------------------------------------------------- migration and downgrade guard (RF6)
    ["store: a missing, corrupt or non-table SavedVariable starts empty"] = function(harness)
        local addon = harness.addon()
        for _, junk in ipairs({ false, "text", 42, { schema = "x" }, { schema = 0 }, { schema = 1.5 }, { schema = 0 / 0 } }) do
            local sv, status = addon.Store.Init(junk)
            harness.equal(status, "reset", tostring(junk)); harness.equal(sv.schema, addon.Store.SCHEMA); harness.truthy(sv.chars and sv.orders and sv.catalog)
            harness.truthy(sv == addon.db)
        end
        local sv, status = addon.Store.Init(nil)
        harness.equal(status, "ok"); harness.equal(sv.schema, addon.Store.SCHEMA)
    end,

    ["store: saved data from a NEWER schema is left untouched and the session runs on a throwaway DB (RF6)"] = function(harness)
        local addon = harness.addon()
        local saved = { schema = addon.Store.SCHEMA + 1, chars = { ["X-R"] = { future = true } }, shiny = "new feature data" }
        local sv, status = addon.Store.Init(saved)
        harness.equal(status, "newer"); harness.truthy(sv == saved, "must hand back the ORIGINAL table so the file is not overwritten")
        harness.equal(saved.schema, addon.Store.SCHEMA + 1); harness.truthy(saved.chars["X-R"].future); harness.equal(saved.shiny, "new feature data")
        harness.truthy(addon.db ~= saved); harness.equal(addon.db.readonly, true)
        addon.Store.PutCharacter(harness.character("Me-R", 50, { 1 }))              -- the session still works...
        harness.equal(saved.chars["Me-R"], nil)                           -- ...but never writes into the saved table
        harness.equal(addon.db.schema, addon.Store.SCHEMA)
    end,

    ["store: /ts clean during a downgrade-guarded session only empties the throwaway DB, never the saved file (RF6)"] = function(harness)
        local addon = harness.addon()
        local saved = { schema = addon.Store.SCHEMA + 1, chars = { ["X-R"] = { future = true } }, orders = { keep = { future = true } } }
        addon.Store.Init(saved)
        addon.Store.PutCharacter(harness.character("Me-R", 50, { 1 }))
        local removed = addon.Store.Clean()
        harness.equal(removed.chars, 1)                                   -- only the session's own record
        harness.truthy(saved.chars["X-R"].future); harness.truthy(saved.orders.keep.future)
        harness.equal(saved.schema, addon.Store.SCHEMA + 1)
    end,

    ["store: /ts clean keeps the schema marker, so the next load does not re-migrate"] = function(harness)
        local addon = harness.addon()
        addon.Store.PutCharacter(harness.character("A-R", 50, { 1 }))
        addon.Store.Clean()
        harness.equal(addon.db.schema, addon.Store.SCHEMA)
        local _, status = addon.Store.Init(addon.db)
        harness.equal(status, "ok")
    end,

    ["store: schema 1 data is migrated: valid records kept, hostile or corrupt ones dropped (RF6)"] = function(harness)
        local addon = harness.addon({ now = 1.8e9 })
        local legacy = {
            schema = 1,
            chars = {
                ["A-R"] = harness.character("A-R", 50, { 1, 2 }),
                ["B-R"] = { name = "B-R", rev = 1 / 0, level = 60, professions = {} },                 -- inf rev
                ["C-R"] = harness.character("D-R", 50, { 1 }),                                                     -- key does not match name
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
        local sv, status = addon.Store.Init(legacy)
        harness.equal(status, "migrated"); harness.equal(sv.schema, addon.Store.SCHEMA)
        harness.truthy(sv.chars["A-R"]); harness.equal(sv.chars["B-R"], nil); harness.equal(sv.chars["C-R"], nil); harness.equal(sv.chars["E-R"], nil)
        harness.truthy(sv.catalog[1]); harness.equal(sv.catalog[2], nil); harness.equal(sv.catalog["x"], nil)
        harness.truthy(sv.orders["Bob-R:1:1"]); harness.equal(sv.orders["Bob-R:1:2"], nil); harness.equal(sv.orders["wrong-key"], nil)
        harness.equal(sv.profNames.deDE[165], "Lederverarbeitung"); harness.equal(sv.profNames.deDE[166], nil)
        harness.equal(sv.profNames["bad|code"], nil)
        harness.equal(type(sv.debug), "table"); harness.equal(type(sv.ui), "table")
        local again, st2 = addon.Store.Init(sv)                      -- idempotent: a second load changes nothing
        harness.equal(st2, "ok"); harness.truthy(again.chars["A-R"] and again.orders["Bob-R:1:1"])
    end,

    ["store: an unsynced clock (server time 0) never wipes saved data; the future bound only applies once time is known"] = function(harness)
        local addon = harness.addon({ now = 0 })
        harness.equal(addon.Store.Horizon(), math.huge)
        local sv, status = addon.Store.Init({ schema = 1, chars = { ["A-R"] = harness.character("A-R", 1.79e9, { 1 }) },
            orders = { ["Bob-R:1:1"] = { id = "Bob-R:1:1", requester = "Bob-R", recipeID = 5, qty = 1, createdAt = 1.79e9, claims = {} } } })
        harness.equal(status, "migrated"); harness.truthy(sv.chars["A-R"]); harness.truthy(sv.orders["Bob-R:1:1"])
        local synced = harness.addon({ now = 1.8e9 })
        harness.equal(synced.Store.Horizon(), 1.8e9 + synced.Store.TIME_SLACK)
    end,

    ---------------------------------------------------------------- one version source (R11)
    ["version: the protocol constants match Core/Base/Init.lua and the TOC version has a CHANGELOG entry"] = function(harness)
        local addon = {}
        assert(loadfile("Core/Base/Init.lua"))("TalentShare", addon)
        local pure = harness.addon()
        harness.equal(pure.PROTOCOL_MAJOR, addon.PROTOCOL_MAJOR, "tests/run.lua harness differs from Init.lua")
        harness.equal(pure.PROTOCOL_MINOR, addon.PROTOCOL_MINOR); harness.equal(pure.PROTOCOL, addon.PROTOCOL); harness.equal(addon.PROTOCOL, addon.PROTOCOL_MAJOR)
        local toc = slurp("TalentShare.toc")
        local version = toc:match("## Version:%s*(%S+)")
        harness.truthy(version, "no ## Version in the TOC")
        harness.equal(addon.BASE_VERSION, version, "Init.lua fallback differs from the TOC version")
        harness.truthy(slurp("CHANGELOG.md"):find("## " .. version:gsub("%.", "%%."), 1), "CHANGELOG.md has no '## " .. version .. "' section")
    end,

    ["version: Init reads the version from addon metadata when the client provides it"] = function(harness)
        local saved = _G.GetAddOnMetadata
        _G.GetAddOnMetadata = function(addonFolderName, field) return (addonFolderName == "TalentShare" and field == "Version") and "9.9.9" or nil end
        local addon = {}
        local ok, err = pcall(function() assert(loadfile("Core/Base/Init.lua"))("TalentShare", addon) end)
        _G.GetAddOnMetadata = saved
        assert(ok, err)
        harness.equal(addon.BASE_VERSION, "9.9.9")
    end,

    ["workflow: releases trigger on v* tags only and the token is not workflow-wide"] = function(harness)
        local wf = slurp(".github/workflows/release.yml")
        harness.truthy(wf:find("'v%*'") or wf:find('"v%*"'), "tag filter must be v*")
        harness.truthy(not wf:find("'%*%*'"), "tag filter must not be '**'")
        local top = wf:match("^(.-)\njobs:") or ""
        harness.truthy(not top:find("CF_API_TOKEN"), "CF_API_TOKEN must be scoped to the packager step, not the whole workflow")
        harness.truthy(wf:find("CF_API_TOKEN"), "packager step lost its token")
    end,
    ---------------------------------------------------------------- feature 015: games moved to GuildGames; schema 5
    ["015: protocol 2.3 and schema 5 are pinned; migration 4 -> 5 drops games and the games settings, keeps everything else"] = function(harness)
        local addon = harness.addon({ now = 1.8e9 })
        harness.equal(addon.PROTOCOL_MAJOR, 2); harness.equal(addon.PROTOCOL_MINOR, 3); harness.equal(addon.Store.SCHEMA, 5)
        harness.equal(addon.Games, nil, "the games left TalentShare")
        local sv = { schema = 4, chars = {}, catalog = {}, orders = {}, me = "Me-R",
            ui = { lastStake = 50, lastStakeCopper = 100, lastSlotStakeCopper = 10, gamesScope = "all", gameKey = "slots" },
            games = { ["A-R"] = { name = "A-R", rev = 1, total = {}, weeks = {}, recent = {} } },
            offers = { ["A-R"] = { name = "A-R", rev = 1.79e9, items = { [6661] = { bag = 1 } }, dibs = {} } }, hidden = {} }
        local out, status = addon.Store.Init(sv)
        harness.equal(status, "migrated"); harness.equal(out.schema, 5)
        harness.equal(out.games, nil); harness.truthy(out.offers["A-R"]); harness.equal(out.ui.lastStake, 50)
        for _, key in ipairs({ "lastStakeCopper", "lastSlotStakeCopper", "gamesScope", "gameKey" }) do harness.equal(out.ui[key], nil, key) end
        -- a schema-3 file walks 3 -> 4 -> 5 and ends without games too
        local older = harness.addon({ now = 1.8e9 })
        local olderOut = older.Store.Init({ schema = 3, chars = {}, catalog = {}, orders = {}, offers = {}, hidden = {}, ui = {} })
        harness.equal(olderOut.schema, 5); harness.equal(olderOut.games, nil)
        -- a schema-6 file (a later build) stays untouched and this session does not save
        local later = harness.addon({ now = 1.8e9 })
        local saved = { schema = 6, future = { x = true } }
        local kept, laterStatus = later.Store.Init(saved)
        harness.equal(laterStatus, "newer"); harness.truthy(kept == saved); harness.truthy(saved.future.x)
        harness.truthy(later.db.readonly)
    end,

    -- RF3: a 0.6.0 member still announces grev and may send WANTG/GAMES; 0.7 ignores them without errors
    ["015: a 0.6 peer's games messages are ignored, the rest of its HELLO still works"] = function(harness)
        local addon = harness.addon({ now = 1.8e9 })
        addon.Store.db.me = "Me-R"
        local sent = {}
        local orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
        local sync = addon.Sync.New({ send = function(m, d, t) sent[#sent + 1] = { msg = m, dist = d, target = t } end,
            now = function() return harness.clock end, random = function() return 0 end, store = addon.Store, orders = orders,
            me = "Me-R", onChange = function() end })
        local status, reason = sync:OnMessage({ v = addon.PROTOCOL, t = "HELLO", rev = 1.79e9, odig = {}, grev = 1.79e9 }, "Old-R")
        harness.equal(status, "ok"); harness.truthy(reason:find("char: have 0 < ", 1, true), reason)
        harness.truthy(not reason:find("games", 1, true), "no games pull: " .. reason)
        harness.equal(#sent, 1); harness.equal(sent[1].msg.t, "WANT")
        for _, messageType in ipairs({ "WANTG", "GAMES" }) do
            local dropped, why = sync:OnMessage({ v = addon.PROTOCOL, t = messageType, names = { "Me-R" }, games = {} }, "Old-R")
            harness.equal(dropped, "dropped"); harness.equal(why, "unknown message type " .. messageType)
        end
        sync:Hello()
        harness.equal(sent[#sent].msg.grev, nil, "0.7 never announces games")
    end,
}
