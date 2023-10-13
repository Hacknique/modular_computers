local modpath = minetest.get_modpath

modular_computers.motherboards = {}
modular_computers.motherboard = {}

function modular_computers.motherboard.save_inventory(id)
    -- Get the inventory
    local inv = minetest.get_inventory({type="detached", name="modular_computers:motherboard_inventory_" .. id})
    
    -- Check if inventory retrieval was successful
    if not inv then
        minetest.log("error", "Failed to get inventory for id: " .. id)
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
                    meta = {
                        
                    }
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
        minetest.log("action", listname .. ": " .. dump(list))  -- Changed from dump(inv_data) to dump(list)
    end

    -- Get the saved inventories data from mod storage
    local saved_inventories = minetest.deserialize(modular_computers.mod_storage:get_string("saved_inventories")) or {}
    
    -- Save or update the inventory data for this id
    saved_inventories[id] = inv_data  -- Directly assign the inv_data here
    
    -- Save the updated saved inventories data back to mod storage
    modular_computers.mod_storage:set_string("motherboard_inventories", minetest.serialize(saved_inventories))
end


function modular_computers.motherboard.load_inventory(id)
    minetest.log("action", "Loading inventory for id: " .. id)
    
    -- Get the saved inventories data from mod storage
    local saved_inventories = minetest.deserialize(modular_computers.mod_storage:get_string("motherboard_inventories")) or {}
    
    -- Check if there is saved inventory data for this id
    if saved_inventories[id] then
        local inv_data = saved_inventories[id]
        if inv_data then
            for listname, list in pairs(inv_data) do
                minetest.log("action", listname .. ": " .. dump(list))
            end

            local inv = minetest.create_detached_inventory("modular_computers:motherboard_inventory_" .. id, {
                -- Callbacks and other settings for the detached inventory
                on_put = function(inv, listname, index, stack, player)
                    local id = modular_computers.motherboard.get_inventory_id(inv)
                    modular_computers.motherboard.save_inventory(id)
                end,
                on_take = function(inv, listname, index, stack, player)
                    local id = modular_computers.motherboard.get_inventory_id(inv)
                    modular_computers.motherboard.save_inventory(id)
                end, 
                on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                    local id = modular_computers.motherboard.get_inventory_id(inv)
                    modular_computers.motherboard.save_inventory(id)
                end,
            })

            if inv then  -- Check if detached inventory creation was successful
                -- Set the size and populate the detached inventory with the saved items
                for listname, list in pairs(inv_data) do
                    inv:set_size(listname, #list)
                    
                    local new_list = {}  -- Create a new list to hold the ItemStacks
                    for i, stack_data in ipairs(list) do
                        local stack = ItemStack(stack_data)  -- Create a new ItemStack from the table data
                        new_list[i] = stack  -- Store the ItemStack in the new list
                    end
                    inv:set_list(listname, new_list)  -- Set the new list in the inventory
                end
            else
                minetest.log("error", "Failed to create detached inventory for id: " .. id)
            end
        else
            minetest.log("error", "Could not deserialize inventory data for id: " .. id)
        end
    else
        minetest.log("error", "Could not load inventory data for id: " .. id)
    end
    minetest.log("action", "Finished loading inventory for id: " .. id)
end




function modular_computers.motherboard.get_inventory_id(inventory)
    local name = inventory:get_location().name
    local id = string.match(name, "modular_computers:motherboard_inventory_(.+)")
    return id
end

function modular_computers.motherboard.get_inventory(id)
    local inventory = minetest.get_inventory({type="detached", name="modular_computers:motherboard_inventory_"..id})
    return inventory
end

function modular_computers.motherboard.delete_inventory(id)
    local inventory = minetest.get_inventory({type="detached", name="modular_computers:motherboard_inventory_"..id})
    if inventory then
        minetest.remove_detached_inventory("modular_computers:motherboard_inventory_"..id)
    else
        minetest.log("warning", "Attempted to delete a non-existent inventory with id: " .. id)
    end
end

function modular_computers.motherboard.list_saved_inventories()

    -- Get saved inventories data from mod storage
    local saved_inventories_data = minetest.deserialize(modular_computers.mod_storage:get_string("motherboard_inventories")) or {}

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
        minetest.log("warning", "No saved inventories found or data is corrupted")
    end

    -- Return the list of inventory IDs
    return inventory_ids
end

function modular_computers.motherboard.check_exists(id)
    -- Log the id being checked
    minetest.log("action", "Checking existence for id: " .. tostring(id))
    
    local attached_inventory = modular_computers.motherboard.get_attached_inventory(id)
    
    -- Log the attached_inventory value
    minetest.log("action", "Attached inventory: " .. tostring(attached_inventory))
    
    if attached_inventory == nil or attached_inventory == {} then  -- checking for nil or empty table
        return false
    else
        local inventory = minetest.get_inventory(attached_inventory)
        if inventory then
            if modular_computers.find_itemstack_with_metafield(inventory, "id", id) then
                return true
            else
                return false
            end
        else
            -- Log an error if the inventory is nil
            minetest.log("error", "Failed to get inventory for id: " .. id)
            return false
        end
    end
end



function modular_computers.motherboard.prune_inventories()
    -- Get list of saved inventory ids
    local inventory_ids = modular_computers.motherboard.list_saved_inventories()

    -- Iterate through the saved inventory ids
    for _, id in ipairs(inventory_ids) do
        -- Check if the inventory exists
        if not modular_computers.motherboard.check_exists(id) then
            -- If the inventory does not exist, delete it
            modular_computers.motherboard.delete_inventory(id)
            modular_computers.motherboard.delete_attached_inventory(id)
        end
    end
end

function modular_computers.motherboard.save_attached_inventory(id, attached_inventory)
    -- Get the saved inventories data from mod storage
    local motherboard_attached_inventories = minetest.deserialize(modular_computers.mod_storage:get_string("motherboard_attached_inventories")) or {}
    
    -- Save or update the inventory data for this id
    motherboard_attached_inventories[id] = attached_inventory  -- Directly assign the inv_data here
    
    -- Save the updated saved inventories data back to mod storage
    modular_computers.mod_storage:set_string("motherboard_attached_inventories", minetest.serialize(motherboard_attached_inventories))
end

function modular_computers.motherboard.get_attached_inventory(id)
    local motherboard_attached_inventories = minetest.deserialize(modular_computers.mod_storage:get_string("motherboard_attached_inventories")) or {}
    return motherboard_attached_inventories[id]
end

function modular_computers.motherboard.delete_attached_inventory(id)
    local motherboard_attached_inventories = minetest.deserialize(modular_computers.mod_storage:get_string("motherboard_attached_inventories")) or {}
    motherboard_attached_inventories[id] = nil
    modular_computers.mod_storage:set_string("motherboard_attached_inventories", minetest.serialize(motherboard_attached_inventories))
end




function modular_computers.register_motherboard(item_name, item_description, item_image, item_recipes, formspec, tier_number)
    modular_computers.motherboards[item_name] = {
        formspec = formspec
    }
    minetest.register_craftitem("modular_computers:motherboard_"..item_name, {
        description = item_description .. " Motherboard",
        inventory_image = item_image,

        on_put = function(inv, listname, index, stack, player)
            local id = modular_computers.motherboard.get_inventory_id(inv)
            local attached_inventory = inv:get_location()
            modular_computers.motherboard.save_attached_inventory(id, attached_inventory)
            minetest.log("action", "Put motherboard in " .. attached_inventory)
        end, 
        on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
            local id = modular_computers.motherboard.get_inventory_id(inv)
            local attached_inventory = inv:get_location()
            modular_computers.motherboard.save_attached_inventory(id, attached_inventory)
            minetest.log("action", "Moved motherboard to " .. attached_inventory)
        end,

        on_secondary_use = function(itemstack, player, pointed_thing)
            -- Get the player's name
            local player_name = player:get_player_name()
            
            -- Get the item's metadata
            local meta = itemstack:get_meta()
            
            -- Check if the 'id' field is not set in the metadata
            if meta:get_string("id") == "" then
                -- If not set, generate a new id using the provided function
                local new_id = modular_computers.generate_id(player_name)

                local inv = minetest.create_detached_inventory("modular_computers:motherboard_inventory_"..new_id, {
                    --allow_put = function(inv, listname, index, stack, player),
                        
                    --end,
                    
                    on_put = function(inv, listname, index, stack, player)
                        local id = modular_computers.motherboard.get_inventory_id(inv)
                        modular_computers.motherboard.save_inventory(id)
                    end,
                    on_take = function(inv, listname, index, stack, player)
                        local id = modular_computers.motherboard.get_inventory_id(inv)
                        modular_computers.motherboard.save_inventory(id)
                    end, 
                    on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                        local id = modular_computers.motherboard.get_inventory_id(inv)
                        modular_computers.motherboard.save_inventory(id)
                    end,
                    
                })
                
                inv:set_size("cpu", 1)
                inv:set_size("gpu", 1)
                inv:set_size("hdd", 1)
                inv:set_size("usb", 1)
                
                -- Set the 'id' field in the metadata
                meta:set_string("id", new_id)
            end

            -- Get metafield: id
            local id = meta:get_string("id")

            -- Set Attached Inventory
            local player_name = player:get_player_name()
            local attached_inventory = {type="player", name=player_name}
            minetest.log("action", "Attached inventory: " .. minetest.serialize(attached_inventory))
            if attached_inventory and type(attached_inventory) == "table" then
                if attached_inventory ~= modular_computers.motherboard.get_attached_inventory(id) then
                    minetest.log("action", "Motherboard moved to " .. minetest.serialize(attached_inventory))
                    modular_computers.motherboard.save_attached_inventory(id, attached_inventory)
                else
                    minetest.log("action", "Motherboard already in " .. minetest.serialize(attached_inventory))
                end
            else
                minetest.log("error", "Invalid attached inventory for id: " .. id .. " - " .. minetest.serialize(attached_inventory))
            end

            local formname = "modular_computers:motherboard_"..item_name.."_"..id.."_formspec"
            minetest.log("Showing motherboard formspec")
            minetest.show_formspec(player:get_player_name(), formname, modular_computers.motherboards[item_name].formspec(id))
            
            -- Return the (possibly modified) itemstack
            return itemstack
        end})
    modular_computers.register_bulk_recipes("motherboard_"..item_name, item_recipes)
end

modular_computers.register_motherboard("tier_1", "Tier 1", nil, {
    {{"default", "basic_materials"}, {
        {"default:steel_ingot", "basic_materials:copper_wire", "default:steel_ingot"},
        {"basic_materials:copper_wire", "basic_materials:ic", "basic_materials:copper_wire"},
        {"default:steel_ingot", "basic_materials:copper_wire", "default:steel_ingot"}
    }},
    {{"default", "mesecons"}, {
        {"default:steel_ingot", "default:copper_ingot", "default:steel_ingot"},
        {"default:copper_ingot", "mesecons_luacontroller:luacontroller0000", "default:copper_ingot"},
        {"default:steel_ingot", "default:copper_ingot", "default:steel_ingot"}
    }},
    {{"default"}, {
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
        {"default:steel_ingot", "default:mese_crystal", "default:steel_ingot"},
        {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"}
    }},
    {{"mcl_core"}, {
        {"mcl_core:iron_ingot", "mcl_copper:copper_ingot", "mcl_core:iron_ingot"},
        {"mcl_copper:copper_ingot", "mesecons_torch:redstoneblock", "mcl_copper:copper_ingot"},
        {"mcl_core:iron_ingot", "mcl_copper:copper_ingot", "mcl_core:iron_ingot"}
    }}
}, function (id) return "size[9,10]" ..
    "label[3.5,0;" .. modular_computers.S("Motherboard") .. "]" ..
    "label[0,1;" .. modular_computers.S("CPU") .. "]" ..
    "list[detached:modular_computers:motherboard_inventory_"..id..";cpu;3,1;1,1;]" ..
    "label[0,2;" .. modular_computers.S("GPU") .. "]" ..
    "list[detached:modular_computers:motherboard_inventory_"..id..";gpu;3,2;1,1;]" ..
    "label[0,3;" .. modular_computers.S("Hard Drive") .. "]" ..
    "list[detached:modular_computers:motherboard_inventory_"..id..";hdd;3,3;1,1;]" ..
    "label[0,4;" .. modular_computers.S("USB") .. "]" ..
    "list[detached:modular_computers:motherboard_inventory_"..id..";usb;3,4;1,1;]" ..
    "list[current_player;main;0,5;9,1;]" ..
    "list[current_player;main;0,6.2;9,3;9]" ..
    "listring[]"
    
end, 1)

minetest.register_on_mods_loaded(function()
    local inventory_ids = modular_computers.motherboard.list_saved_inventories()
    for _, id in ipairs(inventory_ids) do
        modular_computers.motherboard.load_inventory(id)
    end
end)

minetest.register_on_shutdown(function()
    -- Gets rid of unused inventories
    modular_computers.motherboard.prune_inventories()
end)