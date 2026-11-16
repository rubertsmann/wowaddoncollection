local ADDON, ns = ...

-- Standalone window: "Recipes" tab (filter, search, reagents, crafters, request), "Orders" tab (shared board) and
-- "Available" tab (recipe items guild members hold, with dibs).
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
    offerText = "",
    offerMineProf = false,
    selectedOffer = nil,
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
local function short(n) return ns.Util.ShortName(n) end   -- display form of a character name (realm hidden on my own realm)

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
local recipeList, orderList, offerList
local offerRows = {}
local detail = {}

local function professionsList() return ns.Model.Professions(ns.Store) end

------------------------------------------------------------------ profession scan buttons
-- The game only exposes a profession's recipes while its window is open, and addon code may not open it (blocked,
-- "Interface-Aktion auf Grund eines Addons fehlgeschlagen"). A REAL click on a secure button may: each button is the
-- macro "/cast <profession>". Opening the window triggers the normal scan, so one click per profession reads it.
local bar = { buttons = {}, rows = {}, dirty = false }
local MAX_BAR = 5

local function barTooltip(self)
    local r = self.row
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(r.name)
    GameTooltip:AddLine(("%d/%d"):format(r.rank or 0, r.max or 0), 1, 1, 1)
    if r.count > 0 then
        GameTooltip:AddLine(P(r.count, L["{n} recipe"], L["{n} recipes"]), 0.2, 1, 0.6)
    else
        GameTooltip:AddLine(L["not scanned yet"], 1, 0.4, 0.4)
    end
    GameTooltip:AddLine(L["Click to open this profession and read its recipes."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function createBarButton(parent, i)
    local ok, b = pcall(CreateFrame, "Button", nil, parent, "SecureActionButtonTemplate")
    if not ok or not b then return nil end
    b:SetSize(24, 24)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
    b.count = text(b, "GameFontNormalSmall", "RIGHT"); b.count:SetPoint("BOTTOMRIGHT", 0, 1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", barTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- log every click (PostClick runs after the secure action; it does not touch it)
    b:HookScript("PostClick", function(self)
        bar.clickAt = GetTime and GetTime() or 0
        local r = self.row
        ns.Debug.Log("click", r and r.name or "?", "macro=" .. (r and ns.Model.CastMacro(r):gsub("\n", " | ") or "?"))
    end)
    if i == 1 then b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    else b:SetPoint("RIGHT", bar.buttons[i - 1], "LEFT", -4, 0) end
    b:Hide()
    return b
end

-- Attributes and visibility of secure frames may not change in combat: then only the counters are updated and the
-- rest is applied when combat ends (PLAYER_REGEN_ENABLED).
-- true for 6 seconds after a click on a profession button (used to attribute the game's error messages)
function UI.RecentBarClick()
    return bar.clickAt ~= nil and GetTime and (GetTime() - bar.clickAt) < 6 or false
end

-- once per profession set and session: what the spellbook says about each profession (names, ids, passive flag), so a
-- button that opens nothing (Skinning) can be diagnosed from SavedVariables without typing commands
local function logProfessions(live)
    local parts = {}
    for _, p in ipairs(live) do
        local spells = {}
        for _, e in ipairs(p.spellEntries or {}) do
            spells[#spells + 1] = ("%s#%s%s"):format(e.name, tostring(e.spellID), e.passive and "(passive)" or "")
        end
        parts[#parts + 1] = ("%s#%s offset=%s num=%s spells=[%s]"):format(p.name, tostring(p.id), tostring(p.spellOffset),
            tostring(p.numSpells), table.concat(spells, ","))
    end
    local line = table.concat(parts, " ; ")
    if line ~= bar.loggedLine then
        bar.loggedLine = line
        ns.Debug.Log("professions", line)
    end
end

local function refreshBar()
    if not f then return end
    local live = ns.Api.GetPlayerProfessions() or {}
    logProfessions(live)
    bar.rows = ns.Model.OwnProfessions(ns.Store, me(), live)
    local locked = ns.Api.InCombat()
    if locked then bar.dirty = true end
    for i = 1, MAX_BAR do
        local b, r = bar.buttons[i], bar.rows[i]
        if b then
            if r then
                b.row = r
                b.icon:SetTexture(r.icon)
                b.count:SetText(r.count)
                if r.count > 0 then b.count:SetTextColor(0.2, 1, 0.6); b.icon:SetVertexColor(1, 1, 1)
                else b.count:SetTextColor(1, 0.3, 0.3); b.icon:SetVertexColor(1, 0.55, 0.55) end
                if not locked then
                    b:SetAttribute("type", "macro")
                    b:SetAttribute("macrotext", ns.Model.CastMacro(r))
                    b:Show()
                end
            elseif not locked then
                b.row = nil
                b:Hide()
            end
        end
    end
    if not locked then bar.dirty = false end
    -- pulsing "CLICK HERE ->" to the left of the leftmost button while every profession is still at 0
    local lastBtn = bar.buttons[math.min(#bar.rows, MAX_BAR)]
    if f.barHint then
        if lastBtn and ns.Model.NeedsScanHint(bar.rows) then
            f.barHintText:ClearAllPoints()
            f.barHintText:SetPoint("RIGHT", lastBtn, "LEFT", -10, 0)
            f.barHint:Show()
        else
            f.barHint:Hide()
        end
    end
    if f.recipesEmpty then
        f.recipesEmpty:SetShown(#professionsList() == 0)
    end
end

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
            line.label:SetText(("%s  |cffaaaaaa%s %d/%d, %s|r"):format(classColor(c.class, short(c.name)), c.professionName or c.profession,
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

local function selectedOfferRow()
    for _, r in ipairs(offerRows) do if r.key == state.selectedOffer then return r end end
end

local function refreshOffers()
    if not f or state.tab ~= "available" then return end
    local rows = ns.Model.BuildOfferRows(ns.Store, { text = state.offerText, mineProf = state.offerMineProf, me = me() },
        ns.Api.ItemClass, ns.Api.ItemName)
    offerRows = rows
    offerList:SetData(rows)
    f.offerCount:SetText(P(#rows, L["{n} offer"], L["{n} offers"]))
    local sel = selectedOfferRow()
    f.dibsBtn:SetLabel(sel and sel.mine and L["Remove dibs"] or L["Dibs"])
    f.dibsBtn:SetEnabled(sel ~= nil and sel.canDib)
    f.hideBtn:SetEnabled(sel ~= nil)
    f.whisperBtn:SetEnabled(sel ~= nil and sel.canDib)
    if not sel then
        f.offerDetail:SetText(L["Select an offer to see who called dibs."])
    elseif #sel.dibs == 0 then
        f.offerDetail:SetText(L["No dibs yet."])
    else
        local parts = {}
        for i, d in ipairs(sel.dibs) do
            parts[i] = ("%d. %s |cffaaaaaa%s|r"):format(i, d.mine and ("|cff33ff99" .. short(d.who) .. "|r") or short(d.who), ago(d.t))
        end
        f.offerDetail:SetText(F(L["Dibs: {list}"], { list = table.concat(parts, "   ") }))
    end
    f.offersEmpty:SetShown(#rows == 0)
end

function UI.Refresh()
    if not f or not f:IsShown() then return end
    refreshRecipes(); refreshDetail(); refreshOrders(); refreshOffers(); refreshBar()
end

local function setTab(name)
    state.tab = name
    for key, frame in pairs(f.tabs) do frame:SetShown(key == name) end
    f.tabBtns.recipes:SetEnabled(name ~= "recipes")
    f.tabBtns.orders:SetEnabled(name ~= "orders")
    f.tabBtns.available:SetEnabled(name ~= "available")
    UI.Refresh()
end
UI.SelectTab = function(name) if f then setTab(name) end end

local function whisper(name)
    if not name or name == me() then return end   -- you cannot whisper yourself: the game answers "no player named ... online"
    name = ns.Util.WhisperTarget(name)   -- same-realm players by character name only (the "Name-Realm" form is not found)
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
    f:SetScript("OnShow", function() ns.Events.Fire("WINDOW_OPENED"); UI.Refresh() end)

    local title = text(f, "GameFontNormalLarge"); title:SetPoint("TOP", 0, -6); title:SetText(ns.TITLE)

    f.tabBtns = {
        recipes = button(f, L["Recipes"], 90, 22, function() setTab("recipes") end),
        orders = button(f, L["Orders"], 90, 22, function() setTab("orders") end),
        available = button(f, L["Available"], 90, 22, function() setTab("available") end),
    }
    f.tabBtns.recipes:SetPoint("TOPLEFT", 12, -30)
    f.tabBtns.orders:SetPoint("LEFT", f.tabBtns.recipes, "RIGHT", 4, 0)
    f.tabBtns.available:SetPoint("LEFT", f.tabBtns.orders, "RIGHT", 4, 0)
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
    f.recipesEmpty:SetText(L["No recipes known yet. Click your profession icons at the top right once."])
    -- one secure button per own profession (see "profession scan buttons" above)
    for i = 1, MAX_BAR do bar.buttons[i] = createBarButton(rt, i) end
    -- attention label next to the buttons (positioned and shown by refreshBar)
    local hint = CreateFrame("Frame", nil, rt)
    hint:SetSize(1, 1); hint:SetPoint("TOPRIGHT", rt, "TOPRIGHT", 0, 0)
    local hintText = text(hint, "GameFontNormalLarge", "RIGHT")
    hintText:SetText(L["CLICK HERE ->"]); hintText:SetTextColor(1, 0.82, 0)
    hint:SetScript("OnUpdate", function() hintText:SetAlpha(0.55 + 0.45 * math.abs(math.sin((GetTime and GetTime() or 0) * 3))) end)
    hint:Hide()
    f.barHint, f.barHintText = hint, hintText

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
        local claimers = {}
        for i, c in ipairs(row.claimers) do claimers[i] = short(c) end
        local who = #claimers > 0 and ("  -> |cff33ff99" .. table.concat(claimers, ", ") .. "|r") or ""
        local note = row.note ~= "" and ("  |cff999999\"" .. row.note .. "\"|r") or ""
        r.label:SetText(("%dx %s  |cffaaaaaa%s|r%s%s"):format(row.qty, row.recipeName, F(L["for {name}"], { name = short(row.requester) }), who, note))
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

    -- Available tab: recipe items on offer
    local at = CreateFrame("Frame", nil, f); at:SetPoint("TOPLEFT", 12, -58); at:SetPoint("BOTTOMRIGHT", -12, 12)
    f.tabs.available = at
    local osearch = CreateFrame("EditBox", nil, at, "InputBoxTemplate")
    osearch:SetSize(200, 20); osearch:SetPoint("TOPLEFT", 6, -14); osearch:SetAutoFocus(false)
    osearch:SetScript("OnTextChanged", function(self) state.offerText = self:GetText(); refreshOffers() end)
    osearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local ohint = text(at, "GameFontDisableSmall"); ohint:SetPoint("BOTTOMLEFT", osearch, "TOPLEFT", 0, 0)
    ohint:SetText(L["search item, owner or profession"])
    f.offerProfBtn = button(at, L["Only my professions"], 150, 22, function()
        state.offerMineProf = not state.offerMineProf
        f.offerProfBtn:SetLabel(state.offerMineProf and (L["Only my professions"] .. " *") or L["Only my professions"])
        refreshOffers()
    end)
    f.offerProfBtn:SetPoint("LEFT", osearch, "RIGHT", 8, 0)
    f.offerCount = text(at, "GameFontNormalSmall", "RIGHT"); f.offerCount:SetPoint("TOPRIGHT", at, "TOPRIGHT", -4, -6)
    offerList = createList(at, 736, 300, makeSelectableRow, function(r, row)
        r.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local prof = row.profession and ("  |cff888888" .. row.profession .. "|r") or ""
        r.label:SetText(("%s%s  |cffaaaaaa%s|r  |cff999999%s|r"):format(row.name, prof, short(row.ownerName), row.locations))
        r.right:SetText((row.mine and "|cff33ff99* |r" or "") .. P(row.dibCount, L["{n} dib"], L["{n} dibs"]))
        r.label:SetPoint("RIGHT", -100, 0)
        r.sel:SetShown(row.key == state.selectedOffer)
        r:SetScript("OnClick", function() state.selectedOffer = row.key; refreshOffers() end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. row.itemID)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end)
    offerList:SetPoint("TOPLEFT", 0, -38)
    f.offersEmpty = text(at, "GameFontDisable", "CENTER")
    f.offersEmpty:SetPoint("CENTER", offerList, "CENTER", 0, 0); f.offersEmpty:SetWidth(520)
    f.offersEmpty:SetText(L["No recipe items on offer yet. They are listed automatically from the bags, bank, mail, guild bank and auctions of every guild member."])
    f.offerDetail = text(at, "GameFontHighlightSmall")
    f.offerDetail:SetPoint("TOPLEFT", offerList, "BOTTOMLEFT", 4, -8); f.offerDetail:SetWidth(724); f.offerDetail:SetHeight(44)
    f.offerDetail:SetJustifyV("TOP"); f.offerDetail:SetWordWrap(true)
    f.dibsBtn = button(at, L["Dibs"], 140, 24, function()
        local row = selectedOfferRow()
        if not row then return end
        local res, why = ns.Offers.ToggleDib(me(), row.owner, row.itemID, ns.Util.Now())
        if res == "on" then ns.Print(F(L["Dibs set on {name}"], { name = row.name }))
        elseif res == "off" then ns.Print(F(L["Dibs removed from {name}"], { name = row.name }))
        elseif why == "limit" then ns.Print(L["Too many active dibs."])
        else ns.Print(L["That item is no longer on offer."]) end
        if res then ns.Events.Fire("OFFERS_CHANGED") end
        UI.Refresh()
    end)
    f.hideBtn = button(at, L["Remove from my list"], 150, 24, function()
        local row = selectedOfferRow()
        if row and ns.Offers.Hide(row.owner, row.itemID) then state.selectedOffer = nil end
        UI.Refresh()
    end)
    f.whisperBtn = button(at, L["Whisper owner"], 120, 24, function()
        local row = selectedOfferRow()
        if row then whisper(row.owner) end
    end)
    f.dibsBtn:SetPoint("BOTTOMLEFT", 0, 0)
    f.hideBtn:SetPoint("LEFT", f.dibsBtn, "RIGHT", 6, 0)
    f.whisperBtn:SetPoint("LEFT", f.hideBtn, "RIGHT", 6, 0)

    ns.Events.On("DATA_CHANGED", UI.Refresh)
    ns.Events.On("ITEM_INFO", function() if f:IsShown() then refreshDetail(); refreshOffers() end end)
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
pcall(loader.RegisterEvent, loader, "PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if bar.dirty and f and f:IsShown() then refreshBar() end   -- secure buttons could not be updated in combat
        return
    end
    local ok, err = pcall(buildMinimapButton)
    if not ok then ns.Util.ReportError(err) end
end)
