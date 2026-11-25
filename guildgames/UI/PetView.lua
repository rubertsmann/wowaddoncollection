local addonName, addon = ...

-- The minimal window: only the companion, no text. The round pet in the middle, four round care gauges around its
-- lower half (a ring that fills clockwise with the need), the hearts top right, the switch to the full window top
-- left and the training button at the bottom (a click opens the four stat icons; a click anywhere else closes them). Values, prices and refusals are in the tooltips. It stands in for the whole window (UI.SetMode); options
-- (start mode, opacity, size, lock, hide in combat) live in db.ui.petView and are read through Model.PetViewSettings.
---@class PetViewModule
local PetView = {}
addon.PetView = PetView

local AzeCaught = addon.AzeCaught
local Model = addon.Model
local Text, Format = addon.Text, addon.Locale.Format

local PET_SIZE, GAUGE_SIZE, CORNER_SIZE = 96, 30, 22
-- white anti-aliased shapes shipped with the addon (tinted with SetVertexColor), so circles stay smooth at any size
local TEXTURES = "Interface\\AddOns\\" .. addonName .. "\\UI\\Textures\\"
local DISC_TEXTURE, RING_TEXTURE, THIN_RING_TEXTURE = TEXTURES .. "Disc", TEXTURES .. "Ring", TEXTURES .. "RingThin"
-- 64 arcs of Ring in an 8 x 8 grid: cell n shows n/64 of the ring, clockwise from 12 o'clock (Model.RingArc)
local ARCS_TEXTURE, ARC_COLUMNS = TEXTURES .. "RingArcs", 8
local RING_TRACK = { 0.16, 0.16, 0.18, 0.95 }
local OUTLINE_COLOR = { 0.95, 0.78, 0.3 }
local FADE_SECONDS = 0.2
local REFRESH_SECONDS = 0.5
local PLACEHOLDER_ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"
local TRAIN_ICON = "Interface\\Icons\\Spell_Nature_Strength"
local FULL_VIEW_ICON = "Interface\\Buttons\\UI-Panel-BiggerButton-Up"
local MINIMAL_VIEW_ICON = "Interface\\Buttons\\UI-Panel-SmallerButton-Up"
PetView.FULL_VIEW_ICON, PetView.MINIMAL_VIEW_ICON = FULL_VIEW_ICON, MINIMAL_VIEW_ICON

---@type table frames of the view
local widgets = {}
PetView.widgets = widgets
---@type { hiddenByCombat: boolean, hovered: boolean, alpha: number, lastHearts: integer|nil, coolingDown: boolean }
local state = { hiddenByCombat = false, hovered = false, alpha = 1, lastHearts = nil, coolingDown = false }
PetView.state = state

---@return table the raw saved table (db.ui.petView), created on first use
local function saved()
    local ui = addon.UIHelpers.Settings()
    if type(ui.petView) ~= "table" then ui.petView = {} end
    return ui.petView
end

---@return table the options with defaults and limits
function PetView.Settings() return Model.PetViewSettings(addon.UIHelpers.Settings().petView) end

-- Changes one option and applies it at once.
---@param key "startMode"|"opacity"|"scale"|"locked"|"hideInCombat"|"mode"|"open"
---@param value any
function PetView.Set(key, value)
    saved()[key] = value
    local clean = PetView.Settings()
    saved()[key] = clean[key]
    AzeCaught.Journal("DEBUG", "petView.option", "a pet view option changed", { key = key, value = tostring(clean[key]) })
    PetView.Apply()
end

---@param region table
---@param parent table the frame that owns the mask
local function makeRound(region, parent)
    pcall(function()
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(addon.Catcher.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(region)
        region:AddMaskTexture(mask)
    end)
end

---@param parent table
---@param size number
---@param color number[]
---@param layer string
---@param subLevel? integer
---@return table texture
local function disc(parent, size, color, layer, subLevel)
    return PetView.Shape(parent, DISC_TEXTURE, size, color, layer, subLevel)
end

-- A shipped shape texture, centred on `parent` and tinted. Without the file it falls back to a masked colour square.
---@param parent table
---@param path string
---@param size number
---@param color number[]
---@param layer string
---@param subLevel? integer
---@return table texture
function PetView.Shape(parent, path, size, color, layer, subLevel)
    local texture = parent:CreateTexture(nil, layer, nil, subLevel)
    texture:SetSize(size, size); texture:SetPoint("CENTER")
    -- transparent outside the image: a turned texture must not repeat into its corners
    if texture:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") == false then
        texture:SetColorTexture(1, 1, 1, 1)
        makeRound(texture, parent)
    end
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return texture
end

---@param owner table
---@param lines { [1]: string, [2]: number[]|nil }[]
local function showTooltip(owner, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    for index, line in ipairs(lines) do
        local color = line[2] or { 1, 1, 1 }
        if index == 1 then GameTooltip:SetText(line[1], color[1], color[2], color[3])
        else GameTooltip:AddLine(line[1], color[1], color[2], color[3], true) end
    end
    GameTooltip:Show()
    state.tooltipOwner = owner
end

-- Hides the tooltip at once, if it is still one of this view's.
local function hideTooltip()
    local owner = state.tooltipOwner
    state.tooltipOwner = nil
    if owner and GameTooltip and GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
end

------------------------------------------------------------------ gauges

---@param button table
---@param key "feed"|"water"|"pet"|"sleep"
local function gaugeTooltip(button, key)
    local companion = AzeCaught.Active()
    local Panel = addon.AzeCaughtPanel
    local action = (key == "sleep" and companion and companion.asleep) and "wake" or key
    local lines = {}
    local money = Model.MoneyText
    if action == "feed" then lines[1] = { Format(Text["Feed for {gold}"], { gold = money(AzeCaught.FOOD_PRICE) }) }
    elseif action == "water" then lines[1] = { Format(Text["Water for {gold}"], { gold = money(AzeCaught.WATER_PRICE) }) }
    elseif action == "pet" then lines[1] = { Text["Petting is free."] }
    elseif action == "wake" then lines[1] = { Text["Wake"] }
    else lines[1] = { Format(Text["Sleeps {time}; refills energy."], { time = Model.Duration(AzeCaught.SLEEP_DURATION) }) } end
    if companion then
        local need = Model.GAUGE_NEED[key]
        local value = tonumber(companion[need]) or 0
        lines[#lines + 1] = { Format(Text["{need}: {value}%"], { need = Panel.NeedLabel(need), value = math.floor(value + 0.5) }),
            Model.GaugeColor(AzeCaught.ZoneOf(companion, need)) }
        if companion.asleep and key == "sleep" then
            lines[#lines + 1] = { Format(Text["Asleep, wakes in {time}"], { time = Model.Duration(companion.asleep) }), { 0.7, 0.7, 1 } }
        end
    end
    if button.unusable then lines[#lines + 1] = { Panel.CareRefusalText(button.unusable), { 1, 0.4, 0.4 } } end
    showTooltip(button, lines)
end

---@param parent table
---@param key "feed"|"water"|"pet"|"sleep"
---@return table button
local function createGauge(parent, key)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(GAUGE_SIZE, GAUGE_SIZE)
    button.back = disc(button, GAUGE_SIZE - 2, { 0, 0, 0, 0.75 }, "BACKGROUND")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(GAUGE_SIZE - 10, GAUGE_SIZE - 10); icon:SetPoint("CENTER")
    makeRound(icon, button)
    button.icon = icon
    local highlight = disc(button, GAUGE_SIZE - 10, { 1, 1, 1, 0.25 }, "HIGHLIGHT")
    button.highlight = highlight
    -- the ring: a dark track and, on top, the arc cell for the share (no rotation or clipping needed)
    button.track = PetView.Shape(button, RING_TEXTURE, GAUGE_SIZE, RING_TRACK, "BORDER")
    button.arc = PetView.Shape(button, ARCS_TEXTURE, GAUGE_SIZE, { 1, 1, 1, 1 }, "OVERLAY")
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self)
        addon.AzeCaughtPanel.ClickCare(key, PetView.CareTarget())
        PetView.Refresh()
        if self:IsMouseOver() then gaugeTooltip(self, key) end
    end)
    button:SetScript("OnEnter", function(self) state.hovered = true; gaugeTooltip(self, key) end)
    button:SetScript("OnLeave", hideTooltip)
    return button
end

---@param button table
---@param key "feed"|"water"|"pet"|"sleep"
---@param companion CompanionState|nil
local function fillGauge(button, key, companion)
    local Panel = addon.AzeCaughtPanel
    local action = (key == "sleep" and companion and companion.asleep) and "wake" or key
    addon.UIHelpers.SetTextureOr(button.icon, Panel.CARE_ICONS[action], Panel.ACTION_COLOR[action] or { 1, 1, 1 })
    local share, color = 0, Model.GaugeColor(nil)
    if companion then
        local need = Model.GAUGE_NEED[key]
        local neverNeeded = not AzeCaught.ProfileOf(companion).intervals[need]
        share = neverNeeded and 1 or Model.GaugeShare(companion[need])
        color = neverNeeded and Model.GaugeColor(nil) or Model.GaugeColor(AzeCaught.ZoneOf(companion, need))
    end
    PetView.FillRing(button, share, color)
    local usable, reason = false, "none"
    if companion then usable, reason = AzeCaught.CareAvailability(action, addon.Utility.Me()) end
    button.unusable = not usable and reason or nil
    local enabled = usable and not state.coolingDown
    button:SetEnabled(enabled)
    pcall(button.icon.SetDesaturated, button.icon, not enabled)
    button.icon:SetAlpha(enabled and 1 or 0.45)
end

-- Shows `share` (0..1) of the ring in `color`, clockwise from 12 o'clock; nothing at 0.
---@param button table
---@param share number
---@param color number[]
function PetView.FillRing(button, share, color)
    local cell = Model.RingArc(share, ARC_COLUMNS * ARC_COLUMNS)
    button.arc:SetShown(cell ~= nil)
    if not cell then return end
    button.arc:SetTexCoord(Model.ArcTexCoord(cell, ARC_COLUMNS))
    button.arc:SetVertexColor(color[1], color[2], color[3], 1)
end

------------------------------------------------------------------ build

---@return CareTarget
function PetView.CareTarget()
    return { parent = widgets.frame, model = widgets.model }
end

---@return number left, number top the view's top-left corner in UIParent units
function PetView.TopLeft()
    local frame = widgets.frame
    local scale = tonumber(frame:GetScale()) or 1
    return (tonumber(frame:GetLeft()) or 0) * scale, (tonumber(frame:GetTop()) or 0) * scale
end

-- Puts the view's top-left corner at (left, top) in UIParent units, kept on the screen.
---@param left number|nil
---@param top number|nil
function PetView.Place(left, top)
    local frame = widgets.frame
    local scale = PetView.Settings().scale
    local screenWidth = tonumber(UIParent and UIParent:GetWidth()) or 1920
    local screenHeight = tonumber(UIParent and UIParent:GetHeight()) or 1080
    local width, height = (tonumber(frame:GetWidth()) or 0) * scale, (tonumber(frame:GetHeight()) or 0) * scale
    left, top = Model.KeepOnScreen(left, top, width, height, screenWidth, screenHeight)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end

local function savePosition()
    local left, top = PetView.TopLeft()
    saved().left, saved().top = left, top
end

---@param frame table
---@return boolean
local function mouseOver(frame)
    if frame.IsMouseOver then
        local ok, over = pcall(frame.IsMouseOver, frame)
        if ok then return over and true or false end
    end
    return (MouseIsOver and MouseIsOver(frame)) and true or false
end

local function build()
    if widgets.frame then return widgets.frame end
    local layout = Model.PetViewLayout(PET_SIZE, GAUGE_SIZE, CORNER_SIZE)
    local frame = CreateFrame("Frame", addon.FRAME_PREFIX .. "PetView", UIParent)
    frame:SetSize(layout.width, layout.height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if PetView.Settings().locked then return end
        self.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = false
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:Hide()
    widgets.frame = frame

    local function at(region, point)
        region:SetPoint("CENTER", frame, "TOPLEFT", point.x, point.y)
    end

    -- the pet: a dark disc in a thin gold ring, the model on top (a model cannot be masked, it has no background)
    local pet = CreateFrame("Frame", nil, frame)
    pet:SetSize(PET_SIZE, PET_SIZE); at(pet, layout.pet)
    widgets.backdrop = disc(pet, PET_SIZE, { 0.04, 0.04, 0.06, 0.85 }, "BACKGROUND")
    widgets.outline = PetView.Shape(pet, THIN_RING_TEXTURE, PET_SIZE + 4, { OUTLINE_COLOR[1], OUTLINE_COLOR[2], OUTLINE_COLOR[3], 0.95 }, "BORDER")
    widgets.pet = pet
    local model = CreateFrame("DressUpModel", nil, pet)
    model:SetSize(PET_SIZE - 6, PET_SIZE - 6); model:SetPoint("CENTER", 0, -2)
    if model.SetKeepModelOnHide then model:SetKeepModelOnHide(true) end
    addon.AzeCaughtPanel.PrepareModel(model, addon.AzeCaughtPanel.IdleOfCompanion)
    widgets.model = model
    -- no companion: a dimmed placeholder; a click opens the full window at AZEcaught
    local placeholder = CreateFrame("Button", nil, pet)
    placeholder:SetSize(PET_SIZE - 30, PET_SIZE - 30); placeholder:SetPoint("CENTER")
    local placeholderIcon = placeholder:CreateTexture(nil, "ARTWORK"); placeholderIcon:SetAllPoints()
    addon.UIHelpers.SetTextureOr(placeholderIcon, PLACEHOLDER_ICON, { 0.5, 0.5, 0.5 })
    makeRound(placeholderIcon, placeholder)
    pcall(placeholderIcon.SetDesaturated, placeholderIcon, true)
    placeholderIcon:SetAlpha(0.5)
    placeholder:SetScript("OnClick", function() PetView.OpenFullAtCaught() end)
    placeholder:SetScript("OnEnter", function(self)
        state.hovered = true
        showTooltip(self, { { Text["No companion yet."] }, { Text["Click: open AZEcaught."], { 0.7, 0.7, 0.7 } } })
    end)
    placeholder:SetScript("OnLeave", hideTooltip)
    widgets.placeholder = placeholder

    -- the four gauges around the lower half
    widgets.gauges = {}
    for _, key in ipairs(Model.PET_VIEW_GAUGES) do
        local gauge = createGauge(frame, key)
        at(gauge, layout.gauges[key])
        widgets.gauges[key] = gauge
    end

    -- the hearts, top right: the count is in the tooltip only
    local heart = CreateFrame("Frame", nil, frame)
    heart:SetSize(CORNER_SIZE, CORNER_SIZE); at(heart, layout.heart)
    disc(heart, CORNER_SIZE, { 0, 0, 0, 0.75 }, "BACKGROUND")
    local heartIcon = heart:CreateTexture(nil, "ARTWORK")
    heartIcon:SetSize(CORNER_SIZE - 4, CORNER_SIZE - 4); heartIcon:SetPoint("CENTER")
    addon.UIHelpers.SetTextureOr(heartIcon, addon.AzeCaughtPanel.HEART_ICON, { 0.9, 0.1, 0.2 })
    makeRound(heartIcon, heart)
    heart:EnableMouse(true)
    heart:SetScript("OnEnter", function(self)
        state.hovered = true
        local companion = AzeCaught.Active()
        if not companion then return end
        showTooltip(self, { { Format(Text["Hearts: {n}"], { n = companion.hearts }), companion.hearts < 0 and { 0.7, 0.2, 0.2 } or { 1, 0.3, 0.4 } },
            { addon.Utility.Escape(addon.Utility.ShortText(companion.n or "", 28)), { 1, 0.82, 0.2 } } })
    end)
    heart:SetScript("OnLeave", hideTooltip)
    widgets.heart, widgets.heartIcon = heart, heartIcon

    -- the switch to the full window, top left (the full window has its switch at the same spot)
    local switch = CreateFrame("Button", nil, frame)
    switch:SetSize(CORNER_SIZE, CORNER_SIZE); at(switch, layout.switch)
    disc(switch, CORNER_SIZE, { 0, 0, 0, 0.75 }, "BACKGROUND")
    local switchIcon = switch:CreateTexture(nil, "ARTWORK")
    switchIcon:SetSize(CORNER_SIZE - 2, CORNER_SIZE - 2); switchIcon:SetPoint("CENTER")
    addon.UIHelpers.SetTextureOr(switchIcon, FULL_VIEW_ICON, { OUTLINE_COLOR[1], OUTLINE_COLOR[2], OUTLINE_COLOR[3] })
    disc(switch, CORNER_SIZE - 4, { 1, 1, 1, 0.2 }, "HIGHLIGHT")
    switch:RegisterForClicks("LeftButtonUp")
    switch:SetScript("OnClick", function() addon.UI.SetMode("full") end)
    switch:SetScript("OnEnter", function(self) state.hovered = true; showTooltip(self, { { Text["Full view"] } }) end)
    switch:SetScript("OnLeave", hideTooltip)
    widgets.switch = switch

    PetView.BuildTraining(frame, layout.train, at)

    -- live: needs decay, sleep ends; the opacity follows the mouse
    local sinceRefresh = 0
    frame:SetScript("OnUpdate", function(self, elapsedSeconds)
        -- a button disabled under the mouse (care cooldown) gets no OnLeave: the tooltip would linger and fade slowly
        local owner = state.tooltipOwner
        if owner and (GameTooltip:GetOwner() ~= owner) then state.tooltipOwner = nil
        elseif owner and (not owner:IsVisible() or not mouseOver(owner)) then hideTooltip() end
        local hovered = mouseOver(self) or self.dragging or (widgets.trainMenu and widgets.trainMenu:IsShown() and mouseOver(widgets.trainMenu))
        local settings = PetView.Settings()
        local target = hovered and 1 or settings.opacity
        state.alpha = state.alpha + (target - state.alpha) * math.min(1, elapsedSeconds * 8)
        if not addon.Animate.IsTweening("petView") then self:SetAlpha(state.alpha) end
        sinceRefresh = sinceRefresh + elapsedSeconds
        if sinceRefresh < REFRESH_SECONDS then return end
        sinceRefresh = 0
        addon.Log.Protected("petView.refresh", "refreshing the pet view failed", PetView.Refresh)
        addon.Log.Protected("petView.emote", "an idle emote failed", addon.AzeCaughtPanel.MaybeIdleEmote, widgets.model)
    end)
    frame:SetScript("OnHide", function() hideTooltip(); PetView.CloseTraining() end)
    frame:SetScript("OnShow", function()
        model.shownKey = nil   -- the model resets on show: load it again
        PetView.Refresh()
        addon.AzeCaughtPanel.IdleOfCompanion(model, "petViewShown")
        if C_Timer then C_Timer.After(0.3, function()
            if frame:IsVisible() then addon.AzeCaughtPanel.FitCamera(model); addon.AzeCaughtPanel.IdleOfCompanion(model, "petViewShownLate") end
        end) end
    end)
    addon.Events.On("CAUGHT_CHANGED", function() if frame:IsShown() then PetView.Refresh() end end)
    addon.Events.On("CARE_COOLDOWN", function() if frame:IsShown() then PetView.Refresh() end end)
    AzeCaught.Journal("DEBUG", "petView.build", "the pet view was built", { width = layout.width, height = layout.height })
    return frame
end
PetView.Build = build

------------------------------------------------------------------ training menu

-- The training button (a small round icon under the pet) and its menu: the four stat icons in a row below it. A click
-- on an icon trains that stat; the running training shows its time on its icon, the others are greyed out. A click
-- anywhere else closes the menu (GLOBAL_MOUSE_DOWN; without it a screen-wide catcher takes that click).
---@param frame table the view
---@param point { x: number, y: number }
---@param at fun(region: table, point: table)
function PetView.BuildTraining(frame, point, at)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(CORNER_SIZE, CORNER_SIZE); at(button, point)
    disc(button, CORNER_SIZE, { 0, 0, 0, 0.75 }, "BACKGROUND")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CORNER_SIZE - 4, CORNER_SIZE - 4); icon:SetPoint("CENTER")
    addon.UIHelpers.SetTextureOr(icon, TRAIN_ICON, { 1, 0.75, 0.2 })
    makeRound(icon, button)
    button.icon = icon
    -- a training runs: a thin gold ring around the button
    button.ring = PetView.Shape(button, THIN_RING_TEXTURE, CORNER_SIZE + 4, { 1, 0.82, 0, 0.95 }, "BORDER")
    button.ring:Hide()
    disc(button, CORNER_SIZE - 4, { 1, 1, 1, 0.2 }, "HIGHLIGHT")
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function() PetView.ToggleTraining() end)
    button:SetScript("OnEnter", function(self)
        state.hovered = true
        local lines = { { Text["Training"], { 1, 0.82, 0 } } }
        local current = addon.ArenaView.FighterState()
        if current and current.training and current.left then
            lines[2] = { Format(Text["Training {stat}: {time} left (play time)"], { stat = addon.ArenaView.STAT_TEXT[current.training.stat],
                time = ("%d:%02d"):format(math.floor(current.left / 60), math.floor(current.left) % 60) }) }
        else
            lines[2] = { Text["Not training."], { 0.7, 0.7, 0.7 } }
        end
        showTooltip(self, lines)
    end)
    button:SetScript("OnLeave", hideTooltip)
    widgets.trainButton = button

    local STAT_SIZE, GAP = 28, 6
    local count = #addon.Arena.STATS
    local menu = CreateFrame("Frame", nil, frame)
    menu:SetSize(count * STAT_SIZE + (count + 1) * GAP, STAT_SIZE + 2 * GAP)
    menu:SetFrameLevel(frame:GetFrameLevel() + 20)
    menu:EnableMouse(true)
    local plate = menu:CreateTexture(nil, "BACKGROUND"); plate:SetAllPoints(); plate:SetColorTexture(0.04, 0.04, 0.06, 0.9)
    menu:Hide()
    widgets.trainMenu = menu
    widgets.trainIcons = {}
    for index, stat in ipairs(addon.Arena.STATS) do
        local statIcon = addon.ArenaView.CreateStatIcon(menu, stat, STAT_SIZE, false)
        statIcon:SetPoint("TOPLEFT", GAP + (index - 1) * (STAT_SIZE + GAP), -GAP)
        statIcon:HookScript("OnClick", function() PetView.RefreshTraining() end)
        widgets.trainIcons[stat] = statIcon
    end
    -- closes on a click outside the menu and the button
    local closer = CreateFrame("Frame", nil, menu)
    local listens = pcall(closer.RegisterEvent, closer, "GLOBAL_MOUSE_DOWN")
    if listens then
        closer:SetScript("OnEvent", function()
            if menu:IsShown() and not mouseOver(menu) and not mouseOver(button) then PetView.CloseTraining() end
        end)
    else
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("MEDIUM"); catcher:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
        catcher:RegisterForClicks("AnyUp"); catcher:SetScript("OnClick", function() PetView.CloseTraining() end)
        catcher:Hide()
        widgets.trainCatcher = catcher
    end
    AzeCaught.Journal("DEBUG", "petView.train", "the training menu was built", { globalMouse = listens and true or false })
end

-- Opens the training menu below the training button (above it when there is no room below), or closes it.
function PetView.ToggleTraining()
    local menu = widgets.trainMenu
    if not menu then return end
    if menu:IsShown() then PetView.CloseTraining() return end
    if not addon.ArenaView.FighterState() then return end
    hideTooltip()
    menu:ClearAllPoints()
    local bottom = tonumber(widgets.trainButton:GetBottom()) or 1000
    if bottom - menu:GetHeight() - 6 < 0 then menu:SetPoint("BOTTOM", widgets.trainButton, "TOP", 0, 4)
    else menu:SetPoint("TOP", widgets.trainButton, "BOTTOM", 0, -4) end
    menu:Show()
    if widgets.trainCatcher then widgets.trainCatcher:Show() end
    PetView.RefreshTraining()
end

function PetView.CloseTraining()
    if widgets.trainMenu then widgets.trainMenu:Hide() end
    if widgets.trainCatcher then widgets.trainCatcher:Hide() end
end

-- The training button (shown with a companion, a gold ring while a stat trains) and the open menu's icons.
function PetView.RefreshTraining()
    if not widgets.trainButton then return end
    local current = addon.ArenaView.FighterState()
    widgets.trainButton:SetShown(current ~= nil)
    widgets.trainButton.ring:SetShown(current ~= nil and current.training ~= nil and current.left ~= nil)
    if not current then PetView.CloseTraining() return end
    if widgets.trainMenu:IsShown() then
        for _, statIcon in pairs(widgets.trainIcons) do addon.ArenaView.FillStatIcon(statIcon, current) end
    end
end

------------------------------------------------------------------ refresh, show, hide

function PetView.Refresh()
    local frame = widgets.frame
    if not frame then return end
    local companion = AzeCaught.Active()
    state.coolingDown = addon.AzeCaughtPanel.CareCooldownLeft() > 0
    widgets.placeholder:SetShown(companion == nil)
    widgets.model:SetShown(companion ~= nil)
    widgets.heart:SetShown(companion ~= nil)
    addon.AzeCaughtPanel.ShowModel(widgets.model, companion, "petView")
    if companion and widgets.model.asleepShown ~= (companion.asleep ~= nil) then
        addon.AzeCaughtPanel.IdleOfCompanion(widgets.model, companion.asleep and "fellAsleep" or "wokeUp")
    end
    for key, gauge in pairs(widgets.gauges) do fillGauge(gauge, key, companion) end
    PetView.RefreshTraining()
    if companion then
        local hearts = tonumber(companion.hearts) or 0
        local negative = hearts < 0
        pcall(widgets.heartIcon.SetDesaturated, widgets.heartIcon, negative)
        if negative then widgets.heartIcon:SetVertexColor(0.55, 0.12, 0.12) else widgets.heartIcon:SetVertexColor(1, 1, 1) end
        if state.lastHearts and hearts > state.lastHearts then addon.Animate.Pulse(widgets.heartIcon, 1.6, 0.4) end
        state.lastHearts = hearts
    else
        state.lastHearts = nil
    end
end

-- Opacity, size and position from the options (called after every option change).
function PetView.Apply()
    if not widgets.frame then return end
    local settings = PetView.Settings()
    local left, top = settings.left, settings.top
    if widgets.frame:IsShown() and tonumber(widgets.frame:GetLeft()) then left, top = PetView.TopLeft() end
    PetView.Place(left, top)
    savePosition()
    state.alpha = settings.opacity
    widgets.frame:SetAlpha(settings.opacity)
end

---@return boolean
function PetView.IsShown() return (widgets.frame and widgets.frame:IsShown() and not state.closing) and true or false end

-- Shows the view with its top-left corner at (left, top), or where it was last.
---@param left? number
---@param top? number
function PetView.Show(left, top)
    local frame = build()
    local settings = PetView.Settings()
    PetView.Place(left or settings.left, top or settings.top)
    savePosition()
    saved().open = true
    state.closing = false
    if InCombatLockdown and InCombatLockdown() and settings.hideInCombat then
        state.hiddenByCombat = true
        return
    end
    state.alpha = settings.opacity
    frame:SetAlpha(0)
    frame:Show()
    addon.Animate.Tween("petView", FADE_SECONDS, function(elapsed) frame:SetAlpha(state.alpha * elapsed / FADE_SECONDS) end,
        function() frame:SetAlpha(state.alpha) end)
end

-- Hides the view. `keepOpen` (combat) remembers it as open, so it comes back.
---@param animate boolean
---@param keepOpen? boolean
function PetView.Hide(animate, keepOpen)
    local frame = widgets.frame
    if not keepOpen then saved().open = false; state.hiddenByCombat = false end
    if not frame or not frame:IsShown() then return end
    if frame.dragging then frame.dragging = false; frame:StopMovingOrSizing(); savePosition() end
    hideTooltip()
    if not animate then addon.Animate.FinishTween("petView"); frame:Hide(); return end
    state.closing = true
    local fromAlpha = frame:GetAlpha() or 1
    addon.Animate.Tween("petView", FADE_SECONDS, function(elapsed) frame:SetAlpha(fromAlpha * (1 - elapsed / FADE_SECONDS)) end,
        function() state.closing = false; frame:Hide() end)
end

-- The full window at AZEcaught (the placeholder's click).
function PetView.OpenFullAtCaught()
    addon.UI.SetMode("full")
    if addon.GamesTab.SelectGame then addon.GamesTab.SelectGame("caught") end
end

------------------------------------------------------------------ combat and login

local eventFrame = CreateFrame("Frame")
for _, gameEvent in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN" }) do
    pcall(eventFrame.RegisterEvent, eventFrame, gameEvent)
end
eventFrame:SetScript("OnEvent", function(_, gameEvent)
    addon.Log.Protected("petView.event", "a pet view event failed (" .. tostring(gameEvent) .. ")", function()
        if not addon.db then return end
        local settings = PetView.Settings()
        if gameEvent == "PLAYER_LOGIN" then
            -- open at logout or reload: open again
            if settings.open and settings.mode == "minimal" then PetView.Show() end
        elseif gameEvent == "PLAYER_REGEN_DISABLED" then
            if settings.hideInCombat and PetView.IsShown() then
                state.hiddenByCombat = true
                PetView.Hide(true, true)
            end
        elseif gameEvent == "PLAYER_REGEN_ENABLED" then
            if state.hiddenByCombat then
                state.hiddenByCombat = false
                if settings.open and settings.mode == "minimal" then PetView.Show() end
            end
        end
    end)
end)
