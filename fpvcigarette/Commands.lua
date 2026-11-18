local addonName, addon = ...

-- Slash commands. One macro is enough:  /cig   (first press lights it, every further press takes a drag)
local Overlay, Logic = addon.Overlay, addon.Logic

function addon.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd9a066Cigarette:|r " .. message)
end

local HELP = {
    "/cig - light it, or take a drag when it is lit",
    "/cig light | drag | out",
    "/cig auto - only in first person (default) | /cig always - at every zoom",
    "/cig move - drag it into place (again to lock) | /cig scale 0.5-2 | /cig reset",
    "/cig time <seconds> - how long one cigarette burns (default " .. Logic.BURN_SECONDS .. ")",
    "/cig calibrate - say 'I am in first person now' (clients without a camera-distance API)",
    "/cig dance - toggle the dancer | /cig dance lock|unlock|elf|male|next|prev|id <n>|player|custom|scale <n>|reset",
    "/cig status | /cig debug (verbose log) | /cig log [n] | /cig clearlog",
}

local function status()
    local state = Overlay.State()
    local distance = Overlay.CameraDistance()
    addon.Print(string.format("%s, %d%% smoked, mode %s, camera %.1f yd (%s)%s",
        state.lit and "lit" or "not lit", math.floor(state.progress * 100 + 0.5), FpvCigaretteDB.mode or "auto",
        distance, GetCameraZoom and "real" or "estimated",
        Logic.IsFirstPerson(distance, FpvCigaretteDB.threshold) and ", first person" or ""))
end

local handlers = {
    [""] = function()
        if not Overlay.Light() then Overlay.Drag() end
    end,
    light = function() if not Overlay.Light() then addon.Print("already lit.") end end,
    drag = function() if not Overlay.Drag() then addon.Print("not lit (or still inhaling).") end end,
    out = function() if not Overlay.PutOut() then addon.Print("not lit.") end end,
    auto = function() FpvCigaretteDB.mode = "auto"; addon.Print("shown in first person only.") end,
    always = function() FpvCigaretteDB.mode = "always"; addon.Print("shown at every zoom level.") end,
    move = function()
        local moving = not Overlay.runtime.moving
        Overlay.SetMoving(moving)
        addon.Print(moving and "drag it with the left mouse button; /cig move again to lock." or "locked.")
    end,
    scale = function(argument)
        local value = tonumber(argument)
        if not value or value < 0.3 or value > 3 then return addon.Print("usage: /cig scale 0.3-3") end
        FpvCigaretteDB.scale = value
        Overlay.Layout()
    end,
    reset = function()
        FpvCigaretteDB.x, FpvCigaretteDB.y, FpvCigaretteDB.scale = nil, nil, nil
        Overlay.Layout()
        addon.Print("position and scale reset.")
    end,
    time = function(argument)
        local seconds = tonumber(argument)
        if not seconds or seconds < 10 then return addon.Print("usage: /cig time <seconds, at least 10>") end
        Overlay.SetBurnSeconds(seconds)
        addon.Print(string.format("a cigarette now burns %d seconds.", seconds))
    end,
    calibrate = function() Overlay.Calibrate(); addon.Print("camera marked as first person.") end,
    status = status,
    debug = function()
        FpvCigaretteDB.debug = not FpvCigaretteDB.debug
        addon.Log.Write("debug", FpvCigaretteDB.debug and "debug on" or "debug off")
        addon.Print(FpvCigaretteDB.debug and "debug log on (also printed to chat)." or "debug log off.")
    end,
    log = function(argument)
        for _, line in ipairs(addon.Log.Tail(tonumber(argument) or 20)) do DEFAULT_CHAT_FRAME:AddMessage(line) end
    end,
    clearlog = function() addon.Log.Clear(); addon.Print("log cleared.") end,
    dance = function(argument)
        local Dancer = addon.Dancer
        if not Dancer.widgets.frame then return addon.Print("the dancer failed to load, see /cig log.") end
        local word, value = (argument or ""):lower():match("^(%S*)%s*(.-)$")
        if word == "" then
            Dancer.Toggle()
        elseif word == "on" or word == "off" then
            Dancer.SetShown(word == "on")
        elseif word == "lock" or word == "unlock" then
            Dancer.SetLocked(word == "lock")
            addon.Print(word == "lock" and "dancer locked (click-through)."
                or "dancer unlocked: drag to move, corner grip to resize, wheel to scale, right-drag to turn.")
        elseif word == "elf" or word == "male" or word == "player" or word == "custom" or word == "file" then
            Dancer.SetLook(word == "male" and "elfmale" or word)
        elseif word == "next" or word == "prev" then
            local index, count, displayId = Dancer.Cycle(word == "next" and 1 or -1)
            addon.Print(string.format("outfit %d/%d (display %d)", index, count, displayId))
        elseif word == "id" and tonumber(value) then
            Dancer.SetDisplayId(tonumber(value))
            addon.Print("display " .. tonumber(value))
        elseif word == "scale" and tonumber(value) then
            Dancer.SetScale(tonumber(value))
        elseif word == "reset" then
            Dancer.Reset()
        else
            addon.Print("/cig dance [on|off|lock|unlock|elf|male|next|prev|id <n>|player|custom|scale 0.3-3|reset]")
        end
    end,
    help = function() for _, line in ipairs(HELP) do addon.Print(line) end end,
}
handlers.puff = handlers.drag

SLASH_FPVCIGARETTE1 = "/cig"
SLASH_FPVCIGARETTE2 = "/cigarette"
SlashCmdList.FPVCIGARETTE = function(message)
    if not Overlay.State() then return end   -- before PLAYER_LOGIN
    local command, argument = strtrim(message or ""):match("^(%S*)%s*(.-)$")
    local handler = handlers[(command or ""):lower()] or handlers.help
    handler(argument)
end
