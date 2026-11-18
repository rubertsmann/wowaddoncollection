-- LibGuildSync: internal pub/sub, one instance per addon (Events.New). Every handler runs protected: an error in one
-- handler is logged (Log.Exception, with stack) and the others still run.
local lib = LibStub("LibGuildSync-1.0")
local Events = lib:Module("Events", 1)
if not Events then return end

-- An event bus for one addon; functions are called with a dot (events.On(name, handler), events.Fire(name, ...)).
---@param log table the addon's Log instance
---@return table events
function Events.New(log)
    ---@type table<string, function[]>
    local handlersByEvent = {}
    local instance = { handlers = handlersByEvent }
    ---@param eventName string
    ---@param handler function
    function instance.On(eventName, handler)
        handlersByEvent[eventName] = handlersByEvent[eventName] or {}
        table.insert(handlersByEvent[eventName], handler)
    end
    ---@param eventName string
    ---@param ... any
    function instance.Fire(eventName, ...)
        for _, handler in ipairs(handlersByEvent[eventName] or {}) do
            log.Protected("events.fire", "an internal event handler failed (" .. tostring(eventName) .. ")", handler, ...)
        end
    end
    return instance
end
