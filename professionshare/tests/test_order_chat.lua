-- Order chat and history: stored in the order record, merged as a union, synced with protocol 2.9.
local function replica(harness)
    local addon = harness.addon()
    return addon, addon.Orders.New(function() return harness.clock end, {})
end

local function texts(order)
    local out = {}
    for _, message in ipairs(order.msgs or {}) do out[#out + 1] = message.b .. ":" .. message.x end
    return table.concat(out, ",")
end

return {
    ["order chat: messages merge to the same list in any arrival order"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        b:Merge(order)
        harness.clock = harness.clock + 1
        a:AddMessage(order.id, "Bob-R", "hello")
        b:AddMessage(order.id, "Ann-R", "on it")
        harness.clock = harness.clock + 1
        a:AddMessage(order.id, "Bob-R", "thanks")
        harness.truthy(b:Merge(a:Get(order.id)))
        harness.truthy(a:Merge(b:Get(order.id)))
        harness.equal(texts(a:Get(order.id)), texts(b:Get(order.id)))
        harness.equal(#a:Get(order.id).msgs, 3)
        harness.equal(a:Merge(b:Get(order.id)), false, "a second merge changes nothing")
        harness.equal(a.ExtraVersion(a:Get(order.id)), b.ExtraVersion(b:Get(order.id)))
    end,

    ["order chat: two messages in the same second by one author both stay"] = function(harness)
        local _, a = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        a:AddMessage(order.id, "Bob-R", "one"); a:AddMessage(order.id, "Bob-R", "two")
        harness.equal(texts(order), "Bob-R:one,Bob-R:two")
    end,

    ["order chat: the newest 30 are kept, the same ones on every client (RF3)"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        b:Merge(order)
        for index = 1, 20 do harness.clock = harness.clock + 1; a:AddMessage(order.id, "Bob-R", "a" .. index) end
        for index = 1, 20 do harness.clock = harness.clock + 1; b:AddMessage(order.id, "Ann-R", "b" .. index) end
        a:Merge(b:Get(order.id)); b:Merge(a:Get(order.id))
        harness.equal(#a:Get(order.id).msgs, 30)
        harness.equal(texts(a:Get(order.id)), texts(b:Get(order.id)))
        harness.equal(a:Get(order.id).msgs[1].x, "a11", "the 10 oldest dropped")
    end,

    ["order chat: bad entries are dropped, the order still merges (RF5)"] = function(harness)
        local addon, a = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        local copy = addon.Orders.Sanitize(order)
        copy.msgs = { { b = "Ann-R", t = harness.clock, x = "fine" },
            { b = "Bad|Name", t = 1, x = "x" }, { b = "Ann-R", t = 2, x = "ctrl\1char" }, { b = "Ann-R", t = 3, x = string.rep("x", 161) },
            { b = "Ann-R", t = 4, x = "   " }, "garbage", { b = "Ann-R", t = 5.5, x = "float" } }
        copy.ev = { { k = "claim", b = "Ann-R", t = 7 }, { k = "explode", b = "Ann-R", t = 8 } }
        local clean = addon.Orders.Sanitize(copy)
        harness.truthy(clean, "the order survives")
        harness.equal(texts(clean), "Ann-R:fine")
        harness.equal(#clean.ev, 1)
        copy.msgs = "nope"
        harness.equal(addon.Orders.Sanitize(copy).msgs, nil)
        local long = {}
        for index = 1, 121 do long[index] = { b = "Ann-R", t = index, x = "x" } end
        copy.msgs = long
        harness.equal(addon.Orders.Sanitize(copy).msgs, nil, "a list too long is not read")
    end,

    ["order chat: AddMessage trims, cuts long text, refuses empty text and unknown orders"] = function(harness)
        local addon, a = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        harness.equal(a:AddMessage(order.id, "Bob-R", "   "), nil)
        harness.equal(a:AddMessage("nope", "Bob-R", "hi"), nil)
        local message = a:AddMessage(order.id, "Bob-R", "  " .. string.rep("ä", 100) .. "  ")
        harness.truthy(#message.x <= addon.Orders.MAXIMUM_MESSAGE_BYTES)
        harness.truthy(addon.Utility.IsValidUtf8(message.x))
    end,

    ["order history: claim, withdraw and close record events that merge"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        b:Merge(order)
        harness.clock = harness.clock + 1; b:Claim(order.id, "Ann-R")
        harness.clock = harness.clock + 1; b:Withdraw(order.id, "Ann-R")
        harness.clock = harness.clock + 1; b:Claim(order.id, "Ann-R")
        harness.clock = harness.clock + 1; b:Close(order.id, "Ann-R", "done")
        a:Merge(b:Get(order.id))
        local kinds = {}
        for _, event in ipairs(a:Get(order.id).ev) do kinds[#kinds + 1] = event.k end
        harness.equal(table.concat(kinds, ","), "claim,withdraw,claim,done")
    end,

    ["order chat: WithoutChat drops only the chat; MergeMessage adds one message to a known order"] = function(harness)
        local addon, a = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        a:AddMessage(order.id, "Bob-R", "hi"); a:Claim(order.id, "Ann-R")
        local copy = addon.Orders.WithoutChat(order)
        harness.equal(copy.msgs, nil); harness.truthy(copy.ev); harness.truthy(order.msgs)
        harness.truthy(a:MergeMessage(order.id, { b = "Ann-R", t = harness.clock, x = "ok" }))
        harness.equal(a:MergeMessage(order.id, { b = "Ann-R", t = harness.clock, x = "ok" }), false)
        harness.equal(a:MergeMessage("unknown", { b = "Ann-R", t = harness.clock, x = "ok" }), false)
        harness.equal(a:MergeMessage(order.id, { b = "Ann-R", t = harness.clock, x = "a\1b" }), false)
    end,

    ["order chat: Missing pushes chat only to peers that send an extra digest (RF1)"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        b:Merge(order)
        a:AddMessage(order.id, "Bob-R", "hello")
        local remoteDigest = b:Digest(100)
        harness.equal(#a:Missing(remoteDigest, 40), 0, "an old peer (no xdig) is not sent the order again")
        harness.equal(#a:Missing(remoteDigest, 40, b:ExtraDigest(100)), 1, "a 2.9 peer without the chat gets it")
        b:Merge(a:Get(order.id))
        harness.equal(#a:Missing(b:Digest(100), 40, b:ExtraDigest(100)), 0, "in sync: nothing to send")
        harness.equal(a.Version(a:Get(order.id)), b.Version(b:Get(order.id)), "the base version ignores the chat")
    end,

    ["order history: derived from the fields for old orders, merged with recorded events, oldest first"] = function(harness)
        local addon, a = replica(harness)
        local order = a:Create("Bob-R", 5, 1)
        -- a 2.8 peer's claim: no event recorded, only the claim field
        order.claims["Old-R"] = { state = "withdrawn", t = harness.clock + 1 }
        harness.clock = harness.clock + 2; a:Claim(order.id, "Ann-R")
        harness.clock = harness.clock + 1; a:Close(order.id, "Ann-R", "done")
        local parts = {}
        for _, row in ipairs(addon.Model.OrderHistory(order)) do parts[#parts + 1] = row.kind .. ":" .. row.who end
        harness.equal(table.concat(parts, ","), "created:Bob-R,withdraw:Old-R,claim:Ann-R,done:Ann-R", "each change once")
    end,

    ["order overview: reagents for the whole quantity, tools from the catalog, escaped note"] = function(harness)
        local addon, a = replica(harness)
        addon.Store.PutCatalog({ [5] = { name = "Bolt", reagents = { { itemID = 9, count = 2, name = "Cloth" } }, tools = { "Loom" } } })
        local order = a:Create("Bob-R", 5, 3, "a|b")
        local overview = addon.Model.OrderOverview(addon.Store, a, order, function() return 5 end, function() return nil end)
        harness.equal(overview.reagents[1].count, 6); harness.equal(overview.reagents[1].have, 5)
        harness.equal(overview.reagents[1].enough, false)
        harness.equal(overview.tools[1], "Loom"); harness.equal(overview.note, "a||b")
        harness.equal(addon.Store.SanitizeCatalogEntry({ reagents = {}, tools = { "A|B" } }), nil)
        harness.equal(addon.Store.SanitizeCatalogEntry({ reagents = {}, tools = { "a", "b", "c", "d", "e" } }), nil)
        harness.equal(addon.Store.SanitizeCatalogEntry({ reagents = {}, tools = {} }).tools, nil)
    end,

    ["order chat notify: unread only on my orders, by others, until I open the chat"] = function(harness)
        local addon, a = replica(harness)
        local N = addon.Notify
        local mine = a:Create("Me-R", 5, 1)
        local claimed = a:Create("Bob-R", 6, 1); a:Claim(claimed.id, "Me-R")
        local other = a:Create("Bob-R", 7, 1)
        harness.clock = harness.clock + 1
        a:AddMessage(mine.id, "Me-R", "my own words")
        a:AddMessage(mine.id, "Ann-R", "question")
        a:AddMessage(claimed.id, "Bob-R", "thanks")
        a:AddMessage(other.id, "Bob-R", "not for me")
        local seen = N.MarkAllChatSeen(a, nil)
        harness.equal(#N.UnseenChat(a, "Me-R", seen), 0, "the first start: older chat is not news")
        harness.clock = harness.clock + 1
        a:AddMessage(mine.id, "Ann-R", "again"); a:AddMessage(claimed.id, "Bob-R", "ping"); a:AddMessage(other.id, "Bob-R", "x")
        local unseen = N.UnseenChat(a, "Me-R", seen)
        harness.equal(#unseen, 2); harness.equal(unseen[1].kind, "chat")
        seen = N.MarkChatSeen(seen, mine)
        harness.equal(#N.UnseenChat(a, "Me-R", seen), 1)
        harness.equal((N.ChatUnread(claimed, "Me-R", seen)), 1)
        a.db[claimed.id] = nil
        harness.equal(N.PruneChatSeen(a, seen)[claimed.id], nil)
    end,
}
