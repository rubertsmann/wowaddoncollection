local ADDON, ns = ...

-- Protocol state machine. Pure: all I/O goes through `env`, so it is testable offline.
--   env = { send(msg, dist, target), now() -> number, rand() -> [0,1), store, orders, onChange(kind),
--           me = "Name-Realm" | function() -> "Name-Realm" }
-- `me` may be a function so the identity is read at use time: Comm can start before PLAYER_LOGIN has set the current
-- character (SavedVariables are account-wide, so the stored name may still be the previously played character).
-- OnMessage returns (status, reason): "ok" | "ignored" | "dropped" | "error", for the network trace (Core/Trace.lua).
-- Messages (every message carries v = ns.PROTOCOL and a string type t):
--   HELLO {rev, login?, odig, orev?}  broadcast (GUILD) or reply (WHISPER): my record versions + digest of my orders
--   WANT  {names, via?}         "send me your record"; only the sender's own name is honoured
--   SNAP  {char, catalog}       a character record + catalog entries of its recipes
--   OPUSH {orders}              whisper: orders the receiver lacks (<= 10 per message)
--   ORDER {order}               broadcast: one order changed (order may carry a recipe name snapshot, 2.2+)
--   WANTO {names, via?}         "send me your offers record" (2.1+)
--   OFFERS {offers}             a character's offers/dibs record (2.1+)
-- Pulls (2.2): the first WANT/WANTO is a whisper. If the record has not arrived after RETRY[1] seconds the request is
-- repeated on GUILD with via = "GUILD", and the owner answers on GUILD, so a failing whisper path (wrong target form,
-- server restrictions) cannot block sync; one GUILD answer also serves every other member that was behind. A 2.1 peer
-- ignores `via` and answers by whisper as before.
-- A peer can only author its OWN record (SNAP char.name / OFFERS name must equal the sender). Every player name from the
-- wire is compared and stored in canonical form (Util.Canon), so differently spelled realms meet on one key.
local Sync = {}
ns.Sync = Sync
Sync.__index = Sync

Sync.RETRY = { 45, 90, 180 }   -- seconds to wait after attempt n before the next one; after the last: give up
-- A HELLO is fresh proof that the peer is online: it restarts a pull that gave up once this long has passed (the 0.4.0
-- rule, one pull per peer and minute). A longer lock (first 0.4.1 draft: 10 min) left members without a record for up
-- to 10 min after a few lost messages; tests/test_soak.lua caught it (about 1 failed run in 100).
Sync.GIVE_UP_RESET = 60
Sync.GUILD_DEDUP = 60          -- an answer on GUILD for the same rev is sent at most once per this many seconds

local function canon(name) return ns.Util.Canon(name) or name end

function Sync.New(env)
    return setmetatable({ env = env, pending = {}, wanted = {}, wantedO = {}, guildSent = {}, peerRealm = {}, budget = 0, budgetT = 0,
        stats = { sent = 0, received = 0, dropped = 0 } }, Sync)
end

function Sync:_me()
    local me = self.env.me
    if type(me) == "function" then return me() end
    return me
end

-- the outcome of the message being handled (read by OnMessage and returned to the transport for the trace)
function Sync:_note(st, why)
    self.result = { st = st, why = why }
end

function Sync:_send(msg, dist, target)
    self.stats.sent = self.stats.sent + 1
    self.env.send(msg, dist, target)
end

function Sync:_later(delay, msg, dist, target)
    table.insert(self.pending, { at = self.env.now() + delay, msg = msg, dist = dist, target = target })
end

function Sync:_myRev()
    local rec = self.env.store.GetChar(self:_me())
    return rec and rec.rev or 0
end

function Sync:_helloMsg(login)
    local o = ns.Offers.Get(self:_me())
    return { t = "HELLO", rev = self:_myRev(), login = login or nil, odig = self.env.orders:Digest(100),
        orev = (o and o.rev > 0) and o.rev or nil }
end

function Sync:Hello(login)
    self:_send(self:_helloMsg(login), "GUILD")
end

function Sync:BroadcastOrder(order)
    self:_send({ t = "ORDER", order = order }, "GUILD")
end

function Sync:OnMessage(msg, sender)
    self.stats.received = self.stats.received + 1
    if type(msg) ~= "table" or type(msg.t) ~= "string" or msg.v ~= ns.PROTOCOL then
        self.stats.dropped = self.stats.dropped + 1
        return "dropped", "malformed or other protocol version"
    end
    if type(sender) ~= "string" or sender == self:_me() then
        self.stats.dropped = self.stats.dropped + 1
        return "dropped", "own echo"
    end
    local h = self["_on" .. msg.t]
    if not h then
        self.stats.dropped = self.stats.dropped + 1
        return "dropped", "unknown message type " .. msg.t
    end
    self.result = nil
    local ok, err = pcall(h, self, msg, sender)
    if not ok then
        self.stats.dropped = self.stats.dropped + 1
        if ns.Debug then ns.Debug.Log("sync.error", msg.t, err) end
        return "error", (tostring(err):gsub("^.-:%d+: ", ""))   -- strip "file:line: " so the reason reads like the error()
    end
    local r = self.result or { st = "ok" }
    return r.st, r.why
end

------------------------------------------------------------------ record pulls (character record and offers record)

local KINDS = {
    char = { want = "WANT", list = "wanted", label = "char",
        have = function(self, name) local r = self.env.store.GetChar(name) return r and r.rev or 0 end },
    offers = { want = "WANTO", list = "wantedO", label = "offers",
        have = function(_, name) local r = ns.Offers.Get(name) return r and r.rev or 0 end },
}
Sync.KINDS = KINDS

-- Names a request carries: the full name, plus the first-name form a 0.4.0 member uses for itself (Util.LegacyName).
-- `peerRealm` is the realm the member appends to names (learned from its own requests): a 0.4.0 member on another
-- realm of the guild only answers to "First-<its realm>", so that form is added too.
function Sync.AskNames(sender, peerRealm)
    local legacy = ns.Util.LegacyName(sender)
    local out = legacy and { sender, legacy } or { sender }
    if legacy and type(peerRealm) == "string" and peerRealm ~= "" then
        local first = legacy:match("^([^-]+)")
        local there = first .. "-" .. peerRealm
        if there ~= legacy then out[#out + 1] = there end
    end
    return out
end

-- A member builds every name in a request with ITS realm: remember it, so requests to that member use its spelling.
function Sync:_learnRealm(sender, names)
    if type(names) ~= "table" or type(names[1]) ~= "string" then return end
    local realm = names[1]:match("^[^-]+-(.+)$")
    if realm and ns.Util.IsSafeName(realm) and #realm <= 48 then self.peerRealm[sender] = realm end
end

-- A peer announced `rev` for its record of `kind`. Starts a pull when I am behind; returns a note for the trace.
function Sync:_pull(kind, sender, rev, now)
    local k = KINDS[kind]
    local have = k.have(self, sender)
    if have >= rev then return k.label .. ": up to date" end
    local list = self[k.list]
    local w = list[sender]
    if w and w.rev >= rev and not (w.done and now - w.t >= Sync.GIVE_UP_RESET) then
        if w.done then return ("%s: have %d < %d, gave up after %d tries"):format(k.label, have, rev, w.n) end
        return ("%s: have %d < %d, %s pending (try %d, %ds ago)"):format(k.label, have, rev, k.want, w.n, now - w.t)
    end
    list[sender] = { rev = rev, t = now, n = 1 }
    self:_send({ t = k.want, names = Sync.AskNames(sender, self.peerRealm[sender]) }, "WHISPER", sender)
    return ("%s: have %d < %d -> %s"):format(k.label, have, rev, k.want)
end

-- Retries pulls that got no answer: try 2 and 3 go out on GUILD (answered on GUILD). Satisfied pulls are forgotten.
function Sync:_retry(now)
    for kind, k in pairs(KINDS) do
        local list = self[k.list]
        for sender, w in pairs(list) do
            if k.have(self, sender) >= w.rev then
                list[sender] = nil
            elseif not w.done and now - w.t >= Sync.RETRY[w.n] then
                if w.n >= #Sync.RETRY then
                    w.done, w.t = true, now
                    if ns.Trace then
                        ns.Trace.Add({ dir = "sys", st = "warn", peer = sender, mt = k.want,
                            why = ("no %s record after %d tries; their next HELLO starts a new pull"):format(kind, w.n) })
                    end
                else
                    w.n, w.t = w.n + 1, now
                    self:_send({ t = k.want, names = Sync.AskNames(sender, self.peerRealm[sender]), via = "GUILD" }, "GUILD")
                end
            end
        end
    end
end

-- Answers a WANT/WANTO for my own record. `via = "GUILD"` answers on GUILD (deduplicated per rev), else by whisper.
function Sync:_answer(kind, msg, sender, payload, rev)
    if msg.via == "GUILD" then
        local g = self.guildSent[kind]
        local now = self.env.now()
        if g and g.rev == rev and now - g.t < Sync.GUILD_DEDUP then
            self:_note("ignored", ("asked on GUILD; rev %d already broadcast %ds ago"):format(rev, now - g.t))
            return
        end
        self.guildSent[kind] = { rev = rev, t = now }
        self:_later(self.env.rand() * 2, payload, "GUILD")
        self:_note("ok", "-> " .. payload.t .. " on GUILD scheduled")
    else
        self:_later(self.env.rand() * 2, payload, "WHISPER", sender)
        self:_note("ok", "-> " .. payload.t .. " scheduled")
    end
end

-- the name in `names` that means me (in any spelling of my realm), or nil
local function asksForMe(names, me)
    for _, name in ipairs(names) do
        if type(name) == "string" and canon(name) == me then return name end
    end
    return nil
end

-- A whispered answer carries my record under the name the member asked with: a 0.4.0 member on another realm of the
-- guild accepts a record only when its name equals "my name-<its realm>". Updated members fold the realm either way.
local function asAsked(rec, asked, msg)
    if msg.via == "GUILD" or type(asked) ~= "string" or asked == rec.name then return rec end
    local c = {}
    for k, v in pairs(rec) do c[k] = v end
    c.name = asked
    return c
end

local function askedNames(names)
    local out = {}
    for i, n in ipairs(names) do out[i] = tostring(n) end
    return table.concat(out, ",")
end

------------------------------------------------------------------ handlers

function Sync:_onHELLO(msg, sender)
    local env = self.env
    local now = env.now()
    -- a rev is a server timestamp: finite, not negative, not from the future (+inf would make every client pull forever)
    if not ns.Util.SafeInt(msg.rev, 0, ns.Store.Horizon()) then error("bad rev") end
    local notes = {}
    if msg.rev > 0 then
        notes[#notes + 1] = self:_pull("char", sender, msg.rev, now)
    else
        notes[#notes + 1] = "char: peer has no record yet"
    end
    -- offers record (protocol 2.1): same pull rule as the character record, validated like it
    if msg.orev ~= nil and ns.Util.SafeInt(msg.orev, 1, ns.Store.Horizon()) then
        notes[#notes + 1] = self:_pull("offers", sender, msg.orev, now)
    elseif msg.orev ~= nil then
        notes[#notes + 1] = "offers: invalid orev ignored"
    else
        notes[#notes + 1] = "offers: peer has none"
    end
    if msg.login then -- a member just logged in: introduce myself after a random delay (storm control)
        if now - self.budgetT >= 60 then self.budgetT, self.budget = now, 0 end
        if self.budget < 20 then   -- at most 20 login introductions per minute
            self.budget = self.budget + 1
            self:_later(env.rand() * 10, self:_helloMsg(false), "WHISPER", sender)
            notes[#notes + 1] = "login -> HELLO reply scheduled"
        else
            notes[#notes + 1] = "login reply skipped (budget)"
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
        if #missing > 0 then notes[#notes + 1] = ("orders: peer lacks %d -> OPUSH"):format(#missing) end
    end
    self:_note("ok", table.concat(notes, "; "))
end

function Sync:_onWANT(msg, sender)
    local env = self.env
    if type(msg.names) ~= "table" then error("bad names") end
    self:_learnRealm(sender, msg.names)
    local me = self:_me()
    local asked = asksForMe(msg.names, me)
    if not asked then
        -- on GUILD every member sees every request: only a whisper asking for "me" in a foreign form is a real mismatch
        if msg.via == "GUILD" then self:_note("ignored", "request for " .. askedNames(msg.names)) return end
        self:_note("ignored", ("asked for %s but I am %s (name mismatch)"):format(askedNames(msg.names), tostring(me)))
        return
    end
    local rec = env.store.GetChar(me)
    if not rec then self:_note("ignored", "asked for my record but I have none (no profession scanned)") return end
    local catalog = {}
    for _, p in pairs(rec.professions or {}) do
        for id in pairs(p.recipes or {}) do
            local e = env.store.GetRecipe(id)
            if e then catalog[id] = e end
        end
    end
    self:_answer("char", msg, sender, { t = "SNAP", char = asAsked(rec, asked, msg), catalog = catalog }, rec.rev or 0)
end

function Sync:_onWANTO(msg, sender)
    if type(msg.names) ~= "table" then error("bad names") end
    self:_learnRealm(sender, msg.names)
    local me = self:_me()
    local asked = asksForMe(msg.names, me)
    if not asked then
        if msg.via == "GUILD" then self:_note("ignored", "request for " .. askedNames(msg.names)) return end
        self:_note("ignored", ("asked for %s but I am %s (name mismatch)"):format(askedNames(msg.names), tostring(me)))
        return
    end
    local rec = ns.Offers.Get(me)
    if not rec then self:_note("ignored", "asked for my offers but I have none") return end
    self:_answer("offers", msg, sender, { t = "OFFERS", offers = asAsked(rec, asked, msg) }, rec.rev or 0)
end

function Sync:_onOFFERS(msg, sender)
    local rec = ns.Offers.Sanitize(msg.offers)
    if not rec then error("invalid offers") end
    if canon(rec.name) ~= sender then   -- a peer authors only its own record
        error(("offers/sender mismatch: record %s from %s"):format(rec.name, sender))
    end
    rec.name = sender
    local dibs = {}   -- dib keys name other players: stored under their canonical names too
    for key, d in pairs(rec.dibs) do
        local owner, id = ns.Offers.ParseKey(key)
        if owner then dibs[ns.Offers.Key(canon(owner), id)] = d end
    end
    rec.dibs = dibs
    if ns.Offers.Put(rec) then
        self.env.onChange("offers")
        self:_note("ok", "stored")
    else
        self:_note("ignored", "not newer than what I hold")
    end
end

function Sync:_onSNAP(msg, sender)
    local env = self.env
    -- allow-list copy: only validated fields of the record are ever stored
    local rec = env.store.SanitizeChar(msg.char)
    if not rec then error("invalid char") end
    if canon(rec.name) ~= sender then error(("char/sender mismatch: record %s from %s"):format(rec.name, sender)) end
    rec.name = sender
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
    if env.store.PutChar(rec) then
        env.onChange("chars")
        self:_note("ok", "stored")
    else
        self:_note("ignored", "not newer than what I hold")
    end
end

-- an order with every player name in canonical form (a shallow copy; Orders.Merge validates it)
local function canonOrder(o)
    if type(o) ~= "table" then return o end
    local c = {}
    for k, v in pairs(o) do c[k] = v end
    if type(o.requester) == "string" then c.requester = canon(o.requester) end
    if type(o.closedBy) == "string" then c.closedBy = canon(o.closedBy) end
    if type(o.claims) == "table" then
        local claims = {}
        for name, cl in pairs(o.claims) do claims[type(name) == "string" and canon(name) or name] = cl end
        c.claims = claims
    end
    return c
end
Sync.CanonOrder = canonOrder

function Sync:_onOPUSH(msg)
    local env = self.env
    if type(msg.orders) ~= "table" then error("bad orders") end
    local changed, n = false, 0
    for i, o in ipairs(msg.orders) do
        if i > 10 then break end
        if env.orders:Merge(canonOrder(o)) then changed = true; n = n + 1 end
    end
    if changed then env.onChange("orders") end
    self:_note(changed and "ok" or "ignored", ("%d of %d orders changed"):format(n, math.min(#msg.orders, 10)))
end

function Sync:_onORDER(msg)
    if self.env.orders:Merge(canonOrder(msg.order)) then
        self.env.onChange("orders")
        self:_note("ok", "merged")
    else
        self:_note("ignored", ns.Orders.Sanitize(msg.order) and "no change" or "invalid order")
    end
end

-- Send everything that is due and retry unanswered pulls. Call about once per second.
function Sync:Tick(now)
    local keep = {}
    for _, p in ipairs(self.pending) do
        if p.at <= now then self:_send(p.msg, p.dist, p.target)
        else keep[#keep + 1] = p end
    end
    self.pending = keep
    self:_retry(now)
end
