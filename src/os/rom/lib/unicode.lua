-- UTF-8 strings, like the unicode library of OpenComputers. All characters are one cell wide.
local unicode = {}
local byte, char = string.byte, string.char

-- Byte positions where each character of s starts
local function starts(s)
    local positions = {}
    for i = 1, #s do
        local b = byte(s, i)
        if b < 0x80 or b >= 0xC0 then
            positions[#positions + 1] = i
        end
    end
    return positions
end

function unicode.char(...)
    local parts = {}
    for i, code in ipairs({ ... }) do
        code = math.floor(tonumber(code) or 0)
        if code < 0x80 then
            parts[i] = char(code)
        elseif code < 0x800 then
            parts[i] = char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
        elseif code < 0x10000 then
            parts[i] = char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
        else
            parts[i] = char(0xF0 + math.floor(code / 0x40000) % 8, 0x80 + math.floor(code / 0x1000) % 0x40,
                0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
        end
    end
    return table.concat(parts)
end

function unicode.len(s)
    return #starts(s)
end

function unicode.sub(s, i, j)
    local positions = starts(s)
    local count = #positions
    i = i or 1
    j = j or -1
    if i < 0 then
        i = math.max(count + i + 1, 1)
    elseif i == 0 then
        i = 1
    end
    if j < 0 then
        j = count + j + 1
    elseif j > count then
        j = count
    end
    if i > j then
        return ""
    end
    local last = positions[j + 1] and positions[j + 1] - 1 or #s
    return s:sub(positions[i], last)
end

function unicode.reverse(s)
    local positions, parts = starts(s), {}
    for index = #positions, 1, -1 do
        local last = positions[index + 1] and positions[index + 1] - 1 or #s
        parts[#parts + 1] = s:sub(positions[index], last)
    end
    return table.concat(parts)
end

unicode.lower = string.lower
unicode.upper = string.upper
unicode.wlen = unicode.len
function unicode.isWide() return false end
function unicode.charWidth() return 1 end
function unicode.wtrunc(s, count) return unicode.sub(s, 1, count - 1) end

return unicode
