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

function modular_computers.motherboard.save_inventory(id)
    -- Get the inventory
    local inv = modular_computers.motherboard.get_inventory(id)

    -- Check if inventory retrieval was successful
    if not inv then
        modular_computers:err("Failed to get inventory for id: " .. id)
        return
    end

    -- Initialize a table to hold the inventory data
    local inv_data = {}

    -- Iterate through all lists in the inventory
    for listname, list in pairs(inv:get_lists()) do
        -- Create a new list to hold item data
        local new_list = {}

        -- Iterate through all items in the list
        for i, stack in ipairs(list) do
            if stack:is_empty() then
                -- If the stack is empty, set the item data to a empty item
                new_list[i] = {
                    wear = 0,
                    metadata = "",
                    name = "",
                    count = 0,
                    meta = {}
                }
            else
                -- Save the item data to the new list
                new_list[i] = stack:to_table()
            end
        end

        -- Save the new list to the inventory data table
        inv_data[listname] = new_list
    end

    -- Log the serialized inventory data for debugging
    for listname, list in pairs(inv_data) do
        modular_computers:act(listname .. ": " .. dump(list)) -- Changed from dump(inv_data) to dump(list)
    end

    -- Get the saved inventories data from mod storage
    local saved_inventories = minetest.deserialize(
                                  modular_computers.mod_storage:get_string(
                                      "saved_inventories")) or {}

    -- Save or update the inventory data for this id
    saved_inventories[id] = inv_data -- Directly assign the inv_data here

    -- Save the updated saved inventories data back to mod storage
    modular_computers.mod_storage:set_string("motherboard_inventories",
                                             minetest.serialize(
                                                 saved_inventories))
end

function modular_computers.motherboard.load_inventory(id)
    modular_computers:act("Loading inventory for id: " .. id)

    -- Get the saved inventories data from mod storage
    local saved_inventories = minetest.deserialize(
                                  modular_computers.mod_storage:get_string(
                                      "motherboard_inventories")) or {}

    -- Check if there is saved inventory data for this id
    if saved_inventories[id] then
        local inv_data = saved_inventories[id]
        if inv_data then
            for listname, list in pairs(inv_data) do
                modular_computers:act(listname .. ": " .. dump(list))
            end

            local inv = minetest.create_detached_inventory(
                            "modular_computers:motherboard_inventory_" .. id, {
                    -- Callbacks and other settings for the detached inventory
                    on_put = function(inv, listname, index, stack, player)
                        local inventory_id = modular_computers.motherboard
                                       .get_inventory_id(inv)
                        modular_computers.motherboard.save_inventory(inventory_id)
                    end,
                    on_take = function(inv, listname, index, stack, player)
                        local inventory_id = modular_computers.motherboard
                                       .get_inventory_id(inv)
                        modular_computers.motherboard.save_inventory(inventory_id)
                    end,
                    on_move = function(inv, from_list, from_index, to_list,
                                       to_index, count, player)
                        local inventory_id = modular_computers.motherboard
                                       .get_inventory_id(inv)
                        modular_computers.motherboard.save_inventory(inventory_id)
                    end
                })

            if inv then -- Check if detached inventory creation was successful
                -- Set the size and populate the detached inventory with the saved items
                for listname, list in pairs(inv_data) do
                    inv:set_size(listname, #list)

                    local new_list = {} -- Create a new list to hold the ItemStacks
                    for i, stack_data in ipairs(list) do
                        local stack = ItemStack(stack_data) -- Create a new ItemStack from the table data
                        new_list[i] = stack -- Store the ItemStack in the new list
                    end
                    inv:set_list(listname, new_list) -- Set the new list in the inventory
                end

                local tier_number = modular_computers.motherboard.get_tier(id)
                if tier_number then
                    modular_computers:act(
                        "Tracking Motherboard" .. " With ID " .. id)
                    -- Save the attached inventory
                    item_tracking.track_attached_inventory({
                        name = "modular_computers:motherboard_tier_" ..
                            tostring(tier_number),
                        meta = {id = id}
                    }, function(name)
                        minetest.log("action", "Attached to " .. name)
                        local tracked_inventory =
                            modular_computers.inventory_from_string(name)
                        modular_computers.save_attached_inventory(id, tracked_inventory)
                    end)
                end
            else
                modular_computers:err(
                    "Failed to create detached inventory for id: " .. id)
            end
        else
            modular_computers:err(
                "Could not deserialize inventory data for id: " .. id)
        end
    else
        modular_computers:err("Could not load inventory data for id: " .. id)
    end
    modular_computers:act("Finished loading inventory for id: " .. id)
end

function modular_computers.motherboard.get_inventory_id(inventory)
    local name = inventory:get_location().name
    local id = string.match(name,
                            "^modular_computers:motherboard_inventory_(.*)$")
    return id
end

function modular_computers.motherboard.get_inventory_tier_from_inventory(
    inventory)
    local id = modular_computers.motherboard.get_inventory_id(inventory)
    return modular_computers.motherboard.get_tier(id)
end

function modular_computers.motherboard.get_inventory(id)
    local inventory = minetest.get_inventory({
        type = "detached",
        name = "modular_computers:motherboard_inventory_" .. id
    })
    return inventory
end

function modular_computers.motherboard.delete_inventory(id)
    local inventory = minetest.get_inventory({
        type = "detached",
        name = "modular_computers:motherboard_inventory_" .. id
    })
    if inventory then
        minetest.remove_detached_inventory(
            "modular_computers:motherboard_inventory_" .. id)
        local saved_inventories = minetest.deserialize(
                                      modular_computers.mod_storage:get_string(
                                          "motherboard_inventories")) or {}
        if saved_inventories then
            -- Remove the inventory data for this id from the saved inventories data
            saved_inventories[id] = nil

            -- Save the updated saved inventories data back to mod storage
            modular_computers.mod_storage:set_string("motherboard_inventories",
                                                     minetest.serialize(
                                                         saved_inventories))
            modular_computers:act("Deleted motherboard inventory for id: " .. id)
        end
    else
        modular_computers:warn(
            "Attempted to delete a non-existent inventory with id: " .. id)
    end
end

function modular_computers.motherboard.list_saved_inventories()

    -- Get saved inventories data from mod storage
    local saved_inventories_data = minetest.deserialize(
                                       modular_computers.mod_storage:get_string(
                                           "motherboard_inventories")) or {}

    -- Create an empty table to hold the inventory IDs
    local inventory_ids = {}

    -- Check if there's data, and it's a table
    if saved_inventories_data and type(saved_inventories_data) == "table" then
        -- Iterate through the saved inventories data
        for id, _ in pairs(saved_inventories_data) do
            -- Append the inventory ID to the inventory_ids table
            table.insert(inventory_ids, id)
        end
    else
        modular_computers:warn("No saved inventories found or data is corrupted")
    end

    -- Return the list of inventory IDs
    return inventory_ids
end

function modular_computers.motherboard.check_inventory_exists(id)
    local inventory_ids = modular_computers.motherboard.list_saved_inventories()
    for _, saved_id in ipairs(inventory_ids) do
        if id == saved_id then return true end
    end
    return false
end

function modular_computers.motherboard.prune_inventories()
    -- Get list of saved inventory ids
    local inventory_ids = modular_computers.motherboard.list_saved_inventories()

    modular_computers:act("Pruning inventories" ..
                              minetest.serialize(inventory_ids))
    -- Iterate through the saved inventory ids
    for _, id in ipairs(inventory_ids) do
        -- Check if the inventory exists
        if not modular_computers.motherboard.check_exists(id) then
            -- If the inventory does not exist, delete it
            modular_computers:act("Deleting inventory for id: " .. id)
            modular_computers.motherboard.delete_inventory(id)
            modular_computers.motherboard.delete_attached_inventory(id)
        end
    end
end
