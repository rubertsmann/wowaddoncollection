local ADDON, ns = ...

-- Standalone window: "Recipes" tab (filter, search, reagents, crafters, request) and "Orders" tab (shared board).
-- Plain frames only (no secure templates), so it never taints and is safe to open in combat.
-- All text goes through L (Locales/); game names are resolved for this client by Model/Names. tests/test_locale_files.lua
-- fails on a hardcoded label.
local UI = {}
ns.UI = UI

local L, F, P = ns.L, ns.Locale.Fmt, ns.Locale.Plural

local ROW_H = 20
local atan2 = math.atan2 or math.atan

local state = {
    tab = "recipes",
    professionIdx = 0,           -- 0 = all, else index into the professions list ({ key, name })
    text = "",
    mineOnly = false,
    selectedRecipe = nil,
    orderFilterIdx = 1,
    showClosed = false,
    selectedOrder = nil,
}
local function orderFilters()
    return { { "all", L["All"] }, { "open", L["Open"] }, { "mine", L["My requests"] }, { "crafting", L["I'm crafting"] },
        { "can", L["I can craft"] } }
end
local STATUS_COLOR = { open = "ffd100", claimed = "33ff99", done = "888888", cancelled = "ff5555" }
local function statusLabel(st)
    local map = { open = L["Open"], claimed = L["Claimed"], done = L["Done"], cancelled = L["Cancelled"] }
    return map[st] or st
end

local function me() return ns.Store.db.me or ns.Api.GetPlayerInfo().name end

local function classColor(class, text)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, text) end
    return text
end

local function ago(ts)
    local d = ns.Util.Now() - (ts or 0)
    if d < 90 then return L["just now"] end
    if d < 5400 then return F(L["{n}m ago"], { n = math.floor(d / 60) }) end
    if d < 129600 then return F(L["{n}h ago"], { n = math.floor(d / 3600) }) end
    return F(L["{n}d ago"], { n = math.floor(d / 86400) })
end

local function text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", size or "GameFontNormal")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Buttons grow to fit their label (translations are often longer than English); `w` is the minimum width.
local function setLabel(b, label)
    b:SetText(label)
    local fs = b.GetFontString and b:GetFontString()
    if fs and b.minW then b:SetWidth(math.max(b.minW, math.ceil(fs:GetStringWidth()) + 24)) end
end

local function button(parent, label, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b.minW = w
    b.SetLabel = setLabel
    b:SetLabel(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- scrolling list of pooled rows with mouse wheel + slider
local function createList(parent, w, h, makeRow, fillRow)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(w, h)
    local nrows = math.floor(h / ROW_H)
    list.rows, list.data, list.offset = {}, {}, 0
    for i = 1, nrows do
        local r = makeRow(list)
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetSize(w - 16, ROW_H)
        list.rows[i] = r
    end
    local s = CreateFrame("Slider", nil, list)
    s:SetOrientation("VERTICAL")
    s:SetSize(12, h)
    s:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    local bg = s:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.35)
    local th = s:CreateTexture(nil, "OVERLAY"); th:SetSize(10, 28); th:SetColorTexture(0.7, 0.7, 0.7, 0.8)
    s:SetThumbTexture(th)
    s:SetMinMaxValues(0, 0); s:SetValueStep(1); s:SetValue(0)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        if v ~= list.offset then list.offset = v; list:Refresh() end
    end)
    list.slider = s
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, d)
        local maxOff = math.max(0, #self.data - nrows)
        self.offset = math.max(0, math.min(maxOff, self.offset - d * 3))
        s:SetValue(self.offset)
        self:Refresh()
    end)
    function list:SetData(data)
        self.data = data
        local maxOff = math.max(0, #data - nrows)
        if self.offset > maxOff then self.offset = maxOff end
        s:SetMinMaxValues(0, maxOff)
        s:SetValue(self.offset)
        self:Refresh()
    end
    function list:Refresh()
        for i, r in ipairs(self.rows) do
            local item = self.data[self.offset + i]
            if item then r.item = item; fillRow(r, item); r:Show() else r.item = nil; r:Hide() end
        end
    end
    return list
end

local function makeSelectableRow(list)
    local r = CreateFrame("Button", nil, list)
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
    r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(0.2, 0.5, 1, 0.3); r.sel:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(ROW_H - 2, ROW_H - 2); r.icon:SetPoint("LEFT", 2, 0)
    r.label = text(r, "GameFontHighlightSmall"); r.label:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.label:SetPoint("RIGHT", -70, 0)
    r.right = text(r, "GameFontNormalSmall", "RIGHT"); r.right:SetPoint("RIGHT", -2, 0)
    return r
end

------------------------------------------------------------------ frame

local f
local recipeList, orderList
local detail = {}

local function professionsList() return ns.Model.Professions(ns.Store) end

local function refreshRecipes()
    if not f or state.tab ~= "recipes" then return end
    local profs = professionsList()
    if state.professionIdx > #profs then state.professionIdx = 0 end
    local sel = profs[state.professionIdx]
    f.profBtn:SetLabel(F(L["Profession: {name}"], { name = sel and sel.name or L["All"] }))
    local rows = ns.Model.BuildRecipeRows(ns.Store, { profession = sel and sel.key, text = state.text,
        mineOnly = state.mineOnly, me = me() }, ns.Api.ItemName)
    recipeList:SetData(rows)
    f.count:SetText(P(#rows, L["{n} recipe"], L["{n} recipes"]))
    -- nothing cached anywhere yet: say how to fill it (recipes are only readable while a profession window is open)
    f.recipesEmpty:SetShown(#profs == 0)
end

local function refreshDetail()
    if not f or state.tab ~= "recipes" then return end
    local id = state.selectedRecipe
    local d = id and ns.Model.RecipeDetail(ns.Store, id, ns.Api.ItemCount, ns.Api.ItemName)
    detail.title:SetText(d and d.name or L["Select a recipe"])
    detail.icon:SetTexture(d and d.icon or nil)
    detail.reqLabel:SetShown(d ~= nil)
    for i, line in ipairs(detail.reagents) do
        local r = d and d.reagents[i]
        if r then
            line.itemID = r.itemID
            line.icon:SetTexture(ns.Api.ItemIcon(r.itemID))
            local color = r.enough and "33ff99" or "ff6666"
            line.label:SetText(("%s x%d  |cff%s(%s)|r"):format(r.name, r.count, color, F(L["have {n}"], { n = r.have })))
            line:Show()
        else
            line:Hide()
        end
    end
    detail.noReagents:SetShown(d ~= nil and #d.reagents == 0)
    detail.crafterLabel:SetShown(d ~= nil)
    for i, line in ipairs(detail.crafters) do
        local c = d and d.crafters[i]
        if c then
            line.who = c.name
            line.label:SetText(("%s  |cffaaaaaa%s %d/%d, %s|r"):format(classColor(c.class, c.name), c.professionName or c.profession,
                c.rank or 0, c.max or 0, ago(c.rev)))
            line:Show()
        else
            line:Hide()
        end
    end
    detail.more:SetText(d and #d.crafters > #detail.crafters and F(L["+{n} more"], { n = #d.crafters - #detail.crafters }) or "")
    for _, w in ipairs({ detail.qty, detail.note, detail.request }) do w:SetShown(d ~= nil) end
end

local function refreshOrders()
    if not f or state.tab ~= "orders" then return end
    local key = orderFilters()[state.orderFilterIdx]
    f.orderFilterBtn:SetLabel(F(L["Show: {filter}"], { filter = key[2] }))
    f.closedBtn:SetLabel(state.showClosed and L["Hide finished"] or L["Show finished"])
    local rows = ns.Model.BuildOrderRows(ns.Store, ns.orders, key[1], state.showClosed, me())
    orderList:SetData(rows)
    local sel
    for _, r in ipairs(rows) do if r.id == state.selectedOrder then sel = r end end
    f.claimBtn:SetEnabled(sel and sel.canClaim or false)
    f.withdrawBtn:SetEnabled(sel and sel.canWithdraw or false)
    f.doneBtn:SetEnabled(sel and sel.canDone or false)
    f.cancelBtn:SetEnabled(sel and sel.canCancel or false)
    f.ordersEmpty:SetShown(#rows == 0)
end

function UI.Refresh()
    if not f or not f:IsShown() then return end
    refreshRecipes(); refreshDetail(); refreshOrders()
end

local function setTab(name)
    state.tab = name
    for key, frame in pairs(f.tabs) do frame:SetShown(key == name) end
    f.tabBtns.recipes:SetEnabled(name ~= "recipes")
    f.tabBtns.orders:SetEnabled(name ~= "orders")
    UI.Refresh()
end
UI.SelectTab = function(name) if f then setTab(name) end end

local function whisper(name)
    if ChatFrame_SendTell then ChatFrame_SendTell(name) elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " ") end
end

local function afterOrderChange(order)
    if order then ns.Comm.BroadcastOrder(order) end
    UI.Refresh()
end

local function build()
    local ok
    local frameName = ns.FRAME .. "Frame"
    ok, f = pcall(CreateFrame, "Frame", frameName, UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then
        f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -2, -2)
    end
    f:SetSize(780, 520)
    f:SetPoint("CENTER", ns.IS_DEV and 40 or 0, ns.IS_DEV and -40 or 0)   -- dev window is offset so both can be open
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("HIGH")
    f:Hide()
    table.insert(UISpecialFrames, frameName)
    f:SetScript("OnShow", function()
        ns.Events.Fire("WINDOW_OPENED")
        UI.Refresh()
        -- opening the window reads the player's professions (default on; /ts autoscan off disables), see AutoScan.Auto
        -- deferred: the profession window must not be opened from inside our own frame's OnShow (taint)
        if C_Timer and C_Timer.After then C_Timer.After(0.5, ns.AutoScan.Auto) else ns.AutoScan.Auto() end
    end)

    local title = text(f, "GameFontNormalLarge"); title:SetPoint("TOP", 0, -6); title:SetText(ns.TITLE)

    f.tabBtns = {
        recipes = button(f, L["Recipes"], 90, 22, function() setTab("recipes") end),
        orders = button(f, L["Orders"], 90, 22, function() setTab("orders") end),
    }
    f.tabBtns.recipes:SetPoint("TOPLEFT", 12, -30)
    f.tabBtns.orders:SetPoint("LEFT", f.tabBtns.recipes, "RIGHT", 4, 0)
    f.tabs = {}

    -- Recipes tab
    local rt = CreateFrame("Frame", nil, f); rt:SetPoint("TOPLEFT", 12, -58); rt:SetPoint("BOTTOMRIGHT", -12, 12)
    f.tabs.recipes = rt
    f.profBtn = button(rt, F(L["Profession: {name}"], { name = L["All"] }), 190, 22, function() end)
    f.profBtn:SetPoint("TOPLEFT", 0, 0)
    f.profBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.profBtn:SetScript("OnClick", function(_, btn)
        local n = #professionsList()
        state.professionIdx = (state.professionIdx + (btn == "RightButton" and -1 or 1)) % (n + 1)
        refreshRecipes()
    end)
    local search = CreateFrame("EditBox", nil, rt, "InputBoxTemplate")
    search:SetSize(150, 20); search:SetPoint("LEFT", f.profBtn, "RIGHT", 14, 0); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self) state.text = self:GetText(); refreshRecipes() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search
    local hint = text(rt, "GameFontDisableSmall"); hint:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 0, 0); hint:SetText(L["search recipe or reagent"])
    f.mineBtn = button(rt, L["Mine only"], 80, 22, function()
        state.mineOnly = not state.mineOnly
        f.mineBtn:SetLabel(state.mineOnly and (L["Mine only"] .. " *") or L["Mine only"])
        refreshRecipes()
    end)
    f.mineBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
    f.count = text(rt, "GameFontNormalSmall", "RIGHT"); f.count:SetPoint("TOPRIGHT", rt, "TOPRIGHT", -330, -6)

    recipeList = createList(rt, 440, 400, makeSelectableRow, function(r, row)
        r.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.label:SetText(row.name .. "  |cff888888" .. row.profession .. "|r")
        r.right:SetText(P(row.crafterCount, L["{n} crafter"], L["{n} crafters"]))
        r.sel:SetShown(row.recipeID == state.selectedRecipe)
        r:SetScript("OnClick", function()
            state.selectedRecipe = row.recipeID
            recipeList:Refresh(); refreshDetail()
        end)
    end)
    recipeList:SetPoint("TOPLEFT", 0, -34)
    f.recipesEmpty = text(rt, "GameFontDisable", "CENTER")
    f.recipesEmpty:SetPoint("CENTER", recipeList, "CENTER", 0, 0); f.recipesEmpty:SetWidth(380)
    f.recipesEmpty:SetText(L["No recipes known yet. Use the reload symbol at the top right (or open each profession window once)."])
    -- one click reads every profession (opens them one after another), so nobody has to cycle through the pages
    -- small reload symbol (tooltip explains it); the stock refresh texture needs no translation
    local scanBtn = CreateFrame("Button", nil, rt)
    f.scanBtn = scanBtn
    scanBtn:SetSize(20, 20)
    scanBtn:SetPoint("TOPRIGHT", rt, "TOPRIGHT", 0, -1)
    local scanIcon = scanBtn:CreateTexture(nil, "ARTWORK")
    scanIcon:SetAllPoints()
    scanIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    scanBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    scanBtn:SetScript("OnMouseDown", function()
        scanIcon:ClearAllPoints(); scanIcon:SetPoint("TOPLEFT", 1, -1); scanIcon:SetPoint("BOTTOMRIGHT", 1, -1)
    end)
    scanBtn:SetScript("OnMouseUp", function() scanIcon:ClearAllPoints(); scanIcon:SetAllPoints() end)
    scanBtn:SetScript("OnClick", function() ns.AutoScan.Run(true) end)
    scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Scan professions"])
        GameTooltip:AddLine(L["Reads all your professions: opens each one briefly."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- detail panel
    local dp = CreateFrame("Frame", nil, rt); dp:SetPoint("TOPLEFT", recipeList, "TOPRIGHT", 12, 0); dp:SetPoint("BOTTOMRIGHT", 0, 0)
    detail.icon = dp:CreateTexture(nil, "ARTWORK"); detail.icon:SetSize(32, 32); detail.icon:SetPoint("TOPLEFT", 0, 0)
    detail.title = text(dp, "GameFontNormalLarge"); detail.title:SetPoint("LEFT", detail.icon, "RIGHT", 8, 0); detail.title:SetPoint("RIGHT", 0, 0)
    detail.reqLabel = text(dp, "GameFontNormal"); detail.reqLabel:SetPoint("TOPLEFT", 0, -44); detail.reqLabel:SetText(L["Reagents"])
    detail.reagents = {}
    for i = 1, 8 do
        local line = CreateFrame("Frame", nil, dp)
        line:SetSize(280, 18); line:SetPoint("TOPLEFT", 0, -44 - i * 19)
        line.icon = line:CreateTexture(nil, "ARTWORK"); line.icon:SetSize(16, 16); line.icon:SetPoint("LEFT", 0, 0)
        line.label = text(line, "GameFontHighlightSmall"); line.label:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
        line:EnableMouse(true)
        line:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID then GameTooltip:SetHyperlink("item:" .. self.itemID) end
            GameTooltip:Show()
        end)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        detail.reagents[i] = line
    end
    detail.noReagents = text(dp, "GameFontDisableSmall"); detail.noReagents:SetPoint("TOPLEFT", 0, -64); detail.noReagents:SetText(L["reagents unknown (not scanned yet)"])
    detail.crafterLabel = text(dp, "GameFontNormal"); detail.crafterLabel:SetPoint("TOPLEFT", 0, -222); detail.crafterLabel:SetText(L["Who can craft it (click to whisper)"])
    detail.crafters = {}
    for i = 1, 7 do
        local line = CreateFrame("Button", nil, dp)
        line:SetSize(300, 18); line:SetPoint("TOPLEFT", 0, -222 - i * 19)
        local hl = line:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
        line.label = text(line, "GameFontHighlightSmall"); line.label:SetPoint("LEFT", 2, 0)
        line:SetScript("OnClick", function(self) if self.who then whisper(self.who) end end)
        detail.crafters[i] = line
    end
    detail.more = text(dp, "GameFontDisableSmall"); detail.more:SetPoint("TOPLEFT", 0, -222 - 8 * 19)
    detail.qty = CreateFrame("EditBox", nil, dp, "InputBoxTemplate")
    detail.qty:SetSize(30, 20); detail.qty:SetPoint("BOTTOMLEFT", 6, 8); detail.qty:SetAutoFocus(false); detail.qty:SetNumeric(true); detail.qty:SetText("1"); detail.qty:SetMaxLetters(2)
    detail.note = CreateFrame("EditBox", nil, dp, "InputBoxTemplate")
    detail.note:SetSize(130, 20); detail.note:SetPoint("LEFT", detail.qty, "RIGHT", 12, 0); detail.note:SetAutoFocus(false)
    detail.note:SetMaxLetters(80)
    -- the order note limit is 80 BYTES (Orders.lua); multi-byte characters (umlauts, Cyrillic, CJK) count 2-4 bytes each
    if detail.note.SetMaxBytes then detail.note:SetMaxBytes(80) end
    detail.request = button(dp, L["Request"], 70, 22, function()
        local id = state.selectedRecipe
        if not id then return end
        local qty = tonumber(detail.qty:GetText()) or 1
        if qty < 1 then qty = 1 end
        local o = ns.orders:Create(me(), id, qty, detail.note:GetText() or "")
        if o then
            detail.note:SetText(""); detail.qty:SetText("1")
            afterOrderChange(o)
            setTab("orders")
            ns.Print(F(L["Requested {qty}x {name}"], { qty = qty, name = ns.Model.RecipeName(ns.Store, id) }))
        end
    end)
    detail.request:SetPoint("LEFT", detail.note, "RIGHT", 8, 0)

    -- Orders tab
    local ot = CreateFrame("Frame", nil, f); ot:SetPoint("TOPLEFT", 12, -58); ot:SetPoint("BOTTOMRIGHT", -12, 12)
    f.tabs.orders = ot
    f.orderFilterBtn = button(ot, F(L["Show: {filter}"], { filter = L["All"] }), 160, 22, function()
        state.orderFilterIdx = state.orderFilterIdx % #orderFilters() + 1
        refreshOrders()
    end)
    f.orderFilterBtn:SetPoint("TOPLEFT", 0, 0)
    f.closedBtn = button(ot, L["Show finished"], 120, 22, function() state.showClosed = not state.showClosed; refreshOrders() end)
    f.closedBtn:SetPoint("LEFT", f.orderFilterBtn, "RIGHT", 8, 0)
    local help = text(ot, "GameFontDisableSmall"); help:SetPoint("TOPRIGHT", 0, -6)
    help:SetText(L["Request recipes on the Recipes tab. Everyone in the guild sees this board."])
    orderList = createList(ot, 736, 380, makeSelectableRow, function(r, row)
        r.icon:SetTexture((ns.Store.GetRecipe(row.recipeID) or {}).icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local who = #row.claimers > 0 and ("  -> |cff33ff99" .. table.concat(row.claimers, ", ") .. "|r") or ""
        local note = row.note ~= "" and ("  |cff999999\"" .. row.note .. "\"|r") or ""
        r.label:SetText(("%dx %s  |cffaaaaaa%s|r%s%s"):format(row.qty, row.recipeName, F(L["for {name}"], { name = row.requester }), who, note))
        r.right:SetText("|cff" .. (STATUS_COLOR[row.status] or "ffffff") .. statusLabel(row.status) .. "|r  " .. ago(row.createdAt))
        r.label:SetPoint("RIGHT", -130, 0)
        r.sel:SetShown(row.id == state.selectedOrder)
        r:SetScript("OnClick", function() state.selectedOrder = row.id; refreshOrders() end)
    end)
    orderList:SetPoint("TOPLEFT", 0, -30)
    f.ordersEmpty = text(ot, "GameFontDisable"); f.ordersEmpty:SetPoint("CENTER", 0, 0); f.ordersEmpty:SetText(L["No orders yet."])
    local function act(fn)
        return function()
            local id = state.selectedOrder
            if not id then return end
            afterOrderChange(fn(id))
        end
    end
    f.claimBtn = button(ot, L["I'll craft it"], 110, 24, act(function(id) return ns.orders:Claim(id, me()) end))
    f.withdrawBtn = button(ot, L["Withdraw"], 90, 24, act(function(id) return ns.orders:Withdraw(id, me()) end))
    f.doneBtn = button(ot, L["Mark done"], 90, 24, act(function(id) return ns.orders:Close(id, me(), "done") end))
    f.cancelBtn = button(ot, L["Cancel order"], 100, 24, act(function(id) return ns.orders:Close(id, me(), "cancelled") end))
    f.claimBtn:SetPoint("BOTTOMLEFT", 0, 0)
    f.withdrawBtn:SetPoint("LEFT", f.claimBtn, "RIGHT", 6, 0)
    f.doneBtn:SetPoint("LEFT", f.withdrawBtn, "RIGHT", 6, 0)
    f.cancelBtn:SetPoint("LEFT", f.doneBtn, "RIGHT", 6, 0)

    ns.Events.On("DATA_CHANGED", UI.Refresh)
    ns.Events.On("ITEM_INFO", function() if f:IsShown() then refreshDetail() end end)
    setTab("recipes")
end

function UI.Toggle()
    if not f then build() end
    if f:IsShown() then f:Hide() else f:Show() end
end

function UI.Show()
    if not f then build() end
    f:Show()
end

------------------------------------------------------------------ minimap button

local function placeMinimapButton(b)
    local a = math.rad(ns.db and ns.db.ui.minimapAngle or (ns.IS_DEV and 245 or 215))
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

local function buildMinimapButton()
    local b = CreateFrame("Button", ns.FRAME .. "MinimapButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "BACKGROUND"); icon:SetSize(20, 20); icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    local ring = b:CreateTexture(nil, "OVERLAY"); ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("RightButton")
    b:SetScript("OnClick", UI.Toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.TITLE); GameTooltip:AddLine(L["Click: open window. Right-drag: move."], 1, 1, 1); GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.ui.minimapAngle = math.deg(atan2(cy / s - my, cx / s - mx))
            placeMinimapButton(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    placeMinimapButton(b)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    local ok, err = pcall(buildMinimapButton)
    if not ok then ns.Util.ReportError(err) end
end)
