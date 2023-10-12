-- This file is part of ComputerTest Redo.

-- ComputerTest Redo is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- ComputerTest Redo is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
-- You should have received a copy of the GNU Affero General Public License along with ComputerTest Redo. If not, see <https://www.gnu.org/licenses/>.
-- The license is included in the project root under the file labeled LICENSE. All files not otherwise specified under a different license shall be put under this license.

ctr = {} -- Local alias for convenience

ctr.mod = {}
ctr.mod.name = minetest.get_current_modname()
ctr.mod.path = minetest.get_modpath(ctr.mod.name)

ctr.registered_commands = {}

ctr.S = minetest.get_translator(ctr.mod.name)

-- Load the scripts
dofile(ctr.mod.path .. "/src/utilities.lua")
dofile(ctr.mod.path .. "/src/os/api/cli.lua")
dofile(ctr.mod.path .. "/src/nodes/computer.lua")
