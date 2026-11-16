local ADDON, ns = ...

-- Pure view-models for the UI (unit-testable without frames).
local Model = {}
ns.Model = Model

local function recipeName(store, id)
    local e = store.GetRecipe(id)
    return (e and e.name) or ("Recipe #" .. id)
end
Model.RecipeName = recipeName

-- sorted unique profession names across all cached characters
function Model.Professions(store)
    local set, out = {}, {}
    for _, rec in pairs(store.db.chars) do
        for pname, p in pairs(rec.professions or {}) do
            if next(p.recipes or {}) and not set[pname] then set[pname] = true; out[#out + 1] = pname end
        end
    end
    table.sort(out)
    return out
end

-- state = { profession = name|nil, text = string, mineOnly = bool, me = "Name-Realm" }
-- nameFn(itemID) -> cached item name or nil (used for reagent search)
function Model.BuildRecipeRows(store, state, nameFn)
    local text = (state.text or ""):lower()
    local byID, rows = {}, {}
    for _, rec in pairs(store.db.chars) do
        for pname, p in pairs(rec.professions or {}) do
            if not state.profession or state.profession == pname then
                for id in pairs(p.recipes or {}) do
                    if not state.mineOnly or rec.name == state.me then
                        local row = byID[id]
                        if not row then
                            local e = store.GetRecipe(id)
                            row = { recipeID = id, name = recipeName(store, id), icon = e and e.icon,
                                profession = pname, crafters = {} }
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
            keep = row.name:lower():find(text, 1, true) ~= nil
            if not keep then
                local e = store.GetRecipe(row.recipeID)
                for _, r in ipairs(e and e.reagents or {}) do
                    local rn = r.name or (nameFn and nameFn(r.itemID))
                    if rn and rn:lower():find(text, 1, true) then keep = true; break end
                end
            end
        end
        if keep then
            row.crafterCount = #row.crafters
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        if a.profession ~= b.profession then return a.profession < b.profession end
        return a.name < b.name
    end)
    return out
end

-- haveFn(itemID) -> count, nameFn(itemID) -> name|nil
function Model.RecipeDetail(store, recipeID, haveFn, nameFn)
    local e = store.GetRecipe(recipeID)
    local d = { recipeID = recipeID, name = recipeName(store, recipeID), icon = e and e.icon, produces = e and e.produces,
        reagents = {}, crafters = store.Crafters(recipeID) }
    for _, r in ipairs(e and e.reagents or {}) do
        local have = haveFn and haveFn(r.itemID) or 0
        d.reagents[#d.reagents + 1] = { itemID = r.itemID, count = r.count,
            name = r.name or (nameFn and nameFn(r.itemID)) or ("item:" .. r.itemID), have = have, enough = have >= r.count }
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
