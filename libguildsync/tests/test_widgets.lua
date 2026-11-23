-- Widgets.CreateMinimapButton against stub LibDataBroker-1.1 / LibDBIcon-1.0: the button is registered and also offered
-- to the addon compartment when LibDBIcon can do that (button collectors such as Leatrix Plus may hide minimap buttons).
local function withBrokerLibraries(minimapIcons, body)
    local savedBroker, savedIcons = LibStub.libs["LibDataBroker-1.1"], LibStub.libs["LibDBIcon-1.0"]
    LibStub.libs["LibDataBroker-1.1"] = { NewDataObject = function(_, name, fields) fields.name = name; return fields end }
    LibStub.libs["LibDBIcon-1.0"] = minimapIcons
    local ok, errorMessage = pcall(body)
    LibStub.libs["LibDataBroker-1.1"], LibStub.libs["LibDBIcon-1.0"] = savedBroker, savedIcons
    if not ok then error(errorMessage, 0) end
end

local function stubIcons(withCompartment)
    local calls = { registered = {}, compartment = {} }
    local icons = { calls = calls,
        Register = function(_, name, dataObject, settings) calls.registered[#calls.registered + 1] = { name, dataObject, settings } end,
        GetMinimapButton = function() return nil end }   -- hidden button: no frames needed
    if withCompartment then icons.AddButtonToCompartment = function(_, name) calls.compartment[#calls.compartment + 1] = name end end
    return icons
end

return {
    ["widgets: the minimap button is registered and added to the addon compartment"] = function(harness)
        local lib = harness.library()
        local icons = stubIcons(true)
        withBrokerLibraries(icons, function()
            local settings = {}
            local button = lib.Widgets.CreateMinimapButton({ name = "TestAddon", icon = "x", settings = settings, defaultPosition = 200,
                onClick = function() end })
            harness.equal(button, nil, "hidden by the player: no frame")
            harness.equal(#icons.calls.registered, 1); harness.equal(icons.calls.registered[1][1], "TestAddon")
            harness.equal(settings.minimapPos, 200, "default position applied")
            harness.equal(#icons.calls.compartment, 1); harness.equal(icons.calls.compartment[1], "TestAddon")
        end)
    end,

    ["widgets: an older LibDBIcon without compartment support still registers the button"] = function(harness)
        local lib = harness.library()
        local icons = stubIcons(false)
        withBrokerLibraries(icons, function()
            local ok, errorMessage = pcall(lib.Widgets.CreateMinimapButton, { name = "TestAddon", icon = "x", settings = {},
                onClick = function() end })
            harness.truthy(ok, tostring(errorMessage)); harness.equal(#icons.calls.registered, 1)
        end)
    end,
}
