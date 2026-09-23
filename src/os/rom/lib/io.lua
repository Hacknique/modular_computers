-- Input and output: the terminal as stdin and stdout, and files on the hard drive
local host = ...
local io = {}

local function read_line(source, keep_newline)
    local line = source.read_line()
    if line == nil then
        return nil
    end
    return keep_newline and line .. "\n" or line
end

-- Reads one value in the given format from a source that has read_line and read_count
local function read_format(source, format)
    if type(format) == "number" then
        return source.read_count(format)
    end
    format = tostring(format or "l"):gsub("^%*", "")
    local kind = format:sub(1, 1)
    if kind == "l" then
        return read_line(source, false)
    elseif kind == "L" then
        return read_line(source, true)
    elseif kind == "n" then
        local line = read_line(source, false)
        return line and tonumber(line)
    elseif kind == "a" then
        return source.read_all()
    end
    error("bad argument #1 to 'read' (invalid format)", 3)
end

local function read_formats(source, ...)
    local formats = table.pack(...)
    if formats.n == 0 then
        return read_format(source, "l")
    end
    local results = {}
    for i = 1, formats.n do
        results[i] = read_format(source, formats[i])
        if results[i] == nil then
            break
        end
    end
    return table.unpack(results, 1, formats.n)
end

local function write_values(write, ...)
    local values = table.pack(...)
    for i = 1, values.n do
        local value = values[i]
        if type(value) ~= "string" and type(value) ~= "number" then
            error("bad argument #" .. i .. " to 'write' (string expected, got " .. type(value) .. ")", 3)
        end
        write(tostring(value))
    end
end

local terminal_source = {
    read_line = function() return host.read() end,
    read_count = function() return host.read() end,
    read_all = function() return host.read() end,
}

local function stream(name, write)
    local object = { name = name }
    function object:write(...)
        write_values(write, ...)
        return self
    end
    function object:read(...) return read_formats(terminal_source, ...) end
    function object:lines(...)
        local formats = table.pack(...)
        return function() return read_formats(terminal_source, table.unpack(formats, 1, formats.n)) end
    end
    function object:close() return false end
    function object:flush() return self end
    function object:setvbuf() return true end
    return object
end

io.stdin = stream("stdin", function() error("stdin can't be written", 3) end)
io.stdout = stream("stdout", host.write)
io.stderr = stream("stderr", host.write)

local files = setmetatable({}, { __mode = "k" })

local function file_object(handle)
    -- Data read from the file and not handed out yet starts at position in buffer
    local buffer, position, closed = "", 1, false
    local file = {}
    files[file] = true

    local function fill()
        local data = handle.read(8192)
        if data then
            buffer = buffer:sub(position) .. data
            position = 1
            return true
        end
        return false
    end

    local source = {}
    function source.read_line()
        while true do
            local newline = buffer:find("\n", position, true)
            if newline then
                local line = buffer:sub(position, newline - 1)
                position = newline + 1
                return line
            end
            if not fill() then
                if position > #buffer then
                    return nil
                end
                local line = buffer:sub(position)
                buffer, position = "", 1
                return line
            end
        end
    end
    function source.read_count(count)
        while #buffer - position + 1 < count and fill() do end
        if position > #buffer and count > 0 then
            return nil
        end
        local data = buffer:sub(position, position + count - 1)
        position = position + #data
        return data
    end
    function source.read_all()
        local chunks = { buffer:sub(position) }
        while true do
            local data = handle.read(65536)
            if not data then
                break
            end
            chunks[#chunks + 1] = data
        end
        buffer, position = "", 1
        return table.concat(chunks)
    end

    local function check_open()
        if closed then
            error("attempt to use a closed file", 3)
        end
    end

    function file:read(...)
        check_open()
        return read_formats(source, ...)
    end
    function file:write(...)
        check_open()
        local err
        write_values(function(value)
            if not err then
                local ok, reason = handle.write(value)
                if not ok then
                    err = reason or "write failed"
                end
            end
        end, ...)
        if err then
            return nil, err
        end
        return self
    end
    function file:lines(...)
        local formats = table.pack(...)
        return function() return self:read(table.unpack(formats, 1, formats.n)) end
    end
    function file:seek(whence, offset)
        check_open()
        -- Data already read ahead counts as not read yet
        if (whence or "cur") == "cur" then
            offset = (offset or 0) - (#buffer - position + 1)
        end
        buffer, position = "", 1
        return handle.seek(whence or "cur", offset)
    end
    function file:close()
        if closed then
            return nil, "file already closed"
        end
        closed = true
        files[file] = "closed"
        return handle.close()
    end
    function file:flush() return self end
    function file:setvbuf() return true end
    return file
end

function io.open(path, mode)
    local handle, err = filesystem.open(path, mode or "r")
    if not handle then
        return nil, err
    end
    return file_object(handle)
end

function io.lines(path, ...)
    if path == nil then
        return io.stdin:lines(...)
    end
    local file = assert(io.open(path, "r"))
    local formats = table.pack(...)
    return function()
        local value = file:read(table.unpack(formats, 1, formats.n))
        if value == nil then
            file:close()
        end
        return value
    end
end

function io.write(...) return io.stdout:write(...) end
function io.read(...) return io.stdin:read(...) end
function io.close(file) return (file or io.stdout):close() end
function io.input() return io.stdin end
function io.output() return io.stdout end

function io.type(object)
    if object == io.stdin or object == io.stdout or object == io.stderr or files[object] == true then
        return "file"
    elseif files[object] == "closed" then
        return "closed file"
    end
    return nil
end

_G.print = function(...)
    local values = table.pack(...)
    local parts = {}
    for i = 1, values.n do
        parts[i] = tostring(values[i])
    end
    host.write(table.concat(parts, "\t") .. "\n")
end

return io
