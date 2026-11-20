local addonName, addon = ...

-- Identity. The ONLY place that knows whether this is the live addon ("TalentShare") or the side-by-side development
-- copy ("TalentShare-Dev"); everything else reads these fields so both can run in one client without sharing state.
-- BUILD FLAG and the names derived from it come from LibGuildSync-1.0 Addon.Setup (LibGuildSync/Addon.lua), shared with
-- GuildGames: a development build when the generated TalentShare-Dev.toc says "## X-Build: dev" (tools/deploy.ps1) OR the
-- folder name contains "dev"; either signal is enough, so a mismatch fails toward isolation. It sets addon.BUILD,
-- IS_DEVELOPMENT_BUILD, BASE_VERSION, VERSION, TITLE, PREFIX ("TShare"/"TShareDev"), SAVED_VARIABLES_NAME, FRAME_PREFIX,
-- SLASH_COMMANDS (/ts /talentshare or /tsd /talentsharedev), SlashCommands (handlers by word) and Print, warns when the
-- TOC saves another global than this build uses, and registers the slash commands. Do not test the addon folder name or
-- hard-code "TShare" elsewhere.
-- The fallback version only matters for the offline tests, which have no client; tests/test_hardening.lua checks it
-- against the TOC.
LibStub("LibGuildSync-1.0").Addon.Setup(addon, addonName,
    { name = "TalentShare", prefix = "TShare", command = "ts", fallbackVersion = "0.7.3", color = "33ccff" })

-- Wire protocol (docs/protocol.md): MAJOR must match exactly between peers, MINOR may differ (additive changes only).
-- Bump MAJOR for any breaking change to the chunk header, serializer, compression or message meaning.
---@type integer
addon.PROTOCOL_MAJOR = 2
---@type integer
addon.PROTOCOL_MINOR = 3
---@type integer alias: the major is what the payload "v" field carries
addon.PROTOCOL = addon.PROTOCOL_MAJOR

addon.SlashCommands.version = function()
    addon.Print("v" .. addon.VERSION .. " (protocol " .. addon.PROTOCOL_MAJOR .. "." .. addon.PROTOCOL_MINOR .. ", schema "
        .. tostring(addon.Store.SCHEMA) .. ", prefix " .. addon.PREFIX .. ")")
end
