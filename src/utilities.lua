modular_computers.itemstack = {}

function modular_computers.generate_id(player_name)
    local current_time = tostring(os.time())
    local hash = minetest.get_password_hash(player_name, current_time)
    local sanitized_string = string.gsub(hash, "[^%w]", "")
    return sanitized_string
end

function modular_computers.register_bulk_recipes(item_name, item_recipes)
    -- Iterate through an array of recipes
    modular_computers:act( minetest.serialize(item_recipes))
    for _, item in ipairs(item_recipes) do
        -- The first element of item is the mod list, the second element is the recipe
        local mods = item[1]
        local recipe = item[2]
        local output_recipe = recipe  -- Initialize output_recipe with the original recipe
        modular_computers:act( minetest.serialize(mods))
        modular_computers:act( minetest.serialize(recipe))

        -- Assume all required mods are loaded, and set this flag to false if any are missing
        local all_mods_loaded = true
        for _, mod in ipairs(mods) do
            if not minetest.get_modpath(mod) then  -- Corrected function name from modpath to get_modpath
                all_mods_loaded = false  -- If any required mod is not loaded, set flag to false
                break  -- No need to check further mods if one is missing
            end
        end

        -- If all required mods are loaded, register the recipe
        if all_mods_loaded then
            minetest.register_craft({
                output = "modular_computers:"..item_name,
                recipe = output_recipe
            })
            break
        end
    end
end

function modular_computers.find_itemstack_with_metafield(inventory, target_field, target_value)
    -- Iterate through all lists in the inventory
    for listname, list in pairs(inventory:get_lists()) do
        -- Iterate through all item stacks in the list
        for index, stack in ipairs(list) do
            modular_computers:act("Metadata for itemstack in " .. listname .. ": " .. minetest.serialize(stack:get_meta():to_table()))
            -- Get the metadata of the item stack
            local meta = stack:get_meta()
            -- Check if the 'id' field in the metadata matches the target id
            if meta:get_string(target_field) == target_value then
                -- If a match is found, return the list name, index, and the item stack itself
                return listname, index, stack
            end
        end
    end
    -- If no match is found, return nil
    return nil
end

-- logging functions
function modular_computers:log(level, text) minetest.log(level, "[modular_computers]:\t" .. text) end

function modular_computers:err(text) modular_computers:log("error", text) end

function modular_computers:warn(text) modular_computers:log("warning", text) end

function modular_computers:act(text) modular_computers:log("action", text) end

function modular_computers:info(text) modular_computers:log("info", text) end

function modular_computers:verbose(text) modular_computers:log("verbose") end