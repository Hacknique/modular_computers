-- Boots a computer: loads the libraries into the global environment and returns the loop
-- that handles events while no program is running. host has the machine's private functions.
local host = ...
local loaded = {}

local function load_library(name)
    local path = "/lib/" .. name .. ".lua"
    local fn = assert(load(host.rom(path), path))
    local module = fn(host, loaded)
    loaded[name] = module
    return module
end

_G.computer = load_library("computer")
_G.component = load_library("component")
_G.event = load_library("event")
load_library("os")
_G.term = load_library("term")
_G.filesystem = load_library("filesystem")
_G.io = load_library("io")
_G.serialization = load_library("serialization")
_G.sides = load_library("sides")
_G.colors = load_library("colors")
_G.text = load_library("text")
_G.unicode = load_library("unicode")
_G.shell = load_library("shell")
_G.internet = load_library("internet")
for _, name in ipairs({ "string", "table", "math", "coroutine", "os", "bit32" }) do
    loaded[name] = _G[name]
end
loaded._G = _G
_G.package = load_library("package")

return function()
    local pull = event.pull
    while true do
        pull()
    end
end
