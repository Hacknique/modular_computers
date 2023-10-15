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

modular_computers.motherboards = {}
modular_computers.motherboard = {}

dofile(modular_computers.mod.path .. "/src/items/motherboards/inventory.lua")
dofile(modular_computers.mod.path ..
           "/src/items/motherboards/attached/inventory.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/attached/tier.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/utilities.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/register.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/items.lua")
dofile(modular_computers.mod.path ..
           "/src/items/motherboards/event_handlers.lua")
