local ADDON, ns = ...

-- Inbound gate and incompatibility hints. Pure Lua (no WoW calls) so the rules are unit-tested offline.
-- Trust model: guild members are trusted, everyone else is not. Addon whispers work between ANY two players on a realm,
-- so the channel and the sender must be checked before anything is parsed, buffered or answered.
local Guard = {}
ns.Guard = Guard

-- true, or false + reason. `roster` = set of "Name-Realm" for the guild, as of the last roster update.
--   GUILD channel : the server only delivers it to guild members -> accepted.
--   WHISPER       : accepted only from a sender in the cached roster (an empty/unknown roster rejects: fail closed).
--   anything else : rejected (PARTY, RAID, SAY, CHANNEL, ...): this addon never sends there.
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
--   kind = "newer" | "older" | "newer-minor"
Guard.MAX_SEEN = 200

function Guard.NewHints()
    return { shown = {}, seen = {}, count = 0 }
end

-- Records the sender and returns true exactly once per kind (the caller prints the notice then).
function Guard.Note(hints, kind, sender)
    if not hints.seen[sender] and hints.count < Guard.MAX_SEEN then
        hints.seen[sender] = kind
        hints.count = hints.count + 1
    end
    if hints.shown[kind] then return false end
    hints.shown[kind] = true
    return true
end
