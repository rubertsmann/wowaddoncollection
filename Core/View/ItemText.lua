local addonName, addon = ...

-- Effect/tooltip text of the items recipes make, for the free-text search (feature 011): "Intelligenz" finds the elixir
-- and the buff food. Read from THIS client's tooltips (its own language) through Api.ItemTooltipLines, cached in
-- db.itemText = { locale = "deDE", items = { [itemID] = text } } and never sent to anyone. The cache starts over when
-- the client language changes. Items the client has not loaded yet are requested and tried again later (MAXIMUM_TRIES).
---@class ItemTextModule
local ItemText = {}
addon.ItemText = ItemText

ItemText.MAXIMUM_TRIES = 4        -- per item and session
ItemText.MAXIMUM_BYTES = 400      -- bytes of text kept per item

---@type integer[] item ids waiting to be read
local readQueue = {}
---@type table<integer, boolean>
local isQueued = {}
---@type table<integer, integer> failed reads per item this session
local triesByItem = {}

-- the cache for the client's current language, nil before the saved data exists
---@return table<integer, string>|nil
local function cachedTexts()
    local database = addon.db
    if type(database) ~= "table" then return nil end
    local languageCode = (GetLocale and GetLocale()) or "?"
    local cache = database.itemText
    if type(cache) ~= "table" then cache = {}; database.itemText = cache end
    if cache.locale ~= languageCode or type(cache.items) ~= "table" then
        cache.locale, cache.items = languageCode, {}
    end
    return cache.items
end

-- Cached text or nil; an item without text is queued for reading (see Pump).
---@param itemID any
---@return string|nil
function ItemText.Get(itemID)
    local texts = cachedTexts()
    if not texts or type(itemID) ~= "number" then return nil end
    local text = texts[itemID]
    if type(text) == "string" then return text end
    if not isQueued[itemID] and (triesByItem[itemID] or 0) < ItemText.MAXIMUM_TRIES then
        isQueued[itemID] = true
        readQueue[#readQueue + 1] = itemID
    end
    return nil
end

-- Queues every item a known recipe makes (cheap when everything is cached already).
---@param store StoreModule
function ItemText.Prefetch(store)
    for _, catalogEntry in pairs(store.db.catalog or {}) do
        if type(catalogEntry) == "table" and type(catalogEntry.produces) == "number" then ItemText.Get(catalogEntry.produces) end
    end
end

---@return integer
function ItemText.Pending() return #readQueue end

-- Reads up to `maximumReads` queued items; returns how many texts were stored. An item the client has not loaded yet
-- counts a try and comes back with the next Get/Prefetch.
---@param maximumReads integer
---@return integer storedCount
function ItemText.Pump(maximumReads)
    local texts = cachedTexts()
    if not texts then return 0 end
    local storedCount, readCount = 0, 0
    while #readQueue > 0 and readCount < maximumReads do
        readCount = readCount + 1
        local itemID = table.remove(readQueue, 1)
        isQueued[itemID] = nil
        local ok, tooltipLines = pcall(addon.Api.ItemTooltipLines, itemID)
        if not ok then
            addon.Log.Warning("itemText.read", "reading an item tooltip failed", { itemID = itemID, error = tostring(tooltipLines) })
        end
        if ok and type(tooltipLines) == "table" then
            texts[itemID] = addon.Model.TooltipSearchText(tooltipLines, ItemText.MAXIMUM_BYTES)
            storedCount = storedCount + 1
        else
            triesByItem[itemID] = (triesByItem[itemID] or 0) + 1
        end
    end
    return storedCount
end

-- tests only
function ItemText._Reset() readQueue, isQueued, triesByItem = {}, {}, {} end
