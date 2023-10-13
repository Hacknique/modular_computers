modular_computers.itemstack = {}

function modular_computers.generate_id(player_name)
    local current_time = tostring(os.time())
    local hash = minetest.get_password_hash(player_name, current_time)
    local sanitized_string = string.gsub(hash, "[^%w]", "")
    return sanitized_string
end

function modular_computers.register_bulk_recipes(item_name, item_recipes)
    -- Iterate through an array of recipes
    minetest.log("action", minetest.serialize(item_recipes))
    for _, item in ipairs(item_recipes) do
        -- The first element of item is the mod list, the second element is the recipe
        local mods = item[1]
        local recipe = item[2]
        local output_recipe = recipe  -- Initialize output_recipe with the original recipe
        minetest.log("action", minetest.serialize(mods))
        minetest.log("action", minetest.serialize(recipe))

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
