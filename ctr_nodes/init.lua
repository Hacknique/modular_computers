-- This file is part of ComputerTest Redo.

-- ComputerTest Redo is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- ComputerTest Redo is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
-- You should have received a copy of the GNU Affero General Public License along with ComputerTest Redo. If not, see <https://www.gnu.org/licenses/>.
-- The license is included in the project root under the file labeled LICENSE. All files not otherwise specified under a different license shall be put under this license.

ctr = {}

ctr.mod = {}

ctr.mod.name = minetest.get_current_modname()
ctr.mod.path = minetest.get_modpath(ctr.mod.name)

ctr.S = minetest.get_translator(ctr.mod.name)

-- logging functions
function ctr:log(level, text) minetest.log(level, "[ctr]: " .. text) end

function ctr:err(text) ctr:log("error", text) end

function ctr:warn(text) ctr:log("warning", text) end

function ctr:act(text) ctr:log("action", text) end

function ctr:info(text) ctr:log("info", text) end

function ctr:verbose(text) ctr:log("verbose") end

function load_mod_scripts()
    local scripts_path =  ctr.mod.path .. "/src/"
    local script_files_list = minetest.get_dir_list(scripts_path, false)  -- Get list of files in scripts_path
    local argCount = #script_files_list  -- Store the count of files

    for i, v in ipairs(script_files_list) do  -- Iterate over the files
        local script_name = v:match("(.+).lua")  -- Remove .lua suffix
        if script_name then  -- Ensure the file is a Lua script
            ctr:act("loading script '" .. script_name .. "' (" .. i .. "/" .. argCount .. ")")
            dofile(scripts_path .. v)
        end
    end
end

load_mod_scripts()  -- Call the function with no arguments


