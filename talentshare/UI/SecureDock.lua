local addonName, addon = ...

-- Combat fix (2026-11-18). A frame with protected (secure) children is protected itself: during combat lockdown insecure
-- code may not Show()/Hide() it, so the main window (it holds the secure profession scan buttons and the Craft button)
-- could not be opened, closed or switched to another tab in a fight.
-- This dock keeps those secure buttons out of the window while in combat: PLAYER_REGEN_DISABLED (fired before the
-- lockdown starts) moves them into a hidden holder outside the window and clears their anchors; PLAYER_REGEN_ENABLED
-- puts them back. A button created during combat starts in the holder. The secure buttons cannot work in combat anyway
-- (no attribute changes, no casting a profession), so nothing is lost while they are parked.
---@class SecureDockModule
local SecureDock = {}
addon.SecureDock = SecureDock

---@class DockEntry
---@field button table the secure frame
---@field parent table where it belongs in the window
---@field anchor fun(button: table) sets its points

---@type DockEntry[]
local entries = {}
local docked = true   -- false while the buttons are parked (combat)

local holder = CreateFrame("Frame", nil, UIParent)
holder:Hide()

-- overridable for the offline tests
---@return boolean
function SecureDock.InCombat() return (InCombatLockdown and InCombatLockdown()) and true or false end

-- the frame secure buttons are created in (never a window part, so creating one in combat cannot protect the window)
---@return table
function SecureDock.Holder() return holder end

---@return boolean true while the secure buttons are in the window
function SecureDock.IsDocked() return docked end

---@param entry DockEntry
local function park(entry)
    entry.button:ClearAllPoints()
    entry.button:SetParent(holder)
end

---@param entry DockEntry
local function attach(entry)
    entry.button:SetParent(entry.parent)
    entry.button:ClearAllPoints()
    entry.anchor(entry.button)
    entry.button:SetFrameLevel(entry.parent:GetFrameLevel() + 2)
end

-- Adds a secure button. Out of combat it goes to `parent` at once; in combat it waits in the holder until combat ends.
---@param button table
---@param parent table
---@param anchor fun(button: table)
function SecureDock.Register(button, parent, anchor)
    local entry = { button = button, parent = parent, anchor = anchor }
    entries[#entries + 1] = entry
    if SecureDock.InCombat() or not docked then
        park(entry)
        docked = false
    else
        attach(entry)
    end
end

-- PLAYER_REGEN_DISABLED. Returns false when the lockdown is already active (the buttons cannot move then).
---@return boolean parked
function SecureDock.OnCombatStart()
    if SecureDock.InCombat() then
        addon.Log.Warning("window.secureDock", "combat lockdown was already active: the window stays locked until combat ends",
            { buttons = #entries })
        return false
    end
    for _, entry in ipairs(entries) do park(entry) end
    docked = false
    return true
end

-- PLAYER_REGEN_ENABLED. Puts the buttons back (if the lockdown still holds, they wait for the next call).
function SecureDock.OnCombatEnd()
    if docked or SecureDock.InCombat() then return end
    for _, entry in ipairs(entries) do attach(entry) end
    docked = true
end
