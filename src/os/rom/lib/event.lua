-- Events: waiting for signals, and listeners and timers that run while signals are pulled
local host = ...
local event = {}
local listeners = {}
local timers = {}
local next_timer = 0

local function report(err)
    host.write("event handler error: " .. tostring(err) .. "\n")
end

local function call(callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then
        report(result)
        return nil
    end
    return result
end

local function dispatch(signal)
    local list = listeners[signal[1]]
    if not list then
        return
    end
    for _, callback in ipairs({ table.unpack(list) }) do
        if call(callback, table.unpack(signal, 1, signal.n)) == false then
            event.ignore(signal[1], callback)
        end
    end
end

local function run_timers()
    local now = computer.uptime()
    local due = {}
    for id, timer in pairs(timers) do
        if now >= timer.deadline then
            table.insert(due, id)
        end
    end
    for _, id in ipairs(due) do
        local timer = timers[id]
        if timer then
            timer.times = timer.times - 1
            if timer.times <= 0 then
                timers[id] = nil
            else
                timer.deadline = now + timer.interval
            end
            call(timer.callback)
        end
    end
end

local function next_deadline()
    local deadline = math.huge
    for _, timer in pairs(timers) do
        deadline = math.min(deadline, timer.deadline)
    end
    return deadline
end

local function matches(signal, name, ...)
    if name ~= nil and not (type(signal[1]) == "string" and signal[1]:match(name)) then
        return false
    end
    local filters = table.pack(...)
    for i = 1, filters.n do
        if filters[i] ~= nil and filters[i] ~= signal[i + 1] then
            return false
        end
    end
    return true
end

-- event.pull([timeout], [name], ...): waits for a signal whose name matches the pattern
-- name and whose arguments equal the other arguments that are not nil
function event.pull(...)
    local args = table.pack(...)
    local timeout, first = math.huge, 1
    if type(args[1]) == "number" then
        timeout, first = args[1], 2
    end
    local deadline = computer.uptime() + timeout
    repeat
        local wait = math.min(deadline, next_deadline()) - computer.uptime()
        local signal = table.pack(computer.pullSignal(math.max(wait, 0)))
        run_timers()
        if signal.n > 0 then
            dispatch(signal)
            if matches(signal, table.unpack(args, first, args.n)) then
                return table.unpack(signal, 1, signal.n)
            end
        end
    until computer.uptime() >= deadline
    return nil
end

function event.pullFiltered(...)
    local args = table.pack(...)
    local timeout, filter = math.huge, args[1]
    if type(args[1]) == "number" then
        timeout, filter = args[1], args[2]
    end
    local deadline = computer.uptime() + timeout
    repeat
        local signal = table.pack(event.pull(deadline - computer.uptime()))
        if signal.n > 0 and (not filter or filter(table.unpack(signal, 1, signal.n))) then
            return table.unpack(signal, 1, signal.n)
        end
    until computer.uptime() >= deadline
    return nil
end

function event.pullMultiple(...)
    local names = table.pack(...)
    return event.pullFiltered(function(name)
        for i = 1, names.n do
            if type(names[i]) == "string" and name:match(names[i]) then
                return true
            end
        end
        return false
    end)
end

function event.listen(name, callback)
    assert(type(name) == "string", "bad argument #1 (string expected)")
    assert(type(callback) == "function", "bad argument #2 (function expected)")
    listeners[name] = listeners[name] or {}
    for _, existing in ipairs(listeners[name]) do
        if existing == callback then
            return false
        end
    end
    table.insert(listeners[name], callback)
    return true
end

function event.ignore(name, callback)
    local list = listeners[name]
    if list then
        for i, existing in ipairs(list) do
            if existing == callback then
                table.remove(list, i)
                return true
            end
        end
    end
    return false
end

function event.timer(interval, callback, times)
    assert(type(interval) == "number", "bad argument #1 (number expected)")
    assert(type(callback) == "function", "bad argument #2 (function expected)")
    next_timer = next_timer + 1
    timers[next_timer] = {
        interval = interval,
        callback = callback,
        times = times or 1,
        deadline = computer.uptime() + interval,
    }
    return next_timer
end

function event.cancel(id)
    local existed = timers[id] ~= nil
    timers[id] = nil
    return existed
end

function event.push(name, ...)
    return computer.pushSignal(name, ...)
end

function event.onError(message)
    report(message)
end

return event
