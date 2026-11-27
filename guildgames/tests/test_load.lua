-- Load-time smoke test: every file in the TOC compiles and runs its top level against stubbed WoW globals, in TOC order,
-- for the live and the dev identity; the window builds and a flip and a spin run. It does NOT replace testing in the game.
local function slurp(path)
    local handle = assert(io.open(path, "rb"), path)
    local text = handle:read("*a"); handle:close()
    return text
end

-- Universal widget stub: every method returns the stub itself, except the few that must return plain values.
local PLAIN = { GetStringWidth = 40, GetWidth = 100, GetHeight = 20, GetText = "", IsShown = false, GetEffectiveScale = 1,
    GetCenter = 0, GetNumPoints = 0, GetAlpha = 1, GetFrameLevel = 1 }
local function stub()
    local widget = {}
    local shown, text = false, ""
    return setmetatable(widget, {
        __index = function(_, key)
            if key == "IsShown" then return function() return shown end end
            if key == "SetText" then return function(_, value) text = value == nil and "" or tostring(value) return widget end end
            if key == "GetText" then return function() return text end end
            if key == "Show" then return function() shown = true end end
            if key == "Hide" then return function() shown = false end end
            if key == "SetShown" then return function(_, value) shown = value and true or false end end
            if key == "GetFontString" then return function() return nil end end
            return function()
                local value = PLAIN[key]
                if value == nil then return widget end
                return value
            end
        end,
        __call = function() return widget end,
    })
end

local function tocFiles(path)
    local files = {}
    for line in slurp(path):gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%.lua%s*$") then files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/")) end
    end
    return files
end

-- the standard minimap-button libraries (LibDBIcon and what it needs) run against the stubs too; the other Libs are
-- loaded by tests/run.lua
local function isMinimapLibrary(file)
    return file:match("^Libs/CallbackHandler%-1%.0/") or file:match("^Libs/LibDataBroker%-1%.1/") or file:match("^Libs/LibDBIcon%-1%.0/")
end

local function withStubs(body)
    local saved = {}
    local globals = { CreateFrame = function() return stub() end, UIParent = stub(), Minimap = stub(), GameTooltip = stub(), UISpecialFrames = {},
        SlashCmdList = {}, print = function() end, C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
            SendAddonMessage = function() return 0 end },
        C_Timer = { After = function() end, NewTicker = function() return stub() end } }
    for key, value in pairs(globals) do saved[key] = _G[key]; _G[key] = value end
    local ok, errorMessage = pcall(body)
    for key in pairs(globals) do _G[key] = saved[key] end
    if not ok then error(errorMessage, 0) end
end

return {
    ["load: the TOC lists every addon file in Core, UI and Locales"] = function(harness)
        local listed = {}
        for _, file in ipairs(tocFiles("GuildGames.toc")) do listed[file] = true; assert(io.open(file, "rb"), "TOC lists missing file " .. file):close() end
        local listing = io.popen('dir /b /s Core\\*.lua UI\\*.lua Locales\\*.lua 2>nul || find Core UI Locales -name "*.lua"')
        for line in listing:lines() do
            local path = "/" .. line:gsub("\\", "/")
            local relative = path:match(".*/(Core/[%w_/]+%.lua)$") or path:match(".*/(UI/[%w_/]+%.lua)$")
                or path:match(".*/(Locales/[%w_/]+%.lua)$")
            if relative then harness.truthy(listed[relative], relative .. " exists but is not in GuildGames.toc") end
        end
        listing:close()
        harness.truthy(slurp("GuildGames.toc"):find("Libs\\LibGuildSync\\LibGuildSync.xml", 1, true), "the TOC must load the library")
    end,

    ["load: all TOC files run in order for both identities; the window builds, a flip and a spin run"] = function(harness)
        withStubs(function()
            for _, folderName in ipairs({ "GuildGames", "GuildGames-Dev" }) do
                local addon = {}
                for _, file in ipairs(tocFiles("GuildGames.toc")) do
                    if not file:match("^Libs/") or isMinimapLibrary(file) then assert(loadfile(file), file)(folderName, addon) end
                end
                local development = folderName:find("Dev", 1, true) ~= nil
                harness.equal(addon.IS_DEVELOPMENT_BUILD, development)
                harness.equal(addon.PREFIX, development and "GGamesDev" or "GGames")
                harness.equal(addon.SAVED_VARIABLES_NAME, development and "GuildGamesDevDB" or "GuildGamesDB")
                harness.equal(addon.PROTOCOL_MAJOR, 1); harness.equal(addon.PROTOCOL_MINOR, 9); harness.equal(addon.Store.SCHEMA, 3)
                -- the key binding's globals carry this build's names (live + dev installed together)
                local binding = addon.Catcher.BindingNames(development)
                harness.equal(binding.name, development and "AZECAUGHT_THROW_DEV" or "AZECAUGHT_THROW")
                harness.equal(binding.func, development and "GuildGamesDevAzeCaughtThrow" or "GuildGamesAzeCaughtThrow")
                harness.equal(type(rawget(_G, binding.func)), "function", binding.func)
                harness.truthy(rawget(_G, "BINDING_NAME_" .. binding.name) and rawget(_G, "BINDING_HEADER_" .. binding.header), "binding labels")
                harness.truthy(addon.UI and addon.GamesTab and addon.SlotMachine and addon.Communication and addon.Sync, "namespace incomplete")
                addon.Store.Init({})
                addon.Store.db.me = "A-R"
                local okToggle, toggleError = pcall(addon.UI.Toggle)
                harness.truthy(okToggle, "opening the pet view failed: " .. tostring(toggleError))
                harness.truthy(addon.PetView.widgets.frame, "the default start mode builds the pet view")
                harness.truthy(addon.PetView.widgets.trainButton and addon.PetView.widgets.trainMenu, "the pet view has the training button and menu")
                harness.equal(#(function() local list = {} for _, icon in pairs(addon.PetView.widgets.trainIcons) do list[#list + 1] = icon end return list end)(), 4,
                    "four stat icons in the training menu")
                local okFull, fullError = pcall(addon.UI.SetMode, "full")
                harness.truthy(okFull, "building the window failed: " .. tostring(fullError))
                harness.truthy(addon.GamesTab.widgets.flipButton, "the coin flip was not built (see Log: window.games)")
                harness.truthy(addon.SlotMachine.widgets.spinButton, "the slot machine was not built (see Log: games.slots)")
                addon.GamesTab.ReadStake = function() return 100 end   -- the stub boxes hold no text
                local okFlip, flipError = pcall(addon.GamesTab.Flip)
                harness.truthy(okFlip, "flipping failed: " .. tostring(flipError))
                harness.truthy(addon.Games.Get("A-R"), "the flip was stored")
                addon.GamesTab.state.flipping = false
                addon.GamesTab.SelectGame("slots")
                local okSpin, spinError = pcall(addon.SlotMachine.Spin)
                harness.truthy(okSpin, "spinning failed: " .. tostring(spinError))
                harness.truthy(addon.SurvivorArena.widgets.startButton, "the survivor arena was not built (see Log: games.survivor)")
                addon.SlotMachine.state.spinning = false
                addon.GamesTab.SelectGame("survivor")
                addon.SurvivorArena.widgets.stake.Read = function() return 100 end
                local okRun, runError = pcall(function()
                    assert(addon.SurvivorArena.Start(), "no run")
                    for _ = 1, 400 do
                        addon.SurvivorArena.Update(0.1)
                        if addon.SurvivorArena.state.run and addon.SurvivorArena.state.run.choices then addon.SurvivorArena.Choose(1) end
                    end
                    if addon.SurvivorArena.state.run then addon.SurvivorArena.Start() end   -- give up
                end)
                harness.truthy(okRun, "the survivor run failed: " .. tostring(runError))
                harness.truthy(addon.Games.Get("A-R").tower, "the run was stored")
                harness.truthy(addon.SurvivorArena.widgets.pet, "the survivor companion model was built")
                -- the runner: locked without a companion; a run without input crashes and is booked
                addon.GamesTab.SelectGame("runner")
                harness.equal(addon.GamesTab.state.game, "runner")
                harness.truthy(addon.RunnerView.widgets.startButton, "the runner was not built (see Log: games.runner)")
                local selectedForDash = false
                local okDash, dashError = pcall(function()
                    local AzeCaught = addon.AzeCaught
                    if not AzeCaught.Active() then
                        selectedForDash = true
                        assert(addon.RunnerView.Start() == nil, "a run started without a companion")
                        local entry = AzeCaught.NoteFound({ npc = 299, name = "Young Wolf", level = 2, classification = "normal" }, addon.Utility.Now())
                        entry.caught = 1
                        assert(AzeCaught.Select(299, 1))
                    end
                    assert(addon.RunnerView.Start(), "no run")
                    assert(addon.GamesTab.IsBusy(), "the switch is locked during a run")
                    for _ = 1, 400 do
                        addon.RunnerView.Update(0.05)
                        if not addon.RunnerView.state.run then break end
                    end
                end)
                harness.truthy(okDash, "the runner run failed: " .. tostring(dashError))
                harness.equal(addon.RunnerView.state.run, nil, "a run without input ends")
                harness.truthy(addon.Games.Get("A-R").runner, "the runner section was stored")
                harness.equal(addon.GamesTab.IsBusy(), false)
                harness.truthy(pcall(addon.GamesTab.Refresh), "the runner board refreshes")
                if selectedForDash then addon.AzeCaught.State().active = nil; addon.AzeCaught.State().collection[299] = nil end
                harness.truthy(pcall(addon.UI.Refresh), "refreshing failed")
                harness.truthy(addon.UI.parts.sidebar and addon.UI.parts.stage, "the overlay window has a stage and a sidebar")
                harness.truthy(addon.UI.parts.grip and addon.UI.parts.mover, "the scale grip or move handle was not built (see Log: window.grip)")
                harness.truthy(type(addon.GamesTab.widgets.gameButtons.coin.gameIcon) == "table", "the game switch has icons")
                -- the corner follows the cursor: 1.5 times the window's width away is scale 1.5, clamped to the minimum
                -- and the maximum
                harness.equal(addon.UI.ScaleForCorner(100, 800, 100 + 300 * 1.5, 800 - 10), 1.5)
                harness.equal(addon.UI.ScaleForCorner(100, 800, 100 + 300 * 5, 800), addon.UI.MAXIMUM_SCALE)
                harness.equal(addon.UI.ScaleForCorner(100, 800, 90, 810), addon.UI.MINIMUM_SCALE)
                harness.equal(addon.db.ui.sidebarOpen, false, "the leaderboard sidebar starts closed")
                harness.truthy(pcall(addon.UI.ToggleSidebar), "toggling the sidebar failed")
                harness.equal(addon.db.ui.sidebarOpen, true)
                harness.truthy(pcall(addon.UI.ToggleSidebar)); harness.equal(addon.db.ui.sidebarOpen, false)
                -- AZEcaught: the panel builds, every view, care, the commands and the ticker run without an error
                harness.truthy(addon.AzeCaughtPanel.widgets.model, "the AZEcaught panel was not built (see Log: caught.ui)")
                -- the camera (the model was sometimes cut off): full body, zoomed out, wheel per NPC
                do
                    local Panel, calls = addon.AzeCaughtPanel, {}
                    local fake = { npc = 4711,
                        SetPortraitZoom = function(_, value) calls.portrait = value end,
                        SetPosition = function(_, x, y, z) calls.position = x + y + z end,
                        SetCamDistanceScale = function(_, value) calls.distance = value end }
                    local applied = Panel.FitCamera(fake)
                    harness.equal(calls.portrait, 0, "full body"); harness.equal(calls.position, 0)
                    harness.truthy(calls.distance > 1, "farther than the client's own fit: " .. tostring(calls.distance))
                    harness.truthy(applied.camera and applied.portrait)
                    local fitted = calls.distance
                    Panel.ZoomModel(fake, -1); harness.truthy(calls.distance > fitted, "wheel down zooms out")
                    for _ = 1, 50 do Panel.ZoomModel(fake, -1) end; harness.equal(calls.distance, 4, "limit")
                    Panel.FitCamera(fake); harness.equal(calls.distance, 4, "remembered for this NPC")
                    fake.npc = 1; Panel.FitCamera(fake); harness.equal(calls.distance, fitted, "other NPCs keep the default")
                    harness.truthy(Panel.FitCamera({}).camera == false, "a client without the calls is fine")
                    Panel.zoomByNpc = {}
                end
                addon.GamesTab.SelectGame("caught")
                harness.equal(addon.GamesTab.state.game, "caught")
                local entry = addon.AzeCaught.NoteFound({ npc = 4711, name = "Wolf", level = 5 }, 1794873600)
                entry.caught = 1
                for _, view in ipairs({ "collection", "guild", "companion" }) do addon.AzeCaughtPanel.SelectView(view) end
                -- switching: select a row, the button asks "Stats will be reset", confirming switches
                local Panel = addon.AzeCaughtPanel
                -- without a companion only Companion and Collection open
                for _, view in ipairs({ "arena", "guild", "shop", "inventory" }) do
                    harness.equal(Panel.ViewLocked(view), true, view .. " is locked")
                    Panel.SelectView(view)
                    harness.equal(Panel.state.view, "companion", view .. " opens the companion instead")
                end
                harness.equal(Panel.ViewLocked("collection"), false); harness.equal(Panel.ViewLocked("companion"), false)
                Panel.SelectView("collection"); Panel.SelectSection("caught")
                Panel.SelectRow(4711, addon.AzeCaught.Roster()[1].uid)
                harness.equal(Panel.state.previewNpc, 4711, "a click selects the row")
                harness.equal(addon.AzeCaught.Active(), nil, "a click alone does not switch")
                Panel.RequestSwitch()
                harness.truthy(Panel.widgets.confirmDialog:IsShown(), "the confirm dialog opens")
                Panel.CancelSwitch()
                harness.equal(Panel.widgets.confirmDialog:IsShown(), false); harness.equal(addon.AzeCaught.Active(), nil)
                Panel.RequestSwitch(); Panel.ConfirmSwitch()
                harness.truthy(addon.AzeCaught.Active(), "confirming switches")
                harness.equal(Panel.ViewLocked("shop"), false, "a companion unlocks the tabs")
                Panel.SelectView("shop"); harness.equal(Panel.state.view, "shop"); Panel.SelectView("collection")
                Panel.SelectSection("seen"); Panel.SelectSection("caught")
                addon.AzeCaught.Active().hunger = 40
                addon.AzeCaughtPanel.Care("feed"); addon.AzeCaughtPanel.Care("pet"); addon.AzeCaughtPanel.Care("sleep")
                addon.AzeCaughtPanel.RefreshCompanion()
                -- the need bars are the care buttons: greyed out when unusable, a click cooldown
                do
                    local Panel = addon.AzeCaughtPanel
                    local companion = addon.AzeCaught.Active()
                    companion.asleep = nil; companion.affection = 60; companion.thirst = 100
                    Panel.state.careReadyAt = nil
                    Panel.RefreshCareButtons()
                    harness.equal(Panel.widgets.careButtons, nil, "no care icon buttons any more")
                    harness.equal(Panel.widgets.careBars.feed, Panel.widgets.bars.hunger, "the food bar feeds")
                    harness.equal(Panel.widgets.careBars.water, Panel.widgets.bars.thirst, "the water bar waters")
                    harness.equal(Panel.widgets.careBars.pet, Panel.widgets.bars.affection, "the petting bar pets")
                    harness.equal(Panel.widgets.careBars.sleep, Panel.widgets.bars.energy, "the energy bar sleeps")
                    harness.equal(Panel.careState.water.unusable, "full", "water greyed out when full")
                    harness.equal(Panel.widgets.careBars.water.careEnabled, false, "a full need's bar does not take clicks")
                    harness.equal(Panel.careState.pet.unusable, nil, "petting usable")
                    harness.equal(Panel.widgets.careBars.pet.careEnabled, true, "the petting bar takes clicks")
                    Panel.ClickCare("pet")
                    harness.equal(companion.affection, 100, "the click petted")
                    companion.affection = 60
                    Panel.RefreshCareButtons()
                    harness.equal(Panel.widgets.careBars.pet.careEnabled, false, "greyed out during the cooldown")
                    Panel.ClickCare("pet")
                    harness.equal(companion.affection, 60, "a second click inside the cooldown is ignored")
                    harness.truthy(addon.AzeCaught.JournalLines(1, "ui.cooldown")[1], "the ignored click is journaled")
                    Panel.state.careReadyAt = nil
                end
                -- the hover panel shows the NPC's info beside the model
                local npcID, infoEntry = addon.AzeCaughtPanel.CompanionNpc()
                local tooltipLines = {}
                local fakeTooltip = { SetOwner = function() end, Show = function() end,
                    SetText = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
                    AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
                    AddDoubleLine = function(_, left, right) tooltipLines[#tooltipLines + 1] = left .. " | " .. right end }
                local okInfo, lineCount = pcall(addon.AzeCaughtPanel.ShowNpcInfo, fakeTooltip, addon.AzeCaughtPanel.widgets.model, npcID, infoEntry)
                harness.truthy(okInfo and lineCount > 5, "the info panel: " .. tostring(lineCount))
                -- a guild member's companion: my entry of that NPC with their level, or (unknown NPC) no history lines
                do
                    local Panel = addon.AzeCaughtPanel
                    local guildNpc, guildEntry = Panel.GuildNpc({ npc = npcID, lvl = 77, cls = "rare", species = "Wolf" })
                    harness.equal(guildNpc, npcID); harness.equal(guildEntry.lvl, 77); harness.equal(guildEntry.cls, "rare")
                    harness.truthy(guildEntry ~= infoEntry and infoEntry.lvl ~= 77, "my collection entry is not changed")
                    local _, strangerEntry = Panel.GuildNpc({ npc = 987654, lvl = 12, cls = "elite", species = "Stranger" })
                    tooltipLines = {}
                    local okStranger, strangerCount = pcall(Panel.ShowNpcInfo, fakeTooltip, {}, 987654, strangerEntry)
                    harness.truthy(okStranger and strangerCount > 5, "the stranger's info panel: " .. tostring(strangerCount))
                    local hasHistory = false
                    for _, text in ipairs(tooltipLines) do if text == addon.Text["History"] then hasHistory = true end end
                    harness.truthy(not hasHistory, "no history for an NPC I never met")
                    harness.equal(select(2, Panel.GuildNpc(nil)), nil)
                    -- the guild panel adds the TLevel and the hearts under the subtitle
                    tooltipLines = {}
                    local okGuild = pcall(Panel.ShowGuildNpcInfo, fakeTooltip, {},
                        { npc = 987654, lvl = 12, cls = "elite", species = "Stranger", level = 27, hearts = 12 })
                    local levelLine, heartsLine
                    for _, text in ipairs(tooltipLines) do
                        if text:find(addon.Text["TLevel"] .. " | 27", 1, true) then levelLine = true end
                        if text:find(addon.Text["Hearts"] .. " | +12", 1, true) then heartsLine = true end
                    end
                    harness.truthy(okGuild and levelLine and heartsLine, table.concat(tooltipLines, " / "))
                    harness.equal(Panel.ShowGuildNpcInfo(fakeTooltip, {}, nil), nil)
                end
                -- the model returns to idle after an action and whenever the panel shows
                do
                    local Panel = addon.AzeCaughtPanel
                    local played, scripts = {}, {}
                    local fake = setmetatable({ HasAnimation = function() return true end,
                        SetAnimation = function(_, animationID) played[#played + 1] = animationID end,
                        SetScript = function(_, name, handler) scripts[name] = handler end,
                        GetScript = function(_, name) return scripts[name] end }, { __index = Panel.widgets.model })
                    local realModel, realAfter = Panel.widgets.model, C_Timer.After
                    local timers = {}
                    C_Timer.After = function(_, callback) timers[#timers + 1] = callback end
                    Panel.widgets.model = fake
                    Panel.PrepareModel(fake, Panel.IdleOfCompanion)
                    local companion = addon.AzeCaught.Active()
                    companion.asleep = nil; companion.affection = 80
                    Panel.Care("pet")
                    harness.truthy(played[#played] ~= 0, "the action plays its emote")
                    for _, callback in ipairs(timers) do callback() end
                    harness.equal(played[#played], 0, "back to idle after the emote")
                    played = {}
                    harness.truthy(scripts.OnModelLoaded, "the model goes idle once it has loaded")
                    scripts.OnModelLoaded(fake)
                    harness.equal(played[#played], 0, "idle after loading")
                    played = {}
                    Panel.ShowIdle("shown")
                    harness.equal(played[#played], 0, "idle when the menu shows")
                    companion.asleep = 100; played = {}
                    Panel.ShowIdle("shown")
                    harness.truthy(played[#played] ~= 0, "a sleeping companion shows its sleep animation, not the stand")
                    companion.asleep = nil
                    -- an older timer does not override a newer action
                    timers = {}
                    companion.affection = 80; Panel.Care("pet")
                    local stale = timers[1]
                    companion.affection = 80; Panel.Care("pet")
                    played = {}
                    stale()
                    harness.equal(#played, 0, "a stale timer is ignored")
                    Panel.widgets.model, C_Timer.After = realModel, realAfter
                end
                addon.Catcher.Start(); addon.Catcher.OnTick(); addon.Catcher.PollThrows(); addon.Catcher.CheckDeath("target"); addon.Catcher.RefreshIcons()
                -- a catch logs the dump taken at the throw
                addon.Catcher.dumps["Creature-0-1-2-3-4711-AB"] = { at = 0, values = { name = "Wolf", creatureType = "Beast" } }
                addon.Catcher.LogCatchDump("Creature-0-1-2-3-4711-AB", { npc = 4711, chance = 0.1, roll = 0.05, reward = 20000 })
                local dumpLine = addon.AzeCaught.JournalLines(1, "catch.dump")[1] or ""
                harness.truthy(dumpLine:find("creatureType=Beast", 1, true) and dumpLine:find("roll=0.0500", 1, true), "catch dump: " .. dumpLine)
                harness.equal(addon.Catcher.dumps["Creature-0-1-2-3-4711-AB"], nil, "a logged dump is released")
                for _, command in ipairs({ "state", "log 5", "log 5 care", "wallet", "chance", "collection", "verbose on", "verbose off",
                    "notify off", "notify on", "export", "probe", "model", "dump", "", "nonsense" }) do
                    local okCommand, commandError = pcall(addon.SlashCommands.caught, command)
                    harness.truthy(okCommand, "/gg caught " .. command .. ": " .. tostring(commandError))
                end
                harness.truthy(pcall(addon.SlashCommands.catch, ""), "/gg catch")
                -- in a dungeon or raid the throw is refused with an overlay and a chat line
                local savedInstance, savedErrors, savedPrint = IsInInstance, UIErrorsFrame, addon.Print
                local overlay, chat = {}, {}
                UIErrorsFrame = { AddMessage = function(_, text) overlay[#overlay + 1] = text end }
                addon.Print = function(text) chat[#chat + 1] = text end
                for _, kind in ipairs({ "party", "raid" }) do
                    IsInInstance = function() return true, kind end
                    overlay, chat = {}, {}
                    harness.equal(addon.Catcher.Throw("target"), false, "no throw in " .. kind)
                    harness.truthy(overlay[1] and overlay[1]:find("dungeons", 1, true), "overlay in " .. kind .. ": " .. tostring(overlay[1]))
                    harness.truthy(chat[1] and chat[1]:find("dungeons", 1, true), "chat line in " .. kind .. ": " .. tostring(chat[1]))
                end
                IsInInstance = function() return false, "none" end
                overlay = {}
                addon.SlashCommands.catch("")
                harness.equal(#overlay, 0, "no dungeon overlay in the open world")
                IsInInstance, UIErrorsFrame, addon.Print = savedInstance, savedErrors, savedPrint
                -- the icon options page: built, toggles and steps the settings, the slash command too
                local Options = addon.AzeCaughtOptions
                harness.truthy(Options.widgets.frame, "the options page was built (see Log: caught.options)")
                Options.Change("shown"); harness.equal(addon.AzeCaught.IconSettings().shown, false)
                Options.Change("shown"); harness.equal(addon.AzeCaught.IconSettings().shown, true)
                Options.Change("y", 1); harness.equal(addon.AzeCaught.IconSettings().y, 4)
                Options.Reset(); harness.equal(addon.AzeCaught.IconSettings().y, 2)
                for _, command in ipairs({ "icon", "icon off", "icon on", "icon x -10", "icon size 40", "icon reset" }) do
                    harness.truthy(pcall(addon.SlashCommands.caught, command), "/gg caught " .. command)
                end
                harness.equal(addon.AzeCaught.IconSettings().size, 26, "reset at the end")
                -- The client rules: nameplates are restricted regions. Measuring one ("GetCenter():
                -- Can't measure restricted regions ... Lua Taint") and drawing a line to one ("Line:SetEndPoint(): Not
                -- allowed to depend on NamePlate1") are refused; a plain frame with ONE anchor on it works (the rope icon).
                -- The game also hides where the enemy is (UnitPosition is hidden: "position hidden"), so
                -- a wind-up plays on the player, then the lasso in a pin frame anchored to the target's plate.
                local savedNamePlate, savedCreateFrame = C_NamePlate, CreateFrame
                local plate, lockedPlate, refused, anchoredToPlate = stub(), stub(), {}, {}
                for _, restrictedPlate in ipairs({ plate, lockedPlate }) do
                    for _, method in ipairs({ "GetCenter", "GetLeft", "GetTop", "GetRect", "GetEffectiveScale", "GetSize", "GetWidth", "GetHeight" }) do
                        rawset(restrictedPlate, method, function() refused[#refused + 1] = method; error(method .. "(): Can't measure restricted regions") end)
                    end
                end
                local function restricted(region)
                    for _, method in ipairs({ "SetStartPoint", "SetEndPoint" }) do
                        rawset(region, method, function(self, _, relative)
                            if relative == plate or relative == lockedPlate then refused[#refused + 1] = method; error(method .. "(): Not allowed to depend on NamePlate1") end
                            return self
                        end)
                    end
                    rawset(region, "SetPoint", function(self, _, relative)
                        if relative == lockedPlate then error("SetPoint(): Not allowed to depend on NamePlate2") end
                        if relative == plate then anchoredToPlate[#anchoredToPlate + 1] = self end
                        return self
                    end)
                    return region
                end
                CreateFrame = function()
                    local frame = restricted(stub())
                    rawset(frame, "CreateLine", function() return restricted(stub()) end)
                    rawset(frame, "CreateTexture", function() return restricted(stub()) end)
                    return frame
                end
                local platesByUnit = { target = plate }
                C_NamePlate = { GetNamePlateForUnit = function(unit) return platesByUnit[unit] end }
                addon.Catcher.PlayRopeEffect("target")
                for _ = 1, 60 do addon.Animate._onUpdate(nil, 0.02) end   -- fly, land, burst
                harness.equal(table.concat(refused, ","), "", "the rope effect never measures a nameplate or draws a line to it")
                local played = addon.Catcher.lastEffect
                harness.equal(played.mode, "nameplate", tostring(played.error) .. " " .. tostring(played.why))
                harness.equal(#anchoredToPlate, 1, "exactly one frame (the landing pin) is anchored to the plate")
                -- the fail effects: escape on the target, snap where the icon was; same one-anchor rule
                addon.Catcher.PlayFailEffect("escape", "target")
                for _ = 1, 60 do addon.Animate._onUpdate(nil, 0.02) end
                harness.equal(addon.Catcher.lastFailEffect.mode, "nameplate", tostring(addon.Catcher.lastFailEffect.error))
                addon.Catcher.PlayFailEffect("snap", "target")
                for _ = 1, 60 do addon.Animate._onUpdate(nil, 0.02) end
                harness.equal(addon.Catcher.lastFailEffect.kind, "snap"); harness.equal(addon.Catcher.lastFailEffect.mode, "nameplate")
                harness.equal(#anchoredToPlate, 3, "the throw pin plus one fail pin anchoring twice, nothing else")
                addon.Catcher.OnTooSlow("Creature-0-1-2-3-77-0000000001", "Wolf")
                harness.equal(addon.Catcher.lastFailEffect.kind, "snap"); harness.equal(addon.Catcher.lastFailEffect.mode, "front", "unit unknown")
                harness.equal(table.concat(refused, ","), "", "the fail effects never measure a plate")
                -- no plate (plates off, target out of view): the landing plays in front of the player
                platesByUnit.target = nil
                addon.Catcher.PlayRopeEffect("target")
                for _ = 1, 60 do addon.Animate._onUpdate(nil, 0.02) end
                harness.equal(addon.Catcher.lastEffect.mode, "front"); harness.equal(addon.Catcher.lastEffect.why, "no nameplate")
                -- a client that refuses even the anchor: still a throw, in front, with the reason
                platesByUnit.target = lockedPlate
                addon.Catcher.PlayRopeEffect("target")
                for _ = 1, 60 do addon.Animate._onUpdate(nil, 0.02) end
                harness.equal(addon.Catcher.lastEffect.mode, "front")
                harness.truthy(addon.Catcher.lastEffect.why:find("Not allowed", 1, true), addon.Catcher.lastEffect.why)
                harness.equal(table.concat(refused, ","), "", "still nothing measured")
                C_NamePlate, CreateFrame = savedNamePlate, savedCreateFrame
                addon.Catcher.PlayRopeEffect("target")
                harness.truthy(addon.AzeCaught.JournalLines(1, "throw.effect")[1]:find("was played", 1, true),
                    "the throw effect runs: " .. tostring(addon.AzeCaught.JournalLines(1, "throw.effect")[1]))
                harness.truthy(pcall(_G.GuildGamesAzeCaughtThrow), "the key binding")
                -- kills of enemies that fought me: counted once, only for fought GUIDs
                do
                    local Api, Catcher = addon.Api, addon.Catcher
                    local savedGuid, savedDead = Api.UnitGuid, Api.IsDead
                    local guid = "Creature-0-1-2-3-88-00000000AA"
                    addon.AzeCaught.NoteFound({ npc = 88, name = "Boar" }, 1)
                    Api.UnitGuid = function() return guid end
                    Api.IsDead = function() return true end
                    harness.truthy(not Catcher.CheckKill("nameplate1"), "not fought: no kill")
                    Catcher.fought[guid] = 88
                    local okKill, counted = pcall(Catcher.CheckKill, "nameplate1")
                    local twice = Catcher.CheckKill("nameplate1")
                    Api.UnitGuid, Api.IsDead = savedGuid, savedDead
                    harness.truthy(okKill and counted, tostring(counted)); harness.truthy(not twice, "once")
                    harness.equal(addon.AzeCaught.State().collection[88].kills, 1)
                    local lines = 0
                    local tip = setmetatable({}, { __index = function() return function() lines = lines + 1 end end })
                    harness.truthy(addon.AzeCaughtPanel.ShowNpcInfo(tip, {}, 88, addon.AzeCaught.State().collection[88]) > 5)
                    -- the badges (icon based, animated): a new NPC fades in, a higher value pulses
                    local Panel = addon.AzeCaughtPanel
                    harness.truthy(Panel.widgets.historyBadges and Panel.widgets.historyBadges.kills, "badges built")
                    local boar = addon.AzeCaught.State().collection[88]
                    local okShow, mode = pcall(Panel.ShowHistoryBadges, 88, boar)
                    harness.truthy(okShow, tostring(mode)); harness.equal(mode, "new")
                    local pulsed = {}
                    local savedPulse = addon.Animate.Pulse
                    addon.Animate.Pulse = function(region) pulsed[#pulsed + 1] = region.key end
                    boar.kills = boar.kills + 1
                    local okSame, sameMode = pcall(Panel.ShowHistoryBadges, 88, boar)
                    addon.Animate.Pulse = savedPulse
                    harness.truthy(okSame, tostring(sameMode)); harness.equal(sameMode, "same")
                    harness.equal(#pulsed, 1); harness.equal(pulsed[1], "kills", "only the value that went up pulses")
                    harness.equal(Panel.ShowHistoryBadges(nil, nil), nil)
                    -- the arena view: fighter page, training, a fight from another player, the replay
                    do
                        local Arena, AzeCaught = addon.Arena, addon.AzeCaught
                        boar.caught = 1
                        if not (AzeCaught.Active() and AzeCaught.Active().npc == 88) then assert(AzeCaught.Select(88, 1)) end
                        local me = addon.Utility.Me()
                        local okView, viewError = pcall(Panel.SelectView, "arena")
                        harness.truthy(okView, "arena view: " .. tostring(viewError))
                        -- "guild" above opened the arena's Guild page (the guild list moved into the arena)
                        harness.equal(Panel.state.view, "arena"); harness.equal(addon.ArenaView.state.page, "guild")
                        -- the fighter left the arena: an old saved "fighter" page opens Guild
                        harness.truthy(pcall(addon.ArenaView.SelectPage, "fighter"))
                        harness.equal(addon.ArenaView.state.page, "guild", "no fighter page any more")
                        harness.equal(addon.ArenaView.widgets.pageButtons.fighter, nil)
                        -- the fighter block in the Companion view: four stat icons, a click trains
                        local okRefresh, refreshError = pcall(addon.ArenaView.RefreshFighter)
                        harness.truthy(okRefresh, tostring(refreshError))
                        local atkIcon = addon.ArenaView.widgets.statIcons and addon.ArenaView.widgets.statIcons.atk
                        harness.truthy(atkIcon and atkIcon.label, "the attack icon with its points label")
                        harness.equal(atkIcon.label:GetText(), "0/" .. Arena.MAXIMUM_TRAINING, "points/maximum below the icon")
                        local fighterState = addon.ArenaView.FighterState()
                        harness.truthy(fighterState and fighterState.fighter, "my companion is a fighter")
                        AzeCaught.Active().energy = 100
                        addon.Store.db.pool = addon.Store.db.pool or 0
                        local trained, trainError = pcall(addon.ArenaView.Train, "atk", function() end)
                        harness.truthy(trained, "train click: " .. tostring(trainError))
                        -- a refusal goes to the given line
                        local refusal
                        Arena.State().training = Arena.State().training or { stat = "atk", npc = AzeCaught.Active().npc, done = 1e9 }
                        harness.equal(addon.ArenaView.Train("def", function(text) refusal = text end), false, "busy while training")
                        harness.truthy(refusal and refusal:find(addon.Text["Already training."], 1, true), "the busy text: " .. tostring(refusal))
                        -- while one stat trains: its icon shows the time, the others are greyed out
                        local okFill, fillError = pcall(addon.ArenaView.RefreshFighter)
                        harness.truthy(okFill, tostring(fillError))
                        harness.truthy(addon.ArenaView.widgets.statIcons.atk.time:GetText() ~= "", "the time is on the training icon")
                        harness.equal(addon.ArenaView.widgets.statIcons.def.time:GetText(), "", "no time on the others")
                        -- the compact view's training menu: opens, shows the same, closes
                        local PetView = addon.PetView
                        harness.truthy(pcall(PetView.ToggleTraining))
                        harness.truthy(PetView.widgets.trainMenu:IsShown(), "the training menu opens")
                        harness.truthy(PetView.widgets.trainIcons.atk.time:GetText() ~= "", "the training time on the menu icon")
                        PetView.CloseTraining()
                        harness.equal(PetView.widgets.trainMenu:IsShown(), false, "and closes")
                        Arena.State().training = nil
                        -- the Shop and Inventory tabs, the catch items at the target, the target frame mode
                        do
                            local Items, ShopView, CatchItems, Catcher, Api = addon.Items, addon.ShopView, addon.CatchItems, addon.Catcher, addon.Api
                            harness.equal(Panel.RestorableView("fighter"), "companion"); harness.equal(Panel.RestorableView("shop"), "shop")
                            harness.truthy(pcall(Panel.SelectView, "shop"))
                            harness.equal(Panel.state.view, "shop")
                            harness.equal(ShopView.widgets.shop.rows[1].itemID, "meat", "the shop lists the catalog")
                            harness.equal(ShopView.Buy("trapRare"), false, "too expensive")
                            addon.Wallet.Earn(me, 2000 * 10000, "dev", addon.Utility.Now())
                            harness.equal(ShopView.Buy("meat"), true); harness.equal(ShopView.Buy("trap"), true)
                            harness.equal(Items.Count("meat"), 1)
                            harness.truthy(pcall(Panel.SelectView, "inventory"))
                            harness.equal(ShopView.widgets.inventory.rows[1].itemID, "meat", "the inventory lists what I own")
                            harness.equal(ShopView.widgets.inventory.empty:IsShown(), false)
                            -- a full-health enemy as the target: the bag shows (traps need no fight)
                            local savedSnapshot, savedGuid, savedDungeon, savedPlate = Api.UnitSnapshot, Api.UnitGuid, Api.InDungeon, Api.NamePlateFor
                            local foeTarget = { guid = "Creature-0-1-2-3-4711-AB", npc = 4711, name = "Wolf", level = 10,
                                classification = "rare", health = 1, hostile = true }
                            Api.UnitSnapshot = function(unit) if unit == "target" then return foeTarget end end
                            Api.UnitGuid = function(unit) if unit == "target" then return foeTarget.guid end end
                            Api.InDungeon = function() return false end
                            Api.NamePlateFor = function() return stub() end
                            harness.truthy(pcall(Catcher.RefreshIcons))
                            harness.truthy(CatchItems.widgets.holder:IsShown() and CatchItems.widgets.bag:IsShown(), "the bag at the target")
                            harness.truthy(pcall(CatchItems.Toggle))
                            harness.truthy(CatchItems.widgets.row:IsShown(), "the item row opens")
                            local trapButton = CatchItems.widgets.itemButtons[2]
                            harness.equal(trapButton.itemID, "trap")
                            harness.truthy(trapButton.refusal, "a normal trap is greyed out on a rare enemy")
                            harness.equal(CatchItems.UseItem("trap"), false, "and refused")
                            harness.equal(Items.Count("trap"), 1, "the trap is kept")
                            foeTarget.classification = "normal"
                            local okTrap, trapped = pcall(CatchItems.UseItem, "trap")
                            harness.truthy(okTrap and trapped, "trapped: " .. tostring(trapped))
                            harness.equal(Items.Count("trap"), 0)
                            harness.truthy((addon.AzeCaught.State().collection[4711].caught or 0) >= 1, "caught without a fight")
                            harness.equal(CatchItems.widgets.holder:IsShown(), false, "a trapped enemy has no catch items any more")
                            -- the meat on a new target: the clock with the seconds left
                            foeTarget.guid, foeTarget.npc = "Creature-0-1-2-3-4712-AB", 4712
                            harness.truthy(pcall(Catcher.RefreshIcons))
                            harness.truthy(CatchItems.UseItem("meat"), "the meat is used")
                            harness.truthy(CatchItems.widgets.clock:IsShown(), "the boost clock")
                            harness.equal(CatchItems.widgets.clock.count:GetText(), "20")
                            harness.equal(CatchItems.widgets.bag:IsShown(), false, "no items left: only the clock")
                            -- target frame mode: the weak target's icon is at the target frame, nameplate icons are hidden
                            local savedTargetFrame = rawget(_G, "TargetFrame")
                            rawset(_G, "TargetFrame", stub())
                            rawget(_G, "TargetFrame").GetObjectType = function() return "Frame" end
                            addon.AzeCaught.SetIconSetting("atTarget", true)
                            foeTarget.health = 0.2
                            harness.truthy(pcall(Catcher.RefreshIcons))
                            harness.truthy(Catcher.icons.target and Catcher.icons.target:IsShown(), "the rope icon at the target frame")
                            harness.equal(Catcher.IconHiddenReason(addon.AzeCaught.IconSettings(), "nameplate", foeTarget, true), "target frame mode")
                            addon.AzeCaught.SetIconSetting("atTarget", false)
                            harness.truthy(pcall(Catcher.RefreshIcons))
                            harness.equal(Catcher.icons.target:IsShown(), false, "nameplate mode: no icon for the target unit itself")
                            rawset(_G, "TargetFrame", savedTargetFrame)
                            Api.UnitSnapshot, Api.UnitGuid, Api.InDungeon, Api.NamePlateFor = savedSnapshot, savedGuid, savedDungeon, savedPlate
                            Items.Boosts().meat = nil
                            harness.truthy(pcall(Catcher.RefreshIcons))
                        end
                        local foe = { npc = 5, n = "Bear", cls = "elite", disp = 0, ty = 1, al = 3, atk = 30, def = 30, spd = 30, vit = 30, ab = "rend" }
                        local records = { ["Foe-R"] = { name = "Foe-R", caught = { c = { npc = 5 }, weeks = {} },
                            arena = { w = 0, l = 0, ver = addon.VERSION, ch = {}, an = {}, bt = {} } } }
                        -- a team needs three companions
                        AzeCaught.State().collection[AzeCaught.Active().npc].caught = 3
                        AzeCaught.Reconcile()
                        local savedRecords, savedNow = addon.Games.AllRecords, addon.Utility.Now
                        addon.Games.AllRecords = function() return records end
                        local start = savedNow()
                        -- the foe challenges me: an incoming fight with Accept
                        records["Foe-R"].arena.ch["Foe-R#" .. start] = { to = me, at = start, wg = 0, t = { foe, foe, foe } }
                        harness.truthy(pcall(addon.ArenaView.SelectPage, "fights"))
                        harness.truthy(addon.ArenaView.widgets.acceptButton, "accept is in the dialog below the list (next to the counter offer)")
                        harness.equal(addon.ArenaView.state.selected, "Foe-R#" .. start, "the incoming challenge is selected")
                        -- the selected fight in the framed box: the challenger's team as a carousel left, mine unknown yet
                        local fightCards = addon.ArenaView.widgets.fightCards
                        harness.truthy(addon.ArenaView.widgets.fightBox, "the framed fight box")
                        harness.truthy(addon.ArenaView.widgets.answerPanel:IsShown(), "the framed answer panel for an incoming challenge")
                        harness.equal(fightCards.left.fighter.n, "Bear"); harness.equal(addon.ArenaView.state.cardShown.right, nil, "their team: the note")
                        harness.equal(addon.ArenaView.state.cardShown.left, 1)
                        local okAnswer, answerError = pcall(addon.ArenaView.Decide, true)
                        harness.truthy(okAnswer, tostring(answerError))
                        harness.truthy(addon.TeamDialog.IsOpen(), "accepting opens the team dialog")
                        harness.equal(#addon.TeamDialog.state.picks, 3, "three companions picked to start with")
                        -- their team as a carousel: one fighter at a time, the arrows wrap around
                        harness.equal(addon.TeamDialog.state.shown, 1)
                        harness.equal(addon.TeamDialog.ShowTheirs(1), 2)
                        harness.equal(addon.TeamDialog.ShowTheirs(1), 3)
                        harness.equal(addon.TeamDialog.ShowTheirs(1), 1, "wraps to the first")
                        harness.equal(addon.TeamDialog.ShowTheirs(-1), 3, "wraps to the last")
                        harness.truthy(addon.TeamDialog.widgets.card:IsShown(), "the card is shown")
                        -- two carousels side by side: the challenger (the foe) left, mine right, each with its player below
                        local cards = addon.TeamDialog.widgets.cards
                        harness.equal(cards.left.owner, "theirs"); harness.equal(cards.right.owner, "mine")
                        harness.equal(cards.left.fighter.n, "Bear")
                        harness.equal(addon.TeamDialog.ShowMine(1), 2); harness.equal(addon.TeamDialog.ShowMine(-2), 3, "mine wraps too")
                        harness.truthy(cards.right.fighter, "my pick is shown")
                        addon.TeamDialog.ClearSlot(3)
                        harness.equal(addon.TeamDialog.Confirm(), false, "two are not a team")
                        addon.TeamDialog.Toggle(addon.TeamDialog.Rows()[3].uid)
                        local okConfirm, confirmed = pcall(addon.TeamDialog.Confirm)
                        harness.truthy(okConfirm and confirmed, "accepted with the team: " .. tostring(confirmed))
                        harness.truthy(Arena.State().an["Foe-R#" .. start], "accepted")
                        local savedServerTime = rawget(_G, "GetServerTime")
                        rawset(_G, "GetServerTime", function() return start + 400 end)
                        addon.Utility.Now = function() return start + 400 end
                        local okWatch, events = pcall(addon.ArenaView.Watch, "Foe-R#" .. start)
                        harness.truthy(okWatch and events and events > 0, "replay: " .. tostring(events))
                        -- the models act on every step: attack / hurt, the death once
                        local played = {}
                        local savedPlay = addon.ArenaView.PlayAnimation
                        addon.ArenaView.PlayAnimation = function(model, key, back) played[#played + 1] = key return savedPlay(model, key, back) end
                        for _ = 1, 5 do harness.truthy(pcall(addon.ArenaView.Step)) end
                        addon.ArenaView.PlayAnimation = savedPlay
                        local acted = false
                        for _, key in ipairs(played) do if key == "attack" or key == "cast" or key == "hurt" or key == "critical" then acted = true end end
                        harness.truthy(acted, "the models act: " .. table.concat(played, ","))
                        local model = addon.ArenaView.widgets.replayLeft.model
                        addon.ArenaView.ResetModel(model)
                        harness.truthy(addon.ArenaView.PlayDeath(model), "dies")
                        harness.truthy(not addon.ArenaView.PlayDeath(model), "dies once")
                        harness.equal(addon.ArenaView.PlayAnimation(model, "hurt", 0.4), nil, "a dead model stays dead")
                        harness.truthy(pcall(addon.ArenaView.FinishReplay)); harness.truthy(pcall(addon.ArenaView.StopReplay))
                        local okTick, tickError = pcall(addon.Catcher.ArenaTick, true)
                        harness.truthy(okTick, "arena tick: " .. tostring(tickError))
                        harness.equal(Arena.State().w + Arena.State().l, 1, "the fight was settled")
                        addon.Games.AllRecords, addon.Utility.Now = savedRecords, savedNow
                        rawset(_G, "GetServerTime", savedServerTime)
                        -- the fight request on the Fights page: the dummy in the member dropdown, Fight! opens the team
                        -- picker with my wager, Send sends it (the swords clash) and ends the guide
                        local ArenaView = addon.ArenaView
                        addon.Games.simulated[Arena.DUMMY_NAME] = Arena.DummyRecord(Arena.Fighter(AzeCaught.Active()), savedNow())
                        addon.UIHelpers.Settings().arenaGuide = nil
                        harness.equal(Panel.GuideStep(), "arena")
                        harness.truthy(pcall(Panel.SelectView, "guild")); harness.equal(Panel.GuideStep(), "request")
                        harness.truthy(pcall(ArenaView.SelectPage, "fights"))
                        harness.truthy(pcall(Panel.UpdateGuide))
                        harness.truthy(ArenaView.widgets.memberDropdown and ArenaView.widgets.requestButton, "the request row is built")
                        harness.equal(ArenaView.Request(), false, "Fight! needs a member first")
                        harness.truthy(pcall(ArenaView.ToggleMemberMenu))
                        harness.truthy(ArenaView.widgets.memberMenu:IsShown(), "the member list opens")
                        local listed
                        for _, entry in ipairs(ArenaView.Candidates()) do if entry.name == Arena.DUMMY_NAME then listed = entry end end
                        harness.truthy(listed and not listed.reason, "the dummy can be picked")
                        harness.truthy(ArenaView.PickMember(Arena.DUMMY_NAME))
                        harness.truthy(not ArenaView.widgets.memberMenu:IsShown(), "the list closes on a pick")
                        harness.truthy(ArenaView.Request(), "the team picker opens")
                        harness.truthy(addon.TeamDialog.IsOpen(), "the team picker is open")
                        harness.truthy(addon.TeamDialog.widgets.wager:IsShown(), "with my wager")
                        addon.TeamDialog.SetWager("abc"); harness.equal(addon.TeamDialog.Confirm(), false, "a bad wager stays")
                        addon.TeamDialog.SetWager(0); harness.equal(addon.TeamDialog.Confirm(), false, "below 1g stays")
                        addon.TeamDialog.SetWager(1)
                        local okSend, sentOk = pcall(addon.TeamDialog.Confirm)
                        harness.truthy(okSend and sentOk, "sent: " .. tostring(sentOk))
                        harness.truthy(not addon.TeamDialog.IsOpen(), "the picker closes")
                        local sent = 0
                        for _, challenge in pairs(Arena.State().ch) do
                            if challenge.to == Arena.DUMMY_NAME then sent = sent + 1; harness.equal(challenge.wg, 10000) end
                        end
                        harness.equal(sent, 1)
                        harness.equal(Panel.GuideStep(), nil, "the guide is done after the first request")
                        harness.equal(addon.UIHelpers.Settings().arenaGuide, "done")
                        harness.truthy(pcall(addon.Animate.FinishTween, "clash:fightRequest"), "the clash ends")
                        -- greyed members: every reason in the list, a greyed one can't be picked
                        Arena.DevMembers(addon.Games.simulated, savedNow())
                        local reasons = {}
                        for _, entry in ipairs(ArenaView.Candidates()) do if entry.reason then reasons[entry.reason] = entry.name end end
                        harness.truthy(reasons.version and reasons.fewcompanions and reasons.theybusy and reasons.offline,
                            "greyed for every reason")
                        harness.equal(ArenaView.PickMember(reasons.version), false)
                        harness.truthy(ArenaView.PickMember(Arena.DEV_SPARRING), "the sparring member can be picked")
                        ArenaView.state.opponent = nil
                        harness.truthy(ArenaView.CandidateText({ name = reasons.version, reason = "version" }) ~= "", "the hover text")
                        -- an open fight between two others: the framed bet panel, and a bet through it joins the pot
                        local openID
                        for id, fight in pairs(Arena.Fights(addon.Games.AllRecords(), me, savedNow())) do
                            if fight.state == "open" and fight.a ~= me and fight.b ~= me then openID = id end
                        end
                        harness.truthy(openID, "the fake members' fight is open")
                        ArenaView.state.selected = openID
                        harness.truthy(pcall(ArenaView.SelectPage, "fights"))
                        harness.truthy(ArenaView.widgets.betPanel:IsShown(), "the bet panel shows")
                        ArenaView.widgets.betBox:SetText("0")
                        harness.truthy(pcall(ArenaView.Bet, "a"))
                        harness.truthy(ArenaView.state.refusal and ArenaView.state.refusal.id == openID, "a refused bet: one red line in the box")
                        harness.truthy(ArenaView.widgets.betPanel:IsShown(), "the panel stays for another try")
                        ArenaView.widgets.betBox:SetText("2")
                        harness.truthy(pcall(ArenaView.Bet, "a"))
                        harness.equal(Arena.State().bt[openID].c, 20000, "the bet is placed")
                        harness.truthy(not ArenaView.widgets.betPanel:IsShown(), "after the bet the panel goes")
                        harness.truthy(ArenaView.widgets.fightCards.left.gold:IsShown() and ArenaView.widgets.fightCards.right.gold:IsShown(),
                            "both sides show their gold on the name plate")
                        harness.equal(addon.TeamDialog.GoldNumber(10000), "1"); harness.equal(addon.TeamDialog.GoldNumber(25000), "2.5")
                        harness.equal(addon.TeamDialog.GoldNumber(1500), "0.15", "the badge shows plain gold numbers")
                        -- Fights: my waiting challenge has Stop in its row and in the details; it stops
                        local stopID
                        for id, challenge in pairs(Arena.State().ch) do if challenge.to == Arena.DUMMY_NAME then stopID = id end end
                        ArenaView.state.selected = stopID
                        harness.truthy(pcall(ArenaView.SelectPage, "fights"))
                        harness.equal(ArenaView.widgets.stopButton, nil, "Stop is only in the fight row, not in the fight box")
                        local okStop, stopError = pcall(ArenaView.Withdraw, stopID)
                        harness.truthy(okStop, tostring(stopError))
                        harness.truthy(Arena.State().ch[stopID].wd, "stopped")
                        if addon.IS_DEVELOPMENT_BUILD then   -- the dev icon tools on the Fights page, each runs without an error
                            harness.truthy(ArenaView.widgets.dummyButton and ArenaView.widgets.skipButton, "dev icons built")
                            for _, word in ipairs({ "request", "accept", "decline", "skip", "crowd", "latebet", "members", "expire", "reveal", "clear" }) do
                                harness.truthy(ArenaView.widgets.devTools[word], "dev icon " .. word)
                                local okTool, toolError = pcall(addon.Catcher.DevArena, word)
                                harness.truthy(okTool, word .. ": " .. tostring(toolError))
                            end
                            harness.equal(addon.Games.simulated[Arena.DUMMY_NAME], nil, "clear removed the dummy")
                        end
                        harness.truthy(pcall(Panel.SelectView, "guild"))
                        Arena.DevClear(addon.Games.simulated)
                        Panel.state.guildRow = nil
                        harness.truthy(pcall(Panel.Refresh))
                    end
                end
                -- the identity probe: runs on any client, secret or missing functions are named, never raises
                do
                    local savedName, savedSecret = UnitName, rawget(_G, "issecretvalue")
                    local hidden = {}
                    UnitName = function() return hidden end
                    rawset(_G, "issecretvalue", function(value) return value == hidden end)
                    local okProbe, probe = pcall(addon.Api.IdentityProbe, "target")
                    UnitName = savedName; rawset(_G, "issecretvalue", savedSecret)
                    harness.truthy(okProbe, tostring(probe))
                    harness.equal(probe.UnitName, "secret")
                    harness.equal(probe["C_Secrets.ShouldUnitIdentityBeSecret"], "missing")
                    harness.truthy(pcall(addon.SlashCommands.caught, "identity"), "/gg caught identity")
                end
                -- why an icon stays hidden (none in the dungeon): every reason, journaled once per change
                do
                    local Reason, on = addon.Catcher.IconHiddenReason, { shown = true }
                    local npc = { guid = "Creature-0-1-2-3-77-0000000003", npc = 77, health = 0.2 }
                    harness.equal(Reason({ shown = false }, {}, npc, true), "turned off")
                    harness.equal(Reason(on, {}, nil, nil), "unit unreadable (GUID hidden or no unit)")
                    harness.equal(Reason(on, {}, { guid = "Player-1-2" }, true), "not an NPC")
                    harness.equal(Reason(on, {}, { guid = npc.guid, npc = 77, hostile = false }, true), "not hostile")
                    harness.equal(Reason(on, {}, { guid = npc.guid, npc = 77, health = 0.5 }, false), "health above the threshold")
                    harness.equal(Reason(on, {}, { guid = npc.guid, npc = 77 }, nil), "health hidden and not the target")
                    harness.equal(Reason(on, nil, npc, true), "no nameplate frame")
                    harness.equal(Reason(on, {}, { guid = npc.guid, npc = 77, health = 0 }, true), "dead", "health 0 with a hidden dead flag")
                    addon.AzeCaught.thrown[npc.guid] = 1
                    harness.equal(Reason(on, {}, npc, true), "already tried", "a failed throw hides the icon")
                    addon.AzeCaught.throws[npc.guid] = { at = 1, npc = 77 }
                    harness.equal(Reason(on, {}, npc, true), nil, "an armed throw keeps the icon")
                    addon.AzeCaught.thrown[npc.guid], addon.AzeCaught.throws[npc.guid] = nil, nil
                    harness.equal(Reason(on, {}, npc, true), nil)
                    local before = #addon.AzeCaught.State().journal
                    addon.Catcher.NoteIconReason("nameplate9", nil, "unit unreadable (GUID hidden or no unit)")
                    addon.Catcher.NoteIconReason("nameplate9", nil, "unit unreadable (GUID hidden or no unit)")
                    harness.truthy(addon.AzeCaught.JournalLines(1, "icon.state")[1]:find("GUID hidden", 1, true))
                    addon.Catcher.NoteIconReason("nameplate9", npc, "health above the threshold")
                    harness.truthy(#addon.AzeCaught.State().journal - before <= 1, "once per change; the normal case is not written")
                end
                -- the icon style: ring by chance, pulse + one ping at the best moment, arrow until the first throw
                do
                    local shownPaths = {}
                    local picture = stub(); rawset(picture, "SetTexture", function(_, path) shownPaths[#shownPaths + 1] = path return true end)
                    local button = { border = stub(), glow = stub(), arrow = stub(), arrowGlow = stub(), iconSize = 26, texture = picture,
                        SetAlpha = function(self, alpha) self.alpha = alpha end }
                    local pings, savedPlay = 0, addon.Api.PlaySoundNamed
                    addon.Api.PlaySoundNamed = function() pings = pings + 1 end
                    local caughtState = addon.AzeCaught.State()
                    local savedHint, savedFirst = caughtState.throwHintDone, caughtState.firstCatchDone
                    caughtState.throwHintDone, caughtState.firstCatchDone = nil, nil
                    local weak = { guid = "Creature-0-1-2-3-77-0000000002", health = 0.05, classification = "elite" }
                    addon.Catcher.StyleIcon(button, weak); addon.Catcher.StyleIcon(button, weak)
                    harness.truthy(button.pulsing, "pulses at the best moment"); harness.equal(pings, 1, "one ping per NPC")
                    harness.truthy(math.abs(button.chance - 0.85) < 1e-9, "elite at 5%: " .. tostring(button.chance))
                    harness.truthy(button.hinting and button.arrow:IsShown(), "the arrow before the first throw")
                    caughtState.throwHintDone = true
                    addon.Catcher.StyleIcon(button, { guid = weak.guid, health = 0.3 })
                    harness.truthy(not button.hinting and not button.arrow:IsShown(), "no arrow after the first throw")
                    harness.truthy(not button.pulsing and not button.glow:IsShown(), "no glow away from the best moment")
                    addon.Catcher.StyleIcon(button, { guid = weak.guid, health = nil })
                    harness.equal(button.chance, nil, "hidden health: no chance shown")
                    -- catch mode: the net icon while armed, the rope again after; shaking only near the end
                    harness.equal(shownPaths[#shownPaths], addon.Catcher.ROPE_ICON)
                    addon.AzeCaught.throws[weak.guid] = { at = 100, npc = 77 }
                    addon.Catcher.StyleIcon(button, weak)
                    harness.equal(shownPaths[#shownPaths], addon.Catcher.CATCH_ICON, "catch mode shows the net"); harness.equal(button.armedAt, 100)
                    local pathCount = #shownPaths
                    addon.Catcher.StyleIcon(button, weak); harness.equal(#shownPaths, pathCount, "the texture is set once per change")
                    addon.AzeCaught.throws[weak.guid] = nil
                    addon.Catcher.StyleIcon(button, weak)
                    harness.equal(shownPaths[#shownPaths], addon.Catcher.ROPE_ICON); harness.equal(button.armedAt, nil)
                    local Shake = addon.Catcher.ShakeAmplitude
                    harness.equal(Shake(3), 0); harness.equal(Shake(1.0), 0, "still at 1 s left")
                    harness.truthy(Shake(0.5) > 1 and Shake(0.5) < Shake(0.1), "rising toward the end")
                    harness.equal(Shake(0), 5); harness.equal(Shake(-1), 5); harness.equal(Shake(nil), 0)
                    addon.Catcher.ShakeIcon(button, 4); harness.truthy(button.shaken)
                    addon.Catcher.ShakeIcon(button, 0); harness.truthy(not button.shaken, "back in place")
                    caughtState.throwHintDone, caughtState.firstCatchDone = savedHint, savedFirst
                    addon.Api.PlaySoundNamed = savedPlay
                end
                if development then
                    for _, command in ipairs({ "add", "time 30", "give 5", "force", "need hunger 10", "week", "effect", "effect escape", "effect snap target", "hint", "hint", "setup items", "setup boost", "setup" }) do
                        local okCommand, commandError = pcall(addon.SlashCommands.caught, command)
                        harness.truthy(okCommand, "/ggd caught " .. command .. ": " .. tostring(commandError))
                    end
                    -- /ggd caught setup: gold, every item, a companion, the boosters with "boost"
                    harness.truthy(addon.AzeCaught.Active(), "setup leaves a companion")
                    harness.truthy(#addon.AzeCaught.Roster() >= addon.Arena.TEAM_SIZE, "setup fills the roster up to one arena team")
                    for _, item in ipairs(addon.Items.CATALOG) do
                        harness.truthy(addon.Items.Count(item.id) >= 3, "setup gives " .. item.id)
                    end
                    harness.truthy(addon.Items.CatchBoosted(addon.Utility.Now()), "setup boost starts the meat")
                    -- "/ggd reset" did nothing (only /ggd caught reset existed); the dev build takes both
                    addon.AzeCaught.State().firstCatchDone, addon.AzeCaught.State().throwHintDone = true, true
                    addon.SlashCommands.reset("")
                    harness.equal(addon.AzeCaught.State().firstCatchDone, nil, "/ggd reset gives the guaranteed first catch back")
                    harness.equal(addon.AzeCaught.State().throwHintDone, nil, "and the first-throw arrow")
                else
                    harness.equal(addon.SlashCommands.reset, nil, "the live build has no reset")
                end
                harness.truthy(pcall(addon.UI.AddCompanionTooltip, GameTooltip), "the minimap tooltip")
                addon.GamesTab.SelectGame("coin")
                local okMinimap, minimapError = pcall(addon.UI.BuildMinimapButton)
                harness.truthy(okMinimap and addon.UI.minimapButton, "the minimap button was not built: " .. tostring(minimapError))
                if development then
                    harness.truthy(addon.SlashCommands.anim and addon.SlashCommands.game, "dev commands anim/game missing")
                    harness.truthy(pcall(addon.SlashCommands.game, "sim 3"), "game sim failed")
                    harness.equal(addon.Utility.Count(addon.Store.db.games), 1, "simulated players must not be stored")
                else
                    harness.equal(addon.SlashCommands.anim, nil, "dev command in the live build")
                end
                harness.truthy(addon.SlashCommands.version and addon.SlashCommands.comm and addon.SlashCommands.clean, "slash commands missing")
                local errors = {}
                for _, line in ipairs(addon.Store.db.debug) do if line:find(" ERROR ", 1, true) then errors[#errors + 1] = line end end
                harness.equal(#errors, 0, "errors in the log: " .. table.concat(errors, " || "))
                -- a blocked action (caught in Init.lua) lands in the log with the function name
                harness.truthy(type(addon.blockedEarly) == "table", "Init.lua keeps early blocks")
                addon.OnActionBlocked({ kind = "forbidden", ["function"] = "TestFunction()", combat = "false" })
                harness.truthy(addon.Store.db.debug[#addon.Store.db.debug]:find("function=TestFunction()", 1, true), "blocked action logged")
            end
        end)
    end,

    -- live and dev installed together -> "Binding AZECAUGHT_THROW was attempted to be loaded more than
    -- once". Bindings.xml carries the live names once each (deploy.ps1 swaps them for the dev copy) and the code
    -- defines the binding's globals with the names of its own build.
    ["load: the key binding has its own names per build (Bindings.xml, deploy.ps1, Catcher.BindingNames)"] = function(harness)
        local handle = assert(io.open("Bindings.xml", "rb")); local xml = handle:read("*a"); handle:close()
        local function count(text, plain) local n, from = 0, 1
            while true do local at = text:find(plain, from, true); if not at then return n end; n, from = n + 1, at + 1 end end
        handle = assert(io.open("tools/deploy.ps1", "rb")); local deploy = handle:read("*a"); handle:close()
        local live = { header = "GUILDGAMES", name = "AZECAUGHT_THROW", func = "GuildGamesAzeCaughtThrow" }
        local dev = { header = "GUILDGAMESDEV", name = "AZECAUGHT_THROW_DEV", func = "GuildGamesDevAzeCaughtThrow" }
        harness.equal(count(xml, '"' .. live.name .. '"'), 1); harness.equal(count(xml, '"' .. live.header .. '"'), 1)
        harness.equal(count(xml, "then " .. live.func .. "() end"), 1, "the binding calls the function")
        for _, value in pairs(dev) do harness.truthy(deploy:find(value, 1, true), "deploy.ps1 writes the dev name " .. value) end
        harness.truthy(live.name ~= dev.name and live.header ~= dev.header and live.func ~= dev.func)
    end,

    -- the generated GuildGames-Dev.toc (tools/deploy.ps1) goes stale when the live TOC gains a file
    ["load: the generated GuildGames-Dev.toc (when present) lists the same files as GuildGames.toc"] = function(harness)
        local handle = io.open("GuildGames-Dev.toc", "rb")
        if not handle then return end
        handle:close()
        harness.equal(table.concat(tocFiles("GuildGames-Dev.toc"), "\n"), table.concat(tocFiles("GuildGames.toc"), "\n"),
            "GuildGames-Dev.toc is stale: run powershell tools/deploy.ps1, then restart the game")
    end,

    -- RF5: outside a guild (or before the roster) nothing is sent and nothing fails
    ["load: not in a guild -> the channel stays inactive and a play is still stored"] = function(harness)
        local addon = harness.addon({ now = 1794873600 })
        addon.Store.db.me = "Me-R"
        addon.Api = { IsGuilded = function() return false end, GetPlayerInformation = function() return { name = "Me-R" } end }
        addon.Communication.ready = true
        addon.Communication.Start()
        harness.equal(addon.Communication.active, false)
        addon.Communication.RequestHelloSoon()
        harness.equal(#addon.Communication.queue, 0)
        harness.truthy(addon.Games.Flip("Me-R", 100, "H", 1794873600, function() return 0.1 end))
    end,

    ["load: no file reads an unknown lowercase global (a removed local helper)"] = function(harness)
        local known = {}
        for name in ([[type pairs ipairs tostring tonumber select pcall xpcall error assert setmetatable getmetatable unpack print
            next rawget rawset math string table os debug date time tinsert wipe debugstack geterrorhandler loadstring strtrim
            debugprofilestop hooksecurefunc]]):gmatch("%S+") do known[name] = true end
        local unknown = {}
        for _, file in ipairs(tocFiles("GuildGames.toc")) do
            if not file:match("^Libs/") then
                local listing = assert(io.popen('luajit -bl "' .. file .. '"'))
                for name in listing:read("*a"):gmatch('GGET[^\n]-"([a-z][%w_]*)"') do
                    if not known[name] then unknown[#unknown + 1] = file .. ": " .. name end
                end
                listing:close()
            end
        end
        harness.equal(#unknown, 0, "unknown globals (missing local?): " .. table.concat(unknown, ", "))
    end,

    -- Retail-based Forever client (build 70959): registering the combat log is FORBIDDEN for addons (the "reserved for
    -- the Blizzard UI" dialog at load). No file may register it or read it.
    ["load: no file registers or reads the combat log (forbidden on this client)"] = function(harness)
        local offenders = {}
        for _, file in ipairs(tocFiles("GuildGames.toc")) do
            if not file:match("^Libs/") then
                local text = slurp(file)
                for _, forbidden in ipairs({ "COMBAT_LOG_EVENT", "CombatLogGetCurrentEventInfo" }) do
                    if text:find(forbidden, 1, true) then offenders[#offenders + 1] = file .. ": " .. forbidden end
                end
            end
        end
        harness.equal(#offenders, 0, "forbidden combat log use: " .. table.concat(offenders, ", "))
    end,

    -- secret values (in combat, in instances): reading a unit never raises, a secret reads as unknown
    ["load: unit reads survive secret values"] = function(harness)
        local addon = harness.addon({ now = 1794873600 })
        local secret = setmetatable({}, { __index = function() error("indexed a secret") end,
            __lt = function() error("compared a secret") end, __le = function() error("compared a secret") end,
            __div = function() error("arithmetic on a secret") end, __eq = function() error("compared a secret") end })
        local saved = {}
        local globals = { issecretvalue = function(value) return value == secret end, UnitExists = function() return true end,
            UnitGUID = function() return "Creature-0-1-2-3-4711-AB" end, UnitHealth = function() return secret end,
            UnitHealthMax = function() return secret end, UnitLevel = function() return secret end, UnitName = function() return secret end,
            UnitClassification = function() return secret end, UnitCanAttack = function() return secret end,
            UnitIsDead = function() return secret end }
        for key, value in pairs(globals) do saved[key] = _G[key]; _G[key] = value end
        local ok, snapshot = pcall(function()
            assert(loadfile("Core/Game/Api.lua"))("GuildGames", addon)
            return addon.Api.UnitSnapshot("target")
        end)
        for key in pairs(globals) do _G[key] = saved[key] end
        harness.truthy(ok, "UnitSnapshot raised: " .. tostring(snapshot))
        harness.truthy(snapshot, "a unit with secret details is still a unit")
        harness.equal(snapshot.npc, 4711)
        harness.equal(snapshot.health, nil, "a secret health is unknown, not a number")
        harness.equal(snapshot.dead, nil); harness.equal(snapshot.name, nil); harness.equal(snapshot.level, nil)
        harness.equal(snapshot.classification, "normal")
    end,

    -- the catch dump: every readable unit value; secrets, missing functions and errors are named
    ["load: the unit dump names every value, a secret, a missing function and an error"] = function(harness)
        local addon = harness.addon({ now = 1794873600 })
        local secret = {}
        local saved = {}
        local globals = { issecretvalue = function(value) return value == secret end, UnitExists = function() return true end,
            UnitGUID = function() return "Creature-0-1-2-3-4711-AB" end, UnitName = function() return "Wolf" end,
            UnitLevel = function() return 12 end, UnitHealth = function() return secret end, UnitHealthMax = function() return 300 end,
            UnitCreatureType = function() return "Beast" end, UnitCreatureFamily = function() return "Wolf" end,
            UnitPowerType = function() return 0, "MANA" end, UnitSex = function() error("boom") end, UnitRace = nil,
            UnitStat = function() return 5, 5, 0, 0 end }
        for key, value in pairs(globals) do saved[key] = _G[key]; _G[key] = value end
        local ok, dump = pcall(function()
            assert(loadfile("Core/Game/Api.lua"))("GuildGames", addon)
            return addon.Api.UnitDump("target")
        end)
        for key in pairs(globals) do _G[key] = saved[key] end
        harness.truthy(ok, "UnitDump raised: " .. tostring(dump))
        harness.equal(dump.name, "Wolf"); harness.equal(dump.level, "12"); harness.equal(dump.npc, "4711")
        harness.equal(dump.health, "secret"); harness.equal(dump.healthMax, "300")
        harness.equal(dump.creatureType, "Beast"); harness.equal(dump.family, "Wolf"); harness.equal(dump.powerType, "0/MANA")
        harness.equal(dump.sex, "error"); harness.equal(dump.race, "missing")
        harness.equal(dump.strength, "5/5/0/0", "base/effective/buff/debuff"); harness.truthy(dump.unit == "target")
    end,
}
