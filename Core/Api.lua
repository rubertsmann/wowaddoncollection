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

function Api.GetLocale()
    return (GetLocale and GetLocale()) or "enUS"
end

-- Localized spell (= recipe) name from the viewer's client, or nil. Confirmed present on Forever: C_Spell.GetSpellInfo.
function Api.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = try(C_Spell.GetSpellInfo, spellID)
        if type(info) == "table" then return info.name end
        if type(info) == "string" then return info end
    end
    if GetSpellInfo then return (try(GetSpellInfo, spellID)) end
    return nil
end
if ns.Names then ns.Names.env.spellName = Api.SpellName end

-- One spellbook entry: { name, spellID, passive } or nil. The index comes from GetProfessionInfo (spellOffset + 1 ..
-- spellOffset + numSpells). Which spellbook API the client has is not known, so every known variant is tried.
function Api.SpellBookEntry(index)
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = try(C_SpellBook.GetSpellBookItemInfo, index, bank)
        if type(info) == "table" and type(info.name) == "string" then
            return { name = info.name, spellID = info.spellID, passive = info.isPassive }
        end
    end
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local name, _, id = try(C_SpellBook.GetSpellBookItemName, index, bank)
        if type(name) == "string" then return { name = name, spellID = id } end
    end
    if GetSpellBookItemName then
        local name, _, id = try(GetSpellBookItemName, index, "spell")
        if type(name) == "string" then return { name = name, spellID = id } end
    end
    if GetSpellName then
        local name = try(GetSpellName, index, "spell")
        if type(name) == "string" then return { name = name } end
    end
    return nil
end

-- Spellbook entries of a profession (for the profession buttons), never more than 3.
-- Returns the names (for the macro) and the full entries { name, spellID, passive } (for the debug log).
local function professionSpells(offset, count)
    local names, entries = {}, {}
    if type(offset) ~= "number" or type(count) ~= "number" then return names, entries end
    for i = offset + 1, offset + math.min(count, 3) do
        local e = Api.SpellBookEntry(i)
        if e then names[#names + 1] = e.name; entries[#entries + 1] = e end
    end
    return names, entries
end

-- Professions the character has, without needing a window: { {name, icon, rank, max, id, spells}, ... } or nil when
-- unsupported. id = skill line id, the 7th return of GetProfessionInfo (confirmed by the probe: Cooking 185, Skinning 393).
-- spells = names from the profession's spellbook entries (Skinning has 2 on Forever, the others 1).
function Api.GetPlayerProfessions()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local out = {}
    for i = 1, 5 do
        local idx = select(i, GetProfessions())
        if idx then
            local name, icon, rank, max, numSpells, spellOffset, skillLine = GetProfessionInfo(idx)
            if name then
                -- icon and spells are only used locally (profession buttons), they are never stored or sent
                local names, entries = professionSpells(spellOffset, numSpells)
                out[#out + 1] = { name = name, icon = icon, rank = rank or 0, max = max or 0,
                    id = type(skillLine) == "number" and skillLine > 0 and skillLine or nil,
                    numSpells = numSpells, spellOffset = spellOffset, spells = names, spellEntries = entries }
            end
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

-- NOTE: addon code must NOT open professions itself. C_TradeSkillUI.OpenTradeSkill is blocked for addons on Forever
-- (in game it opened nothing and showed "Interface-Aktion auf Grund eines Addons fehlgeschlagen"). Professions are
-- opened by a real click on a secure button (UI/Window.lua profession buttons, same as the macro /cast <profession>).
function Api.InCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

-- The profession whose window is open: { name, rank, max, recipes = { {recipeID,name,icon,produces,reagents} } } or nil.
-- The window reports the profession's name; its skill line id is looked up among my own professions by that name
-- (same client, same language, so the names are identical).
local function withId(res)
    if res and not res.id then
        for _, p in ipairs(Api.GetPlayerProfessions() or {}) do
            if p.name == res.name then res.id = p.id break end
        end
    end
    return res
end

function Api.GetOpenProfession()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local ok, res = pcall(modernOpen)
        if ok and res then return withId(res) end
        if not ok then ns.Debug.Log("api.modernOpen", res) end
    end
    if GetNumTradeSkills and GetTradeSkillLine then
        local ok, res = pcall(legacyOpen)
        if ok then return withId(res) end
        ns.Debug.Log("api.legacyOpen", res)
    end
    return nil
end

-- /ts i18n: what this client reports, to verify the localization assumptions in game.
ns.Slash.i18n = function()
    -- every line is printed AND written to the persistent debug log (TalentShare*.lua in SavedVariables after /reload)
    local function say(msg) ns.Print(msg); ns.Debug.Log("i18n", msg) end
    say(("client locale %s, UI locale %s"):format(Api.GetLocale(), tostring(ns.Locale and ns.Locale.code)))
    for _, p in ipairs(Api.GetPlayerProfessions() or {}) do
        say(("profession %s id=%s | static name: %s"):format(p.name, tostring(p.id),
            tostring(ns.Locale.professions[Api.GetLocale()] and ns.Locale.professions[Api.GetLocale()][p.id])))
        -- spellbook entries of this profession and the macro its button runs (why does Skinning not open a window?)
        say(("  spellOffset=%s numSpells=%s spells=[%s] macro: %s"):format(tostring(p.spellOffset), tostring(p.numSpells),
            table.concat(p.spells or {}, ", "), (ns.Model.CastMacro({ spellName = p.name, spells = p.spells }):gsub("\n", " | "))))
        for i = (p.spellOffset or 0) + 1, (p.spellOffset or 0) + math.min(p.numSpells or 0, 3) do
            local e = Api.SpellBookEntry(i)
            say(("  book[%d] = %s"):format(i, e and ("%s id=%s passive=%s"):format(e.name, tostring(e.spellID), tostring(e.passive)) or "nil (no spellbook API answered)"))
        end
    end
    say(("spellbook APIs: C_SpellBook.GetSpellBookItemInfo %s, C_SpellBook.GetSpellBookItemName %s, GetSpellBookItemName %s"):format(
        tostring(C_SpellBook and C_SpellBook.GetSpellBookItemInfo ~= nil), tostring(C_SpellBook and C_SpellBook.GetSpellBookItemName ~= nil),
        tostring(GetSpellBookItemName ~= nil)))
    local base = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and try(C_TradeSkillUI.GetBaseProfessionInfo)
    if type(base) == "table" then
        say(("open window: professionID=%s parentProfessionID=%s name=%s"):format(
            tostring(base.professionID), tostring(base.parentProfessionID), tostring(base.professionName)))
    else
        say("open window: no profession window open (open one, then run this again)")
    end
    local open = Api.GetOpenProfession()
    for i = 1, math.min(3, open and #open.recipes or 0) do
        local r = open.recipes[i]
        say(("recipe %d: window name '%s' | spell name '%s'"):format(r.recipeID, tostring(r.name), tostring(Api.SpellName(r.recipeID))))
    end
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
