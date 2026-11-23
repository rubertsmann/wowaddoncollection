-- LibGuildSync: plain-frame window helpers (no secure templates, so they never taint and work in combat).
local lib = LibStub("LibGuildSync-1.0")
local Widgets = lib:Module("Widgets", 6)
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
---@field name string LibDBIcon / LibDataBroker name, unique per addon build ("ProfessionShare", "ProfessionShareDev")
---@field label? string the name shown by button collectors and data displays (default: name)
---@field icon string texture path
---@field settings table saved table LibDBIcon keeps the position and the hide flag in (minimapPos, hide, lock)
---@field defaultPosition? number degrees around the minimap (0 = right, 90 = top) until the player drags it
---@field onClick fun(button: table, mouseButton: string)
---@field onTooltip? fun(tooltip: table) fills the tooltip LibDBIcon passes in

-- A minimap button made by the standard LibDataBroker-1.1 launcher + LibDBIcon-1.0, so button collectors (Leatrix Plus
-- "Combine addon buttons", Minimap Button Bag, ElvUI, ...) and data displays (Titan Panel, ChocolateBar) find it. The
-- addon embeds CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 before this library. LibDBIcon owns placement
-- and dragging (left-drag); this adds a hidden red badge (button.badge, button.badgeText) for a counter.
-- Raises an error when the libraries are missing (a TOC that gained them is only read at a client restart, not /reload).
---@param options MinimapButtonOptions
---@return table|nil button LibDBIcon's button, with .icon, .dataObject, .badge and .badgeText; nil while hidden
function Widgets.CreateMinimapButton(options)
    local dataBroker = LibStub:GetLibrary("LibDataBroker-1.1", true)
    local minimapIcons = LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not dataBroker or not minimapIcons then
        error("LibDataBroker-1.1 or LibDBIcon-1.0 is not loaded: the TOC must list them (after a TOC change restart the client)", 0)
    end
    local dataObject = dataBroker:NewDataObject(options.name, {
        type = "launcher",
        label = options.label or options.name,
        icon = options.icon,
        OnClick = options.onClick,
        OnTooltipShow = options.onTooltip,
    })
    if options.settings and options.settings.minimapPos == nil then options.settings.minimapPos = options.defaultPosition end
    minimapIcons:Register(options.name, dataObject, options.settings)
    -- also an entry in the addon compartment (the numbered button by the minimap) on clients that have one; LibDBIcon
    -- remembers it in settings.showInCompartment
    if minimapIcons.AddButtonToCompartment then minimapIcons:AddButtonToCompartment(options.name) end
    local buttonFrame = minimapIcons:GetMinimapButton(options.name)
    if not buttonFrame then return nil end   -- the player hid it (settings.hide)
    local badge = CreateFrame("Frame", nil, buttonFrame); badge:SetSize(16, 14); badge:SetPoint("TOPRIGHT", 2, 2)
    badge:SetFrameLevel(buttonFrame:GetFrameLevel() + 2)
    local badgeBackground = badge:CreateTexture(nil, "BACKGROUND"); badgeBackground:SetAllPoints(); badgeBackground:SetColorTexture(0.75, 0.05, 0.05, 0.95)
    buttonFrame.badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); buttonFrame.badgeText:SetPoint("CENTER", 0, 0)
    buttonFrame.badge = badge
    badge:Hide()
    return buttonFrame
end
