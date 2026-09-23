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

-- Lua 5.1 pattern matching written in Lua, a port of the matcher in lstrlib.c.
-- The string library's matcher runs in C, where the instruction hook that limits computer
-- programs never fires, so a slow pattern could freeze the server. This one runs as Lua
-- code, which the hook can interrupt.

-- The hook doesn't fire in compiled code either, so the matcher is never compiled
local jit = rawget(_G, "jit")
if jit then
    jit.off(true, true)
end

local byte, sub, char = string.byte, string.sub, string.char
local find_plain = string.find
local concat, insert = table.concat, table.insert
local tostring, tonumber, type, error = tostring, tonumber, type, error
local unpack = unpack or table.unpack

local patterns = {}
modular_computers.patterns = patterns

-- Called with the length of each long string gsub is about to make, so the sandbox can
-- refuse ones the program has no memory for
patterns.allocate = function() end

local MAXCAPTURES = 32
local CAP_UNFINISHED = -1
local CAP_POSITION = -2

local PERCENT, LBRACKET, RBRACKET, CARET, DOLLAR = 37, 91, 93, 94, 36
local LPAREN, RPAREN, DOT, MINUS = 40, 41, 46, 45
local STAR, PLUS, QUESTION = 42, 43, 63
local SPECIALS = "[%^%$%*%+%?%.%(%)%[%%%-]"

local function is_lower(c) return c >= 97 and c <= 122 end
local function is_upper(c) return c >= 65 and c <= 90 end
local function is_digit(c) return c >= 48 and c <= 57 end
local function is_alpha(c) return is_lower(c) or is_upper(c) end
local function is_space(c) return c == 32 or (c >= 9 and c <= 13) end
local function is_control(c) return c < 32 or c == 127 end
local function is_punct(c)
    return (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or (c >= 91 and c <= 96) or (c >= 123 and c <= 126)
end
local function is_xdigit(c) return is_digit(c) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70) end

local function match_class(c, cl)
    local lower = is_upper(cl) and cl + 32 or cl
    local res
    if lower == 97 then res = is_alpha(c)            -- a
    elseif lower == 99 then res = is_control(c)      -- c
    elseif lower == 100 then res = is_digit(c)       -- d
    elseif lower == 108 then res = is_lower(c)       -- l
    elseif lower == 112 then res = is_punct(c)       -- p
    elseif lower == 115 then res = is_space(c)       -- s
    elseif lower == 117 then res = is_upper(c)       -- u
    elseif lower == 119 then res = is_alpha(c) or is_digit(c) -- w
    elseif lower == 120 then res = is_xdigit(c)      -- x
    elseif lower == 122 then res = c == 0            -- z
    else return cl == c end
    if is_upper(cl) then
        return not res
    end
    return res
end

-- A match state: the subject, pattern and captures of one match attempt.
-- Like in C, a pattern ends at its first NUL character (%z matches NUL).
local function new_state(s, p)
    local nul = find_plain(p, "\0", 1, true)
    return { s = s, p = p, len = #s, plen = nul and nul - 1 or #p, level = 0, init = {}, caplen = {} }
end

-- Returns the position after the single-character class starting at pattern position pi
local function class_end(ms, pi)
    local p = ms.p
    local c = byte(p, pi)
    pi = pi + 1
    if c == PERCENT then
        if pi > ms.plen then
            error("malformed pattern (ends with '%')", 0)
        end
        return pi + 1
    elseif c == LBRACKET then
        if byte(p, pi) == CARET then
            pi = pi + 1
        end
        repeat
            if pi > ms.plen then
                error("malformed pattern (missing ']')", 0)
            end
            local cc = byte(p, pi)
            pi = pi + 1
            if cc == PERCENT and pi <= ms.plen then
                pi = pi + 1
            end
        until byte(p, pi) == RBRACKET
        return pi + 1
    end
    return pi
end

-- Whether c matches the set [...] from pattern position pi to the closing bracket at ec
local function match_bracket_class(ms, c, pi, ec)
    local p = ms.p
    local sig = true
    if byte(p, pi + 1) == CARET then
        sig = false
        pi = pi + 1
    end
    pi = pi + 1
    while pi < ec do
        local pc = byte(p, pi)
        if pc == PERCENT then
            pi = pi + 1
            if match_class(c, byte(p, pi)) then
                return sig
            end
        elseif byte(p, pi + 1) == MINUS and pi + 2 < ec then
            if pc <= c and c <= byte(p, pi + 2) then
                return sig
            end
            pi = pi + 2
        elseif pc == c then
            return sig
        end
        pi = pi + 1
    end
    return not sig
end

local function single_match(ms, c, pi, ep)
    local pc = byte(ms.p, pi)
    if pc == DOT then
        return true
    elseif pc == PERCENT then
        return match_class(c, byte(ms.p, pi + 1))
    elseif pc == LBRACKET then
        return match_bracket_class(ms, c, pi, ep - 1)
    end
    return pc == c
end

local match

local function match_balance(ms, si, pi)
    if pi + 1 > ms.plen then
        error("unbalanced pattern", 0)
    end
    local s = ms.s
    local b, e = byte(ms.p, pi), byte(ms.p, pi + 1)
    if byte(s, si) ~= b then
        return nil
    end
    local cont = 1
    si = si + 1
    while si <= ms.len do
        local c = byte(s, si)
        if c == e then
            cont = cont - 1
            if cont == 0 then
                return si + 1
            end
        elseif c == b then
            cont = cont + 1
        end
        si = si + 1
    end
    return nil
end

local function max_expand(ms, si, pi, ep)
    local s = ms.s
    local i = 0
    while si + i <= ms.len and single_match(ms, byte(s, si + i), pi, ep) do
        i = i + 1
    end
    while i >= 0 do
        local res = match(ms, si + i, ep + 1)
        if res then
            return res
        end
        i = i - 1
    end
    return nil
end

local function min_expand(ms, si, pi, ep)
    local s = ms.s
    while true do
        local res = match(ms, si, ep + 1)
        if res then
            return res
        elseif si <= ms.len and single_match(ms, byte(s, si), pi, ep) then
            si = si + 1
        else
            return nil
        end
    end
end

local function start_capture(ms, si, pi, what)
    local level = ms.level + 1
    if level > MAXCAPTURES then
        error("too many captures", 0)
    end
    ms.init[level] = si
    ms.caplen[level] = what
    ms.level = level
    local res = match(ms, si, pi)
    if not res then
        ms.level = ms.level - 1
    end
    return res
end

local function end_capture(ms, si, pi)
    local l
    for level = ms.level, 1, -1 do
        if ms.caplen[level] == CAP_UNFINISHED then
            l = level
            break
        end
    end
    if not l then
        error("invalid pattern capture", 0)
    end
    ms.caplen[l] = si - ms.init[l]
    local res = match(ms, si, pi)
    if not res then
        ms.caplen[l] = CAP_UNFINISHED
    end
    return res
end

local function match_capture(ms, si, l)
    l = l - 48
    if l < 1 or l > ms.level or ms.caplen[l] == CAP_UNFINISHED then
        error("invalid capture index", 0)
    end
    local len = ms.caplen[l]
    local init = ms.init[l]
    if ms.len - si + 1 >= len and sub(ms.s, init, init + len - 1) == sub(ms.s, si, si + len - 1) then
        return si + len
    end
    return nil
end

-- Tries to match pattern position pi at subject position si; returns the end of the match
match = function(ms, si, pi)
    local p = ms.p
    while true do
        if pi > ms.plen then
            return si
        end
        local pc = byte(p, pi)
        if pc == LPAREN then
            if byte(p, pi + 1) == RPAREN then
                return start_capture(ms, si, pi + 2, CAP_POSITION)
            end
            return start_capture(ms, si, pi + 1, CAP_UNFINISHED)
        elseif pc == RPAREN then
            return end_capture(ms, si, pi + 1)
        elseif pc == DOLLAR and pi == ms.plen then
            return si == ms.len + 1 and si or nil
        end

        local next_pc = byte(p, pi + 1)
        if pc == PERCENT and next_pc == 98 then -- %b
            si = match_balance(ms, si, pi + 2)
            if not si then
                return nil
            end
            pi = pi + 4
        elseif pc == PERCENT and next_pc == 102 then -- %f
            pi = pi + 2
            if byte(p, pi) ~= LBRACKET then
                error("missing '[' after '%f' in pattern", 0)
            end
            local ep = class_end(ms, pi)
            local previous = si == 1 and 0 or byte(ms.s, si - 1)
            local current = byte(ms.s, si) or 0
            if match_bracket_class(ms, previous, pi, ep - 1) or not match_bracket_class(ms, current, pi, ep - 1) then
                return nil
            end
            pi = ep
        elseif pc == PERCENT and next_pc and is_digit(next_pc) then -- back reference
            si = match_capture(ms, si, next_pc)
            if not si then
                return nil
            end
            pi = pi + 2
        else
            local ep = class_end(ms, pi)
            local m = si <= ms.len and single_match(ms, byte(ms.s, si), pi, ep)
            local ec = byte(p, ep)
            if ec == QUESTION then
                if m then
                    local res = match(ms, si + 1, ep + 1)
                    if res then
                        return res
                    end
                end
                pi = ep + 1
            elseif ec == STAR then
                return max_expand(ms, si, pi, ep)
            elseif ec == PLUS then
                return m and max_expand(ms, si + 1, pi, ep) or nil
            elseif ec == MINUS then
                return min_expand(ms, si, pi, ep)
            elseif not m then
                return nil
            else
                si = si + 1
                pi = ep
            end
        end
    end
end

local function get_capture(ms, i, si, ei)
    if i > ms.level then
        if i == 1 then
            return sub(ms.s, si, ei - 1)
        end
        error("invalid capture index", 0)
    end
    local l = ms.caplen[i]
    if l == CAP_UNFINISHED then
        error("unfinished capture", 0)
    elseif l == CAP_POSITION then
        return ms.init[i]
    end
    return sub(ms.s, ms.init[i], ms.init[i] + l - 1)
end

-- Returns the captures of a match, or the whole match when there are none
local function get_captures(ms, si, ei, whole_if_none)
    local n = (ms.level == 0 and whole_if_none) and 1 or ms.level
    local captures = {}
    for i = 1, n do
        captures[i] = get_capture(ms, i, si, ei)
    end
    return captures, n
end

local function check_string(value, n, name)
    local t = type(value)
    if t == "string" then
        return value
    elseif t == "number" then
        return tostring(value)
    end
    error("bad argument #" .. n .. " to '" .. name .. "' (string expected, got " .. t .. ")", 3)
end

local function start_position(init, len)
    init = tonumber(init) or 1
    init = init >= 0 and init or len + init + 1
    if init < 1 then
        init = 1
    elseif init > len + 1 then
        init = len + 1
    end
    return init
end

local function find_aux(s, p, init, plain, is_find)
    local name = is_find and "find" or "match"
    s = check_string(s, 1, name)
    p = check_string(p, 2, name)
    init = start_position(init, #s)
    if is_find and (plain or not find_plain(p, SPECIALS)) then
        return find_plain(s, p, init, true)
    end
    local ms = new_state(s, p)
    local pi = 1
    local anchor = byte(p, 1) == CARET
    if anchor then
        pi = 2
    end
    local si = init
    repeat
        ms.level = 0
        local ei = match(ms, si, pi)
        if ei then
            if is_find then
                local captures, n = get_captures(ms, si, ei, false)
                return si, ei - 1, unpack(captures, 1, n)
            end
            local captures, n = get_captures(ms, si, ei, true)
            return unpack(captures, 1, n)
        end
        si = si + 1
    until si > ms.len + 1 or anchor
    return nil
end

function patterns.find(s, p, init, plain)
    return find_aux(s, p, init, plain, true)
end

function patterns.match(s, p, init)
    return find_aux(s, p, init, false, false)
end

function patterns.gmatch(s, p)
    s = check_string(s, 1, "gmatch")
    p = check_string(p, 2, "gmatch")
    local si = 1
    return function()
        local ms = new_state(s, p)
        while si <= ms.len + 1 do
            ms.level = 0
            local ei = match(ms, si, 1)
            if ei then
                local start = si
                si = ei == si and ei + 1 or ei
                local captures, n = get_captures(ms, start, ei, true)
                return unpack(captures, 1, n)
            end
            si = si + 1
        end
        return nil
    end
end

local function add_value(ms, parts, si, ei, repl, repl_type)
    local value
    if repl_type == "function" then
        local captures, n = get_captures(ms, si, ei, true)
        value = repl(unpack(captures, 1, n))
    elseif repl_type == "table" then
        value = repl[get_capture(ms, 1, si, ei)]
    else
        local out, size = {}, 0
        local i, len = 1, #repl
        while i <= len do
            local c = byte(repl, i)
            local piece
            if c == PERCENT then
                i = i + 1
                local d = byte(repl, i)
                if d and is_digit(d) then
                    if d == 48 then
                        piece = sub(ms.s, si, ei - 1)
                    else
                        piece = tostring(get_capture(ms, d - 48, si, ei))
                    end
                else
                    -- like the C version, a lone % at the end adds the string terminator
                    piece = d and char(d) or "\0"
                end
            else
                piece = char(c)
            end
            insert(out, piece)
            size = size + #piece
            i = i + 1
        end
        patterns.allocate(size)
        insert(parts, concat(out))
        ms.size = ms.size + size
        return
    end
    if not value then
        value = sub(ms.s, si, ei - 1)
    elseif type(value) == "number" then
        value = tostring(value)
    elseif type(value) ~= "string" then
        error("invalid replacement value (a " .. type(value) .. ")", 0)
    end
    insert(parts, value)
    ms.size = ms.size + #value
end

function patterns.gsub(s, p, repl, max_n)
    s = check_string(s, 1, "gsub")
    p = check_string(p, 2, "gsub")
    local repl_type = type(repl)
    if repl_type == "number" then
        repl, repl_type = tostring(repl), "string"
    elseif repl_type ~= "string" and repl_type ~= "function" and repl_type ~= "table" then
        error("bad argument #3 to 'gsub' (string/function/table expected)", 2)
    end
    max_n = tonumber(max_n) or #s + 1
    local ms = new_state(s, p)
    local pi = 1
    local anchor = byte(p, 1) == CARET
    if anchor then
        pi = 2
    end
    local parts, si, n = {}, 1, 0
    ms.size = 0
    while n < max_n do
        ms.level = 0
        local ei = match(ms, si, pi)
        if ei then
            n = n + 1
            add_value(ms, parts, si, ei, repl, repl_type)
        end
        if ei and ei > si then
            si = ei
        elseif si <= ms.len then
            insert(parts, sub(s, si, si))
            si = si + 1
        else
            break
        end
        if anchor then
            break
        end
    end
    insert(parts, sub(s, si))
    patterns.allocate(ms.size + #s)
    return concat(parts), n
end
