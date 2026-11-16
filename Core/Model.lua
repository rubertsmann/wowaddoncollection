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

-- An order's recipe name: the catalog when the viewer has the recipe, else the snapshot the requester sent (2.2), and only
-- then a spell lookup by recipe id (unreliable on Forever: recipe ids are not spell ids).
function Model.OrderRecipeName(store, o)
    if store.GetRecipe(o.recipeID) or not o.name then return recipeName(store, o.recipeID) end
    return esc(o.name)
end

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

------------------------------------------------------------------ item categories + free-text search (feature 011)
-- A recipe's category comes from the item it makes (catalog `produces`) and the CLIENT's item data (class, subclass,
-- equip slot); nothing about it is sent or stored. Recipes without an item (enchants, old catalog entries) are "none".
Model.CAT_NONE = "none"
local SLOT_ALIAS = { INVTYPE_ROBE = "INVTYPE_CHEST" }
local SLOT_ORDER = {}
for i, slot in ipairs({ "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_BODY",
    "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER",
    "INVTYPE_TRINKET", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }) do SLOT_ORDER[slot] = i end
-- group order: armor, weapons, consumables, containers, quivers, projectiles, trade goods, then by class id, "none" last
local GROUP_ORDER = { [4] = 1, [2] = 2, [0] = 3, [1] = 4, [11] = 5, [6] = 6, [7] = 7 }

-- classID, subClassID, equipLoc (client item data) -> category key, group id (-1 = no item)
function Model.CategoryKey(classID, subID, equipLoc)
    if type(classID) ~= "number" then return Model.CAT_NONE, -1 end
    if classID == 4 and type(equipLoc) == "string" and equipLoc:find("^INVTYPE_") and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        return "slot:" .. (SLOT_ALIAS[equipLoc] or equipLoc), 4
    end
    return ("class:%d:%d"):format(classID, tonumber(subID) or 0), classID
end

local function groupRank(g)
    if g == -1 then return 100000 end
    return GROUP_ORDER[g] or (100 + g)
end

local function recipeCategory(store, recipeID, classFn)
    local e = store.GetRecipe(recipeID)
    local item = e and e.produces
    if not item or not classFn then return Model.CAT_NONE, -1 end
    local ok, classID, subID, equipLoc = pcall(classFn, item)
    if not ok then return Model.CAT_NONE, -1 end
    return Model.CategoryKey(classID, subID, equipLoc)
end

-- Searchable text from tooltip lines (viewer's client, never a peer): drops the first line (the item name, searched
-- anyway) and every UI escape sequence, keeps at most maxLen bytes (cut on a UTF-8 character boundary).
function Model.TooltipSearchText(lines, maxLen)
    local out = {}
    for i, l in ipairs(type(lines) == "table" and lines or {}) do
        if i > 1 and type(l) == "string" then
            l = l:gsub("|4([^:;|]*):[^;|]*;", "%1")     -- plural "|4Sek.:Sek.;" -> "Sek."
                :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
                :gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
                :gsub("|", ""):gsub("%s+", " ")
            l = l:match("^%s*(.-)%s*$")
            if l ~= "" then out[#out + 1] = l end
        end
    end
    local s = table.concat(out, " ")
    if maxLen and #s > maxLen then
        local cut = maxLen
        while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 128 and s:byte(cut + 1) < 192 do cut = cut - 1 end
        s = s:sub(1, cut)
    end
    return s
end

-- state = { profession = canonical key|nil, text = string, mineOnly = bool, me = "Name-Realm",
--           categories = { [categoryKey] = true } (nil or empty = all) }
-- nameFn(itemID) -> cached item name or nil (reagent search)
-- fns (optional) = { class = fn(itemID) -> classID, subClassID, equipLoc; label = fn(categoryKey) -> text;
--                    text = fn(itemID) -> effect/tooltip text or nil }
-- Search is free text: every word must appear somewhere in name, profession, reagents, category or the item's text.
function Model.BuildRecipeRows(store, state, nameFn, fns)
    fns = fns or {}
    local words = {}
    for w in sortKey(state.text):gmatch("%S+") do words[#words + 1] = w end
    local cats = type(state.categories) == "table" and next(state.categories) and state.categories or nil
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
                            row.category, row.group = recipeCategory(store, id, fns.class)
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
        local keep = not cats or cats[row.category] == true
        if keep and #words > 0 then
            local e = store.GetRecipe(row.recipeID)
            local parts = { row.name, row.profession }
            for _, r in ipairs(e and e.reagents or {}) do
                parts[#parts + 1] = (nameFn and nameFn(r.itemID)) or r.name   -- the viewer's client first
            end
            if fns.label then parts[#parts + 1] = fns.label(row.category) end
            if fns.text and e and e.produces then parts[#parts + 1] = fns.text(e.produces) end
            local hay = {}
            for _, v in ipairs(parts) do if type(v) == "string" then hay[#hay + 1] = sortKey(v) end end
            hay = table.concat(hay, "\n")
            for _, w in ipairs(words) do
                if not hay:find(w, 1, true) then keep = false; break end
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

-- The categories present for the current profession / "mine only" choice (ignores text and the category choice itself):
-- { { group = id, label = text, cats = { { key, label, n }, ... } }, ... } in display order.
-- fns.groupLabel(groupID) -> text, fns.label(key) -> text.
function Model.RecipeCategories(store, state, fns)
    fns = fns or {}
    local rows = Model.BuildRecipeRows(store, { profession = state.profession, mineOnly = state.mineOnly, me = state.me,
        text = "" }, nil, { class = fns.class })
    local groups, byGroup, byKey = {}, {}, {}
    for _, row in ipairs(rows) do
        local c = byKey[row.category]
        if not c then
            local g = byGroup[row.group]
            if not g then
                g = { group = row.group, label = tostring((fns.groupLabel and fns.groupLabel(row.group)) or row.group), cats = {} }
                byGroup[row.group] = g
                groups[#groups + 1] = g
            end
            c = { key = row.category, label = tostring((fns.label and fns.label(row.category)) or row.category), n = 0 }
            byKey[row.category] = c
            g.cats[#g.cats + 1] = c
        end
        c.n = c.n + 1
    end
    table.sort(groups, function(a, b)
        local x, y = groupRank(a.group), groupRank(b.group)
        if x ~= y then return x < y end
        return sortKey(a.label) < sortKey(b.label)
    end)
    for _, g in ipairs(groups) do
        table.sort(g.cats, function(a, b)
            local x, y = SLOT_ORDER[a.key:match("^slot:(.+)$") or ""] or 99, SLOT_ORDER[b.key:match("^slot:(.+)$") or ""] or 99
            if x ~= y then return x < y end
            local la, lb = sortKey(a.label), sortKey(b.label)
            if la ~= lb then return la < lb end
            return a.key < b.key
        end)
    end
    return groups
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
            rows[#rows + 1] = { id = o.id, recipeID = o.recipeID, recipeName = Model.OrderRecipeName(store, o), qty = o.qty,
                note = esc(o.note), requester = esc(o.requester), status = st, claimers = escAll(claimers), createdAt = o.createdAt,
                canClaim = live and not iClaimed and knows(o.recipeID),
                canCraft = live and knows(o.recipeID) or false,
                claimersRaw = claimers,
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

------------------------------------------------------------------ craft and whisper from lists (feature 009)

-- The own profession that holds recipeID, as an OwnProfessions row (spellName/spells for CastMacro), or nil + why:
-- "unknown" (I do not know the recipe), "noprof" (my record has it, but the profession is not in my live spellbook).
function Model.CraftTarget(store, me, recipeID, live)
    local rec = store.GetChar(me or "")
    local key
    for pname, p in pairs(rec and rec.professions or {}) do
        if p.recipes and p.recipes[recipeID] then key = ns.Names.ProfKey(pname, p) break end
    end
    if not key then return nil, "unknown" end
    for _, row in ipairs(Model.OwnProfessions(store, me, live)) do
        if row.key == key and type(row.spellName) == "string" and row.spellName ~= "" then return row end
    end
    return nil, "noprof"
end

-- Whom an icon click on an order row whispers: the requester, or on my own order the first claimer (nil: nobody but me).
function Model.OrderContact(row, me)
    if row.requester ~= me then return row.requester end
    for _, c in ipairs(row.claimersRaw or row.claimers or {}) do
        if c ~= me then return c end
    end
    return nil
end

-- Whom an icon click on a recipe row whispers: the first crafter (Store.Crafters order: highest rank) who is not me.
function Model.RecipeContact(crafters, me)
    for _, c in ipairs(crafters or {}) do
        local name = type(c) == "table" and c.name or c
        if name ~= me then return name end
    end
    return nil
end

-- Text inserted into a whisper. link: a hyperlink built by THIS client (Api.RecipeLink), else the recipe name as plain
-- "[Name]" with every "|" and bracket removed, so text a peer sent can never become a link or escape code in chat.
function Model.ChatText(link, name, qty)
    local t = link
    if type(t) ~= "string" or t == "" then
        t = "[" .. (tostring(name or "?"):gsub("[|%[%]\r\n]", "")) .. "]"
    end
    if qty and qty > 1 then t = t .. " x" .. qty end
    return t
end
