local _, addon = ...

-- The UI elements the addon can fade. `frames` lists global frame names; every one that exists is faded together
-- and hovering any of them reveals the whole element. Names are the retail (Edit Mode) ones; a missing name is skipped,
-- so the list works across client versions (e.g. MainActionBar was MainMenuBar before 11.2).
local Elements = {}
addon.Elements = Elements

Elements.list = {
    { key = "actionbar1",  label = "Action Bar 1",      frames = { "MainActionBar", "MainMenuBar" } },
    { key = "actionbar2",  label = "Action Bar 2",      frames = { "MultiBarBottomLeft" } },
    { key = "actionbar3",  label = "Action Bar 3",      frames = { "MultiBarBottomRight" } },
    { key = "actionbar4",  label = "Action Bar 4",      frames = { "MultiBarRight" } },
    { key = "actionbar5",  label = "Action Bar 5",      frames = { "MultiBarLeft" } },
    { key = "actionbar6",  label = "Action Bar 6",      frames = { "MultiBar5" } },
    { key = "actionbar7",  label = "Action Bar 7",      frames = { "MultiBar6" } },
    { key = "actionbar8",  label = "Action Bar 8",      frames = { "MultiBar7" } },
    { key = "stancebar",   label = "Stance Bar",        frames = { "StanceBar" } },
    { key = "petbar",      label = "Pet Bar",           frames = { "PetActionBar" } },
    { key = "player",      label = "Player Frame",      frames = { "PlayerFrame" } },
    { key = "target",      label = "Target Frame",      frames = { "TargetFrame" } },
    { key = "focus",       label = "Focus Frame",       frames = { "FocusFrame" } },
    { key = "pet",         label = "Pet Frame",         frames = { "PetFrame" } },
    { key = "castbar",     label = "Cast Bar",          frames = { "PlayerCastingBarFrame" } },
    { key = "minimap",     label = "Minimap",           frames = { "MinimapCluster" } },
    { key = "buffs",       label = "Buffs",             frames = { "BuffFrame" } },
    { key = "debuffs",     label = "Debuffs",           frames = { "DebuffFrame" } },
    { key = "objectives",  label = "Objective Tracker", frames = { "ObjectiveTrackerFrame" } },
    { key = "micromenu",   label = "Micro Menu",        frames = { "MicroMenuContainer" } },
    { key = "bags",        label = "Bags Bar",          frames = { "BagsBar" } },
    { key = "xpbar",       label = "XP / Rep Bars",     frames = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" } },
    { key = "cdessential", label = "Essential CDs",     frames = { "EssentialCooldownViewer" } },
    { key = "cdutility",   label = "Utility CDs",       frames = { "UtilityCooldownViewer" } },
    { key = "cdbufficons", label = "Tracked Buff Icons", frames = { "BuffIconCooldownViewer" } },
    { key = "cdbuffbars",  label = "Tracked Buff Bars", frames = { "BuffBarCooldownViewer" } },
    { key = "chat",        label = "Chat",              frames = { "ChatFrame1", "GeneralDockManager", "ChatFrameMenuButton", "QuickJoinToastButton" } },
}

local byKey = {}
for _, element in ipairs(Elements.list) do byKey[element.key] = element end

---@param key string
---@return table|nil
function Elements.ByKey(key) return byKey[key] end

-- Existing frames of an element (looked up every time: some are created late, e.g. the cooldown viewers).
---@param element table
---@return table frames
function Elements.Frames(element)
    local frames = {}
    for _, name in ipairs(element.frames) do
        local frame = _G[name]
        if type(frame) == "table" and frame.SetAlpha and not (frame.IsForbidden and frame:IsForbidden()) then
            frames[#frames + 1] = frame
        end
    end
    -- Action bar 1: MainActionBar and MainMenuBar may be the same frame on some clients.
    if #frames == 2 and frames[1] == frames[2] then frames[2] = nil end
    return frames
end
