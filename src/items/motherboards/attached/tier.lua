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

function modular_computers.motherboard.save_tier(id, tier_number)
    -- Get the saved inventories data from mod storage
    local motherboard_tiers = minetest.deserialize(
                                  modular_computers.mod_storage:get_string(
                                      "motherboard_attached_tiers")) or {}

    -- Save or update the inventory data for this id
    motherboard_tiers[id] = attached_inventory -- Directly assign the inv_data here

    -- Save the updated saved inventories data back to mod storage
    modular_computers.mod_storage:set_string("motherboard_attached_tiers",
                                             minetest.serialize(
                                                 motherboard_tiers))
end

function modular_computers.motherboard.get_tier(id)
    local motherboard_attached_tiers = minetest.deserialize(
                                           modular_computers.mod_storage:get_string(
                                               "motherboard_attached_tiers")) or
                                           {}
    if motherboard_attached_tiers[id] == nil then
        return 0
    else
        return to_number(motherboard_attached_tiers[id])
    end
end
