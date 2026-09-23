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
-- all its components and is turned on (node meta "power" is not "off"). A running tower has
-- a Lua machine (src/os/machine.lua) that runs the programs typed on its terminal.

local S = modular_computers.S
local terminal = modular_computers.terminal
local hardware = modular_computers.hardware
local redstone = modular_computers.redstone
local display = modular_computers.display
local machine = modular_computers.machine
local drive = modular_computers.os.fs.drive

-- How often a running program's output is shown, in microseconds: on the monitors,
-- and on the terminals of players using the computer
local DISPLAY_INTERVAL = 500000
local TERMINAL_INTERVAL = 1000000

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

-- Starts or stops the computer at pos after its parts or power changed, and refreshes its screen
function computer.update(pos)
    local meta = minetest.get_meta(pos)
    local running = #computer.get_missing(pos) == 0 and meta:get_string("power") ~= "off"
    if running ~= computer.is_running(pos) then
        meta:set_int("running", running and 1 or 0)
        if running then
            terminal.append(meta,
                S("Modular Computers") .. "\n" .. S("Type 'help' for a list of commands.") .. "\n")
            machine.start(pos)
        else
            machine.stop(pos)
            redstone.set_output(pos, "all", false)
        end
    elseif running and not machine.get(pos) then
        machine.start(pos)
    end
    display.update(pos)
end

-- Starts the computer at pos again, stopping its programs
function computer.restart(pos)
    if computer.is_running(pos) then
        machine.restart(pos)
        display.update(pos)
    end
end

local function program_running(pos)
    local m = machine.get(pos)
    return m ~= nil and m.foreground ~= nil
end

local function show_terminal(player_name, pos, input)
    local info = minetest.get_player_information(player_name)
    local text = terminal.get_text(minetest.get_meta(pos))
    minetest.show_formspec(player_name, terminal.FORMNAME,
        terminal.formspec(text, input, info and info.lang_code, program_running(pos)))
end

-- Shows the terminal again to the players using the computer at pos
function computer.refresh_terminals(pos)
    for _, player in ipairs(minetest.get_connected_players()) do
        local player_name = player:get_player_name()
        local context = modular_computers.contexts[player_name]
        if context and context.computer_pos and vector.equals(context.computer_pos, pos) then
            show_terminal(player_name, pos, "")
        end
    end
end

-- Called when the output or screen of machine m changed. Shows it, but not too often, and
-- returns false when some of it is left to show later.
function computer.screen_changed(m)
    local now = minetest.get_us_time()
    local done = true
    if now - (m.display_time or 0) >= DISPLAY_INTERVAL then
        m.display_time = now
        display.update(m.pos)
    else
        done = false
    end
    if m.prompt_ready or m.output_changed then
        -- While a program waits for a line, players may be typing it, and showing the
        -- terminal again would lose what they typed
        local reading = m.foreground and m.foreground.wait == "input"
        if m.prompt_ready or (not reading and now - (m.terminal_time or 0) >= TERMINAL_INTERVAL) then
            m.terminal_time = now
            m.prompt_ready, m.output_changed = false, false
            computer.refresh_terminals(m.pos)
        elseif reading then
            m.output_changed = false
        else
            done = false
        end
    end
    return done
end

-- Returns the path of the program to run for a command, looked up like a shell does, or nil
function computer.find_program(m, name)
    local candidates = {}
    if name:find("/", 1, true) then
        local path = drive.resolve(name, m.cwd)
        if path then
            table.insert(candidates, path)
            table.insert(candidates, path .. ".lua")
        end
    else
        local directories = 0
        for directory in string.gmatch(m.variables.PATH or "/bin", "[^:]+") do
            local path = drive.resolve(directory .. "/" .. name, m.cwd)
            if path then
                table.insert(candidates, path .. ".lua")
                table.insert(candidates, path)
            end
            directories = directories + 1
            if directories == 32 then
                break
            end
        end
    end
    for _, path in ipairs(candidates) do
        if machine.ROM[path] or drive.is_file(m.drive, path) then
            return path
        end
    end
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

local function run_command_line(pos, command_line, player_name)
    local meta = minetest.get_meta(pos)
    local m = machine.get(pos)
    -- Escape sequences are for the terminal's own text, like translations
    command_line = command_line:gsub("[\r\n]", " "):gsub("\27", "")
    if m and m.foreground then
        -- The line goes to the running program
        if command_line:trim() == terminal.INTERRUPT then
            terminal.append(meta, terminal.INTERRUPT .. "\n")
            machine.interrupt(m)
            return
        end
        terminal.append(meta, command_line .. "\n")
        machine.input(m, command_line)
        return
    end

    command_line = command_line:trim()
    -- The prompt starts a new line, even after a program that didn't end its last one
    local text = terminal.get_text(meta)
    local line_start = (text == "" or text:sub(-1) == "\n") and "" or "\n"
    terminal.append(meta, line_start .. terminal.PROMPT .. " " .. command_line .. "\n")
    if command_line == "" then
        return
    end
    terminal.add_history(meta, command_line)
    local args = string.split(command_line, "%s+", false, -1, true)
    if modular_computers.command.get(args[1]) or not m then
        terminal.append(meta, modular_computers.command.execute_as(player_name, pos, unpack(args)))
        return
    end
    local path = computer.find_program(m, args[1])
    if not path then
        terminal.append(meta, S("@1: command not found", args[1]) .. "\n")
        return
    end
    local ok, err = machine.run(m, path, { unpack(args, 2) })
    if not ok then
        terminal.append(meta, err .. "\n")
    end
    machine.flush(m)
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
            context.editor_opened = nil
            run_command_line(pos, input, player_name)
            input = ""
            context.history_index, context.draft = nil, nil
            if context.editor_opened then
                -- The command showed the editor instead
                context.editor_opened = nil
                display.update(pos)
                return true
            end
            if not computer.is_running(pos) then
                -- The command turned the computer off
                minetest.close_formspec(player_name, terminal.FORMNAME)
                return true
            end
            display.update(pos)
        elseif fields.interrupt then
            local m = machine.get(pos)
            if m and m.foreground then
                terminal.append(minetest.get_meta(pos), terminal.INTERRUPT .. "\n")
                machine.interrupt(m)
                display.update(pos)
            end
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

minetest.register_lbm({
    label = "Start the computers in loaded towers",
    name = "modular_computers:start_computers",
    nodenames = { "group:modular_computer_tower" },
    run_at_every_load = true,
    action = function(pos)
        if computer.is_running(pos) and not machine.get(pos) then
            -- Checks its parts too, which other mods may have changed meanwhile
            computer.update(pos)
        end
    end,
})
