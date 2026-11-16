-- Feature 011: item categories, free-text search, tooltip text cache.
-- Client item data is stubbed with what the dev probe recorded on Forever (deDE, docs/api-findings.md).
local ITEMS = {   -- itemID -> classID, subClassID, equipLoc
    [2302] = { 4, 2, "INVTYPE_FEET" },          -- leather boots
    [4237] = { 4, 2, "INVTYPE_WAIST" },         -- leather belt
    [3000] = { 4, 1, "INVTYPE_ROBE" },          -- robe (counts as chest)
    [5957] = { 4, 2, "INVTYPE_CHEST" },         -- leather vest
    [2680] = { 0, 5, "INVTYPE_NON_EQUIP_IGNORE" },   -- buff food
    [2318] = { 7, 6, "INVTYPE_NON_EQUIP_IGNORE" },   -- leather (trade goods)
}
local function classFn(id) local t = ITEMS[id]; if t then return t[1], t[2], t[3] end end
local LABELS = { ["slot:INVTYPE_FEET"] = "Füße", ["slot:INVTYPE_WAIST"] = "Taille", ["slot:INVTYPE_CHEST"] = "Brust",
    ["class:0:5"] = "Essen & Trinken", ["class:7:6"] = "Leder", none = "Kein Gegenstand" }
local TEXT = { [2680] = "Benutzen: ... erhaltet 15 Min. lang 1 Beweglichkeit.", [2302] = "Füße Leder 31 Rüstung" }
local FNS = { class = classFn, label = function(k) return LABELS[k] end, text = function(id) return TEXT[id] end,
    groupLabel = function(g) return ({ [4] = "Rüstung", [0] = "Verbrauchbar", [7] = "Handwerkswaren", [-1] = "Andere" })[g] end }

local function setup(h)
    local ns = h.ns()
    ns.Store.PutChar(h.char("A-R", 1, { 1, 2, 3, 4, 5, 6, 7 }))
    ns.Store.PutCatalog({
        [1] = { name = "Lederstiefel", produces = 2302, reagents = {} },
        [2] = { name = "Ledergürtel", produces = 4237, reagents = { { itemID = 2318, count = 2, name = "Leichtes Leder" } } },
        [3] = { name = "Robe", produces = 3000, reagents = {} },
        [4] = { name = "Gewürztes Wolfsfleisch", produces = 2680, reagents = {} },
        [5] = { name = "Leichtes Leder", produces = 2318, reagents = {} },
        [6] = { name = "Verzauberung: Brust", reagents = {} },          -- no item
        [7] = { name = "Lederweste", produces = 5957, reagents = {} },
    })
    return ns
end

local function names(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.name end
    table.sort(out)
    return table.concat(out, ",")
end

return {
    ["categories: key from class, subclass and slot; robe is chest; no item is none"] = function(h)
        local ns = h.ns()
        local M = ns.Model
        h.eq((M.CategoryKey(4, 2, "INVTYPE_HEAD")), "slot:INVTYPE_HEAD")
        h.eq((M.CategoryKey(4, 1, "INVTYPE_ROBE")), "slot:INVTYPE_CHEST")
        h.eq((M.CategoryKey(0, 5, "INVTYPE_NON_EQUIP_IGNORE")), "class:0:5")
        h.eq((M.CategoryKey(2, 7, "INVTYPE_WEAPON")), "class:2:7")      -- weapons by weapon type
        h.eq((M.CategoryKey(4, 0, "INVTYPE_NON_EQUIP_IGNORE")), "class:4:0")
        local k, g = M.CategoryKey(nil)
        h.eq(k, "none"); h.eq(g, -1)
        h.eq((M.CategoryKey("4", 2, "INVTYPE_HEAD")), "none")         -- garbage
    end,

    ["categories: filter by checked categories, several at once, empty set = all"] = function(h)
        local ns = setup(h)
        local B = ns.Model.BuildRecipeRows
        h.eq(#B(ns.Store, { text = "" }, nil, FNS), 7)
        h.eq(names(B(ns.Store, { text = "", categories = { ["slot:INVTYPE_CHEST"] = true } }, nil, FNS)), "Lederweste,Robe")
        h.eq(names(B(ns.Store, { text = "", categories = { ["slot:INVTYPE_FEET"] = true, ["class:0:5"] = true } }, nil, FNS)),
            "Gewürztes Wolfsfleisch,Lederstiefel")
        h.eq(names(B(ns.Store, { text = "", categories = { none = true } }, nil, FNS)), "Verzauberung: Brust")
        h.eq(#B(ns.Store, { text = "", categories = {} }, nil, FNS), 7)
        -- without client item data everything is "none" (and nothing breaks)
        h.eq(#B(ns.Store, { text = "", categories = { none = true } }), 7)
    end,

    ["categories: list per profession in display order with counts"] = function(h)
        local ns = setup(h)
        local groups = ns.Model.RecipeCategories(ns.Store, {}, FNS)
        local got = {}
        for _, g in ipairs(groups) do
            local cats = {}
            for _, c in ipairs(g.cats) do cats[#cats + 1] = c.label .. "=" .. c.n end
            got[#got + 1] = g.label .. ":" .. table.concat(cats, "/")
        end
        h.eq(table.concat(got, " | "),
            "Rüstung:Brust=2/Taille=1/Füße=1 | Verbrauchbar:Essen & Trinken=1 | Handwerkswaren:Leder=1 | Andere:Kein Gegenstand=1")
        h.eq(#ns.Model.RecipeCategories(ns.Store, { profession = ns.Names.ProfKey("Tailoring") }, FNS), 0)
    end,

    ["search: free text, words in any order, across name, reagent, category and effect text"] = function(h)
        local ns = setup(h)
        local B = ns.Model.BuildRecipeRows
        h.eq(names(B(ns.Store, { text = "beweglichkeit" }, nil, FNS)), "Gewürztes Wolfsfleisch")      -- effect text
        h.eq(names(B(ns.Store, { text = "füße" }, nil, FNS)), "Lederstiefel")                          -- category label
        h.eq(names(B(ns.Store, { text = "leicht gurtel" }, nil, FNS)), "Ledergürtel")                  -- reagent + name, accents
        h.eq(names(B(ns.Store, { text = "brust leder" }, nil, FNS)), "Lederweste")                     -- any order
        h.eq(#B(ns.Store, { text = "brust zzz" }, nil, FNS), 0)                                        -- every word must match
        h.eq(names(B(ns.Store, { text = "  WOLFS  " }, nil, FNS)), "Gewürztes Wolfsfleisch")           -- spaces, case
        h.eq(names(B(ns.Store, { text = "leder", categories = { ["slot:INVTYPE_FEET"] = true } }, nil, FNS)), "Lederstiefel")
    end,

    ["search: tooltip text drops the name line and every escape sequence, cuts on a character boundary"] = function(h)
        local ns = h.ns()
        local T = ns.Model.TooltipSearchText
        local s = T({ "Gewürztes Wolfsfleisch",
            "Benutzen: Stellt 58 Punkt(e) wieder her. (1 |4Sek.:Sek.; Abklingzeit)",
            "|cffff0000Rot|r |Hitem:1|h[Link]|h",
            "Verkaufspreis: 10|A:coin-copper:14:14:2:0|a |TInterface\\x:0|t",
            "|cnIQ1:Blau|r", "", "Zeile\r\n\r\nzwei" })
        h.eq(s, "Benutzen: Stellt 58 Punkt(e) wieder her. (1 Sek. Abklingzeit) Rot [Link] Verkaufspreis: 10 Blau Zeile zwei")
        h.eq(s:find("|", 1, true), nil)
        local cut = T({ "x", "aü" }, 2)      -- "ü" is 2 bytes: never cut in half
        h.eq(cut, "a")
        h.eq(T(nil), ""); h.eq(T({ "only the name" }), "")
    end,

    ["search: item text cache reads once, retries uncached items, starts over with a new language"] = function(h)
        local ns = h.ns()
        loadfile("Core/ItemText.lua")("TalentShare", ns)
        local IT = ns.ItemText
        local loc = "deDE"
        GetLocale = function() return loc end
        local reads, loaded = 0, {}
        ns.Api = { ItemTooltipLines = function(id)
            reads = reads + 1
            if not loaded[id] then loaded[id] = true; return nil end      -- first time: not loaded yet
            return { "Name", "Erhöht Intelligenz um 10." }
        end }
        h.eq(IT.Get(5), nil); h.eq(IT.Pending(), 1)
        h.eq(IT.Pump(10), 0)                       -- not loaded: one try used
        h.eq(IT.Get(5), nil)                       -- queued again
        h.eq(IT.Pump(10), 1)
        h.eq(IT.Get(5), "Erhöht Intelligenz um 10.")
        h.eq(IT.Pending(), 0)
        IT.Pump(10); h.eq(reads, 2)                -- cached: no more reads
        loc = "enUS"
        h.eq(IT.Get(5), nil)                       -- other language: cache starts over
        h.eq(ns.db.itemText.locale, "enUS")
        -- an item that never loads stops after MAX_TRIES
        ns.Api.ItemTooltipLines = function() return nil end
        for _ = 1, IT.MAX_TRIES + 2 do IT.Get(9); IT.Pump(10) end
        h.eq(IT.Get(9), nil); h.eq(IT.Pending(), 0)
        -- garbage in the saved cache is replaced, not used
        ns.db.itemText = { locale = "enUS", items = { [7] = { "x" } } }
        h.eq(IT.Get(7), nil)
        IT._Reset(); GetLocale = nil
    end,

    ["search: Clean also drops the item text cache"] = function(h)
        local ns = h.ns()
        ns.db.itemText.items = { [1] = "x" }; ns.db.itemText.locale = "deDE"
        ns.Store.Clean()
        h.eq(next(ns.db.itemText), nil)
    end,
}
