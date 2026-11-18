-- Combat bug (2026-11-18): the main window could not be opened or closed in combat. Root cause: it contained secure
-- buttons (profession scan buttons, Craft), and a frame with protected children is protected itself, so insecure
-- Show()/Hide() on it is blocked during combat lockdown. UI/SecureDock.lua parks the secure buttons outside the window
-- when combat starts and puts them back afterwards. These tests drive it with recording frame stubs.

local function newFrame(name)
    local frame = { name = name, points = 0, anchored = 0 }
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetParent() return self.parent end
    function frame:ClearAllPoints() self.points = 0 end
    function frame:SetPoint() self.points = self.points + 1 end
    function frame:GetFrameLevel() return self.level or 5 end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:Hide() self.hidden = true end
    function frame:Show() self.hidden = false end
    return frame
end

-- loads UI/SecureDock.lua into a fresh addon with a controllable combat lockdown
local function load(harness)
    local addon = harness.addon()
    local lockdown = { active = false }
    local logged = {}
    local originalWarning = addon.Log.Warning
    addon.Log.Warning = function(area, message, details) logged[#logged + 1] = area; return originalWarning(area, message, details) end
    -- the WoW globals exist only while the file loads, so later test files see the plain offline environment
    local savedCreateFrame, savedUIParent = CreateFrame, UIParent
    CreateFrame = function() return newFrame("holder") end
    UIParent = newFrame("UIParent")
    local chunk = assert(loadfile("UI/SecureDock.lua"))
    chunk("TalentShare", addon)
    CreateFrame, UIParent = savedCreateFrame, savedUIParent
    addon.SecureDock.InCombat = function() return lockdown.active end
    return addon.SecureDock, lockdown, logged
end

local function anchorOnce(button) button:SetPoint("TOPRIGHT"); button.anchored = button.anchored + 1 end

return {
    ["secure dock: a button registered out of combat sits in its window part"] = function(harness)
        local SecureDock = load(harness)
        local tab, button = newFrame("tab"), newFrame("button")
        SecureDock.Register(button, tab, anchorOnce)
        harness.equal(button.parent, tab)
        harness.equal(button.anchored, 1)
    end,

    ["secure dock: combat start parks the buttons outside the window, combat end puts them back"] = function(harness)
        local SecureDock, lockdown = load(harness)
        local tab, button = newFrame("tab"), newFrame("button")
        SecureDock.Register(button, tab, anchorOnce)
        harness.equal(SecureDock.OnCombatStart(), true, "PLAYER_REGEN_DISABLED runs before the lockdown")
        harness.truthy(button.parent ~= tab, "the window part has no secure child during combat")
        harness.equal(button.points, 0, "no anchor ties the parked button to the window")
        harness.equal(SecureDock.IsDocked(), false)
        lockdown.active = false
        SecureDock.OnCombatEnd()
        harness.equal(button.parent, tab)
        harness.equal(button.anchored, 2, "re-anchored")
        harness.equal(SecureDock.IsDocked(), true)
    end,

    ["secure dock: when the lockdown is already active nothing is touched and it is logged"] = function(harness)
        local SecureDock, lockdown, logged = load(harness)
        local tab, button = newFrame("tab"), newFrame("button")
        SecureDock.Register(button, tab, anchorOnce)
        lockdown.active = true
        harness.equal(SecureDock.OnCombatStart(), false)
        harness.equal(button.parent, tab, "a protected frame may not be reparented in combat")
        harness.equal(logged[#logged], "window.secureDock")
    end,

    ["secure dock: a button created during combat starts parked and joins the window after combat"] = function(harness)
        local SecureDock, lockdown = load(harness)
        lockdown.active = true
        local tab, button = newFrame("tab"), newFrame("button")
        SecureDock.Register(button, tab, anchorOnce)
        harness.truthy(button.parent ~= tab, "never a child of the window while locked down")
        harness.equal(button.anchored, 0)
        lockdown.active = false
        SecureDock.OnCombatEnd()
        harness.equal(button.parent, tab)
        harness.equal(button.anchored, 1)
    end,

    ["secure dock: combat end while still locked down waits for the next chance"] = function(harness)
        local SecureDock, lockdown = load(harness)
        local tab, button = newFrame("tab"), newFrame("button")
        SecureDock.Register(button, tab, anchorOnce)
        SecureDock.OnCombatStart()
        lockdown.active = true
        SecureDock.OnCombatEnd()
        harness.truthy(button.parent ~= tab, "still parked")
        lockdown.active = false
        SecureDock.OnCombatEnd()
        harness.equal(button.parent, tab)
    end,

    ["secure dock: the parent the secure button is created with is the parking holder"] = function(harness)
        local SecureDock = load(harness)
        harness.truthy(SecureDock.Holder() ~= nil)
        harness.equal(SecureDock.Holder().hidden, true, "the holder is never shown")
    end,
}
