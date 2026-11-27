local addonName, addon = ...

-- Mail queue: mails prepared from crafting orders, waiting for the next open mailbox. A job is either the order's
-- reagents for a crafter ("mats") or the crafted item for the requester ("item"); it keeps its own copy of recipient,
-- label and remaining amounts, so it outlives the order. Saved per character (db.mailQueue[characterName] = jobs).
-- Pure: Core/Game/MailSender.lua reads the bags and the mailbox and executes the plan made here.

---@alias MailMode "mats"|"item"

---@class MailJob
---@field id string orderID .. ":" .. mode
---@field orderID string
---@field mode MailMode
---@field recipient string canonical "Name-Realm"
---@field recipeID integer
---@field qty integer order quantity
---@field label string recipe name snapshot (raw, escape before display)
---@field items table<integer, integer> itemID -> amount still to send
---@field createdAt integer

---@class BagStack
---@field bag integer
---@field slot integer
---@field itemID integer
---@field count integer
---@field locked? boolean
---@field bound? boolean

---@class MailAction
---@field kind "whole"|"split" whole: pick up the stack; split: split `count` into a free bag slot, attach that
---@field bag integer
---@field slot integer
---@field itemID integer
---@field count integer

---@class MailPlan
---@field actions MailAction[]
---@field attached table<integer, integer> what the actions attach, by item
---@field missing table<integer, integer> not in the bags (or only bound / locked / no free bag slot for the split)
---@field deferred table<integer, integer> in the bags but past the attachment limit: the next mail
---@field bound table<integer, boolean> items seen only as soulbound stacks
---@field noFreeSlot boolean a split was needed but no bag slot was free

---@class MailQueue
---@field jobs MailJob[]
local MailQueue = {}
MailQueue.__index = MailQueue
addon.MailQueue = MailQueue

MailQueue.ATTACHMENT_LIMIT = 12
local MAXIMUM_JOBS, MAXIMUM_ITEMS_PER_JOB, MAXIMUM_AMOUNT = 100, 40, 100000

---@param backingTable table db.mailQueue
---@param characterName string
---@param now fun(): integer
---@return MailQueue
function MailQueue.New(backingTable, characterName, now)
    if type(backingTable[characterName]) ~= "table" then backingTable[characterName] = {} end
    return setmetatable({ jobs = backingTable[characterName], now = now }, MailQueue)
end

---@param playerName any
---@return string|nil
local function canonical(playerName)
    if type(playerName) ~= "string" or not addon.Utility.IsSafeName(playerName) then return nil end
    return addon.Utility.CanonicalName(playerName) or playerName
end

-- The job for an order in `mode`, sent to `recipient`; nil and a reason ("noRecipient", "self", "noData") when there
-- is nothing to queue.
---@param store table
---@param order Order
---@param mode MailMode
---@param recipient string|nil
---@param myName string
---@return MailJob|nil
---@return string|nil reason
function MailQueue.JobForOrder(store, order, mode, recipient, myName)
    local recipientName = canonical(recipient)
    if not recipientName then return nil, "noRecipient" end
    if recipientName == (canonical(myName) or myName) then return nil, "self" end
    local catalogEntry = store.GetRecipe(order.recipeID)
    local items = {}
    if mode == "mats" then
        for _, reagent in ipairs(catalogEntry and catalogEntry.reagents or {}) do
            items[reagent.itemID] = (items[reagent.itemID] or 0) + reagent.count * order.qty
        end
    elseif mode == "item" then
        if catalogEntry and catalogEntry.produces then items[catalogEntry.produces] = order.qty end
    else
        return nil, "noData"
    end
    if next(items) == nil then return nil, "noData" end
    return { id = order.id .. ":" .. mode, orderID = order.id, mode = mode, recipient = recipientName,
        recipeID = order.recipeID, qty = order.qty, label = (catalogEntry and catalogEntry.name) or order.name or ("#" .. order.recipeID),
        items = items, createdAt = order.createdAt }
end

---@return MailJob[]
function MailQueue:List() return self.jobs end

---@return MailJob|nil
function MailQueue:First() return self.jobs[1] end

---@param jobID string
---@return MailJob|nil
---@return integer|nil index
function MailQueue:Get(jobID)
    for index, job in ipairs(self.jobs) do
        if job.id == jobID then return job, index end
    end
end

---@param job MailJob
---@return boolean added
---@return string|nil reason "duplicate"|"full"
function MailQueue:Add(job)
    if self:Get(job.id) then return false, "duplicate" end
    if #self.jobs >= MAXIMUM_JOBS then return false, "full" end
    self.jobs[#self.jobs + 1] = job
    return true
end

---@param jobID string
---@return boolean removed
function MailQueue:Remove(jobID)
    local _, index = self:Get(jobID)
    if not index then return false end
    table.remove(self.jobs, index)
    return true
end

---@param jobID string
function MailQueue:MoveUp(jobID)
    local _, index = self:Get(jobID)
    if index and index > 1 then self.jobs[index], self.jobs[index - 1] = self.jobs[index - 1], self.jobs[index] end
end

-- What of `sentCounts` (attached items by id) counts for the job: only its items, at most what it still needs.
---@param job MailJob
---@param sentCounts table<integer, integer>
---@return table<integer, integer>
function MailQueue.Delivered(job, sentCounts)
    local delivered = {}
    for itemID, count in pairs(sentCounts or {}) do
        local remaining = job.items[itemID]
        if remaining and type(count) == "number" and count > 0 then delivered[itemID] = math.min(count, remaining) end
    end
    return delivered
end

-- The order's mail entry (Orders:RecordMail) for a mail of `job` sent by `sender`: what it carried (flat
-- { itemID, count, ... } sorted by item id, at most Orders.MAXIMUM_MAIL_ITEMS pairs), whether the job is complete with
-- it, and whether the player marked it by hand.
---@param job MailJob
---@param sender string
---@param delivered table<integer, integer>
---@param complete boolean
---@param byHand boolean
---@return table
function MailQueue.MailEntry(job, sender, delivered, complete, byHand)
    return { m = job.mode, b = sender, r = job.recipient, c = complete or nil, h = byHand or nil,
        i = MailQueue.FlatItems(delivered) }
end

-- { itemID, count, ... } sorted by item id, at most Orders.MAXIMUM_MAIL_ITEMS pairs; nil when the map is empty
---@param itemMap table<integer, integer>|nil
---@return integer[]|nil
function MailQueue.FlatItems(itemMap)
    local itemIDs = {}
    for itemID in pairs(itemMap or {}) do itemIDs[#itemIDs + 1] = itemID end
    table.sort(itemIDs)
    local items = {}
    for index = 1, math.min(#itemIDs, addon.Orders.MAXIMUM_MAIL_ITEMS) do
        items[#items + 1] = itemIDs[index]
        items[#items + 1] = itemMap[itemIDs[index]]
    end
    return #items > 0 and items or nil
end

------------------------------------------------------------------ mail tags (pickup tracking)
-- A queued mail's subject ends with "[#xxxxxx]": a code of the order id and the mail kind, the same on every client, so
-- the recipient's client finds the order when the items are taken out (Core/Game/MailReceiver.lua).

local TAG_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
local TAG_LENGTH, TAG_MODULUS = 6, 2147483647
MailQueue.SUBJECT_BYTES = 64

---@param orderID string
---@param mode MailMode
---@return string six characters of [0-9a-z]
function MailQueue.Tag(orderID, mode)
    local text = tostring(orderID) .. ":" .. tostring(mode)
    local hash = 5381
    for index = 1, #text do hash = (hash * 33 + text:byte(index)) % TAG_MODULUS end
    local characters = {}
    for index = TAG_LENGTH, 1, -1 do
        local digit = hash % 36
        characters[index] = TAG_ALPHABET:sub(digit + 1, digit + 1)
        hash = (hash - digit) / 36
    end
    return table.concat(characters)
end

---@param subject any
---@return string|nil tag
function MailQueue.ParseTag(subject)
    if type(subject) ~= "string" then return nil end
    return subject:match("%[#([0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z])%]")
end

-- `text` with the tag appended, at most SUBJECT_BYTES bytes: the text is cut (never inside a character), never the tag.
---@param text string
---@param tag string
---@return string
function MailQueue.TaggedSubject(text, tag)
    local suffix = " [#" .. tag .. "]"
    return addon.Utility.TruncateUtf8(text, MailQueue.SUBJECT_BYTES - #suffix) .. suffix
end

---@class InboxMail
---@field subject string
---@field sender string
---@field returned boolean
---@field items table<integer, integer> itemID -> count still attached

---@class InboxTotal
---@field tag string
---@field sender string
---@field items table<integer, integer>

-- What the tagged mails of the inbox still carry, summed by tag and sender (returned mails left out).
---@param mails InboxMail[]
---@return table<string, InboxTotal>
function MailQueue.InboxTotals(mails)
    local totals = {}
    for _, mail in ipairs(mails or {}) do
        local tag = MailQueue.ParseTag(mail.subject)
        if tag and not mail.returned and type(mail.sender) == "string" and mail.sender ~= "" then
            local key = tag .. "\0" .. mail.sender
            local total = totals[key] or { tag = tag, sender = mail.sender, items = {} }
            for itemID, count in pairs(mail.items or {}) do total.items[itemID] = (total.items[itemID] or 0) + count end
            totals[key] = total
        end
    end
    return totals
end

---@class MailPickup
---@field tag string
---@field sender string
---@field items table<integer, integer> taken out

-- What was taken out between two inbox readings, only for tags the player was taking items from (a mail that is
-- returned or expires also leaves the inbox, but nobody took it).
---@param before table<string, InboxTotal>
---@param after table<string, InboxTotal>
---@param taking table<string, any> tags the player is taking items from
---@return MailPickup[]
function MailQueue.Pickups(before, after, taking)
    local pickups = {}
    for key, total in pairs(before or {}) do
        if taking[total.tag] then
            local remaining = (after[key] or { items = {} }).items
            local taken = {}
            for itemID, count in pairs(total.items) do
                local difference = count - (remaining[itemID] or 0)
                if difference > 0 then taken[itemID] = difference end
            end
            if next(taken) then pickups[#pickups + 1] = { tag = total.tag, sender = total.sender, items = taken } end
        end
    end
    table.sort(pickups, function(left, right)
        if left.tag ~= right.tag then return left.tag < right.tag end
        return left.sender < right.sender
    end)
    return pickups
end

-- I (`myName`) took the items of a tagged mail out: records the pickup on its order when I am the one the mail was
-- for (the requester for the crafted item, a crafter with a claim for reagents); the crafted item also closes the
-- order as done while it is open. Returns the order (nil: not mine or unknown) and whether it was closed.
---@param orderBoard OrderBoard
---@param pickup MailPickup
---@param myName string|nil
---@return Order|nil
---@return boolean closed
function MailQueue.ApplyPickup(orderBoard, pickup, myName)
    if not myName or type(pickup) ~= "table" then return nil, false end
    local order, mode = orderBoard:FindByTag(pickup.tag)
    if not order then return nil, false end
    if mode == "item" and order.requester ~= myName then return nil, false end
    if mode == "mats" and not order.claims[myName] then return nil, false end
    local entry = orderBoard:RecordPickup(order.id, { m = mode, b = myName, r = canonical(pickup.sender) or pickup.sender,
        i = MailQueue.FlatItems(pickup.items) })
    if not entry then return nil, false end
    local closed = false
    if mode == "item" and not order.closed then closed = orderBoard:Close(order.id, myName, "done") ~= nil end
    return order, closed
end

-- What a sent mail carried (by item) is taken off the job; returns false when the job is done (and removed).
---@param jobID string
---@param sentCounts table<integer, integer>
---@return boolean jobRemains
function MailQueue:ApplySent(jobID, sentCounts)
    local job = self:Get(jobID)
    if not job then return false end
    for itemID, sent in pairs(sentCounts) do
        local remaining = job.items[itemID]
        if remaining then
            remaining = remaining - sent
            job.items[itemID] = remaining > 0 and remaining or nil
        end
    end
    if next(job.items) == nil then
        self:Remove(jobID)
        return false
    end
    return true
end

---@param itemMap table<integer, any>
---@return integer[]
local function sortedItemIDs(itemMap)
    local itemIDs = {}
    for itemID in pairs(itemMap) do itemIDs[#itemIDs + 1] = itemID end
    table.sort(itemIDs)
    return itemIDs
end

-- How to fill one mail for `job` from the bags: whole stacks that fit the remaining need first (biggest first), then
-- the rest split from a bigger stack into a free bag slot. Stops at `attachmentLimit` actions.
---@param job MailJob
---@param bagStacks BagStack[]
---@param freeBagSlots integer
---@param attachmentLimit integer attachment slots still free in the mail
---@return MailPlan
function MailQueue.Plan(job, bagStacks, freeBagSlots, attachmentLimit)
    local plan = { actions = {}, attached = {}, missing = {}, deferred = {}, bound = {}, noFreeSlot = false }
    local slotsLeft, freeLeft = attachmentLimit, freeBagSlots
    for _, itemID in ipairs(sortedItemIDs(job.items)) do
        local need = job.items[itemID]
        local usable, usableTotal = {}, 0
        for _, bagStack in ipairs(bagStacks) do
            if bagStack.itemID == itemID then
                if bagStack.bound == true then plan.bound[itemID] = true
                elseif not bagStack.locked and bagStack.count > 0 then
                    usable[#usable + 1] = bagStack
                    usableTotal = usableTotal + bagStack.count
                end
            end
        end
        table.sort(usable, function(left, right)
            if left.count ~= right.count then return left.count > right.count end
            if left.bag ~= right.bag then return left.bag < right.bag end
            return left.slot < right.slot
        end)
        local remaining, used, limitReached, slotShortage = need, {}, false, false
        for index, bagStack in ipairs(usable) do
            if remaining <= 0 then break end
            if bagStack.count <= remaining then
                if slotsLeft <= 0 then limitReached = true break end
                plan.actions[#plan.actions + 1] = { kind = "whole", bag = bagStack.bag, slot = bagStack.slot, itemID = itemID, count = bagStack.count }
                remaining, slotsLeft, used[index] = remaining - bagStack.count, slotsLeft - 1, true
            end
        end
        if remaining > 0 and not limitReached then
            for index, bagStack in ipairs(usable) do
                if not used[index] and bagStack.count > remaining then
                    if slotsLeft <= 0 then limitReached = true
                    elseif freeLeft <= 0 then slotShortage = true
                    else
                        plan.actions[#plan.actions + 1] = { kind = "split", bag = bagStack.bag, slot = bagStack.slot, itemID = itemID, count = remaining }
                        remaining, slotsLeft, freeLeft = 0, slotsLeft - 1, freeLeft - 1
                    end
                    break
                end
            end
        end
        local attached = need - remaining
        if attached > 0 then plan.attached[itemID] = attached end
        if remaining > 0 then
            local available = math.min(need, usableTotal) - attached
            if limitReached and available > 0 then
                plan.deferred[itemID] = available
                if remaining - available > 0 then plan.missing[itemID] = remaining - available end
            else
                plan.missing[itemID] = remaining
            end
            if slotShortage then plan.noFreeSlot = true end
        end
    end
    return plan
end

---@param job any
---@return MailJob|nil
local function sanitizeJob(job)
    local Utility = addon.Utility
    if type(job) ~= "table" then return nil end
    if not Utility.CleanString(job.id, 120) or not Utility.CleanString(job.orderID, 100) then return nil end
    if job.mode ~= "mats" and job.mode ~= "item" then return nil end
    if not Utility.IsSafeName(job.recipient) then return nil end
    if not Utility.SafeInteger(job.recipeID, 1, 2147483647) or not Utility.SafeInteger(job.qty, 1, 99) then return nil end
    local label = job.label
    if label ~= nil and (not Utility.CleanString(label, 100) or label:find("|", 1, true)) then return nil end
    if type(job.items) ~= "table" then return nil end
    local items, itemCount = {}, 0
    for itemID, amount in pairs(job.items) do
        itemCount = itemCount + 1
        if itemCount > MAXIMUM_ITEMS_PER_JOB then return nil end
        if not Utility.SafeInteger(itemID, 1, 2147483647) or not Utility.SafeInteger(amount, 1, MAXIMUM_AMOUNT) then return nil end
        items[itemID] = amount
    end
    if itemCount == 0 then return nil end
    return { id = job.id, orderID = job.orderID, mode = job.mode, recipient = job.recipient, recipeID = job.recipeID,
        qty = job.qty, label = label or ("#" .. job.recipeID), items = items,
        createdAt = Utility.SafeInteger(job.createdAt, 0, 2147483647) and job.createdAt or 0 }
end

-- Re-validates db.mailQueue on load (allow-list copy); returns the number of dropped entries.
---@param savedVariables table
---@return integer droppedCount
function MailQueue.SanitizePersisted(savedVariables)
    local droppedCount = 0
    if type(savedVariables.mailQueue) ~= "table" then
        savedVariables.mailQueue = {}
        return 0
    end
    local clean = {}
    for characterName, jobs in pairs(savedVariables.mailQueue) do
        if type(characterName) == "string" and addon.Utility.IsSafeName(characterName) and type(jobs) == "table" then
            local cleanJobs, seen = {}, {}
            for _, job in ipairs(jobs) do
                local cleanJob = sanitizeJob(job)
                if cleanJob and not seen[cleanJob.id] and #cleanJobs < MAXIMUM_JOBS then
                    cleanJobs[#cleanJobs + 1], seen[cleanJob.id] = cleanJob, true
                else
                    droppedCount = droppedCount + 1
                end
            end
            clean[characterName] = cleanJobs
        else
            droppedCount = droppedCount + 1
        end
    end
    savedVariables.mailQueue = clean
    return droppedCount
end
