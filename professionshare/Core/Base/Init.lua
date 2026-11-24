local addonName, addon = ...

-- Identity. The ONLY place that knows whether this is the live addon ("ProfessionShare") or the side-by-side development
-- copy ("ProfessionShare-Dev"); everything else reads these fields so both can run in one client without sharing state.
-- The build flag and every name derived from it (PREFIX "PShare"/"PShareDev", /ps or /psd, SavedVariables, frames) come
-- from LibGuildSync-1.0 Addon.Setup (LibGuildSync/Addon.lua). Do not test the addon folder name or hard-code "PShare"
-- elsewhere.
-- The fallback version only matters for the offline tests, which have no client; tests/test_hardening.lua checks it
-- against the TOC.
LibStub("LibGuildSync-1.0").Addon.Setup(addon, addonName,
    { name = "ProfessionShare", prefix = "PShare", command = "ps", fallbackVersion = "1.4.0", color = "33ccff" })

-- Wire protocol (docs/protocol.md): MAJOR must match exactly between peers, MINOR may differ (additive changes only).
-- Bump MAJOR for any breaking change to the chunk header, serializer, compression or message meaning.
---@type integer
addon.PROTOCOL_MAJOR = 2
---@type integer
addon.PROTOCOL_MINOR = 8
---@type integer alias: the major is what the payload "v" field carries
addon.PROTOCOL = addon.PROTOCOL_MAJOR

addon.SlashCommands.version = function()
    addon.Print("v" .. addon.VERSION .. " (protocol " .. addon.PROTOCOL_MAJOR .. "." .. addon.PROTOCOL_MINOR .. ", schema "
        .. tostring(addon.Store.SCHEMA) .. ", prefix " .. addon.PREFIX .. ")")
end
