-- WoW Forever names, reproduced from a real /ts export (2026-11-16): characters have a first name AND a surname.
--   UnitName("player") -> "Drakk", "Nuk"      GetRealmName() -> "CAMWOW EU4 Realm 5 PvE"
--   GetNormalizedRealmName() -> "CAMWOWEU4Realm5PvE"      roster and chat senders -> "Drakk Nuk" (space, no realm)
-- 0.4.0 keyed me as "Drakk-CAMWOWEU4Realm5PvE" while everyone else saw "Drakk Nuk": requests for me were never answered,
-- records from me were refused, and my own GUILD echo was taken for another player.

local REALM, REALM_N = "CAMWOW EU4 Realm 5 PvE", "CAMWOWEU4Realm5PvE"
local ROSTER = { "Drakk Nuk", "Bren Fall", "Mira Holt", "Tam Reed", "Tam Ash", "Lio Brand" }

local function withForever(harness, fn)
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
        local addon = harness.addon()
        assert(loadfile("Core/Game/Api.lua"))("TalentShare", addon)
        fn(addon)
    end)
    for _, n in ipairs(names) do _G[n] = saved[n] end
    if not ok then error(err, 0) end
end

local ME = "Drakk Nuk-" .. REALM_N

return {
    ["forever: my identity is first name + surname, as the roster and chat spell it"] = function(harness)
        withForever(harness, function(addon)
            harness.equal(addon.Api.GetPlayerInformation().name, ME)
            local roster = addon.Api.GetGuildRoster()
            harness.truthy(roster[ME], "me not in the canonical roster")
            harness.truthy(roster["Mira Holt-" .. REALM_N])
            harness.equal(addon.Utility.CanonicalName("Drakk Nuk"), ME)                         -- chat sender form
            harness.equal(addon.Utility.WhisperTarget("Mira Holt-" .. REALM_N), "Mira Holt")
        end)
    end,

    ["forever: 0.4.0 first-name keys map to the full name when unambiguous"] = function(harness)
        withForever(harness, function(addon)
            addon.Api.GetGuildRoster()
            harness.equal(addon.Utility.CanonicalName("Drakk-" .. REALM_N), ME)                  -- my own old key
            harness.equal(addon.Utility.CanonicalName("Mira-" .. REALM_N), "Mira Holt-" .. REALM_N)
            harness.equal(addon.Utility.CanonicalName("Tam-" .. REALM_N), "Tam-" .. REALM_N)     -- "Tam Reed" and "Tam Ash": ambiguous, left alone
            -- one Forever guild spans several realms and names carry none: another realm is the same member
            harness.equal(addon.Utility.CanonicalName("Mira-OtherRealm"), "Mira Holt-" .. REALM_N)
        end)
    end,

    ["forever: stored 0.4.0 data is moved to the full-name keys"] = function(harness)
        withForever(harness, function(addon)
            local S = addon.Store
            local old = "Drakk-" .. REALM_N
            S.db.me = old
            S.db.chars[old] = harness.character(old, 100, { 6499 })
            S.db.offers[old] = { name = old, rev = 5, items = { [777] = { bag = 1 } }, dibs = { ["Mira-" .. REALM_N .. ":12"] = { on = true, t = 1 } } }
            local o = addon.orders and nil
            S.db.orders["x"] = { id = old .. ":1:1", requester = old, recipeID = 6499, qty = 1, note = "", createdAt = 1, claims = {} }
            S.db.me = addon.Api.GetPlayerInformation().name
            addon.Api.GetGuildRoster()
            S.CanonicalizeStoredNames()
            harness.equal(S.db.me, ME)
            harness.equal(S.db.chars[old], nil); harness.equal(S.db.chars[ME].name, ME)
            harness.equal(S.db.offers[ME].name, ME)
            harness.truthy(S.db.offers[ME].dibs["Mira Holt-" .. REALM_N .. ":12"])
            harness.equal(S.db.orders["x"].requester, ME)
        end)
    end,

    ["forever: my own GUILD echo is recognised and never handled as another player"] = function(harness)
        withForever(harness, function(addon)
            addon.Store.db.me = addon.Api.GetPlayerInformation().name
            local C = addon.Communication
            C.salt, C.active, C.roster = 0x1a2b, true, addon.Api.GetGuildRoster()
            local handled = 0
            C.sync = { OnMessage = function() handled = handled + 1 return "ok" end, statistics = { sent = 0, received = 0, dropped = 0 } }
            local mine = addon.Codec.Header(("%04x%x"):format(C.salt, 3), 1, 1) .. addon.Codec.Encode({ t = "HELLO", rev = 1 })
            C.OnAddonMessage(addon.PREFIX, mine, "GUILD", "Drakk Nuk")
            harness.equal(handled, 0)
            harness.equal(C.lastEcho, "Drakk Nuk")
            -- even without the salt (an echo from a previous session) it is dropped as my own message
            local other = addon.Codec.Header("ffff1", 1, 1) .. addon.Codec.Encode({ t = "HELLO", rev = 1 })
            C.OnAddonMessage(addon.PREFIX, other, "GUILD", "Drakk Nuk")
            harness.equal(handled, 0)
        end)
    end,

    ["forever: requests and records between surname players pass, also from a 0.4.0 peer's record"] = function(harness)
        withForever(harness, function(addon)
            addon.Store.db.me = addon.Api.GetPlayerInformation().name
            addon.Api.GetGuildRoster()
            addon.orders = addon.Orders.New(function() return harness.clock end, addon.db.orders)
            addon.Store.PutCharacter(harness.character(ME, 50, { 6499 }))
            local sync = addon.Sync.New({ send = function() end, now = function() return harness.clock end, random = function() return 0 end,
                store = addon.Store, orders = addon.orders, me = function() return addon.Store.db.me end, onChange = function() end })
            local FLEXI = "Mira Holt-" .. REALM_N
            harness.equal((sync:OnMessage({ v = 2, t = "WANT", names = { ME } }, FLEXI)), "ok")
            harness.equal((sync:OnMessage({ v = 2, t = "WANT", names = { "Drakk-" .. REALM_N } }, FLEXI)), "ok")   -- a 0.4.0 peer asks this way
            local st = sync:OnMessage({ v = 2, t = "SNAP", char = harness.character("Mira-" .. REALM_N, 7, { 1 }), catalog = {} }, FLEXI)
            harness.equal(st, "ok"); harness.truthy(addon.Store.GetCharacter(FLEXI))
        end)
    end,

    ["forever: requests also carry the 0.4.0 first-name form, so members who did not update still answer"] = function(harness)
        withForever(harness, function(addon)
            addon.Store.db.me = addon.Api.GetPlayerInformation().name
            addon.Api.GetGuildRoster()
            local sent = {}
            local sync = addon.Sync.New({ send = function(msg, dist) sent[#sent + 1] = { msg = msg, dist = dist } end,
                now = function() return harness.clock end, random = function() return 0 end, store = addon.Store,
                orders = addon.Orders.New(function() return harness.clock end, {}), me = function() return addon.Store.db.me end, onChange = function() end })
            local FLEXI = "Mira Holt-" .. REALM_N
            sync:OnMessage({ v = 2, t = "HELLO", rev = 50, orev = 9 }, FLEXI)
            harness.equal(sent[1].msg.t, "WANT"); harness.equal(sent[1].msg.names[1], FLEXI); harness.equal(sent[1].msg.names[2], "Mira-" .. REALM_N)
            harness.equal(sent[2].msg.t, "WANTO"); harness.equal(sent[2].msg.names[2], "Mira-" .. REALM_N)
            -- a 0.4.0 member compares each name with its own first-name key: one of them matches
            local matches040 = false
            for _, n in ipairs(sent[1].msg.names) do if n == "Mira-" .. REALM_N then matches040 = true end end
            harness.truthy(matches040)
            -- the GUILD retry carries both forms too
            sync:Tick(harness.clock + 45)
            harness.equal(sent[#sent].dist, "GUILD"); harness.equal(#sent[#sent].msg.names, 2)
            -- shared first name ("Tam Reed", "Tam Ash"): no first-name form, both would answer
            harness.equal(addon.Utility.LegacyName("Tam Reed-" .. REALM_N), nil)
            harness.equal(#addon.Sync.AskNames("Tam Reed-" .. REALM_N), 1)
            -- no surname (normal WoW): unchanged
            harness.equal(addon.Utility.LegacyName("Thrall-" .. REALM_N), nil)
            -- a 0.4.1 member receiving both forms answers once
            addon.Store.PutCharacter(harness.character(ME, 60, { 1 }))
            local before = #sync.pending
            harness.equal((sync:OnMessage({ v = 2, t = "WANT", names = { ME, "Drakk-" .. REALM_N } }, FLEXI)), "ok")
            harness.equal(#sync.pending, before + 1)
        end)
    end,

    -- second export (2026-11-16, live 0.4.1): the guild spans "CAMWOW EU4 Realm 1/3/5 PvE" and "CAMWOW EU5 Realm 3 PvE";
    -- every client appended its own realm, so "Drakk Nuk-...Realm3" (asked by Mira) never matched "Drakk Nuk-...Realm5"
    ["forever: members on other realms of the guild are the same members (realm is not part of the name)"] = function(harness)
        withForever(harness, function(addon)
            addon.Store.db.me = addon.Api.GetPlayerInformation().name
            addon.Api.GetGuildRoster()
            local U = addon.Utility
            harness.equal(U.CanonicalName("Drakk Nuk-CAMWOWEU4Realm3PvE"), ME)
            harness.equal(U.CanonicalName("Drakk Nuk-CAMWOWEU5Realm3PvE"), ME)
            harness.equal(U.CanonicalName("Mira-CAMWOWEU4Realm3PvE"), "Mira Holt-" .. REALM_N)   -- a 0.4.0 key from another realm
            harness.equal(U.CanonicalName("Tam-CAMWOWEU4Realm1PvE"), "Tam-" .. REALM_N)             -- ambiguous first name: realm only
            harness.equal(U.WhisperTarget("Mira Holt-CAMWOWEU4Realm3PvE"), "Mira Holt")
            -- stored orders from other realms move to the one key
            addon.Store.db.orders["o"] = { id = "Orin-CAMWOWEU4Realm3PvE:1:1", requester = "Orin-CAMWOWEU4Realm3PvE",
                recipeID = 4094, qty = 1, note = "", createdAt = 1, claims = {} }
            addon.Store.CanonicalizeStoredNames()
            harness.equal(addon.Store.db.orders["o"].requester, "Orin-" .. REALM_N)
        end)
    end,

    ["forever: requests from other realms are answered, in the spelling a 0.4.0 member accepts"] = function(harness)
        withForever(harness, function(addon)
            addon.Store.db.me = addon.Api.GetPlayerInformation().name
            addon.Api.GetGuildRoster()
            addon.Store.PutCharacter(harness.character(ME, 50, { 6499 }))
            addon.Offers.Put({ name = ME, rev = 7, items = { [777] = { bag = 1 } }, dibs = {} })
            local sent = {}
            local sync = addon.Sync.New({ send = function(msg, dist, target) sent[#sent + 1] = { msg = msg, dist = dist, to = target } end,
                now = function() return harness.clock end, random = function() return 0 end, store = addon.Store,
                orders = addon.Orders.New(function() return harness.clock end, {}), me = function() return addon.Store.db.me end, onChange = function() end })
            local FLEXI = "Mira Holt-" .. REALM_N
            -- 0.4.0 member on Realm3 (exactly what the export showed)
            harness.equal((sync:OnMessage({ v = 2, t = "WANT", names = { "Drakk Nuk-CAMWOWEU4Realm3PvE" } }, FLEXI)), "ok")
            harness.equal((sync:OnMessage({ v = 2, t = "WANTO", names = { "Drakk Nuk-CAMWOWEU4Realm3PvE" } }, FLEXI)), "ok")
            -- 0.4.1 member on EU5 Realm3 (full name + first-name form)
            harness.equal((sync:OnMessage({ v = 2, t = "WANT", names = { "Drakk Nuk-CAMWOWEU5Realm3PvE", "Drakk-CAMWOWEU5Realm3PvE" } },
                "Kael Stone-" .. REALM_N)), "ok")
            sync:Tick(harness.clock + 5)
            local snap, offers, snap2
            for _, s in ipairs(sent) do
                if s.msg.t == "SNAP" and s.to == FLEXI then snap = s.msg end
                if s.msg.t == "OFFERS" and s.to == FLEXI then offers = s.msg end
                if s.msg.t == "SNAP" and s.to ~= FLEXI then snap2 = s.msg end
            end
            harness.truthy(snap and offers and snap2, "not every request was answered")
            -- a 0.4.0 member compares the record name with the sender as IT spells it: "Drakk Nuk-<its realm>"
            harness.equal(snap.char.name, "Drakk Nuk-CAMWOWEU4Realm3PvE")
            harness.equal(offers.offers.name, "Drakk Nuk-CAMWOWEU4Realm3PvE")
            harness.equal(addon.Store.GetCharacter(ME).name, ME)   -- my stored record keeps its own key
            -- requests to that member now also carry the first name in its realm (the only name a 0.4.0 client answers)
            sync:OnMessage({ v = 2, t = "HELLO", rev = 99, orev = 9 }, FLEXI)
            local want = sent[#sent - 1].msg
            harness.equal(want.t, "WANT")
            local hasThere = false
            for _, n in ipairs(want.names) do if n == "Mira-CAMWOWEU4Realm3PvE" then hasThere = true end end
            harness.truthy(hasThere, "no Mira-<its realm> in " .. table.concat(want.names, ","))
            -- its answer: record "Mira-CAMWOWEU4Realm3PvE" from sender "Mira Holt" is accepted
            harness.equal((sync:OnMessage({ v = 2, t = "SNAP", char = harness.character("Mira-CAMWOWEU4Realm3PvE", 99, { 1 }), catalog = {} }, FLEXI)), "ok")
            harness.truthy(addon.Store.GetCharacter(FLEXI))
        end)
    end,

    ["forever: the name check shows the surname case as OK"] = function(harness)
        withForever(harness, function(addon)
            addon.Store.db.me = addon.Api.GetPlayerInformation().name
            local roster = addon.Api.GetGuildRoster()
            local info = addon.Api.IdentityInformation()
            harness.equal(info.rosterMe, "Drakk Nuk")
            for _, r in ipairs(addon.Diagnostics.IdentityRows({ identity = info, me = addon.db.me, roster = roster, echo = "Drakk Nuk",
                seen = { ["Mira Holt-" .. REALM_N] = "Mira Holt" } })) do
                harness.truthy(r.status == "ok" or r.status == "info" or r.status == "fixed", r.method .. " = " .. r.status .. " (" .. r.value .. ")")
            end
        end)
    end,
}
