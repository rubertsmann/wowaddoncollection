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
    { id = "charms", name = Text["Charms"] },
    { id = "care", name = Text["Care"] },
    { id = "arena", name = Text["Arena"] },
    { id = "games", name = Text["Games"] },
}

-- trap tiers: a trap catches NPCs whose classification rank is at most its tier's rank; world bosses have no rank
Items.TIER_RANK = { normal = 1, elite = 2, rare = 3 }
Items.CLASS_RANK = { normal = 1, elite = 2, rare = 3, rareelite = 3 }

---@class ItemDefinition
---@field id string stable, stored in SavedVariables
---@field group string Items.GROUPS id
---@field kind "booster"|"trap"|"charm"|"care"|"arenaBuff"|"runner"|"survivor" Items.EFFECTS key
---@field price integer copper
---@field icon string texture path
---@field name string display text
---@field effect string display text of what it does ({seconds} is the duration)
---@field duration? integer booster: seconds the boost lasts
---@field boost? "catch"|"care" booster: what it boosts ("catch": every catch roll succeeds; "care": the needs don't drop)
---@field tier? "normal"|"elite"|"rare" trap: the highest classification it catches
---@field stack? integer most a player can own (default MAXIMUM_STACK)
---@field charm? "reward"|"best"|"second"|"lure" charm: what the equipped charm changes
---@field value? number charm: its strength (reward/lure factor, best-moment health, extra throws)
---@field fills? string[] care: the needs it fills to full
---@field stat? "atk"|"def"|"spd"|"vit" arenaBuff: the fighter stat it raises
---@field factor? number arenaBuff: the stat multiplier
---@field fights? integer arenaBuff: fights it lasts
---@field run? "shield"|"start" runner: what it does to the next run

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
    { id = "charmLuck", group = "charms", kind = "charm", charm = "reward", value = 1.10, stack = 1, price = 300 * 10000,
      icon = "Interface\\Icons\\INV_Misc_Rune_07", name = Text["Lucky Charm"],
      effect = Text["Equipped: catch rewards +10%."] },
    { id = "charmSteady", group = "charms", kind = "charm", charm = "best", value = 0.13, stack = 1, price = 300 * 10000,
      icon = "Interface\\Icons\\INV_Misc_Rune_01", name = Text["Steady Hand"],
      effect = Text["Equipped: the best moment starts at 13% health instead of 10%."] },
    { id = "charmSecond", group = "charms", kind = "charm", charm = "second", value = 1, stack = 1, price = 300 * 10000,
      icon = "Interface\\Icons\\INV_Misc_Rune_05", name = Text["Second Chance"],
      effect = Text["Equipped: when the rope slips off (the enemy died too late), you can throw once more at it."] },
    { id = "charmLure", group = "charms", kind = "charm", charm = "lure", value = 1.25, stack = 1, price = 300 * 10000,
      icon = "Interface\\Icons\\INV_Misc_Rune_09", name = Text["Rare Lure"],
      effect = Text["Equipped: elite and rare catches pay +25%."] },
    { id = "feast", group = "care", kind = "care", fills = { "hunger", "thirst" }, price = 1 * 10000,
      icon = "Interface\\Icons\\INV_Misc_Food_63", name = Text["Feast"],
      effect = Text["Fills the hunger and thirst of your companion."] },
    { id = "toy", group = "care", kind = "care", fills = { "affection" }, price = 50 * 100,
      icon = "Interface\\Icons\\INV_Misc_Toy_01", name = Text["Squeaky Toy"],
      effect = Text["Fills the affection of your companion."] },
    { id = "elixir", group = "care", kind = "booster", boost = "care", duration = 4 * 3600, price = 5 * 10000,
      icon = "Interface\\Icons\\INV_Potion_27", name = Text["Care Elixir"],
      effect = Text["Hunger, thirst and affection don't drop for 4 hours."] },
    { id = "warPaint", group = "arena", kind = "arenaBuff", stat = "atk", factor = 1.10, fights = 3, price = 250 * 10000,
      icon = "Interface\\Icons\\Ability_Warrior_BattleShout", name = Text["War Paint"],
      effect = Text["Attack +10% for your next 3 arena fights."] },
    { id = "barkSkin", group = "arena", kind = "arenaBuff", stat = "vit", factor = 1.10, fights = 3, price = 250 * 10000,
      icon = "Interface\\Icons\\Spell_Nature_StoneClawTotem", name = Text["Bark Skin"],
      effect = Text["Health +10% for your next 3 arena fights."] },
    { id = "swiftTonic", group = "arena", kind = "arenaBuff", stat = "spd", factor = 1.25, fights = 1, price = 100 * 10000,
      icon = "Interface\\Icons\\INV_Potion_95", name = Text["Swift Tonic"],
      effect = Text["Speed +25% for your next arena fight: it nearly always acts first."] },
    { id = "dashShield", group = "games", kind = "runner", run = "shield", price = 10 * 10000,
      icon = "Interface\\Icons\\INV_Shield_06", name = Text["Dash Shield"],
      effect = Text["Your next Companion Dash run survives one hit."] },
    { id = "headStart", group = "games", kind = "runner", run = "start", price = 5 * 10000,
      icon = "Interface\\Icons\\Ability_Rogue_Sprint", name = Text["Head Start"],
      effect = Text["Your next Companion Dash run starts at 200 m (no gold for those 200 m)."] },
    { id = "bomb", group = "games", kind = "survivor", price = 100 * 10000,
      icon = "Interface\\Icons\\INV_Misc_Bomb_05", name = Text["Survivor Bomb"],
      effect = Text["Once per Survivor run with a stake of at most 250g: clears every monster on the screen."] },
}

-- the highest stake a Survivor Bomb works in: its gain grows with the stake, its price does not
Items.BOMB_MAXIMUM_STAKE = 250 * 10000

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
    if Items.Count(id) >= (item.stack or Items.MAXIMUM_STACK) then return "stack" end
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

------------------------------------------------------------------ the charm slot

-- The equipped charm (one slot), or nil. A charm that is no longer owned or known is not equipped.
---@return ItemDefinition|nil
function Items.Equipped()
    local item = byID[addon.AzeCaught.State().equipped]
    if item and item.kind == "charm" and Items.Count(item.id) > 0 then return item end
    return nil
end

-- Equips charm `id` (nil: empties the slot). Returns true when the slot changed.
---@param id string|nil
---@return boolean
function Items.Equip(id)
    local item = id and byID[id]
    if id ~= nil and not (item and item.kind == "charm" and Items.Count(id) > 0) then return false end
    local caught = addon.AzeCaught.State()
    if caught.equipped == id then return false end
    caught.equipped = id
    addon.AzeCaught.Journal("INFORMATION", "item.equip", id and "a charm was equipped" or "the charm was taken off", { item = id })
    return true
end

-- The strength of the equipped charm when it changes `charm` ("reward", "best", "second", "lure"), else nil.
---@param charm string
---@return number|nil
function Items.CharmValue(charm)
    local item = Items.Equipped()
    return item and item.charm == charm and item.value or nil
end

------------------------------------------------------------------ arena buffs

-- Fights left per running arena buff (db.caught.arenaBuffs: id -> fights).
---@return table<string, integer>
function Items.ArenaBuffs()
    local caught = addon.AzeCaught.State()
    if type(caught.arenaBuffs) ~= "table" then caught.arenaBuffs = {} end
    return caught.arenaBuffs
end

-- The running arena buffs, catalog order.
---@return ItemDefinition[]
function Items.RunningArenaBuffs()
    local running, buffs = {}, Items.ArenaBuffs()
    for _, item in ipairs(Items.CATALOG) do
        if item.kind == "arenaBuff" and (buffs[item.id] or 0) > 0 then running[#running + 1] = item end
    end
    return running
end

-- A fighter snapshot with the buffs `ids` was published: each of them loses one fight.
---@param ids string[]|nil
function Items.SpendArenaBuffs(ids)
    local buffs = Items.ArenaBuffs()
    for _, id in ipairs(ids or {}) do
        if buffs[id] then
            buffs[id] = buffs[id] - 1
            if buffs[id] <= 0 then buffs[id] = nil end
        end
    end
end

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
---@field runStart? boolean a Companion Dash run starts (runner items)
---@field survivorRun? SurvivorRun the running Survivor run (the bomb)

-- The effect of each kind: returns true (and a result), or nil and why. The item is only removed on success.
---@type table<string, fun(item: ItemDefinition, context: ItemUseContext): any, any>
Items.EFFECTS = {
    booster = function(item, context)
        Items.Boosts()[item.id] = context.now + item.duration
        return true, { left = item.duration }
    end,
    charm = function(item)
        Items.Equip(Items.Equipped() ~= item and item.id or nil)
        return true, { equipped = Items.Equipped() == item }, true
    end,
    care = function(item, context)
        local result, reason = addon.AzeCaught.CareItem(item.fills, context.now)
        if not result then return nil, reason end
        return true, result
    end,
    arenaBuff = function(item)
        local buffs = Items.ArenaBuffs()
        if (buffs[item.id] or 0) > 0 then return nil, "running" end
        buffs[item.id] = item.fights
        return true, { fights = item.fights }
    end,
    runner = function(item, context)
        if not context.runStart then return nil, "norun" end
        return true, { run = item.run }
    end,
    survivor = function(item, context)
        local run = context.survivorRun
        if not run or run.finished then return nil, "norun" end
        if run.stake > Items.BOMB_MAXIMUM_STAKE then return nil, "stake" end
        if run.bombed then return nil, "used" end
        return true, addon.Survivor.Bomb(run)
    end,
    trap = function(item, context)
        if not context.target then return nil, "notarget" end
        local result, reason = addon.AzeCaught.TrapCatch(context.target, item, context.myName, context.clock or 0, context.now)
        if not result then return nil, reason end
        return true, result
    end,
}

-- Uses one `id`. Returns true and the effect's result, or nil and why: "unknown", "readonly", "none" (not owned), or
-- the effect's refusal (the item is kept). A charm is not used up: using it equips or unequips it.
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
    local ok, result, keep = Items.EFFECTS[item.kind](item, context)
    if not ok then return refuse(result) end
    if keep then return true, result end
    local inventory = Items.Inventory()
    inventory[id] = Items.Count(id) - 1
    if inventory[id] <= 0 then inventory[id] = nil end
    addon.AzeCaught.Journal("INFORMATION", "item.use", "an item was used", { item = id, left = Items.Count(id) })
    return true, result
end

------------------------------------------------------------------ saved data

-- Re-validates db.caught.items, boosts, equipped and arenaBuffs (SavedVariables are untrusted on load): unknown ids and bad counts
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
    if caught.equipped ~= nil then
        local item = byID[caught.equipped]
        if not (item and item.kind == "charm" and type(caught.items) == "table" and caught.items[caught.equipped]) then
            caught.equipped, repaired = nil, true
        end
    end
    if caught.arenaBuffs ~= nil then
        local clean = {}
        for id, fights in pairs(type(caught.arenaBuffs) == "table" and caught.arenaBuffs or {}) do
            local item = byID[id]
            local whole = item and item.kind == "arenaBuff" and SafeInteger(fights, 1, item.fights)
            if whole then clean[id] = whole else repaired = true end
        end
        if type(caught.arenaBuffs) ~= "table" then repaired = true end
        caught.arenaBuffs = clean
    end
    return repaired
end
