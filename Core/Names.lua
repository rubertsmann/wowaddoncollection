local ADDON, ns = ...

-- Game names resolved for the VIEWER. Stored/sent data carries ids (plus a name snapshot tagged with its language);
-- display names are computed here, on the viewer's client. Pure Lua: WoW lookups come in through Names.env.
--   env.spellName(spellID) -> localized spell/recipe name or nil   (set by Api.lua)
local Names = {}
ns.Names = Names
Names.env = {}

local U = ns.Util
local Loc = ns.Locale

local function client() return Loc.clientCode end

-- names the viewer's own client reported: db.profNames[clientLocale][skillLineID] = name
local function learned()
    local db = ns.db
    if not db then return {} end
    db.profNames = db.profNames or {}
    local t = db.profNames[client()]
    if not t then t = {}; db.profNames[client()] = t end
    return t
end

function Names.Learn(id, name)
    if type(id) ~= "number" or type(name) ~= "string" or name == "" then return end
    local t = learned()
    if t[id] ~= name then
        t[id] = name
        Loc.version = Loc.version + 1
    end
end

-- folded name -> skill line id over every registered language and every learned name
local rev, revVersion
local function reverse()
    if rev and revVersion == Loc.version then return rev end
    rev, revVersion = {}, Loc.version
    for _, byId in pairs(Loc.professions) do
        for id, name in pairs(byId) do rev[U.SearchKey(name)] = id end
    end
    local db = ns.db
    for _, byId in pairs(db and db.profNames or {}) do
        for id, name in pairs(byId) do rev[U.SearchKey(name)] = id end
    end
    return rev
end

-- Canonical identity of a profession entry: its skill line id when known (sent by 0.2+ clients or found through the
-- name tables), else a folded-name string. Both spellings of "Cooking" give the same key.
function Names.ProfKey(key, entry)
    if entry and type(entry.id) == "number" then return entry.id end
    if type(key) == "number" then return key end
    local name = (entry and type(entry.name) == "string" and entry.name) or (type(key) == "string" and key) or "?"
    local folded = U.SearchKey(name)
    return reverse()[folded] or ("n:" .. folded)
end

-- Display name in the viewer's language.
function Names.Profession(canon, entry)
    local id = type(canon) == "number" and canon or (entry and type(entry.id) == "number" and entry.id) or nil
    local code = client()
    if id then
        local l = learned()[id]
        if l then return l end
        if entry and entry.name and entry.loc == code then return entry.name end
        local static = Loc.professions[code]
        if static and static[id] then return static[id] end
        local en = Loc.professions.enUS
        if en and en[id] then return en[id] end
    end
    if entry and type(entry.name) == "string" and entry.name ~= "" then return entry.name end
    if id then return Loc.Fmt(ns.L["Profession #{id}"], { id = id }) end
    return (tostring(canon):gsub("^n:", ""))
end

-- Recipe name in the viewer's language. `entry` is the catalog entry (may be nil).
function Names.Recipe(id, entry)
    if entry and entry.name and entry.loc == client() then return entry.name end
    local fn = Names.env.spellName
    local sp = fn and fn(id)
    if type(sp) == "string" and sp ~= "" then return sp end
    if entry and entry.name then return entry.name end
    return Loc.Fmt(ns.L["Recipe #{id}"], { id = id })
end
