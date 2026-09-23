--[[
    This file is part of Modular Computers.
    Modular Computers is free software: you can redistribute it and/or modify it under the terms of the
    GNU Affero General Public License as published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    Modular Computers is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
    without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License along with Modular Computers.
    If not, see <https://www.gnu.org/licenses/>.
    The license is included in the project root under the file labeled LICENSE. All files not otherwise
    specified under a different license shall be put under this license.

    Copyright (c) 2026 James Clarke <james@jamesdavidclarke.com>
]]

-- The Lua machine of a running computer, modelled on OpenComputers.
--
-- A machine boots by loading the libraries in src/os/rom/lib into a sandboxed environment,
-- then runs an event loop (the daemon process) that calls event listeners and timers.
-- Programs started from the shell run as the foreground process. Processes talk to the
-- machine with system calls: waiting for a signal, reading a line of input and exiting.
-- Machines only exist while their tower is loaded; they boot again when it loads.

local sandbox = modular_computers.sandbox
local terminal = modular_computers.terminal
local drive = modular_computers.os.fs.drive

local machine = {}
modular_computers.machine = machine

local pack, unpack = sandbox.pack, unpack or table.unpack
local get_us_time = minetest.get_us_time
local insert, remove, concat = table.insert, table.remove, table.concat

machine.MAX_SIGNALS = 256
machine.MAX_INPUT = 64
machine.MAX_OUTPUT = 64 * 1024
-- Environment variables a machine may have, and the length of their values
machine.MAX_VARIABLES = 256
machine.MAX_VARIABLE = 4096
machine.STEP_BUDGET = 5000 -- microseconds of program time per server step
machine.RESUMES_PER_STEP = 16
-- Microseconds a process should run before it yields. Its CPU's instructions run out first;
-- a process is only stopped for time when it runs four times this long.
machine.MAX_TIME = 50000
-- Instruction and memory limits for each time a process runs, by CPU and RAM tier
machine.INSTRUCTIONS = { 1000000, 2000000, 4000000 }
machine.MEMORY = { 4096, 8192, 16384 }
-- When the server's Lua memory (in KiB) grows past this, the machine that allocated the
-- most lately is stopped
machine.SERVER_MEMORY_LIMIT = (tonumber(minetest.settings:get("modular_computers.memory_limit")) or 1024) * 1024

-- Programs and libraries that come with the computer, by path
local ROM = {}
machine.ROM = ROM

local function read_rom(directory, names)
    for _, name in ipairs(names) do
        local file = io.open(modular_computers.mod.path .. "/src/os/rom/" .. directory .. "/" .. name, "r")
        ROM["/" .. directory .. "/" .. name] = file:read("*a")
        file:close()
    end
end
read_rom("lib", { "boot.lua", "computer.lua", "component.lua", "event.lua", "term.lua", "filesystem.lua",
    "io.lua", "os.lua", "package.lua", "serialization.lua", "sides.lua", "colors.lua", "text.lua",
    "shell.lua", "internet.lua", "unicode.lua" })
read_rom("bin", { "lua.lua", "wget.lua", "components.lua" })
-- The ROM is loaded at every boot, so its code is rewritten for the sandbox once
for _, source in pairs(ROM) do
    sandbox.prepare(source)
end

local machines = {}
local order = {}
-- Restarts that came soon after starting, by position, to catch a startup.lua that restarts
local quick_restarts = {}
machine.QUICK_RESTART = 2e6
machine.MAX_QUICK_RESTARTS = 3

-- Called by components to find what they are part of
machine.components = {}

local function key(pos)
    return minetest.hash_node_position(pos)
end

function machine.get(pos)
    return machines[key(pos)]
end

function machine.all()
    return machines
end

local function simple_hash(text)
    local parts = {}
    for seed = 1, 4 do
        local h = seed * 2166136261 % 4294967296
        for i = 1, #text do
            h = (h * 16777619 + text:byte(i) + seed) % 4294967296
        end
        parts[seed] = string.format("%08x", h)
    end
    return table.concat(parts)
end

-- Returns a UUID-like address made from a text, so the same text gives the same address
function machine.derive_address(text)
    local hash = minetest.sha1 and minetest.sha1(text) or simple_hash(text)
    return hash:sub(1, 8) .. "-" .. hash:sub(9, 12) .. "-" .. hash:sub(13, 16) .. "-" .. hash:sub(17, 20)
        .. "-" .. hash:sub(21, 32)
end

local function is_simple(value)
    local t = type(value)
    return t == "nil" or t == "boolean" or t == "number" or t == "string"
end

-- Queues a signal (an event) for the machine. Arguments must be nil, booleans, numbers or strings.
function machine.push_signal(m, name, ...)
    if type(name) ~= "string" then
        return false
    end
    local signal = pack(name, ...)
    for i = 2, signal.n do
        if not is_simple(signal[i]) then
            return false
        end
    end
    if #m.signals >= machine.MAX_SIGNALS then
        return false
    end
    insert(m.signals, signal)
    return true
end

-- Output of programs: shown on the terminal and, when a program draws, on the GPU buffer
function machine.write(m, text)
    if m.output_size >= machine.MAX_OUTPUT then
        return
    end
    -- Escape sequences are for the terminal's own text, like translations
    text = string.gsub(text, "\27", "")
    if m.output_size + #text > machine.MAX_OUTPUT then
        text = text:sub(1, machine.MAX_OUTPUT - m.output_size) .. "\n[output truncated]\n"
    end
    m.output_size = m.output_size + #text
    insert(m.output, text)
    if m.screen and m.screen.mode == "graphics" then
        modular_computers.gpu.write(m, text)
    end
end

local function flush_output(m)
    if #m.output > 0 then
        local meta = minetest.get_meta(m.pos)
        terminal.append(meta, concat(m.output))
        m.output, m.output_size = {}, 0
        m.dirty = true
        m.output_changed = true
    end
end

-- Moves what programs wrote to the terminal
machine.flush = flush_output

local function new_process(m, fn)
    local co = coroutine.create(fn)
    sandbox.mark_system(co)
    return { co = co }
end

local function end_process(m, process, err)
    if process == m.foreground then
        m.foreground = nil
        if err then
            machine.write(m, err .. "\n")
        end
        if process.drew and m.screen then
            m.screen.mode = "text"
        end
        m.dirty = true
        m.prompt_ready = true
    elseif process == m.daemon then
        m.daemon = nil
        if err then
            machine.write(m, "event loop stopped: " .. err .. "\n")
        end
        -- Keep handling events with a new event loop
        if m.loop and not m.stopping then
            m.daemon = new_process(m, m.loop)
        end
    end
end

-- Runs a process until it waits for something, and handles what it asks for
local function resume_process(m, process, ...)
    m.running_process = process
    local results = sandbox.resume(m.task, process.co, ...)
    m.running_process = nil
    if m.task.killed then
        local reason = m.task.killed
        m.task.killed = nil
        end_process(m, process, reason)
    elseif not results[1] then
        end_process(m, process, sandbox.error_message(results[2]))
    elseif coroutine.status(process.co) == "dead" then
        end_process(m, process)
    elseif results[2] == sandbox.SYSCALL then
        local call, argument = results[3], results[4]
        if call == "pull" then
            process.wait = "signal"
            local timeout = tonumber(argument) or math.huge
            process.deadline = get_us_time() + math.max(math.min(timeout, 1e9), 0) * 1e6
        elseif call == "read" then
            process.wait = "input"
            if process == m.foreground then
                m.prompt_ready = true
            end
        elseif call == "exit" then
            end_process(m, process)
        elseif call == "yield" then
            -- Resumed in the next step
            process.wait = nil
        else
            end_process(m, process, "bad system call")
        end
    else
        process.wait = nil
    end
end

-- Restarts or turns off the machine after a program asked for it
local function change_power(m)
    local reboot = m.reboot
    m.reboot = nil
    machine.stop(m.pos)
    if reboot then
        local hash = key(m.pos)
        quick_restarts[hash] = get_us_time() - m.started < machine.QUICK_RESTART and (quick_restarts[hash] or 0) + 1
            or nil
        machine.start(m.pos)
    else
        minetest.get_meta(m.pos):set_string("power", "off")
        modular_computers.computer.update(m.pos)
    end
end

-- Whether a process can run now, and what to hand it when it does
local function ready(m, process, now)
    if process.wait == nil then
        return true
    elseif process.wait == "signal" then
        local gets_signals = process == m.foreground or not (m.foreground and m.foreground.wait == "signal")
        if gets_signals and #m.signals > 0 then
            return true, remove(m.signals, 1)
        end
        if now >= process.deadline then
            return true, pack()
        end
    elseif process.wait == "input" and #m.stdin > 0 then
        return true, pack(remove(m.stdin, 1))
    end
    return false
end

local function tick(m, budget_end)
    for _ = 1, machine.RESUMES_PER_STEP do
        local ran = false
        for _, which in ipairs({ "foreground", "daemon" }) do
            local process = m[which]
            if process and m.reboot == nil and get_us_time() < budget_end then
                local ok, values = ready(m, process, get_us_time())
                if ok then
                    ran = true
                    if values then
                        resume_process(m, process, unpack(values, 1, values.n))
                    else
                        resume_process(m, process)
                    end
                end
            end
        end
        if not ran then
            break
        end
    end
    flush_output(m)
end

-- Private functions for the libraries in the ROM; programs can't reach them
local function host_functions(m)
    local wrap = sandbox.wrap
    local host = {}

    host.write = wrap(function(text)
        if type(text) ~= "string" then
            error("bad argument #1 (string expected)", 0)
        end
        machine.write(m, text)
    end)
    host.read = function()
        return sandbox.syscall("read")
    end
    host.pull = function(timeout)
        return sandbox.syscall("pull", timeout)
    end
    host.exit = function()
        return sandbox.syscall("exit")
    end
    host.push = wrap(function(...)
        return machine.push_signal(m, ...)
    end)
    host.uptime = wrap(function()
        return (get_us_time() - m.started) / 1e6
    end)
    host.address = wrap(function()
        return m.address
    end)
    host.memory = wrap(function()
        local total = machine.MEMORY[m.ram_tier] * 1024
        return math.max(total - m.task.allocated * 1024, 0), total
    end)
    host.shutdown = wrap(function(reboot)
        m.reboot = reboot and true or false
        sandbox.kill(m.task, "shutting down")
    end)
    host.clear = wrap(function()
        flush_output(m)
        terminal.append(minetest.get_meta(m.pos), terminal.CLEAR)
        if m.screen then
            modular_computers.gpu.clear(m)
            m.screen.mode = "text"
        end
        m.dirty = true
    end)
    host.rom = wrap(function(path)
        return ROM[path]
    end)
    host.cwd = wrap(function()
        return m.cwd
    end)
    host.set_cwd = wrap(function(path)
        local resolved, err = drive.resolve(path, m.cwd)
        if not resolved then
            return nil, err
        end
        if not drive.is_dir(m.drive, resolved) then
            return nil, "no such directory"
        end
        m.cwd = resolved
        minetest.get_meta(m.pos):set_string("cwd", resolved)
        return true
    end)
    host.resolve = wrap(function(path)
        return drive.resolve(path, m.cwd)
    end)
    host.read_file = wrap(function(path)
        local resolved, err = drive.resolve(path, m.cwd)
        if not resolved then
            return nil, err
        end
        if ROM[resolved] then
            return ROM[resolved], resolved
        end
        -- Reading a file makes a string as long as it
        local size = drive.size(m.drive, resolved)
        sandbox.allocate(size)
        sandbox.charge(size / 16)
        local content = drive.read(m.drive, resolved)
        if not content then
            return nil, path .. ": no such file"
        end
        return content, resolved
    end)
    host.getenv = wrap(function(name)
        if name == "PWD" then
            return m.cwd
        end
        return m.variables[name]
    end)
    host.setenv = wrap(function(name, value)
        if type(name) ~= "string" or #name > 256 or (value ~= nil and type(value) ~= "string"
                and type(value) ~= "number") then
            return nil
        end
        value = value and tostring(value)
        if value and #value > machine.MAX_VARIABLE then
            error("value too long", 0)
        end
        if value and m.variables[name] == nil then
            local count = 0
            for _ in pairs(m.variables) do
                count = count + 1
            end
            if count >= machine.MAX_VARIABLES then
                error("too many variables", 0)
            end
        end
        m.variables[name] = value
        return value
    end)
    host.list = wrap(function(filter, exact)
        local result = {}
        for address, component in pairs(m.components) do
            local t = component.type
            if not filter or (exact and t == filter) or (not exact and t:find(filter, 1, true)) then
                result[address] = t
            end
        end
        return result
    end)
    host.type = wrap(function(address)
        local component = m.components[address]
        return component and component.type
    end)
    host.slot = wrap(function(address)
        local component = m.components[address]
        return component and component.slot or -1
    end)
    host.methods = wrap(function(address)
        local component = m.components[address]
        if not component then
            return nil, "no such component"
        end
        local names = {}
        for name in pairs(component.methods) do
            names[name] = true
        end
        return names
    end)
    host.invoke = wrap(function(address, method, ...)
        local component = m.components[address]
        if not component then
            error("no such component", 0)
        end
        local fn = type(method) == "string" and component.methods[method]
        if not fn then
            error("no such method", 0)
        end
        return fn(m, component, ...)
    end)
    return host
end

local function create_environment(m)
    local env, string_library = sandbox.new_environment()
    m.env = env
    m.task = sandbox.new_task({
        string = string_library,
        instructions = machine.INSTRUCTIONS[m.cpu_tier],
        memory = machine.MEMORY[m.ram_tier],
        time = machine.MAX_TIME,
    })
    env.load = function(source, name, mode, environment)
        if type(name) ~= "string" then
            name = "load"
        end
        if environment ~= nil and type(environment) ~= "table" then
            return nil, "bad argument #4 to 'load' (table expected)"
        end
        return sandbox.load(source, name, environment or env)
    end
    env.loadstring = function(source, name)
        return env.load(source, name)
    end
end

local function get_tier(stack, kind)
    return modular_computers.hardware.get_tier(stack, kind)
end

-- Starts the machine of the tower at pos
function machine.start(pos)
    if machine.get(pos) then
        return machine.get(pos)
    end
    local meta = minetest.get_meta(pos)
    local inv = meta:get_inventory()

    local address = meta:get_string("address")
    if address == "" then
        address = drive.new_id()
        meta:set_string("address", address)
    end

    local m = {
        pos = vector.new(pos.x, pos.y, pos.z),
        address = address,
        signals = {},
        stdin = {},
        output = {},
        output_size = 0,
        variables = { HOME = "/", PATH = "/bin:.", SHELL = "/bin/sh" },
        started = get_us_time(),
        cwd = meta:get_string("cwd") ~= "" and meta:get_string("cwd") or "/",
        cpu_tier = math.max(get_tier(inv:get_stack("cpu", 1), "cpu"), 1),
        ram_tier = math.max(get_tier(inv:get_stack("ram", 1), "ram"), 1),
    }
    machines[key(pos)] = m
    insert(order, m)

    modular_computers.components.build(m)
    -- The programs and libraries of the ROM show up in these
    for _, directory in ipairs({ "/bin", "/lib" }) do
        if not drive.is_dir(m.drive, directory) then
            drive.mkdir(m.drive, directory)
        end
    end
    if not drive.is_dir(m.drive, m.cwd) then
        m.cwd = "/"
    end
    create_environment(m)

    local host = host_functions(m)
    local boot = sandbox.load(ROM["/lib/boot.lua"], "/lib/boot.lua", m.env)
    m.daemon = new_process(m, function()
        m.loop = boot(host)
        return m.loop()
    end)
    resume_process(m, m.daemon)

    if drive.is_file(m.drive, "/startup.lua") then
        if (quick_restarts[key(pos)] or 0) >= machine.MAX_QUICK_RESTARTS then
            -- Or it would restart for ever
            quick_restarts[key(pos)] = nil
            machine.write(m, "/startup.lua skipped: the computer restarted too often\n")
        else
            machine.run(m, "/startup.lua", {})
        end
    end
    -- Show the new machine's screen
    m.dirty, m.prompt_ready = true, true
    return m
end

-- Stops the machine of the tower at pos, closing its files
function machine.stop(pos)
    local m = machine.get(pos)
    if not m then
        return
    end
    m.stopping = true
    modular_computers.components.close(m)
    flush_output(m)
    machines[key(pos)] = nil
    for i, other in ipairs(order) do
        if other == m then
            remove(order, i)
            break
        end
    end
end

-- Starts a program as the foreground process. args are strings.
function machine.run(m, path, args)
    local source = ROM[path] or drive.read(m.drive, path)
    if not source then
        return nil, path .. ": no such file"
    end
    local program_env = setmetatable({ arg = args }, { __index = m.env })
    m.foreground = new_process(m, function()
        -- Loaded by the process, under its limits
        local fn, err = sandbox.load(source, path, program_env)
        if not fn then
            error(err, 0)
        end
        return fn(unpack(args))
    end)
    resume_process(m, m.foreground)
    return true
end

-- Starts the machine again, like a reboot
function machine.restart(pos)
    machine.stop(pos)
    return machine.start(pos)
end

-- Adds and removes the components of cards after the cards in the tower changed
function machine.update_cards(pos)
    local m = machine.get(pos)
    if m then
        modular_computers.components.update_cards(m)
    end
end

-- Gives a line typed on the terminal to the foreground program
function machine.input(m, line)
    if #m.stdin < machine.MAX_INPUT then
        insert(m.stdin, line)
    end
end

-- Stops the foreground program
function machine.interrupt(m)
    if m.foreground then
        end_process(m, m.foreground, "interrupted")
    end
end

-- Marks that the foreground program drew on the screen
function machine.drew(m)
    if m.running_process then
        m.running_process.drew = true
    end
end

-- Stops the machine that allocated the most lately when the server runs low on memory
local memory_check_time = 0
local function watch_memory(dtime)
    memory_check_time = memory_check_time + dtime
    if memory_check_time < 1 then
        return
    end
    memory_check_time = 0
    local heaviest
    for _, m in ipairs(order) do
        m.task.allocated = m.task.allocated * 0.9
        if not heaviest or m.task.allocated > heaviest.task.allocated then
            heaviest = m
        end
    end
    local now = get_us_time()
    if heaviest and machine.SERVER_MEMORY_LIMIT > 0 and collectgarbage("count") > machine.SERVER_MEMORY_LIMIT
            and now > (machine.memory_cooldown or 0) and heaviest.task.allocated > 1024 then
        -- Give the garbage collector time before blaming another machine
        machine.memory_cooldown = now + 10e6
        local pos = heaviest.pos
        minetest.log("warning", "[modular_computers] Stopping the computer at " .. minetest.pos_to_string(pos)
            .. ": the server is low on memory")
        machine.stop(pos)
        local meta = minetest.get_meta(pos)
        terminal.append(meta, "\ncomputer crashed: out of memory\n")
        meta:set_string("power", "off")
        modular_computers.computer.update(pos)
    end
end

minetest.register_on_shutdown(function()
    for _, m in ipairs(order) do
        modular_computers.components.close(m)
    end
    drive.save()
end)

minetest.register_globalstep(function(dtime)
    watch_memory(dtime)
    local budget_end = get_us_time() + machine.STEP_BUDGET
    -- Machines can stop and start during the step
    local running = { unpack(order) }
    local count = #running
    if count == 0 then
        return
    end
    -- Start with a different machine every step, so all of them get time
    machine.next_start = ((machine.next_start or 0) % count) + 1
    for i = 0, count - 1 do
        local m = running[((machine.next_start + i - 1) % count) + 1]
        if not m.stopping then
            local node = minetest.get_node_or_nil(m.pos)
            if not node or minetest.get_item_group(node.name, "modular_computer_tower") == 0 then
                -- Unloaded, or replaced without the tower knowing
                machine.stop(m.pos)
            elseif get_us_time() < budget_end then
                tick(m, budget_end)
            end
            if m.reboot ~= nil then
                change_power(m)
            elseif m.dirty and modular_computers.computer.screen_changed(m) then
                m.dirty = false
            end
        end
    end
end)
