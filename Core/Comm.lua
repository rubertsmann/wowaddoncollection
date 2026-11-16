local ADDON, ns = ...

-- Transport: chunks encoded messages to <= 255 bytes, paces sends (token bucket), reassembles received chunks,
-- and wires Sync to the guild. Not in a guild -> inactive (no sends, no errors).
local Comm = {}
ns.Comm = Comm

local CHUNK = 225         -- payload bytes per addon message (header adds ~12)
local MAX_PARTS = 200
local BUCKET_MAX, REFILL = 5, 0.9   -- messages burst / refill per second (server allows 10 burst, 1/s)

Comm.active = false
Comm.queue = {}
Comm.buffers = {}
Comm.tokens = BUCKET_MAX
Comm.lastHello = 0
Comm.msgCounter = 0
Comm.chunksSent, Comm.chunksReceived = 0, 0

local function me() return ns.Store.db and ns.Store.db.me or (ns.Api.GetPlayerInfo().name) end

function Comm.Send(msg, dist, target)
    if not Comm.active then return end
    local ok, enc = pcall(ns.Codec.Encode, msg)
    if not ok then ns.Debug.Log("comm.encode", enc) return end
    Comm.msgCounter = Comm.msgCounter + 1
    local id = string.format("%x", Comm.msgCounter % 65536)
    local total = math.ceil(#enc / CHUNK)
    if total > MAX_PARTS then ns.Debug.Log("comm.toobig", msg.t, #enc) return end
    if #Comm.queue + total > 600 then ns.Debug.Log("comm.queuefull", msg.t) return end  -- never let a storm grow unbounded
    for i = 1, total do
        local part = enc:sub((i - 1) * CHUNK + 1, i * CHUNK)
        local item = { dist = dist, target = target, text = id .. "|" .. i .. "|" .. total .. "|" .. part }
        if msg.t == "ORDER" or msg.t == "WANT" or msg.t == "HELLO" then
            table.insert(Comm.queue, 1, item)  -- small control messages jump the queue (single chunk)
        else
            Comm.queue[#Comm.queue + 1] = item
        end
    end
end

local function pump(dt)
    Comm.tokens = math.min(BUCKET_MAX, Comm.tokens + dt * REFILL)
    while Comm.tokens >= 1 and #Comm.queue > 0 do
        local item = table.remove(Comm.queue, 1)
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, item.text, item.dist, item.target)
        if ok and type(res) == "number" and res == 3 then   -- AddonMessageThrottle: retry later
            table.insert(Comm.queue, 1, item)
            Comm.tokens = 0
            break
        end
        if not ok then ns.Debug.Log("comm.send", res) end
        Comm.chunksSent = Comm.chunksSent + 1
        Comm.tokens = Comm.tokens - 1
    end
end

local function onChunk(text, sender)
    local id, idx, total, part = text:match("^([%x]+)|(%d+)|(%d+)|(.*)$")
    idx, total = tonumber(idx), tonumber(total)
    if not id or not idx or not total or total < 1 or total > MAX_PARTS or idx < 1 or idx > total then return end
    Comm.chunksReceived = Comm.chunksReceived + 1
    local key = sender .. ":" .. id
    local buf = Comm.buffers[key]
    if not buf or buf.total ~= total then
        buf = { total = total, parts = {}, got = 0, t = ns.Util.Now() }
        Comm.buffers[key] = buf
    end
    if not buf.parts[idx] then
        buf.parts[idx] = part
        buf.got = buf.got + 1
    end
    if buf.got == total then
        Comm.buffers[key] = nil
        local msg, err = ns.Codec.Decode(table.concat(buf.parts))
        if msg then
            Comm.sync:OnMessage(msg, sender)
        else
            Comm.sync.stats.dropped = Comm.sync.stats.dropped + 1
            ns.Debug.Log("comm.decode", sender, err)
        end
    end
end

function Comm.OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= ns.PREFIX or not Comm.active or type(text) ~= "string" or type(sender) ~= "string" then return end
    sender = ns.Util.FullName(sender)
    if sender == me() then return end
    local ok, err = pcall(onChunk, text, sender)
    if not ok then ns.Debug.Log("comm.chunk", err) end
end

function Comm.RequestHello(login, force)
    if not Comm.active then return end
    local now = ns.Util.Now()
    if not force and not login and now - Comm.lastHello < 30 then return end
    Comm.lastHello = now
    Comm.sync:Hello(login)
end

function Comm.BroadcastOrder(order)
    if Comm.active then Comm.sync:BroadcastOrder(order) end
end

function Comm.PruneRoster()
    local roster = ns.Api.GetGuildRoster()
    if ns.Util.Count(roster) == 0 then return end
    local n = ns.Store.Prune(roster, ns.Store.db.me)
    if n > 0 then ns.Debug.Log("prune", n) end
end

-- Idempotent; called at login and whenever guild membership may have changed.
function Comm.Start()
    if Comm.active or not ns.Api.IsGuilded() then return end
    Comm.sync = ns.Sync.New({
        send = Comm.Send,
        now = ns.Util.Now,
        rand = math.random,
        store = ns.Store,
        orders = ns.orders,
        me = me(),
        onChange = function(kind) ns.Events.Fire("DATA_CHANGED", kind) end,
    })
    Comm.active = true
    ns.Debug.Log("comm.start", me())
    ns.Api.RequestRoster()
end

function Comm.Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    end
    local f = CreateFrame("Frame")
    local acc, secAcc = 0, 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        secAcc = secAcc + acc
        local step = acc
        acc = 0
        if Comm.active then
            pump(step)
            if secAcc >= 1 then
                Comm.sync:Tick(ns.Util.Now())
            end
        end
        if secAcc >= 1 then secAcc = 0 end
    end)
    local t = 0
    C_Timer.NewTicker(60, function()
        t = t + 1
        if not Comm.active then Comm.Start() end
        if Comm.active then
            local now = ns.Util.Now()
            for k, b in pairs(Comm.buffers) do
                if now - b.t > 60 then Comm.buffers[k] = nil end
            end
            if t % 5 == 0 then ns.Api.RequestRoster() end
            ns.orders:Prune(now)
        end
    end)
end

ns.Slash.comm = function()
    local s = Comm.sync and Comm.sync.stats or { sent = 0, received = 0, dropped = 0 }
    ns.Print(("comm: active=%s sent=%d received=%d dropped=%d queue=%d chunks out/in=%d/%d"):format(
        tostring(Comm.active), s.sent, s.received, s.dropped, #Comm.queue, Comm.chunksSent, Comm.chunksReceived))
end

ns.Slash.hello = function()
    if not Comm.active then ns.Print("not active (not in a guild?)") return end
    Comm.RequestHello(false, true)
    ns.Print("hello sent")
end

ns.Slash.debug = function()
    local log = ns.db and ns.db.debug or {}
    for i = math.max(1, #log - 15), #log do print(log[i]) end
end

ns.Slash.chars = function()
    for _, rec in ipairs(ns.Store.ListChars()) do
        local n = 0
        for _, p in pairs(rec.professions) do n = n + ns.Util.Count(p.recipes) end
        print(("%s lvl %s rev %s recipes %d"):format(rec.name, tostring(rec.level), tostring(rec.rev), n))
    end
end
