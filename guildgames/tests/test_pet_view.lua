-- The pet view's pure parts: options with defaults and limits, the ring gauges, the layout, keeping it on screen.
return {
    ["pet view: settings default to minimal, full opacity, scale 1, hide in combat"] = function(harness)
        local Model = harness.addon().Model
        local settings = Model.PetViewSettings(nil)
        harness.equal(settings.startMode, "minimal"); harness.equal(settings.mode, "minimal")
        harness.equal(settings.opacity, 1); harness.equal(settings.scale, 1)
        harness.equal(settings.locked, false); harness.equal(settings.hideInCombat, true); harness.equal(settings.open, false)
        harness.equal(settings.left, nil); harness.equal(settings.top, nil)
    end,

    ["pet view: broken saved settings are clamped or replaced by defaults"] = function(harness)
        local Model = harness.addon().Model
        local settings = Model.PetViewSettings({ startMode = "huge", mode = 3, opacity = 0.05, scale = "x", locked = "yes",
            hideInCombat = false, open = 1, left = 0 / 0, top = math.huge })
        harness.equal(settings.startMode, "minimal"); harness.equal(settings.mode, "minimal")
        harness.equal(settings.opacity, 0.2); harness.equal(settings.scale, 1)
        harness.equal(settings.locked, false); harness.equal(settings.hideInCombat, false); harness.equal(settings.open, false)
        harness.equal(settings.left, nil); harness.equal(settings.top, nil)
        local big = Model.PetViewSettings({ opacity = 7, scale = 9, startMode = "full" })
        harness.equal(big.opacity, 1); harness.equal(big.scale, 2)
        harness.equal(big.startMode, "full"); harness.equal(big.mode, "full", "no saved mode: the start mode")
        harness.equal(Model.PetViewSettings({ startMode = "full", mode = "minimal" }).mode, "minimal")
    end,

    ["pet view: the ring shows a share of 0..1; broken values show none"] = function(harness)
        local Model = harness.addon().Model
        harness.equal(Model.GaugeShare(0), 0)
        harness.equal(Model.GaugeShare(50), 0.5)
        harness.equal(Model.GaugeShare(100), 1)
        harness.equal(Model.GaugeShare(250), 1); harness.equal(Model.GaugeShare(-5), 0)
        harness.equal(Model.GaugeShare(nil), 0); harness.equal(Model.GaugeShare(0 / 0), 0)
        harness.equal(Model.GaugeShare("50"), 0); harness.equal(Model.GaugeShare(math.huge), 0)
    end,

    ["pet view: the arc cell follows the share; nothing at 0, every cell reachable"] = function(harness)
        local Model = harness.addon().Model
        harness.equal(Model.RingArc(0, 64), nil); harness.equal(Model.RingArc(0 / 0, 64), nil); harness.equal(Model.RingArc(nil, 64), nil)
        harness.equal(Model.RingArc(0.001, 64), 1, "a sliver shows one cell")
        harness.equal(Model.RingArc(0.5, 64), 32); harness.equal(Model.RingArc(1, 64), 64); harness.equal(Model.RingArc(3, 64), 64)
        harness.equal(Model.RingArc(0.995, 64), 64, "almost full shows the whole ring")
        local left, right, top, bottom = Model.ArcTexCoord(1, 8)
        harness.equal(left, 0); harness.equal(right, 0.125); harness.equal(top, 0); harness.equal(bottom, 0.125)
        left, right, top, bottom = Model.ArcTexCoord(10, 8)
        harness.equal(left, 0.125); harness.equal(right, 0.25); harness.equal(top, 0.125); harness.equal(bottom, 0.25)
        left, right, top, bottom = Model.ArcTexCoord(64, 8)
        harness.equal(left, 0.875); harness.equal(right, 1); harness.equal(top, 0.875); harness.equal(bottom, 1)
    end,

    ["pet view: idle emotes come every 90-240 s, shuffled without losing or doubling one"] = function(harness)
        local Model = harness.addon().Model
        harness.equal(Model.IdleEmoteDelay(function(low) return low end), 90)
        harness.equal(Model.IdleEmoteDelay(function(_, high) return high end), 240)
        local seed = 7
        local function random(low, high) seed = (seed * 1103515245 + 12345) % 2147483648; return low + seed % (high - low + 1) end
        local shuffled = Model.ShuffledIdleEmotes(random)
        harness.equal(#shuffled, #Model.IDLE_EMOTES)
        local seen = {}
        for _, animationID in ipairs(shuffled) do harness.truthy(not seen[animationID], "doubled " .. animationID); seen[animationID] = true end
        for _, animationID in ipairs(Model.IDLE_EMOTES) do harness.truthy(seen[animationID], "lost " .. animationID) end
        harness.equal(Model.IDLE_EMOTES[1], 74, "the list itself is not reordered")
    end,

    ["pet view: gauge colours follow the zone, unknown is grey"] = function(harness)
        local Model = harness.addon().Model
        harness.equal(Model.GaugeColor("ok"), Model.GAUGE_ZONE_COLOR.ok)
        harness.equal(Model.GaugeColor("critical"), Model.GAUGE_ZONE_COLOR.critical)
        harness.equal(Model.GaugeColor(nil), Model.GAUGE_ZONE_COLOR.never)
        harness.equal(Model.GaugeColor("weird"), Model.GAUGE_ZONE_COLOR.never)
    end,

    ["pet view: layout keeps everything inside, symmetric, corners free"] = function(harness)
        local Model = harness.addon().Model
        local petSize, gaugeSize, cornerSize = 96, 30, 22
        local layout = Model.PetViewLayout(petSize, gaugeSize, cornerSize)
        local function inside(point, size, label)
            harness.truthy(point.x - size / 2 >= 0 and point.x + size / 2 <= layout.width, label .. " inside horizontally")
            harness.truthy(point.y + size / 2 <= 0 and point.y - size / 2 >= -layout.height, label .. " inside vertically")
        end
        local function apart(first, firstSize, second, secondSize, label)
            local distance = math.sqrt((first.x - second.x) ^ 2 + (first.y - second.y) ^ 2)
            harness.truthy(distance >= (firstSize + secondSize) / 2 - 0.01, label .. " do not overlap")
        end
        inside(layout.pet, petSize, "pet"); inside(layout.switch, cornerSize, "switch"); inside(layout.heart, cornerSize, "heart")
        for _, key in ipairs(Model.PET_VIEW_GAUGES) do
            local gauge = layout.gauges[key]
            harness.truthy(gauge, key)
            inside(gauge, gaugeSize, key)
            apart(gauge, gaugeSize, layout.pet, petSize, key .. " and the pet")
            apart(gauge, gaugeSize, layout.switch, cornerSize, key .. " and the switch")
            apart(gauge, gaugeSize, layout.heart, cornerSize, key .. " and the heart")
        end
        apart(layout.gauges.feed, gaugeSize, layout.gauges.water, gaugeSize, "feed and water")
        apart(layout.gauges.water, gaugeSize, layout.gauges.pet, gaugeSize, "water and pet")
        apart(layout.gauges.pet, gaugeSize, layout.gauges.sleep, gaugeSize, "pet and sleep")
        harness.truthy(math.abs((layout.gauges.feed.x + layout.gauges.sleep.x) - layout.width) < 1e-9, "feed and sleep mirror")
        harness.truthy(math.abs(layout.gauges.feed.y - layout.gauges.sleep.y) < 1e-9, "feed and sleep level")
        harness.truthy(layout.switch.x < layout.pet.x and layout.heart.x > layout.pet.x, "switch left, heart right")
    end,

    ["pet view: a window off the screen is moved back; a missing position is centred"] = function(harness)
        local Model = harness.addon().Model
        local left, top = Model.KeepOnScreen(-50, 2000, 160, 130, 1920, 1080)
        harness.equal(left, 0); harness.equal(top, 1080)
        left, top = Model.KeepOnScreen(1900, 20, 160, 130, 1920, 1080)
        harness.equal(left, 1760); harness.equal(top, 130)
        left, top = Model.KeepOnScreen(nil, nil, 160, 130, 1920, 1080)
        harness.equal(left, 880); harness.equal(top, 605)
        left, top = Model.KeepOnScreen(300, 500, 160, 130, 1920, 1080)
        harness.equal(left, 300); harness.equal(top, 500)
    end,
}
