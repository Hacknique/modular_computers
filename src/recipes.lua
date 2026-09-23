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

    Copyright (c) 2026 James Clarke <james@jamesdavidclarke.com>
]]

-- Recipes name their ingredients by role, and each role uses the first of its items that
-- exists, so the same recipes work in Mineclonia, VoxeLibre and Minetest Game.
local INGREDIENTS = {
    stone = { "mcl_core:stone", "default:stone" },
    glass = { "mcl_panes:pane_natural_flat", "xpanes:pane_natural_flat", "default:glass" },
    iron = { "mcl_core:iron_ingot", "default:steel_ingot" },
    gold = { "mcl_core:gold_ingot", "default:gold_ingot" },
    diamond = { "mcl_core:diamond", "default:diamond" },
    copper = { "mcl_copper:copper_ingot", "default:copper_ingot" },
    redstone = { "mcl_redstone:redstone", "mesecons:redstone", "mesecons:wire_00000000_off",
        "default:mese_crystal_fragment" },
    redstone_block = { "mcl_redstone_torch:redstoneblock", "mesecons_torch:redstoneblock",
        "mesecons_luacontroller:luacontroller0000", "default:mese_crystal" },
    logic = { "mcl_repeaters:repeater_off_1", "mesecons_delayer:delayer_off_1", "basic_materials:ic",
        "default:mese_crystal" },
}

-- Tier 1, 2 and 3 components are made of iron, gold and diamond
local TIER_MATERIALS = { "iron", "gold", "diamond" }

local function find(role)
    for _, item in ipairs(INGREDIENTS[role]) do
        if modular_computers.item_exists(item) then
            return item
        end
    end
end

-- pattern: rows of space separated letters, keys: the role of each letter
local function register(output, pattern, keys)
    local recipe = {}
    for _, line in ipairs(pattern) do
        local row = {}
        for letter in string.gmatch(line, "%S+") do
            local item = find(keys[letter])
            if not item then
                modular_computers:warn("no recipe for " .. output .. ", nothing to use as " .. keys[letter])
                return
            end
            table.insert(row, item)
        end
        table.insert(recipe, row)
    end
    minetest.register_craft({ output = output, recipe = recipe })
end

register("modular_computers:monitor", { "s g s", "s b s", "s s s" },
    { s = "stone", g = "glass", b = "redstone_block" })
register("modular_computers:tower", { "i i i", "i r i", "i c i" },
    { i = "iron", r = "redstone", c = "copper" })

for tier, material in ipairs(TIER_MATERIALS) do
    local keys = { t = material, c = "copper", r = "redstone", b = "redstone_block", l = "logic" }
    local suffix = "_tier_" .. tier
    register("modular_computers:motherboard" .. suffix, { "t c t", "c b c", "t c t" }, keys)
    register("modular_computers:cpu" .. suffix, { "r t r", "t l t", "r t r" }, keys)
    register("modular_computers:gpu" .. suffix, { "t t t", "c l c", "r r r" }, keys)
    register("modular_computers:ram" .. suffix, { "t t t", "r r r" }, keys)
    register("modular_computers:hdd" .. suffix, { "t r t", "r c r", "t r t" }, keys)
end

local card_keys = { i = "iron", g = "gold", w = "glass", c = "copper", r = "redstone", b = "redstone_block",
    l = "logic" }
register("modular_computers:wireless_card_tier_1", { "i r i", "c l c" }, card_keys)
register("modular_computers:wireless_card_tier_2", { "g b g", "c l c" }, card_keys)
register("modular_computers:internet_card", { "w r w", "c l c", "g g g" }, card_keys)
register("modular_computers:data_card", { "i l i", "r c r" }, card_keys)
