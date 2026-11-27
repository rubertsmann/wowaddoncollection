-- Companion nicknames and catch origin: a nickname per roster companion (display only, ids stay the reference), when
-- and where it was caught (server time and uiMapID), kept through the load-time sanitizer, sent to the guild as `nk`
-- (cleaned on receipt), never part of the fight.
local NOW = 1794873600
local ME = "Me-R"

local function fresh(harness)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = ME
    addon.AzeCaught.throws, addon.AzeCaught.rolled, addon.AzeCaught.thrown, addon.AzeCaught.lastThrowAt = {}, {}, {}, nil
    addon.AzeCaught.again, addon.AzeCaught.forceNextCatch = {}, false
    addon.AzeCaught.State().firstCatchDone = true
    return addon
end

-- catches NPC `npc` once through the real throw and roll, on map `map`
local function catch(addon, npc, serial, map, at)
    local AzeCaught = addon.AzeCaught
    local guid = ("Creature-0-1-2-3-%d-%08X"):format(npc, serial)
    AzeCaught.lastThrowAt = nil
    assert(AzeCaught.Throw({ guid = guid, health = 0.1, name = "Npc" .. npc, level = 10, map = map }, 10, serial * 10, at or NOW))
    AzeCaught.forceNextCatch = true
    local result = AzeCaught.OnDeath(guid, ME, serial * 10 + 1, at or NOW, function() return 0.99 end)
    assert(result and result.caught, "caught")
    return result
end

local function reload(addon)
    local saved = addon.Utility.DeepCopy(addon.Store.db)
    addon.AzeCaught.SanitizePersisted(saved)
    addon.Store.db.caught = saved.caught
    return saved.caught
end

return {
    ["nickname: input is trimmed, spaces collapsed, | and control characters removed; empty clears"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        harness.equal(AzeCaught.NormalizeNickname("  Mr   Fluffy \t"), "Mr Fluffy")
        harness.equal(AzeCaught.NormalizeNickname("|cffff0000Red|r"), "cffff0000Redr")
        harness.equal(AzeCaught.NormalizeNickname("A\1B\127C"), "ABC")
        harness.equal(AzeCaught.NormalizeNickname("   "), "")
        local _, reason = AzeCaught.NormalizeNickname(42)
        harness.equal(reason, "invalid")
        _, reason = AzeCaught.NormalizeNickname("\255\254")
        harness.equal(reason, "invalid")
    end,

    ["nickname: 24 characters, counted as characters not bytes"] = function(harness)
        local AzeCaught = fresh(harness).AzeCaught
        harness.equal(AzeCaught.NormalizeNickname(("a"):rep(24)), ("a"):rep(24))
        local _, reason = AzeCaught.NormalizeNickname(("a"):rep(25))
        harness.equal(reason, "toolong")
        local umlauts = ("ü"):rep(24)   -- 48 bytes, 24 characters
        harness.equal(AzeCaught.NormalizeNickname(umlauts), umlauts)
        _, reason = AzeCaught.NormalizeNickname(umlauts .. "ö")
        harness.equal(reason, "toolong")
        local emoji = ("\240\159\144\186"):rep(24)   -- 96 bytes, the byte limit
        harness.equal(AzeCaught.CleanNickname(emoji), emoji)
    end,

    ["nickname: set once on one companion by uid; the other companion of the same NPC keeps its own"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local first = catch(addon, 4711, 1)
        local second = catch(addon, 4711, 2)
        harness.truthy(first.uid and second.uid and first.uid ~= second.uid, "each catch reports its own uid")
        harness.equal(AzeCaught.SetNickname(second.uid, " Rex "), "Rex")
        harness.equal(AzeCaught.ShownName(AzeCaught.Companion(second.uid)), "Rex")
        harness.equal(AzeCaught.ShownName(AzeCaught.Companion(first.uid)), "Npc4711")
        harness.equal(AzeCaught.SpeciesName(AzeCaught.Companion(second.uid)), "Npc4711")
        harness.truthy(AzeCaught.HasNickname(AzeCaught.Companion(second.uid)), "has a nickname")
        harness.truthy(AzeCaught.CanRename(AzeCaught.Companion(first.uid)), "the other one can still be named")
        harness.truthy(not AzeCaught.CanRename(AzeCaught.Companion(second.uid)), "named once")
    end,

    ["nickname: only once; a second name or an empty one is refused and the first stays"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1)
        local _, reason = AzeCaught.SetNickname(result.uid, "   ")
        harness.equal(reason, "empty")
        harness.truthy(AzeCaught.CanRename(AzeCaught.Companion(result.uid)), "an empty try does not use it up")
        harness.equal(AzeCaught.SetNickname(result.uid, "Rex"), "Rex")
        _, reason = AzeCaught.SetNickname(result.uid, "Max")
        harness.equal(reason, "named")
        harness.equal(AzeCaught.ShownName(AzeCaught.Companion(result.uid)), "Rex")
        harness.truthy(not AzeCaught.CanRename(nil), "no companion, no rename")
    end,

    ["nickname: the dev clear frees it again and keeps the catch origin"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1, 1429)
        AzeCaught.SetNickname(result.uid, "Rex")
        harness.truthy(AzeCaught.ClearNickname(result.uid), "cleared")
        local companion = AzeCaught.Companion(result.uid)
        harness.truthy(AzeCaught.CanRename(companion), "free again")
        harness.equal(AzeCaught.ShownName(companion), "Npc4711")
        harness.equal(select(2, AzeCaught.CatchOrigin(companion)), 1429)
    end,

    ["nickname: refusals for an unknown uid, read-only data and too long text; nothing changes"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1)
        local _, reason = AzeCaught.SetNickname("u999", "X")
        harness.equal(reason, "unknown")
        _, reason = AzeCaught.SetNickname(result.uid, ("x"):rep(25))
        harness.equal(reason, "toolong")
        addon.Store.db.readonly = true
        _, reason = AzeCaught.SetNickname(result.uid, "X")
        harness.equal(reason, "readonly")
        addon.Store.db.readonly = nil
        harness.truthy(not AzeCaught.HasNickname(AzeCaught.Companion(result.uid)), "unchanged")
    end,

    ["two companions with the same nickname stay apart: select and release act on the uid"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local first = catch(addon, 4711, 1)
        local second = catch(addon, 555, 2)
        AzeCaught.SetNickname(first.uid, "Twin")
        AzeCaught.SetNickname(second.uid, "Twin")
        assert(AzeCaught.Select(second.uid, NOW))
        harness.equal(AzeCaught.Active().uid, second.uid)
        assert(AzeCaught.Release(first.uid))
        harness.truthy(AzeCaught.Companion(first.uid) == nil, "the first is gone")
        harness.equal(AzeCaught.ShownName(AzeCaught.Companion(second.uid)), "Twin")
    end,

    ["catch origin: time and map are stamped on the caught companion only"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local first = catch(addon, 4711, 1, 1429, NOW)
        local second = catch(addon, 4711, 2, 1411, NOW + 500)
        local at, map = AzeCaught.CatchOrigin(AzeCaught.Companion(first.uid))
        harness.equal(at, NOW); harness.equal(map, 1429)
        at, map = AzeCaught.CatchOrigin(AzeCaught.Companion(second.uid))
        harness.equal(at, NOW + 500); harness.equal(map, 1411)
    end,

    ["catch origin: an unknown map still catches; the time is kept"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1, nil)
        local at, map = AzeCaught.CatchOrigin(AzeCaught.Companion(result.uid))
        harness.equal(at, NOW); harness.equal(map, nil)
        result = catch(addon, 555, 2, "garbage")
        at, map = AzeCaught.CatchOrigin(AzeCaught.Companion(result.uid))
        harness.equal(at, NOW); harness.equal(map, nil)
    end,

    ["catch origin: a trap catch records it too"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local trap = addon.Items.Get("trap")
        local result = assert(AzeCaught.TrapCatch({ guid = "Creature-0-1-2-3-4711-00000009", health = 0.9, name = "Wolf", level = 5,
            classification = "normal", map = 1429 }, trap, ME, 1, NOW))
        local at, map = AzeCaught.CatchOrigin(AzeCaught.Companion(result.uid))
        harness.equal(at, NOW); harness.equal(map, 1429)
    end,

    ["companions from before the origin was recorded have none (no guess from the species)"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1, 1429)
        AzeCaught.Companion(result.uid).info = nil
        local caught = reload(addon)
        local companion = caught.roster[result.uid]
        harness.truthy(companion, "still there")
        harness.equal(companion.info, nil)
        harness.equal(AzeCaught.CatchOrigin(companion), nil)
    end,

    ["the load-time sanitizer keeps nickname and origin; garbage is dropped alone"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1, 1429)
        local other = catch(addon, 555, 2, 1411)
        AzeCaught.SetNickname(result.uid, "Rex")
        AzeCaught.Companion(other.uid).info = { nick = "|TInterface\\Icons\\X:16|t", at = "soon", map = 1411 }
        local caught = reload(addon)
        harness.equal(caught.roster[result.uid].info.nick, "Rex")
        harness.equal(caught.roster[result.uid].info.at, NOW)
        harness.equal(caught.roster[result.uid].info.map, 1429)
        local otherInfo = caught.roster[other.uid].info
        harness.equal(otherInfo.nick, nil); harness.equal(otherInfo.at, nil); harness.equal(otherInfo.map, 1411)
        harness.equal(caught.active and caught.active.uid, AzeCaught.Active().uid)
    end,

    ["roster order uses the shown name, ties by uid"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local a = catch(addon, 100, 1)   -- active (first catch)
        local b = catch(addon, 200, 2)
        local c = catch(addon, 300, 3)
        AzeCaught.SetNickname(c.uid, "aardvark")
        local roster = AzeCaught.Roster()
        harness.equal(roster[1].uid, a.uid)
        harness.equal(roster[2].uid, c.uid)
        harness.equal(roster[3].uid, b.uid)
    end,

    ["guild section: the active companion's nickname goes out as nk; a bad nk is dropped alone"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught = addon.AzeCaught
        local result = catch(addon, 4711, 1, 1429)
        AzeCaught.SetNickname(result.uid, "Rex")
        local section = AzeCaught.BuildSection()
        harness.equal(section.c.nk, "Rex")
        harness.equal(section.c.n, "Npc4711")
        harness.equal(section.c.at, nil)   -- the origin stays mine
        harness.equal(section.c.map, nil)
        local clean = AzeCaught.SanitizeSection(section, math.huge)
        harness.equal(clean.c.nk, "Rex")
        section.c.nk = ("x"):rep(500)
        clean = AzeCaught.SanitizeSection(section, math.huge)
        harness.truthy(clean and clean.c, "the companion survives")
        harness.equal(clean.c.nk, nil)
    end,

    ["arena: a fighter carries nk; a peer's bad nk is dropped without dropping the fighter; the fight ignores it"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught, Arena = addon.AzeCaught, addon.Arena
        local result = catch(addon, 4711, 1)
        AzeCaught.SetNickname(result.uid, "Rex")
        local fighter = Arena.Fighter(AzeCaught.Companion(result.uid))
        harness.equal(fighter.nk, "Rex")
        harness.equal(fighter.n, "Npc4711")
        harness.equal(Arena.SanitizeFighter(fighter).nk, "Rex")
        local bad = addon.Utility.DeepCopy(fighter)
        bad.nk = "|Hitem:1|h[Sword]|h"
        local clean = Arena.SanitizeFighter(bad)
        harness.truthy(clean, "the fighter survives")
        harness.equal(clean.nk, nil)
        -- the TLevel rides along (display only): kept when sane, a bad one is dropped alone
        harness.equal(fighter.tl, AzeCaught.CompanionLevel(AzeCaught.Companion(result.uid)))
        harness.equal(Arena.SanitizeFighter(fighter).tl, fighter.tl)
        local badLevel = addon.Utility.DeepCopy(fighter); badLevel.tl = "lots"
        local cleanLevel = Arena.SanitizeFighter(badLevel)
        harness.truthy(cleanLevel, "the fighter survives a bad TLevel"); harness.equal(cleanLevel.tl, nil)
        local plain = addon.Utility.DeepCopy(fighter); plain.nk = nil
        local other = addon.Utility.DeepCopy(fighter); other.nk = nil; other.atk = other.atk + 3
        local named = addon.Utility.DeepCopy(fighter)
        local first = Arena.Fight({ plain, plain, plain }, { other, other, other }, "X-R#1")
        local second = Arena.Fight({ named, named, named }, { other, other, other }, "X-R#1")
        harness.equal(first.winner, second.winner)
        harness.equal(#first.events, #second.events)
    end,

    ["roster rows: the nickname is the name, the species and the catch origin come along"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught, Model = addon.AzeCaught, addon.Model
        local result = catch(addon, 4711, 1, 1429)
        AzeCaught.SetNickname(result.uid, "Rex|")   -- the bar is removed
        local rows = Model.BuildRosterRows(AzeCaught.Roster(), AzeCaught.State().collection, AzeCaught.Active())
        harness.equal(rows[1].name, "Rex")
        harness.equal(rows[1].nameKey, "rex")
        harness.equal(rows[1].species, "Npc4711")
        harness.truthy(rows[1].nicknamed, "nicknamed")
        harness.equal(rows[1].caughtAt, NOW)
        harness.equal(rows[1].caughtMap, 1429)
    end,

    ["guild rows: a peer's nickname shows, the species comes from the NPC id; both escaped"] = function(harness)
        local addon = fresh(harness)
        local AzeCaught, Model = addon.AzeCaught, addon.Model
        catch(addon, 4711, 1)
        local records = { ["Peer-R"] = { caught = { weeks = {}, c = { npc = 4711, n = "Other|name", nk = "Fang", lvl = 5, cls = "normal",
            disp = 0, h = 0, hu = 50, th = 50, af = 50, en = 50 } } } }
        local rows = Model.BuildCompanionRows(records, ME)
        local peer
        for _, row in ipairs(rows) do if row.nameRaw == "Peer-R" then peer = row end end
        harness.equal(peer.companion, "Fang")
        harness.equal(peer.species, "Npc4711")   -- from my collection by id, not the text the peer sent
        harness.truthy(peer.nicknamed, "nicknamed")
        records["Peer-R"].caught.c.npc, records["Peer-R"].caught.c.nk = 999, "a|b"
        for _, row in ipairs(Model.BuildCompanionRows(records, ME)) do if row.nameRaw == "Peer-R" then peer = row end end
        harness.equal(peer.companion, "a||b")
        harness.equal(peer.species, "Other||name")
    end,

    ["origin text: date and zone, date only, or not recorded"] = function(harness)
        local addon = fresh(harness)
        local Model = addon.Model
        local function formatDate(format, time) return format .. "@" .. time end
        harness.equal(Model.CatchOriginText(NOW, "Elwynn|Forest", formatDate), "Caught %Y-%m-%d@" .. NOW .. " in Elwynn||Forest")
        harness.equal(Model.CatchOriginText(NOW, nil, formatDate), "Caught %Y-%m-%d@" .. NOW)
        harness.equal(Model.CatchOriginText(nil, "Elwynn Forest", formatDate), "Caught: before this was recorded")
    end,

    ["fight history keeps NPC ids and nicknames; old rows without them still load"] = function(harness)
        local addon = fresh(harness)
        local caught = addon.AzeCaught.State()
        caught.arena = { history = {
            { id = "A-R#1", opp = "B-R", me = "Wolf", them = "Boar", won = true, wg = 10000, t = NOW, mi = 299, mk = "Rex", ti = 1984, tk = "|cffbad" },
            { id = "A-R#0", opp = "B-R", me = "Wolf", them = "Boar", won = false, wg = 10000, t = NOW - 10 } } }
        addon.Arena.SanitizePersisted(caught, ME)
        local history = caught.arena.history
        harness.equal(#history, 2)
        harness.equal(history[1].mi, 299); harness.equal(history[1].mk, "Rex")
        harness.equal(history[1].ti, 1984); harness.equal(history[1].tk, nil)
        harness.equal(history[2].mi, nil); harness.equal(history[2].me, "Wolf")
    end,
}
