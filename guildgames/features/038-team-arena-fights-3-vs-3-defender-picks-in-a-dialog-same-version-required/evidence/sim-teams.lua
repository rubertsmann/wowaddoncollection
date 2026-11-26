-- wow-ui-sim scenario for the roster (037) and team fights (038), run by tools/wow-sim.ps1 -Lua. Prepend
-- `SIM_SCENARIO = '<name>'`: "roster" (the collection's roster with two wolves, a resting one selected), "accept" (the
-- dummy's challenge: the team dialog with its team in full), "challenge" (the challenge modal with my team),
-- "replay" (a team fight after the second fighter entered).
local scenario = SIM_SCENARIO or "roster"
local addon
for index = 1, 60 do
    local name, value = debug.getupvalue(SlashCmdList["GUILDGAMES"], index)
    if not name then break end
    if name == "addon" then addon = value end
end
assert(addon, "no addon upvalue")
local AzeCaught, Arena, Utility = addon.AzeCaught, addon.Arena, addon.Utility
local now = Utility.Now()
local me = Utility.Me()
addon.Wallet.Earn(me, 5000 * 10000, "dev", now, "sim")
for _, monster in ipairs({ { 299, "Young Wolf", 2, 1 }, { 1984, "Young Thistle Boar", 1, 1 }, { 1512, "Duskbat", 1, 1 }, { 2956, "Adult Plainstrider", 1, 1 } }) do
    local entry = AzeCaught.NoteFound({ npc = monster[1], name = monster[2], level = 5, classification = "normal", stats = { type = monster[4] } }, now)
    entry.caught = monster[3]
end
AzeCaught.Reconcile()
if not AzeCaught.Active() then assert(AzeCaught.Select(299, now)) end
-- some arena progress, so the rows and fighters differ
for index, companion in ipairs(AzeCaught.Roster()) do
    local progress = Arena.Progress(companion)
    progress.xp = index * 70
    progress.tr.atk = index
end

SlashCmdList["GUILDGAMES"]("")
addon.UI.SetMode("full")
addon.GamesTab.SelectGame("caught")
local Panel, ArenaView = addon.AzeCaughtPanel, addon.ArenaView
local top
local team = {}
for _, companion in ipairs(AzeCaught.Roster()) do if #team < 3 then team[#team + 1] = Arena.Fighter(companion) end end
local dummy = Arena.DummyRecord(team, now, 7)
addon.Games.simulated[Arena.DUMMY_NAME] = dummy
local detail = ""
if scenario == "roster" then
    Panel.SelectView("collection"); Panel.SelectSection("caught")
    local roster = AzeCaught.Roster()
    Panel.SelectRow(roster[2].npc, roster[2].uid)
    top = Panel.widgets.collectionList
    detail = "rows=" .. #roster
elseif scenario == "accept" then
    local id = Arena.DummyChallenge(dummy, me, 50000, now - 30)
    Panel.SelectView("arena"); ArenaView.SelectPage("fights")
    ArenaView.state.selected = id
    ArenaView.Refresh()
    ArenaView.Decide(true)
    top = addon.TeamDialog.widgets.dialog
    detail = "open=" .. tostring(addon.TeamDialog.IsOpen()) .. " chance=" .. tostring(addon.TeamDialog.Chance())
elseif scenario == "challenge" then
    Panel.SelectView("guild")
    local dummyRow
    for _, row in ipairs(addon.Model.BuildCompanionRows(addon.Games.AllRecords(), me)) do
        if row.nameRaw == Arena.DUMMY_NAME then dummyRow = row end
    end
    assert(ArenaView.OpenChallenge(dummyRow), "the challenge modal")
    top = ArenaView.widgets.challenge
    detail = "uids=" .. #ArenaView.challenge.uids
else
    local uids = {}
    for _, companion in ipairs(AzeCaught.Roster()) do if #uids < 3 then uids[#uids + 1] = companion.uid end end
    local records = addon.Games.AllRecords()
    local id = assert(Arena.Challenge(records, me, dummy.name, 0, now - 900, uids))
    Arena.DummyRespond(dummy, me, now - 800)
    Panel.SelectView("arena"); ArenaView.SelectPage("fights")
    local events = ArenaView.Watch(id)
    if ArenaView.state.ticker then ArenaView.state.ticker:Cancel(); ArenaView.state.ticker = nil end
    local result = ArenaView.state.result
    local stop = #result.events
    for index, event in ipairs(result.events) do
        if event.k == "enter" then stop = math.min(#result.events, index + 2) break end
    end
    for _ = 1, stop do ArenaView.Step() end
    top = ArenaView.widgets.replay
    detail = ("events=%d step=%d winner=%s enteredA=%d enteredB=%d"):format(events, stop, result.winner, result.entered.a, result.entered.b)
end
while top:GetParent() and top:GetParent() ~= UIParent do top = top:GetParent() end
top:SetScale(1.8); top:SetAlpha(1); top:ClearAllPoints(); top:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 420 / 1.8, -20 / 1.8)
error(("sim-038 %s: roster=%d active=%s %s"):format(scenario, #AzeCaught.Roster(), tostring(AzeCaught.Active() and AzeCaught.Active().uid), detail))
