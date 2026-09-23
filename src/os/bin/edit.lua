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

-- A text editor for files on the computer's hard drive, shown as a formspec

local S = modular_computers.S
local F = minetest.formspec_escape
local command = modular_computers.command
local drive = modular_computers.os.fs.drive
local files = modular_computers.os.files

local FORMNAME = "modular_computers:editor"
local MAX_SIZE = 64 * 1024

local function editor_formspec(editor, content, message)
    return table.concat({
        "formspec_version[6]",
        "size[18,11]",
        "no_prepend[]",
        "bgcolor[#000000;false]",
        "style_type[textarea;font=mono;textcolor=#D0D0D0]",
        "style_type[label;font=mono;textcolor=#D0D0D0]",
        "label[0.35,0.4;", F(editor.read_only and S("@1 (read-only)", editor.path) or editor.path), "]",
        "textarea[0.35,0.8;17.3,9.1;content;;", F(content), "]",
        message and ("label[0.35,10.45;" .. F(message) .. "]") or "",
        editor.read_only and "" or ("button[12.25,10.1;2.6,0.7;save;" .. F(S("Save")) .. "]"),
        "button[15.05,10.1;2.6,0.7;close;" .. F(S("Close")) .. "]",
    })
end

command.register("edit", files.command(S("Edit a file"), function(m, fs, path)
    local player_name = command.get_player_name()
    if not path then
        error("usage: edit <file>", 0)
    elseif not player_name then
        error("edit: no player to show the editor to", 0)
    end
    local target = files.resolve(m, path)
    if fs.isDirectory(target) then
        error("edit: " .. path .. ": is a directory", 0)
    end
    local content = ""
    if fs.exists(target) then
        content = files.read(m, target)
    end
    if #content > MAX_SIZE then
        error("edit: " .. path .. ": file is too large", 0)
    end
    local editor = {
        pos = vector.new(m.pos.x, m.pos.y, m.pos.z),
        drive_id = m.drive,
        path = target,
        read_only = modular_computers.machine.ROM[target] ~= nil,
    }
    local context = modular_computers.get_context(player_name)
    context.editor = editor
    -- The terminal isn't shown again after this command, or when programs write to it, so
    -- the editor stays open
    context.editor_opened = true
    context.computer_pos = nil
    minetest.show_formspec(player_name, FORMNAME, editor_formspec(editor, content))
end))

-- Saves the text of the editor, returning a message for the player
local function save(player_name, editor, content)
    local pos = editor.pos
    if not modular_computers.computer.is_tower(pos) then
        return S("The computer is gone.")
    end
    if minetest.is_protected(pos, player_name) then
        minetest.record_protection_violation(pos, player_name)
        return S("The computer is protected.")
    end
    local stack = minetest.get_meta(pos):get_inventory():get_stack("hdd", 1)
    if stack:get_meta():get_string("drive_id") ~= editor.drive_id then
        return S("The hard drive was taken out.")
    end
    if #content > MAX_SIZE then
        return S("The file is too large.")
    end
    local capacity = drive.CAPACITY[modular_computers.hardware.get_tier(stack, "hdd")] or drive.CAPACITY[1]
    local ok, err = drive.write(editor.drive_id, editor.path, content, capacity)
    if not ok then
        return S("Could not save: @1", err)
    end
    return S("Saved @1", editor.path)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= FORMNAME then
        return false
    end
    local player_name = player:get_player_name()
    local context = modular_computers.get_context(player_name)
    local editor = context.editor
    if not editor then
        return true
    end
    local content = (fields.content or ""):gsub("\r\n?", "\n")
    if fields.save and not editor.read_only then
        local message = save(player_name, editor, content)
        minetest.show_formspec(player_name, FORMNAME, editor_formspec(editor, content, message))
    elseif fields.close then
        context.editor = nil
        modular_computers.computer.open_terminal(player_name, editor.pos)
    elseif fields.quit then
        context.editor = nil
    end
    return true
end)
