local ADDON, ns = ...

-- DEV BUILD ONLY (feature 011 T1): records what this client can tell about the items our recipes make, so the
-- category filter and the effect-text search are built on facts instead of guesses. Button "Item probe" on the Debug tab,
-- or /tsd itemprobe [itemID ...]. Writes ns.db.devProbe (TalentShareDevDB); /reload flushes it to
-- WTF\Account\<ACCOUNT>\SavedVariables\TalentShare-Dev.lua. The live build never runs it (no button, no command).
-- Plain English strings on purpose: dev-only, not localized.
local Probe = {}
ns.DevProbe = Probe

local MAX_SAMPLES = 150      -- detailed item records
local PER_BUCKET = 3         -- detailed records per class/subclass/slot bucket
local WAITS = { 3, 8 }       -- seconds after the click: first collect, then a retry for items the server had not sent yet

local function fnAt(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return type(v) == "function" and v or nil
end

local APIS = {
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
local TEMPLATES = {   -- { frame type, template }: does CreateFrame accept it?
    { "Frame", "UIDropDownMenuTemplate" }, { "DropdownButton", "WowStyle1DropdownTemplate" },
    { "DropdownButton", "WowStyle1FilterDropdownTemplate" }, { "EditBox", "SearchBoxTemplate" },
    { "EditBox", "InputBoxTemplate" }, { "CheckButton", "UICheckButtonTemplate" },
}

-- readable dump of any value (strings quoted so "" and nil differ)
local function show(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return tostring(v) end
    if depth > 3 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. show(v[k], depth + 1) end
    return "{" .. table.concat(out, ", ") .. "}"
end

-- every return value of fn(...), nils included: "1=..., 2=nil, ..." or "error ..." / "missing"
local function call(fn, ...)
    if not fn then return "missing" end
    local res = { pcall(fn, ...) }
    if not res[1] then return "error " .. tostring(res[2]) end
    local n = table.maxn(res)
    if n <= 1 then return "(no values)" end
    local out = {}
    for i = 2, n do out[#out + 1] = (i - 1) .. "=" .. show(res[i]) end
    return table.concat(out, ", ")
end

local function first(fn, ...)
    if not fn then return nil end
    local res = { pcall(fn, ...) }
    if res[1] then return select(2, unpack(res, 1, table.maxn(res))) end
    return nil
end

------------------------------------------------------------------ tooltip text

local tip
local function scanTooltip(setter, arg)
    if not tip then
        local ok, t = pcall(CreateFrame, "GameTooltip", ns.FRAME .. "ProbeTip", UIParent, "GameTooltipTemplate")
        if not ok then return "error " .. tostring(t) end
        tip = t
    end
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    local ok, err = pcall(tip[setter], tip, arg)
    if not ok then return "error " .. tostring(err) end
    local lines = {}
    for i = 1, tip:NumLines() or 0 do
        local l = _G[ns.FRAME .. "ProbeTipTextLeft" .. i]
        local r = _G[ns.FRAME .. "ProbeTipTextRight" .. i]
        local lt, rt = l and l:GetText(), r and r:IsShown() and r:GetText()
        lines[#lines + 1] = (lt or "") .. ((rt and rt ~= "") and (" || " .. rt) or "")
    end
    tip:Hide()
    return lines
end

local function tooltipInfoLines(fn, arg)
    if not fn then return "missing" end
    local ok, data = pcall(fn, arg)
    if not ok then return "error " .. tostring(data) end
    if type(data) ~= "table" then return "returned " .. show(data) end
    local lines = {}
    for i, line in ipairs(data.lines or {}) do
        if line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
        lines[#lines + 1] = tostring(line.leftText or "") .. ((line.rightText and line.rightText ~= "") and (" || " .. line.rightText) or "")
        if i == 1 then lines.firstRaw = show(line) end
    end
    return lines
end

------------------------------------------------------------------ one item / one recipe without an item

local itemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local itemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local spellDesc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
local itemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local classInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local subClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo

local function request(itemID, spellID)
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    if spellID and C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
end

local function probeItem(itemID)
    local r = { itemID = itemID }
    r.instant = call(instant, itemID)
    r.info = call(itemInfo, itemID)
    r.cached = first(itemInfo, itemID) ~= nil
    local _, _, _, equipLoc, _, classID, subID = first(instant, itemID)
    r.equipLocText = equipLoc and equipLoc ~= "" and tostring(_G[equipLoc]) or nil
    if classID then
        r.className = call(classInfo, classID)
        r.subClassName = call(subClassInfo, classID, subID)
    end
    if C_Item and C_Item.GetItemInventoryTypeByID then r.invType = call(C_Item.GetItemInventoryTypeByID, itemID) end
    local link = ns.Api.ItemLink(itemID) or ("item:" .. itemID)
    r.link = link
    r.stats = call(itemStats, link)
    r.spell = call(itemSpell, itemID)
    local _, spellID = first(itemSpell, itemID)
    if spellID then
        request(nil, spellID)
        r.spellDesc = call(spellDesc, spellID)
    end
    r.tipInfo = C_TooltipInfo and tooltipInfoLines(C_TooltipInfo.GetItemByID, itemID) or "missing"
    r.tipScan = scanTooltip("SetHyperlink", "item:" .. itemID)
    return r
end

local function probeSpell(spellID)
    local r = { spellID = spellID }
    r.spellInfo = call((C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo, spellID)
    r.spellDesc = call(spellDesc, spellID)
    r.tipInfo = C_TooltipInfo and tooltipInfoLines(C_TooltipInfo.GetSpellByID, spellID) or "missing"
    r.tipScanSpell = scanTooltip("SetHyperlink", "spell:" .. spellID)
    r.tipScanEnchant = scanTooltip("SetHyperlink", "enchant:" .. spellID)
    return r
end

------------------------------------------------------------------ open profession window: its own categories/filters

local function probeTradeSkill()
    local t = {}
    t.openProfession = tostring(ns.Api.OpenProfessionName and ns.Api.OpenProfessionName())
    if GetTradeSkillSubClasses then t.subClasses = call(GetTradeSkillSubClasses) end
    if GetTradeSkillInvSlots then t.invSlots = call(GetTradeSkillInvSlots) end
    if GetNumTradeSkills then
        local headers = {}
        for i = 1, math.min(400, first(GetNumTradeSkills) or 0) do
            local name, kind = first(GetTradeSkillInfo, i)
            if kind == "header" or kind == "subheader" then headers[#headers + 1] = tostring(name) .. " (" .. kind .. ")" end
        end
        t.legacyHeaders = headers
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetCategories then
        local cats = {}
        local ok, ids = pcall(function() return { C_TradeSkillUI.GetCategories() } end)
        if ok then
            for _, id in ipairs(ids) do
                cats[#cats + 1] = tostring(id) .. ": " .. call(C_TradeSkillUI.GetCategoryInfo, id)
                if #cats >= 60 then break end
            end
        end
        t.categories = cats
    end
    return t
end

------------------------------------------------------------------ run

local running = false

local function bucketOf(itemID)
    if not itemID then return "no item (enchant or unknown)" end
    local _, _, _, equipLoc, _, classID, subID = first(instant, itemID)
    if not classID then return "unknown to this client" end
    return tostring(classID) .. ":" .. tostring(subID) .. ":" .. tostring(equipLoc ~= "" and equipLoc or "-")
end

local function collect(out, plan)
    out.items, out.spells = {}, {}
    for _, p in ipairs(plan) do
        if p.itemID then
            local r = probeItem(p.itemID)
            r.recipeID, r.recipe, r.bucket = p.recipeID, p.recipe, p.bucket
            out.items[#out.items + 1] = r
        else
            local r = probeSpell(p.recipeID)
            r.recipe, r.bucket = p.recipe, p.bucket
            out.spells[#out.spells + 1] = r
        end
    end
    local missing = 0
    for _, r in ipairs(out.items) do if not r.cached then missing = missing + 1 end end
    out.notCached = missing
    return missing
end

function Probe.Run(extra)
    if not ns.IS_DEV then return end
    if running then ns.Print("item probe already running"); return end
    running = true
    local out = { at = date and date("%Y-%m-%d %H:%M:%S"), locale = GetLocale and GetLocale(), version = ns.VERSION,
        build = call(GetBuildInfo), apis = {}, templates = {}, buckets = {} }
    for _, p in ipairs(APIS) do out.apis[p] = fnAt(p) ~= nil end
    for _, t in ipairs(TEMPLATES) do
        local ok, err = pcall(CreateFrame, t[1], nil, nil, t[2])
        out.templates[t[1] .. "/" .. t[2]] = ok and true or tostring(err)
    end
    -- profession-window data is kept per profession across runs: click once with each profession window open
    local prev = type(ns.db.devProbe) == "table" and type(ns.db.devProbe.tradeskill) == "table" and ns.db.devProbe.tradeskill or {}
    local ts = probeTradeSkill()
    if ts.openProfession ~= "nil" then prev[ts.openProfession] = ts end
    out.tradeskill = prev

    -- every catalog recipe into a bucket; a few per bucket get a detailed record
    local ids = {}
    for id in pairs(ns.db.catalog or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local plan, perBucket = {}, {}
    for _, id in ipairs(ids) do
        local e = ns.db.catalog[id]
        local b = bucketOf(e.produces)
        local s = out.buckets[b]
        if not s then s = { n = 0, examples = {} }; out.buckets[b] = s end
        s.n = s.n + 1
        if #s.examples < 5 then s.examples[#s.examples + 1] = tostring(e.name) end
        perBucket[b] = (perBucket[b] or 0) + 1
        if perBucket[b] <= PER_BUCKET and #plan < MAX_SAMPLES then
            plan[#plan + 1] = { itemID = e.produces, recipeID = id, recipe = e.name, bucket = b }
            request(e.produces, e.produces and nil or id)
        end
    end
    for _, id in ipairs(extra or {}) do
        plan[#plan + 1] = { itemID = id, recipe = "(asked for)", bucket = bucketOf(id) }
        request(id)
    end
    out.catalogSize, out.sampled = #ids, #plan
    ns.db.devProbe = out
    ns.Print(("item probe: %d recipes in %d buckets, %d sampled; collecting in %ds..."):format(#ids,
        (function() local n = 0; for _ in pairs(out.buckets) do n = n + 1 end; return n end)(), #plan, WAITS[1]))

    local function pass(i)
        local missing = collect(out, plan)
        out.pass = i
        if i < #WAITS and missing > 0 then
            ns.Print(("item probe: %d items not cached yet, retrying in %ds"):format(missing, WAITS[i + 1] - WAITS[i]))
            C_Timer.After(WAITS[i + 1] - WAITS[i], function() pass(i + 1) end)
            return
        end
        running = false
        ns.Print(("item probe done: %d items, %d without item, %d not cached. /reload to write the file."):format(
            #out.items, #out.spells, missing))
    end
    C_Timer.After(WAITS[1], function() pass(1) end)
end

if ns.IS_DEV then
    ns.Slash.itemprobe = function(arg)
        local extra = {}
        for n in tostring(arg or ""):gmatch("%d+") do extra[#extra + 1] = tonumber(n) end
        Probe.Run(extra)
    end
end
