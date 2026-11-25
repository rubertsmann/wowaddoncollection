local addonName, addon = ...

-- The catch items at the target's rope icon: a small round bag button (shown while I own catch items and target a
-- catchable enemy, also at full health since traps need no fight) and, while a catch boost runs, a small clock with the
-- seconds left. A click on the bag opens a row of the owned catch items; a click on one uses it (a trap on the target),
-- a click anywhere else closes the row. The row closes when the target changes.
---@class CatchItemsModule
local CatchItems = {}
addon.CatchItems = CatchItems

local AzeCaught, Api, Items = addon.AzeCaught, addon.Api, addon.Items
local Text, Format = addon.Text, addon.Locale.Format

local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local CLOCK_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local BAG_SIZE, CLOCK_SIZE, ITEM_SIZE, GAP = 22, 20, 28, 5
local widgets = {}
CatchItems.widgets = widgets
CatchItems.state = { guid = nil }

---@param texture table
---@param owner table
local function makeRound(texture, owner)
    pcall(function()
        local mask = owner:CreateMaskTexture()
        mask:SetTexture(addon.Catcher.CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(texture)
        texture:AddMaskTexture(mask)
    end)
end

-- A round icon button: dark ring, round picture, highlight.
---@param parent table
---@param size number
---@param icon string
---@return table
local function roundButton(parent, size, icon)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    local ring = button:CreateTexture(nil, "BACKGROUND"); ring:SetPoint("TOPLEFT", -2, 2); ring:SetPoint("BOTTOMRIGHT", 2, -2)
    ring:SetColorTexture(0.05, 0.05, 0.05, 0.9); makeRound(ring, button)
    button.ring = ring
    local texture = button:CreateTexture(nil, "ARTWORK"); texture:SetAllPoints(); texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addon.UIHelpers.SetTextureOr(texture, icon, { 0.8, 0.6, 0.3 }); makeRound(texture, button)
    button.icon = texture
    local highlight = button:CreateTexture(nil, "HIGHLIGHT"); highlight:SetAllPoints(); highlight:SetColorTexture(1, 1, 1, 0.25)
    makeRound(highlight, button)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.count:SetPoint("BOTTOMRIGHT", 3, -2)
    return button
end

local function hideTooltip() if GameTooltip then GameTooltip:Hide() end end

------------------------------------------------------------------ build

function CatchItems.Build()
    if widgets.holder then return widgets.holder end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(BAG_SIZE, BAG_SIZE); holder:SetFrameStrata("MEDIUM"); holder:SetFrameLevel(20)
    holder:Hide()
    widgets.holder = holder

    local bag = roundButton(holder, BAG_SIZE, BAG_ICON)
    bag:SetPoint("LEFT", 0, 0)
    bag:RegisterForClicks("LeftButtonUp")
    bag:SetScript("OnClick", function() CatchItems.Toggle() end)
    bag:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Text["Catch items"])
        GameTooltip:AddLine(Text["Click: show your catch items."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bag:SetScript("OnLeave", hideTooltip)
    widgets.bag = bag

    local clock = roundButton(holder, CLOCK_SIZE, CLOCK_ICON)
    clock:EnableMouse(true)
    clock.count:ClearAllPoints(); clock.count:SetPoint("CENTER", 0, 0)
    clock.count:SetFontObject("GameFontNormalSmall"); clock.count:SetTextColor(1, 0.85, 0.2)
    clock:SetScript("OnEnter", function(self)
        local item, left = Items.ActiveBoost("catch", addon.Utility.Now())
        if not GameTooltip or not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item.name)
        GameTooltip:AddLine(Format(Text["Every catch succeeds: {seconds} s left."], { seconds = math.ceil(left) }), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clock:SetScript("OnLeave", hideTooltip)
    widgets.clock = clock

    local row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("DIALOG"); row:SetSize(ITEM_SIZE + 2 * GAP, ITEM_SIZE + 2 * GAP)
    row:EnableMouse(true)
    local plate = row:CreateTexture(nil, "BACKGROUND"); plate:SetAllPoints(); plate:SetColorTexture(0.04, 0.04, 0.06, 0.9)
    row:Hide()
    widgets.row, widgets.itemButtons = row, {}
    local listens, catcher = addon.UIHelpers.CloseOnClickAway(row, { bag }, function() CatchItems.Close() end, 0)
    widgets.catcher = catcher
    AzeCaught.Journal("DEBUG", "catchItems.build", "the catch items were built", { globalMouse = listens })

    -- the clock counts down; the whole thing hides when nothing is left to show
    local elapsedTotal = 0
    holder:SetScript("OnUpdate", function(_, elapsedSeconds)
        elapsedTotal = elapsedTotal + (tonumber(elapsedSeconds) or 0)
        if elapsedTotal < 0.25 then return end
        elapsedTotal = 0
        if widgets.clock:IsShown() then CatchItems.Update() end
    end)
    return holder
end

---@param index integer
---@return table
local function itemButton(index)
    local button = widgets.itemButtons[index]
    if button then return button end
    button = roundButton(widgets.row, ITEM_SIZE, BAG_ICON)
    button:SetPoint("TOPLEFT", GAP + (index - 1) * (ITEM_SIZE + GAP), -GAP)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self) CatchItems.UseItem(self.itemID) end)
    button:SetScript("OnEnter", function(self)
        local item = Items.Get(self.itemID)
        if not GameTooltip or not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item.name)
        GameTooltip:AddLine(Items.EffectText(item), 1, 1, 1, true)
        GameTooltip:AddLine(Format(Text["You have {n}."], { n = Items.Count(item.id) }), 0.7, 0.7, 0.7)
        if self.refusal then GameTooltip:AddLine(self.refusal, 1, 0.3, 0.3, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", hideTooltip)
    widgets.itemButtons[index] = button
    return button
end

------------------------------------------------------------------ state

-- The target when it is an enemy the catch items can act on, else nil.
---@return UnitSnapshot|nil
function CatchItems.Target()
    local snapshot = Api.UnitSnapshot("target")
    if not snapshot or not snapshot.npc or snapshot.hostile == false or snapshot.dead == true then return nil end
    if AzeCaught.rolled[snapshot.guid] then return nil end
    return snapshot
end

-- Why `item` cannot be used on `snapshot` now (text), or nil.
---@param item ItemDefinition
---@param snapshot UnitSnapshot|nil
---@return string|nil
function CatchItems.Refusal(item, snapshot)
    if item.kind == "trap" and snapshot and not Items.TrapAllows(item, snapshot.classification) then
        return Text["This trap is too weak for this enemy."]
    end
    return nil
end

-- Where the holder goes: right of the target's rope icon, else where that icon would be (the target frame or the
-- target's nameplate). Nil: nowhere to show it.
---@param settings table
---@return function|nil place
local function placement(settings)
    local icon = addon.Catcher.TargetIcon()
    if icon then return function(holder) holder:SetPoint("LEFT", icon, "RIGHT", 5, 0) end end
    local targetFrame = addon.Catcher.AtTarget(settings)
    if targetFrame then return function(holder) holder:SetPoint("LEFT", targetFrame, "RIGHT", settings.x, settings.y) end end
    local plate = Api.NamePlateFor(addon.Catcher.unitByGuid[Api.UnitGuid("target") or ""] or "target")
    if plate then return function(holder) holder:SetPoint("BOTTOM", plate, "TOP", settings.x, settings.y) end end
    return nil
end

-- Shows, places or hides the bag and the clock for the current target; closes the row when the target changed.
function CatchItems.Update()
    if not widgets.holder then return end
    local holder = widgets.holder
    local settings = AzeCaught.IconSettings()
    local snapshot = settings.shown and CatchItems.Target() or nil
    local guid = snapshot and snapshot.guid
    if guid ~= CatchItems.state.guid then CatchItems.Close() end
    CatchItems.state.guid = guid
    local owned = #Items.Owned("catch") > 0
    local boost, left = Items.ActiveBoost("catch", addon.Utility.Now())
    local place = snapshot and (owned or boost) and placement(settings)
    if not place then
        holder:Hide(); CatchItems.Close()
        return
    end
    holder:ClearAllPoints()
    local ok = pcall(place, holder)
    if not ok then holder:Hide() return end
    widgets.bag:SetShown(owned)
    if not owned then CatchItems.Close() end
    local total = 0
    for _, entry in ipairs(Items.Owned("catch")) do total = total + entry.count end
    widgets.bag.count:SetText(total > 1 and tostring(total) or "")
    widgets.clock:ClearAllPoints()
    if owned then widgets.clock:SetPoint("LEFT", widgets.bag, "RIGHT", 5, 0) else widgets.clock:SetPoint("LEFT", holder, "LEFT", 0, 0) end
    widgets.clock:SetShown(boost ~= nil)
    widgets.clock.count:SetText(boost and tostring(math.ceil(left)) or "")
    holder:SetWidth(BAG_SIZE + CLOCK_SIZE + 5)
    holder:Show()
    if widgets.row:IsShown() then CatchItems.FillRow(snapshot) end
end

-- The row's buttons: one per owned catch item, greyed out with the reason when it cannot act on the target.
---@param snapshot UnitSnapshot|nil
function CatchItems.FillRow(snapshot)
    local owned = Items.Owned("catch")
    for index, entry in ipairs(owned) do
        local button = itemButton(index)
        button.itemID = entry.item.id
        addon.UIHelpers.SetTextureOr(button.icon, entry.item.icon, { 0.8, 0.6, 0.3 })
        button.count:SetText(entry.count > 1 and tostring(entry.count) or "")
        button.refusal = CatchItems.Refusal(entry.item, snapshot)
        pcall(button.icon.SetDesaturated, button.icon, button.refusal ~= nil)
        button:SetAlpha(button.refusal and 0.45 or 1)
        button:Show()
    end
    for index = #owned + 1, #widgets.itemButtons do widgets.itemButtons[index]:Hide() end
    widgets.row:SetWidth(math.max(1, #owned) * (ITEM_SIZE + GAP) + GAP)
    if #owned == 0 then CatchItems.Close() end
end

------------------------------------------------------------------ open, close, use

-- Opens the row above the bag, or closes it.
function CatchItems.Toggle()
    local row = widgets.row
    if not row then return end
    if row:IsShown() then CatchItems.Close() return end
    hideTooltip()
    row:ClearAllPoints()
    row:SetPoint("BOTTOMLEFT", widgets.bag, "TOPLEFT", -GAP, 4)
    row:Show()
    if widgets.catcher then widgets.catcher:Show() end
    CatchItems.FillRow(CatchItems.Target())
end

function CatchItems.Close()
    if widgets.row then widgets.row:Hide() end
    if widgets.catcher then widgets.catcher:Hide() end
end

-- Uses one catch item: a booster at once, a trap on the target.
---@param itemID string
---@return boolean used
function CatchItems.UseItem(itemID)
    local item = Items.Get(itemID)
    if not item then return false end
    local used
    if item.kind == "trap" then
        used = addon.Catcher.UseTrap("target", itemID)
    else
        local ok, reason = Items.Use(itemID, { myName = addon.Utility.Me(), now = addon.Utility.Now() })
        used = ok and true or false
        if ok then
            addon.Print(Format(Text["{item}: every catch succeeds for {seconds} seconds."], { item = item.name, seconds = item.duration }))
            Api.PlaySound(Api.SoundKitFor({ "IG_ABILITY_ICON_DROP", "IG_MAINMENU_OPTION_CHECKBOX_ON" }))
            addon.Events.Fire("ITEMS_CHANGED")
        else
            local text = addon.Catcher.TrapRefusalText(reason)
            Api.ShowOverlay(text)
        end
    end
    if used then CatchItems.Close() end
    CatchItems.Update()
    return used
end

addon.Events.On("ITEMS_CHANGED", function() CatchItems.Update() end)
addon.Log.Protected("catchItems.build", "building the catch items failed", CatchItems.Build)
