-- View model of the "Available" tab (feature 007): what is shown, what is hidden, what is escaped.
local BIG = 1700000000

local function setup(harness)
    local addon = harness.addon({ now = BIG })
    addon.Store.db.me = "Me-R"
    addon.Store.PutCharacter({ name = "Me-R", class = "MAGE", level = 60, rev = BIG,
        professions = { Cooking = { name = "Cooking", id = 185, rank = 100, max = 300, recipes = {} } } })
    local O = addon.Offers
    O.Put({ name = "Amy-R", rev = BIG, items = { [6661] = { bag = 1, bank = 1 }, [6670] = { gbank2 = 3 }, [100] = { bag = 1 }, [555] = { bag = 1 } }, dibs = {} })
    O.Put({ name = "Bob|cffff0000X-R", rev = BIG, items = {}, dibs = {} })   -- cannot exist: Sanitize refuses the name, Put is raw on purpose
    addon.Store.db.offers["Bob|cffff0000X-R"] = nil
    O.Put({ name = "Zed-R", rev = BIG, items = { [6661] = { mail = 2 } }, dibs = { ["Amy-R:6661"] = { on = true, t = BIG + 5 } } })
    return addon
end

-- 6661 cooking recipe, 6670 leatherworking recipe, 100 a sword, 555 unknown to the client
local CLASS = { [6661] = { 9, 5, 111 }, [6670] = { 9, 1, 222 }, [100] = { 2, 7, 333 } }
local function classFn(id) local c = CLASS[id]; if c then return c[1], c[2], c[3] end end
local NAMES = { [6661] = "Recipe: Savory Deviate Delight", [6670] = "Pattern: Fine Bag", [100] = "Sword" }
local function nameFn(id) return NAMES[id] end

return {
    ["offers model: only recipe items the client knows are shown; unknown ids and other item classes are hidden (RF2)"] = function(harness)
        local addon = setup(harness)
        local rows = addon.Model.BuildOfferRows(addon.Store, { text = "", me = "Me-R" }, classFn, nameFn)
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.itemID .. "@" .. r.owner end
        table.sort(ids)
        harness.equal(table.concat(ids, ","), "6661@Amy-R,6661@Zed-R,6670@Amy-R")
    end,

    ["offers model: no item class API at all shows nothing and does not error"] = function(harness)
        local addon = setup(harness)
        harness.equal(#addon.Model.BuildOfferRows(addon.Store, { text = "", me = "Me-R" }, function() return nil end, nameFn), 0)
    end,

    ["offers model: locations, dibs, canDib and the profession come out right"] = function(harness)
        local addon = setup(harness)
        local rows = addon.Model.BuildOfferRows(addon.Store, { text = "", me = "Me-R" }, classFn, nameFn)
        local amy
        for _, r in ipairs(rows) do if r.owner == "Amy-R" and r.itemID == 6661 then amy = r end end
        harness.equal(amy.locations, "Bags x1, Bank x1"); harness.equal(amy.total, 2); harness.equal(amy.dibCount, 1); harness.equal(amy.dibs[1].whoRaw, "Zed-R")
        harness.equal(amy.canDib, true); harness.equal(amy.mine, false); harness.equal(amy.profession, "Cooking"); harness.equal(amy.icon, 111)
        harness.equal(amy.name, "Recipe: Savory Deviate Delight")
    end,

    ["offers model: search by item, owner or profession; myProfessionsOnly keeps only my professions"] = function(harness)
        local addon = setup(harness)
        local function count(state) state.me = "Me-R"; return #addon.Model.BuildOfferRows(addon.Store, state, classFn, nameFn) end
        harness.equal(count({ text = "savory" }), 2); harness.equal(count({ text = "zed" }), 1); harness.equal(count({ text = "leatherworking" }), 1)
        harness.equal(count({ text = "nothing like it" }), 0)
        harness.equal(count({ text = "", myProfessionsOnly = true }), 2, "I have Cooking only")
    end,

    ["offers model: my own offers cannot be dibbed by me; peer text is escaped; unloaded item names fall back to the id"] = function(harness)
        local addon = setup(harness)
        local rows = addon.Model.BuildOfferRows(addon.Store, { text = "", me = "Amy-R" }, classFn, function(id) if id == 6661 then return "Evil|cffff0000 Name" end end)
        for _, r in ipairs(rows) do
            if r.owner == "Amy-R" then harness.equal(r.canDib, false) end
            if r.itemID == 6661 then harness.equal(r.name, "Evil||cffff0000 Name") end
            if r.itemID == 6670 then harness.equal(r.name, "Item #6670") end
        end
    end,

    ["offers model: location labels are localized"] = function(harness)
        local addon = setup(harness)
        harness.equal(addon.Model.LocationLabel("gbank3", 2), "Guild bank tab 3 x2")
        addon.Locale.SetInterfaceLanguage("deDE")
        harness.equal(addon.Model.LocationLabel("bag", 1), "Taschen x1"); harness.equal(addon.Model.LocationLabel("gbank3", 2), "Gildenbank Reiter 3 x2")
        addon.Locale.SetInterfaceLanguage("enUS")
    end,
}
