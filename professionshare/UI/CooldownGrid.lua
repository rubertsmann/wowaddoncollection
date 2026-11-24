local addonName, addon = ...

-- The Cooldowns mode of the Misc Items tab: a grid of action-button-sized tiles, one per timegated craft (or one per crafter).
-- A tile shows the craft icon with a cooldown sweep and the time left, a badge with how many crafters are ready, and the
-- profession colour as its border. A tile that becomes ready flashes once and then glows while it stays ready.
-- Clicking whispers the best crafter with the craft's link; right-clicking lists every crafter.
-- The view-model comes from Model.BuildCooldownTiles; this file only draws it. One ticker updates the time texts once per
-- second and runs only while the grid is shown.
---@class CooldownGridModule
local CooldownGrid = {}
addon.CooldownGrid = CooldownGrid

local Text, Format = addon.Text, addon.Locale.Format

CooldownGrid.TILE_SIZE = 36            -- an action button
local CELL_WIDTH, CELL_HEIGHT = 78, 62  -- tile plus its label and some air
local PADDING = 6
local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local BORDER_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local SHINE_TEXTURE = "Interface\\Cooldown\\star4"
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"
local MAXIMUM_TOOLTIP_CRAFTERS = 15
local ONLINE_ICON, OFFLINE_ICON = "|TInterface\\COMMON\\Indicator-Green:12:12|t ", "|TInterface\\COMMON\\Indicator-Gray:12:12|t "

-- border colour per profession skill line (r, g, b)
local PROFESSION_COLORS = {
    [171] = { 0.25, 0.9, 0.45 },   -- Alchemy
    [197] = { 0.75, 0.55, 1.0 },   -- Tailoring
    [165] = { 0.85, 0.6, 0.3 },    -- Leatherworking
}
local DEFAULT_COLOR = { 0.8, 0.8, 0.8 }

---@return number
local function gameTime() return GetTime and GetTime() or 0 end

---@return integer
local function now() return addon.Utility.Now() end

---@param frame table
---@param fromAlpha number
---@param toAlpha number
---@param seconds number
---@return table animation group
local function pulse(frame, fromAlpha, toAlpha, seconds)
    local group = frame:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(fromAlpha); fade:SetToAlpha(toAlpha); fade:SetDuration(seconds); fade:SetSmoothing("IN_OUT")
    return group
end

-- the one-off star that spins and fades when a tile becomes ready
---@param texture table
---@return table animation group
local function shineAnimation(texture)
    local group = texture:CreateAnimationGroup()
    local appear = group:CreateAnimation("Alpha")
    appear:SetFromAlpha(0); appear:SetToAlpha(1); appear:SetDuration(0.15); appear:SetOrder(1)
    local grow = group:CreateAnimation("Scale")
    if grow.SetScaleFrom then grow:SetScaleFrom(0.4, 0.4); grow:SetScaleTo(1.6, 1.6) else grow:SetScale(4, 4) end
    grow:SetDuration(0.6); grow:SetOrder(1)
    local spin = group:CreateAnimation("Rotation")
    spin:SetDegrees(-120); spin:SetDuration(0.75); spin:SetOrder(1)
    local vanish = group:CreateAnimation("Alpha")
    vanish:SetFromAlpha(1); vanish:SetToAlpha(0); vanish:SetDuration(0.45); vanish:SetStartDelay(0.3); vanish:SetOrder(1)
    group:SetScript("OnFinished", function() texture:SetAlpha(0) end)
    return group
end

---@param parent table
---@param grid table
---@return table tile frame
local function createTile(parent, grid)
    local size = CooldownGrid.TILE_SIZE
    local tile = CreateFrame("Button", nil, parent)
    tile:SetSize(size, size)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile.view = {}   -- what this frame shows right now (a plain table: frame fields would mix with the widget API)

    tile.glow = tile:CreateTexture(nil, "BACKGROUND")
    tile.glow:SetTexture(BORDER_TEXTURE); tile.glow:SetBlendMode("ADD")
    tile.glow:SetSize(size * 1.9, size * 1.9); tile.glow:SetPoint("CENTER")
    tile.glow:SetVertexColor(1, 0.82, 0.25); tile.glow:SetAlpha(0)
    tile.glowPulse = pulse(tile.glow, 0.35, 0.95, 0.9)

    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetPoint("TOPLEFT", 1, -1); tile.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    tile.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    tile.border = tile:CreateTexture(nil, "OVERLAY")
    tile.border:SetTexture(BORDER_TEXTURE); tile.border:SetBlendMode("ADD")
    tile.border:SetSize(size * 1.75, size * 1.75); tile.border:SetPoint("CENTER")

    local highlight = tile:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(HIGHLIGHT_TEXTURE); highlight:SetBlendMode("ADD"); highlight:SetAllPoints(tile.icon)

    tile.cooldown = CreateFrame("Cooldown", nil, tile, "CooldownFrameTemplate")
    tile.cooldown:SetAllPoints(tile.icon)
    if tile.cooldown.SetDrawEdge then tile.cooldown:SetDrawEdge(true) end
    if tile.cooldown.SetDrawBling then tile.cooldown:SetDrawBling(true) end
    if tile.cooldown.SetHideCountdownNumbers then tile.cooldown:SetHideCountdownNumbers(true) end
    if tile.cooldown.SetSwipeColor then tile.cooldown:SetSwipeColor(0, 0, 0, 0.7) end

    -- texts above the sweep
    local overlay = CreateFrame("Frame", nil, tile)
    overlay:SetAllPoints(tile); overlay:SetFrameLevel((tile.cooldown:GetFrameLevel() or 1) + 2)
    tile.timer = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    tile.timer:SetPoint("CENTER", 0, 0)
    tile.badge = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    tile.badge:SetPoint("BOTTOMRIGHT", -2, 2); tile.badge:SetJustifyH("RIGHT")
    tile.corner = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.corner:SetPoint("TOPRIGHT", -2, -1); tile.corner:SetText("?")

    tile.shine = overlay:CreateTexture(nil, "OVERLAY")
    tile.shine:SetTexture(SHINE_TEXTURE); tile.shine:SetBlendMode("ADD")
    tile.shine:SetSize(size * 1.6, size * 1.6); tile.shine:SetPoint("CENTER"); tile.shine:SetAlpha(0)
    tile.shineAnimation = shineAnimation(tile.shine)

    tile.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.label:SetPoint("TOP", tile, "BOTTOM", 0, -3)
    tile.label:SetWidth(CELL_WIDTH - 4); tile.label:SetHeight(22)
    tile.label:SetJustifyH("CENTER"); tile.label:SetJustifyV("TOP")
    if tile.label.SetWordWrap then tile.label:SetWordWrap(true) end

    tile:SetScript("OnEnter", function(self)
        self.icon:SetPoint("TOPLEFT", -1, 1); self.icon:SetPoint("BOTTOMRIGHT", 1, -1)   -- grows a little
        if self.tileData then grid:ShowTooltip(self, self.tileData) end
    end)
    tile:SetScript("OnLeave", function(self)
        self.icon:SetPoint("TOPLEFT", 1, -1); self.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)
    tile:SetScript("OnClick", function(self, mouseButton)
        if self.tileData then grid:Click(self, self.tileData, mouseButton) end
    end)
    return tile
end

------------------------------------------------------------------ drawing one tile

---@param tile table
---@param tileData CooldownTile
---@param serverNow integer
local function drawTimer(tile, tileData, serverNow)
    local remaining = tileData.readyAt and (tileData.readyAt - serverNow) or 0
    if tileData.state == "cooling" and remaining > 0 then
        tile.timer:SetText(addon.Model.FormatCooldownShort(remaining))
        if tileData.estimated then tile.timer:SetTextColor(1, 0.7, 0.3) else tile.timer:SetTextColor(1, 1, 1) end
    else
        tile.timer:SetText("")
    end
    return remaining
end

---@param tile table
---@param isReady boolean
local function setGlow(tile, isReady)
    tile.view.glowing = isReady
    if isReady then
        if not tile.glowPulse:IsPlaying() then tile.glow:SetAlpha(0.6); tile.glowPulse:Play() end
    else
        tile.glowPulse:Stop(); tile.glow:SetAlpha(0)
    end
end

---@param tile table
---@param tileData CooldownTile
---@param serverNow integer
---@param expanded boolean
---@param previousState string|nil the state this tile key had in the last draw
local function drawTile(tile, tileData, serverNow, expanded, previousState)
    tile.tileData = tileData
    tile.icon:SetTexture(tileData.icon or QUESTION_MARK_ICON)
    local color = PROFESSION_COLORS[tileData.group.skillLine] or DEFAULT_COLOR
    tile.border:SetVertexColor(color[1], color[2], color[3])
    tile.border:SetAlpha(tileData.state == "none" and 0.25 or 0.75)

    local cooling, ready = tileData.state == "cooling", tileData.state == "ready"
    local anyOnline = tileData.best ~= nil or (tileData.crafters[1] and tileData.crafters[1].online)
    tile.icon:SetDesaturated(cooling or tileData.state == "none")
    local brightness = (tileData.state == "none" and 0.35) or (cooling and 0.65) or 1
    tile.icon:SetVertexColor(brightness, brightness, brightness)
    tile:SetAlpha((tileData.state ~= "none" and not anyOnline) and 0.55 or 1)

    if cooling and tileData.readyAt then
        local remaining = tileData.readyAt - serverNow
        local startedAt = gameTime() - (tileData.duration - remaining)
        if not tile.view.shownReadyAt or math.abs(tile.view.shownReadyAt - tileData.readyAt) > 2 then
            tile.cooldown:SetCooldown(startedAt, tileData.duration)
            tile.view.shownReadyAt = tileData.readyAt
        end
    else
        if tile.view.shownReadyAt then tile.cooldown:Clear() end
        tile.view.shownReadyAt = nil
    end
    drawTimer(tile, tileData, serverNow)

    local crafterCount = #tileData.crafters
    if expanded then tile.badge:SetText("")
    elseif crafterCount > 0 then
        tile.badge:SetText(("%d/%d"):format(tileData.readyCount, crafterCount))
        if tileData.readyCount > 0 then tile.badge:SetTextColor(0.3, 1, 0.45) else tile.badge:SetTextColor(0.8, 0.8, 0.8) end
    else tile.badge:SetText("") end
    local hasUnknown = false
    for _, crafter in ipairs(tileData.crafters) do if crafter.state == "unknown" then hasUnknown = true end end
    tile.corner:SetShown(hasUnknown)

    setGlow(tile, ready and anyOnline)
    if ready and previousState == "cooling" then
        tile.shine:SetAlpha(0); tile.shineAnimation:Stop(); tile.shineAnimation:Play()
    end

    if expanded then
        local crafter = tileData.crafter or tileData.crafters[1]
        local label = crafter and crafter.playerName or ""
        if crafter and not crafter.online then label = "|cff888888" .. label .. "|r"
        elseif crafter and crafter.mine then label = "|cff33ff99" .. label .. "|r" end
        tile.label:SetText(label)
    else
        tile.label:SetText(tileData.state == "none" and ("|cff888888" .. tileData.name .. "|r") or tileData.name)
    end
end

------------------------------------------------------------------ tooltip and clicks

---@param crafter CooldownCrafter
---@param serverNow integer
---@param timeAgo fun(timestamp: integer): string
---@return string text
---@return number red
---@return number green
---@return number blue
local function crafterLine(crafter, serverNow, timeAgo)
    local dot = crafter.online and ONLINE_ICON or OFFLINE_ICON
    local stateText
    local red, green, blue = 0.8, 0.8, 0.8
    if crafter.state == "ready" then
        stateText, red, green, blue = Text["ready"], 0.3, 1, 0.45
    elseif crafter.state == "cooling" then
        local remaining = math.max((crafter.readyAt or serverNow) - serverNow, 0)
        local readyClock = date and date("%a %H:%M", (time and time() or serverNow) + remaining) or ""
        stateText = Format(Text["{time} (ready {when})"], { time = addon.Model.FormatCooldownLong(remaining), when = readyClock })
        if crafter.estimated then stateText = stateText .. " " .. Text["estimated"] end
        red, green, blue = 1, 0.65, 0.25
    else
        stateText, red, green, blue = Text["no cooldown data yet"], 0.6, 0.6, 0.6
    end
    local name = crafter.mine and (crafter.playerName .. " " .. Text["(you)"]) or crafter.playerName
    local seenText = crafter.seen and ("  |cff777777" .. Format(Text["updated {ago}"], { ago = timeAgo(crafter.seen) }) .. "|r") or ""
    return dot .. name .. ": " .. stateText .. seenText, red, green, blue
end

---@param tileData CooldownTile
---@return string|nil whom a left click whispers
local function whisperTarget(tileData) return tileData.best and tileData.best.who or nil end

---@class CooldownGridOptions
---@field whisper fun(playerName: string, insertText: fun(): string) the window's whisper (opens the chat box, inserts text)
---@field timeAgo fun(timestamp: integer): string
---@field onExpire fun() a shown cooldown ran out: the window rebuilds the tiles

-- Creates the grid inside `parent`. Returns the grid object; its `frame` is positioned by the caller.
---@param parent table
---@param options CooldownGridOptions
---@return table grid
function CooldownGrid.Create(parent, options)
    local grid = { tiles = {}, shownTiles = {}, lastState = {}, options = options, expanded = false }

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(100, 100)
    scrollFrame:SetScrollChild(content)
    grid.frame, grid.content = scrollFrame, content
    grid.emptyText = scrollFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    grid.emptyText:SetPoint("CENTER"); grid.emptyText:SetWidth(460)

    function grid:Layout()
        local width = self.frame:GetWidth() or 0
        local columns = math.max(1, math.floor((width - PADDING) / CELL_WIDTH))
        for index, tile in ipairs(self.shownTiles) do
            local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", self.content, "TOPLEFT",
                PADDING + column * CELL_WIDTH + (CELL_WIDTH - CooldownGrid.TILE_SIZE) / 2, -(PADDING + 4 + row * CELL_HEIGHT))
        end
        local rows = math.ceil(#self.shownTiles / columns)
        self.content:SetSize(math.max(width, 1), PADDING * 2 + rows * CELL_HEIGHT)
    end
    scrollFrame:SetScript("OnSizeChanged", function() grid:Layout() end)

    -- Draws `tiles` (Model.BuildCooldownTiles or ExpandCooldownTiles); tile frames are pooled and reused.
    ---@param tileDataList CooldownTile[]
    ---@param expanded boolean
    ---@param emptyText string|nil shown when the list is empty
    function grid:SetTiles(tileDataList, expanded, emptyText)
        local serverNow = now()
        self.expanded = expanded
        local states = {}
        for index, tileData in ipairs(tileDataList) do
            tileData.readyAt = tileData.state == "cooling" and (serverNow + tileData.remaining) or nil
            local tile = self.tiles[index]
            if not tile then tile = createTile(self.content, self); self.tiles[index] = tile end
            if tile.view.tileKey ~= tileData.key then tile.view.shownReadyAt = nil; tile.cooldown:Clear() end
            tile.view.tileKey = tileData.key
            drawTile(tile, tileData, serverNow, expanded, self.lastState[tileData.key])
            states[tileData.key] = tileData.state
            tile:Show(); tile.label:Show()
            self.shownTiles[index] = tile
        end
        for index = #tileDataList + 1, #self.tiles do
            local tile = self.tiles[index]
            tile:Hide(); tile.label:Hide(); tile.tileData = nil; tile.glowPulse:Stop()
            self.shownTiles[index] = nil
        end
        self.lastState = states
        self.emptyText:SetText(emptyText or "")
        self.emptyText:SetShown(#tileDataList == 0 and emptyText ~= nil)
        self:Layout()
    end

    -- once per second while shown: the time texts; a cooldown that ran out makes the window rebuild the tiles
    function grid:Tick()
        local serverNow, expired = now(), false
        for _, tile in ipairs(self.shownTiles) do
            local tileData = tile.tileData
            if tileData and tileData.state == "cooling" then
                if drawTimer(tile, tileData, serverNow) <= 0 then expired = true end
            end
        end
        if expired and self.options.onExpire then self.options.onExpire() end
    end

    scrollFrame:SetScript("OnShow", function()
        if grid.ticker then grid.ticker:Cancel() end
        grid.ticker = C_Timer and C_Timer.NewTicker and C_Timer.NewTicker(1, function() grid:Tick() end) or nil
        for _, tile in ipairs(grid.shownTiles) do setGlow(tile, tile.view.glowing == true) end
    end)
    scrollFrame:SetScript("OnHide", function()
        if grid.ticker then grid.ticker:Cancel(); grid.ticker = nil end
        for _, tile in ipairs(grid.tiles) do tile.glowPulse:Stop(); tile.shineAnimation:Stop() end
    end)

    ---@param owner table
    ---@param tileData CooldownTile
    function grid:ShowTooltip(owner, tileData)
        if not GameTooltip then return end
        local serverNow = now()
        local group = tileData.group
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(tileData.name, 1, 0.82, 0)
        GameTooltip:AddLine(tileData.profession, 0.6, 0.6, 0.6)
        local itemName = addon.Api.ItemName(group.produces)
        if itemName then GameTooltip:AddLine(Format(Text["Makes: {item}"], { item = itemName }), 1, 1, 1) end
        if #group.recipes > 1 then
            GameTooltip:AddLine(Text["All transmutes share one cooldown."], 0.8, 0.8, 0.8, true)
        elseif #group.reagents > 0 then
            local reagentTexts = {}
            for index, reagent in ipairs(group.reagents) do
                reagentTexts[index] = ("%dx %s"):format(reagent.count,
                    addon.Api.ItemName(reagent.itemID) or Format(Text["Item #{id}"], { id = reagent.itemID }))
            end
            GameTooltip:AddLine(Format(Text["Reagents: {list}"], { list = table.concat(reagentTexts, ", ") }), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(" ")
        if #tileData.crafters == 0 then
            GameTooltip:AddLine(Text["Nobody in the guild is known to craft this."], 0.6, 0.6, 0.6, true)
        end
        for index, crafter in ipairs(tileData.crafters) do
            if index > MAXIMUM_TOOLTIP_CRAFTERS then
                GameTooltip:AddLine(Format(Text["+{n} more"], { n = #tileData.crafters - MAXIMUM_TOOLTIP_CRAFTERS }), 0.6, 0.6, 0.6)
                break
            end
            GameTooltip:AddLine(crafterLine(crafter, serverNow, self.options.timeAgo))
        end
        GameTooltip:AddLine(" ")
        if tileData.best then
            GameTooltip:AddLine(Format(Text["Click: whisper {name}"], { name = tileData.best.playerName }), 0.6, 0.8, 1, true)
        elseif #tileData.crafters > 0 then
            GameTooltip:AddLine(Text["Nobody who can craft this is online."], 0.6, 0.6, 0.6, true)
        end
        if not self.expanded and #tileData.crafters > 0 then
            GameTooltip:AddLine(Text["Right-click: choose a crafter"], 0.6, 0.8, 1, true)
        end
        GameTooltip:Show()
    end

    ---@param tileData CooldownTile
    ---@param playerName string|nil
    function grid:Whisper(tileData, playerName)
        if not playerName then
            addon.Print(Text["Nobody who can craft this is online."])
            return
        end
        addon.Log.Information("cooldownGrid.whisper", "a cooldown tile whispers a crafter", { group = tileData.group.key })
        self.options.whisper(playerName, function()
            return addon.Model.ChatText(addon.Api.CraftLink(tileData.group), tileData.name)
        end)
    end

    ---@param owner table
    ---@param tileData CooldownTile
    ---@param mouseButton string
    function grid:Click(owner, tileData, mouseButton)
        if mouseButton ~= "RightButton" or self.expanded or #tileData.crafters == 0 then
            self:Whisper(tileData, whisperTarget(tileData))
            return
        end
        if not (MenuUtil and MenuUtil.CreateContextMenu) then   -- no menus on this client: the left-click target
            self:Whisper(tileData, whisperTarget(tileData))
            return
        end
        local serverNow = now()
        MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
            rootDescription:CreateTitle(tileData.name)
            for _, crafter in ipairs(tileData.crafters) do
                local label = crafterLine(crafter, serverNow, self.options.timeAgo)
                local button = rootDescription:CreateButton(label, function() self:Whisper(tileData, crafter.who) end)
                if (not crafter.online or crafter.mine) and button.SetEnabled then button:SetEnabled(false) end
            end
        end)
    end

    return grid
end
