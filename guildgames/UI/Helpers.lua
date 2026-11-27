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

-- A square button for one shop item outside the inventory (a game's item slot): the icon, the owned count, a gold frame
-- while `button:Paint(armed)` says it is armed, greyed out while none is owned or `button.blocked` names why not.
---@param parent table
---@param size number
---@param itemID string
---@param onClick fun(button: table)
---@return table button
function UIHelpers.CreateItemButton(parent, size, itemID, onClick)
    local Items, Text, Format = addon.Items, addon.Text, addon.Locale.Format
    local item = Items.Get(itemID)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.itemID = itemID
    button.frame = button:CreateTexture(nil, "BACKGROUND")
    button.frame:SetPoint("TOPLEFT", -2, 2); button.frame:SetPoint("BOTTOMRIGHT", 2, -2)
    button.icon = button:CreateTexture(nil, "ARTWORK"); button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UIHelpers.SetTextureOr(button.icon, item.icon, { 0.8, 0.6, 0.3 })
    button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.count:SetPoint("BOTTOMRIGHT", -1, 1)
    function button:Paint(armed)
        local count = Items.Count(self.itemID)
        local usable = count > 0 and not self.blocked
        self.armed = armed and true or false
        self.count:SetText(tostring(count))
        if armed then self.frame:SetColorTexture(1, 0.82, 0.2, 0.95) else self.frame:SetColorTexture(0, 0, 0, 0.6) end
        if self.icon.SetDesaturated then self.icon:SetDesaturated(not usable) end
        self.icon:SetAlpha(usable and 1 or 0.4)
    end
    button:SetScript("OnClick", function(self) onClick(self) end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(item.name)
        GameTooltip:AddLine(Items.EffectText(item), 1, 1, 1, true)
        GameTooltip:AddLine(Format(Text["You have {n}."], { n = Items.Count(self.itemID) }), 0.7, 0.7, 0.7)
        if self.hint then GameTooltip:AddLine(self.hint, 1, 0.82, 0, true) end
        if self.blocked then GameTooltip:AddLine(self.blocked, 1, 0.3, 0.3, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:Paint(false)
    return button
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

-- A dark shade and a 1 px border in `color` around `frame`.
---@param frame table
---@param color number[]
---@param shade number the shade's alpha
function UIHelpers.AddBorder(frame, color, shade)
    local back = frame:CreateTexture(nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(0, 0, 0, shade)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local line = frame:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1]); line:SetPoint(edge[2])
        if edge[3] then line:SetHeight(1) else line:SetWidth(1) end
        line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

-- A frame's level as a number (some clients return nil for a frame that was never shown).
---@param frame table
---@return integer
function UIHelpers.FrameLevel(frame) return tonumber(frame:GetFrameLevel()) or 1 end
