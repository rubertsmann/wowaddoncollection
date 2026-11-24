-- RecipeDrops (pure) and the DROP / DROPA sync handlers.
local function fresh(harness)
    local addon = harness.addon()
    local RecipeDrops = addon.RecipeDrops
    RecipeDrops.mine, RecipeDrops.seen, RecipeDrops.alerts = {}, {}, {}
    return addon, RecipeDrops
end

local function newSync(addon, overrides)
    local sent, drops = {}, {}
    local environment = {
        send = function(message, channel, target) sent[#sent + 1] = { message = message, channel = channel, target = target } end,
        now = function() return 1000 end, random = function() return 0.5 end, store = addon.Store,
        orders = addon.Orders.New(function() return 1000 end, {}), me = function() return "Me-R" end, onChange = function() end,
        onRecipeDrop = function(sender, itemID) drops[#drops + 1] = { sender = sender, itemID = itemID } end,
    }
    for key, value in pairs(overrides or {}) do environment[key] = value end
    return addon.Sync.New(environment), sent, drops
end

return {
    ["recipe drops: settings default on, wrong types fall back, unknown keys refused"] = function(harness)
        local _, RecipeDrops = fresh(harness)
        local ui = {}
        harness.equal(RecipeDrops.Get(ui, "share"), true); harness.equal(RecipeDrops.Get(nil, "icon"), true)
        harness.truthy(RecipeDrops.Set(ui, "chat", false)); harness.equal(RecipeDrops.Get(ui, "chat"), false)
        ui.drops.icon = "yes"; harness.equal(RecipeDrops.Get(ui, "icon"), true, "wrong type -> default")
        harness.equal(RecipeDrops.Set(ui, "nope", true), false); harness.equal(RecipeDrops.Set(ui, "chat", "off"), false)
    end,

    ["recipe drops (RF1): message checks refuse malformed DROP and DROPA"] = function(harness)
        local _, RecipeDrops = fresh(harness)
        harness.equal(RecipeDrops.SanitizeDrop({ item = 14468 }), 14468)
        for _, bad in ipairs({ {}, { item = 0 }, { item = 1.5 }, { item = "14468" }, { item = 1e9 }, "x" }) do
            harness.equal(RecipeDrops.SanitizeDrop(bad), nil)
        end
        local itemID, status, rank = RecipeDrops.SanitizeAnswer({ item = 14468, s = "g", r = 280 })
        harness.equal(itemID, 14468); harness.equal(status, "g"); harness.equal(rank, 280)
        for _, bad in ipairs({ { item = 14468, s = "x", r = 1 }, { item = 14468, s = "g", r = 5000 }, { item = 14468, s = "g" },
            { item = -1, s = "r", r = 1 }, { s = "g", r = 1 } }) do
            harness.equal(RecipeDrops.SanitizeAnswer(bad), nil)
        end
    end,

    ["recipe drops: answer status follows the receiver's own decision"] = function(harness)
        local _, RecipeDrops = fresh(harness)
        harness.equal(RecipeDrops.AnswerStatus({ status = "learnable" }), "g")
        harness.equal(RecipeDrops.AnswerStatus({ status = "low" }), "r")
        for _, status in ipairs({ "known", "noProfession", "unreadable" }) do harness.equal(RecipeDrops.AnswerStatus({ status = status }), nil) end
        harness.equal(RecipeDrops.AnswerStatus(nil), nil)
    end,

    ["recipe drops: hint rows green first, then skill, max 3 and the rest counted; names escaped (RF3)"] = function(harness)
        local _, RecipeDrops = fresh(harness)
        harness.equal(RecipeDrops.HintRows(14468), nil, "not my drop")
        RecipeDrops.NoteMyDrop(14468, 100)
        local empty = RecipeDrops.HintRows(14468)
        harness.equal(#empty.rows, 0); harness.equal(empty.answered, 0)
        harness.truthy(RecipeDrops.AddAnswer("Bob", { item = 14468, s = "r", r = 240 }, 110))
        harness.truthy(RecipeDrops.AddAnswer("Anna", { item = 14468, s = "g", r = 280 }, 110))
        harness.truthy(RecipeDrops.AddAnswer("Cid", { item = 14468, s = "g", r = 300 }, 110))
        harness.truthy(RecipeDrops.AddAnswer("Dora", { item = 14468, s = "g", r = 265 }, 110))
        local hint = RecipeDrops.HintRows(14468, function(name) return name .. "!" end)
        harness.equal(#hint.rows, 3); harness.equal(hint.more, 1); harness.equal(hint.answered, 4)
        harness.equal(hint.rows[1].name, "Cid!"); harness.equal(hint.rows[1].color, "green"); harness.equal(hint.rows[1].rank, 300)
        harness.equal(hint.rows[3].name, "Dora!", "every green before the red Bob")
        harness.truthy(RecipeDrops.AddAnswer("Anna", { item = 14468, s = "g", r = 281 }, 120), "a second answer replaces the first")
        harness.equal(RecipeDrops.HintRows(14468).answered, 4)
        harness.equal(RecipeDrops.AddAnswer("Eve|cff", { item = 14468, s = "g", r = 1 }, 120), false, "unsafe sender name")
        harness.equal(RecipeDrops.HintRows(14468, function() return "A|cffB" end).rows[1].name, "A||cffB", "display text escaped")
    end,

    ["recipe drops (RF1): answers only for my own recent drops"] = function(harness)
        local _, RecipeDrops = fresh(harness)
        harness.equal(RecipeDrops.AddAnswer("Anna", { item = 999, s = "g", r = 1 }, 10), false, "never dropped for me")
        RecipeDrops.NoteMyDrop(999, 10)
        harness.equal(RecipeDrops.AddAnswer("Anna", { item = 999, s = "g", r = 1 }, 10 + RecipeDrops.ANSWER_SECONDS + 1), false, "too late")
        for itemID = 1, RecipeDrops.MAXIMUM_DROPS + 5 do RecipeDrops.NoteMyDrop(itemID, 20) end
        harness.equal(#RecipeDrops.mine, RecipeDrops.MAXIMUM_DROPS)
        harness.equal(RecipeDrops.MyDrop(1), nil, "the oldest drops are forgotten")
    end,

    ["recipe drops: the same DROP from the same sender within 60 s is a duplicate"] = function(harness)
        local _, RecipeDrops = fresh(harness)
        harness.equal(RecipeDrops.IsDuplicate("Anna", 1, 100), false)
        harness.equal(RecipeDrops.IsDuplicate("Anna", 1, 130), true)
        harness.equal(RecipeDrops.IsDuplicate("Bob", 1, 130), false, "another sender")
        harness.equal(RecipeDrops.IsDuplicate("Anna", 1, 161), false, "later again")
        for index = 1, 12 do RecipeDrops.AddAlert(index, "Anna", 100, index) end
        harness.equal(#RecipeDrops.alerts, RecipeDrops.MAXIMUM_ALERTS); harness.equal(RecipeDrops.alerts[1].itemID, 12)
        RecipeDrops.ClearAlerts(); harness.equal(#RecipeDrops.alerts, 0)
    end,

    ["recipe drops sync: DROP reaches the client hook, DROPA is stored, bad ones are rejected"] = function(harness)
        local addon, RecipeDrops = fresh(harness)
        local sync, sent, drops = newSync(addon)
        harness.equal(sync:OnMessage({ v = addon.PROTOCOL, t = "DROP", item = 14468 }, "Anna-R"), "ok")
        harness.equal(drops[1].sender, "Anna-R"); harness.equal(drops[1].itemID, 14468)
        local status = sync:OnMessage({ v = addon.PROTOCOL, t = "DROP", item = "x" }, "Anna-R")
        harness.equal(status, "error"); harness.equal(#drops, 1)
        RecipeDrops.NoteMyDrop(14468, 1000)
        harness.equal(sync:OnMessage({ v = addon.PROTOCOL, t = "DROPA", item = 14468, s = "g", r = 280 }, "Anna-R"), "ok")
        harness.equal(RecipeDrops.HintRows(14468).answered, 1)
        harness.equal(sync:OnMessage({ v = addon.PROTOCOL, t = "DROPA", item = 777, s = "g", r = 280 }, "Anna-R"), "ignored")
        sync:BroadcastDrop(14468)
        sync:AnswerDrop("Anna-R", 14468, "g", 280)
        harness.equal(sent[1].message.t, "DROP"); harness.equal(sent[1].channel, "GUILD"); harness.equal(sent[1].message.item, 14468)
        harness.equal(sent[2].message.t, "DROPA"); harness.equal(sent[2].channel, "WHISPER"); harness.equal(sent[2].target, "Anna-R")
        harness.equal(sent[2].message.s, "g"); harness.equal(sent[2].message.r, 280)
    end,

    ["recipe drops sync (RF2): a client without the DROP handlers drops them as unknown types"] = function(harness)
        local addon = fresh(harness)
        local library = LibStub("LibGuildSync-1.0")
        local oldPeer = library.Sync.New({ send = function() end, now = function() return 1 end, random = function() return 0.5 end,
            me = function() return "Old-R" end, protocol = addon.PROTOCOL })
        local status, reason = oldPeer:OnMessage({ v = addon.PROTOCOL, t = "DROP", item = 14468 }, "Anna-R")
        harness.equal(status, "dropped"); harness.truthy(tostring(reason):find("unknown message type"))
    end,
}
