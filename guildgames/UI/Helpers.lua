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

-- A frame's level as a number (some clients return nil for a frame that was never shown).
---@param frame table
---@return integer
function UIHelpers.FrameLevel(frame) return tonumber(frame:GetFrameLevel()) or 1 end
