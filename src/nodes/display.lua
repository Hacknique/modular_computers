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
-- to MAX_WIDTH x MAX_HEIGHT monitors. The GPU tier sets how many rows of text there are, so
-- the text grows with the screen. While a program draws with the GPU, the screen shows the
-- GPU's buffer, in color, instead of the terminal.
--
-- Each row of text is an entity in front of the monitors, showing the row as a [combine of
-- font glyph textures. Clients keep every texture they are sent until they leave, and a row's
-- texture only depends on what it shows, so text that scrolls up reuses the textures it had.
-- Screens are only shown near players, and not saved with the map.

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
-- Screens farther than this from all players are not shown
display.VIEW_DISTANCE = 96

local UP = vector.new(0, 1, 0)

-- Screen entities by tower position hash, and row
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

local function glyph_code(char)
    return #char == 1 and string.byte(char) or 63 -- "?" for characters not in the font
end

-- Returns the texture of a row of text, columns characters wide
function display.render_line(line, columns, color)
    local size = (columns * CELL_WIDTH + 2 * PADDING) .. "x" .. CELL_HEIGHT
    local glyphs = {}
    local column = 0
    for char in string.gmatch(line, UTF8_CHAR) do
        if column == columns then
            break
        end
        local code = glyph_code(char)
        if code > 32 and code <= 127 then
            table.insert(glyphs, string.format("%d,0=modular_computers_font_%02x.png",
                PADDING + column * CELL_WIDTH, code))
        end
        column = column + 1
    end
    if #glyphs == 0 then
        return "[fill:" .. size .. ":#000000"
    end
    return "[fill:" .. size .. ":#000000^[combine:" .. size .. ":" .. table.concat(glyphs, ":") .. "^[multiply:"
        .. color
end

-- Returns the texture of row y of a GPU buffer: { width, height, rows = { { chars, fg, bg } } }
-- with colors as 0xRRGGBB numbers
function display.render_cells(screen, y)
    local width = screen.width
    local row = screen.rows[y]
    local size = (width * CELL_WIDTH + 2 * PADDING) .. "x" .. CELL_HEIGHT
    local parts = { "[fill:" .. size .. ":#000000" }
    -- Backgrounds, a fill for each run of cells of one color
    local run_start, run_color = 1, row.bg[1]
    for x = 2, width + 1 do
        local bg = row.bg[x]
        if bg ~= run_color then
            if run_color ~= 0 then
                table.insert(parts, string.format("^[fill:%dx%d:%d,0:#%06X", (x - run_start) * CELL_WIDTH,
                    CELL_HEIGHT, PADDING + (run_start - 1) * CELL_WIDTH, run_color))
            end
            run_start, run_color = x, bg
        end
    end
    -- Characters, a layer for each color
    local layers, colors = {}, {}
    for x = 1, width do
        local code = glyph_code(row.chars[x])
        local color = row.fg[x]
        -- Characters in the color of their background can't be seen
        if code > 32 and code <= 127 and color ~= row.bg[x] then
            if not layers[color] then
                layers[color] = {}
                table.insert(colors, color)
            end
            table.insert(layers[color], string.format("%d,0=modular_computers_font_%02x.png",
                PADDING + (x - 1) * CELL_WIDTH, code))
        end
    end
    for _, color in ipairs(colors) do
        table.insert(parts, "^([combine:" .. size .. ":" .. table.concat(layers[color], ":") .. "^[multiply:"
            .. string.format("#%06X", color) .. ")")
    end
    return table.concat(parts)
end

-- Returns the textures of the rows of the screen of the tower at tower_pos
local function screen_rows(tower_pos, wall)
    local textures = {}
    local m = modular_computers.machine.get(tower_pos)
    if m and m.screen and m.screen.mode == "graphics" then
        for y = 1, m.screen.height do
            textures[y] = display.render_cells(m.screen, y)
        end
        return textures
    end

    local inv = minetest.get_meta(tower_pos):get_inventory()
    local gpu_tier = hardware.get_tier(inv:get_stack("gpu", 1), "gpu")
    local columns, rows = display.get_grid(wall, math.max(gpu_tier, 1))
    local lines, color = {}, TEXT_COLOR

    if not modular_computers.computer.is_running(tower_pos) then
        local text = "NO SIGNAL"
        lines[math.ceil(rows / 2)] = string.rep(" ", math.max(math.floor((columns - #text) / 2), 0)) .. text
        color = NO_SIGNAL_COLOR
    else
        local text = terminal.get_text(minetest.get_meta(tower_pos))
        local all = terminal.get_rows(text, "", columns)
        if m and m.foreground then
            -- The cursor follows what the program wrote, like its own prompt
            if text == "" or text:sub(-1) == "\n" then
                table.insert(all, CURSOR)
            else
                all[#all] = all[#all] .. CURSOR
            end
        else
            table.insert(all, terminal.PROMPT .. " " .. CURSOR)
        end
        for index = math.max(#all - rows + 1, 1), #all do
            table.insert(lines, all[index])
        end
    end
    for row = 1, rows do
        textures[row] = display.render_line(lines[row] or "", columns, color)
    end
    return textures
end

local function screen_center(wall)
    return vector.add(wall.anchor, vector.add(
        vector.multiply(wall.right, (wall.right_count - wall.left) / 2),
        vector.add(vector.multiply(UP, (wall.height - 1) / 2), vector.multiply(wall.back, -DEPTH))))
end

-- Returns the cell (x, y) that player points at on the screen of the tower at tower_pos,
-- when the screen shows width x height cells, or nil
function display.pointed_cell(tower_pos, player, width, height)
    local wall = display.get_wall(tower_pos)
    if not wall then
        return nil
    end
    local eye = vector.add(player:get_pos(), vector.new(0, player:get_properties().eye_height or 1.625, 0))
    local dir = player:get_look_dir()
    local toward = vector.dot(dir, wall.back)
    if toward <= 0 then
        return nil
    end
    local center = screen_center(wall)
    local distance = vector.dot(vector.subtract(center, eye), wall.back) / toward
    if distance <= 0 then
        return nil
    end
    local offset = vector.subtract(vector.add(eye, vector.multiply(dir, distance)), center)
    local u = vector.dot(offset, wall.right) / (wall.width - 2 * BEZEL) + 0.5
    local v = 0.5 - offset.y / (wall.height - 2 * BEZEL)
    if u < 0 or u >= 1 or v < 0 or v >= 1 then
        return nil
    end
    return math.floor(u * width) + 1, math.floor(v * height) + 1
end

-- Returns the row entities of the screen of the tower at tower_pos, by row
function display.get_rows(tower_pos)
    local rows = {}
    for row, object in pairs(screens[minetest.hash_node_position(tower_pos)] or {}) do
        if object:get_pos() then
            rows[row] = object
        end
    end
    return rows
end

function display.remove(tower_pos)
    local key = minetest.hash_node_position(tower_pos)
    for _, object in pairs(screens[key] or {}) do
        if object:get_pos() then
            object:remove()
        end
    end
    screens[key] = nil
end

-- Whether a player is near enough to see the screen of the tower at pos
function display.is_seen(pos)
    for _, player in ipairs(minetest.get_connected_players()) do
        if vector.distance(player:get_pos(), pos) <= display.VIEW_DISTANCE then
            return true
        end
    end
    return false
end

-- Creates, updates or removes the screen of the tower at tower_pos
function display.update(tower_pos)
    if minetest.load_area then
        minetest.load_area(vector.add(tower_pos, vector.new(-display.MAX_WIDTH, 0, -display.MAX_WIDTH)),
            vector.add(tower_pos, vector.new(display.MAX_WIDTH, display.MAX_HEIGHT, display.MAX_WIDTH)))
    end
    local wall = is_tower(tower_pos) and display.get_wall(tower_pos)
    local m = modular_computers.machine.get(tower_pos)
    if m and m.screen then
        -- The GPU follows the size of the screen
        modular_computers.gpu.check_resolution(m)
    end
    if not wall or not display.is_seen(tower_pos) then
        display.remove(tower_pos)
        return
    end

    local key = minetest.hash_node_position(tower_pos)
    screens[key] = screens[key] or {}
    local objects = screens[key]
    local textures = screen_rows(tower_pos, wall)
    local count = #textures
    local size = { x = wall.width - 2 * BEZEL, y = (wall.height - 2 * BEZEL) / count }
    local center = screen_center(wall)
    local top = center.y + (wall.height - 2 * BEZEL) / 2
    local yaw = minetest.dir_to_yaw(vector.multiply(wall.back, -1))
    for row = 1, count do
        local pos = vector.new(center.x, top - (row - 0.5) * size.y, center.z)
        local object = objects[row]
        if not (object and object:get_pos()) then
            object = minetest.add_entity(pos, SCREEN_ENTITY, minetest.pos_to_string(tower_pos) .. ";" .. row)
            objects[row] = object
        end
        local entity = object and object:get_luaentity()
        if entity then
            if vector.distance(object:get_pos(), pos) > 0.001 then
                object:set_pos(pos)
            end
            if entity._yaw ~= yaw then
                object:set_yaw(yaw)
                entity._yaw = yaw
            end
            if entity._texture ~= textures[row] or entity._width ~= size.x or entity._height ~= size.y then
                object:set_properties({ visual_size = size, textures = { textures[row], "blank.png" } })
                entity._texture, entity._width, entity._height = textures[row], size.x, size.y
            end
        end
    end
    -- Rows the screen doesn't have anymore
    for row, object in pairs(objects) do
        if row > count then
            if object:get_pos() then
                object:remove()
            end
            objects[row] = nil
        end
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
        -- Screens are made again when their tower is near players
        static_save = false,
    },
    on_activate = function(self, staticdata)
        local tower_text, row = string.match(staticdata or "", "^(.*);(%d+)$")
        local tower_pos = tower_text and minetest.string_to_pos(tower_text)
        if not tower_pos then
            -- A screen saved by an older version, which had one entity for the whole screen
            self.object:remove()
            return
        end
        self._tower, self._row = tower_pos, tonumber(row)
        self.object:set_armor_groups({ immortal = 1 })
    end,
    get_staticdata = function(self)
        return self._tower and (minetest.pos_to_string(self._tower) .. ";" .. self._row) or ""
    end,
})

-- Screens of towers that come near players
minetest.register_abm({
    label = "Show the screens of computer towers near players",
    nodenames = { "group:modular_computer_tower" },
    interval = 2,
    chance = 1,
    catch_up = false,
    action = function(pos)
        if next(display.get_rows(pos)) == nil and display.get_wall(pos) then
            display.update(pos)
        end
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
