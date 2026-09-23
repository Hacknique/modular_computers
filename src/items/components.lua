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

-- Motherboards and the components installed on them, in three tiers each.
-- A motherboard holds components up to its own tier. Installed components are
-- stored in the motherboard's item meta, so they move with the motherboard.

local S = modular_computers.S

modular_computers.hardware = {}
local hardware = modular_computers.hardware

hardware.TIERS = 3
-- Components installed on a motherboard, in the order they are shown
hardware.COMPONENTS = { "cpu", "gpu", "ram", "hdd" }
-- Rows of text a GPU of each tier shows on its monitors
hardware.GPU_ROWS = { 12, 16, 20 }

hardware.NAMES = {
    motherboard = S("Motherboard"),
    cpu = S("CPU"),
    gpu = S("GPU"),
    ram = S("RAM"),
    hdd = S("Hard Drive"),
}

local DESCRIPTIONS = {
    motherboard = function(tier) return S("Tier @1 Motherboard", tier) end,
    cpu = function(tier) return S("Tier @1 CPU", tier) end,
    gpu = function(tier) return S("Tier @1 GPU", tier) end,
    ram = function(tier) return S("Tier @1 RAM", tier) end,
    hdd = function(tier) return S("Tier @1 Hard Drive", tier) end,
}

local DETAILS = {
    motherboard = function(tier) return S("Holds components up to tier @1", tier) end,
    gpu = function(tier) return S("Shows @1 rows of text", hardware.GPU_ROWS[tier]) end,
}

-- Returns the tier of an item if it is a component of this kind ("motherboard", "cpu", ...), else 0
function hardware.get_tier(stack, kind)
    return minetest.get_item_group(ItemStack(stack):get_name(), "modular_computers_" .. kind)
end

-- Returns the components stored on a motherboard, as item strings by kind
function hardware.get_installed(motherboard)
    return minetest.deserialize(motherboard:get_meta():get_string("components")) or {}
end

-- Stores components (item strings by kind) on a motherboard and lists them in its description
function hardware.set_installed(motherboard, installed)
    local meta = motherboard:get_meta()
    local lines = {}
    for _, kind in ipairs(hardware.COMPONENTS) do
        if installed[kind] then
            table.insert(lines, "- " .. ItemStack(installed[kind]):get_short_description())
        end
    end
    if #lines == 0 then
        meta:set_string("components", "")
        meta:set_string("description", "")
        return
    end
    meta:set_string("components", minetest.serialize(installed))
    meta:set_string("description", motherboard:get_definition().description .. "\n" .. table.concat(lines, "\n"))
end

for tier = 1, hardware.TIERS do
    for _, kind in ipairs({ "motherboard", "cpu", "gpu", "ram", "hdd" }) do
        local description = DESCRIPTIONS[kind](tier)
        if DETAILS[kind] then
            description = description .. "\n" .. minetest.colorize("#A0A0A0", DETAILS[kind](tier))
        end
        minetest.register_craftitem("modular_computers:" .. kind .. "_tier_" .. tier, {
            description = description,
            inventory_image = "modular_computers_" .. kind .. "_tier_" .. tier .. ".png",
            stack_max = 1,
            groups = { ["modular_computers_" .. kind] = tier },
        })
    end
end
