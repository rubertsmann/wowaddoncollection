local addonName, addon = ...

-- Inbound gate and incompatibility hints: LibGuildSync-1.0 Guard (LibGuildSync/Guard.lua). Trust model: guild members are
-- trusted, everyone else is not; GUILD is accepted, WHISPER only from a member of the cached roster, nothing else.
---@class GuardModule
addon.Guard = LibStub("LibGuildSync-1.0").Guard
