-- Components: the parts of the computer and the cards in it
local host = ...
local component = {}
local proxies = {}
local primaries = {}

function component.invoke(address, method, ...)
    return host.invoke(address, method, ...)
end

-- A table of address = type that can also be called to go through it
function component.list(filter, exact)
    local list = host.list(filter, exact)
    local key
    return setmetatable(list, { __call = function()
        key = next(list, key)
        if key then
            return key, list[key]
        end
    end })
end

function component.type(address) return host.type(address) end
function component.slot(address) return host.slot(address) end
function component.methods(address) return host.methods(address) end
function component.fields() return {} end
function component.doc() return nil end

function component.get(prefix, component_type)
    for address in pairs(host.list(component_type, true)) do
        if address:sub(1, #prefix) == prefix then
            return address
        end
    end
    return nil, "no such component"
end

function component.proxy(address)
    local component_type = host.type(address)
    if not component_type then
        return nil, "no such component"
    end
    if proxies[address] then
        return proxies[address]
    end
    local proxy = { address = address, type = component_type, slot = host.slot(address) }
    for name in pairs(host.methods(address)) do
        proxy[name] = function(...)
            return host.invoke(address, name, ...)
        end
    end
    proxies[address] = proxy
    return proxy
end

function component.isAvailable(component_type)
    return next(host.list(component_type, true)) ~= nil
end

function component.getPrimary(component_type)
    local address = primaries[component_type]
    if not (address and host.type(address)) then
        address = next(host.list(component_type, true))
        primaries[component_type] = address
    end
    if not address then
        error("no primary '" .. tostring(component_type) .. "' available", 2)
    end
    return component.proxy(address)
end

function component.setPrimary(component_type, address)
    primaries[component_type] = address
end

-- component.gpu and so on give the primary component of that type
return setmetatable(component, { __index = function(_, key)
    if type(key) == "string" and component.isAvailable(key) then
        return component.getPrimary(key)
    end
end })
