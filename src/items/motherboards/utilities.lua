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

function modular_computers.motherboard.get_itemstack_from_id(id)
    modular_computers:act("Checking existence for id: " .. tostring(id))

    local attached_inventory = modular_computers.motherboard
                                   .get_attached_inventory(id)

    -- Log the attached_inventory value
    modular_computers:act("Attached inventory: " ..
                              minetest.serialize(attached_inventory))

    if attached_inventory == nil or attached_inventory == {} then -- checking for nil or empty table
        modular_computers:err("Attached inventory is nil or empty for id: " ..
                                  tostring(id))
        return nil
    else
        local inventory = minetest.get_inventory(attached_inventory)
        if inventory then
            local itemstack = modular_computers.find_itemstack_with_metafield(
                                  inventory, "id", id)[3]
            modular_computers:act("Itemstack found: " .. tostring(found))
            if itemstack then
                return itemstack
            else
                modular_computers:err("Itemstack with id: " .. id ..
                                          " not found in attached inventory")
                return itemstack
            end
        else
            -- Log an error if the inventory is nil
            modular_computers:err("Failed to get inventory for id: " .. id)
            return nil
        end
    end
end

function modular_computers.motherboard.check_exists(id)
    if modular_computers.motherboard.get_itemstack_from_id(id) then
        return true
    else
        return false
    end
end

