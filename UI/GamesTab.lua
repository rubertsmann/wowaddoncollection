local addonName, addon = ...

-- "Games" tab (feature 014): the coin flip and the guild leaderboard. Built lazily by UI/Window.lua (first window open).
-- Rules and records: Core/Play/Games.lua; coin motion: Core/Play/CoinFlip.lua; effects: UI/Animate.lua; rows: Model.
-- The flip is decided and STORED before the coin moves (Games.Flip); the animation only reveals it. While the coin is in
-- the air the Flip button is disabled and the leaderboard is not refreshed, so my new row does not spoil the result.
-- For fun only: the addon never reads, checks or moves real gold.
---@class GamesTabModule
local GamesTab = {}
addon.GamesTab = GamesTab

local Text, Format = addon.Text, addon.Locale.Format

local COIN_SIZE = 96
local COIN_BASE_Y = 10
local COIN_THICKNESS = 7
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAILS_EMBLEM = "Interface\\Icons\\INV_Crown_01"
local HEADS_FALLBACK = "Interface\\Icons\\INV_Misc_Head_Human_01"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local DEFAULT_STAKE = 10000   -- copper (1g)
local COIN_ICON = { gold = "Interface\\MoneyFrame\\UI-GoldIcon", silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon" }
local FEED_ROWS = 8

---@class GamesTabState
---@field pick "H"|"T"
---@field scope "week"|"all"
---@field flipping boolean the coin is in the air
---@field refreshPending boolean a refresh was asked for while flipping
---@field face "H"|"T"|nil the face the coin texture shows
GamesTab.state = { pick = "H", scope = "week", flipping = false, refreshPending = false }

---@type table widgets of the built tab (nil fields until Build ran)
local widgets = {}
GamesTab.widgets = widgets

------------------------------------------------------------------ formatting

-- copper -> "1g 50s 25c" in coin colours
---@param copper integer
---@return string
local function money(copper) return addon.Model.MoneyText(copper) end

-- "+1g 50s" with a green "+", "-25c" with a red "-", "0c" plain
---@param net integer copper
---@return string
local function signedGold(net)
    if net > 0 then return "|cff33ff99+|r" .. money(net) end
    if net < 0 then return "|cffff5555-|r" .. money(-net) end
    return money(0)
end
GamesTab.SignedGold = signedGold

---@param playerName string raw record key
---@param escapedName string
---@return string escaped display name (realm hidden on my realm)
local function displayName(playerName, escapedName)
    local shortName = addon.Utility.ShortName and addon.Utility.ShortName(playerName)
    return shortName and addon.Utility.Escape(shortName) or escapedName
end

---@return table ui settings (db.ui), or an empty table before Store.Init
local function settings() return (addon.db and addon.db.ui) or {} end

------------------------------------------------------------------ coin (2.5D: layered textures, flipped end over end)
-- A coin is drawn as a cylinder seen from the front: a dark "back" ellipse offset by the coin's thickness, a band joining
-- it to the front ellipse (the rim), and the front face (rim ring, inner disc, emblem). Flipping about the horizontal
-- axis squashes every ellipse to |cos angle| of its height; sin(angle) moves the back ellipse below or above the face, so
-- the rim shows while the coin is edge-on. Lighting dims the face as it turns away and a highlight glints at ~25 degrees.
-- Heads = the player's own portrait embossed in gold, tails = a crown. Circles come from a round mask; a client without
-- mask textures draws squares (still two distinct faces).

-- per face: rim and inner disc colours, emblem tint
local FACE_STYLE = {
    H = { rim = { 0.80, 0.58, 0.12 }, inner = { 0.98, 0.80, 0.30 }, emblem = { 1.00, 0.86, 0.45 } },
    T = { rim = { 0.74, 0.52, 0.10 }, inner = { 0.93, 0.72, 0.22 }, emblem = { 1.00, 0.80, 0.35 } },
}
local EDGE_COLOR = { 0.45, 0.30, 0.05 }

---@param owner table frame that owns the mask
---@param texture table
local function maskCircle(owner, texture)
    pcall(function()
        local mask = owner:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(texture)
        texture:AddMaskTexture(mask)
    end)
end

---@param owner table
---@param layer string draw layer
---@param subLevel integer
---@return table texture a round (masked) texture
local function disc(owner, layer, subLevel)
    local texture = owner:CreateTexture(nil, layer, nil, subLevel)
    texture:SetColorTexture(1, 1, 1, 1)
    maskCircle(owner, texture)
    return texture
end

---@param texture table
---@param path string
---@param fallback string
local function setTextureOr(texture, path, fallback)
    if texture:SetTexture(path) == false then texture:SetTexture(fallback) end
end

-- Puts my portrait on the heads emblem (it may not be loaded at build time, so this runs again before each flip).
local function refreshPortrait()
    local emblem = widgets.coinParts and widgets.coinParts.emblem.H
    if not emblem then return end
    local ok = SetPortraitTexture and pcall(SetPortraitTexture, emblem, "player")
    if not ok then setTextureOr(emblem, HEADS_FALLBACK, QUESTION_MARK) end
    emblem:SetDesaturated(true)
end

---@param coinHolder table
---@return table coin frame; its parts are in widgets.coinParts
local function buildCoin(coinHolder)
    local shadow = coinHolder:CreateTexture(nil, "BACKGROUND", nil, 1)
    shadow:SetColorTexture(0, 0, 0, 1); maskCircle(coinHolder, shadow)
    shadow:SetPoint("CENTER", coinHolder, "BOTTOM", 0, COIN_BASE_Y)
    local coin = CreateFrame("Frame", nil, coinHolder)
    coin:SetSize(COIN_SIZE, COIN_SIZE)
    local parts = { shadow = shadow, emblem = {}, rim = {}, inner = {} }
    parts.back = disc(coin, "BACKGROUND", 2)
    parts.band = coin:CreateTexture(nil, "BACKGROUND", nil, 3); parts.band:SetColorTexture(1, 1, 1, 1)
    for _, face in ipairs({ "H", "T" }) do
        parts.rim[face] = disc(coin, "ARTWORK", 1)
        parts.inner[face] = disc(coin, "ARTWORK", 2)
        local emblem = coin:CreateTexture(nil, "ARTWORK", nil, 3)
        maskCircle(coin, emblem)
        parts.emblem[face] = emblem
    end
    setTextureOr(parts.emblem.T, TAILS_EMBLEM, QUESTION_MARK)
    parts.emblem.T:SetDesaturated(true)
    parts.shine = disc(coin, "OVERLAY", 1); parts.shine:SetBlendMode("ADD")
    widgets.coinParts = parts
    widgets.coin = coin
    refreshPortrait()
    return coin
end

---@param texture table
---@param color number[]
---@param light number
local function shade(texture, color, light)
    texture:SetVertexColor(color[1] * light, color[2] * light, color[3] * light)
end

---@param pose CoinPose
local function applyPose(pose)
    local coin, parts = widgets.coin, widgets.coinParts
    local height = math.max(1, COIN_SIZE * pose.width)
    local edgeOffset = COIN_THICKNESS * (pose.edge or 0)   -- > 0: the rim shows below the face
    coin:ClearAllPoints()
    coin:SetPoint("BOTTOM", widgets.coinHolder, "BOTTOM", 0, COIN_BASE_Y + COIN_THICKNESS + pose.y)
    coin:SetSize(COIN_SIZE, COIN_SIZE)
    -- back ellipse and the band joining it to the face: the coin's edge
    parts.back:ClearAllPoints(); parts.back:SetSize(COIN_SIZE, height)
    parts.back:SetPoint("CENTER", coin, "CENTER", 0, -edgeOffset)
    parts.band:ClearAllPoints(); parts.band:SetSize(COIN_SIZE, math.max(0.01, math.abs(edgeOffset)))
    parts.band:SetPoint("CENTER", coin, "CENTER", 0, -edgeOffset / 2)
    shade(parts.back, EDGE_COLOR, 0.8); shade(parts.band, EDGE_COLOR, 1)
    -- the visible face: lit by how flat it faces the viewer
    local light = 0.5 + 0.5 * pose.width
    for _, face in ipairs({ "H", "T" }) do
        local visible = face == pose.face
        local style = FACE_STYLE[face]
        for _, part in ipairs({ { parts.rim[face], 1 }, { parts.inner[face], 0.86 }, { parts.emblem[face], 0.6 } }) do
            local texture, share = part[1], part[2]
            texture:SetShown(visible)
            texture:ClearAllPoints(); texture:SetSize(COIN_SIZE * share, height * share)
            texture:SetPoint("CENTER", coin, "CENTER", 0, 0)
        end
        if visible then
            shade(parts.rim[face], style.rim, light); shade(parts.inner[face], style.inner, light)
            shade(parts.emblem[face], style.emblem, light)
        end
    end
    -- a glint while the face is tilted ~25 degrees towards the light, none when flat or edge-on
    local glint = math.max(0, 1 - math.abs(math.abs(pose.edge or 0) - 0.42) / 0.2)
    parts.shine:ClearAllPoints(); parts.shine:SetSize(COIN_SIZE, height); parts.shine:SetPoint("CENTER", coin, "CENTER", 0, 0)
    parts.shine:SetVertexColor(1, 0.95, 0.8); parts.shine:SetAlpha(0.45 * glint)
    -- the shadow on the ground: smaller and fainter the higher the coin
    local lift = math.min(1, pose.y / addon.CoinFlip.HEIGHT)
    parts.shadow:SetSize(COIN_SIZE * (0.9 - 0.35 * lift), 12 * (1 - 0.3 * lift)); parts.shadow:SetAlpha(0.45 * (1 - 0.6 * lift))
    GamesTab.state.face = pose.face
end

---@param result FlipResult
local function land(result)
    applyPose(addon.CoinFlip.Pose(addon.CoinFlip.DURATION, result.outcome))
    local Animate = addon.Animate
    Animate.Pulse(widgets.coin, 1.15, 0.25)
    widgets.resultText:SetText(Format(result.won and Text["You won {gold}"] or Text["You lost {gold}"], { gold = money(result.stake) }))
    widgets.resultText:SetTextColor(result.won and 0.2 or 1, result.won and 1 or 0.33, result.won and 0.6 or 0.33)
    Animate.FadeIn(widgets.resultText, 0.3)
    if result.won then
        Animate.Glow(widgets.glow, 2)
        addon.Api.PlaySound(addon.Api.CoinSoundKit())
    else
        Animate.Shake(widgets.coinHolder, 4, 4)
    end
    GamesTab.state.flipping = false
    widgets.flipButton:Enable()
    GamesTab.state.refreshPending = false
    GamesTab.Refresh()
end

---@param refusal FlipRefusal|nil
---@return string
local function refusalText(refusal)
    if refusal == "readonly" then return Text["Saved data is read-only in this session."] end
    if refusal == "name" then return Text["Your character is not known yet."] end
    return Format(Text["Enter a stake from 1c to {max}"], { max = money(addon.Games.MAXIMUM_STAKE) })
end

-- The Flip button: decide and store the flip, announce it, then animate the reveal. Nothing happens while a coin flies.
---@return FlipResult|nil
function GamesTab.Flip()
    local state = GamesTab.state
    if state.flipping or not widgets.flipButton then return nil end
    local stake = GamesTab.ReadStake()
    local result, refusal = addon.Games.Flip(addon.Utility.Me(), stake, state.pick, addon.Utility.Now(), addon.Api.Random)
    if not result then
        widgets.resultText:SetText(refusalText(refusal)); widgets.resultText:SetTextColor(1, 0.33, 0.33)
        widgets.resultText:SetAlpha(1); widgets.resultText:Show()
        return nil
    end
    settings().lastStakeCopper = stake
    addon.Events.Fire("GAMES_CHANGED")                   -- announce (coalesced HELLO)
    state.flipping = true
    widgets.flipButton:Disable()
    widgets.resultText:SetText("")
    refreshPortrait()
    addon.Log.Debug("games.flip", "a coin was flipped", { stake = stake, won = result.won })
    addon.Animate.Tween("coin", addon.CoinFlip.DURATION, function(elapsed)
        applyPose(addon.CoinFlip.Pose(elapsed, result.outcome))
    end, function() land(result) end)
    return result
end

------------------------------------------------------------------ stake boxes (gold / silver / copper)

---@param box table
---@return integer|nil the number typed, 0 for an empty box, nil for anything else
local function boxNumber(box)
    local text = box:GetText() or ""
    if text == "" then return 0 end
    return tonumber(text)
end

-- The stake the three boxes hold, in copper, or nil when a box is out of range (Games.Flip then refuses it).
---@return integer|nil
function GamesTab.ReadStake()
    if not widgets.goldBox then return nil end
    return addon.Games.Money(boxNumber(widgets.goldBox), boxNumber(widgets.silverBox), boxNumber(widgets.copperBox))
end

-- Fills the three boxes from a copper amount (empty instead of 0, except copper when everything is 0).
---@param copper integer
function GamesTab.WriteStake(copper)
    local gold, silver, rest = addon.Games.SplitMoney(copper)
    widgets.goldBox:SetText(gold > 0 and tostring(gold) or "")
    widgets.silverBox:SetText(silver > 0 and tostring(silver) or "")
    widgets.copperBox:SetText((rest > 0 or (gold == 0 and silver == 0)) and tostring(rest) or "")
end

---@param parent table
---@param anchor table
---@param anchorPoint string
---@param x number
---@param width number
---@param maximumLetters integer
---@param icon string
---@return table editBox
local function moneyBox(parent, anchor, anchorPoint, x, width, maximumLetters, icon)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 20); box:SetPoint("LEFT", anchor, anchorPoint, x, 0)
    box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(maximumLetters)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); GamesTab.Flip() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTabPressed", function(self)
        local order = { widgets.goldBox, widgets.silverBox, widgets.copperBox }
        for index, other in ipairs(order) do
            if other == self then order[index % #order + 1]:SetFocus() return end
        end
    end)
    local coinIcon = parent:CreateTexture(nil, "ARTWORK")
    coinIcon:SetSize(13, 13); coinIcon:SetTexture(icon); coinIcon:SetPoint("LEFT", box, "RIGHT", 2, 0)
    box.icon = coinIcon
    return box
end

------------------------------------------------------------------ leaderboard and feed

---@param pick "H"|"T"
local function selectPick(pick)
    GamesTab.state.pick = pick
    widgets.headsButton:SetEnabled(pick ~= "H")
    widgets.tailsButton:SetEnabled(pick ~= "T")
end

---@param scope "week"|"all"
local function selectScope(scope)
    GamesTab.state.scope = scope
    settings().gamesScope = scope
    widgets.weekButton:SetEnabled(scope ~= "week")
    widgets.allButton:SetEnabled(scope ~= "all")
    GamesTab.Refresh()
end

-- Redraws the leaderboard, the feed and last week's winner (deferred while the coin flies).
function GamesTab.Refresh()
    if not widgets.leaderboardList then return end
    if GamesTab.state.flipping then GamesTab.state.refreshPending = true return end
    local now = addon.Utility.Now()
    local records = addon.Games.AllRecords()
    local myName = addon.Utility.Me()
    local rows = addon.Model.BuildLeaderboardRows(records, GamesTab.state.scope, addon.Games.PeriodKey(now), myName)
    widgets.leaderboardList:SetData(rows)
    widgets.emptyText:SetShown(#rows == 0)
    widgets.feedList:SetData(addon.Model.BuildFlipFeedRows(records, myName, 15))
    local winner = addon.Model.PreviousWinner(records, addon.Games.PreviousPeriodKey(now))
    widgets.winnerText:SetText(winner and Format(Text["Last week's winner: {name} ({gold})"],
        { name = displayName(winner.nameRaw, winner.name), gold = signedGold(winner.net) }) or "")
end

---@param parent table
---@param width number
---@param justify string
---@param x number
---@return table fontString
local function column(parent, width, justify, x)
    local fontString = addon.UI.Widgets.CreateFontString(parent, "GameFontHighlightSmall", justify)
    fontString:SetWidth(width)
    fontString:SetPoint("LEFT", parent, "LEFT", x, 0)
    return fontString
end

-- column layout (x, width) of the leaderboard, shared by the header and the rows
local COLUMNS = { rank = { 0, 24 }, name = { 30, 150 }, net = { 182, 72 }, won = { 256, 66 }, lost = { 324, 66 }, flips = { 392, 38 } }

---@param parent table
---@return table row
local function createLeaderboardRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.background = row:CreateTexture(nil, "BACKGROUND"); row.background:SetAllPoints()
    row.background:SetColorTexture(0.2, 0.5, 1, 0.25); row.background:Hide()
    row.rank = column(row, COLUMNS.rank[2], "RIGHT", COLUMNS.rank[1])
    row.name = column(row, COLUMNS.name[2], "LEFT", COLUMNS.name[1])
    row.net = column(row, COLUMNS.net[2], "RIGHT", COLUMNS.net[1])
    row.won = column(row, COLUMNS.won[2], "RIGHT", COLUMNS.won[1])
    row.lost = column(row, COLUMNS.lost[2], "RIGHT", COLUMNS.lost[1])
    row.flips = column(row, COLUMNS.flips[2], "RIGHT", COLUMNS.flips[1])
    return row
end

---@param row table
---@param entry LeaderboardRow
local function fillLeaderboardRow(row, entry)
    row.background:SetShown(entry.mine)
    row.rank:SetText(tostring(entry.rank))
    row.name:SetText(displayName(entry.nameRaw, entry.name))
    row.net:SetText(signedGold(entry.net))
    row.won:SetText(money(entry.won))
    row.lost:SetText(money(entry.lost))
    row.flips:SetText(entry.wins .. "/" .. entry.losses)
end

---@param parent table
---@return table row
local function createFeedRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.name = column(row, 180, "LEFT", 4)
    row.net = column(row, 90, "RIGHT", 188)
    row.when = column(row, 140, "RIGHT", 286)
    return row
end

---@param row table
---@param entry FlipFeedRow
local function fillFeedRow(row, entry)
    row.name:SetText(displayName(entry.nameRaw, entry.name))
    row.net:SetText(signedGold(entry.net))
    row.when:SetText("|cffaaaaaa" .. addon.UI.Widgets.TimeAgo(entry.t) .. "|r")
end

------------------------------------------------------------------ build

---@param tabFrame table the tab's frame (about 756 x 450)
function GamesTab.Build(tabFrame)
    local Widgets = addon.UI.Widgets
    local state = GamesTab.state
    state.scope = (settings().gamesScope == "all") and "all" or "week"

    -- left column: the coin
    local title = Widgets.CreateFontString(tabFrame, "GameFontNormalLarge", "CENTER")
    title:SetPoint("TOPLEFT", 0, -4); title:SetWidth(290); title:SetText(Text["Coin flip"])

    local coinHolder = CreateFrame("Frame", nil, tabFrame)
    coinHolder:SetSize(120, 200); coinHolder:SetPoint("TOPLEFT", 85, -28)
    widgets.coinHolder = coinHolder
    local glow = coinHolder:CreateTexture(nil, "BACKGROUND", nil, 0)
    glow:SetSize(COIN_SIZE * 1.6, COIN_SIZE * 1.6); glow:SetTexture(GLOW_TEXTURE); glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0.2); glow:SetAlpha(0); glow:Hide()
    widgets.glow = glow
    local coin = buildCoin(coinHolder)
    glow:SetPoint("CENTER", coin, "CENTER", 0, 0)
    state.face = nil
    applyPose(addon.CoinFlip.Pose(addon.CoinFlip.DURATION, "H"))

    widgets.headsButton = Widgets.CreateButton(tabFrame, Text["Heads"], 100, 22, function() selectPick("H") end)
    widgets.headsButton:SetPoint("TOPLEFT", 40, -236)
    widgets.tailsButton = Widgets.CreateButton(tabFrame, Text["Tails"], 100, 22, function() selectPick("T") end)
    widgets.tailsButton:SetPoint("LEFT", widgets.headsButton, "RIGHT", 10, 0)

    local stakeLabel = Widgets.CreateFontString(tabFrame, "GameFontHighlight")
    stakeLabel:SetPoint("TOPLEFT", 20, -272); stakeLabel:SetText(Text["Stake"])
    widgets.goldBox = moneyBox(tabFrame, stakeLabel, "RIGHT", 10, 62, 6, COIN_ICON.gold)
    widgets.silverBox = moneyBox(tabFrame, widgets.goldBox.icon, "RIGHT", 10, 28, 2, COIN_ICON.silver)
    widgets.copperBox = moneyBox(tabFrame, widgets.silverBox.icon, "RIGHT", 10, 28, 2, COIN_ICON.copper)
    GamesTab.WriteStake(settings().lastStakeCopper or DEFAULT_STAKE)

    widgets.flipButton = Widgets.CreateButton(tabFrame, Text["Flip"], 210, 26, function() GamesTab.Flip() end)
    widgets.flipButton:SetPoint("TOPLEFT", 40, -302)

    widgets.resultText = Widgets.CreateFontString(tabFrame, "GameFontNormalLarge", "CENTER")
    widgets.resultText:SetPoint("TOPLEFT", 0, -340); widgets.resultText:SetWidth(290)

    local note = Widgets.CreateFontString(tabFrame, "GameFontDisableSmall", "CENTER")
    note:SetPoint("BOTTOMLEFT", 0, 4); note:SetWidth(290); note:SetText(Text["For fun only: no gold changes hands."])

    -- right column: leaderboard and feed
    local right = CreateFrame("Frame", nil, tabFrame)
    right:SetPoint("TOPLEFT", 310, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
    widgets.winnerText = Widgets.CreateFontString(right, "GameFontNormal")
    widgets.winnerText:SetPoint("TOPLEFT", 0, -4); widgets.winnerText:SetWidth(440)
    widgets.weekButton = Widgets.CreateButton(right, Text["This week"], 100, 22, function() selectScope("week") end)
    widgets.weekButton:SetPoint("TOPLEFT", 0, -22)
    widgets.allButton = Widgets.CreateButton(right, Text["All time"], 100, 22, function() selectScope("all") end)
    widgets.allButton:SetPoint("LEFT", widgets.weekButton, "RIGHT", 4, 0)

    local header = CreateFrame("Frame", nil, right)
    header:SetSize(430, 16); header:SetPoint("TOPLEFT", 0, -50)
    local headerLabels = { name = Text["Player"], net = Text["Net"], won = Text["Won"], lost = Text["Lost"], flips = Text["Flips"] }
    for columnKey, label in pairs(headerLabels) do
        local headerText = column(header, COLUMNS[columnKey][2], columnKey == "name" and "LEFT" or "RIGHT", COLUMNS[columnKey][1])
        headerText:SetFontObject("GameFontNormalSmall"); headerText:SetText(label)
    end

    widgets.leaderboardList = Widgets.CreateScrollList(right, 446, Widgets.ROW_HEIGHT * 9, createLeaderboardRow, fillLeaderboardRow)
    widgets.leaderboardList:SetPoint("TOPLEFT", 0, -68)
    widgets.emptyText = Widgets.CreateFontString(right, "GameFontDisable", "CENTER")
    widgets.emptyText:SetPoint("TOP", widgets.leaderboardList, "TOP", 0, -60); widgets.emptyText:SetText(Text["No flips yet"])

    local feedTitle = Widgets.CreateFontString(right, "GameFontNormal")
    feedTitle:SetPoint("TOPLEFT", 0, -258); feedTitle:SetText(Text["Recent flips"])
    widgets.feedList = Widgets.CreateScrollList(right, 446, Widgets.ROW_HEIGHT * FEED_ROWS, createFeedRow, fillFeedRow)
    widgets.feedList:SetPoint("TOPLEFT", 0, -276)

    selectPick(state.pick)
    selectScope(state.scope)
end
