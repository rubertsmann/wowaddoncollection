local addonName, addon = ...

-- Small helpers every UI file uses (loaded first of the UI files). One place each, so a client difference (a missing
-- icon, an odd frame level) is handled the same way everywhere.
---@class UIHelpersModule
local UIHelpers = {}
addon.UIHelpers = UIHelpers

-- The window settings (db.ui), or an empty table before Store.Init (then nothing is remembered).
---@return table
function UIHelpers.Settings() return (addon.db and addon.db.ui) or {} end

-- Shows `path` on `texture`. When this client has no such file (SetTexture returns false) it shows `fallback`: another
-- path, or a colour { red, green, blue, alpha? } as a flat tile.
---@param texture table
---@param path string
---@param fallback string|number[]
---@return boolean shown true when `path` itself was shown
function UIHelpers.SetTextureOr(texture, path, fallback)
    if texture:SetTexture(path) ~= false then return true end
    if type(fallback) == "table" then
        texture:SetColorTexture(fallback[1], fallback[2], fallback[3], fallback[4] or 1)
    else
        texture:SetTexture(fallback)
    end
    return false
end

-- Whether the mouse is over `frame` (IsMouseOver, else MouseIsOver).
---@param frame table
---@return boolean
function UIHelpers.MouseOver(frame)
    if frame.IsMouseOver then
        local ok, over = pcall(frame.IsMouseOver, frame)
        if ok then return over and true or false end
    end
    return (MouseIsOver and MouseIsOver(frame)) and true or false
end

-- Closes a pop-up `menu` on a mouse click anywhere outside it and outside the `keep` frames (its opener). Uses
-- GLOBAL_MOUSE_DOWN; a client without it gets a screen-wide click catcher at `catcherLevel` (below the menu), which the
-- caller shows with the menu. Returns whether GLOBAL_MOUSE_DOWN works, and the catcher (nil when it does).
---@param menu table
---@param keep table[]
---@param close fun()
---@param catcherLevel number
---@return boolean listens
---@return table|nil catcher
function UIHelpers.CloseOnClickAway(menu, keep, close, catcherLevel)
    local closer = CreateFrame("Frame", nil, menu)
    if pcall(closer.RegisterEvent, closer, "GLOBAL_MOUSE_DOWN") then
        closer:SetScript("OnEvent", function()
            if not menu:IsShown() or UIHelpers.MouseOver(menu) then return end
            for _, frame in ipairs(keep) do if frame:IsShown() and UIHelpers.MouseOver(frame) then return end end
            close()
        end)
        return true, nil
    end
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("MEDIUM"); catcher:SetFrameLevel(math.max(0, catcherLevel or 0))
    catcher:RegisterForClicks("AnyUp"); catcher:SetScript("OnClick", function() close() end)
    catcher:Hide()
    return false, catcher
end

-- A frame's level as a number (some clients return nil for a frame that was never shown).
---@param frame table
---@return integer
function UIHelpers.FrameLevel(frame) return tonumber(frame:GetFrameLevel()) or 1 end
