-- Mail queue: jobs from orders (mats to the crafter, item to the requester), queue order, the attachment plan (whole
-- stacks, exact splits, missing, bound, the 12-attachment limit), what a sent mail leaves, and the load sanitizer.

local function setup(harness)
    local addon = harness.addon()
    local board = addon.Orders.New(function() return harness.clock end, {})
    addon.Store.PutCatalog({
        [100] = { name = "Copper Thing", produces = 5000, reagents = { { itemID = 2840, count = 2 }, { itemID = 2589, count = 1 } } },
        [200] = { name = "Nothing known", reagents = {} },
    })
    local backing = {}
    local queue = addon.MailQueue.New(backing, "Me-R", function() return harness.clock end)
    return addon, board, queue, backing
end

local function stack(bag, slot, itemID, count, extra)
    local entry = { bag = bag, slot = slot, itemID = itemID, count = count }
    for key, value in pairs(extra or {}) do entry[key] = value end
    return entry
end

local function actionsByKind(plan)
    local counts = { whole = 0, split = 0 }
    for _, action in ipairs(plan.actions) do counts[action.kind] = counts[action.kind] + 1 end
    return counts
end

return {
    ["mail queue: mats job = reagents x quantity to the chosen claimer"] = function(harness)
        local addon, board = setup(harness)
        local order = board:Create("Req-R", 100, 3)
        local job = addon.MailQueue.JobForOrder(addon.Store, order, "mats", "Crafter-R", "Me-R")
        harness.equal(job.recipient, "Crafter-R"); harness.equal(job.mode, "mats")
        harness.equal(job.items[2840], 6); harness.equal(job.items[2589], 3)
        harness.equal(job.label, "Copper Thing"); harness.equal(job.qty, 3)
    end,

    ["mail queue: item job = the product x quantity to the requester"] = function(harness)
        local addon, board = setup(harness)
        local order = board:Create("Req-R", 100, 2)
        local job = addon.MailQueue.JobForOrder(addon.Store, order, "item", "Req-R", "Me-R")
        harness.equal(job.items[5000], 2); harness.equal(job.recipient, "Req-R")
    end,

    ["mail queue: no recipient, myself, or no data -> no job with a reason"] = function(harness)
        local addon, board = setup(harness)
        local order = board:Create("Req-R", 100, 1)
        local job, reason = addon.MailQueue.JobForOrder(addon.Store, order, "mats", nil, "Me-R")
        harness.equal(job, nil); harness.equal(reason, "noRecipient")
        job, reason = addon.MailQueue.JobForOrder(addon.Store, order, "item", "Me-R", "Me-R")
        harness.equal(job, nil); harness.equal(reason, "self")
        local empty = board:Create("Req-R", 200, 1)
        job, reason = addon.MailQueue.JobForOrder(addon.Store, empty, "mats", "Crafter-R", "Me-R")
        harness.equal(job, nil); harness.equal(reason, "noData")
        job, reason = addon.MailQueue.JobForOrder(addon.Store, empty, "item", "Req-R", "Me-R")
        harness.equal(job, nil); harness.equal(reason, "noData")
        job, reason = addon.MailQueue.JobForOrder(addon.Store, order, "mats", "Bad|Name", "Me-R")
        harness.equal(job, nil); harness.equal(reason, "noRecipient")
    end,

    ["mail queue: add, no duplicates, move up, remove; saved per character"] = function(harness)
        local addon, board, queue, backing = setup(harness)
        local first = addon.MailQueue.JobForOrder(addon.Store, board:Create("Req-R", 100, 1), "mats", "A-R", "Me-R")
        harness.clock = harness.clock + 1
        local second = addon.MailQueue.JobForOrder(addon.Store, board:Create("Req-R", 100, 2), "item", "Req-R", "Me-R")
        harness.equal(queue:Add(first), true)
        local again, reason = queue:Add(first)
        harness.equal(again, false); harness.equal(reason, "duplicate")
        harness.equal(queue:Add(second), true)
        harness.equal(queue:First().id, first.id)
        queue:MoveUp(second.id); harness.equal(queue:First().id, second.id)
        queue:MoveUp(first.id); harness.equal(queue:First().id, first.id)
        harness.equal(#backing["Me-R"], 2)
        local other = addon.MailQueue.New(backing, "Alt-R", function() return harness.clock end)
        harness.equal(#other:List(), 0, "another character has its own queue")
        queue:Remove(first.id); harness.equal(#queue:List(), 1)
        harness.equal(queue:Get(second.id).id, second.id)
    end,

    ["mail queue: plan takes whole stacks that fit, splits the rest into a free slot"] = function(harness)
        local addon = setup(harness)
        local job = { id = "j", items = { [2840] = 6 } }
        local plan = addon.MailQueue.Plan(job, { stack(0, 1, 2840, 20), stack(0, 2, 2840, 5) }, 1, 12)
        local kinds = actionsByKind(plan)
        harness.equal(kinds.whole, 1); harness.equal(kinds.split, 1)
        harness.equal(plan.actions[1].count, 5); harness.equal(plan.actions[1].slot, 2)
        harness.equal(plan.actions[2].kind, "split"); harness.equal(plan.actions[2].count, 1); harness.equal(plan.actions[2].slot, 1)
        harness.equal(plan.attached[2840], 6)
        harness.equal(next(plan.missing), nil)
    end,

    ["mail queue: plan without a free bag slot leaves the split part missing"] = function(harness)
        local addon = setup(harness)
        local plan = addon.MailQueue.Plan({ id = "j", items = { [2840] = 6 } }, { stack(0, 1, 2840, 20) }, 0, 12)
        harness.equal(#plan.actions, 0)
        harness.equal(plan.missing[2840], 6); harness.equal(plan.noFreeSlot, true)
    end,

    ["mail queue: plan skips bound and locked stacks and reports what is not there"] = function(harness)
        local addon = setup(harness)
        local plan = addon.MailQueue.Plan({ id = "j", items = { [2840] = 4, [2589] = 3 } },
            { stack(0, 1, 2840, 4, { bound = true }), stack(0, 2, 2589, 2), stack(0, 3, 2589, 5, { locked = true }) }, 2, 12)
        harness.equal(plan.missing[2840], 4); harness.equal(plan.bound[2840], true)
        harness.equal(plan.attached[2589], 2); harness.equal(plan.missing[2589], 1)
    end,

    ["mail queue: plan stops at the attachment limit, the rest is deferred"] = function(harness)
        local addon = setup(harness)
        local stacks = {}
        for slot = 1, 15 do stacks[slot] = stack(0, slot, 2840, 1) end
        local plan = addon.MailQueue.Plan({ id = "j", items = { [2840] = 15 } }, stacks, 3, 12)
        harness.equal(#plan.actions, 12); harness.equal(plan.attached[2840], 12)
        harness.equal(plan.deferred[2840], 3); harness.equal(plan.missing[2840], nil)
        local fewer = addon.MailQueue.Plan({ id = "j", items = { [2840] = 15 } }, stacks, 3, 4)
        harness.equal(#fewer.actions, 4, "attachment slots already in use count against the limit")
    end,

    ["mail queue: a sent mail reduces the job; a fully sent job is removed"] = function(harness)
        local addon, board, queue = setup(harness)
        local job = addon.MailQueue.JobForOrder(addon.Store, board:Create("Req-R", 100, 3), "mats", "A-R", "Me-R")
        queue:Add(job)
        local left = queue:ApplySent(job.id, { [2840] = 6, [2589] = 1, [9999] = 4 })
        harness.equal(left, true)
        harness.equal(queue:Get(job.id).items[2840], nil); harness.equal(queue:Get(job.id).items[2589], 2)
        harness.equal(queue:ApplySent(job.id, { [2589] = 5 }), false)
        harness.equal(queue:Get(job.id), nil)
    end,

    ["mail queue: the job keeps working after its order is gone"] = function(harness)
        local addon, board, queue = setup(harness)
        local order = board:Create("Req-R", 100, 1)
        local job = addon.MailQueue.JobForOrder(addon.Store, order, "mats", "A-R", "Me-R")
        queue:Add(job)
        board.db[order.id] = nil
        harness.equal(queue:First().label, "Copper Thing")
        harness.equal(queue:First().items[2840], 2)
    end,

    ["mail queue: Mail tab rows share the bag contents in queue order and escape names"] = function(harness)
        local addon = setup(harness)
        local jobs = {
            { id = "a", mode = "mats", recipient = "A-R", label = "Copper|Thing", qty = 1, items = { [2840] = 4 } },
            { id = "b", mode = "item", recipient = "B-R", label = "Other", qty = 2, items = { [2840] = 3, [2589] = 1 } },
        }
        local names = { [2840] = "Copper Bar" }
        local rows = addon.Model.BuildMailRows(jobs, { [2840] = 5 }, function(itemID) return names[itemID] end, "a")
        harness.equal(#rows, 2)
        harness.equal(rows[1].missingText, ""); harness.equal(rows[1].isCurrent, true)
        harness.equal(rows[1].label, "Copper||Thing")
        harness.equal(rows[2].missingText, "2x Copper Bar, 1x item 2589", "only 1 bar is left for the second job")
        harness.equal(rows[2].itemsText, "3x Copper Bar, 1x item 2589")
    end,

    ["mail queue: the recipe name is looked up by id; the job's snapshot is only the fallback"] = function(harness)
        local addon = setup(harness)
        local known = { id = "k", mode = "mats", recipient = "A-R", recipeID = 100, label = "Old snapshot", qty = 1, items = { [2840] = 1 } }
        local unknown = { id = "u", mode = "mats", recipient = "A-R", recipeID = 777, label = "Snapshot", qty = 1, items = { [2840] = 1 } }
        harness.equal(addon.Model.MailJobRecipeName(addon.Store, known), "Copper Thing")
        harness.equal(addon.Model.MailJobRecipeName(addon.Store, unknown), "Snapshot")
        local rows = addon.Model.BuildMailRows({ known, unknown }, {}, function() return nil end, nil, addon.Store)
        harness.equal(rows[1].label, "Copper Thing"); harness.equal(rows[2].label, "Snapshot")
    end,

    ["mail queue: the load sanitizer keeps good jobs and drops broken ones"] = function(harness)
        local addon = setup(harness)
        local saved = { mailQueue = {
            ["Me-R"] = {
                { id = "o:mats", orderID = "o", mode = "mats", recipient = "A-R", recipeID = 100, qty = 1, label = "X",
                    items = { [2840] = 2 }, createdAt = 5 },
                { id = "bad", mode = "weird", recipient = "A-R", items = { [2840] = 2 } },
                { id = "bad2", orderID = "o2", mode = "item", recipient = "A|R", recipeID = 1, qty = 1, items = { [1] = 1 } },
                { id = "bad3", orderID = "o3", mode = "item", recipient = "A-R", recipeID = 1, qty = 1, items = { [1] = -3 } },
                "not a job",
            },
            ["Bad|Key"] = {},
            [5] = "nope",
        } }
        local dropped = addon.MailQueue.SanitizePersisted(saved)
        harness.equal(#saved.mailQueue["Me-R"], 1)
        harness.equal(saved.mailQueue["Me-R"][1].id, "o:mats")
        harness.equal(saved.mailQueue["Bad|Key"], nil); harness.equal(saved.mailQueue[5], nil)
        harness.truthy(dropped >= 4)
        local fresh = { mailQueue = "garbage" }
        addon.MailQueue.SanitizePersisted(fresh)
        harness.equal(type(fresh.mailQueue), "table")
    end,
}
