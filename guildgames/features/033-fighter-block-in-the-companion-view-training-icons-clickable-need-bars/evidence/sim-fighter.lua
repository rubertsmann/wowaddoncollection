-- wow-ui-sim scenario for feature 033 (run by tools/wow-sim.ps1 -Lua). Prepend `SIM_SCENARIO = '<name>'`:
-- "companion" (full window, Companion view: level line, clickable bars, stat icons, attack training),
-- "minimal" (compact pet view with the training menu open, attack training).
local scenario = SIM_SCENARIO or "companion"
local addon
for index = 1, 60 do
    local name, value = debug.getupvalue(SlashCmdList["GUILDGAMES"], index)
    if not name then break end
    if name == "addon" then addon = value end
end
assert(addon, "no addon upvalue")
local Arena, AzeCaught, Utility = addon.Arena, addon.AzeCaught, addon.Utility
local now = Utility.Now()
local entry = AzeCaught.NoteFound({ npc = 299, name = "Young Wolf", level = 12, classification = "normal", stats = { type = 1 } }, now)
entry.caught = 1
AzeCaught.Select(299, now)
local companion = AzeCaught.Active()
companion.thirst, companion.hunger, companion.energy = 100, 45, 100
local npc = Arena.Npc(299)
npc.tr.atk, npc.tr.def, npc.tr.vit, npc.xp, npc.w, npc.l = 10, 3, 25, 140, 12, 5
Arena.State().training = { stat = "spd", npc = 299, done = AzeCaught.State().activeSeconds + 240 }
if scenario == "minimal" then
    addon.UI.SetMode("minimal")
    addon.PetView.ToggleTraining()
    addon.PetView.Refresh()
else
    SlashCmdList["GUILDGAMES"]("caught")
    addon.AzeCaughtPanel.SelectView("companion")
    addon.AzeCaughtPanel.RefreshCompanion()
end
local icons = scenario == "minimal" and addon.PetView.widgets.trainIcons or addon.ArenaView.widgets.statIcons
print(("sim-033 %s: spd time=%s atk label=%s menu=%s"):format(scenario, tostring(icons.spd.time:GetText()),
    tostring(icons.atk.withLabel and icons.atk.label:GetText() or "-"), tostring(addon.PetView.widgets.trainMenu and addon.PetView.widgets.trainMenu:IsShown())))
