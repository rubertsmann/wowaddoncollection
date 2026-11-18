local addonName, addon = ...

-- Feature 016: a scroll list that follows its own size (the main window is resizable), plus the column header and
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

-- The caller anchors the list (two corners), so it scales with its parent. list.onLayout (optional) runs after every
-- size change, before the rows are filled again.
---@param parent table
---@param createRow fun(list: table): table
---@param fillRow fun(row: table, entry: any)
---@return table list
function Table.CreateResizableList(parent, createRow, fillRow)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.entries, list.offset, list.visibleRowCount = {}, {}, 0, 0

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
        local height = self:GetHeight() or 0
        local visibleRowCount = math.max(1, math.floor(height / ROW_HEIGHT))
        for rowIndex = #self.rows + 1, visibleRowCount do
            local row = createRow(self)
            row:SetHeight(ROW_HEIGHT)
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(rowIndex - 1) * ROW_HEIGHT)
            row:SetPoint("RIGHT", self, "RIGHT", -SLIDER_SPACE, 0)
            self.rows[rowIndex] = row
        end
        self.visibleRowCount = visibleRowCount
        clampOffset()
        if self.onLayout then self.onLayout(self) end
        self:Refresh()
    end
    -- the width rows can use (the list without the slider)
    ---@return number
    function list:ContentWidth() return math.max(0, (self:GetWidth() or 0) - SLIDER_SPACE) end

    list:SetScript("OnSizeChanged", function(self) self.laidOutHeight = self:GetHeight(); self:UpdateLayout() end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, wheelDelta)
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
    header.buttons = {}
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
            button:ClearAllPoints(); button:SetPoint("LEFT", self, "LEFT", cell.left, 0); button:SetWidth(cell.width)
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
