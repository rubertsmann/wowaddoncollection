-- Buy list from orders: reagent totals, full/subtract modes, Auctionator search strings and import text, and the
-- Auctionator bridge against a stub (present, missing, raising).

local function setup(harness)
    local addon = harness.addon()
    local board = addon.Orders.New(function() return harness.clock end, {})
    addon.Store.PutCatalog({
        [100] = { name = "Bronze Bar Thing", reagents = { { itemID = 2840, count = 2 }, { itemID = 2589, count = 1, name = "Linen Cloth" } } },
        [200] = { name = "Bandage", reagents = { { itemID = 2589, count = 3 } } },
        [300] = { name = "No reagents", reagents = {} },
    })
    return addon, board
end

local NAMES = { [2840] = "Copper Bar", [2589] = "Linen Cloth" }
local function itemName(itemID) return NAMES[itemID] end
local function noneOwned() return 0 end

local function byItem(result)
    local map = {}
    for _, entry in ipairs(result.items) do map[entry.itemID] = entry end
    return map
end

local function loadBridge(addon)
    local chunk = assert(loadfile("Core/Game/Auctionator.lua"))
    chunk("ProfessionShare", addon)
    return addon.AuctionatorBridge
end

local function stubAuctionator(createShoppingList)
    local calls = {}
    Auctionator = { API = { v1 = {
        ConvertToSearchString = function(_, term)
            return (term.isExact and ('"' .. term.searchString .. '"') or term.searchString) .. ";;;;;;;;;;;#;;" .. tostring(term.quantity)
        end,
        CreateShoppingList = createShoppingList or function(callerID, name, strings)
            calls[#calls + 1] = { callerID = callerID, name = name, strings = strings }
        end,
        MultiSearchAdvanced = function(callerID, terms)
            calls.searches = calls.searches or {}
            calls.searches[#calls.searches + 1] = { callerID = callerID, terms = terms }
        end,
    } } }
    return calls
end

local function auctionHouse(open)
    AuctionFrame = open and { IsShown = function() return true end } or nil
end

local function immediately(_, callback) callback() end

return {
    ["buy list: reagents x order quantity are summed per item across ticked orders"] = function(harness)
        local addon, board = setup(harness)
        local first = board:Create("Bob-R", 100, 3)
        local second = board:Create("Ann-R", 200, 2)
        local result = addon.BuyList.Build(addon.Store, board, { first.id, second.id }, { itemName = itemName, owned = noneOwned })
        local items = byItem(result)
        harness.equal(items[2840].buy, 6)          -- 2 x 3
        harness.equal(items[2589].buy, 3 + 6)      -- 1 x 3 + 3 x 2
        harness.equal(#result.items, 2)
        harness.equal(result.items[1].name, "Copper Bar")   -- sorted by name
        harness.equal(#result.missingRecipes, 0)
    end,

    ["buy list: subtract mode buys only what is missing and drops covered items"] = function(harness)
        local addon, board = setup(harness)
        local order = board:Create("Bob-R", 100, 3)
        local owned = { [2840] = 10, [2589] = 1 }
        local result = addon.BuyList.Build(addon.Store, board, { order.id },
            { subtract = true, itemName = itemName, owned = function(itemID) return owned[itemID] or 0 end })
        local items = byItem(result)
        harness.equal(items[2840], nil, "6 needed, 10 owned: nothing to buy")
        harness.equal(items[2589].buy, 2)
        harness.equal(items[2589].need, 3); harness.equal(items[2589].owned, 1)
    end,

    ["buy list: full mode ignores what I own"] = function(harness)
        local addon, board = setup(harness)
        local order = board:Create("Bob-R", 100, 1)
        local result = addon.BuyList.Build(addon.Store, board, { order.id },
            { subtract = false, itemName = itemName, owned = function() return 999 end })
        harness.equal(byItem(result)[2840].buy, 2)
    end,

    ["buy list: orders without reagent data are reported, vanished orders are skipped"] = function(harness)
        local addon, board = setup(harness)
        local empty = board:Create("Bob-R", 300, 1)
        local unknown = board:Create("Bob-R", 999, 1)
        local result = addon.BuyList.Build(addon.Store, board, { empty.id, unknown.id, "Gone-R:1:1234" },
            { itemName = itemName, owned = noneOwned })
        harness.equal(#result.items, 0)
        harness.equal(#result.missingRecipes, 2)
        harness.equal(result.orderCount, 2)
    end,

    ["buy list: an item without a loaded name is reported, the scanned name is the fallback"] = function(harness)
        local addon, board = setup(harness)
        local order = board:Create("Bob-R", 100, 1)
        local result = addon.BuyList.Build(addon.Store, board, { order.id }, { itemName = function() return nil end, owned = noneOwned })
        harness.equal(#result.items, 1)
        harness.equal(result.items[1].name, "Linen Cloth")   -- scanned reagent name
        harness.equal(#result.unnamed, 1); harness.equal(result.unnamed[1], 2840)
    end,

    ["buy list: separators and quotes are stripped from item names"] = function(harness)
        local addon, board = setup(harness)
        local order = board:Create("Bob-R", 200, 1)
        local result = addon.BuyList.Build(addon.Store, board, { order.id },
            { itemName = function() return '  "Evil;^Cloth"\n ' end, owned = noneOwned })
        harness.equal(result.items[1].name, "EvilCloth")
        local onlySeparators = addon.BuyList.Build(addon.Store, board, { order.id },
            { itemName = function() return ';^"' end, owned = noneOwned })
        harness.equal(#onlySeparators.items, 0); harness.equal(#onlySeparators.unnamed, 1)
    end,

    ["buy list: empty selection gives an empty list"] = function(harness)
        local addon, board = setup(harness)
        local result = addon.BuyList.Build(addon.Store, board, {}, { itemName = itemName, owned = noneOwned })
        harness.equal(#result.items, 0); harness.equal(result.orderCount, 0)
    end,

    ["buy list: the collection takes each order once and drops orders that are gone"] = function(harness)
        local addon, board = setup(harness)
        local first = board:Create("Bob-R", 100, 1)
        local second = board:Create("Ann-R", 200, 1)
        local collection = {}
        harness.equal(addon.BuyList.CollectionAdd(collection, first.id), true)
        harness.equal(addon.BuyList.CollectionAdd(collection, first.id), false)
        addon.BuyList.CollectionAdd(collection, second.id)
        board.db[first.id] = nil
        collection[#collection + 1] = 42   -- garbage from a hand-edited file
        harness.equal(addon.BuyList.CollectionPrune(collection, board), 2)
        harness.equal(#collection, 1); harness.equal(collection[1], second.id)
    end,

    ["buy list: order rows say which mail actions are possible"] = function(harness)
        local addon, board = setup(harness)
        addon.Store.PutCatalog({ [400] = { name = "Product", produces = 9000, reagents = { { itemID = 2589, count = 1 } } } })
        local unclaimed = board:Create("Bob-R", 400, 1)
        harness.clock = harness.clock + 1
        local claimed = board:Create("Bob-R", 400, 1)
        board:Claim(claimed.id, "Me-R")
        harness.clock = harness.clock + 1
        local claimedByOther = board:Create("Me-R", 400, 1)
        board:Claim(claimedByOther.id, "Crafter-R")
        local rows = {}
        for _, row in ipairs(addon.Model.BuildOrderRows(addon.Store, board, "all", false, "Me-R")) do rows[row.id] = row end
        harness.equal(rows[unclaimed.id].canMailMats, false, "nobody claimed it")
        harness.equal(rows[unclaimed.id].canMailItem, true)
        harness.equal(rows[claimed.id].canMailMats, false, "only I claimed it: mats to myself make no sense")
        harness.equal(rows[claimedByOther.id].canMailMats, true)
        harness.equal(rows[claimedByOther.id].canMailItem, false, "my own order: no item to myself")
    end,

    ["buy list: search term and import text match Auctionator's format"] = function(harness)
        local addon = setup(harness)
        local term = addon.BuyList.SearchTerm("Copper Bar", 6)
        harness.equal(term, '"Copper Bar";;;;;;;;;;;#;;6')
        local _, separators = term:gsub(";", "")
        harness.equal(separators, 13)   -- 14 fields
        harness.equal(addon.BuyList.ImportText("My^List\n", { "a", "b" }), "MyList^a^b")
    end,

    ["auctionator bridge: unavailable without Auctionator or without the shopping list API"] = function(harness)
        local addon = setup(harness)
        Auctionator = nil
        local bridge = loadBridge(addon)
        harness.equal(bridge.IsAvailable(), false)
        Auctionator = { API = { v1 = {} } }
        harness.equal(bridge.IsAvailable(), false)
        local ok, errorText, importText = bridge.Export("List", { { name = "Copper Bar", buy = 2 } })
        harness.equal(ok, false); harness.truthy(errorText); harness.equal(importText, 'List^"Copper Bar";;;;;;;;;;;#;;2')
        Auctionator = nil
    end,

    ["auctionator bridge: creates the list with exact terms and quantities"] = function(harness)
        local addon = setup(harness)
        local calls = stubAuctionator()
        local bridge = loadBridge(addon)
        harness.equal(bridge.IsAvailable(), true)
        local ok = bridge.Export("PS list", { { name = "Copper Bar", buy = 6 }, { name = "Linen Cloth", buy = 9 } })
        harness.equal(ok, true)
        harness.equal(#calls, 1); harness.equal(calls[1].callerID, "ProfessionShare"); harness.equal(calls[1].name, "PS list")
        harness.equal(calls[1].strings[1], '"Copper Bar";;;;;;;;;;;#;;6')
        harness.equal(calls[1].strings[2], '"Linen Cloth";;;;;;;;;;;#;;9')
        Auctionator = nil
    end,

    ["auctionator bridge: an error inside Auctionator is caught and the import text is returned"] = function(harness)
        local addon = setup(harness)
        stubAuctionator(function() error("Details: something changed") end)
        local bridge = loadBridge(addon)
        local ok, errorText, importText = bridge.Export("PS list", { { name = "Copper Bar", buy = 6 } })
        harness.equal(ok, false)
        harness.truthy(errorText:find("something changed", 1, true))
        harness.equal(importText, 'PS list^"Copper Bar";;;;;;;;;;;#;;6')
        Auctionator = nil
    end,

    ["auctionator bridge: search runs only with the auction house open, exact terms with quantities"] = function(harness)
        local addon = setup(harness)
        local calls = stubAuctionator()
        local bridge = loadBridge(addon)
        auctionHouse(false)
        local ok, errorText = bridge.Search({ { name = "Copper Bar", buy = 6 } })
        harness.equal(ok, false); harness.truthy(errorText)
        harness.equal(calls.searches, nil, "no search while the auction house is closed")
        auctionHouse(true)
        harness.equal(bridge.TakeSearchedThisVisit(), false, "no search yet")
        harness.equal(bridge.Search({ { name = "Copper Bar", buy = 6 } }), true)
        harness.equal(bridge.TakeSearchedThisVisit(), true); harness.equal(bridge.TakeSearchedThisVisit(), false, "taken once")
        local term = calls.searches[1].terms[1]
        harness.equal(calls.searches[1].callerID, "ProfessionShare")
        harness.equal(term.searchString, "Copper Bar"); harness.equal(term.isExact, true); harness.equal(term.quantity, 6)
        auctionHouse(false); Auctionator = nil
    end,

    ["auctionator bridge: a search error is caught; an old Auctionator without the search API is reported"] = function(harness)
        local addon = setup(harness)
        stubAuctionator()
        Auctionator.API.v1.MultiSearchAdvanced = function() error("Auction house is not open") end
        local bridge = loadBridge(addon)
        auctionHouse(true)
        local ok, errorText = bridge.Search({ { name = "Copper Bar", buy = 1 } })
        harness.equal(ok, false); harness.truthy(errorText:find("not open", 1, true))
        Auctionator.API.v1.MultiSearchAdvanced = nil
        ok, errorText = bridge.Search({ { name = "Copper Bar", buy = 1 } })
        harness.equal(ok, false); harness.truthy(errorText:find("MultiSearchAdvanced", 1, true))
        auctionHouse(false); Auctionator = nil
    end,

    ["auctionator bridge: a pending search runs once, on the next auction house opening"] = function(harness)
        local addon = setup(harness)
        local calls = stubAuctionator()
        local bridge = loadBridge(addon)
        local reports = {}
        local function report(ok, errorText, count) reports[#reports + 1] = { ok = ok, errorText = errorText, count = count } end
        harness.equal(bridge.RunPendingSearch(immediately, report), false, "nothing pending")
        bridge.SetPendingSearch({ { name = "Copper Bar", buy = 6 }, { name = "Linen Cloth", buy = 2 } })
        harness.equal(bridge.HasPendingSearch(), true)
        auctionHouse(true)
        harness.equal(bridge.RunPendingSearch(immediately, report), true)
        harness.equal(#calls.searches, 1); harness.equal(#calls.searches[1].terms, 2)
        harness.equal(reports[1].ok, true); harness.equal(reports[1].count, 2)
        harness.equal(bridge.HasPendingSearch(), false)
        harness.equal(bridge.RunPendingSearch(immediately, report), false, "runs only once")
        harness.equal(#calls.searches, 1)
        auctionHouse(false); Auctionator = nil
    end,

    ["auctionator bridge: a pending search is kept while Auctionator is missing"] = function(harness)
        local addon = setup(harness)
        Auctionator = nil
        local bridge = loadBridge(addon)
        bridge.SetPendingSearch({ { name = "Copper Bar", buy = 1 } })
        harness.equal(bridge.RunPendingSearch(immediately, function() error("must not report") end), false)
        harness.equal(bridge.HasPendingSearch(), true)
    end,

    ["auctionator bridge: a broken ConvertToSearchString falls back to the own format"] = function(harness)
        local addon = setup(harness)
        local calls = stubAuctionator()
        Auctionator.API.v1.ConvertToSearchString = function() error("boom") end
        local bridge = loadBridge(addon)
        harness.equal(bridge.Export("L", { { name = "Copper Bar", buy = 1 } }), true)
        harness.equal(calls[1].strings[1], '"Copper Bar";;;;;;;;;;;#;;1')
        Auctionator = nil
    end,
}
