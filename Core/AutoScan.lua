local ADDON, ns = ...

-- Reads every profession of the player without the player clicking through the pages: opens one profession after the
-- other, lets the existing Scanner read it, and closes the window again. The game only exposes a profession's recipes
-- while its window is open. The state machine is pure (all WoW access comes in through `env`), so it is tested offline.
--   env = { supported() -> bool, inCombat() -> bool, windowOpen() -> bool,
--           professions() -> { {id, name}, ... }, recipeCount(p) -> number,
--           open(skillLineID) -> bool, close(), scan(), after(seconds, fn), done(results) }
--   results = { { name = ..., count = n }, ... }   (count 0 = the list never loaded)
local AutoScan = {}
ns.AutoScan = AutoScan
AutoScan.__index = AutoScan

local FIRST_WAIT, RETRY_WAIT, MAX_RETRIES = 1.2, 1.0, 3

function AutoScan.New(env)
    return setmetatable({ env = env, running = false, gen = 0 }, AutoScan)
end

-- Returns true when a run started, else false and a reason:
-- "running" | "unsupported" | "combat" | "busy" (player has a profession window open) | "nothing"
function AutoScan:Start(onlyMissing)
    local env = self.env
    if self.running then return false, "running" end
    if not env.supported() then return false, "unsupported" end
    if env.inCombat() then return false, "combat" end
    if env.windowOpen() then return false, "busy" end   -- never hijack a window the player is using
    local queue = {}
    for _, p in ipairs(env.professions()) do
        if p.id and (not onlyMissing or env.recipeCount(p) == 0) then queue[#queue + 1] = p end
    end
    if #queue == 0 then return false, "nothing" end
    self.running, self.queue, self.i, self.results = true, queue, 0, {}
    self.gen = self.gen + 1
    self:_next(self.gen)
    return true
end

function AutoScan:Cancel()
    if not self.running then return end
    self.gen = self.gen + 1     -- timers of the cancelled run become no-ops
    self.running = false
    self.env.close()
end

function AutoScan:_next(gen)
    local env = self.env
    while true do
        self.i = self.i + 1
        local p = self.queue[self.i]
        if not p then return self:_finish() end
        if env.inCombat() then
            self.aborted = "combat"
            return self:_finish()
        end
        if env.open(p.id) then
            self.tries = 0
            env.after(FIRST_WAIT, function() self:_check(gen) end)
            return
        end
        self.results[#self.results + 1] = { name = p.name, count = 0 }   -- could not be opened: skip, keep going
    end
end

function AutoScan:_check(gen)
    if gen ~= self.gen or not self.running then return end   -- stale timer from a cancelled / older run
    local env = self.env
    local p = self.queue[self.i]
    if env.inCombat() then
        self.aborted = "combat"
        return self:_finish()
    end
    env.scan()
    local n = env.recipeCount(p)
    if n == 0 and self.tries < MAX_RETRIES then
        self.tries = self.tries + 1     -- the recipe list loads asynchronously: bounded retries, never a stall
        return env.after(RETRY_WAIT, function() self:_check(gen) end)
    end
    self.results[#self.results + 1] = { name = p.name, count = n }
    self:_next(gen)
end

function AutoScan:_finish()
    self.running = false
    self.env.close()
    local aborted = self.aborted
    self.aborted = nil
    self.env.done(self.results, aborted)
end

------------------------------------------------------------------ wiring to the real client

function AutoScan.Instance()
    if AutoScan.inst then return AutoScan.inst end
    local Api = ns.Api
    local changed = false
    local function mine() return ns.Store.GetChar(ns.Store.db.me or "") end
    AutoScan.inst = AutoScan.New({
        supported = Api.CanOpenProfession,
        inCombat = Api.InCombat,
        windowOpen = Api.IsProfessionWindowShown,
        professions = function()
            local out, rec = {}, mine()
            for _, p in pairs(rec and rec.professions or {}) do
                if p.id then out[#out + 1] = { id = p.id, name = ns.Names.Profession(p.id, p) } end
            end
            table.sort(out, function(a, b) return ns.Util.SearchKey(a.name) < ns.Util.SearchKey(b.name) end)
            return out
        end,
        recipeCount = function(p)
            local rec = mine()
            for _, e in pairs(rec and rec.professions or {}) do
                if e.id == p.id then return ns.Util.Count(e.recipes or {}) end
            end
            return 0
        end,
        open = Api.OpenProfession,
        close = Api.CloseProfession,
        scan = function() if ns.Scanner.Refresh(ns.Util.Now()) then changed = true end end,
        after = function(sec, fn) C_Timer.After(sec, fn) end,
        done = function(results, aborted)
            local parts, total = {}, 0
            for _, r in ipairs(results) do
                parts[#parts + 1] = r.name .. " " .. r.count
                total = total + r.count
            end
            if aborted == "combat" then ns.Print(ns.L["Scan skipped: you are in combat."]) end
            if total == 0 then
                ns.Print(ns.L["Could not read any recipes: open each profession window once."])
            else
                ns.Print(ns.Locale.Fmt(ns.L["Scanned: {list}"], { list = table.concat(parts, ", ") }))
            end
            if changed then
                changed = false
                ns.Events.Fire("LOCAL_CHANGED")
                ns.Events.Fire("DATA_CHANGED", "chars")
            end
        end,
    })
    return AutoScan.inst
end

-- manual = the player asked (button / slash): every failure is explained. Automatic runs stay quiet when there is
-- nothing to do. Returns true when a run started.
function AutoScan.Run(manual)
    local ok, reason = AutoScan.Instance():Start(not manual)
    if ok then
        ns.Print(ns.L["Scanning your professions (a few seconds) ..."])
        return true
    end
    local L = ns.L
    local msg = {
        combat = L["Scan skipped: you are in combat."],
        busy = L["Close your profession window first, then scan again."],
        unsupported = L["This client cannot open professions automatically: open each profession window once."],
        nothing = L["Nothing to scan: no professions found."],
    }
    if manual or reason == "unsupported" then
        if msg[reason] then ns.Print(msg[reason]) end
    end
    return false
end

ns.Slash.autoscan = function(arg)
    arg = (arg or ""):match("^%s*(%S*)") or ""
    if arg == "off" or arg == "on" then
        if ns.db then ns.db.ui.autoScan = (arg == "on") end
        ns.Print(("autoscan %s"):format(arg))
    else
        AutoScan.Run(true)
    end
end
