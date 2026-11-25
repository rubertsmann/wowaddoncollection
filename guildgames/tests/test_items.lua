-- AZEcaught items: catalog guard, buying, the catch boost, traps, saved data.
local NOW = 1794873600
local GUID = "Creature-0-1-2-3-4711-0000ABCDEF"
local ME = "Me-R"

local function fresh(harness, gold)
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = ME
    addon.AzeCaught.throws, addon.AzeCaught.rolled, addon.AzeCaught.thrown, addon.AzeCaught.lastThrowAt = {}, {}, {}, nil
    addon.AzeCaught.forceNextCatch = false
    addon.AzeCaught.State().firstCatchDone = true
    if gold then addon.Wallet.Earn(ME, gold * 10000, "dev", NOW) end
    return addon
end

local function constant(value) return function() return value end end

local function target(options)
    options = options or {}
    return { guid = options.guid or GUID, health = options.health == nil and 1 or options.health, name = "Wolf", level = 10,
        classification = options.cls or "normal", tapDenied = options.tapDenied, inRange = options.inRange }
end

local function slurp(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text
end

return {
    -- every catalog entry is complete: the guard a new item has to pass
    ["items: the catalog guard (unique ids, known group and kind, kind fields, price, icon, texts translated)"] = function(harness)
        local addon = fresh(harness)
        local Items = addon.Items
        local german = addon.Locale.strings.deDE
        local groups, seen, retired = {}, {}, {}
        for _, group in ipairs(Items.GROUPS) do groups[group.id] = true end
        for _, id in ipairs(Items.RETIRED) do retired[id] = true end
        local source = slurp("Core/Minigames/Items.lua")
        harness.truthy(#Items.CATALOG > 0, "empty catalog")
        for _, item in ipairs(Items.CATALOG) do
            local label = tostring(item.id)
            harness.truthy(type(item.id) == "string" and item.id:match("^[%a][%w]*$") and #item.id <= Items.MAXIMUM_ID_BYTES, label .. ": id")
            harness.truthy(not seen[item.id], label .. ": duplicate id"); seen[item.id] = true
            harness.truthy(not retired[item.id], label .. ": a retired id is reused")
            harness.truthy(groups[item.group], label .. ": unknown group " .. tostring(item.group))
            harness.truthy(Items.EFFECTS[item.kind], label .. ": no effect handler for kind " .. tostring(item.kind))
            harness.truthy(addon.Utility.SafeInteger(item.price, 1, addon.Wallet.MAXIMUM_AMOUNT), label .. ": price")
            harness.truthy(type(item.icon) == "string" and item.icon:find("^Interface\\"), label .. ": icon")
            if item.kind == "booster" then
                harness.truthy(addon.Utility.SafeInteger(item.duration, 1, 86400), label .. ": booster duration")
                harness.truthy(item.boost == "catch", label .. ": unknown boost " .. tostring(item.boost))
            elseif item.kind == "trap" then
                harness.truthy(Items.TIER_RANK[item.tier], label .. ": trap tier")
            end
            harness.truthy(type(item.name) == "string" and item.name ~= "", label .. ": name")
            harness.truthy(type(item.effect) == "string" and item.effect ~= "", label .. ": effect")
        end
        -- the texts are written as Text["..."] in the catalog and translated
        for key in source:gmatch('Text%["(.-)"%]') do harness.truthy(german[key], "untranslated: " .. key) end
    end,

    ["items: buying spends the price, counts up, and refuses funds, a full stack, unknown ids and read-only"] = function(harness)
        local addon = fresh(harness, 30)   -- 20g grant + 30g = 50g
        local Items, Wallet = addon.Items, addon.Wallet
        harness.equal(Items.Buy("meat", ME, NOW), 1)
        harness.equal(Wallet.Balance(ME), 0, "the exact balance buys")
        harness.equal(select(2, Items.Buy("meat", ME, NOW)), "funds", "one copper short")
        harness.equal(Items.Count("meat"), 1)
        local entries = Wallet.Ledger().entries
        harness.equal(entries[#entries].k, "shop"); harness.equal(entries[#entries].a, -50 * 10000)
        harness.equal(select(2, Items.Buy("nope", ME, NOW)), "unknown")
        Wallet.Earn(ME, 100000 * 10000, "dev", NOW)
        Items.Inventory().meat = Items.MAXIMUM_STACK
        harness.equal(select(2, Items.Buy("meat", ME, NOW)), "stack")
        addon.Store.db.readonly = true
        harness.equal(select(2, Items.Buy("trap", ME, NOW)), "readonly")
    end,

    ["items: Delicious Meat makes every catch roll succeed for 20 s, survives a reload, restarts instead of stacking"] = function(harness)
        local addon = fresh(harness, 100)
        local Items, AzeCaught = addon.Items, addon.AzeCaught
        Items.Buy("meat", ME, NOW)
        harness.truthy(Items.Use("meat", { myName = ME, now = NOW }))
        harness.equal(Items.Count("meat"), 0); harness.equal(Items.Inventory().meat, nil, "an empty stack is removed")
        harness.equal(Items.BoostLeft("meat", NOW + 5), 15)
        assert(AzeCaught.Throw(target({ health = 0.3 }), 10, 100, NOW + 5))
        local result = AzeCaught.OnDeath(GUID, ME, 101, NOW + 6, constant(0.99))
        harness.truthy(result.caught and result.boosted, "a 0.99 roll is caught while boosted")
        harness.truthy(result.reward > 0, "the normal reward is paid")
        -- after a reload the stored end still counts; a clock that went back never gives more than 20 s
        local saved = addon.Store.db
        harness.equal(addon.AzeCaught.SanitizePersisted(saved), 0)
        harness.equal(Items.BoostLeft("meat", NOW + 19), 1)
        harness.equal(Items.BoostLeft("meat", NOW - 1000), 20)
        harness.equal(Items.BoostLeft("meat", NOW + 20), 0)
        -- after the boost a 0.99 roll fails again
        local other = "Creature-0-1-2-3-4712-0000ABCDEF"
        assert(AzeCaught.Throw(target({ guid = other, health = 0.3 }), 10, 200, NOW + 30))
        harness.equal(AzeCaught.OnDeath(other, ME, 201, NOW + 31, constant(0.99)).caught, false)
        -- using it again restarts at 20 s
        Items.Inventory().meat = 2
        Items.Use("meat", { myName = ME, now = NOW + 40 })
        Items.Use("meat", { myName = ME, now = NOW + 50 })
        harness.equal(Items.BoostLeft("meat", NOW + 50), 20)
        harness.equal(Items.Count("meat"), 0)
    end,

    ["items: a throw armed during the boost still succeeds when the NPC dies just after it ended"] = function(harness)
        local addon = fresh(harness)
        local Items, AzeCaught = addon.Items, addon.AzeCaught
        Items.Inventory().meat = 1
        Items.Use("meat", { myName = ME, now = NOW })
        assert(AzeCaught.Throw(target({ health = 0.3 }), 10, 100, NOW + 19))
        harness.truthy(AzeCaught.OnDeath(GUID, ME, 102, NOW + 21, constant(0.99)).caught)
    end,

    ["items: traps catch at any health by tier, never world bosses; a refusal keeps the trap"] = function(harness)
        local addon = fresh(harness)
        local Items, AzeCaught = addon.Items, addon.AzeCaught
        local inventory = Items.Inventory()
        inventory.trap, inventory.trapElite, inventory.trapRare = 2, 1, 1
        local function use(id, options)
            return Items.Use(id, { myName = ME, now = NOW, clock = 100, target = target(options) })
        end
        harness.equal(select(2, use("trap", { cls = "elite" })), "tier"); harness.equal(Items.Count("trap"), 2)
        harness.equal(select(2, use("trapRare", { cls = "worldboss" })), "tier")
        harness.equal(select(2, use("trap", { tapDenied = true })), "tapped")
        harness.equal(select(2, use("trap", { inRange = false })), "range")
        harness.equal(select(2, use("trap", { health = 0 })), "dead")
        harness.equal(select(2, use("trap", { guid = "Player-1-0001" })), "unknown")
        harness.equal(select(2, Items.Use("trap", { myName = ME, now = NOW })), "notarget")
        harness.equal(Items.Count("trap"), 2, "every refusal kept the trap")
        local before = addon.Wallet.Balance(ME)
        local ok, result = use("trap", { health = 1 })
        harness.truthy(ok and result.caught and result.trap == "trap", "full health, no fight")
        harness.equal(Items.Count("trap"), 1)
        harness.equal(AzeCaught.State().collection[4711].caught, 1)
        harness.equal(addon.Wallet.Balance(ME) - before, AzeCaught.Reward(AzeCaught.Chance(AzeCaught.BEST_HEALTH, "normal").chance))
        harness.truthy(result.companion, "the first catch became the companion")
        harness.equal(select(2, use("trap")), "rolled", "a trapped NPC cannot be trapped again")
        harness.equal(select(2, AzeCaught.Throw(target({ health = 0.2 }), 10, 105, NOW)), "rolled", "nor roped")
        harness.truthy(Items.TrapAllows(Items.Get("trapElite"), "elite")); harness.truthy(not Items.TrapAllows(Items.Get("trapElite"), "rare"))
        harness.truthy(Items.TrapAllows(Items.Get("trapRare"), "rareelite"))
        harness.truthy(Items.TrapAllows(Items.Get("trapRare"), "normal"))
        harness.truthy(not Items.TrapAllows(Items.Get("meat"), "normal"), "only traps trap")
    end,

    ["items: saved items and boosts are sanitized (unknown ids, bad counts, capped stacks)"] = function(harness)
        local addon = fresh(harness)
        local caught = addon.AzeCaught.State()
        caught.items = { meat = 5, trap = -1, trapRare = "3", gone = 4, trapElite = 1e9, [7] = 1 }
        caught.boosts = { meat = NOW + 10, trap = NOW + 10, nope = 1, [3] = 4 }
        harness.truthy(addon.AzeCaught.SanitizePersisted(addon.Store.db) > 0)
        harness.equal(caught.items.meat, 5); harness.equal(caught.items.trap, nil); harness.equal(caught.items.trapRare, nil)
        harness.equal(caught.items.gone, nil); harness.equal(caught.items.trapElite, addon.Items.MAXIMUM_STACK)
        harness.equal(caught.boosts.meat, NOW + 10); harness.equal(caught.boosts.trap, nil, "traps have no boost")
        caught.items, caught.boosts = "x", 5
        addon.AzeCaught.SanitizePersisted(addon.Store.db)
        harness.equal(type(caught.items), "table"); harness.equal(type(caught.boosts), "table")
        harness.equal(addon.AzeCaught.SanitizePersisted(addon.Store.db), 0, "clean data needs no repair")
    end,

    ["items: Owned lists by group in catalog order; using what is not owned is refused"] = function(harness)
        local addon = fresh(harness)
        local Items = addon.Items
        Items.Inventory().trapRare, Items.Inventory().meat = 1, 3
        local owned = Items.Owned("catch")
        harness.equal(#owned, 2); harness.equal(owned[1].item.id, "meat"); harness.equal(owned[2].count, 1)
        harness.equal(select(2, Items.Use("trap", { myName = ME, now = NOW, target = target() })), "none")
        harness.equal(select(2, Items.Use("nope", { myName = ME, now = NOW })), "unknown")
        harness.equal(Items.EffectText(Items.Get("meat")), "Every catch roll succeeds for 20 seconds.")
    end,
}
