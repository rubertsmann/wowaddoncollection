local addonName, addon = ...

-- DEV BUILD ONLY: finds out how far an addon can prepare a mail on this client (recipient, subject, attachments,
-- exact amounts by splitting stacks) before a mail feature is built. It NEVER sends: SendMail is not called, the
-- player checks the result in the Send Mail tab and closes the mailbox (unsent attachments return to the bags).
-- Anything left on the cursor after an attach attempt is put back at once (an item on the cursor plus a click into the
-- world would ask to destroy it).
--   /psd mailprobe                      API and event check (anywhere)
--   /psd mailprobe fill <name>          mailbox open: Send Mail tab, recipient, subject, body
--   /psd mailprobe attach <itemID> [count] [<itemID> [count] ...]   one at a time, waits for the server each time
--   /psd mailprobe burst <itemID> [count] ...                       all at once, no waiting (is waiting needed?)
--   /psd mailprobe bags                 every item in the bags with its id (pick test items from it)
--   /psd mailprobe report               every saved run (the last 12, also from before a /reload) in a copy box
--   /psd mailprobe clear                forget the saved runs
--   /psd mailfill [name]                shortcut for fill; the name is remembered (dev saved variables)
--   /psd mailprobe attachslot <itemID> <count> ...   split into an empty bag slot first, then attach the new stack
--   /psd mailtest                       shortcut: splits a stack both ways and attaches another item (bound ones skipped), then report
-- Results go to ProfessionShareDevDB.devChecks.mailRuns (the newest also to .mail; /reload writes them to disk).
-- Plain English strings on purpose: dev-only, not localized.
---@class MailProbeModule
local MailProbe = {}
addon.MailProbe = MailProbe

local WAIT_TIMEOUT_SECONDS = 3
local POLL_SECONDS = 0.1
local BAG_IDS = { 0, 1, 2, 3, 4 }

---@type string[] the lines of the current run
local lines = {}
local runStartedAt = 0

---@return number
local function clock() return (GetTime and GetTime()) or 0 end

---@param text string
local function note(text)
    local line = ("[%5.2f] %s"):format(clock() - runStartedAt, text)
    lines[#lines + 1] = line
    addon.Print("mailprobe " .. line)
end

---@param runName string
local function startRun(runName)
    lines, runStartedAt = {}, clock()
    note(("--- %s (%s, %s) ---"):format(runName, tostring(addon.VERSION), date and date("%Y-%m-%d %H:%M:%S") or "?"))
end

local MAXIMUM_SAVED_RUNS = 12

-- the newest run is devChecks.mail; every run is also kept in devChecks.mailRuns (oldest first, survives /reload)
local function saveRun()
    local database = addon.db
    if type(database) ~= "table" then return end
    database.devChecks = type(database.devChecks) == "table" and database.devChecks or {}
    local copy = {}
    for index, line in ipairs(lines) do copy[index] = line end
    local run = { at = date and date("%Y-%m-%d %H:%M:%S") or nil, version = addon.VERSION, lines = copy }
    database.devChecks.mail = run
    local runs = type(database.devChecks.mailRuns) == "table" and database.devChecks.mailRuns or {}
    runs[#runs + 1] = run
    while #runs > MAXIMUM_SAVED_RUNS do table.remove(runs, 1) end
    database.devChecks.mailRuns = runs
end

-- the global value at a dotted path ("C_Container.PickupContainerItem"), or nil
---@param path string
---@return any
local function valueAt(path)
    local value = _G
    for pathPart in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[pathPart]
    end
    return value
end

---@param ... any
---@return string
local function describeAll(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[#parts + 1] = tostring((select(index, ...))) end
    return #parts == 0 and "(nothing)" or table.concat(parts, ", ")
end

---@param path string
---@param ... any
---@return boolean ok
---@return string description
local function call(path, ...)
    local func = valueAt(path)
    if type(func) ~= "function" then return false, "missing" end
    local results = { pcall(func, ...) }
    if not results[1] then return false, "error " .. tostring(results[2]) end
    return true, describeAll(unpack(results, 2, table.maxn(results)))
end

------------------------------------------------------------------ bags, cursor, attachments

---@param bagID integer
---@return integer
local function slotCount(bagID)
    local getNumSlots = valueAt("C_Container.GetContainerNumSlots") or valueAt("GetContainerNumSlots")
    local ok, count = pcall(getNumSlots, bagID)
    return ok and tonumber(count) or 0
end

-- itemID, stack size, locked, bound of a bag slot (both container APIs; bound is nil when the client does not say)
---@param bagID integer
---@param slot integer
---@return integer|nil itemID
---@return integer stackCount
---@return boolean locked
---@return boolean|nil bound
local function slotItem(bagID, slot)
    local modern = valueAt("C_Container.GetContainerItemInfo")
    if modern then
        local ok, information = pcall(modern, bagID, slot)
        if ok and type(information) == "table" then
            return information.itemID, information.stackCount or 1, information.isLocked and true or false, information.isBound
        end
        return nil, 0, false, nil
    end
    local legacy = valueAt("GetContainerItemInfo")
    if not legacy then return nil, 0, false, nil end
    local ok, _, count, locked, _, _, _, _, _, _, itemID, bound = pcall(legacy, bagID, slot)
    if not ok then return nil, 0, false, nil end
    return itemID, count or 1, locked and true or false, bound
end

-- the first unlocked bag slot holding itemID (the biggest stack, so a split can take `count` from it)
---@param itemID integer
---@return integer|nil bagID
---@return integer|nil slot
---@return integer stackCount
local function findItem(itemID)
    local bestBag, bestSlot, bestCount = nil, nil, 0
    for _, bagID in ipairs(BAG_IDS) do
        for slot = 1, slotCount(bagID) do
            local slotItemID, stackCount, locked = slotItem(bagID, slot)
            if slotItemID == itemID and not locked and stackCount > bestCount then
                bestBag, bestSlot, bestCount = bagID, slot, stackCount
            end
        end
    end
    return bestBag, bestSlot, bestCount
end

---@return integer|nil bagID
---@return integer|nil slot
local function findEmptySlot()
    for _, bagID in ipairs(BAG_IDS) do
        for slot = 1, slotCount(bagID) do
            if not slotItem(bagID, slot) then return bagID, slot end
        end
    end
end

-- calls done(true) once the slot holds itemID unlocked, or done(false) after the timeout
---@param bagID integer
---@param slot integer
---@param itemID integer
---@param done fun(landed: boolean, waited: number)
local function waitForSlot(bagID, slot, itemID, done)
    local startedAt = clock()
    local function poll()
        local slotItemID, _, locked = slotItem(bagID, slot)
        local waited = clock() - startedAt
        if slotItemID == itemID and not locked then return done(true, waited) end
        if waited >= WAIT_TIMEOUT_SECONDS or not (C_Timer and C_Timer.After) then return done(false, waited) end
        C_Timer.After(POLL_SECONDS, poll)
    end
    poll()
end

-- every stack of itemID in the bags: "bag 0 slot 3: 20, bag 1 slot 5: 4 (locked)" or "none"
---@param itemID integer
---@return string
local function describeStacks(itemID)
    local parts = {}
    for _, bagID in ipairs(BAG_IDS) do
        for slot = 1, slotCount(bagID) do
            local slotItemID, stackCount, locked, bound = slotItem(bagID, slot)
            if slotItemID == itemID then
                parts[#parts + 1] = ("bag %d slot %d: %d%s, bound=%s"):format(bagID, slot, stackCount, locked and " (locked)" or "",
                    tostring(bound))
            end
        end
    end
    return #parts == 0 and "none" or table.concat(parts, ", ")
end

---@param itemID integer
---@return string
local function itemName(itemID)
    return (addon.Api and addon.Api.ItemName and addon.Api.ItemName(itemID)) or "?"
end

---@return boolean
local function cursorHasItem()
    local cursorHas = valueAt("CursorHasItem")
    if cursorHas then return cursorHas() and true or false end
    local getCursorInfo = valueAt("GetCursorInfo")
    return getCursorInfo and getCursorInfo() == "item" or false
end

-- puts back whatever is on the cursor (never leave an item there)
---@param context string
local function clearCursor(context)
    if cursorHasItem() then
        local clear = valueAt("ClearCursor")
        if clear then clear() end
        note(("%s: cursor still held an item -> ClearCursor (now holds item: %s)"):format(context, tostring(cursorHasItem())))
    end
end

---@return integer
local function attachmentSlots() return tonumber(valueAt("ATTACHMENTS_MAX_SEND")) or 12 end

---@return integer|nil the first empty send attachment slot
local function freeAttachmentSlot()
    local hasItem = valueAt("HasSendMailItem")
    local getItem = valueAt("GetSendMailItem")
    for index = 1, attachmentSlots() do
        if hasItem then
            local ok, has = pcall(hasItem, index)
            if ok and not has then return index end
        elseif getItem then
            local ok, name = pcall(getItem, index)
            if ok and name == nil then return index end
        end
    end
    return nil
end

local function describeAttachments()
    local parts = {}
    for index = 1, attachmentSlots() do
        local ok, description = call("GetSendMailItem", index)
        if ok and description ~= "(nothing)" and not description:match("^nil") then parts[#parts + 1] = index .. ": " .. description end
    end
    note("attachments now: " .. (#parts == 0 and "none" or table.concat(parts, " | ")))
end

------------------------------------------------------------------ events

---@type table<string, integer> events seen since the counter was reset
local seenEvents = {}
local PROBED_EVENTS = { "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_INFO_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
    "ITEM_LOCK_CHANGED", "BAG_UPDATE_DELAYED", "CURSOR_CHANGED", "CURSOR_UPDATE", "UI_ERROR_MESSAGE" }
---@type table|nil
local eventFrame
---@type table<string, boolean>
local registeredEvents = {}
local listening = false

local function ensureEventFrame()
    if eventFrame or not CreateFrame then return end
    eventFrame = CreateFrame("Frame")
    for _, eventName in ipairs(PROBED_EVENTS) do
        registeredEvents[eventName] = pcall(eventFrame.RegisterEvent, eventFrame, eventName) and true or false
    end
    eventFrame:SetScript("OnEvent", function(_, eventName, ...)
        if not listening then return end
        seenEvents[eventName] = (seenEvents[eventName] or 0) + 1
        if eventName ~= "BAG_UPDATE_DELAYED" then note("event " .. eventName .. " " .. describeAll(...)) end
    end)
end

-- calls done() once `eventName` was seen more often than `startCount` (true) or after the timeout (false); the count is
-- taken before the action, so an event that fires during the action itself is not missed
---@param eventName string
---@param startCount integer
---@param done fun(seen: boolean, waited: number)
local function waitFor(eventName, startCount, done)
    local startedAt = clock()
    local function poll()
        local waited = clock() - startedAt
        if (seenEvents[eventName] or 0) > startCount then return done(true, waited) end
        if waited >= WAIT_TIMEOUT_SECONDS or not (C_Timer and C_Timer.After) then return done(false, waited) end
        C_Timer.After(POLL_SECONDS, poll)
    end
    poll()
end

------------------------------------------------------------------ stages

local PROBED_APIS = { "SendMail", "ClickSendMailItemButton", "GetSendMailItem", "GetSendMailItemLink", "HasSendMailItem",
    "SetSendMailMoney", "SetSendMailCOD", "GetSendMailPrice", "C_Container.PickupContainerItem", "PickupContainerItem",
    "C_Container.SplitContainerItem", "SplitContainerItem", "C_Container.GetContainerItemInfo", "GetContainerItemInfo",
    "C_Container.GetContainerNumSlots", "GetContainerNumSlots", "ClearCursor", "CursorHasItem", "GetCursorInfo",
    "MailFrameTab_OnClick", "SendMailFrame_Update", "issecurevariable", "InCombatLockdown" }
local PROBED_GLOBALS = { "MailFrame", "MailFrameTab1", "MailFrameTab2", "SendMailFrame", "SendMailNameEditBox",
    "SendMailSubjectEditBox", "SendMailBodyEditBox", "SendMailMailButton", "SendMailAttachment1", "ATTACHMENTS_MAX_SEND" }

---@return boolean
local function mailboxOpen()
    local mailFrame = valueAt("MailFrame")
    return type(mailFrame) == "table" and type(mailFrame.IsShown) == "function" and mailFrame:IsShown() and true or false
end

function MailProbe.CheckApi()
    ensureEventFrame()
    startRun("api")
    for _, path in ipairs(PROBED_APIS) do note(("api %s: %s"):format(path, type(valueAt(path)))) end
    for _, path in ipairs(PROBED_GLOBALS) do
        local value = valueAt(path)
        note(("global %s: %s"):format(path, type(value) == "table" and "frame/table" or tostring(value)))
    end
    for _, eventName in ipairs(PROBED_EVENTS) do note(("event %s: %s"):format(eventName, registeredEvents[eventName] and "registered" or "unknown")) end
    local isSecure = valueAt("issecurevariable")
    if isSecure then
        for _, functionName in ipairs({ "SendMail", "ClickSendMailItemButton", "PickupContainerItem" }) do
            local ok, secure, taint = pcall(isSecure, functionName)
            note(("secure %s: %s %s"):format(functionName, ok and tostring(secure) or "error", ok and tostring(taint or "") or ""))
        end
    end
    note("mailbox open: " .. tostring(mailboxOpen()))
    saveRun()
end

---@param recipient string
function MailProbe.Fill(recipient)
    ensureEventFrame()
    startRun("fill")
    if not mailboxOpen() then note("the mailbox is not open: open it at a mailbox first") saveRun() return end
    recipient = recipient ~= "" and recipient or (UnitName and UnitName("player")) or ""
    -- the Send Mail tab: the tab's own click handler, then the documented helper as a fallback
    local tab = valueAt("MailFrameTab2")
    if type(tab) == "table" and type(tab.Click) == "function" then
        local ok, failure = pcall(tab.Click, tab)
        note("MailFrameTab2:Click(): " .. (ok and "ok" or ("error " .. tostring(failure))))
    else
        note("MailFrameTab_OnClick(nil, 2): " .. select(2, call("MailFrameTab_OnClick", nil, 2)))
    end
    local sendFrame = valueAt("SendMailFrame")
    note("SendMailFrame shown: " .. tostring(type(sendFrame) == "table" and sendFrame:IsShown()))
    for _, field in ipairs({ { "SendMailNameEditBox", recipient }, { "SendMailSubjectEditBox", "ProfessionShare: mail probe" },
        { "SendMailBodyEditBox", "Test mail prepared by the ProfessionShare mail probe. Not sent automatically." } }) do
        local editBox = valueAt(field[1])
        if type(editBox) == "table" and type(editBox.SetText) == "function" then
            local ok, failure = pcall(editBox.SetText, editBox, field[2])
            note(("%s:SetText -> %s, reads back %q"):format(field[1], ok and "ok" or ("error " .. tostring(failure)),
                tostring(editBox.GetText and editBox:GetText())))
        else
            note(field[1] .. ": missing")
        end
    end
    local updateSendMail = valueAt("SendMailFrame_Update")
    if updateSendMail then note("SendMailFrame_Update(): " .. select(2, call("SendMailFrame_Update"))) end
    note("postage now: " .. select(2, call("GetSendMailPrice")))
    note("check the Send Mail tab: recipient, subject and body should be filled. Nothing was sent.")
    saveRun()
end

-- picks up what lies in bagID/slot (or uses what is already on the cursor), clicks it into attachmentSlot and waits for
-- the mail's confirmation; done() when finished
---@param attachmentSlot integer
---@param pickUp fun(): boolean, string the action that puts the item on the cursor
---@param how string for the log
---@param done fun()
local function clickIntoMail(attachmentSlot, pickUp, how, done)
    local ok, description = pickUp()
    note(("%s -> %s, cursor holds item: %s"):format(how, ok and "ok" or description, tostring(cursorHasItem())))
    local updatesBefore = seenEvents.MAIL_SEND_INFO_UPDATE or 0
    local clickOk, clickDescription = call("ClickSendMailItemButton", attachmentSlot)
    note(("ClickSendMailItemButton(%d): %s; GetSendMailItem(%d) right after: %s"):format(attachmentSlot,
        clickOk and "ok" or clickDescription, attachmentSlot, select(2, call("GetSendMailItem", attachmentSlot))))
    clearCursor("after click")
    waitFor("MAIL_SEND_INFO_UPDATE", updatesBefore, function(seen, waited)
        note(("MAIL_SEND_INFO_UPDATE %s after %.2f s; GetSendMailItem(%d): %s"):format(seen and "seen" or "NOT seen",
            waited, attachmentSlot, select(2, call("GetSendMailItem", attachmentSlot))))
        clearCursor("after wait")
        done()
    end)
end

---@param bagID integer
---@param slot integer
---@return boolean ok
---@return string description
local function pickupSlot(bagID, slot)
    local ok, description = call("C_Container.PickupContainerItem", bagID, slot)
    if description == "missing" then ok, description = call("PickupContainerItem", bagID, slot) end
    return ok, description
end

---@param bagID integer
---@param slot integer
---@param count integer
---@return boolean ok
---@return string description
local function splitSlot(bagID, slot, count)
    local ok, description = call("C_Container.SplitContainerItem", bagID, slot, count)
    if description == "missing" then ok, description = call("SplitContainerItem", bagID, slot, count) end
    return ok, description
end

-- One attachment. method "direct": split (or pick up) and click straight into the mail. method "slot": split into an
-- empty bag slot first, wait until the new stack is there, then attach that whole new stack.
---@param itemID integer
---@param count integer|nil nil = the whole stack
---@param method "direct"|"slot"|nil default "direct"
---@param done fun()
local function attachOne(itemID, count, method, done)
    if valueAt("InCombatLockdown") and InCombatLockdown() then note("in combat: skipped") return done() end
    local bagID, slot, stackCount = findItem(itemID)
    note(("item %d (%s): stacks in the bags: %s"):format(itemID, itemName(itemID), describeStacks(itemID)))
    if not bagID then note(("item %d: no unlocked stack in the bags, skipped"):format(itemID)) return done() end
    local attachmentSlot = freeAttachmentSlot()
    if not attachmentSlot then note("no free attachment slot") return done() end
    local wanted = count or stackCount
    if wanted > stackCount then
        note(("item %d: %d wanted, the biggest stack has %d: attaching the whole stack"):format(itemID, wanted, stackCount))
        wanted = stackCount
    end
    clearCursor("before")
    local origin = ("item %d from bag %d slot %d (stack %d)"):format(itemID, bagID, slot, stackCount)
    if wanted == stackCount then
        return clickIntoMail(attachmentSlot, function() return pickupSlot(bagID, slot) end, origin .. ": pickup", done)
    end
    if method ~= "slot" then
        return clickIntoMail(attachmentSlot, function() return splitSlot(bagID, slot, wanted) end,
            origin .. ": split " .. wanted .. " straight into the mail", done)
    end
    local emptyBag, emptySlot = findEmptySlot()
    if not emptyBag then note("no empty bag slot for the split: skipped") return done() end
    local splitOk, splitDescription = splitSlot(bagID, slot, wanted)
    note(("%s: split %d -> %s, cursor holds item: %s"):format(origin, wanted, splitOk and "ok" or splitDescription, tostring(cursorHasItem())))
    local dropOk, dropDescription = pickupSlot(emptyBag, emptySlot)
    note(("drop into empty bag %d slot %d -> %s, cursor holds item: %s"):format(emptyBag, emptySlot,
        dropOk and "ok" or dropDescription, tostring(cursorHasItem())))
    clearCursor("after drop")
    waitForSlot(emptyBag, emptySlot, itemID, function(landed, waited)
        local _, newCount = slotItem(emptyBag, emptySlot)
        note(("new stack %s after %.2f s: bag %d slot %d holds %s"):format(landed and "landed" or "NOT landed", waited,
            emptyBag, emptySlot, landed and tostring(newCount) or "nothing usable"))
        if not landed then return done() end
        clickIntoMail(attachmentSlot, function() return pickupSlot(emptyBag, emptySlot) end,
            ("pickup new stack bag %d slot %d (%d)"):format(emptyBag, emptySlot, newCount), done)
    end)
end

local RECHECK_SECONDS = 2

---@param requests { itemID: integer, count: integer|nil, method: "direct"|"slot"|nil }[]
---@param burst boolean true: every attach right after the other, no waiting
---@param onFinished? fun() called after the run was saved
function MailProbe.Attach(requests, burst, onFinished)
    ensureEventFrame()
    startRun(burst and "burst" or "attach")
    if not mailboxOpen() then note("the mailbox is not open: open it at a mailbox first") saveRun() return end
    if #requests == 0 then note("usage: /psd mailprobe attach <itemID> [count] [<itemID> [count] ...]") saveRun() return end
    listening = true
    -- the attachments are read again a moment later: the server may still refuse and return one
    local function finish()
        describeAttachments()
        local function recheck()
            listening = false
            note(("%d s later:"):format(RECHECK_SECONDS))
            describeAttachments()
            note("done. Check the Send Mail tab. Nothing was sent; closing the mailbox returns the attachments.")
            saveRun()
            if onFinished then onFinished() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(RECHECK_SECONDS, recheck) else recheck() end
    end
    if burst then
        local pending = #requests
        for _, request in ipairs(requests) do
            attachOne(request.itemID, request.count, request.method, function()
                pending = pending - 1
                if pending == 0 then finish() end
            end)
        end
        return
    end
    local index = 0
    local function nextRequest()
        index = index + 1
        local request = requests[index]
        if not request then return finish() end
        attachOne(request.itemID, request.count, request.method, nextRequest)
    end
    nextRequest()
end

-- every saved run (up to MAXIMUM_SAVED_RUNS, oldest first, also from before a /reload) in one copy box
function MailProbe.Report()
    local devChecks = addon.db and addon.db.devChecks
    local runs = devChecks and devChecks.mailRuns
    local reportLines = {}
    for _, run in ipairs(type(runs) == "table" and runs or {}) do
        for _, line in ipairs(run.lines or {}) do reportLines[#reportLines + 1] = line end
        reportLines[#reportLines + 1] = ""
    end
    if #reportLines == 0 then reportLines = { "no mail probe run yet" } end
    if addon.UI and addon.UI.ShowExport then addon.UI.ShowExport(table.concat(reportLines, "\n")) end
end

-- forgets the saved runs (start a fresh test series)
function MailProbe.Clear()
    local devChecks = addon.db and addon.db.devChecks
    if type(devChecks) == "table" then devChecks.mailRuns, devChecks.mail = nil, nil end
    lines = {}
    addon.Print("mailprobe: saved runs cleared")
end

-- every item in the bags with id, stack size and name, so the attach steps can use what the player has
function MailProbe.Bags()
    startRun("bags")
    for _, bagID in ipairs(BAG_IDS) do
        for slot = 1, slotCount(bagID) do
            local slotItemID, stackCount, locked, bound = slotItem(bagID, slot)
            if slotItemID then
                note(("bag %d slot %d: item %d x%d %s%s, bound=%s"):format(bagID, slot, slotItemID, stackCount, itemName(slotItemID),
                    locked and " (locked)" or "", tostring(bound)))
            end
        end
    end
    saveRun()
end

-- "123 5 456" -> { { itemID = 123, count = 5 }, { itemID = 456 } }: a number after an item id is its count when it is
-- small (item ids are larger than any mail count)
---@param text string
---@return { itemID: integer, count: integer|nil }[]
function MailProbe.ParseRequests(text)
    local requests = {}
    for numberText in tostring(text or ""):gmatch("%d+") do
        local number = tonumber(numberText)
        local last = requests[#requests]
        if last and last.count == nil and number <= 1000 then last.count = number
        else requests[#requests + 1] = { itemID = number } end
    end
    return requests
end

------------------------------------------------------------------ shortcuts

-- /psd mailfill [name]: fill the mail; the name is remembered in the dev saved variables (not in the code), so later
-- calls need no name
---@param arguments string
function MailProbe.QuickFill(arguments)
    local name = tostring(arguments or ""):match("^%s*(.-)%s*$")
    local devChecks = addon.db and addon.db.devChecks
    if name ~= "" then
        if type(addon.db) == "table" then
            addon.db.devChecks = type(devChecks) == "table" and devChecks or {}
            addon.db.devChecks.mailRecipient = name
        end
    else
        name = type(devChecks) == "table" and devChecks.mailRecipient or ""
    end
    if name == "" then addon.Print("mailfill: give the recipient once: /psd mailfill <name>") return end
    MailProbe.Fill(name)
end

-- Test items from the bags (items the client reports as bound are skipped): the biggest stack of at least 3 is split
-- twice, 2 via an empty bag slot, then (with at least 6) 3 straight into the mail; a different item goes as a whole
-- stack. nil when the bags hold no stack of at least 3.
---@return { itemID: integer, count: integer|nil, method: "direct"|"slot"|nil }[]|nil
function MailProbe.PickTestItems()
    local splitItem, splitCount, wholeItem = nil, 0, nil
    local candidates = {}
    for _, bagID in ipairs(BAG_IDS) do
        for slot = 1, slotCount(bagID) do
            local slotItemID, stackCount, locked, bound = slotItem(bagID, slot)
            if slotItemID and not locked and bound ~= true then
                candidates[#candidates + 1] = slotItemID
                if stackCount >= 3 and stackCount > splitCount then splitItem, splitCount = slotItemID, stackCount end
            end
        end
    end
    if not splitItem then return nil end
    for _, candidate in ipairs(candidates) do
        if candidate ~= splitItem then wholeItem = candidate break end
    end
    local requests = { { itemID = splitItem, count = 2, method = "slot" } }
    if splitCount >= 6 then requests[#requests + 1] = { itemID = splitItem, count = 3, method = "direct" } end
    if wholeItem then requests[#requests + 1] = { itemID = wholeItem } end
    return requests
end

-- /psd mailtest: attach 3 of a stack and a whole other stack (picked from the bags), then show every saved run
function MailProbe.QuickTest()
    local requests = MailProbe.PickTestItems()
    if not requests then addon.Print("mailtest: needs a stack of at least 3 of something tradeable in the bags") return end
    MailProbe.Attach(requests, false, MailProbe.Report)
end

---@param arguments string
function MailProbe.Command(arguments)
    local stage, rest = tostring(arguments or ""):match("^%s*(%S*)%s*(.-)%s*$")
    stage = (stage or ""):lower()
    if stage == "" or stage == "api" then return MailProbe.CheckApi() end
    if stage == "fill" then return MailProbe.Fill(rest) end
    if stage == "attach" then return MailProbe.Attach(MailProbe.ParseRequests(rest), false) end
    if stage == "attachslot" then
        local requests = MailProbe.ParseRequests(rest)
        for _, request in ipairs(requests) do request.method = "slot" end
        return MailProbe.Attach(requests, false)
    end
    if stage == "burst" then return MailProbe.Attach(MailProbe.ParseRequests(rest), true) end
    if stage == "report" then return MailProbe.Report() end
    if stage == "clear" then return MailProbe.Clear() end
    if stage == "bags" then return MailProbe.Bags() end
    addon.Print("mailprobe: api | bags | fill <name> | attach <itemID> [count] ... | attachslot <itemID> <count> ... | burst <itemID> [count] ... | report | clear")
end

if addon.IS_DEVELOPMENT_BUILD then
    addon.SlashCommands.mailprobe = function(arguments) MailProbe.Command(arguments) end
    addon.SlashCommands.mailfill = function(arguments) MailProbe.QuickFill(arguments) end
    addon.SlashCommands.mailtest = function() MailProbe.QuickTest() end
end
