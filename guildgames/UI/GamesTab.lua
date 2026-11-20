local addonName, addon = ...

-- The games (feature 014): the coin flip, the slot machine, survivor (UI/SurvivorArena.lua) and their guild leaderboards. Built lazily by UI/Window.lua (first open).
-- Rules and records: Core/Data/Games.lua; coin motion: Core/Minigames/CoinFlip.lua; effects: UI/Animate.lua; rows: Model.
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
-- header icon per game (the dev probe checks they exist)
local GAME_ICONS = { coin = "Interface\\Icons\\INV_Misc_Coin_01",
    slots = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    survivor = "Interface\\Icons\\Spell_Holy_DivineIntervention",
    caught = "Interface\\Icons\\Ability_Hunter_BeastTaming" }
GamesTab.GAME_ICONS = GAME_ICONS
-- the game switch: the casino games (Games.ORDER, each with a casino leaderboard) and AZEcaught (feature 018, its own
-- panel with its own guild view; not a casino game, so not in Games.ORDER)
---@return string[]
local function switchOrder()
    local order = {}
    for index, gameKey in ipairs(addon.Games.ORDER) do order[index] = gameKey end
    order[#order + 1] = "caught"
    return order
end
GamesTab.SwitchOrder = switchOrder

---@class GamesTabState
---@field pick "H"|"T"
---@field scope "week"|"all"
---@field flipping boolean the coin is in the air
---@field refreshPending boolean a refresh was asked for while flipping
---@field face "H"|"T"|nil the face the coin texture shows
---@field game GameKey the selected game (its panel and its own leaderboard)
GamesTab.state = { pick = "H", scope = "week", game = "coin", flipping = false, refreshPending = false }

---@type table widgets of the built tab (nil fields until Build ran)
local widgets = {}
GamesTab.widgets = widgets

------------------------------------------------------------------ formatting

-- copper -> "1g 50s 25c" in coin colours
---@param copper integer
---@return string
local money = addon.Model.MoneyText

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
    local shortName = addon.Utility.ShortName(playerName)
    return shortName and addon.Utility.Escape(shortName) or escapedName
end

local settings = addon.UIHelpers.Settings

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
GamesTab.MaskCircle = maskCircle
GamesTab.GLOW_TEXTURE = GLOW_TEXTURE

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

-- Puts my portrait on the heads emblem (it may not be loaded at build time, so this runs again before each flip).
local function refreshPortrait()
    local emblem = widgets.coinParts and widgets.coinParts.emblem.H
    if not emblem then return end
    local ok = SetPortraitTexture and pcall(SetPortraitTexture, emblem, "player")
    if not ok then addon.UIHelpers.SetTextureOr(emblem, HEADS_FALLBACK, QUESTION_MARK) end
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
    addon.UIHelpers.SetTextureOr(parts.emblem.T, TAILS_EMBLEM, QUESTION_MARK)
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

------------------------------------------------------------------ coin effects: idle rocking, flight trail, landing

-- the coin's resting centre, relative to coinHolder's centre (coinHolder is 200 high, the coin sits near its bottom)
local COIN_REST_Y = COIN_BASE_Y + COIN_THICKNESS + COIN_SIZE / 2 - 100
local TRAIL_LENGTH = 8
local WIN_COLOR, LOSS_COLOR = { 0.35, 1, 0.55 }, { 1, 0.35, 0.3 }

-- While no flip runs, the coin hovers and rocks gently so its rim and a glint catch the light.
---@param elapsedSeconds number
local function idleCoin(elapsedSeconds)
    if GamesTab.state.flipping or not widgets.coin then return end
    local idle = widgets.idle
    idle.time = idle.time + elapsedSeconds * addon.Animate.speed
    local tilt = 0.28 * math.sin(idle.time * 0.9)
    applyPose({ face = GamesTab.state.face or "H", width = math.cos(tilt), edge = math.sin(tilt), y = 4 + 4 * math.sin(idle.time * 1.7) })
end

-- Star ghosts follow the coin through the air: each one shows where the coin was a few frames ago.
---@param y number|nil the coin's height above its rest (nil clears the trail)
local function updateTrail(y)
    local trail = widgets.trail
    if not trail then return end
    if not y then
        trail.history = {}
        for _, ghost in ipairs(trail) do ghost:Hide() end
        return
    end
    table.insert(trail.history, 1, y)
    trail.history[TRAIL_LENGTH * 2 + 1] = nil
    for index, ghost in ipairs(trail) do
        local pastY = trail.history[index * 2]
        if pastY and pastY > 6 then
            local fade = 1 - index / (TRAIL_LENGTH + 1)
            ghost:ClearAllPoints()
            ghost:SetPoint("CENTER", widgets.coinHolder, "CENTER", 0, COIN_REST_Y + pastY)
            ghost:SetSize(COIN_SIZE * 0.55 * fade, COIN_SIZE * 0.55 * fade)
            ghost:SetAlpha(0.55 * fade)
            ghost:Show()
        else
            ghost:Hide()
        end
    end
end

-- Win: a shockwave ring, a burst of gold sparkles, the coin glows and "+1g" floats up.
-- Loss: a puff of dust falls from the coin, it shakes, and "-1g" sinks in red.
---@param result FlipResult
local function landingEffects(result)
    local Animate, holder, effects = addon.Animate, widgets.coinHolder, widgets.effects
    if result.won then
        Animate.Glow(widgets.glow, 2)
        Animate.Ring("coin", effects, widgets.coinCentre, COIN_SIZE * 0.8, COIN_SIZE * 2.6)
        Animate.Burst("coin", effects, holder, 0, COIN_REST_Y, { count = 28, speed = 190, gravity = 260, size = 16 })
        Animate.FloatText("coin", widgets.floatText, holder, 0, COIN_REST_Y + COIN_SIZE / 2 + 8, "+" .. money(result.stake), WIN_COLOR)
    else
        Animate.Shake(holder, 4, 4)
        Animate.Burst("coin", effects, holder, 0, COIN_REST_Y - COIN_SIZE / 3,
            { count = 14, speed = 70, gravity = 120, size = 10, color = { 0.55, 0.5, 0.45 }, duration = 0.9, spread = math.pi * 0.9 })
        Animate.FloatText("coin", widgets.floatText, holder, 0, COIN_REST_Y + COIN_SIZE / 2 + 8, "-" .. money(result.stake), LOSS_COLOR, -26, 1.4)
    end
end

---@param result FlipResult
local function land(result)
    applyPose(addon.CoinFlip.Pose(addon.CoinFlip.DURATION, result.outcome))
    updateTrail(nil)
    local Animate = addon.Animate
    Animate.Pulse(widgets.coin, 1.15, 0.25)
    widgets.resultText:SetText(Format(result.won and Text["You won {gold}"] or Text["You lost {gold}"], { gold = money(result.stake) }))
    widgets.resultText:SetTextColor(result.won and 0.2 or 1, result.won and 1 or 0.33, result.won and 0.6 or 0.33)
    Animate.FadeIn(widgets.resultText, 0.3)
    addon.Log.Protected("games.effects", "a landing effect failed", landingEffects, result)   -- never blocks the unlock below
    if result.won then addon.Api.PlaySound(addon.Api.CoinSoundKit()) end
    GamesTab.state.flipping = false
    widgets.flipButton:Enable()
    GamesTab.SetBusy(false)   -- unlocks the game selector and runs the refresh that waited
end

---@param refusal FlipRefusal|nil
---@return string
local function refusalText(refusal)
    local commonText = addon.Model.CommonRefusalText(refusal, addon.Utility.Me())
    if commonText then return commonText end
    if refusal == "name" then return Text["Your character is not known yet."] end
    return Format(Text["Enter a stake from 1c to {max}"], { max = money(addon.Games.MAXIMUM_STAKE) })
end
GamesTab.RefusalText = refusalText

-- Whether any game is animating (the board waits, the game selector is locked).
---@return boolean
function GamesTab.IsBusy()
    return GamesTab.state.flipping or addon.SlotMachine.state.spinning or addon.SurvivorArena.state.run ~= nil or false
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
    GamesTab.SetBusy(true)
    widgets.flipButton:Disable()
    widgets.resultText:SetText("")
    refreshPortrait()
    addon.Log.Debug("games.flip", "a coin was flipped", { stake = stake, won = result.won })
    addon.Animate.Tween("coin", addon.CoinFlip.DURATION, function(elapsed)
        local pose = addon.CoinFlip.Pose(elapsed, result.outcome)
        applyPose(pose)
        updateTrail(pose.y)
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

---@class StakeRow
---@field goldBox table
---@field silverBox table
---@field copperBox table
---@field Read fun(): integer|nil copper, nil when a box is out of range
---@field Write fun(copper: integer)
---@field SetEnabled fun(enabled: boolean)

---@param parent table
---@param anchor table
---@param x number
---@param width number
---@param maximumLetters integer
---@param icon string
---@param row StakeRow
---@param onEnter fun()
---@return table editBox
local function moneyBox(parent, anchor, x, width, maximumLetters, icon, row, onEnter)
    local createEditBox = addon.UI.Widgets.CreateEditBox
    local box = createEditBox and createEditBox(parent, width) or CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 18); box:SetPoint("LEFT", anchor, "RIGHT", x, 0)
    box:SetAutoFocus(false); box:SetNumeric(true); box:SetMaxLetters(maximumLetters)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); onEnter() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTabPressed", function(self)
        local order = { row.goldBox, row.silverBox, row.copperBox }
        for index, other in ipairs(order) do
            if other == self then order[index % #order + 1]:SetFocus() return end
        end
    end)
    local coinIcon = parent:CreateTexture(nil, "ARTWORK")
    coinIcon:SetSize(13, 13); coinIcon:SetTexture(icon); coinIcon:SetPoint("LEFT", box, "RIGHT", 2, 0)
    box.icon = coinIcon
    return box
end

-- "Stake [gold] g [silver] s [copper] c" at TOPLEFT (x, y) of parent. Enter in any box calls onEnter.
---@param parent table
---@param x number
---@param y number
---@param onEnter fun()
---@return StakeRow
function GamesTab.CreateStakeRow(parent, x, y, onEnter)
    local row = {}
    local label = addon.UI.Widgets.CreateFontString(parent, "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", x, y - 2); label:SetText(Text["Stake"])
    row.goldBox = moneyBox(parent, label, 10, 62, 6, COIN_ICON.gold, row, onEnter)
    row.silverBox = moneyBox(parent, row.goldBox.icon, 10, 28, 2, COIN_ICON.silver, row, onEnter)
    row.copperBox = moneyBox(parent, row.silverBox.icon, 10, 28, 2, COIN_ICON.copper, row, onEnter)
    function row.Read() return addon.Games.Money(boxNumber(row.goldBox), boxNumber(row.silverBox), boxNumber(row.copperBox)) end
    function row.Write(copper)
        local gold, silver, rest = addon.Games.SplitMoney(copper)
        row.goldBox:SetText(gold > 0 and tostring(gold) or "")
        row.silverBox:SetText(silver > 0 and tostring(silver) or "")
        row.copperBox:SetText((rest > 0 or (gold == 0 and silver == 0)) and tostring(rest) or "")
    end
    function row.SetEnabled(enabled)
        for _, box in ipairs({ row.goldBox, row.silverBox, row.copperBox }) do
            if box.SetEnabled then box:SetEnabled(enabled) end
        end
    end
    return row
end

-- The coin flip's stake, in copper, or nil when a box is out of range (Games.Flip then refuses it).
---@return integer|nil
function GamesTab.ReadStake() return widgets.coinStake and widgets.coinStake.Read() or nil end

---@param copper integer
function GamesTab.WriteStake(copper) widgets.coinStake.Write(copper) end

------------------------------------------------------------------ game selector, leaderboard and feed

-- A choice button is selected (underlined, not clickable) or not; buttons from other widget sets just enable/disable.
---@param button table
---@param selected boolean
local function markSelected(button, selected)
    button:SetEnabled(not selected)
    if button.SetSelected then button:SetSelected(selected) end
    if type(button.gameIcon) == "table" then button.gameIcon:SetAlpha(selected and 1 or 0.6) end
end

---@param pick "H"|"T"
local function selectPick(pick)
    GamesTab.state.pick = pick
    markSelected(widgets.headsButton, pick == "H")
    markSelected(widgets.tailsButton, pick == "T")
end

---@param scope "week"|"all"
local function selectScope(scope)
    GamesTab.state.scope = scope
    settings().gamesScope = scope
    markSelected(widgets.weekButton, scope == "week")
    markSelected(widgets.allButton, scope == "all")
    GamesTab.Refresh()
    GamesTab.RevealBoard()
end

-- Locks or unlocks the game selector while a game animates; unlocking runs the refresh that waited.
---@param busy boolean
function GamesTab.SetBusy(busy)
    for gameKey, button in pairs(widgets.gameButtons or {}) do
        button:SetEnabled(not busy and gameKey ~= GamesTab.state.game)
        if button.SetSelected then button:SetSelected(gameKey == GamesTab.state.game) end
        if type(button.gameIcon) == "table" then button.gameIcon:SetDesaturated(busy and gameKey ~= GamesTab.state.game) end
    end
    if not busy and not GamesTab.IsBusy() then
        GamesTab.state.refreshPending = false
        GamesTab.Refresh()
    end
end

-- Shows one game's panel (it fades in) and its own leaderboard. Ignored while a game animates.
---@param gameKey GameKey
function GamesTab.SelectGame(gameKey)
    if GamesTab.IsBusy() or not widgets.panels or not widgets.panels[gameKey] then return end
    local changed = GamesTab.state.game ~= gameKey
    GamesTab.state.game = gameKey
    settings().gameKey = gameKey
    for key, panel in pairs(widgets.panels) do panel:SetShown(key == gameKey) end
    for key, button in pairs(widgets.gameButtons) do markSelected(button, key == gameKey) end
    if changed then addon.Animate.FadeIn(widgets.panels[gameKey], 0.25) end
    GamesTab.Refresh()
    if changed then GamesTab.RevealBoard() end
end

-- per game: feed title, empty-board text and the plays column header
---@param gameKey GameKey
---@return { feed: string, empty: string, plays: string }
local function boardLabels(gameKey)
    if gameKey == "slots" then return { feed = Text["Recent spins"], empty = Text["No spins yet"], plays = Text["Spins"] } end
    if gameKey == "survivor" then return { feed = Text["Recent runs"], empty = Text["No runs yet"], plays = Text["Runs"] } end
    return { feed = Text["Recent flips"], empty = Text["No flips yet"], plays = Text["Flips"] }
end

-- The money pool (feature 018) in the header, next to the game switch.
function GamesTab.RefreshBalance()
    if not widgets.balanceText then return end
    local balance = addon.Wallet.Balance(addon.Utility.Me())
    widgets.balanceText:SetText((balance < 0 and "|cffff5555-|r" or "") .. money(balance))
end

-- Redraws the selected game's leaderboard, feed and last week's winner (deferred while a game animates).
function GamesTab.Refresh()
    if not widgets.leaderboardList then return end
    GamesTab.RefreshBalance()
    if GamesTab.IsBusy() then GamesTab.state.refreshPending = true return end
    local gameKey = GamesTab.state.game
    local now = addon.Utility.Now()
    local records = addon.Games.AllRecords()
    local myName = addon.Utility.Me()
    if gameKey == "caught" then
        -- AZEcaught has its own guild view in its panel; the sidebar shows last week's best and a pointer to it
        widgets.leaderboardList:SetData({}); widgets.feedList:SetData({})
        widgets.emptyText:SetText(Text["The guild's companions are in the Guild view of AZEcaught."]); widgets.emptyText:SetShown(true)
        widgets.feedTitle:SetText(""); widgets.playsHeader:SetText("")
        local winner = addon.Model.CompanionWinner(addon.Store.db.games, addon.Games.PreviousPeriodKey(now), myName)
        widgets.winnerText:SetText(winner and Format(Text["Last week's best: {name} ({level})"], { name = winner.name, level = winner.peak }) or "")
        addon.AzeCaughtPanel.Refresh()
        return
    end
    local labels = boardLabels(gameKey)
    local rows = addon.Model.BuildLeaderboardRows(records, GamesTab.state.scope, addon.Games.PeriodKey(now), myName, gameKey)
    widgets.leaderboardList:SetData(rows)
    widgets.emptyText:SetText(labels.empty); widgets.emptyText:SetShown(#rows == 0)
    widgets.feedTitle:SetText(labels.feed); widgets.playsHeader:SetText(labels.plays)
    widgets.feedList:SetData(addon.Model.BuildFlipFeedRows(records, myName, 15, gameKey))
    local winner = addon.Model.PreviousWinner(records, addon.Games.PreviousPeriodKey(now), gameKey)
    widgets.winnerText:SetText(winner and Format(Text["Last week's winner: {name} ({gold})"],
        { name = displayName(winner.nameRaw, winner.name), gold = signedGold(winner.net) }) or "")
end

-- The board's rows slide in from the right one after another (when the sidebar opens or the board changes).
function GamesTab.RevealBoard()
    local rows = {}
    for _, list in ipairs({ widgets.leaderboardList, widgets.feedList }) do
        if list and type(list.rows) == "table" then
            for index, row in ipairs(list.rows) do rows[#rows + 1] = { row = row, list = list, index = index } end
        end
    end
    if #rows == 0 then return end
    local rowHeight, stagger, slide = addon.UI.Widgets.ROW_HEIGHT, 0.03, 0.22
    local duration = stagger * #rows + slide
    local function place(entry, progress)
        local eased = 1 - (1 - progress) ^ 3
        entry.row:ClearAllPoints()
        entry.row:SetPoint("TOPLEFT", entry.list, "TOPLEFT", 18 * (1 - eased), -(entry.index - 1) * rowHeight)
        entry.row:SetAlpha(eased)
    end
    addon.Animate.Tween("boardReveal", duration, function(elapsed)
        for order, entry in ipairs(rows) do
            place(entry, addon.Utility.Clamp((elapsed - (order - 1) * stagger) / slide, 0, 1))
        end
    end, function() for _, entry in ipairs(rows) do place(entry, 1) end end)
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

-- column layout (x, width) of the leaderboard, shared by the header and the rows; won/lost are in the row's tooltip
local COLUMNS = { rank = { 0, 22 }, name = { 28, 118 }, net = { 148, 96 }, flips = { 248, 62 } }
-- rank colours: gold, silver, bronze, then grey
local MEDALS = { { 1, 0.82, 0.1 }, { 0.82, 0.86, 0.92 }, { 0.86, 0.55, 0.28 } }
local CROWN = "|TInterface\\Icons\\INV_Crown_01:13:13:0:0:64:64:5:59:5:59|t"

---@param row table
local function showRowTooltip(row)
    local entry = row.boardEntry
    if not entry or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(displayName(entry.nameRaw, entry.name))
    GameTooltip:AddDoubleLine(Text["Won"], money(entry.won), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(Text["Lost"], money(entry.lost), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine(Text["Net"], signedGold(entry.net), 1, 1, 1, 1, 1, 1)
    GameTooltip:Show()
end

---@param parent table
---@return table row
local function createLeaderboardRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.background = row:CreateTexture(nil, "BACKGROUND"); row.background:SetAllPoints()
    row.background:SetColorTexture(1, 0.8, 0.2, 0.14); row.background:Hide()
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1); row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.07); row.hover:Hide()
    row.rank = column(row, COLUMNS.rank[2], "RIGHT", COLUMNS.rank[1])
    row.name = column(row, COLUMNS.name[2], "LEFT", COLUMNS.name[1])
    row.net = column(row, COLUMNS.net[2], "RIGHT", COLUMNS.net[1])
    row.flips = column(row, COLUMNS.flips[2], "RIGHT", COLUMNS.flips[1])
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self.hover:Show(); showRowTooltip(self) end)
    row:SetScript("OnLeave", function(self) self.hover:Hide(); if GameTooltip then GameTooltip:Hide() end end)
    return row
end

---@param row table
---@param entry LeaderboardRow
local function fillLeaderboardRow(row, entry)
    row.boardEntry = entry
    row.background:SetShown(entry.mine)
    local medal = MEDALS[entry.rank]
    row.rank:SetText(entry.rank == 1 and CROWN or tostring(entry.rank))
    if medal then row.rank:SetTextColor(medal[1], medal[2], medal[3]) else row.rank:SetTextColor(0.6, 0.6, 0.6) end
    row.name:SetText(displayName(entry.nameRaw, entry.name))
    if medal then row.name:SetTextColor(medal[1], medal[2], medal[3]) else row.name:SetTextColor(1, 1, 1) end
    row.net:SetText(signedGold(entry.net))
    row.flips:SetText(entry.wins .. "/" .. entry.losses)
end

---@param parent table
---@return table row
local function createFeedRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.name = column(row, 130, "LEFT", 4)
    row.net = column(row, 96, "RIGHT", 136)
    row.when = column(row, 76, "RIGHT", 234)
    return row
end

---@param row table
---@param entry FlipFeedRow
local function fillFeedRow(row, entry)
    row.name:SetText(displayName(entry.nameRaw, entry.name))
    row.net:SetText(signedGold(entry.net))
    row.when:SetText("|cff999999" .. addon.UI.Widgets.TimeAgo(entry.t) .. "|r")
end

------------------------------------------------------------------ build

---@param panel table the coin flip's panel (300 wide)
local function buildCoinPanel(panel)
    local Widgets = addon.UI.Widgets
    local coinHolder = CreateFrame("Frame", nil, panel)
    coinHolder:SetSize(120, 200); coinHolder:SetPoint("TOP", 0, 0)
    widgets.coinHolder = coinHolder
    local glow = coinHolder:CreateTexture(nil, "BACKGROUND", nil, 0)
    glow:SetSize(COIN_SIZE * 1.6, COIN_SIZE * 1.6); glow:SetTexture(GLOW_TEXTURE); glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0.2); glow:SetAlpha(0); glow:Hide()
    widgets.glow = glow
    local coin = buildCoin(coinHolder)
    glow:SetPoint("CENTER", coin, "CENTER", 0, 0)
    GamesTab.state.face = nil
    applyPose(addon.CoinFlip.Pose(addon.CoinFlip.DURATION, "H"))

    -- effects layer above the coin: trail ghosts, sparkles, the ring and the floating result
    local effects = CreateFrame("Frame", nil, panel)
    effects:SetAllPoints(panel); effects:SetFrameLevel((tonumber(coin:GetFrameLevel()) or 1) + 5)
    widgets.effects = effects
    local coinCentre = CreateFrame("Frame", nil, effects)
    coinCentre:SetSize(1, 1); coinCentre:SetPoint("CENTER", coinHolder, "CENTER", 0, COIN_REST_Y)
    widgets.coinCentre = coinCentre
    widgets.trail = { history = {} }
    for index = 1, TRAIL_LENGTH do
        local ghost = effects:CreateTexture(nil, "ARTWORK")
        ghost:SetTexture(addon.Animate.SPARKLE_TEXTURE); ghost:SetBlendMode("ADD"); ghost:SetVertexColor(1, 0.8, 0.3)
        ghost:Hide()
        widgets.trail[index] = ghost
    end
    widgets.floatText = Widgets.CreateFontString(effects, "GameFontNormalHuge", "CENTER")
    widgets.floatText:Hide()
    widgets.idle = { time = 0 }
    coinHolder:SetScript("OnUpdate", function(_, elapsedSeconds) idleCoin(elapsedSeconds) end)

    widgets.headsButton = Widgets.CreateButton(panel, Text["Heads"], 80, 20, function() selectPick("H") end)
    widgets.headsButton:SetPoint("TOPRIGHT", panel, "TOP", -4, -206)
    widgets.tailsButton = Widgets.CreateButton(panel, Text["Tails"], 80, 20, function() selectPick("T") end)
    widgets.tailsButton:SetPoint("TOPLEFT", panel, "TOP", 4, -206)

    widgets.coinStake = GamesTab.CreateStakeRow(panel, 36, -238, function() GamesTab.Flip() end)
    widgets.goldBox, widgets.silverBox, widgets.copperBox = widgets.coinStake.goldBox, widgets.coinStake.silverBox, widgets.coinStake.copperBox
    GamesTab.WriteStake(settings().lastStakeCopper or DEFAULT_STAKE)

    widgets.flipButton = Widgets.CreateButton(panel, Text["Flip"], 180, 28, function() GamesTab.Flip() end)
    widgets.flipButton:SetPoint("TOP", panel, "TOP", 0, -268)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.flipButton) end

    widgets.resultText = Widgets.CreateFontString(panel, "GameFontNormalLarge", "CENTER")
    widgets.resultText:SetPoint("TOP", panel, "TOP", 0, -308); widgets.resultText:SetWidth(290)
    selectPick(GamesTab.state.pick)
end

-- Builds the games into `stage`, the leaderboard into `sidebar` and the game switch into `header`
-- (UI/Window.lua; the last two default to `stage`).
---@param stage table
---@param sidebar? table
---@param header? table
function GamesTab.Build(stage, sidebar, header)
    local Widgets = addon.UI.Widgets
    local state = GamesTab.state
    sidebar, header = sidebar or stage, header or stage
    state.scope = (settings().gamesScope == "all") and "all" or "week"
    state.game = (addon.Games.KINDS[settings().gameKey or ""] or settings().gameKey == "caught") and settings().gameKey or "coin"

    -- game switch (header) and one panel per game (stage)
    widgets.gameButtons, widgets.panels = {}, {}
    -- the switch shows one icon per game; the name is its tooltip
    local gameLabels = { coin = Text["Coin flip"], slots = Text["Slots"], survivor = Text["Survivor"], caught = Text["AZEcaught"] }
    local previousButton
    for _, gameKey in ipairs(switchOrder()) do
        local key = gameKey
        local button = Widgets.CreateButton(header, "", 26, 20, function() GamesTab.SelectGame(key) end)
        if previousButton then button:SetPoint("LEFT", previousButton, "RIGHT", 3, 0) else button:SetPoint("LEFT", header, "LEFT", 4, 0) end
        local icon = button:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16); icon:SetPoint("CENTER", 0, 1); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        addon.UIHelpers.SetTextureOr(icon, GAME_ICONS[key], { 1, 0.82, 0.2 })
        button.gameIcon = icon
        button:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(gameLabels[key])
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        widgets.gameButtons[key] = button
        previousButton = button
        local panel = CreateFrame("Frame", nil, stage)
        panel:SetPoint("TOPLEFT", 0, 0); panel:SetPoint("BOTTOMRIGHT", 0, 0)
        widgets.panels[key] = panel
    end
    buildCoinPanel(widgets.panels.coin)
    addon.Log.Protected("games.slots", "building the slot machine failed", addon.SlotMachine.Build, widgets.panels.slots)
    addon.Log.Protected("games.survivor", "building the survivor arena failed", addon.SurvivorArena.Build, widgets.panels.survivor)
    addon.Log.Protected("caught.ui", "building the AZEcaught panel failed", addon.AzeCaughtPanel.Build, widgets.panels.caught)
    -- the money pool (feature 018), right of the game switch
    widgets.balanceText = Widgets.CreateFontString(header, "GameFontHighlightSmall", "LEFT")
    widgets.balanceText:SetPoint("LEFT", previousButton, "RIGHT", 8, 0)
    widgets.balanceText:SetWidth(110)

    -- sidebar: last week's winner, scope, the selected game's leaderboard and feed
    widgets.winnerText = Widgets.CreateFontString(sidebar, "GameFontNormalSmall")
    widgets.winnerText:SetPoint("TOPLEFT", 0, 0); widgets.winnerText:SetWidth(320)
    widgets.weekButton = Widgets.CreateButton(sidebar, Text["This week"], 80, 18, function() selectScope("week") end)
    widgets.weekButton:SetPoint("TOPLEFT", 0, -18)
    widgets.allButton = Widgets.CreateButton(sidebar, Text["All time"], 80, 18, function() selectScope("all") end)
    widgets.allButton:SetPoint("LEFT", widgets.weekButton, "RIGHT", 4, 0)

    local columnHeader = CreateFrame("Frame", nil, sidebar)
    columnHeader:SetSize(314, 16); columnHeader:SetPoint("TOPLEFT", 0, -44)
    local headerLabels = { name = Text["Player"], net = Text["Net"], flips = Text["Flips"] }
    for columnKey, label in pairs(headerLabels) do
        local headerText = column(columnHeader, COLUMNS[columnKey][2], columnKey == "name" and "LEFT" or "RIGHT", COLUMNS[columnKey][1])
        headerText:SetFontObject("GameFontNormalSmall"); headerText:SetText(label)
        if columnKey == "flips" then widgets.playsHeader = headerText end
    end

    widgets.leaderboardList = Widgets.CreateScrollList(sidebar, 330, Widgets.ROW_HEIGHT * 7, createLeaderboardRow, fillLeaderboardRow)
    widgets.leaderboardList:SetPoint("TOPLEFT", 0, -60)
    widgets.emptyText = Widgets.CreateFontString(sidebar, "GameFontDisable", "CENTER")
    widgets.emptyText:SetPoint("TOP", widgets.leaderboardList, "TOP", 0, -50); widgets.emptyText:SetText(Text["No flips yet"])

    widgets.feedTitle = Widgets.CreateFontString(sidebar, "GameFontNormalSmall")
    widgets.feedTitle:SetPoint("TOPLEFT", 0, -210); widgets.feedTitle:SetText(Text["Recent flips"])
    widgets.feedList = Widgets.CreateScrollList(sidebar, 330, Widgets.ROW_HEIGHT * 6, createFeedRow, fillFeedRow)
    widgets.feedList:SetPoint("TOPLEFT", 0, -226)

    local note = Widgets.CreateFontString(sidebar, "GameFontDisableSmall", "LEFT")
    note:SetPoint("BOTTOMLEFT", 0, 0); note:SetWidth(320); note:SetText(Text["For fun only: no gold changes hands."])

    markSelected(widgets.weekButton, state.scope == "week"); markSelected(widgets.allButton, state.scope == "all")
    for key, panel in pairs(widgets.panels) do panel:SetShown(key == state.game) end
    for key, button in pairs(widgets.gameButtons) do markSelected(button, key == state.game) end
    GamesTab.Refresh()
end

-- the money pool changes with catches, care and payouts (feature 018)
addon.Events.On("CAUGHT_CHANGED", function() GamesTab.RefreshBalance() end)
