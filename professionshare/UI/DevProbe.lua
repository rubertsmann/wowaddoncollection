local addonName, addon = ...

-- DEV BUILD ONLY: records what this client can tell about the items our recipes make, so the
-- category filter and the effect-text search are built on facts instead of guesses. Debug tab menu "Dev tools" -> "Item probe (catalog)",
-- or /psd itemprobe [itemID ...]. Writes addon.db.devProbe (ProfessionShareDevDB); /reload flushes it to
-- WTF\Account\<ACCOUNT>\SavedVariables\ProfessionShare-Dev.lua. The live build never runs it (no button, no command).
-- Plain English strings on purpose: dev-only, not localized. The keys of the recorded tables are the file format the
-- item analysis reads; they stay as they are.
---@class DevProbeModule
local DevProbe = {}
addon.DevProbe = DevProbe

local MAXIMUM_SAMPLES = 150          -- detailed item records
local SAMPLES_PER_BUCKET = 3         -- detailed records per class/subclass/slot bucket
local WAIT_SECONDS = { 3, 8 }        -- seconds after the click: first collect, then a retry for items the server had not sent yet

-- the global function at a dotted path ("C_Item.GetItemInfo"), or nil
---@param path string
---@return function|nil
local function functionAtPath(path)
    local value = _G
    for pathPart in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[pathPart]
    end
    return type(value) == "function" and value or nil
end

---@type string[]
local PROBED_APIS = {
    -- item data
    "GetItemInfoInstant", "C_Item.GetItemInfoInstant", "GetItemInfo", "C_Item.GetItemInfo", "C_Item.RequestLoadItemDataByID",
    "C_Item.GetItemInventoryTypeByID", "C_Item.GetItemClassInfo", "GetItemClassInfo", "C_Item.GetItemSubClassInfo",
    "GetItemSubClassInfo", "GetItemStats", "C_Item.GetItemStats", "GetItemSpell", "C_Item.GetItemSpell",
    -- spell text
    "GetSpellInfo", "C_Spell.GetSpellInfo", "GetSpellDescription", "C_Spell.GetSpellDescription", "C_Spell.RequestLoadSpellData",
    -- tooltip reading
    "C_TooltipInfo.GetItemByID", "C_TooltipInfo.GetHyperlink", "C_TooltipInfo.GetSpellByID", "TooltipUtil.SurfaceArgs",
    -- profession categories / filters
    "GetTradeSkillSubClasses", "GetTradeSkillInvSlots", "SetTradeSkillSubClassFilter", "SetTradeSkillInvSlotFilter",
    "C_TradeSkillUI.GetCategories", "C_TradeSkillUI.GetCategoryInfo", "C_TradeSkillUI.GetRecipeInfo", "GetProfessions",
    -- UI building blocks for checkbox menus and dropdowns
    "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton", "ToggleDropDownMenu",
    "MenuUtil.CreateContextMenu", "MenuUtil.CreateCheckboxContextMenu", "MenuUtil.CreateRadioContextMenu",
    "SearchBoxTemplate_OnTextChanged",
}
---@type { [1]: string, [2]: string }[] frame type, template: does CreateFrame accept it?
local PROBED_TEMPLATES = {
    { "Frame", "UIDropDownMenuTemplate" }, { "DropdownButton", "WowStyle1DropdownTemplate" },
    { "DropdownButton", "WowStyle1FilterDropdownTemplate" }, { "EditBox", "SearchBoxTemplate" },
    { "EditBox", "InputBoxTemplate" }, { "CheckButton", "UICheckButtonTemplate" },
}

-- readable dump of any value (strings quoted so "" and nil differ)
---@param value any
---@param depth? integer
---@return string
local function describeValue(value, depth)
    depth = depth or 0
    local valueType = type(value)
    if valueType == "string" then return string.format("%q", value) end
    if valueType ~= "table" then return tostring(value) end
    if depth > 3 then return "{...}" end
    local parts = {}
    for _, key in ipairs(addon.Utility.SortedKeys(value)) do parts[#parts + 1] = tostring(key) .. "=" .. describeValue(value[key], depth + 1) end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- every return value of func(...), nils included: "1=..., 2=nil, ..." or "error ..." / "missing"
---@param func function|nil
---@return string
local function describeCall(func, ...)
    if not func then return "missing" end
    local results = { pcall(func, ...) }
    if not results[1] then return "error " .. tostring(results[2]) end
    local resultCount = table.maxn(results)
    if resultCount <= 1 then return "(no values)" end
    local parts = {}
    for resultIndex = 2, resultCount do parts[#parts + 1] = (resultIndex - 1) .. "=" .. describeValue(results[resultIndex]) end
    return table.concat(parts, ", ")
end

-- the return values of func(...), or nothing when it is missing or raises an error
---@param func function|nil
---@return any ...
local function callResults(func, ...)
    if not func then return nil end
    local results = { pcall(func, ...) }
    if results[1] then return select(2, unpack(results, 1, table.maxn(results))) end
    return nil
end

------------------------------------------------------------------ tooltip text

---@type table|nil
local probeTooltip
---@param setterName string tooltip method, e.g. "SetHyperlink"
---@param argument any
---@return string[]|string lines, or an error description
local function readHiddenTooltip(setterName, argument)
    if not probeTooltip then
        local ok, tooltipOrError = pcall(CreateFrame, "GameTooltip", addon.FRAME_PREFIX .. "ProbeTip", UIParent, "GameTooltipTemplate")
        if not ok then return "error " .. tostring(tooltipOrError) end
        probeTooltip = tooltipOrError
    end
    probeTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    probeTooltip:ClearLines()
    local ok, errorMessage = pcall(probeTooltip[setterName], probeTooltip, argument)
    if not ok then return "error " .. tostring(errorMessage) end
    local tooltipLines = {}
    for lineIndex = 1, probeTooltip:NumLines() or 0 do
        local leftFontString = _G[addon.FRAME_PREFIX .. "ProbeTipTextLeft" .. lineIndex]
        local rightFontString = _G[addon.FRAME_PREFIX .. "ProbeTipTextRight" .. lineIndex]
        local leftText = leftFontString and leftFontString:GetText()
        local rightText = rightFontString and rightFontString:IsShown() and rightFontString:GetText()
        tooltipLines[#tooltipLines + 1] = (leftText or "") .. ((rightText and rightText ~= "") and (" || " .. rightText) or "")
    end
    probeTooltip:Hide()
    return tooltipLines
end

---@param tooltipInfoFunction function|nil
---@param argument any
---@return table|string
local function tooltipInfoLines(tooltipInfoFunction, argument)
    if not tooltipInfoFunction then return "missing" end
    local ok, tooltipData = pcall(tooltipInfoFunction, argument)
    if not ok then return "error " .. tostring(tooltipData) end
    if type(tooltipData) ~= "table" then return "returned " .. describeValue(tooltipData) end
    local tooltipLines = {}
    for lineIndex, tooltipLine in ipairs(tooltipData.lines or {}) do
        if tooltipLine.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, tooltipLine) end
        tooltipLines[#tooltipLines + 1] = tostring(tooltipLine.leftText or "")
            .. ((tooltipLine.rightText and tooltipLine.rightText ~= "") and (" || " .. tooltipLine.rightText) or "")
        if lineIndex == 1 then tooltipLines.firstRaw = describeValue(tooltipLine) end
    end
    return tooltipLines
end

------------------------------------------------------------------ one item / one recipe without an item

local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local getSpellDescription = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
local getItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local getItemClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local getItemSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo

-- asks the server for item / spell data the client has not loaded yet
---@param itemID integer|nil
---@param spellID? integer
local function requestData(itemID, spellID)
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    if spellID and C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
end

---@param itemID integer
---@return table itemRecord
local function probeItem(itemID)
    local itemRecord = { itemID = itemID }
    itemRecord.instant = describeCall(getItemInfoInstant, itemID)
    itemRecord.info = describeCall(getItemInfo, itemID)
    itemRecord.cached = callResults(getItemInfo, itemID) ~= nil
    local _, _, _, equipLocation, _, classID, subclassID = callResults(getItemInfoInstant, itemID)
    itemRecord.equipLocText = equipLocation and equipLocation ~= "" and tostring(_G[equipLocation]) or nil
    if classID then
        itemRecord.className = describeCall(getItemClassInfo, classID)
        itemRecord.subClassName = describeCall(getItemSubClassInfo, classID, subclassID)
    end
    if C_Item and C_Item.GetItemInventoryTypeByID then itemRecord.invType = describeCall(C_Item.GetItemInventoryTypeByID, itemID) end
    local link = addon.Api.ItemLink(itemID) or ("item:" .. itemID)
    itemRecord.link = link
    itemRecord.statistics = describeCall(getItemStats, link)
    itemRecord.spell = describeCall(getItemSpell, itemID)
    local _, spellID = callResults(getItemSpell, itemID)
    if spellID then
        requestData(nil, spellID)
        itemRecord.spellDesc = describeCall(getSpellDescription, spellID)
    end
    itemRecord.tipInfo = C_TooltipInfo and tooltipInfoLines(C_TooltipInfo.GetItemByID, itemID) or "missing"
    itemRecord.tipScan = readHiddenTooltip("SetHyperlink", "item:" .. itemID)
    return itemRecord
end

---@param spellID integer
---@return table spellRecord
local function probeSpell(spellID)
    local spellRecord = { spellID = spellID }
    spellRecord.spellInfo = describeCall((C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo, spellID)
    spellRecord.spellDesc = describeCall(getSpellDescription, spellID)
    spellRecord.tipInfo = C_TooltipInfo and tooltipInfoLines(C_TooltipInfo.GetSpellByID, spellID) or "missing"
    spellRecord.tipScanSpell = readHiddenTooltip("SetHyperlink", "spell:" .. spellID)
    spellRecord.tipScanEnchant = readHiddenTooltip("SetHyperlink", "enchant:" .. spellID)
    return spellRecord
end

------------------------------------------------------------------ open profession window: its own categories/filters

---@return table tradeSkillRecord
local function probeTradeSkill()
    local tradeSkillRecord = {}
    tradeSkillRecord.openProfession = tostring(addon.Api.OpenProfessionName and addon.Api.OpenProfessionName())
    if GetTradeSkillSubClasses then tradeSkillRecord.subClasses = describeCall(GetTradeSkillSubClasses) end
    if GetTradeSkillInvSlots then tradeSkillRecord.invSlots = describeCall(GetTradeSkillInvSlots) end
    if GetNumTradeSkills then
        local headers = {}
        for skillIndex = 1, math.min(400, callResults(GetNumTradeSkills) or 0) do
            local skillName, skillType = callResults(GetTradeSkillInfo, skillIndex)
            if skillType == "header" or skillType == "subheader" then headers[#headers + 1] = tostring(skillName) .. " (" .. skillType .. ")" end
        end
        tradeSkillRecord.legacyHeaders = headers
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetCategories then
        local categoryDescriptions = {}
        local ok, categoryIDs = pcall(function() return { C_TradeSkillUI.GetCategories() } end)
        if ok then
            for _, categoryID in ipairs(categoryIDs) do
                categoryDescriptions[#categoryDescriptions + 1] = tostring(categoryID) .. ": " .. describeCall(C_TradeSkillUI.GetCategoryInfo, categoryID)
                if #categoryDescriptions >= 60 then break end
            end
        end
        tradeSkillRecord.categories = categoryDescriptions
    end
    return tradeSkillRecord
end

------------------------------------------------------------------ run

local probeRunning = false

---@param itemID integer|nil
---@return string bucket "class:subclass:slot" or a reason
local function bucketOf(itemID)
    if not itemID then return "no item (enchant or unknown)" end
    local _, _, _, equipLocation, _, classID, subclassID = callResults(getItemInfoInstant, itemID)
    if not classID then return "unknown to this client" end
    return tostring(classID) .. ":" .. tostring(subclassID) .. ":" .. tostring(equipLocation ~= "" and equipLocation or "-")
end

---@class ProbePlanEntry
---@field itemID integer|nil
---@field recipeID integer|nil
---@field recipe string|nil
---@field bucket string

-- probes every planned entry into `probeResult`; returns how many items were not cached yet
---@param probeResult table
---@param plan ProbePlanEntry[]
---@return integer notCachedCount
local function collectProbes(probeResult, plan)
    probeResult.items, probeResult.spells = {}, {}
    for _, planEntry in ipairs(plan) do
        if planEntry.itemID then
            local itemRecord = probeItem(planEntry.itemID)
            itemRecord.recipeID, itemRecord.recipe, itemRecord.bucket = planEntry.recipeID, planEntry.recipe, planEntry.bucket
            probeResult.items[#probeResult.items + 1] = itemRecord
        else
            local spellRecord = probeSpell(planEntry.recipeID)
            spellRecord.recipe, spellRecord.bucket = planEntry.recipe, planEntry.bucket
            probeResult.spells[#probeResult.spells + 1] = spellRecord
        end
    end
    local notCachedCount = 0
    for _, itemRecord in ipairs(probeResult.items) do if not itemRecord.cached then notCachedCount = notCachedCount + 1 end end
    probeResult.notCached = notCachedCount
    return notCachedCount
end

---@param extraItemIDs? integer[] item ids asked for on the command line
function DevProbe.Run(extraItemIDs)
    if not addon.IS_DEVELOPMENT_BUILD then return end
    if probeRunning then addon.Print("item probe already running"); return end
    probeRunning = true
    local probeResult = { at = date and date("%Y-%m-%d %H:%M:%S"), locale = GetLocale and GetLocale(), version = addon.VERSION,
        build = describeCall(GetBuildInfo), apis = {}, templates = {}, buckets = {} }
    for _, apiPath in ipairs(PROBED_APIS) do probeResult.apis[apiPath] = functionAtPath(apiPath) ~= nil end
    for _, template in ipairs(PROBED_TEMPLATES) do
        local ok, errorMessage = pcall(CreateFrame, template[1], nil, nil, template[2])
        probeResult.templates[template[1] .. "/" .. template[2]] = ok and true or tostring(errorMessage)
    end
    -- profession-window data is kept per profession across runs: click once with each profession window open
    local previousProbe = addon.db.devProbe
    local tradeSkillByProfession = type(previousProbe) == "table" and type(previousProbe.tradeskill) == "table" and previousProbe.tradeskill or {}
    local tradeSkillRecord = probeTradeSkill()
    if tradeSkillRecord.openProfession ~= "nil" then tradeSkillByProfession[tradeSkillRecord.openProfession] = tradeSkillRecord end
    probeResult.tradeskill = tradeSkillByProfession

    -- every catalog recipe into a bucket; a few per bucket get a detailed record
    local recipeIDs = addon.Utility.SortedKeys(addon.db.catalog)
    local plan, samplesByBucket = {}, {}
    for _, recipeID in ipairs(recipeIDs) do
        local catalogEntry = addon.db.catalog[recipeID]
        local bucket = bucketOf(catalogEntry.produces)
        local bucketSummary = probeResult.buckets[bucket]
        if not bucketSummary then bucketSummary = { n = 0, examples = {} }; probeResult.buckets[bucket] = bucketSummary end
        bucketSummary.n = bucketSummary.n + 1
        if #bucketSummary.examples < 5 then bucketSummary.examples[#bucketSummary.examples + 1] = tostring(catalogEntry.name) end
        samplesByBucket[bucket] = (samplesByBucket[bucket] or 0) + 1
        if samplesByBucket[bucket] <= SAMPLES_PER_BUCKET and #plan < MAXIMUM_SAMPLES then
            plan[#plan + 1] = { itemID = catalogEntry.produces, recipeID = recipeID, recipe = catalogEntry.name, bucket = bucket }
            requestData(catalogEntry.produces, catalogEntry.produces and nil or recipeID)
        end
    end
    for _, itemID in ipairs(extraItemIDs or {}) do
        plan[#plan + 1] = { itemID = itemID, recipe = "(asked for)", bucket = bucketOf(itemID) }
        requestData(itemID)
    end
    probeResult.catalogSize, probeResult.sampled = #recipeIDs, #plan
    addon.db.devProbe = probeResult
    addon.Log.Information("devProbe.run", "item probe started", { recipes = #recipeIDs, sampled = #plan })
    addon.Print(("item probe: %d recipes in %d buckets, %d sampled; collecting in %ds..."):format(#recipeIDs,
        addon.Utility.Count(probeResult.buckets), #plan, WAIT_SECONDS[1]))

    local function runPass(passNumber)
        local notCachedCount = collectProbes(probeResult, plan)
        probeResult.pass = passNumber
        if passNumber < #WAIT_SECONDS and notCachedCount > 0 then
            local retrySeconds = WAIT_SECONDS[passNumber + 1] - WAIT_SECONDS[passNumber]
            addon.Print(("item probe: %d items not cached yet, retrying in %ds"):format(notCachedCount, retrySeconds))
            C_Timer.After(retrySeconds, function() runPass(passNumber + 1) end)
            return
        end
        probeRunning = false
        addon.Print(("item probe done: %d items, %d without item, %d not cached. /reload to write the file."):format(
            #probeResult.items, #probeResult.spells, notCachedCount))
    end
    C_Timer.After(WAIT_SECONDS[1], function()
        local ok = addon.Log.Protected("devProbe.run", "the item probe failed", runPass, 1)
        if not ok then probeRunning = false end
    end)
end

------------------------------------------------------------------ fake members and check results (dev build only)

-- Every fake member is made by fakeMember: "Fake <Role>" in the same name form as everyone else's (realm-free on
-- Forever), remembered in ProfessionShareDevDB.devFake so it survives /reload, and kept from the roster prune. Every fake
-- action, trigger and probe writes a result to ProfessionShareDevDB.devChecks[key], readable from the WTF file after
-- /reload. All of it lives only in this client: a fake member is never announced and never sent.

-- names of fake members made before they were remembered in devFake
local LEGACY_FAKE_ROLES = { "Enchanter", "Keyholder", "Tester", "Requester" }
-- the tables that hold one record per member
local MEMBER_TABLES = { "chars", "offers", "access", "rep", "cds", "feedback" }
local MAXIMUM_LOOT_LINES = 20
local LOOT_RECHECK_SECONDS = { 2, 10 }

-- a dev table in the saved variables (created on first use; a throwaway table before the data is loaded)
---@param key string
---@return table
local function devTable(key)
    local database = addon.db
    if type(database) ~= "table" then return {} end
    if type(database[key]) ~= "table" then database[key] = {} end
    return database[key]
end

---@return string|nil
local function timestamp() return date and date("%Y-%m-%d %H:%M:%S") or nil end

-- The name of the fake member with this role; remembered and kept from the prune.
---@param role string
---@return string
local function fakeMember(role)
    local fakeName = addon.Utility.CanonicalName("Fake " .. role) or ("Fake " .. role)
    devTable("devFake")[fakeName] = role
    addon.Store.keptNames[fakeName] = true
    return fakeName
end

-- Stores a check result under `key` (with time and version) and returns it.
---@param key string
---@param result table
---@return table
local function recordCheck(key, result)
    result.at, result.version = timestamp(), addon.VERSION
    devTable("devChecks")[key] = result
    addon.Log.Information("devProbe.check", "a dev check ran", { key = key, ok = result.ok })
    return result
end

-- The fake members remembered from earlier sessions are kept from the prune again (called once the data is loaded).
function DevProbe.RestoreFakeMembers()
    for fakeName in pairs(devTable("devFake")) do addon.Store.keptNames[fakeName] = true end
end

-- Removes every fake member (remembered ones and the legacy names) from every member table, and nothing else.
---@return table result
function DevProbe.RemoveFakeData()
    local fakeNames, myName = {}, addon.Store.db and addon.Store.db.me
    for fakeName in pairs(devTable("devFake")) do fakeNames[fakeName] = true end
    for _, role in ipairs(LEGACY_FAKE_ROLES) do
        fakeNames["Fake " .. role] = true
        local canonicalName = addon.Utility.CanonicalName("Fake " .. role)
        if canonicalName then fakeNames[canonicalName] = true end
    end
    if myName then fakeNames[myName] = nil end
    local removed = {}
    for _, tableKey in ipairs(MEMBER_TABLES) do
        local recordsByName = addon.Store.db and addon.Store.db[tableKey]
        if type(recordsByName) == "table" then
            for fakeName in pairs(fakeNames) do
                if recordsByName[fakeName] ~= nil then
                    recordsByName[fakeName] = nil
                    removed[#removed + 1] = fakeName .. " (" .. tableKey .. ")"
                end
            end
        end
    end
    -- answers and alerts of the fake drop triggers (session memory)
    for _, drop in ipairs(addon.RecipeDrops and addon.RecipeDrops.mine or {}) do
        for fakeName in pairs(fakeNames) do
            if drop.answers[fakeName] then drop.answers[fakeName] = nil; removed[#removed + 1] = fakeName .. " (drop answer)" end
        end
    end
    local alerts = addon.RecipeDrops and addon.RecipeDrops.alerts or {}
    for index = #alerts, 1, -1 do
        if fakeNames[alerts[index].from] then table.remove(alerts, index); removed[#removed + 1] = "alert" end
    end
    if addon.UI and addon.UI.SetDropNotice then addon.UI.SetDropNotice(#alerts) end
    for _, removedOrder in ipairs(DevProbe.RemoveFakeOrders(fakeNames)) do removed[#removed + 1] = removedOrder end
    addon.Events.Fire("DATA_CHANGED", "orders")
    for fakeName in pairs(fakeNames) do addon.Store.keptNames[fakeName] = nil end
    addon.Utility.Wipe(devTable("devFake"))
    table.sort(removed)
    for fakeName in pairs(fakeNames) do DevProbe.fakeOnline[fakeName] = nil end
    for _, tableKey in ipairs(MEMBER_TABLES) do addon.Events.Fire("DATA_CHANGED", tableKey) end
    addon.Print(("fake data removed: %d records%s"):format(#removed, #removed > 0 and (": " .. table.concat(removed, ", ")) or ""))
    return recordCheck("remove", { ok = true, removed = removed })
end

------------------------------------------------------------------ fake orders (Members section)

-- The catalog recipe whose reagents the bags cover best (ties: the lower recipe id); nil when no recipe has reagents.
---@return integer|nil recipeID
---@return integer coveredReagents
local function recipeForBags()
    local held = addon.MailSender and addon.MailSender.MailableCounts() or {}
    local bestRecipe, bestScore = nil, -1
    for recipeID, catalogEntry in pairs(addon.Store.db and addon.Store.db.catalog or {}) do
        local reagents = catalogEntry.reagents or {}
        if #reagents > 0 then
            local score = 0
            for _, reagent in ipairs(reagents) do if (held[reagent.itemID] or 0) > 0 then score = score + 1 end end
            if score > bestScore or (score == bestScore and recipeID < bestRecipe) then bestRecipe, bestScore = recipeID, score end
        end
    end
    return bestRecipe, math.max(bestScore, 0)
end

-- An order from a fake member, claimed by a fake crafter and, when one is remembered (/psd mailfill <name>), by that
-- character too: the mail queue can be tried in both modes, including the menu for several claimers. The recipe is the
-- one whose reagents the bags cover best (or arguments[1]). Local only: the order is not broadcast; "Remove all fake
-- data" deletes it and its mail jobs.
---@param arguments? integer[] { recipeID, quantity }
---@return table result
function DevProbe.AddFakeOrder(arguments)
    arguments = arguments or {}
    local catalog = addon.Store.db and addon.Store.db.catalog or {}
    local recipeID, covered = arguments[1], nil
    if not (recipeID and catalog[recipeID]) then recipeID, covered = recipeForBags() end
    if not recipeID or not addon.orders then
        addon.Print("fake order: no recipe with reagents in the catalog yet (scan a profession first)")
        return recordCheck("order", { ok = false, why = "no recipe with reagents" })
    end
    local catalogEntry = catalog[recipeID]
    local quantity = math.max(1, math.min(99, arguments[2] or 2))
    local requester, crafter = fakeMember("Requester"), fakeMember("Crafter")
    local order = addon.orders:Create(requester, recipeID, quantity, "fake order (dev tools)", catalogEntry.name, catalogEntry.loc)
    if not order then
        addon.Print("fake order: the order did not pass validation")
        return recordCheck("order", { ok = false, why = "invalid order" })
    end
    addon.orders:Claim(order.id, crafter)
    local claimers = { crafter }
    local remembered = addon.db and addon.db.devChecks and addon.db.devChecks.mailRecipient
    local realClaimer = type(remembered) == "string" and remembered ~= "" and (addon.Utility.CanonicalName(remembered) or remembered) or nil
    if realClaimer and addon.Utility.IsSafeName(realClaimer) then
        addon.orders:Claim(order.id, realClaimer)
        claimers[#claimers + 1] = realClaimer
    end
    devTable("devFakeOrders")[order.id] = true
    addon.Events.Fire("DATA_CHANGED", "orders")
    addon.Print(("fake order: %dx %s (recipe %d, %s of its reagents in your bags) from %s, claimed by %s. Not sent to the guild."):format(
        quantity, tostring(catalogEntry.name), recipeID, covered and tostring(covered) or "?", requester, table.concat(claimers, ", ")))
    return recordCheck("order", { ok = true, orderID = order.id, recipeID = recipeID, claimers = claimers })
end

local LINEN_CLOTH = 2589
-- used when no catalog recipe needs Linen Cloth: Bolt of Linen Cloth (Tailoring), 2 Linen Cloth each
local LINEN_BOLT_RECIPE, LINEN_BOLT = 2963, { name = "Bolt of Linen Cloth", produces = 2996, reagents = { { itemID = LINEN_CLOTH, count = 2 } } }

-- A fake order for a recipe that needs Linen Cloth: the catalog's recipe with Linen Cloth as its only reagent if there
-- is one, else Bolt of Linen Cloth (added to the catalog). arguments[1] = quantity (default 3).
---@param arguments? integer[]
---@return table result
function DevProbe.AddFakeLinenOrder(arguments)
    local catalog = addon.Store.db and addon.Store.db.catalog or {}
    local recipeID
    for candidateID, catalogEntry in pairs(catalog) do
        local reagents = catalogEntry.reagents or {}
        if #reagents == 1 and reagents[1].itemID == LINEN_CLOTH and (not recipeID or candidateID < recipeID) then recipeID = candidateID end
    end
    if not recipeID then
        addon.Store.PutCatalog({ [LINEN_BOLT_RECIPE] = LINEN_BOLT })
        recipeID = LINEN_BOLT_RECIPE
    end
    return DevProbe.AddFakeOrder({ recipeID, (arguments and arguments[1]) or 3 })
end

-- Deletes the fake orders and the mail jobs made from them; returns what was removed.
---@param fakeNames table<string, boolean>
---@return string[]
function DevProbe.RemoveFakeOrders(fakeNames)
    local removed = {}
    local fakeOrders = devTable("devFakeOrders")
    local orderTable = addon.Store.db and addon.Store.db.orders or {}
    for orderID, order in pairs(orderTable) do
        if fakeOrders[orderID] or fakeNames[order.requester] then
            orderTable[orderID] = nil
            fakeOrders[orderID] = true
            removed[#removed + 1] = "order " .. orderID
        end
    end
    local mailQueue = addon.MailSender and addon.MailSender.Queue()
    if mailQueue then
        for index = #mailQueue:List(), 1, -1 do
            local job = mailQueue:List()[index]
            if fakeOrders[job.orderID] or fakeNames[job.recipient] then
                mailQueue:Remove(job.id)
                removed[#removed + 1] = "mail job " .. job.id
            end
        end
    end
    addon.Utility.Wipe(fakeOrders)
    return removed
end

------------------------------------------------------------------ fake members (Members section)

-- Enchant recipe ids seen in a live guild's data (the recipe id of an enchant looks like its classic spell id).
local FAKE_ENCHANTS = {
    [13419] = "Enchant Cloak - Minor Agility", [7418] = "Enchant Bracer - Inferior Stamina",
    [7426] = "Enchant Chest - Minor Absorption", [7428] = "Enchant Bracer - Minor Deflect",
    [7771] = "Enchant Cloak - Minor Protection", [7786] = "Enchant Weapon - Minor Beastslayer",
}

-- A fake enchanter with FAKE_ENCHANTS, so the Recipes tab shows enchants without a real enchanter.
---@return table result
function DevProbe.AddFakeEnchanter()
    local fakeName = fakeMember("Enchanter")
    local knownRecipes, catalogEntries = {}, {}
    for recipeID, recipeName in pairs(FAKE_ENCHANTS) do
        knownRecipes[recipeID] = true
        catalogEntries[recipeID] = { name = recipeName, loc = "enUS", icon = 135913, reagents = {} }
    end
    addon.Store.PutCatalog(catalogEntries)
    local added = addon.Store.PutCharacter({ name = fakeName, class = "MAGE", level = 60, rev = addon.Utility.Now(),
        professions = { Enchanting = { id = 333, name = "Enchanting", rank = 150, max = 150, recipes = knownRecipes } } })
    addon.Events.Fire("DATA_CHANGED", "chars")
    addon.Print(("fake enchanter added: %d enchants. Recipes tab -> Profession: Enchanting, hover the icons (twice), then /reload to write the log.")
        :format(addon.Utility.Count(knownRecipes)))
    return recordCheck("enchanter", { ok = added and true or false, name = fakeName, recipes = addon.Utility.Count(knownRecipes) })
end

-- Keys and attunements of a fake guild member, for the Keys and Attunements modes of the Misc Items tab.
local FAKE_KEYS = { [7146] = { keyring = true }, [12382] = { bag = true }, [13704] = { keyring = true },
    [18249] = { bank = true }, [11000] = { keyring = true }, [12344] = { bag = true } }

-- Stores the fake key holder's access record changed by `change` (a newer rev, so Access.Put takes it).
---@param change fun(accessRecord: AccessRecord)
---@return AccessRecord
local function updateFakeKeyholder(change)
    local fakeName = fakeMember("Keyholder")
    local previousRecord = addon.Access.Get(fakeName)
    local accessRecord = previousRecord and addon.Utility.DeepCopy(previousRecord) or { name = fakeName, rev = 0, keys = {}, att = {} }
    change(accessRecord)
    accessRecord.rev = math.max(addon.Utility.Now(), (previousRecord and previousRecord.rev or 0) + 1)
    addon.Access.Put(accessRecord)
    addon.Events.Fire("DATA_CHANGED", "access")
    return accessRecord
end

-- Gives the fake key holder a set of dungeon keys (and Molten Core, known not attuned to Onyxia).
---@return AccessRecord
function DevProbe.AddFakeKeys()
    local accessRecord = updateFakeKeyholder(function(record)
        for itemID, locations in pairs(FAKE_KEYS) do record.keys[itemID] = addon.Utility.DeepCopy(locations) end
        record.att.mc, record.att.ony = true, false
    end)
    addon.Print(("fake keys added: %s holds %d keys. Misc Items -> Keys."):format(accessRecord.name, addon.Utility.Count(accessRecord.keys)))
    recordCheck("keys", { ok = true, name = accessRecord.name, keys = addon.Utility.Count(accessRecord.keys) })
    return accessRecord
end

-- Marks the fake key holder as attuned to Naxxramas.
---@return AccessRecord
function DevProbe.AddFakeNaxxramas()
    local accessRecord = updateFakeKeyholder(function(record) record.att.naxx = true end)
    addon.Print(("fake Naxxramas attunement added for %s. Misc Items -> Attunements."):format(accessRecord.name))
    recordCheck("naxx", { ok = true, name = accessRecord.name })
    return accessRecord
end

------------------------------------------------------------------ fake craft cooldowns (Misc Items -> Cooldowns)

-- fake members the cooldown grid treats as online (session only; real members come from the guild roster)
---@type table<string, boolean>
DevProbe.fakeOnline = {}

---@param playerName string
---@return boolean
function DevProbe.IsFakeOnline(playerName) return DevProbe.fakeOnline[playerName] == true end

-- A fake crafter: a character record with `recipes` in `profession`, and (when `readyTimes` is given) a cooldown record
-- as if it had arrived from a peer whose clock is `skew` seconds off (it goes through CraftCooldowns.FromWire).
---@param role string
---@param profession { id: integer, name: string }|nil
---@param recipes integer[]
---@param readyIn table<string, integer>|nil group key -> seconds from now (0 = ready)
---@param options { online: boolean, skew?: integer, estimated?: table<string, boolean> }
---@return string fakeName
local function addFakeCrafter(role, profession, recipes, readyIn, options)
    local fakeName = fakeMember(role)
    local now = addon.Utility.Now()
    if profession then
        local knownRecipes = {}
        for _, recipeID in ipairs(recipes) do knownRecipes[recipeID] = true end
        local previous = addon.Store.db.chars[fakeName]
        addon.Store.PutCharacter({ name = fakeName, class = "PRIEST", level = 60, rev = math.max(now, (previous and previous.rev or 0) + 1),
            professions = { [profession.name] = { id = profession.id, name = profession.name, rank = 300, max = 300, recipes = knownRecipes } } })
    end
    if readyIn then
        local ownerNow = now + (options.skew or 0)
        local readyTimes = {}
        for groupKey, seconds in pairs(readyIn) do readyTimes[groupKey] = seconds > 0 and (ownerNow + seconds) or 0 end
        local previous = addon.CraftCooldowns.Get(fakeName)
        local wireRecord = addon.CraftCooldowns.Sanitize({ name = fakeName, rev = math.max(now, (previous and previous.rev or 0) + 1),
            c = readyTimes, e = options.estimated or {} })
        addon.CraftCooldowns.Put(addon.CraftCooldowns.FromWire(wireRecord, ownerNow, now))
    end
    DevProbe.fakeOnline[fakeName] = options.online or nil
    return fakeName
end

local ALCHEMY, TAILORING = { id = 171, name = "Alchemy" }, { id = 197, name = "Tailoring" }

-- Fake crafters in every state: ready (online), cooling with a clock 2 h ahead (online), an estimate that runs out in
-- 50 s (online), cooling (offline), no cooldown data (online).
---@return table result
function DevProbe.AddFakeCooldowns()
    local names = {
        addFakeCrafter("Alchemist", ALCHEMY, { 17187, 17559 }, { transmute = 0 }, { online = true }),
        addFakeCrafter("Tailor", TAILORING, { 18560 }, { mooncloth = 3 * 3600 + 120 }, { online = true, skew = 7200 }),
        addFakeCrafter("Salter", nil, {}, { saltshaker = 50 }, { online = true, estimated = { saltshaker = true } }),
        addFakeCrafter("Sleeper", ALCHEMY, { 17187 }, { transmute = 20 * 3600 }, { online = false }),
        addFakeCrafter("Newbie", ALCHEMY, { 11479 }, nil, { online = true }),
    }
    addon.Events.Fire("DATA_CHANGED", "cds")
    addon.Print(("fake cooldowns added for %d members (one clock 2 h ahead; the salt runs out in 50 s). Misc Items -> Cooldowns.")
        :format(#names))
    return recordCheck("cooldowns", { ok = true, names = names })
end

-- A fake crafter whose cooldown of `groupKey` (default transmute) ends in 20 s, to watch a tile turn ready.
---@param groupKey string|nil
---@return table result
function DevProbe.AddFakeCooldownEnding(groupKey)
    local group = addon.CraftCooldowns.Group(groupKey) or addon.CraftCooldowns.Group("transmute")
    local profession = group.skillLine == 197 and TAILORING or (#group.recipes > 0 and ALCHEMY or nil)
    local fakeName = addFakeCrafter("Timer", profession, group.recipes, { [group.key] = 20 }, { online = true })
    addon.Events.Fire("DATA_CHANGED", "cds")
    addon.Print(("%s: %s is ready in 20 s. Misc Items -> Cooldowns."):format(fakeName, group.key))
    return recordCheck("cdsoon", { ok = true, name = fakeName, group = group.key })
end

-- Three messages from a fake member (one bug with a diagnostic snapshot), for the developer list of the Feedback tab.
---@return FeedbackRecord|nil
function DevProbe.AddFakeFeedback()
    local fakeName = fakeMember("Tester")
    local now = addon.Utility.Now()
    local previousRecord = addon.Feedback.Get(fakeName)
    local feedbackRecord = { name = fakeName, rev = math.max(now, (previousRecord and previousRecord.rev or 0) + 1), items = {
        { t = math.max(1, now - 7200), k = "feature", text = "Please add a filter for recipes I can craft right now." },
        { t = math.max(2, now - 600), k = "feedback", text = "The Misc Items tab is great / keys are very handy." },
        { t = math.max(3, now - 30), k = "bug", text = "What I did: opened Orders / What happened: empty list / What I expected: my order",
            log = table.concat({ "v1.3.0-dev protocol 2.5 schema 7 locale deDE client test", "active=true queue=0 sendFailures=0",
                "2026-11-23 10:00 WARNING [fake] a test warning" }, "\n") },
    } }
    if not addon.Feedback.Put(feedbackRecord, addon.Utility.Me()) then
        addon.Print("fake feedback not stored: this client does not read feedback")
        recordCheck("feedback", { ok = false, name = fakeName, why = "this client does not read feedback" })
        return nil
    end
    addon.Events.Fire("DATA_CHANGED", "feedback")
    addon.Print(("fake feedback added: 3 messages from %s. Feedback tab."):format(fakeName))
    recordCheck("feedback", { ok = true, name = fakeName, messages = #feedbackRecord.items })
    return feedbackRecord
end

------------------------------------------------------------------ fake realm request (Triggers section)

-- The realms a member whose client still reports realms appended to my name in a live log.
local FAKE_REQUEST_REALMS = { "CAMWOWEU4Realm3PvE", "CAMWOWEU4Realm5PvE" }
local FAKE_REQUESTER = "Fake Requester"

-- Replays the request that member sent (WANTO and WANT naming me as "Name-Realm" and "FirstName-Realm") against MY real
-- data, on a separate Sync whose sends are captured and never leave the client (no whisper to a player who does not
-- exist, no change to the real sync's state). Prints and traces whether I would answer, and under which name.
-- A client without a realm once answered nothing here: "asked for ... but I am ... (name mismatch)".
---@return { type: string, status: string, reason: string, answer: string|nil, answerName: string|nil, items: integer|nil }[]
function DevProbe.SimulateRealmRequest()
    local myName = addon.Store.db and addon.Store.db.me
    if type(myName) ~= "string" or myName == "" then
        addon.Print("fake request: my own name is not known yet")
        recordCheck("request", { ok = false, why = "my own name is not known yet" })
        return {}
    end
    local bareName = myName:match("^([^-]+)") or myName
    local firstName = bareName:match("^(%S+)") or bareName
    local askedNames = {}
    for _, realmName in ipairs(FAKE_REQUEST_REALMS) do
        askedNames[#askedNames + 1] = bareName .. "-" .. realmName
        if firstName ~= bareName then askedNames[#askedNames + 1] = firstName .. "-" .. realmName end
    end
    local captured = {}
    local simulatedSync = addon.Sync.New({
        send = function(message, channel, target) captured[#captured + 1] = { message = message, channel = channel, target = target } end,
        now = addon.Utility.Now, random = math.random, store = addon.Store, orders = addon.orders,
        me = function() return addon.Store.db.me end, onChange = function() end,
    })
    local answerTypeByRequest = { WANTO = "OFFERS", WANT = "SNAP" }
    local results = {}
    for _, requestType in ipairs({ "WANTO", "WANT" }) do
        local status, reason = simulatedSync:OnMessage({ v = addon.PROTOCOL, t = requestType, names = askedNames }, FAKE_REQUESTER)
        addon.Trace.Add({ dir = "in", ch = "WHISPER", peer = FAKE_REQUESTER, mt = requestType, st = tostring(status),
            info = "SIMULATED names=" .. table.concat(askedNames, ","), why = tostring(reason) })
        results[#results + 1] = { type = requestType, status = tostring(status), reason = tostring(reason) }
    end
    simulatedSync:Tick(addon.Utility.Now() + 3600)   -- answers wait a few seconds; flush them now (captured, not sent)
    for _, result in ipairs(results) do
        for _, sent in ipairs(captured) do
            if sent.message.t == answerTypeByRequest[result.type] then
                local record = sent.message.offers or sent.message.char or {}
                result.answer, result.answerName = sent.message.t, record.name
                result.items = addon.Utility.Count(record.items or {}) + addon.Utility.Count(record.professions or {})
                addon.Trace.Add({ dir = "out", ch = tostring(sent.channel), peer = FAKE_REQUESTER, mt = sent.message.t, st = "info",
                    info = "SIMULATED, not sent: name=" .. tostring(record.name), why = "answer to the simulated " .. result.type })
            end
        end
    end
    local library = LibStub and LibStub("LibGuildSync-1.0", true)
    addon.Print(("fake request as a member whose client reports realms (LibGuildSync MINOR %s active), asking for %s:")
        :format(tostring(library and library.MINOR), table.concat(askedNames, ", ")))
    local allAnswered = true
    for _, result in ipairs(results) do
        if result.answer then
            addon.Print(("  %s -> |cff33ff99answered|r with %s under the name %s"):format(result.type, result.answer, tostring(result.answerName)))
        else
            allAnswered = false
            addon.Print(("  %s -> |cffff5555not answered|r: %s %s"):format(result.type, result.status, result.reason))
        end
    end
    addon.Events.Fire("DATA_CHANGED", "trace")
    recordCheck("request", { ok = allAnswered, results = results })
    return results
end

------------------------------------------------------------------ recipe probe: what my own tooltip says (Probes section)

local STATUS_COLOR = { learnable = "33ff99", low = "ff5555", known = "aaaaaa", noProfession = "aaaaaa", unreadable = "ffaa00" }

-- What this client's tooltip and my stored professions say about one recipe item.
---@param itemID integer
---@param bound boolean|nil soulbound in my bags (nil: not in my bags)
---@return table itemResult
local function probeRecipeItem(itemID, bound)
    local tooltipLines = addon.Api.ItemTooltipLinesWithColor(itemID)
    local reading = addon.RecipeCheck.ReadTooltip(tooltipLines, addon.Api.RecipeCheckStrings())
    local myRecord = addon.Store.db and addon.Store.GetCharacter(addon.Store.db.me)
    local decision = addon.RecipeCheck.Decide(reading, myRecord and myRecord.professions)
    local evidenceLines = {}
    for _, tooltipLine in ipairs(tooltipLines or {}) do
        evidenceLines[#evidenceLines + 1] = tooltipLine.text .. (tooltipLine.r and (" {%.2f %.2f %.2f}"):format(tooltipLine.r,
            tooltipLine.g or 0, tooltipLine.b or 0) or "")
    end
    return { itemID = itemID, name = addon.Api.ItemName(itemID), bound = bound, cached = tooltipLines ~= nil,
        profession = reading and reading.profession, required = reading and reading.required,
        requiredRed = reading and reading.requiredRed, known = reading and reading.known or false,
        bindOnPickup = reading and reading.bindOnPickup or false,
        status = decision.status, rank = decision.rank, mismatch = decision.mismatch, lines = evidenceLines }
end

---@param itemResult table
---@return string
local function describeRecipeResult(itemResult)
    local requirement = itemResult.required and ("%s %d%s"):format(tostring(itemResult.profession), itemResult.required,
        itemResult.requiredRed == true and " (red)" or itemResult.requiredRed == false and " (not red)" or "") or "no requirement read"
    return ("  %s %s: %s, known=%s, BoP=%s -> |cff%s%s|r%s%s"):format(tostring(itemResult.itemID), tostring(itemResult.name or "?"),
        requirement, tostring(itemResult.known), tostring(itemResult.bindOnPickup), STATUS_COLOR[itemResult.status] or "ffffff",
        itemResult.status, itemResult.rank and (" (my skill " .. itemResult.rank .. ")") or "",
        itemResult.mismatch and " |cffff5555MISMATCH colour/skill|r" or "")
end

local recipeProbeRunning = false

-- Every recipe item in my bags (and `extraItemIDs`) through RecipeCheck, with the raw tooltip lines and colours as
-- evidence. Items the client has not loaded yet are asked for once more after a few seconds.
---@param extraItemIDs? integer[]
---@return table|nil result (nil while it waits for item data)
function DevProbe.RecipeProbe(extraItemIDs)
    if recipeProbeRunning then addon.Print("recipe probe already running") return nil end
    local plan, planned = {}, {}
    for _, bagItem in ipairs(addon.Api.BagRecipeItems()) do
        if not planned[bagItem.itemID] then planned[bagItem.itemID] = true; plan[#plan + 1] = { itemID = bagItem.itemID, bound = bagItem.bound } end
    end
    for _, itemID in ipairs(extraItemIDs or {}) do
        if not planned[itemID] then planned[itemID] = true; plan[#plan + 1] = { itemID = itemID } end
    end
    local strings = addon.Api.RecipeCheckStrings()
    local myRecord = addon.Store.db and addon.Store.GetCharacter(addon.Store.db.me)
    local myProfessions = {}
    for professionKey, profession in pairs(myRecord and myRecord.professions or {}) do
        myProfessions[professionKey] = { name = profession.name, rank = profession.rank, max = profession.max }
    end
    local function finish()
        local result = { ok = true, locale = GetLocale and GetLocale() or nil, strings = strings, myProfessions = myProfessions,
            items = {}, counts = {}, mismatches = 0, unreadable = 0 }
        for _, planEntry in ipairs(plan) do
            local itemResult = probeRecipeItem(planEntry.itemID, planEntry.bound)
            result.items[#result.items + 1] = itemResult
            result.counts[itemResult.status] = (result.counts[itemResult.status] or 0) + 1
            if itemResult.mismatch then result.mismatches = result.mismatches + 1 end
            if itemResult.status == "unreadable" then result.unreadable = result.unreadable + 1 end
        end
        result.ok = result.mismatches == 0 and result.unreadable == 0 and #plan > 0
        addon.Print(("recipe probe: %d recipe items, %d mismatches, %d unreadable (/reload writes devChecks.recipes):")
            :format(#plan, result.mismatches, result.unreadable))
        for _, itemResult in ipairs(result.items) do addon.Print(describeRecipeResult(itemResult)) end
        if #plan == 0 then addon.Print("  no recipe item in my bags; /psd recipeprobe <itemID> probes one by id") end
        return recordCheck("recipes", result)
    end
    local notLoaded = 0
    for _, planEntry in ipairs(plan) do
        if not addon.Api.ItemTooltipLinesWithColor(planEntry.itemID) then notLoaded = notLoaded + 1 end   -- also asks the server
    end
    if notLoaded == 0 or not (C_Timer and C_Timer.After) then return finish() end
    recipeProbeRunning = true
    addon.Print(("recipe probe: %d items not loaded yet, reading in 3s"):format(notLoaded))
    C_Timer.After(3, function()
        recipeProbeRunning = false
        addon.Log.Protected("devProbe.recipeProbe", "the recipe probe failed", finish)
    end)
    return nil
end

------------------------------------------------------------------ key probe (Probes section)

local keyProbeRunning = false

-- Everything GetItemInfo / GetItemSpell report for an item (nil while it is not loaded).
---@param itemID integer
---@return table|nil
local function itemInformation(itemID)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo then return nil end
    local ok, name, link, quality, itemLevel, minimumLevel, typeName, subtypeName, stackCount, equipLocation, icon, sellPrice,
        classID, subclassID, bindType, expansionID = pcall(getItemInfo, itemID)
    if not ok or not name then return nil end
    local information = { link = link and link:gsub("|", "||") or nil, quality = quality, itemLevel = itemLevel,
        minimumLevel = minimumLevel, typeName = typeName, subtypeName = subtypeName, stackCount = stackCount,
        equipLocation = equipLocation, icon = icon, sellPrice = sellPrice, classID = classID, subclassID = subclassID,
        bindType = bindType, expansionID = expansionID }
    local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if getItemSpell then
        local spellOk, spellName, spellID = pcall(getItemSpell, itemID)
        if spellOk then information.spellName, information.spellID = spellName, spellID end
    end
    return information
end

-- The item's tooltip for this character as "text {r g b}" lines (nil while it is not loaded).
---@param itemID integer
---@return string[]|nil
local function tooltipEvidence(itemID)
    local ok, tooltipLines = pcall(addon.Api.ItemTooltipLinesWithColor, itemID)
    if not ok then return { "tooltip error: " .. tostring(tooltipLines) } end
    if not tooltipLines then return nil end
    local evidenceLines = {}
    for _, tooltipLine in ipairs(tooltipLines) do
        evidenceLines[#evidenceLines + 1] = tooltipLine.text .. (tooltipLine.r and (" {%.2f %.2f %.2f}"):format(tooltipLine.r,
            tooltipLine.g or 0, tooltipLine.b or 0) or "")
    end
    return evidenceLines
end

local keyScanRunning = false

-- Walks item ids 1..maximumID through the client's own item data (GetItemInfoInstant, no server query) in slices of
-- `sliceSize` per frame and collects every item of class Key; then reads their names (asking the server once).
-- Result in devChecks.keyScan. `done` (optional) is called with the result.
---@param maximumID? integer default 300000
---@param sliceSize? integer default 10000
---@param done? fun(result: table)
---@return table|nil result (nil while it runs)
function DevProbe.KeyScan(maximumID, sliceSize, done)
    if keyScanRunning then addon.Print("key scan already running") return nil end
    local Api, Access = addon.Api, addon.Access
    maximumID, sliceSize = maximumID or 300000, sliceSize or 10000
    local found, nextID = {}, 1
    local function finish()
        local result = { ok = true, maximumID = maximumID, keys = {}, unlisted = 0, notLoaded = 0 }
        for _, itemID in ipairs(found) do
            local _, subclassID = Api.ItemClass(itemID)
            local keyResult = { itemID = itemID, name = Api.ItemName(itemID), subclassID = subclassID,
                instance = Access.KEYS[itemID], denied = Access.DENY[itemID] or nil,
                info = itemInformation(itemID), lines = tooltipEvidence(itemID) }
            if not keyResult.name then result.notLoaded = result.notLoaded + 1 end
            if not keyResult.instance and not keyResult.denied then result.unlisted = result.unlisted + 1 end
            result.keys[#result.keys + 1] = keyResult
        end
        addon.Print(("key scan: ids 1-%d, %d items of class Key, %d not on the list or the deny list, %d names not loaded (/reload writes devChecks.keyScan)")
            :format(maximumID, #found, result.unlisted, result.notLoaded))
        recordCheck("keyScan", result)
        if done then done(result) end
        return result
    end
    local function readNames()
        local notLoaded = 0
        for _, itemID in ipairs(found) do if not Api.ItemName(itemID) then notLoaded = notLoaded + 1 end end
        if notLoaded == 0 or not (C_Timer and C_Timer.After) then keyScanRunning = false return finish() end
        addon.Print(("key scan: %d keys found, %d names not loaded yet, reading in 5s"):format(#found, notLoaded))
        C_Timer.After(5, function()
            keyScanRunning = false
            addon.Log.Protected("devProbe.keyScan", "the key scan failed", finish)
        end)
        return nil
    end
    local function slice()
        local lastID = math.min(nextID + sliceSize - 1, maximumID)
        for itemID = nextID, lastID do
            if Api.ItemClass(itemID) == Access.KEY_CLASS then found[#found + 1] = itemID end
        end
        nextID = lastID + 1
        if nextID <= maximumID then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() addon.Log.Protected("devProbe.keyScan", "the key scan failed", slice) end)
                return nil
            end
            return slice()
        end
        return readNames()
    end
    keyScanRunning = true
    addon.Print(("key scan: walking item ids 1-%d (%d per frame)"):format(maximumID, sliceSize))
    return slice()
end

-- Every listed key, every key in a known access record, every key my scan sees and `extraItemIDs`, with the client's
-- name and item class, whether it counts as a key and which instance it is listed for; plus my attunement quest answers.
-- Items the client has not loaded yet are read again after a few seconds.
---@param extraItemIDs? integer[]
---@return table|nil result (nil while it waits for item data)
function DevProbe.KeyProbe(extraItemIDs)
    if keyProbeRunning then addon.Print("key probe already running") return nil end
    local Api, Access = addon.Api, addon.Access
    local sources = {}
    local function plan(itemID, source)
        if type(itemID) ~= "number" then return end
        sources[itemID] = sources[itemID] or {}
        sources[itemID][source] = true
    end
    for itemID in pairs(Access.KEYS) do plan(itemID, "listed") end
    local holdersByItem = Access.KeyHolders()
    for itemID in pairs(holdersByItem) do plan(itemID, "record") end
    local scanned, accessScan = pcall(Api.ScanAccess)
    for _, heldKeys in pairs(scanned and type(accessScan) == "table" and accessScan.keys or {}) do
        for itemID in pairs(heldKeys) do plan(itemID, "scan") end
    end
    for _, itemID in ipairs(extraItemIDs or {}) do plan(itemID, "argument") end
    local function finish()
        local result = { ok = true, keys = {}, unlisted = 0, notLoaded = 0, attunements = {},
            keyring = Api.accessStatistics and Api.accessStatistics.keyring or false,
            questApi = Api.accessStatistics and Api.accessStatistics.questApi or false }
        for _, itemID in ipairs(addon.Utility.SortedKeys(sources)) do
            local classID, subclassID = Api.ItemClass(itemID)
            local keyResult = { itemID = itemID, name = Api.ItemName(itemID), classID = classID, subclassID = subclassID,
                isKey = Access.IsKey(itemID, classID), denied = Access.DENY[itemID] or nil, instance = Access.KEYS[itemID],
                holders = #(holdersByItem[itemID] or {}), sources = addon.Utility.SortedKeys(sources[itemID]),
                info = itemInformation(itemID), lines = tooltipEvidence(itemID) }
            if not keyResult.name then result.notLoaded = result.notLoaded + 1 end
            if keyResult.isKey and not keyResult.instance then result.unlisted = result.unlisted + 1 end
            result.keys[#result.keys + 1] = keyResult
        end
        for _, attunement in ipairs(Access.ATTUNEMENTS) do
            local quests = {}
            for _, questID in ipairs(attunement.quests) do quests[tostring(questID)] = tostring(Api.QuestDone(questID)) end
            result.attunements[attunement.key] = { quests = quests,
                item = attunement.item and Api.ItemCount(attunement.item) or nil }
        end
        result.ok = result.notLoaded == 0
        addon.Print(("key probe: %d items, %d keys without an instance, %d not loaded (/reload writes devChecks.keyProbe):")
            :format(#result.keys, result.unlisted, result.notLoaded))
        for _, keyResult in ipairs(result.keys) do
            addon.Print(("  %d %s: class %s/%s, key=%s, instance=%s, holders=%d (%s)"):format(keyResult.itemID,
                tostring(keyResult.name or "?"), tostring(keyResult.classID), tostring(keyResult.subclassID),
                tostring(keyResult.isKey), tostring(keyResult.instance or "-"), keyResult.holders, table.concat(keyResult.sources, ",")))
        end
        return recordCheck("keyProbe", result)
    end
    local notLoaded = 0
    for itemID in pairs(sources) do
        if not Api.ItemName(itemID) then notLoaded = notLoaded + 1 end   -- also asks the server
    end
    if notLoaded == 0 or not (C_Timer and C_Timer.After) then return finish() end
    keyProbeRunning = true
    addon.Print(("key probe: %d items not loaded yet, reading in 3s"):format(notLoaded))
    C_Timer.After(3, function()
        keyProbeRunning = false
        addon.Log.Protected("devProbe.keyProbe", "the key probe failed", finish)
    end)
    return nil
end

------------------------------------------------------------------ loot recorder and fake loot (Triggers section)

---@param itemID integer
---@return integer count in my bags (bank not counted)
local function bagCount(itemID)
    local getItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not getItemCount then return 0 end
    local ok, itemCount = pcall(getItemCount, itemID, false)
    return ok and tonumber(itemCount) or 0
end

-- Fills a client format string with `arguments` by argument index ("%s"/"%d" in order, or "%2$s").
---@param formatString string
---@param arguments any[]
---@return string
local function fillFormat(formatString, arguments)
    local nextArgument = 0
    return (formatString:gsub("%%(%d*)%$?([sd])", function(argumentText, _)
        nextArgument = nextArgument + 1
        return tostring(arguments[tonumber(argumentText) or nextArgument] or "")
    end))
end

-- Records a loot chat line with a recipe item: which client format matched, my bag count at the line and a few seconds
-- later, and what my own tooltip says about the item. Lines without a recipe item are ignored.
---@param message any
---@param simulated boolean|nil
---@return table|nil lootRecord
function DevProbe.RecordLootLine(message, simulated)
    local loot = addon.RecipeCheck.ParseLoot(message, addon.Api.RecipeCheckStrings().loot)
    if not loot or addon.Api.ItemClass(loot.itemID) ~= addon.Offers.RECIPE_CLASS then return nil end
    local itemResult = probeRecipeItem(loot.itemID, nil)
    itemResult.lines = nil
    local lootRecord = { at = timestamp(), simulated = simulated and true or false, kind = loot.kind, itemID = loot.itemID,
        count = loot.count, bagAtLine = bagCount(loot.itemID), item = itemResult,
        -- another player's line names that player: keep only the item
        message = loot.kind == "other" and ("<player> ... " .. loot.link) or tostring(message) }
    -- the rule a drop alert would follow: my own loot, not bound on pickup, in my bags
    local function wouldAnnounce()
        return lootRecord.kind == "self" and not itemResult.bindOnPickup and (lootRecord.bagLater or 0) > 0
    end
    local lootLines = devTable("devChecks").lootLines
    if type(lootLines) ~= "table" then lootLines = {}; devTable("devChecks").lootLines = lootLines end
    table.insert(lootLines, 1, lootRecord)
    while #lootLines > MAXIMUM_LOOT_LINES do table.remove(lootLines) end
    for _, seconds in ipairs(LOOT_RECHECK_SECONDS) do
        if C_Timer and C_Timer.After then
            C_Timer.After(seconds, function()
                lootRecord["bagAfter" .. seconds] = bagCount(loot.itemID)
                lootRecord.bagLater = lootRecord["bagAfter" .. seconds]
                lootRecord.wouldAnnounce = wouldAnnounce()
                if seconds == LOOT_RECHECK_SECONDS[#LOOT_RECHECK_SECONDS] then
                    addon.Print(("loot line (%s%s): %s, bag %d -> %d, %s -> would announce: %s"):format(lootRecord.kind,
                        lootRecord.simulated and ", simulated" or "", tostring(itemResult.name or loot.itemID), lootRecord.bagAtLine,
                        lootRecord.bagLater, itemResult.status, tostring(lootRecord.wouldAnnounce)))
                end
            end)
        end
    end
    addon.Log.Information("devProbe.loot", "a loot line with a recipe item was recorded",
        { kind = loot.kind, itemID = loot.itemID, simulated = lootRecord.simulated })
    return lootRecord
end

-- A loot line in the client's own format with a recipe item from my bags (or `itemID`), as mine or as another player's,
-- through the same recorder as a real line.
---@param kind "self"|"other"
---@param itemID? integer
---@return table|nil lootRecord
function DevProbe.SimulateRecipeLoot(kind, itemID)
    if not itemID then
        local bagItem = addon.Api.BagRecipeItems()[1]
        itemID = bagItem and bagItem.itemID
    end
    if not itemID then
        addon.Print("fake loot: no recipe item in my bags; /psd fake loot <itemID>")
        recordCheck("loot", { ok = false, why = "no recipe item in my bags" })
        return nil
    end
    local formats = addon.Api.RecipeCheckStrings().loot[kind == "other" and "other" or "self"]
    local formatString = formats and formats[#formats]   -- the single-item form
    if not formatString then
        recordCheck("loot", { ok = false, why = "the client has no loot format" })
        return nil
    end
    local link = addon.Api.ItemLink(itemID) or ("|cffffffff|Hitem:" .. itemID .. "::::::::60:::::|h[item " .. itemID .. "]|h|r")
    local message = kind == "other" and fillFormat(formatString, { "Fake Looter", link }) or fillFormat(formatString, { link })
    local lootRecord = DevProbe.RecordLootLine(message, true)
    recordCheck(kind == "other" and "lootOther" or "loot", { ok = lootRecord ~= nil and lootRecord.kind == (kind == "other" and "other" or "self"),
        message = lootRecord and lootRecord.message or message, kind = lootRecord and lootRecord.kind, itemID = itemID })
    return lootRecord
end

------------------------------------------------------------------ fake recipe drops (Triggers section)

-- a recipe item for the drop triggers: the asked id, else the first recipe in my bags
---@param itemID integer|nil
---@return integer|nil
local function dropItem(itemID)
    if itemID then return itemID end
    local bagItem = addon.Api.BagRecipeItems()[1]
    return bagItem and bagItem.itemID
end

-- A fake member announces a recipe drop to me: the real decision from my own tooltip, the alert, and the answer I would
-- whisper (captured, never sent).
---@param itemID? integer
function DevProbe.SimulateIncomingDrop(itemID)
    itemID = dropItem(itemID)
    if not itemID or not addon.Drops then
        addon.Print("fake drop: no recipe item in my bags; /psd fake dropin <itemID>")
        recordCheck("dropIn", { ok = false, why = "no recipe item" })
        return
    end
    local looter = fakeMember("Looter")
    addon.RecipeDrops.seen[looter .. ":" .. itemID] = nil   -- a repeated test is not a duplicate
    local captured
    addon.Drops.OnDrop(looter, itemID, {
        answer = function(target, answeredItemID, status, rank) captured = { target = target, item = answeredItemID, s = status, r = rank } end,
        done = function(result)
            addon.Print(("fake drop from %s: %s -> my status %s, answer %s (captured, not sent)"):format(looter,
                tostring(addon.Api.ItemName(itemID) or itemID), tostring(result.status), captured and (captured.s .. " " .. captured.r) or "none"))
            recordCheck("dropIn", { ok = result.status ~= "unreadable", itemID = itemID, status = result.status, answer = captured,
                alerts = #addon.RecipeDrops.alerts })
        end,
    })
end

-- A recipe "dropped for me" with answers from four fake members (three green, one red), so the tooltip list, its order
-- and the "..." can be checked. Nothing is sent to the guild.
---@param itemID? integer
function DevProbe.SimulateMyDropAnswers(itemID)
    itemID = dropItem(itemID)
    if not itemID then
        addon.Print("fake answers: no recipe item in my bags; /psd fake dropmine <itemID>")
        recordCheck("dropMine", { ok = false, why = "no recipe item" })
        return
    end
    local now = addon.Utility.Now()
    addon.RecipeDrops.NoteMyDrop(itemID, now)
    local answers = { { "Alchemist", "g", 280 }, { "Tailor", "r", 240 }, { "Cook", "g", 300 }, { "Skinner", "g", 265 } }
    for _, answer in ipairs(answers) do
        addon.RecipeDrops.AddAnswer(fakeMember(answer[1]), { item = itemID, s = answer[2], r = answer[3] }, now)
    end
    addon.Events.Fire("DATA_CHANGED", "drops")
    local link = addon.Api.ItemLink(itemID) or tostring(itemID)
    addon.Print(("fake answers to my drop %s: hover the link or the item in the bags (expected: Cook 300, Alchemist 280, Skinner 265, then ...)")
        :format(link))
    local hint = addon.RecipeDrops.HintRows(itemID)
    recordCheck("dropMine", { ok = hint ~= nil and #hint.rows == 3 and hint.more == 1, itemID = itemID, rows = hint and hint.rows,
        more = hint and hint.more })
end

if addon.IS_DEVELOPMENT_BUILD and CreateFrame then
    local lootFrame = CreateFrame("Frame")
    pcall(lootFrame.RegisterEvent, lootFrame, "CHAT_MSG_LOOT")
    lootFrame:SetScript("OnEvent", function(_, _, message)
        addon.Log.Protected("devProbe.lootLine", "recording a loot line failed", DevProbe.RecordLootLine, message, false)
    end)
end

------------------------------------------------------------------ the Dev tools menu and /psd fake

---@class DevEntry
---@field key string /psd fake <key>
---@field section string
---@field label string
---@field run fun(arguments: integer[])

DevProbe.SECTIONS = { "Members", "Triggers", "Probes", "Cleanup" }

---@type DevEntry[]
DevProbe.ENTRIES = {
    { key = "enchanter", section = "Members", label = "Enchanter: 6 enchants", run = function() DevProbe.AddFakeEnchanter() end },
    { key = "keys", section = "Members", label = "Keyholder: dungeon keys", run = function() DevProbe.AddFakeKeys() end },
    { key = "naxx", section = "Members", label = "Keyholder: Naxxramas", run = function() DevProbe.AddFakeNaxxramas() end },
    { key = "feedback", section = "Members", label = "Tester: 3 feedback messages", run = function() DevProbe.AddFakeFeedback() end },
    { key = "order", section = "Members", label = "Order from a fake member (mail queue)", run = function(arguments) DevProbe.AddFakeOrder(arguments) end },
    { key = "linen", section = "Members", label = "Order needing Linen Cloth (mail queue)", run = function(arguments) DevProbe.AddFakeLinenOrder(arguments) end },
    { key = "cooldowns", section = "Members", label = "Crafters: cooldowns in every state", run = function() DevProbe.AddFakeCooldowns() end },
    { key = "cdsoon", section = "Triggers", label = "A cooldown ends in 20 s", run = function() DevProbe.AddFakeCooldownEnding() end },
    { key = "cdprobe", section = "Probes", label = "Craft cooldowns (/ps cd)", run = function() addon.SlashCommands.cd("") end },
    { key = "request", section = "Triggers", label = "Realm request (WANTO / WANT)", run = function() DevProbe.SimulateRealmRequest() end },
    { key = "loot", section = "Triggers", label = "Recipe loot (me)", run = function(arguments) DevProbe.SimulateRecipeLoot("self", arguments[1]) end },
    { key = "lootother", section = "Triggers", label = "Recipe loot (other player)", run = function(arguments) DevProbe.SimulateRecipeLoot("other", arguments[1]) end },
    { key = "dropin", section = "Triggers", label = "Recipe drop from a member", run = function(arguments) DevProbe.SimulateIncomingDrop(arguments[1]) end },
    { key = "dropmine", section = "Triggers", label = "Answers to my recipe drop", run = function(arguments) DevProbe.SimulateMyDropAnswers(arguments[1]) end },
    { key = "recipes", section = "Probes", label = "Recipes in my bags", run = function(arguments) DevProbe.RecipeProbe(arguments) end },
    { key = "keyprobe", section = "Probes", label = "Keys and attunements", run = function(arguments) DevProbe.KeyProbe(arguments) end },
    { key = "keyscan", section = "Probes", label = "All keys in the item data", run = function(arguments) DevProbe.KeyScan(arguments[1]) end },
    { key = "items", section = "Probes", label = "Item probe (catalog)", run = function(arguments) DevProbe.Run(arguments) end },
    { key = "mail", section = "Probes", label = "Mail API check (more: /psd mailprobe)", run = function() addon.MailProbe.CheckApi() end },
    { key = "remove", section = "Cleanup", label = "Remove all fake data", run = function() DevProbe.RemoveFakeData() end },
}

-- Runs the entry with this key; false for an unknown key.
---@param key string
---@param arguments? integer[]
---@return boolean
function DevProbe.RunEntry(key, arguments)
    for _, entry in ipairs(DevProbe.ENTRIES) do
        if entry.key == key then
            addon.Log.Protected("devProbe.entry", "a dev tools entry failed", entry.run, arguments or {})
            return true
        end
    end
    return false
end

function DevProbe.PrintEntries()
    addon.Print("dev tools (/psd fake <key> [itemID]):")
    for _, section in ipairs(DevProbe.SECTIONS) do
        for _, entry in ipairs(DevProbe.ENTRIES) do
            if entry.section == section then addon.Print(("  %s: %s - %s"):format(section, entry.key, entry.label)) end
        end
    end
end

---@param arguments any
---@return integer[]
local function numbersIn(arguments)
    local numbers = {}
    for numberText in tostring(arguments or ""):gmatch("%d+") do numbers[#numbers + 1] = tonumber(numberText) end
    return numbers
end

if addon.IS_DEVELOPMENT_BUILD then
    addon.SlashCommands.fake = function(arguments)
        local key = tostring(arguments or ""):match("^%s*(%S+)")
        if not key or not DevProbe.RunEntry(key:lower(), numbersIn(arguments)) then DevProbe.PrintEntries() end
    end
    addon.SlashCommands.recipeprobe = function(arguments) DevProbe.RecipeProbe(numbersIn(arguments)) end
    addon.SlashCommands.itemprobe = function(arguments) DevProbe.Run(numbersIn(arguments)) end
    addon.SlashCommands.keyprobe = function(arguments) DevProbe.KeyProbe(numbersIn(arguments)) end
    addon.SlashCommands.keyscan = function(arguments) DevProbe.KeyScan(numbersIn(arguments)[1]) end
    -- older names of the same entries
    addon.SlashCommands.fakerequest = function() DevProbe.RunEntry("request") end
    addon.SlashCommands.fakeenchanter = function() DevProbe.RunEntry("enchanter") end
    addon.SlashCommands.fakekeys = function() DevProbe.RunEntry("keys") end
    addon.SlashCommands.fakenaxx = function() DevProbe.RunEntry("naxx") end
    addon.SlashCommands.fakefeedback = function() DevProbe.RunEntry("feedback") end
end
