modular_computers.register_motherboard("tier_1", "Tier 1", nil, {
    {
        { "default", "basic_materials" }, {
        {
            "default:steel_ingot", "basic_materials:copper_wire",
            "default:steel_ingot"
        }, {
        "basic_materials:copper_wire", "basic_materials:ic",
        "basic_materials:copper_wire"
    },
        {
            "default:steel_ingot", "basic_materials:copper_wire",
            "default:steel_ingot"
        }
    }
    }, {
    { "default", "mesecons" }, {
    {
        "default:steel_ingot", "default:copper_ingot",
        "default:steel_ingot"
    }, {
    "default:copper_ingot",
    "mesecons_luacontroller:luacontroller0000",
    "default:copper_ingot"
},
    {
        "default:steel_ingot", "default:copper_ingot",
        "default:steel_ingot"
    }
}
}, {
    { "default" }, {
    {
        "default:steel_ingot", "default:steel_ingot",
        "default:steel_ingot"
    },
    {
        "default:steel_ingot", "default:mese_crystal",
        "default:steel_ingot"
    },
    {
        "default:steel_ingot", "default:steel_ingot",
        "default:steel_ingot"
    }
}
}, {
    { "mcl_core" }, {
    {
        "mcl_core:iron_ingot", "mcl_copper:copper_ingot",
        "mcl_core:iron_ingot"
    }, {
    "mcl_copper:copper_ingot", "mesecons_torch:redstoneblock",
    "mcl_copper:copper_ingot"
},
    {
        "mcl_core:iron_ingot", "mcl_copper:copper_ingot",
        "mcl_core:iron_ingot"
    }
}
}
}, function(id)
    return
        "size[9,10]" ..
        "label[3.5,0;" .. modular_computers.S("Motherboard") .. "]" ..
        "label[0,1;" .. modular_computers.S("CPU") .. "]" ..
        "list[detached:modular_computers:motherboard_inventory_" .. id .. ";cpu;3,1;1,1;]" ..
        "label[0,2;" .. modular_computers.S("GPU") .. "]" ..
        "list[detached:modular_computers:motherboard_inventory_" .. id .. ";gpu;3,2;1,1;]" ..
        "label[0,3;" .. modular_computers.S("Hard Drive") .. "]" ..
        "list[detached:modular_computers:motherboard_inventory_" .. id .. ";hdd;3,3;1,1;]" ..
        "label[0,4;" .. modular_computers.S("USB") .. "]" ..
        "list[detached:modular_computers:motherboard_inventory_" .. id .. ";usb;3,4;1,1;]" ..
        "list[current_player;main;0,5;9,1;]" ..
        "list[current_player;main;0,6.2;9,3;9]" ..
        "listring[]"
end, 1)
