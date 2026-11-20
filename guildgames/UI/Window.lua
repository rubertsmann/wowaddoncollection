local addonName, addon = ...

-- The window: a light overlay, not a dialog. No border and no template frame. A faint backdrop shows the game world
-- through; it darkens while the mouse is over the window and fades back when the mouse leaves. A slim header holds
-- the game switch, the leaderboard toggle and close, and is the drag handle. The guild leaderboard is a sidebar that
-- slides out on the right and is hidden by default (db.ui.sidebarOpen).
-- Only the header, the buttons and the boxes take the mouse. Clicks on the transparent parts reach the world below.
-- Plain frames only (no secure templates), so it never taints and is safe to open in combat.
-- All text goes through Text (Locales/).
---@class UIModule
local UI = {}
addon.UI = UI

local Text = addon.Text
local Widgets = LibStub("LibGuildSync-1.0").Widgets

local STAGE_WIDTH, STAGE_HEIGHT = 300, 336
local HEADER_HEIGHT = 24
local SIDEBAR_WIDTH, SIDEBAR_HEIGHT = 350, 400
local BACKDROP_IDLE, BACKDROP_HOVER = 0.10, 0.55
local SIDEBAR_IDLE, SIDEBAR_HOVER = 0.35, 0.72
local HEADER_IDLE, HEADER_HOVER = 0.45, 1
local ACCENT = { 1, 0.78, 0.25 }

------------------------------------------------------------------ flat widgets
-- These replace the red UIPanelButtonTemplate and the boxed InputBoxTemplate. The look is a dark translucent plate with
-- gold text, a soft highlight on hover and a gold underline when the button is selected.

---@param button table
local function paintButton(button)
    local selected, enabled, hovered = button.selected, button:IsEnabled(), button.hovered
    local plateAlpha = button.primary and (enabled and 0.85 or 0.35) or (selected and 0.55 or 0.35)
    if hovered and enabled then plateAlpha = plateAlpha + 0.15 end
    local tint = button.primary and { 0.45, 0.30, 0.04 } or { 0, 0, 0 }
    button.plate:SetColorTexture(tint[1], tint[2], tint[3], plateAlpha)
    button.underline:SetShown(selected and true or false)
    local fontString = button:GetFontString()
    if fontString then
        if selected or (hovered and enabled) then fontString:SetTextColor(1, 1, 1)
        elseif enabled then fontString:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        else fontString:SetTextColor(0.5, 0.5, 0.5) end
    end
end

-- A flat button (same signature as LibGuildSync's CreateButton) with :SetSelected(selected).
---@param parent table
---@param label string
---@param minimumWidth number
---@param height? number
---@param onClick? function
---@return table
local function createFlatButton(parent, label, minimumWidth, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(minimumWidth, height or 20)
    button.minimumWidth = minimumWidth
    button.plate = button:CreateTexture(nil, "BACKGROUND"); button.plate:SetAllPoints()
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetHeight(2); button.underline:SetPoint("BOTTOMLEFT", 3, 0); button.underline:SetPoint("BOTTOMRIGHT", -3, 0)
    button.underline:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button:SetDisabledFontObject("GameFontNormalSmall")
    button:SetPushedTextOffset(0, -1)
    button.SetLabel = Widgets.SetButtonLabel
    button:SetLabel(label)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self) self.hovered = true; paintButton(self) end)
    button:SetScript("OnLeave", function(self) self.hovered = false; paintButton(self) end)
    button:SetScript("OnEnable", paintButton)
    button:SetScript("OnDisable", paintButton)
    function button:SetSelected(selected) self.selected = selected and true or false; paintButton(self) end
    paintButton(button)
    return button
end

-- The big action button (Flip, Spin): a gold plate that breathes softly while it can be pressed.
---@param button table
local function makePrimary(button)
    button.primary = true
    button:SetNormalFontObject("GameFontNormal"); button:SetHighlightFontObject("GameFontHighlight")
    button:SetDisabledFontObject("GameFontDisable")
    local breath = button:CreateTexture(nil, "BORDER")
    breath:SetPoint("TOPLEFT", -6, 6); breath:SetPoint("BOTTOMRIGHT", 6, -6)
    breath:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); breath:SetBlendMode("ADD")
    breath:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3]); breath:SetAlpha(0)
    local time = 0
    button:SetScript("OnUpdate", function(self, elapsedSeconds)
        time = time + elapsedSeconds
        breath:SetAlpha(self:IsEnabled() and (0.12 + 0.12 * math.sin(time * 2.4)) or 0)
    end)
    paintButton(button)
end

-- A flat numeric box: dark plate, a gold underline that brightens while typing.
---@param parent table
---@param width number
---@return table editBox
local function createFlatEditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 18)
    box:SetFontObject("ChatFontNormal")
    box:SetJustifyH("RIGHT")
    box:SetTextInsets(3, 3, 0, 0)
    local plate = box:CreateTexture(nil, "BACKGROUND"); plate:SetAllPoints(); plate:SetColorTexture(0, 0, 0, 0.45)
    local line = box:CreateTexture(nil, "ARTWORK"); line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.35)
    box:SetScript("OnEditFocusGained", function(self) line:SetAlpha(1); line:SetHeight(2); self:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(self) line:SetAlpha(1); line:SetHeight(1); self:HighlightText(0, 0) end)
    return box
end

-- The widget helpers GamesTab and SlotMachine use: LibGuildSync's lists and texts plus the flat buttons and boxes
-- above. TimeAgo uses this addon's texts (Text["just now"], Text["{n}m ago"], Text["{n}h ago"], Text["{n}d ago"]).
UI.Widgets = { ROW_HEIGHT = Widgets.ROW_HEIGHT, CreateButton = createFlatButton, MakePrimary = makePrimary,
    CreateEditBox = createFlatEditBox, CreateFontString = Widgets.CreateFontString,
    CreateScrollList = Widgets.CreateScrollList, CreateSelectableRow = Widgets.CreateSelectableRow,
    TimeAgo = function(timestamp) return Widgets.TimeAgo(timestamp, Text) end }

------------------------------------------------------------------ window

---@type table|nil the main window
local mainFrame
---@type table frames of the built window
local parts = {}
UI.parts = parts

local settings = addon.UIHelpers.Settings

---@param current number
---@param target number
---@param elapsedSeconds number
---@return number
local function approach(current, target, elapsedSeconds)
    local step = math.min(1, elapsedSeconds * 8)
    return current + (target - current) * step
end

-- Darkens the backdrops and brightens the header while the mouse is over the window or the sidebar.
---@param elapsedSeconds number
---@param frame table
---@return boolean
local function mouseOver(frame)
    if frame.IsMouseOver then
        local ok, over = pcall(frame.IsMouseOver, frame)
        if ok then return over and true or false end
    end
    return (MouseIsOver and MouseIsOver(frame)) and true or false
end

local function updateHover(elapsedSeconds)
    local hovered = mouseOver(mainFrame) or (parts.sidebar:IsShown() and mouseOver(parts.sidebar))
    parts.backdropAlpha = approach(parts.backdropAlpha, hovered and BACKDROP_HOVER or BACKDROP_IDLE, elapsedSeconds)
    parts.sidebarAlpha = approach(parts.sidebarAlpha, hovered and SIDEBAR_HOVER or SIDEBAR_IDLE, elapsedSeconds)
    parts.headerAlpha = approach(parts.headerAlpha, hovered and HEADER_HOVER or HEADER_IDLE, elapsedSeconds)
    parts.backdrop:SetAlpha(parts.backdropAlpha)
    parts.sidebarBackdrop:SetAlpha(parts.sidebarAlpha)
    parts.header:SetAlpha(parts.headerAlpha)
    if parts.grip then parts.grip:SetAlpha(parts.grip.dragging and 1 or parts.headerAlpha) end
    if parts.mover then parts.mover:SetAlpha(parts.mover.dragging and 1 or parts.headerAlpha) end
end

------------------------------------------------------------------ position and scale (the grip in the bottom right)

UI.MINIMUM_SCALE, UI.MAXIMUM_SCALE = 0.6, 1.8
local MOVE_TEXTURE = "Interface\\Cursor\\UI-Cursor-Move"
local GRIP_TEXTURE = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"

---@return number left, number top the window's top-left corner in UIParent units
local function topLeftCorner()
    local scale = mainFrame:GetScale() or 1
    return (mainFrame:GetLeft() or 0) * scale, (mainFrame:GetTop() or 0) * scale
end

-- Anchors the window by its top-left corner (UIParent units) at `scale`, so scaling grows it to the bottom right.
---@param left number
---@param top number
---@param scale number
local function placeWindow(left, top, scale)
    mainFrame:SetScale(scale)
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end

local function savePlacement()
    local left, top = topLeftCorner()
    settings().window = { left = left, top = top, scale = mainFrame:GetScale() or 1 }
end

-- The window's scale with its bottom-right corner under the cursor (top-left stays put), clamped.
---@param left number
---@param top number
---@param cursorX number UIParent units
---@param cursorY number
---@return number
function UI.ScaleForCorner(left, top, cursorX, cursorY)
    local byWidth = (cursorX - left) / STAGE_WIDTH
    local byHeight = (top - cursorY) / (STAGE_HEIGHT + HEADER_HEIGHT)
    return math.max(UI.MINIMUM_SCALE, math.min(UI.MAXIMUM_SCALE, math.max(byWidth, byHeight)))
end

---@return number x, number y the cursor in UIParent units
local function cursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    return (x or 0) / scale, (y or 0) / scale
end

-- The grip (bottom right): drag scales the window (the top-left corner stays), a double click resets the size.
-- The move handle (bottom left): drag moves the window.
local function buildGrip()
    local grip = CreateFrame("Button", nil, mainFrame)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel((tonumber(mainFrame:GetFrameLevel()) or 1) + 20)
    grip:EnableMouse(true)
    grip:RegisterForClicks("LeftButtonUp")
    local texture = grip:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    addon.UIHelpers.SetTextureOr(texture, GRIP_TEXTURE, { ACCENT[1], ACCENT[2], ACCENT[3], 0.8 })
    texture:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    grip.texture = texture
    grip:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        self.left, self.top = topLeftCorner()
        self.dragging = true
        texture:SetVertexColor(1, 1, 1)
    end)
    grip:SetScript("OnMouseUp", function(self)
        if not self.dragging then return end
        self.dragging = false
        texture:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
        savePlacement()
    end)
    grip:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local cursorX, cursorY = cursorPosition()
        placeWindow(self.left, self.top, UI.ScaleForCorner(self.left, self.top, cursorX, cursorY))
    end)
    grip:SetScript("OnDoubleClick", function()
        local left, top = topLeftCorner()
        placeWindow(left, top, 1)
        savePlacement()
    end)
    grip:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Text["Drag: scale. Double-click: reset size."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    parts.grip = grip

    local mover = CreateFrame("Button", nil, mainFrame)
    mover:SetSize(16, 16); mover:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 2, 2)
    mover:SetFrameLevel((tonumber(mainFrame:GetFrameLevel()) or 1) + 20)
    mover:EnableMouse(true); mover:RegisterForDrag("LeftButton")
    local moverTexture = mover:CreateTexture(nil, "OVERLAY")
    moverTexture:SetAllPoints()
    addon.UIHelpers.SetTextureOr(moverTexture, MOVE_TEXTURE, { ACCENT[1], ACCENT[2], ACCENT[3], 0.8 })
    moverTexture:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    mover:SetScript("OnDragStart", function(self)
        self.dragging = true
        moverTexture:SetVertexColor(1, 1, 1)
        mainFrame:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        self.dragging = false
        moverTexture:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
        mainFrame:StopMovingOrSizing()
        savePlacement()
    end)
    mover:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(Text["Drag: move."], 1, 1, 1)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    parts.mover = mover
end

-- A soft-edged dark plate: a solid centre and gradient strips that fade out on every side, so there is no hard frame.
---@param owner table
---@param feather number
---@return table holder whose alpha drives the whole plate
local function softPlate(owner, feather)
    local holder = CreateFrame("Frame", nil, owner)
    holder:SetAllPoints(); holder:SetFrameLevel(math.max(0, (tonumber(owner:GetFrameLevel()) or 1) - 1))
    local centre = holder:CreateTexture(nil, "BACKGROUND")
    centre:SetPoint("TOPLEFT", feather, -feather); centre:SetPoint("BOTTOMRIGHT", -feather, feather)
    centre:SetColorTexture(0.02, 0.02, 0.03, 1)
    local function edge(point1, point2, orientation, solidFirst, horizontal)
        local strip = holder:CreateTexture(nil, "BACKGROUND")
        strip:SetColorTexture(0.02, 0.02, 0.03, 1)
        if horizontal then strip:SetWidth(feather) else strip:SetHeight(feather) end
        strip:SetPoint(point1[1], centre, point1[2], 0, 0); strip:SetPoint(point2[1], centre, point2[2], 0, 0)
        local ok = pcall(function()
            strip:SetGradient(orientation, CreateColor(0.02, 0.02, 0.03, solidFirst and 1 or 0), CreateColor(0.02, 0.02, 0.03, solidFirst and 0 or 1))
        end)
        if not ok then
            ok = pcall(strip.SetGradientAlpha, strip, orientation, 0.02, 0.02, 0.03, solidFirst and 1 or 0, 0.02, 0.02, 0.03, solidFirst and 0 or 1)
        end
        if not ok then strip:SetAlpha(0.5) end
    end
    -- gradients run min -> max (left -> right, bottom -> top)
    edge({ "BOTTOMLEFT", "TOPLEFT" }, { "BOTTOMRIGHT", "TOPRIGHT" }, "VERTICAL", true, false)     -- top
    edge({ "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" }, "VERTICAL", false, false)    -- bottom
    edge({ "TOPRIGHT", "TOPLEFT" }, { "BOTTOMRIGHT", "BOTTOMLEFT" }, "HORIZONTAL", false, true)   -- left
    edge({ "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, "HORIZONTAL", true, true)    -- right
    return holder
end

---@param open boolean
---@param animate boolean
local function setSidebar(open, animate)
    local sidebar = parts.sidebar
    settings().sidebarOpen = open
    parts.sidebarButton:SetSelected(open)
    parts.sidebarArrow:SetTexCoord(open and 1 or 0, open and 0 or 1, 0, 1)
    local function place(progress)
        sidebar:ClearAllPoints()
        sidebar:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", -24 + 30 * progress, 0)
        sidebar:SetAlpha(progress)
    end
    if not animate then
        addon.Animate.FinishTween("sidebar")
        place(open and 1 or 0); sidebar:SetShown(open)
        return
    end
    sidebar:Show()
    addon.Animate.Tween("sidebar", 0.28, function(elapsed)
        local progress = elapsed / 0.28
        local eased = 1 - (1 - progress) ^ 3
        place(open and eased or 1 - eased)
    end, function()
        place(open and 1 or 0)
        sidebar:SetShown(open)
    end)
    if open and addon.GamesTab then addon.GamesTab.RevealBoard() end
end

function UI.ToggleSidebar()
    if not mainFrame then return end
    setSidebar(not parts.sidebar:IsShown() or not settings().sidebarOpen, true)
end

local function build()
    local frameName = addon.FRAME_PREFIX .. "Frame"
    mainFrame = CreateFrame("Frame", frameName, UIParent)
    mainFrame:SetSize(STAGE_WIDTH, STAGE_HEIGHT + HEADER_HEIGHT)
    -- the development window is offset so both can be open
    mainFrame:SetPoint("CENTER", addon.IS_DEVELOPMENT_BUILD and -140 or -180, addon.IS_DEVELOPMENT_BUILD and -40 or 0)
    mainFrame:SetMovable(true); mainFrame:SetClampedToScreen(true)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:Hide()
    table.insert(UISpecialFrames, frameName)

    parts.backdrop = softPlate(mainFrame, 18)
    parts.backdropAlpha = BACKDROP_IDLE; parts.backdrop:SetAlpha(BACKDROP_IDLE)

    -- header: the drag handle (the only part of the backdrop that takes the mouse)
    local header = CreateFrame("Frame", nil, mainFrame)
    header:SetHeight(HEADER_HEIGHT); header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    header:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing(); savePlacement() end)
    parts.header, parts.headerAlpha = header, HEADER_IDLE
    header:SetAlpha(HEADER_IDLE)
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1); divider:SetPoint("BOTTOMLEFT", 8, 0); divider:SetPoint("BOTTOMRIGHT", -8, 0)
    divider:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)

    local closeButton = createFlatButton(header, "x", 20, 18, function() UI.Toggle() end)
    closeButton:SetPoint("RIGHT", -2, 0)
    -- the leaderboard toggle: an arrow only (it points to the sidebar when closed, back when open); the name is its tooltip
    parts.sidebarButton = createFlatButton(header, "", 20, 18, function() UI.ToggleSidebar() end)
    parts.sidebarButton:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
    local arrow = parts.sidebarButton:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16); arrow:SetPoint("CENTER", 0, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    parts.sidebarArrow = arrow
    parts.sidebarButton:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Text["Leaderboard"])
        GameTooltip:Show()
    end)
    parts.sidebarButton:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local stage = CreateFrame("Frame", nil, mainFrame)
    stage:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - 4); stage:SetPoint("BOTTOMRIGHT")
    parts.stage = stage
    mainFrame.content = stage

    -- the leaderboard sidebar, outside the window's right edge
    local sidebar = CreateFrame("Frame", nil, mainFrame)
    sidebar:SetSize(SIDEBAR_WIDTH, SIDEBAR_HEIGHT)
    sidebar:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 6, 0)
    sidebar:Hide()
    parts.sidebar = sidebar
    parts.sidebarBackdrop = softPlate(sidebar, 14)
    parts.sidebarAlpha = SIDEBAR_IDLE; parts.sidebarBackdrop:SetAlpha(SIDEBAR_IDLE)
    local sidebarContent = CreateFrame("Frame", nil, sidebar)
    sidebarContent:SetPoint("TOPLEFT", 12, -10); sidebarContent:SetPoint("BOTTOMRIGHT", -8, 8)
    parts.sidebarContent = sidebarContent

    mainFrame:SetScript("OnShow", function() addon.Events.Fire("WINDOW_OPENED"); UI.Refresh() end)
    mainFrame:SetScript("OnUpdate", function(_, elapsedSeconds) updateHover(elapsedSeconds) end)

    addon.Log.Protected("window.games", "building the games failed", addon.GamesTab.Build, stage, sidebarContent, header)
    addon.Log.Protected("window.grip", "building the window grip failed", buildGrip)
    -- the saved position and scale (a bad saved value is ignored)
    local saved = settings().window
    if type(saved) == "table" and type(saved.left) == "number" and type(saved.top) == "number" and type(saved.scale) == "number" then
        placeWindow(saved.left, saved.top, math.max(UI.MINIMUM_SCALE, math.min(UI.MAXIMUM_SCALE, saved.scale)))
    end
    setSidebar(settings().sidebarOpen and true or false, false)
    addon.Events.On("DATA_CHANGED", UI.Refresh)
end

-- Opens with a short fade in and closes with a fade out. A tween that is still running finishes first.
function UI.Toggle()
    if not mainFrame then build() end
    local Animate = addon.Animate
    if mainFrame:IsShown() and not UI.closing then
        UI.closing = true
        local fromAlpha = mainFrame:GetAlpha() or 1
        Animate.Tween("window", 0.18, function(elapsed) mainFrame:SetAlpha(fromAlpha * (1 - elapsed / 0.18)) end,
            function() UI.closing = false; mainFrame:Hide(); mainFrame:SetAlpha(1) end)
        return
    end
    UI.closing = false
    mainFrame:SetAlpha(0)
    mainFrame:Show()
    Animate.Tween("window", 0.22, function(elapsed) mainFrame:SetAlpha(elapsed / 0.22) end, function() mainFrame:SetAlpha(1) end)
end

---@return boolean
function UI.IsShown() return (mainFrame and mainFrame:IsShown() and not UI.closing) and true or false end

-- Redraws the leaderboards (GamesTab defers it while a game animates).
function UI.Refresh()
    if mainFrame and mainFrame:IsShown() and addon.GamesTab then addon.GamesTab.Refresh() end
end

------------------------------------------------------------------ minimap button

---@type table|nil
UI.minimapButton = nil

-- A coin on the minimap (LibGuildSync's button, shared with TalentShare): click opens the window, right-drag moves it.
-- Its default spot is away from TalentShare's (215 degrees; dev builds 245) so the two never cover each other.
function UI.BuildMinimapButton()
    if UI.minimapButton or not Minimap then return end
    UI.minimapButton = Widgets.CreateMinimapButton({
        name = addon.FRAME_PREFIX .. "MinimapButton",
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        defaultAngle = addon.IS_DEVELOPMENT_BUILD and 165 or 185,
        getAngle = function() return addon.db and addon.db.ui.minimapAngle end,
        setAngle = function(degrees) if addon.db then addon.db.ui.minimapAngle = degrees end end,
        onClick = function() UI.Toggle() end,
        onTooltip = function(tooltip)
            tooltip:SetText(addon.TITLE)
            tooltip:AddLine(Text["Coin flip, slots, survivor and AZEcaught"], 1, 1, 1)
            addon.Log.Protected("caught.tooltip", "the AZEcaught tooltip failed", UI.AddCompanionTooltip, tooltip)
            tooltip:AddLine(Text["Click: open window. Right-drag: move."], 0.7, 0.7, 0.7)
        end,
    })
    UI.RefreshMinimapBadge()
end

------------------------------------------------------------------ AZEcaught on the minimap button (feature 018, R14)

local ZONE_RANK = { ok = 0, needy = 1, critical = 2, empty = 2 }

-- How many needs want care now (needy or worse) and the worst zone rank (0 ok, 1 needy, 2 critical).
---@return integer count
---@return integer worst
function UI.CompanionAlerts()
    local companion = addon.db and addon.AzeCaught.Active()
    if not companion then return 0, 0 end
    local count, worst = 0, 0
    for _, need in ipairs(addon.AzeCaught.NEEDS) do
        local rank = ZONE_RANK[addon.AzeCaught.ZoneOf(companion, need)] or 0
        if rank > 0 then count = count + 1 end
        if rank > worst then worst = rank end
    end
    return count, worst
end

-- The badge shows the number of needs that want care (red when one is critical); off with /gg notify off.
function UI.RefreshMinimapBadge()
    local button = UI.minimapButton
    if not button or not button.badge then return end
    local count, worst = UI.CompanionAlerts()
    local notify = addon.AzeCaught.State().notify
    if count > 0 and notify then
        button.badgeText:SetText(tostring(count))
        button.badge:Show()
        button.icon:SetVertexColor(1, worst >= 2 and 0.45 or 0.85, worst >= 2 and 0.45 or 0.6)
    else
        button.badge:Hide()
        button.icon:SetVertexColor(1, 1, 1)
    end
end

---@param seconds number
---@return string
local function minutesText(seconds)
    if seconds == math.huge then return "-" end
    local minutes = math.max(0, math.floor(seconds / 60))
    if minutes >= 60 then return addon.Locale.Format(Text["{h}h {m}m"], { h = math.floor(minutes / 60), m = minutes % 60 }) end
    return addon.Locale.Format(Text["{m}m"], { m = minutes })
end

-- The companion's needs and schedule in the minimap tooltip.
---@param tooltip table
function UI.AddCompanionTooltip(tooltip)
    local AzeCaught = addon.AzeCaught
    local companion = addon.db and AzeCaught.Active()
    local Format = addon.Locale.Format
    tooltip:AddLine(" ")
    if not companion then
        tooltip:AddLine(Text["AZEcaught: no companion"], 0.7, 0.7, 0.7)
        return
    end
    tooltip:AddDoubleLine("AZEcaught: " .. addon.Utility.Escape(companion.n), Format(Text["{hearts} hearts"], { hearts = companion.hearts }),
        1, 0.82, 0, 1, 0.3, 0.4)
    local labels = { hunger = Text["Food"], thirst = Text["Water"], affection = Text["Petting"], energy = Text["Energy"] }
    local profile = AzeCaught.ProfileOf(companion)
    local colors = { ok = { 0.3, 0.85, 0.35 }, needy = { 1, 0.75, 0.15 }, critical = { 1, 0.25, 0.2 }, empty = { 1, 0.1, 0.1 } }
    for _, need in ipairs(AzeCaught.NEEDS) do
        local zone = AzeCaught.ZoneOf(companion, need)
        local seconds = AzeCaught.SecondsUntilNeedy(companion, need)
        local color = colors[zone]
        tooltip:AddDoubleLine(("%s %d%%"):format(labels[need], math.floor(companion[need] + 0.5)),
            seconds == math.huge and Text["never"] or seconds > 0 and Format(Text["care in {time}"], { time = minutesText(seconds) }) or Text["now"],
            color[1], color[2], color[3], 1, 1, 1)
    end
    if companion.asleep then tooltip:AddLine(Format(Text["Asleep, wakes in {time}"], { time = minutesText(companion.asleep) }), 0.65, 0.5, 1) end
    tooltip:AddLine(Format(Text["Water every {water}, food every {food}, petting every {pet}, sleep {sleep} every {awake} (play time)."],
        { water = minutesText(profile.intervals.thirst or math.huge), food = minutesText(profile.intervals.hunger or math.huge),
          pet = minutesText(profile.intervals.affection or math.huge), sleep = minutesText(AzeCaught.SLEEP_DURATION),
          awake = minutesText(profile.intervals.energy or math.huge) }), 0.7, 0.7, 0.7, true)
    if not AzeCaught.State().notify then tooltip:AddLine(Text["Reminders are off (/gg notify on)."], 0.7, 0.7, 0.7) end
end

addon.Events.On("CAUGHT_CHANGED", function() UI.RefreshMinimapBadge() end)
