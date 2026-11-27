local addonName, addon = ...

-- A small model helper for the games: load a creature model (display id, else the creature id), keep it framed, play the
-- first animation of a list the model has, and fall back to a plain texture when nothing loads. Every model call is
-- guarded: model frames differ between clients. What the helper remembers per model lives in a side table, not on the
-- frame.
---@class CompanionModelModule
local CompanionModel = {}
addon.CompanionModel = CompanionModel

-- AnimationData ids, first one the model has wins
CompanionModel.ANIMATION = {
    stand = { 0 },
    ready = { 26, 0 },
    run = { 5, 4, 0 },                    -- Run, Walk
    jump = { 38, 37, 5 },                 -- Jump, JumpStart
    attack = { 16, 17, 18, 19, 0 },       -- AttackUnarmed, Attack1H, Attack2H, Attack2HL
    hurt = { 9, 8, 0 },                   -- CombatWound, StandWound
}

---@class CompanionModelState
---@field shownKey string|nil "npc:display" of the loaded creature
---@field loaded boolean
---@field animation integer|nil the animation playing
---@field camera number camera distance scale (the padding included)
---@field pad number how much larger the frame is than the space the creature is drawn in
---@field facing number radians
---@field afterLoad fun(model: table)|nil runs after every (re)load, before the animation is set again
---@field rendered boolean the client drew the loaded model (OnModelLoaded fired or it reports a model file)
---@field fallback table|nil a child frame with an icon, shown until the model is drawn
---@field fitDistance number|nil the camera distance the client chose to fit the drawn model (FitDistance)
---@field fitKey string|nil the creature `fitDistance` belongs to

local modelStates = setmetatable({}, { __mode = "k" })
-- every model made here, so a change of the window's scale can frame them all again
local models = setmetatable({}, { __mode = "k" })

-- The helper's memory of `model` (created on first use).
---@param model table
---@return CompanionModelState
function CompanionModel.StateOf(model)
    local state = modelStates[model]
    if not state then
        state = { loaded = false, camera = 1, facing = 0, rendered = false }
        modelStates[model] = state
    end
    return state
end
local stateOf = CompanionModel.StateOf

-- True once the client has drawn the loaded model: OnModelLoaded fired, or the model reports its file.
---@param model table
---@return boolean
function CompanionModel.IsRendered(model)
    local state = stateOf(model)
    if state.rendered then return true end
    if state.loaded and model.GetModelFileID then
        local ok, fileID = pcall(model.GetModelFileID, model)
        if ok and type(fileID) == "number" and fileID > 0 then state.rendered = true end
    end
    return state.rendered
end

---@param model table
local function updateFallback(model)
    local fallback = stateOf(model).fallback
    if fallback then fallback:SetShown(not CompanionModel.IsRendered(model)) end
end

-- Sets the fallback icon (mirrored for a creature facing left).
---@param model table
---@param icon string
---@param mirror? boolean
function CompanionModel.SetFallbackIcon(model, icon, mirror)
    local fallback = stateOf(model).fallback
    if not fallback then return end
    addon.UIHelpers.SetTextureOr(fallback.icon, icon, { 0.6, 0.45, 0.25 })
    if mirror then fallback.icon:SetTexCoord(0.92, 0.08, 0.08, 0.92) else fallback.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

-- Creates a model frame (PlayerModel). With `options.fallback` an icon stands in until the model is drawn (a client or
-- a simulator that draws no models, or a creature it cannot load).
---@param parent table
---@param width number
---@param height number
-- `options.pad` makes the frame that much larger and the camera that much further out: the creature is drawn at the same
-- size, but a big one has room around it instead of being cut off at the frame's edge. Callers place the frame by its
-- centre (`width` x `height` is the space the creature is drawn in).
---@param options? { camera: number, pad: number, facing: number, afterLoad: fun(model: table), fallback: { icon: string, size: number, y: number, mirror: boolean } }
---@return table model
function CompanionModel.Create(parent, width, height, options)
    local model = CreateFrame("PlayerModel", nil, parent)
    local pad = options and options.pad or 1
    model:SetSize(width * pad, height * pad)
    models[model] = true
    if model.SetKeepModelOnHide then pcall(model.SetKeepModelOnHide, model, true) end
    local state = stateOf(model)
    state.pad = pad
    state.camera = (options and options.camera or 1) * pad
    state.facing = options and options.facing or 0
    state.afterLoad = options and options.afterLoad
    local fallbackOptions = options and options.fallback
    if fallbackOptions then
        local fallback = CreateFrame("Frame", nil, model)
        fallback:SetAllPoints()
        fallback.icon = fallback:CreateTexture(nil, "ARTWORK")
        fallback.icon:SetSize(fallbackOptions.size, fallbackOptions.size)
        fallback.icon:SetPoint("BOTTOM", model, "BOTTOM", 0, (fallbackOptions.y or 0) + (pad - 1) * height / 2)
        state.fallback = fallback
        CompanionModel.SetFallbackIcon(model, fallbackOptions.icon, fallbackOptions.mirror)
        fallback:SetScript("OnUpdate", function() updateFallback(model) end)
    end
    pcall(model.SetScript, model, "OnModelLoaded", function(self)
        stateOf(self).rendered = true
        updateFallback(self)
        CompanionModel.Frame(self)
    end)
    -- the window may have been scaled while the model was hidden
    if model.HookScript then pcall(model.HookScript, model, "OnShow", function(self) CompanionModel.Refresh(self) end) end
    return model
end

-- Frames a shown, loaded model again: the client fits a model to its frame when it is loaded, so after the frame's
-- drawn size changed (the window was scaled) the camera is refreshed and the framing re-applied.
---@param model table
function CompanionModel.Refresh(model)
    local state = stateOf(model)
    if not state.loaded or not model:IsShown() then return end
    if model.RefreshCamera then pcall(model.RefreshCamera, model) end
    CompanionModel.Frame(model)
end

-- Frames every shown game model again (the window's scale changed).
function CompanionModel.RefreshAll()
    for model in pairs(models) do CompanionModel.Refresh(model) end
end

-- The camera distance the client chose to fit the drawn creature (it grows with the creature's size), measured once per
-- creature while the client's own camera is in use. Nil until the model is drawn or when the client cannot tell.
---@param model table
---@return number|nil distance
---@return number tx, number ty, number tz the point the camera looks at
function CompanionModel.FitDistance(model)
    local state = stateOf(model)
    if state.fitKey == state.shownKey and state.fitDistance then
        return state.fitDistance, state.fitTarget[1], state.fitTarget[2], state.fitTarget[3]
    end
    if not state.shownKey or not CompanionModel.IsRendered(model) then return nil, 0, 0, 0 end
    -- back to the client's own camera (a custom one may still be current), framed as Frame does
    if model.SetCamera then pcall(model.SetCamera, model, 0) end
    if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
    if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, state.camera) end
    local function numbers(method)
        if not model[method] then return nil end
        local ok, x, y, z = pcall(model[method], model)
        if ok and type(x) == "number" and type(y) == "number" and type(z) == "number" then return x, y, z end
        return nil
    end
    local tx, ty, tz = numbers("GetCameraTarget")
    if not tx then tx, ty, tz = 0, 0, 0 end
    local distance
    if model.GetCameraDistance then
        local ok, value = pcall(model.GetCameraDistance, model)
        if ok and type(value) == "number" then distance = value end
    end
    if not distance then
        local px, py, pz = numbers("GetCameraPosition")
        if px then distance = math.sqrt((px - tx) ^ 2 + (py - ty) ^ 2 + (pz - tz) ^ 2) end
    end
    -- nothing usable (0, NaN, infinite): leave it to the caller's default
    if not distance or distance ~= distance or distance <= 0.05 or distance > 1000 then return nil, 0, 0, 0 end
    state.fitKey, state.fitDistance, state.fitTarget = state.shownKey, distance, { tx, ty, tz }
    return distance, tx, ty, tz
end

-- Re-applies the framing, the facing and the animation (a load resets them).
---@param model table
function CompanionModel.Frame(model)
    local state = stateOf(model)
    if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
    if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
    if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, state.camera) end
    if model.SetFacing then pcall(model.SetFacing, model, state.facing) end
    if state.afterLoad then state.afterLoad(model) end
    if state.animation ~= nil and model.SetAnimation then pcall(model.SetAnimation, model, state.animation) end
end

-- Loads `creature` ({ npc, disp }) unless it is already shown. Returns true when the client accepted it.
---@param model table
---@param creature { npc: integer, disp: integer }|nil
---@return boolean loaded
function CompanionModel.Load(model, creature)
    if not model then return false end
    local state = stateOf(model)
    if not creature then
        if model.ClearModel then pcall(model.ClearModel, model) end
        state.shownKey, state.loaded, state.rendered = nil, false, false
        updateFallback(model)
        return false
    end
    local key = tostring(creature.npc) .. ":" .. tostring(creature.disp)
    if state.shownKey == key then return state.loaded end
    state.shownKey, state.rendered = key, false
    local ok = false
    if (tonumber(creature.disp) or 0) > 0 and model.SetDisplayInfo then ok = pcall(model.SetDisplayInfo, model, creature.disp) end
    if not ok and model.SetCreature and creature.npc then ok = pcall(model.SetCreature, model, creature.npc) end
    state.loaded = ok and true or false
    if ok then CompanionModel.Frame(model) end
    updateFallback(model)
    return state.loaded
end

-- Plays the first animation of `candidates` the model has (the first when the client cannot tell). It loops until the
-- next call. The same animation again does nothing unless `restart`.
---@param model table
---@param candidates integer[]
---@param restart? boolean
function CompanionModel.Play(model, candidates, restart)
    if not model or not model.SetAnimation or not candidates then return end
    local state = stateOf(model)
    local chosen = candidates[1]
    if model.HasAnimation then
        chosen = candidates[#candidates]
        for _, animationID in ipairs(candidates) do
            local ok, has = pcall(model.HasAnimation, model, animationID)
            if ok and has then chosen = animationID break end
        end
    end
    if state.animation == chosen and not restart then return end
    state.animation = chosen
    pcall(model.SetAnimation, model, chosen)
end

---@param model table
---@param facing number radians
function CompanionModel.Face(model, facing)
    stateOf(model).facing = facing
    if model.SetFacing then pcall(model.SetFacing, model, facing) end
end
