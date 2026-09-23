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

-- Commands for the files on the computer's hard drive. They use the drive through its
-- filesystem component, so they see the programs and libraries of the ROM in /bin and /lib.

local S = modular_computers.S
local command = modular_computers.command
local drive = modular_computers.os.fs.drive

local files = {}
modular_computers.os.files = files

-- Width that listings are wrapped at, so they fit on small screens
local LIST_WIDTH = 40

-- Wraps a command that works on the computer's files: fn(m, fs, ...) returns the output,
-- or raises an error that becomes the output
function files.command(description, fn)
    return {
        description = description,
        func = function(_, ...)
            local m = command.get_machine()
            if not m then
                return "", "", S("The computer is not running.") .. "\n", 0
            end
            local fs = m.components[m.drive]
            local methods = modular_computers.components.types.filesystem
            local calls = setmetatable({}, { __index = function(_, name)
                return function(...)
                    return methods[name](m, fs, ...)
                end
            end })
            local ok, output = pcall(fn, m, calls, ...)
            if not ok then
                return "", "", tostring(output) .. "\n", 0
            end
            return "", output or "", "", 0
        end,
    }
end

-- Returns the absolute path of path, relative to the working directory of machine m
function files.resolve(m, path)
    local resolved, err = drive.resolve(path, m.cwd)
    if not resolved then
        error(path .. ": " .. err, 0)
    end
    return resolved
end

local function name_of(path)
    return path:match("([^/]*)$")
end

-- Lays out names in columns
function files.columns(names)
    local width = 0
    for _, name in ipairs(names) do
        width = math.max(width, #name)
    end
    local per_row = math.max(math.floor((LIST_WIDTH + 2) / (width + 2)), 1)
    local lines, row = {}, {}
    for _, name in ipairs(names) do
        table.insert(row, name .. string.rep(" ", width - #name))
        if #row == per_row then
            table.insert(lines, (table.concat(row, "  "):gsub("%s+$", "")))
            row = {}
        end
    end
    if #row > 0 then
        table.insert(lines, (table.concat(row, "  "):gsub("%s+$", "")))
    end
    return #lines > 0 and table.concat(lines, "\n") .. "\n" or ""
end

-- Reads a file of the ROM or the hard drive
function files.read(m, path)
    local content = modular_computers.machine.ROM[path] or drive.read(m.drive, path)
    if not content then
        error(path .. ": no such file", 0)
    end
    return content
end

command.register("ls", files.command(S("List the files in a directory"), function(m, fs, path)
    local directory = files.resolve(m, path or ".")
    if not fs.isDirectory(directory) then
        if fs.exists(directory) then
            return name_of(directory) .. "\n"
        end
        error("ls: " .. (path or directory) .. ": no such file or directory", 0)
    end
    return files.columns(fs.list(directory))
end))

command.register("cd", files.command(S("Change the working directory"), function(m, fs, path)
    local directory = files.resolve(m, path or "/")
    if not fs.isDirectory(directory) then
        error("cd: " .. (path or directory) .. ": no such directory", 0)
    end
    m.cwd = directory
    minetest.get_meta(m.pos):set_string("cwd", directory)
end))

command.register("pwd", files.command(S("Show the working directory"), function(m)
    return m.cwd .. "\n"
end))

command.register("cat", files.command(S("Show the contents of files"), function(m, _, ...)
    local output = {}
    for _, path in ipairs({ ... }) do
        local content = files.read(m, files.resolve(m, path))
        if content ~= "" and content:sub(-1) ~= "\n" then
            content = content .. "\n"
        end
        table.insert(output, content)
    end
    return table.concat(output)
end))

command.register("mkdir", files.command(S("Make directories"), function(m, fs, ...)
    for _, path in ipairs({ ... }) do
        local directory = files.resolve(m, path)
        if fs.exists(directory) then
            error("mkdir: " .. path .. ": already exists", 0)
        end
        local ok, err = fs.makeDirectory(directory)
        if not ok then
            error("mkdir: " .. path .. ": " .. tostring(err), 0)
        end
    end
end))

command.register("rm", files.command(S("Remove files, or directories with -r"), function(m, fs, ...)
    local recursive = false
    for _, path in ipairs({ ... }) do
        if path == "-r" or path == "-rf" then
            recursive = true
        else
            local target = files.resolve(m, path)
            if not fs.exists(target) then
                error("rm: " .. path .. ": no such file or directory", 0)
            elseif fs.isDirectory(target) and not recursive then
                error("rm: " .. path .. ": is a directory (use rm -r)", 0)
            elseif not fs.remove(target) then
                error("rm: " .. path .. ": can't be removed", 0)
            end
        end
    end
end))

-- The path that from goes to when copied or moved to to: into to if it is a directory
local function destination(m, fs, from, to)
    local target = files.resolve(m, to)
    if fs.isDirectory(target) then
        target = (target == "/" and "" or target) .. "/" .. name_of(from)
    end
    return target
end

command.register("cp", files.command(S("Copy a file, or a directory with -r"), function(m, fs, ...)
    local args, recursive = {}, false
    for _, arg in ipairs({ ... }) do
        if arg == "-r" then
            recursive = true
        else
            table.insert(args, arg)
        end
    end
    if #args ~= 2 then
        error("usage: cp [-r] <from> <to>", 0)
    end
    local from = files.resolve(m, args[1])
    local to = destination(m, fs, from, args[2])
    if fs.isDirectory(from) then
        if not recursive then
            error("cp: " .. args[1] .. ": is a directory (use cp -r)", 0)
        end
        local ok, err = drive.copy(m.drive, from, to, fs.spaceTotal())
        if not ok then
            error("cp: " .. err, 0)
        end
        return
    end
    if modular_computers.machine.ROM[to] then
        error("cp: " .. args[2] .. ": file is read-only", 0)
    end
    local ok, err = drive.write(m.drive, to, files.read(m, from), fs.spaceTotal())
    if not ok then
        error("cp: " .. err, 0)
    end
end))

command.register("mv", files.command(S("Move or rename a file or directory"), function(m, fs, from, to)
    if not from or not to then
        error("usage: mv <from> <to>", 0)
    end
    local source = files.resolve(m, from)
    if not fs.exists(source) then
        error("mv: " .. from .. ": no such file or directory", 0)
    end
    if not fs.rename(source, destination(m, fs, source, to)) then
        error("mv: " .. from .. ": can't be moved there", 0)
    end
end))

command.register("df", files.command(S("Show how much of the hard drive is used"), function(_, fs)
    local used, total = fs.spaceUsed(), fs.spaceTotal()
    return string.format("%s: %d KiB of %d KiB used (%d%%)\n", fs.getLabel() or S("Hard Drive"),
        math.ceil(used / 1024), total / 1024, math.floor(used / total * 100))
end))

command.register("label", files.command(S("Show or set the label of the hard drive"), function(_, fs, ...)
    if select("#", ...) == 0 then
        return (fs.getLabel() or S("(no label)")) .. "\n"
    end
    fs.setLabel(table.concat({ ... }, " "))
end))
