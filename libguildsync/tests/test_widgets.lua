-- Widgets: where the minimap button sits (it once sat INSIDE the larger Forever minimap at a fixed 80 px).

local function near(harness, actual, expected, message)
    harness.truthy(math.abs(actual - expected) < 0.001, (message or "") .. ": expected " .. expected .. ", got " .. actual)
end

return {
    ["widgets: the minimap button sits just outside the edge, whatever the minimap size"] = function(harness)
        local Widgets = harness.library().Widgets
        local gap = Widgets.MINIMAP_BUTTON_GAP
        -- a 198 px minimap (modern client): right of the centre by half the width plus the gap, never 80
        local x, y = Widgets.MinimapButtonOffset(0, 198, 198, "ROUND")
        near(harness, x, 99 + gap, "right"); near(harness, y, 0, "level")
        x, y = Widgets.MinimapButtonOffset(90, 198, 198)
        near(harness, x, 0, "top x"); near(harness, y, 99 + gap, "top y, no shape means round")
        -- every angle on a round map is at the same distance, outside the map's radius
        for angle = 0, 359, 15 do
            x, y = Widgets.MinimapButtonOffset(angle, 198, 198, "ROUND")
            near(harness, math.sqrt(x * x + y * y), 99 + gap, "angle " .. angle)
        end
        -- the client cannot tell the size (offline stubs): the classic 140 px minimap
        x = Widgets.MinimapButtonOffset(0, nil, {}, nil)
        near(harness, x, Widgets.MINIMAP_FALLBACK_SIZE / 2 + gap, "fallback")
        x = Widgets.MinimapButtonOffset(0, 0 / 0, 0 / 0)
        near(harness, x, Widgets.MINIMAP_FALLBACK_SIZE / 2 + gap, "NaN falls back")
    end,

    ["widgets: on a square minimap the button follows the edge into the corner"] = function(harness)
        local Widgets = harness.library().Widgets
        local half = 198 / 2 + Widgets.MINIMAP_BUTTON_GAP
        local x, y = Widgets.MinimapButtonOffset(45, 198, 198, "SQUARE")
        -- LibDBIcon's corner rule (so we line up with other addons' buttons): on the diagonal, 10 px in from the corner
        local corner = math.cos(math.rad(45)) * (math.sqrt(2 * half ^ 2) - 10)
        near(harness, x, corner, "corner x"); near(harness, y, corner, "corner y")        x, y = Widgets.MinimapButtonOffset(0, 198, 198, "SQUARE")
        near(harness, x, half, "side"); near(harness, y, 0, "side level")
    end,
}
