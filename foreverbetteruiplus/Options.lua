local addonName, addon = ...

-- Options window (/fbui): a global opacity slider, fade time, "full opacity in combat", and one row per element with
-- a mode button (Global -> Custom -> Off) and its own slider. Built from plain frames (own slider widget), so it does
-- not depend on Blizzard option templates that change between clients. A small page in the game's AddOns settings
-- opens it too.
local Logic, Elements = addon.Logic, addon.Elements
local Options = {}
addon.Options = Options

local ROW_HEIGHT, COLUMN_WIDTH, COLUMNS = 26, 450, 2
local widgets = { rows = {} }

local function db() return ForeverBetterUIPlusDB end

local function label(parent, text, template)
    local fontString = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fontString:SetText(text or "")
    return fontString
end

-- A horizontal 0..1 slider. onChange(value) is only called for user input.
local function slider(parent, width, step, onChange)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("HORIZONTAL")
    bar:SetSize(width, 17)
    bar:SetMinMaxValues(0, 1)
    bar:SetValueStep(step)
    bar:SetObeyStepOnDrag(true)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.7)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(6)
    local fill = bar:CreateTexture(nil, "BORDER")
    fill:SetColorTexture(1, 0.82, 0, 0.6)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetHeight(6)
    bar:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    bar.valueText = label(bar, "")
    bar.valueText:SetPoint("LEFT", bar, "RIGHT", 6, 0)
    bar.Set = function(self, value)
        self.quiet = true
        self:SetValue(value)
        self.quiet = false
        fill:SetWidth(math.max(1, width * value))
        self.valueText:SetText(Logic.Percent(value))
    end
    bar:SetScript("OnValueChanged", function(self, value)
        fill:SetWidth(math.max(1, width * value))
        self.valueText:SetText(Logic.Percent(value))
        if not self.quiet then onChange(value) end
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(self, delta)
        if self:IsEnabled() then self:SetValue(Logic.Clamp01(self:GetValue() + delta * step)) end
    end)
    bar.SetActive = function(self, active)
        if active then self:Enable() else self:Disable() end
        self:SetAlpha(active and 1 or 0.35)
    end
    return bar
end

local function button(parent, text, width, onClick)
    local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    widget:SetSize(width, 20)
    widget:SetText(text)
    widget:SetScript("OnClick", onClick)
    return widget
end

local MODE_COLORS = { global = "|cffffffff", custom = "|cffffd100", off = "|cff888888" }
local NEXT_MODE = { global = "custom", custom = "off", off = "global" }
local COMBAT_COLORS = { global = "|cffffffff", full = "|cff60ff60", faded = "|cffff9060" }
local NEXT_COMBAT = { global = true, full = false, faded = nil }   -- global -> full -> faded -> global

local function cycleCombat(key)
    local settings = db()
    settings.combat[key] = NEXT_COMBAT[Logic.CombatModeName(settings, key)]
    addon.Log.Write("options", "combat", { key = key, mode = Logic.CombatModeName(settings, key) })
    Options.Refresh()
end

local function setMode(key, mode)
    local settings = db()
    if mode == "custom" then
        settings.elements[key] = Logic.BaseAlpha(settings, key) or settings.global
    elseif mode == "off" then
        settings.elements[key] = Logic.MODE_OFF
    else
        settings.elements[key] = nil
    end
    addon.Log.Write("options", "mode", { key = key, mode = mode })
    Options.Refresh()
end

local function buildRow(parent, element, index)
    local column = (index - 1) % COLUMNS
    local line = math.floor((index - 1) / COLUMNS)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(COLUMN_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16 + column * (COLUMN_WIDTH + 12), -150 - line * ROW_HEIGHT)
    row.mode = button(row, "", 62, function() setMode(element.key, NEXT_MODE[Logic.ModeName(db(), element.key)]) end)
    row.mode:SetPoint("LEFT", 0, 0)
    row.name = label(row, element.label, "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.mode, "RIGHT", 8, 0)
    row.name:SetWidth(110)
    row.name:SetJustifyH("LEFT")
    row.slider = slider(row, 120, 0.05, function(value)
        db().elements[element.key] = value
    end)
    row.slider:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.combat = button(row, "", 96, function() cycleCombat(element.key) end)
    row.combat:SetPoint("LEFT", row.slider, "RIGHT", 44, 0)
    row.combat:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("In combat")
        GameTooltip:AddLine("Global: follows the \"Full opacity in combat\" checkbox", 1, 1, 1)
        GameTooltip:AddLine("Full: fully visible in combat", 1, 1, 1)
        GameTooltip:AddLine("Faded: keeps its opacity in combat", 1, 1, 1)
        GameTooltip:Show()
    end)
    row.combat:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.element = element
    return row
end

local function build()
    local frame = CreateFrame("Frame", "ForeverBetterUIPlusOptions", UIParent, "BasicFrameTemplateWithInset")
    local lines = math.ceil(#Elements.list / COLUMNS)
    frame:SetSize(COLUMNS * (COLUMN_WIDTH + 12) + 20, 170 + lines * ROW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", function() Options.Refresh() end)
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName())   -- Escape closes it

    local title = label(frame, "Forever Better UI Plus - opacity", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)

    local globalLabel = label(frame, "Global opacity", "GameFontNormal")
    globalLabel:SetPoint("TOPLEFT", 20, -40)
    widgets.global = slider(frame, 260, 0.05, function(value) db().global = value end)
    widgets.global:SetPoint("LEFT", globalLabel, "RIGHT", 16, 0)

    local fadeLabel = label(frame, "Fade time", "GameFontNormal")
    fadeLabel:SetPoint("TOPLEFT", 20, -72)
    widgets.fade = slider(frame, 260, 0.05, function(value) db().fadeSeconds = value end)
    widgets.fade:SetPoint("LEFT", widgets.global, "LEFT", 0, -32)
    -- the fade slider shows seconds, not percent
    widgets.fade:HookScript("OnValueChanged", function(self, value) self.valueText:SetFormattedText("%.2f s", value) end)

    widgets.combat = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    widgets.combat:SetPoint("TOPLEFT", 16, -96)
    widgets.combat:SetScript("OnClick", function(self)
        db().combatFull = self:GetChecked() and true or false
        Options.Refresh()
    end)
    local combatLabel = label(frame, "Full opacity in combat (for elements whose combat button is Global)", "GameFontHighlight")
    combatLabel:SetPoint("LEFT", widgets.combat, "RIGHT", 2, 0)

    local hint = label(frame, "Hovering an element always shows it fully, and so does Edit Mode. "
        .. "First button: Global (uses the global slider) / Custom / Off (not touched). "
        .. "Second button, in combat: Global (checkbox) / Full / Faded.")
    hint:SetPoint("TOPLEFT", 20, -128)
    hint:SetWidth(COLUMNS * (COLUMN_WIDTH + 12) - 20)
    hint:SetJustifyH("LEFT")

    local allGlobal = button(frame, "All to Global", 110, function()
        wipe(db().elements)
        wipe(db().combat)
        Options.Refresh()
    end)
    allGlobal:SetPoint("TOPRIGHT", -24, -36)

    for index, element in ipairs(Elements.list) do widgets.rows[index] = buildRow(frame, element, index) end
    widgets.frame = frame
end

function Options.Refresh()
    if not widgets.frame or not db() then return end
    local settings = db()
    widgets.global:Set(settings.global)
    widgets.fade:Set(math.min(1, settings.fadeSeconds))
    widgets.fade.valueText:SetFormattedText("%.2f s", settings.fadeSeconds)
    widgets.combat:SetChecked(settings.combatFull)
    for _, row in ipairs(widgets.rows) do
        local key = row.element.key
        local mode = Logic.ModeName(settings, key)
        row.mode:SetText(MODE_COLORS[mode] .. mode:sub(1, 1):upper() .. mode:sub(2) .. "|r")
        row.slider:Set(Logic.BaseAlpha(settings, key) or 1)
        row.slider:SetActive(mode == "custom")
        if mode == "global" then row.slider.valueText:SetText("|cff888888" .. Logic.Percent(settings.global) .. "|r") end
        if mode == "off" then row.slider.valueText:SetText("") end
        local combatMode = Logic.CombatModeName(settings, key)
        local combatText = combatMode == "global"
            and ("Global (" .. (settings.combatFull and "full" or "faded") .. ")") or (combatMode:sub(1, 1):upper() .. combatMode:sub(2))
        row.combat:SetText(COMBAT_COLORS[combatMode] .. combatText .. "|r")
        row.combat:SetShown(mode ~= "off")
        local frames = addon.Fader.Info(key)
        row.name:SetText(row.element.label .. (#frames == 0 and " |cffff6060(n/a)|r" or ""))
    end
end

function Options.Toggle()
    if not widgets.frame then build() end
    widgets.frame:SetShown(not widgets.frame:IsShown())
end

-- A page under Options > AddOns with a button that opens the window.
function Options.Register()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local page = CreateFrame("Frame")
    local title = label(page, "Forever Better UI Plus", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local text = label(page, "Opacity per UI element, full opacity on mouseover. Also: /fbui", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    local open = button(page, "Open options", 140, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if not widgets.frame then build() end
        widgets.frame:Show()
    end)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    local category = Settings.RegisterCanvasLayoutCategory(page, "Forever Better UI Plus")
    Settings.RegisterAddOnCategory(category)
end
