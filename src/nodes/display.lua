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

-- Shows a computer's terminal on the monitors above its tower.
--
-- The monitor on top of a tower is the bottom corner of a screen: monitors beside it that
-- face the same way, and full rows of monitors above them, join it into one screen of up
-- to MAX_WIDTH x MAX_HEIGHT monitors. An entity in front of the monitors shows the text as
-- a [combine of font glyph textures. The GPU tier sets how many rows of text there are, so
-- the text grows with the screen.

local terminal = modular_computers.terminal
local hardware = modular_computers.hardware

modular_computers.display = {}
local display = modular_computers.display

display.MAX_WIDTH = 8
display.MAX_HEIGHT = 6

local SCREEN_ENTITY = "modular_computers:screen"
local BEZEL = 2 / 32 -- border around the screen of the monitor texture
local DEPTH = 0.51 -- distance of the text in front of the monitor's center
local CELL_WIDTH, CELL_HEIGHT = 6, 10
local PADDING = 2
local MAX_COLUMNS = 48
local TEXT_COLOR = "#D0D0D0"
local NO_SIGNAL_COLOR = "#707070"
local CURSOR = "\127" -- the font has a block cursor in place of DEL
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local UP = vector.new(0, 1, 0)

-- Screen entities by tower position hash
local screens = {}

local function is_tower(pos)
    return minetest.get_item_group(minetest.get_node(pos).name, "modular_computer_tower") > 0
end

local function is_monitor(pos, param2)
    local node = minetest.get_node(pos)
    return minetest.get_item_group(node.name, "modular_computer_monitor") > 0 and node.param2 == param2
end

-- Returns the screen whose bottom corner is the monitor on top of the tower at tower_pos, or nil:
-- { anchor = monitor on the tower, back = direction into the screen, right = the viewer's right,
--   left = monitors left of the anchor, right_count = monitors right of it, width, height }
function display.get_wall(tower_pos)
    local anchor = vector.add(tower_pos, UP)
    local node = minetest.get_node(anchor)
    if minetest.get_item_group(node.name, "modular_computer_monitor") == 0 or node.param2 > 3 then
        return nil
    end
    local param2 = node.param2
    local back = minetest.facedir_to_dir(param2)
    local right = vector.new(back.z, 0, -back.x)

    -- Counts the monitors in direction dir that join this screen. When another tower's monitor
    -- is in the same row, the monitors between the two are shared out, the nearer ones to each
    -- tower, and win_ties gives this tower the middle one.
    local function reach(dir, win_ties)
        for count = 1, 2 * display.MAX_WIDTH do
            local pos = vector.add(anchor, vector.multiply(dir, count))
            if not is_monitor(pos, param2) then
                return count - 1
            elseif is_tower(vector.subtract(pos, UP)) then
                return win_ties and math.ceil((count - 1) / 2) or math.floor((count - 1) / 2)
            end
        end
        return 2 * display.MAX_WIDTH
    end

    local left = math.min(reach(vector.multiply(right, -1), false), display.MAX_WIDTH - 1)
    local right_count = math.min(reach(right, true), display.MAX_WIDTH - 1 - left)

    local height = 1
    while height < display.MAX_HEIGHT do
        local row = vector.add(anchor, vector.multiply(UP, height))
        for offset = -left, right_count do
            if not is_monitor(vector.add(row, vector.multiply(right, offset)), param2) then
                return { anchor = anchor, back = back, right = right, left = left,
                    right_count = right_count, width = left + right_count + 1, height = height }
            end
        end
        height = height + 1
    end
    return { anchor = anchor, back = back, right = right, left = left,
        right_count = right_count, width = left + right_count + 1, height = height }
end

local function wall_contains(wall, pos)
    local offset = vector.subtract(pos, wall.anchor)
    local across = offset.x * wall.right.x + offset.z * wall.right.z
    local depth = offset.x * wall.back.x + offset.z * wall.back.z
    return depth == 0 and across >= -wall.left and across <= wall.right_count
        and offset.y >= 0 and offset.y < wall.height
end

local tower_names
-- Towers close enough to pos to have it in their screen
local function find_towers(pos)
    if not tower_names then
        tower_names = {}
        for name in pairs(minetest.registered_nodes) do
            if minetest.get_item_group(name, "modular_computer_tower") > 0 then
                table.insert(tower_names, name)
            end
        end
    end
    return minetest.find_nodes_in_area(
        vector.add(pos, vector.new(-display.MAX_WIDTH, -display.MAX_HEIGHT, -display.MAX_WIDTH)),
        vector.add(pos, vector.new(display.MAX_WIDTH, 0, display.MAX_WIDTH)),
        tower_names)
end

-- Returns the position of the tower whose screen the monitor at pos is part of, or nil
function display.find_tower(pos)
    for _, tower_pos in ipairs(find_towers(pos)) do
        local wall = display.get_wall(tower_pos)
        if wall and wall_contains(wall, pos) then
            return tower_pos
        end
    end
end

-- Returns the columns and rows of text on a screen, for a GPU of the given tier
function display.get_grid(wall, gpu_tier)
    local width = wall.width - 2 * BEZEL
    local height = wall.height - 2 * BEZEL
    local rows = hardware.GPU_ROWS[gpu_tier] or hardware.GPU_ROWS[1]
    local columns = math.floor(rows * CELL_HEIGHT / CELL_WIDTH * width / height)
    if columns > MAX_COLUMNS then
        columns = MAX_COLUMNS
        rows = math.max(math.floor(columns * CELL_WIDTH / CELL_HEIGHT * height / width), 1)
    end
    return columns, rows
end

-- Returns a texture showing lines of text in a grid of columns x rows
function display.render(lines, columns, rows, color)
    local size = (columns * CELL_WIDTH + 2 * PADDING) .. "x" .. (rows * CELL_HEIGHT + 2 * PADDING)
    local glyphs = {}
    for row = 1, math.min(#lines, rows) do
        local column = 0
        for char in string.gmatch(lines[row], UTF8_CHAR) do
            if column == columns then
                break
            end
            local code = #char == 1 and string.byte(char) or 63 -- "?" for characters not in the font
            if code > 32 and code <= 127 then
                table.insert(glyphs, string.format("%d,%d=modular_computers_font_%02x.png",
                    PADDING + column * CELL_WIDTH, PADDING + (row - 1) * CELL_HEIGHT, code))
            end
            column = column + 1
        end
    end
    local parts = #glyphs > 0 and (":" .. table.concat(glyphs, ":")) or ""
    return "[fill:" .. size .. ":#000000^[combine:" .. size .. parts .. "^[multiply:" .. color
end

local function screen_texture(tower_pos, wall)
    local inv = minetest.get_meta(tower_pos):get_inventory()
    local gpu_tier = hardware.get_tier(inv:get_stack("gpu", 1), "gpu")
    local columns, rows = display.get_grid(wall, math.max(gpu_tier, 1))

    if not modular_computers.computer.is_running(tower_pos) then
        local text = "NO SIGNAL"
        local lines = {}
        for _ = 1, math.ceil(rows / 2) - 1 do
            table.insert(lines, "")
        end
        table.insert(lines, string.rep(" ", math.max(math.floor((columns - #text) / 2), 0)) .. text)
        return display.render(lines, columns, rows, NO_SIGNAL_COLOR)
    end

    local text = terminal.get_text(minetest.get_meta(tower_pos))
    local lines = terminal.get_rows(text, "", columns)
    table.insert(lines, terminal.PROMPT .. " " .. CURSOR)
    local visible = {}
    for index = math.max(#lines - rows + 1, 1), #lines do
        table.insert(visible, lines[index])
    end
    return display.render(visible, columns, rows, TEXT_COLOR)
end

function display.remove(tower_pos)
    local key = minetest.hash_node_position(tower_pos)
    if screens[key] and screens[key]:get_pos() then
        screens[key]:remove()
    end
    screens[key] = nil
end

-- Creates, updates or removes the screen of the tower at tower_pos
function display.update(tower_pos)
    if minetest.load_area then
        minetest.load_area(vector.add(tower_pos, vector.new(-display.MAX_WIDTH, 0, -display.MAX_WIDTH)),
            vector.add(tower_pos, vector.new(display.MAX_WIDTH, display.MAX_HEIGHT, display.MAX_WIDTH)))
    end
    local wall = is_tower(tower_pos) and display.get_wall(tower_pos)
    if not wall then
        display.remove(tower_pos)
        return
    end

    local key = minetest.hash_node_position(tower_pos)
    local screen = screens[key]
    local center = vector.add(wall.anchor, vector.add(
        vector.multiply(wall.right, (wall.right_count - wall.left) / 2),
        vector.add(vector.multiply(UP, (wall.height - 1) / 2), vector.multiply(wall.back, -DEPTH))))
    if screen and screen:get_pos() then
        if not vector.equals(screen:get_pos(), center) then
            screen:set_pos(center)
        end
    else
        screen = minetest.add_entity(center, SCREEN_ENTITY, minetest.pos_to_string(tower_pos))
        if not screen then
            return
        end
        screens[key] = screen
    end

    local entity = screen:get_luaentity()
    if not entity then
        return
    end
    local yaw = minetest.dir_to_yaw(vector.multiply(wall.back, -1))
    if entity._yaw ~= yaw then
        screen:set_yaw(yaw)
        entity._yaw = yaw
    end
    local size = { x = wall.width - 2 * BEZEL, y = wall.height - 2 * BEZEL }
    local texture = screen_texture(tower_pos, wall)
    if entity._texture ~= texture or entity._width ~= size.x or entity._height ~= size.y then
        screen:set_properties({ visual_size = size, textures = { texture, "blank.png" } })
        entity._texture, entity._width, entity._height = texture, size.x, size.y
    end
end

-- Updates the screens of towers near pos, after a monitor there was placed or removed
function display.update_near(pos)
    for _, tower_pos in ipairs(find_towers(pos)) do
        display.update(tower_pos)
    end
end

minetest.register_entity(SCREEN_ENTITY, {
    initial_properties = {
        visual = "upright_sprite",
        textures = { "blank.png", "blank.png" },
        physical = false,
        collide_with_objects = false,
        pointable = false,
        glow = -1,
        static_save = true,
    },
    on_activate = function(self, staticdata)
        local tower_pos = minetest.string_to_pos(staticdata)
        if not tower_pos then
            self.object:remove()
            return
        end
        self._tower = tower_pos
        self.object:set_armor_groups({ immortal = 1 })

        -- A screen left behind in an unloaded area may have been replaced meanwhile
        local key = minetest.hash_node_position(tower_pos)
        local current = screens[key]
        if current and current:get_pos() and current ~= self.object then
            self.object:remove()
            return
        end
        screens[key] = self.object
        minetest.after(0, function()
            if self.object:get_pos() and minetest.get_node_or_nil(tower_pos) then
                display.update(tower_pos)
            end
        end)
    end,
    get_staticdata = function(self)
        return self._tower and minetest.pos_to_string(self._tower) or ""
    end,
})

minetest.register_lbm({
    label = "Show the screens of computer towers",
    name = "modular_computers:show_tower_screens",
    nodenames = { "group:modular_computer_tower" },
    run_at_every_load = true,
    action = function(pos)
        display.update(pos)
    end,
})

minetest.register_lbm({
    label = "Show the screens of monitors on computer towers",
    name = "modular_computers:show_monitor_screens",
    nodenames = { "group:modular_computer_monitor" },
    run_at_every_load = true,
    action = function(pos)
        local below = vector.subtract(pos, UP)
        if is_tower(below) then
            display.update(below)
        end
    end,
})
