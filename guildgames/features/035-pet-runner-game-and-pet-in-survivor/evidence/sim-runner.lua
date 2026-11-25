-- wow-ui-sim scenario for the runner game and the companion in Survivor (run by tools/wow-sim.ps1 -Lua). Prepend
-- `SIM_SCENARIO = '<name>'`: "idle" (the runner panel before a run), "run" (a frozen frame mid-run: the companion in the
-- air, a ground monster and a flyer), "locked" (no companion), "survivor" (a survivor run with the companion in the tower's
-- place), "live" (a live run for the GUI: click the play area).
local scenario = SIM_SCENARIO or "live"
local addon
for index = 1, 60 do
    local name, value = debug.getupvalue(SlashCmdList["GUILDGAMES"], index)
    if not name then break end
    if name == "addon" then addon = value end
end
assert(addon, "no addon upvalue")
local AzeCaught, Utility, Runner = addon.AzeCaught, addon.Utility, addon.Runner
local now = Utility.Now()
addon.Wallet.Earn(Utility.Me(), 500 * 10000, "dev", now, "sim")

if scenario ~= "locked" then
    for _, monster in ipairs({ { 299, "Young Wolf" }, { 1984, "Young Thistle Boar" }, { 1512, "Duskbat" } }) do
        local entry = AzeCaught.NoteFound({ npc = monster[1], name = monster[2], level = 3, classification = "normal",
            stats = monster[1] == 1512 and { family = "Bat" } or nil }, now)
        entry.caught = 1
    end
    if not AzeCaught.Active() then assert(AzeCaught.Select(299, 1)) end
end

SlashCmdList["GUILDGAMES"]("")
addon.UI.SetMode("full")
local game = scenario == "survivor" and "survivor" or "runner"
addon.GamesTab.SelectGame(game)

if scenario == "run" then
    local run = assert(addon.RunnerView.Start(), "no run")
    run.spawnIn = 1e9
    for _ = 1, 30 do addon.RunnerView.Update(1 / 60) end
    run.distance = 212 * Runner.PIXELS_PER_METER
    run.y, run.vy, run.grounded = 46, 50, false
    run.obstacles = { { id = 901, x = 140, y = 0, fly = false, pick = 1 }, { id = 902, x = 236, y = Runner.FLYER_Y, fly = true, pick = 3 } }
    addon.RunnerView.Update(0)
    addon.RunnerView.widgets.panel:SetScript("OnUpdate", nil)   -- freeze the frame for the screenshot
elseif scenario == "survivor" then
    addon.SurvivorArena.widgets.stake.Read = function() return 10000 end
    assert(addon.SurvivorArena.Start(), "no survivor run")
    for _ = 1, 120 do addon.SurvivorArena.Update(1 / 30) end
    addon.SurvivorArena.widgets.panel:SetScript("OnUpdate", nil)
end
-- large and at the top left, so the screenshot is readable
local top = addon.RunnerView.widgets.area
while top:GetParent() and top:GetParent() ~= UIParent do top = top:GetParent() end
top:SetScale(1.8); top:SetAlpha(1); addon.GamesTab.widgets.panels[game]:SetAlpha(1); top:ClearAllPoints(); top:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20 / 1.8, -20 / 1.8)
local widgets = addon.RunnerView.widgets
print(("sim-035 %s: game=%s busy=%s lock=%s runner=%s pet=%s tower=%s"):format(scenario, addon.GamesTab.state.game,
    tostring(addon.GamesTab.IsBusy()), tostring(widgets.lockText:IsShown()), tostring(widgets.runner:IsShown()),
    tostring(addon.SurvivorArena.widgets.pet:IsShown()), tostring(addon.SurvivorArena.widgets.tower:IsShown())))
