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

-- A computer is a tower with a motherboard and components, used through the monitor on top
-- of it. The tower keeps the terminal (node meta "text" and "history") and runs while it has
-- all its components.

local S = modular_computers.S
local terminal = modular_computers.terminal
local hardware = modular_computers.hardware
local redstone = modular_computers.redstone
local display = modular_computers.display

modular_computers.computer = {}
local computer = modular_computers.computer

function computer.is_tower(pos)
    return minetest.get_item_group(minetest.get_node(pos).name, "modular_computer_tower") > 0
end

function computer.stone_sounds()
    if minetest.global_exists("mcl_sounds") then
        return mcl_sounds.node_sound_stone_defaults()
    elseif minetest.global_exists("default") and default.node_sound_stone_defaults then
        return default.node_sound_stone_defaults()
    end
end

-- Returns the names of the parts the tower at pos still needs to run
function computer.get_missing(pos)
    local inv = minetest.get_meta(pos):get_inventory()
    if inv:is_empty("motherboard") then
        return { hardware.NAMES.motherboard }
    end
    local missing = {}
    for _, kind in ipairs(hardware.COMPONENTS) do
        if inv:is_empty(kind) then
            table.insert(missing, hardware.NAMES[kind])
        end
    end
    return missing
end

function computer.is_running(pos)
    return minetest.get_meta(pos):get_int("running") == 1
end

-- Starts or stops the computer at pos after its parts changed, and refreshes its screen
function computer.update(pos)
    local meta = minetest.get_meta(pos)
    local running = #computer.get_missing(pos) == 0
    if running ~= computer.is_running(pos) then
        meta:set_int("running", running and 1 or 0)
        if running then
            terminal.append(meta,
                S("Modular Computers") .. "\n" .. S("Type 'help' for a list of commands.") .. "\n")
        else
            redstone.set_output(pos, "all", false)
        end
    end
    display.update(pos)
end

local function show_terminal(player_name, pos, input)
    local info = minetest.get_player_information(player_name)
    local text = terminal.get_text(minetest.get_meta(pos))
    minetest.show_formspec(player_name, terminal.FORMNAME,
        terminal.formspec(text, input, info and info.lang_code))
end

-- Opens the terminal of the tower at pos, if it is running
function computer.open_terminal(player_name, pos)
    if minetest.is_protected(pos, player_name) then
        minetest.record_protection_violation(pos, player_name)
        return
    end
    local missing = computer.get_missing(pos)
    if #missing > 0 then
        minetest.chat_send_player(player_name,
            S("The computer tower needs: @1", table.concat(missing, ", ")))
        return
    end

    local context = modular_computers.get_context(player_name)
    context.computer_pos = { x = pos.x, y = pos.y, z = pos.z }
    context.history_index, context.draft = nil, nil
    show_terminal(player_name, pos, "")
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
        if not pos or not computer.is_tower(pos) or not computer.is_running(pos) then
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
            display.update(pos)
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
