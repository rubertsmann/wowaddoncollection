local addonName, addon = ...

-- Animation helpers (feature 014). Hybrid, per features/014-guild-game-base/evidence/animations-research.md:
--   * AnimationGroup for effects that end where they started (fade in, pulse, shake, glow);
--   * one shared OnUpdate driver (Animate.Tween) for motion that changes real layout, so the anchor and the hit rect move
--     with the region (pitfalls K1/K2 do not apply).
-- Every effect is safe: an unsupported animation type or any error applies the final state at once and calls onDone
-- exactly once, so game logic never waits on an animation that cannot play (RF6).
---@class AnimateModule
---@field speed number time multiplier for every animation (debug slow motion: /tsd anim speed 0.25)
local Animate = {}
addon.Animate = Animate

Animate.speed = 1

---@type table<string, boolean> animation type -> CreateAnimation accepted it on this client
local supportCache = {}
---@type table|nil hidden frame the support probe creates groups on
local probeFrame
-- region -> effect name -> AnimationGroup (weak keys: a region that goes away takes its groups with it)
local groupsByRegion = setmetatable({}, { __mode = "k" })

-- Whether this client accepts `animationType` in CreateAnimation (cached).
---@param animationType string "Alpha"|"Scale"|"Translation"|"Rotation"|"Path"|"FlipBook"|...
---@return boolean
function Animate.Supported(animationType)
    if supportCache[animationType] ~= nil then return supportCache[animationType] end
    local ok, animation = pcall(function()
        probeFrame = probeFrame or CreateFrame("Frame")
        local group = probeFrame:CreateAnimationGroup()
        return group:CreateAnimation(animationType)
    end)
    supportCache[animationType] = (ok and animation ~= nil) and true or false
    return supportCache[animationType]
end

-- Plays the cached group `effectName` of `region`, building it with build(group) the first time. finalState() is the
-- state the region must be in afterwards; it runs when the group finishes, or at once when anything fails.
---@param region table
---@param effectName string
---@param requiredTypes string[]
---@param build fun(group: table)
---@param finalState fun()
---@param onDone? fun()
local function play(region, effectName, requiredTypes, build, finalState, onDone)
    local finished = false
    local function finish()
        if finished then return end
        finished = true
        pcall(finalState)
        if onDone then onDone() end
    end
    local ok, errorMessage = pcall(function()
        for _, animationType in ipairs(requiredTypes) do
            if not Animate.Supported(animationType) then error("animation type not supported: " .. animationType) end
        end
        local groups = groupsByRegion[region]
        if not groups then groups = {}; groupsByRegion[region] = groups end
        local group = groups[effectName]
        if not group then
            group = region:CreateAnimationGroup()
            build(group)
            groups[effectName] = group
        end
        group:Stop()   -- a replay restarts cleanly (K7); the replaced run's onDone is dropped with its script
        group:SetScript("OnFinished", finish)
        if group.SetAnimationSpeedMultiplier then group:SetAnimationSpeedMultiplier(Animate.speed) end
        group:Play()
    end)
    if not ok then
        addon.Log.Debug("animate.play", "an animation could not play; its end state was applied directly",
            { effect = effectName, error = tostring(errorMessage) })
        finish()
    end
end

---@param animation table
---@param fromAlpha number
---@param toAlpha number
---@param duration number
---@param order integer
local function alphaStep(animation, fromAlpha, toAlpha, duration, order)
    animation:SetFromAlpha(fromAlpha); animation:SetToAlpha(toAlpha)
    animation:SetDuration(duration); animation:SetOrder(order)
end

-- Scale from -> to (SetScaleFrom/To on current clients, the relative SetScale on old ones)
---@param animation table
---@param fromScale number
---@param toScale number
local function scaleStep(animation, fromScale, toScale)
    if animation.SetScaleFrom and animation.SetScaleTo then
        animation:SetScaleFrom(fromScale, fromScale); animation:SetScaleTo(toScale, toScale)
    else
        animation:SetScale(toScale / fromScale, toScale / fromScale)
    end
end

-- Shows `region` and fades it in from transparent. Ends fully opaque (SetToFinalAlpha, K3).
---@param region table
---@param duration? number default 0.3
---@param onDone? fun()
function Animate.FadeIn(region, duration, onDone)
    region:Show()
    play(region, "fadeIn", { "Alpha" }, function(group)
        if group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
        local fade = group:CreateAnimation("Alpha")
        alphaStep(fade, 0, 1, duration or 0.3, 1)
        fade:SetSmoothing("OUT")
    end, function() region:SetAlpha(1) end, onDone)
end

-- Grows `region` to peakScale and back (scale animations end where they started).
---@param region table
---@param peakScale? number default 1.15
---@param duration? number total seconds, default 0.25
---@param onDone? fun()
function Animate.Pulse(region, peakScale, duration, onDone)
    peakScale, duration = peakScale or 1.15, duration or 0.25
    play(region, "pulse", { "Scale" }, function(group)
        local grow = group:CreateAnimation("Scale")
        scaleStep(grow, 1, peakScale); grow:SetDuration(duration / 2); grow:SetOrder(1); grow:SetSmoothing("OUT")
        local shrink = group:CreateAnimation("Scale")
        scaleStep(shrink, peakScale, 1); shrink:SetDuration(duration / 2); shrink:SetOrder(2); shrink:SetSmoothing("IN")
    end, function() end, onDone)
end

-- Horizontal offsets of a shake that ends where it started: +p, -2p, +2p, ..., back to 0.
---@param pixels number
---@param count integer number of movements (at least 2)
---@return number[]
function Animate.ShakeOffsets(pixels, count)
    count = math.max(2, math.floor(count or 4))
    local offsets, position = {}, 0
    for index = 1, count - 1 do
        local target = (index % 2 == 1) and pixels or -pixels
        offsets[index] = target - position
        position = target
    end
    offsets[count] = -position
    return offsets
end

-- Shakes `region` sideways: `count` Translation steps of 0.04 s that add up to zero (it ends where it started).
---@param region table
---@param pixels? number default 4
---@param count? integer default 4
---@param onDone? fun()
function Animate.Shake(region, pixels, count, onDone)
    local offsets = Animate.ShakeOffsets(pixels or 4, count or 4)
    play(region, "shake" .. #offsets .. ":" .. (pixels or 4), { "Translation" }, function(group)
        for index, offset in ipairs(offsets) do
            local step = group:CreateAnimation("Translation")
            step:SetOffset(offset, 0); step:SetDuration(0.04); step:SetOrder(index)
        end
    end, function() end, onDone)
end

-- Flashes a glow texture (ADD blend) `times` times: alpha 0 -> 1 -> 0. Ends hidden at alpha 0.
---@param region table
---@param times? integer default 2
---@param onDone? fun()
function Animate.Glow(region, times, onDone)
    times = math.max(1, math.floor(times or 2))
    region:SetAlpha(0)
    region:Show()
    play(region, "glow" .. times, { "Alpha" }, function(group)
        if group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
        for index = 1, times do
            local brighten = group:CreateAnimation("Alpha")
            alphaStep(brighten, 0, 1, 0.18, index * 2 - 1); brighten:SetSmoothing("OUT")
            local dim = group:CreateAnimation("Alpha")
            alphaStep(dim, 1, 0, 0.32, index * 2); dim:SetSmoothing("IN")
        end
    end, function() region:SetAlpha(0); region:Hide() end, onDone)
end

------------------------------------------------------------------ tween driver (OnUpdate)

---@class Tween
---@field elapsed number
---@field duration number
---@field onStep fun(elapsed: number)
---@field onDone? fun()

---@type table<string, Tween>
local tweens = {}
---@type table|nil
local driverFrame

-- Ends the tween `key`: removes it, then calls its onDone (errors are logged, never thrown).
---@param key string
---@param tween Tween
local function completeTween(key, tween)
    if tweens[key] == tween then tweens[key] = nil end
    if tween.onDone then addon.Log.Protected("animate.tween", "a tween's end handler failed", tween.onDone) end
end

---@param _ table
---@param elapsedSeconds number
local function onUpdate(_, elapsedSeconds)
    local active = {}
    for key, tween in pairs(tweens) do active[#active + 1] = { key = key, tween = tween } end
    for _, entry in ipairs(active) do
        local tween = entry.tween
        if tweens[entry.key] == tween then   -- not replaced by an earlier step of this frame
            tween.elapsed = math.min(tween.duration, tween.elapsed + elapsedSeconds * Animate.speed)
            local ok, errorMessage = pcall(tween.onStep, tween.elapsed)
            if not ok then
                addon.Log.Warning("animate.tween", "a tween step failed; the tween was ended", { key = entry.key, error = tostring(errorMessage) })
                completeTween(entry.key, tween)
            elseif tween.elapsed >= tween.duration then
                completeTween(entry.key, tween)
            end
        end
    end
    if next(tweens) == nil and driverFrame then driverFrame:SetScript("OnUpdate", nil) end
end

-- Calls onStep(elapsed) every rendered frame for `duration` seconds (last call with elapsed = duration), then onDone().
-- A tween started with the key of a running one replaces it; the replaced one's onDone is NOT called.
-- The driver frame has no parent: closing the window does not stop a tween, so a flip always lands.
---@param key string
---@param duration number
---@param onStep fun(elapsed: number)
---@param onDone? fun()
function Animate.Tween(key, duration, onStep, onDone)
    driverFrame = driverFrame or CreateFrame("Frame")
    tweens[key] = { elapsed = 0, duration = math.max(0, duration or 0), onStep = onStep, onDone = onDone }
    driverFrame:SetScript("OnUpdate", onUpdate)
end

-- Whether a tween with this key is running.
---@param key string
---@return boolean
function Animate.IsTweening(key) return tweens[key] ~= nil end

-- Jumps the tween `key` to its end (final step, then onDone). Nothing when it is not running.
---@param key string
function Animate.FinishTween(key)
    local tween = tweens[key]
    if not tween then return end
    tween.elapsed = tween.duration
    pcall(tween.onStep, tween.duration)
    completeTween(key, tween)
end

-- for tests: the driver's OnUpdate handler
Animate._onUpdate = onUpdate
