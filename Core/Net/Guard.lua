local addonName, addon = ...

-- Inbound gate and incompatibility hints. Pure Lua (no WoW calls) so the rules are unit-tested offline.
-- Trust model: guild members are trusted, everyone else is not. Addon whispers work between ANY two players on a realm,
-- so the channel and the sender must be checked before anything is parsed, buffered or answered.
---@class GuardModule
local Guard = {}
addon.Guard = Guard

---@alias RejectReason "sender"|"not in guild"|"channel"

-- true, or false and the reason. `roster` = set of "Name-Realm" for the guild, as of the last roster update.
--   GUILD channel : the server only delivers it to guild members -> accepted.
--   WHISPER       : accepted only from a sender in the cached roster (an empty/unknown roster rejects: fail closed).
--   anything else : rejected (PARTY, RAID, SAY, CHANNEL, ...): this addon never sends there.
---@param channel string
---@param sender any
---@param roster table<string, boolean>|nil
---@return boolean accepted
---@return RejectReason|nil reason
function Guard.Accept(channel, sender, roster)
    if type(sender) ~= "string" or sender == "" then return false, "sender" end
    if channel == "GUILD" then return true end
    if channel == "WHISPER" then
        if type(roster) == "table" and roster[sender] then return true end
        return false, "not in guild"
    end
    return false, "channel"
end

-- Incompatible-version hints: at most ONE notice per kind per session, and a bounded record of who was seen.
---@alias HintKind "newer"|"older"|"newer-minor"

---@class IncompatibilityHints
---@field shown table<HintKind, boolean> kinds already announced this session
---@field seen table<string, HintKind> sender -> kind (bounded by MAXIMUM_SEEN)
---@field count integer number of senders in `seen`

Guard.MAXIMUM_SEEN = 200

---@return IncompatibilityHints
function Guard.NewHints()
    return { shown = {}, seen = {}, count = 0 }
end

-- Records the sender and returns true exactly once per kind (the caller prints the notice then).
---@param hints IncompatibilityHints
---@param kind HintKind
---@param sender string
---@return boolean announce
function Guard.Note(hints, kind, sender)
    if not hints.seen[sender] and hints.count < Guard.MAXIMUM_SEEN then
        hints.seen[sender] = kind
        hints.count = hints.count + 1
    end
    if hints.shown[kind] then return false end
    hints.shown[kind] = true
    return true
end
