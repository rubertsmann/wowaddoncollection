-- LibGuildSync: plain-frame window helpers (no secure templates, so they never taint and work in combat).
local lib = LibStub("LibGuildSync-1.0")
local Widgets = lib:Module("Widgets", 2)
if not Widgets then return end

Widgets.ROW_HEIGHT = 20

---@param parent table
---@param fontObject? string
---@param justify? string
---@return table fontString
function Widgets.CreateFontString(parent, fontObject, justify)
    local fontString = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    fontString:SetJustifyH(justify or "LEFT")
    return fontString
end

-- Buttons grow to fit their label (translations are often longer than English); minimumWidth is the smallest width.
---@param buttonFrame table
---@param label string
function Widgets.SetButtonLabel(buttonFrame, label)
    buttonFrame:SetText(label)
    local labelFontString = buttonFrame.GetFontString and buttonFrame:GetFontString()
    if labelFontString and buttonFrame.minimumWidth then
        buttonFrame:SetWidth(math.max(buttonFrame.minimumWidth, math.ceil(labelFontString:GetStringWidth()) + 24))
    end
end

---@param parent table
---@param label string
---@param minimumWidth number
---@param height? number
---@param onClick? function
---@return table
function Widgets.CreateButton(parent, label, minimumWidth, height, onClick)
    local buttonFrame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    buttonFrame:SetSize(minimumWidth, height or 22)
    buttonFrame.minimumWidth = minimumWidth
    buttonFrame.SetLabel = Widgets.SetButtonLabel
    buttonFrame:SetLabel(label)
    buttonFrame:SetScript("OnClick", onClick)
    return buttonFrame
end

-- scrolling list of pooled rows with mouse wheel + slider
---@param parent table
---@param width number
---@param height number
---@param createRow fun(list: table): table
---@param fillRow fun(row: table, entry: any)
---@return table list with :SetData(entries) and :Refresh()
function Widgets.CreateScrollList(parent, width, height, createRow, fillRow)
    local rowHeight = Widgets.ROW_HEIGHT
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, height)
    local visibleRowCount = math.floor(height / rowHeight)
    list.rows, list.entries, list.offset = {}, {}, 0
    for rowIndex = 1, visibleRowCount do
        local row = createRow(list)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(rowIndex - 1) * rowHeight)
        row:SetSize(width - 16, rowHeight)
        list.rows[rowIndex] = row
    end
    local slider = CreateFrame("Slider", nil, list)
    slider:SetOrientation("VERTICAL")
    slider:SetSize(12, height)
    slider:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    local sliderBackground = slider:CreateTexture(nil, "BACKGROUND"); sliderBackground:SetAllPoints(); sliderBackground:SetColorTexture(0, 0, 0, 0.35)
    local sliderThumb = slider:CreateTexture(nil, "OVERLAY"); sliderThumb:SetSize(10, 28); sliderThumb:SetColorTexture(0.7, 0.7, 0.7, 0.8)
    slider:SetThumbTexture(sliderThumb)
    slider:SetMinMaxValues(0, 0); slider:SetValueStep(1); slider:SetValue(0)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= list.offset then list.offset = value; list:Refresh() end
    end)
    list.slider = slider
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, wheelDelta)
        local maximumOffset = math.max(0, #self.entries - visibleRowCount)
        self.offset = math.max(0, math.min(maximumOffset, self.offset - wheelDelta * 3))
        slider:SetValue(self.offset)
        self:Refresh()
    end)
    function list:SetData(entries)
        self.entries = entries
        local maximumOffset = math.max(0, #entries - visibleRowCount)
        if self.offset > maximumOffset then self.offset = maximumOffset end
        slider:SetMinMaxValues(0, maximumOffset)
        slider:SetValue(self.offset)
        self:Refresh()
    end
    function list:Refresh()
        for rowIndex, row in ipairs(self.rows) do
            local entry = self.entries[self.offset + rowIndex]
            if entry then row.entry = entry; fillRow(row, entry); row:Show() else row.entry = nil; row:Hide() end
        end
    end
    return list
end

-- A row with hover/selection highlight, an icon (its own button: row.onIconEnter(self) / row.onIconClick()), a label and
-- a right-aligned text.
---@param list table
---@return table row
function Widgets.CreateSelectableRow(list)
    local rowHeight = Widgets.ROW_HEIGHT
    local row = CreateFrame("Button", nil, list)
    local hoverHighlight = row:CreateTexture(nil, "HIGHLIGHT"); hoverHighlight:SetAllPoints(); hoverHighlight:SetColorTexture(1, 1, 1, 0.1)
    row.selectionHighlight = row:CreateTexture(nil, "BACKGROUND"); row.selectionHighlight:SetAllPoints()
    row.selectionHighlight:SetColorTexture(0.2, 0.5, 1, 0.3); row.selectionHighlight:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(rowHeight - 2, rowHeight - 2); row.icon:SetPoint("LEFT", 2, 0)
    row.label = Widgets.CreateFontString(row, "GameFontHighlightSmall"); row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0); row.label:SetPoint("RIGHT", -70, 0)
    row.rightText = Widgets.CreateFontString(row, "GameFontNormalSmall", "RIGHT"); row.rightText:SetPoint("RIGHT", -2, 0)
    local iconButton = CreateFrame("Button", nil, row)
    iconButton:SetAllPoints(row.icon)
    iconButton:SetScript("OnEnter", function(self) if row.onIconEnter then row.onIconEnter(self) end end)
    iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    iconButton:SetScript("OnClick", function() if row.onIconClick then row.onIconClick() else row:Click() end end)
    row.iconButton = iconButton
    return row
end

-- a dialog frame with the inset template, or a backdrop frame on clients without it
---@param frameName string|nil
---@param log? table a Log instance (notes the fallback at DEBUG)
---@return table
function Widgets.CreateDialogFrame(frameName, log)
    local ok, dialogFrame = pcall(CreateFrame, "Frame", frameName, UIParent, "BasicFrameTemplateWithInset")
    if ok and dialogFrame then return dialogFrame end
    if log then log.Debug("window.frame", "BasicFrameTemplateWithInset is missing; a backdrop frame is used", { frame = frameName }) end
    dialogFrame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    dialogFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    local closeButton = CreateFrame("Button", nil, dialogFrame, "UIPanelCloseButton"); closeButton:SetPoint("TOPRIGHT", -2, -2)
    return dialogFrame
end

-- "just now" / "5m ago" / "3h ago" / "2d ago", with the addon's own translations of those four templates.
---@param timestamp integer|nil
---@param Text table<string, string> the addon's text table (keys "just now", "{n}m ago", "{n}h ago", "{n}d ago")
---@return string
function Widgets.TimeAgo(timestamp, Text)
    local Format = lib.Locale.Format
    local secondsAgo = lib.Utility.Now() - (timestamp or 0)
    if secondsAgo < 90 then return Text["just now"] end
    if secondsAgo < 5400 then return Format(Text["{n}m ago"], { n = math.floor(secondsAgo / 60) }) end
    if secondsAgo < 129600 then return Format(Text["{n}h ago"], { n = math.floor(secondsAgo / 3600) }) end
    return Format(Text["{n}d ago"], { n = math.floor(secondsAgo / 86400) })
end

---@class MinimapButtonOptions
---@field name? string global frame name
---@field icon string texture path
---@field defaultAngle number degrees around the minimap (0 = right, 90 = top)
---@field getAngle fun(): number|nil the saved angle (nil: defaultAngle)
---@field setAngle fun(degrees: number) saves the angle while the button is dragged
---@field onClick fun(button: table, mouseButton: string)
---@field onTooltip? fun(tooltip: table) fills GameTooltip (already owned by the button)

-- A round minimap button: left click runs onClick, right-drag moves it around the minimap (the angle is saved by the
-- caller). It has a hidden red badge (button.badge, button.badgeText) for a counter.
---@param options MinimapButtonOptions
---@return table button with .icon, .badge, .badgeText and :Place()
function Widgets.CreateMinimapButton(options)
    local arcTangent2 = math.atan2 or math.atan
    local buttonFrame = CreateFrame("Button", options.name, Minimap)
    buttonFrame:SetSize(31, 31); buttonFrame:SetFrameStrata("MEDIUM"); buttonFrame:SetFrameLevel(8)
    local icon = buttonFrame:CreateTexture(nil, "BACKGROUND"); icon:SetSize(20, 20); icon:SetPoint("CENTER")
    icon:SetTexture(options.icon)
    buttonFrame.icon = icon
    local border = buttonFrame:CreateTexture(nil, "OVERLAY"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local badge = CreateFrame("Frame", nil, buttonFrame); badge:SetSize(16, 14); badge:SetPoint("TOPRIGHT", 2, 2)
    badge:SetFrameLevel(buttonFrame:GetFrameLevel() + 2)
    local badgeBackground = badge:CreateTexture(nil, "BACKGROUND"); badgeBackground:SetAllPoints(); badgeBackground:SetColorTexture(0.75, 0.05, 0.05, 0.95)
    buttonFrame.badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); buttonFrame.badgeText:SetPoint("CENTER", 0, 0)
    buttonFrame.badge = badge
    badge:Hide()
    function buttonFrame:Place()
        local angleRadians = math.rad(options.getAngle() or options.defaultAngle)
        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", math.cos(angleRadians) * 80, math.sin(angleRadians) * 80)
    end
    buttonFrame:RegisterForClicks("LeftButtonUp")
    buttonFrame:RegisterForDrag("RightButton")
    buttonFrame:SetScript("OnClick", options.onClick)
    buttonFrame:SetScript("OnEnter", function(self)
        if not options.onTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        options.onTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    buttonFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttonFrame:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local minimapCenterX, minimapCenterY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            options.setAngle(math.deg(arcTangent2(cursorY / scale - minimapCenterY, cursorX / scale - minimapCenterX)))
            self:Place()
        end)
    end)
    buttonFrame:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    buttonFrame:Place()
    return buttonFrame
end
