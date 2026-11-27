local addonName, addon = ...

-- One window for one order, opened from the chat icon of an order row: Overview (the whole order: recipe, quantity,
-- status, people, note, reagents for the ordered quantity with what I hold, tools, who knows the recipe), Chat (the
-- order's messages, an input line at the bottom; every guild member reads and writes) and History (every status change
-- with date and time, and every mail sent for the order). The data views come from Core/View/Model.lua; peer text arrives escaped from there.
---@class OrderWindowModule
local OrderWindow = {}
addon.OrderWindow = OrderWindow

local Text, Format = addon.Text, addon.Locale.Format
local Widgets = LibStub("LibGuildSync-1.0").Widgets
local createFontString, createButton = Widgets.CreateFontString, Widgets.CreateButton

local WINDOW_WIDTH, WINDOW_HEIGHT = 560, 450
local LIST_WIDTH, LIST_HEIGHT = WINDOW_WIDTH - 28, 300
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
---@type table<OrderStatus, string>
local STATUS_COLOR = { open = "ffd100", claimed = "33ff99", mailed = "66ccff", done = "888888", cancelled = "ff5555" }
---@type string[]
local TABS = { "overview", "chat", "history" }

---@class OrderWindowState
---@field orderID string|nil
---@field tab "overview"|"chat"|"history"
local windowState = { orderID = nil, tab = "overview" }
---@type table|nil
local frame

---@return string|nil
local function me() return addon.Utility.Me() end
---@param playerName string|nil
---@return string
local function shortName(playerName) return addon.Utility.Escape(addon.Utility.ShortName(playerName or "?")) end

---@param timestamp integer|nil
---@return string
local function dateTimeText(timestamp)
    if type(timestamp) ~= "number" or not date then return "" end
    return date("%Y-%m-%d %H:%M", timestamp)
end

-- the time of day for today's messages, else date and time
---@param timestamp integer
---@return string
local function chatTimeText(timestamp)
    if not date then return "" end
    if date("%Y-%m-%d", timestamp) == date("%Y-%m-%d", addon.Utility.Now()) then return date("%H:%M", timestamp) end
    return date("%m-%d %H:%M", timestamp)
end

---@param status OrderStatus
---@return string
local function statusText(status)
    local labels = { open = Text["Open"], claimed = Text["Claimed"], mailed = Text["Mailed"], done = Text["Done"],
        cancelled = Text["Cancelled"] }
    return "|cff" .. (STATUS_COLOR[status] or "ffffff") .. (labels[status] or status) .. "|r"
end

---@param kind string
---@param who string
---@return string
local function historyText(kind, who)
    local templates = { created = Text["{who} placed the order"], claim = Text["{who} will craft it"],
        withdraw = Text["{who} withdrew"], done = Text["{who} marked it done"], cancel = Text["{who} cancelled the order"] }
    return Format(templates[kind] or kind, { who = shortName(who) })
end

-- "Ann mailed the item to Bob: 2x Copper Bar (marked by hand)"
---@param mail OrderMail
---@return string
local function mailHistoryText(mail)
    local templates = mail.m == "item"
        and { [true] = Text["{who} mailed the item to {to}"], [false] = Text["{who} mailed part of the item to {to}"] }
        or { [true] = Text["{who} mailed the reagents to {to}"], [false] = Text["{who} mailed part of the reagents to {to}"] }
    local text = Format(templates[mail.c == true], { who = shortName(mail.b), to = shortName(mail.r) })
    local itemsText = addon.Model.MailItemsText(mail.i, addon.Api.ItemName)
    if itemsText ~= "" then text = text .. ": " .. itemsText end
    if mail.h then text = text .. " |cff999999" .. Text["(marked by hand)"] .. "|r" end
    return text
end

---@return Order|nil
local function currentOrder() return windowState.orderID and addon.orders and addon.orders:Get(windowState.orderID) end

------------------------------------------------------------------ tabs

---@param order Order
local function refreshOverview(order)
    local overview = addon.Model.OrderOverview(addon.Store, addon.orders, order, addon.Api.ItemCount, addon.Api.ItemName)
    local lines = {}
    local function line(text) lines[#lines + 1] = text end
    local function heading(text) line(""); line("|cffffd100" .. text .. "|r") end
    line(Format(Text["Status: {status}"], { status = statusText(overview.status) }))
    line(Format(Text["Requested by {who} on {date}"], { who = shortName(overview.requester), date = dateTimeText(overview.createdAt) }))
    if #overview.claimers > 0 then
        local names = {}
        for index, crafter in ipairs(overview.claimers) do names[index] = shortName(crafter) end
        line(Format(Text["Crafted by: {names}"], { names = table.concat(names, ", ") }))
    end
    if overview.closedAt then
        line(Format(Text["Closed by {who} on {date}"], { who = shortName(overview.closedBy), date = dateTimeText(overview.closedAt) }))
    end
    if overview.note ~= "" then line(Format(Text["Note: {note}"], { note = "|cffdddddd" .. overview.note .. "|r" })) end
    heading(Format(Text["Reagents for {qty}x"], { qty = overview.qty }))
    if #overview.reagents == 0 then line("|cff999999" .. Text["Unknown: nobody in the guild has shared this recipe's reagents yet."] .. "|r") end
    for _, reagent in ipairs(overview.reagents) do
        local icon = addon.Api.ItemIcon(reagent.itemID)
        line(("%s%s x%d  |cff%s(%s)|r"):format(icon and ("|T" .. icon .. ":14|t ") or "", reagent.name, reagent.count,
            reagent.enough and "33ff99" or "ff6666", Format(Text["have {n}"], { n = reagent.have })))
    end
    heading(Text["Tools"])
    line(#overview.tools > 0 and table.concat(overview.tools, ", ")
        or "|cff999999" .. Text["None known (a crafter's scan with the classic profession window records them)."] .. "|r")
    heading(Text["Who knows the recipe"])
    if #overview.crafters == 0 then line("|cff999999" .. Text["Nobody in the guild has shared it yet."] .. "|r") end
    for index, crafter in ipairs(overview.crafters) do
        if index > 12 then line(Format(Text["+{n} more"], { n = #overview.crafters - 12 })); break end
        line(("%s  |cffaaaaaa%s %d/%d|r"):format(shortName(crafter.name), crafter.professionName or "", crafter.rank or 0, crafter.max or 0))
    end
    frame.overviewText:SetText(table.concat(lines, "\n"))
    frame.overviewChild:SetHeight(math.max(10, (tonumber(frame.overviewText:GetStringHeight()) or 0) + 10))
    local itemRecipient, matsRecipient = addon.Model.MarkMailTargets(addon.orders, order, me())
    frame.markItemButton:SetShown(itemRecipient ~= nil)
    frame.markMatsButton:SetShown(matsRecipient ~= nil)
end

---@param order Order
local function refreshChat(order)
    local chatRows = addon.Model.OrderChatRows(order, me())
    frame.chatList.offset = #chatRows   -- newest at the bottom: SetData clamps this to the last page
    frame.chatList:SetData(chatRows)
    frame.chatEmptyText:SetShown(#chatRows == 0)
    if frame:IsShown() and addon.Alerts and addon.Alerts.ChatSeen then addon.Alerts.ChatSeen(order) end
end

---@param order Order
local function refreshHistory(order)
    frame.historyList:SetData(addon.Model.OrderHistory(order))
end

-- Has `order` a mail sent to me that I have not seen yet?
---@param order Order
---@return boolean
local function hasUnseenMail(order)
    local mailSeen = addon.db and addon.db.ui and addon.db.ui.mailSeen
    local seenUntil = type(mailSeen) == "table" and tonumber(mailSeen[order.id]) or 0
    for _, mail in ipairs(order.ml or {}) do
        if mail.r == me() and mail.t > seenUntil then return true end
    end
    return false
end

function OrderWindow.Refresh()
    if not frame or not frame:IsShown() then return end
    local order = currentOrder()
    if not order then frame:Hide() return end
    if hasUnseenMail(order) and addon.Alerts and addon.Alerts.MailSeen then addon.Alerts.MailSeen(order) end
    frame.icon:SetTexture((addon.Store.GetRecipe(order.recipeID) or {}).icon or QUESTION_MARK_ICON)
    frame.titleText:SetText(("%dx %s"):format(order.qty, addon.Model.OrderRecipeName(addon.Store, order)))
    local unreadCount = addon.Notify.ChatUnread(order, me(), addon.db and addon.db.ui and addon.db.ui.chatSeen)
    for _, tabKey in ipairs(TABS) do
        local selected = windowState.tab == tabKey
        frame.panels[tabKey]:SetShown(selected)
        local tabButton = frame.tabButtons[tabKey]
        if selected then tabButton:Disable() else tabButton:Enable() end
        if tabKey == "chat" then
            local messageCount = #(order.msgs or {})
            tabButton:SetLabel(messageCount > 0 and not selected and unreadCount > 0
                and Format(Text["Chat ({n} new)"], { n = unreadCount })
                or (messageCount > 0 and Format(Text["Chat ({n})"], { n = messageCount }) or Text["Chat"]))
        end
    end
    if windowState.tab == "overview" then refreshOverview(order)
    elseif windowState.tab == "chat" then refreshChat(order)
    else refreshHistory(order) end
end

---@param tabKey "overview"|"chat"|"history"
local function showTab(tabKey)
    windowState.tab = tabKey
    OrderWindow.Refresh()
    if tabKey == "chat" then frame.chatInput:SetFocus() end
end

-- I mark the item (`mode` "item") or the reagents ("mats") as mailed or handed over by hand
---@param mode "item"|"mats"
local function markMailed(mode)
    local order, myName = currentOrder(), me()
    if not order or not myName then return end
    local itemRecipient, matsRecipient = addon.Model.MarkMailTargets(addon.orders, order, myName)
    local recipient = mode == "item" and itemRecipient or matsRecipient
    if not recipient then return end
    local mail = addon.orders:RecordMail(order.id, { m = mode, b = myName, r = recipient, c = true, h = true })
    if not mail then return end
    addon.Communication.BroadcastOrder(order)
    addon.Log.Information("orderWindow.mail", "a mail was marked by hand", { orderID = order.id, mode = mode })
    addon.Events.Fire("DATA_CHANGED", "orders")
end
OrderWindow.MarkMailed = markMailed

local function sendChatMessage()
    local order = currentOrder()
    local text = frame.chatInput:GetText() or ""
    if not order or not me() then return end
    local message = addon.orders:AddMessage(order.id, me(), text)
    if not message then return end
    frame.chatInput:SetText("")
    addon.Communication.BroadcastOrderMessage(order.id, message)
    addon.Log.Information("orderWindow.chat", "a chat message was sent", { orderID = order.id, bytes = #message.x })
    addon.Events.Fire("DATA_CHANGED", "orders")
end

------------------------------------------------------------------ frame

---@param list table
---@return table row
local function createChatRow(list)
    local row = CreateFrame("Button", nil, list)
    local hover = row:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.08)
    row.label = createFontString(row, "GameFontHighlightSmall"); row.label:SetPoint("LEFT", 2, 0); row.label:SetPoint("RIGHT", -2, 0)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    -- the whole message in the tooltip (a row shows one line)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(shortName(self.entry.author) .. "  " .. dateTimeText(self.entry.t), 1, 0.82, 0)
        GameTooltip:AddLine(self.entry.text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

---@param row table
---@param chatRow OrderChatRow
local function fillChatRow(row, chatRow)
    local nameColor = chatRow.mine and "66ccff" or "ffd100"
    row.label:SetText(("|cff888888%s|r |cff%s%s:|r %s"):format(chatTimeText(chatRow.t), nameColor, shortName(chatRow.author), chatRow.text))
end

---@param list table
---@return table row
local function createHistoryRow(list)
    local row = CreateFrame("Frame", nil, list)
    row.dateText = createFontString(row, "GameFontDisableSmall"); row.dateText:SetPoint("LEFT", 2, 0); row.dateText:SetWidth(110)
    row.dateText:SetJustifyH("LEFT")
    row.label = createFontString(row, "GameFontHighlightSmall"); row.label:SetPoint("LEFT", row.dateText, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", -2, 0); row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    -- a long mail line in full in the tooltip
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

---@param row table
---@param historyRow OrderHistoryRow
local function fillHistoryRow(row, historyRow)
    row.dateText:SetText(dateTimeText(historyRow.t))
    row.label:SetText(historyRow.mail and mailHistoryText(historyRow.mail) or historyText(historyRow.kind, historyRow.who))
    row.tooltipText = historyRow.mail and row.label:GetText() or nil
end

local function buildFrame()
    local frameName = addon.FRAME_PREFIX .. "OrderFrame"
    frame = Widgets.CreateDialogFrame(frameName, addon.Log)
    frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT); frame:SetPoint("CENTER", 80, 0)
    -- above the main window (strata HIGH): on the same strata the main window's rows, whose frame levels are higher,
    -- would draw through this window
    frame:SetFrameStrata("DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if UISpecialFrames then table.insert(UISpecialFrames, frameName) end
    frame.icon = frame:CreateTexture(nil, "ARTWORK"); frame.icon:SetSize(32, 32); frame.icon:SetPoint("TOPLEFT", 14, -30)
    frame.titleText = createFontString(frame, "GameFontNormalLarge"); frame.titleText:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
    frame.titleText:SetPoint("RIGHT", -14, 0); frame.titleText:SetJustifyH("LEFT")

    frame.tabButtons, frame.panels = {}, {}
    local tabLabels = { overview = Text["Overview"], chat = Text["Chat"], history = Text["History"] }
    local previousButton
    for _, tabKey in ipairs(TABS) do
        local tabButton = createButton(frame, tabLabels[tabKey], 100, 22, function() showTab(tabKey) end)
        if previousButton then tabButton:SetPoint("LEFT", previousButton, "RIGHT", 4, 0) else tabButton:SetPoint("TOPLEFT", 14, -68) end
        frame.tabButtons[tabKey], previousButton = tabButton, tabButton
        local panel = CreateFrame("Frame", nil, frame)
        panel:SetPoint("TOPLEFT", 14, -96); panel:SetPoint("BOTTOMRIGHT", -14, 12)
        frame.panels[tabKey] = panel
    end

    -- Overview: one text in a scroll frame
    local overviewScroll = CreateFrame("ScrollFrame", nil, frame.panels.overview, "UIPanelScrollFrameTemplate")
    overviewScroll:SetPoint("TOPLEFT", 0, 0); overviewScroll:SetPoint("BOTTOMRIGHT", -22, 30)
    local overviewChild = CreateFrame("Frame", nil, overviewScroll); overviewChild:SetSize(LIST_WIDTH - 30, 10)
    overviewScroll:SetScrollChild(overviewChild)
    frame.overviewText = createFontString(overviewChild, "GameFontHighlight"); frame.overviewText:SetPoint("TOPLEFT", 0, 0)
    frame.overviewText:SetWidth(LIST_WIDTH - 34); frame.overviewText:SetJustifyH("LEFT"); frame.overviewText:SetJustifyV("TOP")
    if frame.overviewText.SetWordWrap then frame.overviewText:SetWordWrap(true) end
    frame.overviewChild = overviewChild
    -- marking a mail by hand (sent outside the mail queue, or handed over by trade)
    frame.markItemButton = createButton(frame.panels.overview, Text["Mark item as mailed / handed over"], 240, 22, function() markMailed("item") end)
    frame.markItemButton:SetPoint("BOTTOMLEFT", 0, 2)
    frame.markMatsButton = createButton(frame.panels.overview, Text["Mark reagents as mailed / handed over"], 240, 22, function() markMailed("mats") end)
    frame.markMatsButton:SetPoint("BOTTOMRIGHT", -22, 2)

    -- Chat: the messages, the input line at the bottom
    frame.chatList = Widgets.CreateScrollList(frame.panels.chat, LIST_WIDTH, LIST_HEIGHT, createChatRow, fillChatRow)
    frame.chatList:SetPoint("TOPLEFT", 0, 0)
    frame.chatEmptyText = createFontString(frame.panels.chat, "GameFontDisable"); frame.chatEmptyText:SetPoint("TOP", 0, -120)
    frame.chatEmptyText:SetText(Text["No messages yet. Everyone in the guild with the addon can read and write here."])
    local chatInput = CreateFrame("EditBox", nil, frame.panels.chat, "InputBoxTemplate")
    chatInput:SetAutoFocus(false); chatInput:SetHeight(22)
    if chatInput.SetMaxBytes then chatInput:SetMaxBytes(addon.Orders.MAXIMUM_MESSAGE_BYTES + 1) end
    chatInput:SetPoint("BOTTOMLEFT", 6, 4); chatInput:SetPoint("RIGHT", -90, 0)
    chatInput:SetScript("OnEnterPressed", sendChatMessage)
    chatInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.chatInput = chatInput
    local sendButton = createButton(frame.panels.chat, Text["Send"], 80, 22, sendChatMessage)
    sendButton:SetPoint("LEFT", chatInput, "RIGHT", 6, 0)

    -- History: one row per status change
    frame.historyList = Widgets.CreateScrollList(frame.panels.history, LIST_WIDTH, LIST_HEIGHT + 30, createHistoryRow, fillHistoryRow)
    frame.historyList:SetPoint("TOPLEFT", 0, 0)

    frame:SetScript("OnShow", function() OrderWindow.Refresh() end)
    frame:Hide()
end

-- Opens the window for `orderID`: on the chat when it has unread messages (or `tab` when given), else on the overview.
---@param orderID string
---@param tab? "overview"|"chat"|"history"
function OrderWindow.Open(orderID, tab)
    local order = addon.orders and addon.orders:Get(orderID)
    if not order then return end
    if not frame then buildFrame() end
    windowState.orderID = orderID
    local unreadCount = addon.Notify.ChatUnread(order, me(), addon.db and addon.db.ui and addon.db.ui.chatSeen)
    windowState.tab = tab or (unreadCount > 0 and "chat") or "overview"
    addon.Log.Information("orderWindow.open", "the order window was opened", { orderID = orderID, tab = windowState.tab })
    if frame:IsShown() then OrderWindow.Refresh() else frame:Show() end
    if frame.Raise then frame:Raise() end
end

---@return string|nil orderID shown, or nil when the window is closed
function OrderWindow.ShownOrder() return (frame and frame:IsShown()) and windowState.orderID or nil end

addon.Events.On("DATA_CHANGED", function(kind)
    if kind == "orders" or kind == "chars" or kind == nil then OrderWindow.Refresh() end
end)
