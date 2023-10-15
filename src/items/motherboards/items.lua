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
