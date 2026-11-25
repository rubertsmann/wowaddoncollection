local _, addon = ...

-- The AZEcaught "Arena" view: the guild list (built by AzeCaughtPanel) and the fights (incoming challenges to answer,
-- open fights to bet on, finished fights to watch), plus the replay: both models, health bars, floating damage, a shake on every hit and a burst for the winner. Hands-off: the
-- fight is already decided (Arena.Fight); the replay only shows it. My fighter (level line, the four stat icons that
-- train) is built here as well, but it sits in the Companion view and in the compact pet view's training menu.
local ArenaView = {}
addon.ArenaView = ArenaView

local Text, Format = addon.Text, addon.Locale.Format
local money = addon.Model.MoneyText
local widgets = {}
ArenaView.widgets = widgets
ArenaView.state = { page = "guild", selected = nil }

local STAT_ICONS = { atk = "Interface\\Icons\\Ability_Warrior_Cleave", def = "Interface\\Icons\\INV_Shield_06",
    spd = "Interface\\Icons\\Ability_Rogue_Sprint", vit = "Interface\\Icons\\Spell_Holy_WordFortitude" }
local STAT_TEXT = { atk = Text["Attack"], def = Text["Defense"], spd = Text["Speed"], vit = Text["Vitality"] }
local ABILITY_NAME = { rend = Text["Rend"], breath = Text["Breath"], burn = Text["Fel Fire"], surge = Text["Surge"], smash = Text["Smash"],
    drain = Text["Drain"], focus = Text["Focus"], barrier = Text["Barrier"], strike = Text["Strike"] }
local ABILITY_TEXT = { rend = Text["Rend: a bleeding wound"], breath = Text["Breath: ignores half the armor"],
    burn = Text["Fel Fire: burns for two turns"], surge = Text["Surge: a huge hit"], smash = Text["Smash: may stun"],
    drain = Text["Drain: heals by half the damage"], focus = Text["Focus: the next hit is critical"],
    barrier = Text["Barrier: absorbs damage"], strike = Text["Strike: a heavy hit"] }
ArenaView.STAT_TEXT, ArenaView.ABILITY_NAME = STAT_TEXT, ABILITY_NAME
local REPLAY_STEP = 0.55   -- seconds per fight event in the replay

local function me() return addon.Utility.Me() end
local function now() return addon.Utility.Now() end
local function short(name) return addon.Utility.Escape((name or "?"):match("^([^%-]+)") or name or "?") end
local function records() return addon.Games.AllRecords() end

---@param seconds number
---@return string
local function clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- A horizontal bar (background + fill); bar:SetValue(0..1).
local function createBar(parent, width, height, color)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height)
    local back = bar:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(0.1, 0.1, 0.1, 0.85)
    local fill = bar:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(color[1], color[2], color[3], 0.95)
    bar.fill, bar.width = fill, width
    function bar:SetValue(value) self.fill:SetWidth(math.max(0.01, self.width * addon.Utility.Clamp(value or 0, 0, 1))) end
    bar:SetValue(0)
    return bar
end

------------------------------------------------------------------ fighter block and stat icons

local function trainRefusalText(reason)
    local texts = { busy = Text["Already training."], maximum = Text["This stat is fully trained."], asleep = Text["Your companion is asleep."],
        energy = Text["Your companion is too tired to train."], funds = Text["Not enough gold in your pool."],
        nocompanion = Text["You have no companion."], readonly = Text["Saved data is read-only."] }
    return texts[reason] or tostring(reason)
end
ArenaView.TrainRefusalText = trainRefusalText

-- What the stat icons show now: my companion's fighter, its arena entry and the running training (only when it is
-- this companion's), or nil without a companion.
---@return table|nil
function ArenaView.FighterState()
    local Arena = addon.Arena
    local companion = addon.AzeCaught.Active()
    local fighter = companion and Arena.Fighter(companion)
    if not fighter then return nil end
    local training = Arena.State().training
    if training and training.npc ~= companion.npc then training = nil end
    return { companion = companion, fighter = fighter, npc = Arena.Npc(companion.npc), training = training,
        left = training and Arena.TrainingLeft() or nil }
end

-- Starts training `stat`. A refusal goes to `onRefusal(text)`, or to the red error line.
---@param stat string
---@param onRefusal? fun(text: string)
---@return boolean ok
function ArenaView.Train(stat, onRefusal)
    local ok, reason = addon.Arena.Train(me(), stat, now())
    if ok then
        addon.Events.Fire("CAUGHT_CHANGED")
        return true
    end
    local text = "|cffff6060" .. trainRefusalText(reason) .. "|r"
    if onRefusal then onRefusal(text) else addon.Api.ShowOverlay(trainRefusalText(reason)) end
    return false
end

---@param button table a stat icon
local function statTooltip(button)
    if not GameTooltip then return end
    local Arena = addon.Arena
    local stat, current = button.stat, ArenaView.FighterState()
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(STAT_TEXT[stat] .. (current and ("  |cffffffff" .. current.fighter[stat] .. "|r") or ""), 1, 0.82, 0)
    if current then
        local points = current.npc.tr[stat]
        GameTooltip:AddLine(Format(Text["Trained {points}/{maximum}"], { points = points, maximum = Arena.MAXIMUM_TRAINING }), 1, 1, 1)
        if current.training and current.training.stat == stat and current.left then
            GameTooltip:AddLine(Format(Text["Training {stat}: {time} left (play time)"], { stat = STAT_TEXT[stat], time = clock(current.left) }), 1, 0.82, 0, true)
        elseif points < Arena.MAXIMUM_TRAINING then
            GameTooltip:AddLine(Format(Text["Costs {gold} and {energy} energy, takes {minutes} minutes of play time."],
                { gold = money(Arena.TrainCost(points)), energy = Arena.TRAIN_ENERGY, minutes = math.floor(Arena.TRAIN_SECONDS / 60) }), 1, 1, 1, true)
            if current.training then
                GameTooltip:AddLine(trainRefusalText("busy"), 1, 0.4, 0.4, true)
            else
                GameTooltip:AddLine(Text["Click: train."], 0.4, 1, 0.4)
            end
        end
        GameTooltip:AddLine(Format(Text["+{percent}% per point, at most {maximum} points."],
            { percent = math.floor(Arena.TRAIN_BONUS * 100), maximum = Arena.MAXIMUM_TRAINING }), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

-- A stat icon: the stat's icon, a dark shade that shrinks while it trains, the time left on the icon and, when
-- `withLabel`, "points/maximum" below it. A click trains that stat (`onRefusal` gets the refusal text).
---@param parent table
---@param stat string
---@param size number
---@param withLabel boolean
---@param onRefusal? fun(text: string)
---@return table button
function ArenaView.CreateStatIcon(parent, stat, size, withLabel, onRefusal)
    local Widgets = addon.UI.Widgets
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.stat = stat
    local border = button:CreateTexture(nil, "BACKGROUND"); border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0, 0, 0, 0.85)
    button.icon = button:CreateTexture(nil, "ARTWORK"); button.icon:SetAllPoints()
    addon.UIHelpers.SetTextureOr(button.icon, STAT_ICONS[stat], { 0.6, 0.6, 0.6 })
    if button.icon.SetTexCoord then button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    -- the part still to train, dark from the top
    button.shade = button:CreateTexture(nil, "OVERLAY"); button.shade:SetPoint("TOPLEFT"); button.shade:SetPoint("TOPRIGHT")
    button.shade:SetColorTexture(0, 0, 0, 0.65); button.shade:SetHeight(size); button.shade:Hide()
    button.time = Widgets.CreateFontString(button, "NumberFontNormal", "CENTER"); button.time:SetPoint("CENTER", 0, 0)
    button.time:SetTextColor(1, 0.82, 0)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT"); highlight:SetAllPoints(); highlight:SetColorTexture(1, 1, 1, 0.2)
    button.withLabel = withLabel and true or false
    if withLabel then
        button.label = Widgets.CreateFontString(parent, "GameFontHighlightSmall", "CENTER")
        button.label:SetPoint("TOP", button, "BOTTOM", 0, -1); button.label:SetWidth(60)
    end
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self)
        if ArenaView.Train(stat, onRefusal) then addon.Animate.Pulse(self, 1.15, 0.3) end
        ArenaView.FillStatIcon(self, ArenaView.FighterState())
        if GameTooltip and GameTooltip:GetOwner() == self then statTooltip(self) end
    end)
    button:SetScript("OnEnter", statTooltip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return button
end

-- Shows `current` (ArenaView.FighterState) on a stat icon: trainable, training (shade + time), or greyed out.
---@param button table
---@param current table|nil
function ArenaView.FillStatIcon(button, current)
    local Arena = addon.Arena
    if not current then button:Hide(); if button.withLabel then button.label:Hide() end return end
    button:Show()
    local stat = button.stat
    local points = current.npc.tr[stat]
    local trainingThis = current.training and current.training.stat == stat and current.left ~= nil
    local enabled = trainingThis or (current.training == nil and points < Arena.MAXIMUM_TRAINING)
    pcall(button.icon.SetDesaturated, button.icon, not enabled)
    button.icon:SetAlpha(enabled and 1 or 0.4)
    if trainingThis then
        button.shade:SetHeight(math.max(0.01, button:GetHeight() * addon.Utility.Clamp(current.left / Arena.TRAIN_SECONDS, 0, 1)))
        button.shade:Show()
        button.time:SetText(clock(current.left))
    else
        button.shade:Hide()
        button.time:SetText("")
    end
    if button.withLabel then
        button.label:Show()
        button.label:SetText((points >= Arena.MAXIMUM_TRAINING and "|cff999999" or "") .. points .. "/" .. Arena.MAXIMUM_TRAINING
            .. (points >= Arena.MAXIMUM_TRAINING and "|r" or ""))
    end
end

---@param holder table the level line's mouse frame
local function levelTooltip(holder)
    local current = ArenaView.FighterState()
    if not GameTooltip or not current then return end
    local Arena = addon.Arena
    local level, into, needed = Arena.Level(current.npc.xp)
    GameTooltip:SetOwner(holder, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Text["Fighter"] .. ": " .. Format(Text["Arena level {level}"], { level = level }), 1, 0.82, 0)
    if needed > 0 then GameTooltip:AddLine(into .. "/" .. needed .. " XP", 0.75, 0.6, 1) end
    GameTooltip:AddLine(Format(Text["Wins {wins} · Losses {losses}"], { wins = current.npc.w, losses = current.npc.l }), 1, 1, 1)
    for _, stat in ipairs(Arena.STATS) do
        GameTooltip:AddDoubleLine(STAT_TEXT[stat], tostring(current.fighter[stat]), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(Text["Ability"] .. ": " .. ABILITY_TEXT[current.fighter.ab], 1, 0.82, 0, true)
    if not current.training then GameTooltip:AddLine(Text["Not training."], 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- The fighter in the Companion view: the level line (arena level, wins/losses, XP bar) under the name at `levelY`,
-- and the four stat icons in a row at `iconsY` (where the care buttons used to be).
---@param panel table the companion view
---@param levelY number
---@param iconsY number
---@param onRefusal fun(text: string)
function ArenaView.BuildFighterBlock(panel, levelY, iconsY, onRefusal)
    local Widgets = addon.UI.Widgets
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetSize(200, 22); holder:SetPoint("TOP", 0, levelY)
    holder:SetFrameLevel(panel:GetFrameLevel() + 5)
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", levelTooltip)
    holder:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    widgets.fighterHolder = holder
    widgets.fighterLevel = Widgets.CreateFontString(holder, "GameFontHighlightSmall", "CENTER")
    widgets.fighterLevel:SetPoint("TOP", 0, 0); widgets.fighterLevel:SetWidth(200)
    widgets.xpBar = createBar(holder, 120, 4, { 0.55, 0.35, 1 })
    widgets.xpBar:SetPoint("TOP", widgets.fighterLevel, "BOTTOM", 0, -2)
    widgets.statIcons = {}
    for index, stat in ipairs(addon.Arena.STATS) do
        local icon = ArenaView.CreateStatIcon(panel, stat, 34, true, onRefusal)
        icon:SetPoint("TOPLEFT", 36 + (index - 1) * 64, iconsY)
        widgets.statIcons[stat] = icon
    end
end

function ArenaView.RefreshFighter()
    if not widgets.fighterHolder then return end
    local current = ArenaView.FighterState()
    widgets.fighterHolder:SetShown(current ~= nil)
    for _, icon in pairs(widgets.statIcons) do ArenaView.FillStatIcon(icon, current) end
    if not current then return end
    local level, into, needed = addon.Arena.Level(current.npc.xp)
    addon.UI.Widgets.FitText(widgets.fighterLevel, Format(Text["Arena level {level}"], { level = level })
        .. "  |cff999999" .. Format(Text["{wins}W {losses}L"], { wins = current.npc.w, losses = current.npc.l }) .. "|r"
        .. (current.fighter.bf and ("  " .. ArenaView.BuffIcons(current.fighter.bf)) or ""), 0.7)
    widgets.xpBar:SetValue(needed > 0 and into / needed or 1)
end

------------------------------------------------------------------ fights page

-- Display rows for the fight list: incoming first, then open, then waiting, then finished (newest first).
---@return table[]
function ArenaView.FightRows()
    local Arena = addon.Arena
    local myName, time = me(), now()
    local rows = {}
    local order = { incoming = 1, counterin = 1, open = 2, pending = 3, lapsed = 3, countered = 3, done = 4, declined = 5, rejected = 5,
        expired = 5, withdrawn = 5 }
    for id, fight in pairs(Arena.Fights(records(), myName, time)) do
        local state = fight.state
        if state == "pending" and fight.b == myName and not Arena.State().an[id] and not Arena.State().co[id] then state = "incoming" end
        if state == "countered" and fight.a == myName then state = "counterin" end
        rows[#rows + 1] = { id = id, fight = fight, state = state, order = order[state] or 6, at = fight.at }
    end
    table.sort(rows, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        return left.at > right.at
    end)
    return rows
end

---@param row table
---@return string
local function stateText(row)
    local fight, myName = row.fight, me()
    if row.state == "incoming" then return "|cffffd100" .. Text["challenge!"] .. "|r" end
    if row.state == "counterin" then return "|cffffd100" .. Text["counter offer!"] .. "|r" end
    if row.state == "countered" then return "|cff999999" .. Text["counter offer sent"] .. "|r" end
    if row.state == "rejected" then return "|cff999999" .. Text["declined"] .. "|r" end
    if row.state == "open" then return "|cff66ccff" .. Format(Text["in {time}"], { time = clock(fight.fightAt - now()) }) .. "|r" end
    if row.state == "pending" or row.state == "lapsed" then return "|cff999999" .. Text["waiting"] .. "|r" end
    if row.state == "declined" then return "|cff999999" .. Text["declined"] .. "|r" end
    if row.state == "expired" then return "|cff999999" .. Text["expired"] .. "|r" end
    if row.state == "withdrawn" then return "|cff999999" .. Text["stopped"] .. "|r" end
    -- the result stays hidden until I watched the fight
    if not addon.Arena.Revealed(fight, now()) then return "|cffff9933" .. Text["watch!"] .. "|r" end
    local result = addon.Arena.Result(fight)
    local winner = result and (result.winner == "a" and fight.a or fight.b)
    if winner == myName then return "|cff66ff66" .. Text["won"] .. "|r" end
    if fight.a == myName or fight.b == myName then return "|cffff6060" .. Text["lost"] .. "|r" end
    return Format(Text["{name} won"], { name = short(winner) })
end

local function createFightRow(list)
    local Widgets = addon.UI.Widgets
    local row = CreateFrame("Button", nil, list)
    row.hover = row:CreateTexture(nil, "BACKGROUND"); row.hover:SetAllPoints(); row.hover:SetColorTexture(1, 1, 1, 0.07); row.hover:Hide()
    row.selected = row:CreateTexture(nil, "BACKGROUND", nil, 1); row.selected:SetAllPoints(); row.selected:SetColorTexture(0.3, 0.6, 1, 0.22); row.selected:Hide()
    row.names = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT"); row.names:SetPoint("LEFT", 4, 0); row.names:SetWidth(170)
    row.info = Widgets.CreateFontString(row, "GameFontHighlightSmall", "RIGHT"); row.info:SetPoint("RIGHT", -4, 0); row.info:SetWidth(110)
    -- Stop my own waiting challenge right in the row (Accept / Decline / Counter offer are in the dialog below the list)
    local height = math.max(14, (Widgets.ROW_HEIGHT or 18) - 2)
    row.stop = Widgets.CreateButton(row, Text["Stop"], 56, height, function() if row.entry then ArenaView.Withdraw(row.entry.id) end end)
    row.stop:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self) if self.entry then ArenaView.state.selected = self.entry.id; ArenaView.Refresh() end end)
    return row
end

local function fillFightRow(row, entry)
    row.selected:SetShown(entry.id == ArenaView.state.selected)
    row.names:SetText(short(entry.fight.a) .. " |cff999999vs|r " .. short(entry.fight.b)
        .. (entry.fight.wager > 0 and ("  |cffffd100" .. money(entry.fight.wager) .. "|r") or ""))
    local stoppable = (entry.state == "pending" or entry.state == "lapsed") and entry.fight.a == me()
    row.stop:SetShown(stoppable)
    row.info:SetShown(not stoppable)
    row.info:SetText(stateText(entry))
end

---@param panel table
local function buildFightsPage(panel)
    local Widgets = addon.UI.Widgets
    widgets.fightList = Widgets.CreateScrollList(panel, 292, Widgets.ROW_HEIGHT * 6, createFightRow, fillFightRow)
    widgets.fightList:SetPoint("TOPLEFT", 4, -46)
    widgets.noFights = Widgets.CreateFontString(panel, "GameFontDisable", "CENTER")
    widgets.noFights:SetPoint("TOP", 0, -80); widgets.noFights:SetWidth(270)
    widgets.noFights:SetText(Text["No fights yet. Challenge a guild member in the Guild view."])
    widgets.detail = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "LEFT")
    widgets.detail:SetPoint("TOPLEFT", 8, -46 - Widgets.ROW_HEIGHT * 6 - 8); widgets.detail:SetWidth(284)
    local y = -46 - Widgets.ROW_HEIGHT * 6 - 78
    widgets.actionY = y
    -- an incoming challenge (or a counter offer to my challenge): Accept / Decline on the first line, the counter
    -- offer (gold box + button) on the second
    -- (icons: the text is the tooltip)
    widgets.acceptButton = Widgets.CreateIconButton(panel, "accept", 24, Text["Accept"], function() ArenaView.Decide(true) end)
    widgets.acceptButton:SetPoint("TOPLEFT", 8, y)
    widgets.declineButton = Widgets.CreateIconButton(panel, "decline", 24, Text["Decline"], function() ArenaView.Decide(false) end)
    widgets.declineButton:SetPoint("LEFT", widgets.acceptButton, "RIGHT", 8, 0)
    widgets.betBox = Widgets.CreateEditBox(panel, 44)
    widgets.betBox:SetPoint("TOPLEFT", 8, y - 2)
    widgets.betBox:SetText("1")
    widgets.betLabel = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "LEFT")
    widgets.betLabel:SetPoint("LEFT", widgets.betBox, "RIGHT", 3, 0); widgets.betLabel:SetText(Text["gold on"])
    widgets.betA = Widgets.CreateButton(panel, "A", 84, 22, function() ArenaView.Bet("a") end)
    widgets.betA:SetPoint("TOPLEFT", 104, y)
    widgets.betB = Widgets.CreateButton(panel, "B", 84, 22, function() ArenaView.Bet("b") end)
    widgets.betB:SetPoint("LEFT", widgets.betA, "RIGHT", 4, 0)
    widgets.counterButton = Widgets.CreateButton(panel, Text["Counter offer"], 120, 22, function() ArenaView.Counter() end)
    widgets.counterButton:SetPoint("TOPLEFT", 104, y)
    widgets.stopButton = Widgets.CreateButton(panel, Text["Stop"], 90, 22, function() ArenaView.Withdraw(ArenaView.state.selected) end)
    widgets.stopButton:SetPoint("TOPLEFT", 8, y)
    -- dev build: icon tools: the arena dummy challenges me (= /ggd arena request); its fights run now
    if addon.IS_DEVELOPMENT_BUILD then
        widgets.dummyButton = Widgets.CreateIconButton(panel, "debug", 24, "[dev] Add a challenge from the arena dummy to me",
            function() addon.Catcher.DevArenaRequest(0) end)
        widgets.dummyButton:SetPoint("BOTTOMLEFT", 8, 6)
        widgets.skipButton = Widgets.CreateIconButton(panel, "skip", 24, "[dev] Fight now: ends the waiting time of the dummy's accepted fights",
            function() addon.Catcher.DevArenaSkip() end)
        widgets.skipButton:SetPoint("LEFT", widgets.dummyButton, "RIGHT", 8, 0)
    end
    widgets.watchButton = Widgets.CreateButton(panel, Text["Watch"], 90, 22, function() ArenaView.Watch(ArenaView.state.selected) end)
    widgets.watchButton:SetPoint("TOPRIGHT", -8, y)
    widgets.fightStatus = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.fightStatus:SetPoint("TOP", 0, y - 58); widgets.fightStatus:SetWidth(290)
end

local REFUSALS = { readonly = Text["Saved data is read-only."], unknown = Text["This fight is gone."], answered = Text["Already answered."],
    late = Text["Too late to answer."], nocompanion = Text["You have no companion."], funds = Text["Not enough gold in your pool."],
    closed = Text["Bets are closed for this fight."], own = Text["You cannot bet on your own fight."], twice = Text["You already bet on this fight."],
    stake = Text["Bet between {minimum} and {maximum}."], self = Text["You cannot challenge yourself."],
    nocompanionthere = Text["That player has no companion."], open = Text["You have too many open challenges."],
    wager = Text["The wager is too high."], opponent = Text["Choose a guild member first."],
    busy = Text["One fight at a time: wait until your current fight is over."], theybusy = Text["They are in a fight right now."],
    same = Text["A counter offer needs another wager."] }
---@param reason string
---@return string
function ArenaView.RefusalText(reason)
    local text = REFUSALS[reason] or tostring(reason)
    return Format(text, { minimum = money(addon.Arena.MINIMUM_BET), maximum = money(addon.Arena.MAXIMUM_BET) })
end

local function showResult(ok, reason, success)
    if ok then
        widgets.fightStatus:SetText(success or "")
        addon.Catcher.PublishArena()
    else
        widgets.fightStatus:SetText("|cffff6060" .. ArenaView.RefusalText(reason) .. "|r")
    end
end

---@param accept boolean
---@param id? string the fight (a row's button), else the selected one
function ArenaView.Answer(accept, id)
    id = id or ArenaView.state.selected
    ArenaView.state.selected = id
    local ok, reason = addon.Arena.Answer(records(), me(), id, accept, now())
    showResult(ok, reason, accept and Text["Accepted. The fight is decided in 5 minutes."] or Text["Declined."])
    ArenaView.Refresh()
end

-- The dialog's Accept / Decline: answers the selected incoming challenge, or the counter offer to my challenge.
---@param accept boolean
function ArenaView.Decide(accept)
    local id = ArenaView.state.selected
    local fight = id and addon.Arena.Fights(records(), me(), now())[id]
    if fight and fight.a == me() and fight.state == "countered" then ArenaView.AnswerCounter(accept, id) else ArenaView.Answer(accept, id) end
end

-- A counter offer to the selected incoming challenge: the wager in gold from the box.
function ArenaView.Counter()
    local id = ArenaView.state.selected
    local gold = tonumber(widgets.betBox:GetText() or "")
    local ok, reason = addon.Arena.Counter(records(), me(), id, gold and math.floor(gold * 10000 + 0.5) or -1, now())
    showResult(ok, reason, Text["Counter offer sent."])
    ArenaView.Refresh()
end

-- Accepts or declines the counter offer to my challenge.
---@param accept boolean
---@param id? string
function ArenaView.AnswerCounter(accept, id)
    id = id or ArenaView.state.selected
    ArenaView.state.selected = id
    local ok, reason = addon.Arena.AnswerCounter(records(), me(), id, accept, now())
    showResult(ok, reason, accept and Text["Counter offer accepted. The fight is decided in 5 minutes."] or Text["Counter offer declined."])
    if ok and not accept then addon.Catcher.ArenaTick(true) end
    ArenaView.Refresh()
end

-- Stops my waiting challenge; the arena check runs at once, so the stake comes back right after.
---@param id? string
function ArenaView.Withdraw(id)
    id = id or ArenaView.state.selected
    ArenaView.state.selected = id
    local ok, reason = addon.Arena.Withdraw(records(), me(), id, now())
    showResult(ok, reason, Text["Challenge stopped."])
    if ok then addon.Catcher.ArenaTick(true) end
    ArenaView.Refresh()
end

function ArenaView.Bet(side)
    local id = ArenaView.state.selected
    local gold = tonumber(widgets.betBox:GetText() or "")
    local odds, reason = addon.Arena.Bet(records(), me(), id, side, gold and math.floor(gold * 10000) or 0, now())
    showResult(odds, reason, odds and Format(Text["Bet placed at {odds}x."], { odds = ("%.2f"):format(odds / 100) }))
end

-- The arena buffs of a fighter (`bf`, already sanitized) as small inline icons, "" without any.
---@param buffs string[]|nil
---@return string
function ArenaView.BuffIcons(buffs)
    local icons = {}
    for _, id in ipairs(buffs or {}) do
        local item = addon.Items.Get(id)
        if item then icons[#icons + 1] = "|T" .. item.icon .. ":14:14|t" end
    end
    return table.concat(icons, "")
end

---@param fighter Fighter|nil
---@return string
local function fighterLine(fighter)
    if not fighter then return "?" end
    local buffs = ArenaView.BuffIcons(fighter.bf)
    return ("%s |cff999999(%s %d, %s)|r%s"):format(addon.Utility.Escape(fighter.n), Text["Lv"], fighter.al, ABILITY_NAME[fighter.ab],
        buffs ~= "" and (" " .. buffs) or "")
end

function ArenaView.RefreshFights()
    ArenaView.state.busy = addon.Arena.Busy(addon.Arena.Fights(records(), me(), now()), me(), true) ~= nil
    local rows = ArenaView.FightRows()
    widgets.fightList:SetData(rows)
    widgets.noFights:SetShown(#rows == 0)
    local selected
    for _, row in ipairs(rows) do if row.id == ArenaView.state.selected then selected = row end end
    if not selected and rows[1] then selected = rows[1]; ArenaView.state.selected = rows[1].id end
    for _, region in ipairs({ widgets.stopButton, widgets.betBox, widgets.betLabel, widgets.betA,
        widgets.betB, widgets.watchButton, widgets.counterButton, widgets.acceptButton, widgets.declineButton }) do
        region:Hide()
    end
    -- the box, Counter offer and Stop move between the first and the second line of the dialog
    local function place(region, x, line, nudge)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", x, widgets.actionY - (line - 1) * 28 - (nudge or 0))
    end
    if not selected then widgets.detail:SetText("") return end
    local fight, myName = selected.fight, me()
    local lines = { short(fight.a) .. ": " .. fighterLine(fight.fa), short(fight.b) .. ": " .. fighterLine(fight.fb) }
    if fight.wager > 0 then lines[#lines + 1] = Format(Text["Wager: {gold} each"], { gold = money(fight.wager) }) end
    if fight.counter and not fight.answerAt then
        lines[#lines + 1] = Format(Text["Counter offer: {gold}"], { gold = money(fight.counter.wg) })
    end
    local chance = addon.Arena.Chance(fight)
    if chance then
        lines[#lines + 1] = Format(Text["Win chance {a}% : {b}%  ·  odds {oddsA}x : {oddsB}x"], { a = math.floor(chance * 100 + 0.5),
            b = math.floor((1 - chance) * 100 + 0.5), oddsA = ("%.2f"):format(addon.Arena.Odds(chance) / 100),
            oddsB = ("%.2f"):format(addon.Arena.Odds(1 - chance) / 100) })
        local count = addon.Utility.Count(fight.bets)
        if count > 0 then lines[#lines + 1] = Format(Text["{n} side bets"], { n = count }) end
    end
    local myBet = addon.Arena.State().bt[selected.id]
    if myBet then
        lines[#lines + 1] = Format(Text["Your bet: {gold} on {name} at {odds}x"], { gold = money(myBet.c),
            name = short(myBet.s == "a" and fight.a or fight.b), odds = ("%.2f"):format(myBet.o / 100) })
    end
    -- accepting while my own fight runs or waits is refused: the button is greyed out and the line says why
    local blocked = selected.state == "incoming" and ArenaView.state.busy
    if blocked then lines[#lines + 1] = "|cff999999" .. ArenaView.RefusalText("busy") .. "|r" end
    widgets.detail:SetText(table.concat(lines, "\n"))
    if selected.state == "incoming" then
        widgets.acceptButton:SetLabel(blocked and ArenaView.RefusalText("busy") or Text["Accept"])
        widgets.acceptButton:SetEnabled(not blocked); widgets.acceptButton:Show()
        widgets.declineButton:SetLabel(Text["Decline"]); widgets.declineButton:Show()
        -- a counter offer: another wager in the box, then "Counter offer"
        if widgets.counterFor ~= selected.id then
            widgets.counterFor = selected.id
            widgets.betBox:SetText(tostring(math.floor(fight.wager / 10000)))
        end
        place(widgets.betBox, 8, 2, 2); place(widgets.counterButton, 104, 2)
        widgets.betBox:Show(); widgets.betLabel:SetText(Text["gold"]); widgets.betLabel:Show()
        widgets.counterButton:Show()
    elseif selected.state == "counterin" then
        -- a counter offer to my challenge: accept / decline it; Stop below
        widgets.acceptButton:SetLabel(Format(Text["Accept the counter offer ({gold})"], { gold = money(fight.counter and fight.counter.wg or 0) }))
        widgets.acceptButton:SetEnabled(true); widgets.acceptButton:Show()
        widgets.declineButton:SetLabel(Text["Decline the counter offer"]); widgets.declineButton:Show()
        place(widgets.stopButton, 8, 2); widgets.stopButton:Show()
    elseif (selected.state == "pending" or selected.state == "lapsed") and fight.a == myName then
        place(widgets.stopButton, 8, 1); widgets.stopButton:Show()
    elseif selected.state == "open" and fight.a ~= myName and fight.b ~= myName and not myBet then
        place(widgets.betBox, 8, 1, 2)
        widgets.betBox:Show(); widgets.betLabel:SetText(Text["gold on"]); widgets.betLabel:Show()
        widgets.betA:SetLabel(short(fight.a)); widgets.betB:SetLabel(short(fight.b))
        widgets.betA:Show(); widgets.betB:Show()
    elseif selected.state == "done" then
        widgets.watchButton:Show()
    end
end

------------------------------------------------------------------ replay

local function sideWidgets(side) return side == "a" and widgets.replayLeft or widgets.replayRight end

-- Model animations in the replay: attack / getting hurt on each damage, the death once at 0 health.
-- AnimationData ids, first one the model has wins (no HasAnimation on the client: the first is tried).
local ANIMATION = {
    attack = { 16, 17, 18, 19 },          -- AttackUnarmed, Attack1H, Attack2H, Attack2HL
    cast = { 52, 51, 16, 17 },            -- SpellCastOmni, SpellCastDirected, else an attack (the ability)
    hurt = { 9, 8 },                      -- CombatWound, StandWound
    critical = { 10, 9, 8 },              -- CombatCritical
    dodge = { 20, 11 },                   -- ParryUnarmed, ShuffleLeft
    stun = { 14, 9 },                     -- Stun
    ready = { 26, 0 },                    -- ReadyUnarmed, Stand
    death = { 1 },                        -- Death
    dead = { 6 },                         -- Dead (lying)
}
ArenaView.ANIMATION = ANIMATION
local ACTION_SECONDS, DEATH_SECONDS = 0.45, 1.1
-- per model: { dead = bool, token = n } (a side table: nothing is added to the frame)
local modelState = setmetatable({}, { __mode = "k" })
local function stateOf(model) modelState[model] = modelState[model] or { token = 0 } return modelState[model] end
---@param model table
function ArenaView.ResetModel(model) if model then modelState[model] = { token = 0 } end end

---@param model table
---@param list integer[]
---@return integer|nil
local function pickAnimation(model, list)
    if not model.HasAnimation then return list[1] end
    for _, animationID in ipairs(list) do
        local ok, has = pcall(model.HasAnimation, model, animationID)
        if ok and has then return animationID end
    end
    return nil
end

-- Plays `key` on a replay model, then back to the ready stance after `back` seconds (a newer call wins). A dead
-- model stays dead. Returns the animation id played (tests).
---@param model table
---@param key string
---@param back? number
---@return integer|nil
function ArenaView.PlayAnimation(model, key, back)
    if not model or not model.SetAnimation or stateOf(model).dead then return nil end
    local animationID = pickAnimation(model, ANIMATION[key])
    if not animationID then return nil end
    pcall(model.SetAnimation, model, animationID)
    local state = stateOf(model)
    state.token = state.token + 1
    local token = state.token
    if back and C_Timer and C_Timer.After then
        C_Timer.After(back, function()
            if state.token ~= token or state.dead then return end
            local ready = pickAnimation(model, ANIMATION.ready)
            if ready then pcall(model.SetAnimation, model, ready) end
        end)
    end
    return animationID
end

-- The death, once: Death, then it stays lying (Dead). Returns true the first time.
---@param model table
---@return boolean
function ArenaView.PlayDeath(model)
    if not model or stateOf(model).dead then return false end
    ArenaView.PlayAnimation(model, "death")
    local state = stateOf(model)
    state.dead = true
    local token = state.token
    if C_Timer and C_Timer.After then
        C_Timer.After(DEATH_SECONDS, function()
            if not state.dead or state.token ~= token then return end
            local lying = pickAnimation(model, ANIMATION.dead)
            if lying then pcall(model.SetAnimation, model, lying) end
        end)
    end
    return true
end

-- The target side reacts: dies at 0 health (once), else hurt (critical: the bigger flinch).
local function react(side, health, critical)
    local model = sideWidgets(side).model
    if health <= 0 then ArenaView.PlayDeath(model) else ArenaView.PlayAnimation(model, critical and "critical" or "hurt", ACTION_SECONDS) end
end

---@param parent table
local function buildReplay(parent)
    local Widgets = addon.UI.Widgets
    local replay = CreateFrame("Frame", nil, parent)
    replay:SetAllPoints(); replay:SetFrameLevel(parent:GetFrameLevel() + 30); replay:EnableMouse(true); replay:Hide()
    local back = replay:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(0.03, 0.02, 0.05, 1)   -- fully opaque
    local floor = replay:CreateTexture(nil, "BORDER"); floor:SetPoint("BOTTOMLEFT", 0, 70); floor:SetPoint("BOTTOMRIGHT", 0, 70); floor:SetHeight(2)
    floor:SetColorTexture(1, 0.82, 0.2, 0.5)
    for _, side in ipairs({ "a", "b" }) do
        local part = {}
        part.model = addon.AzeCaughtPanel.CreateModel(replay, 132, 170)
        part.model:SetPoint(side == "a" and "TOPLEFT" or "TOPRIGHT", side == "a" and 6 or -6, -60)
        part.name = Widgets.CreateFontString(replay, "GameFontNormal", side == "a" and "LEFT" or "RIGHT")
        part.name:SetPoint(side == "a" and "TOPLEFT" or "TOPRIGHT", side == "a" and 8 or -8, -10); part.name:SetWidth(140)
        part.bar = createBar(replay, 140, 10, side == "a" and { 0.3, 0.85, 0.35 } or { 0.9, 0.35, 0.3 })
        part.bar:SetPoint(side == "a" and "TOPLEFT" or "TOPRIGHT", side == "a" and 8 or -8, -30)
        part.health = Widgets.CreateFontString(replay, "GameFontHighlightSmall", "CENTER"); part.health:SetPoint("CENTER", part.bar, "CENTER", 0, 0)
        -- the owner at the bottom of its side, above the floor line (not behind the pet's name)
        part.owner = Widgets.CreateFontString(replay, "GameFontHighlightSmall", side == "a" and "LEFT" or "RIGHT")
        part.owner:SetPoint(side == "a" and "BOTTOMLEFT" or "BOTTOMRIGHT", side == "a" and 8 or -8, 76); part.owner:SetWidth(140)
        part.float = Widgets.CreateFontString(replay, "GameFontNormalLarge", "CENTER"); part.float:Hide()
        if side == "a" then widgets.replayLeft = part else widgets.replayRight = part end
    end
    widgets.replayVersus = Widgets.CreateFontString(replay, "GameFontNormalLarge", "CENTER")
    widgets.replayVersus:SetPoint("TOP", 0, -120); widgets.replayVersus:SetText("VS")
    widgets.replayLine = Widgets.CreateFontString(replay, "GameFontHighlight", "CENTER")
    widgets.replayLine:SetPoint("BOTTOM", 0, 44); widgets.replayLine:SetWidth(290)
    -- only Close, centred
    local close = Widgets.CreateButton(replay, Text["Close"], 80, 20, function() ArenaView.StopReplay() end)
    close:SetPoint("BOTTOM", 0, 8)
    widgets.replay = replay
end

---@param event FightEvent
---@param fight ArenaFight
---@return string
function ArenaView.EventText(event, fight)
    local actor = short(event.s == "a" and fight.fa.n or fight.fb.n)
    local ability = event.ab and ABILITY_NAME[event.ab]
    if event.k == "dodge" then return Format(Text["{name} misses."], { name = actor }) end
    if event.k == "dot" then return Format(Text["{name} suffers {n}."], { name = actor, n = event.d }) end
    if event.k == "stun" then return Format(Text["{name} is stunned."], { name = actor }) end
    if event.k == "shield" then return Format(Text["{name}: {ability} ({n})"], { name = actor, ability = ability, n = event.d }) end
    local text = ability and Format(Text["{name}: {ability} for {n}"], { name = actor, ability = ability, n = event.d })
        or Format(Text["{name} hits for {n}"], { name = actor, n = event.d })
    if event.k == "crit" then text = text .. " |cffffd100" .. Text["critical!"] .. "|r" end
    return text
end

local function setHealth(fight, result, healthA, healthB)
    widgets.replayLeft.bar:SetValue(healthA / result.maxA); widgets.replayLeft.health:SetText(healthA .. "/" .. result.maxA)
    widgets.replayRight.bar:SetValue(healthB / result.maxB); widgets.replayRight.health:SetText(healthB .. "/" .. result.maxB)
end

-- Plays the fight `id` (only finished fights). Returns the number of events (tests).
---@param id string
---@return integer|nil
function ArenaView.Watch(id)
    local fight = addon.Arena.Fights(records(), me(), now())[id]
    if not fight or fight.state ~= "done" then return nil end
    local result = addon.Arena.Result(fight)
    ArenaView.StopReplay()
    local replay = ArenaView.state
    replay.fight, replay.result, replay.step = fight, result, 0
    widgets.replay:Show()
    for side, fighter in pairs({ a = fight.fa, b = fight.fb }) do
        local part = sideWidgets(side)
        addon.UI.Widgets.FitText(part.name, addon.Utility.Escape(fighter.n), 0.7)
        part.owner:SetText("|cff999999" .. short(side == "a" and fight.a or fight.b) .. "|r")
        addon.AzeCaughtPanel.ShowModel(part.model, { npc = fighter.npc, disp = fighter.disp }, "replay")
        if part.model.SetFacing then pcall(part.model.SetFacing, part.model, side == "a" and 0.9 or -0.9) end
        ArenaView.ResetModel(part.model)
        ArenaView.PlayAnimation(part.model, "ready")
    end
    setHealth(fight, result, result.maxA, result.maxB)
    widgets.replayLine:SetText(Text["Fight!"])
    if C_Timer and C_Timer.NewTicker then
        replay.ticker = C_Timer.NewTicker(REPLAY_STEP, function() ArenaView.Step() end)
    end
    return #result.events
end

-- One event of the replay: bars, floating number, a shake on the target.
function ArenaView.Step()
    local replay = ArenaView.state
    if not replay.result then return end
    replay.step = replay.step + 1
    local event = replay.result.events[replay.step]
    if not event then ArenaView.FinishReplay() return end
    setHealth(replay.fight, replay.result, event.ha, event.hb)
    widgets.replayLine:SetText(ArenaView.EventText(event, replay.fight))
    local targetSide = (event.k == "dot" or event.k == "stun" or event.k == "shield") and event.s or (event.s == "a" and "b" or "a")
    local target, actor = sideWidgets(targetSide), sideWidgets(event.s)
    if event.k == "hit" or event.k == "crit" or event.k == "dot" then
        addon.Animate.Shake(target.model, event.k == "crit" and 8 or 4, event.k == "crit" and 6 or 4)
        addon.Animate.FloatText("replay" .. targetSide, target.float, target.model, 0, 40, "-" .. event.d,
            event.k == "crit" and { 1, 0.85, 0.2 } or { 1, 0.35, 0.3 }, 40, 0.9)
        if event.heal and event.heal > 0 then
            addon.Animate.FloatText("replay" .. event.s, actor.float, actor.model, 0, 40, "+" .. event.heal, { 0.4, 1, 0.4 }, 40, 0.9)
        end
    elseif event.k == "shield" then
        addon.Animate.Ring("replayShield" .. event.s, widgets.replay, actor.model, 30, 120, { 0.4, 0.7, 1 })
    elseif event.k == "dodge" then
        addon.Animate.FloatText("replay" .. targetSide, target.float, target.model, 0, 40, Text["miss"], { 0.8, 0.8, 0.8 }, 30, 0.7)
    end
    if event.s and (event.k == "hit" or event.k == "crit") then addon.Animate.Pulse(actor.model, 1.08, 0.25) end
    -- the models act: the attacker strikes (its ability: a cast), the target flinches or dies
    local targetHealth = targetSide == "a" and event.ha or event.hb
    if event.k == "hit" or event.k == "crit" then
        ArenaView.PlayAnimation(actor.model, event.ab and "cast" or "attack", ACTION_SECONDS)
        react(targetSide, targetHealth, event.k == "crit")
    elseif event.k == "dot" then
        react(targetSide, targetHealth, false)
    elseif event.k == "dodge" then
        ArenaView.PlayAnimation(actor.model, "attack", ACTION_SECONDS)
        ArenaView.PlayAnimation(target.model, "dodge", ACTION_SECONDS)
    elseif event.k == "stun" then
        ArenaView.PlayAnimation(actor.model, "stun", ACTION_SECONDS * 2)
    elseif event.k == "shield" then
        ArenaView.PlayAnimation(actor.model, "cast", ACTION_SECONDS)
    end
end

-- Jumps to the end: final health, the winner's burst and line.
function ArenaView.FinishReplay()
    local replay = ArenaView.state
    if replay.ticker then replay.ticker:Cancel(); replay.ticker = nil end
    if not replay.result then return end
    ArenaView.Watched(replay.fight)
    local last = replay.result.events[#replay.result.events]
    if last then setHealth(replay.fight, replay.result, last.ha, last.hb) end
    replay.step = #replay.result.events
    local winnerSide = replay.result.winner
    local winner = winnerSide == "a" and replay.fight.fa or replay.fight.fb
    if last and replay.result.reason ~= "time" then   -- skipped to the end: the knocked-out side dies too (once)
        local loserSide = winnerSide == "a" and "b" or "a"
        if (loserSide == "a" and last.ha or last.hb) <= 0 then ArenaView.PlayDeath(sideWidgets(loserSide).model) end
    end
    widgets.replayLine:SetText("|cffffd100" .. Format(Text["{name} wins!"], { name = addon.Utility.Escape(addon.Utility.ShortText(winner.n, 24)) }) .. "|r"
        .. (replay.result.reason == "time" and (" |cff999999" .. Text["(on points)"] .. "|r") or ""))
    addon.Animate.Burst("replayWin", widgets.replay, sideWidgets(winnerSide).model, 0, 20, { count = 22, color = { 1, 0.82, 0.2 }, speed = 120, duration = 1.2 })
end

function ArenaView.StopReplay()
    local replay = ArenaView.state
    if replay.ticker then replay.ticker:Cancel(); replay.ticker = nil end
    local watching = replay.fight
    replay.fight, replay.result = nil, nil
    if widgets.replay then widgets.replay:Hide() end
    if watching then ArenaView.Watched(watching) end
end

-- The replay of `fight` ended (or was closed): its result may be shown now, and my money for it is settled at once
-- (the chat line with the result comes after the replay, never during it).
---@param fight ArenaFight|nil
function ArenaView.Watched(fight)
    if not fight or addon.Arena.State().watched[fight.id] then return end
    addon.Arena.MarkWatched(fight.id, now())
    addon.Catcher.ArenaTick(true)
end

------------------------------------------------------------------ the challenge modal

-- Opened by the one fight icon on another member's pet in the Guild view. Steps: 1 matchup (both companions), 2 wager
-- (presets or a custom amount, checked against my pool), 3 confirm (sends), then "sent". Back / Next at the bottom.
local STEP_TEXT = { Text["Matchup"], Text["Wager"], Text["Confirm"] }
local WAGER_PRESETS = { 0, 1, 5, 10, 50, 100 }   -- gold
ArenaView.challenge = { step = 1, wager = 0 }

---@param parent table the arena's Guild page
function ArenaView.BuildChallenge(parent)
    local Widgets = addon.UI.Widgets
    local dialog = CreateFrame("Frame", nil, parent)
    dialog:SetAllPoints(); dialog:SetFrameLevel(parent:GetFrameLevel() + 40); dialog:EnableMouse(true); dialog:Hide()
    local dim = dialog:CreateTexture(nil, "BACKGROUND"); dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.7)
    local box = CreateFrame("Frame", nil, dialog)
    box:SetSize(288, 290); box:SetPoint("TOP", 0, -24)
    local plate = box:CreateTexture(nil, "BORDER"); plate:SetAllPoints(); plate:SetColorTexture(0.07, 0.06, 0.09, 0.97)
    local line = box:CreateTexture(nil, "ARTWORK"); line:SetHeight(2); line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
    line:SetColorTexture(0.9, 0.3, 0.25, 0.9)
    widgets.challengeTitle = Widgets.CreateFontString(box, "GameFontNormal", "LEFT")
    widgets.challengeTitle:SetPoint("TOPLEFT", 10, -8); widgets.challengeTitle:SetWidth(240)
    local close = Widgets.CreateButton(box, "x", 20, 18, function() ArenaView.CloseChallenge() end)
    close:SetPoint("TOPRIGHT", -4, -5)
    -- the step track: 1 Matchup > 2 Wager > 3 Confirm
    widgets.stepLabels = {}
    for index = 1, #STEP_TEXT do
        local label = Widgets.CreateFontString(box, "GameFontHighlightSmall", "CENTER")
        label:SetPoint("TOPLEFT", 6 + (index - 1) * 92, -28); label:SetWidth(92)
        widgets.stepLabels[index] = label
    end
    widgets.stepBar = createBar(box, 276, 3, { 0.9, 0.3, 0.25 })
    widgets.stepBar:SetPoint("TOPLEFT", 6, -44)
    widgets.stepPages = {}
    for index = 1, 4 do
        local page = CreateFrame("Frame", nil, box)
        page:SetPoint("TOPLEFT", 0, -50); page:SetPoint("BOTTOMRIGHT", 0, 36)
        widgets.stepPages[index] = page
    end
    -- 1 matchup: my fighter left, theirs right
    local matchup = widgets.stepPages[1]
    for _, side in ipairs({ "mine", "theirs" }) do
        local part = {}
        part.model = addon.AzeCaughtPanel.CreateModel(matchup, 110, 94)
        part.model:SetPoint(side == "mine" and "TOPLEFT" or "TOPRIGHT", side == "mine" and 8 or -8, -2)
        part.text = Widgets.CreateFontString(matchup, "GameFontHighlightSmall", "CENTER")
        part.text:SetPoint("TOP", part.model, "BOTTOM", 0, -2); part.text:SetWidth(134)
        widgets[side == "mine" and "matchMine" or "matchTheirs"] = part
    end
    local versus = Widgets.CreateFontString(matchup, "GameFontNormalLarge", "CENTER")
    versus:SetPoint("TOP", 0, -40); versus:SetText("|cffff5040VS|r")
    widgets.matchNote = Widgets.CreateFontString(matchup, "GameFontDisableSmall", "CENTER")
    widgets.matchNote:SetPoint("BOTTOM", 0, 14); widgets.matchNote:SetWidth(276)
    -- 2 wager: presets, a custom amount, my pool
    local wager = widgets.stepPages[2]
    widgets.wagerButtons = {}
    for index, gold in ipairs(WAGER_PRESETS) do
        local amount = gold
        local button = Widgets.CreateButton(wager, gold == 0 and Text["No wager"] or money(gold * 10000), 84, 24,
            function() ArenaView.SetWager(amount * 10000) end)
        button:SetPoint("TOPLEFT", 12 + ((index - 1) % 3) * 90, -10 - math.floor((index - 1) / 3) * 30)
        button.copper = gold * 10000
        widgets.wagerButtons[index] = button
    end
    local customLabel = Widgets.CreateFontString(wager, "GameFontHighlightSmall", "RIGHT")
    customLabel:SetPoint("TOPRIGHT", wager, "TOP", 10, -82); customLabel:SetText(Text["Wager (gold)"])
    widgets.wagerBox = Widgets.CreateEditBox(wager, 60)
    widgets.wagerBox:SetPoint("LEFT", customLabel, "RIGHT", 8, 0)
    widgets.wagerPool = Widgets.CreateFontString(wager, "GameFontHighlightSmall", "CENTER")
    widgets.wagerPool:SetPoint("TOP", 0, -110); widgets.wagerPool:SetWidth(276)
    local wagerHint = Widgets.CreateFontString(wager, "GameFontDisableSmall", "CENTER")
    wagerHint:SetPoint("TOP", 0, -132); wagerHint:SetWidth(270)
    wagerHint:SetText(Text["Both pay the same wager; the winner takes both. A decline or no answer in 24 hours gives it back."])
    -- 3 confirm: the summary
    widgets.confirmSummary = Widgets.CreateFontString(widgets.stepPages[3], "GameFontHighlight", "CENTER")
    widgets.confirmSummary:SetPoint("TOP", 0, -24); widgets.confirmSummary:SetWidth(270)
    -- 4 sent
    widgets.sentText = Widgets.CreateFontString(widgets.stepPages[4], "GameFontNormalLarge", "CENTER")
    widgets.sentText:SetPoint("TOP", 0, -50); widgets.sentText:SetWidth(270)
    local sentHint = Widgets.CreateFontString(widgets.stepPages[4], "GameFontHighlightSmall", "CENTER")
    sentHint:SetPoint("TOP", widgets.sentText, "BOTTOM", 0, -12); sentHint:SetWidth(260)
    sentHint:SetText(Text["They have 24 hours to answer. Follow it in Arena > Fights."])
    -- the refusal line and the buttons
    widgets.challengeError = Widgets.CreateFontString(box, "GameFontHighlightSmall", "CENTER")
    widgets.challengeError:SetPoint("BOTTOM", 0, 34); widgets.challengeError:SetWidth(276)
    widgets.challengeBack = Widgets.CreateButton(box, Text["Back"], 90, 22, function() ArenaView.ChallengeBack() end)
    widgets.challengeBack:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.challengeNext = Widgets.CreateButton(box, Text["Next"], 110, 22, function() ArenaView.ChallengeNext() end)
    widgets.challengeNext:SetPoint("BOTTOMRIGHT", -8, 8)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.challengeNext) end
    widgets.challengeBox, widgets.challenge = box, dialog
    parent:HookScript("OnHide", function() ArenaView.CloseChallenge() end)
end

local function companionLine(row, arena)
    local lines = { "|cffffd100" .. addon.Utility.ShortText(row.companion, 18) .. "|r", Text["Level"] .. " " .. row.lvl .. " · " .. addon.Model.RarityText(row.cls),
        ("|cffff4060%+d|r"):format(row.hearts or 0) }
    if type(arena) == "table" then lines[#lines + 1] = Format(Text["Arena {wins}-{losses}"], { wins = arena.w or 0, losses = arena.l or 0 }) end
    if row.asleep then lines[#lines + 1] = "|cff999999" .. Text["asleep"] .. "|r" end
    return table.concat(lines, "\n")
end

-- The wager in the box in copper, or nil and the refusal.
---@return integer|nil
---@return string|nil
function ArenaView.ReadWager()
    local gold = tonumber(widgets.wagerBox:GetText() or "")
    if not gold or gold < 0 then return nil, "wager" end
    local copper = math.floor(gold * 10000)
    if copper > addon.Arena.MAXIMUM_WAGER then return nil, "wager" end
    if copper > 0 then
        local refusal = addon.Wallet.FundsRefusal(me(), copper)
        if refusal then return nil, refusal end
    end
    return copper
end

---@param copper integer
function ArenaView.SetWager(copper)
    ArenaView.challenge.wager = copper
    widgets.wagerBox:SetText(tostring(math.floor(copper / 10000)))
    for _, button in ipairs(widgets.wagerButtons) do
        if button.SetSelected then button:SetSelected(button.copper == copper) end
        button:SetAlpha(button.copper == copper and 1 or 0.7)
    end
end

-- Shows step `step` (1..4): the page, the track, the buttons.
---@param step integer
function ArenaView.ShowChallengeStep(step)
    local challenge = ArenaView.challenge
    challenge.step = step
    widgets.challengeError:SetText("")
    for index, page in ipairs(widgets.stepPages) do page:SetShown(index == step) end
    for index, label in ipairs(widgets.stepLabels) do
        local color = index == step and "|cffffd100" or index < step and "|cff66ff66" or "|cff777777"
        label:SetText(color .. index .. "  " .. STEP_TEXT[index] .. "|r")
    end
    addon.Animate.Tween("challengeStep", 0.25, function(elapsed)
        widgets.stepBar:SetValue(((step - 1) + math.min(1, elapsed / 0.25)) / 3)
    end, function() widgets.stepBar:SetValue(math.min(step, 3) / 3) end)
    widgets.challengeBack:SetLabel(step == 1 and Text["Cancel"] or Text["Back"])
    widgets.challengeBack:SetShown(step < 4)
    widgets.challengeNext:SetLabel(step == 3 and Text["Send challenge"] or step == 4 and Text["Close"] or Text["Next"])
    local opponent = short(challenge.opponent)
    widgets.challengeTitle:SetText(Format(Text["Challenge {name}"], { name = opponent }))
    if step == 1 then
        local companion = addon.AzeCaught.Active()
        local fighter = companion and addon.Arena.Fighter(companion)
        local mine = widgets.matchMine
        if fighter then
            addon.AzeCaughtPanel.ShowModel(mine.model, { npc = companion.npc, disp = companion.disp }, "challenge")
            local level = addon.Arena.Level(addon.Arena.Npc(companion.npc).xp)
            mine.text:SetText(("|cffffd100%s|r\n%s\n%s %d · %s %d\n%s %d · %s %d\n|cff999999%s|r"):format(addon.Utility.Escape(addon.Utility.ShortText(fighter.n, 18)),
                Format(Text["Arena level {level}"], { level = level }), Text["Attack"], fighter.atk, Text["Defense"], fighter.def,
                Text["Speed"], fighter.spd, Text["Vitality"], fighter.vit, ABILITY_NAME[fighter.ab])
                .. (fighter.bf and ("\n" .. ArenaView.BuffIcons(fighter.bf) .. " |cff66ff66" .. Text["Buffs used in this fight"] .. "|r") or ""))
        else
            addon.AzeCaughtPanel.ShowModel(mine.model, nil, "challenge")
            mine.text:SetText("|cffff6060" .. Text["You have no companion."] .. "|r")
        end
        local row = challenge.row
        addon.AzeCaughtPanel.ShowModel(widgets.matchTheirs.model, { npc = row.npc, disp = row.disp }, "challenge")
        if widgets.matchTheirs.model.SetFacing then pcall(widgets.matchTheirs.model.SetFacing, widgets.matchTheirs.model, -0.6) end
        widgets.matchTheirs.text:SetText(companionLine(row, (records()[row.nameRaw] or {}).arena))
        widgets.matchNote:SetText(Text["Their stats show once they accept. The fight runs on its own."])
    elseif step == 2 then
        widgets.wagerPool:SetText(Format(Text["Your pool: {gold} · at most {maximum}"], { gold = money(addon.Wallet.Balance(me())),
            maximum = money(addon.Arena.MAXIMUM_WAGER) }))
        ArenaView.SetWager(challenge.wager or 0)
    elseif step == 3 then
        local companion = addon.AzeCaught.Active()
        local lines = { Format(Text["{mine} vs {theirs}"], { mine = addon.Utility.Escape(companion and companion.n or "?"),
            theirs = challenge.row.companion }), Format(Text["against {name}"], { name = opponent }), "" }
        lines[#lines + 1] = challenge.wager > 0 and ("|cffffd100" .. Format(Text["Wager: {gold} each"], { gold = money(challenge.wager) }) .. "|r")
            or Text["No wager: just for honor and XP."]
        if challenge.wager > 0 then lines[#lines + 1] = "|cff999999" .. Text["Your stake leaves your pool now."] .. "|r" end
        widgets.confirmSummary:SetText(table.concat(lines, "\n"))
    else
        widgets.sentText:SetText("|cff66ff66" .. Text["Challenge sent."] .. "|r")
        addon.Animate.Pulse(widgets.sentText, 1.3, 0.35)
        addon.Animate.Burst("challengeSent", widgets.challengeBox, widgets.sentText, 0, 0, { count = 18, color = { 1, 0.82, 0.2 }, speed = 100, duration = 1 })
    end
end

-- Opens the modal for a guild row (not my own). Returns true when it opened.
---@param row CompanionRow|nil
---@return boolean
function ArenaView.OpenChallenge(row)
    if not widgets.challenge or not row or row.mine then return false end
    local challenge = ArenaView.challenge
    challenge.row, challenge.opponent, challenge.wager = row, row.nameRaw, 0
    widgets.challenge:Show()
    widgets.challengeBox:SetAlpha(0)
    addon.Animate.FadeIn(widgets.challengeBox, 0.2)
    ArenaView.ShowChallengeStep(1)
    return true
end

function ArenaView.CloseChallenge()
    if widgets.challenge then widgets.challenge:Hide() end
    ArenaView.challenge.row = nil
end

local function challengeError(reason)
    widgets.challengeError:SetText("|cffff6060" .. ArenaView.RefusalText(reason) .. "|r")
    addon.Animate.Shake(widgets.challengeBox, 4, 4)
end

function ArenaView.ChallengeNext()
    local challenge = ArenaView.challenge
    local step = challenge.step
    if step == 1 then
        if not addon.AzeCaught.Active() then challengeError("nocompanion") return end
        local fights = addon.Arena.Fights(records(), me(), now())
        if addon.Arena.Busy(fights, me(), true) then challengeError("busy") return end
        if addon.Arena.Busy(fights, challenge.opponent, false) then challengeError("theybusy") return end
        ArenaView.ShowChallengeStep(2)
    elseif step == 2 then
        local copper, reason = ArenaView.ReadWager()
        if not copper then challengeError(reason) return end
        challenge.wager = copper
        ArenaView.ShowChallengeStep(3)
    elseif step == 3 then
        local id, reason = addon.Arena.Challenge(records(), me(), challenge.opponent or "", challenge.wager or 0, now())
        if not id then challengeError(reason) return end
        addon.Catcher.PublishArena()
        ArenaView.ShowChallengeStep(4)
    else
        ArenaView.CloseChallenge()
    end
end

function ArenaView.ChallengeBack()
    local step = ArenaView.challenge.step
    if step <= 1 or step >= 4 then ArenaView.CloseChallenge() else ArenaView.ShowChallengeStep(step - 1) end
end

------------------------------------------------------------------ build and refresh

---@param page "fighter"|"fights"|"guild"
function ArenaView.SelectPage(page)
    -- (an older saved "fighter" page opens Guild: the fighter moved into the Companion view)
    ArenaView.state.page = page == "fights" and "fights" or "guild"
    widgets.fightsPage:SetShown(ArenaView.state.page == "fights")
    widgets.guildPage:SetShown(ArenaView.state.page == "guild")
    for key, button in pairs(widgets.pageButtons) do
        button:SetEnabled(key ~= ArenaView.state.page)
        if button.SetSelected then button:SetSelected(key == ArenaView.state.page) end
    end
    ArenaView.Refresh()
end

-- Builds the view into `panel` (the AZEcaught panel's arena frame, 300 x 336).
---@param panel table
function ArenaView.Build(panel)
    local Widgets = addon.UI.Widgets
    widgets.panel = panel
    widgets.pageButtons = {}
    -- Guild, Fights (AzeCaughtPanel builds the guild list into guildPage)
    local labels = { fights = Text["Fights"], guild = Text["Guild"] }
    for index, page in ipairs({ "guild", "fights" }) do
        local key = page
        local button = Widgets.CreateButton(panel, labels[page], 143, 18, function() ArenaView.SelectPage(key) end)
        button:SetPoint("TOPLEFT", 4 + (index - 1) * 149, -24)
        widgets.pageButtons[page] = button
    end
    widgets.fightsPage = CreateFrame("Frame", nil, panel); widgets.fightsPage:SetAllPoints()
    widgets.guildPage = CreateFrame("Frame", nil, panel); widgets.guildPage:SetAllPoints()
    buildFightsPage(widgets.fightsPage)
    buildReplay(panel)
    panel:HookScript("OnHide", function() ArenaView.StopReplay() end)
    ArenaView.SelectPage(ArenaView.state.page)
end

function ArenaView.Refresh()
    if not widgets.panel then return end
    local incoming = 0
    for _, row in ipairs(ArenaView.FightRows()) do if row.state == "incoming" then incoming = incoming + 1 end end
    widgets.pageButtons.fights:SetLabel(incoming > 0 and ("|cffffd100" .. Format(Text["Fights ({n} new)"], { n = incoming }) .. "|r") or Text["Fights"])
    if ArenaView.state.page == "guild" then addon.AzeCaughtPanel.RefreshGuild()
    else ArenaView.RefreshFights() end
    if addon.AzeCaughtPanel.UpdateGuide then addon.AzeCaughtPanel.UpdateGuide() end
end
