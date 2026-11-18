-- Offline tests for the pure parts:  luajit tests/run.lua   (from the repo root)
local addon = {}
for _, path in ipairs({ "Geometry.lua", "Logic.lua" }) do
    local chunk = assert(loadfile(path))
    chunk("FpvCigarette", addon)
end
local Logic, Geometry = addon.Logic, addon.Geometry

local function near(actual, expected, label)
    assert(math.abs(actual - expected) < 1e-6, string.format("%s: expected %s, got %s", label or "value", expected, actual))
end

local function sequence(values)
    local index = 0
    return function() index = index % #values + 1; return values[index] end
end

local tests = {}

tests["cell texture coordinates walk the sheet left to right, top to bottom"] = function()
    local left, right, top, bottom = Logic.CellTexCoords(1, 4, 2)
    near(left, 0); near(right, 0.25); near(top, 0); near(bottom, 0.5)
    left, right, top, bottom = Logic.CellTexCoords(6, 4, 2)
    near(left, 0.25); near(right, 0.5); near(top, 0.5); near(bottom, 1)
    left, right, top, bottom = Logic.CellTexCoords(16, 4, 4)
    near(left, 0.75); near(right, 1); near(top, 0.75); near(bottom, 1)
end

tests["flip frame covers every frame and clamps"] = function()
    assert(Logic.FlipFrame(0, 16) == 1)
    assert(Logic.FlipFrame(0.999, 16) == 16)
    assert(Logic.FlipFrame(1, 16) == 16)
    assert(Logic.FlipFrame(-1, 16) == 1)
    assert(Logic.FlipFrame(0.5, 16) == 9)
end

tests["geometry has a tip for every cigarette frame, inside the cell"] = function()
    assert(#Geometry.tips == Geometry.cigarette.frames)
    for _, tip in ipairs(Geometry.tips) do assert(tip.x > 0 and tip.x < 1 and tip.y > 0 and tip.y < 1) end
end

tests["a fresh cigarette shows the unlit frame, then burns through 2..8"] = function()
    local state = Logic.NewState()
    assert(Logic.CigaretteFrame(state, 8) == 1)
    assert(Logic.Light(state, 0))
    assert(not Logic.Light(state, 1), "lighting twice")
    assert(Logic.CigaretteFrame(state, 8) == 2)
    Logic.Advance(state, state.burnSeconds * 0.5, 150)
    assert(Logic.CigaretteFrame(state, 8) == 5, "half way: " .. Logic.CigaretteFrame(state, 8))
    Logic.Advance(state, state.burnSeconds * 0.49, 297)
    assert(Logic.CigaretteFrame(state, 8) == 8)
end

tests["burning down puts it out once and keeps it in hand briefly"] = function()
    local state = Logic.NewState({ burnSeconds = 100 })
    Logic.Light(state, 0)
    assert(Logic.Advance(state, 99, 99) == nil)
    assert(Logic.Advance(state, 2, 101) == "burnedOut")
    assert(not state.lit)
    assert(Logic.Advance(state, 1, 102) == nil, "reported twice")
    assert(Logic.InHand(state, 101 + Logic.HIDE_AFTER_OUT - 0.1))
    assert(not Logic.InHand(state, 101 + Logic.HIDE_AFTER_OUT + 0.1))
    assert(Logic.Light(state, 200) and state.progress == 0, "relighting a burned one gives a fresh one")
end

tests["a drag burns faster, brightens the ember and exhales once"] = function()
    local state = Logic.NewState({ burnSeconds = 100 })
    assert(not Logic.Drag(state, 0), "drag while unlit")
    Logic.Light(state, 0)
    local resting = 0.55 + 0.1 + 0.06   -- the flicker's highest value
    assert(Logic.Drag(state, 10))
    near(state.progress, Logic.DRAG_BURN_SECONDS / 100, "progress")
    assert(not Logic.Drag(state, 10.5), "second drag while inhaling")
    assert(Logic.EmberBrightness(state, 10 + Logic.INHALE_SECONDS) > resting + 0.3)
    assert(not Logic.ExhaleDue(state, 11))
    assert(Logic.ExhaleDue(state, 10 + Logic.EXHALE_DELAY + 0.01))
    assert(not Logic.ExhaleDue(state, 12), "exhaled twice")
    assert(Logic.Drag(state, 20))
    assert(not Logic.ExhaleDue(state, 20.5))
    assert(Logic.ExhaleDue(state, 20 + Logic.EXHALE_DELAY + 0.01), "second drag exhales again")
end

tests["ember is dark when out and bounded when lit"] = function()
    local state = Logic.NewState()
    assert(Logic.EmberBrightness(state, 5) == 0)
    Logic.Light(state, 0)
    for time = 0, 30, 0.1 do
        local brightness = Logic.EmberBrightness(state, time)
        assert(brightness > 0 and brightness <= 1.5)
    end
end

tests["smoke rises, grows, plays the flipbook and ends"] = function()
    for kind in pairs(Logic.PARTICLE_KINDS) do
        local particle = Logic.NewParticle(kind, 0.5, 0.5, sequence({ 0.3, 0.7, 0.5 }))
        local first = Logic.ParticlePose(particle, 16, 0)
        assert(first.frame == 1 and not first.done)
        particle.age = particle.life * 0.6
        local later = Logic.ParticlePose(particle, 16, 0)
        assert(later.y < first.y, kind .. " rises")
        assert(later.size > first.size, kind .. " grows")
        assert(later.frame > first.frame, kind .. " advances frames")
        particle.age = particle.life
        assert(Logic.ParticlePose(particle, 16, 0).done)
    end
end

tests["zoom tracker clamps and detects first person"] = function()
    local tracker = Logic.NewZoomTracker(3)
    Logic.ZoomIn(tracker, 2); Logic.ZoomIn(tracker, 5)
    assert(tracker.distance == 0)
    assert(Logic.IsFirstPerson(tracker.distance))
    Logic.ZoomOut(tracker)
    assert(not Logic.IsFirstPerson(tracker.distance))
    for _ = 1, 100 do Logic.ZoomOut(tracker, 1) end
    assert(tracker.distance == Logic.MAX_ZOOM)
    assert(not Logic.IsFirstPerson(nil))
end

tests["visibility: in hand, first person or always, never while dead / on taxi / in cinematics"] = function()
    local base = { inHand = true, mode = "auto", firstPerson = true }
    assert(Logic.ShouldShow(base))
    assert(not Logic.ShouldShow({ inHand = true, mode = "auto", firstPerson = false }))
    assert(Logic.ShouldShow({ inHand = true, mode = "always", firstPerson = false }))
    assert(not Logic.ShouldShow({ inHand = false, mode = "always", firstPerson = true }))
    for _, blocker in ipairs({ "dead", "taxi", "vehicle", "cinematic" }) do
        local input = { inHand = true, mode = "always", firstPerson = true }
        input[blocker] = true
        assert(not Logic.ShouldShow(input), blocker)
    end
    assert(Logic.ShouldShow({ inHand = false, moving = true }), "move mode always shows")
end

tests["sway and turn lag stay small"] = function()
    for time = 0, 20, 0.37 do
        local dx, dy = Logic.Sway(time, 7)
        assert(math.abs(dx) < 0.05 and math.abs(dy) < 0.05)
    end
    local lag = 0
    for _ = 1, 100 do lag = Logic.TurnLag(lag, 10, 1 / 60) end
    near(lag, -0.08, "lag clamps")
end

tests["dancer scale clamps and survives bad input"] = function()
    assert(Logic.ClampDancerScale(1.5) == 1.5)
    assert(Logic.ClampDancerScale(0.01) == Logic.DANCER_SCALE_MIN)
    assert(Logic.ClampDancerScale(99) == Logic.DANCER_SCALE_MAX)
    assert(Logic.ClampDancerScale("x") == 1)
    assert(Logic.DANCE_ANIMATION == 69)
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failed = 0
for _, name in ipairs(names) do
    local ok, problem = pcall(tests[name])
    print((ok and "ok    " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(problem))))
    if not ok then failed = failed + 1 end
end
print(string.format("%d tests, %d failed", #names, failed))
os.exit(failed == 0 and 0 or 1)
