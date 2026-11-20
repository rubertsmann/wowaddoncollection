-- Console view of the coin flip (feature 014), for tuning without the game:
--   luajit tools/coinflip.lua [H|T] [flips]      (run from the repo root)
-- Prints the pose curve (height bar, coin width, face) the UI plays, then the outcome distribution of simulated flips.
GetServerTime = os.time   -- the client's server clock; Utility.Now() needs it outside the game
dofile("Libs/LibStub/LibStub.lua")
local xmlHandle = assert(io.open("Libs/LibGuildSync/LibGuildSync.xml", "rb"))
for fileName in xmlHandle:read("*a"):gmatch('<Script%s+file="([^"]+)"') do dofile("Libs/LibGuildSync/" .. fileName) end
xmlHandle:close()
local addon = { PROTOCOL_MAJOR = 1, PROTOCOL_MINOR = 0, PROTOCOL = 1, PREFIX = "GGames", SlashCommands = {}, Print = print }
for _, path in ipairs({ "Core/Base/Utility.lua", "Core/Base/Log.lua", "Core/Debug/Trace.lua", "Core/Base/Locale.lua",
    "Core/Data/Store.lua", "Core/Data/Games.lua", "Core/Minigames/CoinFlip.lua" }) do
    assert(loadfile(path))("GuildGames", addon)
end
local outcome = (arg[1] == "T") and "T" or "H"
local flipCount = tonumber(arg[2]) or 10000

local CoinFlip = addon.CoinFlip
print(("Pose curve for outcome %s (%.1f s, height %d px, %d half-turns)"):format(outcome, CoinFlip.DURATION,
    CoinFlip.HEIGHT, CoinFlip.HALF_TURNS[outcome]))
print("   time  face  width                   height")
local steps = 40
for step = 0, steps do
    local elapsed = CoinFlip.DURATION * step / steps
    local pose = CoinFlip.Pose(elapsed, outcome)
    local widthBar = string.rep("#", math.floor(pose.width * 20 + 0.5))
    local heightBar = string.rep("*", math.floor(pose.y / CoinFlip.HEIGHT * 30 + 0.5))
    print(("  %5.2f  %s     %-20s  %4.1f %s"):format(elapsed, pose.face, widthBar, pose.y, heightBar))
end

-- distribution: the real rules (Games.Flip) against an in-memory store
math.randomseed(os.time())
addon.Store.Init(nil)
local heads, wins, net, startTime = 0, 0, 0, os.time() - flipCount
for index = 1, flipCount do
    local result = assert(addon.Games.Flip("Console-Test", 250, index % 2 == 0 and "H" or "T", startTime + index, math.random))
    if result.outcome == "H" then heads = heads + 1 end
    if result.won then wins = wins + 1 end
    net = net + result.net
end
print(("\n%d flips of 2s 50c: heads %.2f%%, wins %.2f%%, net %+d copper"):format(flipCount, heads / flipCount * 100,
    wins / flipCount * 100, net))
local mine = addon.Games.Get("Console-Test")
print(("record: rev %d, total won %d / lost %d, %d recent flips kept, valid for peers: %s"):format(mine.rev, mine.total.won,
    mine.total.lost, #mine.recent, tostring(addon.Games.Sanitize(mine) ~= nil)))
