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
