-- Mail tags and pickup tracking: the subject tag, the inbox diff, the pickup on the order (the crafted item closes it),
-- the pickup digest in HELLO, and the receiver against a simulated inbox.

local GLOBALS = { "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink", "TakeInboxItem",
    "AutoLootMailItem", "ReturnInboxItem", "hooksecurefunc", "C_Timer", "GetTime", "ATTACHMENTS_MAX_RECEIVE" }

local function replica(harness)
    local addon = harness.addon()
    return addon, addon.Orders.New(function() return harness.clock end, {})
end

-- inbox = list of { sender, subject, returned, items = { {itemID, count}, ... } }; the server removes taken items on
-- `state.deliver()` (as the real one does, a moment after the take); options.bagsFull: takes fail
local function world(options)
    options = options or {}
    local state = { inbox = {}, now = 0, pending = {} }
    local saved = {}
    for _, name in ipairs(GLOBALS) do saved[name] = _G[name] end
    state.restore = function() for _, name in ipairs(GLOBALS) do _G[name] = saved[name] end end
    GetTime = function() return state.now end
    C_Timer = { After = function() end }
    ATTACHMENTS_MAX_RECEIVE = 16
    GetInboxNumItems = function() return #state.inbox end
    GetInboxHeaderInfo = function(index)
        local mail = state.inbox[index]
        if not mail then return nil end
        return nil, nil, mail.sender, mail.subject, 0, 0, 30, #mail.items > 0 and #mail.items or nil, false, mail.returned or false
    end
    GetInboxItem = function(index, attachIndex)
        local mail = state.inbox[index]
        local item = mail and mail.items[attachIndex]
        if not item then return nil end
        return "Item " .. item[1], item[1], nil, item[2], 1, true
    end
    TakeInboxItem = function(index, attachIndex)
        if options.bagsFull then return end
        state.pending[#state.pending + 1] = function() table.remove(state.inbox[index].items, attachIndex) end
    end
    AutoLootMailItem = function(index)
        if options.bagsFull then return end
        state.pending[#state.pending + 1] = function() table.remove(state.inbox, index) end
    end
    ReturnInboxItem = function(index) table.remove(state.inbox, index) end
    hooksecurefunc = function(name, post)
        local original = _G[name]
        _G[name] = function(...) original(...); post(...) end
    end
    state.deliver = function()
        for _, apply in ipairs(state.pending) do apply() end
        state.pending = {}
    end
    return state
end

local function setup(harness, options)
    local state = world(options)
    local addon = harness.addon()
    addon.Store.db.me = "Req-R"
    local board = addon.Orders.New(function() return harness.clock end, addon.db.orders)
    addon.orders = board
    assert(loadfile("Core/Game/MailReceiver.lua"))("ProfessionShare", addon)
    addon.MailReceiver.Register()
    return state, addon, board
end

local function run(harness, options, body)
    local state, addon, board = setup(harness, options)
    local ok, failure = pcall(body, state, addon, board)
    state.restore()
    assert(ok, failure)
end

local function claimedOrder(board, harness)
    local order = board:Create("Req-R", 5, 2)
    harness.clock = harness.clock + 1
    board:Claim(order.id, "Crafter-R")
    return order
end

return {
    ["mail tag: six characters, the same for the same order and kind, different otherwise"] = function(harness)
        local addon = harness.addon()
        local tag = addon.MailQueue.Tag("Req-R:1700000000:1234", "item")
        harness.truthy(tag:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$"), tag)
        harness.equal(addon.MailQueue.Tag("Req-R:1700000000:1234", "item"), tag)
        harness.truthy(addon.MailQueue.Tag("Req-R:1700000000:1234", "mats") ~= tag)
        harness.truthy(addon.MailQueue.Tag("Req-R:1700000000:1235", "item") ~= tag)
        local seen, collisions = {}, 0
        for index = 1, 2000 do
            local code = addon.MailQueue.Tag("Someone-Realm:" .. (1700000000 + index) .. ":" .. (1000 + index % 9000), "item")
            if seen[code] then collisions = collisions + 1 end
            seen[code] = true
        end
        harness.equal(collisions, 0)
    end,

    ["mail tag: the subject keeps the tag within 64 bytes; parse finds it"] = function(harness)
        local addon = harness.addon()
        local subject = addon.MailQueue.TaggedSubject("ProfessionShare: 2x " .. string.rep("Ü", 40), "a1b2c3")
        harness.truthy(#subject <= 64, #subject)
        harness.equal(addon.MailQueue.ParseTag(subject), "a1b2c3")
        harness.truthy(addon.Utility.IsValidUtf8(subject), "not cut inside a character")
        harness.equal(addon.MailQueue.ParseTag("ProfessionShare: 2x Thing"), nil)
        harness.equal(addon.MailQueue.ParseTag(nil), nil)
    end,

    ["mail pickup: the diff counts only taken tags; returned mails and untouched tags do not (RF1)"] = function(harness)
        local addon = harness.addon()
        local before = addon.MailQueue.InboxTotals({
            { subject = "x [#aaaaaa]", sender = "Crafter-R", items = { [5000] = 2 } },
            { subject = "y [#bbbbbb]", sender = "Crafter-R", items = { [6000] = 1 } },
            { subject = "z [#cccccc]", sender = "Crafter-R", items = { [7000] = 1 }, returned = true },
            { subject = "no tag", sender = "Crafter-R", items = { [8000] = 1 } } })
        harness.equal(before["cccccc\0Crafter-R"], nil, "returned mails are left out")
        local after = addon.MailQueue.InboxTotals({ { subject = "x [#aaaaaa]", sender = "Crafter-R", items = { [5000] = 1 } } })
        local pickups = addon.MailQueue.Pickups(before, after, { aaaaaa = 1 })
        harness.equal(#pickups, 1, "bbbbbb vanished but was not taken")
        harness.equal(pickups[1].items[5000], 1)
        harness.equal(#addon.MailQueue.Pickups(before, before, { aaaaaa = 1 }), 0, "nothing gone yet")
    end,

    ["mail pickup: the requester taking the item records it and closes the order (R4)"] = function(harness)
        local addon, board = replica(harness)
        local order = claimedOrder(board, harness)
        board:RecordMail(order.id, { m = "item", b = "Crafter-R", r = "Req-R", c = true })
        local tag = addon.MailQueue.Tag(order.id, "item")
        harness.equal(select(2, board:FindByTag(tag)), "item")
        local pickedOrder, closed = addon.MailQueue.ApplyPickup(board, { tag = tag, sender = "Crafter-R", items = { [5000] = 2 } }, "Req-R")
        harness.equal(pickedOrder, order); harness.equal(closed, true)
        harness.equal(board:Status(order), "done"); harness.equal(order.closedBy, "Req-R")
        harness.equal(order.rcv[1].b, "Req-R"); harness.equal(order.rcv[1].r, "Crafter-R"); harness.equal(table.concat(order.rcv[1].i, ","), "5000,2")
        local kinds = {}
        for _, historyRow in ipairs(addon.Model.OrderHistory(order)) do kinds[#kinds + 1] = historyRow.kind end
        harness.truthy(table.concat(kinds, ","):find("pickup", 1, true))
        local _, closedAgain = addon.MailQueue.ApplyPickup(board, { tag = tag, sender = "Crafter-R", items = { [5000] = 1 } }, "Req-R")
        harness.equal(closedAgain, false, "a second part is recorded, the order is already closed (RF5)")
        harness.equal(#order.rcv, 2)
    end,

    ["mail pickup: reagents add history only; the wrong person records nothing (R5, RF3)"] = function(harness)
        local addon, board = replica(harness)
        local order = claimedOrder(board, harness)
        local matsTag = addon.MailQueue.Tag(order.id, "mats")
        local _, closed = addon.MailQueue.ApplyPickup(board, { tag = matsTag, sender = "Req-R", items = { [2840] = 4 } }, "Crafter-R")
        harness.equal(closed, false); harness.equal(board:Status(order), "claimed"); harness.equal(#order.rcv, 1)
        harness.equal(addon.MailQueue.ApplyPickup(board, { tag = matsTag, sender = "Req-R", items = { [2840] = 4 } }, "Stranger-R"), nil)
        harness.equal(addon.MailQueue.ApplyPickup(board, { tag = addon.MailQueue.Tag(order.id, "item"), sender = "Crafter-R", items = {} }, "Crafter-R"), nil,
            "the item is for the requester")
        harness.equal(addon.MailQueue.ApplyPickup(board, { tag = "zzzzzz", sender = "X-R", items = {} }, "Req-R"), nil, "unknown tag")
        harness.equal(#order.rcv, 1)
    end,

    ["mail pickup: the sender gets news; pickups sync only to peers that send rdig (R6, RF4)"] = function(harness)
        local addon, a = replica(harness)
        local _, b = replica(harness)
        local order = claimedOrder(a, harness)
        b:Merge(order)
        a:RecordPickup(order.id, { m = "item", b = "Req-R", r = "Crafter-R" })
        local unseen = addon.Notify.UnseenMail(a, "Crafter-R", nil)
        harness.equal(#unseen, 1); harness.equal(unseen[1].pickedUp, true)
        harness.equal(#addon.Notify.UnseenMail(a, "Req-R", nil), 0, "my own pickup is no news")
        harness.equal(#a:Missing(b:Digest(), 40, b:ExtraDigest(), b:MailDigest()), 0, "a 2.10 peer is not pushed")
        harness.equal(#a:Missing(b:Digest(), 40, b:ExtraDigest(), b:MailDigest(), b:PickupDigest()), 1, "a 2.11 peer is")
        b:Merge(a:Get(order.id))
        harness.equal(#a:Missing(b:Digest(), 40, b:ExtraDigest(), b:MailDigest(), b:PickupDigest()), 0)
        local copy = addon.Orders.Sanitize(order)
        copy.rcv = { { m = "item", b = "Req-R", r = "Crafter-R", t = harness.clock, c = true }, { m = "gold", b = "Req-R", r = "X-R", t = 1 } }
        harness.equal(#addon.Orders.Sanitize(copy).rcv, 1, "bad entries dropped")
        harness.equal(addon.Orders.Sanitize(copy).rcv[1].c, nil, "pickups carry no complete flag")
    end,

    ["mail receiver: taking the items of a tagged mail records the pickup once the server removed them"] = function(harness)
        run(harness, nil, function(state, addon, board)
            local order = claimedOrder(board, harness)
            state.inbox = { { sender = "Crafter", subject = addon.MailQueue.TaggedSubject("ProfessionShare: 2x Thing", addon.MailQueue.Tag(order.id, "item")),
                items = { { 5000, 2 } } }, { sender = "Other", subject = "hello", items = { { 1, 1 } } } }
            addon.MailReceiver.OnMailShow()
            AutoLootMailItem(1)
            addon.MailReceiver.Scan()
            harness.equal(order.rcv, nil, "not removed yet: nothing")
            state.deliver()
            addon.MailReceiver.Scan()
            harness.equal(#order.rcv, 1)
            harness.equal(board:Status(order), "done")
            addon.MailReceiver.Scan()
            harness.equal(#order.rcv, 1, "counted once")
            addon.MailReceiver.OnMailClosed()
        end)
    end,

    ["mail receiver: a failed take or a returned mail records nothing (RF1, RF2)"] = function(harness)
        run(harness, { bagsFull = true }, function(state, addon, board)
            local order = claimedOrder(board, harness)
            local subject = addon.MailQueue.TaggedSubject("ProfessionShare: 2x Thing", addon.MailQueue.Tag(order.id, "item"))
            state.inbox = { { sender = "Crafter", subject = subject, items = { { 5000, 2 } } } }
            addon.MailReceiver.OnMailShow()
            TakeInboxItem(1, 1)
            state.deliver()
            addon.MailReceiver.Scan()
            harness.equal(order.rcv, nil, "bags full: the items stayed")
            state.now = 100
            ReturnInboxItem(1)
            addon.MailReceiver.Scan()
            harness.equal(order.rcv, nil, "returned long after the failed take: not a pickup")
            harness.equal(board:Status(order), "claimed")
        end)
    end,
}
