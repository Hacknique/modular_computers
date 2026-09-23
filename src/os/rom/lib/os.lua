-- Adds sleeping, exiting and environment variables to the os library
local host = ...

function os.sleep(timeout)
    local deadline = computer.uptime() + (tonumber(timeout) or 0)
    repeat
        event.pull(deadline - computer.uptime())
    until computer.uptime() >= deadline
end

function os.exit()
    host.exit()
end

function os.getenv(name) return host.getenv(name) end
function os.setenv(name, value) return host.setenv(name, value) end
function os.remove(path) return filesystem.remove(path) end
function os.rename(from, to) return filesystem.rename(from, to) end
function os.tmpname() return "/tmp/" .. tostring(math.random(100000, 999999)) end

return os
