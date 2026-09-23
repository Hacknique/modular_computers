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

-- The computer tower holds a motherboard and the components installed on it. Components can
-- only be installed on a motherboard of at least their tier, and leave the tower with it.

local S = modular_computers.S
local F = minetest.formspec_escape
local hardware = modular_computers.hardware
local redstone = modular_computers.redstone
local computer = modular_computers.computer
local display = modular_computers.display

local FORMNAME = "modular_computers:tower_formspec"
local SLOTS = {
    { list = "motherboard", x = 0.375 },
    { list = "cpu", x = 2.5 },
    { list = "gpu", x = 3.75 },
    { list = "ram", x = 5 },
    { list = "hdd", x = 6.25 },
}

local function tower_formspec(pos, player)
    local inv = minetest.get_meta(pos):get_inventory()
    local location = "nodemeta:" .. pos.x .. "," .. pos.y .. "," .. pos.z
    local columns = player:get_inventory():get_size("main") >= 36 and 9 or 8
    local mcl = minetest.global_exists("mcl_formspec")
    local function label(x, y, text)
        text = mcl and minetest.colorize(mcl_formspec.label_color, text) or text
        return "label[" .. x .. "," .. y .. ";" .. F(text) .. "]"
    end
    local function slot_backgrounds(x, y, w, h)
        return mcl and mcl_formspec.get_itemslot_bg_v4(x, y, w, h) or ""
    end

    local formspec = {
        "formspec_version[4]",
        "size[", 0.5 + 1.25 * columns, ",10.425]",
        label(0.375, 0.375, S("Computer Tower")),
    }
    for _, slot in ipairs(SLOTS) do
        table.insert(formspec, slot_backgrounds(slot.x, 0.9, 1, 1))
        if inv:is_empty(slot.list) then
            table.insert(formspec, "image[" .. slot.x .. ",0.9;1,1;" ..
                F("modular_computers_" .. slot.list .. "_tier_1.png^[opacity:64") .. "]")
        end
        table.insert(formspec, "list[" .. location .. ";" .. slot.list .. ";" .. slot.x .. ",0.9;1,1;]")
        table.insert(formspec, label(slot.x, 2.2, hardware.NAMES[slot.list]))
    end

    local missing = computer.get_missing(pos)
    local status
    if #missing == 0 then
        status = minetest.colorize("#3CB43C", S("Running"))
    else
        status = minetest.colorize("#D24040", S("Needs: @1", table.concat(missing, ", ")))
    end
    table.insert(formspec, "label[0.375,3.1;" .. F(status) .. "]")
    local tier = hardware.get_tier(inv:get_stack("motherboard", 1), "motherboard")
    if tier > 0 then
        table.insert(formspec, label(0.375, 3.6, S("Holds components up to tier @1", tier)))
    end

    table.insert(formspec, label(0.375, 4.7, S("Inventory")))
    table.insert(formspec, slot_backgrounds(0.375, 5.1, columns, 3))
    table.insert(formspec, "list[current_player;main;0.375,5.1;" .. columns .. ",3;" .. columns .. "]")
    table.insert(formspec, slot_backgrounds(0.375, 9.05, columns, 1))
    table.insert(formspec, "list[current_player;main;0.375,9.05;" .. columns .. ",1;]")
    return table.concat(formspec)
end

local function show_formspec(player, pos)
    minetest.show_formspec(player:get_player_name(), FORMNAME, tower_formspec(pos, player))
end

-- Keeps the components in the tower stored on its motherboard, so they leave the tower with it
local function store_components(inv)
    local motherboard = inv:get_stack("motherboard", 1)
    if motherboard:is_empty() then
        return
    end
    local installed = {}
    for _, kind in ipairs(hardware.COMPONENTS) do
        local stack = inv:get_stack(kind, 1)
        if not stack:is_empty() then
            installed[kind] = stack:to_string()
        end
    end
    hardware.set_installed(motherboard, installed)
    inv:set_stack("motherboard", 1, motherboard)
end

local function is_monitor_item(stack)
    return minetest.get_item_group(stack:get_name(), "modular_computer_monitor") > 0
end

local function on_rightclick(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then
        return itemstack
    end
    -- Holding a monitor puts it on the tower instead
    if pointed_thing and is_monitor_item(itemstack) then
        return minetest.item_place_node(itemstack, clicker, pointed_thing)
    end
    local player_name = clicker:get_player_name()
    if minetest.is_protected(pos, player_name) then
        minetest.record_protection_violation(pos, player_name)
        return itemstack
    end
    show_formspec(clicker, pos)
    return itemstack
end

local function drop_motherboard(pos, motherboard)
    if motherboard and motherboard ~= "" and not ItemStack(motherboard):is_empty() then
        minetest.add_item(pos, motherboard)
    end
end

for mask = 0, redstone.MAX_MASK do
    local groups = { cracky = 2, pickaxey = 1, modular_computer_tower = 1, redstone_not_conductive = 1 }
    if mask ~= 0 then
        groups.not_in_creative_inventory = 1
        groups.not_in_craft_guide = 1
    end

    minetest.register_node(redstone.node_name(mask), {
        description = S("Computer Tower"),
        tiles = {
            "modular_computers_tower_top.png", -- Y+
            "computer_side.png", -- Y-
            "computer_side.png", -- X+
            "computer_side.png", -- X-
            "modular_computers_tower_back.png", -- Z+
            "modular_computers_tower_front.png" -- Z-
        },
        groups = groups,
        is_ground_content = false,
        sounds = computer.stone_sounds(),
        paramtype2 = "facedir",
        stack_max = 1,
        drop = mask ~= 0 and redstone.BASE_NODE or nil,
        _doc_items_create_entry = mask == 0,
        _mcl_hardness = 3.5,
        _mcl_blast_resistance = 3.5,

        on_construct = function(pos)
            local inv = minetest.get_meta(pos):get_inventory()
            for _, slot in ipairs(SLOTS) do
                inv:set_size(slot.list, 1)
            end
            computer.update(pos)
            -- The monitor on top may have been part of another tower's screen
            display.update_near(vector.add(pos, vector.new(0, 1, 0)))
        end,
        on_destruct = display.remove,
        after_destruct = function(pos)
            display.update_near(vector.add(pos, vector.new(0, 1, 0)))
        end,
        after_dig_node = function(pos, _, oldmetadata)
            local lists = oldmetadata and oldmetadata.inventory
            drop_motherboard(pos, lists and lists.motherboard and lists.motherboard[1])
        end,
        on_blast = function(pos)
            drop_motherboard(pos, minetest.get_meta(pos):get_inventory():get_stack("motherboard", 1))
            minetest.remove_node(pos)
        end,

        on_rightclick = on_rightclick,
        on_rotate = redstone.on_rotate,

        allow_metadata_inventory_put = function(pos, listname, _, stack, player)
            local player_name = player:get_player_name()
            local inv = minetest.get_meta(pos):get_inventory()
            if minetest.is_protected(pos, player_name) or not inv:is_empty(listname) then
                return 0
            end
            local tier = hardware.get_tier(stack, listname)
            if listname == "motherboard" or tier == 0 then
                return tier > 0 and 1 or 0
            end
            local motherboard_tier = hardware.get_tier(inv:get_stack("motherboard", 1), "motherboard")
            if motherboard_tier == 0 then
                minetest.chat_send_player(player_name, S("Put a motherboard in the tower first."))
                return 0
            elseif tier > motherboard_tier then
                minetest.chat_send_player(player_name,
                    S("A tier @1 motherboard can't hold tier @2 components.", motherboard_tier, tier))
                return 0
            end
            return 1
        end,
        allow_metadata_inventory_take = function(pos, _, _, stack, player)
            return minetest.is_protected(pos, player:get_player_name()) and 0 or stack:get_count()
        end,
        allow_metadata_inventory_move = function()
            return 0
        end,
        on_metadata_inventory_put = function(pos, listname, _, stack, player)
            local inv = minetest.get_meta(pos):get_inventory()
            if listname == "motherboard" then
                local installed = hardware.get_installed(stack)
                for _, kind in ipairs(hardware.COMPONENTS) do
                    inv:set_stack(kind, 1, ItemStack(installed[kind]))
                end
            else
                store_components(inv)
            end
            computer.update(pos)
            show_formspec(player, pos)
        end,
        on_metadata_inventory_take = function(pos, listname, _, _, player)
            local inv = minetest.get_meta(pos):get_inventory()
            if listname == "motherboard" then
                -- The components left with the motherboard
                for _, kind in ipairs(hardware.COMPONENTS) do
                    inv:set_stack(kind, 1, ItemStack(nil))
                end
            else
                store_components(inv)
            end
            computer.update(pos)
            show_formspec(player, pos)
        end,

        mesecons = redstone.mesecons_def(mask),
        _mcl_redstone = redstone.mcl_redstone_def(mask),
    })
end
