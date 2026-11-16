local ADDON, ns = ...

-- Feature 010: tell the player about new orders (and news on their own orders) while the window is closed:
-- number on the minimap button and the Orders tab, letter icon, sound, chat line, screen message, taskbar flash.
-- What counts as new is decided in Core/Notify.lua (pure); this file only shows it and holds the options panel.
local Alerts = {}
ns.Alerts = Alerts

local L, F = ns.L, ns.Locale.Fmt
local N = ns.Notify

local st = { started = false, prev = nil, lastLoud = -math.huge }

local function me() return ns.Store.db.me or ns.Api.GetPlayerInfo().name end
local function ui() return ns.db and ns.db.ui end
local function opt(key) return N.Get(ui(), key) end

local function ordersVisible()
    return ns.UI and ns.UI.OrdersVisible and ns.UI.OrdersVisible() or false
end

local function plainName(o)
    -- peer-supplied recipe names never reach chat as markup (Model.ChatText strips | [ ] and line breaks)
    return ns.Model.ChatText(nil, ns.Model.OrderRecipeName(ns.Store, o))
end

local function describe(it)
    local o = it.order
    if it.kind == "new" then
        return F(L["New order: {qty}x {name} from {who}"], { qty = o.qty, name = plainName(o), who = ns.Util.ShortName(o.requester) })
    elseif it.kind == "claimed" then
        local who = {}
        for _, c in ipairs(ns.orders:Claimers(o)) do if c ~= me() then who[#who + 1] = ns.Util.ShortName(c) end end
        return F(L["{who} will craft your order {name}"], { who = table.concat(who, ", "), name = plainName(o) })
    end
    return F(L["{who} finished your order {name}"], { who = ns.Util.ShortName(o.closedBy or "?"), name = plainName(o) })
end

local function playSound()
    local name = opt("soundName")
    local id
    for _, s in ipairs(N.SOUNDS) do if s[1] == name then id = (SOUNDKIT and SOUNDKIT[name]) or s[2] end end
    if id and PlaySound then pcall(PlaySound, id, "Master") end
end
Alerts.PlaySound = playSound

local function screenMessage(text)
    local ok = false
    if RaidNotice_AddMessage and RaidWarningFrame then
        ok = pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = 1, g = 0.82, b = 0 })
    end
    if not ok and UIErrorsFrame then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.82, 0) end
end

local function alert(fresh, nowT)
    if opt("chat") then
        for i, it in ipairs(fresh) do
            if i > 3 then
                ns.Print(F(L["... and {n} more on the order board"], { n = #fresh - 3 }))
                break
            end
            ns.Print(describe(fresh[i]))
        end
    end
    if nowT - st.lastLoud < N.THROTTLE then return end   -- a login sync can bring many orders at once: one ping
    st.lastLoud = nowT
    if opt("sound") then playSound() end
    if opt("screen") then
        screenMessage(#fresh == 1 and describe(fresh[1]) or F(L["{n} new on the order board"], { n = #fresh }))
    end
    if opt("flash") and FlashClientIcon then pcall(FlashClientIcon) end
end

-- Options "Test all": every switched-on effect once with a sample text, the badge/letter for 8 s. The taskbar flash
-- comes after 3 s (it is only visible while the game is in the background, so there is time to switch windows).
local testToken = 0
function Alerts.Test()
    local text = L["TalentShare test notification"]
    if opt("chat") then ns.Print(text) end
    if opt("sound") then playSound() end
    if opt("screen") then screenMessage(text) end
    if ns.UI and ns.UI.SetNotice and (opt("badge") or opt("icon")) then
        testToken = testToken + 1
        local token = testToken
        ns.UI.SetNotice(1, opt("icon"), not opt("badge"))
        C_Timer.After(8, function()
            if token ~= testToken then return end
            ns.UI.SetNotice(0, false)
            Alerts.Update()   -- back to the real state
        end)
    end
    if opt("flash") and FlashClientIcon then C_Timer.After(3, function() pcall(FlashClientIcon) end) end
end

-- Recompute the unseen list; alert about items that are new since the last call (never on the first call of a session:
-- what was unseen at logout was already announced then, the badge still shows it).
function Alerts.Update()
    local db = ui()
    if not st.started or not db or not ns.orders then return end
    if db.notifySeen == nil then db.notifySeen = N.MarkSeen(ns.orders, nil) end   -- first run: the existing board is not news
    if ordersVisible() then db.notifySeen = N.MarkSeen(ns.orders, db.notifySeen) end
    local list = N.Unseen(ns.Store, ns.orders, me(), db.notifySeen, { scope = opt("scope"), mine = opt("mine") })
    local fresh, now = N.Fresh(st.prev, list)
    local primed = st.prev ~= nil
    st.prev = now
    if ns.UI and ns.UI.SetNotice then ns.UI.SetNotice(#list, opt("icon"), not opt("badge")) end
    if primed and #fresh > 0 then
        ns.Debug.Log("notify", #fresh, #list)
        alert(fresh, GetTime and GetTime() or 0)
    end
end

-- The player looks at the Orders tab.
function Alerts.Seen()
    local db = ui()
    if not db or not ns.orders then return end
    db.notifySeen = N.MarkSeen(ns.orders, db.notifySeen)
    if st.started then
        st.prev = {}   -- nothing is unseen now; what comes later is fresh again
        if ns.UI and ns.UI.SetNotice then ns.UI.SetNotice(0, false) end
    end
end

function Alerts.Start()
    if st.started then return end
    st.started = true
    Alerts.Update()
end

ns.Events.On("DATA_CHANGED", function(kind)
    if kind == "orders" or kind == "chars" or kind == nil then Alerts.Update() end
end)

------------------------------------------------------------------ options panel

local panel, category

local function scopeLabel(s)
    local map = { profession = L["Orders for my professions"], known = L["Orders for recipes I know"], all = L["All orders"] }
    return map[s] or s
end

local function soundLabel(name)
    local map = { IG_PLAYER_INVITE = L["Invite"], MAP_PING = L["Map ping"], AUCTION_WINDOW_OPEN = L["Auction house"],
        READY_CHECK = L["Ready check"] }
    return map[name] or name
end

local function cycle(list, cur, field)
    for i, v in ipairs(list) do
        local key = field and v[field] or v
        if key == cur then
            local nx = list[i % #list + 1]
            return field and nx[field] or nx
        end
    end
    return field and list[1][field] or list[1]
end

local function buildPanel()
    panel = CreateFrame("Frame", ns.FRAME .. "OptionsPanel")
    panel.name = ns.TITLE
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16); title:SetText(ns.TITLE .. " - " .. L["Notifications"])
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6); sub:SetWidth(560); sub:SetJustifyH("LEFT")
    sub:SetText(L["How TalentShare tells you about new orders on the board and news on your own orders."])

    local y, checks = -64, {}
    local function check(key, label, tip)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(26, 26); cb:SetPoint("TOPLEFT", 16, y)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText(label)
        cb:SetScript("OnClick", function(self)
            N.Set(ui(), key, self:GetChecked() and true or false)
            Alerts.Update()
        end)
        if tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label)
                GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        checks[key] = cb
        y = y - 28
        return cb
    end
    check("badge", L["Number of new orders on the minimap button and the Orders tab"])
    check("icon", L["Minimap button shows a letter while something is new"])
    check("sound", L["Play a sound"])
    local soundBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    soundBtn:SetSize(150, 22); soundBtn:SetPoint("LEFT", checks.sound, "RIGHT", 220, 0)
    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(70, 22); testBtn:SetPoint("LEFT", soundBtn, "RIGHT", 4, 0); testBtn:SetText(L["Test"])
    testBtn:SetScript("OnClick", playSound)
    check("chat", L["Chat message"])
    check("screen", L["Message in the middle of the screen"])
    check("flash", L["Flash the game icon in the taskbar"], L["Only visible while the game is in the background."])
    check("mine", L["My orders: tell me when someone claims or finishes them"])

    local scopeLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scopeLbl:SetPoint("TOPLEFT", 20, y - 10); scopeLbl:SetText(L["Tell me about"])
    local scopeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    scopeBtn:SetSize(220, 22); scopeBtn:SetPoint("LEFT", scopeLbl, "RIGHT", 10, 0)
    local scopeTip = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scopeTip:SetPoint("TOPLEFT", scopeLbl, "BOTTOMLEFT", 0, -10); scopeTip:SetWidth(560); scopeTip:SetJustifyH("LEFT")
    scopeTip:SetText(L["My professions: also orders for recipes of a profession you have that you do not know yet."])

    local testAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testAll:SetSize(220, 24); testAll:SetPoint("TOPLEFT", scopeTip, "BOTTOMLEFT", 0, -16)
    testAll:SetText(L["Test all notifications"])
    testAll:SetScript("OnClick", function() Alerts.Test() end)
    testAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L["Test all notifications"])
        GameTooltip:AddLine(L["Shows every switched-on effect once. The taskbar flash follows after 3 seconds: switch to another window to see it."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    testAll:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function refresh()
        for key, cb in pairs(checks) do cb:SetChecked(opt(key)) end
        scopeBtn:SetText(scopeLabel(opt("scope")))
        soundBtn:SetText(soundLabel(opt("soundName")))
        soundBtn:SetEnabled(opt("sound")); testBtn:SetEnabled(opt("sound"))
    end
    scopeBtn:SetScript("OnClick", function()
        N.Set(ui(), "scope", cycle(N.SCOPES, opt("scope"))); refresh(); Alerts.Update()
    end)
    soundBtn:SetScript("OnClick", function()
        N.Set(ui(), "soundName", cycle(N.SOUNDS, opt("soundName"), 1)); refresh(); playSound()
    end)
    for _, cb in pairs(checks) do cb:HookScript("OnClick", refresh) end
    panel:SetScript("OnShow", refresh)
    panel.refresh = refresh

    -- Settings panel of the game (modern API first, then the old interface options), else a plain window.
    local ok = false
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        ok = pcall(function()
            category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(category)
        end)
        if not ok then category = nil end
    end
    if not ok and InterfaceOptions_AddCategory then ok = pcall(InterfaceOptions_AddCategory, panel) end
    panel.registered = ok
    if not ok then
        panel:SetParent(UIParent); panel:SetSize(620, 420); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG")
        local bg = panel:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.9)
        local x = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -2, -2)
        panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        table.insert(UISpecialFrames, panel:GetName())
        panel:Hide()
    end
end

function Alerts.OpenOptions()
    if not panel then
        local ok, err = pcall(buildPanel)
        if not ok then ns.Util.ReportError(err) return end
    end
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID
        if pcall(Settings.OpenToCategory, id) then return end
    end
    if panel.registered and InterfaceOptionsFrame_OpenToCategory then
        pcall(InterfaceOptionsFrame_OpenToCategory, panel)
        pcall(InterfaceOptionsFrame_OpenToCategory, panel)   -- the old frame needs two calls the first time
        return
    end
    panel:SetShown(not panel:IsShown())
end

ns.Slash.options = function() Alerts.OpenOptions() end

-- Register the panel at login, so it is in the game's AddOns options list without opening it from here first.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if not panel then
        local ok, err = pcall(buildPanel)
        if not ok then ns.Util.ReportError(err) end
    end
end)
