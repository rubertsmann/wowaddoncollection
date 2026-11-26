-- Which spell a profession button casts (Core/Data/ProfessionSpells.lua, Model.OpenAction): the window spell by id,
-- never a spellbook spell by name.

local SKINNING, LEATHERWORKING, COOKING, ALCHEMY = 393, 165, 185, 171

return {
    ["profession spells: the window spells read in game, by skill line"] = function(harness)
        local PS = harness.addon().ProfessionSpells
        harness.equal(PS.WindowSpellID(SKINNING), 1240974)
        harness.equal(PS.WindowSpellID(LEATHERWORKING), 1240961)
        harness.equal(PS.WindowSpellID(COOKING), 1240956)
        harness.equal(PS.WindowSpellID(ALCHEMY), nil, "not read in game yet: cast by name")
        harness.equal(PS.WindowSpellID(nil), nil)
    end,

    ["profession spells: the button casts by id, the same in every language; unknown professions cast their name"] = function(harness)
        local M = harness.addon().Model
        local german = M.OpenAction({ id = SKINNING, spellName = "Kürschnerei", spells = { "Sonnen", "Kürschnerei" } })
        local english = M.OpenAction({ id = SKINNING, spellName = "Skinning", spells = { "Skinning", "Camp" } })
        harness.equal(german.type, "spell"); harness.equal(german.spell, 1240974); harness.equal(german.macrotext, nil)
        harness.equal(english.spell, german.spell, "names do not matter")
        harness.equal(M.DescribeOpenAction(german), "spell 1240974 (static)")
        local alchemy = M.OpenAction({ id = ALCHEMY, spellName = "Alchimie", spells = { "Alchimie" } })
        harness.equal(alchemy.type, "macro"); harness.equal(alchemy.macrotext, "/cast Alchimie"); harness.equal(alchemy.spell, nil)
        harness.equal(M.DescribeOpenAction(alchemy), "macro /cast Alchimie")
    end,

    ["profession spells: own window spells are noted, bounded and encoded for the HELLO"] = function(harness)
        local PS = harness.addon().ProfessionSpells
        local own = {}
        harness.equal(PS.Encode(own), nil, "nothing to report")
        harness.equal(PS.Note(own, SKINNING, 1240974), true)
        harness.equal(PS.Note(own, SKINNING, 1240974), false, "already noted")
        harness.equal(PS.Note(own, LEATHERWORKING, 1240961), true)
        harness.equal(PS.Note(own, LEATHERWORKING, 3104), true, "a spellbook rank that opened the window too")
        harness.equal(PS.Encode(own), "165:1240961,165:3104,393:1240974")
        harness.equal(PS.Note(own, "x", 5), false); harness.equal(PS.Note(own, 5, 1.5), false); harness.equal(PS.Note(own, -1, 5), false)
        for spellID = 1, 10 do PS.Note(own, ALCHEMY, spellID) end
        local alchemySpells = 0 for _ in pairs(own[ALCHEMY]) do alchemySpells = alchemySpells + 1 end
        harness.equal(alchemySpells, PS.MAXIMUM_SPELLS_PER_SKILL_LINE)
        local many = {}
        for skillLine = 1, 40 do PS.Note(many, skillLine, 1240000 + skillLine) end
        harness.truthy(#PS.Encode(many) <= PS.MAXIMUM_WIRE_LENGTH, "the HELLO field stays short")
    end,

    ["profession spells: a peer's field is decoded only when it is a short list of number pairs"] = function(harness)
        local PS = harness.addon().ProfessionSpells
        local decoded = PS.Decode("165:1240961,393:1240974")
        harness.equal(#decoded, 2); harness.equal(decoded[2][1], 393); harness.equal(decoded[2][2], 1240974)
        harness.equal(PS.Decode(nil), nil); harness.equal(PS.Decode(""), nil); harness.equal(PS.Decode(5), nil)
        harness.equal(PS.Decode("165:x"), nil); harness.equal(PS.Decode("|cff165:1"), nil)
        harness.equal(PS.Decode("1:999999999999"), nil, "ids out of range")
        harness.equal(PS.Decode(string.rep("1:2,", 60)), nil, "too long")
    end,

    ["profession spells: the developer's collection counts members and compares with the table"] = function(harness)
        local PS = harness.addon().ProfessionSpells
        local reports = {}
        harness.equal(PS.AddReport(reports, PS.Decode("393:1240974,171:1240950"), "A", 10), true)
        harness.equal(PS.AddReport(reports, PS.Decode("393:1240974"), "A", 11), false, "the same member again adds nothing")
        harness.equal(PS.AddReport(reports, PS.Decode("393:1240974,185:3102"), "B", 12), true)
        local rows = PS.ReportRows(reports)
        harness.equal(#rows, 3)
        harness.equal(rows[1].skillLine, ALCHEMY); harness.equal(rows[1].static, "new"); harness.equal(rows[1].reporters, 1)
        harness.equal(rows[2].skillLine, COOKING); harness.equal(rows[2].static, "other")
        harness.equal(rows[3].skillLine, SKINNING); harness.equal(rows[3].static, "same"); harness.equal(rows[3].reporters, 2)
        harness.equal(PS.AddReport(nil, {}, "A", 1), false)
    end,

    ["profession spells: the window spells travel in the HELLO and reach the reader's callback"] = function(harness)
        local queue, received = {}, {}
        local function newPeer(name, environmentExtras)
            local addon = harness.addon()
            addon.Store.db.me = name
            local environment = { send = function(message, channel, target) queue[#queue + 1] = { from = name, msg = message } end,
                now = function() return harness.clock end, random = function() return 0.5 end, store = addon.Store,
                orders = addon.Orders.New(function() return harness.clock end, addon.db.orders), me = name, onChange = function() end }
            for key, value in pairs(environmentExtras) do environment[key] = value end
            return addon, addon.Sync.New(environment)
        end
        local senderAddon, senderSync = newPeer("A-R", { windowSpells = function() return "393:1240974" end })
        local readerAddon, readerSync = newPeer("B-R", { onWindowSpells = function(sender, decoded) received[#received + 1] = { sender, decoded } end })
        senderSync:Hello(false)
        local hello
        for _, item in ipairs(queue) do if item.msg.t == "HELLO" then hello = item.msg end end
        harness.equal(hello and hello.wsp, "393:1240974")
        readerSync:OnMessage(assert(readerAddon.Codec.Decode(senderAddon.Codec.Encode(hello))), "A-R")
        harness.equal(#received, 1); harness.equal(received[1][1], "A-R"); harness.equal(received[1][2][1][2], 1240974)
        hello.wsp = "garbage"
        readerSync:OnMessage(assert(readerAddon.Codec.Decode(senderAddon.Codec.Encode(hello))), "A-R")
        harness.equal(#received, 1, "an invalid field is ignored")
    end,
}
