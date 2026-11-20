local addonName, addon = ...

-- Coin flip animation math (feature 014). Pure: no WoW calls, so the curve is unit-tested offline and printed by
-- tools/coinflip.lua. UI/GamesTab.lua applies a pose every rendered frame through Animate.Tween.
--   toss:  y follows a parabola, 0 -> HEIGHT -> 0
--   spin:  the coin turns about its vertical axis; its visible width is |cos(angle)|, the face swaps at each edge-on moment
--          (angle = pi/2 + k*pi); the spin decelerates (ease-out cubic) and ends flat on the outcome face.

-- The UI flips the coin end over end (about the horizontal axis): `width` is the visible share of the coin along the flip
-- axis (its height on screen), `edge` = sin(angle) says how much of the rim shows and on which side (> 0: below the face).
---@class CoinPose
---@field width number MINIMUM_WIDTH..1 visible share of the face along the flip axis (|cos angle|)
---@field edge number -1..1 sin(angle): rim visibility and side; 0 when flat
---@field y number pixels above the resting position
---@field face "H"|"T"
---@field done boolean

---@class CoinFlipModule
local CoinFlip = {}
addon.CoinFlip = CoinFlip

CoinFlip.DURATION = 1.6
CoinFlip.HEIGHT = 70
CoinFlip.MINIMUM_WIDTH = 0.04
-- half-turns per outcome: the coin starts on heads, an even count ends on heads, an odd one on tails
CoinFlip.HALF_TURNS = { H = 10, T = 9 }

---@param elapsed number seconds since the toss
---@param outcome "H"|"T"
---@return CoinPose
function CoinFlip.Pose(elapsed, outcome)
    local progress = addon.Utility.Clamp((tonumber(elapsed) or 0) / CoinFlip.DURATION, 0, 1)
    if progress >= 1 then return { width = 1, edge = 0, y = 0, face = outcome, done = true } end
    local eased = 1 - (1 - progress) ^ 3
    local angle = (CoinFlip.HALF_TURNS[outcome] or 10) * math.pi * eased
    local faceIndex = math.floor((angle + math.pi / 2) / math.pi) % 2
    return {
        width = math.max(CoinFlip.MINIMUM_WIDTH, math.abs(math.cos(angle))),
        edge = math.sin(angle),
        y = CoinFlip.HEIGHT * 4 * progress * (1 - progress),
        face = faceIndex == 0 and "H" or "T",
        done = false,
    }
end
