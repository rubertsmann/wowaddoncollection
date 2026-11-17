local addonName, addon = ...

-- Pure view-models for the UI (unit-testable without frames).
-- Everything a player reads is resolved HERE for the viewer's language (Names), never taken from the sender's text,
-- and compared through Utility.SearchKey so case and accents do not matter.
-- Names can come from another player's snapshot: escape "|" so they can never inject colour/texture/hyperlink codes into a
-- FontString. Every peer-originated string leaves this module through `escape`.
---@class ModelModule
local Model = {}
addon.Model = Model

local escape = addon.Utility.Escape

---@param texts string[]
---@return string[]
local function escapeAll(texts)
    local escapedTexts = {}
    for index, text in ipairs(texts) do escapedTexts[index] = escape(text) end
    return escapedTexts
end

---@param store StoreModule
---@param recipeID integer
---@return string escaped
local function recipeName(store, recipeID)
    return escape(addon.Names.Recipe(recipeID, store.GetRecipe(recipeID)))
end
Model.RecipeName = recipeName

-- An order's recipe name: the catalog when the viewer has the recipe, else the snapshot the requester sent (2.2), and
-- only then a spell lookup by recipe id (unreliable on Forever: recipe ids are not spell ids).
---@param store StoreModule
---@param order Order
---@return string escaped
function Model.OrderRecipeName(store, order)
    if store.GetRecipe(order.recipeID) or not order.name then return recipeName(store, order.recipeID) end
    return escape(order.name)
end

---@param text string|nil
---@return string
local function sortKey(text) return addon.Utility.SearchKey(text or "") end

---@param left { name: string, key: any }
---@param right { name: string, key: any }
---@return boolean
local function byNameThenKey(left, right)
    local leftName, rightName = sortKey(left.name), sortKey(right.name)
    if leftName ~= rightName then return leftName < rightName end
    return tostring(left.key) < tostring(right.key)
end

---@class ProfessionChoice
---@field key integer|string canonical profession key
---@field name string escaped display name

-- unique professions across all cached characters, sorted by name.
-- 0.1.0 peers send name keys without an id; Names.ProfessionKey merges them with id-based entries ("Cooking" == "Kochkunst").
---@param store StoreModule
---@return ProfessionChoice[]
function Model.Professions(store)
    local seenKeys, professionChoices = {}, {}
    for _, characterRecord in pairs(store.db.chars) do
        for professionKey, profession in pairs(characterRecord.professions or {}) do
            if next(profession.recipes or {}) then
                local canonicalKey = addon.Names.ProfessionKey(professionKey, profession)
                if not seenKeys[canonicalKey] then
                    seenKeys[canonicalKey] = true
                    professionChoices[#professionChoices + 1] = { key = canonicalKey, name = escape(addon.Names.Profession(canonicalKey, profession)) }
                end
            end
        end
    end
    table.sort(professionChoices, byNameThenKey)
    return professionChoices
end

---@class OwnProfessionRow
---@field key integer|string
---@field id integer|nil skill line id
---@field spellName string the profession name as this client's spellbook spells it
---@field spells string[]
---@field icon any
---@field rank integer
---@field max integer
---@field name string display name
---@field count integer recipes already stored for it (0 = not scanned yet)

-- The player's own professions for the scan buttons (scanning needs the profession window to be opened by a real
-- click, see UI/Window.lua). Old name-keyed records are matched through Names.ProfessionKey.
---@param store StoreModule
---@param myName string|nil
---@param liveProfessions PlayerProfession[]|nil Api.GetPlayerProfessions()
---@return OwnProfessionRow[]
function Model.OwnProfessions(store, myName, liveProfessions)
    local myRecord = store.GetCharacter(myName or "")
    local recipeCountByKey = {}
    for professionKey, profession in pairs(myRecord and myRecord.professions or {}) do
        local canonicalKey = addon.Names.ProfessionKey(professionKey, profession)
        recipeCountByKey[canonicalKey] = (recipeCountByKey[canonicalKey] or 0) + addon.Utility.Count(profession.recipes or {})
    end
    local professionRows = {}
    for _, liveProfession in ipairs(liveProfessions or {}) do
        local canonicalKey = addon.Names.ProfessionKey(liveProfession.name, { id = liveProfession.id, name = liveProfession.name })
        professionRows[#professionRows + 1] = { key = canonicalKey, id = liveProfession.id, spellName = liveProfession.name,
            spells = liveProfession.spells, icon = liveProfession.icon, rank = liveProfession.rank, max = liveProfession.max,
            name = addon.Names.Profession(canonicalKey, { id = liveProfession.id, name = liveProfession.name, loc = addon.Locale.clientCode }),
            count = recipeCountByKey[canonicalKey] or 0 }
    end
    table.sort(professionRows, byNameThenKey)
    return professionRows
end

-- True while the player has professions but none of them has any stored recipe: the UI then shows a "CLICK HERE ->"
-- hint next to the profession buttons. It disappears as soon as one profession has been read.
---@param professionRows OwnProfessionRow[]
---@return boolean
function Model.NeedsScanHint(professionRows)
    if #professionRows == 0 then return false end
    for _, professionRow in ipairs(professionRows) do
        if professionRow.count > 0 then return false end
    end
    return true
end

-- Macro text of a profession button: the profession's own name first, then every other spellbook entry of that
-- profession (e.g. Skinning has a second one on Forever; `/cast` of a passive or unusable spell just fails and the
-- next line runs). Names only, no duplicates, at most 3 lines, nothing with line breaks (they come from our own client).
---@param professionRow { spellName: string|nil, spells: string[]|nil }
---@return string
function Model.CastMacro(professionRow)
    local macroLines, seenNames = {}, {}
    local function addCast(spellName)
        if type(spellName) == "string" and spellName ~= "" and not spellName:find("[\r\n]") and not seenNames[spellName] and #macroLines < 3 then
            seenNames[spellName] = true
            macroLines[#macroLines + 1] = "/cast " .. spellName
        end
    end
    addCast(professionRow.spellName)
    for _, spellName in ipairs(professionRow.spells or {}) do addCast(spellName) end
    return table.concat(macroLines, "\n")
end

------------------------------------------------------------------ item categories + free-text search (feature 011)
-- A recipe's category comes from the item it makes (catalog `produces`) and the CLIENT's item data (class, subclass,
-- equip slot); nothing about it is sent or stored. Recipes without an item (enchants, old catalog entries) are "none".
Model.CATEGORY_NONE = "none"
---@type table<string, string>
local EQUIP_SLOT_ALIAS = { INVTYPE_ROBE = "INVTYPE_CHEST" }
---@type table<string, integer>
local EQUIP_SLOT_ORDER = {}
for position, equipSlot in ipairs({ "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST",
    "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
    "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }) do EQUIP_SLOT_ORDER[equipSlot] = position end
-- group order: armor, weapons, consumables, containers, quivers, projectiles, trade goods, then by class id, "none" last
---@type table<integer, integer>
local GROUP_ORDER = { [4] = 1, [2] = 2, [0] = 3, [1] = 4, [11] = 5, [6] = 6, [7] = 7 }
local ARMOR_CLASS_ID = 4

-- client item data -> category key and group id (-1 = no item)
---@param classID any
---@param subclassID any
---@param equipLocation any
---@return string categoryKey
---@return integer groupID
function Model.CategoryKey(classID, subclassID, equipLocation)
    if type(classID) ~= "number" then return Model.CATEGORY_NONE, -1 end
    if classID == ARMOR_CLASS_ID and type(equipLocation) == "string" and equipLocation:find("^INVTYPE_")
        and equipLocation ~= "INVTYPE_NON_EQUIP_IGNORE" then
        return "slot:" .. (EQUIP_SLOT_ALIAS[equipLocation] or equipLocation), ARMOR_CLASS_ID
    end
    return ("class:%d:%d"):format(classID, tonumber(subclassID) or 0), classID
end

---@param groupID integer
---@return integer
local function groupRank(groupID)
    if groupID == -1 then return 100000 end
    return GROUP_ORDER[groupID] or (100 + groupID)
end

---@param store StoreModule
---@param recipeID integer
---@param itemClassFunction? fun(itemID: integer): any, any, any
---@return string categoryKey
---@return integer groupID
local function recipeCategory(store, recipeID, itemClassFunction)
    local catalogEntry = store.GetRecipe(recipeID)
    local producedItemID = catalogEntry and catalogEntry.produces
    if not producedItemID or not itemClassFunction then return Model.CATEGORY_NONE, -1 end
    local ok, classID, subclassID, equipLocation = pcall(itemClassFunction, producedItemID)
    if not ok then
        addon.Log.Warning("model.category", "reading an item's class failed", { itemID = producedItemID, error = tostring(classID) })
        return Model.CATEGORY_NONE, -1
    end
    return Model.CategoryKey(classID, subclassID, equipLocation)
end

-- Searchable text from tooltip lines (viewer's client, never a peer): drops the first line (the item name, searched
-- anyway) and every UI escape sequence, keeps at most maximumBytes (cut on a UTF-8 character boundary).
---@param tooltipLines any
---@param maximumBytes? integer
---@return string
function Model.TooltipSearchText(tooltipLines, maximumBytes)
    local cleanLines = {}
    for lineIndex, tooltipLine in ipairs(type(tooltipLines) == "table" and tooltipLines or {}) do
        if lineIndex > 1 and type(tooltipLine) == "string" then
            tooltipLine = tooltipLine:gsub("|4([^:;|]*):[^;|]*;", "%1")     -- plural "|4Sek.:Sek.;" -> "Sek."
                :gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
                :gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
                :gsub("|", ""):gsub("%s+", " ")
            tooltipLine = tooltipLine:match("^%s*(.-)%s*$")
            if tooltipLine ~= "" then cleanLines[#cleanLines + 1] = tooltipLine end
        end
    end
    local searchText = table.concat(cleanLines, " ")
    if maximumBytes and #searchText > maximumBytes then searchText = addon.Utility.TruncateUtf8(searchText, maximumBytes) end
    return searchText
end

---@class RecipeFilterState
---@field profession? integer|string canonical profession key (nil = all)
---@field text? string free-text search
---@field mineOnly? boolean
---@field me? string
---@field categories? table<string, boolean> nil or empty = all

---@class RecipeLookups
---@field class? fun(itemID: integer): any, any, any classID, subclassID, equipLocation
---@field label? fun(categoryKey: string): string
---@field groupLabel? fun(groupID: integer): string
---@field text? fun(itemID: integer): string|nil effect/tooltip text

---@class RecipeRow
---@field recipeID integer
---@field name string escaped
---@field icon any
---@field professionKey integer|string
---@field profession string escaped
---@field crafters string[]
---@field crafterCount integer
---@field category string
---@field group integer

-- Search is free text: every word must appear somewhere in name, profession, reagents, category or the item's text.
---@param store StoreModule
---@param state RecipeFilterState
---@param itemNameFunction? fun(itemID: integer): string|nil cached item name (reagent search)
---@param lookups? RecipeLookups
---@return RecipeRow[]
function Model.BuildRecipeRows(store, state, itemNameFunction, lookups)
    lookups = lookups or {}
    local searchWords = {}
    for searchWord in sortKey(state.text):gmatch("%S+") do searchWords[#searchWords + 1] = searchWord end
    local selectedCategories = type(state.categories) == "table" and next(state.categories) and state.categories or nil
    local rowByRecipe, recipeRows = {}, {}
    for _, characterRecord in pairs(store.db.chars) do
        for professionKey, profession in pairs(characterRecord.professions or {}) do
            local canonicalKey = addon.Names.ProfessionKey(professionKey, profession)
            if state.profession == nil or state.profession == canonicalKey then
                for recipeID in pairs(profession.recipes or {}) do
                    if not state.mineOnly or characterRecord.name == state.me then
                        local recipeRow = rowByRecipe[recipeID]
                        if not recipeRow then
                            local catalogEntry = store.GetRecipe(recipeID)
                            recipeRow = { recipeID = recipeID, name = recipeName(store, recipeID), icon = catalogEntry and catalogEntry.icon,
                                professionKey = canonicalKey, profession = escape(addon.Names.Profession(canonicalKey, profession)), crafters = {} }
                            recipeRow.category, recipeRow.group = recipeCategory(store, recipeID, lookups.class)
                            rowByRecipe[recipeID] = recipeRow
                            recipeRows[#recipeRows + 1] = recipeRow
                        end
                        recipeRow.crafters[#recipeRow.crafters + 1] = characterRecord.name
                    end
                end
            end
        end
    end
    local keptRows = {}
    for _, recipeRow in ipairs(recipeRows) do
        local keep = not selectedCategories or selectedCategories[recipeRow.category] == true
        if keep and #searchWords > 0 then
            local catalogEntry = store.GetRecipe(recipeRow.recipeID)
            local searchableTexts = { recipeRow.name, recipeRow.profession }
            for _, reagent in ipairs(catalogEntry and catalogEntry.reagents or {}) do
                searchableTexts[#searchableTexts + 1] = (itemNameFunction and itemNameFunction(reagent.itemID)) or reagent.name   -- the viewer's client first
            end
            if lookups.label then searchableTexts[#searchableTexts + 1] = lookups.label(recipeRow.category) end
            if lookups.text and catalogEntry and catalogEntry.produces then searchableTexts[#searchableTexts + 1] = lookups.text(catalogEntry.produces) end
            local searchKeys = {}
            for _, searchableText in ipairs(searchableTexts) do
                if type(searchableText) == "string" then searchKeys[#searchKeys + 1] = sortKey(searchableText) end
            end
            local haystack = table.concat(searchKeys, "\n")
            for _, searchWord in ipairs(searchWords) do
                if not haystack:find(searchWord, 1, true) then keep = false; break end
            end
        end
        if keep then
            recipeRow.crafterCount = #recipeRow.crafters
            keptRows[#keptRows + 1] = recipeRow
        end
    end
    table.sort(keptRows, function(left, right)
        local leftProfession, rightProfession = sortKey(left.profession), sortKey(right.profession)
        if leftProfession ~= rightProfession then return leftProfession < rightProfession end
        local leftName, rightName = sortKey(left.name), sortKey(right.name)
        if leftName ~= rightName then return leftName < rightName end
        return left.recipeID < right.recipeID
    end)
    return keptRows
end

---@class CategoryChoice
---@field key string
---@field label string
---@field count integer recipes in it

---@class CategoryGroup
---@field group integer
---@field label string
---@field categories CategoryChoice[]

-- The categories present for the current profession / "mine only" choice (ignores text and the category choice itself),
-- in display order.
---@param store StoreModule
---@param state RecipeFilterState
---@param lookups? RecipeLookups
---@return CategoryGroup[]
function Model.RecipeCategories(store, state, lookups)
    lookups = lookups or {}
    local recipeRows = Model.BuildRecipeRows(store, { profession = state.profession, mineOnly = state.mineOnly, me = state.me,
        text = "" }, nil, { class = lookups.class })
    local categoryGroups, groupByID, choiceByKey = {}, {}, {}
    for _, recipeRow in ipairs(recipeRows) do
        local categoryChoice = choiceByKey[recipeRow.category]
        if not categoryChoice then
            local categoryGroup = groupByID[recipeRow.group]
            if not categoryGroup then
                categoryGroup = { group = recipeRow.group,
                    label = tostring((lookups.groupLabel and lookups.groupLabel(recipeRow.group)) or recipeRow.group), categories = {} }
                groupByID[recipeRow.group] = categoryGroup
                categoryGroups[#categoryGroups + 1] = categoryGroup
            end
            categoryChoice = { key = recipeRow.category,
                label = tostring((lookups.label and lookups.label(recipeRow.category)) or recipeRow.category), count = 0 }
            choiceByKey[recipeRow.category] = categoryChoice
            categoryGroup.categories[#categoryGroup.categories + 1] = categoryChoice
        end
        categoryChoice.count = categoryChoice.count + 1
    end
    table.sort(categoryGroups, function(left, right)
        local leftRank, rightRank = groupRank(left.group), groupRank(right.group)
        if leftRank ~= rightRank then return leftRank < rightRank end
        return sortKey(left.label) < sortKey(right.label)
    end)
    for _, categoryGroup in ipairs(categoryGroups) do
        table.sort(categoryGroup.categories, function(left, right)
            local leftSlot = EQUIP_SLOT_ORDER[left.key:match("^slot:(.+)$") or ""] or 99
            local rightSlot = EQUIP_SLOT_ORDER[right.key:match("^slot:(.+)$") or ""] or 99
            if leftSlot ~= rightSlot then return leftSlot < rightSlot end
            local leftLabel, rightLabel = sortKey(left.label), sortKey(right.label)
            if leftLabel ~= rightLabel then return leftLabel < rightLabel end
            return left.key < right.key
        end)
    end
    return categoryGroups
end

---@class ReagentRow
---@field itemID integer
---@field count integer
---@field name string escaped
---@field have integer
---@field enough boolean

---@class RecipeDetail
---@field recipeID integer
---@field name string
---@field icon any
---@field produces integer|nil
---@field reagents ReagentRow[]
---@field crafters CrafterRow[] each with professionName (escaped); name stays raw (whisper target, never contains "|")

---@param store StoreModule
---@param recipeID integer
---@param heldCountFunction? fun(itemID: integer): integer
---@param itemNameFunction? fun(itemID: integer): string|nil
---@return RecipeDetail
function Model.RecipeDetail(store, recipeID, heldCountFunction, itemNameFunction)
    local catalogEntry = store.GetRecipe(recipeID)
    local recipeDetail = { recipeID = recipeID, name = recipeName(store, recipeID), icon = catalogEntry and catalogEntry.icon,
        produces = catalogEntry and catalogEntry.produces, reagents = {}, crafters = store.Crafters(recipeID) }
    for _, crafterRow in ipairs(recipeDetail.crafters) do
        crafterRow.professionName = escape(addon.Names.Profession(addon.Names.ProfessionKey(crafterRow.profession, crafterRow.pentry), crafterRow.pentry))
        -- crafterRow.name stays raw: it is also the whisper target, and character names never contain "|" (Utility.IsSafeName)
    end
    for _, reagent in ipairs(catalogEntry and catalogEntry.reagents or {}) do
        local heldCount = heldCountFunction and heldCountFunction(reagent.itemID) or 0
        recipeDetail.reagents[#recipeDetail.reagents + 1] = { itemID = reagent.itemID, count = reagent.count,
            name = escape((itemNameFunction and itemNameFunction(reagent.itemID)) or reagent.name
                or addon.Locale.Format(addon.Text["Item #{id}"], { id = reagent.itemID })),
            have = heldCount, enough = heldCount >= reagent.count }
    end
    return recipeDetail
end

---@alias OrderFilterKey "all"|"open"|"mine"|"crafting"|"can"

---@class OrderRow
---@field id string
---@field recipeID integer
---@field recipeName string escaped
---@field qty integer
---@field note string escaped
---@field requester string escaped
---@field status OrderStatus
---@field claimers string[] escaped
---@field claimersRaw string[]
---@field createdAt integer
---@field canClaim boolean
---@field canCraft boolean
---@field canWithdraw boolean
---@field canDone boolean
---@field canCancel boolean

---@param store StoreModule
---@param orderBoard OrderBoard
---@param filterKey OrderFilterKey
---@param showClosed boolean
---@param myName string|nil
---@return OrderRow[]
function Model.BuildOrderRows(store, orderBoard, filterKey, showClosed, myName)
    local myRecord = store.GetCharacter(myName)
    local function iKnow(recipeID) return addon.Store.Knows(myRecord, recipeID) end
    local orderRows = {}
    for _, order in ipairs(orderBoard:List({ showClosed = showClosed })) do
        local status = orderBoard:Status(order)
        local claimers = orderBoard:Claimers(order)
        local myClaim = order.claims[myName]
        local iClaimed = myClaim and myClaim.state == "claimed"
        local keep = true
        if filterKey == "open" then keep = status == "open"
        elseif filterKey == "mine" then keep = order.requester == myName
        elseif filterKey == "crafting" then keep = iClaimed and true or false
        elseif filterKey == "can" then keep = iKnow(order.recipeID) end
        if keep then
            local isLive = (status == "open" or status == "claimed")
            orderRows[#orderRows + 1] = { id = order.id, recipeID = order.recipeID, recipeName = Model.OrderRecipeName(store, order),
                qty = order.qty, note = escape(order.note), requester = escape(order.requester), status = status,
                claimers = escapeAll(claimers), createdAt = order.createdAt,
                canClaim = isLive and not iClaimed and iKnow(order.recipeID),
                canCraft = isLive and iKnow(order.recipeID) or false,
                claimersRaw = claimers,
                canWithdraw = isLive and iClaimed or false,
                canDone = isLive and (order.requester == myName or iClaimed) or false,
                canCancel = isLive and order.requester == myName }
        end
    end
    return orderRows
end

------------------------------------------------------------------ recipe items board (feature 007)

-- "Bags x2", "Guild bank tab 3 x1": location label for the viewer's language (stored data holds only the location key)
---@param location string
---@param count integer
---@return string
function Model.LocationLabel(location, count)
    local Text = addon.Text
    local label
    if location == "bag" then label = Text["Bags"]
    elseif location == "bank" then label = Text["Bank"]
    elseif location == "reagent" then label = Text["Reagent bank"]
    elseif location == "mail" then label = Text["Mail"]
    elseif location == "auction" then label = Text["Auctions"]
    else label = addon.Locale.Format(Text["Guild bank tab {n}"], { n = tonumber(tostring(location):match("^gbank(%d)$")) or 0 }) end
    return label .. " x" .. tostring(count)
end

---@class OfferFilterState
---@field text? string
---@field myProfessionsOnly? boolean only items for my professions
---@field me? string

---@class OfferViewRow
---@field key string
---@field owner string raw
---@field ownerName string escaped
---@field itemID integer
---@field name string escaped
---@field icon any
---@field profession string|nil escaped
---@field locations string
---@field total integer
---@field dibs { who: string, whoRaw: string, t: integer, mine: boolean }[]
---@field dibCount integer
---@field mine boolean
---@field canDib boolean
---@field ownerRev integer

-- Everything that came from a peer (owner and dib holder names) is escaped; item names and icons come from THIS client,
-- and an id the client does not know or that is not a recipe item is not shown (a peer cannot list arbitrary things).
---@param store StoreModule
---@param state OfferFilterState
---@param itemClassFunction fun(itemID: integer): any, any, any classID, subclassID, icon (client item data, no loading)
---@param itemNameFunction? fun(itemID: integer): string|nil
---@return OfferViewRow[]
function Model.BuildOfferRows(store, state, itemClassFunction, itemNameFunction)
    local searchText = sortKey(state.text)
    local mySkillLines = {}
    local myRecord = store.GetCharacter(state.me or "")
    for professionKey, profession in pairs(myRecord and myRecord.professions or {}) do
        local canonicalKey = addon.Names.ProfessionKey(professionKey, profession)
        if type(canonicalKey) == "number" then mySkillLines[canonicalKey] = true end
    end
    local offerRows = {}
    for _, offerRow in ipairs(addon.Offers.List(state.me)) do
        local classID, subclassID, icon = itemClassFunction(offerRow.itemID)
        if classID == addon.Offers.RECIPE_CLASS then
            local skillLineID = addon.Offers.SUBCLASS_SKILL[subclassID]
            local keep = true
            if state.myProfessionsOnly and not (skillLineID and mySkillLines[skillLineID]) then keep = false end
            local itemName = escape((itemNameFunction and itemNameFunction(offerRow.itemID))
                or addon.Locale.Format(addon.Text["Item #{id}"], { id = offerRow.itemID }))
            local professionName = skillLineID and escape(addon.Names.Profession(skillLineID, { id = skillLineID })) or nil
            if keep and searchText ~= "" then
                keep = sortKey(itemName):find(searchText, 1, true) ~= nil or sortKey(offerRow.owner):find(searchText, 1, true) ~= nil
                    or (professionName ~= nil and sortKey(professionName):find(searchText, 1, true) ~= nil)
            end
            if keep then
                local locationLabels = {}
                for index, locationCount in ipairs(offerRow.locs) do
                    locationLabels[index] = Model.LocationLabel(locationCount.loc, locationCount.count)
                end
                local dibRows = {}
                for index, dibRow in ipairs(offerRow.dibs) do
                    dibRows[index] = { who = escape(dibRow.who), whoRaw = dibRow.who, t = dibRow.t, mine = dibRow.who == state.me }
                end
                offerRows[#offerRows + 1] = { key = offerRow.key, owner = offerRow.owner, ownerName = escape(offerRow.owner),
                    itemID = offerRow.itemID, name = itemName, icon = icon, profession = professionName,
                    locations = table.concat(locationLabels, ", "), total = offerRow.total, dibs = dibRows, dibCount = #dibRows,
                    mine = offerRow.mine, canDib = offerRow.owner ~= state.me, ownerRev = offerRow.ownerRev }
            end
        end
    end
    table.sort(offerRows, function(left, right)
        local leftProfession, rightProfession = sortKey(left.profession or ""), sortKey(right.profession or "")
        if leftProfession ~= rightProfession then return leftProfession < rightProfession end
        local leftName, rightName = sortKey(left.name), sortKey(right.name)
        if leftName ~= rightName then return leftName < rightName end
        if left.owner ~= right.owner then return left.owner < right.owner end
        return left.itemID < right.itemID
    end)
    return offerRows
end

------------------------------------------------------------------ craft and whisper from lists (feature 009)

---@alias CraftRefusal "unknown"|"noprof"

-- The own profession that holds recipeID, as an OwnProfessions row (spellName/spells for CastMacro), or nil and why:
-- "unknown" (I do not know the recipe), "noprof" (my record has it, but the profession is not in my live spellbook).
---@param store StoreModule
---@param myName string|nil
---@param recipeID integer
---@param liveProfessions PlayerProfession[]|nil
---@return OwnProfessionRow|nil
---@return CraftRefusal|nil
function Model.CraftTarget(store, myName, recipeID, liveProfessions)
    local myRecord = store.GetCharacter(myName or "")
    local canonicalKey
    for professionKey, profession in pairs(myRecord and myRecord.professions or {}) do
        if profession.recipes and profession.recipes[recipeID] then canonicalKey = addon.Names.ProfessionKey(professionKey, profession) break end
    end
    if not canonicalKey then return nil, "unknown" end
    for _, professionRow in ipairs(Model.OwnProfessions(store, myName, liveProfessions)) do
        if professionRow.key == canonicalKey and type(professionRow.spellName) == "string" and professionRow.spellName ~= "" then
            return professionRow
        end
    end
    return nil, "noprof"
end

-- Whom an icon click on an order row whispers: the requester, or on my own order the first claimer (nil: nobody but me).
---@param orderRow OrderRow
---@param myName string|nil
---@return string|nil
function Model.OrderContact(orderRow, myName)
    if orderRow.requester ~= myName then return orderRow.requester end
    for _, crafter in ipairs(orderRow.claimersRaw or orderRow.claimers or {}) do
        if crafter ~= myName then return crafter end
    end
    return nil
end

-- Whom an icon click on a recipe row whispers: the first crafter (Store.Crafters order: highest rank) who is not me.
---@param crafters (CrafterRow|string)[]|nil
---@param myName string|nil
---@return string|nil
function Model.RecipeContact(crafters, myName)
    for _, crafter in ipairs(crafters or {}) do
        local crafterName = type(crafter) == "table" and crafter.name or crafter
        if crafterName ~= myName then return crafterName end
    end
    return nil
end

-- Text inserted into a whisper. link: a hyperlink built by THIS client (Api.RecipeLink), else the recipe name as plain
-- "[Name]" with every "|" and bracket removed, so text a peer sent can never become a link or escape code in chat.
---@param link string|nil
---@param plainName any
---@param quantity? integer
---@return string
function Model.ChatText(link, plainName, quantity)
    local chatText = link
    if type(chatText) ~= "string" or chatText == "" then
        chatText = "[" .. addon.Utility.ChatSafe(plainName or "?") .. "]"
    end
    if quantity and quantity > 1 then chatText = chatText .. " x" .. quantity end
    return chatText
end

------------------------------------------------------------------ guild games leaderboard (feature 014)

---@type table<string, string> WoW's coin colours
local MONEY_COLOR = { g = "ffd700", s = "c7c7cf", c = "eda55f" }

-- "1g 50s 25c" with each part in its coin colour; zero parts are left out ("50s", "3c"); 0 -> "0c". Amounts in copper.
---@param copper integer
---@return string
function Model.MoneyText(copper)
    local gold, silver, rest = addon.Games.SplitMoney(math.abs(copper or 0))
    local Text, Format = addon.Text, addon.Locale.Format
    local parts = {}
    local function add(colorKey, text) parts[#parts + 1] = "|cff" .. MONEY_COLOR[colorKey] .. text .. "|r" end
    if gold > 0 then add("g", Format(Text["{n}g"], { n = gold })) end
    if silver > 0 then add("s", Format(Text["{n}s"], { n = silver })) end
    if rest > 0 or #parts == 0 then add("c", Format(Text["{n}c"], { n = rest })) end
    return table.concat(parts, " ")
end

---@class LeaderboardRow
---@field rank integer
---@field name string escaped display name
---@field nameRaw string the record key
---@field net integer won - lost
---@field won integer
---@field lost integer
---@field wins integer
---@field losses integer
---@field flips integer
---@field mine boolean

---@param left LeaderboardRow
---@param right LeaderboardRow
---@return boolean
local function leaderboardOrder(left, right)
    if left.net ~= right.net then return left.net > right.net end
    if left.flips ~= right.flips then return left.flips > right.flips end
    return left.nameRaw < right.nameRaw
end

-- Leaderboard of one scope: "week" (the totals under `periodKey`) or "all" (all-time totals). Sorted by net, then flips,
-- then name; players without a flip in the scope are left out. Names come from peers and are escaped.
---@param records table<string, GameRecord>
---@param scope "week"|"all"
---@param periodKey string the week shown for scope "week"
---@param myName string|nil
---@return LeaderboardRow[]
function Model.BuildLeaderboardRows(records, scope, periodKey, myName)
    local rows = {}
    for playerName, gameRecord in pairs(records or {}) do
        local totals = gameRecord.total
        if scope == "week" then totals = gameRecord.weeks and gameRecord.weeks[periodKey] end
        local flips = totals and (totals.wins + totals.losses) or 0
        if flips > 0 then
            rows[#rows + 1] = { name = escape(playerName), nameRaw = playerName, net = totals.won - totals.lost, won = totals.won,
                lost = totals.lost, wins = totals.wins, losses = totals.losses, flips = flips, mine = playerName == myName }
        end
    end
    table.sort(rows, leaderboardOrder)
    for index, row in ipairs(rows) do row.rank = index end
    return rows
end

---@class FlipFeedRow
---@field name string escaped
---@field nameRaw string
---@field net integer +stake or -stake
---@field t integer server time of the flip
---@field mine boolean

-- The newest flips of every player, merged (newest first; same second: by name). Default limit 15.
---@param records table<string, GameRecord>
---@param myName string|nil
---@param limit? integer
---@return FlipFeedRow[]
function Model.BuildFlipFeedRows(records, myName, limit)
    local rows = {}
    for playerName, gameRecord in pairs(records or {}) do
        for _, flip in ipairs(gameRecord.recent or {}) do
            rows[#rows + 1] = { name = escape(playerName), nameRaw = playerName, net = flip.r == "W" and flip.c or -flip.c,
                t = flip.t, mine = playerName == myName }
        end
    end
    table.sort(rows, function(left, right)
        if left.t ~= right.t then return left.t > right.t end
        if left.nameRaw ~= right.nameRaw then return left.nameRaw < right.nameRaw end
        return left.net > right.net
    end)
    for index = #rows, (limit or 15) + 1, -1 do rows[index] = nil end
    return rows
end

-- The winner of the week `previousPeriodKey`: the top leaderboard row of that week when its net is positive, else nil.
---@param records table<string, GameRecord>
---@param previousPeriodKey string
---@return LeaderboardRow|nil
function Model.PreviousWinner(records, previousPeriodKey)
    local top = Model.BuildLeaderboardRows(records, "week", previousPeriodKey, nil)[1]
    if top and top.net > 0 then return top end
    return nil
end
