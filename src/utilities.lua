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

modular_computers.contexts = {}

function modular_computers.get_context(name)
    local context = modular_computers.contexts[name] or {}
    modular_computers.contexts[name] = context
    return context
end

minetest.register_on_leaveplayer(function(player)
    modular_computers.contexts[player:get_player_name()] = nil
end)

-- Returns true if an item (or an alias of one) with this name is registered.
-- Empty slots and "group:" ingredients are always considered available.
function modular_computers.item_exists(name)
    if name == "" or string.sub(name, 1, 6) == "group:" then
        return true
    end
    return minetest.registered_items[name] ~= nil
end

-- logging functions
function modular_computers:log(level, text)
    minetest.log(level, "[modular_computers]:\t" .. text)
end

function modular_computers:err(text) modular_computers:log("error", text) end

function modular_computers:warn(text) modular_computers:log("warning", text) end

function modular_computers:act(text) modular_computers:log("action", text) end

function modular_computers:info(text) modular_computers:log("info", text) end

function modular_computers:verbose(text) modular_computers:log("verbose", text) end
