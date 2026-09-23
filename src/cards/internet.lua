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

-- Internet cards: an "internet" component that makes HTTP requests through the server,
-- like the internet card of OpenComputers.
--
-- Requests only work when the server admin turns them on (modular_computers.internet_enabled)
-- and lets this mod use HTTP (secure.http_mods). Requests to the server itself and to local
-- networks are refused, but redirects are followed by the engine, so a server that needs to
-- be safe from that should list the hosts computers may use in modular_computers.internet_whitelist.

local components = modular_computers.components
local machine = modular_computers.machine

local internet = {}
modular_computers.internet = internet

internet.MAX_REQUESTS = 4
internet.MAX_SIZE = 1024 * 1024
internet.TIMEOUT = 10
internet.METHODS = { GET = true, POST = true, PUT = true, PATCH = true, DELETE = true, HEAD = true }

local function read_whitelist()
    local hosts = {}
    for host in string.gmatch(minetest.settings:get("modular_computers.internet_whitelist") or "", "[^,%s]+") do
        table.insert(hosts, host:lower())
    end
    return hosts
end
internet.whitelist = read_whitelist()

function internet.is_enabled()
    return modular_computers.http ~= nil and minetest.settings:get_bool("modular_computers.internet_enabled", false)
end

-- Returns the IPv4 address a host name stands for, if it is written as a number the way
-- inet_aton reads it ("127.0.0.1", "0x7f.1", "2130706433"...), else nil
local function parse_ipv4(host)
    local parts = {}
    for part in (host .. "."):gmatch("([^.]*)%.") do
        table.insert(parts, part)
    end
    if #parts == 0 or #parts > 4 then
        return nil
    end
    local values = {}
    for i, part in ipairs(parts) do
        local value
        if part:match("^0[xX]%x*$") then
            value = tonumber(part:sub(3), 16) or 0
        elseif part:match("^0[0-7]*$") then
            value = tonumber(part, 8)
        elseif part:match("^%d+$") then
            value = tonumber(part)
        else
            return nil
        end
        values[i] = value
    end
    local address = 0
    for i = 1, #values - 1 do
        if values[i] > 255 then
            return nil
        end
        address = address * 256 + values[i]
    end
    local bits = 8 * (5 - #values)
    if values[#values] >= 2 ^ bits then
        return nil
    end
    return address * 2 ^ bits + values[#values]
end

local PRIVATE_RANGES = {
    { "0.0.0.0", 8 }, { "10.0.0.0", 8 }, { "100.64.0.0", 10 }, { "127.0.0.0", 8 },
    { "169.254.0.0", 16 }, { "172.16.0.0", 12 }, { "192.0.0.0", 24 }, { "192.168.0.0", 16 },
    { "198.18.0.0", 15 }, { "224.0.0.0", 3 },
}

local function is_private(address)
    for _, range in ipairs(PRIVATE_RANGES) do
        local base = parse_ipv4(range[1])
        local size = 2 ^ (32 - range[2])
        if address >= base and address < base + size then
            return true
        end
    end
    return false
end

local function host_allowed(host)
    if #internet.whitelist > 0 then
        for _, allowed in ipairs(internet.whitelist) do
            if host == allowed or (allowed:sub(1, 2) == "*." and host:sub(-#allowed + 1) == allowed:sub(2)) then
                return true
            end
        end
        return false
    end
    if host == "" or host == "localhost" or host:find("^%[") then
        return false
    end
    for _, suffix in ipairs({ ".localhost", ".local", ".internal", ".lan", ".home", ".arpa" }) do
        if host:sub(-#suffix) == suffix then
            return false
        end
    end
    local address = parse_ipv4(host)
    return not (address and is_private(address))
end

-- Checks a URL, returning nil and a reason when computers may not request it
function internet.check_url(url)
    if type(url) ~= "string" or #url > 2048 or url:find("[%z\1-\32\127]") then
        return nil, "invalid address"
    end
    local scheme, authority = url:match("^(%a[%w+.-]*)://([^/?#]*)")
    if not scheme then
        return nil, "invalid address"
    end
    scheme = scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then
        return nil, "unsupported protocol"
    end
    local host = authority:gsub("^.*@", "")
    if not host:find("^%[") then
        host = host:gsub(":%d*$", "")
    end
    host = host:lower():gsub("%.$", "")
    if not host_allowed(host) then
        return nil, "address is not allowed"
    end
    return true
end

local function check_headers(headers)
    local result = {}
    if headers == nil then
        return result
    end
    if type(headers) ~= "table" then
        error("bad argument #3 (table expected, got " .. type(headers) .. ")", 0)
    end
    local count = 0
    for name, value in next, headers do
        count = count + 1
        if count > 32 or type(name) ~= "string" or not name:find("^[%w!#$%%&'*+.^_`|~-]+$")
                or (type(value) ~= "string" and type(value) ~= "number")
                or tostring(value):find("[%z\1-\31\127]") then
            error("invalid header", 0)
        end
        table.insert(result, name .. ": " .. tostring(value))
    end
    return result
end

local function get_request(card, id)
    local request = type(id) == "number" and card.requests[id]
    if not request then
        error("no such request", 0)
    end
    return request
end

components.types.internet = {
    isHttpEnabled = function() return internet.is_enabled() end,
    isTcpEnabled = function() return false end,
    connect = function() return nil, "tcp connections are unavailable" end,
    request = function(m, card, url, data, headers, method)
        if not internet.is_enabled() then
            error("http requests are unavailable", 0)
        end
        local ok, err = internet.check_url(url)
        if not ok then
            error(err, 0)
        end
        if data ~= nil and type(data) ~= "string" then
            error("bad argument #2 (string expected, got " .. type(data) .. ")", 0)
        end
        if data and #data > internet.MAX_SIZE then
            error("request too large", 0)
        end
        local extra_headers = check_headers(headers)
        if method ~= nil and (type(method) ~= "string" or not internet.METHODS[method:upper()]) then
            error("unsupported method", 0)
        end
        method = method and method:upper() or (data and "POST" or "GET")
        local count = 0
        for _ in pairs(card.requests) do
            count = count + 1
        end
        if count >= internet.MAX_REQUESTS then
            error("too many open connections", 0)
        end

        card.next_id = card.next_id + 1
        local id = card.next_id
        local request = { position = 1 }
        card.requests[id] = request
        modular_computers.http.fetch({
            url = url,
            method = method,
            data = data,
            extra_headers = extra_headers,
            timeout = internet.TIMEOUT,
            user_agent = "ModularComputers",
            quiet = true,
        }, function(result)
            if card.closed or card.requests[id] ~= request then
                return
            end
            request.done = true
            if result.succeeded then
                request.code = result.code
                request.data = (result.data or ""):sub(1, internet.MAX_SIZE)
            else
                request.error = result.timeout and "timeout" or "connection failed"
            end
            machine.push_signal(m, "internet_ready", card.address, id)
        end)
        return id
    end,
    finishConnect = function(_, card, id)
        local request = get_request(card, id)
        if request.error then
            return nil, request.error
        end
        return request.done == true
    end,
    response = function(_, card, id)
        local request = get_request(card, id)
        if not request.done or request.error then
            return nil
        end
        return request.code, request.code >= 200 and request.code < 300 and "OK" or "", {}
    end,
    read = function(_, card, id, count)
        local request = get_request(card, id)
        if request.error then
            return nil, request.error
        elseif not request.done then
            return ""
        end
        if request.position > #request.data then
            return nil
        end
        count = type(count) == "number" and math.max(math.floor(math.min(count, 65536)), 1) or 65536
        local chunk = request.data:sub(request.position, request.position + count - 1)
        request.position = request.position + #chunk
        return chunk
    end,
    close = function(_, card, id)
        if type(id) == "number" then
            card.requests[id] = nil
        end
        return true
    end,
}

components.cards.internet = function(m, address, slot)
    components.add(m, address, "internet", slot, {
        requests = {},
        next_id = 0,
        close = function(_, card)
            card.closed = true
            card.requests = {}
        end,
    })
end
