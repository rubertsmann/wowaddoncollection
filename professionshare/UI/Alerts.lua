local addonName, addon = ...

-- Tells the player about new orders (and news on their own orders) while the window is closed:
-- number on the minimap button and the Orders tab, letter icon, sound, chat line, screen message, taskbar flash.
-- What counts as new is decided in Core/View/Notify.lua (pure); this file only shows it and holds the options panel.
---@class AlertsModule
local Alerts = {}
addon.Alerts = Alerts

local Text, Format = addon.Text, addon.Locale.Format
local Notify = addon.Notify

---@class AlertsState
---@field started boolean
---@field previousKeys table<string, boolean>|nil keys of the last unseen list (nil until the first update of the session)
---@field lastLoudAlertAt number GetTime() of the last sound / screen message / flash
local alertState = { started = false, previousKeys = nil, lastLoudAlertAt = -math.huge }

---@return string|nil
local function me() return addon.Utility.Me() end
---@return table|nil the SavedVariables ui table
local function interfaceSettings() return addon.db and addon.db.ui end
---@param settingKey string
---@return any
local function setting(settingKey) return Notify.Get(interfaceSettings(), settingKey) end

---@return boolean
local function ordersTabVisible()
    return addon.UI.OrdersVisible()
end

-- peer-supplied recipe names never reach chat as markup (Model.ChatText strips | [ ] and line breaks)
---@param order Order
---@return string
local function plainRecipeName(order)
    return addon.Model.ChatText(nil, addon.Model.OrderRecipeName(addon.Store, order))
end

---@param unseenOrder UnseenOrder
---@return string
local function describe(unseenOrder)
    local order = unseenOrder.order
    if unseenOrder.kind == "new" then
        return Format(Text["New order: {qty}x {name} from {who}"],
            { qty = order.qty, name = plainRecipeName(order), who = addon.Utility.ShortName(order.requester) })
    elseif unseenOrder.kind == "claimed" then
        local crafterNames = {}
        for _, crafter in ipairs(addon.orders:Claimers(order)) do
            if crafter ~= me() then crafterNames[#crafterNames + 1] = addon.Utility.ShortName(crafter) end
        end
        return Format(Text["{who} will craft your order {name}"], { who = table.concat(crafterNames, ", "), name = plainRecipeName(order) })
    elseif unseenOrder.kind == "chat" then
        local message = unseenOrder.message
        return Format(Text["{who} about {name}: {text}"], { who = addon.Utility.ShortName(message.b), name = plainRecipeName(order),
            text = addon.Utility.ChatSafe(message.x) })
    end
    return Format(Text["{who} finished your order {name}"],
        { who = addon.Utility.ShortName(order.closedBy or "?"), name = plainRecipeName(order) })
end

local function playSound()
    local soundName = setting("soundName")
    local soundKitID
    for _, sound in ipairs(Notify.SOUNDS) do
        if sound[1] == soundName then soundKitID = (SOUNDKIT and SOUNDKIT[soundName]) or sound[2] end
    end
    if soundKitID and PlaySound then
        local ok, errorMessage = pcall(PlaySound, soundKitID, "Master")
        if not ok then addon.Log.Warning("alerts.sound", "playing the notification sound failed", { sound = soundName, error = tostring(errorMessage) }) end
    end
end
Alerts.PlaySound = playSound

---@param message string
local function screenMessage(message)
    local shown = false
    if RaidNotice_AddMessage and RaidWarningFrame then
        shown = pcall(RaidNotice_AddMessage, RaidWarningFrame, message, { r = 1, g = 0.82, b = 0 })
    end
    if not shown and UIErrorsFrame then shown = pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, message, 1, 0.82, 0) end
    if not shown then addon.Log.Warning("alerts.screen", "no frame could show the screen message") end
end

local function flashTaskbarIcon()
    if not FlashClientIcon then return end
    local ok, errorMessage = pcall(FlashClientIcon)
    if not ok then addon.Log.Warning("alerts.flash", "flashing the taskbar icon failed", { error = tostring(errorMessage) }) end
end

---@param freshOrders UnseenOrder[]
---@param now number GetTime()
local function alert(freshOrders, now)
    if setting("chat") then
        for index in ipairs(freshOrders) do
            if index > 3 then
                addon.Print(Format(Text["... and {n} more on the order board"], { n = #freshOrders - 3 }))
                break
            end
            addon.Print(describe(freshOrders[index]))
        end
    end
    -- a login sync can bring many orders at once: one ping
    if now - alertState.lastLoudAlertAt < Notify.THROTTLE_SECONDS then return end
    alertState.lastLoudAlertAt = now
    if setting("sound") then playSound() end
    if setting("screen") then
        screenMessage(#freshOrders == 1 and describe(freshOrders[1]) or Format(Text["{n} new on the order board"], { n = #freshOrders }))
    end
    if setting("flash") then flashTaskbarIcon() end
end

-- Options "Test all": every switched-on effect once with a sample text, the badge/letter for 8 s. The taskbar flash
-- comes after 3 s (it is only visible while the game is in the background, so there is time to switch windows).
---@type integer increases with every test, so an older test's timer does not reset a newer one
local testGeneration = 0
function Alerts.Test()
    local sampleText = Text["ProfessionShare test notification"]
    if setting("chat") then addon.Print(sampleText) end
    if setting("sound") then playSound() end
    if setting("screen") then screenMessage(sampleText) end
    if setting("badge") or setting("icon") then
        testGeneration = testGeneration + 1
        local thisGeneration = testGeneration
        addon.UI.SetNotice(1, setting("icon"), not setting("badge"))
        C_Timer.After(8, function()
            if thisGeneration ~= testGeneration then return end
            addon.UI.SetNotice(0, false)
            Alerts.Update()   -- back to the real state
        end)
    end
    if setting("flash") then C_Timer.After(3, flashTaskbarIcon) end
end

-- Recompute the unseen list; alert about items that are new since the last call (never on the first call of a session:
-- what was unseen at logout was already announced then, the badge still shows it).
function Alerts.Update()
    local settings = interfaceSettings()
    if not alertState.started or not settings or not addon.orders then return end
    if settings.notifySeen == nil then settings.notifySeen = Notify.MarkSeen(addon.orders, nil) end   -- first run: the existing board is not news
    if ordersTabVisible() then settings.notifySeen = Notify.MarkSeen(addon.orders, settings.notifySeen) end
    if settings.chatSeen == nil then settings.chatSeen = Notify.MarkAllChatSeen(addon.orders, nil) end   -- older chat is not news
    local unseenOrders = Notify.Unseen(addon.Store, addon.orders, me(), settings.notifySeen,
        { scope = setting("scope"), mine = setting("mine") })
    for _, unseenChat in ipairs(Notify.UnseenChat(addon.orders, me(), settings.chatSeen)) do unseenOrders[#unseenOrders + 1] = unseenChat end
    local freshOrders, currentKeys = Notify.Fresh(alertState.previousKeys, unseenOrders)
    local primed = alertState.previousKeys ~= nil
    alertState.previousKeys = currentKeys
    addon.UI.SetNotice(#unseenOrders, setting("icon"), not setting("badge"))
    if primed and #freshOrders > 0 then
        addon.Log.Information("alerts.update", "new items on the order board", { fresh = #freshOrders, unseen = #unseenOrders })
        alert(freshOrders, GetTime and GetTime() or 0)
    end
end

-- The player looks at the Orders tab.
function Alerts.Seen()
    local settings = interfaceSettings()
    if not settings or not addon.orders then return end
    settings.notifySeen = Notify.MarkSeen(addon.orders, settings.notifySeen)
    if alertState.started then
        -- only unread chat is left; it is read in the order window (Alerts.ChatSeen)
        local unseenChats = Notify.UnseenChat(addon.orders, me(), settings.chatSeen)
        local remainingKeys = {}
        for _, unseenChat in ipairs(unseenChats) do remainingKeys[unseenChat.id .. "|" .. unseenChat.key] = true end
        alertState.previousKeys = remainingKeys   -- what comes later is fresh again
        addon.UI.SetNotice(#unseenChats, #unseenChats > 0 and setting("icon"), not setting("badge"))
    end
end

-- The player read the chat of `order` (the order window shows it).
---@param order Order
function Alerts.ChatSeen(order)
    local settings = interfaceSettings()
    if not settings or not order then return end
    settings.chatSeen = Notify.MarkChatSeen(Notify.PruneChatSeen(addon.orders, settings.chatSeen), order)
    Alerts.Update()
end

function Alerts.Start()
    if alertState.started then return end
    alertState.started = true
    Alerts.Update()
end

addon.Events.On("DATA_CHANGED", function(kind)
    if kind == "orders" or kind == "chars" or kind == nil then Alerts.Update() end
end)

------------------------------------------------------------------ options panel

---@type table|nil
local optionsPanel
---@type table|nil the game's Settings category (modern settings API)
local settingsCategory

---@param scope NotifyScope
---@return string
local function scopeLabel(scope)
    local labels = { profession = Text["Orders for my professions"], known = Text["Orders for recipes I know"],
        level = Text["Orders I have the profession level for"], all = Text["All orders"] }
    return labels[scope] or scope
end

-- what the selected scope means (shown under the dropdown)
---@param scope NotifyScope
---@return string
local function scopeHint(scope)
    if scope == "known" then return Text["Only orders for recipes you know: you can craft them now."] end
    if scope == "level" then
        return Text["Also orders for recipes you do not know yet when your profession rank is high enough: the rank of the guild member who learned the recipe at the lowest rank counts."]
    end
    if scope == "profession" then return Text["My professions: also orders for recipes of a profession you have that you do not know yet."] end
    return Text["Every open order of the guild."]
end

---@param soundName string
---@return string
local function soundLabel(soundName)
    local labels = { IG_PLAYER_INVITE = Text["Invite"], MAP_PING = Text["Map ping"], AUCTION_WINDOW_OPEN = Text["Auction house"],
        READY_CHECK = Text["Ready check"] }
    return labels[soundName] or soundName
end

-- the entry after `currentValue` in `choices` (wrapping); `field` picks the value out of table entries
---@param choices any[]
---@param currentValue any
---@param field? any
---@return any
local function nextChoice(choices, currentValue, field)
    for index, choice in ipairs(choices) do
        local value = field and choice[field] or choice
        if value == currentValue then
            local following = choices[index % #choices + 1]
            return field and following[field] or following
        end
    end
    return field and choices[1][field] or choices[1]
end

-- One page with every switch of the addon, grouped by feature (General, Order notifications, Recipe drops, Recipe list).
-- The sections are taller than the game's settings area, so the page scrolls. Every control reads its value again when
-- the page is shown and after any click (refreshPanel).
local function buildOptionsPanel()
    optionsPanel = CreateFrame("Frame", addon.FRAME_PREFIX .. "OptionsPanel")
    optionsPanel.name = addon.TITLE
    local scrollFrame = CreateFrame("ScrollFrame", addon.FRAME_PREFIX .. "OptionsScroll", optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -6); scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(600, 1000)
    scrollFrame:SetScrollChild(content)

    local titleText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 16, -10); titleText:SetText(addon.TITLE .. " - " .. Text["Settings"])
    local subtitleText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6); subtitleText:SetWidth(560); subtitleText:SetJustifyH("LEFT")
    subtitleText:SetText(Text["Every switch of ProfessionShare, grouped by feature."])

    local nextTop = -50                 -- the layout cursor: top edge of the next control in the content frame
    local refreshers = {}               -- functions that set every control from the stored settings
    local refreshPanel = function() for _, refresh in ipairs(refreshers) do refresh() end end

    ---@param anchoredFrame table
    ---@param label string
    ---@param tooltipText string
    local function addTooltip(anchoredFrame, label, tooltipText)
        anchoredFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltipText, 1, 1, 1, true); GameTooltip:Show()
        end)
        anchoredFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- a section title with a line of explanation under it
    ---@param title string
    ---@param hint string|nil
    local function addSection(title, hint)
        nextTop = nextTop - 18
        local sectionTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        sectionTitle:SetPoint("TOPLEFT", 16, nextTop); sectionTitle:SetText(title)
        local divider = content:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", 16, nextTop - 20); divider:SetSize(560, 1); divider:SetColorTexture(1, 0.82, 0, 0.35)
        nextTop = nextTop - 26
        if hint then
            local hintText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            hintText:SetPoint("TOPLEFT", 18, nextTop); hintText:SetWidth(560); hintText:SetJustifyH("LEFT"); hintText:SetText(hint)
            nextTop = nextTop - math.max(14, math.ceil(tonumber(hintText:GetStringHeight()) or 14)) - 6
        end
    end

    -- a checkbox bound to get/set
    ---@param label string
    ---@param get fun(): boolean
    ---@param set fun(value: boolean)
    ---@param tooltipText? string
    ---@return table checkButton
    local function addCheck(label, get, set, tooltipText)
        local checkButton = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        checkButton:SetSize(26, 26); checkButton:SetPoint("TOPLEFT", 16, nextTop)
        local labelText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labelText:SetPoint("LEFT", checkButton, "RIGHT", 4, 0); labelText:SetText(label)
        checkButton:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); refreshPanel() end)
        if tooltipText then addTooltip(checkButton, label, tooltipText) end
        refreshers[#refreshers + 1] = function() checkButton:SetChecked(get()) end
        nextTop = nextTop - 28
        return checkButton
    end

    ---@param width number
    ---@param height number
    ---@return table button
    local function newButton(width, height)
        local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        button:SetSize(width, height)
        return button
    end

    ------------------------------------------------ General
    addSection(Text["General"])
    addCheck(Text["Show the minimap button"], function() return addon.UI.MinimapButtonShown() end,
        function(shown) addon.UI.SetMinimapButtonShown(shown) end, Text["Hidden: open the window with the slash command."])

    ------------------------------------------------ Order notifications
    addSection(Text["Order notifications"], Text["How ProfessionShare tells you about new orders on the board and news on your own orders."])
    ---@param settingKey string
    ---@param label string
    ---@param tooltipText? string
    local function addNotifyCheck(settingKey, label, tooltipText)
        return addCheck(label, function() return setting(settingKey) end, function(value)
            Notify.Set(interfaceSettings(), settingKey, value)
            Alerts.Update()
        end, tooltipText)
    end
    addNotifyCheck("badge", Text["Number of new orders on the minimap button and the Orders tab"])
    addNotifyCheck("icon", Text["Minimap button shows a letter while something is new"])
    local soundCheck = addNotifyCheck("sound", Text["Play a sound"])
    local soundButton = newButton(150, 22); soundButton:SetPoint("LEFT", soundCheck, "RIGHT", 220, 0)
    local soundTestButton = newButton(70, 22); soundTestButton:SetPoint("LEFT", soundButton, "RIGHT", 4, 0); soundTestButton:SetText(Text["Test"])
    soundTestButton:SetScript("OnClick", playSound)
    soundButton:SetScript("OnClick", function()
        Notify.Set(interfaceSettings(), "soundName", nextChoice(Notify.SOUNDS, setting("soundName"), 1)); refreshPanel(); playSound()
    end)
    refreshers[#refreshers + 1] = function()
        soundButton:SetText(soundLabel(setting("soundName")))
        soundButton:SetEnabled(setting("sound")); soundTestButton:SetEnabled(setting("sound"))
    end
    addNotifyCheck("chat", Text["Chat message"])
    addNotifyCheck("screen", Text["Message in the middle of the screen"])
    addNotifyCheck("flash", Text["Flash the game icon in the taskbar"], Text["Only visible while the game is in the background."])
    addNotifyCheck("mine", Text["My orders: tell me when someone claims or finishes them"])

    local scopeLabelText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scopeLabelText:SetPoint("TOPLEFT", 20, nextTop - 6); scopeLabelText:SetText(Text["Tell me about"])
    local function chooseScope(scope)
        Notify.Set(interfaceSettings(), "scope", scope); refreshPanel(); Alerts.Update()
    end
    -- a dropdown listing every scope; the old cycling button where the client has no menu dropdowns
    local dropdownOk, scopeDropdown = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    if dropdownOk and type(scopeDropdown) == "table" and scopeDropdown.SetupMenu then
        scopeDropdown:SetWidth(280)
        scopeDropdown:SetupMenu(function(_, rootMenu)
            local function isSelectedScope(scope) return setting("scope") == scope end
            for _, scope in ipairs(Notify.SCOPES) do rootMenu:CreateRadio(scopeLabel(scope), isSelectedScope, chooseScope, scope) end
        end)
        refreshers[#refreshers + 1] = function()
            if scopeDropdown.OverrideText then scopeDropdown:OverrideText(scopeLabel(setting("scope")))
            elseif scopeDropdown.GenerateMenu then scopeDropdown:GenerateMenu() end
        end
    else
        scopeDropdown = newButton(280, 22)
        scopeDropdown:SetScript("OnClick", function() chooseScope(nextChoice(Notify.SCOPES, setting("scope"))) end)
        refreshers[#refreshers + 1] = function() scopeDropdown:SetText(scopeLabel(setting("scope"))) end
    end
    scopeDropdown:SetPoint("LEFT", scopeLabelText, "RIGHT", 10, 0)
    nextTop = nextTop - 30
    local scopeHintText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scopeHintText:SetPoint("TOPLEFT", 20, nextTop); scopeHintText:SetWidth(560); scopeHintText:SetJustifyH("LEFT")
    refreshers[#refreshers + 1] = function() scopeHintText:SetText(scopeHint(setting("scope"))) end
    nextTop = nextTop - 34
    local testAllButton = newButton(220, 24); testAllButton:SetPoint("TOPLEFT", 20, nextTop)
    testAllButton:SetText(Text["Test all notifications"])
    testAllButton:SetScript("OnClick", function() Alerts.Test() end)
    addTooltip(testAllButton, Text["Test all notifications"],
        Text["Shows every switched-on effect once. The taskbar flash follows after 3 seconds: switch to another window to see it."])
    nextTop = nextTop - 32

    ------------------------------------------------ Recipe drops
    addSection(Text["Recipe drops"], Text["When a tradeable recipe drops into your bags, guild members who can learn it are told. Hover the recipe to see who answered."])
    local RecipeDrops = addon.RecipeDrops
    ---@param settingKey string
    ---@param label string
    ---@param tooltipText? string
    local function addDropCheck(settingKey, label, tooltipText)
        return addCheck(label, function() return RecipeDrops.Get(interfaceSettings(), settingKey) end,
            function(value) RecipeDrops.Set(interfaceSettings(), settingKey, value) end, tooltipText)
    end
    addDropCheck("share", Text["Share my recipe drops and answer those of others"],
        Text["Off: your drops are not announced and you do not answer when a member's recipe drops."])
    addDropCheck("chat", Text["Chat message for a recipe drop"])
    addDropCheck("icon", Text["Minimap button shows a letter when a recipe I can learn drops"])
    local bagScanButton = newButton(260, 24); bagScanButton:SetPoint("TOPLEFT", 20, nextTop - 4)
    bagScanButton:SetText(Text["Announce the recipes in my bags now"])
    bagScanButton:SetScript("OnClick", function() addon.Drops.AnnounceBags() end)
    addTooltip(bagScanButton, Text["Announce the recipes in my bags now"],
        Text["Treats every tradeable recipe in your bags as if it had just dropped: guild members who can learn one are told, and its tooltip shows who answered. For testing; members get the alert as for a real drop."])
    refreshers[#refreshers + 1] = function() bagScanButton:SetEnabled(RecipeDrops.Get(interfaceSettings(), "share")) end
    nextTop = nextTop - 34

    ------------------------------------------------ Auctionator (only when it is loaded)
    if addon.AuctionatorBridge and addon.AuctionatorBridge.IsAvailable() then
        addSection(Text["Auctionator"], Text["The Orders tab can put the reagents of ticked orders on an Auctionator shopping list."])
        addCheck(Text["Search the buy list when I open the auction house"],
            function() local settings = interfaceSettings(); return not (settings and settings.buyListSearchOnOpen == false) end,
            function(value) local settings = interfaceSettings(); if settings then settings.buyListSearchOnOpen = (not value) and false or nil end end,
            Text["Off: the list only waits in Auctionator's Shopping tab. At the auction house the search always starts at once."])
        nextTop = nextTop - 6
    end

    ------------------------------------------------ Recipe list
    addSection(Text["Recipe list"], Text["Columns shown in the Recipes table. Click a column title in the window to sort by it."])
    local RecipeTable = addon.RecipeTable
    local gridTop = nextTop
    for columnIndex, columnKey in ipairs(RecipeTable.OPTIONAL_KEYS) do
        local columnButton = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        columnButton:SetSize(26, 26)
        -- two columns of checkboxes
        local gridColumn, gridRow = (columnIndex - 1) % 2, math.floor((columnIndex - 1) / 2)
        columnButton:SetPoint("TOPLEFT", 16 + gridColumn * 200, gridTop - gridRow * 28)
        local labelText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labelText:SetPoint("LEFT", columnButton, "RIGHT", 4, 0); labelText:SetText(RecipeTable.ColumnLabel(columnKey))
        columnButton:SetScript("OnClick", function(self)
            RecipeTable.SetColumn(interfaceSettings(), columnKey, self:GetChecked() and true or false)
            addon.UI.Refresh()
        end)
        refreshers[#refreshers + 1] = function() columnButton:SetChecked(RecipeTable.ColumnShown(interfaceSettings(), columnKey)) end
    end
    nextTop = gridTop - math.ceil(#RecipeTable.OPTIONAL_KEYS / 2) * 28 - 6
    local sortLabelText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sortLabelText:SetPoint("TOPLEFT", 20, nextTop - 4)
    sortLabelText:SetText(Text["Sort by"])
    local sortKeyButton = newButton(160, 22); sortKeyButton:SetPoint("LEFT", sortLabelText, "RIGHT", 10, 0)
    local sortDirectionButton = newButton(130, 22); sortDirectionButton:SetPoint("LEFT", sortKeyButton, "RIGHT", 6, 0)
    refreshers[#refreshers + 1] = function()
        local recipeSort = RecipeTable.GetSort(interfaceSettings())
        sortKeyButton:SetText(RecipeTable.ColumnLabel(recipeSort.key))
        sortDirectionButton:SetText(recipeSort.descending and Text["Descending"] or Text["Ascending"])
    end
    sortKeyButton:SetScript("OnClick", function()
        local recipeSort = RecipeTable.GetSort(interfaceSettings())
        local nextKey = nextChoice(RecipeTable.SortKeys(), recipeSort.key)
        RecipeTable.SetSort(interfaceSettings(), nextKey, RecipeTable.Column(nextKey).numeric)   -- numbers highest first, text A-Z
        refreshPanel(); addon.UI.Refresh()
    end)
    sortDirectionButton:SetScript("OnClick", function()
        local recipeSort = RecipeTable.GetSort(interfaceSettings())
        RecipeTable.SetSort(interfaceSettings(), recipeSort.key, not recipeSort.descending)
        refreshPanel(); addon.UI.Refresh()
    end)
    nextTop = nextTop - 40

    content:SetHeight(-nextTop)
    optionsPanel:SetScript("OnShow", refreshPanel)
    optionsPanel.refresh = refreshPanel
    optionsPanel.refreshers = refreshers

    -- Settings panel of the game (modern API first, then the old interface options), else a plain window.
    local registered = false
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local errorMessage
        registered, errorMessage = pcall(function()
            settingsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, optionsPanel.name)
            Settings.RegisterAddOnCategory(settingsCategory)
        end)
        if not registered then
            settingsCategory = nil
            addon.Log.Warning("alerts.options", "the modern settings API refused the options panel", { error = tostring(errorMessage) })
        end
    end
    if not registered and InterfaceOptions_AddCategory then registered = pcall(InterfaceOptions_AddCategory, optionsPanel) end
    optionsPanel.registered = registered
    if not registered then
        addon.Log.Information("alerts.options", "the options panel opens as a plain window (no settings API took it)")
        optionsPanel:SetParent(UIParent); optionsPanel:SetSize(620, 600); optionsPanel:SetPoint("CENTER"); optionsPanel:SetFrameStrata("DIALOG")
        local background = optionsPanel:CreateTexture(nil, "BACKGROUND"); background:SetAllPoints(); background:SetColorTexture(0, 0, 0, 0.9)
        local closeButton = CreateFrame("Button", nil, optionsPanel, "UIPanelCloseButton"); closeButton:SetPoint("TOPRIGHT", -2, -2)
        optionsPanel:EnableMouse(true); optionsPanel:SetMovable(true); optionsPanel:RegisterForDrag("LeftButton")
        optionsPanel:SetScript("OnDragStart", optionsPanel.StartMoving); optionsPanel:SetScript("OnDragStop", optionsPanel.StopMovingOrSizing)
        table.insert(UISpecialFrames, optionsPanel:GetName())
        optionsPanel:Hide()
    end
end

function Alerts.OpenOptions()
    if not optionsPanel then
        local ok = addon.Log.Protected("alerts.options", "building the options panel failed", buildOptionsPanel)
        if not ok then return end
    end
    if settingsCategory and Settings and Settings.OpenToCategory then
        local categoryID = settingsCategory.GetID and settingsCategory:GetID() or settingsCategory.ID
        if pcall(Settings.OpenToCategory, categoryID) then return end
    end
    if optionsPanel.registered and InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsPanel)
        pcall(InterfaceOptionsFrame_OpenToCategory, optionsPanel)   -- the old frame needs two calls the first time
        return
    end
    optionsPanel:SetShown(not optionsPanel:IsShown())
end

addon.SlashCommands.options = function() Alerts.OpenOptions() end

-- Register the panel at login, so it is in the game's AddOns options list without opening it from here first.
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    if not optionsPanel then
        addon.Log.Protected("alerts.options", "building the options panel failed", buildOptionsPanel)
    end
end)
