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

-- The monitor goes on top of a computer tower and opens its terminal. Monitors next to and
-- above it join into a bigger screen, see display.lua.

local S = modular_computers.S
local redstone = modular_computers.redstone
local computer = modular_computers.computer
local display = modular_computers.display

local MONITOR = "modular_computers:monitor"

minetest.register_node(MONITOR, {
    description = S("Computer Monitor"),
    tiles = {
        "computer_side.png", -- Y+
        "computer_side.png", -- Y-
        "computer_side.png", -- X+
        "computer_side.png", -- X-
        "computer_side.png", -- Z+
        "computer_front.png" -- Z-
    },
    groups = { cracky = 2, pickaxey = 1, modular_computer_monitor = 1 },
    is_ground_content = false,
    sounds = computer.stone_sounds(),
    paramtype = "light",
    light_source = 6,
    paramtype2 = "facedir",
    stack_max = 1,
    _mcl_hardness = 3.5,
    _mcl_blast_resistance = 3.5,

    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        if not clicker or not clicker:is_player() then
            return itemstack
        end
        -- Holding a monitor adds it to the screen instead
        if pointed_thing and itemstack:get_name() == MONITOR then
            return minetest.item_place_node(itemstack, clicker, pointed_thing)
        end
        local player_name = clicker:get_player_name()
        local tower_pos = display.find_tower(pos)
        if not tower_pos then
            minetest.chat_send_player(player_name, S("Place the monitor on top of a computer tower."))
            return itemstack
        end
        computer.open_terminal(player_name, tower_pos)
        return itemstack
    end,

    on_construct = display.update_near,
    after_destruct = display.update_near,
})

-- The computer used to be a single block, which is now the monitor
minetest.register_alias("modular_computers:computer", MONITOR)
for mask = 1, redstone.MAX_MASK do
    minetest.register_alias("modular_computers:computer" .. redstone.name_suffix(mask), MONITOR)
end
