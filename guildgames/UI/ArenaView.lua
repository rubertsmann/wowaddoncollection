local _, addon = ...

-- The AZEcaught "Arena" view (feature 020, R10): my fighter (arena level, XP, wins/losses, the four stats with their
-- training) and the fights (incoming challenges to answer, open fights to bet on, finished fights to watch), plus the
-- replay: both models, health bars, floating damage, a shake on every hit and a burst for the winner. Hands-off: the
-- fight is already decided (Arena.Fight); the replay only shows it.
local ArenaView = {}
addon.ArenaView = ArenaView

local Text, Format = addon.Text, addon.Locale.Format
local money = addon.Model.MoneyText
local widgets = {}
ArenaView.widgets = widgets
ArenaView.state = { page = "fighter", selected = nil }

local STAT_ICONS = { atk = "Interface\\Icons\\Ability_Warrior_Cleave", def = "Interface\\Icons\\INV_Shield_06",
    spd = "Interface\\Icons\\Ability_Rogue_Sprint", vit = "Interface\\Icons\\Spell_Holy_SealOfVitality" }
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

------------------------------------------------------------------ fighter page

local function trainRefusalText(reason)
    local texts = { busy = Text["Already training."], maximum = Text["This stat is fully trained."], asleep = Text["Your companion is asleep."],
        energy = Text["Your companion is too tired to train."], funds = Text["Not enough gold in your pool."],
        nocompanion = Text["You have no companion."], readonly = Text["Saved data is read-only."] }
    return texts[reason] or tostring(reason)
end

---@param panel table
local function buildFighterPage(panel)
    local Widgets = addon.UI.Widgets
    local model = addon.AzeCaughtPanel.CreateModel(panel, 110, 132)
    model:SetPoint("TOPLEFT", 4, -46)
    widgets.fighterModel = model
    widgets.fighterName = Widgets.CreateFontString(panel, "GameFontNormal", "CENTER")
    widgets.fighterName:SetPoint("TOP", model, "BOTTOM", 0, -2); widgets.fighterName:SetWidth(116)
    widgets.fighterLevel = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.fighterLevel:SetPoint("TOP", widgets.fighterName, "BOTTOM", 0, -2); widgets.fighterLevel:SetWidth(116)
    widgets.xpBar = createBar(panel, 106, 6, { 0.55, 0.35, 1 })
    widgets.xpBar:SetPoint("TOP", widgets.fighterLevel, "BOTTOM", 0, -3)
    widgets.record = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.record:SetPoint("TOP", widgets.xpBar, "BOTTOM", 0, -4); widgets.record:SetWidth(116)
    widgets.statRows = {}
    for index, stat in ipairs(addon.Arena.STATS) do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(176, 32); row:SetPoint("TOPLEFT", 120, -46 - (index - 1) * 34)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(24, 24); row.icon:SetPoint("LEFT", 0, 0)
        addon.UIHelpers.SetTextureOr(row.icon, STAT_ICONS[stat], { 0.6, 0.6, 0.6 })
        if row.icon.SetTexCoord then row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        row.label = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT"); row.label:SetPoint("TOPLEFT", 28, -2); row.label:SetWidth(92)
        row.points = Widgets.CreateFontString(row, "GameFontDisableSmall", "LEFT"); row.points:SetPoint("BOTTOMLEFT", 28, 3); row.points:SetWidth(92)
        local key = stat
        row.train = Widgets.CreateButton(row, Text["Train"], 52, 20, function() ArenaView.Train(key) end)
        row.train:SetPoint("RIGHT", 0, 0)
        row.train:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            local npc = addon.AzeCaught.Active() and addon.Arena.Npc(addon.AzeCaught.Active().npc)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(STAT_TEXT[key], 1, 0.82, 0)
            GameTooltip:AddLine(Format(Text["Costs {gold} and {energy} energy, takes {minutes} minutes of play time."],
                { gold = money(addon.Arena.TrainCost(npc and npc.tr[key] or 0)), energy = addon.Arena.TRAIN_ENERGY,
                  minutes = math.floor(addon.Arena.TRAIN_SECONDS / 60) }), 1, 1, 1, true)
            GameTooltip:AddLine(Format(Text["+{percent}% per point, at most {maximum} points."],
                { percent = math.floor(addon.Arena.TRAIN_BONUS * 100), maximum = addon.Arena.MAXIMUM_TRAINING }), 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        row.train:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        widgets.statRows[stat] = row
    end
    widgets.trainBar = createBar(panel, 176, 6, { 1, 0.75, 0.2 })
    widgets.trainBar:SetPoint("TOPLEFT", 120, -186)
    widgets.trainText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "LEFT")
    widgets.trainText:SetPoint("TOPLEFT", 120, -196); widgets.trainText:SetWidth(176)
    widgets.ability = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "LEFT")
    widgets.ability:SetPoint("TOPLEFT", 6, -250); widgets.ability:SetWidth(288)
    widgets.fighterStatus = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.fighterStatus:SetPoint("TOP", 0, -272); widgets.fighterStatus:SetWidth(290)
    local hint = Widgets.CreateFontString(panel, "GameFontDisableSmall", "CENTER")
    hint:SetPoint("TOP", 0, -292); hint:SetWidth(290)
    hint:SetText(Text["Challenge a guild member in the Guild view. Fights are fought on their own: train, then watch."])
    widgets.noFighter = Widgets.CreateFontString(panel, "GameFontDisable", "CENTER")
    widgets.noFighter:SetPoint("TOP", 0, -110); widgets.noFighter:SetWidth(270)
    widgets.noFighter:SetText(Text["You need a companion to fight. Catch one and make it your companion."])
end

function ArenaView.Train(stat)
    local ok, reason = addon.Arena.Train(me(), stat, now())
    if ok then
        widgets.fighterStatus:SetText("")
        addon.Animate.Pulse(widgets.statRows[stat].icon and widgets.statRows[stat] or widgets.trainBar, 1.15, 0.3)
        addon.Events.Fire("CAUGHT_CHANGED")
    else
        widgets.fighterStatus:SetText("|cffff6060" .. trainRefusalText(reason) .. "|r")
    end
end

function ArenaView.RefreshFighter()
    local Arena, AzeCaught = addon.Arena, addon.AzeCaught
    local companion = AzeCaught.Active()
    local fighter = companion and Arena.Fighter(companion)
    widgets.noFighter:SetShown(fighter == nil)
    for _, row in pairs(widgets.statRows) do row:SetShown(fighter ~= nil) end
    for _, region in ipairs({ widgets.fighterModel, widgets.fighterName, widgets.fighterLevel, widgets.xpBar, widgets.record,
        widgets.trainBar, widgets.trainText, widgets.ability }) do region:SetShown(fighter ~= nil) end
    if not fighter then return end
    local npc = Arena.Npc(companion.npc)
    local level, into, needed = Arena.Level(npc.xp)
    if widgets.fighterModel.shownNpc ~= companion.npc then
        addon.AzeCaughtPanel.ShowModel(widgets.fighterModel, { npc = companion.npc, disp = companion.disp }, "arena")
        widgets.fighterModel.shownNpc = companion.npc
    end
    widgets.fighterName:SetText(addon.Utility.Escape(fighter.n))
    widgets.fighterLevel:SetText(Format(Text["Arena level {level}"], { level = level })
        .. (needed > 0 and ("  |cff999999" .. into .. "/" .. needed .. " XP|r") or ""))
    widgets.xpBar:SetValue(needed > 0 and into / needed or 1)
    widgets.record:SetText(Format(Text["Wins {wins} · Losses {losses}"], { wins = npc.w, losses = npc.l }))
    local training = Arena.State().training
    for _, stat in ipairs(Arena.STATS) do
        local row = widgets.statRows[stat]
        row.label:SetText(STAT_TEXT[stat] .. "  |cffffffff" .. fighter[stat] .. "|r")
        row.points:SetText(Format(Text["Trained {points}/{maximum}"], { points = npc.tr[stat], maximum = Arena.MAXIMUM_TRAINING }))
        row.train:SetEnabled(training == nil and npc.tr[stat] < Arena.MAXIMUM_TRAINING)
    end
    local left = Arena.TrainingLeft()
    if training and left then
        widgets.trainBar:SetValue(1 - left / Arena.TRAIN_SECONDS)
        widgets.trainText:SetText(Format(Text["Training {stat}: {time} left (play time)"], { stat = STAT_TEXT[training.stat], time = clock(left) }))
    else
        widgets.trainBar:SetValue(0)
        widgets.trainText:SetText(Text["Not training."])
    end
    widgets.ability:SetText(Text["Ability"] .. ": |cffffd100" .. ABILITY_TEXT[fighter.ab] .. "|r")
end

------------------------------------------------------------------ fights page

-- Display rows for the fight list: incoming first, then open, then waiting, then finished (newest first).
---@return table[]
function ArenaView.FightRows()
    local Arena = addon.Arena
    local myName, time = me(), now()
    local rows = {}
    local order = { incoming = 1, open = 2, pending = 3, lapsed = 3, done = 4, declined = 5, expired = 5 }
    for id, fight in pairs(Arena.Fights(records(), myName, time)) do
        local state = fight.state
        if state == "pending" and fight.b == myName and not Arena.State().an[id] then state = "incoming" end
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
    if row.state == "open" then return "|cff66ccff" .. Format(Text["in {time}"], { time = clock(fight.fightAt - now()) }) .. "|r" end
    if row.state == "pending" or row.state == "lapsed" then return "|cff999999" .. Text["waiting"] .. "|r" end
    if row.state == "declined" then return "|cff999999" .. Text["declined"] .. "|r" end
    if row.state == "expired" then return "|cff999999" .. Text["expired"] .. "|r" end
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
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self) if self.entry then ArenaView.state.selected = self.entry.id; ArenaView.Refresh() end end)
    return row
end

local function fillFightRow(row, entry)
    row.selected:SetShown(entry.id == ArenaView.state.selected)
    row.names:SetText(short(entry.fight.a) .. " |cff999999vs|r " .. short(entry.fight.b)
        .. (entry.fight.wager > 0 and ("  |cffffd100" .. money(entry.fight.wager) .. "|r") or ""))
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
    widgets.acceptButton = Widgets.CreateButton(panel, Text["Accept"], 90, 22, function() ArenaView.Answer(true) end)
    widgets.acceptButton:SetPoint("TOPLEFT", 8, y)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.acceptButton) end
    widgets.declineButton = Widgets.CreateButton(panel, Text["Decline"], 90, 22, function() ArenaView.Answer(false) end)
    widgets.declineButton:SetPoint("LEFT", widgets.acceptButton, "RIGHT", 6, 0)
    widgets.betBox = Widgets.CreateEditBox(panel, 44)
    widgets.betBox:SetPoint("TOPLEFT", 8, y - 2)
    widgets.betBox:SetText("1")
    widgets.betLabel = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "LEFT")
    widgets.betLabel:SetPoint("LEFT", widgets.betBox, "RIGHT", 3, 0); widgets.betLabel:SetText(Text["gold on"])
    widgets.betA = Widgets.CreateButton(panel, "A", 84, 22, function() ArenaView.Bet("a") end)
    widgets.betA:SetPoint("TOPLEFT", 104, y)
    widgets.betB = Widgets.CreateButton(panel, "B", 84, 22, function() ArenaView.Bet("b") end)
    widgets.betB:SetPoint("LEFT", widgets.betA, "RIGHT", 4, 0)
    widgets.watchButton = Widgets.CreateButton(panel, Text["Watch"], 90, 22, function() ArenaView.Watch(ArenaView.state.selected) end)
    widgets.watchButton:SetPoint("TOPRIGHT", -8, y)
    widgets.fightStatus = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.fightStatus:SetPoint("TOP", 0, y - 28); widgets.fightStatus:SetWidth(290)
end

local REFUSALS = { readonly = Text["Saved data is read-only."], unknown = Text["This fight is gone."], answered = Text["Already answered."],
    late = Text["Too late to answer."], nocompanion = Text["You have no companion."], funds = Text["Not enough gold in your pool."],
    closed = Text["Bets are closed for this fight."], own = Text["You cannot bet on your own fight."], twice = Text["You already bet on this fight."],
    stake = Text["Bet between {minimum} and {maximum}."], self = Text["You cannot challenge yourself."],
    nocompanionthere = Text["That player has no companion."], open = Text["You have too many open challenges."],
    wager = Text["The wager is too high."], opponent = Text["Choose a guild member first."] }
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

function ArenaView.Answer(accept)
    local id = ArenaView.state.selected
    local ok, reason = addon.Arena.Answer(records(), me(), id, accept, now())
    showResult(ok, reason, accept and Text["Accepted. The fight is decided in 5 minutes."] or Text["Declined."])
end

function ArenaView.Bet(side)
    local id = ArenaView.state.selected
    local gold = tonumber(widgets.betBox:GetText() or "")
    local odds, reason = addon.Arena.Bet(records(), me(), id, side, gold and math.floor(gold * 10000) or 0, now())
    showResult(odds, reason, odds and Format(Text["Bet placed at {odds}x."], { odds = ("%.2f"):format(odds / 100) }))
end

---@param fight ArenaFight
---@return string
local function fighterLine(fighter)
    if not fighter then return "?" end
    return ("%s |cff999999(%s %d, %s)|r"):format(addon.Utility.Escape(fighter.n), Text["Lv"], fighter.al, ABILITY_NAME[fighter.ab])
end

function ArenaView.RefreshFights()
    local rows = ArenaView.FightRows()
    widgets.fightList:SetData(rows)
    widgets.noFights:SetShown(#rows == 0)
    local selected
    for _, row in ipairs(rows) do if row.id == ArenaView.state.selected then selected = row end end
    if not selected and rows[1] then selected = rows[1]; ArenaView.state.selected = rows[1].id end
    for _, region in ipairs({ widgets.acceptButton, widgets.declineButton, widgets.betBox, widgets.betLabel, widgets.betA, widgets.betB, widgets.watchButton }) do
        region:Hide()
    end
    if not selected then widgets.detail:SetText("") return end
    local fight, myName = selected.fight, me()
    local lines = { short(fight.a) .. ": " .. fighterLine(fight.fa), short(fight.b) .. ": " .. fighterLine(fight.fb) }
    if fight.wager > 0 then lines[#lines + 1] = Format(Text["Wager: {gold} each"], { gold = money(fight.wager) }) end
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
    widgets.detail:SetText(table.concat(lines, "\n"))
    if selected.state == "incoming" then
        widgets.acceptButton:Show(); widgets.declineButton:Show()
    elseif selected.state == "open" and fight.a ~= myName and fight.b ~= myName and not myBet then
        widgets.betBox:Show(); widgets.betLabel:Show()
        widgets.betA:SetLabel(short(fight.a)); widgets.betB:SetLabel(short(fight.b))
        widgets.betA:Show(); widgets.betB:Show()
    elseif selected.state == "done" then
        widgets.watchButton:Show()
    end
end

------------------------------------------------------------------ replay

local function sideWidgets(side) return side == "a" and widgets.replayLeft or widgets.replayRight end

---@param parent table
local function buildReplay(parent)
    local Widgets = addon.UI.Widgets
    local replay = CreateFrame("Frame", nil, parent)
    replay:SetAllPoints(); replay:SetFrameLevel(parent:GetFrameLevel() + 30); replay:EnableMouse(true); replay:Hide()
    local back = replay:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(0.03, 0.02, 0.05, 0.97)
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
        part.float = Widgets.CreateFontString(replay, "GameFontNormalLarge", "CENTER"); part.float:Hide()
        if side == "a" then widgets.replayLeft = part else widgets.replayRight = part end
    end
    widgets.replayVersus = Widgets.CreateFontString(replay, "GameFontNormalLarge", "CENTER")
    widgets.replayVersus:SetPoint("TOP", 0, -120); widgets.replayVersus:SetText("VS")
    widgets.replayLine = Widgets.CreateFontString(replay, "GameFontHighlight", "CENTER")
    widgets.replayLine:SetPoint("BOTTOM", 0, 44); widgets.replayLine:SetWidth(290)
    local close = Widgets.CreateButton(replay, Text["Close"], 80, 20, function() ArenaView.StopReplay() end)
    close:SetPoint("BOTTOMRIGHT", -6, 8)
    local skip = Widgets.CreateButton(replay, Text["Skip"], 80, 20, function() ArenaView.FinishReplay() end)
    skip:SetPoint("BOTTOMLEFT", 6, 8)
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
        part.name:SetText(addon.Utility.Escape(fighter.n) .. " |cff999999(" .. short(side == "a" and fight.a or fight.b) .. ")|r")
        addon.AzeCaughtPanel.ShowModel(part.model, { npc = fighter.npc, disp = fighter.disp }, "replay")
        if part.model.SetFacing then pcall(part.model.SetFacing, part.model, side == "a" and 0.9 or -0.9) end
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
end

-- Jumps to the end: final health, the winner's burst and line.
function ArenaView.FinishReplay()
    local replay = ArenaView.state
    if replay.ticker then replay.ticker:Cancel(); replay.ticker = nil end
    if not replay.result then return end
    local last = replay.result.events[#replay.result.events]
    if last then setHealth(replay.fight, replay.result, last.ha, last.hb) end
    replay.step = #replay.result.events
    local winnerSide = replay.result.winner
    local winner = winnerSide == "a" and replay.fight.fa or replay.fight.fb
    widgets.replayLine:SetText("|cffffd100" .. Format(Text["{name} wins!"], { name = addon.Utility.Escape(winner.n) }) .. "|r"
        .. (replay.result.reason == "time" and (" |cff999999" .. Text["(on points)"] .. "|r") or ""))
    addon.Animate.Burst("replayWin", widgets.replay, sideWidgets(winnerSide).model, 0, 20, { count = 22, color = { 1, 0.82, 0.2 }, speed = 120, duration = 1.2 })
end

function ArenaView.StopReplay()
    local replay = ArenaView.state
    if replay.ticker then replay.ticker:Cancel(); replay.ticker = nil end
    replay.fight, replay.result = nil, nil
    if widgets.replay then widgets.replay:Hide() end
end

------------------------------------------------------------------ build and refresh

---@param page "fighter"|"fights"
function ArenaView.SelectPage(page)
    ArenaView.state.page = page == "fights" and "fights" or "fighter"
    widgets.fighterPage:SetShown(ArenaView.state.page == "fighter")
    widgets.fightsPage:SetShown(ArenaView.state.page == "fights")
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
    for index, page in ipairs({ "fighter", "fights" }) do
        local key = page
        local button = Widgets.CreateButton(panel, page == "fighter" and Text["Fighter"] or Text["Fights"], 140, 18, function() ArenaView.SelectPage(key) end)
        button:SetPoint("TOPLEFT", 4 + (index - 1) * 146, -24)
        widgets.pageButtons[page] = button
    end
    widgets.fighterPage = CreateFrame("Frame", nil, panel); widgets.fighterPage:SetAllPoints()
    widgets.fightsPage = CreateFrame("Frame", nil, panel); widgets.fightsPage:SetAllPoints()
    buildFighterPage(widgets.fighterPage)
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
    if ArenaView.state.page == "fighter" then ArenaView.RefreshFighter() else ArenaView.RefreshFights() end
end
