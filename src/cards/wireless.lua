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

-- Wireless cards: a "modem" component that sends messages to the modems of other computers
-- in range, like the wireless network cards of OpenComputers. A message reaches a modem that
-- has its port open and is no farther away than the sender's signal strength, and arrives
-- as a "modem_message" signal.

local components = modular_computers.components
local machine = modular_computers.machine

local wireless = {}
modular_computers.wireless = wireless

wireless.MAX_PACKET_SIZE = 8192
wireless.MAX_OPEN_PORTS = 16
-- Packets a modem may send each second, and in a burst
wireless.PACKET_RATE = 16
wireless.PACKET_BURST = 32

local floor, min, max = math.floor, math.min, math.max
local get_us_time = minetest.get_us_time

local function check_port(port)
    if type(port) ~= "number" then
        error("bad argument (number expected, got " .. type(port) .. ")", 0)
    end
    port = floor(port)
    if port < 1 or port > 65535 then
        error("invalid port number", 0)
    end
    return port
end

-- The size of a packet, counted like OpenComputers does
local function packet_size(values)
    local size = 0
    for i = 1, values.n do
        local value = values[i]
        local t = type(value)
        if t == "string" then
            size = size + 2 + #value
        elseif t == "number" then
            size = size + 10
        elseif t == "boolean" or t == "nil" then
            size = size + 6
        else
            error("unsupported data type: " .. t, 0)
        end
    end
    return size
end

-- Takes one packet from the modem's allowance, if it has one left
local function allow_packet(modem)
    local now = get_us_time()
    modem.tokens = min(wireless.PACKET_BURST,
        modem.tokens + (now - modem.refilled) / 1e6 * wireless.PACKET_RATE)
    modem.refilled = now
    if modem.tokens < 1 then
        return false
    end
    modem.tokens = modem.tokens - 1
    return true
end

-- Sends a packet from the modem of machine m to the modem at target, or to all when target is nil
local function transmit(m, modem, target, port, ...)
    local values = { n = select("#", ...), ... }
    if packet_size(values) > wireless.MAX_PACKET_SIZE then
        error("packet too big (max " .. wireless.MAX_PACKET_SIZE .. ")", 0)
    end
    if not allow_packet(modem) then
        return false
    end
    for _, other in pairs(machine.all()) do
        if other ~= m and not other.stopping then
            local distance = vector.distance(m.pos, other.pos)
            if distance <= modem.strength then
                for address, component in pairs(other.components) do
                    if component.type == "modem" and component.ports[port]
                            and (target == nil or target == address) then
                        machine.push_signal(other, "modem_message", address, modem.address, port, distance,
                            unpack(values, 1, values.n))
                    end
                end
            end
        end
    end
    return true
end

components.types.modem = {
    isWireless = function() return true end,
    isWired = function() return false end,
    maxPacketSize = function() return wireless.MAX_PACKET_SIZE end,
    getStrength = function(_, modem) return modem.strength end,
    setStrength = function(_, modem, strength)
        if type(strength) ~= "number" then
            error("bad argument #1 (number expected, got " .. type(strength) .. ")", 0)
        end
        modem.strength = max(min(floor(strength), modem.max_strength), 0)
        return modem.strength
    end,
    isOpen = function(_, modem, port)
        return modem.ports[check_port(port)] == true
    end,
    open = function(_, modem, port)
        port = check_port(port)
        if modem.ports[port] then
            return false
        end
        if modem.open_count >= wireless.MAX_OPEN_PORTS then
            error("too many open ports", 0)
        end
        modem.ports[port] = true
        modem.open_count = modem.open_count + 1
        return true
    end,
    close = function(_, modem, port)
        if port == nil then
            modem.ports, modem.open_count = {}, 0
            return true
        end
        port = check_port(port)
        if not modem.ports[port] then
            return false
        end
        modem.ports[port] = nil
        modem.open_count = modem.open_count - 1
        return true
    end,
    send = function(m, modem, address, port, ...)
        if type(address) ~= "string" then
            error("bad argument #1 (string expected, got " .. type(address) .. ")", 0)
        end
        return transmit(m, modem, address, check_port(port), ...)
    end,
    broadcast = function(m, modem, port, ...)
        return transmit(m, modem, nil, check_port(port), ...)
    end,
    getWakeMessage = function() return nil end,
    setWakeMessage = function() return nil end,
}

components.cards.wireless = function(m, address, slot, card)
    components.add(m, address, "modem", slot, {
        strength = card.range,
        max_strength = card.range,
        ports = {},
        open_count = 0,
        tokens = wireless.PACKET_BURST,
        refilled = get_us_time(),
    })
end
