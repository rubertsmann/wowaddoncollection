local addonName, addon = ...

-- Slot machine (feature 014, second game). Pure Lua: rules, reel strip, paylines and the reel motion the UI plays
-- (UI/SlotMachine.lua). Results are stored with Games.RecordPlay in the "slots" section of my game record, BEFORE any
-- animation, like the coin flip.
--
-- 3 reels x 3 rows. Every reel is the same strip of symbols; a spin picks a random stop per reel and the window shows
-- strip[stop], strip[stop + 1], strip[stop + 2] (top to bottom). 5 paylines: the 3 rows and both diagonals. Three equal
-- symbols on a payline pay `pays` x stake for that line; the lines of one spin add up. A spin without a line costs the stake.
-- Return to player: about 94% (Slots.ReturnToPlayer, pinned by tests/test_slots.lua).

---@class SlotSymbol
---@field key string
---@field icon string texture path
---@field weight integer copies on the strip (how often it shows)
---@field pays integer multiplier of the stake for three in a line
---@field color number[] fallback colour when the icon is missing on this client

---@class SlotLineWin
---@field line integer index into Slots.LINES
---@field symbol string symbol key
---@field multiplier integer

---@class SlotResult
---@field stops integer[] stop per reel (1-based strip index of the top row)
---@field grid string[][] grid[row][reel] = symbol key
---@field lines SlotLineWin[] winning paylines, in line order
---@field multiplier integer sum of the winning lines' multipliers (0 = no win)
---@field stake integer copper
---@field payout integer stake * multiplier
---@field net integer payout - stake when it won, else -stake

---@class SlotsModule
local Slots = {}
addon.Slots = Slots

Slots.REELS, Slots.ROWS = 3, 3

---@type SlotSymbol[] highest paying first
Slots.SYMBOLS = {
    { key = "coin", icon = "Interface\\Icons\\INV_Misc_Coin_01", weight = 2, pays = 75, color = { 1, 0.82, 0.1 } },
    { key = "crown", icon = "Interface\\Icons\\INV_Crown_01", weight = 3, pays = 30, color = { 0.95, 0.6, 0.1 } },
    { key = "dragon", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", weight = 4, pays = 15, color = { 0.8, 0.2, 0.2 } },
    { key = "sword", icon = "Interface\\Icons\\INV_Sword_04", weight = 5, pays = 9, color = { 0.6, 0.7, 0.9 } },
    { key = "potion", icon = "Interface\\Icons\\INV_Potion_51", weight = 6, pays = 6, color = { 0.3, 0.5, 1 } },
    { key = "rune", icon = "Interface\\Icons\\INV_Misc_Rune_01", weight = 7, pays = 5, color = { 0.4, 0.9, 0.6 } },
    { key = "bag", icon = "Interface\\Icons\\INV_Misc_Bag_10", weight = 8, pays = 3, color = { 0.7, 0.5, 0.3 } },
}
---@type table<string, SlotSymbol>
Slots.BY_KEY = {}
---@type string[] every symbol's icon (the dev probe checks they exist on this client)
Slots.ICONS = {}
for _, symbol in ipairs(Slots.SYMBOLS) do Slots.BY_KEY[symbol.key] = symbol; Slots.ICONS[#Slots.ICONS + 1] = symbol.icon end

---@type integer[][] payline -> row per reel (1 = top)
Slots.LINES = { { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 }, { 1, 2, 3 }, { 3, 2, 1 } }

-- The reel strip: every symbol `weight` times, dealt round-robin (lowest pay first) so equal symbols are spread out.
---@type string[]
Slots.STRIP = {}
do
    local remaining = {}
    for index, symbol in ipairs(Slots.SYMBOLS) do remaining[index] = symbol.weight end
    local added = true
    while added do
        added = false
        for index = #Slots.SYMBOLS, 1, -1 do
            if remaining[index] > 0 then
                Slots.STRIP[#Slots.STRIP + 1] = Slots.SYMBOLS[index].key
                remaining[index] = remaining[index] - 1
                added = true
            end
        end
    end
end

-- every payline paying the top symbol (Games.SLOTS_MAXIMUM_MULTIPLIER must equal this)
Slots.MAXIMUM_MULTIPLIER = #Slots.LINES * Slots.SYMBOLS[1].pays

-- strip symbol at a (possibly out of range) 1-based index, wrapping around
---@param index integer
---@return string
function Slots.SymbolAt(index)
    local length = #Slots.STRIP
    return Slots.STRIP[((index - 1) % length) + 1]
end

---@param stops integer[]
---@return string[][] grid[row][reel]
function Slots.Grid(stops)
    local grid = {}
    for row = 1, Slots.ROWS do
        grid[row] = {}
        for reel = 1, Slots.REELS do grid[row][reel] = Slots.SymbolAt(stops[reel] + row - 1) end
    end
    return grid
end

-- Winning paylines of a grid and their total multiplier.
---@param grid string[][]
---@return SlotLineWin[] lines
---@return integer multiplier
function Slots.Evaluate(grid)
    local lines, multiplier = {}, 0
    for lineIndex, rows in ipairs(Slots.LINES) do
        local first = grid[rows[1]][1]
        local same = true
        for reel = 2, Slots.REELS do
            if grid[rows[reel]][reel] ~= first then same = false break end
        end
        if same then
            local pays = Slots.BY_KEY[first].pays
            lines[#lines + 1] = { line = lineIndex, symbol = first, multiplier = pays }
            multiplier = multiplier + pays
        end
    end
    return lines, multiplier
end

-- Expected payout per staked copper: each line pays when all three reels show the same symbol in its row, and a row of
-- one reel shows symbol s with probability weight / #STRIP, independently per reel.
---@return number
function Slots.ReturnToPlayer()
    local length, perLine = #Slots.STRIP, 0
    for _, symbol in ipairs(Slots.SYMBOLS) do perLine = perLine + (symbol.weight / length) ^ Slots.REELS * symbol.pays end
    return perLine * #Slots.LINES
end

-- One spin. The stops are drawn and the result STORED here (Games.RecordPlay), before any animation. Returns the result,
-- or nil and the refusal ("stake", "readonly", "name", "funds": more than the money pool holds, feature 018 R18).
---@param myName string|nil
---@param stake any copper, 1..Games.MAXIMUM_STAKE
---@param now integer
---@param randomFunction fun(): number in [0, 1)
---@return SlotResult|nil
---@return FlipRefusal|nil
function Slots.Spin(myName, stake, now, randomFunction)
    if not addon.Utility.SafeInteger(stake, 1, addon.Games.MAXIMUM_STAKE) then return nil, "stake" end
    local refused = addon.Games.Refusal(myName, stake, true)
    if refused then return nil, refused end
    local stops = {}
    for reel = 1, Slots.REELS do stops[reel] = math.min(#Slots.STRIP, 1 + math.floor(randomFunction() * #Slots.STRIP)) end
    local grid = Slots.Grid(stops)
    local lines, multiplier = Slots.Evaluate(grid)
    local payout = stake * multiplier
    local net = multiplier > 0 and payout - stake or -stake
    local stored, refusal = addon.Games.RecordPlay(myName, "slots", stake, net, now)
    if not stored then return nil, refusal end
    return { stops = stops, grid = grid, lines = lines, multiplier = multiplier, stake = stake, payout = payout, net = net }
end

------------------------------------------------------------------ reel motion (what the UI plays)

Slots.SETTLE_SECONDS = 0.2     -- the bounce back after the reel overshoots its stop
Slots.OVERSHOOT = 0.35         -- symbols the reel runs past its stop before settling back

-- Seconds reel `reel` spins: the reels stop one after the other, left to right.
---@param reel integer
---@return number
function Slots.ReelDuration(reel) return 1.1 + 0.55 * (reel - 1) end

-- Total animation time of a spin.
---@return number
function Slots.SpinDuration() return Slots.ReelDuration(Slots.REELS) end

---@class ReelPose
---@field index number fractional strip index shown in the top row (falls while the reel turns: symbols move down)
---@field speed number symbols per second (for motion blur)
---@field done boolean

-- Where reel `reel` is `elapsed` seconds into a spin from fromStop to toStop. The reel turns whole extra rounds (more
-- for later reels), decelerates, runs OVERSHOOT symbols past the stop and settles back onto it.
---@param elapsed number
---@param reel integer
---@param fromStop integer
---@param toStop integer
---@return ReelPose
function Slots.ReelPose(elapsed, reel, fromStop, toStop)
    local length = #Slots.STRIP
    local distance = ((fromStop - toStop) % length) + length * (1 + reel)
    local duration = Slots.ReelDuration(reel)
    local main = duration - Slots.SETTLE_SECONDS
    local travelled, speed
    if elapsed >= duration then
        return { index = toStop, speed = 0, done = true }
    elseif elapsed <= main then
        local progress = math.max(0, elapsed) / main
        local reach = distance + Slots.OVERSHOOT
        travelled = reach * (1 - (1 - progress) ^ 2)
        speed = reach * 2 * (1 - progress) / main
    else
        local progress = (elapsed - main) / Slots.SETTLE_SECONDS
        local eased = progress * progress * (3 - 2 * progress)
        travelled = distance + Slots.OVERSHOOT * (1 - eased)
        speed = Slots.OVERSHOOT * 6 * progress * (1 - progress) / Slots.SETTLE_SECONDS
    end
    return { index = fromStop - travelled, speed = speed, done = false }
end
