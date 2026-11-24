local addonName, addon = ...

-- Recipe drop alerts on this client (the pure part is Core/Data/RecipeDrops.lua):
--   * my loot: a recipe item from my own loot line that reaches my bags and does not bind on pickup is announced to the
--     guild (DROP); a chat line says so, and the item's tooltip lists who answered;
--   * a member's drop: my own tooltip decides (RecipeCheck): I can learn it -> I answer "g" and get an alert (chat line,
--     minimap icon); my skill is too low -> I answer "r"; otherwise silence.
-- Everything is read from this client's own tooltips; nothing but ids, a status letter and a skill number is sent.
---@class DropsModule
local Drops = {}
addon.Drops = Drops

local Text, Format = addon.Text, addon.Locale.Format
local RecipeDrops, RecipeCheck = addon.RecipeDrops, addon.RecipeCheck

local BAG_CHECK_SECONDS = { 0, 1, 3, 10 }   -- seconds after the loot line at which my bags are looked at
local READ_RETRY_SECONDS, READ_TRIES = 2, 3  -- item data not loaded yet: ask again
local WAITING_SECONDS = 20                   -- the tooltip says "waiting for answers" this long after my drop
local GREEN, RED, GREY, GOLD = { 0.2, 1, 0.6 }, { 1, 0.33, 0.33 }, { 0.6, 0.6, 0.6 }, { 1, 0.82, 0 }

---@return table|nil
local function interfaceSettings() return addon.db and addon.db.ui end
---@param settingKey string
---@return boolean
local function setting(settingKey) return RecipeDrops.Get(interfaceSettings(), settingKey) end
---@return number
local function now() return addon.Utility.Now() end

---@param seconds number
---@param step function
local function after(seconds, step)
    if seconds <= 0 then return addon.Log.Protected("drops.step", "a recipe drop step failed", step) end
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(seconds, function() addon.Log.Protected("drops.step", "a recipe drop step failed", step) end)
end

---@return table<string, ProfessionEntry>|nil
local function myProfessions()
    local myRecord = addon.Store.db and addon.Store.GetCharacter(addon.Store.db.me)
    return myRecord and myRecord.professions
end

---@param itemID integer
---@return string
local function itemText(itemID) return addon.Api.ItemLink(itemID) or ("[" .. (addon.Api.ItemName(itemID) or ("item " .. itemID)) .. "]") end

---@param playerName string
---@return string
local function shortName(playerName) return addon.Utility.ShortName(playerName) or playerName end

-- A clickable player name for a chat line (click: whisper); peer text made chat safe.
---@param playerName string
---@return string
local function playerLink(playerName)
    local safeName = addon.Utility.ChatSafe(playerName)
    return ("|Hplayer:%s|h[%s]|h"):format(safeName, addon.Utility.ChatSafe(shortName(playerName)))
end

-- Reads the recipe item's tooltip on this client, asking again while the item data is not loaded; then done(reading|nil).
---@param itemID integer
---@param done fun(reading: RecipeReading|nil)
---@param triesLeft? integer
function Drops.ReadRecipe(itemID, done, triesLeft)
    triesLeft = triesLeft or READ_TRIES
    local tooltipLines = addon.Api.ItemTooltipLinesWithColor(itemID)
    if tooltipLines then return done(RecipeCheck.ReadTooltip(tooltipLines, addon.Api.RecipeCheckStrings())) end
    if triesLeft <= 1 then
        addon.Log.Debug("drops.read", "the item data did not load; the recipe is skipped", { itemID = itemID })
        return done(nil)
    end
    after(READ_RETRY_SECONDS, function() Drops.ReadRecipe(itemID, done, triesLeft - 1) end)
end

------------------------------------------------------------------ my loot

-- Announces a recipe that is in my bags: unless it binds on pickup or needs no profession. done(outcome) for tests and
-- the dev tools: "announced", "offline" (not in a guild channel), "bound", "unreadable".
---@param itemID integer
---@param done? fun(outcome: string)
---@param quiet? boolean no chat line per item (the bag scan prints one summary)
function Drops.Announce(itemID, done, quiet)
    Drops.ReadRecipe(itemID, function(reading)
        local outcome
        if not reading or not reading.required then outcome = "unreadable"
        elseif reading.bindOnPickup then outcome = "bound"
        else
            RecipeDrops.NoteMyDrop(itemID, now())
            outcome = addon.Communication.BroadcastDrop(itemID) and "announced" or "offline"
            if setting("chat") and not quiet then
                addon.Print(Format(Text["{item} dropped: hover it to see who in the guild can use it."], { item = itemText(itemID) }))
            end
            addon.Events.Fire("DATA_CHANGED", "drops")
        end
        addon.Log.Information("drops.announce", "a recipe dropped for me", { itemID = itemID, outcome = outcome })
        if done then done(outcome) end
    end)
end

-- A loot chat line: my own loot of a recipe item is announced once it is in my bags (looked at up to 10 s).
---@param message any
---@param done? fun(outcome: string)
---@return LootLine|nil the line when it is my recipe loot
function Drops.OnLootLine(message, done)
    if not setting("share") then return nil end
    local loot = RecipeCheck.ParseLoot(message, addon.Api.RecipeCheckStrings().loot)
    if not loot or loot.kind ~= "self" or addon.Api.ItemClass(loot.itemID) ~= addon.Offers.RECIPE_CLASS then return nil end
    local checkIndex = 0
    local function lookInBags()
        checkIndex = checkIndex + 1
        if addon.Api.BagCount(loot.itemID) > 0 then return Drops.Announce(loot.itemID, done) end
        local nextCheck = BAG_CHECK_SECONDS[checkIndex + 1]
        if not nextCheck then
            addon.Log.Information("drops.loot", "a looted recipe never reached my bags; not announced", { itemID = loot.itemID })
            if done then done("notInBags") end
            return
        end
        after(nextCheck - BAG_CHECK_SECONDS[checkIndex], lookInBags)
    end
    after(BAG_CHECK_SECONDS[1], lookInBags)
    return loot
end

-- seconds between two announcements of the bag scan (one small GUILD message each; keeps the send queue calm)
local BAG_SCAN_SPACING = 2

-- Announces every tradeable recipe in my bags as if it had just dropped (settings page button, /ps drops scan): the
-- guild is told, members who can learn one get the alert, and the recipe's tooltip lists who answered.
-- done(counts) with announced / bound / unreadable / offline counts; false when sharing is switched off.
---@param done? fun(counts: table<string, integer>)
---@return boolean started
function Drops.AnnounceBags(done)
    if not setting("share") then
        addon.Print(Text["Recipe drops: sharing is switched off, nothing was announced."])
        return false
    end
    local itemIDs = RecipeDrops.BagScanList(addon.Api.BagRecipeItems())
    addon.Log.Information("drops.bagScan", "the recipes in my bags are announced as new drops", { items = #itemIDs })
    if #itemIDs == 0 then
        addon.Print(Text["Recipe drops: no tradeable recipe in your bags."])
        if done then done({}) end
        return true
    end
    addon.Print(Format(Text["Recipe drops: announcing {n} recipes from your bags..."], { n = #itemIDs }))
    local counts, finished = {}, 0
    for index, itemID in ipairs(itemIDs) do
        after((index - 1) * BAG_SCAN_SPACING, function()
            Drops.Announce(itemID, function(outcome)
                counts[outcome] = (counts[outcome] or 0) + 1
                finished = finished + 1
                if finished < #itemIDs then return end
                addon.Print(Format(Text["Recipe drops: {announced} announced, {skipped} skipped (bind on pickup or no profession). Hover them to see who answered."],
                    { announced = counts.announced or 0, skipped = (counts.bound or 0) + (counts.unreadable or 0) }))
                if (counts.offline or 0) > 0 then addon.Print(Text["Recipe drops: not connected to the guild channel yet, try again in a moment."]) end
                if done then done(counts) end
            end, true)
        end)
    end
    return true
end

------------------------------------------------------------------ a member's drop

-- Shows the alert for a drop I can learn: chat line and minimap icon, each when switched on.
---@param itemID integer
---@param looter string
---@param rank integer|nil
function Drops.Alert(itemID, looter, rank)
    RecipeDrops.AddAlert(itemID, looter, rank, now())
    if setting("chat") then
        addon.Print(Format(Text["{item} dropped for {name}: you can learn it (your skill {skill})."],
            { item = itemText(itemID), name = playerLink(looter), skill = rank or "?" }))
    end
    if setting("icon") then addon.UI.SetDropNotice(#RecipeDrops.alerts) end
    addon.Events.Fire("DATA_CHANGED", "drops")
end

---@class DropOptions
---@field answer? fun(looter: string, itemID: integer, status: "g"|"r", rank: integer) replaces the whisper (dev tools)
---@field done? fun(result: { status: string, answer: string|nil, rank: integer|nil })

-- A member announced a recipe drop: decide from my own tooltip, answer and alert.
---@param looter string
---@param itemID integer
---@param options? DropOptions
function Drops.OnDrop(looter, itemID, options)
    options = options or {}
    local function finish(result) if options.done then options.done(result) end end
    if not setting("share") then return finish({ status = "off" }) end
    -- only recipe items: crafted gear can carry a "Requires <profession> (n)" line too (engineering goggles)
    if addon.Api.ItemClass(itemID) ~= addon.Offers.RECIPE_CLASS then return finish({ status = "notRecipe" }) end
    if RecipeDrops.IsDuplicate(looter, itemID, now()) then return finish({ status = "duplicate" }) end
    Drops.ReadRecipe(itemID, function(reading)
        local decision = RecipeCheck.Decide(reading, myProfessions())
        local answerStatus = RecipeDrops.AnswerStatus(decision)
        if answerStatus then
            local answer = options.answer or addon.Communication.AnswerDrop
            answer(looter, itemID, answerStatus, decision.rank or 0)
            if answerStatus == "g" then Drops.Alert(itemID, looter, decision.rank) end
        end
        addon.Log.Information("drops.incoming", "a member's recipe drop was checked",
            { itemID = itemID, status = decision.status, answer = answerStatus })
        finish({ status = decision.status, answer = answerStatus, rank = decision.rank })
    end)
end

------------------------------------------------------------------ tooltip lines for my drops

-- Adds who answered to a tooltip of an item that dropped for me (nothing for any other item).
---@param tooltip table
---@param itemID integer|nil
function Drops.AddTooltipLines(tooltip, itemID)
    if not itemID or not tooltip or not tooltip.AddLine then return end
    local hint = RecipeDrops.HintRows(itemID, shortName)
    if not hint then return end
    tooltip:AddLine(Text["Guild members who can use it:"], GOLD[1], GOLD[2], GOLD[3])
    if hint.answered == 0 then
        local drop = RecipeDrops.MyDrop(itemID)
        local waiting = drop and now() - drop.at < WAITING_SECONDS
        tooltip:AddLine(waiting and Text["Waiting for answers..."] or Text["Nobody online can use it."], GREY[1], GREY[2], GREY[3])
    end
    for _, row in ipairs(hint.rows) do
        local color = row.color == "green" and GREEN or RED
        tooltip:AddLine(Format(Text["{name} ({skill})"], { name = row.name, skill = row.rank }), color[1], color[2], color[3])
    end
    if hint.more > 0 then tooltip:AddLine(Format(Text["... and {n} more"], { n = hint.more }), GREY[1], GREY[2], GREY[3]) end
    if tooltip.Show then tooltip:Show() end
end

---@param tooltip table
local function onTooltipItem(tooltip)
    if not tooltip or not tooltip.GetItem then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    local itemID = ok and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if itemID then Drops.AddTooltipLines(tooltip, itemID) end
end

-- Hooks every item tooltip (bags, clicked links) and the chat link hover; only my drops get lines.
local function installTooltipHooks()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
            addon.Log.Protected("drops.tooltip", "adding the drop lines to a tooltip failed", onTooltipItem, tooltip)
        end)
    else
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            if type(tooltip) == "table" and tooltip.HookScript then
                pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(self)
                    addon.Log.Protected("drops.tooltip", "adding the drop lines to a tooltip failed", onTooltipItem, self)
                end)
            end
        end
    end
    -- chat links show nothing on hover by default: show the tooltip of links to my drops
    for chatIndex = 1, NUM_CHAT_WINDOWS or 0 do
        local chatFrame = _G["ChatFrame" .. chatIndex]
        if type(chatFrame) == "table" and chatFrame.HookScript then
            pcall(chatFrame.HookScript, chatFrame, "OnHyperlinkEnter", function(self, link)
                local itemID = type(link) == "string" and tonumber(link:match("^item:(%d+)"))
                if not itemID or not RecipeDrops.MyDrop(itemID) or not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink(link)
                GameTooltip:Show()
            end)
            pcall(chatFrame.HookScript, chatFrame, "OnHyperlinkLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
    end
end

------------------------------------------------------------------ events and command

if CreateFrame then
    local lootFrame = CreateFrame("Frame")
    pcall(lootFrame.RegisterEvent, lootFrame, "CHAT_MSG_LOOT")
    lootFrame:SetScript("OnEvent", function(_, _, message)
        addon.Log.Protected("drops.loot", "reading a loot line failed", Drops.OnLootLine, message)
    end)
    addon.Log.Protected("drops.hooks", "the tooltip hooks could not be installed", installTooltipHooks)
end

-- opening the window counts as having seen the alerts
addon.Events.On("WINDOW_OPENED", function()
    RecipeDrops.ClearAlerts()
    addon.UI.SetDropNotice(0)
end)

---@param value boolean
---@return string
local function onOff(value) return value and Text["on"] or Text["off"] end

addon.SlashCommands.drops = function(arguments)
    if tostring(arguments or ""):lower():match("^%s*scan%s*$") then Drops.AnnounceBags() return end
    local settingKey, valueText = tostring(arguments or ""):lower():match("^%s*(%a+)%s+(%a+)")
    if settingKey then
        local value
        if valueText == "on" then value = true elseif valueText == "off" then value = false end
        if value == nil or not RecipeDrops.Set(interfaceSettings(), settingKey, value) then
            addon.Print(Format(Text["Usage: {cmd} drops [scan | share|chat|icon on|off]"], { cmd = (addon.SLASH_COMMANDS or {})[1] }))
            return
        end
    end
    addon.Print(Format(Text["Recipe drops: share {share}, chat {chat}, minimap icon {icon}"],
        { share = onOff(setting("share")), chat = onOff(setting("chat")), icon = onOff(setting("icon")) }))
    for _, drop in ipairs(RecipeDrops.mine) do
        local hint = RecipeDrops.HintRows(drop.itemID, shortName)
        addon.Print(Format(Text["  my drop {item}: {n} answers"], { item = itemText(drop.itemID), n = hint and hint.answered or 0 }))
    end
end
