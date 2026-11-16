local ADDON, ns = ...

-- Protocol state machine. Pure: all I/O goes through `env`, so it is testable offline.
--   env = { send(msg, dist, target), now() -> number, rand() -> [0,1), store, orders, me -> "Name-Realm", onChange(kind) }
-- Messages (every message carries v = ns.PROTOCOL and a string type t):
--   HELLO {rev, login?, odig}   broadcast (GUILD) or reply (WHISPER): my record version + digest of my orders
--   WANT  {names}               whisper: "send me your record"; only the sender's own name is honoured
--   SNAP  {char, catalog}       whisper: a character record + catalog entries of its recipes
--   OPUSH {orders}              whisper: orders the receiver lacks (<= 10 per message)
--   ORDER {order}               broadcast: one order changed
-- A peer can only author its OWN character record (SNAP char.name must equal the sender).
local Sync = {}
ns.Sync = Sync
Sync.__index = Sync

function Sync.New(env)
    return setmetatable({ env = env, pending = {}, wanted = {}, budget = 0, budgetT = 0,
        stats = { sent = 0, received = 0, dropped = 0 } }, Sync)
end

function Sync:_send(msg, dist, target)
    self.stats.sent = self.stats.sent + 1
    self.env.send(msg, dist, target)
end

function Sync:_later(delay, msg, dist, target)
    table.insert(self.pending, { at = self.env.now() + delay, msg = msg, dist = dist, target = target })
end

function Sync:_myRev()
    local rec = self.env.store.GetChar(self.env.me)
    return rec and rec.rev or 0
end

function Sync:_helloMsg(login)
    return { t = "HELLO", rev = self:_myRev(), login = login or nil, odig = self.env.orders:Digest(100) }
end

function Sync:Hello(login)
    self:_send(self:_helloMsg(login), "GUILD")
end

function Sync:BroadcastOrder(order)
    self:_send({ t = "ORDER", order = order }, "GUILD")
end

function Sync:OnMessage(msg, sender)
    local env = self.env
    self.stats.received = self.stats.received + 1
    if type(msg) ~= "table" or type(msg.t) ~= "string" or msg.v ~= ns.PROTOCOL
        or type(sender) ~= "string" or sender == env.me then
        self.stats.dropped = self.stats.dropped + 1
        return
    end
    local h = self["_on" .. msg.t]
    if not h then
        self.stats.dropped = self.stats.dropped + 1
        return
    end
    local ok, err = pcall(h, self, msg, sender)
    if not ok then
        self.stats.dropped = self.stats.dropped + 1
        if ns.Debug then ns.Debug.Log("sync.error", msg.t, err) end
    end
end

function Sync:_onHELLO(msg, sender)
    local env = self.env
    local now = env.now()
    -- a rev is a server timestamp: finite, not negative, not from the future (+inf would make every client pull forever)
    if not ns.Util.SafeInt(msg.rev, 0, ns.Store.Horizon()) then error("bad rev") end
    local cur = env.store.GetChar(sender)
    if (cur and cur.rev or 0) < msg.rev then
        -- pull once per (sender, rev) per minute; duplicate HELLOs must not trigger duplicate snapshots
        local w = self.wanted[sender]
        if not (w and w.rev >= msg.rev and now - w.t < 60) then
            self.wanted[sender] = { rev = msg.rev, t = now }
            self:_send({ t = "WANT", names = { sender } }, "WHISPER", sender)
        end
    end
    if msg.login then -- a member just logged in: introduce myself after a random delay (storm control)
        if now - self.budgetT >= 60 then self.budgetT, self.budget = now, 0 end
        if self.budget < 20 then   -- at most 20 login introductions per minute
            self.budget = self.budget + 1
            self:_later(env.rand() * 10, self:_helloMsg(false), "WHISPER", sender)
        end
    end
    if type(msg.odig) == "table" then
        local missing = env.orders:Missing(msg.odig, 40)
        local i = 1
        while i <= #missing do
            local batch = {}
            for j = i, math.min(i + 9, #missing) do batch[#batch + 1] = missing[j] end
            self:_later(1 + env.rand() * 5, { t = "OPUSH", orders = batch }, "WHISPER", sender)
            i = i + 10
        end
    end
end

function Sync:_onWANT(msg, sender)
    local env = self.env
    if type(msg.names) ~= "table" then error("bad names") end
    for _, name in ipairs(msg.names) do
        if name == env.me then
            local rec = env.store.GetChar(env.me)
            if rec then
                local catalog = {}
                for _, p in pairs(rec.professions or {}) do
                    for id in pairs(p.recipes or {}) do
                        local e = env.store.GetRecipe(id)
                        if e then catalog[id] = e end
                    end
                end
                self:_later(env.rand() * 2, { t = "SNAP", char = rec, catalog = catalog }, "WHISPER", sender)
            end
        end
    end
end

function Sync:_onSNAP(msg, sender)
    local env = self.env
    -- allow-list copy: only validated fields of the record are ever stored
    local rec = env.store.SanitizeChar(msg.char)
    if not rec then error("invalid char") end
    if rec.name ~= sender then error("char/sender mismatch") end
    -- catalog entries are accepted only for recipes the sender itself knows (it cannot seed names for other recipes)
    local known = {}
    for _, p in pairs(rec.professions) do
        for id in pairs(p.recipes) do known[id] = true end
    end
    local good, n = {}, 0
    if type(msg.catalog) == "table" then
        for id, e in pairs(msg.catalog) do
            n = n + 1
            if n > 2000 then break end
            if known[id] then good[id] = e end   -- PutCatalog rebuilds each entry by allow-list copy
        end
    end
    env.store.PutCatalog(good)
    if env.store.PutChar(rec) then env.onChange("chars") end
end

function Sync:_onOPUSH(msg)
    local env = self.env
    if type(msg.orders) ~= "table" then error("bad orders") end
    local changed = false
    for i, o in ipairs(msg.orders) do
        if i > 10 then break end
        if env.orders:Merge(o) then changed = true end
    end
    if changed then env.onChange("orders") end
end

function Sync:_onORDER(msg)
    if self.env.orders:Merge(msg.order) then self.env.onChange("orders") end
end

-- Send everything that is due. Call about once per second.
function Sync:Tick(now)
    local keep = {}
    for _, p in ipairs(self.pending) do
        if p.at <= now then self:_send(p.msg, p.dist, p.target)
        else keep[#keep + 1] = p end
    end
    self.pending = keep
end
