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

-- The words of a search text, each folded like Utility.SearchKey (case and accents do not matter). Shared by every list
-- with a free-text search: a row matches when EVERY word appears somewhere in its texts (Model.MatchesWords).
---@param text string|nil
---@return string[]
function Model.SearchWords(text)
    local searchWords = {}
    for searchWord in sortKey(text):gmatch("%S+") do searchWords[#searchWords + 1] = searchWord end
    return searchWords
end

-- Whether every search word appears in at least one of the texts (non-strings are skipped). No words match everything.
---@param searchWords string[]
---@param texts any[]
---@return boolean
function Model.MatchesWords(searchWords, texts)
    if #searchWords == 0 then return true end
    local searchKeys = {}
    for _, text in ipairs(texts) do
        if type(text) == "string" then searchKeys[#searchKeys + 1] = sortKey(text) end
    end
    local haystack = table.concat(searchKeys, "\n")
    for _, searchWord in ipairs(searchWords) do
        if not haystack:find(searchWord, 1, true) then return false end
    end
    return true
end

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

-- Unique professions (that hold at least one recipe) across all cached characters, sorted by name.
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

-- Macro text of a profession button whose window spell is not known: "/cast <profession name>" (the client resolves the
-- name to its window spell). One line only: casting a second spell of the profession can toggle the window closed
-- again. Empty when the name is missing or has a line break (it comes from our own client, but is never trusted).
---@param professionRow { spellName: string|nil }
---@return string
function Model.CastMacro(professionRow)
    local spellName = professionRow.spellName
    if type(spellName) ~= "string" or spellName == "" or spellName:find("[\r\n]") then return "" end
    return "/cast " .. spellName
end

-- What a profession button does: cast the window spell by id (ProfessionSpells), or "/cast <name>" when it is not known.
---@param professionRow { id: integer|nil, spellName: string|nil }
---@return { type: "spell"|"macro", spell: integer|nil, macrotext: string|nil, source: string }
function Model.OpenAction(professionRow)
    local spellID = addon.ProfessionSpells.WindowSpellID(professionRow.id)
    if spellID then return { type = "spell", spell = spellID, source = "static" } end
    return { type = "macro", macrotext = Model.CastMacro(professionRow), source = "name" }
end

-- One line for the log: what the button casts.
---@param openAction { type: string, spell: integer|nil, macrotext: string|nil, source: string }
---@return string
function Model.DescribeOpenAction(openAction)
    if openAction.type == "spell" then return ("spell %d (%s)"):format(openAction.spell, openAction.source) end
    return "macro " .. (tostring(openAction.macrotext):gsub("\n", " / "))
end

------------------------------------------------------------------ item categories + free-text search
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
---@field itemDetails? fun(itemID: integer): integer|nil, integer|nil, integer|nil quality, item level, required level
---@field effect? fun(recipeID: integer): string|nil effect text of a recipe without an item, e.g. an enchant

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
---@field categoryLabel string category in the viewer's language ("" without a label lookup)
---@field quality integer|nil crafted item's quality (nil: no item or not cached yet)
---@field itemLevel integer|nil
---@field requiredLevel integer|nil
---@field skill integer|nil profession skill the recipe needs

-- Search is free text: every word must appear somewhere in name, profession, reagents, category, the item's text or an
-- enchant's effect text.
---@param store StoreModule
---@param state RecipeFilterState
---@param itemNameFunction? fun(itemID: integer): string|nil cached item name (reagent search)
---@param lookups? RecipeLookups
---@return RecipeRow[]
function Model.BuildRecipeRows(store, state, itemNameFunction, lookups)
    lookups = lookups or {}
    local searchWords = Model.SearchWords(state.text)
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
                            recipeRow.categoryLabel = lookups.label and lookups.label(recipeRow.category) or ""
                            recipeRow.skill = catalogEntry and catalogEntry.minSkill
                            if lookups.itemDetails and catalogEntry and catalogEntry.produces then
                                recipeRow.quality, recipeRow.itemLevel, recipeRow.requiredLevel = lookups.itemDetails(catalogEntry.produces)
                            end
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
            if recipeRow.categoryLabel ~= "" then searchableTexts[#searchableTexts + 1] = recipeRow.categoryLabel end
            if lookups.text and catalogEntry and catalogEntry.produces then searchableTexts[#searchableTexts + 1] = lookups.text(catalogEntry.produces) end
            -- a recipe without an item (enchant) is searched by its spell's effect text
            if lookups.effect and not (catalogEntry and catalogEntry.produces) then searchableTexts[#searchableTexts + 1] = lookups.effect(recipeRow.recipeID) end
            keep = Model.MatchesWords(searchWords, searchableTexts)
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

---@alias OrderFilterKey "all"|"open"|"mine"|"crafting"|"can"|"mailed"

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
---@field unreadChat integer chat messages by others I have not read (only on orders I requested or claim)

---@param store StoreModule
---@param orderBoard OrderBoard
---@param filterKey OrderFilterKey
---@param showClosed boolean
---@param myName string|nil
---@param chatSeen? table<string, integer> db.ui.chatSeen
---@return OrderRow[]
function Model.BuildOrderRows(store, orderBoard, filterKey, showClosed, myName, chatSeen)
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
        elseif filterKey == "can" then keep = iKnow(order.recipeID)
        elseif filterKey == "mailed" then keep = status == "mailed" end
        if keep then
            local isLive = Model.OrderIsLive(status)
            local catalogEntry = store.GetRecipe(order.recipeID)
            local otherClaimer = false
            for _, crafter in ipairs(claimers) do if crafter ~= myName then otherClaimer = true end end
            orderRows[#orderRows + 1] = { id = order.id, recipeID = order.recipeID, recipeName = Model.OrderRecipeName(store, order),
                -- row actions: reagents to a claimer (not me), the crafted item to the requester (not me)
                canMailMats = isLive and otherClaimer and catalogEntry ~= nil and #(catalogEntry.reagents or {}) > 0,
                canMailItem = status ~= "cancelled" and order.requester ~= myName and catalogEntry ~= nil and catalogEntry.produces ~= nil,
                hasReagents = catalogEntry ~= nil and #(catalogEntry.reagents or {}) > 0,
                qty = order.qty, note = escape(order.note), requester = escape(order.requester), status = status,
                claimers = escapeAll(claimers), createdAt = order.createdAt,
                canClaim = isLive and not iClaimed and iKnow(order.recipeID),
                canCraft = isLive and iKnow(order.recipeID) or false,
                claimersRaw = claimers,
                canWithdraw = isLive and iClaimed or false,
                canDone = isLive and (order.requester == myName or iClaimed) or false,
                canCancel = isLive and order.requester == myName,
                unreadChat = addon.Notify.Involved(order, myName) and (addon.Notify.ChatUnread(order, myName, chatSeen)) or 0 }
        end
    end
    return orderRows
end

------------------------------------------------------------------ order window

-- open, claimed or mailed: the order can still be claimed, withdrawn, finished or cancelled
---@param status OrderStatus
---@return boolean
function Model.OrderIsLive(status) return status == "open" or status == "claimed" or status == "mailed" end

---@class OrderHistoryRow
---@field t integer server time
---@field kind "created"|"claim"|"withdraw"|"done"|"cancel"|"mail"
---@field who string raw canonical name (escape before display)
---@field mail? OrderMail kind "mail": the entry (mode m, recipient r, items i, complete c, by hand h)

-- Every status change of an order, oldest first: the recorded events (protocol 2.9) plus what the order's own fields
-- show (creation, each crafter's last claim or withdrawal, the close), so changes made by older addon versions appear too.
---@param order Order
---@return OrderHistoryRow[]
function Model.OrderHistory(order)
    local historyRows, seenKeys = {}, {}
    local function add(eventTime, kind, who, mail)
        if type(eventTime) ~= "number" or type(who) ~= "string" then return end
        local key = kind .. "\0" .. who .. "\0" .. eventTime .. "\0" .. (mail and mail.m or "")
        if seenKeys[key] then return end
        seenKeys[key] = true
        historyRows[#historyRows + 1] = { t = eventTime, kind = kind, who = who, mail = mail }
    end
    add(order.createdAt, "created", order.requester)
    for _, event in ipairs(order.ev or {}) do add(event.t, event.k, event.b) end
    for _, mail in ipairs(order.ml or {}) do add(mail.t, "mail", mail.b, mail) end
    for crafter, claim in pairs(order.claims or {}) do add(claim.t, claim.state == "claimed" and "claim" or "withdraw", crafter) end
    if order.closed then add(order.closedAt, order.closed == "done" and "done" or "cancel", order.closedBy or order.requester) end
    table.sort(historyRows, function(left, right)
        if left.t ~= right.t then return left.t < right.t end
        if left.kind == "created" or right.kind == "created" then return left.kind == "created" and right.kind ~= "created" end
        if left.kind ~= right.kind then return left.kind < right.kind end
        if left.who ~= right.who then return left.who < right.who end
        return (left.mail and left.mail.m or "") < (right.mail and right.mail.m or "")
    end)
    return historyRows
end

---@class OrderChatRow
---@field t integer server time
---@field author string raw canonical name
---@field text string escaped
---@field mine boolean

---@param order Order
---@param myName string|nil
---@return OrderChatRow[]
function Model.OrderChatRows(order, myName)
    local chatRows = {}
    for index, message in ipairs(order.msgs or {}) do
        chatRows[index] = { t = message.t, author = message.b, text = escape(message.x), mine = message.b == myName }
    end
    return chatRows
end

---@class OrderOverview
---@field recipeName string escaped
---@field icon any
---@field qty integer
---@field status OrderStatus
---@field requester string raw
---@field claimers string[] raw
---@field createdAt integer
---@field closedAt integer|nil
---@field closedBy string|nil raw
---@field note string escaped
---@field reagents ReagentRow[] counts for the whole order (recipe count x quantity)
---@field tools string[] escaped; empty when unknown
---@field crafters CrafterRow[] guild members who know the recipe

---@param store StoreModule
---@param orderBoard OrderBoard
---@param order Order
---@param heldCountFunction? fun(itemID: integer): integer
---@param itemNameFunction? fun(itemID: integer): string|nil
---@return OrderOverview
function Model.OrderOverview(store, orderBoard, order, heldCountFunction, itemNameFunction)
    local recipeDetail = Model.RecipeDetail(store, order.recipeID, heldCountFunction, itemNameFunction)
    for _, reagentRow in ipairs(recipeDetail.reagents) do
        reagentRow.count = reagentRow.count * order.qty
        reagentRow.enough = reagentRow.have >= reagentRow.count
    end
    local catalogEntry = store.GetRecipe(order.recipeID)
    return { recipeName = Model.OrderRecipeName(store, order), icon = recipeDetail.icon, qty = order.qty,
        status = orderBoard:Status(order), requester = order.requester, claimers = orderBoard:Claimers(order),
        createdAt = order.createdAt, closedAt = order.closedAt, closedBy = order.closedBy, note = escape(order.note or ""),
        reagents = recipeDetail.reagents, tools = escapeAll(catalogEntry and catalogEntry.tools or {}),
        crafters = recipeDetail.crafters }
end

-- "6x Copper Bar, 3x Linen Cloth" (escaped) for a mail entry's flat item list; "" when it lists none
---@param items integer[]|nil
---@param itemName fun(itemID: integer): string|nil
---@return string
function Model.MailItemsText(items, itemName)
    if type(items) ~= "table" or #items == 0 then return "" end
    local itemMap = {}
    for index = 1, #items - 1, 2 do itemMap[items[index]] = (itemMap[items[index]] or 0) + items[index + 1] end
    return Model.ItemListText(itemMap, itemName)
end

-- Can I mark the order's mail by hand in the order window? The item: an active claimer (not the requester) while the
-- order is live and not yet mailed. Reagents: the requester while someone else claims it. Returns the recipient for
-- each (nil = not possible).
---@param orderBoard OrderBoard
---@param order Order
---@param myName string|nil
---@return string|nil itemRecipient
---@return string|nil matsRecipient
function Model.MarkMailTargets(orderBoard, order, myName)
    local status = orderBoard:Status(order)
    if not myName or not Model.OrderIsLive(status) then return nil, nil end
    local myClaim = order.claims[myName]
    local itemRecipient = (status ~= "mailed" and myClaim and myClaim.state == "claimed" and order.requester ~= myName)
        and order.requester or nil
    local matsRecipient
    if order.requester == myName then
        for _, crafter in ipairs(orderBoard:Claimers(order)) do
            if crafter ~= myName then matsRecipient = crafter; break end
        end
    end
    return itemRecipient, matsRecipient
end

------------------------------------------------------------------ mail queue

---@class MailViewRow
---@field id string job id
---@field mode MailMode
---@field recipient string raw canonical name
---@field label string escaped recipe name
---@field qty integer
---@field itemsText string escaped "6x Copper Bar, 3x Linen Cloth"
---@field missingText string escaped, "" when the bags hold everything
---@field isCurrent boolean the job the open Send Mail form was filled for

-- "6x Copper Bar, 3x Linen Cloth" for an item map (sorted by name; unknown names as "item <id>")
---@param items table<integer, integer>
---@param itemName fun(itemID: integer): string|nil
---@return string
local function itemListText(items, itemName)
    local entries = {}
    for itemID, amount in pairs(items) do
        entries[#entries + 1] = { name = itemName(itemID) or ("item " .. itemID), amount = amount }
    end
    table.sort(entries, function(left, right) return left.name < right.name end)
    local parts = {}
    for index, entry in ipairs(entries) do parts[index] = entry.amount .. "x " .. entry.name end
    return escape(table.concat(parts, ", "))
end
Model.ItemListText = itemListText

-- A mail job's recipe name, raw (not escaped): looked up by recipe id in the catalog (in this client's language when
-- known), the job's own snapshot only when the catalog has no entry.
---@param store table|nil
---@param job MailJob
---@return string
function Model.MailJobRecipeName(store, job)
    local catalogEntry = store and store.GetRecipe(job.recipeID)
    if catalogEntry then return addon.Names.Recipe(job.recipeID, catalogEntry) end
    return job.label
end

-- Rows of the Mail tab: every queued job with what it carries and what the bags lack for it (the bags are counted once
-- for the whole queue, in queue order, so two jobs needing the same item do not both look complete).
---@param jobs MailJob[]
---@param mailableCounts table<integer, integer> what the bags hold, bound items excluded
---@param itemName fun(itemID: integer): string|nil
---@param currentJobID string|nil
---@param store? table the recipe names are looked up by id there (else the jobs' snapshots)
---@return MailViewRow[]
function Model.BuildMailRows(jobs, mailableCounts, itemName, currentJobID, store)
    local left = {}
    for itemID, count in pairs(mailableCounts) do left[itemID] = count end
    local rows = {}
    for _, job in ipairs(jobs) do
        local missing = {}
        for itemID, amount in pairs(job.items) do
            local have = left[itemID] or 0
            if have < amount then missing[itemID] = amount - have end
            left[itemID] = math.max(0, have - amount)
        end
        rows[#rows + 1] = { id = job.id, mode = job.mode, recipient = job.recipient, label = escape(Model.MailJobRecipeName(store, job)), qty = job.qty,
            itemsText = itemListText(job.items, itemName), missingText = next(missing) and itemListText(missing, itemName) or "",
            isCurrent = job.id == currentJobID }
    end
    return rows
end

------------------------------------------------------------------ recipe items board

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

------------------------------------------------------------------ dungeon keys and raid attunements

---@class AccessFilterState
---@field text? string
---@field me? string

---@class KeyHolderViewRow
---@field who string raw
---@field whoName string escaped short name
---@field locations string[]
---@field mine boolean

---@class KeyViewRow
---@field key integer the item id
---@field itemID integer
---@field name string escaped
---@field icon any
---@field instance string the instance it opens, viewer's language ("" when not known)
---@field holderCount integer
---@field holders KeyHolderViewRow[] sorted by name
---@field holderNames string escaped short names, comma separated
---@field mine boolean I hold it

-- escaped short names, comma separated
---@param playerNames string[]
---@return string
local function shortNameList(playerNames)
    local shortNames = {}
    for index, playerName in ipairs(playerNames) do shortNames[index] = escape(addon.Utility.ShortName(playerName) or playerName) end
    return table.concat(shortNames, ", ")
end

-- One row per key somebody in the guild holds, plus one per listed key nobody holds (holder count 0). Holder names
-- come from peers and are escaped; the item name, icon and class come from THIS client, and an id this client does not
-- take for a key is not shown (a peer cannot list arbitrary items).
---@param state AccessFilterState
---@param itemClassFunction fun(itemID: integer): any, any, any classID, subclassID, icon
---@param itemNameFunction? fun(itemID: integer): string|nil
---@return KeyViewRow[]
function Model.BuildKeyRows(state, itemClassFunction, itemNameFunction)
    local Access = addon.Access
    local searchText = sortKey(state.text)
    local keyRows = {}
    local holdersByItem = Access.KeyHolders()
    for itemID in pairs(Access.KEYS) do holdersByItem[itemID] = holdersByItem[itemID] or {} end
    for itemID, holderRows in pairs(holdersByItem) do
        local classID, _, icon = itemClassFunction(itemID)
        if Access.IsKey(itemID, classID) then
            local itemName = escape((itemNameFunction and itemNameFunction(itemID))
                or addon.Locale.Format(addon.Text["Item #{id}"], { id = itemID }))
            local instanceName = escape(Access.InstanceName(Access.KEYS[itemID]) or "")
            local holders, holderNames, mine = {}, {}, false
            for index, holderRow in ipairs(holderRows) do
                local isMine = holderRow.who == state.me
                if isMine then mine = true end
                holders[index] = { who = holderRow.who, whoName = escape(addon.Utility.ShortName(holderRow.who) or holderRow.who),
                    locations = holderRow.locations, mine = isMine }
                holderNames[index] = holderRow.who
            end
            local holderText = shortNameList(holderNames)
            local keep = searchText == "" or sortKey(itemName):find(searchText, 1, true) ~= nil
                or sortKey(instanceName):find(searchText, 1, true) ~= nil or sortKey(holderText):find(searchText, 1, true) ~= nil
            if keep then
                keyRows[#keyRows + 1] = { key = itemID, itemID = itemID, name = itemName, icon = icon, instance = instanceName,
                    holderCount = #holders, holders = holders, holderNames = holderText, mine = mine }
            end
        end
    end
    return keyRows
end

-- Whom a key row's whisper goes to: the first holder who is not me (nil when only I hold it).
---@param keyRow KeyViewRow
---@param myName string|nil
---@return string|nil raw player name
function Model.KeyContact(keyRow, myName)
    for _, holder in ipairs(keyRow and keyRow.holders or {}) do
        if holder.who ~= myName then return holder.who end
    end
    return nil
end

---@class AttunementViewRow
---@field key string attunement key
---@field name string instance name, viewer's language
---@field icon any
---@field attunedCount integer
---@field attuned string escaped short names of who holds it
---@field attunedRaw string[]
---@field missingCount integer
---@field missing string escaped short names of who is known not to hold it
---@field mine boolean|nil I hold it (nil: not known)

-- One row per attunement, always all of them (also with nobody attuned yet), so the list shows what can be tracked.
---@param state AccessFilterState
---@param itemClassFunction? fun(itemID: integer): any, any, any classID, subclassID, icon
---@return AttunementViewRow[]
function Model.BuildAttunementRows(state, itemClassFunction)
    local Access = addon.Access
    local searchText = sortKey(state.text)
    local statusByKey = Access.AttunementStatus()
    local myRecord = state.me and Access.Get(state.me)
    local attunementRows = {}
    for _, attunement in ipairs(Access.ATTUNEMENTS) do
        local status = statusByKey[attunement.key]
        local instanceName = escape(Access.InstanceName(attunement.instance) or attunement.key)
        local attunedText, missingText = shortNameList(status.yes), shortNameList(status.no)
        local keep = searchText == "" or sortKey(instanceName):find(searchText, 1, true) ~= nil
            or sortKey(attunedText):find(searchText, 1, true) ~= nil or sortKey(missingText):find(searchText, 1, true) ~= nil
        if keep then
            local icon = attunement.icon
            if attunement.item and itemClassFunction then icon = select(3, itemClassFunction(attunement.item)) or icon end
            local mine = nil
            if myRecord and myRecord.att[attunement.key] ~= nil then mine = myRecord.att[attunement.key] end
            attunementRows[#attunementRows + 1] = { key = attunement.key, name = instanceName, icon = icon,
                attunedCount = #status.yes, attuned = attunedText, attunedRaw = status.yes, missingCount = #status.no,
                missing = missingText, mine = mine }
        end
    end
    return attunementRows
end

------------------------------------------------------------------ faction standings

---@class ReputationFilterState
---@field text? string free-text search
---@field me? string
---@field faction? integer only this faction (nil: all)

---@class ReputationLookups
---@field factionName? fun(factionID: integer): string|nil the faction's name in the viewer's client
---@field standingLabel? fun(standing: integer): string|nil the client's label of a standing

---@class ReputationViewRow
---@field key string owner .. "#" .. faction id
---@field factionID integer
---@field name string faction name, viewer's language
---@field icon string
---@field who string raw owner name
---@field playerName string escaped short name
---@field standing integer 1 Hated .. 8 Exalted
---@field standingLabel string
---@field standingRank number sorts by level, then progress
---@field progress integer
---@field size integer
---@field progressText string "4200/12000"
---@field updated integer the record's revision (server time of its last shared change)
---@field mine boolean

-- this addon's standing labels in the viewer's language, used when the client has none (index = standing)
---@return string[]
local function standingLabels()
    local Text = addon.Text
    return { Text["Hated"], Text["Hostile"], Text["Unfriendly"], Text["Neutral"], Text["Friendly"], Text["Honored"],
        Text["Revered"], Text["Exalted"] }
end

-- The label of a standing in the viewer's language: the client's own label, else this addon's translation.
---@param standing integer
---@param lookups? ReputationLookups
---@return string
function Model.StandingLabel(standing, lookups)
    local label = lookups and lookups.standingLabel and lookups.standingLabel(standing)
    if type(label) == "string" and label ~= "" then return label end
    return standingLabels()[standing] or tostring(standing)
end

-- The faction's name in the viewer's language: the client's name, else the English name of the hint data.
---@param factionID integer
---@param lookups? ReputationLookups
---@return string
function Model.FactionName(factionID, lookups)
    local name = lookups and lookups.factionName and lookups.factionName(factionID)
    if type(name) == "string" and name ~= "" then return name end
    local faction = addon.FactionHints.Faction(factionID)
    return faction and faction.name or ("#" .. tostring(factionID))
end

-- One row per member and faction over every known record. Owner names come from peers and are escaped; faction names
-- and standing labels from this client or this addon. The search matches every word in faction (also its English
-- name), player and standing.
---@param state ReputationFilterState
---@param lookups? ReputationLookups
---@return ReputationViewRow[]
function Model.BuildReputationRows(state, lookups)
    local FactionHints = addon.FactionHints
    local searchWords = Model.SearchWords(state.text)
    local factionNames = {}
    local reputationRows = {}
    for owner, reputationRecord in pairs(addon.Store.db.rep) do
        local playerName = escape(addon.Utility.ShortName(owner) or owner)
        for factionID, standing in pairs(reputationRecord.f) do
            local faction = FactionHints.Faction(factionID)
            if faction and (state.faction == nil or state.faction == factionID) then
                factionNames[factionID] = factionNames[factionID] or escape(Model.FactionName(factionID, lookups))
                local standingLabel = escape(Model.StandingLabel(standing.s, lookups))
                if Model.MatchesWords(searchWords, { factionNames[factionID], faction.name, playerName, standingLabel }) then
                    reputationRows[#reputationRows + 1] = { key = owner .. "#" .. factionID, factionID = factionID,
                        name = factionNames[factionID], icon = faction.icon, who = owner, playerName = playerName,
                        standing = standing.s, standingLabel = standingLabel,
                        standingRank = standing.s + (standing.m > 0 and standing.v / standing.m or 0) * 0.999,
                        progress = standing.v, size = standing.m, progressText = standing.v .. "/" .. standing.m,
                        updated = reputationRecord.rev, mine = owner == state.me }
                end
            end
        end
    end
    return reputationRows
end

---@class FactionChoice
---@field id integer
---@field name string escaped

-- The factions somebody in the guild has a standing with, sorted by name (the faction filter dropdown).
---@param lookups? ReputationLookups
---@return FactionChoice[]
function Model.ReputationFactions(lookups)
    local seen, factionChoices = {}, {}
    for _, reputationRecord in pairs(addon.Store.db.rep) do
        for factionID in pairs(reputationRecord.f) do
            if not seen[factionID] and addon.FactionHints.Faction(factionID) then
                seen[factionID] = true
                factionChoices[#factionChoices + 1] = { id = factionID, name = escape(Model.FactionName(factionID, lookups)), key = factionID }
            end
        end
    end
    table.sort(factionChoices, byNameThenKey)
    return factionChoices
end

---@class FactionHintLine
---@field standing integer
---@field label string standing label, viewer's language
---@field text string hint text, viewer's language
---@field state "reached"|"next"|"later" relative to the given standing (nil standing: every line "later")
---@field items integer[]

-- The hint lines of a faction for the tooltip, marked against a player's standing.
---@param factionID integer
---@param standing integer|nil
---@param languageCode string|nil
---@param lookups? ReputationLookups
---@return FactionHintLine[]
function Model.FactionHintLines(factionID, standing, languageCode, lookups)
    local FactionHints = addon.FactionHints
    local faction = FactionHints.Faction(factionID)
    local nextHint = FactionHints.NextHint(factionID, standing)
    local hintLines = {}
    for _, hint in ipairs(faction and faction.hints or {}) do
        local state = "later"
        if standing and hint.standing <= standing then state = "reached" elseif hint == nextHint and standing then state = "next" end
        hintLines[#hintLines + 1] = { standing = hint.standing, label = Model.StandingLabel(hint.standing, lookups),
            text = FactionHints.HintText(hint, languageCode), state = state, items = hint.items or {} }
    end
    return hintLines
end

------------------------------------------------------------------ craft and whisper from lists

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

------------------------------------------------------------------ craft cooldowns (Misc Items, Cooldowns mode)

-- Short time left for a tile, like an action button: "2d", "5h", "12m", "40s".
---@param seconds number
---@return string
function Model.FormatCooldownShort(seconds)
    if seconds >= 86400 then return math.floor(seconds / 86400) .. "d" end
    if seconds >= 3600 then return math.floor(seconds / 3600) .. "h" end
    if seconds >= 60 then return math.ceil(seconds / 60) .. "m" end
    return math.max(math.ceil(seconds), 0) .. "s"
end

-- Time left for a tooltip: "2d 4h", "3h 12m", "12:30".
---@param seconds number
---@return string
function Model.FormatCooldownLong(seconds)
    seconds = math.max(math.floor(seconds + 0.5), 0)
    if seconds >= 86400 then return ("%dd %dh"):format(math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)) end
    if seconds >= 3600 then return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

---@class CooldownLookups
---@field isOnline? fun(playerName: string): boolean|nil
---@field spellName? fun(spellID: integer): string|nil
---@field itemName? fun(itemID: integer): string|nil
---@field itemIcon? fun(itemID: integer): any

-- The craft's name in the viewer's language: "Transmute" for the shared transmute cooldown, else the recipe's or the
-- crafted item's name from this client, else the English name from the data file.
---@param group CraftCooldownGroup
---@param lookups? CooldownLookups
---@return string
function Model.CooldownGroupName(group, lookups)
    lookups = lookups or {}
    if group.key == "transmute" then return addon.Text["Transmute"] end
    local name = #group.recipes == 1 and lookups.spellName and lookups.spellName(group.recipes[1])
    name = name or (lookups.itemName and lookups.itemName(group.produces))
    return escape(name or group.name)
end

---@alias CooldownState "ready"|"cooling"|"unknown"

---@class CooldownCrafter
---@field who string raw player name
---@field playerName string escaped short name
---@field state CooldownState
---@field readyAt? integer my clock; nil when unknown
---@field remaining number seconds left (0 unless cooling)
---@field estimated boolean the ready time comes from a seen cast, not from the game's cooldown
---@field seen? integer my clock when the record was last received or read
---@field online boolean
---@field mine boolean

---@class CooldownTile
---@field key string group key (expanded tiles: group key .. "#" .. player)
---@field group CraftCooldownGroup
---@field name string escaped craft name, viewer's language
---@field profession string profession label, viewer's language
---@field icon any
---@field crafters CooldownCrafter[] best first
---@field best? CooldownCrafter whom a click whispers: online, not me, the best state
---@field readyCount integer crafters ready right now
---@field state "ready"|"cooling"|"unknown"|"none"
---@field remaining number seconds until the soonest crafter is ready (cooling tiles)
---@field duration number the length of the shown cooldown (for the sweep)
---@field estimated boolean the shown cooldown is an estimate
---@field mine boolean I am one of the crafters

local STATE_RANK = { ready = 0, unknown = 1, cooling = 2 }

---@param left CooldownCrafter
---@param right CooldownCrafter
---@return boolean
local function crafterOrder(left, right)
    if left.online ~= right.online then return left.online end
    if left.state ~= right.state then return STATE_RANK[left.state] < STATE_RANK[right.state] end
    if left.state == "cooling" and left.remaining ~= right.remaining then return left.remaining < right.remaining end
    return left.playerName < right.playerName
end

-- One tile per timegated craft, in the data file's order. Crafters are everyone whose synced recipes contain the craft,
-- plus everyone whose cooldown record lists it (item groups: whoever holds the item). Names come from peers and are
-- escaped; craft names and icons come from this client.
---@param state { text?: string, me?: string, now: integer }
---@param lookups? CooldownLookups
---@return CooldownTile[]
function Model.BuildCooldownTiles(state, lookups)
    lookups = lookups or {}
    local CraftCooldowns, database = addon.CraftCooldowns, addon.Store.db
    local now, searchWords = state.now, Model.SearchWords(state.text)
    local groupsByCharacter = {}
    for playerName, characterRecord in pairs(database.chars) do groupsByCharacter[playerName] = CraftCooldowns.GroupsOfCharacter(characterRecord) end
    local tiles = {}
    for _, group in ipairs(CraftCooldowns.GROUPS) do
        local crafterNames = {}
        for playerName, groups in pairs(groupsByCharacter) do if groups[group.key] then crafterNames[playerName] = true end end
        for playerName, cooldownRecord in pairs(database.cds) do
            if cooldownRecord.c[group.key] ~= nil then crafterNames[playerName] = true end
        end
        local crafters, readyCount, mine, allNames = {}, 0, false, {}
        for playerName in pairs(crafterNames) do
            local cooldownRecord = database.cds[playerName]
            local readyAt = cooldownRecord and cooldownRecord.c[group.key]
            local crafterState = readyAt == nil and "unknown" or (readyAt <= now and "ready") or "cooling"
            local isMine = playerName == state.me
            local crafter = { who = playerName, playerName = escape(addon.Utility.ShortName(playerName) or playerName),
                state = crafterState, readyAt = readyAt, remaining = crafterState == "cooling" and readyAt - now or 0,
                estimated = cooldownRecord and cooldownRecord.e[group.key] == true or false,
                seen = cooldownRecord and cooldownRecord.seen, mine = isMine,
                online = isMine or (lookups.isOnline and lookups.isOnline(playerName) == true) or false }
            if crafterState == "ready" then readyCount = readyCount + 1 end
            if isMine then mine = true end
            crafters[#crafters + 1] = crafter
            allNames[#allNames + 1] = crafter.playerName
        end
        table.sort(crafters, crafterOrder)
        local name = Model.CooldownGroupName(group, lookups)
        local profession = escape(addon.Names.Profession(group.skillLine))
        if Model.MatchesWords(searchWords, { name, group.name, profession, table.concat(allNames, " ") }) then
            local tile = { key = group.key, group = group, name = name, profession = profession, crafters = crafters,
                readyCount = readyCount, mine = mine, remaining = 0, duration = group.fallback, estimated = false,
                icon = lookups.itemIcon and lookups.itemIcon(group.produces) or nil }
            for _, crafter in ipairs(crafters) do
                if crafter.online and not crafter.mine then tile.best = crafter break end
            end
            if #crafters == 0 then tile.state = "none"
            elseif readyCount > 0 then tile.state = "ready"
            else
                -- the soonest cooldown among the crafters (online ones first: they are the ones who can be asked)
                local soonest
                for _, crafter in ipairs(crafters) do
                    if crafter.state == "cooling" and (not soonest or (crafter.online and not soonest.online)
                        or (crafter.online == soonest.online and crafter.remaining < soonest.remaining)) then
                        soonest = crafter
                    end
                end
                if soonest then
                    tile.state, tile.remaining, tile.estimated = "cooling", soonest.remaining, soonest.estimated
                    tile.duration = math.max(group.fallback, soonest.remaining)
                else
                    tile.state = "unknown"
                end
            end
            tiles[#tiles + 1] = tile
        end
    end
    return tiles
end

-- One tile per crafter instead of one per craft (the grid's "every crafter" view), crafters in the same order.
---@param tiles CooldownTile[]
---@return CooldownTile[]
function Model.ExpandCooldownTiles(tiles)
    local expanded = {}
    for _, tile in ipairs(tiles) do
        for _, crafter in ipairs(tile.crafters) do
            local crafterState = crafter.state
            expanded[#expanded + 1] = { key = tile.key .. "#" .. crafter.who, group = tile.group, name = tile.name,
                profession = tile.profession, icon = tile.icon, crafters = { crafter },
                best = (crafter.online and not crafter.mine) and crafter or nil, readyCount = crafterState == "ready" and 1 or 0,
                state = crafterState, remaining = crafter.remaining, estimated = crafter.estimated, mine = crafter.mine,
                duration = math.max(tile.group.fallback, crafter.remaining), crafter = crafter }
        end
    end
    return expanded
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

------------------------------------------------------------------ member builds (live build, one viewer)

-- The "member builds" button (bottom left of the window) is for one maintainer character only. The repository is
-- public and holds no real character names, so the name is kept as a hash (djb2 of the lower-case name without realm).
-- Not a secret or a security boundary: the list only shows what this client already received.
Model.BUILD_VIEWER_HASHES = { [3558222112] = true }

-- djb2 (mod 2^32) of `text`
---@param text string
---@return integer
function Model.NameHash(text)
    local hash = 5381
    for index = 1, #text do hash = (hash * 33 + text:byte(index)) % 4294967296 end
    return hash
end

-- Whether `playerName` ("Name" or "Name-Realm") may see the member builds button.
---@param playerName any
---@return boolean
function Model.IsBuildViewer(playerName)
    if type(playerName) ~= "string" or playerName == "" then return false end
    local shortName = (playerName:match("^([^%-]+)") or playerName):lower():match("^%s*(.-)%s*$")
    return Model.BUILD_VIEWER_HASHES[Model.NameHash(shortName)] == true
end

---@class MemberBuildRow
---@field name string escaped player name
---@field ver string|nil the build from their last HELLO this session (nil: none seen, e.g. a build before 1.0.1)
---@field t integer last time a message from them arrived (or their HELLO)
---@field messages integer messages from them in the trace

-- Everyone who sent me an addon message (the trace's "in" entries, newest first as Trace.List gives them) and the build
-- each one announced (Channel.PeerVersions rows), most recent first. Pure.
---@param inboundEntries table[] TraceEntry list (dir "in")
---@param versionRows table[] { name, ver, t }
---@return MemberBuildRow[]
function Model.MemberBuilds(inboundEntries, versionRows)
    local byName, rows = {}, {}
    local function rowFor(playerName)
        local row = byName[playerName]
        if not row then
            row = { name = escape(playerName), t = 0, messages = 0 }
            byName[playerName] = row; rows[#rows + 1] = row
        end
        return row
    end
    for _, traceEntry in ipairs(inboundEntries or {}) do
        if type(traceEntry) == "table" and type(traceEntry.peer) == "string" and traceEntry.peer ~= "" then
            local row = rowFor(traceEntry.peer)
            row.messages = row.messages + 1
            if type(traceEntry.t) == "number" and traceEntry.t > row.t then row.t = traceEntry.t end
        end
    end
    for _, versionRow in ipairs(versionRows or {}) do
        if type(versionRow) == "table" and type(versionRow.name) == "string" and versionRow.name ~= "" then
            local row = rowFor(versionRow.name)
            row.ver = type(versionRow.ver) == "string" and escape(versionRow.ver) or nil
            if type(versionRow.t) == "number" and versionRow.t > row.t then row.t = versionRow.t end
        end
    end
    table.sort(rows, function(left, right)
        if left.t ~= right.t then return left.t > right.t end
        return left.name < right.name
    end)
    return rows
end
