local addonName, addon = ...

-- Standalone window: "Recipes" tab (filter, search, reagents, crafters, request), "Orders" tab (shared board),
-- "Available" tab (recipe items guild members hold, with dibs) and "Debug" tab
-- (network trace, diagnostic export). The tabs are one ordered list (tabDefinitions).
-- Plain frames only, except the secure profession and Craft buttons. Those live in UI/SecureDock.lua's holder while in
-- combat (a window with secure children is protected and could not be shown or hidden in combat), so the window can be
-- opened, closed and switched in a fight. All text goes through Text (Locales/); game names are resolved for this client by Model/Names.
-- tests/test_locale_files.lua fails on a hardcoded label.
---@class UIModule
local UI = {}
addon.UI = UI

local Text, Format, Plural = addon.Text, addon.Locale.Format, addon.Locale.Plural

-- widget helpers shared with other addons: LibGuildSync-1.0 Widgets (LibGuildSync/Widgets.lua)
local Widgets = LibStub("LibGuildSync-1.0").Widgets
local ROW_HEIGHT = Widgets.ROW_HEIGHT
local createFontString, createButton, setButtonLabel = Widgets.CreateFontString, Widgets.CreateButton, Widgets.SetButtonLabel
local createSelectableRow = Widgets.CreateSelectableRow
-- feature 016: lists that follow the (resizable) window, the Recipes table
local Table, RecipeTable = addon.Table, addon.RecipeTable
local createScrollList = Table.CreateResizableList
---@return table|nil the SavedVariables ui table (column, sort and window size settings)
local function interfaceSettings() return addon.db and addon.db.ui end
---@param timestamp integer|nil
---@return string
-- the four templates Widgets.TimeAgo reads from Text: Text["just now"], Text["{n}m ago"], Text["{n}h ago"], Text["{n}d ago"]
local function timeAgo(timestamp) return Widgets.TimeAgo(timestamp, Text) end
---@param frameName string
---@return table
local function createDialogFrame(frameName) return Widgets.CreateDialogFrame(frameName, addon.Log) end
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
---@type { count: integer, showIcon: boolean, hideNumber: boolean } feature 010: unseen orders (UI.SetNotice)
local noticeState = { count = 0, showIcon = false, hideNumber = false }

---@class WindowState
local windowState = {
    tab = "recipes",
    professionIndex = 0,           -- 0 = all, else index into the professions list ({ key, name })
    text = "",
    mineOnly = false,
    categories = {},               -- feature 011: checked category keys (Model.CategoryKey); empty = all
    selectedRecipe = nil,
    orderFilterIndex = 1,
    showClosed = false,
    selectedOrder = nil,
    offerText = "",
    offerMyProfessionsOnly = false,
    selectedOffer = nil,
    debugFilterIndex = 1,
    debugView = "trace",           -- "trace" (message log) | "names" (name check table)
}

---@return { [1]: OrderFilterKey, [2]: string }[]
local function orderFilters()
    return { { "all", Text["All"] }, { "open", Text["Open"] }, { "mine", Text["My requests"] }, { "crafting", Text["I'm crafting"] },
        { "can", Text["I can craft"] } }
end
---@type table<OrderStatus, string>
local STATUS_COLOR = { open = "ffd100", claimed = "33ff99", done = "888888", cancelled = "ff5555" }
---@param status OrderStatus
---@return string
local function statusLabel(status)
    local labels = { open = Text["Open"], claimed = Text["Claimed"], done = Text["Done"], cancelled = Text["Cancelled"] }
    return labels[status] or status
end

---@return string|nil
local function me() return addon.Utility.Me() end
-- display form of a character name (realm hidden on my own realm)
---@param playerName string|nil
---@return string|nil
local function shortName(playerName) return addon.Utility.ShortName(playerName) end

---@param className string|nil
---@param label string
---@return string
local function inClassColor(className, label)
    local classColor = className and RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]
    if classColor then return ("|cff%02x%02x%02x%s|r"):format(classColor.r * 255, classColor.g * 255, classColor.b * 255, label) end
    return label
end







------------------------------------------------------------------ frame

---@type table|nil the main window
local mainFrame
local recipeList, orderList, offerList
local refreshDebug   -- Debug tab (defined with the tab below)
---@type OfferViewRow[]
local currentOfferRows = {}
---@type table recipe detail panel widgets
local detailPanel = {}

---@return ProfessionChoice[]
local function professionChoices() return addon.Model.Professions(addon.Store) end

-- feature 011: client item data for categories and the free-text search (looked up when called; Api loads before UI)
---@type fun(recipeID: integer): string|nil feature 017: effect text of a recipe without an item, defined with the recipe tooltip below
local recipeEffectText
---@type RecipeLookups
local itemLookups = {
    class = function(itemID) return addon.Api.ItemCategoryInformation(itemID) end,
    label = function(categoryKey) return addon.Api.CategoryLabel(categoryKey) end,
    groupLabel = function(groupID) return addon.Api.CategoryGroupLabel(groupID) end,
    text = function(itemID) return addon.ItemText.Get(itemID) end,
    itemDetails = function(itemID) return addon.Api.ItemDetails(itemID) end,   -- feature 016: quality, item level, required level
    effect = function(recipeID) return recipeEffectText(recipeID) end,          -- feature 017: enchant effect text (search)
}
---@type RecipeCell[] the Recipes table's current column positions (feature 016)
local recipeCells = {}
---@type boolean item data arrived since the last Recipes redraw (redrawn debounced by the tab's OnUpdate)
local itemInfoArrived = false

-- Modern menu dropdowns (Blizzard_Menu: WowStyle1DropdownTemplate, checkbox menus; present on Forever, see
-- docs/api-findings.md). nil when the client lacks them; callers then fall back to plain cycle buttons.
---@param parent table
---@param template string
---@param width number
---@return table|nil
local function createMenuDropdown(parent, template, width)
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, template)
    if not ok or type(dropdown) ~= "table" or not dropdown.SetupMenu then
        addon.Log.Debug("window.dropdown", "the client has no menu dropdown; a cycle button is used", { template = template })
        return nil
    end
    dropdown:SetWidth(width)
    return dropdown
end

---@param dropdown table
---@param label string
local function setDropdownText(dropdown, label)
    if dropdown.SetLabel then dropdown:SetLabel(label)                 -- fallback button
    elseif dropdown.OverrideText then dropdown:OverrideText(label)
    elseif dropdown.SetText then dropdown:SetText(label)
    elseif dropdown.Text and dropdown.Text.SetText then dropdown.Text:SetText(label) end
end

------------------------------------------------------------------ profession scan buttons
-- The game only exposes a profession's recipes while its window is open, and addon code may not open it (blocked,
-- "Interface-Aktion auf Grund eines Addons fehlgeschlagen"). A REAL click on a secure button may: each button is the
-- macro "/cast <profession>". Opening the window triggers the normal scan, so one click per profession reads it.
---@class ProfessionBar
---@field buttons table[]
---@field rows OwnProfessionRow[]
---@field needsUpdateAfterCombat boolean
---@field clickedAt number|nil GetTime() of the last click
---@field loggedSpellbookSummary string|nil
local professionBar = { buttons = {}, rows = {}, needsUpdateAfterCombat = false }
local MAXIMUM_PROFESSION_BUTTONS = 5

---@param professionButton table
local function showProfessionButtonTooltip(professionButton)
    local professionRow = professionButton.professionRow
    if not professionRow then return end
    GameTooltip:SetOwner(professionButton, "ANCHOR_LEFT")
    GameTooltip:SetText(professionRow.name)
    GameTooltip:AddLine(("%d/%d"):format(professionRow.rank or 0, professionRow.max or 0), 1, 1, 1)
    if professionRow.count > 0 then
        GameTooltip:AddLine(Plural(professionRow.count, Text["{n} recipe"], Text["{n} recipes"]), 0.2, 1, 0.6)
    else
        GameTooltip:AddLine(Text["not scanned yet"], 1, 0.4, 0.4)
    end
    GameTooltip:AddLine(Text["Click to open this profession and read its recipes."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

---@param parent table
---@param buttonIndex integer
---@return table|nil
local function createProfessionButton(parent, buttonIndex)
    -- created in the dock's holder; SecureDock.Register below moves it into the window (out of combat only)
    local ok, professionButton = pcall(CreateFrame, "Button", nil, addon.SecureDock.Holder(), "SecureActionButtonTemplate")
    if not ok or not professionButton then
        addon.Log.Error("window.professionBar", "a secure profession button could not be created", { error = tostring(professionButton) })
        return nil
    end
    professionButton:SetSize(24, 24)
    professionButton:RegisterForClicks("AnyUp", "AnyDown")
    professionButton.icon = professionButton:CreateTexture(nil, "ARTWORK"); professionButton.icon:SetAllPoints()
    professionButton.recipeCountText = createFontString(professionButton, "GameFontNormalSmall", "RIGHT")
    professionButton.recipeCountText:SetPoint("BOTTOMRIGHT", 0, 1)
    professionButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    professionButton:SetScript("OnEnter", showProfessionButtonTooltip)
    professionButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- log every click (PostClick runs after the secure action; it does not touch it)
    professionButton:HookScript("PostClick", function(self)
        professionBar.clickedAt = GetTime and GetTime() or 0
        local professionRow = self.professionRow
        addon.Log.Debug("window.professionBar", "a profession button was clicked", {
            profession = professionRow and professionRow.name,
            macro = professionRow and (addon.Model.CastMacro(professionRow):gsub("\n", " / ")) })
    end)
    professionButton:Hide()
    local previousButton = professionBar.buttons[buttonIndex - 1]
    addon.SecureDock.Register(professionButton, parent, function(button)
        if buttonIndex == 1 or not previousButton then button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        else button:SetPoint("RIGHT", previousButton, "LEFT", -4, 0) end
    end)
    return professionButton
end

-- true for 6 seconds after a click on a profession button (used to attribute the game's error messages)
---@return boolean
function UI.RecentBarClick()
    return professionBar.clickedAt ~= nil and GetTime and (GetTime() - professionBar.clickedAt) < 6 or false
end

-- once per profession set and session: what the spellbook says about each profession (names, ids, passive flag), so a
-- button that opens nothing (Skinning) can be diagnosed from SavedVariables without typing commands
---@param liveProfessions PlayerProfession[]
local function logSpellbookProfessions(liveProfessions)
    local professionSummaries = {}
    for _, liveProfession in ipairs(liveProfessions) do
        local spellSummaries = {}
        for _, spellBookEntry in ipairs(liveProfession.spellEntries or {}) do
            spellSummaries[#spellSummaries + 1] = ("%s#%s%s"):format(spellBookEntry.name, tostring(spellBookEntry.spellID),
                spellBookEntry.passive and "(passive)" or "")
        end
        professionSummaries[#professionSummaries + 1] = ("%s#%s offset=%s count=%s spells=[%s]"):format(liveProfession.name,
            tostring(liveProfession.id), tostring(liveProfession.spellOffset), tostring(liveProfession.spellCount),
            table.concat(spellSummaries, ","))
    end
    local summary = table.concat(professionSummaries, " ; ")
    if summary ~= professionBar.loggedSpellbookSummary then
        professionBar.loggedSpellbookSummary = summary
        addon.Log.Debug("window.professionBar", "own professions as the spellbook reports them", { professions = summary })
    end
end

-- Attributes and visibility of secure frames may not change in combat: then only the counters are updated and the
-- rest is applied when combat ends (PLAYER_REGEN_ENABLED).
local function refreshProfessionBar()
    if not mainFrame then return end
    local liveProfessions = addon.Api.GetPlayerProfessions() or {}
    logSpellbookProfessions(liveProfessions)
    professionBar.rows = addon.Model.OwnProfessions(addon.Store, me(), liveProfessions)
    local inCombat = addon.Api.InCombat()
    if inCombat then professionBar.needsUpdateAfterCombat = true end
    for buttonIndex = 1, MAXIMUM_PROFESSION_BUTTONS do
        local professionButton, professionRow = professionBar.buttons[buttonIndex], professionBar.rows[buttonIndex]
        if professionButton then
            if professionRow then
                professionButton.professionRow = professionRow
                professionButton.icon:SetTexture(professionRow.icon)
                professionButton.recipeCountText:SetText(professionRow.count)
                if professionRow.count > 0 then
                    professionButton.recipeCountText:SetTextColor(0.2, 1, 0.6); professionButton.icon:SetVertexColor(1, 1, 1)
                else
                    professionButton.recipeCountText:SetTextColor(1, 0.3, 0.3); professionButton.icon:SetVertexColor(1, 0.55, 0.55)
                end
                if not inCombat then
                    professionButton:SetAttribute("type", "macro")
                    professionButton:SetAttribute("macrotext", addon.Model.CastMacro(professionRow))
                    professionButton:Show()
                end
            elseif not inCombat then
                professionButton.professionRow = nil
                professionButton:Hide()
            end
        end
    end
    if not inCombat then professionBar.needsUpdateAfterCombat = false end
    -- pulsing "CLICK HERE ->" to the left of the leftmost button while every profession is still at 0
    local leftmostButton = professionBar.buttons[math.min(#professionBar.rows, MAXIMUM_PROFESSION_BUTTONS)]
    if mainFrame.scanHint then
        if leftmostButton and addon.Model.NeedsScanHint(professionBar.rows) then
            mainFrame.scanHintText:ClearAllPoints()
            mainFrame.scanHintText:SetPoint("RIGHT", leftmostButton, "LEFT", -10, 0)
            mainFrame.scanHint:Show()
        else
            mainFrame.scanHint:Hide()
        end
    end
    if mainFrame.recipesEmptyText then
        mainFrame.recipesEmptyText:SetShown(#professionChoices() == 0)
    end
end

-- the current Recipes tab filter (feature 011 adds categories); also used to build the category menu
---@return RecipeFilterState filter
---@return ProfessionChoice|nil selectedProfession
---@return ProfessionChoice[] choices
local function currentRecipeFilter()
    local choices = professionChoices()
    if windowState.professionIndex > #choices then windowState.professionIndex = 0 end
    local selectedProfession = choices[windowState.professionIndex]
    return { profession = selectedProfession and selectedProfession.key, text = windowState.text, mineOnly = windowState.mineOnly,
        me = me(), categories = windowState.categories }, selectedProfession, choices
end

local function refreshRecipes()
    if not mainFrame or windowState.tab ~= "recipes" then return end
    local filter, selectedProfession, choices = currentRecipeFilter()
    setDropdownText(mainFrame.professionButton, Format(Text["Profession: {name}"], { name = selectedProfession and selectedProfession.name or Text["All"] }))
    local selectedCategoryCount = addon.Utility.Count(windowState.categories)
    setDropdownText(mainFrame.categoryButton, selectedCategoryCount > 0
        and Format(Text["Category ({n})"], { n = selectedCategoryCount }) or Text["Category"])
    local recipeRows = addon.Model.BuildRecipeRows(addon.Store, filter, addon.Api.ItemName, itemLookups)
    RecipeTable.Sort(recipeRows, RecipeTable.GetSort(interfaceSettings()))
    itemInfoArrived = false
    recipeList.onLayout(recipeList)   -- the column choice may have changed in the options
    recipeList:SetData(recipeRows)
    mainFrame.recipeCountText:SetText(Plural(#recipeRows, Text["{n} recipe"], Text["{n} recipes"]))
    -- nothing cached anywhere yet: say how to fill it (recipes are only readable while a profession window is open)
    mainFrame.recipesEmptyText:SetShown(#choices == 0)
end

local function refreshDetail()
    if not mainFrame or windowState.tab ~= "recipes" then return end
    local recipeID = windowState.selectedRecipe
    local recipeDetail = recipeID and addon.Model.RecipeDetail(addon.Store, recipeID, addon.Api.ItemCount, addon.Api.ItemName)
    detailPanel.title:SetText(recipeDetail and recipeDetail.name or Text["Select a recipe"])
    detailPanel.icon:SetTexture(recipeDetail and recipeDetail.icon or nil)
    -- feature 017: the effect of a recipe without an item (enchant), one line under the title; full text in the tooltip
    local catalogEntry = recipeID and addon.Store.GetRecipe(recipeID)
    local effectText = recipeID and not (catalogEntry and catalogEntry.produces) and recipeEffectText(recipeID)
    detailPanel.effectText:SetText(effectText and addon.Utility.Escape(effectText) or "")
    detailPanel.reagentsLabel:SetShown(recipeDetail ~= nil)
    for lineIndex, reagentLine in ipairs(detailPanel.reagentLines) do
        local reagentRow = recipeDetail and recipeDetail.reagents[lineIndex]
        if reagentRow then
            reagentLine.itemID = reagentRow.itemID
            reagentLine.icon:SetTexture(addon.Api.ItemIcon(reagentRow.itemID))
            local haveColor = reagentRow.enough and "33ff99" or "ff6666"
            reagentLine.label:SetText(("%s x%d  |cff%s(%s)|r"):format(reagentRow.name, reagentRow.count, haveColor,
                Format(Text["have {n}"], { n = reagentRow.have })))
            reagentLine:Show()
        else
            reagentLine:Hide()
        end
    end
    detailPanel.noReagentsText:SetShown(recipeDetail ~= nil and #recipeDetail.reagents == 0)
    detailPanel.craftersLabel:SetShown(recipeDetail ~= nil)
    for lineIndex, crafterLine in ipairs(detailPanel.crafterLines) do
        local crafterRow = recipeDetail and recipeDetail.crafters[lineIndex]
        if crafterRow then
            crafterLine.crafterName = crafterRow.name
            crafterLine.label:SetText(("%s  |cffaaaaaa%s %d/%d, %s|r"):format(inClassColor(crafterRow.class, shortName(crafterRow.name)),
                crafterRow.professionName or crafterRow.profession, crafterRow.rank or 0, crafterRow.max or 0, timeAgo(crafterRow.rev)))
            crafterLine:Show()
        else
            crafterLine:Hide()
        end
    end
    detailPanel.moreCraftersText:SetText(recipeDetail and #recipeDetail.crafters > #detailPanel.crafterLines
        and Format(Text["+{n} more"], { n = #recipeDetail.crafters - #detailPanel.crafterLines }) or "")
    for _, requestWidget in ipairs({ detailPanel.quantityBox, detailPanel.noteBox, detailPanel.requestButton }) do
        requestWidget:SetShown(recipeDetail ~= nil)
    end
end

------------------------------------------------------------------ Craft button (feature 009)
-- Crafting needs the profession window open, and only a real click on a secure button may open it (feature 005). So the
-- button has two modes, set out of combat: "open" = macro "/cast <profession>" (the window opens, then the ordered recipe
-- is selected), "craft" = no secure action, PostClick calls C_TradeSkillUI.CraftRecipe for the order's quantity.
local refreshOrders   -- defined below; the craft helpers call it
---@class CraftState
---@field mode "open"|"craft"|nil
---@field recipeID integer|nil
---@field quantity integer
---@field pendingSelection { recipeID: integer, clickedAt: number }|nil recipe to select once the window opens
---@field needsUpdateAfterCombat boolean
---@field lastClickAt number
---@field loggedRecipeID integer|nil
local craftState = { mode = nil, recipeID = nil, quantity = 1, pendingSelection = nil, needsUpdateAfterCombat = false, lastClickAt = 0 }

---@param selectedOrderRow OrderRow|nil
local function refreshCraftButton(selectedOrderRow)
    local craftButton = mainFrame and mainFrame.craftButton
    if not craftButton then return end
    -- secure frame: no attribute or state changes in combat
    if addon.Api.InCombat() then craftState.needsUpdateAfterCombat = true return end
    craftState.needsUpdateAfterCombat = false
    local craftTarget = selectedOrderRow and selectedOrderRow.canCraft
        and addon.Model.CraftTarget(addon.Store, me(), selectedOrderRow.recipeID, addon.Api.GetPlayerProfessions() or {})
    if not craftTarget then
        craftState.mode, craftState.recipeID = nil, nil
        craftButton:SetAttribute("type", nil)
        craftButton:SetLabel(Text["Craft"])
        craftButton:Disable()
        return
    end
    craftState.recipeID, craftState.quantity = selectedOrderRow.recipeID, selectedOrderRow.qty
    -- "craft" when the open profession window lists this recipe. A name compare failed in game (the button stayed on
    -- "/cast", and casting the open profession CLOSES its window: "Open profession works only sometimes").
    local openWindowHasRecipe = addon.Api.OpenWindowHasRecipe(selectedOrderRow.recipeID)
    local mode = openWindowHasRecipe and "craft" or "open"
    if mode ~= craftState.mode or selectedOrderRow.recipeID ~= craftState.loggedRecipeID then
        craftState.loggedRecipeID = selectedOrderRow.recipeID
        addon.Log.Debug("window.craft", "the Craft button changed mode", { mode = mode, recipeID = selectedOrderRow.recipeID,
            openProfession = addon.Api.OpenProfessionName(), target = craftTarget.spellName,
            tradeSkillOpen = addon.Api.open.tradeskill })
    end
    if openWindowHasRecipe then
        craftState.mode = "craft"
        craftButton:SetAttribute("type", nil)
        craftButton:SetLabel(Format(Text["Craft {qty}x"], { qty = selectedOrderRow.qty }))
    else
        craftState.mode = "open"
        craftButton:SetAttribute("type", "macro")
        craftButton:SetAttribute("macrotext", addon.Model.CastMacro(craftTarget))
        craftButton:SetLabel(Text["Open profession"])
    end
    craftButton:Enable()
end

local function onCraftButtonPostClick()
    local now = GetTime and GetTime() or 0
    if now - craftState.lastClickAt < 0.4 then return end   -- clicks are registered on down AND up: act once
    craftState.lastClickAt = now
    local recipeDisplayName = addon.Model.RecipeName(addon.Store, craftState.recipeID or 0)
    if craftState.mode == "open" then
        craftState.pendingSelection = { recipeID = craftState.recipeID, clickedAt = now }
        addon.Log.Information("window.craft", "the Craft button opens the profession for an order", { recipeID = craftState.recipeID })
    elseif craftState.mode == "craft" then
        local ok, errorMessage = addon.Api.CraftRecipe(craftState.recipeID, craftState.quantity)
        if ok then
            addon.Log.Information("window.craft", "crafting started from an order",
                { recipeID = craftState.recipeID, quantity = craftState.quantity })
            addon.Print(Format(Text["Crafting {qty}x {name}"], { qty = craftState.quantity, name = recipeDisplayName }))
        else
            addon.Log.Error("window.craft", "crafting from an order could not start",
                { recipeID = craftState.recipeID, quantity = craftState.quantity, error = tostring(errorMessage) })
            addon.Print(Text["Could not start crafting. The recipe is selected in the profession window: press its Create button."])
        end
    end
end

-- profession window opened or closed: select the pending recipe, then switch the button's mode
---@param isOpen boolean
local function onTradeSkillWindow(isOpen)
    local pendingSelection = craftState.pendingSelection
    if isOpen and pendingSelection and ((GetTime and GetTime() or 0) - pendingSelection.clickedAt) < 20 then
        local recipeID = pendingSelection.recipeID
        craftState.pendingSelection = nil
        C_Timer.After(0.5, function()
            local selected = addon.Api.SelectRecipe(recipeID)
            addon.Log.Debug("window.craft", "selecting the ordered recipe in the opened profession window",
                { recipeID = recipeID, selected = selected })
            if mainFrame and mainFrame:IsShown() then refreshOrders() end
        end)
    end
    if mainFrame and mainFrame:IsShown() then refreshOrders() end
end

refreshOrders = function()
    if not mainFrame or windowState.tab ~= "orders" then return end
    addon.Alerts.Seen()   -- feature 010: looking at the board clears the badge
    local orderFilter = orderFilters()[windowState.orderFilterIndex]
    mainFrame.orderFilterButton:SetLabel(Format(Text["Show: {filter}"], { filter = orderFilter[2] }))
    mainFrame.showClosedButton:SetLabel(windowState.showClosed and Text["Hide finished"] or Text["Show finished"])
    local orderRows = addon.Model.BuildOrderRows(addon.Store, addon.orders, orderFilter[1], windowState.showClosed, me())
    orderList:SetData(orderRows)
    local selectedOrderRow
    for _, orderRow in ipairs(orderRows) do if orderRow.id == windowState.selectedOrder then selectedOrderRow = orderRow end end
    mainFrame.claimButton:SetEnabled(selectedOrderRow and selectedOrderRow.canClaim or false)
    mainFrame.withdrawButton:SetEnabled(selectedOrderRow and selectedOrderRow.canWithdraw or false)
    mainFrame.doneButton:SetEnabled(selectedOrderRow and selectedOrderRow.canDone or false)
    mainFrame.cancelButton:SetEnabled(selectedOrderRow and selectedOrderRow.canCancel or false)
    refreshCraftButton(selectedOrderRow)
    mainFrame.ordersEmptyText:SetShown(#orderRows == 0)
end

---@return OfferViewRow|nil
local function selectedOfferRow()
    for _, offerRow in ipairs(currentOfferRows) do if offerRow.key == windowState.selectedOffer then return offerRow end end
end

local function refreshOffers()
    if not mainFrame or windowState.tab ~= "available" then return end
    local offerRows = addon.Model.BuildOfferRows(addon.Store,
        { text = windowState.offerText, myProfessionsOnly = windowState.offerMyProfessionsOnly, me = me() },
        addon.Api.ItemClass, addon.Api.ItemName)
    currentOfferRows = offerRows
    offerList:SetData(offerRows)
    mainFrame.offerCountText:SetText(Plural(#offerRows, Text["{n} offer"], Text["{n} offers"]))
    local selectedRow = selectedOfferRow()
    mainFrame.dibsButton:SetLabel(selectedRow and selectedRow.mine and Text["Remove dibs"] or Text["Dibs"])
    mainFrame.dibsButton:SetEnabled(selectedRow ~= nil and selectedRow.canDib)
    mainFrame.hideOfferButton:SetEnabled(selectedRow ~= nil)
    mainFrame.whisperOwnerButton:SetEnabled(selectedRow ~= nil and selectedRow.canDib)
    if not selectedRow then
        mainFrame.offerDetailText:SetText(Text["Select an offer to see who called dibs."])
    elseif #selectedRow.dibs == 0 then
        mainFrame.offerDetailText:SetText(Text["No dibs yet."])
    else
        local dibTexts = {}
        for position, dibRow in ipairs(selectedRow.dibs) do
            local holderName = dibRow.mine and ("|cff33ff99" .. shortName(dibRow.who) .. "|r") or shortName(dibRow.who)
            dibTexts[position] = ("%d. %s |cffaaaaaa%s|r"):format(position, holderName, timeAgo(dibRow.t))
        end
        mainFrame.offerDetailText:SetText(Format(Text["Dibs: {list}"], { list = table.concat(dibTexts, "   ") }))
    end
    mainFrame.offersEmptyText:SetShown(#offerRows == 0)
end

---@alias TabName "recipes"|"orders"|"available"|"debug"

---@class TabDefinition
---@field key TabName
---@field label string display text
---@field width number minimum button width

-- The window's tabs, in button order (feature 014: one list instead of hand-placed buttons). A function, so the
-- labels are read in the language active when the window is built.
---@return TabDefinition[]
local function tabDefinitions()
    return {
        { key = "recipes", label = Text["Recipes"], width = 90 },
        { key = "orders", label = Text["Orders"], width = 90 },
        { key = "available", label = Text["Available"], width = 90 },
        { key = "debug", label = Text["Debug"], width = 70 },
    }
end
UI.TabDefinitions = tabDefinitions


function UI.Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end
    refreshRecipes(); refreshDetail(); refreshOrders(); refreshOffers(); refreshDebug(); refreshProfessionBar()
end

---@param tabName TabName
local function selectTab(tabName)
    windowState.tab = tabName
    for key, tabFrame in pairs(mainFrame.tabs) do tabFrame:SetShown(key == tabName) end
    for tabKey, tabButton in pairs(mainFrame.tabButtons) do tabButton:SetEnabled(tabName ~= tabKey) end
    UI.Refresh()
end
---@param tabName TabName
UI.SelectTab = function(tabName) if mainFrame then selectTab(tabName) end end
---@return TabName|nil the shown tab, nil while the window is closed or not built
function UI.CurrentTab() return (mainFrame and mainFrame:IsShown()) and windowState.tab or nil end
---@return boolean
function UI.OrdersVisible() return (mainFrame and mainFrame:IsShown() and windowState.tab == "orders") and true or false end

-- insertText (optional): a function returning the text to put into the whisper's edit box (Model.ChatText: local links
-- only). The whisper opens first; building or inserting the text can never stop it. Every step is logged, and an error
-- is printed to chat (players usually run without script errors shown, so a failing click looked like "nothing happens").
---@param playerName string|nil
---@param insertText? string|fun(): string|nil
local function whisper(playerName, insertText)
    if not playerName or playerName == me() then   -- you cannot whisper yourself: the game answers "no player named ... online"
        addon.Log.Debug("window.whisper", "nobody to whisper (no other player for this row)", { player = playerName })
        return
    end
    -- same-realm players by character name only (the "Name-Realm" form is not found)
    local whisperTarget = addon.Utility.WhisperTarget(playerName)
    local ok, errorMessage = pcall(function()
        if ChatFrame_SendTell then ChatFrame_SendTell(whisperTarget)
        elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. whisperTarget .. " ") end
    end)
    local whisperText, editBox
    if ok and insertText then
        ok, errorMessage = pcall(function()
            whisperText = type(insertText) == "function" and insertText() or insertText
            editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
            if editBox and editBox.Insert and type(whisperText) == "string" and whisperText ~= "" then editBox:Insert(whisperText) end
        end)
    end
    local details = { player = playerName, target = whisperTarget, textLength = whisperText and #whisperText,
        editBoxFound = editBox ~= nil }
    if ok then
        addon.Log.Debug("window.whisper", "a whisper was opened", details)
    else
        details.error = tostring(errorMessage)
        addon.Log.Error("window.whisper", "opening a whisper failed", details)
        addon.Print("whisper failed: " .. addon.Utility.Escape(tostring(errorMessage)))
    end
end

-- whisper text for a recipe: link built by this client, else "[Name]" (Model.ChatText strips escape codes)
---@param recipeID integer
---@param quantity? integer
---@return string
local function recipeChatText(recipeID, quantity)
    local catalogEntry = addon.Store.GetRecipe(recipeID)
    return addon.Model.ChatText(addon.Api.RecipeLink(recipeID, catalogEntry and catalogEntry.produces),
        addon.Names.Recipe(recipeID, catalogEntry), quantity)
end

-- Feature 017: the effect text of a recipe that makes no item (enchants), read on this client by its recipe id as a
-- spell id: the spell DESCRIPTION only. It is empty until the client has loaded the spell (Api.SpellDescription requests
-- the load; SPELL_INFO redraws). The "spell:"/"enchant:" tooltips are not used: before the load they hold only the name,
-- tools and reagents (0.7.2 showed those as the effect). Found texts are cached for the session, misses are not.
-- One log line per recipe when its text is first found (/ps debug, /ps export).
---@type table<integer, string>
local effectTextCache = {}

---@param recipeID integer
---@return string|nil effect text (client text, not peer text)
recipeEffectText = function(recipeID)
    if effectTextCache[recipeID] then return effectTextCache[recipeID] end
    local description = addon.Api.SpellDescription(recipeID)
    if not description then return nil end
    effectTextCache[recipeID] = description
    addon.Log.Debug("window.effectText", "the effect text of a recipe without an item was found", { recipeID = recipeID,
        description = description })
    return description
end

-- hover on a recipe icon: the crafted item's own tooltip when known, else the name; then reagents and what a click does
---@param owner table
---@param recipeID integer
---@param clickHint string|nil
local function showRecipeTooltip(owner, recipeID, clickHint)
    local catalogEntry = addon.Store.GetRecipe(recipeID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if catalogEntry and catalogEntry.produces then
        GameTooltip:SetHyperlink("item:" .. catalogEntry.produces)
        GameTooltip:AddLine(addon.Model.RecipeName(addon.Store, recipeID), 1, 0.82, 0)
    else
        GameTooltip:SetText(addon.Model.RecipeName(addon.Store, recipeID), 1, 0.82, 0)
        local effectText = recipeEffectText(recipeID)   -- feature 017: enchants
        if effectText then GameTooltip:AddLine(addon.Utility.Escape(effectText), 0.2, 1, 0.2, true) end
    end
    local recipeDetail = addon.Model.RecipeDetail(addon.Store, recipeID, addon.Api.ItemCount, addon.Api.ItemName)
    if #recipeDetail.reagents > 0 then
        GameTooltip:AddLine(Text["Reagents"], 1, 1, 1)
        for _, reagentRow in ipairs(recipeDetail.reagents) do
            GameTooltip:AddLine(("%s x%d  (%s)"):format(reagentRow.name, reagentRow.count, Format(Text["have {n}"], { n = reagentRow.have })),
                reagentRow.enough and 0.2 or 1, reagentRow.enough and 1 or 0.4, reagentRow.enough and 0.6 or 0.4)
        end
    end
    if clickHint then GameTooltip:AddLine(clickHint, 0.6, 0.8, 1, true) end
    GameTooltip:Show()
end

---@param order Order|nil the changed order (nil when nothing changed)
local function afterOrderChange(order)
    if order then addon.Communication.BroadcastOrder(order) end
    UI.Refresh()
end

------------------------------------------------------------------ Debug tab (feature 008): network trace + export

---@type string[]
local DEBUG_FILTERS = { "all", "in", "out", "sys", "problems" }
---@param filterKey string
---@return string
local function debugFilterLabel(filterKey)
    local labels = { all = Text["All"], ["in"] = Text["Incoming"], out = Text["Outgoing"], sys = Text["System"], problems = Text["Problems"] }
    return labels[filterKey] or filterKey
end
---@type table<string, string>
local TRACE_STATUS_COLOR = { ok = "33ff99", sent = "33ff99", info = "aaaaaa", queued = "ffd100", ignored = "bbbbbb",
    failed = "ff5555", dropped = "ff5555", rejected = "ff5555", error = "ff5555", warn = "ff8800" }
---@type table<string, string>
local DIRECTION_TEXT = { ["in"] = "|cff66ccff<-|r", out = "|cffffd100->|r", sys = "|cffaaaaaa**|r" }

-- one coloured trace line; every field is escaped (peer text)
---@param traceEntry TraceEntry
---@return string
local function traceLine(traceEntry)
    local Escape = addon.Utility.Escape
    local parts = { "|cff888888" .. addon.Trace.Clock(traceEntry.t) .. "|r", DIRECTION_TEXT[traceEntry.dir] or "?" }
    if traceEntry.ch then parts[#parts + 1] = "|cff888888" .. Escape(traceEntry.ch) .. "|r" end
    if traceEntry.peer then parts[#parts + 1] = Escape(shortName(traceEntry.peer)) end
    if traceEntry.mt then parts[#parts + 1] = "|cffffffff" .. Escape(traceEntry.mt) .. "|r" end
    parts[#parts + 1] = "|cff" .. (TRACE_STATUS_COLOR[traceEntry.st] or "ffffff") .. Escape(traceEntry.st) .. "|r"
    if traceEntry.why then parts[#parts + 1] = "|cffcccccc" .. Escape(traceEntry.why) .. "|r"
    elseif traceEntry.info and traceEntry.info ~= "" then parts[#parts + 1] = "|cff999999" .. Escape(traceEntry.info) .. "|r" end
    return table.concat(parts, " ")
end

-- name check table: column widths (the list is 736 wide, 16 of it for the slider); Location and the full behaviour are in the tooltip
---@type { key: string, width: number }[]
local NAME_CHECK_COLUMNS = { { key = "status", width = 82 }, { key = "method", width = 196 }, { key = "value", width = 168 },
    { key = "expected", width = 150 }, { key = "behaviour", width = 120 } }
---@type table<IdentityStatus, string>
local NAME_STATUS_COLOR = { ok = "33ff99", fixed = "ffd100", bad = "ff5555", info = "aaaaaa", unknown = "aaaaaa" }

---@param identityRow IdentityRow
---@param columnKey string
---@return string
local function nameCheckCell(identityRow, columnKey)
    local Escape = addon.Utility.Escape
    if columnKey == "status" then
        return "|cff" .. (NAME_STATUS_COLOR[identityRow.status] or "ffffff") .. Escape(addon.Diagnostics.StatusLabel(identityRow.status)) .. "|r"
    end
    if columnKey == "method" then return "|cffffffff" .. Escape(identityRow.method) .. "|r" end
    if columnKey == "behaviour" then return "|cff999999" .. Escape(identityRow.behaviour) .. "|r" end
    return Escape(tostring(identityRow[columnKey]))
end

---@param parent table
---@param fontObject string
---@return table[] fontStrings, one per column
local function createColumns(parent, fontObject)
    local columnTexts, left = {}, 2
    for columnIndex, column in ipairs(NAME_CHECK_COLUMNS) do
        local columnText = createFontString(parent, fontObject)
        columnText:SetPoint("LEFT", left, 0); columnText:SetWidth(column.width - 6); columnText:SetWordWrap(false)
        columnTexts[columnIndex] = columnText
        left = left + column.width
    end
    return columnTexts
end

---@param list table
---@return table row
local function createDebugRow(list)
    local row = CreateFrame("Button", nil, list)
    local hoverHighlight = row:CreateTexture(nil, "HIGHLIGHT"); hoverHighlight:SetAllPoints(); hoverHighlight:SetColorTexture(1, 1, 1, 0.1)
    row.label = createFontString(row, "GameFontHighlightSmall"); row.label:SetPoint("LEFT", 2, 0); row.label:SetPoint("RIGHT", -2, 0)
    row.label:SetWordWrap(false)
    row.columnTexts = createColumns(row, "GameFontHighlightSmall")
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        local Escape = addon.Utility.Escape
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if entry.method then
            GameTooltip:SetText(Escape(entry.method), 1, 1, 1)
            GameTooltip:AddLine(Text["Status"] .. ": " .. nameCheckCell(entry, "status"), 1, 1, 1)
            GameTooltip:AddLine(Text["Location"] .. ": " .. Escape(entry.where), 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(Text["Value"] .. ": " .. Escape(entry.value), 1, 1, 1, true)
            GameTooltip:AddLine(Text["Expected"] .. ": " .. Escape(tostring(entry.expected)), 1, 1, 1, true)
            GameTooltip:AddLine(Text["Behaviour"] .. ": " .. Escape(entry.behaviour), 0.8, 0.8, 0.8, true)
        else
            GameTooltip:SetText(Escape(addon.Trace.Format(entry)), 1, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

---@param row table
---@param entry TraceEntry|IdentityRow
local function fillDebugRow(row, entry)
    local isNameCheckRow = entry.method ~= nil
    row.label:SetShown(not isNameCheckRow)
    for columnIndex, columnText in ipairs(row.columnTexts) do
        columnText:SetShown(isNameCheckRow)
        if isNameCheckRow then columnText:SetText(nameCheckCell(entry, NAME_CHECK_COLUMNS[columnIndex].key)) end
    end
    if not isNameCheckRow then row.label:SetText(traceLine(entry)) end
end

local debugList
---@type integer seq of the newest entry shown, to keep a scrolled-down view still while new entries arrive
local newestShownSequence = 0

local function refreshNameCheck()
    local identityRows = addon.Diagnostics.IdentityRows(addon.Diagnostics.IdentityContext())
    debugList.offset = math.min(debugList.offset, math.max(0, #identityRows - 1))
    debugList:SetData(identityRows)
    local countByStatus = { ok = 0, fixed = 0, bad = 0 }
    for _, identityRow in ipairs(identityRows) do
        if countByStatus[identityRow.status] then countByStatus[identityRow.status] = countByStatus[identityRow.status] + 1 end
    end
    mainFrame.debugStatusText:SetText(Format(Text["Name check: {ok} OK, {fixed} normalized, {bad} problems. Hover a row for location and behaviour."],
        { ok = countByStatus.ok, fixed = countByStatus.fixed, bad = countByStatus.bad }))
    mainFrame.debugEmptyText:Hide()
end

refreshDebug = function()
    if not mainFrame or windowState.tab ~= "debug" then return end
    local showingNameCheck = windowState.debugView == "names"
    mainFrame.nameCheckButton:SetLabel(showingNameCheck and Text["Message log"] or Text["Name check"])
    mainFrame.debugFilterButton:SetEnabled(not showingNameCheck)
    mainFrame.nameCheckHeader:SetShown(showingNameCheck)
    if showingNameCheck then refreshNameCheck() return end
    local filterKey = DEBUG_FILTERS[windowState.debugFilterIndex] or "all"
    mainFrame.debugFilterButton:SetLabel(Format(Text["Show: {filter}"], { filter = debugFilterLabel(filterKey) }))
    local traceEntries = addon.Trace.List(filterKey)
    if debugList.offset > 0 then
        local addedCount = 0
        for _, traceEntry in ipairs(traceEntries) do
            if (traceEntry.seq or 0) > newestShownSequence then addedCount = addedCount + 1 else break end
        end
        debugList.offset = debugList.offset + addedCount
    end
    newestShownSequence = traceEntries[1] and traceEntries[1].seq or newestShownSequence
    debugList:SetData(traceEntries)
    local Communication = addon.Communication
    local myName = addon.Store.db.me
    local rosterSize = addon.Utility.Count(Communication.roster)
    mainFrame.debugStatusText:SetText(Format(Text["Queue {q} chunks | incomplete {f} | roster {r} | me in roster: {m} | send failures {s}"], {
        q = #Communication.queue, f = #Communication.InFlight(), r = rosterSize,
        m = (rosterSize == 0 and "?") or (myName and Communication.roster[myName] and Text["yes"] or ("|cffff5555" .. Text["NO"] .. "|r")),
        s = Communication.sendFailures }))
    mainFrame.debugEmptyText:SetShown(#traceEntries == 0)
end


---@type table|nil
local exportFrame
---@param reportText string
function UI.ShowExport(reportText)
    if not exportFrame then
        local frameName = addon.FRAME_PREFIX .. "ExportFrame"
        local dialogFrame = createDialogFrame(frameName)
        dialogFrame:SetSize(720, 500); dialogFrame:SetPoint("CENTER")
        dialogFrame:SetFrameStrata("DIALOG")
        dialogFrame:SetMovable(true); dialogFrame:EnableMouse(true); dialogFrame:RegisterForDrag("LeftButton")
        dialogFrame:SetScript("OnDragStart", dialogFrame.StartMoving); dialogFrame:SetScript("OnDragStop", dialogFrame.StopMovingOrSizing)
        table.insert(UISpecialFrames, frameName)
        local titleText = createFontString(dialogFrame, "GameFontNormalLarge"); titleText:SetPoint("TOP", 0, -6); titleText:SetText(Text["Diagnostic report"])
        local hintText = createFontString(dialogFrame, "GameFontHighlightSmall"); hintText:SetPoint("TOPLEFT", 14, -32); hintText:SetPoint("RIGHT", -14, 0)
        hintText:SetText(Text["Press Ctrl+A, then Ctrl+C to copy. Paste it into Discord, a whisper or a text file for the addon author."])
        local scrollFrame = CreateFrame("ScrollFrame", nil, dialogFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -52); scrollFrame:SetPoint("BOTTOMRIGHT", -32, 12)
        local reportBox = CreateFrame("EditBox", nil, scrollFrame)
        reportBox:SetMultiLine(true); reportBox:SetAutoFocus(false); reportBox:SetMaxLetters(0)
        reportBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        reportBox:SetWidth(660)
        reportBox:SetScript("OnEscapePressed", function() dialogFrame:Hide() end)
        -- read-only: typing restores the report
        reportBox:SetScript("OnTextChanged", function(self, typedByUser)
            if typedByUser and dialogFrame.reportText then self:SetText(dialogFrame.reportText) end
        end)
        scrollFrame:SetScrollChild(reportBox)
        dialogFrame.reportBox = reportBox
        exportFrame = dialogFrame
    end
    exportFrame.reportText = addon.Utility.Escape(reportText)
    exportFrame.reportBox:SetText(exportFrame.reportText)
    exportFrame:Show()
    exportFrame.reportBox:SetFocus()
    exportFrame.reportBox:HighlightText()
end

local function buildDebugTab()
    local debugTab = CreateFrame("Frame", nil, mainFrame); debugTab:SetPoint("TOPLEFT", 12, -58); debugTab:SetPoint("BOTTOMRIGHT", -12, 12)
    mainFrame.tabs.debug = debugTab
    mainFrame.debugFilterButton = createButton(debugTab, Format(Text["Show: {filter}"], { filter = Text["All"] }), 150, 22, function()
        windowState.debugFilterIndex = windowState.debugFilterIndex % #DEBUG_FILTERS + 1
        debugList.offset = 0
        refreshDebug()
    end)
    mainFrame.debugFilterButton:SetPoint("TOPLEFT", 0, 0)
    local helloButton = createButton(debugTab, Text["Send HELLO"], 100, 22, function()
        addon.Communication.RequestHello(false, true); refreshDebug()
    end)
    helloButton:SetPoint("LEFT", mainFrame.debugFilterButton, "RIGHT", 8, 0)
    local clearButton = createButton(debugTab, Text["Clear"], 70, 22, function() addon.Trace.Clear(); debugList.offset = 0; refreshDebug() end)
    clearButton:SetPoint("LEFT", helloButton, "RIGHT", 8, 0)
    mainFrame.nameCheckButton = createButton(debugTab, Text["Name check"], 110, 22, function()
        windowState.debugView = windowState.debugView == "names" and "trace" or "names"
        debugList.offset = 0
        refreshDebug()
    end)
    mainFrame.nameCheckButton:SetPoint("LEFT", clearButton, "RIGHT", 8, 0)
    local exportButton = createButton(debugTab, Text["Export report"], 120, 22, function() addon.SlashCommands.export() end)
    exportButton:SetPoint("TOPRIGHT", 0, 0)
    if addon.IS_DEVELOPMENT_BUILD and addon.DevProbe then   -- dev build only (feature 011): records item/category/tooltip data to SavedVariables
        local probeButton = createButton(debugTab, Text["Item probe"], 100, 22, function() addon.DevProbe.Run() end)
        probeButton:SetPoint("RIGHT", exportButton, "LEFT", -8, 0)
        -- feature 017 test: an enchanter in the dev data, so enchants appear in the Recipes tab
        local fakeEnchanterButton = createButton(debugTab, Text["Fake enchanter"], 110, 18, function() addon.DevProbe.AddFakeEnchanter() end)
        fakeEnchanterButton:SetPoint("TOPRIGHT", debugTab, "TOPRIGHT", 0, -26)   -- second row: the first is full at the minimum width
        mainFrame.fakeEnchanterButton = fakeEnchanterButton
    end
    mainFrame.debugStatusText = createFontString(debugTab, "GameFontHighlightSmall")
    mainFrame.debugStatusText:SetPoint("TOPLEFT", 0, -28)
    if mainFrame.fakeEnchanterButton then mainFrame.debugStatusText:SetPoint("RIGHT", mainFrame.fakeEnchanterButton, "LEFT", -8, 0)
    else mainFrame.debugStatusText:SetPoint("RIGHT", 0, 0) end
    -- column headings of the name check (shown only in that view)
    local nameCheckHeader = CreateFrame("Frame", nil, debugTab); nameCheckHeader:SetSize(720, 16); nameCheckHeader:SetPoint("TOPLEFT", 0, -44)
    local headingTexts = createColumns(nameCheckHeader, "GameFontNormalSmall")
    local headings = { Text["Status"], Text["Method"], Text["Value"], Text["Expected"], Text["Behaviour"] }
    for columnIndex, headingText in ipairs(headingTexts) do headingText:SetText(headings[columnIndex]) end
    nameCheckHeader:Hide()
    mainFrame.nameCheckHeader = nameCheckHeader
    debugList = createScrollList(debugTab, createDebugRow, fillDebugRow)
    debugList:SetPoint("TOPLEFT", 0, -62); debugList:SetPoint("BOTTOMRIGHT", 0, 4)
    mainFrame.debugEmptyText = createFontString(debugTab, "GameFontDisable", "CENTER")
    mainFrame.debugEmptyText:SetPoint("CENTER", debugList, "CENTER", 0, 0)
    mainFrame.debugEmptyText:SetText(Text["No network messages recorded yet."])
    -- live view: entries change status after they were added (queued -> sent), so redraw once a second while visible
    local secondsSinceRedraw = 0
    debugTab:SetScript("OnUpdate", function(_, elapsedSeconds)
        secondsSinceRedraw = secondsSinceRedraw + elapsedSeconds
        if secondsSinceRedraw >= 1 then secondsSinceRedraw = 0; refreshDebug() end
    end)
end

---@param recipesTab table
local function buildRecipesTab(recipesTab)
    -- profession: dropdown with one entry per profession (feature 011); old cycle button if the client has no menus
    local function chooseProfession(professionIndex)
        if windowState.professionIndex ~= professionIndex then windowState.categories = {} end   -- categories differ per profession
        windowState.professionIndex = professionIndex
        refreshRecipes()
    end
    local professionDropdown = createMenuDropdown(recipesTab, "WowStyle1DropdownTemplate", 180)
    if professionDropdown then
        mainFrame.professionButton = professionDropdown
        mainFrame.professionButton:SetupMenu(function(_, rootMenu)
            local function isSelectedProfession(professionIndex) return windowState.professionIndex == professionIndex end
            rootMenu:CreateRadio(Text["All"], isSelectedProfession, chooseProfession, 0)
            for professionIndex, choice in ipairs(professionChoices()) do
                rootMenu:CreateRadio(choice.name, isSelectedProfession, chooseProfession, professionIndex)
            end
        end)
    else
        mainFrame.professionButton = createButton(recipesTab, Format(Text["Profession: {name}"], { name = Text["All"] }), 180, 22, function() end)
        mainFrame.professionButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        mainFrame.professionButton:SetScript("OnClick", function(_, mouseButton)
            local choiceCount = #professionChoices()
            chooseProfession((windowState.professionIndex + (mouseButton == "RightButton" and -1 or 1)) % (choiceCount + 1))
        end)
    end
    mainFrame.professionButton:SetPoint("TOPLEFT", 0, 0)

    -- category: checkbox menu built from the items the recipes of this profession make (feature 011)
    local function toggleCategory(categoryKey)
        windowState.categories[categoryKey] = (not windowState.categories[categoryKey]) or nil
        refreshRecipes()
    end
    local categoryDropdown = createMenuDropdown(recipesTab, "WowStyle1FilterDropdownTemplate", 120)
    if categoryDropdown then
        mainFrame.categoryButton = categoryDropdown
        mainFrame.categoryButton:SetupMenu(function(_, rootMenu)
            if rootMenu.SetScrollMode then rootMenu:SetScrollMode(420) end
            local categoryGroups = addon.Model.RecipeCategories(addon.Store, (currentRecipeFilter()), itemLookups)
            if #categoryGroups == 0 then rootMenu:CreateTitle(Text["No recipes"]); return end
            rootMenu:CreateButton(Text["Show all"], function()
                windowState.categories = {}
                refreshRecipes()
            end)
            local function isSelectedCategory(categoryKey) return windowState.categories[categoryKey] == true end
            for _, categoryGroup in ipairs(categoryGroups) do
                rootMenu:CreateTitle(categoryGroup.label)
                for _, categoryChoice in ipairs(categoryGroup.categories) do
                    rootMenu:CreateCheckbox(("%s (%d)"):format(categoryChoice.label, categoryChoice.count), isSelectedCategory,
                        toggleCategory, categoryChoice.key)
                end
            end
        end)
    else   -- no menus: cycle through the categories one at a time
        mainFrame.categoryButton = createButton(recipesTab, Text["Category"], 120, 22, function()
            local categoryKeys = {}
            for _, categoryGroup in ipairs(addon.Model.RecipeCategories(addon.Store, (currentRecipeFilter()), itemLookups)) do
                for _, categoryChoice in ipairs(categoryGroup.categories) do categoryKeys[#categoryKeys + 1] = categoryChoice.key end
            end
            local currentKey = next(windowState.categories)
            local currentPosition = 0
            for position, categoryKey in ipairs(categoryKeys) do if categoryKey == currentKey then currentPosition = position end end
            windowState.categories = {}
            if categoryKeys[currentPosition + 1] then windowState.categories[categoryKeys[currentPosition + 1]] = true end
            refreshRecipes()
        end)
    end
    mainFrame.categoryButton:SetPoint("LEFT", mainFrame.professionButton, "RIGHT", 8, 0)

    -- free-text search: words in any order over name, reagents, category and the item's effect text (feature 011)
    local searchTemplateOk, searchBox = pcall(CreateFrame, "EditBox", nil, recipesTab, "SearchBoxTemplate")
    if not searchTemplateOk or type(searchBox) ~= "table" then searchBox = CreateFrame("EditBox", nil, recipesTab, "InputBoxTemplate") end
    searchBox:SetSize(170, 20); searchBox:SetPoint("LEFT", mainFrame.categoryButton, "RIGHT", 14, 0); searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged and self.clearButton then pcall(SearchBoxTemplate_OnTextChanged, self) end
        windowState.text = self:GetText()
        refreshRecipes()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    mainFrame.searchBox = searchBox
    local searchHintText = createFontString(recipesTab, "GameFontDisableSmall"); searchHintText:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 0, 0)
    searchHintText:SetText(Text["search name, reagent, slot or effect"])

    -- effect texts are read a few per frame while this tab is open, so the first search does not freeze the game
    local secondsSinceRead, secondsSincePrefetch, secondsSinceRefresh, newTextArrived = 0, 3, 0, false
    recipesTab:SetScript("OnUpdate", function(_, elapsedSeconds)
        secondsSinceRead = secondsSinceRead + elapsedSeconds
        secondsSincePrefetch = secondsSincePrefetch + elapsedSeconds
        secondsSinceRefresh = secondsSinceRefresh + elapsedSeconds
        if secondsSincePrefetch >= 3 then secondsSincePrefetch = 0; addon.ItemText.Prefetch(addon.Store) end
        if secondsSinceRead >= 0.2 then
            secondsSinceRead = 0
            if addon.ItemText.Pump(8) > 0 then newTextArrived = true end
        end
        if newTextArrived and secondsSinceRefresh >= 1 then
            secondsSinceRefresh, newTextArrived = 0, false
            if tostring(windowState.text):find("%S") then refreshRecipes() end
        end
        -- feature 016: item data arrived (quality, levels): one redraw per second at most, however many items load
        if itemInfoArrived and secondsSinceRefresh >= 1 then
            secondsSinceRefresh = 0
            refreshRecipes()
        end
    end)
    mainFrame.mineOnlyButton = createButton(recipesTab, Text["Mine only"], 80, 22, function()
        windowState.mineOnly = not windowState.mineOnly
        mainFrame.mineOnlyButton:SetLabel(windowState.mineOnly and (Text["Mine only"] .. " *") or Text["Mine only"])
        refreshRecipes()
    end)
    mainFrame.mineOnlyButton:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    mainFrame.recipeCountText = createFontString(recipesTab, "GameFontNormalSmall", "LEFT")
    mainFrame.recipeCountText:SetPoint("LEFT", mainFrame.mineOnlyButton, "RIGHT", 10, 0)

    -- feature 016: a table (header + columns from the options, name in item-quality colour); it fills the space left of
    -- the detail panel, which keeps a fixed width at the right
    local detailFrame = CreateFrame("Frame", nil, recipesTab)
    detailFrame:SetPoint("TOPRIGHT", recipesTab, "TOPRIGHT", 0, -34); detailFrame:SetPoint("BOTTOMRIGHT", recipesTab, "BOTTOMRIGHT", 0, 0)
    detailFrame:SetWidth(304)
    local recipeHeader = Table.CreateHeader(recipesTab, function(columnKey)
        RecipeTable.ClickHeader(interfaceSettings(), columnKey)
        refreshRecipes()
    end)
    mainFrame.recipeHeader = recipeHeader
    local function numberText(value) return value and tostring(value) or "" end
    recipeList = createScrollList(recipesTab, Table.CreateTableRow, function(row, recipeRow)
        Table.LayoutRow(row, recipeCells)
        row.icon:SetTexture(recipeRow.icon or QUESTION_MARK_ICON)
        -- recipeRow.name is escaped (Model): the colour code wraps it, a peer's own codes stay plain text
        row.label:SetText(RecipeTable.Coloured(recipeRow.name, addon.Api.QualityHex(recipeRow.quality)))
        Table.SetCell(row, "itemLevel", numberText(recipeRow.itemLevel))
        Table.SetCell(row, "requiredLevel", numberText(recipeRow.requiredLevel))
        Table.SetCell(row, "profession", "|cffaaaaaa" .. recipeRow.profession .. "|r")
        Table.SetCell(row, "skill", numberText(recipeRow.skill))
        Table.SetCell(row, "category", "|cffaaaaaa" .. addon.Utility.Escape(recipeRow.categoryLabel or "") .. "|r")
        row.selectionHighlight:SetShown(recipeRow.recipeID == windowState.selectedRecipe)
        row:SetScript("OnClick", function()
            windowState.selectedRecipe = recipeRow.recipeID
            recipeList:Refresh(); refreshDetail()
        end)
        -- crafters are looked up on hover/click only (not for every row on every refresh)
        local function contactName() return addon.Model.RecipeContact(addon.Store.Crafters(recipeRow.recipeID), me()) end
        row.onIconEnter = function(iconButton)
            local crafterName = contactName()
            showRecipeTooltip(iconButton, recipeRow.recipeID,
                crafterName and Format(Text["Click: whisper {name} with this recipe"], { name = shortName(crafterName) }))
        end
        row.onIconClick = function()
            whisper(contactName(), function() return recipeChatText(recipeRow.recipeID) end)
        end
    end)
    recipeList:SetPoint("TOPLEFT", recipesTab, "TOPLEFT", 0, -54)
    recipeList:SetPoint("BOTTOMRIGHT", detailFrame, "BOTTOMLEFT", -12, 0)
    recipeHeader:SetPoint("TOPLEFT", recipesTab, "TOPLEFT", 0, -34)
    recipeHeader:SetPoint("RIGHT", recipeList, "RIGHT", -Table.SLIDER_SPACE, 0)
    recipeList.onLayout = function(list)
        local settings = interfaceSettings()
        recipeCells = RecipeTable.Layout(RecipeTable.VisibleColumns(settings), list:ContentWidth())
        recipeHeader:SetColumns(recipeCells, RecipeTable.GetSort(settings))
    end
    mainFrame.recipesEmptyText = createFontString(recipesTab, "GameFontDisable", "CENTER")
    mainFrame.recipesEmptyText:SetPoint("CENTER", recipeList, "CENTER", 0, 0); mainFrame.recipesEmptyText:SetWidth(380)
    mainFrame.recipesEmptyText:SetText(Text["No recipes known yet. Click your profession icons at the top right once."])
    -- one secure button per own profession (see "profession scan buttons" above)
    for buttonIndex = 1, MAXIMUM_PROFESSION_BUTTONS do professionBar.buttons[buttonIndex] = createProfessionButton(recipesTab, buttonIndex) end
    -- attention label next to the buttons (positioned and shown by refreshProfessionBar)
    local scanHint = CreateFrame("Frame", nil, recipesTab)
    scanHint:SetSize(1, 1); scanHint:SetPoint("TOPRIGHT", recipesTab, "TOPRIGHT", 0, 0)
    local scanHintText = createFontString(scanHint, "GameFontNormalLarge", "RIGHT")
    scanHintText:SetText(Text["CLICK HERE ->"]); scanHintText:SetTextColor(1, 0.82, 0)
    scanHint:SetScript("OnUpdate", function()
        scanHintText:SetAlpha(0.55 + 0.45 * math.abs(math.sin((GetTime and GetTime() or 0) * 3)))
    end)
    scanHint:Hide()
    mainFrame.scanHint, mainFrame.scanHintText = scanHint, scanHintText

    -- detail panel (detailFrame is created above, the table is anchored to it)
    detailPanel.icon = detailFrame:CreateTexture(nil, "ARTWORK"); detailPanel.icon:SetSize(32, 32); detailPanel.icon:SetPoint("TOPLEFT", 0, 0)
    detailPanel.title = createFontString(detailFrame, "GameFontNormalLarge")
    detailPanel.title:SetPoint("LEFT", detailPanel.icon, "RIGHT", 8, 0); detailPanel.title:SetPoint("RIGHT", 0, 0)
    detailPanel.effectText = createFontString(detailFrame, "GameFontGreenSmall")
    detailPanel.effectText:SetPoint("TOPLEFT", detailPanel.icon, "BOTTOMLEFT", 0, -2); detailPanel.effectText:SetPoint("RIGHT", 0, 0)
    detailPanel.effectText:SetWordWrap(false)
    detailPanel.reagentsLabel = createFontString(detailFrame, "GameFontNormal")
    detailPanel.reagentsLabel:SetPoint("TOPLEFT", 0, -44); detailPanel.reagentsLabel:SetText(Text["Reagents"])
    detailPanel.reagentLines = {}
    for lineIndex = 1, 8 do
        local reagentLine = CreateFrame("Frame", nil, detailFrame)
        reagentLine:SetSize(280, 18); reagentLine:SetPoint("TOPLEFT", 0, -44 - lineIndex * 19)
        reagentLine.icon = reagentLine:CreateTexture(nil, "ARTWORK"); reagentLine.icon:SetSize(16, 16); reagentLine.icon:SetPoint("LEFT", 0, 0)
        reagentLine.label = createFontString(reagentLine, "GameFontHighlightSmall"); reagentLine.label:SetPoint("LEFT", reagentLine.icon, "RIGHT", 4, 0)
        reagentLine:EnableMouse(true)
        reagentLine:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID then GameTooltip:SetHyperlink("item:" .. self.itemID) end
            GameTooltip:Show()
        end)
        reagentLine:SetScript("OnLeave", function() GameTooltip:Hide() end)
        detailPanel.reagentLines[lineIndex] = reagentLine
    end
    detailPanel.noReagentsText = createFontString(detailFrame, "GameFontDisableSmall")
    detailPanel.noReagentsText:SetPoint("TOPLEFT", 0, -64); detailPanel.noReagentsText:SetText(Text["reagents unknown (not scanned yet)"])
    detailPanel.craftersLabel = createFontString(detailFrame, "GameFontNormal")
    detailPanel.craftersLabel:SetPoint("TOPLEFT", 0, -222); detailPanel.craftersLabel:SetText(Text["Who can craft it (click to whisper)"])
    detailPanel.crafterLines = {}
    for lineIndex = 1, 7 do
        local crafterLine = CreateFrame("Button", nil, detailFrame)
        crafterLine:SetSize(300, 18); crafterLine:SetPoint("TOPLEFT", 0, -222 - lineIndex * 19)
        local hoverHighlight = crafterLine:CreateTexture(nil, "HIGHLIGHT"); hoverHighlight:SetAllPoints(); hoverHighlight:SetColorTexture(1, 1, 1, 0.1)
        crafterLine.label = createFontString(crafterLine, "GameFontHighlightSmall"); crafterLine.label:SetPoint("LEFT", 2, 0)
        crafterLine:SetScript("OnClick", function(self)
            local recipeID = windowState.selectedRecipe
            if self.crafterName then whisper(self.crafterName, recipeID and function() return recipeChatText(recipeID) end) end
        end)
        detailPanel.crafterLines[lineIndex] = crafterLine
    end
    detailPanel.moreCraftersText = createFontString(detailFrame, "GameFontDisableSmall")
    detailPanel.moreCraftersText:SetPoint("TOPLEFT", 0, -222 - 8 * 19)
    detailPanel.quantityBox = CreateFrame("EditBox", nil, detailFrame, "InputBoxTemplate")
    detailPanel.quantityBox:SetSize(30, 20); detailPanel.quantityBox:SetPoint("BOTTOMLEFT", 6, 8); detailPanel.quantityBox:SetAutoFocus(false)
    detailPanel.quantityBox:SetNumeric(true); detailPanel.quantityBox:SetText("1"); detailPanel.quantityBox:SetMaxLetters(2)
    detailPanel.noteBox = CreateFrame("EditBox", nil, detailFrame, "InputBoxTemplate")
    detailPanel.noteBox:SetSize(130, 20); detailPanel.noteBox:SetPoint("LEFT", detailPanel.quantityBox, "RIGHT", 12, 0)
    detailPanel.noteBox:SetAutoFocus(false)
    detailPanel.noteBox:SetMaxLetters(80)
    -- the order note limit is 80 BYTES (Orders.lua); multi-byte characters (umlauts, Cyrillic, CJK) count 2-4 bytes each
    if detailPanel.noteBox.SetMaxBytes then detailPanel.noteBox:SetMaxBytes(80) end
    detailPanel.requestButton = createButton(detailFrame, Text["Request"], 70, 22, function()
        local recipeID = windowState.selectedRecipe
        if not recipeID then return end
        local quantity = tonumber(detailPanel.quantityBox:GetText()) or 1
        if quantity < 1 then quantity = 1 end
        local catalogEntry = addon.Store.GetRecipe(recipeID)
        local order = addon.orders:Create(me(), recipeID, quantity, detailPanel.noteBox:GetText() or "",
            catalogEntry and catalogEntry.name, catalogEntry and catalogEntry.loc)
        if order then
            detailPanel.noteBox:SetText(""); detailPanel.quantityBox:SetText("1")
            addon.Log.Information("window.request", "an order was created", { orderID = order.id, recipeID = recipeID, quantity = quantity })
            afterOrderChange(order)
            selectTab("orders")
            addon.Print(Format(Text["Requested {qty}x {name}"], { qty = quantity, name = addon.Model.RecipeName(addon.Store, recipeID) }))
        end
    end)
    detailPanel.requestButton:SetPoint("LEFT", detailPanel.noteBox, "RIGHT", 8, 0)
end

---@param ordersTab table
local function buildOrdersTab(ordersTab)
    mainFrame.orderFilterButton = createButton(ordersTab, Format(Text["Show: {filter}"], { filter = Text["All"] }), 160, 22, function()
        windowState.orderFilterIndex = windowState.orderFilterIndex % #orderFilters() + 1
        refreshOrders()
    end)
    mainFrame.orderFilterButton:SetPoint("TOPLEFT", 0, 0)
    mainFrame.showClosedButton = createButton(ordersTab, Text["Show finished"], 120, 22, function()
        windowState.showClosed = not windowState.showClosed; refreshOrders()
    end)
    mainFrame.showClosedButton:SetPoint("LEFT", mainFrame.orderFilterButton, "RIGHT", 8, 0)
    local helpText = createFontString(ordersTab, "GameFontDisableSmall"); helpText:SetPoint("TOPRIGHT", 0, -6)
    helpText:SetText(Text["Request recipes on the Recipes tab. Everyone in the guild sees this board."])
    orderList = createScrollList(ordersTab, createSelectableRow, function(row, orderRow)
        row.icon:SetTexture((addon.Store.GetRecipe(orderRow.recipeID) or {}).icon or QUESTION_MARK_ICON)
        local claimerNames = {}
        for index, crafter in ipairs(orderRow.claimers) do claimerNames[index] = shortName(crafter) end
        local claimersText = #claimerNames > 0 and ("  -> |cff33ff99" .. table.concat(claimerNames, ", ") .. "|r") or ""
        local noteText = orderRow.note ~= "" and ("  |cff999999\"" .. orderRow.note .. "\"|r") or ""
        row.label:SetText(("%dx %s  |cffaaaaaa%s|r%s%s"):format(orderRow.qty, orderRow.recipeName,
            Format(Text["for {name}"], { name = shortName(orderRow.requester) }), claimersText, noteText))
        row.rightText:SetText("|cff" .. (STATUS_COLOR[orderRow.status] or "ffffff") .. statusLabel(orderRow.status) .. "|r  " .. timeAgo(orderRow.createdAt))
        row.label:SetPoint("RIGHT", -130, 0)
        row.selectionHighlight:SetShown(orderRow.id == windowState.selectedOrder)
        row:SetScript("OnClick", function() windowState.selectedOrder = orderRow.id; refreshOrders() end)
        local contactName = addon.Model.OrderContact(orderRow, me())
        row.onIconEnter = function(iconButton)
            showRecipeTooltip(iconButton, orderRow.recipeID,
                contactName and Format(Text["Click: whisper {name} with this recipe"], { name = shortName(contactName) }))
        end
        row.onIconClick = function()
            whisper(contactName, function() return recipeChatText(orderRow.recipeID, orderRow.qty) end)
        end
    end)
    orderList:SetPoint("TOPLEFT", 0, -30); orderList:SetPoint("BOTTOMRIGHT", 0, 32)
    mainFrame.ordersEmptyText = createFontString(ordersTab, "GameFontDisable")
    mainFrame.ordersEmptyText:SetPoint("CENTER", 0, 0); mainFrame.ordersEmptyText:SetText(Text["No orders yet."])
    -- a click handler that applies `orderAction` to the selected order and broadcasts the result
    ---@param actionName string for the log
    ---@param orderAction fun(orderID: string): Order|nil
    local function onSelectedOrder(actionName, orderAction)
        return function()
            local orderID = windowState.selectedOrder
            if not orderID then return end
            local changedOrder = orderAction(orderID)
            addon.Log.Information("window.order", "an order button was used",
                { action = actionName, orderID = orderID, changed = changedOrder ~= nil })
            afterOrderChange(changedOrder)
        end
    end
    mainFrame.claimButton = createButton(ordersTab, Text["I'll craft it"], 110, 24,
        onSelectedOrder("claim", function(orderID) return addon.orders:Claim(orderID, me()) end))
    mainFrame.withdrawButton = createButton(ordersTab, Text["Withdraw"], 90, 24,
        onSelectedOrder("withdraw", function(orderID) return addon.orders:Withdraw(orderID, me()) end))
    mainFrame.doneButton = createButton(ordersTab, Text["Mark done"], 90, 24,
        onSelectedOrder("done", function(orderID) return addon.orders:Close(orderID, me(), "done") end))
    mainFrame.cancelButton = createButton(ordersTab, Text["Cancel order"], 100, 24,
        onSelectedOrder("cancel", function(orderID) return addon.orders:Close(orderID, me(), "cancelled") end))
    mainFrame.claimButton:SetPoint("BOTTOMLEFT", 0, 0)
    mainFrame.withdrawButton:SetPoint("LEFT", mainFrame.claimButton, "RIGHT", 6, 0)
    mainFrame.doneButton:SetPoint("LEFT", mainFrame.withdrawButton, "RIGHT", 6, 0)
    mainFrame.cancelButton:SetPoint("LEFT", mainFrame.doneButton, "RIGHT", 6, 0)
    -- secure Craft button (see "Craft button" above); without the template (should not happen) there is no button
    local craftTemplateOk, craftButton = pcall(CreateFrame, "Button", nil, addon.SecureDock.Holder(),
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    if craftTemplateOk and craftButton then
        craftButton:SetSize(110, 24)
        craftButton.minimumWidth, craftButton.SetLabel = 110, setButtonLabel
        craftButton:RegisterForClicks("AnyUp", "AnyDown")
        craftButton:HookScript("PostClick", onCraftButtonPostClick)
        craftButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(Text["Craft"], 1, 1, 1)
            GameTooltip:AddLine(Text["First click opens the profession and selects the ordered recipe, the next click crafts the ordered quantity. Only for recipes you know."], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        craftButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        craftButton:SetLabel(Text["Craft"]); craftButton:Disable()
        addon.SecureDock.Register(craftButton, ordersTab, function(button)
            button:SetPoint("LEFT", mainFrame.cancelButton, "RIGHT", 18, 0)
        end)
        mainFrame.craftButton = craftButton
    else
        addon.Log.Error("window.craft", "the secure Craft button could not be created; crafting from orders is unavailable",
            { error = tostring(craftButton) })
    end
end

---@param availableTab table
local function buildAvailableTab(availableTab)
    local offerSearchBox = CreateFrame("EditBox", nil, availableTab, "InputBoxTemplate")
    offerSearchBox:SetSize(200, 20); offerSearchBox:SetPoint("TOPLEFT", 6, -14); offerSearchBox:SetAutoFocus(false)
    offerSearchBox:SetScript("OnTextChanged", function(self) windowState.offerText = self:GetText(); refreshOffers() end)
    offerSearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local offerSearchHint = createFontString(availableTab, "GameFontDisableSmall"); offerSearchHint:SetPoint("BOTTOMLEFT", offerSearchBox, "TOPLEFT", 0, 0)
    offerSearchHint:SetText(Text["search item, owner or profession"])
    mainFrame.myProfessionsOnlyButton = createButton(availableTab, Text["Only my professions"], 150, 22, function()
        windowState.offerMyProfessionsOnly = not windowState.offerMyProfessionsOnly
        mainFrame.myProfessionsOnlyButton:SetLabel(windowState.offerMyProfessionsOnly and (Text["Only my professions"] .. " *")
            or Text["Only my professions"])
        refreshOffers()
    end)
    mainFrame.myProfessionsOnlyButton:SetPoint("LEFT", offerSearchBox, "RIGHT", 8, 0)
    mainFrame.offerCountText = createFontString(availableTab, "GameFontNormalSmall", "RIGHT")
    mainFrame.offerCountText:SetPoint("TOPRIGHT", availableTab, "TOPRIGHT", -4, -6)
    offerList = createScrollList(availableTab, createSelectableRow, function(row, offerRow)
        row.icon:SetTexture(offerRow.icon or QUESTION_MARK_ICON)
        local professionText = offerRow.profession and ("  |cff888888" .. offerRow.profession .. "|r") or ""
        row.label:SetText(("%s%s  |cffaaaaaa%s|r  |cff999999%s|r"):format(offerRow.name, professionText, shortName(offerRow.ownerName),
            offerRow.locations))
        row.rightText:SetText((offerRow.mine and "|cff33ff99* |r" or "") .. Plural(offerRow.dibCount, Text["{n} dib"], Text["{n} dibs"]))
        row.label:SetPoint("RIGHT", -100, 0)
        row.selectionHighlight:SetShown(offerRow.key == windowState.selectedOffer)
        row:SetScript("OnClick", function() windowState.selectedOffer = offerRow.key; refreshOffers() end)
        local function showItemTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. offerRow.itemID)
            if offerRow.canDib then
                GameTooltip:AddLine(Format(Text["Click the icon: whisper {name} with this item"], { name = offerRow.ownerName }), 0.6, 0.8, 1, true)
            end
            GameTooltip:Show()
        end
        row:SetScript("OnEnter", showItemTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.onIconEnter = showItemTooltip
        row.onIconClick = function()
            if offerRow.canDib then
                whisper(offerRow.owner, function()
                    return addon.Model.ChatText(addon.Api.ItemLink(offerRow.itemID), addon.Api.ItemName(offerRow.itemID))
                end)
            end
        end
    end)
    offerList:SetPoint("TOPLEFT", 0, -38); offerList:SetPoint("BOTTOMRIGHT", 0, 112)
    mainFrame.offersEmptyText = createFontString(availableTab, "GameFontDisable", "CENTER")
    mainFrame.offersEmptyText:SetPoint("CENTER", offerList, "CENTER", 0, 0); mainFrame.offersEmptyText:SetWidth(520)
    mainFrame.offersEmptyText:SetText(Text["No recipe items on offer yet. They are listed automatically from the bags, bank, mail, guild bank and auctions of every guild member."])
    mainFrame.offerDetailText = createFontString(availableTab, "GameFontHighlightSmall")
    mainFrame.offerDetailText:SetPoint("TOPLEFT", offerList, "BOTTOMLEFT", 4, -8); mainFrame.offerDetailText:SetPoint("RIGHT", availableTab, "RIGHT", -8, 0)
    mainFrame.offerDetailText:SetHeight(44)
    mainFrame.offerDetailText:SetJustifyV("TOP"); mainFrame.offerDetailText:SetWordWrap(true)
    mainFrame.dibsButton = createButton(availableTab, Text["Dibs"], 140, 24, function()
        local selectedRow = selectedOfferRow()
        if not selectedRow then return end
        local dibState, refusal = addon.Offers.ToggleDib(me(), selectedRow.owner, selectedRow.itemID, addon.Utility.Now())
        addon.Log.Information("window.dibs", "the Dibs button was used",
            { owner = selectedRow.owner, itemID = selectedRow.itemID, result = dibState, refusal = refusal })
        if dibState == "on" then addon.Print(Format(Text["Dibs set on {name}"], { name = selectedRow.name }))
        elseif dibState == "off" then addon.Print(Format(Text["Dibs removed from {name}"], { name = selectedRow.name }))
        elseif refusal == "limit" then addon.Print(Text["Too many active dibs."])
        else addon.Print(Text["That item is no longer on offer."]) end
        if dibState then addon.Events.Fire("OFFERS_CHANGED") end
        UI.Refresh()
    end)
    mainFrame.hideOfferButton = createButton(availableTab, Text["Remove from my list"], 150, 24, function()
        local selectedRow = selectedOfferRow()
        if selectedRow and addon.Offers.Hide(selectedRow.owner, selectedRow.itemID) then windowState.selectedOffer = nil end
        UI.Refresh()
    end)
    mainFrame.whisperOwnerButton = createButton(availableTab, Text["Whisper owner"], 120, 24, function()
        local selectedRow = selectedOfferRow()
        if selectedRow then whisper(selectedRow.owner) end
    end)
    mainFrame.dibsButton:SetPoint("BOTTOMLEFT", 0, 0)
    mainFrame.hideOfferButton:SetPoint("LEFT", mainFrame.dibsButton, "RIGHT", 6, 0)
    mainFrame.whisperOwnerButton:SetPoint("LEFT", mainFrame.hideOfferButton, "RIGHT", 6, 0)
end

---@return table tabFrame
local function createTabFrame()
    local tabFrame = CreateFrame("Frame", nil, mainFrame)
    tabFrame:SetPoint("TOPLEFT", 12, -58); tabFrame:SetPoint("BOTTOMRIGHT", -12, 12)
    return tabFrame
end

-- feature 016: the window is resizable from a grip at its bottom right, between today's size (minimum) and the screen.
-- The size is saved in the ui settings and restored when the window is built. Every tab's list follows (anchored).
local function buildResizeGrip()
    local function screenSize()
        return (UIParent and UIParent:GetWidth()) or RecipeTable.MINIMUM_WIDTH, (UIParent and UIParent:GetHeight()) or RecipeTable.MINIMUM_HEIGHT
    end
    local screenWidth, screenHeight = screenSize()
    local savedWidth, savedHeight = RecipeTable.WindowSize(interfaceSettings(), screenWidth, screenHeight)
    if savedWidth then mainFrame:SetSize(savedWidth, savedHeight) end
    mainFrame:SetResizable(true)
    if mainFrame.SetResizeBounds then
        mainFrame:SetResizeBounds(RecipeTable.MINIMUM_WIDTH, RecipeTable.MINIMUM_HEIGHT, math.max(RecipeTable.MINIMUM_WIDTH, screenWidth),
            math.max(RecipeTable.MINIMUM_HEIGHT, screenHeight))
    elseif mainFrame.SetMinResize then
        mainFrame:SetMinResize(RecipeTable.MINIMUM_WIDTH, RecipeTable.MINIMUM_HEIGHT)
    end
    local resizeGrip = CreateFrame("Button", nil, mainFrame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -3, 3)
    resizeGrip:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then mainFrame:StartSizing("BOTTOMRIGHT") end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        RecipeTable.SetWindowSize(interfaceSettings(), mainFrame:GetWidth(), mainFrame:GetHeight())
        addon.Log.Debug("window.resize", "the window was resized", { width = math.floor(mainFrame:GetWidth()), height = math.floor(mainFrame:GetHeight()) })
    end)
    mainFrame.resizeGrip = resizeGrip
end

local function buildMainFrame()
    local frameName = addon.FRAME_PREFIX .. "Frame"
    mainFrame = createDialogFrame(frameName)
    mainFrame:SetSize(780, 520)
    -- the development window is offset so both can be open
    mainFrame:SetPoint("CENTER", addon.IS_DEVELOPMENT_BUILD and 40 or 0, addon.IS_DEVELOPMENT_BUILD and -40 or 0)
    mainFrame:SetMovable(true); mainFrame:EnableMouse(true); mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()
    table.insert(UISpecialFrames, frameName)
    buildResizeGrip()
    mainFrame:SetScript("OnShow", function() addon.Events.Fire("WINDOW_OPENED"); UI.Refresh() end)

    local titleText = createFontString(mainFrame, "GameFontNormalLarge"); titleText:SetPoint("TOP", 0, -6); titleText:SetText(addon.TITLE)

    mainFrame.tabButtons = {}
    local previousButton
    for _, tab in ipairs(tabDefinitions()) do
        local tabKey = tab.key
        local tabButton = createButton(mainFrame, tab.label, tab.width, 22, function() selectTab(tabKey) end)
        if previousButton then tabButton:SetPoint("LEFT", previousButton, "RIGHT", 4, 0) else tabButton:SetPoint("TOPLEFT", 12, -30) end
        mainFrame.tabButtons[tabKey] = tabButton
        previousButton = tabButton
    end
    mainFrame.optionsButton = createButton(mainFrame, Text["Options"], 80, 22, function() addon.Alerts.OpenOptions() end)
    mainFrame.optionsButton:SetPoint("TOPRIGHT", -30, -30)
    mainFrame.tabs = {}
    UI.SetNotice(noticeState.count, noticeState.showIcon, noticeState.hideNumber)

    mainFrame.tabs.recipes = createTabFrame()
    buildRecipesTab(mainFrame.tabs.recipes)
    mainFrame.tabs.orders = createTabFrame()
    buildOrdersTab(mainFrame.tabs.orders)
    mainFrame.tabs.available = createTabFrame()
    buildAvailableTab(mainFrame.tabs.available)
    buildDebugTab()

    addon.Events.On("DATA_CHANGED", UI.Refresh)
    addon.Events.On("TRADESKILL", onTradeSkillWindow)
    addon.Events.On("ITEM_INFO", function()
        itemInfoArrived = true   -- the Recipes table redraws debounced (its OnUpdate)
        if mainFrame:IsShown() then refreshDetail(); refreshOffers() end
    end)
    addon.Events.On("SPELL_INFO", function()   -- feature 017: an enchant's effect text is readable now
        itemInfoArrived = true   -- the search sees it on the debounced redraw
        if mainFrame:IsShown() then refreshDetail() end
    end)
    selectTab("recipes")
    addon.Log.Debug("window.build", "the main window was built")
end

function UI.Toggle()
    if not mainFrame then buildMainFrame() end
    if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
end

function UI.Show()
    if not mainFrame then buildMainFrame() end
    mainFrame:Show()
end

------------------------------------------------------------------ minimap button

-- Feature 010: unseen orders as a number on the minimap button and the Orders tab, a letter icon while count > 0.
local DEFAULT_ICON, NEWS_ICON = "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Letter_15"
---@type table|nil
local minimapButton

-- hideNumber: the badge option is off (the letter icon may still show that something is new)
---@param unseenCount integer|nil
---@param showIcon boolean|nil
---@param hideNumber boolean|nil
function UI.SetNotice(unseenCount, showIcon, hideNumber)
    noticeState.count, noticeState.showIcon, noticeState.hideNumber = unseenCount or 0, showIcon and true or false, hideNumber and true or false
    if mainFrame and mainFrame.tabButtons then
        mainFrame.tabButtons.orders:SetLabel(noticeState.count > 0 and not noticeState.hideNumber
            and Format(Text["Orders ({n})"], { n = noticeState.count }) or Text["Orders"])
    end
    if not minimapButton then return end
    minimapButton.icon:SetTexture(noticeState.showIcon and noticeState.count > 0 and NEWS_ICON or DEFAULT_ICON)
    minimapButton.badge:SetShown(noticeState.count > 0 and not noticeState.hideNumber)
    minimapButton.badgeText:SetText(noticeState.count > 99 and "99+" or tostring(noticeState.count))
end

-- the round button is LibGuildSync's (Widgets.CreateMinimapButton, shared with GuildGames); its badge shows the count
local function buildMinimapButton()
    minimapButton = Widgets.CreateMinimapButton({
        name = addon.FRAME_PREFIX .. "MinimapButton",
        icon = DEFAULT_ICON,
        defaultAngle = addon.IS_DEVELOPMENT_BUILD and 245 or 215,
        getAngle = function() return addon.db and addon.db.ui.minimapAngle end,
        setAngle = function(degrees) if addon.db then addon.db.ui.minimapAngle = degrees end end,
        onClick = function() UI.Toggle() end,
        onTooltip = function(tooltip)
            tooltip:SetText(addon.TITLE)
            if noticeState.count > 0 then tooltip:AddLine(Format(Text["{n} new on the order board"], { n = noticeState.count }), 1, 0.82, 0) end
            tooltip:AddLine(Text["Click: open window. Right-drag: move."], 1, 1, 1)
        end,
    })
    UI.SetNotice(noticeState.count, noticeState.showIcon, noticeState.hideNumber)
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
pcall(loginFrame.RegisterEvent, loginFrame, "PLAYER_REGEN_ENABLED")
pcall(loginFrame.RegisterEvent, loginFrame, "PLAYER_REGEN_DISABLED")
loginFrame:SetScript("OnEvent", function(_, gameEvent)
    if gameEvent == "PLAYER_REGEN_DISABLED" then
        -- fired before the lockdown: take the secure buttons out of the window so it stays free to show/hide in combat
        addon.SecureDock.OnCombatStart()
        return
    end
    if gameEvent == "PLAYER_REGEN_ENABLED" then
        addon.SecureDock.OnCombatEnd()   -- the secure buttons back into the window first
        -- secure buttons could not be updated in combat
        if professionBar.needsUpdateAfterCombat and mainFrame and mainFrame:IsShown() then refreshProfessionBar() end
        if craftState.needsUpdateAfterCombat and mainFrame and mainFrame:IsShown() then refreshOrders() end
        return
    end
    addon.Log.Protected("window.minimap", "building the minimap button failed", buildMinimapButton)
    addon.Alerts.Start()
end)
