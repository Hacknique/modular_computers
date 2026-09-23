-- Turns values into strings and back
local serialization = {}

local function serialize(value, pretty, seen, indent)
    local t = type(value)
    if t == "string" then
        return string.format("%q", value)
    elseif t == "number" then
        if value ~= value then
            return "0/0"
        elseif value == math.huge then
            return "math.huge"
        elseif value == -math.huge then
            return "-math.huge"
        end
        return string.format("%.17g", value)
    elseif t == "boolean" or t == "nil" then
        return tostring(value)
    elseif t ~= "table" then
        error("can't serialize a " .. t .. " value", 0)
    end
    if seen[value] then
        error("tables with cycles can't be serialized", 0)
    end
    seen[value] = true
    local keys = {}
    for k in next, value do
        table.insert(keys, k)
    end
    local parts = {}
    local inner = indent .. "  "
    local count = #value
    for _, k in ipairs(keys) do
        local key
        if type(k) == "number" and k >= 1 and k <= count and k == math.floor(k) then
            key = ""
        elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
            key = k .. "="
        else
            key = "[" .. serialize(k, pretty, seen, inner) .. "]="
        end
        table.insert(parts, key .. serialize(value[k], pretty, seen, inner))
    end
    seen[value] = nil
    if pretty and #parts > 0 then
        return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. indent .. "}"
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function serialization.serialize(value, pretty)
    return serialize(value, pretty, {}, "")
end

function serialization.unserialize(data)
    if type(data) ~= "string" then
        return nil, "bad argument #1 (string expected)"
    end
    local fn, err = load("return " .. data, "unserialize", "t", { math = { huge = math.huge } })
    if not fn then
        return nil, err
    end
    local ok, result = pcall(fn)
    if not ok then
        return nil, result
    end
    return result
end

return serialization
