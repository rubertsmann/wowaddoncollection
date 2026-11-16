-- View model of the "Available" tab (feature 007): what is shown, what is hidden, what is escaped.
local BIG = 1700000000

local function setup(h)
    local ns = h.ns({ now = BIG })
    ns.Store.db.me = "Me-R"
    ns.Store.PutChar({ name = "Me-R", class = "MAGE", level = 60, rev = BIG,
        professions = { Cooking = { name = "Cooking", id = 185, rank = 100, max = 300, recipes = {} } } })
    local O = ns.Offers
    O.Put({ name = "Amy-R", rev = BIG, items = { [6661] = { bag = 1, bank = 1 }, [6670] = { gbank2 = 3 }, [100] = { bag = 1 }, [555] = { bag = 1 } }, dibs = {} })
    O.Put({ name = "Bob|cffff0000X-R", rev = BIG, items = {}, dibs = {} })   -- cannot exist: Sanitize refuses the name, Put is raw on purpose
    ns.Store.db.offers["Bob|cffff0000X-R"] = nil
    O.Put({ name = "Zed-R", rev = BIG, items = { [6661] = { mail = 2 } }, dibs = { ["Amy-R:6661"] = { on = true, t = BIG + 5 } } })
    return ns
end

-- 6661 cooking recipe, 6670 leatherworking recipe, 100 a sword, 555 unknown to the client
local CLASS = { [6661] = { 9, 5, 111 }, [6670] = { 9, 1, 222 }, [100] = { 2, 7, 333 } }
local function classFn(id) local c = CLASS[id]; if c then return c[1], c[2], c[3] end end
local NAMES = { [6661] = "Recipe: Savory Deviate Delight", [6670] = "Pattern: Fine Bag", [100] = "Sword" }
local function nameFn(id) return NAMES[id] end

return {
    ["offers model: only recipe items the client knows are shown; unknown ids and other item classes are hidden (RF2)"] = function(h)
        local ns = setup(h)
        local rows = ns.Model.BuildOfferRows(ns.Store, { text = "", me = "Me-R" }, classFn, nameFn)
        local ids = {}
        for _, r in ipairs(rows) do ids[#ids + 1] = r.itemID .. "@" .. r.owner end
        table.sort(ids)
        h.eq(table.concat(ids, ","), "6661@Amy-R,6661@Zed-R,6670@Amy-R")
    end,

    ["offers model: no item class API at all shows nothing and does not error"] = function(h)
        local ns = setup(h)
        h.eq(#ns.Model.BuildOfferRows(ns.Store, { text = "", me = "Me-R" }, function() return nil end, nameFn), 0)
    end,

    ["offers model: locations, dibs, canDib and the profession come out right"] = function(h)
        local ns = setup(h)
        local rows = ns.Model.BuildOfferRows(ns.Store, { text = "", me = "Me-R" }, classFn, nameFn)
        local amy
        for _, r in ipairs(rows) do if r.owner == "Amy-R" and r.itemID == 6661 then amy = r end end
        h.eq(amy.locations, "Bags x1, Bank x1"); h.eq(amy.total, 2); h.eq(amy.dibCount, 1); h.eq(amy.dibs[1].whoRaw, "Zed-R")
        h.eq(amy.canDib, true); h.eq(amy.mine, false); h.eq(amy.profession, "Cooking"); h.eq(amy.icon, 111)
        h.eq(amy.name, "Recipe: Savory Deviate Delight")
    end,

    ["offers model: search by item, owner or profession; mineProf keeps only my professions"] = function(h)
        local ns = setup(h)
        local function count(state) state.me = "Me-R"; return #ns.Model.BuildOfferRows(ns.Store, state, classFn, nameFn) end
        h.eq(count({ text = "savory" }), 2); h.eq(count({ text = "zed" }), 1); h.eq(count({ text = "leatherworking" }), 1)
        h.eq(count({ text = "nothing like it" }), 0)
        h.eq(count({ text = "", mineProf = true }), 2, "I have Cooking only")
    end,

    ["offers model: my own offers cannot be dibbed by me; peer text is escaped; unloaded item names fall back to the id"] = function(h)
        local ns = setup(h)
        local rows = ns.Model.BuildOfferRows(ns.Store, { text = "", me = "Amy-R" }, classFn, function(id) if id == 6661 then return "Evil|cffff0000 Name" end end)
        for _, r in ipairs(rows) do
            if r.owner == "Amy-R" then h.eq(r.canDib, false) end
            if r.itemID == 6661 then h.eq(r.name, "Evil||cffff0000 Name") end
            if r.itemID == 6670 then h.eq(r.name, "Item #6670") end
        end
    end,

    ["offers model: location labels are localized"] = function(h)
        local ns = setup(h)
        h.eq(ns.Model.LocLabel("gbank3", 2), "Guild bank tab 3 x2")
        ns.Locale.SetUI("deDE")
        h.eq(ns.Model.LocLabel("bag", 1), "Taschen x1"); h.eq(ns.Model.LocLabel("gbank3", 2), "Gildenbank Reiter 3 x2")
        ns.Locale.SetUI("enUS")
    end,
}
