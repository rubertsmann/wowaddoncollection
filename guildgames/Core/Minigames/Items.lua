local addonName, addon = ...

-- AZEcaught items: the catalog of things the shop sells, the inventory (db.caught.items: id -> count) and the running
-- boosts (db.caught.boosts: id -> server time the boost ends). Pure Lua: buying spends from the wallet, using an item
-- runs the effect of its kind. Items are local only, nothing about them is sent to the guild.
--
-- A new item is one CATALOG entry. A new kind also needs an EFFECTS handler; a new group a GROUPS entry.
-- Ids are stored in SavedVariables: an id never changes and is never reused (a removed item's id goes to RETIRED).
---@class ItemsModule
local Items = {}
addon.Items = Items
local Text = addon.Text

Items.MAXIMUM_STACK = 99
Items.MAXIMUM_ID_BYTES = 24

---@class ItemGroup
---@field id string
---@field name string display text

-- shown in this order in the shop and the inventory
---@type ItemGroup[]
Items.GROUPS = {
    { id = "catch", name = Text["Catch items"] },
}

-- trap tiers: a trap catches NPCs whose classification rank is at most its tier's rank; world bosses have no rank
Items.TIER_RANK = { normal = 1, elite = 2, rare = 3 }
Items.CLASS_RANK = { normal = 1, elite = 2, rare = 3, rareelite = 3 }

---@class ItemDefinition
---@field id string stable, stored in SavedVariables
---@field group string Items.GROUPS id
---@field kind "booster"|"trap" Items.EFFECTS key
---@field price integer copper
---@field icon string texture path
---@field name string display text
---@field effect string display text of what it does ({seconds} is the duration)
---@field duration? integer booster: seconds the boost lasts
---@field boost? "catch" booster: what it boosts ("catch": every catch roll succeeds)
---@field tier? "normal"|"elite"|"rare" trap: the highest classification it catches

---@type ItemDefinition[]
Items.CATALOG = {
    { id = "meat", group = "catch", kind = "booster", boost = "catch", duration = 20, price = 50 * 10000,
      icon = "Interface\\Icons\\INV_Misc_Food_14", name = Text["Delicious Meat"],
      effect = Text["Every catch roll succeeds for {seconds} seconds."] },
    { id = "trap", group = "catch", kind = "trap", tier = "normal", price = 500 * 10000,
      icon = "Interface\\Icons\\Ability_Ensnare", name = Text["Magic Trap"],
      effect = Text["Catches a normal enemy at once, without a fight."] },
    { id = "trapElite", group = "catch", kind = "trap", tier = "elite", price = 1000 * 10000,
      icon = "Interface\\Icons\\Spell_Frost_ChainsOfIce", name = Text["Elite Magic Trap"],
      effect = Text["Catches a normal or elite enemy at once, without a fight."] },
    { id = "trapRare", group = "catch", kind = "trap", tier = "rare", price = 1500 * 10000,
      icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate", name = Text["Rare Magic Trap"],
      effect = Text["Catches a normal, elite or rare enemy at once, without a fight. Never a world boss."] },
}

-- ids of removed items: never used again
Items.RETIRED = {}

local byID = {}
for _, item in ipairs(Items.CATALOG) do byID[item.id] = item end

---@param id any
---@return ItemDefinition|nil
function Items.Get(id) return byID[id] end

-- The item's effect line with its numbers filled in.
---@param item ItemDefinition
---@return string
function Items.EffectText(item)
    return addon.Locale.Format(item.effect, { seconds = item.duration or 0 })
end

------------------------------------------------------------------ inventory

---@return table<string, integer>
function Items.Inventory()
    local caught = addon.AzeCaught.State()
    if type(caught.items) ~= "table" then caught.items = {} end
    return caught.items
end

---@param id string
---@return integer
function Items.Count(id)
    local count = Items.Inventory()[id]
    return type(count) == "number" and count or 0
end

-- Owned items of a group, catalog order: { item, count }.
---@param group string|nil nil: every group
---@return { item: ItemDefinition, count: integer }[]
function Items.Owned(group)
    local owned = {}
    for _, item in ipairs(Items.CATALOG) do
        local count = Items.Count(item.id)
        if count > 0 and (group == nil or item.group == group) then owned[#owned + 1] = { item = item, count = count } end
    end
    return owned
end

-- Why `id` cannot be bought now, or nil: "unknown", "readonly", "stack", "funds".
---@param id string
---@param myName string|nil
---@return string|nil
function Items.BuyRefusal(id, myName)
    local item = byID[id]
    if not item then return "unknown" end
    if addon.Store.db.readonly then return "readonly" end
    if Items.Count(id) >= Items.MAXIMUM_STACK then return "stack" end
    if item.price > addon.Wallet.Balance(myName) then return "funds" end
    return nil
end

-- Buys one `id`: the price is spent from the wallet (ledger kind "shop"), the count goes up. Returns the new count, or
-- nil and the refusal (Items.BuyRefusal).
---@param id string
---@param myName string|nil
---@param now integer server time
---@return integer|nil count
---@return string|nil reason
function Items.Buy(id, myName, now)
    local refusal = Items.BuyRefusal(id, myName)
    if refusal then
        addon.AzeCaught.Journal("DEBUG", "item.buy", "a purchase was refused", { item = tostring(id), reason = refusal })
        return nil, refusal
    end
    local item = byID[id]
    local balance, problem = addon.Wallet.Spend(myName, item.price, "shop", now, id)
    if not balance then return nil, problem end
    local inventory = Items.Inventory()
    inventory[id] = Items.Count(id) + 1
    addon.AzeCaught.Journal("INFORMATION", "item.buy", "an item was bought", { item = id, count = inventory[id], price = item.price })
    return inventory[id]
end

------------------------------------------------------------------ boosts

---@return table<string, integer>
function Items.Boosts()
    local caught = addon.AzeCaught.State()
    if type(caught.boosts) ~= "table" then caught.boosts = {} end
    return caught.boosts
end

-- Seconds left of the boost of `id` (0: not running). Never more than its duration, also when the clock went back.
---@param id string
---@param now integer server time
---@return integer
function Items.BoostLeft(id, now)
    local item, ends = byID[id], Items.Boosts()[id]
    if not item or not item.duration or type(ends) ~= "number" then return 0 end
    return math.max(0, math.min(item.duration, ends - (tonumber(now) or 0)))
end

-- The running boost of a kind ("catch"), the one with the most time left: item, seconds left. Nil when none runs.
---@param boost string
---@param now integer
---@return ItemDefinition|nil
---@return integer
function Items.ActiveBoost(boost, now)
    local best, bestLeft = nil, 0
    for _, item in ipairs(Items.CATALOG) do
        if item.boost == boost then
            local left = Items.BoostLeft(item.id, now)
            if left > bestLeft then best, bestLeft = item, left end
        end
    end
    return best, bestLeft
end

-- True while a catch boost runs: every catch roll succeeds.
---@param now integer
---@return boolean
function Items.CatchBoosted(now) return Items.ActiveBoost("catch", now) ~= nil end

------------------------------------------------------------------ use

-- Whether trap `item` can catch an NPC of `classification`.
---@param item ItemDefinition
---@param classification string|nil
---@return boolean
function Items.TrapAllows(item, classification)
    local rank = Items.CLASS_RANK[addon.AzeCaught.Classification(classification)]
    return item.kind == "trap" and rank ~= nil and rank <= (Items.TIER_RANK[item.tier] or 0)
end

---@class ItemUseContext
---@field myName string|nil
---@field now integer server time
---@field clock? number GetTime() (traps)
---@field target? ThrowTarget the unit a trap is used on

-- The effect of each kind: returns true (and a result), or nil and why. The item is only removed on success.
---@type table<string, fun(item: ItemDefinition, context: ItemUseContext): any, any>
Items.EFFECTS = {
    booster = function(item, context)
        Items.Boosts()[item.id] = context.now + item.duration
        return true, { left = item.duration }
    end,
    trap = function(item, context)
        if not context.target then return nil, "notarget" end
        local result, reason = addon.AzeCaught.TrapCatch(context.target, item, context.myName, context.clock or 0, context.now)
        if not result then return nil, reason end
        return true, result
    end,
}

-- Uses one `id`. Returns true and the effect's result, or nil and why: "unknown", "readonly", "none" (not owned), or
-- the effect's refusal (the item is kept).
---@param id string
---@param context ItemUseContext
---@return boolean|nil
---@return any result or reason
function Items.Use(id, context)
    local item = byID[id]
    local function refuse(reason)
        addon.AzeCaught.Journal("DEBUG", "item.use", "an item use was refused", { item = tostring(id), reason = reason })
        return nil, reason
    end
    if not item then return refuse("unknown") end
    if addon.Store.db.readonly then return refuse("readonly") end
    if Items.Count(id) < 1 then return refuse("none") end
    local ok, result = Items.EFFECTS[item.kind](item, context)
    if not ok then return refuse(result) end
    local inventory = Items.Inventory()
    inventory[id] = Items.Count(id) - 1
    if inventory[id] <= 0 then inventory[id] = nil end
    addon.AzeCaught.Journal("INFORMATION", "item.use", "an item was used", { item = id, left = Items.Count(id) })
    return true, result
end

------------------------------------------------------------------ saved data

-- Re-validates db.caught.items and db.caught.boosts (SavedVariables are untrusted on load): unknown ids and bad counts
-- are dropped, counts kept within 1..MAXIMUM_STACK. Returns true when something had to be repaired.
---@param caught table db.caught
---@return boolean repaired
function Items.SanitizePersisted(caught)
    local repaired = false
    local SafeInteger = addon.Utility.SafeInteger
    if caught.items ~= nil then
        local clean = {}
        for id, count in pairs(type(caught.items) == "table" and caught.items or {}) do
            local whole = byID[id] and SafeInteger(count, 1, 1000000000)
            if whole then clean[id] = math.min(whole, Items.MAXIMUM_STACK) end
            if clean[id] ~= count then repaired = true end
        end
        if type(caught.items) ~= "table" then repaired = true end
        caught.items = clean
    end
    if caught.boosts ~= nil then
        local clean = {}
        for id, ends in pairs(type(caught.boosts) == "table" and caught.boosts or {}) do
            local item = byID[id]
            if item and item.duration and SafeInteger(ends, 0) then clean[id] = ends else repaired = true end
        end
        if type(caught.boosts) ~= "table" then repaired = true end
        caught.boosts = clean
    end
    return repaired
end
