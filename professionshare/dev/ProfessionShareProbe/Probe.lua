-- Dev probe. Usage in game: /psp   (records APIs; with a profession window open also records sample recipe data), then /reload.
-- Results land in WTF\Account\<ACCOUNT>\SavedVariables\ProfessionShareProbeDB.lua
local function exists(path)
    local v = _G
    for part in path:gmatch("[^.]+") do
        if type(v) ~= "table" then return false end
        v = v[part]
    end
    return type(v) == "function"
end

local APIS = {
    "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetRecipeSchematic",
    "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetTradeSkillLine", "C_TradeSkillUI.GetTradeSkillLineInfoByID",
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine", "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo",
    "GetTradeSkillReagentItemLink", "GetTradeSkillRecipeLink", "GetTradeSkillItemLink", "GetTradeSkillIcon",
    "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
    "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessage", "C_ChatInfo.IsAddonMessagePrefixRegistered",
    "C_GuildInfo.GuildRoster", "GuildRoster", "GetNumGuildMembers", "GetGuildRosterInfo", "IsInGuild",
    "C_Spell.GetSpellInfo", "C_Item.GetItemInfo", "C_Item.GetItemNameByID", "C_Item.GetItemIconByID", "C_Item.GetItemCount",
    "C_Item.RequestLoadItemDataByID", "GetItemInfo", "GetItemCount", "GetServerTime", "GetNormalizedRealmName",
    "C_Timer.After", "C_Timer.NewTicker", "ChatFrame_SendTell",
}

local function tostr(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return tostring(v) end
    if depth > 2 then return "{...}" end
    local out = {}
    for k, x in pairs(v) do out[#out + 1] = tostring(k) .. "=" .. tostr(x, depth + 1) end
    table.sort(out)
    return "{" .. table.concat(out, ", ") .. "}"
end

local function run()
    local db = {}
    ProfessionShareProbeDB = db
    db.build = { GetBuildInfo() }
    db.apis = {}
    for _, p in ipairs(APIS) do db.apis[p] = exists(p) end
    db.events = db.events or {}
    db.samples = {}
    if db.apis["C_TradeSkillUI.GetAllRecipeIDs"] then
        local ids = C_TradeSkillUI.GetAllRecipeIDs()
        db.samples.recipeIDCount = ids and #ids
        for i = 1, math.min(5, ids and #ids or 0) do
            local id = ids[i]
            local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
            db.samples["recipeInfo" .. i] = ok and tostr(info) or ("error " .. tostring(info))
            if db.apis["C_TradeSkillUI.GetRecipeSchematic"] then
                local ok2, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
                db.samples["schematic" .. i] = ok2 and tostr(sch) or ("error " .. tostring(sch))
            end
        end
        if C_TradeSkillUI.GetTradeSkillLine then db.samples.line = tostr({ C_TradeSkillUI.GetTradeSkillLine() }) end
    end
    if db.apis.GetNumTradeSkills then
        db.samples.legacyCount = GetNumTradeSkills()
        db.samples.legacyLine = tostr({ GetTradeSkillLine and GetTradeSkillLine() })
        for i = 1, math.min(6, GetNumTradeSkills() or 0) do
            db.samples["legacy" .. i] = tostr({ GetTradeSkillInfo(i) }) .. " link=" .. tostring(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
        end
    end
    if db.apis.GetProfessions then
        local t = {}
        for i = 1, 5 do
            local idx = select(i, GetProfessions())
            if idx then t[#t + 1] = tostr({ GetProfessionInfo(idx) }) end
        end
        db.samples.professions = t
    end
    print("|cff33ccffProfessionShareProbe|r recorded " .. #APIS .. " API checks. /reload to flush SavedVariables.")
end

local EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "SKILL_LINES_CHANGED",
    "CHAT_MSG_SKILL", "PLAYER_LEVEL_UP", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "TRADE_SKILL_CLOSE" }
local f = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event)
    ProfessionShareProbeDB = ProfessionShareProbeDB or {}
    if event == "PLAYER_LOGIN" then return end
    local ev = ProfessionShareProbeDB.events or {}
    ProfessionShareProbeDB.events = ev
    ev[event] = (ev[event] or 0) + 1
end)

SLASH_PROFESSIONSHAREPROBE1 = "/psp"
SlashCmdList["PROFESSIONSHAREPROBE"] = run
