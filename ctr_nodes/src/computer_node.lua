-- This file is part of ComputerTest Redo.

-- ComputerTest Redo is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- ComputerTest Redo is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
-- You should have received a copy of the GNU Affero General Public License along with ComputerTest Redo. If not, see <https://www.gnu.org/licenses/>.
-- The license is included in the project root under the file labeled LICENSE. All files not otherwise specified under a different license shall be put under this license.

-- Copyright (c) 2023 nitrogenez

-- register the computer node
minetest.register_node("ctr_nodes:computer", {
    description = ctrn.S("Computer"),
    tiles = {
        "computer_side.png",      -- Y-
        "computer_side.png",      -- Y+
        "computer_side.png",      -- X-
        "computer_side.png",      -- X+
        "computer_side.png",      -- Z-
        "computer_front_new.png", -- Z+
    },
    groups = { cracky = 2 },
    paramtype = "light",
    light_source = 6,
    paramtype2 = "facedir",          -- needed for the node to rotate properly on place
    on_place = minetest.rotate_node, -- rotates the node on place
})

-- just a shortcut
local modpath = minetest.get_modpath

-- check if dependencies are present
local default_found = modpath("default") ~= nil
local mesecons_found = modpath("mesecons_luacontroller") ~= nil
local mcl_core_found = modpath("mcl_core") ~= nil
local alt_craft = mcl_core_found and not (default_found and mesecons_found)

-- if the dependencies are not present, return
if not default_found and not mesecons_found and not mcl_core_found then
    ctrn:err("none of the dependencies were found")
    return
end

local stone = "default:stone"
local controller = "mesecons_luacontroller:luacontroller0000"

-- make the crafting recipe based on which dependencies are found
if alt_craft then
    stone = "mcl_core:stone"
    controller = "mcl_redstone:redstone_block"
end

-- register crafting recipe
minetest.register_craft({
    output = "ctr_nodes:computer",
    recipe = {
        { stone, stone,      stone },
        { stone, controller, stone },
        { stone, stone,      stone },
    },
})
