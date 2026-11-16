-- Feature 003: the automatic profession scan state machine (pure, driven by a fake client and a fake timer)
local function newScan(h, opts)
    opts = opts or {}
    local ns = h.ns()
    assert(loadfile("Core/AutoScan.lua"))("TalentShare", ns)
    local fake = {
        opened = {}, closed = 0, scans = 0, timers = {}, doneCalls = {}, combat = opts.combat or false,
        window = opts.window or false, supported = opts.supported ~= false,
        -- recipes appear in `counts[id]` once loadAfter[id] scans of that profession happened (simulates async loading)
        counts = {}, loadAfter = opts.loadAfter or {}, current = nil, seen = {}, failOpen = opts.failOpen or {},
    }
    local profs = opts.professions or { { id = 185, name = "Kochkunst" }, { id = 165, name = "Lederverarbeitung" }, { id = 393, name = "Kürschnerei" } }
    local env = {
        supported = function() return fake.supported end,
        inCombat = function() return fake.combat end,
        windowOpen = function() return fake.window end,
        professions = function() return profs end,
        recipeCount = function(p) return fake.counts[p.id] or opts.cached and opts.cached[p.id] or 0 end,
        open = function(id)
            if fake.failOpen[id] then return false end
            fake.opened[#fake.opened + 1] = id; fake.current = id
            return true
        end,
        close = function() fake.closed = fake.closed + 1 end,
        scan = function()
            fake.scans = fake.scans + 1
            local id = fake.current
            if id then
                fake.seen[id] = (fake.seen[id] or 0) + 1
                local need = fake.loadAfter[id]
                if need ~= math.huge and fake.seen[id] >= (need or 1) then fake.counts[id] = (opts.recipes and opts.recipes[id]) or 5 end
            end
        end,
        after = function(sec, fn) fake.timers[#fake.timers + 1] = fn end,
        done = function(results, aborted) fake.doneCalls[#fake.doneCalls + 1] = { results = results, aborted = aborted } end,
    }
    fake.scan = ns.AutoScan.New(env)
    -- run all pending timers (including the ones they schedule) up to `limit` rounds
    function fake.drain(limit)
        local rounds = 0
        while #fake.timers > 0 and rounds < (limit or 100) do
            local t = table.remove(fake.timers, 1)
            t(); rounds = rounds + 1
        end
        return rounds
    end
    return fake
end

return {
    ["autoscan: opens every profession in turn, scans it, closes the window once at the end (R1)"] = function(h)
        local f = newScan(h)
        h.eq(f.scan:Start(false), true)
        f.drain()
        h.eq(table.concat(f.opened, ","), "185,165,393")
        h.eq(f.closed, 1)
        h.eq(#f.doneCalls, 1)
        local r = f.doneCalls[1].results
        h.eq(#r, 3); h.eq(r[1].name, "Kochkunst"); h.eq(r[1].count, 5); h.eq(r[3].count, 5)
        h.eq(f.scan.running, false)
    end,

    ["autoscan: waits for lists that load late, with bounded retries (RF3)"] = function(h)
        local f = newScan(h, { loadAfter = { [185] = 3 } })      -- Kochkunst needs 3 scans before recipes show up
        f.scan:Start(false); f.drain()
        h.eq(f.doneCalls[1].results[1].count, 5, "must have waited for the late list")

        local never = newScan(h, { loadAfter = { [165] = math.huge } })
        never.scan:Start(false)
        local rounds = never.drain(200)
        h.truthy(rounds < 200, "run did not terminate")
        h.eq(never.doneCalls[1].results[2].count, 0)             -- reported as 0, run continued
        h.eq(never.doneCalls[1].results[3].count, 5, "a stuck profession must not block the next one")
        h.truthy((never.seen[165] or 0) <= 5, "too many retries: " .. tostring(never.seen[165]))
    end,

    ["autoscan: refuses to start in combat, with a window open, unsupported, nothing to do, or while running"] = function(h)
        local c = newScan(h, { combat = true })
        local ok, why = c.scan:Start(false); h.eq(ok, false); h.eq(why, "combat"); h.eq(#c.opened, 0)

        local w = newScan(h, { window = true })
        ok, why = w.scan:Start(false); h.eq(why, "busy"); h.eq(#w.opened, 0, "must not hijack the player's window (RF2)")

        local u = newScan(h, { supported = false })
        ok, why = u.scan:Start(false); h.eq(why, "unsupported")                                 -- RF5

        local n = newScan(h, { professions = {} })
        ok, why = n.scan:Start(false); h.eq(why, "nothing")
        local noid = newScan(h, { professions = { { name = "Kochkunst" } } })                   -- profession without skill line id
        ok, why = noid.scan:Start(false); h.eq(why, "nothing")

        local r = newScan(h)
        r.scan:Start(false)
        ok, why = r.scan:Start(false); h.eq(ok, false); h.eq(why, "running")
    end,

    ["autoscan: onlyMissing skips professions that already have recipes"] = function(h)
        local f = newScan(h, { cached = { [185] = 10, [393] = 1 } })
        h.eq(f.scan:Start(true), true)
        f.drain()
        h.eq(table.concat(f.opened, ","), "165")
        local all = newScan(h, { cached = { [185] = 10, [393] = 1, [165] = 12 } })
        local ok, why = all.scan:Start(true); h.eq(ok, false); h.eq(why, "nothing")
    end,

    ["autoscan: combat during the run stops it, closes the window and opens nothing more (RF1)"] = function(h)
        local f = newScan(h)
        f.scan:Start(false)
        h.eq(table.concat(f.opened, ","), "185")                 -- first profession is open, its timer is pending
        f.combat = true                                          -- combat starts before the timer fires
        f.drain()
        h.eq(table.concat(f.opened, ","), "185", "opened a profession during combat")
        h.eq(f.closed, 1)
        h.eq(f.doneCalls[1].aborted, "combat")
        h.eq(f.scan.running, false)
        f.combat = false
        h.eq(f.scan:Start(false), true, "must be restartable after an abort")
    end,

    ["autoscan: a profession that cannot be opened is skipped, the rest still runs"] = function(h)
        local f = newScan(h, { failOpen = { [185] = true } })
        f.scan:Start(false); f.drain()
        h.eq(table.concat(f.opened, ","), "165,393")
        local r = f.doneCalls[1].results
        h.eq(r[1].count, 0); h.eq(r[2].count, 5); h.eq(#r, 3)
    end,

    ["autoscan: Cancel invalidates pending timers and a new run is not disturbed by them (RF4)"] = function(h)
        local f = newScan(h)
        f.scan:Start(false)
        local stale = f.timers[1]
        f.timers = {}
        f.scan:Cancel()
        h.eq(f.closed, 1); h.eq(f.scan.running, false)
        f.scan:Start(false)                                      -- a new run
        local scansBefore = f.scans
        stale()                                                  -- the old run's timer fires late
        h.eq(f.scans, scansBefore, "stale timer acted on the new run")
        f.drain()
        h.eq(table.concat(f.opened, ","), "185,185,165,393")
        h.eq(#f.doneCalls, 1)
    end,

    ["autoscan: Cancel while idle is harmless"] = function(h)
        local f = newScan(h)
        f.scan:Cancel()
        h.eq(f.closed, 0)
    end,
}
