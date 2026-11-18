local addonName, addon = ...

-- The ONLY file that calls profession / guild / item WoW APIs. Supports the modern C_TradeSkillUI API and the legacy
-- GetTradeSkill* API, whichever the client has (Forever's exact shape is confirmed by dev/TalentShareProbe).
-- Client functions differ between game versions, so most calls are made through tryCall: a call that fails (missing or
-- changed API) returns nil and leaves a DEBUG log line naming the call, instead of breaking the caller.
---@class ApiModule
local Api = {}
addon.Api = Api

-- pcall(func, ...) returning func's results, or nil when it raised an error (logged at DEBUG with `callName`).
---@param callName string the client function, for the log
---@param func function|nil
---@param ... any
---@return any ...
local function tryCall(callName, func, ...)
    if type(func) ~= "function" then return nil end
    local results = { pcall(func, ...) }
    if results[1] then return unpack(results, 2, table.maxn(results)) end
    addon.Log.Debug("api.call", "a client function raised an error", { call = callName, error = tostring(results[2]) })
    return nil
end

------------------------------------------------------------------ guild and identity (LibGuildSync-1.0 Guild)
-- The roster and "my name" calls are shared with every addon that embeds LibGuildSync (LibGuildSync/Guild.lua): my base
-- name ("First Surname" on Forever), the canonical roster set (it teaches Utility my realm spelling), the identity facts.
local Guild = LibStub("LibGuildSync-1.0").Guild

---@return boolean
function Api.IsGuilded() return Guild.IsGuilded() end

---@return string|nil
function Api.MyBaseName() return Guild.MyBaseName() end

---@return PlayerInformation
function Api.GetPlayerInformation() return Guild.GetPlayerInformation() end

function Api.RequestRoster() return Guild.RequestRoster() end

---@return table<string, boolean>
function Api.GetGuildRoster() return Guild.GetGuildRoster() end

---@return table
function Api.IdentityInformation() return Guild.IdentityInformation() end

---@return string
function Api.GetLocale()
    return (GetLocale and GetLocale()) or "enUS"
end

-- Localized spell (= recipe) name from the viewer's client, or nil. Confirmed present on Forever: C_Spell.GetSpellInfo.
---@param spellID integer
---@return string|nil
function Api.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local spellInformation = tryCall("C_Spell.GetSpellInfo", C_Spell.GetSpellInfo, spellID)
        if type(spellInformation) == "table" then return spellInformation.name end
        if type(spellInformation) == "string" then return spellInformation end
    end
    if GetSpellInfo then return (tryCall("GetSpellInfo", GetSpellInfo, spellID)) end
    return nil
end
addon.Names.environment.spellName = Api.SpellName

---@class SpellBookEntry
---@field name string
---@field spellID? integer
---@field passive? boolean

-- One spellbook entry or nil. The index comes from GetProfessionInfo (spellOffset + 1 .. spellOffset + spellCount).
-- Which spellbook API the client has is not known, so every known variant is tried.
---@param spellBookIndex integer
---@return SpellBookEntry|nil
function Api.SpellBookEntry(spellBookIndex)
    local spellBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local itemInformation = tryCall("C_SpellBook.GetSpellBookItemInfo", C_SpellBook.GetSpellBookItemInfo, spellBookIndex, spellBank)
        if type(itemInformation) == "table" and type(itemInformation.name) == "string" then
            return { name = itemInformation.name, spellID = itemInformation.spellID, passive = itemInformation.isPassive }
        end
    end
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local spellName, _, spellID = tryCall("C_SpellBook.GetSpellBookItemName", C_SpellBook.GetSpellBookItemName, spellBookIndex, spellBank)
        if type(spellName) == "string" then return { name = spellName, spellID = spellID } end
    end
    if GetSpellBookItemName then
        local spellName, _, spellID = tryCall("GetSpellBookItemName", GetSpellBookItemName, spellBookIndex, "spell")
        if type(spellName) == "string" then return { name = spellName, spellID = spellID } end
    end
    if GetSpellName then
        local spellName = tryCall("GetSpellName", GetSpellName, spellBookIndex, "spell")
        if type(spellName) == "string" then return { name = spellName } end
    end
    return nil
end

-- Spellbook entries of a profession (for the profession buttons), never more than 3.
-- Returns the names (for the macro) and the full entries (for the log).
---@param spellOffset any
---@param spellCount any
---@return string[] names
---@return SpellBookEntry[] entries
local function professionSpells(spellOffset, spellCount)
    local spellNames, spellEntries = {}, {}
    if type(spellOffset) ~= "number" or type(spellCount) ~= "number" then return spellNames, spellEntries end
    for spellBookIndex = spellOffset + 1, spellOffset + math.min(spellCount, 3) do
        local spellBookEntry = Api.SpellBookEntry(spellBookIndex)
        if spellBookEntry then
            spellNames[#spellNames + 1] = spellBookEntry.name
            spellEntries[#spellEntries + 1] = spellBookEntry
        end
    end
    return spellNames, spellEntries
end

---@class PlayerProfession
---@field name string
---@field icon any texture, local only
---@field rank integer
---@field max integer
---@field id integer|nil skill line id
---@field spellCount integer|nil
---@field spellOffset integer|nil
---@field spells string[] spellbook names (Skinning has 2 on Forever, the others 1)
---@field spellEntries SpellBookEntry[]

-- Professions the character has, without needing a window, or nil when unsupported. id = skill line id, the 7th return
-- of GetProfessionInfo (confirmed by the probe: Cooking 185, Skinning 393).
---@return PlayerProfession[]|nil
function Api.GetPlayerProfessions()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local playerProfessions = {}
    for slotIndex = 1, 5 do
        local professionIndex = select(slotIndex, GetProfessions())
        if professionIndex then
            local professionName, icon, rank, maximumRank, spellCount, spellOffset, skillLineID = GetProfessionInfo(professionIndex)
            if professionName then
                -- icon and spells are only used locally (profession buttons), they are never stored or sent
                local spellNames, spellEntries = professionSpells(spellOffset, spellCount)
                playerProfessions[#playerProfessions + 1] = { name = professionName, icon = icon, rank = rank or 0, max = maximumRank or 0,
                    id = type(skillLineID) == "number" and skillLineID > 0 and skillLineID or nil,
                    spellCount = spellCount, spellOffset = spellOffset, spells = spellNames, spellEntries = spellEntries }
            end
        end
    end
    return playerProfessions
end

-- itemID from an item hyperlink ("|Hitem:12345:...|h"); nil for anything else (including non-strings)
---@param link any
---@return integer|nil
local function itemIDOf(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

---@class OpenRecipe
---@field recipeID integer
---@field name string|nil
---@field icon any
---@field produces integer|nil
---@field reagents ReagentEntry[]

---@class OpenProfession
---@field name string
---@field id integer|nil skill line id
---@field rank integer
---@field max integer
---@field recipes OpenRecipe[]

-- the open profession through C_TradeSkillUI (throws on unexpected API shapes; GetOpenProfession catches and logs)
---@return OpenProfession|nil
local function readOpenProfessionModern()
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if type(recipeIDs) ~= "table" then return nil end
    local lineName, rank, maximumRank, parentName, _
    if C_TradeSkillUI.GetTradeSkillLine then
        _, lineName, rank, maximumRank, _, _, parentName = C_TradeSkillUI.GetTradeSkillLine()
    end
    local professionName = parentName or lineName
    if (not professionName or professionName == "") and C_TradeSkillUI.GetBaseProfessionInfo then
        local baseInformation = C_TradeSkillUI.GetBaseProfessionInfo()
        if type(baseInformation) == "table" then
            professionName = baseInformation.parentProfessionName or baseInformation.professionName
            rank, maximumRank = rank or baseInformation.skillLevel, maximumRank or baseInformation.maxSkillLevel
        end
    end
    if not professionName or professionName == "" then return nil end
    local recipes = {}
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInformation = tryCall("C_TradeSkillUI.GetRecipeInfo", C_TradeSkillUI.GetRecipeInfo, recipeID)
        if recipeInformation and recipeInformation.learned then
            local openRecipe = { recipeID = recipeID, name = recipeInformation.name, icon = recipeInformation.icon, reagents = {} }
            local schematic = C_TradeSkillUI.GetRecipeSchematic
                and tryCall("C_TradeSkillUI.GetRecipeSchematic", C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            if schematic then
                openRecipe.produces = schematic.outputItemID
                for _, reagentSlot in ipairs(schematic.reagentSlotSchematics or {}) do
                    local firstReagent = reagentSlot.reagents and reagentSlot.reagents[1]
                    if firstReagent and firstReagent.itemID and (reagentSlot.quantityRequired or 0) > 0 then
                        openRecipe.reagents[#openRecipe.reagents + 1] = { itemID = firstReagent.itemID, count = reagentSlot.quantityRequired }
                    end
                end
            end
            recipes[#recipes + 1] = openRecipe
        end
    end
    return { name = professionName, rank = rank or 0, max = maximumRank or 0, recipes = recipes }
end

-- the open profession through the legacy GetTradeSkill* API
---@return OpenProfession|nil
local function readOpenProfessionLegacy()
    local professionName, rank, maximumRank = GetTradeSkillLine()
    if not professionName or professionName == "" or professionName == "UNKNOWN" then return nil end
    local recipes = {}
    for skillIndex = 1, (GetNumTradeSkills() or 0) do
        local recipeName, skillType = GetTradeSkillInfo(skillIndex)
        if recipeName and skillType ~= "header" then
            local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(skillIndex)
            local recipeID = recipeLink and tonumber(recipeLink:match("|H%a+:(%d+)"))
            if recipeID then
                local openRecipe = { recipeID = recipeID, name = recipeName, reagents = {} }
                openRecipe.icon = GetTradeSkillIcon and GetTradeSkillIcon(skillIndex)
                openRecipe.produces = GetTradeSkillItemLink and itemIDOf(GetTradeSkillItemLink(skillIndex))
                for reagentIndex = 1, (GetTradeSkillNumReagents(skillIndex) or 0) do
                    local reagentName, _, reagentCount = GetTradeSkillReagentInfo(skillIndex, reagentIndex)
                    local reagentItemID = itemIDOf(GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(skillIndex, reagentIndex))
                    if reagentItemID then
                        openRecipe.reagents[#openRecipe.reagents + 1] = { itemID = reagentItemID, count = reagentCount or 1, name = reagentName }
                    end
                end
                recipes[#recipes + 1] = openRecipe
            end
        end
    end
    return { name = professionName, rank = rank or 0, max = maximumRank or 0, recipes = recipes }
end

-- NOTE: addon code must NOT open professions itself. C_TradeSkillUI.OpenTradeSkill is blocked for addons on Forever
-- (in game it opened nothing and showed "Interface-Aktion auf Grund eines Addons fehlgeschlagen"). Professions are
-- opened by a real click on a secure button (UI/Window.lua profession buttons, same as the macro /cast <profession>).
---@return boolean
function Api.InCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

-- The window reports the profession's name; its skill line id is looked up among my own professions by that name
-- (same client, same language, so the names are identical).
---@param openProfession OpenProfession|nil
---@return OpenProfession|nil
local function withSkillLineID(openProfession)
    if openProfession and not openProfession.id then
        for _, playerProfession in ipairs(Api.GetPlayerProfessions() or {}) do
            if playerProfession.name == openProfession.name then openProfession.id = playerProfession.id break end
        end
    end
    return openProfession
end

-- The profession whose window is open, or nil.
---@return OpenProfession|nil
function Api.GetOpenProfession()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local ok, openProfession = pcall(readOpenProfessionModern)
        if ok and openProfession then return withSkillLineID(openProfession) end
        if not ok then
            addon.Log.Exception("api.openProfession", "reading the open profession window (C_TradeSkillUI) failed", openProfession)
        end
    end
    if GetNumTradeSkills and GetTradeSkillLine then
        local ok, openProfession = pcall(readOpenProfessionLegacy)
        if ok then return withSkillLineID(openProfession) end
        addon.Log.Exception("api.openProfession", "reading the open profession window (GetTradeSkill*) failed", openProfession)
    end
    return nil
end

-- /ts i18n: what this client reports, to verify the localization assumptions in game.
addon.SlashCommands.i18n = function()
    -- every line is printed AND written to the log (TalentShare*.lua in SavedVariables after /reload)
    local function report(line) addon.Print(line); addon.Log.Information("api.i18n", line) end
    report(("client locale %s, UI locale %s"):format(Api.GetLocale(), tostring(addon.Locale.code)))
    for _, playerProfession in ipairs(Api.GetPlayerProfessions() or {}) do
        local staticNames = addon.Locale.professions[Api.GetLocale()]
        report(("profession %s id=%s | static name: %s"):format(playerProfession.name, tostring(playerProfession.id),
            tostring(staticNames and staticNames[playerProfession.id])))
        -- spellbook entries of this profession and the macro its button runs (why does Skinning not open a window?)
        report(("  spellOffset=%s spellCount=%s spells=[%s] macro: %s"):format(tostring(playerProfession.spellOffset),
            tostring(playerProfession.spellCount), table.concat(playerProfession.spells or {}, ", "),
            (addon.Model.CastMacro({ spellName = playerProfession.name, spells = playerProfession.spells }):gsub("\n", " | "))))
        local firstIndex = (playerProfession.spellOffset or 0) + 1
        for spellBookIndex = firstIndex, firstIndex - 1 + math.min(playerProfession.spellCount or 0, 3) do
            local spellBookEntry = Api.SpellBookEntry(spellBookIndex)
            report(("  book[%d] = %s"):format(spellBookIndex, spellBookEntry
                and ("%s id=%s passive=%s"):format(spellBookEntry.name, tostring(spellBookEntry.spellID), tostring(spellBookEntry.passive))
                or "nil (no spellbook API answered)"))
        end
    end
    report(("spellbook APIs: C_SpellBook.GetSpellBookItemInfo %s, C_SpellBook.GetSpellBookItemName %s, GetSpellBookItemName %s"):format(
        tostring(C_SpellBook and C_SpellBook.GetSpellBookItemInfo ~= nil), tostring(C_SpellBook and C_SpellBook.GetSpellBookItemName ~= nil),
        tostring(GetSpellBookItemName ~= nil)))
    local baseInformation = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo
        and tryCall("C_TradeSkillUI.GetBaseProfessionInfo", C_TradeSkillUI.GetBaseProfessionInfo)
    if type(baseInformation) == "table" then
        report(("open window: professionID=%s parentProfessionID=%s name=%s"):format(
            tostring(baseInformation.professionID), tostring(baseInformation.parentProfessionID), tostring(baseInformation.professionName)))
    else
        report("open window: no profession window open (open one, then run this again)")
    end
    local openProfession = Api.GetOpenProfession()
    for recipeIndex = 1, math.min(3, openProfession and #openProfession.recipes or 0) do
        local openRecipe = openProfession.recipes[recipeIndex]
        report(("recipe %d: window name '%s' | spell name '%s'"):format(openRecipe.recipeID, tostring(openRecipe.name),
            tostring(Api.SpellName(openRecipe.recipeID))))
    end
end

-- Item helpers used by the UI (all tolerate missing APIs / uncached items).
---@param itemID integer
---@return string|nil
function Api.ItemName(itemID)
    local itemName
    if C_Item and C_Item.GetItemNameByID then itemName = C_Item.GetItemNameByID(itemID) end
    if not itemName and C_Item and C_Item.GetItemInfo then itemName = (C_Item.GetItemInfo(itemID)) end
    if not itemName and GetItemInfo then itemName = (GetItemInfo(itemID)) end
    if not itemName and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return itemName
end

-- feature 011: class id, subclass id, equip slot of an item from the client's item data (no server query needed).
---@param itemID any
---@return integer|nil classID
---@return integer|nil subclassID
---@return string|nil equipLocation
function Api.ItemCategoryInformation(itemID)
    local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getItemInfoInstant or type(itemID) ~= "number" then return nil end
    local _, _, _, equipLocation, _, classID, subclassID = tryCall("GetItemInfoInstant", getItemInfoInstant, itemID)
    if type(classID) == "number" then return classID, subclassID, equipLocation end
    return nil
end

---@param classID integer
---@return string|nil
local function itemClassName(classID)
    local getItemClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
    local className = tryCall("GetItemClassInfo", getItemClassInfo, classID)
    return type(className) == "string" and className ~= "" and className or nil
end

-- Display name of a Model.CategoryKey, in the viewer's language (from the client, no locale strings needed).
---@param categoryKey any "none" | "slot:<INVTYPE>" | "class:<class>:<subclass>"
---@return string
function Api.CategoryLabel(categoryKey)
    if categoryKey == "none" then return addon.Text["No item (enchantments and others)"] end
    local equipSlot = type(categoryKey) == "string" and categoryKey:match("^slot:(.+)$")
    if equipSlot then
        local slotLabel = _G[equipSlot]
        return type(slotLabel) == "string" and slotLabel ~= "" and slotLabel or equipSlot
    end
    local classText, subclassText = tostring(categoryKey):match("^class:(%-?%d+):(%-?%d+)$")
    local classID, subclassID = tonumber(classText), tonumber(subclassText)
    if not classID then return tostring(categoryKey) end
    local getItemSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    local subclassName = tryCall("GetItemSubClassInfo", getItemSubClassInfo, classID, subclassID)
    if type(subclassName) == "string" and subclassName ~= "" then return subclassName end
    return itemClassName(classID) or tostring(categoryKey)
end

---@param groupID integer item class id, or -1 for "Other"
---@return string
function Api.CategoryGroupLabel(groupID)
    if groupID == -1 then return addon.Text["Other"] end
    return itemClassName(groupID) or tostring(groupID)
end

-- Tooltip lines of an item (left text, " " right text), or nil while the client has not loaded the item yet (a load is
-- requested; ask again later). Read on THIS client only; the text is never sent to anyone (feature 011).
---@type table|nil hidden GameTooltip used to read tooltips on clients without C_TooltipInfo
local scanningTooltip
---@param itemID any
---@return string[]|nil
function Api.ItemTooltipLines(itemID)
    if type(itemID) ~= "number" then return nil end
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo or not getItemInfo(itemID) then
        if C_Item and C_Item.RequestLoadItemDataByID then tryCall("C_Item.RequestLoadItemDataByID", C_Item.RequestLoadItemDataByID, itemID) end
        return nil
    end
    local tooltipLines = {}
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local tooltipData = tryCall("C_TooltipInfo.GetItemByID", C_TooltipInfo.GetItemByID, itemID)
        if type(tooltipData) == "table" and type(tooltipData.lines) == "table" then
            for _, tooltipLine in ipairs(tooltipData.lines) do
                local leftText, rightText = tooltipLine.leftText, tooltipLine.rightText
                tooltipLines[#tooltipLines + 1] = tostring(leftText or "")
                    .. ((type(rightText) == "string" and rightText ~= "") and (" " .. rightText) or "")
            end
            return tooltipLines
        end
    end
    if not CreateFrame then return nil end
    if not scanningTooltip then
        scanningTooltip = tryCall("CreateFrame(GameTooltip)", CreateFrame, "GameTooltip", addon.FRAME_PREFIX .. "ScanTip", UIParent,
            "GameTooltipTemplate")
        if not scanningTooltip then
            addon.Log.Warning("api.tooltip", "the hidden tooltip for reading item text could not be created; item text search is limited")
            return nil
        end
    end
    scanningTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanningTooltip:ClearLines()
    if not pcall(scanningTooltip.SetHyperlink, scanningTooltip, "item:" .. itemID) then return nil end
    for lineIndex = 1, scanningTooltip:NumLines() or 0 do
        local leftFontString = _G[addon.FRAME_PREFIX .. "ScanTipTextLeft" .. lineIndex]
        tooltipLines[#tooltipLines + 1] = leftFontString and leftFontString:GetText() or ""
    end
    scanningTooltip:Hide()
    return tooltipLines
end

-- feature 016: quality, item level and required level of an item (the Recipes table). nil while the item is not cached:
-- the load is requested and GET_ITEM_INFO_RECEIVED (ITEM_INFO) redraws the table. 0 means "none" and gives nil.
---@param itemID integer
---@return integer|nil quality
---@return integer|nil itemLevel
---@return integer|nil requiredLevel
function Api.ItemDetails(itemID)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local itemName, _, quality, itemLevel, requiredLevel = tryCall("GetItemInfo", getItemInfo, itemID)
    if not itemName then
        if C_Item and C_Item.RequestLoadItemDataByID then tryCall("RequestLoadItemDataByID", C_Item.RequestLoadItemDataByID, itemID) end
        return nil
    end
    local function positive(value) return type(value) == "number" and value > 0 and value or nil end
    return type(quality) == "number" and quality or nil, positive(itemLevel), positive(requiredLevel)
end

-- "rrggbb" of an item quality: the client's colour table when present, else the usual colours (RecipeTable)
---@param quality integer|nil
---@return string|nil
function Api.QualityHex(quality)
    if quality == nil then return nil end
    local qualityColor = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if type(qualityColor) == "table" and type(qualityColor.r) == "number" and type(qualityColor.g) == "number" and type(qualityColor.b) == "number" then
        local function byte(channel) return math.max(0, math.min(255, math.floor(channel * 255 + 0.5))) end
        return ("%02x%02x%02x"):format(byte(qualityColor.r), byte(qualityColor.g), byte(qualityColor.b))
    end
    return addon.RecipeTable.QualityHex(quality)
end

---@param itemID integer
---@return any texture
function Api.ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    if GetItemIcon then return GetItemIcon(itemID) end
end

-- how many the player holds (bags and bank)
---@param itemID integer
---@return integer
function Api.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, true) or 0 end
    if GetItemCount then return GetItemCount(itemID, true) or 0 end
    return 0
end

------------------------------------------------------------------ recipe items (feature 007: Offers)

-- Which windows are open right now. Set by Events.lua (bank, mail, guild bank and auction house contents are only
-- readable while their window is open); a location that is not open is not scanned and keeps its last known state.
---@type { bank: boolean, mail: boolean, gbank: boolean, auction: boolean, tradeskill: boolean }
Api.open = { bank = false, mail = false, gbank = false, auction = false, tradeskill = false }

-- class id, subclass id, icon of an item WITHOUT loading it (nil when the client does not know the id).
---@param itemID integer
---@return integer|nil classID
---@return integer|nil subclassID
---@return any icon
function Api.ItemClass(itemID)
    local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getItemInfoInstant then return nil end
    local _, _, _, _, icon, classID, subclassID = tryCall("GetItemInfoInstant", getItemInfoInstant, itemID)
    if type(classID) == "number" then return classID, subclassID, icon end
    return nil
end

---@class ScanStatistics
---@field items integer items looked at
---@field recipes integer recipe items among them
---@field bound integer soulbound recipe items (not offered)
---@field unknownClass integer items the client could not classify yet

---@type ScanStatistics of the last ScanItems (for /ts offers)
Api.scanStatistics = { items = 0, recipes = 0, bound = 0, unknownClass = 0 }

-- A recipe item that can be handed to someone: class Recipe, not soulbound. Adds it to `countByItem`.
---@param countByItem table<integer, integer>
---@param itemID integer|nil
---@param itemCount any
---@param isBound any
local function addRecipeItem(countByItem, itemID, itemCount, isBound)
    local statistics = Api.scanStatistics
    if not itemID then return end
    statistics.items = statistics.items + 1
    local classID = Api.ItemClass(itemID)
    if classID == nil then statistics.unknownClass = statistics.unknownClass + 1 end
    if classID ~= addon.Offers.RECIPE_CLASS then return end
    statistics.recipes = statistics.recipes + 1
    if isBound then statistics.bound = statistics.bound + 1 return end
    countByItem[itemID] = (countByItem[itemID] or 0) + math.max(1, tonumber(itemCount) or 1)
end

---@param bagID integer
---@return integer
local function containerSlotCount(bagID)
    local getContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    return getContainerNumSlots and (tryCall("GetContainerNumSlots", getContainerNumSlots, bagID) or 0) or 0
end

-- itemID, count, isBound for one container slot (modern C_Container table, or the legacy multi-value API)
---@param bagID integer
---@param slotIndex integer
---@return integer|nil itemID
---@return integer|nil itemCount
---@return boolean|nil isBound
local function containerItem(bagID, slotIndex)
    if C_Container and C_Container.GetContainerItemInfo then
        local slotInformation = tryCall("C_Container.GetContainerItemInfo", C_Container.GetContainerItemInfo, bagID, slotIndex)
        if type(slotInformation) == "table" then
            return slotInformation.itemID or itemIDOf(slotInformation.hyperlink), slotInformation.stackCount, slotInformation.isBound
        end
        return nil
    end
    if GetContainerItemInfo then
        local _, itemCount, _, _, _, _, link, _, _, itemID, isBound = tryCall("GetContainerItemInfo", GetContainerItemInfo, bagID, slotIndex)
        return itemID or itemIDOf(link), itemCount, isBound
    end
end

-- recipe items in these bags, or nil when none of them is readable
---@param bagIDs integer[]
---@return table<integer, integer>|nil
local function scanContainers(bagIDs)
    local countByItem, anyReadable = {}, false
    for _, bagID in ipairs(bagIDs) do
        local slotCount = containerSlotCount(bagID)
        if slotCount > 0 then anyReadable = true end
        for slotIndex = 1, slotCount do
            local itemID, itemCount, isBound = containerItem(bagID, slotIndex)
            addRecipeItem(countByItem, itemID, itemCount, isBound)
        end
    end
    return anyReadable and countByItem or nil
end

---@return table<integer, integer>|nil
local function scanMail()
    if not (GetInboxNumItems and GetInboxItem) then return nil end
    local countByItem = {}
    local mailCount = tryCall("GetInboxNumItems", GetInboxNumItems) or 0
    for mailIndex = 1, mailCount do
        for attachmentIndex = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local itemName, itemID, _, itemCount = tryCall("GetInboxItem", GetInboxItem, mailIndex, attachmentIndex)
            if itemName or itemID then
                local link = GetInboxItemLink and tryCall("GetInboxItemLink", GetInboxItemLink, mailIndex, attachmentIndex)
                -- mailed items are tradeable
                addRecipeItem(countByItem, itemIDOf(link) or (type(itemID) == "number" and itemID) or nil, itemCount, false)
            end
        end
    end
    return countByItem
end

---@return table<integer, integer>|nil countByItem
---@return string|nil location "gbank<tab>"
local function scanGuildBank()
    if not (GetCurrentGuildBankTab and GetGuildBankItemLink) then return nil end
    local tabIndex = tryCall("GetCurrentGuildBankTab", GetCurrentGuildBankTab)
    if not addon.Utility.SafeInteger(tabIndex, 1, 8) then return nil end
    local countByItem = {}
    for slotIndex = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
        local link = tryCall("GetGuildBankItemLink", GetGuildBankItemLink, tabIndex, slotIndex)
        if link then
            local _, itemCount = tryCall("GetGuildBankItemInfo", GetGuildBankItemInfo, tabIndex, slotIndex)
            addRecipeItem(countByItem, itemIDOf(link), itemCount, false)   -- the guild bank cannot hold soulbound items
        end
    end
    return countByItem, "gbank" .. tabIndex
end

-- own auctions: modern C_AuctionHouse, or the classic "owner" list
---@return table<integer, integer>|nil
local function scanAuctions()
    local countByItem = {}
    if C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions then
        local auctionCount = tryCall("C_AuctionHouse.GetNumOwnedAuctions", C_AuctionHouse.GetNumOwnedAuctions) or 0
        for auctionIndex = 1, auctionCount do
            local auctionInformation = tryCall("C_AuctionHouse.GetOwnedAuctionInfo", C_AuctionHouse.GetOwnedAuctionInfo, auctionIndex)
            if type(auctionInformation) == "table" then
                local itemKey = auctionInformation.itemKey
                addRecipeItem(countByItem, (type(itemKey) == "table" and itemKey.itemID) or itemIDOf(auctionInformation.itemLink),
                    auctionInformation.quantity, false)
            end
        end
        return countByItem
    end
    if GetNumAuctionItems and GetAuctionItemLink then
        local auctionCount = tryCall("GetNumAuctionItems", GetNumAuctionItems, "owner") or 0
        for auctionIndex = 1, auctionCount do
            local link = tryCall("GetAuctionItemLink", GetAuctionItemLink, "owner", auctionIndex)
            local _, _, itemCount = tryCall("GetAuctionItemInfo", GetAuctionItemInfo, "owner", auctionIndex)
            addRecipeItem(countByItem, itemIDOf(link), itemCount, false)
        end
        return countByItem
    end
    return nil
end

-- Returns { [location] = { [itemID] = count } } for every location that can be read right now (see Offers.lua for the
-- keys). A location that cannot be read (window closed, API missing) is simply absent, so its old state is kept.
---@return table<string, table<integer, integer>>
function Api.ScanItems()
    local scans = {}
    Api.scanStatistics = { items = 0, recipes = 0, bound = 0, unknownClass = 0 }
    local bagSlotCount = NUM_BAG_SLOTS or 4
    local bagIDs = {}
    for bagID = 0, bagSlotCount do bagIDs[#bagIDs + 1] = bagID end
    scans.bag = scanContainers(bagIDs)
    if Api.open.bank then
        local bankBagIDs = { BANK_CONTAINER or -1 }
        for bagID = bagSlotCount + 1, bagSlotCount + (NUM_BANKBAGSLOTS or 7) do bankBagIDs[#bankBagIDs + 1] = bagID end
        scans.bank = scanContainers(bankBagIDs)
        scans.reagent = scanContainers({ REAGENTBANK_CONTAINER or -3 })
    end
    if Api.open.mail then scans.mail = scanMail() end
    if Api.open.gbank then
        local countByItem, location = scanGuildBank()
        if countByItem then scans[location] = countByItem end
    end
    if Api.open.auction then scans.auction = scanAuctions() end
    return scans
end

------------------------------------------------------------------ craft and whisper from lists (feature 009)

---@param text any
---@return boolean
local function isHyperlink(text)
    return type(text) == "string" and text:find("|H", 1, true) ~= nil and text:find("|h", 1, true) ~= nil
end

-- A chat link for a recipe, built by THIS client: my own recipe link while the client knows it, else the crafted item's
-- link (needs the item cached; a load is requested), else nil (the caller falls back to plain "[Name]").
---@param recipeID integer
---@param producedItemID integer|nil
---@return string|nil
function Api.RecipeLink(recipeID, producedItemID)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink then
        local link = tryCall("C_TradeSkillUI.GetRecipeLink", C_TradeSkillUI.GetRecipeLink, recipeID)
        if isHyperlink(link) then return link end
    end
    return Api.ItemLink(producedItemID)
end

---@param itemID any
---@return string|nil
function Api.ItemLink(itemID)
    if type(itemID) ~= "number" then return nil end
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = tryCall("GetItemInfo", getItemInfo, itemID)
    if isHyperlink(link) then return link end
    if C_Item and C_Item.RequestLoadItemDataByID then tryCall("C_Item.RequestLoadItemDataByID", C_Item.RequestLoadItemDataByID, itemID) end
    return nil
end

-- Name of the profession whose window is open (nil when none). Same client, so it equals the spellbook name.
---@return string|nil
function Api.OpenProfessionName()
    if not Api.open.tradeskill then return nil end
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local baseInformation = tryCall("C_TradeSkillUI.GetBaseProfessionInfo", C_TradeSkillUI.GetBaseProfessionInfo)
        if type(baseInformation) == "table" and baseInformation.professionName then return baseInformation.professionName end
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then
        local _, lineName = tryCall("C_TradeSkillUI.GetTradeSkillLine", C_TradeSkillUI.GetTradeSkillLine)
        if type(lineName) == "string" then return lineName end
    end
    if GetTradeSkillLine then
        local lineName = tryCall("GetTradeSkillLine", GetTradeSkillLine)
        if type(lineName) == "string" then return lineName end
    end
    return nil
end

-- Select a recipe in the open profession window (so the game's own Create button crafts it). true if a call was made.
---@param recipeID integer
---@return boolean
function Api.SelectRecipe(recipeID)
    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
        local ok, errorMessage = pcall(C_TradeSkillUI.OpenRecipe, recipeID)
        if not ok then
            addon.Log.Error("api.selectRecipe", "selecting the recipe in the profession window failed",
                { recipeID = recipeID, error = tostring(errorMessage) })
        end
        return ok
    end
    if C_TradeSkillUI and C_TradeSkillUI.SetRecipeItemNameFilter then   -- fallback: filter the list down to it
        local catalogEntry = addon.Store.GetRecipe(recipeID)
        if catalogEntry and catalogEntry.name then
            local ok, errorMessage = pcall(C_TradeSkillUI.SetRecipeItemNameFilter, catalogEntry.name)
            if not ok then
                addon.Log.Error("api.selectRecipe", "filtering the profession window to the recipe failed",
                    { recipeID = recipeID, error = tostring(errorMessage) })
            end
            return ok
        end
    end
    return false
end

-- Craft `quantity` of recipeID in the open profession window (must run from a hardware click). true if the call raised
-- no error; a call the client blocks still "succeeds" here (see docs/api-findings.md), so the UI keeps the recipe selected.
---@param recipeID integer
---@param quantity integer
---@return boolean ok
---@return any errorMessage
function Api.CraftRecipe(recipeID, quantity)
    if not (C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) then return false, "no CraftRecipe" end
    local ok, errorMessage = pcall(C_TradeSkillUI.CraftRecipe, recipeID, quantity)
    if not ok then
        addon.Log.Error("api.craftRecipe", "the craft call raised an error", { recipeID = recipeID, quantity = quantity,
            error = tostring(errorMessage) })
    end
    return ok, errorMessage
end

-- Is a profession window open that lists recipeID? (the window's own recipe list, so no name compare is needed)
-- The open flag comes from TRADE_SKILL_SHOW/CLOSE; the default frames are also checked (window open before a /reload).
---@param recipeID integer
---@return boolean
function Api.OpenWindowHasRecipe(recipeID)
    local windowShown = Api.open.tradeskill
    for _, frameName in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
        local professionFrame = _G[frameName]
        if professionFrame and professionFrame.IsShown and professionFrame:IsShown() then windowShown = true end
    end
    if not windowShown or not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return false end
    local recipeIDs = tryCall("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI.GetAllRecipeIDs)
    if type(recipeIDs) ~= "table" then return false end
    for _, listedRecipeID in ipairs(recipeIDs) do if listedRecipeID == recipeID then return true end end
    return false
end

