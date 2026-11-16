-- WoW Forever names, reproduced from a real /ts export (2026-11-16): characters have a first name AND a surname.
--   UnitName("player") -> "Drakk", "Nuk"      GetRealmName() -> "CAMWOW EU4 Realm 5 PvE"
--   GetNormalizedRealmName() -> "CAMWOWEU4Realm5PvE"      roster and chat senders -> "Drakk Nuk" (space, no realm)
-- 0.4.0 keyed me as "Drakk-CAMWOWEU4Realm5PvE" while everyone else saw "Drakk Nuk": requests for me were never answered,
-- records from me were refused, and my own GUILD echo was taken for another player.

local REALM, REALM_N = "CAMWOW EU4 Realm 5 PvE", "CAMWOWEU4Realm5PvE"
local ROSTER = { "Drakk Nuk", "Bren Fall", "Mira Holt", "Tam Reed", "Tam Ash", "Lio Brand" }

local function withForever(h, fn)
    local names = { "GetNormalizedRealmName", "GetRealmName", "UnitName", "UnitClass", "UnitLevel", "IsInGuild",
        "GetNumGuildMembers", "GetGuildRosterInfo", "Ambiguate", "C_GuildInfo", "GuildRoster", "UnitFullName", "GetGuildInfo", "GetBuildInfo" }
    local saved = {}
    for _, n in ipairs(names) do saved[n] = _G[n] end
    GetNormalizedRealmName = function() return REALM_N end
    GetRealmName = function() return REALM end
    UnitName = function() return "Drakk", "Nuk" end
    UnitFullName = function() return "Drakk", "Nuk" end
    UnitClass = function() return "Hunter", "HUNTER" end
    UnitLevel = function() return 29 end
    IsInGuild = function() return true end
    GetNumGuildMembers = function() return #ROSTER end
    GetGuildRosterInfo = function(i) return ROSTER[i] end
    Ambiguate = function(n) return (n:match("^([^-]+)")) end   -- what the export showed: "Drakk-Realm" -> "Drakk"
    local ok, err = pcall(function()
        local ns = h.ns()
        assert(loadfile("Core/Api.lua"))("TalentShare", ns)
        fn(ns)
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    if not ok then error(err, 0) end
end

local ME = "Drakk Nuk-" .. REALM_N

return {
    ["forever: my identity is first name + surname, as the roster and chat spell it"] = function(h)
        withForever(h, function(ns)
            h.eq(ns.Api.GetPlayerInfo().name, ME)
            local roster = ns.Api.GetGuildRoster()
            h.truthy(roster[ME], "me not in the canonical roster")
            h.truthy(roster["Mira Holt-" .. REALM_N])
            h.eq(ns.Util.Canon("Drakk Nuk"), ME)                         -- chat sender form
            h.eq(ns.Util.WhisperTarget("Mira Holt-" .. REALM_N), "Mira Holt")
        end)
    end,

    ["forever: 0.4.0 first-name keys map to the full name when unambiguous"] = function(h)
        withForever(h, function(ns)
            ns.Api.GetGuildRoster()
            h.eq(ns.Util.Canon("Drakk-" .. REALM_N), ME)                  -- my own old key
            h.eq(ns.Util.Canon("Mira-" .. REALM_N), "Mira Holt-" .. REALM_N)
            h.eq(ns.Util.Canon("Tam-" .. REALM_N), "Tam-" .. REALM_N)     -- "Tam Reed" and "Tam Ash": ambiguous, left alone
            -- one Forever guild spans several realms and names carry none: another realm is the same member
            h.eq(ns.Util.Canon("Mira-OtherRealm"), "Mira Holt-" .. REALM_N)
        end)
    end,

    ["forever: stored 0.4.0 data is moved to the full-name keys"] = function(h)
        withForever(h, function(ns)
            local S = ns.Store
            local old = "Drakk-" .. REALM_N
            S.db.me = old
            S.db.chars[old] = h.char(old, 100, { 6499 })
            S.db.offers[old] = { name = old, rev = 5, items = { [777] = { bag = 1 } }, dibs = { ["Mira-" .. REALM_N .. ":12"] = { on = true, t = 1 } } }
            local o = ns.orders and nil
            S.db.orders["x"] = { id = old .. ":1:1", requester = old, recipeID = 6499, qty = 1, note = "", createdAt = 1, claims = {} }
            S.db.me = ns.Api.GetPlayerInfo().name
            ns.Api.GetGuildRoster()
            S.Recanon()
            h.eq(S.db.me, ME)
            h.eq(S.db.chars[old], nil); h.eq(S.db.chars[ME].name, ME)
            h.eq(S.db.offers[ME].name, ME)
            h.truthy(S.db.offers[ME].dibs["Mira Holt-" .. REALM_N .. ":12"])
            h.eq(S.db.orders["x"].requester, ME)
        end)
    end,

    ["forever: my own GUILD echo is recognised and never handled as another player"] = function(h)
        withForever(h, function(ns)
            ns.Store.db.me = ns.Api.GetPlayerInfo().name
            local C = ns.Comm
            C.salt, C.active, C.roster = 0x1a2b, true, ns.Api.GetGuildRoster()
            local handled = 0
            C.sync = { OnMessage = function() handled = handled + 1 return "ok" end, stats = { sent = 0, received = 0, dropped = 0 } }
            local mine = ns.Codec.Header(("%04x%x"):format(C.salt, 3), 1, 1) .. ns.Codec.Encode({ t = "HELLO", rev = 1 })
            C.OnAddonMessage(ns.PREFIX, mine, "GUILD", "Drakk Nuk")
            h.eq(handled, 0)
            h.eq(C.lastEcho, "Drakk Nuk")
            -- even without the salt (an echo from a previous session) it is dropped as my own message
            local other = ns.Codec.Header("ffff1", 1, 1) .. ns.Codec.Encode({ t = "HELLO", rev = 1 })
            C.OnAddonMessage(ns.PREFIX, other, "GUILD", "Drakk Nuk")
            h.eq(handled, 0)
        end)
    end,

    ["forever: requests and records between surname players pass, also from a 0.4.0 peer's record"] = function(h)
        withForever(h, function(ns)
            ns.Store.db.me = ns.Api.GetPlayerInfo().name
            ns.Api.GetGuildRoster()
            ns.orders = ns.Orders.New(function() return h.clock end, ns.db.orders)
            ns.Store.PutChar(h.char(ME, 50, { 6499 }))
            local sync = ns.Sync.New({ send = function() end, now = function() return h.clock end, rand = function() return 0 end,
                store = ns.Store, orders = ns.orders, me = function() return ns.Store.db.me end, onChange = function() end })
            local FLEXI = "Mira Holt-" .. REALM_N
            h.eq((sync:OnMessage({ v = 2, t = "WANT", names = { ME } }, FLEXI)), "ok")
            h.eq((sync:OnMessage({ v = 2, t = "WANT", names = { "Drakk-" .. REALM_N } }, FLEXI)), "ok")   -- a 0.4.0 peer asks this way
            local st = sync:OnMessage({ v = 2, t = "SNAP", char = h.char("Mira-" .. REALM_N, 7, { 1 }), catalog = {} }, FLEXI)
            h.eq(st, "ok"); h.truthy(ns.Store.GetChar(FLEXI))
        end)
    end,

    ["forever: requests also carry the 0.4.0 first-name form, so members who did not update still answer"] = function(h)
        withForever(h, function(ns)
            ns.Store.db.me = ns.Api.GetPlayerInfo().name
            ns.Api.GetGuildRoster()
            local sent = {}
            local sync = ns.Sync.New({ send = function(msg, dist) sent[#sent + 1] = { msg = msg, dist = dist } end,
                now = function() return h.clock end, rand = function() return 0 end, store = ns.Store,
                orders = ns.Orders.New(function() return h.clock end, {}), me = function() return ns.Store.db.me end, onChange = function() end })
            local FLEXI = "Mira Holt-" .. REALM_N
            sync:OnMessage({ v = 2, t = "HELLO", rev = 50, orev = 9 }, FLEXI)
            h.eq(sent[1].msg.t, "WANT"); h.eq(sent[1].msg.names[1], FLEXI); h.eq(sent[1].msg.names[2], "Mira-" .. REALM_N)
            h.eq(sent[2].msg.t, "WANTO"); h.eq(sent[2].msg.names[2], "Mira-" .. REALM_N)
            -- a 0.4.0 member compares each name with its own first-name key: one of them matches
            local matches040 = false
            for _, n in ipairs(sent[1].msg.names) do if n == "Mira-" .. REALM_N then matches040 = true end end
            h.truthy(matches040)
            -- the GUILD retry carries both forms too
            sync:Tick(h.clock + 45)
            h.eq(sent[#sent].dist, "GUILD"); h.eq(#sent[#sent].msg.names, 2)
            -- shared first name ("Tam Reed", "Tam Ash"): no first-name form, both would answer
            h.eq(ns.Util.LegacyName("Tam Reed-" .. REALM_N), nil)
            h.eq(#ns.Sync.AskNames("Tam Reed-" .. REALM_N), 1)
            -- no surname (normal WoW): unchanged
            h.eq(ns.Util.LegacyName("Thrall-" .. REALM_N), nil)
            -- a 0.4.1 member receiving both forms answers once
            ns.Store.PutChar(h.char(ME, 60, { 1 }))
            local before = #sync.pending
            h.eq((sync:OnMessage({ v = 2, t = "WANT", names = { ME, "Drakk-" .. REALM_N } }, FLEXI)), "ok")
            h.eq(#sync.pending, before + 1)
        end)
    end,

    -- second export (2026-11-16, live 0.4.1): the guild spans "CAMWOW EU4 Realm 1/3/5 PvE" and "CAMWOW EU5 Realm 3 PvE";
    -- every client appended its own realm, so "Drakk Nuk-...Realm3" (asked by Mira) never matched "Drakk Nuk-...Realm5"
    ["forever: members on other realms of the guild are the same members (realm is not part of the name)"] = function(h)
        withForever(h, function(ns)
            ns.Store.db.me = ns.Api.GetPlayerInfo().name
            ns.Api.GetGuildRoster()
            local U = ns.Util
            h.eq(U.Canon("Drakk Nuk-CAMWOWEU4Realm3PvE"), ME)
            h.eq(U.Canon("Drakk Nuk-CAMWOWEU5Realm3PvE"), ME)
            h.eq(U.Canon("Mira-CAMWOWEU4Realm3PvE"), "Mira Holt-" .. REALM_N)   -- a 0.4.0 key from another realm
            h.eq(U.Canon("Tam-CAMWOWEU4Realm1PvE"), "Tam-" .. REALM_N)             -- ambiguous first name: realm only
            h.eq(U.WhisperTarget("Mira Holt-CAMWOWEU4Realm3PvE"), "Mira Holt")
            -- stored orders from other realms move to the one key
            ns.Store.db.orders["o"] = { id = "Orin-CAMWOWEU4Realm3PvE:1:1", requester = "Orin-CAMWOWEU4Realm3PvE",
                recipeID = 4094, qty = 1, note = "", createdAt = 1, claims = {} }
            ns.Store.Recanon()
            h.eq(ns.Store.db.orders["o"].requester, "Orin-" .. REALM_N)
        end)
    end,

    ["forever: requests from other realms are answered, in the spelling a 0.4.0 member accepts"] = function(h)
        withForever(h, function(ns)
            ns.Store.db.me = ns.Api.GetPlayerInfo().name
            ns.Api.GetGuildRoster()
            ns.Store.PutChar(h.char(ME, 50, { 6499 }))
            ns.Offers.Put({ name = ME, rev = 7, items = { [777] = { bag = 1 } }, dibs = {} })
            local sent = {}
            local sync = ns.Sync.New({ send = function(msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, to = target } end,
                now = function() return h.clock end, rand = function() return 0 end, store = ns.Store,
                orders = ns.Orders.New(function() return h.clock end, {}), me = function() return ns.Store.db.me end, onChange = function() end })
            local FLEXI = "Mira Holt-" .. REALM_N
            -- 0.4.0 member on Realm3 (exactly what the export showed)
            h.eq((sync:OnMessage({ v = 2, t = "WANT", names = { "Drakk Nuk-CAMWOWEU4Realm3PvE" } }, FLEXI)), "ok")
            h.eq((sync:OnMessage({ v = 2, t = "WANTO", names = { "Drakk Nuk-CAMWOWEU4Realm3PvE" } }, FLEXI)), "ok")
            -- 0.4.1 member on EU5 Realm3 (full name + first-name form)
            h.eq((sync:OnMessage({ v = 2, t = "WANT", names = { "Drakk Nuk-CAMWOWEU5Realm3PvE", "Drakk-CAMWOWEU5Realm3PvE" } },
                "Kael Stone-" .. REALM_N)), "ok")
            sync:Tick(h.clock + 5)
            local snap, offers, snap2
            for _, s in ipairs(sent) do
                if s.msg.t == "SNAP" and s.to == FLEXI then snap = s.msg end
                if s.msg.t == "OFFERS" and s.to == FLEXI then offers = s.msg end
                if s.msg.t == "SNAP" and s.to ~= FLEXI then snap2 = s.msg end
            end
            h.truthy(snap and offers and snap2, "not every request was answered")
            -- a 0.4.0 member compares the record name with the sender as IT spells it: "Drakk Nuk-<its realm>"
            h.eq(snap.char.name, "Drakk Nuk-CAMWOWEU4Realm3PvE")
            h.eq(offers.offers.name, "Drakk Nuk-CAMWOWEU4Realm3PvE")
            h.eq(ns.Store.GetChar(ME).name, ME)   -- my stored record keeps its own key
            -- requests to that member now also carry the first name in its realm (the only name a 0.4.0 client answers)
            sync:OnMessage({ v = 2, t = "HELLO", rev = 99, orev = 9 }, FLEXI)
            local want = sent[#sent - 1].msg
            h.eq(want.t, "WANT")
            local hasThere = false
            for _, n in ipairs(want.names) do if n == "Mira-CAMWOWEU4Realm3PvE" then hasThere = true end end
            h.truthy(hasThere, "no Mira-<its realm> in " .. table.concat(want.names, ","))
            -- its answer: record "Mira-CAMWOWEU4Realm3PvE" from sender "Mira Holt" is accepted
            h.eq((sync:OnMessage({ v = 2, t = "SNAP", char = h.char("Mira-CAMWOWEU4Realm3PvE", 99, { 1 }), catalog = {} }, FLEXI)), "ok")
            h.truthy(ns.Store.GetChar(FLEXI))
        end)
    end,

    ["forever: the name check shows the surname case as OK"] = function(h)
        withForever(h, function(ns)
            ns.Store.db.me = ns.Api.GetPlayerInfo().name
            local roster = ns.Api.GetGuildRoster()
            local info = ns.Api.IdentityInfo()
            h.eq(info.rosterMe, "Drakk Nuk")
            for _, r in ipairs(ns.Diag.IdentityRows({ info = info, me = ns.db.me, roster = roster, echo = "Drakk Nuk",
                seen = { ["Mira Holt-" .. REALM_N] = "Mira Holt" } })) do
                h.truthy(r.status == "ok" or r.status == "info" or r.status == "fixed", r.method .. " = " .. r.status .. " (" .. r.value .. ")")
            end
        end)
    end,
}
