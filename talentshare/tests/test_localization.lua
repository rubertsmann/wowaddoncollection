-- Feature 002: names are resolved for the viewer, text is UTF-8 safe, mixed-language guilds converge
local function prof(name, id, loc, recipes, rank)
    local set = {}
    for _, r in ipairs(recipes) do set[r] = true end
    return { name = name, id = id, loc = loc, rank = rank or 100, max = 150, recipes = set }
end

local function char(name, rev, profs)
    return { name = name, class = "MAGE", level = 60, rev = rev, professions = profs }
end

local function viewer(harness, code, spell)
    local addon = harness.addon()
    addon.Locale.clientCode, addon.Locale.code = code, code
    addon.Names.environment.spellName = spell
    return addon
end

return {
    ["utf8: IsValidUtf8 accepts real text and rejects malformed sequences"] = function(harness)
        local U = harness.addon().Utility
        for _, ok in ipairs({ "", "abc", "Kürschnerei", "Кулинария", "烹饪", "😀" }) do harness.truthy(U.IsValidUtf8(ok), ok) end
        for _, bad in ipairs({ "\128", "\194", "\192\128", "\237\160\128", "\244\144\128\128", "a\255", "\226\130" }) do
            harness.equal(U.IsValidUtf8(bad), false, "accepted malformed " .. #bad .. " bytes")
        end
        harness.equal(U.IsValidUtf8(5), false)
    end,

    ["utf8: TruncateUtf8 never cuts inside a character (RF2)"] = function(harness)
        local U = harness.addon().Utility
        harness.equal(U.TruncateUtf8("abc", 5), "abc")
        harness.equal(U.TruncateUtf8("aé", 2), "a")        -- é is 2 bytes
        harness.equal(U.TruncateUtf8("aé", 3), "aé")
        harness.equal(U.TruncateUtf8("烹饪", 4), "烹")      -- 3 bytes each
        harness.equal(U.TruncateUtf8("😀😀", 5), "😀")
        for n = 0, 12 do
            local t = U.TruncateUtf8("äö烹饪😀x", n)
            harness.truthy(#t <= n and U.IsValidUtf8(t), "bad cut at " .. n)
        end
    end,

    ["utf8: Fold and SearchKey ignore case and accents (R6)"] = function(harness)
        local U = harness.addon().Utility
        harness.equal(U.FoldCase("KÜRSCHNEREI"), "kürschnerei")
        harness.equal(U.FoldCase("ÄÖÜ ÀÉ"), "äöü àé")
        harness.equal(U.SearchKey("Kürschnerei"), U.SearchKey("KURSCHNEREI"))
        harness.equal(U.SearchKey("Straße"), "strasse")
        harness.equal(U.SearchKey("КУЛИНАРИЯ"), U.SearchKey("кулинария"))
        harness.equal(U.SearchKey("Ёлка"), U.SearchKey("елка"))
        harness.equal(U.SearchKey("烹饪"), "烹饪")                    -- CJK is untouched
        harness.truthy(U.SearchKey("Äpfel") < U.SearchKey("Birne"), "ä must sort with a")
    end,

    ["locale: missing translations and unknown locales fall back to English, never nil (RF3)"] = function(harness)
        local addon = harness.addon()
        harness.equal(addon.Text["Recipes"], "Recipes")
        addon.Locale.SetInterfaceLanguage("deDE")
        harness.equal(addon.Text["Recipes"], "Rezepte")
        harness.equal(addon.Text["not translated anywhere"], "not translated anywhere")
        addon.Locale.SetInterfaceLanguage("xxXX")
        harness.equal(addon.Text["Recipes"], "Recipes")
        addon.Locale.SetInterfaceLanguage(nil)
        harness.equal(addon.Locale.code, addon.Locale.clientCode)
    end,

    ["locale: Fmt fills named placeholders and Plural picks one/many"] = function(harness)
        local addon = harness.addon()
        harness.equal(addon.Locale.Format("{a}-{b}-{a}", { a = 1, b = "x" }), "1-x-1")
        harness.equal(addon.Locale.Format("{missing}", {}), "{missing}")
        harness.equal(addon.Locale.Plural(1, "{n} recipe", "{n} recipes"), "1 recipe")
        harness.equal(addon.Locale.Plural(0, "{n} recipe", "{n} recipes"), "0 recipes")
        harness.equal(addon.Locale.Plural(7, "{n} recipe", "{n} recipes"), "7 recipes")
    end,

    ["names: ProfKey merges German, English and 0.1.0 name-key records (RF1)"] = function(harness)
        local addon = viewer(harness, "enUS")
        local N = addon.Names
        local a = N.ProfessionKey("Kochkunst", { name = "Kochkunst" })                   -- 0.1.0 record, no id
        local b = N.ProfessionKey("Cooking", { name = "Cooking" })
        local c = N.ProfessionKey("Kochkunst", { name = "Kochkunst", id = 185, loc = "deDE" })
        harness.equal(a, 185); harness.equal(b, 185); harness.equal(c, 185)
        harness.equal(N.ProfessionKey("Totally Unknown", { name = "Totally Unknown" }), "n:totally unknown")
        harness.equal(N.ProfessionKey("KOCHKUNST", { name = "KOCHKUNST" }), 185, "case-insensitive reverse lookup")
    end,

    ["names: profession display follows the viewer's language (R2)"] = function(harness)
        local entryDe = { name = "Kochkunst", id = 185, loc = "deDE" }
        local en = viewer(harness, "enUS")
        harness.equal(en.Names.Profession(185, entryDe), "Cooking")                          -- static English table beats a German snapshot
        local de = viewer(harness, "deDE")
        harness.equal(de.Names.Profession(185, { name = "Cooking", id = 185, loc = "enUS" }), "Kochkunst")
        local fr = viewer(harness, "frFR")
        harness.equal(fr.Names.Profession(185, { name = "Cuisine", id = 185, loc = "frFR" }), "Cuisine")   -- own-language snapshot
        harness.equal(fr.Names.Profession(185, { name = "Kochkunst", id = 185, loc = "deDE" }), "Cooking") -- English fallback, not German
        harness.equal(fr.Names.Profession(999, { name = "Kochkunst", id = 999, loc = "deDE" }), "Kochkunst")
        harness.equal(fr.Names.Profession(999, nil), "Profession #999")
    end,

    ["names: a name learned from the viewer's own client wins and is persisted per locale"] = function(harness)
        local addon = viewer(harness, "frFR")
        addon.Names.Learn(185, "Cuisine")
        harness.equal(addon.Names.Profession(185, { name = "Kochkunst", id = 185, loc = "deDE" }), "Cuisine")
        harness.equal(addon.db.profNames.frFR[185], "Cuisine")
        harness.equal(addon.Names.ProfessionKey("Cuisine", { name = "Cuisine" }), 185, "learned names feed the reverse lookup")
        addon.Names.Learn("x", "y"); addon.Names.Learn(5, "")                              -- ignored
        harness.equal(addon.db.profNames.frFR[5], nil)
    end,

    ["names: recipe name uses the viewer's spell name unless the snapshot is in the viewer's language (R3)"] = function(harness)
        local spell = function(id) return id == 7 and "Gebratener Eber" or nil end
        local de = viewer(harness, "deDE", spell)
        harness.equal(de.Names.Recipe(7, { name = "Roast Boar", loc = "enUS" }), "Gebratener Eber")
        harness.equal(de.Names.Recipe(7, { name = "Eber (alt)", loc = "deDE" }), "Eber (alt)")
        harness.equal(de.Names.Recipe(8, { name = "Roast Boar", loc = "enUS" }), "Roast Boar")      -- no spell data: snapshot
        harness.equal(de.Names.Recipe(9, nil), "Rezept #9")
        de.Locale.SetInterfaceLanguage("enUS")
        harness.equal(de.Names.Recipe(9, nil), "Recipe #9")
    end,

    ["model: mixed-language guild shows ONE Cooking entry, in the viewer's language (RF1)"] = function(harness)
        local addon = viewer(harness, "enUS")
        addon.Store.PutCharacter(char("De-R", 1, { Kochkunst = prof("Kochkunst", 185, "deDE", { 1, 2 }) }))
        addon.Store.PutCharacter(char("En-R", 1, { Cooking = prof("Cooking", 185, "enUS", { 2, 3 }) }))
        addon.Store.PutCharacter(char("Old-R", 1, { Kochkunst = { name = "Kochkunst", rank = 5, max = 75, recipes = { [3] = true } } }))  -- 0.1.0
        addon.Store.PutCatalog({ [1] = { name = "Gebratener Eber", loc = "deDE", reagents = {} },
            [2] = { name = "Roast Boar", loc = "enUS", reagents = {} }, [3] = { name = "Spiced Wolf", loc = "enUS", reagents = {} } })
        local profs = addon.Model.Professions(addon.Store)
        harness.equal(#profs, 1); harness.equal(profs[1].name, "Cooking"); harness.equal(profs[1].key, 185)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { profession = 185, text = "" }), 3)
        local rows = addon.Model.BuildRecipeRows(addon.Store, { text = "" })
        for _, r in ipairs(rows) do harness.equal(r.profession, "Cooking") end

        local de = viewer(harness, "deDE")
        de.Store.PutCharacter(char("En-R", 1, { Cooking = prof("Cooking", 185, "enUS", { 2 }) }))
        harness.equal(de.Model.Professions(de.Store)[1].name, "Kochkunst")
    end,

    ["model: search and sort ignore case and accents, also on reagent names"] = function(harness)
        local addon = viewer(harness, "deDE")
        addon.Store.PutCharacter(char("A-R", 1, { Kochkunst = prof("Kochkunst", 185, "deDE", { 1, 2, 3 }) }))
        addon.Store.PutCatalog({
            [1] = { name = "Äpfel", loc = "deDE", reagents = {} },
            [2] = { name = "Zwiebelsuppe", loc = "deDE", reagents = { { itemID = 5, count = 1, name = "Süßkartoffel" } } },
            [3] = { name = "Bratwurst", loc = "deDE", reagents = {} } })
        local rows = addon.Model.BuildRecipeRows(addon.Store, { text = "" })
        harness.equal(rows[1].name, "Äpfel"); harness.equal(rows[2].name, "Bratwurst"); harness.equal(rows[3].name, "Zwiebelsuppe")
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "APFEL" }), 1)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "ÄPF" }), 1)
        harness.equal(#addon.Model.BuildRecipeRows(addon.Store, { text = "susskartoffel" }), 1)  -- reagent, ß -> ss
    end,

    ["model: own professions for the scan buttons report how many recipes are stored (0 = not scanned)"] = function(harness)
        local addon = viewer(harness, "deDE")
        -- stored: Kochkunst scanned (id-keyed), Kürschnerei from a 0.1.0 name-keyed record, Lederverarbeitung empty
        addon.Store.PutCharacter(char("Me-R", 1, {
            Kochkunst = prof("Kochkunst", 185, "deDE", { 1, 2, 3 }),
            ["Kürschnerei"] = { name = "Kürschnerei", rank = 5, max = 75, recipes = { [9] = true } },
            Lederverarbeitung = prof("Lederverarbeitung", 165, "deDE", {}),
        }))
        local live = {
            { name = "Lederverarbeitung", icon = 1, rank = 35, max = 75, id = 165 },
            { name = "Kochkunst", icon = 2, rank = 150, max = 150, id = 185 },
            { name = "Kürschnerei", icon = 3, rank = 131, max = 150, id = 393 },
        }
        local rows = addon.Model.OwnProfessions(addon.Store, "Me-R", live)
        harness.equal(#rows, 3)
        harness.equal(rows[1].name, "Kochkunst"); harness.equal(rows[1].count, 3); harness.equal(rows[1].spellName, "Kochkunst")
        harness.equal(rows[2].name, "Kürschnerei"); harness.equal(rows[2].count, 1, "0.1.0 name-keyed record must still be counted")
        harness.equal(rows[3].name, "Lederverarbeitung"); harness.equal(rows[3].count, 0)
        harness.equal(#addon.Model.OwnProfessions(addon.Store, "Nobody-R", live), 3, "unknown character: all professions, all unscanned")
        harness.equal(addon.Model.OwnProfessions(addon.Store, "Nobody-R", live)[1].count, 0)
        harness.equal(#addon.Model.OwnProfessions(addon.Store, "Me-R", nil), 0)
    end,

    ["model: the CLICK HERE hint shows only while professions exist and all of them are at 0"] = function(harness)
        local M = viewer(harness, "enUS").Model
        harness.equal(M.NeedsScanHint({}), false, "no professions: nothing to click")
        harness.equal(M.NeedsScanHint({ { count = 0 } }), true)
        harness.equal(M.NeedsScanHint({ { count = 0 }, { count = 0 }, { count = 0 } }), true)
        harness.equal(M.NeedsScanHint({ { count = 0 }, { count = 1 }, { count = 0 } }), false, "one read profession is enough to hide it")
        harness.equal(M.NeedsScanHint({ { count = 11 } }), false)
    end,

    ["model: profession button macro casts the profession name first, then its other spellbook entries"] = function(harness)
        local M = viewer(harness, "deDE").Model
        harness.equal(M.CastMacro({ spellName = "Kochkunst" }), "/cast Kochkunst")
        harness.equal(M.CastMacro({ spellName = "Kochkunst", spells = { "Kochkunst" } }), "/cast Kochkunst", "no duplicate line")
        harness.equal(M.CastMacro({ spellName = "Kürschnerei", spells = { "Kürschnerei", "Lagerstuhl" } }), "/cast Kürschnerei\n/cast Lagerstuhl")
        harness.equal(M.CastMacro({ spellName = "A", spells = { "B", "C", "D", "E" } }), "/cast A\n/cast B\n/cast C", "at most 3 lines")
        harness.equal(M.CastMacro({ spellName = "A", spells = { "B\n/run evil()", 5, "" } }), "/cast A", "line breaks, non-strings and empty names are dropped")
        local addon = viewer(harness, "deDE")
        local rows = addon.Model.OwnProfessions(addon.Store, "X-R", { { name = "Kürschnerei", id = 393, rank = 1, max = 2, spells = { "Kürschnerei", "Lagerstuhl" } } })
        harness.equal(rows[1].spells[2], "Lagerstuhl")
    end,

    ["model: reagent names come from the viewer's client before the sender's snapshot"] = function(harness)
        local addon = viewer(harness, "deDE")
        addon.Store.PutCatalog({ [1] = { name = "X", reagents = { { itemID = 10, count = 1, name = "Boar Meat" } } } })
        local d = addon.Model.RecipeDetail(addon.Store, 1, nil, function() return "Eberfleisch" end)
        harness.equal(d.reagents[1].name, "Eberfleisch")
        d = addon.Model.RecipeDetail(addon.Store, 1, nil, function() return nil end)
        harness.equal(d.reagents[1].name, "Boar Meat")
    end,

    ["store: hostile id / loc / name fields are rejected (RF6)"] = function(harness)
        local addon = harness.addon()
        local function with(patch)
            local rec = char("A-R", 1, { Cooking = prof("Cooking", 185, "enUS", { 1 }) })
            for k, v in pairs(patch) do rec.professions.Cooking[k] = v end
            return addon.Store.ValidateCharacter(rec)
        end
        harness.equal(with({}), true)
        harness.equal(with({ id = "185" }), false)
        harness.equal(with({ id = 0 / 0 }), false)
        harness.equal(with({ id = -1 }), false)
        harness.equal(with({ id = 1.5 }), false)
        harness.equal(with({ id = 1e12 }), false)
        harness.equal(with({ loc = 5 }), false)
        harness.equal(with({ loc = "x" }), false)
        harness.equal(with({ loc = "de DE" }), false)
        harness.equal(with({ loc = string.rep("a", 40) }), false)
        harness.equal(with({ name = string.rep("a", 200) }), false)
        harness.equal(with({ name = "bad\255" }), false)
        harness.equal(addon.Store.ValidateCatalogEntry({ reagents = {}, loc = "|cffff0000" }), false)
        harness.equal(addon.Store.ValidateCatalogEntry({ reagents = {}, name = "x\128" }), false)
        harness.equal(addon.Store.ValidateCatalogEntry({ reagents = {}, name = "Kürschnerei", loc = "deDE" }), true)
    end,

    ["scanner: records id/loc, upgrades a 0.1.0 name-keyed record, survives a client language switch (RF5)"] = function(harness)
        local addon = viewer(harness, "enUS")
        assert(loadfile("Core/Data/Scanner.lua"))("TalentShare", addon)
        local profs, openProf = nil, nil
        addon.Api = {
            GetPlayerInformation = function() return { name = "Me-R", class = "MAGE", level = 30 } end,
            GetPlayerProfessions = function() return profs end,
            GetOpenProfession = function() return openProf end,
        }
        -- state saved by 0.1.0: name key, no id, no loc
        addon.Store.PutCharacter({ name = "Me-R", class = "MAGE", level = 30, rev = 5,
            professions = { Cooking = { name = "Cooking", rank = 50, max = 75, recipes = { [10] = true, [11] = true } } } })
        profs = { { name = "Cooking", rank = 50, max = 75, id = 185 } }
        harness.equal(addon.Scanner.Refresh(2000), true, "id/loc are new data, so the record must be republished")
        local p = addon.Store.GetCharacter("Me-R").professions.Cooking
        harness.equal(p.id, 185); harness.equal(p.loc, "enUS"); harness.truthy(p.recipes[10] and p.recipes[11], "recipes lost on upgrade")
        harness.equal(addon.Scanner.Refresh(2001), false, "an unchanged rescan must not bump the revision")
        harness.equal(addon.db.profNames.enUS[185], "Cooking")

        -- the player switches the game client to German: the key changes, the recipes must stay
        addon.Locale.clientCode = "deDE"
        profs = { { name = "Kochkunst", rank = 50, max = 75, id = 185 } }
        harness.equal(addon.Scanner.Refresh(2002), true)
        local rec = addon.Store.GetCharacter("Me-R")
        harness.equal(rec.professions.Cooking, nil, "old name key must be replaced")
        harness.truthy(rec.professions.Kochkunst and rec.professions.Kochkunst.recipes[10], "recipes lost on language switch")
        harness.equal(rec.professions.Kochkunst.loc, "deDE")

        -- an open profession window adds recipes and catalog entries tagged with the client language
        openProf = { name = "Kochkunst", id = 185, rank = 50, max = 75,
            recipes = { { recipeID = 12, name = "Gebratener Eber", icon = 1, produces = 99, reagents = {} } } }
        addon.Scanner.Refresh(2003)
        harness.equal(addon.Store.GetRecipe(12).loc, "deDE")
        harness.truthy(addon.Store.GetCharacter("Me-R").professions.Kochkunst.recipes[12])

        -- a dropped profession disappears (RF2 of the original plan still holds)
        profs, openProf = {}, nil
        addon.Scanner.Refresh(2004)
        harness.equal(next(addon.Store.GetCharacter("Me-R").professions), nil)
    end,

    ["orders: notes are byte-limited on a character boundary and the order is never dropped (RF2)"] = function(harness)
        local addon = harness.addon()
        local o = addon.Orders.New(function() return harness.clock end, addon.db.orders)
        local long = string.rep("烹", 40)                      -- 120 bytes
        local c = o:Create("A-R", 1, 1, long)
        harness.truthy(c, "a long multi-byte note must not drop the order")
        harness.truthy(#c.note <= 80 and addon.Utility.IsValidUtf8(c.note), "note cut mid-character")
        harness.equal(#c.note, 78)                                      -- 26 x 3 bytes
        local peer = addon.Orders.New(function() return harness.clock end, {})
        harness.equal(peer:Merge(c), true, "peers must accept what the sender stored")
        harness.equal(o:Create("A-R", 1, 1, "bad\255note").note, "")    -- invalid UTF-8 is dropped, order kept
        local forged = addon.Utility.DeepCopy(c); forged.note = "x\128"
        harness.equal(peer:Merge(forged), false)
    end,
}
