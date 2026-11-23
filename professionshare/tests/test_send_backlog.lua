-- The send queue must not build up outdated record answers or whisper members who went offline (a live session queued
-- 434 chunks, the oldest 12 minutes old; the game answered "no player named ... is online" for a member who had left).
local function withChat(body)
    local saved = C_ChatInfo
    local calls = {}
    C_ChatInfo = { SendAddonMessage = function(prefix, text, channel, target)
        calls[#calls + 1] = { prefix = prefix, text = text, channel = channel, target = target }
        return 0
    end, RegisterAddonMessagePrefix = function() return true end }
    local ok, errorMessage = pcall(body, calls)
    C_ChatInfo = saved
    if not ok then error(errorMessage, 0) end
end

return {
    ["send queue: record answers are replaceable, orders and requests are not; requests jump the queue"] = function(harness)
        local addon = harness.addon()
        local options = addon.Communication.options
        for _, messageType in ipairs({ "SNAP", "OFFERS", "ACCESS" }) do harness.truthy(options.replaceableTypes[messageType], messageType) end
        for _, messageType in ipairs({ "OPUSH", "ORDER", "HELLO", "WANT", "WANTO", "WANTA" }) do
            harness.equal(options.replaceableTypes[messageType], nil, messageType)
        end
        for _, messageType in ipairs({ "WANT", "WANTO", "WANTA", "HELLO" }) do harness.truthy(options.priorityTypes[messageType], messageType) end
    end,

    ["send queue: three record changes to one member leave one answer waiting; an offline member gets nothing"] = function(harness)
        local addon = harness.addon({ now = 1700000000 })
        withChat(function(calls)
            local Communication = addon.Communication
            Communication.active = true
            local online = { ["Peer One"] = true, ["Gone Member"] = false }
            Communication.options.guild = { IsGuilded = function() return true end, GetGuildRoster = function() return {} end,
                RequestRoster = function() end, IsOnline = function(name) return online[name] end }
            local function record(rev)
                local recipes = {}
                for recipeID = 1, 200 do recipes[recipeID] = true end
                return harness.character("Me", rev, recipes)
            end
            for rev = 1, 3 do Communication.Send({ t = "SNAP", char = record(rev), catalog = {} }, "WHISPER", "Peer One") end
            local waitingMessages = {}
            for _, chunk in ipairs(Communication.queue) do waitingMessages[chunk.traceEntry] = true end
            local count = 0
            for _ in pairs(waitingMessages) do count = count + 1 end
            harness.equal(count, 1, "only the newest SNAP waits")
            Communication.Send({ t = "SNAP", char = record(4), catalog = {} }, "WHISPER", "Gone Member")
            LibStub("LibGuildSync-1.0").Channel.shared.tokens = 600
            while #Communication.queue > 0 do Communication._pump(0) end
            for _, call in ipairs(calls) do harness.truthy(call.target ~= "Gone Member", "nothing whispered to an offline member") end
            harness.truthy(#calls > 0)
        end)
    end,
}
