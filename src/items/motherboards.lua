local modpath = minetest.get_modpath

modular_computers.motherboards = {}
modular_computers.motherboard = {}

function modular_computers.motherboard.save_inventory(id)
    local inv = minetest.get_inventory({type="detached", name="modular_computers:motherboard_inventory_" .. id})
    local inv_data = {}
    for listname, list in pairs(inv:get_lists()) do
        local list = inv:get_list(listname)
        local new_list = {}
        for i, stack in ipairs(list) do
            if stack:is_empty() then
                goto continue
            end
            new_list[i] = stack:to_table()
            ::continue::
        end
        inv_data[listname] = new_list 
    end
    for listname, list in pairs(inv_data) do
        minetest.log("action", listname .. ": " .. dump(inv_data))
    end
    local serialized_data = minetest.serialize(inv_data)
    modular_computers.mod_storage:set_string("inventory_" .. id, serialized_data)
end

function modular_computers.motherboard.load_inventory(id)
    local serialized_data = modular_computers.mod_storage:get_string("inventory_" .. id)
    if serialized_data and serialized_data ~= "" then
        local inv_data = minetest.deserialize(serialized_data)
        if inv_data then
            local inv = minetest.create_detached_inventory("modular_computers:motherboard_inventory_" .. id, {})
            for listname, list in pairs(inv_data) do
                inv:set_list(listname, list)
            end
        else
            minetest.log("error", "Could not deserialize inventory data for id: " .. id)
        end
    else
        minetest.log("error", "Could not load inventory data for id: " .. id)
    end
end

function modular_computers.motherboard.get_inventory_id(inventory)
    local name = inventory:get_location().name
    local id = string.match(name, "modular_computers:motherboard_inventory_(.+)")
    return id
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
    local saved_inventories_data = minetest.deserialize(modular_computers.mod_storage:get_string("saved_inventories"))

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




function modular_computers.register_motherboard(item_name, item_description, item_image, item_recipes, formspec, tier_number)
    modular_computers.motherboards[item_name] = {
        formspec = formspec
    }
    minetest.register_craftitem("modular_computers:motherboard_"..item_name, {
        description = item_description .. " Motherboard",
        inventory_image = item_image,
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
                
                inv:set_size("cpu", tier_number)
                inv:set_size("gpu", tier_number)
                inv:set_size("hdd", tier_number)
                inv:set_size("usb", tier_number)
                
                -- Set the 'id' field in the metadata
                meta:set_string("id", new_id)
            end
            local id = meta:get_string("id")
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