minetest.register_on_mods_loaded(function()
    local inventory_ids = modular_computers.motherboard.list_saved_inventories()
    for _, id in ipairs(inventory_ids) do
        if id then modular_computers.motherboard.load_inventory(id) end
    end
end)

minetest.register_on_shutdown(function()
    -- Gets rid of unused inventories
    modular_computers.motherboard.prune_inventories()
end)
