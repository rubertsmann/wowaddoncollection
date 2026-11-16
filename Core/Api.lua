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

-- My base name as the server uses it: "First" on normal clients, "First Surname" on Forever, where UnitName("player")
-- returns the surname as its second value (retail returns nil there for the player).
function Api.MyBaseName()
    local first, second = UnitName("player")
    if type(second) == "string" and second ~= "" and not ns.Util.IsRealmSpelling(second) then
        local base = first .. " " .. second
        ns.Util.NoteMyFullName(base)
        return base
    end
    return first
end

function Api.GetPlayerInfo()
    local _, class = UnitClass("player")
    return { name = ns.Util.Canon(Api.MyBaseName()), class = class, level = UnitLevel("player") }
end

function Api.RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end

-- set of canonical "Name-Realm" for everyone in the guild (empty if the roster is not loaded yet). The roster's spelling
-- of MY character teaches Util which realm string the server uses for my realm (Util.LearnFromRoster), before any name
-- is canonicalized.
function Api.GetGuildRoster()
    local set, raw = {}, {}
    if not Api.IsGuilded() or not GetNumGuildMembers then return set end
    for i = 1, (GetNumGuildMembers()) do
        local name = GetGuildRosterInfo(i)
        if type(name) == "string" and name ~= "" then raw[#raw + 1] = name end
    end
    ns.Util.LearnFromRoster(raw, Api.MyBaseName())
    ns.Util.SetRosterNames(raw)
    for _, name in ipairs(raw) do
        local c = ns.Util.Canon(name)
        if c then set[c] = true end
    end
    return set
end

-- Raw identity facts for the diagnostic report (feature 008): every source of "my name" and of the roster's names, so a
-- mismatch between them (realm suffix form) can be seen without guessing. Values are what the client returned, untouched.
function Api.IdentityInfo()
    local info = {}
    info.unitName, info.unitRealm = try(UnitName, "player")
    if UnitFullName then
        local n, r = try(UnitFullName, "player")
        info.unitFullName = tostring(n) .. " / " .. tostring(r)
    end
    info.realmName = GetRealmName and try(GetRealmName)
    info.normalizedRealm = GetNormalizedRealmName and try(GetNormalizedRealmName)
    info.guild = GetGuildInfo and try(GetGuildInfo, "player")
    local full = ns.Util.Canon(Api.MyBaseName())
    info.base = Api.MyBaseName()
    info.built = full
    info.ambiguated = Ambiguate and full and try(Ambiguate, full, "none")
    local sample, mine = {}, nil
    if Api.IsGuilded() and GetNumGuildMembers then
        local n = try(GetNumGuildMembers) or 0
        info.rosterCount = n
        for i = 1, n do
            local name = try(GetGuildRosterInfo, i)
            if name then
                if #sample < 8 then sample[#sample + 1] = name end   -- the raw form the client reports
                local part = name:match("^([^-]+)") or name
                if info.base and (part == info.base or part == info.unitName) then mine = name end
            end
        end
    end
    info.rosterSample = sample
    info.rosterMe = mine   -- how the roster spells MY name
    if GetBuildInfo then
        local v, b, _, iface = try(GetBuildInfo)
        info.build = ("%s (%s) interface %s"):format(tostring(v), tostring(b), tostring(iface))
    end
    return info
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

------------------------------------------------------------------ recipe items (feature 007: Offers)

-- Which windows are open right now. Set by Events.lua (bank, mail, guild bank and auction house contents are only
-- readable while their window is open); a location that is not open is not scanned and keeps its last known state.
Api.open = { bank = false, mail = false, gbank = false, auction = false, tradeskill = false }

-- class id, subclass id, icon of an item WITHOUT loading it (nil when the client does not know the id).
function Api.ItemClass(itemID)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return nil end
    local ok, _, _, _, _, icon, classID, subClassID = pcall(fn, itemID)
    if ok and type(classID) == "number" then return classID, subClassID, icon end
    return nil
end

local function itemIDOf(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- A recipe item that can be handed to someone: class Recipe, not soulbound. Adds it to `set` (itemID -> total count).
Api.scanStats = { items = 0, recipes = 0, bound = 0, unknownClass = 0 }   -- of the last ScanItems (for /ts offers)
local function addRecipe(set, itemID, count, bound)
    local st = Api.scanStats
    if not itemID then return end
    st.items = st.items + 1
    local class = Api.ItemClass(itemID)
    if class == nil then st.unknownClass = st.unknownClass + 1 end
    if class ~= ns.Offers.RECIPE_CLASS then return end
    st.recipes = st.recipes + 1
    if bound then st.bound = st.bound + 1 return end
    set[itemID] = (set[itemID] or 0) + math.max(1, tonumber(count) or 1)
end

local function containerSlots(bag)
    local fn = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    return fn and (try(fn, bag) or 0) or 0
end

-- itemID, count, isBound for one container slot (modern C_Container table, or the legacy multi-value API)
local function containerItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = try(C_Container.GetContainerItemInfo, bag, slot)
        if type(info) == "table" then return info.itemID or itemIDOf(info.hyperlink), info.stackCount, info.isBound end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, id, bound = try(GetContainerItemInfo, bag, slot)
        return id or itemIDOf(link), count, bound
    end
end

local function scanContainers(bags)
    local set, readable = {}, false
    for _, bag in ipairs(bags) do
        local n = containerSlots(bag)
        if n > 0 then readable = true end
        for slot = 1, n do
            local id, count, bound = containerItem(bag, slot)
            addRecipe(set, id, count, bound)
        end
    end
    return readable and set or nil
end

local function scanMail()
    if not (GetInboxNumItems and GetInboxItem) then return nil end
    local set = {}
    local n = try(GetInboxNumItems) or 0
    for mail = 1, n do
        for att = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local name, id, _, count = try(GetInboxItem, mail, att)
            if name or id then
                local link = GetInboxItemLink and try(GetInboxItemLink, mail, att)
                addRecipe(set, itemIDOf(link) or (type(id) == "number" and id) or nil, count, false)   -- mailed items are tradeable
            end
        end
    end
    return set
end

local function scanGuildBank()
    if not (GetCurrentGuildBankTab and GetGuildBankItemLink) then return nil end
    local tab = try(GetCurrentGuildBankTab)
    if not ns.Util.SafeInt(tab, 1, 8) then return nil end
    local set = {}
    for slot = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
        local link = try(GetGuildBankItemLink, tab, slot)
        if link then
            local _, count = try(GetGuildBankItemInfo, tab, slot)
            addRecipe(set, itemIDOf(link), count, false)   -- the guild bank cannot hold soulbound items
        end
    end
    return set, "gbank" .. tab
end

-- own auctions: modern C_AuctionHouse, or the classic "owner" list
local function scanAuctions()
    local set = {}
    if C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions then
        local n = try(C_AuctionHouse.GetNumOwnedAuctions) or 0
        for i = 1, n do
            local info = try(C_AuctionHouse.GetOwnedAuctionInfo, i)
            if type(info) == "table" then
                local key = info.itemKey
                addRecipe(set, (type(key) == "table" and key.itemID) or itemIDOf(info.itemLink), info.quantity, false)
            end
        end
        return set
    end
    if GetNumAuctionItems and GetAuctionItemLink then
        local n = try(GetNumAuctionItems, "owner") or 0
        for i = 1, n do
            local link = try(GetAuctionItemLink, "owner", i)
            local _, _, count = try(GetAuctionItemInfo, "owner", i)
            addRecipe(set, itemIDOf(link), count, false)
        end
        return set
    end
    return nil
end

-- Returns { [loc] = { [itemID] = count } } for every location that can be read right now (see Offers.lua for the keys).
-- A location that cannot be read (window closed, API missing) is simply absent, so its old state is kept.
function Api.ScanItems()
    local out = {}
    Api.scanStats = { items = 0, recipes = 0, bound = 0, unknownClass = 0 }
    local nbag = NUM_BAG_SLOTS or 4
    local bags = {}
    for b = 0, nbag do bags[#bags + 1] = b end
    out.bag = scanContainers(bags)
    if Api.open.bank then
        local bank = { BANK_CONTAINER or -1 }
        for b = nbag + 1, nbag + (NUM_BANKBAGSLOTS or 7) do bank[#bank + 1] = b end
        out.bank = scanContainers(bank)
        out.reagent = scanContainers({ REAGENTBANK_CONTAINER or -3 })
    end
    if Api.open.mail then out.mail = scanMail() end
    if Api.open.gbank then
        local set, loc = scanGuildBank()
        if set then out[loc] = set end
    end
    if Api.open.auction then out.auction = scanAuctions() end
    return out
end

------------------------------------------------------------------ craft and whisper from lists (feature 009)

local function isLink(s) return type(s) == "string" and s:find("|H", 1, true) ~= nil and s:find("|h", 1, true) ~= nil end

-- A chat link for a recipe, built by THIS client: my own recipe link while the client knows it, else the crafted item's
-- link (needs the item cached; a load is requested), else nil (the caller falls back to plain "[Name]").
function Api.RecipeLink(recipeID, produces)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink then
        local ok, link = pcall(C_TradeSkillUI.GetRecipeLink, recipeID)
        if ok and isLink(link) then return link end
    end
    return Api.ItemLink(produces)
end

function Api.ItemLink(itemID)
    if type(itemID) ~= "number" then return nil end
    local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, _, link = false, nil, nil
    if fn then ok, _, link = pcall(fn, itemID) end
    if ok and isLink(link) then return link end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    return nil
end

-- Name of the profession whose window is open (nil when none). Same client, so it equals the spellbook name.
function Api.OpenProfessionName()
    if not Api.open.tradeskill then return nil end
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and type(info) == "table" and info.professionName then return info.professionName end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then
        local ok, _, name = pcall(C_TradeSkillUI.GetTradeSkillLine)
        if ok and type(name) == "string" then return name end
    end
    if GetTradeSkillLine then
        local ok, name = pcall(GetTradeSkillLine)
        if ok and type(name) == "string" then return name end
    end
    return nil
end

-- Select a recipe in the open profession window (so the game's own Create button crafts it). true if a call was made.
function Api.SelectRecipe(recipeID)
    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
        local ok, err = pcall(C_TradeSkillUI.OpenRecipe, recipeID)
        if not ok then ns.Debug.Log("craft.select", tostring(err)) end
        return ok
    end
    if C_TradeSkillUI and C_TradeSkillUI.SetRecipeItemNameFilter then   -- fallback: filter the list down to it
        local e = ns.Store.GetRecipe(recipeID)
        if e and e.name then return (pcall(C_TradeSkillUI.SetRecipeItemNameFilter, e.name)) end
    end
    return false
end

-- Craft qty of recipeID in the open profession window (must run from a hardware click). true if the call raised no error;
-- a call the client blocks still "succeeds" here (see docs/api-findings.md), so the UI also keeps the recipe selected.
function Api.CraftRecipe(recipeID, qty)
    if not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then return false, "no CraftRecipe" end
    local ok, err = pcall(C_TradeSkillUI.CraftRecipe, recipeID, qty)
    return ok, err
end

-- Is a profession window open that lists recipeID? (the window's own recipe list, so no name compare is needed)
-- The open flag comes from TRADE_SKILL_SHOW/CLOSE; the default frames are also checked (window open before a /reload).
function Api.OpenWindowHasRecipe(recipeID)
    local shown = Api.open.tradeskill
    for _, n in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
        local fr = _G[n]
        if fr and fr.IsShown and fr:IsShown() then shown = true end
    end
    if not shown or not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return false end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return false end
    for _, id in ipairs(ids) do if id == recipeID then return true end end
    return false
end
