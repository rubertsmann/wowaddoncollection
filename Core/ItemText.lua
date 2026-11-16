local ADDON, ns = ...

-- Effect/tooltip text of the items recipes make, for the free-text search (feature 011): "Intelligenz" finds the elixir
-- and the buff food. Read from THIS client's tooltips (its own language) through Api.ItemTooltipLines, cached in
-- db.itemText = { locale = "deDE", items = { [itemID] = text } } and never sent to anyone. The cache starts over when
-- the client language changes. Items the client has not loaded yet are requested and tried again later (MAX_TRIES).
local IT = {}
ns.ItemText = IT

IT.MAX_TRIES = 4      -- per item and session
IT.MAX_LEN = 400      -- bytes of text kept per item

local queue, queued, tries = {}, {}, {}

local function items()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    local loc = (GetLocale and GetLocale()) or "?"
    local c = db.itemText
    if type(c) ~= "table" then c = {}; db.itemText = c end
    if c.locale ~= loc or type(c.items) ~= "table" then
        c.locale, c.items = loc, {}
    end
    return c.items
end

-- Cached text or nil; an item without text is queued for reading (see Pump).
function IT.Get(itemID)
    local t = items()
    if not t or type(itemID) ~= "number" then return nil end
    local v = t[itemID]
    if type(v) == "string" then return v end
    if not queued[itemID] and (tries[itemID] or 0) < IT.MAX_TRIES then
        queued[itemID] = true
        queue[#queue + 1] = itemID
    end
    return nil
end

-- Queues every item a known recipe makes (cheap when everything is cached already).
function IT.Prefetch(store)
    for _, e in pairs(store.db.catalog or {}) do
        if type(e) == "table" and type(e.produces) == "number" then IT.Get(e.produces) end
    end
end

function IT.Pending() return #queue end

-- Reads up to n queued items; returns how many texts were stored. An item the client has not loaded yet counts a try
-- and comes back with the next Get/Prefetch.
function IT.Pump(n)
    local t = items()
    if not t then return 0 end
    local stored, done = 0, 0
    while #queue > 0 and done < n do
        done = done + 1
        local id = table.remove(queue, 1)
        queued[id] = nil
        local ok, lines = pcall(ns.Api.ItemTooltipLines, id)
        if ok and type(lines) == "table" then
            t[id] = ns.Model.TooltipSearchText(lines, IT.MAX_LEN)
            stored = stored + 1
        else
            tries[id] = (tries[id] or 0) + 1
        end
    end
    return stored
end

-- tests only
function IT._Reset() queue, queued, tries = {}, {}, {} end
