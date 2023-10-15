-- This implements a string-based I/O (currently only output) system

local string_output = {}

function string_output:tostring()
    local s = self._value
    if s then
        return s
    end
    s = table.concat(self._buf)
    self._buf = {s}
    return s
end

function string_output:write(x)
    table.insert(self._buf, tostring(x))
    return true
end

string_output.close = string_output.tostring

local string_output_mt = {
    __index = string_output,
    __tostring = string_output.tostring,
}

function new_string_output()
    return setmetatable({_buf = {}}, string_output_mt)
end

setmetatable(string_output, {
    __index = modular_computers.internal.dummy_output,
    __call = function(_, ...) return new_string_output(...) end,
})

modular_computers.internal.string_output = string_output
