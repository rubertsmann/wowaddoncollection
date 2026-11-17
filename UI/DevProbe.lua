local addonName, addon = ...

-- DEV BUILD ONLY (feature 011 T1): records what this client can tell about the items our recipes make, so the
-- category filter and the effect-text search are built on facts instead of guesses. Button "Item probe" on the Debug tab,
-- or /tsd itemprobe [itemID ...]. Writes addon.db.devProbe (TalentShareDevDB); /reload flushes it to
-- WTF\Account\<ACCOUNT>\SavedVariables\TalentShare-Dev.lua. The live build never runs it (no button, no command).
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

if addon.IS_DEVELOPMENT_BUILD then
    addon.SlashCommands.itemprobe = function(arguments)
        local extraItemIDs = {}
        for itemIDText in tostring(arguments or ""):gmatch("%d+") do extraItemIDs[#extraItemIDs + 1] = tonumber(itemIDText) end
        DevProbe.Run(extraItemIDs)
    end
end

------------------------------------------------------------------ feature 014: animation probe and game dev commands

-- /tsd anim: answers the probe questions P1-P8 of features/014-guild-game-base/evidence/animations-research.md on this
-- client. Prints one chat line per question ("anim P3: ..."); P5 and P8 also need a screenshot of the squares it shows
-- in the middle of the screen for ~10 s. Plain English on purpose (dev only).
local animationProbeRunning = false

---@param questionID string
---@param text string
local function report(questionID, text) addon.Print(("anim %s: %s"):format(questionID, text)) end

---@param label string
---@param x number offset from the screen center
---@param y number
---@param red number
---@param green number
---@param blue number
---@return table square a 40 x 40 frame with a coloured texture and a label
local function testSquare(label, x, y, red, green, blue)
    local square = CreateFrame("Frame", nil, UIParent)
    square:SetSize(40, 40); square:SetPoint("CENTER", UIParent, "CENTER", x, y); square:SetFrameStrata("DIALOG")
    square.texture = square:CreateTexture(nil, "ARTWORK"); square.texture:SetAllPoints(); square.texture:SetColorTexture(red, green, blue, 0.9)
    square.label = square:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); square.label:SetPoint("TOP", square, "BOTTOM", 0, -2)
    square.label:SetText(label)
    square:EnableMouse(true)
    return square
end

---@param value number|nil
---@return string
local function rounded(value) return value and ("%.1f"):format(value) or "nil" end

---@param animation table a Scale animation
---@param fromX number
---@param fromY number
---@param toX number
---@param toY number
local function scaleFromTo(animation, fromX, fromY, toX, toY)
    if animation.SetScaleFrom then animation:SetScaleFrom(fromX, fromY); animation:SetScaleTo(toX, toY)
    else animation:SetScale(toX / fromX, toY / fromY) end
end

function DevProbe.AnimationProbe()
    if animationProbeRunning then addon.Print("anim probe: already running") return end
    animationProbeRunning = true
    local squares = {}
    local function keep(square) squares[#squares + 1] = square; return square end

    -- P1: animation types this client accepts
    local accepted, refused = {}, {}
    for _, animationType in ipairs({ "Animation", "Alpha", "Scale", "Translation", "Rotation", "Path", "ControlPoints", "FlipBook",
        "VertexColor", "TextureCoordTranslation", "LineScale", "LineTranslation" }) do
        local list = addon.Animate.Supported(animationType) and accepted or refused
        list[#list + 1] = animationType
    end
    report("P1", "accepted: " .. table.concat(accepted, ", ") .. " | refused: " .. (#refused > 0 and table.concat(refused, ", ") or "none"))

    -- P2: smoothing and looping values the setters accept
    local probeGroup = CreateFrame("Frame"):CreateAnimationGroup()
    local probeAnimation = probeGroup:CreateAnimation("Alpha")
    local smoothings, loopings = {}, {}
    for _, smoothing in ipairs({ "NONE", "IN", "OUT", "IN_OUT", "OUT_IN", "BOUNCE" }) do
        local ok = pcall(probeAnimation.SetSmoothing, probeAnimation, smoothing)
        local readBack = ok and probeAnimation.GetSmoothing and probeAnimation:GetSmoothing() or "?"
        smoothings[#smoothings + 1] = smoothing .. (ok and ("=" .. tostring(readBack)) or "=error")
    end
    for _, looping in ipairs({ "NONE", "REPEAT", "BOUNCE" }) do
        loopings[#loopings + 1] = looping .. (pcall(probeGroup.SetLooping, probeGroup, looping) and "=ok" or "=error")
    end
    report("P2", "smoothing " .. table.concat(smoothings, " ") .. " | looping " .. table.concat(loopings, " ")
        .. " | SetToFinalAlpha=" .. tostring(probeGroup.SetToFinalAlpha ~= nil)
        .. " SetAnimationSpeedMultiplier=" .. tostring(probeGroup.SetAnimationSpeedMultiplier ~= nil))

    -- P3: Translation end state (does it jump back?) and whether the hit rect moves (hover the red square while it moves)
    local moving = keep(testSquare("P3 hover me", -200, 120, 0.9, 0.2, 0.2))
    local entered = {}
    moving:SetScript("OnEnter", function() entered[#entered + 1] = ("%.2fs"):format(GetTime() - (moving.startedAt or GetTime())) end)
    local moveGroup = moving:CreateAnimationGroup()
    local move = moveGroup:CreateAnimation("Translation"); move:SetOffset(150, 0); move:SetDuration(2)
    local centerBefore = moving:GetCenter()
    local centerDuring
    moveGroup:SetScript("OnFinished", function()
        local centerAfter = moving:GetCenter()
        report("P3", ("center x before %s, during %s, after %s (same = GetCenter ignores Translation; check visually whether the square jumped back); OnEnter at %s")
            :format(rounded(centerBefore), rounded(centerDuring), rounded(centerAfter), #entered > 0 and table.concat(entered, ",") or "never"))
    end)
    C_Timer.After(1, function() centerDuring = moving:GetCenter() end)
    moving.startedAt = GetTime()
    moveGroup:Play()

    -- P4: alpha end state with and without SetToFinalAlpha, and with a parallel SetAlpha on the region
    local plain = keep(testSquare("P4 plain", -100, 120, 0.2, 0.9, 0.2))
    local final = keep(testSquare("P4 final", 0, 120, 0.2, 0.9, 0.2))
    local mixed = keep(testSquare("P4 SetAlpha", 100, 120, 0.2, 0.9, 0.2))
    local alphaResults, alphaPending = {}, 3
    for _, entry in ipairs({ { plain, "plain", false }, { final, "final", true }, { mixed, "with SetAlpha(0.5)", false } }) do
        local square, name, toFinal = entry[1], entry[2], entry[3]
        local group = square:CreateAnimationGroup()
        if toFinal and group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
        local fade = group:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0.2); fade:SetDuration(0.6)
        group:SetScript("OnFinished", function()
            alphaResults[#alphaResults + 1] = ("%s=%.2f"):format(name, square:GetAlpha())
            alphaPending = alphaPending - 1
            if alphaPending == 0 then report("P4", "GetAlpha after OnFinished (animated 1 -> 0.2): " .. table.concat(alphaResults, ", ")) end
        end)
        group:Play()
        if square == mixed then C_Timer.After(0.3, function() mixed:SetAlpha(0.5) end) end
    end

    -- P5: scale origin and text sharpness (screenshot while they pulse)
    local scaleCentered = keep(testSquare("P5 default origin", -100, -60, 0.2, 0.4, 0.9))
    local scaleCorner = keep(testSquare("P5 BOTTOMLEFT origin", 60, -60, 0.2, 0.4, 0.9))
    local hasScaleFrom, hasOrigin = false, false
    for _, square in ipairs({ scaleCentered, scaleCorner }) do
        local text = square:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); text:SetPoint("CENTER"); text:SetText("Ag 123")
        local group = square:CreateAnimationGroup(); group:SetLooping("BOUNCE")
        local grow = group:CreateAnimation("Scale"); grow:SetDuration(1.2)
        scaleFromTo(grow, 1, 1, 1.8, 1.8)
        if square == scaleCorner and grow.SetOrigin then grow:SetOrigin("BOTTOMLEFT", 0, 0) end
        hasScaleFrom, hasOrigin = grow.SetScaleFrom ~= nil, grow.SetOrigin ~= nil
        group:Play()
    end
    report("P5", ("SetScaleFrom=%s SetOrigin=%s; screenshot the two blue squares (origin and text sharpness)")
        :format(tostring(hasScaleFrom), tostring(hasOrigin)))

    -- P6: Play() again while playing, and Stop() + Play()
    local restarted = keep(testSquare("P6 restart", 200, -60, 0.9, 0.9, 0.2))
    local restartGroup = restarted:CreateAnimationGroup()
    local restartFade = restartGroup:CreateAnimation("Alpha"); restartFade:SetFromAlpha(1); restartFade:SetToAlpha(0); restartFade:SetDuration(1)
    local finishedCount = 0
    restartGroup:SetScript("OnFinished", function() finishedCount = finishedCount + 1 end)
    restartGroup:Play()
    C_Timer.After(0.5, function()
        local function progress() return restartGroup.GetProgress and restartGroup:GetProgress() or -1 end
        local progressBefore = progress()
        restartGroup:Play()
        local progressAfterPlay = progress()
        restartGroup:Stop(); restartGroup:Play()
        local progressAfterRestart = progress()
        C_Timer.After(1.5, function()
            report("P6", ("progress at 0.5s %.2f, after Play() %.2f, after Stop()+Play() %.2f, OnFinished fired %d time(s), IsPlaying %s")
                :format(progressBefore, progressAfterPlay, progressAfterRestart, finishedCount, tostring(restartGroup:IsPlaying())))
        end)
    end)

    -- P8: rotation on a Frame vs on a Texture
    local rotationResults = {}
    local rotatingFrame = keep(testSquare("P8 frame", -100, -160, 0.8, 0.4, 0.1))
    local rotatingTextureHolder = keep(testSquare("P8 texture", 60, -160, 0.8, 0.4, 0.1))
    for _, entry in ipairs({ { rotatingFrame, "frame" }, { rotatingTextureHolder.texture, "texture" } }) do
        local ok, errorMessage = pcall(function()
            local group = entry[1]:CreateAnimationGroup(); group:SetLooping("REPEAT")
            local spin = group:CreateAnimation("Rotation"); spin:SetDegrees(-360); spin:SetDuration(3)
            group:Play()
        end)
        rotationResults[#rotationResults + 1] = entry[2] .. "=" .. (ok and "ok" or tostring(errorMessage))
    end
    report("P8", table.concat(rotationResults, ", ") .. "; screenshot the two orange squares")

    -- coin and glow textures of the Games tab, and the coin sound
    local textureCheck = {}
    local checkTexture = UIParent:CreateTexture(nil, "BACKGROUND")
    for _, path in ipairs({ "Interface\\CharacterFrame\\TempPortraitAlphaMask", "Interface\\Icons\\INV_Crown_01",
        "Interface\\Icons\\INV_Misc_Head_Human_01", "Interface\\Buttons\\UI-ActionButton-Border" }) do
        local result = checkTexture:SetTexture(path)
        textureCheck[#textureCheck + 1] = path:match("[^\\]+$") .. "=" .. tostring(result) .. "/" .. tostring(checkTexture:GetTexture())
    end
    checkTexture:Hide()
    report("tex", table.concat(textureCheck, ", ") .. " | coin sound kit " .. tostring(addon.Api.CoinSoundKit()))

    -- P7: cost of 25 built-in flips vs 25 OnUpdate tweens (frame rate while each runs)
    C_Timer.After(3, function()
        local idleRate = GetFramerate()
        local tiles = {}
        for index = 1, 25 do
            local tile = keep(testSquare("", -240 + (index % 5) * 30, 260 - math.floor(index / 5) * 30, 0.5, 0.5, 0.5))
            tile:SetSize(24, 24)
            local group = tile:CreateAnimationGroup(); group:SetLooping("REPEAT")
            local shrink = group:CreateAnimation("Scale"); shrink:SetDuration(0.12); shrink:SetOrder(1); scaleFromTo(shrink, 1, 1, 0.05, 1)
            local grow = group:CreateAnimation("Scale"); grow:SetDuration(0.12); grow:SetOrder(2); scaleFromTo(grow, 0.05, 1, 1, 1)
            group:Play()
            tiles[index] = { tile = tile, group = group }
        end
        C_Timer.After(1.5, function()
            local builtInRate = GetFramerate()
            for _, entry in ipairs(tiles) do entry.group:Stop() end
            local started = debugprofilestop()
            local stepCount = 0
            for index, entry in ipairs(tiles) do
                addon.Animate.Tween("probe" .. index, 1.5, function(elapsed)
                    stepCount = stepCount + 1
                    entry.tile:SetWidth(24 * math.max(0.05, math.abs(math.cos(elapsed * 12))))
                end)
            end
            C_Timer.After(1.6, function()
                report("P7", ("fps idle %.0f, 25 AnimationGroups %.0f, 25 tweens %.0f (%d tween steps in %.0f ms)")
                    :format(idleRate, builtInRate, GetFramerate(), stepCount, debugprofilestop() - started))
            end)
        end)
    end)

    C_Timer.After(10, function()
        for _, square in ipairs(squares) do square:Hide() end
        animationProbeRunning = false
        addon.Print("anim probe: done, squares removed. Send the anim lines above (and the P5/P8 screenshots).")
    end)
end

if addon.IS_DEVELOPMENT_BUILD then
    -- /tsd anim             run the probe P1-P8
    -- /tsd anim speed 0.25  slow motion for every animation and tween (1 = normal)
    addon.SlashCommands.anim = function(arguments)
        local word, value = tostring(arguments or ""):match("^%s*(%S*)%s*(%S*)")
        if word == "speed" then
            addon.Animate.speed = math.max(0.05, math.min(4, tonumber(value) or 1))
            addon.Print(("anim speed %.2f"):format(addon.Animate.speed))
            return
        end
        addon.Log.Protected("devProbe.anim", "the animation probe failed", DevProbe.AnimationProbe)
    end
    -- /tsd game sim <n>     n fake leaderboard players (memory only: never stored, never sent); 0 removes them
    addon.SlashCommands.game = function(arguments)
        local word, value = tostring(arguments or ""):match("^%s*(%S*)%s*(%S*)")
        if word ~= "sim" then addon.Print("usage: game sim <count>") return end
        local count = addon.Games.Simulate(tonumber(value) or 0, addon.Utility.Now(), math.random)
        addon.Print(("game sim: %d simulated players (not stored, not sent)"):format(count))
        addon.Events.Fire("DATA_CHANGED", "games-local")
    end
end
