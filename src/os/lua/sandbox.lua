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

-- The sandbox that player programs run in.
--
-- Programs run as coroutines on the server's Lua state, so everything they can reach is
-- checked here: an instruction hook stops code that runs too long or allocates too much,
-- JIT compilation is turned off for program code so the hook fires, the shared string
-- metatable points at the program's own string table while it runs, pattern matching is
-- done in Lua, pcall can't catch the error that stops a program, and host functions run
-- with the real string library and without being interrupted halfway. Library functions
-- written in C, where the hook can't fire, are charged for the work they do.

-- The hook doesn't fire in compiled code, so nothing here is compiled
local jit = rawget(_G, "jit")
if jit then
    jit.off(true, true)
end

local patterns = modular_computers.patterns
local rewrite = modular_computers.rewrite

local sandbox = {}
modular_computers.sandbox = sandbox

local real_string = string
local string_meta = getmetatable("")
local sethook = debug.sethook
local traceback = debug.traceback
local co_create, co_resume, co_yield = coroutine.create, coroutine.resume, coroutine.yield
local co_status, co_running = coroutine.status, coroutine.running
local collectgarbage, loadstring, setfenv = collectgarbage, loadstring, setfenv
local pcall, xpcall, error, type, select, tostring = pcall, xpcall, error, type, select, tostring
local unpack = unpack or table.unpack
local concat = table.concat
local get_us_time = minetest.get_us_time

-- Values programs can't get hold of: the error that stops a program, and the first value
-- of a yield that is a call to the machine
local KILL = setmetatable({}, { __tostring = function() return "program stopped" end })
local SYSCALL = {}
sandbox.KILL = KILL
sandbox.SYSCALL = SYSCALL

sandbox.HOOK_INTERVAL = 1000
sandbox.HOST_CALL_COST = 50
sandbox.MAX_STRING = 1024 * 1024
sandbox.MAX_SOURCE = 256 * 1024
-- Lua compiles code longer than this in the time a program may run at once, but not in half of it
local LONG_SOURCE = 16 * 1024
-- Strings shorter than this are left to the hook, which sees the memory they take soon enough
sandbox.SMALL_ALLOCATION = 4096
-- How long a host function may overrun the deadline before it is stopped anyway
sandbox.HOST_GRACE = 1000000

-- The task running right now: { budget, deadline, time_limit, memory_limit, killed, in_host,
-- string }. Programs are stopped when their instructions run out. Time is only a last resort,
-- for work the instructions don't count: a busy server can be slow for reasons of its own.
local current

-- Coroutines of the machine itself, which programs may not resume
local system_coroutines = setmetatable({}, { __mode = "k" })

local function pack(...)
    return { n = select("#", ...), ... }
end
sandbox.pack = pack

local function hook()
    local task = current
    if not task then
        return
    end
    if not task.killed then
        task.budget = task.budget - sandbox.HOOK_INTERVAL
        if task.budget <= 0 or get_us_time() > task.time_limit then
            task.killed = "too long without yielding"
        elseif collectgarbage("count") > task.memory_limit then
            task.killed = "not enough memory"
        end
    end
    if task.killed and (not task.in_host or get_us_time() > task.time_limit + sandbox.HOST_GRACE) then
        error(KILL, 0)
    end
end

-- In LuaJIT hooks are global and setting one restarts its count, so it is only set when a
-- task starts. In PUC Lua hooks belong to each coroutine, so new coroutines get one too.
local function set_hook(co)
    sethook(co, hook, "", sandbox.HOOK_INTERVAL)
end

local function clear_hook(co)
    sethook(co)
end

-- Returns the task running now, or nil when no program is running
function sandbox.current()
    return current
end

-- Creates the state of a program: its limits and its string library
function sandbox.new_task(options)
    return {
        max_budget = options.instructions or 2000000,
        max_time = options.time or 20000,
        max_memory = options.memory or 4096,
        string = options.string,
        allocated = 0,
    }
end

-- Resumes a coroutine of a program under the program's limits. Returns the results of
-- coroutine.resume, and marks the task killed when it was stopped by the limits.
function sandbox.resume(task, co, ...)
    local previous = current
    current = task
    task.budget = task.max_budget
    task.deadline = get_us_time() + task.max_time
    task.time_limit = task.deadline + 3 * task.max_time
    local memory_before = collectgarbage("count")
    task.memory_limit = memory_before + task.max_memory
    task.in_host = false

    string_meta.__index = task.string
    set_hook(co)
    local results = pack(co_resume(co, ...))
    clear_hook(co)
    string_meta.__index = real_string

    current = previous
    local grown = collectgarbage("count") - memory_before
    if grown > 0 then
        task.allocated = task.allocated + grown
    end
    if not results[1] and results[2] == KILL and not task.killed then
        task.killed = "program stopped"
    end
    return results
end

-- Stops a task: the next time its code runs it gets the error that ends it
function sandbox.kill(task, reason)
    task.killed = task.killed or reason or "program stopped"
end

-- Marks a coroutine as belonging to the machine, so programs can't resume it
function sandbox.mark_system(co)
    system_coroutines[co] = true
end

-- Wraps a host function for programs: it runs with the real string library, is charged
-- against the program's budget and is not stopped halfway by the instruction hook
function sandbox.wrap(fn)
    return function(...)
        local task = current
        if not task then
            return fn(...)
        end
        task.budget = task.budget - sandbox.HOST_CALL_COST
        if task.budget <= 0 and not task.killed then
            task.killed = "too long without yielding"
        end
        if task.killed then
            error(KILL, 0)
        end
        task.in_host = true
        string_meta.__index = real_string
        local results = pack(pcall(fn, ...))
        string_meta.__index = task.string
        task.in_host = false
        if not task.killed and get_us_time() > task.time_limit then
            task.killed = "too long without yielding"
        end
        if task.killed then
            error(KILL, 0)
        end
        if not results[1] then
            error(sandbox.strip_paths(results[2]), 0)
        end
        return unpack(results, 2, results.n)
    end
end

-- Removes the server's directories from error messages, leaving file names and lines: in
-- ".../mods/mod/file.lua:12: message", the part before "file.lua". Messages can be long and
-- made by programs, so this goes through them once, without patterns, which run in C where
-- the hook can't stop them. separator is "/" or, on Windows, "\\".
local function strip_paths(message, separator)
    local marker, separator_byte = separator .. "mods" .. separator, real_string.byte(separator)
    if not real_string.find(message, marker, 1, true) then
        return message
    end
    local parts, copied, position, colon = {}, 1, 1, 0
    while true do
        local found = real_string.find(message, marker, position, true)
        if not found then
            break
        end
        -- The path starts after the space or colon before it, or with a drive letter
        local start = found
        while start > copied do
            local b = real_string.byte(message, start - 1)
            if b == 32 or b == 9 or b == 10 or b == 58 then
                break
            end
            start = start - 1
        end
        if start - 2 >= copied and real_string.find(message, "^%a:", start - 2)
                and (start == 3 or real_string.find(message, "^%s", start - 3)) then
            start = start - 2
        end
        -- and ends at the colon before its line number
        if colon < found then
            colon = real_string.find(message, ":", found, true)
            if not colon then
                break
            end
        end
        -- The file name is what follows the last separator of the path
        local name_start = colon
        while name_start > found and real_string.byte(message, name_start - 1) ~= separator_byte do
            name_start = name_start - 1
        end
        parts[#parts + 1] = real_string.sub(message, copied, start - 1)
        copied = name_start
        position = colon + 1
    end
    parts[#parts + 1] = real_string.sub(message, copied)
    return concat(parts)
end

function sandbox.strip_paths(message)
    if type(message) ~= "string" then
        return message
    end
    return strip_paths(strip_paths(message, "/"), "\\")
end

-- Charges the running program for work done outside the hook's view, and stops it when
-- it runs out of instructions or time
function sandbox.charge(cost)
    local task = current
    if not task then
        return
    end
    task.budget = task.budget - cost
    if not task.killed and (task.budget <= 0 or get_us_time() > task.time_limit) then
        task.killed = "too long without yielding"
    end
    if task.killed and not task.in_host then
        error(KILL, 0)
    end
end
local charge = sandbox.charge

-- Checks that the running program may grow its memory by bytes, before it does, and stops it
-- when it can't. A string can be made in one step, between two checks of the hook.
function sandbox.allocate(bytes)
    local task = current
    if task and bytes >= sandbox.SMALL_ALLOCATION
            and collectgarbage("count") + bytes / 1024 > task.memory_limit then
        task.killed = task.killed or "not enough memory"
        error(KILL, 0)
    end
end
local allocate = sandbox.allocate
patterns.allocate = allocate

-- Wraps a library function so each call is charged cost(...) instructions first
local function metered(fn, cost)
    return function(...)
        charge(cost(...))
        return fn(...)
    end
end

-- Costs of library functions, from the sizes of their arguments. They look at the
-- arguments without running any of the program's code.
local function length(value)
    local t = type(value)
    return (t == "string" or t == "table") and #value or 0
end

-- For functions that make a string as long as their first argument
local function string_cost(s)
    local size = length(s)
    allocate(size)
    return 1 + size / 16
end

-- For string.sub
local function sub_cost(s, i, j)
    if type(s) ~= "string" then
        return 1
    end
    local size = #s
    i, j = tonumber(i) or 1, tonumber(j) or -1
    if i < 0 then
        i = math.max(size + i + 1, 1)
    elseif i == 0 then
        i = 1
    end
    if j < 0 then
        j = size + j + 1
    elseif j > size then
        j = size
    end
    size = j - i + 1
    if size < sandbox.SMALL_ALLOCATION then
        return 1
    end
    allocate(size)
    return 1 + size / 16
end

-- For string.format: its result is about as long as its arguments
local function format_cost(...)
    local size, values = 0, pack(...)
    for i = 1, values.n do
        local value = values[i]
        size = size + (type(value) == "string" and #value or 512)
    end
    allocate(size)
    return 1 + size / 16
end

local function table_cost(t)
    return 1 + length(t) / 4
end

-- For table.concat, which can join a long string many times
local function concat_cost(t, separator, i, j)
    if type(t) ~= "table" then
        return 1
    end
    i = type(i) == "number" and i or 1
    j = type(j) == "number" and j or #t
    if j - i > 1e7 then
        -- More than the budget of any program
        return math.huge
    end
    local size = 0
    for k = i, j do
        local value = rawget(t, k)
        size = size + (type(value) == "string" and #value or 24)
    end
    local separator_length = type(separator) == "string" and #separator or 24
    size = size + separator_length * math.max(j - i, 0)
    allocate(size)
    return 1 + (j - i + 1) / 4 + size / 16
end

local function sort_cost(t)
    return 1 + length(t) * 8
end

local function unpack_cost(t, i, j)
    i = type(i) == "number" and i or 1
    j = type(j) == "number" and j or length(t)
    return 1 + math.max(j - i, 0) / 4
end

local function rep_cost(s, n, sep)
    n = type(n) == "number" and n or 0
    local size = (length(s) + length(sep)) * math.max(n, 0)
    -- Strings that are too long are refused before any work is done
    if size > sandbox.MAX_STRING then
        return 1
    end
    allocate(size)
    return 1 + size / 16
end

local function find_cost(s, p, init, plain)
    -- Plain searches run in C and can take time for the length of s times the length of p
    return 1 + length(s) * length(p) / 64
end

-- table.maxn in C goes through the hash part, whose size can't be seen, so it's done here
local function safe_maxn(t)
    if type(t) ~= "table" then
        error("bad argument #1 to 'maxn' (table expected, got " .. type(t) .. ")", 2)
    end
    local result = 0
    for key in next, t do
        if type(key) == "number" and key > result then
            result = key
        end
    end
    return result
end

-- Turns an error value into a message without running any of the program's code
function sandbox.error_message(value)
    if value == KILL then
        return "program stopped"
    elseif type(value) == "string" then
        return sandbox.strip_paths(value)
    elseif type(value) == "number" or type(value) == "boolean" or value == nil then
        return tostring(value)
    end
    return "(error object is a " .. type(value) .. " value)"
end

local function rethrow_kill(ok, ...)
    if not ok and (current and current.killed or (...) == KILL) then
        error(KILL, 0)
    end
    return ok, ...
end

local function safe_pcall(fn, ...)
    return rethrow_kill(pcall(fn, ...))
end

local function safe_xpcall(fn, handler, ...)
    local args = pack(...)
    local function on_error(err)
        if err == KILL or (current and current.killed) then
            return KILL
        end
        return handler(err)
    end
    return rethrow_kill(xpcall(function() return fn(unpack(args, 1, args.n)) end, on_error))
end

-- coroutine.resume for programs: calls to the machine made inside a program's own
-- coroutines are passed up to the machine, and their results passed back down
local function safe_resume(co, ...)
    if type(co) ~= "thread" then
        error("bad argument #1 to 'resume' (coroutine expected)", 2)
    end
    if system_coroutines[co] then
        return false, "cannot resume a system coroutine"
    end
    local args = pack(...)
    while true do
        local results = pack(co_resume(co, unpack(args, 1, args.n)))
        if not results[1] then
            if results[2] == KILL or (current and current.killed) then
                error(KILL, 0)
            end
            return false, results[2]
        end
        if results[2] == SYSCALL and co_status(co) ~= "dead" then
            args = pack(co_yield(unpack(results, 2, results.n)))
        else
            return true, unpack(results, 2, results.n)
        end
    end
end

local function safe_create(fn)
    if type(fn) ~= "function" then
        error("bad argument #1 to 'create' (function expected)", 2)
    end
    local co = co_create(fn)
    if not jit then
        set_hook(co)
    end
    return co
end

local function safe_wrap(fn)
    local co = safe_create(fn)
    return function(...)
        local results = pack(safe_resume(co, ...))
        if not results[1] then
            error(results[2], 0)
        end
        return unpack(results, 2, results.n)
    end
end

local function safe_rep(s, n, sep)
    s = real_string.format("%s", s)
    n = tonumber(n) or 0
    if n <= 0 then
        return ""
    end
    sep = sep and real_string.format("%s", sep) or ""
    if (#s + #sep) * n > sandbox.MAX_STRING then
        error("string.rep: resulting string too large", 2)
    end
    if sep == "" then
        return real_string.rep(s, n)
    end
    return real_string.rep(s .. sep, n - 1) .. s
end

local DATE_FORMAT = "^!?[%%aAbBcdHIjmMpSUwWxXyY%s%p%w]*$"
local function safe_date(format, time)
    format = format or "%c"
    if type(format) ~= "string" then
        error("bad argument #1 to 'date' (string expected)", 2)
    end
    -- Each conversion can make a dozen characters, in one step
    if #format > 256 then
        error("bad argument #1 to 'date' (format too long)", 2)
    end
    if format ~= "*t" and format ~= "!*t" then
        -- Only conversions that are the same everywhere
        for conversion in real_string.gmatch(format, "%%(.?)") do
            if not real_string.find("aAbBcdHIjmMpSUwWxXyY%", conversion, 1, true) or conversion == "" then
                error("bad argument #1 to 'date' (invalid conversion specifier '%" .. conversion .. "')", 2)
            end
        end
        if not real_string.find(format, DATE_FORMAT) then
            error("bad argument #1 to 'date' (invalid format)", 2)
        end
    end
    return os.date(format, time)
end

local function safe_traceback(...)
    local text = traceback(...)
    if type(text) ~= "string" then
        return text
    end
    -- Keep server paths out of what programs see: the lines of the stack in the server's files
    -- go. The message before the stack is the program's, and can be long, so it isn't searched.
    local stack = real_string.find(text, "stack traceback:", 1, true)
    if not stack then
        return text
    end
    local parts, position = { real_string.sub(text, 1, stack - 1) }, stack
    while position <= #text do
        local line_end = real_string.find(text, "\n", position, true) or #text
        local line = real_string.sub(text, position, line_end)
        if not real_string.find(line, "/mods/", 1, true) then
            parts[#parts + 1] = line
        end
        position = line_end + 1
    end
    return concat(parts)
end

local function safe_getmetatable(value)
    if type(value) == "string" then
        return nil
    end
    return getmetatable(value)
end

local function safe_tostring(value)
    return tostring(value)
end

local function copy(source, names)
    local result = {}
    for _, name in ipairs(names) do
        result[name] = source[name]
    end
    return result
end

-- Concatenation for programs, whose code the rewriter changes so a .. b .. c calls cat(a, b, c)

local function plain_size(value)
    local t = type(value)
    if t == "string" then
        return #value
    elseif t == "number" then
        return 24
    end
end

local function concat_values(a, b)
    return a .. b
end

-- Errors of .. in concat_values start with where it is in this file, and name its variables
local _, probe = pcall(concat_values, nil, "")
local own_position = real_string.match(probe, "^(.-:%d+: )")

local function concat_error(message, level)
    if message == KILL or (current and current.killed) then
        error(KILL, 0)
    end
    -- Errors of .. are short; long messages come from metamethods and aren't searched
    if type(message) == "string" and #message < 512 and own_position
            and real_string.sub(message, 1, #own_position) == own_position then
        -- An error of .. itself: report it where the program concatenated
        message = real_string.sub(message, #own_position + 1)
        message = real_string.gsub(message, "attempt to concatenate %a+ '[^']*' %(a (%a+) value%)",
            "attempt to concatenate a %1 value")
        error(message, level + 1)
    end
    -- An error of a __concat metamethod, which says where it is itself
    error(message, 0)
end

-- a .. b, with errors reported level levels up
local function concat_pair(a, b, level)
    local size_a, size_b = plain_size(a), plain_size(b)
    if size_a and size_b then
        if size_a + size_b >= sandbox.SMALL_ALLOCATION then
            allocate(size_a + size_b)
        end
        return a .. b
    end
    -- __concat metamethods, and errors
    local ok, result = pcall(concat_values, a, b)
    if not ok then
        concat_error(result, level + 1)
    end
    return result
end

local function cat(a, b, ...)
    local rest = select("#", ...)
    if rest == 0 then
        local result = concat_pair(a, b, 2)
        return result
    end
    local values, count = { a, b, ... }, rest + 2
    local size = 0
    for i = 1, count do
        local value_size = plain_size(values[i])
        if not value_size then
            size = nil
            break
        end
        size = size + value_size
    end
    if size then
        if size >= sandbox.SMALL_ALLOCATION then
            allocate(size)
        end
        return concat(values, "", 1, count)
    end
    -- Right to left, like Lua does when there are metamethods
    local result = values[count]
    for i = count - 1, 1, -1 do
        result = concat_pair(values[i], result, 2)
    end
    return result
end

-- The code of programs after rewriting, which takes cat as its first argument, and the name
-- it gives cat
local function prepare(source)
    local cat_name
    for attempt = 1, 100 do
        cat_name = attempt == 1 and "__concat" or "__concat" .. attempt
        local code, err = rewrite.concatenations(source, cat_name)
        if code then
            return "local " .. cat_name .. " = ... return function(...) " .. code .. "\nend"
        elseif not real_string.find(err, "uses the name", 1, true) then
            return nil, err
        end
    end
    return nil, "the code uses too many names"
end

-- Rewriting long code takes a while, so it pauses until the next server step when half of
-- the time or instructions the program may use at once are gone
rewrite.pause = function()
    local task = current
    if task and not task.in_host and (task.budget < task.max_budget / 2
            or get_us_time() > task.deadline - task.max_time / 2) then
        -- Code loaded where a pause can't happen, like in a table.sort comparison, goes on
        pcall(sandbox.syscall, "yield")
    end
end

local function read_uleb128(dump, position)
    local value, scale = 0, 1
    repeat
        local b = real_string.byte(dump, position)
        if not b then
            return nil
        end
        position = position + 1
        value = value + b % 128 * scale
        scale = scale * 128
    until b < 128
    return value, position
end

-- Returns the set of instruction opcodes in the code of fn and the functions in it, read from
-- a stripped LuaJIT bytecode dump (lj_bcdump.h), or nil when that can't be done. The dump has
-- a header and, for each function, its length, flags, counts of parameters, frame slots,
-- upvalues and constants, the number of instructions, and the instructions.
local function opcodes(fn)
    local ok, dump = pcall(real_string.dump, fn, true)
    if not ok or real_string.sub(dump, 1, 3) ~= "\27LJ" then
        return nil
    end
    local flags, position = read_uleb128(dump, 5)
    if not flags then
        return nil
    end
    local opcode_offset = flags % 2 == 1 and 3 or 0 -- big endian
    local found, checked = {}, 0
    while true do
        local size, start = read_uleb128(dump, position)
        if not size then
            return nil
        elseif size == 0 then
            return found
        end
        local p = start + 4
        local count
        for _ = 1, 3 do
            count, p = read_uleb128(dump, p)
            if not count then
                return nil
            end
        end
        for i = 0, count - 1 do
            local opcode = real_string.byte(dump, p + i * 4 + opcode_offset)
            if not opcode then
                return nil
            end
            found[opcode] = true
        end
        checked = checked + count
        if checked > 4096 then
            checked = 0
            rewrite.pause()
        end
        position = start + size
    end
end

-- LuaJIT's bytecode instruction for .., found by comparing code that concatenates with code
-- that does the same without, so loaded code can be checked for concatenation the rewriter
-- missed
local CAT_OPCODE
if jit and real_string.dump then
    local with = opcodes(function(a, b)
        return a .. b
    end)
    local without = opcodes(function(a, b)
        local x, _ = a, b
        return x
    end)
    if with and without then
        for opcode in pairs(with) do
            if not without[opcode] then
                if CAT_OPCODE then
                    CAT_OPCODE = nil
                    break
                end
                CAT_OPCODE = opcode
            end
        end
    end
    if not CAT_OPCODE then
        minetest.log("warning", "[modular_computers] Can't check the code of programs for concatenation")
    end
end

-- Returns true if the code of fn, or of the functions in it, concatenates with the ..
-- instruction, or when that can't be known
function sandbox.concatenates(fn)
    if not CAT_OPCODE then
        return false
    end
    local found = opcodes(fn)
    return not found or found[CAT_OPCODE] == true
end

-- Pauses until the next server step, so the program can use all of its time for what comes
-- next, which can't be paused
local function pause_now()
    local task = current
    if task and not task.in_host then
        pcall(sandbox.syscall, "yield")
    end
end

-- Code of the libraries and programs that come with the computer, prepared once
local prepared = {}

-- Prepares code that will be loaded often, like the ROM's
function sandbox.prepare(source)
    prepared[source] = prepared[source] or assert(prepare(source))
end

-- Loads source code as a function of a program, in environment env
function sandbox.load(source, name, env)
    if type(source) ~= "string" then
        return nil, "bad argument #1 to 'load' (string expected, got " .. type(source) .. ")"
    end
    if real_string.byte(source, 1) == 27 then
        return nil, "binary chunks are not allowed"
    end
    if #source > sandbox.MAX_SOURCE then
        return nil, "code is too long"
    end
    -- LuaJIT skips a byte order mark and a first line starting with #, which the rewritten
    -- code would no longer start with. The line stays, empty, so line numbers don't change.
    if real_string.sub(source, 1, 3) == "\239\187\191" then
        source = real_string.sub(source, 4)
    end
    if real_string.byte(source, 1) == 35 then
        source = real_string.gsub(source, "^[^\n\r]*", "", 1)
    end
    name = "=" .. (name or "load")
    local code = prepared[source]
    if not code then
        charge(#source / 4)
        allocate(#source * 2)
        if #source > LONG_SOURCE then
            pause_now()
        end
        -- Syntax errors come from Lua, in its words
        local fn, err = loadstring(source, name)
        if not fn then
            return nil, err
        end
        code, err = prepare(source)
        if not code then
            return nil, err
        end
        if #source > LONG_SOURCE then
            pause_now()
        end
    end
    local wrapper, err = loadstring(code, name)
    if not wrapper then
        return nil, err
    end
    if sandbox.concatenates(wrapper) then
        return nil, "unsupported code"
    end
    setfenv(wrapper, env)
    if jit then
        jit.off(wrapper, true)
    end
    return wrapper(cat)
end

-- Returns math.random and math.randomseed for a program, with numbers of its own, so programs
-- can't see or change the server's
local function new_random(seed)
    local generator, state
    local function randomseed(value)
        value = math.floor(tonumber(value) or 0) % 2147483646
        generator = rawget(_G, "PcgRandom") and PcgRandom(value)
        state = value + 1
    end
    local function random(m, n)
        local value
        if generator then
            value = (generator:next() + 2147483648) / 4294967296
        else
            state = state * 48271 % 2147483647
            value = (state - 1) / 2147483646
        end
        if m == nil then
            return value
        end
        m = tonumber(m) or error("bad argument #1 to 'random' (number expected)", 2)
        if n == nil then
            m, n = 1, m
        else
            n = tonumber(n) or error("bad argument #2 to 'random' (number expected)", 2)
        end
        m, n = math.floor(m), math.floor(n)
        if m > n then
            error("bad argument to 'random' (interval is empty)", 2)
        end
        return m + math.floor(value * (n - m + 1))
    end
    randomseed(seed)
    return random, randomseed
end

-- Creates the global environment of a program, with the parts of the standard library
-- that are safe to use
function sandbox.new_environment()
    local env = {}
    local string_library = copy(real_string, { "byte", "char", "len" })
    string_library.sub = metered(real_string.sub, sub_cost)
    string_library.format = metered(real_string.format, format_cost)
    string_library.lower = metered(real_string.lower, string_cost)
    string_library.upper = metered(real_string.upper, string_cost)
    string_library.reverse = metered(real_string.reverse, string_cost)
    string_library.rep = metered(safe_rep, rep_cost)
    string_library.find = metered(patterns.find, find_cost)
    string_library.match = patterns.match
    string_library.gmatch = patterns.gmatch
    string_library.gsub = patterns.gsub

    local safe_unpack = metered(unpack, unpack_cost)
    local table_library = {
        concat = metered(table.concat, concat_cost),
        insert = metered(table.insert, table_cost),
        remove = metered(table.remove, table_cost),
        sort = metered(table.sort, sort_cost),
        maxn = safe_maxn,
        unpack = safe_unpack,
        pack = pack,
    }

    local math_library = copy(math, { "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg",
        "exp", "floor", "fmod", "frexp", "huge", "ldexp", "log", "log10", "max", "min", "modf", "pi", "pow",
        "rad", "sin", "sinh", "sqrt", "tan", "tanh" })
    math_library.random, math_library.randomseed = new_random(get_us_time())

    env.assert = assert
    env.error = error
    env.ipairs = ipairs
    env.next = next
    env.pairs = pairs
    env.rawequal = rawequal
    env.rawget = rawget
    env.rawset = rawset
    env.rawlen = function(value) return #value end
    env.select = select
    env.setmetatable = setmetatable
    env.getmetatable = safe_getmetatable
    env.tonumber = tonumber
    env.tostring = safe_tostring
    env.type = type
    env.unpack = safe_unpack
    env.pcall = safe_pcall
    env.xpcall = safe_xpcall
    env._VERSION = _VERSION
    env.string = string_library
    env.table = table_library
    env.math = math_library
    env.coroutine = {
        create = safe_create,
        resume = safe_resume,
        yield = co_yield,
        status = co_status,
        running = co_running,
        wrap = safe_wrap,
        isyieldable = function() return co_running() ~= nil end,
    }
    env.os = {
        clock = os.clock,
        date = safe_date,
        difftime = os.difftime,
        time = os.time,
    }
    env.debug = { traceback = safe_traceback }
    local bit = rawget(_G, "bit")
    if bit then
        -- LuaJIT's bit operations give signed results, bit32 gives unsigned ones
        local function unsigned(fn)
            return function(...)
                return fn(...) % 4294967296
            end
        end
        env.bit32 = {
            band = unsigned(bit.band), bor = unsigned(bit.bor), bxor = unsigned(bit.bxor),
            bnot = unsigned(bit.bnot), lshift = unsigned(bit.lshift), rshift = unsigned(bit.rshift),
            arshift = unsigned(bit.arshift), lrotate = unsigned(bit.rol), rrotate = unsigned(bit.ror),
            btest = function(...)
                return bit.band(...) ~= 0
            end,
            extract = function(n, field, width)
                width = width or 1
                return bit.band(bit.rshift(n, field), 2 ^ width - 1) % 4294967296
            end,
        }
    end
    env._G = env
    return env, string_library
end

-- Runs a system call from a program: yields to the machine and returns what it answers
function sandbox.syscall(...)
    return co_yield(SYSCALL, ...)
end
