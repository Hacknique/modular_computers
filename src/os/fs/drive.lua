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

-- The files on hard drives. A hard drive item has a drive id in its meta, and its files are
-- kept in mod storage under that id, so they move with the drive. Each drive has an index
-- ("drive:<id>") of its directories and file sizes, and one entry per file ("drive:<id>:<path>").
-- Indexes are kept in memory and saved every few seconds and when the server shuts down.

local drive = {}
modular_computers.os.fs.drive = drive

local storage = modular_computers.mod_storage
local find, sub, gsub, byte = string.find, string.sub, string.gsub, string.byte

-- Bytes that fit on a hard drive of each tier
drive.CAPACITY = { 1024 * 1024, 2 * 1024 * 1024, 4 * 1024 * 1024 }
drive.MAX_PATH = 256
drive.MAX_FILES = 4096

drive.SAVE_INTERVAL = 2

local indexes = {}
local unsaved = {}

local secure_random

-- Returns a new random drive id, formatted like a UUID
function drive.new_id()
    if secure_random == nil then
        local ok, generator = pcall(function() return SecureRandom() end)
        secure_random = ok and generator or false
    end
    local digits = {}
    if secure_random then
        local bytes = secure_random:next_bytes(16)
        for i = 1, 16 do
            digits[i] = string.format("%02x", string.byte(bytes, i))
        end
    else
        for i = 1, 32 do
            digits[i] = string.format("%x", math.random(0, 15))
        end
    end
    local id = table.concat(digits)
    return sub(id, 1, 8) .. "-" .. sub(id, 9, 12) .. "-" .. sub(id, 13, 16) .. "-" .. sub(id, 17, 20) .. "-"
        .. sub(id, 21)
end

local function index_key(id)
    return "drive:" .. id
end

local function file_key(id, path)
    return "drive:" .. id .. ":" .. path
end

local function load_index(id)
    local index = indexes[id]
    if not index then
        index = minetest.deserialize(storage:get_string(index_key(id))) or {}
        index.files = index.files or {}
        index.dirs = index.dirs or {}
        index.times = index.times or {}
        index.used = index.used or 0
        index.label = index.label or ""
        index.count = 0
        for _ in pairs(index.files) do
            index.count = index.count + 1
        end
        indexes[id] = index
    end
    return index
end

local function save_index(id)
    unsaved[id] = true
end

-- Saves the indexes that changed
function drive.save()
    for id in pairs(unsaved) do
        local index = indexes[id]
        storage:set_string(index_key(id), minetest.serialize({
            files = index.files, dirs = index.dirs, times = index.times, used = index.used, label = index.label,
        }))
    end
    unsaved = {}
end

local since_save = 0
minetest.register_globalstep(function(dtime)
    since_save = since_save + dtime
    if since_save >= drive.SAVE_INTERVAL then
        since_save = 0
        drive.save()
    end
end)
minetest.register_on_shutdown(drive.save)

-- Returns the absolute form of path, relative to directory cwd, or nil and an error
function drive.resolve(path, cwd)
    if type(path) ~= "string" then
        return nil, "bad path"
    end
    if #path > 4 * drive.MAX_PATH then
        return nil, "path too long"
    end
    if find(path, "[%z\1-\31]") then
        return nil, "bad path"
    end
    if byte(path, 1) ~= 47 then -- relative
        path = (cwd or "/") .. "/" .. path
    end
    local parts = {}
    for part in string.gmatch(path, "[^/]+") do
        if part == ".." then
            if #parts == 0 then
                return nil, "bad path"
            end
            table.remove(parts)
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    local result = "/" .. table.concat(parts, "/")
    if #result > drive.MAX_PATH then
        return nil, "path too long"
    end
    return result
end

-- Returns the directory holding path, and the name of path in it
function drive.split(path)
    local parent, name = string.match(path, "^(.*)/([^/]*)$")
    if not parent or parent == "" then
        parent = "/"
    end
    return parent, name
end

function drive.is_dir(id, path)
    return path == "/" or load_index(id).dirs[path] == true
end

function drive.is_file(id, path)
    return load_index(id).files[path] ~= nil
end

function drive.exists(id, path)
    return drive.is_dir(id, path) or drive.is_file(id, path)
end

function drive.size(id, path)
    return load_index(id).files[path] or 0
end

function drive.modified(id, path)
    return load_index(id).times[path] or 0
end

function drive.used(id)
    return load_index(id).used
end

function drive.get_label(id)
    return load_index(id).label
end

function drive.set_label(id, label)
    load_index(id).label = sub(label or "", 1, 32)
    save_index(id)
end

-- Returns the names in a directory, sorted, with a "/" after directories
function drive.list(id, path)
    if not drive.is_dir(id, path) then
        return nil, "no such directory"
    end
    local index = load_index(id)
    local prefix = path == "/" and "/" or path .. "/"
    local names = {}
    for dir in pairs(index.dirs) do
        if sub(dir, 1, #prefix) == prefix and not find(dir, "/", #prefix + 1, true) then
            table.insert(names, sub(dir, #prefix + 1) .. "/")
        end
    end
    for file in pairs(index.files) do
        if sub(file, 1, #prefix) == prefix and not find(file, "/", #prefix + 1, true) then
            table.insert(names, sub(file, #prefix + 1))
        end
    end
    table.sort(names)
    return names
end

-- Creates a directory and the directories above it
function drive.mkdir(id, path)
    if drive.is_file(id, path) then
        return nil, "a file with that name exists"
    end
    local index = load_index(id)
    local current = ""
    for part in string.gmatch(path, "[^/]+") do
        current = current .. "/" .. part
        if index.files[current] then
            return nil, "a file with that name exists"
        end
        index.dirs[current] = true
    end
    save_index(id)
    return true
end

function drive.read(id, path)
    if not drive.is_file(id, path) then
        return nil, "no such file"
    end
    return storage:get_string(file_key(id, path))
end

-- Writes (or with append, adds to) a file, whose directory must exist
function drive.write(id, path, content, capacity, append)
    local index = load_index(id)
    if path == "/" or index.dirs[path] then
        return nil, "is a directory"
    end
    if not drive.is_dir(id, (drive.split(path))) then
        return nil, "no such directory"
    end
    local old_size = index.files[path]
    if not old_size and index.count >= drive.MAX_FILES then
        return nil, "too many files"
    end
    if append and old_size then
        content = storage:get_string(file_key(id, path)) .. content
    end
    local used = index.used - (old_size or 0) + #content
    if used > capacity then
        return nil, "not enough space"
    end
    storage:set_string(file_key(id, path), content)
    if not old_size then
        index.count = index.count + 1
    end
    index.files[path] = #content
    index.times[path] = os.time()
    index.used = used
    save_index(id)
    return true
end

-- Removes a file, or a directory with everything in it
function drive.remove(id, path)
    if path == "/" then
        return nil, "can't remove the root directory"
    end
    local index = load_index(id)
    local function remove_file(file)
        index.used = index.used - index.files[file]
        index.count = index.count - 1
        index.files[file] = nil
        index.times[file] = nil
        storage:set_string(file_key(id, file), "")
    end
    if index.files[path] then
        remove_file(path)
    elseif index.dirs[path] then
        local prefix = path .. "/"
        local inside = {}
        for file in pairs(index.files) do
            if sub(file, 1, #prefix) == prefix then
                table.insert(inside, file)
            end
        end
        for _, file in ipairs(inside) do
            remove_file(file)
        end
        for dir in pairs(index.dirs) do
            if dir == path or sub(dir, 1, #prefix) == prefix then
                index.dirs[dir] = nil
            end
        end
    else
        return nil, "no such file or directory"
    end
    save_index(id)
    return true
end

-- Copies a file or directory to a path that doesn't exist yet
function drive.copy(id, from, to, capacity)
    if drive.exists(id, to) then
        return nil, "target exists"
    end
    if sub(to, 1, #from + 1) == from .. "/" then
        return nil, "can't copy a directory into itself"
    end
    if drive.is_file(id, from) then
        return drive.write(id, to, drive.read(id, from), capacity)
    elseif not drive.is_dir(id, from) then
        return nil, "no such file or directory"
    end
    local ok, err = drive.mkdir(id, to)
    if not ok then
        return nil, err
    end
    for _, name in ipairs(drive.list(id, from)) do
        local plain = gsub(name, "/$", "")
        ok, err = drive.copy(id, from .. "/" .. plain, to .. "/" .. plain, capacity)
        if not ok then
            return nil, err
        end
    end
    return true
end

function drive.rename(id, from, to)
    if from == to then
        return true
    end
    local index = load_index(id)
    local ok, err = drive.copy(id, from, to, index.used + drive.size(id, from) + 1024 * 1024 * 64)
    if not ok then
        return nil, err
    end
    return drive.remove(id, from)
end
