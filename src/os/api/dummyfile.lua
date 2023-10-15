-- This implements a dummy for Lua's "file" object. Other file-/pipe-
-- related APIs can build on top of this to create "functional" files
-- in the emulated system.

local dummy_file = {}
local dummy_input = setmetatable({}, {__index = dummy_file})
local dummy_output = setmetatable({}, {__index = dummy_file})

local function dummy_no_implementation()
    return nil, "Function not implemented"
end

local function dummy_success()
    return true
end

local function dummy_bad_fd()
    return nil, "Bad file descriptor"
end

dummy_file.close = dummy_success
dummy_file.read = dummy_no_implementation
dummy_file.flush = dummy_success
dummy_file.seek = dummy_no_implementation
dummy_file.setvbuf = dummy_success
dummy_file.write = dummy_no_implementation

function dummy_file:lines()
    return function()
        return self:read("*l")
    end
end

function dummy_file:is_closed() -- Extension for custom io.type()
    return false
end

dummy_input.write = dummy_bad_fd

dummy_output.read = dummy_bad_fd

modular_computers.internal.dummy_file = dummy_file
modular_computers.internal.dummy_input = dummy_input
modular_computers.internal.dummy_output = dummy_output
