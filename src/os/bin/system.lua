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

-- Commands that restart and turn off the computer

local S = modular_computers.S
local command = modular_computers.command

command.register("reboot", {
    description = S("Restart the computer"),
    func = function()
        local m = command.get_machine()
        if not m then
            return "", "", S("The computer is not running.") .. "\n", 0
        end
        -- The machine restarts in the next server step, after this command's output
        m.reboot = true
        return "", S("Restarting...") .. "\n", "", 0
    end,
})

command.register("shutdown", {
    description = S("Turn the computer off"),
    func = function()
        local pos = command.get_computer_pos()
        if not pos then
            return "", "", S("The computer is not running.") .. "\n", 0
        end
        minetest.get_meta(pos):set_string("power", "off")
        modular_computers.computer.update(pos)
        return "", S("Turning off...") .. "\n", "", 0
    end,
})

command.register("uptime", {
    description = S("Show how long the computer has been running"),
    func = function()
        local m = command.get_machine()
        if not m then
            return "", "", S("The computer is not running.") .. "\n", 0
        end
        local seconds = math.floor((minetest.get_us_time() - m.started) / 1e6)
        return "", string.format("%d:%02d:%02d\n", math.floor(seconds / 3600), math.floor(seconds / 60) % 60,
            seconds % 60), "", 0
    end,
})
