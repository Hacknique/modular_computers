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

-- Data cards: a "data" component with hashing, encoding, compression and random bytes,
-- like the data card of OpenComputers

local components = modular_computers.components
local sandbox = modular_computers.sandbox

local data = {}
modular_computers.data_card = data

-- The largest input the card takes, and the largest a compressed input may be
data.LIMIT = 64 * 1024
data.INFLATE_LIMIT = 8 * 1024

local bit = rawget(_G, "bit")

local crc_table
local function crc32(input)
    if not crc_table then
        crc_table = {}
        for i = 0, 255 do
            local crc = i
            for _ = 1, 8 do
                if bit.band(crc, 1) == 1 then
                    crc = bit.bxor(bit.rshift(crc, 1), 0xEDB88320)
                else
                    crc = bit.rshift(crc, 1)
                end
            end
            crc_table[i] = crc
        end
    end
    local crc = 0xFFFFFFFF
    for i = 1, #input do
        crc = bit.bxor(bit.rshift(crc, 8), crc_table[bit.band(bit.bxor(crc, input:byte(i)), 0xFF)])
    end
    crc = bit.bxor(crc, 0xFFFFFFFF) % 4294967296
    return string.char(math.floor(crc / 16777216) % 256, math.floor(crc / 65536) % 256,
        math.floor(crc / 256) % 256, crc % 256)
end

local function input(value, limit)
    if type(value) ~= "string" then
        error("bad argument #1 (string expected, got " .. type(value) .. ")", 0)
    end
    if #value > (limit or data.LIMIT) then
        error("data is too long", 0)
    end
    -- Charge for work done in C, about one instruction per 16 bytes
    sandbox.charge(#value / 16)
    return value
end

components.types.data = {
    getLimit = function() return data.LIMIT end,
    crc32 = function(_, _, value)
        if not bit then
            error("crc32 is unavailable", 0)
        end
        value = input(value)
        sandbox.charge(#value * 4)
        return crc32(value)
    end,
    sha1 = function(_, _, value) return minetest.sha1(input(value), true) end,
    sha256 = function(_, _, value)
        if not minetest.sha256 then
            error("sha256 is unavailable", 0)
        end
        return minetest.sha256(input(value), true)
    end,
    encode64 = function(_, _, value)
        local encoded = minetest.encode_base64(input(value))
        -- With padding, like everywhere else
        return encoded .. string.rep("=", (4 - #encoded % 4) % 4)
    end,
    decode64 = function(_, _, value)
        local result = minetest.decode_base64(input(value))
        if not result then
            return nil, "invalid base64"
        end
        return result
    end,
    deflate = function(_, _, value) return minetest.compress(input(value), "deflate") end,
    inflate = function(_, _, value)
        local ok, result = pcall(minetest.decompress, input(value, data.INFLATE_LIMIT), "deflate")
        if not ok or type(result) ~= "string" then
            return nil, "invalid data"
        end
        if #result > data.LIMIT * 16 then
            return nil, "data is too long"
        end
        return result
    end,
    random = function(_, _, count)
        if type(count) ~= "number" or count < 1 or count > 1024 then
            error("bad argument #1 (number between 1 and 1024 expected)", 0)
        end
        count = math.floor(count)
        if data.secure_random == nil then
            local ok, secure = pcall(function() return SecureRandom() end)
            data.secure_random = ok and secure or false
        end
        if data.secure_random then
            return data.secure_random:next_bytes(count)
        end
        local bytes = {}
        for i = 1, count do
            bytes[i] = string.char(math.random(0, 255))
        end
        return table.concat(bytes)
    end,
}

components.cards.data = function(m, address, slot)
    components.add(m, address, "data", slot)
end
