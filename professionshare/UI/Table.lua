local addonName, addon = ...

-- A scroll list that follows its own size (the main window is resizable), plus the column header and
-- table rows of the Recipes tab. Same interface as LibGuildSync's Widgets.CreateScrollList (SetData, Refresh, .offset),
-- which stays fixed-size and untouched (GuildGames uses it). Rows are created on demand when the list grows and hidden
-- when it shrinks. Column positions come from RecipeTable.Layout (pure).
---@class TableModule
local Table = {}
addon.Table = Table

local Widgets = LibStub("LibGuildSync-1.0").Widgets
local ROW_HEIGHT = Widgets.ROW_HEIGHT
local SLIDER_SPACE = 16   -- right edge reserved for the slider
Table.SLIDER_SPACE = SLIDER_SPACE
local HORIZONTAL_BAR_SPACE = 14   -- bottom edge reserved for the horizontal slider while the table is wider than the list
Table.HORIZONTAL_BAR_SPACE = HORIZONTAL_BAR_SPACE
local HORIZONTAL_WHEEL_STEP = 40

---@param value any
---@return number
local function number(value) return (type(value) == "number" and value == value) and value or 0 end

-- The caller anchors the list (two corners), so it scales with its parent. list.onLayout (optional) runs after every
-- size change, before the rows are filled again; it may return the width the rows need. When that is more than the list
-- is wide, the rows are clipped at the list's edge (never drawn over a neighbour) and scroll sideways: a horizontal
-- slider at the bottom, Shift + mouse wheel. list.onHorizontalScroll(offset) (optional) lets a header follow.
---@param parent table
---@param createRow fun(list: table): table
---@param fillRow fun(row: table, entry: any)
---@return table list
function Table.CreateResizableList(parent, createRow, fillRow)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.entries, list.offset, list.visibleRowCount, list.horizontalOffset = {}, {}, 0, 0, 0
    -- the width the rows need while it is more than the list is wide, else nil (a local: a nil field would fall through
    -- to the frame's own methods)
    local tableWidth = nil

    -- rows live on `content`, inside `viewport`, which clips them; content moves left by the horizontal offset
    local viewport = CreateFrame("Frame", nil, list)
    viewport:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -SLIDER_SPACE, 0)
    if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
    local content = CreateFrame("Frame", nil, viewport)
    list.viewport, list.content = viewport, content

    local slider = CreateFrame("Slider", nil, list)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(12)
    slider:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0); slider:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    local sliderBackground = slider:CreateTexture(nil, "BACKGROUND"); sliderBackground:SetAllPoints(); sliderBackground:SetColorTexture(0, 0, 0, 0.35)
    local sliderThumb = slider:CreateTexture(nil, "OVERLAY"); sliderThumb:SetSize(10, 28); sliderThumb:SetColorTexture(0.7, 0.7, 0.7, 0.8)
    slider:SetThumbTexture(sliderThumb)
    slider:SetMinMaxValues(0, 0); slider:SetValueStep(1); slider:SetValue(0)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= list.offset then list.offset = value; list:Refresh() end
    end)
    list.slider = slider

    local horizontalSlider = CreateFrame("Slider", nil, list)
    horizontalSlider:SetOrientation("HORIZONTAL")
    horizontalSlider:SetHeight(12)
    horizontalSlider:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, 0)
    horizontalSlider:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -SLIDER_SPACE, 0)
    local horizontalBackground = horizontalSlider:CreateTexture(nil, "BACKGROUND"); horizontalBackground:SetAllPoints()
    horizontalBackground:SetColorTexture(0, 0, 0, 0.35)
    local horizontalThumb = horizontalSlider:CreateTexture(nil, "OVERLAY"); horizontalThumb:SetSize(40, 10)
    horizontalThumb:SetColorTexture(0.7, 0.7, 0.7, 0.8)
    horizontalSlider:SetThumbTexture(horizontalThumb)
    horizontalSlider:SetMinMaxValues(0, 0); horizontalSlider:SetValueStep(1); horizontalSlider:SetValue(0)
    horizontalSlider:Hide()
    list.horizontalSlider = horizontalSlider

    ---@return number
    local function maximumHorizontalOffset() return math.max(0, number(tableWidth) - list:ContentWidth()) end
    -- moves the rows (and, through onHorizontalScroll, the header) to `offset`, clamped to what the table overhangs
    ---@param offset number
    local function scrollHorizontally(offset)
        offset = math.max(0, math.min(maximumHorizontalOffset(), math.floor(number(offset) + 0.5)))
        list.horizontalOffset = offset
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", viewport, "TOPLEFT", -offset, 0)
        content:SetPoint("BOTTOMLEFT", viewport, "BOTTOMLEFT", -offset, 0)
        if list.onHorizontalScroll then list.onHorizontalScroll(offset) end
    end
    horizontalSlider:SetScript("OnValueChanged", function(_, value)
        if math.floor(value + 0.5) ~= list.horizontalOffset then scrollHorizontally(value) end
    end)

    ---@return integer
    local function maximumOffset() return math.max(0, #list.entries - list.visibleRowCount) end
    -- clamp the offset (a list grown while scrolled to the bottom would show empty rows) and update the slider range
    local function clampOffset()
        local highest = maximumOffset()
        if list.offset > highest then list.offset = highest end
        if list.offset < 0 then list.offset = 0 end
        slider:SetMinMaxValues(0, highest)
        slider:SetValue(list.offset)
    end

    function list:UpdateLayout()
        local viewWidth = self:ContentWidth()
        local neededWidth = self.onLayout and self.onLayout(self)
        -- wider than the list: clip and scroll sideways; otherwise the rows simply span the list
        tableWidth = (type(neededWidth) == "number" and neededWidth > viewWidth + 0.5) and neededWidth or nil
        self.tableWidth = tableWidth or false
        local barSpace = tableWidth and HORIZONTAL_BAR_SPACE or 0
        viewport:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -SLIDER_SPACE, barSpace)
        content:SetWidth(math.max(1, tableWidth or viewWidth))
        horizontalSlider:SetShown(tableWidth ~= nil)
        horizontalSlider:SetMinMaxValues(0, maximumHorizontalOffset())
        scrollHorizontally(self.horizontalOffset)
        horizontalSlider:SetValue(self.horizontalOffset)

        local height = number(self:GetHeight()) - barSpace
        local visibleRowCount = math.max(1, math.floor(height / ROW_HEIGHT))
        for rowIndex = #self.rows + 1, visibleRowCount do
            local row = createRow(content)
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(rowIndex - 1) * ROW_HEIGHT)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            self.rows[rowIndex] = row
        end
        self.visibleRowCount = visibleRowCount
        clampOffset()
        self:Refresh()
    end
    -- the width rows can use (the list without the slider)
    ---@return number
    function list:ContentWidth() return math.max(0, number(self:GetWidth()) - SLIDER_SPACE) end

    list:SetScript("OnSizeChanged", function(self) self.laidOutHeight = self:GetHeight(); self:UpdateLayout() end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, wheelDelta)
        if tableWidth and IsShiftKeyDown and IsShiftKeyDown() then
            scrollHorizontally(self.horizontalOffset - wheelDelta * HORIZONTAL_WHEEL_STEP)
            horizontalSlider:SetValue(self.horizontalOffset)
            return
        end
        self.offset = math.max(0, math.min(maximumOffset(), self.offset - wheelDelta * 3))
        slider:SetValue(self.offset)
        self:Refresh()
    end)
    function list:SetData(entries)
        self.entries = entries
        -- OnSizeChanged may not have fired yet (first show): lay out from the current height
        local height = self:GetHeight()
        if height ~= self.laidOutHeight then self.laidOutHeight = height; self:UpdateLayout() return end
        clampOffset()
        self:Refresh()
    end
    function list:Refresh()
        for rowIndex, row in ipairs(self.rows) do
            local entry = rowIndex <= self.visibleRowCount and self.entries[self.offset + rowIndex]
            if entry then row.entry = entry; fillRow(row, entry); row:Show() else row.entry = nil; row:Hide() end
        end
    end
    return list
end

------------------------------------------------------------------ header + table rows

local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"

-- A row of clickable column titles. header:SetColumns(cells, sort) places one button per cell; onClick(columnKey).
---@param parent table
---@param onClick fun(columnKey: string)
---@return table header
function Table.CreateHeader(parent, onClick)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(18)
    header.buttons, header.horizontalOffset = {}, 0
    -- the columns scroll sideways with the rows (SetHorizontalOffset) and are clipped at the header's edge
    if header.SetClipsChildren then header:SetClipsChildren(true) end
    local background = header:CreateTexture(nil, "BACKGROUND"); background:SetAllPoints(); background:SetColorTexture(1, 1, 1, 0.06)

    ---@param buttonIndex integer
    ---@return table
    local function headerButton(buttonIndex)
        local button = header.buttons[buttonIndex]
        if button then return button end
        button = CreateFrame("Button", nil, header)
        button:SetHeight(18)
        local hoverHighlight = button:CreateTexture(nil, "HIGHLIGHT"); hoverHighlight:SetAllPoints(); hoverHighlight:SetColorTexture(1, 1, 1, 0.1)
        button.label = Widgets.CreateFontString(button, "GameFontNormalSmall")
        button.label:SetWordWrap(false)
        button.arrow = button:CreateTexture(nil, "OVERLAY"); button.arrow:SetSize(9, 8); button.arrow:SetTexture(SORT_ARROW)
        button:SetScript("OnClick", function(self) if self.columnKey then onClick(self.columnKey) end end)
        header.buttons[buttonIndex] = button
        return button
    end

    ---@param cells RecipeCell[]
    ---@param sort RecipeSort
    function header:SetColumns(cells, sort)
        for cellIndex, cell in ipairs(cells) do
            local button = headerButton(cellIndex)
            button.columnKey = cell.key
            button.cellLeft = cell.left
            button:ClearAllPoints(); button:SetPoint("LEFT", self, "LEFT", cell.left - self.horizontalOffset, 0); button:SetWidth(cell.width)
            button.label:ClearAllPoints(); button.arrow:ClearAllPoints()
            button.label:SetText(addon.RecipeTable.ColumnLabel(cell.key))
            button.label:SetJustifyH(cell.column.justify)
            local sorted = sort and sort.key == cell.key
            if cell.column.justify == "RIGHT" then
                button.label:SetPoint("RIGHT", button, "RIGHT", -2, 0)
                button.arrow:SetPoint("RIGHT", button.label, "LEFT", -2, 0)
            else
                button.label:SetPoint("LEFT", button, "LEFT", cellIndex == 1 and (ROW_HEIGHT + 4) or 2, 0)
                button.arrow:SetPoint("LEFT", button.label, "RIGHT", 2, 0)
            end
            button.arrow:SetShown(sorted and true or false)
            -- the texture points down; flipped for ascending
            if sorted and not sort.descending then button.arrow:SetTexCoord(0, 0.5625, 1, 0) else button.arrow:SetTexCoord(0, 0.5625, 0, 1) end
            button:Show()
        end
        for buttonIndex = #cells + 1, #self.buttons do self.buttons[buttonIndex]:Hide() end
    end

    -- shifts the columns left by `offset` (the list's horizontal scroll)
    ---@param offset number
    function header:SetHorizontalOffset(offset)
        self.horizontalOffset = number(offset)
        for _, button in ipairs(self.buttons) do
            if button.cellLeft then
                button:ClearAllPoints(); button:SetPoint("LEFT", self, "LEFT", button.cellLeft - self.horizontalOffset, 0)
            end
        end
    end
    return header
end

-- A selectable row (icon, name label) with one extra font string per optional column, placed by Table.LayoutRow.
---@param list table
---@return table row
function Table.CreateTableRow(list)
    local row = Widgets.CreateSelectableRow(list)
    row.rightText:Hide()
    row.cellTexts = {}
    return row
end

-- Positions the name label and the column texts of a row for `cells`; texts of columns not in `cells` are hidden.
---@param row table
---@param cells RecipeCell[]
function Table.LayoutRow(row, cells)
    if row.layoutCells == cells then return end   -- same layout as last time
    row.layoutCells = cells
    local shownKeys = {}
    for _, cell in ipairs(cells) do
        if cell.key == "name" then
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            row.label:SetWidth(math.max(10, cell.width - ROW_HEIGHT - 6))
            row.label:SetWordWrap(false)
        else
            local cellText = row.cellTexts[cell.key]
            if not cellText then
                cellText = Widgets.CreateFontString(row, "GameFontHighlightSmall")
                cellText:SetWordWrap(false)
                row.cellTexts[cell.key] = cellText
            end
            cellText:ClearAllPoints()
            cellText:SetPoint("LEFT", row, "LEFT", cell.left, 0)
            cellText:SetWidth(cell.width)
            cellText:SetJustifyH(cell.column.justify)
            cellText:Show()
            shownKeys[cell.key] = true
        end
    end
    for columnKey, cellText in pairs(row.cellTexts) do
        if not shownKeys[columnKey] then cellText:Hide() end
    end
end

---@param row table
---@param columnKey string
---@param text string
function Table.SetCell(row, columnKey, text)
    local cellText = row.cellTexts[columnKey]
    if cellText then cellText:SetText(text) end
end
