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

-- Motherboards and the components installed on them, in three tiers each, and expansion cards.
-- A motherboard holds components and cards up to its own tier, and one card for each tier.
-- Installed components are stored in the motherboard's item meta, so they move with it.

local S = modular_computers.S

modular_computers.hardware = {}
local hardware = modular_computers.hardware

hardware.TIERS = 3
-- Components installed on a motherboard, in the order they are shown
hardware.COMPONENTS = { "cpu", "gpu", "ram", "hdd" }
-- Rows of text a GPU of each tier shows on its monitors
hardware.GPU_ROWS = { 12, 16, 20 }
hardware.CARD_SLOTS = 3

hardware.NAMES = {
    motherboard = S("Motherboard"),
    cpu = S("CPU"),
    gpu = S("GPU"),
    ram = S("RAM"),
    hdd = S("Hard Drive"),
    cards = S("Cards"),
}

-- Expansion cards. range is the distance wireless messages reach, in blocks.
hardware.CARDS = {
    { name = "wireless_card_tier_1", type = "wireless", tier = 1, range = 16,
        description = S("Tier 1 Wireless Card"), details = S("Sends messages @1 blocks far", 16) },
    { name = "wireless_card_tier_2", type = "wireless", tier = 2, range = 400,
        description = S("Tier 2 Wireless Card"), details = S("Sends messages @1 blocks far", 400) },
    { name = "internet_card", type = "internet", tier = 2,
        description = S("Internet Card"), details = S("Makes HTTP requests") },
    { name = "data_card", type = "data", tier = 1,
        description = S("Data Card"), details = S("Hashes, encodes and compresses data") },
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

-- Returns the card definition (from hardware.CARDS) of an item, or nil if it isn't a card
function hardware.get_card(stack)
    local def = minetest.registered_items[ItemStack(stack):get_name()]
    return def and def._modular_computers_card
end

-- Items installed on a motherboard are stored as { name, wear, meta } tables
function hardware.stack_data(stack)
    return { name = stack:get_name(), wear = stack:get_wear(), meta = stack:get_meta():to_table().fields }
end

-- Returns the item stored as data by stack_data, or as an item string by older versions
function hardware.make_stack(data)
    if type(data) == "string" then
        return ItemStack(data)
    elseif type(data) ~= "table" or type(data.name) ~= "string" then
        return ItemStack(nil)
    end
    local stack = ItemStack(data.name)
    stack:set_wear(tonumber(data.wear) or 0)
    if type(data.meta) == "table" then
        stack:get_meta():from_table({ fields = data.meta })
    end
    return stack
end

-- Returns the components stored on a motherboard, as item data by kind
function hardware.get_installed(motherboard)
    return minetest.deserialize(motherboard:get_meta():get_string("components")) or {}
end

-- Stores components (item data by kind, and cards as a list of item data by slot) on a
-- motherboard and lists them in its description
function hardware.set_installed(motherboard, installed)
    local meta = motherboard:get_meta()
    local lines = {}
    for _, kind in ipairs(hardware.COMPONENTS) do
        if installed[kind] then
            table.insert(lines, "- " .. hardware.make_stack(installed[kind]):get_short_description())
        end
    end
    for slot = 1, hardware.CARD_SLOTS do
        local card = installed.cards and installed.cards[slot]
        if card then
            table.insert(lines, "- " .. hardware.make_stack(card):get_short_description())
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

for _, card in ipairs(hardware.CARDS) do
    minetest.register_craftitem("modular_computers:" .. card.name, {
        description = card.description .. "\n" .. minetest.colorize("#A0A0A0", card.details),
        inventory_image = "modular_computers_" .. card.name .. ".png",
        stack_max = 1,
        groups = { modular_computers_card = card.tier },
        _modular_computers_card = card,
    })
end
