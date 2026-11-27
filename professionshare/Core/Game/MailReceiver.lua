local addonName, addon = ...

-- Pickup tracking: notices when the player takes the items out of a tagged mail (MailQueue.Tag in the subject) and
-- records that on the order (MailQueue.ApplyPickup: history entry; the crafted item closes the order as done).
-- How: the inbox is read on every MAIL_INBOX_UPDATE (subject, sender, attachments, summed by tag and sender); the
-- functions that take items (TakeInboxItem, AutoLootMailItem, also used by "Open all" and other mail addons) mark the
-- mail's tag; what a marked tag lost between two readings was taken. A mail that is returned or expires is never
-- marked, so it does not count. Every client call is guarded: a missing or failing inbox API only turns this off.
---@class MailReceiverModule
local MailReceiver = {}
addon.MailReceiver = MailReceiver

-- a mark counts this long after the take (a take that failed, e.g. full bags, must not count much later)
local TAKE_WINDOW_SECONDS = 15
local DEFAULT_ATTACHMENTS = 16

---@type table<string, InboxTotal>|nil the last reading (nil until the mailbox is open)
local lastTotals
---@type table<string, number> tag -> GetTime() of the take
local taking = {}

---@param name string
---@return any
local function global(name) return rawget(_G, name) end

---@return number
local function clock()
    local getTime = global("GetTime")
    return type(getTime) == "function" and getTime() or 0
end

---@param mailIndex integer
---@param attachIndex integer
---@return integer|nil itemID
---@return integer|nil count
local function attachment(mailIndex, attachIndex)
    local getItem = global("GetInboxItem")
    if type(getItem) ~= "function" then return nil, nil end
    local ok, _, itemID, _, count = pcall(getItem, mailIndex, attachIndex)
    if not ok or type(count) ~= "number" or count <= 0 then return nil, nil end
    if type(itemID) ~= "number" then
        local getLink = global("GetInboxItemLink")
        local okLink, link = false, nil
        if type(getLink) == "function" then okLink, link = pcall(getLink, mailIndex, attachIndex) end
        itemID = okLink and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    end
    if not itemID then return nil, nil end
    return itemID, count
end

---@param mailIndex integer
---@return InboxMail|nil
local function readMail(mailIndex)
    local getHeader = global("GetInboxHeaderInfo")
    if type(getHeader) ~= "function" then return nil end
    local ok, _, _, sender, subject, _, _, _, hasItem, _, wasReturned = pcall(getHeader, mailIndex)
    if not ok or type(subject) ~= "string" then return nil end
    local mail = { subject = subject, sender = type(sender) == "string" and sender or "", returned = wasReturned and true or false, items = {} }
    if hasItem then
        for attachIndex = 1, tonumber(global("ATTACHMENTS_MAX_RECEIVE")) or DEFAULT_ATTACHMENTS do
            local itemID, count = attachment(mailIndex, attachIndex)
            if itemID then mail.items[itemID] = (mail.items[itemID] or 0) + count end
        end
    end
    return mail
end

---@return InboxMail[]|nil nil when the inbox cannot be read
local function readInbox()
    local countMails = global("GetInboxNumItems")
    if type(countMails) ~= "function" then return nil end
    local ok, mailCount = pcall(countMails)
    if not ok or type(mailCount) ~= "number" then return nil end
    local mails = {}
    for mailIndex = 1, mailCount do mails[#mails + 1] = readMail(mailIndex) end
    return mails
end

---@param pickup MailPickup
local function handlePickup(pickup)
    if not addon.orders then return end
    local order, closed = addon.MailQueue.ApplyPickup(addon.orders, pickup, addon.Utility.Me())
    if not order then
        addon.Log.Information("mail.pickup", "a tagged mail was taken out but is for no order of mine", { tag = pickup.tag })
        return
    end
    addon.Log.Information("mail.pickup", "a tagged mail was taken out and recorded on its order", { orderID = order.id, closed = closed })
    if addon.Communication and addon.Communication.BroadcastOrder then addon.Communication.BroadcastOrder(order) end
    if addon.Events then addon.Events.Fire("DATA_CHANGED", "orders") end
end

-- Reads the inbox; what a marked tag lost since the last reading was picked up.
function MailReceiver.Scan()
    if lastTotals == nil then return end   -- the mailbox is not open
    local mails = readInbox()
    if not mails then return end
    local now = clock()
    for tag, takenAt in pairs(taking) do
        if now - takenAt > TAKE_WINDOW_SECONDS then taking[tag] = nil end
    end
    local totals = addon.MailQueue.InboxTotals(mails)
    for _, pickup in ipairs(addon.MailQueue.Pickups(lastTotals, totals, taking)) do
        taking[pickup.tag] = nil
        handlePickup(pickup)
    end
    lastTotals = totals
end

-- post-hook of the take functions: the mail at `mailIndex` is still listed at this point
---@param mailIndex any
function MailReceiver.OnTake(mailIndex)
    if lastTotals == nil or type(mailIndex) ~= "number" then return end
    local mail = readMail(mailIndex)
    local tag = mail and not mail.returned and addon.MailQueue.ParseTag(mail.subject)
    if not tag then return end
    taking[tag] = clock()
    local after = global("C_Timer") and C_Timer.After
    if after then after(1, MailReceiver.Scan) end   -- in case no inbox update follows
end

function MailReceiver.OnMailShow()
    taking, lastTotals = {}, {}
    MailReceiver.Scan()
end

function MailReceiver.OnMailClosed()
    MailReceiver.Scan()
    taking, lastTotals = {}, nil
end

-- the hooks on the take functions (called once from Core/Game/Events.lua)
function MailReceiver.Register()
    local hook = global("hooksecurefunc")
    if type(hook) ~= "function" then return end
    for _, functionName in ipairs({ "TakeInboxItem", "AutoLootMailItem" }) do
        if type(global(functionName)) == "function" then
            hook(functionName, function(mailIndex) MailReceiver.OnTake(mailIndex) end)
        end
    end
end
