local modpath = minetest.get_modpath

function modular_computers.register_motherboard(item_name, item_description, item_image, item_recipes)
    minetest.register_craftitem("modular_computers:motherboard_"..item_name, {
        description = item_description .. " Motherboard",
        inventory_image = item_image
    })
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
})