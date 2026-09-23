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

-- The terminal screen of a computer: scrollback, command history and the formspec showing them.
-- Scrollback is stored in node meta "text" and command history in node meta "history".

modular_computers.terminal = {}
local terminal = modular_computers.terminal

terminal.FORMNAME = "modular_computers:computer_formspec"
-- Command output containing the ANSI "erase display" sequence clears the screen
terminal.CLEAR = "\27[2J"
terminal.PROMPT = "$"
terminal.COLUMNS = 80
-- Output is padded with empty rows at the top so that it always sits right above the prompt
terminal.ROWS = 64
terminal.MAX_LINES = 200
terminal.MAX_HISTORY = 50

local BACKGROUND = "#000000"
local FOREGROUND = "#D0D0D0"
local PROMPT_COLOR = "#55FF55"
local INPUT_COLOR = "#FFFFFF"

local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- Every formspec gets a new table name so the client does not restore the old
-- scroll position, which makes the screen jump to the newest output
local shown_count = 0

local function split_lines(text)
    if text ~= "" and string.sub(text, -1) ~= "\n" then
        text = text .. "\n"
    end
    local lines = {}
    for line in string.gmatch(text, "([^\n]*)\n") do
        table.insert(lines, line)
    end
    return lines
end

local function join_lines(lines)
    if #lines == 0 then
        return ""
    end
    return table.concat(lines, "\n") .. "\n"
end

local function wrap_line(line, width, rows)
    local row, length = {}, 0
    for char in string.gmatch(line, UTF8_CHAR) do
        if length == width then
            table.insert(rows, table.concat(row))
            row, length = {}, 0
        end
        table.insert(row, char)
        length = length + 1
    end
    table.insert(rows, table.concat(row))
end

local function mark_private(meta)
    meta:mark_as_private({ "text", "history" })
end

function terminal.get_text(meta)
    return meta:get_string("text")
end

-- Appends command output to the scrollback, handling terminal.CLEAR
function terminal.append(meta, output)
    local text = meta:get_string("text")

    local clear_end
    local search_from = 1
    while true do
        local _, found_end = string.find(output, terminal.CLEAR, search_from, true)
        if not found_end then
            break
        end
        clear_end, search_from = found_end, found_end + 1
    end
    if clear_end then
        text = ""
        output = string.sub(output, clear_end + 1)
    end

    local lines = split_lines(text .. output)
    if #lines > terminal.MAX_LINES then
        lines = { unpack(lines, #lines - terminal.MAX_LINES + 1) }
    end
    meta:set_string("text", join_lines(lines))
    mark_private(meta)
end

function terminal.get_history(meta)
    return split_lines(meta:get_string("history"))
end

function terminal.add_history(meta, command)
    local history = terminal.get_history(meta)
    if history[#history] == command then
        return
    end
    table.insert(history, command)
    if #history > terminal.MAX_HISTORY then
        table.remove(history, 1)
    end
    meta:set_string("history", join_lines(history))
    mark_private(meta)
end

-- Converts scrollback text to screen rows for a player with the given language
function terminal.get_rows(text, lang_code)
    if minetest.get_translated_string then
        text = minetest.get_translated_string(lang_code or "", text)
    end
    -- Remove escape sequences (colors, untranslated strings) and other control characters
    text = text:gsub("\27%(.-%)", ""):gsub("\27.", ""):gsub("\t", "    "):gsub("[%z\1-\8\11-\31\127]", "")

    -- Computers from older versions can have more scrollback than is kept now
    local lines = split_lines(text)
    local rows = {}
    for index = math.max(#lines - terminal.MAX_LINES + 1, 1), #lines do
        wrap_line(lines[index], terminal.COLUMNS, rows)
    end
    return rows
end

function terminal.formspec(text, input, lang_code)
    local rows = terminal.get_rows(text, lang_code)
    local cells = {}
    for _ = #rows + 1, terminal.ROWS do
        table.insert(cells, "")
    end
    for _, row in ipairs(rows) do
        table.insert(cells, minetest.formspec_escape(row))
    end
    shown_count = shown_count + 1

    return table.concat({
        "formspec_version[6]",
        "size[18,11]",
        "no_prepend[]",
        "bgcolor[", BACKGROUND, ";false]",
        "style_type[table;font=mono]",
        "style_type[label;font=mono]",
        "style[terminal_in;border=false;font=mono;textcolor=", INPUT_COLOR, "]",
        "tableoptions[background=", BACKGROUND, ";border=false;highlight=", BACKGROUND,
        ";color=", FOREGROUND, ";highlight_text=", FOREGROUND, "]",
        "tablecolumns[text,padding=0]",
        -- The table reaches past the right edge of the form, which hides its scrollbar.
        -- Selecting the last row scrolls the newest output into view.
        "table[0.35,0.3;18.65,9.7;terminal_out_", shown_count, ";",
        table.concat(cells, ","), ";", #cells, "]",
        "label[0.35,10.375;", minetest.colorize(PROMPT_COLOR, terminal.PROMPT), "]",
        "field_close_on_enter[terminal_in;false]",
        "set_focus[terminal_in;true]",
        "field[0.75,10.05;16.9,0.65;terminal_in;;", minetest.formspec_escape(input or ""), "]",
    })
end
