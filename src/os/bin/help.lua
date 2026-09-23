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

modular_computers.command.register("help", {
    description = modular_computers.S("List the available commands"),
    func = function()
        local lines = {}
        for _, name in ipairs(modular_computers.command.list()) do
            local description = modular_computers.command.get(name).description
            table.insert(lines, description and string.format("%-10s %s", name, description) or name)
        end
        -- Lua programs in /bin
        local m = modular_computers.command.get_machine()
        if m then
            local fs = m.components[m.drive]
            local programs = {}
            for _, file in ipairs(modular_computers.components.types.filesystem.list(m, fs, "/bin") or {}) do
                local name = file:match("^(.-)%.lua$")
                if name then
                    table.insert(programs, name)
                end
            end
            if #programs > 0 then
                table.insert(lines, "")
                table.insert(lines, modular_computers.S("Programs: @1", table.concat(programs, ", ")))
            end
        end
        return "", table.concat(lines, "\n") .. "\n", "", 0
    end,
})
