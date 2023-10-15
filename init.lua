-- This file is part of ComputerTest Redo.

-- ComputerTest Redo is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- ComputerTest Redo is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
-- You should have received a copy of the GNU Affero General Public License along with ComputerTest Redo. If not, see <https://www.gnu.org/licenses/>.
-- The license is included in the project root under the file labeled LICENSE. All files not otherwise specified under a different license shall be put under this license.

-- global mod namespace
modular_computers = {}
modular_computers.internal = {}
modular_computers.mod = {}

modular_computers.mod_storage = minetest.get_mod_storage()

modular_computers.mod.name = minetest.get_current_modname()
modular_computers.mod.path = minetest.get_modpath(modular_computers.mod.name)

modular_computers.S = minetest.get_translator(modular_computers.mod.name)

-- Load the scripts
dofile(modular_computers.mod.path .. "/src/utilities.lua")
dofile(modular_computers.mod.path .. "/src/item_tracking.lua")
dofile(modular_computers.mod.path .. "/src/os/init.lua")
dofile(modular_computers.mod.path .. "/src/nodes/init.lua")
dofile(modular_computers.mod.path .. "/src/items/init.lua")
