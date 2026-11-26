local addonName, addon = ...

-- The team picker of an arena fight: a modal over the arena view. The opponent's team (when known: accepting or
-- countering) is shown at the top as a carousel, one fighter at a time (round portrait with its model, its level,
-- ability, stats and buffs; the arrows go through the three in fighting order), my three slots below it, then my whole roster to pick from (a click puts
-- a companion into the next free slot, a click on a slot empties it). With both teams known it shows my win chance
-- for the current pick. Confirm hands the uids in fighting order to the caller's action.
local TeamDialog = {}
addon.TeamDialog = TeamDialog

local Text, Format = addon.Text, addon.Locale.Format
local widgets = {}
TeamDialog.widgets = widgets

---@class TeamDialogRequest
---@field title string
---@field opponent? string the opponent's name (escaped short form)
---@field opponentTeam? Fighter[] their team when it is known
---@field fightID? string the fight's id (the win chance uses its seed)
---@field mySide? "a"|"b" which side of the fight my team is on (default "b")
---@field confirmText? string
---@field onConfirm fun(uids: string[]): boolean|nil, string|nil the action; a refusal reason keeps the dialog open
---@field hideBehind? table a page hidden while the dialog is open (shown again on close)

---@class TeamDialogState
---@field request TeamDialogRequest|nil
---@field picks string[] the uids in the slots (fighting order)
TeamDialog.state = { request = nil, picks = {}, shown = 1 }

local PORTRAIT_SIZE = 70
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
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
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
    addon.UI.Widgets.FitText(row.name, addon.Utility.Escape(fighter.n) .. (entry.active and " |cff66ff66*|r" or ""), 0.8)
    row.info:SetText(("|cff999999%s%d %s|r %d/%d/%d/%d"):format(Text["Lv"], fighter.al, addon.ArenaView.ABILITY_NAME[fighter.ab] or "",
        fighter.atk, fighter.def, fighter.spd, fighter.vit))
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
    widgets.title = Widgets.CreateFontString(dialog, "GameFontNormal", "LEFT")
    widgets.title:SetPoint("TOPLEFT", 8, -6); widgets.title:SetWidth(284)
    -- their team: one fighter at a time with arrows, or a note while challenging
    widgets.theirsLabel = Widgets.CreateFontString(dialog, "GameFontHighlightSmall", "LEFT")
    widgets.theirsLabel:SetPoint("TOPLEFT", 8, -24); widgets.theirsLabel:SetWidth(220)
    widgets.theirsIndex = Widgets.CreateFontString(dialog, "GameFontHighlightSmall", "RIGHT")
    widgets.theirsIndex:SetPoint("TOPRIGHT", -8, -24); widgets.theirsIndex:SetWidth(60)
    local card = CreateFrame("Frame", nil, dialog)
    card:SetPoint("TOPLEFT", 0, -38); card:SetPoint("TOPRIGHT", 0, -38); card:SetHeight(PORTRAIT_SIZE + 4)
    card:EnableMouseWheel(true)
    card:SetScript("OnMouseWheel", function(_, delta) TeamDialog.ShowTheirs(delta > 0 and -1 or 1) end)
    widgets.previous = Widgets.CreateButton(card, "<", 20, 30, function() TeamDialog.ShowTheirs(-1) end)
    widgets.previous:SetPoint("LEFT", 4, 0)
    widgets.next = Widgets.CreateButton(card, ">", 20, 30, function() TeamDialog.ShowTheirs(1) end)
    widgets.next:SetPoint("RIGHT", -4, 0)
    local portrait = CreateFrame("Frame", nil, card)
    portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE); portrait:SetPoint("LEFT", 28, 0)
    addon.PetView.Shape(portrait, DISC_TEXTURE, PORTRAIT_SIZE, { 0.04, 0.04, 0.06, 0.9 }, "BACKGROUND")
    addon.PetView.Shape(portrait, RING_TEXTURE, PORTRAIT_SIZE + 4, { 0.95, 0.78, 0.3, 0.95 }, "BORDER")
    widgets.model = addon.AzeCaughtPanel.CreateModel(portrait, PORTRAIT_SIZE - 6, PORTRAIT_SIZE - 6)
    widgets.model:SetPoint("CENTER", 0, -2)
    widgets.fighterName = Widgets.CreateFontString(card, "GameFontNormal", "LEFT")
    widgets.fighterName:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 8, -2); widgets.fighterName:SetWidth(166)
    widgets.fighterInfo = Widgets.CreateFontString(card, "GameFontHighlightSmall", "LEFT")
    widgets.fighterInfo:SetPoint("TOPLEFT", widgets.fighterName, "BOTTOMLEFT", 0, -3); widgets.fighterInfo:SetWidth(166)
    widgets.fighterInfo:SetJustifyV("TOP")
    widgets.card = card
    widgets.theirsNote = Widgets.CreateFontString(dialog, "GameFontDisableSmall", "CENTER")
    widgets.theirsNote:SetPoint("TOP", 0, -50); widgets.theirsNote:SetWidth(280)
    -- my slots
    widgets.mineLabel = Widgets.CreateFontString(dialog, "GameFontHighlightSmall", "LEFT")
    widgets.mineLabel:SetPoint("TOPLEFT", 8, -118); widgets.mineLabel:SetWidth(284)
    widgets.slots = {}
    for index = 1, addon.Arena.TEAM_SIZE do
        local slot = index
        local button = Widgets.CreateButton(dialog, "", 92, 20, function() TeamDialog.ClearSlot(slot) end)
        button:SetPoint("TOPLEFT", 6 + (index - 1) * 96, -132)
        widgets.slots[index] = button
    end
    -- my roster
    widgets.list = Widgets.CreateScrollList(dialog, 292, Widgets.ROW_HEIGHT * 7, createRosterRow, fillRosterRow)
    widgets.list:SetPoint("TOPLEFT", 4, -158)
    widgets.chance = Widgets.CreateFontString(dialog, "GameFontHighlightSmall", "CENTER")
    widgets.chance:SetPoint("BOTTOM", 0, 48); widgets.chance:SetWidth(290)
    widgets.error = Widgets.CreateFontString(dialog, "GameFontHighlightSmall", "CENTER")
    widgets.error:SetPoint("BOTTOM", 0, 34); widgets.error:SetWidth(290)
    widgets.cancel = Widgets.CreateButton(dialog, Text["Cancel"], 90, 22, function() TeamDialog.Close() end)
    widgets.cancel:SetPoint("BOTTOMLEFT", 8, 8)
    widgets.confirm = Widgets.CreateButton(dialog, Text["Confirm"], 130, 22, function() TeamDialog.Confirm() end)
    widgets.confirm:SetPoint("BOTTOMRIGHT", -8, 8)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.confirm) end
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
    TeamDialog.state.shown = 1
    if request.hideBehind then request.hideBehind:Hide() end
    widgets.dialog:Show()
    widgets.error:SetText("")
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
    if #picks < addon.Arena.TEAM_SIZE then picks[#picks + 1] = uid end
    TeamDialog.Refresh()
end

---@param slot integer
function TeamDialog.ClearSlot(slot)
    table.remove(TeamDialog.state.picks, slot)
    TeamDialog.Refresh()
end

local chanceCache = {}
-- My win chance with the current pick against the known opponent team (cached per pick), or nil.
---@return number|nil
function TeamDialog.Chance()
    local request, picks = TeamDialog.state.request, TeamDialog.state.picks
    if not request or not request.opponentTeam or #picks ~= addon.Arena.TEAM_SIZE then return nil end
    local key = (request.fightID or "?") .. "|" .. table.concat(picks, ",")
    if chanceCache[key] == nil then
        local mine = addon.Arena.Team(picks)
        if not mine then return nil end
        local id = request.fightID or "team"
        if request.mySide == "a" then
            chanceCache[key] = addon.Arena.WinChance(mine, request.opponentTeam, id)
        else
            chanceCache[key] = 1 - addon.Arena.WinChance(request.opponentTeam, mine, id)
        end
    end
    return chanceCache[key]
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

-- Moves the carousel of their team by `step` (wraps around; 0 redraws) and shows that fighter. Returns its slot.
---@param step integer
---@return integer|nil
function TeamDialog.ShowTheirs(step)
    local request = TeamDialog.state.request
    local team = request and request.opponentTeam
    local count = team and #team or 0
    if widgets.card then
        widgets.card:SetShown(count > 0)
        widgets.theirsIndex:SetShown(count > 0)
    end
    if count == 0 then return nil end
    local shown = ((TeamDialog.state.shown or 1) - 1 + (step or 0)) % count + 1
    TeamDialog.state.shown = shown
    if not widgets.card then return shown end
    local fighter = team[shown]
    widgets.theirsIndex:SetText(shown .. " / " .. count)
    addon.UI.Widgets.FitText(widgets.fighterName, "|cffffd100" .. shown .. ".|r " .. addon.Utility.Escape(fighter.n), 0.75)
    widgets.fighterInfo:SetText(TeamDialog.CardText(fighter))
    if widgets.shownFighter ~= fighter then
        widgets.shownFighter = fighter
        addon.AzeCaughtPanel.ShowModel(widgets.model, { npc = fighter.npc, disp = fighter.disp }, "team")
        if widgets.model.SetFacing then pcall(widgets.model.SetFacing, widgets.model, -0.5) end
    end
    return shown
end

function TeamDialog.Refresh()
    local request = TeamDialog.state.request
    if not request or not widgets.dialog then return end
    local Arena = addon.Arena
    widgets.title:SetText(request.title)
    local opponentTeam = request.opponentTeam
    widgets.theirsLabel:SetText(Format(Text["{name}'s team"], { name = request.opponent or "?" }))
    TeamDialog.ShowTheirs(0)
    widgets.theirsNote:SetText(opponentTeam and "" or Text["They see your team in full and pick theirs to counter it."])
    local picks = TeamDialog.state.picks
    widgets.mineLabel:SetText(Format(Text["Your team ({n}/{size}): click to pick or drop"],
        { n = #picks, size = Arena.TEAM_SIZE }))
    for index, button in ipairs(widgets.slots) do
        local companion = addon.AzeCaught.Companion(picks[index])
        button:SetLabel(companion and (index .. ". " .. addon.Utility.ShortText(companion.n, 11)) or ("|cff777777" .. index .. ". —|r"))
    end
    local rows = TeamDialog.Rows()
    widgets.list:SetData(rows)
    local missing = Arena.MissingForTeam()
    local chance = TeamDialog.Chance()
    if missing > 0 then
        widgets.chance:SetText("|cffff6060" .. Format(Text["You need {n} more companions for a team of 3."], { n = missing }) .. "|r")
    elseif chance then
        widgets.chance:SetText(Format(Text["Your win chance with this team: {n}%"], { n = math.floor(chance * 100 + 0.5) }))
    else
        widgets.chance:SetText("")
    end
    widgets.confirm:SetLabel(request.confirmText or Text["Confirm"])
    widgets.confirm:SetEnabled(#picks == Arena.TEAM_SIZE)
end

-- Runs the request's action with the picked team. A refusal stays in the dialog; success closes it.
---@return boolean ok
function TeamDialog.Confirm()
    local request = TeamDialog.state.request
    if not request then return false end
    local picks = TeamDialog.state.picks
    if #picks ~= addon.Arena.TEAM_SIZE then
        widgets.error:SetText("|cffff6060" .. addon.ArenaView.RefusalText("team") .. "|r")
        return false
    end
    local ok, reason = request.onConfirm({ picks[1], picks[2], picks[3] })
    if not ok then
        widgets.error:SetText("|cffff6060" .. addon.ArenaView.RefusalText(reason) .. "|r")
        addon.Animate.Shake(widgets.dialog, 4, 4)
        return false
    end
    TeamDialog.Close()
    return true
end

