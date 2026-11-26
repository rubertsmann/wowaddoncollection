local addonName, addon = ...

-- Standalone window: "Recipes" tab (filter, search, reagents, crafters, request), "Orders" tab (shared board),
-- "Misc Items" tab (recipe items with dibs, dungeon keys, raid attunements of guild members), "Feedback" tab (messages
-- for the developer) and "Debug" tab (network trace, diagnostic export; in the live build only after /ps debug). The
-- tabs are one ordered list (tabDefinitions).
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
-- lists that follow the (resizable) window, the Recipes table
local Table, RecipeTable = addon.Table, addon.RecipeTable
local createScrollList = Table.CreateResizableList
---@return table|nil the SavedVariables ui table (column, sort and window size settings)
local function interfaceSettings() return addon.db and addon.db.ui end
-- the four templates Widgets.TimeAgo reads from Text: Text["just now"], Text["{n}m ago"], Text["{n}h ago"], Text["{n}d ago"]
---@param timestamp integer|nil
---@return string
local function timeAgo(timestamp) return Widgets.TimeAgo(timestamp, Text) end
---@param frameName string
---@return table
local function createDialogFrame(frameName) return Widgets.CreateDialogFrame(frameName, addon.Log) end
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
---@type { count: integer, showIcon: boolean, hideNumber: boolean } unseen orders shown by UI.SetNotice
local noticeState = { count = 0, showIcon = false, hideNumber = false, drops = 0 }

---@class WindowState
local windowState = {
    tab = "recipes",
    professionIndex = 0,           -- 0 = all, else index into the professions list ({ key, name })
    text = "",
    mineOnly = false,
    categories = {},               -- checked category keys (Model.CategoryKey); empty = all
    selectedRecipe = nil,
    orderFilterIndex = 1,
    showClosed = false,
    selectedOrder = nil,
    offerText = "",
    offerMyProfessionsOnly = false,
    selectedOffer = nil,
    selectedKey = nil,             -- Misc Items, Keys mode: item id
    selectedAttunement = nil,      -- Misc Items, Attunements mode: attunement key
    selectedReputation = nil,      -- Misc Items, Reputation mode: row key (owner#factionID)
    reputationFaction = nil,       -- Misc Items, Reputation mode: faction filter (nil = all)
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
local recipeList, orderList, miscList
local refreshDebug   -- Debug tab (defined with the tab below)
local refreshFeedback   -- Feedback tab (defined with the tab below)
-- the live build shows the Debug tab only after /ps debug (this session); the development build always
local debugTabUnlocked = false
---@return boolean
local function debugTabAvailable() return addon.IS_DEVELOPMENT_BUILD and true or debugTabUnlocked end
---@type table[] rows of the Misc Items table (OfferViewRow, KeyViewRow or AttunementViewRow, by currentMiscMode)
local currentMiscRows = {}
---@type MiscMode the mode currentMiscRows were built for
local currentMiscMode = "offers"
---@type TableCell[] the Misc Items table's current column positions
local miscCells = {}
---@type table recipe detail panel widgets
local detailPanel = {}

---@return ProfessionChoice[]
local function professionChoices() return addon.Model.Professions(addon.Store) end

-- client item data for categories and the free-text search (looked up when called; Api loads before UI)
---@type fun(recipeID: integer): string|nil effect text of a recipe without an item, defined with the recipe tooltip below
local recipeEffectText
---@type RecipeLookups
local itemLookups = {
    class = function(itemID) return addon.Api.ItemCategoryInformation(itemID) end,
    label = function(categoryKey) return addon.Api.CategoryLabel(categoryKey) end,
    groupLabel = function(groupID) return addon.Api.CategoryGroupLabel(groupID) end,
    text = function(itemID) return addon.ItemText.Get(itemID) end,
    itemDetails = function(itemID) return addon.Api.ItemDetails(itemID) end,   -- quality, item level, required level
    effect = function(recipeID) return recipeEffectText(recipeID) end,          -- enchant effect text (search)
}
---@type RecipeCell[] the Recipes table's current column positions
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

-- Puts a Model.OpenAction on a secure button (out of combat only; the caller checks).
---@param secureButton table
---@param openAction { type: string, spell: integer|nil, macrotext: string|nil }
local function applyOpenAction(secureButton, openAction)
    secureButton:SetAttribute("type", openAction.type)
    secureButton:SetAttribute("spell", openAction.spell)
    secureButton:SetAttribute("macrotext", openAction.macrotext)
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
    professionButton:RegisterForClicks("AnyDown")   -- one cast per click (a second cast toggles the window closed); on Forever a secure action runs on the press, an "AnyUp"-only button casts nothing
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
            casts = professionRow and addon.Model.DescribeOpenAction(addon.Model.OpenAction(professionRow)) })
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
                    applyOpenAction(professionButton, addon.Model.OpenAction(professionRow))
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

-- the current Recipes tab filter; also used to build the category menu
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
    recipeList:UpdateLayout()   -- the column choice may have changed in the options (and with it the table width)
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
    -- the effect of a recipe without an item (enchant), one line under the title; full text in the tooltip
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

------------------------------------------------------------------ Craft button
-- Crafting needs the profession window open, and only a real click on a secure button may open it. So the
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
        applyOpenAction(craftButton, addon.Model.OpenAction(craftTarget))
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
    addon.Alerts.Seen()   -- looking at the board clears the badge
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

---@param mode MiscMode
---@return any the selected row key of that mode
local function selectedMiscKey(mode)
    if mode == "keys" then return windowState.selectedKey end
    if mode == "attunements" then return windowState.selectedAttunement end
    if mode == "reputation" then return windowState.selectedReputation end
    return windowState.selectedOffer
end

---@param mode MiscMode
---@param rowKey any
local function selectMiscRow(mode, rowKey)
    if mode == "keys" then windowState.selectedKey = rowKey
    elseif mode == "attunements" then windowState.selectedAttunement = rowKey
    elseif mode == "reputation" then windowState.selectedReputation = rowKey
    else windowState.selectedOffer = rowKey end
end

---@return table|nil the selected row of the shown mode
local function selectedMiscRow()
    local selectedKey = selectedMiscKey(currentMiscMode)
    for _, miscRow in ipairs(currentMiscRows) do if miscRow.key == selectedKey then return miscRow end end
end

---@return OfferViewRow|nil
local function selectedOfferRow()
    if currentMiscMode ~= "offers" then return nil end
    return selectedMiscRow()
end

---@param location string
---@return string
local function keyLocationLabel(location)
    if location == "keyring" then return Text["Key ring"] end
    if location == "bank" then return Text["Bank"] end
    return Text["Bags"]
end

-- faction names and standing labels from this client (Model falls back to the addon's own texts)
---@return ReputationLookups
local function reputationLookups()
    return { factionName = addon.Api.FactionName, standingLabel = addon.Api.StandingLabel }
end

-- layout only, no text: an empty tooltip line, and the indent of an item under a hint
local TOOLTIP_SPACER, TOOLTIP_INDENT = " ", "   "

---@type table<integer, string> colour of each standing (1 Hated .. 8 Exalted)
local STANDING_COLOR = { "cc2222", "ff3333", "ee6622", "ffff00", "33ff33", "33ff99", "33ffcc", "33ccff" }

---@param standing integer
---@param text string
---@return string
local function standingText(standing, text) return "|cff" .. (STANDING_COLOR[standing] or "ffffff") .. text .. "|r" end

-- the text under the list: dibs of an offer, holders of a key, who is attuned to a raid, what a standing unlocks next
---@param mode MiscMode
---@param selectedRow table|nil
---@return string
local function miscDetailText(mode, selectedRow)
    if mode == "keys" then
        if not selectedRow then return Text["Select a key to see who holds it and where."] end
        local holderTexts = {}
        for index, holder in ipairs(selectedRow.holders) do
            local locationLabels = {}
            for position, location in ipairs(holder.locations) do locationLabels[position] = keyLocationLabel(location) end
            local holderName = holder.mine and ("|cff33ff99" .. holder.whoName .. "|r") or holder.whoName
            holderTexts[index] = ("%s |cffaaaaaa(%s)|r"):format(holderName, table.concat(locationLabels, ", "))
        end
        return Format(Text["{name}: {list}"], { name = selectedRow.name, list = table.concat(holderTexts, "   ") })
    end
    if mode == "reputation" then
        if not selectedRow then return Text["Select a row to see what the next standing unlocks."] end
        local nextHint = addon.FactionHints.NextHint(selectedRow.factionID, selectedRow.standing)
        local nextText = nextHint and Format(Text["Next: {standing}: {hint}"], {
            standing = addon.Model.StandingLabel(nextHint.standing, reputationLookups()),
            hint = addon.FactionHints.HintText(nextHint, addon.Locale.code) }) or Text["Nothing more to unlock."]
        return Format(Text["{player}: {faction}, {standing} ({progress}). {next}"], { player = selectedRow.playerName,
            faction = selectedRow.name, standing = standingText(selectedRow.standing, selectedRow.standingLabel),
            progress = selectedRow.progressText, next = nextText })
    end
    if mode == "attunements" then
        if not selectedRow then return Text["Select a raid to see who is attuned."] end
        local myState = selectedRow.mine == true and Text["you are attuned"]
            or selectedRow.mine == false and Text["you are not attuned yet"] or Text["your attunement is not known yet"]
        return Format(Text["{name} ({state}). Attuned: {yes}. Not attuned yet: {no}."], { name = selectedRow.name, state = myState,
            yes = selectedRow.attuned ~= "" and selectedRow.attuned or "-", no = selectedRow.missing ~= "" and selectedRow.missing or "-" })
    end
    if not selectedRow then return Text["Select an offer to see who called dibs."] end
    if #selectedRow.dibs == 0 then return Text["No dibs yet."] end
    local dibTexts = {}
    for position, dibRow in ipairs(selectedRow.dibs) do
        local holderName = dibRow.mine and ("|cff33ff99" .. shortName(dibRow.who) .. "|r") or shortName(dibRow.who)
        dibTexts[position] = ("%d. %s |cffaaaaaa%s|r"):format(position, holderName, timeAgo(dibRow.t))
    end
    return Format(Text["Dibs: {list}"], { list = table.concat(dibTexts, "   ") })
end

---@param mode MiscMode
---@return string
local function miscEmptyText(mode)
    if mode == "keys" then
        return Text["No dungeon keys known yet. They are listed automatically from the bags, key ring and bank of every guild member."]
    end
    if mode == "attunements" then return Text["Nothing to show."] end
    if mode == "reputation" then
        return Text["No reputation known yet. Guild members on version 1.4.0 or newer share their standings automatically."]
    end
    return Text["No recipe items on offer yet. They are listed automatically from the bags, bank, mail, guild bank and auctions of every guild member."]
end

-- Cooldowns mode: the grid instead of the table (UI/CooldownGrid.lua); the table-only controls are hidden.
---@param isGrid boolean
local function showMiscGrid(isGrid)
    miscList:SetShown(not isGrid)
    mainFrame.miscHeader:SetShown(not isGrid)
    if mainFrame.miscColumnsButton then mainFrame.miscColumnsButton:SetShown(not isGrid) end
    mainFrame.offerDetailText:SetShown(not isGrid)
    if mainFrame.cooldownGrid then mainFrame.cooldownGrid.frame:SetShown(isGrid) end
    mainFrame.cooldownExpandButton:SetShown(isGrid)
    mainFrame.cooldownLegendText:SetShown(isGrid)
end

---@return CooldownLookups
local function cooldownLookups()
    local function isOnline(playerName)
        if addon.Api.IsOnline(playerName) then return true end
        -- dev build: the fake crafters of the Dev tools menu count as online
        return addon.IS_DEVELOPMENT_BUILD and addon.DevProbe ~= nil and addon.DevProbe.IsFakeOnline(playerName) or false
    end
    return { isOnline = isOnline, spellName = addon.Api.SpellName, itemName = addon.Api.ItemName, itemIcon = addon.Api.ItemIcon }
end

local function refreshCooldowns()
    local settings = interfaceSettings()
    local tiles = addon.Model.BuildCooldownTiles({ text = windowState.offerText, me = me(), now = addon.Utility.Now() },
        cooldownLookups())
    local expanded = settings and settings.cooldownExpanded == true
    local readyCrafts, crafterCount = 0, 0
    for _, tile in ipairs(tiles) do
        if tile.best and tile.best.state == "ready" then readyCrafts = readyCrafts + 1 end
        crafterCount = crafterCount + #tile.crafters
    end
    local shownTiles = expanded and addon.Model.ExpandCooldownTiles(tiles) or tiles
    local emptyText = (expanded and crafterCount == 0) and Text["Nobody in the guild is known to craft a timegated recipe yet."]
        or (#tiles == 0 and Text["Nothing to show."]) or nil
    if mainFrame.cooldownGrid then mainFrame.cooldownGrid:SetTiles(shownTiles, expanded, emptyText) end
    mainFrame.cooldownExpandButton:SetLabel(expanded and Text["One tile per craft"] or Text["One tile per crafter"])
    mainFrame.offerCountText:SetText(Format(Text["{n} ready to ask"], { n = readyCrafts }))
    mainFrame.offersEmptyText:SetShown(false)
end

local function refreshOffers()
    if not mainFrame or windowState.tab ~= "available" then return end
    local settings = interfaceSettings()
    local mode = addon.MiscTables.GetMode(settings)
    local isGrid = addon.MiscTables.IsGrid(mode)
    showMiscGrid(isGrid)
    if isGrid then
        currentMiscMode = mode
        setDropdownText(mainFrame.miscModeButton, addon.MiscTables.ModeLabel(mode))
        mainFrame.myProfessionsOnlyButton:SetShown(false)
        if mainFrame.reputationFactionButton then mainFrame.reputationFactionButton:SetShown(false) end
        for _, offerButton in ipairs({ mainFrame.dibsButton, mainFrame.hideOfferButton, mainFrame.whisperOwnerButton,
            mainFrame.whisperHolderButton }) do
            offerButton:SetShown(false)
        end
        mainFrame.offerSearchHint:SetText(Text["search craft or member"])
        refreshCooldowns()
        return
    end
    local columnTable = addon.MiscTables.Table(mode)
    local filterState = { text = windowState.offerText, myProfessionsOnly = windowState.offerMyProfessionsOnly, me = me() }
    local miscRows
    if mode == "keys" then miscRows = addon.Model.BuildKeyRows(filterState, addon.Api.ItemClass, addon.Api.ItemName)
    elseif mode == "attunements" then miscRows = addon.Model.BuildAttunementRows(filterState, addon.Api.ItemClass)
    elseif mode == "reputation" then
        miscRows = addon.Model.BuildReputationRows({ text = windowState.offerText, me = me(), faction = windowState.reputationFaction },
            reputationLookups())
    else miscRows = addon.Model.BuildOfferRows(addon.Store, filterState, addon.Api.ItemClass, addon.Api.ItemName) end
    columnTable.Sort(miscRows, columnTable.GetSort(settings))
    -- each row knows its mode: the relayout below may still redraw the previous mode's rows once
    for _, miscRow in ipairs(miscRows) do miscRow.miscMode = mode end
    currentMiscMode, currentMiscRows = mode, miscRows
    setDropdownText(mainFrame.miscModeButton, addon.MiscTables.ModeLabel(mode))
    local isOffers = mode == "offers"
    mainFrame.myProfessionsOnlyButton:SetShown(isOffers)
    if mainFrame.reputationFactionButton then
        mainFrame.reputationFactionButton:SetShown(mode == "reputation")
        local selectedFaction = windowState.reputationFaction
        setDropdownText(mainFrame.reputationFactionButton, selectedFaction
            and addon.Model.FactionName(selectedFaction, reputationLookups()) or Text["All factions"])
    end
    mainFrame.offerSearchHint:SetText(isOffers and Text["search item, owner or profession"]
        or mode == "keys" and Text["search key, dungeon or member"]
        or mode == "reputation" and Text["search faction, member or standing"] or Text["search raid or member"])
    miscList:UpdateLayout()   -- another mode has other columns
    miscList:SetData(miscRows)
    if mode == "keys" then mainFrame.offerCountText:SetText(Plural(#miscRows, Text["{n} key"], Text["{n} keys"]))
    elseif mode == "attunements" then mainFrame.offerCountText:SetText("")
    elseif mode == "reputation" then mainFrame.offerCountText:SetText(Plural(#miscRows, Text["{n} standing"], Text["{n} standings"]))
    else mainFrame.offerCountText:SetText(Plural(#miscRows, Text["{n} offer"], Text["{n} offers"])) end
    local selectedRow = selectedMiscRow()
    for _, offerButton in ipairs({ mainFrame.dibsButton, mainFrame.hideOfferButton, mainFrame.whisperOwnerButton }) do
        offerButton:SetShown(isOffers)
    end
    mainFrame.whisperHolderButton:SetShown(mode == "keys")
    if isOffers then
        mainFrame.dibsButton:SetLabel(selectedRow and selectedRow.mine and Text["Remove dibs"] or Text["Dibs"])
        mainFrame.dibsButton:SetEnabled(selectedRow ~= nil and selectedRow.canDib)
        mainFrame.hideOfferButton:SetEnabled(selectedRow ~= nil)
        mainFrame.whisperOwnerButton:SetEnabled(selectedRow ~= nil and selectedRow.canDib)
    end
    mainFrame.whisperHolderButton:SetEnabled(mode == "keys" and selectedRow ~= nil and addon.Model.KeyContact(selectedRow, me()) ~= nil)
    mainFrame.offerDetailText:SetText(miscDetailText(mode, selectedRow))
    mainFrame.offersEmptyText:SetText(miscEmptyText(mode))
    mainFrame.offersEmptyText:SetShown(#miscRows == 0)
end

---@alias TabName "recipes"|"orders"|"available"|"feedback"|"debug"

---@class TabDefinition
---@field key TabName
---@field label string display text
---@field width number minimum button width

-- The window's tabs, in button order. A function, so the labels are read in the language active when the window is
-- built.
---@return TabDefinition[]
local function tabDefinitions()
    return {
        { key = "recipes", label = Text["Recipes"], width = 90 },
        { key = "orders", label = Text["Orders"], width = 90 },
        { key = "available", label = Text["Misc Items"], width = 100 },
        { key = "feedback", label = Text["Feedback"], width = 90 },
        { key = "debug", label = Text["Debug"], width = 70 },
    }
end
UI.TabDefinitions = tabDefinitions

-- The Feedback tab is shown only where a message can arrive: the developer's character is in my guild roster (or I am
-- the developer, or this is a development build). The roster table is replaced on every roster update, so the answer
-- is cached per roster table.
local feedbackRosterCache = { roster = nil, readerInRoster = false }
---@return boolean
local function feedbackTabAvailable()
    if addon.IS_DEVELOPMENT_BUILD or addon.Feedback.IsReader(me()) then return true end
    local roster = addon.Communication and addon.Communication.roster
    if roster ~= feedbackRosterCache.roster then
        feedbackRosterCache.roster, feedbackRosterCache.readerInRoster = roster, addon.Feedback.ReaderInRoster(roster)
    end
    return feedbackRosterCache.readerInRoster
end

---@param tabKey TabName
---@return boolean
local function tabAvailable(tabKey)
    if tabKey == "debug" then return debugTabAvailable() end
    if tabKey == "feedback" then return feedbackTabAvailable() end
    return true
end

-- shows the available tab buttons side by side, in tabDefinitions order (a hidden one leaves no gap)
local function layoutTabButtons()
    local previousButton
    for _, tab in ipairs(tabDefinitions()) do
        local tabButton = mainFrame.tabButtons[tab.key]
        tabButton:ClearAllPoints()
        if tabAvailable(tab.key) then
            if previousButton then tabButton:SetPoint("LEFT", previousButton, "RIGHT", 4, 0) else tabButton:SetPoint("TOPLEFT", 12, -30) end
            tabButton:Show()
            previousButton = tabButton
        else
            tabButton:Hide()
        end
    end
end

local selectTab

function UI.Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end
    layoutTabButtons()
    if not tabAvailable(windowState.tab) then selectTab("recipes") return end   -- selectTab refreshes again
    refreshRecipes(); refreshDetail(); refreshOrders(); refreshOffers(); refreshFeedback(); refreshDebug(); refreshProfessionBar()
end

---@param tabName TabName
selectTab = function(tabName)
    if not tabAvailable(tabName) then tabName = "recipes" end
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

-- The effect text of a recipe that makes no item (enchants), read on this client by its recipe id as a
-- spell id: the spell DESCRIPTION only. It is empty until the client has loaded the spell (Api.SpellDescription requests
-- the load; SPELL_INFO redraws). The "spell:"/"enchant:" tooltips are not used: before the load they hold only the name,
-- tools and reagents. Found texts are cached for the session, misses are not.
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
        local effectText = recipeEffectText(recipeID)   -- enchants
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

------------------------------------------------------------------ Debug tab: network trace + export

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

-- name check table: column widths (716 in all, inside the 720 wide header); Location and the full behaviour are in the tooltip
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
    if addon.IS_DEVELOPMENT_BUILD and addon.DevProbe then   -- dev build only: fake data, fake triggers and probes in one menu
        local DevProbe = addon.DevProbe
        local devToolsButton = createMenuDropdown(debugTab, "WowStyle1DropdownTemplate", 120)
        if devToolsButton then
            devToolsButton:SetupMenu(function(_, rootMenu)
                for sectionIndex, section in ipairs(DevProbe.SECTIONS) do
                    if sectionIndex > 1 and rootMenu.CreateDivider then rootMenu:CreateDivider() end
                    if rootMenu.CreateTitle then rootMenu:CreateTitle(section) end
                    for _, entry in ipairs(DevProbe.ENTRIES) do
                        if entry.section == section then
                            rootMenu:CreateButton(entry.label, function() DevProbe.RunEntry(entry.key); refreshDebug() end)
                        end
                    end
                end
            end)
            setDropdownText(devToolsButton, Text["Dev tools"])
        else   -- no menus: list the entries in the chat (/psd fake <key> runs one)
            devToolsButton = createButton(debugTab, Text["Dev tools"], 120, 22, function() DevProbe.PrintEntries() end)
        end
        devToolsButton:SetPoint("RIGHT", exportButton, "LEFT", -8, 0)
        mainFrame.devToolsButton = devToolsButton
    end
    mainFrame.debugStatusText = createFontString(debugTab, "GameFontHighlightSmall")
    mainFrame.debugStatusText:SetPoint("TOPLEFT", 0, -28)
    mainFrame.debugStatusText:SetPoint("RIGHT", 0, 0)
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
    -- profession: dropdown with one entry per profession; old cycle button if the client has no menus
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

    -- category: checkbox menu built from the items the recipes of this profession make
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

    -- free-text search: words in any order over name, profession, reagents, category and the effect text (Model.BuildRecipeRows)
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

    -- effect texts are read 8 at a time every 0.2 s while this tab is open, so the first search does not freeze the game
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
        -- item data arrived (quality, levels): one redraw per second at most, however many items load
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

    -- a table (header + columns from the options, name in item-quality colour); it fills the space left of
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
        -- a narrow window: the table keeps its minimum width and scrolls sideways instead of running under the detail panel
        return RecipeTable.TableWidth(recipeCells)
    end
    recipeList.onHorizontalScroll = function(offset) recipeHeader:SetHorizontalOffset(offset) end
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
        craftButton:RegisterForClicks("AnyDown")   -- one cast per click, see the profession buttons
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

-- The Misc Items tab: a mode dropdown (Recipe items, Keys, Attunements, Reputation) over one table whose columns, sort and column
-- choice belong to the shown mode (MiscTables). The search box serves every mode; the buttons under the list depend on it.
---@param availableTab table
local function buildAvailableTab(availableTab)
    local MiscTables = addon.MiscTables
    local function chooseMode(mode)
        MiscTables.SetMode(interfaceSettings(), mode)
        refreshOffers()
    end
    local modeDropdown = createMenuDropdown(availableTab, "WowStyle1DropdownTemplate", 150)
    if modeDropdown then
        modeDropdown:SetupMenu(function(_, rootMenu)
            local function isSelectedMode(mode) return MiscTables.GetMode(interfaceSettings()) == mode end
            for _, mode in ipairs(MiscTables.MODES) do rootMenu:CreateRadio(MiscTables.ModeLabel(mode), isSelectedMode, chooseMode, mode) end
        end)
    else   -- no menus: cycle through the modes
        modeDropdown = createButton(availableTab, MiscTables.ModeLabel(MiscTables.DEFAULT_MODE), 150, 22, function()
            local currentMode, nextMode = MiscTables.GetMode(interfaceSettings()), MiscTables.MODES[1]
            for position, mode in ipairs(MiscTables.MODES) do
                if mode == currentMode then nextMode = MiscTables.MODES[position % #MiscTables.MODES + 1] end
            end
            chooseMode(nextMode)
        end)
    end
    mainFrame.miscModeButton = modeDropdown
    modeDropdown:SetPoint("TOPLEFT", 0, -10)

    local offerSearchBox = CreateFrame("EditBox", nil, availableTab, "InputBoxTemplate")
    offerSearchBox:SetSize(200, 20); offerSearchBox:SetPoint("LEFT", modeDropdown, "RIGHT", 14, 0); offerSearchBox:SetAutoFocus(false)
    offerSearchBox:SetScript("OnTextChanged", function(self) windowState.offerText = self:GetText(); refreshOffers() end)
    offerSearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    mainFrame.offerSearchHint = createFontString(availableTab, "GameFontDisableSmall")
    mainFrame.offerSearchHint:SetPoint("BOTTOMLEFT", offerSearchBox, "TOPLEFT", 0, 0)
    mainFrame.offerSearchHint:SetText(Text["search item, owner or profession"])
    mainFrame.myProfessionsOnlyButton = createButton(availableTab, Text["Only my professions"], 150, 22, function()
        windowState.offerMyProfessionsOnly = not windowState.offerMyProfessionsOnly
        mainFrame.myProfessionsOnlyButton:SetLabel(windowState.offerMyProfessionsOnly and (Text["Only my professions"] .. " *")
            or Text["Only my professions"])
        refreshOffers()
    end)
    mainFrame.myProfessionsOnlyButton:SetPoint("LEFT", offerSearchBox, "RIGHT", 8, 0)

    -- Reputation mode: the faction filter (All factions, or the factions somebody in the guild has a standing with)
    local function chooseFaction(factionID)
        windowState.reputationFaction = factionID ~= 0 and factionID or nil
        windowState.selectedReputation = nil
        refreshOffers()
    end
    local factionDropdown = createMenuDropdown(availableTab, "WowStyle1DropdownTemplate", 170)
    if factionDropdown then
        factionDropdown:SetupMenu(function(_, rootMenu)
            local function isSelected(factionID) return (windowState.reputationFaction or 0) == factionID end
            rootMenu:CreateRadio(Text["All factions"], isSelected, chooseFaction, 0)
            for _, factionChoice in ipairs(addon.Model.ReputationFactions(reputationLookups())) do
                rootMenu:CreateRadio(factionChoice.name, isSelected, chooseFaction, factionChoice.id)
            end
        end)
    else   -- no menus: cycle through All and the factions
        factionDropdown = createButton(availableTab, Text["All factions"], 170, 22, function()
            local factionChoices = addon.Model.ReputationFactions(reputationLookups())
            local nextFaction = factionChoices[1] and factionChoices[1].id or 0
            for position, factionChoice in ipairs(factionChoices) do
                if factionChoice.id == windowState.reputationFaction then
                    nextFaction = factionChoices[position + 1] and factionChoices[position + 1].id or 0
                end
            end
            chooseFaction(nextFaction)
        end)
    end
    factionDropdown:SetPoint("LEFT", offerSearchBox, "RIGHT", 8, 0)
    factionDropdown:Hide()
    mainFrame.reputationFactionButton = factionDropdown

    -- columns of the shown mode: a checkbox menu (the name column is always shown)
    local columnsDropdown = createMenuDropdown(availableTab, "WowStyle1FilterDropdownTemplate", 100)
    if columnsDropdown then
        columnsDropdown:SetupMenu(function(_, rootMenu)
            local columnTable = MiscTables.Table(MiscTables.GetMode(interfaceSettings()))
            local function isShown(columnKey) return columnTable.ColumnShown(interfaceSettings(), columnKey) end
            local function toggle(columnKey)
                columnTable.SetColumn(interfaceSettings(), columnKey, not columnTable.ColumnShown(interfaceSettings(), columnKey))
                refreshOffers()
            end
            for _, columnKey in ipairs(columnTable.OPTIONAL_KEYS) do
                rootMenu:CreateCheckbox(columnTable.ColumnLabel(columnKey), isShown, toggle, columnKey)
            end
        end)
        setDropdownText(columnsDropdown, Text["Columns"])
        columnsDropdown:SetPoint("TOPRIGHT", availableTab, "TOPRIGHT", -80, -10)
    end
    mainFrame.miscColumnsButton = columnsDropdown
    mainFrame.offerCountText = createFontString(availableTab, "GameFontNormalSmall", "RIGHT")
    mainFrame.offerCountText:SetPoint("TOPRIGHT", availableTab, "TOPRIGHT", -4, -14)

    local miscHeader = Table.CreateHeader(availableTab, function(columnKey)
        MiscTables.Table(MiscTables.GetMode(interfaceSettings())).ClickHeader(interfaceSettings(), columnKey)
        refreshOffers()
    end)
    mainFrame.miscHeader = miscHeader
    ---@param row table
    ---@param offerRow OfferViewRow
    local function fillOfferRow(row, offerRow)
        row.label:SetText(offerRow.name)
        Table.SetCell(row, "profession", "|cff888888" .. (offerRow.profession or "") .. "|r")
        Table.SetCell(row, "owner", "|cffaaaaaa" .. (shortName(offerRow.ownerName) or "") .. "|r")
        Table.SetCell(row, "locations", "|cff999999" .. offerRow.locations .. "|r")
        Table.SetCell(row, "total", tostring(offerRow.total))
        Table.SetCell(row, "dibs", (offerRow.mine and "|cff33ff99* |r" or "") .. tostring(offerRow.dibCount))
        local function showItemTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. offerRow.itemID)
            if offerRow.canDib then
                GameTooltip:AddLine(Format(Text["Click the icon: whisper {name} with this item"], { name = offerRow.ownerName }), 0.6, 0.8, 1, true)
            end
            GameTooltip:Show()
        end
        row:SetScript("OnEnter", showItemTooltip)
        row.onIconEnter = showItemTooltip
        row.onIconClick = function()
            if offerRow.canDib then
                whisper(offerRow.owner, function()
                    return addon.Model.ChatText(addon.Api.ItemLink(offerRow.itemID), addon.Api.ItemName(offerRow.itemID))
                end)
            end
        end
    end
    ---@param row table
    ---@param keyRow KeyViewRow
    local function fillKeyRow(row, keyRow)
        local keyName = keyRow.holderCount == 0 and ("|cff808080" .. keyRow.name .. "|r") or keyRow.name
        row.label:SetText(keyRow.mine and (keyName .. " |cff33ff99*|r") or keyName)
        Table.SetCell(row, "instance", "|cffaaaaaa" .. keyRow.instance .. "|r")
        Table.SetCell(row, "holderCount", tostring(keyRow.holderCount))
        Table.SetCell(row, "holderNames", "|cff999999" .. keyRow.holderNames .. "|r")
        local contactName = addon.Model.KeyContact(keyRow, me())
        local function showKeyTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. keyRow.itemID)
            if contactName then
                GameTooltip:AddLine(Format(Text["Click the icon: whisper {name} about this key"], { name = shortName(contactName) }),
                    0.6, 0.8, 1, true)
            end
            GameTooltip:Show()
        end
        row:SetScript("OnEnter", showKeyTooltip)
        row.onIconEnter = showKeyTooltip
        row.onIconClick = function()
            whisper(contactName, function()
                return addon.Model.ChatText(addon.Api.ItemLink(keyRow.itemID), addon.Api.ItemName(keyRow.itemID))
            end)
        end
    end
    ---@param row table
    ---@param attunementRow AttunementViewRow
    local function fillAttunementRow(row, attunementRow)
        local marker = attunementRow.mine == true and " |cff33ff99*|r" or ""
        row.label:SetText(attunementRow.name .. marker)
        Table.SetCell(row, "attunedCount", tostring(attunementRow.attunedCount))
        Table.SetCell(row, "attuned", "|cff33ff99" .. attunementRow.attuned .. "|r")
        Table.SetCell(row, "missingCount", tostring(attunementRow.missingCount))
        Table.SetCell(row, "missing", "|cffaaaaaa" .. attunementRow.missing .. "|r")
        local function showAttunementTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(attunementRow.name, 1, 0.82, 0)
            GameTooltip:AddLine(Format(Text["Attuned: {list}"], { list = attunementRow.attuned ~= "" and attunementRow.attuned or "-" }),
                0.2, 1, 0.6, true)
            GameTooltip:AddLine(Format(Text["Not attuned yet: {list}"], { list = attunementRow.missing ~= "" and attunementRow.missing or "-" }),
                0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
        row:SetScript("OnEnter", showAttunementTooltip)
        row.onIconEnter = showAttunementTooltip
        row.onIconClick = nil
    end
    ---@param row table
    ---@param reputationRow ReputationViewRow
    local function fillReputationRow(row, reputationRow)
        row.label:SetText(reputationRow.mine and (reputationRow.name .. " |cff33ff99*|r") or reputationRow.name)
        Table.SetCell(row, "player", reputationRow.mine and ("|cff33ff99" .. reputationRow.playerName .. "|r") or reputationRow.playerName)
        Table.SetCell(row, "standing", standingText(reputationRow.standing, reputationRow.standingLabel))
        Table.SetCell(row, "progress", "|cffaaaaaa" .. reputationRow.progressText .. "|r")
        Table.SetCell(row, "updated", "|cff999999" .. timeAgo(reputationRow.updated) .. "|r")
        local canWhisper = not reputationRow.mine
        -- what each standing of the faction unlocks; the row player's reached standings green, the next one white
        local function showReputationTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(reputationRow.name, 1, 0.82, 0)
            GameTooltip:AddLine(Format(Text["{player}: {standing} ({progress})"], { player = reputationRow.playerName,
                standing = standingText(reputationRow.standing, reputationRow.standingLabel), progress = reputationRow.progressText }),
                1, 1, 1, true)
            local hintLines = addon.Model.FactionHintLines(reputationRow.factionID, reputationRow.standing, addon.Locale.code,
                reputationLookups())
            if #hintLines > 0 then
                GameTooltip:AddLine(TOOLTIP_SPACER)
                GameTooltip:AddLine(Text["What each standing unlocks:"], 1, 0.82, 0)
            end
            for _, hintLine in ipairs(hintLines) do
                local red, green, blue = 0.55, 0.55, 0.55
                if hintLine.state == "reached" then red, green, blue = 0.2, 1, 0.6
                elseif hintLine.state == "next" then red, green, blue = 1, 1, 1 end
                local marker = hintLine.state == "next" and "> " or ""
                GameTooltip:AddLine(marker .. hintLine.label .. ": " .. hintLine.text, red, green, blue, true)
                for _, itemID in ipairs(hintLine.items) do
                    GameTooltip:AddLine(TOOLTIP_INDENT .. (addon.Api.ItemName(itemID) or Format(Text["Item #{id}"], { id = itemID })), red, green, blue, true)
                end
            end
            GameTooltip:AddLine(TOOLTIP_SPACER)
            GameTooltip:AddLine(Format(Text["Hints are static notes, last checked {date}."], { date = addon.FactionHints.CHECKED }),
                0.5, 0.5, 0.5, true)
            if canWhisper then
                GameTooltip:AddLine(Format(Text["Click the icon or the name: whisper {name}"], { name = reputationRow.playerName }), 0.6, 0.8, 1, true)
            end
            GameTooltip:Show()
        end
        row:SetScript("OnEnter", showReputationTooltip)
        row.onIconEnter = showReputationTooltip
        row.onIconClick = canWhisper and function() whisper(reputationRow.who) end or nil
        -- the player's name whispers too (my own name selects the row like any other cell)
        Table.SetCellClick(row, "player", canWhisper and function() whisper(reputationRow.who) end or nil)
    end
    miscList = createScrollList(availableTab, Table.CreateTableRow, function(row, miscRow)
        local mode = miscRow.miscMode or currentMiscMode
        Table.LayoutRow(row, miscCells)
        row.icon:SetTexture(miscRow.icon or QUESTION_MARK_ICON)
        row.selectionHighlight:SetShown(miscRow.key == selectedMiscKey(mode))
        row:SetScript("OnClick", function() selectMiscRow(mode, miscRow.key); refreshOffers() end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if mode == "keys" then fillKeyRow(row, miscRow)
        elseif mode == "attunements" then fillAttunementRow(row, miscRow)
        elseif mode == "reputation" then fillReputationRow(row, miscRow)
        else fillOfferRow(row, miscRow) end
    end)
    miscList:SetPoint("TOPLEFT", 0, -58); miscList:SetPoint("BOTTOMRIGHT", 0, 112)
    miscHeader:SetPoint("TOPLEFT", availableTab, "TOPLEFT", 0, -38)
    miscHeader:SetPoint("RIGHT", miscList, "RIGHT", -Table.SLIDER_SPACE, 0)
    miscList.onLayout = function(list)
        local settings = interfaceSettings()
        local columnTable = MiscTables.Table(MiscTables.GetMode(settings))
        miscCells = columnTable.Layout(columnTable.VisibleColumns(settings), list:ContentWidth())
        miscHeader:SetColumns(miscCells, columnTable.GetSort(settings), columnTable.ColumnLabel)
        return columnTable.TableWidth(miscCells)
    end
    miscList.onHorizontalScroll = function(offset) miscHeader:SetHorizontalOffset(offset) end
    mainFrame.offersEmptyText = createFontString(availableTab, "GameFontDisable", "CENTER")
    mainFrame.offersEmptyText:SetPoint("CENTER", miscList, "CENTER", 0, 0); mainFrame.offersEmptyText:SetWidth(520)
    mainFrame.offerDetailText = createFontString(availableTab, "GameFontHighlightSmall")
    mainFrame.offerDetailText:SetPoint("TOPLEFT", miscList, "BOTTOMLEFT", 4, -8); mainFrame.offerDetailText:SetPoint("RIGHT", availableTab, "RIGHT", -8, 0)
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
    -- Keys mode: whisper somebody who holds the selected key
    mainFrame.whisperHolderButton = createButton(availableTab, Text["Whisper a holder"], 140, 24, function()
        local selectedRow = currentMiscMode == "keys" and selectedMiscRow()
        if not selectedRow then return end
        whisper(addon.Model.KeyContact(selectedRow, me()), function()
            return addon.Model.ChatText(addon.Api.ItemLink(selectedRow.itemID), addon.Api.ItemName(selectedRow.itemID))
        end)
    end)
    mainFrame.whisperHolderButton:SetPoint("BOTTOMLEFT", 0, 0)

    -- Cooldowns mode: the tile grid, a switch between one tile per craft and one per crafter, a short legend
    mainFrame.cooldownExpandButton = createButton(availableTab, Text["One tile per crafter"], 170, 22, function()
        local settings = interfaceSettings()
        if settings then settings.cooldownExpanded = not settings.cooldownExpanded end
        refreshOffers()
    end)
    mainFrame.cooldownExpandButton:SetPoint("LEFT", offerSearchBox, "RIGHT", 8, 0)
    mainFrame.cooldownExpandButton:Hide()
    local gridCreated, grid = pcall(addon.CooldownGrid.Create, availableTab, {
        whisper = whisper,
        timeAgo = timeAgo,
        onExpire = function() if mainFrame:IsShown() then refreshOffers() end end,
    })
    if gridCreated then
        mainFrame.cooldownGrid = grid
        grid.frame:SetPoint("TOPLEFT", 0, -40); grid.frame:SetPoint("BOTTOMRIGHT", -26, 36)   -- the scroll bar sits to the right of the frame
        grid.frame:Hide()
    else
        addon.Log.Error("window.cooldownGrid", "the cooldown grid could not be created", { error = tostring(grid) })
    end
    mainFrame.cooldownLegendText = createFontString(availableTab, "GameFontDisableSmall")
    mainFrame.cooldownLegendText:SetPoint("BOTTOMLEFT", 4, 8); mainFrame.cooldownLegendText:SetPoint("RIGHT", availableTab, "RIGHT", -8, 0)
    mainFrame.cooldownLegendText:SetText(Text["Glowing: someone online can craft it now. Badge: crafters ready / all. ?: someone has not shared a cooldown yet. Click to whisper, right-click to choose who."])
    mainFrame.cooldownLegendText:SetWordWrap(true)
    mainFrame.cooldownLegendText:Hide()
end

------------------------------------------------------------------ Feedback tab: messages for the developer
-- Everyone: a type dropdown, a text box (filled with the type's template), "Attach diagnostic info" and Send. Fire and
-- forget: the sender sees no status. The developer's client (Feedback.IsReader) also lists every received message with
-- Whisper, the diagnostic snapshot and three status buttons; the status stays on that client.

local FEEDBACK_TYPE_ICON = { feedback = "Interface\\Icons\\INV_Letter_01", feature = "Interface\\Icons\\INV_Misc_Gear_01",
    bug = "Interface\\Icons\\Spell_Nature_InsectSwarm" }
local FEEDBACK_STATUS_ICON = { declined = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    answered = "Interface\\GossipFrame\\GossipGossipIcon", fixed = "Interface\\RaidFrame\\ReadyCheck-Ready" }
-- the sender's own view: sent / delivered (the developer's client asked for them) / waiting
local FEEDBACK_DELIVERY_ICON = { sent = "Interface\\Icons\\INV_Letter_01", delivered = "Interface\\RaidFrame\\ReadyCheck-Ready",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting" }

---@param feedbackType string
---@return string
local function feedbackTypeLabel(feedbackType)
    local labels = { feedback = Text["Feedback"], feature = Text["Feature request"], bug = Text["Bug"] }
    return labels[feedbackType] or tostring(feedbackType)
end

---@param feedbackType string
---@return string the text put into the box when that type is chosen
local function feedbackTemplate(feedbackType)
    local templates = {
        feedback = Text["What do you like, what bothers you?"],
        feature = Text["I would like to ... so that ..."],
        bug = table.concat({ Text["What I did:"], Text["What happened:"], Text["What I expected:"] }, "\n"),
    }
    return templates[feedbackType] or ""
end

---@param status string
---@return string
local function feedbackStatusLabel(status)
    local labels = { declined = Text["Declined"], answered = Text["Answered"], fixed = Text["Fixed"] }
    return labels[status] or tostring(status)
end

---@class FeedbackFormState
local feedbackState = { type = "feedback", attach = false, selectedKey = nil, sentNotice = nil }
---@type FeedbackRow[]
local currentFeedbackRows = {}
local feedbackList

-- whether the box holds nothing of the player's own: empty or one of the templates unchanged
---@param text string
---@return boolean
local function isUntouchedFeedbackText(text)
    local Feedback = addon.Feedback
    local cleanText = Feedback.CleanText(text)
    if not cleanText then return true end
    for _, feedbackType in ipairs(Feedback.TYPES) do
        if cleanText == Feedback.CleanText(feedbackTemplate(feedbackType)) then return true end
    end
    return false
end

-- the diagnostic snapshot of a bug report: versions, sync state, the newest log lines
---@return string
local function bugSnapshot()
    local Communication, database, Count = addon.Communication, addon.db or {}, addon.Utility.Count
    local identityOk, identity = pcall(function() return addon.Api.IdentityInformation() end)
    local syncLine = ("active=%s queue=%d sendFailures=%d roster=%d chars=%d orders=%d offers=%d access=%d"):format(
        tostring(Communication.active), #(Communication.queue or {}), Communication.sendFailures or 0,
        Count(Communication.roster), Count(database.chars), Count(database.orders), Count(database.offers), Count(database.access))
    return addon.Feedback.Snapshot({
        version = addon.VERSION, protocol = addon.PROTOCOL_MAJOR .. "." .. addon.PROTOCOL_MINOR, schema = addon.Store.SCHEMA,
        locale = addon.Locale.clientCode, client = identityOk and type(identity) == "table" and identity.build or nil,
        sync = syncLine, logLines = database.debug,
    })
end

---@return FeedbackRow|nil
local function selectedFeedbackRow()
    for _, feedbackRow in ipairs(currentFeedbackRows) do
        if feedbackRow.key == feedbackState.selectedKey then return feedbackRow end
    end
    return nil
end

refreshFeedback = function()
    if not mainFrame or windowState.tab ~= "feedback" then return end
    local Feedback = addon.Feedback
    setDropdownText(mainFrame.feedbackTypeButton, feedbackTypeLabel(feedbackState.type))
    local summary = Feedback.MySummary(me())
    setDropdownText(mainFrame.myFeedbackButton, Format(Text["My messages ({n})"], { n = summary.sent }))
    mainFrame.feedbackCounters.sent.count:SetText(tostring(summary.sent))
    mainFrame.feedbackCounters.delivered.count:SetText(tostring(summary.delivered))
    mainFrame.feedbackCounters.waiting.count:SetText(tostring(summary.waiting))
    mainFrame.feedbackNoticeText:SetText(feedbackState.sentNotice or "")
    local isReader = Feedback.IsReader(me())
    mainFrame.feedbackReaderFrame:SetShown(isReader)
    if not isReader then return end
    currentFeedbackRows = Feedback.List()
    feedbackList:SetData(currentFeedbackRows)
    mainFrame.feedbackEmptyText:SetShown(#currentFeedbackRows == 0)
    local selectedRow = selectedFeedbackRow()
    if selectedRow then
        local header = Format(Text["{type} from {name}, {age}"], { type = feedbackTypeLabel(selectedRow.k),
            name = addon.Utility.Escape(shortName(selectedRow.owner) or "?"), age = timeAgo(selectedRow.t) })
        mainFrame.feedbackDetailText:SetText("|cffffd100" .. header .. "|r\n" .. addon.Utility.Escape(selectedRow.text))
    else
        mainFrame.feedbackDetailText:SetText(Text["Select a message."])
    end
    mainFrame.feedbackWhisperButton:SetEnabled(selectedRow ~= nil and selectedRow.owner ~= me())
    mainFrame.feedbackSnapshotButton:SetEnabled(selectedRow ~= nil and selectedRow.log ~= nil)
    for status, statusButton in pairs(mainFrame.feedbackStatusButtons) do
        statusButton:SetEnabled(selectedRow ~= nil)
        statusButton:SetAlpha((selectedRow and selectedRow.status == status) and 1 or 0.4)
    end
end

---@param feedbackType string
local function chooseFeedbackType(feedbackType)
    local feedbackBox = mainFrame.feedbackBox
    if isUntouchedFeedbackText(feedbackBox:GetText() or "") then feedbackBox:SetText(feedbackTemplate(feedbackType)) end
    feedbackState.type = feedbackType
    feedbackState.attach = feedbackType == "bug"
    mainFrame.feedbackAttachCheck:SetChecked(feedbackState.attach)
    feedbackState.sentNotice = nil
    refreshFeedback()
end

local function sendFeedback()
    local text = mainFrame.feedbackBox:GetText() or ""
    if isUntouchedFeedbackText(text) then
        feedbackState.sentNotice = "|cffff9933" .. Text["Write something first."] .. "|r"
        refreshFeedback()
        return
    end
    local snapshot = feedbackState.attach and bugSnapshot() or nil
    local added, refusal = addon.Feedback.Add(me(), feedbackState.type, text, addon.Utility.Now(), snapshot)
    addon.Log.Information("window.feedback", "a feedback message was sent", { type = feedbackState.type, added = added,
        refusal = refusal, bytes = #text, snapshotBytes = snapshot and #snapshot or 0 })
    if added then
        feedbackState.sentNotice = "|cff33ff99" .. Text["Sent. Thank you!"] .. "|r"
        mainFrame.feedbackBox:SetText(feedbackTemplate(feedbackState.type))
        mainFrame.feedbackBox:ClearFocus()
        addon.Events.Fire("FEEDBACK_CHANGED")
    elseif refusal == "duplicate" then
        feedbackState.sentNotice = "|cffff9933" .. Text["You already sent this message."] .. "|r"
    else
        feedbackState.sentNotice = "|cffff9933" .. Text["Write something first."] .. "|r"
    end
    refreshFeedback()
end
UI.SendFeedback = sendFeedback

---@param feedbackTab table
local function buildFeedbackTab(feedbackTab)
    local Feedback = addon.Feedback
    local typeDropdown = createMenuDropdown(feedbackTab, "WowStyle1DropdownTemplate", 150)
    if typeDropdown then
        typeDropdown:SetupMenu(function(_, rootMenu)
            local function isSelectedType(feedbackType) return feedbackState.type == feedbackType end
            for _, feedbackType in ipairs(Feedback.TYPES) do
                rootMenu:CreateRadio(feedbackTypeLabel(feedbackType), isSelectedType, chooseFeedbackType, feedbackType)
            end
        end)
    else   -- no menus: cycle through the types
        typeDropdown = createButton(feedbackTab, feedbackTypeLabel(feedbackState.type), 150, 22, function()
            for position, feedbackType in ipairs(Feedback.TYPES) do
                if feedbackType == feedbackState.type then
                    chooseFeedbackType(Feedback.TYPES[position % #Feedback.TYPES + 1])
                    return
                end
            end
        end)
    end
    typeDropdown:SetPoint("TOPLEFT", 0, -4)
    mainFrame.feedbackTypeButton = typeDropdown

    local attachCheck = CreateFrame("CheckButton", nil, feedbackTab, "UICheckButtonTemplate")
    attachCheck:SetSize(22, 22); attachCheck:SetPoint("LEFT", typeDropdown, "RIGHT", 14, 0)
    attachCheck:SetScript("OnClick", function(self) feedbackState.attach = self:GetChecked() and true or false end)
    attachCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Text["Attach diagnostic info"], 1, 1, 1)
        GameTooltip:AddLine(Text["Adds the addon version, the sync state and the newest log lines (they can name guild members), so the developer can find the cause."],
            0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    attachCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local attachLabel = createFontString(feedbackTab, "GameFontHighlightSmall")
    attachLabel:SetPoint("LEFT", attachCheck, "RIGHT", 2, 0); attachLabel:SetText(Text["Attach diagnostic info"])
    mainFrame.feedbackAttachCheck = attachCheck

    local sendButton = createButton(feedbackTab, Text["Send"], 90, 22, sendFeedback)
    sendButton:SetPoint("TOPRIGHT", 0, -4)
    local hintText = createFontString(feedbackTab, "GameFontDisableSmall", "RIGHT")
    hintText:SetPoint("RIGHT", sendButton, "LEFT", -10, 0); hintText:SetPoint("LEFT", attachLabel, "RIGHT", 12, 0)
    hintText:SetText(Text["Goes to the addon developer only."])

    -- the text box: multi-line, limited to what a message keeps
    local boxFrame = CreateFrame("Button", nil, feedbackTab)
    boxFrame:SetPoint("TOPLEFT", 0, -32); boxFrame:SetPoint("RIGHT", feedbackTab, "RIGHT", 0, 0); boxFrame:SetHeight(64)
    local boxBackground = boxFrame:CreateTexture(nil, "BACKGROUND"); boxBackground:SetAllPoints(); boxBackground:SetColorTexture(0, 0, 0, 0.45)
    local feedbackBox = CreateFrame("EditBox", nil, boxFrame)
    feedbackBox:SetMultiLine(true); feedbackBox:SetAutoFocus(false)
    feedbackBox:SetMaxBytes(Feedback.MAXIMUM_TEXT_BYTES + 1)
    feedbackBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    feedbackBox:SetPoint("TOPLEFT", 6, -4); feedbackBox:SetPoint("BOTTOMRIGHT", -6, 4)
    feedbackBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    feedbackBox:SetText(feedbackTemplate(feedbackState.type))
    boxFrame:SetScript("OnClick", function() feedbackBox:SetFocus() end)
    mainFrame.feedbackBox = feedbackBox

    -- under the box: "My messages" menu (my own messages with their delivery icon), counters, the last send result
    local function myMessagesTooltip(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
        GameTooltip:SetText(Text["Feedback"], 1, 1, 1)
        GameTooltip:AddLine(Text["Ideas, wishes and bug reports help to improve ProfessionShare. You get no answer inside the addon; the developer may whisper you."],
            0.8, 0.8, 0.8, true)
    end
    ---@param myRow MyFeedbackRow
    ---@return string
    local function myMessageLine(myRow)
        local icon = myRow.delivered and FEEDBACK_DELIVERY_ICON.delivered or FEEDBACK_DELIVERY_ICON.waiting
        return ("|T%s:14|t %s: %s"):format(icon, feedbackTypeLabel(myRow.k),
            addon.Utility.Escape(addon.Utility.TruncateUtf8(myRow.text, 60)))
    end
    local myFeedbackButton = createMenuDropdown(feedbackTab, "WowStyle1DropdownTemplate", 150)
    if myFeedbackButton then
        myFeedbackButton:SetupMenu(function(_, rootMenu)
            local summary = Feedback.MySummary(me())
            local function addLine(label)
                if rootMenu.CreateTitle then rootMenu:CreateTitle(label) else rootMenu:CreateButton(label, function() end) end
            end
            if #summary.rows == 0 then addLine(Text["No messages sent yet."]) end
            for _, myRow in ipairs(summary.rows) do addLine(myMessageLine(myRow)) end
        end)
        myFeedbackButton:HookScript("OnEnter", function(self) myMessagesTooltip(self); GameTooltip:Show() end)
        myFeedbackButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
    else   -- no menus: the list is the button's tooltip
        myFeedbackButton = createButton(feedbackTab, Format(Text["My messages ({n})"], { n = 0 }), 150, 22, function() end)
        myFeedbackButton:SetScript("OnEnter", function(self)
            myMessagesTooltip(self)
            local summary = Feedback.MySummary(me())
            if #summary.rows == 0 then GameTooltip:AddLine(Text["No messages sent yet."], 1, 1, 1) end
            for _, myRow in ipairs(summary.rows) do GameTooltip:AddLine(myMessageLine(myRow), 1, 1, 1) end
            GameTooltip:Show()
        end)
        myFeedbackButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    myFeedbackButton:SetPoint("TOPLEFT", boxFrame, "BOTTOMLEFT", 0, -3)
    mainFrame.myFeedbackButton = myFeedbackButton

    -- one icon with a number; the tooltip explains it
    local function createCounter(icon, title, explanation)
        local counter = CreateFrame("Frame", nil, feedbackTab)
        counter:SetSize(44, 20)
        local counterIcon = counter:CreateTexture(nil, "ARTWORK"); counterIcon:SetSize(16, 16); counterIcon:SetPoint("LEFT", 0, 0)
        counterIcon:SetTexture(icon)
        counter.count = createFontString(counter, "GameFontHighlight"); counter.count:SetPoint("LEFT", counterIcon, "RIGHT", 4, 0)
        counter:EnableMouse(true)
        counter:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(explanation, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        counter:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return counter
    end
    mainFrame.feedbackCounters = {
        sent = createCounter(FEEDBACK_DELIVERY_ICON.sent, Text["Sent"],
            Format(Text["Messages you sent that are still kept (the newest {max})."], { max = Feedback.MAXIMUM_ITEMS })),
        delivered = createCounter(FEEDBACK_DELIVERY_ICON.delivered, Text["Delivered"], Text["The developer's client has picked them up."]),
        waiting = createCounter(FEEDBACK_DELIVERY_ICON.waiting, Text["Waiting"],
            Text["Not picked up yet: they go out the next time you and the developer are online at the same time."]),
    }
    mainFrame.feedbackCounters.sent:SetPoint("LEFT", myFeedbackButton, "RIGHT", 14, 0)
    mainFrame.feedbackCounters.delivered:SetPoint("LEFT", mainFrame.feedbackCounters.sent, "RIGHT", 6, 0)
    mainFrame.feedbackCounters.waiting:SetPoint("LEFT", mainFrame.feedbackCounters.delivered, "RIGHT", 6, 0)
    mainFrame.feedbackNoticeText = createFontString(feedbackTab, "GameFontHighlightSmall", "RIGHT")
    mainFrame.feedbackNoticeText:SetPoint("LEFT", mainFrame.feedbackCounters.waiting, "RIGHT", 10, 0)
    mainFrame.feedbackNoticeText:SetPoint("RIGHT", feedbackTab, "RIGHT", 0, 0)

    -- the developer's list (shown only on a reader's client)
    local readerFrame = CreateFrame("Frame", nil, feedbackTab)
    readerFrame:SetPoint("TOPLEFT", boxFrame, "BOTTOMLEFT", 0, -26); readerFrame:SetPoint("BOTTOMRIGHT", feedbackTab, "BOTTOMRIGHT", 0, 0)
    mainFrame.feedbackReaderFrame = readerFrame
    feedbackList = createScrollList(readerFrame, createSelectableRow, function(row, feedbackRow)
        row.icon:SetTexture(FEEDBACK_TYPE_ICON[feedbackRow.k] or QUESTION_MARK_ICON)
        row.label:SetText(("|cffaaaaaa%s:|r %s"):format(addon.Utility.Escape(shortName(feedbackRow.owner) or "?"),
            addon.Utility.Escape(feedbackRow.text)))
        local statusIcon = feedbackRow.status and ("|T" .. FEEDBACK_STATUS_ICON[feedbackRow.status] .. ":14|t ") or ""
        local snapshotMark = feedbackRow.log and "|cff66ccff+|r " or ""
        row.rightText:SetText(snapshotMark .. statusIcon .. timeAgo(feedbackRow.t))
        row.label:SetPoint("RIGHT", -90, 0)
        row.selectionHighlight:SetShown(feedbackRow.key == feedbackState.selectedKey)
        row:SetScript("OnClick", function() feedbackState.selectedKey = feedbackRow.key; refreshFeedback() end)
        local function showFeedbackTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText(feedbackTypeLabel(feedbackRow.k) .. " - " .. addon.Utility.Escape(shortName(feedbackRow.owner) or "?"), 1, 0.82, 0)
            GameTooltip:AddLine(addon.Utility.Escape(feedbackRow.text), 1, 1, 1, true)
            if feedbackRow.status then GameTooltip:AddLine(feedbackStatusLabel(feedbackRow.status), 0.6, 0.8, 1) end
            if feedbackRow.log then GameTooltip:AddLine(Text["With diagnostic info."], 0.4, 0.8, 1) end
            GameTooltip:Show()
        end
        row:SetScript("OnEnter", showFeedbackTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.onIconEnter = showFeedbackTooltip
        row.onIconClick = nil
    end)
    feedbackList:SetPoint("TOPLEFT", 0, 0); feedbackList:SetPoint("BOTTOMRIGHT", 0, 76)
    mainFrame.feedbackEmptyText = createFontString(readerFrame, "GameFontDisable", "CENTER")
    mainFrame.feedbackEmptyText:SetPoint("CENTER", feedbackList, "CENTER", 0, 0)
    mainFrame.feedbackEmptyText:SetText(Text["No messages received yet."])
    mainFrame.feedbackDetailText = createFontString(readerFrame, "GameFontHighlightSmall")
    mainFrame.feedbackDetailText:SetPoint("TOPLEFT", feedbackList, "BOTTOMLEFT", 4, -6)
    mainFrame.feedbackDetailText:SetPoint("RIGHT", readerFrame, "RIGHT", -4, 0)
    mainFrame.feedbackDetailText:SetHeight(40); mainFrame.feedbackDetailText:SetJustifyV("TOP"); mainFrame.feedbackDetailText:SetWordWrap(true)

    mainFrame.feedbackWhisperButton = createButton(readerFrame, Text["Whisper"], 90, 24, function()
        local selectedRow = selectedFeedbackRow()
        if selectedRow then whisper(selectedRow.owner) end
    end)
    mainFrame.feedbackWhisperButton:SetPoint("BOTTOMLEFT", 0, 0)
    mainFrame.feedbackSnapshotButton = createButton(readerFrame, Text["Diagnostic info"], 120, 24, function()
        local selectedRow = selectedFeedbackRow()
        if selectedRow and selectedRow.log then UI.ShowExport(selectedRow.text .. "\n\n" .. selectedRow.log) end
    end)
    mainFrame.feedbackSnapshotButton:SetPoint("LEFT", mainFrame.feedbackWhisperButton, "RIGHT", 6, 0)
    mainFrame.feedbackStatusButtons = {}
    local previousButton, gap = mainFrame.feedbackSnapshotButton, 14
    for _, status in ipairs(Feedback.STATUSES) do
        local statusButton = CreateFrame("Button", nil, readerFrame)
        statusButton:SetSize(24, 24)
        statusButton:SetPoint("LEFT", previousButton, "RIGHT", gap, 0)
        local statusTexture = statusButton:CreateTexture(nil, "ARTWORK"); statusTexture:SetAllPoints()
        statusTexture:SetTexture(FEEDBACK_STATUS_ICON[status])
        local hoverTexture = statusButton:CreateTexture(nil, "HIGHLIGHT"); hoverTexture:SetAllPoints(); hoverTexture:SetColorTexture(1, 1, 1, 0.2)
        statusButton:SetScript("OnClick", function()
            local selectedRow = selectedFeedbackRow()
            if not selectedRow then return end
            local newStatus = Feedback.SetStatus(selectedRow.key, status)
            addon.Log.Information("window.feedback", "the status of a feedback message changed", { key = selectedRow.key, status = newStatus })
            refreshFeedback()
        end)
        statusButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(feedbackStatusLabel(status), 1, 1, 1)
            GameTooltip:AddLine(Text["Only you see this status. Click again to clear it."], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        statusButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mainFrame.feedbackStatusButtons[status] = statusButton
        previousButton, gap = statusButton, 6
    end
end

---@return table tabFrame
local function createTabFrame()
    local tabFrame = CreateFrame("Frame", nil, mainFrame)
    tabFrame:SetPoint("TOPLEFT", 12, -58); tabFrame:SetPoint("BOTTOMRIGHT", -12, 12)
    return tabFrame
end

-- The window is resizable from a grip at its bottom right, between RecipeTable.MINIMUM_WIDTH x MINIMUM_HEIGHT and the screen.
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

-- Bottom left: a small button for one maintainer character (Model.IsBuildViewer) whose tooltip lists who sent me addon
-- messages and the build each announced in its HELLO.
local MEMBER_BUILDS_TOOLTIP_ROWS = 25
local function buildMemberBuildsButton()
    local buildsButton = CreateFrame("Button", nil, mainFrame)
    buildsButton:SetSize(14, 14)
    buildsButton:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 4)
    buildsButton:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
    buildsButton:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
    buildsButton:SetHighlightTexture("Interface\\FriendsFrame\\InformationIcon")
    buildsButton:SetScript("OnEnter", function(self)
        local Channel = LibStub("LibGuildSync-1.0").Channel
        local Communication = addon.Communication
        local rows = addon.Model.MemberBuilds(addon.Trace.List("in"), Communication and Channel.PeerVersions(Communication) or {})
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(Text["Member builds"], 1, 1, 1)
        GameTooltip:AddLine(Format(Text["my build: {build}"], { build = Communication and Channel.VersionTag(Communication) or "?" }), 0.7, 0.7, 0.7)
        if #rows == 0 then GameTooltip:AddLine(Text["no messages received yet"], 0.6, 0.6, 0.6) end
        for rowIndex = 1, math.min(#rows, MEMBER_BUILDS_TOOLTIP_ROWS) do
            local row = rows[rowIndex]
            local versionText = row.ver and ("|cff33ff33" .. row.ver .. "|r") or ("|cff999999" .. Text["no build sent (before 1.0.1)"] .. "|r")
            GameTooltip:AddDoubleLine(row.name .. " |cff999999(" .. Format(Text["{n} msg, {ago}"], { n = row.messages, ago = row.t > 0 and timeAgo(row.t) or "?" }) .. ")|r",
                versionText, 1, 1, 1, 1, 1, 1)
        end
        if #rows > MEMBER_BUILDS_TOOLTIP_ROWS then
            GameTooltip:AddLine(Format(Text["+{n} more"], { n = #rows - MEMBER_BUILDS_TOOLTIP_ROWS }), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    buildsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buildsButton:Hide()
    mainFrame.memberBuildsButton = buildsButton
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
    buildMemberBuildsButton()
    mainFrame:SetScript("OnShow", function()
        -- my name is only known after login: decide on every open
        mainFrame.memberBuildsButton:SetShown(addon.Model.IsBuildViewer(me()))
        addon.Events.Fire("WINDOW_OPENED"); UI.Refresh()
    end)

    local titleText = createFontString(mainFrame, "GameFontNormalLarge"); titleText:SetPoint("TOP", 0, -6); titleText:SetText(addon.TITLE)

    mainFrame.tabButtons = {}
    for _, tab in ipairs(tabDefinitions()) do
        local tabKey = tab.key
        mainFrame.tabButtons[tabKey] = createButton(mainFrame, tab.label, tab.width, 22, function() selectTab(tabKey) end)
    end
    layoutTabButtons()   -- again on every refresh: Debug after /ps debug, Feedback when the roster changes
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
    mainFrame.tabs.feedback = createTabFrame()
    buildFeedbackTab(mainFrame.tabs.feedback)
    buildDebugTab()

    addon.Events.On("DATA_CHANGED", UI.Refresh)
    addon.Events.On("TRADESKILL", onTradeSkillWindow)
    addon.Events.On("ITEM_INFO", function()
        itemInfoArrived = true   -- the Recipes table redraws debounced (its OnUpdate)
        if mainFrame:IsShown() then refreshDetail(); refreshOffers() end
    end)
    addon.Events.On("SPELL_INFO", function()   -- an enchant's effect text is readable now
        itemInfoArrived = true   -- the search sees it on the debounced redraw
        if mainFrame:IsShown() then refreshDetail() end
    end)
    selectTab("recipes")
    addon.Log.Debug("window.build", "the main window was built")
end

-- Shows the Debug tab for this session (the live build hides it) and opens the window on it.
function UI.ShowDebugTab()
    debugTabUnlocked = true
    UI.Show()
    if mainFrame then
        layoutTabButtons()
        selectTab("debug")
    end
end

-- /ps debug [count]: the library prints the last log lines; ProfessionShare also shows the Debug tab
local printLogLines = addon.SlashCommands.debug
addon.SlashCommands.debug = function(arguments)
    if printLogLines then printLogLines(arguments) end
    UI.ShowDebugTab()
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

-- Unseen orders as a number on the minimap button and the Orders tab, a letter icon while count > 0.
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
    -- through the LibDataBroker object, so LibDBIcon and data displays (Titan Panel, ...) show the same icon
    local showNews = (noticeState.showIcon and noticeState.count > 0) or noticeState.drops > 0
    minimapButton.dataObject.icon = showNews and NEWS_ICON or DEFAULT_ICON
    minimapButton.badge:SetShown(noticeState.count > 0 and not noticeState.hideNumber)
    minimapButton.badgeText:SetText(noticeState.count > 99 and "99+" or tostring(noticeState.count))
end

-- Whether the minimap button is shown (the player can hide it on the settings page).
---@return boolean
function UI.MinimapButtonShown()
    local iconSettings = addon.db and addon.db.ui and addon.db.ui.minimapIcon
    return not (type(iconSettings) == "table" and iconSettings.hide)
end

-- Shows or hides the minimap button (LibDBIcon keeps the choice in ui.minimapIcon.hide).
---@param shown boolean
function UI.SetMinimapButtonShown(shown)
    if not (addon.db and addon.db.ui) then return end
    addon.db.ui.minimapIcon = type(addon.db.ui.minimapIcon) == "table" and addon.db.ui.minimapIcon or {}
    addon.db.ui.minimapIcon.hide = not shown
    local minimapIcons = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if minimapIcons then
        if shown then pcall(minimapIcons.Show, minimapIcons, addon.FRAME_PREFIX) else pcall(minimapIcons.Hide, minimapIcons, addon.FRAME_PREFIX) end
    end
end

-- The minimap button shows the news icon while a recipe that dropped for a member is one I can learn (0 clears it).
---@param alertCount integer
function UI.SetDropNotice(alertCount)
    noticeState.drops = tonumber(alertCount) or 0
    UI.SetNotice(noticeState.count, noticeState.showIcon, noticeState.hideNumber)
end

-- LibDBIcon's button (Widgets.CreateMinimapButton, shared with GuildGames); its badge shows the count
local function buildMinimapButton()
    addon.db.ui.minimapIcon = addon.db.ui.minimapIcon or {}
    minimapButton = Widgets.CreateMinimapButton({
        name = addon.FRAME_PREFIX,
        label = addon.TITLE,
        icon = DEFAULT_ICON,
        settings = addon.db.ui.minimapIcon,
        defaultPosition = addon.IS_DEVELOPMENT_BUILD and 245 or 215,   -- away from GuildGames' coin (185, dev 165)
        onClick = function() UI.Toggle() end,
        onTooltip = function(tooltip)
            tooltip:SetText(addon.TITLE)
            if noticeState.count > 0 then tooltip:AddLine(Format(Text["{n} new on the order board"], { n = noticeState.count }), 1, 0.82, 0) end
            if noticeState.drops > 0 then
                for _, alert in ipairs(addon.RecipeDrops.alerts) do
                    tooltip:AddLine(Format(Text["{item} dropped for {name}: you can learn it"], { item = addon.Api.ItemLink(alert.itemID)
                        or addon.Api.ItemName(alert.itemID) or tostring(alert.itemID), name = addon.Utility.Escape(addon.Utility.ShortName(alert.from)
                        or alert.from) }), 0.2, 1, 0.6)
                end
            end
            tooltip:AddLine(Text["Click: open window. Drag: move."], 1, 1, 1)
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
