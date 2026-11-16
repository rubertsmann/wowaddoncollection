local ADDON, ns = ...

-- Pure view-models for the UI (unit-testable without frames).
-- Everything a player reads is resolved HERE for the viewer's language (Names), never taken from the sender's text,
-- and compared through Util.SearchKey so case and accents do not matter.
local Model = {}
ns.Model = Model

-- Names can come from another player's snapshot: escape "|" so they can never inject colour/texture/hyperlink codes into a
-- FontString. Every peer-originated string leaves this module through `esc`.
local esc = ns.Util.Esc

local function escAll(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = esc(v) end
    return out
end

local function recipeName(store, id)
    return esc(ns.Names.Recipe(id, store.GetRecipe(id)))
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
                    out[#out + 1] = { key = key, name = esc(ns.Names.Profession(key, p)) }
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

-- True while the player has professions but none of them has any stored recipe: the UI then shows a "CLICK HERE ->"
-- hint next to the profession buttons. It disappears as soon as one profession has been read.
function Model.NeedsScanHint(rows)
    if #rows == 0 then return false end
    for _, r in ipairs(rows) do
        if r.count > 0 then return false end
    end
    return true
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
                                professionKey = key, profession = esc(ns.Names.Profession(key, p)), crafters = {} }
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
        c.professionName = esc(ns.Names.Profession(ns.Names.ProfKey(c.profession, c.pentry), c.pentry))
        -- c.name stays raw: it is also the whisper target, and character names can never contain "|" (Util.IsSafeName)
    end
    for _, r in ipairs(e and e.reagents or {}) do
        local have = haveFn and haveFn(r.itemID) or 0
        d.reagents[#d.reagents + 1] = { itemID = r.itemID, count = r.count,
            name = esc((nameFn and nameFn(r.itemID)) or r.name or ns.Locale.Fmt(ns.L["Item #{id}"], { id = r.itemID })),
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
                note = esc(o.note), requester = esc(o.requester), status = st, claimers = escAll(claimers), createdAt = o.createdAt,
                canClaim = live and not iClaimed and knows(o.recipeID),
                canWithdraw = live and iClaimed or false,
                canDone = live and (o.requester == me or iClaimed) or false,
                canCancel = live and o.requester == me }
        end
    end
    return rows
end

------------------------------------------------------------------ recipe items board (feature 007)

-- "Bags x2", "Guild bank tab 3 x1": location label for the viewer's language (stored data holds only the location key)
function Model.LocLabel(loc, count)
    local L = ns.L
    local text
    if loc == "bag" then text = L["Bags"]
    elseif loc == "bank" then text = L["Bank"]
    elseif loc == "reagent" then text = L["Reagent bank"]
    elseif loc == "mail" then text = L["Mail"]
    elseif loc == "auction" then text = L["Auctions"]
    else text = ns.Locale.Fmt(L["Guild bank tab {n}"], { n = tonumber(tostring(loc):match("^gbank(%d)$")) or 0 }) end
    return text .. " x" .. tostring(count)
end

-- state = { text = search string, mineProf = only items for my professions, me = "Name-Realm" }
-- classFn(itemID) -> classID, subClassID, icon (client item data, no loading); nameFn(itemID) -> name | nil
-- Everything that came from a peer (owner and dibber names) is escaped; item names and icons come from THIS client, and an
-- id the client does not know or that is not a recipe item is not shown (a peer cannot list arbitrary things).
function Model.BuildOfferRows(store, state, classFn, nameFn)
    local text = sortKey(state.text)
    local mySkills = {}
    local mine = store.GetChar(state.me or "")
    for key, p in pairs(mine and mine.professions or {}) do
        local canon = ns.Names.ProfKey(key, p)
        if type(canon) == "number" then mySkills[canon] = true end
    end
    local out = {}
    for _, row in ipairs(ns.Offers.List(state.me)) do
        local class, sub, icon = classFn(row.itemID)
        if class == ns.Offers.RECIPE_CLASS then
            local skill = ns.Offers.SUBCLASS_SKILL[sub]
            local keep = true
            if state.mineProf and not (skill and mySkills[skill]) then keep = false end
            local name = esc((nameFn and nameFn(row.itemID)) or ns.Locale.Fmt(ns.L["Item #{id}"], { id = row.itemID }))
            local prof = skill and esc(ns.Names.Profession(skill, { id = skill })) or nil
            if keep and text ~= "" then
                keep = sortKey(name):find(text, 1, true) ~= nil or sortKey(row.owner):find(text, 1, true) ~= nil
                    or (prof ~= nil and sortKey(prof):find(text, 1, true) ~= nil)
            end
            if keep then
                local locs = {}
                for i, l in ipairs(row.locs) do locs[i] = Model.LocLabel(l.loc, l.count) end
                local dibs = {}
                for i, d in ipairs(row.dibs) do dibs[i] = { who = esc(d.who), whoRaw = d.who, t = d.t, mine = d.who == state.me } end
                out[#out + 1] = { key = row.key, owner = row.owner, ownerName = esc(row.owner), itemID = row.itemID, name = name,
                    icon = icon, profession = prof, locations = table.concat(locs, ", "), total = row.total,
                    dibs = dibs, dibCount = #dibs, mine = row.mine, canDib = row.owner ~= state.me, ownerRev = row.ownerRev }
            end
        end
    end
    table.sort(out, function(a, b)
        local pa, pb = sortKey(a.profession or ""), sortKey(b.profession or "")
        if pa ~= pb then return pa < pb end
        local na, nb = sortKey(a.name), sortKey(b.name)
        if na ~= nb then return na < nb end
        if a.owner ~= b.owner then return a.owner < b.owner end
        return a.itemID < b.itemID
    end)
    return out
end
