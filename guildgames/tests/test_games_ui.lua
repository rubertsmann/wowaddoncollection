-- Games tab and animation helpers against a recording widget stub (feature 014, L3: R1, R3, R4 fallback, RF3, RF6).
-- It proves the logic around the widgets (button state, store-before-animate, fallbacks), not how anything looks.
local NOW = 1794873600   -- 2026-11-17 00:00 UTC

-- A widget that records state. Unknown methods are accepted and return the widget (so layout calls chain).
local function newWidget(world, kind)
    local widget = { kind = kind, scripts = {}, text = "", shown = true, enabled = true, alpha = 1, width = 0 }
    local methods = {}
    function methods:SetScript(name, handler) self.scripts[name] = handler end
    function methods:GetScript(name) return self.scripts[name] end
    function methods:SetText(text) self.text = text end
    function methods:GetText() return self.text end
    function methods:Show() self.shown = true end
    function methods:Hide() self.shown = false end
    function methods:SetShown(shown) self.shown = shown and true or false end
    function methods:IsShown() return self.shown end
    function methods:Enable() self.enabled = true end
    function methods:Disable() self.enabled = false end
    function methods:SetEnabled(enabled) self.enabled = enabled and true or false end
    function methods:IsEnabled() return self.enabled end
    function methods:SetAlpha(alpha) self.alpha = alpha end
    function methods:GetAlpha() return self.alpha end
    function methods:SetWidth(width) self.width = width end
    function methods:SetTexture(path) self.texture = path; return true end
    function methods:GetStringWidth() return 40 end
    function methods:GetFontString() return nil end
    function methods:CreateTexture() return newWidget(world, "Texture") end
    function methods:CreateFontString() return newWidget(world, "FontString") end
    function methods:CreateLine() return newWidget(world, "Line") end
    function methods:CreateAnimationGroup()
        local group = newWidget(world, "AnimationGroup")
        group.animations, group.playCount, group.stopCount = {}, 0, 0
        function group:CreateAnimation(animationType)
            if world.refusedTypes[animationType] then error("Unknown animation type " .. animationType) end
            local animation = newWidget(world, animationType)
            self.animations[#self.animations + 1] = animation
            return animation
        end
        function group:Play() self.playCount = self.playCount + 1; world.played[#world.played + 1] = self end
        function group:Stop() self.stopCount = self.stopCount + 1 end
        return group
    end
    return setmetatable(widget, { __index = function(_, key)
        if methods[key] then return methods[key] end
        return function(self) return self end
    end })
end

-- an addon with the pure modules plus UI/Animate.lua and UI/GamesTab.lua on stubbed widgets (no Window)
local function setup(harness, options)
    local world = { refusedTypes = (options and options.refusedTypes) or {}, played = {}, fired = {}, sounds = 0 }
    local saved = { CreateFrame = _G.CreateFrame, BreakUpLargeNumbers = _G.BreakUpLargeNumbers }
    _G.CreateFrame = function(kind) return newWidget(world, kind) end
    _G.BreakUpLargeNumbers = nil
    local addon = harness.addon({ now = NOW })
    addon.Store.db.me = "Me-R"
    addon.Events = { Fire = function(name, ...) world.fired[#world.fired + 1] = name end, On = function() end }
    addon.Api = { Random = function() return world.random or 0.1 end, CoinSoundKit = function() return 120 end,
        PlaySound = function() world.sounds = world.sounds + 1 end, PlaySoundNamed = function() end }
    addon.UI = { Widgets = {
        ROW_HEIGHT = 20,
        CreateFontString = function() return newWidget(world, "FontString") end,
        CreateButton = function(_, label, _, _, onClick)
            local button = newWidget(world, "Button"); button.text = label; button.scripts.OnClick = onClick
            return button
        end,
        CreateScrollList = function(_, _, _, createRow, fillRow)
            local list = newWidget(world, "List")
            function list:SetData(entries)
                self.entries = entries
                for _, entry in ipairs(entries) do fillRow(createRow(self), entry) end   -- exercises the row code
            end
            return list
        end,
        TimeAgo = function() return "1m" end,
    } }
    addon.AzeCaughtPanel = { Build = function() end, Refresh = function() end }   -- not loaded here (tests/test_load.lua builds it)
    for _, path in ipairs({ "UI/Helpers.lua", "UI/Animate.lua", "UI/GamesTab.lua", "UI/SlotMachine.lua", "UI/SurvivorArena.lua" }) do assert(loadfile(path))("GuildGames", addon) end
    world.restore = function() for key, value in pairs(saved) do _G[key] = value end end
    return addon, world
end

-- runs the tween driver until no tween is left (or a step limit)
local function runTweens(addon, seconds)
    local steps = math.ceil((seconds or 5) / 0.05)
    for _ = 1, steps do
        addon.Animate._onUpdate(nil, 0.05)
    end
end

local function withSetup(harness, options, body)
    local addon, world = setup(harness, options)
    local ok, errorMessage = pcall(body, addon, world)
    world.restore()
    if not ok then error(errorMessage, 0) end
end

return {
    ["games ui: a survivor run locks the selector, pauses for item cards, and is booked when it ends or is given up"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local seed = 17
            world.random = nil
            addon.Api.Random = function() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
            local GamesTab, Arena = addon.GamesTab, addon.SurvivorArena
            GamesTab.Build(newWidget(world, "Frame"))
            local failures = {}
            local protected = addon.Log.Protected
            addon.Log.Protected = function(area, message, handler, ...)
                local ok, errorMessage = pcall(handler, ...)
                if not ok then failures[#failures + 1] = area .. ": " .. tostring(errorMessage) end
            end
            GamesTab.widgets.gameButtons.survivor.scripts.OnClick()
            harness.equal(GamesTab.state.game, "survivor"); harness.equal(GamesTab.widgets.playsHeader.text, "Runs")
            local widgets = Arena.widgets
            widgets.targetButtons[2].scripts.OnClick()
            harness.equal(Arena.state.targetIndex, 2); harness.equal(addon.db.ui.survivorTarget, 2)
            widgets.stake.Write(400)
            local run = assert(Arena.Start())
            harness.equal(addon.db.ui.survivorPending.c, 400, "the stake is pending while the run is open")
            harness.equal(widgets.startButton.text, "Give up")
            harness.equal(GamesTab.widgets.gameButtons.coin.enabled, false, "selector locked during the run")
            harness.equal(widgets.targetButtons[1].enabled, false, "target locked during the run")
            local sawCards, frames = false, 0
            while Arena.state.run and frames < 20000 do
                frames = frames + 1
                Arena.Update(0.05)
                addon.Animate._onUpdate(nil, 0.05)
                if run.choices then
                    harness.truthy(widgets.cards[1].shown, "cards are shown for a choice"); sawCards = true
                    widgets.cards[1].scripts.OnClick()
                end
            end
            harness.equal(Arena.state.run, nil, "the run ended")
            harness.truthy(sawCards, "a level-up showed cards")
            harness.equal(#failures, 0, table.concat(failures, "; "))
            harness.equal(addon.db.ui.survivorPending, nil)
            local section = addon.Games.Get("Me-R").survivor
            harness.equal(section.total.wins + section.total.losses, 1)
            harness.equal(widgets.startButton.text, "Start"); harness.equal(GamesTab.widgets.gameButtons.coin.enabled, true)
            harness.equal(#GamesTab.widgets.leaderboardList.entries, 1, "my run is on the survivor board")
            -- give up: the same button ends an open run as a loss
            assert(Arena.Start())
            for _ = 1, 10 do Arena.Update(0.05) end
            harness.equal(Arena.Start(), nil)
            harness.equal(Arena.state.run, nil)
            harness.equal(addon.Games.Get("Me-R").survivor.total.losses, section.total.losses + 1)
            harness.equal(#failures, 0, table.concat(failures, "; "))
            -- every weapon draws (projectile styles, blasts, zaps) without errors
            local armed = assert(Arena.Start())
            for _, item in ipairs(addon.Survivor.ITEMS) do armed.items[item.key] = math.min(3, item.maximum) end
            armed.shield = addon.Survivor.DefenseStats(armed).shield
            for _ = 1, 120 do
                armed.hp = armed.maxHp
                Arena.Update(0.05)
                if armed.choices then widgets.cards[1].scripts.OnClick() end
            end
            harness.equal(#failures, 0, table.concat(failures, "; "))
            Arena.Start()   -- give up
            -- endless: the button cashes out once a minute was reached
            widgets.targetButtons[addon.Survivor.ENDLESS_INDEX].scripts.OnClick()
            harness.equal(Arena.state.targetIndex, addon.Survivor.ENDLESS_INDEX)
            local endless = assert(Arena.Start())
            for _ = 1, 1300 do
                endless.hp, endless.maxHp = 1e9, 1e9   -- unkillable: only the clock matters
                Arena.Update(0.05)
                if endless.choices then widgets.cards[1].scripts.OnClick() end
            end
            harness.truthy(endless.time >= 60, "a minute passed"); harness.equal(widgets.startButton.text, "Cash out")
            local before = addon.Games.Get("Me-R").survivor.total.won
            Arena.Start()
            harness.equal(Arena.state.run, nil)
            harness.equal(addon.Games.Get("Me-R").survivor.total.won, before + 400, "x2 cashed out")
            harness.equal(#failures, 0, table.concat(failures, "; "))
            addon.Log.Protected = protected
        end)
    end,

    ["games ui: an unsupported animation type applies the end state and calls onDone once (RF6)"] = function(harness)
        withSetup(harness, { refusedTypes = { Alpha = true, Scale = true, Translation = true } }, function(addon, world)
            local Animate = addon.Animate
            local region = newWidget(world, "FontString"); region.alpha = 0
            local doneCount = 0
            Animate.FadeIn(region, 0.3, function() doneCount = doneCount + 1 end)
            harness.equal(doneCount, 1); harness.equal(region.alpha, 1); harness.truthy(region.shown)
            local glow = newWidget(world, "Texture")
            Animate.Glow(glow, 2, function() doneCount = doneCount + 1 end)
            harness.equal(doneCount, 2); harness.equal(glow.alpha, 0); harness.equal(glow.shown, false)
            Animate.Pulse(region, 1.2, 0.2, function() doneCount = doneCount + 1 end)
            Animate.Shake(region, 4, 4, function() doneCount = doneCount + 1 end)
            harness.equal(doneCount, 4); harness.equal(#world.played, 0)
            harness.equal(Animate.Supported("Alpha"), false); harness.equal(Animate.Supported("Rotation"), true)
        end)
    end,

    ["games ui: effects reuse one group per region, stop before replay and finish through OnFinished (K3, K7)"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local Animate = addon.Animate
            local region = newWidget(world, "FontString")
            local doneCount = 0
            Animate.FadeIn(region, 0.3, function() doneCount = doneCount + 1 end)
            local group = world.played[1]
            harness.truthy(group); harness.equal(doneCount, 0)
            Animate.FadeIn(region, 0.3, function() doneCount = doneCount + 10 end)
            harness.truthy(world.played[2] == group, "the same group is replayed"); harness.equal(group.stopCount, 2)
            harness.equal(#group.animations, 1, "built once")
            group.scripts.OnFinished(group)
            harness.equal(doneCount, 10, "only the latest run's onDone"); harness.equal(region.alpha, 1)
            group.scripts.OnFinished(group)
            harness.equal(doneCount, 10, "onDone runs once per run")
        end)
    end,

    ["games ui: shake offsets add up to zero"] = function(harness)
        withSetup(harness, nil, function(addon)
            for _, count in ipairs({ 2, 3, 4, 7 }) do
                local sum = 0
                for _, offset in ipairs(addon.Animate.ShakeOffsets(4, count)) do sum = sum + offset end
                harness.equal(sum, 0, "count " .. count)
                harness.equal(#addon.Animate.ShakeOffsets(4, count), count)
            end
        end)
    end,

    ["games ui: a tween with the same key replaces the old one; a failing step ends the tween (RF3)"] = function(harness)
        withSetup(harness, nil, function(addon)
            local Animate = addon.Animate
            local calls = {}
            Animate.Tween("coin", 1, function() calls[#calls + 1] = "a" end, function() calls[#calls + 1] = "doneA" end)
            Animate._onUpdate(nil, 0.1)
            Animate.Tween("coin", 0.2, function(elapsed) calls[#calls + 1] = elapsed end, function() calls[#calls + 1] = "doneB" end)
            runTweens(addon, 1)
            harness.equal(calls[1], "a"); harness.equal(calls[#calls], "doneB")
            for _, call in ipairs(calls) do harness.truthy(call ~= "doneA", "the replaced tween's onDone must not run") end
            harness.equal(Animate.IsTweening("coin"), false)
            local ended = 0
            Animate.Tween("broken", 5, function() error("boom") end, function() ended = ended + 1 end)
            Animate._onUpdate(nil, 0.05)
            harness.equal(ended, 1); harness.equal(Animate.IsTweening("broken"), false)
        end)
    end,

    ["games ui: the tab builds, a flip is stored before the coin moves and the button is locked meanwhile (R1, R3)"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local GamesTab = addon.GamesTab
            GamesTab.Build(newWidget(world, "Frame"))
            local widgets = GamesTab.widgets
            harness.truthy(widgets.flipButton and widgets.leaderboardList and widgets.feedList and widgets.coin)
            harness.equal(widgets.goldBox.text, "1"); harness.equal(widgets.silverBox.text, ""); harness.equal(widgets.copperBox.text, "")
            widgets.goldBox.text, widgets.silverBox.text, widgets.copperBox.text = "", "2", "50"
            widgets.flipButton.scripts.OnClick()
            local stored = addon.Games.Get("Me-R")
            harness.truthy(stored, "stored at the click, before any animation frame"); harness.equal(stored.total.won, 250)
            harness.equal(widgets.flipButton.enabled, false); harness.truthy(GamesTab.state.flipping)
            harness.equal(world.fired[#world.fired], "GAMES_CHANGED")
            harness.equal(addon.db.ui.lastStakeCopper, 250)
            -- a second click while the coin flies does nothing
            harness.equal(GamesTab.Flip(), nil)
            harness.equal(addon.Games.Get("Me-R").total.wins + addon.Games.Get("Me-R").total.losses, 1)
            -- the leaderboard waits for the landing
            harness.equal(#widgets.leaderboardList.entries, 0)
            GamesTab.Refresh()
            harness.equal(#widgets.leaderboardList.entries, 0); harness.truthy(GamesTab.state.refreshPending)
            runTweens(addon, addon.CoinFlip.DURATION + 0.2)
            harness.equal(widgets.flipButton.enabled, true); harness.equal(GamesTab.state.flipping, false)
            harness.equal(#widgets.leaderboardList.entries, 1); harness.equal(#widgets.feedList.entries, 1)
            harness.equal(GamesTab.state.face, "H", "landed on heads (random 0.1)")
            local parts = widgets.coinParts
            harness.truthy(parts.emblem.H.shown and parts.rim.H.shown, "heads face shown")
            harness.truthy(not parts.emblem.T.shown and not parts.rim.T.shown, "tails face hidden")
            harness.truthy(widgets.resultText.text:find("50", 1, true), widgets.resultText.text); harness.equal(world.sounds, 1, "coin sound on a win")
        end)
    end,

    ["games ui: a refused flip shows the reason and starts no animation (R2, RF3)"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local GamesTab = addon.GamesTab
            GamesTab.Build(newWidget(world, "Frame"))
            local widgets = GamesTab.widgets
            for _, boxes in ipairs({ { "0", "0", "0" }, { "", "", "" }, { "", "100", "" }, { "", "", "100" } }) do
                widgets.goldBox.text, widgets.silverBox.text, widgets.copperBox.text = boxes[1], boxes[2], boxes[3]
                harness.equal(GamesTab.Flip(), nil)
                harness.truthy(widgets.resultText.text:find("100000", 1, true), "error names the limit: " .. widgets.resultText.text)
            end
            harness.equal(addon.Animate.IsTweening("coin"), false); harness.equal(widgets.flipButton.enabled, true)
            harness.equal(addon.Games.Get("Me-R"), nil)
            addon.Store.db.readonly = true
            widgets.goldBox.text, widgets.silverBox.text, widgets.copperBox.text = "10", "", ""
            harness.equal(GamesTab.Flip(), nil)
            harness.truthy(widgets.resultText.text:find("read-only", 1, true))
        end)
    end,

    ["games ui: a loss shakes the coin and plays no sound; scope buttons switch the leaderboard (R4, R6)"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local GamesTab = addon.GamesTab
            world.random = 0.9   -- tails
            GamesTab.Build(newWidget(world, "Frame"))
            local widgets = GamesTab.widgets
            widgets.goldBox.text, widgets.silverBox.text, widgets.copperBox.text = "", "", "40"
            harness.equal(GamesTab.Flip().won, false)
            -- mid-flight both faces take turns: count the swaps the coin shows
            local swaps, previousFace = 0, GamesTab.state.face
            for _ = 1, 40 do
                addon.Animate._onUpdate(nil, addon.CoinFlip.DURATION / 40)
                if GamesTab.state.face ~= previousFace then swaps = swaps + 1; previousFace = GamesTab.state.face end
            end
            harness.truthy(swaps >= 3, "the coin shows both faces while it spins (" .. swaps .. " swaps)")
            runTweens(addon, 2)
            harness.equal(GamesTab.state.face, "T"); harness.truthy(widgets.coinParts.emblem.T.shown)
            harness.equal(world.sounds, 0)
            local shaken = false
            for _, group in ipairs(world.played) do
                if group.animations[1] and group.animations[1].kind == "Translation" then shaken = true end
            end
            harness.truthy(shaken, "a Translation (shake) group played")
            harness.equal(widgets.weekButton.enabled, false); harness.equal(widgets.allButton.enabled, true)
            widgets.allButton.scripts.OnClick()
            harness.equal(GamesTab.state.scope, "all"); harness.equal(addon.db.ui.gamesScope, "all")
            harness.equal(widgets.allButton.enabled, false); harness.equal(#widgets.leaderboardList.entries, 1)
        end)
    end,

    ["games ui: the game selector shows one panel and that game's own board; it is locked while a game runs"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local GamesTab = addon.GamesTab
            GamesTab.Build(newWidget(world, "Frame"))
            local widgets = GamesTab.widgets
            harness.truthy(widgets.panels.coin.shown and not widgets.panels.slots.shown, "the coin flip is the default game")
            harness.truthy(addon.SlotMachine.widgets.spinButton, "the slot machine was built")
            addon.Games.Flip("Me-R", 10, "H", NOW, function() return 0.1 end)
            widgets.gameButtons.slots.scripts.OnClick()
            harness.equal(GamesTab.state.game, "slots"); harness.equal(addon.db.ui.gameKey, "slots")
            harness.truthy(widgets.panels.slots.shown and not widgets.panels.coin.shown)
            harness.equal(widgets.gameButtons.slots.enabled, false); harness.equal(widgets.gameButtons.coin.enabled, true)
            harness.equal(#widgets.leaderboardList.entries, 0, "the slot board does not list coin flips")
            harness.equal(widgets.playsHeader.text, "Spins"); harness.equal(widgets.feedTitle.text, "Recent spins")
            addon.SlotMachine.widgets.stake.Write(500)
            harness.truthy(addon.SlotMachine.Spin())
            harness.equal(widgets.gameButtons.coin.enabled, false, "selector locked while the reels turn")
            GamesTab.SelectGame("coin")
            harness.equal(GamesTab.state.game, "slots", "no switch mid-spin")
            runTweens(addon, addon.Slots.SpinDuration() + 0.2)
            harness.equal(widgets.gameButtons.coin.enabled, true)
            harness.equal(#widgets.leaderboardList.entries, 1, "my spin is on the slot board after the reels stopped")
        end)
    end,

    ["games ui: a spin is stored before the reels move, the reels land on the result and a win lights its lines"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local SlotMachine = addon.SlotMachine
            -- the same stop on every reel: every row line pays
            local stop
            for candidate = 1, #addon.Slots.STRIP do
                if addon.Slots.SymbolAt(candidate) == "bag" then stop = candidate break end
            end
            world.random = (stop - 0.5) / #addon.Slots.STRIP
            addon.GamesTab.Build(newWidget(world, "Frame"))
            addon.GamesTab.SelectGame("slots")
            local widgets = SlotMachine.widgets
            widgets.stake.Write(250)
            local result = assert(SlotMachine.Spin())
            harness.truthy(addon.Games.Get("Me-R").slots, "stored at the click")
            harness.equal(widgets.spinButton.enabled, false); harness.truthy(SlotMachine.state.spinning)
            harness.equal(SlotMachine.Spin(), nil, "no second spin while the reels turn")
            harness.equal(addon.Games.Get("Me-R").slots.total.wins + addon.Games.Get("Me-R").slots.total.losses, 1)
            -- halfway: reels are moving (motion blur visible on the first reel)
            for _ = 1, 10 do addon.Animate._onUpdate(nil, 0.05) end
            harness.truthy(widgets.reels[1].blur.alpha > 0, "motion blur while fast")
            runTweens(addon, addon.Slots.SpinDuration() + 0.2)
            harness.equal(widgets.spinButton.enabled, true); harness.equal(SlotMachine.state.spinning, false)
            for reel = 1, 3 do
                for row = 1, 3 do
                    harness.equal(widgets.reels[reel].symbols[row].symbol, result.grid[row][reel], "cell " .. row .. "," .. reel)
                end
                harness.equal(widgets.reels[reel].blur.alpha, 0)
            end
            harness.truthy(result.multiplier > 0)
            runTweens(addon, 6)   -- the line cycle ends with every winning line shown
            for _, lineWin in ipairs(result.lines) do harness.truthy(widgets.paylines[lineWin.line].shown, "line " .. lineWin.line) end
            harness.truthy(widgets.cellGlows[1].shown == false or widgets.cellGlows[1].alpha >= 0)
            harness.truthy(widgets.resultText.text:find("50", 1, true), widgets.resultText.text)
            harness.equal(widgets.multiplierText.text, "x" .. result.multiplier)
            -- the next spin clears the old effects first
            world.random = 0.37
            SlotMachine.Spin()
            for _, line in ipairs(widgets.paylines) do harness.equal(line.shown, false) end
            harness.equal(widgets.multiplierText.text, "")
        end)
    end,

    ["games ui: a refused spin shows the reason and starts no reels"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            addon.GamesTab.Build(newWidget(world, "Frame"))
            local widgets = addon.SlotMachine.widgets
            widgets.stake.goldBox.text, widgets.stake.silverBox.text, widgets.stake.copperBox.text = "", "", ""
            harness.equal(addon.SlotMachine.Spin(), nil)
            harness.truthy(widgets.resultText.text:find("100000", 1, true), widgets.resultText.text)
            harness.equal(addon.Animate.IsTweening("slotReels"), false); harness.equal(widgets.spinButton.enabled, true)
            harness.equal(addon.Games.Get("Me-R"), nil)
        end)
    end,

    ["games ui: landing and win effects run without errors (sparkles, ring, floating result, trail, reel flash)"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local failures = {}
            local realLog = addon.Log
            addon.Log = setmetatable({
                Protected = function(area, _, func, ...)
                    local ok, errorMessage = pcall(func, ...)
                    if not ok then failures[#failures + 1] = area .. ": " .. tostring(errorMessage) end
                    return ok
                end,
                Warning = function(area, _, details) failures[#failures + 1] = area .. ": " .. tostring(details and details.error) end,
            }, { __index = realLog })
            local GamesTab = addon.GamesTab
            GamesTab.Build(newWidget(world, "Frame"))
            local widgets = GamesTab.widgets
            for _, randomValue in ipairs({ 0.1, 0.9 }) do   -- a win, then a loss
                world.random = randomValue
                widgets.goldBox.text, widgets.silverBox.text, widgets.copperBox.text = "1", "", ""
                assert(GamesTab.Flip())
                for _ = 1, 10 do addon.Animate._onUpdate(nil, 0.05) end
                local ghosts = 0
                for _, ghost in ipairs(widgets.trail) do if ghost.shown then ghosts = ghosts + 1 end end
                harness.truthy(ghosts > 0, "the trail follows the coin in the air")
                runTweens(addon, addon.CoinFlip.DURATION)
                local expected = randomValue < 0.5 and "+" or "-"
                harness.equal(widgets.floatText.text:sub(1, 1), expected, "floating result " .. widgets.floatText.text)
                runTweens(addon, 3)
                harness.equal(widgets.floatText.shown, false, "the floating result fades out")
                for _, ghost in ipairs(widgets.trail) do harness.equal(ghost.shown, false) end
            end
            -- a slot win with every row paying
            local stop
            for candidate = 1, #addon.Slots.STRIP do
                if addon.Slots.SymbolAt(candidate) == "bag" then stop = candidate break end
            end
            world.random = (stop - 0.5) / #addon.Slots.STRIP
            GamesTab.SelectGame("slots")
            addon.SlotMachine.widgets.stake.Write(250)
            assert(addon.SlotMachine.Spin())
            runTweens(addon, addon.Slots.SpinDuration() + 0.1)
            harness.equal(addon.SlotMachine.widgets.floatText.text:sub(1, 1), "+")
            runTweens(addon, 6)
            harness.equal(#failures, 0, "effect errors: " .. table.concat(failures, " | "))
            addon.Log = realLog
        end)
    end,

    ["games ui: the choice buttons are marked selected (flat buttons) and the board can be revealed"] = function(harness)
        withSetup(harness, nil, function(addon, world)
            local selected = {}
            local createButton = addon.UI.Widgets.CreateButton
            addon.UI.Widgets.CreateButton = function(...)
                local button = createButton(...)
                button.SetSelected = function(self, value) selected[self] = value end
                return button
            end
            local GamesTab = addon.GamesTab
            GamesTab.Build(newWidget(world, "Frame"))
            local widgets = GamesTab.widgets
            harness.equal(selected[widgets.headsButton], true); harness.equal(selected[widgets.tailsButton], false)
            harness.equal(selected[widgets.weekButton], true); harness.equal(selected[widgets.gameButtons.coin], true)
            widgets.tailsButton.scripts.OnClick()
            harness.equal(selected[widgets.headsButton], false); harness.equal(selected[widgets.tailsButton], true)
            harness.equal(GamesTab.state.pick, "T")
            widgets.gameButtons.slots.scripts.OnClick()
            harness.equal(selected[widgets.gameButtons.slots], true); harness.equal(selected[widgets.gameButtons.coin], false)
            GamesTab.RevealBoard()   -- stub lists have no rows: nothing to reveal, no error
        end)
    end,
}
