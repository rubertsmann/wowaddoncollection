-- LibGuildSync-1.0: guild addon-message sync and the helpers around it, shared by TalentShare and GuildGames.
-- Embedded: every addon ships a copy under Libs\LibGuildSync and loads LibGuildSync.xml. LibStub keeps ONE copy active:
--   * Core.lua of a NEWER copy (higher MINOR) takes over the library table; its module files then upgrade every module
--     table in place (same table identity, so instances made by an older copy call the new code).
--   * Files of an equal or older copy are skipped: lib:Module returns nil for them, and each file returns at once.
-- RULE: every file passes the same MINOR as below to lib:Module (tests/test_core.lua pins it). Bump MINOR on ANY change.
-- RULE: state that must survive an in-place upgrade lives in fields created with `x = x or {}`, never in file locals.
local MAJOR, MINOR = "LibGuildSync-1.0", 1

local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.MAJOR, lib.MINOR = MAJOR, MINOR
---@type table<string, table> module name -> module table (kept across upgrades)
lib.modules = lib.modules or {}

-- The module table `name` for the copy being loaded, or nil when this file belongs to a copy that is not the active one
-- (an older copy, or a second copy of the same version). Creates the table on first use and keeps it on upgrades.
---@param name string
---@param minor integer the MINOR of the file's copy
---@return table|nil
function lib:Module(name, minor)
    if minor ~= self.MINOR then return nil end
    local module = self.modules[name]
    if module and module.LIBRARY_MINOR == minor then return nil end
    module = module or {}
    module.LIBRARY_MINOR = minor
    self.modules[name] = module
    self[name] = module
    return module
end
