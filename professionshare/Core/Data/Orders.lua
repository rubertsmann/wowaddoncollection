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
---@field note string at most MAXIMUM_NOTE_BYTES ("" when none)
---@field createdAt integer
---@field name? string recipe name snapshot as the requester sees it (protocol 2.2+)
---@field loc? string language code of `name`
---@field closed? "done"|"cancelled"
---@field closedAt? integer
---@field closedBy? string
---@field claims table<string, OrderClaim> by crafter
---@field msgs? OrderMessage[] chat, oldest first (protocol 2.9)
---@field ev? OrderEvent[] status changes, oldest first (protocol 2.9)
---@field ml? OrderMail[] mails sent for the order, oldest first (protocol 2.10)

---@class OrderMail
---@field m "item"|"mats" the crafted item to the requester, or reagents to a crafter
---@field b string sender
---@field r string recipient
---@field t integer server time
---@field c? boolean complete: nothing of the mail job was left to send
---@field h? boolean marked by hand (not seen going out)
---@field i? integer[] flat item list { itemID, count, itemID, count, ... }

---@class OrderMessage
---@field b string author
---@field t integer server time
---@field x string text, at most MAXIMUM_MESSAGE_BYTES

---@class OrderEvent
---@field k "claim"|"withdraw"|"done"|"cancel"
---@field b string who
---@field t integer server time

---@alias OrderStatus "open"|"claimed"|"mailed"|"done"|"cancelled"

---@class OrderBoard
---@field db table<string, Order> backing table (persisted in SavedVariables)
---@field now fun(): integer server time
local Orders = {}
addon.Orders = Orders
Orders.__index = Orders

local MAXIMUM_CLAIMS, MAXIMUM_NOTE_BYTES, MAXIMUM_ID_BYTES = 50, 80, 80
-- chat and history per order: the newest MAXIMUM_ENTRIES of each are kept; longer incoming lists are not read at all
local MAXIMUM_ENTRIES, MAXIMUM_INCOMING_ENTRIES, MAXIMUM_MESSAGE_BYTES = 30, 120, 160
Orders.MAXIMUM_ENTRIES, Orders.MAXIMUM_MESSAGE_BYTES = MAXIMUM_ENTRIES, MAXIMUM_MESSAGE_BYTES
---@type table<string, boolean>
local EVENT_KINDS = { claim = true, withdraw = true, done = true, cancel = true }
---@type table<string, boolean>
local MAIL_KINDS = { item = true, mats = true }
local MAXIMUM_MAIL_ITEMS, MAXIMUM_MAIL_COUNT = 12, 100000
Orders.MAXIMUM_MAIL_ITEMS = MAXIMUM_MAIL_ITEMS
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

-- The same for the chat and the history (kept apart from orderVersion, which peers before protocol 2.9 compute too).
---@param order Order
---@return number
local function extraVersion(order)
    local extraVersionSum = 0
    for _, message in ipairs(order.msgs or {}) do extraVersionSum = extraVersionSum + message.t end
    for _, event in ipairs(order.ev or {}) do extraVersionSum = extraVersionSum + event.t end
    return extraVersionSum
end
Orders.ExtraVersion = extraVersion

-- The same for the mail entries (protocol 2.10; kept apart so peers before 2.10, which drop them, are never pushed
-- orders for them).
---@param order Order
---@return number
local function mailVersion(order)
    local mailVersionSum = 0
    for _, mail in ipairs(order.ml or {}) do mailVersionSum = mailVersionSum + mail.t end
    return mailVersionSum
end
Orders.MailVersion = mailVersion

---@param message OrderMessage
---@return string
local function messageKey(message) return message.b .. "\0" .. message.t end
---@param event OrderEvent
---@return string
local function eventKey(event) return event.k .. "\0" .. event.b .. "\0" .. event.t end
---@param mail OrderMail
---@return string
local function mailKey(mail) return mail.m .. "\0" .. mail.b .. "\0" .. mail.t end

-- Allow-list copy of a mail entry's item list: pairs of positive integers, at most MAXIMUM_MAIL_ITEMS pairs.
---@param list any
---@return integer[]|nil items nil when absent or empty
---@return boolean ok false when the list is malformed
local function sanitizeMailItems(list)
    if list == nil then return nil, true end
    if type(list) ~= "table" or #list % 2 ~= 0 or #list > MAXIMUM_MAIL_ITEMS * 2 then return nil, false end
    local Utility, clean = addon.Utility, {}
    for index = 1, #list, 2 do
        if not Utility.SafeInteger(list[index], 1, 2147483647) or not Utility.SafeInteger(list[index + 1], 1, MAXIMUM_MAIL_COUNT) then
            return nil, false
        end
        clean[#clean + 1] = list[index]
        clean[#clean + 1] = list[index + 1]
    end
    if #clean == 0 then return nil, true end
    return clean, true
end

-- the newest MAXIMUM_ENTRIES of `entries`, oldest first, one entry per key. Ties are broken by key and text, so every
-- client keeps the same entries in the same order whatever order they arrived in.
---@param entries table[]
---@param keyOf fun(entry: table): string
---@return table[]
local function normalizeEntries(entries, keyOf)
    table.sort(entries, function(left, right)
        if left.t ~= right.t then return left.t < right.t end
        local leftKey, rightKey = keyOf(left), keyOf(right)
        if leftKey ~= rightKey then return leftKey < rightKey end
        return (left.x or "") < (right.x or "")
    end)
    local unique, seenKeys = {}, {}
    for _, entry in ipairs(entries) do
        local key = keyOf(entry)
        if not seenKeys[key] then seenKeys[key] = true; unique[#unique + 1] = entry end
    end
    while #unique > MAXIMUM_ENTRIES do table.remove(unique, 1) end
    return unique
end

-- Allow-list copy of a chat or history list. A bad entry is dropped, never the whole order (the rest of the order is
-- still good); a list that is not a table, or one too long to read, counts as empty.
---@param list any
---@param kind "msgs"|"ev"|"ml"
---@return table[]|nil
local function sanitizeEntries(list, kind)
    if type(list) ~= "table" or #list > MAXIMUM_INCOMING_ENTRIES then return nil end
    local Utility, horizon = addon.Utility, addon.Store.Horizon()
    local clean = {}
    for _, entry in ipairs(list) do
        if type(entry) == "table" and Utility.IsSafeName(entry.b) and Utility.SafeInteger(entry.t, 0, horizon) then
            if kind == "msgs" then
                local text = Utility.CleanString(entry.x, MAXIMUM_MESSAGE_BYTES)
                if text and text:find("%S") then clean[#clean + 1] = { b = entry.b, t = entry.t, x = text } end
            elseif kind == "ml" then
                local items, itemsOk = sanitizeMailItems(entry.i)
                if MAIL_KINDS[entry.m] and Utility.IsSafeName(entry.r) and itemsOk
                    and (entry.c == nil or entry.c == true) and (entry.h == nil or entry.h == true) then
                    clean[#clean + 1] = { m = entry.m, b = entry.b, r = entry.r, t = entry.t, c = entry.c, h = entry.h, i = items }
                end
            elseif EVENT_KINDS[entry.k] then
                clean[#clean + 1] = { k = entry.k, b = entry.b, t = entry.t }
            end
        end
    end
    if #clean == 0 then return nil end
    return normalizeEntries(clean, kind == "msgs" and messageKey or kind == "ml" and mailKey or eventKey)
end

-- stored list + incoming list -> the merged list and whether it differs from the stored one
---@param stored table[]|nil
---@param incoming table[]|nil
---@param keyOf fun(entry: table): string
---@return table[]|nil merged
---@return boolean changed
local function mergeEntries(stored, incoming, keyOf)
    if not incoming then return stored, false end
    local combined = {}
    for _, entry in ipairs(stored or {}) do combined[#combined + 1] = entry end
    for _, entry in ipairs(incoming) do combined[#combined + 1] = entry end
    local merged = normalizeEntries(combined, keyOf)
    local changed = #merged ~= #(stored or {})
    if not changed then
        for index, entry in ipairs(merged) do
            if keyOf(entry) ~= keyOf(stored[index]) or entry.x ~= stored[index].x then changed = true; break end
        end
    end
    return merged, changed
end

---@param orderID string
---@return Order|nil
function Orders:Get(orderID) return self.db[orderID] end

---@param order Order
---@return OrderStatus
function Orders:Status(order)
    if order.closed == "cancelled" then return "cancelled" end
    if order.closed == "done" then return "done" end
    for _, mail in ipairs(order.ml or {}) do
        if mail.m == "item" and mail.c then return "mailed" end
    end
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
        closedBy = order.closedBy, claims = claims, name = recipeName, loc = recipeName and languageCode or nil,
        msgs = sanitizeEntries(order.msgs, "msgs"), ev = sanitizeEntries(order.ev, "ev"), ml = sanitizeEntries(order.ml, "ml") }
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
    local messagesChanged, eventsChanged, mailsChanged
    stored.msgs, messagesChanged = mergeEntries(stored.msgs, incoming.msgs, messageKey)
    stored.ev, eventsChanged = mergeEntries(stored.ev, incoming.ev, eventKey)
    stored.ml, mailsChanged = mergeEntries(stored.ml, incoming.ml, mailKey)
    return changed or messagesChanged or eventsChanged or mailsChanged or orderVersion(stored) ~= versionBefore
end

-- A copy of the order without its chat (ORDER broadcasts: the chat travels as OMSG and with OPUSH).
---@param order Order
---@return Order
function Orders.WithoutChat(order)
    local copy = {}
    for key, value in pairs(order) do copy[key] = value end
    copy.msgs = nil
    return copy
end

-- Adds a chat message by `author`; its time is after the author's previous message on this order, so the key is unique.
-- Returns the message, or nil (unknown order, empty or invalid text). Text longer than MAXIMUM_MESSAGE_BYTES is cut.
---@param orderID string
---@param author string
---@param text string
---@return OrderMessage|nil
function Orders:AddMessage(orderID, author, text)
    local order = self.db[orderID]
    if not order or type(text) ~= "string" then return nil end
    local Utility = addon.Utility
    text = Utility.StripControlCharacters(text):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or not Utility.IsValidUtf8(text) then return nil end
    text = Utility.TruncateUtf8(text, MAXIMUM_MESSAGE_BYTES)
    local messageTime = self.now()
    for _, message in ipairs(order.msgs or {}) do
        if message.b == author and message.t >= messageTime then messageTime = message.t + 1 end
    end
    local message = { b = author, t = messageTime, x = text }
    order.msgs = mergeEntries(order.msgs, { message }, messageKey)
    return message
end

-- Merges one chat message (OMSG) into a known order. Returns true when it was new.
---@param orderID any
---@param message any
---@return boolean
function Orders:MergeMessage(orderID, message)
    local order = type(orderID) == "string" and self.db[orderID]
    if not order then return false end
    local clean = sanitizeEntries({ message }, "msgs")
    if not clean then return false end
    local changed
    order.msgs, changed = mergeEntries(order.msgs, clean, messageKey)
    return changed
end

-- Records a mail sent for the order (`entry` as built by MailQueue.MailEntry: m, b, r, c?, h?, i?). Its time is after the
-- sender's previous mail of the same kind on this order, so the key is unique. Returns the stored entry, or nil
-- (unknown order, invalid entry).
---@param orderID string
---@param entry table
---@return OrderMail|nil
function Orders:RecordMail(orderID, entry)
    local order = type(orderID) == "string" and self.db[orderID]
    if not order or type(entry) ~= "table" then return nil end
    local mailTime = self.now()
    for _, mail in ipairs(order.ml or {}) do
        if mail.m == entry.m and mail.b == entry.b and mail.t >= mailTime then mailTime = mail.t + 1 end
    end
    local clean = sanitizeEntries({ { m = entry.m, b = entry.b, r = entry.r, t = mailTime, c = entry.c, h = entry.h, i = entry.i } }, "ml")
    if not clean then return nil end
    order.ml = mergeEntries(order.ml, clean, mailKey)
    return clean[1]
end

---@param order Order
---@param kind "claim"|"withdraw"|"done"|"cancel"
---@param who string
---@param eventTime integer
local function recordEvent(order, kind, who, eventTime)
    order.ev = mergeEntries(order.ev, { { k = kind, b = who, t = eventTime } }, eventKey)
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
    recordEvent(order, state == "claimed" and "claim" or "withdraw", crafter, order.claims[crafter].t)
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
    recordEvent(order, closeKind == "done" and "done" or "cancel", closedBy, order.closedAt)
    return order
end

---@class OrderFilter
---@field status? OrderStatus
---@field requester? string
---@field crafter? string
---@field recipeID? integer
---@field showClosed? boolean

---@type table<OrderStatus, integer>
local STATUS_RANK = { open = 1, claimed = 2, mailed = 3, done = 4, cancelled = 5 }

-- open first, then claimed, mailed, done, cancelled; newest first within each
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

-- { [orderID] = ExtraVersion } for those of the newest `limit` orders that have chat or history (the "xdig" field of
-- HELLO, protocol 2.9)
---@param limit? integer default 100
---@return table<string, number>
function Orders:ExtraDigest(limit)
    local orders = {}
    for _, order in pairs(self.db) do orders[#orders + 1] = order end
    table.sort(orders, function(left, right) return left.createdAt > right.createdAt end)
    local digest = {}
    for index = 1, math.min(limit or 100, #orders) do
        local version = extraVersion(orders[index])
        if version > 0 then digest[orders[index].id] = version end
    end
    return digest
end

-- { [orderID] = MailVersion } for those of the newest `limit` orders that have mail entries (the "mdig" field of HELLO,
-- protocol 2.10)
---@param limit? integer default 100
---@return table<string, number>
function Orders:MailDigest(limit)
    local orders = {}
    for _, order in pairs(self.db) do orders[#orders + 1] = order end
    table.sort(orders, function(left, right) return left.createdAt > right.createdAt end)
    local digest = {}
    for index = 1, math.min(limit or 100, #orders) do
        local version = mailVersion(orders[index])
        if version > 0 then digest[orders[index].id] = version end
    end
    return digest
end

-- Is my part (`mine` > 0) missing from or older in the remote digest entry?
---@param remoteDigest table<string, any>|nil
---@param orderID string
---@param mine number
---@return boolean
local function behind(remoteDigest, orderID, mine)
    if type(remoteDigest) ~= "table" or mine <= 0 then return false end
    local remote = remoteDigest[orderID]
    return remote == nil or (type(remote) == "number" and remote < mine)
end

-- Orders I hold that the remote digest lacks or has an older version of (at most `limit`, newest first). With the
-- remote's extra digest (a 2.9 peer) also the orders whose chat or history the peer has less of, and with its mail
-- digest (2.10) those whose mail entries it has less of; a peer without them would drop that part anyway, so it is
-- never sent an order for it.
---@param remoteDigest table<string, any>
---@param limit? integer default 40
---@param remoteExtraDigest? table<string, any>
---@param remoteMailDigest? table<string, any>
---@return Order[]
function Orders:Missing(remoteDigest, limit, remoteExtraDigest, remoteMailDigest)
    local missingOrders = {}
    for orderID, order in pairs(self.db) do
        local remoteVersion = remoteDigest[orderID]
        local missing = remoteVersion == nil or (type(remoteVersion) == "number" and remoteVersion < orderVersion(order))
        missing = missing or behind(remoteExtraDigest, orderID, extraVersion(order))
            or behind(remoteMailDigest, orderID, mailVersion(order))
        if missing then missingOrders[#missingOrders + 1] = order end
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
