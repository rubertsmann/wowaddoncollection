-- Feature 002: names are resolved for the viewer, text is UTF-8 safe, mixed-language guilds converge
local function prof(name, id, loc, recipes, rank)
    local set = {}
    for _, r in ipairs(recipes) do set[r] = true end
    return { name = name, id = id, loc = loc, rank = rank or 100, max = 150, recipes = set }
end

local function char(name, rev, profs)
    return { name = name, class = "MAGE", level = 60, rev = rev, professions = profs }
end

local function viewer(h, code, spell)
    local ns = h.ns()
    ns.Locale.clientCode, ns.Locale.code = code, code
    ns.Names.env.spellName = spell
    return ns
end

return {
    ["utf8: IsValidUtf8 accepts real text and rejects malformed sequences"] = function(h)
        local U = h.ns().Util
        for _, ok in ipairs({ "", "abc", "Kürschnerei", "Кулинария", "烹饪", "😀" }) do h.truthy(U.IsValidUtf8(ok), ok) end
        for _, bad in ipairs({ "\128", "\194", "\192\128", "\237\160\128", "\244\144\128\128", "a\255", "\226\130" }) do
            h.eq(U.IsValidUtf8(bad), false, "accepted malformed " .. #bad .. " bytes")
        end
        h.eq(U.IsValidUtf8(5), false)
    end,

    ["utf8: TruncateUtf8 never cuts inside a character (RF2)"] = function(h)
        local U = h.ns().Util
        h.eq(U.TruncateUtf8("abc", 5), "abc")
        h.eq(U.TruncateUtf8("aé", 2), "a")        -- é is 2 bytes
        h.eq(U.TruncateUtf8("aé", 3), "aé")
        h.eq(U.TruncateUtf8("烹饪", 4), "烹")      -- 3 bytes each
        h.eq(U.TruncateUtf8("😀😀", 5), "😀")
        for n = 0, 12 do
            local t = U.TruncateUtf8("äö烹饪😀x", n)
            h.truthy(#t <= n and U.IsValidUtf8(t), "bad cut at " .. n)
        end
    end,

    ["utf8: Fold and SearchKey ignore case and accents (R6)"] = function(h)
        local U = h.ns().Util
        h.eq(U.Fold("KÜRSCHNEREI"), "kürschnerei")
        h.eq(U.Fold("ÄÖÜ ÀÉ"), "äöü àé")
        h.eq(U.SearchKey("Kürschnerei"), U.SearchKey("KURSCHNEREI"))
        h.eq(U.SearchKey("Straße"), "strasse")
        h.eq(U.SearchKey("КУЛИНАРИЯ"), U.SearchKey("кулинария"))
        h.eq(U.SearchKey("Ёлка"), U.SearchKey("елка"))
        h.eq(U.SearchKey("烹饪"), "烹饪")                    -- CJK is untouched
        h.truthy(U.SearchKey("Äpfel") < U.SearchKey("Birne"), "ä must sort with a")
    end,

    ["locale: missing translations and unknown locales fall back to English, never nil (RF3)"] = function(h)
        local ns = h.ns()
        h.eq(ns.L["Recipes"], "Recipes")
        ns.Locale.SetUI("deDE")
        h.eq(ns.L["Recipes"], "Rezepte")
        h.eq(ns.L["not translated anywhere"], "not translated anywhere")
        ns.Locale.SetUI("xxXX")
        h.eq(ns.L["Recipes"], "Recipes")
        ns.Locale.SetUI(nil)
        h.eq(ns.Locale.code, ns.Locale.clientCode)
    end,

    ["locale: Fmt fills named placeholders and Plural picks one/many"] = function(h)
        local ns = h.ns()
        h.eq(ns.Locale.Fmt("{a}-{b}-{a}", { a = 1, b = "x" }), "1-x-1")
        h.eq(ns.Locale.Fmt("{missing}", {}), "{missing}")
        h.eq(ns.Locale.Plural(1, "{n} recipe", "{n} recipes"), "1 recipe")
        h.eq(ns.Locale.Plural(0, "{n} recipe", "{n} recipes"), "0 recipes")
        h.eq(ns.Locale.Plural(7, "{n} recipe", "{n} recipes"), "7 recipes")
    end,

    ["names: ProfKey merges German, English and 0.1.0 name-key records (RF1)"] = function(h)
        local ns = viewer(h, "enUS")
        local N = ns.Names
        local a = N.ProfKey("Kochkunst", { name = "Kochkunst" })                   -- 0.1.0 record, no id
        local b = N.ProfKey("Cooking", { name = "Cooking" })
        local c = N.ProfKey("Kochkunst", { name = "Kochkunst", id = 185, loc = "deDE" })
        h.eq(a, 185); h.eq(b, 185); h.eq(c, 185)
        h.eq(N.ProfKey("Totally Unknown", { name = "Totally Unknown" }), "n:totally unknown")
        h.eq(N.ProfKey("KOCHKUNST", { name = "KOCHKUNST" }), 185, "case-insensitive reverse lookup")
    end,

    ["names: profession display follows the viewer's language (R2)"] = function(h)
        local entryDe = { name = "Kochkunst", id = 185, loc = "deDE" }
        local en = viewer(h, "enUS")
        h.eq(en.Names.Profession(185, entryDe), "Cooking")                          -- static English table beats a German snapshot
        local de = viewer(h, "deDE")
        h.eq(de.Names.Profession(185, { name = "Cooking", id = 185, loc = "enUS" }), "Kochkunst")
        local fr = viewer(h, "frFR")
        h.eq(fr.Names.Profession(185, { name = "Cuisine", id = 185, loc = "frFR" }), "Cuisine")   -- own-language snapshot
        h.eq(fr.Names.Profession(185, { name = "Kochkunst", id = 185, loc = "deDE" }), "Cooking") -- English fallback, not German
        h.eq(fr.Names.Profession(999, { name = "Kochkunst", id = 999, loc = "deDE" }), "Kochkunst")
        h.eq(fr.Names.Profession(999, nil), "Profession #999")
    end,

    ["names: a name learned from the viewer's own client wins and is persisted per locale"] = function(h)
        local ns = viewer(h, "frFR")
        ns.Names.Learn(185, "Cuisine")
        h.eq(ns.Names.Profession(185, { name = "Kochkunst", id = 185, loc = "deDE" }), "Cuisine")
        h.eq(ns.db.profNames.frFR[185], "Cuisine")
        h.eq(ns.Names.ProfKey("Cuisine", { name = "Cuisine" }), 185, "learned names feed the reverse lookup")
        ns.Names.Learn("x", "y"); ns.Names.Learn(5, "")                              -- ignored
        h.eq(ns.db.profNames.frFR[5], nil)
    end,

    ["names: recipe name uses the viewer's spell name unless the snapshot is in the viewer's language (R3)"] = function(h)
        local spell = function(id) return id == 7 and "Gebratener Eber" or nil end
        local de = viewer(h, "deDE", spell)
        h.eq(de.Names.Recipe(7, { name = "Roast Boar", loc = "enUS" }), "Gebratener Eber")
        h.eq(de.Names.Recipe(7, { name = "Eber (alt)", loc = "deDE" }), "Eber (alt)")
        h.eq(de.Names.Recipe(8, { name = "Roast Boar", loc = "enUS" }), "Roast Boar")      -- no spell data: snapshot
        h.eq(de.Names.Recipe(9, nil), "Rezept #9")
        de.Locale.SetUI("enUS")
        h.eq(de.Names.Recipe(9, nil), "Recipe #9")
    end,

    ["model: mixed-language guild shows ONE Cooking entry, in the viewer's language (RF1)"] = function(h)
        local ns = viewer(h, "enUS")
        ns.Store.PutChar(char("De-R", 1, { Kochkunst = prof("Kochkunst", 185, "deDE", { 1, 2 }) }))
        ns.Store.PutChar(char("En-R", 1, { Cooking = prof("Cooking", 185, "enUS", { 2, 3 }) }))
        ns.Store.PutChar(char("Old-R", 1, { Kochkunst = { name = "Kochkunst", rank = 5, max = 75, recipes = { [3] = true } } }))  -- 0.1.0
        ns.Store.PutCatalog({ [1] = { name = "Gebratener Eber", loc = "deDE", reagents = {} },
            [2] = { name = "Roast Boar", loc = "enUS", reagents = {} }, [3] = { name = "Spiced Wolf", loc = "enUS", reagents = {} } })
        local profs = ns.Model.Professions(ns.Store)
        h.eq(#profs, 1); h.eq(profs[1].name, "Cooking"); h.eq(profs[1].key, 185)
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { profession = 185, text = "" }), 3)
        local rows = ns.Model.BuildRecipeRows(ns.Store, { text = "" })
        for _, r in ipairs(rows) do h.eq(r.profession, "Cooking") end

        local de = viewer(h, "deDE")
        de.Store.PutChar(char("En-R", 1, { Cooking = prof("Cooking", 185, "enUS", { 2 }) }))
        h.eq(de.Model.Professions(de.Store)[1].name, "Kochkunst")
    end,

    ["model: search and sort ignore case and accents, also on reagent names"] = function(h)
        local ns = viewer(h, "deDE")
        ns.Store.PutChar(char("A-R", 1, { Kochkunst = prof("Kochkunst", 185, "deDE", { 1, 2, 3 }) }))
        ns.Store.PutCatalog({
            [1] = { name = "Äpfel", loc = "deDE", reagents = {} },
            [2] = { name = "Zwiebelsuppe", loc = "deDE", reagents = { { itemID = 5, count = 1, name = "Süßkartoffel" } } },
            [3] = { name = "Bratwurst", loc = "deDE", reagents = {} } })
        local rows = ns.Model.BuildRecipeRows(ns.Store, { text = "" })
        h.eq(rows[1].name, "Äpfel"); h.eq(rows[2].name, "Bratwurst"); h.eq(rows[3].name, "Zwiebelsuppe")
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { text = "APFEL" }), 1)
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { text = "ÄPF" }), 1)
        h.eq(#ns.Model.BuildRecipeRows(ns.Store, { text = "susskartoffel" }), 1)  -- reagent, ß -> ss
    end,

    ["model: own professions for the scan buttons report how many recipes are stored (0 = not scanned)"] = function(h)
        local ns = viewer(h, "deDE")
        -- stored: Kochkunst scanned (id-keyed), Kürschnerei from a 0.1.0 name-keyed record, Lederverarbeitung empty
        ns.Store.PutChar(char("Me-R", 1, {
            Kochkunst = prof("Kochkunst", 185, "deDE", { 1, 2, 3 }),
            ["Kürschnerei"] = { name = "Kürschnerei", rank = 5, max = 75, recipes = { [9] = true } },
            Lederverarbeitung = prof("Lederverarbeitung", 165, "deDE", {}),
        }))
        local live = {
            { name = "Lederverarbeitung", icon = 1, rank = 35, max = 75, id = 165 },
            { name = "Kochkunst", icon = 2, rank = 150, max = 150, id = 185 },
            { name = "Kürschnerei", icon = 3, rank = 131, max = 150, id = 393 },
        }
        local rows = ns.Model.OwnProfessions(ns.Store, "Me-R", live)
        h.eq(#rows, 3)
        h.eq(rows[1].name, "Kochkunst"); h.eq(rows[1].count, 3); h.eq(rows[1].spellName, "Kochkunst")
        h.eq(rows[2].name, "Kürschnerei"); h.eq(rows[2].count, 1, "0.1.0 name-keyed record must still be counted")
        h.eq(rows[3].name, "Lederverarbeitung"); h.eq(rows[3].count, 0)
        h.eq(#ns.Model.OwnProfessions(ns.Store, "Nobody-R", live), 3, "unknown character: all professions, all unscanned")
        h.eq(ns.Model.OwnProfessions(ns.Store, "Nobody-R", live)[1].count, 0)
        h.eq(#ns.Model.OwnProfessions(ns.Store, "Me-R", nil), 0)
    end,

    ["model: the CLICK HERE hint shows only while professions exist and all of them are at 0"] = function(h)
        local M = viewer(h, "enUS").Model
        h.eq(M.NeedsScanHint({}), false, "no professions: nothing to click")
        h.eq(M.NeedsScanHint({ { count = 0 } }), true)
        h.eq(M.NeedsScanHint({ { count = 0 }, { count = 0 }, { count = 0 } }), true)
        h.eq(M.NeedsScanHint({ { count = 0 }, { count = 1 }, { count = 0 } }), false, "one read profession is enough to hide it")
        h.eq(M.NeedsScanHint({ { count = 11 } }), false)
    end,

    ["model: profession button macro casts the profession name first, then its other spellbook entries"] = function(h)
        local M = viewer(h, "deDE").Model
        h.eq(M.CastMacro({ spellName = "Kochkunst" }), "/cast Kochkunst")
        h.eq(M.CastMacro({ spellName = "Kochkunst", spells = { "Kochkunst" } }), "/cast Kochkunst", "no duplicate line")
        h.eq(M.CastMacro({ spellName = "Kürschnerei", spells = { "Kürschnerei", "Lagerstuhl" } }), "/cast Kürschnerei\n/cast Lagerstuhl")
        h.eq(M.CastMacro({ spellName = "A", spells = { "B", "C", "D", "E" } }), "/cast A\n/cast B\n/cast C", "at most 3 lines")
        h.eq(M.CastMacro({ spellName = "A", spells = { "B\n/run evil()", 5, "" } }), "/cast A", "line breaks, non-strings and empty names are dropped")
        local ns = viewer(h, "deDE")
        local rows = ns.Model.OwnProfessions(ns.Store, "X-R", { { name = "Kürschnerei", id = 393, rank = 1, max = 2, spells = { "Kürschnerei", "Lagerstuhl" } } })
        h.eq(rows[1].spells[2], "Lagerstuhl")
    end,

    ["model: reagent names come from the viewer's client before the sender's snapshot"] = function(h)
        local ns = viewer(h, "deDE")
        ns.Store.PutCatalog({ [1] = { name = "X", reagents = { { itemID = 10, count = 1, name = "Boar Meat" } } } })
        local d = ns.Model.RecipeDetail(ns.Store, 1, nil, function() return "Eberfleisch" end)
        h.eq(d.reagents[1].name, "Eberfleisch")
        d = ns.Model.RecipeDetail(ns.Store, 1, nil, function() return nil end)
        h.eq(d.reagents[1].name, "Boar Meat")
    end,

    ["store: hostile id / loc / name fields are rejected (RF6)"] = function(h)
        local ns = h.ns()
        local function with(patch)
            local rec = char("A-R", 1, { Cooking = prof("Cooking", 185, "enUS", { 1 }) })
            for k, v in pairs(patch) do rec.professions.Cooking[k] = v end
            return ns.Store.ValidateChar(rec)
        end
        h.eq(with({}), true)
        h.eq(with({ id = "185" }), false)
        h.eq(with({ id = 0 / 0 }), false)
        h.eq(with({ id = -1 }), false)
        h.eq(with({ id = 1.5 }), false)
        h.eq(with({ id = 1e12 }), false)
        h.eq(with({ loc = 5 }), false)
        h.eq(with({ loc = "x" }), false)
        h.eq(with({ loc = "de DE" }), false)
        h.eq(with({ loc = string.rep("a", 40) }), false)
        h.eq(with({ name = string.rep("a", 200) }), false)
        h.eq(with({ name = "bad\255" }), false)
        h.eq(ns.Store.ValidateCatalogEntry({ reagents = {}, loc = "|cffff0000" }), false)
        h.eq(ns.Store.ValidateCatalogEntry({ reagents = {}, name = "x\128" }), false)
        h.eq(ns.Store.ValidateCatalogEntry({ reagents = {}, name = "Kürschnerei", loc = "deDE" }), true)
    end,

    ["scanner: records id/loc, upgrades a 0.1.0 name-keyed record, survives a client language switch (RF5)"] = function(h)
        local ns = viewer(h, "enUS")
        assert(loadfile("Core/Scanner.lua"))("TalentShare", ns)
        local profs, openProf = nil, nil
        ns.Api = {
            GetPlayerInfo = function() return { name = "Me-R", class = "MAGE", level = 30 } end,
            GetPlayerProfessions = function() return profs end,
            GetOpenProfession = function() return openProf end,
        }
        -- state saved by 0.1.0: name key, no id, no loc
        ns.Store.PutChar({ name = "Me-R", class = "MAGE", level = 30, rev = 5,
            professions = { Cooking = { name = "Cooking", rank = 50, max = 75, recipes = { [10] = true, [11] = true } } } })
        profs = { { name = "Cooking", rank = 50, max = 75, id = 185 } }
        h.eq(ns.Scanner.Refresh(2000), true, "id/loc are new data, so the record must be republished")
        local p = ns.Store.GetChar("Me-R").professions.Cooking
        h.eq(p.id, 185); h.eq(p.loc, "enUS"); h.truthy(p.recipes[10] and p.recipes[11], "recipes lost on upgrade")
        h.eq(ns.Scanner.Refresh(2001), false, "an unchanged rescan must not bump the revision")
        h.eq(ns.db.profNames.enUS[185], "Cooking")

        -- the player switches the game client to German: the key changes, the recipes must stay
        ns.Locale.clientCode = "deDE"
        profs = { { name = "Kochkunst", rank = 50, max = 75, id = 185 } }
        h.eq(ns.Scanner.Refresh(2002), true)
        local rec = ns.Store.GetChar("Me-R")
        h.eq(rec.professions.Cooking, nil, "old name key must be replaced")
        h.truthy(rec.professions.Kochkunst and rec.professions.Kochkunst.recipes[10], "recipes lost on language switch")
        h.eq(rec.professions.Kochkunst.loc, "deDE")

        -- an open profession window adds recipes and catalog entries tagged with the client language
        openProf = { name = "Kochkunst", id = 185, rank = 50, max = 75,
            recipes = { { recipeID = 12, name = "Gebratener Eber", icon = 1, produces = 99, reagents = {} } } }
        ns.Scanner.Refresh(2003)
        h.eq(ns.Store.GetRecipe(12).loc, "deDE")
        h.truthy(ns.Store.GetChar("Me-R").professions.Kochkunst.recipes[12])

        -- a dropped profession disappears (RF2 of the original plan still holds)
        profs, openProf = {}, nil
        ns.Scanner.Refresh(2004)
        h.eq(next(ns.Store.GetChar("Me-R").professions), nil)
    end,

    ["orders: notes are byte-limited on a character boundary and the order is never dropped (RF2)"] = function(h)
        local ns = h.ns()
        local o = ns.Orders.New(function() return h.clock end, ns.db.orders)
        local long = string.rep("烹", 40)                      -- 120 bytes
        local c = o:Create("A-R", 1, 1, long)
        h.truthy(c, "a long multi-byte note must not drop the order")
        h.truthy(#c.note <= 80 and ns.Util.IsValidUtf8(c.note), "note cut mid-character")
        h.eq(#c.note, 78)                                      -- 26 x 3 bytes
        local peer = ns.Orders.New(function() return h.clock end, {})
        h.eq(peer:Merge(c), true, "peers must accept what the sender stored")
        h.eq(o:Create("A-R", 1, 1, "bad\255note").note, "")    -- invalid UTF-8 is dropped, order kept
        local forged = ns.Util.DeepCopy(c); forged.note = "x\128"
        h.eq(peer:Merge(forged), false)
    end,
}
