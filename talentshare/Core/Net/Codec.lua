local addonName, addon = ...

-- Table <-> string for the addon channel: a LibGuildSync-1.0 Codec (serializer, LibDeflate, chunk header and version
-- rule: LibGuildSync/Codec.lua) for TalentShare's protocol. The version is read from addon.PROTOCOL_* at use time.
---@class CodecModule
addon.Codec = LibStub("LibGuildSync-1.0").Codec.New(setmetatable({}, {
    __index = function(_, field)
        if field == "major" then return addon.PROTOCOL_MAJOR end
        if field == "minor" then return addon.PROTOCOL_MINOR end
        return nil
    end,
}))
