local ADDON, ns = ...

-- Crafting orders as a merge-able record (CRDT-style, so message arrival order never matters).
--   Order = { id, requester, recipeID, qty, note, createdAt,
--             closed = nil|"done"|"cancelled", closedAt, closedBy,
--             claims = { [crafter] = { state = "claimed"|"withdrawn", t = serverTime } } }
-- Merge rules: claims merge per crafter (newer t wins; tie -> "withdrawn"); closed: earliest closedAt wins
-- (tie -> "cancelled"); immutable fields are fixed by the id.
local Orders = {}
ns.Orders = Orders
Orders.__index = Orders

local MAX_CLAIMS, MAX_NOTE, MAX_ID = 50, 80, 80

-- tbl: backing table (persisted in SavedVariables); now: function -> server time
function Orders.New(now, tbl)
    return setmetatable({ db = tbl or {}, now = now }, Orders)
end

local function version(o)
    local v = o.createdAt or 0
    for _, c in pairs(o.claims) do v = v + (c.t or 0) end
    return v + (o.closedAt or 0)
end
Orders.Version = version

function Orders:Get(id) return self.db[id] end

function Orders:Status(o)
    if o.closed == "cancelled" then return "cancelled" end
    if o.closed == "done" then return "done" end
    for _, c in pairs(o.claims) do
        if c.state == "claimed" then return "claimed" end
    end
    return "open"
end

function Orders:Claimers(o)
    local out = {}
    for name, c in pairs(o.claims) do
        if c.state == "claimed" then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

-- Allow-list copy of an order (remote or persisted): known fields only, finite bounded numbers, safe names, UTF-8 note
-- without control characters. Timestamps may not lie in the future (a far-future createdAt would never be pruned, a
-- tiny closedAt would win every merge). NOTE: whether a member may change THIS order is not checked: guild members
-- are trusted (README "Trust model").
local function sanitize(o)
    local U = ns.Util
    if type(o) ~= "table" then return nil end
    if not U.CleanString(o.id, MAX_ID) or o.id == "" then return nil end
    if not U.IsSafeName(o.requester) then return nil end
    local horizon = ns.Store.Horizon()
    if not U.SafeInt(o.recipeID, 1, 2147483647) then return nil end
    if not U.SafeInt(o.qty, 1, 99) then return nil end
    if not U.SafeInt(o.createdAt, 0, horizon) then return nil end
    local note = o.note
    -- MAX_NOTE counts BYTES (the wire and storage limit); notes must be well-formed UTF-8 so peers never show garbage
    if note ~= nil then
        if type(note) ~= "string" or #note > MAX_NOTE or not U.IsValidUtf8(note) then return nil end
        note = U.StripControl(note)
    end
    if o.closed ~= nil and o.closed ~= "done" and o.closed ~= "cancelled" then return nil end
    if o.closed and not U.SafeInt(o.closedAt, 0, horizon) then return nil end
    if o.closedBy ~= nil and not U.IsSafeName(o.closedBy) then return nil end
    if type(o.claims) ~= "table" then return nil end
    local claims, n = {}, 0
    for name, c in pairs(o.claims) do
        n = n + 1
        if n > MAX_CLAIMS then return nil end
        if not U.IsSafeName(name) or type(c) ~= "table" or not U.SafeInt(c.t, 0, horizon)
            or (c.state ~= "claimed" and c.state ~= "withdrawn") then
            return nil
        end
        claims[name] = { state = c.state, t = c.t }
    end
    return { id = o.id, requester = o.requester, recipeID = o.recipeID, qty = o.qty, note = note or "",
        createdAt = o.createdAt, closed = o.closed, closedAt = o.closed and o.closedAt or nil, closedBy = o.closedBy,
        claims = claims }
end
Orders.Sanitize = sanitize

-- Merge a (possibly remote) order. Returns true when local state changed.
function Orders:Merge(incoming)
    local o = sanitize(incoming)
    if not o then return false end
    local cur = self.db[o.id]
    if not cur then
        self.db[o.id] = o
        return true
    end
    local before = version(cur)
    local changed = false
    for name, c in pairs(o.claims) do
        local mine = cur.claims[name]
        if not mine or c.t > mine.t or (c.t == mine.t and c.state == "withdrawn" and mine.state ~= "withdrawn") then
            if not mine or mine.t ~= c.t or mine.state ~= c.state then
                cur.claims[name] = c
                changed = true
            end
        end
    end
    if o.closed then
        local take = false
        if not cur.closed then take = true
        elseif o.closedAt < cur.closedAt then take = true
        elseif o.closedAt == cur.closedAt and o.closed == "cancelled" and cur.closed ~= "cancelled" then take = true end
        if take and (cur.closed ~= o.closed or cur.closedAt ~= o.closedAt) then
            cur.closed, cur.closedAt, cur.closedBy = o.closed, o.closedAt, o.closedBy
            changed = true
        end
    end
    return changed or version(cur) ~= before
end

function Orders:Create(requester, recipeID, qty, note)
    local t = self.now()
    note = note or ""
    if not ns.Util.IsValidUtf8(note) then note = "" end
    note = ns.Util.TruncateUtf8(note, MAX_NOTE)   -- never cut inside a multi-byte character; a long note must not drop the order
    local o = { id = requester .. ":" .. t .. ":" .. math.random(1000, 9999), requester = requester, recipeID = recipeID,
        qty = qty, note = note, createdAt = t, claims = {} }
    local clean = sanitize(o)
    if not clean then return nil end
    self.db[clean.id] = clean
    return clean
end

local function setClaim(self, id, crafter, state)
    local o = self.db[id]
    if not o then return nil end
    local prev = o.claims[crafter]
    o.claims[crafter] = { state = state, t = math.max(self.now(), (prev and prev.t or 0) + 1) }
    return o
end

function Orders:Claim(id, crafter) return setClaim(self, id, crafter, "claimed") end
function Orders:Withdraw(id, crafter) return setClaim(self, id, crafter, "withdrawn") end

-- how = "done" | "cancelled". Only the requester may cancel; the requester or an active claimer may mark done.
function Orders:Close(id, by, how)
    local o = self.db[id]
    if not o or o.closed then return nil end
    if how == "cancelled" then
        if by ~= o.requester then return nil end
    elseif how == "done" then
        local c = o.claims[by]
        if by ~= o.requester and not (c and c.state == "claimed") then return nil end
    else
        return nil
    end
    o.closed, o.closedAt, o.closedBy = how, self.now(), by
    return o
end

-- filter: { status=, requester=, crafter=, recipeID=, showClosed= }
function Orders:List(filter)
    filter = filter or {}
    local out = {}
    for _, o in pairs(self.db) do
        local st = self:Status(o)
        local ok = true
        if not filter.showClosed and (st == "done" or st == "cancelled") then ok = false end
        if ok and filter.status and st ~= filter.status then ok = false end
        if ok and filter.requester and o.requester ~= filter.requester then ok = false end
        if ok and filter.recipeID and o.recipeID ~= filter.recipeID then ok = false end
        if ok and filter.crafter then
            local c = o.claims[filter.crafter]
            if not (c and c.state == "claimed") then ok = false end
        end
        if ok then out[#out + 1] = o end
    end
    local rank = { open = 1, claimed = 2, done = 3, cancelled = 4 }
    table.sort(out, function(a, b)
        local ra, rb = rank[self:Status(a)], rank[self:Status(b)]
        if ra ~= rb then return ra < rb end
        return a.createdAt > b.createdAt
    end)
    return out
end

-- { [id] = version } for the newest `limit` orders
function Orders:Digest(limit)
    local list = {}
    for _, o in pairs(self.db) do list[#list + 1] = o end
    table.sort(list, function(a, b) return a.createdAt > b.createdAt end)
    local d = {}
    for i = 1, math.min(limit or 100, #list) do d[list[i].id] = version(list[i]) end
    return d
end

-- Orders I hold that the remote digest lacks or has an older version of (max `limit`).
function Orders:Missing(remote, limit)
    local out = {}
    for id, o in pairs(self.db) do
        local rv = remote[id]
        if rv == nil or (type(rv) == "number" and rv < version(o)) then out[#out + 1] = o end
    end
    table.sort(out, function(a, b) return a.createdAt > b.createdAt end)
    while #out > (limit or 40) do table.remove(out) end
    return out
end

-- closed orders older than 7 days and any order older than 30 days
function Orders:Prune(nowTs)
    local n = 0
    for id, o in pairs(self.db) do
        local age = nowTs - o.createdAt
        local closedAge = o.closedAt and (nowTs - o.closedAt)
        if age > 30 * 86400 or (closedAge and closedAge > 7 * 86400) then
            self.db[id] = nil
            n = n + 1
        end
    end
    return n
end
