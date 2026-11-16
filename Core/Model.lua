local ADDON, ns = ...

-- Pure view-models for the UI (unit-testable without frames).
-- Everything a player reads is resolved HERE for the viewer's language (Names), never taken from the sender's text,
-- and compared through Util.SearchKey so case and accents do not matter.
local Model = {}
ns.Model = Model

local function recipeName(store, id)
    return ns.Names.Recipe(id, store.GetRecipe(id))
end
Model.RecipeName = recipeName

local function sortKey(s) return ns.Util.SearchKey(s or "") end

-- unique professions across all cached characters: { { key = canonical id, name = display name }, ... } sorted by name
-- 0.1.0 peers send name keys without an id; Names.ProfKey merges them with id-based entries ("Cooking" == "Kochkunst").
function Model.Professions(store)
    local seen, out = {}, {}
    for _, rec in pairs(store.db.chars) do
        for pname, p in pairs(rec.professions or {}) do
            if next(p.recipes or {}) then
                local key = ns.Names.ProfKey(pname, p)
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { key = key, name = ns.Names.Profession(key, p) }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local x, y = sortKey(a.name), sortKey(b.name)
        if x ~= y then return x < y end
        return tostring(a.key) < tostring(b.key)
    end)
    return out
end

-- The player's own professions for the scan buttons: live = Api.GetPlayerProfessions() ({name, icon, rank, max, id}).
-- count = recipes already stored for that profession (0 = not scanned yet; scanning needs the profession window to be
-- opened by a real click, see UI/Window.lua). Old name-keyed records are matched through Names.ProfKey.
function Model.OwnProfessions(store, me, live)
    local rec = store.GetChar(me or "")
    local counts = {}
    for key, p in pairs(rec and rec.professions or {}) do
        local canon = ns.Names.ProfKey(key, p)
        counts[canon] = (counts[canon] or 0) + ns.Util.Count(p.recipes or {})
    end
    local out = {}
    for _, lp in ipairs(live or {}) do
        local key = ns.Names.ProfKey(lp.name, { id = lp.id, name = lp.name })
        out[#out + 1] = { key = key, id = lp.id, spellName = lp.name, spells = lp.spells, icon = lp.icon, rank = lp.rank, max = lp.max,
            name = ns.Names.Profession(key, { id = lp.id, name = lp.name, loc = ns.Locale.clientCode }),
            count = counts[key] or 0 }
    end
    table.sort(out, function(a, b)
        local x, y = sortKey(a.name), sortKey(b.name)
        if x ~= y then return x < y end
        return tostring(a.key) < tostring(b.key)
    end)
    return out
end

-- Macro text of a profession button: the profession's own name first, then every other spellbook entry of that
-- profession (e.g. Skinning has a second one on Forever; `/cast` of a passive or unusable spell just fails and the
-- next line runs). Names only, no duplicates, at most 3 lines, nothing with line breaks (they come from our own client).
function Model.CastMacro(row)
    local lines, seen = {}, {}
    local function add(name)
        if type(name) == "string" and name ~= "" and not name:find("[\r\n]") and not seen[name] and #lines < 3 then
            seen[name] = true
            lines[#lines + 1] = "/cast " .. name
        end
    end
    add(row.spellName)
    for _, n in ipairs(row.spells or {}) do add(n) end
    return table.concat(lines, "\n")
end

-- state = { profession = canonical key|nil, text = string, mineOnly = bool, me = "Name-Realm" }
-- nameFn(itemID) -> cached item name or nil (used for reagent search)
function Model.BuildRecipeRows(store, state, nameFn)
    local text = sortKey(state.text)
    local byID, rows = {}, {}
    for _, rec in pairs(store.db.chars) do
        for pname, p in pairs(rec.professions or {}) do
            local key = ns.Names.ProfKey(pname, p)
            if state.profession == nil or state.profession == key then
                for id in pairs(p.recipes or {}) do
                    if not state.mineOnly or rec.name == state.me then
                        local row = byID[id]
                        if not row then
                            local e = store.GetRecipe(id)
                            row = { recipeID = id, name = recipeName(store, id), icon = e and e.icon,
                                professionKey = key, profession = ns.Names.Profession(key, p), crafters = {} }
                            byID[id] = row
                            rows[#rows + 1] = row
                        end
                        row.crafters[#row.crafters + 1] = rec.name
                    end
                end
            end
        end
    end
    local out = {}
    for _, row in ipairs(rows) do
        local keep = true
        if text ~= "" then
            keep = sortKey(row.name):find(text, 1, true) ~= nil
            if not keep then
                local e = store.GetRecipe(row.recipeID)
                for _, r in ipairs(e and e.reagents or {}) do
                    local rn = (nameFn and nameFn(r.itemID)) or r.name   -- the viewer's client first
                    if rn and sortKey(rn):find(text, 1, true) then keep = true; break end
                end
            end
        end
        if keep then
            row.crafterCount = #row.crafters
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        local pa, pb = sortKey(a.profession), sortKey(b.profession)
        if pa ~= pb then return pa < pb end
        local na, nb = sortKey(a.name), sortKey(b.name)
        if na ~= nb then return na < nb end
        return a.recipeID < b.recipeID
    end)
    return out
end

-- haveFn(itemID) -> count, nameFn(itemID) -> name|nil
function Model.RecipeDetail(store, recipeID, haveFn, nameFn)
    local e = store.GetRecipe(recipeID)
    local d = { recipeID = recipeID, name = recipeName(store, recipeID), icon = e and e.icon, produces = e and e.produces,
        reagents = {}, crafters = store.Crafters(recipeID) }
    for _, c in ipairs(d.crafters) do
        c.professionName = ns.Names.Profession(ns.Names.ProfKey(c.profession, c.pentry), c.pentry)
    end
    for _, r in ipairs(e and e.reagents or {}) do
        local have = haveFn and haveFn(r.itemID) or 0
        d.reagents[#d.reagents + 1] = { itemID = r.itemID, count = r.count,
            name = (nameFn and nameFn(r.itemID)) or r.name or ns.Locale.Fmt(ns.L["Item #{id}"], { id = r.itemID }),
            have = have, enough = have >= r.count }
    end
    return d
end

-- filterKey: "all" | "open" | "mine" | "crafting" | "can"; me = "Name-Realm"
function Model.BuildOrderRows(store, orders, filterKey, showClosed, me)
    local mine = store.GetChar(me)
    local function knows(recipeID)
        for _, p in pairs(mine and mine.professions or {}) do
            if p.recipes[recipeID] then return true end
        end
        return false
    end
    local rows = {}
    for _, o in ipairs(orders:List({ showClosed = showClosed })) do
        local st = orders:Status(o)
        local claimers = orders:Claimers(o)
        local my = o.claims[me]
        local iClaimed = my and my.state == "claimed"
        local keep = true
        if filterKey == "open" then keep = st == "open"
        elseif filterKey == "mine" then keep = o.requester == me
        elseif filterKey == "crafting" then keep = iClaimed and true or false
        elseif filterKey == "can" then keep = knows(o.recipeID) end
        if keep then
            local live = (st == "open" or st == "claimed")
            rows[#rows + 1] = { id = o.id, recipeID = o.recipeID, recipeName = recipeName(store, o.recipeID), qty = o.qty,
                note = o.note, requester = o.requester, status = st, claimers = claimers, createdAt = o.createdAt,
                canClaim = live and not iClaimed and knows(o.recipeID),
                canWithdraw = live and iClaimed or false,
                canDone = live and (o.requester == me or iClaimed) or false,
                canCancel = live and o.requester == me }
        end
    end
    return rows
end
