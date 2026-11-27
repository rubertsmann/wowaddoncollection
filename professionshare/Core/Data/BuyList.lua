local addonName, addon = ...

-- Buy list from crafting orders: the reagents the chosen orders need (catalog reagents x reagent count x order
-- quantity, summed per item), optionally minus what the player already owns, as Auctionator search terms.
-- Pure: item names and owned counts come in through `options`; Core/Game/Auctionator.lua hands the list to Auctionator.

---@class BuyListItem
---@field itemID integer
---@field name string search name (separators removed)
---@field need integer total the orders need
---@field owned integer what the player holds (0 in full mode)
---@field buy integer what goes on the list

---@class BuyListResult
---@field items BuyListItem[] sorted by name
---@field missingRecipes string[] ids of chosen orders whose recipe has no reagent data
---@field unnamed integer[] item ids left out because no name is known yet
---@field orderCount integer chosen orders that still exist

---@class BuyListOptions
---@field subtract? boolean buy only need - owned
---@field owned fun(itemID: integer): integer
---@field itemName fun(itemID: integer): string|nil

local BuyList = {}
addon.BuyList = BuyList

-- Auctionator splits search terms at ";", lists at "^" and marks exact searches with quotes; none of them may appear
-- inside a name.
---@param text any
---@return string|nil
local function searchName(text)
    if type(text) ~= "string" then return nil end
    local cleaned = addon.Utility.StripControlCharacters(text):gsub('[;%^"]', ""):match("^%s*(.-)%s*$")
    if cleaned == "" then return nil end
    return cleaned
end

---@param store table
---@param orderBoard OrderBoard
---@param orderIDs string[]
---@param options BuyListOptions
---@return BuyListResult
function BuyList.Build(store, orderBoard, orderIDs, options)
    local needByItem, scannedNames, itemOrder = {}, {}, {}
    local result = { items = {}, missingRecipes = {}, unnamed = {}, orderCount = 0 }
    for _, orderID in ipairs(orderIDs) do
        local order = orderBoard:Get(orderID)
        if order then
            result.orderCount = result.orderCount + 1
            local catalogEntry = store.GetRecipe(order.recipeID)
            local reagents = catalogEntry and catalogEntry.reagents
            if not reagents or #reagents == 0 then
                result.missingRecipes[#result.missingRecipes + 1] = orderID
            else
                for _, reagent in ipairs(reagents) do
                    if not needByItem[reagent.itemID] then itemOrder[#itemOrder + 1] = reagent.itemID end
                    needByItem[reagent.itemID] = (needByItem[reagent.itemID] or 0) + reagent.count * order.qty
                    scannedNames[reagent.itemID] = scannedNames[reagent.itemID] or reagent.name
                end
            end
        end
    end
    for _, itemID in ipairs(itemOrder) do
        local need = needByItem[itemID]
        local owned = options.subtract and math.max(0, tonumber(options.owned(itemID)) or 0) or 0
        local buy = math.max(0, need - owned)
        if buy > 0 then
            local name = searchName(options.itemName(itemID)) or searchName(scannedNames[itemID])
            if name then
                result.items[#result.items + 1] = { itemID = itemID, name = name, need = need, owned = owned, buy = buy }
            else
                result.unnamed[#result.unnamed + 1] = itemID
            end
        end
    end
    table.sort(result.items, function(left, right)
        if left.name ~= right.name then return left.name < right.name end
        return left.itemID < right.itemID
    end)
    return result
end

-- An exact Auctionator search term with a quantity (the field layout of Auctionator.Search.ReconstituteAdvancedSearch:
-- query, category, item level min/max, level min/max, crafted level min/max, price min/max, quality, tier, expansion,
-- quantity).
---@param name string already cleaned by SearchName
---@param quantity integer
---@return string
function BuyList.SearchTerm(name, quantity)
    return table.concat({ '"' .. name .. '"', "", "", "", "", "", "", "", "", "", "", "#", "", tostring(quantity) }, ";")
end

-- The collected buy list: order ids gathered until the next auction house visit (db.ui.buyListOrders[character]).
---@param collection string[]
---@param orderID string
---@return boolean added false when it was already collected
function BuyList.CollectionAdd(collection, orderID)
    for _, collectedID in ipairs(collection) do if collectedID == orderID then return false end end
    collection[#collection + 1] = orderID
    return true
end

-- drops collected orders that are gone from the board; returns how many were dropped
---@param collection string[]
---@param orderBoard OrderBoard
---@return integer droppedCount
function BuyList.CollectionPrune(collection, orderBoard)
    local droppedCount = 0
    for index = #collection, 1, -1 do
        if type(collection[index]) ~= "string" or not orderBoard:Get(collection[index]) then
            table.remove(collection, index)
            droppedCount = droppedCount + 1
        end
    end
    return droppedCount
end

-- Auctionator's Shopping -> Import format: "List name^term^term" (one list per line).
---@param listName string
---@param searchTerms string[]
---@return string
function BuyList.ImportText(listName, searchTerms)
    local cleanName = tostring(listName):gsub("[%^\r\n]", "")
    if #searchTerms == 0 then return cleanName end
    return cleanName .. "^" .. table.concat(searchTerms, "^")
end
