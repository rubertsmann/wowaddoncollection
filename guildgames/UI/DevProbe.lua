local addonName, addon = ...

-- DEV BUILD ONLY: the animation probe and the game dev commands (/ggd anim, /ggd anim speed <x>, /ggd game sim <n>).
-- Plain English strings on purpose: dev-only, not localized. The live build never runs it (no command).
---@class DevProbeModule
local DevProbe = {}
addon.DevProbe = DevProbe

-- /ggd anim: answers the probe questions P1-P8 of features/014-guild-game-base/evidence/animations-research.md on this
-- client. Prints one chat line per question ("anim P3: ..."); P5 and P8 also need a screenshot of the squares it shows
-- in the middle of the screen for ~10 s. Plain English on purpose (dev only).
local animationProbeRunning = false

---@param questionID string
---@param text string
local function report(questionID, text) addon.Print(("anim %s: %s"):format(questionID, text)) end

---@param label string
---@param x number offset from the screen center
---@param y number
---@param red number
---@param green number
---@param blue number
---@return table square a 40 x 40 frame with a coloured texture and a label
local function testSquare(label, x, y, red, green, blue)
    local square = CreateFrame("Frame", nil, UIParent)
    square:SetSize(40, 40); square:SetPoint("CENTER", UIParent, "CENTER", x, y); square:SetFrameStrata("DIALOG")
    square.texture = square:CreateTexture(nil, "ARTWORK"); square.texture:SetAllPoints(); square.texture:SetColorTexture(red, green, blue, 0.9)
    square.label = square:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); square.label:SetPoint("TOP", square, "BOTTOM", 0, -2)
    square.label:SetText(label)
    square:EnableMouse(true)
    return square
end

---@param value number|nil
---@return string
local function rounded(value) return value and ("%.1f"):format(value) or "nil" end

---@param animation table a Scale animation
---@param fromX number
---@param fromY number
---@param toX number
---@param toY number
local function scaleFromTo(animation, fromX, fromY, toX, toY)
    if animation.SetScaleFrom then animation:SetScaleFrom(fromX, fromY); animation:SetScaleTo(toX, toY)
    else animation:SetScale(toX / fromX, toY / fromY) end
end

function DevProbe.AnimationProbe()
    if animationProbeRunning then addon.Print("anim probe: already running") return end
    animationProbeRunning = true
    local squares = {}
    local function keep(square) squares[#squares + 1] = square; return square end

    -- P1: animation types this client accepts
    local accepted, refused = {}, {}
    for _, animationType in ipairs({ "Animation", "Alpha", "Scale", "Translation", "Rotation", "Path", "ControlPoints", "FlipBook",
        "VertexColor", "TextureCoordTranslation", "LineScale", "LineTranslation" }) do
        local list = addon.Animate.Supported(animationType) and accepted or refused
        list[#list + 1] = animationType
    end
    report("P1", "accepted: " .. table.concat(accepted, ", ") .. " | refused: " .. (#refused > 0 and table.concat(refused, ", ") or "none"))

    -- P2: smoothing and looping values the setters accept
    local probeGroup = CreateFrame("Frame"):CreateAnimationGroup()
    local probeAnimation = probeGroup:CreateAnimation("Alpha")
    local smoothings, loopings = {}, {}
    for _, smoothing in ipairs({ "NONE", "IN", "OUT", "IN_OUT", "OUT_IN", "BOUNCE" }) do
        local ok = pcall(probeAnimation.SetSmoothing, probeAnimation, smoothing)
        local readBack = ok and probeAnimation.GetSmoothing and probeAnimation:GetSmoothing() or "?"
        smoothings[#smoothings + 1] = smoothing .. (ok and ("=" .. tostring(readBack)) or "=error")
    end
    for _, looping in ipairs({ "NONE", "REPEAT", "BOUNCE" }) do
        loopings[#loopings + 1] = looping .. (pcall(probeGroup.SetLooping, probeGroup, looping) and "=ok" or "=error")
    end
    report("P2", "smoothing " .. table.concat(smoothings, " ") .. " | looping " .. table.concat(loopings, " ")
        .. " | SetToFinalAlpha=" .. tostring(probeGroup.SetToFinalAlpha ~= nil)
        .. " SetAnimationSpeedMultiplier=" .. tostring(probeGroup.SetAnimationSpeedMultiplier ~= nil))

    -- P3: Translation end state (does it jump back?) and whether the hit rect moves (hover the red square while it moves)
    local moving = keep(testSquare("P3 hover me", -200, 120, 0.9, 0.2, 0.2))
    local entered = {}
    moving:SetScript("OnEnter", function() entered[#entered + 1] = ("%.2fs"):format(GetTime() - (moving.startedAt or GetTime())) end)
    local moveGroup = moving:CreateAnimationGroup()
    local move = moveGroup:CreateAnimation("Translation"); move:SetOffset(150, 0); move:SetDuration(2)
    local centerBefore = moving:GetCenter()
    local centerDuring
    moveGroup:SetScript("OnFinished", function()
        local centerAfter = moving:GetCenter()
        report("P3", ("center x before %s, during %s, after %s (same = GetCenter ignores Translation; check visually whether the square jumped back); OnEnter at %s")
            :format(rounded(centerBefore), rounded(centerDuring), rounded(centerAfter), #entered > 0 and table.concat(entered, ",") or "never"))
    end)
    C_Timer.After(1, function() centerDuring = moving:GetCenter() end)
    moving.startedAt = GetTime()
    moveGroup:Play()

    -- P4: alpha end state with and without SetToFinalAlpha, and with a parallel SetAlpha on the region
    local plain = keep(testSquare("P4 plain", -100, 120, 0.2, 0.9, 0.2))
    local final = keep(testSquare("P4 final", 0, 120, 0.2, 0.9, 0.2))
    local mixed = keep(testSquare("P4 SetAlpha", 100, 120, 0.2, 0.9, 0.2))
    local alphaResults, alphaPending = {}, 3
    for _, entry in ipairs({ { plain, "plain", false }, { final, "final", true }, { mixed, "with SetAlpha(0.5)", false } }) do
        local square, name, toFinal = entry[1], entry[2], entry[3]
        local group = square:CreateAnimationGroup()
        if toFinal and group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
        local fade = group:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0.2); fade:SetDuration(0.6)
        group:SetScript("OnFinished", function()
            alphaResults[#alphaResults + 1] = ("%s=%.2f"):format(name, square:GetAlpha())
            alphaPending = alphaPending - 1
            if alphaPending == 0 then report("P4", "GetAlpha after OnFinished (animated 1 -> 0.2): " .. table.concat(alphaResults, ", ")) end
        end)
        group:Play()
        if square == mixed then C_Timer.After(0.3, function() mixed:SetAlpha(0.5) end) end
    end

    -- P5: scale origin and text sharpness (screenshot while they pulse)
    local scaleCentered = keep(testSquare("P5 default origin", -100, -60, 0.2, 0.4, 0.9))
    local scaleCorner = keep(testSquare("P5 BOTTOMLEFT origin", 60, -60, 0.2, 0.4, 0.9))
    local hasScaleFrom, hasOrigin = false, false
    for _, square in ipairs({ scaleCentered, scaleCorner }) do
        local text = square:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); text:SetPoint("CENTER"); text:SetText("Ag 123")
        local group = square:CreateAnimationGroup(); group:SetLooping("BOUNCE")
        local grow = group:CreateAnimation("Scale"); grow:SetDuration(1.2)
        scaleFromTo(grow, 1, 1, 1.8, 1.8)
        if square == scaleCorner and grow.SetOrigin then grow:SetOrigin("BOTTOMLEFT", 0, 0) end
        hasScaleFrom, hasOrigin = grow.SetScaleFrom ~= nil, grow.SetOrigin ~= nil
        group:Play()
    end
    report("P5", ("SetScaleFrom=%s SetOrigin=%s; screenshot the two blue squares (origin and text sharpness)")
        :format(tostring(hasScaleFrom), tostring(hasOrigin)))

    -- P6: Play() again while playing, and Stop() + Play()
    local restarted = keep(testSquare("P6 restart", 200, -60, 0.9, 0.9, 0.2))
    local restartGroup = restarted:CreateAnimationGroup()
    local restartFade = restartGroup:CreateAnimation("Alpha"); restartFade:SetFromAlpha(1); restartFade:SetToAlpha(0); restartFade:SetDuration(1)
    local finishedCount = 0
    restartGroup:SetScript("OnFinished", function() finishedCount = finishedCount + 1 end)
    restartGroup:Play()
    C_Timer.After(0.5, function()
        local function progress() return restartGroup.GetProgress and restartGroup:GetProgress() or -1 end
        local progressBefore = progress()
        restartGroup:Play()
        local progressAfterPlay = progress()
        restartGroup:Stop(); restartGroup:Play()
        local progressAfterRestart = progress()
        C_Timer.After(1.5, function()
            report("P6", ("progress at 0.5s %.2f, after Play() %.2f, after Stop()+Play() %.2f, OnFinished fired %d time(s), IsPlaying %s")
                :format(progressBefore, progressAfterPlay, progressAfterRestart, finishedCount, tostring(restartGroup:IsPlaying())))
        end)
    end)

    -- P8: rotation on a Frame vs on a Texture
    local rotationResults = {}
    local rotatingFrame = keep(testSquare("P8 frame", -100, -160, 0.8, 0.4, 0.1))
    local rotatingTextureHolder = keep(testSquare("P8 texture", 60, -160, 0.8, 0.4, 0.1))
    for _, entry in ipairs({ { rotatingFrame, "frame" }, { rotatingTextureHolder.texture, "texture" } }) do
        local ok, errorMessage = pcall(function()
            local group = entry[1]:CreateAnimationGroup(); group:SetLooping("REPEAT")
            local spin = group:CreateAnimation("Rotation"); spin:SetDegrees(-360); spin:SetDuration(3)
            group:Play()
        end)
        rotationResults[#rotationResults + 1] = entry[2] .. "=" .. (ok and "ok" or tostring(errorMessage))
    end
    report("P8", table.concat(rotationResults, ", ") .. "; screenshot the two orange squares")

    -- coin and glow textures of the Games tab, and the coin sound
    local textureCheck = {}
    local checkTexture = UIParent:CreateTexture(nil, "BACKGROUND")
    local paths = { "Interface\\CharacterFrame\\TempPortraitAlphaMask", "Interface\\Icons\\INV_Crown_01",
        "Interface\\Icons\\INV_Misc_Head_Human_01", "Interface\\Buttons\\UI-ActionButton-Border",
        "Interface\\MoneyFrame\\UI-GoldIcon", unpack(addon.Slots.ICONS or {}) }
    for _, path in ipairs(addon.Survivor.ICONS) do paths[#paths + 1] = path end
    for _, path in pairs(addon.GamesTab.GAME_ICONS) do paths[#paths + 1] = path end
    paths[#paths + 1] = "Interface\\Cursor\\UI-Cursor-Move"
    paths[#paths + 1] = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
    for _, path in ipairs(paths) do
        local result = checkTexture:SetTexture(path)
        textureCheck[#textureCheck + 1] = path:match("[^\\]+$") .. "=" .. tostring(result) .. "/" .. tostring(checkTexture:GetTexture())
    end
    checkTexture:Hide()
    report("tex", table.concat(textureCheck, ", ") .. " | coin sound kit " .. tostring(addon.Api.CoinSoundKit()))

    -- P7: cost of 25 built-in flips vs 25 OnUpdate tweens (frame rate while each runs)
    C_Timer.After(3, function()
        local idleRate = GetFramerate()
        local tiles = {}
        for index = 1, 25 do
            local tile = keep(testSquare("", -240 + (index % 5) * 30, 260 - math.floor(index / 5) * 30, 0.5, 0.5, 0.5))
            tile:SetSize(24, 24)
            local group = tile:CreateAnimationGroup(); group:SetLooping("REPEAT")
            local shrink = group:CreateAnimation("Scale"); shrink:SetDuration(0.12); shrink:SetOrder(1); scaleFromTo(shrink, 1, 1, 0.05, 1)
            local grow = group:CreateAnimation("Scale"); grow:SetDuration(0.12); grow:SetOrder(2); scaleFromTo(grow, 0.05, 1, 1, 1)
            group:Play()
            tiles[index] = { tile = tile, group = group }
        end
        C_Timer.After(1.5, function()
            local builtInRate = GetFramerate()
            for _, entry in ipairs(tiles) do entry.group:Stop() end
            local started = debugprofilestop()
            local stepCount = 0
            for index, entry in ipairs(tiles) do
                addon.Animate.Tween("probe" .. index, 1.5, function(elapsed)
                    stepCount = stepCount + 1
                    entry.tile:SetWidth(24 * math.max(0.05, math.abs(math.cos(elapsed * 12))))
                end)
            end
            C_Timer.After(1.6, function()
                report("P7", ("fps idle %.0f, 25 AnimationGroups %.0f, 25 tweens %.0f (%d tween steps in %.0f ms)")
                    :format(idleRate, builtInRate, GetFramerate(), stepCount, debugprofilestop() - started))
            end)
        end)
    end)

    C_Timer.After(10, function()
        for _, square in ipairs(squares) do square:Hide() end
        animationProbeRunning = false
        addon.Print("anim probe: done, squares removed. Send the anim lines above (and the P5/P8 screenshots).")
    end)
end

if addon.IS_DEVELOPMENT_BUILD then
    -- /ggd anim             run the probe P1-P8
    -- /ggd anim speed 0.25  slow motion for every animation and tween (1 = normal)
    addon.SlashCommands.anim = function(arguments)
        local word, value = tostring(arguments or ""):match("^%s*(%S*)%s*(%S*)")
        if word == "speed" then
            addon.Animate.speed = math.max(0.05, math.min(4, tonumber(value) or 1))
            addon.Print(("anim speed %.2f"):format(addon.Animate.speed))
            return
        end
        addon.Log.Protected("devProbe.anim", "the animation probe failed", DevProbe.AnimationProbe)
    end
    -- /ggd game sim <n>     n fake leaderboard players (memory only: never stored, never sent); 0 removes them
    addon.SlashCommands.game = function(arguments)
        local word, value = tostring(arguments or ""):match("^%s*(%S*)%s*(%S*)")
        if word ~= "sim" then addon.Print("usage: game sim <count>") return end
        local count = addon.Games.Simulate(tonumber(value) or 0, addon.Utility.Now(), math.random)
        addon.Print(("game sim: %d simulated players (not stored, not sent)"):format(count))
        addon.Events.Fire("DATA_CHANGED", "games-local")
    end
end
