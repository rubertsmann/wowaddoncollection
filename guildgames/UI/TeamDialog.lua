local addonName, addon = ...

-- The team picker of an arena fight, for a request and for an accept: a modal over the arena view. The opponent's team
-- (when known: accepting) is shown at the top as a carousel, one fighter at a time (round portrait with its model, its
-- level, ability, stats and buffs; the arrows go through the three in fighting order), my three slots below it, then my
-- whole roster to pick from (a click puts a companion into the next free slot, a click on a slot empties it), and my
-- wager in gold next to Confirm. With both teams known it shows my win chance for the current pick. Confirm hands the
-- uids in fighting order and the wager in copper to the caller's action.
local TeamDialog = {}
addon.TeamDialog = TeamDialog

local Text, Format = addon.Text, addon.Locale.Format
local widgets = {}
TeamDialog.widgets = widgets

---@class TeamDialogRequest
---@field opponent? string the opponent's name (escaped short form)
---@field opponentTeam? Fighter[] their team when it is known
---@field fightID? string the fight's id (the win chance uses its seed)
---@field mySide? "a"|"b" which side of the fight my team is on (default "b")
---@field confirmText? string
---@field wager? integer copper the wager box starts with; nil: no wager box
---@field onConfirm fun(uids: string[], wager: integer|nil): boolean|nil, string|nil the action; a refusal reason keeps the dialog open
---@field hideBehind? table a page hidden while the dialog is open (shown again on close)

---@class TeamDialogState
---@field request TeamDialogRequest|nil
---@field picks string[] the uids in the slots (fighting order)
TeamDialog.state = { request = nil, picks = {}, shown = 1 }

local TEXTURES = "Interface\\AddOns\\" .. addonName .. "\\UI\\Textures\\"
local DISC_TEXTURE, RING_TEXTURE = TEXTURES .. "Disc", TEXTURES .. "RingThin"


---@param list table
---@return table row
local function createRosterRow(list)
    local Widgets = addon.UI.Widgets
    local row = CreateFrame("Button", nil, list)
    row.hover = row:CreateTexture(nil, "BACKGROUND"); row.hover:SetAllPoints(); row.hover:SetColorTexture(1, 1, 1, 0.07); row.hover:Hide()
    row.picked = row:CreateTexture(nil, "BACKGROUND", nil, 1); row.picked:SetAllPoints(); row.picked:SetColorTexture(1, 0.8, 0.2, 0.18); row.picked:Hide()
    row.slot = Widgets.CreateFontString(row, "GameFontNormal", "CENTER"); row.slot:SetPoint("LEFT", 2, 0); row.slot:SetWidth(14)
    row.name = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT"); row.name:SetPoint("LEFT", 18, 0); row.name:SetWidth(120)
    row.info = Widgets.CreateFontString(row, "GameFontHighlightSmall", "RIGHT"); row.info:SetPoint("RIGHT", -2, 0); row.info:SetWidth(130)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        local companion = self.entry and addon.AzeCaught.Companion(self.entry.uid)
        if companion and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            addon.AzeCaughtPanel.ShowCompanionTooltip(GameTooltip, companion)
        end
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide(); if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self) if self.entry then TeamDialog.Toggle(self.entry.uid) end end)
    return row
end

---@param row table
---@param entry table { uid, fighter }
local function fillRosterRow(row, entry)
    local slot
    for index, uid in ipairs(TeamDialog.state.picks) do if uid == entry.uid then slot = index end end
    row.picked:SetShown(slot ~= nil)
    row.slot:SetText(slot and ("|cffffd100" .. slot .. "|r") or "")
    local fighter = entry.fighter
    addon.UI.Widgets.FitText(row.name, addon.Utility.Escape(addon.AzeCaught.ShownName(fighter)) .. (entry.active and " |cff66ff66*|r" or ""), 0.8)
    row.info:SetText(("|cff999999%s%d %s|r %d/%d/%d/%d"):format(Text["Lv"], fighter.al, addon.ArenaView.ABILITY_NAME[fighter.ab] or "",
        fighter.atk, fighter.def, fighter.spd, fighter.vit))
end

-- The tooltip title of a fighter (mine or a peer's): the nickname when it has one, then its species from the NPC id.
---@param tooltip table
---@param fighter Fighter
function TeamDialog.AddFighterName(tooltip, fighter)
    local AzeCaught, Escape = addon.AzeCaught, addon.Utility.Escape
    tooltip:SetText(Escape(AzeCaught.ShownName(fighter)), 1, 0.82, 0)
    if AzeCaught.HasNickname(fighter) then tooltip:AddLine(Escape(AzeCaught.SpeciesName(fighter)), 0.85, 0.85, 0.85) end
end

local CARD_PORTRAIT = 58
local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local BET_MARK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CARD_TEXT_HEIGHT = 2 + 3 + 14 + 1 + 24 + 3 + 18   -- under the portrait: name, level line (two lines), name plate

---@class TeamCardOptions
---@field width? number default 140
---@field portrait? number default 58
---@field height? number default: the portrait plus room for the name, the level line and the name plate
---@field onStep? fun(card: table, step: integer) the arrows and the mouse wheel (default: the card's own team)

-- One team's carousel: a round portrait with its model, < > through the three in fighting order (also the mouse
-- wheel), "2/3", the fighter's name and level line, and the player's name on a plate below. Hover: the full stats.
-- Used by the team picker and by the Fights page (the selected fight). The caller anchors it.
---@param parent table
---@param side "left"|"right" left: the challenger (red), right: the challenged player (blue)
---@param options? TeamCardOptions
---@return table card
function TeamDialog.BuildCard(parent, side, options)
    options = options or {}
    local Widgets = addon.UI.Widgets
    local width, size = options.width or 140, options.portrait or 58
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, options.height or (size + CARD_TEXT_HEIGHT))
    card.side = side
    card:Show()
    local function step(delta)
        if options.onStep then options.onStep(card, delta) else TeamDialog.FillCard(card, card.team, (card.shown or 1) + delta, card.note, card.playerName) end
    end
    card:EnableMouse(true); card:EnableMouseWheel(true)
    card:SetScript("OnMouseWheel", function(_, delta) step(delta > 0 and -1 or 1) end)
    card:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.fighter then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        TeamDialog.AddFighterName(GameTooltip, self.fighter)
        -- the TLevel when the team was sent (older teams have none)
        if self.fighter.tl then GameTooltip:AddLine(Text["TLevel"] .. " " .. self.fighter.tl, 1, 0.82, 0.2) end
        GameTooltip:AddLine(TeamDialog.CardText(self.fighter), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local portrait = CreateFrame("Frame", nil, card)
    portrait:SetSize(size, size); portrait:SetPoint("TOP", 0, -2)
    addon.PetView.Shape(portrait, DISC_TEXTURE, size, { 0.04, 0.04, 0.06, 0.9 }, "BACKGROUND")
    card.ring = addon.PetView.Shape(portrait, RING_TEXTURE, size + 4, { 0.95, 0.78, 0.3, 0.95 }, "BORDER")
    card.view = addon.ModelView.New(portrait, { preset = "portrait", width = size - 6, height = size - 6, area = "team" })
    card.model = card.view.frame
    card.model:SetPoint("CENTER", 0, -2)
    card.previous = Widgets.CreateButton(card, "<", 12, 16, function() step(-1) end)
    card.previous:SetPoint("RIGHT", portrait, "LEFT", -6, 0)
    card.next = Widgets.CreateButton(card, ">", 12, 16, function() step(1) end)
    card.next:SetPoint("LEFT", portrait, "RIGHT", 6, 0)
    card.index = Widgets.CreateFontString(card, "GameFontDisableSmall", side == "left" and "LEFT" or "RIGHT")
    card.index:SetPoint(side == "left" and "TOPLEFT" or "TOPRIGHT", 0, -2); card.index:SetWidth(30)
    card.fighterName = Widgets.CreateFontString(card, "GameFontNormal", "CENTER")
    card.fighterName:SetPoint("TOP", portrait, "BOTTOM", 0, -3); card.fighterName:SetWidth(width); card.fighterName:SetHeight(14)
    card.fighterInfo = Widgets.CreateFontString(card, "GameFontHighlightSmall", "CENTER")
    card.fighterInfo:SetPoint("TOP", card.fighterName, "BOTTOM", 0, -1); card.fighterInfo:SetWidth(width)
    card.fighterInfo:SetHeight(24); card.fighterInfo:SetJustifyV("TOP")
    -- the player's name on a plate in the side's colour, its own frame above the rest
    local plate = CreateFrame("Frame", nil, card)
    plate:SetPoint("TOPLEFT", card.fighterInfo, "BOTTOMLEFT", 0, -3); plate:SetPoint("TOPRIGHT", card.fighterInfo, "BOTTOMRIGHT", 0, -3)
    plate:SetHeight(18)   -- under the level line (never over it)
    plate:SetFrameLevel(card:GetFrameLevel() + 5)
    card.plateColor = plate:CreateTexture(nil, "BACKGROUND"); card.plateColor:SetAllPoints()
    card.player = Widgets.CreateFontString(plate, "GameFontNormal", "CENTER")
    card.player:SetPoint("CENTER", 0, 0); card.player:SetWidth(width - 8)
    card.plate = plate
    -- the gold on this side (Fights page only): a coin and the amount on top of the plate, at its end toward the
    -- middle; a tick when my bet is on this side; hover says what it is (TeamDialog.SetCardGold)
    local gold = CreateFrame("Frame", nil, card)
    gold:SetSize(78, 16)
    gold:SetPoint(side == "left" and "BOTTOMRIGHT" or "BOTTOMLEFT", plate, side == "left" and "TOPRIGHT" or "TOPLEFT", 0, -5)
    gold:SetFrameLevel(plate:GetFrameLevel() + 3)
    gold:EnableMouse(true)
    gold.icon = gold:CreateTexture(nil, "ARTWORK"); gold.icon:SetSize(14, 14)
    gold.icon:SetPoint(side == "left" and "RIGHT" or "LEFT", side == "left" and -2 or 2, 0)
    addon.UIHelpers.SetTextureOr(gold.icon, GOLD_ICON, { 1, 0.82, 0.2 })
    gold.text = Widgets.CreateFontString(gold, "GameFontNormalSmall", side == "left" and "RIGHT" or "LEFT")
    gold.text:SetPoint(side == "left" and "RIGHT" or "LEFT", gold.icon, side == "left" and "LEFT" or "RIGHT", side == "left" and -2 or 2, 0)
    gold.text:SetWidth(46)
    gold.mark = gold:CreateTexture(nil, "OVERLAY"); gold.mark:SetSize(12, 12)
    gold.mark:SetPoint(side == "left" and "LEFT" or "RIGHT", side == "left" and 2 or -2, 0)
    addon.UIHelpers.SetTextureOr(gold.mark, BET_MARK, { 0.3, 0.9, 0.3 })
    gold:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for index, line in ipairs(self.tip) do
            if index == 1 then GameTooltip:SetText(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end)
    gold:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    gold:Hide()
    card.gold = gold
    return card
end

-- `copper` as a plain gold number for the badge (the coin next to it is the unit): "12", "2.5", "0.15".
---@param copper integer
---@return string
function TeamDialog.GoldNumber(copper)
    local text = ("%.2f"):format(math.floor(copper / 100) / 100)
    return (text:gsub("%.?0+$", ""))
end

-- The gold badge of a card:`amount` copper with the hover lines `tip` (the first is the title), a tick when `mine`
-- (my bet is on this side); nil hides it.
---@param card table
---@param amount integer|nil
---@param tip? string[]
---@param mine? boolean
function TeamDialog.SetCardGold(card, amount, tip, mine)
    local gold = card.gold
    if not amount then gold:Hide() return end
    gold.text:SetText(TeamDialog.GoldNumber(amount))
    gold.mark:SetAlpha(mine and 1 or 0)
    gold.tip = tip
    gold:Show()
end
local buildCard = TeamDialog.BuildCard

-- The side colours, like two corners of a ring: the challenger red (left), the challenged player blue (right); on the
-- plate, the name and the portrait ring. The Fights page uses the same two (ArenaView.SideName).
local SIDE_COLOR = { left = { 0.85, 0.18, 0.15 }, right = { 0.2, 0.45, 0.95 } }
TeamDialog.SIDE_COLOR = SIDE_COLOR

-- Shows fighter `shown` of `team` (wraps; nil or empty: the note) on a card under `player`. Returns the slot shown.
---@param card table
---@param team Fighter[]|nil
---@param shown integer|nil
---@param note string shown instead of a fighter
---@param player string the player's name (escaped)
---@return integer|nil
function TeamDialog.FillCard(card, team, shown, note, player)
    card.team, card.note, card.playerName = team, note, player
    local color = SIDE_COLOR[card.side]
    card.plateColor:SetColorTexture(color[1] * 0.55, color[2] * 0.55, color[3] * 0.55, 0.95)
    card.ring:SetVertexColor(color[1], color[2], color[3], 1)
    card.player:SetText(("|cff%02x%02x%02x%s|r"):format(math.floor(math.min(1, color[1] + 0.35) * 255),
        math.floor(math.min(1, color[2] + 0.35) * 255), math.floor(math.min(1, color[3] + 0.35) * 255), player))
    local count = team and #team or 0
    card.previous:SetShown(count > 1); card.next:SetShown(count > 1)
    if count == 0 then
        card.fighter, card.shown = nil, nil
        card.index:SetText(""); card.fighterName:SetText(""); card.fighterInfo:SetText("|cff999999" .. note .. "|r")
        if card.shownFighter ~= false then
            card.shownFighter = false
            card.view.Show(nil)
        end
        return nil
    end
    shown = ((type(shown) == "number" and shown or 1) - 1) % count + 1
    local fighter = team[shown]
    card.fighter, card.shown = fighter, shown
    card.index:SetText(shown .. "/" .. count)
    addon.UI.Widgets.FitText(card.fighterName, "|cffffd100" .. shown .. ".|r " .. addon.Utility.Escape(addon.AzeCaught.ShownName(fighter)), 0.7)
    local buffs = addon.ArenaView.BuffIcons(fighter.bf)
    card.fighterInfo:SetText(("|cff999999%s %d · %s|r"):format(Text["Lv"], fighter.al or 1, addon.ArenaView.ABILITY_NAME[fighter.ab] or fighter.ab)
        .. (buffs ~= "" and (" " .. buffs) or ""))
    if card.shownFighter ~= fighter then
        card.shownFighter = fighter
        card.view.Show({ npc = fighter.npc, disp = fighter.disp })
        card.view.Face(card.side == "left" and 0.6 or -0.6)   -- the two face each other
    end
    return shown
end

-- Builds the dialog into `parent` (the arena view's frame).
---@param parent table
function TeamDialog.Build(parent)
    local Widgets = addon.UI.Widgets
    local dialog = CreateFrame("Frame", nil, parent)
    dialog:SetAllPoints(); dialog:SetFrameLevel(parent:GetFrameLevel() + 60); dialog:EnableMouse(true); dialog:Hide()
    local back = dialog:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(0.05, 0.04, 0.07, 0.98)
    local line = dialog:CreateTexture(nil, "ARTWORK"); line:SetHeight(2); line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
    line:SetColorTexture(0.9, 0.3, 0.25, 0.9)
    -- the two teams as carousels side by side: the challenger left, VS, the challenged player right, each with its
    -- player's name below (their team is unknown while I request: a note in its card)
    local function onStep(card, step) TeamDialog.Step(card.owner, step) end
    widgets.cards = { left = buildCard(dialog, "left", { onStep = onStep }), right = buildCard(dialog, "right", { onStep = onStep }) }
    widgets.cards.left:SetPoint("TOPLEFT", 6, -8)
    widgets.cards.right:SetPoint("TOPRIGHT", -6, -8)
    widgets.card = widgets.cards.right
    widgets.versus = Widgets.CreateFontString(dialog, "GameFontNormalLarge", "CENTER")
    widgets.versus:SetPoint("TOP", 0, -8 - CARD_PORTRAIT / 2 - 4); widgets.versus:SetText("|cffff5040VS|r")
    -- my roster: a click picks a companion into the next place of my team or takes it out (the number is its place)
    widgets.list = Widgets.CreateScrollList(dialog, 292, Widgets.ROW_HEIGHT * 9, createRosterRow, fillRosterRow)
    widgets.list:SetPoint("TOPLEFT", 4, -136)
    widgets.chance = Widgets.CreateFontString(dialog, "GameFontHighlightSmall", "CENTER")
    widgets.chance:SetPoint("BOTTOM", 0, 48); widgets.chance:SetWidth(290)
    widgets.error = Widgets.CreateFontString(dialog, "GameFontHighlightSmall", "CENTER")
    widgets.error:SetPoint("BOTTOM", 0, 34); widgets.error:SetWidth(290)
    -- my wager in gold (sending and accepting a fight) on the left; confirm (tick) and cancel (cross) on the right
    local wager = CreateFrame("Frame", nil, dialog)
    wager:SetPoint("BOTTOMLEFT", 8, 8); wager:SetSize(76, 24)
    widgets.wagerBox = Widgets.CreateEditBox(wager, 46)
    widgets.wagerBox:SetPoint("LEFT", 0, 0)
    widgets.wagerLabel = Widgets.CreateFontString(wager, "GameFontHighlightSmall", "LEFT")
    widgets.wagerLabel:SetPoint("LEFT", widgets.wagerBox, "RIGHT", 3, 0); widgets.wagerLabel:SetText(Text["gold"])
    widgets.wager = wager
    widgets.cancel = Widgets.CreateIconButton(dialog, "decline", 24, Text["Cancel"], function() TeamDialog.Close() end)
    widgets.cancel:SetPoint("BOTTOMRIGHT", -8, 8)
    widgets.confirm = Widgets.CreateIconButton(dialog, "accept", 24, Text["Confirm"], function() TeamDialog.Confirm() end)
    widgets.confirm:SetPoint("RIGHT", widgets.cancel, "LEFT", -8, 0)
    widgets.dialog = dialog
    parent:HookScript("OnHide", function() TeamDialog.Close() end)
end

-- My roster as dialog rows (each with its fighter now).
---@return table[]
function TeamDialog.Rows()
    local rows, active = {}, addon.AzeCaught.Active()
    for _, companion in ipairs(addon.AzeCaught.Roster()) do
        local fighter = addon.Arena.Fighter(companion)
        if fighter then rows[#rows + 1] = { uid = companion.uid, fighter = fighter, active = companion == active } end
    end
    return rows
end

-- The first TEAM_SIZE companions of the roster (the active one first): the pick the dialog starts with.
---@return string[]
function TeamDialog.DefaultPicks()
    local picks = {}
    for _, row in ipairs(TeamDialog.Rows()) do
        if #picks < addon.Arena.TEAM_SIZE then picks[#picks + 1] = row.uid end
    end
    return picks
end

-- Opens the dialog. Returns true when it opened (it needs the built frame).
---@param request TeamDialogRequest
---@param picks? string[] the start pick (default: TeamDialog.DefaultPicks)
---@return boolean
function TeamDialog.Open(request, picks)
    if not widgets.dialog then return false end
    TeamDialog.state.request = request
    TeamDialog.state.picks = picks or TeamDialog.DefaultPicks()
    TeamDialog.state.shown, TeamDialog.state.shownMine = 1, 1
    if request.hideBehind then request.hideBehind:Hide() end
    widgets.dialog:Show()
    widgets.error:SetText("")
    widgets.wager:SetShown(request.wager ~= nil)
    if request.wager then widgets.wagerBox:SetText(tostring(math.floor(request.wager / 10000))) end
    TeamDialog.Refresh()
    return true
end

function TeamDialog.Close()
    if widgets.dialog then widgets.dialog:Hide() end
    local request = TeamDialog.state.request
    TeamDialog.state.request = nil
    if request and request.hideBehind then request.hideBehind:Show() end
end

---@return boolean
function TeamDialog.IsOpen() return widgets.dialog ~= nil and widgets.dialog:IsShown() and TeamDialog.state.request ~= nil end

-- A click on a roster row: in the team, it leaves; otherwise it takes the next free slot.
---@param uid string
function TeamDialog.Toggle(uid)
    local picks = TeamDialog.state.picks
    for index, picked in ipairs(picks) do
        if picked == uid then table.remove(picks, index) TeamDialog.Refresh() return end
    end
    if #picks < addon.Arena.TEAM_SIZE then picks[#picks + 1] = uid; TeamDialog.state.shownMine = #picks end   -- the new pick shows in my carousel
    TeamDialog.Refresh()
end

---@param slot integer
function TeamDialog.ClearSlot(slot)
    table.remove(TeamDialog.state.picks, slot)
    TeamDialog.Refresh()
end

-- The card's fighter text: arena level, ability, the four stats with their names and the buffs.
---@param fighter Fighter
---@return string
function TeamDialog.CardText(fighter)
    local ability = addon.ArenaView.ABILITY_NAME[fighter.ab] or fighter.ab
    local buffs = addon.ArenaView.BuffIcons(fighter.bf)
    return ("|cff999999%s %d · %s|r\n%s |cffff8060%d|r  %s |cff80b0ff%d|r\n%s |cff80ff80%d|r  %s |cffffd060%d|r%s"):format(
        Text["Lv"], fighter.al or 1, ability, Text["Attack"], fighter.atk, Text["Defense"], fighter.def,
        Text["Speed"], fighter.spd, Text["Vitality"], fighter.vit, buffs ~= "" and ("\n" .. buffs) or "")
end

-- The cards of their team and mine (the challenger's is on the left).
---@return table theirs
---@return table mine
local function cardsBySide()
    local request = TeamDialog.state.request
    local mineLeft = request and request.mySide == "a"
    return mineLeft and widgets.cards.right or widgets.cards.left, mineLeft and widgets.cards.left or widgets.cards.right
end

-- My picks as fighters, in fighting order.
---@return Fighter[]
function TeamDialog.MyTeam()
    local team = {}
    for _, uid in ipairs(TeamDialog.state.picks) do
        local fighter = addon.Arena.Fighter(addon.AzeCaught.Companion(uid))
        if fighter then team[#team + 1] = fighter end
    end
    return team
end

-- Moves the carousel of their team by `step` (wraps around; 0 redraws) and shows that fighter. Returns its slot, nil
-- while their team is unknown.
---@param step integer
---@return integer|nil
function TeamDialog.ShowTheirs(step)
    local request = TeamDialog.state.request
    local team = request and request.opponentTeam
    local count = team and #team or 0
    local shown = count > 0 and ((TeamDialog.state.shown or 1) - 1 + (step or 0)) % count + 1 or nil
    TeamDialog.state.shown = shown or 1
    if not widgets.cards or not request then return shown end
    local theirs = cardsBySide()
    theirs.owner = "theirs"
    widgets.card = theirs
    TeamDialog.FillCard(theirs, team, shown, Text["They see your team in full and pick theirs to counter it."], request.opponent or "?")
    return shown
end

-- Moves the carousel of my picks by `step` (wraps; 0 redraws). Returns the slot shown, nil without a pick.
---@param step integer
---@return integer|nil
function TeamDialog.ShowMine(step)
    local team = TeamDialog.MyTeam()
    local count = #team
    local shown = count > 0 and ((TeamDialog.state.shownMine or 1) - 1 + (step or 0)) % count + 1 or nil
    TeamDialog.state.shownMine = shown or 1
    if not widgets.cards or not TeamDialog.state.request then return shown end
    local _, mine = cardsBySide()
    mine.owner = "mine"
    local myName = addon.Utility.Me() or "?"
    TeamDialog.FillCard(mine, team, shown, Text["Pick exactly 3 different companions."], addon.Utility.Escape(myName:match("^([^%-]+)") or myName))
    return shown
end

-- The arrows and the mouse wheel of a card.
---@param owner "theirs"|"mine"
---@param step integer
function TeamDialog.Step(owner, step)
    if owner == "mine" then TeamDialog.ShowMine(step) else TeamDialog.ShowTheirs(step) end
end

function TeamDialog.Refresh()
    local request = TeamDialog.state.request
    if not request or not widgets.dialog then return end
    local Arena = addon.Arena
    TeamDialog.ShowTheirs(0)
    TeamDialog.ShowMine(0)
    local picks = TeamDialog.state.picks
    local rows = TeamDialog.Rows()
    widgets.list:SetData(rows)
    local missing = Arena.MissingForTeam()
    if missing > 0 then
        widgets.chance:SetText("|cffff6060" .. Format(Text["You need {n} more companions for a team of 3."], { n = missing }) .. "|r")
    else
        widgets.chance:SetText("")
    end
    widgets.confirm:SetLabel(request.confirmText or Text["Confirm"])
    widgets.confirm:SetEnabled(#picks == Arena.TEAM_SIZE)
end

-- The wager in the box in copper (whole gold, MINIMUM_WAGER..MAXIMUM_WAGER), or nil.
---@return integer|nil
function TeamDialog.ReadWager()
    local gold = tonumber(widgets.wagerBox and widgets.wagerBox:GetText() or "")
    local copper = gold and math.floor(gold * 10000) or -1
    if copper < addon.Arena.MINIMUM_WAGER or copper > addon.Arena.MAXIMUM_WAGER then return nil end
    return copper
end

---@param gold number
function TeamDialog.SetWager(gold) if widgets.wagerBox then widgets.wagerBox:SetText(tostring(gold)) end end

-- Runs the request's action with the picked team (and the wager, when the request asks for one). A refusal stays in
-- the dialog; success closes it.
---@return boolean ok
function TeamDialog.Confirm()
    local request = TeamDialog.state.request
    if not request then return false end
    local picks = TeamDialog.state.picks
    if #picks ~= addon.Arena.TEAM_SIZE then
        widgets.error:SetText("|cffff6060" .. addon.ArenaView.RefusalText("team") .. "|r")
        return false
    end
    local wager
    if request.wager then
        wager = TeamDialog.ReadWager()
        if not wager then
            widgets.error:SetText("|cffff6060" .. addon.ArenaView.RefusalText("wager") .. "|r")
            return false
        end
    end
    local ok, reason = request.onConfirm({ picks[1], picks[2], picks[3] }, wager)
    if not ok then
        widgets.error:SetText("|cffff6060" .. addon.ArenaView.RefusalText(reason) .. "|r")
        addon.Animate.Shake(widgets.dialog, 4, 4)
        return false
    end
    TeamDialog.Close()
    return true
end

