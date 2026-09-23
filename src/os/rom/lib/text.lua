-- Helpers for text
local text = {}

function text.trim(value)
    local _, leading = value:find("^%s*")
    -- Trailing spaces are found from the end, which takes as long as there are of them
    local last = #value
    while last > leading do
        local b = value:byte(last)
        if b ~= 32 and (b < 9 or b > 13) then
            break
        end
        last = last - 1
    end
    return value:sub(leading + 1, last)
end

function text.padRight(value, length)
    value = tostring(value or "")
    return value .. string.rep(" ", length - #value)
end

function text.padLeft(value, length)
    value = tostring(value or "")
    return string.rep(" ", length - #value) .. value
end

function text.detab(value, width)
    width = width or 8
    return (value:gsub("\t", string.rep(" ", width)))
end

-- Splits a string into words, keeping parts in double quotes together
function text.tokenize(value)
    local tokens, current, quoted, has_token = {}, {}, false, false
    for character in value:gmatch(".") do
        if character == '"' then
            quoted = not quoted
            has_token = true
        elseif character:match("%s") and not quoted then
            if has_token then
                table.insert(tokens, table.concat(current))
                current, has_token = {}, false
            end
        else
            table.insert(current, character)
            has_token = true
        end
    end
    if has_token then
        table.insert(tokens, table.concat(current))
    end
    return tokens
end

return text
