-- Coin flip animation math (feature 014, R4): the pose curve UI/GamesTab.lua plays every frame.
return {
    ["coinflip: starts flat on heads at rest and ends flat on the outcome"] = function(harness)
        local CoinFlip = harness.addon().CoinFlip
        local start = CoinFlip.Pose(0, "T")
        harness.equal(start.width, 1); harness.equal(start.y, 0); harness.equal(start.face, "H"); harness.equal(start.done, false)
        for _, outcome in ipairs({ "H", "T" }) do
            for _, elapsed in ipairs({ CoinFlip.DURATION, CoinFlip.DURATION + 5 }) do
                local pose = CoinFlip.Pose(elapsed, outcome)
                harness.equal(pose.face, outcome); harness.equal(pose.done, true); harness.equal(pose.width, 1); harness.equal(pose.y, 0)
            end
            -- just before the end the face already shows the outcome (no last-frame swap)
            harness.equal(CoinFlip.Pose(CoinFlip.DURATION * 0.999, outcome).face, outcome)
        end
    end,

    ["coinflip: width never collapses, the toss peaks at HEIGHT in the middle"] = function(harness)
        local CoinFlip = harness.addon().CoinFlip
        local highest, highestAt = 0, 0
        for step = 0, 200 do
            local elapsed = CoinFlip.DURATION * step / 200
            local pose = CoinFlip.Pose(elapsed, step % 2 == 0 and "H" or "T")
            harness.truthy(pose.width >= CoinFlip.MINIMUM_WIDTH and pose.width <= 1, "width at " .. step)
            harness.truthy(pose.y >= 0)
            harness.truthy(pose.edge >= -1 and pose.edge <= 1, "edge at " .. step)
            harness.truthy(math.abs(pose.width ^ 2 + pose.edge ^ 2 - 1) < 1e-9 or pose.width == CoinFlip.MINIMUM_WIDTH,
                "width and edge are cos and sin of one angle")
            if pose.y > highest then highest, highestAt = pose.y, step end
        end
        harness.truthy(math.abs(highest - CoinFlip.HEIGHT) < 1e-9, "peak " .. highest)
        harness.equal(highestAt, 100)
    end,

    ["coinflip: the face swaps exactly once per half-turn"] = function(harness)
        local CoinFlip = harness.addon().CoinFlip
        for outcome, halfTurns in pairs(CoinFlip.HALF_TURNS) do
            local swaps, previousFace = 0, "H"
            for step = 0, 4000 do
                local face = CoinFlip.Pose(CoinFlip.DURATION * step / 4000, outcome).face
                if face ~= previousFace then swaps = swaps + 1 end
                previousFace = face
            end
            harness.equal(swaps, halfTurns, "outcome " .. outcome)
        end
    end,
}
