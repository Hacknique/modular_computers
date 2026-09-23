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

-- Rewrites the source code of programs so that each chain of concatenations, a .. b .. c,
-- becomes a call, cat(a, b, c). Concatenation runs inside the Lua VM, where nothing can see
-- how long the result will be, so a program could make a string of gigabytes between two
-- checks of its memory. The function the calls go to checks first.
--
-- Programs are parsed with Lua 5.1's grammar as LuaJIT reads it, only to find the operands
-- of each chain. The code is otherwise unchanged, and stays on the same lines. Only code
-- that Lua has already compiled is rewritten, so it is known to be valid. Tokens are split
-- the way LuaJIT's lexer (lj_lex.c) splits them: a difference could hide a .. from here.

-- Programs can make this take long, so the hook must be able to stop it
local jit = rawget(_G, "jit")
if jit then
    jit.off(true, true)
end

local find, sub, byte, match = string.find, string.sub, string.byte, string.match
local concat = table.concat

local rewrite = {}
modular_computers.rewrite = rewrite

-- Called now and then while rewriting long code, so machines can pause it
rewrite.pause = function() end
local STEPS_PER_PAUSE = 256

local KEYWORDS = {}
for word in string.gmatch("and break do else elseif end false for function if in local nil not or repeat "
        .. "return then true until while", "%a+") do
    KEYWORDS[word] = true
end

-- Priorities of binary operators, from lparser.c: left, right
local LEFT = { ["+"] = 6, ["-"] = 6, ["*"] = 7, ["/"] = 7, ["%"] = 7, ["^"] = 10, [".."] = 5,
    ["=="] = 3, ["~="] = 3, ["<"] = 3, ["<="] = 3, [">"] = 3, [">="] = 3, ["and"] = 2, ["or"] = 1 }
local RIGHT = { ["+"] = 6, ["-"] = 6, ["*"] = 7, ["/"] = 7, ["%"] = 7, ["^"] = 9, [".."] = 4,
    ["=="] = 3, ["~="] = 3, ["<"] = 3, ["<="] = 3, [">"] = 3, [">="] = 3, ["and"] = 2, ["or"] = 1 }
local UNARY_PRIORITY = 8
local CONCAT_PRIORITY = 5

local BLOCK_ENDS = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true, eof = true }

-- Splits source into tokens: their types ("name", "number", "string", keywords and symbols),
-- where each starts and ends, the words of names by token, and the set of names used.
-- Returns nil for code Lua wouldn't read.
local function tokenize(source)
    local types, starts, ends, words, names = {}, {}, {}, {}, {}
    local position, count, length = 1, 0, #source
    while true do
        -- Whitespace and comments
        while true do
            local _, space_end = find(source, "^[ \t\r\n\f\v]+", position)
            if space_end then
                position = space_end + 1
            end
            if sub(source, position, position + 1) ~= "--" then
                break
            end
            local level = match(source, "^%[(=*)%[", position + 2)
            if level then
                local _, close = find(source, "]" .. level .. "]", position + 4 + #level, true)
                if not close then
                    return nil
                end
                position = close + 1
            else
                -- A line comment, which ends at \n or \r
                local line_end = find(source, "[\n\r]", position + 2)
                position = line_end or length + 1
            end
        end
        if position > length then
            break
        end
        if count > 0 and count % STEPS_PER_PAUSE == 0 then
            rewrite.pause()
        end

        count = count + 1
        starts[count] = position
        local c = byte(source, position)
        local token_end, token_type
        if (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or c == 95 or c >= 128 then
            -- A name or keyword, which may contain any byte above 127, like in LuaJIT
            local _, name_end = find(source, "^[%w_\128-\255]*", position + 1)
            token_end = name_end
            local word = sub(source, position, token_end)
            token_type = KEYWORDS[word] and word or "name"
            if token_type == "name" then
                names[word] = true
                words[count] = word
            end
        elseif (c >= 48 and c <= 57) or (c == 46 and find(source, "^%d", position + 1)) then
            -- A number: digits, letters (hex, exponents, suffixes like LL), dots, and a sign
            -- after the exponent letter, which is p in hex numbers and e in others
            local exponent = find(source, "^0[xX]", position) and 112 or 101
            token_end = position
            while true do
                local _, part_end = find(source, "^[%w_%.\128-\255]*", token_end + 1)
                token_end = part_end
                local last = byte(source, token_end)
                local next_char = byte(source, token_end + 1)
                if (next_char == 43 or next_char == 45) and (last == exponent or last == exponent - 32) then
                    token_end = token_end + 1
                else
                    break
                end
            end
            token_type = "number"
        elseif c == 34 or c == 39 then
            -- A quoted string
            local quote = c == 34 and '"' or "'"
            local search = position + 1
            while true do
                local found = find(source, "[\\\n\r" .. quote .. "]", search)
                if not found then
                    return nil
                end
                local found_char = byte(source, found)
                if found_char == 92 then
                    local escaped = byte(source, found + 1)
                    if escaped == 122 then
                        -- \z skips the whitespace after it
                        local _, space_end = find(source, "^[ \t\r\n\f\v]*", found + 2)
                        search = space_end + 1
                    elseif escaped == 13 or escaped == 10 then
                        -- An escaped line break, which can be \r\n or \n\r
                        local following = byte(source, found + 2)
                        search = found + 2
                        if (following == 13 or following == 10) and following ~= escaped then
                            search = search + 1
                        end
                    else
                        search = found + 2
                    end
                elseif found_char == c then
                    token_end = found
                    break
                else
                    return nil
                end
            end
            token_type = "string"
        elseif c == 91 and find(source, "^%[=*%[", position) then
            -- A long string
            local level = match(source, "^%[(=*)%[", position)
            local _, close = find(source, "]" .. level .. "]", position + 2 + #level, true)
            if not close then
                return nil
            end
            token_end = close
            token_type = "string"
        else
            local three, two = sub(source, position, position + 2), sub(source, position, position + 1)
            if three == "..." then
                token_type, token_end = "...", position + 2
            elseif two == ".." or two == "==" or two == "~=" or two == "<=" or two == ">=" or two == "::" then
                token_type, token_end = two, position + 1
            else
                token_type, token_end = sub(source, position, position), position
            end
        end
        types[count] = token_type
        ends[count] = token_end
        position = token_end + 1
    end
    types[count + 1] = "eof"
    return types, starts, ends, words, names
end

-- Finds the chains of concatenations in tokens, given the token types and the text of names.
-- Returns what goes before and after tokens and what replaces the .. between operands, by
-- token index.
local function find_chains(types, names, cat_name)
    local p = 1
    local prefix, suffix, replace = {}, {}, {}
    local expr, block

    local function explist()
        expr(0)
        while types[p] == "," do
            p = p + 1
            expr(0)
        end
    end

    local function table_constructor()
        p = p + 1 -- {
        while types[p] ~= "}" and types[p] ~= "eof" do
            if types[p] == "[" then
                p = p + 1
                expr(0)
                p = p + 2 -- ] =
                expr(0)
            elseif types[p] == "name" and types[p + 1] == "=" then
                p = p + 2
                expr(0)
            else
                expr(0)
            end
            if types[p] == "," or types[p] == ";" then
                p = p + 1
            end
        end
        p = p + 1 -- }
    end

    local function function_body()
        p = p + 1 -- (
        while types[p] ~= ")" and types[p] ~= "eof" do
            p = p + 1
        end
        p = p + 1 -- )
        block()
        p = p + 1 -- end
    end

    local function call_arguments()
        local t = types[p]
        if t == "string" then
            p = p + 1
        elseif t == "{" then
            table_constructor()
        else
            p = p + 1 -- (
            if types[p] ~= ")" then
                explist()
            end
            p = p + 1 -- )
        end
    end

    local function suffixed_expr()
        if types[p] == "(" then
            p = p + 1
            expr(0)
            p = p + 1 -- )
        else
            p = p + 1 -- name
        end
        while true do
            local t = types[p]
            if t == "." then
                p = p + 2
            elseif t == "[" then
                p = p + 1
                expr(0)
                p = p + 1 -- ]
            elseif t == ":" then
                p = p + 2
                call_arguments()
            elseif t == "(" or t == "string" or t == "{" then
                call_arguments()
            else
                break
            end
        end
    end

    local function simple_expr()
        local t = types[p]
        if t == "number" or t == "string" or t == "nil" or t == "true" or t == "false" or t == "..." then
            p = p + 1
        elseif t == "{" then
            table_constructor()
        elseif t == "function" then
            p = p + 1
            function_body()
        else
            suffixed_expr()
        end
    end

    function expr(limit)
        local start = p
        local t = types[p]
        if t == "not" or t == "-" or t == "#" then
            p = p + 1
            expr(UNARY_PRIORITY)
        else
            simple_expr()
        end
        while true do
            local op = types[p]
            local priority = LEFT[op]
            if not priority or priority <= limit then
                break
            end
            if op == ".." then
                -- The operands of a chain bind tighter than .. The space keeps the call from
                -- joining a word right before it, like the and in `x and"a"..b`, and the
                -- parentheses keep `return a .. b` from becoming a tail call, which would
                -- leave the program out of the traceback of errors.
                prefix[start] = (prefix[start] or "") .. " (" .. cat_name .. "("
                repeat
                    replace[p] = ","
                    p = p + 1
                    expr(CONCAT_PRIORITY)
                until types[p] ~= ".."
                suffix[p - 1] = (suffix[p - 1] or "") .. "))"
            else
                p = p + 1
                expr(RIGHT[op])
            end
        end
    end

    local function statement()
        local t = types[p]
        if t == ";" then
            p = p + 1
        elseif t == "if" then
            p = p + 1
            expr(0)
            p = p + 1 -- then
            block()
            while types[p] == "elseif" do
                p = p + 1
                expr(0)
                p = p + 1 -- then
                block()
            end
            if types[p] == "else" then
                p = p + 1
                block()
            end
            p = p + 1 -- end
        elseif t == "while" then
            p = p + 1
            expr(0)
            p = p + 1 -- do
            block()
            p = p + 1 -- end
        elseif t == "do" then
            p = p + 1
            block()
            p = p + 1 -- end
        elseif t == "for" then
            p = p + 1
            if types[p + 1] == "=" then
                p = p + 2
                explist()
            else
                while types[p] ~= "in" and types[p] ~= "eof" do
                    p = p + 1
                end
                p = p + 1 -- in
                explist()
            end
            p = p + 1 -- do
            block()
            p = p + 1 -- end
        elseif t == "repeat" then
            p = p + 1
            block()
            p = p + 1 -- until
            expr(0)
        elseif t == "function" then
            p = p + 2 -- function name
            while types[p] == "." or types[p] == ":" do
                p = p + 2
            end
            function_body()
        elseif t == "local" then
            p = p + 1
            if types[p] == "function" then
                p = p + 2 -- function name
                function_body()
            else
                p = p + 1
                while types[p] == "," do
                    p = p + 2
                end
                if types[p] == "=" then
                    p = p + 1
                    explist()
                end
            end
        elseif t == "return" then
            p = p + 1
            if not BLOCK_ENDS[types[p]] and types[p] ~= ";" then
                explist()
            end
        elseif t == "break" then
            p = p + 1
        elseif t == "::" then
            p = p + 3 -- :: name ::
        elseif t == "name" and names[p] == "goto" and types[p + 1] == "name" then
            -- goto is only a statement when a name follows it
            p = p + 2
        else
            suffixed_expr()
            if types[p] == "=" or types[p] == "," then
                while types[p] == "," do
                    p = p + 1
                    suffixed_expr()
                end
                p = p + 1 -- =
                explist()
            end
        end
    end

    local statements = 0
    function block()
        while not BLOCK_ENDS[types[p]] do
            local before = p
            statements = statements + 1
            if statements % STEPS_PER_PAUSE == 0 then
                rewrite.pause()
            end
            statement()
            if p == before then
                -- Never stop moving through the code
                error("unexpected " .. tostring(types[p]), 0)
            end
        end
    end

    block()
    if types[p] ~= "eof" then
        error("unexpected " .. tostring(types[p]), 0)
    end
    return prefix, suffix, replace
end

-- Returns source with each chain of concatenations turned into a call to the function named
-- cat_name, or nil and an error. For tests, separator replaces the commas between operands:
-- with an empty cat_name and "..", the code means the same as source.
function rewrite.concatenations(source, cat_name, separator)
    local types, starts, ends, words, names = tokenize(source)
    if not types then
        return nil, "unreadable code"
    end
    if names[cat_name] then
        return nil, "the code uses the name " .. cat_name
    end
    local ok, prefix, suffix, replace = pcall(find_chains, types, words, cat_name)
    if not ok then
        if type(prefix) ~= "string" then
            -- Not a parse error, like the sandbox stopping the program
            error(prefix, 0)
        end
        return nil, prefix
    end
    for i = 1, #starts do
        if types[i] == ".." and not replace[i] then
            return nil, "unsupported code"
        end
    end
    local out, copied = {}, 1
    for i = 1, #starts do
        if i % STEPS_PER_PAUSE == 0 then
            rewrite.pause()
        end
        out[#out + 1] = sub(source, copied, starts[i] - 1)
        if prefix[i] then
            out[#out + 1] = prefix[i]
        end
        out[#out + 1] = replace[i] and (separator or replace[i]) or sub(source, starts[i], ends[i])
        if suffix[i] then
            out[#out + 1] = suffix[i]
        end
        copied = ends[i] + 1
    end
    out[#out + 1] = sub(source, copied)
    return concat(out)
end
