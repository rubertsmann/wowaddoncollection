local addonName, addon = ...

-- Crafting orders as a merge-able record (CRDT-style, so message arrival order never matters).
-- Merge rules: claims merge per crafter (newer t wins; tie -> "withdrawn"); closed: earliest closedAt wins
-- (tie -> "cancelled"); immutable fields are fixed by the id.
-- The field names are the wire and saved-data format and stay as they are.

---@class OrderClaim
---@field state "claimed"|"withdrawn"
---@field t integer server time of the change

---@class Order
---@field id string "Requester-Realm:createdAt:random"
---@field requester string
---@field recipeID integer
---@field qty integer quantity, 1..99
---@field note string at most MAXIMUM_NOTE_BYTES
---@field createdAt integer
---@field name? string recipe name snapshot as the requester sees it (protocol 2.2+)
---@field loc? string language code of `name`
---@field closed? "done"|"cancelled"
---@field closedAt? integer
---@field closedBy? string
---@field claims table<string, OrderClaim> by crafter

---@alias OrderStatus "open"|"claimed"|"done"|"cancelled"

---@class OrderBoard
---@field db table<string, Order> backing table (persisted in SavedVariables)
---@field now fun(): integer server time
local Orders = {}
addon.Orders = Orders
Orders.__index = Orders

local MAXIMUM_CLAIMS, MAXIMUM_NOTE_BYTES, MAXIMUM_ID_BYTES = 50, 80, 80
local SECONDS_PER_DAY = 86400

---@param now fun(): integer server time
---@param backingTable? table<string, Order>
---@return OrderBoard
function Orders.New(now, backingTable)
    return setmetatable({ db = backingTable or {}, now = now }, Orders)
end

-- A number that grows with every change of an order; peers compare it to find orders that need sending.
---@param order Order
---@return number
local function orderVersion(order)
    local orderVersionSum = order.createdAt or 0
    for _, claim in pairs(order.claims) do orderVersionSum = orderVersionSum + (claim.t or 0) end
    return orderVersionSum + (order.closedAt or 0)
end
Orders.Version = orderVersion

---@param orderID string
---@return Order|nil
function Orders:Get(orderID) return self.db[orderID] end

---@param order Order
---@return OrderStatus
function Orders:Status(order)
    if order.closed == "cancelled" then return "cancelled" end
    if order.closed == "done" then return "done" end
    for _, claim in pairs(order.claims) do
        if claim.state == "claimed" then return "claimed" end
    end
    return "open"
end

-- crafters with an active claim, sorted
---@param order Order
---@return string[]
function Orders:Claimers(order)
    local crafters = {}
    for crafter, claim in pairs(order.claims) do
        if claim.state == "claimed" then crafters[#crafters + 1] = crafter end
    end
    table.sort(crafters)
    return crafters
end

-- Allow-list copy of an order (remote or persisted): known fields only, finite bounded numbers, safe names, UTF-8 note
-- without control characters. Timestamps may not lie in the future (a far-future createdAt would never be pruned, a
-- tiny closedAt would win every merge). NOTE: whether a member may change THIS order is not checked: guild members
-- are trusted (README "Trust model").
---@param order any
---@return Order|nil
local function sanitize(order)
    local Utility = addon.Utility
    if type(order) ~= "table" then return nil end
    if not Utility.CleanString(order.id, MAXIMUM_ID_BYTES) or order.id == "" then return nil end
    if not Utility.IsSafeName(order.requester) then return nil end
    local horizon = addon.Store.Horizon()
    if not Utility.SafeInteger(order.recipeID, 1, 2147483647) then return nil end
    if not Utility.SafeInteger(order.qty, 1, 99) then return nil end
    if not Utility.SafeInteger(order.createdAt, 0, horizon) then return nil end
    local note = order.note
    -- MAXIMUM_NOTE_BYTES counts BYTES (the wire and storage limit); notes must be well-formed UTF-8 so peers never show garbage
    if note ~= nil then
        if type(note) ~= "string" or #note > MAXIMUM_NOTE_BYTES or not Utility.IsValidUtf8(note) then return nil end
        note = Utility.StripControlCharacters(note)
    end
    -- recipe name snapshot (optional, 2.2): shown when the viewer has no catalog entry for the recipe yet
    local recipeName, languageCode
    if order.name ~= nil then
        if not Utility.CleanString(order.name, 100) or order.name == "" or order.name:find("|", 1, true) then return nil end
        recipeName = order.name
        if order.loc ~= nil then
            if type(order.loc) ~= "string" or not order.loc:match("^[%a_]+$") or #order.loc > 8 then return nil end
            languageCode = order.loc
        end
    end
    if order.closed ~= nil and order.closed ~= "done" and order.closed ~= "cancelled" then return nil end
    if order.closed and not Utility.SafeInteger(order.closedAt, 0, horizon) then return nil end
    if order.closedBy ~= nil and not Utility.IsSafeName(order.closedBy) then return nil end
    if type(order.claims) ~= "table" then return nil end
    local claims, claimCount = {}, 0
    for crafter, claim in pairs(order.claims) do
        claimCount = claimCount + 1
        if claimCount > MAXIMUM_CLAIMS then return nil end
        if not Utility.IsSafeName(crafter) or type(claim) ~= "table" or not Utility.SafeInteger(claim.t, 0, horizon)
            or (claim.state ~= "claimed" and claim.state ~= "withdrawn") then
            return nil
        end
        claims[crafter] = { state = claim.state, t = claim.t }
    end
    return { id = order.id, requester = order.requester, recipeID = order.recipeID, qty = order.qty, note = note or "",
        createdAt = order.createdAt, closed = order.closed, closedAt = order.closed and order.closedAt or nil,
        closedBy = order.closedBy, claims = claims, name = recipeName, loc = recipeName and languageCode or nil }
end
Orders.Sanitize = sanitize

-- Merge a (possibly remote) order. Returns true when local state changed.
---@param incomingOrder any
---@return boolean changed
function Orders:Merge(incomingOrder)
    local incoming = sanitize(incomingOrder)
    if not incoming then return false end
    local stored = self.db[incoming.id]
    if not stored then
        self.db[incoming.id] = incoming
        return true
    end
    local versionBefore = orderVersion(stored)
    local changed = false
    if incoming.name and not stored.name then   -- a name snapshot from a 2.2 peer completes an order a 2.1 peer sent without it
        stored.name, stored.loc = incoming.name, incoming.loc
        changed = true
    end
    for crafter, incomingClaim in pairs(incoming.claims) do
        local storedClaim = stored.claims[crafter]
        if not storedClaim or incomingClaim.t > storedClaim.t
            or (incomingClaim.t == storedClaim.t and incomingClaim.state == "withdrawn" and storedClaim.state ~= "withdrawn") then
            if not storedClaim or storedClaim.t ~= incomingClaim.t or storedClaim.state ~= incomingClaim.state then
                stored.claims[crafter] = incomingClaim
                changed = true
            end
        end
    end
    if incoming.closed then
        local takeIncoming = false
        if not stored.closed then takeIncoming = true
        elseif incoming.closedAt < stored.closedAt then takeIncoming = true
        elseif incoming.closedAt == stored.closedAt and incoming.closed == "cancelled" and stored.closed ~= "cancelled" then
            takeIncoming = true
        end
        if takeIncoming and (stored.closed ~= incoming.closed or stored.closedAt ~= incoming.closedAt) then
            stored.closed, stored.closedAt, stored.closedBy = incoming.closed, incoming.closedAt, incoming.closedBy
            changed = true
        end
    end
    return changed or orderVersion(stored) ~= versionBefore
end

-- recipeName/languageCode: the recipe name as the requester sees it (catalog entry), sent along so every viewer can show it
---@param requester string
---@param recipeID integer
---@param quantity integer
---@param note? string
---@param recipeName? string
---@param languageCode? string
---@return Order|nil
function Orders:Create(requester, recipeID, quantity, note, recipeName, languageCode)
    local createdAt = self.now()
    note = note or ""
    if not addon.Utility.IsValidUtf8(note) then note = "" end
    -- never cut inside a multi-byte character; a long note must not drop the order
    note = addon.Utility.TruncateUtf8(note, MAXIMUM_NOTE_BYTES)
    local order = { id = requester .. ":" .. createdAt .. ":" .. math.random(1000, 9999), requester = requester,
        recipeID = recipeID, qty = quantity, note = note, createdAt = createdAt, claims = {},
        name = type(recipeName) == "string" and recipeName ~= "" and addon.Utility.TruncateUtf8(recipeName, 100) or nil,
        loc = languageCode }
    local clean = sanitize(order)
    if not clean then
        addon.Log.Warning("orders.create", "a new order did not pass validation and was not created",
            { requester = requester, recipeID = recipeID, quantity = quantity })
        return nil
    end
    self.db[clean.id] = clean
    return clean
end

---@param orderBoard OrderBoard
---@param orderID string
---@param crafter string
---@param state "claimed"|"withdrawn"
---@return Order|nil
local function setClaim(orderBoard, orderID, crafter, state)
    local order = orderBoard.db[orderID]
    if not order then return nil end
    local previousClaim = order.claims[crafter]
    order.claims[crafter] = { state = state, t = math.max(orderBoard.now(), (previousClaim and previousClaim.t or 0) + 1) }
    return order
end

---@param orderID string
---@param crafter string
---@return Order|nil
function Orders:Claim(orderID, crafter) return setClaim(self, orderID, crafter, "claimed") end

---@param orderID string
---@param crafter string
---@return Order|nil
function Orders:Withdraw(orderID, crafter) return setClaim(self, orderID, crafter, "withdrawn") end

-- Only the requester may cancel; the requester or an active claimer may mark done.
---@param orderID string
---@param closedBy string
---@param closeKind "done"|"cancelled"
---@return Order|nil
function Orders:Close(orderID, closedBy, closeKind)
    local order = self.db[orderID]
    if not order or order.closed then return nil end
    if closeKind == "cancelled" then
        if closedBy ~= order.requester then return nil end
    elseif closeKind == "done" then
        local claim = order.claims[closedBy]
        if closedBy ~= order.requester and not (claim and claim.state == "claimed") then return nil end
    else
        return nil
    end
    order.closed, order.closedAt, order.closedBy = closeKind, self.now(), closedBy
    return order
end

---@class OrderFilter
---@field status? OrderStatus
---@field requester? string
---@field crafter? string
---@field recipeID? integer
---@field showClosed? boolean

---@type table<OrderStatus, integer>
local STATUS_RANK = { open = 1, claimed = 2, done = 3, cancelled = 4 }

-- open first, then claimed, done, cancelled; newest first within each
---@param filter? OrderFilter
---@return Order[]
function Orders:List(filter)
    filter = filter or {}
    local selected = {}
    for _, order in pairs(self.db) do
        local status = self:Status(order)
        local keep = true
        if not filter.showClosed and (status == "done" or status == "cancelled") then keep = false end
        if keep and filter.status and status ~= filter.status then keep = false end
        if keep and filter.requester and order.requester ~= filter.requester then keep = false end
        if keep and filter.recipeID and order.recipeID ~= filter.recipeID then keep = false end
        if keep and filter.crafter then
            local claim = order.claims[filter.crafter]
            if not (claim and claim.state == "claimed") then keep = false end
        end
        if keep then selected[#selected + 1] = order end
    end
    table.sort(selected, function(left, right)
        local leftRank, rightRank = STATUS_RANK[self:Status(left)], STATUS_RANK[self:Status(right)]
        if leftRank ~= rightRank then return leftRank < rightRank end
        return left.createdAt > right.createdAt
    end)
    return selected
end

-- { [orderID] = version } for the newest `limit` orders (the "odig" field of HELLO)
---@param limit? integer default 100
---@return table<string, number>
function Orders:Digest(limit)
    local orders = {}
    for _, order in pairs(self.db) do orders[#orders + 1] = order end
    table.sort(orders, function(left, right) return left.createdAt > right.createdAt end)
    local digest = {}
    for index = 1, math.min(limit or 100, #orders) do digest[orders[index].id] = orderVersion(orders[index]) end
    return digest
end

-- Orders I hold that the remote digest lacks or has an older version of (at most `limit`, newest first).
---@param remoteDigest table<string, any>
---@param limit? integer default 40
---@return Order[]
function Orders:Missing(remoteDigest, limit)
    local missingOrders = {}
    for orderID, order in pairs(self.db) do
        local remoteVersion = remoteDigest[orderID]
        if remoteVersion == nil or (type(remoteVersion) == "number" and remoteVersion < orderVersion(order)) then
            missingOrders[#missingOrders + 1] = order
        end
    end
    table.sort(missingOrders, function(left, right) return left.createdAt > right.createdAt end)
    while #missingOrders > (limit or 40) do table.remove(missingOrders) end
    return missingOrders
end

-- removes closed orders older than 7 days and any order older than 30 days
---@param now integer server time
---@return integer removedCount
function Orders:Prune(now)
    local removedCount = 0
    for orderID, order in pairs(self.db) do
        local age = now - order.createdAt
        local closedAge = order.closedAt and (now - order.closedAt)
        if age > 30 * SECONDS_PER_DAY or (closedAge and closedAge > 7 * SECONDS_PER_DAY) then
            self.db[orderID] = nil
            removedCount = removedCount + 1
        end
    end
    return removedCount
end
