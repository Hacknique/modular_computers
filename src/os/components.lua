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

-- The components of a machine, which programs use through component.invoke: the computer,
-- its hard drive (filesystem), GPU, screen and redstone, and the cards in the tower. Each
-- method gets the machine, the component and the arguments from the program, which it
-- checks before using, since they come from untrusted code.

local drive = modular_computers.os.fs.drive

local components = {}
modular_computers.components = components

local gpu = {}
modular_computers.gpu = gpu

local floor, max, min = math.floor, math.max, math.min
local sub, find = string.sub, string.find
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local function check(value, expected, n)
    if type(value) ~= expected then
        error("bad argument #" .. n .. " (" .. expected .. " expected, got " .. type(value) .. ")", 0)
    end
    return value
end

local function optional(value, expected, n, default)
    if value == nil then
        return default
    end
    return check(value, expected, n)
end

local function integer(value, n)
    return floor(check(value, "number", n))
end

-- Methods of each component type, by name
components.types = {}

-- Adds a component to machine m
function components.add(m, address, component_type, slot, data)
    local component = data or {}
    component.type = component_type
    component.address = address
    component.slot = slot
    component.methods = components.types[component_type]
    m.components[address] = component
    return component
end

-- The computer ------------------------------------------------------------------------------

components.types.computer = {
    isRunning = function() return true end,
    beep = function() return true end,
    getDeviceInfo = function() return {} end,
}

-- Filesystem ----------------------------------------------------------------------------------

local MAX_HANDLES = 16

-- The programs and libraries that come with the computer show up in /bin and /lib of its
-- hard drive, and can't be changed
local function rom(path)
    return modular_computers.machine.ROM[path]
end

local function rom_names(path)
    local names = {}
    local prefix = path == "/" and "/" or path .. "/"
    for file in pairs(modular_computers.machine.ROM) do
        if sub(file, 1, #prefix) == prefix and not find(file, "/", #prefix + 1, true) then
            table.insert(names, sub(file, #prefix + 1))
        end
    end
    return names
end

local function read_only(path)
    return rom(path) ~= nil or path == "/bin" or path == "/lib"
end

local function fs_path(component, path)
    local resolved, err = drive.resolve(check(path, "string", 1), "/")
    if not resolved then
        error(err, 0)
    end
    return resolved
end

local function get_handle(m, handle)
    local open = m.handles[check(handle, "number", 1)]
    if not open then
        error("bad file descriptor", 0)
    end
    return open
end

local function flush_handle(component, open)
    if open.mode == "w" or open.mode == "a" then
        local ok, err = drive.write(component.id, open.path, table.concat(open.chunks), component.capacity,
            open.mode == "a")
        open.chunks = {}
        open.pending = 0
        open.mode = "a"
        return ok, err
    end
    return true
end

components.types.filesystem = {
    spaceUsed = function(_, c) return drive.used(c.id) end,
    spaceTotal = function(_, c) return c.capacity end,
    isReadOnly = function() return false end,
    getLabel = function(_, c)
        local label = drive.get_label(c.id)
        return label ~= "" and label or nil
    end,
    setLabel = function(_, c, label)
        drive.set_label(c.id, optional(label, "string", 1, ""))
        return drive.get_label(c.id)
    end,
    exists = function(_, c, path)
        path = fs_path(c, path)
        return rom(path) ~= nil or drive.exists(c.id, path)
    end,
    isDirectory = function(_, c, path) return drive.is_dir(c.id, fs_path(c, path)) end,
    size = function(_, c, path)
        path = fs_path(c, path)
        return rom(path) and #rom(path) or drive.size(c.id, path)
    end,
    lastModified = function(_, c, path) return drive.modified(c.id, fs_path(c, path)) * 1000 end,
    list = function(_, c, path)
        path = fs_path(c, path)
        local names, err = drive.list(c.id, path)
        if not names then
            return nil, err
        end
        local seen = {}
        for _, name in ipairs(names) do
            seen[name] = true
        end
        for _, name in ipairs(rom_names(path)) do
            if not seen[name] then
                table.insert(names, name)
            end
        end
        table.sort(names)
        return names
    end,
    makeDirectory = function(_, c, path)
        path = fs_path(c, path)
        if rom(path) or drive.exists(c.id, path) then
            return false
        end
        return drive.mkdir(c.id, path)
    end,
    remove = function(_, c, path)
        path = fs_path(c, path)
        if read_only(path) then
            return false
        end
        return drive.remove(c.id, path) or false
    end,
    rename = function(_, c, from, to)
        from, to = fs_path(c, from), fs_path(c, to)
        if read_only(from) or read_only(to) then
            return false
        end
        return drive.rename(c.id, from, to) or false
    end,
    open = function(m, c, path, mode)
        path = fs_path(c, path)
        mode = sub(optional(mode, "string", 2, "r"), 1, 1)
        if mode ~= "r" and read_only(path) then
            return nil, "file is read-only"
        end
        local count = 0
        for _ in pairs(m.handles) do
            count = count + 1
        end
        if count >= MAX_HANDLES then
            return nil, "too many open files"
        end
        local open = { path = path, mode = mode, position = 1, component = c, chunks = {}, pending = 0 }
        if mode == "r" then
            if not rom(path) then
                local size = drive.size(c.id, path)
                modular_computers.sandbox.allocate(size)
                modular_computers.sandbox.charge(size / 16)
            end
            local content = rom(path) or drive.read(c.id, path)
            if not content then
                return nil, path
            end
            open.content = content
        elseif mode == "w" or mode == "a" then
            if drive.is_dir(c.id, path) or not drive.is_dir(c.id, (drive.split(path))) then
                return nil, path
            end
            if mode == "w" then
                local ok, err = drive.write(c.id, path, "", c.capacity)
                if not ok then
                    return nil, err
                end
                open.mode = "a"
            end
        else
            return nil, "unsupported mode"
        end
        m.next_handle = (m.next_handle or 0) + 1
        m.handles[m.next_handle] = open
        return m.next_handle
    end,
    read = function(m, _, handle, count)
        local open = get_handle(m, handle)
        if not open.content then
            return nil, "file not open for reading"
        end
        count = min(integer(count, 2), 64 * 1024)
        if open.position > #open.content then
            return nil
        end
        local data = sub(open.content, open.position, open.position + count - 1)
        open.position = open.position + #data
        return data
    end,
    write = function(m, _, handle, value)
        local open = get_handle(m, handle)
        if open.content then
            return nil, "file not open for writing"
        end
        value = check(value, "string", 2)
        local component = open.component
        if drive.used(component.id) + open.pending + #value > component.capacity then
            return nil, "not enough space"
        end
        table.insert(open.chunks, value)
        open.pending = open.pending + #value
        if open.pending > 16 * 1024 then
            local ok, err = flush_handle(component, open)
            if not ok then
                return nil, err
            end
        end
        return true
    end,
    seek = function(m, _, handle, whence, offset)
        local open = get_handle(m, handle)
        if not open.content then
            return nil, "can't seek in a file open for writing"
        end
        whence = optional(whence, "string", 2, "cur")
        offset = floor(optional(offset, "number", 3, 0))
        local base = whence == "set" and 0 or whence == "end" and #open.content or open.position - 1
        open.position = max(base + offset, 0) + 1
        return open.position - 1
    end,
    close = function(m, _, handle)
        local open = get_handle(m, handle)
        m.handles[handle] = nil
        return flush_handle(open.component, open)
    end,
}

-- GPU and screen ------------------------------------------------------------------------------

-- The 16 colors of tier 2 GPUs, like OpenComputers
gpu.PALETTE = {
    0xFFFFFF, 0xFFCC33, 0xCC66CC, 0x6699FF, 0xFFFF33, 0x33CC33, 0xFF6699, 0x333333,
    0xCCCCCC, 0x336699, 0x9933CC, 0x333399, 0x663300, 0x336600, 0xFF3333, 0x000000,
}
-- Largest resolution and color depth of GPUs of each tier
gpu.MAX_RESOLUTION = { { 50, 16 }, { 80, 25 }, { 80, 25 } }
gpu.DEPTH = { 1, 4, 8 }

local function blank_row(width, fg, bg)
    local chars, fgs, bgs = {}, {}, {}
    for x = 1, width do
        chars[x], fgs[x], bgs[x] = " ", fg, bg
    end
    return { chars = chars, fg = fgs, bg = bgs }
end

-- Makes the GPU buffer of machine m width x height, keeping what fits
function gpu.resize(m, width, height)
    local screen = m.screen
    local rows = {}
    for y = 1, height do
        local row = blank_row(width, screen.foreground, screen.background)
        local old = screen.rows[y]
        if old then
            for x = 1, min(width, screen.width) do
                row.chars[x], row.fg[x], row.bg[x] = old.chars[x], old.fg[x], old.bg[x]
            end
        end
        rows[y] = row
    end
    screen.rows, screen.width, screen.height = rows, width, height
    screen.cursor_x = min(screen.cursor_x, width)
    screen.cursor_y = min(screen.cursor_y, height)
end

-- Blanks the GPU buffer of machine m and puts the cursor in the top left corner
function gpu.clear(m)
    local screen = m.screen
    for y = 1, screen.height do
        screen.rows[y] = blank_row(screen.width, screen.foreground, screen.background)
    end
    screen.cursor_x, screen.cursor_y = 1, 1
end

-- The resolution that fills the monitors on top of the tower
function gpu.default_resolution(m)
    local wall = modular_computers.display.get_wall(m.pos)
    local tier = m.gpu_tier
    local limit = gpu.MAX_RESOLUTION[tier]
    if not wall then
        return limit[1], limit[2]
    end
    local columns, rows = modular_computers.display.get_grid(wall, tier)
    return min(columns, limit[1]), min(rows, limit[2])
end

function gpu.init(m)
    m.screen = {
        rows = {}, width = 0, height = 0, cursor_x = 1, cursor_y = 1,
        foreground = 0xFFFFFF, background = 0x000000, mode = "text",
        palette = table.copy(gpu.PALETTE), depth = gpu.DEPTH[m.gpu_tier],
    }
    local width, height = gpu.default_resolution(m)
    gpu.resize(m, width, height)
end

-- Follows the size of the monitors, until a program sets a resolution itself
function gpu.check_resolution(m)
    if m.screen and not m.screen.explicit then
        local width, height = gpu.default_resolution(m)
        if width ~= m.screen.width or height ~= m.screen.height then
            gpu.resize(m, width, height)
        end
    end
end

local function luminance(color)
    return (floor(color / 65536) % 256) * 0.299 + (floor(color / 256) % 256) * 0.587 + (color % 256) * 0.114
end

-- The color a GPU shows for color (0xRRGGBB), given its depth
function gpu.map_color(m, color)
    color = floor(color) % 0x1000000
    local depth = m.screen.depth
    if depth == 1 then
        return luminance(color) >= 64 and 0xFFFFFF or 0x000000
    elseif depth == 4 then
        local best, best_distance = 0, math.huge
        for _, entry in ipairs(m.screen.palette) do
            local distance = 0
            for shift = 0, 2 do
                local a = floor(color / 256 ^ shift) % 256
                local b = floor(entry / 256 ^ shift) % 256
                distance = distance + (a - b) ^ 2
            end
            if distance < best_distance then
                best, best_distance = entry, distance
            end
        end
        return best
    end
    return color
end

local function drawing(m)
    m.screen.mode = "graphics"
    m.dirty = true
    modular_computers.machine.drew(m)
end

local function set_cell(screen, x, y, character)
    local row = screen.rows[y]
    if row and x >= 1 and x <= screen.width then
        row.chars[x], row.fg[x], row.bg[x] = character, screen.foreground, screen.background
    end
end

local function scroll(screen)
    table.remove(screen.rows, 1)
    table.insert(screen.rows, blank_row(screen.width, screen.foreground, screen.background))
end

-- Writes terminal output onto the GPU buffer at the cursor, wrapping and scrolling
function gpu.write(m, text)
    local screen = m.screen
    for character in string.gmatch(text, UTF8_CHAR) do
        if character == "\n" then
            screen.cursor_x = 1
            screen.cursor_y = screen.cursor_y + 1
        elseif character ~= "\r" then
            if screen.cursor_x > screen.width then
                screen.cursor_x = 1
                screen.cursor_y = screen.cursor_y + 1
            end
            if screen.cursor_y > screen.height then
                scroll(screen)
                screen.cursor_y = screen.height
            end
            set_cell(screen, screen.cursor_x, screen.cursor_y, character)
            screen.cursor_x = screen.cursor_x + 1
        end
        if screen.cursor_y > screen.height then
            scroll(screen)
            screen.cursor_y = screen.height
        end
    end
    m.dirty = true
end

local function get_color(m, which)
    local color = m.screen[which]
    for index, entry in ipairs(m.screen.palette) do
        if entry == color and m.screen.depth > 1 then
            return color, index - 1
        end
    end
    return color
end

local function set_color(m, which, color, is_palette_index)
    color = integer(color, 1)
    local old, old_index = get_color(m, which)
    if is_palette_index then
        if m.screen.depth == 1 then
            error("palette not available", 0)
        end
        color = m.screen.palette[color + 1] or error("invalid palette index", 0)
    end
    m.screen[which] = gpu.map_color(m, color)
    return old, old_index
end

components.types.gpu = {
    bind = function() return true end,
    getScreen = function(m) return m.screen_address end,
    getResolution = function(m) return m.screen.width, m.screen.height end,
    setResolution = function(m, _, width, height)
        width, height = integer(width, 1), integer(height, 2)
        local limit = gpu.MAX_RESOLUTION[m.gpu_tier]
        if width < 1 or height < 1 or width > limit[1] or height > limit[2] then
            error("unsupported resolution", 0)
        end
        local changed = width ~= m.screen.width or height ~= m.screen.height
        m.screen.explicit = true
        gpu.resize(m, width, height)
        drawing(m)
        return changed
    end,
    maxResolution = function(m)
        local limit = gpu.MAX_RESOLUTION[m.gpu_tier]
        return limit[1], limit[2]
    end,
    getViewport = function(m) return m.screen.width, m.screen.height end,
    getDepth = function(m) return m.screen.depth end,
    maxDepth = function(m) return gpu.DEPTH[m.gpu_tier] end,
    setDepth = function(m) return m.screen.depth end,
    getForeground = function(m) return get_color(m, "foreground") end,
    getBackground = function(m) return get_color(m, "background") end,
    setForeground = function(m, _, color, is_palette_index)
        return set_color(m, "foreground", color, is_palette_index)
    end,
    setBackground = function(m, _, color, is_palette_index)
        return set_color(m, "background", color, is_palette_index)
    end,
    getPaletteColor = function(m, _, index)
        return m.screen.palette[integer(index, 1) + 1] or error("invalid palette index", 0)
    end,
    setPaletteColor = function(m, _, index, color)
        index = integer(index, 1)
        local old = m.screen.palette[index + 1] or error("invalid palette index", 0)
        m.screen.palette[index + 1] = integer(color, 2) % 0x1000000
        return old
    end,
    set = function(m, _, x, y, value, vertical)
        x, y = integer(x, 1), integer(y, 2)
        value = check(value, "string", 3)
        local screen = m.screen
        for character in string.gmatch(sub(value, 1, 4096), UTF8_CHAR) do
            set_cell(screen, x, y, character)
            if vertical then
                y = y + 1
            else
                x = x + 1
            end
        end
        drawing(m)
        return true
    end,
    get = function(m, _, x, y)
        x, y = integer(x, 1), integer(y, 2)
        local row = m.screen.rows[y]
        if not row or x < 1 or x > m.screen.width then
            error("index out of bounds", 0)
        end
        return row.chars[x], row.fg[x], row.bg[x]
    end,
    fill = function(m, _, x, y, width, height, character)
        x, y, width, height = integer(x, 1), integer(y, 2), integer(width, 3), integer(height, 4)
        character = check(character, "string", 5)
        character = string.match(character, UTF8_CHAR) or " "
        local screen = m.screen
        for row = max(y, 1), min(y + height - 1, screen.height) do
            for column = max(x, 1), min(x + width - 1, screen.width) do
                set_cell(screen, column, row, character)
            end
        end
        drawing(m)
        return true
    end,
    copy = function(m, _, x, y, width, height, tx, ty)
        x, y, width, height = integer(x, 1), integer(y, 2), integer(width, 3), integer(height, 4)
        tx, ty = integer(tx, 5), integer(ty, 6)
        local screen = m.screen
        local cells = {}
        for row = max(y, 1), min(y + height - 1, screen.height) do
            local source = screen.rows[row]
            for column = max(x, 1), min(x + width - 1, screen.width) do
                table.insert(cells,
                    { column + tx, row + ty, source.chars[column], source.fg[column], source.bg[column] })
            end
        end
        for _, cell in ipairs(cells) do
            local target = screen.rows[cell[2]]
            if target and cell[1] >= 1 and cell[1] <= screen.width then
                target.chars[cell[1]], target.fg[cell[1]], target.bg[cell[1]] = cell[3], cell[4], cell[5]
            end
        end
        drawing(m)
        return true
    end,
}

-- Programs move the cursor of terminal output drawn on the GPU buffer through the term library
components.types.gpu.getCursor = function(m) return m.screen.cursor_x, m.screen.cursor_y end
components.types.gpu.setCursor = function(m, _, x, y)
    m.screen.cursor_x = max(1, integer(x, 1))
    m.screen.cursor_y = max(1, integer(y, 2))
    return true
end

components.types.screen = {
    isOn = function() return true end,
    turnOn = function() return false end,
    turnOff = function() return false end,
    getAspectRatio = function(m)
        local wall = modular_computers.display.get_wall(m.pos)
        if not wall then
            return 1, 1
        end
        return wall.width, wall.height
    end,
    getKeyboards = function() return {} end,
}

-- Redstone ------------------------------------------------------------------------------------

-- OpenComputers numbers sides from 0: bottom, top, back, front, right, left
components.SIDES = { [0] = "bottom", "top", "back", "front", "right", "left" }
local SIDE_NUMBERS = {}
for number, side in pairs(components.SIDES) do
    SIDE_NUMBERS[side] = number
end

local function side_name(side)
    if type(side) == "number" then
        return components.SIDES[floor(side)] or error("invalid side", 0)
    elseif type(side) == "string" and SIDE_NUMBERS[side] then
        return side
    end
    error("invalid side", 0)
end

local function all_sides(fn)
    local result = {}
    for number, side in pairs(components.SIDES) do
        result[number] = fn(side)
    end
    return result
end

components.types.redstone = {
    getInput = function(m, _, side)
        local redstone = modular_computers.redstone
        if side == nil then
            return all_sides(function(name) return redstone.get_input(m.pos, name) end)
        end
        return redstone.get_input(m.pos, side_name(side))
    end,
    getOutput = function(m, _, side)
        local redstone = modular_computers.redstone
        if side == nil then
            return all_sides(function(name) return redstone.get_output(m.pos, name) and 15 or 0 end)
        end
        return redstone.get_output(m.pos, side_name(side)) and 15 or 0
    end,
    setOutput = function(m, _, side, value)
        local redstone = modular_computers.redstone
        side = side_name(side)
        local old = redstone.get_output(m.pos, side) and 15 or 0
        local on = type(value) == "boolean" and value or (type(value) == "number" and value > 0)
        redstone.set_output(m.pos, side, on)
        return old
    end,
}

-- Tells the programs of machine m that the redstone input on a side changed
function components.redstone_changed(m, side, old, new)
    modular_computers.machine.push_signal(m, "redstone_changed", m.redstone_address, SIDE_NUMBERS[side], old, new)
end

-- Machine setup -----------------------------------------------------------------------------

-- Gives an item in a slot of the tower an id in its meta, if it has none, and returns the id
local function item_id(m, list, index, field)
    local inv = minetest.get_meta(m.pos):get_inventory()
    local stack = inv:get_stack(list, index)
    local id = stack:get_meta():get_string(field)
    if id == "" then
        id = drive.new_id()
        stack:get_meta():set_string(field, id)
        inv:set_stack(list, index, stack)
        modular_computers.computer.save_parts(m.pos)
    end
    return id
end

-- Cards add components through these, by card type: fn(m, address, slot, card)
components.cards = {}

local function remove_component(m, address)
    local component = m.components[address]
    if component and component.close then
        component.close(m, component)
    end
    m.components[address] = nil
end

-- Adds and removes the components of the cards in the tower, after they changed.
-- A running program is told with component_added and component_removed signals.
function components.update_cards(m, quiet)
    local hardware = modular_computers.hardware
    local inv = minetest.get_meta(m.pos):get_inventory()
    local present = {}
    for index = 1, inv:get_size("cards") do
        local card = hardware.get_card(inv:get_stack("cards", index))
        if card and components.cards[card.type] then
            local address = item_id(m, "cards", index, "address")
            present[address] = true
            if not m.components[address] then
                components.cards[card.type](m, address, index + 1, card)
                m.components[address].card = true
                if not quiet then
                    modular_computers.machine.push_signal(m, "component_added", address, m.components[address].type)
                end
            end
        end
    end
    for address, component in pairs(m.components) do
        if component.card and not present[address] then
            remove_component(m, address)
            modular_computers.machine.push_signal(m, "component_removed", address, component.type)
        end
    end
end

-- Creates the components of machine m from the parts in its tower
function components.build(m)
    local hardware = modular_computers.hardware
    local inv = minetest.get_meta(m.pos):get_inventory()
    m.components = {}
    m.handles = {}
    m.gpu_tier = math.max(hardware.get_tier(inv:get_stack("gpu", 1), "gpu"), 1)

    components.add(m, m.address, "computer")

    local hdd_tier = hardware.get_tier(inv:get_stack("hdd", 1), "hdd")
    m.drive = item_id(m, "hdd", 1, "drive_id")
    components.add(m, m.drive, "filesystem", 0, { id = m.drive, capacity = drive.CAPACITY[math.max(hdd_tier, 1)] })

    components.add(m, modular_computers.machine.derive_address(m.address .. ":gpu"), "gpu", 1)
    m.screen_address = modular_computers.machine.derive_address(m.address .. ":screen")
    components.add(m, m.screen_address, "screen")
    m.redstone_address = modular_computers.machine.derive_address(m.address .. ":redstone")
    components.add(m, m.redstone_address, "redstone")
    gpu.init(m)
    components.update_cards(m, true)
end

-- Closes the open files of machine m, saving what was written
function components.close(m)
    for handle, open in pairs(m.handles or {}) do
        flush_handle(open.component, open)
        m.handles[handle] = nil
    end
    for _, component in pairs(m.components or {}) do
        if component.close then
            component.close(m, component)
        end
    end
end
