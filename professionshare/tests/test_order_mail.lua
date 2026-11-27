-- Mails sent for an order: recorded in the order (ml), the "mailed" status, merge and validation, the mail digest in
-- HELLO, and the mail sender writing the entries for sends and for "Done".

local function replica(harness)
    local addon = harness.addon()
    return addon, addon.Orders.New(function() return harness.clock end, {})
end

local function itemEntry(sender, recipient, complete, items)
    return { m = "item", b = sender, r = recipient, c = complete or nil, i = items }
end

return {
    ["order mail: a complete item mail makes the order mailed; a partial one does not"] = function(harness)
        local _, board = replica(harness)
        local order = board:Create("Req-R", 5, 2)
        board:Claim(order.id, "Crafter-R")
        harness.truthy(board:RecordMail(order.id, itemEntry("Crafter-R", "Req-R", false, { 5000, 1 })))
        harness.equal(board:Status(order), "claimed", "partly mailed keeps the status")
        harness.truthy(board:RecordMail(order.id, itemEntry("Crafter-R", "Req-R", true, { 5000, 1 })))
        harness.equal(board:Status(order), "mailed")
        harness.equal(#order.ml, 2, "two mails in the same second both stay")
        harness.truthy(order.ml[2].t > order.ml[1].t)
        board:RecordMail(order.id, { m = "mats", b = "Req-R", r = "Crafter-R", c = true })
        harness.equal(board:Status(order), "mailed", "a reagent mail does not change the status")
        board:Close(order.id, "Req-R", "done")
        harness.equal(board:Status(order), "done", "closing still works and wins")
    end,

    ["order mail: mailed sorts between claimed and done and is not hidden as closed"] = function(harness)
        local _, board = replica(harness)
        local open = board:Create("Req-R", 1, 1)
        harness.clock = harness.clock + 1
        local mailed = board:Create("Req-R", 2, 1)
        board:RecordMail(mailed.id, itemEntry("Crafter-R", "Req-R", true))
        harness.clock = harness.clock + 1
        local claimed = board:Create("Req-R", 3, 1)
        board:Claim(claimed.id, "Crafter-R")
        local list = board:List({})
        harness.equal(#list, 3)
        harness.equal(list[1].id, open.id); harness.equal(list[2].id, claimed.id); harness.equal(list[3].id, mailed.id)
    end,

    ["order mail: entries merge to the same list on every client"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local order = a:Create("Req-R", 5, 1)
        b:Merge(order)
        a:RecordMail(order.id, { m = "mats", b = "Req-R", r = "Crafter-R", c = true, i = { 2840, 2, 2589, 1 } })
        harness.clock = harness.clock + 1
        b:RecordMail(order.id, itemEntry("Crafter-R", "Req-R", true, { 5000, 1 }))
        harness.truthy(a:Merge(b:Get(order.id)))
        harness.truthy(b:Merge(a:Get(order.id)))
        harness.equal(#a:Get(order.id).ml, 2)
        harness.equal(a.MailVersion(a:Get(order.id)), b.MailVersion(b:Get(order.id)))
        harness.equal(a:Status(a:Get(order.id)), "mailed")
        harness.equal(a:Merge(b:Get(order.id)), false, "a second merge changes nothing")
        harness.equal(a:Get(order.id).ml[1].i[3], 2589)
    end,

    ["order mail: bad entries are dropped, never the order (RF3)"] = function(harness)
        local addon, board = replica(harness)
        local copy = addon.Orders.Sanitize(board:Create("Req-R", 5, 1))
        local manyItems = {}
        for index = 1, 26 do manyItems[index] = index end
        copy.ml = { itemEntry("Crafter-R", "Req-R", true, { 5000, 1 }),
            { m = "gold", b = "Crafter-R", r = "Req-R", t = 1 },
            { m = "item", b = "Bad|Name", r = "Req-R", t = 2 },
            { m = "item", b = "Crafter-R", r = "Req-R", t = 3, i = { 5000, -1 } },
            { m = "item", b = "Crafter-R", r = "Req-R", t = 4, i = { 5000 } },
            { m = "item", b = "Crafter-R", r = "Req-R", t = 5, i = manyItems },
            { m = "item", b = "Crafter-R", r = "Req-R", t = 6, c = "yes" },
            { m = "item", b = "Crafter-R", t = 7 }, "garbage" }
        copy.ml[1].t = harness.clock
        local clean = addon.Orders.Sanitize(copy)
        harness.truthy(clean, "the order survives")
        harness.equal(#clean.ml, 1)
        harness.equal(clean.ml[1].i[2], 1)
        local tooLong = {}
        for index = 1, 121 do tooLong[index] = { m = "item", b = "Crafter-R", r = "Req-R", t = index } end
        copy.ml = tooLong
        clean = addon.Orders.Sanitize(copy)
        harness.truthy(clean); harness.equal(clean.ml, nil, "a list too long is not read")
        harness.equal(board:RecordMail("no-such-order", itemEntry("Crafter-R", "Req-R", true)), nil)
    end,

    ["order mail: the newest 30 entries are kept"] = function(harness)
        local _, board = replica(harness)
        local order = board:Create("Req-R", 5, 1)
        for _ = 1, 35 do harness.clock = harness.clock + 1; board:RecordMail(order.id, itemEntry("Crafter-R", "Req-R", false)) end
        harness.equal(#order.ml, 30)
    end,

    ["order mail: the mail digest pushes only to peers that send it (RF1)"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local order = a:Create("Req-R", 5, 1)
        b:Merge(order)
        a:RecordMail(order.id, itemEntry("Crafter-R", "Req-R", true))
        harness.equal(#a:Missing(b:Digest(), 40, b:ExtraDigest()), 0, "a 2.9 peer (no mdig) is not pushed")
        harness.equal(#a:Missing(b:Digest(), 40, b:ExtraDigest(), b:MailDigest()), 1, "a 2.10 peer is")
        b:Merge(a:Get(order.id))
        harness.equal(#a:Missing(b:Digest(), 40, b:ExtraDigest(), b:MailDigest()), 0, "in sync")
        harness.equal(a.Version(a:Get(order.id)), a.Version(b:Get(order.id)), "the order version is unchanged by mails")
    end,

    ["order mail: history rows, items text, who may mark by hand (RF5)"] = function(harness)
        local addon, board = replica(harness)
        local order = board:Create("Req-R", 5, 1)
        harness.clock = harness.clock + 1
        board:Claim(order.id, "Crafter-R")
        local itemRecipient, matsRecipient = addon.Model.MarkMailTargets(board, order, "Crafter-R")
        harness.equal(itemRecipient, "Req-R"); harness.equal(matsRecipient, nil)
        itemRecipient, matsRecipient = addon.Model.MarkMailTargets(board, order, "Req-R")
        harness.equal(itemRecipient, nil); harness.equal(matsRecipient, "Crafter-R")
        harness.clock = harness.clock + 1
        board:RecordMail(order.id, { m = "mats", b = "Req-R", r = "Crafter-R", c = true, i = { 2840, 2 } })
        harness.clock = harness.clock + 1
        board:RecordMail(order.id, itemEntry("Crafter-R", "Req-R", true))
        harness.equal(addon.Model.MarkMailTargets(board, order, "Crafter-R"), nil, "already mailed")
        local kinds = {}
        for _, historyRow in ipairs(addon.Model.OrderHistory(order)) do kinds[#kinds + 1] = historyRow.kind .. (historyRow.mail and (":" .. historyRow.mail.m) or "") end
        harness.equal(table.concat(kinds, ","), "created,claim,mail:mats,mail:item")
        harness.equal(addon.Model.MailItemsText({ 2840, 2, 2589, 1 }, function(itemID) return itemID == 2840 and "Copper|Bar" or nil end),
            "2x Copper||Bar, 1x item 2589", "names escaped")
        local rows = addon.Model.BuildOrderRows(addon.Store, board, "all", false, "Crafter-R")
        harness.equal(rows[1].status, "mailed")
        harness.truthy(rows[1].canWithdraw and rows[1].canDone, "a mailed order stays actionable")
        harness.truthy(addon.Model.BuildOrderRows(addon.Store, board, "all", false, "Req-R")[1].canCancel)
        board:Close(order.id, "Req-R", "done")
        harness.equal(addon.Model.MarkMailTargets(board, order, "Req-R"), nil, "closed: nothing to mark")
    end,

    ["order mail: a mail to me by someone else is news until seen"] = function(harness)
        local addon, board = replica(harness)
        local order = board:Create("Req-R", 5, 1)
        board:RecordMail(order.id, { m = "mats", b = "Req-R", r = "Crafter-R", c = true })
        harness.equal(#addon.Notify.UnseenMail(board, "Req-R", nil), 0, "my own mail is no news")
        local unseen = addon.Notify.UnseenMail(board, "Crafter-R", nil)
        harness.equal(#unseen, 1); harness.equal(unseen[1].kind, "mail"); harness.equal(unseen[1].mail.m, "mats")
        local mailSeen = addon.Notify.MarkMailSeen(board, nil, order)
        harness.equal(#addon.Notify.UnseenMail(board, "Crafter-R", mailSeen), 0)
        harness.clock = harness.clock + 1
        board:RecordMail(order.id, { m = "mats", b = "Req-R", r = "Crafter-R", c = true })
        harness.equal(#addon.Notify.UnseenMail(board, "Crafter-R", mailSeen), 1, "a further mail is news again")
        mailSeen = addon.Notify.MarkMailSeen(board, mailSeen)
        harness.equal(#addon.Notify.UnseenMail(board, "Crafter-R", mailSeen), 0)
        board.db[order.id] = nil
        harness.equal(next(addon.Notify.MarkMailSeen(board, mailSeen)), nil, "pruned orders are forgotten")
    end,

    ["order mail: MailQueue builds the entry from what a mail carried"] = function(harness)
        local addon = harness.addon()
        local job = { mode = "mats", recipient = "Crafter-R", items = { [2840] = 6, [2589] = 3 } }
        local delivered = addon.MailQueue.Delivered(job, { [2840] = 10, [2589] = 1, [9999] = 4 })
        harness.equal(delivered[2840], 6, "at most what the job needs"); harness.equal(delivered[2589], 1); harness.equal(delivered[9999], nil)
        local entry = addon.MailQueue.MailEntry(job, "Me-R", delivered, false, true)
        harness.equal(entry.m, "mats"); harness.equal(entry.b, "Me-R"); harness.equal(entry.r, "Crafter-R")
        harness.equal(entry.c, nil); harness.equal(entry.h, true)
        harness.equal(table.concat(entry.i, ","), "2589,1,2840,6")
        harness.equal(addon.MailQueue.MailEntry(job, "Me-R", {}, true, false).i, nil)
    end,
}
