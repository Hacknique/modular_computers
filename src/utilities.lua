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

modular_computers.itemstack = {}


modular_computers.contexts = {}

function modular_computers.get_context(name)
    local context = modular_computers.contexts[name] or {}
    modular_computers.contexts[name] = context
    return context
end

function modular_computers.inventory_from_player_name(player_name)
    local player = minetest.get_player_by_name(player_name)

    if player then
        local inventory = player:get_inventory()
        if inventory then
            return inventory
        else
            minetest.log("error",
                "Failed to get inventory for player " .. player_name)
            return nil
        end
    else
        minetest.log("error", "Player " .. player_name .. " not found")
        return nil
    end
end

function modular_computers.inventory_from_string(inv_string)
    -- Ensure inv_string is a string to prevent errors with string.match
    if type(inv_string) ~= "string" then
        error("Expected a string, got " .. type(inv_string))
    end

    if string.match(inv_string, "^player:") then
        local pattern = "^player:(.*)$"
        local name = string.match(inv_string, pattern)
        return modular_computers.inventory_from_player_name(name)
    elseif string.match(inv_string, "^nodemeta:") then
        local pattern = "^nodemeta:(%d+),(%d+),(%d+)$"
        local x, y, z = string.match(inv_string, pattern)
        x = tonumber(x)
        y = tonumber(y)
        z = tonumber(z)

        local meta = minetest.get_meta({ x = x, y = y, z = z })
        local inventory = meta:get_inventory()
        return inventory
    elseif string.match(inv_string, "^detached:") then
        local pattern = "^detached:(.*)$"
        local name = string.match(inv_string, pattern)
        return minetest.get_inventory({ type = "detached", name = name })
    else
        return nil
    end
end

function modular_computers.generate_id(player_name)
    local current_time = tostring(os.time())
    local hash = minetest.get_password_hash(player_name, current_time)
    local sanitized_string = string.gsub(hash, "[^%w]", "")
    return sanitized_string
end

function modular_computers.register_bulk_recipes(item_name, item_recipes)
    -- Iterate through an array of recipes
    modular_computers:act(minetest.serialize(item_recipes))
    for _, item in ipairs(item_recipes) do
        -- The first element of item is the mod list, the second element is the recipe
        local mods = item[1]
        local recipe = item[2]
        local output_recipe = recipe -- Initialize output_recipe with the original recipe
        modular_computers:act(minetest.serialize(mods))
        modular_computers:act(minetest.serialize(recipe))

        -- Assume all required mods are loaded, and set this flag to false if any are missing
        local all_mods_loaded = true
        for _, mod in ipairs(mods) do
            if not minetest.get_modpath(mod) then -- Corrected function name from modpath to get_modpath
                all_mods_loaded = false           -- If any required mod is not loaded, set flag to false
                break                             -- No need to check further mods if one is missing
            end
        end

        -- If all required mods are loaded, register the recipe
        if all_mods_loaded then
            minetest.register_craft({
                output = "modular_computers:" .. item_name,
                recipe = output_recipe
            })
            break
        end
    end
end

function modular_computers.find_itemstack_with_metafield(inventory,
                                                         target_field,
                                                         target_value)
    -- Iterate through all lists in the inventory
    for listname, list in pairs(inventory:get_lists()) do
        -- Iterate through all item stacks in the list
        for index, stack in ipairs(list) do
            modular_computers:act("Metadata for itemstack in " .. listname ..
                ": " ..
                minetest.serialize(
                    stack:get_meta():to_table()))
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
function modular_computers:log(level, text)
    minetest.log(level, "[modular_computers]:\t" .. text)
end

function modular_computers:err(text) modular_computers:log("error", text) end

function modular_computers:warn(text) modular_computers:log("warning", text) end

function modular_computers:act(text) modular_computers:log("action", text) end

function modular_computers:info(text) modular_computers:log("info", text) end

function modular_computers:verbose(text) modular_computers:log("verbose", text) end
