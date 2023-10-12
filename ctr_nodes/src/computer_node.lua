-- This file is part of ComputerTest Redo.

-- ComputerTest Redo is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- ComputerTest Redo is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
-- You should have received a copy of the GNU Affero General Public License along with ComputerTest Redo. If not, see <https://www.gnu.org/licenses/>.
-- The license is included in the project root under the file labeled LICENSE. All files not otherwise specified under a different license shall be put under this license.

-- Copyright (c) 2023 James Clarke <james@jamesdavidclarke.com>
-- Copyright (c) 2023 nitrogenez


-- register the computer node
minetest.register_node("ctr_nodes:computer", {
    description = ctr.S("Computer"),
    tiles = {
        "computer_side.png",      -- Y-
        "computer_side.png",      -- Y+
        "computer_side.png",      -- X-
        "computer_side.png",      -- X+
        "computer_side.png",      -- Z-
        "computer_front.png",     -- Z+
    },
    groups = { cracky = 2 },
    paramtype = "light",
    light_source = 6,
    paramtype2 = "facedir",          -- needed for the node to rotate properly on place
    on_place = minetest.rotate_node, -- rotates the node on place
})

-- local shortcut for get_modpath
local modpath = minetest.get_modpath

local stone = nil
local core = nil
local glass = nil

-- register crafting recipe

if modpath("default") and modpath("mesecons_luacontroller") then
    stone = "default:stone"
    core = "mesecons_luacontroller:luacontroller0000"
    glass = "default:glass"
elseif modpath("mcl_core") then
    stone = "mcl_core:stone"
    core = "mcl_redstone:redstone_block"
    glass = "mcl_core:glass_pane"
end

if not stone or not core or not glass then
    ctr:err("could not find a crafting recipe")
else
minetest.register_craft({
    output = "ctr_nodes:computer",
    recipe = {
        { stone, glass,      stone },
        { stone, core, stone },
        { stone, stone,      stone },
    },
})
end