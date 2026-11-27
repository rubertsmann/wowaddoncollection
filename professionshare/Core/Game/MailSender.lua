local addonName, addon = ...

-- Fills the Send Mail form from the mail queue (Core/Data/MailQueue.lua) while a mailbox is open: recipient, subject,
-- body and the attachments of the queued mail the player clicked. It NEVER sends: the player presses Send. After a send
-- to the job's recipient the job keeps only what that mail did not carry; the next mail waits for the next click.
-- Facts it relies on (features/045-mail-order-items/evidence): a split clicked straight into the mail attaches the whole
-- stack, so an exact amount is split into a free bag slot first and that new stack is attached; MAIL_SEND_INFO_UPDATE
-- fires inside ClickSendMailItemButton; a soulbound item is refused and stays on the cursor. Anything on the cursor is
-- put back after every step (an item left there plus a click into the world would ask to destroy it).

---@class MailSenderModule
local MailSender = {}
addon.MailSender = MailSender

local BAG_IDS = { 0, 1, 2, 3, 4 }
local SLOT_WAIT_SECONDS, POLL_SECONDS = 3, 0.1
local FILL_DELAY_SECONDS = 0.3

---@alias MailSenderState "closed"|"idle"|"filling"|"ready"

---@type MailSenderState
MailSender.state = "closed"
---@type { jobID: string, plan: MailPlan, recipient: string }|nil the job the open form was filled for
MailSender.current = nil
---@type { recipient: string, counts: table<integer, integer> }|nil what the last SendMail call carried
local sendSnapshot
-- bumped when the mailbox closes or a new fill starts: steps of an older fill stop
local fillToken = 0

------------------------------------------------------------------ queue

---@type MailQueue|nil
local queue
---@type string|nil
local queueOwner

-- the mail queue of the logged-in character (created on first use: the name is not known when the addon loads)
---@return MailQueue|nil
function MailSender.Queue()
    local myName = addon.Utility.Me()
    if not myName or type(addon.db) ~= "table" or type(addon.db.mailQueue) ~= "table" then return nil end
    if not queue or queueOwner ~= myName then
        queue, queueOwner = addon.MailQueue.New(addon.db.mailQueue, myName, addon.Utility.Now), myName
    end
    return queue
end

local function changed()
    if addon.Events then addon.Events.Fire("DATA_CHANGED", "mail") end
end

------------------------------------------------------------------ client helpers

---@param path string
---@return any
local function global(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = rawget(value, part)
    end
    return value
end

---@param bagID integer
---@return integer
local function slotCount(bagID)
    local getNumSlots = global("C_Container.GetContainerNumSlots") or global("GetContainerNumSlots")
    if not getNumSlots then return 0 end
    local ok, count = pcall(getNumSlots, bagID)
    return ok and tonumber(count) or 0
end

---@param bagID integer
---@param slot integer
---@return BagStack|nil
local function slotStack(bagID, slot)
    local modern = global("C_Container.GetContainerItemInfo")
    if modern then
        local ok, information = pcall(modern, bagID, slot)
        if not ok or type(information) ~= "table" or not information.itemID then return nil end
        return { bag = bagID, slot = slot, itemID = information.itemID, count = information.stackCount or 1,
            locked = information.isLocked and true or false, bound = information.isBound }
    end
    local legacy = global("GetContainerItemInfo")
    if not legacy then return nil end
    local ok, _, count, locked, _, _, _, _, _, _, itemID, bound = pcall(legacy, bagID, slot)
    if not ok or not itemID then return nil end
    return { bag = bagID, slot = slot, itemID = itemID, count = count or 1, locked = locked and true or false, bound = bound }
end

-- every stack in the bags and the empty slots
---@return BagStack[] stacks
---@return { bag: integer, slot: integer }[] emptySlots
function MailSender.ReadBags()
    local stacks, emptySlots = {}, {}
    for _, bagID in ipairs(BAG_IDS) do
        for slot = 1, slotCount(bagID) do
            local bagStack = slotStack(bagID, slot)
            if bagStack then stacks[#stacks + 1] = bagStack else emptySlots[#emptySlots + 1] = { bag = bagID, slot = slot } end
        end
    end
    return stacks, emptySlots
end

-- how many of each item the bags hold (bound stacks not counted: they cannot be mailed)
---@return table<integer, integer>
function MailSender.MailableCounts()
    local counts = {}
    for _, bagStack in ipairs((MailSender.ReadBags())) do
        if bagStack.bound ~= true then counts[bagStack.itemID] = (counts[bagStack.itemID] or 0) + bagStack.count end
    end
    return counts
end

---@return boolean
local function cursorHasItem()
    local cursorHas = global("CursorHasItem")
    if cursorHas then return cursorHas() and true or false end
    local getCursorInfo = global("GetCursorInfo")
    return getCursorInfo and getCursorInfo() == "item" or false
end

local function clearCursor()
    if cursorHasItem() then
        local clear = global("ClearCursor")
        if clear then clear() end
    end
end

---@param path string
---@param ... any
---@return boolean ok
local function try(path, ...)
    local func = global(path)
    if type(func) ~= "function" then return false end
    return (pcall(func, ...))
end

---@param bagID integer
---@param slot integer
local function pickup(bagID, slot)
    if not try("C_Container.PickupContainerItem", bagID, slot) then try("PickupContainerItem", bagID, slot) end
end

---@param bagID integer
---@param slot integer
---@param count integer
local function split(bagID, slot, count)
    if not try("C_Container.SplitContainerItem", bagID, slot, count) then try("SplitContainerItem", bagID, slot, count) end
end

---@return integer
local function attachmentLimit() return tonumber(global("ATTACHMENTS_MAX_SEND")) or addon.MailQueue.ATTACHMENT_LIMIT end

---@param index integer
---@return boolean
local function hasAttachment(index)
    local hasItem = global("HasSendMailItem")
    if hasItem then
        local ok, has = pcall(hasItem, index)
        return ok and has and true or false
    end
    local getItem = global("GetSendMailItem")
    if not getItem then return false end
    local ok, name = pcall(getItem, index)
    return ok and name ~= nil
end

---@return integer|nil
local function freeAttachmentSlot()
    for index = 1, attachmentLimit() do
        if not hasAttachment(index) then return index end
    end
end

---@return integer
local function freeAttachmentCount()
    local free = 0
    for index = 1, attachmentLimit() do if not hasAttachment(index) then free = free + 1 end end
    return free
end

-- what the Send Mail form carries now, by item
---@return table<integer, integer>
function MailSender.AttachedCounts()
    local counts = {}
    local getItem = global("GetSendMailItem")
    if not getItem then return counts end
    for index = 1, attachmentLimit() do
        local ok, name, itemID, _, count = pcall(getItem, index)
        if ok and name and itemID then counts[itemID] = (counts[itemID] or 0) + (tonumber(count) or 1) end
    end
    return counts
end

---@return boolean
function MailSender.MailboxOpen()
    local mailFrame = global("MailFrame")
    return type(mailFrame) == "table" and type(mailFrame.IsShown) == "function" and mailFrame:IsShown() and true or false
end

---@return boolean
local function inCombat() return (global("InCombatLockdown") and InCombatLockdown()) and true or false end

---@param name string
---@param text string
local function setText(name, text)
    local editBox = global(name)
    if type(editBox) == "table" and type(editBox.SetText) == "function" then pcall(editBox.SetText, editBox, text) end
end

-- "Name" / "Name-Realm" -> "name" (realm and case do not matter when comparing a typed recipient with a job's)
---@param playerName any
---@return string
local function nameKey(playerName)
    return (tostring(playerName or ""):match("^([^%-]+)") or ""):lower()
end

------------------------------------------------------------------ filling

---@param callback function
---@param seconds number
local function after(seconds, callback)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, callback) else callback() end
end

-- waits until bag/slot holds an unlocked stack of itemID; done(landedStack or nil)
---@param token integer
---@param bagID integer
---@param slot integer
---@param itemID integer
---@param done fun(landed: BagStack|nil)
local function waitForSlot(token, bagID, slot, itemID, done)
    local startedAt = (GetTime and GetTime()) or 0
    local function poll()
        if token ~= fillToken then return end
        local bagStack = slotStack(bagID, slot)
        if bagStack and bagStack.itemID == itemID and not bagStack.locked then return done(bagStack) end
        local waited = ((GetTime and GetTime()) or 0) - startedAt
        if waited >= SLOT_WAIT_SECONDS or not (C_Timer and C_Timer.After) then return done(nil) end
        C_Timer.After(POLL_SECONDS, poll)
    end
    poll()
end

---@class MailFillReport
---@field jobID string
---@field attached table<integer, integer>
---@field missing table<integer, integer>
---@field deferred table<integer, integer>
---@field bound table<integer, boolean>
---@field failed table<integer, integer> planned but not in the mail afterwards (refused, did not land)
---@field noFreeSlot boolean

---@type MailFillReport|nil the outcome of the last fill (the panel and the Mail tab show it)
MailSender.lastReport = nil

---@param job MailJob
---@param plan MailPlan
---@param attachedBefore table<integer, integer>
local function finishFill(job, plan, attachedBefore)
    local attachedNow = MailSender.AttachedCounts()
    local attached, failed = {}, {}
    for itemID, planned in pairs(plan.attached) do
        local gained = (attachedNow[itemID] or 0) - (attachedBefore[itemID] or 0)
        if gained > 0 then attached[itemID] = gained end
        if gained < planned then failed[itemID] = planned - math.max(gained, 0) end
    end
    MailSender.lastReport = { jobID = job.id, attached = attached, missing = plan.missing, deferred = plan.deferred,
        bound = plan.bound, failed = failed, noFreeSlot = plan.noFreeSlot }
    MailSender.state = "ready"
    addon.Log.Information("mail.fill", "a mail was filled from the queue", { job = job.id, actions = #plan.actions,
        failed = next(failed) ~= nil, missing = next(plan.missing) ~= nil, deferred = next(plan.deferred) ~= nil })
    changed()
end

-- runs the plan's actions one after the other
---@param token integer
---@param job MailJob
---@param plan MailPlan
---@param emptySlots { bag: integer, slot: integer }[]
---@param attachedBefore table<integer, integer>
local function runActions(token, job, plan, emptySlots, attachedBefore)
    local index, emptyIndex = 0, 0
    local function nextAction()
        if token ~= fillToken then return end
        if not MailSender.MailboxOpen() or inCombat() then clearCursor() return end
        index = index + 1
        local action = plan.actions[index]
        if not action then return finishFill(job, plan, attachedBefore) end
        local attachmentSlot = freeAttachmentSlot()
        if not attachmentSlot then return finishFill(job, plan, attachedBefore) end
        clearCursor()
        if action.kind == "whole" then
            pickup(action.bag, action.slot)
            if cursorHasItem() then try("ClickSendMailItemButton", attachmentSlot) end
            clearCursor()
            return nextAction()
        end
        emptyIndex = emptyIndex + 1
        local target = emptySlots[emptyIndex]
        if not target then return nextAction() end
        split(action.bag, action.slot, action.count)
        if cursorHasItem() then pickup(target.bag, target.slot) end   -- drops the split stack into the empty slot
        clearCursor()
        waitForSlot(token, target.bag, target.slot, action.itemID, function(landed)
            if token ~= fillToken then return end
            if landed and MailSender.MailboxOpen() then
                local slotForIt = freeAttachmentSlot()
                if slotForIt then
                    pickup(landed.bag, landed.slot)
                    if cursorHasItem() then try("ClickSendMailItemButton", slotForIt) end
                end
                clearCursor()
            end
            nextAction()
        end)
    end
    nextAction()
end

---@param job MailJob
---@return string
local function subjectFor(job)
    return addon.Locale.Format(addon.Text["ProfessionShare: {qty}x {name}"], { qty = job.qty, name = addon.Model.MailJobRecipeName(addon.Store, job) })
end

---@param job MailJob
---@return string
local function bodyFor(job)
    local Text, Format = addon.Text, addon.Locale.Format
    if job.mode == "mats" then
        return Format(Text["Reagents for the order {qty}x {name}. Prepared with ProfessionShare."], { qty = job.qty, name = addon.Model.MailJobRecipeName(addon.Store, job) })
    end
    return Format(Text["Your order {qty}x {name}. Prepared with ProfessionShare."], { qty = job.qty, name = addon.Model.MailJobRecipeName(addon.Store, job) })
end

---@type boolean the last fill request found nothing in the bags for its mail
MailSender.waitingForItems = false

-- Fills the form for `jobID` (nil: the first job that has something in the bags to attach). A form holding another
-- queued mail's items is emptied first (they go back to the bags, then the fill starts); a form with items the player
-- put in by hand is not touched. false and a reason when it cannot start now.
---@param jobID string|nil
---@return boolean started
---@return string|nil reason "closed"|"combat"|"empty"|"busy"|"notEmpty"|"nothingInBags"|"unknownJob"|"clearing"
function MailSender.FillJob(jobID)
    if not MailSender.MailboxOpen() then return false, "closed" end
    if inCombat() then return false, "combat" end
    if MailSender.state == "filling" then return false, "busy" end
    local mailQueue = MailSender.Queue()
    if not mailQueue or not mailQueue:First() then
        MailSender.current, MailSender.state, MailSender.waitingForItems = nil, "idle", false
        changed()
        return false, "empty"
    end
    if jobID and not mailQueue:Get(jobID) then return false, "unknownJob" end
    if next(MailSender.AttachedCounts()) ~= nil then
        if not MailSender.current then return false, "notEmpty" end
        -- another queued mail is in the form: its items go back first; the bags settle, then this fill starts
        fillToken = fillToken + 1
        MailSender.ClearForm()
        MailSender.current, MailSender.state = nil, "idle"
        changed()
        after(FILL_DELAY_SECONDS * 2, function() MailSender.FillJob(jobID) end)
        return true, "clearing"
    end
    local stacks, emptySlots = MailSender.ReadBags()
    local job, plan
    local candidates = jobID and { (mailQueue:Get(jobID)) } or mailQueue:List()
    for _, candidate in ipairs(candidates) do
        local candidatePlan = addon.MailQueue.Plan(candidate, stacks, #emptySlots, freeAttachmentCount())
        if #candidatePlan.actions > 0 then job, plan = candidate, candidatePlan break end
    end
    if not job then
        MailSender.current, MailSender.state, MailSender.waitingForItems = nil, "idle", true
        changed()
        return false, "nothingInBags"
    end
    MailSender.waitingForItems = false
    fillToken = fillToken + 1
    local token = fillToken
    MailSender.state = "filling"
    local tab = global("MailFrameTab2")
    if type(tab) == "table" and type(tab.Click) == "function" then pcall(tab.Click, tab)
    else try("MailFrameTab_OnClick", nil, 2) end
    local recipient = addon.Utility.WhisperTarget(job.recipient) or job.recipient
    setText("SendMailNameEditBox", recipient)
    setText("SendMailSubjectEditBox", subjectFor(job))
    setText("SendMailBodyEditBox", bodyFor(job))
    MailSender.current = { jobID = job.id, plan = plan, recipient = recipient }
    changed()
    runActions(token, job, plan, emptySlots, MailSender.AttachedCounts())
    return true
end

-- Returns every attachment of the form to the bags (right-click on each attachment slot).
function MailSender.ClearForm()
    clearCursor()
    for index = 1, attachmentLimit() do
        if hasAttachment(index) then try("ClickSendMailItemButton", index, true) end
    end
    clearCursor()
end

-- "This mail went out": the items attached for this job are taken off it (what is still missing stays as the reduced
-- need). Nothing of this job attached: the job is removed. Returns true when the job remains.
---@param jobID string
---@return boolean jobRemains
function MailSender.Done(jobID)
    local mailQueue = MailSender.Queue()
    local job = mailQueue and mailQueue:Get(jobID)
    if not job then return false end
    local delivered = {}
    if MailSender.current and MailSender.current.jobID == jobID then
        for itemID, count in pairs(MailSender.AttachedCounts()) do
            if job.items[itemID] then delivered[itemID] = math.min(count, job.items[itemID]) end
        end
        fillToken = fillToken + 1
        MailSender.current, MailSender.state = nil, MailSender.MailboxOpen() and "idle" or "closed"
    end
    local remains
    if next(delivered) then remains = mailQueue:ApplySent(jobID, delivered)
    else mailQueue:Remove(jobID) remains = false end
    addon.Log.Information("mail.done", "a queued mail was marked done", { job = jobID, remains = remains })
    changed()
    return remains
end

---@param jobID string
function MailSender.Remove(jobID)
    local mailQueue = MailSender.Queue()
    if not mailQueue then return end
    if MailSender.current and MailSender.current.jobID == jobID then
        fillToken = fillToken + 1
        MailSender.ClearForm()
        MailSender.current, MailSender.state = nil, MailSender.MailboxOpen() and "idle" or "closed"
    end
    mailQueue:Remove(jobID)
    changed()
end

------------------------------------------------------------------ events

-- the mailbox opened: nothing is filled until the player clicks a queued mail (UI/MailPanel.lua lists them)
function MailSender.OnMailShow()
    MailSender.state, MailSender.current, sendSnapshot, MailSender.waitingForItems = "idle", nil, nil, false
    changed()
end

function MailSender.OnMailClosed()
    fillToken = fillToken + 1
    clearCursor()
    MailSender.state, MailSender.current, sendSnapshot = "closed", nil, nil
    changed()
end

-- post-hook of SendMail: the form still holds the recipient and attachments at this point
---@param recipient any
function MailSender.OnSendMail(recipient)
    sendSnapshot = { recipient = tostring(recipient or ""), counts = MailSender.AttachedCounts() }
end

function MailSender.OnSendSuccess()
    local snapshot, current = sendSnapshot, MailSender.current
    sendSnapshot = nil
    local mailQueue = MailSender.Queue()
    if not (snapshot and current and mailQueue) then return end
    local job = mailQueue:Get(current.jobID)
    MailSender.current, MailSender.state = nil, "idle"
    -- only a mail to the job's recipient counts for the job (the player may have changed the form)
    if job and nameKey(snapshot.recipient) == nameKey(job.recipient) then
        local remains = mailQueue:ApplySent(job.id, snapshot.counts)
        addon.Log.Information("mail.sent", "a queued mail was sent", { job = job.id, remains = remains })
    end
    changed()   -- the next mail waits for the player's click
end

function MailSender.OnSendFailed()
    sendSnapshot = nil
    if MailSender.current then MailSender.state = "ready" end
    changed()
end

-- the events and the SendMail hook (called once from Core/Game/Events.lua)
---@param register fun(eventName: string, handler: function)
function MailSender.Register(register)
    register("MAIL_SEND_SUCCESS", MailSender.OnSendSuccess)
    register("MAIL_FAILED", MailSender.OnSendFailed)
    if hooksecurefunc and type(global("SendMail")) == "function" then
        hooksecurefunc("SendMail", function(recipient) MailSender.OnSendMail(recipient) end)
    end
end
