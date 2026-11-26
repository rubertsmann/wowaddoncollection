local addonName, addon = ...

-- The ONLY file that calls profession / guild / item WoW APIs. Supports the modern C_TradeSkillUI API and the legacy
-- GetTradeSkill* API, whichever the client has (Forever's exact shape is confirmed by dev/ProfessionShareProbe).
-- Client functions differ between game versions, so most calls are made through tryCall: a call that fails (missing or
-- changed API) returns nil and leaves a DEBUG log line naming the call, instead of breaking the caller.
---@class ApiModule
local Api = {}
addon.Api = Api

-- pcall(func, ...) returning func's results, or nil when it is missing or raised an error (logged at DEBUG with
-- `callName`).
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

-- Whether the last guild roster showed this canonical name online (nil: not in it). Queued whispers to an offline
-- member are dropped instead of sent ("no player named ... is online").
---@param playerName string
---@return boolean|nil
function Api.IsOnline(playerName) return Guild.IsOnline(playerName) end

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

-- /ps i18n: what this client reports, to verify the localization assumptions in game.
addon.SlashCommands.i18n = function()
    -- every line is printed AND written to the log (ProfessionShare*.lua in SavedVariables after /reload)
    local function report(line) addon.Print(line); addon.Log.Information("api.i18n", line) end
    report(("client locale %s, UI locale %s"):format(Api.GetLocale(), tostring(addon.Locale.code)))
    for _, playerProfession in ipairs(Api.GetPlayerProfessions() or {}) do
        local staticNames = addon.Locale.professions[Api.GetLocale()]
        report(("profession %s id=%s | static name: %s"):format(playerProfession.name, tostring(playerProfession.id),
            tostring(staticNames and staticNames[playerProfession.id])))
        -- spellbook entries of this profession and what its button casts
        report(("  spellOffset=%s spellCount=%s spells=[%s] button casts: %s"):format(tostring(playerProfession.spellOffset),
            tostring(playerProfession.spellCount), table.concat(playerProfession.spells or {}, ", "),
            addon.Model.DescribeOpenAction(addon.Model.OpenAction({ id = playerProfession.id, spellName = playerProfession.name }))))
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

-- class id, subclass id, equip slot of an item from the client's item data (no server query needed).
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
-- requested; ask again later). Read on THIS client only; the text is never sent to anyone.
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
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local tooltipData = tryCall("C_TooltipInfo.GetItemByID", C_TooltipInfo.GetItemByID, itemID)
        if type(tooltipData) == "table" and type(tooltipData.lines) == "table" then
            local tooltipLines = {}
            for _, tooltipLine in ipairs(tooltipData.lines) do
                local leftText, rightText = tooltipLine.leftText, tooltipLine.rightText
                tooltipLines[#tooltipLines + 1] = tostring(leftText or "")
                    .. ((type(rightText) == "string" and rightText ~= "") and (" " .. rightText) or "")
            end
            return tooltipLines
        end
    end
    return Api.HyperlinkTooltipLines("item:" .. itemID)
end

-- the lines a hidden tooltip shows for `hyperlink`, with the left text colour; nil when the client has no tooltip for it
---@param hyperlink string
---@return TooltipLine[]|nil
local function scanTooltip(hyperlink)
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
    if not pcall(scanningTooltip.SetHyperlink, scanningTooltip, hyperlink) then return nil end
    local tooltipLines = {}
    for lineIndex = 1, scanningTooltip:NumLines() or 0 do
        local leftFontString = _G[addon.FRAME_PREFIX .. "ScanTipTextLeft" .. lineIndex]
        local red, green, blue
        if leftFontString and leftFontString.GetTextColor then red, green, blue = leftFontString:GetTextColor() end
        tooltipLines[#tooltipLines + 1] = { text = leftFontString and leftFontString:GetText() or "", r = red, g = green, b = blue }
    end
    scanningTooltip:Hide()
    if #tooltipLines == 0 then return nil end
    return tooltipLines
end

-- the left text of every line a hidden tooltip shows for `hyperlink` ("item:123", "spell:123", "enchant:123");
-- nil when the client has no tooltip for it
---@param hyperlink string
---@return string[]|nil
function Api.HyperlinkTooltipLines(hyperlink)
    local coloredLines = scanTooltip(hyperlink)
    if not coloredLines then return nil end
    local tooltipLines = {}
    for _, tooltipLine in ipairs(coloredLines) do tooltipLines[#tooltipLines + 1] = tooltipLine.text end
    return tooltipLines
end

-- The effect text of a spell, for recipes that make no item (enchants). On Forever the recipe id of an enchant is its
-- classic spell id (13419 = Enchant Cloak - Minor Agility; confirmed in game). nil while the
-- client has not loaded the spell (the load is requested) or when it has no text.
---@param spellID integer
---@return string|nil
function Api.SpellDescription(spellID)
    if type(spellID) ~= "number" then return nil end
    local getSpellDescription = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    local description = tryCall("GetSpellDescription", getSpellDescription, spellID)
    if type(description) == "string" and description:find("%S") then return description end
    if C_Spell and C_Spell.RequestLoadSpellData then tryCall("C_Spell.RequestLoadSpellData", C_Spell.RequestLoadSpellData, spellID) end
    return nil
end

-- quality, item level and required level of an item (the Recipes table). nil while the item is not cached:
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

-- How many of an item are in my bags (the bank not counted).
---@param itemID integer
---@return integer
function Api.BagCount(itemID)
    local getItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
    return tonumber(getItemCount and tryCall("GetItemCount", getItemCount, itemID, false)) or 0
end

------------------------------------------------------------------ recipe items (Offers)

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

---@type ScanStatistics of the last ScanItems (for /ps offers)
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

------------------------------------------------------------------ recipe items: own tooltip and loot lines (RecipeCheck)

---@class BagRecipeItem
---@field itemID integer
---@field bound boolean
---@field bag integer
---@field slot integer

-- Every recipe item in my bags, soulbound ones included (one entry per slot).
---@return BagRecipeItem[]
function Api.BagRecipeItems()
    local recipeItems = {}
    for bagID = 0, NUM_BAG_SLOTS or 4 do
        for slotIndex = 1, containerSlotCount(bagID) do
            local itemID, _, isBound = containerItem(bagID, slotIndex)
            if itemID and Api.ItemClass(itemID) == addon.Offers.RECIPE_CLASS then
                recipeItems[#recipeItems + 1] = { itemID = itemID, bound = isBound and true or false, bag = bagID, slot = slotIndex }
            end
        end
    end
    return recipeItems
end

-- The client's own format strings RecipeCheck reads tooltips and loot lines with (the MULTIPLE forms first: the
-- single form would also match "...x2." with a wrong link).
---@return RecipeCheckStrings
function Api.RecipeCheckStrings()
    local function present(...)
        local formats = {}
        for argumentIndex = 1, select("#", ...) do   -- not ipairs: a format this client lacks is a nil in the middle
            local formatString = select(argumentIndex, ...)
            if type(formatString) == "string" then formats[#formats + 1] = formatString end
        end
        return formats
    end
    return {
        minSkill = ITEM_MIN_SKILL, known = ITEM_SPELL_KNOWN, bindOnPickup = ITEM_BIND_ON_PICKUP,
        loot = {
            self = present(LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF),
            pushed = present(LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF),
            other = present(LOOT_ITEM_MULTIPLE, LOOT_ITEM),
        },
    }
end

---@param colorObject any
---@return number|nil, number|nil, number|nil
local function colorValues(colorObject)
    if type(colorObject) ~= "table" then return nil end
    if type(colorObject.GetRGB) == "function" then
        local ok, red, green, blue = pcall(colorObject.GetRGB, colorObject)
        if ok then return red, green, blue end
    end
    return colorObject.r, colorObject.g, colorObject.b
end

-- Tooltip lines of an item for THIS character with the left text colour ({ text, r, g, b }), or nil while the client has
-- not loaded the item (a load is requested; ask again later). Read on this client only; nothing of it is sent.
---@param itemID any
---@return TooltipLine[]|nil
function Api.ItemTooltipLinesWithColor(itemID)
    if type(itemID) ~= "number" then return nil end
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getItemInfo or not tryCall("GetItemInfo", getItemInfo, itemID) then
        if C_Item and C_Item.RequestLoadItemDataByID then tryCall("C_Item.RequestLoadItemDataByID", C_Item.RequestLoadItemDataByID, itemID) end
        return nil
    end
    local tooltipLines = {}
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local tooltipData = tryCall("C_TooltipInfo.GetItemByID", C_TooltipInfo.GetItemByID, itemID)
        if type(tooltipData) == "table" and type(tooltipData.lines) == "table" then
            for _, tooltipLine in ipairs(tooltipData.lines) do
                if tooltipLine.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, tooltipLine) end
                local red, green, blue = colorValues(tooltipLine.leftColor)
                tooltipLines[#tooltipLines + 1] = { text = tostring(tooltipLine.leftText or ""), r = red, g = green, b = blue }
            end
            if #tooltipLines > 0 then return tooltipLines end
        end
    end
    return scanTooltip("item:" .. itemID)
end

------------------------------------------------------------------ dungeon keys and raid attunements (Access)

-- Whether a quest is completed: true/false, or nil when the client offers no way to ask.
---@param questID integer
---@return boolean|nil
function Api.QuestDone(questID)
    local isQuestFlaggedCompleted = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not isQuestFlaggedCompleted then return nil end
    local done = tryCall("IsQuestFlaggedCompleted", isQuestFlaggedCompleted, questID)
    if done == nil then return nil end
    return done and true or false
end

---@class AccessScanStatistics
---@field keyring boolean the client has a key ring container
---@field questApi boolean completed quests can be asked
---@field keys integer keys seen
---@field unknownClass integer items the client could not classify yet

---@type AccessScanStatistics of the last ScanAccess (for /ps access)
Api.accessStatistics = { keyring = false, questApi = false, keys = 0, unknownClass = 0 }

-- keys in these bags, or nil when none of them is readable
---@param bagIDs integer[]
---@return table<integer, true>|nil
local function scanKeyContainers(bagIDs)
    local statistics = Api.accessStatistics
    local heldKeys, anyReadable = {}, false
    for _, bagID in ipairs(bagIDs) do
        local slotCount = containerSlotCount(bagID)
        if slotCount > 0 then anyReadable = true end
        for slotIndex = 1, slotCount do
            local itemID = containerItem(bagID, slotIndex)
            if itemID then
                local classID = Api.ItemClass(itemID)
                if classID == nil then statistics.unknownClass = statistics.unknownClass + 1 end
                if addon.Access.IsKey(itemID, classID) and not heldKeys[itemID] then
                    heldKeys[itemID] = true
                    statistics.keys = statistics.keys + 1
                end
            end
        end
    end
    return anyReadable and heldKeys or nil
end

-- Keys by readable location (bags and key ring always, the bank while it is open) and the attunements that can be
-- judged on this client: held when a quest of it is completed or its item is held (also in a closed bank: the item count
-- includes it), known not held when the quests can be asked and none is done. Unknown attunements are left out.
---@return AccessScan
function Api.ScanAccess()
    Api.accessStatistics = { keyring = false, questApi = false, keys = 0, unknownClass = 0 }
    local keysByLocation = {}
    local bagIDs = {}
    for bagID = 0, NUM_BAG_SLOTS or 4 do bagIDs[#bagIDs + 1] = bagID end
    keysByLocation.bag = scanKeyContainers(bagIDs)
    if KEYRING_CONTAINER then
        keysByLocation.keyring = scanKeyContainers({ KEYRING_CONTAINER })
        Api.accessStatistics.keyring = keysByLocation.keyring ~= nil
    end
    if Api.open.bank then
        local bankBagIDs = { BANK_CONTAINER or -1 }
        local bagSlotCount = NUM_BAG_SLOTS or 4
        for bagID = bagSlotCount + 1, bagSlotCount + (NUM_BANKBAGSLOTS or 7) do bankBagIDs[#bankBagIDs + 1] = bagID end
        keysByLocation.bank = scanKeyContainers(bankBagIDs)
    end
    local attunements = {}
    for _, attunement in ipairs(addon.Access.ATTUNEMENTS) do
        local held, questAnswered = false, false
        for _, questID in ipairs(attunement.quests) do
            local done = Api.QuestDone(questID)
            if done ~= nil then questAnswered = true end
            if done then held = true end
        end
        if attunement.item and Api.ItemCount(attunement.item) > 0 then held = true end
        if held then attunements[attunement.key] = true elseif questAnswered then attunements[attunement.key] = false end
        if questAnswered then Api.accessStatistics.questApi = true end
    end
    return { keys = keysByLocation, att = attunements }
end

------------------------------------------------------------------ faction standings (Reputation)

---@class FactionInformation
---@field name string|nil the faction's name in this client's language
---@field standing integer|nil 1 Hated .. 8 Exalted
---@field progress integer|nil progress inside the standing
---@field size integer|nil size of the standing

-- One faction as this client reports it, or nil when it cannot be asked. Classic GetFactionInfoByID first, the
-- C_Reputation table API of newer clients second.
---@param factionID integer
---@return FactionInformation|nil
local function factionInformation(factionID)
    if GetFactionInfoByID then
        local name, _, standing, barMinimum, barMaximum, barValue = tryCall("GetFactionInfoByID", GetFactionInfoByID, factionID)
        if type(standing) == "number" and type(barMinimum) == "number" and type(barMaximum) == "number" and type(barValue) == "number" then
            return { name = name, standing = standing, progress = barValue - barMinimum, size = barMaximum - barMinimum }
        end
        if type(name) == "string" then return { name = name } end
    end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local factionData = tryCall("C_Reputation.GetFactionDataByID", C_Reputation.GetFactionDataByID, factionID)
        if type(factionData) == "table" then
            local low, high, current = factionData.currentReactionThreshold, factionData.nextReactionThreshold, factionData.currentStanding
            if type(factionData.reaction) == "number" and type(low) == "number" and type(high) == "number" and type(current) == "number" then
                return { name = factionData.name, standing = factionData.reaction, progress = current - low, size = high - low }
            end
            return { name = factionData.name }
        end
    end
    return nil
end

-- the faction ids in the player's reputation list as it is shown (children of collapsed headers are not listed)
---@return table<integer, true>
local function listedFactionIDs()
    local factionIDs = {}
    local numberOfFactions = (C_Reputation and C_Reputation.GetNumFactions) or GetNumFactions
    local count = tonumber(tryCall("GetNumFactions", numberOfFactions)) or 0
    for factionIndex = 1, math.min(count, 500) do
        local factionID
        if GetFactionInfo then
            factionID = select(14, tryCall("GetFactionInfo", GetFactionInfo, factionIndex))
        elseif C_Reputation and C_Reputation.GetFactionDataByIndex then
            local factionData = tryCall("C_Reputation.GetFactionDataByIndex", C_Reputation.GetFactionDataByIndex, factionIndex)
            factionID = type(factionData) == "table" and factionData.factionID or nil
        end
        if type(factionID) == "number" then factionIDs[factionID] = true end
    end
    return factionIDs
end

---@class ReputationScanStatistics
---@field api boolean the client answers faction questions
---@field listed integer factions in the shown reputation list
---@field met integer listed factions (FactionHints) the character has met

---@type ReputationScanStatistics of the last ScanReputation (for /ps rep)
Api.reputationStatistics = { api = false, listed = 0, met = 0 }

-- My standing with every faction of FactionHints.FACTIONS I have met, or nil when the client cannot be asked (the record
-- then stays as it is). Factions of the other side are skipped. A faction counts as met when it is in my reputation list,
-- or when its standing is not an untouched default (Neutral or Hated with no progress), which also finds factions under a
-- collapsed header.
---@return table<integer, FactionStanding>|nil
function Api.ScanReputation()
    local statistics = { api = false, listed = 0, met = 0 }
    Api.reputationStatistics = statistics
    local listed = listedFactionIDs()
    statistics.listed = addon.Utility.Count(listed)
    local mySide = UnitFactionGroup and tryCall("UnitFactionGroup", UnitFactionGroup, "player")
    local standings = {}
    for _, faction in ipairs(addon.FactionHints.FACTIONS) do
        local otherSide = faction.side ~= nil and type(mySide) == "string" and faction.side ~= mySide
        local information = not otherSide and factionInformation(faction.id)
        if information and information.standing then
            statistics.api = true
            local untouched = (information.standing == 4 or information.standing == 1) and information.progress == 0
            if listed[faction.id] or not untouched then
                standings[faction.id] = { s = information.standing, v = information.progress, m = information.size }
                statistics.met = statistics.met + 1
            end
        end
    end
    if not statistics.api then return nil end
    return standings
end

-- the faction's name in this client's language, or nil
---@param factionID integer
---@return string|nil
function Api.FactionName(factionID)
    local information = factionInformation(factionID)
    local name = information and information.name
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- the game's own label of a standing ("Honored", "Wohlwollend"), or nil
---@param standing integer
---@return string|nil
function Api.StandingLabel(standing)
    local label = _G["FACTION_STANDING_LABEL" .. tostring(standing)]
    if type(label) == "string" and label ~= "" then return label end
    return nil
end

------------------------------------------------------------------ craft cooldowns (CraftCooldowns)

-- Right after login the game answers "no cooldown" for every spell until its cooldown data has arrived. A "ready" read
-- from a spell is only believed once Events has seen the first SPELL_UPDATE_COOLDOWN (or enough time has passed);
-- before that, a stored cooling value must not be replaced by a false "ready". Readings that show a cooldown are always
-- believed.
Api.cooldownState = { trusted = false }

-- a cooldown shorter than this is the global cooldown, not the craft's
local GLOBAL_COOLDOWN_SECONDS = 2

-- seconds left from a (start, duration) pair in GetTime() terms; 0 = no cooldown, nil = the values are unusable
---@param start any
---@param duration any
---@return number|nil
local function secondsLeft(start, duration)
    if type(start) ~= "number" or type(duration) ~= "number" or not GetTime then return nil end
    if start <= 0 or duration <= GLOBAL_COOLDOWN_SECONDS then return 0 end
    local remaining = start + duration - GetTime()
    if remaining <= 0 then return 0 end
    return math.min(remaining, duration)   -- a start time after "now" (clock wrap on long uptimes) still ends within duration
end

-- the cooldown of a spell I know: seconds left, or nil when the client gives no usable answer
---@param spellID integer
---@return number|nil
local function spellSecondsLeft(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local information = tryCall("C_Spell.GetSpellCooldown", C_Spell.GetSpellCooldown, spellID)
        if type(information) == "table" then return secondsLeft(information.startTime, information.duration) end
    end
    if GetSpellCooldown then
        local start, duration = tryCall("GetSpellCooldown", GetSpellCooldown, spellID)
        return secondsLeft(start, duration)
    end
    return nil
end

---@param itemID integer
---@return number|nil
local function itemSecondsLeft(itemID)
    local getItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not getItemCooldown then return nil end
    local start, duration = tryCall("GetItemCooldown", getItemCooldown, itemID)
    return secondsLeft(start, duration)
end

-- the open profession window's own cooldown for a recipe (nil: window closed, recipe not in it, or no answer)
---@param recipeID integer
---@return number|nil
local function tradeSkillSecondsLeft(recipeID)
    if not Api.open.tradeskill then return nil end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown then
        local information = C_TradeSkillUI.GetRecipeInfo and tryCall("C_TradeSkillUI.GetRecipeInfo", C_TradeSkillUI.GetRecipeInfo, recipeID)
        if type(information) ~= "table" or not information.learned then return nil end
        local cooldown = tryCall("C_TradeSkillUI.GetRecipeCooldown", C_TradeSkillUI.GetRecipeCooldown, recipeID)
        if type(cooldown) == "number" then return math.max(cooldown, 0) end
        return 0   -- learned, in the open window, and the window reports no cooldown
    end
    if GetNumTradeSkills and GetTradeSkillCooldown and GetTradeSkillRecipeLink then
        for skillIndex = 1, (tryCall("GetNumTradeSkills", GetNumTradeSkills) or 0) do
            local link = tryCall("GetTradeSkillRecipeLink", GetTradeSkillRecipeLink, skillIndex)
            if type(link) == "string" and tonumber(link:match("|H%a+:(%d+)")) == recipeID then
                local cooldown = tryCall("GetTradeSkillCooldown", GetTradeSkillCooldown, skillIndex)
                return type(cooldown) == "number" and math.max(cooldown, 0) or 0
            end
        end
    end
    return nil
end

---@param spellID integer
---@return boolean
local function knowsSpell(spellID)
    if IsPlayerSpell and tryCall("IsPlayerSpell", IsPlayerSpell, spellID) then return true end
    if IsSpellKnown and tryCall("IsSpellKnown", IsSpellKnown, spellID) then return true end
    return false
end

---@class CraftCooldownProbe
---@field known boolean
---@field byRecipes boolean I know a recipe of the group (my stored recipes)
---@field bySpell boolean the client says I know one of its spells
---@field itemCount? integer
---@field spell? number seconds left from the spell cooldown
---@field trade? number seconds left from the open profession window
---@field item? number seconds left from the item cooldown
---@field reading? CooldownReading what was taken

-- My craft cooldowns as the game reports them right now.
-- Returns known (group key -> true for each group I can do), readings (group key -> CooldownReading for the groups the
-- game gave a believable answer for) and the raw values per group for /ps cd.
---@return table<string, boolean> known
---@return table<string, CooldownReading> readings
---@return table<string, CraftCooldownProbe> probes
function Api.ReadCraftCooldowns()
    local CraftCooldowns = addon.CraftCooldowns
    local myName = addon.Utility.Me()
    local myRecord = myName and addon.Store.db and addon.Store.db.chars[myName]
    local byRecipes = CraftCooldowns.GroupsOfCharacter(myRecord)
    local known, readings, probes = {}, {}, {}
    for _, group in ipairs(CraftCooldowns.GROUPS) do
        local probe = { byRecipes = byRecipes[group.key] == true, bySpell = false }
        probes[group.key] = probe
        for _, recipeID in ipairs(group.recipes) do
            if knowsSpell(recipeID) then probe.bySpell = true end
            local tradeLeft = tradeSkillSecondsLeft(recipeID)
            if tradeLeft then probe.trade = math.max(probe.trade or 0, tradeLeft) end
            if probe.byRecipes or knowsSpell(recipeID) then
                local spellLeft = spellSecondsLeft(recipeID)
                if spellLeft then probe.spell = math.max(probe.spell or 0, spellLeft) end
            end
        end
        if group.item then
            probe.itemCount = Api.ItemCount(group.item)
            if probe.itemCount > 0 then probe.item = itemSecondsLeft(group.item) end
        end
        probe.known = probe.byRecipes or probe.bySpell or (probe.itemCount or 0) > 0 or probe.trade ~= nil
        if probe.known then
            known[group.key] = true
            -- the profession window is the most direct answer; then the spell, then the item
            local remaining, source = probe.trade, "trade"
            if remaining == nil then remaining, source = probe.spell, "spell" end
            if remaining == nil then remaining, source = probe.item, "item" end
            local believable = remaining ~= nil and (remaining > 0 or source == "trade" or Api.cooldownState.trusted)
            if believable then
                probe.reading = { remaining = remaining, source = source }
                readings[group.key] = probe.reading
            end
        end
    end
    return known, readings, probes
end

---@class CooldownRecipeProbe
---@field recipeID integer
---@field name string|nil
---@field cooldown number seconds left (0 = ready)

-- Every learned recipe of the OPEN profession window that has a cooldown (running or not, as far as the client says),
-- so /ps cd can show the real recipe ids on this client. Empty when no window is open or the API is missing.
---@return CooldownRecipeProbe[]
function Api.OpenWindowCooldownRecipes()
    local found = {}
    if not Api.open.tradeskill then return found end
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeCooldown then
        for _, recipeID in ipairs(tryCall("C_TradeSkillUI.GetAllRecipeIDs", C_TradeSkillUI.GetAllRecipeIDs) or {}) do
            local information = tryCall("C_TradeSkillUI.GetRecipeInfo", C_TradeSkillUI.GetRecipeInfo, recipeID)
            if type(information) == "table" and information.learned then
                local cooldown, isDayCooldown, charges, maximumCharges =
                    tryCall("C_TradeSkillUI.GetRecipeCooldown", C_TradeSkillUI.GetRecipeCooldown, recipeID)
                if type(cooldown) == "number" or isDayCooldown or (type(maximumCharges) == "number" and maximumCharges > 0)
                    or addon.CraftCooldowns.GroupOfRecipe(recipeID) then
                    found[#found + 1] = { recipeID = recipeID, name = information.name, cooldown = tonumber(cooldown) or 0,
                        charges = charges, dayCooldown = isDayCooldown }
                end
            end
        end
    elseif GetNumTradeSkills and GetTradeSkillCooldown then
        for skillIndex = 1, (tryCall("GetNumTradeSkills", GetNumTradeSkills) or 0) do
            local cooldown = tryCall("GetTradeSkillCooldown", GetTradeSkillCooldown, skillIndex)
            local link = GetTradeSkillRecipeLink and tryCall("GetTradeSkillRecipeLink", GetTradeSkillRecipeLink, skillIndex)
            local recipeID = type(link) == "string" and tonumber(link:match("|H%a+:(%d+)"))
            if recipeID and (type(cooldown) == "number" or addon.CraftCooldowns.GroupOfRecipe(recipeID)) then
                found[#found + 1] = { recipeID = recipeID, name = (tryCall("GetTradeSkillInfo", GetTradeSkillInfo, skillIndex)),
                    cooldown = tonumber(cooldown) or 0 }
            end
        end
    end
    return found
end

-- The chat link for a timegated craft, built by THIS client: the recipe's link for a one-recipe group, else (and as the
-- fallback) the crafted item's link; nil when neither is available yet.
---@param group CraftCooldownGroup
---@return string|nil
function Api.CraftLink(group)
    if #group.recipes == 1 then
        local link = Api.RecipeLink(group.recipes[1], group.produces)
        if link then return link end
    end
    return Api.ItemLink(group.produces)
end

------------------------------------------------------------------ craft and whisper from lists

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

-- Select a recipe in the open profession window (so the game's own Create button crafts it). true when the call (or the
-- filter fallback) raised no error; false when it failed or no API was there.
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

