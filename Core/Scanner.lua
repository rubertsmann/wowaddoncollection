local ADDON, ns = ...

-- Builds MY character record from Api and stores it. Re-scanning identical data does not bump `rev`.
local Scanner = {}
ns.Scanner = Scanner

-- cheap content signature (ignores rev)
local function signature(rec)
    if not rec then return "" end
    local names = {}
    for pname in pairs(rec.professions or {}) do names[#names + 1] = pname end
    table.sort(names)
    local parts = { tostring(rec.class), tostring(rec.level) }
    for _, pname in ipairs(names) do
        local p = rec.professions[pname]
        local count, sum, sumsq = 0, 0, 0
        for id in pairs(p.recipes) do
            count = count + 1
            sum = sum + id
            sumsq = (sumsq + (id * id) % 2147483647) % 2147483647
        end
        parts[#parts + 1] = table.concat({ pname, p.id or 0, p.loc or "", p.rank or 0, p.max or 0, count, sum, sumsq }, ":")
    end
    return table.concat(parts, "|")
end
Scanner.signature = signature

-- The key under which my record already holds this profession: matched by skill line id first (so a client language
-- switch renames the key instead of losing the recipes), then by name.
local function findKey(rec, id, name)
    if id then
        for key, e in pairs(rec.professions) do
            if e.id == id then return key end
        end
    end
    if rec.professions[name] then return name end
    return nil
end

-- Returns true when my stored record changed.
function Scanner.Refresh(now)
    local Store, Api = ns.Store, ns.Api
    local info = Api.GetPlayerInfo()
    if not info.name then return false end
    local old = Store.GetChar(info.name)
    local rec = old and ns.Util.DeepCopy(old) or { name = info.name, professions = {} }
    rec.class, rec.level = info.class, info.level
    rec.professions = rec.professions or {}
    local code = ns.Locale.clientCode

    -- ranks (needs no window). A nil list means "API unsupported": keep what we have (RF2).
    local list = Api.GetPlayerProfessions()
    if list then
        local present = {}
        for _, p in ipairs(list) do
            present[p.name] = true
            local oldKey = findKey(rec, p.id, p.name)
            local e = (oldKey and rec.professions[oldKey]) or { recipes = {} }
            if oldKey and oldKey ~= p.name then rec.professions[oldKey] = nil end
            e.name, e.id, e.loc, e.rank, e.max = p.name, p.id, code, p.rank, p.max
            rec.professions[p.name] = e
            ns.Names.Learn(p.id, p.name)
        end
        for pname in pairs(rec.professions) do
            if not present[pname] then rec.professions[pname] = nil end
        end
    end

    -- recipes (only while a profession window is open and its list is loaded). An empty list never wipes data (RF2).
    local open = Api.GetOpenProfession()
    if open and #open.recipes > 0 then
        local oldKey = findKey(rec, open.id, open.name)
        local e = (oldKey and rec.professions[oldKey]) or { recipes = {} }
        if oldKey and oldKey ~= open.name then rec.professions[oldKey] = nil end
        e.name, e.loc = open.name, code
        e.id = open.id or e.id
        e.rank = (open.rank and open.rank > 0) and open.rank or e.rank or 0
        e.max = (open.max and open.max > 0) and open.max or e.max or 0
        if e.rank > e.max then e.max = e.rank end
        local set, catalog = {}, {}
        for _, r in ipairs(open.recipes) do
            set[r.recipeID] = true
            catalog[r.recipeID] = { name = r.name, loc = code, icon = r.icon, produces = r.produces, reagents = r.reagents }
        end
        e.recipes = set
        rec.professions[open.name] = e
        ns.Names.Learn(e.id, open.name)
        Store.PutCatalog(catalog)
    end

    if signature(rec) == signature(old) then
        Store.db.me = info.name
        return false
    end
    rec.rev = math.max(now, ((old and old.rev) or 0) + 1)
    Store.PutChar(rec)
    Store.db.me = info.name
    return true
end

ns.Slash.scan = function()
    local changed = Scanner.Refresh(ns.Util.Now())
    local me = ns.Store.GetChar(ns.Store.db.me or "")
    local n = 0
    for _, p in pairs(me and me.professions or {}) do n = n + ns.Util.Count(p.recipes) end
    ns.Print(("scan: %s, %d recipes known"):format(changed and "updated" or "unchanged", n))
    -- why a scan finds nothing: recipes are only readable while ONE profession's recipe list is open
    local ok, open = pcall(ns.Api.GetOpenProfession)
    if not ok then
        ns.Print("profession window check failed: " .. tostring(open))
    elseif not open then
        ns.Print("no profession recipe list detected: open one profession's window (click its name, e.g. Kochkunst) and run this again")
    else
        ns.Print(("open profession: %s (id %s), %d learned recipes visible"):format(tostring(open.name), tostring(open.id), #open.recipes))
    end
end

ns.Slash.dump = function()
    local me = ns.Store.GetChar(ns.Store.db.me or "")
    if not me then ns.Print("no record yet; try /ts scan") return end
    for pname, p in pairs(me.professions) do
        ns.Print(("%s (id %s) %d/%d: %d recipes"):format(ns.Names.Profession(ns.Names.ProfKey(pname, p), p), tostring(p.id),
            p.rank or 0, p.max or 0, ns.Util.Count(p.recipes)))
    end
end
