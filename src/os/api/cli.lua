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
]]

modular_computers.command = {}
modular_computers.internal.command = { registered_commands = {} }

function modular_computers.command.register(name, callback)
    modular_computers.internal.command.registered_commands[name] = callback
end

-- Returns the definition of a registered command, or nil
function modular_computers.command.get(name)
    return modular_computers.internal.command.registered_commands[name]
end

-- Returns the names of all registered commands, sorted alphabetically
function modular_computers.command.list()
    local names = {}
    for name in pairs(modular_computers.internal.command.registered_commands) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Returns the position of the computer running the current command, or nil
-- when the command was not started through execute_at
function modular_computers.command.get_computer_pos()
    return modular_computers.internal.command.computer_pos
end

function modular_computers.command.execute(...)
    local args = { ... }
    local name = args[1]
    if name == nil or name == "" then
        return ""
    end

    local def = modular_computers.internal.command.registered_commands[name]
    if def == nil then
        return modular_computers.S("@1: command not found", name) .. "\n"
    end

    local ok, stdin, stdout, stderr, exit_code = pcall(def.func, #args - 1, unpack(args, 2))
    if not ok then
        modular_computers:err("command " .. name .. " failed: " .. tostring(stdin))
        return name .. ": " .. tostring(stdin) .. "\n"
    end
    stdin, stdout, stderr, exit_code = stdin or "", stdout or "", stderr or "", exit_code or 0

    local terminal_text = ""
    if stdin ~= "" then
        terminal_text = terminal_text .. stdin
    end
    if stderr ~= "" then
        terminal_text = terminal_text .. stderr
    elseif stdout ~= "" then
        terminal_text = terminal_text .. stdout
    end
    if exit_code ~= 0 then
        terminal_text = terminal_text .. modular_computers.S("ERROR: Command exited with code: ")
            .. exit_code .. "\n"
    end
    return terminal_text
end

-- Like execute, but lets the command find the computer at pos through get_computer_pos
function modular_computers.command.execute_at(pos, ...)
    local internal = modular_computers.internal.command
    local previous_pos = internal.computer_pos
    internal.computer_pos = pos
    local terminal_text = modular_computers.command.execute(...)
    internal.computer_pos = previous_pos
    return terminal_text
end
