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
local ROPE_SEGMENTS = 16
local ROPE_FLIGHT = 0.35            -- seconds from the player to the target
local HOSTILE_FLAG = 0x40          -- COMBATLOG_OBJECT_REACTION_HOSTILE
local PUBLISH_MINIMUM_GAP = 30     -- seconds between published updates of my companion
local PUBLISH_EVERY = 300          -- and at least this often while a companion is active
local MAXIMUM_NOTED = 500

Catcher.unitByGuid = {}     -- nameplate unit token by GUID
Catcher.icons = {}          -- rope icon button by unit token
Catcher.noted = {}          -- GUIDs whose unit details were read (cleared when it grows past MAXIMUM_NOTED)
Catcher.notedCount = 0
Catcher.lastClock = nil
Catcher.lastPublish = -math.huge
Catcher.dirty = false
Catcher.week = nil
Catcher.anchorFailures = 0
Catcher.lastZones = {}
Catcher.started = false
Catcher.dumps = {}          -- full unit dumps taken at the throw, by GUID (logged on a catch; the dead unit is often gone)

local function me() return addon.Utility.Me() end
local function now() return addon.Utility.Now() end
local function money(copper) return addon.Model.MoneyText(copper) end
local function chat(message) addon.Print(message) end

------------------------------------------------------------------ display capture (spike S1)

local captureModel
-- The CreatureDisplayInfo id of a unit, read through a hidden model (PlayerModel:SetUnit + GetDisplayInfo), or nil.
---@param unit string
---@return integer|nil
function Catcher.CaptureDisplay(unit)
    local ok, displayId = pcall(function()
        if not captureModel then
            captureModel = CreateFrame("PlayerModel", nil, UIParent)
            captureModel:SetSize(1, 1); captureModel:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10)
        end
        captureModel:SetUnit(unit)
        return captureModel.GetDisplayInfo and captureModel:GetDisplayInfo() or nil
    end)
    local valid = ok and addon.Utility.SafeInteger(displayId, 1, AzeCaught.MAXIMUM_ID) or nil
    AzeCaught.Journal("DEBUG", "found.display", valid and "a display id was read" or "no display id could be read",
        { unit = unit, display = tostring(displayId), ok = ok, api = captureModel and captureModel.GetDisplayInfo ~= nil })
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
    if Catcher.noted[snapshot.guid] then return snapshot end
    if snapshot.name and snapshot.level then   -- complete: no need to read this GUID again
        Catcher.notedCount = Catcher.notedCount + 1
        if Catcher.notedCount > MAXIMUM_NOTED then Catcher.noted, Catcher.notedCount = {}, 1 end
        Catcher.noted[snapshot.guid] = true
    end
    local entry = AzeCaught.State().collection[snapshot.npc]
    local display = (not entry or entry.disp == 0) and Catcher.CaptureDisplay(unit) or nil
    AzeCaught.NoteFound({ npc = snapshot.npc, name = snapshot.name, level = snapshot.level,
        classification = snapshot.classification, display = display, stats = Api.UnitStats(unit) }, now())
    return snapshot
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
-- window ended without a seen death is journaled once (in-game evidence for "why was nothing rolled").
function Catcher.PollThrows()
    pollRunning = false
    local clock = Api.Clock()
    local any = false
    for guid, throw in pairs(AzeCaught.throws) do
        local age = clock - throw.at
        if age <= AzeCaught.CATCH_WINDOW + 1 then
            any = true
            local unit = Catcher.UnitFor(guid)
            if unit then Catcher.CheckDeath(unit) end
        elseif not throw.reported then
            throw.reported = true
            AzeCaught.Journal("INFORMATION", "death.notSeen", "no death was seen inside the catch window",
                { guid = guid, npc = throw.npc, unitVisible = Catcher.UnitFor(guid) ~= nil })
        end
    end
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
    if reason == "full" then
        return Format(Text["Your caught list is full ({max}). A companion that dies or runs away frees a place."],
            { max = AzeCaught.MAXIMUM_CAUGHT })
    end
    return Text["Only NPCs can be caught."]
end

-- Throws the rope at `unit` (default target). Feedback in chat; every outcome is in the journal.
---@param unit? string
---@return boolean thrown
function Catcher.Throw(unit)
    unit = unit or "target"
    local snapshot = Api.UnitSnapshot(unit)
    if not snapshot then
        chat(Text["No target to throw the rope at."])
        AzeCaught.Journal("DEBUG", "throw.refused", "a throw was refused", { reason = "nounit", unit = unit })
        return false
    end
    if snapshot.hostile == false then
        chat(Text["Only hostile NPCs can be caught."])
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
        chat(Format(Text["Rope thrown at {name}: kill it within {seconds} seconds!"], { name = name, seconds = AzeCaught.CATCH_WINDOW }))
        Api.PlaySound(Api.SoundKitFor({ "IG_ABILITY_ICON_DROP", "IG_MAINMENU_OPTION_CHECKBOX_ON" }))
    elseif reason == "health" then
        chat(Format(Text["{name} is not weak enough yet (at most {percent}% health)."],
            { name = name, percent = math.floor(AzeCaught.THROW_HEALTH * 100) }))
    else
        chat(throwRefusalText(reason))
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
        chat("|cff66ff66" .. Format(Text["You caught {name}! (+{gold})"], { name = npcName, gold = money(result.reward) }) .. "|r"
            .. (result.first and (" " .. Text["(Your first catch always succeeds.)"]) or ""))
        Api.PlaySound(Api.SoundKitFor({ "UI_EPICLOOT_TOAST", "LOOTWINDOWCOINSOUND", "IG_QUEST_LIST_COMPLETE" }))
        addon.Events.Fire("CAUGHT_CHANGED")
    elseif result then
        chat(Format(Text["{name} slipped out of the rope ({percent}% chance)."],
            { name = npcName, percent = ("%.1f"):format(result.chance * 100) }))
    elseif reason == "late" then
        chat(Format(Text["{name} died too late for the rope."], { name = npcName }))
    end
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

-- the key binding and its labels (Options > Key Bindings > AddOns)
_G.GuildGamesAzeCaughtThrow = function() addon.Log.Protected("caught.throw", "the throw binding failed", Catcher.Throw, "target") end
_G.BINDING_HEADER_GUILDGAMES = "GuildGames"
_G.BINDING_NAME_AZECAUGHT_THROW = Text["AZEcaught: throw rope at target"]

------------------------------------------------------------------ rope icon on nameplates (spike S3)

---@param unit string
---@return table button
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
    -- the glow: grows and turns from red to green as the catch chance rises (user 2026-11-20)
    local glow = button:CreateTexture(nil, "BACKGROUND", nil, -1); glow:SetPoint("CENTER")
    glow:SetColorTexture(1, 1, 1, 1)
    pcall(glow.SetBlendMode, glow, "ADD")
    round(glow)
    button.glow = glow
    local border = button:CreateTexture(nil, "BACKGROUND"); border:SetPoint("TOPLEFT", -3, 3); border:SetPoint("BOTTOMRIGHT", 3, -3)
    border:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    round(border)
    button.border = border
    local texture = button:CreateTexture(nil, "ARTWORK"); texture:SetAllPoints(); texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if texture:SetTexture(ROPE_ICON) == false then texture:SetTexture(ROPE_FALLBACK) end
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
        GameTooltip:AddLine(Format(Text["Kill it within {seconds} seconds for a chance to catch it."], { seconds = AzeCaught.CATCH_WINDOW }), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    Catcher.icons[unit] = button
    return button
end

------------------------------------------------------------------ throw effect: a rope flying from the player to the target

local effect   -- { frame, segments, head, anchor } built on first use

-- Addons cannot place effects in the 3D world, and this client hides where nameplates are (restricted regions:
-- measuring one taints the addon, anchoring a line to one is refused - journal 2026-11-20). So the throw is drawn on the
-- screen between two PROJECTED points (user 2026-11-20: "trigonometrically calculated and scale accordingly like its
-- getting distance"): the player's body and the target's body, placed by AzeCaught.ProjectToScreen from the camera zoom
-- and the target's distance and bearing (Api.ThrowGeometry). A farther target lands higher and everything at it is
-- smaller. No nameplate is read or anchored to. Journaled as `throw.effect` with every input.
---@param unit string the target unit
---@return table|nil details what was played (also Catcher.lastEffect)
function Catcher.PlayRopeEffect(unit)
    local ok, problem = pcall(function()
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local geometry = Api.ThrowGeometry(unit)
        local view = { width = width, height = height, zoom = geometry.zoom }
        local fromX, fromY = AzeCaught.ProjectToScreen(view, 0, 0)
        local toX, toY, scale = AzeCaught.ProjectToScreen(view, geometry.distance, geometry.bearing)
        scale = math.max(0.3, math.min(1.5, scale))
        if not effect then
            local frame = CreateFrame("Frame", nil, UIParent)
            frame:SetAllPoints(UIParent); frame:SetFrameStrata("HIGH"); frame:EnableMouse(false)
            local segments = {}
            for index = 1, ROPE_SEGMENTS do
                local segment = frame:CreateTexture(nil, "ARTWORK")
                segment:SetColorTexture(ROPE_COLOR[1], ROPE_COLOR[2], ROPE_COLOR[3], 1)
                segment:Hide()
                segments[index] = segment
            end
            local head = frame:CreateTexture(nil, "OVERLAY")
            if head:SetTexture(addon.Animate.SPARKLE_TEXTURE) == false then head:SetColorTexture(1, 0.9, 0.5, 1) end
            pcall(head.SetBlendMode, head, "ADD")
            head:SetSize(22, 22); head:Hide()
            local anchor = CreateFrame("Frame", nil, frame); anchor:SetSize(1, 1)
            effect = { frame = frame, segments = segments, head = head, anchor = anchor }
        end
        local Animate = addon.Animate
        local distance = math.sqrt((toX - fromX) ^ 2 + (toY - fromY) ^ 2)
        local lift = 30 + distance * 0.25
        -- the size at t (0 player .. 1 target): the player's body is 1, the target's `scale`
        local function sizeAt(t) return 1 + (scale - 1) * t end
        local function place(region, t)
            local x, y = Animate.ArcPoint(fromX, fromY, toX, toY, lift, t)
            region:ClearAllPoints(); region:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end
        effect.anchor:ClearAllPoints(); effect.anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", toX, toY)
        Animate.Tween("ropeThrow", ROPE_FLIGHT + 0.15, function(elapsed)
            local progress = math.min(1, elapsed / ROPE_FLIGHT)
            local fade = 1 - math.max(0, (elapsed - ROPE_FLIGHT) / 0.15)
            place(effect.head, progress)
            effect.head:SetSize(22 * sizeAt(progress), 22 * sizeAt(progress))
            effect.head:SetAlpha(fade); effect.head:Show()
            for index, segment in ipairs(effect.segments) do
                -- the rope trails behind the tip, thins with distance and fades out after it lands
                local t = progress * (1 - (index - 1) / ROPE_SEGMENTS)
                place(segment, t)
                local size = (5 - 2 * (index - 1) / ROPE_SEGMENTS) * sizeAt(t)
                segment:SetSize(size, size)
                segment:SetAlpha(0.9 * fade)
                segment:Show()
            end
        end, function()
            effect.head:Hide()
            for _, segment in ipairs(effect.segments) do segment:Hide() end
            Animate.Burst("ropeHit", effect.frame, effect.anchor, 0, 0,
                { count = 16, color = { 1, 0.8, 0.35 }, speed = 110 * scale, gravity = 220 * scale, size = 14 * scale, duration = 0.7 })
            Animate.Ring("ropeHit", effect.frame, effect.anchor, 10 * scale, 80 * scale, { 1, 0.85, 0.3 }, 0.45)
        end)
        local details = { unit = unit, mode = "projected", source = geometry.source, why = geometry.why,
            distance = ("%.1f"):format(geometry.distance), bearing = math.floor(math.deg(geometry.bearing) + 0.5),
            zoom = geometry.zoom and ("%.1f"):format(geometry.zoom) or "default",
            from = math.floor(fromX) .. "," .. math.floor(fromY), to = math.floor(toX) .. "," .. math.floor(toY),
            scale = ("%.2f"):format(scale) }
        Catcher.lastEffect = details
        AzeCaught.Journal("DEBUG", "throw.effect", "the throw effect was played", details)
        -- dev build: the inputs are said at once, to tune the camera model without a /reload
        if addon.IS_DEVELOPMENT_BUILD then
            chat(("rope effect: %s yd (%s), bearing %s, zoom %s -> %s, size x%s"):format(details.distance, details.source,
                tostring(details.bearing), details.zoom, details.to, details.scale))
        end
    end)
    if not ok then
        Catcher.lastEffect = { mode = "failed", error = tostring(problem), unit = unit }
        AzeCaught.Journal("WARNING", "throw.effect", "the throw effect failed", { error = tostring(problem) })
    end
    return Catcher.lastEffect
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
    local show = settings.shown and plate and snapshot and snapshot.npc and snapshot.hostile ~= false and snapshot.dead ~= true
        and weakEnough and not AzeCaught.rolled[snapshot.guid]
    if not show then
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
    end)
    if not ok then
        Catcher.anchorFailures = Catcher.anchorFailures + 1
        if Catcher.anchorFailures == 1 then
            AzeCaught.Journal("WARNING", "icon.anchor", "the rope icon could not be attached to a nameplate", { error = tostring(problem) })
        end
        button:Hide()
        return
    end
    local armed = AzeCaught.throws[snapshot.guid] ~= nil
    if armed then button.border:SetColorTexture(1, 0.82, 0.2, 0.95) else button.border:SetColorTexture(0.05, 0.05, 0.05, 0.9) end
    local quality = AzeCaught.ThrowQuality(snapshot.health)
    local r, g, b = AzeCaught.QualityColor(quality)
    local glowSize = settings.size + 8 + 14 * (quality or 0.4)
    button.glow:SetSize(glowSize, glowSize)
    button.glow:SetVertexColor(r, g, b, 1)
    button.glow:SetAlpha(0.45 + 0.45 * (quality or 0.4))
    button:Show()
end

function Catcher.RefreshIcons()
    for unit in pairs(Catcher.icons) do Catcher.UpdateIcon(unit) end
    for _, unit in pairs(Catcher.unitByGuid) do Catcher.UpdateIcon(unit) end
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
            chat(Format(needText(need), { name = addon.Utility.ChatSafe(companion.n) })
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

function Catcher.RunPayout()
    local amount, reason, rank = AzeCaught.WeeklyPayout(me(), addon.Store.db.games, now())
    if amount > 0 then
        chat(Format(Text["Weekly AZEcaught payout: place {rank}, {gold} added to your pool."], { rank = rank, gold = money(amount) }))
        addon.Events.Fire("CAUGHT_CHANGED")
    end
    return amount, reason
end

function Catcher.OnTick()
    local clock = Api.Clock()
    local dt = Catcher.lastClock and (clock - Catcher.lastClock) or 0
    Catcher.lastClock = clock
    local serverNow = now()
    local before = AzeCaught.Active()
    local result = AzeCaught.Tick(dt, serverNow)
    AzeCaught.ExpireThrows(clock)
    for guid, stored in pairs(Catcher.dumps) do
        if clock - stored.at > 60 then Catcher.dumps[guid] = nil end
    end
    local companion = AzeCaught.Active()
    if result.died and before then
        chat("|cffff4040" .. Format(Text["{name} died: it was left hungry or thirsty for too long."],
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
    local breakdown = AzeCaught.Chance(snapshot.health, snapshot.classification, snapshot.level or 1, Api.PlayerLevel())
    printLine(("chance %.2f%% = base %.2f x health %.3f (hp %.1f%%) x rarity %.2f (%s) x level %.2f (npc %s vs %d)%s; icon %s; rolled %s"):format(
        breakdown.chance * 100, breakdown.base, breakdown.healthFactor, snapshot.health * 100, breakdown.rarityFactor,
        tostring(snapshot.classification), breakdown.levelFactor, tostring(snapshot.level), Api.PlayerLevel(),
        breakdown.capped and " (capped)" or "", snapshot.health <= AzeCaught.THROW_HEALTH and "yes" or "no",
        tostring(AzeCaught.rolled[snapshot.guid] ~= nil)))
end

function commands.collection()
    local caughtCount, newest = 0, {}
    for npcId, entry in pairs(AzeCaught.State().collection) do
        if entry.caught > 0 then caughtCount = caughtCount + 1 end
        newest[#newest + 1] = { npc = npcId, entry = entry }
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

-- Spikes S1-S3: what this client can do (results also go to the journal).
function commands.probe()
    local s1 = Api.UnitSnapshot("target")
    local display = s1 and s1.npc and Catcher.CaptureDisplay("target")
    local result1 = s1 and s1.npc and ("display " .. tostring(display)) or "target an NPC first"
    local panelModel = addon.AzeCaughtPanel and addon.AzeCaughtPanel.widgets.model
    local animations = {}
    if panelModel and panelModel.HasAnimation then
        for _, animationId in ipairs({ 0, 4, 5, 26, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 100, 101, 102, 103, 113, 114 }) do
            local ok, has = pcall(panelModel.HasAnimation, panelModel, animationId)
            if ok and has then animations[#animations + 1] = animationId end
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
    companion[need] = math.max(0, math.min(100, tonumber(value)))
    AzeCaught.Journal("INFORMATION", "dev.need", "a need was set by hand", { need = need, value = companion[need] })
    addon.Events.Fire("CAUGHT_CHANGED"); commands.state()
end
function developmentCommands.week()
    AzeCaught.State().paidWeek = nil
    local amount, reason = Catcher.RunPayout()
    printLine(("payout %d (%s)"):format(amount, tostring(reason or "paid")))
end
-- plays the throw effect at the target (no throw) and prints which path it took and why (debugging the effect)
function developmentCommands.effect(arguments)
    local unit = ((arguments or ""):match("^%s*(%S+)") or "target"):lower()
    Catcher.lastEffect = nil
    local details = Catcher.PlayRopeEffect(unit) or {}
    printLine("effect: " .. keyValues(details))
end

-- /ggd caught reset [all]: starts AZEcaught over (settings and journal stay; "all" also clears the wallet)
function developmentCommands.reset(arguments)
    local word = ((arguments or ""):match("^%s*(%S*)") or ""):lower()
    if word ~= "" and word ~= "all" then printLine("reset [all]") return end
    if addon.Store.db.readonly then printLine("the saved data is read-only: nothing was reset") return end
    local summary = AzeCaught.Reset(word == "all")
    Catcher.noted, Catcher.notedCount, Catcher.dumps = {}, 0, {}
    printLine(("AZEcaught reset: %d found (%d caught) cleared%s%s"):format(summary.found, summary.caught,
        summary.companion and ", companion released" or "", summary.wallet and ", wallet cleared" or ""))
    addon.Events.Fire("CAUGHT_CHANGED"); Catcher.RefreshIcons()
end

-- adds the current target (or a test NPC) as caught, without a roll
function developmentCommands.add()
    local snapshot = Api.UnitSnapshot("target")
    local info = snapshot and snapshot.npc and { npc = snapshot.npc, name = snapshot.name, level = snapshot.level,
        classification = snapshot.classification, display = Catcher.CaptureDisplay("target"), stats = Api.UnitStats("target") }
        or { npc = 299, name = "Young Wolf", level = 2, classification = "normal" }
    if AzeCaught.CaughtCount() >= AzeCaught.MAXIMUM_CAUGHT then
        printLine(("the caught list is full (%d)"):format(AzeCaught.MAXIMUM_CAUGHT))
        return
    end
    local entry = AzeCaught.NoteFound(info, now())
    if entry then
        entry.caught = entry.caught + 1
        AzeCaught.Journal("INFORMATION", "dev.add", "an NPC was added as caught by hand", { npc = info.npc, name = entry.n })
        if snapshot and snapshot.npc then
            AzeCaught.Journal("INFORMATION", "catch.dump", "everything the client told about the caught NPC (dev add)", Api.UnitDump("target"))
        end
        printLine("added " .. entry.n .. " (" .. info.npc .. ")")
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

-- /gg caught icon [on|off|x <n>|y <n>|size <n>|reset] (user 2026-11-20)
function commands.icon(arguments) addon.AzeCaughtOptions.Command(arguments) end

-- /gg catch [mouseover]: the throw for macros (/target X then /gg catch)
addon.SlashCommands.catch = function(arguments)
    local unit = ((arguments or ""):match("^%s*(%S*)") or ""):lower()
    Catcher.Throw((unit == "mouseover" or unit == "focus") and unit or "target")
end

-- /gg notify on|off (R14)
addon.SlashCommands.notify = function(arguments) commands.notify(arguments) end
