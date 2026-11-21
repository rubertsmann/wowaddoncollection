-- Api.ScanItems against stubbed WoW globals (feature 007): which items count, which locations are read, missing APIs.
local GLOBALS = { "C_Container", "C_Item", "GetContainerNumSlots", "GetContainerItemInfo", "GetItemInfoInstant", "GetInboxNumItems",
    "GetInboxItem", "GetInboxItemLink", "GetCurrentGuildBankTab", "GetGuildBankItemLink", "GetGuildBankItemInfo", "C_AuctionHouse",
    "GetNumAuctionItems", "GetAuctionItemLink", "GetAuctionItemInfo", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "MAX_GUILDBANKSLOTS_PER_TAB" }

local function withGlobals(harness, setup, fn)
    local saved = {}
    for _, k in ipairs(GLOBALS) do saved[k] = _G[k]; _G[k] = nil end
    local ok, err = pcall(function()
        local addon = harness.addon()
        assert(loadfile("Core/Game/Api.lua"))("ProfessionShare", addon)
        setup()
        fn(addon)
    end)
    for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

-- item ids: 6661 recipe, 6662 recipe, 100 sword (class 2), 5 unknown to the client
local CLASS = { [6661] = 9, [6662] = 9, [6663] = 9, [100] = 2 }
local function instant(id) local c = CLASS[id]; if c then return id, "t", "s", "", 1234, c, 0 end end
local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[x]|h|r" end

return {
    ["items api: bags list tradeable recipe items only (bound, other classes and unknown ids are skipped), counts add up"] = function(harness)
        withGlobals(harness, function()
            NUM_BAG_SLOTS = 1
            C_Item = { GetItemInfoInstant = instant }
            local bags = { [0] = { { itemID = 6661, stackCount = 1, isBound = false }, { itemID = 6661, stackCount = 2 }, { itemID = 6662, stackCount = 1, isBound = true },
                { itemID = 100, stackCount = 1 }, { itemID = 5, stackCount = 1 } }, [1] = { false, { itemID = 6663, stackCount = 1 } } }
            C_Container = {
                GetContainerNumSlots = function(b) return bags[b] and #bags[b] or 0 end,
                GetContainerItemInfo = function(b, s) return bags[b][s] or nil end,
            }
        end, function(addon)
            local out = addon.Api.ScanItems()
            harness.equal(out.bag[6661], 3); harness.equal(out.bag[6662], nil, "soulbound recipe is not offered"); harness.equal(out.bag[100], nil)
            harness.equal(out.bag[5], nil); harness.equal(out.bag[6663], 1)
            harness.equal(out.bank, nil, "bank is not scanned while closed"); harness.equal(out.mail, nil)
            local st = addon.Api.scanStatistics
            harness.equal(st.recipes, 4); harness.equal(st.bound, 1); harness.equal(st.unknownClass, 1)
        end)
    end,

    ["items api: bank and reagent bank are read only while open; an unreadable bag set is absent, not empty"] = function(harness)
        withGlobals(harness, function()
            NUM_BAG_SLOTS = 1; NUM_BANKBAGSLOTS = 1
            C_Item = { GetItemInfoInstant = instant }
            local bags = { [0] = { { itemID = 6661, stackCount = 1 } }, [-1] = { { itemID = 6662, stackCount = 1 } }, [2] = { { itemID = 6663, stackCount = 2 } } }
            C_Container = {
                GetContainerNumSlots = function(b) return bags[b] and #bags[b] or 0 end,
                GetContainerItemInfo = function(b, s) return bags[b][s] end,
            }
        end, function(addon)
            harness.equal(addon.Api.ScanItems().bank, nil)
            addon.Api.open.bank = true
            local out = addon.Api.ScanItems()
            harness.equal(out.bank[6662], 1); harness.equal(out.bank[6663], 2)
            harness.equal(out.reagent, nil, "no reagent bank on this client: absent, so nothing is wiped")
        end)
    end,

    ["items api: no container API at all returns an empty result without errors (RF2)"] = function(harness)
        withGlobals(harness, function() end, function(addon)
            addon.Api.open.bank, addon.Api.open.mail, addon.Api.open.gbank, addon.Api.open.auction = true, true, true, true
            local out = addon.Api.ScanItems()
            harness.equal(next(out), nil)
        end)
    end,

    ["items api: erroring and legacy container APIs are survived"] = function(harness)
        withGlobals(harness, function()
            NUM_BAG_SLOTS = 0
            C_Item = { GetItemInfoInstant = instant }
            GetContainerNumSlots = function(b) if b == 0 then return 2 end error("boom") end
            GetContainerItemInfo = function(b, s)
                if s == 1 then return nil, 1, false, 1, false, false, link(6661), false, false, 6661, false end
                error("boom")
            end
        end, function(addon)
            local out = addon.Api.ScanItems()
            harness.equal(out.bag[6661], 1)
        end)
    end,

    ["items api: mail, guild bank tab and own auctions"] = function(harness)
        withGlobals(harness, function()
            C_Item = { GetItemInfoInstant = instant }
            GetInboxNumItems = function() return 2 end
            GetInboxItem = function(m, a) if m == 1 and a == 1 then return "Rezept", 6661, 1, 2 end end
            GetInboxItemLink = function(m, a) if m == 1 and a == 1 then return link(6661) end end
            GetCurrentGuildBankTab = function() return 3 end
            GetGuildBankItemLink = function(t, s) if s == 5 then return link(6662) end end
            GetGuildBankItemInfo = function() return 1, 4 end
            C_AuctionHouse = { GetNumOwnedAuctions = function() return 1 end,
                GetOwnedAuctionInfo = function() return { itemKey = { itemID = 6663 }, quantity = 1 } end }
        end, function(addon)
            addon.Api.open.mail, addon.Api.open.gbank, addon.Api.open.auction = true, true, true
            local out = addon.Api.ScanItems()
            harness.equal(out.mail[6661], 2); harness.equal(out.gbank3[6662], 4); harness.equal(out.auction[6663], 1)
            harness.equal(out.gbank1, nil)
            addon.Api.open.mail, addon.Api.open.gbank, addon.Api.open.auction = false, false, false
            local closed = addon.Api.ScanItems()
            harness.equal(closed.mail, nil); harness.equal(closed.gbank3, nil); harness.equal(closed.auction, nil)
        end)
    end,
}
