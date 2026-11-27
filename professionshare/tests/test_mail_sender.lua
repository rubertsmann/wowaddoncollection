-- Mail sender against a simulated mailbox: fills the clicked job with exact amounts (whole stacks + a split into a free
-- slot), never sends, never leaves an item on the cursor, counts a sent mail only for the job's recipient, keeps what
-- was missing, and goes on with the next job.

local GLOBALS = { "CreateFrame", "GetTime", "C_Timer", "C_Container", "CursorHasItem", "ClearCursor", "GetCursorInfo",
    "ClickSendMailItemButton", "GetSendMailItem", "HasSendMailItem", "SendMail", "MailFrame", "MailFrameTab2",
    "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox", "ATTACHMENTS_MAX_SEND", "InCombatLockdown",
    "hooksecurefunc", "PickupContainerItem", "SplitContainerItem", "GetContainerItemInfo", "GetContainerNumSlots" }

-- bag 0 with `slots` slots; options.bags = { [slot] = { itemID, count, bound } }
local function world(options)
    options = options or {}
    local state = { now = 0, cursor = nil, attachments = {}, sent = {}, clears = 0, slots = options.slots or 6,
        bags = options.bags or { [1] = { itemID = 2840, count = 20 }, [2] = { itemID = 2840, count = 5 }, [3] = { itemID = 2589, count = 4 } },
        open = true }
    local saved = {}
    for _, name in ipairs(GLOBALS) do saved[name] = _G[name] end
    state.restore = function() for _, name in ipairs(GLOBALS) do _G[name] = saved[name] end end
    local function editBox()
        local box = { text = "" }
        function box:SetText(text) self.text = text end
        function box:GetText() return self.text end
        return box
    end
    GetTime = function() state.now = state.now + 0.05; return state.now end
    C_Timer = { After = function(_, callback) callback() end }
    C_Container = {
        GetContainerNumSlots = function(bagID) return bagID == 0 and state.slots or 0 end,
        GetContainerItemInfo = function(bagID, slot)
            local entry = bagID == 0 and state.bags[slot]
            if not entry then return nil end
            return { itemID = entry.itemID, stackCount = entry.count, isLocked = false, isBound = entry.bound or false }
        end,
        PickupContainerItem = function(_, slot)
            local entry = state.bags[slot]
            if state.cursor then
                if entry then return end
                if options.dropFails then state.cursor = nil return end   -- the split never lands
                state.bags[slot] = { itemID = state.cursor.itemID, count = state.cursor.count }
                local source = state.cursor.source
                source.count = source.count - state.cursor.count
                state.cursor = nil
                return
            end
            if entry then state.cursor = { itemID = entry.itemID, count = entry.count, fromSlot = slot, bound = entry.bound } end
        end,
        SplitContainerItem = function(_, slot, count)
            local entry = state.bags[slot]
            state.cursor = { itemID = entry.itemID, count = count, source = entry, split = true }
        end,
    }
    CursorHasItem = function() return state.cursor ~= nil end
    ClearCursor = function() state.clears = state.clears + 1; state.cursor = nil end
    ClickSendMailItemButton = function(index, clear)
        if clear then
            local attachment = state.attachments[index]
            if attachment then state.bags[attachment.fromSlot or 99] = { itemID = attachment.itemID, count = attachment.count } end
            state.attachments[index] = nil
            return
        end
        local cursor = state.cursor
        if not cursor or state.attachments[index] then return end
        if cursor.bound or options.refuseItem == cursor.itemID then return end   -- refused: stays on the cursor
        state.attachments[index] = cursor
        if cursor.fromSlot then state.bags[cursor.fromSlot] = nil end
        state.cursor = nil
    end
    GetSendMailItem = function(index)
        local attachment = state.attachments[index]
        if not attachment then return nil end
        return "Item " .. attachment.itemID, attachment.itemID, nil, attachment.count, 1
    end
    HasSendMailItem = function(index) return state.attachments[index] ~= nil end
    SendMail = function(recipient, subject)
        state.sent[#state.sent + 1] = { recipient = recipient, subject = subject }
    end
    hooksecurefunc = function(name, post)
        local original = _G[name]
        _G[name] = function(...) original(...); post(...) end
    end
    MailFrame = { IsShown = function() return state.open end }
    MailFrameTab2 = { Click = function() state.sendTab = true end }
    SendMailNameEditBox, SendMailSubjectEditBox, SendMailBodyEditBox = editBox(), editBox(), editBox()
    ATTACHMENTS_MAX_SEND = 12
    InCombatLockdown = function() return false end
    -- the game sends: the form empties, the server confirms
    state.send = function(recipient, sender)
        SendMail(recipient or SendMailNameEditBox:GetText(), SendMailSubjectEditBox:GetText(), "")
        state.attachments = {}
        sender.OnSendSuccess()
    end
    return state
end

local function setup(harness, options)
    local state = world(options)
    local addon = harness.addon()
    addon.Store.db.me = "Me-R"
    addon.Store.PutCatalog({
        [100] = { name = "Copper Thing", produces = 5000, reagents = { { itemID = 2840, count = 2 }, { itemID = 2589, count = 1 } } },
        [200] = { name = "Other Thing", produces = 6000, reagents = { { itemID = 2589, count = 1 } } },
    })
    local board = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    assert(loadfile("Core/Game/MailSender.lua"))("ProfessionShare", addon)
    local events = {}
    addon.MailSender.Register(function(name, handler) events[name] = handler end)
    return state, addon, board, events
end

local function queueJob(addon, board, recipeID, qty, mode, recipient)
    local order = board:Create("Req-R", recipeID, qty)
    local job = assert(addon.MailQueue.JobForOrder(addon.Store, order, mode, recipient, "Me-R"))
    addon.MailSender.Queue():Add(job)
    return job
end

local function attachedOf(state)
    local counts = {}
    for _, attachment in pairs(state.attachments) do counts[attachment.itemID] = (counts[attachment.itemID] or 0) + attachment.count end
    return counts
end

local function run(harness, options, body)
    local state, addon, board, events = setup(harness, options)
    local ok, failure = pcall(body, state, addon, board, events)
    state.restore()
    assert(ok, failure)
end

return {
    ["mail sender: opening the mailbox fills nothing; a click fills that mail with exact amounts, never sends"] = function(harness)
        run(harness, nil, function(state, addon, board)
            local job = queueJob(addon, board, 100, 3, "mats", "Crafter-R")   -- 6 bars, 3 cloth
            addon.MailSender.OnMailShow()
            harness.equal(next(state.attachments), nil, "opening the mailbox fills nothing")
            harness.equal(state.sendTab, nil)
            harness.equal(addon.MailSender.FillJob(job.id), true)
            local attached = attachedOf(state)
            harness.equal(attached[2840], 6, "the stack of 5 whole + 1 split into a free slot")
            harness.equal(attached[2589], 3, "3 split off the stack of 4")
            harness.equal(state.sendTab, true)
            harness.truthy(SendMailNameEditBox:GetText():find("Crafter", 1, true))
            harness.truthy(SendMailSubjectEditBox:GetText():find("3x Copper Thing", 1, true))
            harness.equal(state.cursor, nil); harness.equal(#state.sent, 0)
            harness.equal(addon.MailSender.state, "ready")
        end)
    end,

    ["mail sender: a send to the job's recipient finishes the job; the next mail waits for a click"] = function(harness)
        run(harness, nil, function(state, addon, board)
            local first = queueJob(addon, board, 100, 1, "mats", "Crafter-R")
            harness.clock = harness.clock + 1
            local second = queueJob(addon, board, 200, 1, "mats", "Other-R")
            addon.MailSender.OnMailShow()
            addon.MailSender.FillJob(first.id)
            state.send(nil, addon.MailSender)
            local queue = addon.MailSender.Queue()
            harness.equal(queue:Get(first.id), nil, "fully sent")
            harness.equal(#queue:List(), 1)
            harness.equal(next(state.attachments), nil, "the next mail is not filled by itself")
            harness.equal(addon.MailSender.state, "idle")
            addon.MailSender.FillJob(second.id)
            harness.truthy(SendMailNameEditBox:GetText():find("Other", 1, true))
            harness.equal(attachedOf(state)[2589], 1)
        end)
    end,

    ["mail sender: a mail to someone else does not count for the job"] = function(harness)
        run(harness, nil, function(state, addon, board)
            local job = queueJob(addon, board, 100, 1, "mats", "Crafter-R")
            addon.MailSender.OnMailShow()
            addon.MailSender.FillJob(job.id)
            state.send("Somebody", addon.MailSender)
            harness.equal(addon.MailSender.Queue():Get(job.id).items[2840], 2)
        end)
    end,

    ["mail sender: what the bags lack stays in the job; a job with nothing in the bags is not filled"] = function(harness)
        run(harness, { bags = { [1] = { itemID = 2840, count = 2 } } }, function(state, addon, board)
            local job = queueJob(addon, board, 100, 1, "mats", "Crafter-R")   -- 2 bars (there), 1 cloth (missing)
            addon.MailSender.OnMailShow()
            addon.MailSender.FillJob(job.id)
            harness.equal(attachedOf(state)[2840], 2)
            harness.equal(addon.MailSender.lastReport.missing[2589], 1)
            state.send(nil, addon.MailSender)
            local left = addon.MailSender.Queue():Get(job.id)
            harness.equal(left.items[2840], nil); harness.equal(left.items[2589], 1)
            local started, reason = addon.MailSender.FillJob(job.id)
            harness.equal(started, false); harness.equal(reason, "nothingInBags")
            harness.equal(addon.MailSender.waitingForItems, true)
            harness.equal(next(state.attachments), nil, "no empty mail was prepared")
        end)
    end,

    ["mail sender: a split that never lands and a refused item leave the cursor empty"] = function(harness)
        run(harness, { dropFails = true, refuseItem = 2840 }, function(state, addon, board)
            local job = queueJob(addon, board, 100, 3, "mats", "Crafter-R")
            addon.MailSender.OnMailShow()
            addon.MailSender.FillJob(job.id)
            harness.equal(state.cursor, nil)
            local report = addon.MailSender.lastReport
            harness.truthy(report.failed[2840] and report.failed[2840] > 0)
            harness.equal(#state.sent, 0)
        end)
    end,

    ["mail sender: items the player put in are not filled over; another queued mail is emptied first"] = function(harness)
        run(harness, nil, function(state, addon, board)
            local first = queueJob(addon, board, 100, 1, "mats", "Crafter-R")
            harness.clock = harness.clock + 1
            local second = queueJob(addon, board, 200, 2, "mats", "Other-R")
            state.attachments[1] = { itemID = 777, count = 1 }
            addon.MailSender.OnMailShow()
            local started, reason = addon.MailSender.FillJob(first.id)
            harness.equal(started, false); harness.equal(reason, "notEmpty")
            state.attachments = {}
            addon.MailSender.FillJob(first.id)
            harness.equal(attachedOf(state)[2840], 2)
            addon.MailSender.FillJob(second.id)
            harness.truthy(SendMailNameEditBox:GetText():find("Other", 1, true))
            harness.equal(attachedOf(state)[2840], nil, "the first mail's items went back")
            harness.equal(attachedOf(state)[2589], 2)
        end)
    end,

    ["mail sender: Done subtracts what is attached and keeps the missing rest; nothing attached removes the job"] = function(harness)
        run(harness, { bags = { [1] = { itemID = 2840, count = 2 } } }, function(state, addon, board)
            local job = queueJob(addon, board, 100, 1, "mats", "Crafter-R")   -- 2 bars (there), 1 cloth (missing)
            harness.clock = harness.clock + 1
            local other = queueJob(addon, board, 200, 1, "mats", "Other-R")
            addon.MailSender.OnMailShow()
            addon.MailSender.FillJob(job.id)
            harness.equal(addon.MailSender.Done(job.id), true)
            local left = addon.MailSender.Queue():Get(job.id)
            harness.equal(left.items[2840], nil); harness.equal(left.items[2589], 1, "the missing cloth is still needed")
            harness.equal(addon.MailSender.current, nil)
            harness.equal(addon.MailSender.Done(other.id), false)
            harness.equal(addon.MailSender.Queue():Get(other.id), nil, "nothing attached for it: removed")
            addon.MailSender.Remove(job.id)
            harness.equal(#addon.MailSender.Queue():List(), 0)
        end)
    end,

    ["mail sender: closing the mailbox stops; nothing is filled while it is closed"] = function(harness)
        run(harness, nil, function(state, addon, board)
            queueJob(addon, board, 100, 1, "mats", "Crafter-R")
            state.open = false
            addon.MailSender.OnMailClosed()
            local started, reason = addon.MailSender.FillJob(nil)
            harness.equal(started, false); harness.equal(reason, "closed")
            harness.equal(addon.MailSender.state, "closed")
        end)
    end,
}
