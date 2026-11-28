local addonName, addon = ...

-- The AZEcaught game panel: three views in the 300 x 376 game stage.
--   Companion   the 3D model, hearts, need bars with threshold marks (a click on a bar cares for that need), the
--               care effects, and my fighter (level line, four stat icons that train; built by UI/ArenaView.lua)
--   Collection  every found NPC (caught ones first), a model preview, click a caught one to make it the companion
--   Arena       built by UI/ArenaView.lua; its Guild page (built here) lists every member's current companion by companion
--               level, with a preview of the selected one
-- Logic lives in Core/Minigames/AzeCaught.lua; this file only shows it and calls it. Model loading and emotes are journaled,
-- so a white or missing model can be traced with /gg caught log model.
---@class AzeCaughtPanelModule
local Panel = {}
addon.AzeCaughtPanel = Panel

local AzeCaught = addon.AzeCaught
local Text, Format = addon.Text, addon.Locale.Format

local HEART_ICON = "Interface\\Icons\\INV_ValentinesCandy"
local ZONE_COLOR = { ok = { 0.3, 0.85, 0.35 }, needy = { 1, 0.75, 0.15 }, critical = { 1, 0.25, 0.2 }, empty = { 0.6, 0.1, 0.1 } }
local ACTION_COLOR = { feed = { 1, 0.6, 0.2 }, water = { 0.3, 0.65, 1 }, pet = { 1, 0.45, 0.75 }, sleep = { 0.65, 0.5, 1 }, wake = { 1, 1, 0.6 } }
local RARITY_COLOR = { normal = "ffffff", elite = "ffd100", rare = "c0c0c0", rareelite = "a335ee", worldboss = "ff8000" }
local NEED_ORDER = AzeCaught.NEEDS
local CARE_COOLDOWN = 1.5    -- seconds the care buttons stay locked after a click
local CARE_OF_NEED = { hunger = "feed", thirst = "water", affection = "pet", energy = "sleep" }
local CARE_ICONS = { feed = "Interface\\Icons\\INV_Misc_Food_15", water = "Interface\\Icons\\INV_Drink_07",
    pet = "Interface\\Icons\\Ability_Hunter_BeastSoothe", sleep = "Interface\\Icons\\Spell_Nature_Sleep",
    wake = "Interface\\Icons\\Ability_Warrior_BattleShout" }
-- the history badges under the preview model and their icons (rows and hover panel use the same ones)
local HISTORY_ICONS = { seen = "Interface\\Icons\\INV_Misc_Spyglass_03", kills = "Interface\\Icons\\Ability_DualWield",
    caught = "Interface\\Icons\\Ability_Ensnare", last = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    first = "Interface\\Icons\\INV_Misc_Map_01" }
local HISTORY_COLOR = { seen = { 0.55, 0.75, 1 }, kills = { 1, 0.42, 0.35 }, caught = { 1, 0.82, 0.2 }, last = { 0.85, 0.85, 0.85 } }
local BADGE_SIZE, BADGE_GAP = 24, 2
Panel.HISTORY_ICONS = HISTORY_ICONS
-- inline icon for a text line (trimmed border)
---@param key string
---@param size? integer
---@return string
local function inlineIcon(key, size)
    size = size or 12
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(HISTORY_ICONS[key], size, size)
end
Panel.InlineIcon = inlineIcon
local BAR_WIDTH = 210   -- the label is an icon, so the bar takes the room

---@class AzeCaughtPanelState
---@field view "companion"|"collection"|"arena"|"shop"|"inventory"
---@field section "caught"|"seen" the collection's section
---@field previewNpc integer|nil collection preview
---@field selectedNpc integer|nil the collection row the switch button acts on
---@field guildRow CompanionRow|nil guild preview
---@field selectedUid string|nil the roster companion the switch and release buttons act on
---@field confirmUid string|nil the roster companion waiting in the confirm dialog
---@field confirmMode "switch"|"release"|nil
---@field careReadyAt number|nil clock until the care buttons unlock (CARE_COOLDOWN)
---@field badgeNpc integer|nil whose history badges are shown
---@field badgeValues table|nil their values (a rise pulses the badge)
---@field guildBadgeOwner string|nil whose stat badges are shown in the guild preview
Panel.state = { view = "companion", section = "caught" }
-- the tabs, in this order, and their icons
Panel.VIEWS = { "companion", "collection", "arena", "shop", "inventory" }
local VIEW_ICONS = {
    companion = "Interface\\Icons\\Ability_Hunter_BeastTaming",
    collection = "Interface\\Icons\\INV_Misc_Book_09",
    arena = "Interface\\Icons\\Ability_DualWield",
    shop = "Interface\\Icons\\INV_Misc_Coin_02",
    inventory = "Interface\\Icons\\INV_Misc_Bag_08",
}

-- Tabs that need a companion: until one is chosen only Companion and Collection open (a catch while none is chosen
-- makes the caught NPC the companion).
Panel.NEEDS_COMPANION = { arena = true, guild = true, shop = true, inventory = true }

-- True while `view` is locked because no companion is chosen.
---@param view string
---@return boolean
function Panel.ViewLocked(view)
    return Panel.NEEDS_COMPANION[view] == true and AzeCaught.Active() == nil
end

-- The view a saved `view` opens (an unknown or old one opens the companion).
---@param view any
---@return string
function Panel.RestorableView(view)
    if view == "collection" or view == "guild" or view == "shop" or view == "inventory" then return view end
    return "companion"
end

local widgets = {}
Panel.widgets = widgets
-- per care button: the action it does now and why it is greyed out (kept off the frames)
---@type table<string, { action: string, unusable: string|nil }>
local careState = {}
Panel.careState = careState

local me = addon.Utility.Me
local money = addon.Model.MoneyText
local settings = addon.UIHelpers.Settings

------------------------------------------------------------------ texts

---@param classification string
---@return string
local function rarityText(classification) return addon.Model.RarityText(classification) end

---@param need string
---@return string
local function needLabel(need)
    if need == "hunger" then return Text["Food"] end
    if need == "thirst" then return Text["Water"] end
    if need == "affection" then return Text["Petting"] end
    return Text["Energy"]
end

---@param refusal string|nil
---@return string
local function careRefusalText(refusal)
    local commonText = addon.Model.CommonRefusalText(refusal, me())
    if commonText then return commonText end
    if refusal == "asleep" then return Text["It is asleep. Wake it first."] end
    if refusal == "full" then return Text["It does not need that right now."] end
    if refusal == "awake" then return Text["It is already awake."] end
    return Text["No companion. Catch an NPC and pick it in the collection."]
end

local duration = addon.Model.Duration


------------------------------------------------------------------ need bars

---@param parent table
---@param y number
---@param careKey? "feed"|"water"|"pet"|"sleep" makes the bar a care button (my companion's bars)
---@return table bar
local function createBar(parent, y, careKey)
    local Widgets = addon.UI.Widgets
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(286, 14); bar:SetPoint("TOPLEFT", 8, y)
    -- the need as an icon instead of its name; the name stays in the tooltip
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(16, 16); bar.icon:SetPoint("LEFT", 0, 0)
    if bar.icon.SetTexCoord then bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetSize(BAR_WIDTH, 10); track:SetPoint("LEFT", 22, 0); track:SetColorTexture(0, 0, 0, 0.55)
    bar.track = track
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetHeight(10); bar.fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    -- threshold marks: critical and needy (moved to the companion's own thresholds in fillBar)
    bar.ticks = {}
    for index, level in ipairs({ AzeCaught.CRITICAL_LEVEL, AzeCaught.OK_LEVEL }) do
        local tick = bar:CreateTexture(nil, "OVERLAY")
        tick:SetSize(2, 14); tick:SetPoint("CENTER", track, "LEFT", BAR_WIDTH * level / 100, 0)
        tick:SetColorTexture(1, 1, 1, index == 1 and 0.75 or 0.45)
        bar.ticks[index] = tick
    end
    bar.value = Widgets.CreateFontString(bar, "GameFontHighlightSmall", "RIGHT")
    bar.value:SetPoint("RIGHT", 0, 0); bar.value:SetWidth(52)
    bar:EnableMouse(true)
    if careKey then
        bar.careKey = careKey
        bar.highlight = bar:CreateTexture(nil, "HIGHLIGHT"); bar.highlight:SetAllPoints(); bar.highlight:SetColorTexture(1, 1, 1, 0.12)
        bar:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not self.careEnabled then return end
            Panel.ClickCare(careKey)
            if GameTooltip and GameTooltip:GetOwner() == self then self:GetScript("OnEnter")(self) end
        end)
    end
    bar:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.need then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(needLabel(self.need))
        GameTooltip:AddLine(self.tooltipText or "", 1, 1, 1, true)
        if self.careKey then Panel.AddCareTooltip(self.careKey) end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return bar
end

---@param bar table
---@param need string
---@param value number
---@param companion CompanionState|nil (nil for a peer's bars)
local function fillBar(bar, need, value, companion)
    if bar.need ~= need then
        local icons = { hunger = CARE_ICONS.feed, thirst = CARE_ICONS.water, affection = CARE_ICONS.pet, energy = CARE_ICONS.sleep }
        addon.UIHelpers.SetTextureOr(bar.icon, icons[need] or CARE_ICONS.feed, { 0.6, 0.6, 0.6 })
    end
    bar.need = need
    -- the companion's own thresholds (from its stats); peers' bars use the base ones
    local profile = AzeCaught.ProfileOf(companion)
    for index, level in ipairs({ profile.critical, profile.ok }) do
        bar.ticks[index]:ClearAllPoints()
        bar.ticks[index]:SetPoint("CENTER", bar.track, "LEFT", BAR_WIDTH * level / 100, 0)
    end
    local zone = AzeCaught.Zone(value, profile.ok, profile.critical)
    local color = ZONE_COLOR[zone]
    bar.fill:SetWidth(math.max(1, BAR_WIDTH * value / 100))
    bar.fill:SetColorTexture(color[1], color[2], color[3], 0.9)
    bar.value:SetText(("%d%%"):format(math.floor(value + 0.5)))
    if companion and not profile.intervals[need] then
        bar.fill:SetColorTexture(0.45, 0.45, 0.45, 0.6)
        bar.value:SetText(Text["never"])
        bar.tooltipText = Text["This companion never needs this."]
    elseif companion then
        local seconds = AzeCaught.SecondsUntilNeedy(companion, need)
        bar.tooltipText = seconds > 0 and Format(Text["Needs care in {time}."], { time = duration(seconds) }) or Text["Needs care now."]
    else
        bar.tooltipText = nil
    end
end

------------------------------------------------------------------ views

---@param view "companion"|"collection"|"guild"|"arena"|"shop"|"inventory" "guild": the arena's Guild page
function Panel.SelectView(view)
    if Panel.ViewLocked(view) then view = "companion" else settings().caughtView = view end
    if view == "guild" then   -- the guild list lives in the arena
        view = "arena"
        addon.ArenaView.state.page = "guild"
        if addon.ArenaView.widgets.panel then addon.ArenaView.SelectPage("guild") end
    end
    Panel.state.view = view
    for key, frame in pairs(widgets.views or {}) do frame:SetShown(key == view) end
    Panel.UpdateViewButtons()
    AzeCaught.Journal("DEBUG", "ui.view", "a view was selected", { view = view })
    if view == "arena" then Panel.AdvanceGuide("arena") end
    Panel.Refresh()
end

-- The tab buttons: the open one selected, the locked ones greyed out with the reason in their tooltip.
function Panel.UpdateViewButtons()
    local view = Panel.state.view
    for key, button in pairs(widgets.viewButtons or {}) do
        local locked = Panel.ViewLocked(key)
        button:SetEnabled(key ~= view and not locked)
        if button.SetSelected then button:SetSelected(key == view) end
        if button.icon then
            button.icon:SetAlpha(key == view and 1 or (locked and 0.3 or 0.6))
            if button.icon.SetDesaturated then button.icon:SetDesaturated(locked) end
        end
        button.lockedText = locked and Text["Catch a companion first: your next catch becomes it."] or nil
    end
end

-- A companion was chosen or lost: the locks change, and a locked tab that is open goes back to the companion.
function Panel.UpdateViewLocks()
    if not widgets.viewButtons then return end
    if Panel.ViewLocked(Panel.state.view) then Panel.SelectView("companion") else Panel.UpdateViewButtons() end
end

-- A care button's click: ignored during the click cooldown, else the action (Sleep turns into Wake while asleep).
-- The cooldown is shared by every view that cares (this panel and the pet view), so one click pays once.
---@param key "feed"|"water"|"pet"|"sleep"
---@param target? CareTarget where the effects show; default this panel
function Panel.ClickCare(key, target)
    local clock = addon.Api.Clock()
    if clock < (Panel.state.careReadyAt or 0) then
        AzeCaught.Journal("DEBUG", "ui.cooldown", "a care click came during the cooldown", { action = key,
            left = math.floor((Panel.state.careReadyAt - clock) * 10) / 10 })
        return
    end
    local companion = AzeCaught.Active()
    local action = (key == "sleep" and companion and companion.asleep) and "wake" or key
    Panel.state.careReadyAt = clock + CARE_COOLDOWN
    Panel.Care(action, target)
    Panel.RefreshCareButtons()
    addon.Events.Fire("CARE_COOLDOWN")
    if C_Timer then C_Timer.After(CARE_COOLDOWN + 0.05, function()
        Panel.RefreshCareButtons()
        addon.Events.Fire("CARE_COOLDOWN")
    end) end
end

---@return number seconds until care clicks are accepted again (0 = now)
function Panel.CareCooldownLeft()
    return math.max(0, (Panel.state.careReadyAt or 0) - addon.Api.Clock())
end
Panel.CARE_COOLDOWN, Panel.CARE_ICONS, Panel.ACTION_COLOR = CARE_COOLDOWN, CARE_ICONS, ACTION_COLOR
Panel.CareRefusalText, Panel.NeedLabel = careRefusalText, needLabel
Panel.HEART_ICON = HEART_ICON

-- Icons and greyed-out state of the clickable need bars (AzeCaught.CareAvailability; the cooldown greys them too).
function Panel.RefreshCareButtons()
    if not widgets.careBars then return end
    local companion = AzeCaught.Active()
    local coolingDown = addon.Api.Clock() < (Panel.state.careReadyAt or 0)
    for key, bar in pairs(widgets.careBars) do
        local action = (key == "sleep" and companion and companion.asleep) and "wake" or key
        local usable, reason = AzeCaught.CareAvailability(action, me())
        careState[key] = { action = action, unusable = not usable and reason or nil }
        addon.UIHelpers.SetTextureOr(bar.icon, CARE_ICONS[action], ACTION_COLOR[action] or { 1, 1, 1 })
        bar.careEnabled = usable and not coolingDown
        pcall(bar.icon.SetDesaturated, bar.icon, not bar.careEnabled)
        bar.icon:SetAlpha(bar.careEnabled and 1 or 0.4)
    end
end

-- The care lines of a need bar's tooltip: what a click does and what it costs, or why it cannot be done now.
---@param key "feed"|"water"|"pet"|"sleep"
function Panel.AddCareTooltip(key)
    local state = careState[key] or {}
    local shown = state.action or key
    local line
    if shown == "feed" then line = Format(Text["Feed for {gold}"], { gold = money(AzeCaught.FOOD_PRICE) })
    elseif shown == "water" then line = Format(Text["Water for {gold}"], { gold = money(AzeCaught.WATER_PRICE) })
    elseif shown == "pet" then line = Text["Petting is free."]
    elseif shown == "wake" then line = Text["Wake"]
    else line = Format(Text["Sleeps {time}; refills energy."], { time = duration(AzeCaught.SLEEP_DURATION) }) end
    GameTooltip:AddLine(Text["Click:"] .. " " .. line, 0.4, 1, 0.4, true)
    if shown == "sleep" and addon.Arena.TrainingLeft() and addon.Arena.TrainingLeft() > 0 then
        GameTooltip:AddLine(Text["Sleeping stops the running training (no refund)."], 1, 0.6, 0.2, true)
    end
    if state.unusable then GameTooltip:AddLine(careRefusalText(state.unusable), 1, 0.4, 0.4, true) end
end

-- A line in the Companion view's status line (a training refusal, a care result).
---@param text string
function Panel.ShowStatus(text)
    if widgets.statusText then widgets.statusText:SetText(text) end
end

---@class CareTarget where a care action's effects show
---@field parent table the frame the burst is drawn on
---@field view ModelViewObject the companion view that plays the emote
---@field heartIcon table|nil pulses on a heart gain
---@field floatText table|nil the "+n hearts" text (nil: no floating text)
---@field status fun(text: string)|nil shows the refusal or the price paid (nil: the refusal goes to the error line)

---@return CareTarget
local function panelTarget()
    return { parent = widgets.companionView, view = widgets.modelView, heartIcon = widgets.heartIcon, floatText = widgets.floatText,
        status = function(text) widgets.statusText:SetText(text) end }
end

-- care button -> AzeCaught.Care + effects on `target` (default this panel)
---@param action CareAction
---@param target? CareTarget
function Panel.Care(action, target)
    target = target or panelTarget()
    local result, refusal = AzeCaught.Care(action, me(), addon.Utility.Now())
    if not result then
        local text = careRefusalText(refusal)
        if target.status then target.status("|cffff5555" .. text .. "|r")
        elseif UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, 1, 0.3, 0.3) end
        return
    end
    local color = ACTION_COLOR[action] or { 1, 1, 1 }
    local model = target.view.frame
    addon.Animate.Burst("care", target.parent, model, 0, -20, { count = 18, color = color, speed = 120, duration = 1 })
    if result.hearts > 0 then
        if target.floatText then
            addon.Animate.FloatText("hearts", target.floatText, model, 0, 10, "+" .. result.hearts .. " " .. Text["hearts"], { 1, 0.3, 0.4 })
        end
        if target.heartIcon then addon.Animate.Pulse(target.heartIcon, 1.5, 0.4) end
    end
    target.view.Emote(addon.ModelView.ANIMATION[action] and action or "stand", action)
    addon.Api.PlaySound(addon.Api.SoundKitFor({ "IG_MAINMENU_OPTION_CHECKBOX_ON" }))
    if target.status then target.status(result.cost > 0 and Format(Text["Paid {gold}."], { gold = money(result.cost) }) or "") end
    if result.trainingCancelled then addon.Print(Text["The running training was cancelled."]) end
    addon.Catcher.PublishSoon(true)
    addon.Events.Fire("CAUGHT_CHANGED")
end

-- Makes roster companion `uid` active (after the confirm dialog, see Panel.RequestSwitch).
---@param uid string
function Panel.SelectCompanion(uid)
    local companion, refusal, trainingCancelled = AzeCaught.Select(uid, addon.Utility.Now())
    if not companion then
        widgets.collectionStatus:SetText(refusal == "notcaught" and Text["Only caught NPCs can be your companion."] or "")
        return
    end
    if trainingCancelled then addon.Print(Text["The running training was cancelled."]) end
    addon.Catcher.lastZones = {}
    addon.Catcher.PublishSoon(true)
    addon.Events.Fire("CAUGHT_CHANGED")
    Panel.SelectView("companion")
    addon.Animate.Ring("select", widgets.companionView, widgets.model, 40, 220, { 1, 0.85, 0.3 })
end

------------------------------------------------------------------ hover panel: everything known about the NPC
-- A tooltip-style panel BESIDE the model (the companion stays visible), grouped: header, values, needs, traits.
-- Unknown values are only counted. Needs are coloured by how they compare with the normal schedule.

local NEED_ICON = { thirst = CARE_ICONS.water, hunger = CARE_ICONS.feed, affection = CARE_ICONS.pet, energy = CARE_ICONS.sleep }
local TREND_COLOR = { more = { 1, 0.6, 0.25 }, less = { 0.45, 0.8, 1 }, normal = { 1, 1, 1 }, never = { 0.5, 0.5, 0.5 } }

---@param hex string "rrggbb"
---@return number red
---@return number green
---@return number blue
local function hexColor(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- A stat bar as inline textures (right-aligned after the number, so the bars line up): the filled part in the stat's
-- colour (gold when stronger than a full bar), the rest dark.
local STAT_BAR_WIDTH, STAT_BAR_HEIGHT = 80, 8
local STAT_COLOR = { attack = { 220, 70, 60 }, defense = { 70, 140, 230 }, speed = { 90, 200, 90 } }
local STAT_OVER_COLOR, STAT_EMPTY_COLOR = { 255, 200, 40 }, { 50, 50, 50 }
---@param width integer
---@param color integer[] r, g, b 0-255
---@return string
local function barPiece(width, color)
    if width < 1 then return "" end
    return ("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(STAT_BAR_HEIGHT, width, color[1], color[2], color[3])
end
---@param stat { key: string, fill: number, over: boolean }
---@return string
function Panel.StatBar(stat)
    local filled = math.floor(STAT_BAR_WIDTH * addon.Utility.Clamp(stat.fill, 0, 1) + 0.5)
    return barPiece(filled, stat.over and STAT_OVER_COLOR or STAT_COLOR[stat.key] or STAT_COLOR.attack)
        .. barPiece(STAT_BAR_WIDTH - filled, STAT_EMPTY_COLOR)
end

-- Fills `tooltip` (GameTooltip) with the NPC's info. Returns the number of lines added (tests).
---@param tooltip table
---@param owner table
---@param npcID integer
---@param entry CollectionEntry
---@param extra? { label: string, value: string, color: number[] }[] rows under the subtitle
---@return integer lines
function Panel.ShowNpcInfo(tooltip, owner, npcID, entry, extra)
    local npcView = addon.Model.BuildNpcInfo(npcID, entry)
    local count = 0
    local function line(...) tooltip:AddLine(...) count = count + 1 end
    local function double(...) tooltip:AddDoubleLine(...) count = count + 1 end
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local red, green, blue = hexColor(npcView.rarityColor)
    tooltip:SetText(npcView.title, red, green, blue)
    line(npcView.subtitle, 0.75, 0.75, 0.75)
    -- extra rows right under the subtitle (a guild member's companion: its level and hearts)
    if extra and #extra > 0 then
        line(" ")
        for _, row in ipairs(extra) do double(row.label, row.value, 0.65, 0.65, 0.65, row.color[1], row.color[2], row.color[3]) end
    end
    if #npcView.facts > 0 or npcView.hiddenCount > 0 then
        line(" ")
        for _, fact in ipairs(npcView.facts) do double(fact.label, fact.value, 0.65, 0.65, 0.65, 1, 1, 1) end
        if npcView.hiddenCount > 0 then
            line(addon.Locale.Plural(npcView.hiddenCount, Text["The game hides 1 more value."], Text["The game hides {n} more values."]),
                0.5, 0.5, 0.5)
        end
    end
    -- the history: how often seen, killed, caught x/y, first and last seen (none for an NPC I never met: a guild
    -- member's companion)
    local history, timeAgo = npcView.history, addon.UI.Widgets.TimeAgo
    if history.seen > 0 and history.first then
        line(" ")
        line(Text["History"], 1, 0.82, 0)
        double(inlineIcon("seen") .. " " .. Text["Seen"], Format(Text["{n} times"], { n = history.seen }), 0.65, 0.65, 0.65, 1, 1, 1)
        double(inlineIcon("kills") .. " " .. Text["Killed"], tostring(history.kills), 0.65, 0.65, 0.65, 1, 1, 1)
        double(inlineIcon("caught") .. " " .. Text["Caught"], history.caught .. "/" .. history.throws, 0.65, 0.65, 0.65, 1, 1, 1)
        double(inlineIcon("first") .. " " .. Text["First seen"], timeAgo(history.first), 0.65, 0.65, 0.65, 1, 1, 1)
        double(inlineIcon("last") .. " " .. Text["Last seen"], timeAgo(history.last), 0.65, 0.65, 0.65, 1, 1, 1)
    end
    line(" ")
    line(Text["Combat"], 1, 0.82, 0)
    for _, stat in ipairs(npcView.combat) do double(stat.label, stat.value .. " " .. Panel.StatBar(stat), 0.65, 0.65, 0.65, 1, 1, 1) end
    line(" ")
    line(Text["Needs"], 1, 0.82, 0)
    for _, need in ipairs(npcView.needs) do
        local color = TREND_COLOR[need.trend]
        local marker = need.trend == "more" and (" " .. Text["(more often)"]) or need.trend == "less" and (" " .. Text["(less often)"]) or ""
        double("|T" .. NEED_ICON[need.need] .. ":14:14:0:0:64:64:5:59:5:59|t " .. need.label, need.text .. marker,
            1, 1, 1, color[1], color[2], color[3])
    end
    line(npcView.thresholds, 0.65, 0.65, 0.65)
    if #npcView.traits > 0 then
        line(" ")
        line(Text["Traits"], 1, 0.82, 0)
        for _, trait in ipairs(npcView.traits) do line(trait, 0.85, 0.85, 0.85, true) end
    end
    tooltip:Show()
    return count
end

-- The tooltip of one of my companions: the shown name, the species when it has a nickname, where and when it was
-- caught, and an optional hint line.
---@param tooltip table
---@param companion CompanionState
---@param hint? string
function Panel.ShowCompanionTooltip(tooltip, companion, hint)
    local Escape = addon.Utility.Escape
    tooltip:SetText(Escape(AzeCaught.ShownName(companion)), 1, 0.82, 0)
    if AzeCaught.HasNickname(companion) then tooltip:AddLine(Escape(AzeCaught.SpeciesName(companion)), 0.85, 0.85, 0.85) end
    local at, map = AzeCaught.CatchOrigin(companion)
    tooltip:AddLine(addon.Model.CatchOriginText(at, addon.Api.MapName(map), rawget(_G, "date")), 0.55, 0.8, 1)
    local gender = addon.Model.GenderText(AzeCaught.CompanionSex(companion))
    if gender then tooltip:AddLine(Text["Gender"] .. ": " .. gender, 0.85, 0.85, 0.85) end
    if hint then tooltip:AddLine(hint, 0.6, 0.6, 0.6) end
    tooltip:Show()
end

-- Shows the info panel while the mouse is over `model`. `getNpc()` returns npcID, collection entry (or nil: nothing).
---@param model table
---@param getNpc fun(): integer|nil, CollectionEntry|nil
local function attachInfoPanel(model, getNpc)
    model:HookScript("OnEnter", function(self)
        local npcID, entry = getNpc()
        if not entry or not GameTooltip then return end
        Panel.ShowNpcInfo(GameTooltip, self, npcID, entry)
        AzeCaught.Journal("DEBUG", "ui.info", "the NPC npcView panel was shown", { npc = npcID, stats = AzeCaught.StatsText(entry.st) })
    end)
    model:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- The collection entry of `companion`'s NPC for the info panel, with the companion's own gender (an NPC can be both).
---@param companion table
---@return CollectionEntry|nil
local function entryOf(companion)
    local entry = AzeCaught.State().collection[companion.npc]
    local sex = AzeCaught.CompanionSex(companion)
    if not entry or not sex then return entry end
    local copy = {}
    for key, value in pairs(entry) do copy[key] = value end
    copy.st = {}
    for key, value in pairs(type(entry.st) == "table" and entry.st or {}) do copy.st[key] = value end
    copy.st.sex = sex
    return copy
end

---@return integer|nil npcID
---@return CollectionEntry|nil
local function companionNpc()
    local companion = AzeCaught.Active()
    if not companion then return nil, nil end
    return companion.npc, entryOf(companion)
end

---@return integer|nil npcID
---@return CollectionEntry|nil
local function previewNpc()
    local npcID = Panel.state.previewNpc
    local companion = AzeCaught.Companion(Panel.state.previewUid)
    if npcID and companion and companion.npc == npcID then return npcID, entryOf(companion) end
    return npcID, npcID and AzeCaught.State().collection[npcID] or nil
end
Panel.CompanionNpc, Panel.PreviewNpc = companionNpc, previewNpc

-- The info panel entry of a guild member's companion: my own collection entry of that NPC (its stats and my history
-- with it) with the companion's name, level and rarity; without one, only what the guild record tells (no history).
---@param row CompanionRow|nil
---@return integer|nil npcID
---@return CollectionEntry|nil
function Panel.GuildNpc(row)
    if type(row) ~= "table" or not row.npc then return nil, nil end
    local entry = { cnt = 0 }
    for key, value in pairs(AzeCaught.State().collection[row.npc] or {}) do entry[key] = value end
    -- the row's species name is already escaped (BuildNpcInfo escapes once more: shown literally, still safe)
    entry.n = entry.n or row.species or "?"
    entry.lvl, entry.cls, entry.disp = row.lvl, row.cls, row.disp or entry.disp
    return row.npc, entry
end

-- The info panel of a guild member's companion, with its TLevel (the ranking value) and its hearts on top.
---@param tooltip table
---@param owner table
---@param row CompanionRow|nil
---@return integer|nil lines nil: no companion
function Panel.ShowGuildNpcInfo(tooltip, owner, row)
    local npcID, entry = Panel.GuildNpc(row)
    if not entry then return nil end
    local hearts = tonumber(row.hearts) or 0
    local extra = {
        { label = "|TInterface\\Icons\\Ability_Hunter_BeastTraining:14:14:0:0:64:64:5:59:5:59|t " .. Text["TLevel"],
          value = tostring(row.level or AzeCaught.CompanionLevel(row) or 0), color = { 1, 0.82, 0.2 } },
        { label = "|TInterface\\Icons\\INV_ValentinesCandy:14:14:0:0:64:64:5:59:5:59|t " .. Text["Hearts"],
          value = ("%+d"):format(hearts), color = { 1, 0.25, 0.4 } },
    }
    return Panel.ShowNpcInfo(tooltip, owner, npcID, entry, extra)
end

---@param panel table
local function buildCompanionView(panel)
    local Widgets = addon.UI.Widgets
    widgets.companionView = panel
    widgets.modelView = addon.ModelView.New(panel, { preset = "portrait", width = 300, height = 150, companion = true, area = "companion" })
    local model = widgets.modelView.frame
    model:SetPoint("TOP", 0, -24)
    widgets.model = model
    attachInfoPanel(model, companionNpc)
    widgets.nameText = Widgets.CreateFontString(panel, "GameFontNormal", "CENTER")
    widgets.nameText:SetPoint("TOP", 0, -26); widgets.nameText:SetWidth(290)
    Panel.BuildRename(panel)
    widgets.floatText = Widgets.CreateFontString(panel, "GameFontNormalLarge", "CENTER"); widgets.floatText:Hide()
    widgets.sleepText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.sleepText:SetPoint("BOTTOM", model, "BOTTOM", 0, 4)

    local heart = panel:CreateTexture(nil, "ARTWORK")
    heart:SetSize(18, 18); heart:SetPoint("TOPLEFT", 8, -180); heart:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addon.UIHelpers.SetTextureOr(heart, HEART_ICON, { 0.9, 0.1, 0.2 })
    widgets.heartIcon = heart
    widgets.heartText = Widgets.CreateFontString(panel, "GameFontNormalLarge", "LEFT")
    widgets.heartText:SetPoint("LEFT", heart, "RIGHT", 4, 0)
    widgets.streakText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "RIGHT")
    widgets.streakText:SetPoint("TOPRIGHT", -8, -182); widgets.streakText:SetWidth(200)

    -- the need bars are the care buttons: a click on a bar cares for that need
    widgets.bars, widgets.careBars = {}, {}
    for index, need in ipairs(NEED_ORDER) do
        local careKey = CARE_OF_NEED[need]
        widgets.bars[need] = createBar(panel, -204 - (index - 1) * 18, careKey)
        if careKey then widgets.careBars[careKey] = widgets.bars[need] end
    end

    -- my fighter: the level line under the name, the four stat icons where the care buttons were
    addon.ArenaView.BuildFighterBlock(panel, -42, -276, Panel.ShowStatus)
    widgets.statusText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.statusText:SetPoint("TOP", 0, -322); widgets.statusText:SetWidth(290)
    widgets.emptyCompanion = Widgets.CreateFontString(panel, "GameFontDisable", "CENTER")
    widgets.emptyCompanion:SetPoint("TOP", 0, -90); widgets.emptyCompanion:SetWidth(270)
    widgets.emptyCompanion:SetText(Text["No companion yet. Bring an enemy below 35% health, throw the rope (icon on its nameplate, key binding or /gg catch) and kill it within 3 seconds. Then pick it in the collection."])
end

---@param list table
---@return table row
local function createCollectionRow(list)
    local Widgets = addon.UI.Widgets
    local row = CreateFrame("Button", nil, list)
    row.hover = row:CreateTexture(nil, "BACKGROUND"); row.hover:SetAllPoints(); row.hover:SetColorTexture(1, 1, 1, 0.07); row.hover:Hide()
    row.active = row:CreateTexture(nil, "BACKGROUND", nil, 1); row.active:SetAllPoints(); row.active:SetColorTexture(1, 0.8, 0.2, 0.16); row.active:Hide()
    row.name = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT"); row.name:SetPoint("LEFT", 4, 0); row.name:SetWidth(112)
    row.info = Widgets.CreateFontString(row, "GameFontHighlightSmall", "RIGHT"); row.info:SetPoint("RIGHT", -2, 0); row.info:SetWidth(60)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.entry then Panel.state.previewNpc, Panel.state.previewUid = self.entry.npc, self.entry.uid; Panel.RefreshPreview() end
        local companion = self.entry and AzeCaught.Companion(self.entry.uid)
        if companion and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            Panel.ShowCompanionTooltip(GameTooltip, companion)
        end
    end)
    row.selected = row:CreateTexture(nil, "BACKGROUND", nil, 2); row.selected:SetAllPoints(); row.selected:SetColorTexture(0.3, 0.6, 1, 0.22); row.selected:Hide()
    row:SetScript("OnLeave", function(self) self.hover:Hide(); if GameTooltip then GameTooltip:Hide() end end)
    -- a click selects the row (preview + the switch button); switching needs the button and its confirm dialog
    row:SetScript("OnClick", function(self) if self.entry then Panel.SelectRow(self.entry.npc, self.entry.uid) end end)
    return row
end

---@param row table
---@param entry CollectionRow
local function fillCollectionRow(row, entry)
    row.active:SetShown(entry.active)
    row.selected:SetShown(entry.uid and entry.uid == Panel.state.selectedUid or (not entry.uid and entry.npc == Panel.state.selectedNpc))
    local color = entry.caught > 0 and (RARITY_COLOR[entry.cls] or "ffffff") or "777777"
    addon.UI.Widgets.FitText(row.name, "|cff" .. color .. entry.name .. "|r", 0.85)
    if Panel.state.section == "seen" then   -- how often seen, then the level
        row.info:SetText(inlineIcon("seen", 11) .. "|cff88bbff" .. entry.history.seen .. "|r |cffaaaaaa" .. entry.lvl .. "|r")
    else   -- arena level, then the NPC level
        row.info:SetText("|cffffd100A" .. (entry.arenaLevel or 1) .. "|r |cffaaaaaa" .. entry.lvl .. "|r")
    end
end

------------------------------------------------------------------ collection: sections, selection, switching

-- "caught" (the roster: one row per companion) or "seen" (every enemy fought, with its highest level)
---@param section "caught"|"seen"
function Panel.SelectSection(section)
    Panel.state.section = section == "seen" and "seen" or "caught"
    settings().caughtSection = Panel.state.section
    for key, button in pairs(widgets.sectionButtons or {}) do
        button:SetEnabled(key ~= Panel.state.section)
        if button.SetSelected then button:SetSelected(key == Panel.state.section) end
    end
    Panel.Refresh()
end

-- Switch: a resting roster companion is selected. Release: any roster companion is selected.
local function refreshSwitchButton()
    if not widgets.switchButton then return end
    local companion = Panel.state.section ~= "seen" and AzeCaught.Companion(Panel.state.selectedUid) or nil
    widgets.switchButton:SetEnabled(companion ~= nil and companion ~= AzeCaught.Active())
    widgets.releaseButton:SetEnabled(companion ~= nil)
    Panel.RefreshRosterRename(companion)
end

------------------------------------------------------------------ collection: naming the selected companion (once)

-- The Rename button shows for a selected roster companion without a nickname. While editing, the box with the tick
-- and the cross stands in its place; it closes when the selection moves to another companion.
---@param companion CompanionState|nil the selected roster companion
function Panel.RefreshRosterRename(companion)
    local editor, button = widgets.renameEditor, widgets.renameRowButton
    if not editor then return end
    if editor:IsShown() and (not companion or companion.uid ~= editor.uid or not AzeCaught.CanRename(companion)) then
        editor.uid = nil
        editor:Hide()
    end
    button:SetShown(not editor:IsShown() and AzeCaught.CanRename(companion))
end

function Panel.StartRosterRename()
    local companion = AzeCaught.Companion(Panel.state.selectedUid)
    if not AzeCaught.CanRename(companion) then return end
    local editor, box = widgets.renameEditor, widgets.renameRowBox
    editor.uid = companion.uid
    box:SetText("")
    widgets.renameRowButton:Hide()
    widgets.collectionStatus:SetText("")
    editor:Show(); box:SetFocus()
end

-- The tick (or Enter): names the companion; a refusal stays in the box with its reason under the list.
function Panel.ConfirmRosterRename()
    local editor, box = widgets.renameEditor, widgets.renameRowBox
    local uid = editor.uid
    if not uid then return end
    local ok, refusal = addon.Catcher.Rename(uid, box:GetText() or "")
    if not ok then
        widgets.collectionStatus:SetText("|cffff6060" .. (refusal or "") .. "|r")
        box:SetFocus()
        return
    end
    editor.uid = nil
    box:ClearFocus(); editor:Hide()
    widgets.collectionStatus:SetText("")
    Panel.Refresh()
end

-- The cross (or Escape): back to the button, nothing changes.
function Panel.CancelRosterRename()
    local editor = widgets.renameEditor
    editor.uid = nil
    widgets.renameRowBox:ClearFocus(); editor:Hide()
    widgets.collectionStatus:SetText("")
    Panel.RefreshRosterRename(AzeCaught.Companion(Panel.state.selectedUid))
end

---@param npcID integer
---@param uid? string the roster companion (caught section)
function Panel.SelectRow(npcID, uid)
    Panel.state.selectedNpc, Panel.state.selectedUid, Panel.state.previewNpc, Panel.state.previewUid = npcID, uid, npcID, uid
    local entry = AzeCaught.State().collection[npcID]
    widgets.collectionStatus:SetText(not uid and entry and (entry.caught or 0) < 1 and Text["Only caught NPCs can be your companion."] or "")
    if widgets.collectionList then widgets.collectionList:Refresh() end
    Panel.RefreshPreview()
    refreshSwitchButton()
end

-- The switch button: asks first (the current companion rests; a running training is cancelled).
function Panel.RequestSwitch()
    local companion = AzeCaught.Companion(Panel.state.selectedUid)
    if not companion or companion == AzeCaught.Active() then return end
    local text = Format(Text["Make {name} your companion? The current one rests: its needs wait until you switch back."],
        { name = addon.Utility.Escape(AzeCaught.ShownName(companion)) })
    if addon.Arena.State().training then
        text = text .. "\n|cffff8040" .. Text["The running training is cancelled (no refund)."] .. "|r"
    end
    widgets.confirmText:SetText(text)
    Panel.state.confirmUid, Panel.state.confirmMode = companion.uid, "switch"
    widgets.confirmDialog:Show()
    AzeCaught.Journal("DEBUG", "ui.switch", "the switch dialog was opened", { uid = companion.uid })
end

-- The release button: asks first, then the companion is gone for good.
function Panel.RequestRelease()
    local companion = AzeCaught.Companion(Panel.state.selectedUid)
    if not companion then return end
    widgets.confirmText:SetText(Format(Text["Release {name} for good? Its arena progress is lost."], { name = addon.Utility.Escape(AzeCaught.ShownName(companion)) }))
    Panel.state.confirmUid, Panel.state.confirmMode = companion.uid, "release"
    widgets.confirmDialog:Show()
end

function Panel.ConfirmSwitch()
    local uid, mode = Panel.state.confirmUid, Panel.state.confirmMode
    widgets.confirmDialog:Hide()
    Panel.state.confirmUid, Panel.state.confirmMode = nil, nil
    AzeCaught.Journal("DEBUG", "ui.switch", "the dialog was confirmed", { uid = uid, mode = mode })
    if not uid then return end
    if mode == "release" then
        if AzeCaught.Release(uid) then
            Panel.state.selectedUid = nil
            addon.Catcher.PublishSoon(true)
            addon.Events.Fire("CAUGHT_CHANGED")
        end
    else
        Panel.SelectCompanion(uid)
    end
end

function Panel.CancelSwitch()
    widgets.confirmDialog:Hide()
    AzeCaught.Journal("DEBUG", "ui.switch", "the dialog was cancelled", { uid = Panel.state.confirmUid })
    Panel.state.confirmUid, Panel.state.confirmMode = nil, nil
end

---@param panel table
local function buildConfirmDialog(panel)
    local Widgets = addon.UI.Widgets
    local dialog = CreateFrame("Frame", nil, panel)
    dialog:SetAllPoints(); dialog:SetFrameLevel(panel:GetFrameLevel() + 40); dialog:EnableMouse(true); dialog:Hide()
    local dim = dialog:CreateTexture(nil, "BACKGROUND"); dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.6)
    local box = CreateFrame("Frame", nil, dialog)
    box:SetSize(260, 110); box:SetPoint("CENTER", 0, 10)
    local plate = box:CreateTexture(nil, "BORDER"); plate:SetAllPoints(); plate:SetColorTexture(0.08, 0.08, 0.1, 0.96)
    local line = box:CreateTexture(nil, "ARTWORK"); line:SetHeight(2); line:SetPoint("TOPLEFT"); line:SetPoint("TOPRIGHT")
    line:SetColorTexture(1, 0.82, 0.2, 0.8)
    widgets.confirmText = Widgets.CreateFontString(box, "GameFontHighlight", "CENTER")
    widgets.confirmText:SetPoint("TOP", 0, -14); widgets.confirmText:SetWidth(240)
    -- tick / X (the word is in the tooltip)
    local yes = Widgets.CreateIconButton(box, "accept", 28, Text["Yes"], function() Panel.ConfirmSwitch() end)
    yes:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -8, 12)
    local no = Widgets.CreateIconButton(box, "decline", 28, Text["No"], function() Panel.CancelSwitch() end)
    no:SetPoint("BOTTOMLEFT", box, "BOTTOM", 8, 12)
    widgets.confirmDialog = dialog
end

---@param panel table
local function buildCollectionView(panel)
    local Widgets = addon.UI.Widgets
    widgets.sectionButtons = {}
    for index, section in ipairs({ "caught", "seen" }) do
        local key = section
        local button = Widgets.CreateButton(panel, "", 140, 18, function() Panel.SelectSection(key) end)
        button:SetPoint("TOPLEFT", 4 + (index - 1) * 146, -24)
        widgets.sectionButtons[section] = button
    end
    widgets.collectionList = Widgets.CreateScrollList(panel, 190, Widgets.ROW_HEIGHT * 11, createCollectionRow, fillCollectionRow)
    widgets.collectionList:SetPoint("TOPLEFT", 4, -46)
    widgets.previewView = addon.ModelView.New(panel, { preset = "portrait", width = 104, height = 150, area = "preview" })
    local preview = widgets.previewView.frame
    preview:SetPoint("TOPRIGHT", -2, -46)
    widgets.previewModel = preview
    attachInfoPanel(preview, previewNpc)
    widgets.previewText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.previewText:SetPoint("TOP", preview, "BOTTOM", 0, -4); widgets.previewText:SetWidth(104)
    widgets.historyBadges = Panel.BuildHistoryBadges(panel, preview)
    -- the button column: Rename (only for a selected companion without a nickname), Make companion, Release. Each has
    -- its own slot, so nothing moves when Rename is hidden. While naming, a box with tick and cross takes the Rename
    -- slot and reaches left under the list.
    widgets.renameRowButton = Widgets.CreateButton(panel, Text["Rename"], 104, 18, function() Panel.StartRosterRename() end)
    widgets.renameRowButton:SetPoint("TOPRIGHT", -2, -258)
    widgets.renameRowButton:Hide()
    widgets.switchButton = Widgets.CreateButton(panel, Text["Make companion"], 104, 22, function() Panel.RequestSwitch() end)
    widgets.switchButton:SetPoint("TOP", widgets.renameRowButton, "BOTTOM", 0, -3)
    widgets.switchButton:SetEnabled(false)
    widgets.releaseButton = Widgets.CreateButton(panel, Text["Release"], 104, 18, function() Panel.RequestRelease() end)
    widgets.releaseButton:SetPoint("TOP", widgets.switchButton, "BOTTOM", 0, -3)
    widgets.releaseButton:SetEnabled(false)
    local editor = CreateFrame("Frame", nil, panel)
    editor:SetSize(190, 18); editor:SetPoint("TOPRIGHT", widgets.renameRowButton, "TOPRIGHT", 0, 0)
    local no = Widgets.CreateIconButton(editor, "decline", 18, Text["Cancel"], function() Panel.CancelRosterRename() end)
    no:SetPoint("RIGHT", 0, 0)
    local yes = Widgets.CreateIconButton(editor, "accept", 18, Text["Save the nickname (once)"], function() Panel.ConfirmRosterRename() end)
    yes:SetPoint("RIGHT", no, "LEFT", -3, 0)
    local box = Widgets.CreateEditBox(editor, 148)
    box:SetPoint("RIGHT", yes, "LEFT", -3, 0); box:SetJustifyH("LEFT"); box:SetAutoFocus(false)
    if box.SetMaxLetters then box:SetMaxLetters(AzeCaught.MAXIMUM_NICK_CHARACTERS) end
    box:SetScript("OnEnterPressed", function() Panel.ConfirmRosterRename() end)
    box:SetScript("OnEscapePressed", function() Panel.CancelRosterRename() end)
    box:SetScript("OnHide", function(self) self:ClearFocus() end)
    editor:Hide()
    widgets.renameEditor, widgets.renameRowBox = editor, box
    widgets.collectionStatus = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.collectionStatus:SetPoint("TOP", 0, -328); widgets.collectionStatus:SetWidth(290)
    local hint = Widgets.CreateFontString(panel, "GameFontDisableSmall", "CENTER")
    hint:SetPoint("TOP", 0, -342); hint:SetWidth(290)
    hint:SetText(Text["Every catch is its own companion: select one, then Make companion. Resting ones wait with frozen needs."])
    buildConfirmDialog(panel)
end

---@param list table
---@return table row
local function createGuildRow(list)
    local Widgets = addon.UI.Widgets
    local row = CreateFrame("Button", nil, list)
    row.hover = row:CreateTexture(nil, "BACKGROUND"); row.hover:SetAllPoints(); row.hover:SetColorTexture(1, 1, 1, 0.07); row.hover:Hide()
    row.mine = row:CreateTexture(nil, "BACKGROUND", nil, 1); row.mine:SetAllPoints(); row.mine:SetColorTexture(1, 0.8, 0.2, 0.14); row.mine:Hide()
    row.rank = Widgets.CreateFontString(row, "GameFontHighlightSmall", "RIGHT"); row.rank:SetPoint("LEFT", 0, 0); row.rank:SetWidth(18)
    row.owner = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT"); row.owner:SetPoint("LEFT", 22, 0); row.owner:SetWidth(76)
    row.level = Widgets.CreateFontString(row, "GameFontNormalSmall", "RIGHT"); row.level:SetPoint("RIGHT", -2, 0); row.level:SetWidth(88)
    row.selected = row:CreateTexture(nil, "BACKGROUND", nil, 2); row.selected:SetAllPoints(); row.selected:SetColorTexture(0.3, 0.6, 1, 0.22)
    row.selected:Hide()
    -- a click selects the pet; hovering shows its info panel (like the collection's preview)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if GameTooltip then Panel.ShowGuildNpcInfo(GameTooltip, self, self.entry) end
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide(); if GameTooltip then GameTooltip:Hide() end end)
    row:SetScript("OnClick", function(self) if self.entry then Panel.SelectGuildRow(self.entry) end end)
    return row
end

---@param row table
---@param entry CompanionRow
local function fillGuildRow(row, entry)
    row.mine:SetShown(entry.mine)
    row.selected:SetShown(Panel.state.guildRow ~= nil and Panel.state.guildRow.nameRaw == entry.nameRaw)
    row.rank:SetText(tostring(entry.rank))
    local owner = entry.nameRaw:match("^([^%-]+)") or entry.nameRaw
    row.owner:SetText(addon.Utility.Escape(owner))
    -- the TLevel (training level: NPC level + rarity + hearts, the ranking value) and the hearts in it
    row.level:SetText(("|cff999999%s|r %d |cffff4060(%+d)|r"):format(Text["TLevel"], entry.level, entry.hearts))
end

---@param panel table
local function buildGuildView(panel)
    local Widgets = addon.UI.Widgets
    widgets.guildWinner = Widgets.CreateFontString(panel, "GameFontNormalSmall", "LEFT")
    widgets.guildWinner:SetPoint("TOPLEFT", 8, -46); widgets.guildWinner:SetWidth(180)
    widgets.guildList = Widgets.CreateScrollList(panel, 190, Widgets.ROW_HEIGHT * 10, createGuildRow, fillGuildRow)
    widgets.guildList:SetPoint("TOPLEFT", 4, -62)
    widgets.guildEmpty = Widgets.CreateFontString(panel, "GameFontDisable", "CENTER")
    widgets.guildEmpty:SetPoint("TOP", widgets.guildList, "TOP", -10, -60); widgets.guildEmpty:SetWidth(170)
    widgets.guildEmpty:SetText(Text["No guild member has a companion yet."])
    widgets.guildView = addon.ModelView.New(panel, { preset = "portrait", width = 104, height = 116, area = "guild" })
    local preview = widgets.guildView.frame
    preview:SetPoint("TOPRIGHT", -2, -78)
    widgets.guildModel = preview
    -- hovering the model shows the same info panel as the collection's preview
    preview:HookScript("OnEnter", function(self)
        if GameTooltip then Panel.ShowGuildNpcInfo(GameTooltip, self, Panel.state.guildRow) end
    end)
    preview:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    -- the selected pet's name above the model, its stats as icon badges with numbers below (like the collection's caught
    -- view)
    widgets.guildPreviewName = Widgets.CreateFontString(panel, "GameFontNormal", "CENTER")
    widgets.guildPreviewName:SetPoint("BOTTOM", preview, "TOP", 0, 3); widgets.guildPreviewName:SetWidth(108)
    widgets.guildBadges = Panel.BuildStatBadges(panel, preview)
end

------------------------------------------------------------------ guild pet stats as badges

local RARITY_RGB = {}
for rarity, hex in pairs(RARITY_COLOR) do
    RARITY_RGB[rarity] = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end
local GUILD_STATS = {
    { key = "level", label = function() return Text["TLevel"] end, icon = "Interface\\Icons\\Ability_Hunter_BeastTraining", color = { 1, 0.82, 0.2 } },
    { key = "hearts", label = function() return Text["Hearts"] end, icon = "Interface\\Icons\\INV_ValentinesCandy", color = { 1, 0.25, 0.4 } },
    { key = "wins", label = function() return Text["Arena wins"] end, icon = "Interface\\Icons\\INV_Sword_27", color = { 0.35, 0.85, 0.35 } },
    { key = "losses", label = function() return Text["Arena losses"] end, icon = "Interface\\Icons\\Ability_Rogue_FeignDeath", color = { 0.9, 0.3, 0.3 } },
    { key = "hunger", label = function() return Text["Food"] end, icon = CARE_ICONS.feed, color = { 0.9, 0.6, 0.25 } },
    { key = "thirst", label = function() return Text["Water"] end, icon = CARE_ICONS.water, color = { 0.35, 0.65, 1 } },
    { key = "affection", label = function() return Text["Petting"] end, icon = CARE_ICONS.pet, color = { 1, 0.45, 0.7 } },
    { key = "energy", label = function() return Text["Energy"] end, icon = CARE_ICONS.sleep, color = { 0.6, 0.5, 1 } },
}
Panel.GUILD_STATS = GUILD_STATS

-- Eight icon badges (two rows of four) under the guild preview: level, hearts, arena wins/losses, the four needs.
---@param panel table
---@param preview table
---@return table[] badges by order, also by key
function Panel.BuildStatBadges(panel, preview)
    local Widgets = addon.UI.Widgets
    local badges = {}
    local total = 4 * BADGE_SIZE + 3 * BADGE_GAP
    for index, stat in ipairs(GUILD_STATS) do
        local column, line = (index - 1) % 4, math.floor((index - 1) / 4)
        local badge = CreateFrame("Frame", nil, panel)
        badge:SetSize(BADGE_SIZE, BADGE_SIZE)
        badge:SetPoint("TOPLEFT", preview, "BOTTOM", -total / 2 + column * (BADGE_SIZE + BADGE_GAP), -4 - line * (BADGE_SIZE + 4))
        badge.key, badge.stat = stat.key, stat
        badge.frame = badge:CreateTexture(nil, "BACKGROUND"); badge.frame:SetPoint("TOPLEFT", -1, 1); badge.frame:SetPoint("BOTTOMRIGHT", 1, -1)
        badge.icon = badge:CreateTexture(nil, "ARTWORK"); badge.icon:SetAllPoints()
        addon.UIHelpers.SetTextureOr(badge.icon, stat.icon, stat.color)
        if badge.icon.SetTexCoord then badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        badge.count = Widgets.CreateFontString(badge, "NumberFontNormalSmall", "RIGHT")
        badge.count:SetPoint("BOTTOMRIGHT", 2, -2)
        badge:EnableMouse(true)
        badge:SetScript("OnEnter", function(self)
            if not GameTooltip or not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(stat.label(), stat.color[1], stat.color[2], stat.color[3])
            for _, tipLine in ipairs(self.tip) do GameTooltip:AddLine(tipLine, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        badge:Hide()
        badges[index], badges[stat.key] = badge, badge
    end
    return badges
end

-- The badge values of a guild row: { key = { count = "short text", tip = { lines } } }.
---@param row CompanionRow
---@return table<string, { count: string, tip: string[] }>
function Panel.GuildStats(row)
    local arena = row.mine and addon.Arena.State() or (addon.Games.Get(row.nameRaw) or {}).arena
    arena = type(arena) == "table" and arena or {}
    local stats = {
        level = { count = tostring(row.level or AzeCaught.CompanionLevel(row) or 0),
            tip = { ("%s %d · %s"):format(Text["Level"], row.lvl, rarityText(row.cls)),
            Format(Text["TLevel (training level) = NPC level + rarity + hearts. Weekly pay: {first}, {second}, {third}, others {other}."],
                { first = money(AzeCaught.PAYOUTS[1]), second = money(AzeCaught.PAYOUTS[2]), third = money(AzeCaught.PAYOUTS[3]),
                  other = money(AzeCaught.PAYOUT_OTHER) }) } },
        hearts = { count = tostring(row.hearts or 0), tip = { tostring(row.hearts or 0) } },
        wins = { count = tostring(arena.w or 0), tip = { tostring(arena.w or 0) } },
        losses = { count = tostring(arena.l or 0), tip = { tostring(arena.l or 0) } },
    }
    for _, need in ipairs({ "hunger", "thirst", "affection", "energy" }) do
        local value = math.floor((tonumber(row[need]) or 0) + 0.5)
        stats[need] = { count = tostring(value), tip = { value .. "%" } }
    end
    if row.asleep then
        stats.energy.count = "Zz"
        stats.energy.tip[#stats.energy.tip + 1] = Text["asleep"]
    end
    return stats
end

------------------------------------------------------------------ the arena guide arrow

-- Like the first-throw arrow: a bobbing red arrow shows the way to the first fight, once: the Arena tab, then the
-- fight request on the Fights page. Each step ends when it is done; after the first request was sent it never shows
-- again (settings().arenaGuide = "done"). Only with a companion (no fight without one).
local GUIDE_ARROW = "Interface\\Buttons\\UI-MicroStream-Red"   -- points down
local GUIDE_FALLBACK = { 1, 0.15, 0.1, 1 }
local GUIDE_NEXT = { arena = "request", request = "done" }

-- The current guide step, or nil (done or no companion). The older steps "pet" and "fight" (the Guild view's fight
-- icon) continue at "request".
---@return "arena"|"request"|nil
function Panel.GuideStep()
    local step = settings().arenaGuide
    if step == "done" or not AzeCaught.Active() then return nil end
    return (step == "request" or step == "pet" or step == "fight") and "request" or "arena"
end

-- Moves the guide on when `step` is the current one.
---@param step "arena"|"request"
function Panel.AdvanceGuide(step)
    if Panel.GuideStep() ~= step then return end
    settings().arenaGuide = GUIDE_NEXT[step]
    AzeCaught.Journal("DEBUG", "ui.guide", "the arena guide moved on", { from = step, to = GUIDE_NEXT[step] })
    Panel.UpdateGuide()
end

---@param panel table
local function buildGuideArrow(panel)
    local holder = CreateFrame("Frame", nil, panel)
    holder:SetSize(26, 26); holder:SetFrameLevel(panel:GetFrameLevel() + 60); holder:Hide()
    holder.glow = holder:CreateTexture(nil, "OVERLAY", nil, 1)
    holder.glow:SetPoint("CENTER"); holder.glow:SetSize(42, 42)
    addon.UIHelpers.SetTextureOr(holder.glow, GUIDE_ARROW, GUIDE_FALLBACK)
    pcall(holder.glow.SetBlendMode, holder.glow, "ADD")
    holder.glow:SetVertexColor(1, 0.2, 0.1, 0.6)
    holder.arrow = holder:CreateTexture(nil, "OVERLAY", nil, 2)
    holder.arrow:SetAllPoints()
    addon.UIHelpers.SetTextureOr(holder.arrow, GUIDE_ARROW, GUIDE_FALLBACK)
    holder.time = 0
    holder:SetScript("OnUpdate", function(self, elapsedSeconds)
        if not self.target then return end
        self.time = self.time + (tonumber(elapsedSeconds) or 0)
        local wave = 0.5 + 0.5 * math.sin(self.time * 6)
        local push = 3 + 6 * wave
        self:ClearAllPoints()
        if self.side == "left" then       -- left of the target, pointing right
            self:SetPoint("RIGHT", self.target, "LEFT", -push, 0)
        elseif self.side == "right" then  -- right of the target, pointing left
            self:SetPoint("LEFT", self.target, "RIGHT", push, 0)
        else                              -- above the target, pointing down
            self:SetPoint("BOTTOM", self.target, "TOP", 0, push)
        end
        self.glow:SetAlpha(0.3 + 0.6 * wave)
    end)
    widgets.guideArrow = holder
end

-- Where the arrow points now: the frame and the side it sits on, or nil.
---@return table|nil target
---@return "above"|"left"|"right"|nil side
function Panel.GuideTarget()
    local step = Panel.GuideStep()
    if not step or not widgets.panel or not widgets.panel:IsVisible() then return nil end
    if Panel.state.view ~= "arena" then return widgets.viewButtons.arena, "above" end
    local ArenaView = addon.ArenaView
    if ArenaView.state.page ~= "fights" then return ArenaView.widgets.pageButtons.fights, "above" end
    -- the member dropdown of the fight request
    local dropdown = ArenaView.widgets.memberDropdown
    if dropdown and dropdown:IsShown() then return dropdown, "right" end
    return nil
end

-- Shows the arrow at the current step's target (or hides it).
function Panel.UpdateGuide()
    local holder = widgets.guideArrow
    if not holder then return end
    local target, side = Panel.GuideTarget()
    holder.target, holder.side = target, side
    if not target then holder:Hide() return end
    local turn = side == "left" and math.pi / 2 or side == "right" and -math.pi / 2 or 0
    for _, texture in ipairs({ holder.arrow, holder.glow }) do
        if texture.SetRotation then pcall(texture.SetRotation, texture, turn) end
    end
    holder:Show()
end

------------------------------------------------------------------ build and refresh

-- Builds the panel into `panel` (the game stage's AZEcaught panel, 300 x 376).
---@param panel table
function Panel.Build(panel)
    local Widgets = addon.UI.Widgets
    widgets.panel = panel
    widgets.views, widgets.viewButtons = {}, {}
    -- the guild list is a page of the arena
    local labels = { companion = Text["Companion"], collection = Text["Collection"], arena = Text["Arena"], shop = Text["Shop"],
        inventory = Text["Inventory"] }
    for index, view in ipairs(Panel.VIEWS) do
        local key = view
        local frame = CreateFrame("Frame", nil, panel)
        frame:SetPoint("TOPLEFT", 0, 0); frame:SetPoint("BOTTOMRIGHT", 0, 0)
        widgets.views[view] = frame
        -- an icon per tab (five text labels do not fit), the name on hover
        local button = Widgets.CreateButton(panel, "", 56, 20, function() Panel.SelectView(key) end)
        button:SetPoint("TOPLEFT", 4 + (index - 1) * 59, -1)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16); icon:SetPoint("CENTER", 0, 1); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        addon.UIHelpers.SetTextureOr(icon, VIEW_ICONS[view], { 1, 0.82, 0.2 })
        button.icon = icon
        button.tooltip = labels[view]
        button:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tooltip)
            if self.lockedText then GameTooltip:AddLine(self.lockedText, 1, 0.45, 0.35, true) end
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        widgets.viewButtons[view] = button
    end
    buildCompanionView(widgets.views.companion)
    buildCollectionView(widgets.views.collection)
    addon.ArenaView.Build(widgets.views.arena)
    buildGuildView(addon.ArenaView.widgets.guildPage)
    addon.ShopView.BuildShop(widgets.views.shop)
    addon.ShopView.BuildInventory(widgets.views.inventory)
    buildGuideArrow(panel)
    -- the bars move while the panel is visible: redraw twice a second
    local elapsedTotal = 0
    panel:SetScript("OnUpdate", function(_, elapsedSeconds)
        elapsedTotal = elapsedTotal + elapsedSeconds
        if elapsedTotal < 0.5 then return end
        elapsedTotal = 0
        if Panel.state.view == "companion" then
            addon.Log.Protected("caught.ui", "refreshing the companion failed", Panel.RefreshCompanion)
            addon.Log.Protected("caught.ui", "an idle emote failed", widgets.modelView.Tick)
        end
        if Panel.state.view == "arena" and addon.ArenaView.state.page ~= "guild" then
            addon.Log.Protected("caught.ui", "refreshing the arena failed", addon.ArenaView.Refresh)
        end
    end)
    panel:HookScript("OnShow", function()
        Panel.Refresh()
        widgets.modelView.Reload("shown")   -- the model resets on show
    end)
    Panel.state.section = settings().caughtSection == "seen" and "seen" or "caught"
    local view = settings().caughtView
    Panel.SelectView(Panel.RestorableView(view))
    Panel.SelectSection(Panel.state.section)
end

------------------------------------------------------------------ rename (a click on the companion's name)

-- A button over the name line (hover: species and catch origin; click: an edit box in its place). Enter saves,
-- Escape or a click elsewhere cancels; the box never keeps the keyboard once hidden.
---@param panel table
function Panel.BuildRename(panel)
    local Widgets = addon.UI.Widgets
    local button = CreateFrame("Button", nil, panel)
    button:SetPoint("TOP", 0, -24); button:SetSize(290, 18)
    button:SetScript("OnEnter", function(self)
        local companion = AzeCaught.Active()
        if not companion or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        Panel.ShowCompanionTooltip(GameTooltip, companion, AzeCaught.CanRename(companion) and Text["Click to give it a nickname (once)."] or nil)
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:SetScript("OnClick", function() Panel.StartRename() end)
    widgets.nameButton = button
    local box = Widgets.CreateEditBox(panel, 200)
    box:SetPoint("TOP", 0, -24); box:SetJustifyH("CENTER"); box:SetAutoFocus(false)
    if box.SetMaxLetters then box:SetMaxLetters(AzeCaught.MAXIMUM_NICK_CHARACTERS) end
    box:SetScript("OnEnterPressed", function(self)
        local uid = self.uid
        Panel.EndRename()
        if uid then addon.Catcher.Rename(uid, self:GetText() or "") end
    end)
    box:SetScript("OnEscapePressed", function() Panel.EndRename() end)
    box:HookScript("OnEditFocusLost", function() Panel.EndRename() end)
    box:SetScript("OnHide", function(self) self:ClearFocus() end)
    box:Hide()
    widgets.renameBox = box
end

function Panel.StartRename()
    local companion, box = AzeCaught.Active(), widgets.renameBox
    if not AzeCaught.CanRename(companion) or not box then return end
    if GameTooltip then GameTooltip:Hide() end
    box.uid = companion.uid
    box:SetText("")
    widgets.nameText:Hide(); widgets.nameButton:Hide()
    box:Show(); box:SetFocus(); box:HighlightText()
end

function Panel.EndRename()
    local box = widgets.renameBox
    if not box or not box:IsShown() then return end
    box.uid = nil
    box:ClearFocus(); box:Hide()
    widgets.nameButton:Show()
    widgets.nameText:SetShown(AzeCaught.Active() ~= nil)
end

function Panel.RefreshCompanion()
    if not widgets.model then return end
    local companion = AzeCaught.Active()
    local hasCompanion = companion ~= nil
    widgets.emptyCompanion:SetShown(not hasCompanion)
    for _, region in ipairs({ widgets.model, widgets.heartIcon, widgets.heartText, widgets.streakText, widgets.nameText, widgets.sleepText }) do
        region:SetShown(hasCompanion)
    end
    if widgets.renameBox and widgets.renameBox:IsShown() then
        if not hasCompanion or widgets.renameBox.uid ~= companion.uid then Panel.EndRename() else widgets.nameText:Hide() end
    end
    widgets.nameButton:SetShown(hasCompanion and not widgets.renameBox:IsShown())
    for _, bar in pairs(widgets.bars) do bar:SetShown(hasCompanion) end
    Panel.RefreshCareButtons()
    addon.ArenaView.RefreshFighter()
    widgets.modelView.Show(companion)
    if not companion then return end
    addon.UI.Widgets.FitText(widgets.nameText, ("|cff%s%s|r  |cffaaaaaa%s %d · %s|r"):format(RARITY_COLOR[companion.cls] or "ffffff",
        addon.Utility.Escape(addon.Utility.ShortText(AzeCaught.ShownName(companion), 28)), Text["Level"], companion.lvl, rarityText(companion.cls)))
    widgets.heartText:SetText((companion.hearts < 0 and "|cff993333" or "|cffff4060") .. companion.hearts .. "|r")
    widgets.streakText:SetText(Format(Text["Fed streak {fed} · care streak {care} · TLevel {rank}"],
        { fed = companion.fedStreak, care = companion.careStreak, rank = AzeCaught.CompanionLevel(companion) }))
    widgets.sleepText:SetText(companion.asleep and Format(Text["Asleep, wakes in {time}"], { time = duration(companion.asleep) }) or "")
    for _, need in ipairs(NEED_ORDER) do fillBar(widgets.bars[need], need, companion[need], companion) end
    if companion.starve > 0 then
        widgets.statusText:SetText("|cffff4040" .. Format(Text["Starving! It dies in {time}."],
            { time = duration(AzeCaught.STARVE_TIME - companion.starve) }) .. "|r")
    end
end

------------------------------------------------------------------ history badges

-- Four icon badges under the preview model: seen, killed, caught x/y, last seen. Each has its number in the corner,
-- a glow for pulses, a "+n" that floats up, and a tooltip with the label and the full value.
---@param panel table
---@param preview table the preview model
---@return table[] badges by order, also by key
function Panel.BuildHistoryBadges(panel, preview)
    local Widgets = addon.UI.Widgets
    local badges = {}
    local labels = { seen = "Seen", kills = "Killed", caught = "Caught", last = "Last seen" }
    local total = 4 * BADGE_SIZE + 3 * BADGE_GAP
    for index, key in ipairs({ "seen", "kills", "caught", "last" }) do
        local badge = CreateFrame("Frame", nil, panel)
        badge:SetSize(BADGE_SIZE, BADGE_SIZE)
        badge:SetPoint("TOPLEFT", preview, "BOTTOM", -total / 2 + (index - 1) * (BADGE_SIZE + BADGE_GAP), -30)
        badge.key = key
        local color = HISTORY_COLOR[key]
        badge.frame = badge:CreateTexture(nil, "BACKGROUND"); badge.frame:SetPoint("TOPLEFT", -1, 1); badge.frame:SetPoint("BOTTOMRIGHT", 1, -1)
        badge.frame:SetColorTexture(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6, 0.9)
        badge.icon = badge:CreateTexture(nil, "ARTWORK"); badge.icon:SetAllPoints()
        addon.UIHelpers.SetTextureOr(badge.icon, HISTORY_ICONS[key], color)
        if badge.icon.SetTexCoord then badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        badge.glow = badge:CreateTexture(nil, "OVERLAY"); badge.glow:SetPoint("CENTER"); badge.glow:SetSize(BADGE_SIZE * 1.9, BADGE_SIZE * 1.9)
        addon.UIHelpers.SetTextureOr(badge.glow, "Interface\\Buttons\\UI-ActionButton-Border", color)
        if badge.glow.SetBlendMode then badge.glow:SetBlendMode("ADD") end
        badge.glow:SetVertexColor(color[1], color[2], color[3]); badge.glow:SetAlpha(0); badge.glow:Hide()
        badge.count = Widgets.CreateFontString(badge, "NumberFontNormalSmall", "RIGHT")
        badge.count:SetPoint("BOTTOMRIGHT", 2, -2)
        badge.float = Widgets.CreateFontString(panel, "GameFontNormalSmall", "CENTER"); badge.float:Hide()
        badge:EnableMouse(true)
        badge:SetScript("OnEnter", function(self)
            if not GameTooltip or not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(Text[labels[key]], color[1], color[2], color[3])
            for _, tipLine in ipairs(self.tip) do GameTooltip:AddLine(tipLine, 1, 1, 1) end
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        badge:Hide()
        badges[index], badges[key] = badge, badge
    end
    return badges
end

-- Counts a badge's number up from `from` to `to` (an animation over 0.45 s), keeping its suffix ("/3").
---@param badge table
---@param from integer
---@param to integer
---@param suffix string
local function countUp(badge, from, to, suffix)
    if from == to then badge.count:SetText(to .. suffix) return end
    addon.Animate.Tween("badge:" .. badge.key, 0.45, function(elapsed)
        local progress = math.min(1, elapsed / 0.45)
        badge.count:SetText(math.floor(from + (to - from) * (1 - (1 - progress) ^ 2) + 0.5) .. suffix)
    end, function() badge.count:SetText(to .. suffix) end)
end

-- Shows the badges for `entry` (nil hides them). A new NPC: the badges fade in one after another and count up from
-- 0. The same NPC with a higher value (a kill while the panel is open): that badge pulses, glows and floats "+n".
---@param npcID integer|nil
---@param entry CollectionEntry|nil
---@return string|nil mode "new", "same" or nil (tests)
function Panel.ShowHistoryBadges(npcID, entry)
    local badges = widgets.historyBadges
    if not badges then return nil end
    if not entry then
        for _, badge in ipairs(badges) do badge:Hide() end
        Panel.state.badgeNpc, Panel.state.badgeValues = nil, nil
        return nil
    end
    local history = AzeCaught.History(entry)
    local list = addon.Model.HistoryBadges(history, addon.Utility.Now())
    local isNew = Panel.state.badgeNpc ~= npcID
    local previous = (not isNew and Panel.state.badgeValues) or {}
    local values = {}
    local timeAgo = addon.UI.Widgets.TimeAgo
    for index, data in ipairs(list) do
        local badge = badges[data.key]
        badge.tip = data.key == "seen" and { Format(Text["{n} times"], { n = history.seen }), Text["First seen"] .. ": " .. timeAgo(history.first) }
            or data.key == "kills" and { tostring(history.kills) }
            or data.key == "caught" and { Format(Text["Caught {x}/{y}"], { x = history.caught, y = history.throws }) }
            or { timeAgo(history.last) }
        if badge.icon.SetDesaturated then badge.icon:SetDesaturated(data.empty) end
        badge.icon:SetAlpha(data.empty and 0.45 or 1)
        values[data.key] = data.value
        local suffix = data.key == "caught" and ("/" .. history.throws) or ""
        if data.value == nil then
            badge.count:SetText(data.text)
        elseif isNew then
            countUp(badge, 0, data.value, suffix)
        else
            local before = previous[data.key] or data.value
            countUp(badge, before, data.value, suffix)
            if data.value > before then
                addon.Animate.Pulse(badge, 1.35, 0.35)
                addon.Animate.Flash("badge:" .. data.key, badge.glow, 0.9, 0.6)
                addon.Animate.FloatText("badge:" .. data.key, badge.float, badge, 0, 8, "+" .. (data.value - before), HISTORY_COLOR[data.key], 22, 1)
            end
        end
        if isNew then
            badge:SetAlpha(0)
            addon.Animate.FadeIn(badge, 0.15 + 0.08 * index)
        else
            badge:Show()
        end
    end
    Panel.state.badgeNpc, Panel.state.badgeValues = npcID, values
    return isNew and "new" or "same"
end

function Panel.RefreshPreview()
    local entry = Panel.state.previewNpc and AzeCaught.State().collection[Panel.state.previewNpc]
    if not entry then
        widgets.previewView.Show(nil) widgets.previewText:SetText("")
        Panel.ShowHistoryBadges(nil, nil)
        return
    end
    -- a caught companion shows its own look (an NPC can be male or female), a found NPC the look it was seen with
    local companion = AzeCaught.Companion(Panel.state.previewUid)
    local display = companion and companion.npc == Panel.state.previewNpc and (tonumber(companion.disp) or 0) > 0 and companion.disp or entry.disp
    widgets.previewView.Show({ npc = Panel.state.previewNpc, disp = display })
    widgets.previewText:SetText(("%s\n%s %d · %s"):format(addon.Utility.Escape(addon.Utility.ShortText(entry.n, 20)), Text["Level"], entry.lvl, rarityText(entry.cls)))
    Panel.ShowHistoryBadges(Panel.state.previewNpc, entry)
end

function Panel.RefreshGuildPreview()
    local row = Panel.state.guildRow
    if not row then
        widgets.guildView.Show(nil) widgets.guildPreviewName:SetText("")
        for _, badge in ipairs(widgets.guildBadges) do badge:Hide() end
        Panel.state.guildBadgeOwner = nil
        return
    end
    widgets.guildView.Show({ npc = row.npc, disp = row.disp })
    -- the name on top (rarity colour), the stats as badges (arena wins/losses: mine local, others from their record)
    addon.UI.Widgets.FitText(widgets.guildPreviewName, ("|cff%s%s|r"):format(RARITY_COLOR[row.cls] or "ffffff", row.companion), 0.7)
    local isNew = Panel.state.guildBadgeOwner ~= row.nameRaw
    Panel.state.guildBadgeOwner = row.nameRaw
    local stats = Panel.GuildStats(row)
    for index, badge in ipairs(widgets.guildBadges) do
        local stat = stats[badge.key]
        badge.count:SetText(stat.count); badge.tip = stat.tip
        local edge = badge.key == "level" and RARITY_RGB[row.cls] or badge.stat.color
        badge.frame:SetColorTexture(edge[1] * 0.6, edge[2] * 0.6, edge[3] * 0.6, 0.9)
        local faded = badge.key == "energy" and row.asleep
        if badge.icon.SetDesaturated then badge.icon:SetDesaturated(faded) end
        badge.icon:SetAlpha(faded and 0.55 or 1)
        if isNew then badge:SetAlpha(0); addon.Animate.FadeIn(badge, 0.1 + 0.04 * index) else badge:Show() end
    end
end

-- Selects a guild row (a click).
---@param row CompanionRow
function Panel.SelectGuildRow(row)
    Panel.state.guildRow = row
    Panel.Refresh()
end

-- Redraws the visible view (CAUGHT_CHANGED, GAMES_CHANGED, DATA_CHANGED and on show).
function Panel.Refresh()
    if not widgets.views then return end
    Panel.RefreshView()
    Panel.UpdateGuide()
end

function Panel.RefreshView()
    local view = Panel.state.view
    if view == "companion" then
        Panel.RefreshCompanion()
    elseif view == "arena" then
        addon.ArenaView.Refresh()
    elseif view == "shop" or view == "inventory" then
        addon.ShopView.Refresh(view)
    elseif view == "collection" then
        local caught = AzeCaught.State()
        local active = caught.active
        local sections = addon.Model.BuildCollectionSections(caught.collection, active and active.npc)
        sections.caught = addon.Model.BuildRosterRows(AzeCaught.Roster(), caught.collection, active)
        widgets.sectionButtons.caught:SetLabel(Format(Text["Caught ({n})"], { n = #sections.caught }))
        widgets.sectionButtons.seen:SetLabel(Format(Text["Seen {n}"], { n = #sections.seen }))
        local rows = sections[Panel.state.section] or sections.caught
        widgets.collectionList:SetData(rows)
        if not Panel.state.previewNpc and rows[1] then Panel.state.previewNpc, Panel.state.previewUid = rows[1].npc, rows[1].uid end
        Panel.RefreshPreview()
        refreshSwitchButton()
    end
end

-- The arena's Guild page: every member's companion, the selected one in the preview (ArenaView.Refresh calls it).
function Panel.RefreshGuild()
    if not widgets.guildList then return end
    do
        local now = addon.Utility.Now()
        local records = addon.Games.AllRecords()
        local rows = addon.Model.BuildCompanionRows(records, me())
        -- keep the selected pet (by owner, with its fresh row), else the first
        local selectedName = Panel.state.guildRow and Panel.state.guildRow.nameRaw
        Panel.state.guildRow = rows[1]
        for _, row in ipairs(rows) do if row.nameRaw == selectedName then Panel.state.guildRow = row end end
        widgets.guildList:SetData(rows)
        widgets.guildEmpty:SetShown(#rows == 0)
        local winner = addon.Model.CompanionWinner(addon.Store.db.games, addon.Games.PreviousPeriodKey(now), me())
        widgets.guildWinner:SetText(winner and Format(Text["Last week's best: {name} (TLevel {level})"], { name = winner.name, level = winner.peak }) or "")
        Panel.RefreshGuildPreview()
    end
end

addon.Events.On("CAUGHT_CHANGED", function()
    Panel.UpdateViewLocks()
    if widgets.panel and widgets.panel:IsVisible() then Panel.Refresh() end
end)
local function guildShown() return widgets.panel and widgets.panel:IsVisible() and Panel.state.view == "arena" and addon.ArenaView.state.page == "guild" end
addon.Events.On("GAMES_CHANGED", function() if guildShown() then Panel.Refresh() end end)
addon.Events.On("DATA_CHANGED", function() if guildShown() then Panel.Refresh() end end)
