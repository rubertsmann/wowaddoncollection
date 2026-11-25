-- wow-ui-sim scenario for the second item batch (run by tools/wow-sim.ps1 -Lua). Prepend `SIM_SCENARIO = '<name>'`:
-- "inventory" (owned items, an equipped charm, a running arena buff), "shop" (the shop scrolled to the new groups),
-- "runner" (the Dash item toggles, the shield armed), "survivor" (a run with the bomb button).
local scenario = SIM_SCENARIO or "inventory"
local addon
for index = 1, 60 do
    local name, value = debug.getupvalue(SlashCmdList["GUILDGAMES"], index)
    if not name then break end
    if name == "addon" then addon = value end
end
assert(addon, "no addon upvalue")
local AzeCaught, Utility, Items = addon.AzeCaught, addon.Utility, addon.Items
local now = Utility.Now()
addon.Wallet.Earn(Utility.Me(), 5000 * 10000, "dev", now, "sim")
for _, monster in ipairs({ { 299, "Young Wolf" }, { 1984, "Young Thistle Boar" }, { 1512, "Duskbat" } }) do
    local entry = AzeCaught.NoteFound({ npc = monster[1], name = monster[2], level = 3, classification = "normal" }, now)
    entry.caught = 1
end
if not AzeCaught.Active() then assert(AzeCaught.Select(299, 1)) end
local inventory = Items.Inventory()
inventory.meat, inventory.charmLuck, inventory.charmSteady, inventory.feast, inventory.toy, inventory.elixir = 2, 1, 1, 3, 1, 1
inventory.warPaint, inventory.dashShield, inventory.headStart, inventory.bomb = 1, 2, 1, 2
Items.Equip("charmLuck")
Items.ArenaBuffs().warPaint = 2

SlashCmdList["GUILDGAMES"]("")
addon.UI.SetMode("full")
local top
if scenario == "inventory" or scenario == "shop" then
    addon.GamesTab.SelectGame("caught")
    addon.AzeCaughtPanel.SelectView(scenario)
    addon.ShopView.Refresh(scenario)
    if scenario == "shop" then addon.ShopView.widgets.shop.scroll:SetVerticalScroll(4 * 46 + 18) end
    top = addon.ShopView.widgets[scenario].panel
elseif scenario == "runner" then
    addon.GamesTab.SelectGame("runner")
    addon.RunnerView.state.armed.dashShield = true
    addon.RunnerView.Refresh()
    top = addon.RunnerView.widgets.area
else
    addon.GamesTab.SelectGame("survivor")
    addon.SurvivorArena.widgets.stake.Read = function() return 10000 end
    assert(addon.SurvivorArena.Start(), "no survivor run")
    for _ = 1, 120 do addon.SurvivorArena.Update(1 / 30) end
    addon.SurvivorArena.widgets.panel:SetScript("OnUpdate", nil)
    top = addon.SurvivorArena.widgets.arena
end
while top:GetParent() and top:GetParent() ~= UIParent do top = top:GetParent() end
top:SetScale(1.8); top:SetAlpha(1); top:ClearAllPoints(); top:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20 / 1.8, -20 / 1.8)
error(("sim-036 %s: equipped=%s buffs=%s bombShown=%s"):format(scenario, tostring(Items.Equipped() and Items.Equipped().id),
    tostring(Items.ArenaBuffs().warPaint), tostring(addon.SurvivorArena.widgets.bombButton:IsShown())))
