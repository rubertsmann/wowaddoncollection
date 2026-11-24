-- wow-ui-sim scenario for feature 032 (run by tools/wow-sim.ps1 -Lua). The first line of the run sets SCENARIO:
-- "incoming" (a challenge to me: Accept / Decline / Counter offer), "counterin" (the dummy countered my challenge),
-- "ready" (a decided fight I have not watched), "watched" (the same fight after the replay).
local scenario = SIM_SCENARIO or "incoming"
local addon
for index = 1, 60 do
    local name, value = debug.getupvalue(SlashCmdList["GUILDGAMES"], index)
    if not name then break end
    if name == "addon" then addon = value end
end
assert(addon, "no addon upvalue")
local Arena, AzeCaught, Utility = addon.Arena, addon.AzeCaught, addon.Utility
local now = Utility.Now()
local me = Utility.Me()
-- my companion
local entry = AzeCaught.NoteFound({ npc = 299, name = "Young Wolf", level = 12, classification = "normal", stats = { type = 1 } }, now)
entry.caught = 1
AzeCaught.Select(299, now)
-- the dummy joins the guild list (memory only)
local dummy = Arena.DummyRecord(Arena.Fighter(AzeCaught.Active()), now)
addon.Games.simulated[Arena.DUMMY_NAME] = dummy
local records = addon.Games.AllRecords()
local selected
if scenario == "incoming" then
    selected = Arena.DummyChallenge(dummy, me, 50000, now - 60)
elseif scenario == "counterin" then
    selected = assert(Arena.Challenge(records, me, dummy.name, 50000, now - 120))
    dummy.arena.co[selected] = { wg = 120000, at = now - 60, f = Utility.DeepCopy(dummy.dummyFighter) }
else
    selected = assert(Arena.Challenge(records, me, dummy.name, 50000, now - 900))
    dummy.arena.an[selected] = { ok = true, at = now - 800, f = Utility.DeepCopy(dummy.dummyFighter) }
end
addon.Catcher.ArenaTick(true)
SlashCmdList["GUILDGAMES"]("caught arena")
addon.ArenaView.SelectPage("fights")
addon.ArenaView.state.selected = selected
addon.ArenaView.Refresh()
if scenario == "watched" then
    addon.ArenaView.Watch(selected)
    addon.ArenaView.FinishReplay()
    addon.ArenaView.StopReplay()
    addon.ArenaView.Refresh()
end
local fight = Arena.Fights(addon.Games.AllRecords(), me, Utility.Now())[selected]
print(("sim-032 %s: state=%s revealed=%s w+l=%d"):format(scenario, fight and fight.state or "nil",
    tostring(fight and Arena.Revealed(fight, Utility.Now())), Arena.State().w + Arena.State().l))
