local addonName, addon = ...

-- DEV BUILD ONLY (feature 011 T1): records what this client can tell about the items our recipes make, so the
-- category filter and the effect-text search are built on facts instead of guesses. Button "Item probe" on the Debug tab,
-- or /psd itemprobe [itemID ...]. Writes addon.db.devProbe (ProfessionShareDevDB); /reload flushes it to
-- WTF\Account\<ACCOUNT>\SavedVariables\ProfessionShare-Dev.lua. The live build never runs it (no button, no command).
-- Plain English strings on purpose: dev-only, not localized. The keys of the recorded tables are the file format the
-- feature 011 analysis reads; they stay as they are.
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

------------------------------------------------------------------ fake enchanter (feature 017 test, dev build only)

-- Enchant recipe ids seen in a live guild's data (the recipe id of an enchant looks like its classic spell id).
local FAKE_ENCHANTS = {
    [13419] = "Enchant Cloak - Minor Agility", [7418] = "Enchant Bracer - Inferior Stamina",
    [7426] = "Enchant Chest - Minor Absorption", [7428] = "Enchant Bracer - Minor Deflect",
    [7771] = "Enchant Cloak - Minor Protection", [7786] = "Enchant Weapon - Minor Beastslayer",
}

-- Adds "Fake Enchanter-<my realm>" with Enchanting and FAKE_ENCHANTS to the dev data, in memory and kept from the
-- roster prune, so the Recipes tab shows enchants without a real enchanter. Gone after a version change or /psd clean.
function DevProbe.AddFakeEnchanter()
    -- the same name form as everyone else's: "Fake Enchanter-<my realm>", or "Fake Enchanter" when the client knows no
    -- realm (WoW Forever names are realm-free; GetNormalizedRealmName can return nothing there). Before 1.0.0 this
    -- refused with "my own name is not known yet" whenever my stored name had no realm part.
    local fakeName = addon.Utility.CanonicalName("Fake Enchanter") or "Fake Enchanter"
    local knownRecipes, catalogEntries = {}, {}
    for recipeID, recipeName in pairs(FAKE_ENCHANTS) do
        knownRecipes[recipeID] = true
        catalogEntries[recipeID] = { name = recipeName, loc = "enUS", icon = 135913, reagents = {} }
    end
    addon.Store.PutCatalog(catalogEntries)
    addon.Store.keptNames[fakeName] = true
    local added = addon.Store.PutCharacter({ name = fakeName, class = "MAGE", level = 60, rev = addon.Utility.Now(),
        professions = { Enchanting = { id = 333, name = "Enchanting", rank = 150, max = 150, recipes = knownRecipes } } })
    addon.Log.Information("devProbe.fakeEnchanter", "a fake enchanter was added for the enchant text test",
        { name = fakeName, recipes = addon.Utility.Count(knownRecipes), added = added })
    addon.Events.Fire("DATA_CHANGED", "chars")
    addon.Print(("fake enchanter added: %d enchants. Recipes tab -> Profession: Enchanting, hover the icons (twice), then /reload to write the log.")
        :format(addon.Utility.Count(knownRecipes)))
end

if addon.IS_DEVELOPMENT_BUILD then
    addon.SlashCommands.fakeenchanter = function() DevProbe.AddFakeEnchanter() end
    addon.SlashCommands.itemprobe = function(arguments)
        local extraItemIDs = {}
        for itemIDText in tostring(arguments or ""):gmatch("%d+") do extraItemIDs[#extraItemIDs + 1] = tonumber(itemIDText) end
        DevProbe.Run(extraItemIDs)
    end
end
