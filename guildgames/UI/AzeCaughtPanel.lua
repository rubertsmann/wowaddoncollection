local addonName, addon = ...

-- The AZEcaught game panel (feature 018, R6-R9, R11, R12, R16): three views in the 300 x 336 game stage.
--   Companion   the 3D model, hearts, need bars with threshold marks, the care buttons and their effects
--   Collection  every found NPC (caught ones first), a model preview, click a caught one to make it the companion
--   Guild       every member's current companion as a leaderboard (companion level), with a preview of the selected one
-- Logic lives in Core/Minigames/AzeCaught.lua; this file only shows it and calls it. Model loading and emotes are journaled
-- (spikes S1/S2), so a white or missing model can be traced with /gg caught log model.
---@class AzeCaughtPanelModule
local Panel = {}
addon.AzeCaughtPanel = Panel

local AzeCaught = addon.AzeCaught
local Text, Format = addon.Text, addon.Locale.Format

local HEART_ICON = "Interface\\Icons\\INV_ValentinesCandy"
local ZONE_COLOR = { ok = { 0.3, 0.85, 0.35 }, needy = { 1, 0.75, 0.15 }, critical = { 1, 0.25, 0.2 }, empty = { 0.6, 0.1, 0.1 } }
local ACTION_COLOR = { feed = { 1, 0.6, 0.2 }, water = { 0.3, 0.65, 1 }, pet = { 1, 0.45, 0.75 }, sleep = { 0.65, 0.5, 1 }, wake = { 1, 1, 0.6 } }
-- emote animation candidates per action; the first the model has is played (spike S2: /gg caught probe lists them)
local EMOTES = { feed = { 61, 74, 0 }, water = { 61, 0 }, pet = { 68, 67, 70, 74, 0 }, sleep = { 71, 100, 0 }, wake = { 4, 74, 0 },
    idle = { 0 }, asleep = { 71, 100, 0 } }
local RARITY_COLOR = { normal = "ffffff", elite = "ffd100", rare = "c0c0c0", rareelite = "a335ee", worldboss = "ff8000" }
local NEED_ORDER = AzeCaught.NEEDS
local CARE_COOLDOWN = 1.5    -- seconds the care buttons stay locked after a click (user 2026-11-20)
local CARE_ICON_SIZE = 34
local CARE_ICONS = { feed = "Interface\\Icons\\INV_Misc_Food_15", water = "Interface\\Icons\\INV_Drink_07",
    pet = "Interface\\Icons\\Ability_Hunter_BeastSoothe", sleep = "Interface\\Icons\\Spell_Nature_Sleep",
    wake = "Interface\\Icons\\Ability_Warrior_BattleShout" }
local EMOTE_SECONDS = 2.5   -- an action's emote plays this long, then the model goes back to idle (user 2026-11-20)
-- per model: a counter that voids older "back to idle" timers (kept off the frame itself)
local emoteTokens = setmetatable({}, { __mode = "k" })
---@param model table
---@return integer the new token
local function nextEmoteToken(model)
    emoteTokens[model] = (emoteTokens[model] or 0) + 1
    return emoteTokens[model]
end
local BAR_WIDTH = 170

---@class AzeCaughtPanelState
---@field view "companion"|"collection"|"guild"
---@field previewNpc integer|nil collection preview
---@field guildRow CompanionRow|nil guild preview
---@field confirmNpc integer|nil a switch that makes the old companion run away waits for a second click
---@field confirmUntil number
Panel.state = { view = "companion", section = "caught" }

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
    if refusal == "funds" then return Format(Text["Not enough money in the pool ({gold})."], { gold = money(addon.Wallet.Balance(me())) }) end
    if refusal == "asleep" then return Text["It is asleep. Wake it first."] end
    if refusal == "full" then return Text["It does not need that right now."] end
    if refusal == "awake" then return Text["It is already awake."] end
    if refusal == "readonly" then return Text["Saved data is read-only in this session."] end
    return Text["No companion. Catch an NPC and pick it in the collection."]
end

---@param seconds number
---@return string
local function duration(seconds)
    if seconds == math.huge then return "-" end
    local minutes = math.max(0, math.floor(seconds / 60))
    if minutes >= 60 then return Format(Text["{h}h {m}m"], { h = math.floor(minutes / 60), m = minutes % 60 }) end
    return Format(Text["{m}m"], { m = minutes })
end

------------------------------------------------------------------ 3D model (fpvcigarette's method, feature 018 design)

---@param model table DressUpModel
---@param companion { npc: integer, disp: integer }|nil
---@param area string journal area
local function showModel(model, companion, area)
    if not model then return end
    if not companion then pcall(model.ClearModel, model) model.shownKey = nil return end
    local key = tostring(companion.npc) .. ":" .. tostring(companion.disp)
    if model.shownKey == key then return end
    model.shownKey = key
    pcall(model.ClearModel, model)
    local ok, problem, method = false, nil, nil
    if (companion.disp or 0) > 0 then
        ok, problem = pcall(model.SetDisplayInfo, model, companion.disp)
        method = "display"
    end
    if not ok and model.SetCreature then
        ok, problem = pcall(model.SetCreature, model, companion.npc)
        method = "creature"
    end
    pcall(model.SetFacing, model, 0.4)
    if ok and model.idleFunction then model.idleFunction(model, "set") end
    AzeCaught.Journal(ok and "DEBUG" or "WARNING", "model." .. area, ok and "a model was loaded" or "a model could not be loaded",
        { npc = companion.npc, display = companion.disp, method = method or "none", error = problem and tostring(problem) or nil })
end

-- Plays the first animation of `candidates` the model has (HasAnimation when the client offers it).
---@param model table
---@param candidates integer[]
---@param reason string
local function playEmote(model, candidates, reason)
    if not model or not model.SetAnimation then return end
    local chosen = candidates[#candidates]
    if model.HasAnimation then
        for _, animationId in ipairs(candidates) do
            local ok, has = pcall(model.HasAnimation, model, animationId)
            if ok and has then chosen = animationId break end
        end
    else
        chosen = candidates[1]
    end
    local ok, problem = pcall(model.SetAnimation, model, chosen)
    AzeCaught.Journal(ok and "DEBUG" or "WARNING", "model.emote", ok and "an animation was played" or "an animation failed",
        { reason = reason, animation = chosen, hasCheck = model.HasAnimation ~= nil, error = problem and tostring(problem) or nil })
end

-- The idle pose of the companion model: the sleep animation while it sleeps, else the stand (0).
---@param model table
---@param reason string
function Panel.IdleOfCompanion(model, reason)
    local companion = AzeCaught.Active()
    local asleep = companion ~= nil and companion.asleep ~= nil
    model.asleepShown = asleep
    playEmote(model, asleep and EMOTES.asleep or EMOTES.idle, "idle:" .. reason)
end

---@param model table
---@param reason string
local function previewIdle(model, reason) playEmote(model, EMOTES.idle, "idle:" .. reason) end

-- `idleFunction(model, reason)` runs whenever the model has (re)loaded: a model resets its animation on load, and an
-- animation set before an asynchronous load finishes is lost.
---@param model table
---@param idleFunction fun(model: table, reason: string)
function Panel.PrepareModel(model, idleFunction)
    model.idleFunction = idleFunction
    pcall(model.SetScript, model, "OnModelLoaded", function(self)
        if self.idleFunction then self.idleFunction(self, "loaded") end
    end)
end

-- The companion model back to idle now (the menu shows, a view switches back).
---@param reason string
function Panel.ShowIdle(reason)
    if widgets.model then
        nextEmoteToken(widgets.model)   -- a pending "after action" timer is void
        Panel.IdleOfCompanion(widgets.model, reason)
    end
end

---@param parent table
---@param width number
---@param height number
---@param idleFunction fun(model: table, reason: string)
---@return table model
local function createModel(parent, width, height, idleFunction)
    local model = CreateFrame("DressUpModel", nil, parent)
    model:SetSize(width, height)
    if model.SetKeepModelOnHide then model:SetKeepModelOnHide(true) end
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then self.turnFrom = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(self) self.turnFrom = nil end)
    Panel.PrepareModel(model, idleFunction or previewIdle)
    model:SetScript("OnUpdate", function(self)
        if not self.turnFrom then return end
        local cursorX = GetCursorPosition()
        pcall(self.SetFacing, self, (self:GetFacing() or 0) + (cursorX - self.turnFrom) * 0.02)
        self.turnFrom = cursorX
    end)
    return model
end

------------------------------------------------------------------ need bars

---@param parent table
---@param y number
---@return table bar
local function createBar(parent, y)
    local Widgets = addon.UI.Widgets
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(286, 14); bar:SetPoint("TOPLEFT", 8, y)
    bar.label = Widgets.CreateFontString(bar, "GameFontNormalSmall", "LEFT")
    bar.label:SetPoint("LEFT", 0, 0); bar.label:SetWidth(60)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetSize(BAR_WIDTH, 10); track:SetPoint("LEFT", 62, 0); track:SetColorTexture(0, 0, 0, 0.55)
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
    bar:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.need then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(needLabel(self.need))
        GameTooltip:AddLine(self.tooltipText or "", 1, 1, 1, true)
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
    bar.need = need
    bar.label:SetText(needLabel(need))
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

---@param view "companion"|"collection"|"guild"
function Panel.SelectView(view)
    Panel.state.view = view
    settings().caughtView = view
    for key, frame in pairs(widgets.views or {}) do frame:SetShown(key == view) end
    for key, button in pairs(widgets.viewButtons or {}) do
        button:SetEnabled(key ~= view)
        if button.SetSelected then button:SetSelected(key == view) end
    end
    AzeCaught.Journal("DEBUG", "ui.view", "a view was selected", { view = view })
    Panel.Refresh()
end

-- A care button's click: ignored during the click cooldown, else the action (Sleep turns into Wake while asleep).
---@param key "feed"|"water"|"pet"|"sleep"
function Panel.ClickCare(key)
    local clock = addon.Api.Clock()
    if clock < (Panel.state.careReadyAt or 0) then
        AzeCaught.Journal("DEBUG", "ui.cooldown", "a care click came during the cooldown", { action = key,
            left = math.floor((Panel.state.careReadyAt - clock) * 10) / 10 })
        return
    end
    local companion = AzeCaught.Active()
    local action = (key == "sleep" and companion and companion.asleep) and "wake" or key
    Panel.state.careReadyAt = clock + CARE_COOLDOWN
    for _, button in pairs(widgets.careButtons or {}) do
        if button.cooldown then pcall(button.cooldown.SetCooldown, button.cooldown, clock, CARE_COOLDOWN) end
    end
    Panel.Care(action)
    Panel.RefreshCareButtons()
    if C_Timer then C_Timer.After(CARE_COOLDOWN + 0.05, function() Panel.RefreshCareButtons() end) end
end

-- Icons, prices and greyed-out state of the care buttons (AzeCaught.CareAvailability; the cooldown greys them too).
function Panel.RefreshCareButtons()
    if not widgets.careButtons then return end
    local companion = AzeCaught.Active()
    local coolingDown = addon.Api.Clock() < (Panel.state.careReadyAt or 0)
    for key, button in pairs(widgets.careButtons) do
        local action = (key == "sleep" and companion and companion.asleep) and "wake" or key
        local usable, reason = AzeCaught.CareAvailability(action, me())
        careState[key] = { action = action, unusable = not usable and reason or nil }
        addon.UIHelpers.SetTextureOr(button.icon, CARE_ICONS[action], ACTION_COLOR[action] or { 1, 1, 1 })
        local enabled = usable and not coolingDown
        button:SetEnabled(enabled)
        pcall(button.icon.SetDesaturated, button.icon, not enabled)
        button.icon:SetAlpha(enabled and 1 or 0.4)
        local price = action == "feed" and AzeCaught.FOOD_PRICE or action == "water" and AzeCaught.WATER_PRICE or nil
        button.price:SetText(price and money(price) or (action == "wake" and Text["Wake"] or Text["free"]))
        button.price:SetAlpha(enabled and 1 or 0.5)
    end
end

-- care button -> AzeCaught.Care + effects
---@param action CareAction
function Panel.Care(action)
    local result, refusal = AzeCaught.Care(action, me(), addon.Utility.Now())
    if not result then
        widgets.statusText:SetText("|cffff5555" .. careRefusalText(refusal) .. "|r")
        return
    end
    local color = ACTION_COLOR[action] or { 1, 1, 1 }
    addon.Animate.Burst("care", widgets.companionView, widgets.model, 0, -20, { count = 18, color = color, speed = 120, duration = 1 })
    if result.hearts > 0 then
        addon.Animate.FloatText("hearts", widgets.floatText, widgets.model, 0, 10, "+" .. result.hearts .. " " .. Text["hearts"], { 1, 0.3, 0.4 })
        addon.Animate.Pulse(widgets.heartIcon, 1.5, 0.4)
    end
    local model = widgets.model
    playEmote(model, EMOTES[action] or EMOTES.idle, action)
    -- back to idle when the emote is over; a newer action (or the menu showing) voids this timer
    local token = nextEmoteToken(model)
    if C_Timer then
        C_Timer.After(EMOTE_SECONDS, function()
            if widgets.model == model and emoteTokens[model] == token then Panel.IdleOfCompanion(model, "afterAction") end
        end)
    end
    addon.Api.PlaySound(addon.Api.SoundKitFor({ "IG_MAINMENU_OPTION_CHECKBOX_ON" }))
    widgets.statusText:SetText(result.cost > 0 and Format(Text["Paid {gold}."], { gold = money(result.cost) }) or "")
    addon.Catcher.PublishSoon(true)
    addon.Events.Fire("CAUGHT_CHANGED")
end

-- Makes `npcId` the companion (after the confirm dialog, see Panel.RequestSwitch).
---@param npcId integer
function Panel.SelectCompanion(npcId)
    local companion, refusal, ranAway = AzeCaught.Select(npcId, addon.Utility.Now())
    if not companion then
        widgets.collectionStatus:SetText(refusal == "notcaught" and Text["Only caught NPCs can be your companion."] or "")
        return
    end
    if ranAway then addon.Print(Format(Text["{name} ran away."], { name = addon.Utility.ChatSafe(ranAway.name) })) end
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
---@return number r
---@return number g
---@return number b
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
---@param npcId integer
---@param entry CollectionEntry
---@return integer lines
function Panel.ShowNpcInfo(tooltip, owner, npcId, entry)
    local info = addon.Model.BuildNpcInfo(npcId, entry)
    local count = 0
    local function line(...) tooltip:AddLine(...) count = count + 1 end
    local function double(...) tooltip:AddDoubleLine(...) count = count + 1 end
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local r, g, b = hexColor(info.rarityColor)
    tooltip:SetText(info.title, r, g, b)
    line(info.subtitle, 0.75, 0.75, 0.75)
    if #info.facts > 0 or info.hiddenCount > 0 then
        line(" ")
        for _, fact in ipairs(info.facts) do double(fact.label, fact.value, 0.65, 0.65, 0.65, 1, 1, 1) end
        if info.hiddenCount > 0 then
            line(addon.Locale.Plural(info.hiddenCount, Text["The game hides 1 more value."], Text["The game hides {n} more values."]),
                0.5, 0.5, 0.5)
        end
    end
    line(" ")
    line(Text["Combat"], 1, 0.82, 0)
    for _, stat in ipairs(info.combat) do double(stat.label, stat.value .. " " .. Panel.StatBar(stat), 0.65, 0.65, 0.65, 1, 1, 1) end
    line(" ")
    line(Text["Needs"], 1, 0.82, 0)
    for _, need in ipairs(info.needs) do
        local color = TREND_COLOR[need.trend]
        local marker = need.trend == "more" and (" " .. Text["(more often)"]) or need.trend == "less" and (" " .. Text["(less often)"]) or ""
        double("|T" .. NEED_ICON[need.need] .. ":14:14:0:0:64:64:5:59:5:59|t " .. need.label, need.text .. marker,
            1, 1, 1, color[1], color[2], color[3])
    end
    line(info.thresholds, 0.65, 0.65, 0.65)
    if #info.traits > 0 then
        line(" ")
        line(Text["Traits"], 1, 0.82, 0)
        for _, trait in ipairs(info.traits) do line(trait, 0.85, 0.85, 0.85, true) end
    end
    tooltip:Show()
    return count
end

-- Shows the info panel while the mouse is over `model`. `getNpc()` returns npcId, collection entry (or nil: nothing).
---@param model table
---@param getNpc fun(): integer|nil, CollectionEntry|nil
local function attachInfoPanel(model, getNpc)
    model:HookScript("OnEnter", function(self)
        local npcId, entry = getNpc()
        if not entry or not GameTooltip then return end
        Panel.ShowNpcInfo(GameTooltip, self, npcId, entry)
        AzeCaught.Journal("DEBUG", "ui.info", "the NPC info panel was shown", { npc = npcId, stats = AzeCaught.StatsText(entry.st) })
    end)
    model:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

---@return integer|nil npcId
---@return CollectionEntry|nil
local function companionNpc()
    local companion = AzeCaught.Active()
    if not companion then return nil, nil end
    return companion.npc, AzeCaught.State().collection[companion.npc]
end

---@return integer|nil npcId
---@return CollectionEntry|nil
local function previewNpc()
    local npcId = Panel.state.previewNpc
    return npcId, npcId and AzeCaught.State().collection[npcId] or nil
end
Panel.CompanionNpc, Panel.PreviewNpc = companionNpc, previewNpc

---@param panel table
local function buildCompanionView(panel)
    local Widgets = addon.UI.Widgets
    widgets.companionView = panel
    local model = createModel(panel, 300, 150, Panel.IdleOfCompanion)
    model:SetPoint("TOP", 0, -24)
    widgets.model = model
    attachInfoPanel(model, companionNpc)
    widgets.nameText = Widgets.CreateFontString(panel, "GameFontNormal", "CENTER")
    widgets.nameText:SetPoint("TOP", 0, -26); widgets.nameText:SetWidth(290)
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

    widgets.bars = {}
    for index, need in ipairs(NEED_ORDER) do widgets.bars[need] = createBar(panel, -204 - (index - 1) * 18) end

    -- care buttons: icons (user 2026-11-20), greyed out while unusable (AzeCaught.CareAvailability, the reason is in the
    -- tooltip) and locked for CARE_COOLDOWN after a click (a cooldown sweep shows it)
    widgets.careButtons = {}
    for index, action in ipairs({ "feed", "water", "pet", "sleep" }) do
        local key = action
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(CARE_ICON_SIZE, CARE_ICON_SIZE)
        button:SetPoint("TOPLEFT", 36 + (index - 1) * 64, -276)
        local icon = button:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.icon = icon
        local border = button:CreateTexture(nil, "BACKGROUND"); border:SetPoint("TOPLEFT", -2, 2); border:SetPoint("BOTTOMRIGHT", 2, -2)
        border:SetColorTexture(0, 0, 0, 0.85)
        local highlight = button:CreateTexture(nil, "HIGHLIGHT"); highlight:SetAllPoints(); highlight:SetColorTexture(1, 1, 1, 0.2)
        button.price = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
        button.price:SetPoint("TOP", button, "BOTTOM", 0, -1); button.price:SetWidth(60)
        local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
        if ok and cooldown then cooldown:SetAllPoints(); button.cooldown = cooldown end
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnClick", function() Panel.ClickCare(key) end)
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local state = careState[key] or {}
            local shown = state.action or key
            if shown == "feed" then GameTooltip:SetText(Format(Text["Feed for {gold}"], { gold = money(AzeCaught.FOOD_PRICE) }))
            elseif shown == "water" then GameTooltip:SetText(Format(Text["Water for {gold}"], { gold = money(AzeCaught.WATER_PRICE) }))
            elseif shown == "pet" then GameTooltip:SetText(Text["Petting is free."])
            elseif shown == "wake" then GameTooltip:SetText(Text["Wake"])
            else GameTooltip:SetText(Format(Text["Sleeps {time}; refills energy."], { time = duration(AzeCaught.SLEEP_DURATION) })) end
            if state.unusable then GameTooltip:AddLine(careRefusalText(state.unusable), 1, 0.4, 0.4, true) end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        widgets.careButtons[action] = button
    end
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
        if self.entry then Panel.state.previewNpc = self.entry.npc; Panel.RefreshPreview() end
    end)
    row.selected = row:CreateTexture(nil, "BACKGROUND", nil, 2); row.selected:SetAllPoints(); row.selected:SetColorTexture(0.3, 0.6, 1, 0.22); row.selected:Hide()
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    -- a click selects the row (preview + the switch button); switching needs the button and its confirm dialog
    row:SetScript("OnClick", function(self) if self.entry then Panel.SelectRow(self.entry.npc) end end)
    return row
end

---@param row table
---@param entry CollectionRow
local function fillCollectionRow(row, entry)
    row.active:SetShown(entry.active)
    row.selected:SetShown(entry.npc == Panel.state.selectedNpc)
    local color = entry.caught > 0 and (RARITY_COLOR[entry.cls] or "ffffff") or "777777"
    row.name:SetText("|cff" .. color .. entry.name .. "|r")
    row.info:SetText((entry.caught > 1 and ("x" .. entry.caught .. " ") or "") .. "|cffaaaaaa" .. entry.lvl .. "|r")
end

------------------------------------------------------------------ collection: sections, selection, switching

-- "caught" (at most MAXIMUM_CAUGHT) or "seen" (every enemy fought, with its highest level)
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

-- The switch button is usable for a caught NPC that is not the companion already.
local function refreshSwitchButton()
    if not widgets.switchButton then return end
    local npcId = Panel.state.selectedNpc
    local entry = npcId and AzeCaught.State().collection[npcId]
    local active = AzeCaught.Active()
    widgets.switchButton:SetEnabled(entry ~= nil and (entry.caught or 0) > 0 and not (active and active.npc == npcId))
end

---@param npcId integer
function Panel.SelectRow(npcId)
    Panel.state.selectedNpc, Panel.state.previewNpc = npcId, npcId
    local entry = AzeCaught.State().collection[npcId]
    widgets.collectionStatus:SetText(entry and (entry.caught or 0) < 1 and Text["Only caught NPCs can be your companion."] or "")
    if widgets.collectionList then widgets.collectionList:Refresh() end
    Panel.RefreshPreview()
    refreshSwitchButton()
end

-- The switch button: asks first ("Stats will be reset"; a companion with negative hearts runs away).
function Panel.RequestSwitch()
    local npcId = Panel.state.selectedNpc
    local entry = npcId and AzeCaught.State().collection[npcId]
    if not entry or (entry.caught or 0) < 1 then return end
    local text = Format(Text["Make {name} your companion? Stats will be reset."], { name = addon.Utility.Escape(entry.n) })
    local current = AzeCaught.Active()
    if current and current.hearts < 0 then
        text = text .. "\n|cffff8040" .. Format(Text["{name} has negative hearts and will run away."],
            { name = addon.Utility.Escape(current.n) }) .. "|r"
    end
    widgets.confirmText:SetText(text)
    Panel.state.confirmNpc = npcId
    widgets.confirmDialog:Show()
    AzeCaught.Journal("DEBUG", "ui.switch", "the switch dialog was opened", { npc = npcId })
end

function Panel.ConfirmSwitch()
    local npcId = Panel.state.confirmNpc
    widgets.confirmDialog:Hide()
    Panel.state.confirmNpc = nil
    AzeCaught.Journal("DEBUG", "ui.switch", "the switch was confirmed", { npc = npcId })
    if npcId then Panel.SelectCompanion(npcId) end
end

function Panel.CancelSwitch()
    widgets.confirmDialog:Hide()
    AzeCaught.Journal("DEBUG", "ui.switch", "the switch was cancelled", { npc = Panel.state.confirmNpc })
    Panel.state.confirmNpc = nil
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
    local yes = Widgets.CreateButton(box, Text["Yes"], 90, 22, function() Panel.ConfirmSwitch() end)
    yes:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -6, 12)
    if Widgets.MakePrimary then Widgets.MakePrimary(yes) end
    local no = Widgets.CreateButton(box, Text["No"], 90, 22, function() Panel.CancelSwitch() end)
    no:SetPoint("BOTTOMLEFT", box, "BOTTOM", 6, 12)
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
    local preview = createModel(panel, 104, 150)
    preview:SetPoint("TOPRIGHT", -2, -46)
    widgets.previewModel = preview
    attachInfoPanel(preview, previewNpc)
    widgets.previewText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.previewText:SetPoint("TOP", preview, "BOTTOM", 0, -4); widgets.previewText:SetWidth(104)
    widgets.switchButton = Widgets.CreateButton(panel, Text["Make companion"], 104, 22, function() Panel.RequestSwitch() end)
    widgets.switchButton:SetPoint("TOPRIGHT", -2, -246)
    widgets.switchButton:SetEnabled(false)
    widgets.collectionStatus = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.collectionStatus:SetPoint("TOP", 0, -292); widgets.collectionStatus:SetWidth(290)
    local hint = Widgets.CreateFontString(panel, "GameFontDisableSmall", "CENTER")
    hint:SetPoint("TOP", 0, -314); hint:SetWidth(290)
    hint:SetText(Text["Select a caught NPC, then Make companion. Seen: every enemy you fought, with its highest level."])
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
    row.owner = Widgets.CreateFontString(row, "GameFontHighlightSmall", "LEFT"); row.owner:SetPoint("LEFT", 22, 0); row.owner:SetWidth(80)
    row.level = Widgets.CreateFontString(row, "GameFontNormalSmall", "RIGHT"); row.level:SetPoint("RIGHT", -2, 0); row.level:SetWidth(76)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        if self.entry then Panel.state.guildRow = self.entry; Panel.RefreshGuildPreview() end
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    return row
end

---@param row table
---@param entry CompanionRow
local function fillGuildRow(row, entry)
    row.mine:SetShown(entry.mine)
    row.rank:SetText(tostring(entry.rank))
    local owner = entry.nameRaw:match("^([^%-]+)") or entry.nameRaw
    row.owner:SetText(addon.Utility.Escape(owner))
    row.level:SetText(("%d |cffff4060(%+d)|r"):format(entry.level, entry.hearts))
end

---@param panel table
local function buildGuildView(panel)
    local Widgets = addon.UI.Widgets
    widgets.guildWinner = Widgets.CreateFontString(panel, "GameFontNormalSmall", "LEFT")
    widgets.guildWinner:SetPoint("TOPLEFT", 8, -26); widgets.guildWinner:SetWidth(284)
    widgets.guildList = Widgets.CreateScrollList(panel, 190, Widgets.ROW_HEIGHT * 11, createGuildRow, fillGuildRow)
    widgets.guildList:SetPoint("TOPLEFT", 4, -44)
    widgets.guildEmpty = Widgets.CreateFontString(panel, "GameFontDisable", "CENTER")
    widgets.guildEmpty:SetPoint("TOP", widgets.guildList, "TOP", -10, -60); widgets.guildEmpty:SetWidth(170)
    widgets.guildEmpty:SetText(Text["No guild member has a companion yet."])
    local preview = createModel(panel, 104, 130)
    preview:SetPoint("TOPRIGHT", -2, -44)
    widgets.guildModel = preview
    widgets.guildPreviewText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.guildPreviewText:SetPoint("TOP", preview, "BOTTOM", 0, -2); widgets.guildPreviewText:SetWidth(104)
    local note = Widgets.CreateFontString(panel, "GameFontDisableSmall", "CENTER")
    note:SetPoint("TOP", 0, -276); note:SetWidth(290)
    note:SetText(Format(Text["Level = NPC level + rarity + hearts. Weekly pay: {first}, {second}, {third}, others {other}."],
        { first = money(AzeCaught.PAYOUTS[1]), second = money(AzeCaught.PAYOUTS[2]), third = money(AzeCaught.PAYOUTS[3]),
          other = money(AzeCaught.PAYOUT_OTHER) }))
end

------------------------------------------------------------------ build and refresh

-- Builds the panel into `panel` (the game stage's AZEcaught panel, 300 x 336).
---@param panel table
function Panel.Build(panel)
    local Widgets = addon.UI.Widgets
    widgets.panel = panel
    widgets.views, widgets.viewButtons = {}, {}
    local labels = { companion = Text["Companion"], collection = Text["Collection"], guild = Text["Guild"] }
    for index, view in ipairs({ "companion", "collection", "guild" }) do
        local key = view
        local frame = CreateFrame("Frame", nil, panel)
        frame:SetPoint("TOPLEFT", 0, 0); frame:SetPoint("BOTTOMRIGHT", 0, 0)
        widgets.views[view] = frame
        local button = Widgets.CreateButton(panel, labels[view], 94, 18, function() Panel.SelectView(key) end)
        button:SetPoint("TOPLEFT", 4 + (index - 1) * 98, -2)
        widgets.viewButtons[view] = button
    end
    buildCompanionView(widgets.views.companion)
    buildCollectionView(widgets.views.collection)
    buildGuildView(widgets.views.guild)
    -- the bars move while the panel is visible: redraw twice a second
    local elapsedTotal = 0
    panel:SetScript("OnUpdate", function(_, elapsedSeconds)
        elapsedTotal = elapsedTotal + elapsedSeconds
        if elapsedTotal < 0.5 then return end
        elapsedTotal = 0
        if Panel.state.view == "companion" then addon.Log.Protected("caught.ui", "refreshing the companion failed", Panel.RefreshCompanion) end
    end)
    panel:HookScript("OnShow", function()
        widgets.model.shownKey = nil   -- the model resets on show: load it again
        Panel.Refresh()
        Panel.ShowIdle("shown")
        -- clients without OnModelLoaded: once more after the load had time to finish
        if C_Timer then C_Timer.After(0.3, function() if widgets.panel:IsVisible() then Panel.ShowIdle("shownLate") end end) end
    end)
    Panel.state.section = settings().caughtSection == "seen" and "seen" or "caught"
    local view = settings().caughtView
    Panel.SelectView((view == "collection" or view == "guild") and view or "companion")
    Panel.SelectSection(Panel.state.section)
end

function Panel.RefreshCompanion()
    if not widgets.model then return end
    local companion = AzeCaught.Active()
    local hasCompanion = companion ~= nil
    widgets.emptyCompanion:SetShown(not hasCompanion)
    for _, region in ipairs({ widgets.model, widgets.heartIcon, widgets.heartText, widgets.streakText, widgets.nameText, widgets.sleepText }) do
        region:SetShown(hasCompanion)
    end
    for _, bar in pairs(widgets.bars) do bar:SetShown(hasCompanion) end
    Panel.RefreshCareButtons()
    if not companion then showModel(widgets.model, nil, "companion") return end
    showModel(widgets.model, companion, "companion")
    if widgets.model.asleepShown ~= (companion.asleep ~= nil) then
        Panel.IdleOfCompanion(widgets.model, companion.asleep and "fellAsleep" or "wokeUp")
    end
    widgets.nameText:SetText(("|cff%s%s|r  |cffaaaaaa%s %d · %s|r"):format(RARITY_COLOR[companion.cls] or "ffffff",
        addon.Utility.Escape(companion.n), Text["Level"], companion.lvl, rarityText(companion.cls)))
    widgets.heartText:SetText((companion.hearts < 0 and "|cff993333" or "|cffff4060") .. companion.hearts .. "|r")
    widgets.streakText:SetText(Format(Text["Fed streak {fed} · care streak {care} · rank {rank}"],
        { fed = companion.fedStreak, care = companion.careStreak, rank = AzeCaught.CompanionLevel(companion) }))
    widgets.sleepText:SetText(companion.asleep and Format(Text["Asleep, wakes in {time}"], { time = duration(companion.asleep) }) or "")
    for _, need in ipairs(NEED_ORDER) do fillBar(widgets.bars[need], need, companion[need], companion) end
    if companion.starve > 0 then
        widgets.statusText:SetText("|cffff4040" .. Format(Text["Starving! It dies in {time}."],
            { time = duration(AzeCaught.STARVE_TIME - companion.starve) }) .. "|r")
    end
end

function Panel.RefreshPreview()
    local entry = Panel.state.previewNpc and AzeCaught.State().collection[Panel.state.previewNpc]
    if not entry then showModel(widgets.previewModel, nil, "preview") widgets.previewText:SetText("") return end
    showModel(widgets.previewModel, { npc = Panel.state.previewNpc, disp = entry.disp }, "preview")
    widgets.previewText:SetText(("%s\n%s %d · %s\n%s"):format(addon.Utility.Escape(entry.n), Text["Level"], entry.lvl,
        rarityText(entry.cls), entry.caught > 0 and Format(Text["caught x{n}"], { n = entry.caught }) or Text["found"]))
end

function Panel.RefreshGuildPreview()
    local row = Panel.state.guildRow
    if not row then showModel(widgets.guildModel, nil, "guild") widgets.guildPreviewText:SetText("") return end
    showModel(widgets.guildModel, { npc = row.npc, disp = row.disp }, "guild")
    widgets.guildPreviewText:SetText(("%s\n%s %d · %s\n%s %d%% %s %d%%\n%s %d%% %s %d%%%s"):format(row.companion, Text["Level"], row.lvl,
        rarityText(row.cls), Text["Food"], row.hunger, Text["Water"], row.thirst, Text["Petting"], row.affection, Text["Energy"], row.energy,
        row.asleep and ("\n" .. Text["asleep"]) or ""))
end

-- Redraws the visible view (CAUGHT_CHANGED, GAMES_CHANGED, DATA_CHANGED and on show).
function Panel.Refresh()
    if not widgets.views then return end
    local view = Panel.state.view
    if view == "companion" then
        Panel.RefreshCompanion()
    elseif view == "collection" then
        local caught = AzeCaught.State()
        local active = caught.active
        local sections = addon.Model.BuildCollectionSections(caught.collection, active and active.npc)
        widgets.sectionButtons.caught:SetLabel(Format(Text["Caught {n}/{max}"], { n = sections.caughtCount, max = sections.caughtLimit }))
        widgets.sectionButtons.seen:SetLabel(Format(Text["Seen {n}"], { n = #sections.seen }))
        local rows = sections[Panel.state.section] or sections.caught
        widgets.collectionList:SetData(rows)
        if not Panel.state.previewNpc and rows[1] then Panel.state.previewNpc = rows[1].npc end
        Panel.RefreshPreview()
        refreshSwitchButton()
    else
        local now = addon.Utility.Now()
        local records = addon.Games.AllRecords()
        local rows = addon.Model.BuildCompanionRows(records, me())
        widgets.guildList:SetData(rows)
        widgets.guildEmpty:SetShown(#rows == 0)
        local winner = addon.Model.CompanionWinner(addon.Store.db.games, addon.Games.PreviousPeriodKey(now), me())
        widgets.guildWinner:SetText(winner and Format(Text["Last week's best: {name} ({level})"], { name = winner.name, level = winner.peak }) or "")
        if not Panel.state.guildRow and rows[1] then Panel.state.guildRow = rows[1] end
        Panel.RefreshGuildPreview()
    end
end

addon.Events.On("CAUGHT_CHANGED", function() if widgets.panel and widgets.panel:IsVisible() then Panel.Refresh() end end)
addon.Events.On("GAMES_CHANGED", function() if widgets.panel and widgets.panel:IsVisible() and Panel.state.view == "guild" then Panel.Refresh() end end)
addon.Events.On("DATA_CHANGED", function() if widgets.panel and widgets.panel:IsVisible() and Panel.state.view == "guild" then Panel.Refresh() end end)
