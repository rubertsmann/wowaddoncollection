local addonName, addon = ...

-- Screen overlay: the cigarette flipbook, the ember glow and a pool of smoke flipbook sprites. Rules live in Logic.lua;
-- this file only reads the game state and moves textures. Parented to WorldFrame so it stays when the UI is hidden
-- (Alt+Z), at BACKGROUND strata so every window draws above it.
--
--   base   anchored at the bottom of the screen, never sways; smoke sprites hang off it (smoke stays in the air
--          while the hand moves)
--   hand   child of base, moved by the sway / turn lag; holds the cigarette and the ember
local Overlay = {}
addon.Overlay = Overlay

local Logic, Geometry = addon.Logic, addon.Geometry
local TEXTURES = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local POOL_SIZE = 56
local STREAM_INTERVAL = 0.2       -- seconds between stream sprites
local EXHALE_SPRITES = 9
local CHECK_INTERVAL = 0.15       -- seconds between visibility checks
local MOUTH = { x = 0.42, y = 1.02 }   -- where exhaled smoke starts, S units (just below the bottom edge)

local widgets = { sprites = {}, free = {}, live = {} }
Overlay.widgets = widgets

local runtime = {
    state = nil,          ---@type CigaretteState
    zoom = Logic.NewZoomTracker(15),
    visible = false,
    moving = false,
    cinematic = false,
    clock = 0,
    nextStream = 0,
    nextCheck = 0,
    lagX = 0,
    lastFacing = nil,
    rotationWorks = nil,
}
Overlay.runtime = runtime

local function db() return FpvCigaretteDB end

local function now() return GetTime() end

-- S: the on-screen size of one cigarette cell (pixels in WorldFrame space).
local function cellSize()
    return WorldFrame:GetHeight() * 0.62 * (db().scale or 1)
end

------------------------------------------------------------------ zoom

-- Camera distance: the real one where the client has GetCameraZoom, else the tracked estimate.
function Overlay.CameraDistance()
    if GetCameraZoom then
        local ok, distance = pcall(GetCameraZoom)
        if ok and type(distance) == "number" then return distance end
    end
    return runtime.zoom.distance
end

local function hookZoom()
    local Log = addon.Log
    if CameraZoomIn then hooksecurefunc("CameraZoomIn", function(increment)
        Logic.ZoomIn(runtime.zoom, increment)
        Log.Debug("zoom", "CameraZoomIn", { increment = increment, estimate = runtime.zoom.distance })
    end) end
    if CameraZoomOut then hooksecurefunc("CameraZoomOut", function(increment)
        Logic.ZoomOut(runtime.zoom, increment)
        Log.Debug("zoom", "CameraZoomOut", { increment = increment, estimate = runtime.zoom.distance })
    end) end
    -- saved views jump the camera somewhere unknown: assume third person until the next zoom
    for _, name in ipairs({ "SetView", "ResetView" }) do
        if _G[name] then hooksecurefunc(name, function(view)
            runtime.zoom.distance = 15
            Log.Debug("zoom", name .. ": estimate reset to 15", { view = view })
        end) end
    end
end

-- "I am in first person now" for the estimate (/cig calibrate).
function Overlay.Calibrate()
    addon.Log.Write("zoom", "calibrated to first person", { estimateWas = runtime.zoom.distance })
    runtime.zoom.distance = 0
end

------------------------------------------------------------------ build

local function setRotation(texture, radians)
    if runtime.rotationWorks == false then return end
    local ok, problem = pcall(texture.SetRotation, texture, radians)
    if runtime.rotationWorks == nil then
        runtime.rotationWorks = ok
        addon.Log.Write("probe", ok and "Texture:SetRotation works" or "Texture:SetRotation failed, smoke will not spin",
            { error = not ok and tostring(problem) or nil })
    end
end

local function build()
    local base = CreateFrame("Frame", addonName .. "Base", WorldFrame)
    base:SetFrameStrata("BACKGROUND")
    base:SetFrameLevel(1)
    base:Hide()
    widgets.base = base

    local hand = CreateFrame("Frame", nil, base)
    hand:SetAllPoints()
    widgets.hand = hand

    local cigarette = hand:CreateTexture(nil, "ARTWORK", nil, 0)
    cigarette:SetTexture(TEXTURES .. "cigarette")
    cigarette:SetAllPoints()
    widgets.cigarette = cigarette

    local spill = hand:CreateTexture(nil, "ARTWORK", nil, 1)    -- wide, faint light around the tip
    spill:SetTexture(TEXTURES .. "ember")
    spill:SetBlendMode("ADD")
    widgets.spill = spill
    local ember = hand:CreateTexture(nil, "ARTWORK", nil, 2)
    ember:SetTexture(TEXTURES .. "ember")
    ember:SetBlendMode("ADD")
    widgets.ember = ember

    for index = 1, POOL_SIZE do
        local sprite = base:CreateTexture(nil, "OVERLAY")
        sprite:SetTexture(TEXTURES .. "smoke")
        sprite:Hide()
        widgets.sprites[index] = sprite
        widgets.free[#widgets.free + 1] = sprite
    end

    -- move mode: a frame outline and dragging
    local outline = base:CreateTexture(nil, "BACKGROUND")
    outline:SetAllPoints()
    outline:SetColorTexture(0.2, 0.6, 1, 0.18)
    outline:Hide()
    widgets.outline = outline
    base:SetMovable(true)
    base:SetClampedToScreen(true)
    base:RegisterForDrag("LeftButton")
    base:SetScript("OnDragStart", function(self) self:StartMoving() end)
    base:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, bottom = self:GetLeft(), self:GetBottom()
        local width, height = WorldFrame:GetWidth(), WorldFrame:GetHeight()
        db().x = (left + self:GetWidth() / 2 - width / 2) / width
        db().y = bottom / height
        Overlay.Layout()
    end)
end

-- Size and position from the saved settings (also after a resolution change).
function Overlay.Layout()
    local base, size = widgets.base, cellSize()
    base:ClearAllPoints()
    base:SetSize(size, size)
    base:SetPoint("BOTTOM", WorldFrame, "BOTTOM", (db().x or 0.12) * WorldFrame:GetWidth(), (db().y or 0) * WorldFrame:GetHeight())
    addon.Log.Write("layout", "overlay placed", { size = size, x = db().x or 0.12, y = db().y or 0, scale = db().scale or 1,
        worldWidth = WorldFrame:GetWidth(), worldHeight = WorldFrame:GetHeight() })
end

------------------------------------------------------------------ smoke

local function spawn(kind, x, y)
    local sprite = table.remove(widgets.free)
    if not sprite then                 -- pool exhausted: skip (old sprites free up within seconds)
        addon.Log.Once("poolEmpty", "smoke", "sprite pool exhausted, some smoke skipped", { pool = POOL_SIZE, kind = kind })
        return
    end
    widgets.live[#widgets.live + 1] = { sprite = sprite, particle = Logic.NewParticle(kind, x, y, math.random) }
end

local function clearSmoke()
    for _, entry in ipairs(widgets.live) do entry.sprite:Hide(); widgets.free[#widgets.free + 1] = entry.sprite end
    wipe(widgets.live)
end

-- Tip position (S units, from the top-left of base) including the current hand offset.
local function tipPosition(frame, handX, handY)
    local tip = Geometry.tips[frame]
    return tip.x + handX, tip.y + handY
end

local function updateSmoke(elapsed, size)
    local frames, columns, rows = Geometry.smoke.frames, Geometry.smoke.columns, Geometry.smoke.rows
    local wind = db().wind or 0.015
    local index = 1
    while index <= #widgets.live do
        local entry = widgets.live[index]
        entry.particle.age = entry.particle.age + elapsed
        local pose = Logic.ParticlePose(entry.particle, frames, wind)
        if pose.done then
            entry.sprite:Hide()
            widgets.free[#widgets.free + 1] = entry.sprite
            table.remove(widgets.live, index)
        else
            local sprite = entry.sprite
            sprite:ClearAllPoints()
            sprite:SetPoint("CENTER", widgets.base, "TOPLEFT", pose.x * size, -pose.y * size)
            sprite:SetSize(pose.size * size, pose.size * size)
            sprite:SetTexCoord(Logic.CellTexCoords(pose.frame, columns, rows))
            sprite:SetAlpha(pose.alpha)
            setRotation(sprite, pose.rotation)
            sprite:Show()
            index = index + 1
        end
    end
end

------------------------------------------------------------------ per frame

---@return boolean visible
---@return VisibilityInput input
---@return number distance
local function readVisibility()
    local vehicle = (UnitInVehicle and UnitInVehicle("player")) or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
    local distance = Overlay.CameraDistance()
    local input = {
        inHand = Logic.InHand(runtime.state, now()),
        mode = db().mode or "auto",
        firstPerson = Logic.IsFirstPerson(distance, db().threshold),
        dead = UnitIsDeadOrGhost("player") and true or false,
        taxi = UnitOnTaxi and UnitOnTaxi("player") and true or false,
        vehicle = vehicle and true or false,
        cinematic = runtime.cinematic,
        moving = runtime.moving,
    }
    return Logic.ShouldShow(input), input, distance
end

local function setVisible(visible, input, distance)
    if visible == runtime.visible then return end
    runtime.visible = visible
    local fields = { distance = distance }
    for key, value in pairs(input or {}) do fields[key] = value end
    addon.Log.Write("show", visible and "shown" or "hidden", fields)
    if visible then
        Overlay.Layout()
        widgets.base:Show()
    else
        widgets.base:Hide()
        clearSmoke()
    end
end

local function turnRate(elapsed)
    local facing = GetPlayerFacing and GetPlayerFacing()   -- nil in some instances
    if not facing or not runtime.lastFacing or elapsed <= 0 then runtime.lastFacing = facing; return 0 end
    local delta = facing - runtime.lastFacing
    if delta > math.pi then delta = delta - 2 * math.pi elseif delta < -math.pi then delta = delta + 2 * math.pi end
    runtime.lastFacing = facing
    return delta / elapsed
end

local function update(elapsed)
    local state = runtime.state
    local time = now()
    runtime.clock = runtime.clock + elapsed
    if Logic.Advance(state, elapsed, time) == "burnedOut" then
        addon.Log.Write("cig", "burned down to the filter")
        addon.Print("burned down to the filter.")
    end
    if runtime.clock >= runtime.nextCheck then
        runtime.nextCheck = runtime.clock + CHECK_INTERVAL
        local visible, input, distance = readVisibility()
        setVisible(visible, input, distance)
        -- camera samples (debug only): every change of more than 0.1 yd, at most once per check
        if addon.Log.Enabled() and math.abs(distance - (runtime.lastLoggedDistance or -1)) > 0.1 then
            runtime.lastLoggedDistance = distance
            addon.Log.Write("camera", "distance", { distance = distance, firstPerson = input.firstPerson,
                source = GetCameraZoom and "GetCameraZoom" or "estimate" })
        end
    end
    if not runtime.visible then
        runtime.lastFacing = nil
        return
    end

    local size = cellSize()
    local speed = GetUnitSpeed and GetUnitSpeed("player") or 0
    local swayX, swayY = Logic.Sway(time, speed)
    runtime.lagX = Logic.TurnLag(runtime.lagX, turnRate(elapsed), elapsed)
    local handX, handY = swayX + runtime.lagX, swayY
    widgets.hand:ClearAllPoints()
    widgets.hand:SetPoint("TOPLEFT", widgets.base, "TOPLEFT", handX * size, -handY * size)
    widgets.hand:SetSize(size, size)

    local frame = Logic.CigaretteFrame(state, Geometry.cigarette.frames)
    widgets.cigarette:SetTexCoord(Logic.CellTexCoords(frame, Geometry.cigarette.columns, Geometry.cigarette.rows))

    local tipX, tipY = Geometry.tips[frame].x, Geometry.tips[frame].y
    local brightness = Logic.EmberBrightness(state, time)
    local emberSize = size * (0.06 + 0.02 * brightness)
    widgets.ember:SetSize(emberSize, emberSize)
    widgets.ember:SetPoint("CENTER", widgets.hand, "TOPLEFT", tipX * size, -tipY * size)
    widgets.ember:SetAlpha(math.min(1, brightness))
    widgets.ember:SetShown(brightness > 0)
    widgets.spill:SetSize(size * 0.22, size * 0.22)
    widgets.spill:SetPoint("CENTER", widgets.hand, "TOPLEFT", tipX * size, -tipY * size)
    widgets.spill:SetAlpha(0.3 * brightness)
    widgets.spill:SetShown(brightness > 0)

    if state.lit and runtime.clock >= runtime.nextStream then
        runtime.nextStream = runtime.clock + STREAM_INTERVAL * (0.7 + 0.6 * math.random())
        local x, y = tipPosition(frame, handX, handY)
        spawn("stream", x, y - 0.01)
    end
    if Logic.ExhaleDue(state, time) then
        addon.Log.Debug("cig", "exhale", { live = #widgets.live, free = #widgets.free })
        for index = 1, EXHALE_SPRITES do
            spawn("exhale", MOUTH.x + (index - EXHALE_SPRITES / 2) * 0.02, MOUTH.y)
        end
    end
    updateSmoke(elapsed, size)
end

-- Errors are logged (once per message, with the stack) instead of spamming every frame.
local function onUpdate(_, elapsed)
    local ok, problem = xpcall(update, function(message)
        return tostring(message) .. "\n" .. (debugstack and debugstack(2, 8, 0) or "")
    end, elapsed)
    if not ok then
        addon.Log.Once("error:" .. tostring(problem):match("^[^\n]*"), "error", tostring(problem))
    end
end

-- What this client supports, written once per login (the first thing to read in a bug report).
local function probe()
    local version, build, buildDate, interface = GetBuildInfo()
    local zoomOk, zoom = false, nil
    if GetCameraZoom then zoomOk, zoom = pcall(GetCameraZoom) end
    local facingOk, facing = false, nil
    if GetPlayerFacing then facingOk, facing = pcall(GetPlayerFacing) end
    addon.Log.Write("probe", "client", { version = version, build = build, date = buildDate, interface = interface,
        locale = GetLocale and GetLocale() })
    addon.Log.Write("probe", "api", {
        GetCameraZoom = GetCameraZoom ~= nil, cameraZoom = zoomOk and zoom or "n/a",
        CameraZoomIn = CameraZoomIn ~= nil, CameraZoomOut = CameraZoomOut ~= nil,
        GetPlayerFacing = GetPlayerFacing ~= nil, facing = facingOk and facing or "n/a",
        GetUnitSpeed = GetUnitSpeed ~= nil, UnitInVehicle = UnitInVehicle ~= nil, UnitOnTaxi = UnitOnTaxi ~= nil,
        cameraMaxZoomFactor = GetCVar and GetCVar("cameraDistanceMaxZoomFactor"),
    })
    addon.Log.Write("probe", "screen", { worldWidth = WorldFrame:GetWidth(), worldHeight = WorldFrame:GetHeight(),
        worldScale = WorldFrame:GetEffectiveScale(), uiScale = UIParent:GetEffectiveScale() })
    addon.Log.Write("probe", "textures", { cigarette = widgets.cigarette:GetTexture(), smoke = widgets.sprites[1]:GetTexture(),
        ember = widgets.ember:GetTexture() })
    addon.Log.Write("probe", "saved state", { lit = runtime.state.lit, progress = runtime.state.progress,
        burnSeconds = runtime.state.burnSeconds, mode = db().mode or "auto", debug = db().debug or false })
end

------------------------------------------------------------------ actions (called by Commands.lua)

local function save()
    local state = runtime.state
    db().lit, db().progress, db().burnSeconds = state.lit, state.progress, state.burnSeconds
end

function Overlay.Light()
    if not Logic.Light(runtime.state, now()) then return false end
    addon.Log.Write("cig", "lit", { progress = runtime.state.progress, distance = Overlay.CameraDistance() })
    local frame = Logic.CigaretteFrame(runtime.state, Geometry.cigarette.frames)
    local x, y = tipPosition(frame, 0, 0)
    for _ = 1, 4 do spawn("puff", x, y) end
    runtime.nextCheck = 0
    save()
    return true
end

function Overlay.Drag()
    local ok = Logic.Drag(runtime.state, now())
    addon.Log.Write("cig", ok and "drag" or "drag refused", { lit = runtime.state.lit, progress = runtime.state.progress })
    if ok then save() end
    return ok
end

function Overlay.PutOut()
    local ok = Logic.PutOut(runtime.state, now())
    addon.Log.Write("cig", ok and "put out" or "put out refused (not lit)", { progress = runtime.state.progress })
    if ok then save() end
    return ok
end

function Overlay.SetBurnSeconds(seconds)
    runtime.state.burnSeconds = seconds
    save()
end

function Overlay.SetMoving(moving)
    runtime.moving = moving
    widgets.outline:SetShown(moving)
    widgets.base:EnableMouse(moving)
    runtime.nextCheck = 0
end

function Overlay.State() return runtime.state end

------------------------------------------------------------------ boot

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("CINEMATIC_START")
events:RegisterEvent("CINEMATIC_STOP")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
pcall(events.RegisterEvent, events, "PLAY_MOVIE")
pcall(events.RegisterEvent, events, "STOP_MOVIE")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        FpvCigaretteDB = FpvCigaretteDB or {}
        runtime.state = Logic.NewState(FpvCigaretteDB)
        addon.Log.Write("boot", "---- login ----")
        local ok, problem = pcall(function()
            build()
            hookZoom()
            probe()
        end)
        if not ok then addon.Log.Write("error", "boot failed", { error = tostring(problem) }) end
        events:SetScript("OnUpdate", onUpdate)
    elseif event == "PLAYER_LOGOUT" then
        if runtime.state then save() end
    elseif event == "CINEMATIC_START" or event == "PLAY_MOVIE" then
        runtime.cinematic = true
        addon.Log.Write("event", event)
    elseif event == "CINEMATIC_STOP" or event == "STOP_MOVIE" then
        runtime.cinematic = false
        addon.Log.Write("event", event)
    elseif event == "DISPLAY_SIZE_CHANGED" and widgets.base then
        Overlay.Layout()
    end
end)
