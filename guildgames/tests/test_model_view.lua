-- UI/ModelView.lua against a recording model frame: loading, the animation pick, poses and their timers, death, the
-- companion mode, zoom, the window-scale refresh. Plus the lint that keeps every shown model in that one module.
-- It proves the logic around the model frame, not how a creature looks in the game.

local function slurp(path)
    local handle = assert(io.open(path, "rb"), path)
    local text = handle:read("*a"); handle:close()
    return text
end

local function sourceFiles()
    local files = {}
    local listing = io.popen('dir /b /s Core\\*.lua UI\\*.lua 2>nul || find Core UI -name "*.lua"')
    for line in listing:lines() do
        local path = ("/" .. line:gsub("\\", "/"))
        local relative = path:match(".*/(Core/[%w_/]+%.lua)$") or path:match(".*/(UI/[%w_/]+%.lua)$")
        if relative then files[#files + 1] = relative end
    end
    listing:close()
    return files
end

-- A model frame that records what was called. `world.has` decides HasAnimation (nil: the client has no HasAnimation).
local function newFrame(world, kind)
    local frame = { kind = kind, scripts = {}, shown = true, visible = true, calls = {}, animations = {} }
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetScript(name, handler) self.scripts[name] = handler end
    function frame:HookScript(name, handler) self.scripts["hook:" .. name] = handler end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.visible end
    function frame:SetShown(shown) self.shown = shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetAllPoints() end
    function frame:SetPoint() end
    function frame:EnableMouse(enabled) self.mouse = enabled end
    function frame:EnableMouseWheel(enabled) self.wheel = enabled end
    function frame:CreateTexture() return { SetSize = function() end, SetPoint = function() end, SetTexCoord = function() end } end
    function frame:SetKeepModelOnHide() end
    function frame:ClearModel() self.calls[#self.calls + 1] = "clear"; self.display, self.npc = nil, nil end
    function frame:SetDisplayInfo(displayID)
        if world.refuseDisplay then error("bad display") end
        self.calls[#self.calls + 1] = "display"; self.display = displayID
    end
    function frame:SetCreature(npcID) self.calls[#self.calls + 1] = "creature"; self.npc = npcID end
    function frame:SetAnimation(animationID) self.animations[#self.animations + 1] = animationID end
    function frame:SetFacing(facing) self.facing = facing end
    function frame:SetCamDistanceScale(value) self.distance = value end
    function frame:SetPortraitZoom(value) self.portrait = value end
    function frame:SetPosition() end
    if world.has ~= nil then
        function frame:HasAnimation(animationID) return world.has[animationID] == true end
    end
    return frame
end

local function setup(harness, options)
    local world = { timers = {}, has = options and options.has, now = 100 }
    local saved = { CreateFrame = _G.CreateFrame, C_Timer = _G.C_Timer, GetCursorPosition = _G.GetCursorPosition }
    _G.CreateFrame = function(kind) return newFrame(world, kind) end
    _G.C_Timer = { After = function(seconds, callback) world.timers[#world.timers + 1] = { seconds = seconds, callback = callback } end }
    _G.GetCursorPosition = function() return world.cursor or 0 end
    local addon = harness.addon()
    addon.Api = { Clock = function() return world.now end }
    addon.UIHelpers = { SetTextureOr = function() end }
    assert(loadfile("UI/ModelView.lua"))("GuildGames", addon)
    world.restore = function() for key, value in pairs(saved) do _G[key] = value end end
    -- runs the timers due so far (a timer added meanwhile waits for the next call)
    function world.runTimers()
        local due = world.timers
        world.timers = {}
        for _, timer in ipairs(due) do timer.callback() end
    end
    return addon, world
end

local function withSetup(harness, options, body)
    local addon, world = setup(harness, options)
    local ok, errorMessage = pcall(body, addon, world)
    world.restore()
    if not ok then error(errorMessage, 0) end
end

local function last(list) return list[#list] end

return {
    ["model view: a creature loads by display id, else by npc id; the same one again does nothing; nil clears"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local view = addon.ModelView.New({}, { width = 50, height = 60 })
            harness.equal(view.frame.kind, "PlayerModel"); harness.equal(view.frame.width, 50)
            harness.truthy(view.Show({ npc = 7, disp = 99 }))
            harness.equal(view.frame.display, 99)
            local callCount = #view.frame.calls
            harness.truthy(view.Show({ npc = 7, disp = 99 }), "still loaded")
            harness.equal(#view.frame.calls, callCount, "the same creature is not loaded again")
            view.Show({ npc = 8, disp = 0 })
            harness.equal(view.frame.npc, 8, "no display id: the npc id")
            world.refuseDisplay = true
            harness.truthy(view.Show({ npc = 9, disp = 5 }), "a refused display id falls back to the npc id")
            harness.equal(view.frame.npc, 9)
            harness.equal(view.Show(nil), false)
            harness.equal(view.creature, nil); harness.equal(view.loaded, false)
            view.Show({ npc = 9, disp = 5 })
            view.Forget()
            local before = #view.frame.calls
            view.Show({ npc = 9, disp = 5 })
            harness.truthy(#view.frame.calls > before, "a forgotten creature loads again")
        end)
    end,

    ["model view: the first animation the model has; the first when it cannot tell; the last when it has none"] = function(harness)
        withSetup(harness, { has = { [17] = true, [0] = true } }, function(addon)
            local frame = { HasAnimation = function(_, animationID) return animationID == 17 end }
            harness.equal(addon.ModelView.Pick(frame, "attack"), 17)
            harness.equal(addon.ModelView.Pick(frame, { 1, 2, 3 }), 3, "none of them: the last")
            harness.equal(addon.ModelView.Pick({}, "attack"), 16, "no HasAnimation: the first")
            harness.equal(addon.ModelView.Pick({ HasAnimation = function() error("secret") end }, { 4, 5 }), 5, "an erroring check counts as no")
            harness.equal(addon.ModelView.Pick(frame, "nonsense"), nil)
            for key, list in pairs(addon.ModelView.ANIMATION) do harness.truthy(#list > 0, key .. " has candidates") end
        end)
    end,

    ["model view: a load (also a late one) plays the loop again, else the idle pose"] = function(harness)
        withSetup(harness, nil, function(addon)
            local view = addon.ModelView.New({}, { width = 10, height = 10, idle = "ready" })
            view.Show({ npc = 1, disp = 2 })
            harness.equal(last(view.frame.animations), 26, "loaded: the idle pose")
            view.Play("run")
            harness.equal(last(view.frame.animations), 5)
            local count = #view.frame.animations
            view.Play("run")
            harness.equal(#view.frame.animations, count, "the same loop again does nothing")
            view.Play("run", { restart = true })
            harness.equal(#view.frame.animations, count + 1, "unless restarted")
            -- the client finished loading: it reset the animation, the view sets it again
            view.frame.scripts.OnModelLoaded(view.frame)
            harness.equal(last(view.frame.animations), 5, "the loop again after OnModelLoaded")
            harness.equal(view.rendered, true)
        end)
    end,

    ["model view: back to idle after an action; a newer action voids the older timer"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local view = addon.ModelView.New({}, { width = 10, height = 10, idle = "ready" })
            view.Show({ npc = 1, disp = 2 })
            view.Play("attack", { restart = true, back = 0.5 })
            harness.equal(last(view.frame.animations), 16)
            local stale = world.timers[1]
            world.timers = {}
            view.Play("hurt", { restart = true, back = 0.5 })
            stale.callback()
            harness.equal(last(view.frame.animations), 9, "the stale timer is ignored")
            world.runTimers()
            harness.equal(last(view.frame.animations), 26, "the newer one goes back to ready")
            -- an emote marks the view busy until it is over
            view.Emote("pet", "test")
            harness.equal(view.busyUntil, world.now + addon.ModelView.EMOTE_SECONDS)
            view.Idle("now")
            harness.equal(view.busyUntil, nil); harness.equal(last(view.frame.animations), 26)
        end)
    end,

    ["model view: a dead view stays dead until it is revived or shows another creature"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local view = addon.ModelView.New({}, { width = 10, height = 10, idle = "ready" })
            view.Show({ npc = 1, disp = 2 })
            harness.truthy(view.Die(), "dies"); harness.equal(last(view.frame.animations), 1)
            harness.equal(view.Die(), false, "once")
            harness.equal(view.Play("hurt", { back = 1 }), nil, "a dead view plays nothing")
            world.runTimers()
            harness.equal(last(view.frame.animations), 6, "then it lies")
            view.Revive()
            harness.equal(last(view.frame.animations), 26, "revived: ready")
            view.Die()
            view.Show({ npc = 3, disp = 4 })
            harness.equal(view.dead, false, "another creature is alive")
            -- the lying pose of the old death does not come back
            world.runTimers()
            harness.equal(last(view.frame.animations), 26)
        end)
    end,

    ["model view: a companion view sleeps while its companion sleeps and switches when it wakes"] = function(harness)
        withSetup(harness, nil, function(addon)
            local view = addon.ModelView.New({}, { preset = "portrait", width = 10, height = 10, companion = true, area = "companion" })
            harness.equal(view.frame.kind, "DressUpModel", "the preset's frame")
            local companion = { npc = 1, disp = 2, asleep = 50 }
            view.Show(companion)
            harness.equal(last(view.frame.animations), 71, "asleep pose")
            companion.asleep = nil
            view.Show(companion)
            harness.equal(last(view.frame.animations), 0, "woke up: the stand")
            companion.asleep = 10
            view.Show(companion)
            harness.equal(last(view.frame.animations), 71, "fell asleep")
            -- a plain view ignores the sleep
            local plain = addon.ModelView.New({}, { width = 10, height = 10 })
            plain.Show({ npc = 1, disp = 2, asleep = 5 })
            harness.equal(last(plain.frame.animations), 0)
            harness.truthy(#addon.AzeCaught.JournalLines(5, "model.companion") > 0, "a view with an area journals")
        end)
    end,

    ["model view: an awake, visible companion plays an ambient emote now and then; dev forces one"] = function(harness)
        withSetup(harness, { has = { [74] = true, [0] = true } }, function(addon, world)
            local view = addon.ModelView.New({}, { width = 10, height = 10, companion = true })
            local companion = { npc = 1, disp = 2 }
            view.Show(companion)
            view.Tick(100)
            harness.truthy(view.nextAmbientAt and view.nextAmbientAt >= 100 + 90, "the first one comes a while later")
            local count = #view.frame.animations
            view.Tick(150)
            harness.equal(#view.frame.animations, count, "not yet")
            view.Tick(view.nextAmbientAt)
            harness.equal(last(view.frame.animations), 74, "an emote it has")
            -- forced: within a second, once per forcing
            world.now = 200
            addon.ModelView.ForceAmbient(200)
            view.busyUntil = nil
            count = #view.frame.animations
            view.Tick(200.5)
            harness.equal(#view.frame.animations, count + 1, "forced")
            view.busyUntil = nil
            view.Tick(200.6)
            harness.equal(#view.frame.animations, count + 1, "once per forcing")
            -- asleep or hidden: none
            companion.asleep = 5
            view.Tick(10000); harness.equal(view.nextAmbientAt, nil)
            companion.asleep = nil; view.frame.visible = false
            view.Tick(10000); harness.equal(view.nextAmbientAt, nil)
        end)
    end,

    ["model view: the wheel zooms within limits, remembered per NPC; a reload re-frames once more later"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local view = addon.ModelView.New({}, { preset = "portrait", width = 10, height = 10 })
            harness.truthy(view.frame.wheel and view.frame.mouse, "the preset turns and zooms")
            view.Show({ npc = 4711, disp = 1 })
            harness.equal(view.frame.portrait, 0, "full body"); harness.equal(view.frame.distance, 1.35)
            view.frame.scripts.OnMouseWheel(view.frame, -1)
            harness.truthy(view.frame.distance > 1.35, "wheel down zooms out")
            for _ = 1, 50 do view.Zoom(-1) end
            harness.equal(view.frame.distance, 4, "limit")
            local other = addon.ModelView.New({}, { preset = "portrait", width = 10, height = 10, zoom = false })
            other.Show({ npc = 4711, disp = 1 })
            harness.equal(other.frame.distance, 4, "remembered for this NPC in every view")
            harness.equal(other.frame.wheel, nil, "without the wheel")
            other.Show({ npc = 1, disp = 1 })
            harness.equal(other.frame.distance, 1.35, "other NPCs keep the default")
            -- right-drag turns, a new creature faces the default again
            world.cursor = 10
            view.frame.scripts.OnMouseDown(view.frame, "RightButton")
            world.cursor = 60
            view.frame.scripts.OnUpdate(view.frame)
            harness.truthy(math.abs(view.facing - (0.4 + 1)) < 1e-9, "turned: " .. view.facing)
            view.frame.scripts.OnMouseUp(view.frame)
            view.Show({ npc = 2, disp = 2 })
            harness.equal(view.facing, 0.4)
            -- a reload: loaded again, idle, and framed once more after a moment
            world.timers = {}
            local before = #view.frame.calls
            view.Reload("shown")
            harness.truthy(#view.frame.calls > before, "loaded again")
            harness.equal(#world.timers, 1, "a late framing")
            world.runTimers()
            addon.ModelView.zoomByNpc = {}
        end)
    end,

    ["model view: a client without the optional calls is fine"] = function(harness)
        withSetup(harness, nil, function(addon)
            local view = addon.ModelView.New({}, { width = 10, height = 10, companion = true })
            local frame = view.frame
            for _, method in ipairs({ "SetAnimation", "SetCamDistanceScale", "SetPortraitZoom", "SetPosition", "SetFacing", "ClearModel" }) do
                frame[method] = nil
            end
            harness.truthy(pcall(view.Show, { npc = 1, disp = 2 }))
            harness.equal(view.Play("run"), nil, "no SetAnimation: nothing played")
            harness.truthy(pcall(view.Idle, "x")); harness.truthy(pcall(view.Emote, "pet", "x")); harness.truthy(pcall(view.Die))
            harness.equal(view.Has(0), nil, "cannot tell")
            harness.equal(view.LookFrom({ 0, 0, 1 }, { 0, 0, 0 }), false, "no custom camera")
            harness.equal(view.FitDistance(), nil, "not drawn")
        end)
    end,

    ["model view: window scaling frames shown views again, hidden ones on their OnShow"] = function(harness)
        withSetup(harness, nil, function(addon)
            local view = addon.ModelView.New({}, { width = 10, height = 10 })
            local refreshed = 0
            view.frame.RefreshCamera = function() refreshed = refreshed + 1 end
            view.Show({ npc = 1, disp = 2 })
            addon.ModelView.RefreshAll()
            harness.equal(refreshed, 1)
            view.frame.shown = false
            addon.ModelView.RefreshAll()
            harness.equal(refreshed, 1, "hidden: left alone")
            view.frame.shown = true
            view.frame.scripts["hook:OnShow"](view.frame)
            harness.equal(refreshed, 2, "framed when it shows")
        end)
    end,

    ["model view: an emote's timer after the companion fell asleep keeps the asleep pose; Show(nil) voids timers"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local view = addon.ModelView.New({}, { width = 10, height = 10, companion = true })
            local companion = { npc = 1, disp = 2 }
            view.Show(companion)
            view.Emote("pet", "care")
            companion.asleep = 30
            world.runTimers()
            harness.equal(last(view.frame.animations), 71, "the timer's idle pose is the asleep one")
            -- cleared while an action is pending: nothing plays on the empty frame
            companion.asleep = nil
            view.Show(companion); view.Play("attack", { restart = true, back = 1 })
            view.Show(nil)
            local count = #view.frame.animations
            world.runTimers()
            harness.equal(#view.frame.animations, count, "a cleared view plays nothing")
        end)
    end,

    ["model view: a hidden view only forgets on Reload; a view without zoom memory keeps its own zoom"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local view = addon.ModelView.New({}, { width = 10, height = 10, camera = 2, zoom = true })
            view.Show({ npc = 5, disp = 6 })
            view.frame.visible = false
            world.timers = {}
            local before = #view.frame.calls
            view.Reload("shown")
            harness.equal(#view.frame.calls, before, "not loaded into a hidden frame")
            harness.equal(#world.timers, 0)
            view.frame.visible = true
            view.Show({ npc = 5, disp = 6 })
            harness.truthy(#view.frame.calls > before, "it loads on the next Show")
            view.Zoom(1)
            harness.truthy(math.abs(view.frame.distance - 2 / addon.ModelView.ZOOM_STEP) < 1e-9)
            harness.equal(addon.ModelView.zoomByNpc[5], nil, "not remembered for other views")
            harness.truthy(not pcall(addon.ModelView.New, {}, { width = 1, height = 1, preset = "nonsense" }), "an unknown preset is an error")
        end)
    end,

    ["model view: a client whose SetScript or HookScript fails still gets a working view"] = function(harness)
        withSetup(harness, nil, function(addon)
            local savedCreateFrame = _G.CreateFrame
            _G.CreateFrame = function(kind)
                local frame = savedCreateFrame(kind)
                frame.SetScript = function() error("no such script") end
                frame.HookScript = nil
                return frame
            end
            local ok, view = pcall(addon.ModelView.New, {}, { width = 10, height = 10 })
            _G.CreateFrame = savedCreateFrame
            harness.truthy(ok, tostring(view))
            harness.truthy(view.Show({ npc = 1, disp = 2 }))
            harness.equal(last(view.frame.animations), 0)
        end)
    end,

    -- the split stays clean: model frame calls for shown models live in UI/ModelView.lua only. A method counts when it
    -- is called (`:M(`, `.M(`, `.M,` for pcall) or named as a string argument (`call(frame, "M")`).
    ["model view: no other file creates or drives a model frame (allowed: the hidden look capture, the dev probe)"] = function(harness)
        local METHODS = { "SetDisplayInfo", "SetCreature", "SetUnit", "SetModel", "ClearModel", "SetAnimation", "HasAnimation",
            "SetSequence", "FreezeAnimation", "SetFacing", "SetPosition", "SetModelScale", "SetCamera", "SetCamDistanceScale",
            "SetPortraitZoom", "MakeCurrentCameraCustom", "SetCameraPosition", "SetCameraTarget", "SetKeepModelOnHide",
            "RefreshCamera", "GetCameraDistance", "GetModelFileID", "GetDisplayInfo" }
        local FRAME_TYPES = { "PlayerModel", "DressUpModel", "Model", "CinematicModel", "TabardModel", "ModelScene", "OnModelLoaded" }
        -- whole files, or the functions of a file that hold the hidden models reading a unit's look (never shown)
        local LOOK_CAPTURE = { ClearModel = true, SetCreature = true, SetUnit = true, GetModelFileID = true, GetDisplayInfo = true,
            PlayerModel = true }
        local ALLOWED = {
            ["UI/ModelView.lua"] = "all",
            ["UI/DevProbe.lua"] = "all",   -- client capability probes of the dev build: the raw API on purpose
            ["Core/Game/Catcher.lua"] = { hiddenModel = LOOK_CAPTURE, readInteger = LOOK_CAPTURE,
                ["Catcher.CreatureDisplay"] = LOOK_CAPTURE, ["Catcher.CaptureDisplay"] = LOOK_CAPTURE },
            ["Core/Game/Api.lua"] = { ["Api.IdentityProbe"] = LOOK_CAPTURE, ["Api.GenderProbe"] = LOOK_CAPTURE,
                ["Api.GenderProbeReread"] = LOOK_CAPTURE },
        }
        local found, scannedCount = {}, 0
        local function uses(code, name)
            return code:find("[:.]" .. name .. "%s*[(,]") or code:find('[(,]%s*"' .. name .. '"') or code:find('"' .. name .. '"%s*[,)]')
                or code:find('%[%s*"' .. name .. '"%s*%]')
        end
        for _, path in ipairs(sourceFiles()) do
            scannedCount = scannedCount + 1
            local allowedByFunction = ALLOWED[path] or {}
            if allowedByFunction ~= "all" then
                local lineNumber, functionName = 0, nil
                for line in (slurp(path) .. "\n"):gmatch("([^\n]*)\n") do
                    lineNumber = lineNumber + 1
                    functionName = line:match("^function ([%w_.:]+)") or line:match("^local function ([%w_]+)") or functionName
                    if line:match("^%S") and not line:match("^function ") and not line:match("^local function ") then
                        functionName = nil   -- a top-level statement or the function's `end`: out of its scope
                    end
                    local allowed = allowedByFunction[functionName] or {}
                    local code = line:gsub("%-%-.*$", "")
                    for _, name in ipairs(METHODS) do
                        if uses(code, name) and not allowed[name] then found[#found + 1] = path .. ":" .. lineNumber .. " " .. name end
                    end
                    for _, kind in ipairs(FRAME_TYPES) do
                        local pattern = kind == "OnModelLoaded" and '"OnModelLoaded"' or ('CreateFrame%s*[(,]%s*"' .. kind .. '"')
                        if code:find(pattern) and not allowed[kind] then
                            found[#found + 1] = path .. ":" .. lineNumber .. " " .. kind
                        end
                    end
                end
            end
        end
        harness.truthy(scannedCount > 20, "the file listing found too few files: " .. scannedCount)
        harness.equal(#found, 0, "model frame calls outside UI/ModelView.lua: " .. table.concat(found, " | "))
    end,
}
