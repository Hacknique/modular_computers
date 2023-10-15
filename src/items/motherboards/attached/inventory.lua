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

function modular_computers.motherboard.delete_attached_inventory(id)
    local motherboard_attached_inventories =
        minetest.deserialize(modular_computers.mod_storage:get_string(
                                 "motherboard_attached_inventories")) or {}
    if motherboard_attached_inventories then
        motherboard_attached_inventories[id] = nil
        modular_computers.mod_storage:set_string(
            "motherboard_attached_inventories",
            minetest.serialize(motherboard_attached_inventories))
        modular_computers:act(
            "Deleted attached motherboard inventory for id: " .. id)
    else
        modular_computers:warn(
            "Attempted to delete a non-existent attached motherboard inventory with id: " ..
                id)
    end
end

function modular_computers.motherboard.save_attached_inventory(id,
                                                               attached_inventory)
    -- Get the saved inventories data from mod storage
    local motherboard_attached_inventories =
        minetest.deserialize(modular_computers.mod_storage:get_string(
                                 "motherboard_attached_inventories")) or {}

    -- Save or update the inventory data for this id
    motherboard_attached_inventories[id] = attached_inventory -- Directly assign the inv_data here

    -- Save the updated saved inventories data back to mod storage
    modular_computers.mod_storage:set_string("motherboard_attached_inventories",
                                             minetest.serialize(
                                                 motherboard_attached_inventories))
end

function modular_computers.motherboard.get_attached_inventory(id)
    local motherboard_attached_inventories =
        minetest.deserialize(modular_computers.mod_storage:get_string(
                                 "motherboard_attached_inventories")) or {}
    return motherboard_attached_inventories[id]
end
