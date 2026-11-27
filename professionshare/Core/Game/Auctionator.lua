local addonName, addon = ...

-- Optional bridge to the Auctionator addon (OptionalDeps in the TOC): the only file that touches Auctionator. Everything
-- goes through its public API (Auctionator.API.v1) and every call is protected, so a missing, old or changed Auctionator
-- can never break this addon; on failure the caller gets the error and the list as Auctionator import text instead.

---@class AuctionatorBridge
local Bridge = {}
addon.AuctionatorBridge = Bridge

local CALLER_ID = "ProfessionShare"

---@return table|nil Auctionator.API.v1
local function apiV1()
    local auctionator = rawget(_G, "Auctionator")
    local api = type(auctionator) == "table" and rawget(auctionator, "API")
    local v1 = type(api) == "table" and rawget(api, "v1")
    if type(v1) == "table" then return v1 end
end

-- true when Auctionator is loaded and offers shopping lists through its API
---@return boolean
function Bridge.IsAvailable()
    local v1 = apiV1()
    return v1 ~= nil and type(v1.CreateShoppingList) == "function"
end

-- One exact search term per item; Auctionator builds it when it can, the own format is the fallback.
---@param buyItems { name: string, buy: integer }[]
---@return string[]
function Bridge.SearchStrings(buyItems)
    local v1 = apiV1()
    local convert = v1 and type(v1.ConvertToSearchString) == "function" and v1.ConvertToSearchString
    local searchStrings = {}
    for index, buyItem in ipairs(buyItems) do
        local searchString
        if convert then
            local ok, converted = pcall(convert, CALLER_ID,
                { searchString = buyItem.name, isExact = true, categoryKey = "", quantity = buyItem.buy })
            if ok and type(converted) == "string" and converted ~= "" then searchString = converted end
        end
        searchStrings[index] = searchString or addon.BuyList.SearchTerm(buyItem.name, buyItem.buy)
    end
    return searchStrings
end

-- the auction house window is open (the same check Auctionator's search API makes: AuctionFrame on the legacy
-- auction house, AuctionHouseFrame on the modern one)
---@return boolean
function Bridge.IsAuctionHouseOpen()
    for _, frameName in ipairs({ "AuctionFrame", "AuctionHouseFrame" }) do
        local frame = rawget(_G, frameName)
        if type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() then return true end
    end
    return false
end

-- Starts an Auctionator search for the items in its Shopping tab (MultiSearchAdvanced: switches to the tab, searches
-- at once; Auctionator shows them as its temporary list). Needs the auction house to be open.
---@param buyItems { name: string, buy: integer }[]
---@return boolean ok
---@return string|nil errorText
function Bridge.Search(buyItems)
    local v1 = apiV1()
    if not v1 or type(v1.MultiSearchAdvanced) ~= "function" then return false, "Auctionator.API.v1.MultiSearchAdvanced is not available" end
    if not Bridge.IsAuctionHouseOpen() then return false, "the auction house is not open" end
    local searchTerms = {}
    for index, buyItem in ipairs(buyItems) do
        searchTerms[index] = { searchString = buyItem.name, isExact = true, quantity = buyItem.buy }
    end
    local ok, failure = pcall(v1.MultiSearchAdvanced, CALLER_ID, searchTerms)
    if not ok then return false, tostring(failure) end
    Bridge.searchedThisVisit = true
    return true
end

---@type boolean a buy-list search ran since the auction house opened (the collected orders start fresh when it closes)
Bridge.searchedThisVisit = false

-- true once per visit in which a search ran (and resets it); called when the auction house closes
---@return boolean
function Bridge.TakeSearchedThisVisit()
    local searched = Bridge.searchedThisVisit
    Bridge.searchedThisVisit = false
    return searched
end

-- A search waiting for the next time the auction house opens (this session only; the next export replaces it).
---@type { name: string, buy: integer }[]|nil
local pendingSearch

---@param buyItems { name: string, buy: integer }[]|nil nil clears it
function Bridge.SetPendingSearch(buyItems) pendingSearch = buyItems end

---@return boolean
function Bridge.HasPendingSearch() return pendingSearch ~= nil end

-- Auctionator switches to its default tab when the auction house opens (once at once, once a frame later), so the
-- waiting search starts a moment after that. `after(seconds, callback)` is C_Timer.After in the game.
-- `report(ok, errorText, itemCount)` is told the outcome.
---@param after fun(seconds: number, callback: function)
---@param report fun(ok: boolean, errorText: string|nil, itemCount: integer)
---@return boolean scheduled
function Bridge.RunPendingSearch(after, report)
    if not pendingSearch or not Bridge.IsAvailable() then return false end
    local buyItems = pendingSearch
    pendingSearch = nil
    after(1, function()
        local ok, errorText = Bridge.Search(buyItems)
        report(ok, errorText, #buyItems)
    end)
    return true
end

-- Creates (or replaces) the Auctionator shopping list `listName`.
---@param listName string
---@param buyItems { name: string, buy: integer }[]
---@return boolean ok
---@return string|nil errorText when not ok
---@return string importText the list in Auctionator's import format (for copy and paste when not ok)
function Bridge.Export(listName, buyItems)
    local searchStrings = Bridge.SearchStrings(buyItems)
    local importText = addon.BuyList.ImportText(listName, searchStrings)
    if not Bridge.IsAvailable() then return false, "Auctionator.API.v1.CreateShoppingList is not available", importText end
    local ok, failure = pcall(apiV1().CreateShoppingList, CALLER_ID, listName, searchStrings)
    if not ok then return false, tostring(failure), importText end
    return true, nil, importText
end
