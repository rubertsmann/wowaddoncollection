local ADDON, ns = ...

-- SavedVariables schema and queries. Pure Lua (no WoW calls) so it runs in the offline tests.
--   chars[fullName]   = { name, class, level, rev, professions = { [profName] = { name, rank, max, recipes = { [recipeID]=true } } } }
--   catalog[recipeID] = { name, icon, minSkill, produces, reagents = { { itemID, count, name? } } }
--   orders[id]        = see Orders.lua
local S = {}
ns.Store = S

S.SCHEMA = 1

function S.Init(sv)
    sv = sv or {}
    sv.schema = sv.schema or S.SCHEMA
    sv.chars = sv.chars or {}
    sv.catalog = sv.catalog or {}
    sv.orders = sv.orders or {}
    sv.debug = sv.debug or {}
    sv.ui = sv.ui or {}
    S.db = sv
    ns.db = sv
    return sv
end

function S.GetChar(fullName)
    return S.db.chars[fullName]
end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
function S.PutChar(rec)
    if type(rec) ~= "table" or type(rec.name) ~= "string" then return false end
    local cur = S.db.chars[rec.name]
    if cur and (cur.rev or 0) >= (rec.rev or 0) then return false end
    S.db.chars[rec.name] = rec
    return true
end

function S.ListChars()
    local out = {}
    for _, rec in pairs(S.db.chars) do out[#out + 1] = rec end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function S.PutCatalog(entries)
    if type(entries) ~= "table" then return end
    for id, e in pairs(entries) do
        if type(id) == "number" and type(e) == "table" and S.db.catalog[id] == nil then
            S.db.catalog[id] = e
        end
    end
end

function S.GetRecipe(recipeID)
    return S.db.catalog[recipeID]
end

-- Everyone (cached) who knows recipeID, with their rank in the owning profession.
function S.Crafters(recipeID)
    local out = {}
    for _, rec in pairs(S.db.chars) do
        for profName, p in pairs(rec.professions or {}) do
            if p.recipes and p.recipes[recipeID] then
                out[#out + 1] = { name = rec.name, class = rec.class, level = rec.level, rev = rec.rev,
                    profession = profName, rank = p.rank, max = p.max }
                break
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.rank or 0) ~= (b.rank or 0) then return (a.rank or 0) > (b.rank or 0) end
        return a.name < b.name
    end)
    return out
end

-- Drop cached characters that are no longer in the guild roster (never drops `keep`).
function S.Prune(rosterNames, keep)
    local n = 0
    for name in pairs(S.db.chars) do
        if not rosterNames[name] and name ~= keep then
            S.db.chars[name] = nil
            n = n + 1
        end
    end
    return n
end

-- Structural validation for records received from the network.
function S.ValidateChar(rec)
    if type(rec) ~= "table" then return false end
    if type(rec.name) ~= "string" or #rec.name > 64 then return false end
    if type(rec.rev) ~= "number" then return false end
    if type(rec.level) ~= "number" or rec.level < 1 or rec.level > 100 then return false end
    if rec.class ~= nil and (type(rec.class) ~= "string" or #rec.class > 20) then return false end
    if type(rec.professions) ~= "table" then return false end
    local total = 0
    for pname, p in pairs(rec.professions) do
        if type(pname) ~= "string" or type(p) ~= "table" then return false end
        if type(p.rank) ~= "number" or type(p.max) ~= "number" or p.rank > p.max then return false end
        if type(p.recipes) ~= "table" then return false end
        for id, v in pairs(p.recipes) do
            if type(id) ~= "number" or v ~= true then return false end
            total = total + 1
            if total > 2000 then return false end
        end
    end
    return true
end

function S.ValidateCatalogEntry(e)
    if type(e) ~= "table" then return false end
    if e.name ~= nil and (type(e.name) ~= "string" or #e.name > 100) then return false end
    if type(e.reagents) ~= "table" or #e.reagents > 12 then return false end
    for _, r in ipairs(e.reagents) do
        if type(r) ~= "table" or type(r.itemID) ~= "number" or type(r.count) ~= "number" then return false end
    end
    return true
end
