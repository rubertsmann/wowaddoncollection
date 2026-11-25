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
---@field camera number camera distance scale
---@field facing number radians
---@field afterLoad fun(model: table)|nil runs after every (re)load, before the animation is set again

local modelStates = setmetatable({}, { __mode = "k" })

-- The helper's memory of `model` (created on first use).
---@param model table
---@return CompanionModelState
function CompanionModel.StateOf(model)
    local state = modelStates[model]
    if not state then
        state = { loaded = false, camera = 1, facing = 0 }
        modelStates[model] = state
    end
    return state
end
local stateOf = CompanionModel.StateOf

-- Creates a model frame (PlayerModel).
---@param parent table
---@param width number
---@param height number
---@param options? { camera: number, facing: number, afterLoad: fun(model: table) }
---@return table model
function CompanionModel.Create(parent, width, height, options)
    local model = CreateFrame("PlayerModel", nil, parent)
    model:SetSize(width, height)
    if model.SetKeepModelOnHide then pcall(model.SetKeepModelOnHide, model, true) end
    local state = stateOf(model)
    state.camera = options and options.camera or 1
    state.facing = options and options.facing or 0
    state.afterLoad = options and options.afterLoad
    pcall(model.SetScript, model, "OnModelLoaded", function(self) CompanionModel.Frame(self) end)
    return model
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
        state.shownKey, state.loaded = nil, false
        return false
    end
    local key = tostring(creature.npc) .. ":" .. tostring(creature.disp)
    if state.shownKey == key then return state.loaded end
    state.shownKey = key
    local ok = false
    if (tonumber(creature.disp) or 0) > 0 and model.SetDisplayInfo then ok = pcall(model.SetDisplayInfo, model, creature.disp) end
    if not ok and model.SetCreature and creature.npc then ok = pcall(model.SetCreature, model, creature.npc) end
    state.loaded = ok and true or false
    if ok then CompanionModel.Frame(model) end
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
