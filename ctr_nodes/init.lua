-- This file is part of ComputerTest Redo.

-- ComputerTest Redo is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
-- ComputerTest Redo is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
-- You should have received a copy of the GNU Affero General Public License along with ComputerTest Redo. If not, see <https://www.gnu.org/licenses/>.
-- The license is included in the project root under the file labeled LICENSE. All files not otherwise specified under a different license shall be put under this license.



-- TODO: remove that message
-- hi james.
-- it's nitro.
-- i had a look at the code and because i was free at the moment/
-- i made my changes. boilerplate, better ways to do things, etc.
-- you gave me the repo access, so i've decided that it's more than ok to
-- make good changes.
-- i have also added translations to ukrainian, because why not.
-- i have also changed init.lua, and i'll do a quick explanation how everything
-- is structured.

-- first of all, `ctrn` is a global, it's used to store... well, global things
-- that every script might need.

-- `ctrn.mod` contains mod info. it's that simple. take a look at the code.
-- `ctrn.S` is a translation unit. it's used to translate in-game strings, like
-- `... = ctrn.S("yomama")` will be translated according to the `locale/ctr_nodes.<lang>.tr`.

-- `ctrn:log,err,warn,act,info,verbose` are all just shortcuts to `minetest.log`.
-- `ctrn.mod.scripts` is an array of relative paths to the scripts. scripts are
-- interpreted automatically in a for loop in an order in which the paths are in
-- the array.

-- hopefully you got what i'm saying. imma go sleep. take care.



ctrn = {}

ctrn.mod = {}

ctrn.mod.name = minetest.get_current_modname()
ctrn.mod.path = minetest.get_modpath(ctrn.mod.name)

ctrn.S = minetest.get_translator(ctrn.mod.name)

-- logging functions
function ctrn:log(level, text) minetest.log(level, "[ctrn]: " .. text) end

function ctrn:err(text) ctrn:log("error", text) end

function ctrn:warn(text) ctrn:log("warning", text) end

function ctrn:act(text) ctrn:log("action", text) end

function ctrn:info(text) ctrn:log("info", text) end

function ctrn:verbose(text) ctrn:log("verbose") end

-- relative paths to scripts
ctrn.mod.scripts = {
    "src/computer_node.lua",
}

for i, v in ipairs(ctrn.mod.scripts) do
    ctrn:act("loading script '" .. v .. "' (" .. i .. "/" .. #ctrn.mod.scripts .. ")")
    dofile(ctrn.mod.path .. "/" .. v)
end
