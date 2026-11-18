local addonName, addon = ...

-- Applies the opacity to the UI elements. One OnUpdate drives everything:
--   * hover is polled with MouseIsOver (no OnEnter/OnLeave hooks, so action buttons keep their own scripts and no
--     taint is added; it also counts the mouse over child buttons, which OnEnter on the bar would not),
--   * each element fades towards its target with Logic.Step,
--   * SetAlpha is only called when the frame's alpha differs, which also re-applies it when Blizzard code resets it.
local Logic, Elements = addon.Logic, addon.Elements
local Fader = {}
addon.Fader = Fader

local HOVER_INTERVAL = 0.05   -- seconds between hover checks
local RESOLVE_INTERVAL = 2    -- seconds between frame lookups (some frames are created late)

local runtime = {
    alpha = {},      -- key -> current faded alpha
    managed = {},    -- key -> true while the addon controls it
    hovered = {},    -- key -> true
    frames = {},     -- key -> list of frames
    hoverTimer = 0,
    resolveTimer = RESOLVE_INTERVAL,
}
Fader.runtime = runtime

local function db() return ForeverBetterUIPlusDB end

local function resolve()
    for _, element in ipairs(Elements.list) do runtime.frames[element.key] = Elements.Frames(element) end
end

-- frame:IsMouseOver() is the widget method; the global MouseIsOver(frame) helper does not exist on every client.
local function mouseOver(frame)
    if frame.IsMouseOver then return frame:IsMouseOver() end
    if MouseIsOver then return MouseIsOver(frame) end
    return false
end

local function isHovered(frames)
    for _, frame in ipairs(frames) do
        if frame:IsVisible() and mouseOver(frame) then return true end
    end
    return false
end

local function editModeActive()
    return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive()
        or false
end

local function apply(frames, alpha)
    for _, frame in ipairs(frames) do
        if math.abs(frame:GetAlpha() - alpha) > 0.001 then frame:SetAlpha(alpha) end
    end
end

local context = {}
local function onUpdate(_, elapsed)
    local settings = db()
    if not settings then return end
    runtime.resolveTimer = runtime.resolveTimer + elapsed
    if runtime.resolveTimer >= RESOLVE_INTERVAL then
        runtime.resolveTimer = 0
        resolve()
    end
    runtime.hoverTimer = runtime.hoverTimer + elapsed
    local checkHover = runtime.hoverTimer >= HOVER_INTERVAL
    if checkHover then runtime.hoverTimer = 0 end

    context.editMode = editModeActive()
    context.inCombat = InCombatLockdown() or UnitAffectingCombat("player")

    for _, element in ipairs(Elements.list) do
        local key = element.key
        local frames = runtime.frames[key]
        local base = Logic.BaseAlpha(settings, key)
        if not base then
            if runtime.managed[key] then
                apply(frames, 1)
                runtime.managed[key], runtime.alpha[key] = nil, nil
            end
        elseif frames and #frames > 0 then
            runtime.managed[key] = true
            if checkHover then runtime.hovered[key] = isHovered(frames) end
            context.hovered = runtime.hovered[key]
            context.combatFull = Logic.CombatFull(settings, key)
            local target = Logic.TargetAlpha(base, context)
            local current = runtime.alpha[key] or 1
            local alpha = Logic.Step(current, target, elapsed, settings.fadeSeconds)
            runtime.alpha[key] = alpha
            apply(frames, alpha)
        end
    end
end

-- Puts every element back to full opacity (used by /fbui disable and before a full reset).
function Fader.RestoreAll()
    for _, element in ipairs(Elements.list) do
        apply(runtime.frames[element.key] or Elements.Frames(element), 1)
        runtime.managed[element.key], runtime.alpha[element.key] = nil, nil
    end
end

---@param key string
---@return table frames, boolean hovered
function Fader.Info(key) return runtime.frames[key] or {}, runtime.hovered[key] or false end

------------------------------------------------------------------ boot

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ForeverBetterUIPlusDB = Logic.NewSettings(ForeverBetterUIPlusDB)
        addon.Log.Write("boot", "---- login ----", { global = ForeverBetterUIPlusDB.global })
        resolve()
        local missing = {}
        for _, element in ipairs(Elements.list) do
            if #runtime.frames[element.key] == 0 then missing[#missing + 1] = element.key end
        end
        if #missing > 0 then addon.Log.Write("boot", "frames not found (yet)", { keys = table.concat(missing, ",") }) end
        local ok, problem = pcall(addon.Options.Register)
        if not ok then addon.Log.Write("error", "options register failed", { error = tostring(problem) }) end
        driver:SetScript("OnUpdate", function(self, elapsed)
            if ForeverBetterUIPlusDB.disabled then return end
            onUpdate(self, elapsed)
        end)
    end
end)
