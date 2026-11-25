local addonName, addon = ...

-- The AZEcaught Shop and Inventory views (two tabs of the AZEcaught panel). Shop: every catalog item by group, with
-- price, owned count and a Buy button. Inventory: the owned items by group with a Use button (a trap is used on the
-- current target). Refusals and results show in the view's status line. Logic: Core/Minigames/Items.lua.
---@class ShopViewModule
local ShopView = {}
addon.ShopView = ShopView

local Items = addon.Items
local Text, Format = addon.Text, addon.Locale.Format
local money = addon.Model.MoneyText

local ROW_HEIGHT, HEADER_HEIGHT, ICON_SIZE = 44, 18, 32
local LIST_TOP, LIST_HEIGHT = -42, 268
local widgets = { shop = {}, inventory = {} }
ShopView.widgets = widgets

---@param reason string|nil
---@return string
local function buyRefusalText(reason)
    if reason == "funds" then return Text["Not enough gold."] end
    if reason == "stack" then return Format(Text["You cannot carry more than {n}."], { n = Items.MAXIMUM_STACK }) end
    if reason == "readonly" then return Text["Saved data is read-only in this session."] end
    return Text["This item is not sold."]
end
ShopView.BuyRefusalText = buyRefusalText

---@param view "shop"|"inventory"
---@param text string
function ShopView.ShowStatus(view, text)
    if widgets[view].status then widgets[view].status:SetText(text) end
end

------------------------------------------------------------------ rows

---@param parent table
---@param view "shop"|"inventory"
---@return table row
local function createRow(parent, view)
    local Widgets = addon.UI.Widgets
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(286, ROW_HEIGHT)
    row:EnableMouse(true)
    local hover = row:CreateTexture(nil, "BACKGROUND"); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.05)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ICON_SIZE, ICON_SIZE); row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = Widgets.CreateFontString(row, "GameFontNormal", "LEFT")
    row.name:SetPoint("TOPLEFT", 42, -4); row.name:SetWidth(196)
    row.effect = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT")
    row.effect:SetPoint("TOPLEFT", 42, -19); row.effect:SetWidth(176); row.effect:SetHeight(22)
    pcall(row.effect.SetJustifyV, row.effect, "TOP")
    row.detail = Widgets.CreateFontString(row, "GameFontHighlightSmall", "RIGHT")
    row.detail:SetPoint("TOPRIGHT", -4, -6); row.detail:SetWidth(60)
    row.action = Widgets.CreateButton(row, view == "shop" and Text["Buy"] or Text["Use"], 62, 18, function()
        if view == "shop" then ShopView.Buy(row.itemID) else ShopView.Use(row.itemID) end
    end)
    row.action:SetPoint("BOTTOMRIGHT", -4, 4)
    row:SetScript("OnEnter", function(self)
        local item = Items.Get(self.itemID)
        if not GameTooltip or not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item.name)
        GameTooltip:AddLine(Items.EffectText(item), 1, 1, 1, true)
        GameTooltip:AddLine(Format(Text["Price: {gold}"], { gold = money(item.price) }), 1, 0.82, 0)
        if item.kind == "trap" then GameTooltip:AddLine(Text["Use it with your target selected."], 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

---@param parent table
---@return table header
local function createHeader(parent)
    local header = addon.UI.Widgets.CreateFontString(parent, "GameFontNormalSmall", "LEFT")
    header:SetWidth(280); header:SetHeight(HEADER_HEIGHT)
    return header
end

------------------------------------------------------------------ build

-- One view: the gold line, a scrolling list of group headers and item rows, the empty hint and the status line.
---@param panel table
---@param view "shop"|"inventory"
local function buildView(panel, view)
    local Widgets = addon.UI.Widgets
    local parts = widgets[view]
    parts.panel = panel
    parts.gold = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "LEFT")
    parts.gold:SetPoint("TOPLEFT", 8, -26); parts.gold:SetWidth(284)
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 4, LIST_TOP); scroll:SetSize(290, LIST_HEIGHT)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(290, LIST_HEIGHT)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maximum = math.max(0, (parts.contentHeight or 0) - LIST_HEIGHT)
        local offset = addon.Utility.Clamp((tonumber(self:GetVerticalScroll()) or 0) - delta * ROW_HEIGHT, 0, maximum)
        self:SetVerticalScroll(offset)
    end)
    parts.scroll, parts.content, parts.rows, parts.headers = scroll, content, {}, {}
    parts.empty = Widgets.CreateFontString(panel, "GameFontDisableSmall", "CENTER")
    parts.empty:SetPoint("TOP", 0, -120); parts.empty:SetWidth(260)
    parts.empty:SetText(view == "shop" and "" or Text["Nothing here yet. Buy items in the Shop."])
    parts.empty:Hide()
    parts.status = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    parts.status:SetPoint("TOP", 0, -318); parts.status:SetWidth(290)
end

function ShopView.BuildShop(panel) buildView(panel, "shop") end
function ShopView.BuildInventory(panel) buildView(panel, "inventory") end

------------------------------------------------------------------ refresh

-- The entries of a view by group: { header = group } and { item, count } in catalog order.
---@param view "shop"|"inventory"
---@return table[]
function ShopView.Entries(view)
    local entries = {}
    for _, group in ipairs(Items.GROUPS) do
        local list = {}
        if view == "shop" then
            for _, item in ipairs(Items.CATALOG) do
                if item.group == group.id then list[#list + 1] = { item = item, count = Items.Count(item.id) } end
            end
        else
            list = Items.Owned(group.id)
        end
        if #list > 0 then
            entries[#entries + 1] = { header = group }
            for _, entry in ipairs(list) do entries[#entries + 1] = entry end
        end
    end
    return entries
end

---@param view "shop"|"inventory"
function ShopView.Refresh(view)
    local parts = widgets[view]
    if not parts.panel then return end
    local myName = addon.Utility.Me()
    parts.gold:SetText(Format(Text["Your gold: {gold}"], { gold = money(addon.Wallet.Balance(myName)) }))
    local entries = ShopView.Entries(view)
    local y, rowIndex, headerIndex = 0, 0, 0
    for _, entry in ipairs(entries) do
        if entry.header then
            headerIndex = headerIndex + 1
            local header = parts.headers[headerIndex] or createHeader(parts.content)
            parts.headers[headerIndex] = header
            header:ClearAllPoints(); header:SetPoint("TOPLEFT", 4, -y)
            header:SetText(entry.header.name); header:Show()
            y = y + HEADER_HEIGHT
        else
            rowIndex = rowIndex + 1
            local row = parts.rows[rowIndex] or createRow(parts.content, view)
            parts.rows[rowIndex] = row
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
            local item = entry.item
            row.itemID = item.id
            addon.UIHelpers.SetTextureOr(row.icon, item.icon, { 0.8, 0.6, 0.3 })
            row.effect:SetText(Items.EffectText(item))
            if view == "shop" then
                -- the owned count after the name: the right side holds the price and the Buy button
                row.name:SetText(item.name .. (entry.count > 0 and (" |cffb0b0b0" .. Format(Text["Owned: {n}"], { n = entry.count }) .. "|r") or ""))
                row.detail:SetText(money(item.price))
                row.action:SetEnabled(Items.BuyRefusal(item.id, myName) == nil)
            else
                row.name:SetText(item.name)
                row.detail:SetText("x" .. entry.count)
                row.action:SetEnabled(true)
            end
            row:Show()
            y = y + ROW_HEIGHT + 2
        end
    end
    for index = rowIndex + 1, #parts.rows do parts.rows[index]:Hide() end
    for index = headerIndex + 1, #parts.headers do parts.headers[index]:Hide() end
    parts.contentHeight = y
    parts.content:SetHeight(math.max(LIST_HEIGHT, y))
    parts.empty:SetShown(rowIndex == 0)
end

------------------------------------------------------------------ actions

-- Buys one item; the result or the refusal goes to the Shop's status line.
---@param itemID string
---@return boolean bought
function ShopView.Buy(itemID)
    local item = Items.Get(itemID)
    local count, reason = Items.Buy(itemID, addon.Utility.Me(), addon.Utility.Now())
    if count then
        ShopView.ShowStatus("shop", "|cff66ff66" .. Format(Text["Bought {item} for {gold}. You have {n}."],
            { item = item.name, gold = money(item.price), n = count }) .. "|r")
        addon.Api.PlaySound(addon.Api.SoundKitFor({ "LOOTWINDOWCOINSOUND", "IG_MAINMENU_OPTION_CHECKBOX_ON" }))
        addon.Events.Fire("ITEMS_CHANGED")
    else
        ShopView.ShowStatus("shop", "|cffff4040" .. buyRefusalText(reason) .. "|r")
    end
    ShopView.Refresh("shop")
    return count ~= nil
end

-- Uses one item from the Inventory (a trap on the current target).
---@param itemID string
---@return boolean used
function ShopView.Use(itemID)
    local item = Items.Get(itemID)
    if not item then return false end
    local used = addon.CatchItems.UseItem(itemID)
    ShopView.ShowStatus("inventory", used and ("|cff66ff66" .. Format(Text["Used {item}."], { item = item.name }) .. "|r") or "")
    ShopView.Refresh("inventory")
    return used
end

addon.Events.On("ITEMS_CHANGED", function()
    for _, view in ipairs({ "shop", "inventory" }) do
        local panel = widgets[view].panel
        if panel and panel:IsVisible() then ShopView.Refresh(view) end
    end
end)
