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

local STAGE_WIDTH, STAGE_HEIGHT = 300, 376
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

-- A yes/no decision as an icon: "accept" is a green tick, "decline" a red X, on a dark plate tinted green/red on hover; the word stays in
-- the tooltip. Disabled: grey. :SetLabel only changes the tooltip (callers that relabel buttons keep working).
local ICON_BUTTON = {
    accept = { texture = "Interface\\RaidFrame\\ReadyCheck-Ready", color = { 0.25, 0.85, 0.3 } },
    decline = { texture = "Interface\\RaidFrame\\ReadyCheck-NotReady", color = { 0.95, 0.3, 0.25 } },
    -- dev build tools: add a debug thing / make a timer run out / the fake arena events
    debug = { texture = "Interface\\Icons\\Trade_Engineering", color = { 1, 0.55, 0.15 }, crop = true, dev = true },
    skip = { texture = "Interface\\Icons\\INV_Misc_PocketWatch_01", color = { 0.35, 0.75, 1 }, crop = true, dev = true },
    crowd = { texture = "Interface\\Icons\\INV_Misc_Coin_01", color = { 1, 0.82, 0.2 }, crop = true, dev = true },
    latebet = { texture = "Interface\\Icons\\INV_Misc_PocketWatch_02", color = { 0.8, 0.5, 0.2 }, crop = true, dev = true },
    members = { texture = "Interface\\Icons\\Spell_Holy_PrayerOfHealing", color = { 0.6, 0.8, 1 }, crop = true, dev = true },
    devaccept = { texture = "Interface\\RaidFrame\\ReadyCheck-Ready", color = { 0.25, 0.85, 0.3 }, dev = true },
    devdecline = { texture = "Interface\\RaidFrame\\ReadyCheck-NotReady", color = { 0.95, 0.3, 0.25 }, dev = true },
    expire = { texture = "Interface\\Icons\\Spell_Shadow_DeathCoil", color = { 0.6, 0.3, 0.8 }, crop = true, dev = true },
    reveal = { texture = "Interface\\Icons\\INV_Misc_Spyglass_03", color = { 0.4, 0.9, 0.9 }, crop = true, dev = true },
    clear = { texture = "Interface\\Icons\\Spell_Holy_DispelMagic", color = { 0.9, 0.9, 0.9 }, crop = true, dev = true },
}
---@param parent table
---@param kind string a key of ICON_BUTTON
---@param size number
---@param tooltip string
---@param onClick? function
---@return table
local function createIconButton(parent, kind, size, tooltip, onClick)
    local look = ICON_BUTTON[kind] or ICON_BUTTON.accept
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.kind, button.tooltip = kind, tooltip
    button.plate = button:CreateTexture(nil, "BACKGROUND"); button.plate:SetAllPoints()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER"); button.icon:SetSize(size - 4, size - 4)
    addon.UIHelpers.SetTextureOr(button.icon, look.texture, look.color)
    if look.crop and button.icon.SetTexCoord then button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    if look.dev then   -- dev tools wear an orange "DEV" corner tag
        button.tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.tag:SetPoint("BOTTOMRIGHT", 3, -3); button.tag:SetText("|cffff9020dev|r")
    end
    local function paint(self)
        local enabled = self:IsEnabled()
        local color = look.color
        if self.hovered and enabled then
            self.plate:SetColorTexture(color[1] * 0.45, color[2] * 0.45, color[3] * 0.45, 0.8)
        else
            self.plate:SetColorTexture(0, 0, 0, enabled and 0.45 or 0.25)
        end
        if self.icon.SetDesaturated then self.icon:SetDesaturated(not enabled) end
        self.icon:SetAlpha(enabled and 1 or 0.4)
    end
    function button:SetLabel(text) self.tooltip = text end
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        self.hovered = true; paint(self)
        if GameTooltip and self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tooltip, look.color[1], look.color[2], look.color[3])
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self) self.hovered = false; paint(self); if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnEnable", paint)
    button:SetScript("OnDisable", paint)
    paint(button)
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

local fitFonts = setmetatable({}, { __mode = "k" })   -- font string -> its own font { file, size, flags }

-- One line of text that fits its font string's width (long names break the layout): the font
-- shrinks down to `minimumScale` (default 0.75) of its size, and what still does not fit ends in "..." (no wrapping).
-- The font string needs a width. Clients without GetFont/SetFont just get the text, cut by the width.
---@param fontString table
---@param text string
---@param minimumScale? number
local function fitText(fontString, text, minimumScale)
    if fontString.SetWordWrap then fontString:SetWordWrap(false) end
    if fontString.SetMaxLines then pcall(fontString.SetMaxLines, fontString, 1) end
    if fontString.GetFont and fontString.SetFont and not fitFonts[fontString] then
        local font, size, flags = fontString:GetFont()
        if type(font) == "string" and type(size) == "number" then fitFonts[fontString] = { font, size, flags } end
    end
    local base = fitFonts[fontString]
    if base then fontString:SetFont(base[1], base[2], base[3]) end
    fontString:SetText(text)
    if not base then return end
    local width = fontString:GetWidth()
    local measure = fontString.GetUnboundedStringWidth or fontString.GetStringWidth
    local needed = measure(fontString)
    if type(width) == "number" and width > 0 and type(needed) == "number" and needed > width then
        local scale = math.max(minimumScale or 0.75, width / needed)
        fontString:SetFont(base[1], math.max(6, math.floor(base[2] * scale)), base[3])
        fontString:SetText(text)
    end
end

-- The widget helpers the UI files use: LibGuildSync's lists and texts plus the flat buttons and boxes above. TimeAgo
-- uses this addon's texts (Text["just now"], Text["{n}m ago"], Text["{n}h ago"], Text["{n}d ago"]).
UI.Widgets = { ROW_HEIGHT = Widgets.ROW_HEIGHT, FitText = fitText, CreateButton = createFlatButton, MakePrimary = makePrimary, CreateIconButton = createIconButton,
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
    local scale = tonumber(mainFrame:GetScale()) or 1
    return (tonumber(mainFrame:GetLeft()) or 0) * scale, (tonumber(mainFrame:GetTop()) or 0) * scale
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

    -- the switch to the minimal pet view, at the top-left corner (the pet view has its switch at the same spot)
    local switchButton = createFlatButton(header, "", 20, 18, function() UI.SetMode("minimal") end)
    switchButton:SetPoint("LEFT", 2, 0)
    local switchIcon = switchButton:CreateTexture(nil, "OVERLAY")
    switchIcon:SetSize(18, 18); switchIcon:SetPoint("CENTER", 0, 0)
    addon.UIHelpers.SetTextureOr(switchIcon, addon.PetView.MINIMAL_VIEW_ICON, { ACCENT[1], ACCENT[2], ACCENT[3] })
    switchButton:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(Text["Minimal view"])
        GameTooltip:Show()
    end)
    switchButton:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    parts.switchButton = switchButton
    header.firstButtonOffset = 26

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

---@return boolean
local function fullShown() return (mainFrame and mainFrame:IsShown() and not UI.closing) and true or false end

-- The full window closes with a short fade out (or at once).
---@param animate boolean
local function hideFull(animate)
    if not mainFrame or not mainFrame:IsShown() then return end
    if not animate then
        addon.Animate.FinishTween("window")
        UI.closing = false; mainFrame:Hide(); mainFrame:SetAlpha(1)
        return
    end
    UI.closing = true
    local fromAlpha = mainFrame:GetAlpha() or 1
    addon.Animate.Tween("window", 0.18, function(elapsed) mainFrame:SetAlpha(fromAlpha * (1 - elapsed / 0.18)) end,
        function() UI.closing = false; mainFrame:Hide(); mainFrame:SetAlpha(1) end)
end

-- The full window opens with a short fade in; with (left, top) its top-left corner goes there first.
---@param left? number
---@param top? number
local function showFull(left, top)
    if not mainFrame then build() end
    if left and top then
        placeWindow(left, top, tonumber(mainFrame:GetScale()) or 1)
        savePlacement()
    end
    if fullShown() then return end
    UI.closing = false
    mainFrame:SetAlpha(0)
    mainFrame:Show()
    addon.Animate.Tween("window", 0.22, function(elapsed) mainFrame:SetAlpha(elapsed / 0.22) end, function() mainFrame:SetAlpha(1) end)
end

-- Switches between the full window and the minimal pet view. The new one opens with its top-left corner where the
-- other one had it, so the switch icon stays under the mouse.
---@param mode "full"|"minimal"
function UI.SetMode(mode)
    local PetView = addon.PetView
    mode = mode == "minimal" and "minimal" or "full"
    addon.UIHelpers.Settings().petView = addon.UIHelpers.Settings().petView or {}
    addon.UIHelpers.Settings().petView.mode = mode
    local left, top
    if mode == "minimal" then
        if fullShown() then left, top = topLeftCorner() end
        hideFull(false)
        PetView.Show(left, top)
    else
        if PetView.IsShown() then left, top = PetView.TopLeft()
        elseif PetView.state.hiddenByCombat then left, top = PetView.Settings().left, PetView.Settings().top end
        PetView.Hide(false)
        showFull(left, top)
    end
    addon.AzeCaught.Journal("DEBUG", "petView.mode", "the window mode switched", { mode = mode })
end

-- The full window (commands that open a game or view): from the pet view it switches, else it opens.
function UI.ShowFull()
    if not fullShown() then UI.SetMode("full") end
end

-- /gg and the minimap button: closes whichever view is open, else opens the start mode of the options.
function UI.Toggle()
    local PetView = addon.PetView
    if fullShown() or PetView.IsShown() or PetView.state.hiddenByCombat then
        hideFull(true)
        PetView.Hide(true)
        return
    end
    UI.SetMode(PetView.Settings().startMode)
end

---@return boolean the full window or the pet view is open
function UI.IsShown() return fullShown() or addon.PetView.IsShown() end

-- Redraws the leaderboards (GamesTab defers it while a game animates).
function UI.Refresh()
    if mainFrame and mainFrame:IsShown() and addon.GamesTab then addon.GamesTab.Refresh() end
end

------------------------------------------------------------------ minimap button

---@type table|nil
UI.minimapButton = nil

-- A coin on the minimap (LibDBIcon's button via Widgets.CreateMinimapButton, shared with ProfessionShare): click opens
-- the window, drag moves it.
function UI.BuildMinimapButton()
    if UI.minimapButton or not Minimap then return end
    addon.db.ui.minimapIcon = addon.db.ui.minimapIcon or {}
    UI.minimapButton = Widgets.CreateMinimapButton({
        name = addon.FRAME_PREFIX,
        label = addon.TITLE,
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        settings = addon.db.ui.minimapIcon,
        defaultPosition = addon.IS_DEVELOPMENT_BUILD and 165 or 185,   -- away from ProfessionShare's button (215, dev 245)
        onClick = function() UI.Toggle() end,
        onTooltip = function(tooltip)
            tooltip:SetText(addon.TITLE)
            tooltip:AddLine(Text["Coin flip, slots, survivor and AZEcaught"], 1, 1, 1)
            addon.Log.Protected("caught.tooltip", "the AZEcaught tooltip failed", UI.AddCompanionTooltip, tooltip)
            tooltip:AddLine(Text["Click: open window. Drag: move."], 0.7, 0.7, 0.7)
        end,
    })
    UI.RefreshMinimapBadge()
end

------------------------------------------------------------------ AZEcaught on the minimap button

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
    tooltip:AddDoubleLine("AZEcaught: " .. addon.Utility.Escape(addon.AzeCaught.ShownName(companion)), Format(Text["{hearts} hearts"], { hearts = companion.hearts }),
        1, 0.82, 0, 1, 0.3, 0.4)
    local labels = { hunger = Text["Food"], thirst = Text["Water"], affection = Text["Petting"], energy = Text["Energy"] }
    local profile = AzeCaught.ProfileOf(companion)
    local colors = { ok = { 0.3, 0.85, 0.35 }, needy = { 1, 0.75, 0.15 }, critical = { 1, 0.25, 0.2 }, empty = { 1, 0.1, 0.1 } }
    for _, need in ipairs(AzeCaught.NEEDS) do
        local zone = AzeCaught.ZoneOf(companion, need)
        local seconds = AzeCaught.SecondsUntilNeedy(companion, need)
        local color = colors[zone]
        tooltip:AddDoubleLine(("%s %d%%"):format(labels[need], math.floor(companion[need] + 0.5)),
            seconds == math.huge and Text["never"] or seconds > 0 and Format(Text["care in {time}"], { time = addon.Model.Duration(seconds) }) or Text["now"],
            color[1], color[2], color[3], 1, 1, 1)
    end
    if companion.asleep then tooltip:AddLine(Format(Text["Asleep, wakes in {time}"], { time = addon.Model.Duration(companion.asleep) }), 0.65, 0.5, 1) end
    tooltip:AddLine(Format(Text["Water every {water}, food every {food}, petting every {pet}, sleep {sleep} every {awake} (play time)."],
        { water = addon.Model.Duration(profile.intervals.thirst or math.huge), food = addon.Model.Duration(profile.intervals.hunger or math.huge),
          pet = addon.Model.Duration(profile.intervals.affection or math.huge), sleep = addon.Model.Duration(AzeCaught.SLEEP_DURATION),
          awake = addon.Model.Duration(profile.intervals.energy or math.huge) }), 0.7, 0.7, 0.7, true)
    if not AzeCaught.State().notify then tooltip:AddLine(Text["Reminders are off (/gg notify on)."], 0.7, 0.7, 0.7) end
end

addon.Events.On("CAUGHT_CHANGED", function() UI.RefreshMinimapBadge() end)
