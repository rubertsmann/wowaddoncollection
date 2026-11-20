local addonName, addon = ...

-- Survivor panel (third game). Rules and simulation: Core/Minigames/Survivor.lua. Everything here is presentation:
--   arena (an almost clear overlay): the tower in the middle with its health bar and a glow, monsters drawn from a pool,
--     bolts with a short trail, the cleave as a sword sweeping round the tower plus a shockwave, the nova as a frost ring,
--     death puffs, a red flash when the tower is hurt
--   HUD: timer against the bet target, a progress line, experience bar, level, the owned items with their levels
--   level-up: three item cards over the arena (the run is paused until one is picked)
--   end: survived = burst, ring, glow and the payout floating up; fallen = shake, red text
-- The stake is booked as pending when the run starts (Survivor.Begin) and settled when it ends (Survivor.Settle).
-- While a run is open the game switch is locked (GamesTab.IsBusy). Closing the window pauses the run (no OnUpdate).
---@class SurvivorArenaModule
local SurvivorArena = {}
addon.SurvivorArena = SurvivorArena

local Text, Format = addon.Text, addon.Locale.Format

local ARENA_WIDTH, ARENA_HEIGHT = 290, 200
local TOWER_SIZE = 30
local DEFAULT_STAKE = 10000        -- copper (1g)
local DEFAULT_TARGET = 1
local PUFF_COUNT = 24
local BLAST_COUNT = 16
local ZAP_SEGMENTS = 32
local ZAP_SECONDS, BLAST_SECONDS = 0.22, 0.35
-- projectiles drawn as their (spinning or pointed) item icon; every other projectile is a glowing spark in its colour
local ICON_PROJECTILES = { arrows = "point", knives = "point", axe = "spin" }
local MAXIMUM_DRAWN_ENEMIES = 120
local SWORD_TEXTURE = "Interface\\Icons\\INV_Sword_04"
local CARD_WIDTH, CARD_HEIGHT = 88, 104

---@class SurvivorArenaState
---@field run SurvivorRun|nil the open run
---@field targetIndex integer the selected bet target
---@field lastRun SurvivorRun|nil
SurvivorArena.state = { run = nil, targetIndex = DEFAULT_TARGET, lastRun = nil }

---@type table widgets (nil fields until Build ran)
local widgets = {}
SurvivorArena.widgets = widgets

---@param soundNames string[]
local function play(soundNames)
    local soundKit = SOUNDKIT and addon.Api.SoundKitFor and addon.Api.SoundKitFor(soundNames) or nil
    addon.Api.PlaySound(soundKit)
end

-- 75 -> "1:15"
---@param seconds number
---@return string
local function clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end
SurvivorArena.Clock = clock

---@param frame table
---@return integer
local function frameLevel(frame) return tonumber(frame:GetFrameLevel()) or 1 end

---@param texture table
---@param path string
---@param color number[]
local function iconOr(texture, path, color)
    if texture:SetTexture(path) == false then texture:SetColorTexture(color[1], color[2], color[3], 1) end
end

------------------------------------------------------------------ item names (localized here, rules in Core)

---@type table<string, { name: string, description: string }>
local ITEM_TEXT = {
    bolt = { name = Text["Fire bolt"], description = Text["Shoots the nearest monster. Levels add damage, speed and more bolts."] },
    cleave = { name = Text["Cleave"], description = Text["Hits every monster next to the tower and pushes it back."] },
    nova = { name = Text["Frost nova"], description = Text["Damages and slows every monster around the tower."] },
    might = { name = Text["Might"], description = Text["+20% damage for every weapon."] },
    haste = { name = Text["Haste"], description = Text["Weapons recharge 12% faster."] },
    armor = { name = Text["Armor"], description = Text["The tower takes 15% less damage."] },
    vitality = { name = Text["Vitality"], description = Text["+25 maximum health and heals 25."] },
    regen = { name = Text["Regeneration"], description = Text["The tower heals 0.8 health per second."] },
    arcane = { name = Text["Arcane missiles"], description = Text["A fan of missiles that seek out monsters."] },
    shadow = { name = Text["Shadow bolt"], description = Text["A slow, heavy bolt that passes through several monsters."] },
    arrows = { name = Text["Multi-shot"], description = Text["A volley of arrows in a fan. Levels add arrows."] },
    lightning = { name = Text["Chain lightning"], description = Text["Strikes the nearest monster and jumps to the next ones."] },
    fireball = { name = Text["Fireball"], description = Text["Explodes on impact and burns everything nearby."] },
    icelance = { name = Text["Ice lance"], description = Text["A fast lance that pierces and slows."] },
    smite = { name = Text["Smite"], description = Text["Holy light strikes random monsters from above."] },
    knives = { name = Text["Throwing knives"], description = Text["Knives fly out in a turning spiral, very fast."] },
    axe = { name = Text["Throwing axe"], description = Text["Flies out, hits everything in its way and comes back."] },
    starfall = { name = Text["Starfall"], description = Text["Stars rain down on many monsters at once."] },
    volley = { name = Text["Volley"], description = Text["+1 projectile for every projectile weapon."] },
    pierce = { name = Text["Penetration"], description = Text["Projectiles pass through one more monster."] },
    reach = { name = Text["Reach"], description = Text["+15% area for cleave, nova, explosions and strikes."] },
    thorns = { name = Text["Thorns"], description = Text["Monsters touching the tower take 5 damage per second."] },
    deflect = { name = Text["Deflect"], description = Text["Turns 10% of the damage away and hits the attacker with 3x of it."] },
    barrier = { name = Text["Barrier"], description = Text["A shield of 15 that takes hits first and refills after 3 seconds."] },
    leech = { name = Text["Leech"], description = Text["Every kill heals the tower by 0.6."] },
}
SurvivorArena.ITEM_TEXT = ITEM_TEXT

------------------------------------------------------------------ pools

-- texture `index` of a pool on `layer`, created on first use (an icon masked to a circle when `round`)
---@param poolTable table[]
---@param layer table
---@param index integer
---@param round boolean
---@return table texture
local function pooled(poolTable, layer, index, round)
    local texture = poolTable[index]
    if not texture then
        texture = layer:CreateTexture(nil, "ARTWORK")
        if round then addon.GamesTab.MaskCircle(layer, texture) end
        poolTable[index] = texture
    end
    return texture
end

---@param poolTable table[]
---@param fromIndex integer
local function hideFrom(poolTable, fromIndex)
    for index = fromIndex, #poolTable do poolTable[index]:Hide() end
end

------------------------------------------------------------------ drawing a run

---@param texture table
---@param x number arena coordinates (tower at 0, 0; y up)
---@param y number
---@param size number
local function place(texture, x, y, size)
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", widgets.arena, "CENTER", x, y)
    texture:SetSize(size, size)
end

---@param run SurvivorRun
local function drawEnemies(run)
    local drawn = 0
    for _, enemy in ipairs(run.enemies) do
        if drawn >= MAXIMUM_DRAWN_ENEMIES then break end
        drawn = drawn + 1
        local texture = pooled(widgets.enemyPool, widgets.actors, drawn, true)
        local kind = addon.Survivor.ENEMY_BY_KEY[enemy.kind]
        if texture.kindKey ~= enemy.kind then
            texture.kindKey = enemy.kind
            iconOr(texture, kind.icon, kind.color)
            texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        place(texture, enemy.x, enemy.y, enemy.radius * 2 + 4)
        if enemy.flash > 0 then texture:SetVertexColor(1, 0.4, 0.4)
        elseif enemy.slow > 0 then texture:SetVertexColor(0.55, 0.8, 1)
        else texture:SetVertexColor(1, 1, 1) end
        texture:SetAlpha(1)
        texture:Show()
    end
    hideFrom(widgets.enemyPool, drawn + 1)
end

-- sets a pooled projectile texture up for `weapon` (only when it changes)
---@param texture table
---@param weapon string
local function styleProjectile(texture, weapon)
    if texture.weapon == weapon then return end
    texture.weapon = weapon
    local item = addon.Survivor.ITEM_BY_KEY[weapon]
    if ICON_PROJECTILES[weapon] then
        iconOr(texture, item.icon, item.color)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pcall(texture.SetBlendMode, texture, "BLEND")
        texture:SetVertexColor(1, 1, 1)
    else
        texture:SetTexture(addon.Animate.SPARKLE_TEXTURE)
        texture:SetTexCoord(0, 1, 0, 1)
        pcall(texture.SetBlendMode, texture, "ADD")
        texture:SetVertexColor(item.color[1], item.color[2], item.color[3])
    end
end

---@param run SurvivorRun
local function drawProjectiles(run)
    local drawn = 0
    for _, projectile in ipairs(run.projectiles) do
        local spec = addon.Survivor.RANGED[projectile.weapon] or {}
        local size, style = spec.size or 12, ICON_PROJECTILES[projectile.weapon]
        for ghost = 0, style and 0 or 1 do   -- sparks leave one fainter ghost behind
            drawn = drawn + 1
            local texture = pooled(widgets.boltPool, widgets.actors, drawn, false)
            styleProjectile(texture, projectile.weapon)
            local back = ghost * 0.035
            place(texture, projectile.x - projectile.vx * back, projectile.y - projectile.vy * back, ghost == 0 and size or size * 0.65)
            if style == "spin" then
                pcall(texture.SetRotation, texture, (projectile.maxLife - projectile.life) * 14)
            elseif style == "point" then
                pcall(texture.SetRotation, texture, math.atan2(projectile.vy, projectile.vx) - math.pi / 4)
            end
            texture:SetAlpha(ghost == 0 and 1 or 0.45)
            texture:Show()
        end
    end
    hideFrom(widgets.boltPool, drawn + 1)
end

---@param run SurvivorRun
local function drawHud(run)
    local share = math.max(0, math.min(1, run.hp / run.maxHp))
    widgets.hpFill:SetWidth(math.max(1, 44 * share))
    widgets.hpFill:SetColorTexture(1 - share, 0.35 + 0.6 * share, 0.25, 1)
    if run.target.endless then
        -- endless: the time, the payout reached so far, and the line fills towards the next minute
        local factor = addon.Survivor.EndlessFactor(run.time)
        widgets.timerText:SetText(clock(run.time) .. (factor > 0 and ("  |cffffd200" .. Format(Text["x{n}"], { n = factor }) .. "|r") or ""))
        local minute = addon.Survivor.MILESTONE_SECONDS
        widgets.progressFill:SetWidth(math.max(1, ARENA_WIDTH * ((run.time % minute) / minute)))
    else
        widgets.timerText:SetText(clock(run.time) .. " / " .. clock(run.target.seconds))
        widgets.progressFill:SetWidth(math.max(1, ARENA_WIDTH * math.min(1, run.time / run.target.seconds)))
    end
    widgets.xpFill:SetWidth(math.max(1, ARENA_WIDTH * math.min(1, run.xp / run.xpNext)))
    widgets.levelText:SetText(Format(Text["Lv {n}"], { n = run.level }))
    -- owned items, in item order: weapons in the bottom row, passives in the row above
    local shown = { weapon = 0, passive = 0 }
    for _, item in ipairs(addon.Survivor.ITEMS) do
        local level = run.items[item.key] or 0
        if level > 0 then
            shown[item.kind] = shown[item.kind] + 1
            local slot = widgets.itemSlots[item.kind][shown[item.kind]]
            if slot.key ~= item.key then slot.key = item.key; iconOr(slot.icon, item.icon, item.color) end
            slot.levelText:SetText(tostring(level))
            slot:Show()
        end
    end
    for kind, slots in pairs(widgets.itemSlots) do
        for index = shown[kind] + 1, #slots do slots[index]:Hide() end
    end
    -- defenses: the barrier bubble shows how much shield is left, the thorns aura turns while owned
    local defense = addon.Survivor.DefenseStats(run)
    widgets.barrier:SetAlpha(defense.shield > 0 and 0.75 * run.shield / defense.shield or 0)
    widgets.thornsAura:SetShown((run.items.thorns or 0) > 0)
    pcall(widgets.thornsAura.SetRotation, widgets.thornsAura, run.time * 0.8)
end

------------------------------------------------------------------ effects

-- a puff of sparkles where a monster died (own pool: many deaths overlap, Animate.Burst would replace itself)
---@param x number
---@param y number
---@param color number[]
local function puff(x, y, color)
    widgets.puffIndex = widgets.puffIndex % PUFF_COUNT + 1
    local entry = widgets.puffs[widgets.puffIndex]
    entry.x, entry.y, entry.age, entry.spin = x, y, 0, (addon.Api.Random() - 0.5) * 10
    entry.texture:SetVertexColor(color[1], color[2], color[3])
    entry.texture:Show()
end

---@param elapsedSeconds number
local function updatePuffs(elapsedSeconds)
    for _, entry in ipairs(widgets.puffs) do
        if entry.age < 0.45 then
            entry.age = entry.age + elapsedSeconds
            local progress = math.min(1, entry.age / 0.45)
            place(entry.texture, entry.x, entry.y + 10 * progress, 10 + 26 * progress)
            entry.texture:SetAlpha(1 - progress)
            pcall(entry.texture.SetRotation, entry.texture, entry.spin * entry.age)
            if progress >= 1 then entry.texture:Hide() end
        end
    end
end

-- an expanding ring where a fireball exploded or a strike landed
---@param x number
---@param y number
---@param radius number
---@param color number[]
local function blastRing(x, y, radius, color)
    widgets.blastIndex = widgets.blastIndex % BLAST_COUNT + 1
    local entry = widgets.blasts[widgets.blastIndex]
    entry.x, entry.y, entry.radius, entry.age = x, y, radius, 0
    entry.texture:SetVertexColor(color[1], color[2], color[3])
    entry.texture:Show()
end

-- a jagged lightning line through `points` (each segment broken once at a random kink)
---@param points number[][]
---@param color number[]
local function zap(points, color)
    if not widgets.zapsSupported then
        for index = 2, #points do puff(points[index][1], points[index][2], color) end
        return
    end
    local random = addon.Api.Random
    for index = 2, #points do
        local fromX, fromY = points[index - 1][1], points[index - 1][2]
        local toX, toY = points[index][1], points[index][2]
        local kinkX = (fromX + toX) / 2 + (random() - 0.5) * 18
        local kinkY = (fromY + toY) / 2 + (random() - 0.5) * 18
        for _, segment in ipairs({ { fromX, fromY, kinkX, kinkY }, { kinkX, kinkY, toX, toY } }) do
            widgets.zapIndex = widgets.zapIndex % ZAP_SEGMENTS + 1
            local entry = widgets.zaps[widgets.zapIndex]
            entry.age = 0
            entry.line:SetStartPoint("CENTER", widgets.arena, segment[1], segment[2])
            entry.line:SetEndPoint("CENTER", widgets.arena, segment[3], segment[4])
            entry.line:SetColorTexture(color[1], color[2], color[3], 1)
            entry.line:Show()
        end
    end
end

---@param elapsedSeconds number
local function updateWeaponEffects(elapsedSeconds)
    for _, entry in ipairs(widgets.blasts) do
        if entry.age < BLAST_SECONDS then
            entry.age = entry.age + elapsedSeconds
            local progress = math.min(1, entry.age / BLAST_SECONDS)
            place(entry.texture, entry.x, entry.y, entry.radius * 2 * (0.4 + 0.9 * (1 - (1 - progress) ^ 2)))
            entry.texture:SetAlpha(0.9 * (1 - progress))
            if progress >= 1 then entry.texture:Hide() end
        end
    end
    for _, entry in ipairs(widgets.zaps) do
        if entry.age < ZAP_SECONDS then
            entry.age = entry.age + elapsedSeconds
            local progress = math.min(1, entry.age / ZAP_SECONDS)
            entry.line:SetAlpha(1 - progress)
            if progress >= 1 then entry.line:Hide() end
        end
    end
end

-- the sword sweeps once round the tower at the cleave's reach
---@param radius number
local function cleaveSwing(radius)
    local sword = widgets.sword
    addon.Animate.Tween("survivorCleave", 0.22, function(elapsed)
        local progress = elapsed / 0.22
        local angle = math.pi / 2 - 2 * math.pi * progress
        place(sword, math.cos(angle) * radius * 0.8, math.sin(angle) * radius * 0.8, 20)
        pcall(sword.SetRotation, sword, angle - math.pi / 4)
        sword:SetAlpha(1 - progress * 0.6)
        sword:Show()
    end, function() sword:Hide() end)
    addon.Animate.Ring("survivorCleave", widgets.effects, widgets.towerAnchor, 20, radius * 2.4, { 0.9, 0.9, 1 }, 0.3)
end

---@param event SurvivorEvent
local function handleEvent(event)
    local Animate = addon.Animate
    if event.kind == "blast" then
        local item = addon.Survivor.ITEM_BY_KEY[event.weapon]
        local color = item and item.color or { 1, 0.8, 0.3 }
        blastRing(event.x, event.y, event.radius, color)
        if event.weapon ~= "fireball" then puff(event.x, event.y, color) end   -- strikes flash where they land
    elseif event.kind == "zap" then
        local item = addon.Survivor.ITEM_BY_KEY[event.weapon]
        zap(event.points, item and item.color or { 0.6, 0.8, 1 })
    elseif event.kind == "kill" then
        local kind = addon.Survivor.ENEMY_BY_KEY[event.enemy]
        puff(event.x, event.y, kind and kind.color or { 1, 0.8, 0.3 })
    elseif event.kind == "cleave" then
        cleaveSwing(event.radius)
        play({ "IG_MAINMENU_OPTION_CHECKBOX_OFF" })
    elseif event.kind == "nova" then
        Animate.Ring("survivorNova", widgets.effects, widgets.towerAnchor, 20, event.radius * 2.6, { 0.45, 0.75, 1 }, 0.5)
    elseif event.kind == "shieldbreak" then
        Animate.Ring("survivorShield", widgets.effects, widgets.towerAnchor, TOWER_SIZE * 2, TOWER_SIZE * 4, { 0.4, 0.7, 1 }, 0.35)
        play({ "IG_MAINMENU_OPTION_CHECKBOX_OFF" })
    elseif event.kind == "hurt" then
        Animate.Flash("survivorHurt", widgets.hurtFlash, 0.22, 0.3)
        Animate.Pulse(widgets.tower, 0.9, 0.15)
    elseif event.kind == "milestone" then
        local label = Format(Text["x{n}"], { n = event.factor })
        Animate.Ring("survivorMilestone", widgets.effects, widgets.towerAnchor, 30, 300, { 1, 0.85, 0.3 }, 0.8)
        Animate.Burst("survivor", widgets.effects, widgets.towerAnchor, 0, 0, { count = 18, speed = 170, gravity = 200, size = 13 })
        Animate.FloatText("survivor", widgets.floatText, widgets.towerAnchor, 0, 24, label, { 1, 0.85, 0.3 })
        widgets.startButton:SetText(Text["Cash out"])
        play({ "LOOT_WINDOW_COIN_SOUND", "UI_EPICLOOT_TOAST" })
    elseif event.kind == "levelup" then
        Animate.Ring("survivorLevel", widgets.effects, widgets.towerAnchor, 30, 160, { 1, 0.85, 0.3 }, 0.6)
        play({ "LEVELUP", "UI_EPICLOOT_TOAST" })
    end
end

------------------------------------------------------------------ item cards

local function hideCards()
    for _, card in ipairs(widgets.cards) do card:Hide() end
    widgets.cardTitle:Hide()
end

---@param run SurvivorRun
local function showCards(run)
    local choices = run.choices
    local count = #choices
    local totalWidth = count * CARD_WIDTH + (count - 1) * 6
    for index, card in ipairs(widgets.cards) do
        local choice = choices[index]
        if choice then
            local item = addon.Survivor.ITEM_BY_KEY[choice.key]
            local texts = ITEM_TEXT[choice.key]
            iconOr(card.icon, item.icon, item.color)
            card.nameText:SetText(texts.name)
            card.levelText:SetText((run.items[choice.key] or 0) == 0 and Text["New!"] or Format(Text["Lv {n}"], { n = choice.level }))
            card.descriptionText:SetText(texts.description)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", widgets.arena, "CENTER", -totalWidth / 2 + (index - 1) * (CARD_WIDTH + 6), CARD_HEIGHT / 2 - 8)
            card:Show()
            addon.Animate.FadeIn(card, 0.15 + 0.06 * index)
        else
            card:Hide()
        end
    end
    widgets.cardTitle:Show()
    addon.Animate.FadeIn(widgets.cardTitle, 0.2)
end

------------------------------------------------------------------ controls

---@param running boolean
local function setControls(running)
    widgets.startButton:SetText(running and Text["Give up"] or Text["Start"])
    widgets.stake.SetEnabled(not running)
    for index, button in ipairs(widgets.targetButtons) do
        button:SetEnabled(not running and index ~= SurvivorArena.state.targetIndex)
        if button.SetSelected then button:SetSelected(index == SurvivorArena.state.targetIndex) end
    end
end

---@param target SurvivorTarget
local function showHint(target)
    if target.endless then
        widgets.hintText:SetText(Text["Endless: every minute doubles the payout (x2 at 1:00). Cash out any time."])
        widgets.timerText:SetText(clock(0))
    else
        widgets.hintText:SetText(Format(Text["Survive {time} to win {n}x your stake"], { time = clock(target.seconds), n = target.factor }))
        widgets.timerText:SetText(clock(0) .. " / " .. clock(target.seconds))
    end
end

---@param index integer
local function selectTarget(index)
    if SurvivorArena.state.run or not addon.Survivor.Target(index) then return end
    SurvivorArena.state.targetIndex = index
    addon.GamesTab.Settings().survivorTarget = index
    setControls(false)
    showHint(addon.Survivor.Target(index))
end

---@param run SurvivorRun
local function finish(run)
    local state = SurvivorArena.state
    local Animate = addon.Animate
    local money = addon.GamesTab.Money
    local net = addon.Survivor.Settle(run, addon.Utility.Now())
    state.run, state.lastRun = nil, run
    addon.Events.Fire("GAMES_CHANGED")   -- announce (coalesced HELLO)
    hideCards()
    addon.Log.Debug("games.survivor", "a survivor run ended", { result = run.finished, time = run.time, net = net })
    addon.Log.Protected("games.effects", "the survivor end effects failed", function()
        if net > 0 then
            widgets.resultText:SetText(Format(Text["You won {gold}"], { gold = money(net) }))
            widgets.resultText:SetTextColor(0.2, 1, 0.6)
            widgets.bannerText:SetText(run.target.endless and Format(Text["x{n}"], { n = addon.Survivor.EndlessFactor(run.time) })
                .. "  " .. clock(run.time) or Text["Survived!"])
            Animate.FadeIn(widgets.bannerText, 0.2); Animate.Pulse(widgets.bannerText, 1.4, 0.5)
            Animate.Glow(widgets.towerGlow, 4)
            Animate.Ring("survivorEnd", widgets.effects, widgets.towerAnchor, 40, 340, nil, 0.8)
            Animate.Burst("survivor", widgets.effects, widgets.towerAnchor, 0, 0, { count = 32, speed = 210, gravity = 230, size = 15 })
            Animate.FloatText("survivor", widgets.floatText, widgets.towerAnchor, 0, 24, "+" .. money(net), { 0.35, 1, 0.55 })
            play({ "UI_EPICLOOT_TOAST", "LOOT_WINDOW_COIN_SOUND" })
        else
            widgets.resultText:SetText(Format(Text["The tower fell after {time}. You lost {gold}"],
                { time = clock(run.time), gold = money(run.stake) }))
            widgets.resultText:SetTextColor(1, 0.33, 0.33)
            widgets.bannerText:SetText("")
            Animate.Shake(widgets.arena, 4, 5)
            Animate.Flash("survivorHurt", widgets.hurtFlash, 0.45, 0.7)
            Animate.FloatText("survivor", widgets.floatText, widgets.towerAnchor, 0, 24, "-" .. money(run.stake), { 1, 0.35, 0.3 }, -24, 1.3)
        end
        Animate.FadeIn(widgets.resultText, 0.3)
    end)
    setControls(false)
    showHint(run.target)
    addon.GamesTab.SetBusy(false)   -- the run is over: the leaderboard may show it now
end

-- One frame of an open run: simulate, react to what happened, draw.
---@param elapsedSeconds number
function SurvivorArena.Update(elapsedSeconds)
    local run = SurvivorArena.state.run
    if run then
        local hadChoices = run.choices ~= nil
        addon.Survivor.Advance(run, elapsedSeconds * addon.Animate.speed)
        for _, event in ipairs(addon.Survivor.TakeEvents(run)) do handleEvent(event) end
        drawEnemies(run); drawProjectiles(run); drawHud(run)
        if run.finished then
            finish(run)
        elseif run.choices and not hadChoices then
            showCards(run)
        end
    end
    if widgets.puffs then updatePuffs(elapsedSeconds * addon.Animate.speed) end
    if widgets.blasts then updateWeaponEffects(elapsedSeconds * addon.Animate.speed) end
end

-- A card was clicked: take the item, show the next offer or resume.
---@param index integer
function SurvivorArena.Choose(index)
    local run = SurvivorArena.state.run
    if not run or not addon.Survivor.Choose(run, index) then return end
    play({ "IG_MAINMENU_OPTION_CHECKBOX_ON" })
    addon.Animate.Pulse(widgets.tower, 1.25, 0.3)
    if run.choices then showCards(run) else hideCards() end
    drawHud(run)
end

-- The Start button: book the stake as pending and open a run; during a run the same button gives up (a loss).
---@return SurvivorRun|nil
function SurvivorArena.Start()
    local state = SurvivorArena.state
    if not widgets.startButton then return nil end
    if state.run then
        state.run.finished = "lost"
        finish(state.run)
        return nil
    end
    local stake = widgets.stake.Read()
    local run, refusal = addon.Survivor.Begin(addon.Utility.Me(), stake, state.targetIndex, addon.Utility.Now(), addon.Api.Random)
    if not run then
        widgets.resultText:SetText(addon.GamesTab.RefusalText(refusal)); widgets.resultText:SetTextColor(1, 0.33, 0.33)
        widgets.resultText:SetAlpha(1); widgets.resultText:Show()
        return nil
    end
    addon.GamesTab.Settings().lastSurvivorStakeCopper = stake
    state.run = run
    addon.GamesTab.SetBusy(true)
    widgets.resultText:SetText(""); widgets.bannerText:SetText(""); widgets.hintText:SetText("")
    addon.Animate.FinishTween("float:survivor")
    setControls(true)
    widgets.towerGlow:SetAlpha(0)
    addon.Animate.Ring("survivorStart", widgets.effects, widgets.towerAnchor, 10, 200, { 1, 0.85, 0.3 }, 0.6)
    play({ "IG_MAINMENU_OPTION_CHECKBOX_ON" })
    addon.Log.Debug("games.survivor", "a survivor run started", { stake = stake, target = run.target.seconds })
    drawHud(run)
    return run
end

------------------------------------------------------------------ build

---@param parent table
---@param index integer
---@return table card button
local function buildCard(parent, index)
    local Widgets = addon.UI.Widgets
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    card:EnableMouse(true)
    local plate = card:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints(); plate:SetColorTexture(0.06, 0.05, 0.03, 0.92)
    local edge = card:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(0.85, 0.66, 0.2, 0.9)
    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(); highlight:SetColorTexture(1, 0.85, 0.3, 0.15)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(30, 30); card.icon:SetPoint("TOP", 0, -6); card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.nameText = Widgets.CreateFontString(card, "GameFontNormalSmall", "CENTER")
    card.nameText:SetPoint("TOP", card.icon, "BOTTOM", 0, -3); card.nameText:SetWidth(CARD_WIDTH - 6)
    card.levelText = Widgets.CreateFontString(card, "GameFontHighlightSmall", "CENTER")
    card.levelText:SetPoint("TOP", card.nameText, "BOTTOM", 0, -1); card.levelText:SetTextColor(1, 0.85, 0.3)
    card.descriptionText = Widgets.CreateFontString(card, "GameFontDisableSmall", "CENTER")
    card.descriptionText:SetPoint("TOP", card.levelText, "BOTTOM", 0, -2); card.descriptionText:SetWidth(CARD_WIDTH - 8)
    card.descriptionText:SetTextColor(0.85, 0.85, 0.85)
    card:SetScript("OnClick", function() SurvivorArena.Choose(index) end)
    card:Hide()
    return card
end

---@param arena table
local function buildHud(arena)
    local Widgets = addon.UI.Widgets
    -- target progress along the top edge, experience along the bottom edge
    local function line(anchorPoint, y, color)
        local back = arena:CreateTexture(nil, "BORDER")
        back:SetSize(ARENA_WIDTH, 2); back:SetPoint(anchorPoint, arena, anchorPoint, 0, y); back:SetColorTexture(1, 1, 1, 0.08)
        local fill = arena:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(2); fill:SetWidth(1); fill:SetPoint("LEFT", back, "LEFT", 0, 0)
        fill:SetColorTexture(color[1], color[2], color[3], 0.9)
        return fill
    end
    widgets.progressFill = line("TOP", 0, { 1, 0.82, 0.2 })
    widgets.xpFill = line("BOTTOM", 0, { 0.35, 0.6, 1 })
    widgets.timerText = Widgets.CreateFontString(arena, "GameFontNormal", "CENTER")
    widgets.timerText:SetPoint("TOP", arena, "TOP", 0, -5)
    widgets.levelText = Widgets.CreateFontString(arena, "GameFontHighlightSmall", "LEFT")
    widgets.levelText:SetPoint("BOTTOMLEFT", arena, "BOTTOMLEFT", 4, 5)
    widgets.itemSlots = { weapon = {}, passive = {} }
    for kind, rowY in pairs({ weapon = 6, passive = 24 }) do
        for index = 1, #addon.Survivor.ITEMS do
            local slot = CreateFrame("Frame", nil, arena)
            slot:SetSize(15, 15); slot:SetPoint("BOTTOMRIGHT", arena, "BOTTOMRIGHT", -4 - (index - 1) * 17, rowY)   -- right to left
            slot.icon = slot:CreateTexture(nil, "ARTWORK"); slot.icon:SetAllPoints(); slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            slot.levelText = Widgets.CreateFontString(slot, "NumberFontNormalSmall", "RIGHT")
            slot.levelText:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 2, -2)
            slot:Hide()
            widgets.itemSlots[kind][index] = slot
        end
    end
end

---@param panel table the Games tab's survivor panel (300 wide)
function SurvivorArena.Build(panel)
    local Widgets = addon.UI.Widgets
    local state = SurvivorArena.state
    widgets.panel = panel

    -- arena: a faint plate with a soft frame, clicks pass through except on the cards
    local arena = CreateFrame("Frame", nil, panel)
    arena:SetSize(ARENA_WIDTH, ARENA_HEIGHT); arena:SetPoint("TOP", panel, "TOP", 0, -2)
    widgets.arena = arena
    local plate = arena:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints(); plate:SetColorTexture(0, 0, 0, 0.22)
    local ground = arena:CreateTexture(nil, "BACKGROUND", nil, 1)
    ground:SetSize(150, 150); ground:SetPoint("CENTER"); ground:SetTexture(addon.GamesTab.GLOW_TEXTURE)
    ground:SetVertexColor(1, 0.8, 0.3); ground:SetAlpha(0.18); pcall(ground.SetBlendMode, ground, "ADD")
    widgets.hurtFlash = arena:CreateTexture(nil, "OVERLAY", nil, 6)
    widgets.hurtFlash:SetAllPoints(); widgets.hurtFlash:SetColorTexture(0.9, 0.1, 0.05, 1)
    pcall(widgets.hurtFlash.SetBlendMode, widgets.hurtFlash, "ADD")
    widgets.hurtFlash:SetAlpha(0); widgets.hurtFlash:Hide()

    -- actors (monsters, bolts, puffs) on their own layer above the tower
    local towerLayer = CreateFrame("Frame", nil, arena)
    towerLayer:SetAllPoints()
    widgets.towerAnchor = CreateFrame("Frame", nil, towerLayer)
    widgets.towerAnchor:SetSize(1, 1); widgets.towerAnchor:SetPoint("CENTER", arena, "CENTER", 0, 0)
    widgets.barrier = towerLayer:CreateTexture(nil, "OVERLAY", nil, 3)
    widgets.barrier:SetSize(TOWER_SIZE * 2.3, TOWER_SIZE * 2.3); widgets.barrier:SetPoint("CENTER", arena, "CENTER", 0, 0)
    widgets.barrier:SetTexture(addon.GamesTab.GLOW_TEXTURE); widgets.barrier:SetVertexColor(0.4, 0.7, 1)
    pcall(widgets.barrier.SetBlendMode, widgets.barrier, "ADD"); widgets.barrier:SetAlpha(0)
    widgets.thornsAura = towerLayer:CreateTexture(nil, "BACKGROUND", nil, 3)
    widgets.thornsAura:SetSize(TOWER_SIZE * 1.9, TOWER_SIZE * 1.9); widgets.thornsAura:SetPoint("CENTER", arena, "CENTER", 0, 0)
    widgets.thornsAura:SetTexture(addon.Animate.SPARKLE_TEXTURE); widgets.thornsAura:SetVertexColor(0.5, 0.85, 0.3)
    pcall(widgets.thornsAura.SetBlendMode, widgets.thornsAura, "ADD"); widgets.thornsAura:SetAlpha(0.55); widgets.thornsAura:Hide()
    widgets.towerGlow = towerLayer:CreateTexture(nil, "BACKGROUND", nil, 2)
    widgets.towerGlow:SetSize(TOWER_SIZE * 2, TOWER_SIZE * 2); widgets.towerGlow:SetPoint("CENTER", arena, "CENTER", 0, 0)
    widgets.towerGlow:SetTexture(addon.GamesTab.GLOW_TEXTURE); widgets.towerGlow:SetVertexColor(1, 0.85, 0.3)
    pcall(widgets.towerGlow.SetBlendMode, widgets.towerGlow, "ADD"); widgets.towerGlow:SetAlpha(0)
    widgets.tower = towerLayer:CreateTexture(nil, "ARTWORK")
    widgets.tower:SetSize(TOWER_SIZE, TOWER_SIZE); widgets.tower:SetPoint("CENTER", arena, "CENTER", 0, 0)
    iconOr(widgets.tower, addon.Survivor.TOWER_ICON, { 1, 0.85, 0.3 })
    widgets.tower:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    addon.GamesTab.MaskCircle(towerLayer, widgets.tower)
    local hpBack = towerLayer:CreateTexture(nil, "ARTWORK", nil, 1)
    hpBack:SetSize(44, 4); hpBack:SetPoint("TOP", widgets.tower, "BOTTOM", 0, -3); hpBack:SetColorTexture(0, 0, 0, 0.7)
    widgets.hpFill = towerLayer:CreateTexture(nil, "ARTWORK", nil, 2)
    widgets.hpFill:SetHeight(4); widgets.hpFill:SetWidth(44); widgets.hpFill:SetPoint("LEFT", hpBack, "LEFT", 0, 0)
    widgets.hpFill:SetColorTexture(0.2, 0.95, 0.25, 1)

    local actors = CreateFrame("Frame", nil, arena)
    actors:SetAllPoints(); actors:SetFrameLevel(frameLevel(towerLayer) + 2)
    widgets.actors = actors
    widgets.enemyPool, widgets.boltPool = {}, {}
    widgets.puffs, widgets.puffIndex = {}, 0
    widgets.blasts, widgets.blastIndex = {}, 0
    for index = 1, BLAST_COUNT do
        local texture = actors:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(addon.GamesTab.GLOW_TEXTURE); pcall(texture.SetBlendMode, texture, "ADD"); texture:Hide()
        widgets.blasts[index] = { texture = texture, age = 1, x = 0, y = 0, radius = 1 }
    end
    -- lightning segments (Line regions; a client without them gets sparks at the struck monsters instead)
    widgets.zaps, widgets.zapIndex = {}, 0
    widgets.zapsSupported = pcall(function()
        for index = 1, ZAP_SEGMENTS do
            local line = actors:CreateLine(nil, "OVERLAY")
            line:SetThickness(2.5); pcall(line.SetBlendMode, line, "ADD"); line:Hide()
            widgets.zaps[index] = { line = line, age = 1 }
        end
    end)
    for index = 1, PUFF_COUNT do
        local texture = actors:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(addon.Animate.SPARKLE_TEXTURE); pcall(texture.SetBlendMode, texture, "ADD"); texture:Hide()
        widgets.puffs[index] = { texture = texture, age = 1, x = 0, y = 0, spin = 0 }
    end
    widgets.sword = actors:CreateTexture(nil, "OVERLAY")
    widgets.sword:SetTexture(SWORD_TEXTURE); widgets.sword:SetTexCoord(0.08, 0.92, 0.08, 0.92); widgets.sword:Hide()

    -- effects above everything: rings, bursts, floating money, banner
    local effects = CreateFrame("Frame", nil, panel)
    effects:SetAllPoints(panel); effects:SetFrameLevel(frameLevel(actors) + 3)
    widgets.effects = effects
    widgets.floatText = Widgets.CreateFontString(effects, "GameFontNormalHuge", "CENTER"); widgets.floatText:Hide()
    widgets.bannerText = Widgets.CreateFontString(effects, "GameFontNormalHuge", "CENTER")
    widgets.bannerText:SetPoint("CENTER", arena, "CENTER", 0, 56); widgets.bannerText:SetTextColor(1, 0.9, 0.3)
    widgets.hintText = Widgets.CreateFontString(effects, "GameFontHighlightSmall", "CENTER")
    widgets.hintText:SetPoint("BOTTOM", arena, "BOTTOM", 0, 22); widgets.hintText:SetWidth(ARENA_WIDTH - 20)

    buildHud(arena)

    -- level-up cards (above the effects so they can be clicked)
    local cardLayer = CreateFrame("Frame", nil, panel)
    cardLayer:SetAllPoints(arena); cardLayer:SetFrameLevel(frameLevel(effects) + 3)
    widgets.cardTitle = Widgets.CreateFontString(cardLayer, "GameFontNormal", "CENTER")
    widgets.cardTitle:SetPoint("BOTTOM", arena, "CENTER", 0, CARD_HEIGHT / 2 - 4)
    widgets.cardTitle:SetText(Text["Level up! Pick an item"]); widgets.cardTitle:Hide()
    widgets.cards = {}
    for index = 1, 3 do widgets.cards[index] = buildCard(cardLayer, index) end

    -- controls: bet target, stake, start / give up, result
    widgets.targetButtons = {}
    local buttonWidth, gap = 54, 4
    local buttonCount = addon.Survivor.ENDLESS_INDEX
    local rowWidth = buttonCount * buttonWidth + (buttonCount - 1) * gap
    for index = 1, buttonCount do
        local target, targetIndex = addon.Survivor.Target(index), index
        local label = target.endless and Text["Endless"] or Format(Text["{time} x{n}"], { time = clock(target.seconds), n = target.factor })
        local button = Widgets.CreateButton(panel, label, buttonWidth, 18, function() selectTarget(targetIndex) end)
        button:SetPoint("TOPLEFT", panel, "TOP", -rowWidth / 2 + (index - 1) * (buttonWidth + gap), -208)
        widgets.targetButtons[index] = button
    end
    widgets.stake = addon.GamesTab.CreateStakeRow(panel, 36, -234, function() SurvivorArena.Start() end)
    widgets.stake.Write(addon.GamesTab.Settings().lastSurvivorStakeCopper or DEFAULT_STAKE)
    widgets.startButton = Widgets.CreateButton(panel, Text["Start"], 180, 28, function() SurvivorArena.Start() end)
    widgets.startButton:SetPoint("TOP", panel, "TOP", 0, -262)
    if Widgets.MakePrimary then Widgets.MakePrimary(widgets.startButton) end
    widgets.resultText = Widgets.CreateFontString(panel, "GameFontNormal", "CENTER")
    widgets.resultText:SetPoint("TOP", panel, "TOP", 0, -298); widgets.resultText:SetWidth(290)

    -- the run (and the idle glow) advance only while the panel is visible
    widgets.idleTime = 0
    panel:SetScript("OnUpdate", function(_, elapsedSeconds)
        SurvivorArena.Update(elapsedSeconds)
        if not state.run then
            widgets.idleTime = widgets.idleTime + elapsedSeconds
            widgets.towerGlow:SetAlpha(0.25 + 0.2 * math.sin(widgets.idleTime * 2.2))
        end
    end)

    local savedTarget = addon.GamesTab.Settings().survivorTarget
    state.targetIndex = addon.Survivor.Target(savedTarget) and savedTarget or DEFAULT_TARGET
    selectTarget(state.targetIndex)
end
