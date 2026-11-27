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

-- A fighter's name in their side's colour, like the team picker: the challenger ("a") red, the challenged player ("b")
-- blue.
local SIDE_HEX = { a = "ff5a48", b = "6a9cff" }
local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local BET_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"   -- my bet is on this fight (the fight list)
---@param name string
---@param side "a"|"b"
---@return string
function ArenaView.SideName(name, side) return "|cff" .. SIDE_HEX[side] .. short(name) .. "|r" end
local sideName = ArenaView.SideName
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
    if training and training.uid ~= companion.uid then training = nil end
    return { companion = companion, fighter = fighter, npc = Arena.Progress(companion), training = training,
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
        expired = 5, withdrawn = 5, version = 5 }
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
    if row.state == "version" then return "|cffff9933" .. Text["other version"] .. "|r" end
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
    -- Stop my own waiting challenge right in the row (Accept / Decline are below the list)
    local height = math.max(14, (Widgets.ROW_HEIGHT or 18) - 2)
    row.stop = Widgets.CreateButton(row, Text["Stop"], 56, height, function() if row.entry then ArenaView.Withdraw(row.entry.id) end end)
    row.stop:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.entry then ArenaView.state.selected, ArenaView.state.refusal = self.entry.id, nil; ArenaView.Refresh() end
    end)
    return row
end

local function fillFightRow(row, entry)
    row.selected:SetShown(entry.id == ArenaView.state.selected)
    row.names:SetText(sideName(entry.fight.a, "a") .. " |cff999999vs|r " .. sideName(entry.fight.b, "b")
        .. "  |cffffd100" .. money(entry.fight.wager) .. (entry.fight.wagerB and (" : " .. money(entry.fight.wagerB)) or "") .. "|r"
        .. (addon.Arena.State().bt[entry.id] and (" |T" .. BET_ICON .. ":12:12|t") or ""))
    local stoppable = (entry.state == "pending" or entry.state == "lapsed" or entry.state == "countered") and entry.fight.a == me()
    row.stop:SetShown(stoppable)
    row.info:SetShown(not stoppable)
    row.info:SetText(stateText(entry))
end

local MEMBER_ROWS = 8
local FIGHT_ROWS = 4   -- the fight list; the selected fight fills the framed box below it

-- A member row of the dropdown: the name, and on the right why they can't be challenged (greyed, the tooltip says more).
local function createMemberRow(list)
    local Widgets = addon.UI.Widgets
    local row = CreateFrame("Button", nil, list)
    row.hover = row:CreateTexture(nil, "BACKGROUND"); row.hover:SetAllPoints(); row.hover:SetColorTexture(1, 1, 1, 0.08); row.hover:Hide()
    row.name = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT"); row.name:SetPoint("LEFT", 6, 0); row.name:SetWidth(170)
    row.info = Widgets.CreateFontString(row, "GameFontDisableSmall", "RIGHT"); row.info:SetPoint("RIGHT", -6, 0); row.info:SetWidth(110)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if not GameTooltip or not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(short(self.entry.name), 1, 0.82, 0)
        GameTooltip:AddLine(ArenaView.CandidateText(self.entry), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide(); if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self) if self.entry then ArenaView.PickMember(self.entry.name) end end)
    return row
end

local function fillMemberRow(row, entry)
    local available = entry.reason == nil
    row.name:SetText((available and "" or "|cff777777") .. short(entry.name) .. (available and "" or "|r"))
    row.info:SetText(available and "" or ArenaView.CandidateShort(entry.reason))
end

-- A dark shade and a 1 px border in `color` around `frame`.
---@param frame table
---@param color number[]
---@param shade number the shade's alpha
local function addBorder(frame, color, shade)
    local back = frame:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(0, 0, 0, shade)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1]); line:SetPoint(edge[2])
        if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
        line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

-- An action panel in the fight box (answer a challenge, place a bet): a gold border, a header on a gold strip, room
-- for one row of controls. Returns the frame and its header.
---@param panel table
---@param top number
---@return table frame
---@return table header
local function buildActionPanel(panel, top)
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetPoint("TOPLEFT", 8, top); frame:SetSize(282, 52)
    addBorder(frame, { 1, 0.82, 0.25, 0.95 }, 0.55)
    local strip = frame:CreateTexture(nil, "ARTWORK"); strip:SetPoint("TOPLEFT", 1, -1); strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(18); strip:SetColorTexture(0.45, 0.33, 0.08, 0.85)
    local header = addon.UI.Widgets.CreateFontString(frame, "GameFontNormal", "CENTER")
    header:SetPoint("TOP", 0, -3); header:SetWidth(272)
    frame:Hide()
    return frame, header
end

---@param panel table
local function buildFightsPage(panel)
    local Widgets = addon.UI.Widgets
    -- the fight request: a dropdown of the guild members, then "Fight!" opens the team picker with my wager
    local dropdown = Widgets.CreateButton(panel, Text["Choose a guild member"], 196, 22, function() ArenaView.ToggleMemberMenu() end)
    dropdown:SetPoint("TOPLEFT", 4, -46)
    widgets.memberDropdown = dropdown
    widgets.requestButton = Widgets.CreateButton(panel, Text["Fight!"], 90, 22, function() ArenaView.Request() end)
    widgets.requestButton:SetPoint("LEFT", dropdown, "RIGHT", 6, 0)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.requestButton) end
    local menu = CreateFrame("Frame", nil, panel)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2); menu:SetSize(292, Widgets.ROW_HEIGHT * MEMBER_ROWS + 6)   -- the full width of the page
    menu:SetFrameLevel(panel:GetFrameLevel() + 30); menu:EnableMouse(true); menu:Hide()
    local plate = menu:CreateTexture(nil, "BACKGROUND"); plate:SetAllPoints(); plate:SetColorTexture(0.06, 0.05, 0.08, 1)
    -- fully opaque, also while the window around it is faded (the list covers the fights below it)
    if menu.SetIgnoreParentAlpha then menu:SetIgnoreParentAlpha(true) end
    local edge = menu:CreateTexture(nil, "BORDER"); edge:SetHeight(1); edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT")
    edge:SetColorTexture(1, 0.78, 0.25, 0.8)
    widgets.memberList = Widgets.CreateScrollList(menu, 288, Widgets.ROW_HEIGHT * MEMBER_ROWS, createMemberRow, fillMemberRow)
    widgets.memberList:SetPoint("TOPLEFT", 2, -3)
    widgets.noMembers = Widgets.CreateFontString(menu, "GameFontDisableSmall", "CENTER")
    widgets.noMembers:SetPoint("TOP", 0, -20); widgets.noMembers:SetWidth(270)
    widgets.noMembers:SetText(Text["Nobody in the guild has a companion yet."])
    widgets.memberMenu = menu
    panel:HookScript("OnHide", function() menu:Hide() end)
    -- the fights
    local top = -46 - 28
    widgets.fightList = Widgets.CreateScrollList(panel, 292, Widgets.ROW_HEIGHT * FIGHT_ROWS, createFightRow, fillFightRow)
    widgets.fightList:SetPoint("TOPLEFT", 4, top)
    widgets.noFights = Widgets.CreateFontString(panel, "GameFontDisable", "CENTER")
    widgets.noFights:SetPoint("TOP", 0, top - 24); widgets.noFights:SetWidth(270)
    widgets.noFights:SetText(Text["No fights yet. Pick a guild member above and send a request."])
    -- the selected fight in a framed box below the list: both teams as carousels side by side (the challenger left,
    -- red; the challenged player right, blue), then the pot, the chance and the buttons
    local boxTop = top - Widgets.ROW_HEIGHT * FIGHT_ROWS - 4
    local box = CreateFrame("Frame", nil, panel)
    box:SetPoint("TOPLEFT", 2, boxTop); box:SetPoint("BOTTOMRIGHT", -2, 2)
    box:SetFrameLevel(panel:GetFrameLevel())
    addBorder(box, { 0.85, 0.65, 0.25, 0.85 }, 0.4)
    widgets.fightBox = box
    widgets.fightCards = {}
    for _, side in ipairs({ "left", "right" }) do
        local card = addon.TeamDialog.BuildCard(box, side, { width = 132, portrait = 44, onStep = function(self, step)
            local shown = ArenaView.state.cardShown or {}
            ArenaView.state.cardShown = shown
            shown[self.side] = addon.TeamDialog.FillCard(self, self.team, (shown[self.side] or 1) + step, self.note, self.playerName)
        end })
        card:SetPoint(side == "left" and "TOPLEFT" or "TOPRIGHT", side == "left" and 6 or -6, -5)
        widgets.fightCards[side] = card
    end
    widgets.fightVersus = Widgets.CreateFontString(box, "GameFontNormalLarge", "CENTER")
    widgets.fightVersus:SetPoint("TOP", 0, -24); widgets.fightVersus:SetText("|cffff5040VS|r")
    widgets.detail = Widgets.CreateFontString(box, "GameFontHighlightSmall", "LEFT")
    widgets.detail:SetPoint("TOPLEFT", 8, -118); widgets.detail:SetWidth(280)
    -- an incoming challenge: its own framed panel, the header "<Name> challenges you", then
    -- a tick (accept: opens the team picker) and a cross (decline) next to each other in the middle; the tooltips say it
    local answer
    answer, widgets.answerTitle = buildActionPanel(panel, boxTop - 146)
    widgets.acceptButton = Widgets.CreateIconButton(answer, "accept", 24, Text["Accept: pick your team and wager"], function() ArenaView.Decide(true) end)
    widgets.acceptButton:SetPoint("BOTTOMRIGHT", answer, "BOTTOM", -6, 4)
    widgets.declineButton = Widgets.CreateIconButton(answer, "decline", 24, Text["Decline"], function() ArenaView.Decide(false) end)
    widgets.declineButton:SetPoint("BOTTOMLEFT", answer, "BOTTOM", 6, 4)
    widgets.answerPanel = answer
    -- the bet on an open fight that is not mine: the same kind of panel, the header "Place your bet", then
    -- "[gold] (coin) [Red] [Blue]"
    local bet
    bet, widgets.betTitle = buildActionPanel(panel, boxTop - 146)
    widgets.betTitle:SetText(Text["Place your bet"])
    widgets.betBox = Widgets.CreateEditBox(bet, 40)
    widgets.betBox:SetPoint("BOTTOMLEFT", 8, 6)
    widgets.betBox:SetText("1")
    widgets.betLabel = Widgets.CreateFontString(bet, "GameFontHighlightSmall", "LEFT")
    widgets.betLabel:SetPoint("LEFT", widgets.betBox, "RIGHT", 3, 0); widgets.betLabel:SetText("|T" .. GOLD_ICON .. ":14:14|t")
    widgets.betA = Widgets.CreateButton(bet, "A", 100, 20, function() ArenaView.Bet("a") end)
    widgets.betA:SetPoint("BOTTOMLEFT", 70, 6)
    widgets.betB = Widgets.CreateButton(bet, "B", 100, 20, function() ArenaView.Bet("b") end)
    widgets.betB:SetPoint("LEFT", widgets.betA, "RIGHT", 6, 0)
    widgets.betPanel = bet
    if addon.IS_DEVELOPMENT_BUILD then ArenaView.BuildDevTools(panel) end
    -- a decided fight: the same kind of panel, the header "The fight is decided" (or who won once watched), and
    -- [Watch] in the middle
    local watch
    watch, widgets.watchTitle = buildActionPanel(panel, boxTop - 146)
    widgets.watchButton = Widgets.CreateButton(watch, Text["Watch"], 120, 20, function() ArenaView.Watch(ArenaView.state.selected) end)
    widgets.watchButton:SetPoint("BOTTOM", 0, 6)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.watchButton) end
    widgets.watchPanel = watch
end

local REFUSALS = { readonly = Text["Saved data is read-only."], unknown = Text["This fight is gone."], answered = Text["Already answered."],
    late = Text["Too late to answer."], nocompanion = Text["You have no companion."], funds = Text["Not enough gold in your pool."],
    closed = Text["Bets are closed for this fight."], own = Text["You cannot bet on your own fight."], twice = Text["You already bet on this fight."],
    stake = Text["Bet between {minimum} and {maximum}."], self = Text["You cannot challenge yourself."],
    nocompanionthere = Text["That player has no companion."], open = Text["You have too many open challenges."],
    wager = Text["A wager is {minimumWager} to {maximumWager}."], opponent = Text["Choose a guild member first."],
    busy = Text["One fight at a time: wait until your current fight is over."], theybusy = Text["They are in a fight right now."],
    team = Text["Pick exactly 3 different companions."],
    version = Text["Both players need the same GuildGames version."] }
---@param reason string
---@return string
function ArenaView.RefusalText(reason)
    local text = REFUSALS[reason] or tostring(reason)
    return Format(text, { minimum = money(addon.Arena.MINIMUM_BET), maximum = money(addon.Arena.MAXIMUM_BET),
        minimumWager = money(addon.Arena.MINIMUM_WAGER), maximumWager = money(addon.Arena.MAXIMUM_WAGER) })
end

-- After an action: a success publishes (the fight list and the box show the new state, no message); a refusal is
-- one red line in the fight box (ArenaView.state.refusal) until the next action or another selection.
local function showResult(ok, reason)
    if ok then
        ArenaView.state.refusal = nil
        addon.Catcher.PublishArena()
    else
        ArenaView.state.refusal = { id = ArenaView.state.selected, text = ArenaView.RefusalText(reason) }
        ArenaView.Refresh()
    end
end

---@param accept boolean
---@param id? string the fight (a row's button), else the selected one
function ArenaView.Answer(accept, id)
    id = id or ArenaView.state.selected
    ArenaView.state.selected = id
    if not accept then
        local ok, reason = addon.Arena.Answer(records(), me(), id, false, now())
        showResult(ok, reason)
        ArenaView.Refresh()
        return
    end
    local fight = addon.Arena.Fights(records(), me(), now())[id]
    if not fight then showResult(nil, "unknown") return end
    -- the same picker as a request: their team in the carousel, my three, my own wager (it starts at theirs)
    addon.TeamDialog.Open({
        opponent = short(fight.a), opponentTeam = fight.ta, fightID = id, mySide = "b", confirmText = Text["Accept"],
        wager = math.max(fight.wager, addon.Arena.MINIMUM_WAGER), hideBehind = widgets.fightsPage,
        onConfirm = function(uids, wager)
            local ok, reason = addon.Arena.Answer(records(), me(), id, true, now(), uids, wager)
            if ok then
                showResult(true)
                ArenaView.Refresh()
            end
            return ok, reason
        end })
end

-- The Accept / Decline icons: answer the selected incoming challenge.
---@param accept boolean
function ArenaView.Decide(accept) ArenaView.Answer(accept, ArenaView.state.selected) end

-- Stops my waiting challenge; the arena check runs at once, so the stake comes back right after.
---@param id? string
function ArenaView.Withdraw(id)
    id = id or ArenaView.state.selected
    ArenaView.state.selected = id
    local ok, reason = addon.Arena.Withdraw(records(), me(), id, now())
    showResult(ok, reason)
    if ok then addon.Catcher.ArenaTick(true) end
    ArenaView.Refresh()
end

function ArenaView.Bet(side)
    local id = ArenaView.state.selected
    local gold = tonumber(widgets.betBox:GetText() or "")
    local ok, reason = addon.Arena.Bet(records(), me(), id, side, gold and math.floor(gold * 10000) or 0, now())
    showResult(ok, reason)
    ArenaView.Refresh()
end

------------------------------------------------------------------ the fight request

local CANDIDATE_SHORT = { version = Text["other version"], fewcompanions = Text["under 3 companions"], theybusy = Text["in a fight"],
    offline = Text["offline"] }

---@param reason string
---@return string
function ArenaView.CandidateShort(reason) return CANDIDATE_SHORT[reason] or reason end

-- The tooltip line of a dropdown entry: who can be challenged, or why not.
---@param entry ArenaCandidate
---@return string
function ArenaView.CandidateText(entry)
    if entry.reason == "version" then return ArenaView.VersionText(entry.name) end
    if entry.reason == "fewcompanions" then
        return Format(Text["{name} has {n} companions: a team needs 3."], { name = short(entry.name), n = entry.companions or 0 })
    end
    if entry.reason == "theybusy" then return ArenaView.RefusalText("theybusy") end
    if entry.reason == "offline" then return Text["Offline right now."] end
    return Text["Click to pick them for a fight."]
end

-- The dropdown entries now (the guild roster says who is offline).
---@return ArenaCandidate[]
function ArenaView.Candidates()
    local function isOnline(name)
        local ok, online = pcall(addon.Api.IsOnline, name)
        if ok and online == false then return false end
        return nil
    end
    return addon.Arena.Candidates(records(), me(), now(), isOnline)
end

function ArenaView.ToggleMemberMenu()
    local menu = widgets.memberMenu
    if not menu then return end
    if menu:IsShown() then menu:Hide() return end
    local list = ArenaView.Candidates()
    widgets.memberList:SetData(list)
    widgets.noMembers:SetShown(#list == 0)
    menu:Show()
end

-- Picks `name` from the dropdown (a greyed one can't be picked: its tooltip says why).
---@param name string
---@return boolean picked
function ArenaView.PickMember(name)
    for _, entry in ipairs(ArenaView.Candidates()) do
        if entry.name == name then
            if entry.reason then return false end
            ArenaView.state.opponent = name
            if widgets.memberMenu then widgets.memberMenu:Hide() end
            ArenaView.Refresh()
            return true
        end
    end
    return false
end

-- "Fight!": the team picker for the picked member with my wager (the last one, at least MINIMUM_WAGER). Returns true
-- when it opened.
---@return boolean
function ArenaView.Request()
    local opponent = ArenaView.state.opponent
    if not opponent then showResult(nil, "opponent") return false end
    if widgets.memberMenu then widgets.memberMenu:Hide() end
    local wager = math.max(ArenaView.state.lastWager or 0, addon.Arena.MINIMUM_WAGER)
    return addon.TeamDialog.Open({
        opponent = short(opponent), mySide = "a", confirmText = Text["Send"], wager = wager, hideBehind = widgets.fightsPage,
        onConfirm = function(uids, copper)
            local id, reason = addon.Arena.Challenge(records(), me(), opponent, copper, now(), uids)
            if not id then return nil, reason end
            ArenaView.state.lastWager, ArenaView.state.selected, ArenaView.state.opponent = copper, id, nil
            addon.Catcher.PublishArena()
            if addon.AzeCaughtPanel.AdvanceGuide then addon.AzeCaughtPanel.AdvanceGuide("request") end
            -- the send: crossed swords clash over the Fights page; the new fight is selected in the list
            addon.Animate.Clash("fightRequest", widgets.fightsPage)
            ArenaView.Refresh()
            return true
        end })
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

-- A team in one line: the fighters' names in order, their buffs once.
---@param team Fighter[]|nil
---@return string
local function teamLine(team)
    if not team then return "|cff999999" .. Text["picks a team when answering"] .. "|r" end
    local names = {}
    for index, fighter in ipairs(team) do names[index] = addon.Utility.Escape(addon.Utility.ShortText(addon.AzeCaught.ShownName(fighter), 14)) end
    local buffs = ArenaView.BuffIcons(team[1] and team[1].bf)
    return table.concat(names, " · ") .. (buffs ~= "" and (" " .. buffs) or "")
end
ArenaView.TeamLine = teamLine

-- "Name runs 0.11.0, you run 0.11.1": why a fight with `name` is not possible.
---@param name string
---@return string
function ArenaView.VersionText(name)
    return Format(Text["{name} runs {theirs}, you run {mine}: both need the same version."],
        { name = short(name), theirs = addon.Arena.VersionOf(records(), name) or "?", mine = addon.VERSION })
end

-- dev build: one icon per fake event in a row just below the Fights page (each is the /ggd arena command of its word;
-- crowd and latebet act on the selected fight)
local DEV_TOOLS = {
    { word = "request", kind = "debug", tip = "[dev] The arena dummy challenges me" },
    { word = "accept", kind = "devaccept", tip = "[dev] The dummy accepts my waiting challenge now (its own wager)" },
    { word = "decline", kind = "devdecline", tip = "[dev] The dummy declines my waiting challenge" },
    { word = "skip", kind = "skip", tip = "[dev] Fight now: ends the waiting time of the dummy's accepted fights" },
    { word = "crowd", kind = "crowd", tip = "[dev] Fake guild members bet on both sides of the selected open fight" },
    { word = "latebet", kind = "latebet", tip = "[dev] A fake bet after the selected fight's fight time (stays out of the pot)" },
    { word = "members", kind = "members", tip = "[dev] Fake members for the dropdown: other version, 2 companions, in a fight, offline" },
    { word = "expire", kind = "expire", tip = "[dev] Waiting challenges with fake members expire (stakes come back)" },
    { word = "reveal", kind = "reveal", tip = "[dev] Unwatched fake fights settle as if an hour passed" },
    { word = "clear", kind = "clear", tip = "[dev] Remove all fake members, bettors, time shifts and the dummy" },
}

---@param panel table the Fights page
function ArenaView.BuildDevTools(panel)
    local Widgets = addon.UI.Widgets
    widgets.devTools = {}
    for index, tool in ipairs(DEV_TOOLS) do
        local word = tool.word
        local button = Widgets.CreateIconButton(panel, tool.kind, 22, tool.tip, function()
            if word == "request" then addon.Catcher.DevArenaRequest(1) else addon.Catcher.DevArena(word) end
        end)
        button:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 6 + (index - 1) * 29, -4)   -- below the window: the fight box fills the page
        widgets.devTools[word] = button
    end
    widgets.dummyButton, widgets.skipButton = widgets.devTools.request, widgets.devTools.skip
end

function ArenaView.RefreshFights()
    ArenaView.state.busy = addon.Arena.Busy(addon.Arena.Fights(records(), me(), now()), me(), true) ~= nil
    -- the request: the picked member stays while they can still be challenged
    if ArenaView.state.opponent then
        local still = false
        for _, entry in ipairs(ArenaView.Candidates()) do
            if entry.name == ArenaView.state.opponent and not entry.reason then still = true end
        end
        if not still then ArenaView.state.opponent = nil end
    end
    widgets.memberDropdown:SetLabel(ArenaView.state.opponent and Format(Text["vs {name}"], { name = short(ArenaView.state.opponent) })
        or Text["Choose a guild member"])
    widgets.requestButton:SetEnabled(ArenaView.state.opponent ~= nil and not ArenaView.state.busy)
    if widgets.memberMenu:IsShown() then widgets.memberList:SetData(ArenaView.Candidates()) end
    local rows = ArenaView.FightRows()
    widgets.fightList:SetData(rows)
    widgets.noFights:SetShown(#rows == 0)
    local selected
    for _, row in ipairs(rows) do if row.id == ArenaView.state.selected then selected = row end end
    if not selected and rows[1] then selected = rows[1]; ArenaView.state.selected = rows[1].id end
    for _, region in ipairs({ widgets.betPanel, widgets.watchPanel, widgets.answerPanel }) do
        region:Hide()
    end
    local cards = widgets.fightCards
    if not selected then
        widgets.detail:SetText("")
        cards.left:Hide(); cards.right:Hide(); widgets.fightVersus:SetText("")
        return
    end
    local fight, myName = selected.fight, me()
    -- both teams as carousels (a new selection starts at the first fighter; the arrows keep their place on a refresh)
    cards.left:Show(); cards.right:Show(); widgets.fightVersus:SetText("|cffff5040VS|r")
    if ArenaView.state.cardFight ~= selected.id then ArenaView.state.cardFight, ArenaView.state.cardShown = selected.id, {} end
    local cardShown = ArenaView.state.cardShown
    local TeamDialog = addon.TeamDialog
    cardShown.left = TeamDialog.FillCard(cards.left, fight.ta, cardShown.left, Text["picks a team when answering"], short(fight.a))
    cardShown.right = TeamDialog.FillCard(cards.right, fight.tb or (fight.counter and fight.counter.t), cardShown.right,
        Text["picks a team when answering"], short(fight.b))
    local lines = {}
    if fight.state == "version" then
        lines[#lines + 1] = "|cffff9933" .. ArenaView.VersionText(fight.a == me() and fight.b or fight.a) .. "|r"
    end
    -- the gold of each side as a badge on its name plate: before the accept the challenger's wager, then the pot of
    -- each side (the fighter's wager plus every bet on them); a tick on the side my bet is on
    local myBet = addon.Arena.State().bt[selected.id]
    if fight.tb then
        local pot = addon.Arena.Pot(fight)
        for _, side in ipairs({ "a", "b" }) do
            local name = side == "a" and fight.a or fight.b
            local tip = { Format(Text["Pot of {name}: {gold}"], { name = short(name), gold = money(pot[side]) }),
                Text["The fighter's wager plus every bet on them. The winning side gets its stakes back and shares the losing side's pot."] }
            local mine = myBet ~= nil and myBet.s == side
            if mine then tip[#tip + 1] = "|cff66ff66" .. Format(Text["Your bet: {gold}"], { gold = money(myBet.c) }) .. "|r" end
            TeamDialog.SetCardGold(side == "a" and cards.left or cards.right, pot[side], tip, mine)
        end
    else
        TeamDialog.SetCardGold(cards.left, fight.wager, { Format(Text["Wager of {name}: {gold}"], { name = short(fight.a), gold = money(fight.wager) }) })
        TeamDialog.SetCardGold(cards.right, nil)
    end
    -- accepting while my own fight runs or waits is refused: the button is greyed out and the line says why
    local blocked = selected.state == "incoming" and ArenaView.state.busy
    if blocked then lines[#lines + 1] = "|cff999999" .. ArenaView.RefusalText("busy") .. "|r" end
    local refusal = ArenaView.state.refusal
    if refusal and refusal.id == selected.id then lines[#lines + 1] = "|cffff6060" .. refusal.text .. "|r" end
    widgets.detail:SetText(table.concat(lines, "\n"))
    if selected.state == "incoming" then
        widgets.answerTitle:SetText(Format(Text["{name} challenges you"], { name = sideName(fight.a, "a") }))
        widgets.acceptButton:SetLabel(blocked and ArenaView.RefusalText("busy") or Text["Accept: pick your team and wager"])
        widgets.acceptButton:SetEnabled(not blocked)
        widgets.answerPanel:Show()
    elseif selected.state == "open" and fight.a ~= myName and fight.b ~= myName and not myBet then
        widgets.betA:SetLabel(sideName(fight.a, "a")); widgets.betB:SetLabel(sideName(fight.b, "b"))
        widgets.betPanel:Show()
    elseif selected.state == "done" then
        local result = addon.Arena.Revealed(fight, now()) and addon.Arena.Result(fight)
        widgets.watchTitle:SetText(result and Format(Text["{name} won"], { name = sideName(result.winner == "a" and fight.a or fight.b, result.winner) })
            or Text["The fight is decided"])
        widgets.watchPanel:Show()
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
        -- hover over the name: the species behind a nickname
        part.nameHover = CreateFrame("Frame", nil, replay)
        part.nameHover:SetAllPoints(part.name); part.nameHover:EnableMouse(true)
        part.nameHover:SetScript("OnEnter", function(self)
            if not self.fighter or not GameTooltip then return end
            GameTooltip:SetOwner(self, side == "a" and "ANCHOR_BOTTOMRIGHT" or "ANCHOR_BOTTOMLEFT")
            addon.TeamDialog.AddFighterName(GameTooltip, self.fighter)
            GameTooltip:Show()
        end)
        part.nameHover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        part.bar = createBar(replay, 140, 10, side == "a" and { 0.3, 0.85, 0.35 } or { 0.9, 0.35, 0.3 })
        part.bar:SetPoint(side == "a" and "TOPLEFT" or "TOPRIGHT", side == "a" and 8 or -8, -30)
        part.health = Widgets.CreateFontString(replay, "GameFontHighlightSmall", "CENTER"); part.health:SetPoint("CENTER", part.bar, "CENTER", 0, 0)
        -- the owner at the bottom of its side, above the floor line (not behind the pet's name)
        part.owner = Widgets.CreateFontString(replay, "GameFontHighlightSmall", side == "a" and "LEFT" or "RIGHT")
        part.owner:SetPoint(side == "a" and "BOTTOMLEFT" or "BOTTOMRIGHT", side == "a" and 8 or -8, 76); part.owner:SetWidth(140)
        part.float = Widgets.CreateFontString(replay, "GameFontNormalLarge", "CENTER"); part.float:Hide()
        -- the team strip: one square per fighter (gold: fighting, green: waiting, dark: beaten)
        part.dots = {}
        for index = 1, addon.Arena.TEAM_SIZE do
            local dot = replay:CreateTexture(nil, "ARTWORK")
            dot:SetSize(12, 12)
            dot:SetPoint(side == "a" and "TOPLEFT" or "TOPRIGHT", part.bar, side == "a" and "BOTTOMLEFT" or "BOTTOMRIGHT",
                (side == "a" and 1 or -1) * (index - 1) * 16, -4)
            part.dots[index] = dot
        end
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
    local team = event.s == "a" and fight.ta or fight.tb
    local fighter = team and team[(event.s == "a" and event.ia or event.ib) or 1] or (event.s == "a" and fight.fa or fight.fb)
    local actor = addon.Utility.Escape(addon.AzeCaught.ShownName(fighter))
    if event.k == "enter" then return "|cffffd100" .. Format(Text["{name} enters the fight!"], { name = actor }) .. "|r" end
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

local function setHealth(fight, result, healthA, healthB, maxA, maxB)
    maxA, maxB = maxA or result.maxA, maxB or result.maxB
    widgets.replayLeft.bar:SetValue(healthA / maxA); widgets.replayLeft.health:SetText(healthA .. "/" .. maxA)
    widgets.replayRight.bar:SetValue(healthB / maxB); widgets.replayRight.health:SetText(healthB .. "/" .. maxB)
end

-- Puts team slot `slot` of `side` into the ring: its name and model, the team strip.
---@param fight ArenaFight
---@param side "a"|"b"
---@param slot integer
local function showFighter(fight, side, slot)
    local part = sideWidgets(side)
    local team = (side == "a" and fight.ta or fight.tb) or { side == "a" and fight.fa or fight.fb }
    local fighter = team[slot] or team[1]
    part.slot = slot
    addon.UI.Widgets.FitText(part.name, addon.Utility.Escape(addon.AzeCaught.ShownName(fighter)), 0.7)
    part.nameHover.fighter = fighter
    addon.AzeCaughtPanel.ShowModel(part.model, { npc = fighter.npc, disp = fighter.disp }, "replay")
    if part.model.SetFacing then pcall(part.model.SetFacing, part.model, side == "a" and 0.9 or -0.9) end
    ArenaView.ResetModel(part.model)
    ArenaView.PlayAnimation(part.model, "ready")
    for index, dot in ipairs(part.dots) do
        dot:SetShown(index <= #team)
        if index < slot then dot:SetColorTexture(0.25, 0.22, 0.25, 1)
        elseif index == slot then dot:SetColorTexture(1, 0.82, 0.2, 1)
        else dot:SetColorTexture(0.3, 0.8, 0.35, 1) end
    end
end
ArenaView.ShowFighter = showFighter

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
    for _, side in ipairs({ "a", "b" }) do
        sideWidgets(side).owner:SetText("|cff999999" .. short(side == "a" and fight.a or fight.b) .. "|r")
        showFighter(fight, side, 1)
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
    if event.k == "enter" then showFighter(replay.fight, event.s, event.s == "a" and event.ia or event.ib) end
    setHealth(replay.fight, replay.result, event.ha, event.hb, event.ma, event.mb)
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
    if last then
        for _, side in ipairs({ "a", "b" }) do
            local slot = side == "a" and last.ia or last.ib
            if slot and sideWidgets(side).slot ~= slot then showFighter(replay.fight, side, slot) end
        end
        setHealth(replay.fight, replay.result, last.ha, last.hb, last.ma, last.mb)
    end
    replay.step = #replay.result.events
    local winnerSide = replay.result.winner
    local winner = { n = short(winnerSide == "a" and replay.fight.a or replay.fight.b) }
    if last and replay.result.reason ~= "time" then   -- skipped to the end: the knocked-out side dies too (once)
        local loserSide = winnerSide == "a" and "b" or "a"
        if (loserSide == "a" and last.ha or last.hb) <= 0 then ArenaView.PlayDeath(sideWidgets(loserSide).model) end
    end
    widgets.replayLine:SetText("|cffffd100" .. Format(Text["{name}'s team wins!"], { name = addon.Utility.ShortText(winner.n, 24) }) .. "|r"
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

-- Builds the view into `panel` (the AZEcaught panel's arena frame, 300 x 376).
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
    addon.TeamDialog.Build(panel)
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
