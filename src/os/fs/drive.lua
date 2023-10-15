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

modular_computers.os.fs.drive = {}

DriveTypes = {"hd", "fd"}
-- 1 -> HDD
-- 2 -> FDD

DRIVE_LETTERS = {
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z"
}

function modular_computers.os.fs.drive.create(pos, type_id)
    for index in ipairs(DriveTypes) do
        if index == type_id then
            local computer_meta = minetest.get_meta(pos)
            local n_filesystems = #modular_computers.os.fs.drive.list(pos)
            local drive_name = DriveTypes[index] .. DRIVE_LETTERS[n_filesystems + 1]
            computer_meta:set_string("drive_" .. drive_name, minetest.serialize({}))
        end
    end
end

function modular_computers.os.fs.drive.get(pos)
    local computer_meta = minetest.get_meta(pos)
    local filesystem = computer_meta:get_string("filesystem")
    return minetest.deserialize(filesystem)
end

function modular_computers.os.fs.drive.list(pos)
    local computer_meta = minetest.get_meta(pos)
    local filesystems = {}
    for key, value in pairs(computer_meta:to_table().fields) do
        if string.find(key, "filesystem_") then
            table.insert(filesystems, key)
        end
    end
    return filesystems
end

