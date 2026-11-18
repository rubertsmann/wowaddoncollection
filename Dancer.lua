local addonName, addon = ...

-- A dancing night elf on a small stage with a pole behind her, in a window you can move, resize and scale.
--   unlocked: left-drag moves, the corner grip resizes, the mouse wheel scales, right-drag turns the dancer
--   locked:   click-through (the mouse goes to the game)
-- Layers (back to front): stage + pole on the window frame, the 3D model on a child frame above them.
-- The model is the game's own night elf (addons cannot load their own 3D models), see Dancer.ApplyLook.
local Dancer = {}
addon.Dancer = Dancer

local Logic = addon.Logic
local TEXTURES = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local NIGHT_ELF_RACE = 4
local FEMALE_MODEL_FILE = 921844      -- character/nightelf/female/nightelffemale_hd.m2
local MALE_MODEL_FILE = 974343        -- character/nightelf/male/nightelfmale_hd.m2

local widgets = {}
Dancer.widgets = widgets

local function settings()
    FpvCigaretteDB.dancer = FpvCigaretteDB.dancer or {}
    return FpvCigaretteDB.dancer
end

local function log(message, fields) addon.Log.Write("dancer", message, fields) end

------------------------------------------------------------------ model

local function playDance()
    local model = widgets.model
    local ok, problem = pcall(model.SetAnimation, model, Logic.DANCE_ANIMATION)
    if not ok then addon.Log.Once("danceAnimation", "dancer", "SetAnimation failed", { error = tostring(problem) }) end
end

-- Night elf NPC appearances for a look ("elf" = women, "elfmale" = men), see Displays.lua.
local function displayList(look) return look == "elfmale" and addon.Displays.male or addon.Displays.female end

-- The race swap of the "custom" look must wait until the player model has loaded: swapping earlier leaves the
-- skin untextured (white) on this client.
local function applyCustomRace()
    local model = widgets.model
    widgets.pendingCustomRace = nil
    local ok, problem = pcall(model.SetCustomRace, model, NIGHT_ELF_RACE, 1)
    log("SetCustomRace after load", { ok = ok, error = not ok and tostring(problem) or nil })
end

local function onModelLoaded()
    if widgets.pendingCustomRace then applyCustomRace() end
    playDance()
end

-- Sets who dances. look:
--   "elf" / "elfmale"  a night elf NPC appearance (textures baked in); /cig dance next picks another outfit
--   "id"               a display ID of your choice (/cig dance id <n>)
--   "player"           your own character with its gear
--   "custom"           your character turned into a night elf woman (SetCustomRace; experimental)
--   "file"             the bare night elf model file (untextured: only for comparison)
function Dancer.ApplyLook(look)
    local model, saved = widgets.model, settings()
    pcall(model.ClearModel, model)
    local fields = { look = look }
    if look == "player" then
        model:SetUnit("player")
    elseif look == "custom" then
        model:SetUnit("player")
        widgets.pendingCustomRace = true
        -- fallback when this client fires no OnModelLoaded
        if C_Timer then C_Timer.After(0.5, function() if widgets.pendingCustomRace then applyCustomRace(); playDance() end end) end
    elseif look == "file" then
        model:SetModel(FEMALE_MODEL_FILE)
        fields.file = FEMALE_MODEL_FILE
    else
        local displayId
        if look == "id" then
            displayId = saved.displayId
        else
            local list = displayList(look)
            local index = ((saved[look .. "Index"] or 1) - 1) % #list + 1
            displayId, fields.index = list[index], index
        end
        local ok, problem = pcall(model.SetDisplayInfo, model, displayId)
        fields.display, fields.ok, fields.error = displayId, ok, not ok and tostring(problem) or nil
    end
    pcall(model.SetFacing, model, saved.facing or 0.35)
    playDance()
    log("look applied", fields)
end

-- Next (step 1) or previous (step -1) outfit of the current elf look. Returns index, count, display ID.
function Dancer.Cycle(step)
    local saved = settings()
    local look = (saved.look == "elfmale") and "elfmale" or "elf"
    local list = displayList(look)
    local index = ((saved[look .. "Index"] or 1) - 1 + step) % #list + 1
    saved[look .. "Index"], saved.look = index, look
    Dancer.ApplyLook(look)
    return index, #list, list[index]
end

function Dancer.SetDisplayId(displayId)
    settings().displayId, settings().look = displayId, "id"
    Dancer.ApplyLook("id")
end

------------------------------------------------------------------ layout

local function layout()
    local frame, saved = widgets.frame, settings()
    local scale = Logic.ClampDancerScale(saved.scale or 1)
    -- saved x/y are UIParent units; SetPoint offsets are in the frame's own (scaled) units
    local x = saved.x or UIParent:GetWidth() * 0.8
    local y = saved.y or UIParent:GetHeight() * 0.35
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    frame:SetSize(saved.width or 220, saved.height or 320)
end

local function placeProps()
    local frame = widgets.frame
    local width, height = frame:GetWidth(), frame:GetHeight()
    local stageHeight = math.max(16, width * 0.25)
    widgets.stage:SetSize(width * 0.95, stageHeight)
    widgets.stage:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    widgets.pole:SetSize(math.max(6, height * 0.035), height - stageHeight * 0.45)
    widgets.pole:SetPoint("BOTTOM", frame, "BOTTOM", 0, stageHeight * 0.45)
end

-- Saves where the window is (centre, in UIParent coordinates at scale 1) and its size.
local function savePlacement()
    local frame, saved = widgets.frame, settings()
    local x, y = frame:GetCenter()
    local scale = frame:GetScale()
    saved.x, saved.y = x * scale, y * scale
    saved.width, saved.height = frame:GetWidth(), frame:GetHeight()
end

------------------------------------------------------------------ build

local function build()
    local frame = CreateFrame("Frame", addonName .. "Dancer", UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(80, 120, 1200, 1600)
    elseif frame.SetMinResize then frame:SetMinResize(80, 120); frame:SetMaxResize(1200, 1600) end
    frame:SetClampedToScreen(true)
    frame:Hide()
    widgets.frame = frame

    local border = frame:CreateTexture(nil, "BACKGROUND", nil, -8)   -- only while unlocked
    border:SetAllPoints()
    border:SetColorTexture(0.6, 0.3, 1, 0.12)
    widgets.border = border

    local pole = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    pole:SetTexture(TEXTURES .. "pole")
    widgets.pole = pole
    local stage = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    stage:SetTexture(TEXTURES .. "stage")
    widgets.stage = stage

    local model = CreateFrame("DressUpModel", nil, frame)
    model:SetAllPoints()
    model:SetFrameLevel(frame:GetFrameLevel() + 2)
    if model.SetKeepModelOnHide then model:SetKeepModelOnHide(true) end
    -- the model resets to its stand animation on load and on show: start the dance again
    pcall(model.SetScript, model, "OnModelLoaded", onModelLoaded)
    model:SetScript("OnShow", playDance)
    widgets.model = model

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(model:GetFrameLevel() + 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePlacement()
        log("resized", { width = frame:GetWidth(), height = frame:GetHeight() })
    end)
    widgets.grip = grip

    -- mouse on the model frame (it is on top): left-drag moves, right-drag turns, wheel scales
    model:RegisterForDrag("LeftButton")
    model:SetScript("OnDragStart", function() frame:StartMoving() end)
    model:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); savePlacement() end)
    model:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then widgets.turnFrom = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            widgets.turnFrom = nil
            settings().facing = model:GetFacing()
        end
    end)
    model:SetScript("OnUpdate", function()
        if not widgets.turnFrom then return end
        local cursor = GetCursorPosition()
        model:SetFacing(model:GetFacing() + (cursor - widgets.turnFrom) * 0.02)
        widgets.turnFrom = cursor
    end)
    model:SetScript("OnMouseWheel", function(_, delta)
        Dancer.SetScale((settings().scale or 1) + delta * 0.1)
    end)

    frame:SetScript("OnSizeChanged", placeProps)
end

------------------------------------------------------------------ actions (Commands.lua)

function Dancer.SetLocked(locked)
    settings().locked = locked
    widgets.model:EnableMouse(not locked)
    widgets.model:EnableMouseWheel(not locked)
    widgets.border:SetShown(not locked)
    widgets.grip:SetShown(not locked)
end

function Dancer.SetScale(scale)
    local saved = settings()
    local x, y = widgets.frame:GetCenter()
    local oldScale = widgets.frame:GetScale()
    saved.scale = Logic.ClampDancerScale(scale)
    if x then saved.x, saved.y = x * oldScale, y * oldScale end   -- keep the centre where it is
    layout()
end

function Dancer.SetShown(shown)
    settings().shown = shown
    widgets.frame:SetShown(shown)
    log(shown and "shown" or "hidden")
end

function Dancer.Toggle() Dancer.SetShown(not widgets.frame:IsShown()) end

function Dancer.SetLook(look)
    settings().look = look
    Dancer.ApplyLook(look)
end

function Dancer.Reset()
    local saved = settings()
    saved.x, saved.y, saved.width, saved.height, saved.scale, saved.facing = nil, nil, nil, nil, nil, nil
    layout()
    placeProps()
    pcall(widgets.model.SetFacing, widgets.model, 0.35)
end

function Dancer.IsLocked() return settings().locked and true or false end

------------------------------------------------------------------ boot

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    local ok, problem = pcall(function()
        build()
        layout()
        placeProps()
        local saved = settings()
        Dancer.SetLocked(saved.locked or false)
        Dancer.ApplyLook(saved.look or "elf")
        widgets.frame:SetShown(saved.shown or false)
    end)
    if not ok then addon.Log.Write("error", "dancer boot failed", { error = tostring(problem) }) end
end)
