local addonName, addon = ...

-- AZEcaught options (user 2026-11-20): the rope icon on nameplates can be turned off, moved and resized. The page is
-- registered in the game's options (Options > AddOns > <title> AZEcaught); /gg caught icon does the same from chat.
-- Settings live in db.caught.icon (AzeCaught.IconSettings, clamped); every change is journaled and applied at once.
---@class AzeCaughtOptionsModule
local Options = {}
addon.AzeCaughtOptions = Options

local AzeCaught = addon.AzeCaught
local Text, Format = addon.Text, addon.Locale.Format

local STEP = { x = 2, y = 2, size = 2 }
local widgets = {}
Options.widgets = widgets

local function apply()
    addon.Catcher.RefreshIcons()
    Options.Refresh()
end

-- toggles or steps one setting (the buttons and /gg caught icon use it)
---@param key "shown"|"x"|"y"|"size"
---@param direction? integer -1 or 1 (numbers)
function Options.Change(key, direction)
    local settings = AzeCaught.IconSettings()
    if key == "shown" then AzeCaught.SetIconSetting("shown", not settings.shown)
    else AzeCaught.SetIconSetting(key, settings[key] + (direction or 1) * STEP[key]) end
    apply()
end

function Options.Reset()
    AzeCaught.ResetIconSettings()
    apply()
end

function Options.Refresh()
    if not widgets.frame or not addon.db then return end
    local settings = AzeCaught.IconSettings()
    widgets.shownButton:SetLabel(settings.shown and Text["Rope icon: on"] or Text["Rope icon: off"])
    widgets.values.x:SetText(tostring(settings.x))
    widgets.values.y:SetText(tostring(settings.y))
    widgets.values.size:SetText(tostring(settings.size))
    widgets.preview:SetSize(settings.size, settings.size)
    widgets.preview:SetAlpha(settings.shown and 1 or 0.3)
end

---@param parent table
---@param y number
---@param key "x"|"y"|"size"
---@param label string
local function stepper(parent, y, key, label)
    local Widgets = addon.UI.Widgets
    local caption = Widgets.CreateFontString(parent, "GameFontHighlight", "LEFT")
    caption:SetPoint("TOPLEFT", 20, y); caption:SetWidth(200); caption:SetText(label)
    local minus = Widgets.CreateButton(parent, "-", 26, 22, function() Options.Change(key, -1) end)
    minus:SetPoint("TOPLEFT", 230, y + 3)
    local value = Widgets.CreateFontString(parent, "GameFontHighlight", "CENTER")
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0); value:SetWidth(44)
    local plus = Widgets.CreateButton(parent, "+", 26, 22, function() Options.Change(key, 1) end)
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    widgets.values[key] = value
end

function Options.Build()
    if widgets.frame then return widgets.frame end
    local Widgets = addon.UI.Widgets
    local frame = CreateFrame("Frame")
    frame.name = addon.TITLE .. " AZEcaught"
    widgets.frame, widgets.values = frame, {}
    local title = Widgets.CreateFontString(frame, "GameFontNormalLarge", "LEFT")
    title:SetPoint("TOPLEFT", 16, -16); title:SetText(frame.name)
    local note = Widgets.CreateFontString(frame, "GameFontHighlightSmall", "LEFT")
    note:SetPoint("TOPLEFT", 16, -40); note:SetWidth(560)
    note:SetText(Text["The rope icon appears above a weak enemy's nameplate. The key binding and /gg catch work even when it is off."])
    widgets.shownButton = Widgets.CreateButton(frame, "", 200, 24, function() Options.Change("shown") end)
    widgets.shownButton:SetPoint("TOPLEFT", 20, -72)
    stepper(frame, -112, "x", Text["Move left / right"])
    stepper(frame, -142, "y", Text["Move down / up"])
    stepper(frame, -172, "size", Text["Size"])
    local reset = Widgets.CreateButton(frame, Text["Reset"], 120, 22, function() Options.Reset() end)
    reset:SetPoint("TOPLEFT", 20, -208)
    -- a preview of the round icon
    local preview = frame:CreateTexture(nil, "ARTWORK")
    preview:SetPoint("TOPLEFT", 400, -120)
    if preview:SetTexture(addon.Catcher.ROPE_ICON) == false then preview:SetColorTexture(1, 0.82, 0.2, 1) end
    pcall(function()
        local mask = frame:CreateMaskTexture()
        mask:SetTexture(addon.Catcher.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(preview)
        preview:AddMaskTexture(mask)
    end)
    widgets.preview = preview
    frame:SetScript("OnShow", function() Options.Refresh() end)
    -- register in the game's options: the Settings API (current clients) or the older interface options
    local registered, problem = pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local category = Settings.RegisterCanvasLayoutCategory(frame, frame.name)
            Settings.RegisterAddOnCategory(category)
            Options.category = category
            return
        end
        if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(frame) end
    end)
    AzeCaught.Journal(registered and "DEBUG" or "WARNING", "options", registered and "the options page was registered"
        or "the options page could not be registered", { error = problem and tostring(problem) or nil })
    return frame
end

-- /gg caught icon [on|off|x <n>|y <n>|size <n>|reset]
function Options.Command(arguments)
    local word, number = (arguments or ""):match("^%s*(%S*)%s*(%-?%d*)")
    word = (word or ""):lower()
    if word == "on" or word == "off" then AzeCaught.SetIconSetting("shown", word == "on")
    elseif (word == "x" or word == "y" or word == "size") and number ~= "" then AzeCaught.SetIconSetting(word, tonumber(number))
    elseif word == "reset" then AzeCaught.ResetIconSettings() end
    apply()
    local settings = AzeCaught.IconSettings()
    addon.Print(Format(Text["Rope icon: {shown}, x {x}, y {y}, size {size}. Options > AddOns > {title}."], { shown = settings.shown
        and Text["on"] or Text["off"], x = settings.x, y = settings.y, size = settings.size, title = widgets.frame and widgets.frame.name or "" }))
end

addon.Log.Protected("caught.options", "building the AZEcaught options failed", Options.Build)
