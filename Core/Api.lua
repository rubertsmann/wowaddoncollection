local ADDON, ns = ...

-- The ONLY file that calls profession / guild WoW APIs. Supports the modern C_TradeSkillUI API and the
-- legacy GetTradeSkill* API, whichever the client has (Forever's exact shape is confirmed by dev/TalentShareProbe).
local Api = {}
ns.Api = Api

local function try(fn, ...)
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
    return nil
end

function Api.IsGuilded()
    return (IsInGuild and IsInGuild()) and true or false
end

function Api.GetPlayerInfo()
    local _, class = UnitClass("player")
    return { name = ns.Util.FullName((UnitName("player"))), class = class, level = UnitLevel("player") }
end

function Api.RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end

-- set of "Name-Realm" for everyone in the guild (empty if the roster is not loaded yet)
function Api.GetGuildRoster()
    local set = {}
    if not Api.IsGuilded() or not GetNumGuildMembers then return set end
    for i = 1, (GetNumGuildMembers()) do
        local name = GetGuildRosterInfo(i)
        if name then set[ns.Util.FullName(name)] = true end
    end
    return set
end

-- Professions the character has, without needing a window: { {name, rank, max}, ... } or nil when unsupported.
function Api.GetPlayerProfessions()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local out = {}
    for i = 1, 5 do
        local idx = select(i, GetProfessions())
        if idx then
            local name, _, rank, max = GetProfessionInfo(idx)
            if name then out[#out + 1] = { name = name, rank = rank or 0, max = max or 0 } end
        end
    end
    return out
end

local function itemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function modernOpen()
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if type(ids) ~= "table" then return nil end
    local lineID, lineName, rank, max, _, parentID, parentName
    if C_TradeSkillUI.GetTradeSkillLine then
        lineID, lineName, rank, max, _, parentID, parentName = C_TradeSkillUI.GetTradeSkillLine()
    end
    local name = parentName or lineName
    if (not name or name == "") and C_TradeSkillUI.GetBaseProfessionInfo then
        local base = C_TradeSkillUI.GetBaseProfessionInfo()
        if type(base) == "table" then
            name = base.parentProfessionName or base.professionName
            rank, max = rank or base.skillLevel, max or base.maxSkillLevel
        end
    end
    if not name or name == "" then return nil end
    local recipes = {}
    for _, id in ipairs(ids) do
        local info = try(C_TradeSkillUI.GetRecipeInfo, id)
        if info and info.learned then
            local entry = { recipeID = id, name = info.name, icon = info.icon, reagents = {} }
            local schem = C_TradeSkillUI.GetRecipeSchematic and try(C_TradeSkillUI.GetRecipeSchematic, id, false)
            if schem then
                entry.produces = schem.outputItemID
                for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
                    local r1 = slot.reagents and slot.reagents[1]
                    if r1 and r1.itemID and (slot.quantityRequired or 0) > 0 then
                        entry.reagents[#entry.reagents + 1] = { itemID = r1.itemID, count = slot.quantityRequired }
                    end
                end
            end
            recipes[#recipes + 1] = entry
        end
    end
    return { name = name, rank = rank or 0, max = max or 0, recipes = recipes }
end

local function legacyOpen()
    local name, rank, max = GetTradeSkillLine()
    if not name or name == "" or name == "UNKNOWN" then return nil end
    local recipes = {}
    for i = 1, (GetNumTradeSkills() or 0) do
        local rname, rtype = GetTradeSkillInfo(i)
        if rname and rtype ~= "header" then
            local link = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
            local id = link and tonumber(link:match("|H%a+:(%d+)"))
            if id then
                local entry = { recipeID = id, name = rname, reagents = {} }
                entry.icon = GetTradeSkillIcon and GetTradeSkillIcon(i)
                entry.produces = GetTradeSkillItemLink and itemIDFromLink(GetTradeSkillItemLink(i))
                for j = 1, (GetTradeSkillNumReagents(i) or 0) do
                    local reagentName, _, count = GetTradeSkillReagentInfo(i, j)
                    local itemID = itemIDFromLink(GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j))
                    if itemID then
                        entry.reagents[#entry.reagents + 1] = { itemID = itemID, count = count or 1, name = reagentName }
                    end
                end
                recipes[#recipes + 1] = entry
            end
        end
    end
    return { name = name, rank = rank or 0, max = max or 0, recipes = recipes }
end

-- The profession whose window is open: { name, rank, max, recipes = { {recipeID,name,icon,produces,reagents} } } or nil.
function Api.GetOpenProfession()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local ok, res = pcall(modernOpen)
        if ok and res then return res end
        if not ok then ns.Debug.Log("api.modernOpen", res) end
    end
    if GetNumTradeSkills and GetTradeSkillLine then
        local ok, res = pcall(legacyOpen)
        if ok then return res end
        ns.Debug.Log("api.legacyOpen", res)
    end
    return nil
end

-- Item helpers used by the UI (all tolerate missing APIs / uncached items).
function Api.ItemName(itemID)
    local n
    if C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(itemID) end
    if not n and C_Item and C_Item.GetItemInfo then n = (C_Item.GetItemInfo(itemID)) end
    if not n and GetItemInfo then n = (GetItemInfo(itemID)) end
    if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return n
end

function Api.ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    if GetItemIcon then return GetItemIcon(itemID) end
end

function Api.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, true) or 0 end
    if GetItemCount then return GetItemCount(itemID, true) or 0 end
    return 0
end
