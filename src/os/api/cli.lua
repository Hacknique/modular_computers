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

    Copyright (c) 2023 James Clarke <james@jamesdavidclarke.com>
]]

modular_computers.command = {}
modular_computers.internal.command = { registered_commands = {} }

function modular_computers.command.register(name, callback)
    modular_computers.internal.command.registered_commands[name] = callback
end

function modular_computers.command.execute(...)
    local args = { ... }
    local def = modular_computers.internal.command.registered_commands[args[1]]
    local terminal_text = ""
    if def ~= nil then
        local stdin, stdout, stderr, exit_code = def.func(player, #args - 1, unpack(args, 2))
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
    end
    return terminal_text
end
