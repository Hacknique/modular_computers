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

local S = modular_computers.S

local function usage()
    return table.concat({
        "usage: redstone",
        "       redstone get <side>",
        "       redstone set <side|all> <on|off>",
        "sides: " .. table.concat(modular_computers.redstone.SIDES, ", "),
    }, "\n") .. "\n"
end

modular_computers.command.register("redstone", {
    description = S("Read and set redstone signals on the sides of the computer"),
    func = function(argc, action, side, state)
        local redstone = modular_computers.redstone
        local pos = modular_computers.command.get_computer_pos()
        if not pos then
            return "", "", "redstone: " .. S("not running on a computer") .. "\n", 1
        end

        if argc == 0 then
            local lines = {}
            for _, name in ipairs(redstone.SIDES) do
                table.insert(lines, string.format("%-7s %-6s in %-3d out %s", name,
                    redstone.get_direction_name(pos, name), redstone.get_input(pos, name),
                    redstone.get_output(pos, name) and "on" or "off"))
            end
            return "", table.concat(lines, "\n") .. "\n", "", 0
        elseif argc == 2 and action == "get" and redstone.is_side(side) then
            return "", redstone.get_input(pos, side) .. "\n", "", 0
        elseif argc == 3 and action == "set" and (state == "on" or state == "off")
                and redstone.set_output(pos, side, state == "on") then
            return "", "", "", 0
        end
        return "", "", usage(), 1
    end,
})
