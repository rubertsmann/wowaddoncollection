-- wow-ui-sim scenario for the shop and the catch items (run by tools/wow-sim.ps1 -Lua). Prepend `SIM_SCENARIO = '<name>'`:
-- "shop" (Shop tab), "inventory" (Inventory tab), "target" (a fake weak elite enemy with the rope icon, the bag row open
-- and the meat clock), "all" (the Shop tab plus the target scene; for the GUI).
local scenario = SIM_SCENARIO or "all"
local addon
for index = 1, 60 do
    local name, value = debug.getupvalue(SlashCmdList["GUILDGAMES"], index)
    if not name then break end
    if name == "addon" then addon = value end
end
assert(addon, "no addon upvalue")
local Items, Api, Catcher, Utility = addon.Items, addon.Api, addon.Catcher, addon.Utility
local now = Utility.Now()
addon.Wallet.Earn(Utility.Me(), 3000 * 10000, "dev", now, "sim")
local inventory = Items.Inventory()
inventory.meat, inventory.trap, inventory.trapElite = 3, 1, 2

if scenario == "target" or scenario == "all" then
    -- a fake nameplate in the middle of the screen and a weak elite wolf as the target
    local plate = CreateFrame("Frame", nil, UIParent)
    plate:SetSize(120, 12); plate:SetPoint("CENTER", UIParent, "CENTER", -260, 120)
    local bar = plate:CreateTexture(nil, "ARTWORK"); bar:SetAllPoints(); bar:SetColorTexture(0.8, 0.1, 0.1, 0.9)
    local guid = "Creature-0-1-2-3-299-0000000001"
    local foe = { guid = guid, npc = 299, name = "Young Wolf", level = 12, classification = "elite", health = 0.2, hostile = true }
    Api.UnitSnapshot = function(unit) if unit == "target" or unit == "nameplate1" then return foe end end
    Api.UnitGuid = function(unit) if unit == "target" or unit == "nameplate1" then return guid end end
    Api.NamePlateFor = function(unit) if unit == "nameplate1" or unit == "target" then return plate end end
    Api.InDungeon = function() return false end
    Catcher.unitByGuid[guid] = "nameplate1"
    Items.Use("meat", { myName = Utility.Me(), now = now })
    Catcher.RefreshIcons()
    addon.CatchItems.Toggle()
end
if scenario ~= "target" then
    SlashCmdList["GUILDGAMES"]("caught")
    addon.AzeCaughtPanel.SelectView(scenario == "inventory" and "inventory" or "shop")
end
local CatchItems = addon.CatchItems.widgets
print(("sim-034 %s: bag=%s row=%s clock=%s icon=%s"):format(scenario, tostring(CatchItems.bag:IsShown()),
    tostring(CatchItems.row:IsShown()), tostring(CatchItems.clock.count:GetText()),
    tostring(Catcher.icons.nameplate1 and Catcher.icons.nameplate1:IsShown())))
