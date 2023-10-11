-- Load in your textures
local texture_front = "computer_front.png"
local texture_rest = "computer_rest.png"

-- Register the node
minetest.register_node("ctr_nodes:computer", {
    description = "Computer",
    tiles = {
        texture_front,  -- Top face
        texture_rest,   -- Bottom face
        texture_rest,   -- Right face
        texture_rest,   -- Left face
        texture_rest,   -- Back face
        texture_rest,   -- Front face
    },
    groups = {cracky = 2},  -- This makes it breakable with an iron pickaxe
    sounds = default.node_sound_metal_defaults(),
})

-- Check for required mods
if minetest.get_modpath("default") and minetest.get_modpath("mesecons_luacontroller") then
    -- Register the crafting recipe for default and mesecons
    minetest.register_craft({
        output = 'ctr_nodes:computer',
        recipe = {
            {'default:stone', 'default:glass', 'default:stone'},
            {'default:stone', 'mesecons_luacontroller:luacontroller0000', 'default:stone'},
            {'default:stone', 'default:stone', 'default:stone'}
        }
    })
elseif minetest.get_modpath("mcl_core") then
    -- Register the crafting recipe for mcl_core
    minetest.register_craft({
        output = 'ctr_nodes:computer',
        recipe = {
            {'mcl_core:stone', 'mcl_core:glass_pane', 'mcl_core:stone'},
            {'mcl_core:stone', 'mcl_redstone:redstone_block', 'mcl_core:stone'},
            {'mcl_core:stone', 'mcl_core:stone', 'mcl_core:stone'}
        }
    })
end

