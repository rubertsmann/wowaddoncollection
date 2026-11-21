local addonName, addon = ...

-- AZEcaught's client side (feature 018): the combat log (found NPCs, deaths), the rope icon on nameplates, the throw
-- (icon, key binding, /gg catch), the active-time ticker, publishing my companion to the guild, the weekly payout and
-- the /gg caught diagnostics. Game logic stays in Core/Minigames/AzeCaught.lua (pure); WoW reads go through Core/Game/Api.lua.
-- Everything here writes to the AZEcaught journal (/gg caught log) so a problem on a player's machine can be followed.
---@class CatcherModule
local Catcher = {}
addon.Catcher = Catcher

local AzeCaught, Api = addon.AzeCaught, addon.Api
local Text, Format = addon.Text, addon.Locale.Format

local ROPE_ICON = "Interface\\Icons\\INV_Misc_Rope_01"
local ROPE_FALLBACK = "Interface\\Icons\\Ability_Hunter_BeastTaming"
Catcher.ROPE_ICON = ROPE_ICON
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
Catcher.CIRCLE_MASK = CIRCLE_MASK
local ICON_SIZE = 26
local ROPE_COLOR = { 0.78, 0.58, 0.3 }
local ROPE_DELAY = 0.35             -- seconds from the wind-up on the player to the lasso on the target
local PLAYER_SCREEN_HEIGHT = 0.42   -- the player's character stands about here (share of the screen height, centred)
local FRONT_RISE = 0.2              -- no nameplate: the lasso lands this share of the screen height above the player
local LANDING_DROP = 18             -- the lasso lands this far below the target's nameplate (on its body)
local LANDING_LINGER = 0.9          -- seconds the landing pin stays on the plate (then it lets go of it)
-- the icon while a throw is armed ("catch mode", user 2026-11-20): a net instead of the rope
local CATCH_ICON = "Interface\\Icons\\Ability_Ensnare"
Catcher.CATCH_ICON = CATCH_ICON
local SHAKE_SECONDS = 1.0           -- the armed icon shakes this long before the window ends (user 2026-11-20)
local SHAKE_MAXIMUM = 5             -- pixels at the very end
local ARROW_TEXTURE = "Interface\\Buttons\\UI-MicroStream-Red"            -- a red arrow pointing down
local ARROW_FALLBACK = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"
local ARROW_SIZE = 30
local SNAP_SOUNDS = { "IG_QUEST_LOG_ABANDON_QUEST", "IG_MAINMENU_OPTION_CHECKBOX_OFF" }
local BEST_SOUNDS = { "MAP_PING", "IG_MAINMENU_OPTION_CHECKBOX_ON" }
local MAXIMUM_PINGED = 200
local HOSTILE_FLAG = 0x40          -- COMBATLOG_OBJECT_REACTION_HOSTILE
local PUBLISH_MINIMUM_GAP = 30     -- seconds between published updates of my companion
local PUBLISH_EVERY = 300          -- and at least this often while a companion is active
local MAXIMUM_NOTED = 500

Catcher.unitByGuid = {}     -- nameplate unit token by GUID
Catcher.icons = {}          -- rope icon button by unit token
Catcher.noted = {}          -- GUIDs whose unit details were read (cleared when it grows past MAXIMUM_NOTED)
Catcher.fought, Catcher.foughtCount = {}, 0   -- GUID -> NPC id of enemies that fought me (their death is a kill)
Catcher.notedCount = 0
Catcher.lastClock = nil
Catcher.lastPublish = -math.huge
Catcher.dirty = false
Catcher.week = nil
Catcher.anchorFailures = 0
Catcher.lastZones = {}
Catcher.started = false
Catcher.dumps = {}          -- full unit dumps taken at the throw, by GUID (logged on a catch; the dead unit is often gone)
Catcher.pinged = {}         -- GUIDs whose ring turned "best" (the ping plays once per NPC)
Catcher.pingedCount = 0
Catcher.hintPrinted = false -- the chat line that goes with the first red arrow (once per session)
Catcher.forceHint = false   -- dev: show the arrow regardless (/ggd caught hint)

local me = addon.Utility.Me
local now = addon.Utility.Now
local money = addon.Model.MoneyText

------------------------------------------------------------------ display capture (spike S1)

local captureModel
-- The CreatureDisplayInfo id of a unit, read through a hidden model (PlayerModel:SetUnit + GetDisplayInfo), or nil.
---@param unit string
---@return integer|nil
function Catcher.CaptureDisplay(unit)
    local ok, displayID = pcall(function()
        if not captureModel then
            captureModel = CreateFrame("PlayerModel", nil, UIParent)
            captureModel:SetSize(1, 1); captureModel:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
        end
        captureModel:SetUnit(unit)
        return captureModel.GetDisplayInfo and captureModel:GetDisplayInfo() or nil
    end)
    local valid = ok and addon.Utility.SafeInteger(displayID, 1, AzeCaught.MAXIMUM_ID) or nil
    AzeCaught.Journal("DEBUG", "found.display", valid and "a display id was read" or "no display id could be read",
        { unit = unit, display = tostring(displayID), ok = ok, api = captureModel and captureModel.GetDisplayInfo ~= nil })
    return valid
end

------------------------------------------------------------------ found NPCs
-- No combat log on this client (forbidden for addons, see Core/Game/Api.lua): an NPC counts as fought when it has the player
-- on its threat list (UNIT_THREAT_LIST_UPDATE, the target, nameplates) or when the rope is thrown at it.

-- Notes a hostile NPC from a unit token (level, rarity, display). Reads the unit's details only once per GUID; values
-- the client hides (secrets) are learned later from another sighting.
---@param unit string
---@return UnitSnapshot|nil
function Catcher.NoteUnit(unit)
    local snapshot = Api.UnitSnapshot(unit)
    if not snapshot or not snapshot.npc or snapshot.hostile == false then return snapshot end
    if not Catcher.fought[snapshot.guid] then
        Catcher.foughtCount = Catcher.foughtCount + 1
        if Catcher.foughtCount > MAXIMUM_NOTED then Catcher.fought, Catcher.foughtCount = {}, 1 end
        Catcher.fought[snapshot.guid] = snapshot.npc
    end
    if Catcher.noted[snapshot.guid] then return snapshot end
    if snapshot.name and snapshot.level then   -- complete: no need to read this GUID again
        Catcher.notedCount = Catcher.notedCount + 1
        if Catcher.notedCount > MAXIMUM_NOTED then Catcher.noted, Catcher.notedCount = {}, 1 end
        Catcher.noted[snapshot.guid] = true
    end
    local entry = AzeCaught.State().collection[snapshot.npc]
    local display = (not entry or entry.disp == 0) and Catcher.CaptureDisplay(unit) or nil
    AzeCaught.NoteFound({ npc = snapshot.npc, name = snapshot.name, level = snapshot.level, guid = snapshot.guid,
        classification = snapshot.classification, display = display, stats = Api.UnitStats(unit) }, now())
    return snapshot
end

-- An enemy that fought me died? Counts the kill once (Seen tab, user 2026-11-21). Returns true when it counted.
---@param unit string
---@return boolean
function Catcher.CheckKill(unit)
    local guid = Api.UnitGuid(unit)
    local npcID = guid and Catcher.fought[guid]
    if not npcID or not Api.IsDead(unit) then return false end
    Catcher.fought[guid] = nil
    if not AzeCaught.NoteKill(guid, npcID, now()) then return false end
    addon.Events.Fire("CAUGHT_CHANGED")
    return true
end

-- Notes `unit` when it is fighting the player.
---@param unit string
function Catcher.NoteIfFighting(unit)
    if Api.IsFightingMe(unit) then Catcher.NoteUnit(unit) end
end

-- The unit token currently showing `guid` (UnitTokenFromGUID, else nameplate/target/softenemy/mouseover/focus), or nil.
---@param guid string
---@return string|nil
function Catcher.UnitFor(guid)
    local unit = Api.UnitTokenFromGuid(guid)
    if unit then return unit end
    if Catcher.unitByGuid[guid] then return Catcher.unitByGuid[guid] end
    for _, candidate in ipairs({ "target", "softenemy", "mouseover", "focus" }) do
        if Api.UnitGuid(candidate) == guid then return candidate end
    end
    return nil
end

------------------------------------------------------------------ death watch (thrown GUIDs only)

-- `unit` died? (dead flag, or health 0 when readable). Only GUIDs with an armed throw are looked at.
---@param unit string
function Catcher.CheckDeath(unit)
    local guid = Api.UnitGuid(unit)
    if not guid or not AzeCaught.throws[guid] then return end
    local dead = Api.IsDead(unit)
    local snapshot = dead == nil and Api.UnitSnapshot(unit) or nil
    if dead == nil and snapshot and snapshot.health == 0 then dead = true end
    if dead then
        AzeCaught.Journal("DEBUG", "death.seen", "a thrown-at NPC was seen dead", { guid = guid, unit = unit })
        Catcher.OnDeath(guid, snapshot and snapshot.name or nil)
    end
end

local pollRunning = false
-- While a throw is armed, look for its NPC 5 times a second (the health event is not sent everywhere). A throw whose
-- window ended without a seen death is journaled, ended (AzeCaught.EndLateThrows) and snaps (Catcher.OnTooSlow).
function Catcher.PollThrows()
    pollRunning = false
    local clock = Api.Clock()
    local any = false
    for guid, throw in pairs(AzeCaught.throws) do
        local age = clock - throw.at
        any = true
        local unit = Catcher.UnitFor(guid)
        if unit then Catcher.CheckDeath(unit) end
        if age > AzeCaught.CATCH_WINDOW and AzeCaught.throws[guid] then
            AzeCaught.Journal("INFORMATION", "death.notSeen", "no death was seen inside the catch window",
                { guid = guid, npc = throw.npc, unitVisible = unit ~= nil })
        end
    end
    -- user 2026-11-20: killed too slow -> at the window's end the rope snaps (icon gone with a burst)
    for _, late in ipairs(AzeCaught.EndLateThrows(clock)) do Catcher.OnTooSlow(late.guid, late.name) end
    if any and C_Timer then pollRunning = true; C_Timer.After(0.2, function()
        addon.Log.Protected("caught.poll", "the throw poll failed", Catcher.PollThrows)
    end) end
end

local function startPoll()
    if not pollRunning then Catcher.PollThrows() end
end

------------------------------------------------------------------ throwing and catching

-- (literal Text[...] keys, so the locale test sees every key)
---@param reason string|nil
---@return string
local function throwRefusalText(reason)
    if reason == "cooldown" then return Text["The rope is not ready yet."] end
    if reason == "rolled" then return Text["You already tried to catch this one."] end
    if reason == "dead" then return Text["It is already dead."] end
    if reason == "thrown" then return Text["You already threw the rope at this one."] end
    return Text["Only NPCs can be caught."]
end

-- Throws the rope at `unit` (default target). Feedback in chat; every outcome is in the journal.
---@param unit? string
---@return boolean thrown
function Catcher.Throw(unit)
    unit = unit or "target"
    local snapshot = Api.UnitSnapshot(unit)
    if not snapshot then
        addon.Print(Text["No target to throw the rope at."])
        AzeCaught.Journal("DEBUG", "throw.refused", "a throw was refused", { reason = "nounit", unit = unit })
        return false
    end
    if snapshot.hostile == false then
        addon.Print(Text["Only hostile NPCs can be caught."])
        AzeCaught.Journal("DEBUG", "throw.refused", "a throw was refused", { reason = "friendly", unit = unit, guid = snapshot.guid })
        return false
    end
    local entry = snapshot.npc and AzeCaught.State().collection[snapshot.npc]
    local display = snapshot.npc and (not entry or entry.disp == 0) and Catcher.CaptureDisplay(unit) or nil
    if snapshot.npc then
        AzeCaught.NoteFound({ npc = snapshot.npc, name = snapshot.name, level = snapshot.level,
            classification = snapshot.classification, display = display, stats = Api.UnitStats(unit) }, now())
    end
    local thrown, reason = AzeCaught.Throw({ guid = snapshot.guid, health = snapshot.health, name = snapshot.name,
        level = snapshot.level, classification = snapshot.classification, display = display }, Api.PlayerLevel(), Api.Clock(), now())
    local name = addon.Utility.ChatSafe(snapshot.name or AzeCaught.State().collection[snapshot.npc or 0] and AzeCaught.State().collection[snapshot.npc].n or "?")
    if thrown then
        Catcher.PlayRopeEffect(unit)
        Catcher.dumps[snapshot.guid] = { at = Api.Clock(), values = Api.UnitDump(unit) }
        startPoll()
        addon.Print(Format(Text["Rope thrown at {name}: kill it within {seconds} seconds!"], { name = name, seconds = AzeCaught.CATCH_WINDOW }))
        Api.PlaySound(Api.SoundKitFor({ "IG_ABILITY_ICON_DROP", "IG_MAINMENU_OPTION_CHECKBOX_ON" }))
    elseif reason == "health" then
        addon.Print(Format(Text["{name} is not weak enough yet (at most {percent}% health)."],
            { name = name, percent = math.floor(AzeCaught.THROW_HEALTH * 100) }))
    else
        addon.Print(throwRefusalText(reason))
    end
    Catcher.RefreshIcons()
    return thrown and true or false
end

---@param guid string|nil
---@param name string|nil
function Catcher.OnDeath(guid, name)
    if not guid or not AzeCaught.throws[guid] then return end
    local result, reason = AzeCaught.OnDeath(guid, me(), Api.Clock(), now(), Api.Random)
    local npcName = addon.Utility.ChatSafe(name or "?")
    if result and result.caught then
        Catcher.LogCatchDump(guid, result)
        addon.Print("|cff66ff66" .. Format(Text["You caught {name}! (+{gold})"], { name = npcName, gold = money(result.reward) }) .. "|r"
            .. (result.first and (" " .. Text["(Your first catch always succeeds.)"]) or ""))
        if result.companion then   -- no companion was active: the catch is it now (user 2026-11-21)
            addon.Print(Format(Text["{name} is now your companion."], { name = npcName }))
            Catcher.lastZones = {}
            Catcher.PublishSoon(true)
        end
        Api.PlaySound(Api.SoundKitFor({ "UI_EPICLOOT_TOAST", "LOOTWINDOWCOINSOUND", "IG_QUEST_LIST_COMPLETE" }))
        addon.Events.Fire("CAUGHT_CHANGED")
    elseif result then
        addon.Print(Format(Text["{name} slipped out of the rope ({percent}% chance)."],
            { name = npcName, percent = ("%.1f"):format(result.chance * 100) }))
        Catcher.PlayFailEffect("escape", Catcher.UnitFor(guid))
    elseif reason == "late" then
        Catcher.OnTooSlow(guid, name, true)
        return
    end
    Catcher.RefreshIcons()
end

-- The catch window ended before the NPC died (user 2026-11-20: "the icon disappearing when getting killed too slow with
-- a small burst particle effect"): the rope snaps where the icon was, the icon goes (the NPC counts as rolled).
---@param guid string
---@param name string|nil
---@param died? boolean it died, just after the window
function Catcher.OnTooSlow(guid, name, died)
    addon.Print(Format(Text["Too slow: the rope slipped off {name}."], { name = addon.Utility.ChatSafe(name or "?") }))
    Catcher.PlayFailEffect("snap", Catcher.UnitFor(guid))
    AzeCaught.Journal("DEBUG", "throw.snap", "the rope snapped (killed too slow)", { guid = guid, died = died == true })
    Catcher.RefreshIcons()
end

-- Writes everything the client told about a caught NPC (taken at the throw) into the journal, with the roll.
---@param guid string
---@param result RollResult
function Catcher.LogCatchDump(guid, result)
    local stored = Catcher.dumps[guid]
    Catcher.dumps[guid] = nil
    local details = {}
    for key, value in pairs(stored and stored.values or {}) do details[key] = value end
    details.rollChance = ("%.4f"):format(result.chance or 0)
    details.roll = ("%.4f"):format(result.roll or 0)
    details.reward = result.reward
    details.dumpedAtThrow = stored ~= nil
    if not stored then details.npc = result.npc end
    AzeCaught.Journal("INFORMATION", "catch.dump", "everything the client told about the caught NPC (at the throw)", details)
end

-- The key binding's names for a build. Live and dev each load their own Bindings.xml (the dev one is generated by
-- tools/deploy.ps1 from the live one, replacing these three names), so both can be installed side by side (user
-- 2026-11-21: "Binding AZECAUGHT_THROW was attempted to be loaded more than once").
---@param isDevelopment boolean
---@return { header: string, name: string, func: string }
function Catcher.BindingNames(isDevelopment)
    local suffix = isDevelopment and "DEV" or ""
    return { header = "GUILDGAMES" .. suffix, name = "AZECAUGHT_THROW" .. (isDevelopment and "_DEV" or ""),
        func = (isDevelopment and "GuildGamesDev" or "GuildGames") .. "AzeCaughtThrow" }
end

-- the key binding and its labels (Options > Key Bindings > AddOns)
local BINDING = Catcher.BindingNames(addon.IS_DEVELOPMENT_BUILD == true)
_G[BINDING.func] = function() addon.Log.Protected("caught.throw", "the throw binding failed", Catcher.Throw, "target") end
_G["BINDING_HEADER_" .. BINDING.header] = addon.TITLE or "GuildGames"
_G["BINDING_NAME_" .. BINDING.name] = Text["AZEcaught: throw rope at target"]

------------------------------------------------------------------ rope icon on nameplates (spike S3)

---@param unit string
---@return table button
-- How hard the armed icon shakes with `remaining` seconds of the catch window left: 0 until SHAKE_SECONDS before the
-- end, then rising to SHAKE_MAXIMUM pixels (user 2026-11-20: "shake violently shortly before breaking").
---@param remaining number
---@return number pixels
function Catcher.ShakeAmplitude(remaining)
    remaining = tonumber(remaining) or math.huge
    if remaining >= SHAKE_SECONDS then return 0 end
    local progress = addon.Utility.Clamp(1 - remaining / SHAKE_SECONDS, 0, 1)
    return 1 + (SHAKE_MAXIMUM - 1) * progress * progress
end

-- Moves the icon's picture, ring and glow by a random offset of up to `amplitude` pixels (0: back in place). Only the
-- textures move; the button keeps its one anchor on the nameplate.
---@param button table
---@param amplitude number
function Catcher.ShakeIcon(button, amplitude)
    if amplitude <= 0 and not button.shaken then return end
    local x = amplitude > 0 and (math.random() * 2 - 1) * amplitude or 0
    local y = amplitude > 0 and (math.random() * 2 - 1) * amplitude or 0
    button.shaken = amplitude > 0
    button.texture:ClearAllPoints()
    button.texture:SetPoint("TOPLEFT", x, y); button.texture:SetPoint("BOTTOMRIGHT", x, y)
    button.border:ClearAllPoints()
    button.border:SetPoint("TOPLEFT", x - 3, y + 3); button.border:SetPoint("BOTTOMRIGHT", x + 3, y - 3)
    button.glow:ClearAllPoints(); button.glow:SetPoint("CENTER", x, y)
end

local function iconFor(unit)
    local button = Catcher.icons[unit]
    if button then return button end
    -- a round icon (circle mask) on a round ring that glows gold while a throw is armed (user 2026-11-20)
    button = CreateFrame("Button", nil, UIParent)
    button:SetSize(ICON_SIZE, ICON_SIZE); button:SetFrameStrata("MEDIUM"); button:Hide()
    local function round(texture)
        pcall(function()
            local mask = button:CreateMaskTexture()
            mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(texture)
            texture:AddMaskTexture(mask)
        end)
    end
    -- the glow behind the ring: gold and steady while a throw is armed, pulsing at the best moment (user 2026-11-20)
    local glow = button:CreateTexture(nil, "BACKGROUND", nil, -1); glow:SetPoint("CENTER")
    glow:SetColorTexture(1, 1, 1, 1)
    pcall(glow.SetBlendMode, glow, "ADD")
    round(glow)
    glow:Hide()
    button.glow = glow
    -- the ring: red -> yellow -> green with the catch chance (user 2026-11-20)
    local border = button:CreateTexture(nil, "BACKGROUND"); border:SetPoint("TOPLEFT", -3, 3); border:SetPoint("BOTTOMRIGHT", 3, -3)
    border:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    round(border)
    button.border = border
    -- the first-throw hint (user 2026-11-20): a glowing red arrow above the icon, pointing down at it, bobbing
    local arrowGlow = button:CreateTexture(nil, "OVERLAY", nil, 1)
    arrowGlow:SetSize(ARROW_SIZE * 1.6, ARROW_SIZE * 1.6)
    addon.UIHelpers.SetTextureOr(arrowGlow, ARROW_TEXTURE, ARROW_FALLBACK)
    pcall(arrowGlow.SetBlendMode, arrowGlow, "ADD")
    arrowGlow:SetVertexColor(1, 0.2, 0.1, 0.6)
    local arrow = button:CreateTexture(nil, "OVERLAY", nil, 2)
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    if not addon.UIHelpers.SetTextureOr(arrow, ARROW_TEXTURE, ARROW_FALLBACK) then arrow:SetVertexColor(1, 0.15, 0.1, 1) end
    arrowGlow:SetPoint("CENTER", arrow, "CENTER")
    arrow:Hide(); arrowGlow:Hide()
    button.arrow, button.arrowGlow = arrow, arrowGlow
    button.animationTime = 0
    button:SetScript("OnUpdate", function(self, elapsedSeconds)
        if self.armedAt then Catcher.ShakeIcon(self, Catcher.ShakeAmplitude(AzeCaught.CATCH_WINDOW - (Api.Clock() - self.armedAt))) end
        if not self.pulsing and not self.hinting then return end
        self.animationTime = self.animationTime + (tonumber(elapsedSeconds) or 0)
        local wave = 0.5 + 0.5 * math.sin(self.animationTime * 6)
        if self.pulsing then
            local glowSize = (self.iconSize or ICON_SIZE) + 10 + 10 * wave
            self.glow:SetSize(glowSize, glowSize)
            self.glow:SetAlpha(0.35 + 0.55 * wave)
        end
        if self.hinting then
            self.arrow:ClearAllPoints()
            self.arrow:SetPoint("BOTTOM", self, "TOP", 0, 4 + 6 * wave)
            self.arrowGlow:SetAlpha(0.3 + 0.6 * wave)
        end
    end)
    local texture = button:CreateTexture(nil, "ARTWORK"); texture:SetAllPoints(); texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addon.UIHelpers.SetTextureOr(texture, ROPE_ICON, ROPE_FALLBACK)
    round(texture)
    button.texture = texture
    local highlight = button:CreateTexture(nil, "HIGHLIGHT"); highlight:SetAllPoints(); highlight:SetColorTexture(1, 1, 1, 0.25)
    round(highlight)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function(self) Catcher.Throw(self.unit) end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Text["Throw the rope"])
        if self.chance then
            GameTooltip:AddLine(Format(Text["Catch chance now: {percent}%"], { percent = math.floor(self.chance * 100 + 0.5) }),
                AzeCaught.QualityColor(self.quality))
        end
        GameTooltip:AddLine(Format(Text["Kill it within {seconds} seconds for a chance to catch it."], { seconds = AzeCaught.CATCH_WINDOW }), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Catcher.icons[unit] = button
    return button
end

------------------------------------------------------------------ throw effect: a wind-up on the player, then the lasso on the target

local effect   -- { playerPin, targetPin, failPin } built on first use

-- The effect pins: 1x1 frames (parent UIParent, one anchor each) the effect textures live in.
local function effectPins()
    if not effect then
        local function newPin()
            local pin = CreateFrame("Frame", nil, UIParent)
            pin:SetSize(1, 1); pin:SetFrameStrata("HIGH"); pin:EnableMouse(false)
            return pin
        end
        effect = { playerPin = newPin(), targetPin = newPin(), failPin = newPin() }
    end
    return effect
end

-- Puts `pin` on the unit's nameplate with ONE SetPoint (the only thing the client allows, see below); no plate or a
-- refused anchor: above the player ("front"). Returns the mode and why it is not "nameplate".
---@param pin table
---@param unit string|nil
---@param point string
---@param relativePoint string
---@param x number
---@param y number
---@return "nameplate"|"front" mode
---@return string|nil why
local function placeOnPlate(pin, unit, point, relativePoint, x, y)
    local plate = unit and Api.NamePlateFor(unit)
    local why
    if plate then
        local anchored, anchorError = pcall(function()
            pin:ClearAllPoints()
            pin:SetPoint(point, plate, relativePoint, x, y)
        end)
        if anchored then return "nameplate", nil end
        why = tostring(anchorError)
    else
        why = "no nameplate"
    end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", UIParent:GetWidth() / 2, UIParent:GetHeight() * (PLAYER_SCREEN_HEIGHT + FRONT_RISE))
    return "front", why
end

-- Lets go of the plate once the effect is over (a recycled plate then carries nothing of ours).
---@param key string
---@param pin table
local function releaseLater(key, pin)
    addon.Animate.Tween(key, LANDING_LINGER, function() end, function()
        pin:ClearAllPoints(); pin:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end)
end

-- The client does not let an addon know where an enemy is on the screen (journal 2026-11-20): its world position is
-- hidden (UnitPosition), range checks are restricted in combat, measuring a nameplate taints the addon ("Can't measure
-- restricted regions") and a line may not end on one ("Not allowed to depend on NamePlate1"). A plain frame with ONE
-- anchor on a nameplate is allowed (the rope icon is placed that way). So the throw is two effects, nothing in between
-- (user 2026-11-20: "first a cool animation on the player and then after a short amount on the enemy"):
--   1. wind-up on the player (screen centre, PLAYER_SCREEN_HEIGHT): a rope ring gathers in, sparks rise, a gold flash;
--   2. ROPE_DELAY later the lasso closes and bursts on the target, in a 1x1 pin frame anchored to its nameplate, so it
--      plays on the real enemy wherever it is. Nothing measures the pin; it lets go of the plate after LANDING_LINGER.
-- No nameplate (plates off, target not on screen) or a refused anchor: the lasso plays above the player ("front").
-- Journaled as `throw.effect` with the mode and the reason.
---@param unit string the target unit
---@return table|nil details what was played (also Catcher.lastEffect)
function Catcher.PlayRopeEffect(unit)
    local ok, problem = pcall(function()
        local pins = effectPins()
        local Animate = addon.Animate
        local playerPin, targetPin = pins.playerPin, pins.targetPin
        playerPin:ClearAllPoints()
        playerPin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", UIParent:GetWidth() / 2, UIParent:GetHeight() * PLAYER_SCREEN_HEIGHT)
        local mode, why = placeOnPlate(targetPin, unit, "TOP", "BOTTOM", 0, -LANDING_DROP)
        -- 1. wind-up on the player: the rope gathers in, sparks rise, a gold ring flashes out
        Animate.Ring("ropeWind", playerPin, playerPin, 110, 26, ROPE_COLOR, ROPE_DELAY)
        Animate.Burst("ropeCast", playerPin, playerPin, 0, 0,
            { count = 14, color = { 1, 0.85, 0.4 }, speed = 120, gravity = -80, size = 11, spread = math.pi * 0.8, duration = 0.6 })
        -- 2. the lasso on the target
        Animate.Tween("ropeThrow", ROPE_DELAY, function() end, function()
            Animate.Ring("ropeFlash", playerPin, playerPin, 20, 90, { 1, 0.85, 0.3 }, 0.3)
            Animate.Ring("ropeLasso", targetPin, targetPin, 80, 18, ROPE_COLOR, 0.3)
            Animate.Burst("ropeHit", targetPin, targetPin, 0, 0,
                { count = 16, color = { 1, 0.8, 0.35 }, speed = 100, gravity = 200, size = 12, duration = 0.7 })
            Animate.Ring("ropeHit", targetPin, targetPin, 10, 70, { 1, 0.85, 0.3 }, 0.45)
            releaseLater("ropeLanding", targetPin)
        end)
        local details = { unit = unit, mode = mode, why = why }
        Catcher.lastEffect = details
        AzeCaught.Journal("DEBUG", "throw.effect", "the throw effect was played", details)
        -- dev build: say at once where it landed (and why not on the target)
        if addon.IS_DEVELOPMENT_BUILD then
            addon.Print(("rope effect: %s%s"):format(mode, why and (" (" .. why .. ")") or ""))
        end
    end)
    if not ok then
        Catcher.lastEffect = { mode = "failed", error = tostring(problem), unit = unit }
        AzeCaught.Journal("WARNING", "throw.effect", "the throw effect failed", { error = tostring(problem) })
    end
    return Catcher.lastEffect
end

-- Why the rope icon of a unit stays hidden, or nil when it shows (user 2026-11-20: "why does the icon not appear in
-- the dungeon?" - the client hides values in instances; the journal now says which one was missing).
---@param settings table AzeCaught.IconSettings()
---@param plate table|nil
---@param snapshot UnitSnapshot|nil
---@param weakEnough any
---@return string|nil
function Catcher.IconHiddenReason(settings, plate, snapshot, weakEnough)
    if not settings.shown then return "turned off" end
    if not snapshot then return "unit unreadable (GUID hidden or no unit)" end
    if not snapshot.npc then return "not an NPC" end
    if snapshot.hostile == false then return "not hostile" end
    if snapshot.dead == true then return "dead" end
    if AzeCaught.rolled[snapshot.guid] then return "already tried" end
    if not weakEnough then
        return snapshot.health == nil and "health hidden and not the target" or "health above the threshold"
    end
    if not plate then return "no nameplate frame" end
    return nil
end

-- Journals the icon state of a unit when its reason changes (DEBUG; "health above the threshold" is the normal case
-- and not written). Bounded by the 40 nameplate tokens.
---@param unit string
---@param snapshot UnitSnapshot|nil
---@param reason string|nil
function Catcher.NoteIconReason(unit, snapshot, reason)
    Catcher.iconReasons = Catcher.iconReasons or {}
    local key = (snapshot and snapshot.guid or "?") .. "|" .. tostring(reason)
    if Catcher.iconReasons[unit] == key then return end
    Catcher.iconReasons[unit] = key
    if reason == "health above the threshold" then return end
    AzeCaught.Journal("DEBUG", "icon.state", reason and "the rope icon stays hidden" or "the rope icon is shown",
        { unit = unit, reason = reason, npc = snapshot and snapshot.npc, health = snapshot and (snapshot.health and
            ("%.0f%%"):format(snapshot.health * 100) or "hidden"), instance = Api.InInstance() })
end

-- Shows or hides the rope icon of one nameplate unit.
---@param unit string
function Catcher.UpdateIcon(unit)
    local button = Catcher.icons[unit]
    local snapshot = Api.UnitSnapshot(unit)
    local plate = Api.NamePlateFor(unit)
    -- health hidden (a secret in combat): the icon shows on the current target, and the throw rolls at the threshold
    local weakEnough = snapshot and ((snapshot.health and snapshot.health <= AzeCaught.THROW_HEALTH)
        or (snapshot.health == nil and Api.UnitGuid("target") == snapshot.guid))
    local settings = AzeCaught.IconSettings()
    local hiddenBecause = Catcher.IconHiddenReason(settings, plate, snapshot, weakEnough)
    Catcher.NoteIconReason(unit, snapshot, hiddenBecause)
    if hiddenBecause then
        if button then button:Hide() end
        return
    end
    button = iconFor(unit)
    button.unit = unit
    local ok, problem = pcall(function()
        button:ClearAllPoints()
        -- above the plate (the level and name stay readable), moved by the icon settings
        button:SetPoint("BOTTOM", plate, "TOP", settings.x, settings.y)
        button:SetSize(settings.size, settings.size)
        button.iconSize = settings.size   -- never measured: the button hangs on a nameplate
    end)
    if not ok then
        Catcher.anchorFailures = Catcher.anchorFailures + 1
        if Catcher.anchorFailures == 1 then
            AzeCaught.Journal("WARNING", "icon.anchor", "the rope icon could not be attached to a nameplate", { error = tostring(problem) })
        end
        button:Hide()
        return
    end
    Catcher.StyleIcon(button, snapshot)
    button:Show()
end

-- The ring colour (the chance), the glow (armed: gold; best moment: pulsing green with a ping once per NPC) and the
-- first-throw arrow of one icon.
---@param button table
---@param snapshot UnitSnapshot
function Catcher.StyleIcon(button, snapshot)
    local throw = AzeCaught.throws[snapshot.guid]
    local armed = throw ~= nil
    -- catch mode: the net icon and the shake clock (OnUpdate); back to the rope and still otherwise
    button.armedAt = throw and throw.at or nil
    local iconPath = armed and CATCH_ICON or ROPE_ICON
    if button.iconPath ~= iconPath then
        button.iconPath = iconPath
        addon.UIHelpers.SetTextureOr(button.texture, iconPath, armed and ROPE_ICON or ROPE_FALLBACK)
    end
    if not armed then Catcher.ShakeIcon(button, 0) end
    local quality, best = AzeCaught.ThrowQuality(snapshot.health, snapshot.classification)
    button.quality = quality
    button.chance = quality and AzeCaught.Chance(snapshot.health, snapshot.classification).chance or nil
    local red, green, blue = AzeCaught.QualityColor(quality)
    button.border:SetColorTexture(red, green, blue, 1)
    button.pulsing = best and not armed
    if armed then
        local glowSize = (button.iconSize or ICON_SIZE) + 12
        button.glow:SetSize(glowSize, glowSize); button.glow:SetVertexColor(1, 0.82, 0.2, 1); button.glow:SetAlpha(0.8)
        button.glow:Show()
    elseif best then
        button.glow:SetVertexColor(red, green, blue, 1); button.glow:Show()
    else
        button.glow:Hide()
    end
    if best and not Catcher.pinged[snapshot.guid] then
        if Catcher.pingedCount >= MAXIMUM_PINGED then Catcher.pinged, Catcher.pingedCount = {}, 0 end
        Catcher.pinged[snapshot.guid], Catcher.pingedCount = true, Catcher.pingedCount + 1
        Api.PlaySoundNamed(BEST_SOUNDS)
    end
    local hinting = (Catcher.forceHint or AzeCaught.NeedsThrowHint()) and not armed
    button.hinting = hinting
    button.arrow:SetShown(hinting); button.arrowGlow:SetShown(hinting)
    if hinting then
        button.arrow:ClearAllPoints(); button.arrow:SetPoint("BOTTOM", button, "TOP", 0, 4)
        if not Catcher.hintPrinted then
            Catcher.hintPrinted = true
            addon.Print(Format(Text["New: click the rope icon above a weakened enemy, then finish it within {seconds} seconds to catch it."],
                { seconds = AzeCaught.CATCH_WINDOW }))
            AzeCaught.Journal("INFORMATION", "hint.arrow", "the first-throw arrow was shown", { forced = Catcher.forceHint or nil })
        end
    end
end

function Catcher.RefreshIcons()
    for unit in pairs(Catcher.icons) do Catcher.UpdateIcon(unit) end
    for _, unit in pairs(Catcher.unitByGuid) do Catcher.UpdateIcon(unit) end
end

-- The rope failed (user 2026-11-20, two different effects):
--   "escape": the NPC died and slipped out: red rope fragments fly off the target and a grey puff spreads;
--   "snap":   killed too slow: the rope icon cracks into brown and grey shards where it was.
-- Both play in a pin on the unit's nameplate (one anchor, like the throw), else above the player. Journaled as
-- `fail.effect`; a short snap sound.
---@param kind "escape"|"snap"
---@param unit string|nil
---@return table details (also Catcher.lastFailEffect)
function Catcher.PlayFailEffect(kind, unit)
    local ok, problem = pcall(function()
        local pin = effectPins().failPin
        local Animate = addon.Animate
        local mode, why
        if kind == "snap" then
            local settings = AzeCaught.IconSettings()
            mode, why = placeOnPlate(pin, unit, "CENTER", "TOP", settings.x, settings.y + settings.size / 2)
            Animate.Burst("failShards", pin, pin, 0, 0,
                { count = 14, color = ROPE_COLOR, speed = 110, gravity = 260, size = 9, duration = 0.7 })
            Animate.Burst("failDust", pin, pin, 0, 0,
                { count = 8, color = { 0.6, 0.6, 0.6 }, speed = 60, gravity = 40, size = 12, duration = 0.6 })
            Animate.Ring("failRing", pin, pin, settings.size + 6, settings.size * 2.4, { 0.55, 0.5, 0.45 }, 0.4)
        else
            mode, why = placeOnPlate(pin, unit, "TOP", "BOTTOM", 0, -LANDING_DROP)
            Animate.Burst("failShards", pin, pin, 0, 0,
                { count = 18, color = { 0.9, 0.2, 0.12 }, speed = 150, gravity = 160, size = 11, duration = 0.8 })
            Animate.Burst("failDust", pin, pin, 0, 0,
                { count = 10, color = { 0.75, 0.72, 0.68 }, speed = 50, gravity = -30, size = 16, duration = 0.9 })
            Animate.Ring("failRing", pin, pin, 20, 90, { 0.95, 0.25, 0.15 }, 0.45)
        end
        releaseLater("failLanding", pin)
        Api.PlaySoundNamed(SNAP_SOUNDS)
        Catcher.lastFailEffect = { kind = kind, unit = unit, mode = mode, why = why }
        AzeCaught.Journal("DEBUG", "fail.effect", "the rope fail effect was played", Catcher.lastFailEffect)
    end)
    if not ok then
        Catcher.lastFailEffect = { kind = kind, mode = "failed", error = tostring(problem), unit = unit }
        AzeCaught.Journal("WARNING", "fail.effect", "the rope fail effect failed", { error = tostring(problem) })
    end
    return Catcher.lastFailEffect
end

------------------------------------------------------------------ active time, publishing, reminders, payout

---@param need string
---@return string
local function needText(need)
    if need == "hunger" then return Text["{name} is hungry."] end
    if need == "thirst" then return Text["{name} is thirsty."] end
    if need == "affection" then return Text["{name} wants to be petted."] end
    return Text["{name} is tired."]
end

local function remind(companion)
    local caught = AzeCaught.State()
    for _, need in ipairs(AzeCaught.NEEDS) do
        local zone = companion.zones[need]
        local previous = Catcher.lastZones[need]
        local worse = (zone == "needy" and previous == "ok") or ((zone == "critical" or zone == "empty") and previous ~= "critical" and previous ~= "empty")
        if worse and previous ~= nil and caught.notify then
            addon.Print(Format(needText(need), { name = addon.Utility.ChatSafe(companion.n) })
                .. (zone ~= "needy" and (" |cffff4040" .. Text["(critical)"] .. "|r") or ""))
        end
        Catcher.lastZones[need] = zone
    end
end

-- Writes my companion into my game record when something changed (at most every PUBLISH_MINIMUM_GAP) or every
-- PUBLISH_EVERY seconds. `force` publishes now (select, care, death).
---@param force? boolean
function Catcher.PublishSoon(force)
    local clock = Api.Clock()
    Catcher.dirty = true
    if not force and clock - Catcher.lastPublish < PUBLISH_MINIMUM_GAP then return end
    Catcher.dirty = false
    Catcher.lastPublish = clock
    if AzeCaught.Publish(me(), now()) then addon.Events.Fire("GAMES_CHANGED") end
end

------------------------------------------------------------------ companion arena (feature 020)

local ARENA_TICK = 5   -- seconds between arena checks (training, answers, fights, bets)
Catcher.lastArena = 0

-- Writes my arena section into my game record (a new rev) and announces it; redraws the panel.
function Catcher.PublishArena()
    if addon.Games.SetSection(me(), "arena", addon.Arena.BuildSection(), now()) then addon.Events.Fire("GAMES_CHANGED") end
    addon.Events.Fire("CAUGHT_CHANGED")
end

local STAT_TEXT = { atk = Text["Attack"], def = Text["Defense"], spd = Text["Speed"], vit = Text["Vitality"] }
Catcher.ARENA_STAT_TEXT = STAT_TEXT

-- One chat line per arena notice (Arena.Settle).
---@param notice table
---@return string|nil
function Catcher.ArenaNoticeText(notice)
    local function short(name) return addon.Utility.ChatSafe((name or "?"):match("^([^%-]+)") or name or "?") end
    if notice.kind == "challenged" then
        return Format(Text["{name} challenges your companion to an arena fight (wager {gold}). Answer in AZEcaught > Arena."],
            { name = short(notice.from), gold = money(notice.wager) })
    elseif notice.kind == "answered" then
        return Format(notice.accepted and Text["{name} accepted your arena challenge. The fight is decided in 5 minutes."]
            or Text["{name} declined your arena challenge."], { name = short(notice.by) })
    elseif notice.kind == "won" then
        return "|cff66ff66" .. Format(Text["Arena: your companion beat {name}! (+{gold})"], { name = short(notice.opponent), gold = money(notice.wager * 2) }) .. "|r"
    elseif notice.kind == "lost" then
        return "|cffff6060" .. Format(Text["Arena: {name} beat your companion."], { name = short(notice.opponent) }) .. "|r"
    elseif notice.kind == "refund" then
        return notice.wager > 0 and Format(Text["Arena: {gold} came back to your pool."], { gold = money(notice.wager) }) or nil
    elseif notice.kind == "betwon" then
        return "|cff66ff66" .. Format(Text["Arena bet won: {gold} on {name}."], { gold = money(notice.payout), name = short(notice.fighter) }) .. "|r"
    elseif notice.kind == "betlost" then
        return Format(Text["Arena bet lost: {name} did not win."], { name = short(notice.fighter) })
    end
    return nil
end

-- Training, answers, fights and bets: runs every ARENA_TICK seconds from the tick (and on demand).
---@param force? boolean
function Catcher.ArenaTick(force)
    local clock = Api.Clock()
    if not force and clock - Catcher.lastArena < ARENA_TICK then return end
    Catcher.lastArena = clock
    local Arena = addon.Arena
    local publish = false
    local finished = Arena.FinishTraining()
    if finished then
        local entry = AzeCaught.State().collection[finished.npc]
        addon.Print(Format(Text["Training done: {name}'s {stat} is now {points}."], { name = addon.Utility.ChatSafe(entry and entry.n or "?"),
            stat = STAT_TEXT[finished.stat], points = finished.points }))
        Api.PlaySound(Api.SoundKitFor({ "LEVELUPSOUND", "IG_QUEST_LIST_COMPLETE" }))
        addon.Events.Fire("CAUGHT_CHANGED")
    end
    -- the dev dummy (dev build only) accepts my challenges to it
    local dummy = addon.IS_DEVELOPMENT_BUILD and addon.Games.simulated[Arena.DUMMY_NAME]
    if dummy and Arena.DummyRespond(dummy, me(), now()) > 0 then
        addon.Print("[dev] the arena dummy accepted your challenge: the fight is decided in " .. math.floor(Arena.BET_WINDOW / 60) .. " minutes")
        addon.Events.Fire("CAUGHT_CHANGED")
    end
    local notices, changed = Arena.Settle(addon.Games.AllRecords(), me(), now())
    for _, notice in ipairs(notices) do
        local line = Catcher.ArenaNoticeText(notice)
        if line then addon.Print(line) end
        if notice.kind == "challenged" then Api.PlaySound(Api.SoundKitFor({ "READY_CHECK", "RAID_WARNING" })) end
        if notice.kind == "won" or notice.kind == "lost" or notice.kind == "refund" or notice.kind == "betwon" then publish = true end
        if notice.kind == "won" or notice.kind == "lost" then Catcher.lastFight = notice.id end
    end
    if changed or publish then Catcher.PublishArena()
    elseif #notices > 0 then addon.Events.Fire("CAUGHT_CHANGED") end
end

function Catcher.RunPayout()
    local amount, reason, rank = AzeCaught.WeeklyPayout(me(), addon.Store.db.games, now())
    if amount > 0 then
        addon.Print(Format(Text["Weekly AZEcaught payout: place {rank}, {gold} added to your pool."], { rank = rank, gold = money(amount) }))
        addon.Events.Fire("CAUGHT_CHANGED")
    end
    return amount, reason
end

function Catcher.OnTick()
    local clock = Api.Clock()
    local elapsedSeconds = Catcher.lastClock and (clock - Catcher.lastClock) or 0
    Catcher.lastClock = clock
    local serverNow = now()
    local before = AzeCaught.Active()
    local result = AzeCaught.Tick(elapsedSeconds, serverNow)
    AzeCaught.ExpireThrows(clock)
    for guid, stored in pairs(Catcher.dumps) do
        if clock - stored.at > 60 then Catcher.dumps[guid] = nil end
    end
    local companion = AzeCaught.Active()
    if result.died and before then
        addon.Print("|cffff4040" .. Format(Text["{name} died: it was left hungry or thirsty for too long."],
            { name = addon.Utility.ChatSafe(before.n) }) .. "|r")
        Catcher.lastZones = {}
        Catcher.PublishSoon(true)
    elseif companion then
        remind(companion)
        if result.changed then Catcher.PublishSoon(false) end
        if Catcher.dirty and clock - Catcher.lastPublish >= PUBLISH_MINIMUM_GAP then Catcher.PublishSoon(true) end
        if clock - Catcher.lastPublish >= PUBLISH_EVERY then Catcher.PublishSoon(true) end
    end
    if result.changed or result.died then addon.Events.Fire("CAUGHT_CHANGED") end
    addon.Log.Protected("caught.arena", "the arena check failed", Catcher.ArenaTick)
    local periodKey = addon.Games.PeriodKey(serverNow)
    if Catcher.week and periodKey ~= Catcher.week then Catcher.RunPayout() end
    Catcher.week = periodKey
end

-- Starts the ticker and the payout check (PLAYER_LOGIN).
function Catcher.Start()
    if Catcher.started then return end
    Catcher.started = true
    Catcher.lastClock = Api.Clock()
    Catcher.week = addon.Games.PeriodKey(now())
    local companion = AzeCaught.Active()
    if companion then for _, need in ipairs(AzeCaught.NEEDS) do Catcher.lastZones[need] = companion.zones[need] end end
    if C_Timer then
        Catcher.ticker = C_Timer.NewTicker(1, function()
            addon.Log.Protected("caught.tick", "the AZEcaught tick failed", Catcher.OnTick)
        end)
        C_Timer.After(5, function() addon.Log.Protected("caught.publish", "publishing failed", Catcher.PublishSoon, true) end)
        -- after the first records arrived: last week's place (the stored records of the last session count too)
        C_Timer.After(60, function() addon.Log.Protected("caught.payout", "the weekly payout failed", Catcher.RunPayout) end)
    end
    AzeCaught.Journal("INFORMATION", "start", "AZEcaught started",
        { found = addon.Utility.Count(AzeCaught.State().collection), active = companion and companion.npc or nil,
          activeSeconds = math.floor(AzeCaught.State().activeSeconds), balance = addon.Wallet.Balance(me()),
          version = addon.VERSION })
end

------------------------------------------------------------------ game events

local eventFrame = CreateFrame("Frame")
local onEvent = {}

function onEvent.NAME_PLATE_UNIT_ADDED(unit)
    local guid = Api.UnitGuid(unit)
    if guid then Catcher.unitByGuid[guid] = unit end
    Catcher.UpdateIcon(unit)
end

function onEvent.NAME_PLATE_UNIT_REMOVED(unit)
    Catcher.CheckKill(unit)   -- a dead enemy's plate goes away; the unit is still readable here
    for guid, plateUnit in pairs(Catcher.unitByGuid) do
        if plateUnit == unit then Catcher.unitByGuid[guid] = nil end
    end
    if Catcher.icons[unit] then Catcher.icons[unit]:Hide() end
end

-- units the player can see; the rest of a raid's health events are not looked at
---@param unit any
---@return boolean
local function watchedUnit(unit)
    return type(unit) == "string" and (unit == "target" or unit == "softenemy" or unit == "mouseover" or unit == "focus"
        or unit:find("^nameplate") ~= nil)
end

function onEvent.UNIT_HEALTH(unit)
    if not watchedUnit(unit) then return end
    if unit:find("^nameplate") then Catcher.UpdateIcon(unit) end
    if next(AzeCaught.throws) then Catcher.CheckDeath(unit) end
    if next(Catcher.fought) then Catcher.CheckKill(unit) end
end

function onEvent.UNIT_THREAT_LIST_UPDATE(unit)
    if watchedUnit(unit) then Catcher.NoteIfFighting(unit) end
end

function onEvent.PLAYER_TARGET_CHANGED()
    if Api.UnitGuid("target") then Catcher.NoteIfFighting("target") end
    Catcher.RefreshIcons()   -- with hidden health the icon follows the target
end

for gameEvent in pairs(onEvent) do
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, gameEvent)
    if not ok then AzeCaught.Journal("WARNING", "events.register", "this client does not know a game event", { event = gameEvent }) end
end
eventFrame:SetScript("OnEvent", function(_, gameEvent, ...)
    local handler = onEvent[gameEvent]
    if handler then addon.Log.Protected("caught.event", "an AZEcaught event handler failed (" .. tostring(gameEvent) .. ")", handler, ...) end
end)

------------------------------------------------------------------ slash commands (diagnostics in English on purpose)

---@param details table
---@return string
local function keyValues(details)
    local parts = {}
    for _, key in ipairs(addon.Utility.SortedKeys(details)) do parts[#parts + 1] = key .. "=" .. tostring(details[key]) end
    return table.concat(parts, " ")
end

local function printLine(text) print(addon.Utility.Escape(text)) end

---@type table<string, fun(arguments: string)>
local commands = {}
Catcher.commands = commands

function commands.state()
    local caught = AzeCaught.State()
    local companion = caught.active
    printLine(("AZEcaught: active time %ds, found %d, notify %s, verbose %s, paidWeek %s, firstCatchDone %s"):format(
        math.floor(caught.activeSeconds), addon.Utility.Count(caught.collection), tostring(caught.notify),
        tostring(caught.verbose == true), tostring(caught.paidWeek), tostring(caught.firstCatchDone == true)))
    if not companion then printLine("no companion") return end
    printLine(keyValues(AzeCaught.Describe(companion)))
    for _, need in ipairs(AzeCaught.NEEDS) do
        local seconds = AzeCaught.SecondsUntilNeedy(companion, need)
        printLine(("  %s %.1f zone=%s needyIn=%s"):format(need, companion[need], companion.zones[need],
            seconds == math.huge and "asleep" or (math.floor(seconds / 60) .. "min")))
    end
end

function commands.log(arguments)
    local count = tonumber((arguments or ""):match("^(%d+)")) or 20
    local filter = (arguments or ""):gsub("^%d+%s*", "")
    local lines = AzeCaught.JournalLines(count, filter ~= "" and filter or nil)
    if #lines == 0 then printLine("journal: no lines" .. (filter ~= "" and (" matching '" .. filter .. "'") or "")) end
    for _, line in ipairs(lines) do printLine(line) end
end

function commands.wallet()
    local breakdown = addon.Wallet.Breakdown(me())
    printLine(("balance %d = grant %d + casino %d (coin %d, slots %d, survivor %d) - pending %d + earned %d - spent %d (copper)"):format(
        breakdown.balance, breakdown.grant, breakdown.casino, breakdown.byGame.coin, breakdown.byGame.slots, breakdown.byGame.survivor,
        breakdown.pending, breakdown.earned, breakdown.spent))
    local entries = addon.Wallet.Ledger().entries
    for index = math.max(1, #entries - 9), #entries do
        local entry = entries[index]
        printLine(("  %s %s %+d -> %d %s"):format(date and date("%m-%d %H:%M", entry.t) or entry.t, entry.k, entry.a, entry.b, entry.note or ""))
    end
end

function commands.chance()
    local snapshot = Api.UnitSnapshot("target")
    if not snapshot or not snapshot.npc then printLine("chance: target an NPC") return end
    local breakdown = AzeCaught.Chance(snapshot.health, snapshot.classification)
    local healthKnown = type(snapshot.health) == "number"
    printLine(("chance %.1f%% = health %.1f%% (hp %s) - rarity %.1f (%s), at least %.0f%%%s; icon %s; reward %s; rolled %s"):format(
        breakdown.chance * 100, breakdown.healthChance * 100, healthKnown and ("%.1f%%"):format(snapshot.health * 100) or "hidden",
        breakdown.malus * 100, breakdown.classification, AzeCaught.MINIMUM_CHANCE * 100, breakdown.best and " (best)" or "",
        (not healthKnown or snapshot.health <= AzeCaught.THROW_HEALTH) and "yes" or "no", money(AzeCaught.Reward(breakdown.chance)),
        tostring(AzeCaught.rolled[snapshot.guid] ~= nil)))
end

function commands.collection()
    local caughtCount, newest = 0, {}
    for npcID, entry in pairs(AzeCaught.State().collection) do
        if entry.caught > 0 then caughtCount = caughtCount + 1 end
        newest[#newest + 1] = { npc = npcID, entry = entry }
    end
    table.sort(newest, function(left, right) return left.entry.seen > right.entry.seen end)
    printLine(("collection: %d found, %d caught"):format(#newest, caughtCount))
    for index = 1, math.min(5, #newest) do
        local item = newest[index]
        printLine(("  %d %s lvl %d %s display %d caught %d"):format(item.npc, item.entry.n, item.entry.lvl, item.entry.cls, item.entry.disp, item.entry.caught))
    end
end

local function toggle(field, arguments)
    local word = (arguments or ""):match("^%s*(%S*)")
    local caught = AzeCaught.State()
    if word == "on" then caught[field] = true elseif word == "off" then caught[field] = field == "notify" and false or nil end
    printLine(field .. " " .. ((caught[field] and "on") or "off"))
    addon.Events.Fire("CAUGHT_CHANGED")
end
function commands.verbose(arguments) toggle("verbose", arguments) end
function commands.notify(arguments) toggle("notify", arguments) end

function commands.export()
    local line = AzeCaught.Export(me())
    AzeCaught.State().lastExport = line
    printLine(line)
    printLine("(also saved as lastExport in the SavedVariables file after /reload or logout)")
end

-- /gg caught dump [unit]: everything the client tells about a unit (default target), into the journal and chat
function commands.dump(arguments)
    local unit = ((arguments or ""):match("^%s*(%S+)") or "target"):lower()
    local values = Api.UnitDump(unit)
    AzeCaught.Journal("INFORMATION", "dump", "everything the client tells about a unit", values)
    for _, key in ipairs(addon.Utility.SortedKeys(values)) do printLine(("  %s = %s"):format(key, values[key])) end
end

-- /gg caught identity [unit]: every other way the client might say who a unit is (dungeons hide the GUID and name)
function commands.identity(arguments)
    local unit = ((arguments or ""):match("^%s*(%S+)") or "target"):lower()
    local values = Api.IdentityProbe(unit)
    AzeCaught.Journal("INFORMATION", "identity", "other ways to tell who a unit is", values)
    for _, key in ipairs(addon.Utility.SortedKeys(values)) do printLine(("  %s = %s"):format(key, values[key])) end
end

-- Spikes S1-S3: what this client can do (results also go to the journal).
function commands.probe()
    local targetSnapshot = Api.UnitSnapshot("target")
    local display = targetSnapshot and targetSnapshot.npc and Catcher.CaptureDisplay("target")
    local result1 = targetSnapshot and targetSnapshot.npc and ("display " .. tostring(display)) or "target an NPC first"
    local panelModel = addon.AzeCaughtPanel.widgets.model
    local animations = {}
    if panelModel and panelModel.HasAnimation then
        for _, animationID in ipairs({ 0, 4, 5, 26, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 100, 101, 102, 103, 113, 114 }) do
            local ok, has = pcall(panelModel.HasAnimation, panelModel, animationID)
            if ok and has then animations[#animations + 1] = animationID end
        end
    end
    local result2 = panelModel and ("animations " .. (#animations > 0 and table.concat(animations, ",") or "none or HasAnimation missing"))
        or "open the AZEcaught companion view first"
    local plates = 0
    for _ in pairs(Catcher.unitByGuid) do plates = plates + 1 end
    local result3 = ("nameplates %d, icons shown %d, anchor failures %d, combat %s"):format(plates,
        (function() local shown = 0 for _, button in pairs(Catcher.icons) do if button:IsShown() then shown = shown + 1 end end return shown end)(),
        Catcher.anchorFailures, tostring(InCombatLockdown and InCombatLockdown() or false))
    printLine("S1 " .. result1); printLine("S2 " .. result2); printLine("S3 " .. result3)
    AzeCaught.Journal("INFORMATION", "probe", "spike probe", { s1 = result1, s2 = result2, s3 = result3 })
end

-- dev build only: cheats for testing without hours of play
local developmentCommands = {}
function developmentCommands.time(arguments)
    local minutes = tonumber((arguments or ""):match("(%d+)")) or 10
    AzeCaught.Journal("INFORMATION", "dev.time", "active time was fast-forwarded", { minutes = minutes })
    for _ = 1, math.floor(minutes * 60 / AzeCaught.MAXIMUM_TICK) do
        local result = AzeCaught.Tick(AzeCaught.MAXIMUM_TICK, now())
        if result.died then printLine("the companion died while fast-forwarding") break end
    end
    addon.Events.Fire("CAUGHT_CHANGED"); commands.state()
end
function developmentCommands.give(arguments)
    local gold = tonumber((arguments or ""):match("(%d+)")) or 100
    addon.Wallet.Earn(me(), gold * 10000, "dev", now(), "give")
    addon.Events.Fire("CAUGHT_CHANGED"); commands.wallet()
end
function developmentCommands.force()
    AzeCaught.forceNextCatch = true
    printLine("the next roll catches")
end
function developmentCommands.need(arguments)
    local need, value = (arguments or ""):match("^%s*(%a+)%s+(%d+)")
    local companion = AzeCaught.Active()
    if not companion or not companion[need or ""] or type(companion[need]) ~= "number" then printLine("need <hunger|thirst|affection|energy> <0-100>") return end
    companion[need] = addon.Utility.Clamp(tonumber(value), 0, 100)
    AzeCaught.Journal("INFORMATION", "dev.need", "a need was set by hand", { need = need, value = companion[need] })
    addon.Events.Fire("CAUGHT_CHANGED"); commands.state()
end
function developmentCommands.week()
    AzeCaught.State().paidWeek = nil
    local amount, reason = Catcher.RunPayout()
    printLine(("payout %d (%s)"):format(amount, tostring(reason or "paid")))
end
-- /ggd caught effect [throw|escape|snap] [unit]: plays an effect at the target (no throw) and prints which path it took
-- and why (debugging the effects)
function developmentCommands.effect(arguments)
    local first, second = (arguments or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local kind = (first == "escape" or first == "snap" or first == "throw") and first or "throw"
    local unit = (kind == first and second or first)
    unit = (unit and unit ~= "") and unit or "target"
    local details
    if kind == "throw" then
        Catcher.lastEffect = nil
        details = Catcher.PlayRopeEffect(unit)
    else
        details = Catcher.PlayFailEffect(kind, unit)
    end
    printLine("effect " .. kind .. ": " .. keyValues(details or {}))
end
-- /ggd caught hint: shows (or hides again) the first-throw arrow on every rope icon
function developmentCommands.hint()
    Catcher.forceHint = not Catcher.forceHint
    Catcher.hintPrinted = false
    printLine("first-throw arrow forced " .. (Catcher.forceHint and "on" or "off"))
    Catcher.RefreshIcons()
end

-- /ggd caught reset [all]: starts AZEcaught over (settings and journal stay; "all" also clears the wallet)
function developmentCommands.reset(arguments)
    local word = ((arguments or ""):match("^%s*(%S*)") or ""):lower()
    if word ~= "" and word ~= "all" then printLine("reset [all]") return end
    if addon.Store.db.readonly then printLine("the saved data is read-only: nothing was reset") return end
    local summary = AzeCaught.Reset(word == "all")
    Catcher.noted, Catcher.notedCount, Catcher.dumps = {}, 0, {}
    Catcher.fought, Catcher.foughtCount = {}, 0
    Catcher.pinged, Catcher.pingedCount, Catcher.hintPrinted = {}, 0, false
    printLine(("AZEcaught reset: %d found (%d caught) cleared%s%s; the next catch is guaranteed again, the arrow shows until the next throw"):format(
        summary.found, summary.caught, summary.companion and ", companion released" or "", summary.wallet and ", wallet cleared" or ""))
    addon.Events.Fire("CAUGHT_CHANGED"); Catcher.RefreshIcons()
end
-- user 2026-11-20 typed "/ggd reset" (not a command; the reset is /ggd caught reset): the dev build takes both
if addon.IS_DEVELOPMENT_BUILD then
    addon.SlashCommands.reset = function(arguments) addon.SlashCommands.caught("reset " .. (arguments or "")) end
end

-- /ggd caught dummy [off] (also /ggd arena dummy): a fake guild member with a companion in the Guild list, to test the
-- arena alone (user 2026-11-21). Memory only (Games.simulated: never stored, never sent; gone after a reload). It
-- accepts my challenges on the next arena tick (5 s).
function developmentCommands.dummy(arguments)
    local Arena = addon.Arena
    if ((arguments or ""):match("^%s*(%S*)") or ""):lower() == "off" then
        addon.Games.simulated[Arena.DUMMY_NAME] = nil
        printLine("the arena dummy is gone")
    else
        local companion = AzeCaught.Active()
        addon.Games.simulated[Arena.DUMMY_NAME] = Arena.DummyRecord(companion and Arena.Fighter(companion), now())
        printLine(Arena.DUMMY_NAME .. " joined the guild list (memory only): challenge it in AZEcaught > Guild, it accepts within 5 s")
    end
    AzeCaught.Journal("INFORMATION", "dev.dummy", "the arena dummy was changed", { on = addon.Games.simulated[Arena.DUMMY_NAME] ~= nil })
    addon.Events.Fire("GAMES_CHANGED"); addon.Events.Fire("CAUGHT_CHANGED")
end
-- /ggd caught request [gold] (also /ggd arena request): the dummy challenges me (it joins first if needed)
function developmentCommands.request(arguments)
    local Arena = addon.Arena
    if not addon.Games.simulated[Arena.DUMMY_NAME] then developmentCommands.dummy("") end
    local gold = tonumber((arguments or ""):match("(%d+)")) or 0
    local id = Arena.DummyChallenge(addon.Games.simulated[Arena.DUMMY_NAME], me(), gold * 10000, now())
    AzeCaught.Journal("INFORMATION", "dev.request", "the arena dummy challenged me", { id = id, wager = gold * 10000 })
    Catcher.ArenaTick(true)
    addon.Events.Fire("GAMES_CHANGED"); addon.Events.Fire("CAUGHT_CHANGED")
end

-- the Fights page's dev button (user 2026-11-21: "send a fake request to me from the arena dummy")
if addon.IS_DEVELOPMENT_BUILD then
    function Catcher.DevArenaRequest(gold) developmentCommands.request(tostring(gold or 0)) end
    -- the Fights page's stopwatch (user 2026-11-21: "reduce the timer there for the anticipated fight")
    function Catcher.DevArenaSkip() developmentCommands.skip() end
end

-- /ggd caught skip (also /ggd arena skip): the dummy's accepted fights are decided now (no 5 minute wait)
function developmentCommands.skip()
    local count = addon.Arena.SkipDummyWait(addon.Games.AllRecords(), me(), now())
    AzeCaught.Journal("INFORMATION", "dev.skip", "the dummy fights' waiting time was cut short", { fights = count })
    printLine(count > 0 and ("%d dummy fight(s) decided now"):format(count) or "no accepted fight with the arena dummy is waiting")
    Catcher.ArenaTick(true)
    addon.Events.Fire("CAUGHT_CHANGED")
end

-- adds the current target (or a test NPC) as caught, without a roll
function developmentCommands.add()
    local snapshot = Api.UnitSnapshot("target")
    local npcInformation = snapshot and snapshot.npc and { npc = snapshot.npc, name = snapshot.name, level = snapshot.level,
        classification = snapshot.classification, display = Catcher.CaptureDisplay("target"), stats = Api.UnitStats("target") }
        or { npc = 299, name = "Young Wolf", level = 2, classification = "normal" }
    local entry = AzeCaught.NoteFound(npcInformation, now())
    if entry then
        entry.caught = entry.caught + 1
        AzeCaught.Journal("INFORMATION", "dev.add", "an NPC was added as caught by hand", { npc = npcInformation.npc, name = entry.n })
        if snapshot and snapshot.npc then
            AzeCaught.Journal("INFORMATION", "catch.dump", "everything the client told about the caught NPC (dev add)", Api.UnitDump("target"))
        end
        printLine("added " .. entry.n .. " (" .. npcInformation.npc .. ")")
    end
    addon.Events.Fire("CAUGHT_CHANGED")
end

addon.SlashCommands.caught = function(arguments)
    local word, rest = (arguments or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    AzeCaught.Journal("DEBUG", "command", "a command was typed", { command = word ~= "" and word or "(open)", arguments = rest })
    if word == "" then
        if not addon.UI.IsShown() then addon.UI.Toggle() end
        if addon.GamesTab.SelectGame then addon.GamesTab.SelectGame("caught") end
        return
    end
    local handler = commands[word] or (addon.IS_DEVELOPMENT_BUILD and developmentCommands[word])
    if handler then handler(rest) return end
    local words = addon.Utility.SortedKeys(commands)
    if addon.IS_DEVELOPMENT_BUILD then for _, name in ipairs(addon.Utility.SortedKeys(developmentCommands)) do words[#words + 1] = name end end
    printLine(addon.SLASH_COMMANDS[1] .. " caught [" .. table.concat(words, "|") .. "]")
end

-- /gg caught arena: opens the arena view (feature 020); the dev build also takes "dummy [off]" and "request [gold]"
function commands.arena(arguments)
    local word, rest = (arguments or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if addon.IS_DEVELOPMENT_BUILD and (word == "dummy" or word == "request" or word == "skip") then developmentCommands[word](rest) return end
    if not addon.UI.IsShown() then addon.UI.Toggle() end
    if addon.GamesTab.SelectGame then addon.GamesTab.SelectGame("caught") end
    addon.AzeCaughtPanel.SelectView("arena")
end
addon.SlashCommands.arena = function(arguments) commands.arena(arguments) end

-- /gg caught icon [on|off|x <n>|y <n>|size <n>|reset] (user 2026-11-20)
function commands.icon(arguments) addon.AzeCaughtOptions.Command(arguments) end

-- /gg catch [mouseover]: the throw for macros (/target X then /gg catch)
addon.SlashCommands.catch = function(arguments)
    local unit = ((arguments or ""):match("^%s*(%S*)") or ""):lower()
    Catcher.Throw((unit == "mouseover" or unit == "focus") and unit or "target")
end

-- /gg notify on|off (R14)
addon.SlashCommands.notify = function(arguments) commands.notify(arguments) end
