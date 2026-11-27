-- Dev mail probe against a simulated mailbox: it never sends, splits stacks for exact amounts, never leaves an item on
-- the cursor, and in sequential mode waits for MAIL_SEND_INFO_UPDATE before the next attachment.

local SAVED = { "CreateFrame", "GetTime", "C_Timer", "C_Container", "CursorHasItem", "ClearCursor", "GetCursorInfo",
    "ClickSendMailItemButton", "GetSendMailItem", "HasSendMailItem", "SendMail", "MailFrame", "MailFrameTab2",
    "SendMailFrame", "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox", "ATTACHMENTS_MAX_SEND",
    "InCombatLockdown", "UnitName", "GetSendMailPrice", "PickupContainerItem", "SplitContainerItem",
    "GetContainerItemInfo", "GetContainerNumSlots" }

-- a fake client: bag 0 holds the given stacks; cursor and attachments behave like the game (one item at a time)
local function world(options)
    options = options or {}
    local state = { now = 0, cursor = nil, attachments = {}, sent = 0, clears = 0, splits = {}, pickups = 0,
        timeline = {}, eventHandler = nil, slots = options.slots or 4,
        bags = options.bags or { { itemID = 2840, count = 20 }, { itemID = 2589, count = 5 } } }
    local saved = {}
    for _, name in ipairs(SAVED) do saved[name] = _G[name] end
    state.restore = function() for _, name in ipairs(SAVED) do _G[name] = saved[name] end end
    local function editBox()
        local box = { text = "" }
        function box:SetText(text) self.text = text end
        function box:GetText() return self.text end
        return box
    end
    local function fire(eventName, ...) if state.eventHandler then state.eventHandler(nil, eventName, ...) end end
    CreateFrame = function()
        local frame = {}
        function frame:RegisterEvent() end
        function frame:SetScript(_, handler) state.eventHandler = handler end
        return frame
    end
    GetTime = function() state.now = state.now + 0.05; return state.now end
    C_Timer = { After = function(_, callback) callback() end }
    C_Container = {
        GetContainerNumSlots = function(bagID) return bagID == 0 and state.slots or 0 end,
        GetContainerItemInfo = function(bagID, slot)
            local stack = bagID == 0 and state.bags[slot]
            if not stack or stack.count == 0 then return nil end
            return { itemID = stack.itemID, stackCount = stack.count, isLocked = false, isBound = stack.bound or false }
        end,
        -- with an item on the cursor and an empty slot: the cursor stack is dropped there (taken from its source)
        PickupContainerItem = function(bagID, slot)
            local stack = state.bags[slot]
            if state.cursor and not stack then
                state.bags[slot] = { itemID = state.cursor.itemID, count = state.cursor.count }
                if state.cursor.source then state.cursor.source.count = state.cursor.source.count - state.cursor.count end
                state.cursor = nil
                return
            end
            state.pickups = state.pickups + 1
            state.cursor = { itemID = stack.itemID, count = stack.count }
        end,
        SplitContainerItem = function(bagID, slot, count)
            state.splits[#state.splits + 1] = count
            local stack = state.bags[slot]
            state.cursor = { itemID = stack.itemID, count = count, source = stack }
        end,
    }
    CursorHasItem = function() return state.cursor ~= nil end
    ClearCursor = function() state.clears = state.clears + 1; state.cursor = nil end
    ClickSendMailItemButton = function(index)
        state.timeline[#state.timeline + 1] = "click " .. index
        if options.clickKeepsCursor then return end   -- e.g. a soulbound item: refused, stays on the cursor
        if state.cursor then
            state.attachments[index] = state.cursor
            state.cursor = nil
            if not options.silentServer then fire("MAIL_SEND_INFO_UPDATE") end
        end
    end
    GetSendMailItem = function(index)
        local attachment = state.attachments[index]
        if not attachment then return nil end
        return "Item " .. attachment.itemID, attachment.itemID, nil, attachment.count
    end
    HasSendMailItem = function(index) return state.attachments[index] ~= nil end
    SendMail = function() state.sent = state.sent + 1 end
    MailFrame = { IsShown = function() return options.mailboxClosed ~= true end }
    SendMailFrame = { IsShown = function() return true end }
    MailFrameTab2 = { Click = function() state.tabClicked = true end }
    SendMailNameEditBox, SendMailSubjectEditBox, SendMailBodyEditBox = editBox(), editBox(), editBox()
    ATTACHMENTS_MAX_SEND = 12
    InCombatLockdown = function() return false end
    UnitName = function() return "Me" end
    GetSendMailPrice = function() return 30 end
    return state
end

local function probe(harness)
    local addon = harness.addon()
    addon.IS_DEVELOPMENT_BUILD = true
    addon.UI = { ShowExport = function(text) addon.exported = text end }
    addon.db = addon.db or {}
    assert(loadfile("UI/MailProbe.lua"))("ProfessionShare", addon)
    return addon
end

return {
    ["mail probe: request parsing pairs small numbers with the item id before them"] = function(harness)
        local addon = probe(harness)
        local requests = addon.MailProbe.ParseRequests("2840 6 2589 14047 3")
        harness.equal(#requests, 3)
        harness.equal(requests[1].itemID, 2840); harness.equal(requests[1].count, 6)
        harness.equal(requests[2].itemID, 2589); harness.equal(requests[2].count, nil)
        harness.equal(requests[3].itemID, 14047); harness.equal(requests[3].count, 3)
    end,

    ["mail probe: fill sets recipient, subject and body on the Send Mail tab and never sends"] = function(harness)
        local state = world()
        local ok, failure = pcall(function()
            local addon = probe(harness)
            addon.SlashCommands.mailprobe("fill Crafter")
            harness.equal(state.tabClicked, true)
            harness.equal(SendMailNameEditBox:GetText(), "Crafter")
            harness.truthy(SendMailSubjectEditBox:GetText():find("ProfessionShare", 1, true))
            harness.equal(state.sent, 0)
        end)
        state.restore()
        assert(ok, failure)
    end,

    ["mail probe: attach splits for an exact amount, takes whole stacks otherwise, waits between items"] = function(harness)
        local state = world()
        local ok, failure = pcall(function()
            local addon = probe(harness)
            addon.SlashCommands.mailprobe("attach 2840 6 2589")
            harness.equal(state.attachments[1].itemID, 2840); harness.equal(state.attachments[1].count, 6)
            harness.equal(state.attachments[2].itemID, 2589); harness.equal(state.attachments[2].count, 5)
            harness.equal(#state.splits, 1); harness.equal(state.splits[1], 6)
            harness.equal(state.pickups, 1)
            harness.equal(state.cursor, nil)
            harness.equal(state.sent, 0)
            local lines = addon.db.devChecks.mail.lines
            local waits = 0
            for _, line in ipairs(lines) do if line:find("MAIL_SEND_INFO_UPDATE seen", 1, true) then waits = waits + 1 end end
            harness.equal(waits, 2)
            addon.SlashCommands.mailprobe("report")
            harness.truthy(addon.exported:find("attachments now", 1, true))
        end)
        state.restore()
        assert(ok, failure)
    end,

    ["mail probe: an item the mail refuses is put back from the cursor; a silent server times out"] = function(harness)
        local state = world({ clickKeepsCursor = true, silentServer = true })
        local ok, failure = pcall(function()
            local addon = probe(harness)
            addon.SlashCommands.mailprobe("burst 2840 2 2589 1")
            harness.equal(state.cursor, nil, "never leaves an item on the cursor")
            harness.truthy(state.clears >= 2)
            harness.equal(next(state.attachments), nil)
            local timedOut = false
            for _, line in ipairs(addon.db.devChecks.mail.lines) do
                if line:find("NOT seen", 1, true) then timedOut = true end
            end
            harness.truthy(timedOut)
            harness.equal(state.sent, 0)
        end)
        state.restore()
        assert(ok, failure)
    end,

    ["mail probe: nothing happens with the mailbox closed"] = function(harness)
        local state = world({ mailboxClosed = true })
        local ok, failure = pcall(function()
            local addon = probe(harness)
            addon.SlashCommands.mailprobe("attach 2840 6")
            harness.equal(state.pickups, 0); harness.equal(#state.splits, 0)
            harness.truthy(addon.db.devChecks.mail.lines[2]:find("not open", 1, true))
        end)
        state.restore()
        assert(ok, failure)
    end,

    ["mail probe: report shows every saved run, bags lists ids, clear forgets them"] = function(harness)
        local state = world()
        local ok, failure = pcall(function()
            local addon = probe(harness)
            addon.SlashCommands.mailprobe("api")
            addon.SlashCommands.mailprobe("bags")
            addon.SlashCommands.mailprobe("attach 2589 2")
            addon.SlashCommands.mailprobe("report")
            harness.truthy(addon.exported:find("--- api", 1, true))
            harness.truthy(addon.exported:find("bag 0 slot 1: item 2840 x20", 1, true))
            harness.truthy(addon.exported:find("--- attach", 1, true))
            harness.truthy(addon.exported:find("stacks in the bags: bag 0 slot 2: 5", 1, true))
            local attachmentsLine = addon.exported:match("attachments now: [^\n]*")
            harness.equal(attachmentsLine, "attachments now: 1: Item 2589, 2589, nil, 2", "empty attachment slots are not listed")
            addon.SlashCommands.mailprobe("clear")
            addon.SlashCommands.mailprobe("report")
            harness.equal(addon.exported, "no mail probe run yet")
        end)
        state.restore()
        assert(ok, failure)
    end,

    ["mail probe: mailfill remembers the recipient; mailtest skips bound items and splits both ways"] = function(harness)
        local state = world({ slots = 5, bags = { { itemID = 6948, count = 1, bound = true }, { itemID = 2840, count = 20 },
            { itemID = 2589, count = 5 } } })
        local ok, failure = pcall(function()
            local addon = probe(harness)
            addon.SlashCommands.mailfill("")
            harness.equal(SendMailNameEditBox:GetText(), "", "no name known yet: nothing filled")
            addon.SlashCommands.mailfill("Some Alt")
            harness.equal(SendMailNameEditBox:GetText(), "Some Alt")
            SendMailNameEditBox:SetText("")
            addon.SlashCommands.mailfill("")
            harness.equal(SendMailNameEditBox:GetText(), "Some Alt", "the remembered name is used")
            addon.SlashCommands.mailtest()
            -- 2 via an empty bag slot: the new stack of 2 lands in slot 4 and is attached whole
            harness.equal(state.attachments[1].itemID, 2840); harness.equal(state.attachments[1].count, 2)
            harness.equal(state.bags[4].count, 2); harness.equal(state.bags[2].count, 18)
            -- 3 straight into the mail, then the other tradeable item; the bound Hearthstone is never touched
            harness.equal(state.attachments[2].itemID, 2840); harness.equal(state.attachments[2].count, 3)
            harness.equal(state.attachments[3].itemID, 2589); harness.equal(state.attachments[3].count, 5)
            harness.equal(state.attachments[4], nil)
            harness.truthy(addon.exported:find("new stack landed", 1, true))
            harness.truthy(addon.exported:find("2 s later:", 1, true))
            harness.truthy(addon.exported and addon.exported:find("--- attach", 1, true), "the report opens afterwards")
            harness.equal(state.sent, 0)
        end)
        state.restore()
        assert(ok, failure)
    end,

    ["mail probe: the API check runs without a mailbox"] = function(harness)
        local state = world({ mailboxClosed = true })
        local ok, failure = pcall(function()
            local addon = probe(harness)
            addon.SlashCommands.mailprobe("")
            local text = table.concat(addon.db.devChecks.mail.lines, "\n")
            harness.truthy(text:find("api ClickSendMailItemButton: function", 1, true))
            harness.truthy(text:find("mailbox open: false", 1, true))
        end)
        state.restore()
        assert(ok, failure)
    end,
}
