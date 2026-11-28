local addonName, addon = ...

-- Every 3D creature model of the addon: ModelView.New(parent, options) makes a view; the view loads a creature (display
-- id, else NPC id), frames it, plays poses and one-off animations and falls back to an icon until the client draws it.
-- The view's functions are bound to it and called with a dot (view.Show(creature), view.Play("attack")), its state is
-- plain fields, `view.frame` is the model frame for anchoring and effects. Every model call is guarded: model frames
-- differ between clients. No other file calls model frame methods for a shown model.
---@class ModelViewModule
local ModelView = {}
addon.ModelView = ModelView

-- AnimationData ids per pose or action: the first one the model has is played (ModelView.Pick)
ModelView.ANIMATION = {
    stand = { 0 },
    ready = { 26, 0 },                    -- ReadyUnarmed, Stand
    run = { 5, 4, 0 },                    -- Run, Walk
    jump = { 38, 37, 5 },                 -- Jump, JumpStart
    attack = { 16, 17, 18, 19, 0 },       -- AttackUnarmed, Attack1H, Attack2H, Attack2HL
    cast = { 52, 51, 16, 17 },            -- SpellCastOmni, SpellCastDirected, else an attack
    hurt = { 9, 8, 0 },                   -- CombatWound, StandWound
    critical = { 10, 9, 8 },              -- CombatCritical
    dodge = { 20, 11 },                   -- ParryUnarmed, ShuffleLeft
    stun = { 14, 9 },
    death = { 1 },
    dead = { 6 },                         -- lying dead
    feed = { 61, 74, 0 },
    water = { 61, 0 },
    pet = { 68, 67, 70, 74, 0 },
    sleep = { 71, 100, 0 },
    wake = { 4, 74, 0 },
    asleep = { 71, 100, 0 },
}

ModelView.EMOTE_SECONDS = 2.5   -- an emote plays this long, then the view goes back to its idle pose
ModelView.DEATH_SECONDS = 1.1   -- the death animation, then the lying pose
ModelView.LATE_FRAME_SECONDS = 0.3   -- clients without OnModelLoaded: framed once more after a reload
ModelView.ZOOM_LIMITS = { 0.6, 4 }
ModelView.ZOOM_STEP = 1.15
ModelView.zoomByNpc = {}        -- camera distance chosen with the mouse wheel, by NPC id (session only, every view)
ModelView.ambientForcedUntil = 0   -- clock: until then every companion view plays an ambient emote at once (dev)

-- Option sets several views share; `options.preset` names one, the view's own options win.
ModelView.PRESET = {
    -- a creature to look at (the AZEcaught views, the arena, the team dialog): full body, a bit farther than the
    -- client's own fit, turned a little; right-drag turns, the wheel zooms (remembered per NPC)
    portrait = { frameType = "DressUpModel", camera = 1.35, facing = 0.4, turn = true, zoom = true, zoomMemory = true },
}

---@class ModelViewFallback
---@field icon string
---@field size number
---@field y? number offset from the bottom of the drawn space
---@field mirror? boolean the creature faces left

---@class ModelViewOptions
---@field width number the space the creature is drawn in
---@field height number
---@field frameType? "PlayerModel"|"DressUpModel" default PlayerModel
---@field pad? number the frame is this much larger and the camera this much further out, so a big creature has room
---@field camera? number camera distance scale (default 1); the wheel's choice replaces it per NPC when `zoom`
---@field facing? number radians
---@field idle? string ANIMATION key of the resting pose (default "stand")
---@field companion? boolean the creature is a companion record: asleep pose while it sleeps, ambient emotes while awake
---@field turn? boolean right-drag turns the creature (until another one is shown)
---@field preset? string a ModelView.PRESET name the other options are added to
---@field zoom? boolean the mouse wheel zooms (into ModelView.zoomByNpc)
---@field zoomMemory? boolean the camera uses the distance chosen with the wheel for this NPC (in any view)
---@field fallback? ModelViewFallback an icon stands in until the model is drawn
---@field afterLoad? fun(view: ModelViewObject) runs after every framing, before the pose is set again
---@field area? string journal area (`caught.model.<area>`): loads and poses are journaled; nil: nothing is
---@field quietPoses? boolean journal the loads only (a view that plays an action every second)

---@class ModelViewObject
---@field frame table the model frame
---@field options ModelViewOptions
---@field creature table|nil the shown creature ({ npc, disp }, a companion record for companion views)
---@field shownKey string|nil "npc:display" of the loaded creature
---@field loaded boolean the client accepted the creature
---@field rendered boolean the client drew it (OnModelLoaded fired or it reports a model file)
---@field animation integer|nil the looping animation
---@field facing number radians
---@field dead boolean
---@field token integer a newer pose voids older timers
---@field busyUntil number|nil clock: an emote plays
---@field asleepShown boolean|nil the asleep state the pose was chosen for
---@field nextAmbientAt number|nil clock of the next ambient emote
---@field ambientForcedAt number|nil the forced window already used
---@field fallback table|nil the stand-in icon frame
---@field fitKey string|nil
---@field fitDistance number|nil
---@field fitTarget number[]|nil
---@field zoomDistance number|nil the wheel's choice for this view's creature (views without zoomMemory)

-- every view, so a change of the window's scale can frame them all again (a frame lives for the session, and its
-- scripts hold its view: an entry is never freed, so make a view once per place, not per call)
local views = setmetatable({}, { __mode = "k" })

---@param frame table
---@param method string
---@return boolean ok
---@return any result
local function call(frame, method, ...)
    local handler = frame[method]
    if not handler then return false, nil end
    return pcall(handler, frame, ...)
end

local function clock() return addon.Api.Clock() end

---@param view ModelViewObject
---@param level string
---@param message string
---@param details table
local function journal(view, level, message, details)
    if view.options.area then addon.AzeCaught.Journal(level, "model." .. view.options.area, message, details) end
end

-- The first candidate the model has; the first when the client cannot tell; the last when it has none of them.
---@param frame table
---@param animation string|integer[] an ANIMATION key or a candidate list
---@return integer|nil animationID
function ModelView.Pick(frame, animation)
    local candidates = type(animation) == "table" and animation or ModelView.ANIMATION[animation]
    if not candidates or #candidates == 0 then return nil end
    if not frame.HasAnimation then return candidates[1] end
    for _, animationID in ipairs(candidates) do
        local ok, has = pcall(frame.HasAnimation, frame, animationID)
        if ok and has then return animationID end
    end
    return candidates[#candidates]
end

-- The camera distance after `delta` wheel steps from `current` (up = closer), within ZOOM_LIMITS.
---@param current number
---@param delta number
---@return number
function ModelView.ZoomStep(current, delta)
    return addon.Utility.Clamp(delta > 0 and current / ModelView.ZOOM_STEP or current * ModelView.ZOOM_STEP,
        ModelView.ZOOM_LIMITS[1], ModelView.ZOOM_LIMITS[2])
end

---@param view ModelViewObject
---@return number
local function cameraDistance(view)
    local npcID = view.creature and view.creature.npc
    local chosen = view.options.zoomMemory and npcID and ModelView.zoomByNpc[npcID] or view.zoomDistance
    return (chosen or view.options.camera or 1) * (view.options.pad or 1)
end

---@param view ModelViewObject
---@return string key
local function idlePose(view)
    if view.options.companion and view.creature and view.creature.asleep ~= nil then return "asleep" end
    return view.options.idle or "stand"
end

-- True once the client has drawn the loaded model: OnModelLoaded fired, or the model reports its file.
---@param view ModelViewObject
---@return boolean
function ModelView.IsRendered(view)
    if view.rendered then return true end
    if view.loaded then
        local ok, fileID = call(view.frame, "GetModelFileID")
        if ok and type(fileID) == "number" and fileID > 0 then view.rendered = true end
    end
    return view.rendered
end

---@param view ModelViewObject
local function updateFallback(view)
    if view.fallback then view.fallback:SetShown(not ModelView.IsRendered(view)) end
end

-- Sets the stand-in icon (mirrored for a creature facing left).
---@param view ModelViewObject
---@param icon string
---@param mirror? boolean
function ModelView.SetFallbackIcon(view, icon, mirror)
    local fallback = view.fallback
    if not fallback then return end
    addon.UIHelpers.SetTextureOr(fallback.icon, icon, { 0.6, 0.45, 0.25 })
    if mirror then fallback.icon:SetTexCoord(0.92, 0.08, 0.08, 0.92) else fallback.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

-- Plays `animation` and loops it until the next call. The same animation again does nothing unless `options.restart`.
-- `options.back`: back to the idle pose after that many seconds (a newer call voids it). A dead view plays nothing.
---@param view ModelViewObject
---@param animation string|integer[]
---@param options? { restart: boolean, back: number }
---@return integer|nil animationID played
function ModelView.Play(view, animation, options)
    if view.dead or not view.frame.SetAnimation then return nil end
    local animationID = ModelView.Pick(view.frame, animation)
    if animationID == nil then return nil end
    view.token = view.token + 1
    local token = view.token
    if view.animation ~= animationID or (options and options.restart) then
        view.animation = animationID
        call(view.frame, "SetAnimation", animationID)
    end
    local back = options and options.back
    if back and C_Timer and C_Timer.After then
        C_Timer.After(back, function()
            if view.token == token and not view.dead then ModelView.Idle(view, "after") end
        end)
    end
    return animationID
end

-- The resting pose now (the asleep pose for a sleeping companion); a pending "back to idle" timer is void.
---@param view ModelViewObject
---@param reason string
---@return integer|nil animationID
function ModelView.Idle(view, reason)
    view.busyUntil = nil
    view.asleepShown = view.creature ~= nil and view.creature.asleep ~= nil
    local pose = idlePose(view)
    local animationID = ModelView.Play(view, pose, { restart = true })
    if not view.options.quietPoses then
        journal(view, "DEBUG", "a pose was played", { reason = reason, pose = pose, animation = animationID })
    end
    return animationID
end

-- An emote, then the idle pose after EMOTE_SECONDS; no ambient emote meanwhile.
---@param view ModelViewObject
---@param animation string|integer[]
---@param reason string
---@return integer|nil animationID
function ModelView.Emote(view, animation, reason)
    local animationID = ModelView.Play(view, animation, { restart = true, back = ModelView.EMOTE_SECONDS })
    if animationID == nil then return nil end
    view.busyUntil = clock() + ModelView.EMOTE_SECONDS
    if view.options.quietPoses then return animationID end
    journal(view, "DEBUG", "an emote was played", { reason = reason, animation = animationID, hasCheck = view.frame.HasAnimation ~= nil })
    return animationID
end

-- The death once, then the lying pose; the view stays dead until Revive or another creature. True the first time.
---@param view ModelViewObject
---@return boolean
function ModelView.Die(view)
    if view.dead then return false end
    ModelView.Play(view, "death", { restart = true })
    view.dead = true
    local token = view.token
    if C_Timer and C_Timer.After then
        C_Timer.After(ModelView.DEATH_SECONDS, function()
            if not view.dead or view.token ~= token then return end
            local lying = ModelView.Pick(view.frame, "dead")
            if lying then view.animation = lying; call(view.frame, "SetAnimation", lying) end
        end)
    end
    return true
end

---@param view ModelViewObject
function ModelView.Revive(view)
    view.dead = false
    ModelView.Idle(view, "revive")
end

---@param view ModelViewObject
---@param facing number radians
function ModelView.Face(view, facing)
    view.facing = facing
    call(view.frame, "SetFacing", facing)
end

-- Re-applies the framing, the facing and the pose (a load resets them).
---@param view ModelViewObject
function ModelView.Frame(view)
    local frame = view.frame
    call(frame, "SetPortraitZoom", 0)
    call(frame, "SetPosition", 0, 0, 0)
    call(frame, "SetCamDistanceScale", cameraDistance(view))
    call(frame, "SetFacing", view.facing)
    if view.options.afterLoad then view.options.afterLoad(view) end
    if view.animation ~= nil then call(frame, "SetAnimation", view.animation)
    elseif view.loaded and frame.SetAnimation then ModelView.Idle(view, "framed") end
end

-- Frames a shown, loaded view again: the client fits a model to its frame when it loads, so after the drawn size
-- changed (the window was scaled, the frame was shown) the camera is refreshed first.
---@param view ModelViewObject
function ModelView.Refresh(view)
    if not view.loaded or not view.frame:IsShown() then return end
    call(view.frame, "RefreshCamera")
    ModelView.Frame(view)
end

-- Frames every shown view again (the window's scale changed).
function ModelView.RefreshAll()
    for view in pairs(views) do ModelView.Refresh(view) end
end

-- Shows `creature` ({ npc, disp }, or a companion record) unless it is already shown; nil clears the view. Returns
-- true when the client accepted it.
---@param view ModelViewObject
---@param creature table|nil
---@return boolean loaded
function ModelView.Show(view, creature)
    local frame = view.frame
    if not creature then
        call(frame, "ClearModel")
        view.creature, view.shownKey, view.loaded, view.rendered, view.animation = nil, nil, false, false, nil
        view.token, view.dead, view.busyUntil = view.token + 1, false, nil   -- pending timers are void
        updateFallback(view)
        return false
    end
    local key = tostring(creature.npc) .. ":" .. tostring(creature.disp)
    view.creature = creature
    if view.shownKey == key then
        if view.options.companion and view.asleepShown ~= (creature.asleep ~= nil) then
            ModelView.Idle(view, creature.asleep and "fellAsleep" or "wokeUp")
        end
        return view.loaded
    end
    view.shownKey, view.rendered, view.dead, view.animation, view.busyUntil, view.zoomDistance = key, false, false, nil, nil, nil
    view.token = view.token + 1
    if view.options.turn then view.facing = view.options.facing or 0 end
    call(frame, "ClearModel")
    local ok, problem, method = false, nil, "none"
    if (tonumber(creature.disp) or 0) > 0 and frame.SetDisplayInfo then
        ok, problem = call(frame, "SetDisplayInfo", creature.disp)
        method = "display"
    end
    if not ok and frame.SetCreature and creature.npc then
        ok, problem = call(frame, "SetCreature", creature.npc)
        method = "creature"
    end
    view.loaded = ok and true or false
    if ok then ModelView.Frame(view) end
    updateFallback(view)
    journal(view, ok and "DEBUG" or "WARNING", ok and "a model was loaded" or "a model could not be loaded",
        { npc = creature.npc, display = creature.disp, method = method, error = (not ok and problem) and tostring(problem) or nil,
          distance = cameraDistance(view) })
    return view.loaded
end

-- Forgets the shown creature, so the next Show loads it again.
---@param view ModelViewObject
function ModelView.Forget(view)
    view.shownKey = nil
end

-- Loads the shown creature again and plays the idle pose, then frames it once more a moment later (a frame that was
-- hidden comes back without its model; clients without OnModelLoaded need the late framing). A view that is not
-- visible (its tab is not open) only forgets: it loads on the next Show.
---@param view ModelViewObject
---@param reason string
function ModelView.Reload(view, reason)
    local creature = view.creature
    view.shownKey = nil
    if not creature or not view.frame:IsVisible() then return end
    ModelView.Show(view, creature)
    ModelView.Idle(view, reason)
    if C_Timer and C_Timer.After then
        C_Timer.After(ModelView.LATE_FRAME_SECONDS, function()
            if view.frame:IsVisible() and view.creature == creature then
                ModelView.Frame(view)
                ModelView.Idle(view, reason .. "Late")
            end
        end)
    end
end

-- The mouse wheel: closer (up) or farther, remembered for this NPC for the session.
---@param view ModelViewObject
---@param delta number
function ModelView.Zoom(view, delta)
    local npcID = view.creature and view.creature.npc
    local remembered = view.options.zoomMemory and npcID and ModelView.zoomByNpc[npcID] or view.zoomDistance
    local distance = ModelView.ZoomStep(remembered or view.options.camera or 1, delta)
    if view.options.zoomMemory and npcID then ModelView.zoomByNpc[npcID] = distance else view.zoomDistance = distance end
    call(view.frame, "SetCamDistanceScale", distance * (view.options.pad or 1))
end

-- Companion views: now and then an awake, visible companion plays a random emote it has (Model.IDLE_EMOTES), then
-- goes back to idle. Called from the views' refresh; the first one comes a while after the view was shown.
---@param view ModelViewObject
---@param now? number clock
function ModelView.Tick(view, now)
    local creature = view.creature
    if not view.options.companion or not creature or creature.asleep or view.dead or not view.frame:IsVisible() then
        view.nextAmbientAt = nil
        return
    end
    now = now or clock()
    if not view.nextAmbientAt then view.nextAmbientAt = now + addon.Model.IdleEmoteDelay(math.random) return end
    local forced = now < ModelView.ambientForcedUntil and view.ambientForcedAt ~= ModelView.ambientForcedUntil
    if (now < view.nextAmbientAt and not forced) or now < (view.busyUntil or 0) then return end
    if forced then view.ambientForcedAt = ModelView.ambientForcedUntil end
    view.nextAmbientAt = now + addon.Model.IdleEmoteDelay(math.random)
    local candidates = {}
    for _, animationID in ipairs(addon.Model.ShuffledIdleEmotes(math.random)) do
        local has = true
        if view.frame.HasAnimation then
            local ok, result = pcall(view.frame.HasAnimation, view.frame, animationID)
            has = ok and result and true or false
        end
        if has then candidates[#candidates + 1] = animationID end
    end
    if #candidates == 0 then return end
    candidates[#candidates + 1] = 0
    ModelView.Emote(view, candidates, "ambient")
end

-- Every companion view plays an ambient emote within a second (dev).
---@param now number clock
function ModelView.ForceAmbient(now)
    ModelView.ambientForcedUntil = now + 1
end

-- Whether the model has `animationID`: nil when the client cannot tell, "error" when the check failed.
---@param view ModelViewObject
---@param animationID integer
---@return boolean|nil|"error"
function ModelView.Has(view, animationID)
    if not view.frame.HasAnimation then return nil end
    local ok, has = pcall(view.frame.HasAnimation, view.frame, animationID)
    if not ok then return "error" end
    return has and true or false
end

-- the model frame methods `/gg caught model` reports
ModelView.CAPABILITIES = { "HasAnimation", "SetAnimation", "MakeCurrentCameraCustom", "SetCameraPosition", "SetCameraTarget",
    "SetCameraFacing", "SetPitch", "SetModelScale", "SetCamDistanceScale" }

-- "Method=true|false" for each of ModelView.CAPABILITIES on this client.
---@param view ModelViewObject
---@return string[]
function ModelView.Capabilities(view)
    local list = {}
    for _, name in ipairs(ModelView.CAPABILITIES) do list[#list + 1] = name .. "=" .. tostring(view.frame[name] ~= nil) end
    return list
end

-- Looks at the creature through a custom camera at `position` towards `target` ({ x, y, z }). True when the client
-- allowed it.
---@param view ModelViewObject
---@param position number[]
---@param target number[]
---@return boolean
function ModelView.LookFrom(view, position, target)
    local frame = view.frame
    if not (frame.MakeCurrentCameraCustom and frame.SetCameraPosition and frame.SetCameraTarget) then return false end
    return call(frame, "MakeCurrentCameraCustom") and call(frame, "SetCameraTarget", target[1], target[2], target[3])
        and call(frame, "SetCameraPosition", position[1], position[2], position[3]) or false
end

-- The camera distance the client chose to fit the drawn creature (it grows with the creature's size), measured once per
-- creature with the client's own camera. Nil until the model is drawn or when the client cannot tell.
---@param view ModelViewObject
---@return number|nil distance
---@return number tx, number ty, number tz the point the camera looks at
function ModelView.FitDistance(view)
    if view.fitKey == view.shownKey and view.fitDistance then
        return view.fitDistance, view.fitTarget[1], view.fitTarget[2], view.fitTarget[3]
    end
    if not view.shownKey or not ModelView.IsRendered(view) then return nil, 0, 0, 0 end
    local frame = view.frame
    -- back to the client's own camera (a custom one may still be current), framed as Frame does
    call(frame, "SetCamera", 0)
    call(frame, "SetPortraitZoom", 0)
    call(frame, "SetCamDistanceScale", cameraDistance(view))
    local function numbers(method)
        local ok, x, y, z = call(frame, method)
        if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then return x, y, z end
        return nil
    end
    local tx, ty, tz = numbers("GetCameraTarget")
    if not tx then tx, ty, tz = 0, 0, 0 end
    local okDistance, distance = call(frame, "GetCameraDistance")
    if not okDistance or type(distance) ~= "number" then distance = nil end
    if not distance then
        local px, py, pz = numbers("GetCameraPosition")
        if px then distance = math.sqrt((px - tx) ^ 2 + (py - ty) ^ 2 + (pz - tz) ^ 2) end
    end
    -- nothing usable (0, NaN, infinite): leave it to the caller's default
    if not distance or distance ~= distance or distance <= 0.05 or distance > 1000 then return nil, 0, 0, 0 end
    view.fitKey, view.fitDistance, view.fitTarget = view.shownKey, distance, { tx, ty, tz }
    return distance, tx, ty, tz
end

---@param view ModelViewObject
---@param fallbackOptions ModelViewFallback
local function buildFallback(view, fallbackOptions)
    local options, frame = view.options, view.frame
    local fallback = CreateFrame("Frame", nil, frame)
    fallback:SetAllPoints()
    fallback.icon = fallback:CreateTexture(nil, "ARTWORK")
    fallback.icon:SetSize(fallbackOptions.size, fallbackOptions.size)
    fallback.icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, (fallbackOptions.y or 0) + ((options.pad or 1) - 1) * options.height / 2)
    view.fallback = fallback
    ModelView.SetFallbackIcon(view, fallbackOptions.icon, fallbackOptions.mirror)
    fallback:SetScript("OnUpdate", function() updateFallback(view) end)
end

---@param view ModelViewObject
local function enableTurnAndZoom(view)
    local options, frame = view.options, view.frame
    frame:EnableMouse(true)
    if options.zoom then
        if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
        frame:SetScript("OnMouseWheel", function(_, delta) ModelView.Zoom(view, delta) end)
    end
    if not options.turn then return end
    local turnFrom
    frame:SetScript("OnMouseDown", function(_, button) if button == "RightButton" then turnFrom = GetCursorPosition() end end)
    frame:SetScript("OnMouseUp", function() turnFrom = nil end)
    frame:SetScript("OnUpdate", function()
        if not turnFrom then return end
        local cursorX = GetCursorPosition()
        ModelView.Face(view, view.facing + (cursorX - turnFrom) * 0.02)
        turnFrom = cursorX
    end)
end

-- `options` on top of its preset (a new table; the caller's stays as it is).
---@param options ModelViewOptions
---@return ModelViewOptions
function ModelView.Options(options)
    local merged = {}
    local preset = options.preset and assert(ModelView.PRESET[options.preset], "unknown model view preset " .. tostring(options.preset))
    for key, value in pairs(preset or {}) do merged[key] = value end
    for key, value in pairs(options) do merged[key] = value end
    return merged
end

-- A view on a new model frame. Callers place `view.frame` by its centre (`width` x `height` is the space the creature
-- is drawn in; with `pad` the frame is larger).
---@param parent table
---@param options ModelViewOptions
---@return ModelViewObject view
function ModelView.New(parent, options)
    options = ModelView.Options(options)
    local pad = options.pad or 1
    local frame = CreateFrame(options.frameType or "PlayerModel", nil, parent)
    frame:SetSize(options.width * pad, options.height * pad)
    local view = { frame = frame, options = options, loaded = false, rendered = false, facing = options.facing or 0,
        dead = false, token = 0 }
    views[view] = true
    call(frame, "SetKeepModelOnHide", true)
    if options.fallback then buildFallback(view, options.fallback) end
    call(frame, "SetScript", "OnModelLoaded", function()
        view.rendered = true
        updateFallback(view)
        ModelView.Frame(view)
    end)
    -- the window may have been scaled while the view was hidden
    if frame.HookScript then call(frame, "HookScript", "OnShow", function() ModelView.Refresh(view) end) end
    if options.turn or options.zoom then enableTurnAndZoom(view) end

    function view.Show(creature) return ModelView.Show(view, creature) end
    function view.Forget() return ModelView.Forget(view) end
    function view.Reload(reason) return ModelView.Reload(view, reason) end
    function view.Frame() return ModelView.Frame(view) end
    function view.Refresh() return ModelView.Refresh(view) end
    function view.Play(animation, playOptions) return ModelView.Play(view, animation, playOptions) end
    function view.Emote(animation, reason) return ModelView.Emote(view, animation, reason) end
    function view.Idle(reason) return ModelView.Idle(view, reason) end
    function view.Die() return ModelView.Die(view) end
    function view.Revive() return ModelView.Revive(view) end
    function view.Face(facing) return ModelView.Face(view, facing) end
    function view.Zoom(delta) return ModelView.Zoom(view, delta) end
    function view.Tick(now) return ModelView.Tick(view, now) end
    function view.Has(animationID) return ModelView.Has(view, animationID) end
    function view.Capabilities() return ModelView.Capabilities(view) end
    function view.LookFrom(position, target) return ModelView.LookFrom(view, position, target) end
    function view.IsRendered() return ModelView.IsRendered(view) end
    function view.FitDistance() return ModelView.FitDistance(view) end
    function view.SetFallbackIcon(icon, mirror) return ModelView.SetFallbackIcon(view, icon, mirror) end
    return view
end
