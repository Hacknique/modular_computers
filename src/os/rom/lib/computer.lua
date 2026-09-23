-- The computer: time, memory, signals and power
local host = ...
local computer = {}

function computer.address() return host.address() end
function computer.uptime() return host.uptime() end
function computer.freeMemory() return (host.memory()) end
function computer.totalMemory() return select(2, host.memory()) end
function computer.pushSignal(name, ...) return host.push(name, ...) end
function computer.pullSignal(timeout) return host.pull(timeout) end
function computer.shutdown(reboot) host.shutdown(reboot) end
function computer.beep() end
function computer.energy() return math.huge end
function computer.maxEnergy() return math.huge end
function computer.isRobot() return false end
function computer.getArchitecture() return "Lua 5.1" end
function computer.getArchitectures() return { "Lua 5.1" } end
function computer.getDeviceInfo() return {} end
function computer.users() end
function computer.addUser() return nil, "not supported" end
function computer.removeUser() return false end
function computer.tmpAddress() return nil end
function computer.getBootAddress()
    return (next(host.list("filesystem", true)))
end

return computer
