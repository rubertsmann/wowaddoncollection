local addonName, addon = ...

-- Companion Dash, the runner game's panel (rules and numbers: Core/Minigames/Runner.lua).
--   play area: a sky gradient and four parallax layers drawn from plain shapes (clouds, far mountains as tall ellipses
--     whose lower half the hills cover, rolling hills, the ground with pebbles), each scrolling at its own share of the speed;
--     the companion's model runs on the ground line, monsters from the collection come as models from the right
--   input: mouse down in the top half jumps (held = higher), held in the bottom half ducks; Space / Up / W jump and
--     Down / S duck while a run is open (other keys pass through to the game)
--   below: Start, the best distance and today's gold, the result of the last run
-- Without an active companion the panel is locked. A run pauses while the panel is hidden (no OnUpdate).
---@class RunnerViewModule
local RunnerView = {}
addon.RunnerView = RunnerView

local Text, Format = addon.Text, addon.Locale.Format
local Runner = addon.Runner

local AREA_HEIGHT = 200
local GROUND_Y = 30                   -- the ground line above the play area's bottom
local IDLE_SPEED = 60                 -- background scroll while no run is open
local MODEL_SIZE = 64                 -- model frames are larger than the boxes: models have empty margins
local RUNNER_FACING, MONSTER_FACING = math.pi / 2, -math.pi / 2
local OBSTACLE_MODELS = 6
local DISC_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\UI\\Textures\\Disc"
-- stand-ins while a model is not drawn: the runner, a ground monster, a flying monster
local RUNNER_ICON = "Interface\\Icons\\Ability_Hunter_Pet_Wolf"
local GROUND_ICON = "Interface\\Icons\\Ability_Hunter_Pet_Boar"
local FLYER_ICON = "Interface\\Icons\\Ability_Hunter_Pet_Bat"
local KEYS_JUMP = { SPACE = true, UP = true, W = true }
local KEYS_DUCK = { DOWN = true, S = true }

-- parallax layers: share of the run speed, wrap span, and the shapes { x, y, w, h } (y = centre above the ground line);
-- every round shape is the addon's disc texture (tall ellipses are the mountains, the hills cover their lower half)
local LAYERS = {
    { key = "clouds", share = 0.06, span = 520, shape = "disc", color = { 1, 1, 1, 0.55 },
      shapes = { { 30, 140, 74, 20 }, { 150, 160, 54, 16 }, { 250, 128, 90, 24 }, { 370, 150, 64, 18 }, { 450, 136, 48, 14 } } },
    { key = "mountains", share = 0.14, span = 560, shape = "disc", color = { 0.36, 0.40, 0.56, 1 },
      shapes = { { 20, 20, 120, 170 }, { 110, 25, 150, 200 }, { 230, 15, 110, 140 }, { 330, 25, 170, 210 }, { 450, 20, 130, 160 } } },
    { key = "hills", share = 0.35, span = 520, shape = "disc", color = { 0.22, 0.42, 0.24, 1 }, band = 22,
      shapes = { { 0, 14, 170, 60 }, { 130, 16, 150, 70 }, { 260, 12, 190, 56 }, { 390, 15, 160, 66 } } },
    { key = "pebbles", share = 1, span = 340, shape = "rect", color = { 0.30, 0.22, 0.12, 1 },
      shapes = { { 10, -9, 6, 3 }, { 70, -18, 10, 3 }, { 120, -6, 4, 2 }, { 190, -14, 8, 3 }, { 250, -22, 12, 4 }, { 300, -10, 5, 2 } } },
}

---@class RunnerViewState
---@field run RunnerRun|nil
---@field input { jump: boolean, duck: boolean }
---@field scroll number distance shown while idle
---@field lastResult RunnerResult|nil
RunnerView.state = { run = nil, input = { jump = false, duck = false }, scroll = 0, lastResult = nil }

---@type table widgets (nil fields until Build ran)
local widgets = {}
RunnerView.widgets = widgets

local money = addon.Model.MoneyText

------------------------------------------------------------------ background

---@param texture table
---@param top number[]
---@param bottom number[]
local function gradient(texture, top, bottom)
    texture:SetColorTexture(1, 1, 1, 1)
    local applied = CreateColor and pcall(texture.SetGradient, texture, "VERTICAL",
        CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    if not applied then applied = texture.SetGradientAlpha and pcall(texture.SetGradientAlpha, texture, "VERTICAL",
        bottom[1], bottom[2], bottom[3], 1, top[1], top[2], top[3], 1) end
    if not applied then texture:SetColorTexture((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2, 1) end
end

---@param area table
local function buildBackground(area)
    local sky = area:CreateTexture(nil, "BACKGROUND", nil, 0)
    sky:SetAllPoints(); gradient(sky, { 0.32, 0.52, 0.82 }, { 0.86, 0.76, 0.58 })
    widgets.layers = {}
    for order, layer in ipairs(LAYERS) do
        local shapes = {}
        if layer.band then
            local band = area:CreateTexture(nil, "BACKGROUND", nil, order + 1)
            band:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, GROUND_Y); band:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, GROUND_Y)
            band:SetHeight(layer.band); band:SetColorTexture(layer.color[1], layer.color[2], layer.color[3], layer.color[4])
        end
        for index, shape in ipairs(layer.shapes) do
            local texture = area:CreateTexture(nil, "BACKGROUND", nil, order + 1)
            if layer.shape == "disc" then
                addon.UIHelpers.SetTextureOr(texture, DISC_TEXTURE, layer.color)
                texture:SetVertexColor(layer.color[1], layer.color[2], layer.color[3]); texture:SetAlpha(layer.color[4])
            else
                texture:SetColorTexture(layer.color[1], layer.color[2], layer.color[3], layer.color[4])
            end
            texture:SetSize(shape[3], shape[4])
            shapes[index] = { texture = texture, x = shape[1], y = shape[2] }
        end
        widgets.layers[order] = { spec = layer, shapes = shapes }
    end
    local ground = area:CreateTexture(nil, "BORDER", nil, 0)
    ground:SetPoint("BOTTOMLEFT"); ground:SetPoint("BOTTOMRIGHT"); ground:SetHeight(GROUND_Y)
    gradient(ground, { 0.55, 0.42, 0.24 }, { 0.36, 0.26, 0.14 })
    local edge = area:CreateTexture(nil, "BORDER", nil, 1)
    edge:SetPoint("BOTTOMLEFT", 0, GROUND_Y - 2); edge:SetPoint("BOTTOMRIGHT", 0, GROUND_Y - 2); edge:SetHeight(3)
    edge:SetColorTexture(0.68, 0.56, 0.32, 1)
    -- the pebbles lie on the ground, above it
    for _, shape in ipairs(widgets.layers[#widgets.layers].shapes) do shape.texture:SetDrawLayer("BORDER", 2) end
end

-- Places every layer's shapes for a scroll distance (each wraps over its span).
---@param distance number
local function drawBackground(distance)
    local area = widgets.area
    for _, layer in ipairs(widgets.layers) do
        local span, offset = layer.spec.span, distance * layer.spec.share
        for _, shape in ipairs(layer.shapes) do
            local x = (shape.x - offset) % span - (span - Runner.WIDTH) / 2
            shape.texture:ClearAllPoints()
            shape.texture:SetPoint("CENTER", area, "BOTTOMLEFT", x, GROUND_Y + shape.y)
        end
    end
end
RunnerView.DrawBackground = drawBackground

------------------------------------------------------------------ actors

---@param model table
---@param boxX number left edge of the box
---@param boxY number bottom of the box above the ground line
---@param boxWidth number
local function placeModel(model, boxX, boxY, boxWidth)
    model:ClearAllPoints()
    model:SetPoint("BOTTOM", widgets.area, "BOTTOMLEFT", boxX + boxWidth / 2, GROUND_Y + boxY - 6)
end

---@param run RunnerRun|nil
local function drawRunner(run)
    local runner = widgets.runner
    local y, ducking = run and run.y or 0, run and run.ducking or false
    runner:SetHeight(ducking and MODEL_SIZE * 0.72 or MODEL_SIZE)
    placeModel(runner, Runner.RUNNER_X, y, Runner.RUNNER_WIDTH)
    widgets.runnerShadow:SetAlpha(0.35 * math.max(0.25, 1 - y / 120))
end

-- the model frame of an obstacle (one per obstacle id; the pool is reused)
---@param obstacle RunnerObstacle
---@param run RunnerRun
---@return table|nil slot
local function slotFor(obstacle, run)
    local free
    for _, slot in ipairs(widgets.obstacles) do
        if slot.id == obstacle.id then return slot end
        if not free and not slot.id then free = slot end
    end
    if not free then return nil end
    free.id = obstacle.id
    local monster = run.pool[obstacle.pick]
    addon.CompanionModel.SetFallbackIcon(free.model, obstacle.fly and FLYER_ICON or GROUND_ICON, true)
    addon.CompanionModel.Load(free.model, monster)
    addon.CompanionModel.Play(free.model, addon.CompanionModel.ANIMATION.run, true)
    free.name = monster and monster.n or "?"
    return free
end

---@param run RunnerRun|nil
local function drawObstacles(run)
    local alive = {}
    for _, obstacle in ipairs(run and run.obstacles or {}) do
        alive[obstacle.id] = true
        local slot = obstacle.x < Runner.WIDTH - Runner.BOX * 0.5 and slotFor(obstacle, run) or nil
        if slot then
            placeModel(slot.model, obstacle.x, obstacle.y, Runner.BOX)
            slot.shadow:ClearAllPoints()
            slot.shadow:SetPoint("CENTER", widgets.area, "BOTTOMLEFT", obstacle.x + Runner.BOX / 2, GROUND_Y - 2)
            slot.shadow:SetAlpha(obstacle.fly and 0.15 or 0.35)
            slot.model:Show(); slot.shadow:Show()
        end
    end
    for _, slot in ipairs(widgets.obstacles) do
        if slot.id and not alive[slot.id] then
            slot.id = nil
            slot.model:Hide(); slot.shadow:Hide()
        end
    end
end

------------------------------------------------------------------ text

---@return string
local function statsText()
    local state = Runner.State()
    local paid = Runner.PaidToday(addon.Utility.Now())
    return Format(Text["Best: {meters} m   Gold today: {gold}/{cap}"],
        { meters = state.b, gold = paid, cap = Runner.DAILY_CAP_GOLD })
end

-- The panel's state: locked without a companion, else the stats and the start hint.
function RunnerView.Refresh()
    if not widgets.area then return end
    local companion = addon.AzeCaught.Active()
    local locked = companion == nil
    widgets.lockText:SetShown(locked)
    widgets.startButton:SetEnabled(not locked)
    widgets.statsText:SetText(statsText())
    if not RunnerView.state.run then
        widgets.hintText:SetShown(not locked)
        local loaded = addon.CompanionModel.Load(widgets.runner, companion)
        widgets.runner:SetShown(loaded); widgets.runnerShadow:SetShown(loaded)
        if loaded then addon.CompanionModel.Play(widgets.runner, addon.CompanionModel.ANIMATION.run) end
    end
end

------------------------------------------------------------------ a run

---@param handled boolean
local function propagate(handled)
    if widgets.area.SetPropagateKeyboardInput then pcall(widgets.area.SetPropagateKeyboardInput, widgets.area, not handled) end
end

---@param result RunnerResult
---@param crashedName string|nil
local function showResult(result, crashedName)
    local lines = { Format(Text["{meters} m: +{gold}"], { meters = result.meters, gold = money(result.gold * addon.Games.COPPER_PER_GOLD) }) }
    if result.best and result.meters > 0 then lines[#lines + 1] = "|cffffd200" .. Text["New best!"] .. "|r" end
    if result.capped then lines[#lines + 1] = "|cff999999" .. Text["Today's gold limit is reached; runs still count for the board."] .. "|r" end
    if crashedName then lines[#lines + 1] = "|cff999999" .. Format(Text["Stopped by {name}"], { name = addon.Utility.Escape(crashedName) }) .. "|r" end
    widgets.resultText:SetText(table.concat(lines, "\n"))
    addon.Animate.FadeIn(widgets.resultText, 0.3)
end

---@param run RunnerRun
local function finish(run)
    local state = RunnerView.state
    state.run, state.scroll = nil, run.distance
    state.input.jump, state.input.duck = false, false
    if widgets.area.EnableKeyboard then pcall(widgets.area.EnableKeyboard, widgets.area, false) end
    local crashed = run.crashedInto and run.pool[run.crashedInto.pick]
    local result = Runner.Finish(run, addon.Utility.Me(), addon.Utility.Now())
    state.lastResult = result
    addon.CompanionModel.Play(widgets.runner, addon.CompanionModel.ANIMATION.hurt, true)
    addon.Animate.Flash("runnerCrash", widgets.crashFlash, 0.35, 0.35)
    addon.Api.PlaySoundNamed(result.gold > 0 and { "LOOT_WINDOW_COIN_SOUND" } or { "IG_MAINMENU_OPTION_CHECKBOX_OFF" })
    showResult(result, crashed and crashed.n)
    widgets.startButton:SetText(Text["Run again"])
    addon.Log.Debug("games.runner", "a run ended", { meters = result.meters, gold = result.gold, best = result.best })
    addon.GamesTab.SetBusy(false)
    addon.Events.Fire("GAMES_CHANGED"); addon.Events.Fire("CAUGHT_CHANGED")
    RunnerView.Refresh()
end

-- Starts a run (Start button, or a click into the idle play area). Refused without a companion or while one is open.
---@return RunnerRun|nil
function RunnerView.Start()
    local state = RunnerView.state
    local companion = addon.AzeCaught.Active()
    if state.run or not companion or not widgets.area then return nil end
    local pool = Runner.BuildPool(addon.AzeCaught.State().collection)
    local run = Runner.New(pool, math.floor(addon.Api.Random() * 2147483646) + 1)
    state.run = run
    state.input.jump, state.input.duck = false, false
    widgets.resultText:SetText(""); widgets.hintText:Hide()
    for _, slot in ipairs(widgets.obstacles) do slot.id = nil; slot.model:Hide(); slot.shadow:Hide() end
    if widgets.area.EnableKeyboard then pcall(widgets.area.EnableKeyboard, widgets.area, true) end
    addon.CompanionModel.Load(widgets.runner, companion)
    addon.CompanionModel.Play(widgets.runner, addon.CompanionModel.ANIMATION.run, true)
    addon.GamesTab.SetBusy(true)
    addon.Api.PlaySoundNamed({ "IG_MAINMENU_OPTION_CHECKBOX_ON" })
    addon.Log.Debug("games.runner", "a run started", { pool = #pool })
    return run
end

---@param event table
local function handleEvent(event)
    local CompanionModel = addon.CompanionModel
    if event.kind == "jump" then
        CompanionModel.Play(widgets.runner, CompanionModel.ANIMATION.jump, true)
    elseif event.kind == "land" then
        CompanionModel.Play(widgets.runner, CompanionModel.ANIMATION.run, true)
    elseif event.kind == "milestone" then
        addon.Animate.FloatText("runner", widgets.floatText, widgets.runner, 0, 20, Format(Text["{meters} m"], { meters = event.meters }),
            { 1, 0.85, 0.3 })
        addon.Api.PlaySoundNamed({ "LOOT_WINDOW_COIN_SOUND" })
    end
end

-- One frame: simulate an open run (or scroll the idle background) and draw.
---@param elapsedSeconds number
function RunnerView.Update(elapsedSeconds)
    local state = RunnerView.state
    local run = state.run
    if run then
        Runner.Step(run, elapsedSeconds, state.input)
        local events = Runner.TakeEvents(run)
        for _, event in ipairs(events) do handleEvent(event) end
        if run.finished then
            drawObstacles(run); drawRunner(run)
            finish(run)
            return
        end
        drawBackground(run.distance); drawRunner(run); drawObstacles(run)
        widgets.distanceText:SetText(Format(Text["{meters} m"], { meters = Runner.Meters(run) }))
    else
        state.scroll = state.scroll + IDLE_SPEED * math.min(elapsedSeconds, Runner.MAXIMUM_FRAME)
        drawBackground(state.scroll)
    end
end

------------------------------------------------------------------ input

---@param area table
local function pressAt(area)
    local state = RunnerView.state
    if not state.run then RunnerView.Start() return end
    local _, cursorY = GetCursorPosition()
    local scale = area:GetEffectiveScale() or 1
    local bottom = area:GetBottom() or 0
    if (cursorY / scale - bottom) > AREA_HEIGHT / 2 then state.input.jump = true else state.input.duck = true end
end

---@param area table
local function bindInput(area)
    area:EnableMouse(true)
    area:SetScript("OnMouseDown", function(self) pressAt(self) end)
    area:SetScript("OnMouseUp", function()
        RunnerView.state.input.jump, RunnerView.state.input.duck = false, false
    end)
    area:SetScript("OnHide", function()
        RunnerView.state.input.jump, RunnerView.state.input.duck = false, false
    end)
    pcall(area.SetScript, area, "OnKeyDown", function(_, key)
        local input = RunnerView.state.input
        if not RunnerView.state.run then propagate(false) return end
        if KEYS_JUMP[key] then input.jump = true propagate(true)
        elseif KEYS_DUCK[key] then input.duck = true propagate(true)
        else propagate(false) end
    end)
    pcall(area.SetScript, area, "OnKeyUp", function(_, key)
        local input = RunnerView.state.input
        if KEYS_JUMP[key] then input.jump = false end
        if KEYS_DUCK[key] then input.duck = false end
    end)
end

------------------------------------------------------------------ build

---@param panel table the Games tab's runner panel (300 wide)
function RunnerView.Build(panel)
    local Widgets = addon.UI.Widgets
    widgets.panel = panel
    local area = CreateFrame("Frame", nil, panel)
    area:SetSize(Runner.WIDTH, AREA_HEIGHT); area:SetPoint("TOP", panel, "TOP", 0, -2)
    if area.SetClipsChildren then pcall(area.SetClipsChildren, area, true) end
    widgets.area = area
    buildBackground(area)

    -- actors: shadows on the ground, then the monster models and the runner
    local actors = CreateFrame("Frame", nil, area)
    actors:SetAllPoints(); actors:SetFrameLevel(addon.UIHelpers.FrameLevel(area) + 1)
    widgets.obstacles = {}
    for index = 1, OBSTACLE_MODELS do
        local shadow = actors:CreateTexture(nil, "ARTWORK")
        addon.UIHelpers.SetTextureOr(shadow, DISC_TEXTURE, { 0, 0, 0 })
        shadow:SetVertexColor(0, 0, 0); shadow:SetSize(Runner.BOX, 8); shadow:Hide()
        local model = addon.CompanionModel.Create(actors, MODEL_SIZE, MODEL_SIZE, { facing = MONSTER_FACING,
            fallback = { icon = GROUND_ICON, size = Runner.BOX - 4, y = 8, mirror = true } })
        model:Hide()
        widgets.obstacles[index] = { model = model, shadow = shadow }
    end
    widgets.runnerShadow = actors:CreateTexture(nil, "ARTWORK")
    addon.UIHelpers.SetTextureOr(widgets.runnerShadow, DISC_TEXTURE, { 0, 0, 0 })
    widgets.runnerShadow:SetVertexColor(0, 0, 0); widgets.runnerShadow:SetSize(Runner.RUNNER_WIDTH + 6, 8)
    widgets.runnerShadow:SetPoint("CENTER", area, "BOTTOMLEFT", Runner.RUNNER_X + Runner.RUNNER_WIDTH / 2, GROUND_Y - 2)
    widgets.runner = addon.CompanionModel.Create(actors, MODEL_SIZE, MODEL_SIZE, { facing = RUNNER_FACING,
        fallback = { icon = RUNNER_ICON, size = Runner.RUNNER_WIDTH, y = 6 } })
    widgets.runner:SetFrameLevel(addon.UIHelpers.FrameLevel(actors) + 2)

    -- overlay: distance, hint, lock, crash flash, floating text
    local overlay = CreateFrame("Frame", nil, area)
    overlay:SetAllPoints(); overlay:SetFrameLevel(addon.UIHelpers.FrameLevel(actors) + 5)
    widgets.crashFlash = overlay:CreateTexture(nil, "OVERLAY")
    widgets.crashFlash:SetAllPoints(); widgets.crashFlash:SetColorTexture(0.9, 0.15, 0.05, 1)
    widgets.crashFlash:SetAlpha(0); widgets.crashFlash:Hide()
    widgets.distanceText = Widgets.CreateFontString(overlay, "GameFontNormalLarge", "RIGHT")
    widgets.distanceText:SetPoint("TOPRIGHT", area, "TOPRIGHT", -6, -6); widgets.distanceText:SetText("")
    widgets.hintText = Widgets.CreateFontString(overlay, "GameFontHighlightSmall", "CENTER")
    widgets.hintText:SetPoint("TOP", area, "TOP", 0, -10); widgets.hintText:SetWidth(Runner.WIDTH - 20)
    widgets.hintText:SetText(Text["Click the top half to jump (hold: higher), hold the bottom half to duck. Space and the arrow keys work too."])
    widgets.lockText = Widgets.CreateFontString(overlay, "GameFontNormal", "CENTER")
    widgets.lockText:SetPoint("CENTER", area, "CENTER", 0, 20); widgets.lockText:SetWidth(Runner.WIDTH - 30)
    widgets.lockText:SetText(Text["Catch a companion in AZEcaught first: it is the runner."])
    widgets.floatText = Widgets.CreateFontString(overlay, "GameFontNormalHuge", "CENTER"); widgets.floatText:Hide()
    bindInput(area)

    widgets.startButton = Widgets.CreateButton(panel, Text["Start"], 180, 28, function() RunnerView.Start() end)
    widgets.startButton:SetPoint("TOP", panel, "TOP", 0, -214)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.startButton) end
    widgets.statsText = Widgets.CreateFontString(panel, "GameFontHighlightSmall", "CENTER")
    widgets.statsText:SetPoint("TOP", panel, "TOP", 0, -250); widgets.statsText:SetWidth(290)
    widgets.resultText = Widgets.CreateFontString(panel, "GameFontNormal", "CENTER")
    widgets.resultText:SetPoint("TOP", panel, "TOP", 0, -272); widgets.resultText:SetWidth(290)

    panel:SetScript("OnUpdate", function(_, elapsedSeconds) RunnerView.Update(elapsedSeconds) end)
    panel:HookScript("OnShow", function() RunnerView.Refresh() end)
    drawBackground(0); drawRunner(nil)
    RunnerView.Refresh()
end

addon.Events.On("CAUGHT_CHANGED", function() if not RunnerView.state.run then RunnerView.Refresh() end end)
