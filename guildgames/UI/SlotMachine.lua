local addonName, addon = ...

-- Slot machine panel of the Games tab (feature 014). Rules: Core/Minigames/Slots.lua (the spin is decided and STORED before
-- the reels move). Everything here is presentation:
--   cabinet with chasing light bulbs (idle: slow chase, spin: fast chase, win: all flash, loss: dim)
--   lever that is pulled on every spin (click the knob to spin, too)
--   3 reels drawn as clipped strips (texture crop per frame, no clipping API needed) with cylinder shading, motion blur
--     while fast, and the per-reel pose of Slots.ReelPose (staggered stops, overshoot and settle, a click per stop)
--   win: payline overlays cycling through the winning lines, glowing and pulsing winning cells, a "x15" pop,
--     a payout count-up, and for big wins a coin shower with a "Big win!" / "Jackpot!" banner
-- Every effect goes through UI/Animate.lua (fallbacks included), tweens by key so a new spin replaces old effects.
---@class SlotMachineModule
local SlotMachine = {}
addon.SlotMachine = SlotMachine

local Text, Format = addon.Text, addon.Locale.Format

local CELL = 56                  -- reel cell size (px)
local PAD = 4                    -- gap between the icon and its cell
local REEL_GAP = 6
local CABINET_WIDTH, CABINET_HEIGHT = 236, 222
local REELS_TOP = 36             -- reel window below the cabinet's top edge
local BULB_COUNT = 18
local SHOWER_COINS = 26
local DEFAULT_STAKE = 1000       -- copper (10s)
local BIG_WIN = 15               -- total multiplier from which a coin shower plays
local LINE_COLORS = { { 1, 0.85, 0.1 }, { 0.3, 1, 0.4 }, { 0.3, 0.7, 1 }, { 1, 0.4, 0.8 }, { 1, 0.55, 0.2 } }
local COIN_TEXTURE = "Interface\\Icons\\INV_Misc_Coin_01"

---@class SlotMachineState
---@field spinning boolean the reels are moving
---@field stops integer[] stops the reels show now (the start of the next spin)
---@field lights "idle"|"spin"|"win"|"lose"
---@field lightsTime number
---@field lastResult SlotResult|nil
SlotMachine.state = { spinning = false, stops = { 1, 13, 25 }, lights = "idle", lightsTime = 0 }

---@type table widgets (nil fields until Build ran)
local widgets = {}
SlotMachine.widgets = widgets

------------------------------------------------------------------ reels

---@param texture table
---@param symbolKey string
local function setSymbol(texture, symbolKey)
    if texture.symbol == symbolKey then return end
    texture.symbol = symbolKey
    local symbol = addon.Slots.BY_KEY[symbolKey]
    addon.UIHelpers.SetTextureOr(texture, symbol.icon, symbol.color)   -- icon missing on this client: a coloured tile
end

-- x offset of a reel inside the reel area
---@param reel integer
---@return number
local function reelX(reel) return (reel - 1) * (CELL + REEL_GAP) end

-- Draws reel `reel` with the fractional strip index `index` in the top row. Icons are cropped to the window by size and
-- texture coordinates, so the reel needs no clipping support.
---@param reel integer
---@param index number
---@param speed number symbols per second
local function renderReel(reel, index, speed)
    local reelFrame = widgets.reels[reel]
    local base = math.floor(index + 1e-9)
    local fraction = index - base
    if fraction < 1e-6 then fraction = 0 end
    local windowHeight = CELL * addon.Slots.ROWS
    local blur = math.min(1, speed / 45)
    for slot = 1, addon.Slots.ROWS + 1 do
        local texture = reelFrame.symbols[slot]
        local cellTop = (slot - 1 - fraction) * CELL
        local iconTop, iconBottom = cellTop + PAD, cellTop + CELL - PAD
        local visibleTop, visibleBottom = math.max(iconTop, 0), math.min(iconBottom, windowHeight)
        if visibleBottom - visibleTop < 0.5 then
            texture:Hide()
        else
            setSymbol(texture, addon.Slots.SymbolAt(base + slot - 1))
            local iconHeight = CELL - 2 * PAD
            local fromV, toV = (visibleTop - iconTop) / iconHeight, (visibleBottom - iconTop) / iconHeight
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", reelFrame, "TOPLEFT", PAD, -visibleTop)
            texture:SetSize(CELL - 2 * PAD, visibleBottom - visibleTop)
            texture:SetTexCoord(0.08, 0.92, 0.08 + 0.84 * fromV, 0.08 + 0.84 * toV)
            texture:SetAlpha(1 - 0.45 * blur)
            texture:Show()
        end
    end
    reelFrame.blur:SetAlpha(0.55 * blur)
end

---@param stops integer[]
local function renderStops(stops)
    for reel = 1, addon.Slots.REELS do renderReel(reel, stops[reel], 0) end
end

---@param parent table
---@param top boolean shade at the top (else the bottom)
---@return table texture a dark band fading towards the middle: the curve of the reel drum
local function drumShade(parent, top)
    local shade = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    shade:SetHeight(CELL * 0.55)
    shade:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT"); shade:SetPoint(top and "TOPRIGHT" or "BOTTOMRIGHT")
    shade:SetColorTexture(1, 1, 1, 1)
    local dark, clear = { r = 0, g = 0, b = 0, a = 0.75 }, { r = 0, g = 0, b = 0, a = 0 }
    local ok = pcall(function()   -- current clients: colour objects; older ones: numbers
        if CreateColor then
            shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, top and 0 or 0.75), CreateColor(0, 0, 0, top and 0.75 or 0))
        else
            error("no CreateColor")
        end
    end)
    if not ok then
        ok = pcall(shade.SetGradientAlpha, shade, "VERTICAL", 0, 0, 0, top and 0 or dark.a, 0, 0, 0, top and dark.a or clear.a)
    end
    if not ok then shade:SetColorTexture(0, 0, 0, 0.25) end
    return shade
end

---@param reelsArea table
---@param reel integer
---@return table reel frame with .symbols, .blur
local function buildReel(reelsArea, reel)
    local reelFrame = CreateFrame("Frame", nil, reelsArea)
    reelFrame:SetSize(CELL, CELL * addon.Slots.ROWS)
    reelFrame:SetPoint("TOPLEFT", reelX(reel), 0)
    local background = reelFrame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetColorTexture(0.93, 0.89, 0.78, 1)
    reelFrame.symbols = {}
    for slot = 1, addon.Slots.ROWS + 1 do reelFrame.symbols[slot] = reelFrame:CreateTexture(nil, "ARTWORK") end
    reelFrame.blur = reelFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    reelFrame.blur:SetAllPoints(); reelFrame.blur:SetColorTexture(0.95, 0.92, 0.85, 1); reelFrame.blur:SetAlpha(0)
    drumShade(reelFrame, true); drumShade(reelFrame, false)
    -- a white flash when the reel clicks into place
    reelFrame.stopFlash = reelFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    reelFrame.stopFlash:SetAllPoints(); reelFrame.stopFlash:SetColorTexture(1, 1, 0.9, 0.55)
    pcall(reelFrame.stopFlash.SetBlendMode, reelFrame.stopFlash, "ADD")
    reelFrame.stopFlash:SetAlpha(0); reelFrame.stopFlash:Hide()
    return reelFrame
end

------------------------------------------------------------------ paylines and winning cells

-- centre of a cell in reel-area coordinates (x right, y down as a positive number)
---@param reel integer
---@param row integer
---@return number x
---@return number y
local function cellCenter(reel, row) return reelX(reel) + CELL / 2, (row - 0.5) * CELL end

---@param overlay table
---@param lineIndex integer
---@return table line region (a Line, or a rotated texture on clients without CreateLine)
local function buildPayline(overlay, lineIndex)
    local rows = addon.Slots.LINES[lineIndex]
    local startX, startY = cellCenter(1, rows[1])
    local endX, endY = cellCenter(addon.Slots.REELS, rows[addon.Slots.REELS])
    local deltaX, deltaY = endX - startX, endY - startY
    local length = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    local extendX, extendY = deltaX / length * 22, deltaY / length * 22   -- run a little past the outer cells
    local color = LINE_COLORS[lineIndex]
    local ok, line = pcall(function()
        local created = overlay:CreateLine(nil, "OVERLAY")
        created:SetThickness(5)
        created:SetColorTexture(color[1], color[2], color[3], 1)
        created:SetStartPoint("TOPLEFT", overlay, startX - extendX, -(startY - extendY))
        created:SetEndPoint("TOPLEFT", overlay, endX + extendX, -(endY + extendY))
        return created
    end)
    if not ok or not line then
        line = overlay:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(color[1], color[2], color[3], 1)
        line:SetSize(length + 44, 5)
        line:SetPoint("CENTER", overlay, "TOPLEFT", (startX + endX) / 2, -(startY + endY) / 2)
        if deltaY ~= 0 then pcall(line.SetRotation, line, -math.atan2(deltaY, deltaX)) end
    end
    pcall(line.SetBlendMode, line, "ADD")
    line:Hide()
    return line
end

-- Ends every effect of the previous spin (finishing tweens first: their end handlers show the final state, which is
-- then cleared here).
local function hideWinEffects()
    addon.Animate.FinishTween("slotLines")
    addon.Animate.FinishTween("slotShower")
    addon.Animate.FinishTween("slotCount")
    for _, effect in ipairs({ "float:slots", "flash:slots", "ring:slots", "burst:slots" }) do addon.Animate.FinishTween(effect) end
    for _, line in ipairs(widgets.paylines or {}) do line:Hide() end
    for _, glow in ipairs(widgets.cellGlows or {}) do glow:SetAlpha(0); glow:Hide() end
    for _, coin in ipairs(widgets.showerCoins or {}) do coin:Hide() end
    widgets.banner:SetText(""); widgets.multiplierText:SetText("")
end

------------------------------------------------------------------ lights, lever, coin shower

-- Bulb brightness per mode; runs from the cabinet's OnUpdate, so only while the panel is visible.
---@param elapsedSeconds number
local function updateLights(elapsedSeconds)
    local state = SlotMachine.state
    state.lightsTime = state.lightsTime + elapsedSeconds * addon.Animate.speed
    local time = state.lightsTime
    if state.lights == "lose" and time > 1.2 then state.lights, state.lightsTime = "idle", 0 end
    for index, bulb in ipairs(widgets.bulbs) do
        local brightness
        if state.lights == "spin" then
            brightness = ((index + math.floor(time * 18)) % 4 == 0) and 1 or 0.3
        elseif state.lights == "win" then
            brightness = ((math.floor(time * 8) + index) % 2 == 0) and 1 or 0.45
        elseif state.lights == "lose" then
            brightness = 0.2
        else
            brightness = ((index + math.floor(time * 3)) % 3 == 0) and 1 or 0.4
        end
        local color = bulb.baseColor
        bulb:SetVertexColor(color[1] * brightness, color[2] * brightness, color[3] * brightness)
    end
end

---@param mode "idle"|"spin"|"win"|"lose"
local function setLights(mode)
    SlotMachine.state.lights, SlotMachine.state.lightsTime = mode, 0
end

local function pullLever()
    local travel = 46
    addon.Animate.Tween("slotLever", 0.5, function(elapsed)
        local pull = math.sin(math.pi * math.min(1, elapsed / 0.5)) * travel
        widgets.leverStick:SetHeight(math.max(4, 64 - pull))
    end, function() widgets.leverStick:SetHeight(64) end)
end

-- Coins burst up from the reels and fall with gravity; `count` of the pooled coins take part.
---@param count integer
local function coinShower(count)
    local panel = widgets.panel
    local coins = widgets.showerCoins
    local random = addon.Api.Random
    local launches = {}
    for index = 1, math.min(count, #coins) do
        launches[index] = { x = 30 + random() * (CABINET_WIDTH - 60), delay = random() * 0.6, up = 120 + random() * 180,
            drift = (random() - 0.5) * 120, spin = (random() - 0.5) * 14, size = 14 + random() * 10 }
    end
    local gravity, startY = 520, REELS_TOP + CELL * 1.5
    addon.Animate.Tween("slotShower", 2.6, function(elapsed)
        for index, launch in ipairs(launches) do
            local coin, time = coins[index], elapsed - launch.delay
            if time <= 0 then
                coin:Hide()
            else
                local y = startY - launch.up * time + gravity * time * time / 2   -- y grows downwards
                coin:ClearAllPoints()
                coin:SetPoint("CENTER", panel, "TOPLEFT", launch.x + launch.drift * time, -y)
                coin:SetSize(launch.size, launch.size)
                pcall(coin.SetRotation, coin, launch.spin * time)
                coin:SetAlpha(addon.Utility.Clamp((2.6 - elapsed) / 0.5, 0, 1))
                coin:Show()
            end
        end
    end, function() for _, coin in ipairs(coins) do coin:Hide() end end)
end

------------------------------------------------------------------ result

---@param result SlotResult
local function showWin(result)
    local Animate = addon.Animate
    local money = addon.Model.MoneyText
    setLights("win")
    -- winning cells: glow and pulse every cell of every winning line
    local glowing = {}
    for _, lineWin in ipairs(result.lines) do
        for reel, row in ipairs(addon.Slots.LINES[lineWin.line]) do
            local cellIndex = (row - 1) * addon.Slots.REELS + reel
            if not glowing[cellIndex] then
                glowing[cellIndex] = true
                Animate.Glow(widgets.cellGlows[cellIndex], 4)
                Animate.Pulse(widgets.reels[reel].symbols[row], 1.18, 0.35)
            end
        end
    end
    -- paylines: each winning line in turn, 0.6 s each, at least two rounds
    local lineOrder = result.lines
    local lineDuration = math.max(2.4, 1.2 * #lineOrder)
    Animate.Tween("slotLines", lineDuration, function(elapsed)
        local shown = lineOrder[math.floor(elapsed / 0.6) % #lineOrder + 1].line
        local pulse = 0.55 + 0.45 * math.abs(math.sin(elapsed * math.pi / 0.6))
        for lineIndex, line in ipairs(widgets.paylines) do
            line:SetShown(lineIndex == shown)
            if lineIndex == shown then line:SetAlpha(pulse) end
        end
    end, function()
        for _, lineWin in ipairs(lineOrder) do widgets.paylines[lineWin.line]:SetAlpha(0.8); widgets.paylines[lineWin.line]:Show() end
    end)
    -- multiplier pop and payout count-up
    widgets.multiplierText:SetText(Format(Text["x{n}"], { n = result.multiplier }))
    Animate.FadeIn(widgets.multiplierText, 0.15)
    Animate.Pulse(widgets.multiplierText, 1.6, 0.4)
    local countDuration = 0.8 + math.min(1.6, result.multiplier / 40)
    widgets.resultText:SetTextColor(0.2, 1, 0.6)
    Animate.Tween("slotCount", countDuration, function(elapsed)
        local eased = 1 - (1 - math.min(1, elapsed / countDuration)) ^ 3
        widgets.resultText:SetText(Format(Text["You won {gold}"], { gold = money(math.floor(result.net * eased)) }))
    end, function() widgets.resultText:SetText(Format(Text["You won {gold}"], { gold = money(result.net) })) end)
    -- every win: sparkles from the reels and the payout floats up over the cabinet
    Animate.Burst("slots", widgets.effects, widgets.reelsArea, 0, 0,
        { count = math.min(36, 14 + 2 * #result.lines + math.floor(result.multiplier / 3)), speed = 200, gravity = 240, size = 15 })
    Animate.FloatText("slots", widgets.floatText, widgets.cabinet, 0, CABINET_HEIGHT / 2 - 14, "+" .. money(result.net), { 0.35, 1, 0.55 })
    -- big wins: banner, shockwave, a gold flash over the cabinet and the coin shower
    local jackpot = false
    for _, lineWin in ipairs(result.lines) do if lineWin.symbol == addon.Slots.SYMBOLS[1].key then jackpot = true end end
    if jackpot or result.multiplier >= BIG_WIN then
        widgets.banner:SetText(jackpot and Text["Jackpot!"] or Text["Big win!"])
        Animate.FadeIn(widgets.banner, 0.2)
        Animate.Pulse(widgets.banner, 1.4, 0.5)
        Animate.Ring("slots", widgets.effects, widgets.reelsArea, 60, jackpot and 420 or 300, nil, jackpot and 0.8 or 0.6)
        Animate.Flash("slots", widgets.cabinetFlash, jackpot and 0.6 or 0.4, jackpot and 0.9 or 0.6)
        coinShower(jackpot and SHOWER_COINS or math.floor(SHOWER_COINS * 0.6))
        addon.Api.PlaySoundNamed({ "UI_EPICLOOT_TOAST", "LOOT_WINDOW_COIN_SOUND" })
    end
    addon.Api.PlaySoundNamed({ "LOOT_WINDOW_COIN_SOUND" })
end

---@param result SlotResult
local function reveal(result)
    local state = SlotMachine.state
    state.stops, state.lastResult = result.stops, result
    renderStops(result.stops)
    if result.multiplier > 0 then
        addon.Log.Protected("games.effects", "the win effects failed", showWin, result)   -- never blocks the unlock below
    else
        setLights("lose")
        widgets.resultText:SetText(Format(Text["You lost {gold}"], { gold = addon.Model.MoneyText(result.stake) }))
        widgets.resultText:SetTextColor(1, 0.33, 0.33)
        addon.Animate.FadeIn(widgets.resultText, 0.3)
        addon.Animate.Shake(widgets.cabinet, 3, 4)
        addon.Animate.FloatText("slots", widgets.floatText, widgets.cabinet, 0, CABINET_HEIGHT / 2 - 14,
            "-" .. addon.Model.MoneyText(result.stake), { 1, 0.35, 0.3 }, -24, 1.3)
    end
    state.spinning = false
    widgets.spinButton:Enable()
    widgets.stake.SetEnabled(true)
    addon.GamesTab.SetBusy(false)   -- the reels have stopped: the leaderboard may show the result now
end

-- The Spin button (and the lever): decide and store the spin, announce it, then run the reels.
---@return SlotResult|nil
function SlotMachine.Spin()
    local state = SlotMachine.state
    if state.spinning or not widgets.spinButton then return nil end
    local stake = widgets.stake.Read()
    local result, refusal = addon.Slots.Spin(addon.Utility.Me(), stake, addon.Utility.Now(), addon.Api.Random)
    if not result then
        widgets.resultText:SetText(addon.GamesTab.RefusalText(refusal)); widgets.resultText:SetTextColor(1, 0.33, 0.33)
        widgets.resultText:SetAlpha(1); widgets.resultText:Show()
        return nil
    end
    addon.UIHelpers.Settings().lastSlotStakeCopper = stake
    addon.Events.Fire("GAMES_CHANGED")                    -- announce (coalesced HELLO)
    state.spinning = true
    addon.GamesTab.SetBusy(true)
    widgets.spinButton:Disable()
    widgets.stake.SetEnabled(false)
    hideWinEffects()
    widgets.resultText:SetText("")
    setLights("spin")
    pullLever()
    addon.Api.PlaySoundNamed({ "IG_MAINMENU_OPTION_CHECKBOX_ON" })
    addon.Log.Debug("games.spin", "the slot machine was spun", { stake = stake, multiplier = result.multiplier })
    local fromStops, stopped = state.stops, {}
    addon.Animate.Tween("slotReels", addon.Slots.SpinDuration(), function(elapsed)
        for reel = 1, addon.Slots.REELS do
            local pose = addon.Slots.ReelPose(elapsed, reel, fromStops[reel], result.stops[reel])
            renderReel(reel, pose.index, pose.speed)
            if pose.done and not stopped[reel] then
                stopped[reel] = true
                addon.Animate.Glow(widgets.reels[reel].stopFlash, 1)
                addon.Api.PlaySoundNamed({ "U_CHAT_SCROLL_BUTTON", "IG_MAINMENU_OPTION_CHECKBOX_OFF" })
            end
        end
    end, function() reveal(result) end)
    return result
end

------------------------------------------------------------------ build

local function showPaytable(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(Text["Paytable: three in a line"])
    for _, symbol in ipairs(addon.Slots.SYMBOLS) do
        local icon = "|T" .. symbol.icon .. ":16|t"
        GameTooltip:AddDoubleLine(icon .. icon .. icon, Format(Text["x{n}"], { n = symbol.pays }), 1, 1, 1, 1, 0.82, 0)
    end
    GameTooltip:AddLine(Text["5 lines: 3 rows and 2 diagonals"], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

---@param cabinet table
local function buildBulbs(cabinet)
    widgets.bulbs = {}
    local perimeter = 2 * (CABINET_WIDTH + CABINET_HEIGHT)
    for index = 1, BULB_COUNT do
        local distance = (index - 1) / BULB_COUNT * perimeter
        local x, y
        if distance < CABINET_WIDTH then x, y = distance, 0
        elseif distance < CABINET_WIDTH + CABINET_HEIGHT then x, y = CABINET_WIDTH, distance - CABINET_WIDTH
        elseif distance < 2 * CABINET_WIDTH + CABINET_HEIGHT then x, y = CABINET_WIDTH - (distance - CABINET_WIDTH - CABINET_HEIGHT), CABINET_HEIGHT
        else x, y = 0, CABINET_HEIGHT - (distance - 2 * CABINET_WIDTH - CABINET_HEIGHT) end
        local bulb = cabinet:CreateTexture(nil, "OVERLAY", nil, 2)
        bulb:SetSize(9, 9); bulb:SetPoint("CENTER", cabinet, "TOPLEFT", x, -y)
        bulb:SetColorTexture(1, 1, 1, 1)
        addon.GamesTab.MaskCircle(cabinet, bulb)
        bulb.baseColor = (index % 2 == 0) and { 1, 0.85, 0.3 } or { 1, 0.35, 0.25 }
        widgets.bulbs[index] = bulb
    end
end

---@param panel table the Games tab's slot panel (300 x 400)
function SlotMachine.Build(panel)
    local Widgets = addon.UI.Widgets
    widgets.panel = panel

    -- cabinet: wood-dark body, gold frame, title, bulbs; hover shows the paytable
    local cabinet = CreateFrame("Frame", nil, panel)
    cabinet:SetSize(CABINET_WIDTH, CABINET_HEIGHT); cabinet:SetPoint("TOPLEFT", 24, -4)
    widgets.cabinet = cabinet
    local body = cabinet:CreateTexture(nil, "BACKGROUND", nil, 0)
    body:SetAllPoints(); body:SetColorTexture(0.28, 0.07, 0.07, 1)
    local frame = cabinet:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame:SetPoint("TOPLEFT", -4, 4); frame:SetPoint("BOTTOMRIGHT", 4, -4); frame:SetColorTexture(0.85, 0.66, 0.2, 1)
    local title = Widgets.CreateFontString(cabinet, "GameFontNormalLarge", "CENTER")
    title:SetPoint("TOP", 0, -10); title:SetText(Text["Slots"])
    buildBulbs(cabinet)
    cabinet:EnableMouse(true)
    cabinet:SetScript("OnEnter", showPaytable)
    cabinet:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cabinet:SetScript("OnUpdate", function(_, elapsedSeconds) updateLights(elapsedSeconds) end)

    -- reel window
    local reelsWidth = addon.Slots.REELS * CELL + (addon.Slots.REELS - 1) * REEL_GAP
    local reelsArea = CreateFrame("Frame", nil, cabinet)
    reelsArea:SetSize(reelsWidth, CELL * addon.Slots.ROWS)
    reelsArea:SetPoint("TOPLEFT", (CABINET_WIDTH - reelsWidth) / 2, -REELS_TOP)
    local well = cabinet:CreateTexture(nil, "BACKGROUND", nil, 1)
    well:SetPoint("TOPLEFT", reelsArea, "TOPLEFT", -5, 5); well:SetPoint("BOTTOMRIGHT", reelsArea, "BOTTOMRIGHT", 5, -5)
    well:SetColorTexture(0.08, 0.02, 0.02, 1)
    widgets.reels = {}
    for reel = 1, addon.Slots.REELS do widgets.reels[reel] = buildReel(reelsArea, reel) end

    -- overlay above the reels: cell glows, paylines, multiplier pop, banner
    local overlay = CreateFrame("Frame", nil, reelsArea)
    overlay:SetAllPoints(); overlay:SetFrameLevel(addon.UIHelpers.FrameLevel(reelsArea) + 5)
    widgets.cellGlows = {}
    for row = 1, addon.Slots.ROWS do
        for reel = 1, addon.Slots.REELS do
            local glow = overlay:CreateTexture(nil, "ARTWORK")
            glow:SetSize(CELL * 1.45, CELL * 1.45); glow:SetTexture(addon.GamesTab.GLOW_TEXTURE); glow:SetBlendMode("ADD")
            glow:SetVertexColor(1, 0.85, 0.25)
            local x, y = cellCenter(reel, row)
            glow:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
            glow:SetAlpha(0); glow:Hide()
            widgets.cellGlows[(row - 1) * addon.Slots.REELS + reel] = glow
        end
    end
    widgets.paylines = {}
    for lineIndex = 1, #addon.Slots.LINES do widgets.paylines[lineIndex] = buildPayline(overlay, lineIndex) end
    widgets.multiplierText = Widgets.CreateFontString(overlay, "GameFontNormalHuge", "CENTER")
    widgets.multiplierText:SetPoint("CENTER", overlay, "CENTER", 0, 0); widgets.multiplierText:SetTextColor(1, 0.9, 0.3)
    widgets.banner = Widgets.CreateFontString(cabinet, "GameFontNormalLarge", "CENTER")
    widgets.banner:SetPoint("BOTTOM", cabinet, "BOTTOM", 0, 6); widgets.banner:SetTextColor(1, 0.9, 0.3)

    -- lever on the right of the cabinet: a stick that shortens while pulled, a red knob on top (click = spin)
    local leverBase = panel:CreateTexture(nil, "ARTWORK")
    leverBase:SetSize(16, 26); leverBase:SetPoint("LEFT", cabinet, "RIGHT", 4, -30); leverBase:SetColorTexture(0.5, 0.38, 0.12, 1)
    local stick = panel:CreateTexture(nil, "ARTWORK")
    stick:SetSize(5, 64); stick:SetPoint("BOTTOM", leverBase, "TOP", 0, 0); stick:SetColorTexture(0.75, 0.75, 0.78, 1)
    widgets.leverStick = stick
    local knob = CreateFrame("Button", nil, panel)
    knob:SetSize(20, 20); knob:SetPoint("CENTER", stick, "TOP", 0, 0)
    local knobTexture = knob:CreateTexture(nil, "OVERLAY")
    knobTexture:SetAllPoints(); knobTexture:SetColorTexture(0.85, 0.12, 0.1, 1)
    addon.GamesTab.MaskCircle(knob, knobTexture)
    knob:SetScript("OnClick", function() SlotMachine.Spin() end)
    widgets.leverKnob = knob

    -- coins for the shower (pooled, hidden)
    local showerLayer = CreateFrame("Frame", nil, panel)
    showerLayer:SetAllPoints(); showerLayer:SetFrameLevel(addon.UIHelpers.FrameLevel(overlay) + 5)
    widgets.showerCoins = {}
    for index = 1, SHOWER_COINS do
        local coin = showerLayer:CreateTexture(nil, "OVERLAY")
        coin:SetTexture(COIN_TEXTURE); coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        addon.GamesTab.MaskCircle(showerLayer, coin)
        coin:Hide()
        widgets.showerCoins[index] = coin
    end
    -- effects (sparkles, shockwave, floating payout, the big-win flash) share the shower's layer
    widgets.effects = showerLayer
    widgets.reelsArea = reelsArea
    widgets.cabinetFlash = showerLayer:CreateTexture(nil, "ARTWORK")
    widgets.cabinetFlash:SetPoint("TOPLEFT", cabinet, "TOPLEFT", -4, 4); widgets.cabinetFlash:SetPoint("BOTTOMRIGHT", cabinet, "BOTTOMRIGHT", 4, -4)
    widgets.cabinetFlash:SetColorTexture(1, 0.85, 0.35, 1); pcall(widgets.cabinetFlash.SetBlendMode, widgets.cabinetFlash, "ADD")
    widgets.cabinetFlash:SetAlpha(0); widgets.cabinetFlash:Hide()
    widgets.floatText = Widgets.CreateFontString(showerLayer, "GameFontNormalHuge", "CENTER")
    widgets.floatText:Hide()

    -- controls below the cabinet
    widgets.resultText = Widgets.CreateFontString(panel, "GameFontNormalLarge", "CENTER")
    widgets.resultText:SetPoint("TOP", panel, "TOP", 0, -236); widgets.resultText:SetWidth(290)
    widgets.stake = addon.GamesTab.CreateStakeRow(panel, 36, -262, function() SlotMachine.Spin() end)
    widgets.stake.Write(addon.UIHelpers.Settings().lastSlotStakeCopper or DEFAULT_STAKE)
    widgets.spinButton = Widgets.CreateButton(panel, Text["Spin"], 180, 28, function() SlotMachine.Spin() end)
    widgets.spinButton:SetPoint("TOP", panel, "TOP", 0, -292)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.spinButton) end

    renderStops(SlotMachine.state.stops)
end
