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

    Copyright (c) 2023-2026 James Clarke <james@jamesdavidclarke.com>
    Copyright (c) 2023 nitrogenez
]]

local S = modular_computers.S
local terminal = modular_computers.terminal
local redstone = modular_computers.redstone

local function is_computer(pos)
    return minetest.get_item_group(minetest.get_node(pos).name, "modular_computer") > 0
end

local function stone_sounds()
    if minetest.global_exists("mcl_sounds") then
        return mcl_sounds.node_sound_stone_defaults()
    elseif minetest.global_exists("default") and default.node_sound_stone_defaults then
        return default.node_sound_stone_defaults()
    end
end

local function show_terminal(player_name, pos, input)
    local info = minetest.get_player_information(player_name)
    local text = terminal.get_text(minetest.get_meta(pos))
    minetest.show_formspec(player_name, terminal.FORMNAME,
        terminal.formspec(text, input, info and info.lang_code))
end

local function run_command_line(pos, command_line)
    local meta = minetest.get_meta(pos)
    command_line = command_line:gsub("[\r\n]", " "):trim()
    terminal.append(meta, terminal.PROMPT .. " " .. command_line .. "\n")
    if command_line == "" then
        return
    end
    terminal.add_history(meta, command_line)
    local args = string.split(command_line, "%s+", false, -1, true)
    terminal.append(meta, modular_computers.command.execute_at(pos, unpack(args)))
end

-- Up/Down arrow keys walk through the command history like a shell does
local function recall_history(context, meta, step, input)
    local history = terminal.get_history(meta)
    local index = context.history_index
    if #history == 0 or (not index and step > 0) then
        return input
    end
    if not index then
        context.draft = input
        index = #history + 1
    end
    index = math.max(index + step, 1)
    if index > #history then
        context.history_index = nil
        return context.draft or ""
    end
    context.history_index = index
    return history[index]
end

local function on_rightclick(pos, node, clicker, itemstack)
    if not clicker or not clicker:is_player() then
        return itemstack
    end
    local player_name = clicker:get_player_name()
    if minetest.is_protected(pos, player_name) then
        minetest.record_protection_violation(pos, player_name)
        return itemstack
    end

    local context = modular_computers.get_context(player_name)
    context.computer_pos = { x = pos.x, y = pos.y, z = pos.z }
    context.history_index, context.draft = nil, nil
    show_terminal(player_name, pos, "")
    return itemstack
end

-- register the computer node, with one variant for every combination of powered redstone sides
for mask = 0, redstone.MAX_MASK do
    local groups = { cracky = 2, pickaxey = 1, modular_computer = 1 }
    if mask ~= 0 then
        groups.not_in_creative_inventory = 1
        groups.not_in_craft_guide = 1
    end

    minetest.register_node(redstone.node_name(mask), {
        description = S("Computer"),
        tiles = {
            "computer_side.png", -- Y+
            "computer_side.png", -- Y-
            "computer_side.png", -- X+
            "computer_side.png", -- X-
            "computer_side.png", -- Z+
            "computer_front.png" -- Z-
        },
        groups = groups,
        is_ground_content = false,
        sounds = stone_sounds(),
        paramtype = "light",
        light_source = 6,
        paramtype2 = "facedir", -- needed for the node to rotate properly on place
        stack_max = 1,
        drop = mask ~= 0 and redstone.BASE_NODE or nil,
        _doc_items_create_entry = mask == 0,
        _mcl_hardness = 3.5,
        _mcl_blast_resistance = 3.5,

        on_place = minetest.rotate_node,

        on_construct = function(pos)
            terminal.append(minetest.get_meta(pos),
                S("Modular Computers") .. "\n" .. S("Type 'help' for a list of commands.") .. "\n")
        end,

        on_rightclick = on_rightclick,
        on_rotate = redstone.on_rotate,

        mesecons = redstone.mesecons_def(mask),
        _mcl_redstone = redstone.mcl_redstone_def(mask),
    })
end

-- Handle form submission
minetest.register_on_player_receive_fields(
    function(player, formname, fields)
        if formname ~= terminal.FORMNAME then
            return false
        end

        local player_name = player:get_player_name()
        local context = modular_computers.get_context(player_name)
        local pos = context.computer_pos
        if fields.quit then
            context.computer_pos, context.history_index, context.draft = nil, nil, nil
            return true
        end
        if not pos or not is_computer(pos) then
            minetest.close_formspec(player_name, terminal.FORMNAME)
            return true
        end
        if minetest.is_protected(pos, player_name) then
            minetest.record_protection_violation(pos, player_name)
            minetest.close_formspec(player_name, terminal.FORMNAME)
            return true
        end

        local input = fields.terminal_in or ""
        if fields.key_enter_field == "terminal_in" then
            modular_computers:act("Player:\t" .. player_name .. "\tSubmitted command:\t" .. input)
            run_command_line(pos, input)
            input = ""
            context.history_index, context.draft = nil, nil
        elseif fields.key_up then
            input = recall_history(context, minetest.get_meta(pos), -1, input)
        elseif fields.key_down then
            input = recall_history(context, minetest.get_meta(pos), 1, input)
        end

        -- Anything else (like clicking the output) just refocuses the input
        show_terminal(player_name, pos, input)
        return true
    end
)

modular_computers.register_bulk_recipes("computer", {
    {
        { "default", "mesecons_luacontroller" }, {
            { "default:stone", "default:glass", "default:stone" },
            { "default:stone", "mesecons_luacontroller:luacontroller0000", "default:stone" },
            { "default:stone", "default:stone", "default:stone" }
        }
    }, {
        { "default" }, {
            { "default:stone", "default:glass", "default:stone" },
            { "default:stone", "default:mese_crystal", "default:stone" },
            { "default:stone", "default:stone", "default:stone" }
        }
    }, {
        -- Mineclonia
        { "mcl_core", "mcl_panes", "mcl_redstone_torch" }, {
            { "mcl_core:stone", "mcl_panes:pane_natural_flat", "mcl_core:stone" },
            { "mcl_core:stone", "mcl_redstone_torch:redstoneblock", "mcl_core:stone" },
            { "mcl_core:stone", "mcl_core:stone", "mcl_core:stone" }
        }
    }, {
        -- VoxeLibre
        { "mcl_core", "xpanes", "mesecons_torch" }, {
            { "mcl_core:stone", "xpanes:pane_natural_flat", "mcl_core:stone" },
            { "mcl_core:stone", "mesecons_torch:redstoneblock", "mcl_core:stone" },
            { "mcl_core:stone", "mcl_core:stone", "mcl_core:stone" }
        }
    }
})
