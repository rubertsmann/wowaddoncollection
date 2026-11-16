local ADDON, ns = ...

-- SavedVariables schema and queries. Pure Lua (no WoW calls) so it runs in the offline tests.
--   chars[fullName]   = { name, class, level, rev, professions = { [profName] = { name, rank, max, recipes = { [recipeID]=true } } } }
--   catalog[recipeID] = { name, icon, minSkill, produces, reagents = { { itemID, count, name? } } }
--   orders[id]        = see Orders.lua
local S = {}
ns.Store = S

-- Schema history (docs/protocol.md "Stored data"):
--   1  0.1.0 / 0.2.0   raw records as received
--   2  0.3.0           every persisted record is re-validated on load (allow-list copy); hostile or corrupt entries dropped
S.SCHEMA = 2

local DAY = 86400
local MAX_ID = 2147483647          -- recipe / item / spell ids fit a signed 32-bit integer
S.TIME_SLACK = DAY                 -- timestamps further than this into the future are rejected (clock skew is seconds)

-- Upper bound for timestamps (rev, createdAt, closedAt, claim time). If the clock is not usable yet (server time still 0,
-- or a unit test), "the future" cannot be judged: no upper bound, so a slow clock never wipes saved data.
function S.Horizon()
    local now = ns.Util.Now()
    if now < 1000000000 then return math.huge end
    return now + S.TIME_SLACK
end

local function fresh(sv)
    sv = sv or {}
    sv.schema = S.SCHEMA
    sv.chars = type(sv.chars) == "table" and sv.chars or {}
    sv.catalog = type(sv.catalog) == "table" and sv.catalog or {}
    sv.orders = type(sv.orders) == "table" and sv.orders or {}
    sv.debug = type(sv.debug) == "table" and sv.debug or {}
    sv.ui = type(sv.ui) == "table" and sv.ui or {}
    sv.profNames = type(sv.profNames) == "table" and sv.profNames or {}   -- [clientLocale][skillLineID] = name the viewer's own client reported
    return sv
end

-- Sizes of everything held locally (for /ts clean).
function S.Counts()
    local n = { chars = 0, recipes = 0, orders = 0, catalog = 0, names = 0 }
    for _ in pairs(S.db.chars) do n.chars = n.chars + 1 end
    for _ in pairs(S.db.catalog) do n.catalog = n.catalog + 1 end
    for _ in pairs(S.db.orders) do n.orders = n.orders + 1 end
    for _, byId in pairs(S.db.profNames) do for _ in pairs(byId) do n.names = n.names + 1 end end
    for _, rec in pairs(S.db.chars) do
        for _, p in pairs(rec.professions or {}) do for _ in pairs(p.recipes or {}) do n.recipes = n.recipes + 1 end end
    end
    return n
end

-- Removes every cached and synced thing. The tables are emptied IN PLACE (Orders and Sync hold references to them);
-- UI preferences, `schema` and `me` stay. Returns the counts that were removed.
function S.Clean()
    local removed = S.Counts()
    for _, key in ipairs({ "chars", "catalog", "orders", "profNames", "debug" }) do
        local t = S.db[key]
        for k in pairs(t) do t[k] = nil end
    end
    return removed
end

-- Re-validates every persisted peer record by allow-list copy and drops what fails. Returns the number dropped.
-- SavedVariables are untrusted on load: older/newer builds, hand edits and corruption all end up here.
function S.SanitizePersisted(sv)
    local dropped = 0
    local chars = {}
    if type(sv.chars) == "table" then
        for key, rec in pairs(sv.chars) do
            local ok, clean = pcall(S.SanitizeChar, rec)
            if ok and clean and clean.name == key then chars[key] = clean else dropped = dropped + 1 end
        end
    end
    sv.chars = chars
    local catalog = {}
    if type(sv.catalog) == "table" then
        for id, e in pairs(sv.catalog) do
            local ok, clean = pcall(S.SanitizeCatalogEntry, e)
            if ok and clean and ns.Util.SafeInt(id, 1, MAX_ID) then catalog[id] = clean else dropped = dropped + 1 end
        end
    end
    sv.catalog = catalog
    local orders = {}
    if type(sv.orders) == "table" and ns.Orders and ns.Orders.Sanitize then
        for id, o in pairs(sv.orders) do
            local ok, clean = pcall(ns.Orders.Sanitize, o)
            if ok and clean and clean.id == id then orders[id] = clean else dropped = dropped + 1 end
        end
    elseif type(sv.orders) == "table" then
        orders = sv.orders
    end
    sv.orders = orders
    local names = {}
    if type(sv.profNames) == "table" then
        for code, byId in pairs(sv.profNames) do
            if type(code) == "string" and #code >= 2 and #code <= 8 and code:match("^[%a_]+$") and type(byId) == "table" then
                local t = {}
                for id, name in pairs(byId) do
                    if ns.Util.SafeInt(id, 1, 1000000) and ns.Util.CleanString(name, 60) then t[id] = name else dropped = dropped + 1 end
                end
                names[code] = t
            else
                dropped = dropped + 1
            end
        end
    end
    sv.profNames = names
    return dropped
end

-- schema n -> n+1. Peer-derived caches (chars, catalog) are re-fetchable via HELLO/WANT, so migrations may simply drop
-- them; only orders (and the viewer's own record) deserve care.
local MIGRATIONS = {
    [1] = function(sv) S.SanitizePersisted(sv) end,
}

-- Returns sv, status:  "ok" | "migrated"            usable table (modified in place)
--                      "newer"                      saved by a newer build: nil table, caller must NOT overwrite the file
--                      "reset"                      not a table / corrupt schema marker: nil table, start empty
function S.Migrate(sv)
    if type(sv) ~= "table" then return nil, "reset" end
    local v = sv.schema
    if v == nil then v = 1 end
    if not ns.Util.SafeInt(v, 1, 1000000) then return nil, "reset" end
    if v > S.SCHEMA then return nil, "newer" end
    local migrated = v < S.SCHEMA
    while v < S.SCHEMA do
        local fn = MIGRATIONS[v]
        if fn then
            local ok = pcall(fn, sv)
            if not ok then sv.chars, sv.catalog = {}, {} end   -- a failed migration must not leave half-converted caches
        end
        v = v + 1
        sv.schema = v
    end
    return sv, migrated and "migrated" or "ok"
end

-- Returns sv, status. The caller assigns `sv` back to the SavedVariables global:
--   "newer": returns the ORIGINAL untouched table (so the file on disk keeps the newer data) and runs this session on a
--            throwaway database that is never saved.
function S.Init(sv)
    if sv == nil then   -- first run: nothing to migrate
        sv = fresh({})
        S.db, ns.db = sv, sv
        return sv, "ok"
    end
    local clean, status = S.Migrate(sv)
    if status == "newer" then
        local tmp = fresh({})
        tmp.readonly = true
        S.db, ns.db = tmp, tmp
        return sv, status
    end
    sv = fresh(clean)
    local dropped = S.SanitizePersisted(sv)   -- every load, not only migrations
    S.db, ns.db = sv, sv
    if dropped > 0 and ns.Debug then ns.Debug.Log("store.dropped", dropped) end
    return sv, status or "ok"
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

-- First writer wins. Every entry is rebuilt by allow-list copy, so nothing but validated fields is ever stored.
function S.PutCatalog(entries)
    if type(entries) ~= "table" then return end
    for id, e in pairs(entries) do
        if ns.Util.SafeInt(id, 1, MAX_ID) and S.db.catalog[id] == nil then
            local clean = S.SanitizeCatalogEntry(e)
            if clean then S.db.catalog[id] = clean end
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
                    profession = profName, pentry = p, rank = p.rank, max = p.max }
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

------------------------------------------------------------------ allow-list sanitizers (network and persisted data)

-- optional localization fields: id = skill line id, loc = language code of the name snapshot, name = that snapshot
local function validLoc(v) return v == nil or (type(v) == "string" and #v >= 2 and #v <= 8 and v:match("^[%a_]+$") ~= nil) end

local function validProfName(v)
    return v == nil or (ns.Util.CleanString(v, 60) ~= nil and v ~= "" and not v:find("|", 1, true))
end

function S.ValidateProfessionMeta(p)
    if p.id ~= nil and not ns.Util.SafeInt(p.id, 1, 1000000) then return false end
    if not validLoc(p.loc) then return false end
    if not validProfName(p.name) then return false end
    return true
end

-- Returns a CLEAN COPY of a character record (only known fields, bounded, finite, UTF-8, no control characters) or nil.
-- `rev` must not lie in the future (it decides which snapshot wins; +inf or a far-future value would freeze a record).
function S.SanitizeChar(rec)
    local U = ns.Util
    if type(rec) ~= "table" then return nil end
    if not U.IsSafeName(rec.name) then return nil end
    local rev = U.SafeInt(rec.rev, 0, S.Horizon())
    local level = U.SafeInt(rec.level, 1, 100)
    if not rev or not level then return nil end
    local class = rec.class
    if class ~= nil and (U.CleanString(class, 20) == nil or class:find("|", 1, true)) then return nil end
    if type(rec.professions) ~= "table" then return nil end
    local out, profs, total, count = { name = rec.name, class = class, level = level, rev = rev }, {}, 0, 0
    for pname, p in pairs(rec.professions) do
        count = count + 1
        if count > 16 then return nil end
        if type(pname) ~= "string" or pname == "" or not U.CleanString(pname, 60) or pname:find("|", 1, true)
            or type(p) ~= "table" or not S.ValidateProfessionMeta(p) then
            return nil
        end
        local rank, max = U.SafeInt(p.rank, 0, 1000), U.SafeInt(p.max, 0, 1000)
        if not rank or not max or rank > max or type(p.recipes) ~= "table" then return nil end
        local recipes = {}
        for id, v in pairs(p.recipes) do
            if not U.SafeInt(id, 1, MAX_ID) or v ~= true then return nil end
            total = total + 1
            if total > 2000 then return nil end
            recipes[id] = true
        end
        profs[pname] = { id = p.id, loc = p.loc, name = p.name, rank = rank, max = max, recipes = recipes }
    end
    out.professions = profs
    return out
end

function S.ValidateChar(rec) return S.SanitizeChar(rec) ~= nil end

-- Safe texture reference: a numeric file id, or a path made of plain path characters.
local function validIcon(v)
    if v == nil then return true end
    if type(v) == "number" then return ns.Util.SafeInt(v, 0, MAX_ID) ~= nil end
    return type(v) == "string" and ns.Util.CleanString(v, 200) ~= nil and v:match("^[%w_%-%. \\/]+$") ~= nil
end

-- Returns a clean copy of a catalog entry or nil. Optional fields must be valid or absent; a bad one rejects the entry.
function S.SanitizeCatalogEntry(e)
    local U = ns.Util
    if type(e) ~= "table" then return nil end
    if not validLoc(e.loc) then return nil end
    if e.name ~= nil and (not U.CleanString(e.name, 100) or e.name:find("|", 1, true)) then return nil end
    if not validIcon(e.icon) then return nil end
    if e.produces ~= nil and not U.SafeInt(e.produces, 1, MAX_ID) then return nil end
    if e.minSkill ~= nil and not U.SafeInt(e.minSkill, 0, 1000) then return nil end
    if type(e.reagents) ~= "table" or #e.reagents > 12 then return nil end
    local reagents = {}
    for i, r in ipairs(e.reagents) do
        if type(r) ~= "table" or not U.SafeInt(r.itemID, 1, MAX_ID) or not U.SafeInt(r.count, 1, 1000) then return nil end
        if r.name ~= nil and (not U.CleanString(r.name, 100) or r.name:find("|", 1, true)) then return nil end
        reagents[i] = { itemID = r.itemID, count = r.count, name = r.name }
    end
    return { name = e.name, loc = e.loc, icon = e.icon, produces = e.produces, minSkill = e.minSkill, reagents = reagents }
end

function S.ValidateCatalogEntry(e) return S.SanitizeCatalogEntry(e) ~= nil end
