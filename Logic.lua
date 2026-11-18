local _, addon = ...

-- Pure rules of the cigarette: burning, flipbook frames, ember glow, smoke particles, first-person detection.
-- No WoW API calls here (tests/run.lua loads this file outside the game). Lengths are in "S" units: fractions of the
-- overlay's size (the cigarette cell is S x S on screen), so everything scales with the screen and /cig scale.
---@class FpvLogic
local Logic = {}
addon.Logic = Logic

Logic.BURN_SECONDS = 300          -- a whole cigarette, default (/cig time)
Logic.DRAG_BURN_SECONDS = 4       -- a drag burns this much extra
Logic.INHALE_SECONDS = 1.3        -- ember brightens while you draw
Logic.EXHALE_DELAY = 1.6          -- exhale starts this long after the drag began
Logic.LIGHT_FLARE_SECONDS = 1.2
Logic.HIDE_AFTER_OUT = 2.5        -- seconds the cigarette stays on screen after going out
Logic.ZOOM_THRESHOLD = 0.75       -- camera distance (yards) counted as first person
Logic.MAX_ZOOM = 50

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

------------------------------------------------------------------ flipbooks

-- Texture coordinates of 1-based `frame` in a sheet of `columns` x `rows` cells (left to right, top to bottom).
---@return number left, number right, number top, number bottom
function Logic.CellTexCoords(frame, columns, rows)
    local index = frame - 1
    local column, row = index % columns, math.floor(index / columns)
    return column / columns, (column + 1) / columns, row / rows, (row + 1) / rows
end

-- Flipbook frame (1-based) for `progress` 0..1 through an animation of `frames` frames.
function Logic.FlipFrame(progress, frames)
    return clamp(1 + math.floor(clamp(progress, 0, 1) * frames), 1, frames)
end

------------------------------------------------------------------ cigarette state

---@class CigaretteState
---@field lit boolean
---@field progress number 0 (fresh) .. 1 (burned down)
---@field lightTime number|nil clock time it was lit
---@field dragTime number|nil clock time of the last drag
---@field visibleUntil number|nil after going out: shown until this time
---@field burnSeconds number

---@param saved? { lit: boolean, progress: number, burnSeconds: number }
---@return CigaretteState
function Logic.NewState(saved)
    saved = saved or {}
    return { lit = saved.lit and true or false, progress = clamp(saved.progress or 0, 0, 1),
             burnSeconds = saved.burnSeconds or Logic.BURN_SECONDS }
end

-- Lights the cigarette (a fresh one when the last burned down). Returns false when it was already lit.
function Logic.Light(state, now)
    if state.lit then return false end
    if state.progress >= 1 then state.progress = 0 end
    state.lit, state.lightTime, state.dragTime, state.visibleUntil = true, now, nil, nil
    return true
end

-- Puts it out; it stays on screen for HIDE_AFTER_OUT seconds so the last smoke can drift away.
function Logic.PutOut(state, now)
    if not state.lit then return false end
    state.lit, state.visibleUntil = false, now + Logic.HIDE_AFTER_OUT
    return true
end

-- Takes a drag: brighter ember, faster burn, an exhale afterwards. Returns false when not lit or mid-drag.
function Logic.Drag(state, now)
    if not state.lit then return false end
    if state.dragTime and now - state.dragTime < Logic.EXHALE_DELAY then return false end
    state.dragTime = now
    state.progress = math.min(1, state.progress + Logic.DRAG_BURN_SECONDS / state.burnSeconds)
    return true
end

-- Burns for `elapsed` seconds. Returns "burnedOut" on the step it reaches the filter.
function Logic.Advance(state, elapsed, now)
    if not state.lit then return nil end
    state.progress = math.min(1, state.progress + elapsed / state.burnSeconds)
    if state.progress >= 1 then
        state.lit, state.visibleUntil = false, now + Logic.HIDE_AFTER_OUT
        return "burnedOut"
    end
    return nil
end

-- Whether the cigarette is in hand (lit, or just put out).
function Logic.InHand(state, now)
    return state.lit or (state.visibleUntil ~= nil and now < state.visibleUntil)
end

-- Cigarette flipbook frame: 1 = unlit and fresh, 2..frames = burning down.
function Logic.CigaretteFrame(state, frames)
    if not state.lit and state.progress <= 0 then return 1 end
    return clamp(2 + math.floor(state.progress * (frames - 1)), 2, frames)
end

local function smooth(x) x = clamp(x, 0, 1); return x * x * (3 - 2 * x) end

-- Ember brightness 0..1.5: a slow flicker, a flare when lit, a strong glow while drawing.
function Logic.EmberBrightness(state, now)
    if not state.lit then return 0 end
    local brightness = 0.55 + 0.1 * math.sin(now * 2.1) + 0.06 * math.sin(now * 5.3 + 1.7)
    if state.lightTime then
        local since = now - state.lightTime
        if since < Logic.LIGHT_FLARE_SECONDS then brightness = brightness + 0.6 * (1 - since / Logic.LIGHT_FLARE_SECONDS) end
    end
    if state.dragTime then
        local since = now - state.dragTime
        if since < Logic.INHALE_SECONDS then
            brightness = brightness + 0.75 * smooth(since / Logic.INHALE_SECONDS)
        elseif since < Logic.INHALE_SECONDS + 1.5 then
            brightness = brightness + 0.75 * (1 - smooth((since - Logic.INHALE_SECONDS) / 1.5))
        end
    end
    return clamp(brightness, 0, 1.5)
end

-- True once per drag, on the first update after the exhale delay (the caller then spawns the exhale).
function Logic.ExhaleDue(state, now)
    if state.dragTime and not state.exhaled and now - state.dragTime >= Logic.EXHALE_DELAY then
        state.exhaled = true
        return true
    end
    if state.dragTime and now - state.dragTime < Logic.EXHALE_DELAY then state.exhaled = false end
    return false
end

------------------------------------------------------------------ smoke particles

---@class SmokeParticle
---@field kind "stream"|"puff"|"exhale"
---@field x number origin, S units from the overlay's top-left (y down)
---@field y number
---@field age number seconds
---@field life number seconds
---@field vx number S/s, right
---@field vy number S/s, up
---@field damping number 0 = constant speed; higher slows down faster
---@field size0 number S
---@field size1 number S
---@field alpha number
---@field spin number radians/s
---@field swayAmplitude number S
---@field swayFrequency number rad/s
---@field swayPhase number

-- Particle kinds: the thin stream off a resting cigarette, the puff of lighting it, and an exhale.
local KINDS = {
    stream = { life = { 2.6, 3.6 }, vx = { -0.01, 0.025 }, vy = { 0.09, 0.13 }, damping = 0,
               size0 = { 0.05, 0.08 }, size1 = { 0.30, 0.45 }, alpha = { 0.35, 0.55 }, spin = { -0.6, 0.6 },
               sway = { 0.01, 0.03 } },
    puff = { life = { 1.8, 2.6 }, vx = { -0.04, 0.06 }, vy = { 0.12, 0.2 }, damping = 0.8,
             size0 = { 0.12, 0.18 }, size1 = { 0.55, 0.8 }, alpha = { 0.55, 0.75 }, spin = { -1, 1 },
             sway = { 0.01, 0.02 } },
    exhale = { life = { 2.2, 3.2 }, vx = { -0.18, 0.18 }, vy = { 0.45, 0.7 }, damping = 1.3,
               size0 = { 0.3, 0.45 }, size1 = { 1.3, 1.9 }, alpha = { 0.4, 0.6 }, spin = { -0.8, 0.8 },
               sway = { 0.02, 0.05 } },
}
Logic.PARTICLE_KINDS = KINDS

---@param kind "stream"|"puff"|"exhale"
---@param x number
---@param y number
---@param random fun(): number 0..1
---@return SmokeParticle
function Logic.NewParticle(kind, x, y, random)
    local spec = KINDS[kind]
    local function pick(range) return range[1] + (range[2] - range[1]) * random() end
    return { kind = kind, x = x, y = y, age = 0, life = pick(spec.life), vx = pick(spec.vx), vy = pick(spec.vy),
             damping = spec.damping, size0 = pick(spec.size0), size1 = pick(spec.size1), alpha = pick(spec.alpha),
             spin = pick(spec.spin), swayAmplitude = pick(spec.sway), swayFrequency = 1 + random() * 1.5,
             swayPhase = random() * math.pi * 2 }
end

-- Distance travelled after `age` seconds at speed `speed` with exponential slow-down `damping`.
local function travelled(speed, damping, age)
    if damping <= 0 then return speed * age end
    return speed * (1 - math.exp(-damping * age)) / damping
end

---@class ParticlePose
---@field x number centre, S units from the overlay's top-left (y down)
---@field y number
---@field size number S
---@field alpha number
---@field frame integer smoke flipbook frame
---@field rotation number radians
---@field done boolean

---@param particle SmokeParticle
---@param frames integer smoke flipbook frames
---@param wind number S/s, sideways drift added to every particle
---@return ParticlePose
function Logic.ParticlePose(particle, frames, wind)
    local age, life = particle.age, particle.life
    if age >= life then return { x = particle.x, y = particle.y, size = 0, alpha = 0, frame = frames, rotation = 0, done = true } end
    local progress = age / life
    local sway = particle.swayAmplitude * math.sin(particle.swayPhase + age * particle.swayFrequency) * math.min(1, age)
    local x = particle.x + travelled(particle.vx, particle.damping, age) + (wind or 0) * age + sway
    local y = particle.y - travelled(particle.vy, particle.damping, age)
    local grow = 1 - (1 - progress) ^ 2                       -- grows fast, then slowly
    local size = particle.size0 + (particle.size1 - particle.size0) * grow
    local alpha = particle.alpha * math.min(1, (1 - progress) * 3)   -- the flipbook fades too; this ends it cleanly
    return { x = x, y = y, size = size, alpha = alpha, frame = Logic.FlipFrame(progress, frames),
             rotation = particle.spin * age, done = false }
end

------------------------------------------------------------------ hand sway

-- Offset of the cigarette (S units) from breathing and walking.
---@param time number
---@param speed number yards/s (7 = running)
---@return number dx, number dy
function Logic.Sway(time, speed)
    local moving = clamp(speed / 7, 0, 1.5)
    local dx = 0.004 * math.sin(time * 0.7) + 0.012 * moving * math.sin(time * 5.5)
    local dy = 0.006 * math.sin(time * 0.9 + 1) + 0.010 * moving * math.abs(math.sin(time * 5.5))
    return dx, dy
end

-- Lag while turning: eases `current` (S units) toward an offset against the turn rate (radians/s).
function Logic.TurnLag(current, turnRate, elapsed)
    local target = clamp(-turnRate * 0.03, -0.08, 0.08)
    local blend = 1 - math.exp(-8 * elapsed)
    return current + (target - current) * blend
end

------------------------------------------------------------------ dancer

Logic.DANCE_ANIMATION = 69        -- AnimationData: EmoteDance
Logic.DANCER_SCALE_MIN, Logic.DANCER_SCALE_MAX = 0.3, 3

function Logic.ClampDancerScale(scale)
    return clamp(tonumber(scale) or 1, Logic.DANCER_SCALE_MIN, Logic.DANCER_SCALE_MAX)
end

------------------------------------------------------------------ first person

-- Camera distance estimate for clients without GetCameraZoom: follows CameraZoomIn / CameraZoomOut calls.
---@class ZoomTracker
---@field distance number

---@param start number
---@return ZoomTracker
function Logic.NewZoomTracker(start) return { distance = start or 15 } end

function Logic.ZoomIn(tracker, increment)
    tracker.distance = math.max(0, tracker.distance - (tonumber(increment) or 1))
end

function Logic.ZoomOut(tracker, increment)
    tracker.distance = math.min(Logic.MAX_ZOOM, tracker.distance + (tonumber(increment) or 1))
end

function Logic.IsFirstPerson(distance, threshold)
    return distance ~= nil and distance <= (threshold or Logic.ZOOM_THRESHOLD)
end

---@class VisibilityInput
---@field inHand boolean
---@field mode "auto"|"always"
---@field firstPerson boolean
---@field dead boolean
---@field taxi boolean
---@field vehicle boolean
---@field cinematic boolean
---@field moving boolean move mode (/cig move) always shows it

function Logic.ShouldShow(input)
    if input.moving then return true end
    if not input.inHand then return false end
    if input.dead or input.taxi or input.vehicle or input.cinematic then return false end
    return input.mode == "always" or input.firstPerson
end
