-- The filesystem of the computer's hard drive, with paths relative to the working directory
local host = ...
local filesystem = {}

local function drive()
    return component.proxy(computer.getBootAddress())
end

local function absolute(path)
    local resolved, err = host.resolve(path)
    if not resolved then
        error(err, 3)
    end
    return resolved
end

function filesystem.canonical(path) return absolute(path) end
function filesystem.concat(...)
    local path = table.concat({ ... }, "/"):gsub("/+", "/")
    return path
end
function filesystem.path(path) return path:match("^(.*/)[^/]*/?$") or "" end
function filesystem.name(path) return path:match("([^/]*)/?$") end
function filesystem.segments(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts
end

function filesystem.exists(path) return drive().exists(absolute(path)) end
function filesystem.isDirectory(path) return drive().isDirectory(absolute(path)) end
function filesystem.size(path) return drive().size(absolute(path)) end
function filesystem.lastModified(path) return drive().lastModified(absolute(path)) end
function filesystem.makeDirectory(path) return drive().makeDirectory(absolute(path)) end
function filesystem.remove(path) return drive().remove(absolute(path)) end
function filesystem.rename(from, to) return drive().rename(absolute(from), absolute(to)) end
function filesystem.isLink() return false end
function filesystem.isAutorunEnabled() return true end
function filesystem.setAutorunEnabled() end
function filesystem.get() return drive(), "/" end

function filesystem.mounts()
    local done = false
    return function()
        if not done then
            done = true
            return drive(), "/"
        end
    end
end

function filesystem.list(path)
    local names, err = drive().list(absolute(path))
    if not names then
        return nil, err
    end
    local i = 0
    return function()
        i = i + 1
        return names[i]
    end
end

-- Opens a file; returns a handle with read, write, seek and close
function filesystem.open(path, mode)
    local fs = drive()
    local handle, err = fs.open(absolute(path), mode or "r")
    if not handle then
        return nil, err
    end
    local file = {}
    function file.read(count) return fs.read(handle, count or math.huge) end
    function file.write(value) return fs.write(handle, tostring(value)) end
    function file.seek(whence, offset) return fs.seek(handle, whence, offset) end
    function file.close() return fs.close(handle) end
    return file
end

function filesystem.copy(from, to)
    local input, err = filesystem.open(from, "r")
    if not input then
        return nil, err
    end
    local output
    output, err = filesystem.open(to, "w")
    if not output then
        input.close()
        return nil, err
    end
    repeat
        local data = input.read(8192)
        if data then
            output.write(data)
        end
    until not data
    input.close()
    return output.close()
end

return filesystem
