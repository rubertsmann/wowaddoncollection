local ADDON, ns = ...

-- Recipe items on offer (feature 007). Pure Lua: the WoW side is Api.ScanItems, the UI side is Model/Window.
--
-- One record per character, authored ONLY by that character and replaced as a whole by the newer `rev` (like a char record):
--   offers[name] = { name, rev,
--                    items = { [itemID] = { [loc] = count } },          -- what I hold, by location
--                    dibs  = { ["Owner-Realm:itemID"] = { on = bool, t = serverTime } } }   -- MY dibs on other people's items
-- Because a record is only ever written by its author, nobody can set or remove somebody else's dib.
-- Locations: bag bank reagent mail auction gbank1..gbank8. A scan replaces only the locations it could read.
-- Local removal ("hide") is never sent: hidden[key] = the owner's rev at that time; a newer rev shows the offer again.
local Offers = {}
ns.Offers = Offers

local MAX_ID, MAX_ITEMS, MAX_DIBS, MAX_COUNT, MAX_HIDDEN = 2147483647, 300, 200, 9999, 500

Offers.RECIPE_CLASS = 9
-- recipe item subclass -> skill line id of the profession that uses it (book/others have none)
Offers.SUBCLASS_SKILL = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356,
    [10] = 755, [11] = 773 }
-- display order of locations
Offers.LOC_ORDER = { "bag", "bank", "reagent", "mail", "auction", "gbank1", "gbank2", "gbank3", "gbank4", "gbank5", "gbank6",
    "gbank7", "gbank8" }

local ORDER_INDEX = {}
for i, l in ipairs(Offers.LOC_ORDER) do ORDER_INDEX[l] = i end
function Offers.IsLoc(l) return type(l) == "string" and ORDER_INDEX[l] ~= nil end
function Offers.LocIndex(l) return ORDER_INDEX[l] or 99 end

function Offers.Key(owner, itemID) return owner .. ":" .. itemID end

-- "Owner-Realm:12345" -> owner, itemID (nil when malformed; owner must be a safe name)
function Offers.ParseKey(key)
    if type(key) ~= "string" or #key > 100 then return nil end
    local owner, id = key:match("^(.+):(%d+)$")
    id = tonumber(id)
    if not owner or not ns.Util.IsSafeName(owner) or not ns.Util.SafeInt(id, 1, MAX_ID) then return nil end
    return owner, id
end

local function db() return ns.Store.db end

------------------------------------------------------------------ validation (network and persisted data)

local function sanitizeItems(items)
    local U = ns.Util
    if type(items) ~= "table" then return nil end
    local out, n = {}, 0
    for id, locs in pairs(items) do
        n = n + 1
        if n > MAX_ITEMS or not U.SafeInt(id, 1, MAX_ID) or type(locs) ~= "table" then return nil end
        local clean, c = {}, 0
        for loc, count in pairs(locs) do
            c = c + 1
            if c > #Offers.LOC_ORDER or not Offers.IsLoc(loc) or not U.SafeInt(count, 1, MAX_COUNT) then return nil end
            clean[loc] = count
        end
        if c == 0 then return nil end
        out[id] = clean
    end
    return out
end

-- Returns a CLEAN COPY of an offers record or nil. A single bad entry rejects the whole record.
function Offers.Sanitize(rec)
    local U = ns.Util
    if type(rec) ~= "table" or not U.IsSafeName(rec.name) then return nil end
    local rev = U.SafeInt(rec.rev, 0, ns.Store.Horizon())
    if not rev then return nil end
    local items = sanitizeItems(rec.items)
    if not items then return nil end
    local dibs, n = {}, 0
    if rec.dibs ~= nil then
        if type(rec.dibs) ~= "table" then return nil end
        for key, d in pairs(rec.dibs) do
            n = n + 1
            local owner = Offers.ParseKey(key)
            if n > MAX_DIBS or not owner or owner == rec.name or type(d) ~= "table" or type(d.on) ~= "boolean"
                or not U.SafeInt(d.t, 0, ns.Store.Horizon()) then
                return nil
            end
            dibs[key] = { on = d.on, t = d.t }
        end
    end
    return { name = rec.name, rev = rev, items = items, dibs = dibs }
end

------------------------------------------------------------------ store access

function Offers.Get(name) return db().offers[name] end

-- Stores the record only if it is newer than what we hold. Returns true when stored.
function Offers.Put(rec)
    if type(rec) ~= "table" or type(rec.name) ~= "string" then return false end
    local cur = db().offers[rec.name]
    if cur and (cur.rev or 0) >= (rec.rev or 0) then return false end
    db().offers[rec.name] = rec
    return true
end

-- Re-validates persisted records (SavedVariables are untrusted on load). Returns the number dropped.
function Offers.SanitizePersisted(sv)
    local dropped, offers, hidden = 0, {}, {}
    if type(sv.offers) == "table" then
        for key, rec in pairs(sv.offers) do
            local ok, clean = pcall(Offers.Sanitize, rec)
            if ok and clean and clean.name == key then offers[key] = clean else dropped = dropped + 1 end
        end
    end
    if type(sv.hidden) == "table" then
        local n = 0
        for key, rev in pairs(sv.hidden) do
            n = n + 1
            if n <= MAX_HIDDEN and Offers.ParseKey(key) and ns.Util.SafeInt(rev, 0, 1e15) then hidden[key] = rev else dropped = dropped + 1 end
        end
    end
    sv.offers, sv.hidden = offers, hidden
    return dropped
end

------------------------------------------------------------------ my record

local function signature(rec)
    if not rec then return "" end
    local ids = {}
    for id in pairs(rec.items) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        local locs = {}
        for _, l in ipairs(Offers.LOC_ORDER) do
            if rec.items[id][l] then locs[#locs + 1] = l .. "=" .. rec.items[id][l] end
        end
        parts[#parts + 1] = id .. "{" .. table.concat(locs, ",") .. "}"
    end
    local keys = {}
    for k, d in pairs(rec.dibs or {}) do keys[#keys + 1] = k .. (d.on and "+" or "-") .. d.t end
    table.sort(keys)
    return table.concat(parts, ";") .. "|" .. table.concat(keys, ";")
end

local function emptyRecord(me) return { name = me, rev = 0, items = {}, dibs = {} } end

local function commit(me, rec, now, old)
    rec.rev = math.max(now, (old and old.rev or 0) + 1)
    db().offers[me] = rec
    return rec
end

-- scans = { [loc] = { [itemID] = count } }; a location that is NOT a key was not readable and keeps its old state.
-- Returns true when my record changed (rev bumped).
function Offers.Update(me, scans, now)
    if type(me) ~= "string" or type(scans) ~= "table" then return false end
    local old = db().offers[me]
    local rec = old and ns.Util.DeepCopy(old) or emptyRecord(me)
    for id, locs in pairs(rec.items) do
        for loc in pairs(locs) do
            if scans[loc] ~= nil then locs[loc] = nil end
        end
        if next(locs) == nil then rec.items[id] = nil end
    end
    for loc, set in pairs(scans) do
        if Offers.IsLoc(loc) and type(set) == "table" then
            for id, count in pairs(set) do
                if ns.Util.SafeInt(id, 1, MAX_ID) and ns.Util.SafeInt(count, 1, MAX_COUNT) then
                    rec.items[id] = rec.items[id] or {}
                    rec.items[id][loc] = count
                end
            end
        end
    end
    -- hard cap: never exceed what peers accept (an oversized record would be dropped whole by everyone)
    local ids = {}
    for id in pairs(rec.items) do ids[#ids + 1] = id end
    if #ids > MAX_ITEMS then
        table.sort(ids)
        for i = MAX_ITEMS + 1, #ids do rec.items[ids[i]] = nil end
    end
    if not old and next(rec.items) == nil and next(rec.dibs) == nil then return false end
    if signature(rec) == signature(old) then return false end
    commit(me, rec, now, old)
    return true
end

-- Drops MY dibs on offers that vanished: the owner's record is known and no longer lists the item. Returns true when changed.
function Offers.Maintain(me, now)
    local old = db().offers[me]
    if not old then return false end
    local rec, changed = ns.Util.DeepCopy(old), false
    for key in pairs(old.dibs) do
        local owner, id = Offers.ParseKey(key)
        local theirs = owner and db().offers[owner]
        if not owner or (theirs and not theirs.items[id]) then
            rec.dibs[key] = nil
            changed = true
        end
    end
    if not changed then return false end
    commit(me, rec, now, old)
    return true
end

-- Toggles MY dib on owner's item. Returns "on" | "off", or nil, reason ("self" | "gone" | "limit" | "unsafe").
function Offers.ToggleDib(me, owner, itemID, now)
    if owner == me then return nil, "self" end
    local theirs = owner and db().offers[owner]
    if not Offers.ParseKey(Offers.Key(owner or "", itemID or 0)) then return nil, "unsafe" end
    if not (theirs and theirs.items[itemID]) then return nil, "gone" end
    local old = db().offers[me]
    local rec = old and ns.Util.DeepCopy(old) or emptyRecord(me)
    local key = Offers.Key(owner, itemID)
    local prev = rec.dibs[key]
    local turnOn = not (prev and prev.on)
    if turnOn then
        local active = 0
        for _, d in pairs(rec.dibs) do if d.on then active = active + 1 end end
        if active >= MAX_DIBS then return nil, "limit" end
    end
    -- t only grows per key, so the newest toggle wins on every client
    rec.dibs[key] = { on = turnOn, t = math.max(now, (prev and prev.t or 0) + 1) }
    -- keep the record inside the transport/validation limit: drop the oldest switched-off entries first
    local total = 0
    for _ in pairs(rec.dibs) do total = total + 1 end
    if total > MAX_DIBS then
        local off = {}
        for k, d in pairs(rec.dibs) do if not d.on then off[#off + 1] = k end end
        table.sort(off, function(a, b) return rec.dibs[a].t < rec.dibs[b].t end)
        for i = 1, math.min(#off, total - MAX_DIBS) do rec.dibs[off[i]] = nil end
    end
    commit(me, rec, now, old)
    return turnOn and "on" or "off"
end

------------------------------------------------------------------ hide (local only)

function Offers.Hide(owner, itemID)
    local theirs = db().offers[owner]
    if not theirs then return false end
    local n = 0
    for _ in pairs(db().hidden) do n = n + 1 end
    if n >= MAX_HIDDEN then return false end
    db().hidden[Offers.Key(owner, itemID)] = theirs.rev
    return true
end

local function isHidden(owner, itemID, ownerRev)
    local h = db().hidden[Offers.Key(owner, itemID)]
    return h ~= nil and h >= ownerRev
end

-- forget hide entries that no longer apply (owner changed or left)
function Offers.PruneHidden()
    for key, rev in pairs(db().hidden) do
        local owner, id = Offers.ParseKey(key)
        local theirs = owner and db().offers[owner]
        if not theirs or theirs.rev > rev or not theirs.items[id] then db().hidden[key] = nil end
    end
end

------------------------------------------------------------------ listing

-- All visible offers: { key, owner, itemID, locs = { {loc, count}... }, total, ownerRev, dibs = { {who, t}... oldest first },
-- mine = I have an active dib }. Hidden offers are left out. Owner's own items are included (so one sees them).
function Offers.List(me)
    local index = {}   -- key -> { {who, t} }
    for who, rec in pairs(db().offers) do
        for key, d in pairs(rec.dibs or {}) do
            if d.on then
                local l = index[key]
                if not l then l = {}; index[key] = l end
                l[#l + 1] = { who = who, t = d.t }
            end
        end
    end
    local rows = {}
    for owner, rec in pairs(db().offers) do
        for id, locs in pairs(rec.items) do
            if not isHidden(owner, id, rec.rev) then
                local key = Offers.Key(owner, id)
                local list, total, dibs = {}, 0, index[key] or {}
                for loc, n in pairs(locs) do list[#list + 1] = { loc = loc, count = n }; total = total + n end
                table.sort(list, function(a, b) return Offers.LocIndex(a.loc) < Offers.LocIndex(b.loc) end)
                table.sort(dibs, function(a, b)
                    if a.t ~= b.t then return a.t < b.t end
                    return a.who < b.who
                end)
                local mine = false
                for _, d in ipairs(dibs) do if d.who == me then mine = true end end
                rows[#rows + 1] = { key = key, owner = owner, itemID = id, locs = list, total = total, ownerRev = rec.rev,
                    dibs = dibs, mine = mine }
            end
        end
    end
    return rows
end

-- counts for /ts clean
function Offers.Counts()
    local records, items = 0, 0
    for _, rec in pairs(db().offers) do
        records = records + 1
        for _ in pairs(rec.items) do items = items + 1 end
    end
    return records, items
end
