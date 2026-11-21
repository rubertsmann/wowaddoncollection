local addonName, addon = ...

-- Feature 010: tell the player about new orders (and news on their own orders) while the window is closed:
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
    local unseenOrders = Notify.Unseen(addon.Store, addon.orders, me(), settings.notifySeen,
        { scope = setting("scope"), mine = setting("mine") })
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
        alertState.previousKeys = {}   -- nothing is unseen now; what comes later is fresh again
        addon.UI.SetNotice(0, false)
    end
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
    local labels = { profession = Text["Orders for my professions"], known = Text["Orders for recipes I know"], all = Text["All orders"] }
    return labels[scope] or scope
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

local function buildOptionsPanel()
    optionsPanel = CreateFrame("Frame", addon.FRAME_PREFIX .. "OptionsPanel")
    optionsPanel.name = addon.TITLE
    local titleText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", 16, -16); titleText:SetText(addon.TITLE .. " - " .. Text["Notifications"])
    local subtitleText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6); subtitleText:SetWidth(560); subtitleText:SetJustifyH("LEFT")
    subtitleText:SetText(Text["How ProfessionShare tells you about new orders on the board and news on your own orders."])

    local nextTop, checkButtons = -64, {}
    ---@param settingKey string
    ---@param label string
    ---@param tooltipText? string
    local function addCheckButton(settingKey, label, tooltipText)
        local checkButton = CreateFrame("CheckButton", nil, optionsPanel, "UICheckButtonTemplate")
        checkButton:SetSize(26, 26); checkButton:SetPoint("TOPLEFT", 16, nextTop)
        local labelText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labelText:SetPoint("LEFT", checkButton, "RIGHT", 4, 0); labelText:SetText(label)
        checkButton:SetScript("OnClick", function(self)
            Notify.Set(interfaceSettings(), settingKey, self:GetChecked() and true or false)
            Alerts.Update()
        end)
        if tooltipText then
            checkButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label)
                GameTooltip:AddLine(tooltipText, 1, 1, 1, true); GameTooltip:Show()
            end)
            checkButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        checkButtons[settingKey] = checkButton
        nextTop = nextTop - 28
        return checkButton
    end
    addCheckButton("badge", Text["Number of new orders on the minimap button and the Orders tab"])
    addCheckButton("icon", Text["Minimap button shows a letter while something is new"])
    addCheckButton("sound", Text["Play a sound"])
    local soundButton = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    soundButton:SetSize(150, 22); soundButton:SetPoint("LEFT", checkButtons.sound, "RIGHT", 220, 0)
    local soundTestButton = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    soundTestButton:SetSize(70, 22); soundTestButton:SetPoint("LEFT", soundButton, "RIGHT", 4, 0); soundTestButton:SetText(Text["Test"])
    soundTestButton:SetScript("OnClick", playSound)
    addCheckButton("chat", Text["Chat message"])
    addCheckButton("screen", Text["Message in the middle of the screen"])
    addCheckButton("flash", Text["Flash the game icon in the taskbar"], Text["Only visible while the game is in the background."])
    addCheckButton("mine", Text["My orders: tell me when someone claims or finishes them"])

    local scopeLabelText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scopeLabelText:SetPoint("TOPLEFT", 20, nextTop - 10); scopeLabelText:SetText(Text["Tell me about"])
    local scopeButton = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    scopeButton:SetSize(220, 22); scopeButton:SetPoint("LEFT", scopeLabelText, "RIGHT", 10, 0)
    local scopeHintText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scopeHintText:SetPoint("TOPLEFT", scopeLabelText, "BOTTOMLEFT", 0, -10); scopeHintText:SetWidth(560); scopeHintText:SetJustifyH("LEFT")
    scopeHintText:SetText(Text["My professions: also orders for recipes of a profession you have that you do not know yet."])

    local testAllButton = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    testAllButton:SetSize(220, 24); testAllButton:SetPoint("TOPLEFT", scopeHintText, "BOTTOMLEFT", 0, -16)
    testAllButton:SetText(Text["Test all notifications"])
    testAllButton:SetScript("OnClick", function() Alerts.Test() end)
    testAllButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(Text["Test all notifications"])
        GameTooltip:AddLine(Text["Shows every switched-on effect once. The taskbar flash follows after 3 seconds: switch to another window to see it."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    testAllButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- feature 016: Recipes table columns (several can be on) and its sort; the window redraws at once
    local RecipeTable = addon.RecipeTable
    local recipeTitleText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    recipeTitleText:SetPoint("TOPLEFT", testAllButton, "BOTTOMLEFT", -4, -24); recipeTitleText:SetText(Text["Recipe list"])
    local recipeHintText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    recipeHintText:SetPoint("TOPLEFT", recipeTitleText, "BOTTOMLEFT", 0, -6); recipeHintText:SetWidth(560); recipeHintText:SetJustifyH("LEFT")
    recipeHintText:SetText(Text["Columns shown in the Recipes table. Click a column title in the window to sort by it."])
    local columnButtons = {}
    for columnIndex, columnKey in ipairs(RecipeTable.OPTIONAL_KEYS) do
        local columnButton = CreateFrame("CheckButton", nil, optionsPanel, "UICheckButtonTemplate")
        columnButton:SetSize(26, 26)
        -- two columns of checkboxes
        local gridColumn, gridRow = (columnIndex - 1) % 2, math.floor((columnIndex - 1) / 2)
        columnButton:SetPoint("TOPLEFT", recipeHintText, "BOTTOMLEFT", gridColumn * 200, -8 - gridRow * 28)
        local labelText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        labelText:SetPoint("LEFT", columnButton, "RIGHT", 4, 0); labelText:SetText(RecipeTable.ColumnLabel(columnKey))
        columnButton:SetScript("OnClick", function(self)
            RecipeTable.SetColumn(interfaceSettings(), columnKey, self:GetChecked() and true or false)
            addon.UI.Refresh()
        end)
        columnButtons[columnKey] = columnButton
    end
    local sortRowCount = math.ceil(#RecipeTable.OPTIONAL_KEYS / 2)
    local sortLabelText = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sortLabelText:SetPoint("TOPLEFT", recipeHintText, "BOTTOMLEFT", 4, -16 - sortRowCount * 28)
    sortLabelText:SetText(Text["Sort by"])
    local sortKeyButton = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    sortKeyButton:SetSize(160, 22); sortKeyButton:SetPoint("LEFT", sortLabelText, "RIGHT", 10, 0)
    local sortDirectionButton = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
    sortDirectionButton:SetSize(130, 22); sortDirectionButton:SetPoint("LEFT", sortKeyButton, "RIGHT", 6, 0)

    local function refreshPanel()
        for settingKey, checkButton in pairs(checkButtons) do checkButton:SetChecked(setting(settingKey)) end
        scopeButton:SetText(scopeLabel(setting("scope")))
        soundButton:SetText(soundLabel(setting("soundName")))
        soundButton:SetEnabled(setting("sound")); soundTestButton:SetEnabled(setting("sound"))
        for columnKey, columnButton in pairs(columnButtons) do columnButton:SetChecked(RecipeTable.ColumnShown(interfaceSettings(), columnKey)) end
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
    scopeButton:SetScript("OnClick", function()
        Notify.Set(interfaceSettings(), "scope", nextChoice(Notify.SCOPES, setting("scope"))); refreshPanel(); Alerts.Update()
    end)
    soundButton:SetScript("OnClick", function()
        Notify.Set(interfaceSettings(), "soundName", nextChoice(Notify.SOUNDS, setting("soundName"), 1)); refreshPanel(); playSound()
    end)
    for _, checkButton in pairs(checkButtons) do checkButton:HookScript("OnClick", refreshPanel) end
    optionsPanel:SetScript("OnShow", refreshPanel)
    optionsPanel.refresh = refreshPanel

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
