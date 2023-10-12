-- This file is part of ComputerTest Redo.

-- ComputerTest Redo is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- ComputerTest Redo is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
-- You should have received a copy of the GNU Affero General Public License along with ComputerTest Redo. If not, see <https://www.gnu.org/licenses/>.
-- The license is included in the project root under the file labeled LICENSE. All files not otherwise specified under a different license shall be put under this license.

-- Copyright (c) 2023 James Clarke <james@jamesdavidclarke.com>
-- Copyright (c) 2023 nitrogenez

local terminal_text = ""

function formspec(terminal_text)
return "size[15,10]" .. 
    "textarea[0.5,0.5;14,8;terminal_out;Terminal:;" .. minetest.formspec_escape(terminal_text) .. "]" .. 
    "field_close_on_enter[terminal_in;false]" .. 
    "set_focus[terminal_in;true]" ..
    "field[0.5,9;14,1;terminal_in;Input Command:;]"
end
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
    on_rightclick = function(pos, node, player)
        local formname = "ctr_nodes:computer_formspec"
        minetest.show_formspec(player:get_player_name(), formname, formspec(""))
    end,
})

-- Handle form submission
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "ctr_nodes:computer_formspec" then
        if fields.key_enter_field == "terminal_in" then
            -- Append the command to the terminal text
            if fields.terminal_out ~= "" then
                terminal_text = fields.terminal_out .. "\n" .. fields.terminal_in
            else
                terminal_text = fields.terminal_in
            end
            minetest.log("action", "[ctr]:\t" .. "Player:\t" .. player:get_player_name() .. "Submitted command:\t" .. fields.terminal_in)
            -- Show the updated formspec to the player
            minetest.show_formspec(player:get_player_name(), formname, formspec(terminal_text))
        end
    end
end)


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
elseif modpath("default") then
    stone = "default:stone"
    core = "default:mese"
    glass = "default:glass"
elseif modpath("mcl_core") then
    stone = "mcl_core:stone"
    core = "mesecons_torch:redstoneblock"
    glass = "xpanes:pane_natural_flat"
end

if not stone or not core or not glass then
    minetest.log("error","[ctr]:\tcould not find a crafting recipe")
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