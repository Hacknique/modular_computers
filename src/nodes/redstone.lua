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

-- Redstone support for computer towers, through mcl_redstone (Mineclonia) and mesecons
-- (VoxeLibre, Minetest Game, or the mesecons modpack in other games).
--
-- Sides are relative to the tower: "front" is its front panel, and "left" and "right" are
-- as seen by a player looking at the front.
--
-- Both mcl_redstone and mesecons work out the power a node emits from the node alone, so
-- the powered sides are stored in the node name: there is one node for every combination
-- of powered sides, like the mesecons luacontroller. Inputs are stored in node meta per
-- world direction, separately for each system so both can be used at the same time.

modular_computers.redstone = {}
local redstone = modular_computers.redstone

redstone.BASE_NODE = "modular_computers:tower"
redstone.SIDES = { "front", "back", "left", "right", "top", "bottom" }
redstone.MAX_MASK = 2 ^ #redstone.SIDES - 1

local MCL_INPUT = "redstone_input_mcl"
local MESECONS_INPUT = "redstone_input_mesecons"

local SIDE_BITS = {}
for index, side in ipairs(redstone.SIDES) do
    SIDE_BITS[side] = 2 ^ (index - 1)
end

local function has_bit(mask, bit)
    return math.floor(mask / bit) % 2 == 1
end

-- World directions, in the order of the digits of the input meta strings
local DIRECTIONS = {
    vector.new(1, 0, 0), vector.new(-1, 0, 0),
    vector.new(0, 1, 0), vector.new(0, -1, 0),
    vector.new(0, 0, 1), vector.new(0, 0, -1),
}
local DIRECTION_NAMES = { "east", "west", "up", "down", "north", "south" }

local function direction_index(dir)
    for index, direction in ipairs(DIRECTIONS) do
        if dir.x == direction.x and dir.y == direction.y and dir.z == direction.z then
            return index
        end
    end
end

local function copy_directions(indices)
    local rules = {}
    for _, index in ipairs(indices) do
        local dir = DIRECTIONS[index]
        table.insert(rules, { x = dir.x, y = dir.y, z = dir.z })
    end
    return rules
end

-- Direction the top of a node points to, by facedir axis (param2 / 4)
local AXIS_TOPS = {
    [0] = vector.new(0, 1, 0), vector.new(0, 0, 1), vector.new(0, 0, -1),
    vector.new(1, 0, 0), vector.new(-1, 0, 0), vector.new(0, -1, 0),
}

-- side_directions[facedir][side] and direction_sides[facedir][direction index]
local side_directions = {}
local direction_sides = {}
for facedir = 0, 23 do
    local back = minetest.facedir_to_dir(facedir)
    local top = AXIS_TOPS[math.floor(facedir / 4)]
    local right = vector.cross(top, back)
    local directions = {
        front = direction_index(vector.multiply(back, -1)),
        back = direction_index(back),
        left = direction_index(vector.multiply(right, -1)),
        right = direction_index(right),
        top = direction_index(top),
        bottom = direction_index(vector.multiply(top, -1)),
    }
    side_directions[facedir] = directions
    direction_sides[facedir] = {}
    for side, index in pairs(directions) do
        direction_sides[facedir][index] = side
    end
end

local function get_facedir(node)
    local facedir = node.param2 % 32
    return facedir < 24 and facedir or 0
end

-- Returns the suffix of the node name for outputs on the sides in mask, like "_100000"
function redstone.name_suffix(mask)
    if mask == 0 then
        return ""
    end
    local digits = {}
    for index, side in ipairs(redstone.SIDES) do
        digits[index] = has_bit(mask, SIDE_BITS[side]) and "1" or "0"
    end
    return "_" .. table.concat(digits)
end

local node_names = {}
local masks = {}
for mask = 0, redstone.MAX_MASK do
    local name = redstone.BASE_NODE .. redstone.name_suffix(mask)
    node_names[mask] = name
    masks[name] = mask
end

-- Returns the name of the tower node with outputs on the sides in mask
function redstone.node_name(mask)
    return node_names[mask]
end

function redstone.is_side(side)
    return SIDE_BITS[side] ~= nil
end

-- Returns the compass direction ("north", "up", ...) a side of the tower at pos faces
function redstone.get_direction_name(pos, side)
    return DIRECTION_NAMES[side_directions[get_facedir(minetest.get_node(pos))][side]]
end

local function read_levels(meta, key)
    local digits = meta:get_string(key)
    local levels = {}
    for index = 1, #DIRECTIONS do
        levels[index] = tonumber(string.sub(digits, index, index), 16) or 0
    end
    return levels
end

local function write_levels(meta, key, levels)
    local digits = {}
    local powered = false
    for index = 1, #DIRECTIONS do
        digits[index] = string.format("%x", levels[index])
        powered = powered or levels[index] > 0
    end
    local value = powered and table.concat(digits) or ""
    if meta:get_string(key) ~= value then
        meta:set_string(key, value)
    end
end

-- Returns the signal level (0-15) coming into a side of the tower at pos
function redstone.get_input(pos, side)
    local index = side_directions[get_facedir(minetest.get_node(pos))][side]
    local meta = minetest.get_meta(pos)
    return math.max(read_levels(meta, MCL_INPUT)[index], read_levels(meta, MESECONS_INPUT)[index])
end

local function input_levels(pos)
    local levels = {}
    for _, side in ipairs(redstone.SIDES) do
        levels[side] = redstone.get_input(pos, side)
    end
    return levels
end

-- Tells the programs of the computer at pos about the sides whose input changed
local function notify(pos, before)
    local m = modular_computers.machine.get(pos)
    if not m then
        return
    end
    for _, side in ipairs(redstone.SIDES) do
        local level = redstone.get_input(pos, side)
        if level ~= before[side] then
            modular_computers.components.redstone_changed(m, side, before[side], level)
        end
    end
end

-- Returns true if the tower at pos powers a side
function redstone.get_output(pos, side)
    return has_bit(masks[minetest.get_node(pos).name] or 0, SIDE_BITS[side])
end

local ALL_RULES = copy_directions({ 1, 2, 3, 4, 5, 6 })

-- mesecons rules for the powered sides of a tower node, cached by facedir and mask
local output_rules_cache = {}
local function output_rules(node)
    local mask = masks[node.name] or 0
    local facedir = get_facedir(node)
    local key = facedir * (redstone.MAX_MASK + 1) + mask
    if not output_rules_cache[key] then
        local indices = {}
        for _, side in ipairs(redstone.SIDES) do
            if has_bit(mask, SIDE_BITS[side]) then
                table.insert(indices, side_directions[facedir][side])
            end
        end
        output_rules_cache[key] = copy_directions(indices)
    end
    return output_rules_cache[key]
end

local function contains_rule(rules, rule)
    for _, other in ipairs(rules) do
        if other.x == rule.x and other.y == rule.y and other.z == rule.z then
            return true
        end
    end
    return false
end

-- Swaps the tower node at pos for new_node and tells redstone about changed outputs
local function transition(pos, old_node, new_node)
    if minetest.global_exists("mcl_redstone") then
        mcl_redstone.swap_node(pos, new_node)
    else
        minetest.swap_node(pos, new_node)
    end

    if minetest.global_exists("mesecon") then
        local old_rules, new_rules = output_rules(old_node), output_rules(new_node)
        local turned_off, turned_on = {}, {}
        for _, rule in ipairs(old_rules) do
            if not contains_rule(new_rules, rule) then
                table.insert(turned_off, rule)
            end
        end
        for _, rule in ipairs(new_rules) do
            if not contains_rule(old_rules, rule) then
                table.insert(turned_on, rule)
            end
        end
        if #turned_off > 0 then
            mesecon.receptor_off(pos, turned_off)
        end
        if #turned_on > 0 then
            mesecon.receptor_on(pos, turned_on)
        end
    end
end

-- Switches the output of a side (or "all" sides) of the tower at pos on or off.
-- Returns false if there is no tower at pos or the side is unknown.
function redstone.set_output(pos, side, on)
    local node = minetest.get_node(pos)
    local mask = masks[node.name]
    if not mask or not (side == "all" or redstone.is_side(side)) then
        return false
    end

    local new_mask = mask
    for _, name in ipairs(side == "all" and redstone.SIDES or { side }) do
        local bit = SIDE_BITS[name]
        if on and not has_bit(new_mask, bit) then
            new_mask = new_mask + bit
        elseif not on and has_bit(new_mask, bit) then
            new_mask = new_mask - bit
        end
    end

    if new_mask ~= mask then
        transition(pos, node, { name = node_names[new_mask], param1 = node.param1, param2 = node.param2 })
    end
    return true
end

-- Screwdriver callback: moves the outputs along with the tower
function redstone.on_rotate(pos, node, user, mode, new_param2)
    if (masks[node.name] or 0) == 0 then
        return nil
    end
    transition(pos, node, { name = node.name, param1 = node.param1, param2 = new_param2 })
    return true
end

-- The `mesecons` field of the tower node with outputs on the sides in mask
function redstone.mesecons_def(mask)
    return {
        effector = {
            rules = ALL_RULES,
            action_change = function(pos, _, rule, new_state)
                local index = direction_index(rule)
                if index then
                    local before = input_levels(pos)
                    local meta = minetest.get_meta(pos)
                    local levels = read_levels(meta, MESECONS_INPUT)
                    levels[index] = new_state == "on" and 15 or 0
                    write_levels(meta, MESECONS_INPUT, levels)
                    notify(pos, before)
                end
            end,
        },
        receptor = {
            state = mask == 0 and "off" or "on",
            rules = mask == 0 and ALL_RULES or output_rules,
        },
    }
end

-- The `_mcl_redstone` field of the tower node with outputs on the sides in mask
function redstone.mcl_redstone_def(mask)
    local def = {
        connects_to = function()
            return true
        end,
        update = function(pos)
            local before = input_levels(pos)
            local levels = {}
            for index, dir in ipairs(DIRECTIONS) do
                levels[index] = mcl_redstone.get_power(pos, dir)
            end
            write_levels(minetest.get_meta(pos), MCL_INPUT, levels)
            notify(pos, before)
        end,
    }
    if mask ~= 0 then
        def.get_power = function(node, dir)
            local index = direction_index(dir)
            local side = index and direction_sides[get_facedir(node)][index]
            return side and has_bit(mask, SIDE_BITS[side]) and 15 or 0, false
        end
    end
    return def
end
