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

function modular_computers.register_motherboard(item_name, item_description,
                                                item_image, item_recipes,
                                                formspec, tier_number)
    local id = nil
    modular_computers.motherboards[item_name] = {
        original_formspec = formspec,
        formspec = formspec,
        detached_inventory = {
            -- allow_put = function(inv, listname, index, stack, player),

            -- end,

            on_put = function(inv, listname, index, stack, player)
                local inventory_id = modular_computers.motherboard.get_inventory_id(inv)
                modular_computers.motherboard.save_inventory(inventory_id)
            end,
            on_take = function(inv, listname, index, stack, player)
                local inventory_id = modular_computers.motherboard.get_inventory_id(inv)
                modular_computers.motherboard.save_inventory(inventory_id)
            end,
            on_move = function(inv, from_list, from_index, to_list, to_index,
                               count, player)
                local inventory_id = modular_computers.motherboard.get_inventory_id(inv)
                modular_computers.motherboard.save_inventory(inventory_id)
            end

        }
    }
    minetest.register_craftitem("modular_computers:motherboard_" .. item_name, {
        description = item_description .. " Motherboard",
        inventory_image = item_image,
        stack_max = 1,

        on_put = function(inv, listname, index, stack, player)
            local inventory_id = modular_computers.motherboard.get_inventory_id(inv)
            local attached_inventory = inv:get_location()
            modular_computers.motherboard.save_attached_inventory(inventory_id,
                                                                  attached_inventory)
            modular_computers:act("Put motherboard in " .. attached_inventory)
        end,
        on_move = function(inv, from_list, from_index, to_list, to_index, count,
                           player)
            local inventory_id = modular_computers.motherboard.get_inventory_id(inv)
            local attached_inventory = inv:get_location()
            modular_computers.motherboard.save_attached_inventory(inventory_id,
                                                                  attached_inventory)
            modular_computers:act("Moved motherboard to " .. attached_inventory)
        end,

        on_secondary_use = function(itemstack, player, pointed_thing)
            -- Get the player's name
            local player_name = player:get_player_name()

            -- Get the item's metadata
            local meta = itemstack:get_meta()

            -- Check if the 'id' field is not set in the metadata
            if meta:get_string("id") == "" then
                -- If not set, generate a new id using the provided function
                id = modular_computers.generate_id(player_name)

                -- Set Tier
                modular_computers.motherboard.save_tier(id, tier_number)

                local inv = minetest.create_detached_inventory(
                                "modular_computers:motherboard_inventory_" .. id,
                                modular_computers.motherboards[item_name]
                                    .detached_inventory)

                inv:set_size("cpu", 1)
                inv:set_size("gpu", 1)
                inv:set_size("hdd", 1)
                inv:set_size("usb", 1)

                -- Set the 'id' field in the metadata
                meta:set_string("id", id)

                -- Save Inventory
                modular_computers.motherboard.save_inventory(id)

                -- Set Callback for Saving Inventory
                modular_computers:act(
                    "Tracking Tier: " .. tostring(tier_number) .. "Motherboard" ..
                        " With ID " .. id)
                item_tracking.track_attached_inventory({
                    name = "modular_computers:motherboard_tier_" ..
                        tostring(tier_number),
                    meta = {id = id}
                }, function(name)
                    minetest.log("action", "Attached to " .. name)
                    local tracked_inventory = modular_computers.inventory_from_string(name)
                    modular_computers.save_attached_inventory(id, tracked_inventory)
                end)
            else
                id = meta:get_string("id")
            end

            -- Set Attached Inventory
            local attached_inventory = {type = "player", name = player_name}
            modular_computers:act("Attached inventory: " ..
                                      minetest.serialize(attached_inventory))
            if attached_inventory and type(attached_inventory) == "table" then
                if attached_inventory ~=
                    modular_computers.motherboard.get_attached_inventory(id) then
                    modular_computers:act(
                        "Motherboard moved to " ..
                            minetest.serialize(attached_inventory))
                    modular_computers.motherboard.save_attached_inventory(id,
                                                                          attached_inventory)
                else
                    modular_computers:act(
                        "Motherboard already in " ..
                            minetest.serialize(attached_inventory))
                end
            else
                modular_computers:err("Invalid attached inventory for id: " ..
                                          id .. " - " ..
                                          minetest.serialize(attached_inventory))
            end

            -- Check if inventory exists if it doesn't, create it
            if modular_computers.motherboard.check_inventory_exists(id) == false then
                local inv = minetest.create_detached_inventory(
                                "modular_computers:motherboard_inventory_" .. id,
                                modular_computers.motherboards[item_name]
                                    .detached_inventory)

                inv:set_size("cpu", 1)
                inv:set_size("gpu", 1)
                inv:set_size("hdd", 1)
                inv:set_size("usb", 1)

                modular_computers.motherboards[item_name].formspec =
                    function(_)
                        return "size[10,3]" .. "bgcolor[#FF0000]" ..
                                   "label[1,1;Inventory was reset as the motherboard was detached.]" ..
                                   "label[1,1.5;Right-click again to access a new inventory.]"
                    end
            else
                modular_computers.motherboards[item_name].formspec =
                    modular_computers.motherboards[item_name].original_formspec
            end

            local formname = "modular_computers:motherboard_" .. item_name ..
                                 "_" .. id .. "_formspec"
            minetest.log("Showing motherboard formspec")
            minetest.show_formspec(player:get_player_name(), formname,
                                   modular_computers.motherboards[item_name]
                                       .formspec(id))

            -- Return the (possibly modified) itemstack
            return itemstack
        end
    })
    modular_computers.register_bulk_recipes("motherboard_" .. item_name,
                                            item_recipes)
end
