local addonName, addon = ...

-- AZEcaught options: the rope icon on nameplates can be turned off, moved and resized. The page is
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

-- toggles or steps one setting (the page's buttons; /gg caught icon sets values directly in Options.Command)
---@param key "shown"|"atTarget"|"x"|"y"|"size"
---@param direction? integer -1 or 1 (numbers)
function Options.Change(key, direction)
    local settings = AzeCaught.IconSettings()
    if key == "shown" or key == "atTarget" then AzeCaught.SetIconSetting(key, not settings[key])
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
    widgets.atTargetButton:SetLabel(settings.atTarget and Text["At the target frame: on"] or Text["At the target frame: off"])
    widgets.values.x:SetText(tostring(settings.x))
    widgets.values.y:SetText(tostring(settings.y))
    widgets.values.size:SetText(tostring(settings.size))
    widgets.preview:SetSize(settings.size, settings.size)
    widgets.preview:SetAlpha(settings.shown and 1 or 0.3)
    Options.RefreshPetView()
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

------------------------------------------------------------------ the minimal pet view

---@param percent number
---@return string
local function percentText(percent) return ("%d%%"):format(math.floor(percent + 0.5)) end

-- A slider from `minimum` to `maximum` percent (OptionsSliderTemplate; clients without it get - and + buttons).
---@param parent table
---@param y number
---@param key "opacity"|"scale"
---@param label string
---@param minimum integer
---@param maximum integer
---@param step integer
local function percentSlider(parent, y, key, label, minimum, maximum, step)
    local Widgets = addon.UI.Widgets
    local caption = Widgets.CreateFontString(parent, "GameFontHighlight", "LEFT")
    caption:SetPoint("TOPLEFT", 20, y); caption:SetWidth(200); caption:SetText(label)
    local value = Widgets.CreateFontString(parent, "GameFontHighlight", "LEFT")
    value:SetPoint("TOPLEFT", 420, y); value:SetWidth(60)
    widgets.petValues[key] = value
    local function set(percent)
        percent = math.max(minimum, math.min(maximum, math.floor(percent / step + 0.5) * step))
        addon.PetView.Set(key, percent / 100)
        Options.Refresh()
    end
    local ok, slider = pcall(CreateFrame, "Slider", nil, parent, "OptionsSliderTemplate")
    if ok and slider then
        slider:SetPoint("TOPLEFT", 230, y + 2); slider:SetWidth(170)
        slider:SetMinMaxValues(minimum, maximum)
        slider:SetValueStep(step)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        for _, part in ipairs({ "Low", "High", "Text" }) do if slider[part] then slider[part]:SetText("") end end
        slider:SetScript("OnValueChanged", function(self, newValue, byUser)
            if widgets.refreshing then return end
            if byUser == false then return end
            set(newValue)
        end)
        widgets.petSliders[key] = slider
        return
    end
    local minus = Widgets.CreateButton(parent, "-", 26, 22, function()
        set(addon.PetView.Settings()[key] * 100 - step)
    end)
    minus:SetPoint("TOPLEFT", 230, y + 3)
    local plus = Widgets.CreateButton(parent, "+", 26, 22, function()
        set(addon.PetView.Settings()[key] * 100 + step)
    end)
    plus:SetPoint("TOPLEFT", 262, y + 3)
end

-- The pet view section: start mode, opacity, size, lock, hide in combat (db.ui.petView through PetView.Set).
---@param frame table
---@param y number
function Options.BuildPetView(frame, y)
    local Widgets = addon.UI.Widgets
    widgets.petValues, widgets.petSliders = {}, {}
    local title = Widgets.CreateFontString(frame, "GameFontNormalLarge", "LEFT")
    title:SetPoint("TOPLEFT", 16, y); title:SetText(Text["Minimal view"])
    local note = Widgets.CreateFontString(frame, "GameFontHighlightSmall", "LEFT")
    note:SetPoint("TOPLEFT", 16, y - 22); note:SetWidth(560)
    note:SetText(Text["Only your companion: round care buttons fill with each need. The icon in the top-left corner switches to the full window and back."])
    widgets.startButton = Widgets.CreateButton(frame, "", 240, 24, function()
        addon.PetView.Set("startMode", addon.PetView.Settings().startMode == "minimal" and "full" or "minimal")
        Options.Refresh()
    end)
    widgets.startButton:SetPoint("TOPLEFT", 20, y - 52)
    percentSlider(frame, y - 92, "opacity", Text["Opacity"], 20, 100, 5)
    percentSlider(frame, y - 126, "scale", Text["Size"], 50, 200, 10)
    widgets.lockButton = Widgets.CreateButton(frame, "", 200, 24, function()
        addon.PetView.Set("locked", not addon.PetView.Settings().locked)
        Options.Refresh()
    end)
    widgets.lockButton:SetPoint("TOPLEFT", 20, y - 160)
    widgets.combatButton = Widgets.CreateButton(frame, "", 200, 24, function()
        addon.PetView.Set("hideInCombat", not addon.PetView.Settings().hideInCombat)
        Options.Refresh()
    end)
    widgets.combatButton:SetPoint("TOPLEFT", 230, y - 160)
    local show = Widgets.CreateButton(frame, Text["Show minimal view"], 200, 24, function() addon.UI.SetMode("minimal") end)
    show:SetPoint("TOPLEFT", 20, y - 192)
end

-- Labels and slider positions of the pet view section.
function Options.RefreshPetView()
    if not (widgets.startButton and widgets.lockButton and widgets.combatButton) then return end
    local settings = addon.PetView.Settings()
    widgets.startButton:SetLabel(settings.startMode == "minimal" and Text["Opens with: minimal view"] or Text["Opens with: full view"])
    widgets.lockButton:SetLabel(settings.locked and Text["Position: locked"] or Text["Position: movable"])
    widgets.combatButton:SetLabel(settings.hideInCombat and Text["In combat: hidden"] or Text["In combat: shown"])
    widgets.refreshing = true
    for key, value in pairs(widgets.petValues) do
        local percent = settings[key] * 100
        value:SetText(percentText(percent))
        local slider = widgets.petSliders[key]
        if slider then slider:SetValue(percent) end
    end
    widgets.refreshing = false
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
    -- less immersive, easier: the icons sit next to the target frame (current target only) instead of on nameplates
    widgets.atTargetButton = Widgets.CreateButton(frame, "", 200, 24, function() Options.Change("atTarget") end)
    widgets.atTargetButton:SetPoint("TOPLEFT", 230, -72)
    widgets.atTargetButton:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Text["At the target frame"])
        GameTooltip:AddLine(Text["The rope icon and the catch items show next to the target frame, for your target only, instead of on the nameplates."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widgets.atTargetButton:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    stepper(frame, -112, "x", Text["Move left / right"])
    stepper(frame, -142, "y", Text["Move down / up"])
    stepper(frame, -172, "size", Text["Size"])
    local reset = Widgets.CreateButton(frame, Text["Reset"], 120, 22, function() Options.Reset() end)
    reset:SetPoint("TOPLEFT", 20, -208)
    -- a preview of the round icon
    local preview = frame:CreateTexture(nil, "ARTWORK")
    preview:SetPoint("TOPLEFT", 400, -120)
    addon.UIHelpers.SetTextureOr(preview, addon.Catcher.ROPE_ICON, { 1, 0.82, 0.2 })
    pcall(function()
        local mask = frame:CreateMaskTexture()
        mask:SetTexture(addon.Catcher.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(preview)
        preview:AddMaskTexture(mask)
    end)
    widgets.preview = preview
    Options.BuildPetView(frame, -260)
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

-- /gg caught icon [on|off|target on|target off|x <n>|y <n>|size <n>|reset]
function Options.Command(arguments)
    local word, number = (arguments or ""):match("^%s*(%S*)%s*(%-?%d*)")
    word = (word or ""):lower()
    local targetSwitch = (arguments or ""):lower():match("^%s*target%s+(%a+)")
    if word == "target" and (targetSwitch == "on" or targetSwitch == "off") then AzeCaught.SetIconSetting("atTarget", targetSwitch == "on")
    elseif word == "on" or word == "off" then AzeCaught.SetIconSetting("shown", word == "on")
    elseif (word == "x" or word == "y" or word == "size") and number ~= "" then AzeCaught.SetIconSetting(word, tonumber(number))
    elseif word == "reset" then AzeCaught.ResetIconSettings() end
    apply()
    local settings = AzeCaught.IconSettings()
    addon.Print(Format(Text["Rope icon: {shown}, x {x}, y {y}, size {size}. Options > AddOns > {title}."], { shown = settings.shown
        and Text["on"] or Text["off"], x = settings.x, y = settings.y, size = settings.size, title = widgets.frame and widgets.frame.name or "" }))
end

addon.Log.Protected("caught.options", "building the AZEcaught options failed", Options.Build)
